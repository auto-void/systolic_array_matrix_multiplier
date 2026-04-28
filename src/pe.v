`timescale 1ns / 1ps
// ============================================================================
// Processing Element (PE) for Systolic Array Matrix Multiplier
//
// Each PE computes: accum += a_in * b_in
// Data flows:  a_in -> [PE] -> a_out (rightward)
//              b_in -> [PE] -> b_out (downward)
//
// Features:
//   - Signed multiply-accumulate
//   - Overflow detection with saturation arithmetic
//   - Pipeline registers for data pass-through
// ============================================================================

module pe #(
    parameter DATA_WIDTH  = 8,
    parameter ACCUM_WIDTH = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         en,          // enable accumulation
    input  wire                         clear_acc,   // clear accumulator
    input  wire signed [DATA_WIDTH-1:0]  a_in,       // from left neighbor
    input  wire signed [DATA_WIDTH-1:0]  b_in,       // from top neighbor
    output reg  signed [DATA_WIDTH-1:0]  a_out,      // to right neighbor
    output reg  signed [DATA_WIDTH-1:0]  b_out,      // to bottom neighbor
    output wire signed [ACCUM_WIDTH-1:0] result,     // accumulated output
    output reg                          overflow    // overflow flag (sticky)
);

    // Saturation limits
    localparam signed [ACCUM_WIDTH-1:0] SAT_MAX = {1'b0, {(ACCUM_WIDTH-1){1'b1}}};
    localparam signed [ACCUM_WIDTH-1:0] SAT_MIN = {1'b1, {(ACCUM_WIDTH-1){1'b0}}};

    reg signed [ACCUM_WIDTH-1:0] accum;

    // Compute product (full precision, no overflow possible with proper ACCUM_WIDTH)
    wire signed [ACCUM_WIDTH-1:0] product;
    assign product = $signed(a_in) * $signed(b_in);

    // Next accumulation value
    wire signed [ACCUM_WIDTH-1:0] sum_next;
    assign sum_next = accum + product;

    // Overflow detection for accum + product
    // Occurs when: same-sign operands produce different-sign result
    wire pos_overflow = ~accum[ACCUM_WIDTH-1] & ~product[ACCUM_WIDTH-1] &  sum_next[ACCUM_WIDTH-1];
    wire neg_overflow =  accum[ACCUM_WIDTH-1] &  product[ACCUM_WIDTH-1] & ~sum_next[ACCUM_WIDTH-1];
    wire ovf = pos_overflow | neg_overflow;

    // Accumulator with saturation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum    <= {ACCUM_WIDTH{1'b0}};
            overflow <= 1'b0;
        end else if (clear_acc) begin
            accum    <= {ACCUM_WIDTH{1'b0}};
            overflow <= 1'b0;
        end else if (en) begin
            if (ovf) begin
                // Saturate to max/min instead of wrapping
                accum    <= pos_overflow ? SAT_MAX : SAT_MIN;
                overflow <= 1'b1;
            end else begin
                accum <= sum_next;
            end
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
