# 91 — Test harness (`MetalUITesting`, `HT-`)

Branch `feat/test-harness` from `70e9389`, merged with master `f2fe54a` (§88
key-focus, §89 SMK gaps and §90 shadow cache are published; **91 was free on
master, so the number stands**). **Not a plan task**: item 8 of the gpui-gap
list (user request 2026-10-02), requested by MetalCreator (`metalui-gaps.md`
M6-e, M7-b, TH-a) and the SMK configurator port (`2026-10-06-metalui-gaps.md`
MG-17, MG-12). Spec `docs/superpowers/specs/2026-10-09-test-harness-design.md`;
rulings `HT-A`…`HT-X` in `docs/superpowers/2026-10-09-test-harness-decisions.md`
(next unused `HT-Y`); probe `docs/probes/swiftui-xcuitest-test-surface.sh`
(`HT-B`, evidence E1). Public guide: `docs/testing.md`.

**Status: LANDED — every agent-doable clause is built; two measurements are
owed to a Windows run and a Linux run with fonts** (`HT-V` items 4 and 5;
`docs/verification/human-checks.md` group HT, §9). Three lanes, sequential
(`HT-P`), each red first and verified `ok: true`; this record is the Record
phase's, and it also fixed the merge with master (`HT-X`).

## §0 Baseline and design

- **Baseline** at `70e9389`: 3069 tests in 3 suites, 0 goldens, 195 typecheck
  guards, 133 live divergences (master's `f2fe54a` has since moved all of them).
- **Evidence before design** (`HT-B`, E1): SwiftUI offers no in-process input
  injection or element query. `ImageRenderer`, `NSHostingView.fittingSize` and
  an in-view `onGeometryChange` run headless (R1–R3); a SwiftUI app tests its
  UI out of process through XCUITest (X1 typechecks, X2 `rightTap()` does not;
  S1 finds no `simulate`, `TestHost`, `inject` or `ViewInspect`). So the
  harness is **MetalUI-only**: its structure is gpui's `TestAppContext` /
  `VisualTestContext` (E2, read, not probed), its action names XCUITest's.
- **Critic round** (`HT-R`, 2026-10-09): the window lookup reads `App.windows`,
  not `Window.liveWindows`; `TestElement` is not `Sendable`; 1.35's literals
  re-derived; lane-2 mutations named; guard 3.4 dropped.

## §1 What landed

A portable library product **`MetalUITesting`** (`HT-A`; the manifest's
portable list; depends on `MetalUI` and `MetalUIScene` only, imports nothing
else), 14 files, 1,856 lines, linked by test targets only:

- **Host** (lane 1): `HeadlessPlatform` / `HeadlessPlatformWindow` /
  `HeadlessWindowRenderer` implement every `Platform`, `PlatformWindow` and
  `WindowRenderer` requirement honestly: recorded requests, simulated events,
  `options` defaulting to AppKit's answers, accessibility activated at open,
  `run()` returns at once (`HT-D`). `TestApp` / `TestWindow` run the **real**
  `App.openWindow` and `Window`. Input by point in XCUITest's names (`click`,
  `doubleClick`, `rightClick`, `typeText`, `typeKey`, `scroll`, `drag`,
  `click(at:forDuration:thenDragTo:)`, `magnify`, `rotate`) with AppKit's key
  routing (`HT-F`); a **simulated clock** (`tick`, `advance(by:)`,
  `advanceFrames`, `runUntilIdle()`; `HT-E`, `HT-S` item 1); resize, scale and
  appearance; close; `frame(ofID:)` / `frames(ofID:)`; `FrameWork` per frame
  (layout work, rasters, atlas uploads; M7-b, `HT-I`).
- **Inspection** (lane 2, extensions in new files): `TestElement` queries over
  the accessibility tree by identifier, label, role and predicate in tree
  pre-order (`HT-G`), `focusedElement`, element-aimed input at the visible
  frame's centre (`.notHittable`), `performAccessibilityAction`, `focus(_:)`;
  presentations read at the seam and answered as a platform does (alerts, file
  dialogs, context menus, the toolbar), on the native and the drawn path
  (`HT-H`, `HT-T`); the menu bar (`TestApp.menuBar`, `performMenuBarItem`) and
  `MenuEvaluation` (an `App.commands` or `.contextMenu` evaluated; `perform`).
- **`MetalUI` additions** (`HT-C`): only `package` read-back hooks in two new
  files, `Sources/MetalUI/TestingHooks.swift` and `TestingMenuHooks.swift`
  (element bounds, per-build work, the menu evaluation), plus `NativeLayoutWork`
  made `package` in `MetalUILayout`. `Window.swift` and `App.swift` are
  **unchanged** by the branch. No public declaration was added to `MetalUI`;
  the product's census rows are class `M` throughout.
- **Proof and docs** (lane 3): three plain-import guards, four migrated tests
  (two by swap), a generated test target in `metalui new`, `docs/testing.md`.
- **The merge** (`HT-X`): `HeadlessPlatform.showsMenuBarNatively` for master's
  defaultless `setMenuBar(_:) -> Bool`.

## §2 Tests and guards, per file

On `70e9389`: 3069 → lane 1 3106 (+37) → lane 2 3136 (+30) → lane 3 3141 (+5).
At the merge, +1 (2.31). Counts on the merge: §12.

| File | Tests | What |
|---|---|---|
| `HarnessWindowTests`, `HarnessClockTests`, `HarnessInputTests`, `HarnessLayoutTests`, `HarnessLifecycleTests`, `HarnessWorkTests`, `XCTestHarnessTests` | lane 1: 1.1–1.38 (37 new; 1.27 green on arrival, which the spec's red column allows) | open and first frame, accessibility at open, failing frames, click/double/right, key routing, drag/long press/pinch, clock, `runUntilIdle`, scheme and scale, element bounds, close/terminate, warm-frame work counters, the XCTest arm |
| `HarnessQueryTests`, `HarnessPresentationTests`, `HarnessMenuTests` | lane 2: 2.1–2.30 (30 new); the merge's 2.31 | label/identifier/role queries, element input, alerts native and drawn, file dialog, menus, toolbar, the menu bar, `MenuEvaluation`, popover in the tree, shared-title ambiguity, the drawn menu bar |
| `MigratedHarnessTests` | 4 moved | 3.5 `aClickInsideTheBoundsRunsTheHandler`, 3.6 `anIfThatInsertsContentRunsItsOnAppearOnce`, 3.7 `aStaleAlertAnswerNeverReachesTheNextAlert`, 3.8 `aMenuActionWithAStaleTokenRunsNothing` (3.7 and 3.8 are swaps, `HT-V` item 1) |
| `TestHarnessCompileGuards` (`MetalUITests`) | 3 guards (`typecheckFile`, plain import, `SA-P`) | 3.1 `anOutsideTestFileCanDriveATestWindowWithAPlainImport`, 3.2 `anOutsideFileCannotReachTheTestingHooks`, 3.3 `anOutsideFileStillCannotConstructAWindow` |
| `ScaffoldTests` | 3.9, 3.10 | `aGeneratedPackageHasATestTargetOverTheHarness`, `metalUITestingIsARefusedName` |

`Tests/MetalUITestingTests` is portable: it runs in the `swift:6.4-noble`
image (67 tests there at `cafc337`, 2.18 and 2.25 green after `HT-U`).

## §3 Lane 1 — host: red, mutations, corrections

Red first (`917b2ea`): 36 of the 37 failed against stubs. Every mutation ran
the full native suite from a copy. The interrupted predecessor's driver ran
the rows on a **locked screen** (each shows the five known
`AppKitPresentationTests` sheet issues of `CI-AF`, the baseline); the verifier
re-ran the three rows the driver spoiled.

| Test | Mutation | Reddened |
|---|---|---|
| 1.1 | renderer `beginFrame` returns `nil` | every drawing test (the log is cut off with no summary line: a crash, counted red because the unmutated suite finishes) |
| 1.2 | activation at open dropped | `anAccessibilityClientActiveAtOpenHasTheTreeInTheFirstFrame` |
| 1.3 | `failsNextFrame` ignored | `aRendererThatFailsAFrameLeavesTheWindowDirtyAndTheNextTickDraws` |
| 1.4 | click sends only `.mouseDown` | six click tests, 1.38 among them |
| 1.5 | leading `.mouseMoved` omitted | `aClickMovesThePointerFirstSoHoverSeesIt` |
| 1.6, 1.7 | second click count 1; right click as `.mouseDown` | `aDoubleClickDeliversClickCountTwo`; `aRightClickNeverRunsOnClick` |
| 1.8+1.9 | `isTextInputActive` always false | `typeTextIntoAFocusedFieldEditsItsBinding`, `aPlainLetterKeymapBindingIsSilentWhileAFieldIsFocused` |
| 1.10, 1.11 | `typeKey` drops modifiers; shift not applied | `typeKeyWithCommandFiresAKeyboardShortcut` + `aShiftedShortcutMatchesAsAppKitDeliversIt`; the latter alone |
| 1.12 | **the spec's spelling has no effect**: removing `scroll.location = scroll.position` reddens nothing, because `ScrollEvent`'s designated initialiser already sets `location = position` (the line matters only to a raw event whose `position` is edited after construction). **Separating arm**: delta y sent as 0 | exactly `scrollMovesAScrollViewsContent` |
| 1.13–1.17 | drag steps collapsed to 1; `advance` not ticking; no hold before the drags; no `.changed` pinch steps; `send` ticks | `aDragDeliversStepsDraggedEventsEachWithAFrame`; `aLongPressRunsOnlyAfterItsDurationUnderAdvance` + `clickForDurationThenDragToHoldsThenDrags`; the latter; `magnifyAndRotateReachTheirGestures`; `aRawSendDrawsNoFrameUntilATick` + two more |
| 1.18+1.19 | `Window.drainLifecycle` returns at once (restored) | about 70 lifecycle and task tests |
| 1.20, 1.21 | `runUntilIdle` without `Task.yield()`; round limit 65 | `aTaskCompletesUnderRunUntilIdle`; `runUntilIdleThrowsNotIdleForAWindowThatRedrawsForever` |
| 1.22–1.24 | init ignores scheme; appearance change skips its handler; preferred scheme unrecorded | `aDarkWindowResolvesItsFirstFrameDark` + `setAppearanceSwitchesTheSchemeLikeTheSystem`; the latter; `aPreferredColorSchemeReachesThePlatformRecord` |
| 1.25–1.29 | bounds not recorded; `frames(ofID:)` first only; `recordsLayout` guard removed; `simulateResize` skips `onResize`; scale answers 1 | four layout tests; `frameOfAnAmbiguousIDThrowsAndFramesOfIDListsBoth`; `aWindowNotRecordingLayoutThrowsNotRecorded`; `resizeReflowsTheRoot`; `scaleFactorTwoDoublesTheScenesDeviceRects` |
| 1.30–1.33 | `close()` fires no `onClose`; close-request answer ignored; `terminate()` uncounted; atlas dirty rect uncleared | `closeRunsEveryOnDisappearOnce` + `theLastWindowsCloseTerminatesTheTestApp`; `aVetoedCloseRequestKeepsTheWindowOpen`; `theLastWindowsCloseTerminatesTheTestApp`; `theSecondUnchangedFrameUploadsNothing` |
| 1.34, 1.35a | accumulator reset per build; not reset at `finishFrame` | `frameWorkSumsEveryBuildOfAFrame`; `aWarmDragLoopCountsLayoutWorkPerFrame` + `anUnchangedPathIsRasterizedOnceAcrossFrames` |
| 1.35b | the hook reads the previous build's `lastNativeLayoutWork`. **Spelled `var previous: NativeLayoutWork? = nil; let work = previous ?? current`**: the spec's `NativeLayoutWork()` does not compile (internal initialiser) | exactly `aWarmDragLoopCountsLayoutWorkPerFrame` |
| 1.36 | the hook reports the previous build's `rasterizedPixels` (the driver's run was spoiled by a kill; re-run) | exactly `anUnchangedPathIsRasterizedOnceAcrossFrames` |
| 1.37 | `App.hasDefaultTextSystem` false on Apple | `theDefaultTextSystemIsCoreTextOnApple` |

Corrections measured on the way (`HT-S`): `runUntilIdle` returns after four
quiet yields (a `.task` continuation and an observation hop each need a
main-actor turn); `sequenced(before:)` does not exist; the gesture arena
stamps a press at the first tick after it; `frame(ofID:)` is the laid-out
rect before any scroll offset or effect; `TestApp.windows` holds its windows
weakly (a `TestApp` / `TestWindow` cycle kept a dirty `Window` alive in
`liveWindows` and made `withAnimation`'s "build pending" answer for later
tests). The interrupted predecessor also left an orphaned mutation driver and
an unreverted 1.36 mutation; the verifier reverted it (the worktree was clean
at `96d5c3f`).

## §4 Lane 2 — inspection: red, fix round, mutations

Red first (`0f48f5d`): stubs and 2.1–2.26. Implementation `c366644`. Its
verifier ran the root package in `swift:6.4-noble`: 63 tests, **3 issues**.
2.25: ⌘C is not copy off macOS. 2.18: a menu-bar action's model write reached
the window only through the observation hop, which is synchronous on macOS
only. The fix round (`HT-U`): red `d978e2b` (2.27 red alone on macOS), fix
`96c443d` (`performMenuBarItem` marks every window dirty before its tick),
2.25 sends the platform's shortcut modifier, three claims gain pins
(2.28–2.30). Verified at `cafc337`: noble `67 + 6 + 35 + 18 + 199 + 67 + 22`
all passed, 0 `warning:`; the native run 3136 tests.

Mutations, each on the full native unfiltered suite with `git status --short`
clean after each restore:

| Mutation | Reddened |
|---|---|
| `setNeedsRedraw` dropped from `performMenuBarItem` (`HT-U` 1) | `aMenuBarCommandDrawsWithNoObservationHop` (2.27) only |
| `standardAction` guard dropped (`HT-T` 3) | `aStandardMenuBarItemIsNotPerformed` (2.28) only |
| `presentedAlert`'s `dismissedPresentations` check dropped | `anAlertTheWindowDismissesIsNoLongerPresented` (2.29) only |
| `respondToAlert(button:)`'s `matches.count == 1` guard dropped | `anAlertButtonTitleTwoButtonsShareIsAmbiguous` (2.30) only |
| **2.23b**: `preOrder` skips the children of a `.popover` | `aPopoverAppearsInTheTreeInsideTheWindow` only |
| 2.23 as first named: the walk visits only `roots.first` | seven other tests (`aClickByElementReRunsLane1sClickTestThroughTheTree`, `aDeclinedAlertIsDrawnAndPressedThroughTheTree`, `aDeclinedToolbarIsDrawnAndItsButtonClickable`, `aDrawnMenuIsDrivenThroughTheTree`, `aMissingAndAnAmbiguousElementThrowNamingTheQuery`, `elementsByRoleAreInTreeOrder`, `tabMovesFocusAndFocusedElementFollows`), **not** 2.23: the popover's node is inside the one root (`HT-U` 3); "only the last root" (2.23c) left it green too |

Corrections (`HT-T`): `element(label:)` matches a static text by its string
(its node's `value`); a presentation getter answers `nil` when the option makes
the window draw it; a standard menu-bar item is not performed (`.noMenuItem`);
a popover is in the tree one tick after the frame that opens it; a `Button`'s
node is its chrome, not its `.frame` wrapper (52 × 24 centred in 80 × 30);
`performAccessibilityAction` takes an `AccessibilityActions` set.

## §5 Lane 3 — proof and docs: mutations

Red first (`4b3be3a`). Each row was mutated once on `6d3da45` from a copy, a
full native unfiltered run of 3141 tests, `git status --short` empty after
each (`HT-W`); the verifier re-ran them all at `e2e5ada` with the same results.

| Row | Mutation | Reddened |
|---|---|---|
| 3.1 | `click(_ element:modifierFlags:)` made `internal` **plus** the twelve `MetalUITestingTests` files switched to `@testable import` for the run (without the companion edit the build fails before the guard runs) | exactly `anOutsideTestFileCanDriveATestWindowWithAPlainImport` |
| 3.2 | `testingElementBounds` made `public` | exactly `anOutsideFileCannotReachTheTestingHooks` |
| 3.3 | `Window.init(platformWindow:…)` made `public` | exactly `anOutsideFileStillCannotConstructAWindow` |
| 3.5 | `runClick` called twice in `Window.dispatchClick` (the original named none) | 113 tests, the moved `aClickInsideTheBoundsRunsTheHandler` among them |
| 3.6 | `if let old = previous[key] ?? returned[key]` → `returned[key]` in `LifecycleStore.endFrame`. **The spelling measured**: equivalent for keys not returning from a ghost, and still red | 41 tests, the moved `anIfThatInsertsContentRunsItsOnAppearOnce` among them |
| 3.7 | `token == result.token` dropped in `handleAlertResult` | exactly `aStaleAlertAnswerNeverReachesTheNextAlert` |
| 3.8 | `session.token == outcome.menu` dropped | exactly `aMenuActionWithAStaleTokenRunsNothing` |
| 3.9a | the `Tests/<Name>Tests/<Name>Tests.swift` entry dropped | `aGeneratedPackageHasATestTargetOverTheHarness`, `theDefaultPackageIsMacOSOnlyAndDependsOnTheRepositoryByGitURL` |
| 3.9b | `testSource` never escapes a keyword | `aGeneratedPackageHasATestTargetOverTheHarness` (that run also read the five locked-screen sheet issues: environment, not the mutation) |
| 3.10a | the `metalui` prefix refusal made `guard true` | `metalUITestingIsARefusedName`, `aNameThatIsNotAModuleNameIsRefusedWithItsReason` |
| 3.10b | the `"Testing"` entry removed from `clashingModuleNames` | exactly `metalUITestingIsARefusedName` |

Two runs paired mutations the reddened tests separate (3.2 + 3.3; 3.9b +
3.10b). **The doc comment of the moved 3.5 named a different mutation from the
measured one** (the verifier's finding); it now reads "`Window.dispatchClick`
calls `runClick` twice".

Corrections (`HT-V`): two of the four migrations are swaps; **`Testing` joins
the refused names** (a generated package passes `swift build` and fails
`swift build --build-tests` with `unknown attribute 'Test'`, measured twice),
while `XCTest` is **not** refused (its first failure was an instrument fault: a
`Testing` module left in the shared build directory); a keyword app name is
imported in backticks (`class`, `func`, `Self` built and passed); the generated
test target is declared on every platform.

## §6 Probes

`docs/probes/swiftui-xcuitest-test-surface.sh` (arms X1/X2, S0/S1, R1–R3;
output in its header). No other probe: every other claim is MetalUI's own and
is pinned by a test.

## §7 Hazards and decisions worth the next reader's time

- **A harness action draws one frame; `tick` draws the next** (`HT-E`). The
  observation hop is asynchronous off macOS, so a test's model is a plain class
  plus `setNeedsRedraw()`, or `@Observable` and `runUntilIdle()`; a menu-bar
  action runs outside window input and marks every window dirty itself
  (`HT-U` 1).
- **`TestApp.windows` is weak and get-only** (`HT-S` 10); a `TestWindow` keeps
  its app.
- **A new `PlatformWindow`/`Platform`/`WindowRenderer` requirement owes
  `HeadlessPlatform*` an honest implementation in the change that adds it.**
  The merge proved it: master's `setMenuBar(_:) -> Bool` stopped the root
  package compiling until `HeadlessPlatform` answered (`HT-X` 1). CLAUDE.md's
  "defaultless requirements" paragraph now names three conformers.
- **Pixels are not offered** (`HT-L`): the headless renderer records the scene
  and its counters; a pixel test stays on `Tests/MetalUITests/Fakes.swift`'s
  `FakePlatformWindow`.
- **The generated test target and `SG-D`**: master's rule (portable-text
  products unconditional) holds for the test target too (`HT-X` 2).

## §8 Deferrals and owed measurements

| Item | Owner |
|---|---|
| Whether a testable executable imports on **Windows** (`HT-V` 4: the UTM VM was stopped); fallback `HT-O`: declare the test target off Windows | the first Windows run of a generated package (human-checks `HT1`) |
| The cross-platform generated test's Linux arm (`SystemFonts.resolver()`): the Linux image installs no fonts (`HT-V` 5) | a Linux consumer run with fonts (`HT2`) |
| Pixels; `GPUSurface` draws; shaping counters; virtual `Task.sleep`; IME helper; multi-window key switching (`HT-Q` 1–6) | none (reasons in `HT-Q`) |
| An in-window menu bar (`HT-Q` 7) | **discharged** by C12 and `HT-X` 1 |
| A scrolled `frame(ofID:)` (`HT-S` 4) | none |

## §9 Demo comparison

`docs/probes/demo-pixels/compare.sh <scratch> 70e9389 <head>`: all fourteen
images `differing=0`, identical scenes (lane 1 at `96d5c3f`, lane 3 at
`e2e5ada`); the merge's own comparison is in §12. `DemoFrameDeterminismTests`'
`Expected.swift` is unedited.

## §10 Divergences, looks

No divergence: SwiftUI has no in-process harness to differ from (`HT-B`), and
every declaration is class `M`. Nothing paints. Looks owed: the two
unmeasured platforms of §8, as human-checks group **HT** (`HT1`, `HT2`);
record §03 carries the same note.

## §11 Docs changed

`CLAUDE.md` / `AGENTS.md` (one paragraph; the `HT-` prefix; the record map; the
counts bullet), `docs/api-overview.md` (a Testing section), `docs/migration.md`
(a row), `docs/getting-started.md`, `docs/testing.md` (new),
`docs/verification/human-checks.md` (group HT), `docs/record/README.md`,
`docs/record/03-verified-on-real-hardware.md`, `README.md`,
`docs/probes/closeout-inventory-map.tsv` and `closeout-public-api.tsv`.

## §12 Closing measurements (the merge, 2026-10-10)

@@CLOSING@@
