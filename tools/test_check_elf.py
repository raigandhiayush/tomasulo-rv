#!/usr/bin/env python3
"""Unit test suite for check_elf.py ELF validation and decoder compliance."""
import os, random, shutil, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_elf  # noqa: E402

# xor program from mem_generator/imem_dmem/code.dis (gcc 13, -march=rv32i)
XOR = [0xfe010113, 0x00112e23, 0x00812c23, 0x02010413, 0x00a00793, 0xfef42623,
       0x00300793, 0xfef42423, 0xfec42703, 0xfe842783, 0x00f747b3, 0xfef42223,
       0xfe442783, 0x00078513, 0x01c12083, 0x01812403, 0x02010113, 0x00008067]


def make_elf(words, relocs=(), data_bytes=0, main_off=0, flags=0, machine=243):
    text = b"".join(struct.pack("<I", w) for w in words)
    names = [b"", b".text", b".symtab", b".strtab", b".shstrtab"]
    if relocs:
        names.append(b".rela.text")
    if data_bytes:
        names.append(b".data")
    shstr = b"\0".join(names) + b"\0"
    name_off = {n: shstr.index(n + b"\0") if n else 0 for n in names}
    strtab = b"\0main\0"
    symtab = b"\0" * 16 + struct.pack("<IIIBBH", 1, main_off, 4 * len(words), 0x12, 0, 1)
    rela = b"".join(struct.pack("<IIi", off, (1 << 8) | t, 0) for off, t in relocs)
    data = b"\0" * data_bytes
    blobs = [(".text", text), (".symtab", symtab), (".strtab", strtab), (".shstrtab", shstr)]
    if relocs:
        blobs.append((".rela.text", rela))
    if data_bytes:
        blobs.append((".data", data))
    body, offs = b"", {}
    for n, b in blobs:
        offs[n] = 52 + len(body)
        body += b + b"\0" * (-len(b) % 4)
    shoff = 52 + len(body)
    sh = [b"\0" * 40]
    idx = {".text": 1, ".symtab": 2, ".strtab": 3, ".shstrtab": 4}

    def hdr(n, typ, fl, link=0, info=0, ent=0, align=4):
        size = len(dict(blobs)[n])
        return struct.pack("<IIIIIIIIII", name_off[n.encode()], typ, fl, 0, offs[n], size, link, info, align, ent)
    sh.append(hdr(".text", 1, 0x6))
    sh.append(hdr(".symtab", 2, 0, link=3, info=1, ent=16))
    sh.append(hdr(".strtab", 3, 0))
    sh.append(hdr(".shstrtab", 3, 0))
    if relocs:
        sh.append(hdr(".rela.text", 4, 0x40, link=2, info=1, ent=12))
    if data_bytes:
        sh.append(hdr(".data", 1, 0x3))
    ehdr = b"\x7fELF" + bytes([1, 1, 1, 0]) + b"\0" * 8 + struct.pack(
        "<HHIIIIIHHHHHH", 1, machine, 1, 0, 0, shoff, flags, 52, 0, 0, 40, len(sh), idx[".shstrtab"])
    return ehdr + body + b"".join(sh)


def run_case(tmp, name, blob, expect_status, expect_text=None):
    path = os.path.join(tmp, name + ".elf")
    open(path, "wb").write(blob)
    p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "check_elf.py"), path],
                       capture_output=True, text=True)
    ok = p.returncode == expect_status and (expect_text is None or expect_text in p.stdout)
    if not ok:
        print(f"TEST_FAIL check_elf case {name}: exit {p.returncode} (expected {expect_status}), output:\n{p.stdout}")
    return ok


def decoder_crosscheck(tmp):
    """Every opcode x funct3 x funct7 corner plus random words vs ooo_decode.illegal."""
    if not shutil.which("iverilog"):
        print("decoder cross-check skipped (no iverilog)")
        return 0, 0
    root = os.path.join(HERE, "..")
    rng = random.Random(2026)
    words = []
    for op in range(128):
        for f3 in range(8):
            for f7 in (0x00, 0x01, 0x20, 0x21, 0x40, 0x7F):
                words.append((f7 << 25) | (rng.getrandbits(13) << 12 & 0x01F00000) | (f3 << 12) | op
                             | (rng.getrandbits(5) << 15) | (rng.getrandbits(5) << 7))
    words += [rng.getrandbits(32) for _ in range(20000)]
    vec = os.path.join(tmp, "words.hex")
    open(vec, "w").write("".join(f"{w:08x}\n" for w in words))
    tb = os.path.join(tmp, "tb_dec.v")
    open(tb, "w").write(f"""`include "ooo_defs.vh"
module tb_dec; reg [31:0] w [0:{len(words) - 1}]; reg [31:0] inst; wire ill; integer i;
ooo_decode d(.inst(inst), .pc(32'd0), .illegal(ill), .cls(), .funct3(), .sub(), .rs1(), .rs2(), .rd(),
 .uses_rs1(), .uses_rs2(), .writes_rd(), .use_imm(), .imm(), .pre_value(), .is_jal(), .is_jalr(),
 .is_branch(), .br_target());
initial begin $readmemh("{vec}", w); for (i = 0; i < {len(words)}; i = i + 1) begin inst = w[i]; #1 $display("%0d", ill); end end
endmodule
""")
    out = os.path.join(tmp, "tb_dec")
    subprocess.run(["iverilog", "-g2012", "-I", os.path.join(root, "ooo_rtl"), "-o", out,
                    os.path.join(root, "ooo_rtl", "ooo_decode.v"), tb], check=True)
    res = subprocess.run(["vvp", "-n", out], capture_output=True, text=True, check=True).stdout.split()
    bad = 0
    for w, r in zip(words, res):
        if (r == "0") != check_elf.legal(w):
            bad += 1
            if bad <= 5:
                print(f"TEST_FAIL check_elf legal({w:08x}) = {check_elf.legal(w)}, ooo_decode illegal = {r}")
    if len(res) != len(words):
        bad += 1
        print(f"TEST_FAIL check_elf decoder harness printed {len(res)} of {len(words)} results")
    return len(words), bad


def main():
    tmp = tempfile.mkdtemp()
    cases = [
        ("good_xor", make_elf(XOR), 0, "OK (18 instructions"),
        ("good_rv32m", make_elf(XOR[:4] + [0x02f707b3, 0x02f747b3] + XOR[4:]), 0, "OK"),   # mul, div
        ("reloc_call", make_elf(XOR, relocs=[(0x10, 19), (0x10, 51)]), 1, "R_RISCV_CALL_PLT x1"),
        ("reloc_branch", make_elf(XOR, relocs=[(0x20, 16)]), 1, "R_RISCV_BRANCH"),
        ("auipc", make_elf(XOR[:3] + [0x00000097] + XOR[3:]), 1, "not a supported"),
        ("ecall", make_elf(XOR + [0x00000073]), 1, "not a supported"),
        ("fence", make_elf(XOR + [0x0ff0000f]), 1, "not a supported"),
        ("bad_srli_f7", make_elf(XOR + [0x4000d093 | (1 << 25)]), 1, "not a supported"),
        ("globals", make_elf(XOR, data_bytes=8), 1, "writable data"),
        ("rvc_flag", make_elf(XOR, flags=0x1), 1, "compressed"),
        ("hard_float", make_elf(XOR, flags=0x4), 1, "hard-float"),
        ("main_not_first", make_elf(XOR, main_off=8), 1, "offset 0"),
        ("wrong_machine", make_elf(XOR, machine=62), 1, "not RISC-V"),
        ("not_elf", b"hello world, not an elf", 2, "not an ELF"),
    ]
    n = bad = 0
    for name, blob, st, txt in cases:
        n += 1
        bad += not run_case(tmp, name, blob, st, txt)
    m, mbad = decoder_crosscheck(tmp)
    shutil.rmtree(tmp)
    print(f"{n} ELF cases, {m} decoder cross-check words")
    if bad or mbad:
        print(f"TEST_FAIL check_elf {bad} case failures, {mbad} decoder mismatches")
        return 1
    print(f"TEST_PASS check_elf {n + m}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
