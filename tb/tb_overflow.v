`include "src/utils.vh"
`timescale 1ns / 1ps
// ============================================================================
// Overflow & Saturation Testbench
// Uses small ACCUM_WIDTH (8-bit) to guarantee overflow with 4-bit data.
// Verifies that PE saturates to MAX/MIN instead of wrapping.
//
// RTL timing: assert valid, @posedge (FSM enters FEED), then for each
// feed cycle c: set data, @posedge. Same protocol as tb_systolic_array.
// ============================================================================

module tb_overflow;

    parameter M_ROWS     = `ifdef M_ROWS     `M_ROWS     `else 2 `endif;
    parameter K_DIM      = `ifdef K_DIM      `K_DIM      `else 2 `endif;
    parameter N_COLS     = `ifdef N_COLS     `N_COLS     `else 2 `endif;
    parameter DATA_WIDTH = `ifdef DATA_WIDTH `DATA_WIDTH `else 4 `endif;
    parameter ACCUM_WIDTH = `ifdef ACCUM_WIDTH `ACCUM_WIDTH `else 8 `endif;

    reg                              clk, rst_n;
    reg  signed [DATA_WIDTH-1:0]     a_data [0:M_ROWS-1];
    reg                               a_valid;
    wire                              a_ready;
    reg  signed [DATA_WIDTH-1:0]     b_data [0:N_COLS-1];
    reg                               b_valid;
    wire                              b_ready;
    wire signed [ACCUM_WIDTH-1:0]    c_data [0:M_ROWS-1][0:N_COLS-1];
    wire                              c_valid, busy, any_overflow;

    reg  [`ADDR_WIDTH(M_ROWS)-1:0]        row_sel;
    reg  [`ADDR_WIDTH(N_COLS)-1:0]        col_sel;
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

    integer errors, i, j, c, feed_cycles;
    reg signed [ACCUM_WIDTH-1:0] expected;

    initial begin
        `ifdef DUMP
        $dumpfile("overflow.vcd");
        $dumpvars(0, tb_overflow);
        `endif

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
        // C[0][0] = (-8)*(-8) + (-8)*(-8) = 64+64 = 128 -> saturate to 127
        // ============================================================
        $display("=== Positive overflow (saturation to MAX) ===");
        $display("  DATA_WIDTH=%0d, ACCUM_WIDTH=%0d", DATA_WIDTH, ACCUM_WIDTH);
        $display("  Max accum = %0d", (1 << (ACCUM_WIDTH-1)) - 1);

        feed_cycles = K_DIM + M_ROWS + N_COLS - 2;  // 4

        // Protocol: pre-set cycle-0 data, assert valid, @posedge (FSM enters FEED)
        // then for each remaining cycle: set data, @posedge
        wait (!busy);
        @(posedge clk);  // ensure we are in IDLE (not DONE)

        // Pre-set cycle-0 data BEFORE asserting valid
        for (i = 0; i < M_ROWS; i = i + 1) begin
            if (0 >= i && (0 - i) < K_DIM)
                a_data[i] = -8;
            else
                a_data[i] = 0;
        end
        for (j = 0; j < N_COLS; j = j + 1) begin
            if (0 >= j && (0 - j) < K_DIM)
                b_data[j] = -8;
            else
                b_data[j] = 0;
        end

        a_valid = 1; b_valid = 1;
        @(posedge clk);  // FSM: IDLE->FEED, feed_cnt=0, boundary has cycle-0 data

        for (c = 1; c < feed_cycles; c = c + 1) begin
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

        // Final posedge: PE accumulates last cycle's product
        for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
        for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;
        @(posedge clk);

        a_valid = 0; b_valid = 0;

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
        if (!any_overflow) begin
            $display("  ERROR: overflow flag not raised!");
            errors = errors + 1;
        end else begin
            $display("  Overflow flag correctly raised (count=%0d/%0d PEs overflowed)",
                     overflow_count, M_ROWS * N_COLS);
        end

        #50;

        // ============================================================
        // Test: Negative overflow saturation
        // Use A=-8, B=7 for all elements. Each product = -56.
        // Sum over K_DIM products = -56 * K_DIM.
        // Triggers negative overflow when -56*K_DIM < -128 (i.e. K_DIM >= 3).
        // ============================================================
        $display("\n=== Negative overflow (saturation to MIN) ===");
        $display("  DATA_WIDTH=%0d, K_DIM=%0d, ACCUM_WIDTH=%0d", DATA_WIDTH, K_DIM, ACCUM_WIDTH);

        if (K_DIM < 3) begin
            $display("  K_DIM=%0d too small for negative overflow (need >=3) -- skipping", K_DIM);
        end else begin
            $display("  Expected sum = (-8)*7 * %0d = %0d (should saturate to -128)",
                     K_DIM, (-8)*7*K_DIM);

            feed_cycles = K_DIM + M_ROWS + N_COLS - 2;

            wait (!busy);
            @(posedge clk);

            // Pre-set cycle-0 data: A=-8, B=7
            for (i = 0; i < M_ROWS; i = i + 1)
                a_data[i] = (0 >= i && (0 - i) < K_DIM) ? -8 : 0;
            for (j = 0; j < N_COLS; j = j + 1)
                b_data[j] = (0 >= j && (0 - j) < K_DIM) ? 7 : 0;

            a_valid = 1; b_valid = 1;
            @(posedge clk);

            for (c = 1; c < feed_cycles; c = c + 1) begin
                for (i = 0; i < M_ROWS; i = i + 1)
                    a_data[i] = (c >= i && (c - i) < K_DIM) ? -8 : 0;
                for (j = 0; j < N_COLS; j = j + 1)
                    b_data[j] = (c >= j && (c - j) < K_DIM) ? 7 : 0;
                @(posedge clk);
            end
            // Final posedge
            for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
            for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;
            @(posedge clk);

            a_valid = 0; b_valid = 0;

            wait (c_valid); @(posedge clk);

            expected = -(1 << (ACCUM_WIDTH-1));  // -128 (saturated MIN)
            $display("  Expected C = %0d (saturated MIN)", expected);
            for (i = 0; i < M_ROWS; i = i + 1)
                for (j = 0; j < N_COLS; j = j + 1) begin
                    $display("  C[%0d][%0d] = %0d, overflow = %0d",
                             i, j, c_data[i][j], any_overflow);
                    if (c_data[i][j] !== expected) begin
                        $display("  MISMATCH: expected %0d, got %0d", expected, c_data[i][j]);
                        errors = errors + 1;
                    end
                end
            if (!any_overflow) begin
                $display("  ERROR: overflow flag not raised!");
                errors = errors + 1;
            end else begin
                $display("  Overflow flag correctly raised (count=%0d/%0d PEs overflowed)",
                         overflow_count, M_ROWS * N_COLS);
            end
        end

        // ============================================================
        #100;
        if (errors == 0)
            $display("\n*** ALL OVERFLOW TESTS PASSED ***");
        else
            $display("\n*** %0d ERRORS ***", errors);
        $finish;
    end

endmodule
