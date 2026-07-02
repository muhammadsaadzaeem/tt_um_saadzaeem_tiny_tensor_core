`default_nettype none

module tt_um_saadzaeem_tiny_tensor_core (
    input  wire [7:0] ui_in,
    output reg  [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

assign uio_oe  = 8'hFE;
assign uio_out = {3'b000, done, state};

wire strobe = uio_in[0];
wire unused = &{ena, uio_in[7:1]};

localparam CMD_WRITE_REG = 8'hE0;
localparam CMD_READ_REG  = 8'hE1;

localparam S_IDLE       = 4'd0;
localparam S_WR_ADDR    = 4'd1;
localparam S_WR_DATA    = 4'd2;
localparam S_RD_ADDR    = 4'd3;
localparam S_RESET      = 4'd4;
localparam S_RUN0       = 4'd5;
localparam S_RUN1       = 4'd6;
localparam S_RUN2       = 4'd7;
localparam S_WAIT       = 4'd8;
localparam S_DONE       = 4'd9;

reg [3:0] state;
reg [7:0] reg_addr;

reg [3:0] shift_amount;
reg [15:0] cycle_counter;
reg [15:0] last_cycles;

reg signed [7:0] a00, a01, a10, a11;
reg signed [7:0] b00, b01, b10, b11;

reg valid;
reg accel_rst;

reg signed [7:0] a0_in, a1_in, b0_in, b1_in;

wire signed [31:0] c00, c01, c10, c11;
wire done;

function [7:0] relu_quant8;
    input signed [31:0] x;
    input [3:0] shamt;
    reg signed [31:0] y;
    begin
        if (x < 0)
            y = 32'sd0;
        else
            y = x >>> shamt;

        if (y > 32'sd127)
            relu_quant8 = 8'd127;
        else
            relu_quant8 = y[7:0];
    end
endfunction

wire [7:0] q00 = relu_quant8(c00, shift_amount);
wire [7:0] q01 = relu_quant8(c01, shift_amount);
wire [7:0] q10 = relu_quant8(c10, shift_amount);
wire [7:0] q11 = relu_quant8(c11, shift_amount);

systolic_2x2_real accel (
    .clk(clk),
    .rst(accel_rst),
    .valid(valid),
    .a0_in(a0_in),
    .a1_in(a1_in),
    .b0_in(b0_in),
    .b1_in(b1_in),
    .c00(c00),
    .c01(c01),
    .c10(c10),
    .c11(c11),
    .done(done)
);

always @(posedge clk) begin
    if (!rst_n) begin
        state <= S_IDLE;
        reg_addr <= 0;
        shift_amount <= 0;
        cycle_counter <= 0;
        last_cycles <= 0;
        uo_out <= 0;

        a00 <= 0; a01 <= 0; a10 <= 0; a11 <= 0;
        b00 <= 0; b01 <= 0; b10 <= 0; b11 <= 0;

        valid <= 0;
        accel_rst <= 1;

        a0_in <= 0; a1_in <= 0;
        b0_in <= 0; b1_in <= 0;
    end else begin
        valid <= 0;
        accel_rst <= 0;

        case (state)

            S_IDLE: begin
                if (strobe && ui_in == CMD_WRITE_REG)
                    state <= S_WR_ADDR;
                else if (strobe && ui_in == CMD_READ_REG)
                    state <= S_RD_ADDR;
            end

            S_WR_ADDR: begin
                if (strobe) begin
                    reg_addr <= ui_in;
                    state <= S_WR_DATA;
                end
            end

            S_WR_DATA: begin
                if (strobe) begin
                    case (reg_addr)
                        8'h00: a00 <= ui_in;
                        8'h01: a01 <= ui_in;
                        8'h02: a10 <= ui_in;
                        8'h03: a11 <= ui_in;
                        8'h04: b00 <= ui_in;
                        8'h05: b01 <= ui_in;
                        8'h06: b10 <= ui_in;
                        8'h07: b11 <= ui_in;
                        8'h08: shift_amount <= ui_in[3:0];

                        8'h09: begin
                            if (ui_in[0]) begin
                                accel_rst <= 1;
                                cycle_counter <= 0;
                                last_cycles <= 0;
                                state <= S_RESET;
                            end else begin
                                state <= S_IDLE;
                            end
                        end

                        default: ;
                    endcase

                    if (reg_addr != 8'h09)
                        state <= S_IDLE;
                end
            end

            S_RD_ADDR: begin
                if (strobe) begin
                    case (ui_in)
                        8'h08: uo_out <= {4'b0000, shift_amount};
                        8'h0A: uo_out <= {7'b0000000, done};

                        8'h10: uo_out <= q00;
                        8'h11: uo_out <= q01;
                        8'h12: uo_out <= q10;
                        8'h13: uo_out <= q11;

                        8'h14: uo_out <= last_cycles[7:0];
                        8'h15: uo_out <= last_cycles[15:8];

                        default: uo_out <= 8'h00;
                    endcase
                    state <= S_IDLE;
                end
            end

            S_RESET: begin
                accel_rst <= 0;
                cycle_counter <= cycle_counter + 1;
                state <= S_RUN0;
            end

            S_RUN0: begin
                valid <= 1;
                cycle_counter <= cycle_counter + 1;
                a0_in <= a00;
                a1_in <= 8'sd0;
                b0_in <= b00;
                b1_in <= 8'sd0;
                state <= S_RUN1;
            end

            S_RUN1: begin
                valid <= 1;
                cycle_counter <= cycle_counter + 1;
                a0_in <= a01;
                a1_in <= a10;
                b0_in <= b10;
                b1_in <= b01;
                state <= S_RUN2;
            end

            S_RUN2: begin
                valid <= 1;
                cycle_counter <= cycle_counter + 1;
                a0_in <= 8'sd0;
                a1_in <= a11;
                b0_in <= 8'sd0;
                b1_in <= b11;
                state <= S_WAIT;
            end

            S_WAIT: begin
                valid <= 0;
                a0_in <= 0; a1_in <= 0;
                b0_in <= 0; b1_in <= 0;

                if (done) begin
                    last_cycles <= cycle_counter;
                    state <= S_DONE;
                end else begin
                    cycle_counter <= cycle_counter + 1;
                end
            end

            S_DONE: begin
                if (strobe && ui_in == CMD_WRITE_REG)
                    state <= S_WR_ADDR;
                else if (strobe && ui_in == CMD_READ_REG)
                    state <= S_RD_ADDR;
            end

            default: state <= S_IDLE;

        endcase
    end
end

endmodule

`default_nettype wire