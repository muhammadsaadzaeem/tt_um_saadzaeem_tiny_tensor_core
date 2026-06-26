`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/17/2026 10:39:50 PM
// Design Name: 
// Module Name: pe
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module pe (
    input wire clk,
    input wire rst,
    input wire signed [7:0] a_in,
    input wire signed [7:0] b_in,
    input wire valid_in,

    output reg signed [7:0] a_out,
    output reg signed [7:0] b_out,
    output reg signed [31:0] acc_out,
    output reg valid_out
);

always @(posedge clk) begin
    if (rst) begin
        a_out <= 0;
        b_out <= 0;
        acc_out <= 0;
        valid_out <= 0;
    end else begin
        a_out <= a_in;
        b_out <= b_in;
        valid_out <= valid_in;

        if (valid_in)
            acc_out <= acc_out + (a_in * b_in);
    end
end

endmodule
