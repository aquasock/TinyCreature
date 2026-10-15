# TinyCreature

TinyCreature aims to run Black & White (Lionhead, 2001) on the Sipeed Tang
Console 138K, as a core for TinyTang: the game's engine from
[openblack](https://github.com/openblack/openblack), an open-source
reimplementation, running on the FPGA's AE350 RISC-V processor, with a 3D
renderer built in the FPGA's fabric.

**Status: a stripped openblack landscape playground builds and runs on a PC**
with the game's files (below). It retains the complete world, renders it at 320
by 180 in a retro pixel style, and has a 75.7 MiB headless startup peak. Nothing
runs on the Tang yet.

## openblack on a PC

The landscape playground keeps each original world's dimensions, terrain,
materials, sky, water and camera coordinates. It skips the quest scripts,
audio, entities, vegetation, sprites, footpaths, terrain collision meshes and
the debug GUI runtime. It replaces the 1024 by 1024 reflection and full-island
footprint buffers with one-pixel placeholders. Its launcher renders at 320 by
180, scales that image to a 640 by 360 window with nearest-neighbour sampling,
and caps the playground at 30 frames per second with reduced process priority.

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
the 30 FPS cap, used 9% CPU and peaked at 215.47 MiB RSS on this PC. Its Noop
startup peak is 75.68 MiB, down from 85.70 MiB for the first stripped build and
360.76 MiB for unmodified openblack. The FPGA renderer can replace the PC's
Vulkan driver and video buffers, but the remaining CPU-side peak is still about
11.7 MiB above the fitted 64 MiB SDRAM capacity.

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
  peak is 75.7 MiB, so the 64 MiB design still needs bounded terrain staging,
  more compact runtime data, or access to the second chip. The module's 1 GiB
  DDR3 remains a direct alternative, but it has no open-flow controller yet.
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
