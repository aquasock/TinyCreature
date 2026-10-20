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
