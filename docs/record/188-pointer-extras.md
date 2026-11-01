# 188 - pointer and hover extras (`PH-A`..`PH-J`)

2026-11-01, branch `feat/pointer-extras` from master `5be22a6a`; round-3 item R3-10 part 2. Rulings:
`docs/superpowers/2026-11-01-pointer-extras-decisions.md`. Probe: `docs/probes/swiftui-pointer-extras.swift` (ran in this session; output recorded in
its header). Rules: `docs/rules/input-focus.md` ("Pointer extras") and `docs/rules/sdl.md`. Human checks: group PH. No divergence label taken
(1015-1024 reserved, unused).

## 1. What was there

The brief expected `frameResize`, `pointerVisibility`, `columnResize(directions:)`, `rowResize(directions:)`, `onContinuousHover` with other spaces and
the hover effects to be missing. The macOS SDK's `SwiftUI`/`SwiftUICore` `.swiftinterface` files (searched for `PointerStyle`, `pointerVisibility`,
`onContinuousHover`, `HoverPhase`, `hoverEffect`, `FrameResizePosition`, `FrameResizeDirection`, `onHover`, `pointerStyle`) and MetalUI's sources say:

| SwiftUI on macOS | MetalUI before this change |
|---|---|
| `PointerStyle` statics, `image(_:hotSpot:)`, `pointerStyle(_:)` (macOS 15) | built (`CI-H`, `IC-`) |
| `frameResize(position:directions:)`, `FrameResizePosition`, `FrameResizeDirection(.Set)` | **built already** (`CI-H`) |
| `columnResize(directions:)`, `rowResize(directions:)`, `HorizontalDirection(.Set)`, `VerticalDirection(.Set)` | **missing** |
| `pointerVisibility(_:)` | **missing** |
| `onContinuousHover(coordinateSpace:perform:)`, `HoverPhase`, `onHover` | **built**, with `.global` and `.named` since `OV-F` (the divergences page's "Not offered" row was stale) |
| `shape(_:eoFill:size:)` | `@available(macOS, unavailable)`; MetalUI's own look (divergence 735) |
| `hoverEffect`, `HoverEffect`, `CustomHoverEffect`, `HoverEffectGroup`, `defaultHoverEffect`, `hoverEffectDisabled`, `listRowHoverEffect*` | **`@available(macOS, unavailable)`**: not applicable |
| `TableRowContent.onHover` | macOS 14; MetalUI has no `Table` (carried) |

## 2. The probe, in one table

Instrument: `swiftui-input-apis.swift`'s (hosted window, `cursorUpdate` driven into the tracking areas, `NSCursor.current`), plus a swizzle of
`+[NSCursor hide]`/`unhide`/`setHiddenUntilMouseMoves:` to see SwiftUI's hide (the control `V0` is a direct `hide()`); two runs, byte-identical.

| arm | result |
|---|---|
| `D1` `columnResize(directions: .all)` | = `D0` `.columnResize` (`resizeLeftRight`) |
| `D2` `.leading`, `D3` `.trailing` | `NSCursor.columnResize(directions: .left)` / `.right` (`resizeLeft` / `resizeRight`) |
| `D4` `[]` | the arrow |
| `D6`-`D9` rows | `.all` = `rowResize`; `.up` = `rowResize(.up)`; `.down`; `[]` = the arrow |
| `V2` `.hidden` | `NSCursor.hide()` once on entering, `unhide()` once on leaving; `current` unchanged |
| `V3`, `V4` `.visible`, `.automatic` alone | no call |
| `V5` outer `.hidden`, inner `.visible`, over inner | no hide (inner wins) |
| `V6` inner `.automatic` | hides (defers to the outer) |
| `V7`, `V7b` with `.pointerStyle(.link)`, either order | hides **and** `current` = pointing hand (independent); `V7c` the hand alone |
| `V9` an opaque `onTapGesture` sibling over the pointer | no hide (covered, as a style is) |

The first two runs of the instrument were discarded (a removed CoreGraphics API; `current` read after leaving) - the probe's header says so.

## 3. Design

`HorizontalDirection`/`VerticalDirection` and their `Set`s are SwiftUI's option sets. `PointerStyle.columnResize(directions:)`/`rowResize(directions:)` normalise
`.all` to the existing `.columnResize`/`.rowResize` and the empty set to `.default`, and lower one direction to the seam's `columnResizeOneWay(towardTrailing:)` /
`rowResizeOneWay(towardDown:)` (`leading` is the left, unmirrored, as `frameResize`). `pointerVisibility(_:)` stores `.hidden`/`.visible` in `PointerAttachment`
(`.automatic` attaches nothing; the inner wins), registered through the existing pointer region (`registerHandlers`, same gates), counted in `pointerStyleRegionCount`.
`Window.updatePointerStyle` finds the innermost style and the innermost visibility in one walk (the cover is also eligible when it carries a visibility), resolves
`.hidden` to the one internal `PointerStyle` kind `.hidden` when the winning visibility is `.hidden`, and sends `.arrow` once when the pointer leaves the window while hidden.

Platforms: AppKit sets `NSCursor.columnResize(directions:)`/`rowResize(directions:)` (macOS 15+; the one-way `resize*` cursors on macOS 14) and, for `.hidden`,
a **transparent 1x1 cursor** (not the counted `NSCursor.hide()`: nothing to balance if a window closes or the pointer leaves while hidden). SDL maps one-way to its
single-edge `W`/`E`/`N`/`S_RESIZE` cursors (no one-arrow divider cursor exists) and `.hidden` to `SDL_HideCursor()` through two new bridge functions (any other style
shows the pointer first). `HeadlessPlatformWindow`/`TestWindow` record the style, `.hidden` included. No new `PlatformWindow` requirement: the seam gains three cases.

## 4. Source breaks

An outside exhaustive `switch` over `PlatformPointerStyle` owes `.columnResizeOneWay`, `.rowResizeOneWay` and `.hidden` (or `default:`): `docs/migration.md`. New public
types `HorizontalDirection`, `VerticalDirection` could collide with an app's own of those names. A stored property was added to `PointerAttachment` (internal class):
no `swift package clean` needed beyond the usual.

## 5. Tests and mutations

`PointerExtrasTests.swift` (MetalUITests; 11), `appKitMapsTheOneWayResizesAndTheHiddenCursor` (AppKit; 1), `theHeadlessPlatformRecordsAHiddenPointerAndAOneWayResize`
(MetalUITestingTests; 1), `sdlOneWayResizesMapToEdgeCursorsAndHiddenHidesTheCursor` (`Backends/SDL`, run there, not in the root suite; 1), and the `ModifierTests` table
(66 -> 67 cases, `pointerVisibility(_:)`). 15 mutations, each applied to the named declaration (branch and spelling), the filtered tests run, and reverted:

| # | mutation (file, spelling) | reddened |
|---|---|---|
| 1 | `PointerStyle.columnResize(directions:)`: `.leading` lowered to `trailing: true` and `.trailing` to `false` | `aDirectionalResizeLowersAsProbeDMeasured`, `aOneWayResizeReachesThePlatformOnBothVocabularies`, `theHeadlessPlatformRecordsAHiddenPointerAndAOneWayResize` |
| 2 | `rowResize(directions:)`: the `(false, false)` arm `.rowResize` instead of `.default` | `aDirectionalResizeLowersAsProbeDMeasured` (line 66) |
| 3 | `HorizontalDirection.Set.all = [.leading]` | `theDirectionSetsAreSwiftUIsOptionSets`, `aDirectionalResizeLowersAsProbeDMeasured` |
| 4 | `updatePointerStyle(at: nil)`: drop the `sendPointerStyle(.arrow)` for a hidden pointer | `aHiddenPointerIsSentOnEntryAndShownAgainOnExit` |
| 5 | `PointerAttachment.visibility`: drop the `visibility != .automatic` guard | `theInnermostVisibilityWinsAndAutomaticDefers`, `aVisibilityRegionCountsAsAPointerRegion` |
| 6 | `pressedPointer(_:)`: ignore the visibility | `aPressHoldsAHiddenPointerWhileThePointerLeaves` |
| 7 | `updatePointerStyle`: drop `hoverIsSuppressed ||` | `aDrawnAlertShowsThePointerOverAHiddenRegion` |
| 8 | `pointerUnderPointer` cover eligibility without the visibility arm | `anOpaqueTargetAboveCoversAVisibilityRegion` (the uncovered half), `aHiddenPointerIsSentOnEntryAndShownAgainOnExit`, `theInnermostVisibilityWinsAndAutomaticDefers`, `pointerVisibilityIsWithdrawn…`, `visibilityAndStyleAreIndependentDeclarations`, `aVisibilityRegionCountsAsAPointerRegion`, `aDrawnAlert…`: not isolated; the cover test names the half that is |
| 9 | `pointerUnderPointer`: the outermost visibility wins (`found.visibility == nil` guard) | `theInnermostVisibilityWinsAndAutomaticDefers`, `visibilityAndStyleAreIndependentDeclarations` |
| 10 | `Frame.registerHandlers`: drop `enabled` from the pointer region's gate | `pointerVisibilityIsWithdrawnByDisabledAllowsHitTestingAndHidden` (the disabled arm) |
| 11 | `Frame.registerHandlers`: count `pointer.style` only | `aVisibilityRegionCountsAsAPointerRegion` and the hidden tests (a frame with only a visibility region resolves nothing) |
| 12 | `AppKitCursor`: `.columnResizeOneWay` sides swapped | `appKitMapsTheOneWayResizesAndTheHiddenCursor` |
| 13 | `AppKitCursor.hiddenCursor`: opaque pixel (255) | `appKitMapsTheOneWayResizesAndTheHiddenCursor` (`alpha == 0`) |
| 14 | `Window.updatePointerStyle`: `.hidden` resolved to `style ?? .default` | `aHiddenPointerIsSentOnEntryAndShownAgainOnExit`, `anOpaqueTargetAbove…`, `aPressHoldsAHiddenPointer…`, `pointerVisibilityIsWithdrawn…`, `theInnermostVisibility…`, `visibilityAndStyleAreIndependentDeclarations`, `aDrawnAlert…`, `theHeadlessPlatformRecordsAHiddenPointerAndAOneWayResize` |
| 15 | `SDLCursorTable`: `towardTrailing ? .wResize : .eResize`; `SDLWindow.setPointerStyle`: never show after a hide | `sdlOneWayResizesMapToEdgeCursorsAndHiddenHidesTheCursor` (four expectations) |

(Mutations 1-7 and 14 were applied in groups with disjoint expected reds; the reddened tests above are by name. Mutation 8's cover half is the one test that isolates the
cover; the others redden because a lone visibility region is no longer a cover at all.) No survivor. The one test that first failed on arrival was
`theInnermostVisibilityWinsAndAutomaticDefers`'s last expectation (mine: `.hidden` then `.visible` on one element keeps the first written, `.hidden`; the test expected
the opposite) - a wrong test, fixed to the `CI-AH` item 2 rule.

## 6. Counts

Root, `swift test --build-system native --no-parallel`, unfiltered, after `swift build --build-system native --build-tests`: **`Test run with 4830 tests in 13 suites passed after 1062.171 seconds`**, `FR-J no-argument frame: succeeded=true` (guards ran). Master's last count was 4817: +13 = the 11 `PointerExtrasTests`, the AppKit test and the headless test. An earlier run of the same tree failed one test, `anOutsideSwitchOverPlatformPointerStyleOwesTheImageCase` (its "old cases" list did not name the three new cases, so its positive controls stopped compiling); fixed by naming them. `Backends/SDL`: the two cursor tests pass (`swift test … --filter "sdlOneWayResizes|sdlPointerStylesMap"`) and the package builds. `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

## 7. Carried

`TableRowContent.onHover` (no `Table`), `PointerStyle.image(_ resource:)`, mirroring `leading`/`trailing` for the resize cursors in a right-to-left layout, and hover effects
(unavailable on macOS) - `PH-J`.
