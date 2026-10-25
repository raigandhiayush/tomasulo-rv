// ooo_defs.vh -- Shared architecture parameters and constants for TOMA-RV.
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

`endif // OOO_DEFS_VH
