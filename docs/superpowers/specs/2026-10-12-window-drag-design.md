# Window drag — design spec

Item C22. Rulings: [`../2026-10-12-window-drag-decisions.md`](../2026-10-12-window-drag-decisions.md)
(`WD-A`…`WD-I`). Evidence: `docs/probes/swiftui-window-drag.swift` (recorded in its
header). Baseline `a720fba`: **3402 tests in 3 suites**, 0 goldens, the
`FR-J no-argument frame: succeeded=` line, 0 `error:`, the only `warning:`
SwiftPM's deprecation notice; `swift build --build-tests` 0 warnings; pixels 0 px
in the fourteen offscreen images (`docs/probes/demo-pixels/compare.sh <scratch>
a720fba HEAD`); `DemoFrameDeterminismTests` `Expected.swift` unedited.

**Status: designed (2026-10-12), not built.**

## 0. The report, reproduced, and what the probe says

MetalCreator (C8-a): with `windowStyle: .hiddenTitleBar` a band press drags only
if nothing claims it (`AS-J`, `Window.answerUnclaimedTitleBarPress`: `active ==
nil && !hasGestureArena`). Its full-window viewport carries a `SpatialTapGesture`,
three `DragGesture`s and a `MagnifyGesture`, so every band press forms an arena
and the platform is never asked. Test 1.1 reproduces it headless
(`titleBarPresses == []`, the viewport's drag runs) and stays as the pin that
`AS-J` is untouched.

SwiftUI (probe, macOS 27.0.1): `WindowDragGesture` is attached with `.gesture`; a
region carrying it above a `DragGesture` base takes the press and moves the window
(W2; W9 the separating arm); it is **not exclusive** toward gestures on its own
view or parent (W3b, W4, W4b, W11) but loses to a `DragGesture` ahead of it (W3,
W11b); a secondary press, `allowsHitTesting(false)`, `.hidden()` and a clear view
with no `contentShape` do nothing (W7, W8a/d/e); `windowBackgroundDragBehavior` is
a **Scene** modifier. SwiftUI's spelling fits the one arena, so the item is a
gesture, not `.windowDragArea()` (`WD-B`).

## 1. Public API

```swift
// WindowDragGesture.swift (new). SwiftUI's spelling; one behavioural divergence (275).
public struct WindowDragGesture: Gesture {
    public struct Value: Equatable, Sendable { }      // no members, as SwiftUI's
    public init()
    @_spi(MetalUIGesture) public func _recognizers() -> _GestureRecognizers
}
// usage: Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
```

Platform seam (`PlatformWindow`, **defaultless**; migration: a conformer adds
`func performWindowDrag() -> Bool { false }`):

```swift
/// Moves the window with the pointer for the press now in progress; true when it did.
func performWindowDrag() -> Bool
```

`HeadlessPlatformWindow`: `public private(set) var windowDrags: Int`,
`Options.performsWindowDrag: Bool = true`. `TestWindow`: `public var windowDrags: Int`
(read-through; a `docs/testing.md` row). No other public surface.

## 2. Implementation

- `Gesture.swift`: `GestureLeaf.Kind.windowDrag`; `ArenaLeaf.isLive(in:)` (press
  arena only); `GestureArena.move`: `.windowDrag` ready when `distance >= tapSlop`;
  `act`: the `.draggable` arm's shape, emitting `.beginWindowDrag(owner:)` after
  the cancel callbacks of members that had reported; `isBlocked` and
  `yieldsToDraggable` use one `startsHandoff` predicate (`isDraggable ||
  isWindowDrag`); `release`/`tick` give `.windowDrag` `.draggable`'s arms (fails at
  the release); `GestureCallback.beginWindowDrag`. Every `switch` over `Kind` is
  exhaustive, so the compiler lists the sites.
- `Window.swift`: one `runGestureCallbacks` arm:
  `_ = platformWindow.performWindowDrag(); endPressForDrag()`. **No change** to
  `answerUnclaimedTitleBarPress`, hit testing, `Frame.registerHandlers`, `Handlers`,
  `Style`, layout, the renderer or the shaders.
- `Platform.swift`: the requirement and its migration doc comment.
- `MetalUIAppKit`: the host view retains the primary mouse-down `NSEvent` of the
  press (`currentPress`), set at the mouse-down dispatch, cleared at the matching
  up, at `resignKey`/close, and replaced by a second down;
  `AppKitWindow.performWindowDrag()` acts only while the host view is dispatching
  that press's mouse-dragged, through the injectable `performWindowDrag(with:)`
  (the injection style `AS-J` uses), with the stored event; else `false`.
- `Backends/SDL`: `performWindowDrag()` records (`windowDragRequests`), answers `false`.
- `MetalUITesting`: the headless window (§1).
- Every other conformer: `func performWindowDrag() -> Bool { false }` — the 15 files
  `grep -rl "func performTitleBarPress" Sources Tests Backends` lists.
- Public-API inventory: map rows for `WindowDragGesture`, `Value`, `init()`, its
  `Gesture` members (class A), `performWindowDrag`, `windowDrags`,
  `performsWindowDrag` (class M); doc comments; census re-recorded;
  `docs/divergences.md` 275, 276.
- Record phase: `docs/api-overview.md`, `docs/migration.md`, `docs/divergences.md`,
  `docs/testing.md`, `docs/verification/human-checks.md` (group `WD`), record 97,
  CLAUDE.md/AGENTS.md rule (one or two sentences), `docs/record/README.md`.

## 3. Demo

`METALUI_APP_SHELL_DEMO=1`: the hidden-title-bar section gains a 40-point handle
(`Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())`) over a
full-window `DragGesture` canvas that counts its drags, in **its own function**
(`everyProductionTreeBuildsOnAOneMegabyteThread` gets an arm for it). The default
demo and the fourteen offscreen images are untouched (0 px);
`DemoFrameDeterminismTests` unedited.

## 4. Lanes (at most two, disjoint files; run one after the other)

**Lane 1 (core, seam, headless, demo).** `Sources/MetalUI/{WindowDragGesture.swift,
Gesture.swift,Window.swift}`, `Sources/MetalUIPlatform/Platform.swift`,
`Sources/MetalUITesting/{HeadlessPlatformWindow.swift,TestWindow*.swift}`, every
fake's one line (the 15 files), `MetalUIAppKit` and `Backends/SDL` **stubs
answering `false`** so the tree builds, the demo, the inventory map/census,
`Tests/MetalUITests/WindowDragTests.swift`,
`Tests/MetalUITestingTests/WindowDragHeadlessTests.swift`, the guards. Commit
order: (1) skeleton (type, seam, stubs, a leaf never ready) with the tests, red
where marked S; (2) the arena; (3) conformers, docs, demo.
**Lane 2 (platforms).** `Sources/MetalUIAppKit/*`, `Tests/MetalUITests/AppKitWindowDragTests.swift`
(new), `Backends/SDL/**` (code and tests), the Linux image run, human checks `WD`,
a real-window capture only when the lock probe allows.

## 5. Tests — each with its red-before and the mutation that must redden it

Mutations: commit first, restore from a copy, full unfiltered suite, `git status
--short` after, name every reddened test. Red-before **S** = the skeleton commit
(type, seam, stubs, a leaf that is never ready); **B** = baseline `a720fba`.

Lane 1 — `WindowDragTests` (headless `TestApp`, `windowStyle: .hiddenTitleBar`,
`titleBarInsets.top = 32`; a full-window viewport with `DragGesture(minimumDistance:
0)` + `onCancelled`, a `SpatialTapGesture`, a `MagnifyGesture`; the handle a 32-point
strip above it unless stated):

| # | Test | Asserts | Red-before | Mutation → reddened |
|---|---|---|---|---|
| 1.1 | `aBandPressOverAGestureViewportDragsNoWindowWithoutAHandle` | no handle: `titleBarPresses == []`, `windowDrags == 0`, the viewport's drag reported (the C8-a reproduction) | B (passes; pins the bug and `AS-J`) | delete `!hasGestureArena` in `answerUnclaimedTitleBarPress` → 1.1 (`titleBarPresses == [1]`) |
| 1.2 | `aHandleOverAGestureViewportDragsTheWindowAndCancelsTheViewport` | press in the band, drag 20 pt: `windowDrags == 1`; viewport `changed` 0, tap/magnify not fired; arena gone | S | never `ready` (the skeleton); `act` not failing the others → viewport `changed` > 0 |
| 1.3 | `aMoveUnderTheSlopIsNoDragAndTheHandlesButtonStillClicks` | 4 pt + release: `windowDrags == 0`; a `Button` in the handle fires once | S | slop → 0 for the leaf: 1.3, 1.4 |
| 1.4 | `aMoveOfExactlyTheSlopBeginsOneDragAndNeverASecond` | 5 pt: `windowDrags == 1`; six more moves and the release add none; the release is no click | S | leaf not `ended` after acting → count > 1 |
| 1.5 | `aHandleInsideTheViewportCutsTheViewportsDragThatHadReported` | handle a child of the gesture view; viewport drag reports once, then `onCancelled` runs once, `onEnded` never | S | omit the cancel loop in the new `act` arm → `onCancelled` 0 |
| 1.6 | `aDragGestureInsideTheHandleOutranksIt` | probe W3: `windowDrags == 0`, the inner drag runs | S | treat an undecided drag ahead as yielding in `isBlocked` → red |
| 1.7 | `aHighPriorityAncestorDragOutranksTheHandle` | probe W11b: `windowDrags == 0` | S | register the leaf `.high` always → red |
| 1.8 | `aTapOnTheHandlesElementStillFiresAndDragsNothing` | `.onTapGesture` + `WindowDragGesture` on one element: press/release fires the tap, no drag | S | drop `.windowDrag` from the yield rule → red |
| 1.9 | `aSiblingViewportBeneathTheHandleNeverJoinsTheArena` | probe W2/W9: press in the handle, the viewport sees nothing; the same press outside, the viewport's | S | register the handle non-opaque → red |
| 1.10 | `aSecondaryOrOtherPressInTheHandleDragsNothing` | `rightClick`/`otherClick` + drag: `windowDrags == 0`; the `MN-B` context menu still opens | S | `isLive` true in a button arena → red |
| 1.11 | `allowsHitTestingFalseHiddenAndDisabledEachRemoveTheHandle` (3 arms) | each: the press reaches the viewport, `windowDrags == 0`; a frame without a handle has its old hitbox count | S | remove `hitTestingDisabledDepth == 0` from the opaque site → arms 1–2; remove `enabled` → arm 3 |
| 1.12 | `aPlatformAnsweringFalseStillEndsThePress` | `performsWindowDrag = false`: members still cut; `active == nil`; the release is no click; the next press forms a fresh arena | S | skip `endPressForDrag()` on `false` → red |
| 1.13 | `aPressAfterAWindowDragFormsAFreshArena` | second press-drag: `windowDrags == 2` | S | `endPressForDrag` omitted → the `CI-AB` stale path reddens |
| 1.14 | `aHandleWorksInAStandardTitleBarWindowAndAnywhereInTheWindow` | no `hiddenTitleBar`, handle mid-window: drags | S | gate the callback on `windowStyle` → red |
| 1.15 | `aWindowDragLeafIsAPointerTargetNotADraggable` | `isPointerTarget` true, `hasDraggable` false | S | `isDraggable` includes `.windowDrag` → red (and 1.9) |
| 1.16 | `anAttachmentOrderOfHandleAndDragOnOneElementIsInnerFirst` | `.gesture(drag).gesture(window)`: drag only; `.gesture(window).gesture(drag)`: window wins and cuts the drag (divergence 275) | S | reverse the sort in `GestureArena.init` → both arms |
| 1.17 | `aHighPriorityWindowDragGestureOutranksTheViewport` | probe W4 mapped: the window moves, the drag is cancelled | S | ignore `.high` for the leaf → red |

Existing pins that must stay green and unedited: `AppKitAppShellTests` 1.7b
(`appKitTitleBarPressDragsOnlyDuringAMouseDown`), the `AS-J` window tests,
`aPlatformWindowWithoutEachAppShellRequirementDoesNotCompile`.

Headless — `WindowDragHeadlessTests` (`MetalUITestingTests`): 2.1
`aHeadlessWindowRecordsWindowDragsAndAnswersItsOption` (B: compile-red), 2.2
`aTestWindowExposesWindowDrags`.

Guards (typecheck; each mutated red once):
- 3.1 `aPlatformWindowWithoutPerformWindowDragDoesNotCompile` — a row in
  `AppShellSeamCompileGuards`' table; mutation: a default in a protocol extension.
- 3.2 `aPlainImporterCanAttachWindowDragGestureButCannotGiveItCallbacks`
  (`typecheckFile`, plain import: `.gesture(WindowDragGesture())` compiles,
  `.onChanged` and a memberwise `Value(...)` do not); mutation: a public
  `onChanged`.

Lane 2:
- 4.1 `appKitWindowDragActsOnlyDuringTheDraggedEventOfAHeldPress`: a stored
  mouse-down and a drag dispatch → the injected `performWindowDrag(with:)` runs once
  with the stored event, answer `true`; outside a dispatch, or with no down, `false`.
  Mutation: drop the dispatching guard → red.
- 4.2 `appKitForgetsThePressAtTheMouseUpAndOnResignKey`. Mutation: keep it → red.
- 4.3 `appKitASecondDownReplacesTheStoredPressAndASecondaryDownIsNotStored`.
- 4.4 `sdlPerformWindowDragRecordsAndAnswersFalse` (`SDLAppShellTests`, arms
  `armMainRunLoopExitCheck()`; run in `Backends/SDL` and the Linux image; needs no
  presented frame, so no `.enabled(if:)` gate).
- 4.5 the cross-platform fake (`PortableFakeWindow`) compiles in the Linux image.
- 4.6 `theAppShellDemosHandleSectionBuildsOnAOneMegabyteThread` (an arm of
  `everyProductionTreeBuildsOnAOneMegabyteThread`).

Expected count: 3402 + 17 (1.1 is a new passing pin: counted) + 2 + 2 guards + 4
(AppKit 3, SDL is Backends' own count) + 1 demo arm ≈ **3424**; re-measure native,
read the one summary line and the `FR-J` line.

## 6. Human checks (new group `WD`, not run — an agent cannot)

- **WD-1** (the AS-5 equivalent): `windowStyle: .hiddenTitleBar` with the demo's
  handle over a gesture canvas — press-drag on the handle **moves the window**, the
  canvas does not react, and it follows to the release. Compare with SwiftUI's own
  `WindowDragGesture` in a scratch app for what the neighbouring gesture reports
  (divergence 275; the probe's delivery was synthetic).
- **WD-2** A click on a `Button` in the handle clicks it; a 3-point wobble does not
  drag; a 6-point move does, with no jump of the window.
- **WD-3** After a drag, hover, the pointer style and the next press work.
- **WD-4** A secondary press on the handle opens the context menu, drags nothing.
- **WD-5** A double click on the handle (no zoom, `WD-A`): record what real SwiftUI does.
- **WD-6** Full screen and Stage Manager: nothing harmful.
- **WD-7** Linux/Windows (SDL): the handle claims the press and moves nothing; the
  system title bar drags (divergence 276).

## 7. Risks and what would change the design

1. `performDrag(with:)` from a mouse-dragged dispatch with the stored mouse-down
   (`WD-D`): not runnable synthetically; the fallback is a one-site change.
2. The slop of 5 points is `tapSlop`; `WD-2` reads whether it is right.
3. Divergence 275 (cutting the neighbours) rests on a synthetic delivery; `WD-1` decides.
4. A handle is an opaque pointer target: a hover or wheel handler beneath it stops
   seeing the pointer there (as SwiftUI's overlay, probe `W2`, and any MetalUI
   `gesture`). MetalCreator's adoption note must say it.

## 8. Deferred (reasons and owners in `WD-A`)

`windowBackgroundDragBehavior` (a Scene modifier), `.windowDragArea()` (declined),
double-click zoom, gesture callbacks, SDL region drag (client decorations,
`AS-E` item 6), `allowsWindowActivationEvents`.
