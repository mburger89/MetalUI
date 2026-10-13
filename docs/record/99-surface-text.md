# 99 — Text over a GPU surface (C23)

Branch `feat/surface-text` from `d6a815c`. Not a plan task: item C23 of the
gpui-gap priority list (user request 2026-10-02), requested by MetalCreator
(gap S5-c). Spec `docs/superpowers/specs/2026-10-12-surface-text-design.md`;
rulings `GT-A`…`GT-G` in `docs/superpowers/2026-10-12-surface-text-decisions.md`
(next unused `GT-H`); probe `docs/probes/swiftui-surface-text.swift`.
Divergence labels reserved: 295–304.

**Status: DESIGNED — not yet built.** Phase log below grows with each phase.

## §1 The measurement (design phase, `d6a815c`)

`Tests/MetalUITestingTests/SurfaceTextOverlayCostTests.swift`, test
`measureTheOverlayCost`; the scenario and the table are `GT-A`. Re-taking it
(C14 recipe): `swift test --build-system native --no-parallel --filter
measureTheOverlayCost` (after lane 1, `theOverlayCostIsLinearAndCounted`) and
compare the rows; the columns are `FrameWork` fields and the counting text
system's seam calls. Output at `d6a815c`:

```
C23 n=0 distinct=true per-frame: builds=1 measureCalls=1 hits=1 misses=2 glyphs=0 atlasUpload=0 | textSystem measure=0 place=0
C23 n=20 distinct=true: builds=1 measureCalls=21 hits=21 misses=22 glyphs=110 atlasUpload=0 | measure=40 place=20
C23 n=100 distinct=true: builds=1 measureCalls=101 hits=101 misses=102 glyphs=590 atlasUpload=0 | measure=200 place=100
C23 n=20 distinct=false: builds=1 measureCalls=21 hits=21 misses=22 glyphs=120 atlasUpload=0 | measure=40 place=20
C23 n=100 distinct=false: builds=1 measureCalls=101 hits=101 misses=102 glyphs=600 atlasUpload=0 | measure=200 place=100
```

Reading: linear in N, per label 1 leaf measure, 2 seam measures, 1 `placeGlyphs`;
no rasters, uploads or textures. CoreText shapes a moving label 0 times; the
portable system once per frame per label (fixed by `GT-E`). Decision: `GT-A`.

## §2 The SwiftUI probe

`docs/probes/swiftui-surface-text.swift`, output in its header (macOS 27.0, run
twice, byte-identical): Canvas `ResolvedText.measure(in:)` equals the view's ideal
size (51, 16); wraps at 60 (60, 80); a 5-point height proposal caps at one line;
reads the environment font; the empty string is (0, 14) there and (0, 0) as a
view; baselines are functions of a size.

## §3 Deferred

`drawText` (GT-F), baselines and `GraphicsContext` (GT-G).
