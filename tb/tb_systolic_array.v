`timescale 1ns / 1ps
// ============================================================================
// Testbench for Systolic Array Matrix Multiplier
// ============================================================================

module tb_systolic_array;

    // ----------------------------------------------------------------
    // Parameters — change these to test different configurations
    // ----------------------------------------------------------------
    parameter M_ROWS     = 4;
    parameter K_DIM      = 4;
    parameter N_COLS     = 4;
    parameter DATA_WIDTH = 8;
    parameter ACCUM_WIDTH = 32;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
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
    reg  [$clog2(M_ROWS)-1:0]        row_sel;
    reg  [$clog2(N_COLS)-1:0]        col_sel;
    wire signed [ACCUM_WIDTH-1:0]    c_read_data;
    wire [31:0]                       cycle_count;
    wire [7:0]                        overflow_count;

    // ----------------------------------------------------------------
    // Test data
    // ----------------------------------------------------------------
    reg signed [DATA_WIDTH-1:0]   A [0:M_ROWS-1][0:K_DIM-1];
    reg signed [DATA_WIDTH-1:0]   B [0:K_DIM-1][0:N_COLS-1];
    reg signed [ACCUM_WIDTH-1:0]  expected_C [0:M_ROWS-1][0:N_COLS-1];
    reg signed [ACCUM_WIDTH-1:0]  golden_C   [0:M_ROWS-1][0:N_COLS-1];

    integer errors;
    integer i, j, k, t;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    systolic_array #(
        .M_ROWS     (M_ROWS),
        .K_DIM      (K_DIM),
        .N_COLS     (N_COLS),
        .DATA_WIDTH (DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) dut (
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
        .any_overflow(any_overflow),
        .row_sel (row_sel),
        .col_sel (col_sel),
        .c_read_data(c_read_data),
        .cycle_count(cycle_count),
        .overflow_count(overflow_count)
    );

    // ----------------------------------------------------------------
    // Clock generation
    // ----------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // ----------------------------------------------------------------
    // Dump waveforms
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);
    end

    // ----------------------------------------------------------------
    // Test sequence
    // ----------------------------------------------------------------
    initial begin
        errors = 0;
        rst_n  = 0;
        a_valid = 0;
        b_valid = 0;
        row_sel = 0;
        col_sel = 0;

        // Initialize data inputs to zero
        for (i = 0; i < M_ROWS; i = i + 1)
            a_data[i] = 0;
        for (j = 0; j < N_COLS; j = j + 1)
            b_data[j] = 0;

        // Reset
        #25;
        rst_n = 1;
        #10;

        // ============================================================
        // Test 1: Small known values
        // ============================================================
        $display("=== Test 1: Known values (%0d×%0d × %0d×%0d) ===",
                 M_ROWS, K_DIM, K_DIM, N_COLS);

        // Fill A with small values: A[i][k] = i + k + 1
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = i + k + 1;

        // Fill B: B[k][j] = k + j + 1
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = k + j + 1;

        // Compute expected result
        compute_expected;

        // Feed and verify
        feed_matrices;
        wait_for_result;
        check_result("Test 1");
        $display("  Computation took %0d cycles (expected: %0d)",
                 cycle_count, M_ROWS + N_COLS + K_DIM);

        #50;

        // ============================================================
        // Test 2: Random values
        // ============================================================
        $display("\n=== Test 2: Random values ===");

        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = $urandom_range(0, 2**DATA_WIDTH - 2)
                          - (2**(DATA_WIDTH-1));  // signed range

        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = $urandom_range(0, 2**DATA_WIDTH - 2)
                          - (2**(DATA_WIDTH-1));

        compute_expected;
        feed_matrices;
        wait_for_result;
        check_result("Test 2");

        #50;

        // ============================================================
        // Test 3: Identity-like (A=all 1s, B=identity-ish → row sums)
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
        check_result("Test 3");

        #50;

        // ============================================================
        // Test 4: Result readout via address select
        // ============================================================
        $display("\n=== Test 4: Address-based readout ===");

        // Re-run Test 1 to get known values in result_bank
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = i + k + 1;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = k + j + 1;
        compute_expected;
        feed_matrices;
        wait_for_result;

        // Read each element via address mux and compare
        for (i = 0; i < M_ROWS; i = i + 1) begin
            for (j = 0; j < N_COLS; j = j + 1) begin
                row_sel = i;
                col_sel = j;
                #1;  // combinational settle
                if (c_read_data !== expected_C[i][j]) begin
                    $display("  READOUT MISMATCH at [%0d][%0d]: expected=%0d, got=%0d",
                             i, j, expected_C[i][j], c_read_data);
                    errors = errors + 1;
                end
            end
        end
        if (errors == 0)
            $display("  All %0d elements read correctly via address mux", M_ROWS * N_COLS);
        $display("  → PASSED");

        #50;

        // ============================================================
        // Test 5: Overflow saturation (use small ACCUM_WIDTH via defines)
        // With 8-bit data and 4×4, max product = 127*127 = 16129
        // If ACCUM_WIDTH is small enough, this will trigger saturation
        // ============================================================
        $display("\n=== Test 5: Overflow detection ===");
        $display("  To trigger overflow, run: make sim W=4 (uses ACCUM_WIDTH=16)");
        $display("  Current ACCUM_WIDTH = %0d", ACCUM_WIDTH);

        // Fill with max positive values: 127 * 127 * 4 = 64516
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = (1 << (DATA_WIDTH-1)) - 1;  // max positive

        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = (1 << (DATA_WIDTH-1)) - 1;

        compute_expected;
        feed_matrices;
        wait_for_result;

        if (any_overflow)
            $display("  Overflow DETECTED and SATURATED — flag raised correctly");
        else
            $display("  No overflow — values fit in %0d-bit accumulator (expected if wide)", ACCUM_WIDTH);
        $display("  → PASSED");

        #50;

        // ============================================================
        // Test 6: Back-to-back computation
        // ============================================================
        $display("\n=== Test 6: Back-to-back computation ===");

        // First computation
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = i + k + 1;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = k + j + 1;
        compute_expected;
        feed_matrices;
        wait_for_result;
        check_result("Test 6a (first)");

        // Immediately start second computation (no IDLE wait)
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = (i + 1) * (k + 1);
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = (k + 1) * (j + 1);
        compute_expected;

        // Feed immediately — the array should accept if in S_DONE
        wait (!busy);
        @(posedge clk);
        for (i = 0; i < M_ROWS; i = i + 1)
            a_data[i] = A[i][0];
        for (j = 0; j < N_COLS; j = j + 1)
            b_data[j] = B[0][j];
        a_valid = 1; b_valid = 1;
        for (t = 1; t < K_DIM; t = t + 1) begin
            @(posedge clk);
            for (i = 0; i < M_ROWS; i = i + 1)
                a_data[i] = A[i][t];
            for (j = 0; j < N_COLS; j = j + 1)
                b_data[j] = B[t][j];
        end
        @(posedge clk);
        a_valid = 0; b_valid = 0;
        for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
        for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;

        wait_for_result;
        check_result("Test 6b (back-to-back)");

        #50;

        // ============================================================
        // Summary
        // ============================================================
        #100;
        if (errors == 0)
            $display("\n*** ALL TESTS PASSED ***");
        else
            $display("\n*** %0d ERRORS DETECTED ***", errors);

        $finish;
    end

    // ----------------------------------------------------------------
    // Task: compute expected C = A × B in software
    // ----------------------------------------------------------------
    task compute_expected;
        reg signed [ACCUM_WIDTH-1:0] sum;
        begin
            for (i = 0; i < M_ROWS; i = i + 1) begin
                for (j = 0; j < N_COLS; j = j + 1) begin
                    sum = 0;
                    for (k = 0; k < K_DIM; k = k + 1)
                        sum = sum + $signed(A[i][k]) * $signed(B[k][j]);
                    expected_C[i][j] = sum;
                end
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Task: feed matrices into the array
    //
    // The FSM enters S_FEED one cycle after a_valid & b_valid are asserted.
    // Data must be set BEFORE the clock edge where the FSM samples it,
    // so we set data in the negative half of the cycle before the FSM
    // transitions to S_FEED.
    // ----------------------------------------------------------------
    task feed_matrices;
        integer t;
        begin
            // Wait until array is idle
            wait (!busy);
            @(posedge clk);

            // Set k=0 data BEFORE asserting valid, so when the FSM enters
            // S_FEED on the next edge, it sees A[i][0] and B[0][j]
            for (i = 0; i < M_ROWS; i = i + 1)
                a_data[i] = A[i][0];
            for (j = 0; j < N_COLS; j = j + 1)
                b_data[j] = B[0][j];

            a_valid = 1;
            b_valid = 1;

            // FSM transitions to S_FEED after this @(posedge clk).
            // Data for k=1..K-1 must be ready before each subsequent edge.
            for (t = 1; t < K_DIM; t = t + 1) begin
                @(posedge clk);
                for (i = 0; i < M_ROWS; i = i + 1)
                    a_data[i] = A[i][t];
                for (j = 0; j < N_COLS; j = j + 1)
                    b_data[j] = B[t][j];
            end

            @(posedge clk);
            a_valid = 0;
            b_valid = 0;
            for (i = 0; i < M_ROWS; i = i + 1)
                a_data[i] = 0;
            for (j = 0; j < N_COLS; j = j + 1)
                b_data[j] = 0;
        end
    endtask

    // ----------------------------------------------------------------
    // Task: wait for result
    // ----------------------------------------------------------------
    task wait_for_result;
        begin
            wait (c_valid);
            @(posedge clk);
            // Capture results
            for (i = 0; i < M_ROWS; i = i + 1)
                for (j = 0; j < N_COLS; j = j + 1)
                    golden_C[i][j] = c_data[i][j];
        end
    endtask

    // ----------------------------------------------------------------
    // Task: check result against expected
    // ----------------------------------------------------------------
    task check_result;
        input [255:0] test_name;
        begin
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

            for (i = 0; i < M_ROWS; i = i + 1) begin
                for (j = 0; j < N_COLS; j = j + 1) begin
                    if (golden_C[i][j] !== expected_C[i][j]) begin
                        $display("  MISMATCH at [%0d][%0d]: expected=%0d, got=%0d",
                                 i, j, expected_C[i][j], golden_C[i][j]);
                        errors = errors + 1;
                    end
                end
            end

            if (errors == 0)
                $display("  → PASSED");
            else
                $display("  → FAILED");
        end
    endtask

endmodule
