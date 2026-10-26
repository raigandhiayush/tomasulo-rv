#!/usr/bin/env python3
"""Instruction-level RV32IM reference model and commit-trace generator for TOMA-RV."""
import argparse, sys

M32 = 0xFFFFFFFF
MMIO_RESULT, MMIO_DONE, MMIO_SW = 0x10000000, 0x10000004, 0x10000008


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def s32(v):
    return sx(v, 32)


def load_hex(path):
    words = []
    for line in open(path):
        tok = line.split("//")[0].split()
        for t in tok:
            if t.startswith("@"):
                raise SystemExit(f"{path}: address records (@) are not supported")
            words.append(int(t, 16) if "x" not in t.lower() else 0)
    words += [0] * (1024 - len(words))
    return words[:1024]


def muldiv(f3, a, b):
    sa, sb = s32(a), s32(b)
    if f3 == 0: return (a * b) & M32
    if f3 == 1: return ((sa * sb) >> 32) & M32
    if f3 == 2: return ((sa * b) >> 32) & M32
    if f3 == 3: return ((a * b) >> 32) & M32
    if f3 == 4:
        if b == 0: return M32
        if a == 0x80000000 and b == M32: return a
        q = abs(sa) // abs(sb)
        return (-q if (sa < 0) != (sb < 0) else q) & M32
    if f3 == 5: return M32 if b == 0 else a // b
    if f3 == 6:
        if b == 0: return a
        if a == 0x80000000 and b == M32: return 0
        r = abs(sa) % abs(sb)
        return (-r if sa < 0 else r) & M32
    return a if b == 0 else a % b


def alu(f3, alt, a, b):
    sh = b & 31
    if f3 == 0: return (a - b if alt else a + b) & M32
    if f3 == 1: return (a << sh) & M32
    if f3 == 2: return int(s32(a) < s32(b))
    if f3 == 3: return int(a < b)
    if f3 == 4: return a ^ b
    if f3 == 5: return (s32(a) >> sh) & M32 if alt else a >> sh
    if f3 == 6: return a | b
    return a & b


class Model:
    def __init__(self, imem, sw=0):
        self.imem, self.sw = imem, sw & 0xFFFF
        self.dmem = [0] * 1024
        self.written = [False] * 1024
        self.x = [0] * 32
        self.pc = 0
        self.result = self.done = self.exception = 0
        self.warnings = []

    def read_word(self, addr):
        if addr >> 28 == 1:
            return self.sw if addr >> 2 == MMIO_SW >> 2 else 0
        i = (addr >> 2) & 0x3FF
        if not self.written[i]:
            self.warnings.append(f"pc {self.pc:08x}: load from data_mem word {i:#x} never written")
        return self.dmem[i]

    def write(self, addr, data, strb):
        if addr >> 28 == 1:
            if addr >> 2 == MMIO_RESULT >> 2:
                for k in range(4):
                    if strb >> k & 1:
                        self.result = (self.result & ~(0xFF << 8 * k)) | (data & (0xFF << 8 * k))
            elif addr >> 2 == MMIO_DONE >> 2:
                self.done = 1
            return
        i = (addr >> 2) & 0x3FF
        for k in range(4):
            if strb >> k & 1:
                self.dmem[i] = (self.dmem[i] & ~(0xFF << 8 * k)) | (data & (0xFF << 8 * k))
        self.written[i] = True

    def step(self):
        """Execute one instruction; return its trace record (kind, pc, rd, value, addr, lanes, strb)."""
        pc, ins = self.pc, self.imem[(self.pc >> 2) & 0x3FF]
        op, rd, f3 = ins & 0x7F, (ins >> 7) & 31, (ins >> 12) & 7
        rs1, rs2, f7 = self.x[(ins >> 15) & 31], self.x[(ins >> 20) & 31], ins >> 25
        imm_i = sx(ins >> 20, 12)
        imm_s = sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)
        imm_b = sx(((ins >> 31) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 63) << 5) | (((ins >> 8) & 15) << 1), 13)
        imm_j = sx(((ins >> 31) << 20) | (((ins >> 12) & 255) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 1023) << 1), 21)
        nxt, val, store = (pc + 4) & M32, None, None
        legal = True
        if op == 0x37:
            val = ins & 0xFFFFF000
        elif op == 0x6F:
            val, nxt = (pc + 4) & M32, (pc + imm_j) & M32
        elif op == 0x67 and f3 == 0:
            val, nxt = (pc + 4) & M32, (rs1 + imm_i) & M32 & ~1
        elif op == 0x63 and f3 not in (2, 3):
            a, b = rs1, rs2
            take = {0: a == b, 1: a != b, 4: s32(a) < s32(b), 5: s32(a) >= s32(b), 6: a < b, 7: a >= b}[f3]
            if take:
                nxt = (pc + imm_b) & M32
        elif op == 0x03 and f3 in (0, 1, 2, 4, 5):
            addr = (rs1 + imm_i) & M32
            w = self.read_word(addr) >> 8 * (addr & 3)
            val = {0: sx(w, 8), 1: sx(w, 16), 2: w, 4: w & 0xFF, 5: w & 0xFFFF}[f3] & M32
        elif op == 0x23 and f3 in (0, 1, 2):
            addr = (rs1 + imm_s) & M32
            off = addr & 3
            if f3 == 0:   data, strb = (rs2 & 0xFF) * 0x01010101, 1 << off
            elif f3 == 1: data, strb = (rs2 & 0xFFFF) * 0x00010001, 0xC if off & 2 else 0x3
            else:         data, strb = rs2, 0xF
            lanes = sum(data & (0xFF << 8 * k) for k in range(4) if strb >> k & 1)
            self.write(addr, data, strb)
            store = (addr, lanes, strb)
        elif op == 0x13 and (f3 not in (1, 5) or (f3 == 1 and f7 == 0) or (f3 == 5 and f7 in (0, 0x20))):
            b = (ins >> 20) & 31 if f3 in (1, 5) else imm_i & M32
            val = alu(f3, f3 == 5 and f7 == 0x20, rs1, b)
        elif op == 0x33 and f7 == 1:
            val = muldiv(f3, rs1, rs2)
        elif op == 0x33 and (f7 == 0 or (f7 == 0x20 and f3 in (0, 5))):
            val = alu(f3, f7 == 0x20, rs1, rs2)
        else:
            legal = False
            self.exception = 1
        self.pc = nxt
        if store:
            return (2, pc, 0, 0) + store
        if legal and val is not None and rd != 0:
            self.x[rd] = val & M32
            return (1, pc, rd, val & M32, 0, 0, 0)
        return (0, pc, 0, 0, 0, 0, 0)


def run(imem, sw=0, max_commits=2000):
    m = Model(imem, sw)
    trace = []
    while len(trace) < max_commits and not m.done:
        trace.append(m.step())
    trace.append((3, 0, 0, m.result, m.done, m.exception, 0))
    return trace, m


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("hex")
    ap.add_argument("--sw", type=lambda s: int(s, 0), default=0)
    ap.add_argument("--max", type=int, default=2000)
    ap.add_argument("-o", "--out")
    a = ap.parse_args()
    trace, m = run(load_hex(a.hex), a.sw, a.max)
    text = "".join(" ".join(f"{v:x}" for v in t) + "\n" for t in trace)
    if a.out:
        open(a.out, "w").write(text)
    else:
        sys.stdout.write(text)
    for w in m.warnings:
        print("WARNING " + w, file=sys.stderr)
    print(f"{a.hex}: {len(trace) - 1} commits, done={m.done} result={m.result:#010x} "
          f"exception={m.exception}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
