/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * TinyCreature's first terrain renderer: a TCL1 landscape
 * (tools/convert_land.py) drawn as flat-coloured triangles into a 320x180
 * indexed frame buffer, back to front, in integer arithmetic only, so that
 * the AE350 and a PC draw identical frames. The same source builds for both.
 */
#ifndef TINYCREATURE_TERRAIN_H
#define TINYCREATURE_TERRAIN_H

#include <stddef.h>
#include <stdint.h>

#define TC_WIDTH  320
#define TC_HEIGHT 180

/* Palette entries the renderer owns: 0 is never drawn, 1 to 8 the sky from
 * the top down to the horizon, 9 to 16 the sea from the horizon down; the
 * land file's colours start at TC_LAND_COLOUR. */
#define TC_SKY_COLOUR  1
#define TC_SEA_COLOUR  9
#define TC_LAND_COLOUR 17
#define TC_RAMP        8

struct tc_land {
	uint16_t cells_x, cells_z;   /* cells; vertices are one more each way */
	uint16_t origin_x, origin_z; /* the grid's first cell on the island */
	uint16_t colours, first;     /* the land file's palette entries */
	const uint32_t *palette;     /* 0x00RRGGBB, colours of them */
	const uint8_t *altitude;     /* (cells_x + 1) * (cells_z + 1) */
	const uint8_t *cells;        /* cells_x * cells_z * 3: flags, colours */
};

/* What one frame drew: triangles handed to the rasterizer after culling,
 * and the pixels it filled, overdraw included. */
struct tc_stats {
	uint32_t triangles;
	uint32_t pixels;
};

/* Check a TCL1 file's header and body CRC and point land into it; returns
 * 0, or a short reason. */
const char *tc_land_open(struct tc_land *land, const uint8_t *file, size_t bytes);

/* The 0x00RRGGBB colour of each of the 256 palette entries. */
uint32_t tc_palette(const struct tc_land *land, unsigned index);

/* Working memory tc_draw needs for this land, in bytes, and the call that
 * hands it over (which must be 4-byte aligned) before the first frame. */
size_t tc_work_bytes(const struct tc_land *land);
void tc_init(const struct tc_land *land, void *work);

/* Draw frame number frame of frames, one orbit of the island, into fb,
 * whose rows are stride bytes apart. */
void tc_draw(uint8_t *fb, uint32_t stride, uint32_t frame, uint32_t frames,
	     struct tc_stats *stats);

/* IEEE CRC-32, continued from crc (0 to start). */
uint32_t tc_crc32(uint32_t crc, const uint8_t *data, size_t bytes);

#endif
