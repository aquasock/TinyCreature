/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * TinyCreature's terrain renderer: a TCL2 landscape (tools/convert_land.py)
 * walked back to front and sent as shaded screen triangles to a target,
 * either the fabric rasterizer (fpga/raster.sv) or tc_soft, its exact model
 * in software, in integer arithmetic only, so that the AE350 and a PC draw
 * identical frames. The same source builds for both.
 */
#ifndef TINYCREATURE_TERRAIN_H
#define TINYCREATURE_TERRAIN_H

#include <stddef.h>
#include <stdint.h>

#define TC_WIDTH  320
#define TC_HEIGHT 180

/* Palette entries the renderer owns: 0 is never drawn, 1 to 8 the sky from
 * the top down to the horizon, 16 the one blue the sea now draws, 17 and 18
 * the cursor, and 9 to 15 the tall sprite's ramp -- what is left of the sea's
 * eight-entry ramp after entry 23 gave it up. The land file's colours start at
 * TC_LAND_COLOUR. */
#define TC_SKY_COLOUR  1
#define TC_CURSOR_IDLE 17
#define TC_CURSOR_HELD 18
#define TC_CURSOR_EDGE  0
#define TC_SEA_COLOUR  9
#define TC_SPRITE_FIRST TC_SEA_COLOUR   /* the ramp the sprite's cells name */
/* Entries 192 to 255 are the art's: one 64-colour palette every tile this
 * project draws is quantised into, loaded beside the land's and read by the
 * fabric's textured quads. The land takes what is left, 19 to 191. */
#define TC_ART_FIRST   192
#define TC_ART_COLOURS 64
#define TC_LAND_COLOUR 19
#define TC_RAMP        8

struct tc_land {
	uint16_t cells_x, cells_z;   /* cells; vertices are one more each way */
	uint16_t origin_x, origin_z; /* the grid's first cell on the island */
	uint16_t colours, first;     /* the land file's palette entries */
	const uint32_t *palette;     /* 0x00RRGGBB, colours of them */
	const uint8_t *altitude;     /* (cells_x + 1) * (cells_z + 1) */
	const uint8_t *colour;       /* the same vertices' palette entries */
	const uint8_t *cells;        /* cells_x * cells_z: flags byte each */
};

/* A card, exactly as the fabric's CARD command carries one. The caller works
 * every field out -- the pixel range, the steps and the accumulators the fill
 * starts from -- because the fabric has no divider, so a card's fields are
 * the whole of its arithmetic and both renderers take them verbatim. */
struct tc_card {
	uint32_t tile;            /* which tile of the art */
	uint32_t i0, j0, i1, j1;  /* pixels: [i0, i1) across, [j0, j1) down */
	uint32_t du, dv;          /* Q8 texels a pixel, across and down */
	uint32_t u0, v0;          /* Q8 texels the first pixel stands at */
};

/* Where a frame goes. rows fills rows first to end - 1 with one colour;
 * triangle fills a triangle given as three Q4 screen corners, each
 * coordinate within -32768 to 32767, in the order fpga/raster.sv requires,
 * and shaded between the three palette entries colours holds, the first
 * corner's in bits 7:0 and the second's in 15:8; and card fills the
 * rectangle with one tile of the art, its texels written as palette entries
 * from TC_ART_FIRST up, one texel a pixel, without the shading table being
 * consulted at all. A target with no card function is one whose rasterizer
 * cannot draw them. */
struct tc_target {
	void (*rows)(void *ctx, uint32_t first, uint32_t end, uint8_t colour);
	void (*triangle)(void *ctx, const int32_t *x, const int32_t *y,
			 uint32_t colours);
	void (*card)(void *ctx, const struct tc_card *card);
	void *ctx;
	/* The board's cycle counter and the durations it measures into, both NULL
	 * for the host twin: a profile is the board's alone, and the host's frames
	 * must not move because one exists. */
	uint64_t (*now)(void);
	uint64_t *phase;
};

/* The shading the fill does. A triangle's three corners carry three palette
 * entries, and each pixel takes the entry nearest the point of that
 * triangle's colour plane whose barycentric weights are the pixel's, those
 * weights quantised to quarters -- which a triangle a few pixels across
 * cannot tell from the real ones, and which the fabric can do in its fill
 * clock. Colours are mixed in the five bits a channel the game's materials
 * carry, so a colour is 15 bits and the table that turns one back into an
 * entry is 32768 bytes: entry i is the land entry nearest the 15-bit colour
 * i, and the lowest entry wins a tie. Everything that shades reads these two
 * tables and the fabric holds the same numbers, which is what lets the AE350
 * and a PC draw identical frames. */
#define TC_PAL5_ENTRIES 256
#define TC_PAL5_BYTES   (TC_PAL5_ENTRIES * sizeof(uint16_t))
#define TC_LUT_BYTES    32768
void tc_shade_tables(const struct tc_land *land, uint16_t *pal5, uint8_t *lut);

/* The software rasterizer: fpga/raster.sv's fill rule, pixel for pixel,
 * into fb, whose rows are stride bytes apart. It counts what the fabric
 * counts in its TRIS and PIXELS registers. pal5 and lut are
 * tc_shade_tables' output for this land, 512 and 32768 bytes. */
struct tc_soft {
	uint8_t *fb;
	uint32_t stride;
	uint32_t triangles, pixels;
	const uint16_t *pal5;
	const uint8_t *lut;
};
void tc_soft_rows(void *soft, uint32_t first, uint32_t end, uint8_t colour);
void tc_soft_triangle(void *soft, const int32_t *x, const int32_t *y,
		      uint32_t colours);
/* The art's tiles as the cards read them, and how many there are. The host
 * writes them out for the rasterizer's own testbench, which loads them into
 * the unit's store through the same two registers the program uses. */
const uint8_t *tc_art_tiles(void);
unsigned tc_art_tile_count(void);

/* A card: the same fields the fabric's CARD command carries, filled the same
 * way, so that a mismatch between the two is a mismatch of this arithmetic
 * and not of a duplicated copy of it. */
void tc_soft_card(void *soft, const struct tc_card *c);

/* What one frame sent: triangles, after culling, and the cells the walk drew. */
struct tc_stats {
	uint32_t triangles;
	uint32_t cells;
};

/* The phases tc_draw records into tc_target.phase when it has a clock. The
 * cursor and the sprite are inside the walk, so the three say where a frame
 * went rather than what any one thing cost. */
enum {
	TC_PHASE_ROWS = 0,   /* the sky and the sea, a run of rows at a time */
	TC_PHASE_CULL,       /* cull_blocks, once a frame */
	TC_PHASE_WALK,       /* the cell walk and every triangle's submission */
	TC_PHASE_COUNT
};

/* Check a TCL2 file's header and body CRC and point land into it; returns
 * 0, or a short reason. */
const char *tc_land_open(struct tc_land *land, const uint8_t *file, size_t bytes);

/* The 0x00RRGGBB colour of each of the 256 palette entries. */
uint32_t tc_palette(const struct tc_land *land, unsigned index);

/* Working memory tc_draw needs for this land, in bytes -- the vertices, the
 * block culling and the shading tables -- and the call that hands it over
 * (which must be 4-byte aligned) before the first frame. It returns the
 * shading tables, which the target that draws the pixels needs and the
 * fabric must be given. */
size_t tc_work_bytes(const struct tc_land *land);
struct tc_shade {
	const uint16_t *pal5;
	const uint8_t *lut;
};
struct tc_shade tc_init(const struct tc_land *land, void *work);

/* How a mouse count maps onto the camera: dx and dy turn it, the wheel moves
 * it in and out, and a drag covers this fraction of the camera's distance.
 * These four are the whole feel of the camera. They are shared with the host
 * twin so a recorded sequence draws the same frames on both. */
#define TC_TURN_PER_COUNT 128   /* 1/65536 of a turn a count */
#define TC_PITCH_PER_COUNT 24   /* 1/65536 of a turn a count, tilting */
#define TC_ZOOM_PER_COUNT 128   /* Q4 world units a wheel detent */
#define TC_DRAG_DIVISOR 256     /* a count covers distance / this of the world */

/* The mouse's buttons, as its HID boot report has them. */
#define TC_MOUSE_LEFT   0x01u
#define TC_MOUSE_MIDDLE 0x04u
#define TC_MOUSE_RIGHT  0x02u

/* Send frame number frame of frames, one orbit of the island, to target. */
void tc_draw(const struct tc_target *target, uint32_t frame, uint32_t frames,
	     struct tc_stats *stats);

/* Hand the camera one mouse report: the buttons as they are now, and the
 * movement and the wheel since the last one. What they mean is openblack's
 * mapping (core-reference OB-005): the left button drags the landscape, the
 * middle one turns the camera about its focus, and the wheel changes how far
 * from the focus it sits. A run that hands over no reports keeps tc_draw's own
 * scripted orbit, so the frames this project accepted stay where they are. */
void tc_mouse(uint8_t buttons, int32_t dx, int32_t dy, int32_t wheel);

/* IEEE CRC-32, continued from crc (0 to start). */
uint32_t tc_crc32(uint32_t crc, const uint8_t *data, size_t bytes);

#endif
