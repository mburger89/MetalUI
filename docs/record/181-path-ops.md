# 181 - path operations (`PG-A`..`PG-H`)

2026-10-31, branch `feat/path-ops` from `519a1ebe`; round-3 item R3-8. Rulings: `docs/superpowers/2026-10-31-path-ops-decisions.md`. Probe: `docs/probes/swiftui-path-ops.swift` (output recorded in its header). Divergences 945-947 of the reserved 945-954; live count 179 -> 182.

## 1. What landed

- `Path.trimmedPath(from:to:)`, `Shape.trim(from:to:)` (`TrimmedShape`, animatable): true arc length across all subpaths, closing edge counted, fractions clamped, reversed/equal/NaN empty, a whole subpath keeps its close, a trimmed Bézier stays a Bézier (`PG-A`). `MetalUIPath`: `PathGeometry.trimmed(from:to:)`, `arcLength`, Simpson on the exact speed with a 4-point Neville distance-to-parameter map (`PG-C`).
- `Path.strokedPath(_:)` over the existing `Stroker` (`PG-B`, divergence 946).
- `Path.addRelativeArc(center:radius:startAngle:delta:transform:)` (unclamped signed sweep, `PG-D`), `Path.applying(_:)`, `Transform2D`, and a trailing `transform:` on `addRect`, `addRects`, `addRoundedRect`, `addEllipse`, `addPath`, both `addArc`s (`PG-E`, divergence 945). `offsetBy` already existed.
- `UnevenRoundedRectangle(cornerRadii:style:)` / `(topLeadingRadius:...)`, `RectangleCornerRadii` (`PG-G`): **no new GPU primitive and no shader change** - the SDF already takes four circular radii; a fitted radius past half the shorter side (SwiftUI allows it) is drawn as a path. Divergence 90 (`.continuous` drawn circular) and 91 (a path cannot clip) apply. `ContainerRelativeShape` not done (out of scope).
- Built-in outlines start where SwiftUI's do (`PG-H`): `Path(ShapeGeometry)` changed; a dashed stroke of a built-in now starts its pattern there.
- `trim` animation (`PG-F`): internal `PaintAnimatedShape` + `shapeForPaint`, called by `ShapeView.paint` and `Shape`'s default `paint`; `animatedNumbers` at `$anim-layer.trim`.

## 2. SwiftUI probe (selected)

Run 2026-10-31, macOS 27.2, Apple Swift 6.4, compiled, twice, byte-identical. Arc length, not per element: L10+L90 trim(0,0.5) ends (10,40); quarter circle r100 trim(0,0.5) ends (70.711,70.711); fractions run across subpaths (10+90: 0..0.5 -> 10 + 40); a closed square's 0.9..1 is (0,4)->(0,0); a closed triangle's closing edge counts (0.9 -> (2.414,2.414)); 0..1 keeps `Z`; from>to and from==to empty; -0.5 and 1.5 clamp. Starts: Rectangle (0,0); RoundedRectangle/Capsule (100,30) in 100x60 running down; Circle (80,30); Ellipse (100,30); Uneven 30/10/20/0: (100,20) = (tr + (h - br))/2. Relative arc: +90 ends (50,100), -90 (50,0), 450 ends (50,100), 1000 ends (58.682,0.760) - not capped. Uneven radii: circular TL45 on 100x60 stays 45; 45/45 -> 30/30; 20/50 -> 20/40; 70/70 on 100 -> 50/50; 80 on 60 high -> 60; all 40 -> 30; negative -> 0. `strokedPath`: ring samples, dash gaps, miter tip (10,12.828); `Path.boundingRect` is not tight at a miter tip (the V arm reads elements).

## 3. Tests and mutations

New: `Tests/MetalUIPathTests/PathTrimTests.swift` (16, portable: runs on Linux and Windows CI; independent 1e-7 flattening oracle for lengths and fractions; coverage by winding sampling, since the stroker's inner side runs through the vertex and signed area is not the band's) and `Tests/MetalUITests/PathOpsTests.swift` (16).

Mutations (applied to `Sources/`, one `swift test --filter 'PathTrimTests|PathOpsTests'` per group, source restored by `git checkout`; groups of mutations that redden different tests ran together):

| mutation | tests turned red |
|---|---|
| PGM1 closing edge left out of a closed subpath's length | `theArcLengthOfStraightPathsIsExact`, `aClosedSubpathCountsItsClosingEdgeAndKeepsItsCloseWhenWhole`, `outOfRangeFractionsClampAndAnEmptyRangeIsEmpty`, `aBuiltInShapesOutlineStartsWhereSwiftUIsDoes` |
| PGM2 Simpson's midpoint term dropped | `aCurvesLengthIsItsTrueArcLength`, `aTrimmedCurveEndsAtTheRightArcLengthAndStaysACurve`, `trimmedPathIsBitIdenticalEverywhere` |
| PGM3 segment offset not advanced (each segment measured from 0) | `fractionsAreArcLengthNotPerElement`, `pathTrimmedPathIsArcLength`, `aClosedSubpathCounts...`, `outOfRangeFractions...`, `aBuiltInShapes...`, `aBareTrimmedShapeAnimatesToo` |
| PGM4 distance to parameter as `d / length` | `aTrimmedCurveEndsAtTheRightArcLengthAndStaysACurve`, `trimmedPathIsBitIdenticalEverywhere` |
| PGM5 subpath offset reset (fractions per subpath) | `aFractionRunsAcrossSubpaths` |
| PGM6 whole subpath copied without `close` | `aClosedSubpathCountsItsClosingEdgeAndKeepsItsCloseWhenWhole`, `anUnevenOutlineIsSwiftUIs` |
| PGM7 reversed range swapped, not emptied | `outOfRangeFractionsClampAndAnEmptyRangeIsEmpty`, `pathTrimmedPathIsArcLength` (and the group's others) |
| PGM10 cap ignored by `stroked` | `aStrokedLineIsItsOutlinePolygon` |
| PGM11 closed subpath stroked open | `aClosedPathStrokesToABand`, `strokedPathOfAClosedRectAndOfATrim` |
| PGM12 dash ignored | `aDashedStrokeIsOnePolygonPerDashAndAZeroWidthIsEmpty`, `strokedPathFillsAndHitTestsAsTheStroke` |
| PGM13 join ignored | `joinsReachTheProbesExtents` |
| PGM14 negative delta swept positive | `aRelativeArcSweepsBySignedDelta`, `pathAddRelativeArcSweepsBySignedDelta` |
| PGM15 relative sweep capped at a turn | `aRelativeArcPastATurnKeepsGoing`, `pathAddRelativeArcSweepsBySignedDelta` |
| PGM16 rounded rectangle start moved to the top-right corner | `aBuiltInShapesOutlineStartsWhereSwiftUIsDoes`, `anUnevenOutlineIsSwiftUIs` |
| PGM17 `shapeForPaint` returns the shape | `trimAnimatesItsEndFraction`, `bothFractionsAnimate`, `aBareTrimmedShapeAnimatesToo` |
| PGM18 `Shape.paint` skips `shapeForPaint` | `aBareTrimmedShapeAnimatesToo` |
| PGM19 `strokedPath` returns `self` | `strokedPathFillsAndHitTestsAsTheStroke`, `strokedPathOfAClosedRectAndOfATrim` |
| PGM20 `rotated(by:)` applied after the receiver | `transform2DAppliesInCoreGraphicsOrder` |
| PGM21a-h `transform:` ignored by `addRect`, `addEllipse`, `addRoundedRect`, `addPath`, `addRects`, `addRelativeArc`, `addArc`, tangent `addArc` | `addMethodsTakeATransform`, nine expectation lines (223-256), one per method |
| PGM22 fitted radii also clamped to half the shorter side | `radiiFitByTheSwiftUIRule`, `anUnevenOutlineIsSwiftUIs`, `anUnevenRectangleUsesTheSDFWhenItCanAndAPathWhenItMust` |
| PGM23 outline start at the edge midpoint, radii ignored | `anUnevenOutlineIsSwiftUIs` |
| PGM24a never the SDF | `anUnevenRectangleUsesTheSDFWhenItCanAndAPathWhenItMust` |
| PGM24b always the SDF | `anUnevenRectangleUsesTheSDFWhenItCanAndAPathWhenItMust` |

**Survivors.** PGM9 (the speed's `sqrt(x/2) * sqrt2`) and PGM9b (Simpson's `/ 6 * h` association) leave `trimmedPathIsBitIdenticalEverywhere` green: the pinned length and end point do not move under sub-ulp reassociation, so that test catches algorithmic drift (PGM2, PGM4 redden it), while bit-identity across platforms rests on the target importing nothing (no libm, no FMA - `grep import Sources/MetalUIPath` is empty). Two draft mutations were harness errors, not findings (a redeclared `style` and `lo`; two edits stacked on one line) and were rewritten. Chord sums with Richardson extrapolation were the first length method; measured 3e-4 off at a mid-curve fraction of a quadratic, replaced by Simpson (`PG-C`).

## 4. Counts

`swift package clean`, `swift build --build-system native --build-tests`, then an unfiltered `swift test --build-system native --no-parallel` (screen on the console; the sheet tests skip by themselves when locked): **4697 tests in 12 suites, 357.966 s**, `FR-J no-argument frame: succeeded=true` printed. That run had **2 issues**, both typecheck guards (`thePathAndShadowSpellingsCompileFromAPlainImport`, `anOutsideShapeCanWritePathInAlone`) whose negative controls were `trimmedPath` and `applying`, now built; they use `subtracting` and `forEach` (absent) and pass (re-run alone, native: 3 tests passed). The default build system's unfiltered run before that fix: 4697 passed in 16 summaries, 0 issues (the guards skip there). New tests: 32 (16 + 16); the base reads 4635 + the later merges, so no other test moved.

## 5. Carried

`ContainerRelativeShape`; SVG strings; `UnevenRoundedRectangle` with all radii 0 starts top-left (SwiftUI mid-right); `.continuous` curves; an `Animatable` protocol (a custom `Shape` still cannot animate its own number); human checks group PG (unrun, an agent cannot).
