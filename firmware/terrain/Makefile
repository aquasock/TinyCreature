# SPDX-License-Identifier: GPL-3.0-or-later
#
# TinyCreature's terrain program for the Tang32 core, built with the pinned
# TinyNES runtime (tools/fetch_tang32.sh) and its boot ROM's receiver, which
# takes the land file; and the same renderer for this PC.
#
#   make TINYNES=<dir> BUILD=<dir>          $(BUILD)/terrain.elf
#   make TINYNES=<dir> BUILD=<dir> host     $(BUILD)/host/terrain_host
#
# FRAMES=<n> replaces the 600 frames of one orbit, and FABRIC=0 draws with
# tc_soft into the SDRAM buffers instead of the fabric rasterizer; give such
# builds their own BUILD=<dir>. CARDS=1 draws the art's cards, which both the
# program and the host twin must be built with. SPRITE names the tall sprite,
# SPRITE_CELL its cell size in source pixels, SPRITE_TINT the colour its mask
# is tinted, and SPRITE_DIR the directory holding the two tiles. The tint is saturated here
# because a neutral ramp is not available to it: the land's palette is dense
# between 25 and 75 degrees of hue, and its palest, least saturated colours are
# nearer to a grey than to the land's own entries, so a grey ramp claims about
# a tenth of the island's pixels on two of the six lands. A saturated ramp cost
# none of them.

TINYNES ?= $(abspath ../../build/tang32-src)
ifeq ($(wildcard $(TINYNES)/firmware/rt/rt.mk),)
$(error TinyNES runtime not found in $(TINYNES): run tools/fetch_tang32.sh)
endif

APP      := terrain
SOURCES  := main.c terrain.c $(TINYNES)/firmware/boot/load.c
CPPFLAGS += -I$(TINYNES)/firmware/boot $(if $(FRAMES),-DFRAMES=$(FRAMES)) \
            $(if $(FABRIC),-DFABRIC=$(FABRIC))

# In place of the runtime's -O2: this renderer is integer and index-heavy, and
# the board draws measurably faster for it. OPT= on the command line still wins.
OPT ?= -O3

include $(TINYNES)/firmware/rt/rt.mk

# The tall sprite the renderer plants: Dungeon Crawl Stone Soup's two-tile
# creatures, converted here and never committed, because the tiles are that
# project's art. The header is a build product, so the object that includes it
# waits for the rule that writes it.
SPRITE      ?= okawaru
SPRITE_DIR  ?= $(HOME)/Downloads/Dungeon Crawl Stone Soup Full/emissaries
SPRITE_CELL ?= 2
SPRITE_TINT ?= 6688cc
SPRITE_DRAW ?= 1
# The parameters are part of the header's name, so that changing one builds a
# header and a binary rather than reusing the last one's.
SPRITE_H    := $(BUILD)/sprite/$(SPRITE)-c$(SPRITE_CELL)-t$(SPRITE_TINT).h
SPRITE_TOOL := $(abspath ../../tools/convert_sprite.py)
SPRITE_CPPFLAGS := -I$(BUILD)/sprite -DTC_SPRITE_HEADER='"$(notdir $(SPRITE_H))"' \
                   -DTC_SPRITE_DRAW=$(SPRITE_DRAW)

# The art's cards. Off by default, and the switch has to reach both the program
# and the host twin or they would be asked for different frames; run_cards.sh
# and the run scripts pass it.
CARDS       ?= 0
CARDS_N     ?= 64
# The camera readout, on by default: a driven run draws where the eye and its
# focus are along the bottom of the frame. It costs a few dozen rectangles a
# frame and moves no scripted frame, so the recorded CRCs stay where they are.
# READOUT=0 takes it out.
READOUT     ?= 1
# The pin: one card standing at a cell of the island, named the way the readout
# names one, with 0xffff in either coordinate meaning there is no pin -- which
# is every scripted build, and what keeps their frames as recorded. A pinned
# build also opens looking at its pin from PIN_DIST back, in Q4, so it stands
# where it was asked to stand. run_tang32_feel.sh passes all three.
PIN_X       ?= 0xffff
PIN_Z       ?= 0xffff
PIN_DIST    ?= 3200
PIN_PITCH   ?= 2731
# A card is a box that keeps one facing: CARD_YAW is which way its front looks,
# in the same 1/65536 of a turn the camera's angle uses, and CARD_DEPTH how
# thick it is, in Q4 -- a tenth of its height by default.
CARD_YAW    ?= 0
CARD_DEPTH  ?= 48
# How wide one column of a card face is on the screen, in whole pixels. A face
# is drawn as columns this wide rather than as one rectangle, which is what
# lets its outline follow the quadrilateral it projects into; smaller is
# closer and costs a command a column. 1000 draws the single rectangle of
# before.
CARD_COLUMN_PX ?= 3
# A card's faces as textured triangles from their own projected corners rather
# than as columns of rectangles: the outline is the quadrilateral exactly and
# the texels are the projective quotient of the planes the fill steps. Off
# until the fabric's rasterizer can fill one, which the host twin and the
# board's software path already can.
CARD_TEX    ?= 0
COMMON_CPPFLAGS := $(SPRITE_CPPFLAGS) -DTC_CARDS=$(CARDS) \
                   -DTC_CARDS_N=$(CARDS_N) -DTC_READOUT=$(READOUT) \
                   -DTC_PIN_X=$(PIN_X) -DTC_PIN_Z=$(PIN_Z) \
                   -DTC_PIN_DIST=$(PIN_DIST) -DTC_PIN_PITCH=$(PIN_PITCH) \
                   -DTC_CARD_YAW=$(CARD_YAW) -DTC_CARD_DEPTH=$(CARD_DEPTH) \
                   -DTC_CARD_COLUMN_PX=$(CARD_COLUMN_PX) -DTC_TEX=$(CARD_TEX)

# The art's tiles: a generated header, off by default because the art is
# fetched rather than committed, so a fresh clone builds. TILES=1 wants the
# sheet in TILES_SHEET and no more tiles than fpga/raster.sv's store holds,
# which its TILE_COUNT sizes at 64.
TILES         ?= 0
TILES_SHEET   ?= $(abspath ../../build/tiles/Meph/data/art/Meph_32x32.png)
TILES_LIMIT   ?= 64
TILES_COLOURS ?= 64
TILES_FIRST   ?= 192
TILES_H       := $(BUILD)/tiles/meph-$(TILES_COLOURS)c-$(TILES_LIMIT)t.h
TILES_TOOL    := $(abspath ../../tools/convert_tiles.py)

ifeq ($(TILES),1)
TILES_FLAGS := -I$(BUILD)/tiles -DTC_TILES_HEADER='"$(notdir $(TILES_H))"'
COMMON_CPPFLAGS += $(TILES_FLAGS)
CPPFLAGS += $(TILES_FLAGS)

$(TILES_H): $(TILES_TOOL) $(TILES_SHEET)
	@mkdir -p $(dir $@)
	@python3 $(TILES_TOOL) --sheet "$(TILES_SHEET)" --first $(TILES_FIRST) \
		--colours $(TILES_COLOURS) --limit $(TILES_LIMIT) --out $@

$(call objects,terrain.c): $(TILES_H)
endif

CPPFLAGS += $(COMMON_CPPFLAGS)

$(SPRITE_H): $(SPRITE_TOOL) $(wildcard $(SPRITE_DIR)/$(SPRITE)_top.png)
	@mkdir -p $(dir $@)
	@python3 $(SPRITE_TOOL) "$(SPRITE_DIR)" $(SPRITE) --cell $(SPRITE_CELL) \
		--tint $(SPRITE_TINT) --out $@

$(call objects,terrain.c): $(SPRITE_H)

HOST_CC ?= gcc
host: $(BUILD)/host/terrain_host

$(BUILD)/host/terrain_host: terrain.c host.c terrain.h $(SPRITE_H) $(MAKEFILE_LIST)
	@mkdir -p $(dir $@)
	$(HOST_CC) -O2 -std=gnu11 -Wall -Wextra -Werror $(COMMON_CPPFLAGS) -o $@ terrain.c host.c

.PHONY: host
