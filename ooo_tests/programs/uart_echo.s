# uart_echo.s - sends back every byte you type; Enter starts a new line, q quits.
# The result register holds the number of bytes echoed.
        li    s0, 0x10000000
        li    a0, 84
        jal   ra, putc
        li    a0, 79
        jal   ra, putc
        li    a0, 77
        jal   ra, putc
        li    a0, 65
        jal   ra, putc
        li    a0, 45
        jal   ra, putc
        li    a0, 82
        jal   ra, putc
        li    a0, 86
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 101
        jal   ra, putc
        li    a0, 99
        jal   ra, putc
        li    a0, 104
        jal   ra, putc
        li    a0, 111
        jal   ra, putc
        li    a0, 46
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 113
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 113
        jal   ra, putc
        li    a0, 117
        jal   ra, putc
        li    a0, 105
        jal   ra, putc
        li    a0, 116
        jal   ra, putc
        li    a0, 115
        jal   ra, putc
        li    a0, 46
        jal   ra, putc
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc

        li    s1, 0
loop:   jal   ra, getc
        li    t1, 113                # q
        beq   a0, t1, quit
        addi  s1, s1, 1
        sw    s1, 0(s0)
        li    t1, 13
        beq   a0, t1, newline
        li    t1, 10
        beq   a0, t1, newline
        jal   ra, putc
        j     loop
newline:
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc

        j     loop
quit:
        li    a0, 98
        jal   ra, putc
        li    a0, 121
        jal   ra, putc
        li    a0, 101
        jal   ra, putc
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc

        sw    zero, 4(s0)
end:    j     end

# ---- UART runtime: t0 scratch; a0 = byte
getc:   lw    t0, 0x20(s0)           # status
        andi  t0, t0, 1              # [0] = a byte is waiting
        beqz  t0, getc
        lw    a0, 0x24(s0)           # read it (this removes it)
        ret
putc:   lw    t0, 0x20(s0)
        andi  t0, t0, 2              # [1] = room to send
        beqz  t0, putc
        sw    a0, 0x24(s0)
        ret
