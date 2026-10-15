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
| What did Black & White need to run? | GAME | GAME-001 |
| Which open FPGA rasterizer implements an OpenGL-style fixed-function pipeline, and how fast is it? | GFX | GFX-001 |
| Where are the board, AE350, SDRAM, HDMI and toolchain facts? | (TinyNES) | TinyNES DEV-008, DEV-011 to DEV-013, BRD-010, BRD-011, PSX-005, TOOL-018 |

---

## 4. Fast lookup index

One line per live record, in the order of section 5. Retired ids are in section 8.

```yaml
OB-001: "openblack (github.com/openblack/openblack) is a GPL-3.0 C++23 reimplementation of Black & White's engine, about 47,000 lines, that runs on the user's own extracted game files; v0.1.0 of 2024-09-04 is its only release, read here at a243c6b; it depends on SDL2, bgfx, Bullet, OpenAL, EnTT, imgui, spdlog, glm, stb, minizip and cxxopts"
OB-002: "openblack draws everything through bgfx with 10 game shader programs (terrain, water, sky, object, object instanced, vegetation, sprite, line, footprint) plus imgui's; its terrain fragment shader takes up to nine texture samples a pixel and its water reflects a second rendering of the scene"
OB-003: "openblack a243c6b2 built on this PC and run on the user's patched Black & White draws Land 1's landscape correctly with no villagers or creature, logging eight unimplemented script functions led by CreatePlannedAbode; one run peaked at 592 MB resident including the OpenGL driver, and the game's Data and Scripts are 241 MB"
GAME-001: "Black & White (2001) for Windows needed at least a 350 MHz Pentium II or K6-2, 64 MB of RAM, an 8 MB Direct3D (DirectX 7) card and 500 to 600 MB of disk; the Mac version a 333 MHz G3, 128 MB and an 8 MB OpenGL 1.2 card"
GFX-001: "Rasterix (github.com/ToNi3141/Rasterix) is a Verilog FPGA rasterizer with a mostly OpenGL 1.3 fixed-function pixel pipeline, up to two texture units and register combiners, vertex work in software, reported at 100 Mpixel/s and 200 Mtexel/s at 100 MHz; its licence has not been read"
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
  statement: "Built on this PC (Ubuntu, GCC 15.2, CMake 4.2, the ninja-multi-vcpkg preset) and run as openblack -g <install> -V on the user's Black & White installed under Wine 10.0 with official patches 1.1 and 1.2, in a 1280 by 1024 window through bgfx on OpenGL, openblack loaded Land1.txt by default and drew the landscape, which the user called perfect, with camera movement working, while villagers and the creature were absent. Its log reported eight script functions not implemented, by count: CreatePlannedAbode 86, CreateNewTownSpell 22, SetTownBeliefCap 18, CreateMist 17, SetTownUninhabitable 7, SetLandNumber 2, SetTownCongregationPos 1 and CreateTownVillager 1, and ALSA could not open the sound device (snd_pcm_dmix_open). After 4 minutes 22 seconds the process had used 72 seconds of CPU with vertical sync on, and its resident set peaked at 591,836 kB, a figure that includes the OpenGL driver's mappings. The installed game's Data folder is 233 MB, Scripts 7.7 MB and Audio 221 MB."
  consequence: "The terrain path that the Tang most needs is complete in openblack; the town and villager scripting is not, so a port would at first show the same empty land unless those functions are implemented. That buildings and villagers are absent because CreatePlannedAbode and CreateTownVillager do nothing is a lead from the log, not established. The 592 MB peak is not the game's own need: separating its data from the driver's is still to be measured, as is per-frame CPU work without vsync."
  sources:
    - "This project's build/run/openblack.log and build/run/time.log (not committed), the user's account of the window, and /proc/<pid>/status during the run"
    - "openblack a243c6b2: src/LHScriptX/FeatureScriptCommands.cpp (the not-implemented messages)"
  verification: "Observed on 2026-10-14 (core-log entry 2) on this PC with the user watching; one run, so the CPU and memory figures are a first look, not a measurement."

- record_id: GAME-001
  kind: EXTERNAL
  topic_id: GAME
  title: "Black & White's published system requirements"
  status: SOURCED
  verified_date: 2026-10-14
  statement: "Listings of Black & White's minimum requirements for Windows give a 350 MHz Pentium II or AMD K6-2, 64 MB of RAM, an 8 MB Direct3D 3D accelerator with DirectX 7 compatible drivers, Windows 95, 98, ME or 2000 with DirectX 7.0a, and 500 MB (Computer Hope) or 600 MB (GameSystemRequirements) of disk; the Mac version lists Mac OS 8.6, a 333 MHz G3, 128 MB of RAM, 750 MB of disk and an 8 MB OpenGL 1.2 card. Players reported the game running poorly at the minimum."
  consequence: "The minimum is the floor for a faithful port: about 64 MB of memory for the game and 8 MB for graphics, which the dock's 32 MB SDRAM (TinyNES BRD-010) cannot hold and the module's 1 GiB DDR3 (TinyNES PSX-005) could, and hundreds of MB of data to bring from the card."
  sources:
    - "https://www.computerhope.com/games/games/baw.htm"
    - "https://gamesystemrequirements.com/game/black-and-white"
  verification: "Looked up online on 2026-10-14 (core-log entry 1); secondary listings, not the box, so SOURCED."

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
last_reviewed: 2026-10-14
```

---

## 8. Retired record ids

None.
