# Overlays and coordinates (C15) — design

Item C15 of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**), for MetalCreator's editor polish: its gaps **EP-a** (an element's frame
in window/named coordinates, a coordinate space on `onContinuousHover`, the
window's size) and **EP-b** (a chrome-less point-anchored popover that closes on
any outside press), `docs/metalui-gaps.md` from line ~420, checked on `c62d6ba`.
Branch `feat/overlays-coords` from `ebcf3c7` (3204 tests in 3 suites). Rulings
`OV-A`…`OV-P` in `../2026-10-10-overlays-coords-decisions.md`; record §92;
divergence labels 225–234 (this branch's range; only **225** is used).

Builds on C9 (record §88: `onGeometryChange`, `KF-J`/`KF-S`, `.global` frames
already built — OV-I) and on menus/popovers (record §74: `.popover` as an
anchored presentation root, `MN-M`/`MN-N`/`MN-Y`/`MN-Z`). `.help` needs nothing.

## 1. SwiftUI's answers (probes, recorded 2026-10-10)

`docs/probes/swiftui-overlays-coords.swift` (compiled, run twice,
byte-identical, 90 lines; re-run by the critic byte for byte, then arms G6/G7
added, 100 lines, run twice byte-identical) and `docs/probes/swiftui-overlays-coords-typecheck.sh`
(T0–T16, each a one-file `swiftc -typecheck`).

| Claim | Arm | Answer |
|---|---|---|
| Point anchor exists, both presentations | T11, T12, T13 | compiles |
| Point anchor placement | A1–A7 vs control A0 | a zero-size rect at the unit point of the anchor's bounds; popover centred across `arrowEdge`, arrow tip at the point; `.rect(.rect(r))` is in the anchor's space |
| A corner of the popover at the point | A1–A7 | never |
| Chrome-less popover | B0–B2, T15 | `.presentationBackground(.clear)` keeps frame, glass and shadow (B1 = B0); `.red` recolours (B2, separating); no `popoverStyle` |
| Named spaces | G1–G5, T4, T16 | nearest ancestor; missing or sibling → `.global`; moves with its container's effects, rotation included |
| Named frame under a rotation | G6 vs G4, G7 | container at 30°: named stays exact (30,30,40x20) — not the global box mapped back (separating; at 90° they coincide); an effect between space and element: its box in the space (`OV-M`) |
| `Sendable` | SDK interface, `swiftc -swift-version 6` | SwiftUI's `CoordinateSpace`, `NamedCoordinateSpace`, `PopoverAttachmentAnchor` are `~Sendable`; an `AnyHashable` payload refuses in a `Sendable` enum (`OV-L`) |
| `CoordinateSpace` cases | T9 vs T10 | exactly `local`, `global`, `named` |
| Hover coordinate space | T1–T3 | `onContinuousHover(coordinateSpace:)` exists; behaviour unmeasurable (hover is a recorded broken instrument, `SV-N`) |
| Window size in the environment | W0/W1, T0 vs T5–T8 | none |

gpui (`anchored.rs`): `anchored()` defaults to `Anchor::TopLeft` and
`AnchoredFitMode::SwitchAnchor`; `position` is in window coordinates; with
`on_mouse_down_out` it is exactly EP-b. OV-A rests on it where SwiftUI has
nothing.

## 2. Public API

### 2.1 EP-b (lane B)

```swift
public enum PopoverAttachmentAnchor: Sendable, Hashable {      // OV-B, divergence 225; extra conformances additive (OV-L)
    case rect(Source)
    case point(UnitPoint)
    public struct Source: Sendable, Hashable {
        public static var bounds: Source { get }
        public static func rect(_ r: Bounds<Pixels>) -> Source  // in the anchor's own space
    }
}

extension StyledElement {                                     // and ProposalElementGroup, same four
    public func popover<P: ElementGroup>(isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds), arrowEdge: Edge? = nil,
        @ElementBuilder content: @escaping @MainActor () -> P) -> PopoverModifier<Self, P>
    public func popover<Item: Identifiable, P: ElementGroup>(item: Binding<Item?>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds), arrowEdge: Edge? = nil,
        @ElementBuilder content: @escaping @MainActor (Item) -> P) -> PopoverModifier<Self, P>

    /// MetalUI-only (OV-A, OV-K).
    public func anchoredOverlay<P: ElementGroup>(isPresented: Binding<Bool>, at point: Point<Pixels>,
        in space: CoordinateSpace = .local, anchor: UnitPoint = .topLeading,
        @ElementBuilder content: @escaping @MainActor () -> P) -> PopoverModifier<Self, P>
    public func anchoredOverlay<Item: Identifiable, P: ElementGroup>(item: Binding<Item?>,
        at point: Point<Pixels>, in space: CoordinateSpace = .local, anchor: UnitPoint = .topLeading,
        @ElementBuilder content: @escaping @MainActor (Item) -> P) -> PopoverModifier<Self, P>
}
```

The existing `popover(isPresented:arrowEdge:content:)`/`item:` declarations are
**replaced** by the defaulted ones (every call compiles unchanged; the census
re-records their signatures). `presentationBackground(_:)` is not built (OV-C).

### 2.2 EP-a (lane A)

```swift
public enum CoordinateSpace: @unchecked Sendable, Hashable {  // OV-D — migration note; OV-L
    case local, global
    case named(AnyHashable)
}
public struct NamedCoordinateSpace: @unchecked Sendable, Hashable {   // OV-L
    public static func named(_ name: some Hashable) -> NamedCoordinateSpace   // SwiftUI's exactly
}
extension ElementGroup {                                      // both vocabularies through ElementGroup
    public func coordinateSpace(_ space: NamedCoordinateSpace) -> CoordinateSpaceScope<Self>
}
public struct CoordinateSpaceScope<Content: ElementGroup>: ElementGroup  // + ProposalElementGroup when Content is
extension StyledElement {
    public func onContinuousHover(coordinateSpace: CoordinateSpace = .local,
                                  perform action: @escaping (HoverPhase) -> Void) -> Self
}
extension ProposalElementGroup {
    public func onContinuousHover(coordinateSpace: CoordinateSpace = .local,
                                  perform action: @escaping (HoverPhase) -> Void) -> HoverModifier<Self>
}
extension EnvironmentValues {
    public internal(set) var windowSize: Size<Pixels>         // OV-G, MetalUI-only
}
```

`GeometryProxy.frame(in:)`, `DragGesture(coordinateSpace:)`,
`SpatialTapGesture(coordinateSpace:)` and `onTapGesture(coordinateSpace:)`
accept `.named` through the enum (OV-E, OV-H). The old
`onContinuousHover(perform:)` declarations are replaced by the defaulted ones.
`AnyHashable` in a `Sendable` enum refuses under Swift 6 (measured): `OV-L`
settles `@unchecked Sendable` on both types, the hole named in their doc
comments.

## 3. Implementation

### 3.1 Lane A — coordinates

- **`SpatialGestures.swift`**: the case; `NamedCoordinateSpace`; doc comment
  carries `CI-AC`'s migration sentence.
- **New `CoordinateSpaceScope.swift`**: the transparent scope (OV-E item 1),
  copied from `GeometryChangeScope`'s two entries (typed and untyped, each
  pinned). Layout records the content's nodes; prepaint computes the frame like
  `noteGeometry` (factor the union-scroll-effect computation into
  `Frame.localSpace(of nodes:) -> NamedSpace?`, used by the scope, by
  `noteGeometry` and by lane B's `.local` overlay, `OV-N`), builds a
  `NamedSpace(name:, toSpace:, toWindow:)` (both directions; `nil`
  `toSpace` when degenerate) and runs the content's prepaint inside
  `frame.withNamedSpace(_:)` (push/pop). `PrepaintPass.deferred` keeps the
  stack (`OV-M` item 2).
- **`Frame.swift`**: `namedSpaces: [NamedSpace]` (the stack),
  `namedSpace(_ name: AnyHashable) -> NamedSpace?` (innermost; `nil` for a
  degenerate entry), `hitboxNamedSpaces: [Int: [NamedSpace]]` filled in
  `insertHitbox`'s registering path only while the stack is non-empty,
  `namedSpaceSnapshots` work counter, and `presentationSpaces:
  [GlobalElementID: NamedSpace]` with `recordPresentationSpace(_:for:)` and
  `previousPresentationSpaces` (for lane B, OV-K, OV-N, OV-P).
- **`GeometryChange.swift`**: `GeometryProxy` gains the named spaces in force,
  the scrolled union and the element's composed map; `frame(in: .named(n))`
  maps the union through `toSpace ∘ composed` and boxes once (`OV-M` item 1 —
  never the boxed `globalFrame` mapped back); `.global` when missing; the
  switch is exhaustive.
- **`Hover.swift`**: `HoverAttachment.coordinateSpace`; both
  `onContinuousHover`s take it; `updateHoveredRegions` converts through it
  (`.local` as today, `.global` the window point, `.named` via
  `lastHitboxNamedSpaces[index]`); `HoverPhase`'s doc loses "only `.local`".
- **`Gesture.swift`**: `ArenaLeaf.point(_:in:)` an exhaustive switch; the leaf
  takes its hitbox's snapshot at arena formation (OV-H).
- **`EnvironmentValues.swift`** + **`Window.swift`**: `windowSize` and its
  stamp beside `titleBarInsets`'; `lastHitboxNamedSpaces`,
  `lastPresentationSpaces` carried like `lastHitboxes`/`lastPresentationAnchors`.

### 3.2 Lane B — presentation

- **`AnchoredPresentation.swift`**: `edge` becomes `placement:
  PresentationPlacement` — `.popover(anchor: Bounds, edge: Edge)` (the resolved
  attachment rect) or `.overlay(point: Point<Pixels>, anchor: UnitPoint)` (a
  window point) — and `chrome: Bool`; paint skips the panel when `false`;
  `OpenPopover.consumesAnchorPress`. New `OverlayPlacement: ProposalLayout`
  with `static func origin(point:size:anchor:window:)` (OV-A item 2).
- **`Popover.swift`**: `PopoverModifier` stores a `PopoverKind`
  (`.popover(PopoverAttachmentAnchor, Edge)` or `.overlay(point, space,
  anchor)`); `layOutPopover` resolves the attachment anchor against
  `previousPresentationAnchors[id]` (OV-B) or the overlay point (OV-K, OV-N:
  `.global` as is; `.local` and `.named` through
  `previousPresentationSpaces[id].toWindow`, `.global` when absent or
  degenerate); prepaint records, for an overlay, the declarer's own space
  (`frame.localSpace(of:)`, `.local`) or `frame.namedSpace(n)` (`.named`)
  with `frame.recordPresentationSpace`. `PopoverModifier`'s stored properties
  change: `swift package clean` before the next native build. The overlay's
  chrome `Box` has padding 0. `dispatchPopovers` honours
  `consumesAnchorPress`. The four popover overloads gain `attachmentAnchor:`.
- **New `AnchoredOverlay.swift`**: `PopoverAttachmentAnchor`, the four
  `anchoredOverlay` overloads.
- **Demo**: new `Sources/MetalUIDemoContent/OverlaysDemo.swift`
  (`METALUI_OVERLAYS_DEMO=1`, one line in `Sources/MetalUIDemo/main.swift`),
  each section its own function (1 MB stacks): a canvas declaring
  `.coordinateSpace(.named("canvas"))` with a crosshair from
  `onContinuousHover(coordinateSpace: .named("canvas"))`; a click opens a
  palette (`anchoredOverlay(at: pointer, in: .named("canvas"))`, glass-free:
  a `.surface` rounded content of its own, a `TextField` and a list); a
  readout of `windowSize` and the palette's `onGeometryChange` named frame.
  **Expectation**: the palette's top-left corner is at the click, flipped at the
  right/bottom edges; any press outside (left, right, middle; onto the field
  beside it or the slider) closes it — a primary press on the canvas itself
  closes it **and** reaches the canvas, whose click handler reopens it at the
  new point (OV-A item 3, gpui's `on_mouse_down_out`); Escape closes it; typing reaches its
  field. No existing demo moves: **0 px in all fourteen images**.

### 3.3 Platforms

Everything is in `MetalUI` (drawn presentations, the window's input hook). No
`PlatformWindow`/`Platform`/`WindowRenderer` requirement, no shader, no
`Backends/SDL` change (the SDL Docker run is not owed; Linux/Windows CI build
the root as usual). AppKit and SDL behave identically; the native-popover
divergences 111/112 are unchanged.

## 4. Tests

"Red before" for every new test: the file does not compile at `ebcf3c7`; each
lane also takes the red against a **stub** (API compiles, behaviour absent —
named resolves as `.global`, hover ignores the space, `windowSize` unstamped,
the overlay drawn with chrome at the declarer's centre), recorded in its red
commit. Mutations: commit first, restore from a copy, full unfiltered suite,
name every reddened test.

### 4.1 Lane A — `Tests/MetalUITests/CoordinateSpaceTests.swift`

| # | Test | Follows | Mutation that must redden it |
|---|---|---|---|
| A1 | `frameInNamedSpaceIsRelativeToTheNearestAncestorSoNamed` | G1, G2 | `namedSpace(_:)` takes the outermost match |
| A2 | `aNameNoAncestorDeclaresFallsBackToGlobal` (missing; sibling) | G1, G5 | the scope never pops its entry (sibling arm) |
| A3 | `aNamedSpaceMovesWithAnOffsetOnItsContainer` | G3 | the entry built without the composed map |
| A4 | `aRotatedNamedSpaceReportsTheUnrotatedFrame` (**30°**, G6's literals) | G6 | (a) `toSpace` as "minus the bounding box's origin" (A3 stays green: separating); (b) the boxed `globalFrame` mapped back (`OV-M`; separating only off 90°) |
| A4b | `anEffectBetweenTheSpaceAndTheElementReportsItsBoxInTheSpace` | G7 | the element's own effect dropped from the composed map |
| A5 | `aNamedSpaceInsideAScrollerFollowsTheScroll` (space inside content: constant; outside: moves by the offset) | — | entry origin unscrolled |
| A6 | `coordinateSpaceAddsNoNodeAndNoIdentityLevel` | — | the scope numbers its content from 0 under a new level |
| A7 | `noNamedSpaceMeansNoSnapshots` (work counter 0; K spaces × H hitboxes = derived literal) | — | snapshot on every registration |
| A8 | `theTypedAndUntypedScopeEntriesAreEachPinned` | — | each entry's push dropped in turn |
| A9 | `continuousHoverReportsTheGlobalPoint` | OV-F | hover ignores the space |
| A10 | `continuousHoverReportsTheNamedPointUnderAScroll` | OV-F | `.named` treated as `.global` in hover |
| A11 | `continuousHoverDefaultsToLocalAndALaterOnHoverKeepsTheSpace` | OV-F | default `.global`; `HoverAttachment.hover` dropping the space |
| A12 | `aDragGestureInANamedSpaceReportsNamedLocations` | OV-H | `point(_:in:)` maps `.named` as `.global` |
| A13 | `aSpatialTapInANamedSpaceReportsTheNamedPoint` | OV-H | same site (A12 and A13 both named) |
| A14 | `windowSizeIsInTheFirstPresentedFrameAndFollowsAResize` (equals `contentSize`, also with a fake answering `setToolbar` `false`, the drawn strip included) | OV-G, OV-O | drop the stamp; stamp the root's size below the strip |
| A15 | `stampingWindowSizeLeavesASteadyWindowClean` (a second `drawFrameIfNeeded` draws nothing) | OV-G | stamp through `Window.environment` |
| A16 | `aNamedGeometryValueIsReportedOnceAndOnChange` | KF-J | named value excluded from `isEqual` input (re-reports every frame) |
| A17 | `aPresentationsContentResolvesItsDeclarersNamedSpace` | OV-M 2 | `PrepaintPass.deferred` clears the stack |
| A18 | `presentationSpacesAreCarriedToTheNextFrame` (`.local` with an effect, `.named`) | OV-N, OV-P | not carried; `localSpace` without the composed map |

Guards (`Tests/MetalUITests/CoordinateSpaceCompileGuards.swift`, `typecheckFile`
with a plain import, each mutated red once): **GA1**
`windowSizeIsReadOnlyOutsideMetalUI` (red: setter `public`); **GA2**
`coordinateSpaceTakesOnlyANamedSpace` (`.coordinateSpace(.global)` refuses;
red: parameter typed `CoordinateSpace`); **GA3** `theNamedSpaceSpellingsCompile`
(`.coordinateSpace(.named("x"))`, `frame(in: .named("x"))`,
`onContinuousHover(coordinateSpace: .named("x"))`, `DragGesture(coordinateSpace:
.named("x"))`, an exhaustive three-case switch, `\.windowSize`,
`.coordinateSpace(.named(NonSendableName()))` under Swift 6; red: drop
`coordinateSpace:` from the proposal `onContinuousHover`; second red, `OV-L`:
the factory constrained `& Sendable`).

Unchanged and staying green: every `GeometryChangeTests`, `HoverTests`,
`InputAPI*` test (A11's default mutation must redden the existing local-point
hover tests too — lane A names them).

### 4.2 Lane B — `Tests/MetalUITests/AnchoredOverlayTests.swift` (+ `PopoverTests.swift` for B1–B5)

| # | Test | Follows | Mutation that must redden it |
|---|---|---|---|
| B1 | `aPointAnchorCentresThePopoverOnThePoint` (args: four edges) | A1, A4–A6 | `.point` resolved as the whole bounds |
| B2 | `aRectSourceIsInTheAnchorsOwnSpace` | A7 | the source rect used as a window rect |
| B3 | `aPointAnchoredPopoverFlipsAndClamps` | MN-M | flip skipped for a zero-size anchor |
| B4 | `aPressOnAPointAnchoredPopoversDeclarerIsStillConsumed` | MN-Y 2, OV-B | `consumesAnchorPress` false for popovers |
| B5 | `theDefaultAttachmentAnchorIsTheBounds` | OV-B | default `.point(.center)` (also reddens `theDefaultArrowEdgeIsTop`) |
| B6 | `anOverlayPutsItsTopLeadingCornerAtThePoint` | OV-A 2 | origin centred on the point |
| B7 | `anOverlayFlipsPerAxisAtTheRightAndBottomEdges` (args: right, bottom, both) | OV-A 2 | flip both axes when either overflows; no flip (clamp only) |
| B8 | `anOverlayThatFitsNeitherWayIsClampedInsideTheWindow` | OV-A 2 | clamp dropped |
| B9 | `anOverlayHonoursItsAnchorUnitPoint` (`.bottomTrailing`, `.center`) | OV-A 2 | anchor ignored |
| B10 | `anOverlayDrawsNoChromeAndNoPadding` (no `.surface`/border rect, no shadow leaf, content at the point) | OV-A 1 | `chrome: true` for overlays |
| B11 | `anOutsidePressOfEveryButtonDismissesAnOverlay` (args: primary, secondary, other) | OV-A 3 | the secondary/other arms skip overlays |
| B12 | `aPressIntoAFieldASliderOrAContextMenuDismissesAndStillLands` (args: field focuses, slider writes, context menu opens) | EP-b | the popover stage moved after `dispatchTextInput` (field arm) |
| B13 | `aPressOnTheDeclarerDismissesTheOverlayAndPassesOn` | OV-A 3 | `consumesAnchorPress` true for overlays |
| B14 | `escapeDismissesTheTopmostOverlayEvenWithAFieldInsideFocused` | OV-A 5 | Escape arm after the key stages |
| B15 | `aPressOrWheelOnTheOverlayNeverReachesBeneath` | MN-Z | the raw opaque hitbox skipped when `chrome == false` |
| B16 | `keysReachAFocusedTextFieldInsideTheOverlay` | OV-A 5 | — (pin; mutation: the popover stage claims every key while open) |
| B17 | `anOverlayAtAPointWrittenWithItsBindingAppearsThereInTheFirstFrame` | OV-K | the point taken from the last frame |
| B18 | `anOverlayInGlobalAndNamedSpaces` (+ arm: `.local` under `.scaleEffect(2)` on the declarer) | OV-K, OV-N | `.named` placed as `.global`; `.local` as bounds origin + point (scale arm) |
| B19 | `anOverlayIsReplacedOnAWindowResize` | OV-K | placement cached across frames |
| B20 | `anOverlayAddsOneIdentityLevelOnlyForItsCaller` | MN-L | slot at cursor 0 |
| B21 | `anOverlayWritesNoStateTableEntryAndPublishesAPopoverNode` | MN-O | `popoverHint` dropped for overlays |
| B22 | `aProposalPathOverlayPresentsPlacesAndDismisses` | — | the proposal overload forwards `.topLeading` as `.center` |
| B23 | `anOverlayItemFollowsTheItemAndResetsOnANewID` | ID-R | item name not applied |
| B24 | `overlaysDemoOpensThePaletteAtThePointerAndClosesOnAnOutsidePress` | demo | — (demo pin) |

Plus an arm in `everyProductionTreeBuildsOnAOneMegabyteThread` for the overlays
demo (its own `@inline(never)` frame). Guards
(`Tests/MetalUITests/AnchoredOverlayCompileGuards.swift`): **GB1**
`thePopoverAttachmentAnchorSpellingsCompile` (`.rect(.bounds)`,
`.rect(.rect(b))`, `.point(.topLeading)`, `item:`; red: drop `attachmentAnchor:`
from the proposal `item:` overload); **GB2** `theAnchoredOverlaySpellingsCompile`
(both vocabularies, `item:`, `in: .named("x")`; red: drop `in:`'s default).

Unchanged and staying green: every `PopoverTests`/`PopoverCompileGuards` test.

**Expected totals**: 3204 + 19 (A) + 24 test functions (B, parametrised cases
counted as the runner counts them, measured) + the 1 MB arm if it is a new
case; guards 195 → 200 is not assumed — the lanes measure under
`--build-system native` and grep `FR-J no-argument frame: succeeded=`.

## 5. Documents (Record phase)

- `docs/divergences.md`: **225** (`PopoverAttachmentAnchor.Source` for
  `Anchor<CGRect>.Source`, rect in `Bounds<Pixels>`); the header's next-label
  line is left for the merge.
- `docs/migration.md`: `CoordinateSpace.named` (an outside exhaustive switch
  owes a case); the popover overloads' signatures.
- Inventory map rows: `PopoverAttachmentAnchor` (+`Source`) **D 225**,
  `anchoredOverlay` **M**, `NamedCoordinateSpace`, `coordinateSpace(_:)`,
  `CoordinateSpaceScope` **A**, `onContinuousHover(coordinateSpace:perform:)`
  **A**, `windowSize` **M**; the `input-apis-global-space` row's note gains
  `.named`; `presentationBackground` **R** (OV-C). Census re-recorded.
- `docs/verification/human-checks.md`, new group **OV** (not run — an agent
  cannot): OV1 the palette opens with its corner at the real pointer and flips
  at both edges of a live window; OV2 one right-click outside closes it and
  opens the context menu beneath; OV3 typing into its field, Escape closing it
  with the field focused; OV4 the crosshair from `.named("canvas")` hover stays
  under the pointer across a scroll; OV5 `windowSize` tracks a live resize and
  the palette re-flips.
- CLAUDE.md rule paragraph (OV-), `docs/record/92-overlays-coords.md`,
  `docs/record/README.md` row, `cp CLAUDE.md AGENTS.md`.

## 6. Lanes (at most two; disjoint files; run in order A then B)

| Lane | Files (owned) |
|---|---|
| **A — coordinates** (OV-D–OV-H, OV-L, OV-M, OV-O, OV-J/OV-P's provisions) | `Sources/MetalUI/SpatialGestures.swift`, `GeometryChange.swift`, `Hover.swift`, `Gesture.swift`, `EnvironmentValues.swift`, `Window.swift`, `Frame.swift`, new `CoordinateSpaceScope.swift`; tests `CoordinateSpaceTests.swift`, `CoordinateSpaceCompileGuards.swift` |
| **B — presentation** (OV-A, OV-B, OV-K, OV-N) | `Sources/MetalUI/Popover.swift`, `AnchoredPresentation.swift`, new `AnchoredOverlay.swift`; `Sources/MetalUIDemoContent/OverlaysDemo.swift`, `Sources/MetalUIDemo/main.swift`; tests `AnchoredOverlayTests.swift`, `AnchoredOverlayCompileGuards.swift`, additions to `PopoverTests.swift`, the arm in `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift`, `docs/verification/human-checks.md` group OV |

Parallel branches: `fix/smk-port-gaps` (C12: drawn menu bar, `MenuSession`,
window chrome height) and `feat/test-harness` (item 8: `Sources/MetalUITesting`).
Lane A's `Window.swift`/`Frame.swift` edits are additive stored properties and
one stamp line; lane B stays out of `MenusDemo.swift` and `Menu*.swift`.

## 7. What must not move

Identity and retention (the seven slots, `MC-A`/`MC-C`/`MC-P`; the overlay slot
is `.popover`'s cursor 1), hit testing (the named-space table is a side table
no ranking reads), accessibility (an overlay publishes `.popover`'s node),
animation, focus, `List`, `Deferred`, text input. 0 px in the fourteen images;
`DemoFrameDeterminismTests`' `Expected.swift` unedited; 0 `warning:` on both
build systems; `MetalUILayout`/`MetalUIScene` imports unchanged;
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green.

## 8. Deferred (named, with reason and owner)

- `presentationBackground(_:)` — OV-C; cannot carry EP-b; no owner until an app
  asks.
- `coordinateSpace(name:)` (deprecated in SwiftUI), `CoordinateSpaceProtocol`,
  `.scrollView` — OV-D; `.named` covers EP-a; no owner.
- ~~A named space under an effect between the container and the element~~ —
  withdrawn: probed (G7) and built (`OV-M`, A4b).
- `.named` translation of a `DragGesture` under a rotated space — OV-H;
  unmeasured.
- SwiftUI's overlay-like `presentationCompactAdaptation` and iOS sheets —
  product boundary (`PB-A`).
