`include "src/utils.vh"
`timescale 1ns / 1ps
// Targeted bug verification tests
module tb_bug_verify;

    parameter M_ROWS     = 2;
    parameter K_DIM      = 2;
    parameter N_COLS     = 2;
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

    integer errors;
    integer i, j, k, c, fc;

    // Test matrices: A=[[1,2],[3,4]], B=[[5,6],[7,8]]
    // C = [[1*5+2*7, 1*6+2*8], [3*5+4*7, 3*6+4*8]]
    //   = [[19, 22], [43, 50]]
    reg signed [DATA_WIDTH-1:0] A1 [0:M_ROWS-1][0:K_DIM-1];
    reg signed [DATA_WIDTH-1:0] B1 [0:K_DIM-1][0:N_COLS-1];
    reg signed [DATA_WIDTH-1:0] A2 [0:M_ROWS-1][0:K_DIM-1];
    reg signed [DATA_WIDTH-1:0] B2 [0:K_DIM-1][0:N_COLS-1];

    initial begin
        $dumpfile("bug_verify.vcd");
        $dumpvars(0, tb_bug_verify);

        errors = 0;
        rst_n = 0;
        a_valid = 0; b_valid = 0;
        row_sel = 0; col_sel = 0;
        for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
        for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;

        // Matrices for test 1
        A1[0][0] = 1; A1[0][1] = 2; A1[1][0] = 3; A1[1][1] = 4;
        B1[0][0] = 5; B1[0][1] = 6; B1[1][0] = 7; B1[1][1] = 8;

        // Matrices for test 2
        A2[0][0] = 10; A2[0][1] = 20; A2[1][0] = 30; A2[1][1] = 40;
        B2[0][0] = 1;  B2[0][1] = 2;  B2[1][0] = 3;  B2[1][1] = 4;
        // C2 = [[70, 80], [150, 180]]

        #25; rst_n = 1; #10;
        fc = K_DIM + M_ROWS + N_COLS - 2;  // 4

        // =================================================================
        // BUG TEST 1: Back-to-back without IDLE gap
        // Feed second computation immediately after DONE, skipping IDLE.
        // If clear_acc bug exists, second result will be contaminated.
        // =================================================================
        $display("=== BUG TEST 1: Back-to-back without IDLE (clear_acc test) ===");

        // First computation
        wait (!busy); @(posedge clk);
        a_valid = 1; b_valid = 1;
        @(posedge clk);
        for (c = 0; c < fc; c = c + 1) begin
            for (i = 0; i < M_ROWS; i = i + 1)
                a_data[i] = (c >= i && (c - i) < K_DIM) ? A1[i][c - i] : 0;
            for (j = 0; j < N_COLS; j = j + 1)
                b_data[j] = (c >= j && (c - j) < K_DIM) ? B1[c - j][j] : 0;
            @(posedge clk);
        end
        a_valid = 0; b_valid = 0;
        for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
        for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;

        // Wait for result
        wait (c_valid); @(posedge clk);
        $display("  Result 1: C[0][0]=%0d (expect 19), C[0][1]=%0d (expect 22), C[1][0]=%0d (expect 43), C[1][1]=%0d (expect 50)",
                 c_data[0][0], c_data[0][1], c_data[1][0], c_data[1][1]);

        // Now: FSM will go to DONE. We want to start second computation
        // WITHOUT waiting for IDLE (no clear_acc gap).
        // Wait until state == DONE (busy==0, but NOT going through IDLE)
        wait (!busy);
        // DON'T add extra @(posedge clk) — start immediately while FSM is in DONE
        // This is the "true back-to-back" scenario

        // Feed second computation IMMEDIATELY
        a_valid = 1; b_valid = 1;
        @(posedge clk);  // FSM: DONE→FEED (skipping IDLE!)
        for (c = 0; c < fc; c = c + 1) begin
            for (i = 0; i < M_ROWS; i = i + 1)
                a_data[i] = (c >= i && (c - i) < K_DIM) ? A2[i][c - i] : 0;
            for (j = 0; j < N_COLS; j = j + 1)
                b_data[j] = (c >= j && (c - j) < K_DIM) ? B2[c - j][j] : 0;
            @(posedge clk);
        end
        a_valid = 0; b_valid = 0;
        for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
        for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;

        wait (c_valid); @(posedge clk);
        $display("  Result 2: C[0][0]=%0d (expect 70), C[0][1]=%0d (expect 80), C[1][0]=%0d (expect 150), C[1][1]=%0d (expect 180)",
                 c_data[0][0], c_data[0][1], c_data[1][0], c_data[1][1]);

        if (c_data[0][0] !== 32'sd70 || c_data[0][1] !== 32'sd80 ||
            c_data[1][0] !== 32'sd150 || c_data[1][1] !== 32'sd180) begin
            $display("  ✗ BUG CONFIRMED: Back-to-back contamination! Second result includes first result's accumulation.");
            $display("    Expected [70,80;150,180], got [%0d,%0d;%0d,%0d]",
                     c_data[0][0], c_data[0][1], c_data[1][0], c_data[1][1]);
            errors = errors + 1;
        end else begin
            $display("  ✓ Back-to-back results are clean (no contamination)");
        end
        #100;

        // =================================================================
        // BUG TEST 2: Random value range — does TB ever generate 127?
        // =================================================================
        $display("\n=== BUG TEST 2: Random value generation range ===");
        begin
            integer saw_max, saw_min, val;
            saw_max = 0; saw_min = 0;
            for (i = 0; i < 10000; i = i + 1) begin
                val = $urandom_range(0, 2**DATA_WIDTH - 2) - (2**(DATA_WIDTH-1));
                if (val == 127) saw_max = 1;
                if (val == -128) saw_min = 1;
            end
            if (!saw_max) begin
                $display("  ✗ BUG: $urandom_range(0,254)-128 never generates 127 (max is 126)");
                $display("    Fix: use $urandom_range(0, 2**DATA_WIDTH-1) - (2**(DATA_WIDTH-1))");
                errors = errors + 1;
            end else begin
                $display("  ✓ Random range includes 127");
            end
            if (!saw_min) begin
                $display("  ✗ BUG: Never generates -128");
                errors = errors + 1;
            end else begin
                $display("  ✓ Random range includes -128");
            end
        end
        #50;

        // =================================================================
        // BUG TEST 3: Negative values in multiplication
        // A=[[-1,-2],[3,4]], B=[[5,-6],[-7,8]]
        // C[0][0] = (-1)*5 + (-2)*(-7) = -5+14 = 9
        // C[0][1] = (-1)*(-6) + (-2)*8 = 6-16 = -10
        // C[1][0] = 3*5 + 4*(-7) = 15-28 = -13
        // C[1][1] = 3*(-6) + 4*8 = -18+32 = 14
        // =================================================================
        $display("\n=== BUG TEST 3: Negative value multiplication ===");
        begin
            reg signed [DATA_WIDTH-1:0] A3 [0:1][0:1];
            reg signed [DATA_WIDTH-1:0] B3 [0:1][0:1];
            A3[0][0] = -1; A3[0][1] = -2; A3[1][0] = 3; A3[1][1] = 4;
            B3[0][0] = 5;  B3[0][1] = -6; B3[1][0] = -7; B3[1][1] = 8;

            wait (!busy); @(posedge clk);
            a_valid = 1; b_valid = 1;
            @(posedge clk);
            for (c = 0; c < fc; c = c + 1) begin
                for (i = 0; i < M_ROWS; i = i + 1)
                    a_data[i] = (c >= i && (c - i) < K_DIM) ? A3[i][c - i] : 0;
                for (j = 0; j < N_COLS; j = j + 1)
                    b_data[j] = (c >= j && (c - j) < K_DIM) ? B3[c - j][j] : 0;
                @(posedge clk);
            end
            a_valid = 0; b_valid = 0;
            for (i = 0; i < M_ROWS; i = i + 1) a_data[i] = 0;
            for (j = 0; j < N_COLS; j = j + 1) b_data[j] = 0;

            wait (c_valid); @(posedge clk);
            $display("  C[0][0]=%0d (expect 9), C[0][1]=%0d (expect -10)", c_data[0][0], c_data[0][1]);
            $display("  C[1][0]=%0d (expect -13), C[1][1]=%0d (expect 14)", c_data[1][0], c_data[1][1]);

            if (c_data[0][0] !== 9 || c_data[0][1] !== -10 ||
                c_data[1][0] !== -13 || c_data[1][1] !== 14) begin
                $display("  ✗ FAILED: Negative multiplication results incorrect");
                errors = errors + 1;
            end else begin
                $display("  ✓ Negative multiplication correct");
            end
        end
        #100;

        // =================================================================
        // BUG TEST 4: c_data stability after DONE (accumulator clearing)
        // After FSM enters DONE, clear_acc=1 zeros the accumulators.
        // c_data (wire from accum) goes to 0, but result_bank should hold.
        // =================================================================
        $display("\n=== BUG TEST 4: c_data vs result_bank after DONE ===");
        begin
            // Use the last result (from test 3)
            // After c_valid, FSM goes to DONE, then IDLE
            // In DONE state, clear_acc=1, accumulators get cleared
            // c_data should become 0, but c_read_data (from result_bank) should hold

            // Wait for FSM to settle in IDLE
            wait (!busy); #20;

            // Check result_bank via address readout
            row_sel = 0; col_sel = 0; #1;
            $display("  result_bank[0][0] via c_read_data = %0d (expect 9 from test 3)", c_read_data);
            if (c_read_data !== 9) begin
                $display("  ✗ FAILED: result_bank lost value after DONE→IDLE");
                errors = errors + 1;
            end else begin
                $display("  ✓ result_bank preserves value correctly");
            end

            // Check c_data (should be 0 since accumulators cleared in IDLE)
            $display("  c_data[0][0] direct = %0d (expect 0 since accum cleared in IDLE)", c_data[0][0]);
            if (c_data[0][0] !== 0) begin
                $display("  ✗ WARNING: c_data[0][0] not zero in IDLE (clear_acc may not be working)");
                errors = errors + 1;
            end else begin
                $display("  ✓ Accumulators correctly cleared in IDLE state");
            end
        end
        #100;

        // =================================================================
        // Summary
        // =================================================================
        #100;
        if (errors == 0)
            $display("\n*** ALL BUG TESTS PASSED (no bugs found) ***");
        else
            $display("\n*** %0d BUG(S) CONFIRMED ***", errors);
        $finish;
    end

endmodule
