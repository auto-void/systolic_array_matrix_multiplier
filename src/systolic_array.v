`include "src/utils.vh"
`timescale 1ns / 1ps
// ============================================================================
// Systolic Array Matrix Multiplier — Top Module
//
// Computes: C = A × B
//   A : M_ROWS × K_DIM  (signed integer)
//   B : K_DIM  × N_COLS (signed integer)
//   C : M_ROWS × N_COLS (signed integer, ACCUM_WIDTH bit accumulator)
//
// Data flow:
//   A enters from the left edge, B enters from the top edge.
//   Each PE(i,j) accumulates C[i][j] = Σ_k A[i][k] * B[k][j].
//
// Timing:
//   1. Assert start → internal FSM feeds data over K_DIM cycles.
//   2. Result is valid after M_ROWS + N_COLS + K_DIM cycles (pipeline latency).
// ============================================================================

module systolic_array #(
    parameter M_ROWS     = 4,
    parameter K_DIM      = 4,
    parameter N_COLS     = 4,
    parameter DATA_WIDTH = 8,
    parameter ACCUM_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Matrix A input (row-serial): feed one element per cycle per row
    input  wire signed [DATA_WIDTH-1:0] a_data [0:M_ROWS-1],  // A[i][*] feed
    input  wire                     a_valid,
    output wire                     a_ready,                   // array accepts A

    // Matrix B input (col-serial): feed one element per cycle per column
    input  wire signed [DATA_WIDTH-1:0] b_data [0:N_COLS-1],  // B[*][j] feed
    input  wire                     b_valid,
    output wire                     b_ready,                   // array accepts B

    // Result output — full matrix (directly from PE accumulators)
    output wire signed [ACCUM_WIDTH-1:0] c_data [0:M_ROWS-1][0:N_COLS-1],
    output reg                      c_valid,
    output wire                     busy,
    output wire                     any_overflow,  // OR of all PE overflow flags

    // Result readout — address-based single-element access
    input  wire [`ADDR_WIDTH(M_ROWS)-1:0] row_sel,      // row address
    input  wire [`ADDR_WIDTH(N_COLS)-1:0] col_sel,      // column address
    output wire signed [ACCUM_WIDTH-1:0] c_read_data, // selected element

    // Status outputs
    output wire [31:0]              cycle_count,   // total cycles since start
    output wire [7:0]               overflow_count // number of PEs that overflowed
);

    // ----------------------------------------------------------------
    // Internal signals
    // ----------------------------------------------------------------
    wire signed [DATA_WIDTH-1:0] pe_a_out [0:M_ROWS-1][0:N_COLS-1];
    wire signed [DATA_WIDTH-1:0] pe_b_out [0:M_ROWS-1][0:N_COLS-1];
    wire signed [DATA_WIDTH-1:0] pe_a_in  [0:M_ROWS-1][0:N_COLS-1];
    wire signed [DATA_WIDTH-1:0] pe_b_in  [0:M_ROWS-1][0:N_COLS-1];
    wire        pe_overflow [0:M_ROWS-1][0:N_COLS-1];

    // FSM
    localparam S_IDLE   = 2'd0;
    localparam S_FEED   = 2'd1;
    localparam S_DRAIN  = 2'd2;
    localparam S_DONE   = 2'd3;

    reg [1:0]  state, state_next, prev_state;
    reg [$clog2(K_DIM+M_ROWS+N_COLS+1)-1:0] feed_cnt;
    reg [$clog2(M_ROWS+N_COLS+K_DIM+2)-1:0] drain_cnt;

    // FEED phase: data is staggered — A[i][k] enters at cycle k+i, B[k][j] at k+j
    // Boundary is combinational, but PE accumulates on the NEXT posedge.
    // PE(i,j) accumulates at cycle k+i+j+1. Last accumulation:
    // PE(M-1,N-1) at cycle (K-1)+(M-1)+(N-1)+1 = K+M+N-2.
    // en must be high for cycles 0..K+M+N-3, so FEED_CYCLES = K+M+N-2.
    localparam FEED_CYCLES = K_DIM + M_ROWS + N_COLS - 2;
    wire feed_done  = (feed_cnt == FEED_CYCLES - 1);
    // DRAIN: no additional flush needed — all data accumulated by FEED end.
    // Just 1 cycle for c_valid to latch.
    localparam DRAIN_CYCLES = 1;
    wire drain_done = (drain_cnt == DRAIN_CYCLES - 1);

    assign busy   = (state != S_IDLE) && (state != S_DONE);
    assign a_ready = (state == S_FEED);
    assign b_ready = (state == S_FEED);

    // ----------------------------------------------------------------
    // FSM sequential
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            prev_state <= S_IDLE;
        end else begin
            prev_state <= state;
            state <= state_next;
        end
    end

    // FSM next-state
    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE:   if (a_valid && b_valid) state_next = S_FEED;
            S_FEED:   if (feed_done)          state_next = S_DRAIN;
            S_DRAIN:  if (drain_done)         state_next = S_DONE;
            S_DONE:   if (a_valid && b_valid) state_next = S_FEED;  // back-to-back
                      else                    state_next = S_IDLE;
            default:  state_next = S_IDLE;
        endcase
    end

    // Feed counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            feed_cnt <= 0;
        else if (state == S_IDLE && state_next == S_FEED)
            feed_cnt <= 0;
        else if (state == S_DONE && state_next == S_FEED)
            feed_cnt <= 0;  // back-to-back: reset on DONE→FEED
        else if (state == S_FEED)
            feed_cnt <= feed_cnt + 1;
    end

    // Drain counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            drain_cnt <= 0;
        else if (state == S_FEED && state_next == S_DRAIN)
            drain_cnt <= 0;
        else if (state == S_DONE && state_next == S_FEED)
            drain_cnt <= 0;  // back-to-back: reset on DONE→FEED

        else if (state == S_DRAIN)
            drain_cnt <= drain_cnt + 1;
    end

    // Result valid (one cycle after last PE finishes accumulation)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            c_valid <= 1'b0;
        else
            c_valid <= (state == S_DRAIN) && drain_done;
    end

    // ----------------------------------------------------------------
    // Boundary input logic — Staggered entry for data alignment
    // ----------------------------------------------------------------
    // In a systolic array, A flows right (j PEs) and B flows down (i PEs).
    // To ensure A[i][k] and B[k][j] arrive at PE(i,j) simultaneously:
    //
    //   A[i][k] enters PE(i,0) at cycle k+i  (staggered by row)
    //   B[k][j] enters PE(0,j) at cycle k+j  (staggered by column)
    //   Both reach PE(i,j) at cycle k+i+j    ✓ aligned!
    //
    // At FEED cycle c:
    //   pe_a_in[i][0] = A[i][c-i] if c >= i and c-i < K_DIM, else 0
    //   pe_b_in[0][j] = B[c-j][j] if c >= j and c-j < K_DIM, else 0
    //
    // Total FEED cycles = K_DIM + M_ROWS + N_COLS - 2
    // Both boundaries are combinational (no extra registers).
    genvar gi, gj;
    generate
        for (gi = 0; gi < M_ROWS; gi = gi + 1) begin : gen_a_boundary
            /* verilator lint_off UNSIGNED */
            wire a_in_range = (state == S_FEED) &&
                              (feed_cnt >= gi) &&
                              (feed_cnt - gi < K_DIM);
            /* verilator lint_on UNSIGNED */
            assign pe_a_in[gi][0] = a_in_range ? a_data[gi] : {DATA_WIDTH{1'b0}};
        end
        for (gj = 0; gj < N_COLS; gj = gj + 1) begin : gen_b_boundary
            /* verilator lint_off UNSIGNED */
            wire b_in_range = (state == S_FEED) &&
                              (feed_cnt >= gj) &&
                              (feed_cnt - gj < K_DIM);
            /* verilator lint_on UNSIGNED */
            assign pe_b_in[0][gj] = b_in_range ? b_data[gj] : {DATA_WIDTH{1'b0}};
        end
    endgenerate

    // ----------------------------------------------------------------
    // PE array instantiation & wiring
    // ----------------------------------------------------------------
    // Clear accumulator in IDLE and DONE states.
    // No DONE→FEED edge detection needed — DONE state keeps clear high
    // for multiple cycles, ensuring accumulator is zero before FEED starts.
    // The testbench pre-sets cycle-0 data while in DONE state so the
    // boundary has it ready when the first FEED posedge arrives.
    wire clear = (state == S_IDLE) || (state == S_DONE);

    generate
        for (gi = 0; gi < M_ROWS; gi = gi + 1) begin : gen_row
            for (gj = 0; gj < N_COLS; gj = gj + 1) begin : gen_col

                // Internal wiring: A flows right, B flows down
                if (gj > 0) begin : gen_a_wire
                    assign pe_a_in[gi][gj] = pe_a_out[gi][gj-1];
                end
                if (gi > 0) begin : gen_b_wire
                    assign pe_b_in[gi][gj] = pe_b_out[gi-1][gj];
                end

                pe #(
                    .DATA_WIDTH  (DATA_WIDTH),
                    .ACCUM_WIDTH (ACCUM_WIDTH)
                ) u_pe (
                    .clk       (clk),
                    .rst_n     (rst_n),
                    .en        (state == S_FEED),
                    .clear_acc (clear),
                    .a_in      (pe_a_in[gi][gj]),
                    .b_in      (pe_b_in[gi][gj]),
                    .a_out     (pe_a_out[gi][gj]),
                    .b_out     (pe_b_out[gi][gj]),
                    .result    (c_data[gi][gj]),
                    .overflow  (pe_overflow[gi][gj])
                );

            end
        end
    endgenerate

    // ----------------------------------------------------------------
    // Result register bank — latches final values when c_valid asserts
    // Keeps results stable even after next computation starts
    // ----------------------------------------------------------------
    reg signed [ACCUM_WIDTH-1:0] result_bank [0:M_ROWS-1][0:N_COLS-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin : rst_bank
            integer ri, rj;
            for (ri = 0; ri < M_ROWS; ri = ri + 1)
                for (rj = 0; rj < N_COLS; rj = rj + 1)
                    result_bank[ri][rj] <= {ACCUM_WIDTH{1'b0}};
        end else if (c_valid) begin : latch_bank
            integer ri, rj;
            for (ri = 0; ri < M_ROWS; ri = ri + 1)
                for (rj = 0; rj < N_COLS; rj = rj + 1)
                    result_bank[ri][rj] <= c_data[ri][rj];
        end
    end

    // Address-based readout mux
    assign c_read_data = result_bank[row_sel][col_sel];

    // ----------------------------------------------------------------
    // Overflow aggregation
    // ----------------------------------------------------------------
    reg ovf_accum;
    integer oi, oj;
    always @(*) begin
        ovf_accum = 1'b0;
        for (oi = 0; oi < M_ROWS; oi = oi + 1)
            for (oj = 0; oj < N_COLS; oj = oj + 1)
                ovf_accum = ovf_accum | pe_overflow[oi][oj];
    end
    assign any_overflow = ovf_accum;

    // Overflow count — how many PEs overflowed
    reg [7:0] ovf_cnt;
    always @(*) begin
        ovf_cnt = 0;
        for (oi = 0; oi < M_ROWS; oi = oi + 1)
            for (oj = 0; oj < N_COLS; oj = oj + 1)
                ovf_cnt = ovf_cnt + 8'(pe_overflow[oi][oj]);
    end
    assign overflow_count = ovf_cnt;

    // Cycle counter — counts from start of feed to result valid
    reg [31:0] cyc_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cyc_cnt <= 0;
        else if (state == S_IDLE && state_next == S_FEED)
            cyc_cnt <= 0;
        else if (busy)
            cyc_cnt <= cyc_cnt + 1;
    end
    assign cycle_count = cyc_cnt;

endmodule
