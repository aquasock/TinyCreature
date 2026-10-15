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

## 11 COMMIT Unreleased 2026-10-15T05:52:55-07:00

#### Coming From:

Unreleased 3ba2a9b

#### Purpose:

Cut the per-vertex camera transform, which entry 10's phase profile put at 2.3M cycles a frame with all eight of its products in 64 bits on a 32-bit core, without moving the accepted frame.

#### Outcome:

`to_camera` now holds its products in 32 bits, which is only safe against a bound, so `tc_land_open` checks that bound and refuses a grid that would break it rather than leaving it to a comment: the widest land the game ships, Land 5 at 352 by 256 cells, an extent of 56,320 in Q4, passes with 9.6 percent to spare, a synthetic 400-cell land is rejected with `TOO WIDE`, and 384 cells is accepted, so the limit is enforced and its edge is tested. Since the whole point was that the frame must not move, the frame is what was checked: the 64-bit and the 32-bit transform drew all 600 frames of the orbit byte for byte identically on each of the six lands the game ships, among them Land 5 at the tightest bound, and the same held across the six stressed configurations, including the one that takes the near-plane clip 1,300,229 times, with AddressSanitizer and UndefinedBehaviorSanitizer clean at `-O3` on the baseline, on the stressed build and on Land 5. On the board the fabric path's mean frame fell from 28,204 to 27,755 us, its longest from 33,491 to 33,011 and its mean period from 42,455 to 42,146, the software path's mean frame from 30,779 to 30,298, and both still reported frame CRC `4a893c8b` against `terrain_host`, the same value entries 9 and 10 pinned, so the frame the user had accepted was not re-drawn but re-derived. The saving is 1.6 percent, well under the 1.5 ms the estimate had claimed, which makes this the second time this work's arithmetic predicted more than the board measured: the products were not as costly as the disassembly's density of `mul` and `mulh` suggested. The frame is provably the frame the user accepted, so that acceptance carries rather than being taken again, and the build itself ran on the board. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

Entry 10's next-step note named two targets and this was one; the other was already in hand, because the phase profile and a throwaway probe showed that reading each frame's buffer back over the bus to check it cost about 5 ms of every frame, a fifth of the whole period and nothing to do with drawing. Moving that fold into the fabric is the cycle that followed. After it the cell walk's remaining 15.1M cycles a frame are the open target, and the level-of-detail idea is held in reserve for 60 frames a second, where the budget is 16.6 ms and free cuts will not reach it.

#### Files Modified:

- firmware/terrain/terrain.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 12 COMMIT Unreleased 2026-10-15T05:53:40-07:00

#### Coming From:

Unreleased bd53b27

#### Purpose:

Stop spending a fifth of every frame reading the rasterizer's own buffer back over the bus, by having the rasterizer fold the frame into the run's CRC-32 itself.

#### Outcome:

A throwaway probe had put the frame checksum's read-back at 5,013 us a frame, an eighth of the 42 ms period and every cycle of it bus reads rather than drawing, so `fpga/raster.sv` now folds the target buffer into a CRC-32 in address order, seeded by the program with the state the run has reached and read back a frame later; the same scan counts the bytes that were not zero and `STATUS` bit 1 says one is running. The design reuses the port the CPU's read-back already used, so the line fetch keeps its priority and nothing at all was added to the frame; the scan is a byte a clock, eight reflected steps at once and so no table to initialise, which is 2.3 ms for a frame, and the program hides even that by reading the previous frame's result while the current one is drawn. The firmware now reads one register a frame instead of 14,400 and chains the frames exactly as `tc_crc32(crc, frame, bytes)` chains them, so the value it ends with is bit for bit the one `terrain_host` computes from the same file: the board reports `CRC=4a893c8b`, the value entries 9, 10 and 11 pinned, which is the point of the design. A first version of the scan left `w_crc` set, so the scan restarted every cycle and the polling loop added to `tests/raster_tb.sv` never ended; the simulation hung for half an hour instead of failing, and both the flag and the testbench's unbounded waits were fixed, so that class of defect now fails loudly. The testbench and its runner also check the unit's checksum against the C's, for one frame and for two frames chained, and the simulation passes with the read-back and line-fetch checks intact. On the board the fabric path's mean frame went from 27,755 to 27,736 us and its mean period from 42,146 to 33,341 us, which is two vertical blanks, so 599 of the 600 frames now take two blanks and one takes three: the orbit runs at 30 frames a second where entry 9 measured 20, and the user called the frame rate rock solid. The software path, which still reads its buffer back in software, moved only with entry 11's camera change, to a 30,298 us mean frame and a 40,058 us period, and both paths still match `terrain_host` frame for frame. The core was rebuilt with the eight-seed sweep, five seeds clean and seed 2 kept at 81.04 MHz on the 75 MHz bus and 98.18 MHz on the 74.25 MHz pixel clock, `.fs` SHA-256 `391f892a11b7c636de4f67ff0892c60496783b05dc35ba9dfdb2c0a6287d392a` and `.bin` SHA-256 `089cfe606c7de4d74403be6bd7b709370062caecf3d55ba114f13fc24de16f01`; the checksum cost 299 LUT4s, 28 ALUs and 95 flip-flops with no additional block RAM, and it is not the critical path, which the timing report still puts in the HDMI encoder and the UART receiver. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The cell walk is the only large target left: outside the triangle submission and the two per-vertex transforms it is still about 15.1M cycles a frame, roughly 320 for each of the 46,592 cells visited, most of them in blocks that are drawn. Thirty frames a second is where this core now sits; 60 needs the whole frame under 16.6 ms, a halving that the cell walk alone will not give, so the level-of-detail idea -- cells merged once they cover less than a pixel, thresholded on projected size rather than distance -- is the tool for that and is deliberately unspent, as is its cost of a new pinned frame CRC and a fresh look from the user. The stress harness that caught entry 10's clip-path defect, and would have failed this cycle's hang in seconds rather than half an hour, still lives outside the repository; committing it under `tools` with the frame CRC pinned per configuration remains the outstanding debt. The unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/main.c
- fpga/raster.sv
- tests/raster_tb.sv
- tools/test_tang32_raster.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 13 COMMIT Unreleased 2026-10-15T06:08:36-07:00

#### Coming From:

Unreleased e60cd5c

#### Purpose:

Attribute what remains of the cell walk, which entry 12 left as the last large target, and decide from measurement whether to keep cutting it.

#### Outcome:

Three throwaway builds on the board answered this, and the answer is that the walk is not what its instruction count suggests. An attribution tree over the walk reported 25.51M cycles a frame, of which `draw_cell` is 23.69M over 21,041 calls, or 1,126 cycles each: its own work 553 of those, `vertex` 248 over 3.45 calls, and `submit` 321 over 1.7 calls, while a cell that is visited and not drawn costs about 41, so the loop and the block test are not the problem. A model of the A25's cache (32 KiB, 4-way, 32-byte lines, TinyNES DEV-013) replayed over the walk's real accesses -- instrumenting the host twin to record every touch of the vertex records, cells, altitude and block flags, 293,019 a frame -- finds only 8,282 misses, 2.8 percent, identically under LRU and random replacement, which is 5.1M cycles or about a quarter of the frame: the walk is not memory-bound. A null-target build, the same walk with only the rasterizer emission removed, then took `DRAW` from 27,736 to 16,889 us, so sending a frame's commands costs 10,847 us, 39 percent of it, for 80,340 words at about 101 A25 cycles each. That last figure matches AE-002's 120 cycles for a back-to-back uncached store and contradicts the 23 cycles for four stores entry 9 recorded, which is the number the planning retired triangular packing on: the packing question is open again, and the older figure is the one to distrust. The reason the store path dominates is the resolution: at 320 by 180 the whole island is about 1.4 cells to a pixel when the camera is out, so the renderer sends 20,085 triangles to fill 33,072 pixels, 1.6 pixels a triangle at roughly 540 cycles each including its four command words, or 330 cycles for every pixel drawn. So no arithmetic change will pay -- this cycle's three estimates over-predicted by three to ten times each -- and the only lever that crosses the display's one-blank 16.66 ms budget is drawing fewer and larger primitives, which is the level-of-detail idea the user has chosen to keep unspent for now. The user parked the walk here at 30 frames a second, asked for the project to move towards a game, and asked whether the camera could be moved with a mouse; the investigation of that is the next entry, and the input hardware facts are as TinyNES records them: four Wii Classic Controllers read over I2C on PMOD0 and exposed to the AE350 at 0xe8040000 (TinyNES PMOD-007, WII-001), which this core's patch removes, the platform's keyboard path enumerated and discarded (TinyNES NEST-002), and the dock's two USB-A ports sitting on FPGA pins (TinyNES BRD-003). No core in these projects has read a mouse. Nothing was committed by this cycle: every build was a throwaway, the shipped source is unchanged, and no frame CRC moved. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

Turn the terrain orbit into something a person drives. The core reads no input at all today, so the first question is which input path to build, and there are three with very different costs: the Wii Classic Controller path this core's patch removed, which TinyNES proved on this bench and which needs the pad blocks and their register restored and a core rebuild; the console link, which is already open on the board and could carry camera commands from a host-side mouse into the AE350's UART with no change to the fabric at all, at the price of staying tethered to the PC; and a USB host in the fabric for the dock's USB-A ports, which nothing here has done and which is the only way to a mouse on the board itself. Whichever is chosen, the camera becomes state the firmware owns and the frame stops being a fixed 600-frame orbit, which changes what `terrain_host` and the frame CRC mean and needs its own cycle. The stress harness that would have caught entry 10's clip-path defect in seconds, and that this cycle's hangs and mis-estimates argue for again, still lives outside the repository. The unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 14 COMMIT Unreleased 2026-10-15T06:37:52-07:00

#### Coming From:

Unreleased 4bcde11

#### Purpose:

Give the terrain program a camera a person drives, held as state the firmware owns and fed by input the board can deliver, so the island stops being one fixed orbit.

#### Outcome:

`tc_camera(turn, zoom)` now aims the walk, adding to the orbit's own turn and to its distance from the island's centre; until a program calls it, `tc_draw` keeps the scripted orbit exactly, which is what let every frame this project has accepted stay where it was: all six shipped lands reproduce their previous frame CRCs byte for byte, the six stressed configurations still agree with the code before the change, and AddressSanitizer and UndefinedBehaviorSanitizer are clean at `-O3`. One input report is six bytes -- the frame it belongs to, the buttons, and the mouse's dx, dy and wheel, which is the shape a mouse's own HID boot report has -- and there are two ways in. A recorded sequence rides in the tail of the land file the program asks for, split off by the TCL1 header's body length so that the land's own check and its CRC still see the land alone; a live mouse sends the same six bytes on the AE350's UART as a frame in TinyTang's format, `0xAA len_hi len_lo type`, with type 0x16 and the frame 0xffff meaning apply it as it arrives. The UART stays in the loader mode it resets into, received bytes going to the AE350's own buffer, because this core carries no desk link to enter link mode with, and that is what makes the live path possible with no change to the fabric at all. `tools/tang_input.py` writes a sequence and appends it to a land file, and `tools/run_tang32.sh terrain` grew `TINYCREATURE_INPUT`, which appends, hands the PC twin the same reports, and now compares INPUT alongside LAND, FRAMES, TRIS, PIXELS and CRC. On the board a run without input reported INPUT=0 and frame CRC `4a893c8b`, the value entries 9 and 12 pinned, so the accepted frames had not moved; a run of 600 reports reported INPUT=600, TRIS=17661, PIXELS=38444 and CRC `fbadead4`, matching `terrain_host` given the same reports frame for frame, which is the first time this project has checked the board against the PC for frames a person's input shaped rather than a fixed script's. The driven camera does something the orbit never did: at 1152 blanks for 600 frames, one frame fit a single blank, so parts of the run are at 60 frames a second. Two mistakes of this cycle's are worth recording. The first board attempt deployed a stale ELF left in `build/tang32/terrain` from entry 12, whose untouched length check correctly rejected the appended tail, which read as a defect in the new code until the binary was inspected. The runner also exported `TC_INPUT` as an empty string when no input was set, and `getenv` returns that rather than nothing, so the twin tried to open an empty path; both are fixed and both runs were then taken. The user watched the run on HDMI and marked it pass. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The board's own BLE mouse is what remains, and it is the phase this cycle prepared: TinyTang already gathers the mouse's boot report in `tang_ble_mouse()` and hands it to its desktop pointer, so the work is to send that same report to the core as a type 0x16 frame beside the desk layer's own sends, which needs the BL616 flashed, the one operation in this project that can cost more than time, and the user's explicit go-ahead for it is still outstanding. The keyboard follows the same route and needs a little more, because TinyTang types it into its own desktop rather than passing it on. Once the board's mouse drives the camera, the recorded path wants a pinned frame CRC of its own held in a tool, so that the input path can be regressed without a live board, and the stress harness that caught entry 10's clip-path defect -- the debt named in entries 10, 12 and 13, and felt again here -- should be committed beside it. The unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/host.c
- firmware/terrain/main.c
- firmware/terrain/terrain.c
- firmware/terrain/terrain.h
- tools/run_tang32.sh
- tools/tang_input.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 15 COMMIT Unreleased 2026-10-15T06:59:42-07:00

#### Coming From:

Unreleased e690f35

#### Purpose:

Put the board's own Bluetooth mouse behind the input path entry 14 built, so the island is driven by a hand on this board rather than by a host.

#### Outcome:

Entry 14 left the live path decoded and waiting; this cycle is the other repository's half of it, and no line of this project's program changed to make it work. TinyTang at `62fe6a7` (its entry 79) gained `FPGA_CMD_INPUT 0x16`, the first command that carries input into a core -- six bytes of the frame it belongs to, the buttons, and the mouse's dx, dy and wheel, with 0xffff meaning apply it as it arrives -- sent from its desk task in both branches, because the overlay is cleared while a program runs and the desk layer's poll only ran while it was drawn. The first interactive attempt drove nothing, and both causes are worth keeping. The mouse had not reconnected: `blemouse` reported "waiting" until it was woken, which is a thing the user saw before the agent did. And the host's loader held the link for the whole run, because `load_ae350.py` keeps TinyTang's `fpgapipe` open until the program exits and `fpgapipe` holds the transmit lock throughout: a program loaded and watched from the PC cannot receive in-band input until the host lets go, which is the same exclusivity that keeps the desktop off the screen while a cartridge loads. With the mouse connected and the pipe released the user drove the camera with it and reported it working perfectly, which is this cycle's test. The firmware was built with the Xuantie-900 GCC 10.2.0 and SDK 2.3.36 this machine already held, installed with TinyTang's own `tools/tinytang_flash.py` and a power cycle, after which `platform` reported `6145683-dirty.7381d83` against `0947b57-dirty.aafcfe8` before it. One defect is left open rather than tidied away: `pointer_frame()` guards on `tang_fpga_link_open()`, which brings the UART up and returns 0 but does not say whether the host's pipe owns the link, so while a pipe is open the call takes the transmit lock with `portMAX_DELAY` and stalls the desk task for that pipe's lifetime instead of returning. It recovers when the pipe closes, but a run held open from the host holds the desktop's task with it, and that is the next fix. `.ai/core-reference.md` gains topic TANG and record TANG-001 for the frame contract, which is another project's and which this program's decoder depends on, and the README no longer says the board's mouse is unwired. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

Fix the pipe guard in TinyTang and flash it once more: the state wants a query of its own, `s_pipe` being already tracked in `tang_fpga_uart.c`, so that the forwarder returns early instead of taking the lock while a host owns the link. The keyboard is deliberately not in this cycle, as the user asked: TinyTang types its reports into its own desktop rather than passing them on, so forwarding them is its own decision. What a mouse count means to this camera is `TC_TURN_PER_COUNT` and `TC_ZOOM_PER_COUNT` in firmware/terrain/terrain.h, and now that the user can feel them they are theirs to set. The recorded-input run remains the regression and the interactive run cannot be one, which is the case for pinning a CRC per recorded sequence in a tool, beside the stress harness that entries 10, 12, 13 and 14 all owe. The unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 16 COMMIT Unreleased 2026-10-15T07:33:43-07:00

#### Coming From:

Unreleased c0945d8

#### Purpose:

Drive the terrain camera with the mouse the way the original game does, so that the user can move around as they did in Black & White and judge the frame rate from that, rather than from a scripted orbit.

#### Outcome:

The camera is now openblack's (core-reference OB-005): a focus point on the land, an angle and a tilt it is seen from, and a distance from that point, with the middle button held and dragged turning and tilting it, the left button held and dragged moving the focus so that the land follows the hand, and the wheel changing the distance -- which the user asked to be inverted from the usual direction, and it is, with the comment saying so. The renderer needed nothing: `to_camera()` has always taken a position and two angles, and only the update was scripted. The mapping lives in `tc_mouse()` in `firmware/terrain/terrain.c` rather than in the firmware, so one function decides what a report means and the host twin beside it decides the same, which is what lets a recorded session still be checked frame for frame. The tilt is held between about nine and seventy-nine degrees, the distance between twenty world units and twice the island's width, and the camera keeps ten units of clearance over the ground it looks at. The four constants in terrain.h are the whole feel -- `TC_TURN_PER_COUNT` 128, `TC_PITCH_PER_COUNT` 24, `TC_ZOOM_PER_COUNT` 128 and `TC_DRAG_DIVISOR` 256 -- and the zoom was doubled and the wheel inverted at the user's request, each tried on the board and passed. A run that hands over no report keeps the scripted orbit exactly, which is what the whole acceptance chain rests on: all six shipped lands still reproduce their frame CRCs byte for byte, most importantly Land 1's `4a893c8b`, the six stressed configurations still agree with the code before the change, and AddressSanitizer and UndefinedBehaviorSanitizer are clean on both the scripted and the driven paths. A recorded session of turns, drags and wheel now draws `TRIS=15602 PIXELS=15872 INPUT=600 CRC=62c277f1` where the scripted orbit draws `20085`, `33072` and `4a893c8b`. One bug was found by the first driven run drawing nothing at all: the input is applied before `tc_draw` has ever run, so on the first frame the camera state was uninitialised zeros, a distance of zero and a focus at the world origin. The camera is now seeded at init with the scripted orbit's own frame zero -- the island's centre looked at from reach away at the orbit's tilt -- so a hand on the mouse moves the view from where the run would start rather than jumping it, and no frame is drawn from a state that never existed. `tools/run_tang32_feel.sh` is new: one command that builds for a long run, loads the core, runs the program, hands the board's link back to the mouse and says what the buttons do, about forty seconds a change with no core rebuild and no TinyTang flash. `tools/tang_input.py`'s pattern now holds the middle button, then the left, then rolls the wheel, which is every way the camera moves. The user drove the camera with the board's own mouse through all of it and passed the cycle. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The pipe guard in TinyTang is still the one defect either project is carrying: `pointer_frame()` takes the transmit lock while a host owns the link and stalls the desk task for that pipe's life, where it should return early, and fixing it needs a build and a flash. Flying to a clicked point, openblack's double click, needs a screen-to-land raycast and is the one camera behaviour deliberately left out. The keyboard is held off at the user's request. The feel is now the user's to set through terrain.h's four constants, and the recorded-input run remains the regression that a live run cannot be, which is the case for pinning a CRC per recorded sequence in a tool beside the stress harness that entries 10, 12, 13, 14 and 15 all owe. The level-of-detail idea stays parked for sixty frames a second, where the budget is 16.6 ms and free cuts will not reach it. The unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/host.c
- firmware/terrain/main.c
- firmware/terrain/terrain.c
- firmware/terrain/terrain.h
- tools/run_tang32_feel.sh
- tools/tang_input.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---
