# Cold-frame profile of the bracket window (C14-e (b), `CF-F`, `CF-K`)

Measurement notes, dated 2026-10-20, MacBookPro18,2 (M1 Max), macOS 27.0.1, Swift 6.4, **release**. Other workflows shared the Mac:
one-minute load average 4.5 to 34 over the runs (stated per run in each TSV's `load_average` line), so every figure is thread-CPU time
(`CLOCK_THREAD_CPUTIME_ID`), medians of 12 (or 30) fresh windows per run, three runs per commit, alternated. Dated measurements, never pins.

Instrument: `cold-profile.sh <commit> [rounds] [--trace]` (this directory): `git archive` of the commit into `/tmp/metalui-cold-<sha>`,
`cold-harness` (public API only, so it builds at every commit below) with the commit's own `BracketFixture.swift`, a counters line that
reads only fields present at that commit. Frame 0 is `TestWindow.init` (it draws the window's first frame), frames 1-2 unchanged redraws,
frames 3-5 orbit frames (viewport token bumped, panels unchanged). `--trace` records `xctrace` Time Profiler over 150 fresh windows,
frame 0 only (`--cold-only`); export with `xctrace export --xpath '/trace-toc/run[1]/data/table[@schema="time-profile"]'` and aggregate
inclusive samples per frame name (the 1 ms samples are the weights).

## Frame 0 (the cold frame), `.panels` arm, thread-CPU ms, three runs each

| Commit | What it is | frame 0 | counted work at frame 0 |
|---|---|---|---|
| `a595b0d7` | before retained subtrees (C14b design commit: fixture, no retention) | 12.70 13.01 13.01 | measures 325, memo hits 695 / **misses 639**, no ledger, raster 124 852 px |
| `fb9a7e42` | C14b lane 1 + 2 (retained paint, placement memo) | 14.32 15.59 14.40 | measures 303, memo 658 / **864**, **70 ledger snapshots**, 32 retained misses, raster 124 852 |
| `6273e3a4` | C14b-2 (prepaint replay, graft) | 14.44 15.12 14.27 | identical to `fb9a7e42` |
| `679f5d7d` | base of this branch (+ C14-c, RW-, MO-, P3, P4) | 14.20 13.99 13.89 (and 14.14 14.39 13.57) | identical, except raster **255 208 px** (P4 overscan) |
| head `9264a660` | + CF-J (placement footprint) | 14.00 15.43 14.68 (and 14.36 14.08 15.14) | identical to `679f5d7d` |

The `.value` arm reads the same pattern (12.66 to 13.03, then 13.0 to 14.4). Warm frames fall the other way as retention matures:
frame 1 reads 7.2 (`a595b0d7`), 5.9 (`fb9a7e42`), 3.9 (`6273e3a4`), 4.1 (`679f5d7d`); an orbit frame (frame 3) 7.4, 5.9, 3.6, **2.5**.

## Attribution (Time Profiler, 150 fresh windows, 1969 samples at `679f5d7d`, 1974 at `a595b0d7`)

Inclusive share of the cold frame (`Frame.render` = 91.6 % of samples; the rest is window and fixture setup):

| Where | `679f5d7d` samples (share) | `a595b0d7` samples |
|---|---|---|
| layout kernel, `computeNativeLayout` | 522 (26.5 %) | 596 |
| build, `Component.requestGroupLayout` | 482 (24.5 %) | 448 |
| paint, `Component.paintGroup` | 608 (30.9 %) | 608 |
| prepaint | 187 (9.5 %) | 137 |
| glyph rasterization (`GlyphRaster.rasterize`) | 74 (3.8 %) | 85 |
| path rasterization (`Frame.pathImage`) | 65 (3.3 %) | 72 |
| memo-miss handling: `prepareMemo` 25, `LayoutMemo.lookup` 14, `LayoutMemo.store` 11 | 50 (2.5 %) | 61 |
| **retained bookkeeping**: `finishRetainedPaint` 11, `retainedPrepaintPhase` 13, `readRetainedGeometry` 9 | 33 (1.7 %) | 0 |
| `ContentMemoStore.materialize` (the `.equatable()` getter and its observation session) | 48 (2.4 %) | 0 |

- **Ledger snapshots cost nothing measurable.** `ledgerSnapshot()` is five loads and a struct (`RetainedSubtree.swift:429`); 70 of them
  per cold frame are below the profiler's resolution (no frame of its own survives inlining). The "2 per retained miss" counter is
  real, its cost is not.
- **Memo-miss handling** is 2.5 % of the cold frame, and the layout kernel itself is *cheaper* than before retention (522 against 596
  samples; the cause is unattributed).
- **Retained bookkeeping plus the content memo is 4.1 %** (81 samples of 1969), offset by the kernel's 74 fewer; total samples equal
  within 0.3 %, and the interleaved thread-CPU medians (12.7 to 13.0 against 14.0 to 14.4) read **+8 to +11 % from `a595b0d7` to
  `fb9a7e42`, and flat afterwards within the run-to-run spread (about 5 %)**.
- **P4's overscan doubles the cold raster** (124 852 to 255 208 pixels at `679f5d7d`) and moves the cold frame by less than the
  spread: the bracket fixture's rasters are strokes (3.3 %) and glyphs (3.8 %), so 130 k extra pixels are not where its time is.
- `memoMisses` rose 639 to 864 (+35 %) at C14b (`fb9a7e42`), where the placement memo and retained records arrived, and has not moved
  since; `retainedLedgerSnapshots` 70 has not moved since `fb9a7e42` either. The fixture does not show a rise at `6273e3a4`.

## What this does and does not show

MetalCreator's cold orbit-panel-left frame (+25 % time, +9 % counted work against the 10-13 pin) is **not reproduced** by this fixture: on it the
cold frame rose about 10 % once, at C14b, and is flat since. Where MetalCreator's tree differs (shadows, blurs and gradients under P3/P4's
overscan, 3D viewport) the extra cost is in raster work this fixture cannot show; the next measurement belongs on MetalCreator's own tree
with `rasterizedPixels` and the ledger counters beside the times. No value-identical cold-frame win was measured, so none is landed
(`CF-F` (i)). The named candidate (not snapshotting a ledger on a first sighting) would save nothing visible, and is **wrong in principle**:
the record made on first sighting is the one that hits next frame, and its before-snapshot is what taints it.
