/* INSERT NAME AND PENNKEY HERE */
`timescale 1ns / 1ns

module DividerUnsignedPipelined (
    input  wire clk,
    input  wire rst,
    input  wire stall,
    input  wire [31:0] i_dividend,
    input  wire [31:0] i_divisor,
    output wire [31:0] o_remainder,
    output wire [31:0] o_quotient
);

    // 7 inter-stage registers (between stages 0-1, 1-2, ... 6-7)
    logic [31:0] dividend  [0:7];
    logic [31:0] remainder [0:7];
    logic [31:0] quotient  [0:7];
    logic [31:0] divisor   [0:7];

    // Stage 0 input wires (combinational from module ports)
    wire [31:0] d_in_0   = i_dividend;
    wire [31:0] r_in_0   = 32'b0;
    wire [31:0] q_in_0   = 32'b0;
    wire [31:0] div_in_0 = i_divisor;

    // Stage 0 output wires
    wire [31:0] d_out_0, r_out_0, q_out_0;

    divu_4iter stage0 (
        .i_dividend (d_in_0),   .i_divisor  (div_in_0),
        .i_remainder(r_in_0),   .i_quotient (q_in_0),
        .o_dividend (d_out_0),  .o_remainder(r_out_0),  .o_quotient(q_out_0)
    );

    // Register stage 0 output into index [0]
    always_ff @(posedge clk) begin
        if (rst) begin
            dividend[0] <= 0; remainder[0] <= 0;
            quotient[0] <= 0; divisor[0]   <= 0;
        end else begin
            dividend[0] <= d_out_0; remainder[0] <= r_out_0;
            quotient[0] <= q_out_0; divisor[0]   <= div_in_0;
        end
    end

    // Stages 1-6: registered outputs feed next stage
    genvar s;
    generate
        for (s = 1; s < 7; s++) begin : stage
            wire [31:0] d_next, r_next, q_next;
            divu_4iter stage_logic (
                .i_dividend (dividend[s-1]),  .i_divisor  (divisor[s-1]),
                .i_remainder(remainder[s-1]), .i_quotient (quotient[s-1]),
                .o_dividend (d_next),         .o_remainder(r_next), .o_quotient(q_next)
            );
            always_ff @(posedge clk) begin
                if (rst) begin
                    dividend[s] <= 0; remainder[s] <= 0;
                    quotient[s] <= 0; divisor[s]   <= 0;
                end else begin
                    dividend[s] <= d_next; remainder[s] <= r_next;
                    quotient[s] <= q_next; divisor[s]   <= divisor[s-1];
                end
            end
        end
    endgenerate

    // Stage 7: combinational output (no output FF — result readable same cycle as last clock)
    wire [31:0] unused_dividend;
    divu_4iter stage_7 (
        .i_dividend(dividend[6]),         .i_divisor(divisor[6]),
        .i_remainder(remainder[6]),       .i_quotient(quotient[6]),
        .o_dividend(unused_dividend),     .o_remainder(o_remainder), .o_quotient(o_quotient)
    );

endmodule


module divu_4iter (
    input  wire [31:0] i_dividend,
    input  wire [31:0] i_divisor,
    input  wire [31:0] i_remainder,
    input  wire [31:0] i_quotient,

    output wire [31:0] o_dividend,
    output wire [31:0] o_remainder,
    output wire [31:0] o_quotient
);

    wire [31:0] d [0:4];
    wire [31:0] r [0:4];
    wire [31:0] q [0:4];

    assign d[0] = i_dividend;
    assign r[0] = i_remainder;
    assign q[0] = i_quotient;

    genvar i;

    generate
        for (i = 0; i < 4; i++) begin : iter

            divu_1iter u (
                .i_dividend (d[i]),
                .i_divisor  (i_divisor),
                .i_remainder(r[i]),
                .i_quotient (q[i]),
                .o_dividend (d[i+1]),
                .o_remainder(r[i+1]),
                .o_quotient (q[i+1])
            );

        end
    endgenerate

    assign o_dividend  = d[4];
    assign o_remainder = r[4];
    assign o_quotient  = q[4];

endmodule



module divu_1iter (
    input  wire [31:0] i_dividend,
    input  wire [31:0] i_divisor,
    input  wire [31:0] i_remainder,
    input  wire [31:0] i_quotient,

    output wire [31:0] o_dividend,
    output wire [31:0] o_remainder,
    output wire [31:0] o_quotient
);

    wire [31:0] new_remainder; 
    assign new_remainder = (i_remainder << 1) | ((i_dividend >> 31) & 32'b1); 
    wire can_subtract; 
    assign can_subtract = (new_remainder >= i_divisor); 
    assign o_quotient = can_subtract ? ((i_quotient << 1) | 32'b1) : (i_quotient << 1); 
    assign o_remainder = can_subtract ? (new_remainder - i_divisor) : new_remainder;
    assign o_dividend = i_dividend << 1; 
endmodule
