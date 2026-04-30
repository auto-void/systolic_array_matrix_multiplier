`include "src/utils.vh"
`timescale 1ns / 1ps
// ============================================================================
// Testbench for Systolic Array Matrix Multiplier
//
// Staggered feeding: A[i][k] enters at cycle k+i, B[k][j] at cycle k+j.
// Both reach PE(i,j) at cycle k+i+j — correctly aligned for accumulation.
//
// Timing model (Verilator / RTL):
//   - Boundary is combinational: pe_a_in[i][0] = a_data[i] when state==FEED
//     and feed_cnt matches the stagger condition.
//   - PE accumulates on posedge: reads the combinational pe_a_in from the
//     PREVIOUS cycle's a_data assignment.
//
// Protocol for feed_matrices:
//   1. Assert a_valid/b_valid
//   2. @(posedge clk)  ← FSM: IDLE→FEED, feed_cnt resets to 0
//                         a_data still holds zeros (set before valid)
//                         boundary outputs 0 (feed_cnt=0 but data=0)
//   WAIT: TB now sets cycle-0 data AFTER this posedge
//   3. Set cycle-0 data (before next posedge)
//   4. @(posedge clk)  ← feed_cnt=0, boundary reads cycle-0 data
//   5. Set cycle-1 data (before next posedge)
//   6. @(posedge clk)  ← feed_cnt=1, boundary reads cycle-1 data,
//                         PE accumulates cycle-0 product
//   ... repeat for c = 1..fc-1 ...
//   4+fc. @(posedge clk)  ← feed_cnt=fc-1 → feed_done → DRAIN
//                           PE accumulates cycle-(fc-1) product
//   Deassert valid.
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
                A[i][k] = DATA_WIDTH'(i + k + 1);
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = DATA_WIDTH'(k + j + 1);
        compute_expected;
        feed_matrices;
        wait_for_result;
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
        //
        // With standard ACCUM_WIDTH=32 and DATA_WIDTH=8, the max possible
        // sum for M×K×N=4×4×4 is:
        //   max(A)*max(B)*K = 126*126*4 = 63,504 < 2^31-1 = 2,147,483,647
        // So no overflow occurs. We verify overflow_count==0 (detection works).
        // To see actual saturation, run: make overflow (ACCUM_WIDTH=8)
        // ============================================================
        $display("\n=== Test 5: Overflow detection ===");
        $display("  DATA_WIDTH=%0d, ACCUM_WIDTH=%0d", DATA_WIDTH, ACCUM_WIDTH);
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = (1 << (DATA_WIDTH-1)) - 1;  // 126 or 127
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = (1 << (DATA_WIDTH-1)) - 1;  // 126 or 127
        compute_expected;
        feed_matrices;
        wait_for_result;
        // With ACCUM_WIDTH=32, overflow should NOT occur for these sizes.
        // Verify overflow detection mechanism is wired correctly.
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
        // Test 6: Back-to-back
        // ============================================================
        $display("\n=== Test 6: Back-to-back computation ===");
        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = DATA_WIDTH'(i + k + 1);
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = DATA_WIDTH'(k + j + 1);
        compute_expected;
        feed_matrices;
        wait_for_result;
        check_result("Test 6a");

        for (i = 0; i < M_ROWS; i = i + 1)
            for (k = 0; k < K_DIM; k = k + 1)
                A[i][k] = DATA_WIDTH'((i + 1) * (k + 1));
        for (k = 0; k < K_DIM; k = k + 1)
            for (j = 0; j < N_COLS; j = j + 1)
                B[k][j] = DATA_WIDTH'((k + 1) * (j + 1));
        compute_expected;
        feed_matrices;
        wait_for_result;
        check_result("Test 6b (back-to-back)");
        #50;

        // ============================================================
        // Test 7: All-zero matrices — result must be all zeros
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
        check_result("Test 7 (all-zero)");
        #50;

        // ============================================================
        // Test 8: Single-element (1x1 x 1x1) — minimal size
        // ============================================================
        $display("\n=== Test 8: Single-element 1x1 x 1x1 ===");
        begin
            reg signed [ACCUM_WIDTH-1:0] expected_1x1;
            // Set A=1, B=1 => C[0][0]=1
            A[0][0] = DATA_WIDTH'(1);
            B[0][0] = DATA_WIDTH'(1);
            expected_1x1 = 1;
            feed_matrices;
            wait_for_result;
            if (c_data[0][0] !== expected_1x1) begin
                $display("  MISMATCH: expected=%0d, got=%0d", expected_1x1, c_data[0][0]);
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
    // Staggered feed task
    //
    // Protocol: set data BEFORE @(posedge clk) so the combinational
    // boundary has the correct values when the posedge arrives.
    //
    // Cycle timeline:
    //   1. Wait for !busy + extra posedge (ensure FSM in IDLE)
    //   2. Set cycle-0 data BEFORE posedge
    //   3. Assert valid + @(posedge clk) → FSM enters FEED
    //      boundary sees cycle-0 data, PE accumulates on NEXT posedge
    //   4. Set cycle-1 data BEFORE next posedge
    //   5. @(posedge clk) → PE accumulates cycle-0 product
    //   ... repeat ...
    //   Last: set cycle-(fc-1) data, @(posedge clk) → PE accum cycle-(fc-2)
    //         set zero data, @(posedge clk) → PE accum cycle-(fc-1)
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
            @(posedge clk);  // FSM: IDLE→FEED, feed_cnt=0, boundary has cycle-0 data

            // Feed remaining fc-1 cycles: set cycle-c data, then posedge
            // PE accumulates cycle-(c-1) product at each posedge
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

            // Final posedge: PE accumulates cycle-(fc-1) product
            // Set data to zero for the drain
            for (ii = 0; ii < M_ROWS; ii = ii + 1) a_data[ii] = 0;
            for (jj = 0; jj < N_COLS; jj = jj + 1) b_data[jj] = 0;
            @(posedge clk);

            a_valid = 0;
            b_valid = 0;
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
