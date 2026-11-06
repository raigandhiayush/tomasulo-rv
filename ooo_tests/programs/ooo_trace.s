# ooo_trace.s - out-of-order completion scenario for tb_ooo_event_trace (C).
# TASKS 19 Oct: younger instructions complete on cdb_alu, cdb_mul and cdb_lsu
# while the DIV at the ROB head is still running (ooo_event, D18).
        lui   s0, 0x10000            # MMIO base
        li    t0, 1000
        li    t1, 7
        sw    t1, 0x100(zero)        # data for the load below
        div   a0, t0, t1             # 142, 34-cycle occupancy, becomes ROB head
        addi  a1, t1, 1              # 8   on cdb_alu while DIV is head
        mul   a2, t1, t1             # 49  on cdb_mul while DIV is head
        lw    a3, 0x100(zero)        # 7   on cdb_lsu while DIV is head
        add   a4, a1, a2             # 57  operands from cdb_alu and cdb_mul
        mul   a5, a2, a3             # 343 operands from cdb_mul and cdb_lsu
        add   a6, a0, a4             # 199 waits for the DIV
        add   a6, a6, a5             # 542
        sw    a6, 0(s0)              # result = 542
        sw    zero, 4(s0)            # done
end:    j     end
