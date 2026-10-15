// SPDX-License-Identifier: GPL-3.0-or-later
//
// TinyCreature's terrain run on the Tang32 core: asks for a TCL2 land file
// (tools/convert_land.py) with
//   TinyNES WANT <address> <bytes>
// and draws FRAMES frames of one orbit of the island, flipping each at a
// vertical blank. Built with FABRIC=1 (the default) the triangles go to the
// fabric rasterizer (fpga/raster.sv), which draws into its block RAM
// buffers; with FABRIC=0 its model, tc_soft, draws them into the SDRAM
// buffers instead. Either way it reports
//   TinyCreature TERRAIN OK MODE=<FABRIC|SOFT> LAND=<crc> FRAMES=<n>
//     TRIS=<mean> PIXELS=<mean> DRAW=<us> MAX=<us> FINISH=<us> STALLS=<n>
//     VBL=<n> VBLMIN=<n> VBLMAX=<n> PERIOD=<us> INPUT=<n> LATE=<n> CRC=<crc>
// LAND is the file's CRC-32; TRIS and PIXELS the mean triangles sent and
// pixels they filled per frame; DRAW and MAX the mean and longest CPU time
// to send a frame, FINISH the mean time after that until the rasterizer is
// idle; STALLS the mean bus cycles per frame the CPU waited on a full
// rasterizer FIFO; VBL the vertical blanks 600 frames took, VBLMIN and
// VBLMAX the fewest and most one frame took, PERIOD the mean time per shown
// frame; CRC the CRC-32 of all frames in turn, which terrain_host computes
// from the same file over the same bytes. With the fabric drawing, that CRC
// is the rasterizer's own: it folds each frame's buffer, in address order,
// into a seed the program passes back, so the scan runs while the next frame
// is drawn and only one register is read a frame. The last frame stays up. A
// failed check prints BAD TINYCREATURE <name> and the program exits with 1.
// Each frame is then held for TC_BLANKS_PER_FRAME vertical blanks before the
// next one starts, so the shown rate is 60/TC_BLANKS_PER_FRAME frames a
// second, steady. The hold is there because the display shows a frame only on
// a blank boundary: a frame whose cost lands near one takes the next blank on
// some frames and the one after on others, so the shown rate flickers between
// two rates and the motion appears to speed up and slow down. VBLMIN and
// VBLMAX should then both equal TC_BLANKS_PER_FRAME; if VBLMAX is larger the
// renderer missed a blank, and a frame that misses the hold outright prints
// BAD TINYCREATURE CADENCE.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "load.h"
#include "terrain.h"
#include "tinynes.h"

#ifndef FRAMES
#define FRAMES 600
#endif
#ifndef FABRIC
#define FABRIC 1
#endif
#define FILE_MAGIC 0x31524e54u /* "TNR1", from load_ae350.py --file */
#define FILE_MAX   (1u << 20)

/* fpga/raster.sv at 0xe8018000. */
#define RASTER_FIFO    TN_REG(0x18000)
#define RASTER_CTRL    TN_REG(0x18004)
#define RASTER_STATUS  TN_REG(0x18008)
#define RASTER_ID      TN_REG(0x1800c)
#define RASTER_TRIS    TN_REG(0x18010)
#define RASTER_PIXELS  TN_REG(0x18014)
#define RASTER_STALLS  TN_REG(0x18018)
#define RASTER_CRC     TN_REG(0x1801c)
#define RASTER_RB_ADDR TN_REG(0x18020)
#define RASTER_RB_DATA TN_REG(0x18024)
#define RASTER_NONZERO TN_REG(0x18028)
#define RASTER_PAL     TN_REG(0x1802c)
#define RASTER_LUT     TN_REG(0x18030)
#define RASTER_ID_VALUE 0x54435231u /* "TCR1" */

/* Vertical blanks each frame is held for. The display shows a frame only on a
 * blank boundary, so a frame whose cost lands near one takes the next blank on
 * some frames and the one after on others: this renderer's 29.5 ms draw against
 * a 16.7 ms blank came out as three blanks on some frames and two on the rest,
 * a shown rate flicking between twenty and thirty, which is the speed-up and
 * slow-down the user saw. Three blanks is a steady twenty, and the worst frame
 * this renderer draws, 35.3 ms, fits inside it with room to spare. Raise it to
 * slow the cadence down, lower it to speed it up and let the flicker back in;
 * the cost of raising it is that the mouse is read once a frame, so a report
 * waits that long to be acted on. */
#define TC_BLANKS_PER_FRAME 3
#define RASTER_SHOW   0x1u
#define RASTER_TARGET 0x2u
#define RASTER_BUSY   0x1u
#define RASTER_CRC_RUN 0x2u

/* TinyTang's frame format, either direction: 0xAA len_hi len_lo type, the
 * length counting the type byte, then the payload. An input frame carries a
 * frame's mouse movement: the frame it belongs to, then the mouse's HID boot
 * report. The frame 0xffff means "as soon as it arrives", which is what a
 * live mouse sends; a replay tags each report with the frame it belongs to,
 * so one sequence draws the same frames however the link is paced. */
#define TC_FRAME_MAGIC  0xaau
#define TC_FRAME_INPUT  0x16u
#define TC_NO_FRAME     0xffffu
#define TC_IN_PAYLOAD   6u      /* frame, buttons, dx, dy, wheel */
#define TC_IN_FRAMES    4096u   /* frames a tagged report may name */

static void fail(const char *name)
{
	printf("BAD TINYCREATURE %s\n", name);
	exit(1);
}

// The rasterizer's frame scan takes about 2.3 ms. Inside the loop it had a
// whole drawn frame to finish in; after the last frame only the flip wait
// stands between it and being read, so wait for it rather than assume.
static void wait_scan(void)
{
	uint64_t start = tn_cycles64();
	while (RASTER_STATUS & RASTER_CRC_RUN)
		if (tn_cycles64() - start > TN_CORE_HZ / 10u)
			fail("CRC BUSY");
}

/* ---- input: the mouse, as TinyTang sends it ---- */

/* What a report carried, one slot a frame, and what the untagged reports of a
 * live mouse have left waiting for the frame being drawn. */
static int32_t in_dx[TC_IN_FRAMES], in_dy[TC_IN_FRAMES], in_wheel[TC_IN_FRAMES];
static uint8_t in_buttons[TC_IN_FRAMES];
static uint8_t in_seen[TC_IN_FRAMES];    /* a report named this frame */
static int32_t live_dx, live_dy, live_wheel;
static uint8_t live_buttons;
static uint8_t live_report;              /* the link delivered one */
static uint32_t in_applied;

/* Where the decoder is: 0 magic, 1 length high, 2 length low, 3 type, 4
 * payload. A length high byte of 8 or more cannot be a frame, and neither
 * can a length of zero, which is how the protocol resynchronises. */
static uint32_t rx_state, rx_left, rx_type, rx_at;
static uint8_t rx_payload[8];

/* One report a frame, six bytes: the frame it belongs to, the buttons, and
 * the mouse's dx, dy and wheel, the same six the link delivers. A run's file
 * holds the whole sequence, so what the board draws does not depend on how
 * the link was paced. */
static void input_report(const uint8_t *p)
{
	uint32_t at = (uint32_t)p[0] | (uint32_t)p[1] << 8;

	if (at == TC_NO_FRAME) {
		live_buttons = p[2];
		live_dx += (int8_t)p[3];
		live_dy += (int8_t)p[4];
		live_wheel += (int8_t)p[5];
		live_report = 1;
	} else if (at < TC_IN_FRAMES) {
		in_buttons[at] = p[2];
		in_dx[at] += (int8_t)p[3];
		in_dy[at] += (int8_t)p[4];
		in_wheel[at] += (int8_t)p[5];
		in_seen[at] = 1;
	}
}

/* A run's recorded reports, as they arrived in the file. */
static void input_load(const uint8_t *data, uint32_t bytes)
{
	for (uint32_t i = 0; i + TC_IN_PAYLOAD <= bytes; i += TC_IN_PAYLOAD)
		input_report(data + i);
}

static void input_byte(uint8_t byte)
{
	switch (rx_state) {
	case 0:
		if (byte == TC_FRAME_MAGIC)
			rx_state = 1;
		return;
	case 1:
		if (byte >= 8u) {
			rx_state = 0;
			return;
		}
		rx_left = (uint32_t)byte << 8;
		rx_state = 2;
		return;
	case 2:
		rx_left |= byte;
		if (rx_left == 0) {
			rx_state = 0;
			return;
		}
		rx_state = 3;
		return;
	case 3:
		rx_type = byte;
		rx_left -= 1u;   /* the type byte is counted in the length */
		rx_at = 0;
		if (rx_left != 0) {
			rx_state = 4;
			return;
		}
		break;           /* no payload: the frame is complete */
	case 4:
		if (rx_at < sizeof rx_payload)
			rx_payload[rx_at] = byte;
		rx_at++;
		if (--rx_left != 0)
			return;
		break;           /* the frame is complete */
	}
	if (rx_type == TC_FRAME_INPUT && rx_at == TC_IN_PAYLOAD)
		input_report(rx_payload);
	rx_state = 0;
}

/* Aim the camera at what this frame's mouse reports hold, if anything, and
 * say whether anything did. */
static uint32_t input_frame(uint32_t frame)
{
	int32_t dx, dy, wheel;
	uint8_t buttons;
	uint32_t value;
	/* Everything the link has delivered since the last frame. */
	for (unsigned n = 0; n < 512u; n++) {
		value = TN_UART_RX;
		if (!(value & TN_UART_RX_VALID))
			break;
		input_byte((uint8_t)(value & 0xffu));
	}
	/* A report is handed over when one arrived, not when it carried
	 * something: the buttons are a level and the movement a delta, so the
	 * report that lets a button go carries neither, and asking what it
	 * contained drops it and leaves the cursor wearing the sprite of the
	 * button that was let go. */
	uint32_t arrived = live_report;
	live_report = 0;
	buttons = live_buttons;
	dx = live_dx;
	dy = live_dy;
	wheel = live_wheel;
	live_dx = live_dy = live_wheel = 0;
	if (frame < TC_IN_FRAMES) {
		if (in_seen[frame]) {
			buttons = in_buttons[frame];
			arrived = 1;
		}
		dx += in_dx[frame];
		dy += in_dy[frame];
		wheel += in_wheel[frame];
	}
	if (!arrived)
		return 0;
	tc_mouse(buttons, dx, dy, wheel);
	return 1;
}

static const uint8_t *receive(uint32_t *bytes)
{
	uint8_t *buffer = malloc(FILE_MAX + 8);
	if (!buffer)
		fail("MEMORY");
	printf("TinyNES WANT %08lx %08lx\n", (unsigned long)(uintptr_t)buffer,
	       (unsigned long)(FILE_MAX + 8));
	fflush(stdout);
	tn_load_reset();
	uint32_t got = 0;
	for (int second = 0; second < 30 && !got; second++)
		got = tn_load_poll(TN_CORE_HZ);
	uint32_t magic, length;
	memcpy(&magic, buffer, 4);
	memcpy(&length, buffer + 4, 4);
	if (got != (uintptr_t)buffer || magic != FILE_MAGIC || length > FILE_MAX)
		fail("FILE");
	*bytes = length;
	return buffer + 8;
}

// The fabric target: each call is one rasterizer command.
static void fabric_rows(void *ctx, uint32_t first, uint32_t end, uint8_t colour)
{
	(void)ctx;
	RASTER_FIFO = 2u << 28 | end << 16 | first << 8 | colour;
}

static void fabric_triangle(void *ctx, const int32_t *x, const int32_t *y,
			    uint32_t colours)
{
	(void)ctx;
	RASTER_FIFO = 1u << 28 | colours;
	RASTER_FIFO = (uint32_t)(uint16_t)y[0] << 16 | (uint16_t)x[0];
	RASTER_FIFO = (uint32_t)(uint16_t)y[1] << 16 | (uint16_t)x[1];
	RASTER_FIFO = (uint32_t)(uint16_t)y[2] << 16 | (uint16_t)x[2];
}

// Give the fabric the shading tables: the palette in five bits a channel and
// the table from a colour they make back to a land entry. This happens once,
// before the first frame, and about a millisecond of a run. It is the same
// arithmetic the fill does, on a program that would otherwise not need it.
static void fabric_tables(const struct tc_shade *shade)
{
	for (unsigned i = 0; i < TC_PAL5_ENTRIES; i++)
		RASTER_PAL = (uint32_t)shade->pal5[i] << 16 | i;
	for (unsigned i = 0; i < TC_LUT_BYTES; i++)
		RASTER_LUT = (uint32_t)shade->lut[i] << 24 | i;
}

int main(void)
{
	if (TN_VIDEO_ID != TN_VIDEO_ID_VALUE)
		fail("VIDEO ID");
	if (TN_VIDEO_WIDTH != TC_WIDTH || TN_VIDEO_HEIGHT != TC_HEIGHT)
		fail("VIDEO SIZE");
	if (RASTER_ID != RASTER_ID_VALUE)
		fail("RASTER ID");
	if (!FABRIC)
		RASTER_CTRL = 0; // show the SDRAM buffers
	uint32_t bytes;
	const uint8_t *file = receive(&bytes);
	/* The file is a TCL2 land, and a run's recorded mouse reports follow it,
	 * six bytes each. The header's body length says where the land ends, so
	 * the land's own check and CRC see the land alone. */
	uint32_t land_bytes = 0;
	if (bytes >= 32u && file[0] == 'T' && file[1] == 'C' && file[2] == 'L' &&
	    file[3] == '2')
		land_bytes = 32u + ((uint32_t)file[16] | (uint32_t)file[17] << 8 |
				    (uint32_t)file[18] << 16 |
				    (uint32_t)file[19] << 24);
	if (land_bytes == 0 || land_bytes > bytes) {
		printf("BAD TINYCREATURE LAND LENGTH\n");
		exit(1);
	}
	struct tc_land land;
	const char *why = tc_land_open(&land, file, land_bytes);
	if (why) {
		printf("BAD TINYCREATURE LAND %s\n", why);
		exit(1);
	}
	uint32_t land_crc = tc_crc32(0, file, land_bytes);
	input_load(file + land_bytes, bytes - land_bytes);
	void *work = malloc(tc_work_bytes(&land));
	if (!work)
		fail("MEMORY");
	struct tc_shade shade = tc_init(&land, work);
	for (unsigned i = 0; i < TN_VIDEO_PALETTE_SIZE; i++)
		TN_VIDEO_PALETTE(i) = tc_palette(&land, i);
	if (FABRIC)
		fabric_tables(&shade);

	struct tc_soft soft = {.stride = TN_VIDEO_FB_STRIDE,
			       .pal5 = shade.pal5, .lut = shade.lut};
	const struct tc_target target = FABRIC ?
		(struct tc_target){fabric_rows, fabric_triangle, 0} :
		(struct tc_target){tc_soft_rows, tc_soft_triangle, &soft};
	uint32_t late0 = TN_VIDEO_LATE, vbl0 = TN_VIDEO_FRAMES;
	uint32_t stalls0 = FABRIC ? RASTER_STALLS : 0;
	uint32_t crc = 0, lit = 0;
	// The fabric's checksum: each frame's buffer is folded into a CRC-32 by
	// the rasterizer, seeded with the state the run has reached, so the value
	// at the end is the one terrain_host computes from the same file. The
	// scan runs while the next frame is drawn, so its result is read a frame
	// later rather than waited for.
	uint32_t chain = 0xffffffffu;
	int scanning = 0;
	uint64_t tris = 0, pixels = 0, draw = 0, longest = 0, finish = 0;
	uint32_t vbl_min = ~0u, vbl_max = 0;
	uint64_t start = tn_cycles64();
	for (uint32_t frame = 0; frame < FRAMES; frame++) {
		uint32_t blanks = TN_VIDEO_FRAMES;
		in_applied += input_frame(frame);
		uint32_t back = (TN_VIDEO_STATUS & TN_VIDEO_BUFFER) ? 0u : 1u;
		uint32_t tris0 = 0, pixels0 = 0;
		if (FABRIC) {
			RASTER_CTRL = RASTER_SHOW | (back ? RASTER_TARGET : 0u);
			tris0 = RASTER_TRIS;
			pixels0 = RASTER_PIXELS;
		} else {
			soft.fb = TN_VIDEO_FB(back);
			soft.triangles = soft.pixels = 0;
		}
		struct tc_stats stats;
		uint64_t t0 = tn_cycles64();
		tc_draw(&target, frame, FRAMES, &stats);
		uint64_t t1 = tn_cycles64();
		if (FABRIC)
			while (RASTER_STATUS & RASTER_BUSY)
				if (tn_cycles64() - t1 > TN_CORE_HZ / 10u)
					fail("RASTER BUSY");
		uint64_t t2 = tn_cycles64();
		draw += t1 - t0;
		longest = t1 - t0 > longest ? t1 - t0 : longest;
		finish += t2 - t1;
		uint32_t sent = FABRIC ? RASTER_TRIS - tris0 : soft.triangles;
		if (sent != stats.triangles)
			fail("TRIS");
		tris += stats.triangles;
		pixels += FABRIC ? RASTER_PIXELS - pixels0 : soft.pixels;

		// The frame as drawn, folded by the fabric into the run's CRC-32, or
		// read back from where it was drawn when the AE350 drew it itself.
		lit = 0;
		if (FABRIC) {
			if (scanning) {
				wait_scan();
				chain = RASTER_CRC;
				lit = RASTER_NONZERO;
			}
			RASTER_CRC = chain;
			scanning = 1;
		} else {
			for (uint32_t y = 0; y < TC_HEIGHT; y++) {
				const uint8_t *row = TN_VIDEO_FB_ROW(back, y);
				crc = tc_crc32(crc, row, TC_WIDTH);
				for (uint32_t x = 0; x < TC_WIDTH; x++)
					lit += row[x] != 0;
			}
			tn_dcache_wbinval();
		}
		TN_VIDEO_CTRL = TN_VIDEO_ENABLE | (back ? TN_VIDEO_BUFFER : 0u);
		uint32_t want = TN_VIDEO_SHOWING | (back ? TN_VIDEO_BUFFER : 0u);
		uint64_t wait = tn_cycles64();
		while ((TN_VIDEO_STATUS & (TN_VIDEO_SHOWING | TN_VIDEO_BUFFER)) != want)
			if (tn_cycles64() - wait > TN_CORE_HZ / 10u)
				fail("FLIP");
		/* Hold every frame to the same cadence. The display shows a frame on a
		 * blank boundary, so a frame whose cost lands near one flickers between
		 * sixty, thirty and twenty a second, which is what makes the motion
		 * speed up and slow down. Three blanks is a steady twenty, and the worst
		 * frame this renderer draws fits inside it. */
		while (TN_VIDEO_FRAMES - blanks < TC_BLANKS_PER_FRAME)
			if (tn_cycles64() - wait > TN_CORE_HZ / 10u)
				fail("CADENCE");
		uint32_t spent = TN_VIDEO_FRAMES - blanks;
		vbl_min = spent < vbl_min ? spent : vbl_min;
		vbl_max = spent > vbl_max ? spent : vbl_max;
	}
	uint64_t elapsed = tn_cycles64() - start;
	if (FABRIC) {
		wait_scan();
		chain = RASTER_CRC;
		lit = RASTER_NONZERO;
		crc = ~chain;
	}
	uint32_t vbl = TN_VIDEO_FRAMES - vbl0;
	uint32_t late = TN_VIDEO_LATE - late0;
	uint32_t stalls = FABRIC ? RASTER_STALLS - stalls0 : 0;
	uint32_t us = TN_CORE_HZ / 1000000u;

	// What the fabric shows of the last frame: its non-zero pixels, 4x4.
	uint32_t f = TN_VIDEO_FRAMES;
	while (TN_VIDEO_FRAMES - f < 2u)
		;
	uint32_t shown = TN_VIDEO_PIXELS;
	if (late)
		fail("LATE");
	if (shown != lit * 16u)
		fail("PIXELS");
	printf("TinyCreature TERRAIN OK MODE=%s LAND=%08lx FRAMES=%u TRIS=%lu "
	       "PIXELS=%lu DRAW=%luus MAX=%luus FINISH=%luus STALLS=%lu "
	       "VBL=%lu VBLMIN=%lu VBLMAX=%lu PERIOD=%luus INPUT=%lu LATE=%lu CRC=%08lx\n",
	       FABRIC ? "FABRIC" : "SOFT", (unsigned long)land_crc, (unsigned)FRAMES,
	       (unsigned long)(tris / FRAMES), (unsigned long)(pixels / FRAMES),
	       (unsigned long)(draw / FRAMES / us), (unsigned long)(longest / us),
	       (unsigned long)(finish / FRAMES / us), (unsigned long)(stalls / FRAMES),
	       (unsigned long)vbl, (unsigned long)vbl_min, (unsigned long)vbl_max,
	       (unsigned long)(elapsed / FRAMES / us), (unsigned long)in_applied,
	       (unsigned long)late, (unsigned long)crc);
	return 0;
}
