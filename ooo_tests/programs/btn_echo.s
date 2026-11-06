# btn_echo.s - copies the button register (0x1000_000C) to the result register forever.
# It also reads 0x1000_0010, an unused MMIO address that must read 0; if not, it sets done.
# Checked by tb_buttons.v.
        lui   s0, 0x10000
loop:   lw    t0, 12(s0)
        sw    t0, 0(s0)
        lw    t1, 16(s0)
        bne   t1, zero, bad
        jal   zero, loop
bad:    addi  t2, zero, 1
        sw    t2, 4(s0)
        jal   zero, bad
