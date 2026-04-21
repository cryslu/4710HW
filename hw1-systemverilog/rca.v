`default_nettype none
module halfadder (
	a,
	b,
	s,
	cout
);
	input wire a;
	input wire b;
	output wire s;
	output wire cout;
	assign s = a ^ b;
	assign cout = a & b;
endmodule
module fulladder1 (
	cin,
	a,
	b,
	s,
	cout
);
	input wire cin;
	input wire a;
	input wire b;
	output wire s;
	output wire cout;
	wire s_tmp;
	wire cout_tmp1;
	wire cout_tmp2;
	halfadder h0(
		.a(a),
		.b(b),
		.s(s_tmp),
		.cout(cout_tmp1)
	);
	halfadder h1(
		.a(s_tmp),
		.b(cin),
		.s(s),
		.cout(cout_tmp2)
	);
	assign cout = cout_tmp1 | cout_tmp2;
endmodule
module fulladder2 (
	cin,
	a,
	b,
	s,
	cout
);
	input wire cin;
	input wire [1:0] a;
	input wire [1:0] b;
	output wire [1:0] s;
	output wire cout;
	wire cout_tmp;
	fulladder1 fa0(
		.cin(cin),
		.a(a[0]),
		.b(b[0]),
		.s(s[0]),
		.cout(cout_tmp)
	);
	fulladder1 fa1(
		.cin(cout_tmp),
		.a(a[1]),
		.b(b[1]),
		.s(s[1]),
		.cout(cout)
	);
endmodule
module rca4 (
	a,
	b,
	sum,
	carry_out
);
	input wire [3:0] a;
	input wire [3:0] b;
	output wire [3:0] sum;
	output wire carry_out;
	wire cout0;
	fulladder2 adder0(
		.cin(1'b0),
		.a(a[1:0]),
		.b(b[1:0]),
		.s(sum[1:0]),
		.cout(cout0)
	);
	fulladder2 adder3(
		.cin(cout0),
		.a(a[3:2]),
		.b(b[3:2]),
		.s(sum[3:2]),
		.cout(carry_out)
	);
endmodule
module rca4_demo (
	BUTTON,
	LED
);
	input wire [6:0] BUTTON;
	output wire [7:0] LED;
	rca4 rca(
		.a(4'd2),
		.b({BUTTON[2], BUTTON[5], BUTTON[4], BUTTON[6]}),
		.sum(LED[3:0]),
		.carry_out(LED[4])
	);
	assign LED[7:5] = 3'd0;
endmodule