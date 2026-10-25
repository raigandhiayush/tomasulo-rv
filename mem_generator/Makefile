#//////////////////////////////////////////////////////
#/////////////////INCLUDING CROSS-COMPILER/////////////

CC      = riscv-none-elf-gcc
AR      = riscv-none-elf-ar
OBJDUMP = riscv-none-elf-objdump
OBJCOPY = riscv-none-elf-objcopy
READELF = riscv-none-elf-readelf


#///// flags for RV32i architecture///////////////////
CFLAGS  = -march=rv32i -mabi=ilp32


#////Source for c code file ///////////////////////////
SRC_ADDITION     = code_addition.c
SRC_SORT     = code_sort.c
SRC_NEGATIVE = code_negative.c
SRC_XOR = code_xor.c

TARGET   = code.elf

# python3 on Linux, python on Windows (override: make PY=...)
PY      ?= $(if $(filter Windows_NT,$(OS)),python,python3)

.PHONY: all clean

#/// generating .text file of code cross-compiled from highlevel-c code to risc-v code
# ////////////// Copying and converting the text file into binary files
#/////// Python script to convert the binary files into the required hex files

addition: $(SRC_ADDITION)
	$(CC) -c  $(SRC_ADDITION) -o $(TARGET) $(CFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && $(PY) bin2hex.py

sort: $(SRC_SORT)
	$(CC) -c  $(SRC_SORT) -o $(TARGET) $(CFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && $(PY) bin2hex.py

negative: $(SRC_NEGATIVE)
	$(CC) -c  $(SRC_NEGATIVE) -o $(TARGET) $(CFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && $(PY) bin2hex.py

xor : $(SRC_XOR)
	$(CC) -c $(SRC_XOR) -o $(TARGET) $(CFLAGS)
	$(OBJCOPY) -O binary $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && $(PY) bin2hex.py

#//////////////////////////////////////////////////////
#///// D8 workloads (PROJECT_BLUEPRINT.md 6.17; owner D, reviewer E)
#///// make <prog>_d8     : -march=rv32i  (baseline and OoO, comparison D17)
#///// make <prog>_d8_im  : -march=rv32im (OoO only; RV32M workloads)
#///// -mno-relax lets the assembler resolve local branches, so the object
#///// has no relocations; tools/check_elf.py rejects the build otherwise (F3).
#///// Only .text goes into imem (the core starts at pc 0 = main).
D8_PROGS  = addition sort negative xor
D8_CFLAGS = -mabi=ilp32 -mno-relax -O0
CHECK_ELF = $(PY) ../tools/check_elf.py

define D8_BUILD
	$(CC) -c $(1) -o $(TARGET) -march=$(2) $(D8_CFLAGS)
	$(CHECK_ELF) $(TARGET)
	$(OBJCOPY) -O binary -j .text $(TARGET) ./imem_dmem/imem.bin
	$(OBJCOPY) -j .data -O binary $(TARGET) ./imem_dmem/dmem.bin
	$(OBJDUMP) -d $(TARGET) > ./imem_dmem/code.dis
	cd imem_dmem && $(PY) bin2hex.py
endef

%_d8_im: code_%_d8.c
	$(call D8_BUILD,$<,rv32im)

#///// RV32M workloads: make mul_d8_im, div_d8_im, rv32m_d8_im (OoO only).
#///// They have no rv32i build: gcc would call __mulsi3/__divsi3 (F2/F3),
#///// so the explicit rules below stop make <prog>_d8 before the pattern rule.
D8_M_PROGS = mul div rv32m
.PHONY: $(addsuffix _d8,$(D8_M_PROGS))

$(addsuffix _d8,$(D8_M_PROGS)):
	@echo "$@: RV32M workload, no rv32i build (gcc would call libgcc). Use: make $@_im"; exit 1

%_d8: code_%_d8.c
	$(call D8_BUILD,$<,rv32i)

# /////clean function
clean:
	$(RM) $(TARGET) ./imem_dmem/imem.bin ./imem_dmem/imem.hex ./imem_dmem/dmem.bin ./imem_dmem/dmem.hex ./imem_dmem/code.dis
