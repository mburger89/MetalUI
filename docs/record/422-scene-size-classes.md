# 422 - the scene's arrays reserve a size class (G52, `HP-N`)

Date: 2026-11-25. Branch `perf/g52-streaming-large-churn`, from master 810dbf1b. Class M, no divergence label. Evidence: Alloy
after #437: peak 823 to 455 MB but footprint still climbed with reply length, `Malloc Large (empty)` 160 MB in 61 regions held
through 45 s of idle.

## What was found

Probe (release build, `Sources/G52Probe`, not committed): a bottom-anchored `LazyVStack` of `MarkdownView`s, six settled replies and one
streamed a word a frame to 25 KB (4022 frames, 900x900 at 2x). Large (>= 128 KiB) requests attributed with a `malloc_logger` hook
that records a backtrace per request (main thread), symbolicated with `dladdr`. Per frame at 25 KB: 13 requests, 8.3 MB, the top five
being `Scene.reserveCapacity` glyphs 2.3 MB, `Scene.finalize` permuted glyphs 2.0 MB, its merge array 0.9 MB, two `RetainLog.SceneOp`
arrays and `BuildJournal.rebased`. They grow with the number of glyphs the scene holds (one `MarkdownView` row paints the whole reply).
The cause of the retained regions is not the bytes but the sizes: `HP-M` reserves the last frame's exact count, so every frame asks
for a block a few hundred bytes larger than the one just freed and malloc's large-block cache never serves it.

| 25 KB essay, release, 4022 frames | master | this |
| --- | --- | --- |
| `phys_footprint` over base | +126 to +133 MiB (three runs) | +51 to +67 MiB |
| `Malloc Large (empty)` | 65.9 MiB in 34 regions | 8.3 MiB in 4 regions |
| one 25 KB paragraph (no blocks) | +131 MiB, 67.8 MiB in 34 | +102 MiB, 26.5 MiB in 13 (the rest is CoreText's own glyph storage, one size per frame) |
| each block its own lazy row | +28.7 MiB, no large churn | unchanged (+30.7) |

`malloc_zone_pressure_relief(nil, 0)` after the run: footprint and regions unchanged (0.01 ms); an idle trim would do nothing.
`AppKitMenuBuilder.fill` is not 144 MB: thirty `NSImage(systemSymbolName:)` in six menus cost +3.9 MiB `phys_footprint`, once.

## What changed

`steadyCapacity` (exact under 1024, else an eighth-power-of-two step) in `Scene.reserveCapacity`, `finalize()`, retained records'
`scene`/`finalScene` and `rebased`; `finalize()` skips the sort when already ordered (its scratch block was the last
size-varying one). The same idea as `GlyphCapacity` (record 415, a quarter step) for the arrays below it.
