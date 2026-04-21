`timescale 1ns / 1ns

`define REG_SIZE 31:0
`define INSN_SIZE 31:0
`define OPCODE_SIZE 6:0

`ifndef DIVIDER_STAGES
`define DIVIDER_STAGES 8
`endif

`ifndef SYNTHESIS
`include "../hw3-singlecycle/RvDisassembler.sv"
`endif
`include "../hw2b-cla/CarryLookaheadAdder.sv"
`include "../hw4-multicycle/DividerUnsignedPipelined.sv"
`include "../hw3-singlecycle/cycle_status.sv"

module Disasm #(
    byte PREFIX = "D"
) (
    input wire [31:0] insn,
    output wire [(8*32)-1:0] disasm
);
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
endmodule

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

  assign rs1_data = (rs1 == 5'd0)                   ? '0 :
                    (we && rd == rs1 && rd != 5'd0)  ? rd_data :
                    regs[rs1];
  assign rs2_data = (rs2 == 5'd0)                   ? '0 :
                    (we && rd == rs2 && rd != 5'd0)  ? rd_data :
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
typedef struct packed {
  logic [`REG_SIZE]  pc;
  logic [`INSN_SIZE] insn;
  cycle_status_e     cycle_status;
} stage_decode_t;

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

typedef struct packed {
  logic [`REG_SIZE]  pc;
  logic [`INSN_SIZE] insn;
  cycle_status_e     cycle_status;
  logic [`REG_SIZE]  alu_result;
  logic [`REG_SIZE]  rs2_data;
  logic [ 4:0]       rd;
  logic              rf_we;
  logic              halt;
} stage_memory_t;

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
//  DatapathPipelined
// ---------------------------------------------------------------
module DatapathPipelined (
    input  wire                clk,
    input  wire                rst,
    output logic [`REG_SIZE]   pc_to_imem,
    input  wire  [`INSN_SIZE]  insn_from_imem,
    output logic [`REG_SIZE]   addr_to_dmem,
    input  wire  [`REG_SIZE]   load_data_from_dmem,
    output logic [`REG_SIZE]   store_data_to_dmem,
    output logic [3:0]         store_we_to_dmem,
    output logic               halt,
    output logic [`REG_SIZE]   trace_writeback_pc,
    output logic [`INSN_SIZE]  trace_writeback_insn,
    output cycle_status_e      trace_writeback_cycle_status
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

  // =============================================================
  //  FETCH
  // =============================================================
  logic [`REG_SIZE]  f_pc_current;
  wire  [`INSN_SIZE] f_insn;
  cycle_status_e     f_cycle_status;

  logic             x_redirect_valid;
  logic [`REG_SIZE] x_redirect_pc;

  logic stall_f, stall_d, flush_d, flush_x, load_use_bubble;

  // div_stall forward declaration (wire, driven from always_comb below)
  logic div_stall;

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
  assign pc_to_imem = f_pc_current;
  assign f_insn     = insn_from_imem;

  wire [255:0] f_disasm;
  Disasm #(.PREFIX("F")) disasm_0fetch (.insn(f_insn), .disasm(f_disasm));

  // =============================================================
  //  DECODE
  // =============================================================
  stage_decode_t decode_state;
  always_ff @(posedge clk) begin
    if (rst)
      decode_state <= '{pc: 0, insn: 0, cycle_status: CYCLE_RESET};
    else if (flush_d)
      decode_state <= '{pc: 0, insn: 0, cycle_status: CYCLE_TAKEN_BRANCH};
    else if (!stall_d)
      decode_state <= '{pc: f_pc_current, insn: f_insn, cycle_status: f_cycle_status};
    // stall_d: hold
  end

  wire [255:0] d_disasm;
  Disasm #(.PREFIX("D")) disasm_1decode (.insn(decode_state.insn), .disasm(d_disasm));

  wire [ 6:0] d_funct7    = decode_state.insn[31:25];
  wire [ 4:0] d_rs2       = decode_state.insn[24:20];
  wire [ 4:0] d_rs1       = decode_state.insn[19:15];
  wire [ 2:0] d_funct3    = decode_state.insn[14:12];
  wire [ 4:0] d_rd        = decode_state.insn[11: 7];
  wire [`OPCODE_SIZE] d_opcode = decode_state.insn[6:0];

  wire [11:0] d_imm_i     = decode_state.insn[31:20];
  wire [ 4:0] d_imm_shamt = decode_state.insn[24:20];

  wire [11:0] d_imm_s;
  assign d_imm_s[11:5] = d_funct7; assign d_imm_s[4:0] = d_rd;

  wire [12:0] d_imm_b;
  assign {d_imm_b[12], d_imm_b[10:5]} = d_funct7;
  assign {d_imm_b[4:1], d_imm_b[11]}  = d_rd;
  assign d_imm_b[0] = 1'b0;

  wire [20:0] d_imm_j;
  assign {d_imm_j[20], d_imm_j[10:1], d_imm_j[11], d_imm_j[19:12], d_imm_j[0]} =
         {decode_state.insn[31:12], 1'b0};

  wire [`REG_SIZE] d_imm_i_sext = {{20{d_imm_i[11]}}, d_imm_i};
  wire [`REG_SIZE] d_imm_s_sext = {{20{d_imm_s[11]}}, d_imm_s};
  wire [`REG_SIZE] d_imm_b_sext = {{19{d_imm_b[12]}}, d_imm_b};
  wire [`REG_SIZE] d_imm_j_sext = {{11{d_imm_j[20]}}, d_imm_j};

  wire        wb_rf_we;
  wire [ 4:0] wb_rd;
  wire [`REG_SIZE] wb_rd_data;

  wire [`REG_SIZE] d_rs1_data, d_rs2_data;
  RegFile rf (
      .clk(clk), .rst(rst),
      .we(wb_rf_we), .rd(wb_rd), .rd_data(wb_rd_data),
      .rs1(d_rs1), .rs1_data(d_rs1_data),
      .rs2(d_rs2), .rs2_data(d_rs2_data)
  );

  // =============================================================
  //  EXECUTE
  // =============================================================

  stage_execute_t execute_state;

  wire [`OPCODE_SIZE] x_opcode = execute_state.insn[6:0];
  wire [ 6:0]         x_funct7 = execute_state.insn[31:25];
  wire [ 2:0]         x_funct3 = execute_state.insn[14:12];

  wire x_is_divide = (x_opcode == OpcodeRegReg) &&
                     (x_funct7 == 7'd1) &&
                     (x_funct3[2] == 1'b1);

  logic [6:0] div_pipe_valid;

  always_comb div_stall = x_is_divide && !div_pipe_valid[6];

  always_ff @(posedge clk) begin
    if (rst || !x_is_divide)
      div_pipe_valid <= 7'd0;
    else
      div_pipe_valid <= {div_pipe_valid[5:0], 1'b1};
  end

  // -- MEM/WB bypass forward declarations --
  wire        m_rf_we;
  wire [ 4:0] m_rd;
  wire [`REG_SIZE] m_alu_result;

  // -- Forwarding muxes (MX > WX) --
  logic [`REG_SIZE] x_rs1_fwd, x_rs2_fwd;
  always_comb begin
    if (m_rf_we && m_rd != 5'd0 && m_rd == execute_state.rs1)
      x_rs1_fwd = m_alu_result;
    else if (wb_rf_we && wb_rd != 5'd0 && wb_rd == execute_state.rs1)
      x_rs1_fwd = wb_rd_data;
    else
      x_rs1_fwd = execute_state.rs1_data;

    if (m_rf_we && m_rd != 5'd0 && m_rd == execute_state.rs2)
      x_rs2_fwd = m_alu_result;
    else if (wb_rf_we && wb_rd != 5'd0 && wb_rd == execute_state.rs2)
      x_rs2_fwd = wb_rd_data;
    else
      x_rs2_fwd = execute_state.rs2_data;
  end

  // -- Divider operands: combinational input with latched fallback --
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

  // -- CLA adder --
  logic [`REG_SIZE] cla_a, cla_b, cla_sum;
  logic             cla_cin;
  CarryLookaheadAdder cla_inst (
      .a(cla_a), .b(cla_b), .cin(cla_cin), .sum(cla_sum)
  );

  // -- Execute combinational --
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
              x_alu_result = x_rs1_fwd * x_rs2_fwd;
              x_rf_we = 1'b1;
            end else if (x_funct7 == 7'd0) begin
              cla_a = x_rs1_fwd; cla_b = x_rs2_fwd; cla_cin = 1'b0;
              x_alu_result = cla_sum;
              x_rf_we = 1'b1;
            end else begin
              cla_a = x_rs1_fwd; cla_b = ~x_rs2_fwd; cla_cin = 1'b1;
              x_alu_result = cla_sum;
              x_rf_we = 1'b1;
            end
          end
          3'b001: begin
            if (x_funct7 == 7'd1) begin
              x_alu_result = 32'($signed(($signed({{32{x_rs1_fwd[31]}}, x_rs1_fwd}) *
                             $signed({{32{x_rs2_fwd[31]}}, x_rs2_fwd}))) >>> 32);
              x_rf_we = 1'b1;
            end else begin
              x_alu_result = x_rs1_fwd << x_rs2_fwd[4:0];
              x_rf_we = 1'b1;
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
              x_alu_result = (x_rs1_fwd < x_rs2_fwd) ? 32'd1 : 32'd0;
              x_rf_we = 1'b1;
            end
          end
          3'b100: begin
            if (x_funct7 == 7'd1) begin
              // DIV (signed)
              if (!div_stall) begin
                if (div_rs2_zero)
                  x_alu_result = 32'hFFFFFFFF;
                else if (div_rs1_neg && div_op_a_reg == 32'h80000000 && div_op_b_reg == 32'h00000001)
                  x_alu_result = 32'h80000000;
                else
                  x_alu_result = (div_rs1_neg ^ div_rs2_neg) ?
                                 (~div_quotient + 32'd1) : div_quotient;
                x_rf_we = 1'b1;
              end
            end else begin
              x_alu_result = x_rs1_fwd ^ x_rs2_fwd;
              x_rf_we = 1'b1;
            end
          end
          3'b101: begin
            if (x_funct7 == 7'd1) begin
              // DIVU (unsigned)
              if (!div_stall) begin
                if (div_rs2_zero)
                  x_alu_result = 32'hFFFFFFFF;
                else
                  x_alu_result = div_quotient;
                x_rf_we = 1'b1;
              end
            end else if (x_funct7 == 7'b0000000) begin
              x_alu_result = x_rs1_fwd >> x_rs2_fwd[4:0];
              x_rf_we = 1'b1;
            end else begin
              x_alu_result = $signed(x_rs1_fwd) >>> x_rs2_fwd[4:0];
              x_rf_we = 1'b1;
            end
          end
          3'b110: begin
            if (x_funct7 == 7'd1) begin
              // REM (signed)
              if (!div_stall) begin
                if (div_rs2_zero)
                  x_alu_result = div_rs1_orig;
                else if (div_rs1_neg && div_op_a_reg == 32'h80000000 && div_op_b_reg == 32'h00000001)
                  x_alu_result = 32'd0;
                else
                  x_alu_result = div_rs1_neg ? (~div_remainder + 32'd1) : div_remainder;
                x_rf_we = 1'b1;
              end
            end else begin
              x_alu_result = x_rs1_fwd | x_rs2_fwd;
              x_rf_we = 1'b1;
            end
          end
          3'b111: begin
            if (x_funct7 == 7'd1) begin
              // REMU (unsigned)
              if (!div_stall) begin
                if (div_rs2_zero)
                  x_alu_result = div_rs1_orig;
                else
                  x_alu_result = div_remainder;
                x_rf_we = 1'b1;
              end
            end else begin
              x_alu_result = x_rs1_fwd & x_rs2_fwd;
              x_rf_we = 1'b1;
            end
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
        x_alu_result = cla_sum;
        x_rf_we = 1'b1;
      end
      OpcodeStore: begin
        cla_a = x_rs1_fwd; cla_b = execute_state.imm_s_sext; cla_cin = 1'b0;
        x_alu_result = cla_sum;
        x_store_data = x_rs2_fwd;
      end
      OpcodeEnviron: begin
        if (execute_state.insn[31:7] == 25'd0) x_halt = 1'b1;
      end
      OpcodeMiscMem: begin /* fence = nop */ end
      default: begin end
    endcase
  end

  // Branch redirect
  assign x_redirect_valid = x_branch_taken && !div_stall &&
                             (execute_state.cycle_status == CYCLE_NO_STALL);
  assign x_redirect_pc    = x_branch_target;

  // -- Hazard detection --
  wire x_is_load = (x_opcode == OpcodeLoad);
  wire x_result_not_ready = x_is_load || div_stall;

  wire d_uses_rs1 = (d_opcode != OpcodeLui) && (d_opcode != OpcodeAuipc) &&
                    (d_opcode != OpcodeJal);
  wire d_uses_rs2_in_x = (d_opcode == OpcodeRegReg) || (d_opcode == OpcodeBranch);

  wire load_use_stall = x_result_not_ready && (execute_state.rd != 5'd0) &&
                        ((d_uses_rs1 && execute_state.rd == d_rs1) ||
                         (d_uses_rs2_in_x && execute_state.rd == d_rs2));

  assign load_use_bubble = load_use_stall && !div_stall;

  assign stall_f = load_use_stall || div_stall;
  assign stall_d = load_use_stall || div_stall;
  assign flush_d = x_redirect_valid;
  assign flush_x = x_redirect_valid;

  // -- Execute stage latch --
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
      execute_state.rs1_data <= x_rs1_fwd;
      execute_state.rs2_data <= x_rs2_fwd;
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
  Disasm #(.PREFIX("X")) disasm_2execute (.insn(execute_state.insn), .disasm(x_disasm));

  // =============================================================
  //  MEMORY
  // =============================================================
  stage_memory_t memory_state;
  always_ff @(posedge clk) begin
    if (rst) begin
      memory_state <= '{
        pc: 0, insn: 0, cycle_status: CYCLE_RESET,
        alu_result: 0, rs2_data: 0, rd: 0, rf_we: 0, halt: 0
      };
    end else if (div_stall) begin
      memory_state <= '{
        pc: 0, insn: 0, cycle_status: CYCLE_DIV,
        alu_result: 0, rs2_data: 0, rd: 0, rf_we: 0, halt: 0
      };
    end else begin
      memory_state <= '{
        pc:           execute_state.pc,
        insn:         execute_state.insn,
        cycle_status: x_cycle_status_out,
        alu_result:   x_alu_result,
        rs2_data:     x_store_data,
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
  Disasm #(.PREFIX("M")) disasm_3mem (.insn(memory_state.insn), .disasm(m_disasm));

  wire [`OPCODE_SIZE] m_opcode = memory_state.insn[6:0];
  wire [ 2:0]         m_funct3 = memory_state.insn[14:12];

  // WM bypass: forward writeback data to store data when applicable
  wire [4:0] m_rs2_reg = memory_state.insn[24:20];
  wire wm_bypass_valid = (m_opcode == OpcodeStore) && wb_rf_we &&
                         (wb_rd != 5'd0) && (wb_rd == m_rs2_reg);
  wire [`REG_SIZE] m_store_data = wm_bypass_valid ? wb_rd_data : memory_state.rs2_data;

  logic [`REG_SIZE] m_rd_data;
  always_comb begin
    addr_to_dmem       = {memory_state.alu_result[31:2], 2'b00};
    store_data_to_dmem = 32'd0;
    store_we_to_dmem   = 4'b0000;
    m_rd_data          = memory_state.alu_result;

    if (m_opcode == OpcodeStore) begin
      case (m_funct3)
        3'b000: begin
          case (memory_state.alu_result[1:0])
            2'b00: begin store_data_to_dmem={24'd0,m_store_data[7:0]};       store_we_to_dmem=4'b0001; end
            2'b01: begin store_data_to_dmem={16'd0,m_store_data[7:0],8'd0};  store_we_to_dmem=4'b0010; end
            2'b10: begin store_data_to_dmem={8'd0,m_store_data[7:0],16'd0};  store_we_to_dmem=4'b0100; end
            2'b11: begin store_data_to_dmem={m_store_data[7:0],24'd0};       store_we_to_dmem=4'b1000; end
            default: store_we_to_dmem=4'b0000;
          endcase
        end
        3'b001: begin
          case (memory_state.alu_result[1])
            1'b0: begin store_data_to_dmem={16'd0,m_store_data[15:0]};  store_we_to_dmem=4'b0011; end
            1'b1: begin store_data_to_dmem={m_store_data[15:0],16'd0};  store_we_to_dmem=4'b1100; end
            default: store_we_to_dmem=4'b0000;
          endcase
        end
        3'b010: begin
          store_data_to_dmem=m_store_data; store_we_to_dmem=4'b1111;
        end
        default: store_we_to_dmem=4'b0000;
      endcase
    end else if (m_opcode == OpcodeLoad) begin
      case (m_funct3)
        3'b000: begin
          case (memory_state.alu_result[1:0])
            2'b00: m_rd_data={{24{load_data_from_dmem[7]}},  load_data_from_dmem[7:0]};
            2'b01: m_rd_data={{24{load_data_from_dmem[15]}}, load_data_from_dmem[15:8]};
            2'b10: m_rd_data={{24{load_data_from_dmem[23]}}, load_data_from_dmem[23:16]};
            2'b11: m_rd_data={{24{load_data_from_dmem[31]}}, load_data_from_dmem[31:24]};
            default: m_rd_data=32'd0;
          endcase
        end
        3'b001: begin
          case (memory_state.alu_result[1])
            1'b0: m_rd_data={{16{load_data_from_dmem[15]}}, load_data_from_dmem[15:0]};
            1'b1: m_rd_data={{16{load_data_from_dmem[31]}}, load_data_from_dmem[31:16]};
            default: m_rd_data=32'd0;
          endcase
        end
        3'b010: m_rd_data=load_data_from_dmem;
        3'b100: begin
          case (memory_state.alu_result[1:0])
            2'b00: m_rd_data={24'd0,load_data_from_dmem[7:0]};
            2'b01: m_rd_data={24'd0,load_data_from_dmem[15:8]};
            2'b10: m_rd_data={24'd0,load_data_from_dmem[23:16]};
            2'b11: m_rd_data={24'd0,load_data_from_dmem[31:24]};
            default: m_rd_data=32'd0;
          endcase
        end
        3'b101: begin
          case (memory_state.alu_result[1])
            1'b0: m_rd_data={16'd0,load_data_from_dmem[15:0]};
            1'b1: m_rd_data={16'd0,load_data_from_dmem[31:16]};
            default: m_rd_data=32'd0;
          endcase
        end
        default: m_rd_data=32'd0;
      endcase
    end
  end

  // =============================================================
  //  WRITEBACK
  // =============================================================
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
  Disasm #(.PREFIX("W")) disasm_4wb (.insn(writeback_state.insn), .disasm(w_disasm));

  assign wb_rf_we   = writeback_state.rf_we;
  assign wb_rd      = writeback_state.rd;
  assign wb_rd_data = writeback_state.rd_data;

  assign halt = writeback_state.halt;

  assign trace_writeback_pc           = writeback_state.pc;
  assign trace_writeback_insn         = writeback_state.insn;
  assign trace_writeback_cycle_status = writeback_state.cycle_status;

  wire [`REG_SIZE]  trace_completed_pc           = writeback_state.pc;
  wire [`INSN_SIZE] trace_completed_insn         = writeback_state.insn;
  cycle_status_e    trace_completed_cycle_status;
  assign trace_completed_cycle_status = writeback_state.cycle_status;

endmodule

// ---------------------------------------------------------------
//  Memory
// ---------------------------------------------------------------
module MemorySingleCycle #(
    parameter int NUM_WORDS = 512
) (
    input  wire                rst,
    input  wire                clk,
    input  wire  [`REG_SIZE]   pc_to_imem,
    output logic [`INSN_SIZE]  insn_from_imem,
    input  wire  [`REG_SIZE]   addr_to_dmem,
    output logic [`REG_SIZE]   load_data_from_dmem,
    input  wire  [`REG_SIZE]   store_data_to_dmem,
    input  wire  [3:0]         store_we_to_dmem
);
  logic [`REG_SIZE] mem_array[NUM_WORDS];
`ifdef SYNTHESIS
  initial begin $readmemh("mem_initial_contents.hex", mem_array); end
`endif
  always_comb begin
    assert (pc_to_imem[1:0] == 2'b00);
    assert (addr_to_dmem[1:0] == 2'b00);
  end
  localparam int AddrMsb = $clog2(NUM_WORDS) + 1;
  localparam int AddrLsb = 2;
  always @(negedge clk) begin
    if (!rst) insn_from_imem <= mem_array[{pc_to_imem[AddrMsb:AddrLsb]}];
  end
  always @(negedge clk) begin
    if (!rst) begin
      if (store_we_to_dmem[0]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][7:0]   <= store_data_to_dmem[7:0];
      if (store_we_to_dmem[1]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][15:8]  <= store_data_to_dmem[15:8];
      if (store_we_to_dmem[2]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][23:16] <= store_data_to_dmem[23:16];
      if (store_we_to_dmem[3]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][31:24] <= store_data_to_dmem[31:24];
      load_data_from_dmem <= mem_array[{addr_to_dmem[AddrMsb:AddrLsb]}];
    end
  end
endmodule

// ---------------------------------------------------------------
//  Top-level Processor
// ---------------------------------------------------------------
module Processor (
    input  wire               clk,
    input  wire               rst,
    output logic              halt,
    output wire [`REG_SIZE]   trace_writeback_pc,
    output wire [`INSN_SIZE]  trace_writeback_insn,
    output cycle_status_e     trace_writeback_cycle_status
);
  wire [`INSN_SIZE] insn_from_imem;
  wire [`REG_SIZE]  pc_to_imem, mem_data_addr, mem_data_loaded_value, mem_data_to_write;
  wire [3:0]        mem_data_we;
  wire [(8*32)-1:0] test_case;

  MemorySingleCycle #(.NUM_WORDS(8192)) memory (
      .rst(rst), .clk(clk),
      .pc_to_imem(pc_to_imem), .insn_from_imem(insn_from_imem),
      .addr_to_dmem(mem_data_addr),
      .load_data_from_dmem(mem_data_loaded_value),
      .store_data_to_dmem(mem_data_to_write),
      .store_we_to_dmem(mem_data_we)
  );

  DatapathPipelined datapath (
      .clk(clk), .rst(rst),
      .pc_to_imem(pc_to_imem), .insn_from_imem(insn_from_imem),
      .addr_to_dmem(mem_data_addr),
      .store_data_to_dmem(mem_data_to_write),
      .store_we_to_dmem(mem_data_we),
      .load_data_from_dmem(mem_data_loaded_value),
      .halt(halt),
      .trace_writeback_pc(trace_writeback_pc),
      .trace_writeback_insn(trace_writeback_insn),
      .trace_writeback_cycle_status(trace_writeback_cycle_status)
  );
endmodule
