# mul_stream.s - best case for the pipelined multiplier (A, 26 Oct 2026).
# 32 MULs that do not depend on each other: sources s1-s8 are set once and never
# written again, destinations rotate over a0-a7 (the reuse is a WAW, removed by
# renaming). No branches, no memory before the MMIO stores. pipe_ooo starts one
# MUL per cycle (mul_unit is pipelined, t -> t+2); pipe_m freezes for each MUL.
# This is a constructed best case, not a typical workload: label it so (D17).
# Result = sum of the last 8 products (every product is checked by the trace).
        lui   s0, 0x10000            # MMIO base
        li    s1, 3                  # source, never written again
        li    s2, 5                  # source, never written again
        li    s3, 7                  # source, never written again
        li    s4, 11                 # source, never written again
        li    s5, 13                 # source, never written again
        li    s6, 17                 # source, never written again
        li    s7, 74565              # source, never written again
        li    s8, -26505             # source, never written again
# 32 independent MULs
        mul   a0, s1, s2
        mul   a1, s2, s3
        mul   a2, s3, s4
        mul   a3, s4, s5
        mul   a4, s5, s6
        mul   a5, s6, s7
        mul   a6, s7, s8
        mul   a7, s8, s1
        mul   a0, s1, s3
        mul   a1, s2, s4
        mul   a2, s3, s5
        mul   a3, s4, s6
        mul   a4, s5, s7
        mul   a5, s6, s8
        mul   a6, s7, s1
        mul   a7, s8, s2
        mul   a0, s1, s4
        mul   a1, s2, s5
        mul   a2, s3, s6
        mul   a3, s4, s7
        mul   a4, s5, s8
        mul   a5, s6, s1
        mul   a6, s7, s2
        mul   a7, s8, s3
        mul   a0, s1, s5
        mul   a1, s2, s6
        mul   a2, s3, s7
        mul   a3, s4, s8
        mul   a4, s5, s1
        mul   a5, s6, s2
        mul   a6, s7, s3
        mul   a7, s8, s4
# sum the 8 surviving products
        add   t0, a0, a1
        add   t1, a2, a3
        add   t2, a4, a5
        add   t3, a6, a7
        add   t0, t0, t1
        add   t2, t2, t3
        add   t0, t0, t2
        sw    t0, 0(s0)              # result = 0x000708f8
        sw    zero, 4(s0)            # done
end:    j     end
