# Controls and looks — design

User request 2026-10-02 (item C10 of the gpui-gap priority list; **not a plan
task**). Rulings: [`../2026-10-08-controls-looks-decisions.md`](../2026-10-08-controls-looks-decisions.md)
(`LK-A`…`LK-T`; `LK-O`…`LK-T` are the critic's amendments, and win where they differ from an earlier ruling). Record: `../../record/85-controls-looks.md`. Branch
`feat/controls-looks` from `cd84b0c`.

**Motivation.** MetalCreator ships stopgaps for six missing pieces —
`EditorModel.setInput(_:to:continuous:)`'s coalescing key (M5-a, no slider
editing-ended callback), `GlassPanel` (M5-c, no material or blur), a solid
window background (M5-d, no gradient), a spring-back offset (M5-i, no keyframe
shake), `StatusBadge.text(for:)`'s static `◌` (M5-j, no spinner) and a hex
field per theme role (M6-f, no colour picker). The SMK configurator's port
keeps a swatch plus hex field (MG-7) and translucent palette colours for its
rail's glass tiles (MG-9). The decisions doc's first table gives the spelling
each stopgap swaps to.

**SwiftUI's answers** are in `docs/probes/swiftui-controls-looks.swift`'s
header (160 recorded lines); arms are cited by name below (`S1`, `V8`, `K3g`,
`G11`, `B2`, `M5`, …).

---

## §0 Baseline

Per the brief, at `cd84b0c`: **2723 tests in 3 suites**, `FR-J no-argument
frame: succeeded=` present, 0 `error:`, the only `warning:` SwiftPM's
deprecation notice; `swift build --build-tests` 0 warnings. `docs/divergences.md`
next label 139 in the header; **this branch's labels are 165–174** (`LK-N`).
**Lane 1 re-takes the baseline before its first change** (native build,
unfiltered `--no-parallel`, the one summary line, the `FR-J` grep) and records
it in record §85 §0, with `Backends/SDL` (macOS and the Linux image) since lane
1 touches `AccessKitTree.swift`.

## §1 Public API (final spellings)

Every new public declaration owes a doc comment and an inventory map row
(`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; the
census re-recorded with `closeout-public-api.sh`). Classes: **A** unless noted.

**Lane 1**

```swift
// Slider (LK-B) — the two existing inits gain the defaulted parameter
init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1,
                             onEditingChanged: @escaping (Bool) -> Void = { _ in })
init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride,
                             onEditingChanged: @escaping (Bool) -> Void = { _ in })

// ColorPicker (LK-C, LK-D, LK-P) — D (divergence 165: drawn panel on macOS); Toggle's shape: one Box, label + well
public struct ColorPicker<Label: ElementGroup>: Element, StyledElement {
  init(selection: Binding<Color>, supportsOpacity: Bool = true, @ElementBuilder label: () -> Label) }
extension ColorPicker where Label == Text { init(_ titleKey: String, selection: Binding<Color>, supportsOpacity: Bool = true) }

// AccessibilityRole (LK-G) — M (MetalUI's own neutral tree)
case progressIndicator, busyIndicator, colorWell
```

**Lane 2**

```swift
// ProgressView (LK-E, LK-F, LK-P) — Toggle's shape: one Box over the label(s) and an internal indicator leaf
public struct ProgressView<Label: ElementGroup, CurrentValueLabel: ElementGroup>: Element, StyledElement
  init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0, @ElementBuilder label: () -> Label,
                               @ElementBuilder currentValueLabel: () -> CurrentValueLabel)
extension ProgressView where Label == EmptyGroup, CurrentValueLabel == EmptyGroup {
  init();  init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) }
extension ProgressView where Label == Text, CurrentValueLabel == EmptyGroup {
  init(_ title: String);  init<V: BinaryFloatingPoint>(_ title: String, value: V?, total: V = 1.0) }
public struct ProgressViewStyle: Hashable, Sendable { static let automatic, linear, circular }
func progressViewStyle(_ style: ProgressViewStyle)   // on ProgressView and on ElementGroup (MD-B pattern)

// Keyframes (LK-H, LK-I)
public protocol VectorArithmetic: AdditiveArithmetic { mutating func scale(by: Double); var magnitudeSquared: Double { get } }
// Double, Float, CGFloat (where Foundation has it), Angle conform
public struct UnitCurve: Hashable, Sendable { static let linear, easeIn, easeOut, easeInOut
                                              static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve }
public struct Spring: Hashable, Sendable { init(duration: Double = 0.5, bounce: Double = 0) }
public protocol KeyframeTrackContent<Value>       public protocol Keyframes<Value>
public struct LinearKeyframe<Value: VectorArithmetic>: KeyframeTrackContent { init(_ to: Value, duration: TimeInterval, timingCurve: UnitCurve = .linear) }
public struct CubicKeyframe<Value>   { init(_ to: Value, duration: TimeInterval, startVelocity: Value? = nil, endVelocity: Value? = nil) }
public struct SpringKeyframe<Value>  { init(_ to: Value, duration: TimeInterval, spring: Spring = Spring(), startVelocity: Value? = nil) }  // D: duration required (div. 168)
public struct MoveKeyframe<Value>    { init(_ to: Value) }
public struct KeyframeTrack<Root, Value: VectorArithmetic, Content>: Keyframes { init(_ keyPath: WritableKeyPath<Root, Value> = \.self, @KeyframeTrackContentBuilder<Value> content: () -> Content) }
@resultBuilder public enum KeyframesBuilder<Value>          @resultBuilder public enum KeyframeTrackContentBuilder<Value>
public struct KeyframeTimeline<Value> { init(initialValue: Value, @KeyframesBuilder<Value> content: () -> some Keyframes<Value>)
                                        var duration: TimeInterval; func value(time: TimeInterval) -> Value; func value(progress: Double) -> Value }
extension ElementGroup {   // proposal content stays proposal (a ProposalElementGroup overload)
  func keyframeAnimator<Value, Content: ElementGroup, K: Keyframes<Value>>(initialValue: Value, trigger: some Equatable,
       @ElementBuilder content: @escaping (Self, Value) -> Content, @KeyframesBuilder<Value> keyframes: @escaping (Value) -> K) -> some ElementGroup
  func keyframeAnimator<…>(initialValue: Value, repeating: Bool = true, content:…, keyframes:…) -> some ElementGroup
}
public struct KeyframeAnimator<Value, Content: ElementGroup, K>: ElementGroup {   // LK-T item 4
  init(initialValue:trigger:content: @escaping (Value) -> Content, keyframes:)
  init(initialValue:repeating: Bool = true, content: @escaping (Value) -> Content, keyframes:) }
// D (divergence 169): Value constraint VectorArithmetic, content receives Self
```

**Lane 3**

```swift
public struct Gradient: Hashable, Sendable { struct Stop { var color: Color; var location: Double }
                                             init(colors: [Color]); init(stops: [Stop]) }
public struct LinearGradient  { init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint)
                                init(colors: [Color], startPoint:endPoint:); init(stops: [Gradient.Stop], startPoint:endPoint:) }
public struct RadialGradient  { init(gradient: Gradient, center: UnitPoint, startRadius: Pixels, endRadius: Pixels)  + colors:/stops: }
// both: greedy leaves (ideal 10×10) in both vocabularies
// LK-R: where each overload lives and what it returns
extension Shape { func fill(_: LinearGradient) / fill(_: RadialGradient) / fill(_: Material)
                  func fill(_:style: FillStyle) for each of the three (beside fill(_ color:, style:))
                  func stroke(_: LinearGradient, lineWidth: Pixels = 1) / stroke(_:style:) (and RadialGradient) }
// ShapeView's own chained fill(_:) / fill(_:style:) gain the same three
extension ElementGroup { func background<S: Shape>(_: LinearGradient | RadialGradient | Material, in: S)
                             -> BackgroundModifier<Self, ShapeView<S>> }        // beside the Color pair, both vocabularies
extension ProposalElementGroup { func background(_: LinearGradient) -> BackgroundModifier<Self, LinearGradient>   // the view as attachment
                                 func background(_: RadialGradient) -> BackgroundModifier<Self, RadialGradient>
                                 func background(_: Material) -> ModifiedContent<ProposalBase, LayoutModifier>    // existing .background(Color) case
                                 func blur(radius: Pixels) -> ModifiedContent<ProposalBase, LayoutModifier> }
extension StyledElement { func background(_: LinearGradient) -> Self / (_: RadialGradient) / (_: Material); func blur(radius: Pixels) -> Self }
public struct Material: Hashable, Sendable { static let ultraThinMaterial, thinMaterial, regularMaterial, thickMaterial, ultraThickMaterial, bar }
// static members also on the overload sites' parameter types so `.background(.ultraThinMaterial)` resolves (typecheck guard 3.T1)
case blur(radius: Pixels)    // the ONE new LayoutModifier case — M; migration note (LK-R item 3)
```

## §2 Files and lanes

At most three lanes, sequential, disjoint (`LK-A`, `LK-N`).

| Lane | Owns (new **bold**) |
|---|---|
| 1 controls | `Slider.swift`, `Window.swift` (after `updatePointerState(event)` in the input hook, `dispatchValueTrack`, the close path — `LK-Q`), **`ColorPicker.swift`**, **`ColorPickerPanel.swift`**, **`ColorMath.swift`** (HSB, hex), `AccessibilityTree.swift` (3 roles), `AppKitAccessibility.swift`, `Backends/SDL/Sources/MetalUISDL/AccessKitTree.swift`, `ControlsDemo.swift` (`controlsLooksSection()`); tests **`SliderEditingTests.swift`**, **`ColorPickerTests.swift`**, **`ColorPickerPanelTests.swift`**, **`ColorMathTests.swift`**, **`ColorPickerCompileGuards.swift`** (no `PlatformWindow` conformer, `LK-T`), **`ControlsLooksAccessibilityTests.swift`**, and an arm in `Backends/SDL/Tests/MetalUISDLTests` (the AccessKit role file it already has) |
| 2 progress, keyframes | **`ProgressView.swift`**, **`ProgressViewStyle.swift`**, **`Keyframes.swift`** (types, builders, timeline), **`KeyframeAnimator.swift`** (scope, modifier, view), **`VectorArithmetic.swift`**, `AnimationStore.swift` (the keyframe records), `Animation.swift` (`springValue` and the curve solver made internal — no behaviour change), `ControlsDemo.swift` (`progressSection()`), `LooksDemo.swift` (`keyframesSection()`); tests **`ProgressViewTests.swift`**, **`ProgressViewCompileGuards.swift`**, **`KeyframeTimelineTests.swift`**, **`KeyframeAnimatorTests.swift`**, **`KeyframeCompileGuards.swift`** |
| 3 looks | **`Gradient.swift`** (types, Oklab table), **`GradientRaster.swift`**, **`Blur.swift`**, **`Material.swift`**, `RasterCache.swift`, `Shadow.swift` (the shared per-leaf capture, refactored not changed), `Frame.swift` (a `CapturedPrimitive` kind and the blur scope), `RenderEffects.swift`, `ShapeView.swift`, `Box.swift` (`Decoration`'s fill), `NativeModifiedContent.swift` (`LayoutModifier.blur`), `NativeBackgroundModifier.swift`, `ClipShape.swift` (`background(_:in:)`), `LooksDemo.swift` (`gradientsBlurMaterialsSection()`); tests **`GradientTests.swift`**, **`GradientRasterTests.swift`**, **`BlurTests.swift`**, **`MaterialTests.swift`**, **`LooksCompileGuards.swift`**, plus replay frame 9 (`LK-S`): `Experiments/SDLGPU/Sources/Replay/main.swift` (the recorder) and `.github/workflows/sdl-gpu-linux.yml` (`--expect 8` → `9`, both jobs) |

Lanes 1 and 2 both append a function to `ControlsDemo.swift`, lanes 2 and 3
to `LooksDemo.swift` — appended at the end, never editing another lane's
function (`LK-T` item 3); lanes are sequential. New
public cases on public types (`AccessibilityRole`, `LayoutModifier`) and the
new stored property on `Decoration`: **`swift package clean` before the next
measured run** in that lane.

## §3 Implementation by lane

### §3.1 Lane 1

**Slider** (`LK-B`, `LK-Q`). `ValueTrackTarget` gains `onEditingChanged: (@MainActor
(Bool) -> Void)?`. `dispatchValueTrack(_:)` (signature unchanged): on `.mouseDown` over
a track, end any still-open `editingTrack` first, then call `onEditingChanged(true)`,
then `track(toWindowX:)`, and store `(id, end: onEditingChanged)` in a new
`private var editingTrack`; `.mouseDragged` unchanged. **The release end runs
right after `self.updatePointerState(event)` at the top of the `onInput` hook**
— before the services switch, the drawn alert, the drag and menu sessions and
the popovers' stage, any of which may claim the release — calling `end(false)`
under `StateDispatch` to the stored id and clearing it, **whether or not** a
region with that id is still in `lastHitboxes`, and **claiming nothing** (the
release continues exactly as at `cd84b0c`). The window's close path
(`runDisappearancesForClose`'s caller) ends an open `editingTrack` the same way. The keyboard and accessibility adjust closures in
`Slider.prepaint` wrap their write in `true`/`false`.

**ColorPicker** (`LK-C`, `LK-P`). An `Element, StyledElement` on `Toggle`'s
shape (`@State var isPresented`): **one `Box`** (row, gap 8, cross-centred) over
the label and the well — so it is one node in any container — the well a `StyledElement` leaf (48×24, `registerAndScope` in `prepaint`,
`paintDecoration` in `paint`, `.colorWell` AX node with the `"rgb …"` value,
press and Space/Return → `isPresented = true`) carrying `.popover(isPresented:)`
over `ColorPickerPanel`. Empty title: the well alone.

**ColorPickerPanel** (`LK-D`). An internal `Component` with `@State` HSBA and
`lastWritten: Color?`, whose body is **one** column (a popover's content is
one presentation root, `LK-P` item 3). The square, hue bar and opacity bar are `Image`s of
`ImageBitmap`s generated by `ColorMath` (square 100×75 device-independent
samples scaled with the linear filter; the hue strip 360×1; the opacity strip
64×1 over a checkerboard), each under a `DragGesture(minimumDistance: 0)`
writing on change, with its marker drawn over it, focusable with the `LK-D`
keys through `onKey`. The hex field is a `TextField` over a local
`@State var hex: String`, parsed on submit by `ColorMath.parseHex(_:allowsAlpha:)`.

**ColorMath** (internal, pure): `hsb(from rgb:)`, `rgb(from hsb:)`,
`hexString(_:includesAlpha:)`, `parseHex(_:allowsAlpha:) -> (r,g,b,a)?`,
`axComponents(_:) -> String` (`"rgb 1 0 0 1"`).

**Roles** (`LK-G`): `AccessibilityRole` three cases; `AppKitAccessibility.swift`
role rows (`.progressIndicator`, `.busyIndicator`, `.colorWell`; value for the
first as `NSNumber`); `AccessKitTree.swift` rows (`PROGRESS_INDICATOR` with
`numericValue`/min 0/max 1 for the first, none for the second; `COLOR_WELL`
with the value string). Convert every C enum `rawValue` explicitly.

### §3.2 Lane 2

**ProgressView** (`LK-E`, `LK-F`, `LK-P`): an internal leaf `StyledElement`
(`lowerLegacyLeaf`, `requestNativeLeaf` with `LK-E` item 3's sizes) for the
spinner, the bar and the ring, inside the public `ProgressView`'s **one `Box`**
(column) with its title and current-value label (above/below per `LK-E` item
3) — `Toggle`'s shape, never a `Component`. Paint: spinner = 12
spokes (2-point-wide capsules from 0.5r to r, opacity 1 → 0.25 around, rotated
by the step `floor((t mod 0.8)/0.8·24)·15°`), drawn as `Path`s through
`pass.drawPath` (a CPU raster of at most 32×32 points per step change — the
window's `RasterCache` keeps only what a frame touched);
bar = two rounded rects; ring = a `Path` arc stroke. `t` is the frame
timestamp the animation store uses; `noteActiveAnimation()` from `paint` only
when indeterminate and visible (`PaintPass`' visibility: nonzero size, not
hidden, opacity > 0, inside the clip). AX per `LK-E` item 5.

**Keyframes** (`LK-I`): `KeyframeTimeline` compiles each track into an array
of segments `(start, end, kind, from, to, v0, v1)` once at init (tangents per
item 4, spring velocity carried per item 5); `value(time:)` binary-searches.
`Keyframes`/`KeyframeTrackContent` are protocols with internal requirements
(`_segments(from:)`), so user conformances cannot be written (`MC-G`'s
precedent; a plain-import guard pins it). **The animator scope** is transparent
(no node, no id level; `LifecycleScope`'s shape): during the build it reads its
record from `AnimationStore` under `$keyframes<depth>`, compares the trigger
(`AnyEquatableBox`), starts/restarts per item 10, evaluates the timeline at the
frame time and passes the value to `content(self, value)`; while running
`noteActiveAnimation()`. Records untouched for a frame are dropped at its end
(the store's sweep).

### §3.3 Lane 3

**Gradient raster** (`LK-J`). `Gradient.table(scheme/theme-resolved colours)
-> [UInt32]` (1024 premultiplied RGBA8 entries in premultiplied Oklab, the
probe's arithmetic). A new `CapturedPrimitive.gradient(GradientPaint)` holding
the shape geometry (`PathGeometry`, or a rect + radii for the fast path), mode
(fill/stroke), the resolved stops, the gradient's points in local device
pixels, `local` and the masks — the `PathPaint` shape. `Frame.gradientImage`
mirrors `pathImage`: strip fast path when `LK-J` item 5 holds (a `W×1` or
`1×H` texture, image bounds = the rect, mask = the rect's radii), else coverage
(`PathRaster.fill`/`stroke`) × per-pixel colour (t by inverse-mapping the
device pixel centre into local space; linear projection or radial distance;
table lookup). `RasterCache` gains a gradient texture entry keyed by coverage
key + table words. Shadows see a gradient leaf's alpha (its silhouette is
coverage × the table's alpha at each pixel — implemented by rasterizing it,
the image-leaf path).

**Blur** (`LK-K`). A `Frame.paintScopes` entry `.blur(radius)`: primitives
emitted inside are captured per leaf (the shadow scope's capture), and at the
scope's exit each leaf becomes one image: `colourRaster(leaf)` (the shadow's
`silhouette` switch, producing four premultiplied channels — rect fill and
border colours, glyph colour × atlas coverage, image texels resampled, path
colour × coverage, gradient texels, nested shadow tinted) → `BoxBlur.blur` per
channel → recombined `ImageTexture`, keyed as the shadow is plus a kind word.
A `.surface` leaf passes through unchanged (divergence 167). Proposal: a
`LayoutModifier.blur` layer whose paint wraps `PaintPass.withBlur`; legacy:
`appendingRenderEffect(.blur)`; the radius animates through the store as the
shadow's does.

**Material** (`LK-L`). `Material.fill(for scheme:) -> Color` (the table, a
literal gamma grey at an alpha); every material site lowers to the colour
site's code path with that colour (a proposal `.background(material)` is a
`.background(color)` layer resolved at paint by scheme, a legacy one sets
`Decoration.background` to a `Color(light:dark:)` pair). No new primitive.

**Replay parity** (`LK-S`): the gradient and blur images are `MUIImage`s made
on the CPU, so both renderers receive the same texels and `TE-AD` holds by
construction. The recorder gains **frame 9** through `renderFrame` (vertical and
horizontal strip-path rounded rects at quarter-pixel bounds, a diagonal full
raster, a radial circle, a blurred text leaf); CI's `--expect 8` becomes `9`.
It is replayed locally on macOS (`PortableReplay --driver metal`) and in CI on
llvmpipe and D3D12 — the offscreen Linux image does not replay.

## §4 Tests (by name; red-before; the mutation that must redden it)

"Red before" = what the test reads on `cd84b0c` (most do not compile there:
"absent API"). Each lane mutates every test it adds (or the declaration it is
named for) in an isolated copy, runs the whole suite unfiltered, restores, and
names every reddened test (practices). Guards (typecheck) are mutated red once
each. Numbers come from the probe unless marked *(MetalUI rule)*.

### §4.1 Lane 1

| Test | Red before | Mutation that must redden it |
|---|---|---|
| `aSliderPressCallsEditingTrueBeforeItsFirstWrite` | absent API | call `onEditingChanged(true)` after `track(toWindowX:)` |
| `aSliderReleaseCallsEditingFalseAfterTheLastWrite` (S1 order, 2 drags) | absent | drop the `.mouseUp` case |
| `aPressWithNoDragIsTrueWriteFalse` (S2) | absent | skip the write on a press |
| `aDisabledSliderPressCallsNothing` (S7) | absent | register `valueTrack` outside the disabled gate |
| `anOutsideBindingWriteCallsNothing` (S5) | absent | call `onEditingChanged` from `paint` on a value change |
| `anAccessibilityIncrementIsAWholeEdit` (S4) | absent | drop the pair around the adjust closure's write |
| `anArrowKeyIsAWholeEdit` *(MetalUI rule)* | absent | same, keyboard branch |
| `aReleaseAfterTheSliderLeftTheTreeStillEndsTheEdit` *(rule)* | absent | look the callback up in `lastHitboxes` at release |
| `aReleaseAfterTheSliderWasDisabledStillEndsTheEdit` *(rule)* | absent | same |
| `closingTheWindowMidDragEndsTheEdit` *(rule)* | absent | drop the close-path call |
| `aReleaseClaimedByTheDrawnAlertStillEndsTheEdit` (`LK-Q`) | absent | end the edit in `dispatchValueTrack`'s `.mouseUp` case (the first design's spelling) |
| `aSecondPressWithoutAReleaseEndsTheFirstEdit` (`LK-Q`) | absent | overwrite `editingTrack` without ending it |
| `theReleaseIsNotClaimedByTheSlider` (`LK-Q`: an ancestor's tap arena sees the release as at `cd84b0c`) | absent | return `true` from the end |
| `theEditingCallbacksRunUnderTheSlidersDispatch` (`ID-F`: one slider value placed twice) | absent | run the calls outside `StateDispatch` |
| `theSliderInitialisersKeepTheirSwiftUISpellings` (guard: `Slider(value:in:onEditingChanged:)`, `step:`, trailing closure; plain import) | absent | rename the parameter |
| `aColorPickerIsItsLabelEightPointsAndAFortyEightByTwentyFourWell` (C0, V12: own width = MetalUI's `Text("Tint")` width + 56, height 24) | absent | spacing 6 |
| `aColorPickerWithAnEmptyTitleIsTheWellAlone` (48×24) | absent | keep the spacing with no label |
| `aColorPickerInAVStackKeepsItsLabelBesideTheWell` / `aColorPickerInAnHStackKeepsItsOwnEightPointGap` (`LK-P`) | absent | make the body a `Component` of two top-level nodes |
| `aColorPickerTakesABackgroundAndPadding` (guard, plain import; also `ColorPicker(selection:label:)`) | absent | drop the `StyledElement` conformance |
| `pressingTheWellOpensThePanelAndDoesNotFocus` | absent | focus on press |
| `spaceOnAFocusedWellOpensThePanel` | absent | drop the key |
| `aDragOnTheSquareWritesSaturationAndBrightness` (exact `Color(.sRGB …)` for a hue-0 square at (¼, ¼)) | absent | swap the axes |
| `aDragOnTheHueBarWritesTheHueKeepingSaturationAndBrightness` | absent | reset S/B on a hue drag |
| `theOpacityBarIsAbsentWithoutSupportsOpacity` and `everyWriteHasOpacityOneWithoutSupportsOpacity` (C8) | absent | pass the panel's alpha through |
| `theHueSurvivesSaturationZeroWhileDragging` | absent | re-seed from the binding every frame |
| `anOutsideWriteWhileOpenReSeedsThePanel` | absent | never re-seed |
| `aTokenSelectionOpensAtItsResolvedValueAndTheFirstEditWritesALiteral` | absent | seed from the token's light value regardless of scheme |
| `theHexFieldAcceptsTheFourForms` / `anInvalidHexRevertsAndWritesNothing` / `alphaHexIsRefusedWithoutSupportsOpacity` | absent | accept 5-digit strings; write on invalid |
| `theHexFieldShowsUppercaseWithAlphaOnlyBelowOne` | absent | always 8 digits |
| `squareAndBarKeysStepByOneHundredthAndShiftByATenth` | absent | step 0.1 unshifted |
| `escapeClosesThePanel` | absent | swallow Escape in the panel |
| `hsbRoundTripsEveryByteTriple` (`ColorMathTests`, a 17³ grid) | absent | truncate instead of round in `rgb(from:)` |
| `theWellPublishesAColorWellWithAppKitsValueFormat` (C1: `rgb 1 0 0 1`, `rgb 0.2 0.4 0.6 0.5`) | absent | print `%.3f` |
| `thePanelsSlidersPublishTheirValues` | absent | omit the hue node's value |
| `theThreeNewRolesHaveRowsOnTheAppKitBridge` (`AppKitAccessibilityTests`-style, macOS) | absent | map `.colorWell` to `.group` |
| `theThreeNewRolesHaveRowsOnAccessKit` (`Backends/SDL`, macOS and the Linux image) | absent | map `.busyIndicator` with a numeric value |
| `theControlsLooksSectionBuildsOnAOneMegabyteThread` — covered by the existing `everyProductionTreeBuildsOnAOneMegabyteThread` once the section is in `controlsDemoContent()`; lane 1 confirms it reddens when the section is inlined into a 600 KiB frame (mutation: inline it) | — | inline the section |

### §4.2 Lane 2

| Test | Red before | Mutation |
|---|---|---|
| `theSpinnerIsThirtyTwoSixteenAndTenByControlSize` (V0) | absent | `.mini` = 12 |
| `theBarIsGreedyTwentyTallAndZeroWideAtNil` (V3, V6; infinity at infinity) | absent | ideal width 30 |
| `aSmallBarIsTwelveTall` (V3) | absent | 20 |
| `aTitledBarStacksTheTitleAboveWithNoGap` (V4: 16 + 20 in MetalUI's own text height) | absent | gap 4 |
| `aCurrentValueLabelSitsBelowInTheCaptionFont` (V4) | absent | body font |
| `aTitledSpinnerStacksTheTitleBelowFourPointsApart` (V1, own 48×52) | absent | above |
| `aTitledProgressViewInAnHStackStacksItsTitleAbove` (`LK-P`) | absent | make it a `Component` of two top-level nodes |
| `aNegativeValueOrAZeroTotalIsIndeterminate` (V8) | absent | clamp to 0 instead |
| `aValueAboveTheTotalDrawsFull` (V8) | absent | no clamp (fill overflows the track: a pixel test) |
| `aNonFiniteValueIsIndeterminateAndNothingNonFiniteIsStored` *(rule)* | absent | pass NaN through |
| `progressViewStyleCircularDrawsARingAndLinearAnIndeterminateBar`, `theInnermostProgressViewStyleWins` | absent | outermost wins |
| `theSpinnerAdvancesTwentyFourStepsPerPointEightSeconds` (V13; `simulateTick` at 0, 0.0333, 0.8) | absent | 12 steps |
| `anIndeterminateViewKeepsTheWindowAnimatingAndADeterminateOneDoesNot` (`hasActiveAnimations`) | absent | always note |
| `aHiddenOrZeroSizeSpinnerRequestsNoFrames` | absent | note before the visibility check |
| `reduceMotionDoesNotStopTheSpinner` (V10) | absent | gate the step on `accessibilityReduceMotion` |
| `aDeterminateViewPublishesAProgressIndicatorWithTheFraction` (V7, V8: 5/10 → 0.5, title as label) | absent | publish the raw value |
| `anIndeterminateViewPublishesABusyIndicatorWithNoValue` | absent | value "0" |
| `linearKeyframesMatchK1` / `easeInOutMatchesK2` (every K1/K2 sample within 0.001) | absent | apply the curve to the whole track |
| `aLoneCubicIsSmoothstepK3b` / `cubicTangentsAreCatmullRomBetweenCubicsK3K3fK3g` / `aCubicTakesALinearNeighboursVelocityK3dK3h` / `anExplicitStartVelocityWinsK3e` | absent | tangent = (next − prev)/2 per segment (fails K3g only — the separating arm) |
| `aSpringKeyframeHoldsWhereItsDurationEndsK4` / `aSpringCarriesTheIncomingVelocityK4e` / `theNextKeyframeStartsFromTheSpringsValueK4c` / `springValuesMatchK4dAtPointOne` | absent | run the spring to its target at the end |
| `aMoveKeyframeJumpsK5` | absent | interpolate it |
| `tracksRunInParallelAndHoldK6` / `anUntrackedFieldKeepsItsInitialValueK7` | absent | sum durations |
| `aZeroDurationKeyframeReadsItsTarget` (K8; divergence 171) | absent | divide by the duration |
| `valueProgressClampsK9` | absent | no clamp |
| `theAnimatorShowsTheInitialValueAndCallsNoKeyframesOnAppearK10` | absent | start on appear |
| `aTriggerFromRestRestartsFromTheInitialValueK11K12` | absent | start from the held end value |
| `aTriggerMidRunStartsFromTheCurrentValueK13` | absent | restart from initial |
| `theAnimatorHoldsItsEndValueAtRest` | absent | reset to initial at the end |
| `repeatingLoopsAndCallsKeyframesOnceK14` | absent | call per cycle |
| `theAnimatorNotesAnimationOnlyWhileRunning` | absent | always note |
| `theKeyframeScopeTakesNoIdentityLevel` (a `@State` under it survives adding the scope; `theSevenRetentionSlotsAreMutuallyDistinct` unchanged) | absent | wrap content in an `IdentifiedGroup` |
| `keyframeAnimatorTypechecksWithSwiftUIsCallShape` (guard: the shake snippet from the decisions doc, plain import; negative arm `LK-T` item 2: a legacy decoration after it does not compile) | absent | rename `trigger:`; return `Self` |
| `userConformancesToKeyframesDoNotCompile` (guard, plain import, `typecheckFile`) | absent | make `_segments` public |
| `springKeyframeWithoutDurationDoesNotCompile` (guard; divergence 168) | absent | default `duration` to nil |

### §4.3 Lane 3

| Test | Red before | Mutation |
|---|---|---|
| `theOklabTableMatchesG11G2G5` (red→blue midpoint (140,83,162); black→white x50 99; clear-red→blue (127,128,255) over white; each ±1) | absent | interpolate in gamma sRGB |
| `aVerticalGradientSamplesAtPixelCentresG1` (y0, y50, y100 of a 10×101) | absent | t = y/H |
| `aDiagonalGradientsIsolinesArePerpendicularInPointsG3` (separating arm: unit-space reads 0.25 at both points) | absent | project in unit space |
| `stopsAreSortedPaddedAndHardAtEqualLocationsG4G4bG4cG7` | absent | no sort |
| `aDegenerateGradientDrawsTheLastColourG6` | absent | first colour |
| `aRadialGradientIsCircularInPointsR1R2` | absent | elliptical (scale by the rect) |
| `aGradientFilledCircleIsCutByTheCircleG8` | absent | fill the bounding rect |
| `aLinearGradientViewIsGreedyWithAnIdealOfTenG10` | absent | ideal 0 |
| `legacyAndProposalBackgroundGradientsFillTheFrameG9` | absent | draw under the padding box |
| `anAxisAlignedRectGradientDrawsAOnePixelStrip` (`lastRasterizedPixels` = H, texture width 1) | absent | always full raster |
| `aDiagonalOrClippedGradientRastersInFull` (work counter = clipped area) | absent | strip for diagonals |
| `anUnchangedGradientKeepsItsTextureIdentity` / `aChangedStopMakesANewTexture` (cache key) | absent | drop the stops from the key |
| `aGradientUnderARotationFollowsTheTransform` | absent | ignore `local` |
| `aGradientChangeSnaps` *(rule)* | absent | route through `animatedBackground` |
| `aShadowSeesAGradientLeafsAlpha` | absent | silhouette from the bounding rect |
| `blurIsPerLeafB2` (blue over red, blurred: red channel at the edge > green channel by the probe's ratio) | absent | composite the leaves first |
| `blurSigmaIsTheRadiusB1` (four profile points within divergence 105's tolerance) | absent | sigma = radius / 2 |
| `aBlurChangesNoLayoutHitOrAccessibilityB4` | absent | add the reach to the layout size |
| `aClipOutsideTheBlurCutsItB5` | absent | clip inside |
| `aTextRunBlursAsOneLeaf` | absent | blur glyph by glyph (the overlap differs) |
| `aSurfaceLeafUnderBlurIsDrawnUnblurred` (divergence 167) | absent | drop the surface |
| `theBlurRadiusAnimates` (`simulateTick` midpoint) | absent | snap |
| `aBlurOfRadiusZeroDrawsTheLeafUnchanged` / `aNonFiniteBlurRadiusTraps` (exit test) | absent | blur anyway / clamp |
| `theLegacyBlurJoinsRenderEffectsInWrittenOrder` (a blur then a shadow vs a shadow then a blur) | absent | append at front |
| `everyMaterialMatchesSwiftUIOverWhiteAndBlackM5` (12 × 2 composites within ±1) | absent | swap thin/thick |
| `aMaterialFollowsTheColourScheme` | absent | light table in dark |
| `materialSpellingsResolveWithoutAmbiguity` (guard 3.T1: `.background(.ultraThinMaterial)`, `.background(.surface)`, `.fill(.red)`, `.fill(LinearGradient(…))`, `.fill(LinearGradient(…), style: FillStyle(eoFill: true))`, legacy `Text("x").background(.thinMaterial, in: Capsule())` in one file, plain import) | absent | add `static let surface` to `Material`; declare `background(_:in:)` on `ProposalElementGroup` only (`LK-R`) |
| `theLayoutModifierBlurCaseIsOneIdentityLevel` | absent | wrap in two layers |
| replay parity: frame 9 replays on SDL (`PortableReplay --driver metal` locally; llvmpipe and D3D12 in CI) with `--expect 9` (`LK-S`) | absent (8 frames) | `SDLBridge.c` image sampler `address_mode_v` = `REPEAT`, isolated copy — frame 9 must fail (the first design's "change the table on one side" cannot: the texels are shared) |

Pixel tests read the scene through the existing `FakePlatformWindow`/scene
dumps (`PaintPrimitiveTests` style) and the CPU textures directly — no GPU
readback, no golden file (stage 7a).

## §5 Platforms

- **macOS (AppKit + Metal)**: everything; the only shader-adjacent work is new
  `MUIImage`s.
- **SDL (Linux, Windows)**: everything draws identically through the image
  pipeline; the colour panel is the same drawn panel; AccessKit rows for the
  three roles. Lane 1 runs `Backends/SDL` on macOS and the Linux image
  (`docker build -t metalui-portable …`, the volume
  `metalui-sdl-build-controls-looks`); lane 3 records frame 9 and replays it on
  macOS (`--driver metal`); CI replays on llvmpipe and D3D12 on push (`LK-S`
  item 4: the offscreen Linux image does not replay).
- No new `PlatformWindow`/`Platform`/`WindowRenderer` requirement in this
  branch (the colour-panel seam is designed in `LK-C` item 6 and deferred).

## §6 Demo expectation

`METALUI_CONTROLS_DEMO=1`: a "Controls and looks" section — a slider whose
editing state and a coalesced-edit counter are shown beside it (one count per
drag), a `ColorPicker("Accent", …)` and a `ColorPicker("Opaque", …,
supportsOpacity: false)` driving a swatch, and a progress row (spinner at three
control sizes, a bar animated by a slider, a titled bar with a current-value
label, an indeterminate bar). `METALUI_LOOKS_DEMO=1`: a keyframes row (a "Shake"
button shaking a box, the MetalCreator snippet) and a looks row (a vertical
window-style gradient panel, a diagonal and a radial gradient, a blurred text
and image with a radius slider, and the six materials over a striped backdrop
in both schemes). **The fourteen offscreen images read 0 px against `cd84b0c`**
(`docs/probes/demo-pixels/compare.sh <scratch> cd84b0c HEAD`), checked at the
end of each lane. A real-window look only when the lock probe allows.

## §7 Human checks (added to `docs/verification/human-checks.md` in the Record phase)

1. The colour well's look against an `NSColorWell` beside it; the drawn panel
   opens anchored to the well, flips near a window edge, and closes on Escape
   and an outside press.
2. Dragging in the square and bars feels continuous; a theme role edited in
   MetalCreator coalesces into one undo step per drag (M5-a and M6-f together).
3. The spinner at 32/16/10 points against `NSProgressIndicator`'s; its step
   rate looks like AppKit's (24 per 0.8 s); the indeterminate bar's motion.
4. The determinate bar's track and fill colours in light/dark, key and inactive
   windows.
5. A window-background gradient during live resize stays smooth (the strip
   path), and a large diagonal one shows its first-frame raster cost.
6. Gradient banding at 8 bits on a P3 display (divergence 1 applies).
7. A blurred text and image look like SwiftUI's at the same radius.
8. Materials over a striped backdrop: the flat tint versus SwiftUI's blur
   (divergence 166 is visible by design) — in both schemes; **and over a
   uniform backdrop in a real key window**, whether SwiftUI's tint matches the
   ImageRenderer fit (`LK-O` item 2: `cacheDisplay`, `M4`, cannot tell).
9. The keyframe shake reads as a shake at 60 Hz and on a 120 Hz display.
10. VoiceOver: the well announces its colour; the panel's sliders adjust; a
    progress view announces its fraction; a spinner announces busy. (**An
    agent cannot run VoiceOver**, `IX-AE`.)

## §8 Divergences (labels from this branch's range; rows added by the lanes)

| Label | Lane | Subject |
|---|---|---|
| 165 | 1 | `ColorPicker` on macOS opens a drawn popover, not `NSColorPanel` (`LK-C` item 6) |
| 166 | 3 | materials draw a flat tint fitted from ImageRenderer, with no backdrop blur (`LK-L`, `LK-O` item 2) |
| 167 | 3 | a GPU surface leaf under `.blur` is drawn unblurred (`LK-K` item 5) |
| 168 | 2 | `SpringKeyframe` requires `duration:` (`LK-I` item 5) |
| 169 | 2 | keyframe track values constrain `VectorArithmetic` (not `Animatable`); the content closure receives the element itself (`LK-I` item 8) |
| 171 | 2 | a zero-duration keyframe reads its target, not `nan` (`LK-I` item 7) |

170 and 172–174 stay reserved for lane findings. Each row gets a record §04
section and a pin (the tests above named for them).

## §9 What this design did not measure

- The determinate bar's colours and the spinner's spoke shape (ImageRenderer
  draws platform views as a placeholder, `V9`; `cacheDisplay` read an inactive
  dark window, `V14`) — looks, human checks 3–4.
- The indeterminate bar's period (`V8`'s animation was not timed) — `LK-F`
  item 2 picks 1.6 s, a look.
- Whether SwiftUI animates a gradient's stops under a transaction, and a
  determinate `NSProgressIndicator`'s fill animation — recorded as unmeasured,
  not divergences.
- SwiftUI's default `SpringKeyframe` length (`K4b`, `K4d` recorded; unfitted).
- Real-window captures (the screen was locked for the whole session).
- A material's tint in a real window (`M4`'s `cacheDisplay` does not
  composite it; `LK-O` item 2). `M1` is not byte-stable (±1 between runs,
  `LK-O` item 1).
