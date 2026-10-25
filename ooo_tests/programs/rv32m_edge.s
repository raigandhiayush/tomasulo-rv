# rv32m_edge.s - RV32M edge cases (blueprint 6.17 "RV32M edge-case program").
# Every result goes to data_mem 0x400.. and is checked against tools/ref_model.py
# by tb_commit_trace; result = XOR of all of them.
        lui   s0, 0x10000            # MMIO base
        li    s1, 0x400              # output pointer
        li    t0, 7
        li    t1, -7
        li    t2, 0x80000000         # INT_MIN
        li    t3, -1
        li    t4, 0x7FFFFFFF         # INT_MAX
        li    t5, 0
        li    t6, 2
        li    a7, 0                  # checksum
# divide by zero
        div   a0, t0, t5
        divu  a1, t1, t5
        rem   a2, t1, t5
        remu  a3, t0, t5
        sw    a0, 0(s1)
        sw    a1, 4(s1)
        sw    a2, 8(s1)
        sw    a3, 12(s1)
        xor   a7, a7, a0
        xor   a7, a7, a1
        xor   a7, a7, a2
        xor   a7, a7, a3
# signed overflow INT_MIN / -1
        div   a0, t2, t3
        rem   a1, t2, t3
        divu  a2, t2, t3
        remu  a3, t2, t3
        sw    a0, 16(s1)
        sw    a1, 20(s1)
        sw    a2, 24(s1)
        sw    a3, 28(s1)
        xor   a7, a7, a0
        xor   a7, a7, a1
        xor   a7, a7, a2
        xor   a7, a7, a3
# sign combinations
        div   a0, t1, t6
        rem   a1, t1, t6
        div   a2, t0, t3
        rem   a3, t1, t3
        sw    a0, 32(s1)
        sw    a1, 36(s1)
        sw    a2, 40(s1)
        sw    a3, 44(s1)
        xor   a7, a7, a0
        xor   a7, a7, a1
        xor   a7, a7, a2
        xor   a7, a7, a3
# multiply: low word overflow and all high-word variants
        mul   a0, t4, t4
        mulh  a1, t2, t2
        mulhsu a2, t1, t4
        mulhu a3, t3, t3
        mulh  a4, t1, t0
        mulhsu a5, t3, t3
        sw    a0, 48(s1)
        sw    a1, 52(s1)
        sw    a2, 56(s1)
        sw    a3, 60(s1)
        sw    a4, 64(s1)
        sw    a5, 68(s1)
        xor   a7, a7, a0
        xor   a7, a7, a1
        xor   a7, a7, a2
        xor   a7, a7, a3
        xor   a7, a7, a4
        xor   a7, a7, a5
# back-to-back dependent MUL -> DIV -> REM chain
        mul   a0, t1, t1             # 49
        div   a1, a0, t0             # 7
        rem   a2, a0, t6             # 1
        add   a3, a1, a2             # 8
        sw    a3, 72(s1)
        xor   a7, a7, a3
        sw    a7, 0(s0)              # result = checksum
        sw    zero, 4(s0)            # done
end:    j     end
