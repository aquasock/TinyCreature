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
//   0x3c BUSY    read: bus cycles setup or the fill was working, free-running:
//                how much of a frame the fabric itself took, not counting
//                clocks spent waiting for the CPU's next word
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
//   TEX   13 words: 4 << 28 | tile << 16, the three corners as a TRI's, then
//         the value at the first pixel of the clamped bounding box and the
//         step a pixel across and a row down of three planes: the tile's u,
//         its v and the reciprocal of depth, which the fill steps and divides.
//   VTX   3 words: 5 << 28 | slot << 18 | colour, then y << 16 | x, then D:
//         a shaded vertex into slot 0 to 1023 of the vertex store, D being its
//         depth, (1 << 30) / z, below 2^24.
//   VTXT  3 words: 6 << 28 | slot << 18 | tile << 12 | v << 2, then
//         y << 16 | x, then u << 22 | z: a textured vertex, u and v in Q4
//         texels below 1024 and z the Q4 camera-space depth, 128 or more and
//         below 2^22. The store keeps the corner's three plane values,
//         (u << 20) / z, (v << 20) / z and (1 << 20) / z, and its depth
//         (1 << 30) / z, divided here.
//   TRIV  1 word: 3 << 30 | a << 20 | b << 10 | c: the shaded triangle of
//         three stored vertices, drawn as the TRI of their corners and
//         colours would be.
//   TEXV  1 word: 2 << 30 | a << 20 | b << 10 | c: the textured triangle of
//         three stored vertices, in the tile of the first. The planes a TEX
//         would carry are worked out here by the arithmetic tex_plane in
//         firmware/terrain/terrain.c does, divide for divide and to the same
//         truncation, so it draws the TEX the program would have sent.
//         Commands run in order, so a slot may be written again as soon as
//         the triangles that name it have been sent.
// A TRIV or TEXV triangle carries a plane of its corners' D, worked out the
// way TEXV's planes are, and is tested against a depth buffer of one 18-bit
// value a pixel: a covered pixel is written, with its depth, only when its D
// >> 6, held to 18 bits, is no less than the buffer's, so the nearer wins and
// a tie goes to the later triangle. ROWS writes depth 0 as it fills, which
// clears the buffer each frame; TRI, TEX and CARD test nothing and write no
// depth, and neither does a transparent texel.
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

    // ---- Command FIFO, 512 x 36 in one block RAM ----
    // Bit 35 of each word says whether it is the last word of its command.
    // The writer knows a command's length from the opcode word it pushes and
    // counts the words out as it goes, so the assembler reads the answer
    // beside the word instead of decoding a length and comparing it on the
    // block RAM's output, which was this design's longest bus path.
    reg [35:0] fifo [0:511];
    reg [9:0] wr_ptr = 0, rd_ptr = 0;
    reg [3:0] wr_rem = 0;
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
    // A command's length in words, read off its opcode word.
    function automatic [3:0] op_len(input [3:0] op);
        case (op)
            4'd1: op_len = 4'd4;
            4'd3: op_len = 4'd5;
            4'd4: op_len = 4'd13;
            4'd5: op_len = 4'd3;
            4'd6: op_len = 4'd3;
            default: op_len = 4'd1;
        endcase
    endfunction
    // Words left in the command being written, this one included. A zero
    // count means this push starts one and reads its length from the opcode.
    wire [3:0] wr_left = wr_rem == 0 ? op_len(hwdata[31:28]) : wr_rem;
    wire wr_last = wr_left == 1;
    always @(posedge clk) begin
        if (push) fifo[wr_ptr[8:0]] <= {wr_last, 3'd0, hwdata};
        if (pop) fifo_q <= fifo[rd_ptr[8:0]];
    end
    always @(posedge clk or negedge resetn)
        if (!resetn) begin wr_ptr <= 0; wr_rem <= 0; end
        else if (push) begin
            wr_ptr <= wr_ptr + 1'b1;
            wr_rem <= wr_left - 1'b1;
        end

    // ---- Bus slave ----
    reg target = 0, err2 = 0, w_ctrl = 0, w_rb = 0, w_crc = 0, r_fb = 0;
    reg w_land = 0, w_land_addr = 0, r_land = 0, r_land_wait = 0;
    // The walker's controls, the block bitset and its cell FIFO. The cell
    // entries are {14'd0, front, gz[7:0], gx[8:0]}.
    reg [15:0] wcx = 0, wcz = 0, wcells_x = 0, wcells_z = 0;
    reg [2:0] wshow_a = 0;
    reg [223:0] wshown = 0;
    reg walk_go = 0, w_walk = 0;
    reg [2:0] walk_wreg = 0;
    reg r_wfifo = 0, r_wfifo_wait = 0;
    reg [31:0] wfifo_q = 0;
    reg [8:0] wfifo_wr = 0, wfifo_rd = 0;
    (* ram_style = "block" *) reg [31:0] wfifo [0:255];
    reg [2:0] wstate = 0;
    reg [15:0] wz_lo = 0, wz_hi = 0, wx_lo = 0, wx_hi = 0;
    reg [15:0] wgz = 0, wgx = 0, wrow_base = 0, wcount = 0, wcell = 0;
    reg [9:0] wblock = 0;
    reg wfront = 0;
    localparam W_IDLE = 0, W_Z = 1, W_X = 2, W_FLAG = 3, W_DONE = 4;
    // terrain.c's farther(): the end farther from the camera cell, moving
    // toward it. The differences are 17-bit signed so the comparison is
    // exact for any grid this store holds.
    wire signed [16:0] xda = $signed({1'b0, wcx}) - $signed({1'b0, wx_lo});
    wire signed [16:0] xdb = $signed({1'b0, wx_hi}) - $signed({1'b0, wcx});
    wire [16:0] xaa = xda[16] ? -xda : xda;
    wire [16:0] xab = xdb[16] ? -xdb : xdb;
    wire xpick_lo = xaa >= xab;
    wire signed [16:0] zda = $signed({1'b0, wcz}) - $signed({1'b0, wz_lo});
    wire signed [16:0] zdb = $signed({1'b0, wz_hi}) - $signed({1'b0, wcz});
    wire [16:0] zaa = zda[16] ? -zda : zda;
    wire [16:0] zab = zdb[16] ? -zdb : zdb;
    wire zpick_lo = zaa >= zab;
    wire [15:0] wcell_now = wrow_base + (xpick_lo ? wx_lo : wx_hi);
    always @(posedge clk)
        wfifo_q <= wfifo[wfifo_rd[7:0]];
    reg [1:0] r_byte = 0;
    reg r_issued = 0;
    reg [31:0] r_data = 0;
    reg [31:0] tris = 0, pixels = 0, stalls = 0, busy_cycles = 0;
    // The frame checksum: a reflected CRC-32 over the target buffer in
    // address order, seeded by the CPU. The program chains a run's frames
    // through it exactly as tc_crc32(crc, frame, bytes) chains them, so the
    // value it ends with is the one terrain_host computes from the same
    // file.
    reg [31:0] crc_reg = 32'hffffffff;
    reg [15:0] nz_count = 0, nz_latch = 0;
    reg [15:0] crc_addr = 0;
    reg crc_scanning = 0, crc_buf = 0;
    wire busy, working;
    wire accept = hready_in && hsel && htrans[1];
    wire word = hsize == 3'd2 && haddr[1:0] == 0;
    wire [4:0] reg_index = haddr[6:2];
    wire is_reg = haddr[14:7] == 0;
    wire is_fb = is_reg && !hwrite && reg_index == 9;
    // The register window is now 128 bytes: the old 0x00 to 0x3c keep their
    // indices, and the land's two registers sit at 0x40 and 0x44.
    wire ok = word && is_reg &&
              (hwrite ? ((reg_index <= 1) ||
                         (reg_index >= 7 && reg_index <= 8) ||
                         (reg_index >= 11 && reg_index <= 14) ||
                         (reg_index >= 16 && reg_index <= 23))
                      : ((reg_index >= 1 && reg_index <= 7) ||
                         reg_index == 9 || reg_index == 10 ||
                         reg_index == 15 || reg_index == 17 ||
                         (reg_index >= 24 && reg_index <= 26)));
    // The CPU's read port request, served when the line fetch leaves it.
    reg cpu_rd = 0;
    wire cpu_rd_grant;
    reg [15:0] cpu_raddr = 0;
    wire [7:0] cpu_q;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            hready <= 1; hresp <= 0; hrdata <= 0; err2 <= 0; w_fifo <= 0;
            w_ctrl <= 0; w_crc <= 0; r_fb <= 0; show <= 0; target <= 0;
            stalls <= 0; cpu_rd <= 0; r_issued <= 0; busy_cycles <= 0;
            w_land <= 0; w_land_addr <= 0; r_land <= 0; r_land_wait <= 0;
            walk_go <= 0; w_walk <= 0; r_wfifo <= 0; r_wfifo_wait <= 0;
            wfifo_rd <= 0;
        end else begin
            if (working) busy_cycles <= busy_cycles + 1'b1;
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
            end else if (w_land_addr) begin
                w_land_addr <= 0; hready <= 1;
            end else if (w_land) begin
                w_land <= 0; hready <= 1;
            end else if (r_land) begin
                // The store loads land_q on this edge; the data phase
                // follows one clock later.
                r_land <= 0; r_land_wait <= 1;
            end else if (r_land_wait) begin
                hrdata <= land_rmode
                          ? (land_fraw >> (8 * land_rsel)) & 16'h00ff
                          : (land_rsel[0] ? land_vraw[31:16]
                                          : land_vraw[15:0]);
                hready <= 1; r_land_wait <= 0;
            end else if (w_walk) begin
                w_walk <= 0; hready <= 1;
                case (walk_wreg)
                    3'd0: wcx <= hwdata[15:0];
                    3'd1: wcz <= hwdata[15:0];
                    3'd2: begin
                        wcells_x <= hwdata[15:0];
                        wcells_z <= hwdata[31:16];
                    end
                    3'd3: wshow_a <= hwdata[2:0];
                    3'd4: wshown[{wshow_a, 5'd0} +: 32] <= hwdata;
                    3'd5: begin
                        walk_go <= hwdata[0];
                        wfifo_rd <= 0;
                    end
                endcase
            end else if (walk_go) begin
                walk_go <= 0;
            end else if (r_wfifo) begin
                wfifo_rd <= wfifo_rd + 1'b1;
                r_wfifo <= 0; r_wfifo_wait <= 1;
            end else if (r_wfifo_wait) begin
                hrdata <= wfifo_q; hready <= 1; r_wfifo_wait <= 0;
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
                        15: hrdata <= busy_cycles;
                        24: hrdata <= {28'd0, wfull, wempty, wdone, wbusy};
                        26: hrdata <= {16'd0, wcount};
                        default: hrdata <= 0;
                    endcase
                if (accept) begin
                    if (!ok) begin
                        hready <= 0; hresp <= 1; err2 <= 1;
                    end else if (is_fb) begin
                        hready <= 0; r_fb <= 1; r_byte <= 0; cpu_rd <= 1;
                    end else if (!hwrite && reg_index == 17) begin
                        hready <= 0; r_land <= 1;
                    end else if (hwrite && reg_index == 16) begin
                        hready <= 0; w_land_addr <= 1;
                    end else if (hwrite && reg_index == 17) begin
                        hready <= 0; w_land <= 1;
                    end else if (!hwrite && reg_index == 25) begin
                        hready <= 0; r_wfifo <= 1;
                    end else if (hwrite && reg_index >= 18 && reg_index <= 23) begin
                        hready <= 0; w_walk <= 1;
                        walk_wreg <= reg_index[2:0] - 3'd2;
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
    reg [3:0] got = 0;
    reg q_valid = 0;
    reg cmd_full = 0;
    reg [3:0] cmd_op = 0;
    reg [31:0] cmd_w0 = 0;      // the opcode word whole, for the store's fields
    // The assembler's own write into the vertex store, for a shaded vertex.
    reg asm_we = 0;
    reg [9:0] asm_waddr = 0;
    reg [143:0] asm_wdata = 0;
    wire vst_busy;
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
    // A textured triangle's nine plane numbers, after its three corners: the
    // value of each plane at the first pixel of the clamped bounding box and
    // its step a Q4 unit across and down, for u, v and the reciprocal of the
    // camera-space depth in that order.
    reg signed [31:0] cmd_p [0:8];
    wire take;
    // The writer marked each command's last word, so the word arriving says
    // whether it is the last.
    wire completing = q_valid && fifo_q[35];
    // A shaded vertex goes into the store from here, without setup, unless
    // setup is reading slots or finishing a textured vertex: those are the
    // commands ahead of it a write could overtake. Then it waits for setup
    // like any other command. A vertex is three words, so its last word is
    // never the first and cmd_op holds its opcode.
    wire vtx_direct = completing && got != 0 && cmd_op == 4'd5 && !vst_busy;
    // Words are fetched one a clock while a command is being gathered; the
    // last word of one that goes to setup stops the fetch until setup has
    // taken it, and the last word of a vertex written from here does not.
    assign pop = !cmd_full && !fifo_empty &&
                 (completing ? vtx_direct : 1'b1);
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            got <= 0; q_valid <= 0; cmd_full <= 0;
            rd_ptr <= 0; asm_we <= 0;
        end else begin
            q_valid <= pop;
            asm_we <= 1'b0;
            if (take) cmd_full <= 0;
            // rd_ptr moves with each pop, so fifo_empty already counts
            // the words in flight.
            if (pop) rd_ptr <= rd_ptr + 1'b1;
            if (q_valid) begin
                if (got == 0) begin
                    cmd_op <= fifo_q[31:28]; cmd_colour <= fifo_q[7:0];
                    cmd_w0 <= fifo_q[31:0];
                    cmd_first <= fifo_q[15:8]; cmd_end <= fifo_q[23:16];
                    if (fifo_q[31:28] == 4'd1) begin
                        cmd_c1 <= fifo_q[15:8]; cmd_c2 <= fifo_q[23:16];
                    end else if (fifo_q[31:28] == 4'd3 || fifo_q[31:28] == 4'd4)
                        cmd_tile <= fifo_q[23:16];
                end else begin
                    // A textured triangle's three corner words are read the
                    // way a triangle's are, and its nine plane words after
                    // them, whole. A vertex's corner word lands where a
                    // triangle's first corner does, and a textured one's u
                    // and depth word in the second corner's fields, split in
                    // half.
                    if (cmd_op == 4'd4 && got > 4'd3) begin
                        cmd_p[got - 4] <= fifo_q;
                    end else begin
                        cmd_x[got - 1] <= fifo_q[15:0];
                        cmd_y[got - 1] <= fifo_q[31:16];
                    end
                end
                if (completing) begin
                    if (vtx_direct) begin
                        asm_we <= 1'b1;
                        asm_waddr <= cmd_w0[27:18];
                        asm_wdata <= {cmd_x[0], cmd_y[0], cmd_w0[7:0], 6'd0,
                                      24'd0, 24'd0, 14'd0, fifo_q[23:0], 12'd0};
                    end else
                        cmd_full <= 1;
                    got <= 0;
                end else
                    got <= got + 1'b1;
            end
        end
    end
    // A word is fetched every clock until the flag says the command is whole;
    // a vertex written from here does not stop the fetch.

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
    // The art's transparent key, palette-relative texel 0. The fill does not
    // write it and does not count it, which is what makes a card a cutout.
    localparam [7:0] TEX_KEY = 8'd0;
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

    // ---- The land, packed for the walker ----
    // A vertex is one 16-bit word, {colour, altitude}; a cell's three flag
    // bits -- split, first triangle, second triangle -- are one nibble, two
    // cells a byte. Sized for the accepted Celtic grid, 240 by 224 cells;
    // Land 1's smaller grid fits the same stores. The walker is not here
    // yet, so nothing reads these but the upload's own read-back.
    localparam LAND_VX = 241, LAND_VZ = 225;
    localparam LAND_CX = 240, LAND_CZ = 224;
    localparam LAND_VERTICES = LAND_VX * LAND_VZ;   // 54,225
    localparam LAND_CELLS = LAND_CX * LAND_CZ;      // 53,760
    localparam LAND_VERTEX_WORDS = (LAND_VERTICES + 1) / 2;
    localparam LAND_FLAG_WORDS = (LAND_CELLS + 7) / 8;
    // One 32-bit word a write, so the memory has a single write port: two
    // vertex words a word, or eight cells' nibbles. The odd last vertex's
    // high half is zero.
    (* ram_style = "block" *) reg [31:0] land_v [0:LAND_VERTEX_WORDS - 1];
    (* ram_style = "block" *) reg [31:0] land_f [0:LAND_FLAG_WORDS - 1];
    // No initial value on these pointers: the block-RAM mapper refuses a read
    // address register with one, and the first LAND_ADDR write sets them.
    reg [16:0] land_waddr, land_raddr;
    // During a walk's cell step the flag word comes from the walker's cell;
    // otherwise from the bus read-back's byte address.
    wire [13:0] land_f_ra = wstate == W_X
                            ? {1'b0, wcell_now[15:3]}
                            : wstate == W_FLAG
                              ? {1'b0, wcell[15:3]} : land_raddr[15:2];
    // The memories' own output registers, directly fed so the mapper can use
    // the block RAM's output flip-flops; the byte or half selection is made
    // in the bus cycle after, from these.
    reg [31:0] land_vraw = 0, land_fraw = 0;
    reg land_rmode = 0;
    reg [1:0] land_rsel = 0;
    // A LAND_ADDR write sets both pointers; bit 16 picks flags over vertices.
    // A LAND_DATA write takes one 32-bit word and moves the write pointer; a
    // LAND_DATA read returns one 16-bit vertex or one flag byte and moves the
    // read pointer by that unit.
    always @(posedge clk) begin
        if (w_land_addr) begin
            land_waddr <= {hwdata[16], hwdata[15:0]};
            land_raddr <= {hwdata[16], hwdata[15:0]};
        end
        if (w_land) begin
            if (land_waddr[16]) begin
                land_f[land_waddr[15:2]] <= hwdata;
                land_waddr <= land_waddr + 17'd4;
            end else begin
                land_v[land_waddr[15:1]] <= hwdata;
                land_waddr <= land_waddr + 17'd2;
            end
        end
        if (r_land) begin
            land_vraw <= land_v[land_raddr[15:1]];
            land_rmode <= land_raddr[16];
            land_rsel <= land_raddr[1:0];
            land_raddr <= land_raddr + 1'b1;
        end
        land_fraw <= land_f[land_f_ra];
    end

    // ---- The walker: terrain.c's far-to-near cell order ----
    // Rows farthest from the camera row first, and in each row the columns
    // farthest from its column first. A cell in a shown block whose flags
    // carry either triangle is pushed to the FIFO with its front, gx and gz;
    // the walk stalls when the FIFO is full and the test drains it.
    wire [8:0] wlevel = wfifo_wr - wfifo_rd;
    wire wempty = wlevel == 0;
    wire wfull = wlevel[8];
    wire wbusy = wstate != W_IDLE && wstate != W_DONE;
    wire wdone = wstate == W_DONE;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wstate <= W_IDLE; wfifo_wr <= 0; wcount <= 0;
        end else if (walk_go) begin
            wstate <= W_Z; wfifo_wr <= 0; wcount <= 0;
            wz_lo <= 0; wz_hi <= wcells_z - 1'b1;
        end else case (wstate)
            W_Z: if (wz_lo > wz_hi)
                     wstate <= W_DONE;
                 else begin
                     wgz <= zpick_lo ? wz_lo : wz_hi;
                     if (zpick_lo) wz_lo <= wz_lo + 1'b1;
                     else wz_hi <= wz_hi - 1'b1;
                     wfront <= (zpick_lo ? wz_lo : wz_hi) < wcz ? 1'b0 : 1'b1;
                     wrow_base <= (zpick_lo ? wz_lo : wz_hi) * wcells_x;
                     wx_lo <= 0; wx_hi <= wcells_x - 1'b1;
                     wstate <= W_X;
                 end
            W_X: if (wx_lo > wx_hi)
                     wstate <= W_Z;
                 else begin
                     wgx <= xpick_lo ? wx_lo : wx_hi;
                     if (xpick_lo) wx_lo <= wx_lo + 1'b1;
                     else wx_hi <= wx_hi - 1'b1;
                     wcell <= wcell_now;
                     wblock <= ((wgz >> 4) * (wcells_x >> 4)) +
                               ((xpick_lo ? wx_lo : wx_hi) >> 4);
                     wstate <= W_FLAG;
                 end
            W_FLAG: if (!wshown[wblock])
                         wstate <= W_X;
                     else if (((land_fraw >> (4 * wcell[2:0])) & 7) & 6) begin
                         if (!wfull) begin
                             wfifo[wfifo_wr[7:0]] <=
                                 {14'd0, wfront, wgz[7:0], wgx[8:0]};
                             wfifo_wr <= wfifo_wr + 1'b1;
                             wcount <= wcount + 1'b1;
                             wstate <= W_X;
                         end
                     end else
                         wstate <= W_X;
            W_DONE: ;
            default: wstate <= W_DONE;
        endcase
    end

    // ---- The vertex store: 1024 slots of 144 bits, four 36-bit block RAMs
    // wide ----
    // A slot holds the corner's Q4 screen position, its palette entry, the
    // tile, the three plane values a textured corner carries and its depth:
    //   [143:128] x  [127:112] y  [111:104] colour  [103:98] tile
    //   [97:74] (u << 20) / z  [73:50] (v << 20) / z  [49:36] (1 << 20) / z
    //   [35:12] (1 << 30) / z
    // The engine writes a slot as it takes the vertex command and reads the
    // three a triangle names one after another, each a clock after its
    // address, which is the same shape the tile store has.
    (* ram_style = "block" *) reg [143:0] vstore [0:1023];
    reg vst_we = 0;
    reg [9:0] vst_waddr = 0, vst_raddr = 0;
    reg [143:0] vst_wdata = 0, vst_q = 0;
    // Setup and the assembler never write in the same clock: the assembler
    // holds back while setup could (vst_busy), and setup's own vertex write
    // is a command the assembler had to stop for.
    always @(posedge clk) begin
        if (vst_we) vstore[vst_waddr] <= vst_wdata;
        else if (asm_we) vstore[asm_waddr] <= asm_wdata;
        vst_q <= vstore[vst_raddr];
    end

    // ---- Engine ----
    localparam S_IDLE = 0, S_ROWS = 1, S_BOX = 2, S_CLAMP = 3, S_LOAD = 4,
               S_EDGE = 5, S_TRIPLE = 6, S_MUL = 7, S_FIN = 8, S_PAL = 9,
               S_SCAN = 10, S_DRAIN = 11, S_CARD = 12,
               S_TEXDIV = 13, S_TEXW = 14,
               S_VDIV = 15, S_VWR = 16, S_VRD = 17,
               S_TP0 = 18, S_TPMUL = 19, S_TPN = 20, S_TPDIV = 21,
               S_TPSIGN = 22, S_TPG3 = 23, S_TPORG = 24, S_TPFIN = 25,
               S_HAND = 26, S_TPSH = 27, S_TPSH2 = 28;
    reg [4:0] state = S_IDLE;
    // The fill's own states. Setup and fill run side by side: setup works the
    // next command out while the fill draws the last, and hands it over in
    // S_HAND the clock the fill is free (fill_start below), which is the one
    // place a command crosses from one to the other.
    localparam F_IDLE = 0, F_ROWS = 1, F_SCAN = 2, F_DRAIN = 3, F_CARD = 4,
               F_TEXDIV = 5, F_TEXW = 6;
    reg [2:0] fstate = F_IDLE;
    localparam H_TRI = 0, H_ROWS = 1, H_CARD = 2;
    reg [1:0] hand_kind = H_TRI;
    wire fill_start = state == S_HAND && fstate == F_IDLE;
    assign vst_busy = state == S_VRD || state == S_VDIV || state == S_VWR;
    assign working = state != S_IDLE || fstate != F_IDLE;

    // ---- A textured vertex's divides ----
    // (u << 20) / z, (v << 20) / z and (1 << 20) / z, one quotient bit a
    // clock each, by long division: the numerator's bits are brought down one
    // at a time against a remainder that stays below z.
    reg [9:0] vt_slot = 0;
    reg [5:0] vt_tile = 0;
    reg signed [15:0] vt_x = 0, vt_y = 0;
    // Two quotient bits a clock, radix 4, against z, 2z and 3z. z is at least
    // 128, so a numerator's top six bits cannot reach it and go straight into
    // the remainder, which leaves twelve steps for the 24 bits a value holds.
    reg [21:0] vd_den = 0;
    reg [23:0] vd_den3 = 0;
    reg [23:0] vd_num [0:3];
    reg [21:0] vd_rem [0:3];
    reg [23:0] vd_q [0:3];
    reg [3:0] vd_bit = 0;

    // ---- A stored triangle: its slots, and what the first two held ----
    reg [9:0] vi [0:2];
    reg [2:0] vr_step = 0;
    reg signed [15:0] cap_x [0:1];
    reg signed [15:0] cap_y [0:1];
    reg [7:0] cap_c [0:1];
    reg [5:0] cap_tile = 0;
    reg [23:0] cap_u [0:1];
    reg [23:0] cap_v [0:1];
    reg [13:0] cap_r [0:1];
    reg [23:0] cap_d [0:1];
    // A TEXV triangle has its planes worked out after its edges are set up;
    // a TEX one brought them in its command.
    reg tex_setup = 0;
    // The three corners' plane values, u, v and 1/z.
    reg [23:0] pu [0:2];
    reg [23:0] pv [0:2];
    reg [13:0] pr [0:2];
    reg [23:0] pd [0:2];
    // A stored triangle carries a depth plane and is tested against the depth
    // buffer; one sent whole does neither.
    reg zplane = 0;
    reg signed [31:0] zd0 = 0, zd_s = 0, zd_j = 0;

    // ---- A TEXV triangle's planes: tex_plane in hardware ----
    // For each of u, v and 1/z, with a1 and a2 the second and third corners'
    // values less the first's: gx = (a1 d2y - a2 d1y) / det and gy =
    // (a2 d1x - a1 d2x) / det, truncated towards zero; the steps are 16 gx
    // and 16 gy and the value at the first pixel is the first corner's value
    // plus ox gx plus oy gy, all of it kept to its low 32 bits as the C keeps
    // it. d1 is the first edge, dx[0] and dy[0]; d2 runs from the first
    // corner to the third, the third edge reversed; and det is -S, which the
    // edge setup has already summed. Twelve products in one pass of the
    // multiplier's nine digits, six long divisions side by side, then six
    // products of the origin offsets, low 32 bits only.
    reg signed [47:0] ta1 [0:3];
    reg signed [47:0] ta2 [0:3];
    reg signed [47:0] ta1x3 [0:3];
    reg signed [47:0] ta2x3 [0:3];
    reg signed [47:0] macc [0:15];
    reg [41:0] dv_num [0:7];
    reg [34:0] dv_rem [0:7];
    reg [31:0] dv_q [0:7];
    reg dv_neg [0:7];
    reg [35:0] dv_den = 0;
    reg [37:0] dv_den3 = 0;
    reg det_zero = 0;
    reg [5:0] dv_bit = 0;
    reg tp_triple = 0;   // the multiplier's first clock makes the triples
    wire [31:0] tg [0:7];
    wire [31:0] tg3 [0:7];
    reg [31:0] oacc [0:7];

    // ---- A textured triangle's own state ----
    // The three planes the fill steps -- the tile's u, its v and the
    // reciprocal of the camera-space depth -- each as its value at the first
    // pixel of the triangle's clamped bounding box and its step a Q4 unit
    // across and down, all worked out by the caller. The fill adds, divides
    // the first two by the third, and writes the texel that names; the
    // quotient is what makes the mapping projective where a weight of the
    // corners would make it affine and wrong between them.
    reg tex_on = 0;
    reg [5:0] tex_tile = 0;
    reg signed [31:0] tex_a = 0, tex_b = 0, tex_c = 0;
    reg signed [31:0] tex_arow = 0, tex_brow = 0, tex_crow = 0;
    reg signed [31:0] tex_as = 0, tex_bs = 0, tex_cs = 0;
    reg signed [31:0] tex_aj = 0, tex_bj = 0, tex_cj = 0;
    // The fill's depth: the plane and whether this triangle tests against the
    // buffer, this pixel's depth, and the write the pixel before will make.
    reg fzmode = 0;
    reg signed [31:0] fd = 0, fd_row = 0, fd_s = 0, fd_j = 0;
    reg [17:0] d18_p = 0, zd1_r = 0;
    reg [17:0] tex_z = 0;   // a textured pixel's depth, held through its divide
    reg zpass_r = 0;
    reg zw1_r = 0;
    // The depth buffer, one 18-bit value a pixel of the target: read at the
    // address the scan stands on, a clock before the pass is decided, and
    // written beside the frame buffer.
    (* ram_style = "block" *) reg [17:0] zbuf [0:PIXELS - 1];
    reg [17:0] zq = 0;
    reg zwe = 0;
    reg [15:0] zwaddr = 0;
    reg [17:0] zwdata = 0;
    function automatic [17:0] depth18(input signed [31:0] v);
        begin
            if (v < 0)
                depth18 = 0;
            else if ((v >>> 6) > 32'sd262143)
                depth18 = 18'h3ffff;
            else
                depth18 = v[23:6];
        end
    endfunction
    // The depth test is taken in the scan's first phase, where d18_p and zq
    // both hold this pixel, and registered for the second: the compare then
    // ends at one register instead of fanning out to the fill's enables.
    // The fill's copies of the planes, taken at the hand-over.
    reg ftex_on = 0;
    reg [5:0] ftile = 0;
    reg signed [31:0] ftex_a = 0, ftex_b = 0, ftex_c = 0;
    reg signed [31:0] ftex_arow = 0, ftex_brow = 0, ftex_crow = 0;
    reg signed [31:0] ftex_as = 0, ftex_bs = 0, ftex_cs = 0;
    reg signed [31:0] ftex_aj = 0, ftex_bj = 0, ftex_cj = 0;
    // This pixel's three planes, latched before the step moves them on.
    reg signed [31:0] tn_a = 0, tn_b = 0, tn_c = 0;
    reg signed [31:0] tex_rem = 0, tex_q = 0;
    reg [3:0] tex_bit = 0;
    reg tex_second = 0;
    reg [1:0] tex_w = 0;
    reg signed [11:0] tex_uu = 0, tex_vv = 0;
    wire signed [31:0] tex_aden = tn_c >= 0 ? tn_c : -tn_c;
    wire tex_set = tex_rem >= (tex_aden <<< tex_bit);
    wire signed [31:0] tex_q_next = tex_set ? (tex_q | (32'd1 <<< tex_bit)) : tex_q;
    wire signed [31:0] tex_rem_next = tex_set ? tex_rem - (tex_aden <<< tex_bit) : tex_rem;
    wire signed [11:0] tex_u_texel = tex_uu >>> 4;
    wire signed [11:0] tex_v_texel = tex_vv >>> 4;
    wire [4:0] tex_tu = tex_u_texel < 0 ? 5'd0 :
                        (tex_u_texel > 12'sd31 ? 5'd31 : tex_u_texel[4:0]);
    wire [4:0] tex_tv = tex_v_texel < 0 ? 5'd0 :
                        (tex_v_texel > 12'sd31 ? 5'd31 : tex_v_texel[4:0]);

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
    // Setup's copy of a card, which the fill takes at the hand-over.
    reg [8:0] hc_i0 = 0, hc_i1 = 0;
    reg [7:0] hc_j0 = 0, hc_j1 = 0;
    reg [15:0] hc_du = 0, hc_dv = 0, hc_u0 = 0, hc_v0 = 0, hc_addr = 0;
    reg [7:0] hc_tile = 0;
    assign take = cmd_full && state == S_IDLE;
    assign busy = !fifo_empty || pop || q_valid || cmd_full || got != 0 ||
                  state != S_IDLE || fstate != F_IDLE || w_fifo || asm_we;

    reg [7:0] colour = 0;
    reg signed [15:0] vx [0:2];
    reg signed [15:0] vy [0:2];
    reg [8:0] i0 = 0, i1 = 0;
    reg [7:0] j0 = 0, j1 = 0;
    reg [15:0] addr = 0, fill_end = 0;
    // The fill's copies of the box, the edge functions and the scan position.
    reg [7:0] fcolour = 0;
    reg [8:0] fi0 = 0, fi1 = 0, fi = 0;
    reg [7:0] fj1 = 0, fj = 0;
    reg [15:0] faddr = 0, frow_addr = 0, ffill_end = 0;
    reg signed [35:0] fe [0:2];
    reg signed [35:0] fe_row [0:2];
    reg signed [35:0] fstep_x [0:2];
    reg signed [35:0] fstep_y [0:2];
    reg signed [35:0] fs = 0, fs2 = 0, fs3 = 0;
    reg [15:0] fc0 = 0, fc1 = 0, fc2 = 0;
    reg signed [16:0] dx [0:2];
    reg signed [16:0] dy [0:2];
    reg signed [17:0] ox [0:2];
    reg signed [17:0] oy [0:2];
    reg signed [35:0] dx3 [0:2];
    reg signed [35:0] dy3 [0:2];
    reg signed [35:0] acc_x [0:2];   // dy * ox
    reg signed [35:0] acc_y [0:2];   // dx * oy
    reg signed [35:0] e [0:2];       // F at the box's first pixel
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
    wire [4:0] r0 = fc0[14:10], g0 = fc0[9:5], b0 = fc0[4:0];
    wire [4:0] r1 = fc1[14:10], g1 = fc1[9:5], b1 = fc1[4:0];
    wire [4:0] r2 = fc2[14:10], g2 = fc2[9:5], b2 = fc2[4:0];
    // The weights, in quarters: a triangle of no area has S zero, so every
    // threshold would pass and its corners would be asked for a colour the
    // mix cannot give, so its first corner colours it instead. The weight of
    // the second corner is F2 / S and of the third F0 / S, each edge function
    // measuring the corner across from it.
    wire signed [35:0] f2 = fe[2] <<< 2;
    wire signed [35:0] f0s = fe[0] <<< 2;
    wire [1:0] aw = fs > 0 ? ({1'b0, f2 >= fs} + {1'b0, f2 >= fs2} +
                              {1'b0, f2 >= fs3}) : 2'd0;
    wire [1:0] bw = fs > 0 ? ({1'b0, f0s >= fs} + {1'b0, f0s >= fs2} +
                              {1'b0, f0s >= fs3}) : 2'd0;
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

    // The edge products start at the highest digit their multipliers need,
    // top, which carries the sign; the bits above it are the sign repeated,
    // so the digits skipped would have added nothing.
    function automatic signed [35:0] radix4(input signed [17:0] b,
        input [3:0] k, input signed [35:0] a, input signed [35:0] a3,
        input [3:0] top);
        reg [1:0] d;
        begin
            d = b[2 * k +: 2];
            if (k == top)   // the top digit carries the sign: its high bit weighs -2
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

    // The same digit, on wider and on 32-bit multiplicands: the plane
    // numerators need 48 bits, and the origin products only their low 32.
    function automatic signed [47:0] radix4w(input signed [17:0] b,
        input [3:0] k, input signed [47:0] a, input signed [47:0] a3,
        input [3:0] top);
        reg [1:0] d;
        begin
            d = b[2 * k +: 2];
            if (k == top)
                case (d)
                    2'd0: radix4w = 0;
                    2'd1: radix4w = a;
                    2'd2: radix4w = -(a <<< 1);
                    default: radix4w = -a;
                endcase
            else
                case (d)
                    2'd0: radix4w = 0;
                    2'd1: radix4w = a;
                    2'd2: radix4w = a <<< 1;
                    default: radix4w = a3;
                endcase
        end
    endfunction

    function automatic [31:0] radix4n(input signed [17:0] b, input [3:0] k,
        input [31:0] a, input [31:0] a3, input [3:0] top);
        reg [1:0] d;
        begin
            d = b[2 * k +: 2];
            if (k == top)
                case (d)
                    2'd0: radix4n = 0;
                    2'd1: radix4n = a;
                    2'd2: radix4n = -(a << 1);
                    default: radix4n = -a;
                endcase
            else
                case (d)
                    2'd0: radix4n = 0;
                    2'd1: radix4n = a;
                    2'd2: radix4n = a << 1;
                    default: radix4n = a3;
                endcase
        end
    endfunction

    // These wide arithmetic banks deliberately have no clock enables. Their
    // values outside the named arithmetic states are don't-cares; updating
    // them continuously avoids a few very large, placement-hostile enable
    // nets while the first active radix digit still loads the exact value.
    integer mk;
    always @(posedge clk) begin
        for (mk = 0; mk < 4; mk = mk + 1) begin
            macc[4 * mk] <= (digit == mul_top ? 48'sd0 :
                (macc[4 * mk] <<< 2)) +
                radix4w({dy[2][16], dy[2]}, digit, ta1[mk], ta1x3[mk], mul_top);
            macc[4 * mk + 1] <= (digit == mul_top ? 48'sd0 :
                (macc[4 * mk + 1] <<< 2)) +
                radix4w({dy[0][16], dy[0]}, digit, ta2[mk], ta2x3[mk], mul_top);
            macc[4 * mk + 2] <= (digit == mul_top ? 48'sd0 :
                (macc[4 * mk + 2] <<< 2)) +
                radix4w({dx[0][16], dx[0]}, digit, ta2[mk], ta2x3[mk], mul_top);
            macc[4 * mk + 3] <= (digit == mul_top ? 48'sd0 :
                (macc[4 * mk + 3] <<< 2)) +
                radix4w({dx[2][16], dx[2]}, digit, ta1[mk], ta1x3[mk], mul_top);
        end
    end

    genvar gg;
    generate
        for (gg = 0; gg < 8; gg = gg + 1) begin : tp_gradient
            assign tg[gg] = (dv_neg[gg] ? -dv_q[gg] : dv_q[gg]) &
                            {32{!det_zero}};
            assign tg3[gg] = (dv_neg[gg] ?
                              -(dv_q[gg] + (dv_q[gg] << 1)) :
                               dv_q[gg] + (dv_q[gg] << 1)) &
                             {32{!det_zero}};
        end
    endgenerate

    integer oi;
    always @(posedge clk) begin
        for (oi = 0; oi < 4; oi = oi + 1) begin
            oacc[2 * oi] <= (digit == mul_top ? 32'd0 :
                (oacc[2 * oi] << 2)) +
                radix4n(ox[0], digit, tg[2 * oi], tg3[2 * oi], mul_top);
            oacc[2 * oi + 1] <= (digit == mul_top ? 32'd0 :
                (oacc[2 * oi + 1] << 2)) +
                radix4n(oy[0], digit, tg[2 * oi + 1], tg3[2 * oi + 1], mul_top);
        end
    end

    integer ek;
    always @(posedge clk) begin
        for (ek = 0; ek < 3; ek = ek + 1) begin
            acc_x[ek] <= (digit == mul_top ? 36'sd0 :
                         (acc_x[ek] <<< 2)) +
                         radix4(ox[ek], digit, dy[ek], dy3[ek], mul_top);
            acc_y[ek] <= (digit == mul_top ? 36'sd0 :
                         (acc_y[ek] <<< 2)) +
                         radix4(oy[ek], digit, dx[ek], dx3[ek], mul_top);
        end
    end

    // The plane numerators of each of u, v and 1/z, from the four products:
    // nx = -(a1 dy[2] + a2 dy[0]) and ny = a2 dx[0] + a1 dx[2].
    wire signed [47:0] tp_nx [0:3];
    wire signed [47:0] tp_ny [0:3];
    genvar gm;
    generate
        for (gm = 0; gm < 4; gm = gm + 1) begin : tp_num
            assign tp_nx[gm] = -(macc[4 * gm] + macc[4 * gm + 1]);
            assign tp_ny[gm] = macc[4 * gm + 2] + macc[4 * gm + 3];
        end
    endgenerate
    wire signed [35:0] s_abs = s_reg < 0 ? -s_reg : s_reg;
    // The highest digit the plane products' multipliers need, and the origin
    // products'.
    wire [3:0] tp_top = max4(max4(top_digit({dy[2][16], dy[2]}), top_digit({dy[0][16], dy[0]})),
                             max4(top_digit({dx[0][16], dx[0]}), top_digit({dx[2][16], dx[2]})));
    wire [3:0] org_top = max4(top_digit(ox[0]), top_digit(oy[0]));
    // The divides' numerators all fit below bit dv_msb + 1; the division runs
    // only the radix-4 steps that cover them.
    wire [41:0] dv_any = dv_num[0] | dv_num[1] | dv_num[2] | dv_num[3] |
                         dv_num[4] | dv_num[5] | dv_num[6] | dv_num[7];
    function automatic [5:0] msb42(input [41:0] v);
        integer b;
        begin
            msb42 = 0;
            for (b = 0; b < 42; b = b + 1)
                if (v[b]) msb42 = b;
        end
    endfunction
    reg [4:0] dv_steps = 0;

    // The least digit index whose signed pair still holds v: v fits in 2t + 2
    // signed bits.
    function automatic [3:0] top_digit(input signed [17:0] v);
        integer t;
        begin
            top_digit = 8;
            for (t = 8; t >= 0; t = t - 1)
                if ((v >>> (2 * t + 1)) == 0 || (v >>> (2 * t + 1)) == -1)
                    top_digit = t;
        end
    endfunction
    function automatic [3:0] max4(input [3:0] a, input [3:0] b);
        max4 = a > b ? a : b;
    endfunction
    reg [3:0] mul_top = 8;

    wire covered = !fe[0][35] && !fe[1][35] && !fe[2][35];
    // ---- Setup: commands in, a triangle, rows or card ready for the fill ----
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= S_IDLE; tris <= 0; vst_we <= 0; tex_setup <= 0;
        end else begin
            vst_we <= 0;
            case (state)
            S_IDLE:
                if (take) begin
                    colour <= cmd_colour;
                    tex_on <= 1'b0;
                    if (cmd_op == 4'd1 || cmd_op == 4'd4) begin
                        tex_setup <= 1'b0;
                        zplane <= 1'b0;
                        for (integer k = 0; k < 3; k = k + 1) begin
                            vx[k] <= cmd_x[k]; vy[k] <= cmd_y[k];
                        end
                        c0_e <= cmd_colour;
                        c1_e <= cmd_c1;
                        c2_e <= cmd_c2;
                        tris <= tris + 1'b1;
                        if (cmd_op == 4'd4) begin
                            // A textured triangle: the corners are read the
                            // way a shaded one's are and the nine plane
                            // numbers follow them, straight into the
                            // accumulators the fill steps, which start at
                            // the value the caller gave for the first pixel.
                            tex_on <= 1'b1;
                            tex_tile <= cmd_tile[5:0];
                            tex_a <= cmd_p[0]; tex_as <= cmd_p[1]; tex_aj <= cmd_p[2];
                            tex_b <= cmd_p[3]; tex_bs <= cmd_p[4]; tex_bj <= cmd_p[5];
                            tex_c <= cmd_p[6]; tex_cs <= cmd_p[7]; tex_cj <= cmd_p[8];
                        end
                        hand_kind <= H_TRI;
                        state <= S_BOX;
                    end else if (cmd_op == 4'd2 && cmd_first < cmd_end &&
                                 cmd_end <= H) begin
                        addr <= {cmd_first, 8'd0} + {2'd0, cmd_first, 6'd0};
                        fill_end <= {cmd_end, 8'd0} + {2'd0, cmd_end, 6'd0};
                        hand_kind <= H_ROWS;
                        state <= S_HAND;
                    end else if (cmd_op == 4'd3 && cmd_x[1] > cmd_x[0] &&
                                 cmd_y[1] > cmd_y[0]) begin
                        hc_i0 <= cmd_x[0][8:0];
                        hc_i1 <= cmd_x[1][8:0];
                        hc_j0 <= cmd_y[0][7:0];
                        hc_j1 <= cmd_y[1][7:0];
                        hc_du <= cmd_x[2];
                        hc_dv <= cmd_y[2];
                        hc_u0 <= cmd_x[3];
                        hc_v0 <= cmd_y[3];
                        hc_tile <= cmd_tile;
                        hc_addr <= {cmd_y[0][7:0], 8'd0} +
                                   {2'd0, cmd_y[0][7:0], 6'd0} +
                                   {7'd0, cmd_x[0][8:0]};
                        hand_kind <= H_CARD;
                        state <= S_HAND;
                    end else if (cmd_op == 4'd5) begin
                        // A shaded vertex: its corner and palette entry, and
                        // nothing a textured triangle reads.
                        vst_we <= 1'b1;
                        vst_waddr <= cmd_w0[27:18];
                        vst_wdata <= {cmd_x[0], cmd_y[0], cmd_w0[7:0], 6'd0,
                                      24'd0, 24'd0, 14'd0,
                                      cmd_y[1][7:0], cmd_x[1], 12'd0};
                    end else if (cmd_op == 4'd6) begin
                        // A textured vertex: the corner and the tile wait in
                        // registers while its three plane values are divided.
                        vt_slot <= cmd_w0[27:18];
                        vt_tile <= cmd_w0[17:12];
                        vt_x <= cmd_x[0];
                        vt_y <= cmd_y[0];
                        vd_den <= {cmd_y[1][5:0], cmd_x[1]};
                        vd_den3 <= {2'd0, cmd_y[1][5:0], cmd_x[1]} +
                                   {1'd0, cmd_y[1][5:0], cmd_x[1], 1'b0};
                        // The numerators, u << 20, v << 20 and 1 << 20, as
                        // their top six bits, already in the remainder, and
                        // the 24 below them.
                        vd_rem[0] <= {16'd0, cmd_y[1][15:10]};
                        vd_num[0] <= {cmd_y[1][9:6], 20'd0};
                        vd_rem[1] <= {16'd0, cmd_w0[11:6]};
                        vd_num[1] <= {cmd_w0[5:2], 20'd0};
                        vd_rem[2] <= 0;
                        vd_num[2] <= 24'd1 << 20;
                        // 1 << 30 is 31 bits: its top seven, 64, go into the
                        // remainder, below z as z is at least 128.
                        vd_rem[3] <= 22'd64;
                        vd_num[3] <= 24'd0;
                        for (integer k = 0; k < 4; k = k + 1)
                            vd_q[k] <= 0;
                        vd_bit <= 4'd11;
                        state <= S_VDIV;
                    end else if (cmd_op[3]) begin
                        // TRIV or TEXV: read the three slots it names.
                        vi[0] <= cmd_w0[29:20];
                        vi[1] <= cmd_w0[19:10];
                        vi[2] <= cmd_w0[9:0];
                        tex_setup <= !cmd_op[2];
                        vr_step <= 0;
                        state <= S_VRD;
                    end
                end
            S_VDIV: begin
                for (integer k = 0; k < 4; k = k + 1) begin
                    if ({vd_rem[k], vd_num[k][23:22]} >= {2'd0, vd_den3}) begin
                        vd_rem[k] <= {vd_rem[k], vd_num[k][23:22]} - {2'd0, vd_den3};
                        vd_q[k] <= {vd_q[k][21:0], 2'd3};
                    end else if ({vd_rem[k], vd_num[k][23:22]} >= {1'd0, vd_den, 1'b0}) begin
                        vd_rem[k] <= {vd_rem[k], vd_num[k][23:22]} - {1'd0, vd_den, 1'b0};
                        vd_q[k] <= {vd_q[k][21:0], 2'd2};
                    end else if ({vd_rem[k], vd_num[k][23:22]} >= {2'd0, vd_den}) begin
                        vd_rem[k] <= {vd_rem[k], vd_num[k][23:22]} - {2'd0, vd_den};
                        vd_q[k] <= {vd_q[k][21:0], 2'd1};
                    end else begin
                        vd_rem[k] <= {vd_rem[k][19:0], vd_num[k][23:22]};
                        vd_q[k] <= {vd_q[k][21:0], 2'd0};
                    end
                    vd_num[k] <= vd_num[k] << 2;
                end
                if (vd_bit == 0)
                    state <= S_VWR;
                else
                    vd_bit <= vd_bit - 1'b1;
            end
            S_VWR: begin
                vst_we <= 1'b1;
                vst_waddr <= vt_slot;
                vst_wdata <= {vt_x, vt_y, 8'd0, vt_tile, vd_q[0][23:0],
                              vd_q[1][23:0], vd_q[2][13:0], vd_q[3][23:0], 12'd0};
                state <= S_IDLE;
            end
            S_VRD: begin
                // One slot asked for a clock, each answering two clocks later:
                // the address register moves on one edge and the store's
                // output on the next.
                case (vr_step)
                    3'd0: vst_raddr <= vi[0];
                    3'd1: vst_raddr <= vi[1];
                    3'd2: vst_raddr <= vi[2];
                    default: ;
                endcase
                if (vr_step == 3'd2 || vr_step == 3'd3) begin
                    cap_x[vr_step - 3'd2] <= vst_q[143:128];
                    cap_y[vr_step - 3'd2] <= vst_q[127:112];
                    cap_c[vr_step - 3'd2] <= vst_q[111:104];
                    cap_u[vr_step - 3'd2] <= vst_q[97:74];
                    cap_v[vr_step - 3'd2] <= vst_q[73:50];
                    cap_r[vr_step - 3'd2] <= vst_q[49:36];
                    cap_d[vr_step - 3'd2] <= vst_q[35:12];
                    if (vr_step == 3'd2)
                        cap_tile <= vst_q[103:98];
                end
                if (vr_step == 3'd4) begin
                    vx[0] <= cap_x[0]; vx[1] <= cap_x[1]; vx[2] <= vst_q[143:128];
                    vy[0] <= cap_y[0]; vy[1] <= cap_y[1]; vy[2] <= vst_q[127:112];
                    c0_e <= cap_c[0]; c1_e <= cap_c[1]; c2_e <= vst_q[111:104];
                    pu[0] <= cap_u[0]; pu[1] <= cap_u[1]; pu[2] <= vst_q[97:74];
                    pv[0] <= cap_v[0]; pv[1] <= cap_v[1]; pv[2] <= vst_q[73:50];
                    pr[0] <= cap_r[0]; pr[1] <= cap_r[1]; pr[2] <= vst_q[49:36];
                    pd[0] <= cap_d[0]; pd[1] <= cap_d[1]; pd[2] <= vst_q[35:12];
                    tex_tile <= cap_tile;
                    tex_on <= tex_setup;
                    zplane <= 1'b1;
                    tris <= tris + 1'b1;
                    hand_kind <= H_TRI;
                    state <= S_BOX;
                end
                vr_step <= vr_step + 1'b1;
            end
            S_TP0: begin
                ta1[0] <= $signed({24'd0, pu[1]}) - $signed({24'd0, pu[0]});
                ta2[0] <= $signed({24'd0, pu[2]}) - $signed({24'd0, pu[0]});
                ta1[1] <= $signed({24'd0, pv[1]}) - $signed({24'd0, pv[0]});
                ta2[1] <= $signed({24'd0, pv[2]}) - $signed({24'd0, pv[0]});
                ta1[2] <= $signed({34'd0, pr[1]}) - $signed({34'd0, pr[0]});
                ta2[2] <= $signed({34'd0, pr[2]}) - $signed({34'd0, pr[0]});
                ta1[3] <= $signed({24'd0, pd[1]}) - $signed({24'd0, pd[0]});
                ta2[3] <= $signed({24'd0, pd[2]}) - $signed({24'd0, pd[0]});
                dv_den <= s_abs;
                state <= S_TPMUL;
                // The products start at the highest digit the edges need.
                digit <= tp_top;
                mul_top <= tp_top;
                tp_triple <= 1'b1;
            end
            S_TPMUL: begin
                if (tp_triple) begin
                    // Three times each difference, which the digit wants.
                    for (integer k = 0; k < 4; k = k + 1) begin
                        ta1x3[k] <= ta1[k] + (ta1[k] <<< 1);
                        ta2x3[k] <= ta2[k] + (ta2[k] <<< 1);
                    end
                    dv_den3 <= {2'd0, dv_den} + {1'd0, dv_den, 1'b0};
                    tp_triple <= 1'b0;
                end else begin
                    if (digit == 0) state <= S_TPN;
                    digit <= digit - 1'b1;
                end
            end
            S_TPN: begin
                // det = -S, so the quotient is negative when the numerator's
                // sign and S's agree.
                for (integer k = 0; k < 4; k = k + 1) begin
                    dv_num[2 * k] <= tp_nx[k] < 0 ? -tp_nx[k] : tp_nx[k];
                    dv_neg[2 * k] <= (tp_nx[k] < 0) == (s_reg < 0);
                    dv_num[2 * k + 1] <= tp_ny[k] < 0 ? -tp_ny[k] : tp_ny[k];
                    dv_neg[2 * k + 1] <= (tp_ny[k] < 0) == (s_reg < 0);
                end
                for (integer k = 0; k < 8; k = k + 1) begin
                    dv_rem[k] <= 0; dv_q[k] <= 0;
                end
                det_zero <= s_reg == 0;
                state <= S_TPSH;
            end
            S_TPSH: begin
                // How many radix-4 steps the largest numerator needs: its top
                // bit, rounded up to a pair. A numerator's leading zeros,
                // brought down into a remainder of zero, add only zeros to the
                // quotient, so skipping them is exact.
                dv_steps <= dv_any == 0 ? 5'd1 : (msb42(dv_any) >> 1) + 1'b1;
                state <= S_TPSH2;
            end
            S_TPSH2: begin
                for (integer k = 0; k < 8; k = k + 1)
                    dv_num[k] <= dv_num[k] << (6'd42 - {dv_steps, 1'b0});
                dv_bit <= dv_steps - 1'b1;
                state <= S_TPDIV;
            end
            S_TPDIV: begin
                // Two quotient bits a clock against det, 2 det and 3 det, the
                // 42 numerator bits in 21 steps; the quotient keeps its low 32.
                for (integer k = 0; k < 8; k = k + 1) begin
                    if ({dv_rem[k], dv_num[k][41:40]} >= {1'b0, dv_den3}) begin
                        dv_rem[k] <= {dv_rem[k], dv_num[k][41:40]} - {1'b0, dv_den3};
                        dv_q[k] <= {dv_q[k][29:0], 2'd3};
                    end else if ({dv_rem[k], dv_num[k][41:40]} >= {1'b0, dv_den, 1'b0}) begin
                        dv_rem[k] <= {dv_rem[k], dv_num[k][41:40]} - {1'b0, dv_den, 1'b0};
                        dv_q[k] <= {dv_q[k][29:0], 2'd2};
                    end else if ({dv_rem[k], dv_num[k][41:40]} >= {2'd0, dv_den}) begin
                        dv_rem[k] <= {dv_rem[k], dv_num[k][41:40]} - {2'd0, dv_den};
                        dv_q[k] <= {dv_q[k][29:0], 2'd1};
                    end else begin
                        dv_rem[k] <= {dv_rem[k][32:0], dv_num[k][41:40]};
                        dv_q[k] <= {dv_q[k][29:0], 2'd0};
                    end
                    dv_num[k] <= dv_num[k] << 2;
                end
                if (dv_bit == 0)
                    state <= S_TPSIGN;
                else
                    dv_bit <= dv_bit - 1'b1;
            end
            S_TPSIGN: begin
                // A triangle of no area keeps the first corner's value and
                // no steps, which is tex_plane's own rule for it. The
                // gradient wires above also provide three times each value
                // for the origin products' digit 3.
                digit <= org_top;
                mul_top <= org_top;
                state <= S_TPORG;
            end
            S_TPORG: begin
                if (digit == 0) state <= S_TPFIN;
                digit <= digit - 1'b1;
            end
            S_TPFIN: begin
                tex_a <= {8'd0, pu[0]} + oacc[0] + oacc[1];
                tex_as <= tg[0] << 4; tex_aj <= tg[1] << 4;
                tex_b <= {8'd0, pv[0]} + oacc[2] + oacc[3];
                tex_bs <= tg[2] << 4; tex_bj <= tg[3] << 4;
                tex_c <= {18'd0, pr[0]} + oacc[4] + oacc[5];
                tex_cs <= tg[4] << 4; tex_cj <= tg[5] << 4;
                zd0 <= {8'd0, pd[0]} + oacc[6] + oacc[7];
                zd_s <= tg[6] << 4; zd_j <= tg[7] << 4;
                state <= S_HAND;
            end
            S_BOX: begin
                // The palette walk rides along from here to S_TRIPLE: its five
                // steps need nothing the geometry works out.
                pal_addr <= c0_e;
                pal_step <= 3'd1;
                xmin <= min01x < vx[2] ? min01x : vx[2];
                xmax <= max01x > vx[2] ? max01x : vx[2];
                ymin <= min01y < vy[2] ? min01y : vy[2];
                ymax <= max01y > vy[2] ? max01y : vy[2];
                state <= S_CLAMP;
            end
            S_CLAMP: begin
                pal_addr <= c1_e;
                ci0 <= bi0 < 0 ? 13'sd0 : bi0;
                ci1 <= bi1 > 13'sd319 ? 13'sd319 : bi1;
                cj0 <= bj0 < 0 ? 13'sd0 : bj0;
                cj1 <= bj1 > 13'sd179 ? 13'sd179 : bj1;
                state <= S_LOAD;
            end
            S_LOAD: begin
                pal_addr <= c2_e;
                c0_c <= pal_q[15:0];
                if (box_empty)
                    state <= S_IDLE;
                else begin
                    i0 <= ci0[8:0]; i1 <= ci1[8:0]; j0 <= cj0[7:0];
                    j1 <= cj1[7:0];
                    addr <= {cj0[7:0], 8'd0} + {2'd0, cj0[7:0], 6'd0} +
                            {7'd0, ci0[8:0]};
                    state <= S_EDGE;
                end
            end
            S_EDGE: begin
                c1_c <= pal_q[15:0];
                for (integer k = 0; k < 3; k = k + 1) begin
                    dx[k] <= vx[(k + 1) % 3] - vx[k];
                    dy[k] <= vy[(k + 1) % 3] - vy[k];
                    ox[k] <= $signed({5'd0, i0, 4'd8}) - vx[k];
                    oy[k] <= $signed({6'd0, j0, 4'd8}) - vy[k];
                end
                state <= S_TRIPLE;
            end
            S_TRIPLE: begin
                c2_c <= pal_q[15:0];
                for (integer k = 0; k < 3; k = k + 1) begin
                    dy3[k] <= dy[k] * 3;
                    dx3[k] <= dx[k] * 3;
                    step_x[k] <= dy[k] <<< 4;
                    step_y[k] <= -(dx[k] <<< 4);
                end
                // Start at the highest digit any of the six offsets needs.
                digit <= max4(max4(max4(top_digit(ox[0]), top_digit(ox[1])),
                                   max4(top_digit(ox[2]), top_digit(oy[0]))),
                              max4(top_digit(oy[1]), top_digit(oy[2])));
                mul_top <= max4(max4(max4(top_digit(ox[0]), top_digit(ox[1])),
                                     max4(top_digit(ox[2]), top_digit(oy[0]))),
                                max4(top_digit(oy[1]), top_digit(oy[2])));
                state <= S_MUL;
            end
            S_MUL: begin
                if (digit == 0) state <= S_FIN;
                digit <= digit - 1'b1;
            end
            S_FIN: begin
                for (integer k = 0; k < 3; k = k + 1)
                    e[k] <= acc_x[k] - acc_y[k];
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
                // A stored triangle works its planes out next -- the depth
                // plane, and TEXV's u, v and 1/z; everything else is ready for
                // the fill.
                state <= zplane ? S_TP0 : S_HAND;
            end
            S_HAND:
                // Held until the fill is free; fill_start is the same
                // condition, so the fill takes this command's fields on the
                // clock setup lets go of them.
                if (fstate == F_IDLE)
                    state <= S_IDLE;
            default: state <= S_IDLE;
            endcase
        end
    end

    // ---- Fill: one triangle, run of rows or card at a time, into the target ----
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            fstate <= F_IDLE; we <= 0; pixels <= 0; we1_r <= 0;
            phase <= 0; last_p <= 0; zwe <= 0; zw1_r <= 0;
        end else begin
            we <= 0;
            zwe <= 0;
            case (fstate)
            F_IDLE:
                if (fill_start) begin
                    // The hand-over: everything the fill reads, copied from
                    // setup in the one clock both agree it happens.
                    phase <= 0; last_p <= 0; we1_r <= 0; zw1_r <= 0;
                    if (hand_kind == H_ROWS) begin
                        faddr <= addr; ffill_end <= fill_end; fcolour <= colour;
                        fstate <= F_ROWS;
                    end else if (hand_kind == H_CARD) begin
                        card_i0 <= hc_i0; card_i1 <= hc_i1;
                        card_j0 <= hc_j0; card_j1 <= hc_j1;
                        card_i <= hc_i0; card_j <= hc_j0;
                        card_du <= hc_du; card_dv <= hc_dv;
                        card_u0 <= hc_u0; card_u <= hc_u0; card_v <= hc_v0;
                        card_tile <= hc_tile; card_addr <= hc_addr;
                        card_phase <= 0;
                        fstate <= F_CARD;
                    end else begin
                        fi0 <= i0; fi1 <= i1; fi <= i0; fj1 <= j1; fj <= j0;
                        faddr <= addr; frow_addr <= addr;
                        for (integer k = 0; k < 3; k = k + 1) begin
                            fe[k] <= e[k]; fe_row[k] <= e[k];
                            fstep_x[k] <= step_x[k]; fstep_y[k] <= step_y[k];
                        end
                        fs <= s_reg; fs2 <= s2_reg; fs3 <= s3_reg;
                        fc0 <= c0_c; fc1 <= c1_c; fc2 <= c2_c;
                        ftex_on <= tex_on; ftile <= tex_tile;
                        ftex_a <= tex_a; ftex_arow <= tex_a;
                        ftex_b <= tex_b; ftex_brow <= tex_b;
                        ftex_c <= tex_c; ftex_crow <= tex_c;
                        ftex_as <= tex_as; ftex_bs <= tex_bs; ftex_cs <= tex_cs;
                        ftex_aj <= tex_aj; ftex_bj <= tex_bj; ftex_cj <= tex_cj;
                        fzmode <= zplane;
                        fd <= zd0; fd_row <= zd0; fd_s <= zd_s; fd_j <= zd_j;
                        d18_p <= depth18(zd0);
                        zpass_r <= 1'b0;
                        tex_z <= 18'd0;
                        fstate <= F_SCAN;
                    end
                end
            F_CARD: begin
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
                    we <= (tile_q[7:0] != TEX_KEY);
                    waddr <= card_addr;
                    wdata <= ART_FIRST_W + tile_q[7:0];
                    if (tile_q[7:0] != TEX_KEY)
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
                        fstate <= F_IDLE;
                end
            end
            F_ROWS: begin
                we <= 1; waddr <= faddr; wdata <= fcolour;
                zwe <= 1; zwaddr <= faddr; zwdata <= 0;
                faddr <= faddr + 1'b1;
                if (faddr + 1'b1 == ffill_end) fstate <= F_IDLE;
            end
            F_SCAN: begin
                // Two clocks a pixel. The first takes this pixel's weights
                // and its coverage and address, and steps the edge functions
                // on; the second mixes its fcolour, from the weights just
                // registered, and gives that fcolour to the table. A pixel's
                // entry comes back a clock later, so the pixel written here
                // is the one before: its fcolour was addressed in the last
                // cycle, and it is written once, in the first phase.
                if (phase && we1_r && !ftex_on) begin
                    we <= 1; waddr <= a1_r; wdata <= lut_q[7:0];
                    zwe <= zw1_r; zwaddr <= a1_r; zwdata <= zd1_r;
                end
                if (!phase) begin
                    aw_r <= aw;
                    bw_r <= bw;
                    covered_r <= covered;
                    addr_r <= faddr;
                    // This pixel's planes, before the step moves them on: a
                    // textured triangle divides the ones belonging to the
                    // pixel it is writing, not the next one's.
                    tn_a <= ftex_a;
                    tn_b <= ftex_b;
                    tn_c <= ftex_c;
                    // The depth buffer's read for this pixel landed this
                    // clock, so its test belongs here, before the second
                    // phase needs the answer.
                    zpass_r <= !fzmode || d18_p >= zq;
                    if (fi == fi1) begin
                        if (fj == fj1)
                            last_p <= 1;
                        else begin
                            fj <= fj + 1'b1; fi <= fi0;
                            frow_addr <= frow_addr + 16'd320;
                            faddr <= frow_addr + 16'd320;
                            for (integer k = 0; k < 3; k = k + 1) begin
                                fe_row[k] <= fe_row[k] + fstep_y[k];
                                fe[k] <= fe_row[k] + fstep_y[k];
                            end
                            ftex_arow <= ftex_arow + ftex_aj;
                            ftex_brow <= ftex_brow + ftex_bj;
                            ftex_crow <= ftex_crow + ftex_cj;
                            ftex_a <= ftex_arow + ftex_aj;
                            ftex_b <= ftex_brow + ftex_bj;
                            ftex_c <= ftex_crow + ftex_cj;
                            fd_row <= fd_row + fd_j;
                            fd <= fd_row + fd_j;
                        end
                    end else begin
                        fi <= fi + 1'b1; faddr <= faddr + 1'b1;
                        for (integer k = 0; k < 3; k = k + 1)
                            fe[k] <= fe[k] + fstep_x[k];
                        ftex_a <= ftex_a + ftex_as;
                        ftex_b <= ftex_b + ftex_bs;
                        ftex_c <= ftex_c + ftex_cs;
                        fd <= fd + fd_s;
                    end
                end else begin
                    if (ftex_on) begin
                        // The texel this pixel names: the two numerators
                        // divided by the interpolated reciprocal of depth,
                        // ten quotient bits each.
                        if (covered_r && zpass_r) begin
                            tex_rem <= tn_a >= 0 ? tn_a : -tn_a;
                            tex_q <= 0;
                            tex_bit <= 4'd9;
                            tex_second <= 1'b0;
                            tex_z <= d18_p;
                            fstate <= F_TEXDIV;
                        end else if (last_p)
                            fstate <= F_IDLE;
                    end else begin
                        lut_addr <= mixed;
                        we1_r <= covered_r && zpass_r;
                        zw1_r <= covered_r && zpass_r && fzmode;
                        zd1_r <= d18_p;
                        a1_r <= addr_r;
                        if (covered_r && zpass_r)
                            pixels <= pixels + 1'b1;
                        if (last_p) begin
                            fstate <= F_DRAIN;
                            drain <= 2'd2;
                        end
                    end
                    // fd has already stepped to the next pixel's depth, so
                    // it is the one the next first phase tests.
                    d18_p <= depth18(fd);
                end
                phase <= ~phase;
            end
            F_DRAIN: begin
                // The last pixel's entry arrives a clock after its fcolour
                // went to the table: the first of these two clocks lets it
                // arrive, the second writes it.
                if (drain <= 1 && we1_r) begin
                    we <= 1; waddr <= a1_r; wdata <= lut_q[7:0];
                    zwe <= zw1_r; zwaddr <= a1_r; zwdata <= zd1_r;
                end
                if (drain <= 1) begin
                    we1_r <= 0;
                    fstate <= F_IDLE;
                end else
                    drain <= drain - 1'b1;
            end
            F_TEXDIV: begin
                // The quotient u = A/C, then v = B/C, ten bits each: the
                // denominator shifted up against the remainder, which is the
                // truncation towards zero the twin's own division gives. The
                // sign goes on at the end, because the texel has to be the
                // one the twin names when the numerator is negative too.
                tex_q <= tex_q_next;
                if (tex_bit == 4'd0) begin
                    if (!tex_second) begin
                        tex_uu <= (tn_a < 0) != (tn_c < 0) ? -tex_q_next[11:0]
                                                          : tex_q_next[11:0];
                        tex_second <= 1'b1;
                        tex_rem <= tn_b >= 0 ? tn_b : -tn_b;
                        tex_q <= 0;
                        tex_bit <= 4'd9;
                    end else begin
                        tex_vv <= (tn_b < 0) != (tn_c < 0) ? -tex_q_next[11:0]
                                                          : tex_q_next[11:0];
                        tex_second <= 1'b0;
                        tex_w <= 2'd0;
                        fstate <= F_TEXW;
                    end
                end else begin
                    tex_rem <= tex_rem_next;
                    tex_bit <= tex_bit - 1'b1;
                end
            end
            F_TEXW: begin
                // Three clocks, the shape the card fill taught: one to give the
                // store the address, one for its byte to land -- the address
                // register is itself a register, so the memory sees the address
                // a clock after it is written -- and the third to write it. Two
                // clocks wrote each pixel the previous pixel's texel, which is
                // invisible wherever two pixels share a texel and a mottled
                // texture everywhere else.
                if (tex_w == 2'd0) begin
                    tile_raddr <= {ftile, 10'd0} + {5'd0, tex_tv, 5'd0} +
                                  {10'd0, tex_tu};
                    tex_w <= 2'd1;
                end else if (tex_w == 2'd1) begin
                    tex_w <= 2'd2;
                end else begin
                    we <= (tile_q[7:0] != TEX_KEY);
                    waddr <= addr_r;
                    wdata <= ART_FIRST_W + tile_q[7:0];
                    zwe <= (tile_q[7:0] != TEX_KEY) && fzmode;
                    zwaddr <= addr_r; zwdata <= tex_z;
                    if (tile_q[7:0] != TEX_KEY)
                        pixels <= pixels + 1'b1;
                    tex_w <= 2'd0;
                    phase <= 1'b0;
                    if (last_p)
                        fstate <= F_IDLE;
                    else
                        fstate <= F_SCAN;
                end
            end
            default: fstate <= F_IDLE;
            endcase
        end
    end

    // The depth read is issued a pixel ahead: in phase 0 zq holds this
    // pixel's depth. The hand-over cycle primes it with the first pixel's
    // address, since faddr still holds the previous triangle's last.
    wire [15:0] zraddr = fill_start && hand_kind == H_TRI ? addr : faddr;
    always @(posedge clk) begin
        if (zwe) zbuf[zwaddr] <= zwdata;
        zq <= zbuf[zraddr];
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
