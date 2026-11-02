# 3D render effects — decisions (prefix `PJ-`)

Rulings for round-3 item R3-10 item 6: `rotation3DEffect`, `projectionEffect`, `transformEffect`, `ProjectionTransform`. Branch `feat/projection-effects`
from master `5c47e0d8`. Code: `Sources/MetalUI/Homography2D.swift`, `ProjectionTransform.swift`, `RenderEffects.swift`, `Transition.swift`, `Hitbox.swift`, `Frame.swift`.
Probe: `docs/probes/swiftui-projection-effects.swift` (recorded, compiled, two byte-identical runs). Tests: `ProjectionEffectTests.swift`, the `LayoutModifier` guard in
`RenderEffectCompileGuards.swift`. Record: `docs/record/193-projection-effects.md`. Also `ProjectionPaintTests.swift`, `Tests/MetalUIRenderTests/ProjectivePrimitiveTests.swift`, the fixture and SDL tests, parity frame 15.

**State.** Every ruling is built. The pinned `shadercross` (`1ff05bec`, `docs/packaging.md` 4a) was built outside the repo at `~/Developer/tools/shadercross`; before the rebuild it reproduced the checked-in blobs byte for byte (HEAD's `replay.hlsl` compiled to an identical `compiled/`). Divergences 1065-1069 used (1070-1074 unused). **Next unused: `PJ-N`.**

## PJ-A: `Homography2D`

A 3x3 map `(a b c d tx ty g h i)` in `Double`, internal. Every operation has an affine fast path (two affine operands run `Affine2D`'s own formulas), so an affine effect is
bit-identical. Carrier fields changed type so the compiler found every reader: `PrepaintEffect.composed/inverse/map`, `HitboxTransform.inverse`, `PrimitiveTransform.homography`,
`RenderEffect.homography`, `AXEffectStep.map`, `GeometryProxy.composed`, `NamedSpace`. A reader needing an affine asks for `.affine` and handles `nil` (raster sites read
`transform?.affine ?? .identity`, i.e. creation space). `Affine2D` gains no `g h i` (a direct reader would silently drop the perspective).

## PJ-B: measured semantics (probe)

`rotation3DEffect(_:axis:anchor:anchorZ:perspective:)` (eight animatable numbers); `projectionEffect` and `transformEffect` snap. View-local `v = (x - ax, y - ay, -anchorZ)`,
right-handed Rodrigues about the normalised axis, `d = max(W, H) / perspective`, `w = 1 - v'z / d`, screen `(ax + v'x / w, ay + v'y / w)`; `anchorZ` is not added back; an exactly
zero angle or a zero axis is the identity (even with `anchorZ`); a negative `perspective` is the negated angle; 0 is orthographic. `ProjectionTransform` is row-vector with a w
column, in the view's own points. `transformEffect` takes `Transform2D` (CoreGraphics order, local to the view).

## PJ-C: behind the eye

A view with any corner of its rectangle on or behind the eye (`w <= 0`) draws nothing (measured: one corner at w -0.2; `m13` -0.01; 60 degrees at perspective 2.5, not 2.2). Exactly 90
degrees is edge-on. A window point whose inverse has `w <= 0` hits nothing; a bounding box over such a rect collapses to an empty one.

## PJ-D: layout, nesting, clipping

Layout is unaffected. Each effect is its own projective map and nested maps compose. A clip after the effect clips to the layout rect; a clip inside is projected.

## PJ-E: hit testing, geometry, accessibility

`Hitbox.contains` maps the window point through the inverse homography (the divide, `nil` behind the eye). `frame(in: .global)` and the accessibility frame are the bounding box of the
projected quad (measured for geometry; accessibility by the same chain, unmeasured, `AT-A`/`AT-G` unchanged).

## PJ-F: right to left

Every effect is conjugated by the reflection about the rect's centre line (`LD-C`): `rotation3D` becomes axis `(x, -y, -z)` with anchor x `1 - x` and the same angle; a projection is
`F . M . F` (`transformEffect` tx 30 becomes -30, `m31` 30 becomes -30, `m32` unchanged).

## PJ-G: paint

One 3x3 per draw, no offscreen pass. `MUITransform` is 80 bytes, five `float4` lanes; lane 4 is `(g, h, i, det3)` and `det3 == 0` means affine, so every old record and scene runs the old code byte for byte (the 64-byte `Scene.transformIndex` zeroing of `_reserved` is unchanged; a compatibility `init` without the tail keeps every affine call site). The vertex stage emits the homogeneous clip point `(2X/vw - W, -2Y/vh + W, 0, W)` so the rasteriser interpolates the local position perspective-correctly (the fringe is one over the smallest `sqrt(|det3| / w^3)` of the four un-grown corners); the fragment recomputes `s = sqrt(|det3| / w^3)` and the outer mask's screen point from the local point. `+ - * / sqrt` only, `shaders.metal` and `replay.hlsl` statement for statement. A primitive with a corner at `w <= 0` is dropped per primitive (divergence 1069); an effect whose rectangle has such a corner paints nothing. Backdrop and glass stages are never given a projective record: a backdrop degrades to its flat tint at the scope (1067).

## PJ-L: creation-space rasters (divergence 1065)

A path, shadow, gradient or blur under a projective record is rasterised in its creation space (`RasterPlacement`: local content mask, clip bounded by the window) and inserted as a linearly filtered image **with** the record, so the cache key does not depend on the effect and an animating flip makes no texture after its first frame. A shadow, blur or composite scope enclosing a projective leaf drops it from the silhouette and draws it unblurred (1066).

## PJ-M: SDL and the fixture

`SDLBridge.c` `TRANSFORM_STRIDE` is 80. The replay fixture is version 6; versions 2-5 still load (a 64-byte record is widened with a zero lane 4, which is affine). The blobs and `SOURCE.sha256` are rebuilt with the pinned shadercross. Parity frame 15 (`Experiments/SDLGPU`, `projectionFrame`) is judged as frame 7 is; the workflow's `--expect` is 16.

## PJ-H: API

`LayoutModifier.rotation3DEffect` and `.projectionEffect` are `indirect` (the 1 MB Windows stack; `MemoryLayout<LayoutModifier>.size` is pinned at 81). Both vocabularies get all three
modifiers. Not offered: the `Rotation3D` overloads (visionOS), `VisualEffect` overloads, `ProjectionTransform.init(CATransform3D)`, and the effects on a `Component` (`GX-P` item 5).

## PJ-I: divergence 1068

`ProjectionTransform` has `Double` fields and no `init(CATransform3D)`; `transformEffect` takes `Transform2D`, not `CGAffineTransform` (amends 945).

## PJ-J: animation

`rotation3DEffect` interpolates angle, axis x y z, anchor x y, `anchorZ` and `perspective` (`RenderEffectSpec.numbers`, `ProposalAnimation`). `projectionEffect` and `transformEffect`
snap (a change of kind snaps, `LR-AS`).

## PJ-K: retained

An equal key replays (it holds every number). Any change in a projective effect, and a pan composed onto one, refuses by name `effectProjective`, in both the paint scopes
(`AmbientKey`: the projective flag word 3 = 2, compared before the outer-clip words) and the prepaint vectors (`PrepaintExtras` indices 19-24, appended only, `RZ-M`).
