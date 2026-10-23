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
//     CELLS=<mean> PHROWS=<us> PHCULL=<us> PHWALK=<us> FABRIC=<us>
//     CAMFOCUS=<x>,<z> CAMEYE=<x>,<z> CAMTURN=<degrees> PIN=<x>,<z>|none
// LAND is the file's CRC-32; TRIS and PIXELS the mean triangles sent and
// pixels they filled per frame; DRAW and MAX the mean and longest CPU time
// to send a frame, FINISH the mean time after that until the rasterizer is
// idle; STALLS the mean bus cycles per frame the CPU waited on a full
// rasterizer FIFO; VBL the vertical blanks 600 frames took, VBLMIN and
// VBLMAX the fewest and most one frame took, PERIOD the mean time per shown
// frame; CRC the CRC-32 of all frames in turn, which terrain_host computes
// from the same file over the same bytes; CELLS the mean cells the walk drew;
// and PHROWS, PHCULL and PHWALK the mean time the frame spent in the sky and
// sea rows, in the block cull and in the cell walk, which is this program's
// own profile of a frame, taken with the core's cycle counter and left out of
// the host's line because the host has no such counter; FABRIC is the mean
// time a frame kept the rasterizer itself busy, from its own BUSY counter,
// which is how close the fabric is to setting the pace instead of the CPU. CAMFOCUS and CAMEYE
// are the cells the camera ended the run looking at and standing in, and
// CAMTURN its bearing in degrees: what the readout draws when a mouse is
// driving the camera, and the last frame of the orbit when nothing is. With
// the fabric drawing, that CRC
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
#define RASTER_TILES_A TN_REG(0x18034)
#define RASTER_TILES_D TN_REG(0x18038)
#define RASTER_BUSYCYC TN_REG(0x1803c)
/* The walker's own way in: the land store, the frame's walk, and the camera
 * file the transform reads. fpga/raster.sv explains each. */
#define RASTER_LAND_A  TN_REG(0x18040)
#define RASTER_LAND_D  TN_REG(0x18044)
#define RASTER_WALK_X  TN_REG(0x18048)
#define RASTER_WALK_Z  TN_REG(0x1804c)
#define RASTER_WALK_GRID TN_REG(0x18050)
#define RASTER_WALK_BLK_I TN_REG(0x18054)
#define RASTER_WALK_BLK_D TN_REG(0x18058)
#define RASTER_WALK_GO TN_REG(0x1805c)
#define RASTER_WALK_ST TN_REG(0x18060)
#define RASTER_WALK_N  TN_REG(0x18068)
#define RASTER_CAM_A   TN_REG(0x1806c)
#define RASTER_CAM_D   TN_REG(0x18070)
#ifndef TC_FABRIC_WALK
#define TC_FABRIC_WALK 0
#endif
#define RASTER_BUS_MHZ 75u   /* the bus clock the BUSY counter counts */
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

/* Whether the program hands the link back to the desk layer once it is about
 * to draw, so that the board's own mouse and keyboard drive it.  Off by
 * default: see the use, and what it does to a gated run. */
#ifndef TC_HANDOVER
#define TC_HANDOVER 0
#endif

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

#if TC_FABRIC_WALK
/* The land, packed for the fabric's walker: two vertices a word, {colour,
 * altitude} each with the low vertex first, then the cells' flag nibbles,
 * eight to a word. It is the shape tools/pack_land.py writes for the unit's
 * testbench, and the stride the walker reads is the land's own, cells_x + 1. */
static void fabric_land_upload(const struct tc_land *land)
{
	uint32_t vx = (uint32_t)land->cells_x + 1u;
	uint32_t vz = (uint32_t)land->cells_z + 1u;
	uint32_t vertices = vx * vz;
	RASTER_LAND_A = 0;
	for (uint32_t i = 0; i < vertices; i += 2u) {
		uint32_t w = (uint32_t)land->altitude[i] |
			     (uint32_t)land->colour[i] << 8;
		if (i + 1u < vertices)
			w |= ((uint32_t)land->altitude[i + 1u] |
			      (uint32_t)land->colour[i + 1u] << 8) << 16;
		RASTER_LAND_D = w;
	}
	uint32_t cells = (uint32_t)land->cells_x * (uint32_t)land->cells_z;
	RASTER_LAND_A = 0x10000u;
	for (uint32_t i = 0; i < cells; i += 8u) {
		uint32_t w = 0;
		for (uint32_t k = 0; k < 8u && i + k < cells; k++)
			w |= (uint32_t)(land->cells[i + k] & 7u) << (4u * k);
		RASTER_LAND_D = w;
	}
	while (RASTER_STATUS & RASTER_BUSY)
		;
}

static void walk_hung(uint32_t walk, const char *at)
{
	printf("BAD TINYCREATURE WALK %s WALKS=%u ST=%02x STATUS=%x CELLS=%u "
	       "TRIS=%u PIXELS=%u STALLS=%u\n", at, (unsigned)walk,
	       (unsigned)RASTER_WALK_ST, (unsigned)RASTER_STATUS,
	       (unsigned)RASTER_WALK_N, (unsigned)RASTER_TRIS,
	       (unsigned)RASTER_PIXELS, (unsigned)RASTER_STALLS);
	exit(1);
}

/* One frame's walk in the fabric: the camera file, the camera cell, the grid
 * and the blocks the cull kept, then the start. The unit reports when its
 * assembly has gone idle after the walk, which is when the frame is done. */
static void fabric_walk(void *ctx, const uint8_t *shown, uint32_t bx,
			uint32_t bz, uint32_t cells_x, uint32_t cells_z,
			const int32_t cam[7], uint32_t cx, uint32_t cz)
{
	(void)ctx;
	for (unsigned k = 0; k < 7u; k++) {
		RASTER_CAM_A = k;
		RASTER_CAM_D = (uint32_t)cam[k];
	}
	RASTER_WALK_X = cx;
	RASTER_WALK_Z = cz;
	RASTER_WALK_GRID = cells_z << 16 | cells_x;
	uint32_t words = (bx * bz + 31u) / 32u;
	for (uint32_t w = 0; w < words; w++) {
		uint32_t bits = 0;
		for (uint32_t k = 0; k < 32u; k++) {
			uint32_t b = w * 32u + k;
			/* 1 is a block the fabric walks: 2 is one the program
			 * draws itself, 0 culled and 0xff no land at all. */
			if (b < bx * bz && shown[b] == 1)
				bits |= 1u << k;
		}
		RASTER_WALK_BLK_I = w;
		RASTER_WALK_BLK_D = bits;
	}
	RASTER_WALK_GO = 3u;
	/* The walk clears its done bit when it takes the start, so the frame is
	 * over when that bit is back with the assembly idle. A walk is a few tens
	 * of milliseconds; one still running after two seconds has hung, and the
	 * unit's state is reported rather than the board left frozen. */
	static uint32_t walks;
	uint64_t t0 = tn_cycles64();
	while (RASTER_WALK_ST & 0x10u)
		if (tn_cycles64() - t0 > 2ull * TN_CORE_HZ)
			walk_hung(walks, "START");
	while ((RASTER_WALK_ST & 0x30u) != 0x30u)
		if (tn_cycles64() - t0 > 2ull * TN_CORE_HZ)
			walk_hung(walks, "DONE");
	walks++;
}
#endif

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

// A card's five words, which fpga/raster.sv reads as CARD: the opcode with the
// tile, the first pixel of the rectangle, the last, the Q8 steps and the
// accumulators to start from. Everything the fill needs is worked out here,
// because the fabric has no divider.
static void fabric_card(void *ctx, const struct tc_card *c)
{
	(void)ctx;
	RASTER_FIFO = 3u << 28 | c->tile << 16;
	RASTER_FIFO = c->j0 << 16 | c->i0;
	RASTER_FIFO = c->j1 << 16 | c->i1;
	RASTER_FIFO = c->dv << 16 | c->du;
	RASTER_FIFO = c->v0 << 16 | c->u0;
	/* The depth plane whole: D at the first pixel and its two steps, each
	 * 32 bits, because a near card's D is near 2^23 and a step between
	 * adjacent pixels of it does not fit in sixteen. */
	RASTER_FIFO = (uint32_t)c->d0;
	RASTER_FIFO = (uint32_t)c->dx;
	RASTER_FIFO = (uint32_t)c->dy;
}

// A textured triangle's thirteen words, which fpga/raster.sv reads as TEX: the
// opcode with the tile, the three Q4 corners, and the nine plane numbers the
// fill steps -- the tile's u, its v and the reciprocal of depth, each as its
// value at the first pixel of the triangle's clamped bounding box and its step
// a pixel across and a row down. All of it is worked out here, because the
// fabric has no divider at setup and needs none when it is handed the
// coefficients. A target with no tex function is one whose rasterizer cannot
// fill one, and the program falls back to the columns.
static void fabric_tex(void *ctx, const struct tc_tex *t)
{
	(void)ctx;
	RASTER_FIFO = 4u << 28 | (t->tile & 0xffffu) << 16;
	for (unsigned k = 0; k < 3; k++)
		RASTER_FIFO = (uint32_t)(uint16_t)t->y[k] << 16 |
			      (uint32_t)(uint16_t)t->x[k];
	const int32_t n[9] = { t->u0, t->ux, t->uy, t->v0, t->vx,
			       t->vy, t->r0, t->rx, t->ry };
	for (unsigned k = 0; k < 9; k++)
		RASTER_FIFO = (uint32_t)n[k];
}

// A vertex into the fabric's store, which fpga/raster.sv reads as VTX or VTXT,
// three words each: the opcode and the ten-bit slot with the palette entry, or
// with the tile and v; the Q4 screen corner; and the shaded vertex's depth,
// (1 << 30) / z, or the textured one's u and z, from which the store works the
// corner's plane values and its depth out itself.
static void fabric_vertex(void *ctx, const struct tc_vertex *v)
{
	(void)ctx;
	if (!v->textured) {
		RASTER_FIFO = 5u << 28 | v->slot << 18 | v->colour;
		RASTER_FIFO = (uint32_t)(uint16_t)v->y << 16 | (uint16_t)v->x;
		RASTER_FIFO = v->depth;
		return;
	}
	RASTER_FIFO = 6u << 28 | v->slot << 18 | v->tile << 12 | v->v << 2;
	RASTER_FIFO = (uint32_t)(uint16_t)v->y << 16 | (uint16_t)v->x;
	RASTER_FIFO = v->u << 22 | (uint32_t)v->z;
}

// A triangle of three stored vertices, one word: the top two bits 11 for TRIV,
// shaded, and 10 for TEXV, textured, then three ten-bit slots.
static void fabric_tri(void *ctx, uint32_t a, uint32_t b, uint32_t c,
		       int textured)
{
	(void)ctx;
	RASTER_FIFO = (textured ? 2u : 3u) << 30 | a << 20 | b << 10 | c;
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

#if TC_CARDS || TC_TREES || TC_PLANTS
// The art's tiles, four bytes a write through TILES_ADDR and TILES_DATA,
// which is the shape the frame read-back and the palette already use. Without
// this the store is whatever the block RAM powers up as, and a card or tree
// drawn from it has the right geometry in the wrong colours -- which is
// exactly how the first hardware run of each failed.
static void fabric_tiles(void)
{
	const uint8_t *art = tc_art_tiles();
	unsigned bytes = tc_art_tile_count() * 1024;
	for (unsigned i = 0; i < bytes; i += 4) {
		RASTER_TILES_A = i;
		RASTER_TILES_D = (uint32_t)art[i + 3] << 24 |
				 (uint32_t)art[i + 2] << 16 |
				 (uint32_t)art[i + 1] << 8 | art[i];
	}
}
#endif

/* The core's cycle counter, as tc_draw's clock: the phases it measures are the
 * board's profile of a frame, and the host twin passes nothing here because it
 * has no such counter and its frames must not move. */
static uint64_t phase_now(void)
{
	return tn_cycles64();
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
#if TC_CARDS || TC_TREES || TC_PLANTS
	if (FABRIC)
		fabric_tiles();
#endif

	struct tc_soft soft = {.stride = TN_VIDEO_FB_STRIDE,
			       .pal5 = shade.pal5, .lut = shade.lut};
	if (!FABRIC) {
		/* The software path keeps its own depth buffer, as the fabric does. */
		soft.zbuf = malloc(TC_WIDTH * TC_HEIGHT * sizeof(uint32_t));
		if (!soft.zbuf)
			fail("MEMORY");
	}
	/* The frame's phases, this frame's and the run's, and the cells the walk
	 * drew: where the phase fields of the report come from. */
	uint64_t phase[TC_PHASE_COUNT] = {0};
	uint64_t phase_sum[TC_PHASE_COUNT] = {0};
	uint64_t cells = 0;
	uint64_t plant_seen = 0, plant_culled = 0, plant_cards = 0;
	const struct tc_target target = FABRIC ?
		(struct tc_target){fabric_rows, fabric_triangle, fabric_card,
				   fabric_tex, 0, phase_now, phase,
				   fabric_vertex, fabric_tri,
#if TC_FABRIC_WALK
				   fabric_walk
#else
				   0
#endif
				   , TN_CORE_HZ} :
		(struct tc_target){tc_soft_rows, tc_soft_triangle, tc_soft_card,
				   tc_soft_tex, &soft, phase_now, phase,
				   tc_soft_vertex, tc_soft_tri, 0, TN_CORE_HZ};
#if TC_FABRIC_WALK
	if (FABRIC)
		fabric_land_upload(&land);
#endif
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
	uint64_t tris = 0, pixels = 0, draw = 0, longest = 0, finish = 0, fabric = 0;
	uint32_t vbl_min = ~0u, vbl_max = 0;
	uint64_t start = tn_cycles64();
	/* The link goes back to the desk layer here, before the first frame, which
	 * is what lets the board's own mouse and keyboard reach this program:
	 * TinyTang sends them as input frames only while no host holds the link
	 * (core-reference TANG-001), and a loader holds it until it sees this line.
	 * Tiny89's program prints the same one for the same reason.  It is off in
	 * the gated builds -- `HANDOVER=0` is the default and `run_tang32.sh`
	 * passes nothing -- because their frames come from the input replayed out
	 * of the land file's tail and must not have a live mouse moving the camera
	 * under them. */
#if TC_HANDOVER
	printf("TinyNES LINK\n");
	fflush(stdout);
#endif
	for (uint32_t frame = 0; frame < FRAMES; frame++) {
		uint32_t blanks = TN_VIDEO_FRAMES;
		in_applied += input_frame(frame);
		uint32_t back = (TN_VIDEO_STATUS & TN_VIDEO_BUFFER) ? 0u : 1u;
		uint32_t tris0 = 0, pixels0 = 0, busy0 = 0;
		if (FABRIC) {
			RASTER_CTRL = RASTER_SHOW | (back ? RASTER_TARGET : 0u);
			tris0 = RASTER_TRIS;
			pixels0 = RASTER_PIXELS;
			busy0 = RASTER_BUSYCYC;
		} else {
			soft.fb = TN_VIDEO_FB(back);
			soft.triangles = soft.pixels = 0;
		}
		struct tc_stats stats;
		uint64_t t0 = tn_cycles64();
		tc_draw(&target, frame, FRAMES, &stats);
		uint64_t t1 = tn_cycles64();
		for (unsigned p = 0; p < TC_PHASE_COUNT; p++)
			phase_sum[p] += phase[p];
		cells += stats.cells;
		plant_seen += stats.plant_seen;
		plant_culled += stats.plant_culled;
		plant_cards += stats.plant_cards;
		if (FABRIC)
			while (RASTER_STATUS & RASTER_BUSY)
				if (tn_cycles64() - t1 > TN_CORE_HZ / 10u)
					fail("RASTER BUSY");
		uint64_t t2 = tn_cycles64();
		if (FABRIC)
			fabric += RASTER_BUSYCYC - busy0;
		draw += t1 - t0;
		longest = t1 - t0 > longest ? t1 - t0 : longest;
		finish += t2 - t1;
		uint32_t sent = FABRIC ? RASTER_TRIS - tris0 : soft.triangles;
		if (TC_FABRIC_WALK && FABRIC)
			tris += sent;      /* the fabric named them, not the program */
		else {
			if (sent != stats.triangles)
				fail("TRIS");
			tris += stats.triangles;
		}
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
	/* Where the camera ended the run: the focus and the eye in the island's own
	 * cells and the bearing in degrees, which is what the readout draws. A
	 * scripted run reports the last frame of its orbit. */
	int32_t cam_focus_x, cam_focus_z, cam_eye_x, cam_eye_z, cam_turn;
	tc_camera(&cam_focus_x, &cam_focus_z, &cam_eye_x, &cam_eye_z, &cam_turn);
	printf("TinyCreature TERRAIN OK MODE=%s LAND=%08lx FRAMES=%u TRIS=%lu "
	       "PIXELS=%lu DRAW=%luus MAX=%luus FINISH=%luus STALLS=%lu "
	       "VBL=%lu VBLMIN=%lu VBLMAX=%lu PERIOD=%luus INPUT=%lu LATE=%lu "
	       "CRC=%08lx CELLS=%lu PHROWS=%luus PHCULL=%luus PHWALK=%luus "
	       "FABRIC=%luus CAMFOCUS=%ld,%ld CAMEYE=%ld,%ld CAMTURN=%ld "
	       "PLANT=%luus PSCAN=%luus PCARDS=%lu PSEEN=%lu PCULL=%lu",
	       FABRIC ? "FABRIC" : "SOFT", (unsigned long)land_crc, (unsigned)FRAMES,
	       (unsigned long)(tris / FRAMES), (unsigned long)(pixels / FRAMES),
	       (unsigned long)(draw / FRAMES / us), (unsigned long)(longest / us),
	       (unsigned long)(finish / FRAMES / us), (unsigned long)(stalls / FRAMES),
	       (unsigned long)vbl, (unsigned long)vbl_min, (unsigned long)vbl_max,
	       (unsigned long)(elapsed / FRAMES / us), (unsigned long)in_applied,
	       (unsigned long)late, (unsigned long)crc,
	       (unsigned long)(cells / FRAMES),
	       (unsigned long)(phase_sum[TC_PHASE_ROWS] / FRAMES / us),
	       (unsigned long)(phase_sum[TC_PHASE_CULL] / FRAMES / us),
	       (unsigned long)(phase_sum[TC_PHASE_WALK] / FRAMES / us),
	       (unsigned long)(fabric / FRAMES / RASTER_BUS_MHZ),
	       (long)cam_focus_x, (long)cam_focus_z, (long)cam_eye_x,
	       (long)cam_eye_z, (long)cam_turn,
	       (unsigned long)(phase_sum[TC_PHASE_PLANT] / FRAMES / us),
	       (unsigned long)(phase_sum[TC_PHASE_PSCAN] / FRAMES / us),
	       (unsigned long)(plant_cards / FRAMES),
	       (unsigned long)(plant_seen / FRAMES),
	       (unsigned long)(plant_culled / FRAMES));
	/* The cell this build stands its card on, if it has one: the one thing in the
	 * world that is not the camera, and what a pinned build is for. */
	int32_t pin_x, pin_z;
	if (tc_pin(&pin_x, &pin_z))
		printf(" PIN=%ld,%ld\n", (long)pin_x, (long)pin_z);
	else
		printf(" PIN=none\n");
#if TC_PHASE_DETAIL
	/* The walk split four ways, a sample of cells scaled to a frame: what a
	 * sampled cell spent in its vertices, in submit(), inside the fill's
	 * triangle call, and in the cell's own work, which is the walk less the
	 * other two.  Zero on a build that did not ask for the detail. */
	if (phase_sum[TC_PHASE_SAMPLES] != 0) {
		uint64_t cells_a_frame = cells / FRAMES;
		uint64_t vert = phase_sum[TC_PHASE_VERTEX] /
				phase_sum[TC_PHASE_SAMPLES] * cells_a_frame / us;
		uint64_t sub = phase_sum[TC_PHASE_SUBMIT] /
			       phase_sum[TC_PHASE_SAMPLES] * cells_a_frame / us;
		uint64_t emit = phase_sum[TC_PHASE_EMIT] /
				phase_sum[TC_PHASE_SAMPLES] * cells_a_frame / us;
		uint64_t walk = phase_sum[TC_PHASE_WALK] / FRAMES / us;
		uint64_t plant = phase_sum[TC_PHASE_PLANT] / FRAMES / us;
		uint64_t sprite = phase_sum[TC_PHASE_SPRITE] / FRAMES / us;
		printf("TinyCreature PHASE CELL=%luus VERT=%luus SUB=%luus "
		       "EMIT=%luus PLANT=%luus SPRITE=%luus SAMPLES=%lu\n",
		       (unsigned long)(walk - vert - sub - plant - sprite),
		       (unsigned long)vert, (unsigned long)sub,
		       (unsigned long)emit, (unsigned long)plant,
		       (unsigned long)sprite,
		       (unsigned long)(phase_sum[TC_PHASE_SAMPLES] / FRAMES));
	}
#endif
	return 0;
}
