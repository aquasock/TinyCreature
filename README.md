# TinyCreature

TinyCreature aims to run Black & White (Lionhead, 2001) on the Sipeed Tang
Console 138K, as a core for TinyTang: the game's engine from
[openblack](https://github.com/openblack/openblack), an open-source
reimplementation, running on the FPGA's AE350 RISC-V processor, with a 3D
renderer built in the FPGA's fabric.

**Status: a stripped openblack landscape playground builds and runs on a PC**
with the game's files (below). It retains the complete world, renders it at 320
by 180 in a retro pixel style, and has a 47.2 MiB headless startup peak. The
first 32 MiB Tang image builds in the open flow, meets timing, and has passed on
the board, first with an animated test landscape, then drawing the game's real
Land 1 terrain from the AE350, and now through a first rasterizer in the
FPGA's fabric.

## Tang 32 MiB bring-up

The first target image keeps TinyNES's proven AE350, J9 SDRAM, UART loader and
720p HDMI foundation, while omitting its NES desk, audio and controller blocks.
It displays two 320 by 180 indexed framebuffers at exact 4x nearest-neighbour
scale. The buffers use 256 KiB at the top of SDRAM, leaving 31.75 MiB in the
application link region.

    bash tools/build_tang32.sh
    bash tools/test_tang32_video.sh
    bash tools/run_tang32.sh one-wire
    # or, with the TinyTang shell on /dev/ttyACM0:
    bash tools/run_tang32.sh two-wire

The run command loads a ten-second animated retro landscape, flips both
framebuffers, and requires a TinyCreature TANG32 OK report with zero late
SDRAM line fetches. Set TINYCREATURE_TANG_UART, TINYTANG_PORT, or TINYTANG_DIR
when the defaults do not match the local setup.

The accepted board run tested all 32 MiB, uploaded the 47,636-byte application
at 184.7 KB/s, displayed 600 frames at a 16,664 us mean period, and reported
zero late line fetches. The user saw the moving 2D landscape and accepted it.

The reproducible build pins TinyNES at
f5011dd374cfc65f4f17616fec97c903a66b6cc8 and applies
patches/tinynes-tang32.patch. It expects the same xPack RISC-V GCC, OSS CAD
Suite, nextpnr fork, and Apicula fork used by TinyNES. Every core build
synthesises once and places and routes seeds 1 to 8 in parallel, keeping the
clean seed with the fastest bus clock; a seed is clean when TinyNES's build
script accepts it. `build/tang32/seeds.tsv` lists each seed's result and
`TINYCREATURE_SEEDS` replaces the list. The first image routed at seed 11 at
82.41 MHz on the 75 MHz bus and 100.92 MHz on the 74.25 MHz pixel clock; the
image with the rasterizer kept seed 4 at 80.45 and 98.16 MHz.

The later 64 MiB configuration will add the separate J10 SDRAM bus as a second
32 MiB bank. The current memory map and controller remain the 32 MiB J9
baseline so this first board gate does not depend on unverified hardware.

## Terrain on the Tang

The Tang32 core also runs a first terrain renderer, `firmware/terrain/`. The
user's own Land 1 is converted on the PC by `tools/convert_land.py` into a
142 KB file under `build/land/`. The converter reads the `.lnd` format as
openblack does and gives each vertex the daylight colour openblack's terrain
shader would give it, from the cell's materials, noise, bump map and
luminosity, then fits those vertex colours to 239 palette entries. The AE350
receives the file over the loader, orbits the island once over 600 frames,
and draws shaded triangles back to front into the 320 by 180 indexed
framebuffers in integer arithmetic. Each pixel takes the palette entry
nearest the point of its triangle's colour plane that its own weights give,
those weights quantised to quarters, which is what the fabric can do in a
clock and what `tc_soft` does to the bit. Every triangle passes through a
single `submit()` call, which is where the fabric rasterizer takes over. The
same source builds for the PC as `terrain_host`, so the board's frame CRC can
be checked against it.

    bash tools/build_tang32.sh
    bash tools/test_tang32_raster.sh        # the rasterizer in simulation
    bash tools/run_tang32.sh terrain        # or: two-wire terrain
    bash tools/run_tang32.sh terrain-soft   # the same frames in software

A run can be driven instead of scripted. The camera belongs to the program
once something moves it, and a run's mouse reports ride in the land file's
tail, where the program finds them after the TCL2 header says where the land
ends. `tools/tang_input.py` writes such a sequence, and `TINYCREATURE_INPUT`
makes the runner append it and hand the same reports to the PC twin, so the
board and the PC must draw the same frames.

    python3 tools/tang_input.py pattern build/land/in.bin 600
    TINYCREATURE_INPUT=build/land/in.bin bash tools/run_tang32.sh terrain

A report is six bytes: the frame it belongs to, the buttons, and the mouse's
dx, dy and wheel, which is what a mouse's own HID boot report carries. A live
mouse sends the same six bytes to the AE350 as a frame in TinyTang's format,
`0xAA len_hi len_lo type`, type 0x16, with the frame 0xffff meaning "apply it
as it arrives". The UART stays in the loader mode it resets into because this
core carries no desk link, so the AE350 receives every byte TinyTang sends.
The board's own Bluetooth mouse drives the camera this way, TinyTang sending
the report from its desk task whether or not the desktop is drawn (TinyTang
entry 79, core-reference TANG-001), and the user has driven it. One thing to
know when a run is loaded from a PC: the loader holds the board's link for the
whole run, so in-band input cannot arrive until the host lets go of the port.

The camera the mouse drives is openblack's (core-reference OB-005): the middle
button held and dragged turns and tilts it, the left button held and dragged
slides the land along with the hand, and the wheel moves the camera in and
out, which this user asked to be the other way round from the usual. Four
constants in `firmware/terrain/terrain.h` are the whole feel --
`TC_TURN_PER_COUNT`, `TC_PITCH_PER_COUNT`, `TC_ZOOM_PER_COUNT` and
`TC_DRAG_DIVISOR` -- and `tools/run_tang32_feel.sh` builds for the mouse, loads
it and hands the board's link back to the mouse in one command, about forty
seconds a change, with no core rebuild and no TinyTang flash. A hand is drawn
where the pointer is, this project's own shape and not the game's, filled in
the palest sky and outlined in the deepest sea -- the program's own two
colours, the only pair that suits every land -- so that a left drag has
something on screen to hold the land with. Flying to a clicked point is not
implemented; it would want a screen-to-land raycast.

The run converts the land, prints the PC's totals, loads the program and the
land file, and fails unless the board reports `TinyCreature TERRAIN OK` with
the same land CRC, triangle and pixel means and frame CRC as the PC. Set
`TINYCREATURE_LND` to draw another landscape. The converted file is the
game's data and is never committed.

The accepted board run drew all 600 frames identically to the PC, frame CRC
`da75b4c1` from land CRC `c3794636`. It drew a mean 20,085 triangles and
filled 33,072 pixels per frame, took a mean 30.3 ms and at most 33.5 ms to
draw a frame on the AE350's software path, and so showed most frames in two
vertical blanks and the rest in three, with zero late line fetches. That draw
time is the CPU baseline the fabric renderer has to beat.

## The fabric rasterizer

`fpga/raster.sv` sits at `0xe8018000`, in the upper half of the video unit's
bus window. It takes `ROWS` and `TRI` commands through a 512-word FIFO, sets
up each triangle's three edge functions with a radix-4 sequential multiplier,
and fills the pixels whose centres all three functions place inside, one a
clock over the clamped bounding box. A `TRI` word carries its three corners'
palette entries, one byte each, and each filled pixel is shaded between them:
the edge functions give the pixel's weights, quantised to quarters by a
handful of compares instead of a divide, and the mix is done in the five bits
a channel the game's materials carry, which is what keeps the command four
words wide. The colour that comes out is looked up in a 32 KB table the
program loads, entry by entry, which holds the land's nearest entry to each
of those 32768 colours, and the palette itself is 256 entries in the same five
bits. It draws into two 320 by 180 frame
buffers of its own in single-clock block RAM, which the video unit shows
through the same line-fetch handshake as the SDRAM, and the CPU reads a buffer
back through two registers, which is also where the unit starts and reports a
CRC-32 of the buffer it has just drawn. `tc_soft` in `terrain.c` is its exact model, so
`terrain_host` predicts every pixel. `tools/test_tang32_raster.sh` drives two
real Land 1 frames' commands through it in simulation and compares the result
byte for byte, through the read-back registers and the line fetch, and checks
the unit's frame checksum against the same value the C computes.

On the board the rasterizer drew all 600 frames as the PC model did, frame
CRC `da75b4c1` from 20,085 triangles and 33,072 pixels a frame, with zero
late line fetches. It is idle by the time each frame has been sent, so the
CPU sets the pace: a mean 29.4 ms to send a frame and at most 35.2 ms,
against 30.3 ms and 33.5 ms for the same frames filled in software
(`terrain-soft`). Shading every pixel between its triangle's three corner
colours, rather than filling it with their mean, costs about 1.6 ms a frame
and the worst frame 2.2 ms: the fill takes two clocks a pixel instead of one,
each triangle walks the palette before it starts, and the CPU waits on a
fuller FIFO more often. The mean period is 36.7 ms, about 27 frames a second,
where the unshaded fill held 30. The mesh averages under two screen pixels a
triangle at the default orbit, so most of that interpolation is finer than the
display can show; the user judged the look on the board, close in where it
tells, and accepted the frame drop. Three seconds of the run's twenty-five
were not drawing at
all: reading each frame's buffer back over the bus to check it cost about 5 ms
a frame, an eighth of the period, so the rasterizer now folds a frame's buffer
into a CRC-32 itself, in address order and seeded with the state the run has
reached, and the program reads one register a frame instead of 14,400. That
took the mean frame from 42.1 ms to 33.3 ms, which is two vertical blanks, so
the orbit runs at 30 frames a second throughout: 599 of its 600 frames in two
blanks and one in three. Measured on the board, sending a triangle's four
command words costs 23 CPU cycles within the frame loop, and a cached store
that misses into the SDRAM about 620 cycles a 32-byte line, but the CPU's
time is not that memory stream. A phase profile puts it in the cell walk and
the triangle submission inside it: cutting the vertex record from 24 bytes to
8, which the whole island is walked over once a frame, moved the mean frame
by only 2.5%, while taking the everyday all-front triangle straight from the
record, without the clip machinery, and building the program at `-O3` took
the mean from 37.9 ms to 28.2 ms.

## openblack on a PC

The landscape playground keeps each original world's dimensions, terrain,
materials, sky, water and camera coordinates. It skips the quest scripts,
audio, entities, vegetation, sprites, footpaths, terrain collision meshes and
the debug GUI runtime. Its entity spatial map is a no-op instead of two dense
512 by 512 arrays because the playground has no entities. It replaces the 1024
by 1024 reflection and full-island footprint buffers with one-pixel
placeholders. Its launcher renders at 320 by 180, scales that image to a 640 by
360 window with nearest-neighbour sampling, and caps the playground at 30
frames per second with reduced process priority.

```sh
tools/build_openblack_playground.sh
tools/run_openblack_playground.sh "<install>/Black & White"
```

The second command finds the repository's local Wine install automatically
when no path is given. Use the arrow keys to move, the mouse wheel to zoom,
the middle mouse button to rotate, and Escape to exit. Another landscape can
be selected with an openblack option, for example `-s Land2.txt` after the
install path. `OPENBLACK_PIXEL_SCALE=1` restores native 640 by 360 rendering;
the default value is 2.

The accepted retro build completed a 300-frame Vulkan run in 10.72 seconds at
the 30 FPS cap and used 9% CPU. Replacing its unused 28 MiB entity map reduced
three Noop startup runs to a 47.23 MiB mean peak, down from 75.68 MiB with the
dense map and 360.76 MiB for unmodified openblack. The tested Vulkan process
measured 190.74 MiB RSS, 133.55 MiB PSS and 114.36 MiB private memory on this PC;
the FPGA renderer replaces that build's Vulkan driver and video buffers. The
headless software measurement is now 16.8 MiB below the fitted 64 MiB SDRAM
capacity, before adding the target renderer interface and firmware.

The unmodified PC build remains useful as the reference:

```sh
tools/fetch_openblack.sh      # openblack at a pinned commit, with its vcpkg
cmake -S third_party/openblack -B build/openblack --preset ninja-multi-vcpkg
cmake --build build/openblack --config Release
build/openblack/bin/Release/openblack -g "<install>/Black & White" -V
tools/profile_openblack.sh "<install>/Black & White"
```

`<install>` is the game installed and patched to 1.2: openblack reads its
`Data` and `Scripts` folders. On Linux the installer and patches 1.1 and 1.2
run under Wine; a prefix of its own, inside `build/`, keeps it apart from
`~/.wine`. On the user's copy the landscape draws correctly, while villagers
and the creature are missing and the log lists script functions openblack has
not implemented yet.

## PC resource profile

`tools/profile_openblack.sh` runs three startup, no-vsync and realtime cases at
1280 by 720 with logging disabled and OpenAL Soft's null driver. It compares
bgfx's Noop and Vulkan backends and writes its generated measurements under
`build/profile-openblack/`.

The profile on the development PC at openblack `a243c6b2` measured:

| Backend | Mean peak RSS | Mean peak PSS | Mean peak private memory | Threads |
|---|---:|---:|---:|---:|
| Noop | 360.76 MiB | 357.08 MiB | 356.70 MiB | 4 |
| Vulkan | 531.87 MiB | 487.30 MiB | 463.33 MiB | 10 |

The Vulkan no-vsync runs used a mean 0.861 ms of CPU time per steady frame on
this PC. At normal realtime cadence, where openblack also runs its 100 ms game
turns, the median was 14.45 ms per frame. That realtime number includes Vulkan
driver and render-thread work and is not an estimate for the AE350.

The Noop result establishes that the current asset and engine representation
is already far beyond 64 MiB before a real renderer is included. An SDRAM-only
port therefore requires a substantial asset streaming and memory-layout
redesign; merely enabling the second SDRAM chip is insufficient. The next
software measurement must identify the owners of the headless footprint before
choosing that redesign or the DDR3 controller.

## What it builds on

- **openblack** (GPL-3.0) supplies the game: its logic, file formats and
  renderer, which draws through bgfx with a small, fixed set of shader
  programs that a fixed-function FPGA renderer can be made to cover.
- **TinyNES** (https://github.com/aquasock/TinyNES) brought up the AE350 on
  this board in the open flow, with its SDRAM, HDMI output, sound, controllers
  and loading over TinyTang, and records what it measured in its
  `.ai/core-reference.md`.
- **TinyTang** (https://github.com/aquasock/TinyTang) is the board's firmware,
  which loads cores from the SD card and hosts the desktop.

## What it needs before it can work

- Memory: the fitted J9 SDRAM module has two 32 MiB chips, but the existing
  controller can address only one because the second chip-select signal has
  not been identified. The stripped playground's measured headless startup
  peak is 47.2 MiB, leaving 16.8 MiB for the target renderer interface and
  firmware within the full 64 MiB module. Bounded terrain staging and compact
  runtime data remain necessary to protect that margin. The module's 1 GiB DDR3
  remains a direct alternative, but it has no open-flow controller yet.
- A renderer: a fixed-function rasterizer in the FPGA, with vertex work on the
  AE350.
- A way to bring hundreds of megabytes of game data from the card faster than
  the 2 Mbaud link TinyNES uses.

The source audit found that a single-threaded bgfx target requires removing its
target-side `multithreaded` vcpkg feature. Removing ImGui cleanly requires an
openblack build option that substitutes a no-op `DebugGuiInterface` and omits
the Debug sources, ImGui shaders, package and `imgui_user` library. Openblack's
own engine and component sources do not create C++ threads.

## Game data

The game's assets are not part of this repository and never will be. You
extract them from your own copy of Black & White, as openblack describes.

## Licence

GPL-3.0 (`LICENSE`), the whole repository, matching openblack.
