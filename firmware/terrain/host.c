// SPDX-License-Identifier: GPL-3.0-or-later
//
// The terrain renderer on this PC: draws the same frames as the AE350
// program from the same TCL1 file and prints the same totals and frame CRC,
// so a board run can be compared with it, and writes chosen frames as PNGs.
//
//   terrain_host <land.tcl> [frames] [png-prefix frame...]
//
// prints
//   HOST TERRAIN LAND=<crc> FRAMES=<n> TRIS=<mean> PIXELS=<mean> CRC=<crc>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "terrain.h"

static uint8_t frame[TC_HEIGHT][TC_WIDTH];

static void put32(FILE *f, uint32_t v)
{
	uint8_t b[4] = {(uint8_t)(v >> 24), (uint8_t)(v >> 16), (uint8_t)(v >> 8), (uint8_t)v};
	fwrite(b, 1, 4, f);
}

static void chunk(FILE *f, const char *type, const uint8_t *data, uint32_t n)
{
	put32(f, n);
	fwrite(type, 1, 4, f);
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
	tc_init(&land, work);

	uint32_t crc = 0;
	uint64_t tris = 0, pixels = 0;
	for (uint32_t i = 0; i < frames; i++) {
		struct tc_stats stats;
		tc_draw(&frame[0][0], TC_WIDTH, i, frames, &stats);
		crc = tc_crc32(crc, &frame[0][0], sizeof frame);
		tris += stats.triangles;
		pixels += stats.pixels;
		for (int k = 4; k < argc; k++)
			if (strtoul(argv[k], NULL, 0) == i) {
				char path[4096];
				snprintf(path, sizeof path, "%s%04u.png", argv[3], (unsigned)i);
				if (write_png(path, &land)) {
					perror(path);
					return 1;
				}
			}
	}
	printf("HOST TERRAIN LAND=%08x FRAMES=%u TRIS=%u PIXELS=%u CRC=%08x\n",
	       (unsigned)tc_crc32(0, file, bytes), (unsigned)frames,
	       (unsigned)(tris / frames), (unsigned)(pixels / frames), (unsigned)crc);
	return 0;
}
