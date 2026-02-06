`timescale 1ns / 1ps

/**
 * @param a first 1-bit input
 * @param b second 1-bit input
 * @param g whether a and b generate a carry
 * @param p whether a and b would propagate an incoming carry
 */
module gp1(input wire a, b,
           output wire g, p);
   assign g = a & b;
   assign p = a | b;
endmodule

/**
 * Computes aggregate generate/propagate signals over a 4-bit window.
 * @param gin incoming generate signals
 * @param pin incoming propagate signals
 * @param cin the incoming carry
 * @param gout whether these 4 bits internally would generate a carry-out (independent of cin)
 * @param pout whether these 4 bits internally would propagate an incoming carry from cin
 * @param cout the carry outs for the low-order 3 bits
 */
module gp4(input wire [3:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire [2:0] cout);

   // TODO: your code here
   assign pout = pin[0] & pin[1] & pin[2] & pin[3]; 
   // create intermediate wires: 
   wire g1; 
   wire g2; 
   wire g3; 
   // assign values to intermediate wires: 
   assign g1 = pin[1] & pin[2] & pin[3] & gin[0]; 
   assign g2 = pin[2] & pin[3] & gin[1]; 
   assign g3 = pin[3] & gin[2]; 
   // find gout: 
   assign gout = g1 | g2 | g3 | gin[3]; 
   assign cout[0] = gin[0] | (pin[0] & cin);  
   
   assign cout[1] = gin[1] | 
                    (pin[1] & gin[0]) | 
                    (pin[1] & pin[0] & cin);  
   
   assign cout[2] = gin[2] | 
                    (pin[2] & gin[1]) | 
                    (pin[2] & pin[1] & gin[0]) | 
                    (pin[2] & pin[1] & pin[0] & cin); 
endmodule

/** Same as gp4 but for an 8-bit window instead */
module gp8(input wire [7:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire [6:0] cout);
   // TODO: your code here
   // intermediate wires: 
   wire g0, p0; // generate and propagate for block 0 
   wire g1, p1; // generate and propagate for block 1 
   wire c4; // for carry between blocks
   // create gp4 blocks: 
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

module CarryLookaheadAdder
  (input wire [31:0]  a, b,
   input wire         cin,
   output wire [31:0] sum);
   // TODO: your code here
   wire [31:0] g, p; 
   assign g = a & b; 
   assign p = a ^ b; 

   wire g0, p0, g1, p1, g2, p2, g3, p3; 
   wire [6:0] carries0, carries1, carries2, carries3; 
   wire c8, c16, c24;

   gp8 block0 (.gin(g[7:0]),   .pin(p[7:0]),   .cin(cin), .gout(g0), .pout(p0), .cout(carries0));
   gp8 block1 (.gin(g[15:8]),  .pin(p[15:8]),  .cin(c8),  .gout(g1), .pout(p1), .cout(carries1));
   gp8 block2 (.gin(g[23:16]), .pin(p[23:16]), .cin(c16), .gout(g2), .pout(p2), .cout(carries2));
   gp8 block3 (.gin(g[31:24]), .pin(p[31:24]), .cin(c24), .gout(g3), .pout(p3), .cout(carries3));
   
   assign c8  = g0 | (p0 & cin);
   assign c16 = g1 | (p1 & g0) | (p1 & p0 & cin);
   assign c24 = g2 | (p2 & g1) | (p2 & p1 & g0) | (p2 & p1 & p0 & cin);
   
   assign sum[0] = p[0] ^ cin;
   assign sum[7:1] = p[7:1] ^ carries0;
   assign sum[8] = p[8] ^ c8;
   assign sum[15:9] = p[15:9] ^ carries1;
   assign sum[16] = p[16] ^ c16;
   assign sum[23:17] = p[23:17] ^ carries2;
   assign sum[24] = p[24] ^ c24;
   assign sum[31:25] = p[31:25] ^ carries3;
endmodule
