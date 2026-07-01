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

localparam CMD_LOAD    = 8'hA0;
localparam CMD_COMPUTE = 8'hB0;
localparam CMD_READ    = 8'hC0;
localparam CMD_SHIFT   = 8'hD0;

localparam S_IDLE  = 4'd0;
localparam S_LOAD  = 4'd1;
localparam S_RESET = 4'd2;
localparam S_RUN0  = 4'd3;
localparam S_RUN1  = 4'd4;
localparam S_RUN2  = 4'd5;
localparam S_WAIT  = 4'd6;
localparam S_DONE  = 4'd7;
localparam S_SHIFT = 4'd8;

reg [3:0] state;
reg [3:0] load_idx;
reg [3:0] read_idx;

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
        load_idx <= 0;
        read_idx <= 0;
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
                if (strobe && ui_in == CMD_LOAD) begin
                    load_idx <= 0;
                    read_idx <= 0;
                    state <= S_LOAD;
                end else if (strobe && ui_in == CMD_COMPUTE) begin
                    accel_rst <= 1;
                    cycle_counter <= 0;
                    last_cycles <= 0;
                    state <= S_RESET;
                end else if (strobe && ui_in == CMD_SHIFT) begin
                    state <= S_SHIFT;
                end
            end

            S_SHIFT: begin
                if (strobe) begin
                    shift_amount <= ui_in[3:0];
                    state <= S_IDLE;
                end
            end

            S_LOAD: begin
                if (strobe) begin
                    case (load_idx)
                        4'd0: a00 <= ui_in;
                        4'd1: a01 <= ui_in;
                        4'd2: a10 <= ui_in;
                        4'd3: a11 <= ui_in;
                        4'd4: b00 <= ui_in;
                        4'd5: b01 <= ui_in;
                        4'd6: b10 <= ui_in;
                        4'd7: b11 <= ui_in;
                        default: ;
                    endcase

                    if (load_idx == 4'd7)
                        state <= S_IDLE;
                    else
                        load_idx <= load_idx + 1;
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
                    read_idx <= 0;
                    state <= S_DONE;
                end else begin
                    cycle_counter <= cycle_counter + 1;
                end
            end

            S_DONE: begin
                if (strobe && ui_in == CMD_READ) begin
                    case (read_idx)
                        4'd0: uo_out <= q00;
                        4'd1: uo_out <= q01;
                        4'd2: uo_out <= q10;
                        4'd3: uo_out <= q11;
                        4'd4: uo_out <= last_cycles[7:0];
                        4'd5: uo_out <= last_cycles[15:8];
                        default: uo_out <= 8'h00;
                    endcase

                    if (read_idx < 4'd5)
                        read_idx <= read_idx + 1;
                end else if (strobe && ui_in == CMD_LOAD) begin
                    load_idx <= 0;
                    read_idx <= 0;
                    state <= S_LOAD;
                end else if (strobe && ui_in == CMD_COMPUTE) begin
                    read_idx <= 0;
                    accel_rst <= 1;
                    cycle_counter <= 0;
                    last_cycles <= 0;
                    state <= S_RESET;
                end else if (strobe && ui_in == CMD_SHIFT) begin
                    state <= S_SHIFT;
                end
            end

            default: state <= S_IDLE;

        endcase
    end
end

endmodule

`default_nettype wire