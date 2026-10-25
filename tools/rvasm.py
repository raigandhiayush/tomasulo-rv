#!/usr/bin/env python3
"""Minimal RV32IM assembler generating imem.hex memory initialization files."""
import re, sys, os

ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1"] + \
      [f"a{i}" for i in range(8)] + [f"s{i}" for i in range(2, 12)] + \
      [f"t{i}" for i in range(3, 7)]
REG = {n: i for i, n in enumerate(ABI)}
REG.update({f"x{i}": i for i in range(32)})
REG["fp"] = 8

R_OPS = {  # name: (funct7, funct3)
    "add": (0x00, 0), "sub": (0x20, 0), "sll": (0x00, 1), "slt": (0x00, 2),
    "sltu": (0x00, 3), "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5),
    "or": (0x00, 6), "and": (0x00, 7),
    "mul": (0x01, 0), "mulh": (0x01, 1), "mulhsu": (0x01, 2), "mulhu": (0x01, 3),
    "div": (0x01, 4), "divu": (0x01, 5), "rem": (0x01, 6), "remu": (0x01, 7)}
I_OPS = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SH_OPS = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
LD_OPS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
ST_OPS = {"sb": 0, "sh": 1, "sw": 2}
BR_OPS = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}


class AsmError(Exception):
    pass


def reg(s):
    s = s.strip()
    if s not in REG:
        raise AsmError(f"bad register '{s}'")
    return REG[s]


def num(s):
    return int(s.strip(), 0)


def check(v, bits, signed=True, what="immediate"):
    lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if signed else (0, (1 << bits) - 1)
    if not lo <= v <= hi:
        raise AsmError(f"{what} {v} out of range [{lo}, {hi}]")
    return v & ((1 << bits) - 1)


def li_parts(v):
    """Split a 32-bit constant into (upper20, lower12) so lui+addi rebuilds it."""
    v &= 0xFFFFFFFF
    lo = v & 0xFFF
    if lo & 0x800:
        lo -= 0x1000
    hi = ((v - lo) >> 12) & 0xFFFFF
    return hi, lo


def size_of(op, args):
    if op == "li":
        v = num(args[1])
        return 4 if -2048 <= v <= 2047 else 8
    return 4


def enc_r(f7, rs2, rs1, f3, rd, opc=0x33):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opc


def enc_i(imm, rs1, f3, rd, opc):
    return (check(imm, 12) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opc


def enc_s(imm, rs2, rs1, f3):
    i = check(imm, 12)
    return ((i >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((i & 0x1F) << 7) | 0x23


def enc_b(off, rs2, rs1, f3):
    if off & 1:
        raise AsmError(f"branch offset {off} is odd")
    i = check(off, 13, what="branch offset")
    return (((i >> 12) & 1) << 31) | (((i >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | (((i >> 1) & 0xF) << 8) | (((i >> 11) & 1) << 7) | 0x63


def enc_j(off, rd):
    if off & 1:
        raise AsmError(f"jump offset {off} is odd")
    i = check(off, 21, what="jump offset")
    return (((i >> 20) & 1) << 31) | (((i >> 1) & 0x3FF) << 21) | (((i >> 11) & 1) << 20) | \
           (((i >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def mem_arg(s):
    m = re.fullmatch(r"\s*(-?(?:0x[0-9a-fA-F]+|\d+))?\s*\(\s*(\w+)\s*\)\s*", s)
    if not m:
        raise AsmError(f"bad memory operand '{s}'")
    return num(m.group(1) or "0"), reg(m.group(2))


def target(s, labels, pc):
    s = s.strip()
    return labels[s] - pc if s in labels else num(s)


def encode(op, a, labels, pc):
    if op in R_OPS:
        f7, f3 = R_OPS[op]
        return [enc_r(f7, reg(a[2]), reg(a[1]), f3, reg(a[0]))]
    if op in I_OPS:
        return [enc_i(num(a[2]), reg(a[1]), I_OPS[op], reg(a[0]), 0x13)]
    if op in SH_OPS:
        f7, f3 = SH_OPS[op]
        return [enc_r(f7, check(num(a[2]), 5, False, "shift amount"), reg(a[1]), f3, reg(a[0]), 0x13)]
    if op in LD_OPS:
        off, rs1 = mem_arg(a[1])
        return [enc_i(off, rs1, LD_OPS[op], reg(a[0]), 0x03)]
    if op in ST_OPS:
        off, rs1 = mem_arg(a[1])
        return [enc_s(off, reg(a[0]), rs1, ST_OPS[op])]
    if op in BR_OPS:
        return [enc_b(target(a[2], labels, pc), reg(a[1]), reg(a[0]), BR_OPS[op])]
    if op == "lui":
        return [(check(num(a[1]), 20, False, "lui immediate") << 12) | (reg(a[0]) << 7) | 0x37]
    if op == "jal":
        if len(a) == 1:
            a = ["ra"] + a
        return [enc_j(target(a[1], labels, pc), reg(a[0]))]
    if op == "jalr":
        if len(a) == 1:
            return [enc_i(0, reg(a[0]), 0, 1, 0x67)]
        if len(a) == 2:                                   # jalr rd, off(rs1)
            off, rs1 = mem_arg(a[1])
            return [enc_i(off, rs1, 0, reg(a[0]), 0x67)]
        return [enc_i(num(a[2]), reg(a[1]), 0, reg(a[0]), 0x67)]
    # pseudo-instructions
    if op == "nop":
        return [enc_i(0, 0, 0, 0, 0x13)]
    if op == "mv":
        return [enc_i(0, reg(a[1]), 0, reg(a[0]), 0x13)]
    if op == "li":
        rd, v = reg(a[0]), num(a[1])
        if -2048 <= v <= 2047:
            return [enc_i(v, 0, 0, rd, 0x13)]
        hi, lo = li_parts(v)
        return [(hi << 12) | (rd << 7) | 0x37, enc_i(lo, rd, 0, rd, 0x13)]
    if op == "j":
        return [enc_j(target(a[0], labels, pc), 0)]
    if op == "jr":
        return [enc_i(0, reg(a[0]), 0, 0, 0x67)]
    if op == "ret":
        return [enc_i(0, 1, 0, 0, 0x67)]
    if op == "beqz":
        return [enc_b(target(a[1], labels, pc), 0, reg(a[0]), 0)]
    if op == "bnez":
        return [enc_b(target(a[1], labels, pc), 0, reg(a[0]), 1)]
    if op == ".word":
        return [num(a[0]) & 0xFFFFFFFF]
    raise AsmError(f"unsupported instruction '{op}'")


def parse(text):
    """Yield (line_no, label_list, op, args) for each source line."""
    for n, line in enumerate(text.splitlines(), 1):
        line = re.split(r"#|//", line, 1)[0].strip()
        labels = []
        while True:
            m = re.match(r"([A-Za-z_.][\w.]*)\s*:\s*(.*)", line)
            if not m:
                break
            labels.append(m.group(1))
            line = m.group(2)
        if not line:
            yield n, labels, None, []
            continue
        parts = line.split(None, 1)
        args = [x.strip() for x in parts[1].split(",")] if len(parts) > 1 else []
        yield n, labels, parts[0].lower(), args


def assemble(text):
    lines = list(parse(text))
    labels, pc = {}, 0
    for n, labs, op, args in lines:
        for lab in labs:
            if lab in labels:
                raise AsmError(f"line {n}: label '{lab}' defined twice")
            labels[lab] = pc
        if op:
            pc += size_of(op, args)
    words, pc = [], 0
    for n, _, op, args in lines:
        if not op:
            continue
        try:
            w = encode(op, args, labels, pc)
        except (AsmError, ValueError, IndexError, KeyError) as e:
            raise AsmError(f"line {n}: {op} {', '.join(args)}: {e}")
        words += w
        pc += 4 * len(w)
    return words, labels


def to_hex(words, ramsize=4096):
    if 4 * len(words) > ramsize:
        raise AsmError(f"program is {4 * len(words)} bytes, instr_mem holds {ramsize}")
    out = []
    for i in range(ramsize // 4):
        w = words[i] if i < len(words) else 0
        out.append(f"{w:08x} // 32'h{4 * i:08x}")
    return "\n".join(out) + "\n"


def selftest(dis_path):
    """Assemble every instruction of an objdump listing; compare with gcc's encoding."""
    n = bad = 0
    for line in open(dis_path):
        m = re.match(r"\s*([0-9a-f]+):\s+([0-9a-f]{8})\s+(\S+)\s*(.*)", line)
        if not m:
            continue
        pc, ref, op, rest = int(m.group(1), 16), int(m.group(2), 16), m.group(3), m.group(4)
        rest = re.split(r"\s+<|#", rest)[0].strip()
        args = [x.strip() for x in rest.split(",")] if rest else []
        if op in BR_OPS or op in ("j", "jal", "beqz", "bnez"):
            args[-1] = str(int(args[-1], 16) - pc)        # objdump prints absolute targets
        got = encode(op, args, {}, pc)
        n += 1
        if got != [ref]:
            bad += 1
            print(f"MISMATCH {pc:#x} {op} {rest}: gcc {ref:08x} rvasm {' '.join(f'{w:08x}' for w in got)}")
    return n, bad


def main(argv):
    if argv[1:2] == ["--selftest"]:
        here = os.path.dirname(os.path.abspath(__file__))
        dis = argv[2] if len(argv) > 2 else os.path.join(here, "..", "mem_generator", "imem_dmem", "code.dis")
        n, bad = selftest(dis)
        print(f"rvasm selftest: {n} instructions from {os.path.normpath(dis)}, {bad} mismatches")
        print("TEST_PASS rvasm %d" % n if n and not bad else "TEST_FAIL rvasm %d mismatches" % bad)
        return 0 if n and not bad else 1
    if len(argv) != 4 or argv[2] != "-o":
        print(__doc__)
        return 2
    try:
        words, _ = assemble(open(argv[1]).read())
    except AsmError as e:
        print(f"{argv[1]}: {e}", file=sys.stderr)
        return 1
    with open(argv[3], "w") as f:
        f.write(to_hex(words))
    print(f"{argv[1]}: {len(words)} words -> {argv[3]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
