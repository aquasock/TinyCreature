/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * TinyCreature's terrain renderer: a TCL1 landscape (tools/convert_land.py)
 * walked back to front and sent as flat-coloured screen triangles to a
 * target, either the fabric rasterizer (fpga/raster.sv) or tc_soft, its
 * exact model in software, in integer arithmetic only, so that the AE350
 * and a PC draw identical frames. The same source builds for both.
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

/* Where a frame goes. rows fills rows first to end - 1 with one colour;
 * triangle fills a triangle given as three Q4 screen corners, each
 * coordinate within -32768 to 32767, in the order fpga/raster.sv requires.
 * Both are exactly the fabric rasterizer's ROWS and TRI commands. */
struct tc_target {
	void (*rows)(void *ctx, uint32_t first, uint32_t end, uint8_t colour);
	void (*triangle)(void *ctx, const int32_t *x, const int32_t *y, uint8_t colour);
	void *ctx;
};

/* The software rasterizer: fpga/raster.sv's fill rule, pixel for pixel,
 * into fb, whose rows are stride bytes apart. It counts what the fabric
 * counts in its TRIS and PIXELS registers. */
struct tc_soft {
	uint8_t *fb;
	uint32_t stride;
	uint32_t triangles, pixels;
};
void tc_soft_rows(void *soft, uint32_t first, uint32_t end, uint8_t colour);
void tc_soft_triangle(void *soft, const int32_t *x, const int32_t *y, uint8_t colour);

/* What one frame sent: triangles, after culling. */
struct tc_stats {
	uint32_t triangles;
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

/* Send frame number frame of frames, one orbit of the island, to target. */
void tc_draw(const struct tc_target *target, uint32_t frame, uint32_t frames,
	     struct tc_stats *stats);

/* IEEE CRC-32, continued from crc (0 to start). */
uint32_t tc_crc32(uint32_t crc, const uint8_t *data, size_t bytes);

#endif
