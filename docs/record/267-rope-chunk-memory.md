# 267. Rope chunks fill their malloc size class (Alloy gap G33 (e), `CV-AI`)

Branch `perf/rope-chunk-memory` (master `07173201`). Decision `CV-AI` in `docs/superpowers/2026-11-07-code-view-decisions.md`. Class `M`; no public API, no divergence added or retired (220 live, next label 241).

- **Cause.** An Alloy heap report: 4,472 `_ContiguousArrayStorage<UInt8>` chunks of about 512 B held 2.87 MiB for a 2.17 MiB file (1.32x). Measured with `malloc_size` on each chunk's storage (base pointer minus the 32-byte header): the block is the payload plus header rounded up to malloc's size class, and classes step in quarters of a power of two. 512 + 32 = 544 lands in a 640 block, so the ratio is 1.25x at 512, 1024, 2048 and 4096 alike. Bigger chunks alone do not help.
- **Change.** `Rope.targetChunk` 512 to 472 (`mergeLimit` follows). A cut scalar or CRLF adds at most four bytes, so a built chunk is at most 480 and header plus payload fills the 512 class exactly.
- **Measured** (release, `swiftc -O` of the target plus a throwaway driver; 2,270,026 bytes of generated Swift-like source; best of three; ms are for 2,000 single-char inserts at random offsets, 2,000 at a moving caret, 500 `lineRanges` windows of 60 rows, 20,000 random `lineStart(row:)`):

| max / target | chunks | resident | ratio | load | random edits | caret edits | lineRanges | lineStart |
|---|---|---|---|---|---|---|---|---|
| 768 / 512 (before) | 4434 | 2,837,760 | 1.250 | 1.7 | 50 | 133 | 1.1 | 4.0 |
| 1536 / 1024 | 2217 | 2,837,760 | 1.250 | 1.6 | 55 | 137 | 1.0 | 5.6 |
| 3072 / 2048 | 1109 | 2,839,040 | 1.251 | 1.6 | 54 | 135 | 1.1 | 9.0 |
| 6144 / 4096 | 555 | 2,841,600 | 1.252 | 1.5 | 57 | 144 | 1.3 | 16 |
| 1008 / 976 | 2326 | 2,381,824 | 1.049 | 1.7 | 62 | 165 | 1.2 | 6.6 |
| 1536 / 984 | 2307 | 2,362,368 | 1.041 | 1.6 | 52 | 138 | 1.1 | 5.4 |
| 3072 / 2000 | 1136 | 2,326,528 | 1.025 | 1.5 | 53 | 137 | 1.1 | 8.8 |
| **768 / 472 (chosen)** | 4810 | 2,462,720 | 1.085 | 1.7 | 52 | 138 | 1.1 | 3.8 |

  Edits and lookups of the chosen row are within noise of before (`lineStart` is 5 percent faster); resident falls 375 KB (13 percent; about 0.35 MiB on a 2.17 MiB file's 2.87 MiB). The 984 and 2000 targets save a further 0.1 MB and 0.14 MB but cost 35 and 125 percent on `lineStart`; rejected under the within-10-percent rule. After 4,000 edits the resident figure grew by under 3 KB.
- **Tests** (`Tests/MetalUICodeBufferTests/FindAndPerformanceTests.swift`): `builtChunksLeaveRoomForTheArrayHeaderInTheirMallocClass` (longest built chunk at most 480, average at least 440, 100,000 ASCII bytes cut into 212 chunks); it fails three expectations at a target of 512.
