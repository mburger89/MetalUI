# 3D render effects — decisions (prefix `PJ-`)

Rulings for round-3 item R3-10 item 6: `rotation3DEffect`, `projectionEffect`, `transformEffect`, `ProjectionTransform`. Branch `feat/projection-effects`
from master `5c47e0d8`. Code: `Sources/MetalUI/Homography2D.swift`, `ProjectionTransform.swift`, `RenderEffects.swift`, `Transition.swift`, `Hitbox.swift`, `Frame.swift`.
Probe: `docs/probes/swiftui-projection-effects.swift` (recorded, compiled, two byte-identical runs). Tests: `ProjectionEffectTests.swift`, the `LayoutModifier` guard in
`RenderEffectCompileGuards.swift`. Record: `docs/record/193-projection-effects.md`. **Next unused: `PJ-L`.**
Divergences reserved 1065-1074: **1068 used**; 1065-1067 and 1069 are the paint rulings (below) and are unused until the GPU record lands; 1070-1074 unused.

**State of this branch.** Rulings A-F, H-K are built. **`PJ-G` (paint) is not**: the 80-byte `MUITransform`, both shader backends, the rebuilt SDL blobs
and the parity frame need the pinned `shadercross`, which was not installed where this was written; a projective scope paints nothing until they land
(`paintWithDeviceMap`, marked `PJ-STEP4`). Hit testing, accessibility, geometry, right-to-left, animation and retained refusal are complete.

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

## PJ-G: paint (not built here)

One 3x3 per draw, no offscreen pass; `MUITransform` 64 to 80 bytes, lane 4 `(g, h, i, det3)`, `det3 == 0` meaning affine; the vertex stage emits `(X, Y, 0, W)`, the fragment
`local = H^-1(screen)`; paths, shadows and gradients rasterise flat in creation space and are resampled (divergence 1065); an enclosing shadow, blur or composite drops projective
leaves (1066); a material or glass draws its flat tint (1067); overflow crossing behind the eye is dropped per primitive (1069). Amends 106, 109.

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
