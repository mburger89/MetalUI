# pan-rasters probes (P3, record 118)

Release timing and work counters for the bracket canvas. Measurements are dated, never pins (a pin counts work).

- `ab.sh <baseline-checkout> <head-checkout> [rounds] [secs]` builds both in `-c release` into `$AB_SCRATCH` (default
  `/private/tmp/claude-501/pan-rasters-ab`), alternates them per scenario (bracket-pan, bracket-pan-panels, bracket-value,
  shadows) for N rounds, prints `uptime`'s load average before each run, then the main-thread allocations of 400
  bracket-pan frames (`PROF_ALLOC=8`, malloc_logger). Baseline checkout: `git archive 34491ff4 | tar -x -C <dir>`.
- `counters.sh <head-checkout>` runs 88 steps of each scenario with `PROF_RASTER_FRAMES=88` and prints the total rasterized,
  tinted pixels and textures made. `tintedPx` needs `lastTintedPixels` (built with `-DPROF_TINT -enable-testing`, HEAD only;
  at 34491ff4 a tint multiplies exactly the rasterized pixels). `bracket-value` is the node drag: 4 drags of 20 steps, 84
  drawn frames in 88 loop iterations (the other four draw nothing).
- `measurements-2026-10-14.txt` is the raw `ab.sh` output of the run below. `Sources/Prof` is the profiling harness
  (`/private/tmp/claude-501/profiling/Prof`) plus the counters mode and a `PROF_OUT` for the allocation dump.

## 2026-10-14, 34491ff4 vs 29830625 (HEAD), Apple silicon 10 cores, shared Mac

Load average 1 min ranged 4.4 to 28.8 (other workflows' builds), so rounds 1 and 2 are noisy; rounds 3 to 5 ran at 5 to 24.
Median over five rounds of each run's median ms/frame (bracket-value: mean ms per loop iteration, since its median iteration
draws nothing):

| scenario | 34491ff4 | HEAD | delta |
|---|---|---|---|
| bracket-pan | 7.56 | 6.53 | -1.03 ms (-14 %) |
| bracket-pan-panels | 7.42 | 6.60 | -0.82 ms (-11 %) |
| bracket-value (drag, mean/iteration) | 5.16 | 4.58 | -0.59 ms (-11 %) |
| shadows | 1.238 | 1.242 | noise |

Paired per round, HEAD is faster in every round for the three bracket scenarios; shadows moves by at most 0.01 ms either way.
The profile's 9.4 ms for pan was taken under heavier load; compare ratios, not absolutes.

Allocations, bracket-pan, 400 frames after warm-up, main thread: 34491ff4 18,981 allocs and 7.97 MB per frame; HEAD 16,342
allocs and 5.84 MB per frame (-2,639 allocs, -14 %; -2.1 MB, -27 %). The profile's estimate for the rasterizer was about 2,400.

## Work counters (counters.sh, debug build, same scenarios)

| scenario (88 steps) | rasterized px | tinted px | textures made |
|---|---|---|---|
| bracket-pan, 34491ff4 | 11,791,732 | = rasterized (whole mask) | not read |
| bracket-pan, HEAD | 134,688 (the cold first frames; 0 after) | 7,904 | 2 |
| bracket-value drag, 34491ff4 | 7,247,148 (82,353 per drawn frame) | = rasterized | not read |
| bracket-value drag, HEAD | 7,345,800 (87,450 per drawn frame) | 450,304 (5,361 per drawn frame) | 160 |

Reading for P3c (R8 coverage with a shader tint): after P3a/P3b the tint is 6 % of the drag's rasterized pixels and the pan
rasterizes nothing in steady state. What remains in the drag is coverage rasterization itself (`CoverageRasterizer`), which R8
does not reduce; R8 would only quarter the texture bytes and drop the tint's 450 K pixels per 84 frames. Not justified by these
numbers; the drag's moving wires are new functions of their key each step (PN-E). The overscan grew the drag's rasterized
pixels by 1.4 % (extent over the clip-cut bounds).
