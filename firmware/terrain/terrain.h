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
/* Entries 192 to 255 are the art's: one 64-entry palette every tile this
 * project draws is quantised into, loaded beside the land's and read by the
 * fabric's textured quads. Entry 0 of that pool is the transparent key, so the
 * fitted colours are 1 to 63. The land takes what is left, 19 to 191. */
/* A tile of the art is 32 by 32 texels, which is what tools/convert_tiles.py
 * writes and what a card reads, a byte a texel. The generated header says the
 * same and saying it twice, identically, is allowed. */
#define TC_TILE_SIZE  32
#define TC_TILE_PIXELS (TC_TILE_SIZE * TC_TILE_SIZE)
/* Palette-relative texel 0 is the transparent key: the fill skips it, on the
 * host and in fpga/raster.sv alike, so a card is a cutout. */
#define TC_TILE_KEY   0

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

/* A textured triangle: three Q4 screen corners, one tile of the art, and the
 * three planes the fill interpolates -- the tile's u, its v and the reciprocal
 * of the camera-space depth -- each as its value at the first pixel the fill
 * visits, and its step a whole pixel across and a whole row down. The fill
 * steps those planes, adds, and writes the texel the quotient of the first two
 * by the third names, which is what makes the mapping projective rather than
 * affine; the caller works the planes out because the fabric has no divider at
 * setup and does not need one if it is handed the coefficients.
 *
 * A corner's numerator is (u << TC_TEX_SCALE) / z and its denominator
 * (1 << TC_TEX_SCALE) / z, so the quotient is the texel coordinate in Q4 with
 * the scale cancelled. u and v are Q4 texels of the tile, z is Q4 camera-space
 * units, and TC_TEX_SCALE is what keeps the steps and the products the fill
 * takes with them inside 32 bits. The steps are per pixel, not per Q4 unit,
 * because that is what the fill adds: a step given per Q4 unit and added once
 * a pixel walks a plane sixteen times too slowly. */
#define TC_TEX_SCALE 20
struct tc_tex {
	uint32_t tile;             /* which tile of the art */
	int32_t x[3], y[3];        /* Q4 screen corners, in the fill's order */
	int32_t u0, ux, uy;        /* tile u at the first pixel, per pixel, per row */
	int32_t v0, vx, vy;        /* tile v the same way */
	int32_t r0, rx, ry;        /* 1/z the same way */
};

/* A vertex for the fabric's vertex store: TC_SLOTS slots, written by vertex and
 * named three at a time by tri, so a vertex that several triangles share is
 * sent once. A shaded vertex is its Q4 screen corner and its palette entry. A
 * textured one adds the camera-space depth z, Q4 and from NEAR to
 * TC_VERTEX_Z_MAX, the tile, and the tile's u and v at that corner in Q4
 * texels, below 1024; the store works out the three plane values a corner of
 * a textured triangle carries -- (u << TC_TEX_SCALE) / z, (v << TC_TEX_SCALE)
 * / z and (1 << TC_TEX_SCALE) / z -- and a textured tri the planes themselves,
 * with the arithmetic tex_plane in terrain.c does, so the caller sends
 * corners and no coefficients. */
#define TC_SLOTS 1024
#define TC_VERTEX_Z_MAX 0x3fffff
struct tc_vertex {
	uint32_t slot;
	int32_t x, y;              /* Q4 screen corner */
	uint32_t colour;           /* palette entry, shaded */
	int textured;
	uint32_t tile;             /* textured: the tile, its u and v, and z */
	uint32_t u, v;
	int32_t z;
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
	/* A target with no tex function is one whose rasterizer cannot draw a
	 * textured triangle yet, and the program falls back to the columns. */
	void (*tex)(void *ctx, const struct tc_tex *tex);
	void *ctx;
	/* The board's cycle counter and the durations it measures into, both NULL
	 * for the host twin: a profile is the board's alone, and the host's frames
	 * must not move because one exists. */
	uint64_t (*now)(void);
	uint64_t *phase;
	/* The vertex store and the triangles that name it, which a target may
	 * leave out: the program then sends every triangle whole, with its
	 * corners in it, as it did before the store existed. A textured tri takes
	 * its tile from its first vertex. */
	void (*vertex)(void *ctx, const struct tc_vertex *v);
	void (*tri)(void *ctx, uint32_t a, uint32_t b, uint32_t c, int textured);
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

/* Where the camera is, for the readout tc_draw draws when a mouse is driving
 * it and for a run's report: the focus and the eye in the land's own cells,
 * and the turn in degrees clockwise from the grid's own north. */
void tc_camera(int32_t *focus_x, int32_t *focus_z, int32_t *eye_x,
	       int32_t *eye_z, int32_t *turn);

/* The cell this build stands a card on, if it was built with one: TC_PIN_X and
 * TC_PIN_Z name it, and a build without them returns 0. It is the one thing
 * this renderer has that is at a place in the world and not the camera. */
int tc_pin(int32_t *x, int32_t *z);

/* A card: the same fields the fabric's CARD command carries, filled the same
 * way, so that a mismatch between the two is a mismatch of this arithmetic
 * and not of a duplicated copy of it. */
void tc_soft_card(void *soft, const struct tc_card *c);
/* The same for a textured triangle: the twin implements fpga/raster.sv's fill
 * rule for the TEX command, stepping the three planes the caller handed over
 * and dividing, with the same truncation and the same clamp on the texel. */
void tc_soft_tex(void *soft, const struct tc_tex *t);
/* The vertex store and its triangles, as fpga/raster.sv's VTX, VTXT, TRIV and
 * TEXV commands draw them: a stored triangle is filled exactly as the same
 * triangle sent whole would be, and a textured one with the planes tex_plane
 * gives, so the store moves no pixel. */
void tc_soft_vertex(void *soft, const struct tc_vertex *v);
void tc_soft_tri(void *soft, uint32_t a, uint32_t b, uint32_t c, int textured);

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
	/* The four below are cycles, not microseconds, and are collected only
	 * when the build asks for them (TC_PHASE_DETAIL): they time a sample of
	 * cells -- one in 64 -- so the clock reads do not cost more than the
	 * work they measure.  TC_PHASE_SAMPLES counts the sampled cells, which
	 * turns the cycle totals into a per-cell cost. */
	TC_PHASE_VERTEX,     /* inside vertex() for the sampled cells */
	TC_PHASE_SUBMIT,     /* inside submit(), emission included */
	TC_PHASE_EMIT,       /* inside the fill's own triangle call */
	TC_PHASE_PLANT,      /* draw_plant_cell, the ready-made plants */
	TC_PHASE_SPRITE,     /* draw_sprite, the tall sprite */
	TC_PHASE_SAMPLES,
	TC_PHASE_COUNT
};

#ifndef TC_PHASE_DETAIL
#define TC_PHASE_DETAIL 0
#endif

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
