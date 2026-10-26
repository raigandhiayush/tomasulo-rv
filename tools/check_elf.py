#!/usr/bin/env python3
"""Validates RISC-V ELF binaries against TOMA-RV architectural and execution constraints."""
import struct, sys

EM_RISCV = 243
SHT_SYMTAB, SHT_RELA, SHT_NOBITS, SHT_REL = 2, 4, 8, 9
SHF_WRITE, SHF_ALLOC, SHF_EXECINSTR = 0x1, 0x2, 0x4
EF_RISCV_RVC, EF_RISCV_FLOAT_ABI = 0x1, 0x6

RELOC_NAMES = {16: "R_RISCV_BRANCH", 17: "R_RISCV_JAL", 18: "R_RISCV_CALL", 19: "R_RISCV_CALL_PLT",
               20: "R_RISCV_GOT_HI20", 23: "R_RISCV_PCREL_HI20", 24: "R_RISCV_PCREL_LO12_I",
               25: "R_RISCV_PCREL_LO12_S", 26: "R_RISCV_HI20", 27: "R_RISCV_LO12_I",
               28: "R_RISCV_LO12_S", 43: "R_RISCV_ALIGN", 44: "R_RISCV_RVC_BRANCH",
               45: "R_RISCV_RVC_JUMP", 51: "R_RISCV_RELAX"}


def legal(w):
    """Check if instruction word is supported by ooo_decode."""
    op, f3, f7 = w & 0x7F, (w >> 12) & 7, w >> 25
    if op in (0x37, 0x6F):                       # LUI, JAL
        return True
    if op == 0x67:                               # JALR
        return f3 == 0
    if op == 0x63:                               # branches
        return f3 not in (2, 3)
    if op == 0x03:                               # loads
        return f3 in (0, 1, 2, 4, 5)
    if op == 0x23:                               # stores
        return f3 in (0, 1, 2)
    if op == 0x13:                               # ALU immediate
        if f3 == 1:
            return f7 == 0
        if f3 == 5:
            return f7 in (0, 0x20)
        return True
    if op == 0x33:                               # ALU register, RV32M
        return f7 in (0, 1) or (f7 == 0x20 and f3 in (0, 5))
    return False


class ElfError(Exception):
    pass


def sections(data):
    if data[:4] != b"\x7fELF":
        raise ElfError("not an ELF file")
    if data[4] != 1 or data[5] != 1:
        raise ElfError("not ELF32 little-endian")
    (e_type, e_machine, _, _, _, e_shoff, e_flags, _, _, _, e_shentsize, e_shnum,
     e_shstrndx) = struct.unpack_from("<HHIIIIIHHHHHH", data, 16)
    if e_shoff == 0 or e_shentsize != 40:
        raise ElfError("no section header table")
    secs = []
    for i in range(e_shnum):
        f = struct.unpack_from("<IIIIIIIIII", data, e_shoff + 40 * i)
        secs.append(dict(name_off=f[0], type=f[1], flags=f[2], addr=f[3], offset=f[4],
                         size=f[5], link=f[6], info=f[7], entsize=f[9]))
    strtab = secs[e_shstrndx]
    for s in secs:
        o = strtab["offset"] + s["name_off"]
        s["name"] = data[o:data.index(b"\0", o)].decode(errors="replace")
    return e_machine, e_flags, secs


def symbol(data, secs, wanted):
    for s in secs:
        if s["type"] != SHT_SYMTAB:
            continue
        strs = secs[s["link"]]
        for i in range(s["size"] // 16):
            name, value, size, info, other, shndx = struct.unpack_from("<IIIBBH", data, s["offset"] + 16 * i)
            o = strs["offset"] + name
            if data[o:data.index(b"\0", o)].decode(errors="replace") == wanted:
                return value, shndx
    return None


def check(path):
    data = open(path, "rb").read()
    machine, flags, secs = sections(data)
    errors = []
    if machine != EM_RISCV:
        errors.append(f"e_machine {machine} is not RISC-V ({EM_RISCV})")
    if flags & EF_RISCV_RVC:
        errors.append("compressed instructions enabled (EF_RISCV_RVC): build with -march=rv32i or rv32im, no 'c'")
    if flags & EF_RISCV_FLOAT_ABI:
        errors.append("hard-float ABI: build with -mabi=ilp32")
    for s in secs:
        if s["type"] in (SHT_REL, SHT_RELA) and s["size"]:
            ent = 8 if s["type"] == SHT_REL else 12
            kinds = {}
            for i in range(s["size"] // ent):
                r_info = struct.unpack_from("<I", data, s["offset"] + ent * i + 4)[0]
                t = RELOC_NAMES.get(r_info & 0xFF, f"type {r_info & 0xFF}")
                kinds[t] = kinds.get(t, 0) + 1
            errors.append(f"{s['name']}: {s['size'] // ent} relocation(s) "
                          + ", ".join(f"{k} x{v}" for k, v in sorted(kinds.items()))
                          + " (F3: no calls, no globals; RV32M needs -march=rv32im; build with -mno-relax)")
        if s["flags"] & SHF_ALLOC and s["flags"] & SHF_WRITE and s["size"]:
            errors.append(f"{s['name']}: {s['size']} bytes of writable data (F2: data_mem never loads dmem.hex; no globals)")
    text = [(i, s) for i, s in enumerate(secs) if s["flags"] & SHF_EXECINSTR and s["size"]]
    if not text:
        errors.append("no executable section")
    n_words = 0
    for _, s in text:
        if s["size"] % 4:
            errors.append(f"{s['name']}: size {s['size']} is not a multiple of 4")
        for off in range(0, s["size"] - s["size"] % 4, 4):
            w = struct.unpack_from("<I", data, s["offset"] + off)[0]
            n_words += 1
            if not legal(w):
                errors.append(f"{s['name']}+{off:#x}: {w:08x} is not a supported RV32IM instruction (opcode {w & 0x7F:#04x})")
    main = symbol(data, secs, "main")
    if main is None:
        errors.append("no symbol 'main'")
    elif text and (main[1] != text[0][0] or main[0] != 0):
        errors.append(f"main is at {secs[main[1]]['name'] if main[1] < len(secs) else main[1]}+{main[0]:#x}; "
                      f"it must be at offset 0 of {text[0][1]['name']} (the core starts at pc 0)")
    return n_words, errors


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    status = 0
    for path in argv[1:]:
        try:
            n, errors = check(path)
        except (ElfError, OSError, struct.error, ValueError, IndexError) as e:
            print(f"{path}: ERROR {e}")
            status = max(status, 2)
            continue
        if errors:
            print(f"{path}: REJECTED ({len(errors)} problem(s))")
            for e in errors[:50]:
                print("  " + e)
            status = max(status, 1)
        else:
            print(f"{path}: OK ({n} instructions, no relocations, no data)")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
