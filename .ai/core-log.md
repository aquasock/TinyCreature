## 1 COMMIT Unreleased 2026-10-14T21:50:50-07:00

#### Coming From:

None.

#### Purpose:

Start the TinyCreature repository, the user's new project to run Black & White on the Tang through openblack on the AE350 and an FPGA renderer, with its project-control files, licence and README.

#### Outcome:

After closing TinyNES at its entry 39, the user asked whether the FPGA and the AE350 could run Black & White's 3D world. The agent judged the A25's 750 MHz and FPU to be in the class of the game's 350 MHz Pentium II minimum, an FPGA rasterizer of the fill rate the game targeted to be credible from Rasterix's reported 100 Mpixel/s at 100 MHz (GFX-001), and memory and asset bandwidth to be the limits: the dock's 32 MB SDRAM against the game's 64 MB and 8 MB of graphics memory (GAME-001), no open-flow controller yet for the module's 1 GiB DDR3, and the 2 Mbaud link from the card. It proposed porting openblack rather than writing the game, and from a shallow clone at `a243c6b` found it GPL-3.0, C++23, about 47,000 lines, starting no threads of its own and drawing through bgfx with ten game shader programs, of which the terrain's takes up to nine texture samples a pixel (OB-001, OB-002). The user chose the name TinyCreature over the agent's other suggestions and created `aquasock/TinyCreature`, public and empty, and chose that `.ai/core.md` be copied from TinyNES unchanged and that the whole repository be GPL-3.0. `.ai/core.md` is therefore byte-identical to TinyNES's at `f5011dd`, so its Purpose and repository lines still describe TinyNES until the user edits them; `.ai/core-syntax.md` is copied unchanged; `.ai/core-bootstrap.md` points at this repository; `.ai/core-reference.md` is new, keeping TinyNES's rules and template, citing TinyNES's and TinyTang's references for board facts rather than copying them, and holding the four records looked up today. `LICENSE` is the FSF's current GPL-3.0 text, SHA-256 `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`, taken from the system's copy rather than openblack's older one with `http://` addresses. The README states the aim, what the project builds on, what it needs first and that game data is never included. Nothing was built or deployed; the user is gathering their copy of the game's files. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` contents, confirmed `.ai/core.md` is the user's chosen unchanged copy and not an edit, and validated this entry's six sections, numbering from 1, prose, Status values and the 100-entry limit.

#### Next Steps:

The user should edit `.ai/core.md`'s Purpose and repository lines, which still describe TinyNES. The first engineering cycle, to be proposed for approval, is a PC build of openblack in a configuration like the Tang's, single-threaded, without imgui and with a software renderer that does only what a two-texture fixed-function pipeline could, run on the user's game files to measure memory, data size and per-frame CPU work; the open-flow DDR3 controller and the asset path from the card follow from what it shows.

#### Files Modified:

- .gitignore
- LICENSE
- README.md

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 2 COMMIT Unreleased 2026-10-14T22:10:50-07:00

#### Coming From:

Unreleased 27f5205

#### Purpose:

Build openblack on this PC and run it on the user's own Black & White, as the user approved as the first cycle, to see how complete the engine is, and record a handoff so the next agent starts from the project's records.

#### Outcome:

The user corrected the agent's earlier figure for the dock's SDRAM: the J9 module holds two 32 MB W9825G6KH-6, 64 MB, of which TinyNES drives one on its single chip select, the second's select pin never found (TinyNES BRD-010 and its entry 8); both share one 16-bit bus, so the second doubles space and not speed. On that basis the user chose to attempt the port without DDR3, with a faster SDRAM controller and a tile-based renderer that keeps depth and colour in block RAM, DDR3 kept in reserve. The user installed Wine 10.0 with its 32-bit half and the development packages vcpkg needs, from commands the agent gave. The new `tools/fetch_openblack.sh` fetches openblack at `a243c6b2fbd251b5d54c1b5f09f59ded9b3b4c81` with its vcpkg submodule at `5de6d1ff` into the git-ignored `third_party/openblack`, after a first run failed because the agent had guessed the short hash's eighth character; `cmake --preset ninja-multi-vcpkg` with the build tree in `build/openblack` built every dependency and openblack, 182 of 182 steps, leaving the fetched tree clean. The user's `/home/vash/Downloads/Black and White/` holds the game and Creature Isle as ISOs and the patch installers with an `info.txt` of serials and install order. pycdlib refused the game ISO because its volume descriptors disagree, so it was attached read-only with `udisksctl` and detached afterwards; the installer and official patches 1.1 and 1.2 ran under Wine in a prefix at `build/wineprefix`, kept apart from `~/.wine`, with the user clicking through each, and file change times show patch 1.1 writing 3 files and 1.2 writing 41, `Scripts/info.dat` and `Scripts/Land1.txt` among them, the community patches being left out as openblack does not need them. Run by the agent as `openblack -g <install> -V`, openblack opened a 1280 by 1024 window, loaded Land 1, and the user found the landscape perfect and the camera working but no villagers or creature, which the user described as a perfect, empty land and accepted as everything the project needs from the engine for now. The log lists eight unimplemented script functions, led by `CreatePlannedAbode` with 86 calls and including `CreateTownVillager`, which is the lead for the missing villagers; ALSA could not open the sound device. After 4 minutes 22 seconds the process had used 72 seconds of CPU with vsync on and peaked at 591,836 kB resident, including the OpenGL driver, and the game's `Data` and `Scripts` are 241 MB with `Audio` 221 MB more (OB-003). The game was still running when this entry was written. The build products, the Wine prefix with the installed game, which is copyrighted, and the run logs are all under the git-ignored `build/` and are never committed. OB-001 is now VERIFIED and OB-003 is new, and the README describes the PC build. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed and no settled log entry was rewritten, checked that the reference's records and fast index list the same ids in the same order, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

`.ai/core.md` is still TinyNES's unchanged, so its Purpose and repository lines describe TinyNES until the user edits them. This cycle's measurement is not finished: separate openblack's own memory from the OpenGL driver's, for example by counting its allocations or with Valgrind's massif, measure CPU work per frame with vsync off over a fixed number of frames (`-n`), and try the Tang-like configuration, single-threaded, without imgui and with a renderer limited to what two texture units can do. The result decides whether 64 MB of SDRAM is enough; then the second chip select and a faster SDRAM controller are the first hardware work, with DDR3 in reserve. Implementing the missing town functions, starting with `CreatePlannedAbode` and `CreateTownVillager`, would bring villagers back, and the user has not yet said whether that is wanted before the port.

#### Files Modified:

- README.md
- tools/fetch_openblack.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: PASS

---
