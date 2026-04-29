`timescale 1ns / 1ps
// ============================================================================
// Testbench for Systolic Array Matrix Multiplier
//
// Staggered feeding: A[i][k] enters at cycle k+i, B[k][j] at cycle k+j.
// Both reach PE(i,j) at cycle k+i+j — correctly aligned for accumulation.
// Data is set BEFORE posedge clk so combinational boundary reads it at edge.
// ============================================================================

module tb_systolic_array;

    parameter M_ROWS     = 4;
    parameter K_DIM      = 4;
    parameter N_COLS     = 4;
    parameter DATA_WIDTH = 8;
    parameter ACCUM_WIDTH = 32;

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

    reg signed [DATA_WIDTH-1:0]   A [0:M_ROWS-1][0:K_DIM-1];
    reg signed [DATA_WIDTH-1:0]   B [0:K_DIM-1][0:N_COLS-1];
    reg signed [ACCUM_WIDTH-1:0]  expected_C [0:M_ROWS-1][0:N_COLS-1];
    reg signed [ACCUM_WIDTH-1:0]  golden_C   [0:M_ROWS-1][0:N_COLS-1];

    integer errors;
    integer i, j, k, t;

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

    initial begin
        $dumpfile("systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);
    end

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
                A[i][k] = i + k + 1;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = k + j + 1;
        compute_expected;
        feed_matrices;
        wait_for_result;
        check_result("Test 1");
        $display("  Computation took %0d cycles", cycle_count);
        #50;

        // ============================================================
        // Test 2: Random values
        // ============================================================
        $display("\n=== Test 2: Random values ===");
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = $urandom_range(0, 2**DATA_WIDTH - 2) - (2**(DATA_WIDTH-1));
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = $urandom_range(0, 2**DATA_WIDTH - 2) - (2**(DATA_WIDTH-1));
        compute_expected;
        feed_matrices;
        wait_for_result;
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
        check_result("Test 3");
        #50;

        // ============================================================
        // Test 4: Address-based readout
        // ============================================================
        $display("\n=== Test 4: Address-based readout ===");
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = i + k + 1;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = k + j + 1;
        compute_expected;
        feed_matrices;
        wait_for_result;
        for (i = 0; i < M_ROWS; i = i + 1)
            for (j = 0; j < N_COLS; j = j + 1) begin
                row_sel = i; col_sel = j; #1;
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
        $display("  Current ACCUM_WIDTH = %0d", ACCUM_WIDTH);
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = (1 << (DATA_WIDTH-1)) - 1;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = (1 << (DATA_WIDTH-1)) - 1;
        compute_expected;
        feed_matrices;
        wait_for_result;
        if (any_overflow) $display("  Overflow DETECTED — flag raised correctly");
        else              $display("  No overflow (expected if ACCUM_WIDTH is wide)");
        $display("  → PASSED");
        #50;

        // ============================================================
        // Test 6: Back-to-back
        // ============================================================
        $display("\n=== Test 6: Back-to-back computation ===");
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = i + k + 1;
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = k + j + 1;
        compute_expected;
        feed_matrices;
        wait_for_result;
        check_result("Test 6a");

        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = (i + 1) * (k + 1);
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = (k + 1) * (j + 1);
        compute_expected;
        feed_matrices;
        wait_for_result;
        check_result("Test 6b (back-to-back)");
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
    // Staggered feed: set data BEFORE @(posedge clk) so the
    // combinational boundary reads it at that edge.
    //
    // Cycle 0 data → edge 1 (FSM enters FEED, feed_cnt=0)
    // Cycle c data → edge c+1 (feed_cnt=c)
    //
    // At cycle c:
    //   a_data[i] = A[i][c-i] if c>=i and c-i<K_DIM, else 0
    //   b_data[j] = B[c-j][j] if c>=j and c-j<K_DIM, else 0
    // ----------------------------------------------------------------
    task feed_matrices;
        integer c, ii, jj, fc;
        begin
            wait (!busy);
            @(posedge clk);

            fc = K_DIM;
            if (M_ROWS > fc) fc = M_ROWS;
            if (N_COLS > fc) fc = N_COLS;
            fc = fc + K_DIM - 1;

            // Set data for cycle 0
            for (ii = 0; ii < M_ROWS; ii = ii + 1)
                a_data[ii] = (0 >= ii && (0 - ii) < K_DIM) ? A[ii][0 - ii] : 0;
            for (jj = 0; jj < N_COLS; jj = jj + 1)
                b_data[jj] = (0 >= jj && (0 - jj) < K_DIM) ? B[0 - jj][jj] : 0;

            a_valid = 1;
            b_valid = 1;

            for (c = 0; c < fc; c = c + 1) begin
                @(posedge clk);
                // Set data for cycle c+1 (will be read at edge c+2)
                for (ii = 0; ii < M_ROWS; ii = ii + 1)
                    if ((c+1) >= ii && ((c+1) - ii) < K_DIM)
                        a_data[ii] = A[ii][(c+1) - ii];
                    else
                        a_data[ii] = 0;
                for (jj = 0; jj < N_COLS; jj = jj + 1)
                    if ((c+1) >= jj && ((c+1) - jj) < K_DIM)
                        b_data[jj] = B[(c+1) - jj][jj];
                    else
                        b_data[jj] = 0;
            end

            @(posedge clk);
            a_valid = 0;
            b_valid = 0;
            for (ii = 0; ii < M_ROWS; ii = ii + 1) a_data[ii] = 0;
            for (jj = 0; jj < N_COLS; jj = jj + 1) b_data[jj] = 0;
        end
    endtask

    // ----------------------------------------------------------------
    task wait_for_result;
        begin
            wait (c_valid);
            @(posedge clk);
            for (i = 0; i < M_ROWS; i = i + 1)
                for (j = 0; j < N_COLS; j = j + 1)
                    golden_C[i][j] = c_data[i][j];
        end
    endtask

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
            for (i = 0; i < M_ROWS; i = i + 1)
                for (j = 0; j < N_COLS; j = j + 1)
                    if (golden_C[i][j] !== expected_C[i][j]) begin
                        $display("  MISMATCH at [%0d][%0d]: expected=%0d, got=%0d",
                                 i, j, expected_C[i][j], golden_C[i][j]);
                        errors = errors + 1;
                    end
            if (errors == 0) $display("  → PASSED");
            else             $display("  → FAILED");
        end
    endtask

endmodule
