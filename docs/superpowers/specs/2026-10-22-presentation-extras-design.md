# Presentation extras — design

Round 2 item 7 (user request 2026-10-21): `presentationBackground` (`OV-C`), `windowBackgroundDragBehavior` (`WD-A`), `PointerStyle.shape` (`IC-G`).
Rulings `BG-A`…`BG-N` in [`../2026-10-22-presentation-extras-decisions.md`](../2026-10-22-presentation-extras-decisions.md). Branch `feat/presentation-extras`
from `dd9a072f`. Record §144. Status: BUILT (two lanes verified ok, record §144).

## Outcome

All three **built**. What the probes decided: `presentationBackground` is a popover-panel fill reported from the popover's content (innermost wins, a declarer-level
use does nothing; `B2`–`B9`); `windowBackgroundDragBehavior` only drags with `.enabled` and does not use `isMovableByWindowBackground` (`D` arms); and
`PointerStyle.shape` **does not exist on macOS in SwiftUI** (visionOS only, `T1`), so it is MetalUI's own look on the visionOS spelling (`BG-K`), not a SwiftUI claim.
No platform requirement, no shader, no `Retained*.swift`, no `Handlers` member, no seventh/eighth state slot. Pixels: 0 px in the fourteen images (nothing is
visible by default: a popover closed, behavior `.automatic`, no shape cursor).

## Inventory (what exists at `dd9a072f`)

`PopoverModifier`/`Popover.swift` (`chrome(_:name:padding:)`: a `Box` padded 12, `PopoverChrome`), `AnchoredPresentation.swift` (`requestLayout` brackets the content with
`beginPresentationPreferences`/`endPresentationPreferences`; `paint` fills `theme[.surface]` with the `.separator` border under the shadow), `EnvironmentScope.swift`
(`EnvironmentWrite`, `reportingPreference`, `scopedValues`), `Frame.swift` (the collected-preference slots, 625–760), `WindowPreferences.swift` (`navigationTitle`, the
extension to copy), `MaterialTransparency.swift` (`fillMaterial`), `WindowShell.swift` (`answerUnclaimedTitleBarPress`), `WindowChrome.swift` (`WindowChromeState`,
`publishChromeRegions`, `chromeRegions`), `ChromeRegions.swift`, `PointerStyle.swift` (`Kind`, `.image`, `updatePointerStyle`), `Window.swift:2852` (`sendPointerStyle`),
`RasterCache.swift` (`pathImage`: the `PathRaster.fill/stroke` call shape), `ImageBitmap(width:height:rgba:)`, `PlatformCursorImage` (`MetalUIPlatform`), AppKit's
`performTitleBarPress`, SDL's `setWindowDragRegions`/`publishChrome`/`mui_chrome_hit`, `HeadlessPlatformWindow` (`titleBarPresses`, `windowDragRegions`, `Options.usesWindowDragRegions`).

## Public API (all with doc comments and inventory map rows)

```swift
// Lane 1 (MetalUI)
extension ElementGroup {
    public func presentationBackground(_ color: Color) -> EnvironmentScope<Self>
    public func presentationBackground(_ token: ColorToken) -> EnvironmentScope<Self>          // @_disfavoredOverload twin (CR-D)
    public func presentationBackground(_ material: Material) -> EnvironmentScope<Self>
    public func presentationBackground(_ gradient: LinearGradient) -> EnvironmentScope<Self>
    public func presentationBackground(_ gradient: RadialGradient) -> EnvironmentScope<Self>
    public func presentationBackground<Background: ElementGroup>(
        alignment: ProposalAlignment = .center, @ProposalContentBuilder content: () -> Background) -> EnvironmentScope<Self>
}
// Lane 2 (MetalUI)
public struct WindowInteractionBehavior: Sendable, Hashable {
    public static let automatic, enabled, disabled: WindowInteractionBehavior
}
extension Window { public var backgroundDragBehavior: WindowInteractionBehavior { get set } }
extension PointerStyle {
    public static func shape(_ shape: some Shape, eoFill: Bool = false, size: Size<Pixels>,
                             hotSpot: UnitPoint = .center, fill: Color = .black, outline: Color = .white) -> PointerStyle
}
```

(The first block's exact return type follows `navigationTitle`'s; the lane keeps whatever the existing extension returns.) Class: `presentationBackground` A (SwiftUI spelling,
the `ShapeStyle` generic spelled as overloads, divergence 119 stands); `WindowInteractionBehavior` A; `Window.backgroundDragBehavior` M (divergence 736); `shape` M (735).
No `PlatformWindow`/`Platform`/`WindowRenderer` requirement, so no migration note and no new honest-answer owed to the headless platform; a doc-comment sentence on
`WindowInteractionBehavior` and `PointerStyle`'s "not offered" text (`IC-G`) change.

## Files and lanes (sequential in this worktree; disjoint source files)

**Lane 1 — `presentationBackground`** (`BG-A`…`BG-F`). New `Sources/MetalUI/PresentationBackground.swift` (the spec enum, the extension, the content-background layout
and its named id); edits `EnvironmentScope.swift` (a case and its `reportingPreference`/`scopedValues` arms), `Frame.swift` (a collected slot saved/restored by the existing
`begin`/`endPresentationPreferences` bracket), `AnchoredPresentation.swift` (read the slot into `LayoutState`, paint it, request the content node), and `Popover.swift` only if the
bracket needs a hook. Tests `Tests/MetalUITests/PresentationBackgroundTests.swift`, guards `PresentationBackgroundCompileGuards.swift`. Not touched: `Retained*.swift`, `Window*.swift`,
`PointerStyle.swift`. Then inventory map rows, census, `docs/api-overview.md` (a popover paragraph), `OV-C` amended in its decisions doc (one line pointing here), divergences none new.

**Lane 2 — window background drag and the shape cursor** (`BG-G`…`BG-M`). New `Sources/MetalUI/WindowInteractionBehavior.swift` and `Sources/MetalUI/ShapeCursor.swift`;
edits `WindowChrome.swift` (state, `chromeRegions` and the publication), `WindowShell.swift` (the press), `ChromeRegions.swift` (the second candidate), `PointerStyle.swift`
(`Kind.shape`, the static), `Window.swift` (the one `sendPointerStyle` site and the cache field). Tests `WindowBackgroundDragTests.swift`, `ShapeCursorTests.swift`,
`AppKitWindowDragTests.swift` (one arm), `Backends/SDL/Tests` (one region test), guards `BackgroundDragCompileGuards.swift`. Not touched: `AnchoredPresentation.swift`, `EnvironmentScope.swift`,
`Frame.swift`. Lane 2 also adds the divergence rows 735–737, the SDL Linux-image run and the demo sections.

**Record phase** (after both lanes, Sonnet, no source): `docs/record/144-presentation-extras.md`, record §04 sections for 735–737, CLAUDE.md (a `BG-` paragraph, the prefix table, counts,
human-check groups list gains `BG`), `AGENTS.md` copy, `docs/record/README.md` row, `docs/verification/human-checks.md` group BG, `docs/api-overview.md`, `docs/guides` snippets
(popover background in `presentations.md`; shape cursor beside the image cursor in `input.md`; each mirrored by hand per `DG-C`, the background-drag one a `text`-free `swift` block
only if the mirror test can run it headless), `OV-C`, `WD-A`, `IC-G` marked built in their decisions docs.

## Tests, by name (every one red before: the API does not exist, so the call does not compile; the mutation is applied after green and must redden the named tests)

### Lane 1 (`PresentationBackgroundTests`, a `Window` over `HeadlessPlatform`, scene read as in `PopoverTests` 3.16)
1. `aPopoverPanelTakesThePresentationBackgroundColourAsItsFill` — the panel rect's background equals the colour. Mutation: paint ignores the slot (`theme[.surface]`). Reddens 1, 2, 4, 6.
2. `theInnermostPresentationBackgroundWins` (probe `B7`). Mutation: overwrite instead of keep-first.
3. `aPresentationBackgroundOutsideThePopoverContentChangesNothing` (`B4`): the declarer's modifier leaves the panel's fill `theme[.surface]`. Mutation: collect into the main slot, read by the chrome.
4. `thePanelKeepsItsBorderRadiusAndShadowUnderAPresentationBackground` (`OV-C`/`B1`). Mutation: skip the border when a spec is present.
5. `aMaterialPresentationBackgroundGoesThroughFillMaterial` (backdrop run present; with Reduce Transparency an opaque rect and no backdrop record). Mutation: call `fillBackdrop` directly (also reddens the existing `MT-` scan guard).
6. `aGradientPresentationBackgroundPaintsAGradientImageUnderTheContent` (one image run inside the panel, the raster counter 1, then 0 on the next equal frame).
7. `aColourTokenPresentationBackgroundFollowsTheColourScheme` (token resolves against dark and light). Mutation: resolve once at build.
8. `aContentPresentationBackgroundIsProposedThePanelAndPlacedByItsAlignment` (`B8` vs `B3`: a flexible `Color` fills the panel, a 30-pt-wide leaf sits at the leading edge; the panel size is the same with and without). Mutation: ignore `alignment`; mutation 2: let the background's size answer the layout.
9. `theContentBackgroundNameIsReturnedFresh` (an arm of `everyNamingSiteStartsAReturningNameFresh`, plus: the background's `@State` resets when the popover closes). Mutation: drop the `noteNamed` call.
10. `aPresentationBackgroundInAnAnchoredOverlayPaintsNothing` (`BG-A`: scene equal to the same overlay without it).
11. `aStrayPresentationBackgroundDoesNotChangeARetainedOccurrence` (`BG-F`: `FrameWork` counters equal with and without, an `.equatable()` occurrence, the graft still happens). Mutation: report into the main slot with a `BuildAudit` count.
12. `aPopoverWithAPresentationBackgroundHitsAndDismissesAsBefore` (hitboxes list equal, outside press dismisses). Mutation: insert an extra hitbox for the background node.
13. `aPresentationBackgroundDoesNotReachTheWindowsPreferences` (`preferredColorScheme`, title, toolbar untouched).
14. Guards (typecheck, native build, each mutated red once): `thePresentationBackgroundColourTokenTwinIsUnambiguous` (`.presentationBackground(.surface)` compiles: delete the twin); `presentationBackgroundIsOfferedOnAnElementGroupAndAProposalGroup`.
Work counters, not time: `FrameWork.environmentTransformCount`-style reads for the scope, the raster counter for 6.

### Lane 2 — background drag (`WindowBackgroundDragTests`, `HeadlessPlatform` with and without `usesWindowDragRegions`)
15. `anUnclaimedPrimaryPressOnTheBackgroundDragsWhenEnabled` (`titleBarPresses == [1]`). Mutation: drop the behavior check (reddens 16).
16. `automaticAndDisabledNeverDragFromTheBackground`.
17. `aPressOnAnOpaqueTargetANestedGestureOrAHandleNeverDragsFromTheBackground` (three arms: `onClick`, `DragGesture`, `WindowDragGesture` which keeps its own `performWindowDrag` path). Mutation: skip `active == nil`.
18. `aSecondaryPressAndADoubleClickOnTheBackgroundDoNotDrag` (`BG-H`). Mutation: pass `mouse.clickCount` through.
19. `theTitleBandKeepsItsDragWhateverTheBehavior` (`BG-J`): the three behaviors, `AppKitWindowDragTests`' band arms equal.
20. `theBackgroundRegionIsTheWindowCarvedByEveryBlocker` (`BG-I`, literal rects): a button at known bounds leaves the four surrounding rects. Mutation: carve by handles only.
21. `aWindowWideOpaqueBackdropLeavesNoBackgroundRegion` (separating arm for the band's exemption `CW-V`). Mutation: reuse `isBackdrop`.
22. `theBackgroundRegionIsEmptyWhileAPopoverADrawnAlertOrAMenuIsOpenAndWhileZoomed`. Mutation: drop the zoomed arm.
23. `aTooFragmentedBackgroundIsDroppedWholeNotCutShort` (more than 64 blockers: no background rect published, handles and band still present).
24. `aChangeOfBehaviorRepublishesTheRegionsOnceAndNeverOnAnEqualFrame` (`chromeCarveCount` and the published-count).
25. `appKitBackgroundPressDragsOnlyDuringAMouseDown` (the `AS-J` guard re-run for a point below the band). Backends/SDL: `aBackgroundRegionReachesTheSDLHitTestSnapshot` (the C twin `mui_chrome_hit` answers drag inside, normal at a carved button; `armMainRunLoopExitCheck()`; the Linux image runs it, gated where the offscreen driver cannot set a hit test).
26. Guards: `WindowInteractionBehaviorOffersExactlyThreeValues` (a plain-import `switch`-free equality list), `theBackgroundDragBehaviorIsSettableFromOutsideTheModule`.

### Lane 2 — shape cursor (`ShapeCursorTests`; `TestWindow.pointerStyle` reads the resolved `.image`)
27. `aShapeCursorIsAnImageCursorOfTheShapeRasterizedAtTheDisplayScale` — pixel size `(size × scale) + 2 × ceil(scale)`, point size `size + 2`, centre pixel black and opaque, a pixel outside transparent, the ring white. Mutation: raster at scale 1.
28. `eoFillLeavesTheHoleOfAnOverlappingPathTransparent` (separating: the same path nonzero is filled). Mutation: always nonzero.
29. `aShapeRebuiltEveryFrameIsOneCursorWithOneTexture` (`setPointerStyle` records one send, one texture identity across 5 frames; `ShapeCursorCache` counter: 1 raster). Mutation: key the cache by closure identity.
30. `aDifferentSizeScaleHotSpotOrColourIsAnotherCursor` (four arms, each one new raster and one new send). Mutation: leave `outline` out of the key.
31. `theShapeCursorHotSpotIsTheCentreByDefaultAndClampsOutsideTheUnitSquare`. Mutation: hot spot from the bitmap origin.
32. `aNonFiniteOrEmptySizeFallsBackToTheArrowAndAnOversizedOneClampsTo128`. Mutation: no clamp (the pixel size reads 1000+).
33. `theShapeCursorCacheKeepsTheEightMostRecentlyUsed` (nine shapes then the first again: a ninth raster). Mutation: no eviction (reddens 33 by the raster counter).
34. `aShapeCursorCostsNoFrameRasterWork` (`RasterCache.lastTexturesMade` and `touchedImages` unmoved by a send). Mutation: route the cursor through `animationStore.rasters`.
35. `aShapeCursorUnderAScaleChangeIsReSentOnceAtTheNewScale` (headless display-scale change).
36. Guard `theShapeCursorSpellingTypechecksWithTheVisionOSCall` (`.shape(Circle(), size: …)` and the `eoFill:` call; a call omitting `size:` does not compile).

Each mutation runs as a **commit-first, restore-from-copy, full unfiltered suite** (the practice), `git status --short` after, every reddened test named in the record.
Whole-suite expectation: 4264 + the lanes' new tests (about 50), 0 goldens, typecheck guards + 6 (each mutated red once), the fourteen images 0 px against `dd9a072f`.

## Demo expectation

`METALUI_MENUS_DEMO=1`: one popover gains a background (a `Color` fill and, in its own function, a gradient one) — the popover is closed in the default frame, so the images
stay 0 px (`docs/probes/demo-pixels/compare.sh <scratch> dd9a072f HEAD`; if any reads nonzero the section moves behind its own flag). `METALUI_CHROME_DEMO=1`: a toggle
that sets `window.backgroundDragBehavior` and a labelled region with a `.pointerStyle(.shape(…))` (a star path, `eoFill`). Each section in its own function (Windows 1 MB stacks,
`everyProductionTreeBuildsOnAOneMegabyteThread` covers it).

## Human checks (group `BG`, appended to `docs/verification/human-checks.md`, **not run**)

`BG1` a popover with each background spelling on AppKit and SDL (colour, token in both schemes, gradient, material over busy content, border and shadow kept, translucent fill
over the window behind). `BG2` background drag on macOS (drag from empty space; a press on a button/text field/slider never moves; double-click does nothing) and SDL Linux/Windows
(drag from empty space; hover and wheel in the region are lost, divergence 737; the 64-region cap with a dense form). `BG3` the shape cursor at 1x and 2x on macOS and SDL (outline
visible on light and dark, hot spot centred, eo hole). `BG4` SwiftUI with `.enabled`: does a press on a Button/Toggle begin a window move (the probe could not separate it).

## Deferred (named, with reason and owner)

`presentationBackground` on `anchoredOverlay`/alerts/menus (`BG-A`: no panel or no view; a `.sheet` would reuse the channel), a `<S: ShapeStyle>` generic (divergence 119),
background drag from a control (`BG-G`, check `BG4`), a drag while zoomed on SDL (`BG-I`), animated or stroked shape cursors (additive), visionOS look (unmeasurable here,
`BG-K`). Owner: none.

## Risks the lanes must stop on

Lane 1: the content spelling's named id surviving a close (`BG-E`'s escape hatch: ship the colour spellings and carry the content one). Lane 2: SDL's 64-rect cap
behaviour of `ChromeHitMap.carve` (read it before writing test 23; if it already returns a conservative single rect the test pins that instead and `BG-I`'s sentence is amended), and
any change in the fourteen images from the pointer-style or region work (there should be none).
