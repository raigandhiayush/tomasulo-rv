# uart_calc.s - type a number, Enter; it prints n*2, n*n, n/7, n%7 (uses MUL and DIV).
# q quits. The result register (7-segment display) shows the last n*n.
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
        li    a0, 99
        jal   ra, putc
        li    a0, 97
        jal   ra, putc
        li    a0, 108
        jal   ra, putc
        li    a0, 99
        jal   ra, putc
        li    a0, 117
        jal   ra, putc
        li    a0, 108
        jal   ra, putc
        li    a0, 97
        jal   ra, putc
        li    a0, 116
        jal   ra, putc
        li    a0, 111
        jal   ra, putc
        li    a0, 114
        jal   ra, putc
        li    a0, 46
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 78
        jal   ra, putc
        li    a0, 117
        jal   ra, putc
        li    a0, 109
        jal   ra, putc
        li    a0, 98
        jal   ra, putc
        li    a0, 101
        jal   ra, putc
        li    a0, 114
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 43
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 69
        jal   ra, putc
        li    a0, 110
        jal   ra, putc
        li    a0, 116
        jal   ra, putc
        li    a0, 101
        jal   ra, putc
        li    a0, 114
        jal   ra, putc
        li    a0, 44
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

prompt:
        li    a0, 110
        jal   ra, putc
        li    a0, 63
        jal   ra, putc
        li    a0, 32
        jal   ra, putc

        li    s1, 0                  # value
        li    s2, 0                  # digits seen
read:   jal   ra, getc
        li    t1, 113                # q
        beq   a0, t1, quit
        li    t1, 13                 # Enter: CR
        beq   a0, t1, enter
        li    t1, 10                 # Enter: LF
        beq   a0, t1, enter
        addi  t2, a0, -48            # digit?
        li    t1, 10
        bgeu  t2, t1, read           # anything else is ignored
        li    t1, 10
        mul   s1, s1, t1
        add   s1, s1, t2
        addi  s2, s2, 1
        jal   ra, putc               # echo
        j     read
enter:  beqz  s2, read               # second half of CR LF, or an empty line
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 120
        jal   ra, putc
        li    a0, 50
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 61
        jal   ra, putc
        li    a0, 32
        jal   ra, putc

        add   a1, s1, s1
        jal   s11, putdec
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 115
        jal   ra, putc
        li    a0, 113
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 61
        jal   ra, putc
        li    a0, 32
        jal   ra, putc

        mul   a1, s1, s1
        sw    a1, 0(s0)              # result register
        jal   s11, putdec
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 47
        jal   ra, putc
        li    a0, 55
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 61
        jal   ra, putc
        li    a0, 32
        jal   ra, putc

        li    t1, 7
        divu  a1, s1, t1
        jal   s11, putdec
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 37
        jal   ra, putc
        li    a0, 55
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 61
        jal   ra, putc
        li    a0, 32
        jal   ra, putc

        li    t1, 7
        remu  a1, s1, t1
        jal   s11, putdec
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc

        j     prompt
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

        sw    zero, 4(s0)            # done
end:    j     end

# putdec: print a1 in decimal, return through s11; no leading zeros
putdec: li    s3, 1000000000
        li    s4, 0                  # printed anything yet?
pd_lp:  divu  t3, a1, s3
        remu  a1, a1, s3
        bnez  t3, pd_out
        bnez  s4, pd_out
        li    t1, 1
        beq   s3, t1, pd_out         # the last digit always prints
        j     pd_nxt
pd_out: addi  a0, t3, 48
        li    s4, 1
        jal   ra, putc
pd_nxt: li    t1, 10
        divu  s3, s3, t1
        bnez  s3, pd_lp
        jr    s11

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
