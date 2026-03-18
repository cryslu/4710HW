/* INSERT NAME AND PENNKEY HERE */

`timescale 1ns / 1ns

`define REG_SIZE 31:0
`define INSN_SIZE 31:0
`define OPCODE_SIZE 6:0

`include "../hw2b-cla/CarryLookaheadAdder.sv"
`include "DividerUnsignedPipelined.sv"
`include "../hw3-singlecycle/cycle_status.sv"

module RegFile (
    input logic [4:0] rd,
    input logic [`REG_SIZE] rd_data,
    input logic [4:0] rs1,
    output logic [`REG_SIZE] rs1_data,
    input logic [4:0] rs2,
    output logic [`REG_SIZE] rs2_data,
    input logic clk,
    input logic we,
    input logic rst
);
  localparam int NumRegs = 32;
  logic [`REG_SIZE] regs[NumRegs];

  assign rs1_data = (rs1 == 5'd0) ? '0 : regs[rs1];
  assign rs2_data = (rs2 == 5'd0) ? '0 : regs[rs2];

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < NumRegs; i++) begin
        regs[i] <= '0;
      end
    end else if (we && rd != 5'd0) begin
      regs[rd] <= rd_data;
    end
  end
endmodule

module DatapathMultiCycle (
    input wire                clk,
    input wire                rst,
    output logic              halt,
    output logic [`REG_SIZE]  pc_to_imem,
    input wire [`INSN_SIZE]   insn_from_imem,
    output logic [`REG_SIZE]  addr_to_dmem,
    input wire [`REG_SIZE]    load_data_from_dmem,
    output logic [`REG_SIZE]  store_data_to_dmem,
    output logic [3:0]        store_we_to_dmem,
    output logic [`REG_SIZE]  trace_completed_pc,
    output logic [`INSN_SIZE] trace_completed_insn,
    output cycle_status_e     trace_completed_cycle_status
);

  wire [6:0] insn_funct7;
  wire [4:0] insn_rs2;
  wire [4:0] insn_rs1;
  wire [2:0] insn_funct3;
  wire [4:0] insn_rd;
  wire [`OPCODE_SIZE] insn_opcode;

  assign {insn_funct7, insn_rs2, insn_rs1, insn_funct3, insn_rd, insn_opcode} = insn_from_imem;

  wire [11:0] imm_i;
  assign imm_i = insn_from_imem[31:20];
  wire [4:0] imm_shamt = insn_from_imem[24:20];

  wire [11:0] imm_s;
  assign imm_s[11:5] = insn_funct7, imm_s[4:0] = insn_rd;

  wire [12:0] imm_b;
  assign {imm_b[12], imm_b[10:5]} = insn_funct7, {imm_b[4:1], imm_b[11]} = insn_rd, imm_b[0] = 1'b0;

  wire [20:0] imm_j;
  assign {imm_j[20], imm_j[10:1], imm_j[11], imm_j[19:12], imm_j[0]} = {insn_from_imem[31:12], 1'b0};

  wire [`REG_SIZE] imm_i_sext = {{20{imm_i[11]}}, imm_i[11:0]};
  wire [`REG_SIZE] imm_s_sext = {{20{imm_s[11]}}, imm_s[11:0]};
  wire [`REG_SIZE] imm_b_sext = {{19{imm_b[12]}}, imm_b[12:0]};
  wire [`REG_SIZE] imm_j_sext = {{11{imm_j[20]}}, imm_j[20:0]};

  localparam bit [`OPCODE_SIZE] OpLoad    = 7'b00_000_11;
  localparam bit [`OPCODE_SIZE] OpStore   = 7'b01_000_11;
  localparam bit [`OPCODE_SIZE] OpBranch  = 7'b11_000_11;
  localparam bit [`OPCODE_SIZE] OpJalr    = 7'b11_001_11;
  localparam bit [`OPCODE_SIZE] OpMiscMem = 7'b00_011_11;
  localparam bit [`OPCODE_SIZE] OpJal     = 7'b11_011_11;
  localparam bit [`OPCODE_SIZE] OpRegImm  = 7'b00_100_11;
  localparam bit [`OPCODE_SIZE] OpRegReg  = 7'b01_100_11;
  localparam bit [`OPCODE_SIZE] OpEnviron = 7'b11_100_11;
  localparam bit [`OPCODE_SIZE] OpAuipc   = 7'b00_101_11;
  localparam bit [`OPCODE_SIZE] OpLui     = 7'b01_101_11;

  wire insn_lui   = insn_opcode == OpLui;
  wire insn_auipc = insn_opcode == OpAuipc;
  wire insn_jal   = insn_opcode == OpJal;
  wire insn_jalr  = insn_opcode == OpJalr;

  wire insn_beq  = insn_opcode == OpBranch && insn_from_imem[14:12] == 3'b000;
  wire insn_bne  = insn_opcode == OpBranch && insn_from_imem[14:12] == 3'b001;
  wire insn_blt  = insn_opcode == OpBranch && insn_from_imem[14:12] == 3'b100;
  wire insn_bge  = insn_opcode == OpBranch && insn_from_imem[14:12] == 3'b101;
  wire insn_bltu = insn_opcode == OpBranch && insn_from_imem[14:12] == 3'b110;
  wire insn_bgeu = insn_opcode == OpBranch && insn_from_imem[14:12] == 3'b111;

  wire insn_lb  = insn_opcode == OpLoad && insn_from_imem[14:12] == 3'b000;
  wire insn_lh  = insn_opcode == OpLoad && insn_from_imem[14:12] == 3'b001;
  wire insn_lw  = insn_opcode == OpLoad && insn_from_imem[14:12] == 3'b010;
  wire insn_lbu = insn_opcode == OpLoad && insn_from_imem[14:12] == 3'b100;
  wire insn_lhu = insn_opcode == OpLoad && insn_from_imem[14:12] == 3'b101;

  wire insn_sb = insn_opcode == OpStore && insn_from_imem[14:12] == 3'b000;
  wire insn_sh = insn_opcode == OpStore && insn_from_imem[14:12] == 3'b001;
  wire insn_sw = insn_opcode == OpStore && insn_from_imem[14:12] == 3'b010;

  wire insn_addi  = insn_opcode == OpRegImm && insn_from_imem[14:12] == 3'b000;
  wire insn_slti  = insn_opcode == OpRegImm && insn_from_imem[14:12] == 3'b010;
  wire insn_sltiu = insn_opcode == OpRegImm && insn_from_imem[14:12] == 3'b011;
  wire insn_xori  = insn_opcode == OpRegImm && insn_from_imem[14:12] == 3'b100;
  wire insn_ori   = insn_opcode == OpRegImm && insn_from_imem[14:12] == 3'b110;
  wire insn_andi  = insn_opcode == OpRegImm && insn_from_imem[14:12] == 3'b111;

  wire insn_slli = insn_opcode == OpRegImm && insn_from_imem[14:12] == 3'b001 && insn_from_imem[31:25] == 7'd0;
  wire insn_srli = insn_opcode == OpRegImm && insn_from_imem[14:12] == 3'b101 && insn_from_imem[31:25] == 7'd0;
  wire insn_srai = insn_opcode == OpRegImm && insn_from_imem[14:12] == 3'b101 && insn_from_imem[31:25] == 7'b0100000;

  wire insn_add  = insn_opcode == OpRegReg && insn_from_imem[14:12] == 3'b000 && insn_from_imem[31:25] == 7'd0;
  wire insn_sub  = insn_opcode == OpRegReg && insn_from_imem[14:12] == 3'b000 && insn_from_imem[31:25] == 7'b0100000;
  wire insn_sll  = insn_opcode == OpRegReg && insn_from_imem[14:12] == 3'b001 && insn_from_imem[31:25] == 7'd0;
  wire insn_slt  = insn_opcode == OpRegReg && insn_from_imem[14:12] == 3'b010 && insn_from_imem[31:25] == 7'd0;
  wire insn_sltu = insn_opcode == OpRegReg && insn_from_imem[14:12] == 3'b011 && insn_from_imem[31:25] == 7'd0;
  wire insn_xor  = insn_opcode == OpRegReg && insn_from_imem[14:12] == 3'b100 && insn_from_imem[31:25] == 7'd0;
  wire insn_srl  = insn_opcode == OpRegReg && insn_from_imem[14:12] == 3'b101 && insn_from_imem[31:25] == 7'd0;
  wire insn_sra  = insn_opcode == OpRegReg && insn_from_imem[14:12] == 3'b101 && insn_from_imem[31:25] == 7'b0100000;
  wire insn_or   = insn_opcode == OpRegReg && insn_from_imem[14:12] == 3'b110 && insn_from_imem[31:25] == 7'd0;
  wire insn_and  = insn_opcode == OpRegReg && insn_from_imem[14:12] == 3'b111 && insn_from_imem[31:25] == 7'd0;

  wire insn_mul    = insn_opcode == OpRegReg && insn_from_imem[31:25] == 7'd1 && insn_from_imem[14:12] == 3'b000;
  wire insn_mulh   = insn_opcode == OpRegReg && insn_from_imem[31:25] == 7'd1 && insn_from_imem[14:12] == 3'b001;
  wire insn_mulhsu = insn_opcode == OpRegReg && insn_from_imem[31:25] == 7'd1 && insn_from_imem[14:12] == 3'b010;
  wire insn_mulhu  = insn_opcode == OpRegReg && insn_from_imem[31:25] == 7'd1 && insn_from_imem[14:12] == 3'b011;
  wire insn_div    = insn_opcode == OpRegReg && insn_from_imem[31:25] == 7'd1 && insn_from_imem[14:12] == 3'b100;
  wire insn_divu   = insn_opcode == OpRegReg && insn_from_imem[31:25] == 7'd1 && insn_from_imem[14:12] == 3'b101;
  wire insn_rem    = insn_opcode == OpRegReg && insn_from_imem[31:25] == 7'd1 && insn_from_imem[14:12] == 3'b110;
  wire insn_remu   = insn_opcode == OpRegReg && insn_from_imem[31:25] == 7'd1 && insn_from_imem[14:12] == 3'b111;

  wire insn_ecall = insn_opcode == OpEnviron && insn_from_imem[31:7] == 25'd0;
  wire insn_fence = insn_opcode == OpMiscMem;

  `ifndef SYNTHESIS
  `include "../hw3-singlecycle/RvDisassembler.sv"
  string disasm_string;
  always_comb begin
    disasm_string = rv_disasm(insn_from_imem);
  end
  wire [(8*32)-1:0] disasm_wire;
  genvar i;
  for (i = 0; i < 32; i = i + 1) begin : gen_disasm
    assign disasm_wire[(((i+1))*8)-1:((i)*8)] = disasm_string[31-i];
  end
  `endif

  // ── Divide stall logic ────────────────────────────────────────────
  wire is_divide = (insn_opcode == OpRegReg) && (insn_funct7 == 7'd1) &&
                   (insn_funct3[2] == 1'b1);

  logic [3:0] div_cycle_count;
  wire div_stall = is_divide && (div_cycle_count != 4'd7);

  always_ff @(posedge clk) begin
    if (rst) begin
      div_cycle_count <= 4'd0;
    end else if (is_divide) begin
      if (div_cycle_count == 4'd8)
        div_cycle_count <= 4'd0;
      else
        div_cycle_count <= div_cycle_count + 4'd1;
    end else begin
      div_cycle_count <= 4'd0;
    end
  end

  // ── Program counter ──────────────────────────────────────────────
  logic [`REG_SIZE] pcNext, pcCurrent;
  always_ff @(posedge clk) begin
    if (rst) begin
      pcCurrent <= 32'd0;
    end else if (!div_stall) begin
      pcCurrent <= pcNext;
    end
  end
  assign pc_to_imem = pcCurrent;

  // ── Cycle/insn counters ───────────────────────────────────────────
  logic [`REG_SIZE] cycles_current;
  logic [`REG_SIZE] num_insns_current;
  always_ff @(posedge clk) begin
    if (rst) begin
      cycles_current    <= 0;
      num_insns_current <= 0;
    end else begin
      cycles_current <= cycles_current + 1;
      if (!div_stall)
        num_insns_current <= num_insns_current + 1;
    end
  end

  // ── Register file ─────────────────────────────────────────────────
  wire [`REG_SIZE] rs1_data, rs2_data;
  logic [`REG_SIZE] rd_data;
  logic we;
  logic rf_we;
  assign rf_we = we && !div_stall;

  RegFile rf (
      .clk(clk), .rst(rst),
      .we(rf_we),
      .rd(insn_rd),
      .rd_data(rd_data),
      .rs1(insn_rs1), .rs1_data(rs1_data),
      .rs2(insn_rs2), .rs2_data(rs2_data)
  );

  // ── CLA adder ─────────────────────────────────────────────────────
  logic [`REG_SIZE] cla_a, cla_b, cla_sum;
  logic cla_cin;

  CarryLookaheadAdder cla_inst (
      .a(cla_a), .b(cla_b), .cin(cla_cin), .sum(cla_sum)
  );

  // ── Pipelined divider ─────────────────────────────────────────────
  logic [`REG_SIZE] div_dividend, div_divisor;
  wire  [`REG_SIZE] div_quotient, div_remainder;

  DividerUnsignedPipelined divider_inst (
      .clk(clk),
      .rst(rst),
      .stall(1'b0),
      .i_dividend(div_dividend),
      .i_divisor(div_divisor),
      .o_quotient(div_quotient),
      .o_remainder(div_remainder)
  );

  // ── Main combinational logic ──────────────────────────────────────
  logic [`REG_SIZE] load_addr, store_addr;
  logic illegal_insn;

  always_comb begin
    illegal_insn = 1'b0;
    halt         = 1'b0;

    pcNext             = pcCurrent + 32'd4;
    rd_data            = 32'd0;
    we                 = 1'b0;

    cla_a   = 32'd0;
    cla_b   = 32'd0;
    cla_cin = 1'b0;

    div_dividend = 32'd0;
    div_divisor  = 32'd1;

    load_addr          = 32'd0;
    store_addr         = 32'd0;
    addr_to_dmem       = 32'd0;
    store_data_to_dmem = 32'd0;
    store_we_to_dmem   = 4'b0000;

    trace_completed_pc           = pcCurrent;
    trace_completed_insn         = insn_from_imem;
    trace_completed_cycle_status = is_divide ? CYCLE_DIV : CYCLE_NO_STALL;

    case (insn_opcode)
      OpLui: begin
        rd_data = {insn_from_imem[31:12], 12'b0};
        we = 1'b1;
      end
      OpAuipc: begin
        rd_data = pcCurrent + {insn_from_imem[31:12], 12'b0};
        we = 1'b1;
      end
      OpRegImm: begin
        we = 1'b1;
        case (insn_funct3)
          3'b000: begin
            cla_a   = rs1_data;
            cla_b   = imm_i_sext;
            cla_cin = 1'b0;
            rd_data = cla_sum;
          end
          3'b010: rd_data = ($signed(rs1_data) < $signed(imm_i_sext)) ? 32'd1 : 32'd0;
          3'b011: rd_data = (rs1_data < imm_i_sext) ? 32'd1 : 32'd0;
          3'b100: rd_data = rs1_data ^ imm_i_sext;
          3'b110: rd_data = rs1_data | imm_i_sext;
          3'b111: rd_data = rs1_data & imm_i_sext;
          3'b001: rd_data = rs1_data << imm_shamt;
          3'b101: begin
            if (insn_funct7 == 7'b0000000)
              rd_data = rs1_data >> imm_shamt;
            else
              rd_data = $signed(rs1_data) >>> imm_shamt;
          end
          default: illegal_insn = 1'b1;
        endcase
      end
      OpRegReg: begin
        we = 1'b1;
        case (insn_funct3)
          3'b000: begin
            if (insn_funct7 == 7'd1) begin
              rd_data = rs1_data * rs2_data;
            end else if (insn_funct7 == 7'd0) begin
              cla_a = rs1_data; cla_b = rs2_data; cla_cin = 1'b0;
              rd_data = cla_sum;
            end else begin
              cla_a = rs1_data; cla_b = ~rs2_data; cla_cin = 1'b1;
              rd_data = cla_sum;
            end
          end
          3'b001: begin
            if (insn_funct7 == 7'd1)
              rd_data = 32'($signed(($signed({{32{rs1_data[31]}}, rs1_data}) *
                         $signed({{32{rs2_data[31]}}, rs2_data}))) >>> 32);
            else
              rd_data = rs1_data << rs2_data[4:0];
          end
          3'b010: begin
            if (insn_funct7 == 7'd1)
              rd_data = 32'($signed(($signed({{32{rs1_data[31]}}, rs1_data}) *
                         {32'd0, rs2_data})) >>> 32);
            else
              rd_data = ($signed(rs1_data) < $signed(rs2_data)) ? 32'd1 : 32'd0;
          end
          3'b011: begin
            if (insn_funct7 == 7'd1)
              rd_data = 32'(({32'd0, rs1_data} * {32'd0, rs2_data}) >> 32);
            else
              rd_data = (rs1_data < rs2_data) ? 32'd1 : 32'd0;
          end
          3'b100: begin
            if (insn_funct7 == 7'd1) begin // div signed
              if (rs2_data == 32'd0)
                rd_data = 32'hFFFFFFFF;
              else if (rs1_data == 32'h80000000 && rs2_data == 32'hFFFFFFFF)
                rd_data = 32'h80000000;
              else begin
                div_dividend = rs1_data[31] ? (~rs1_data + 32'd1) : rs1_data;
                div_divisor  = rs2_data[31] ? (~rs2_data + 32'd1) : rs2_data;
                rd_data      = (rs1_data[31] ^ rs2_data[31]) ?
                               (~div_quotient + 32'd1) : div_quotient;
              end
            end else
              rd_data = rs1_data ^ rs2_data;
          end
          3'b101: begin
            if (insn_funct7 == 7'd1) begin // divu
              if (rs2_data == 32'd0)
                rd_data = 32'hFFFFFFFF;
              else begin
                div_dividend = rs1_data;
                div_divisor  = rs2_data;
                rd_data      = div_quotient;
              end
            end else if (insn_funct7 == 7'b0000000)
              rd_data = rs1_data >> rs2_data[4:0];
            else
              rd_data = $signed(rs1_data) >>> rs2_data[4:0];
          end
          3'b110: begin
            if (insn_funct7 == 7'd1) begin // rem signed
              if (rs2_data == 32'd0)
                rd_data = rs1_data;
              else if (rs1_data == 32'h80000000 && rs2_data == 32'hFFFFFFFF)
                rd_data = 32'd0;
              else begin
                div_dividend = rs1_data[31] ? (~rs1_data + 32'd1) : rs1_data;
                div_divisor  = rs2_data[31] ? (~rs2_data + 32'd1) : rs2_data;
                rd_data      = rs1_data[31] ? (~div_remainder + 32'd1) : div_remainder;
              end
            end else
              rd_data = rs1_data | rs2_data;
          end
          3'b111: begin
            if (insn_funct7 == 7'd1) begin // remu
              if (rs2_data == 32'd0)
                rd_data = rs1_data;
              else begin
                div_dividend = rs1_data;
                div_divisor  = rs2_data;
                rd_data      = div_remainder;
              end
            end else
              rd_data = rs1_data & rs2_data;
          end
          default: illegal_insn = 1'b1;
        endcase
      end
      OpBranch: begin
        case (insn_funct3)
          3'b000: if (rs1_data == rs2_data)                    pcNext = pcCurrent + imm_b_sext;
          3'b001: if (rs1_data != rs2_data)                    pcNext = pcCurrent + imm_b_sext;
          3'b100: if ($signed(rs1_data) < $signed(rs2_data))  pcNext = pcCurrent + imm_b_sext;
          3'b101: if ($signed(rs1_data) >= $signed(rs2_data)) pcNext = pcCurrent + imm_b_sext;
          3'b110: if (rs1_data < rs2_data)                     pcNext = pcCurrent + imm_b_sext;
          3'b111: if (rs1_data >= rs2_data)                    pcNext = pcCurrent + imm_b_sext;
          default: illegal_insn = 1'b1;
        endcase
      end
      OpJal: begin
        rd_data = pcCurrent + 32'd4;
        we      = 1'b1;
        pcNext  = pcCurrent + imm_j_sext;
      end
      OpJalr: begin
        rd_data = pcCurrent + 32'd4;
        we      = 1'b1;
        pcNext  = (rs1_data + imm_i_sext) & ~32'd1;
      end
      OpLoad: begin
        we = 1'b1;
        load_addr    = rs1_data + imm_i_sext;
        addr_to_dmem = {load_addr[31:2], 2'b00};
        case (insn_funct3)
          3'b000: begin
            case (load_addr[1:0])
              2'b00: rd_data = {{24{load_data_from_dmem[7]}},  load_data_from_dmem[7:0]};
              2'b01: rd_data = {{24{load_data_from_dmem[15]}}, load_data_from_dmem[15:8]};
              2'b10: rd_data = {{24{load_data_from_dmem[23]}}, load_data_from_dmem[23:16]};
              2'b11: rd_data = {{24{load_data_from_dmem[31]}}, load_data_from_dmem[31:24]};
              default: rd_data = 32'd0;
            endcase
          end
          3'b001: begin
            case (load_addr[1])
              1'b0: rd_data = {{16{load_data_from_dmem[15]}}, load_data_from_dmem[15:0]};
              1'b1: rd_data = {{16{load_data_from_dmem[31]}}, load_data_from_dmem[31:16]};
              default: rd_data = 32'd0;
            endcase
          end
          3'b010: rd_data = load_data_from_dmem;
          3'b100: begin
            case (load_addr[1:0])
              2'b00: rd_data = {24'd0, load_data_from_dmem[7:0]};
              2'b01: rd_data = {24'd0, load_data_from_dmem[15:8]};
              2'b10: rd_data = {24'd0, load_data_from_dmem[23:16]};
              2'b11: rd_data = {24'd0, load_data_from_dmem[31:24]};
              default: rd_data = 32'd0;
            endcase
          end
          3'b101: begin
            case (load_addr[1])
              1'b0: rd_data = {16'd0, load_data_from_dmem[15:0]};
              1'b1: rd_data = {16'd0, load_data_from_dmem[31:16]};
              default: rd_data = 32'd0;
            endcase
          end
          default: illegal_insn = 1'b1;
        endcase
      end
      OpStore: begin
        store_addr   = rs1_data + imm_s_sext;
        addr_to_dmem = {store_addr[31:2], 2'b00};
        case (insn_funct3)
          3'b000: begin
            case (store_addr[1:0])
              2'b00: begin store_data_to_dmem = {24'd0, rs2_data[7:0]};       store_we_to_dmem = 4'b0001; end
              2'b01: begin store_data_to_dmem = {16'd0, rs2_data[7:0], 8'd0}; store_we_to_dmem = 4'b0010; end
              2'b10: begin store_data_to_dmem = {8'd0, rs2_data[7:0], 16'd0}; store_we_to_dmem = 4'b0100; end
              2'b11: begin store_data_to_dmem = {rs2_data[7:0], 24'd0};       store_we_to_dmem = 4'b1000; end
              default: store_we_to_dmem = 4'b0000;
            endcase
          end
          3'b001: begin
            case (store_addr[1])
              1'b0: begin store_data_to_dmem = {16'd0, rs2_data[15:0]};  store_we_to_dmem = 4'b0011; end
              1'b1: begin store_data_to_dmem = {rs2_data[15:0], 16'd0};  store_we_to_dmem = 4'b1100; end
              default: store_we_to_dmem = 4'b0000;
            endcase
          end
          3'b010: begin
            store_data_to_dmem = rs2_data;
            store_we_to_dmem   = 4'b1111;
          end
          default: illegal_insn = 1'b1;
        endcase
      end
      OpEnviron: begin
        if (insn_ecall) halt = 1'b1;
      end
      OpMiscMem: begin
        // fence: nop
      end
      default: illegal_insn = 1'b1;
    endcase
  end

endmodule

module MemorySingleCycle #(
    parameter int NUM_WORDS = 512
) (
    input wire rst,
    input wire clock_mem,
    input wire [`REG_SIZE] pc_to_imem,
    output logic [`INSN_SIZE] insn_from_imem,
    input wire [`REG_SIZE] addr_to_dmem,
    output logic [`REG_SIZE] load_data_from_dmem,
    input wire [`REG_SIZE] store_data_to_dmem,
    input wire [3:0] store_we_to_dmem
);
  logic [`REG_SIZE] mem_array[NUM_WORDS];

`ifdef SYNTHESIS
  initial begin
    $readmemh("mem_initial_contents.hex", mem_array);
  end
`endif

  always_comb begin
    assert (pc_to_imem[1:0] == 2'b00);
    assert (addr_to_dmem[1:0] == 2'b00);
  end

  localparam int AddrMsb = $clog2(NUM_WORDS) + 1;
  localparam int AddrLsb = 2;

  always @(posedge clock_mem) begin
    if (rst) begin
    end else begin
      insn_from_imem <= mem_array[{pc_to_imem[AddrMsb:AddrLsb]}];
    end
  end

  always @(negedge clock_mem) begin
    if (rst) begin
    end else begin
      if (store_we_to_dmem[0]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][7:0]   <= store_data_to_dmem[7:0];
      if (store_we_to_dmem[1]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][15:8]  <= store_data_to_dmem[15:8];
      if (store_we_to_dmem[2]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][23:16] <= store_data_to_dmem[23:16];
      if (store_we_to_dmem[3]) mem_array[addr_to_dmem[AddrMsb:AddrLsb]][31:24] <= store_data_to_dmem[31:24];
      load_data_from_dmem <= mem_array[{addr_to_dmem[AddrMsb:AddrLsb]}];
    end
  end
endmodule

module Processor (
    input wire               clock_proc,
    input wire               clock_mem,
    input wire               rst,
    output wire [`REG_SIZE]  trace_completed_pc,
    output wire [`INSN_SIZE] trace_completed_insn,
    output cycle_status_e    trace_completed_cycle_status,
    output logic             halt
);
  wire [`REG_SIZE] pc_to_imem, mem_data_addr, mem_data_loaded_value, mem_data_to_write;
  wire [`INSN_SIZE] insn_from_imem;
  wire [3:0] mem_data_we;
  wire [(8*32)-1:0] test_case;

  MemorySingleCycle #(.NUM_WORDS(8192)) memory (
      .rst(rst), .clock_mem(clock_mem),
      .pc_to_imem(pc_to_imem), .insn_from_imem(insn_from_imem),
      .addr_to_dmem(mem_data_addr),
      .load_data_from_dmem(mem_data_loaded_value),
      .store_data_to_dmem(mem_data_to_write),
      .store_we_to_dmem(mem_data_we)
  );

  DatapathMultiCycle datapath (
      .clk(clock_proc), .rst(rst),
      .pc_to_imem(pc_to_imem), .insn_from_imem(insn_from_imem),
      .addr_to_dmem(mem_data_addr),
      .store_data_to_dmem(mem_data_to_write),
      .store_we_to_dmem(mem_data_we),
      .load_data_from_dmem(mem_data_loaded_value),
      .trace_completed_pc(trace_completed_pc),
      .trace_completed_insn(trace_completed_insn),
      .trace_completed_cycle_status(trace_completed_cycle_status),
      .halt(halt)
  );
endmodule
