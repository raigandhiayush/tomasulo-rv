// ---------------------------------------------------------------------------
// ooo_defs.vh  --  shared constants for TOMA-RV
// Owner: A (interface owner).  Do not edit without telling A.
//
// Status: complete against PROJECT_BLUEPRINT v0.3 (sec. 3.1 D1-D20, 3.4, 5)
// and SIGNALS_REFERENCE v0.3. Prepared by B on 20 Oct 2026 in place of the
// earlier temporary copy; signed off by A on 20 Oct 2026 (iface-v1 tag pending).
//
// Usage:   `include "ooo_defs.vh"     (compile with -I ooo_rtl)
//          input [`ROB_W-1:0] tag;     bus k tag = cdb_tag[k*`ROB_W +: `ROB_W]
// Never hard-code 8 / 3 / 4 for these meanings (ROB 8/16 sweep, goal G2).
// ---------------------------------------------------------------------------
`ifndef OOO_DEFS_VH
`define OOO_DEFS_VH

// ---- ROB and tags (D1, D2) ------------------------------------------------
`define ROB_N        8          // ROB entries
`define ROB_W        3          // tag width = log2(ROB_N); ROB entry number
`define ROB_CNT_W    (`ROB_W+1) // rob_count width: holds 0..ROB_N

// ---- Common Data Buses (D6, D14) ------------------------------------------
`define NCDB         4          // four buses, one per functional unit
`define CDB_ALU      0          // bus 0: ALU / branch / JALR
`define CDB_MUL      1          // bus 1: multiplier
`define CDB_DIV      2          // bus 2: divider
`define CDB_LSU      3          // bus 3: load/store unit
// packed vectors: cdb_valid[`NCDB-1:0]
//                 cdb_tag  [`NCDB*`ROB_W-1:0]  (bus k in slice k)
//                 cdb_value[`NCDB*`XLEN-1:0]   (bus k in slice k)

// ---- Datapath and field widths ----------------------------------------------
`define XLEN         32         // register / bus value width
`define REG_W        5          // architectural register number (x0..x31)
`define NREG         32         // architectural registers (x0 hard-wired 0)
`define OP_W         8          // rs_al_op / iss_op width (D16)
`define CLS_W        3          // ooo_decode.cls width
`define KIND_W       2          // rob_al_kind width
`define F3_W         3          // funct3 width

// ---- Structure sizes (D3, D5) ---------------------------------------------
`define RS_ALU_N     3          // ALU/branch reservation stations
`define RS_MUL_N     2          // MUL reservation stations
`define RS_DIV_N     1          // DIV reservation station
`define LSQ_N        4          // load/store queue entries
`define IQ_DEPTH     4          // instruction queue entries (no bypass)

// ---- Instruction classes (ooo_decode.cls) ---------------------------------
`define CLS_ALU      3'd0
`define CLS_MUL      3'd1
`define CLS_DIV      3'd2
`define CLS_LD       3'd3
`define CLS_ST       3'd4
`define CLS_BR       3'd5       // conditional branches and JALR
`define CLS_PRE      3'd6       // LUI, JAL (AUIPC at goal level): ready at dispatch
`define CLS_NOP      3'd7       // illegal / unsupported: ready at dispatch, sets exception

// ---- ROB entry kind (rob_al_kind) -----------------------------------------
`define KIND_VALUE   2'd0       // normal result (also CLS_PRE, CLS_NOP)
`define KIND_STORE   2'd1
`define KIND_BRANCH  2'd2       // branch / JALR

// ---- rs_al_op encoding (D16) ----------------------------------------------
//   [2:0] funct3   [3] sub/sra   [4] is_branch   [5] is_jalr   [7:6] = 0
//   MUL / DIV units use op[1:0]
`define OP_F3_HI     2
`define OP_F3_LO     0
`define OP_ALT_BIT   3          // SUB / SRA(I)
`define OP_BR_BIT    4          // conditional branch
`define OP_JALR_BIT  5          // JALR
`define OP_MD_HI     1          // MUL/DIV sub-operation = op[`OP_MD_HI:0]
`define OP_PRED_BIT  6          // conditional branch was predicted taken (SPEC_EN)

// ---- MUL / DIV sub-operation (funct3[1:0]) --------------------------------
`define MUL_MUL      2'b00
`define MUL_MULH     2'b01
`define MUL_MULHSU   2'b10
`define MUL_MULHU    2'b11
`define DIV_DIV      2'b00
`define DIV_DIVU     2'b01
`define DIV_REM      2'b10
`define DIV_REMU     2'b11

// ---- Load / store funct3 (size and signedness) ----------------------------
`define F3_LB        3'b000
`define F3_LH        3'b001
`define F3_LW        3'b010
`define F3_LBU       3'b100
`define F3_LHU       3'b101
`define F3_SB        3'b000
`define F3_SH        3'b001
`define F3_SW        3'b010

// ---- Reset PC and MMIO (rule 13, D8, D20) ---------------------------------
`define RESET_PC     32'h0000_0000
`define MMIO_RESULT  32'h1000_0000   // store: publish result
`define MMIO_DONE    32'h1000_0004   // store: set done
`define MMIO_SWITCH  32'h1000_0008   // load : read switches
// MMIO decode = addr[31:28] == 4'h1; MMIO stores never write data_mem (D20)

// ---- L1 data cache (l1_dcache.v, instantiated in ooo_core) -----------------
// Defaults; each can be overridden on the command line (iverilog -DDC_WB=1)
// for configuration sweeps.
`ifndef DC_EN
`define DC_EN        1          // 0 = no cache: LSU talks to data_mem directly
`endif
`ifndef DC_WAYS
`define DC_WAYS      2          // 1 (direct-mapped) or 2 (2-way, LRU bit per set)
`endif
`ifndef DC_SETS
`define DC_SETS      8          // sets per way (power of 2)
`endif
`ifndef DC_WORDS
`define DC_WORDS     4          // 32-bit words per line: 4 (16 B) or 8 (32 B)
`endif
`ifndef DC_WB
`define DC_WB        1          // 1 = write-back, write-allocate (dirty bit per line)
`endif                          // 0 = write-through, no-write-allocate
`define DC_MEM_AW    12         // byte-address bits decoded by data_mem (4 KB, aliases above)

// ---- Branch speculation -----------------------------------------------------
`ifndef SPEC_EN
`define SPEC_EN      1          // 0 = no speculation: dispatch holds after each branch
`endif
`ifndef BTB_N
`define BTB_N        16         // branch target buffer entries (power of 2)
`endif
`ifndef BHT_N
`define BHT_N        64         // 2-bit counters (power of 2)
`endif
`define BR_CKPT_N    `RS_ALU_N  // RAT checkpoints; an unresolved branch holds an ALU RS

// ---- Data memory access time (mem_wait.v, board top) -------------------------
`ifndef MEM_WAIT
`define MEM_WAIT     10         // extra cycles for a non-sequential access; 0 = data_mem as is
`endif
`ifndef MEM_WBUF_N
`define MEM_WBUF_N   4          // write buffer entries
`endif

`endif // OOO_DEFS_VH
