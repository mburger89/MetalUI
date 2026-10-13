# Text over a GPU surface — design (C23)

Item C23 of the gpui-gap priority list; MetalCreator gap S5-c. Rulings
`GT-A`…`GT-G` in [`../2026-10-12-surface-text-decisions.md`](../2026-10-12-surface-text-decisions.md);
probe `docs/probes/swiftui-surface-text.swift`; measurement test
`Tests/MetalUITestingTests/SurfaceTextOverlayCostTests.swift` (written in the
design phase as a printing measurement; the lane-1 agent turns it into test
1.10 below in the same file; table in the decisions doc and record §99). Branch
`feat/surface-text` from `d6a815c`. Divergence labels 295–304.

**Status: LANDED** (record §99, 2026-10-12): both lanes built and verified; `GT-A`…`GT-I`; the one look (GT1) is owed to a human.

## 1. What is built, what is not

| | | ruling |
|---|---|---|
| Built | `TextMeasurer` / `TextMeasurer.ResolvedText`, `EnvironmentValues.textMeasurer`: SwiftUI's `resolve(_:)` + `measure(in:)` | GT-B…D |
| Built | `PortableTextSystem` caches the origin-free layout, so a moving text shapes once | GT-E |
| Built | the overlay cost measurement kept as a baseline pin for C14's re-take | GT-A |
| Deferred | `MetalDrawContext.drawText`, `SDLGPUDrawContext` twin, shader work | GT-F |
| Deferred | the layout cache for styled (rich) text on the portable system, `GT-H` |
| Deferred | `firstBaseline(in:)`/`lastBaseline(in:)`, `GraphicsContext` | GT-G |

No platform/protocol requirement changes: `TextSystem`, `PlatformWindow`,
`Platform`, `WindowRenderer` and the shaders are untouched, so no migration note,
no replay-parity run, no `Backends/SDL` source change.

## 2. Public API (lane 1)

```swift
public struct TextMeasurer {                       // no public init
    public func resolve(_ text: Text) -> ResolvedText
    public func resolve(_ text: ProposalText) -> ResolvedText
    public struct ResolvedText {
        /// The size `text` is laid out at under `proposal`; infinite = unbounded.
        public func measure(in proposal: Size<Pixels>) -> Size<Pixels>
    }
}
extension EnvironmentValues { public var textMeasurer: TextMeasurer { get } }   // get-only
```

Semantics (GT-C): exactly `proposalTextMeasurement` / `richTextMeasurement`
(layout's functions) over `resolveTextStyle(request, in: environment)` and the
frame's text system; the environment is the one at the reading element; the
resolved value captures the style, key and system, not the `Text`. Empty string
as `Text("")` lays out: 0 wide, one line tall (divergence 295, `GT-I`); the answer is
the unrounded leaf answer, a frame is that rounded to whole points (`GT-I`). Delivery (GT-D): get-only computed property over an
internal stamped system box; trap (named) with none.

Files, lane 1: new `Sources/MetalUI/TextMeasurer.swift`; edits to
`EnvironmentValues.swift` (internal box field, computed property),
`Frame.swift` (`rootEnvironment` setter stamps, `scopedValues` restores);
`docs/probes/closeout-inventory-map.tsv` (rows: `TextMeasurer`,
`TextMeasurer.ResolvedText`, the two `resolve`, `measure(in:)`,
`textMeasurer` — class `M`, divergence column 296), re-recorded census
(`closeout-public-api.sh`), doc comments, `docs/api-overview.md` (a "Measuring
text" paragraph), `docs/divergences.md` rows 295 (an empty `Text` is one line tall, probe E2) and 296 (carrier is the environment, no `GraphicsContext`),
`docs/testing.md` (a recipe: measure in a `Component`, assert in a
`TestWindow`), `docs/migration.md` none. Tests in
`Tests/MetalUITestingTests/SurfaceTextMeasureTests.swift` (portable, plain
imports, `harnessWindow`) and `Tests/MetalUITests/TextMeasurerGuardTests.swift`.

## 3. Portable layout cache (lane 2)

Plain text only (`GT-H`): `layOut(_ text: StyledText…)` is unchanged.

`PortableTextSystem`: `private var layouts: [MeasureKey: Entry<[LaidOutLine]>]`
beside `measurements`, same generation filter in `endFrame`; `measure`,
`placeGlyphs`, `lineRanges` read/fill it; `LineEmission.placements` gains a
form taking the lines; internal `layOutCount` counts `PortableText.layOut`
calls. Files, lane 2 only: `Sources/MetalUIPortableText/PortableTextSystem.swift`,
`LineEmission.swift`; `Tests/MetalUIPortableTextTests/LayoutCacheTests.swift`.
Disjoint from lane 1 (no shared file). Lane 2 is small; run it first, one agent.

## 4. Tests, each with its red-before and the mutation that reddens it

**Lane 1** (`SurfaceTextMeasureTests`, `harnessWindow`, Noto Sans, so literals
agree on every platform; every literal derived before the run from the font's
metrics read through the same system):

- **1.1 `aMeasuredTextIsTheFrameALaidOutTextGets`**: in a `Component` read
  `\.textMeasurer`, measure `Text("12.5 mm")` unbounded, store it; a sibling
  `Text("12.5 mm").id("t")` in the window; `frame(ofID:)` size equals the measure
  (the differential, probe A0). Red before: no `textMeasurer` (does not
  compile). 1.1 also runs under `.font(.system(size: 26))`.
  Mutation: `measure(in:)` skips `resolveTextStyle` (uses `.unstyled`), which
  reddens the 26 pt arm of 1.1 and 1.2 (the default-font arm alone would not).
- **1.2 `theMeasureReadsTheEnvironmentAtTheReadingPoint`**: a Component under
  `.font(.system(size: 26))` measures wider than one outside it (probe D); sizes
  equal their laid-out frames. Mutation: the measurer snapshots the root
  environment.
- **1.3 `aNarrowProposalWrapsAndAShortHeightCapsTheLines`**: width 60 → lines =
  ⌈…⌉ (literal from the text system's own `measure`), height < 1 line → one
  line (probes B, C). Mutation: `measure(in:)` passes `nil` height to
  `textLines`.
- **1.4 `measuringLaysNothingOutAndBuildsNothing`**: 50 measures in one
  Component body add 0 `layoutMeasureCalls` and 0 builds to the frame beyond the
  baseline tree's, and the counting text system sees exactly the distinct
  measures (hits otherwise). Mutation: `resolve` registers a native leaf.
- **1.5 `aRichTextMeasuresAsItLaysOut`**: a `Text` with a bold + larger run and a
  Markdown literal: measure == laid-out frame (RT-F). Mutation: rich takes the
  plain path.
- **1.6 `aProposalTextMeasuresAsItLaysOut`**: `ProposalText` overload.
- **1.7 `anEmptyStringMeasuresAsItLaysOut`**: width 0, height one line, equal to
  the frame (divergence 295 pin, `GT-I`). Mutation: a zero height forced.
- **1.8 `anEnvironmentResetKeepsTheMeasurer`**: `.environment(\.self,
  EnvironmentValues())` below a Component; it still measures. Mutation:
  `scopedValues` stops restoring the box.
- **1.9 `aMeasurerWithNoFrameTrapsNamingItself`**: exit test over
  `EnvironmentValues().textMeasurer.resolve(Text("x"))`, stderr contains
  `textMeasurer`. Mutation: return zero.
- **1.10 `theOverlayCostIsLinearAndCounted`** (the C23 baseline, for C14 to
  re-take): the measurement scenario at 20 and 100 labels, asserting per frame
  `builds == 1`, `layoutMeasureCalls == N + 1`, `layoutCacheHits == N + 1`,
  `layoutCacheMisses == N + 2`, seam `measure == 2N`, seam `placeGlyphs == N`,
  `atlasUploadPixels == 0`, `rasterizedPixels == 0`, `newTextures == 0` (the
  decisions table). **Expected to change when C14 lands; the change is the
  result.** Mutation: a label's text rebuilt twice per frame (a doubled
  `ForEach`) reddens it.
- **1.11 guard `theMeasurerHasNoPublicInitialiserAndNoSetter`**
  (`typecheckFile`, plain `import MetalUI`): `TextMeasurer()` and
  `env.textMeasurer = x` do not compile; a separating arm `env.textMeasurer.resolve(Text("x"))`
  does. Mutation: make the property settable → red once, restored.

**Lane 2** (`LayoutCacheTests`, `@testable import MetalUIPortableText`):
- **2.1 `aMovingTextShapesOnce`**: 100 `placeGlyphs` at 100 origins, one
  string/font/width → `layOutCount == 1` (red before: 100). Mutation: the key
  includes the origin.
- **2.2 `aCachedLayoutPlacesAsAFreshOneDoes`**: hit at a new origin and at
  scale 1 and 2 equals a fresh system's glyphs, subpixel variants included.
  Mutation: the cache stores placements, not lines.
- **2.3 `measureThenPlaceShapesOnce`** and `lineRangesThenPlace`: 1 shape.
  Mutation: `measure` bypasses the cache.
- **2.4 `theLayoutCacheForgetsAfterTwoFrames`**: unused for two frames → a third
  use shapes again. Mutation: `endFrame` stops filtering.
- **2.5 width and options are in the key**: a different width or `maxLines` is a
  second shape.

Whole-suite gates: `swift test --build-system native --no-parallel` summary line
(3446 + the new), 0 `warning:`, `FR-J no-argument frame: succeeded=`, 14 images
0 px (`compare.sh <scratch> d6a815c HEAD`), `DemoFrameDeterminismTests` unedited,
the Linux image root run (lane 2 and lane 1 portable tests), inventory scripts
print nothing. `Backends/SDL`: untouched, one build to confirm.

## 5. Demo and human checks

No demo change (the fourteen images must not move). Human check **GT1** (group
`GT`, to add at the Record phase; **not run — an agent cannot**), owned with
MetalCreator's S5c-6: in a 20-label sketch, labels sized by `measure` get chips
that hug their text (no 7-points-a-character slack), moving the camera shows no
label hitching on a Mac and on the SDL backend, and labels placed by a
`MetalView` viewport's pose stay on their anchors during a pan. The overlay
counts are the agent-side evidence.

## 6. Order, owners, risks

Lane 2 then lane 1 (or either; no shared file). The Record phase adds CLAUDE.md's
rule (two sentences: the measurer is `Layout`'s function in the environment; the
portable layout cache is origin-free), the divergence header, README row, group
`GT` in `human-checks.md`. Risk: `EnvironmentValues` gains a stored field —
`swift package clean` after the change (public type crossing a module
boundary). Deferred items and owners: GT-F (`drawText`; trigger and design in
the ruling; owner C14's close-out), GT-G (baselines, `GraphicsContext`; owner the
first request).
