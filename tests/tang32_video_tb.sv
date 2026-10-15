`timescale 1ns/1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Checks the complete 320-byte line-buffer request sequence for one displayed
// 320x180 frame. The SDRAM model returns each 320-byte line well before its
// four scaled raster rows begin.
module tang32_video_tb;
    reg clk=0, pix_clk=0, resetn=0, pix_reset=1;
    always #6.667 clk=!clk;
    always #6.734 pix_clk=!pix_clk;

    reg [17:0] haddr=0;
    reg [1:0] htrans=0;
    reg hsel=0, hwrite=0;
    reg [2:0] hsize=3'd2;
    reg [31:0] hwdata=0;
    wire [31:0] hrdata;
    wire hready, hresp;
    wire vstart;
    wire [24:9] vaddr;
    reg vvalid=0;
    reg [7:0] vindex=0;
    reg [15:0] vdata=16'h0101;
    reg vdone=0;
    wire [9:0] blue, green, red;

    video dut(
        .clk(clk),.resetn(resetn),.haddr(haddr),.htrans(htrans),
        .hsel(hsel),.hwrite(hwrite),.hsize(hsize),.hwdata(hwdata),
        .hready_in(1'b1),.hrdata(hrdata),.hready(hready),.hresp(hresp),
        .vstart(vstart),.vaddr(vaddr),.vvalid(vvalid),.vindex(vindex),
        .vdata(vdata),.vdone(vdone),.pix_clk(pix_clk),.pix_reset(pix_reset),
        .tmds_blue(blue),.tmds_green(green),.tmds_red(red)
    );

    integer fetches=0;
    integer beats=0;
    reg serving=0;
    always @(posedge clk) begin
        vvalid<=0;
        vdone<=0;
        if (vstart) begin
            if (serving) begin
                $display("FAIL overlapping fetch");
                $finish_and_return(1);
            end
            if (vaddr !== {7'h7f,1'b1,fetches[7:0]}) begin
                $display("FAIL fetch %0d address %h",fetches,vaddr);
                $finish_and_return(1);
            end
            serving<=1;
            beats<=0;
            fetches<=fetches+1;
        end else if (serving) begin
            vvalid<=1;
            vindex<=beats[7:0];
            if (beats==159) begin
                vdone<=1;
                serving<=0;
                if (fetches==180) begin
                    if (dut.late!=0) begin
                        $display("FAIL late=%0d",dut.late);
                        $finish_and_return(1);
                    end
                    $display("PASS Tang32 video fetched 180 lines x 320 bytes");
                    $finish;
                end
            end
            beats<=beats+1;
        end
    end

    initial begin
        repeat(10) @(posedge clk);
        resetn=1;
        repeat(10) @(posedge pix_clk);
        pix_reset=0;
        force dut.ctrl=2'b11;
        #50000000;
        $display("FAIL timeout fetches=%0d late=%0d",fetches,dut.late);
        $finish_and_return(1);
    end
endmodule
