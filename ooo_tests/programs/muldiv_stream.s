# muldiv_stream.s - DIV with independent MULs in its shadow (A, 26 Oct 2026).
# 4 groups of one DIV followed by 7 MULs that do not depend on it. 8 instructions
# fill the 8-entry ROB, the most pipe_ooo can complete behind one divide; pipe_m
# freezes for the DIV and then for each MUL. The single divider (34 cycles) is
# paid in full by both cores. Constructed best case, not a typical workload (D17).
# Result = sum of the last 8 products and the 4 quotients.
        lui   s0, 0x10000            # MMIO base
        li    s1, 3                  # source, never written again
        li    s2, 5                  # source, never written again
        li    s3, 7                  # source, never written again
        li    s4, 11                 # source, never written again
        li    s5, 13                 # source, never written again
        li    s6, 17                 # source, never written again
        li    s7, 74565              # source, never written again
        li    s8, -26505             # source, never written again
# group 0: one DIV, then 7 MULs that do not need it (DIV + 7 = 8 = ROB size)
        div   t4, s7, s1
        mul   a0, s1, s2
        mul   a1, s2, s3
        mul   a2, s3, s4
        mul   a3, s4, s5
        mul   a4, s5, s6
        mul   a5, s6, s7
        mul   a6, s7, s8
# group 1: one DIV, then 7 MULs that do not need it (DIV + 7 = 8 = ROB size)
        div   t5, s8, s2
        mul   a7, s8, s1
        mul   a0, s1, s3
        mul   a1, s2, s4
        mul   a2, s3, s5
        mul   a3, s4, s6
        mul   a4, s5, s7
        mul   a5, s6, s8
# group 2: one DIV, then 7 MULs that do not need it (DIV + 7 = 8 = ROB size)
        div   t6, s7, s3
        mul   a6, s7, s1
        mul   a7, s8, s2
        mul   a0, s1, s4
        mul   a1, s2, s5
        mul   a2, s3, s6
        mul   a3, s4, s7
        mul   a4, s5, s8
# group 3: one DIV, then 7 MULs that do not need it (DIV + 7 = 8 = ROB size)
        div   s9, s8, s4
        mul   a5, s6, s1
        mul   a6, s7, s2
        mul   a7, s8, s3
        mul   a0, s1, s5
        mul   a1, s2, s6
        mul   a2, s3, s7
        mul   a3, s4, s8
# sum the surviving products and the quotients
        add   t0, a0, a1
        add   t1, a2, a3
        add   t2, a4, a5
        add   t3, a6, a7
        add   t0, t0, t1
        add   t2, t2, t3
        add   t0, t0, t2
        add   t0, t0, t4
        add   t0, t0, t5
        add   t0, t0, t6
        add   t0, t0, s9
        sw    t0, 0(s0)              # result = 0x00018ae9
        sw    zero, 4(s0)            # done
end:    j     end
