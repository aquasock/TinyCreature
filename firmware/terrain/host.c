// SPDX-License-Identifier: GPL-3.0-or-later
//
// The terrain renderer on this PC: draws the same frames as the AE350
// program from the same TCL2 file through tc_soft, the fabric
// rasterizer's model, and prints the same totals and frame CRC, so a board
// run can be compared with it. For each chosen frame it writes
// <prefix><frame>.png, <prefix><frame>.cmd, the rasterizer command words
// the frame sends, one hex word a line, and <prefix><frame>.fb, the frame
// it must produce, one hex byte a line, for tests/raster_tb.sv.
//
//   terrain_host <land.tcl> [frames] [prefix frame...]
//
// TC_INPUT names a file of mouse reports, six bytes each: the frame it
// belongs to, the buttons, and the mouse's dx, dy and wheel.
//
// prints
//   HOST TERRAIN LAND=<crc> FRAMES=<n> TRIS=<mean> PIXELS=<mean> INPUT=<n>
//     CRC=<crc> CAMFOCUS=<x>,<z> CAMEYE=<x>,<z> CAMTURN=<degrees>
//     PIN=<x>,<z>|none
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "terrain.h"

static uint8_t frame[TC_HEIGHT][TC_WIDTH];
static uint32_t depth[TC_HEIGHT * TC_WIDTH];
static FILE *commands;

// tc_soft, which also writes each command as fpga/raster.sv takes it.
static void rows(void *ctx, uint32_t first, uint32_t end, uint8_t colour)
{
	if (commands)
		fprintf(commands, "%08x\n", 2u << 28 | end << 16 | first << 8 | colour);
	tc_soft_rows(ctx, first, end, colour);
}

static void triangle(void *ctx, const int32_t *x, const int32_t *y, uint32_t colours)
{
	if (commands) {
		fprintf(commands, "%08x\n", 1u << 28 | colours);
		for (int k = 0; k < 3; k++)
			fprintf(commands, "%08x\n",
				(uint32_t)(uint16_t)y[k] << 16 | (uint16_t)x[k]);
	}
	tc_soft_triangle(ctx, x, y, colours);
}

// A card's five words as fpga/raster.sv takes them, then the twin's own fill:
// both come from the fields the caller worked out, so the file the testbench
// replays and the pixels it is compared against cannot disagree about a card.
static void card(void *ctx, const struct tc_card *c)
{
	if (commands) {
		fprintf(commands, "%08x\n", 3u << 28 | c->tile << 16);
		fprintf(commands, "%08x\n", c->j0 << 16 | c->i0);
		fprintf(commands, "%08x\n", c->j1 << 16 | c->i1);
		fprintf(commands, "%08x\n", c->dv << 16 | c->du);
		fprintf(commands, "%08x\n", c->v0 << 16 | c->u0);
	}
	tc_soft_card(ctx, c);
}

// A textured triangle's words, in the shape fpga/raster.sv will take them when
// it gains the command: the opcode and the tile, the three Q4 screen corners,
// then the nine plane numbers the fill steps. The twin's own fill follows from
// the same fields, so the file the testbench replays and the pixels it is
// compared against cannot disagree about a triangle. The exact packing is the
// fabric cycle's business; what matters here is that both renderers take the
// numbers the caller worked out.
static void tex(void *ctx, const struct tc_tex *t)
{
	if (commands) {
		fprintf(commands, "%08x\n", 4u << 28 | t->tile << 16);
		for (int k = 0; k < 3; k++)
			fprintf(commands, "%08x\n",
				(uint32_t)(uint16_t)t->y[k] << 16 |
					(uint32_t)(uint16_t)t->x[k]);
		const int32_t n[9] = { t->u0, t->ux, t->uy, t->v0, t->vx,
				       t->vy, t->r0, t->rx, t->ry };
		for (int k = 0; k < 9; k++)
			fprintf(commands, "%08x\n", (uint32_t)n[k]);
	}
	tc_soft_tex(ctx, t);
}

// The vertex store's commands, word for word as main.c sends them, then the
// twin's own store and fill, so the testbench replays what the board would.
static void vertex(void *ctx, const struct tc_vertex *v)
{
	if (commands) {
		if (!v->textured) {
			fprintf(commands, "%08x\n", 5u << 28 | v->slot << 18 | v->colour);
			fprintf(commands, "%08x\n",
				(uint32_t)(uint16_t)v->y << 16 | (uint16_t)v->x);
			fprintf(commands, "%08x\n", v->depth);
		} else {
			fprintf(commands, "%08x\n",
				6u << 28 | v->slot << 18 | v->tile << 12 | v->v << 2);
			fprintf(commands, "%08x\n",
				(uint32_t)(uint16_t)v->y << 16 | (uint16_t)v->x);
			fprintf(commands, "%08x\n", v->u << 22 | (uint32_t)v->z);
		}
	}
	tc_soft_vertex(ctx, v);
}

static void tri(void *ctx, uint32_t a, uint32_t b, uint32_t c, int textured)
{
	if (commands)
		fprintf(commands, "%08x\n",
			(textured ? 2u : 3u) << 30 | a << 20 | b << 10 | c);
	tc_soft_tri(ctx, a, b, c, textured);
}

// What the fabric needs before its first triangle: the palette in the five
// bits a channel the shading works in, and the table from a colour those
// channels make back to a land entry. $readmemh reads both in this form.
static int write_tables(const char *prefix, const struct tc_shade *shade)
{
	char path[4096];
	snprintf(path, sizeof path, "%spal.hex", prefix);
	FILE *f = fopen(path, "w");
	if (!f)
		return -1;
	for (unsigned i = 0; i < TC_PAL5_ENTRIES; i++)
		fprintf(f, "%04x\n", shade->pal5[i]);
	fclose(f);
	snprintf(path, sizeof path, "%stiles.hex", prefix);
	f = fopen(path, "w");
	if (!f)
		return -1;
	const uint8_t *art = tc_art_tiles();
	unsigned bytes = tc_art_tile_count() * 1024;
	for (unsigned i = 0; i < bytes; i++)
		fprintf(f, "%02x\n", art[i]);
	fclose(f);
	snprintf(path, sizeof path, "%slut.hex", prefix);
	f = fopen(path, "w");
	if (!f)
		return -1;
	for (unsigned i = 0; i < TC_LUT_BYTES; i++)
		fprintf(f, "%02x\n", shade->lut[i]);
	return fclose(f);
}

static void put32(FILE *f, uint32_t v)
{
	uint8_t b[4] = {(uint8_t)(v >> 24), (uint8_t)(v >> 16), (uint8_t)(v >> 8), (uint8_t)v};
	fwrite(b, 1, 4, f);
}

static void chunk(FILE *f, const char *type, const uint8_t *data, uint32_t n)
{
	put32(f, n);
	fwrite(type, 1, 4, f);
	if (n)
		fwrite(data, 1, n, f);
	put32(f, tc_crc32(tc_crc32(0, (const uint8_t *)type, 4), data, n));
}

// An indexed PNG at 2x, its image data in stored (uncompressed) blocks.
static int write_png(const char *path, const struct tc_land *land)
{
	enum { S = 2, W = TC_WIDTH * S, H = TC_HEIGHT * S, ROW = W + 1 };
	static uint8_t raw[ROW * H], z[ROW * H + ROW * H / 65535 * 5 + 64];
	for (int y = 0; y < H; y++) {
		raw[y * ROW] = 0;
		for (int x = 0; x < W; x++)
			raw[y * ROW + 1 + x] = frame[y / S][x / S];
	}
	uint32_t n = 0, a = 1, b = 0;
	z[n++] = 0x78;
	z[n++] = 0x01;
	for (uint32_t at = 0; at < sizeof raw;) {
		uint32_t len = sizeof raw - at > 65535 ? 65535 : (uint32_t)(sizeof raw - at);
		z[n++] = at + len == sizeof raw;
		z[n++] = (uint8_t)len;
		z[n++] = (uint8_t)(len >> 8);
		z[n++] = (uint8_t)~len;
		z[n++] = (uint8_t)(~len >> 8);
		memcpy(z + n, raw + at, len);
		n += len;
		at += len;
	}
	for (uint32_t i = 0; i < sizeof raw; i++) {
		a = (a + raw[i]) % 65521;
		b = (b + a) % 65521;
	}
	z[n++] = (uint8_t)(b >> 8);
	z[n++] = (uint8_t)b;
	z[n++] = (uint8_t)(a >> 8);
	z[n++] = (uint8_t)a;

	FILE *f = fopen(path, "wb");
	if (!f)
		return -1;
	fwrite("\x89PNG\r\n\x1a\n", 1, 8, f);
	uint8_t ihdr[13] = {0, 0, W >> 8, W & 0xff, 0, 0, H >> 8, H & 0xff, 8, 3, 0, 0, 0};
	chunk(f, "IHDR", ihdr, sizeof ihdr);
	uint8_t plte[768];
	for (unsigned i = 0; i < 256; i++) {
		uint32_t c = tc_palette(land, i);
		plte[3 * i] = (uint8_t)(c >> 16);
		plte[3 * i + 1] = (uint8_t)(c >> 8);
		plte[3 * i + 2] = (uint8_t)c;
	}
	chunk(f, "PLTE", plte, sizeof plte);
	chunk(f, "IDAT", z, n);
	chunk(f, "IEND", NULL, 0);
	return fclose(f);
}

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: %s <land.tcl> [frames] [png-prefix frame...]\n", argv[0]);
		return 2;
	}
	FILE *f = fopen(argv[1], "rb");
	if (!f) {
		perror(argv[1]);
		return 1;
	}
	static uint8_t file[4 << 20];
	size_t bytes = fread(file, 1, sizeof file, f);
	fclose(f);
	struct tc_land land;
	const char *why = tc_land_open(&land, file, bytes);
	if (why) {
		fprintf(stderr, "%s: bad land file: %s\n", argv[1], why);
		return 1;
	}
	uint32_t frames = argc > 2 ? (uint32_t)strtoul(argv[2], NULL, 0) : 600;
	void *work = malloc(tc_work_bytes(&land));
	if (!work || !frames)
		return 1;
	struct tc_shade shade = tc_init(&land, work);

	// A recorded input sequence, one report a frame and six bytes each: the
	// frame it belongs to, the buttons, and the mouse's dx, dy and wheel,
	// which is what the board is given in the land file it asks for. The two
	// draw the same frames however the link was paced.
	static int32_t in_dx[4096], in_dy[4096], in_wheel[4096];
	static uint8_t in_buttons[4096];
	/* A frame is handed to the mouse when a report named it, not when that
	 * report carried something: the buttons are a level and the movement a
	 * delta, so the report that lets a button go carries neither, and asking
	 * what a report contained drops it and leaves the cursor wearing the
	 * sprite of the button that was let go. */
	static uint8_t in_seen[4096];
	uint32_t applied = 0;
	const char *input_path = getenv("TC_INPUT");
	if (input_path && !*input_path)
		input_path = NULL;   /* set but empty means no input */
	if (input_path) {
		FILE *in = fopen(input_path, "rb");
		if (!in) {
			perror(input_path);
			return 1;
		}
		uint8_t record[6];
		while (fread(record, 1, sizeof record, in) == sizeof record) {
			uint32_t at = (uint32_t)record[0] |
				      (uint32_t)record[1] << 8;
			if (at < 4096) {
				in_buttons[at] = record[2];
				in_dx[at] += (int8_t)record[3];
				in_dy[at] += (int8_t)record[4];
				in_wheel[at] += (int8_t)record[5];
				in_seen[at] = 1;
			}
		}
		fclose(in);
	}

	uint32_t crc = 0;
	uint64_t tris = 0, pixels = 0;
	struct tc_soft soft = {.fb = &frame[0][0], .stride = TC_WIDTH,
			       .pal5 = shade.pal5, .lut = shade.lut, .zbuf = depth};
	/* TC_NO_STORE leaves the vertex store out, which sends every triangle
	 * whole as before it existed: the same frames, by a different stream. */
	const char *no_store = getenv("TC_NO_STORE");
	const int store = !(no_store && *no_store && *no_store != '0');
	const struct tc_target target = {.rows = rows, .triangle = triangle,
					.ctx = &soft, .card = card, .tex = tex,
					.vertex = store ? vertex : NULL,
					.tri = store ? tri : NULL};
	const char *trace_path = getenv("TC_CELL_TRACE");
	FILE *cell_trace = NULL;
	if (trace_path && *trace_path) {
		cell_trace = fopen(trace_path, "w");
		if (!cell_trace) {
			perror(trace_path);
			return 1;
		}
		const char *trace_frame = getenv("TC_CELL_TRACE_FRAME");
		tc_trace_set(cell_trace, trace_frame ? (uint32_t)strtoul(trace_frame, NULL, 0) : 0);
	}
	for (uint32_t i = 0; i < frames; i++) {
		int chosen = 0;
		char path[4096];
		for (int k = 4; k < argc; k++)
			chosen |= strtoul(argv[k], NULL, 0) == i;
		if (chosen) {
			snprintf(path, sizeof path, "%s%04u.cmd", argv[3], (unsigned)i);
			if (!(commands = fopen(path, "w"))) {
				perror(path);
				return 1;
			}
		}
		struct tc_stats stats;
		soft.triangles = soft.pixels = 0;
		if (i < 4096 && in_seen[i]) {
			tc_mouse(in_buttons[i], in_dx[i], in_dy[i], in_wheel[i]);
			applied++;
		}
		tc_draw(&target, i, frames, &stats);
		if (soft.triangles != stats.triangles)
			return 1;
		crc = tc_crc32(crc, &frame[0][0], sizeof frame);
		tris += stats.triangles;
		pixels += soft.pixels;
		if (chosen) {
			fclose(commands);
			commands = NULL;
			// The tables change with the land, not the frame.
			static int wrote_tables;
			if (!wrote_tables && write_tables(argv[3], &shade)) {
				perror(argv[3]);
				return 1;
			}
			wrote_tables = 1;
			snprintf(path, sizeof path, "%s%04u.fb", argv[3], (unsigned)i);
			FILE *fb = fopen(path, "w");
			if (!fb) {
				perror(path);
				return 1;
			}
			for (size_t p = 0; p < sizeof frame; p++)
				fprintf(fb, "%02x\n", (&frame[0][0])[p]);
			fclose(fb);
			snprintf(path, sizeof path, "%s%04u.png", argv[3], (unsigned)i);
			if (write_png(path, &land)) {
				perror(path);
				return 1;
			}
		}
	}
	int32_t cam_focus_x, cam_focus_z, cam_eye_x, cam_eye_z, cam_turn;
	tc_camera(&cam_focus_x, &cam_focus_z, &cam_eye_x, &cam_eye_z, &cam_turn);
	printf("HOST TERRAIN LAND=%08x FRAMES=%u TRIS=%u PIXELS=%u INPUT=%u CRC=%08x "
	       "CAMFOCUS=%ld,%ld CAMEYE=%ld,%ld CAMTURN=%ld",
	       (unsigned)tc_crc32(0, file, bytes), (unsigned)frames,
	       (unsigned)(tris / frames), (unsigned)(pixels / frames),
	       (unsigned)applied, (unsigned)crc,
	       (long)cam_focus_x, (long)cam_focus_z, (long)cam_eye_x,
	       (long)cam_eye_z, (long)cam_turn);
	int32_t pin_x, pin_z;
	if (tc_pin(&pin_x, &pin_z))
		printf(" PIN=%ld,%ld\n", (long)pin_x, (long)pin_z);
	else
		printf(" PIN=none\n");
	if (cell_trace)
		fclose(cell_trace);
	return 0;
}
