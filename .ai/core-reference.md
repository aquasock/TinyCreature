# TINYCREATURE TECHNICAL REFERENCE

> **Project:** TinyCreature
> **Purpose:** The authoritative lookup for externally defined facts this project depends on: the engines, renderers and games it builds on, the Tang Console board and its AE350, and the behaviour of the tools.
> **Authority:** Per `.ai/core.md`, consult this file before looking anything up online, and open the record behind any hardware fact before acting on it. A record is authoritative to the extent of its `status` and cited `sources`. When a better or newer source is found online, add or revise a record and notify the user.

This file records what an outside source (a datasheet, schematic, vendor SDK, vendor tool, or external repository) says, plus hardware observations that confirm or refute it. It does not record project history, build results, or discussion; those belong in `core-log.md`. It does not record project design choices unless an external fact forces them.

The board, its FPGA and AE350, the SDRAM, the HDMI path, the toolchain and TinyTang's contracts are already recorded in TinyNES's `.ai/core-reference.md` (https://github.com/aquasock/TinyNES) and TinyTang's (https://github.com/aquasock/TinyTang). They are cited from there by record id, not copied (section 7).

---

## 1. AI operating rules

```yaml
schema_version: 1

record_kinds:
  - DEVICE      # FPGA silicon: part, revision, identification
  - BOARD       # Tang Console 138K board: pins, parts, clocks, wiring, power
  - SOC         # BL616 microcontroller: address map, USB block, power domains
  - USB         # USB behaviour on this board: roles, VBUS, speeds, stack lifecycle
  - FLASH       # BL616 flash layout and boot image format
  - PROTOCOL    # the BL616 <-> loaded FPGA core UART contract
  - EXTERNAL    # interface contracts owned by other projects
  - TOOLCHAIN   # Bouffalo SDK, CherryUSB, Gowin EDA, RISC-V toolchain

statuses:
  VERIFIED:   "Primary source cited AND confirmed on this project's hardware or tools."
  SOURCED:    "Primary source cited; not yet confirmed on this project's hardware or tools."
  INFERRED:   "Derived from secondary sources, reverse inspection, or consistent observation; no primary source. Flag before relying on it."

rules:
  - "One fact or one tightly coupled fact group per record."
  - "Every record cites at least one source with enough detail to re-check it: repository path plus commit, file, symbol, register name, or tool version."
  - "Separate what the source says (statement) from what it means for this project (consequence)."
  - "Diagnostic or implementation limits chosen by this project are never recorded as standard or device limits."
  - "A record holds what is true now. When a fact changes or proves wrong, edit the record in place: revise statement and consequence, update verified_date and sources, and end verification with 'Revised <date> (core-log entry N): <what changed>'. Git and core-log.md keep the history; this file does not."
  - "Before acting on a record, check that the code paths and symbols it cites still exist; fix the record in the same cycle if they do not."
  - "Never reuse a record_id. When a record is folded into another, or split, move its id to the retired-id table in section 8 with the record that now holds its facts, after checking that every fact still true has been carried across."
  - "An INFERRED record must say how it was inferred, in verification."
  - "A negative result is a fact. Record what the hardware cannot do with the same rigour as what it can, and say how many attempts established it. An open defect may be recorded as its established facts and ruled-out causes, with any lead labelled as a lead."
  - "When an online lookup was needed because this file had no answer, add the finding here with the existing syntax, then notify the user if the source is newer or more valid than a record already here."
  - "Use technical names (GW5AST-138, BL616, CDC, OTG). The user's conversational names are not used in this file."
```

---

## 2. Topic catalog

Topic IDs are the `record_id` prefix. An entry reserves a name; it does not claim coverage.

```yaml
- topic_id: OB
  name: "openblack (external project)"
  description: "The open-source reimplementation of Black & White's engine: its licence, code, dependencies, renderer and what it needs from a platform."

- topic_id: GAME
  name: "Black & White (2001)"
  description: "The original game as published: its requirements, data and behaviour, as the target this project measures itself against."

- topic_id: GFX
  name: "FPGA rasterizers"
  description: "Existing open FPGA graphics pipelines considered as references for this project's renderer: what they implement and how fast they are."

- topic_id: AE
  name: "The AE350 on this project's Tang32 core"
  description: "What this project has measured of the AE350 and its bus ports in its own core, beyond what TinyNES's reference records: address reach and access costs."

- topic_id: TOOL
  name: "Open toolchain behaviour"
  description: "How Yosys, nextpnr and Apicula treat this project's designs, where that differs from what a reader would assume."

- topic_id: PROV
  name: "Provenance and attribution"
  description: "The licences and notices that follow from the code this project builds on or carries."
```

---

## 3. Active routing

| Question | Consult first | Fast records |
|---|---|---|
| What is openblack, under what licence, and what does it need from a platform? | OB | OB-001 |
| How does openblack render, and which shader programs would a fixed-function back end have to cover? | OB | OB-002 |
| How complete is openblack on the real game, and what did a first run use? | OB | OB-003 |
| How is a .lnd landscape laid out, and how does openblack colour a terrain vertex? | OB | OB-004 |
| What did Black & White need to run? | GAME | GAME-001 |
| Which open FPGA rasterizer implements an OpenGL-style fixed-function pipeline, and how fast is it? | GFX | GFX-001 |
| Which EXTS addresses reach the fabric, and what do bus and SDRAM accesses cost the A25? | AE | AE-001, AE-002 |
| Does Yosys map multiplies to the GW5A's DSP blocks? | TOOL | TOOL-001 |
| Where are the board, AE350, SDRAM, HDMI and toolchain facts? | (TinyNES) | TinyNES DEV-008, DEV-011 to DEV-013, BRD-010, BRD-011, PSX-005, TOOL-018 |

---

## 4. Fast lookup index

One line per live record, in the order of section 5. Retired ids are in section 8.

```yaml
OB-001: "openblack (github.com/openblack/openblack) is a GPL-3.0 C++23 reimplementation of Black & White's engine, about 47,000 lines, that runs on the user's own extracted game files; v0.1.0 of 2024-09-04 is its only release, read here at a243c6b; it depends on SDL2, bgfx, Bullet, OpenAL, EnTT, imgui, spdlog, glm, stb, minizip and cxxopts"
OB-002: "openblack draws everything through bgfx with 10 game shader programs (terrain, water, sky, object, object instanced, vegetation, sprite, line, footprint) plus imgui's; its terrain fragment shader takes up to nine texture samples a pixel and its water reflects a second rendering of the scene"
OB-003: "openblack a243c6b2 built on this PC and run on the user's patched Black & White draws Land 1's landscape correctly with no villagers or creature; a repeatable three-run profile measures about 361 MiB peak RSS with bgfx Noop and 532 MiB with Vulkan, so the current engine does not fit in 64 MiB"
OB-004: "openblack a243c6b2 reads a .lnd as a 1052-byte header with a 32 by 32 block lookup table, low-resolution textures, 2520-byte blocks of 17 by 17 eight-byte cells, 3076-byte countries, 0x20002-byte 256 by 256 B5G5R5A1 materials, then 64 KiB noise and bump maps; a cell outside every block is all zero but fullWater; a vertex's materials come from its country at (altitude + noise) mod 256"
GAME-001: "Black & White (2001) for Windows needed at least a 350 MHz Pentium II or K6-2, 64 MB of RAM, an 8 MB Direct3D (DirectX 7) card and 500 to 600 MB of disk; the Mac version a 333 MHz G3, 128 MB and an 8 MB OpenGL 1.2 card"
GFX-001: "Rasterix (github.com/ToNi3141/Rasterix) is a Verilog FPGA rasterizer with a mostly OpenGL 1.3 fixed-function pixel pipeline, up to two texture units and register combiners, vertex work in software, reported at 100 Mpixel/s and 200 Mtexel/s at 100 MHz; its licence has not been read"
AE-001: "In the Tang32 core the AE350's EXTS port carries 0xe8018000 to 0xe801ffff to the fabric: the raster unit decoded there answers its ID and runs; 0xe8020000 and above are untested"
AE-002: "Measured on the Tang32 core at 750 MHz: an uncached EXTS write costs about 120 A25 cycles back to back and a register read about 102, four posted writes amid other work about 23, and a cached store missing into the SDRAM about 78 a word, about 620 a 32-byte line; the terrain program's time is per-cell and per-triangle work, not its vertex records"
TOOL-001: "Yosys 0.69+260's synth_gowin infers DSP multipliers only for -family gw1n and gw2a; for gw5a every multiply becomes LUT and carry logic"
```

---

## 5. Records

```yaml
- record_id: OB-001
  kind: EXTERNAL
  topic_id: OB
  title: "openblack: what it is, its licence, size and dependencies"
  status: VERIFIED
  verified_date: 2026-10-14
  statement: "github.com/openblack/openblack describes itself as an open source reimplementation of Black & White (2001) in modern C++ with modern rendering engines (OpenGL, Vulkan), and says the original game assets are needed and are not provided, with instructions to extract them from the official installer and patches 1.10 and 1.2. Its licence file is the GNU GPL version 3. CMakeLists.txt sets CMAKE_CXX_STANDARD 23 and project version 0.1.0; vcpkg.json lists sdl2, imgui, spdlog, glm, stb, entt, cxxopts, openal-soft, drlibs, bgfx (multithreaded), bullet3, minizip and gtest. src/ and components/ hold about 47,000 lines of .cpp and .h, the components being readers for the game's formats (anm, glw, l3d, lnd, morph, pack, ScriptLibrary). src/ starts no threads of its own (no std::thread or std::async) and uses std::filesystem mostly for paths, with five exists calls and two directory iterators. The README calls its pre-built binaries experimental. v0.1.0, published 2024-09-04, is its only release; the default branch was pushed on 2026-10-15 and read here at commit a243c6b of 2026-10-03."
  consequence: "This project would port openblack rather than write the game from scratch, using the user's own copy of the game for assets, and is GPL-3.0 throughout so the port, the engine around it and the HDL can mix. On the AE350 the platform pieces to replace are SDL2's window and input, OpenAL's sound, std::filesystem's file access and bgfx's renderer back end (OB-002); our RISC-V toolchain already runs C++ with exceptions and RTTI on the A25 (TinyNES TOOL-018). How complete the game is under openblack has not been established."
  sources:
    - "https://github.com/openblack/openblack at a243c6b: readme.md, license, CMakeLists.txt, vcpkg.json, src/, components/"
    - "GitHub API for openblack/openblack (licence GPL-3.0, pushed_at 2026-10-15) and its releases (v0.1.0, 2024-09-04)"
    - "https://gamingonlinux.com/2024/09/black-white-2001-open-source-game-engine-sees-a-first-release"
  verification: "Read from a shallow clone on 2026-10-14 (core-log entry 1). Revised 2026-10-14 (core-log entry 2): built on this PC from tools/fetch_openblack.sh's pinned a243c6b2 with its vcpkg submodule at 5de6d1ff and the ninja-multi-vcpkg preset, 182 of 182 steps, and run on the user's game (OB-003), so VERIFIED."

- record_id: OB-002
  kind: EXTERNAL
  topic_id: OB
  title: "openblack's renderer: bgfx and ten shader programs"
  status: SOURCED
  verified_date: 2026-10-14
  statement: "openblack's assets/shaders hold bgfx shaders for terrain, water, sky (fragment only), object, object_instanced, object_hm_instanced, vegetation, vegetation_hm_instanced, sprite, line, line_instanced and footprint_instanced, plus imgui's. fs_terrain.sc blends two materials for each of three weights from a texture array, six texture2DArray samples, then multiplies by a bump map, a small bump map within 200 units of the camera, and a footprint texture, up to nine samples a pixel, and discards where the water alpha is 0. fs_water.sc mixes a diffuse texture with a projected reflection texture by an alpha texture; its comment says the original game rendered parts of the scene upside down in the back buffer and alpha-blended the ocean over it. src/ calls bgfx for textures, vertex layouts, views, transforms, state, instance data and submit."
  consequence: "A fixed-function FPGA renderer with two texture units cannot run the terrain shader in one pass, so a port would bake each terrain block's blended texture when the terrain changes and draw terrain with one or two textures, and water would need the scene drawn twice or the original's flipped-scene trick. Because the set of programs is small and fixed, a bgfx back end for this hardware can recognise each program and map it to a hardware mode instead of implementing a general shader language."
  sources:
    - "https://github.com/openblack/openblack at a243c6b: assets/shaders/*.sc (fs_terrain.sc, vs_terrain.sc, fs_water.sc), src/Graphics/Renderer.cpp"
  verification: "Read on 2026-10-14 (core-log entry 1); not built, so SOURCED."

- record_id: OB-003
  kind: EXTERNAL
  topic_id: OB
  title: "openblack a243c6b2 on Black & White 1.2's Land 1: what runs and what is missing"
  status: VERIFIED
  verified_date: 2026-10-14
  statement: "Built on this PC (Ubuntu, GCC 15.2, CMake 4.2, the ninja-multi-vcpkg preset) and run as openblack -g <install> -V on the user's Black & White installed under Wine 10.0 with official patches 1.1 and 1.2, in a 1280 by 1024 window through bgfx on Vulkan, openblack loaded Land1.txt by default and drew the landscape, which the user called perfect, with camera movement working, while villagers and the creature were absent. Its log reported eight script functions not implemented, by count: CreatePlannedAbode 86, CreateNewTownSpell 22, SetTownBeliefCap 18, CreateMist 17, SetTownUninhabitable 7, SetLandNumber 2, SetTownCongregationPos 1 and CreateTownVillager 1. A later deterministic profile at 1280 by 720, with logging off and OpenAL Soft's null driver, ran three one-frame startup cases, three 3,601-frame no-vsync cases and three 601-frame realtime cases. The Noop backend averaged 360.76 MiB peak RSS, 357.08 MiB sampled peak PSS, 356.70 MiB sampled peak private memory and four threads; Vulkan averaged 531.87 MiB RSS, 487.30 MiB PSS, 463.33 MiB private memory and ten threads. After subtracting startup CPU time, Vulkan's no-vsync cases averaged 0.861 ms per frame and its realtime cases had a median 14.45 ms per frame. The installed game's Data folder is 233 MB, Scripts 7.7 MB and Audio 221 MB."
  consequence: "The terrain path that the Tang most needs is complete in openblack; the town and villager scripting is not, so a port would at first show the same empty land unless those functions are implemented. That buildings and villagers are absent because CreatePlannedAbode and CreateTownVillager do nothing is a lead from the log, not established. The Noop profile establishes that the present engine and asset representation does not fit in 64 MiB even before a real renderer, but it does not identify which allocations can be streamed or compacted. The no-vsync loop finishes too quickly to run openblack's normal 100 ms game turns, while the realtime CPU number includes Vulkan driver and render-thread work; neither number by itself predicts AE350 game-logic cost."
  sources:
    - "This project's build/run/openblack.log and build/run/time.log (not committed), the user's account of the window, and /proc/<pid>/status during the run"
    - "This project's tools/profile_openblack.sh and generated build/profile-openblack/20261014T222244-0700/summary.tsv, steady-cpu.tsv and realtime-cpu.tsv (generated results not committed)"
    - "openblack a243c6b2: src/LHScriptX/FeatureScriptCommands.cpp (the not-implemented messages)"
  verification: "Observed on 2026-10-14 (core-log entry 2) on this PC with the user watching. Revised 2026-10-14 (core-log entry 3): tools/profile_openblack.sh completed all 15 cases against binary SHA-256 45436b81416408ae7f3b5c7563f62ba27c9d982f0927d9be1d35d5a7b45b18b2; generated results remain under the git-ignored build/profile-openblack/. The Vulkan identification was corrected from OpenGL by re-reading src/main.cpp and src/Graphics/Renderer.cpp at the pinned commit."

- record_id: OB-004
  kind: EXTERNAL
  topic_id: OB
  title: "openblack's .lnd layout and terrain vertex colour"
  status: VERIFIED
  verified_date: 2026-10-15
  statement: "LNDFile::ReadFile reads, in order, a 1052-byte LNDHeader (blockCount, a 0x400-byte lookUpTable, materialCount, countryCount, blockSize 2520, materialSize 0x20002, countrySize 3076, lowResolutionCount), lowResolutionCount textures each of a 20-byte header whose size field counts its own four bytes plus the texels, blockCount - 1 LNDBlocks, countryCount LNDCountries, materialCount LNDMaterials and 0x20000 bytes of noise then bump map, each 256 by 256 R8. An LNDBlock starts with 17 by 17 LNDCells (r, g, b, luminosity, altitude, saveColor, a properties byte of country in bits 0 to 3, hasWater 4, coastLine 5, fullWater 6, split 7, and sound flags) with blockX and blockZ at byte offsets 2324 and 2328. An LNDCountry is a type and 256 LNDMapMaterials of two material indices and a coefficient. LandIsland::GetCell finds cell (x, z) through lookUpTable[(x >> 4) << 5 | (z >> 4)], a 1-based block index, and cell (x & 15) * 17 + (z & 15), only the first 16 rows and columns of a block being used; outside every block, or beyond 511, it returns k_EmptyCell, all zero but fullWater. GetNoise takes a u8vec2, so the noise index (x * 256 + z) wraps at 256 cells. LandBlock::BuildVertexList places a vertex at 10 units a cell and 0.67 units an altitude step, takes its materials from country.materials[(altitude + noise) % 256], splits each cell into the triangles TL-TR-BR and TL-BL-BR, or BL-TL-TR and BL-BR-TR when split is set, and gives a vertex water alpha 0 for hasWater or fullWater and 0.5 for coastLine. fs_terrain.sc mixes each corner's two materials by its coefficient as a normalised u8, weights the three corners barycentrically, multiplies by mix(1, 2 * bump, bumpMapStrength) and by mix(0.25, clamp(2 * luminosity, 0.5, 1), skyType / 2), and discards a fragment whose interpolated alpha is 0."
  consequence: "tools/convert_land.py reads Land files by this layout and colours each vertex by the daylight case (skyType 2, bumpMapStrength 1) with each material reduced to its mean colour and the bump map to its mean, so the Tang's terrain colour approximates openblack's rather than reproducing its per-pixel texturing; a triangle with three water vertices is not drawn, as openblack discards it. Treating cells outside the blocks as dry land instead of fullWater draws slivers along the island's outer block edges."
  sources:
    - "openblack a243c6b2: components/lnd/include/LNDFile.h, components/lnd/src/LNDFile.cpp (LNDFile::ReadFile), src/3D/Implementations/LandIsland.cpp (GetCell, GetNoise, EmptyCell, k_HeightUnit, k_CellSize), src/3D/LandBlock.cpp (BuildVertexList, LandVertex), assets/shaders/fs_terrain.sc, assets/shaders/vs_terrain.sc"
  verification: "Read on 2026-10-15 (core-log entry 8). tools/convert_land.py parsed the user's Land1.lnd by this layout, every one of its 100 blocks' blockX and blockZ agreeing with the lookup table, and the Tang drew the result, which the user accepted as Land 1; the empty-cell rule was confirmed when the first conversion, which treated those cells as dry, drew the slivers described above."

- record_id: GAME-001
  kind: EXTERNAL
  topic_id: GAME
  title: "Black & White's published system requirements"
  status: SOURCED
  verified_date: 2026-10-14
  statement: "Listings of Black & White's minimum requirements for Windows give a 350 MHz Pentium II or AMD K6-2, 64 MB of RAM, an 8 MB Direct3D 3D accelerator with DirectX 7 compatible drivers, Windows 95, 98, ME or 2000 with DirectX 7.0a, and 500 MB (Computer Hope) or 600 MB (GameSystemRequirements) of disk; the Mac version lists Mac OS 8.6, a 333 MHz G3, 128 MB of RAM, 750 MB of disk and an 8 MB OpenGL 1.2 card. Players reported the game running poorly at the minimum."
  consequence: "The published minimum is a reference point for the port: about 64 MB of system memory plus 8 MB of graphics memory and hundreds of MB of data to bring from the card. The fitted J9 module physically carries two 32 MiB SDRAM chips, but TinyNES currently addresses only one because the second chip-select signal has not been identified (TinyNES BRD-010). OB-003 shows that current openblack does not fit even after both chips are enabled; a 64 MiB design requires asset streaming and compact runtime formats whose feasibility is not established. The module's 1 GiB DDR3 array (TinyNES PSX-005) remains the direct fallback."
  sources:
    - "https://www.computerhope.com/games/games/baw.htm"
    - "https://gamesystemrequirements.com/game/black-and-white"
  verification: "Looked up online on 2026-10-14 (core-log entry 1); secondary listings, not the box, so SOURCED. Revised 2026-10-14 (core-log entry 3): corrected the consequence to distinguish the fitted module's two physical 32 MiB chips from the one chip currently addressable, after re-reading TinyNES BRD-010."

- record_id: GFX-001
  kind: EXTERNAL
  topic_id: GFX
  title: "Rasterix, an OpenGL 1.3-style FPGA rasterizer"
  status: SOURCED
  verified_date: 2026-10-14
  statement: "github.com/ToNi3141/Rasterix describes a rasterizer for FPGAs in Verilog with a mostly OpenGL 1.3 compatible fixed-function pixel pipeline, at most two texture units and register combiners in hardware, its vertex pipeline in software, and two variants, RasterixIF with an internal framebuffer and RasterixEF with an external one; its README reports 100 Mpixel/s and 200 Mtexel/s at 100 MHz. A related project, RasteriCEr, targets iCE40 FPGAs with fewer features."
  consequence: "Shows that an OpenGL 1.x-class pipeline with the fill rate of the cards Black & White targeted fits an FPGA at about 100 MHz; this project's open flow closes pixel logic near 80 to 90 MHz on this board (TinyNES BRD-011, entry 34). It is a reference to study; its licence and resource use have not been read, so nothing from it may be used until they are."
  sources:
    - "https://github.com/ToNi3141/Rasterix README"
    - "https://github.com/ToNi3141/RasteriCEr README"
  verification: "Read online on 2026-10-14 (core-log entry 1) through search results, not from the repository; SOURCED."

- record_id: AE-001
  kind: DEVICE
  topic_id: AE
  title: "EXTS addresses that reach the fabric in the Tang32 core"
  status: VERIFIED
  verified_date: 2026-10-15
  statement: "TinyNES decodes the EXTS window in fabric from exts_addr[17:16], the UART at 0xe8000000 and its video unit at 0xe8010000, and nothing of its records establishes how far above that the AE350 forwards accesses to the EXTS port. In this project's core the raster unit decoded at exts_addr[17:16] == 01 with exts_addr[15] set, 0xe8018000 to 0xe801ffff, answered RASTER_ID 0x54435231, took 80,000 command writes a frame and served read-back reads on the board."
  consequence: "fpga/raster.sv lives at 0xe8018000, in the upper half of the video unit's 64 KiB, rather than at 0xe8020000, which no build has yet shown to reach the fabric. A later unit placed at or above 0xe8020000 must first be checked with a single register read on the board."
  sources:
    - "This project's patches/tinynes-tang32.patch (ae350_soc.sv video_hit, raster_hit), fpga/raster.sv, firmware/terrain/main.c (RASTER_ID check)"
  verification: "On this board on 2026-10-15 (core-log entry 9): the fabric and software terrain programs both passed their RASTER_ID check, and the fabric run drew 600 frames read back bit-exact through 0xe8018020 and 0xe8018024."

- record_id: AE-002
  kind: DEVICE
  topic_id: AE
  title: "A25 cycle costs of EXTS and cached SDRAM accesses in the Tang32 core"
  status: VERIFIED
  verified_date: 2026-10-15
  statement: "With the A25 at 750 MHz, the bus at 75 MHz, both caches on and the Tang32 core's ahb_sdram on J9, a profiling build of the terrain program measured with mcycle: 4,096 back-to-back stores to the raster unit's FIFO register 491,227 cycles (about 120 each), 4,096 reads of one of its registers 420,348 (about 102 each), 4,096 word stores through the D-cache to a 16 KiB array not yet cached 319,549 (about 78 each, about 620 per 32-byte line), and the four FIFO stores of one triangle inside the frame loop a mean 23 cycles over 2.4 million triangles."
  consequence: "Uncached EXTS stores are posted and overlap the CPU's other work, but drain at about one per 12 bus cycles, so a stream of them is limited to about 6 million words a second. A cache miss into the SDRAM costs on the order of a microsecond, and a renderer whose working set exceeds the 32 KiB D-cache (TinyNES DEV-013) pays it, but the terrain program is not bound by the vertex records of its walk: the walk touches them two rows at a time, and cutting the record from 24 bytes to 8, which the island is walked over once a frame, moved its mean frame by only 2.5 percent. The cost measured there is per-cell and per-triangle CPU work instead, which the fabric fill does not carry."
  sources:
    - "This project's firmware/terrain/main.c and terrain.c with the profiling builds described in core-log entries 9 and 10 (the throwaway builds are not committed), fpga/raster.sv, TinyNES f5011dd fpga/ae350_soc/ahb_sdram.sv"
  verification: "One profiling run on this board on 2026-10-15 (core-log entry 9), 120 frames; a single run, so the figures are representative, not bounds. Revised 2026-10-15 (core-log entry 10): the claim that the roughly 1.1 MB vertex walk was why a frame took about 38 ms was refuted, first by measuring a 24-byte to 8-byte record change as a 2.5 percent move of the mean frame and then by a per-phase mcycle profile that put the time in the cell walk and the triangle submission; the consequence now records what was measured."

- record_id: TOOL-001
  kind: TOOLCHAIN
  topic_id: TOOL
  title: "No DSP inference for GW5A in Yosys"
  status: VERIFIED
  verified_date: 2026-10-15
  statement: "yosys -p 'help synth_gowin' for Yosys 0.69+260 (git dcd59343b) in the OSS CAD Suite lists the DSP steps techmap +/mul2dsp.v and +/gowin/dsp_map.v only for -family gw1n or gw2a; synthesising this project's raster unit for gw5a used no MULT12X12, MULTALU27X18 or MULTADDALU12X12 cells."
  consequence: "Multiplies in this project's GW5A fabric are LUT and carry logic, so fpga/raster.sv builds its triangle setup products with a sequential radix-4 multiplier rather than relying on inferred DSP blocks; instantiating the DSP primitives by hand would need its own hardware check under Apicula."
  sources:
    - "Yosys 0.69+260 help synth_gowin; ~/oss-cad-suite/share/yosys/gowin/dsp_map.v"
    - "This project's build/tang32/nextpnr.log device utilisation (not committed)"
  verification: "Read and observed on 2026-10-15 (core-log entry 9): the Tang32 image with the raster unit reports 0 of each DSP cell type."
```

---

## 6. Record template

```yaml
- record_id: <TOPIC>-<NNN>
  kind: DEVICE | BOARD | SOC | USB | FLASH | PROTOCOL | EXTERNAL | TOOLCHAIN
  topic_id: <TOPIC>
  title: "Short noun phrase"
  status: VERIFIED | SOURCED | INFERRED
  verified_date: YYYY-MM-DD
  statement: "What the source says, with exact values and units"
  consequence: "What it means for this project, or where it is implemented"
  sources:
    - "Document or repository, revision/commit/path/symbol, URL"
  verification: "How and when it was confirmed, or why it is not yet confirmed; then any 'Revised <date> (core-log entry N): ...' notes"
```

---

## 7. Maintenance boundary

- Keep external facts, their sources, and their verification status here.
- Board, FPGA, AE350, SDRAM, HDMI, toolchain and TinyTang contract facts are kept in TinyNES's and TinyTang's references, which have measured them on this board; this file cites them by repository and record id and copies them only if one of those projects stops being a live source.
- Keep build results, failures, rationale, and chronology in `core-log.md`; cite a log entry number in `verification` instead of repeating it.
- Do not add speculative records for topics that have not been looked up. An unanswered question stays out of this file until a source answers it.
- Keep this file current rather than historical: when a record's source is replaced by a newer document or tool version, or its fact changes, revise the record in place and let git and `core-log.md` carry the history (section 1).
- A `core-syntax.md` audit is required whenever this file changes, per `.ai/core.md`.

```yaml
last_reviewed: 2026-10-15
```

---

## 8. Retired record ids

None.
