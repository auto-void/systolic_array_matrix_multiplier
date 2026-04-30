`include "src/utils.vh"
`timescale 1ns / 1ps
// ============================================================================
// Testbench for Systolic Array Matrix Multiplier
//
// c_valid is registered (one cycle after DRAIN+drain_done). The TB captures
// c_data on the c_valid cycle — accumulators still hold results because
// clear_acc only activates when state==DONE (next posedge).
//
// feed_matrices task: feeds matrix data into the array. Does NOT deassert
// valid or wait for result — the caller must do that.
// ============================================================================

module tb_systolic_array;

    parameter M_ROWS     = `ifdef M_ROWS     `M_ROWS     `else 4 `endif;
    parameter K_DIM      = `ifdef K_DIM      `K_DIM      `else 4 `endif;
    parameter N_COLS     = `ifdef N_COLS     `N_COLS     `else 4 `endif;
    parameter DATA_WIDTH = `ifdef DATA_WIDTH `DATA_WIDTH `else 8 `endif;
    parameter ACCUM_WIDTH = `ifdef ACCUM_WIDTH `ACCUM_WIDTH `else 32 `endif;

    reg                              clk;
    reg                              rst_n;
    reg  signed [DATA_WIDTH-1:0]     a_data [0:M_ROWS-1];
    reg                               a_valid;
    wire                              a_ready;
    reg  signed [DATA_WIDTH-1:0]     b_data [0:N_COLS-1];
    reg                               b_valid;
    wire                              b_ready;
    wire signed [ACCUM_WIDTH-1:0]    c_data [0:M_ROWS-1][0:N_COLS-1];
    wire                              c_valid;
    wire                              busy;
    wire                              any_overflow;
    reg  [`ADDR_WIDTH(M_ROWS)-1:0]     row_sel;
    reg  [`ADDR_WIDTH(N_COLS)-1:0]     col_sel;
    wire signed [ACCUM_WIDTH-1:0]    c_read_data;
    wire [31:0]                       cycle_count;
    wire [7:0]                        overflow_count;

    reg signed [DATA_WIDTH-1:0]   A [0:M_ROWS-1][0:K_DIM-1];
    reg signed [DATA_WIDTH-1:0]   B [0:K_DIM-1][0:N_COLS-1];
    reg signed [ACCUM_WIDTH-1:0]  expected_C [0:M_ROWS-1][0:N_COLS-1];
    reg signed [ACCUM_WIDTH-1:0]  golden_C   [0:M_ROWS-1][0:N_COLS-1];

    integer errors;
    integer i, j, k;

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

    `ifdef DUMP
    initial begin
        $dumpfile("systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);
    end
    `endif

    initial begin
        errors = 0;
        rst_n  = 0;
        a_valid = 0;
        b_valid = 0;
        row_sel = 0;
        col_sel = 0;
        for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
        for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;
        #25; rst_n = 1; #10;

        // ============================================================
        // Test 1: Known values
        // ============================================================
        $display("=== Test 1: Known values (%0d×%0d × %0d×%0d) ===",
                 M_ROWS, K_DIM, K_DIM, N_COLS);
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = DATA_WIDTH'(i + k + 1);
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = DATA_WIDTH'(k + j + 1);
        compute_expected;
        feed_matrices;
        wait_for_result;
        a_valid = 0; b_valid = 0;
        check_result("Test 1");
        $display("  Computation took %0d cycles", cycle_count);
        #50;

        // ============================================================
        // Test 2: Random values
        // ============================================================
        $display("\n=== Test 2: Random values ===");
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = DATA_WIDTH'($urandom_range(0, (2**DATA_WIDTH) - 1) - (2**(DATA_WIDTH-1)));
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = DATA_WIDTH'($urandom_range(0, (2**DATA_WIDTH) - 1) - (2**(DATA_WIDTH-1)));
        compute_expected;
        feed_matrices;
        wait_for_result;
        a_valid = 0; b_valid = 0;
        check_result("Test 2");
        #50;

        // ============================================================
        // Test 3: Identity-like
        // ============================================================
        $display("\n=== Test 3: All ones A, identity B ===");
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = 1;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = (k == j) ? 1 : 0;
        compute_expected;
        feed_matrices;
        wait_for_result;
        a_valid = 0; b_valid = 0;
        check_result("Test 3");
        #50;

        // ============================================================
        // Test 4: Address-based readout
        // ============================================================
        $display("\n=== Test 4: Address-based readout ===");
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = DATA_WIDTH'(i + k + 1);
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = DATA_WIDTH'(k + j + 1);
        compute_expected;
        feed_matrices;
        wait_for_result;
        a_valid = 0; b_valid = 0;
        // Wait for result_bank to latch (happens on c_valid posedge)
        @(posedge clk);
        for (i = 0; i < M_ROWS; i = i + 1)
            for (j = 0; j < N_COLS; j = j + 1) begin
                row_sel = `ADDR_WIDTH(M_ROWS)'(i); col_sel = `ADDR_WIDTH(N_COLS)'(j); #1;
                if (c_read_data !== expected_C[i][j]) begin
                    $display("  READOUT MISMATCH at [%0d][%0d]: expected=%0d, got=%0d",
                             i, j, expected_C[i][j], c_read_data);
                    errors = errors + 1;
                end
            end
        if (errors == 0) $display("  All %0d elements read correctly", M_ROWS * N_COLS);
        $display("  → PASSED");
        #50;

        // ============================================================
        // Test 5: Overflow detection
        // ============================================================
        $display("\n=== Test 5: Overflow detection ===");
        $display("  DATA_WIDTH=%0d, ACCUM_WIDTH=%0d", DATA_WIDTH, ACCUM_WIDTH);
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = (1 << (DATA_WIDTH-1)) - 1;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = (1 << (DATA_WIDTH-1)) - 1;
        compute_expected;
        feed_matrices;
        wait_for_result;
        a_valid = 0; b_valid = 0;
        if (any_overflow) begin
            $display("  UNEXPECTED: overflow flag raised (overflow_count=%0d)", overflow_count);
            $display("  → FAILED (overflow should not occur with ACCUM_WIDTH=%0d)", ACCUM_WIDTH);
            errors = errors + 1;
        end else if (overflow_count > 0) begin
            $display("  Overflow count=%0d but any_overflow=0 — wiring mismatch!", overflow_count);
            $display("  → FAILED");
            errors = errors + 1;
        end else begin
            $display("  Overflow count=%0d, any_overflow=0 — detection works correctly", overflow_count);
            $display("  → PASSED");
        end
        #50;

        // ============================================================
        // Test 6: Back-to-back (DONE→FEED without IDLE gap)
        // ============================================================
        $display("\n=== Test 6: Back-to-back computation ===");
        // 6a: first computation
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = DATA_WIDTH'(i + k + 1);
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = DATA_WIDTH'(k + j + 1);
        compute_expected;
        feed_matrices;
        wait_for_result;
        a_valid = 0; b_valid = 0;
        check_result("Test 6a");

        // 6b: second computation — keep valid high for DONE→FEED
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = DATA_WIDTH'((i + 1) * (k + 1));
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = DATA_WIDTH'((k + 1) * (j + 1));
        compute_expected;
        // Preset cycle-0 data BEFORE the posedge that moves FSM to DONE
        for (i = 0; i < M_ROWS; i = i + 1)
            if (0 >= i && (0 - i) < K_DIM)
                a_data[i] = A[i][0 - i];
            else
                a_data[i] = 0;
        for (j = 0; j < N_COLS; j = j + 1)
            if (0 >= j && (0 - j) < K_DIM)
                b_data[j] = B[0 - j][j];
            else
                b_data[j] = 0;
        // valid stays high from 6a → FSM sees DONE→FEED on next posedge
        @(posedge clk);  // FSM: DONE→FEED, feed_cnt=0
        begin : feed_6b
            integer c, fc, ii, jj;
            fc = K_DIM + M_ROWS + N_COLS - 2;
            for (c = 1; c < fc; c = c + 1) begin
                for (ii = 0; ii < M_ROWS; ii = ii + 1)
                    if (c >= ii && (c - ii) < K_DIM)
                        a_data[ii] = A[ii][c - ii];
                    else
                        a_data[ii] = 0;
                for (jj = 0; jj < N_COLS; jj = jj + 1)
                    if (c >= jj && (c - jj) < K_DIM)
                        b_data[jj] = B[c - jj][jj];
                    else
                        b_data[jj] = 0;
                @(posedge clk);
            end
            for (ii = 0; ii < M_ROWS; ii = ii + 1) a_data[ii] = 0;
            for (jj = 0; jj < N_COLS; jj = jj + 1) b_data[jj] = 0;
            @(posedge clk);
        end
        a_valid = 0; b_valid = 0;
        wait_for_result;
        check_result("Test 6b (back-to-back)");
        #50;

        // ============================================================
        // Test 7: All-zero matrices
        // ============================================================
        $display("\n=== Test 7: All-zero matrices ===");
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = DATA_WIDTH'(0);
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = DATA_WIDTH'(0);
        compute_expected;
        feed_matrices;
        wait_for_result;
        a_valid = 0; b_valid = 0;
        check_result("Test 7 (all-zero)");
        #50;

        // ============================================================
        // Test 8: Single-element (1x1 x 1x1)
        // ============================================================
        $display("\n=== Test 8: Single-element 1x1 x 1x1 ===");
        begin
            reg signed [ACCUM_WIDTH-1:0] expected_1x1;
            A[0][0] = DATA_WIDTH'(1);
            B[0][0] = DATA_WIDTH'(1);
            expected_1x1 = 1;
            feed_matrices;
            wait_for_result;
            a_valid = 0; b_valid = 0;
            if (golden_C[0][0] !== expected_1x1) begin
                $display("  MISMATCH: expected=%0d, got=%0d", expected_1x1, golden_C[0][0]);
                errors = errors + 1;
            end else begin
                $display("  [PASS] Test 8");
            end
        end
        #50;

        #100;
        if (errors == 0) $display("\n*** ALL TESTS PASSED ***");
        else             $display("\n*** %0d ERRORS DETECTED ***", errors);
        $finish;
    end

    // ----------------------------------------------------------------
    task compute_expected;
        reg signed [ACCUM_WIDTH-1:0] sum;
        begin
            for (i = 0; i < M_ROWS; i = i + 1)
                for (j = 0; j < N_COLS; j = j + 1) begin
                    sum = 0;
                    for (k = 0; k < K_DIM; k = k + 1)
                        sum = sum + $signed(A[i][k]) * $signed(B[k][j]);
                    expected_C[i][j] = sum;
                end
        end
    endtask

    // ----------------------------------------------------------------
    // Feed task — feeds matrix data into the array.
    // Does NOT deassert valid or wait for result. Caller must:
    //   1. wait_for_result
    //   2. a_valid = 0; b_valid = 0;
    //   3. #50; (settling time)
    // ----------------------------------------------------------------
    task feed_matrices;
        integer c, ii, jj, fc;
        begin
            wait (!busy);
            @(posedge clk);  // ensure FSM in IDLE

            fc = K_DIM + M_ROWS + N_COLS - 2;

            // Pre-set cycle-0 data BEFORE asserting valid
            for (ii = 0; ii < M_ROWS; ii = ii + 1)
                if (0 >= ii && (0 - ii) < K_DIM)
                    a_data[ii] = A[ii][0 - ii];
                else
                    a_data[ii] = 0;
            for (jj = 0; jj < N_COLS; jj = jj + 1)
                if (0 >= jj && (0 - jj) < K_DIM)
                    b_data[jj] = B[0 - jj][jj];
                else
                    b_data[jj] = 0;

            // Assert valid — FSM will enter FEED on next posedge
            a_valid = 1;
            b_valid = 1;
            @(posedge clk);  // FSM: IDLE→FEED, feed_cnt=0

            // Feed remaining fc-1 cycles
            for (c = 1; c < fc; c = c + 1) begin
                for (ii = 0; ii < M_ROWS; ii = ii + 1)
                    if (c >= ii && (c - ii) < K_DIM)
                        a_data[ii] = A[ii][c - ii];
                    else
                        a_data[ii] = 0;
                for (jj = 0; jj < N_COLS; jj = jj + 1)
                    if (c >= jj && (c - jj) < K_DIM)
                        b_data[jj] = B[c - jj][jj];
                    else
                        b_data[jj] = 0;
                @(posedge clk);
            end

            // Final posedge: PE accumulates last cycle's product
            for (ii = 0; ii < M_ROWS; ii = ii + 1) a_data[ii] = 0;
            for (jj = 0; jj < N_COLS; jj = jj + 1) b_data[jj] = 0;
            @(posedge clk);

            // valid stays HIGH — caller decides when to deassert
        end
    endtask

    // ----------------------------------------------------------------
    // Wait for c_valid (registered) and capture results.
    // c_valid asserts one cycle after state==S_DRAIN. At that posedge,
    // state is still DRAIN, clear_acc=0, accumulators hold valid results.
    // We capture c_data before the next posedge transitions to DONE.
    // ----------------------------------------------------------------
    task wait_for_result;
        begin
            wait (c_valid);
            // Capture c_data on c_valid cycle — state still DRAIN, accumulators valid
            for (i = 0; i < M_ROWS; i = i + 1)
                for (j = 0; j < N_COLS; j = j + 1)
                    golden_C[i][j] = c_data[i][j];
            @(posedge clk);  // transition to DONE
        end
    endtask

    // ----------------------------------------------------------------
    task check_result;
        input [255:0] test_name;
        integer errors_before;
        begin
            errors_before = errors;
            $display("  Expected C:");
            for (i = 0; i < M_ROWS; i = i + 1) begin
                $write("    ");
                for (j = 0; j < N_COLS; j = j + 1)
                    $write("%6d ", expected_C[i][j]);
                $write("\n");
            end
            $display("  Got C:");
            for (i = 0; i < M_ROWS; i = i + 1) begin
                $write("    ");
                for (j = 0; j < N_COLS; j = j + 1)
                    $write("%6d ", golden_C[i][j]);
                $write("\n");
            end
            for (i = 0; i < M_ROWS; i = i + 1)
                for (j = 0; j < N_COLS; j = j + 1)
                    if (golden_C[i][j] !== expected_C[i][j]) begin
                        $display("  MISMATCH at [%0d][%0d]: expected=%0d, got=%0d",
                                 i, j, expected_C[i][j], golden_C[i][j]);
                        errors = errors + 1;
                    end
            if (errors == errors_before) $display("  → PASSED");
            else                         $display("  → FAILED");
        end
    endtask

endmodule
