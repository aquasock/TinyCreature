// SPDX-License-Identifier: GPL-3.0-or-later
// fpga/raster.sv against terrain_host's model: two frames' command words,
// pushed over the bus into the two buffers, must leave exactly the frames
// terrain_host drew, read back through the bus window and through the
// video line fetch. tools/test_tang32_raster.sh makes the files.
`timescale 1ns/1ps
module raster_tb;
    reg clk = 0, resetn = 0;
    always #6.667 clk = !clk;

    reg [14:0] haddr = 0;
    reg [1:0] htrans = 0;
    reg hsel = 0, hwrite = 0;
    reg [31:0] hwdata = 0;
    wire [31:0] hrdata;
    wire hready, hresp, show;
    reg vstart = 0;
    reg [24:9] vaddr = 0;
    wire vvalid, vdone;
    wire [7:0] vindex;
    wire [15:0] vdata;

    raster dut(.clk(clk), .resetn(resetn), .haddr(haddr), .htrans(htrans),
        .hsel(hsel), .hwrite(hwrite), .hsize(3'd2), .hwdata(hwdata),
        .hready_in(hready), .hrdata(hrdata), .hready(hready), .hresp(hresp),
        .show(show), .vstart(vstart), .vaddr(vaddr), .vvalid(vvalid),
        .vindex(vindex), .vdata(vdata), .vdone(vdone));

    integer errors = 0;

    // One AHB transfer: the address phase on the edge after hready is
    // seen high, the data phase until hready is seen high again.
    task automatic transfer(input [14:0] a, input w, input [31:0] d,
                            output [31:0] q);
        begin
            @(negedge clk);
            while (!hready) @(negedge clk);
            haddr = a; htrans = 2'b10; hsel = 1; hwrite = w;
            @(negedge clk);
            htrans = 0; hsel = 0; hwdata = d;
            while (!hready) @(negedge clk);
            if (hresp) begin
                $display("FAIL: error response at %h", a);
                errors = errors + 1;
            end
            q = hrdata;
        end
    endtask

    task automatic write(input [14:0] a, input [31:0] d);
        reg [31:0] unused;
        transfer(a, 1, d, unused);
    endtask

    task automatic read(input [14:0] a, output [31:0] q);
        transfer(a, 0, 0, q);
    endtask

    reg [7:0] expect0 [0:57599];
    reg [7:0] expect1 [0:57599];
    function automatic [7:0] expected(input integer slot, input integer i);
        expected = slot ? expect1[i] : expect0[i];
    endfunction
    integer tris_sent [0:1];

    // Push one frame's command words, counting its triangles.
    task automatic push(input [8*256-1:0] path, input integer slot);
        integer f, n, words, rest;
        reg [31:0] w;
        begin
            f = $fopen(path, "r");
            if (f == 0) begin
                $display("FAIL: cannot open %0s", path);
                $finish;
            end
            words = 0; rest = 0; tris_sent[slot] = 0;
            while ($fscanf(f, "%h\n", w) == 1) begin
                if (rest == 0 && w[31:28] == 4'd1) begin
                    tris_sent[slot] = tris_sent[slot] + 1; rest = 3;
                end else if (rest != 0)
                    rest = rest - 1;
                write(15'h00, w);
                words = words + 1;
            end
            $fclose(f);
            $display("frame %0d: %0d words, %0d triangles", slot, words,
                     tris_sent[slot]);
        end
    endtask

    task automatic wait_idle;
        reg [31:0] s;
        integer guard;
        begin
            s = 1; guard = 0;
            while (s[0]) begin
                read(15'h08, s);
                guard = guard + 1;
                if (guard > 100000) begin
                    $display("FAIL: the engine never went idle");
                    errors = errors + 1;
                    $finish;
                end
            end
        end
    endtask

    task automatic check_readback(input integer slot);
        integer k, bad;
        reg [31:0] q;
        begin
            bad = 0;
            write(15'h0020, 0);
            for (k = 0; k < 14400; k = k + 1) begin
                read(15'h0024, q);
                if (q !== {expected(slot, 4*k+3), expected(slot, 4*k+2),
                           expected(slot, 4*k+1), expected(slot, 4*k)}) begin
                    if (bad < 4)
                        $display("FAIL: buffer %0d word %0d read %h", slot, k, q);
                    bad = bad + 1;
                end
            end
            if (bad) errors = errors + 1;
            else $display("buffer %0d: read-back matches terrain_host", slot);
        end
    endtask

    task automatic check_line(input integer slot, input integer line);
        integer seen, bad;
        begin
            seen = 0; bad = 0;
            @(negedge clk);
            vaddr = {7'h7f, slot[0], line[7:0]}; vstart = 1;
            @(negedge clk);
            vstart = 0;
            while (seen < 160) begin
                @(posedge clk); #1;
                if (vvalid) begin
                    if (vindex != seen ||
                        vdata !== {expected(slot, line*320+2*seen+1),
                                   expected(slot, line*320+2*seen)})
                        bad = bad + 1;
                    if (vdone != (seen == 159)) bad = bad + 1;
                    seen = seen + 1;
                end
            end
            if (bad) begin
                $display("FAIL: buffer %0d line %0d fetch: %0d bad", slot, line, bad);
                errors = errors + 1;
            end
        end
    endtask

    reg [8*256-1:0] cmd0, cmd1, fb0, fb1;
    reg [31:0] q, tris0, pixels0, stalls;

    // The fabric's frame checksum, against the C the firmware and
    // terrain_host use: tc_crc32(0, bytes) == zlib.crc32(bytes), and a run
    // chains frames by seeding each scan with the last state, so the second
    // scan's result must be the CRC of both frames together.
    task automatic scan(input integer slot, input [31:0] seed,
                        input [31:0] want_crc, input integer want_nz,
                        output [31:0] state, output [31:0] nz);
        integer guard;
        begin
            write(15'h04, slot ? 32'h2 : 32'h0);  // the buffer to scan
            write(15'h1c, seed);
            q = 2; guard = 0;
            while (q[1]) begin                  // STATUS bit 1: scanning
                read(15'h08, q);
                guard = guard + 1;
                if (guard > 200000) begin
                    $display("FAIL: the scan of buffer %0d never finished", slot);
                    errors = errors + 1;
                    $finish;
                end
            end
            read(15'h1c, state);
            read(15'h28, nz);
            if (~state !== want_crc) begin
                $display("FAIL: buffer %0d CRC %h, expected %h", slot, ~state,
                         want_crc);
                errors = errors + 1;
            end else
                $display("buffer %0d: CRC %h matches tc_crc32", slot, ~state);
            if (nz !== want_nz) begin
                $display("FAIL: buffer %0d non-zero %0d, expected %0d", slot, nz,
                         want_nz);
                errors = errors + 1;
            end
        end
    endtask

    reg [31:0] want_crc0, want_crc01, state0, state1;
    reg [31:0] nz0, nz1;
    integer want_nz0, want_nz1;
    initial begin
        if (!$value$plusargs("cmd0=%s", cmd0) || !$value$plusargs("cmd1=%s", cmd1) ||
            !$value$plusargs("fb0=%s", fb0) || !$value$plusargs("fb1=%s", fb1)) begin
            $display("FAIL: give +cmd0= +cmd1= +fb0= +fb1=");
            $finish;
        end
        if (!$value$plusargs("crc0=%h", want_crc0) ||
            !$value$plusargs("crc01=%h", want_crc01) ||
            !$value$plusargs("nz0=%d", want_nz0) ||
            !$value$plusargs("nz1=%d", want_nz1)) begin
            $display("FAIL: give +crc0= +crc01= +nz0= +nz1=");
            $finish;
        end
        $readmemh(fb0, expect0);
        $readmemh(fb1, expect1);
        repeat (4) @(posedge clk);
        resetn = 1;

        read(15'h0c, q);
        if (q != 32'h54435231) begin
            $display("FAIL: ID %h", q); errors = errors + 1;
        end
        read(15'h10, tris0);
        write(15'h04, 32'h0);          // draw into buffer 0
        push(cmd0, 0);
        wait_idle;
        read(15'h10, q);
        if (q - tris0 != tris_sent[0]) begin
            $display("FAIL: TRIS %0d, sent %0d", q - tris0, tris_sent[0]);
            errors = errors + 1;
        end
        write(15'h04, 32'h2);          // draw into buffer 1
        push(cmd1, 1);
        wait_idle;
        read(15'h18, stalls);
        read(15'h14, pixels0);
        $display("stalls %0d, pixels %0d", stalls, pixels0);
        check_readback(1);
        write(15'h04, 32'h0);          // buffer 0 is untouched by frame 1
        check_readback(0);
        check_line(0, 0); check_line(0, 90); check_line(0, 179);
        check_line(1, 0); check_line(1, 137);
        // Buffer 0's content is frame 0 and buffer 1's is frame 1: scan both,
        // the second seeded from the first, the way a run chains its frames.
        scan(0, 32'hffffffff, want_crc0, want_nz0, state0, nz0);
        scan(1, state0, want_crc01, want_nz1, state1, nz1);
        if (errors == 0) $display("PASS raster_tb");
        else $display("FAIL raster_tb: %0d errors", errors);
        $finish;
    end
endmodule
