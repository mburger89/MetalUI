# Input follow-ups — design spec

Item C16. Rulings: [`../2026-10-10-input-followups-decisions.md`](../2026-10-10-input-followups-decisions.md)
(`IF-A`…`IF-J`). Evidence: `docs/probes/swiftui-input-followups.swift` (recorded
in its header). Baseline `f2fe54a`: **3237 tests in 3 suites**, 0 goldens, the
`FR-J no-argument frame: succeeded=` line, 0 `error:`, the only `warning:`
SwiftPM's deprecation notice; `swift build --build-tests` 0 warnings; pixels 0 px
in the fourteen offscreen images (`docs/probes/demo-pixels/compare.sh <scratch>
f2fe54a HEAD`); `DemoFrameDeterminismTests` `Expected.swift` unedited.

## 1. Public API

SwiftUI spelling wherever SwiftUI has one; **MetalUI-only** marked.

```swift
// SpatialGestures.swift
extension SpatialTapGesture.Value {
    public var modifiers: EventModifiers          // MetalUI-only (div 235): the last press's
    public init(location: Point<Pixels>, modifiers: EventModifiers = [])
}
// Gesture.swift
extension DragGesture.Value {
    public var clickCount: Int                    // MetalUI-only (div 235): the press's, 1 default
    public init(startLocation:location:modifiers: = [], clickCount: Int = 1)
}
extension DragGesture   { public func onCancelled(_ action: @escaping @MainActor () -> Void) -> DragGesture }
extension MagnifyGesture { public func onCancelled(...) -> MagnifyGesture }   // MetalUI-only (div 236)
extension RotateGesture  { public func onCancelled(...) -> RotateGesture }
// ModifierKeysChange.swift — SwiftUI's signature, on every ElementGroup and the proposal vocabulary
extension ElementGroup {
    public func onModifierKeysChanged(mask: EventModifiers = .all, initial: Bool = true,
        _ action: @escaping @MainActor (_ old: EventModifiers, _ new: EventModifiers) -> Void) -> ...
}
```

`onModifierKeysChanged` returns the same transparent-scope type `onGeometryChange`
does (lane 3 reads `GeometryChange.swift` and copies its overload set: legacy
`ElementGroup`, `StyledElement` placement, proposal group). `.onScrollWheel`'s
signature is unchanged; its doc comment loses "a gliding scroll is not latched"
and gains `IF-G`/`IF-H`. No `PlatformWindow`/`Platform`/`WindowRenderer`/
`TextSystem` requirement is added, so no migration note beyond the value-type
fields (`swift package clean` after lane 1: stored properties on public types
crossing a module boundary). A new public declaration owes a doc comment and a map
row: `zsh docs/probes/closeout-inventory-check.sh` and
`zsh docs/probes/closeout-undocumented.sh` print nothing; the census is
re-recorded with `docs/probes/closeout-public-api.sh`.

## 2. Implementation by lane (sequential, one worktree; `IF-J`)

### Lane 1 — gesture values and cancellation

- `ArenaLeaf` gains `pressModifiers: Modifiers` (set at each `press`) and
  `reportedChange: Bool` (set where an `onChanged` callback is appended, drag,
  magnify, rotate). `SpatialTapGesture`'s callback builds `Value(location:,
  modifiers: leaf.pressModifiers.eventModifiers)`. `GestureArena` gains the
  press's `clickCount` per leaf (`pressClickCount`) for drag values.
- `GestureLeaf` gains `dragCancelled`, `magnifyCancelled`, `rotateCancelled`
  closures; `GestureArena.cancel() -> [GestureCallback]` appends, for every leaf
  with `status == .possible && reportedChange`, a `.gesture(owner:, run:)` and
  fails the leaf. `abandon()` calls it first (its existing `fail` loop stays).
- `Window`: `.mouseDown` branch's `arena.abandon()` keeps its place (now carries
  cancels); `buttonPress`'s `buttonArena = nil` and `dispatchPinch`'s
  `pinchArena = nil` (stale drops) become `cancel()` + run; `endPressForDrag`
  cancels before clearing; a new `.mouseMoved` arm in `dispatchButtonArena`'s
  caller cancels a live button arena (`IF-F` item 3) and drops
  `pendingContextMenu`; the control-state hook cancels the pinch arena on leaving
  `.key`; the close path cancels all three before `runDisappearancesForClose`.
- `Gesture.swift`'s "Not offered" doc keeps `@GestureState`/`updating`; names
  `onCancelled` as the replacement.

### Lane 2 — wheel latch and terminal phase

- New `ScrollLatch.swift`: `struct ScrollLatch { var cover: GlobalElementID;
  var layer: Int; var fingerInFlight: Bool; var momentumInFlight: Bool }`; one
  stored property on `Window`.
- `applyScroll(_:)` splits "find the cover and candidates at the pointer" from
  "walk the chain": the latched path builds the candidates by id and layer
  (ancestors of the latched cover, no `contains`), the pointer path is the current
  code byte for byte (`DD-Y`, `CI-AH`, `CI-AL` pins unmoved). The latch is set,
  advanced and cleared per `IF-G` item 3.
- `synthesizeTerminalScroll()` (`IF-H`) is called from the control-state hook (on
  leaving `.key`, beside `dismissInWindowMenu`) and the close path.

### Lane 3 — modifier keys

- New `ModifierKeysChange.swift`: `ModifierKeysScope` after `GeometryChangeScope`;
  `Frame.noteModifierKeys(...)` in prepaint; `LifecycleStore` gains the entry kind
  and its `endFrame` event; `Window.currentModifiers`, `hasModifierObservers`,
  `noteModifiers(from:)` at the top of `onInput` (before hover/active tracking,
  never claiming); the key-loss reset (`IF-D` item 4).
- `AppKitPlatform.refreshControlActiveState` (or its `didBecomeKey` path) sends
  `.modifiersChanged(modifiers(NSEvent.modifierFlags))`; `SDLBridge.c` fills
  `modifiers` for `MUI_EVENT_FOCUS_GAINED`; `SDLPlatform` forwards it.
- Demo: a section in `Sources/MetalUIDemoContent/CanvasDemo.swift`, **in its own
  function** (Windows 1 MB stack, `everyProductionTreeBuildsOnAOneMegabyteThread`),
  reachable only under `METALUI_CANVAS_DEMO=1`: a one-line readout of the held
  modifiers (from `onModifierKeysChanged`), the last tap's modifiers, the last
  drag's click count and the last cancel/scroll-phase. Nothing paints before
  input, so the fourteen default images stay 0 px; lane 3 checks the canvas demo is
  not among them with `compare.sh`.
- Human checks group **IF** appended to `docs/verification/human-checks.md` at the
  Record phase (§5).

## 3. How tests drive it headless

All with the existing `Window` test harness: a fake `PlatformWindow` whose
`onInput` the test calls (the recipe of `InputAPIGestureWindowTests`,
`InputAPIWindowTests`), `renderFrame`-style builds, the fake's
`onControlActiveStateChange` for key loss, and `simulateTick(timestamp:)`; no
test sleeps. Events carry `MouseEvent(position:modifiers:clickCount:)`,
`ScrollEvent(position:delta:modifiers:phase:momentumPhase:isPrecise:timestamp:)`
and `.modifiersChanged`. Each test below is **red before** the change (compile
error for a missing API, or the stated wrong behaviour) and names the **mutation**
that must redden it; mutations follow the practice file (commit first, restore
from a copy, full unfiltered suite, `git status --short` after, name every
reddened test). A suite with no summary after 12 minutes is a hang.

### Lane 1 (`GestureFollowupTests`, ids 1.x)

| id | test | red before | mutation that reddens it |
|---|---|---|---|
| 1.1 | `aSpatialTapReportsTheModifiersHeldAtItsPress` (press `[.command]`, release `[]`) | no field | take the release's modifiers |
| 1.2 | `aTapSequenceReportsTheLastPressModifiers` (`count: 2`, ⇧ then ⌘) | no field | keep the first press's |
| 1.3 | `aDragValueCarriesThePressClickCount` (press count 2: every `onChanged`, the `onEnded`) | no field | hard-code 1 / read the move event's count |
| 1.4 | `aSecondaryDragCarriesItsPressClickCount` (middle button arena) | no field | read the primary path only |
| 1.5 | `aDroppedPrimaryDragReportsCancelledOnceAndNotEnded` (drag past min on A, press elsewhere, no release) | no API | drop the cancel in `abandon()` |
| 1.6 | `aStaleButtonArenaReportsCancelledWhenTheSameButtonPressesAgain` (the `CI-AB` 2.26 setup) | silent drop | restore `buttonArena = nil` |
| 1.7 | `aStalePinchArenaReportsCancelledBeforeASameCentrePinchBegins` (second began at the same position; its first value is from 1, cancel ran first) | silent drop | restore `pinchArena = nil` |
| 1.8 | `aDragThatNeverBeganIsNotCancelled` (min 10, no move; an exclusive loser) | n/a | cancel every leaf |
| 1.9 | `aReleasedDragIsNotCancelledByTheNextPress` | n/a | cancel after `onEnded` too |
| 1.10 | `aMoveWithoutAButtonCancelsALiveButtonArena` (other-press, drag, `.mouseMoved`; a later press of another button then works; a pending context menu is dropped) | arena lives | remove the `.mouseMoved` arm |
| 1.11 | `aPrimaryArenaIsNotCancelledByAMoveWithoutAButton` (pins the deferral) | n/a | extend the arm to the primary arena |
| 1.12 | `aPinchArenaIsCancelledWhenTheWindowLeavesKey` | no API | remove the control-state line |
| 1.13 | `aDragIsNotCancelledWhenTheWindowLeavesKey` (SwiftUI `C4`; the release ends it) | n/a | cancel every arena on key loss |
| 1.14 | `aWindowCloseCancelsLiveArenasBeforeOnDisappear` (order recorded) | no API | run the cancel after the disappearances |
| 1.15 | `aDragStartedByADraggablesPreviewIsCancelled` (`endPressForDrag` with a reported `DragGesture`) | no API | remove the cancel in `endPressForDrag` |

Typecheck guards (new; each mutated red once, run under `--build-system native`):
`aDragValueBuiltWithoutAClickCountStillCompiles` (plain import, `typecheckFile`;
mutation: remove the default) and `onCancelledIsOfferedOnDragMagnifyAndRotate`
(mutation: remove `RotateGesture`'s). Existing guards `anOutsideTypeCannotConformToGesture`
and the `Handlers` size/count pins stay green and unedited.

### Lane 2 (`ScrollLatchTests`, ids 2.x)

| id | test | mutation |
|---|---|---|
| 2.1 | `aTrackpadScrollsMomentumGoesToTheElementItBeganOver` (A and B wheel handlers; `.began` over A, `.changed` and momentum over B: all A's) | dispatch by the pointer |
| 2.2 | `aNewBeganReplacesTheLatch` | never replace |
| 2.3 | `aWheelMouseIsNeverLatchedAndClearsTheLatch` (`phase .none, momentum .none` at B mid-latch goes to B) | latch on any event |
| 2.4 | `aLatchedScrollViewKeepsScrollingWhenThePointerLeavesIt` (offset advances off its bounds) | keep the `contains` test |
| 2.5 | `theLatchEndsAtMomentumEnded` and `aMayBeginLatchesNothing` | never clear / latch `.mayBegin` |
| 2.6 | `aLatchedElementThatLeftTheFrameFallsBackToThePointer` | trap/ignore on a missing id |
| 2.7 | `leavingKeyMidScrollSynthesizesOneCancelledToTheHandler` (finger stage: phase `.cancelled`, delta 0; momentum stage: phase `.none`, momentum `.cancelled`; exactly once) | skip the hook / synthesize twice |
| 2.8 | `aScrollThatEndedNormallySynthesizesNothing` and `eventsWithNoPhaseNeverSynthesize` (the SDL shape) | synthesize unconditionally |
| 2.9 | `aSynthesizedCancelMovesNoScroller` (offset and indicator state unchanged; the handler's `Bool` ignored) | route it through `scroll(_:by:)` |
| 2.10 | `closingMidScrollSynthesizesTheCancel` | omit the close path |

The existing `DD-Y`/`CI-AH`/`CI-AL` pins must stay green unedited (the pointer path
is untouched).

### Lane 3 (`ModifierKeysTests`, ids 3.x; `SDLModifierKeysTests`, 4.x)

| id | test | mutation |
|---|---|---|
| 3.1 | `aModifierChangeRunsTheActionWithOldAndNewAfterTheBuild` | run it inside the build / skip the drain |
| 3.2 | `aMaskFiltersTheChange` (⇧ with `mask: .command` runs nothing; ⌘ does; old/new masked) | ignore the mask |
| 3.3 | `initialTrueReportsAtTheFirstFrameAndFalseDoesNot` (also an empty current reports nothing) | invert `initial` |
| 3.4 | `modifiersCanComeFromAKeyEventAlone` (the SDL shape: a ⌘ `keyDown`, no `.modifiersChanged`) | read `.modifiersChanged` only |
| 3.5 | `leavingKeyReportsTheModifiersAsReleased` and `becomingKeyReportsTheCurrentOnes` | remove the reset |
| 3.6 | `aWindowWithNoScopeIsNotDirtiedByAModifierChange` (work counter: no extra build) | always dirty |
| 3.7 | `aRemovedScopeStopsReporting` and `twoStackedScopesBothReport` | leak the store entry / share a key |
| 3.8 | `aStillPointerHoverSeesACommandPress` (end to end: `onContinuousHover`, then ⌘ with no move; the model holds both) | n/a (composition pin) |
| 3.9 | `aHeadlessRenderRunsNoModifierAction` | run in `renderFrame` |
| 4.1 | `aFocusGainedCarriesTheModifiersHeld` (`SDLPlatform`, via the bridge's synthesize function; arms `armMainRunLoopExitCheck()`) | drop the field |
| 4.2 | `anSDLKeyEventForAModifierKeyReachesTheWindow` (gated `.enabled(if: windowsPresentFrames)` where it needs a presented frame; the Linux image's offscreen driver otherwise via `SDLPlatform(offscreenRenderers:)`, `TF-C`) | n/a |
| 4.3 | AppKit: `becomingKeySendsTheCurrentModifiers` in `AppKitInputAPITests` | remove the send |

Existing tests that must stay green unedited: `theSevenRetentionSlotsAreMutuallyDistinct`,
the `Handlers` count/size pins, `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
`everyProductionTreeBuildsOnAOneMegabyteThread`, `DemoFrameDeterminismTests`.

## 4. Verification each lane owes

Build `swift build --build-system native --build-tests`; run `swift test
--build-system native --no-parallel` unfiltered and read the one summary line and
the `FR-J` line; `swift build --build-tests` 0 warnings; the fourteen images 0 px;
lane 3 also `Backends/SDL` (`python3 Backends/SDL/scripts/fetch-accesskit.py`
once, then `swift test $(python3 scripts/fetch-accesskit.py --print-flags)`) and
the `metalui-portable` image (`docker build -t metalui-portable -f
Backends/SDL/linux/Dockerfile Backends/SDL`, then the run line with volume
`metalui-sdl-build-input-followups`; OrbStack left running). A real-window capture
only when `appkit-screen-lock-state.swift` allows.

## 5. Human checks (group IF, appended at the Record phase; not run by an agent)

- **IF1** `onModifierKeysChanged`: demo readout follows ⇧/⌘/⌥/⌃ held still;
  compare with a SwiftUI sample app for old/new and `initial` (the probe's `M` arms
  did not run, `IF-D`); ⌘-Tab away with ⌘ held and back.
- **IF2** ⇧-click on the demo canvas reports ⇧ in the tap readout, also when ⇧ is
  released before the button.
- **IF3** Double-click on the canvas reads `clickCount` 2 at the speed set in
  System Settings > Mouse (slow it, then speed it).
- **IF4** Flick the canvas to glide, move the pointer onto the style strip: the
  glide stays on the canvas (`CI-AD`'s Y13 now answers yes).
- **IF5** Hold the middle button, open Mission Control or a native menu, release
  there, return: the readout shows a cancel on the first plain move.
- **IF6** ⌘-Tab mid-trackpad-scroll: the readout shows `cancelled` once.
- **IF7** Pinch, ⌘-Tab, pinch again at the same spot: first gesture reads cancelled,
  the second starts from 1.

## 6. Out of scope (named, with reason and owner)

`@GestureState`/`updating` (`IF-A`), a drag per button, primary lost-release
detection, `modifiers` on other taps, a probe of AppKit latching and of
`onModifierKeysChanged`'s timing (`IF-A`, `IF-D`, `IF-G`), reading the system
double-click interval for taps (`IF-C`: SwiftUI does not). Owner of each: none,
all additive. Files this branch stays off: the `feat/test-harness` (HT-) and
`feat/overlays-coords` (OV-) lanes' (`CoordinateSpace` is untouched; no case added).
