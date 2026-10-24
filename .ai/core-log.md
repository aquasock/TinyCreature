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
## 7 COMMIT Unreleased 2026-10-21T19:24:11-07:00

#### Coming From:

Unreleased c2e4553

#### Purpose:

Make the fabric walk run the whole orbit on the board in a core that meets the bus clock, by shrinking the near clip, giving the assembly back-pressure and clearing the defects that hung the walk in simulation and on hardware.

#### Outcome:

The near clip's crossing arithmetic is now `nearcut`, one `mullane` and a radix-4 divider returning the 32-bit quotient a crossing can have, checked by the new `tests/nearcut_tb.sv` against C's `(int64)a * b / d` over 26,663 cases with three deliberate mutations each failing it; the clip cost 837 `LUT4` where entry 6's two single-clock 32-by-32 multiplies and 64-bit divider cost 3,485, and its divider's done is now a one-clock pulse, since the old level done let `CK_DIVX` take the previous quotient. The assembly's triangle and the clip's fan words now wait for room in the command queue instead of being lost against a full one. Entry 6's clip drove `feed_req`, `f_gx`, `f_gz`, `f_alt` and `ck_t` from a second always block, which Yosys reported as multiple conflicting drivers and which the first core of this cycle on the board, seed 4 packed by hand, showed as a program that never left the colour screen; the clip now has its own transform request, and `tools/build_tang32.sh` refuses a synthesis that reports a multiply-driven register. Every walk simulation since entry 6 had also stalled in the bench alone, because `cslot()` and `tri_k()` read module signals rather than arguments, which iverilog does not re-evaluate, so the bench saw stale slots and a bogus clip whose unknown corners hung the fill; both now take their inputs as arguments, and the clip also gained the second clock the land store needs before its word is read and an exit when no corner is in front of the plane, where it had looped forever. A scratch build of the host counted no triangle entering `submit_slow()` anywhere in the 600-frame orbit, so the clip does not run on the orbit and entries 5 and 6 were wrong to attribute the board's missing pixels to it. With these fixes `tools/test_tang32_raster.sh` now takes `TINYCREATURE_TRACE_FRAME`, dumps the walk's frame and counts clip entries and queue holds, and the walk drew the terrain of frames 0, 52, 75 and 150 exactly as the host did, every differing pixel lying under the host's overlay quads, with no clip and no hold at any of them; vvp still segfaults in the bench's own buffer read-back after the store path is pushed, so the frames were compared offline and the script exits non-zero. Seed 3 of the next sweep, 74.11 MHz against 75, ran 52 frames on the board and then stopped, and the walk timeout `firmware/terrain/main.c` now has reported its fill busy with the walker having pushed 20,767 cells against the 20,640 the frame has: its failing path ran from the walker's flag store through the queue level into the feeder, so the assembly now tests a registered nearly-full flag instead. The next sweep's critical path was the walker's row multiply, so the walker keeps running row and block-row bases for both ends, built once a walk by `W_INIT`, and hands the feeder its vertex row in a 37-bit cell FIFO; that FIFO had been flip-flops since entry 5 because it was written inside a reset block, and written from its own block it is a block RAM, the feeder waiting a clock before taking a cell from an empty FIFO. Synthesis is 18,523 `LUT4`, 11,179 `ALU`, 13,969 `DFFRE` and 294 of 340 block RAMs against entry 6's 25,285, 11,003, 19,233 and 292. The last sweep closed seed 2 at 75.34 MHz bus and 84.79 MHz pixel and refused it only for the unmeasured SPINE27 pixel-clock bridge, seed 6 reached 74.44 MHz with the measured bridges, seeds 1, 4, 5, 7 and 8 reached 67.99, 72.17, 73.81, 72.79 and 64.02 MHz, and seed 3 was stopped, so no seed was clean. At the user's direction seed 2 was packed by hand with the bridge check not applied, `ae350_soc.bin` SHA-256 `64827186a0f766afea99b6abbe1b857689196c17c82883ecb67dcd1255ba6598` and `ae350_soc.fs` SHA-256 `926c1ab790b9fff585d1bc6543256c6167199a005d770a3638e1ada3666d3f76`, with `terrain.elf` built with `FABRIC_WALK=1`, SHA-256 `4d7f9e7496fcc90a30c2724ba91d17bc0f12cdfef2076f8749a8c5edec285a83`, and loaded over two-wire; it ran the whole orbit, `TinyCreature TERRAIN OK MODE=FABRIC LAND=96a94274 FRAMES=600 TRIS=36096 PIXELS=32371 DRAW=26593us MAX=31011us STALLS=0 VBLMIN=3 VBLMAX=3 PERIOD=49996us CRC=2fd83d22 PHWALK=26548us FABRIC=16493us`, the picture holding through SPINE27 for all 600 frames, and the user accepted it and directed the commit. The triangle count and CRC differ from the host's because the fabric does not cull, the last frame is 744 pixels short of the host's 33,115 for a reason not yet found, and the shown rate is the twenty frames a second `TC_BLANKS_PER_FRAME` of 3 holds it to. `.ai/core.md` was not touched. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed that `.ai/core.md`, `.ai/core-reference.md` and `.ai/core-syntax.md` are unchanged and that no settled entry was rewritten, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

The worst frame is 31.0 ms against the 33.3 ms two blanks allow, so `TC_BLANKS_PER_FRAME` of 2 can be tried for thirty frames a second, with VBLMAX showing any frame that spills; the lasting gain is the feeder's 144 clocks a cell, which pipelining would bring under the fill, and the back-face cull, which would stop sending the triangles the fill rejects. The 744-pixel shortfall against the host, the bench's vvp segfault, the near clip's check against the CPU on a recorded close-in flight, the SPINE27 observation and the two tool behaviours this cycle found, a memory written in a reset block becoming registers and iverilog not re-evaluating a function's module signals, which are candidates for `.ai/core-reference.md`, the archived entry 51 `BAD TINYCREATURE PIXELS` and the art queue stay open.

#### Files Modified:

- firmware/terrain/main.c
- fpga/raster.sv
- tests/nearcut_tb.sv
- tests/raster_tb.sv
- tools/build_tang32.sh
- tools/test_tang32_raster.sh

#### Status:

- Build: FAIL
- Deployment: PASS
- User Test: PASS

---
## 8 COMMIT Unreleased 2026-10-21T20:32:57-07:00

#### Coming From:

Unreleased 6d3e54a

#### Purpose:

Fix what the user found flying the Celtic land on the fabric walk, the missing target square and the triangles drawn with wrong corners when the camera is near the land, in a core that passes every build check.

#### Outcome:

The fabric walk's branch of `tc_draw()` returned before the pin, the cursor and the camera readout were drawn, which is why the green target square was missing; `firmware/terrain/terrain.c` now draws them in `draw_overlays()` after either walk, the host's orbit still drawing `TRIS=20445 PIXELS=33115 CRC=5afe81aa`, and the user confirmed the square was back. The scattered wrong triangles were the vertex store: the feeder writes a slot directly while the triangles naming its previous owner can still be queued, where a CPU-driven frame's vertex commands keep their order in the queue, so once the fill fell behind the walk reused slots before queued triangles had read them. `tools/tang_input.py zoom` now writes a wheel roll that brings the eye down to the land, the near plane starting to cut on Land 1 at frame 202, and `TINYCREATURE_INPUT` replays such a sequence through `tools/test_tang32_raster.sh`; on the core as it stood the walk's frames 180 and 199 differed from the host's in 7,661 and 8,467 pixels spread across the screen, with the queue held full for 73,779 and 124,398 clocks. The feeder now waits before taking the first cell of a new row until the queue is empty, the assembler holds nothing and no slot read is under way, so every queued triangle has read its corners before the row's writes begin; the frames then differ only in 982 and 1,763 pixels, all of them the creature sprite and the camera readout that the host draws and the bench's fabric frame does not, while orbit frames 0 and 75 still match apart from the overlay and their walks grew from 2,296,169 and 2,021,441 clocks to 2,307,059 and 2,023,565. The sweep closed seed 3 at 75.67 MHz bus and 90.00 MHz pixel on the measured clock bridges, the first seed to pass every check since the fabric walk went in, with seeds 1, 4, 5, 7 and 8 at 74.84, 71.90, 71.38, 72.72 and 71.48 MHz and seeds 2 and 6 stopped while routing; synthesis is 18,483 `LUT4` and 13,979 `DFFRE`, `ae350_soc.bin` SHA-256 `b59a78eb8fe16a34f3484105e60f6b7f2e1618f293d30a1c0c9c2f2358de29a0` and `ae350_soc.fs` SHA-256 `84f657594d1ad8e0d743fbb58cea230977c04fd3208f9171b1a49d685a679325`. It was loaded over two-wire by `tools/run_tang32_feel.sh` with `FABRIC_WALK=1 HANDOVER=1` and the Celtic land, `build/feel/terrain.elf` SHA-256 `1d64e436e3922b9be09d1af9c78e2c6c6e58e6150cef79a39eafa5254e0a1305`, and the user flew it and reported the random clipping gone. The feel script itself passes neither `FABRIC_WALK` nor the `HANDOVER=1` the Makefile says feel builds use, so both came from the environment. Close to the land the user still sees the ocean through the ground, which is the near plane and the missing guard band, and the fabric walk still draws no creature sprite, because the CPU's walk draws it as it reaches the sprite's cell. `.ai/core.md` was not touched. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed that `.ai/core.md`, `.ai/core-reference.md` and `.ai/core-syntax.md` are unchanged and that no settled entry was rewritten, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

The near plane and guard band, where the user sees the ocean through the land at full zoom: the zoom input's frames from 202 on, where the CPU cuts 19 to 74 triangles a frame and finds up to about 300 wholly behind the plane, are the test case, compared in the bench before any change; the leading option is to have the fabric skip the triangles it cannot carry and the CPU draw them through `submit_slow()`, which already clips both exactly, if the fill depth-tests the CPU's flat triangles so their order does not matter, against a guard clip in the fabric. The feel script should pass `FABRIC_WALK` and `HANDOVER=1` itself, the creature sprite needs drawing in fabric-walk frames, and entry 7's open items stand: the feeder's 144 clocks a cell before thirty frames a second, the back-face cull, the 744-pixel shortfall on the orbit, the bench's vvp segfault, the core-reference candidates, the archived entry 51 `BAD TINYCREATURE PIXELS` and the art queue.

#### Files Modified:

- firmware/terrain/terrain.c
- fpga/raster.sv
- tools/tang_input.py
- tools/test_tang32_raster.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---
## 9 COMMIT Unreleased 2026-10-21T20:53:04-07:00

#### Coming From:

Unreleased 15d16d3

#### Purpose:

Draw the land next to the camera correctly in fabric-walk frames, where the user saw the ocean through the ground at full zoom, and leave the project in a state the next agent can pick up.

#### Outcome:

The ground nearest the camera reaches behind the near plane or past the guard band, which the fabric's store cannot carry and which its own near clip handles without a guard band and has never been checked against the CPU, so the work went to the CPU instead without a core change. `cull_blocks()` in `firmware/terrain/terrain.c` now marks a shown block 2 when any corner of its bounding box is behind the near plane or projects past `GUARD` less a 64-unit margin, which bounds every vertex inside it since camera-space z is linear and x / z and y / z are linear-fractional over the box; a fabric walk is given only the blocks marked 1, `fabric_walk()` in `firmware/terrain/main.c` now setting a block's bit only for 1 where it had set it for any non-zero value, including blocks with no land, and `draw_beyond_blocks()` draws the 2s through `draw_cell()` and `submit_slow()` after the fabric's walk, far to near over only the rows and columns they span, while the CPU's own walk draws 1s and 2s alike. The host is unchanged, `TRIS=20445 PIXELS=33115 CRC=5afe81aa` on the orbit and `TRIS=7924 PIXELS=53820 CRC=3e011caa` through `tools/tang_input.py zoom`, and a scratch build counting the blocks found none marked 2 in any of the orbit's 600 frames, so the fabric's orbit walk is what it was, and at most 2 against 12 to 22 shown from frame 200 of the zoom on. It ran on entry 8's seed 3 core, `ae350_soc.bin` SHA-256 `b59a78eb8fe16a34f3484105e60f6b7f2e1618f293d30a1c0c9c2f2358de29a0`, with `build/feel/terrain.elf` SHA-256 `7fe1e3ab43270139ed062fbdb914db747c2042a5dca68670c8561d24bd8ed110` built by `tools/run_tang32_feel.sh` with `FABRIC_WALK=1 HANDOVER=1` and the Celtic land `Data/Landscape/Tribal/2Celticgodland.lnd`, loaded over two-wire, and the user flew it to full zoom and reported it perfect. The board's two-wire port drops off USB after some runs and the BL616 console refuses a load while a handed-over program still runs, so a reboot of the Tang has come before most loads, and `tools/tang_power.py` still finds no USBRelay8 to do it. Because no block whose corners reach behind the plane or past the guard band now reaches the fabric, its near clip, 837 `LUT4`, should no longer run. `.ai/core.md` was not touched. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed that `.ai/core.md`, `.ai/core-reference.md` and `.ai/core-syntax.md` are unchanged and that no settled entry was rewritten, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

The user asked for a steady frame rate over a higher one, so `TC_BLANKS_PER_FRAME` stays 3, twenty frames a second, until the worst frame sits well inside the 33.3 ms two blanks allow; the work that gets there is the feeder's 144 clocks a cell, which pipelining would bring under the fill, and the back-face cull, which would stop sending the triangles the fill rejects and let the board's TRIS and CRC be compared with the host's again. Smaller open items are the fabric's now unused near clip, which could come out once the guard margin is confirmed on the board to keep every such triangle from the fabric, the creature sprite that fabric-walk frames do not draw, `tools/run_tang32_feel.sh` passing `FABRIC_WALK` and `HANDOVER=1` itself instead of from the environment, the 744-pixel shortfall on the orbit, the bench's vvp segfault in its own buffer read-back, and core-reference records for the SPINE27 bridge holding the picture for 600 frames in entry 7 and for the two tool behaviours entry 7 found. The archived entry 51 `BAD TINYCREATURE PIXELS` and the art queue stay open.

#### Files Modified:

- firmware/terrain/main.c
- firmware/terrain/terrain.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---
## 10 COMMIT Unreleased 2026-10-23T02:34:01-07:00

#### Coming From:

Unreleased fad6dec

#### Purpose:

Draw the level script's trees in fabric-walk frames, measure and raise the frame rate, and make the fabric depth-test a card so a tree behind the land is occluded by it instead of painting over it.

#### Outcome:

The fabric walk had taken the plant pass with it: `draw_plant_cell()` was called only from the CPU walk loop, which a fabric frame never runs, so the board drew no trees at all. `draw_plant_blocks()` now draws them from the fabric branch after `draw_beyond_blocks()`, over the blocks the cull kept and those handed to the CPU, and with `PLANTS=1 PLANT_ART=1 TILES=1 PLANT_RANDOM=1 PLANT_SEED=1` and the table from `Scripts/Playgrounds/2- The Celtic God (OB).txt` against `2Celticgodland.lnd` it reports 1,405 plants and 4,619 cards a frame, `TRIS=44663` against entry 9's 36,096, at `PERIOD=65676us`, 15.2 fps. The frame rate then got a permanent readout: `tc_target` gained `clock_hz`, the board passes `TN_CORE_HZ`, and `draw_readout()` measures the rate over the last half second and draws two digits after the bearing. The plant pass itself was mostly the search: 46,412 cells were being binary-searched for 1,235 plants, and iterating the table instead took `PSCAN` from 11,892 us to 443 us and the frame to `PERIOD=54298us`, 18.4 fps, with the cards unchanged. Level of detail came next: `TC_PLANT_LOD` (9,600 Q4, 600 world units) draws a tree past that distance as one card instead of five, which cut `PCARDS` from 4,619 to 1,417 and the frame to `PERIOD=50008us`, 20 fps on the three-blank cadence floor with `MAX=44108us`; the user flew it, called the frame rate much better and reported the trees visible through the landscape. That is the card's missing depth: `fpga/raster.sv` tested nothing for `TRI`, `TEX` or `CARD`, and the CPU walk had hidden it by drawing each tree between terrain cells. A horizon cull, `plant_visible()` sampling the land along the ray from each plant's top to the camera, removed 110 of 1,235 plants at a cost of about a millisecond and the user flew it and accepted the result, but the mechanism does not belong there. `CARD` is now eight words with a depth plane -- D at the first pixel and its steps across and down, each 32 bits -- and the fill compares and writes it exactly as a stored triangle does, with the depth buffer read following `card_addr`; the firmware works the plane out per column through `tex_plane()` and sends it whole. `tests/card_tb.sv` checks six cases on written-pixel counts and passes, and a copy with the comparison forced true fails five of the six, so the bench is live; `tests/raster_tb.sv` counts the card's seven following words. The land regression still matches the model -- `nearcut_tb` passes, 21,223 cells and 84,892 slots over them agree, and the land store reads back -- but its frame CRC checks are lost to the pre-existing `vvp` segfault in the bench's own read-back, so no frame was compared this cycle. Synthesis is 18,492 `LUT4` and 11,271 `ALU`, nine LUTs over entry 9 for the comparator and the 32-bit stepping, and the eight-seed sweep was stopped at the user's direction while all eight were still routing: no seed wrote a timing report, nothing was placed and routed, nothing was deployed, and the core on the card and in `build/tang32/ae350_soc.bin` is still `b59a78eb` from entry 8. Three times during the cycle another agent's `tangload` of a `ddrdll` core reprogrammed the FPGA under the running program and blacked the screen; each time the board was rebooted, and none of it came from this project's tooling. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed that `.ai/core.md`, `.ai/core-reference.md` and `.ai/core-syntax.md` are unchanged and that no settled entry was rewritten, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

Run `tools/build_tang32.sh` again and let the eight seeds finish: the card fill has not been placed and routed, so its timing, its clean seed and the board's picture are all unknown, and the change is not proven until a clean seed is deployed and flown. Once it is on the board the horizon cull in `plant_visible()` should come back out, since a depth-tested card needs no guess, and the fabric's own near clip, 837 `LUT4` and unused since entry 9, is still a candidate for removal. The `vvp` segfault in the raster bench's buffer read-back blocks the frame comparison and should be fixed before the next change that touches the fill. Beyond that the LOD distance wants tuning against the picture, the feeder's cost and the back-face cull remain the route to thirty frames a second, and the archived entry 51 `BAD TINYCREATURE PIXELS` and the art queue stay open.

#### Files Modified:

- firmware/terrain/Makefile
- firmware/terrain/main.c
- firmware/terrain/terrain.c
- firmware/terrain/terrain.h
- fpga/raster.sv
- tests/card_tb.sv
- tests/raster_tb.sv
- tools/run_tang32_feel.sh

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: NOT RUN

---
## 11 COMMIT Unreleased 2026-10-24T10:07:39-07:00

#### Coming From:

Unreleased e47b526

#### Purpose:

Finish entry 10's card-depth cycle by getting a core onto the board that draws the depth-tested cards, then attack the bus timing the design has never met and prove the fabric's near clip was dead code.

#### Outcome:

Entry 10's card-depth core had never been placed, routed, deployed or flown. Twelve seeds were routed against it: seed 1 reached 74.78 MHz on the bus and 84.32 on the pixel clock, seed 8 74.33, seed 10 74.74, seed 9 75.31 but refused for routing the pixel clock through the unmeasured SPINE27 bridge, and the rest between 68.40 and 72.26, so no seed was clean. At the user's direction seed 1 was packed by hand with the project's Apicula fork and the timing check skipped, its card image 5,251,448 bytes at SHA-256 `d787002b9767d946` from the 42,048,325-byte SRAM image at `d2f98b1e4f655e9c`, and deployed over two-wire with the Celtic land, `PLANTS=1 PLANT_ART=1 TILES=1 PLANT_RANDOM=1 PLANT_SEED=1 PLANT_LOD=9600`, reporting `AE350 OK`, `SDRAM OK 32M`, 140,820 bytes loaded at 185.6 KB/s and 162,942 bytes of land; the user flew it, confirmed the fabric now depth-tests a card so a tree behind the land is occluded, and adopted that seed as the one to use going forward. The board's card had meanwhile been rebuilt with its other four applications named `tinynes`, `tinygbc`, `tiny89` and `tinyphosphor`, each an `<app>.bin` that `tangload` reads with its paired `.fs` gzipped beside it as an openFPGALoader companion the board does not read, so TinyCreature was installed the same way as `/root/cores/console138k/tinycreature.bin` with `tinycreature.fs.gz` beside it, and `tools/run_tang32.sh`, `tools/run_tang32_feel.sh` and `tools/tinycreature.tdsh` were renamed off `tinycreature-tang32.bin` and made to write the gzipped `.fs`. Six more seeds and then another six found no clean one, the second batch worse than the first at 64.05 to 73.06, and the critical path of the best seed was then read rather than guessed: 13.377 ns against a 13.333 ns period, 44 picoseconds over, of which 1.080 ns is the AE350's own `EXTS_HADDR4` clock-to-Q and 1.516 ns the first routing hop out to the fabric. The near clip was removed on the strength of entry 9's cull: the `CK_IDLE` to `CK_LAND2` state machine, the `nearcut` divider and `tests/nearcut_tb.sv` with its invocation, the transform's `camx`, `camy` and `camz` outputs, and the clip's request path into the transform's input mux, the assembler's push and the land store's read address, with the feeder now skipping a triangle the store cannot carry. Synthesis fell from 18,492 to 18,155 `LUT4`, 11,271 to 10,607 `ALU` and 14,187 to 13,455 `DFFRE` with the block RAMs unchanged and no multiple-conflicting-driver report; `tests/card_tb.sv` passes its six cases, `tests/raster_tb.sv` compiles, and the walk then proved the removal changed nothing: 21,223 cells match the model, every slot agrees, `walk: 0 triangles skipped as uncarryable`, and the walk cost 2,307,059 clocks, exactly entry 8's figure for the same land. The removal did not recover the timing, the best seed of the clip-free design being 74.76 against 75.00, and seed 9's 75.31 belonged to the design with the clip. The bench's frame read-back still segfaults as entry 10 recorded, and its buffered stdout is lost when it does, which made an earlier run look as though the bench had never started; `vvp` needs more than 300 seconds to reach the crash. The user then reported two open defects on the flying seed, a band of flickering pixels about a third from the bottom of the screen and a grab that stays sticky for about a second before the land moves, and neither had a cause established: the input path was ruled out because a live report names frame `0xffff` and is applied at once rather than parked, and a mid-fill flip was ruled out because the firmware waits on `RASTER_BUSY` before `TN_VIDEO_CTRL` and that term covers the fill's own state including the card path. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed that `.ai/core.md`, `.ai/core-reference.md` and `.ai/core-syntax.md` are unchanged and that no settled entry was rewritten, and validated this entry's six sections, sequential number, prose, Status values and the 100-entry limit.

#### Next Steps:

The flickering band comes first and needs evidence rather than another sweep: a screenshot, or two a second apart, to say whether it sits at a fixed height, whether it is garbage or a shifted copy, and whether it moves with the camera, with `tools/run_tang32.sh`'s gated run as the stronger test because it reports late SDRAM line fetches and compares the board's frame CRC against the host twin. The sticky grab is separate and needs to be known as constant or only at the start of a grab, which decides between late input and the camera model's pick. The 44-picosecond bus deficit is one logic level on the path that leaves the AE350's `EXTS_HADDR4` and ends at `screen.shown_buf`, a framebuffer bank select that has no business in the write-data path, and the alternative of admitting SPINE27 to the measured bridge set is now backed by three accepted flights, entry 7's 600 frames and two more today. The bench's read-back segfault still blocks every frame comparison and its buffered stdout should be flushed as well. Smaller items stand: the horizon cull in `plant_visible()` once the picture is trusted, `tests/card_tb.sv` wired into `tools/test_tang32_raster.sh` rather than run by hand, and core-reference records for SPINE27, for the card's short-name `.bin` and `.fs.gz` convention and for the bench's buffered stdout. The archived entry 51 `BAD TINYCREATURE PIXELS` and the art queue stay open.

#### Files Modified:

- fpga/raster.sv
- tests/nearcut_tb.sv
- tests/raster_tb.sv
- tools/run_tang32.sh
- tools/run_tang32_feel.sh
- tools/test_tang32_raster.sh
- tools/tinycreature.tdsh

#### Status:

- Build: FAIL
- Deployment: PASS
- User Test: PASS

---
