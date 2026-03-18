module MyClockGen (
	input_clk_25MHz,
	clk_proc,
	clk_mem,
	locked
);
	input input_clk_25MHz;
	output wire clk_proc;
	output wire clk_mem;
	output wire locked;
	wire clkfb;
	(* FREQUENCY_PIN_CLKI = "25" *) (* FREQUENCY_PIN_CLKOP = "10" *) (* FREQUENCY_PIN_CLKOS = "10" *) (* ICP_CURRENT = "12" *) (* LPF_RESISTOR = "8" *) (* MFG_ENABLE_FILTEROPAMP = "1" *) (* MFG_GMCREF_SEL = "2" *) EHXPLLL #(
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
		.CLKOP_DIV(60),
		.CLKOP_CPHASE(30),
		.CLKOP_FPHASE(0),
		.CLKOS_ENABLE("ENABLED"),
		.CLKOS_DIV(60),
		.CLKOS_CPHASE(45),
		.CLKOS_FPHASE(0),
		.FEEDBK_PATH("INT_OP"),
		.CLKFB_DIV(2)
	) pll_i(
		.RST(1'b0),
		.STDBY(1'b0),
		.CLKI(input_clk_25MHz),
		.CLKOP(clk_proc),
		.CLKOS(clk_mem),
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
	assign rs1_data = (rs1 == 5'd0 ? {32 {1'sb0}} : regs[rs1]);
	assign rs2_data = (rs2 == 5'd0 ? {32 {1'sb0}} : regs[rs2]);
	always @(posedge clk)
		if (rst) begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < NumRegs; i = i + 1)
				regs[i] <= 1'sb0;
		end
		else if (we && (rd != 5'd0))
			regs[rd] <= rd_data;
endmodule
module DatapathMultiCycle (
	clk,
	rst,
	halt,
	pc_to_imem,
	insn_from_imem,
	addr_to_dmem,
	load_data_from_dmem,
	store_data_to_dmem,
	store_we_to_dmem,
	trace_completed_pc,
	trace_completed_insn,
	trace_completed_cycle_status
);
	reg _sv2v_0;
	input wire clk;
	input wire rst;
	output reg halt;
	output wire [31:0] pc_to_imem;
	input wire [31:0] insn_from_imem;
	output reg [31:0] addr_to_dmem;
	input wire [31:0] load_data_from_dmem;
	output reg [31:0] store_data_to_dmem;
	output reg [3:0] store_we_to_dmem;
	output reg [31:0] trace_completed_pc;
	output reg [31:0] trace_completed_insn;
	output reg [31:0] trace_completed_cycle_status;
	wire [6:0] insn_funct7;
	wire [4:0] insn_rs2;
	wire [4:0] insn_rs1;
	wire [2:0] insn_funct3;
	wire [4:0] insn_rd;
	wire [6:0] insn_opcode;
	assign {insn_funct7, insn_rs2, insn_rs1, insn_funct3, insn_rd, insn_opcode} = insn_from_imem;
	wire [11:0] imm_i;
	assign imm_i = insn_from_imem[31:20];
	wire [4:0] imm_shamt = insn_from_imem[24:20];
	wire [11:0] imm_s;
	assign imm_s[11:5] = insn_funct7;
	assign imm_s[4:0] = insn_rd;
	wire [12:0] imm_b;
	assign {imm_b[12], imm_b[10:5]} = insn_funct7;
	assign {imm_b[4:1], imm_b[11]} = insn_rd;
	assign imm_b[0] = 1'b0;
	wire [20:0] imm_j;
	assign {imm_j[20], imm_j[10:1], imm_j[11], imm_j[19:12], imm_j[0]} = {insn_from_imem[31:12], 1'b0};
	wire [31:0] imm_i_sext = {{20 {imm_i[11]}}, imm_i[11:0]};
	wire [31:0] imm_s_sext = {{20 {imm_s[11]}}, imm_s[11:0]};
	wire [31:0] imm_b_sext = {{19 {imm_b[12]}}, imm_b[12:0]};
	wire [31:0] imm_j_sext = {{11 {imm_j[20]}}, imm_j[20:0]};
	localparam [6:0] OpLoad = 7'b0000011;
	localparam [6:0] OpStore = 7'b0100011;
	localparam [6:0] OpBranch = 7'b1100011;
	localparam [6:0] OpJalr = 7'b1100111;
	localparam [6:0] OpMiscMem = 7'b0001111;
	localparam [6:0] OpJal = 7'b1101111;
	localparam [6:0] OpRegImm = 7'b0010011;
	localparam [6:0] OpRegReg = 7'b0110011;
	localparam [6:0] OpEnviron = 7'b1110011;
	localparam [6:0] OpAuipc = 7'b0010111;
	localparam [6:0] OpLui = 7'b0110111;
	wire insn_lui = insn_opcode == OpLui;
	wire insn_auipc = insn_opcode == OpAuipc;
	wire insn_jal = insn_opcode == OpJal;
	wire insn_jalr = insn_opcode == OpJalr;
	wire insn_beq = (insn_opcode == OpBranch) && (insn_from_imem[14:12] == 3'b000);
	wire insn_bne = (insn_opcode == OpBranch) && (insn_from_imem[14:12] == 3'b001);
	wire insn_blt = (insn_opcode == OpBranch) && (insn_from_imem[14:12] == 3'b100);
	wire insn_bge = (insn_opcode == OpBranch) && (insn_from_imem[14:12] == 3'b101);
	wire insn_bltu = (insn_opcode == OpBranch) && (insn_from_imem[14:12] == 3'b110);
	wire insn_bgeu = (insn_opcode == OpBranch) && (insn_from_imem[14:12] == 3'b111);
	wire insn_lb = (insn_opcode == OpLoad) && (insn_from_imem[14:12] == 3'b000);
	wire insn_lh = (insn_opcode == OpLoad) && (insn_from_imem[14:12] == 3'b001);
	wire insn_lw = (insn_opcode == OpLoad) && (insn_from_imem[14:12] == 3'b010);
	wire insn_lbu = (insn_opcode == OpLoad) && (insn_from_imem[14:12] == 3'b100);
	wire insn_lhu = (insn_opcode == OpLoad) && (insn_from_imem[14:12] == 3'b101);
	wire insn_sb = (insn_opcode == OpStore) && (insn_from_imem[14:12] == 3'b000);
	wire insn_sh = (insn_opcode == OpStore) && (insn_from_imem[14:12] == 3'b001);
	wire insn_sw = (insn_opcode == OpStore) && (insn_from_imem[14:12] == 3'b010);
	wire insn_addi = (insn_opcode == OpRegImm) && (insn_from_imem[14:12] == 3'b000);
	wire insn_slti = (insn_opcode == OpRegImm) && (insn_from_imem[14:12] == 3'b010);
	wire insn_sltiu = (insn_opcode == OpRegImm) && (insn_from_imem[14:12] == 3'b011);
	wire insn_xori = (insn_opcode == OpRegImm) && (insn_from_imem[14:12] == 3'b100);
	wire insn_ori = (insn_opcode == OpRegImm) && (insn_from_imem[14:12] == 3'b110);
	wire insn_andi = (insn_opcode == OpRegImm) && (insn_from_imem[14:12] == 3'b111);
	wire insn_slli = ((insn_opcode == OpRegImm) && (insn_from_imem[14:12] == 3'b001)) && (insn_from_imem[31:25] == 7'd0);
	wire insn_srli = ((insn_opcode == OpRegImm) && (insn_from_imem[14:12] == 3'b101)) && (insn_from_imem[31:25] == 7'd0);
	wire insn_srai = ((insn_opcode == OpRegImm) && (insn_from_imem[14:12] == 3'b101)) && (insn_from_imem[31:25] == 7'b0100000);
	wire insn_add = ((insn_opcode == OpRegReg) && (insn_from_imem[14:12] == 3'b000)) && (insn_from_imem[31:25] == 7'd0);
	wire insn_sub = ((insn_opcode == OpRegReg) && (insn_from_imem[14:12] == 3'b000)) && (insn_from_imem[31:25] == 7'b0100000);
	wire insn_sll = ((insn_opcode == OpRegReg) && (insn_from_imem[14:12] == 3'b001)) && (insn_from_imem[31:25] == 7'd0);
	wire insn_slt = ((insn_opcode == OpRegReg) && (insn_from_imem[14:12] == 3'b010)) && (insn_from_imem[31:25] == 7'd0);
	wire insn_sltu = ((insn_opcode == OpRegReg) && (insn_from_imem[14:12] == 3'b011)) && (insn_from_imem[31:25] == 7'd0);
	wire insn_xor = ((insn_opcode == OpRegReg) && (insn_from_imem[14:12] == 3'b100)) && (insn_from_imem[31:25] == 7'd0);
	wire insn_srl = ((insn_opcode == OpRegReg) && (insn_from_imem[14:12] == 3'b101)) && (insn_from_imem[31:25] == 7'd0);
	wire insn_sra = ((insn_opcode == OpRegReg) && (insn_from_imem[14:12] == 3'b101)) && (insn_from_imem[31:25] == 7'b0100000);
	wire insn_or = ((insn_opcode == OpRegReg) && (insn_from_imem[14:12] == 3'b110)) && (insn_from_imem[31:25] == 7'd0);
	wire insn_and = ((insn_opcode == OpRegReg) && (insn_from_imem[14:12] == 3'b111)) && (insn_from_imem[31:25] == 7'd0);
	wire insn_mul = ((insn_opcode == OpRegReg) && (insn_from_imem[31:25] == 7'd1)) && (insn_from_imem[14:12] == 3'b000);
	wire insn_mulh = ((insn_opcode == OpRegReg) && (insn_from_imem[31:25] == 7'd1)) && (insn_from_imem[14:12] == 3'b001);
	wire insn_mulhsu = ((insn_opcode == OpRegReg) && (insn_from_imem[31:25] == 7'd1)) && (insn_from_imem[14:12] == 3'b010);
	wire insn_mulhu = ((insn_opcode == OpRegReg) && (insn_from_imem[31:25] == 7'd1)) && (insn_from_imem[14:12] == 3'b011);
	wire insn_div = ((insn_opcode == OpRegReg) && (insn_from_imem[31:25] == 7'd1)) && (insn_from_imem[14:12] == 3'b100);
	wire insn_divu = ((insn_opcode == OpRegReg) && (insn_from_imem[31:25] == 7'd1)) && (insn_from_imem[14:12] == 3'b101);
	wire insn_rem = ((insn_opcode == OpRegReg) && (insn_from_imem[31:25] == 7'd1)) && (insn_from_imem[14:12] == 3'b110);
	wire insn_remu = ((insn_opcode == OpRegReg) && (insn_from_imem[31:25] == 7'd1)) && (insn_from_imem[14:12] == 3'b111);
	wire insn_ecall = (insn_opcode == OpEnviron) && (insn_from_imem[31:7] == 25'd0);
	wire insn_fence = insn_opcode == OpMiscMem;
	reg [31:0] pcNext;
	reg [31:0] pcCurrent;
	reg [2:0] div_cycle_count;
	wire is_divide = ((insn_opcode == OpRegReg) && (insn_funct7 == 7'd1)) && (insn_funct3[2] == 1'b1);
	wire div_stall = is_divide && (div_cycle_count != 3'd7);
	always @(posedge clk)
		if (rst)
			pcCurrent <= 32'd0;
		else if (!div_stall)
			pcCurrent <= pcNext;
	assign pc_to_imem = pcCurrent;
	reg [31:0] cycles_current;
	reg [31:0] num_insns_current;
	always @(posedge clk)
		if (rst) begin
			cycles_current <= 0;
			num_insns_current <= 0;
		end
		else begin
			cycles_current <= cycles_current + 1;
			if (!div_stall)
				num_insns_current <= num_insns_current + 1;
		end
	always @(posedge clk)
		if (rst)
			div_cycle_count <= 3'd0;
		else if (is_divide) begin
			if (div_cycle_count == 3'd7)
				div_cycle_count <= 3'd0;
			else
				div_cycle_count <= div_cycle_count + 3'd1;
		end
		else
			div_cycle_count <= 3'd0;
	reg prev_is_divide;
	always @(posedge clk)
		if (rst)
			prev_is_divide <= 1'b0;
		else
			prev_is_divide <= is_divide;
	reg [31:0] stall_pc;
	always @(posedge clk)
		if (rst)
			stall_pc <= 32'd0;
		else if (is_divide && !prev_is_divide)
			stall_pc <= pcCurrent;
	wire [31:0] rs1_data;
	wire [31:0] rs2_data;
	reg [31:0] rd_data;
	reg we;
	wire rf_we;
	assign rf_we = we && !div_stall;
	RegFile rf(
		.clk(clk),
		.rst(rst),
		.we(rf_we),
		.rd(insn_rd),
		.rd_data(rd_data),
		.rs1(insn_rs1),
		.rs1_data(rs1_data),
		.rs2(insn_rs2),
		.rs2_data(rs2_data)
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
	reg [31:0] div_dividend;
	reg [31:0] div_divisor;
	wire [31:0] div_quotient;
	wire [31:0] div_remainder;
	DividerUnsignedPipelined divider_inst(
		.clk(clk),
		.rst(rst),
		.stall(1'b0),
		.i_dividend(div_dividend),
		.i_divisor(div_divisor),
		.o_quotient(div_quotient),
		.o_remainder(div_remainder)
	);
	reg [31:0] load_addr;
	reg [31:0] store_addr;
	reg illegal_insn;
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
		illegal_insn = 1'b0;
		halt = 1'b0;
		pcNext = pcCurrent + 32'd4;
		rd_data = 32'd0;
		we = 1'b0;
		cla_a = 32'd0;
		cla_b = 32'd0;
		cla_cin = 1'b0;
		div_dividend = 32'd0;
		div_divisor = 32'd1;
		load_addr = 32'd0;
		store_addr = 32'd0;
		addr_to_dmem = 32'd0;
		store_data_to_dmem = 32'd0;
		store_we_to_dmem = 4'b0000;
		trace_completed_pc = (is_divide ? stall_pc : pcCurrent);
		trace_completed_insn = insn_from_imem;
		trace_completed_cycle_status = (is_divide ? 32'd2 : 32'd1);
		case (insn_opcode)
			OpLui: begin
				rd_data = {insn_from_imem[31:12], 12'b000000000000};
				we = 1'b1;
			end
			OpAuipc: begin
				rd_data = pcCurrent + {insn_from_imem[31:12], 12'b000000000000};
				we = 1'b1;
			end
			OpRegImm: begin
				we = 1'b1;
				case (insn_funct3)
					3'b000: begin
						cla_a = rs1_data;
						cla_b = imm_i_sext;
						cla_cin = 1'b0;
						rd_data = cla_sum;
					end
					3'b010: rd_data = ($signed(rs1_data) < $signed(imm_i_sext) ? 32'd1 : 32'd0);
					3'b011: rd_data = (rs1_data < imm_i_sext ? 32'd1 : 32'd0);
					3'b100: rd_data = rs1_data ^ imm_i_sext;
					3'b110: rd_data = rs1_data | imm_i_sext;
					3'b111: rd_data = rs1_data & imm_i_sext;
					3'b001: rd_data = rs1_data << imm_shamt;
					3'b101:
						if (insn_funct7 == 7'b0000000)
							rd_data = rs1_data >> imm_shamt;
						else
							rd_data = $signed(rs1_data) >>> imm_shamt;
					default: illegal_insn = 1'b1;
				endcase
			end
			OpRegReg: begin
				we = 1'b1;
				case (insn_funct3)
					3'b000:
						if (insn_funct7 == 7'd1)
							rd_data = rs1_data * rs2_data;
						else if (insn_funct7 == 7'd0) begin
							cla_a = rs1_data;
							cla_b = rs2_data;
							cla_cin = 1'b0;
							rd_data = cla_sum;
						end
						else begin
							cla_a = rs1_data;
							cla_b = ~rs2_data;
							cla_cin = 1'b1;
							rd_data = cla_sum;
						end
					3'b001:
						if (insn_funct7 == 7'd1)
							rd_data = sv2v_cast_32_signed($signed($signed({{32 {rs1_data[31]}}, rs1_data}) * $signed({{32 {rs2_data[31]}}, rs2_data})) >>> 32);
						else
							rd_data = rs1_data << rs2_data[4:0];
					3'b010:
						if (insn_funct7 == 7'd1)
							rd_data = sv2v_cast_32_signed($signed($signed({{32 {rs1_data[31]}}, rs1_data}) * {32'd0, rs2_data}) >>> 32);
						else
							rd_data = ($signed(rs1_data) < $signed(rs2_data) ? 32'd1 : 32'd0);
					3'b011:
						if (insn_funct7 == 7'd1)
							rd_data = sv2v_cast_32(({32'd0, rs1_data} * {32'd0, rs2_data}) >> 32);
						else
							rd_data = (rs1_data < rs2_data ? 32'd1 : 32'd0);
					3'b100:
						if (insn_funct7 == 7'd1) begin
							if (rs2_data == 32'd0)
								rd_data = 32'hffffffff;
							else if ((rs1_data == 32'h80000000) && (rs2_data == 32'hffffffff))
								rd_data = 32'h80000000;
							else begin
								div_dividend = (rs1_data[31] ? ~rs1_data + 32'd1 : rs1_data);
								div_divisor = (rs2_data[31] ? ~rs2_data + 32'd1 : rs2_data);
								rd_data = (rs1_data[31] ^ rs2_data[31] ? ~div_quotient + 32'd1 : div_quotient);
							end
						end
						else
							rd_data = rs1_data ^ rs2_data;
					3'b101:
						if (insn_funct7 == 7'd1) begin
							if (rs2_data == 32'd0)
								rd_data = 32'hffffffff;
							else begin
								div_dividend = rs1_data;
								div_divisor = rs2_data;
								rd_data = div_quotient;
							end
						end
						else if (insn_funct7 == 7'b0000000)
							rd_data = rs1_data >> rs2_data[4:0];
						else
							rd_data = $signed(rs1_data) >>> rs2_data[4:0];
					3'b110:
						if (insn_funct7 == 7'd1) begin
							if (rs2_data == 32'd0)
								rd_data = rs1_data;
							else if ((rs1_data == 32'h80000000) && (rs2_data == 32'hffffffff))
								rd_data = 32'd0;
							else begin
								div_dividend = (rs1_data[31] ? ~rs1_data + 32'd1 : rs1_data);
								div_divisor = (rs2_data[31] ? ~rs2_data + 32'd1 : rs2_data);
								rd_data = (rs1_data[31] ? ~div_remainder + 32'd1 : div_remainder);
							end
						end
						else
							rd_data = rs1_data | rs2_data;
					3'b111:
						if (insn_funct7 == 7'd1) begin
							if (rs2_data == 32'd0)
								rd_data = rs1_data;
							else begin
								div_dividend = rs1_data;
								div_divisor = rs2_data;
								rd_data = div_remainder;
							end
						end
						else
							rd_data = rs1_data & rs2_data;
					default: illegal_insn = 1'b1;
				endcase
			end
			OpBranch:
				case (insn_funct3)
					3'b000:
						if (rs1_data == rs2_data)
							pcNext = pcCurrent + imm_b_sext;
					3'b001:
						if (rs1_data != rs2_data)
							pcNext = pcCurrent + imm_b_sext;
					3'b100:
						if ($signed(rs1_data) < $signed(rs2_data))
							pcNext = pcCurrent + imm_b_sext;
					3'b101:
						if ($signed(rs1_data) >= $signed(rs2_data))
							pcNext = pcCurrent + imm_b_sext;
					3'b110:
						if (rs1_data < rs2_data)
							pcNext = pcCurrent + imm_b_sext;
					3'b111:
						if (rs1_data >= rs2_data)
							pcNext = pcCurrent + imm_b_sext;
					default: illegal_insn = 1'b1;
				endcase
			OpJal: begin
				rd_data = pcCurrent + 32'd4;
				we = 1'b1;
				pcNext = pcCurrent + imm_j_sext;
			end
			OpJalr: begin
				rd_data = pcCurrent + 32'd4;
				we = 1'b1;
				pcNext = (rs1_data + imm_i_sext) & ~32'd1;
			end
			OpLoad: begin
				we = 1'b1;
				load_addr = rs1_data + imm_i_sext;
				addr_to_dmem = {load_addr[31:2], 2'b00};
				case (insn_funct3)
					3'b000:
						case (load_addr[1:0])
							2'b00: rd_data = {{24 {load_data_from_dmem[7]}}, load_data_from_dmem[7:0]};
							2'b01: rd_data = {{24 {load_data_from_dmem[15]}}, load_data_from_dmem[15:8]};
							2'b10: rd_data = {{24 {load_data_from_dmem[23]}}, load_data_from_dmem[23:16]};
							2'b11: rd_data = {{24 {load_data_from_dmem[31]}}, load_data_from_dmem[31:24]};
							default: rd_data = 32'd0;
						endcase
					3'b001:
						case (load_addr[1])
							1'b0: rd_data = {{16 {load_data_from_dmem[15]}}, load_data_from_dmem[15:0]};
							1'b1: rd_data = {{16 {load_data_from_dmem[31]}}, load_data_from_dmem[31:16]};
							default: rd_data = 32'd0;
						endcase
					3'b010: rd_data = load_data_from_dmem;
					3'b100:
						case (load_addr[1:0])
							2'b00: rd_data = {24'd0, load_data_from_dmem[7:0]};
							2'b01: rd_data = {24'd0, load_data_from_dmem[15:8]};
							2'b10: rd_data = {24'd0, load_data_from_dmem[23:16]};
							2'b11: rd_data = {24'd0, load_data_from_dmem[31:24]};
							default: rd_data = 32'd0;
						endcase
					3'b101:
						case (load_addr[1])
							1'b0: rd_data = {16'd0, load_data_from_dmem[15:0]};
							1'b1: rd_data = {16'd0, load_data_from_dmem[31:16]};
							default: rd_data = 32'd0;
						endcase
					default: illegal_insn = 1'b1;
				endcase
			end
			OpStore: begin
				store_addr = rs1_data + imm_s_sext;
				addr_to_dmem = {store_addr[31:2], 2'b00};
				case (insn_funct3)
					3'b000:
						case (store_addr[1:0])
							2'b00: begin
								store_data_to_dmem = {24'd0, rs2_data[7:0]};
								store_we_to_dmem = 4'b0001;
							end
							2'b01: begin
								store_data_to_dmem = {16'd0, rs2_data[7:0], 8'd0};
								store_we_to_dmem = 4'b0010;
							end
							2'b10: begin
								store_data_to_dmem = {8'd0, rs2_data[7:0], 16'd0};
								store_we_to_dmem = 4'b0100;
							end
							2'b11: begin
								store_data_to_dmem = {rs2_data[7:0], 24'd0};
								store_we_to_dmem = 4'b1000;
							end
							default: store_we_to_dmem = 4'b0000;
						endcase
					3'b001:
						case (store_addr[1])
							1'b0: begin
								store_data_to_dmem = {16'd0, rs2_data[15:0]};
								store_we_to_dmem = 4'b0011;
							end
							1'b1: begin
								store_data_to_dmem = {rs2_data[15:0], 16'd0};
								store_we_to_dmem = 4'b1100;
							end
							default: store_we_to_dmem = 4'b0000;
						endcase
					3'b010: begin
						store_data_to_dmem = rs2_data;
						store_we_to_dmem = 4'b1111;
					end
					default: illegal_insn = 1'b1;
				endcase
			end
			OpEnviron:
				if (insn_ecall)
					halt = 1'b1;
			OpMiscMem:
				;
			default: illegal_insn = 1'b1;
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module MemorySingleCycle (
	rst,
	clock_mem,
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
	input wire clock_mem;
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
	always @(posedge clock_mem)
		if (rst)
			;
		else
			insn_from_imem <= mem_array[{pc_to_imem[AddrMsb:AddrLsb]}];
	always @(negedge clock_mem)
		if (rst)
			;
		else begin
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
module SystemResourceCheck (
	external_clk_25MHz,
	btn,
	led
);
	input wire external_clk_25MHz;
	input wire [6:0] btn;
	output wire [7:0] led;
	wire clk_proc;
	wire clk_mem;
	wire clk_locked;
	MyClockGen clock_gen(
		.input_clk_25MHz(external_clk_25MHz),
		.clk_proc(clk_proc),
		.clk_mem(clk_mem),
		.locked(clk_locked)
	);
	wire [31:0] pc_to_imem;
	wire [31:0] insn_from_imem;
	wire [31:0] mem_data_addr;
	wire [31:0] mem_data_loaded_value;
	wire [31:0] mem_data_to_write;
	wire [3:0] mem_data_we;
	MemorySingleCycle #(.NUM_WORDS(128)) memory(
		.rst(!clk_locked),
		.clock_mem(clk_mem),
		.pc_to_imem(pc_to_imem),
		.insn_from_imem(insn_from_imem),
		.addr_to_dmem(mem_data_addr),
		.load_data_from_dmem(mem_data_loaded_value),
		.store_data_to_dmem(mem_data_to_write),
		.store_we_to_dmem(mem_data_we)
	);
	DatapathMultiCycle datapath(
		.clk(clk_proc),
		.rst(!clk_locked),
		.pc_to_imem(pc_to_imem),
		.insn_from_imem(insn_from_imem),
		.addr_to_dmem(mem_data_addr),
		.store_data_to_dmem(mem_data_to_write),
		.store_we_to_dmem(mem_data_we),
		.load_data_from_dmem(mem_data_loaded_value),
		.halt(led[0])
	);
endmodule