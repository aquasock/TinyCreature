# TinyCreature

TinyCreature aims to run Black & White (Lionhead, 2001) on the Sipeed Tang
Console 138K, as a core for TinyTang: the game's engine from
[openblack](https://github.com/openblack/openblack), an open-source
reimplementation, running on the FPGA's AE350 RISC-V processor, with a 3D
renderer built in the FPGA's fabric.

**Status: openblack builds and runs on a PC with the game's files** (below);
nothing runs on the Tang yet. The project starts by measuring what the game
asks of the hardware, before any FPGA work.

## openblack on a PC

```sh
tools/fetch_openblack.sh      # openblack at a pinned commit, with its vcpkg
cmake -S third_party/openblack -B build/openblack --preset ninja-multi-vcpkg
cmake --build build/openblack --config Release
build/openblack/bin/Release/openblack -g "<install>/Black & White" -V
```

`<install>` is the game installed and patched to 1.2: openblack reads its
`Data` and `Scripts` folders. On Linux the installer and patches 1.1 and 1.2
run under Wine; a prefix of its own, inside `build/`, keeps it apart from
`~/.wine`. On the user's copy the landscape draws correctly, while villagers
and the creature are missing and the log lists script functions openblack has
not implemented yet.

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

- Memory: the game wants about 64 MB plus graphics memory, more than the
  dock's 32 MB SDRAM, so the module's 1 GiB DDR3 is needed, and there is no
  open-flow DDR3 controller for it yet.
- A renderer: a fixed-function rasterizer in the FPGA, with vertex work on the
  AE350.
- A way to bring hundreds of megabytes of game data from the card faster than
  the 2 Mbaud link TinyNES uses.

## Game data

The game's assets are not part of this repository and never will be. You
extract them from your own copy of Black & White, as openblack describes.

## Licence

GPL-3.0 (`LICENSE`), the whole repository, matching openblack.
