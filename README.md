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
luminosity, then fits those vertex colours to 237 palette entries. The rest of
the 256 are the sky's eight-entry ramp, the cursor's two colours and its
outline in entry 0, and the sea is one blue, so the seven entries its ramp used
to take are free; the land's own colours start at entry 19. The AE350 receives
the file over the loader, orbits the island once over 600 frames, and draws
shaded triangles back to front into the 320 by 180 indexed framebuffers in
integer arithmetic. Each pixel takes the palette entry
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
slides the land along with the cursor, and the wheel moves the camera in and
out, which this user asked to be the other way round from the usual. A middle
press takes hold of the piece of land under the cursor: that point becomes what
the camera looks at and the point it turns about, at the distance it was from
the camera when the button went down, so the land under the finger holds still
while everything else swings around it. The point is found by taking the
camera and the projection back apart and marching the result against the
height field the renderer draws, once per press, and a press that misses the
island leaves the camera turning about the focus it had. While the middle
button is held the cursor is drawn at the middle of the screen, which is where
the aim puts the land it took, and it follows the mouse again when the button
comes up. A left press on the land takes hold of it the same way: the piece
of land under the cursor becomes a world point the cursor is holding, and
while the button is held the cursor is drawn where that point projects, so it
travels with the land it took rather than staying under the mouse, and when
the button comes up the cursor is left holding where the land went while the
mouse moves it on from there. Four constants in `firmware/terrain/terrain.h`
are the whole feel --
`TC_TURN_PER_COUNT`, `TC_PITCH_PER_COUNT`, `TC_ZOOM_PER_COUNT` and
`TC_DRAG_DIVISOR` -- and `tools/run_tang32_feel.sh` builds for the mouse, loads
it and hands the board's link back to the mouse in one command, about forty
seconds a change, with no core rebuild and no TinyTang flash. The cursor is
drawn from the Dungeon Crawl Stone Soup tile set (CC0, credited in
`THIRD_PARTY.md`), which the source reduces to two 16 by 16 silhouettes: the
green frame while no button is down and the red crosshair while one is held,
changed the moment a button moves either way, whether or not the mouse does.
Both are drawn on whole framebuffer pixels, because the fill keeps a pixel
whose centre lies on a triangle's edge and a sprite on a half pixel therefore
draws one-pixel lines two pixels wide, and both about their own middle rather
than beside it, so the land a press takes is the piece the marker is centred
on. Their fill is the tile's own green and red, which the shading table admits
as two entries of its own; their outline comes out the land's nearest
near-black. Flying to a clicked point is not implemented; it would want a
screen-to-land raycast.

A tall sprite stands on the island's middle: `tools/convert_sprite.py` stacks
one of the tile set's two-tile creatures into 32 by 64, trims it to the art,
tints it and quantises it to the seven palette entries the sea gave up when it
became one blue, and writes a C header the build generates and never commits,
so the art stays out of the repository as the landscape does. `tc_palette`
gives those entries the ramp and the shading table admits them beside the
cursor's two, which is what keeps them off the land: a neutral grey ramp
claims about a tenth of the pixels Land 2 draws, because the land's palest,
least saturated colours are nearer a grey than to the land's own entries,
while a saturated one claims none -- so with the ramp admitted and the sprite
absent all six scripted lands still draw the frame CRCs they drew before it
existed. The land's own entries are 192 rather than the 237 it could take,
because the entries above 211 are the pool the tile art this project is turning
to has to be fitted into and the island gives them up cheaply: fitting its 817
vertex colours to 237, 224, 192, 160, 128, 96, 64 and 48 entries costs a
weighted mean error of 2.04, 2.17, 2.85, 6.19, 7.82, 10.01, 13.13 and 14.37 out
of 255, so the first forty-five entries go for about one per cent of colour and
the next thirty-two cost more than those did. That is Land 1's curve and not
the others': at 192 the remaining five fit to between 1.93 and 17.40, so a
different world would want its own decision about how much of the pool it
takes. The sprite is drawn the way the cursor is, a run of one colour a row
as a rectangle, and from inside the cell walk at the cell it stands on, so
nearer land paints over it and farther land stays behind. Its height is six
cells of world and it obeys the camera, which makes it about fifteen pixels at
the orbit's reach and larger as the wheel comes in; its two-pixel cells are
under a pixel each at that reach, so it is a smudge until you come in, which a
coarser cell table chosen by screen size would fix. It costs 360 triangles and
0.74 ms a frame on the board, inside the three-blank hold, so `VBLMIN` and
`VBLMAX` are still both 3. That same 0.74 ms is what a population would cost:
a hundred mosaic sprites is about 74 ms, so a village wants textures in the
fabric rather than more triangles, and the palette room a texture needs wants
the land's 237 entries re-fitted.

The renderer also draws cards: axis-aligned rectangles filled with one 32 by 32
tile each. They go to the fabric as a five-word `CARD` command -- the opcode and
the tile, the pixel rectangle, the Q8 texel steps and the accumulators to start
from -- and the caller works all of that out because the fabric has no divider,
so the fill only adds. It takes three clocks a pixel, because the tile store is
a block RAM whose answer arrives the clock after its address and the address is
a register changing on that same edge; two clocks wrote each pixel the previous
pixel's texel, which the testbench caught as a frame reading one column left.
A texel is written as the palette entry `192 + its own index`, so the shading
table is never consulted and art cannot take colour off the land. `tc_soft_card`
takes the same five fields, so the model and the fabric cannot disagree about
the arithmetic, only about carrying it out, and `tests/raster_tb.sv` replays two
real frames' commands and requires the unit's read-back to match the twin word
for word. On the board the same check passes: the four cards add no triangles,
33158 pixels become 33325, the frame takes 29995 us rather than 29661, `VBLMIN`
and `VBLMAX` are still both 3, and the frame CRC is `0609cd9f` against the host's
`0609cd9f`. The first hardware attempt drew the right number of pixels in the
wrong colours, which is what a card filled from a store the program had never
written looks like; `fabric_tiles` in `main.c` now loads it four bytes a write
before the first frame. The tiles it loads are the converted art when the build
has them: `TILES=1` runs `tools/convert_tiles.py` over Meph's sheet and the
header it writes names the tiles and the sixty-four palette entries at 192,
while a build without the art still draws four synthetic tiles so the path can
be exercised with nothing fetched. The unit's store holds sixty-four tiles and
Meph's sheet has 255, so the header takes the first sixty-four of them.

A build that times its own phases with the core's cycle counter reports the
mean cells a frame drew and the time it spent in the sky and sea rows, the
block cull and the cell walk: `CELLS=18158 PHROWS=2us PHCULL=48us
PHWALK=29607us` against a 29,662 us mean frame. So the frame is the walk, and
the rows and the cull are free. Three throwaway builds that measured the walk
by throwing work away split it three ways: 9.0 ms computing the cells -- the
vertices, the flags, the order and each cell's setup -- 4.9 ms testing the
triangles, which is the back-face cross product, the guard band and the
bounding box, and 15.7 ms writing the four command words. That last is 53 per
cent of the frame, 80,340 words at about 196 cycles each back to back, which
the CPU's store buffer cannot overlap; AE-002 measured the same writes at 23
cycles when other work sits between them. Walking the cells row-major instead
of back to front moved the walk by one per cent, so the depth order is nearly
free and the cost is the interface rather than the traversal: that is what a
command list the fabric fetches for itself would take, and it is why the
CPU's time is best spent by not sending the commands at all. What such a list
would cost was then measured on the board: the same 80,340 words written to the
SDRAM for a frame cost 9,023 us, which is 84 cycles a word against the fabric's
196, and the flush a fabric reader would need for them cost another 550 us. So
a command list saves about a fifth of a frame rather than the order of
magnitude its arithmetic suggests, and the words themselves are the cost either
way: the same frame read by a cell-shaped command, which needs 6 words for two
triangles where four-word triangles need 8, would save 4.7 ms for far less
work. Two things this cycle's software pass then tried, and neither helped.
Walking the cells row-major rather than back to front, which should have made
the vertex records cheap to reach, moved the walk by one per cent, so the depth
order is nearly free. And computing every vertex in row order before the walk
-- the same arithmetic, with the terrain's own layout under it -- made the
frame a third slower, 40.7 ms against 30.8, because the pass writes 150 KB of
records that the walk then has to fetch again. The walk's vertex work is
7.3 ms, 18,690 vertices at 293 cycles each, and that is nearly every vertex in
the grid, so the stamp saves no work; what costs is reaching them rather than
the arithmetic, and both of the ways that promised cheaper reaches have now
been measured and do not.

The run converts the land, prints the PC's totals, loads the program and the
land file, and fails unless the board reports `TinyCreature TERRAIN OK` with
the same land CRC, triangle and pixel means and frame CRC as the PC. Set
`TINYCREATURE_LND` to draw another landscape. The converted file is the
game's data and is never committed.

The accepted board run drew all 600 frames identically to the PC, frame CRC
`5b022d0d` from land CRC `205046bf`. It drew a mean 20,085 triangles and
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
CRC `5b022d0d` from 20,085 triangles and 33,072 pixels a frame, with zero
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

The frame loop now holds every frame for the same three vertical blanks, so the
orbit runs at a steady 20 frames a second instead of flickering between 30 and
20. The reason is the blank itself: the display shows a frame only on a blank
boundary, so a draw costing 29.5 ms against a 16.7 ms blank lands near one and
takes the next blank on some frames and the one after on others, which the eye
reads as the motion speeding up and slowing down. Held at three, the shown
period is 49,978 us, VBLMIN and VBLMAX are both 3 over all 600 frames, and the
frame CRC is unchanged at `5b022d0d`: the hold alters when a frame is shown and
not one pixel of it. The worst frame the renderer draws, 35.3 ms, has 14.7 ms
of margin inside the 50.0 ms hold. `TC_BLANKS_PER_FRAME` in `main.c` is the one
number: `2` buys back 30 frames a second and the flicker with it, `4` a
rock-steady 15. If a frame ever misses the hold the run prints
`BAD TINYCREATURE CADENCE` rather than jittering on unannounced. The cost is
that the mouse is read once a frame, so a report waits up to the hold to be
acted on: a mean 38 ms before, a flat 50 now.

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
