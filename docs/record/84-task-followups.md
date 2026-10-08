# 84 — `.task` follow-ups: a ghost return compares its id, test 1.7 can fail, `.task` under SDL in CI (implementation lane)

Branch `fix/task-followups` from `70ed000` (master: portable app merged, PR
#51). **Not a plan task**: item C4f of the gpui-gap priority list (user
request 2026-10-02) — the three minor findings `PX-V` logged after `.task`
landed (record §80). Spec `docs/superpowers/specs/2026-10-08-task-followups-design.md`;
rulings `TF-A`…`TF-E` in `docs/superpowers/2026-10-08-task-followups-decisions.md`
(next unused `TF-F`); probes `docs/probes/swiftui-task-ghost-id.swift`
(`Y0`…`Y4`) and `docs/probes/swiftpm-remote-dependency-warnings.sh`
(`LOCAL`/`URL`/`URL-OWN`). Parallel branches at the time: `feat/input-apis`
(§81), `feat/variable-height-list` (§82), `feat/rich-text` (§83).

**Status: implementation lane complete (2026-10-08)**; the Record phase (CLAUDE.md
rule, record §04 dated line for divergence 123, README row) follows.

## 0. Baseline

`70ed000`, native build, unfiltered `--no-parallel`: **2672 tests in 3 suites**
(record §80 §5). `Backends/SDL` 24 + 83 on macOS, 24 + 80 in CI's Linux image.

## 1. Item 1 — a key returning from a removal ghost (`TF-A`, `TF-D`)

**Red** (`0321f5d`, tests in `Tests/MetalUITests/TaskModifierTests.swift`,
`// MARK: - Ghost return with a changed id (TF-A)`), at `70ed000`'s source:

| Test | Failure line |
|---|---|
| TF1.0 `aTaskIDReinsertedUnchangedFromAGhostRestartsNothing` | green (the control, `Y0`) |
| TF1.1 `aTaskReinsertedFromAGhostWithAChangedIDRestarts` | `:641` `log.take() → []` (expected `["cancel 0", "start 1"]`); `:647` later removal `["cancel 0"]` (expected `["cancel 1"]`) |
| TF1.2 `anIDWrittenWhileAGhostRestartsTheTaskOnReturn` | `:675` `log.take() → []` |
| TF1.3 `anOnChangeReinsertedFromAGhostWithAChangedValueFiresAfterTheRestart` | `:710` `log.take() → []` (expected `["change2 0->1", "cancel 0", "start 1", "change 0->1"]`) |
| TF1.4 `aTaskIDReadFromTheContentsOwnStateRestartsOnReturnFromAGhost` | `:752` `log.entries → []` (expected `["cancel 1", "start 0"]`) |

TF1.4's `@State` is written by the content's own `onAppear` (under
`StateDispatch`, as input is), not a synthesized click.

**Fix** (`3ccaafa`, `Sources/MetalUI/Lifecycle.swift` only):
`ParkedGhost.running: [Key: RunningTask]` → `departed: [Key: Entry]`; the
parked loop moves a returning key's entry into a per-build `returned` map; the
walk reads `previous[key] ?? returned[key]`; `runningTaskCount` reads
`departed.values.compactMap(\.running)`; `closeAll` unchanged (`TF-D` item 3).
`docs/divergences.md` row 123 amended (MetalUI column, rulings `TF-A`/`TF-D`,
second pin TF1.4); no new label (160–164 unused).

**Mutations** (each on `3ccaafa`'s `Lifecycle.swift`, restored from a copy,
full unfiltered native suite, `git status --short` clean of source after):

- **MT1.1** — `if let old = previous[key] ?? returned[key]` → `previous[key]`:
  2677 tests, 11 issues — `aTaskReinsertedMidRemovalKeepsRunning` (3.13:
  `["start"]` then `["start", "cancel"]` — a second start one build later, the
  carry now runs through the departed entry), TF1.0 (`["start 0"]`), TF1.1,
  TF1.2, TF1.3, TF1.4 (`["start 0"]`). The spec did not predict TF1.0: without
  the fallback the returning key's box is lost and the next build restarts it.
- **MT1.0** — the task-id comparison `!isEqual(before)` →
  `!(previous[key] != nil && isEqual(before))` (a departed entry's id never
  equal): 1 issue — TF1.0, `["cancel 0", "start 0"]`.
- **MT1.3** — park a departed entry only when it holds a running box: 1 issue —
  TF1.3, `["cancel 0", "start 1"]` (both `onChange` lines gone, `TF-D` item 2's
  corrected reading).

## 2. Item 3 — `.task` under SDL in CI's Linux image (`TF-C`, `TF-E`)

**Design correction, measured** (`TF-E`): the spec's `package init` does not
compile at its caller — `MainQueueDrainCheck` is in the `Backends/SDL` package,
`MetalUISDL` in the root package (`main.swift:94:73: error: extra argument
'offscreenRenderers' in call`, macOS and image); and a class's designated
initialiser cannot delegate (`SDLPlatform.swift:33:12`). Taken:
`@_spi(Checks) public init(hiddenWindows:offscreenRenderers:)`, the public
`init(hiddenWindows:)` a `convenience` forwarder, `@_spi(Checks) import
MetalUISDL` in the check. `Backends/SDL/Sources` is outside the census.

**Red** (`6ae6ace`: the mode and 3.20b over the swapchain path,
`offscreenRenderers: false`), in CI's Linux image (`metalui-portable`, rebuilt,
volume `metalui-sdl-build-task-followups`): 24 + 81, 1 issue —
`aTaskModifierProgressesAndIsCancelledUnderSDLWithoutAPresentedFrame` at
`SDLMainQueueDrainTests.swift:129`, output `task started=false steps=0
cancelled=false iterations=200000`. macOS: 24 + 84 green (a hidden window
presents there).

**Fix** (`ff1880d`): the check passes `offscreenRenderers: mode ==
"task-modifier-offscreen"`. Image 24 + 81 green, `task started=true steps=3
cancelled=true iterations=13`; macOS 24 + 84 green.

**Mutations** (each restored from git, both runs):

| Mutation | Image | macOS |
|---|---|---|
| **MT3.1** — the disappearance cancel in `LifecycleStore.endFrame` (`?? entry.running.map { cancelEvent }` → `?? nil`) | 3.20b red: `started=true steps=3 cancelled=false iterations=200000` | 3.20 and 3.20b red, same line |
| **MT3.2** — `openSDLWindow` passes `offscreen: false` | 3.20b red: `started=false steps=0 cancelled=false` | green (recorded: the swapchain presents) |
| **MT3.3** — both `drainMainQueue()` calls in `SDLPlatform.run` commented out | 3.20b red (`started=true steps=0 cancelled=false`), and 1.18 `theSDLLoopRunsAMainActorTaskStartedFromTopLevelCode`, 1.19 `aDialogAnsweredOnAnotherThreadResumesAnAwaitingTask`, 3.21 `anImmediateMainActorTaskResumesAndSeesItsCancellationUnderTheSDLLoop` | green (recorded: macOS's run loop drains the main queue, `SV-H`) |

## 3. Item 2 — test 1.7 refuses every `warning:` line (`TF-B`)

`4f72608`. Run in CI's Linux image, `METALUI_RUN_SDL_CONSUMER_BUILD_TEST=1
swift test --filter aCrossPlatformPackageBuildsItsSDLAppByURL --scratch-path
/tmp/root`, each arm on its own copy of the tree (no `.git`, no `.build`) so
the five ran without touching the worktree:

| Arm | 1.7 |
|---|---|
| **A** — old filter, MT2.1 (`pkgConfig: "accesskit"` on `CAccessKit`) | **green** — the defect shown (SwiftPM printed `warning: 'work': couldn't find pc file for accesskit` and the consumer's `warning: 'metalui': …`; neither names the repository path) |
| **B** — new filter, MT2.1 | red, `ScaffoldTests.swift:671`: `["warning: 'metalui': couldn't find pc file for accesskit"]` |
| **C** — new filter, unmutated | green |
| **D** — new filter, MT2.2 (`func starterWarning() { let unused = 1 }` in the starter's `main.swift` text) | red: `…/Consumer/Sources/Consumer/main.swift:25:29: warning: initialization of immutable value 'unused' was never used…` |
| **E** — new filter, MT2.3 (`func w() { let unused = 1 }` in `Sources/MetalUI/Lifecycle.swift`) | green — the root build printed the warning twice, the URL consumer none (`TF-B` item 1 confirmed in the image) |

MT2.2 on macOS (full unfiltered suite): 2677 green — no macOS scaffold test
compares the starter's text byte-for-byte (they use `contains`).

## 4. Verification (at `4f72608`)

- Root, native, unfiltered `--no-parallel`: **2677 tests in 3 suites** passed
  (2672 + TF1.0–TF1.4); `FR-J no-argument frame: succeeded=true`; 0 `error:`;
  the only `warning:` SwiftPM's deprecation notice. `swift build --build-tests`
  (default build system): 0 warnings. Guards 175 (unchanged; no guard added).
- Pixels: `docs/probes/demo-pixels/compare.sh <scratch> 70ed000 HEAD` —
  controls as recorded, **0 px and scene identical in all fourteen images**.
  `DemoFrameDeterminismTests`' `Expected.swift` unedited.
- `Backends/SDL`: macOS 24 + 84, image 24 + 81 (3.20b runs; 3.20 still gated).
  Warnings in both are pre-existing and in files this branch does not touch:
  `AccessKitControlsParityTests.swift:83` (`no calls to throwing functions occur
  within 'try'`, both) and macOS's `ld: warning: building for macOS-14.0, but
  linking with dylib … libSDL3.0.dylib … built for newer version 27.0`.
- Root in `swift:6.4-noble`: §5.
- `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing;
  census unchanged (no public declaration in root `Sources/`).
- Import rules unchanged (`Lifecycle.swift`'s imports untouched; no
  `MetalUILayout`/`MetalUIScene` edit).

## 5. Linux root container

`swift:6.4-noble`, volume `metalui-root-build-task-followups`, `swift build
--build-tests && swift test --skip-build`: 6 + 35 + 18 + 199 + 49 + 22 passed
(record §80's line, unmoved: the new tests are AppKit-window tests), 0
warnings; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green there and
in the macOS suite.

## 6. Deferred

As spec §8: un-gating `SDLLifecycleTests` 10.2/10.3 through the same option
(owner: the SDL test lane); a ghost that ends before the key returns (`Y4`,
already MetalUI's); `@State` across a ghost (divergence 123's root, `ID-C`).
