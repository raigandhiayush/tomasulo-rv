# pipe_m_edge.s - corner cases of the baseline + in-order MUL/DIV core (pipe_m,
# baseline_m/) for tb_baseline_counters; also runs on pipe_ooo.
# Freeze vs: load / store just before MUL/DIV, MUL/DIV at a taken-branch target,
# MUL/DIV on the squashed wrong path, dependent MUL/DIV chains, branch and store
# on a MUL/DIV result, byte stores to MMIO around a freeze.
        lui   s0, 0x10000            # MMIO base
        li    s1, 0x100
        li    t0, 1234
        sw    t0, 0(s1)
        li    t1, -7
        lw    t2, 0(s1)              # load ...
        mul   a0, t2, t1             # ... used at once by MUL: -8638
        sw    a0, 4(s1)              # store just before a DIV
        div   a1, a0, t1             # 1234
        rem   a2, a0, t0             # 0 (dependent on the MUL)
        mulh  a3, a0, a0             # 0 (8638^2 < 2^32)
        mulhu a4, a0, a0             # high word of 0xFFFFDE42^2
        divu  a5, a0, t0             # 0xFFFFDE42 / 1234
        remu  a6, a0, t0
        lw    t3, 4(s1)              # -8638, written before the DIV
        add   a7, a1, t3             # 1234 - 8638
        j     tgt
        mul   a1, a1, a1             # wrong path: must not change a1
        div   a2, a1, t1             # wrong path: must not change a2
tgt:    mul   s2, a1, t1             # first instruction at a jump target: -8638
        div   s3, s2, a1             # second: -7
        beq   s3, t1, ok1            # branch on a DIV result
        li    s2, 0
ok1:    sb    s3, 0(s0)              # result byte 0 = 0xF9, then freeze
        remu  s4, s2, t0
        sb    s4, 1(s0)              # result byte 1, written once after the freeze
        li    s5, 3
loop:   mul   s6, s5, s5             # MUL as loop target, chained
        mul   s6, s6, s5
        addi  s5, s5, -1
        bnez  s5, loop               # taken twice; DIV in its shadow below
        div   s7, s6, s5             # s5 = 0 here: divide by zero -> -1
        xor   t4, a3, a4
        xor   t4, t4, a5
        xor   t4, t4, a6
        xor   t4, t4, a7
        xor   t4, t4, a2
        xor   t4, t4, s6
        xor   t4, t4, s7
        sh    t4, 2(s0)              # result bytes 2-3
        sw    t4, 8(s1)
        sb    zero, 4(s0)            # done
end:    j     end
