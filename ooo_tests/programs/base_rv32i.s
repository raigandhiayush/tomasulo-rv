# base_rv32i.s - RV32I-only workload for tb_baseline_counters: the one test
# program that the baseline pipe can run (no MUL/DIV), so the same hex is
# measured on pipe, pipe_m and pipe_ooo. Loads, stores, taken and not-taken
# branches, shifts, byte/halfword accesses, D8 result + done stores.
        lui   s0, 0x10000            # MMIO base
        li    s1, 0x100              # array base
        li    t0, 23
        sw    t0, 0(s1)
        li    t0, -5
        sw    t0, 4(s1)
        li    t0, 42
        sw    t0, 8(s1)
        li    t0, 7
        sw    t0, 12(s1)
        li    t0, 0
        sw    t0, 16(s1)
        li    t0, 100
        sw    t0, 20(s1)
        li    t0, -77
        sw    t0, 24(s1)
        li    t0, 15
        sw    t0, 28(s1)
        li    s2, 7                  # bubble sort, n-1 passes, signed
outer:  mv    t1, s1
        mv    t2, s2
inner:  lw    t3, 0(t1)
        lw    t4, 4(t1)
        bge   t4, t3, noswap
        sw    t4, 0(t1)
        sw    t3, 4(t1)
noswap: addi  t1, t1, 4
        addi  t2, t2, -1
        bnez  t2, inner
        addi  s2, s2, -1
        bnez  s2, outer
        li    a0, 0                  # a0 = sum of arr[i] << i
        li    t2, 0
        mv    t1, s1
sum:    lw    t3, 0(t1)
        sll   t3, t3, t2
        add   a0, a0, t3
        addi  t1, t1, 4
        addi  t2, t2, 1
        slti  t5, t2, 8
        bnez  t5, sum
        lbu   t3, 0(s1)              # arr[0] = -77 -> 0xB3
        xor   a0, a0, t3
        sh    a0, 0(s0)              # result, low half
        srli  t3, a0, 16
        sh    t3, 2(s0)              # result, high half
        sb    zero, 4(s0)            # done
end:    j     end
