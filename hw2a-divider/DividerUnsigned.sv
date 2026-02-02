/* Crystal Lu 13505884 */

`timescale 1ns / 1ns

// quotient = dividend / divisor

module DividerUnsigned (
    input  wire [31:0] i_dividend,
    input  wire [31:0] i_divisor,
    output wire [31:0] o_remainder,
    output wire [31:0] o_quotient
);

    // TODO: your code here
    wire [31:0] dividend [32:0]; // 33 wires, each 32 bits wide 
    wire [31:0] remainder [32:0]; 
    wire [31:0] quotient [32:0]; 

    assign dividend[0] = i_dividend; 
    assign remainder[0] = 32'b0; 
    assign quotient[0] = 32'b0; 

    genvar i; 
    generate 
        for (i = 0; i < 32; i++) begin : div_stage 
            DividerOneIter iter (
                .i_dividend(dividend[i]), 
                .i_divisor(i_divisor), 
                .i_remainder(remainder[i]), 
                .i_quotient(quotient[i]), 
                .o_dividend(dividend[i+1]), 
                .o_remainder(remainder[i+1]), 
                .o_quotient(quotient[i+1])
            ); 
        end 
    endgenerate 
    assign o_remainder = remainder[32];
    assign o_quotient = quotient[32];
endmodule


module DividerOneIter (
    input  wire [31:0] i_dividend,
    input  wire [31:0] i_divisor,
    input  wire [31:0] i_remainder,
    input  wire [31:0] i_quotient,
    output wire [31:0] o_dividend,
    output wire [31:0] o_remainder,
    output wire [31:0] o_quotient
);
  /*
    for (int i = 0; i < 32; i++) {
        remainder = (remainder << 1) | ((dividend >> 31) & 0x1);
        if (remainder < divisor) {
            quotient = (quotient << 1);
        } else {
            quotient = (quotient << 1) | 0x1;
            remainder = remainder - divisor;
        }
        dividend = dividend << 1;
    }
    */
    wire [31:0] new_remainder; 
    assign new_remainder = (i_remainder << 1) | ((i_dividend >> 31) & 32'b1); 
    wire can_subtract; 
    assign can_subtract = (new_remainder >= i_divisor); // feed this into mux 
    assign o_quotient = can_subtract ? ((i_quotient << 1) | 32'b1) : (i_quotient << 1); 
    assign o_remainder = can_subtract ? (new_remainder - i_divisor) : new_remainder;
    assign o_dividend = i_dividend << 1; 
endmodule
