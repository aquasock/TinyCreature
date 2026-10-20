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
`TINYCREATURE_SEEDS` replaces the list. This project's patch admits `SPINE19`
beside `SPINE26` in the pixel-clock bridge check, on TinyTang's measured
result; every other bridge pip is still refused. The first image routed at seed 11 at
82.41 MHz on the 75 MHz bus and 100.92 MHz on the 74.25 MHz pixel clock; the
image with the rasterizer kept seed 4 at 80.45 and 98.16 MHz.

The later 64 MiB configuration will add the separate J10 SDRAM bus as a second
32 MiB bank. The current memory map and controller remain the 32 MiB J9
baseline so this first board gate does not depend on unverified hardware.

### Power and boot mode from this PC

The board can be powered off and on, and booted one-wire or two-wire, without
a hand on it. Its power input runs through relay 1 of a dcttech USBRelay8 USB
relay board on the normally open contact, and its OTG cable to the PC has the
VBUS wire cut, so the PC cannot keep the board alive and the relay alone
powers it; no USB port on this PC can switch its own 5 V
(`.ai/core-reference.md` PWR-003). Which program the BL616 runs is chosen at a
cold power-up, and on this bench what chooses it is whether a USB host is on
the OTG port then (PWR-002): with one it is Sipeed's FT2232 debugger,
one-wire, and with none it is TinyTang, two-wire. The PC hides itself by
disabling the cable's port, which stops the data and nothing else.

    python3 tools/tang_power.py status
    python3 tools/tang_power.py cycle               # two-wire, about 15 s
    python3 tools/tang_power.py cycle --mode one-wire
    python3 tools/tang_power.py on | off

A two-wire cycle disables the port, powers the board off for five seconds and
on again, waits six seconds for the loader to choose, enables the port, and
fails unless TinyTang's console answers. The port is whichever one the Tang is
plugged into, on the PC or on a hub: the tool reads it from where the board
shows up on the bus in either mode and remembers it in `build/` for when the
board is off, so moving the cable needs nothing changed. The relay board's
hidraw node and every port's `disable` file need write access, which two udev
rules give the plugdev group:

    # /etc/udev/rules.d/60-usbrelay8.rules
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="05df", MODE="0660", GROUP="plugdev"
    # /etc/udev/rules.d/61-tang-port.rules: every port of every hub, the PC's own included
    ACTION=="bind", SUBSYSTEM=="usb", DRIVER=="hub", RUN+="/bin/sh -c 'for f in /sys%p/*-port*/disable; do chgrp plugdev $f && chmod g+w $f; done'"

`TINYCREATURE_POWER_RELAY` names another relay, and
`TINYCREATURE_TANG_USB_PORT` a port's sysfs directory; a cycle refuses if the
board is on the bus somewhere else.

## Terrain on the Tang

The Tang32 core also runs a first terrain renderer, `firmware/terrain/`. A
landscape the user owns -- Land 1, or a map pack's `.lnd` such as Celtic -- is
converted on the PC by `tools/convert_land.py` into a land file under
`build/land/`. The converter reads the `.lnd` format as openblack does and
gives each vertex the daylight colour openblack's terrain shader would give
it: both of the cell's materials and the bump map are sampled at the vertex's
block-local UV (openblack's `zx / yx` mapping), blended by the country
coefficient and scaled by the luminosity clamp, then the vertex colours are
fitted to 173 palette entries. The palette's other entries are the sky's
eight-entry ramp, the sea, the cursor's two colours and its outline in entry 0,
and the art's 64 at 192 to 255; the land's own colours start at entry 19.
The material textures are Meph's now. `tools/ground_map.tsv` maps all 17
Celtic materials to Meph tiles -- 14 from `Meph_32x32.png` and 3 from the ice
family in `_Meph_decorations_2.png` -- each with a gain that matches the
original material's luminance, and `convert_land.py --materials-map`
substitutes them before sampling; `TINYCREATURE_GROUND_MAP` selects the table
for a run. The AE350 receives
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

While the mouse is driving the camera the frame carries a readout of where it
is: the focus and the eye in the island's own cells and the bearing in
degrees, along the bottom, the first pair green and the second red so which is
which needs no label. There is no font in this renderer, so the digits are
seven-segment ones and a segment is one rectangle, drawn with the same
`hand_rect` the cursor and the sprite are drawn with; a digit that needs seven
segments costs seven of them, which is why the whole readout came to seventy
rectangles, or 146 triangles, on the frame it was measured on. It is drawn only when a mouse is driving the camera, which is what
keeps every scripted frame the project has on record byte for byte where it
was, and `READOUT=0` takes it out of a build altogether. What it costs a frame
is below what a frame's own variation can resolve: with a recorded drag of six
hundred reports driving the camera, the same run with the readout off draws
20,561 triangles and 30,535 pixels in a 29,264 us mean frame and the same run
with it on draws 20,707 triangles and 31,429 pixels in 29,196 us, so 146
triangles and 894 pixels a frame, and the mean frame time moved the wrong way
by 68 us. The run's report carries the same numbers -- `CAMFOCUS=111,103
CAMEYE=110,283 CAMTURN=539` for a scripted orbit's last frame, and the board
and the twin agree on them as they do on the frame CRC. A run driven from a PC
shows it too: `TINYCREATURE_INPUT=<file> tools/run_tang32.sh terrain` is the
same comparison with recorded reports instead of the scripted orbit. The
bearing is an angle a drag adds to without wrapping, so the readout takes the
low sixteen bits of it: it had printed turns past 359, and the user read one
back as `388`, where the true bearing was 28 degrees. The scripted orbit's last
frame, which the report had been calling 539, is 179.

A build can also be given one thing to stand in the world, which is the first
this renderer has that is neither the camera nor the land. `PIN_X` and `PIN_Z`
in the Makefile name a cell in the coordinates the readout shows, and the
program plants one card there, three cells tall, standing on that cell's own
ground and drawn through the same arithmetic the shelf of tiles uses -- one
copy of the projection, the clamping and the fill's steps, shared by both. A
pinned build opens looking at its pin from `PIN_DIST` back in Q4, twenty cells
by default, and its camera stands still on it until the mouse takes over, so
the first thing a pinned build shows is the card it was asked to stand there.
The pin is how this user put himself in his own world: he read `080 090` off
the readout while flying, the card was built at that cell, and the board then
drew it against the twin at CRC `065cd90a`, four times cheaper a frame than the
orbit because a close view culls the island down to 2,785 triangles from
20,445 and 3,543 cells from 18,158. A card is told from the land by the palette -- art texels are entries
192 and up, which the land never writes -- which is what made the pin's own
pixels countable: 1,482 of them in a 38 by 39 rectangle centred on the focus's
cell, and none at all in the same build with no pin.

That card's size was wrong, and flying over it is how the user found it: a card
shrank as the camera tilted down onto it. The size came from projecting a
segment of the world's vertical axis -- the card's base and the point three
cells above it -- and a vertical length foreshortens by the cosine of the tilt,
so the card went from 1,188 pixels across at the orbit's fifteen degrees to 36
at the tilt's seventy-nine, three percent of its area, and would have vanished
at the top of the tilt. A card is a rectangle that faces the camera, and its
size should follow how far away it is and not how the camera is pointing, so
the height is now three cells times the projection's own 4096 over the depth --
`project_xy`'s arithmetic with an x of three cells -- and the rectangle's top is
the base less that height rather than a projected world point. The same card now
measures 1,444 pixels at every tilt from 15 to 79 degrees, and at 10, 20, 40 and
80 cells of camera distance its area is 5,852, 1,444, 380 and 100 pixels, which
is the quartering a billboard should do. `PIN_PITCH` is the new knob the sweep
needed -- the tilt a pinned build opens at, in the same Q16 turn units the camera
uses -- and the first attempt at that sweep was five copies of one build, because
the knob was read by the program and never passed by the Makefile; what made the
real one a measurement was the eye moving from cell 109 behind the focus to 94
as the tilt went from 15 degrees to 79 while the card stayed 38 by 38. The
unpinned board run moved with the fix and moved only in the cards:
`TRIS=20445` and `CELLS=18158` unchanged, `PIXELS` from 35,831 to 36,080 -- the
shelf's sixty-four cards at their true size -- and the frame CRC to `21a74c13`.
The tall sprite takes its height from that same projected vertical segment and
shrinks the same way; it is left as it is here because this cycle was scoped to
the cards.

A card is then not a picture that turns to face the camera but an object: a box
three cells wide and tall and a tenth of that deep, standing on the ground and
looking one way, `CARD_YAW` in the same 1/65536 of a turn the camera's angle
uses. Each visible face is drawn as a run of columns, and every column is
filled from its own four projected corners -- the art on the front, the same art
on the back for now, and the four edges solid black, the thin side that says it
is a box rather than a sheet. A face whose normal points away from
the camera is dropped, and the rest are drawn farthest first, so the nearer ones
paint over the farther ones. The consequence is the one the user asked for: the
camera sees a card edge-on and then from behind as it circles the island. What
that measures, one card at 80,90 with the camera twenty cells back, is the front
face's art at 1,444 pixels in a 38 by 38 rectangle facing the camera, 1,107 in a
27 by 41 rectangle at 45 degrees -- 38 times the cosine, which is what a turning
face should do -- nothing at all at 90, where the card is edge-on, and 1,189
back from behind, with the black strip one pixel tall across the top when the
card faces the camera and three pixels wide beside it at 45. A face's true outline is the quadrilateral its
corners project into, and a rectangle cannot be one, which is what the user saw
as a distorted card: drawn as one rectangle the front face at 45 degrees was
27.5 by 44.3 pixels around a face of 1,047, so 141 of the 1,188 pixels drawn --
13 per cent of the face -- stood outside it. Drawn in columns three screen
pixels wide, that face draws 1,067 pixels with 20 of them outside it, and the
art moves at most 1.2 texels of 32 where a single rectangle moved it 5.5; at 20
degrees 48 pixels outside against 120 and at most 0.8 texels against 2.5; and
facing the camera the frame is unchanged to the byte. The columns' art runs
across the face with the same texel step and the same origin on its left edge,
so cutting a face up does not move the art sideways, while its rows are anchored
to each column's own height instead of the tallest part of the face.
Which way a face is cut matters as much as how finely. The columns run across
the face's width, and the width is u on every face but the two sides, whose
normal is along u and whose width is therefore n; a face cut the other way is
drawn as its own bounding rectangle again. That is what the top of a card was
before this was fixed, and it is what looking down on one showed: at seventy-one
degrees of tilt the top of the box projects into a long slanted parallelogram,
whose rectangle was 38 by 24 pixels of solid black around it, so the pins'
card painted 1,368 pixels where its outline holds 645, with 727 of them outside
it. Cut the wrong way the columns painted 1,077 and 436 of them outside; cut
across the width at three pixels a column, 724 and 90; at one pixel, 687 and 58.

`CARD_COLUMN_PX` is how many whole pixels of width one column covers, and 1000
draws the single rectangle of before. A column is another `CARD` command, so
what a face costs follows what it covers: the pin's front face is thirteen
columns and the shelf's ten-pixel cards four. Black is palette entry 9, which the palette dump shows as
`#000000`, and it arrives through the shading table the way the cursor's outline
does, so no palette entry was added and no land colour can move. The board gates were taken with one
column first, which reproduced entry 45's frames byte for byte, `6f3ff69d`
unpinned and `8e9ba88f` pinned, and then with columns: the orbit's frame moved
to `62b662a6`, because the shelf's sixty-four cards are seen at many angles,
with `TRIS` 20609 to 20676 and `PIXELS` 35611 to 35839, while the pinned view,
which opens facing the card, drew the identical frame at `8e9ba88f` and wrote
114 more pixels where columns meet. `CELLS` is unchanged at 18,158.

The columns are the cheap stop before the real thing, and the real thing has a
model now. A textured triangle's command carries three Q4 screen corners, a
tile, and, for each of the tile's u, its v and the reciprocal of the
camera-space depth, the plane the fill interpolates: the value at the first
corner and a step a Q4 unit across and down, which the caller works out because
the fabric has no divider. The fill steps those planes, adds, and writes the
texel the quotient of the first two by the third names, which is what makes the
mapping projective rather than affine. The planes are scaled by twenty bits so
that a card at ten cells has a denominator near a hundred and one at two hundred
cells a denominator above five, and the quotient resolves better than a
sixteenth of a texel at both. `TEX=1` draws a card's faces as two triangles each
from their own four projected corners, and its solid edges as two flat
triangles, so no part of a card is a rectangle any more except the tile itself.

What that measures, at seventy-one degrees of tilt and thirty of yaw, against
the card's true outline of 645 pixels: one rectangle a face painted 885 pixels
with 408 of them outside the outline and 168 of it missed; three-pixel columns
painted the face's 496 art pixels with 64 outside it; the triangles paint 645
with none outside and none missed, and the texel the fill produces sits a mean
0.048 and at most 0.144 texels of 32 from the exact homography, where a column's
rows stepped 3.3 texels at every seam. `TEX=0` is the default and draws the
columns exactly as before, so every card frame CRC on record is untouched: the
board's fabric has no TEX command yet, and `TEX=1` on a board build falls back
to the columns, which is what keeps the gate the board and the twin are compared
on one build. The fabric follows in its own cycle.

One thing the model turned up and does not fix: this projection puts the world's
u on the left of a camera looking along -z with up +y, where a right-handed one
puts it on the right, so the 3D image is left-right mirrored against the world's
own axes. The tile's u therefore runs against the box's u, which is what the
rectangle fill always did and what keeps the art reading the way the user
accepted it. Whether the projection itself should be corrected is its own
question, and every scripted frame would move if it were.

The fabric fills it now. `fpga/raster.sv` takes a thirteen-word textured triangle
-- the opcode and the tile, three Q4 corners, and the nine plane numbers -- and
its fill steps the three planes a pixel at a time, divides u and v by the
interpolated reciprocal of depth over ten quotient bits each, and writes the
texel that names, clamped into the tile. The divides are a restoring divider at
ten clocks a quotient, which makes a textured pixel about twenty-five clocks
against the shaded fill's two; the card's own load pays for that easily, five or
six thousand pixels a frame being about two milliseconds where the fabric is
idle by the time the CPU finishes, and it is what a crowd would feel first. Two
things had to be the same on both sides, and both are written down in two places
because the fabric and the caller cannot share code: the planes are given at the
first pixel of the triangle's clamped bounding box, which `tex_origin` in
terrain.c writes down against the fabric's own S_BOX and S_CLAMP, and the store
needs three clocks, because its address register is itself a register. Three
clocks is entry 37's lesson twice over: at two, each pixel reads the previous
one's texel, which is invisible wherever two pixels share a texel and a mottled
texture everywhere else -- and the emitter's own counters agreed with the twin
throughout, so only the word-for-word frame comparison could see it.

`tests/raster_tb.sv` replays two real frames whose commands carry textured
triangles and requires the fabric's read-back to match `terrain_host` byte for
byte, which it does both for a card alone and for the shelf of sixty-four, and
it still does for the shaded triangles and the cards the columns draw. The
board fills them too: the orbit gate runs the shelf of sixty-four textured
cards on the Tang and matches the twin frame for frame, `TRIS=20734`,
`PIXELS=34677` and frame CRC `5f788c32` with zero late line fetches, and the
user flew the pinned build and called it perfect. `CARD_TEX` is still zero by
default, so a board build draws the columns unless it is asked for the
triangles; flipping that default and retiring the columns, `CARD_COLUMN_PX` and
the `CARD` command is its own small cycle.

The card's size is a knob, `CARD_UNITS` in Q4 and the thickness a tenth of it:
three cells is a small building, and `CARD_UNITS=80` is half a cell, which is
about a villager in the original. At that size, at the pin's own camera twenty
cells back, the card is six pixels across and reads as a black speck -- not
because anything is broken, but because nearest-neighbour sampling at five to
one consults six texels of the tile's 1024 and lands on the near-black
background the creature figure sits on. Four cells back the card is 24 pixels
and the figure is plainly there, and at two cells it is 59 pixels and
unmistakable: the distinct texels a tile can offer saturate at about 24, which
is the art's own palette count and not a sampling limit. So the size reads
correctly at any distance and the *art* is what does not, which is the case for
choosing a card's tile by its screen size.

`tools/measure_tang32.sh` measures what the engine draws. It builds each
configuration and runs it through `run_tang32.sh`, so the board and the twin it
is judged against are always one build, and writes one table of triangles,
pixels, cells, `DRAW`, `MAX`, `PERIOD`, stalls and the frame CRC. Two sweeps,
each on the board: one villager card with the camera at 3200, 1600, 800 and 320
Q4 -- 20, 10, 5 and 2 cells -- and a ladder of villager-sized textured cards at
64, 256, 1,000, 1,500, 2,000 and 3,000. Closing from 20 cells to 2 cuts the
triangles from 2,787 to 1,123 and the frame from 7,606 to 4,391 us while the
pixels rise from 50,630 to 59,430, and the twenty-a-second hold is kept at
every distance. The ladder puts a villager card at 7.9 us -- 5.8 times entry
40's billboard, because a textured face is two triangles at thirteen words
where a card used to be five -- and the pacing wall at about 1,500 cards, where
the worst frame is 48,063 us of the 50,000 the hold allows. A crowd's tempo is
set by emission, so the far level of a level of detail wants to be a *flat*
quad at six words rather than a coarse texture at twenty-six.

One defect is open and is the first thing to pick up. At 2,000 cards and at
3,000 the board stops with `BAD TINYCREATURE PIXELS`: the twin expects
`TRIS=23193 PIXELS=34373` for that configuration and the board draws a
different number of pixels, while 1,500 cards pass. It is a count discrepancy
and not a frame budget, and it has not been reproduced on a second run, so the
first step is fresh data on the same configuration rather than a hypothesis
about the FIFO or the fill.

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

The renderer also draws cards: columns of axis-aligned rectangles, each filled
with one 32 by 32 tile, a face being one rectangle for every `CARD_COLUMN_PX`
pixels of its projected width and never fewer than one. They go to the fabric as a five-word `CARD` command -- the opcode and
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
for word, which needs the unit's whole tile store loaded: the testbench held
four tiles while the art had grown to sixty-four, so every cards-on run of it
from entry 39 read `x` for a card's texels, and the passes recorded since then
were all cards-off runs. On the board the same check passes: the four cards add no triangles,
33158 pixels become 33325, the frame takes 29995 us rather than 29661, `VBLMIN`
and `VBLMAX` are still both 3, and the frame CRC is `0609cd9f` against the host's
`0609cd9f`. The first hardware attempt drew the right number of pixels in the
wrong colours, which is what a card filled from a store the program had never
written looks like; `fabric_tiles` in `main.c` now loads it four bytes a write
before the first frame. The tiles it loads are the converted art when the build
has them: `TILES=1` runs `tools/convert_tiles.py` over Meph's sheet and the
header it writes names the tiles, the transparent key at entry 192 and the
art's sixty-three colours at 193 to 255, while a build without the art still
draws four synthetic tiles so the path can
be exercised with nothing fetched. The unit's store holds sixty-four tiles and
Meph's sheet has 255, so the header takes the first sixty-four of them. What a
card costs is measured rather than projected: with 64, 100, 500, 1,000 and
2,000 of them standing on the island the frame takes 30.0, 30.3, 31.0, 31.7 and
32.7 ms, which is 1.36 us a card, the worst frame goes from 36.0 to 37.8 ms,
the period stays at 50.00 ms, and every rung still matches the twin on the
frame CRC. What grows faster than the count is the fill: the CPU's stalls on a
full FIFO climb from 15,000 to 92,000 bus cycles a frame, so at some point the
fabric's filling, not the CPU's sending, is what limits a crowd. Ten thousand
cards would be 13.6 ms of sending and about 12 ms of filling, which puts the
wall near there -- extrapolated, not measured. The count is `TC_CARDS_N`, and
one a tile is the default shelf. With the textured cutout cards the current
binary draws, the ladder is dearer and the ceiling lower: 64 cards draw
32.97 ms, 1000 draw 43.40 ms and 1500 draw 47.19 ms, where a worst frame of
51.76 ms no longer fits the three-blank hold and the period rises to 55.08 ms;
2000 draw 50.61 ms at 16.6 fps and 3000 draw 57.23 ms at 15.4 fps. The
marginal cost falls from 14.9 to 6.4 us a card over that range because the
grid widens with the count and most added cards fall outside the view, so this
measures a spreading crowd rather than a densifying one.

The art's transparent texels are holes now. Palette-relative texel 0 is the
key: `tools/convert_tiles.py` fits the art into the 63 colours beside it in
entries 193 to 255, the host twin skips a key texel in both card fills, and
`fpga/raster.sv` gates the write and the pixel count on it in `S_CARD` and
`S_TEXW`. `CARD_EDGE=0`, the new default, drops the four solid near-black sides
of the card box, so a cutout card is its art's silhouette with only the face
toward the camera drawn; `CARD_EDGE=1` restores the box. The animal icons are
the cards this actually cuts out. Meph's tree sheet divides in two: rows 0 to
5 are the trunk and fork parts the four-level stack draws, and they are fully
opaque; rows 6 to 8 are 43 whole plant sprites whose own alpha, duplicated in
`-bg`, is a real silhouette. `TREE_WHOLE=1` builds from those cells and draws
each plant as one card at `CARD_UNITS=320`; the user recognised the sprites as
fruit, and the parts stack remains the default. The core this first runs on is seed
13, 75.06 MHz on the bus and 101.63 MHz on the pixel clock, published after
`patches/tinynes-tang32.patch` admitted `SPINE19` beside `SPINE26` in the pixel
clock's bridge check: TinyTang's TOOL-021 found those spines dead only because
apicula tied their select ports to VCC, and its accepted open-flow desktop core
clocks 74.25 MHz through the same `SPINE18` entry and the same `SPINE19` and
`SPINE26` bridge set. `SPINE27` remains refused. The user flew the 256-card
animal build, reported the transparency perfect, and preferred the flat cards
with the texture visible from either side to the box cards they replace.

Plants now come from the game rather than a fixed grid.
`tools/convert_plants.py` reads the level script's `CREATE_NEW_TREE` and
`CREATE_DEAD_TREE` commands, keeps each position, rotation and scale, and
converts the position into the land grid with the same `.lnd` block origin
`convert_land.py` uses; `PLANTS=1` compiles the table in, one card a plant,
sorted by cell so the walk finds a cell's plants with a binary search, and
`PLANT_UNITS` (default 160 Q4 at scale 1.0) sets the card's size. Land 1 gives
1,398 plants across 16 types, 3.7 to 30 units, at the rotations and scales the
original states. The board and host matched at CRC `05319cf9` with 2,071 plant
triangles visible, `DRAW=51014us` and a 60.2 ms period in the scripted orbit.
Two faults were caught before it flew: the board's tile store was uploaded only
for cards and trees, and the first table kept absolute script coordinates,
which put every plant in the ocean.

The art is Meph's plants sheet now. Of its 16 by 16 cells only 77 are cutout
sprites -- rows 2, 3, 6, 9 and 12; row 0 is nearly full tiles and the rest are
solid ground. `tools/make_plant_sheet.py` ranks those by excess green, keeps
the 16 greenest, and lays them in a 4 by 4 sheet, and the script's 16 tree
types map one-to-one onto the tiles in type order, so each species keeps its
plant. Every card's base sits a quarter of its height below the ground so the
sprite reads as rooted. The board and host matched at CRC `319d2c52` with
`PIXELS=34638`, `DRAW=51041us` and a 60.3 ms period. Every non-terrain card
is now one size: 80 Q4, half a cell, the villager height this project has
used since entry 51. A one-tile plant is exactly that card, whatever the
script's scale said; a tree is the 3 by 3 picture of five cards -- 23 | 3 | 23,
then 17, then 1 -- at the same 80 Q4 each, so a tree is three bush heights
tall and wide. The five tree cells live at tiles 16 to 19 in the plant sheet,
taken from `_Meph_trees.png`, and the per-type stretch is gone. That build
matched at CRC `ab321e0c` with `TRIS=21957`, `PIXELS=33509`, `DRAW=49499us`
and a 59.5 ms period. The middle-drag pitch is inverted at the user's request:
dragging up now tilts the other way, and the other camera paths are unchanged.

Plants now carry random rotations. `convert_plants.py --random-rotation
--seed 1` replaces each script rotation with a uniform random yaw, deterministic
for the seed, so the same island and seed give the same table. Big forests are
not drawn as anything of their own: all 1,405 of Celtic's trees are plants,
including the 833 the script places inside its 88 `CREATE_NEW_BIG_FOREST`
commands, and no canopy card, canopy mesh or raised mound is drawn. Three
forest treatments were tried and rejected -- flat canopy cards read as roof
tiles, a raised terrain mound read as a stain on the land, and a five-shell
canopy mesh in the shape of openblack's `FeatureForest` models clashed with the
terrain -- so the accepted build is the plain one: CRC `73f24771`,
`TRIS=28606`, `PIXELS=35569`, `DRAW=76990us`, `MAX=84370us`, an 82.6 ms period
and `LATE=0`. `convert_land.py --forests` still raises a cosine mound at each
forest when asked, but no build uses it.

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

The Celtic build changed the answer, and a `TC_PHASE_DETAIL` build measured it:
the same walk, timing one cell in 64 and reporting the sample scaled to a frame.
It put a mean 92.4 ms period at `PLANT=45856us SUB=21049us VERT=10241us
CELL=4824us SPRITE=247us`, with the fill's own triangle call inside `SUB` at
`EMIT=1672us`. The instrumented frame is about six per cent slower than the
plain one, so the shares matter more than the absolute numbers. The plants are
56 per cent of the frame: 953 five-card trees and 452 bushes, 5,217 cards at
8.8 us each, which is the villager-card price the ladder measured. The terrain
walk is 36 ms, of which `submit()` timed 21 ms and the fill's triangle call
1.7 ms. That last figure was wrong about the words: a posted write's cost lands
on whatever bus access comes after it, often a cache refill inside `vertex()`
or `submit()`, so the sample charged the words to their neighbours. Throwing
the words away measured them instead -- the same plain Celtic build drew in
77.1 ms, 65.1 ms without the terrain's words, 67.0 ms without the plants',
55.0 ms without any, and 66.1 ms keeping the words but skipping the plants'
plane divides -- so the command words are 22 ms of the frame and the plants'
setup divides 11 ms, which is what the vertex store below was built against.
`PHASE_DETAIL=0` is the default, so the plain build is unchanged.

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

### Setup beside the fill

The unit is two engines now. Setup takes commands -- the vertex store's
writes and reads, a triangle's box, edge functions and palette walk, a TEXV
triangle's planes -- and hands each finished triangle, run of rows or card to
the fill, which draws it while setup works out the next; the hand-over is one
clock, when setup holds a command and the fill is free. Before, one engine did
both in turn, and the island's triangles are a few pixels each, so the fill
sat idle through every setup. The command assembler reads a command's length
off its first word as it arrives and so takes one word a clock, and writes a
shaded vertex into the store itself unless setup is reading slots or finishing
a textured vertex; the textured vertex's three divides and TEXV's six take two
quotient bits a clock; the palette walk runs during the box and edge states;
and the edge products start at the highest radix-4 digit their offsets need.
None of it moves a pixel. In simulation, with the commands fed at the bus's
pace, two Celtic frames fell from 1.62 and 1.80 million bus cycles to 0.89 and
0.97 million, and on the board the BUSY register, at `0x3c`, puts the fabric's
own work at 14.3 ms of a 60.9 ms frame, which the run line reports as
`FABRIC=`: the CPU sets the pace with room to spare, which is what a fabric
terrain walker needs before it can take the CPU's 32 ms of terrain.

### The vertex store

The fabric also keeps a store of 1024 vertices, so a triangle of any shape is
sent as its corners once and then one word. `VTX` writes a shaded vertex -- a
slot, a Q4 screen corner and a palette entry -- in two words; `VTXT` a
textured one -- a slot, the corner, a tile, the tile's u and v at that corner
in Q4 texels and the camera-space depth -- in three, and the store divides out
the corner's three plane values, `(u << 20) / z`, `(v << 20) / z` and
`(1 << 20) / z`. `TRIV` and `TEXV` are one word each, three ten-bit slots, and
draw the shaded or textured triangle of those vertices. For `TEXV` the fabric
works out the nine plane numbers a `TEX` command carries by the arithmetic
`tex_plane` in `terrain.c` does: four products a plane, two truncating
divides by the triangle's determinant, which is minus the edge functions' sum
the setup already has, and the origin products kept to their low 32 bits as
the C keeps them. So it draws the `TEX` the program would have sent, to the
bit, and the board's frames did not move when the store went in. Commands run
in order, so a slot can be written again as soon as the triangles naming it
have been sent.

The land's vertices are keyed to slots by the z front of the walk their row was
reached from, the row's parity and the column modulo 256, so a cell's three
corners never share a slot and the walk reuses the corners it sent for the cell
beside it and the row before; Celtic sends about 0.7 vertices a triangle, three
words where the whole triangle took four. A card face is four textured
vertices and two `TEXV`s, fourteen words where two `TEX`es took twenty-six,
and the CPU no longer divides for it at all. A frame's words fell to between
0.56 and 0.60 of what they were, and the Celtic baseline went from a 77.1 ms
draw and an 82.7 ms period to 61.7 ms and 67.5 ms with the frame CRC unchanged
at `73f24771`; the phase build put the plants at 29.7 ms against 45.9 ms and
`submit()` at 18.2 ms against 21.0 ms. A target without the store's two
functions is sent whole triangles as before, which `TC_NO_STORE=1` asks of
`terrain_host` and which draws the same frames. The setup cost timing: one of
eight seeds, seed 3, closed the 75 MHz bus, at 76.65 MHz.

### The depth buffer

The source and the board now carry a depth buffer. A stored triangle carries
a plane of its corners' depth, D = (1 << 30) / z -- the same reciprocal the
projection takes -- worked out by `tex_plane`'s arithmetic, and a pixel it
covers is written only when D >> 6, held to 18 bits, is no less than the
buffer's; a tie goes to the later triangle, so the walk's painter order still
decides ties. Rows clear the buffer as they fill; whole triangles, cards and
transparent texels test and write nothing. A shaded vertex brings its D as a
third `VTX` word and the store divides a textured one's out of its z; the
store is 144 bits wide for it and the buffer is 57,600 18-bit values. The twin
draws the Celtic baseline at CRC `44f4ef06`, 181 pixels a frame fewer than
without depth, most of them plants' sunk bases now behind the terrain, and the
simulation matches it on seven configurations. Plane setup for every stored
triangle took a Celtic frame from 0.89 to 1.35 million fabric cycles after its
multiplies and divides were cut to the digits they need. The core places once
the command assembler reads each word's last-word flag from the FIFO beside
it, written as the CPU pushes the command, instead of decoding a length and
comparing it on the block RAM's output: seed 7 closed the 75 MHz bus at
75.27 MHz and the 74.25 MHz pixel clock at 92.00 MHz, the only one of eight
seeds to pass every gate, and the core uses 223 of 340 block RAMs. The board
ran the Celtic scene on seed 7's `ae350_soc.bin`, SHA-256
`96af99100554022831f24b0f711f7cb5105afb97dcc7be33b0d4c2fc86d2555a`, drew the
plants' sunk bases behind the terrain, and the user passed it.

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
