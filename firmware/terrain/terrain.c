// SPDX-License-Identifier: GPL-3.0-or-later
//
// The terrain renderer in terrain.h. World units are openblack's (a cell is
// 10 units, an altitude step 0.67) held in Q4; angles are 1/65536 of a turn;
// sines are Q14. The camera orbits the island at a fixed pitch. Each frame
// clears to a sky and sea split at the horizon, culls the 16x16-cell blocks
// against the view, then walks the cells back to front, the rows farthest
// from the camera's row first and in each row the columns farthest from its
// column first, which on a height field leaves the nearer cell on top. Each
// triangle goes through submit(), which clips it at the near plane, culls
// back faces and triangles off the screen, and hands the rest to the
// target: the fabric rasterizer, or tc_soft, which fills exactly what the
// fabric fills.
#include "terrain.h"

#include <string.h>

#define CELL      160   // a cell, 10 units, in Q4
#define NEAR      128   // the near plane, 8 units, in Q4
#define FOCAL     256   // pixels per unit of x / z: about 64 degrees across
#define PITCH     2731  // 15 degrees down
#define TAN_PITCH 4390  // tan(15 degrees), Q14
#define LIFT      1920  // 120 units above the line to the centre
#define BLOCK     16    // cells a side in a block
#define GUARD     32000 // Q4: corners sent to a target stay within 2000 pixels

// A vertex, 8 bytes so that a frame's walk writes as little to the SDRAM as
// it can, and so that four vertices share a cache line. The camera-space
// position it was computed from is not kept: the record holds what every
// drawn triangle needs, and the rare vertex that needs more recomputes it
// from its place in the grid.
struct vertex {
	int16_t sx, sy;    // screen, Q4, exact when VERT_FRONT
	uint32_t stamp;    // generation << 2 | state
};

// What a vertex's record holds, in the two low bits of stamp.
#define VERT_FRONT  0u  // in front of the near plane, both coordinates exact
#define VERT_BEHIND 1u  // behind the near plane, so no screen position
#define VERT_WIDE   2u  // in front, but a screen coordinate did not fit int16

static const struct tc_land *land;
static struct vertex *vertices;
/* The palette in five bits a channel and the table back to an entry,
 * tc_init's own, in the working memory beside the vertices. */
static const uint16_t *shade_pal5;
static const uint8_t *shade_lut;
static uint8_t *block_low, *block_high, *block_shown;
static uint32_t verts_x, blocks_x, blocks_z, generation;
static int32_t cam_x, cam_y, cam_z, sin_yaw, cos_yaw, sin_pitch, cos_pitch;
// The cursor: a hand drawn in two colours, its outline the deepest sea and
// its fill the palest sky, which are the program's own colours and so are the
// same on every land. It is what the mouse moves and what a left drag takes
// hold of the land with, so it is drawn last, over everything. Each row of it
// is a few runs of one colour, and a run is two triangles: the CPU cannot
// write the rasterizer's pixels, only send it triangles.
#define TC_HAND_W 13
#define TC_HAND_H 15
#define TC_CURSOR_FILL    (TC_SKY_COLOUR + TC_RAMP - 1)
#define TC_CURSOR_OUTLINE (TC_SEA_COLOUR + TC_RAMP - 1)

// The outline is derived rather than drawn, so the shape below is only the
// hand: the tip of the pointing finger is at its top left, which is also the
// cursor's hotspot.
static const char *const hand_shape[TC_HAND_H] = {
	"  ##         ",
	"  ##         ",
	"  ##         ",
	"  ##         ",
	"  ##         ",
	"  ## ## ##   ",
	"  ## ## ##   ",
	"  ## ## ##   ",
	"  ########   ",
	"  ########   ",
	"#### ######  ",
	"###########  ",
	"  ########   ",
	"   ######    ",
	"   #####     ",
};

struct hand_run {
	int16_t y, x, length;
	uint8_t colour;
};

static struct hand_run hand_runs[128];
static uint32_t hand_runs_used;
static int32_t cursor_x, cursor_y;   // Q4 screen pixels, at the fingertip

static void hand_build(void)
{
	uint8_t grid[TC_HAND_H][TC_HAND_W];

	for (int32_t y = 0; y < TC_HAND_H; y++)
		for (int32_t x = 0; x < TC_HAND_W; x++) {
			if (hand_shape[y][x] == '#') {
				grid[y][x] = TC_CURSOR_FILL;
				continue;
			}
			// One ring out from the hand is its outline.
			grid[y][x] = 0;
			for (int32_t dy = -1; dy <= 1 && !grid[y][x]; dy++)
				for (int32_t dx = -1; dx <= 1; dx++) {
					int32_t ny = y + dy, nx = x + dx;
					if (ny < 0 || ny >= TC_HAND_H ||
					    nx < 0 || nx >= TC_HAND_W)
						continue;
					if (hand_shape[ny][nx] == '#') {
						grid[y][x] = TC_CURSOR_OUTLINE;
						break;
					}
				}
		}

	hand_runs_used = 0;
	for (int32_t y = 0; y < TC_HAND_H; y++)
		for (int32_t x = 0; x < TC_HAND_W;) {
			uint8_t colour = grid[y][x];
			if (!colour) {
				x++;
				continue;
			}
			int32_t start = x;
			while (x < TC_HAND_W && grid[y][x] == colour)
				x++;
			if (hand_runs_used <
			    sizeof hand_runs / sizeof hand_runs[0]) {
				hand_runs[hand_runs_used].y = (int16_t)y;
				hand_runs[hand_runs_used].x = (int16_t)start;
				hand_runs[hand_runs_used].length =
					(int16_t)(x - start);
				hand_runs[hand_runs_used].colour = colour;
				hand_runs_used++;
			}
		}
}

static const struct tc_target *out;
static struct tc_stats *counts;
// The camera the mouse drives, in openblack's terms (core-reference OB-005):
// the point on the land it looks at, the angle and tilt it looks from, and how
// far from that point it sits. The scripted orbit fills the same camera when
// no report has arrived, which is what keeps a run without input drawing the
// frames this project accepted.
static int32_t cam_focus_x, cam_focus_y, cam_focus_z;  // Q4 world units
static int32_t cam_turn;                               // 1/65536 of a turn
static int32_t cam_pitch;                              // 1/65536 of a turn
static int32_t cam_dist;                               // Q4, focus to camera
static int cam_driven;

static uint32_t read32(const uint8_t *p)
{
	return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

static uint16_t read16(const uint8_t *p)
{
	return (uint16_t)(p[0] | p[1] << 8);
}

uint32_t tc_crc32(uint32_t crc, const uint8_t *data, size_t bytes)
{
	static uint32_t table[256];
	if (!table[1])
		for (uint32_t i = 0; i < 256; i++) {
			uint32_t c = i;
			for (int k = 0; k < 8; k++)
				c = (c >> 1) ^ (0xedb88320u & -(c & 1));
			table[i] = c;
		}
	crc = ~crc;
	while (bytes--)
		crc = table[(crc ^ *data++) & 0xff] ^ (crc >> 8);
	return ~crc;
}

const char *tc_land_open(struct tc_land *out, const uint8_t *file, size_t bytes)
{
	if (bytes < 32 || memcmp(file, "TCL2", 4) != 0)
		return "MAGIC";
	if (read32(file + 4) != 2)
		return "VERSION";
	struct tc_land l = {
		.cells_x = read16(file + 8), .cells_z = read16(file + 10),
		.origin_x = read16(file + 12), .origin_z = read16(file + 14),
		.colours = read16(file + 24), .first = read16(file + 26),
	};
	uint32_t body = read32(file + 16);
	if (body != bytes - 32)
		return "LENGTH";
	if (tc_crc32(0, file + 32, body) != read32(file + 20))
		return "CRC";
	if (!l.cells_x || !l.cells_z || l.cells_x % BLOCK || l.cells_z % BLOCK)
		return "GRID";
	if (l.first != TC_LAND_COLOUR || l.first + l.colours > 256)
		return "PALETTE";
	size_t vertices = (size_t)(l.cells_x + 1) * (l.cells_z + 1);
	size_t cells = (size_t)l.cells_x * l.cells_z;
	if (body != 4u * l.colours + 2 * vertices + cells)
		return "SIZE";
	// to_camera holds each camera-space difference, and the products it forms
	// with a Q14 sine or cosine, in 32 bits. This is the grid limit that keeps
	// them there. The camera orbits at 0.5 of the island's extent of its
	// centre and within 0.8 of that extent of it, so a difference is at most
	// 1.3 extents; of an angle's sine and cosine, the two used together sum to
	// at most 2^14 times the square root of two, so the yaw rotation's result
	// is at most 1.841 extents; the pitch rotation adds 0.214 extents and the
	// tallest cell, height(255), to it; and each rotation sums two products,
	// so the bound is the sum of those, times 2^14. Every land shipped with
	// the game passes it with at least ten percent to spare.
	int64_t extent = (int64_t)(l.cells_x > l.cells_z ? l.cells_x : l.cells_z) * CELL;
	int64_t rz_max = extent * 18404 / 10000;
	int64_t dy_max = extent * 2140 / 10000 + 2744;
	if ((rz_max + dy_max) * 16384 >= (int64_t)1 << 31)
		return "TOO WIDE";
	l.palette = (const uint32_t *)(file + 32);
	l.altitude = file + 32 + 4 * l.colours;
	l.colour = l.altitude + vertices;
	l.cells = l.colour + vertices;
	*out = l;
	return 0;
}

static uint32_t mix(uint32_t a, uint32_t b, unsigned i, unsigned n)
{
	uint32_t out = 0;
	for (int shift = 0; shift < 24; shift += 8) {
		int32_t x = (int32_t)(a >> shift & 0xff), y = (int32_t)(b >> shift & 0xff);
		out |= (uint32_t)(x + (y - x) * (int32_t)i / (int32_t)n) << shift;
	}
	return out;
}

uint32_t tc_palette(const struct tc_land *l, unsigned index)
{
	if (index >= TC_SKY_COLOUR && index < TC_SKY_COLOUR + TC_RAMP)
		return mix(0x2a5aa8, 0xb4cce0, index - TC_SKY_COLOUR, TC_RAMP - 1);
	if (index >= TC_SEA_COLOUR && index < TC_SEA_COLOUR + TC_RAMP)
		return mix(0x6aa0b4, 0x1c4a6a, index - TC_SEA_COLOUR, TC_RAMP - 1);
	if (index >= l->first && index < l->first + l->colours)
		return read32((const uint8_t *)&l->palette[index - l->first]);
	return 0;
}

// Five bits a channel is what the game's materials carry, B5G5R5, so a colour
// reduced to them loses nothing the land ever held; the sky's and the sea's
// own ramps are this renderer's and lose a little.
static uint32_t to5(uint32_t colour)
{
	return (colour >> 19 & 31) << 10 | (colour >> 11 & 31) << 5 |
	       (colour >> 3 & 31);
}

void tc_shade_tables(const struct tc_land *l, uint16_t *pal5, uint8_t *lut)
{
	for (unsigned i = 0; i < TC_PAL5_ENTRIES; i++)
		pal5[i] = (uint16_t)to5(tc_palette(l, i));
	for (uint32_t rgb = 0; rgb < TC_LUT_BYTES; rgb++) {
		unsigned best = l->first;
		int32_t best_d = -1;
		for (unsigned i = l->first; i < l->first + l->colours; i++) {
			int32_t d = 0;
			for (int shift = 0; shift < 15; shift += 5) {
				int32_t a = (int32_t)(rgb >> shift & 31);
				int32_t b = (int32_t)(pal5[i] >> shift & 31);
				d += (a - b) * (a - b);
			}
			if (best_d < 0 || d < best_d) {
				best_d = d;
				best = i;
			}
		}
		lut[rgb] = (uint8_t)best;
	}
}

// One pixel's colour: the palette entries the three corners name, mixed with
// the weights a and b out of four of the second and third corners -- the
// first corner's being what is left -- and then the land's nearest entry to
// the result. fpga/raster.sv's fill computes this with the same numbers, a
// compare and an add at a time.
static uint8_t shade(const uint16_t *pal5, const uint8_t *lut,
		     uint32_t colours, int32_t a, int32_t b)
{
	uint32_t out = 0;
	for (int shift = 0; shift < 15; shift += 5) {
		int32_t c0 = (int32_t)(pal5[colours & 0xff] >> shift & 31);
		int32_t c1 = (int32_t)(pal5[colours >> 8 & 0xff] >> shift & 31);
		int32_t c2 = (int32_t)(pal5[colours >> 16 & 0xff] >> shift & 31);
		int32_t mix = c0 + (((c1 - c0) * a + (c2 - c0) * b + 2) >> 2);
		out |= (uint32_t)(mix & 31) << shift;
	}
	return lut[out];
}

size_t tc_work_bytes(const struct tc_land *l)
{
	size_t blocks = (size_t)(l->cells_x / BLOCK) * (l->cells_z / BLOCK);
	return (size_t)(l->cells_x + 1) * (l->cells_z + 1) * sizeof(struct vertex) +
	       3 * blocks + TC_PAL5_BYTES + TC_LUT_BYTES;
}

static int32_t height(uint32_t altitude)
{
	return (int32_t)(altitude * 2744u >> 8); // 0.67 units, Q4
}

// The angle helpers below tc_init only by placement: it seeds the camera the
// mouse will drive, and that camera is described in the same angles.
static int32_t isin(uint32_t a);
static int32_t icos(uint32_t a);

struct tc_shade tc_init(const struct tc_land *l, void *work)
{
	land = l;
	verts_x = l->cells_x + 1u;
	blocks_x = l->cells_x / BLOCK;
	blocks_z = l->cells_z / BLOCK;
	uint32_t count = verts_x * (l->cells_z + 1u);
	vertices = work;
	for (uint32_t i = 0; i < count; i++)
		vertices[i].stamp = 0;
	generation = 0;
	// Where the mouse picks the camera up when its first report arrives: the
	// scripted orbit's own frame zero, the island's centre looked at from reach
	// away at the orbit's tilt, so that a hand on the mouse moves the view from
	// where the run would have started rather than jumping it.
	cam_turn = 0x8000;
	cam_pitch = PITCH;
	cam_dist = (int32_t)((int64_t)((l->cells_x > l->cells_z ? l->cells_x : l->cells_z) *
				      CELL * 4 / 5) * 16384 / icos(PITCH));
	cam_focus_x = (int32_t)l->cells_x * CELL / 2;
	cam_focus_z = (int32_t)l->cells_z * CELL / 2;
	cam_focus_y = LIFT;
	cam_driven = 0;
	// The cursor's shape, and where it starts: the middle of the screen.
	hand_build();
	cursor_x = TC_WIDTH / 2 * 16;
	cursor_y = TC_HEIGHT / 2 * 16;
	block_low = (uint8_t *)(vertices + count);
	block_high = block_low + blocks_x * blocks_z;
	block_shown = block_high + blocks_x * blocks_z;
	// The shading tables, which every fill reads and main.c hands the fabric.
	uint16_t *pal5 = (uint16_t *)(block_shown + blocks_x * blocks_z);
	uint8_t *lut = (uint8_t *)pal5 + TC_PAL5_BYTES;
	tc_shade_tables(l, pal5, lut);
	shade_pal5 = pal5;
	shade_lut = lut;
	const struct tc_shade shade = {pal5, lut};
	for (uint32_t bz = 0; bz < blocks_z; bz++)
		for (uint32_t bx = 0; bx < blocks_x; bx++) {
			uint8_t low = 255, high = 0, any = 0;
			for (uint32_t z = bz * BLOCK; z <= (bz + 1) * BLOCK; z++)
				for (uint32_t x = bx * BLOCK; x <= (bx + 1) * BLOCK; x++) {
					uint8_t a = l->altitude[z * verts_x + x];
					low = a < low ? a : low;
					high = a > high ? a : high;
					if (z < (bz + 1) * BLOCK && x < (bx + 1) * BLOCK)
						any |= l->cells[z * l->cells_x + x] & 6;
				}
			uint32_t b = bz * blocks_x + bx;
			block_low[b] = low;
			block_high[b] = high;
			// An empty block stays culled for good.
			block_shown[b] = any ? 1 : 0xff;
		}
	return shade;
}

// sin(a), Q14, a in 1/65536 of a turn: a seventh-order odd polynomial on
// each quarter, within 2e-4 of the true value.
static int32_t isin(uint32_t a)
{
	a &= 0xffff;
	uint32_t quarter = a >> 14;
	int64_t x = a & 0x3fff;
	if (quarter & 1)
		x = 0x4000 - x;
	int64_t x2 = x * x >> 14;
	int64_t r = 77;
	r = 1306 - (x2 * r >> 14);
	r = 10584 - (x2 * r >> 14);
	r = 25736 - (x2 * r >> 14);
	int32_t s = (int32_t)(x * r >> 14);
	if (s > 16384)
		s = 16384;
	return quarter & 2 ? -s : s;
}

static int32_t icos(uint32_t a)
{
	return isin(a + 0x4000);
}

// The camera transform: rotate a world point into camera space, Q4. Every
// product and sum here is held in 32 bits, which tc_land_open's grid check is
// what makes safe -- a 64-bit product costs several instructions on the A25
// and this is on the path of every vertex.
static void to_camera(int32_t wx, int32_t wy, int32_t wz, int32_t *x,
		      int32_t *y, int32_t *z)
{
	int32_t dx = wx - cam_x, dy = wy - cam_y, dz = wz - cam_z;
	int32_t rz = (dx * sin_yaw + dz * cos_yaw) >> 14;
	*x = (dx * cos_yaw - dz * sin_yaw) >> 14;
	*y = (dy * cos_pitch + rz * sin_pitch) >> 14;
	*z = (rz * cos_pitch - dy * sin_pitch) >> 14;
}

// The screen position of a camera-space point, Q4: pixels, 16 to a pixel.
static void project_xy(int32_t x, int32_t y, int32_t z, int32_t *sx, int32_t *sy)
{
	int64_t inv = (1 << 30) / z;
	*sx = TC_WIDTH * 8 + (int32_t)(x * inv >> 18);
	*sy = TC_HEIGHT * 8 - (int32_t)(y * inv >> 18);
}

// A stored vertex's camera-space position, recomputed from the grid it
// indexes because the 8-byte record does not keep it. The arithmetic is the
// one vertex() used, so the result is the value it would have stored.
static void vertex_camera(const struct vertex *v, int32_t *x, int32_t *y, int32_t *z)
{
	size_t i = (size_t)(v - vertices);
	uint32_t gz = (uint32_t)(i / verts_x), gx = (uint32_t)(i % verts_x);
	to_camera((int32_t)gx * CELL, height(land->altitude[gz * verts_x + gx]),
		  (int32_t)gz * CELL, x, y, z);
}

static struct vertex *vertex(uint32_t gx, uint32_t gz)
{
	struct vertex *v = &vertices[gz * verts_x + gx];
	if ((v->stamp >> 2) != generation) {
		int32_t x, y, z, sx = 0, sy = 0;
		uint32_t state = VERT_BEHIND;
		to_camera((int32_t)gx * CELL, height(land->altitude[gz * verts_x + gx]),
			  (int32_t)gz * CELL, &x, &y, &z);
		if (z >= NEAR) {
			project_xy(x, y, z, &sx, &sy);
			state = VERT_FRONT;
			if (sx > 32767 || sx < -32768 || sy > 32767 || sy < -32768) {
				// Held clamped and flagged; submit() recomputes it.
				state = VERT_WIDE;
				sx = sx > 32767 ? 32767 : sx < -32768 ? -32768 : sx;
				sy = sy > 32767 ? 32767 : sy < -32768 ? -32768 : sy;
			}
		}
		v->sx = (int16_t)sx;
		v->sy = (int16_t)sy;
		v->stamp = generation << 2 | state;
	}
	return v;
}

void tc_soft_rows(void *ctx, uint32_t first, uint32_t end, uint8_t colour)
{
	struct tc_soft *soft = ctx;
	for (uint32_t r = first; r < end && r < TC_HEIGHT; r++)
		memset(soft->fb + r * soft->stride, colour, TC_WIDTH);
}

// fpga/raster.sv's rule: pixel (i, j) of the screen is filled when, at its
// centre (16 i + 8, 16 j + 8), F = (by - ay)(px - ax) - (bx - ax)(py - ay)
// is >= 0 for each edge a to b; only the bounding box of the corners'
// pixel centres, clamped to the screen, is visited. A filled pixel's colour
// is shade()'s, and S = F0 + F1 + F2 is the same at every pixel of a
// triangle, being the sum of three affine functions whose slopes cancel.
// The weight of the first corner is F1 / S, of the second F2 / S and of the
// third F0 / S, each edge function measuring the far corner from its edge.
void tc_soft_triangle(void *ctx, const int32_t *x, const int32_t *y,
		      uint32_t colours)
{
	struct tc_soft *soft = ctx;
	soft->triangles++;
	int32_t x_lo = x[0], x_hi = x[0], y_lo = y[0], y_hi = y[0];
	for (int k = 1; k < 3; k++) {
		x_lo = x[k] < x_lo ? x[k] : x_lo;
		x_hi = x[k] > x_hi ? x[k] : x_hi;
		y_lo = y[k] < y_lo ? y[k] : y_lo;
		y_hi = y[k] > y_hi ? y[k] : y_hi;
	}
	int32_t i0 = (x_lo + 7) >> 4, i1 = (x_hi - 8) >> 4;
	int32_t j0 = (y_lo + 7) >> 4, j1 = (y_hi - 8) >> 4;
	i0 = i0 < 0 ? 0 : i0;
	j0 = j0 < 0 ? 0 : j0;
	i1 = i1 > TC_WIDTH - 1 ? TC_WIDTH - 1 : i1;
	j1 = j1 > TC_HEIGHT - 1 ? TC_HEIGHT - 1 : j1;
	if (i0 > i1 || j0 > j1)
		return;
	int64_t row[3], step_x[3], step_y[3];
	for (int k = 0; k < 3; k++) {
		int32_t dx = x[(k + 1) % 3] - x[k], dy = y[(k + 1) % 3] - y[k];
		row[k] = (int64_t)dy * (16 * i0 + 8 - x[k]) -
			 (int64_t)dx * (16 * j0 + 8 - y[k]);
		step_x[k] = (int64_t)dy * 16;
		step_y[k] = -(int64_t)dx * 16;
	}
	int64_t s = row[0] + row[1] + row[2];
	int64_t s2 = s << 1, s3 = s + s2;
	for (int32_t j = j0; j <= j1; j++) {
		uint8_t *line = soft->fb + (uint32_t)j * soft->stride;
		int64_t e0 = row[0], e1 = row[1], e2 = row[2];
		for (int32_t i = i0; i <= i1; i++) {
			if ((e0 | e1 | e2) >= 0) {
				int64_t f0 = e0 << 2, f2 = e2 << 2;
				/* A triangle of no area has F all zero, so all
				 * three thresholds pass; its one corner colours
				 * it instead. Inside a real one, F0 + F1 <= S, so
				 * no more than four quarters are ever asked for.*/
				int32_t a = 0, b = 0;
				if (s > 0) {
					a = (f2 >= s) + (f2 >= s2) + (f2 >= s3);
					b = (f0 >= s) + (f0 >= s2) + (f0 >= s3);
				}
				line[i] = shade(soft->pal5, soft->lut, colours, a, b);
				soft->pixels++;
			}
			e0 += step_x[0];
			e1 += step_x[1];
			e2 += step_x[2];
		}
		for (int k = 0; k < 3; k++)
			row[k] += step_y[k];
	}
}

// Clip a convex polygon of n Q4 screen points, in place, to within GUARD of
// the origin on both axes; returns the points left.
static int clip_guard(int32_t *x, int32_t *y, int32_t *wa, int32_t *wb, int n)
{
	for (int side = 0; side < 4 && n; side++) {
		int32_t cx[9], cy[9], ca[9], cb[9];
		int m = 0;
		int32_t sign = side & 2 ? -1 : 1;
		for (int i = 0; i < n; i++) {
			int j = (i + 1) % n;
			// v is the coordinate this side bounds, signed so in is <= GUARD.
			int64_t vp = sign * (int64_t)(side & 1 ? y[i] : x[i]);
			int64_t vq = sign * (int64_t)(side & 1 ? y[j] : x[j]);
			if (vp <= GUARD) {
				cx[m] = x[i];
				cy[m] = y[i];
				ca[m] = wa[i];
				cb[m++] = wb[i];
			}
			if ((vp <= GUARD) != (vq <= GUARD)) {
				int64_t num = GUARD - vp, den = vq - vp;
				cx[m] = x[i] + (int32_t)((int64_t)(x[j] - x[i]) * num / den);
				cy[m] = y[i] + (int32_t)((int64_t)(y[j] - y[i]) * num / den);
				// A cut vertex's colour is the two it cuts mixed at
				// the same fraction, in the quarters the fill uses.
				ca[m] = (int32_t)(((int64_t)wa[i] * (den - num) +
						   (int64_t)wa[j] * num + den / 2) / den);
				cb[m] = (int32_t)(((int64_t)wb[i] * (den - num) +
						   (int64_t)wb[j] * num + den / 2) / den);
				if (side & 1)
					cy[m] = sign * GUARD;
				else
					cx[m] = sign * GUARD;
				m++;
			}
		}
		n = m;
		memcpy(x, cx, sizeof(int32_t) * (size_t)m);
		memcpy(y, cy, sizeof(int32_t) * (size_t)m);
		memcpy(wa, ca, sizeof(int32_t) * (size_t)m);
		memcpy(wb, cb, sizeof(int32_t) * (size_t)m);
	}
	return n;
}

// One triangle facing up, its corners counter-clockwise seen from above:
// send it if it faces the camera and reaches the screen. Front faces wind
// clockwise on the screen (y down), which is the order that makes the
// rasterizer's edge functions >= 0 inside.
static void emit(const int32_t *x, const int32_t *y, uint32_t colours)
{
	int64_t cross = (int64_t)(x[1] - x[0]) * (y[2] - y[0]) -
			(int64_t)(y[1] - y[0]) * (x[2] - x[0]);
	if (cross >= 0)
		return;
	int32_t x_lo = x[0], x_hi = x[0], y_lo = y[0], y_hi = y[0];
	for (int i = 1; i < 3; i++) {
		x_lo = x[i] < x_lo ? x[i] : x_lo;
		x_hi = x[i] > x_hi ? x[i] : x_hi;
		y_lo = y[i] < y_lo ? y[i] : y_lo;
		y_hi = y[i] > y_hi ? y[i] : y_hi;
	}
	// No pixel centre on the screen in its box: the rasterizer would fill
	// nothing, so it is not sent.
	if (((x_lo + 7) >> 4) > ((x_hi - 8) >> 4) || x_hi < 8 ||
	    x_lo + 7 >= TC_WIDTH * 16 || ((y_lo + 7) >> 4) > ((y_hi - 8) >> 4) ||
	    y_hi < 8 || y_lo + 7 >= TC_HEIGHT * 16)
		return;
	out->triangle(out->ctx, x, y, colours);
	counts->triangles++;
}

// The slow side of submit(): a corner whose screen position the 8-byte
// record could not hold exactly, or one that reached past the guard band.
// Recomputes camera space from the grid where it is needed, clips at the
// near plane, and fans the result.
static void submit_slow(const struct vertex *a, const struct vertex *b,
			const struct vertex *c, uint32_t colours)
{
	const struct vertex *in[3] = {a, b, c};
	uint32_t state[3];
	int32_t x[3] = {0, 0, 0}, y[3] = {0, 0, 0}, z[3] = {0, 0, 0};
	int32_t sx[3] = {0, 0, 0}, sy[3] = {0, 0, 0};
	// The first corner's colour is what is left after the other two, so a
	// polygon vertex needs only their two weights, in quarters.
	int32_t wa[3] = {0, 4, 0}, wb[3] = {0, 0, 4};
	int behind = 0;
	for (int i = 0; i < 3; i++) {
		state[i] = in[i]->stamp & 3u;
		if (state[i] == VERT_FRONT) {
			sx[i] = in[i]->sx;
			sy[i] = in[i]->sy;
			continue;
		}
		vertex_camera(in[i], &x[i], &y[i], &z[i]);
		if (state[i] == VERT_BEHIND)
			behind++;
		else
			project_xy(x[i], y[i], z[i], &sx[i], &sy[i]);
	}
	if (behind == 3)
		return;
	if (behind) {
		// Clipping interpolates along the edges, so every corner needs its
		// camera-space position, including the ones the record held exactly.
		for (int i = 0; i < 3; i++)
			if (state[i] == VERT_FRONT)
				vertex_camera(in[i], &x[i], &y[i], &z[i]);
	}
	int32_t px[9], py[9], pa[9], pb[9];
	int n = 0;
	if (!behind) {
		for (int i = 0; i < 3; i++) {
			px[n] = sx[i];
			py[n] = sy[i];
			pa[n] = wa[i];
			pb[n++] = wb[i];
		}
	} else {
		for (int i = 0; i < 3; i++) {
			int j = (i + 1) % 3;
			if (z[i] >= NEAR) {
				px[n] = sx[i];
				py[n] = sy[i];
				pa[n] = wa[i];
				pb[n++] = wb[i];
			}
			if ((z[i] >= NEAR) != (z[j] >= NEAR)) {
				int64_t num = NEAR - z[i], den = z[j] - z[i];
				int32_t cx = x[i] + (int32_t)((x[j] - x[i]) * num / den);
				int32_t cy = y[i] + (int32_t)((y[j] - y[i]) * num / den);
				int32_t qx, qy;
				project_xy(cx, cy, NEAR, &qx, &qy);
				px[n] = qx;
				py[n] = qy;
				pa[n] = (int32_t)(((int64_t)wa[i] * (den - num) +
						   (int64_t)wa[j] * num + den / 2) / den);
				pb[n] = (int32_t)(((int64_t)wb[i] * (den - num) +
						   (int64_t)wb[j] * num + den / 2) / den);
				n++;
			}
		}
	}
	for (int i = 0; i < n; i++)
		if (px[i] < -GUARD || px[i] > GUARD || py[i] < -GUARD || py[i] > GUARD) {
			n = clip_guard(px, py, pa, pb, n);
			break;
		}
	for (int k = 1; k + 1 < n; k++) {
		int32_t tx[3] = {px[0], px[k], px[k + 1]};
		int32_t ty[3] = {py[0], py[k], py[k + 1]};
		uint32_t corner[3];
		const int32_t at[3] = {0, k, k + 1};
		for (int i = 0; i < 3; i++)
			corner[i] = shade(shade_pal5, shade_lut, colours,
					  pa[at[i]], pb[at[i]]);
		emit(tx, ty, corner[0] | corner[1] << 8 | corner[2] << 16);
	}
}

// Draw one triangle facing up. The walk's everyday case -- every corner in
// front of the near plane with an exact screen position inside the guard
// band, which is every triangle of the orbit the board draws -- is taken
// straight from the record, with none of the clip machinery's stack; a
// corner beyond the guard band falls through to submit_slow().
static void submit(const struct vertex *a, const struct vertex *b,
		   const struct vertex *c, uint32_t colours)
{
	if (!(a->stamp & 3u) && !(b->stamp & 3u) && !(c->stamp & 3u)) {
		int32_t x[3] = {a->sx, b->sx, c->sx};
		int32_t y[3] = {a->sy, b->sy, c->sy};
		int i;
		for (i = 0; i < 3; i++)
			if (x[i] < -GUARD || x[i] > GUARD || y[i] < -GUARD || y[i] > GUARD)
				break;
		if (i == 3) {
			emit(x, y, colours);
			return;
		}
	}
	submit_slow(a, b, c, colours);
}

static int outside(int32_t x, int32_t y, int32_t z)
{
	int64_t z5 = (int64_t)z * 5, z45 = (int64_t)z * 45;
	return (z < NEAR) | ((int64_t)x * 8 < -z5) << 1 | ((int64_t)x * 8 > z5) << 2 |
	       ((int64_t)y * 128 > z45) << 3 | ((int64_t)y * 128 < -z45) << 4;
}

static void cull_blocks(void)
{
	for (uint32_t bz = 0; bz < blocks_z; bz++)
		for (uint32_t bx = 0; bx < blocks_x; bx++) {
			uint32_t b = bz * blocks_x + bx;
			if (block_shown[b] == 0xff)
				continue;
			int all = 0x1f;
			for (int k = 0; k < 8 && all; k++) {
				int32_t x, y, z;
				to_camera((int32_t)(bx + (k & 1)) * BLOCK * CELL,
					  height(k & 2 ? block_high[b] : block_low[b]),
					  (int32_t)(bz + (k >> 2 & 1)) * BLOCK * CELL,
					  &x, &y, &z);
				all &= outside(x, y, z);
			}
			block_shown[b] = all ? 0 : 1;
		}
}

static int32_t floor_div(int32_t a, int32_t b)
{
	return a >= 0 ? a / b : -((-a + b - 1) / b);
}

static void draw_cell(uint32_t gx, uint32_t gz)
{
	const uint8_t *cell = &land->cells[gz * land->cells_x + gx];
	uint8_t flags = cell[0];
	if (!(flags & 6))
		return;
	struct vertex *tl = vertex(gx, gz), *tr = vertex(gx + 1, gz);
	struct vertex *bl = vertex(gx, gz + 1), *br = vertex(gx + 1, gz + 1);
	// Each corner carries its own colour, and they are handed over in the
	// order the corners are, which is the order the fill shades between.
	uint32_t ctl = land->colour[gz * verts_x + gx];
	uint32_t ctr = land->colour[gz * verts_x + gx + 1];
	uint32_t cbl = land->colour[(gz + 1) * verts_x + gx];
	uint32_t cbr = land->colour[(gz + 1) * verts_x + gx + 1];
	int32_t px = cam_x - (int32_t)gx * CELL, pz = cam_z - (int32_t)gz * CELL;
	const struct vertex *t[2][3];
	uint32_t c[2][3];
	int far;
	if (flags & 1) {
		t[0][0] = bl, t[0][1] = tl, t[0][2] = tr;
		t[1][0] = bl, t[1][1] = tr, t[1][2] = br;
		c[0][0] = cbl, c[0][1] = ctl, c[0][2] = ctr;
		c[1][0] = cbl, c[1][1] = ctr, c[1][2] = cbr;
		far = px + pz > CELL ? 0 : 1;
	} else {
		t[0][0] = tl, t[0][1] = tr, t[0][2] = br;
		t[1][0] = tl, t[1][1] = br, t[1][2] = bl;
		c[0][0] = ctl, c[0][1] = ctr, c[0][2] = cbr;
		c[1][0] = ctl, c[1][1] = cbr, c[1][2] = cbl;
		far = px < pz ? 0 : 1;
	}
	for (int k = 0; k < 2; k++) {
		int i = k ? 1 - far : far;
		if (flags & (2 << i))
			submit(t[i][0], t[i][1], t[i][2],
			       c[i][0] | c[i][1] << 8 | c[i][2] << 16);
	}
}

// The next of lo..hi, whichever is farther from c, toward c.
static uint32_t farther(int32_t *lo, int32_t *hi, int32_t c)
{
	int32_t a = c - *lo, b = *hi - c;
	if ((a < 0 ? -a : a) >= (b < 0 ? -b : b))
		return (uint32_t)(*lo)++;
	return (uint32_t)(*hi)--;
}

// The land's height under a world position, Q4, clamped to the island: the
// camera's focus follows the ground it is dragged over.
static int32_t ground(int32_t x, int32_t z)
{
	int32_t gx = x / CELL, gz = z / CELL;
	if (gx < 0)
		gx = 0;
	if (gz < 0)
		gz = 0;
	if (gx > (int32_t)land->cells_x)
		gx = (int32_t)land->cells_x;
	if (gz > (int32_t)land->cells_z)
		gz = (int32_t)land->cells_z;
	return height(land->altitude[(uint32_t)gz * verts_x + (uint32_t)gx]);
}

void tc_mouse(uint8_t buttons, int32_t dx, int32_t dy, int32_t wheel)
{
	/* The camera the scripted orbit left in the same variables, so that the
	 * first report takes the view up where it is rather than jumping it. */
	if (!cam_driven)
		cam_driven = 1;

	/* The cursor follows the hand whatever the buttons are doing, so that a
	 * drag keeps hold of the piece of land it took. */
	cursor_x += dx * 16;
	cursor_y += dy * 16;
	if (cursor_x < 0)
		cursor_x = 0;
	if (cursor_y < 0)
		cursor_y = 0;
	if (cursor_x > (TC_WIDTH - 1) * 16)
		cursor_x = (TC_WIDTH - 1) * 16;
	if (cursor_y > (TC_HEIGHT - 1) * 16)
		cursor_y = (TC_HEIGHT - 1) * 16;

	if (buttons & TC_MOUSE_MIDDLE) {
		/* Turning: the angle moves with the drag and the tilt against it,
		 * which is what makes dragging down look further down. */
		cam_turn += dx * TC_TURN_PER_COUNT;
		cam_pitch -= dy * TC_PITCH_PER_COUNT;
		if (cam_pitch < 4096)
			cam_pitch = 4096;      /* about nine degrees: never flat */
		if (cam_pitch > 0x3800)
			cam_pitch = 0x3800;    /* about seventy-nine: never straight down */
	} else if (buttons & TC_MOUSE_LEFT) {
		/* The land follows the hand: a count covers this much of it at
		 * this distance, and the focus moves against the drag. Pulling the
		 * land down moves the focus forward, which takes more world for
		 * the same count because the ground is seen at a tilt. */
		int32_t per = cam_dist / TC_DRAG_DIVISOR;
		int32_t ax = -(per * dx);
		int32_t az = (int32_t)((int64_t)per * dy * 16384 / cos_pitch);
		cam_focus_x += (int32_t)(((int64_t)ax * cos_yaw +
					  (int64_t)az * sin_yaw) >> 14);
		cam_focus_z += (int32_t)((-(int64_t)ax * sin_yaw +
					  (int64_t)az * cos_yaw) >> 14);
		if (cam_focus_x < 0)
			cam_focus_x = 0;
		if (cam_focus_z < 0)
			cam_focus_z = 0;
		if (cam_focus_x > (int32_t)land->cells_x * CELL)
			cam_focus_x = (int32_t)land->cells_x * CELL;
		if (cam_focus_z > (int32_t)land->cells_z * CELL)
			cam_focus_z = (int32_t)land->cells_z * CELL;
		cam_focus_y = ground(cam_focus_x, cam_focus_z);
	}

	if (wheel) {
		/* Rolling towards the hand comes closer: the wheel is inverted from
		 * the usual direction, as this user wants it. */
		cam_dist += wheel * TC_ZOOM_PER_COUNT;
		if (cam_dist < 320)
			cam_dist = 320;              /* twenty units: in the grass */
		if (cam_dist > (int32_t)((land->cells_x > land->cells_z ?
					  land->cells_x : land->cells_z) * CELL * 2))
			cam_dist = (int32_t)((land->cells_x > land->cells_z ?
					      land->cells_x : land->cells_z) * CELL * 2);
	}
}

// One run of the cursor as the two triangles a rectangle needs, wound the way
// the rasterizer's edge functions want: the interior has to lie to the left of
// each directed edge, which on a screen whose y runs downwards is down the
// left side, along the bottom, and back along the diagonal.
static void hand_rect(int32_t x0, int32_t y0, int32_t x1, int32_t y1,
		      uint8_t colour)
{
	int32_t x[3], y[3];
	uint32_t colours = colour * 0x010101u;

	x[0] = x0; y[0] = y0;
	x[1] = x0; y[1] = y1;
	x[2] = x1; y[2] = y1;
	out->triangle(out->ctx, x, y, colours);
	counts->triangles++;
	x[0] = x0; y[0] = y0;
	x[1] = x1; y[1] = y1;
	x[2] = x1; y[2] = y0;
	out->triangle(out->ctx, x, y, colours);
	counts->triangles++;
}

void tc_draw(const struct tc_target *target, uint32_t frame, uint32_t frames,
	     struct tc_stats *stats)
{
	out = target;
	counts = stats;
	stats->triangles = 0;
	generation++;

	// One orbit, swinging in to 40% and back out twice on the way round.
	int32_t size = (land->cells_x > land->cells_z ? land->cells_x : land->cells_z) * CELL;
	int32_t reach = size * 4 / 5;
	if (!cam_driven) {
		uint32_t turn = (uint32_t)((uint64_t)frame * 65536 / frames);
		int32_t radius = (int32_t)(reach * (7 * 16384 + 3 * (int64_t)icos(2 * turn)) / (10 * 16384));
		cam_x = land->cells_x * CELL / 2 + (int32_t)((int64_t)radius * isin(turn) >> 14);
		cam_z = land->cells_z * CELL / 2 + (int32_t)((int64_t)radius * icos(turn) >> 14);
		cam_y = (int32_t)((int64_t)radius * TAN_PITCH >> 14) + LIFT;
		sin_yaw = isin(turn + 0x8000);
		cos_yaw = icos(turn + 0x8000);
		sin_pitch = isin(PITCH);
		cos_pitch = icos(PITCH);
		// The same camera written as the focus, angle, tilt and distance the
		// mouse drives, so its first report can take it over in place.
		cam_turn = (int32_t)(turn + 0x8000);
		cam_pitch = PITCH;
		cam_dist = (int32_t)((int64_t)radius * 16384 / cos_pitch);
		cam_focus_x = cam_x + (int32_t)((int64_t)radius * sin_yaw >> 14);
		cam_focus_z = cam_z + (int32_t)((int64_t)radius * cos_yaw >> 14);
		cam_focus_y = cam_y - (int32_t)((int64_t)radius * TAN_PITCH >> 14);
	} else {
		sin_yaw = isin((uint32_t)cam_turn);
		cos_yaw = icos((uint32_t)cam_turn);
		sin_pitch = isin((uint32_t)cam_pitch);
		cos_pitch = icos((uint32_t)cam_pitch);
		int32_t horiz = (int32_t)((int64_t)cam_dist * cos_pitch >> 14);
		cam_x = cam_focus_x - (int32_t)((int64_t)horiz * sin_yaw >> 14);
		cam_z = cam_focus_z - (int32_t)((int64_t)horiz * cos_yaw >> 14);
		cam_y = cam_focus_y + (int32_t)((int64_t)cam_dist * sin_pitch >> 14);
		// The camera stays clear of the ground it is looking at, which is what
		// keeps a drag over a hill from burying it (core-reference OB-005).
		int32_t clearance = ground(cam_x, cam_z) + 160;
		if (cam_y < clearance)
			cam_y = clearance;
	}

	// The sky above the horizon, the sea below it, a run of rows at a time.
	int32_t horizon = TC_HEIGHT / 2 - FOCAL * sin_pitch / cos_pitch;
	uint32_t run = 0, run_colour = 0;
	for (int32_t r = 0; r <= TC_HEIGHT; r++) {
		uint32_t c = 0;
		if (r == TC_HEIGHT)
			c = 0x100;
		else if (r < horizon)
			c = TC_SKY_COLOUR + (uint32_t)(r * TC_RAMP / horizon);
		else
			c = TC_SEA_COLOUR +
			    (uint32_t)((r - horizon) * TC_RAMP / (TC_HEIGHT - horizon));
		if (r && c != run_colour) {
			target->rows(target->ctx, run, (uint32_t)r, (uint8_t)run_colour);
			run = (uint32_t)r;
		}
		run_colour = c;
	}

	cull_blocks();
	int32_t cx = floor_div(cam_x, CELL), cz = floor_div(cam_z, CELL);
	int32_t z_lo = 0, z_hi = land->cells_z - 1;
	while (z_lo <= z_hi) {
		uint32_t gz = farther(&z_lo, &z_hi, cz);
		int32_t x_lo = 0, x_hi = land->cells_x - 1;
		while (x_lo <= x_hi) {
			uint32_t gx = farther(&x_lo, &x_hi, cx);
			if (block_shown[gz / BLOCK * blocks_x + gx / BLOCK] == 1)
				draw_cell(gx, gz);
		}
	}

	// The cursor goes last, so that it lies over the land it is holding.
	if (cam_driven)
		for (uint32_t i = 0; i < hand_runs_used; i++) {
			const struct hand_run *run = &hand_runs[i];
			int32_t x0 = cursor_x + run->x * 16;
			int32_t y0 = cursor_y + run->y * 16;
			hand_rect(x0, y0, x0 + run->length * 16, y0 + 16,
				  run->colour);
		}
}
