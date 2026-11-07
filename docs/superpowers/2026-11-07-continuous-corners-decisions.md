# Continuous rounded corners - decisions (prefix `CC-`)

Rulings for R4-5 PR F, run 1: SwiftUI's `.continuous` corner for every outline (**divergence 90 narrowed, not retired**: a continuous clip and multi-member glass stay circular, carried to run 2; live 208 with 167 retired, next label 227). Branch `feat/continuous-corners` (master `17b76c1b`, merged with `#222`). Record 226. Evidence: `docs/probes/swiftui-continuous-corners.swift` (arms `CC0`..`CC10`; compiled, run twice, identical, 2026-11-07). Next unused id: `CC-J`. Carried: `CC-I`.

## CC-A: the curve is read, not fitted

A corner of radius `r` is three cubics (`ContinuousCorner`, `MetalUIPath`, imports nothing): `A` `(t,0) (c1,0) (c2,0) (0.631493986, 0.074911401)`, the fixed middle `B`, `C` its mirror, with `t = min(room / r, 1.528664947)`, `c1 = 0.716953795 + 0.243046205 t`, `c2 = 0.728435369 + 0.091564631 t`. A side's room is `side * r / (r + neighbour's r)`. Agreement with SwiftUI's elements 7.5e-6 absolute. The pixel arm reads an exact-area metric (the shape fill is not rasterised like a generic Path at 1x): model 2.72 pt2, circular 18.2, superellipse 243.

## CC-B: uneven and elliptical

Uneven radii fit horizontal sides first (top, then bottom), then vertical (right, then left), each pair by `fitPair`; this also fixes the circular `UnevenRoundedRectangle` (39 of 847 mismatches before). An elliptical `cornerSize` scales as a pair. The outline starts at `(tr + h - br)/2` on the right edge and runs BR, BL, TL, TR.

## CC-C: one kind, per-corner radii

`PrimitiveShape.continuousRoundedRectangle = 2`, the byte `MUIRect.shape`/`MUIBackdrop.shape` already hold: no stride, struct or fixture change (version 9). Any nonzero radius is kind 2; all zero is kind 0. `UnevenRoundedRectangle(.continuous)` is the renderer's rect while each corner's curve stays in its quadrant (a reach past the half is allowed while its tail is under 0.01 px off the side, `fitsQuadrants`), else a `Path` (`PG-G`).

## CC-D: the distance

`rect_sdf` first; where `|d| <= 0.02 r + band` the nearest point of one cubic, picked by the tangent at each joint (3 seeds, 3 Gauss-Newton steps, 1.8e-5 r), plus the straight rays, the sign from the tangent; a point more than 0.2 r away (a wide border) searches all three with 4 Newton steps. `shaders.metal` and `replay.hlsl` identical (`TE-AD`); a test pins the constants in both to `ContinuousCorner`. Accuracy: 3 levels (0.012 px) up to r 256.

## CC-E: borders

The border is the ellipse branch's band on the inset curve: `strokeBorder(w)` = stroke of the shape inset by `w/2` with radii less `w/2` (`CC5`, 0 px on four pairs); `stroke(w)` the same over the outset rect; a non-positive inset radius is left square (Chebyshev, `CC5b`). `paintShapeStroke` keeps a continuous radius whole (no `kept` rule).

## CC-F: its own fragment entry

Measured: the continuous code inside `rect_fragment` cost the circular kind 9 % (3.000 to 3.270 ms). `rect_continuous_fragment` (and `continuous.fragment`, `-DCONTINUOUS_STAGE`, a pipeline in `Renderer` and `SDLBridge.c`) carries it; `Scene.finalize` starts a rect run wherever the continuous kind changes and the pipeline is read from the run's first rect, so no run kind, fixture or bridge format moves. Kind 0's shaders are the base's byte for byte. Cost accepted: 1.49x (96×64 r 20) and 2.46x (24×24 r 12).

## CC-G: silhouettes and keys

`RasterMath.outline`/`continuousOutline`; a border silhouette is the stroked inset outline. `keyLeaf` (shadow and blur) already carries `shapeKind`.

## CC-H: Path and hit tests

`Path.addRoundedRect(in:cornerSize:style:)`, `Path(roundedRect:)`, `Path(ShapeGeometry)` emit the continuous cubics for `.continuous`; `ShapeGeometry.contains` is the path's winding.

## CC-I: carried (run 2)

A continuous clip (`ShapeGeometry.clip`, `pushClip`, `Frame.intersect`/`clipsCross`, the 19 `activeClipRadii` readers, `mask_coverage` and its scaled twin, the transform outer mask) and multi-member glass (`GlassMember` radii, `glass_member_sdf`). It needs a sign test in `mask_coverage`, which `rect_fragment` calls: touching kind 0's shader is deferred (user decision). `GlassReference` (the CPU twin) draws kind 2 circular.
