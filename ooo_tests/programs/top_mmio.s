# top_mmio.s - MMIO, counter and workload program for tb_top_fpga_ooo (E).
# Decisions D8, D20, D21, D22; test plan T1-T9 in evidence/docs/mmio_D8_D20.md.
# Build: bash tools/build_test_programs.sh   (rvasm -> .hex, ref_model -> .trace)

        lui   s0, 0x10000            # s0 = 0x1000_0000, MMIO base

# T2b: byte and halfword stores to result (0 after reset) honour byte lanes
        li    t0, 5
        sb    t0, 0(s0)              # result = 0x0000_0005
        li    t1, 0x1234
        sh    t1, 2(s0)              # result = 0x1234_0005
# T2: full-word store to result
        li    t2, 0xCAFEBABE
        sw    t2, 0(s0)              # result = 0xCAFE_BABE

# T6: stores to other MMIO addresses, every byte-lane pattern: all dropped
        sb    t0, 8(s0)
        sb    t0, 9(s0)
        sb    t0, 10(s0)
        sb    t0, 11(s0)
        sh    t1, 12(s0)
        sh    t1, 14(s0)
        sw    t2, 16(s0)
        li    t3, 0x1FFFFFF0
        sw    t2, 0(t3)
        sb    t0, 3(t3)

# T7: plain RAM stores (bits [31:28] = 0) reach data_mem
        li    t4, 0x11223344
        sw    t4, 0x100(zero)
        li    t5, 0x0FFFFFFC
        sw    t4, 0(t5)

# T4/T5: loads alternating switches, RAM and other MMIO addresses
        lw    a0, 8(s0)              # {16'd0, sw}
        lw    a1, 0x100(zero)        # 0x1122_3344 from data_mem
        lw    a2, 8(s0)              # {16'd0, sw} again
        lw    a3, 16(s0)             # other MMIO address -> 0
        lhu   a4, 8(s0)              # sw[15:0]
        lbu   a5, 9(s0)              # sw[15:8]
        lw    a6, 0(s0)              # result address is store-only -> 0
        sw    a0, 0x200(zero)
        sw    a1, 0x204(zero)
        sw    a2, 0x208(zero)
        sw    a3, 0x20C(zero)
        sw    a4, 0x210(zero)
        sw    a5, 0x214(zero)
        sw    a6, 0x218(zero)

# T8: bubble sort of {6, 3, 9} (same algorithm as code_sort.c), then MUL/DIV
        li    t0, 6
        sw    t0, 0x300(zero)
        li    t0, 3
        sw    t0, 0x304(zero)
        li    t0, 9
        sw    t0, 0x308(zero)
        li    s1, 3                  # n
outer:  li    s2, 0                  # swapped
        li    s4, 0x300              # &arr[j]
        addi  s5, s1, -1             # n-1
        li    s6, 0                  # j
inner:  bge   s6, s5, inner_end
        lw    a0, 0(s4)
        lw    a1, 4(s4)
        bge   a1, a0, noswap         # swap if arr[j] > arr[j+1]
        sw    a1, 0(s4)
        sw    a0, 4(s4)
        li    s2, 1
noswap: addi  s4, s4, 4
        addi  s6, s6, 1
        j     inner
inner_end:
        addi  s1, s1, -1
        li    t1, 1
        beq   s2, t1, outer
        lw    a0, 0x300(zero)        # arr[0] = 3
        mul   t2, a0, a0             # 9
        div   t3, t2, a0             # 3
        sw    t3, 0(s0)              # result = 3

# T3: any store to 0x1000_0004 sets done (a byte store of 9 here)
        sb    t0, 4(s0)
end:    j     end
