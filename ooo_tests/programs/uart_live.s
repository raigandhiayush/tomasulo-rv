# uart_live.s - live calculator. Type two numbers and Enter; sw[3:0] picks the operation.
# Flip a switch and the answer updates with the same numbers. See report_uart.md.
#   sw[3:0] operation, sw[4] hex in the terminal, sw[5] result register shows cycles, not the answer
# Registers: s0 MMIO, s1 s2 operands, s3 switches in use, s4 line length, s5 answer, s6 cycles,
#            s7 operands typed yet, s8 first operand while parsing, s9 line buffer; s10 s11 links
        li    s0, 0x10000000
        li    s9, 0x200
        li    s4, 0
        li    s5, 0
        li    s6, 0
        li    s7, 0
        lw    s3, 8(s0)
        andi  s3, s3, 63
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
        li    a0, 108
        jal   ra, putc
        li    a0, 105
        jal   ra, putc
        li    a0, 118
        jal   ra, putc
        li    a0, 101
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
        li    a0, 46
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 97
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 98
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
        li    a0, 115
        jal   ra, putc
        li    a0, 119
        jal   ra, putc
        li    a0, 91
        jal   ra, putc
        li    a0, 51
        jal   ra, putc
        li    a0, 58
        jal   ra, putc
        li    a0, 48
        jal   ra, putc
        li    a0, 93
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 111
        jal   ra, putc
        li    a0, 112
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
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc
prompt:
        li    a0, 62
        jal   ra, putc
        li    a0, 32
        jal   ra, putc

poll:   lw    t0, 0x20(s0)
        andi  t0, t0, 1
        bnez  t0, key
        bnez  s4, poll               # half-typed line: switch changes wait for Enter
        lw    t1, 8(s0)
        andi  t1, t1, 63
        beq   t1, s3, poll
settle: lui   t2, 8              # a switch bounces: act only once it holds still
        addi  t2, t2, 232
st_lp:  lw    t0, 8(s0)
        andi  t0, t0, 63
        beq   t0, t1, st_same
        mv    t1, t0
        j     settle
st_same:
        addi  t2, t2, -1
        bnez  t2, st_lp
        beq   t1, s3, poll           # it bounced back to where it started
        xor   t2, t1, s3
        mv    s3, t1
        andi  t2, t2, 31
        beqz  t2, disp_only          # only sw[5] moved: no new line
        beqz  s7, disp_only          # no numbers yet
        li    a0, 13
        jal   ra, putc
        jal   s10, show
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc
        j     prompt
disp_only:
        jal   s10, display
        j     poll

key:    lw    a0, 0x24(s0)
        li    t1, 113                # q
        beq   a0, t1, quit
        li    t1, 13
        beq   a0, t1, enter
        li    t1, 10
        beq   a0, t1, enter
        li    t1, 8                  # Backspace, both codes
        beq   a0, t1, bksp
        li    t1, 127
        beq   a0, t1, bksp
        li    t1, 32                 # other control bytes are ignored
        blt   a0, t1, poll
        bge   a0, t1, printable
printable:
        li    t1, 127
        bge   a0, t1, poll
        li    t1, 39                 # room for 39 characters
        bge   s4, t1, poll
        add   t1, s9, s4
        sb    a0, 0(t1)
        addi  s4, s4, 1
        jal   ra, putc               # echo
        j     poll
bksp:   beqz  s4, poll
        addi  s4, s4, -1
        li    a0, 8
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 8
        jal   ra, putc
        j     poll

enter:  beqz  s4, poll               # empty line, or the second half of CR LF
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc
        add   t1, s9, s4
        sb    zero, 0(t1)
        li    s4, 0
        lw    s3, 8(s0)
        andi  s3, s3, 63
        mv    a2, s9
        jal   s11, parse
        beqz  a3, bad
        mv    s8, a0
        jal   s11, parse
        beqz  a3, bad
sk_end: lbu   t0, 0(a2)              # nothing but separators may follow
        beqz  t0, line_ok
        li    t1, 32
        beq   t0, t1, sk_nxt
        li    t1, 44
        bne   t0, t1, bad
sk_nxt: addi  a2, a2, 1
        j     sk_end
line_ok:
        mv    s1, s8
        mv    s2, a0
        li    s7, 1
        jal   s10, show
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc
        j     prompt
bad:
        li    a0, 63
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 110
        jal   ra, putc
        li    a0, 101
        jal   ra, putc
        li    a0, 101
        jal   ra, putc
        li    a0, 100
        jal   ra, putc
        li    a0, 58
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 97
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        li    a0, 98
        jal   ra, putc
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc
        j     prompt

quit:
        li    a0, 13
        jal   ra, putc
        li    a0, 10
        jal   ra, putc
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
        sw    zero, 4(s0)            # done: stops the counters
end:    j     end

# parse: read one number at a2. Returns a0, a3 = 1 if good, a2 past it. Link s11.
parse:  li    a3, 0
pa_sp:  lbu   t0, 0(a2)
        li    t1, 32
        beq   t0, t1, pa_skp
        li    t1, 44
        bne   t0, t1, pa_sgn
pa_skp: addi  a2, a2, 1
        j     pa_sp
pa_sgn: li    t3, 0                  # negative?
        li    t1, 45
        bne   t0, t1, pa_rdx
        li    t3, 1
        addi  a2, a2, 1
pa_rdx: li    t4, 10
        andi  t1, s3, 16
        beqz  t1, pa_pfx
        li    t4, 16
pa_pfx: lbu   t0, 0(a2)              # a 0x prefix means hex in either mode
        li    t1, 48
        bne   t0, t1, pa_num
        lbu   t0, 1(a2)
        ori   t0, t0, 32
        li    t1, 120
        bne   t0, t1, pa_num
        li    t4, 16
        addi  a2, a2, 2
pa_num: li    a0, 0
        li    t5, 0                  # digits seen
pa_lp:  lbu   t0, 0(a2)
        beqz  t0, pa_end
        li    t1, 32
        beq   t0, t1, pa_end
        li    t1, 44
        beq   t0, t1, pa_end
        addi  t1, t0, -48
        li    t2, 10
        bltu  t1, t2, pa_dig
        ori   t1, t0, 32
        addi  t1, t1, -97
        li    t2, 6
        bgeu  t1, t2, pa_ret
        addi  t1, t1, 10
pa_dig: bgeu  t1, t4, pa_ret         # a digit too big for this base
        mulhu t2, a0, t4             # more than 32 bits is an error, not a wrap
        bnez  t2, pa_ret
        mul   t2, a0, t4
        add   t6, t2, t1
        bltu  t6, t2, pa_ret
        mv    a0, t6
        addi  t5, t5, 1
        addi  a2, a2, 1
        j     pa_lp
pa_end: beqz  t5, pa_ret
        beqz  t3, pa_ok
        li    t2, 0x80000000
        bltu  t2, a0, pa_ret
        sub   a0, zero, a0
pa_ok:  li    a3, 1
pa_ret: jr    s11

# show: run the operation in s3[3:0] on s1, s2, then print and update the display. Link s10.
show:   lw    t3, 0x28(s0)           # the same sequence around a move, to subtract the overhead
        mv    t5, s1
        xor   t6, t5, t5
        add   t6, t6, s0
        lw    t4, 0x28(t6)
        sub   a7, t4, t3
        andi  t0, s3, 15
        jal   t6, anchor
anchor: slli  t0, t0, 5
        add   t6, t6, t0
        jalr  zero, 12(t6)
        lw    t3, 0x28(s0)           # ADD: counter before
        add   t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 1092
        addi  a4, a4, 1089           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # SUB: counter before
        sub   t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 1061
        addi  a4, a4, 1363           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # MUL: counter before
        mul   t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 1221
        addi  a4, a4, 1357           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # MULH: counter before
        mulh  t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 296133
        addi  a4, a4, 1357           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # DIV: counter before
        div   t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 1381
        addi  a4, a4, -1724           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # DIVU: counter before
        divu  t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 349541
        addi  a4, a4, -1724           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # REM: counter before
        rem   t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 1236
        addi  a4, a4, 1362           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # REMU: counter before
        remu  t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 349396
        addi  a4, a4, 1362           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # AND: counter before
        and   t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 1093
        addi  a4, a4, -447           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # OR: counter before
        or    t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 5
        addi  a4, a4, 591           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # XOR: counter before
        xor   t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 1317
        addi  a4, a4, -168           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # SLL: counter before
        sll   t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 1221
        addi  a4, a4, -941           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # SRL: counter before
        srl   t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 1221
        addi  a4, a4, 595           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # SRA: counter before
        sra   t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 1045
        addi  a4, a4, 595           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # SLT: counter before
        slt   t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 1349
        addi  a4, a4, -941           # name, low byte first
        j     measured
        lw    t3, 0x28(s0)           # SLTU: counter before
        sltu  t5, s1, s2
        xor   t6, t5, t5             # 0, but only once the answer exists
        add   t6, t6, s0
        lw    t4, 0x28(t6)           # counter after: this load depends on the answer
        lui   a4, 349509
        addi  a4, a4, -941           # name, low byte first
        j     measured
measured:
        mv    s5, t5
        sub   s6, t4, t3
        sub   s6, s6, a7             # cycles beyond a move, plus the 1 a move takes
        addi  s6, s6, 1
        li    t1, 1
        bge   s6, t1, name
        li    s6, 1
name:   andi  a0, a4, 255
        beqz  a0, shown
        jal   ra, putc
        srli  a4, a4, 8
        j     name
shown:
        li    a5, 37024             # the operations that print as unsigned
        andi  t0, s3, 15
        srl   a5, a5, t0
        andi  a5, a5, 1
        li    a0, 32
        jal   ra, putc
        mv    a1, s1
        jal   s11, putnum
        li    a0, 32
        jal   ra, putc
        mv    a1, s2
        jal   s11, putnum
        li    a0, 32
        jal   ra, putc
        li    a0, 61
        jal   ra, putc
        li    a0, 32
        jal   ra, putc
        mv    a1, s5
        jal   s11, putnum
        li    a0, 32
        jal   ra, putc
        li    a0, 91
        jal   ra, putc
        mv    a1, s6
        jal   s11, putu
        li    a0, 93
        jal   ra, putc
        andi  t0, s3, 15
        addi  t0, t0, -4
        li    t1, 4
        bgeu  t0, t1, disp0
        bnez  s2, disp0
        li    a0, 32
        jal   ra, putc
        li    a0, 68
        jal   ra, putc
        li    a0, 73
        jal   ra, putc
        li    a0, 86
        jal   ra, putc
        li    a0, 48
        jal   ra, putc
disp0:  mv    a6, s10
        jal   s10, display
        jr    a6

# display: the result register gets the answer, or the cycles when sw[5] is on. Link s10.
display:
        mv    a0, s5
        andi  t1, s3, 32
        beqz  t1, dp_st
        mv    a0, s6
dp_st:  sw    a0, 0(s0)
        jr    s10

# putnum: print a1 in the current format; a5 = 1 for unsigned decimal. Link s11.
putnum: andi  t1, s3, 16
        bnez  t1, puthex
        bnez  a5, putu
        bge   a1, zero, putu
        li    a0, 45
        jal   ra, putc
        sub   a1, zero, a1
# putu: print a1 as unsigned decimal. Link s11.
putu:   li    a3, 1000000000
        li    t5, 0                  # printed anything yet?
pu_lp:  divu  t3, a1, a3
        remu  a1, a1, a3
        bnez  t3, pu_out
        bnez  t5, pu_out
        li    t1, 1
        beq   a3, t1, pu_out         # the last digit always prints
        j     pu_nxt
pu_out: addi  a0, t3, 48
        li    t5, 1
        jal   ra, putc
pu_nxt: li    t1, 10
        divu  a3, a3, t1
        bnez  a3, pu_lp
        jr    s11
puthex: li    t3, 28
ph_lp:  srl   t4, a1, t3
        andi  t4, t4, 15
        addi  a0, t4, 48
        li    t1, 10
        blt   t4, t1, ph_out
        addi  a0, t4, 55
ph_out: jal   ra, putc
        addi  t3, t3, -4
        bge   t3, zero, ph_lp
        jr    s11

# UART: t0 scratch, a0 = byte. Link ra.
getc:   lw    t0, 0x20(s0)
        andi  t0, t0, 1
        beqz  t0, getc
        lw    a0, 0x24(s0)
        ret
putc:   lw    t0, 0x20(s0)
        andi  t0, t0, 2
        beqz  t0, putc
        sw    a0, 0x24(s0)
        ret
