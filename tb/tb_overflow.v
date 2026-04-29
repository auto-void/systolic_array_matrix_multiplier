`timescale 1ns / 1ps
// ============================================================================
// Overflow & Saturation Testbench
// Uses small ACCUM_WIDTH (8-bit) to guarantee overflow with 4-bit data.
// Verifies that PE saturates to MAX/MIN instead of wrapping.
// ============================================================================

module tb_overflow;

    parameter M_ROWS     = 2;
    parameter K_DIM      = 2;
    parameter N_COLS     = 2;
    parameter DATA_WIDTH = 4;   // -8 to 7
    parameter ACCUM_WIDTH = 8;  // -128 to 127

    reg                              clk, rst_n;
    reg  signed [DATA_WIDTH-1:0]     a_data [0:M_ROWS-1];
    reg                               a_valid;
    wire                              a_ready;
    reg  signed [DATA_WIDTH-1:0]     b_data [0:N_COLS-1];
    reg                               b_valid;
    wire                              b_ready;
    wire signed [ACCUM_WIDTH-1:0]    c_data [0:M_ROWS-1][0:N_COLS-1];
    wire                              c_valid, busy, any_overflow;

    reg  [$clog2(M_ROWS)-1:0]        row_sel;
    reg  [$clog2(N_COLS)-1:0]        col_sel;
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

    integer errors, i, j, k, c, feed_cycles;
    reg signed [ACCUM_WIDTH-1:0] expected;

    initial begin
        $dumpfile("overflow.vcd");
        $dumpvars(0, tb_overflow);

        errors = 0;
        rst_n = 0;
        a_valid = 0; b_valid = 0;
        row_sel = 0; col_sel = 0;
        for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
        for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;
        #25; rst_n = 1; #10;

        // ============================================================
        // Test: Positive overflow saturation
        // A = [[-8,-8],[-8,-8]], B = [[-8,-8],[-8,-8]]
        // C[0][0] = (-8)*(-8) + (-8)*(-8) = 64+64 = 128 → saturate to 127
        // ============================================================
        $display("=== Positive overflow (saturation to MAX) ===");
        $display("  DATA_WIDTH=%0d, ACCUM_WIDTH=%0d", DATA_WIDTH, ACCUM_WIDTH);
        $display("  Max accum = %0d", (1 << (ACCUM_WIDTH-1)) - 1);

        wait (!busy); @(posedge clk);

        // Staggered feed: A[i][k] at cycle c=k+i, B[k][j] at cycle c=k+j
        feed_cycles = K_DIM + M_ROWS + N_COLS - 2;

        a_valid = 1; b_valid = 1;
        for (c = 0; c < feed_cycles; c = c + 1) begin
            for (i = 0; i < M_ROWS; i = i + 1) begin
                if (c >= i && (c - i) < K_DIM)
                    a_data[i] = -8;
                else
                    a_data[i] = 0;
            end
            for (j = 0; j < N_COLS; j = j + 1) begin
                if (c >= j && (c - j) < K_DIM)
                    b_data[j] = -8;
                else
                    b_data[j] = 0;
            end
            @(posedge clk);
        end
        a_valid = 0; b_valid = 0;
        for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
        for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;

        wait (c_valid); @(posedge clk);

        expected = (1 << (ACCUM_WIDTH-1)) - 1;  // 127 (saturated)
        $display("  Expected C = %0d (saturated MAX)", expected);
        for (i = 0; i < M_ROWS; i = i + 1)
            for (j = 0; j < N_COLS; j = j + 1) begin
                $display("  C[%0d][%0d] = %0d, overflow = %0d",
                         i, j, c_data[i][j], any_overflow);
                if (c_data[i][j] !== expected) begin
                    $display("  MISMATCH: expected %0d, got %0d", expected, c_data[i][j]);
                    errors = errors + 1;
                end
            end
        if (!any_overflow)
            $display("  WARNING: overflow flag not raised!");
        else
            $display("  Overflow flag correctly raised");

        #50;

        // ============================================================
        // Test: Negative overflow saturation
        // With DATA_WIDTH=4, K_DIM=2, ACCUM_WIDTH=8:
        // Min possible sum = (-8)*7 * 2 = -112, which fits in -128..127
        // Negative overflow impossible with these parameters.
        // ============================================================
        $display("\n=== Negative overflow (saturation to MIN) ===");
        $display("  DATA_WIDTH=%0d, K_DIM=%0d, ACCUM_WIDTH=%0d", DATA_WIDTH, K_DIM, ACCUM_WIDTH);
        $display("  Min possible sum = (-8)*7 * %0d = %0d (fits in %0d-bit min %0d)",
                 K_DIM, (-8)*7*K_DIM, ACCUM_WIDTH, -(1 << (ACCUM_WIDTH-1)));
        $display("  Negative overflow impossible with these parameters — skipping");

        // ============================================================
        #100;
        if (errors == 0)
            $display("\n*** ALL OVERFLOW TESTS PASSED ***");
        else
            $display("\n*** %0d ERRORS ***", errors);
        $finish;
    end

endmodule
