// SPDX-License-Identifier: GPL-3.0-or-later
//
// TinyCreature's terrain run on the Tang32 core: asks for a TCL1 land file
// (tools/convert_land.py) with
//   TinyNES WANT <address> <bytes>
// and draws FRAMES frames of one orbit of the island, flipping each at a
// vertical blank. Built with FABRIC=1 (the default) the triangles go to the
// fabric rasterizer (fpga/raster.sv), which draws into its block RAM
// buffers; with FABRIC=0 its model, tc_soft, draws them into the SDRAM
// buffers instead. Either way it reports
//   TinyCreature TERRAIN OK MODE=<FABRIC|SOFT> LAND=<crc> FRAMES=<n>
//     TRIS=<mean> PIXELS=<mean> DRAW=<us> MAX=<us> FINISH=<us> STALLS=<n>
//     VBL=<n> VBLMIN=<n> VBLMAX=<n> PERIOD=<us> LATE=<n> CRC=<crc>
// LAND is the file's CRC-32; TRIS and PIXELS the mean triangles sent and
// pixels they filled per frame; DRAW and MAX the mean and longest CPU time
// to send a frame, FINISH the mean time after that until the rasterizer is
// idle; STALLS the mean bus cycles per frame the CPU waited on a full
// rasterizer FIFO; VBL the vertical blanks 600 frames took, VBLMIN and
// VBLMAX the fewest and most one frame took, PERIOD the mean time per shown
// frame; CRC the CRC-32 of all frames in turn, read back from where they
// were drawn, which terrain_host computes from the same file. The last frame
// stays up. A failed check prints BAD TINYCREATURE <name> and the program
// exits with 1. VBLMAX is what a frame rate is judged by: the display shows
// a frame no sooner than the blank after it is ready, so the shown rate is
// 60/VBLMAX frames a second.
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
#define RASTER_RB_ADDR TN_REG(0x18020)
#define RASTER_RB_DATA TN_REG(0x18024)
#define RASTER_ID_VALUE 0x54435231u /* "TCR1" */
#define RASTER_SHOW   0x1u
#define RASTER_TARGET 0x2u
#define RASTER_BUSY   0x1u

static void fail(const char *name)
{
	printf("BAD TINYCREATURE %s\n", name);
	exit(1);
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

static void fabric_triangle(void *ctx, const int32_t *x, const int32_t *y, uint8_t colour)
{
	(void)ctx;
	RASTER_FIFO = 1u << 28 | colour;
	RASTER_FIFO = (uint32_t)(uint16_t)y[0] << 16 | (uint16_t)x[0];
	RASTER_FIFO = (uint32_t)(uint16_t)y[1] << 16 | (uint16_t)x[1];
	RASTER_FIFO = (uint32_t)(uint16_t)y[2] << 16 | (uint16_t)x[2];
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
	struct tc_land land;
	const char *why = tc_land_open(&land, file, bytes);
	if (why) {
		printf("BAD TINYCREATURE LAND %s\n", why);
		exit(1);
	}
	uint32_t land_crc = tc_crc32(0, file, bytes);
	void *work = malloc(tc_work_bytes(&land));
	if (!work)
		fail("MEMORY");
	tc_init(&land, work);
	for (unsigned i = 0; i < TN_VIDEO_PALETTE_SIZE; i++)
		TN_VIDEO_PALETTE(i) = tc_palette(&land, i);

	struct tc_soft soft = {.stride = TN_VIDEO_FB_STRIDE};
	const struct tc_target target = FABRIC ?
		(struct tc_target){fabric_rows, fabric_triangle, 0} :
		(struct tc_target){tc_soft_rows, tc_soft_triangle, &soft};
	uint32_t late0 = TN_VIDEO_LATE, vbl0 = TN_VIDEO_FRAMES;
	uint32_t stalls0 = FABRIC ? RASTER_STALLS : 0;
	uint32_t crc = 0, lit = 0;
	uint64_t tris = 0, pixels = 0, draw = 0, longest = 0, finish = 0;
	uint32_t vbl_min = ~0u, vbl_max = 0;
	uint64_t start = tn_cycles64();
	for (uint32_t frame = 0; frame < FRAMES; frame++) {
		uint32_t blanks = TN_VIDEO_FRAMES;
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

		// The frame as drawn, read back from where it was drawn.
		lit = 0;
		if (FABRIC) {
			RASTER_RB_ADDR = 0;
			for (uint32_t k = 0; k < TC_WIDTH * TC_HEIGHT / 4; k++) {
				uint32_t w = RASTER_RB_DATA;
				uint8_t b[4] = {(uint8_t)w, (uint8_t)(w >> 8), (uint8_t)(w >> 16),
						(uint8_t)(w >> 24)};
				crc = tc_crc32(crc, b, 4);
				lit += (b[0] != 0) + (b[1] != 0) + (b[2] != 0) + (b[3] != 0);
			}
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
		uint32_t spent = TN_VIDEO_FRAMES - blanks;
		vbl_min = spent < vbl_min ? spent : vbl_min;
		vbl_max = spent > vbl_max ? spent : vbl_max;
	}
	uint64_t elapsed = tn_cycles64() - start;
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
	       "VBL=%lu VBLMIN=%lu VBLMAX=%lu PERIOD=%luus LATE=%lu CRC=%08lx\n",
	       FABRIC ? "FABRIC" : "SOFT", (unsigned long)land_crc, (unsigned)FRAMES,
	       (unsigned long)(tris / FRAMES), (unsigned long)(pixels / FRAMES),
	       (unsigned long)(draw / FRAMES / us), (unsigned long)(longest / us),
	       (unsigned long)(finish / FRAMES / us), (unsigned long)(stalls / FRAMES),
	       (unsigned long)vbl, (unsigned long)vbl_min, (unsigned long)vbl_max,
	       (unsigned long)(elapsed / FRAMES / us), (unsigned long)late,
	       (unsigned long)crc);
	return 0;
}
