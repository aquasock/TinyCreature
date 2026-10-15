# SPDX-License-Identifier: GPL-3.0-or-later
#
# TinyCreature's terrain program for the Tang32 core, built with the pinned
# TinyNES runtime (tools/fetch_tang32.sh) and its boot ROM's receiver, which
# takes the land file; and the same renderer for this PC.
#
#   make TINYNES=<dir> BUILD=<dir>          $(BUILD)/terrain.elf
#   make TINYNES=<dir> BUILD=<dir> host     $(BUILD)/host/terrain_host
#
# FRAMES=<n> replaces the 600 frames of one orbit; give such builds their own
# BUILD=<dir>.

TINYNES ?= $(abspath ../../build/tang32-src)
ifeq ($(wildcard $(TINYNES)/firmware/rt/rt.mk),)
$(error TinyNES runtime not found in $(TINYNES): run tools/fetch_tang32.sh)
endif

APP      := terrain
SOURCES  := main.c terrain.c $(TINYNES)/firmware/boot/load.c
CPPFLAGS += -I$(TINYNES)/firmware/boot $(if $(FRAMES),-DFRAMES=$(FRAMES))

include $(TINYNES)/firmware/rt/rt.mk

HOST_CC ?= gcc
host: $(BUILD)/host/terrain_host

$(BUILD)/host/terrain_host: terrain.c host.c terrain.h $(MAKEFILE_LIST)
	@mkdir -p $(dir $@)
	$(HOST_CC) -O2 -std=gnu11 -Wall -Wextra -Werror -o $@ terrain.c host.c

.PHONY: host
