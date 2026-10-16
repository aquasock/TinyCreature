// SPDX-License-Identifier: GPL-3.0-or-later
// TinyCreature's fabric rasterizer: shaded triangles into two 320x180
// indexed frame buffers in block RAM, which the video unit shows through
// the same line-fetch handshake as the SDRAM (ahb_sdram.sv).
//
// Everything is on the bus clock: block RAM on two clocks reads back wrong
// in the open flow on this chip (TinyNES TOOL-020), and each store maps to
// 9-bit or 36-bit block RAM modes.
//
// The unit takes the upper half of the video unit's window, which the
// AE350 is known to pass to the fabric. Bus offsets from 0xe8018000:
//   0x00 FIFO    write: command words; a write to a full FIFO waits
//   0x04 CTRL    bit 0 show these buffers instead of the SDRAM's,
//                bit 1 the buffer drawn into and read back
//   0x08 STATUS  bit 0 busy: commands queued or being drawn
//   0x0c ID      "TCR1"
//   0x10 TRIS    triangle commands taken, free-running
//   0x14 PIXELS  pixels written by triangles, free-running
//   0x18 STALLS  bus cycles writes waited on a full FIFO, free-running
//   0x20 RB_ADDR write: the drawn buffer's pixel the next RB_DATA read
//                starts at, a multiple of 4 below 57,600
//   0x24 RB_DATA read: four pixels from RB_ADDR, the first in bits 7:0;
//                RB_ADDR then moves on by 4
//   0x1c CRC     write: start folding the target buffer into this CRC-32
//                seed, in address order; read: the state left by the last
//                scan that finished, raw, for the program to invert once at
//                the end of a run. Scanning 57,600 bytes takes about 2.3 ms,
//                so a program reads the result a frame later rather than
//                waiting for it.
//   0x28 NONZERO read: how many bytes the last finished scan found not zero
//                STATUS bit 1 is set while a scan is running
//   0x2c PAL     write: entry << 16 | index, one of the 256 palette entries
//                in the five bits a channel the shading mixes in
//   0x30 LUT     write: entry << 24 | colour, one of the 32768 colours those
//                channels make: the land's nearest entry to that colour
//
// Commands:
//   ROWS  1 word: 2 << 28 | end << 16 | first << 8 | colour, fills rows
//         first to end - 1
//   TRI   4 words: 1 << 28 | c2 << 16 | c1 << 8 | c0, then y << 16 | x for
//         each corner, as 16-bit two's-complement Q4 screen coordinates.
//         c0, c1 and c2 are the corners' palette entries, one byte each.
//   CARD  5 words: 3 << 28 | tile << 16, then i0 | j0 << 16, then
//         i1 | j1 << 16, then du | dv << 16, then u0 | v0 << 16: an
//         axis-aligned rectangle of pixels, [i0, i1) across and [j0, j1)
//         down, filled with one 32 by 32 tile of the art, whose texel is
//         taken by accumulating du and dv, in Q8 texels a pixel, from u0 and
//         v0. The caller works the pixel range, the steps and the starting
//         accumulators out, because the fabric has no divider; the fill only
//         adds. A texel is written as the palette entry ART_FIRST plus its
//         own index, so the art's entries are written rather than searched
//         for and the shading table is not consulted at all -- which is why
//         art cannot take colour off the land the way a shaded triangle's
//         nearest-entry search can. A card is two clocks a pixel: the store
//         is asked at one address and its byte is written the next.
// A triangle fills pixel (i, j) when, at its centre (16i + 8, 16j + 8), all
// three edge functions F = (by - ay)(px - ax) - (bx - ax)(py - ay) over its
// edges a to b are >= 0; pixels outside the screen are never visited. The
// corners must be in the order that makes F >= 0 inside, which for this
// project is a front face (firmware/terrain/terrain.c, raster_triangle()).
//
// A filled pixel takes the colour of the three corners mixed by the pixel's
// own weights: F1 / S belongs to the first corner, F2 / S to the second and
// F0 / S to the third, each edge function measuring the corner across from
// it, and S = F0 + F1 + F2 is the same at every pixel of a triangle. Those
// weights are quantised to quarters -- a few compares instead of a divide,
// and a triangle a few pixels across cannot tell the difference -- and the
// mix is done in the five bits a channel the game's materials carry, which
// is what tc_soft in terrain.c does to the bit, so the AE350 and a PC draw
// identical frames. The colour that comes out is looked up in the table the
// program loaded, which gives the palette entry to write.
module raster #(
    parameter [31:0] ID_VALUE = 32'h54435231
) (
    input wire clk, input wire resetn,
    input wire [14:0] haddr, input wire [1:0] htrans, input wire hsel,
    input wire hwrite, input wire [2:0] hsize, input wire [31:0] hwdata,
    input wire hready_in, output reg [31:0] hrdata, output reg hready,
    output reg hresp,
    output reg show,
    input wire vstart, input wire [24:9] vaddr,
    output reg vvalid, output reg [7:0] vindex, output reg [15:0] vdata,
    output reg vdone
);
    localparam W = 320, H = 180, PIXELS = W * H;

    // ---- Command FIFO, 512 x 32 in one block RAM ----
    reg [35:0] fifo [0:511];
    reg [9:0] wr_ptr = 0, rd_ptr = 0;
    wire [9:0] level = wr_ptr - rd_ptr;
    wire fifo_full = level[9];
    wire fifo_empty = level == 0;
    reg w_fifo = 0;
    // A write waiting in its data phase goes in as soon as there is room.
    wire push = w_fifo && !fifo_full;
    // The command assembler takes the word at rd_ptr on the edge it moves
    // rd_ptr on; the word is in fifo_q, q_valid set, the cycle after.
    wire pop;
    reg [35:0] fifo_q = 0;
    always @(posedge clk) begin
        if (push) fifo[wr_ptr[8:0]] <= {4'd0, hwdata};
        if (pop) fifo_q <= fifo[rd_ptr[8:0]];
    end
    always @(posedge clk or negedge resetn)
        if (!resetn) wr_ptr <= 0;
        else if (push) wr_ptr <= wr_ptr + 1'b1;

    // ---- Bus slave ----
    reg target = 0, err2 = 0, w_ctrl = 0, w_rb = 0, w_crc = 0, r_fb = 0;
    reg [1:0] r_byte = 0;
    reg r_issued = 0;
    reg [31:0] r_data = 0;
    reg [31:0] tris = 0, pixels = 0, stalls = 0;
    // The frame checksum: a reflected CRC-32 over the target buffer in
    // address order, seeded by the CPU. The program chains a run's frames
    // through it exactly as tc_crc32(crc, frame, bytes) chains them, so the
    // value it ends with is the one terrain_host computes from the same
    // file.
    reg [31:0] crc_reg = 32'hffffffff;
    reg [15:0] nz_count = 0, nz_latch = 0;
    reg [15:0] crc_addr = 0;
    reg crc_scanning = 0, crc_buf = 0;
    wire busy;
    wire accept = hready_in && hsel && htrans[1];
    wire word = hsize == 3'd2 && haddr[1:0] == 0;
    wire [3:0] reg_index = haddr[5:2];
    wire is_reg = haddr[14:6] == 0;
    wire is_fb = is_reg && !hwrite && reg_index == 9;
    wire ok = word && is_reg &&
              (hwrite ? (reg_index <= 1 || reg_index >= 7 && reg_index <= 8) ||
                        reg_index == 11 || reg_index == 12 || reg_index == 13 ||
                        reg_index == 14
                      : (reg_index >= 1 && reg_index <= 7) || reg_index == 9 ||
                        reg_index == 10);
    // The CPU's read port request, served when the line fetch leaves it.
    reg cpu_rd = 0;
    wire cpu_rd_grant;
    reg [15:0] cpu_raddr = 0;
    wire [7:0] cpu_q;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            hready <= 1; hresp <= 0; hrdata <= 0; err2 <= 0; w_fifo <= 0;
            w_ctrl <= 0; w_crc <= 0; r_fb <= 0; show <= 0; target <= 0;
            stalls <= 0; cpu_rd <= 0; r_issued <= 0;
        end else begin
            if (err2) begin
                err2 <= 0; hready <= 1;
            end else if (w_fifo) begin
                if (!fifo_full) begin
                    w_fifo <= 0; hready <= 1;
                end else
                    stalls <= stalls + 1'b1;
            end else if (w_ctrl) begin
                if (w_rb)
                    cpu_raddr <= {hwdata[15:2], 2'b00};
                else begin
                    show <= hwdata[0]; target <= hwdata[1];
                end
                w_ctrl <= 0; hready <= 1;
            end else if (w_pal) begin
                w_pal <= 0; hready <= 1;
            end else if (w_lut) begin
                w_lut <= 0; hready <= 1;
            end else if (w_tiles_addr) begin
                tiles_addr <= hwdata[15:0];
                w_tiles_addr <= 0; hready <= 1;
            end else if (w_tiles) begin
                // Four bytes a write, the first in bits 7:0, which is the
                // shape the frame read-back already has.
                if (tiles_step == 2'd3) begin
                    w_tiles <= 0; hready <= 1;
                    tiles_addr <= tiles_addr + 16'd4;
                end else
                    tiles_step <= tiles_step + 1'b1;
            end else if (w_crc) begin
                // One cycle of w_crc is the scan's start pulse.
                w_crc <= 0; hready <= 1;
            end else if (r_fb) begin
                // Four bytes, one block RAM read each, data a cycle later.
                if (cpu_rd && cpu_rd_grant) begin
                    cpu_rd <= 0; r_issued <= 1;
                end else if (r_issued) begin
                    r_issued <= 0;
                    r_data <= {cpu_q, r_data[31:8]};
                    cpu_raddr <= cpu_raddr + 1'b1;
                    if (r_byte == 3) begin
                        r_fb <= 0; hready <= 1; hrdata <= {cpu_q, r_data[31:8]};
                    end else begin
                        r_byte <= r_byte + 1'b1; cpu_rd <= 1;
                    end
                end
            end else begin
                hresp <= 0; hrdata <= 0;
                if (accept && ok && !hwrite && !is_fb)
                    case (reg_index)
                        1: hrdata <= {30'd0, target, show};
                        2: hrdata <= {30'd0, crc_scanning, busy};
                        3: hrdata <= ID_VALUE;
                        4: hrdata <= tris;
                        5: hrdata <= pixels;
                        6: hrdata <= stalls;
                        7: hrdata <= crc_reg;
                        10: hrdata <= {16'd0, nz_latch};
                        default: hrdata <= 0;
                    endcase
                if (accept) begin
                    if (!ok) begin
                        hready <= 0; hresp <= 1; err2 <= 1;
                    end else if (is_fb) begin
                        hready <= 0; r_fb <= 1; r_byte <= 0; cpu_rd <= 1;
                    end else if (hwrite && reg_index == 0) begin
                        hready <= 0; w_fifo <= 1;
                    end else if (hwrite && reg_index == 7) begin
                        hready <= 0; w_crc <= 1;
                    end else if (hwrite && reg_index == 13) begin
                        hready <= 0; w_tiles_addr <= 1;
                    end else if (hwrite && reg_index == 14) begin
                        hready <= 0; w_tiles <= 1; tiles_step <= 0;
                    end else if (hwrite && (reg_index == 11 || reg_index == 12)) begin
                        hready <= 0;
                        w_pal <= reg_index == 11;
                        w_lut <= reg_index == 12;
                    end else if (hwrite) begin
                        hready <= 0; w_ctrl <= 1; w_rb <= reg_index == 8;
                    end
                end
            end
        end
    end

    // ---- Command assembler: the next command is gathered while the
    // engine draws the last ----
    reg [2:0] issued = 0, got = 0, len = 1;
    reg q_valid = 0;
    reg cmd_full = 0;
    assign pop = !cmd_full && !fifo_empty && issued < len;
    reg [3:0] cmd_op = 0;
    reg [7:0] cmd_colour = 0, cmd_first = 0, cmd_end = 0;
    // A triangle's three corner colours; the first is the byte a ROWS word
    // also carries, so both commands read the same field.
    reg [7:0] cmd_c1 = 0, cmd_c2 = 0;
    // A card's tile, and the four words that follow its opcode. They are read
    // into the same fields a triangle's corners are, four of them instead of
    // three, which is why these hold one more than the triangle needs.
    reg [7:0] cmd_tile = 0;
    reg signed [15:0] cmd_x [0:3];
    reg signed [15:0] cmd_y [0:3];
    wire take;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            issued <= 0; got <= 0; len <= 1; q_valid <= 0; cmd_full <= 0;
            rd_ptr <= 0;
        end else begin
            q_valid <= pop;
            if (take) cmd_full <= 0;
            // rd_ptr moves with each pop, so fifo_empty already counts
            // the words in flight.
            if (pop) begin
                rd_ptr <= rd_ptr + 1'b1; issued <= issued + 1'b1;
            end
            if (q_valid) begin
                if (got == 0) begin
                    cmd_op <= fifo_q[31:28]; cmd_colour <= fifo_q[7:0];
                    cmd_first <= fifo_q[15:8]; cmd_end <= fifo_q[23:16];
                    if (fifo_q[31:28] == 4'd1) begin
                        cmd_c1 <= fifo_q[15:8]; cmd_c2 <= fifo_q[23:16];
                        len <= 4; got <= 1;
                    end else if (fifo_q[31:28] == 4'd3) begin
                        cmd_tile <= fifo_q[23:16];
                        len <= 5; got <= 1;
                    end else begin
                        cmd_full <= 1; got <= 0; issued <= 0; len <= 1;
                    end
                end else begin
                    cmd_x[got - 1] <= fifo_q[15:0];
                    cmd_y[got - 1] <= fifo_q[31:16];
                    if (got == (cmd_op == 4'd3 ? 3'd4 : 3'd3)) begin
                        cmd_full <= 1; got <= 0; issued <= 0; len <= 1;
                    end else
                        got <= got + 1'b1;
                end
            end
        end
    end
    // Before word 0 arrives len is 1, so nothing is popped past a ROWS
    // word; a TRI's three corner words follow once its opcode is seen.

    // ---- Palette and the nearest-colour table, one block RAM each ----
    // The program loads both before its first frame: the 256 palette entries
    // in the five bits a channel the shading works in, and the 32768-entry
    // table from a colour those channels make back to a palette entry. Each
    // is written straight from the bus in the cycle after its write is
    // accepted, which is the cycle its data is on the bus, and read by the
    // palette walk at the start of a triangle and by the fill's own stage.
    // Both nine bits wide where they can be, the width this chip's video
    // block RAMs are held to: only the 9-bit modes read back correctly in the
    // open flow, so the palette is 18 bits and the table 9, not 16 and 8.
    (* ram_style = "block" *) reg [17:0] palette [0:255];
    (* ram_style = "block" *) reg [8:0] lut [0:32767];
    // The art: 64 tiles of 32 by 32 texels, a byte each, 64 KiB. The program
    // loads them through TILES_ADDR and TILES_DATA, four bytes a write, the
    // first in bits 7:0, which is the shape RB_ADDR and RB_DATA already use.
    localparam TILE_BYTES = 1024, TILE_COUNT = 64;
    localparam ART_FIRST_W = 192;
    (* ram_style = "block" *) reg [8:0] tiles [0:TILE_COUNT * TILE_BYTES - 1];
    reg [15:0] tiles_addr = 0;
    reg [1:0] tiles_step = 0;
    reg w_tiles = 0, w_tiles_addr = 0;
    reg [15:0] tile_raddr = 0;
    reg [8:0] tile_q = 0;
    reg [7:0] pal_addr = 0;
    reg [14:0] lut_addr = 0;
    reg [17:0] pal_q = 0;
    reg [8:0] lut_q = 0;
    // A write and a read in one clock, at different addresses, which is what
    // maps to block RAM here: the same shape the frame buffers use, and no
    // reset, so the flow sees a memory rather than a register file.
    always @(posedge clk) begin
        if (w_pal) palette[hwdata[7:0]] <= hwdata[31:16];
        if (w_lut) lut[hwdata[14:0]] <= hwdata[31:24];
        if (w_tiles) tiles[tiles_addr + tiles_step] <= hwdata[8 * tiles_step +: 8];
        pal_q <= palette[pal_addr];
        lut_q <= lut[lut_addr];
        tile_q <= tiles[tile_raddr];
    end

    // ---- Engine ----
    localparam S_IDLE = 0, S_ROWS = 1, S_BOX = 2, S_CLAMP = 3, S_LOAD = 4,
               S_EDGE = 5, S_TRIPLE = 6, S_MUL = 7, S_FIN = 8, S_PAL = 9,
               S_SCAN = 10, S_DRAIN = 11, S_CARD = 12;
    reg [3:0] state = S_IDLE;

    // ---- A card's own state ----
    // The rectangle, the running pixel, the two Q8 texel accumulators and
    // their starting values, and the steps: all of it worked out by the
    // caller, so the fill adds and never multiplies or divides.
    reg [8:0] card_i = 0, card_i0 = 0, card_i1 = 0;
    reg [7:0] card_j = 0, card_j0 = 0, card_j1 = 0;
    reg [15:0] card_u = 0, card_v = 0, card_u0 = 0, card_du = 0, card_dv = 0;
    reg [15:0] card_addr = 0;
    // The tile is latched from the assembler's field, not read from it: the
    // assembler has already started gathering the next command's words.
    reg [7:0] card_tile = 0;
    reg [1:0] card_phase = 0;
    assign take = cmd_full && state == S_IDLE;
    assign busy = !fifo_empty || pop || q_valid || cmd_full || got != 0 ||
                  state != S_IDLE || w_fifo;

    reg [7:0] colour = 0;
    reg signed [15:0] vx [0:2];
    reg signed [15:0] vy [0:2];
    reg [8:0] i0 = 0, i1 = 0, i = 0;
    reg [7:0] j0 = 0, j1 = 0, j = 0;
    reg [15:0] addr = 0, row_addr = 0, fill_end = 0;
    reg signed [16:0] dx [0:2];
    reg signed [16:0] dy [0:2];
    reg signed [17:0] ox [0:2];
    reg signed [17:0] oy [0:2];
    reg signed [35:0] dx3 [0:2];
    reg signed [35:0] dy3 [0:2];
    reg signed [35:0] acc_x [0:2];   // dy * ox
    reg signed [35:0] acc_y [0:2];   // dx * oy
    reg signed [35:0] e [0:2];       // F at (i, j)
    reg signed [35:0] e_row [0:2];   // F at (i0, j)
    reg signed [35:0] step_x [0:2];
    reg signed [35:0] step_y [0:2];
    reg [3:0] digit = 0;
    reg we = 0;
    reg [15:0] waddr = 0;
    reg [7:0] wdata = 0;

    // ---- The shading's own state ----
    // S is the sum of the three edge functions, the same at every pixel of a
    // triangle; two and three times it are the thresholds the weights are
    // counted against. The corners' colours come from the palette, and the
    // colour of each pixel the fill visits is registered here with whether
    // it was covered and where it is, so the table's answer can be written a
    // cycle later without stopping the scan.
    reg signed [35:0] s_reg = 0, s2_reg = 0, s3_reg = 0;
    reg [15:0] c0_c = 0, c1_c = 0, c2_c = 0;
    // The command's three corner colours, taken with its corners: the
    // assembler gathers the next command while this one draws, so the words
    // it decoded are gone by the time the palette is read.
    reg [7:0] c0_e = 0, c1_e = 0, c2_e = 0;
    reg [2:0] pal_step = 0;
    reg w_pal = 0, w_lut = 0;
    reg [14:0] col15 = 0;
    reg we1_r = 0;
    reg [15:0] a1_r = 0;
    reg [1:0] drain = 0;
    // The fill takes two clocks a pixel: the first works out this pixel's
    // weights and whether it is covered, the second mixes its colour from the
    // registered weights. One clock would carry a 36-bit compare chain and
    // the mix in a single path, which the bus clock does not hold.
    reg phase = 0;
    reg [1:0] aw_r = 0, bw_r = 0;
    reg covered_r = 0;
    reg [15:0] addr_r = 0;
    reg last_p = 0;
    wire [4:0] r0 = c0_c[14:10], g0 = c0_c[9:5], b0 = c0_c[4:0];
    wire [4:0] r1 = c1_c[14:10], g1 = c1_c[9:5], b1 = c1_c[4:0];
    wire [4:0] r2 = c2_c[14:10], g2 = c2_c[9:5], b2 = c2_c[4:0];
    // The weights, in quarters: a triangle of no area has S zero, so every
    // threshold would pass and its corners would be asked for a colour the
    // mix cannot give, so its first corner colours it instead. The weight of
    // the second corner is F2 / S and of the third F0 / S, each edge function
    // measuring the corner across from it.
    wire signed [35:0] f2 = e[2] <<< 2;
    wire signed [35:0] f0s = e[0] <<< 2;
    wire [1:0] aw = s_reg > 0 ? ({1'b0, f2 >= s_reg} + {1'b0, f2 >= s2_reg} +
                                 {1'b0, f2 >= s3_reg}) : 2'd0;
    wire [1:0] bw = s_reg > 0 ? ({1'b0, f0s >= s_reg} + {1'b0, f0s >= s2_reg} +
                                 {1'b0, f0s >= s3_reg}) : 2'd0;
    // The mix reads the weights the first phase registered, so nothing here
    // waits on an edge function.
    wire signed [3:0] aws = $signed({2'b0, aw_r});
    wire signed [3:0] bws = $signed({2'b0, bw_r});
    wire signed [8:0] dr1 = $signed({4'b0, r1}) - $signed({4'b0, r0});
    wire signed [8:0] dg1 = $signed({4'b0, g1}) - $signed({4'b0, g0});
    wire signed [8:0] db1 = $signed({4'b0, b1}) - $signed({4'b0, b0});
    wire signed [8:0] dr2 = $signed({4'b0, r2}) - $signed({4'b0, r0});
    wire signed [8:0] dg2 = $signed({4'b0, g2}) - $signed({4'b0, g0});
    wire signed [8:0] db2 = $signed({4'b0, b2}) - $signed({4'b0, b0});
    wire signed [12:0] mr = (dr1 * aws + dr2 * bws + 13'sd2) >>> 2;
    wire signed [12:0] mg = (dg1 * aws + dg2 * bws + 13'sd2) >>> 2;
    wire signed [12:0] mb = (db1 * aws + db2 * bws + 13'sd2) >>> 2;
    wire signed [12:0] vr = $signed({7'b0, r0}) + mr;
    wire signed [12:0] vg = $signed({7'b0, g0}) + mg;
    wire signed [12:0] vb = $signed({7'b0, b0}) + mb;
    wire [4:0] outr = vr[4:0];
    wire [4:0] outg = vg[4:0];
    wire [4:0] outb = vb[4:0];
    wire [14:0] mixed = {outr, outg, outb};

    // Bounding box of the corners, in pixel centres, clamped to the screen,
    // over three cycles (S_BOX, S_CLAMP, S_LOAD) to keep each short.
    wire signed [15:0] min01x = vx[0] < vx[1] ? vx[0] : vx[1];
    wire signed [15:0] max01x = vx[0] < vx[1] ? vx[1] : vx[0];
    wire signed [15:0] min01y = vy[0] < vy[1] ? vy[0] : vy[1];
    wire signed [15:0] max01y = vy[0] < vy[1] ? vy[1] : vy[0];
    reg signed [15:0] xmin = 0, xmax = 0, ymin = 0, ymax = 0;
    wire signed [16:0] xmin7 = xmin + 17'sd7, ymin7 = ymin + 17'sd7;
    wire signed [16:0] xmax8 = xmax - 17'sd8, ymax8 = ymax - 17'sd8;
    wire signed [12:0] bi0 = xmin7 >>> 4, bi1 = xmax8 >>> 4;
    wire signed [12:0] bj0 = ymin7 >>> 4, bj1 = ymax8 >>> 4;
    reg signed [12:0] ci0 = 0, ci1 = 0, cj0 = 0, cj1 = 0;
    wire box_empty = ci0 > ci1 || cj0 > cj1;

    function automatic signed [35:0] radix4(input signed [17:0] b,
        input [3:0] k, input signed [35:0] a, input signed [35:0] a3);
        reg [1:0] d;
        begin
            d = b[2 * k +: 2];
            if (k == 8)   // the top digit carries the sign: b17 weighs -2
                case (d)
                    2'd0: radix4 = 0;
                    2'd1: radix4 = a;
                    2'd2: radix4 = -(a <<< 1);
                    default: radix4 = -a;
                endcase
            else
                case (d)
                    2'd0: radix4 = 0;
                    2'd1: radix4 = a;
                    2'd2: radix4 = a <<< 1;
                    default: radix4 = a3;
                endcase
        end
    endfunction

    wire covered = !e[0][35] && !e[1][35] && !e[2][35];
    integer k;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= S_IDLE; we <= 0; tris <= 0; pixels <= 0; we1_r <= 0;
            phase <= 0; last_p <= 0;
        end else begin
            we <= 0;
            case (state)
            S_IDLE:
                if (take) begin
                    colour <= cmd_colour;
                    if (cmd_op == 4'd1) begin
                        for (k = 0; k < 3; k = k + 1) begin
                            vx[k] <= cmd_x[k]; vy[k] <= cmd_y[k];
                        end
                        c0_e <= cmd_colour;
                        c1_e <= cmd_c1;
                        c2_e <= cmd_c2;
                        tris <= tris + 1'b1;
                        state <= S_BOX;
                    end else if (cmd_op == 4'd2 && cmd_first < cmd_end &&
                                 cmd_end <= H) begin
                        addr <= {cmd_first, 8'd0} + {2'd0, cmd_first, 6'd0};
                        fill_end <= {cmd_end, 8'd0} + {2'd0, cmd_end, 6'd0};
                        state <= S_ROWS;
                    end else if (cmd_op == 4'd3 && cmd_x[1] > cmd_x[0] &&
                                 cmd_y[1] > cmd_y[0]) begin
                        card_i0 <= cmd_x[0][8:0];
                        card_i1 <= cmd_x[1][8:0];
                        card_j0 <= cmd_y[0][7:0];
                        card_j1 <= cmd_y[1][7:0];
                        card_i <= cmd_x[0][8:0];
                        card_j <= cmd_y[0][7:0];
                        card_du <= cmd_x[2];
                        card_dv <= cmd_y[2];
                        card_u0 <= cmd_x[3];
                        card_u <= cmd_x[3];
                        card_v <= cmd_y[3];
                        card_tile <= cmd_tile;
                        card_addr <= {cmd_y[0][7:0], 8'd0} +
                                     {2'd0, cmd_y[0][7:0], 6'd0} +
                                     {7'd0, cmd_x[0][8:0]};
                        card_phase <= 0;
                        state <= S_CARD;
                    end
                end
            S_CARD: begin
                // Three clocks a pixel. The store is a block RAM, so its data
                // arrives the clock after its address, and the address is a
                // register that changes on the same edge the data is taken:
                // one clock to ask, one for the answer to land, and the third
                // to write it. Two clocks wrote each pixel the previous
                // pixel's texel, which the testbench caught as the frame's
                // bytes reading one column to the left.
                if (card_phase == 2'd0) begin
                    tile_raddr <= {card_tile, 10'd0} +
                                  {5'd0, card_v[15:8], 5'd0} +
                                  {10'd0, card_u[15:8]};
                    card_phase <= 2'd1;
                end else if (card_phase == 2'd1) begin
                    card_phase <= 2'd2;
                end else begin
                    we <= 1;
                    waddr <= card_addr;
                    wdata <= ART_FIRST_W + tile_q[7:0];
                    pixels <= pixels + 1'b1;
                    card_phase <= 2'd0;
                    if (card_i + 1'b1 < card_i1) begin
                        card_i <= card_i + 1'b1;
                        card_u <= card_u + card_du;
                        card_addr <= card_addr + 1'b1;
                    end else if (card_j + 1'b1 < card_j1) begin
                        card_i <= card_i0;
                        card_u <= card_u0;
                        card_v <= card_v + card_dv;
                        card_j <= card_j + 1'b1;
                        card_addr <= {card_j + 1'b1, 8'd0} +
                                     {2'd0, card_j + 1'b1, 6'd0} +
                                     {7'd0, card_i0};
                    end else
                        state <= S_IDLE;
                end
            end
            S_ROWS: begin
                we <= 1; waddr <= addr; wdata <= colour;
                addr <= addr + 1'b1;
                if (addr + 1'b1 == fill_end) state <= S_IDLE;
            end
            S_BOX: begin
                xmin <= min01x < vx[2] ? min01x : vx[2];
                xmax <= max01x > vx[2] ? max01x : vx[2];
                ymin <= min01y < vy[2] ? min01y : vy[2];
                ymax <= max01y > vy[2] ? max01y : vy[2];
                state <= S_CLAMP;
            end
            S_CLAMP: begin
                ci0 <= bi0 < 0 ? 13'sd0 : bi0;
                ci1 <= bi1 > 13'sd319 ? 13'sd319 : bi1;
                cj0 <= bj0 < 0 ? 13'sd0 : bj0;
                cj1 <= bj1 > 13'sd179 ? 13'sd179 : bj1;
                state <= S_LOAD;
            end
            S_LOAD:
                if (box_empty)
                    state <= S_IDLE;
                else begin
                    i0 <= ci0[8:0]; i1 <= ci1[8:0]; j0 <= cj0[7:0];
                    j1 <= cj1[7:0]; i <= ci0[8:0]; j <= cj0[7:0];
                    row_addr <= {cj0[7:0], 8'd0} + {2'd0, cj0[7:0], 6'd0} +
                                {7'd0, ci0[8:0]};
                    addr <= {cj0[7:0], 8'd0} + {2'd0, cj0[7:0], 6'd0} +
                            {7'd0, ci0[8:0]};
                    state <= S_EDGE;
                end
            S_EDGE: begin
                for (k = 0; k < 3; k = k + 1) begin
                    dx[k] <= vx[(k + 1) % 3] - vx[k];
                    dy[k] <= vy[(k + 1) % 3] - vy[k];
                    ox[k] <= $signed({5'd0, i0, 4'd8}) - vx[k];
                    oy[k] <= $signed({6'd0, j0, 4'd8}) - vy[k];
                end
                state <= S_TRIPLE;
            end
            S_TRIPLE: begin
                for (k = 0; k < 3; k = k + 1) begin
                    dy3[k] <= dy[k] * 3;
                    dx3[k] <= dx[k] * 3;
                    acc_x[k] <= 0; acc_y[k] <= 0;
                    step_x[k] <= dy[k] <<< 4;
                    step_y[k] <= -(dx[k] <<< 4);
                end
                digit <= 8;
                state <= S_MUL;
            end
            S_MUL: begin
                for (k = 0; k < 3; k = k + 1) begin
                    acc_x[k] <= (acc_x[k] <<< 2) +
                                radix4(ox[k], digit, dy[k], dy3[k]);
                    acc_y[k] <= (acc_y[k] <<< 2) +
                                radix4(oy[k], digit, dx[k], dx3[k]);
                end
                if (digit == 0) state <= S_FIN;
                digit <= digit - 1'b1;
            end
            S_FIN: begin
                for (k = 0; k < 3; k = k + 1) begin
                    e[k] <= acc_x[k] - acc_y[k];
                    e_row[k] <= acc_x[k] - acc_y[k];
                end
                // S and its multiples, the thresholds the weights are
                // counted against, from the first pixel's edge functions.
                s_reg <= acc_x[0] - acc_y[0] + acc_x[1] - acc_y[1] +
                         acc_x[2] - acc_y[2];
                s2_reg <= (acc_x[0] - acc_y[0] + acc_x[1] - acc_y[1] +
                           acc_x[2] - acc_y[2]) <<< 1;
                s3_reg <= ((acc_x[0] - acc_y[0] + acc_x[1] - acc_y[1] +
                            acc_x[2] - acc_y[2]) <<< 1) +
                          (acc_x[0] - acc_y[0] + acc_x[1] - acc_y[1] +
                           acc_x[2] - acc_y[2]);
                pal_step <= 0;
                state <= S_PAL;
            end
            S_PAL: begin
                // The three corners' palette entries, in the five bits a
                // channel. A read answers the cycle after it is asked for, so
                // the address of the one after is given as each arrives.
                case (pal_step)
                    3'd0: pal_addr <= c0_e;
                    3'd1: pal_addr <= c1_e;
                    3'd2: begin pal_addr <= c2_e; c0_c <= pal_q[15:0]; end
                    3'd3: c1_c <= pal_q[15:0];
                    default: begin
                        c2_c <= pal_q[15:0];
                        we1_r <= 0;
                        phase <= 0;
                        last_p <= 0;
                        state <= S_SCAN;
                    end
                endcase
                pal_step <= pal_step + 1'b1;
            end
            S_SCAN: begin
                // Two clocks a pixel. The first takes this pixel's weights
                // and its coverage and address, and steps the edge functions
                // on; the second mixes its colour, from the weights just
                // registered, and gives that colour to the table. A pixel's
                // entry comes back a clock later, so the pixel written here
                // is the one before: its colour was addressed in the last
                // cycle, and it is written once, in the first phase.
                if (phase && we1_r) begin
                    we <= 1; waddr <= a1_r; wdata <= lut_q[7:0];
                end
                if (!phase) begin
                    aw_r <= aw;
                    bw_r <= bw;
                    covered_r <= covered;
                    addr_r <= addr;
                    if (covered)
                        pixels <= pixels + 1'b1;
                    if (i == i1) begin
                        if (j == j1)
                            last_p <= 1;
                        else begin
                            j <= j + 1'b1; i <= i0;
                            row_addr <= row_addr + 16'd320;
                            addr <= row_addr + 16'd320;
                            for (k = 0; k < 3; k = k + 1) begin
                                e_row[k] <= e_row[k] + step_y[k];
                                e[k] <= e_row[k] + step_y[k];
                            end
                        end
                    end else begin
                        i <= i + 1'b1; addr <= addr + 1'b1;
                        for (k = 0; k < 3; k = k + 1)
                            e[k] <= e[k] + step_x[k];
                    end
                end else begin
                    lut_addr <= mixed;
                    we1_r <= covered_r;
                    a1_r <= addr_r;
                    if (last_p) begin
                        state <= S_DRAIN;
                        drain <= 2'd2;
                    end
                end
                phase <= ~phase;
            end
            S_DRAIN: begin
                // The last pixel's entry arrives a clock after its colour
                // went to the table: the first of these two clocks lets it
                // arrive, the second writes it.
                if (drain <= 1 && we1_r) begin
                    we <= 1; waddr <= a1_r; wdata <= lut_q[7:0];
                end
                if (drain <= 1) begin
                    we1_r <= 0;
                    state <= S_IDLE;
                end else
                    drain <= drain - 1'b1;
            end
            default: state <= S_IDLE;
            endcase
        end
    end

    // ---- Frame buffers: one write port (the engine, into the target),
    // one read port each (the line fetch of the shown buffer, or the CPU's
    // read-back of the target) ----
    reg [7:0] fb0 [0:PIXELS - 1];
    reg [7:0] fb1 [0:PIXELS - 1];
    wire [15:0] raddr0, raddr1;
    reg [7:0] q0 = 0, q1 = 0;
    always @(posedge clk) begin
        if (we && !target) fb0[waddr] <= wdata;
        if (we && target) fb1[waddr] <= wdata;
        q0 <= fb0[raddr0];
        q1 <= fb1[raddr1];
    end

    // ---- Line fetch: 320 bytes of the shown buffer as 160 halfwords ----
    reg fetching = 0, f_buf = 0, f_valid = 0;
    reg [8:0] f_x = 0;
    reg [15:0] f_addr = 0;
    reg [7:0] f_even = 0;
    reg f_odd = 0;
    reg [7:0] f_index = 0;
    reg f_last = 0;
    wire [7:0] f_q = f_buf ? q1 : q0;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            fetching <= 0; f_valid <= 0; vvalid <= 0; vdone <= 0;
            vindex <= 0; vdata <= 0;
        end else begin
            vvalid <= 0; vdone <= 0;
            f_valid <= fetching;
            f_odd <= f_x[0];
            f_index <= f_x[8:1];
            f_last <= f_x == 9'd319;
            if (vstart && !fetching) begin
                fetching <= 1; f_buf <= vaddr[17]; f_x <= 0;
                f_addr <= {vaddr[16:9], 8'd0} + {2'd0, vaddr[16:9], 6'd0};
            end else if (fetching) begin
                f_addr <= f_addr + 1'b1;
                f_x <= f_x + 1'b1;
                if (f_x == 9'd319) fetching <= 0;
            end
            if (f_valid) begin
                if (!f_odd)
                    f_even <= f_q;
                else begin
                    vvalid <= 1; vindex <= f_index; vdata <= {f_q, f_even};
                    vdone <= f_last;
                end
            end
        end
    end

    // ---- Frame checksum - continued ----
    // A byte a clock: eight reflected steps at once, the work the table does
    // without a table to initialise. The scan reads the target buffer through
    // the same port the CPU's read-back uses, so the line fetch keeps its
    // priority and the scan waits whenever the buffer it is reading is the
    // one being shown. Nothing is added to the frame: the program reads the
    // result a frame later instead of waiting for it.
    localparam [31:0] CRC_POLY = 32'hEDB88320;
    wire [7:0] crc_byte = crc_buf ? q1 : q0;
    wire crc_owns = crc_scanning && !(fetching && f_buf == crc_buf);
    reg crc_own_q = 0, crc_own_qq = 0;
    reg [7:0] crc_d = 0;
    reg [1:0] crc_wait = 0;

    function automatic [31:0] crc_step8(input [31:0] c, input [7:0] b);
        reg [31:0] x;
        integer n;
        begin
            x = c ^ {24'd0, b};
            for (n = 0; n < 8; n = n + 1)
                x = {1'b0, x[31:1]} ^ (x[0] ? CRC_POLY : 32'd0);
            crc_step8 = x;
        end
    endfunction

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            crc_reg <= 32'hffffffff; crc_addr <= 0; crc_scanning <= 0;
            crc_buf <= 0; crc_wait <= 0; nz_count <= 0; nz_latch <= 0;
            crc_own_q <= 0; crc_own_qq <= 0; crc_d <= 0;
        end else begin
            crc_own_q <= crc_owns;
            crc_own_qq <= crc_own_q;
            crc_d <= crc_byte;
            if (w_crc) begin
                crc_reg <= hwdata;      // the state the run has reached
                crc_addr <= 0;
                nz_count <= 0;
                crc_buf <= target;
                crc_scanning <= 1;
                crc_wait <= 2;
            end else if (crc_scanning) begin
                if (crc_wait != 0)
                    crc_wait <= crc_wait - 1'b1;
                else if (crc_own_qq && crc_own_q) begin
                    // crc_d is the byte for crc_addr: the port was ours for
                    // the two cycles that read it, address held.
                    crc_reg <= crc_step8(crc_reg, crc_d);
                    if (crc_addr == PIXELS - 1) begin
                        nz_latch <= nz_count + (crc_d != 0 ? 1'b1 : 1'b0);
                        crc_scanning <= 0;
                    end else begin
                        nz_count <= nz_count + (crc_d != 0 ? 1'b1 : 1'b0);
                        crc_addr <= crc_addr + 1'b1;
                        crc_wait <= 2;
                    end
                end
            end
        end
    end

    // The line fetch owns the shown buffer's read port while it runs, and a
    // scan owns it otherwise; the CPU's read-back waits for both.
    assign cpu_rd_grant = !(fetching && f_buf == target) && !crc_scanning;
    assign cpu_q = target ? q1 : q0;
    assign raddr0 = (fetching && !f_buf) ? f_addr
                   : (crc_scanning ? crc_addr : cpu_raddr);
    assign raddr1 = (fetching && f_buf) ? f_addr
                   : (crc_scanning ? crc_addr : cpu_raddr);
endmodule
