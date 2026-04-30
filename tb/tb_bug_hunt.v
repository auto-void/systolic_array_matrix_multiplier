`include "src/utils.vh"
`timescale 1ns / 1ps
// ============================================================================
// Bug Hunt Testbench — targeted tests for potential unknown bugs
// Tests: back-to-back overflow flag reset, K_DIM=1, large K, negative values
// ============================================================================

module tb_bug_hunt;

    parameter M_ROWS     = 4;
    parameter K_DIM      = 4;
    parameter N_COLS     = 4;
    parameter DATA_WIDTH = 8;
    parameter ACCUM_WIDTH = 32;

    reg                              clk, rst_n;
    reg  signed [DATA_WIDTH-1:0]     a_data [0:M_ROWS-1];
    reg                               a_valid;
    wire                              a_ready;
    reg  signed [DATA_WIDTH-1:0]     b_data [0:N_COLS-1];
    reg                               b_valid;
    wire                              b_ready;
    wire signed [ACCUM_WIDTH-1:0]    c_data [0:M_ROWS-1][0:N_COLS-1];
    wire                              c_valid, busy, any_overflow;
    reg  [`ADDR_WIDTH(M_ROWS)-1:0]  row_sel;
    reg  [`ADDR_WIDTH(N_COLS)-1:0]  col_sel;
    wire signed [ACCUM_WIDTH-1:0]    c_read_data;
    wire [31:0]                       cycle_count;
    wire [7:0]                        overflow_count;

    systolic_array #(
        .M_ROWS(M_ROWS), .K_DIM(K_DIM), .N_COLS(N_COLS),
        .DATA_WIDTH(DATA_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .a_data(a_data), .a_valid(a_valid), .a_ready(a_ready),
        .b_data(b_data), .b_valid(b_valid), .b_ready(b_ready),
        .c_data(c_data), .c_valid(c_valid), .busy(busy),
        .any_overflow(any_overflow),
        .row_sel(row_sel), .col_sel(col_sel),
        .c_read_data(c_read_data),
        .cycle_count(cycle_count),
        .overflow_count(overflow_count)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors, i, j, k, c, fc;
    reg signed [ACCUM_WIDTH-1:0] expected [0:M_ROWS-1][0:N_COLS-1];

    task feed_and_check;
        input integer fc_val;
        begin
            wait (!busy); @(posedge clk);
            // Pre-set cycle-0 data
            for (i = 0; i < M_ROWS; i = i + 1)
                a_data[i] = (0 >= i && (0 - i) < K_DIM) ? a_data_store[i][0] : 0;
            for (j = 0; j < N_COLS; j = j + 1)
                b_data[j] = (0 >= j && (0 - j) < K_DIM) ? b_data_store[0][j] : 0;
            a_valid = 1; b_valid = 1;
            @(posedge clk);
            for (c = 1; c < fc_val; c = c + 1) begin
                for (i = 0; i < M_ROWS; i = i + 1)
                    a_data[i] = (c >= i && (c - i) < K_DIM) ? a_data_store[i][c - i] : 0;
                for (j = 0; j < N_COLS; j = j + 1)
                    b_data[j] = (c >= j && (c - j) < K_DIM) ? b_data_store[c - j][j] : 0;
                @(posedge clk);
            end
            for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
            for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;
            @(posedge clk);
            a_valid = 0; b_valid = 0;
            wait (c_valid); @(posedge clk);
        end
    endtask

    reg signed [DATA_WIDTH-1:0] a_data_store [0:M_ROWS-1][0:K_DIM-1];
    reg signed [DATA_WIDTH-1:0] b_data_store [0:K_DIM-1][0:N_COLS-1];

    task compute_expected;
        reg signed [ACCUM_WIDTH-1:0] sum;
        begin
            for (i = 0; i < M_ROWS; i = i + 1)
                for (j = 0; j < N_COLS; j = j + 1) begin
                    sum = 0;
                    for (k = 0; k < K_DIM; k = k + 1)
                        sum = sum + $signed(a_data_store[i][k]) * $signed(b_data_store[k][j]);
                    expected[i][j] = sum;
                end
        end
    endtask

    task check_results;
        input [8*32-1:0] test_name;
        integer idx;
        begin
            idx = 0;
            for (i = 0; i < M_ROWS; i = i + 1)
                for (j = 0; j < N_COLS; j = j + 1) begin
                    if (c_data[i][j] !== expected[i][j]) begin
                        $display("  [%s] MISMATCH at [%0d][%0d]: expected=%0d, got=%0d",
                                 test_name, i, j, expected[i][j], c_data[i][j]);
                        errors = errors + 1;
                    end
                    idx = idx + 1;
                end
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 0;
        a_valid = 0; b_valid = 0;
        row_sel = 0; col_sel = 0;
        for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
        for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;
        #25; rst_n = 1; #10;

        // ============================================================
        // Test 1: Back-to-back — overflow flag resets between computations
        // First: all-max values (no overflow with ACCUM_WIDTH=32)
        // Second: verify overflow flag is 0
        // ============================================================
        $display("=== Test 1: Overflow flag reset between computations ===");
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                a_data_store[i][k] = 127;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                b_data_store[k][j] = 127;
        compute_expected;
        feed_and_check(K_DIM + M_ROWS + N_COLS - 2);
        check_results("T1-max");
        if (any_overflow) begin
            $display("  UNEXPECTED: overflow with ACCUM_WIDTH=%0d", ACCUM_WIDTH);
            errors = errors + 1;
        end
        $display("  Result[0][0]=%0d, overflow=%0d", c_data[0][0], any_overflow);

        // Second computation: small values
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                a_data_store[i][k] = 1;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                b_data_store[k][j] = 1;
        compute_expected;
        feed_and_check(K_DIM + M_ROWS + N_COLS - 2);
        check_results("T1-small");
        if (any_overflow) begin
            $display("  BUG: overflow flag leaked from previous computation!");
            errors = errors + 1;
        end else begin
            $display("  Overflow flag correctly reset: %0d", any_overflow);
        end

        // ============================================================
        // Test 2: All-negative values
        // A[i][k] = -1, B[k][j] = -1 → C = K_DIM (positive)
        // ============================================================
        $display("\n=== Test 2: All-negative values ===");
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                a_data_store[i][k] = -1;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                b_data_store[k][j] = -1;
        compute_expected;
        feed_and_check(K_DIM + M_ROWS + N_COLS - 2);
        check_results("T2-neg");
        if (c_data[0][0] !== K_DIM) begin
            $display("  BUG: (-1)*(-1)*K = %0d, got %0d", K_DIM, c_data[0][0]);
            errors = errors + 1;
        end else begin
            $display("  All-negative: C[0][0]=%0d (expect %0d) OK", c_data[0][0], K_DIM);
        end

        // ============================================================
        // Test 3: Mixed signs
        // A = [[127,-128],[127,-128]], B = [[127,127],[-128,-128]]
        // C[0][0] = 127*127 + (-128)*(-128) = 16129 + 16384 = 32513
        // C[0][1] = 127*127 + (-128)*(-128) = 32513
        // ============================================================
        $display("\n=== Test 3: Mixed signs, extreme values ===");
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                a_data_store[i][k] = 0;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                b_data_store[k][j] = 0;
        a_data_store[0][0] = 127; a_data_store[0][1] = -128;
        a_data_store[1][0] = 127; a_data_store[1][1] = -128;
        b_data_store[0][0] = 127; b_data_store[0][1] = 127;
        b_data_store[1][0] = -128; b_data_store[1][1] = -128;
        compute_expected;
        feed_and_check(K_DIM + M_ROWS + N_COLS - 2);
        check_results("T3-extreme");
        $display("  C[0][0]=%0d (expect 32513), C[0][1]=%0d (expect 32513)",
                 c_data[0][0], c_data[0][1]);

        // ============================================================
        // Test 4: Back-to-back with different matrix sizes
        // (same module params, different data patterns)
        // ============================================================
        $display("\n=== Test 4: Back-to-back pattern stress ===");
        begin
            integer iter;
            for (iter = 0; iter < 5; iter = iter + 1) begin
                // Random-ish data
                for (i = 0; i < M_ROWS; i = i + 1)
                    for (k = 0; k < K_DIM; k = k + 1)
                        a_data_store[i][k] = DATA_WIDTH'((i * K_DIM + k + iter * 7) % 256 - 128);
                for (k = 0; k < K_DIM; k = k + 1)
                    for (j = 0; j < N_COLS; j = j + 1)
                        b_data_store[k][j] = DATA_WIDTH'((k * N_COLS + j + iter * 13) % 256 - 128);
                compute_expected;
                feed_and_check(K_DIM + M_ROWS + N_COLS - 2);
                check_results("T4-iter");
            end
            if (errors == 0)
                $display("  5 back-to-back iterations: all correct");
        end

        // ============================================================
        // Test 5: Rapid DONE→FEED (no idle gap)
        // ============================================================
        $display("\n=== Test 5: Rapid DONE→FEED (no idle gap) ===");
        begin
            integer iter;
            for (iter = 0; iter < 3; iter = iter + 1) begin
                for (i = 0; i < M_ROWS; i = i + 1)
                    for (k = 0; k < K_DIM; k = k + 1)
                        a_data_store[i][k] = DATA_WIDTH'(iter + 1);
                for (k = 0; k < K_DIM; k = k + 1)
                    for (j = 0; j < N_COLS; j = j + 1)
                        b_data_store[k][j] = DATA_WIDTH'(iter + 1);
                compute_expected;
                // Don't wait for IDLE — feed immediately after DONE
                wait (!busy);
                for (i = 0; i < M_ROWS; i = i + 1)
                    a_data[i] = (0 >= i && (0 - i) < K_DIM) ? a_data_store[i][0] : 0;
                for (j = 0; j < N_COLS; j = j + 1)
                    b_data[j] = (0 >= j && (0 - j) < K_DIM) ? b_data_store[0][j] : 0;
                a_valid = 1; b_valid = 1;
                @(posedge clk);
                fc = K_DIM + M_ROWS + N_COLS - 2;
                for (c = 1; c < fc; c = c + 1) begin
                    for (i = 0; i < M_ROWS; i = i + 1)
                        a_data[i] = (c >= i && (c - i) < K_DIM) ? a_data_store[i][c - i] : 0;
                    for (j = 0; j < N_COLS; j = j + 1)
                        b_data[j] = (c >= j && (c - j) < K_DIM) ? b_data_store[c - j][j] : 0;
                    @(posedge clk);
                end
                for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
                for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;
                @(posedge clk);
                a_valid = 0; b_valid = 0;
                wait (c_valid); @(posedge clk);
                check_results("T5-rapid");
            end
            if (errors == 0)
                $display("  3 rapid DONE→FEED iterations: all correct");
        end

        // ============================================================
        #100;
        if (errors == 0)
            $display("\n*** ALL BUG HUNT TESTS PASSED ***");
        else
            $display("\n*** %0d ERRORS IN BUG HUNT ***", errors);
        $finish;
    end

endmodule
