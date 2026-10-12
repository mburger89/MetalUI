# 97 — Window drag, `WindowDragGesture`

Branch `feat/window-drag` from `a720fba` (master: C15 §92 and C16 §93 merged), merged with
master `5f35df6` (C20, `fix/foreach-identity`, §95; the only conflict was `docs/divergences.md`'s
table, resolved by keeping 255 and 275–277). **Not a plan task**: item C22 of the gpui-gap
priority list (user request 2026-10-02), reported by MetalCreator (`docs/metalui-gaps.md` there,
gap **C8-a**, human check AS-5; read, never edited). Spec
`docs/superpowers/specs/2026-10-12-window-drag-design.md`; rulings `WD-A`…`WD-K` in the new
decisions doc `docs/superpowers/2026-10-12-window-drag-decisions.md` (next unused `WD-L`); probe
`docs/probes/swiftui-window-drag.swift` (arms `W0`…`W11`).

**Numbering.** Written as §97 from the start. `§94` (backdrop blur, C21), `§95` (`ForEach`
identity, C20, already on master) and `§96` (text selection, C25) belong to the parallel branches;
master carried no 97 at the merge, so §97 stands. The human-checks group is **WD** (provisional
letter, in the manner of `IF`/`SG`); the divergence labels are this branch's reserved range
**275–284**, of which 275–277 are used.

**Status: LANDED — every agent-doable clause is built; the looks are owed to a human**
(`docs/verification/human-checks.md` group WD, §7). Two lanes, each red first, both verified
`ok: true`. `NSWindow.performDrag(with:)` called from a mouse-*dragged* dispatch is the one call no
headless test can prove (`WD-D`, check WD1).

## §0 Baseline, the report, the probe

- **Baseline** at `a720fba`: **3402 tests in 3 suites**, 0 goldens, the `FR-J` line, 0 `error:`, the
  only `warning:` SwiftPM's deprecation notice; fourteen offscreen images; `Backends/SDL` untouched
  since.
- **The report (C8-a).** With `windowStyle: .hiddenTitleBar` a band press drags only when nothing
  claims it (`AS-J`, `Window.answerUnclaimedTitleBarPress`: `active == nil && !hasGestureArena`).
  MetalCreator's full-window viewport carries a `SpatialTapGesture`, three `DragGesture`s and a
  `MagnifyGesture`, so every band press forms an arena and the platform is never asked. Test 1.1
  (`aBandPressOverAGestureViewportDragsNoWindowWithoutAHandle`) reproduces it headless
  (`titleBarPresses == []`, the viewport's drag reported) and **stays as the pin that `AS-J` is
  untouched**.
- **Probe** `swiftui-window-drag.swift` (positive control `W1`, separating arms `W9`, `W8f`, `W11d`;
  run twice, two deliveries, 58 stdout lines byte-identical; macOS 27.0.1, Swift 6.4, screen
  locked). The instrument sees a window move only through AppKit's stderr diagnostic, so what a
  *real* drag does to the other gestures is unmeasured (check WD1). Findings: a region carrying
  `WindowDragGesture` above a `DragGesture` base takes the press (`W2`; `W9`); the gesture is
  **not exclusive** toward gestures on its own view or parent (`W3b`, `W4`, `W4b`, `W11`) but loses
  to a `DragGesture` ahead of it (`W3`, `W11b`); a secondary press, `allowsHitTesting(false)`,
  `.hidden()` and a clear view with no `contentShape` do nothing (`W7`, `W8a`/`W8d`/`W8e`); an
  `.opacity(0)` region is inert (`W8c`); `windowBackgroundDragBehavior` is a **Scene** modifier.
  The critic round re-ran `W8c` byte for byte (md5 `2cbb77aa2cfe92ee3ec16b5463de18c4`).

## §1 What landed

- **`WindowDragGesture`** (`Sources/MetalUI/WindowDragGesture.swift`, portable on every platform,
  `WD-B`): SwiftUI's spelling and surface — `struct WindowDragGesture: Gesture`, an empty
  `Value: Equatable, Sendable`, `init()` — attached with `.gesture`/`.highPriorityGesture`/
  `.simultaneousGesture`. **SwiftUI's spelling fits the one arena, so `.windowDragArea()` is not
  built.** It makes its element an opaque pointer target at the element's bounds or `contentShape`
  (`IX-D` item 5): no new hitbox kind, no `Handlers` member (still nineteen), no
  `Frame.registerHandlers` arm. The sibling viewport beneath the handle never joins the arena
  (they are not its ancestors), which is MetalCreator's case.
- **The arena leaf** (`Gesture.swift`, `WD-C`): `GestureLeaf.Kind.windowDrag`, live in a **press**
  arena only (a secondary or other press forms a button arena and drags nothing, `W7`), **ready at
  the first move of at least `tapSlop` (5 points)**, blocked exactly as a draggable is (`isBlocked`
  and the yield rule share one `startsHandoff` predicate over `isDraggable || isWindowDrag`): an
  undecided tap, long press or click ahead does not hold it, an undecided `DragGesture` ahead
  does. When it acts it ends, emits `GestureCallback.beginWindowDrag(owner:)` **after** the
  `onCancelled` of every member that had reported (`IF-F` item 1), and fails the rest without an
  end — `.draggable`'s `act` arm, line for line.
- **`Window`** (`WD-D`): one `runGestureCallbacks` arm, `_ = platformWindow.performWindowDrag();
  endPressForDrag()` — whatever the platform answers, the press was handed off and must not
  complete a click later. `answerUnclaimedTitleBarPress`, hit testing, `Handlers`, `Style`, layout,
  the renderer and the shaders are **unchanged**.
- **The seam** (`WD-E`): `PlatformWindow.performWindowDrag() -> Bool`, **defaultless**; migration
  row in `docs/migration.md`. AppKit (`AppKitPlatform.swift`): the host view keeps the primary
  mouse-down `NSEvent` of the press (`forgetHeldPress()` at the up, at `resignKey`/
  `windowWillClose`, on a second down) and `AppKitWindow.performWindowDrag()` calls
  `NSWindow.performDrag(with:)` with it **only while dispatching that press's mouse-dragged**
  (`true`), else `false`. The band's injected closure is renamed `performTitleBarDrag` (`WD-K` 1);
  nothing else of `AS-J` moved. SDL records (`SDLWindow.windowDragRequests`) and answers `false`
  (`WD-F`, divergence 276: no `SDL_SetWindowHitTest` region list — it would swallow a handle's
  buttons, the SDL window keeps its system decoration, and it would be a second requirement; owner
  client-side decorations, `AS-E` item 6). The headless window records (`windowDrags`, exposed on
  `TestWindow`) and answers `Options.performsWindowDrag` (default `true`). Every test fake gains the
  one line (`FakePlatformWindow` records `windowDrags`; `PortableFakeWindow` answers `false`).
- **Gates** (`WD-G`): the gesture rides its element's hitbox, so `allowsHitTesting(false)`,
  `.hidden()` and `.disabled` each remove it with no new arm (the disabled case is divergence 23
  as ever); an `.opacity(0)` handle still captures — **divergence 277**, pinned wrong on purpose.
- **Demo**: `METALUI_APP_SHELL_DEMO=1`'s hidden-title-bar section gains a 40-point handle strip over
  a canvas carrying a simultaneous `DragGesture`, in its own function
  (`appShellDragHandleSectionBody()`, an arm of `DemoStackBudgetTests`'
  `everyProductionTreeBuildsOnAOneMegabyteThread`); the default demo is untouched.
- **Deferred, each named in `WD-A`**: `Scene.windowBackgroundDragBehavior` (a Scene modifier; no
  owner, additive), `.windowDragArea()` (declined), a double click in a handle running the
  title bar's zoom (owner: none until MetalCreator reports it), `onChanged`/`onEnded`/`updating`
  (SwiftUI's `Value` has no members), SDL moving a window from a region (client-side decorations),
  `allowsWindowActivationEvents` (not a drag API).

## §2 Divergences (record §04)

- **275** — a window drag cuts its neighbours: SwiftUI runs `WindowDragGesture` alongside a
  `DragGesture` on its own view or parent; MetalUI ends the others (`onCancelled` runs for one
  that had reported). Narrow, measured only in a synthetic delivery (check WD1 decides; if a real
  drag leaves the neighbour running, the fix is the `simultaneous` placement of the leaf, one arm
  of `act`).
- **276** — a window drag moves a window on AppKit only (SDL records and answers `false`).
- **277** — an `.opacity(0)` handle still captures (MetalUI gates no hitbox on opacity for any
  gesture; `WD-J`, found by the critic: `WD-G` had wrongly called it an existing divergence).

Header: 140 live; 3 added, none retired (the merge's count; 137 + 3).

## §3 Tests

Root target, by file (counted by name; the suite total is §4):

- `Tests/MetalUITests/WindowDragTests.swift` (19): the C8-a reproduction (1.1, passing pin), the
  handle over a gesture viewport (1.2), under and at the slop (1.3, 1.4, 1.4b once-only in the
  arena), a handle inside the viewport cutting a drag that had reported (1.5), a `DragGesture`
  inside the handle and a high-priority ancestor outranking it (1.6, 1.7), a tap on the handle's
  own element (1.8) and a button or long press yielding (1.8b), a sibling viewport never joining
  (1.9), secondary/other presses (1.10), the three gates plus the opacity arm (1.11), a platform
  answering `false` still ending the press (1.12), a fresh arena after a drag (1.13), a standard
  title bar and anywhere in the window (1.14), pointer target not draggable (1.15), attachment
  order inner first (1.16), a high-priority `WindowDragGesture` outranking the viewport (1.17).
  Driven over `FakePlatformWindow` (`WD-K` 2: `MetalUITests` does not depend on `MetalUITesting`).
- `Tests/MetalUITests/AppKitWindowDragTests.swift` (3): `appKitWindowDragActsOnlyDuringTheDraggedEventOfAHeldPress`,
  `appKitForgetsThePressAtTheMouseUpAndOnResignKey`,
  `appKitASecondDownReplacesTheStoredPressAndASecondaryDownIsNotStored`.
- `Tests/MetalUITestingTests/WindowDragHeadlessTests.swift` (2): the headless window records and
  answers its option; `TestWindow` exposes `windowDrags`.
- `Tests/MetalUITests/WindowDragCompileGuards.swift` (1, **new guard 3.2**): a plain importer can
  attach `WindowDragGesture` but cannot give it callbacks or a memberwise `Value`. Guard 3.1 is
  the new row of `AppShellSeamCompileGuards`' window table (a conformer without
  `performWindowDrag` does not compile) and every other guard file's fake gained the one line.
- `Backends/SDL/Tests/MetalUISDLTests/SDLAppShellTests.swift` (1, in the SDL package's own count):
  `sdlPerformWindowDragRecordsAndAnswersFalse`.
- Edited existing: `AppKitAppShellTests.appKitTitleBarPressDragsOnlyDuringAMouseDown` follows the
  rename (one line); `DemoStackBudgetTests` gains the demo section's arm.

## §4 Red runs, mutations, counts

- **Red first.** The skeleton commit (`4ff0788`: the type, the seam, stubs, a leaf never ready)
  reddened 11 tests (19 tests had been written, 20 issues): 1.2, 1.4, 1.5, 1.9, 1.11 arm 4, 1.12,
  1.13, 1.14, 1.16 arm b, 1.17, 2.2; passing pins 1.1, 1.3, 1.6, 1.7, 1.8, 1.10, 1.15, 2.1. Lane 2's
  tests were committed red against a closure-less stub (`054a1bd`, 4.1–4.3, SDL 4.4) before
  `e6fac3f` made them green.
- **Mutations.** The implementer ran about twenty mutations in filtered runs (about 600 tests);
  two of them (M2, M6) found tests 1.4 and 1.8 blind and led to two new tests, **1.4b** (the
  arena-level once-only) and **1.8b** (a button or long press yields), both in `458ae26`. The individual rows of the rest were not carried to this
  record; the spec's §5 table names the intended mutation of every test. The verifiers re-ran, on
  committed sources, restored from a copy, with `git status --short` empty after each:
  - Lane 1 verifier, `Window.swift`'s `beginWindowDrag` arm with the `performWindowDrag()` call
    removed (filtered to the window-drag, handle and headless tests, 31 tests): reddened
    `aTestWindowExposesWindowDrags`,
    `aHandleOverAGestureViewportDragsTheWindowAndCancelsTheViewport`,
    `aMoveOfExactlyTheSlopBeginsOneDragAndNeverASecond`,
    `aHandleInsideTheViewportCutsTheViewportsDragThatHadReported`,
    `aDragStartingOnAButtonOrUnderALongPressInTheHandleStillMovesTheWindow`,
    `aSiblingViewportBeneathTheHandleNeverJoinsTheArena`,
    `allowsHitTestingFalseHiddenAndDisabledEachRemoveTheHandle`,
    `aPlatformAnsweringFalseStillEndsThePress`, `aPressAfterAWindowDragFormsAFreshArena`,
    `aHandleWorksInAStandardTitleBarWindowAndAnywhereInTheWindow`,
    `anAttachmentOrderOfHandleAndDragOnOneElementIsInnerFirst`,
    `aHighPriorityWindowDragGestureOutranksTheViewport` (17 issues).
  - Lane 2 verifier, full unfiltered suite, `AppKitPlatform.swift` `performWindowDrag()` with
    `hostView.forgetHeldPress()` removed (a clear-after-act call not in the implementer's table):
    reddened `appKitASecondDownReplacesTheStoredPressAndASecondaryDownIsNotStored` (2 issues) and
    `appKitWindowDragActsOnlyDuringTheDraggedEventOfAHeldPress` (1 issue).
  - **Not mutated by anyone**: `windowWillClose`'s `forgetHeldPress()` — the close-clears-the-press
    claim has no confirmed reddening test (`AppKitWindowDragTests` 4.2 pins the up and `resignKey`).
    Owner: none; add a pin if the claim is relied on.
- **Counts.** Lane 1 (`458ae26`): **3424 tests**, five issues all the locked screen's
  `AppKitPresentationTests` sheet tests (`CI-AF`). Lane 2 (`6c4d47d`): **3427 tests in 3 suites**,
  the same five, `FR-J no-argument frame: succeeded=true`, 0 `error:`, `swift build --build-tests`
  0 `warning:`; inventory and undocumented checks print nothing. The merged tree is in §6.

## §5 Probes and the pixel comparison

- `docs/probes/swiftui-window-drag.swift`: header carries the recorded 58 lines and how to run it.
- Demo comparison against `a720fba` (lane 2): **0 differing pixels in all fourteen offscreen
  images**, scene identical; no shader changed on either renderer (`TE-AD` not engaged).
  `DemoFrameDeterminismTests`' `Expected.swift` unedited.

## §6 The merged tree (record phase)

See the lines the Record phase appended below (suite line, guards, pixel comparison, SDL and
Linux image) — filled in at the end of this phase.

## §7 Hazards, deferrals, owners

1. **`performDrag(with:)` from a mouse-dragged dispatch** (`WD-D`): documented argument, common
   pattern, **not run** — a synthetic event cannot enter the system tracking loop. Fallback: ready
   at the press (slop 0), losing taps in the handle; the sites are `AppKitWindow.performWindowDrag`
   and the arena's ready condition. Human check **WD1**.
2. **The 5-point slop** is `tapSlop`; WD2 reads whether it is right.
3. **Divergence 275 rests on a synthetic delivery**; WD1 decides.
4. **A handle is an opaque pointer target**: a hover or wheel handler beneath it stops seeing the
   pointer there (as any MetalUI `gesture`, and SwiftUI's overlay, probe `W2`). MetalCreator's
   adoption note must say so, and that a double click in a handle no longer zooms.
5. **SDL moves nothing from a handle** (276); borderless SDL windows are not offered, so no app is
   affected today.
6. **Looks owed, none performed (an agent cannot)**: `docs/verification/human-checks.md` group **WD**
   (WD1–WD7); the screen was locked for both lanes.
