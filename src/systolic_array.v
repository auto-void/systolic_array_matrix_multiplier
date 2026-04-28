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
    input  wire [$clog2(M_ROWS)-1:0] row_sel,      // row address
    input  wire [$clog2(N_COLS)-1:0] col_sel,      // column address
    output wire signed [ACCUM_WIDTH-1:0] c_read_data  // selected element
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

    reg [1:0]  state, state_next;
    reg [$clog2(K_DIM+1)-1:0] feed_cnt;
    reg [$clog2(M_ROWS+N_COLS+K_DIM+2)-1:0] drain_cnt;

    wire feed_done  = (feed_cnt == K_DIM - 1);
    // After feeding K elements, need M_ROWS-1 + N_COLS-1 + 1 more cycles for
    // pipeline drain + 1 cycle register delay for result
    localparam DRAIN_CYCLES = M_ROWS + N_COLS;  // pipeline latency
    wire drain_done = (drain_cnt == DRAIN_CYCLES - 1);

    assign busy   = (state != S_IDLE) && (state != S_DONE);
    assign a_ready = (state == S_FEED);
    assign b_ready = (state == S_FEED);

    // ----------------------------------------------------------------
    // FSM sequential
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    // FSM next-state
    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE:   if (a_valid && b_valid) state_next = S_FEED;
            S_FEED:   if (feed_done)          state_next = S_DRAIN;
            S_DRAIN:  if (drain_done)         state_next = S_DONE;
            S_DONE:   state_next = S_IDLE;
            default:  state_next = S_IDLE;
        endcase
    end

    // Feed counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            feed_cnt <= 0;
        else if (state == S_IDLE && state_next == S_FEED)
            feed_cnt <= 0;
        else if (state == S_FEED)
            feed_cnt <= feed_cnt + 1;
    end

    // Drain counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            drain_cnt <= 0;
        else if (state == S_FEED && state_next == S_DRAIN)
            drain_cnt <= 0;
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
    // Boundary input logic
    // ----------------------------------------------------------------
    // A boundary: pe_a_in[i][0] = a_data[i] when feeding, else 0
    // B boundary: pe_b_in[0][j] = b_data[j] when feeding, else 0
    genvar gi, gj;
    generate
        for (gi = 0; gi < M_ROWS; gi = gi + 1) begin : gen_a_boundary
            assign pe_a_in[gi][0] = (state == S_FEED) ? a_data[gi] : {DATA_WIDTH{1'b0}};
        end
        for (gj = 0; gj < N_COLS; gj = gj + 1) begin : gen_b_boundary
            assign pe_b_in[0][gj] = (state == S_FEED) ? b_data[gj] : {DATA_WIDTH{1'b0}};
        end
    endgenerate

    // ----------------------------------------------------------------
    // PE array instantiation & wiring
    // ----------------------------------------------------------------
    wire clear = (state == S_IDLE) || (state == S_DONE);

    generate
        for (gi = 0; gi < M_ROWS; gi = gi + 1) begin : gen_row
            for (gj = 0; gj < N_COLS; gj = gj + 1) begin : gen_col

                // Internal wiring: A flows right, B flows down
                if (gj > 0)
                    assign pe_a_in[gi][gj] = pe_a_out[gi][gj-1];
                if (gi > 0)
                    assign pe_b_in[gi][gj] = pe_b_out[gi-1][gj];

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

endmodule
