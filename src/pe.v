`timescale 1ns / 1ps
// ============================================================================
// Processing Element (PE) for Systolic Array Matrix Multiplier
//
// Each PE computes: accum += a_in * b_in
// Data flows:  a_in -> [PE] -> a_out (rightward)
//              b_in -> [PE] -> b_out (downward)
// ============================================================================

module pe #(
    parameter DATA_WIDTH  = 8,
    parameter ACCUM_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,          // enable accumulation
    input  wire                     clear_acc,   // clear accumulator
    input  wire signed [DATA_WIDTH-1:0]  a_in,   // from left neighbor
    input  wire signed [DATA_WIDTH-1:0]  b_in,   // from top neighbor
    output reg  signed [DATA_WIDTH-1:0]  a_out,  // to right neighbor
    output reg  signed [DATA_WIDTH-1:0]  b_out,  // to bottom neighbor
    output wire signed [ACCUM_WIDTH-1:0] result  // accumulated output
);

    reg signed [ACCUM_WIDTH-1:0] accum;

    // Accumulator
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum <= {ACCUM_WIDTH{1'b0}};
        end else if (clear_acc) begin
            accum <= {ACCUM_WIDTH{1'b0}};
        end else if (en) begin
            accum <= accum + $signed(a_in) * $signed(b_in);
        end
    end

    // Pass data to neighbors (pipeline registers)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out <= {DATA_WIDTH{1'b0}};
            b_out <= {DATA_WIDTH{1'b0}};
        end else if (en) begin
            a_out <= a_in;
            b_out <= b_in;
        end
    end

    assign result = accum;

endmodule
