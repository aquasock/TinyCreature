// SPDX-License-Identifier: GPL-3.0-or-later
//
// TinyCreature's terrain run on the Tang32 core: asks for a TCL1 land file
// (tools/convert_land.py) with
//   TinyNES WANT <address> <bytes>
// draws FRAMES frames of one orbit of the island into the two 320x180
// frame buffers, flipping each at a vertical blank, and reports
//   TinyCreature TERRAIN OK LAND=<crc> FRAMES=<n> TRIS=<mean> PIXELS=<mean>
//     DRAW=<us> MAX=<us> PERIOD=<us> VBL=<n> LATE=<n> CRC=<crc>
// LAND is the file's CRC-32, TRIS and PIXELS the mean triangles rasterized
// and pixels filled per frame, DRAW and MAX the mean and longest time to
// draw a frame, PERIOD the mean time per shown frame, and CRC the CRC-32 of
// all frames in turn, which terrain_host computes from the same file. The
// last frame stays up after the program ends. A failed check prints
// BAD TINYCREATURE <name> and the program exits with 1.
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
#define FILE_MAGIC 0x31524e54u /* "TNR1", from load_ae350.py --file */
#define FILE_MAX   (1u << 20)

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

int main(void)
{
	if (TN_VIDEO_ID != TN_VIDEO_ID_VALUE)
		fail("VIDEO ID");
	if (TN_VIDEO_WIDTH != TC_WIDTH || TN_VIDEO_HEIGHT != TC_HEIGHT)
		fail("VIDEO SIZE");
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

	uint32_t late0 = TN_VIDEO_LATE, vbl0 = TN_VIDEO_FRAMES;
	uint32_t crc = 0, lit = 0;
	uint64_t tris = 0, pixels = 0, draw = 0, longest = 0;
	uint64_t start = tn_cycles64();
	for (uint32_t frame = 0; frame < FRAMES; frame++) {
		uint32_t back = (TN_VIDEO_STATUS & TN_VIDEO_BUFFER) ? 0u : 1u;
		struct tc_stats stats;
		uint64_t t0 = tn_cycles64();
		tc_draw(TN_VIDEO_FB(back), TN_VIDEO_FB_STRIDE, frame, FRAMES, &stats);
		uint64_t spent = tn_cycles64() - t0;
		draw += spent;
		longest = spent > longest ? spent : longest;
		tris += stats.triangles;
		pixels += stats.pixels;
		lit = 0;
		for (uint32_t y = 0; y < TC_HEIGHT; y++) {
			const uint8_t *row = TN_VIDEO_FB_ROW(back, y);
			crc = tc_crc32(crc, row, TC_WIDTH);
			for (uint32_t x = 0; x < TC_WIDTH; x++)
				lit += row[x] != 0;
		}
		tn_dcache_wbinval();
		TN_VIDEO_CTRL = TN_VIDEO_ENABLE | (back ? TN_VIDEO_BUFFER : 0u);
		uint32_t want = TN_VIDEO_SHOWING | (back ? TN_VIDEO_BUFFER : 0u);
		uint64_t wait = tn_cycles64();
		while ((TN_VIDEO_STATUS & (TN_VIDEO_SHOWING | TN_VIDEO_BUFFER)) != want)
			if (tn_cycles64() - wait > TN_CORE_HZ / 10u)
				fail("FLIP");
	}
	uint64_t elapsed = tn_cycles64() - start;
	uint32_t vbl = TN_VIDEO_FRAMES - vbl0;
	uint32_t late = TN_VIDEO_LATE - late0;
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
	printf("TinyCreature TERRAIN OK LAND=%08lx FRAMES=%u TRIS=%lu PIXELS=%lu "
	       "DRAW=%luus MAX=%luus PERIOD=%luus VBL=%lu LATE=%lu CRC=%08lx\n",
	       (unsigned long)land_crc, (unsigned)FRAMES,
	       (unsigned long)(tris / FRAMES), (unsigned long)(pixels / FRAMES),
	       (unsigned long)(draw / FRAMES / us), (unsigned long)(longest / us),
	       (unsigned long)(elapsed / FRAMES / us), (unsigned long)vbl,
	       (unsigned long)late, (unsigned long)crc);
	return 0;
}
