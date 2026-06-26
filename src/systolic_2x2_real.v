`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/18/2026 12:24:34 AM
// Design Name: 
// Module Name: systolic_2x2_real
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


module systolic_2x2_real(
    input wire clk,
    input wire rst,
    input wire valid,

    input wire signed [7:0] a0_in,
    input wire signed [7:0] a1_in,
    input wire signed [7:0] b0_in,
    input wire signed [7:0] b1_in,

    output wire signed [31:0] c00,
    output wire signed [31:0] c01,
    output wire signed [31:0] c10,
    output wire signed [31:0] c11,
    output reg done
);

wire signed [7:0] a00_to_a01;
wire signed [7:0] a10_to_a11;
wire signed [7:0] b00_to_b10;
wire signed [7:0] b01_to_b11;

wire v00_to_v01;
wire v10_to_v11;
wire v00_to_v10;
wire v01_to_v11;

reg [3:0] cycle_count;

pe PE00 (
    .clk(clk), .rst(rst),
    .a_in(a0_in), .b_in(b0_in), .valid_in(valid),
    .a_out(a00_to_a01), .b_out(b00_to_b10),
    .acc_out(c00), .valid_out(v00_to_v01)
);

pe PE01 (
    .clk(clk), .rst(rst),
    .a_in(a00_to_a01), .b_in(b1_in), .valid_in(v00_to_v01),
    .a_out(), .b_out(b01_to_b11),
    .acc_out(c01), .valid_out(v01_to_v11)
);

pe PE10 (
    .clk(clk), .rst(rst),
    .a_in(a1_in), .b_in(b00_to_b10), .valid_in(v00_to_v01),
    .a_out(a10_to_a11), .b_out(),
    .acc_out(c10), .valid_out(v10_to_v11)
);

pe PE11 (
    .clk(clk), .rst(rst),
    .a_in(a10_to_a11), .b_in(b01_to_b11), .valid_in(v01_to_v11),
    .a_out(), .b_out(),
    .acc_out(c11), .valid_out()
);

always @(posedge clk) begin
    if (rst) begin
        cycle_count <= 0;
        done <= 0;
    end else begin
        if (valid) begin
            cycle_count <= cycle_count + 1;
            done <= 0;
        end else begin
            if (cycle_count >= 3)
                done <= 1;
            else
                done <= 0;
        end
    end
end

endmodule