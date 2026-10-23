// SPDX-License-Identifier: GPL-3.0-or-later
// fpga/raster.sv's CARD against its depth buffer: a card behind what the
// buffer already holds writes nothing where the buffer is nearer, and one in
// front writes over it. The cards here are the eight words
// firmware/terrain/main.c's fabric_card() sends, the last three their depth
// plane, and the count of written pixels is the observation: a fill that
// ignored depth would count every pixel of every card.
//
//   iverilog -g2012 -s card_tb -o build/card-tb/card_tb \
//       tests/card_tb.sv fpga/raster.sv && vvp -n build/card-tb/card_tb
`timescale 1ns/1ps
module card_tb;
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
    integer pixels;

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

    // One card, eight words, the plane constant across the rectangle so the
    // depth it stands at is the D in the command.
    task automatic card(input integer i0, input integer j0, input integer i1,
                        input integer j1, input [31:0] d);
        begin
            write(15'h00, 32'h3000_0000);            // opcode 3, tile 0
            write(15'h00, j0 << 16 | i0);
            write(15'h00, j1 << 16 | i1);
            write(15'h00, 32'h0);                    // du | dv
            write(15'h00, 32'h0);                    // u0 | v0
            write(15'h00, d);                        // D at the first pixel
            write(15'h00, 32'h0);                    // step across
            write(15'h00, 32'h0);                    // step down
        end
    endtask

    task automatic check_pixels(input [8*40-1:0] what, input integer want);
        begin
            read(15'h14, pixels);
            if (pixels !== want) begin
                $display("FAIL: %0s: PIXELS=%0d, want %0d", what, pixels, want);
                errors = errors + 1;
            end else
                $display("ok: %0s: PIXELS=%0d", what, pixels);
        end
    endtask

    integer k;
    initial begin
        // Reset, then give the block RAMs a clock to come up.
        repeat (8) @(negedge clk);
        resetn = 1;
        repeat (4) @(negedge clk);

        // Tile 0, every texel 0x11: opaque, so every pixel of a card writes.
        write(15'h34, 32'd0);
        for (k = 0; k < 256; k = k + 1)
            write(15'h38, 32'h1111_1111);

        // Clear the frame and the depth buffer: rows 0 to 179, colour 0.
        write(15'h00, 32'h2000_0000 | 180 << 16 | 0 << 8 | 0);
        wait_idle;

        // A near card on the left half, then a far one over the whole frame.
        // The far one may only write the half the near one did not cover.
        card(0, 0, 160, 180, 32'd1000);
        wait_idle;
        check_pixels("near card, left half", 28800);
        card(0, 0, 320, 180, 32'd500);
        wait_idle;
        check_pixels("far card over it, occluded", 57600);

        // A nested check: the far card cannot write anywhere at all now.
        card(0, 0, 320, 180, 32'd100);
        wait_idle;
        check_pixels("far card behind both", 57600);

        // Clear, then the other order: far first, near over it, then a tie.
        write(15'h00, 32'h2000_0000 | 180 << 16 | 0 << 8 | 0);
        wait_idle;
        card(0, 0, 320, 180, 32'd500);
        wait_idle;
        check_pixels("far card on a clear buffer", 115200);
        card(0, 0, 320, 180, 32'd1000);
        wait_idle;
        check_pixels("near card over it", 172800);
        card(0, 0, 320, 180, 32'd1000);
        wait_idle;
        check_pixels("equal depth, later wins", 230400);

        if (errors == 0)
            $display("PASS card_tb");
        else
            $display("FAIL card_tb: %0d errors", errors);
        $finish;
    end
endmodule
