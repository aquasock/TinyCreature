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

## 3 COMMIT Unreleased 2026-10-14T22:25:40-07:00

#### Coming From:

Unreleased 4dbfd84

#### Purpose:

Measure openblack's repeatable CPU and memory cost, determine whether the current engine can fit the fitted SDRAM, and audit the changes needed for a single-threaded build without ImGui.

#### Outcome:

The new deterministic `tools/profile_openblack.sh` ran openblack `a243c6b2` at 1280 by 720 with logging off and null audio through three repetitions of startup, 3,601-frame no-vsync, and 601-frame realtime cases, all 15 cases passing against executable SHA-256 `45436b81416408ae7f3b5c7563f62ba27c9d982f0927d9be1d35d5a7b45b18b2`. Noop averaged 360.76 MiB peak RSS, 357.08 MiB sampled peak PSS, 356.70 MiB sampled peak private memory and four threads; Vulkan averaged 531.87 MiB RSS, 487.30 MiB PSS, 463.33 MiB private memory and ten threads. Vulkan's no-vsync cases averaged 0.861 ms of CPU per frame, while its realtime cases had a median 14.45 ms per frame including driver and render-thread work; Noop's fast loop did not advance normal 100 ms game turns, so it does not measure gameplay simulation cost. The headless result rules out moving the current engine directly into 64 MiB, although allocation ownership still has to show whether asset streaming and compact formats can close the gap. The source audit found that the target bgfx dependency can become single-threaded by dropping its target-side `multithreaded` vcpkg feature, while a clean GUI-free build needs a no-op `DebugGuiInterface` plus conditional omission of the Debug sources, ImGui shaders, package and `imgui_user`; openblack's own engine and component sources create no C++ threads. The README now records the profile and corrects the J9 module description, OB-003 replaces the earlier one-run figure and corrects Vulkan previously being called OpenGL, and GAME-001 now distinguishes the two physical 32 MiB chips from the one currently addressable. The existing Release build completed, the profiling script passed syntax, usage, full-run and worktree-cleanliness checks, no Tang artifact applied to this diagnostic cycle, and the required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, and validated the reference edits and this entry's six sections, numbering, prose, Status values and 100-entry limit.

#### Next Steps:

Instrument the Noop path by allocation owner and retained asset class to explain its roughly 357 MiB private footprint, then decide whether a bounded asset cache and compact runtime formats make the 64 MiB SDRAM design credible or whether the open-flow DDR3 controller must precede the port; per-stage and per-turn timing must also separate engine work from Vulkan and bgfx before using the PC CPU result to budget the AE350.

#### Files Modified:

- README.md
- tools/profile_openblack.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 4 COMMIT Unreleased 2026-10-14T22:44:18-07:00

#### Coming From:

Unreleased 45cf7d6

#### Purpose:

Replace the proposed full-engine recreation with a low-resolution PC landscape playground that preserves the scale of Black & White's worlds while removing systems and effects that are unnecessary for exploring them.

#### Outcome:

The reproducible `tools/build_openblack_playground.sh` now makes an isolated build from pinned openblack `a243c6b2` and applies `patches/openblack-playground.patch`, while `tools/run_openblack_playground.sh` launches it at 640 by 360 and finds the repository's local Wine install automatically. Playground mode retains the complete `.lnd` terrain, its materials, sky, simplified water, original coordinates and camera, while omitting bulk meshes, animations, sounds, entities, vegetation, sprites, footpaths and challenge logic; it also suppresses reflection and footprint passes and replaces their large buffers with one-pixel placeholders. The Release build completed, a two-frame Noop smoke test loaded Land 1, and an eight-frame Vulkan test produced a correct 640 by 360 screenshot before the interactive build was launched. The user explored that build and reported that it looked fantastic. After about three minutes the live process measured 228.29 MiB RSS, 181.91 MiB PSS and 157.95 MiB private memory with eight threads, reducing private memory by 305.38 MiB, or 65.9%, from the earlier full Vulkan profile while remaining about 2.5 times the 64 MiB target. No Tang artifact applied to this PC cycle, and the required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged and settled entries untouched, and validated this entry's six sections, sequential numbering, prose, Status values and 100-entry limit.

#### Next Steps:

Profile the remaining roughly 158 MiB by allocation and resource owner, then remove or compact the largest owners while repeatedly checking that the full landscape scale, terrain appearance and camera remain intact; use that evidence to decide whether the 64 MiB SDRAM target is credible before starting Tang renderer work.

#### Files Modified:

- .gitignore
- README.md
- patches/openblack-playground.patch
- tools/build_openblack_playground.sh
- tools/run_openblack_playground.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: PASS

---

## 5 COMMIT Unreleased 2026-10-14T23:17:10-07:00

#### Coming From:

Unreleased f8dcf12

#### Purpose:

Reduce the accepted landscape playground further and use a retro pixel presentation to preserve the worlds' scale while making lower rendering resolution visually intentional.

#### Outcome:

The incremental `patches/openblack-playground-retro.patch` makes the playground render the full world at 320 by 180 into an offscreen buffer and upscale it to the 640 by 360 window with nearest-neighbour sampling, substitutes a no-op debug GUI, omits the terrain's Bullet collision meshes, and flushes terrain uploads in bounded batches while retaining terrain-derived camera height. The build and launcher now apply both patches reproducibly, accept `OPENBLACK_PIXEL_SCALE`, and run at lower scheduling priority. The first interactive revision rendered correctly but drove one CPU core at roughly 86%, making the PC lag; a 30 FPS playground cap corrected the regression, and the final 300-frame Vulkan validation completed in 10.72 seconds at 9% CPU with a 215.47 MiB RSS peak. The two-frame Noop startup test exited cleanly with a 75.68 MiB RSS peak, down 10.02 MiB from the first stripped build, and an AddressSanitizer Noop smoke test found no error after the offscreen framebuffer was explicitly destroyed before bgfx shutdown. Sequential application of both patches reproduced the tested source byte for byte, the Release rebuild passed, and the user retested movement and presentation and reported that it looked great. No Tang artifact applied to this PC cycle. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` and settled entries unchanged, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

Profile the owners of the remaining 75.7 MiB headless startup peak and remove or stream at least another 11.7 MiB without changing the accepted world scale and retro presentation, then use the reduced software budget to define the first fixed-function FPGA rendering path and its SDRAM interface.

#### Files Modified:

- README.md
- patches/openblack-playground-retro.patch
- tools/build_openblack_playground.sh
- tools/run_openblack_playground.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: PASS

---

## 6 COMMIT Unreleased 2026-10-14T23:34:09-07:00

#### Coming From:

Unreleased d1df05e

#### Purpose:

Remove the landscape playground's unused dense entity spatial map and determine whether the resulting CPU-side memory footprint fits within the full 64 MiB SDRAM module.

#### Outcome:

Heap profiling identified `MapProduction` as the largest target-relevant allocation: two 512 by 512 arrays of empty `std::unordered_set` objects occupy 28.0 MiB even though playground mode loads no fixed or mobile entities. The new incremental `patches/openblack-playground-memory.patch` substitutes a `MapPlayground` implementation whose spatial queries return one empty set and whose rebuild is a no-op, leaving normal openblack behavior unchanged outside playground mode. Three Release Noop runs peaked at 46.77, 47.27 and 47.66 MiB RSS, a 47.23 MiB mean that removes 28.45 MiB from the prior 75.68 MiB result and leaves 16.8 MiB beneath the full 64 MiB module capacity. The interactive Vulkan process measured 190.74 MiB RSS, 133.55 MiB PSS and 114.36 MiB private memory at 7.2% CPU; the user tested movement, zoom, rotation and presentation and reported that it worked perfectly. The Release build, AddressSanitizer Noop smoke test, shell syntax check and byte-for-byte three-patch source replay passed. No Tang artifact applied to this PC cycle. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` and settled entries unchanged, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

Remove the unused approximately 4.4 MiB Bullet world from playground mode and bound or stream terrain staging to protect the remaining SDRAM margin, then define and measure the AE350-facing interface for the first fixed-function FPGA renderer.

#### Files Modified:

- README.md
- patches/openblack-playground-memory.patch
- tools/build_openblack_playground.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: PASS

---

## 7 COMMIT Unreleased 2026-10-15T01:53:34-07:00

#### Coming From:

Unreleased 4e6e63d

#### Purpose:

Build and prove the first 32 MiB Tang target as a small retro playground foundation, while keeping a separate J10 SDRAM bank as the later path to 64 MiB.

#### Outcome:

The reproducible Tang32 flow pins TinyNES at f5011dd374cfc65f4f17616fec97c903a66b6cc8 and applies patches/tinynes-tang32.patch, retaining its proven AE350, J9 SDRAM, UART loader and 720p HDMI path while omitting the NES desk, audio and controller blocks. The target displays two indexed 320 by 180 framebuffers at exact 4x scaling from the top 256 KiB of SDRAM and leaves a 31.75 MiB application link region; its 47,636-byte test application draws and flips an animated retro landscape. Two seed-11 builds reproduced .fs SHA-256 70bf0f4d08658fbb7ffc3366b8003a68339c501807fddb7763ed90d9fa9a6b7a and .bin SHA-256 fc288166f61cca77be910151220be6448eeb7db7f633e4330d61918064385ff9, closing the 75 MHz bus at 82.41 MHz and the 74.25 MHz pixel clock at 100.92 MHz; the full-line framebuffer simulation and timing-checking SDRAM simulation passed. The two-wire runner uploaded the image, waited through tangload, and loaded the application at 184.7 KB/s after its first revision exposed and then fixed a prompt-wait race. On the board the boot ROM reported TinyNES SDRAM OK 32M, and the application reported TinyCreature TANG32 OK RAM=32MiB VIDEO=320x180 SCALE=4 FRAMES=600 PERIOD=16664us VBL=601 LATE=0 before exiting cleanly. The user saw a nice 2D picture with moving graphics and marked the result pass. The core-syntax audit re-read .ai/core.md and .ai/core-syntax.md, inspected the complete .ai/ diff, confirmed .ai/core.md and settled entries unchanged, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

Use the proven 320 by 180 indexed display and bounded SDRAM layout as the first interface for terrain staging and rendering within the current 32 MiB bank, then add a second independent 32 MiB controller on J10 when its SDRAM module is installed and preserve the current J9 map as bank zero.

#### Files Modified:

- README.md
- THIRD_PARTY.md
- patches/tinynes-tang32.patch
- tests/tang32_sdram_video_tb.sv
- tests/tang32_video_tb.sv
- tools/build_tang32.sh
- tools/fetch_tang32.sh
- tools/run_tang32.sh
- tools/test_tang32_video.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 8 COMMIT Unreleased 2026-10-15T02:19:22-07:00

#### Coming From:

Unreleased 35b2bc7

#### Purpose:

Draw the user's real Land 1 terrain on the proven Tang32 320 by 180 display from the AE350, through a triangle submission boundary a fabric rasterizer can later take over, and measure the software baseline.

#### Outcome:

The new `tools/convert_land.py` reads a `.lnd` file by openblack's layout (OB-004) and writes a TCL1 file under the git-ignored `build/land/`. Each vertex gets the daylight colour openblack's terrain shader would give it, from material means, noise, bump-map mean and luminosity. Each triangle takes the mean of its three vertices, and the results are fitted to 239 palette entries by deterministic median cut. Land 1 becomes 224 by 208 cells, 42,147 drawable triangles and 187,789 bytes with CRC-32 `ed38589d`. A first conversion treated cells outside the blocks as dry land and drew slivers along the outer block edges until it followed openblack's fullWater `k_EmptyCell`. The new `firmware/terrain/` program, built with the pinned TinyNES runtime and its boot ROM receiver, requests the file with a WANT line and orbits the island once over 600 frames. Using integer arithmetic only, it culls blocks against the view, walks cells back to front, sends each triangle through one `submit()` call that culls back faces and clips at the near plane, and fills flat-coloured spans into the two framebuffers. The approved plan named Gouraud shading, but an 8-bit indexed framebuffer makes flat colour the practical form, which the user accepted. The same source builds as `terrain_host` on the PC, where it ran clean under AddressSanitizer and UndefinedBehaviorSanitizer after one undefined left shift of a negative value was replaced. `tools/build_tang32.sh` now builds both programs, and `tools/run_tang32.sh terrain` converts the land, runs the PC twin and fails unless the board's land CRC, triangle and pixel means and frame CRC match it. The rebuilt core reproduced entry 7's `.fs` SHA-256 `70bf0f4d08658fbb7ffc3366b8003a68339c501807fddb7763ed90d9fa9a6b7a` and `.bin` SHA-256 `fc288166f61cca77be910151220be6448eeb7db7f633e4330d61918064385ff9` with unchanged 82.41 and 100.92 MHz timing. The first deployment attempt stopped untouched because TinyTang's console was passing through a running TinyNES game, and it went ahead once the user freed the board. Over two-wire, `terrain.elf` SHA-256 `acbfd0fa3280604205aa466a11d6e50a07a409f1b1b6db82c66f74f650c07927` loaded at 185.3 KB/s and the land file in 1.01 s. The board reported TinyCreature TERRAIN OK LAND=ed38589d FRAMES=600 TRIS=19218 PIXELS=32505 DRAW=38097us MAX=42794us PERIOD=50004us VBL=1801 LATE=0 CRC=859df765, matching the PC frame for frame, and the user found the result perfect and marked it pass. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` and settled entries unchanged, checked that the reference's fast index and records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The AE350 software path takes a mean 38.1 ms per frame and shows 20 frames per second, so the next work is either material textures on the terrain, about 1.8 MiB for Land 1, or the first fabric rasterizer behind `submit()`, which must beat that baseline using the same back-to-front triangle stream and indexed framebuffers. The unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/Makefile
- firmware/terrain/host.c
- firmware/terrain/main.c
- firmware/terrain/terrain.c
- firmware/terrain/terrain.h
- tools/build_tang32.sh
- tools/convert_land.py
- tools/run_tang32.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 9 COMMIT Unreleased 2026-10-15T03:30:50-07:00

#### Coming From:

Unreleased e1d7870

#### Purpose:

Move the terrain's triangle fill into a first fabric rasterizer behind `submit()` and measure whether it beats the AE350's 38.1 ms software baseline.

#### Outcome:

The new `fpga/raster.sv`, read into the pinned TinyNES build through a `TINY_NES_EXTRA_SV` hook in `patches/tinynes-tang32.patch`, takes `ROWS` and `TRI` commands through a 512-word FIFO at `0xe8018000`. That address is in the upper half of the video unit's window, chosen because no record shows that `0xe8020000` reaches the fabric (AE-001). The unit sets up each triangle's edge functions with a sequential radix-4 multiplier, because Yosys infers no DSP blocks for GW5A (TOOL-001). It fills pixel centres over the clamped bounding box at one a clock into two 320 by 180 buffers of 58 single-clock DPX9B blocks, which the video unit shows through the SDRAM's line-fetch handshake, latched per fetch in `ae350_soc.sv`, and which the CPU reads back through two registers. The build script's one-clock and 9-bit block RAM checks now cover the `raster.` cells. `terrain.c` now sends frames to a target, with `tc_soft` as the rasterizer's exact model. Its fill rule changed from scanlines to edge functions, the CPU culls triangles whose box holds no pixel centre, rare triangles beyond a 2000-pixel guard band are clipped first, and the expected frame CRC moved from `859df765` to `4a893c8b`. The new `tests/raster_tb.sv`, run by `tools/test_tang32_raster.sh`, pushes two real Land 1 frames' commands through the unit over the bus and passed byte for byte through read-back and line fetch, after it exposed a FIFO read that lagged its pointer and an X from a never-evaluated `always @(*)`. The first build at seed 11 failed with the bus clock at 68.34 MHz on a single-cycle bounding-box path of 14.63 ns. That box was split over three cycles, and at the user's direction `tools/build_tang32.sh` now synthesises once and routes seeds 1 to 8 in parallel through two new hooks (`TINY_NES_STAGE`, `TINY_NES_NETLIST`) in the pinned build script, keeping the clean seed with the fastest bus clock and writing `build/tang32/seeds.tsv`. Seeds 2, 3, 4 and 7 were clean at 80.13, 80.28, 80.45 and 78.48 MHz before the user cancelled the other four, and seed 4 was kept, with a 98.16 MHz pixel clock, 16,229 LUTs and 108 BSRAM blocks, giving `.fs` SHA-256 `9ed85617e4ff57ada2ebb654f4798f6b01a7f59b7c45ed42b94641363fcb605c` and `.bin` SHA-256 `b9f126e0d97941eb00f1ade290fb5c969338fb324c3b053dcf14320a7e5c1268`. Over two-wire, `terrain.elf` SHA-256 `47f245db6b6cc51112275e977d529b101491bdc6d2526c5114b32f81e6c14e0f` reported MODE=FABRIC TRIS=20085 PIXELS=33072 DRAW=37880us MAX=44989us FINISH=0us STALLS=4651 PERIOD=49673us LATE=0 CRC=4a893c8b, matching the PC frame for frame. The software build on the same image, SHA-256 `44a5204aeb64c42188244babb8a0fb7976b0534d6471a8a6b50f810f224e8fe9`, reported the same CRC with DRAW=42441us, so both showed a frame every three vertical blanks. A throwaway profiling build then measured a triangle's four FIFO writes at 23 CPU cycles within the loop, and a cached store missing into the SDRAM at about 620 cycles a line (AE-002). That shows the CPU's time is cache misses in its 1.1 MB vertex walk, not drawing or the bus, which met the plan's decision point. The user watched both runs and marked them pass. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` and settled entries unchanged, checked that the reference's fast index and records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

Make the CPU walk cache-friendly as the next cycle, already proposed: walk back to front by block and then by cell so that a block's vertices stay in the D-cache, and shrink the vertex records from 24 to about 8 bytes, recomputing camera-space values only for near-clipped triangles. Then profile on the board again. If the FIFO's measured drain rate of one word per about 120 cycles becomes the floor, pack a triangle into three words.

#### Files Modified:

- README.md
- firmware/terrain/Makefile
- firmware/terrain/host.c
- firmware/terrain/main.c
- firmware/terrain/terrain.c
- firmware/terrain/terrain.h
- fpga/raster.sv
- patches/tinynes-tang32.patch
- tests/raster_tb.sv
- tools/build_tang32.sh
- tools/run_tang32.sh
- tools/test_tang32_raster.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 10 COMMIT Unreleased 2026-10-15T04:33:53-07:00

#### Coming From:

Unreleased 3459472

#### Purpose:

Take entry 9's roughly 38 ms terrain frame apart by measurement, act on what the measurement showed, and cut the CPU work without moving the accepted frame.

#### Outcome:

Entry 9's diagnosis, that the CPU's time went on cache misses in its walk over about 1.1 MB of vertex records, did not survive measurement, and this cycle replaced it with a measured account and 25.5 percent off both the mean and the longest frame. A throwaway profiling build of `firmware/terrain/terrain.c` with `mcycle` probes reported per frame on the board 2.5M cycles in `to_camera` over 18,690 calls, 0.7M in `project_xy`, 12.0M in `submit()` over 36,096 calls, 0.05M in `cull_blocks` and 30.8M in the cell walk, which visits all 46,592 cells but draws only 21,041 of them. The same build established that the near-plane clip path never executes anywhere in the 600-frame orbit and that every stored projection stays well inside int16 (`sx` -3806 to 8788, `sy` 906 to 6866), so the vertex record became an int16 screen pair plus one 32-bit word holding a generation and the vertex's state, 8 bytes against 24, and no longer holds a camera-space position: a corner behind the near plane, or one whose screen coordinate left int16, has its camera-space position and exact projection recomputed from the grid index it is stored at, which makes the frame bit-identical. Working memory fell from 1,129,146 to 376,746 bytes. The plan's other half, a block-major traversal to hold a block's vertices in the D-cache, was rejected on evidence: reversing the walk's back-to-front order changed the frame CRC from `4a893c8b` to `b90fc26a` with identical triangle and pixel counts, so the order sets the frame the user accepted, and the walk already touched the records two rows at a time. A first version of the clip path skipped filling a front corner's camera-space depth, which the ordinary orbit hid and the stressed configurations caught, and the frame is bit-identical once that was fixed: old and new agree byte for byte in seven stressed configurations, among them one that takes the near-plane clip 1,300,229 times and one that takes the over-wide recompute 5,059,840 times, and AddressSanitizer and UndefinedBehaviorSanitizer are clean on the orbit, on the stressed build, and at `-O3`. The record change alone moved the mean frame from 37,880 to 36,925 us, which is what refuted the memory attribution; taking the everyday all-front triangle straight from the record, without the clip machinery's stack, cut `submit()` from 333 to 230 cycles a call and the mean to 31,249 us; and building the program at `-O3` through the runtime's `OPT` hook, now defaulted in the program's Makefile, took it to 28,204 us. `firmware/terrain/main.c` now also reports `VBLMIN` and `VBLMAX`, the fewest and most vertical blanks one frame took, because the shown rate is quantised to whole blanks and the worst frame, not the mean, is what stutters; the worst is now 33,491 us against the 33,320 us of two blanks, so one more win of that size turns the whole orbit into 30 frames a second. The core was rebuilt with the eight-seed sweep, all eight seeds clean this time and seed 6 kept at 87.36 MHz on the 75 MHz bus and 96.24 MHz on the 74.25 MHz pixel clock, `.fs` SHA-256 `b8f7d37f1d32fef383ba66d641bafbf9b54ebf7f22311f4dbf1ef0fab92c5338` and `.bin` SHA-256 `53d8f3998a462ea39a3166e82a4d66c039ab3463fb9106ce2567971ea489d66c`, with entry 9's device utilisation, and only the AE350 program was rebuilt after that. Over two-wire the board reported `MODE=FABRIC LAND=ed38589d FRAMES=600 TRIS=20085 PIXELS=33072 DRAW=28204us MAX=33491us FINISH=0us STALLS=14363 VBL=1529 VBLMIN=2 VBLMAX=3 PERIOD=42455us LATE=0 CRC=4a893c8b`, against 37,880, 44,989, 49,673 and 1,801 in entry 9, and `MODE=SOFT DRAW=30779us MAX=34119us PERIOD=42533us` against 42,441, so the mean and longest frame fell 25.5 percent and the mean period 14.5 percent; two consecutive runs agreed to within 60 us and both matched `terrain_host` frame for frame. The user watched the runs and called this build the best so far. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

Continue on the cell walk, which the phase profile now puts at about 15.1M cycles a frame outside `submit()`, `to_camera` and `project_xy`, roughly 324 for each of the 46,592 cells visited, and on `to_camera`'s 2.5M cycles, whose 64-bit multiplies are worth trying in 32-bit with the overflow bound checked and the frame CRC watched, since the worst frame is 171 us above the two-blank 33,320 us that would hold the whole orbit at 30 frames a second. Packing a triangle's four FIFO words into three is retired: four command words cost 23 CPU cycles and 34 with the indirect call, so the bus is not the limit. The stress harness that caught this cycle's clip-path bug still exists only outside the repository and is worth committing under `tools` with the frame CRC pinned for each configuration. The unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/Makefile
- firmware/terrain/main.c
- firmware/terrain/terrain.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---
