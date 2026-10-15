// SPDX-License-Identifier: GPL-3.0-or-later
// TinyCreature's first fabric rasterizer: flat-coloured triangles into two
// 320x180 indexed frame buffers in block RAM, which the video unit shows
// through the same line-fetch handshake as the SDRAM (ahb_sdram.sv).
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
//   STATUS bit 1 set while a scan is running
//
// Commands:
//   ROWS  1 word: 2 << 28 | end << 16 | first << 8 | colour, fills rows
//         first to end - 1
//   TRI   4 words: 1 << 28 | colour, then y << 16 | x for each corner, as
//         16-bit two's-complement Q4 screen coordinates
// A triangle fills pixel (i, j) when, at its centre (16i + 8, 16j + 8), all
// three edge functions F = (by - ay)(px - ax) - (bx - ax)(py - ay) over its
// edges a to b are >= 0; pixels outside the screen are never visited. The
// corners must be in the order that makes F >= 0 inside, which for this
// project is a front face (firmware/terrain/terrain.c, raster_triangle()).
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
              (hwrite ? reg_index <= 1 || reg_index == 7 || reg_index == 8
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
    reg signed [15:0] cmd_x [0:2];
    reg signed [15:0] cmd_y [0:2];
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
                        len <= 4; got <= 1;
                    end else begin
                        cmd_full <= 1; got <= 0; issued <= 0; len <= 1;
                    end
                end else begin
                    cmd_x[got - 1] <= fifo_q[15:0];
                    cmd_y[got - 1] <= fifo_q[31:16];
                    if (got == 3) begin
                        cmd_full <= 1; got <= 0; issued <= 0; len <= 1;
                    end else
                        got <= got + 1'b1;
                end
            end
        end
    end
    // Before word 0 arrives len is 1, so nothing is popped past a ROWS
    // word; a TRI's three corner words follow once its opcode is seen.

    // ---- Engine ----
    localparam S_IDLE = 0, S_ROWS = 1, S_BOX = 2, S_CLAMP = 3, S_LOAD = 4,
               S_EDGE = 5, S_TRIPLE = 6, S_MUL = 7, S_FIN = 8, S_SCAN = 9;
    reg [3:0] state = S_IDLE;
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
            state <= S_IDLE; we <= 0; tris <= 0; pixels <= 0;
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
                        tris <= tris + 1'b1;
                        state <= S_BOX;
                    end else if (cmd_op == 4'd2 && cmd_first < cmd_end &&
                                 cmd_end <= H) begin
                        addr <= {cmd_first, 8'd0} + {2'd0, cmd_first, 6'd0};
                        fill_end <= {cmd_end, 8'd0} + {2'd0, cmd_end, 6'd0};
                        state <= S_ROWS;
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
                state <= S_SCAN;
            end
            S_SCAN: begin
                if (covered) begin
                    we <= 1; waddr <= addr; wdata <= colour;
                    pixels <= pixels + 1'b1;
                end
                if (i == i1) begin
                    if (j == j1)
                        state <= S_IDLE;
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
