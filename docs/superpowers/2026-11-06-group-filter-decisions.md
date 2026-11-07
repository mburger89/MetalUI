# A shadow and a blur over a group texture — decisions (prefix `GF-`)

Rulings for R4-5 PR B: a shadow or blur outside an opacity group lifts the opacity mark every leaf shares (model F, probe `GF0`), and a leaf the CPU cannot read (a GPU surface, a leaf under a projective effect, a leaf still inside an opacity group) is filtered over an offscreen group texture on both renderers (**divergences 221 and 1066 retired; 167 stays live, reworded; 104, 105 and 1065 amended; 223 added**). Branch `feat/group-filter` (master `54aa3c43`). Record 219. Evidence: the probe `docs/probes/swiftui-group-filter.swift` (arms `GF0`..`GF6`; compiled, run twice byte-identical, 2026-11-06, macOS 27.2, Swift 6.4.2, screen locked, no computer use). Next unused id: `GF-I`.

## GF-A: routing and lifting

1. **SwiftUI** (`GF0`, the separating arm): `overlap().compositingGroup().opacity(0.5).shadow(black, 0, 10, 10)` equals the F reference (`...shadow(...).compositingGroup().opacity(0.5)`, 0 differing pixels) and differs from the S reference (a half-faded black copy drawn under the half-faded group) at 4800: **the fade is applied to the shadow and the content together**, so the shadow does not show through the half-faded group at (65, 65). `GF2`: radius 6 with the default colour is F as well. `GF1`: a **view's** `.opacity(0.5)` before a shadow is F too ((55, 55) reads half red over white), a **colour's** alpha is S ((191, 64, 64)): divergence 223.
2. `Frame.processScopes`' shadow and blur arms **lift** the marks every primitive of the leaf shares (`Frame.liftSharedMarks`: same token and alpha, outermost first, while they hold), build the item from the **unfaded** leaf and give it the lifted marks. A shadow item gets the **same tokens** as its content (model F), so `insertLeaves` puts the shadow and the content in one group; a blur item replaces its leaf and carries the marks alone, so its single-leaf bake multiplies `BlurPaint.alpha` (the quad's opacity). A blur is linear and a silhouette's alpha is linear in the group alpha, so this is exact; it also means a fade costs no CPU raster (the key never holds the alpha) and the kernel stays the CPU triple box, so nothing pops when alpha crosses 1.
3. `Frame.needsGPU(leaf)`, recursive through nested shadow and blur items: a `.surface`, a primitive under a projective record, or any mark left after lifting. Everything else is **byte for byte today's CPU path** (same keys, rasters and pins).

## GF-B: the filtered group

`insertIntoScene`'s shadow and blur arms call `insertFilteredGroup` when `needsGPU(paint.leaf)`. Space: an affine record is applied (`full = record.affine . paint.local`) and the quad is drawn plain; a projective record is left to the quad, drawn with it, `.linear` (the `PJ-L` rule, divergence 1065). Masks at or outside the scope (`!innerMask`, an outer mask with `!outerMaskInner`) are the entry clip, which cuts after the filter (B5): inside the group they are replaced by the reach box (the raster target's clip grown by the pad and the offset) or, under a non-flattening map, by an unbounded local mask; the entry clip cuts the quad. Masks pushed inside shape the leaf. The mapped leaf goes through `insertLeaves` into a fresh `Scene` (an inner opacity group composites inside it). **The shadow's offset moves the content, not the quad**: the group's target origin is the quad's origin (the projection translates by it), so a quad moved by the offset would move the content twice. The box is the painted bounds grown by pad = ceil(3 sigma) + 1, cut by the reach, floored and ceiled without libm, then widened so both sides are whole multiples of 2^L (L = `BackdropBlurReference.levels`): the quad's linear read lands on `BB-R`'s texel coordinate with no new shader. The quad is `.nearest` at L = 0 under an affine record and `.linear` otherwise; a blur's quad opacity is its alpha, a shadow's 1 (the tint carries it). Sigma = radius x `full.linearScale`; a shadow's tint is the premultiplied sRGB of its colour through the same `Hsla.toRgba` the CPU tint uses.

## GF-C: Scene

`Scene.GroupFilter` (kind none, blur, shadow; sigma; premultiplied tint), `groupFilters` parallel to `groupScenes` (permuted by `finalize()`, cleared by `clear()`), `insert(_:group:layer:transform:filter:)` (the quad's transform index lives in `filter` bits 8...31, as an image's), `paintedBounds` reads it, and `package func allSurfaceTargets()` walks the group scenes (root first, each id once): `MetalWindowRenderer` and `SDLWindowRenderer` keep and resolve the target of a surface only a group references.

## GF-D: ghosts and retained

`Scene.capturedGroup(at:)` rebuilds a filtered group as **one** `.blur` or `.shadow` captured primitive over the inner scene's captured primitives (radius = sigma, local identity, mask from the quad, colour from the tint, the quad's transform record), so a ghost goes through the same route again. A retained `.equatable()` record holds the paint values (marks included) and `replayPaint` -> `insertLeaves` -> `insertIntoScene` routes again; `RetainedTranslation` already refuses blur and shadow by name. `filterGroups` and `filtersFlattenedOversize` are `.frameLocal` in `everyFrameChannelIsClassified`.

## GF-E: Metal and the tint pass

`Renderer.encodeGroups` runs `filterGroup` after a filtered group's pass: L downsamples and a horizontal and a vertical Gaussian (the backdrop pipelines, over the whole target: clamping to the target equals zero extension because the pad is transparent and wider than 3 sigma), and for a shadow one `group_tint_fragment` pass (`tint * texel.a`, `GroupTintPass { int4 src; float4 tint }`, 32 bytes). The raw target goes back to the pool at once; the quad samples the result. Counters `lastFilterPasses`, `lastFilteredGroups`, `lastFilterAllocationFailures`, hook `filterPoolFailsAllocation`. An intermediate that cannot be made degrades by name (`BB-I`): a blur draws the unfiltered target, a shadow nothing. The stop condition holds: the tint shader reads `[[position]]` like every pass shader, no group-content shader does. `replay.hlsl` holds the same statements (`TINT_STAGE`, `tint.fragment`), `TE-AD`.

## GF-F: SDL and the fixture

`ReplayGroup` gains `filter_kind`, `sigma` and `tint[4]`; `filter_group` in `SDLBridge.c` is `blur_pass` with `g->downsample`, `g->gaussian` and the new `g->tint` (`ensure_backdrop_pipelines` builds it), counters and a `filter_pool_fails` hook. `SDLGroupSet` and `FlatFrame` carry the filter, shift a group quad's own transform index like any record's, and append a group scene's **surface quads** with their handle index (`SDLWindowRenderer` builds the handles from `allSurfaceTargets()`). `ReplayFixture` **version 8**: per group after `x, y, width, height`: `u32 filterKind, f32 sigma, f32 tint[4]` (versions 2-7 load with the filter none). Shader blobs from the pinned shadercross (`1ff05bec`): only `tint.fragment.*` is new, every other blob byte-identical. Parity frame 17 (`--expect 18`).

## GF-G: limits and fallbacks

A filtered leaf whose box exceeds `Frame.maxGroupTargetSide` (8192) takes the CPU arm (`filtersFlattenedOversize`): it draws what the CPU can read (a shadow's affine primitives, a surface as its quad; a blur's affine non-surface primitives). Not a divergence label (as `GO-C`'s oversize). **248 stays** (a material inside a shadow, blur or composite draws its flat tint), as does **222**. No cross-frame cache: a filtered group costs one group pass, L downsamples, two Gaussian passes and, for a shadow, one tint pass every frame.

## GF-H: divergences

**Retired: 221, 1066.** **167 stays live, reworded** (a GPU surface under a blur is now blurred; SwiftUI's side for platform views is unmeasured, `W1` not run because the screen was locked; human check `GF3`). **Amended: 104** (a surface's shadow is its pixels' unless the box is oversize), **105** (the GPU path is a true Gaussian, the CPU path stays the triple box), **1065** (a GPU-filtered leaf under a projective record is resampled from creation space). **Added: 223** (a view's `.opacity` inside a shadow fades the shadow's source: model S where SwiftUI is F, `GF1`), pinned wrong on purpose, owner none.

## Carried

- `W1` (a layer-backed `NSViewRepresentable` under `.blur(radius: 6)` in a real window): run it on an unlocked screen, and retire 167 if SwiftUI blurs it (record 219).
- 223: a view's opacity as a mark (a `groups` mark at the opacity modifier rather than the colours) would give F for a single leaf.
- 222's surface clause could follow cheaply now that group scenes resolve surfaces.
