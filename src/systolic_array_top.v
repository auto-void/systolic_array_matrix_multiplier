`timescale 1ns / 1ps
// ============================================================================
// Configurable Wrapper for Systolic Array Matrix Multiplier
//
// Use Verilog defines to override parameters from command line:
//   iverilog -DM_ROWS=8 -DK_DIM=8 -DN_COLS=8 -DDATA_WIDTH=16 ...
//
// Or use the Makefile: make sim M=8 K=8 N=8 W=16
// ============================================================================

module systolic_array_top #(
    parameter M_ROWS     = `ifdef M_ROWS   `M_ROWS   `else 4 `endif,
    parameter K_DIM      = `ifdef K_DIM    `K_DIM    `else 4 `endif,
    parameter N_COLS     = `ifdef N_COLS   `N_COLS   `else 4 `endif,
    parameter DATA_WIDTH = `ifdef DATA_WIDTH `DATA_WIDTH `else 8 `endif,
    parameter ACCUM_WIDTH = `ifdef ACCUM_WIDTH `ACCUM_WIDTH `else 32 `endif
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire signed [DATA_WIDTH-1:0] a_data [0:M_ROWS-1],
    input  wire                     a_valid,
    output wire                     a_ready,
    input  wire signed [DATA_WIDTH-1:0] b_data [0:N_COLS-1],
    input  wire                     b_valid,
    output wire                     b_ready,
    output wire signed [ACCUM_WIDTH-1:0] c_data [0:M_ROWS-1][0:N_COLS-1],
    output wire                     c_valid,
    output wire                     busy,
    output wire                     any_overflow
);

    systolic_array #(
        .M_ROWS     (M_ROWS),
        .K_DIM      (K_DIM),
        .N_COLS     (N_COLS),
        .DATA_WIDTH (DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) u_array (
        .clk     (clk),
        .rst_n   (rst_n),
        .a_data  (a_data),
        .a_valid (a_valid),
        .a_ready (a_ready),
        .b_data  (b_data),
        .b_valid (b_valid),
        .b_ready (b_ready),
        .c_data  (c_data),
        .c_valid (c_valid),
        .busy    (busy),
        .any_overflow(any_overflow)
    );

endmodule
