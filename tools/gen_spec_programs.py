#!/usr/bin/env python3
"""Generates ooo_tests/programs/spec_stress_<k>.{hex,trace}: random looping RV32IM programs
that make branch speculation work hard. Nested counted loops (backward branches: BTB hits,
predicted-taken paths, mispredicted loop exits) around random bodies with data-dependent forward
branches, JAL, JALR, loads, stores, MUL, DIV and MMIO. Illegal words sit where only the wrong
path can reach them. The program ends by adding every register and all test memory into the
result, so a wrong-path store or a bad rename changes the result.
Usage: python3 -I tools/gen_spec_programs.py [count]"""
import os, random, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ooo_tests", "programs")
BASE, WORDS = 31, 64           # x31 = 0x400: test memory, 64 words
MMIO = 30                      # x30 = 0x1000_0000
CNT0, CNT1, TMP = 20, 21, 22   # loop counters and JALR scratch: never random destinations
R = list(range(1, 9))          # random destinations and sources

def r_t(f7, rs2, rs1, f3, rd): return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33
def i_t(imm, rs1, f3, rd, op=0x13): return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def s_t(imm, rs2, rs1, f3):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 31) << 7) | 0x23
def b_t(imm, rs2, rs1, f3):
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 63) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | \
           (((imm >> 1) & 15) << 8) | (((imm >> 11) & 1) << 7) | 0x63
def j_t(imm, rd):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 1023) << 21) | (((imm >> 11) & 1) << 20) | \
           (((imm >> 12) & 255) << 12) | (rd << 7) | 0x6F
def lui(imm20, rd): return (imm20 << 12) | (rd << 7) | 0x37

class Prog:
    def __init__(s, rnd): s.w, s.rnd, s.fix = [], rnd, []
    def emit(s, x): s.w.append(x); return len(s.w) - 1
    def li(s, rd, v): s.emit(i_t(v, 0, 0, rd))
    def here(s): return len(s.w)
    def patch(s, at, target):
        """at = index of a branch/JAL placeholder (kind, regs): fill in the offset."""
        kind, a, b, c = s.w[at]
        off = (target - at) * 4
        s.w[at] = b_t(off, b, a, c) if kind == "b" else j_t(off, a)

    def item(s):
        rnd, r = s.rnd, s.rnd.randrange(100)
        rd, a, b = rnd.choice(R), rnd.choice(R), rnd.choice(R)
        if r < 12:                         # a branch that resolves late, with work behind it:
            s.emit(rnd.choice((r_t(1, b, a, 0, rd), r_t(1, b, a, 4, rd),     # MUL, DIV or
                               i_t(rnd.randrange(WORDS) * 4, BASE, 2, rd, 0x03))))   # load, then
            at = s.emit(("b", rd, rnd.choice(R), rnd.choice((0, 1, 4, 5, 6, 7))))    # branch on it
            for _ in range(rnd.randrange(2, 6)): s.item_simple()
            s.patch(at, s.here())
        elif r < 28:
            f3 = rnd.randrange(8)
            s.emit(r_t(0x20 if f3 in (0, 5) and rnd.random() < .5 else 0, b, a, f3, rd))
        elif r < 34: s.emit(i_t(rnd.randrange(-2048, 2048), a, rnd.choice((0, 2, 3, 4, 6, 7)), rd))
        elif r < 42: s.emit(r_t(1, b, a, rnd.randrange(4), rd))
        elif r < 47: s.emit(r_t(1, b, a, 4 + rnd.randrange(4), rd))
        elif r < 62:
            f3 = rnd.choice((0, 1, 2, 4, 5))
            sz = {0: 1, 4: 1, 1: 2, 5: 2, 2: 4}[f3]
            s.emit(i_t(rnd.randrange(WORDS * 4 // sz) * sz, BASE, f3, rd, 0x03))
        elif r < 74:
            f3 = rnd.randrange(3)
            sz = 1 << f3
            s.emit(s_t(rnd.randrange(WORDS * 4 // sz) * sz, b, BASE, f3))
        elif r < 88:                       # data-dependent forward branch over a small block
            at = s.emit(("b", a, b, rnd.choice((0, 1, 4, 5, 6, 7))))
            for _ in range(rnd.randrange(1, 5)): s.item_simple()
            s.patch(at, s.here())
        elif r < 92:                       # JAL over a word only the wrong path can fetch
            at = s.emit(("j", rnd.choice((0, rd)), 0, 0))
            s.emit(0xFFFFFFFF)
            s.patch(at, s.here())
        elif r < 95:                       # always-taken branch over an illegal word
            at = s.emit(("b", 0, 0, 0))
            s.emit(0xFFFFFFFF)
            s.patch(at, s.here())
        elif r < 98:                       # JALR
            target = s.here() + 3
            s.li(TMP, target * 4)
            s.emit(i_t(0, TMP, 0, rnd.choice((0, rd)), 0x67))
            s.emit(0xFFFFFFFF)
        elif r < 99: s.emit(i_t(8, MMIO, 2, rd, 0x03))     # load the switches
        else:        s.emit(s_t(0, a, MMIO, 2))            # publish a result

    def item_simple(s):
        """Something a wrong path must not leave a mark with: store, DIV, MUL, load, ALU."""
        rnd, r = s.rnd, s.rnd.randrange(5)
        rd, a, b = rnd.choice(R), rnd.choice(R), rnd.choice(R)
        if r == 0: s.emit(s_t(rnd.randrange(WORDS) * 4, b, BASE, 2))
        elif r == 1: s.emit(r_t(1, b, a, 4 + rnd.randrange(4), rd))
        elif r == 2: s.emit(r_t(1, b, a, rnd.randrange(4), rd))
        elif r == 3: s.emit(i_t(rnd.randrange(WORDS) * 4, BASE, 2, rd, 0x03))
        else: s.emit(r_t(0, b, a, 0, rd))

    def loop(s, cnt, n, body):
        s.li(cnt, n)
        top = s.here()
        body()
        s.emit(i_t(-1, cnt, 0, cnt))
        at = s.emit(("b", cnt, 0, 1))      # bne cnt, x0, top
        s.patch(at, top)

def generate(seed, scale):
    rnd = random.Random(seed)
    p = Prog(rnd)
    p.li(BASE, 0x400)
    p.emit(lui(0x10000, MMIO))
    for r in R: p.li(r, rnd.randrange(-2048, 2048))
    # initialise the test memory (data_mem starts undefined)
    p.li(TMP, 0)
    def init():
        p.emit(r_t(0, BASE, TMP, 0, 9))                     # x9 = x22 + x31
        p.emit(s_t(0, TMP, 9, 2))
        p.emit(i_t(4, TMP, 0, TMP))
    p.loop(CNT0, WORDS, init)
    for _ in range(rnd.randrange(3, 6)):
        def inner():
            for _ in range(rnd.randrange(3, 8)): p.item()
        def outer():
            for _ in range(rnd.randrange(2, 6)): p.item()
            p.loop(CNT1, rnd.randrange(2, 5), inner)
        p.loop(CNT0, max(2, rnd.randrange(3, 8) // scale), outer)
    # checksum: registers + test memory
    p.li(10, 0)
    for r in R: p.emit(r_t(0, r, 10, 0, 10))
    p.li(TMP, 0)
    def csum():
        p.emit(r_t(0, BASE, TMP, 0, 9))
        p.emit(i_t(0, 9, 2, 11, 0x03))
        p.emit(r_t(0, 11, 10, 0, 10))
        p.emit(i_t(4, TMP, 0, TMP))
    p.loop(CNT0, WORDS, csum)
    p.emit(s_t(0, 10, MMIO, 2))
    p.emit(s_t(4, 0, MMIO, 2))
    p.emit(j_t(0, 0))
    return p.w

def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    model = os.path.join(ROOT, "tools", "ref_model.py")
    for k in range(count):
        for scale in (1, 2, 3, 4, 6, 8):
            words = generate(1000 + k, scale)
            if len(words) > 500: continue            # JALR targets are reached with ADDI
            hex_p = os.path.join(OUT, f"spec_stress_{k}.hex")
            trace_p = os.path.join(OUT, f"spec_stress_{k}.trace")
            with open(hex_p, "w") as f:
                for i in range(1024):
                    f.write(f"{(words[i] if i < len(words) else 0):08x} // 32'h{i*4:08x}\n")
            out = subprocess.run([sys.executable, "-I", model, hex_p, "--max", "3900", "-o", trace_p],
                                 capture_output=True, text=True).stderr.strip().splitlines()[-1]
            # an illegal word reached on the right path would be a generator bug
            if "done=1" in out and "exception=0" in out:
                print(f"spec_stress_{k}: {len(words)} words, {out.split(':')[1].strip()}")
                break
        else:
            raise SystemExit(f"seed {k}: no size fits the 4,096-line trace limit")

main()
