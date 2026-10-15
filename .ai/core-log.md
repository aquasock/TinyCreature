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

## 17 COMMIT Unreleased 2026-10-15T08:04:12-07:00

#### Coming From:

Unreleased bb83c43

#### Purpose:

Draw the mouse's own cursor, so that the hand moving the land on the board is visible on the screen it is moving, which is the last thing missing before the feel of the camera can be judged like the original game's.

#### Outcome:

The program now draws a hand where the pointer is, and it is this repository's own shape rather than anything from the game: a 13 by 15 drawing held in `firmware/terrain/terrain.c` whose one asset is the hand itself, the tip of its pointing finger at the top left, which is the cursor's hotspot. Its outline is derived at `tc_init` by taking one ring out from the hand in eight directions, so nothing is drawn twice and the outline follows any change to the shape; the result is kept as 57 runs of one colour, a run being a horizontal span of the hand or of its outline, in a 128-entry array of `struct hand_run`. A run becomes two triangles because the CPU cannot write the rasterizer's pixels, only send it triangles, so the whole cursor is 114 `TRI` commands and 456 words through the FIFO, about 0.07 ms of a frame -- under a fifth of a percent, against a frame of 33.3 ms. The two colours are the program's own and are the same on every land, because the palette's first sixteen entries are the sky's and the sea's ramps: the fill is the palest sky, entry 8, and the outline the deepest sea, entry 16. Reserving palette entries for the cursor was rejected for that reason, since the land file's fitted palette is what sets the scripted frame the whole regression rests on. The cursor is drawn after the land and only when the camera is driven by the mouse, so a scripted run is untouched, and it follows the hand whatever the buttons are doing, which is what lets a left drag take hold of the piece of land it took: its position is kept in the renderer's own sixteenths of a pixel, moving by `dx * 16` and `dy * 16` and clamped to the screen, starting at the middle. One bug is worth keeping: the first attempt sent all 114 triangles and filled none of them, because the rasterizer fills where the interior lies to the left of each directed edge, so on a screen whose y runs downwards a rectangle has to be wound down its left side, along the bottom, and back along the diagonal, and the two triangles are now written in that order with the reason in a comment beside them. The user looked at the hand on the board and passed it. Every one of the six shipped lands still draws its scripted orbit to the same frame CRC as before the change, Land 1 `4a893c8b`, Land 2 `17376a79`, Land 3 `5d272ec0`, Land 4 `82d707b0`, Land 5 `450bd5fe` and Land T `80058e01`, and both recorded sessions of turns, drags and wheel agree with the code before it except for the hand: `build/land/in-drag.bin` draws `TRIS=14860 PIXELS=14979 INPUT=600 CRC=f3392ebc` where the committed program draws `14746`, `14937` and `bfd8c5d7`, and `build/land/in-pattern.bin` draws `24767`, `23665` and `2e5b1541` where it draws `24653`, `23641` and `c0cf57e3` -- exactly 114 triangles more in each, which is the cursor's runs to the triangle, and 42 and 24 pixels more, which is the hand where it lies over land rather than over sky. Entry 16's recorded-session figures could not be reproduced while this cycle was checked, and are recorded here as wrong rather than quietly replaced: the committed program draws `14746`, `14937` and `bfd8c5d7` from `build/land/in-drag.bin`, the recorded drag session in the tree, and no step of `tools/tang_input.py`'s pattern, tried from 1 to 24, draws the `15602`, `15872` and `62c277f1` entry 16 records, so those three numbers were measured from a state of the tree that its own commit does not hold. This cycle records only what it reproduced, and the case for pinning a CRC per recorded sequence in a tool is the stronger for it. AddressSanitizer and UndefinedBehaviorSanitizer are clean on both the scripted and the driven paths, and the hand was also confirmed against a framebuffer dump before it was deployed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The next cycle is approved and is the one that answers why the land looks rough: this program has no textures, and gives each triangle the single colour that is the mean of its three corners, which is the whole of the flat look the user called garbage. `tools/convert_land.py` will write a colour per vertex instead of a colour per triangle, keeping only a flags byte per cell, which also shrinks the file, and the fill will interpolate the three corners -- Gouraud -- instead of using one. Three eight-bit corner indices fit in the single colour word the `TRI` command already carries, so the command must stay four words: sending commands is 39 percent of the frame, so widening it would cost more than the shading could win. Interpolating palette indices is wrong because a palette is not a ramp, so the fabric has to interpolate red, green and blue and then find the nearest entry, which wants the palette and a 32 KB index table in block RAM, sixteen of the 232 free blocks. `tc_soft` in terrain.c is the rasterizer's exact model and `tests/raster_tb.sv` drives the same commands, so both must implement the same rule pixel for pixel, and a fabric change means a core rebuild with the eight-seed sweep and a new pinned frame CRC for the user to accept. The pipe guard in TinyTang is still the one defect either project is carrying: `pointer_frame()` takes the transmit lock while a host owns the link and stalls the desk task for that pipe's life, where it should return early, and fixing it needs a build and a flash. Flying to a clicked point, openblack's double click, needs a screen-to-land raycast and is the one camera behaviour deliberately left out; the keyboard is held off at the user's request. Pinning a CRC per recorded input sequence in a tool remains owed with the stress harness that entries 10, 12, 13, 14 and 15 all name, and entry 16's unreproducible figures are the second reason for it: three numbers in a committed log entry cannot be re-derived from that entry's own commit, and a tool that regenerates each recorded sequence and fails on a changed CRC is what stops the next one. The level-of-detail idea stays parked for sixty frames a second, the unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/terrain.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 18 COMMIT Unreleased 2026-10-15T10:01:38-07:00

#### Coming From:

Unreleased a6e0988

#### Purpose:

Take the flat look out of the land. Until now every triangle was filled with the single palette entry nearest the mean of its three corners, so each one was a flat patch and the terrain read as facets. This cycle gives each vertex its own colour in the file and shades every pixel between its triangle's three corner colours, on the board, in the fabric, with the AE350 and a PC still drawing identical frames.

#### Outcome:

The file is now TCL2 and carries a colour per vertex rather than a colour per triangle: `tools/convert_land.py` still gives each vertex the daylight colour openblack's terrain shader would give it, still reduces each material to a mean colour, but fits the 239 palette entries to the *vertex* colours weighted by how many drawn triangles use each one, and writes a flags byte per cell instead of that byte plus two triangle colours. Land 1's file falls from 187,789 bytes to 141,630 and the geometry is untouched: all six shipped lands draw the same triangle and pixel counts as before, and the palette fit moved the frames by only a few percent on the neighbour-difference measure that judges such things (mean neighbour colour distance 3.94 against 4.10 for the old mean-colour palette on triangles eight pixels across, hard jumps 0.7 against 1.0 percent, all Land 1, the "in the grass" zoom). The command stays four words because three corner entries fit in the one colour word a `TRI` already carries, which matters: sending commands is 39 percent of the frame, so widening it would have cost more than the shading could win. `tc_soft` in `terrain.c` is still the fabric's exact model and now shades too, from `tc_shade_tables`: the 256 palette entries in the five bits a channel the game's materials carry, and a 32,768-entry table from a colour those channels make back to the nearest land entry, ties to the lower one. `tc_init` builds both in the working memory beside the vertices, which grew by 33,280 bytes, and returns them. The fabric holds the same two tables, written once by the program through two new registers at `0x2c` and `0x30`, and a `TRI` word's three colour bytes are taken with its corners: the command assembler gathers the next command while the engine draws the last, so reading them at the palette walk found them already overwritten by the next triangle. Each filled pixel takes the palette entry nearest the point of its triangle's colour plane whose barycentric weights are the pixel's, those weights quantised to quarters by counting the thresholds 2S, 3S against S = F0 + F1 + F2, which is the same at every pixel of a triangle. That quantisation is not free of arithmetic: it is a 36-bit compare chain and five-bit mixes, and it does not fit one bus clock. The first sweep's five finished seeds all failed the bus clock at 48.39 to 65.75 MHz against the 75 MHz the bus needs, so the fill now takes two clocks a pixel, weights in the first and the mix and the table's address in the second, with the table's answer written a clock later and a two-clock drain for the last pixel; the same seeds then reached 75.26 to 78.73 MHz and six of the eight came back clean. Two bugs were found by measurement rather than by reading, and both are worth keeping. The first was mine in the shading rule: I had the barycentric correspondence wrong, using F0/S for the second corner and F1/S for the third where the edge functions measure the corner across from them, so the weight of the second corner is F2/S and of the third F0/S. With it wrong each triangle's colour plane was a different permutation of the true one, so colours disagreed across every shared edge and the shaded image measured twice as noisy as flat, mean neighbour colour distance 9.92 against 5.19 and hard jumps 6.8 against 1.9 percent, and even on triangles eight pixels across 10.12 against 3.94; with it right, quarters measure 5.97 against 5.15 and hard jumps 2.0 against 1.9 percent overall, and on triangles ten pixels across 0.8 against 1.4 percent, which is the shading doing its job where a triangle is big enough to show a gradient. The second was found by instrumenting the design and comparing its weights against the model's: `3S` was written `(S << 1) | S`, a bitwise or, which equals the sum only when no carry lands on the same bit; s3 came out 115 where the model said 147, and every weight that depended on it was wrong. Four more were caught in simulation, where the testbench compares the fabric's frames byte for byte against the twin's through the read-back registers, the line fetch and the CRC chain: the table's write address was truncated to eight bits, so entries above 255 were never written and pixels read unknown; the palette's three reads were captured a cycle early, so the corner colours were its neighbours'; the table and palette writes were latched at the address phase, where the bus data has not arrived yet, instead of the cycle after acceptance where every other register reads it, which filled both memories with the previous write's data; and the fill's write was a clock out of step with the table's answer, which needed a second pipeline stage and a two-clock drain. The memory mapping cost two detours of its own. Yosys was turning the 32,768-entry table and the palette into registers, 262,144 flip-flops for the table alone, because their writes sat inside the bus finite state machine's block with an asynchronous reset; moved into a clocked block of their own, the shape the frame buffers already used, both map to block RAM. Then the build script rejected every seed, including one that passed both clocks at 75.65 and 88.50 MHz, with "video block RAMs not in 9-bit mode": every `screen.` and `raster.` block RAM's width must be a multiple of nine, because only those modes read back correctly in the video unit on this chip (entry 14), so the palette is declared 18 bits wide and the table nine, and no seed could be clean before that. Two sweeps were also lost to a peer agent's build cleanup on this machine, which killed both projects' seed shells at once; at the user's instruction the other agent's routers were then killed and the third sweep had the machine to itself. The core was rebuilt with the eight-seed sweep and seed 6 kept at 78.73 MHz on the bus and 90.42 MHz on the pixel clock, against 75 and 74.25 required, with seed 8 best on the pixel clock at 95.29 and seeds 2, 3, 5 and 8 also clean. Over two-wire the board reported `TinyCreature TERRAIN OK MODE=FABRIC LAND=c3794636 FRAMES=600 TRIS=20085 PIXELS=33072 DRAW=29353us MAX=35218us FINISH=0us STALLS=15068 VBL=1322 VBLMIN=2 VBLMAX=3 PERIOD=36707us INPUT=0 LATE=0 CRC=da75b4c1`, which is `terrain_host`'s frame CRC for the same file, so the fabric's shading matches the model on every pixel of every frame. The price is in those numbers: the mean frame rose from 27.7 to 29.4 ms and the worst from 33.0 to 35.2 ms, past the 33.3 ms of two vertical blanks, so the mean period is 36.7 ms, about 27 frames a second where the unshaded fill held 30, and 15,068 bus cycles a frame are now spent waiting on a fuller FIFO. The mesh averages under two screen pixels a triangle at the default orbit, 33,072 pixels over 20,085 triangles, so at that distance most of the interpolation is finer than the display can show; the user flew it with the board's mouse, looked close in where it tells, called it great and accepted the frame drop. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The keyboard is the next thing the user wants, and it is waiting on another project: TinyTang is gaining keyboard forwarding for Tiny89's sake, and this program's decoder reads only frame type 0x16 as six bytes of mouse, ignoring unknown types and discarding their payloads, so a new type is safe but a re-used one is not and wants checking when it lands. The shading's cost is now known and has known fat to trim if the frame rate matters again: the four-cycle palette walk each triangle pays before its first pixel, the second clock a pixel, and the 16 block RAMs the two tables take of the 232 free, against the 15,068 stalls a frame the CPU now waits on. The quarters the weights are quantised to were chosen because the fabric can count them, not because the look demanded them; if a gradient ever reads as stepped when a cell fills the screen, more compares buy finer steps, and the sixteenths build tried here was flawed and settled nothing. The level-of-detail idea stays parked with a measured price beside it now that the fill is doing real work. The pipe guard in TinyTang is still the one defect either project is carrying: `pointer_frame()` takes the transmit lock while a host owns the link and stalls the desk task for that pipe's life, where it should return early, and fixing it needs a build and a flash. Flying to a clicked point, openblack's double click, needs a screen-to-land raycast and remains the one camera behaviour deliberately left out. Pinning a CRC per recorded input sequence in a tool remains owed, with the stress harness entries 10, 12, 13, 14 and 15 all name and entry 16's unreproducible figures as its second reason. The unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/host.c
- firmware/terrain/main.c
- firmware/terrain/terrain.c
- firmware/terrain/terrain.h
- fpga/raster.sv
- tests/raster_tb.sv
- tools/convert_land.py
- tools/run_tang32.sh
- tools/tang_input.py
- tools/test_tang32_raster.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 19 COMMIT Unreleased 2026-10-15T10:29:39-07:00

#### Coming From:

Unreleased 09e976a

#### Purpose:

Make the PC reference behave like the original's camera, so that there is something to build the board's user control against. The user, testing openblack's playground on this PC before turning to TinyCreature's own mouse, reported that a middle drag there made the near field stand still while the far field tracked the cursor, and that the original he remembers is the inverse: the hand takes hold of a piece of land and the camera swings about it.

#### Outcome:

The behaviour the user described is real, and it is upstream's, not the original's. `UpdateModeArcBall` in openblack's `DefaultWorldCameraModel.cpp` sets the focus to the grabbed point plus `screenCentreOffset * halfTan * arcBallRadius * 2`, so the point under the cursor slides along with the cursor, and nothing recentres the pointer while a rotation is held: upstream's issue #711, "Reset the mouse position in the window when performing some camera manipulations", is open for that, with its TODO sitting in the two-button zoom. Because the offset term is what the original never sees, it is worth saying where that was read from. openblack's test directory carries per-frame dumps of the original's own camera-controller memory, and across the 401 frames of `test/camera/scenarios/MiddleDragRightUp.json` the distance from the camera's origin to the grabbed land point stays between 11.68 and 11.73, the camera's azimuth about that point sweeps 42.4 degrees, the distance from the aim point to the grabbed point falls from 1476.7 to 3.0 and ends 2.86 units above it -- the floating height of 3 that the model sets -- and the pointer is at 400,450 on every single frame, the centre of an 800 by 900 window. So the original pins the pivot, orbits at a fixed radius, converges its aim onto the finger and recentres the pointer every frame; upstream's live arc ball does none of that, and its own recorded-data test cannot see the difference because the offset term is identically zero in all of its evidence. The same reading cleared up the other half of the question: the left-button land grab, the half the user already judged this project's better, is the one upstream flags as broken, with `// FIXME: This whole section is broken` on its movement scaling and three TODO(#713) markers about the hand-plane geometry the engine never derives, while `MiddleDragRightUp` passes only because the test harness injects that geometry out of the recording. The fix is this project's, not upstream's: a fourth patch, `patches/openblack-camera-arcball.patch`, wired into `tools/build_openblack_playground.sh`, which makes the grabbed point the pivot and nothing else, and holds the pointer at the centre of the window while the middle button is down. Two attempts were needed and both failures are worth keeping. The first zeroed the mouse delta when it saw the pointer's recentring arrive as a motion event, which it does, carrying the reverse of the movement the hand has just made and landing last in the frame: that wiped the turn on every frame, and the user's report was exact -- "middle click is a single shot button that just snaps to a location, now I cant rotate at all". The same attempt recentred to the position the rotation began at, where the original recentres to the centre of the window, as its recordings show. The second attempt dropped the recentring's event without touching the delta, which fixed the rotation, but warped the pointer with `SDL_WarpMouseInWindow(nullptr, ...)`, which means the window with keyboard focus rather than the game's. With focus elsewhere the button still reaches the game, which is how the user was playing, but the recentre went to the wrong window: the game's pointer walked out of it, motion events stopped, and the user saw the symptom they had already guessed at, "the game rotates for like a split second. maybe its when my mouse leaves the screan". Adding `SetMousePosition` to the windowing interface and warping the game's own window fixed it, which needs no focus at all. The verification is a synthetic middle drag through `xdotool`, and its first results were worthless: an untouched second changed 0 pixels of the frame, which made the test meaningful, but drags appeared to do nothing until the window was raised and focused, and the user's own hand on the mouse interfered with anything read while their pointer was shared. With the window raised and focused, a 60-pixel middle drag held the pointer at the window centre and changed 921,592 pixels of a 921,600 pixel frame against 0 for the control. The user then drove it himself and called it perfect and just like he remembers, and asked that this be kept as TinyCreature's reference for user control. `OB-005` in `.ai/core-reference.md` was revised in place for it: the record was SOURCED from source reading alone and described the arc ball without the pivot, the recentring or upstream's deviation, which is exactly what let this project describe the original's rotation wrongly to the user earlier the same day; it now carries the recorded evidence, upstream's deviation and this project's patch, and is raised to VERIFIED on the strength of the recorded frames and the playground on this PC. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The camera's shape is now settled by the reference rather than by guesswork, and the next cycle is to build it into `firmware/terrain/terrain.c`: a middle press picks the piece of land under the cursor and that point becomes the pivot, the camera orbits it at the distance it had then, its aim converges onto it and stays when the button comes up, and the left drag and the wheel keep their present meaning and their inverted zoom. The pick is the one piece of machinery this needs and does not have, and the same pick is what flying to a clicked point has wanted since entry 16, so it should be built once for both. Nothing there needs the recentring upstream was missing, because the board is sent mouse deltas rather than a pointer position and so lives in the recentred world already; that is worth remembering before anyone copies a pointer into this camera. The keyboard is still the user's stated next want and is still gated on TinyTang gaining keyboard forwarding from the Tiny89 work, with this program's decoder reading only frame type 0x16 as six bytes of mouse and discarding unknown types safely, so a new type is fine and a re-used one is not. The pipe guard in TinyTang is still the one defect either project carries, `pointer_frame()` holding the transmit lock while a host owns the link, and fixing it needs a build and a flash. Pinning a CRC per recorded input sequence in a tool remains owed, with the stress harness entries 10, 12, 13, 14 and 15 all name and entry 16's unreproducible figures as its second reason. The level-of-detail idea stays parked with a measured price beside it, the unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- .ai/core-reference.md
- patches/openblack-camera-arcball.patch
- tools/build_openblack_playground.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 20 COMMIT Unreleased 2026-10-15T10:46:31-07:00

#### Coming From:

Unreleased 0c37094

#### Purpose:

Make the board's rotation feel like the reference. Entry 19 left the PC playground rotating the way the original does and the user asked for that to be this project's model, so this cycle puts the pivot into the board's camera: a middle press takes the piece of land under the hand, the camera orbits that point at the distance it had, and the hand stays on it while it turns.

#### Outcome:

The reference, restated from entry 19's recording rather than from memory: the pivot is the piece of land under the hand when the middle button goes down, the camera keeps the distance it had to that point and orbits it, its aim converges onto the point, the turn comes from the pointer's deltas alone, and the pointer is recentred on every frame of the rotation. Our camera is `focus + distance * direction(turn, pitch)` looking at the focus, so the whole of that comes from setting the focus to the picked point and the distance to the picked point's depth along the view: the existing turn and tilt are already an orbit of the focus, the camera keeps its angle and only re-anchors, and on release nothing is undone. The one piece of machinery this needed is the pick, which is new: `land_pick` in `firmware/terrain/terrain.c` undoes the projection and then the two rotations `to_camera` applies, against them and in the reverse order, and marches the resulting ray against the height field the renderer draws in one-unit steps to a limit of three island extents, taking the first point that drops to or below the ground and only inside the island's grid. The depth is the picked point's distance along the view, the projection of the camera's own axis on the way to it, clamped to 160 Q4 -- the ten units the original keeps as a floor -- and to twice the island's extent. The pick was checked by round trip rather than by eye: pressing with the hand at the middle of the screen picked the island's centre at 17920, 2004, 16150 Q4, 125 units of height, and projecting that point back through `to_camera` and `project_xy` landed at screen Q4 2560, 1413 against the cursor's 2560, 1440, an error of 1.7 pixels from the one-unit march. The second half is the hand: while the middle button is held the cursor is put on the middle of the screen every report, which is where the aim puts the piece of land it took, so the fingertip and the land it holds stay in the same place while everything else swings, and the pick has already happened by then, at where the hand was when the button went down. Ours is drawn rather than puppeted, which is why it needs none of the trouble entry 19 had: there is no OS pointer to warp, no event carrying the jump back as motion, and no window to get wrong. Chasing the pick turned up a bug that had been there since entry 16: `tc_init` seeded the focus, the angles and the distance but never derived `cam_x`, `cam_y`, `cam_z` or the sines and cosines, which only happened in `tc_draw`, so the first mouse report of any driven run acted on a camera at the world origin with no rotation at all. Entry 16's seeding fixed the state a frame is drawn from and left the state an input is applied to; both are seeded now. That is why the recorded drag session's numbers moved so far when this landed -- 14,860 triangles and 14,979 pixels became 19,834 and 31,113 -- the session had been thrown by its own first report. The wheel was also turned back to the direction the user first had it, having been reversed once in entry 16's cycle at their request; the comment in `tc_mouse` says which is which. Every check held: all six scripted lands draw the frame CRCs they drew before, most importantly Land 1's `da75b4c1`, which is the check that says none of this touches a run with no mouse; the recorded session that presses no buttons is unchanged to the byte; the recorded drag session that presses the middle button passes on the board against `terrain_host`, `TRIS=19834 PIXELS=31113 CRC=fc9b7256` with zero late line fetches, a mean 28.7 ms and at most 36.6 ms a frame, a 37.1 ms period; AddressSanitizer and UndefinedBehaviorSanitizer are clean on the scripted, pressed and recorded runs; and the pick's own arithmetic is the round trip above. The user flew it, said it was better, and then asked for exactly what the original does and this project had not yet copied -- the hand snapping and locking to the middle of the screen while the middle button is held, which is now in and which he passed. One difference from the original is left in deliberately and put to him: a middle press that misses the island leaves the camera turning about the focus it already had, where the original returns early and does not rotate at all. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

Two feel questions are the user's to settle. The first is the press that misses the land: matching the original means the middle button only bites when the hand is on the island, and the present behaviour, rotating about the old focus, is what this camera has done since entry 16. The second is easing: the original slides into a new pivot over about a second, where this jumps there as it presses, and the user has not asked for the slide. Flying to a clicked point is the other thing the pick unlocks, and it wants the same march plus the animation the original uses; it is now cheap and should be taken with the next camera change rather than on its own. The keyboard is still the user's stated next want and is still gated on TinyTang gaining keyboard forwarding from the Tiny89 work, with this program's decoder reading only frame type 0x16 as six bytes of mouse and discarding unknown types safely, so a new type is fine and a re-used one is not. The pipe guard in TinyTang is still the one defect either project carries, `pointer_frame()` holding the transmit lock while a host owns the link. Pinning a CRC per recorded input sequence in a tool remains owed, with the stress harness entries 10, 12, 13, 14 and 15 all name and entry 16's unreproducible figures as its second reason, and this cycle's driven runs are another pair of figures that only one file records. The level-of-detail idea stays parked with a measured price beside it, the unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/terrain.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 21 COMMIT Unreleased 2026-10-15T11:05:31-07:00

#### Coming From:

Unreleased 63e46e6

#### Purpose:

Make the hand sticky when it takes the earth with the left button, the way it is with the middle button's pivot: the hand holds a piece of land, and the land it holds stays with it while the camera moves.

#### Outcome:

The user asked for this and had the mechanism the wrong way round, and the recording says he was right about the behaviour and I was wrong about the reading. openblack's recorded left drag, `test/camera/scenarios/DragUpDown.json`, is 400 frames of GRABBING_LAND with the button held, and across all of them `lastGrabMouseHitPoint` takes exactly one value, (1000, 0, 1108.6): the hand holds one piece of land for the whole gesture. Meanwhile the camera's origin moves, 1120 to 1142, and the aim's own raycast sweeps from -368.5 to -346. At the press, that held point sits 12 units in front of the camera and 14.6 degrees below the aim, while the screen centre's own raycast lands 1488 units away, so the hand is nowhere near under the pointer: it is a thing in the world holding a world point, and its screen position is whatever the projection says. The pointer sits dead centre throughout. What this corrects is the account I gave the user earlier the same day, that the original's hand is the pointer and the land moves to keep up; the data says the hand is the held land and the camera is what moves. The implementation follows the measurement. A left press on the land takes the point under the hand with `land_pick`, the pick the middle press already uses, and keeps it as a world point; while the button is held the hand is drawn where that point projects, and because the hand, both picks and the drag all read one cursor, the cursor is set to that projection too, or the hand would be drawn in one place and the picks happen in another. On release the hand is left holding where the land went and the mouse moves it on from there, which is what the original does with its hand. What the mouse still moves is the camera, so the land keeps following the hand with the pull the user tuned in entry 16, `TC_DRAG_DIVISOR` and all. Two bugs were found on the way and both are worth keeping. `last_buttons = buttons` had ended up between the middle press's edge test and the left press's, so the left edge compared the current buttons against themselves and the grab was either never taken or taken on every report; it is now the last thing `tc_mouse` does, after every edge is read. And the camera's derivation from the focus, angle, tilt and distance was in two places, `tc_draw`'s driven branch and the copy entry 20 put in `tc_init`, which is a bug waiting for a third; it is now one function, `camera_from_angles`, called by the frame, by the init and by the input, the last because a grab has to project the point it holds through the camera the report was applied to rather than the frame before it, or the hand trails the land by a frame. The verification is the strongest kind this project has, a control: every one of the six scripted lands draws the frame CRC it drew before, most importantly Land 1's `da75b4c1`, and a build with the left press disabled reproduces entry 20 to the byte, `TRIS=19834 PIXELS=31113 CRC=fc9b7256`, which proves the refactor moved nothing and the grab is the only change. The recorded session's own numbers moved, from that `19834` to `20155` triangles and `31113` to `28503` pixels, and the reason is the design working rather than a fault: that session presses the middle button again at frame 240, and the middle press now pivots on the piece of land the hand is holding rather than where the mouse had drifted to by then. The hand's own contribution is unchanged at 114 triangles a frame, measured by splitting the count in a throwaway build. AddressSanitizer and UndefinedBehaviorSanitizer are clean on the scripted, recorded and pressed runs. The core was not rebuilt: this is the AE350 program alone. Over two-wire the board drew the scripted run to `CRC=da75b4c1`, unchanged, and the recorded drag to `TRIS=20155 PIXELS=28503 CRC=b92f03e8`, which is `terrain_host`'s frame CRC for the same session, so the pick and the projected hand run identically on the AE350; both runs reported zero late line fetches, a mean 28.6 ms and at most 36.8 ms a frame, a 37.5 ms period. The user flew it and passed it. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The user has said he will name the next cycle, so this is a handover rather than a plan. Open and in his hands: whether a middle press that misses the island should stop rotating the camera, which is the original's rule, or keep turning about the focus it had, which is what this camera has done since entry 16; and whether a new pivot should ease in over about a second the way the original's does, where this jumps there as it presses. Flying to a clicked point is now cheap, because the pick it needs exists and is checked, and it wants the animation the original uses with it, so it should be taken with the next camera change rather than on its own. The keyboard is still the stated next want and is still gated on TinyTang gaining keyboard forwarding from the Tiny89 work, with this program's decoder reading only frame type 0x16 as six bytes of mouse and discarding unknown types safely, so a new type is fine and a re-used one is not. The pipe guard in TinyTang is still the one defect either project carries, `pointer_frame()` holding the transmit lock while a host owns the link. Pinning a CRC per recorded input sequence in a tool is owed more strongly each cycle: entries 16 and 20 both left driven-run figures that only the log records, and this entry adds a third, `b92f03e8`, to a list a tool should be checking. The level-of-detail idea stays parked with a measured price beside it, the unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/terrain.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 22 COMMIT Unreleased 2026-10-15T11:49:14-07:00

#### Coming From:

Unreleased 4a5316d

#### Purpose:

Give the mouse a cursor that says what it is doing and takes the land by its own middle: the Dungeon Crawl Stone Soup tile set's green frame while no button is down and its red crosshair while one is held, drawn about the pick point rather than beside a fingertip.

#### Outcome:

The user picked `/home/vash/Downloads/Dungeon Crawl Stone Soup Full/` as the project's asset source, to move away from Lionhead's own art, and chose two of its tiles as the mouse cursor: the frame `misc/cursor_green.png` while no button is down and the crosshair `misc/cursor_red.png` while one is held, with a press taking the piece of land the marker is centred on rather than the piece beside a fingertip. Both are one flat colour and the source now carries them as grids of characters, as `THIRD_PARTY.md` records; the set is CC0, and it is credited there and named in the README. So that the cursor can own two palette entries of its own, the land gives up two of the 239 it had: `TC_LAND_COLOUR` moves from 17 to 19, `TC_CURSOR_IDLE` and `TC_CURSOR_HELD` take 17 and 18, and `tools/convert_land.py` fits each vertex to 237 entries, so all six converted lands were regenerated and their frame CRCs moved with their palettes while their triangle and pixel means did not, Land 1's from `da75b4c1` to `7511d71e` at an unchanged 20,085 triangles and 33,072 pixels and land CRC `205046bf`. Entry 0, which the land never draws, is the outline the build derives one ring out from whichever sprite is in use, so both markers keep an edge against the terrain without a third colour. Two faults came out of the first build. The sprite choice read `TC_MOUSE_LEFT | TC_MOUSE_RIGHT`, so a middle drag, which is the press that pivots on the land, kept the idle marker and never showed the crosshair; the mask now names the middle bit. And the user judged both markers too large at 32 by 32, so they are 16 by 16 with the pick at 7.5 screen pixels rather than 15.5. They were not redrawn by hand: they were taken from the two PNGs again and reduced 2 by 2, a block surviving when any of its four pixels is at least half opaque, and the check on that method is that it regenerates the 32 by 32 grids with exactly the ink they were committed with, 124 pixels for the frame and 212 for the crosshair. The middle button's fix is proved by a control rather than by inspection: a throwaway build with the middle bit taken out of the mask draws one recorded middle-held session with a different sprite and nothing else, 27,788 triangles and `5d6673ba` against 27,836 and `b80d95aa`, the camera identical because the mask cannot touch it, while the same control reproduces the right-button and left-button sessions to the byte at `24813` and `d4aa354d`, and `23614` and `0b12dfdc`, which is what says the change reaches the middle and nothing else. All six scripted lands draw what they drew before the cursor changed, and the reason is worth keeping: the cursor is drawn only when the camera is driven, and `terrain_host` hands a report to `tc_mouse` only when it carries something, so a scripted run draws no cursor at all and the cursor work is invisible to that baseline by construction rather than by luck. The recorded sessions were rebaselined, the drag to `TRIS=20201 PIXELS=28738 CRC=86406394` and the pattern to `24765` and `c8030604`, the cursor costing 113 and 128 fewer triangles a frame than the 32 by 32 pair did. AddressSanitizer and UndefinedBehaviorSanitizer are clean on the scripted, both recorded and middle-held runs, with the same CRCs as the optimized build. The core was not rebuilt: this is the AE350 program alone. Over two-wire the board drew the scripted run to `CRC=7511d71e` from land CRC `205046bf`, matching the PC, in a mean 29.6 ms a frame and at most 35.7 ms against a 37.8 ms period, and the recorded drag to `TRIS=20201 PIXELS=28738 CRC=86406394`, also matching, in a mean 28.8 ms and at most 37.1 ms, with zero late line fetches in both. The user flew it and passed it, and the one thing the halving left in his hands is the weight it gives each marker: a one-pixel line cannot be halved, so the frame's border stays one pixel while the crosshair's arms stay two, because two is what its source bars are, and the held marker therefore reads heavier than the idle one where a strict half scale would have thinned its arms to one. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order with no retired ids, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The user has said he will name the next cycle, so this is a handover rather than a plan. Open and in his hands from this cycle: whether the crosshair's arms should be thinned to one pixel so the two markers weigh the same, which is a redraw rather than a downsample and which he has seen and accepted as it stands. Open and in his hands from the last: whether a middle press that misses the island should stop rotating the camera, which is the original's rule, or keep turning about the focus it had, which is what this camera has done since entry 16; and whether a new pivot should ease in over about a second the way the original's does, where this one jumps there as it presses. Flying to a clicked point is still the obvious next use of a pick that exists and is checked, and it wants the original's animation taken with it. The keyboard is still the stated next want, gated on TinyTang gaining keyboard forwarding from the Tiny89 work, with this program's decoder reading only frame type 0x16 as six bytes of mouse and discarding unknown types safely, so a new type is fine and a re-used one is not. The pipe guard in TinyTang is still the one defect either project carries, `pointer_frame()` holding the transmit lock while a host owns the link. Pinning a CRC per recorded input sequence in a tool is owed more strongly each cycle: entries 16, 20, 21 and 22 all leave driven-run figures that only the log records. The level-of-detail idea stays parked with a measured price beside it, the unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- THIRD_PARTY.md
- firmware/terrain/terrain.c
- firmware/terrain/terrain.h
- tools/convert_land.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 23 COMMIT Unreleased 2026-10-15T12:13:52-07:00

#### Coming From:

Unreleased 35e5f46

#### Purpose:

Make the cursor honest about what it is doing: draw it on whole framebuffer pixels so its one-pixel lines stay one pixel, give it the tile set's own green and red instead of the land colours the shading table substituted, and hand a mouse report to the cursor when it arrives rather than when it carries something, so letting a button go reaches it.

#### Outcome:

The user flew entry 22's cursor and reported three things, and a fourth fell out of the first. The cursor was drawn at sub-pixel positions: its midpoint is 7.5 screen pixels and a left press draws it where the held point projects, which is an arbitrary Q4 value, so its edges landed on pixel centres and the fill rule, which keeps a pixel whose centre lies on a triangle's edge (`fpga/raster.sv` fills where all three edge functions are at least zero), made ties of them. Measured on the idle frame it was 17 by 17 with the left and top ink border one pixel and the right and bottom two, and the phase that produced it moved with every click, which is the partly-one-pixel, partly-two-pixel cursor the user saw. Snapping every run to a whole pixel fixed it: the sprite is exactly 16 by 16 with one-pixel lines on all four sides, and the held crosshair's ink comes to exactly 80 pixels, which is the source sprite's own count, so it renders one to one with nothing added or lost. The second finding is that the cursor's colours never reached the screen at all. The shading path mixes a triangle's corner colours and looks the result up in the 32 KB table, whose candidates were the land's entries alone, so the tile's green `0x00c000` came out as land entry 71, `0x5f6a21`, and its red `0xff0000` as entry 164, `0x896b3c` -- an olive frame and a brown crosshair -- and the two palette entries the land gave up in entry 22 were in effect unused. The fix admits the cursor's two entries as candidates beside the land's, with ties going to the land, and the check that it costs the island nothing is that the change applied by itself left all six scripted lands byte-identical; across the table 3,243 of 32,768 colours answer differently, all of them nearer the cursor's green or red than any of the land's 237, and none occurs in what the island draws. The cursor's fill is now entry 17 and, held, entry 18, and its outline still comes out the land's nearest near-black, entry 19, because entry 0 was deliberately not admitted, as admitting black would let the island's darkest terrain snap to it. The third finding is the bug the user found: letting go of the left or middle button without moving the mouse left the red crosshair up until the mouse moved again. Neither front-end was at fault in the renderer; both handed a report to the mouse only when it carried something, the board's `input_frame` returning early on `dx == 0 && dy == 0 && wheel == 0 && buttons == 0` and the host skipping a record whose fields were all zero, and the board's recorded path could not express a release at all because `if (in_buttons[frame])` treats zero as no record. A report is now handed over when one arrived, not when it carried something -- a per-frame `seen` flag in both, and a `live_report` for the board's link -- since the buttons are a level and the movement a delta and the report that lets a button go carries neither. It was reproduced on the PC before it was fixed: a session pressing left at frame 0 and releasing at frame 10 still wore the crosshair at frame 15, 80 pixels of entry 18 and none of 17, with `INPUT=1`, and after the fix the same frame is the idle frame, 60 pixels of entry 17 and no crosshair, with `INPUT=2`. The user also asked for one blue for the ocean, so every sea row now takes entry 16, `0x1c4a6a`, the deepest of the ramp, where it took a ramp of eight; entries 9 to 15 are consequently unused, seven entries the land could fit its vertices to and which the texture quality the user has complained of could use. This entry also corrects entry 22, which says the cursor's colours and its outline reach the screen as entries 17, 18 and 0: they did not, because the shading table mapped every one of them into the land, which is exactly what this entry fixes; the correction is recorded here rather than by rewriting a committed entry. The six scripted lands draw the frame CRCs their palette now gives, `5b022d0d` for Land 1 against `7511d71e` before, with triangles and pixels unchanged at 20,085 and 33,072, so the sea's colour moved and no geometry did; the recorded drag draws `20201` and `28580` with CRC `fc6ec0f4` and the pattern `24765` and `23730` with `7c20a6cc`. AddressSanitizer and UndefinedBehaviorSanitizer are clean with the same CRCs as the optimized build. The core was not rebuilt: the table is the program's, loaded into the fabric, so every change here is the AE350 program and the host twin. Over two-wire the board drew the scripted run to `CRC=5b022d0d` in a mean 29.6 ms a frame and the recorded drag to `20201` and `28580` with `fc6ec0f4`, both matching the PC with zero late line fetches, and the release session to `INPUT=2` and `CRC=f51f76f9`, which is the host's frame CRC for it and shows the board's own input path applies a release too. The user flew it and passed it, including the gesture that failed before, which also settles that TinyTang does send a report for a button change with no movement; had it not, the sprite would still have stuck and the gap would have been upstream rather than here. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` unchanged, checked that the reference's fast index and its records list the same ids in the same order with no retired ids, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The user has said he will name the next cycle, so this is a handover rather than a plan, and the first thing in his hands is now the best-value one: the seven palette entries the sea ramp gave up, 9 to 15, which the land could fit its vertices to instead of the 237 it has, and which speak directly to the texture quality he has called garbage. Open from this cycle: whether the crosshair's arms should be thinned to one pixel so the two markers weigh the same, since its source bars are two pixels of sixteen against the frame's one-pixel border, which the snapping did not change because it moved placement and not stroke. Open from before: whether a middle press that misses the island should stop rotating the camera, which is the original's rule, or keep turning about the focus it had, which is what this camera has done since entry 16, and whether a new pivot should ease in over about a second the way the original's does, where this one jumps. Flying to a clicked point is still the obvious next use of a pick that exists and is checked, and it wants the original's animation with it. The keyboard is still the stated next want, gated on TinyTang gaining keyboard forwarding from the Tiny89 work, with this program's decoder reading only frame type 0x16 as six bytes of mouse and discarding unknown types safely, so a new type is fine and a re-used one is not. The pipe guard in TinyTang is still the one defect either project carries, `pointer_frame()` holding the transmit lock while a host owns the link. Pinning a CRC per recorded input sequence in a tool is owed more strongly each cycle: entries 16 and 20 to 23 each leave driven-run figures that only the log records, and this entry adds `fc6ec0f4`, `7c20a6cc` and `f51f76f9` to that list. The level-of-detail idea stays parked with a measured price beside it, the unused Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/host.c
- firmware/terrain/main.c
- firmware/terrain/terrain.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 24 COMMIT Unreleased 2026-10-15T14:01:43-07:00

#### Coming From:

Unreleased 1500f52

#### Purpose:

Raise the frame rate by drawing the far field as a coarser mesh, after measuring that the command bus rather than the CPU sets the pace.

#### Outcome:

The orbit ran at about 27 frames a second with a stutter: a mean frame of 29.5 ms and a worst of 35.6, past the 33.3 ms of two vertical blanks, so some frames showed a third blank later. The previous cycle's work had left the CPU as the only suspect, and the first measurement took the emission out of it: a null-target build put sending a frame's commands at 10,847 us, 39 per cent of the frame, for 80,340 words at about 101 A25 cycles each, and AE-002's drain rate of one word per twelve bus cycles, about six million words a second, accounts for it exactly. A stream of uncached stores is limited by the bus into the fabric, so no amount of software reordering helps -- the idea of interleaving the stores with the triangle setup was refuted by AE-002 before it was built -- and the only lever left in software is sending fewer primitives. That is what this cycle built, twice. First a block of sixteen cells by sixteen was drawn as the two triangles of the quad its corners sit in when it lay beyond the depth at which a cell covers TC_MERGE_PIXELS screen pixels, and a block whose cells did not all draw was excluded so that a patch could not cover water with land. That gave 20,085 triangles down to 14,419, a mean frame of 21.8 ms and a steady 30 frames a second, but it also left 383 screen pixels a frame showing the sea where land should be: measured against an unmerged build, they are the patch's straight edge cutting the corners off land whose edge is the polyline of its boundary vertices, and 326 of the 383 sit against another, so where a ridge crosses a block's edge the cut is a real chunk rather than a sliver. The second build merges four cells a side instead of sixteen, and it dominates the first: 111 such pixels instead of 383, with 15,568 triangles against 14,419, and 9,925 on the driven camera where the first gave 14,004. The frame is 32,477 us with VBLMIN 1 and VBLMAX 2, so the mean is 30.8 frames a second and the lightest frames are shown after one blank, that is at 60. A straightness test on a group's boundary is available as a dial, measured at four cells: off, 111 pixels and 22 per cent fewer triangles; at one pixel, 54 pixels and 8.6 per cent; at half a pixel, 18 pixels and 4 per cent. It is off by default because the frame is what the merge is for, and the user, watching the board's HDMI, called the shoreline good at 111. Two related attempts were measured and rejected. Growing each side of a patch outward by the bulge of the group's own boundary was built and came out worse, 152 pixels against 111, because the bulge was taken along a screen axis and the sides of a grid-aligned group are not screen-axis-aligned once the camera has yawed; it is not in the tree, and the comment on merge_group records the attempt and why it failed so that the next agent does not repeat it. Reverting it left the accepted build byte for byte, which the frame CRC shows: ed8eb724. Fog was added, refined through five measured iterations and then removed at the user's instruction, and the reasons are worth keeping because they close the question rather than leaving it open. A fade toward the sky steps, through the shading table's nearest-entry search, across colours the land's palette does not hold, whose nearest entries are browns, and it came out as bands of mud; a fade toward the land's own palest colour is smooth but warm, and at full zoom-out that warm band is most of the screen; two stages fix both, but shifting the split makes the far field the sky's own colour, which is sea, land and air as one flat colour; and the sea's haze needs a real distance rather than a screen row, or it hazes the near water too. The decisive one is that with no per-pixel depth a saturated far field is a single flat colour, so fog here can only tint where it reaches saturation and can never conceal, which means it was never going to hide the 383 pixels -- and that is what settled it. Five defects were found by measurement rather than by reading, and each is worth the technique that found it: the fog's channel mask sat outside its shift, so the blend composed the wrong bits and the far field came out wearing the sky's darkest entries as a band of shadow; the whole sky ramp admitted to the shading table let a barely hazed dark land colour snap to a dark sky entry, which the same band showed; the sea's haze ramped on screen row, which underestimates distance, so the water behind the island stayed the darkest blue while the land beside it hazed; the derived sea distance divided by the drop below the horizon, which is zero on the horizon row itself, a division by zero that core-dumped the host and would have hard-faulted the AE350 mid-run; and the bounding patch's bulge, above. The verification is the project's usual chain. The six scripted lands and both recorded sessions draw the frame CRCs their merge now gives, all of them reproduced byte for byte when the merge was removed by a build-time constant, and the board matches terrain_host on every run with zero late line fetches. The scripted run reports LAND=205046bf TRIS=15568 PIXELS=36048 DRAW=24288us MAX=32853us FINISH=0us STALLS=7750 VBL=1170 VBLMIN=1 VBLMAX=2 PERIOD=32477us LATE=0 CRC=ed8eb724, and the recorded pattern TRIS=9925 CRC=4004c0bf; the worst frame has 2.7 ms of margin against the two-blank budget where the unmerged build had none, and the delivered rate against the host twin is what the run script's own PASS checks. AddressSanitizer and UndefinedBehaviorSanitizer are clean on the scripted run and on the recorded one, with the same CRC as the optimized build. The core was not rebuilt: fpga/raster.sv is untouched, so this cycle is the AE350 program and the host twin alone, and a seed sweep would have produced the identical bitstream. PIXELS rose from 33,072 to 36,048, nine per cent, because four-cell quads over-cover their cells a little; the fabric's fill is idle when the CPU finishes, so it costs nothing measurable, but it is real. The user flew every build of this cycle on the board and accepted the fine-grain merge's shoreline. The core-syntax audit re-read .ai/core.md and .ai/core-syntax.md, inspected the complete .ai/ diff, confirmed .ai/core.md unchanged, checked that the reference's fast index and its records list the same ids in the same order with no retired ids, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The user has named the next cycle as optional, and the one thing it would buy is the last of the slivers: growing each side of a patch by the bulge of the group's boundary is right in principle and failed only because the bulge was measured along a screen axis, so measuring it along each side's own screen normal is a small change with a known target -- 111 pixels down toward none, at no command cost. The dial beside it needs no new work: TC_MERGE_FLAT at four cells was measured at off, one pixel and half a pixel with the frame and sliver each, and TC_MERGE_CELLS at eight gives 269 pixels and 20 per cent fewer triangles, so the trade is already charted for whoever tunes it. The texture quality the user has complained of is untouched by this cycle and its lever is unchanged: the sea's ramp gives up seven palette entries, 9 to 15, that the land could fit its vertices to instead of the 237 it has. Flying to a clicked point is still the obvious next use of a pick that exists and is checked, and it wants the original's animation with it. The keyboard is still the stated next want, gated on TinyTang gaining keyboard forwarding from the Tiny89 work, with this program's decoder reading only frame type 0x16 as six bytes of mouse and discarding unknown types safely, so a new type is fine and a re-used one is not. The pipe guard in TinyTang is still the one defect either project carries, pointer_frame() holding the transmit lock while a host owns the link. Pinning a CRC per recorded input sequence in a tool is owed more strongly each cycle: entries 16 and 20 to 24 each leave driven-run figures that only the log records, and this entry adds 4004c0bf and 9,925 to that list. The capture card the user attached to the machine returns pure black in every format offered, so the board's own HDMI was the judge this cycle; the host twin's frames are byte-identical to the board's by CRC, and turning one into a true-colour image, which the palette file holds packed in five bits a channel with blue in the low bits, is how this cycle looked at what it had drawn. The level-of-detail idea this cycle delivered is the first of its kind in the project and was parked with a measured price for three cycles; the Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/terrain.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 25 COMMIT Unreleased 2026-10-15T14:32:20-07:00

#### Coming From:

Unreleased 64d8fae

#### Purpose:

Stop the far-field merge's leaks from showing the sea, without covering the sea itself.

#### Outcome:

The user, watching the board, reported that the merge's slivers had become visible again now that the fog is gone, and proposed the fix: a ground plane in the land's own colour, laid under the island a little above the water line, so that anything the merge fails to draw shows a colour like the land rather than the sea's blue. Measuring the land's own palette first bore him out better than he claimed: of the 237 entries, 153 are yellow-brown and 84 green, every one between 25 and 75 degrees of hue, with no grey, no blue and nothing else at all, so the land's entire colour range is a single narrow band. The first build was his plane literally: two triangles whose extent is the land that actually draws, at the height of the lowest land, with the colour taken as the mean of the palette in the five bits a channel the renderer works in, answered with the entry nearest it. That removed every leak -- 111 pixels to 0 -- and covered 12,157 pixels of water inside the island's extent, which is what he had asked for. It also failed, and he found how: zoomed out, the ocean turned brown, and at a shallow angle he could see above the brown back into the distant sea. Reproduced on the host with the middle button dragged to its pitch limit and the wheel turned forty clicks out, the plane covered 16,066 pixels of ocean and the sea's own pixels fell from about forty thousand to 24,463; the frame's own measurement was worse, the CPU's FIFO stalls rising from 7,750 to 53,264 because the fabric was busy filling that plane, the worst frame going from 32,853 us to 34,222 and the period from 32,477 to 34,707, which is 30.8 frames a second down to 28.8. The reason is structural rather than a matter of tuning: the sea is drawn as a screen-space backdrop of rows, while a ground plane is a world-space quad, so at a shallow angle the quad's projection lands on top of the near ocean and replaces it, and beyond its far edge the rows show again. The second build keeps the colour and the height and drops the extent: a merged group that borders water lays its own ground under itself first, two triangles at the group's own four corners lowered to the lowest land, drawn immediately before its patch. The mask can then only ever appear under a group, never across the sea. Measured against the same grazing view, the ground's pixels fell from 16,066 to 576 and the sea's rose from 24,463 to 39,560, and on the board the stalls returned to 7,553 with a period of 33,313 us, VBLMIN 2 and VBLMAX 2, that is every frame in exactly two vertical blanks and a steady 30.0 frames a second, for 40 triangles and 185 pixels a frame more than the patches alone. The leaks are not fixed: they fall from 111 to 96, because the ground sits at the lowest land and its projection is therefore about a pixel away from the patch's at the depths groups merge at, and a margin of two pixels rounded the ground back only part of the way. Those leaks are 26 more than the user was told to expect, and are the next thing to try: the ground is grown past the group from its own middle, and the test that decides whether a group needs one looks only at the four cells directly beside it, so a group at a diagonal shore may be missed. A defect of this cycle's own making was found while auditing rather than by a crash: the script that removed the fog last cycle sliced out two lines that were not fog, the assignments of the shading table pointers, and those are read by the near-plane clip fan. That path never runs in the orbit, which is why every frame CRC still matched and nothing ever faulted, but zooming in is what reaches it, and it would have dereferenced a null pointer on the board. They are restored. AddressSanitizer and UndefinedBehaviorSanitizer are clean. The board PASSes with LATE=0 and a frame CRC matching terrain_host, and fpga/raster.sv is untouched, so no seed sweep was needed. The core-syntax audit re-read .ai/core.md and .ai/core-syntax.md, inspected the complete .ai/ diff, confirmed .ai/core.md unchanged, checked that the reference's fast index and its records list the same ids in the same order with no retired ids, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The leaks are the open work and their shape is known: 96 pixels, from groups whose ground quad is either not laid or laid a pixel off, so the two things to try are the diagonal neighbours in the test that decides whether a group borders water and a margin that follows the group rather than the screen middle. The user has not judged this build yet; he flies every build, and his report will say whether a steady 30 with 96 pixels is better than 111 with the occasional frame at 60. The texture quality he has complained of is untouched, and its lever is unchanged: the sea's ramp gave up seven palette entries, 9 to 15, that the land could fit its vertices to, and the measurement of the land's hue band now says exactly what they would be spent on, the band being 50 degrees wide with nothing outside it. Flying to a clicked point is the obvious next use of a pick that exists and is checked, and it wants the original's animation with it. The keyboard is still the stated next want, gated on TinyTang gaining keyboard forwarding from the Tiny89 work, with this program's decoder reading only frame type 0x16 as six bytes of mouse and discarding unknown types safely, so a new type is fine and a re-used one is not. The pipe guard in TinyTang is still the one defect either project carries, pointer_frame() holding the transmit lock while a host owns the link. Pinning a CRC per recorded input sequence in a tool is owed more strongly each cycle: entries 16 and 20 to 25 each leave driven-run figures that only the log records, and this entry adds the grazing-view figures, 16,066 against 1,318, which is why the host could confirm the user's report without the capture card, whose HDMI input still returns pure black to this machine in every format it offers. The Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/terrain.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 26 COMMIT Unreleased 2026-10-15T14:36:18-07:00

#### Coming From:

Unreleased af62129

#### Purpose:

Put the renderer back to what it was before the far-field merge, on the user's judgement that a level of detail at distance is the wrong approach to this renderer's problems.

#### Outcome:

The user, having flown the merge, the fog and the ground in turn, called the whole direction wrong and asked for the renderer as it was before it. What that means exactly is commit 1500f52, the state entry 23 left: the cursor, the sea's single blue, the release fix and the shading table's own assignments, with no merge, no fog and no ground. Both files the cycle touches were taken from it, firmware/terrain/terrain.c and README.md, and the log was not, so entries 24 and 25 remain as the record of what was tried and what it measured. The check that the revert is exact is the strongest this project has: the six scripted lands and both recorded sessions draw the frame CRCs they drew at entry 23, Land 1's 5b022d0d from land CRC 205046bf at 20,085 triangles and 33,072 pixels, byte for byte, from a renderer whose merge, ground plane and bounding attempts are absent rather than disabled. The board PASSes the scripted run at that same CRC with LATE=0 and zero late line fetches. The price is the one the merge was paying for, and it is visible in the same run: the mean period goes from 32,477 us to 38,012 and VBLMAX from 2 to 3, so the orbit runs at about 26 frames a second with occasional frames shown a blank late, where the merge held a steady 30. Nothing else is lost, because the merge's cycle touched nothing else: the core was never rebuilt, fpga/raster.sv is untouched, and the shading table assignments that the near-plane clip fan reads, which the fog's removal had taken out and entry 25 restored, are part of 1500f52 and so are in place. Two pieces of knowledge from the abandoned work are worth keeping and live only in the log now, since the code that carried them is gone. The land's palette is a single narrow band: of its 237 entries, 153 are yellow-brown and 84 green, every one between 25 and 75 degrees of hue, with no grey, no blue and nothing outside it. And the reason none of the three ways of stopping the merge's slivers earned its place is that the win and the sliver are one mechanism: the saving comes from drawing a group as two triangles instead of thirty-two, and the sliver from those two triangles cutting the corners off land that is never flat enough to make the cut harmless at block granularity, while at four-cell granularity the win itself shrinks to the point that the flattening test which removes the slivers also removes the merge. AddressSanitizer and UndefinedBehaviorSanitizer are clean on the reverted renderer. The core-syntax audit re-read .ai/core.md and .ai/core-syntax.md, inspected the complete .ai/ diff, confirmed .ai/core.md unchanged, checked that the reference's fast index and its records list the same ids in the same order with no retired ids, and validated this entry's six sections, sequential numbering, prose, Status values and the 100-entry limit.

#### Next Steps:

The user has said he will name the next cycle. The texture quality he has complained of is the most likely candidate and its measurement is now in hand: the land is 237 entries inside a 50 degree hue band with nothing outside it, and the sea's ramp gave up seven entries, 9 to 15, that could be spent sharpening exactly that band, which is a change to tools/convert_land.py and the palette layout rather than to the renderer. If distance detail is ever wanted again the log holds the measured ground for it: four-cell groups with the straightness test off give 22 per cent fewer triangles and 111 screen pixels of sea where land should be, the test at half a pixel gives 18 pixels for 4 per cent, and three ways of buying the pixels back were each measured and rejected, the best of them covering 590 pixels of ocean for three frames a second. Flying to a clicked point remains the obvious next use of a pick that exists and is checked, and it wants the original's animation with it. The keyboard is still the stated next want, gated on TinyTang gaining keyboard forwarding from the Tiny89 work, with this program's decoder reading only frame type 0x16 as six bytes of mouse and discarding unknown types safely, so a new type is fine and a re-used one is not. The pipe guard in TinyTang is still the one defect either project carries, pointer_frame() holding the transmit lock while a host owns the link. Pinning a CRC per recorded input sequence in a tool is owed more strongly each cycle: entries 16 and 20 to 26 each leave driven-run figures that only the log records. The capture card attached to this machine returns pure black to it in every format it offers, so the board's own HDMI remains the judge and the host twin, whose frames match the board's by CRC, is how this project looks at what it has drawn. The Bullet world removal from the PC playground (entry 6) and the J10 second SDRAM bank (entry 7) remain open, and GAME-001 still describes the 64 MiB route as J9's second chip select rather than the J10 bank.

#### Files Modified:

- README.md
- firmware/terrain/terrain.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---
