# Text over a GPU surface — decisions

Rulings for item C23 of the gpui-gap priority list (user request 2026-10-02;
**not a plan task**), requested by MetalCreator (developer-0a, gap S5-c in its
`docs/metalui-gaps.md`; sketcher spec §8: 20+ world-anchored dimension labels
such as "12.5 mm" over a 3D `MetalView` viewport, moving with the camera; their
human check S5c-6). Prefix `GT-`. Spec:
[`specs/2026-10-12-surface-text-design.md`](specs/2026-10-12-surface-text-design.md).
Record: `../record/99-surface-text.md`. Branch `feat/surface-text` from
`d6a815c`. Divergence labels reserved for this branch: 295–304.

SwiftUI's side: `docs/probes/swiftui-surface-text.swift` (arms A0, B, C, D, E,
E2, F, G; run twice, byte-identical, output in its header). gpui's side, where
SwiftUI has nothing: `WindowTextSystem::layout_line`/`shape_line` (a `ShapedLine`
carries its `width`), which is how a gpui editor measures a string outside any
element.

**Next unused id: `GT-J`.**

## GT-A — Measure first; the overlay is linear, cache-served and rebuild-bound, so `drawText` is deferred

**Question.** S5-c asks for `MetalDrawContext.drawText(_:at:style:)` because
20–100 `Text` overlays "rebuild on every camera change". Is the overlay path
the cost, in a way a cache cannot remove?

**Evidence** (`SurfaceTextOverlayCostTests.measureTheOverlayCost`, headless,
`PortableTextSystem` over Noto Sans behind a call-counting `TextSystem`, 800 ×
600, `ZStack(alignment: .topLeading) { GPUSurface(value: phase) { _ in }; ForEach
labels: Text(…).offset(x:y:) }`; `phase` moves every frame so every label moves;
2 warm frames, then the mean of 5; counts, never time):

| labels | builds | leaf measure calls | layout hits / misses | seam `measure` | seam `placeGlyphs` | glyphs | atlas upload | rasterized px |
|---|---|---|---|---|---|---|---|---|
| 0   | 1 | 1   | 1 / 2     | 0   | 0   | 0   | 0 | 0 |
| 20  | 1 | 21  | 21 / 22   | 40  | 20  | 110 | 0 | 0 |
| 100 | 1 | 101 | 101 / 102 | 200 | 100 | 590 | 0 | 0 |
| 20, one shared string  | 1 | 21  | 21 / 22   | 40  | 20  | 120 | 0 | 0 |
| 100, one shared string | 1 | 101 | 101 / 102 | 200 | 100 | 600 | 0 | 0 |

Per label per frame: **1** leaf measure call, **2** text-system measures (the
layout leaf's, and `textLines` in paint), **1** `placeGlyphs`, about six
glyphs; no atlas upload, no raster, no new texture after the first frame.
Exactly linear (the 0 → 20 → 100 rows differ by 20 and 80 labels' worth), with
no per-label term that grows with N. Inside the text system:
- **CoreText** (the macOS path): `ShapingCache` is keyed `(string, FontKey,
  width, options)` and `placeGlyphs` goes through it, so a label that only
  moves is **0 shapes** (`CoreTextTextSystem.placeGlyphs`: `cache.shaped(…)
  .placedGlyphs(at:…)`). Both seam measures are hits.
- **Portable** (Linux, Windows, SDL): `measure` is cached for two frames but
  `placeGlyphs` calls `PortableText.placements`, which runs `layOut` — bidi,
  line breaking and HarfBuzz — **on every call**. A moving label is one full
  shape per frame (`MetalUIPortableText/PortableTextSystem.swift` `placeGlyphs`,
  `LineEmission.placements`). That is a cache a text system can have, and it
  removes the per-label text work entirely (GT-E).

**Ruling.** The text work is already served from a cache on macOS and, with
GT-E, on every platform. What the camera pays for is the rebuild itself: one
tree build, one layout run (≈ N leaf measures, all answered by the text caches)
and one paint of N small leaves, linear and with a constant per label. That is
what `MetalCreator` named PERF-b and what **C14 (incremental invalidation)** is
queued to attack; a `drawText` in the surface pass would still need the app to
compute N anchors per frame, and would not fix an animation's missing redraw
(their M4-b). So: (1) **`drawText` is deferred** with these numbers (GT-F);
(2) **a public string measure is built** (GT-B…GT-D) — wanted for collision
avoidance in any case; (3) **the portable layout cache is built** (GT-E), the
cheap win, with a shape-count pin.

**Cost if wrong.** If the 100-label overlay is still too slow after C14 and
GT-E, the app falls back to nothing it has today; the cost is the weeks until
`drawText` is built. GT-F records the trigger and the design so the decision
is a re-take, not a re-derivation.

## GT-B — The measure is SwiftUI's `resolve(_:)` + `ResolvedText.measure(in:)`, delivered by the environment

**Question.** What is SwiftUI's spelling for "how big is this string"?

**Evidence.** Probe A0: the only public one is `GraphicsContext.resolve(_:)`
→ `ResolvedText.measure(in: CGSize) -> CGSize`, inside a `Canvas`; for
`Text("12.5 mm").font(.system(size: 13))` it answers (51, 16), equal to the
view's ideal size (the positive control). `Text` has none; a custom `Layout`
measures its subviews, which MetalUI's `ProposalLayout` already does (it needs
the labels as subviews, so it cannot serve a model that computes anchors before
there is a tree). MetalUI has no `Canvas` or `GraphicsContext` type (`grep -rn
GraphicsContext Sources` reads nothing; the demo's "canvas" is a node-graph
screen, `CanvasDemo.swift`).

**Ruling.** Keep SwiftUI's two names and move the carrier from the graphics
context to the environment:

```swift
@Environment(\.textMeasurer) var measurer           // MetalUI-only carrier (divergence 296)
let resolved = measurer.resolve(Text("12.5 mm"))    // GraphicsContext.resolve(_:)
let size = resolved.measure(in: Size(width: .infinity, height: .infinity))   // ResolvedText.measure(in:)
```

`TextMeasurer` and `TextMeasurer.ResolvedText` are public structs;
`resolve` has a `Text` and a `ProposalText` overload (a rich or Markdown `Text`
measures as it lays out, RT-F). MetalUI-only because SwiftUI has no environment
value for it (class `M`).

**Cost if wrong.** A rename on an unreleased additive type; nothing else reads
it.

## GT-C — A measure is the layout answer, not a new algorithm

**Question.** What does `measure(in:)` return?

**Evidence.** Probe B: a width proposal wraps (60 → (60, 80)); probe C: a
short height proposal caps the lines to one ((51, 16) at height 5); probe D:
the resolve reads the environment's font ((97, 30) at `.system(size: 26)`);
probe F: an infinite proposal is the unbounded measure. These are the rules
`proposalTextMeasurement` already has (TE-H item 2, LR-AU). Probe E vs E2:
the empty string measures (0, 14) in a Canvas but (0, 0) as a view — the
Canvas measure is not always the layout answer.

**Ruling.** `measure(in:)` calls the one function layout calls
(`proposalTextMeasurement` / `richTextMeasurement`) with the proposal, through
`resolveTextStyle` (`TE-AA`) over the environment at the **reading** point and
`Frame.textSystem` (`TS-A`): **a measured size equals the frame a `Text` is
laid out at under the same proposal and environment**, by construction and by a
differential test. It lays nothing out, places no node, records no state,
shapes only through the text system's own caches, and an infinite or `nil` axis
is unbounded. **Empty string: (0, one line)** — `Text("")` lays out 0 wide and
one line tall (measured at implementation: frame (0, 18) in Noto Sans 13), so
the measure says the same; SwiftUI's *view* is (0, 0) (probe E2) and its Canvas
measure (0, 14) (probe E), which MetalUI's layout matches in kind: divergence
295, corrected by `GT-I`. Baselines (`firstBaseline(in:)`, probe G: 13 for a
13 pt text) are **not built** (GT-G).

**Cost if wrong.** A measure that disagreed with layout would place a chip a
pixel off its text: the differential test is the pin.

## GT-D — The environment value is stamped by the frame and survives a reset

**Question.** How does a `Component` reach the text system?

**Evidence.** `Frame` already stamps `theme` and `displayScale` on the root
environment and a scope's `\.self` reset re-stamps `theme` (EV-U); `Frame` owns
`textSystem`.

**Ruling.** `EnvironmentValues.textMeasurer` is a **get-only computed**
property: `TextMeasurer(system: <stamped box>, environment: self)`, so the
snapshot is the environment at the reading element (a `.font` above it counts;
the nearest writer wins by construction). The system box is an internal stored
field the root stamps in `rootEnvironment`'s setter and `scopedValues` puts
back after a transform, exactly as `theme` (a `.environment(\.self,
EnvironmentValues())` keeps it). `TextMeasurer` has no public initialiser. A
value read where no frame stamped one (a bare `EnvironmentValues()`) **traps
naming the measurer** on `resolve` (a measurer with no text system has no
honest answer; zero would hide a missing seam). `Window.environment` is not
involved (no dirtying write).

**Cost if wrong.** A reset that drops the box would trap in a subtree that
writes `\.self`; test 1.8 pins the reset.

## GT-E — The portable text system caches a layout, not a placement

**Question.** The cheap win: can a moving label cost no shaping on the portable
path?

**Evidence.** GT-A: `measure` caches only the two summary numbers and
`placeGlyphs` re-runs `layOut`.

**Ruling.** `PortableTextSystem` keeps one `[LaidOutLine]` per
`(string, FontKey, width, options)` — the existing `MeasureKey` — with the
existing two-frame generation lifetime (`beginFrame`/`endFrame`), filled by
`measure`, `placeGlyphs` and `lineRanges`, whichever runs first. The cached
value is the **origin-free** layout: `LineEmission.placements` takes the lines
and applies origin and scale (they are arithmetic over `penX`), so a hit at a
new origin or scale is identical to a fresh call. An internal
`layOutCount` is the instrument (work, not time). Pixels move by 0 (every
`LineEmissionOracleTests` arm, the fourteen images).

**Cost if wrong.** A key missing an input returns a stale layout: the key is
the existing measure key, which already decides every layout input; the pin
compares a hit with a fresh system's answer at two origins and two scales.

## GT-F — `MetalDrawContext.drawText` and its portable twin are deferred

**Question.** Why not build what was asked?

**Evidence.** GT-A. Building it means a glyph draw **inside the app's own
pass** into the surface target: a glyph pipeline bound to the surface's
render pass on `MetalWindowRenderer` and `SDLWindowRenderer` (the atlas is
uploaded before encode, MV-F, so the texture is there, but MetalUI's glyph
pipeline state is built for the window's pass format and its transform/
backdrop/segment machinery (§94)), the same primitive in `shaders.metal` and
`replay.hlsl` with replay parity (TE-AD), a defaultless `GPUSurfaceContext`
requirement or a per-backend method on `MetalDrawContext` and
`SDLGPUDrawContext`, and the text would be resampled with the surface rather
than snapped to the window's pixel grid (divergence 106's rule). It saves a
tree rebuild only when the app also stops rebuilding (C14), and it gives up
what the element path has: accessibility, selection, `.help`, theming through
`resolveTextStyle`, Reduce Motion.

**Ruling.** Deferred; owner C14's close-out. **Trigger to build:** after C14
and GT-E, a 100-label overlay's per-frame work (this record's table, re-taken
with the same test) still scales with N through anything but the labels'
own paint, and MetalCreator's S5c-6 reports a missing frame budget. The sketch
above is the design to start from (one defaulted-nothing requirement, replay
parity, `drawText(_ text: Text/ResolvedText, at: Point<Pixels>)` taking the
`GT-B` resolved value so one `resolveTextStyle` serves both).

**Cost if wrong.** MetalCreator keeps `handleLabels`-style overlays (they
work, S5c-6 looks at them) and gains the measure for the collision part.

## GT-G — Deferred with owners

- `ResolvedText.firstBaseline(in:)`/`lastBaseline(in:)` (probe G): no consumer in
  S5-c; owner: the first request that asks (alignment of a chip's text), one
  pass over `proposalTextMeasurement`'s existing baselines.
- `Canvas`-style `GraphicsContext` and `context.draw(Text, at:)`: not built;
  MetalUI's drawing surfaces are elements (`Path`, `GPUSurface`); revisit with
  GT-F.
- A measure of a `TextField`/`TextEditor` string: they stay plain (RT-M) and
  have `caretOffsets`; no request.
- `MetalCreator`'s `PlacedLabel.size(of:)` 7-points-a-character guess: replaced
  by the measure on their side after merge; MetalUI never edits their tree.


## GT-H — The portable layout cache covers plain text only; a moving styled label still shapes per frame there (critic pass)

**Question.** GT-E caches `[LaidOutLine]` for the plain `placeGlyphs`; does it
remove the portable per-frame shape for every label?

**Evidence.** `PortableTextSystem.layOut(_ text: StyledText, …)` calls
`PortableText.styledLayout` on every call (only its `measure` is cached,
`styledMeasurements`); a rich or Markdown `Text` (RT-) that only moves therefore
shapes once per frame on SDL/Linux/Windows. Dimension labels like "12.5 mm" are
plain strings (S5-c), and CoreText caches both paths. The one-run unstyled `Text`
takes the plain calls byte for byte (RT-M), so it is covered.

**Ruling.** Rejected for this branch: extending the cache to `styledLayout` needs
an origin-free styled layout and a split of `styledLayout`'s placement step, a
second oracle surface (`RichTextTests`) with no requester. Stated in the record
and the spec so GT-E is not read as covering rich text. Owner: the first request
for moving rich labels on SDL, after C14's re-take.

**Cost if wrong.** A moving Markdown label on SDL shapes once per frame, as
today; no regression.

## GT-I — The measure is the leaf's unrounded answer; a laid-out frame is that answer rounded; an empty `Text` is one line tall (implementation, lane 1)

**Question.** GT-C says a measured size "equals the frame a `Text` is laid
out at". Does it, to the bit?

**Evidence** (`SurfaceTextMeasureTests` 1.1, run red on the first build): a
`Text("12.5 mm")` measures (53.482, 18) and its frame reads (54, 18).
`LayoutTree.roundNativeStoredRects` applies `roundLayout` (cumulative edges,
`Rounding.swift`) to every stored rect after positioning, so a frame is the
leaf's answer rounded to whole points by its edges (difference < 1 point); the
kernel records the unrounded width for paint (`measuredWidth(of:)`). And
`Text("")` lays out (0, 18), not (0, 0): `proposalTextMeasurement` pads
nothing and the empty string's `totalHeight` is one line (existing behaviour,
undocumented until now; SwiftUI's view answers (0, 0), probe E2).

**Ruling.** (1) `measure(in:)` returns the **unrounded** leaf answer — the
number layout's measure function returns, which paint wraps at — and the
differential tests compare a laid-out frame **within one point** (and a frame's
height exactly when width is fixed). An app placing a chip rounds up itself
(`.rounded(.up)`); rounding to the device grid is the kernel's, not the
measurer's. (2) The empty string measures as it lays out: width 0, height one
line. Divergence 295 is therefore "an empty `Text` is one line tall where
SwiftUI's view is zero tall", pinned by test 1.7; it is a fact about layout
that the measurer inherits, not new behaviour. The spec's 1.7 name
`anEmptyStringMeasuresZeroByZero` becomes `anEmptyStringMeasuresAsItLaysOut`.

**Cost if wrong.** A caller wanting SwiftUI's empty-is-zero writes
`string.isEmpty ? .zero : …` themselves; changing layout's empty answer is a
separate, visible change to every empty `Text` (not this branch's).
