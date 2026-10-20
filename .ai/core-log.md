## 1 COMMIT Unreleased 2026-10-20T07:41:01-07:00

#### Coming From:

Unreleased 3048640

#### Purpose:

Roll the active log over to an archive at the user's request, ahead of its hundredth entry, and open the new log with a handoff that states the live project state.

#### Outcome:

The user asked for the rollover early, with 88 entries in the active log rather than 100. Those entries were archived to `archived_logs/core-log-2026-10-20T074053-0700.tar.gz`, whose single member is `core-log.md` with SHA-256 `099ff580f62f240ac25d5651eaa7437d48897cf5a3b600f866326c8fdc51435a`, identical to the log it was taken from and holding all 88 headings; the active log was then cleared and this entry written as its first. The board runs the archived log's entry 80 seed 5 core, `ae350_soc.bin` SHA-256 `23c0166497ddc081be8b4276b1b42d5c1b5833bef296c29a20f8d4581455309d` and `ae350_soc.fs` SHA-256 `13fdddc75f637fbb47abe716d67cc5f181e5206f53d80190b8ab30ef7c96d077`, at 78.98 MHz bus and 94.63 MHz pixel, flying the Celtic scene the user accepted. The source has gained seven units since that core: the packed land store and its read-back, the CPU cell trace and `tools/land_walk.py` model, the fabric cell walk against it, the CPU vertex trace and `tests/vert_model.sv`, the transform unit, the camera file and transform registers in the raster, and a sequential radix-4 multiplier. `tools/test_tang32_raster.sh` passes on Land 1 and Celtic: the land store reads back exactly, 21,223 and 26,542 cells match the model, 256 traced vertices match the CPU through the testbench model, the standalone unit and the raster's own registers, and the frames are unchanged at `293e6ccf` and `5c2808f5` and at `4bb0a03f` and `9013c700`. The current source synthesises at 20,633 `LUT4`, 9,121 `ALU`, 18,056 `DFFRE`, 1,767 `DFFCE` and 293 of 340 block RAMs and has not been placed and routed: the sequential transform is exact but takes about 208 clocks a vertex, 150 ms for the unique grid vertices and 295 ms for four corners of each drawn cell, so it would not make a usable frame and the board stays on seed 5. The walker's cell FIFO, the land vertex reads, the slot keys, the near-plane clip and the triangle assembly are not connected, so no terrain is drawn by the fabric. The archived log's entry 51 `BAD TINYCREATURE PIXELS` at 2,000 and 3,000 villager-sized cards is still open, as is the art queue: authored-tall plant sprites, grass as ground cover and the 13 dropped sprites if the tile store is widened. `tools/tang_power.py status` reported no USBRelay8 on USB at the rollover, so the bench cannot cycle the board until the relay is plugged back in. `.ai/core.md` was not touched. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed that `.ai/core.md`, `.ai/core-reference.md` and `.ai/core-syntax.md` are unchanged and that the archive holds the log byte for byte, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

First make the transform arithmetic a frame: four to eight multiplier lanes issuing the four yaw and four pitch products together, the reciprocal on its own lane and the two screen products in parallel, targeting one vertex every eight to sixteen clocks and staying bit-exact against `tests/vert_model.sv` and the vertex traces. Then connect the walker's cell FIFO to that unit with the land store's vertex words, the slot keys and the CPU's de-duplication, still against the traces; then the near-plane and guard clip and the triangle assembly into the existing setup; then a build, an eight-seed sweep and the user's flight test.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---
## 2 COMMIT Unreleased 2026-10-20T08:06:46-07:00

#### Coming From:

Unreleased 886a986

#### Purpose:

Replace the transform's one-product-at-a-time arithmetic with a four-round pipeline of multiplier lanes, so that a vertex costs a round rather than about two hundred clocks without moving a bit of any result.

#### Outcome:

The transform is four rounds of an eighteen-clock pipeline now, one vertex a round: the four yaw products, the four pitch products, the reciprocal on a lane of its own, then the two screen products, with `go` and `done` replaced by a ready/valid handshake that returns each vertex's grid key beside its screen position. Ten lanes of the new `mullane` do the multiplying, and the barrel shifter the old `mulseq` needed for its variable digit position is gone: the shifted magnitude walks right two bits a clock while the multiplier's remaining bits walk left, so a radix-4 digit is a mux of the magnitude, its double and their sum. The first build of the lane was wrong twice -- it walked the magnitude left, and it took the first digit from the multiplier's low bits instead of its top two -- and `tests/vert_model.sv` caught both at the first vertex. `tests/raster_tb.sv` now reads the trace into arrays once and checks four paths against it: the model, the unit worked one vertex at a time, all 256 vertices issued back to back, and the raster's camera file and registers, with each result's returned key checked against the key that was issued. The stream measures 18 clocks a vertex, where the sequential unit took about 208, so Land 1's 54,225 unique grid vertices would cost 13.0 ms of a frame at 75 MHz rather than 150. Both lands still pass, 21,223 and 26,542 cells against the model and 256 vertices through all four paths, and the frames are unchanged at `293e6ccf` and `5c2808f5` and at `4bb0a03f` and `9013c700` because nothing draws through the transform yet. The ten lanes add 12 `LUT4` and 1,136 `ALU` to the core rather than the two thousand `LUT4` a copy of the old lane would have cost, the synthesis being 20,645 `LUT4` against 20,633, 10,257 `ALU` against 9,121, 17,472 `DFFRE` and 3,171 `DFFCE` with 2,000 `DFF` against 18,056 and 1,767, and 293 of 340 block RAMs unchanged; it has not been placed and routed, which stays with the walker's cycle. Celtic had to be run from `Data/Landscape/Tribal/2Celticgodland.lnd`, the top-level copy of the same size being refused by `tools/convert_land.py` as non-standard. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed that `.ai/core.md`, `.ai/core-reference.md` and `.ai/core-syntax.md` are unchanged and that no settled entry was rewritten, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

Connect the walker's cell FIFO to the unit's handshake: fetch each drawn cell's corners from the packed land store, de-duplicate them by the CPU's slot keys, transform them a round apart and write the slots the triangle assembly reads; then the near-plane and guard clip and the triangle assembly into the existing setup, still against the traces; then a build, an eight-seed sweep and the user's flight test.

#### Files Modified:

- fpga/raster.sv
- tests/raster_tb.sv

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---
## 3 COMMIT Unreleased 2026-10-20T09:58:34-07:00

#### Coming From:

Unreleased ea85565

#### Purpose:

Connect the walker's cells to the transform and the vertex store, with terrain.c's slot rule and its owner de-duplication, so the fabric computes and stores the screen position of every corner the walk draws.

#### Outcome:

The walker's FIFO now has a feeder: each cell's four corners are addressed in the packed land store, de-duplicated through a 1024-entry owner table in one block RAM against terrain.c's rule -- the z front the row was reached from, the row's parity and the column modulo 256 -- sent through the transform a round apart, and written into the vertex store as `{x, y, colour, depth}` when they are in front of the near plane, which is what the CPU's store holds. Results return in issue order through a four-deep queue. The transform carries a one-bit tag so the walker and the bus can share it and each take only its own results, and three registers were added for looking at the store afterwards, `0x98` a slot address with `0x9c` and `0xa0` its corner and its colour and depth, served while the engine is not drawing. The land store is addressed with the grid's own stride, `cells_x + 1`, because the packed vertices are the land's rows and not the 241 the store is sized at; Land 1's rows are 225 wide. Three defects were found and fixed on the way. Synthesis caught two registers with two driving always blocks, `wfifo_rd` and `feed_en`, which iverilog resolves silently and hardware cannot, and it refused to map `land_v` until its read address was a register rather than a mux of one and a combinational index. Simulation then caught the feeder's land address reverting to the bus's pointer while it waited on a full result queue, which paired the right slot with the previous vertex's word: 115 of 1024 slots disagreed with the model on Land 1 and 113 on Celtic until the corner's address was held for as long as the corner was in hand. A fourth, the queue depth assigned twice in one clock when a push and a pop landed together, was fixed to one sum and changed nothing measurable. Both lands pass now -- 21,223 cells and 84,892 corner visits on Land 1, 26,542 and 106,168 on Celtic -- with every slot the walk should have written matching the model field for field, the 256-vertex transform checks and the frames unchanged at `293e6ccf` and `5c2808f5` and at `4bb0a03f` and `9013c700`, since nothing draws from these slots yet. A copy with the slot column shifted one bit fails the slot check alone, 288 of 1024 slots wrong, so the gate is live. The synthesis is 21,082 `LUT4` against 20,645, 10,372 `ALU` against 10,257, 17,640 `DFFRE` and 3,307 `DFFCE` with 2,065 `DFF` against 17,472 and 3,171 with 2,000, and 294 of 340 block RAMs against 293, the owner table taking the extra one; it has not been placed and routed. `tools/test_tang32_raster.sh` gained `TINYCREATURE_RASTER_BUILD` and `TINYCREATURE_RASTER_SV` so two lands and a deliberately broken copy can be simulated side by side. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed that `.ai/core.md`, `.ai/core-reference.md` and `.ai/core-syntax.md` are unchanged and that no settled entry was rewritten, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

Issue each cell's triangle from the slots the feeder has filled: the near-plane and guard clip terrain.c's submit() applies, the triangle command naming three slots, and the coupling that keeps the fill's slot reads ahead of the next walk write, since the walk runs a few cells ahead of the assembly. Then a build, an eight-seed sweep and the user's flight test. The archived entry 51 `BAD TINYCREATURE PIXELS` at 2,000 and 3,000 villager-sized cards and the art queue stay open.

#### Files Modified:

- fpga/raster.sv
- tests/raster_tb.sv
- tools/test_tang32_raster.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---
## 4 COMMIT Unreleased 2026-10-20T13:49:50-07:00

#### Coming From:

Unreleased a4c3b37

#### Purpose:

Fold the triangle decision into the walker's feeder and make its stores map to the block RAM modes the video unit requires, so the core builds, reaches the board and draws.

#### Outcome:

The separate assembler and its per-slot flag table are gone: the feeder now decides each cell's two triangles itself, reading the drawable bit out of the owner entry it already kept, so the aq queue, the flag store and one state machine came out and the block RAM count returned to the 293 the deployed core used. Two defects were found on the way, both by the sixteen-cell bench rather than the full simulation: the owner table's write address had been the read multiplexer, so results landed on whatever slot the state machine was looking at, and a cell's second triangle was skipped after the first was pushed. The build then failed on a rule rather than on timing: `land_v` and `land_f` are 32 bits wide and only the 9-, 18- and 36-bit block RAM modes read back correctly in this unit on this chip, so seed 7, which had routed and met both clocks at 75.80 MHz bus and 87.56 MHz pixel, was refused by the build's own check. Widening both stores to 36 bits, using 32, satisfied it and cost 285 `LUT4` while saving two block RAMs, the synthesis standing at 21,800 `LUT4`, 10,418 `ALU`, 18,487 `DFFRE` and 292 of 340 block RAMs. The new sweep lost seed 6 to illegal placement and closed seeds 2, 5, 3 and 4 at 61.12, 68.18, 67.21 and 71.38 MHz on the bus, every one of them short of the 75 MHz the core is clocked at; pix_clk passed on all four. The user directed that the best of them be deployed anyway to prove the design, so seed 4 was packed by hand with the project's Apicula fork, skipping the timing check deliberately, and loaded over two-wire. It ran the whole terrain test: `TinyCreature TERRAIN OK MODE=FABRIC LAND=96a94274 FRAMES=600 TRIS=20445 PIXELS=32701 DRAW=30877us MAX=36953us CRC=98c5c78e PHWALK=30821us FABRIC=12746us`, with the triangle count and land CRC matching the PC and the frame not matching it, 32,701 pixels against the host's 33,115, which the user judged to be the overclock rather than the new logic and asked to proceed on. The feeder and the assembly are idle on the board because the firmware never starts the walk, so nothing in this run exercised them; the slots were checked in simulation on Land 1, 84,892 corner visits over 21,223 cells matching the model, and the drawn-frame comparison never completed in simulation before the cycle turned to hardware. Seeds 1, 7 and 8 were still routing when the user stopped them. `.ai/core.md` was not touched. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed that `.ai/core.md`, `.ai/core-reference.md` and `.ai/core-syntax.md` are unchanged and that no settled entry was rewritten, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

Give the firmware the walk: pack the land's vertices and flags for the fabric's store, upload them, write the block bitset, the camera cell, the grid size and the camera file, start the walk with its feed bit and wait for `feed_done` and an idle assembly, and stop the AE350 sending its own vertex and triangle commands for that frame. Then congestion and timing, since the design closes at 71.38 MHz against the 75 it runs at, and the near-plane and guard clip, which the assembly does not yet do.

#### Files Modified:

- fpga/raster.sv
- tests/raster_tb.sv

#### Status:

- Build: FAIL
- Deployment: PASS
- User Test: NOT RUN

---
## 5 COMMIT Unreleased 2026-10-20T13:54:05-07:00

#### Coming From:

Unreleased fdff4f7

#### Purpose:

Give the firmware the walk, so the fabric walks and draws the land itself instead of the AE350 walking it and sending the triangles.

#### Outcome:

The renderer's target gained a walk callback: a target that walks the land itself is handed the block bitset the cull kept, the block grid, the cell grid, the camera cell and the camera's seven numbers, and the program then sends no terrain of its own. `main.c` implements it for the board: a `FABRIC_WALK` build knob packs the land's vertices as `{colour, altitude}` words and its cells' flag nibbles and uploads them through the land store's two registers once at startup, and each frame writes the transform's camera file, the camera cell, the grid and the bitset, starts the walk with its feed bit, and waits for the walker's done bit with the assembly idle before the frame is flipped. The first attempt passed the block grid where the cell grid belongs, so the unit walked a fourteen by thirteen patch at the island's corner, declared no triangles and the run reported `TRIS=0`; with the cell grid in place the board reported `TinyCreature TERRAIN OK MODE=FABRIC LAND=96a94274 FRAMES=600 TRIS=35400 PIXELS=31406 DRAW=26784us MAX=31061us CRC=69580a88 PHWALK=26738us FABRIC=16833us CAMFOCUS=111,103 CAMEYE=110,283 CAMTURN=179`, and the user watched it and accepted it. Every one of those 35,400 triangles was declared by the fabric, the AE350's own walk being off for the run, which reports `CELLS=0`, and the walk and assembly cost 26.7 ms a frame with 16.8 ms of fill inside it. The frame is not the host's: the board drew 31,406 pixels against 33,115 and its CRC differs, which is the assembly having no near-plane or guard clip, so a triangle with a corner behind the camera is skipped where the CPU cuts and draws part of it, and no cull, so back-facing triangles are sent and left for the fill to reject; the core is also still the overclocked seed 4, closing at 71.38 MHz and clocked at 75. `.ai/core.md` was not touched. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed that `.ai/core.md`, `.ai/core-reference.md` and `.ai/core-syntax.md` are unchanged and that no settled entry was rewritten, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

The near-plane and guard clip, so the fabric draws the triangles it now skips and the frame can be compared against the host's instead of merely watched. Then congestion and timing, the design closing at 71.38 MHz against the 75 it runs at, and the cull, which would stop sending the triangles the fill rejects. The archived entry 51 `BAD TINYCREATURE PIXELS` and the art queue stay open.

#### Files Modified:

- firmware/terrain/Makefile
- firmware/terrain/main.c
- firmware/terrain/terrain.c
- firmware/terrain/terrain.h

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---
## 6 COMMIT Unreleased 2026-10-20T14:13:28-07:00

#### Coming From:

Unreleased d65233e

#### Purpose:

Cut the triangles the vertex store cannot carry at the near plane, so the fabric draws the geometry it had been skipping, and hand the state to the next agent.

#### Outcome:

The fabric now has a near-plane clip: `sdiv64` divides a 64-bit signed numerator by a 32-bit one truncating toward zero as C's does, checked on its own bench against ten cases including every sign combination, and the feeder re-derives an undrawable triangle's three corners in camera space through the transform, cuts the edges that cross the plane, projects each cut point at NEAR -- where `(1 << 30) / 128` is exactly 2^23, so the projection is a five-bit shift and not a multiply -- and draws the polygon as a fan of whole four-word TRI commands through the same command queue, which now takes its length from the word that starts a command so the assembly can send either kind. The transform gained camera-space outputs beside its screen corner, and a sixteen-cell bench with the camera moved inside the land produced the first clipped triangles, 32 before the close walk and 34 after, so the path executes. It has not been checked against the CPU: measured against a corner-interpolated picture it can only be close, because a cut corner takes the palette entry of the corner it was cut from where terrain.c shades it from the interpolated weights, and the guard band is not implemented at all, both of which the user accepted as the scope. Synthesis of the clip is 25,285 `LUT4` against 21,800, 11,003 `ALU` against 10,418, 19,233 `DFFRE` against 18,487 and 292 of 340 block RAMs unchanged, so the cut costs more logic than the whole walker and assembler did, and on a design already marginal for the placer seed 7 failed placement outright while the other seven were still placing; the user stopped the sweep there rather than spend an hour on a build whose end was visible. The full-land simulation started alongside it never reached its first checkpoint before it too was stopped, so the store path has not been re-checked since the clip arrived. The board still runs seed 4's overclocked core (`ae350_soc.bin` SHA-256 `db2869114add7c10`) with the fabric-walk program from entry 5, which is what the user last watched; entry 80's core is backed up in `build/core-entry80/` and seed 4's pack in `build/core-seed4/`. `.ai/core.md` was not touched. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed that `.ai/core.md`, `.ai/core-reference.md` and `.ai/core-syntax.md` are unchanged and that no settled entry was rewritten, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

Check the clip against the CPU before trusting it: the full-land testbench should compare the fabric's walk frame against the program's whole command stream, TRI commands included, rather than against the store path alone, and the two known differences -- a cut corner's colour and the missing guard band -- will show as the pixels that remain. Then decide what to do about the clip's cost, since 3,485 more `LUT4` on a design that closes at 71.38 MHz and cannot place on every seed is the wrong direction: the candidates are reusing the transform's own lanes for the corner re-runs instead of a second copy, cutting the polygon buffer down, and moving the clip to the CPU for the few triangles that need it if the depth buffer can be made to cover their order. The walk also still costs 144 clocks a cell, 26.7 ms a frame, which is the pipelining work entry 5 set out, and the archived entry 51 `BAD TINYCREATURE PIXELS` and the art queue stay open.

#### Files Modified:

- fpga/raster.sv
- tests/raster_tb.sv

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: NOT RUN

---
