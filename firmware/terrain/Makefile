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
# The handover: whether the program hands the link back to the desk layer so
# the board's own mouse and keyboard can drive it (TANG-001). Off by default,
# because a gated run's frames come from the input replayed out of the land
# file's tail and a live mouse must not move the camera under them; the demo
# and feel builds pass HANDOVER=1.
HANDOVER    ?= 0

CARDS       ?= 0
CARDS_N     ?= 64
# The opaque crossed-card tree experiment. TREE_ART=1 makes a two-tile sheet
# from Meph's aligned base, background and top layers; TREES=1 plants that
# lower/upper pair as two perpendicular planes without changing the FPGA core.
TREES       ?= 0
TREES_N     ?= 16
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
# The card's size: how tall and wide the box is, in Q4, and its thickness a
# tenth of that by default. Three cells (480) is a small building; half a cell
# (80) is about a villager in the original game.
CARD_UNITS  ?= 480
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
# Whether a card keeps its four thin near-black sides. On, it is a box and the
# sides show at an angle; off, it is a two-faced billboard and cutout art has
# no black frame. The transparent texel is skipped either way.
CARD_EDGE   ?= 0
COMMON_CPPFLAGS := $(SPRITE_CPPFLAGS) -DTC_CARDS=$(CARDS) \
                   -DTC_CARDS_N=$(CARDS_N) -DTC_TREES=$(TREES) \
                   -DTC_TREES_N=$(TREES_N) -DTC_READOUT=$(READOUT) \
                   -DTC_PIN_X=$(PIN_X) -DTC_PIN_Z=$(PIN_Z) \
                   -DTC_PIN_DIST=$(PIN_DIST) -DTC_PIN_PITCH=$(PIN_PITCH) \
                   -DTC_CARD_YAW=$(CARD_YAW) -DTC_CARD_DEPTH=$(CARD_DEPTH) \
                   -DTC_CARD_UNITS=$(CARD_UNITS) \
                   -DTC_CARD_COLUMN_PX=$(CARD_COLUMN_PX) -DTC_TEX=$(CARD_TEX) \
                   -DTC_CARD_EDGE=$(CARD_EDGE) -DTC_HANDOVER=$(HANDOVER) \
                   -DTC_TREE_WHOLE=$(TREE_WHOLE) -DTC_PLANTS=$(PLANTS)

# The art's tiles: a generated header, off by default because the art is
# fetched rather than committed, so a fresh clone builds. TILES=1 wants the
# sheet in TILES_SHEET and no more tiles than fpga/raster.sv's store holds,
# which its TILE_COUNT sizes at 64.
TILES         ?= 0
TILES_SHEET   ?= $(abspath ../../build/tiles/Meph/data/art/Meph_32x32.png)
TILES_LIMIT   ?= 64
TILES_COLOURS ?= 64
TILES_FIRST   ?= 192
TREE_ART      ?= 0
TREE_WHOLE    ?= 0
TREE_ART_DIR  ?= $(abspath ../../build/tiles/Meph/data/art)
TREE_SHEET    := $(BUILD)/trees/meph-tree.png
TREE_TOOL     := $(abspath ../../tools/make_tree_sheet.py)
TREE_TOOL_ARGS := $(if $(filter 1,$(TREE_WHOLE)),--whole,)
ifeq ($(TREE_ART),1)
ifneq ($(TILES),1)
$(error TREE_ART=1 requires TILES=1)
endif
TILES_SHEET   := $(TREE_SHEET)
ifeq ($(TREE_WHOLE),1)
TILES_LIMIT   := 64
else
TILES_LIMIT   := 2
endif
endif
# The plants sheet overrides the tree sheet when both knobs are asked for;
# a build uses one art set at a time.  PLANT_TILES is also the number of
# script tree types the plant converter maps onto it.
PLANT_ART     ?= 0
PLANT_TILES   ?= 16
PLANT_TREE_CELLS ?= 23,3,17,1
PLANT_EXTRA_TILES ?= 4
PLANT_ART_DIR ?= $(abspath ../../build/tiles/Meph/data/art)
PLANT_SHEET   := $(BUILD)/plants/meph-plants.png
PLANT_SHEET_TOOL := $(abspath ../../tools/make_plant_sheet.py)
ifeq ($(PLANT_ART),1)
ifneq ($(TILES),1)
$(error PLANT_ART=1 requires TILES=1)
endif
TILES_SHEET   := $(PLANT_SHEET)
TILES_LIMIT   := $(shell expr $(PLANT_TILES) + $(PLANT_EXTRA_TILES))
endif
TILES_H       := $(BUILD)/tiles/meph-$(TILES_COLOURS)c-$(TILES_LIMIT)t.h
TILES_TOOL    := $(abspath ../../tools/convert_tiles.py)

ifeq ($(TILES),1)
TILES_FLAGS := -I$(BUILD)/tiles -DTC_TILES_HEADER='"$(notdir $(TILES_H))"'
COMMON_CPPFLAGS += $(TILES_FLAGS)
CPPFLAGS += $(TILES_FLAGS)

ifeq ($(TREE_ART),1)
$(TREE_SHEET): $(TREE_TOOL) $(TREE_ART_DIR)/_Meph_trees.png \
                              $(TREE_ART_DIR)/_Meph_trees-bg.png \
                              $(TREE_ART_DIR)/_Meph_trees-top.png
	@mkdir -p $(dir $@)
	@python3 $(TREE_TOOL) --base "$(TREE_ART_DIR)/_Meph_trees.png" \
		--background "$(TREE_ART_DIR)/_Meph_trees-bg.png" \
		--top "$(TREE_ART_DIR)/_Meph_trees-top.png" $(TREE_TOOL_ARGS) --out $@
endif

ifeq ($(PLANT_ART),1)
$(PLANT_SHEET): $(PLANT_SHEET_TOOL) $(PLANT_ART_DIR)/_Meph_plants.png \
                                $(PLANT_ART_DIR)/_Meph_plants-top.png \
                                $(PLANT_ART_DIR)/_Meph_trees.png \
                                $(PLANT_ART_DIR)/_Meph_trees-top.png
	@mkdir -p $(dir $@)
	@python3 $(PLANT_SHEET_TOOL) --base "$(PLANT_ART_DIR)/_Meph_plants.png" \
		--top "$(PLANT_ART_DIR)/_Meph_plants-top.png" \
		--count $(PLANT_TILES) --also $(PLANT_TREE_CELLS) \
		--extra-base "$(PLANT_ART_DIR)/_Meph_trees.png" \
		--extra-top "$(PLANT_ART_DIR)/_Meph_trees-top.png" \
		--out $@
endif

$(TILES_H): $(TILES_TOOL) $(TILES_SHEET)
	@mkdir -p $(dir $@)
	@python3 $(TILES_TOOL) --sheet "$(TILES_SHEET)" --first $(TILES_FIRST) \
		--colours $(TILES_COLOURS) --limit $(TILES_LIMIT) --out $@

$(call objects,terrain.c): $(TILES_H)
endif

# The level script's own tree placements, one card each.  The script and the
# landscape it loads live outside the repository and their paths contain
# spaces, so they are read by the recipe and are not prerequisites; the tool
# is.  A build with no game data keeps PLANTS=0 and needs none of this.
PLANTS        ?= 0
PHASE_DETAIL  ?= 0
PLANT_UNITS   ?= 80
PLANT_BIG     ?= 120
PLANT_RANDOM  ?= 0
PLANT_SEED    ?= 0
PLANT_SCRIPT  ?= ../../build/wineprefix/drive_c/Program Files (x86)/Lionhead Studios Ltd/Black & White/Scripts/Land1.txt
PLANT_LAND    ?= ../../build/wineprefix/drive_c/Program Files (x86)/Lionhead Studios Ltd/Black & White/Data/Landscape/Land1.lnd
PLANT_TOOL    := $(abspath ../../tools/convert_plants.py)
PLANT_H       := $(BUILD)/plants/land1-plants.h
# The table the tool writes depends on every knob below, not only on the tool,
# so a build that changes one of them must regenerate it.  The stamp holds the
# knobs' values and is rewritten only when they change, which is what makes the
# header out of date.
PLANT_STAMP   := $(BUILD)/plants/flags
PLANT_WANT    := PLANTS=$(PLANTS) UNITS=$(PLANT_UNITS) BIG=$(PLANT_BIG) \
                 RANDOM=$(PLANT_RANDOM) SEED=$(PLANT_SEED) \
                 TILES=$(PLANT_TILES) \
                 TREE_CELLS=$(PLANT_TREE_CELLS) \
                 EXTRA_TILES=$(PLANT_EXTRA_TILES) \
                 SCRIPT=$(PLANT_SCRIPT) LAND=$(PLANT_LAND)
PLANT_ROTATION_FLAG := $(if $(filter 1,$(PLANT_RANDOM)),--random-rotation,)

ifeq ($(PLANTS),1)
PLANT_FLAGS := -I$(BUILD)/plants -DTC_PLANTS_HEADER='"$(notdir $(PLANT_H))"' \
               -DTC_PLANT_TILES=$(PLANT_TILES) -DTC_PLANT_UNITS=$(PLANT_UNITS) \
               -DTC_PLANT_BIG=$(PLANT_BIG)
COMMON_CPPFLAGS += $(PLANT_FLAGS)
CPPFLAGS += $(PLANT_FLAGS)
CPPFLAGS += $(if $(filter 1,$(PHASE_DETAIL)),-DTC_PHASE_DETAIL=1)

$(PLANT_STAMP): FORCE
	@mkdir -p $(dir $@)
	@echo '$(PLANT_WANT)' | cmp -s - $@ || echo '$(PLANT_WANT)' > $@

$(PLANT_H): $(PLANT_TOOL) $(PLANT_STAMP)
	@mkdir -p $(dir $@)
	@python3 $(PLANT_TOOL) --script "$(PLANT_SCRIPT)" \
		--land "$(PLANT_LAND)" --units $(PLANT_UNITS) --tiles $(PLANT_TILES) \
		$(PLANT_ROTATION_FLAG) --seed $(PLANT_SEED) \
		--out $@
$(call objects,terrain.c): $(PLANT_H)
endif

CPPFLAGS += $(COMMON_CPPFLAGS)

$(SPRITE_H): $(SPRITE_TOOL) $(wildcard $(SPRITE_DIR)/$(SPRITE)_top.png)
	@mkdir -p $(dir $@)
	@python3 $(SPRITE_TOOL) "$(SPRITE_DIR)" $(SPRITE) --cell $(SPRITE_CELL) \
		--tint $(SPRITE_TINT) --out $@

$(call objects,terrain.c): $(SPRITE_H)

HOST_CC ?= gcc
host: $(BUILD)/host/terrain_host

$(BUILD)/host/terrain_host: terrain.c host.c terrain.h $(SPRITE_H) \
                           $(if $(filter 1,$(PLANTS)),$(PLANT_H)) \
                           $(if $(filter 1,$(TILES)),$(TILES_H)) $(MAKEFILE_LIST)
	@mkdir -p $(dir $@)
	$(HOST_CC) -O2 -std=gnu11 -Wall -Wextra -Werror $(COMMON_CPPFLAGS) -o $@ terrain.c host.c

.PHONY: host

.PHONY: FORCE
FORCE:
