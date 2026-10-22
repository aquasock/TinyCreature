// SPDX-License-Identifier: GPL-3.0-or-later
// fpga/raster.sv's nearcut against terrain.c's crossing, (int64)a * b / d
// truncated toward zero, over every sign combination, the extremes, the
// ranges the near clip produces and random operands whose quotient fits.
`timescale 1ns/1ps
module nearcut_tb;
    reg clk = 0, resetn = 0;
    always #5 clk = !clk;
    reg start = 0;
    reg signed [31:0] a = 0, b = 0, d = 1;
    wire signed [31:0] q;
    wire done;
    nearcut dut(.clk(clk), .resetn(resetn), .start(start),
                .a(a), .b(b), .d(d), .q(q), .done(done));

    integer errors = 0, cases = 0, skipped = 0, longest = 0;

    task automatic check(input signed [31:0] ta, tb, td);
        reg signed [63:0] p, want;
        integer guard;
        begin
            p = 64'(ta) * 64'(tb);
            want = p / 64'(td);
            // The crossing's quotient fits in 32 bits; a case that does not
            // is outside the unit's contract and is not run.
            if (want > 64'sh7fffffff || want < -64'sh80000000)
                skipped = skipped + 1;
            else begin
                @(negedge clk);
                a = ta; b = tb; d = td; start = 1;
                @(negedge clk);
                start = 0;
                guard = 0;
                while (!done && guard < 100) begin
                    @(negedge clk);
                    guard = guard + 1;
                end
                if (guard > longest) longest = guard;
                if (!done || q !== want[31:0]) begin
                    if (errors < 8)
                        $display("FAIL: %0d * %0d / %0d: %0d, want %0d",
                                 ta, tb, td, q, want);
                    errors = errors + 1;
                end
                cases = cases + 1;
            end
        end
    endtask

    integer i, s;
    reg signed [31:0] za, zb, ra, rb, rd;
    initial begin
        repeat (3) @(posedge clk);
        resetn = 1;
        // Every sign combination, and exact and inexact quotients.
        for (s = 0; s < 8; s = s + 1) begin
            check(s[0] ? -7 : 7, s[1] ? -5 : 5, s[2] ? -3 : 3);
            check(s[0] ? -9 : 9, s[1] ? -4 : 4, s[2] ? -6 : 6);
            check(s[0] ? -1000 : 1000, s[1] ? -128 : 128, s[2] ? -128 : 128);
        end
        check(0, 5, 3); check(5, 0, -3); check(0, 0, 1);
        // The extremes of the operands.
        check(32'sh80000000, 1, 1);
        check(32'sh80000000, -1, -1);
        check(32'sh7fffffff, 32'sh7fffffff, 32'sh7fffffff);
        check(32'sh80000000, 32'sh80000000, 32'sh80000000);
        check(32'sh80000000, 32'sh7fffffff, 32'sh80000000);
        check(32'sh7fffffff, -32'sh7fffffff, 32'sh80000000);
        check(1, 32'sh7fffffff, 32'sh80000000);
        check(-1, 32'sh7fffffff, 32'sh80000000);
        // Crossings as the clip makes them: z[i] and z[j] either side of
        // NEAR, a and b the coordinate span and NEAR - z[i], d the z span.
        for (i = 0; i < 20000; i = i + 1) begin
            za = $signed($urandom % 32'h80000) - 32'sh40000;
            zb = $signed($urandom % 32'h80000) - 32'sh40000;
            if ((za >= 128) != (zb >= 128)) begin
                ra = $signed($urandom % 32'h100000) - 32'sh80000;
                check(ra, 32'sd128 - za, zb - za);
            end
        end
        // Random operands of every width.
        for (i = 0; i < 20000; i = i + 1) begin
            ra = $urandom >> ($urandom % 32);
            rb = $urandom >> ($urandom % 32);
            rd = $urandom >> ($urandom % 32);
            if ($urandom & 1) ra = -ra;
            if ($urandom & 1) rb = -rb;
            if ($urandom & 1) rd = -rd;
            if (rd == 0) rd = 1;
            check(ra, rb, rd);
        end
        $display("nearcut: %0d cases, %0d outside the contract, %0d clocks",
                 cases, skipped, longest + 1);
        if (errors == 0) $display("PASS nearcut_tb");
        else $display("FAIL nearcut_tb: %0d errors", errors);
        $finish;
    end
endmodule
