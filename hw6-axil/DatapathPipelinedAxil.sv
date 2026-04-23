`timescale 1ns / 1ns

`define REG_SIZE 31:0
`define INSN_SIZE 31:0
`define OPCODE_SIZE 6:0
`define ADDR_WIDTH 32
`define DATA_WIDTH 32

`ifndef DIVIDER_STAGES
`define DIVIDER_STAGES 8
`endif

`ifndef SYNTHESIS
  `include "../hw3-singlecycle/RvDisassembler.sv"
`endif
`include "../hw2b-cla/CarryLookaheadAdder.sv"
`include "../hw3-singlecycle/cycle_status.sv"
`include "../hw4-multicycle/DividerUnsignedPipelined.sv"
`include "EasyAxilMemory.sv"

module Disasm #(
    PREFIX = "D"
) (
    input wire [31:0] insn,
    output wire [(8*32)-1:0] disasm
);
`ifndef RISCV_FORMAL
`ifndef SYNTHESIS
  string disasm_string;
  always_comb begin
    disasm_string = rv_disasm(insn);
  end
  genvar i;
  for (i = 3; i < 32; i = i + 1) begin : gen_disasm
    assign disasm[((i+1-3)*8)-1-:8] = disasm_string[31-i];
  end
  assign disasm[255-:8] = PREFIX;
  assign disasm[247-:8] = ":";
  assign disasm[239-:8] = " ";
`endif
`endif
endmodule

// ---------------------------------------------------------------
//  Register file
// ---------------------------------------------------------------
module RegFile (
    input  logic [ 4:0] rd,
    input  logic [`REG_SIZE] rd_data,
    input  logic [ 4:0] rs1,
    output logic [`REG_SIZE] rs1_data,
    input  logic [ 4:0] rs2,
    output logic [`REG_SIZE] rs2_data,
    input  logic clk,
    input  logic we,
    input  logic rst
);
  localparam int NumRegs = 32;
  logic [`REG_SIZE] regs[NumRegs];

  assign rs1_data = (rs1 == 5'd0)                  ? '0 :
                    (we && rd == rs1 && rd != 5'd0) ? rd_data :
                    regs[rs1];
  assign rs2_data = (rs2 == 5'd0)                  ? '0 :
                    (we && rd == rs2 && rd != 5'd0) ? rd_data :
                    regs[rs2];

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < NumRegs; i++) regs[i] <= '0;
    end else if (we && rd != 5'd0) begin
      regs[rd] <= rd_data;
    end
  end
endmodule

// ---------------------------------------------------------------
//  Pipeline stage structs
// ---------------------------------------------------------------

// G stage: holds the PC that was sent on ARADDR last cycle.
// The matching RDATA arrives from imem this cycle (1-cycle latency).
typedef struct packed {
  logic [`REG_SIZE]  pc;           // PC of the in-flight request
  cycle_status_e     cycle_status;
} stage_gfetch_t;

// D stage: PC + instruction word
typedef struct packed {
  logic [`REG_SIZE]  pc;
  logic [`INSN_SIZE] insn;
  cycle_status_e     cycle_status;
} stage_decode_t;

// X stage: decoded operands / immediates
typedef struct packed {
  logic [`REG_SIZE]  pc;
  logic [`INSN_SIZE] insn;
  cycle_status_e     cycle_status;
  logic [`REG_SIZE]  rs1_data;
  logic [`REG_SIZE]  rs2_data;
  logic [ 4:0]       rs1;
  logic [ 4:0]       rs2;
  logic [ 4:0]       rd;
  logic [`REG_SIZE]  imm_i_sext;
  logic [`REG_SIZE]  imm_s_sext;
  logic [`REG_SIZE]  imm_b_sext;
  logic [`REG_SIZE]  imm_j_sext;
  logic [ 4:0]       imm_shamt;
} stage_execute_t;

// M stage: ALU result + control
typedef struct packed {
  logic [`REG_SIZE]  pc;
  logic [`INSN_SIZE] insn;
  cycle_status_e     cycle_status;
  logic [`REG_SIZE]  alu_result;
  logic [ 4:0]       rd;
  logic              rf_we;
  logic              halt;
} stage_memory_t;

// W stage: writeback
typedef struct packed {
  logic [`REG_SIZE]  pc;
  logic [`INSN_SIZE] insn;
  cycle_status_e     cycle_status;
  logic [`REG_SIZE]  rd_data;
  logic [ 4:0]       rd;
  logic              rf_we;
  logic              halt;
} stage_writeback_t;

// ---------------------------------------------------------------
//  DatapathPipelinedAxil
// ---------------------------------------------------------------
module DatapathPipelinedAxil (
    input wire clk,
    input wire rst,

    axil_if.manager imem,
    axil_if.manager dmem,

    output logic halt,

    output logic [`REG_SIZE]  trace_completed_pc,
    output logic [`INSN_SIZE] trace_completed_insn,
    output cycle_status_e     trace_completed_cycle_status
);

  localparam bit [`OPCODE_SIZE] OpcodeLoad    = 7'b00_000_11;
  localparam bit [`OPCODE_SIZE] OpcodeStore   = 7'b01_000_11;
  localparam bit [`OPCODE_SIZE] OpcodeBranch  = 7'b11_000_11;
  localparam bit [`OPCODE_SIZE] OpcodeJalr    = 7'b11_001_11;
  localparam bit [`OPCODE_SIZE] OpcodeMiscMem = 7'b00_011_11;
  localparam bit [`OPCODE_SIZE] OpcodeJal     = 7'b11_011_11;
  localparam bit [`OPCODE_SIZE] OpcodeRegImm  = 7'b00_100_11;
  localparam bit [`OPCODE_SIZE] OpcodeRegReg  = 7'b01_100_11;
  localparam bit [`OPCODE_SIZE] OpcodeEnviron = 7'b11_100_11;
  localparam bit [`OPCODE_SIZE] OpcodeAuipc   = 7'b00_101_11;
  localparam bit [`OPCODE_SIZE] OpcodeLui     = 7'b01_101_11;

  logic [`REG_SIZE] cycles_current;
  always_ff @(posedge clk) begin
    if (rst) cycles_current <= 0;
    else     cycles_current <= cycles_current + 1;
  end

  // ===================================================================
  //  Forward declarations
  // ===================================================================
  logic             x_redirect_valid;
  logic [`REG_SIZE] x_redirect_pc;
  logic             div_stall;

  wire              wb_rf_we;
  wire [ 4:0]       wb_rd;
  wire [`REG_SIZE]  wb_rd_data;

  wire              m_rf_we;
  wire [ 4:0]       m_rd;
  wire [`REG_SIZE]  m_alu_result;
  logic [`REG_SIZE] m_rd_data;

  logic stall_f;
  logic stall_g;
  logic stall_d;
  logic flush_g;
  logic flush_d;
  logic flush_x;

  // ===================================================================
  //  FETCH  (F)
  //
  //  f_pc_current is the PC currently being presented on ARADDR.
  //  On each non-stalled posedge, F advances to the next PC.
  //
  //  Key insight for PC/RDATA alignment:
  //    Edge N:   F presents ARADDR = PC_A  (f_pc_current = PC_A)
  //              At this same edge, f_pc_current advances to PC_B
  //    Edge N+1: imem.RDATA = insn(PC_A)   [1-cycle memory latency]
  //              G needs to know the response is for PC_A, not PC_B.
  //
  //  So G must capture the PC that was on ARADDR *before* F advanced,
  //  i.e. the old f_pc_current value — which means G latches the
  //  pre-increment value. We accomplish this by having G sample
  //  f_pc_current on the same posedge that F advances, before F's
  //  always_ff updates f_pc_current. Since always_ff blocks see the
  //  old register value, gfetch_state.pc = old f_pc_current = PC_A,
  //  which correctly pairs with RDATA = insn(PC_A) arriving next cycle.
  // ===================================================================
  logic [`REG_SIZE] f_pc_current;
  cycle_status_e    f_cycle_status;

  always_ff @(posedge clk) begin
    if (rst) begin
      f_pc_current   <= 32'd0;
      f_cycle_status <= CYCLE_NO_STALL;
    end else if (!stall_f) begin
      f_cycle_status <= CYCLE_NO_STALL;
      if (x_redirect_valid)
        f_pc_current <= x_redirect_pc;
      else
        f_pc_current <= f_pc_current + 4;
    end
  end

  // ARVALID: assert when F is not stalled and no branch resolves this cycle.
  // When stall_f=1, the AR was already sent last cycle — do NOT re-send.
  // When x_redirect_valid=1, f_pc_current is about to change — don't send
  // the old (wrong) PC; the new PC will be sent next cycle.
  assign imem.ARVALID = !rst && !stall_f && !x_redirect_valid;
  assign imem.ARADDR  = f_pc_current;
  assign imem.ARPROT  = 3'd0;

  // RREADY: de-assert when G is stalled so the memory holds RDATA for us
  assign imem.RREADY  = !stall_g;

  assign imem.AWVALID = 1'b0;
  assign imem.AWADDR  = '0;
  assign imem.AWPROT  = 3'd0;
  assign imem.WVALID  = 1'b0;
  assign imem.WDATA   = '0;
  assign imem.WSTRB   = 4'd0;
  assign imem.BREADY  = 1'b1;

  // ===================================================================
  //  G STAGE  (Going-to-insn-memory)
  //
  //  Timing with 1-cycle memory latency:
  //    Edge N:   ARVALID=1, ARADDR=PC_A
  //              G latches: pc = f_pc_current (old) = PC_A
  //                         (F hasn't updated yet — always_ff sees old value)
  //    Edge N+1: imem.RDATA = insn(PC_A), RVALID=1
  //              D latches: {pc=PC_A, insn=imem.RDATA}  ← correctly paired
  //
  //  This works because all always_ff blocks in a single posedge see the
  //  register values from BEFORE that edge. So when F's block runs and
  //  writes f_pc_current <= f_pc_current + 4, G's block simultaneously
  //  reads the old f_pc_current (= PC_A) — the PC we just sent.
  // ===================================================================
  stage_gfetch_t gfetch_state;

  always_ff @(posedge clk) begin
    if (rst) begin
      gfetch_state <= '{pc: 0, cycle_status: CYCLE_RESET};
    end else if (flush_g) begin
      gfetch_state <= '{pc: 0, cycle_status: CYCLE_TAKEN_BRANCH};
    end else if (!stall_g) begin
      // Capture the PC currently on ARADDR (old f_pc_current before F advances)
      gfetch_state <= '{pc: f_pc_current, cycle_status: f_cycle_status};
    end
  end

  wire [255:0] g_disasm;
  Disasm #(.PREFIX("G")) disasm_gfetch (
      .insn(imem.RVALID ? imem.RDATA : 32'd0),
      .disasm(g_disasm)
  );

  // ===================================================================
  //  DECODE  (D)
  //
  //  When G advances (stall_g=0, flush_g=0), imem.RDATA contains the
  //  instruction for gfetch_state.pc (which was the PC on ARADDR when
  //  G was last loaded, i.e. one cycle ago). The pairing is:
  //    gfetch_state.pc  = PC_A   (set at edge N)
  //    imem.RDATA       = insn(PC_A)  (valid at edge N+1)
  //  D latches both together.
  // ===================================================================
  stage_decode_t decode_state;

  always_ff @(posedge clk) begin
    if (rst) begin
      decode_state <= '{pc: 0, insn: 0, cycle_status: CYCLE_RESET};
    end else if (flush_d) begin
      decode_state <= '{pc: 0, insn: 0, cycle_status: CYCLE_TAKEN_BRANCH};
    end else if (!stall_d) begin
      decode_state <= '{
        pc:           gfetch_state.pc,
        insn:         imem.RDATA,        // response to gfetch_state.pc's AR
        cycle_status: gfetch_state.cycle_status
      };
    end
  end

  wire [255:0] d_disasm;
  Disasm #(.PREFIX("D")) disasm_decode (
      .insn(decode_state.insn),
      .disasm(d_disasm)
  );

  // Decode fields
  wire [ 6:0] d_funct7 = decode_state.insn[31:25];
  wire [ 4:0] d_rs2    = decode_state.insn[24:20];
  wire [ 4:0] d_rs1    = decode_state.insn[19:15];
  wire [ 2:0] d_funct3 = decode_state.insn[14:12];
  wire [ 4:0] d_rd     = decode_state.insn[11: 7];
  wire [`OPCODE_SIZE] d_opcode = decode_state.insn[6:0];

  wire [11:0] d_imm_i     = decode_state.insn[31:20];
  wire [ 4:0] d_imm_shamt = decode_state.insn[24:20];

  wire [11:0] d_imm_s;
  assign d_imm_s[11:5] = d_funct7;
  assign d_imm_s[ 4:0] = d_rd;

  wire [12:0] d_imm_b;
  assign {d_imm_b[12], d_imm_b[10:5]} = d_funct7;
  assign {d_imm_b[ 4:1], d_imm_b[11]} = d_rd;
  assign d_imm_b[0] = 1'b0;

  wire [20:0] d_imm_j;
  assign {d_imm_j[20], d_imm_j[10:1], d_imm_j[11], d_imm_j[19:12], d_imm_j[0]} =
         {decode_state.insn[31:12], 1'b0};

  wire [`REG_SIZE] d_imm_i_sext = {{20{d_imm_i[11]}},   d_imm_i};
  wire [`REG_SIZE] d_imm_s_sext = {{20{d_imm_s[11]}},   d_imm_s};
  wire [`REG_SIZE] d_imm_b_sext = {{19{d_imm_b[12]}},   d_imm_b};
  wire [`REG_SIZE] d_imm_j_sext = {{11{d_imm_j[20]}},   d_imm_j};

  wire [`REG_SIZE] d_rs1_data, d_rs2_data;
  RegFile rf (
      .clk(clk), .rst(rst),
      .we(wb_rf_we), .rd(wb_rd), .rd_data(wb_rd_data),
      .rs1(d_rs1), .rs1_data(d_rs1_data),
      .rs2(d_rs2), .rs2_data(d_rs2_data)
  );

  // ===================================================================
  //  EXECUTE  (X)
  // ===================================================================
  stage_execute_t execute_state;

  wire [`OPCODE_SIZE] x_opcode = execute_state.insn[6:0];
  wire [ 6:0]         x_funct7 = execute_state.insn[31:25];
  wire [ 2:0]         x_funct3 = execute_state.insn[14:12];

    // ---- Divider --------------------------------------------------------
  wire x_is_divide = (x_opcode == OpcodeRegReg) &&
                     (x_funct7 == 7'd1) &&
                     (x_funct3[2] == 1'b1);

  logic [`DIVIDER_STAGES-2:0] div_pipe_valid;

  always_comb begin
    div_stall = x_is_divide && !div_pipe_valid[`DIVIDER_STAGES-2];
  end

  always_ff @(posedge clk) begin
    if (rst || !x_is_divide)
      div_pipe_valid <= '0;
    else
      div_pipe_valid <= {div_pipe_valid[`DIVIDER_STAGES-3:0], 1'b1};
  end

  // ---- MX / WX forwarding (MX uses m_rd_data for correct load bypass) --
  logic [`REG_SIZE] x_rs1_fwd, x_rs2_fwd;
  always_comb begin
    if (m_rf_we && m_rd != 5'd0 && m_rd == execute_state.rs1)
      x_rs1_fwd = m_rd_data;
    else if (wb_rf_we && wb_rd != 5'd0 && wb_rd == execute_state.rs1)
      x_rs1_fwd = wb_rd_data;
    else
      x_rs1_fwd = execute_state.rs1_data;

    if (m_rf_we && m_rd != 5'd0 && m_rd == execute_state.rs2)
      x_rs2_fwd = m_rd_data;
    else if (wb_rf_we && wb_rd != 5'd0 && wb_rd == execute_state.rs2)
      x_rs2_fwd = wb_rd_data;
    else
      x_rs2_fwd = execute_state.rs2_data;
  end

  // ---- Divider operand latching ---------------------------------------
  logic [`REG_SIZE] div_op_a_reg, div_op_b_reg;
  logic             div_rs1_neg, div_rs2_neg;
  logic             div_rs2_zero;
  logic [`REG_SIZE] div_rs1_orig;
  logic             div_ops_latched;

  wire div_is_signed = (x_funct3[1:0] == 2'b00 || x_funct3[1:0] == 2'b10);

  wire [`REG_SIZE] div_op_a_fresh = div_is_signed ?
      (x_rs1_fwd[31] ? (~x_rs1_fwd + 32'd1) : x_rs1_fwd) : x_rs1_fwd;
  wire [`REG_SIZE] div_op_b_fresh = div_is_signed ?
      (x_rs2_fwd[31] ? (~x_rs2_fwd + 32'd1) : x_rs2_fwd) : x_rs2_fwd;

  wire [`REG_SIZE] div_op_a = div_ops_latched ? div_op_a_reg : div_op_a_fresh;
  wire [`REG_SIZE] div_op_b = div_ops_latched ? div_op_b_reg : div_op_b_fresh;

  always_ff @(posedge clk) begin
    if (rst || !x_is_divide || !div_stall) begin
      div_op_a_reg    <= '0;
      div_op_b_reg    <= '0;
      div_rs1_neg     <= 1'b0;
      div_rs2_neg     <= 1'b0;
      div_rs2_zero    <= 1'b0;
      div_rs1_orig    <= '0;
      div_ops_latched <= 1'b0;
    end else if (!div_ops_latched) begin
      div_op_a_reg    <= div_op_a_fresh;
      div_op_b_reg    <= div_op_b_fresh;
      div_rs1_neg     <= x_rs1_fwd[31];
      div_rs2_neg     <= x_rs2_fwd[31];
      div_rs2_zero    <= (x_rs2_fwd == 32'd0);
      div_rs1_orig    <= x_rs1_fwd;
      div_ops_latched <= 1'b1;
    end
  end

  wire [`REG_SIZE] div_quotient, div_remainder;
  DividerUnsignedPipelined divider_inst (
      .clk(clk), .rst(rst), .stall(1'b0),
      .i_dividend(div_op_a),
      .i_divisor (div_op_b),
      .o_quotient(div_quotient),
      .o_remainder(div_remainder)
  );

  // ---- CLA adder ------------------------------------------------------
  logic [`REG_SIZE] cla_a, cla_b, cla_sum;
  logic             cla_cin;
  CarryLookaheadAdder cla_inst (
      .a(cla_a), .b(cla_b), .cin(cla_cin), .sum(cla_sum)
  );

  // ---- Execute combinational ------------------------------------------
  logic [`REG_SIZE] x_alu_result;
  logic             x_rf_we;
  logic             x_branch_taken;
  logic [`REG_SIZE] x_branch_target;
  logic             x_halt;
  logic [`REG_SIZE] x_store_data;
  cycle_status_e    x_cycle_status_out;

  always_comb begin
    x_alu_result       = 32'd0;
    x_rf_we            = 1'b0;
    x_branch_taken     = 1'b0;
    x_branch_target    = execute_state.pc + 32'd4;
    x_halt             = 1'b0;
    x_store_data       = x_rs2_fwd;
    x_cycle_status_out = execute_state.cycle_status;

    cla_a   = 32'd0;
    cla_b   = 32'd0;
    cla_cin = 1'b0;

    if (div_stall) x_cycle_status_out = CYCLE_DIV;

    case (x_opcode)
      OpcodeLui: begin
        x_alu_result = {execute_state.insn[31:12], 12'b0};
        x_rf_we = 1'b1;
      end
      OpcodeAuipc: begin
        x_alu_result = execute_state.pc + {execute_state.insn[31:12], 12'b0};
        x_rf_we = 1'b1;
      end
      OpcodeRegImm: begin
        x_rf_we = 1'b1;
        case (x_funct3)
          3'b000: begin
            cla_a = x_rs1_fwd; cla_b = execute_state.imm_i_sext; cla_cin = 1'b0;
            x_alu_result = cla_sum;
          end
          3'b010: x_alu_result = ($signed(x_rs1_fwd) < $signed(execute_state.imm_i_sext)) ? 32'd1 : 32'd0;
          3'b011: x_alu_result = (x_rs1_fwd < execute_state.imm_i_sext) ? 32'd1 : 32'd0;
          3'b100: x_alu_result = x_rs1_fwd ^ execute_state.imm_i_sext;
          3'b110: x_alu_result = x_rs1_fwd | execute_state.imm_i_sext;
          3'b111: x_alu_result = x_rs1_fwd & execute_state.imm_i_sext;
          3'b001: x_alu_result = x_rs1_fwd << execute_state.imm_shamt;
          3'b101: begin
            if (x_funct7 == 7'b0000000) x_alu_result = x_rs1_fwd >> execute_state.imm_shamt;
            else                         x_alu_result = $signed(x_rs1_fwd) >>> execute_state.imm_shamt;
          end
          default: x_rf_we = 1'b0;
        endcase
      end
      OpcodeRegReg: begin
        case (x_funct3)
          3'b000: begin
            if (x_funct7 == 7'd1) begin
              x_alu_result = x_rs1_fwd * x_rs2_fwd; x_rf_we = 1'b1;
            end else if (x_funct7 == 7'd0) begin
              cla_a = x_rs1_fwd; cla_b = x_rs2_fwd; cla_cin = 1'b0;
              x_alu_result = cla_sum; x_rf_we = 1'b1;
            end else begin
              cla_a = x_rs1_fwd; cla_b = ~x_rs2_fwd; cla_cin = 1'b1;
              x_alu_result = cla_sum; x_rf_we = 1'b1;
            end
          end
          3'b001: begin
            if (x_funct7 == 7'd1) begin
              x_alu_result = 32'($signed(($signed({{32{x_rs1_fwd[31]}}, x_rs1_fwd}) *
                             $signed({{32{x_rs2_fwd[31]}}, x_rs2_fwd}))) >>> 32);
              x_rf_we = 1'b1;
            end else begin
              x_alu_result = x_rs1_fwd << x_rs2_fwd[4:0]; x_rf_we = 1'b1;
            end
          end
          3'b010: begin
            if (x_funct7 == 7'd1) begin
              x_alu_result = 32'($signed(($signed({{32{x_rs1_fwd[31]}}, x_rs1_fwd}) *
                             {32'd0, x_rs2_fwd})) >>> 32);
              x_rf_we = 1'b1;
            end else begin
              x_alu_result = ($signed(x_rs1_fwd) < $signed(x_rs2_fwd)) ? 32'd1 : 32'd0;
              x_rf_we = 1'b1;
            end
          end
          3'b011: begin
            if (x_funct7 == 7'd1) begin
              x_alu_result = 32'(({32'd0, x_rs1_fwd} * {32'd0, x_rs2_fwd}) >> 32);
              x_rf_we = 1'b1;
            end else begin
              x_alu_result = (x_rs1_fwd < x_rs2_fwd) ? 32'd1 : 32'd0; x_rf_we = 1'b1;
            end
          end
          3'b100: begin
            if (x_funct7 == 7'd1) begin
              if (!div_stall) begin
                if (div_rs2_zero) x_alu_result = 32'hFFFFFFFF;
                else if (div_rs1_neg && div_op_a_reg == 32'h80000000 && div_op_b_reg == 32'h00000001)
                  x_alu_result = 32'h80000000;
                else
                  x_alu_result = (div_rs1_neg ^ div_rs2_neg) ?
                                 (~div_quotient + 32'd1) : div_quotient;
                x_rf_we = 1'b1;
              end
            end else begin x_alu_result = x_rs1_fwd ^ x_rs2_fwd; x_rf_we = 1'b1; end
          end
          3'b101: begin
            if (x_funct7 == 7'd1) begin
              if (!div_stall) begin
                x_alu_result = div_rs2_zero ? 32'hFFFFFFFF : div_quotient;
                x_rf_we = 1'b1;
              end
            end else if (x_funct7 == 7'b0000000) begin
              x_alu_result = x_rs1_fwd >> x_rs2_fwd[4:0]; x_rf_we = 1'b1;
            end else begin
              x_alu_result = $signed(x_rs1_fwd) >>> x_rs2_fwd[4:0]; x_rf_we = 1'b1;
            end
          end
          3'b110: begin
            if (x_funct7 == 7'd1) begin
              if (!div_stall) begin
                if (div_rs2_zero) x_alu_result = div_rs1_orig;
                else if (div_rs1_neg && div_op_a_reg == 32'h80000000 && div_op_b_reg == 32'h00000001)
                  x_alu_result = 32'd0;
                else
                  x_alu_result = div_rs1_neg ? (~div_remainder + 32'd1) : div_remainder;
                x_rf_we = 1'b1;
              end
            end else begin x_alu_result = x_rs1_fwd | x_rs2_fwd; x_rf_we = 1'b1; end
          end
          3'b111: begin
            if (x_funct7 == 7'd1) begin
              if (!div_stall) begin
                x_alu_result = div_rs2_zero ? div_rs1_orig : div_remainder;
                x_rf_we = 1'b1;
              end
            end else begin x_alu_result = x_rs1_fwd & x_rs2_fwd; x_rf_we = 1'b1; end
          end
          default: x_rf_we = 1'b0;
        endcase
      end
      OpcodeBranch: begin
        case (x_funct3)
          3'b000: x_branch_taken = (x_rs1_fwd == x_rs2_fwd);
          3'b001: x_branch_taken = (x_rs1_fwd != x_rs2_fwd);
          3'b100: x_branch_taken = ($signed(x_rs1_fwd) < $signed(x_rs2_fwd));
          3'b101: x_branch_taken = ($signed(x_rs1_fwd) >= $signed(x_rs2_fwd));
          3'b110: x_branch_taken = (x_rs1_fwd < x_rs2_fwd);
          3'b111: x_branch_taken = (x_rs1_fwd >= x_rs2_fwd);
          default: x_branch_taken = 1'b0;
        endcase
        x_branch_target = execute_state.pc + execute_state.imm_b_sext;
      end
      OpcodeJal: begin
        x_alu_result    = execute_state.pc + 32'd4;
        x_rf_we         = 1'b1;
        x_branch_taken  = 1'b1;
        x_branch_target = execute_state.pc + execute_state.imm_j_sext;
      end
      OpcodeJalr: begin
        x_alu_result    = execute_state.pc + 32'd4;
        x_rf_we         = 1'b1;
        x_branch_taken  = 1'b1;
        x_branch_target = (x_rs1_fwd + execute_state.imm_i_sext) & ~32'd1;
      end
      OpcodeLoad: begin
        cla_a = x_rs1_fwd; cla_b = execute_state.imm_i_sext; cla_cin = 1'b0;
        x_alu_result = cla_sum; x_rf_we = 1'b1;
      end
      OpcodeStore: begin
        cla_a = x_rs1_fwd; cla_b = execute_state.imm_s_sext; cla_cin = 1'b0;
        x_alu_result = cla_sum; x_store_data = x_rs2_fwd;
      end
      OpcodeEnviron: begin
        if (execute_state.insn[31:7] == 25'd0) x_halt = 1'b1;
      end
      OpcodeMiscMem: begin /* fence = nop */ end
      default: begin end
    endcase
  end

  assign x_redirect_valid = x_branch_taken && !div_stall &&
                             (execute_state.cycle_status == CYCLE_NO_STALL);
  assign x_redirect_pc    = x_branch_target;

  // ---- Hazard detection -----------------------------------------------
  wire x_is_load = (x_opcode == OpcodeLoad);
  wire x_result_not_ready = x_is_load || div_stall;

  wire d_uses_rs1 = (d_opcode != OpcodeLui)  &&
                    (d_opcode != OpcodeAuipc) &&
                    (d_opcode != OpcodeJal);
  wire d_uses_rs2_in_x = (d_opcode == OpcodeRegReg) || (d_opcode == OpcodeBranch);

  wire load_use_stall = x_result_not_ready && (execute_state.rd != 5'd0) &&
                        ((d_uses_rs1 && execute_state.rd == d_rs1) ||
                         (d_uses_rs2_in_x && execute_state.rd == d_rs2));

  wire load_use_bubble = load_use_stall && !div_stall;

  // ---- Stall / flush --------------------------------------------------
  always_comb begin
    stall_f = load_use_stall || div_stall;
    stall_g = load_use_stall || div_stall;
    stall_d = load_use_stall || div_stall;
    flush_g = x_redirect_valid;
    flush_d = x_redirect_valid;
    flush_x = x_redirect_valid;
  end

  // ---- Execute stage latch --------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      execute_state <= '{
        pc: 0, insn: 0, cycle_status: CYCLE_RESET,
        rs1_data: 0, rs2_data: 0, rs1: 0, rs2: 0, rd: 0,
        imm_i_sext: 0, imm_s_sext: 0, imm_b_sext: 0, imm_j_sext: 0,
        imm_shamt: 0
      };
    end else if (flush_x) begin
      execute_state <= '{
        pc: 0, insn: 0, cycle_status: CYCLE_TAKEN_BRANCH,
        rs1_data: 0, rs2_data: 0, rs1: 0, rs2: 0, rd: 0,
        imm_i_sext: 0, imm_s_sext: 0, imm_b_sext: 0, imm_j_sext: 0,
        imm_shamt: 0
      };
    end else if (div_stall) begin
      execute_state <= execute_state;
    end else if (load_use_bubble) begin
      execute_state <= '{
        pc: 0, insn: 0, cycle_status: CYCLE_LOAD2USE,
        rs1_data: 0, rs2_data: 0, rs1: 0, rs2: 0, rd: 0,
        imm_i_sext: 0, imm_s_sext: 0, imm_b_sext: 0, imm_j_sext: 0,
        imm_shamt: 0
      };
    end else begin
      execute_state <= '{
        pc:           decode_state.pc,
        insn:         decode_state.insn,
        cycle_status: decode_state.cycle_status,
        rs1_data:     d_rs1_data,
        rs2_data:     d_rs2_data,
        rs1:          d_rs1,
        rs2:          d_rs2,
        rd:           d_rd,
        imm_i_sext:   d_imm_i_sext,
        imm_s_sext:   d_imm_s_sext,
        imm_b_sext:   d_imm_b_sext,
        imm_j_sext:   d_imm_j_sext,
        imm_shamt:    d_imm_shamt
      };
    end
  end

  wire [255:0] x_disasm;
  Disasm #(.PREFIX("X")) disasm_execute (
      .insn(execute_state.insn), .disasm(x_disasm)
  );

  // ===================================================================
  //  DMEM AXIL
  //
  //  Address/data sent at end of X. RDATA valid in M, registered to W.
  //  ARREADY/AWREADY/WREADY guaranteed always-1.
  // ===================================================================
  wire x_is_store_op = (x_opcode == OpcodeStore);
  wire x_is_load_op  = (x_opcode == OpcodeLoad);
  wire x_real_insn   = (execute_state.cycle_status == CYCLE_NO_STALL) && !div_stall;

  logic [3:0]       x_store_we;
  logic [`REG_SIZE] x_store_data_shifted;

  always_comb begin
    x_store_we           = 4'b0000;
    x_store_data_shifted = 32'd0;
    if (x_is_store_op && x_real_insn) begin
      case (x_funct3)
        3'b000: begin
          case (x_alu_result[1:0])
            2'b00: begin x_store_data_shifted = {24'd0, x_store_data[7:0]};        x_store_we = 4'b0001; end
            2'b01: begin x_store_data_shifted = {16'd0, x_store_data[7:0],  8'd0}; x_store_we = 4'b0010; end
            2'b10: begin x_store_data_shifted = { 8'd0, x_store_data[7:0], 16'd0}; x_store_we = 4'b0100; end
            2'b11: begin x_store_data_shifted = {x_store_data[7:0], 24'd0};        x_store_we = 4'b1000; end
            default: begin x_store_we = 4'b0000; x_store_data_shifted = 32'd0; end
          endcase
        end
        3'b001: begin
          case (x_alu_result[1])
            1'b0: begin x_store_data_shifted = {16'd0, x_store_data[15:0]};  x_store_we = 4'b0011; end
            1'b1: begin x_store_data_shifted = {x_store_data[15:0], 16'd0};  x_store_we = 4'b1100; end
            default: begin x_store_we = 4'b0000; x_store_data_shifted = 32'd0; end
          endcase
        end
        3'b010: begin
          x_store_data_shifted = x_store_data;
          x_store_we           = 4'b1111;
        end
        default: begin x_store_we = 4'b0000; x_store_data_shifted = 32'd0; end
      endcase
    end
  end

  assign dmem.ARVALID = x_real_insn && x_is_load_op;
  assign dmem.ARADDR  = {x_alu_result[31:2], 2'b00};
  assign dmem.ARPROT  = 3'd0;
  assign dmem.RREADY  = 1'b1;

  assign dmem.AWVALID = x_real_insn && x_is_store_op;
  assign dmem.AWADDR  = {x_alu_result[31:2], 2'b00};
  assign dmem.AWPROT  = 3'd0;
  assign dmem.WVALID  = dmem.AWVALID;
  assign dmem.WDATA   = x_store_data_shifted;
  assign dmem.WSTRB   = x_store_we;
  assign dmem.BREADY  = 1'b1;

  // ===================================================================
  //  MEMORY  (M)
  // ===================================================================
  stage_memory_t memory_state;

  always_ff @(posedge clk) begin
    if (rst) begin
      memory_state <= '{
        pc: 0, insn: 0, cycle_status: CYCLE_RESET,
        alu_result: 0, rd: 0, rf_we: 0, halt: 0
      };
    end else if (div_stall) begin
      memory_state <= '{
        pc: 0, insn: 0, cycle_status: CYCLE_DIV,
        alu_result: 0, rd: 0, rf_we: 0, halt: 0
      };
    end else begin
      memory_state <= '{
        pc:           execute_state.pc,
        insn:         execute_state.insn,
        cycle_status: x_cycle_status_out,
        alu_result:   x_alu_result,
        rd:           execute_state.rd,
        rf_we:        x_rf_we,
        halt:         x_halt
      };
    end
  end

  assign m_rf_we      = memory_state.rf_we;
  assign m_rd         = memory_state.rd;
  assign m_alu_result = memory_state.alu_result;

  wire [255:0] m_disasm;
  Disasm #(.PREFIX("M")) disasm_mem (
      .insn(memory_state.insn), .disasm(m_disasm)
  );

  wire [`OPCODE_SIZE] m_opcode = memory_state.insn[6:0];
  wire [ 2:0]         m_funct3 = memory_state.insn[14:12];

  always_comb begin
    m_rd_data = memory_state.alu_result;
    if (m_opcode == OpcodeLoad) begin
      case (m_funct3)
        3'b000: begin
          case (memory_state.alu_result[1:0])
            2'b00: m_rd_data = {{24{dmem.RDATA[ 7]}}, dmem.RDATA[ 7: 0]};
            2'b01: m_rd_data = {{24{dmem.RDATA[15]}}, dmem.RDATA[15: 8]};
            2'b10: m_rd_data = {{24{dmem.RDATA[23]}}, dmem.RDATA[23:16]};
            2'b11: m_rd_data = {{24{dmem.RDATA[31]}}, dmem.RDATA[31:24]};
            default: m_rd_data = 32'd0;
          endcase
        end
        3'b001: begin
          case (memory_state.alu_result[1])
            1'b0: m_rd_data = {{16{dmem.RDATA[15]}}, dmem.RDATA[15: 0]};
            1'b1: m_rd_data = {{16{dmem.RDATA[31]}}, dmem.RDATA[31:16]};
            default: m_rd_data = 32'd0;
          endcase
        end
        3'b010: m_rd_data = dmem.RDATA;
        3'b100: begin
          case (memory_state.alu_result[1:0])
            2'b00: m_rd_data = {24'd0, dmem.RDATA[ 7: 0]};
            2'b01: m_rd_data = {24'd0, dmem.RDATA[15: 8]};
            2'b10: m_rd_data = {24'd0, dmem.RDATA[23:16]};
            2'b11: m_rd_data = {24'd0, dmem.RDATA[31:24]};
            default: m_rd_data = 32'd0;
          endcase
        end
        3'b101: begin
          case (memory_state.alu_result[1])
            1'b0: m_rd_data = {16'd0, dmem.RDATA[15: 0]};
            1'b1: m_rd_data = {16'd0, dmem.RDATA[31:16]};
            default: m_rd_data = 32'd0;
          endcase
        end
        default: m_rd_data = 32'd0;
      endcase
    end
  end

  // ===================================================================
  //  WRITEBACK  (W)
  // ===================================================================
  stage_writeback_t writeback_state;

  always_ff @(posedge clk) begin
    if (rst) begin
      writeback_state <= '{
        pc: 0, insn: 0, cycle_status: CYCLE_RESET,
        rd_data: 0, rd: 0, rf_we: 0, halt: 0
      };
    end else begin
      writeback_state <= '{
        pc:           memory_state.pc,
        insn:         memory_state.insn,
        cycle_status: memory_state.cycle_status,
        rd_data:      m_rd_data,
        rd:           memory_state.rd,
        rf_we:        memory_state.rf_we,
        halt:         memory_state.halt
      };
    end
  end

  wire [255:0] w_disasm;
  Disasm #(.PREFIX("W")) disasm_wb (
      .insn(writeback_state.insn), .disasm(w_disasm)
  );

  assign wb_rf_we   = writeback_state.rf_we;
  assign wb_rd      = writeback_state.rd;
  assign wb_rd_data = writeback_state.rd_data;

  assign halt = writeback_state.halt;

  assign trace_completed_pc           = writeback_state.pc;
  assign trace_completed_insn         = writeback_state.insn;
  assign trace_completed_cycle_status = writeback_state.cycle_status;

endmodule

// ---------------------------------------------------------------
//  Top-level Processor
// ---------------------------------------------------------------
module Processor (
    input  wire  clk,
    input  wire  rst,
    output logic halt,
    output wire [`REG_SIZE]  trace_completed_pc,
    output wire [`INSN_SIZE] trace_completed_insn,
    output cycle_status_e    trace_completed_cycle_status
);

  wire [(8*32)-1:0] test_case;

  axil_if axil_mem_ro ();
  axil_if axil_mem_rw ();

  EasyAxilMemory #(
      .OPT_SKIDBUFFER(1),
      .OPT_LOWPOWER(0),
      .NUM_WORDS(8192)
  ) memory (
      .ACLK(clk),
      .ARESETn(~rst),
      .port_ro(axil_mem_ro.subord),
      .port_rw(axil_mem_rw.subord)
  );

  DatapathPipelinedAxil datapath (
      .clk(clk),
      .rst(rst),
      .imem(axil_mem_ro.manager),
      .dmem(axil_mem_rw.manager),
      .halt(halt),
      .trace_completed_pc(trace_completed_pc),
      .trace_completed_insn(trace_completed_insn),
      .trace_completed_cycle_status(trace_completed_cycle_status)
  );

endmodule
