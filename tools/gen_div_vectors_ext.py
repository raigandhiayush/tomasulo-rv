#!/usr/bin/env python3
"""Generates extended corner-case and randomized div_unit test vectors."""
import random,sys,os
M=(1<<32)-1
def sx(v): return v-(1<<32) if v>>31 else v
def trunc_div(n,d):  # C-style truncation toward zero
    q=abs(n)//abs(d); return q if (n<0)==(d<0) else -q
def rv(f,a,b):
    if f==0:   # DIV
        if b==0: return M
        if sx(a)==-2**31 and sx(b)==-1: return a
        return trunc_div(sx(a),sx(b))&M
    if f==1: return M if b==0 else a//b
    if f==2:   # REM
        if b==0: return a
        if sx(a)==-2**31 and sx(b)==-1: return 0
        return (sx(a)-trunc_div(sx(a),sx(b))*sx(b))&M
    return a if b==0 else a%b
vals=set([0,1,2,3,M,M-1,M-2,0x80000000,0x80000001,0x80000002,0x7FFFFFFF,0x7FFFFFFE,
          0x55555555,0xAAAAAAAA,0x0000FFFF,0xFFFF0000,0x00010000,0xFFFF0001,0x0000FFFE])
for k in (4,7,8,15,16,23,24,30): vals |= {1<<k,(1<<k)-1,(-(1<<k))&M}
vals=sorted(vals)[:45]
out=sys.argv[1]; os.makedirs(out,exist_ok=True)
def write(name,grp,pairs):
    with open(os.path.join(out,name),'w') as fh:
        fh.write("// group funct3 a b expected (independent model, audit 23 Oct)\n")
        for f,a,b in pairs: fh.write(f"{grp:08x} {f:08x} {a:08x} {b:08x} {rv(f,a,b):08x}\n")
write("ext_grid.mem",25,[(f,a,b) for f in range(4) for a in vals for b in vals])
rng=random.Random(20261023)
for c in range(int(sys.argv[2])):
    pairs=[]
    for i in range(8000):
        a,b=rng.getrandbits(32),rng.getrandbits(32)
        m=i%8
        if m==1: b&=0xFF
        if m==2: b=(-(b&0xF))&M
        if m==3: a,b=a, a                      # a == b
        if m==4: b=(a>>rng.randrange(1,31))|1  # quotient of a few bits
        if m==5: b=1<<rng.randrange(32)
        if m==6: a=0x80000000|rng.getrandbits(8); b=M^rng.getrandbits(2)  # around INT_MIN / -1
        pairs.append((i%4,a,b))
    write(f"rnd_{c:02d}.mem",26,pairs)
print(len(vals),"corner values ->",len(vals)**2*4,"grid vectors")
print("self-check vs spec examples:",rv(0,7,0)==M,rv(2,(-7)&M,0)==(-7)&M,rv(0,0x80000000,M)==0x80000000,rv(2,0x80000000,M)==0,rv(2,(-7)&M,2)==(-1)&M,rv(2,7,(-2)&M)==1)
