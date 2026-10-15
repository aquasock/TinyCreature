`timescale 1ns/1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Runs the widened video transaction against TinyNES's timing-checking SDRAM
// model and verifies all 160 halfwords arrive in order.
module ODDR(input wire D0,input wire D1,input wire TX,input wire CLK,
            output wire Q0,output wire Q1);
    assign Q0=~CLK;
    assign Q1=1'b0;
endmodule

module tang32_sdram_video_tb;
    reg clk=0, resetn=0;
    always #6.667 clk=!clk;
    reg req=0, write=0, vstart=0;
    reg [24:3] addr=0;
    reg [7:0] lanes=0;
    reg [63:0] wdata=0;
    wire ack, ready, vvalid, vdone, sdram_clk;
    wire [63:0] rdata;
    reg [24:9] vaddr=16'hfe00;
    wire [7:0] vindex;
    wire [15:0] vdata;
    wire cs_n,ras_n,cas_n,we_n;
    wire [1:0] ba,dqm;
    wire [12:0] a;
    wire [15:0] dq;

    ahb_sdram #(.INIT_CYCLES(32)) dut(
        .clk(clk),.resetn(resetn),.req(req),.write(write),.addr(addr),
        .lanes(lanes),.wdata(wdata),.ack(ack),.rdata(rdata),.ready(ready),
        .vstart(vstart),.vaddr(vaddr),.vvalid(vvalid),.vindex(vindex),
        .vdata(vdata),.vdone(vdone),.sdram_clk(sdram_clk),
        .sdram_cs_n(cs_n),.sdram_ras_n(ras_n),.sdram_cas_n(cas_n),
        .sdram_we_n(we_n),.sdram_ba(ba),.sdram_a(a),.sdram_dqm(dqm),
        .sdram_dq(dq)
    );
    sdram_model mem(.clk(sdram_clk),.cs_n(cs_n),.ras_n(ras_n),
        .cas_n(cas_n),.we_n(we_n),.ba(ba),.a(a),.dqm(dqm),.dq(dq));

    integer count=0;
    always @(posedge clk) if (vvalid) begin
        if (vindex!==count[7:0]) begin
            $display("FAIL video index %0d after %0d",vindex,count);
            $finish_and_return(1);
        end
        if (vdone!==(count==159)) begin
            $display("FAIL vdone at %0d is %b",count,vdone);
            $finish_and_return(1);
        end
        count<=count+1;
    end

    initial begin
        repeat(5) @(posedge clk);
        resetn=1;
        wait(ready);
        @(negedge clk); vstart=1;
        @(negedge clk); vstart=0;
        wait(vdone);
        repeat(3) @(posedge clk);
        if (count!=160 || mem.reads!=160) begin
            $display("FAIL video beats=%0d SDRAM reads=%0d",count,mem.reads);
            $finish_and_return(1);
        end
        $display("PASS Tang32 SDRAM returned 160 ordered halfwords");
        $finish;
    end
endmodule
