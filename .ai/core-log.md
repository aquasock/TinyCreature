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
