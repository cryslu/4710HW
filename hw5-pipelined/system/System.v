module MyClockGen (
	input_clk_25MHz,
	clk_proc,
	locked
);
	input input_clk_25MHz;
	output wire clk_proc;
	output wire locked;
	wire clkfb;
	(* FREQUENCY_PIN_CLKI = "25" *) (* FREQUENCY_PIN_CLKOP = "20" *) (* ICP_CURRENT = "12" *) (* LPF_RESISTOR = "8" *) (* MFG_ENABLE_FILTEROPAMP = "1" *) (* MFG_GMCREF_SEL = "2" *) EHXPLLL #(
		.PLLRST_ENA("DISABLED"),
		.INTFB_WAKE("DISABLED"),
		.STDBY_ENABLE("DISABLED"),
		.DPHASE_SOURCE("DISABLED"),
		.OUTDIVIDER_MUXA("DIVA"),
		.OUTDIVIDER_MUXB("DIVB"),
		.OUTDIVIDER_MUXC("DIVC"),
		.OUTDIVIDER_MUXD("DIVD"),
		.CLKI_DIV(5),
		.CLKOP_ENABLE("ENABLED"),
		.CLKOP_DIV(30),
		.CLKOP_CPHASE(15),
		.CLKOP_FPHASE(0),
		.FEEDBK_PATH("INT_OP"),
		.CLKFB_DIV(4)
	) pll_i(
		.RST(1'b0),
		.STDBY(1'b0),
		.CLKI(input_clk_25MHz),
		.CLKOP(clk_proc),
		.CLKFB(clkfb),
		.CLKINTFB(clkfb),
		.PHASESEL0(1'b0),
		.PHASESEL1(1'b0),
		.PHASEDIR(1'b1),
		.PHASESTEP(1'b1),
		.PHASELOADREG(1'b1),
		.PLLWAKESYNC(1'b0),
		.ENCLKOP(1'b0),
		.LOCK(locked)
	);
endmodule
module gp4 (
	gin,
	pin,
	cin,
	gout,
	pout,
	cout
);
	input wire [3:0] gin;
	input wire [3:0] pin;
	input wire cin;
	output wire gout;
	output wire pout;
	output wire [2:0] cout;
	assign pout = ((pin[0] & pin[1]) & pin[2]) & pin[3];
	wire g1;
	wire g2;
	wire g3;
	assign g1 = ((pin[1] & pin[2]) & pin[3]) & gin[0];
	assign g2 = (pin[2] & pin[3]) & gin[1];
	assign g3 = pin[3] & gin[2];
	assign gout = ((g1 | g2) | g3) | gin[3];
	assign cout[0] = gin[0] | (pin[0] & cin);
	assign cout[1] = (gin[1] | (pin[1] & gin[0])) | ((pin[1] & pin[0]) & cin);
	assign cout[2] = ((gin[2] | (pin[2] & gin[1])) | ((pin[2] & pin[1]) & gin[0])) | (((pin[2] & pin[1]) & pin[0]) & cin);
endmodule
module gp8 (
	gin,
	pin,
	cin,
	gout,
	pout,
	cout
);
	input wire [7:0] gin;
	input wire [7:0] pin;
	input wire cin;
	output wire gout;
	output wire pout;
	output wire [6:0] cout;
	wire g0;
	wire p0;
	wire g1;
	wire p1;
	wire c4;
	gp4 block0(
		.gin(gin[3:0]),
		.pin(pin[3:0]),
		.cin(cin),
		.gout(g0),
		.pout(p0),
		.cout(cout[2:0])
	);
	assign c4 = g0 | (p0 & cin);
	assign cout[3] = c4;
	gp4 block1(
		.gin(gin[7:4]),
		.pin(pin[7:4]),
		.cin(c4),
		.gout(g1),
		.pout(p1),
		.cout(cout[6:4])
	);
	assign gout = g1 | (p1 & g0);
	assign pout = p1 & p0;
endmodule
module CarryLookaheadAdder (
	a,
	b,
	cin,
	sum
);
	input wire [31:0] a;
	input wire [31:0] b;
	input wire cin;
	output wire [31:0] sum;
	wire [31:0] g;
	wire [31:0] p;
	assign g = a & b;
	assign p = a ^ b;
	wire g0;
	wire p0;
	wire g1;
	wire p1;
	wire g2;
	wire p2;
	wire g3;
	wire p3;
	wire [6:0] carries0;
	wire [6:0] carries1;
	wire [6:0] carries2;
	wire [6:0] carries3;
	wire c8;
	wire c16;
	wire c24;
	gp8 block0(
		.gin(g[7:0]),
		.pin(p[7:0]),
		.cin(cin),
		.gout(g0),
		.pout(p0),
		.cout(carries0)
	);
	gp8 block1(
		.gin(g[15:8]),
		.pin(p[15:8]),
		.cin(c8),
		.gout(g1),
		.pout(p1),
		.cout(carries1)
	);
	gp8 block2(
		.gin(g[23:16]),
		.pin(p[23:16]),
		.cin(c16),
		.gout(g2),
		.pout(p2),
		.cout(carries2)
	);
	gp8 block3(
		.gin(g[31:24]),
		.pin(p[31:24]),
		.cin(c24),
		.gout(g3),
		.pout(p3),
		.cout(carries3)
	);
	assign c8 = g0 | (p0 & cin);
	assign c16 = (g1 | (p1 & g0)) | ((p1 & p0) & cin);
	assign c24 = ((g2 | (p2 & g1)) | ((p2 & p1) & g0)) | (((p2 & p1) & p0) & cin);
	assign sum[0] = p[0] ^ cin;
	assign sum[7:1] = p[7:1] ^ carries0;
	assign sum[8] = p[8] ^ c8;
	assign sum[15:9] = p[15:9] ^ carries1;
	assign sum[16] = p[16] ^ c16;
	assign sum[23:17] = p[23:17] ^ carries2;
	assign sum[24] = p[24] ^ c24;
	assign sum[31:25] = p[31:25] ^ carries3;
endmodule
module DividerUnsignedPipelined (
	clk,
	rst,
	stall,
	i_dividend,
	i_divisor,
	o_remainder,
	o_quotient
);
	input wire clk;
	input wire rst;
	input wire stall;
	input wire [31:0] i_dividend;
	input wire [31:0] i_divisor;
	output wire [31:0] o_remainder;
	output wire [31:0] o_quotient;
	reg [31:0] dividend [0:7];
	reg [31:0] remainder [0:7];
	reg [31:0] quotient [0:7];
	reg [31:0] divisor [0:7];
	wire [31:0] d_in_0 = i_dividend;
	wire [31:0] r_in_0 = 32'b00000000000000000000000000000000;
	wire [31:0] q_in_0 = 32'b00000000000000000000000000000000;
	wire [31:0] div_in_0 = i_divisor;
	wire [31:0] d_out_0;
	wire [31:0] r_out_0;
	wire [31:0] q_out_0;
	divu_4iter stage0(
		.i_dividend(d_in_0),
		.i_divisor(div_in_0),
		.i_remainder(r_in_0),
		.i_quotient(q_in_0),
		.o_dividend(d_out_0),
		.o_remainder(r_out_0),
		.o_quotient(q_out_0)
	);
	always @(posedge clk)
		if (rst) begin
			dividend[0] <= 0;
			remainder[0] <= 0;
			quotient[0] <= 0;
			divisor[0] <= 0;
		end
		else begin
			dividend[0] <= d_out_0;
			remainder[0] <= r_out_0;
			quotient[0] <= q_out_0;
			divisor[0] <= div_in_0;
		end
	genvar _gv_s_1;
	generate
		for (_gv_s_1 = 1; _gv_s_1 < 7; _gv_s_1 = _gv_s_1 + 1) begin : stage
			localparam s = _gv_s_1;
			wire [31:0] d_next;
			wire [31:0] r_next;
			wire [31:0] q_next;
			divu_4iter stage_logic(
				.i_dividend(dividend[s - 1]),
				.i_divisor(divisor[s - 1]),
				.i_remainder(remainder[s - 1]),
				.i_quotient(quotient[s - 1]),
				.o_dividend(d_next),
				.o_remainder(r_next),
				.o_quotient(q_next)
			);
			always @(posedge clk)
				if (rst) begin
					dividend[s] <= 0;
					remainder[s] <= 0;
					quotient[s] <= 0;
					divisor[s] <= 0;
				end
				else begin
					dividend[s] <= d_next;
					remainder[s] <= r_next;
					quotient[s] <= q_next;
					divisor[s] <= divisor[s - 1];
				end
		end
	endgenerate
	wire [31:0] unused_dividend;
	divu_4iter stage_7(
		.i_dividend(dividend[6]),
		.i_divisor(divisor[6]),
		.i_remainder(remainder[6]),
		.i_quotient(quotient[6]),
		.o_dividend(unused_dividend),
		.o_remainder(o_remainder),
		.o_quotient(o_quotient)
	);
endmodule
module divu_4iter (
	i_dividend,
	i_divisor,
	i_remainder,
	i_quotient,
	o_dividend,
	o_remainder,
	o_quotient
);
	input wire [31:0] i_dividend;
	input wire [31:0] i_divisor;
	input wire [31:0] i_remainder;
	input wire [31:0] i_quotient;
	output wire [31:0] o_dividend;
	output wire [31:0] o_remainder;
	output wire [31:0] o_quotient;
	wire [31:0] d [0:4];
	wire [31:0] r [0:4];
	wire [31:0] q [0:4];
	assign d[0] = i_dividend;
	assign r[0] = i_remainder;
	assign q[0] = i_quotient;
	genvar _gv_i_1;
	generate
		for (_gv_i_1 = 0; _gv_i_1 < 4; _gv_i_1 = _gv_i_1 + 1) begin : iter
			localparam i = _gv_i_1;
			divu_1iter u(
				.i_dividend(d[i]),
				.i_divisor(i_divisor),
				.i_remainder(r[i]),
				.i_quotient(q[i]),
				.o_dividend(d[i + 1]),
				.o_remainder(r[i + 1]),
				.o_quotient(q[i + 1])
			);
		end
	endgenerate
	assign o_dividend = d[4];
	assign o_remainder = r[4];
	assign o_quotient = q[4];
endmodule
module divu_1iter (
	i_dividend,
	i_divisor,
	i_remainder,
	i_quotient,
	o_dividend,
	o_remainder,
	o_quotient
);
	input wire [31:0] i_dividend;
	input wire [31:0] i_divisor;
	input wire [31:0] i_remainder;
	input wire [31:0] i_quotient;
	output wire [31:0] o_dividend;
	output wire [31:0] o_remainder;
	output wire [31:0] o_quotient;
	wire [31:0] new_remainder;
	assign new_remainder = (i_remainder << 1) | ((i_dividend >> 31) & 32'b00000000000000000000000000000001);
	wire can_subtract;
	assign can_subtract = new_remainder >= i_divisor;
	assign o_quotient = (can_subtract ? (i_quotient << 1) | 32'b00000000000000000000000000000001 : i_quotient << 1);
	assign o_remainder = (can_subtract ? new_remainder - i_divisor : new_remainder);
	assign o_dividend = i_dividend << 1;
endmodule
module Disasm (
	insn,
	disasm
);
	parameter signed [7:0] PREFIX = "D";
	input wire [31:0] insn;
	output wire [255:0] disasm;
endmodule
module RegFile (
	rd,
	rd_data,
	rs1,
	rs1_data,
	rs2,
	rs2_data,
	clk,
	we,
	rst
);
	input wire [4:0] rd;
	input wire [31:0] rd_data;
	input wire [4:0] rs1;
	output wire [31:0] rs1_data;
	input wire [4:0] rs2;
	output wire [31:0] rs2_data;
	input wire clk;
	input wire we;
	input wire rst;
	localparam signed [31:0] NumRegs = 32;
	reg [31:0] regs [0:31];
	assign rs1_data = (rs1 == 5'd0 ? {32 {1'sb0}} : ((we && (rd == rs1)) && (rd != 5'd0) ? rd_data : regs[rs1]));
	assign rs2_data = (rs2 == 5'd0 ? {32 {1'sb0}} : ((we && (rd == rs2)) && (rd != 5'd0) ? rd_data : regs[rs2]));
	always @(posedge clk)
		if (rst) begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < NumRegs; i = i + 1)
				regs[i] <= 1'sb0;
		end
		else if (we && (rd != 5'd0))
			regs[rd] <= rd_data;
endmodule
module DatapathPipelined (
	clk,
	rst,
	pc_to_imem,
	insn_from_imem,
	addr_to_dmem,
	load_data_from_dmem,
	store_data_to_dmem,
	store_we_to_dmem,
	halt,
	trace_writeback_pc,
	trace_writeback_insn,
	trace_writeback_cycle_status
);
	reg _sv2v_0;
	input wire clk;
	input wire rst;
	output wire [31:0] pc_to_imem;
	input wire [31:0] insn_from_imem;
	output reg [31:0] addr_to_dmem;
	input wire [31:0] load_data_from_dmem;
	output reg [31:0] store_data_to_dmem;
	output reg [3:0] store_we_to_dmem;
	output wire halt;
	output wire [31:0] trace_writeback_pc;
	output wire [31:0] trace_writeback_insn;
	output wire [31:0] trace_writeback_cycle_status;
	localparam [6:0] OpcodeLoad = 7'b0000011;
	localparam [6:0] OpcodeStore = 7'b0100011;
	localparam [6:0] OpcodeBranch = 7'b1100011;
	localparam [6:0] OpcodeJalr = 7'b1100111;
	localparam [6:0] OpcodeMiscMem = 7'b0001111;
	localparam [6:0] OpcodeJal = 7'b1101111;
	localparam [6:0] OpcodeRegImm = 7'b0010011;
	localparam [6:0] OpcodeRegReg = 7'b0110011;
	localparam [6:0] OpcodeEnviron = 7'b1110011;
	localparam [6:0] OpcodeAuipc = 7'b0010111;
	localparam [6:0] OpcodeLui = 7'b0110111;
	reg [31:0] cycles_current;
	always @(posedge clk)
		if (rst)
			cycles_current <= 0;
		else
			cycles_current <= cycles_current + 1;
	reg [31:0] f_pc_current;
	wire [31:0] f_insn;
	reg [31:0] f_cycle_status;
	wire x_redirect_valid;
	wire [31:0] x_redirect_pc;
	wire stall_f;
	wire stall_d;
	wire flush_d;
	wire flush_x;
	wire load_use_bubble;
	reg div_stall;
	always @(posedge clk)
		if (rst) begin
			f_pc_current <= 32'd0;
			f_cycle_status <= 32'd1;
		end
		else if (!stall_f) begin
			f_cycle_status <= 32'd1;
			if (x_redirect_valid)
				f_pc_current <= x_redirect_pc;
			else
				f_pc_current <= f_pc_current + 4;
		end
	assign pc_to_imem = f_pc_current;
	assign f_insn = insn_from_imem;
	wire [255:0] f_disasm;
	Disasm #(.PREFIX("F")) disasm_0fetch(
		.insn(f_insn),
		.disasm(f_disasm)
	);
	reg [95:0] decode_state;
	always @(posedge clk)
		if (rst)
			decode_state <= 96'h000000000000000000000004;
		else if (flush_d)
			decode_state <= 96'h000000000000000000000008;
		else if (!stall_d)
			decode_state <= {f_pc_current, f_insn, f_cycle_status};
	wire [255:0] d_disasm;
	Disasm #(.PREFIX("D")) disasm_1decode(
		.insn(decode_state[63-:32]),
		.disasm(d_disasm)
	);
	wire [6:0] d_funct7 = decode_state[63:57];
	wire [4:0] d_rs2 = decode_state[56:52];
	wire [4:0] d_rs1 = decode_state[51:47];
	wire [2:0] d_funct3 = decode_state[46:44];
	wire [4:0] d_rd = decode_state[43:39];
	wire [6:0] d_opcode = decode_state[38:32];
	wire [11:0] d_imm_i = decode_state[63:52];
	wire [4:0] d_imm_shamt = decode_state[56:52];
	wire [11:0] d_imm_s;
	assign d_imm_s[11:5] = d_funct7;
	assign d_imm_s[4:0] = d_rd;
	wire [12:0] d_imm_b;
	assign {d_imm_b[12], d_imm_b[10:5]} = d_funct7;
	assign {d_imm_b[4:1], d_imm_b[11]} = d_rd;
	assign d_imm_b[0] = 1'b0;
	wire [20:0] d_imm_j;
	assign {d_imm_j[20], d_imm_j[10:1], d_imm_j[11], d_imm_j[19:12], d_imm_j[0]} = {decode_state[63:44], 1'b0};
	wire [31:0] d_imm_i_sext = {{20 {d_imm_i[11]}}, d_imm_i};
	wire [31:0] d_imm_s_sext = {{20 {d_imm_s[11]}}, d_imm_s};
	wire [31:0] d_imm_b_sext = {{19 {d_imm_b[12]}}, d_imm_b};
	wire [31:0] d_imm_j_sext = {{11 {d_imm_j[20]}}, d_imm_j};
	wire wb_rf_we;
	wire [4:0] wb_rd;
	wire [31:0] wb_rd_data;
	wire [31:0] d_rs1_data;
	wire [31:0] d_rs2_data;
	RegFile rf(
		.clk(clk),
		.rst(rst),
		.we(wb_rf_we),
		.rd(wb_rd),
		.rd_data(wb_rd_data),
		.rs1(d_rs1),
		.rs1_data(d_rs1_data),
		.rs2(d_rs2),
		.rs2_data(d_rs2_data)
	);
	reg [307:0] execute_state;
	wire [6:0] x_opcode = execute_state[250:244];
	wire [6:0] x_funct7 = execute_state[275:269];
	wire [2:0] x_funct3 = execute_state[258:256];
	wire x_is_divide = ((x_opcode == OpcodeRegReg) && (x_funct7 == 7'd1)) && (x_funct3[2] == 1'b1);
	reg [6:0] div_pipe_valid;
	always @(*) begin
		if (_sv2v_0)
			;
		div_stall = x_is_divide && !div_pipe_valid[6];
	end
	always @(posedge clk)
		if (rst || !x_is_divide)
			div_pipe_valid <= 7'd0;
		else
			div_pipe_valid <= {div_pipe_valid[5:0], 1'b1};
	wire m_rf_we;
	wire [4:0] m_rd;
	wire [31:0] m_alu_result;
	reg [31:0] x_rs1_fwd;
	reg [31:0] x_rs2_fwd;
	always @(*) begin
		if (_sv2v_0)
			;
		if ((m_rf_we && (m_rd != 5'd0)) && (m_rd == execute_state[147-:5]))
			x_rs1_fwd = m_alu_result;
		else if ((wb_rf_we && (wb_rd != 5'd0)) && (wb_rd == execute_state[147-:5]))
			x_rs1_fwd = wb_rd_data;
		else
			x_rs1_fwd = execute_state[211-:32];
		if ((m_rf_we && (m_rd != 5'd0)) && (m_rd == execute_state[142-:5]))
			x_rs2_fwd = m_alu_result;
		else if ((wb_rf_we && (wb_rd != 5'd0)) && (wb_rd == execute_state[142-:5]))
			x_rs2_fwd = wb_rd_data;
		else
			x_rs2_fwd = execute_state[179-:32];
	end
	reg [31:0] div_op_a_reg;
	reg [31:0] div_op_b_reg;
	reg div_rs1_neg;
	reg div_rs2_neg;
	reg div_rs2_zero;
	reg [31:0] div_rs1_orig;
	reg div_ops_latched;
	wire div_is_signed = (x_funct3[1:0] == 2'b00) || (x_funct3[1:0] == 2'b10);
	wire [31:0] div_op_a_fresh = (div_is_signed ? (x_rs1_fwd[31] ? ~x_rs1_fwd + 32'd1 : x_rs1_fwd) : x_rs1_fwd);
	wire [31:0] div_op_b_fresh = (div_is_signed ? (x_rs2_fwd[31] ? ~x_rs2_fwd + 32'd1 : x_rs2_fwd) : x_rs2_fwd);
	wire [31:0] div_op_a = (div_ops_latched ? div_op_a_reg : div_op_a_fresh);
	wire [31:0] div_op_b = (div_ops_latched ? div_op_b_reg : div_op_b_fresh);
	always @(posedge clk)
		if ((rst || !x_is_divide) || !div_stall) begin
			div_op_a_reg <= 1'sb0;
			div_op_b_reg <= 1'sb0;
			div_rs1_neg <= 1'b0;
			div_rs2_neg <= 1'b0;
			div_rs2_zero <= 1'b0;
			div_rs1_orig <= 1'sb0;
			div_ops_latched <= 1'b0;
		end
		else if (!div_ops_latched) begin
			div_op_a_reg <= div_op_a_fresh;
			div_op_b_reg <= div_op_b_fresh;
			div_rs1_neg <= x_rs1_fwd[31];
			div_rs2_neg <= x_rs2_fwd[31];
			div_rs2_zero <= x_rs2_fwd == 32'd0;
			div_rs1_orig <= x_rs1_fwd;
			div_ops_latched <= 1'b1;
		end
	wire [31:0] div_quotient;
	wire [31:0] div_remainder;
	DividerUnsignedPipelined divider_inst(
		.clk(clk),
		.rst(rst),
		.stall(1'b0),
		.i_dividend(div_op_a),
		.i_divisor(div_op_b),
		.o_quotient(div_quotient),
		.o_remainder(div_remainder)
	);
	reg [31:0] cla_a;
	reg [31:0] cla_b;
	wire [31:0] cla_sum;
	reg cla_cin;
	CarryLookaheadAdder cla_inst(
		.a(cla_a),
		.b(cla_b),
		.cin(cla_cin),
		.sum(cla_sum)
	);
	reg [31:0] x_alu_result;
	reg x_rf_we;
	reg x_branch_taken;
	reg [31:0] x_branch_target;
	reg x_halt;
	reg [31:0] x_store_data;
	reg [31:0] x_cycle_status_out;
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		x_alu_result = 32'd0;
		x_rf_we = 1'b0;
		x_branch_taken = 1'b0;
		x_branch_target = execute_state[307-:32] + 32'd4;
		x_halt = 1'b0;
		x_store_data = x_rs2_fwd;
		x_cycle_status_out = execute_state[243-:32];
		cla_a = 32'd0;
		cla_b = 32'd0;
		cla_cin = 1'b0;
		if (div_stall)
			x_cycle_status_out = 32'd2;
		case (x_opcode)
			OpcodeLui: begin
				x_alu_result = {execute_state[275:256], 12'b000000000000};
				x_rf_we = 1'b1;
			end
			OpcodeAuipc: begin
				x_alu_result = execute_state[307-:32] + {execute_state[275:256], 12'b000000000000};
				x_rf_we = 1'b1;
			end
			OpcodeRegImm: begin
				x_rf_we = 1'b1;
				case (x_funct3)
					3'b000: begin
						cla_a = x_rs1_fwd;
						cla_b = execute_state[132-:32];
						cla_cin = 1'b0;
						x_alu_result = cla_sum;
					end
					3'b010: x_alu_result = ($signed(x_rs1_fwd) < $signed(execute_state[132-:32]) ? 32'd1 : 32'd0);
					3'b011: x_alu_result = (x_rs1_fwd < execute_state[132-:32] ? 32'd1 : 32'd0);
					3'b100: x_alu_result = x_rs1_fwd ^ execute_state[132-:32];
					3'b110: x_alu_result = x_rs1_fwd | execute_state[132-:32];
					3'b111: x_alu_result = x_rs1_fwd & execute_state[132-:32];
					3'b001: x_alu_result = x_rs1_fwd << execute_state[4-:5];
					3'b101:
						if (x_funct7 == 7'b0000000)
							x_alu_result = x_rs1_fwd >> execute_state[4-:5];
						else
							x_alu_result = $signed(x_rs1_fwd) >>> execute_state[4-:5];
					default: x_rf_we = 1'b0;
				endcase
			end
			OpcodeRegReg:
				case (x_funct3)
					3'b000:
						if (x_funct7 == 7'd1) begin
							x_alu_result = x_rs1_fwd * x_rs2_fwd;
							x_rf_we = 1'b1;
						end
						else if (x_funct7 == 7'd0) begin
							cla_a = x_rs1_fwd;
							cla_b = x_rs2_fwd;
							cla_cin = 1'b0;
							x_alu_result = cla_sum;
							x_rf_we = 1'b1;
						end
						else begin
							cla_a = x_rs1_fwd;
							cla_b = ~x_rs2_fwd;
							cla_cin = 1'b1;
							x_alu_result = cla_sum;
							x_rf_we = 1'b1;
						end
					3'b001:
						if (x_funct7 == 7'd1) begin
							x_alu_result = sv2v_cast_32_signed($signed($signed({{32 {x_rs1_fwd[31]}}, x_rs1_fwd}) * $signed({{32 {x_rs2_fwd[31]}}, x_rs2_fwd})) >>> 32);
							x_rf_we = 1'b1;
						end
						else begin
							x_alu_result = x_rs1_fwd << x_rs2_fwd[4:0];
							x_rf_we = 1'b1;
						end
					3'b010:
						if (x_funct7 == 7'd1) begin
							x_alu_result = sv2v_cast_32_signed($signed($signed({{32 {x_rs1_fwd[31]}}, x_rs1_fwd}) * {32'd0, x_rs2_fwd}) >>> 32);
							x_rf_we = 1'b1;
						end
						else begin
							x_alu_result = ($signed(x_rs1_fwd) < $signed(x_rs2_fwd) ? 32'd1 : 32'd0);
							x_rf_we = 1'b1;
						end
					3'b011:
						if (x_funct7 == 7'd1) begin
							x_alu_result = sv2v_cast_32(({32'd0, x_rs1_fwd} * {32'd0, x_rs2_fwd}) >> 32);
							x_rf_we = 1'b1;
						end
						else begin
							x_alu_result = (x_rs1_fwd < x_rs2_fwd ? 32'd1 : 32'd0);
							x_rf_we = 1'b1;
						end
					3'b100:
						if (x_funct7 == 7'd1) begin
							if (!div_stall) begin
								if (div_rs2_zero)
									x_alu_result = 32'hffffffff;
								else if ((div_rs1_neg && (div_op_a_reg == 32'h80000000)) && (div_op_b_reg == 32'h00000001))
									x_alu_result = 32'h80000000;
								else
									x_alu_result = (div_rs1_neg ^ div_rs2_neg ? ~div_quotient + 32'd1 : div_quotient);
								x_rf_we = 1'b1;
							end
						end
						else begin
							x_alu_result = x_rs1_fwd ^ x_rs2_fwd;
							x_rf_we = 1'b1;
						end
					3'b101:
						if (x_funct7 == 7'd1) begin
							if (!div_stall) begin
								if (div_rs2_zero)
									x_alu_result = 32'hffffffff;
								else
									x_alu_result = div_quotient;
								x_rf_we = 1'b1;
							end
						end
						else if (x_funct7 == 7'b0000000) begin
							x_alu_result = x_rs1_fwd >> x_rs2_fwd[4:0];
							x_rf_we = 1'b1;
						end
						else begin
							x_alu_result = $signed(x_rs1_fwd) >>> x_rs2_fwd[4:0];
							x_rf_we = 1'b1;
						end
					3'b110:
						if (x_funct7 == 7'd1) begin
							if (!div_stall) begin
								if (div_rs2_zero)
									x_alu_result = div_rs1_orig;
								else if ((div_rs1_neg && (div_op_a_reg == 32'h80000000)) && (div_op_b_reg == 32'h00000001))
									x_alu_result = 32'd0;
								else
									x_alu_result = (div_rs1_neg ? ~div_remainder + 32'd1 : div_remainder);
								x_rf_we = 1'b1;
							end
						end
						else begin
							x_alu_result = x_rs1_fwd | x_rs2_fwd;
							x_rf_we = 1'b1;
						end
					3'b111:
						if (x_funct7 == 7'd1) begin
							if (!div_stall) begin
								if (div_rs2_zero)
									x_alu_result = div_rs1_orig;
								else
									x_alu_result = div_remainder;
								x_rf_we = 1'b1;
							end
						end
						else begin
							x_alu_result = x_rs1_fwd & x_rs2_fwd;
							x_rf_we = 1'b1;
						end
					default: x_rf_we = 1'b0;
				endcase
			OpcodeBranch: begin
				case (x_funct3)
					3'b000: x_branch_taken = x_rs1_fwd == x_rs2_fwd;
					3'b001: x_branch_taken = x_rs1_fwd != x_rs2_fwd;
					3'b100: x_branch_taken = $signed(x_rs1_fwd) < $signed(x_rs2_fwd);
					3'b101: x_branch_taken = $signed(x_rs1_fwd) >= $signed(x_rs2_fwd);
					3'b110: x_branch_taken = x_rs1_fwd < x_rs2_fwd;
					3'b111: x_branch_taken = x_rs1_fwd >= x_rs2_fwd;
					default: x_branch_taken = 1'b0;
				endcase
				x_branch_target = execute_state[307-:32] + execute_state[68-:32];
			end
			OpcodeJal: begin
				x_alu_result = execute_state[307-:32] + 32'd4;
				x_rf_we = 1'b1;
				x_branch_taken = 1'b1;
				x_branch_target = execute_state[307-:32] + execute_state[36-:32];
			end
			OpcodeJalr: begin
				x_alu_result = execute_state[307-:32] + 32'd4;
				x_rf_we = 1'b1;
				x_branch_taken = 1'b1;
				x_branch_target = (x_rs1_fwd + execute_state[132-:32]) & ~32'd1;
			end
			OpcodeLoad: begin
				cla_a = x_rs1_fwd;
				cla_b = execute_state[132-:32];
				cla_cin = 1'b0;
				x_alu_result = cla_sum;
				x_rf_we = 1'b1;
			end
			OpcodeStore: begin
				cla_a = x_rs1_fwd;
				cla_b = execute_state[100-:32];
				cla_cin = 1'b0;
				x_alu_result = cla_sum;
				x_store_data = x_rs2_fwd;
			end
			OpcodeEnviron:
				if (execute_state[275:251] == 25'd0)
					x_halt = 1'b1;
			OpcodeMiscMem:
				;
			default:
				;
		endcase
	end
	assign x_redirect_valid = (x_branch_taken && !div_stall) && (execute_state[243-:32] == 32'd1);
	assign x_redirect_pc = x_branch_target;
	wire x_is_load = x_opcode == OpcodeLoad;
	wire x_result_not_ready = x_is_load || div_stall;
	wire d_uses_rs1 = ((d_opcode != OpcodeLui) && (d_opcode != OpcodeAuipc)) && (d_opcode != OpcodeJal);
	wire d_uses_rs2_in_x = (d_opcode == OpcodeRegReg) || (d_opcode == OpcodeBranch);
	wire load_use_stall = (x_result_not_ready && (execute_state[137-:5] != 5'd0)) && ((d_uses_rs1 && (execute_state[137-:5] == d_rs1)) || (d_uses_rs2_in_x && (execute_state[137-:5] == d_rs2)));
	assign load_use_bubble = load_use_stall && !div_stall;
	assign stall_f = load_use_stall || div_stall;
	assign stall_d = load_use_stall || div_stall;
	assign flush_d = x_redirect_valid;
	assign flush_x = x_redirect_valid;
	always @(posedge clk)
		if (rst)
			execute_state <= 308'h400000000000000000000000000000000000000000000000000000;
		else if (flush_x)
			execute_state <= 308'h800000000000000000000000000000000000000000000000000000;
		else if (div_stall) begin
			execute_state[211-:32] <= x_rs1_fwd;
			execute_state[179-:32] <= x_rs2_fwd;
		end
		else if (load_use_bubble)
			execute_state <= 308'h1000000000000000000000000000000000000000000000000000000;
		else
			execute_state <= {sv2v_cast_32(decode_state[95-:32]), sv2v_cast_32(decode_state[63-:32]), sv2v_cast_32(decode_state[31-:32]), d_rs1_data, d_rs2_data, d_rs1, d_rs2, d_rd, d_imm_i_sext, d_imm_s_sext, d_imm_b_sext, d_imm_j_sext, d_imm_shamt};
	wire [255:0] x_disasm;
	Disasm #(.PREFIX("X")) disasm_2execute(
		.insn(execute_state[275-:32]),
		.disasm(x_disasm)
	);
	reg [166:0] memory_state;
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	always @(posedge clk)
		if (rst)
			memory_state <= 167'h000000000000000000000002000000000000000000;
		else if (div_stall)
			memory_state <= 167'h000000000000000000000001000000000000000000;
		else
			memory_state <= {sv2v_cast_32(execute_state[307-:32]), sv2v_cast_32(execute_state[275-:32]), x_cycle_status_out, x_alu_result, x_store_data, sv2v_cast_5(execute_state[137-:5]), x_rf_we, x_halt};
	assign m_rf_we = memory_state[1];
	assign m_rd = memory_state[6-:5];
	assign m_alu_result = memory_state[70-:32];
	wire [255:0] m_disasm;
	Disasm #(.PREFIX("M")) disasm_3mem(
		.insn(memory_state[134-:32]),
		.disasm(m_disasm)
	);
	wire [6:0] m_opcode = memory_state[109:103];
	wire [2:0] m_funct3 = memory_state[117:115];
	wire [4:0] m_rs2_reg = memory_state[127:123];
	wire wm_bypass_valid = (((m_opcode == OpcodeStore) && wb_rf_we) && (wb_rd != 5'd0)) && (wb_rd == m_rs2_reg);
	wire [31:0] m_store_data = (wm_bypass_valid ? wb_rd_data : memory_state[38-:32]);
	reg [31:0] m_rd_data;
	always @(*) begin
		if (_sv2v_0)
			;
		addr_to_dmem = {memory_state[70:41], 2'b00};
		store_data_to_dmem = 32'd0;
		store_we_to_dmem = 4'b0000;
		m_rd_data = memory_state[70-:32];
		if (m_opcode == OpcodeStore)
			case (m_funct3)
				3'b000:
					case (memory_state[40:39])
						2'b00: begin
							store_data_to_dmem = {24'd0, m_store_data[7:0]};
							store_we_to_dmem = 4'b0001;
						end
						2'b01: begin
							store_data_to_dmem = {16'd0, m_store_data[7:0], 8'd0};
							store_we_to_dmem = 4'b0010;
						end
						2'b10: begin
							store_data_to_dmem = {8'd0, m_store_data[7:0], 16'd0};
							store_we_to_dmem = 4'b0100;
						end
						2'b11: begin
							store_data_to_dmem = {m_store_data[7:0], 24'd0};
							store_we_to_dmem = 4'b1000;
						end
						default: store_we_to_dmem = 4'b0000;
					endcase
				3'b001:
					case (memory_state[40])
						1'b0: begin
							store_data_to_dmem = {16'd0, m_store_data[15:0]};
							store_we_to_dmem = 4'b0011;
						end
						1'b1: begin
							store_data_to_dmem = {m_store_data[15:0], 16'd0};
							store_we_to_dmem = 4'b1100;
						end
						default: store_we_to_dmem = 4'b0000;
					endcase
				3'b010: begin
					store_data_to_dmem = m_store_data;
					store_we_to_dmem = 4'b1111;
				end
				default: store_we_to_dmem = 4'b0000;
			endcase
		else if (m_opcode == OpcodeLoad)
			case (m_funct3)
				3'b000:
					case (memory_state[40:39])
						2'b00: m_rd_data = {{24 {load_data_from_dmem[7]}}, load_data_from_dmem[7:0]};
						2'b01: m_rd_data = {{24 {load_data_from_dmem[15]}}, load_data_from_dmem[15:8]};
						2'b10: m_rd_data = {{24 {load_data_from_dmem[23]}}, load_data_from_dmem[23:16]};
						2'b11: m_rd_data = {{24 {load_data_from_dmem[31]}}, load_data_from_dmem[31:24]};
						default: m_rd_data = 32'd0;
					endcase
				3'b001:
					case (memory_state[40])
						1'b0: m_rd_data = {{16 {load_data_from_dmem[15]}}, load_data_from_dmem[15:0]};
						1'b1: m_rd_data = {{16 {load_data_from_dmem[31]}}, load_data_from_dmem[31:16]};
						default: m_rd_data = 32'd0;
					endcase
				3'b010: m_rd_data = load_data_from_dmem;
				3'b100:
					case (memory_state[40:39])
						2'b00: m_rd_data = {24'd0, load_data_from_dmem[7:0]};
						2'b01: m_rd_data = {24'd0, load_data_from_dmem[15:8]};
						2'b10: m_rd_data = {24'd0, load_data_from_dmem[23:16]};
						2'b11: m_rd_data = {24'd0, load_data_from_dmem[31:24]};
						default: m_rd_data = 32'd0;
					endcase
				3'b101:
					case (memory_state[40])
						1'b0: m_rd_data = {16'd0, load_data_from_dmem[15:0]};
						1'b1: m_rd_data = {16'd0, load_data_from_dmem[31:16]};
						default: m_rd_data = 32'd0;
					endcase
				default: m_rd_data = 32'd0;
			endcase
	end
	reg [134:0] writeback_state;
	always @(posedge clk)
		if (rst)
			writeback_state <= 135'h0000000000000000000000020000000000;
		else
			writeback_state <= {sv2v_cast_32(memory_state[166-:32]), sv2v_cast_32(memory_state[134-:32]), sv2v_cast_32(memory_state[102-:32]), m_rd_data, sv2v_cast_5(memory_state[6-:5]), memory_state[1], memory_state[0]};
	wire [255:0] w_disasm;
	Disasm #(.PREFIX("W")) disasm_4wb(
		.insn(writeback_state[102-:32]),
		.disasm(w_disasm)
	);
	assign wb_rf_we = writeback_state[1];
	assign wb_rd = writeback_state[6-:5];
	assign wb_rd_data = writeback_state[38-:32];
	assign halt = writeback_state[0];
	assign trace_writeback_pc = writeback_state[134-:32];
	assign trace_writeback_insn = writeback_state[102-:32];
	assign trace_writeback_cycle_status = writeback_state[70-:32];
	wire [31:0] trace_completed_pc = writeback_state[134-:32];
	wire [31:0] trace_completed_insn = writeback_state[102-:32];
	wire [31:0] trace_completed_cycle_status;
	assign trace_completed_cycle_status = writeback_state[70-:32];
	initial _sv2v_0 = 0;
endmodule
module MemorySingleCycle (
	rst,
	clk,
	pc_to_imem,
	insn_from_imem,
	addr_to_dmem,
	load_data_from_dmem,
	store_data_to_dmem,
	store_we_to_dmem
);
	reg _sv2v_0;
	parameter signed [31:0] NUM_WORDS = 512;
	input wire rst;
	input wire clk;
	input wire [31:0] pc_to_imem;
	output reg [31:0] insn_from_imem;
	input wire [31:0] addr_to_dmem;
	output reg [31:0] load_data_from_dmem;
	input wire [31:0] store_data_to_dmem;
	input wire [3:0] store_we_to_dmem;
	reg [31:0] mem_array [0:NUM_WORDS - 1];
	initial $readmemh("mem_initial_contents.hex", mem_array);
	always @(*)
		if (_sv2v_0)
			;
	localparam signed [31:0] AddrMsb = $clog2(NUM_WORDS) + 1;
	localparam signed [31:0] AddrLsb = 2;
	always @(negedge clk)
		if (!rst)
			insn_from_imem <= mem_array[{pc_to_imem[AddrMsb:AddrLsb]}];
	always @(negedge clk)
		if (!rst) begin
			if (store_we_to_dmem[0])
				mem_array[addr_to_dmem[AddrMsb:AddrLsb]][7:0] <= store_data_to_dmem[7:0];
			if (store_we_to_dmem[1])
				mem_array[addr_to_dmem[AddrMsb:AddrLsb]][15:8] <= store_data_to_dmem[15:8];
			if (store_we_to_dmem[2])
				mem_array[addr_to_dmem[AddrMsb:AddrLsb]][23:16] <= store_data_to_dmem[23:16];
			if (store_we_to_dmem[3])
				mem_array[addr_to_dmem[AddrMsb:AddrLsb]][31:24] <= store_data_to_dmem[31:24];
			load_data_from_dmem <= mem_array[{addr_to_dmem[AddrMsb:AddrLsb]}];
		end
	initial _sv2v_0 = 0;
endmodule
module SystemDemo (
	external_clk_25MHz,
	btn,
	led,
	gp
);
	input wire external_clk_25MHz;
	input wire [6:0] btn;
	output wire [7:0] led;
	output wire [27:0] gp;
	localparam signed [31:0] MmapGpioStart = 32'hff001000;
	localparam signed [31:0] LastGpioIndex = 27;
	localparam signed [31:0] MmapGpioEnd = MmapGpioStart + LastGpioIndex;
	localparam signed [31:0] MmapLeds = 32'hff002000;
	localparam signed [31:0] MmapButtons = 32'hff003000;
	wire clk_proc;
	wire clk_locked;
	MyClockGen clock_gen(
		.input_clk_25MHz(external_clk_25MHz),
		.clk_proc(clk_proc),
		.locked(clk_locked)
	);
	wire [31:0] pc_to_imem;
	wire [31:0] insn_from_imem;
	wire [31:0] mem_data_addr;
	wire [31:0] mem_data_loaded_value;
	wire [31:0] mem_data_to_write;
	wire [3:0] mem_data_we;
	wire [31:0] trace_writeback_pc;
	wire [31:0] trace_writeback_insn;
	wire [31:0] trace_writeback_cycle_status;
	wire is_gpio_write = (mem_data_we != 0) && ((MmapGpioStart <= mem_data_addr) && (mem_data_addr <= MmapGpioEnd));
	wire is_led_write = (mem_data_we != 0) && (mem_data_addr == MmapLeds);
	wire is_button_read = mem_data_addr == MmapButtons;
	reg [7:0] led_reg;
	reg [27:0] gpio_reg;
	always @(posedge clk_proc)
		if (!clk_locked) begin
			led_reg <= 0;
			gpio_reg <= 0;
		end
		else if (is_gpio_write)
			gpio_reg[mem_data_addr - MmapGpioStart] <= mem_data_to_write[0];
		else if (is_led_write)
			led_reg <= mem_data_to_write[7:0];
	assign gp = gpio_reg;
	assign led = led_reg;
	MemorySingleCycle #(.NUM_WORDS(1024)) memory(
		.rst(!clk_locked),
		.clk(clk_proc),
		.pc_to_imem(pc_to_imem),
		.insn_from_imem(insn_from_imem),
		.addr_to_dmem(mem_data_addr),
		.load_data_from_dmem(mem_data_loaded_value),
		.store_data_to_dmem(mem_data_to_write),
		.store_we_to_dmem((is_gpio_write ? 4'd0 : mem_data_we))
	);
	DatapathPipelined datapath(
		.clk(clk_proc),
		.rst(!clk_locked),
		.pc_to_imem(pc_to_imem),
		.insn_from_imem(insn_from_imem),
		.addr_to_dmem(mem_data_addr),
		.store_data_to_dmem(mem_data_to_write),
		.store_we_to_dmem(mem_data_we),
		.load_data_from_dmem(mem_data_loaded_value),
		.halt(),
		.trace_writeback_pc(trace_writeback_pc),
		.trace_writeback_insn(trace_writeback_insn),
		.trace_writeback_cycle_status(trace_writeback_cycle_status)
	);
endmodule