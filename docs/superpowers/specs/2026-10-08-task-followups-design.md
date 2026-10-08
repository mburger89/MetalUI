# `.task` follow-ups — design

Item C4f of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**): the three minor findings `PX-V` logged after `.task` landed
(`docs/superpowers/2026-10-07-portable-app-decisions.md`, record §80).
Branch `fix/task-followups` from `70ed000`. Rulings:
[`../2026-10-08-task-followups-decisions.md`](../2026-10-08-task-followups-decisions.md)
(`TF-A`…`TF-D`). Record: `docs/record/84-task-followups.md` (Record phase).

## 1. Scope

| # | Finding (`PX-V`) | Answer | Ruling |
|---|---|---|---|
| 1 | A `.task(id:)` re-inserted from a removal ghost with a changed id keeps its old task | **Fixed** to SwiftUI's probed answer; the same fix gives `onChange(of:)` its baseline back across the ghost; a value read from the content's own (reset) `@State` now compares as changed on return (divergence 123 amended) | `TF-A`, `TF-D` |
| 2 | Test 1.7's warning filter cannot fail | **Fixed**: every `warning:` line refused; two mutations redden it in the Linux image | `TF-B` |
| 3 | No CI job runs `.task` under SDL | **Fixed**: an offscreen-rendered `SDLPlatform` window (an SPI `Checks` option, `TF-E`) runs the real loop in the image; new ungated test 3.20b | `TF-C` |

No public API is added or changed. No new divergence (the reserved labels
160–164 stay unused). No `PlatformWindow`/`Platform`/`WindowRenderer`
requirement. No shader, renderer or pixel change; no demo change.

## 2. SwiftUI's answers (probed)

`docs/probes/swiftui-task-ghost-id.swift`, arms `Y0`…`Y4`, recorded in its
header (macOS 27.0.1, Swift 6.4, run three times, byte-identical): a
re-insertion from a live removal ghost with a **changed** `task(id:)` value
cancels the old task, starts the new one and fires `onChange` old→new, in the
re-insertion's update (`Y1`; `Y2` with the id written while a ghost) — the
same lines and order as a plain id change (`Y3`, control). Unchanged id: nothing
(`Y0`, control, `X17`'s reading). No transition: a new appearance (`Y4`).

Items 2 and 3 have no SwiftUI facet. Item 2's SwiftPM fact is measured by
`docs/probes/swiftpm-remote-dependency-warnings.sh` (a URL dependency's source
warnings are suppressed; a local one's and the root's print).

## 3. Design

### 3.1 Item 1 (`TF-A`) — `Sources/MetalUI/Lifecycle.swift` only

- `LifecycleStore.ParkedGhost.running: [Key: RunningTask]` →
  `departed: [Key: Entry]` — the full last-build entry of each key parked on
  the ghost (`disappearances` carries the entry instead of only `running`).
- In `endFrame`'s parked loop, a key whose `current[key] != nil` moves its
  departed entry into a local `returned: [Key: Entry]` (and stays in
  `cancelled`, as today). The line `current[key]?.running = box` goes: the walk
  carries the box through the old entry, as for any present key.
- The walk's first branch reads `if let old = previous[key] ?? returned[key]`.
  No other branch changes. Consequences, each the `previous` branch's existing
  behaviour: id differs → change-bucket event `cancel` then `start` (`X5`);
  id equal or no id → box carried, nothing runs (`X17`); `onChange` value
  differs → change-bucket event old→new; scope no longer a task → cancel.
  `T4` (no `onAppear`, no `initial: true` firing on a return) holds because a
  returning key never reaches the appearance branch.
- `runningTaskCount` reads `departed.values.compactMap(\.running)` where it
  read `running.values`. `closeAll` is **unchanged**: it never read the
  parked boxes — a parked task's cancel is already its parked event
  (`entry.onDisappear ?? cancelEvent(running)`), which `closeAll` runs; adding
  the boxes would cancel twice (corrected at critique, `TF-D` item 3).
- Doc comments: `ParkedGhost`, `Entry.running` ("from a parked ghost when the
  key returns") and `endFrame`'s summary name `TF-A`.
- `docs/divergences.md` row 123: the MetalUI column replaces "and its next
  `onChange` compares against nothing (the entry was dropped at the removal
  build)" with "so a `task(id:)` or `onChange(of:)` value read from that
  `@State` compares the fresh value against the one it left with (a restart
  or a firing SwiftUI does not make); a value from outside the content
  compares as SwiftUI's does (`TF-A`)"; the rulings column adds `TF-A`,
  `TF-D`; the pin column adds TF1.4. (Record §04's dated line: Record
  phase.)

### 3.2 Item 2 (`TF-B`) — `Tests/MetalUIScaffoldTests/ScaffoldTests.swift` only

`aCrossPlatformPackageBuildsItsSDLAppByURL`'s filter becomes
`output.split(separator: "\n").filter { $0.contains("warning:") }`, expected
empty; its doc comment states what a URL consumer can and cannot show
(`TF-B` items 1–2) and names MT2.1/MT2.2. 1.8 is unchanged.

### 3.3 Item 3 (`TF-C`) — `Backends/SDL` only

- `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`: `@_spi(Checks) public init(hiddenWindows:
  Bool = false, offscreenRenderers: Bool) throws`; the public
  `init(hiddenWindows:)` forwards `offscreenRenderers: false`. A stored
  `offscreenRenderers` is passed by `openSDLWindow` to `SDLWindow.init(handle:
  offscreenSize:)` (`nil` = today's swapchain claim). With a size, the window's
  renderer is `SDLWindowRenderer(offscreenWidth:height:)` at the window's pixel
  size (scale 1, as `offscreenScaleFactor` already reports). The `#if !SDL`
  stub is untouched. (Amended by `TF-E`: the design's `package init` cannot be
  reached from `MainQueueDrainCheck`, which is in the `Backends/SDL` package, not
  the root package that declares `MetalUISDL`; the public initialiser becomes a
  `convenience` forwarder, and the check imports `@_spi(Checks) import MetalUISDL`.)
- `Backends/SDL/Sources/MainQueueDrainCheck/main.swift`: the platform is
  created with `offscreenRenderers: mode == "task-modifier-offscreen"`; the
  `task-modifier` case also matches `task-modifier-offscreen`; the header
  comment documents the mode.
- `Backends/SDL/Tests/MetalUISDLTests/SDLMainQueueDrainTests.swift`: test
  3.20b (below), ungated. 3.20 keeps its gate.

## 4. Lanes

**One lane** (`model: opus`), files: `Sources/MetalUI/Lifecycle.swift`,
`Tests/MetalUITests/TaskModifierTests.swift`, `docs/divergences.md` (row 123),
`Tests/MetalUIScaffoldTests/ScaffoldTests.swift`,
`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`,
`Backends/SDL/Sources/MainQueueDrainCheck/main.swift`,
`Backends/SDL/Tests/MetalUISDLTests/SDLMainQueueDrainTests.swift`, the TF-
decisions doc (amendments). Off every file of `feat/input-apis` (§81),
`feat/variable-height-list` (§82), `feat/rich-text` (§83); if `SDLPlatform.swift`
conflicts at merge, the change is two lines in the initialiser and one in
`openSDLWindow`.

Order: item 1 (red-first, macOS), item 3 (red-first in the image), item 2
(image only). Commit each test red before its fix.

## 5. Tests

Every test below states its red-before and the mutation that must redden it.
Mutations: commit first, restore from a copy, full unfiltered suite
(`swift test --build-system native --no-parallel`) — or, for `Backends/SDL`
and the image, that package's full run — `git status --short` after each,
every reddened test named.

### 5.1 Item 1 — `Tests/MetalUITests/TaskModifierTests.swift`, new `// MARK: - Ghost return with a changed id (TF-A)`

Harness: `taskTransitionWindow`, `lcLeaf`, `LCModel.shown/key`, `LCLog`,
`untilCancelled`, `simulateTick` — 3.13's shape (removal under
`withAnimation(.linear(duration: 0.6))` at 101, re-insertion at 101.15, ticks
to 103). No sleeps.

- **TF1.0 `aTaskIDReinsertedUnchangedFromAGhostRestartsNothing`** (`Y0`):
  `lcLeaf(50, 30).task(id: m.key) {…}.onChange(of: m.key) {…}.transition(.opacity)`,
  re-inserted with the key unchanged → log `[]`, `runningTaskCount == 1`,
  `parkedCount == 0`. Green before (the control). Mutation **MT1.0**: at the
  return, compare against a departed entry whose id is never equal
  (`isEqual` → `false`) → reddens TF1.0 (a restart).
- **TF1.1 `aTaskReinsertedFromAGhostWithAChangedIDRestarts`** (`Y1`): the
  re-insertion's transaction also writes `m.key = 1` → at the 101.15 tick the
  log is `["cancel 0", "start 1"]`; then no more lines through 103;
  `runningTaskCount == 1`; a later plain removal (`m.shown = false`, tick 104)
  logs `["cancel 1"]`. **Red before** at `70ed000`: the log stays `[]` (the
  old task keeps running). Mutation **MT1.1**: drop the `returned` fallback
  (`previous[key]` alone) → reddens TF1.1, TF1.2, TF1.3; 3.13
  (`aTaskReinsertedMidRemovalKeepsRunning`) must also redden under it (the box
  is no longer carried: `runningTaskCount == 0` and no cancel at the later
  removal), which proves the carry now runs through the departed entry.
- **TF1.2 `anIDWrittenWhileAGhostRestartsTheTaskOnReturn`** (`Y2`): `m.key = 1`
  written at 101.05 (ghost alive, tick at 101.1: log still `[]`), then
  `m.shown = true` under animation → `["cancel 0", "start 1"]`. Red before:
  `[]`. Mutation: MT1.1.
- **TF1.3 `anOnChangeReinsertedFromAGhostWithAChangedValueFiresAfterTheRestart`**
  (`Y1`, order): the probe's subject — `.task(id: k)` inner, `.onChange(of: k)`
  outer — re-inserted with `k = 1` → exactly
  `["cancel 0", "start 1", "change 0->1"]` (reverse registration order in
  the change bucket, `Y1`'s lines). Red before: `[]`. The test also holds a
  second leaf under the same ghost with only `.onChange(of: k)`, whose line
  `"change2 0->1"` must appear (first: it is registered later, so it runs
  earlier in reverse order — the exact expected list is derived from the
  registration order before the run and written as a literal). Mutation
  **MT1.3**: park only departed entries that hold a running box → **both**
  `onChange` lines are missing (each modifier is its own key — scope id plus
  occurrence — so the subject leaf's `onChange` holds no box either; the
  second leaf is the case with no task anywhere in its content, not the only
  one MT1.3 reaches); reddens TF1.3 only.
- **TF1.4 `aTaskIDReadFromTheContentsOwnStateRestartsOnReturnFromAGhost`**
  (`TF-D`, divergence 123 as amended): a `Component` holding `@State var n:
  Float = 0` whose body is `lcLeaf(50, 30).task(id: n) { log "start <n>"; await
  untilCancelled { log "cancel <n>" } }`, `n` written to 1 from input before
  the removal (log `["start 0", "cancel 0", "start 1"]` taken as set-up), then
  removed under the 0.6 s animation and re-inserted at 101.15 with **no**
  write: `@State` is fresh (`ID-C`), so the log is exactly `["cancel 1",
  "start 0"]` and `runningTaskCount == 1`. SwiftUI would log nothing (`T4`
  keeps the state, so the id is unchanged — `Y0`'s reading). **Red before** at
  `70ed000`: `[]` (the stale task for id 1 keeps running while the content
  shows `n == 0`). Mutation: MT1.1 reddens it.

Must stay green unedited: 3.12, 3.13, 3.22, 6.4
(`reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState`, the
divergence-123 pin), every `LifecycleTests` transition test,
`taskScopesCostWhatLifecycleScopesCost` (work counts unchanged),
`theSevenRetentionSlotsAreMutuallyDistinct`.

### 5.2 Item 2 — `Tests/MetalUIScaffoldTests/ScaffoldTests.swift` (Linux image only)

Run: from `/` in the image (`PX-` record §80 §5's worktree hazard),
`METALUI_RUN_SDL_CONSUMER_BUILD_TEST=1 swift test --filter aCrossPlatformPackage
--scratch-path /tmp/root` (CI's line, `sdl-gpu-linux.yml`), with the
worktree mounted and the `metalui-sdl-build-task-followups` volume or a
branch-named scratch volume — never another workflow's.

- **1.7 `aCrossPlatformPackageBuildsItsSDLAppByURL`**, filter changed (§3.2).
  **Red before (the defect, shown)**: under MT2.1 the **unchanged** test is
  green. Mutations, each against the new filter: **MT2.1** add
  `pkgConfig: "accesskit"` to `CAccessKit` in the root `Package.swift` →
  reddens 1.7 (record the warning line); **MT2.2** append
  `func starterWarning() { let unused = 1 }` to the scaffold's generated
  `main.swift` text → reddens 1.7 (and must not redden a macOS scaffold test
  — record if one compares the text byte-for-byte, then that test is named
  too). Measurement **MT2.3** (recorded only): `func w() { let unused = 1 }`
  in `Sources/MetalUI` → 1.7 stays green, confirming `TF-B` item 1 in the
  image.

### 5.3 Item 3 — `Backends/SDL/Tests/MetalUISDLTests/SDLMainQueueDrainTests.swift`

- **3.20b `aTaskModifierProgressesAndIsCancelledUnderSDLWithoutAPresentedFrame`**,
  ungated: `runDrainCheck("task-modifier-offscreen")` contains `task
  started=true steps=3 cancelled=true`. **Red before**, in the image: the
  mode first lands with `offscreenRenderers: false` (the swapchain path) and
  prints `task started=false steps=0 cancelled=false` — the separating arm;
  then flipped. Mutations: **MT3.1** delete the disappearance cancel in
  `LifecycleStore` (M3.20's site) → `cancelled=false`, reddens 3.20b in the
  image and on macOS; **MT3.2** `SDLPlatform` ignores `offscreenRenderers`
  → reddens 3.20b in the image (macOS result recorded: a hidden window may
  present there); **MT3.3** delete `drainMainQueue()`'s calls in
  `SDLPlatform.run` → `steps=0` in the image (M3.21's site; macOS recorded).
  Every new SDL test helper creating an `SDLPlatform` arms
  `armMainRunLoopExitCheck()` — 3.20b creates none in the test process (the
  check executable does, and must not arm it, per its header).

Expected counts: root 2672 + 5 = **2677 tests**, 175 guards (unchanged), census
2536 (unchanged: no public declaration). `Backends/SDL` macOS 24 + 84, Linux
image 24 + 81 (3.20b runs; 3.20 still skipped there). Re-measured, never
assumed.

## 6. Verification

- Root: `swift build --build-system native --build-tests`; `swift test
  --build-system native --no-parallel` unfiltered: one summary line, 2677 in 3
  suites; `FR-J no-argument frame: succeeded=`; 0 `error:`, the only
  `warning:` SwiftPM's deprecation notice; `swift build --build-tests` 0
  warnings.
- `Backends/SDL` on macOS (`swift test $(python3 scripts/fetch-accesskit.py
  --print-flags)`) and in CI's Linux image (`docker build -t metalui-portable
  -f Backends/SDL/linux/Dockerfile Backends/SDL`; the run line of the task
  brief with volume `metalui-sdl-build-task-followups`), 0 warnings both.
- Root in a `swift:6.4-noble` container builds; `MetalUILayout`/`MetalUIScene`
  imports unchanged; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green.
- Pixels: `docs/probes/demo-pixels/compare.sh <scratch> 70ed000 HEAD` — 0 px in
  all fourteen images; `DemoFrameDeterminismTests` `Expected.swift` unedited.
- `zsh docs/probes/closeout-inventory-check.sh` and
  `closeout-undocumented.sh` print nothing (no public declaration added).

## 7. Demo and human checks

No demo change (the behaviour needs a removal transition reversed mid-way with
an id change; no section shows `.task(id:)` that way). **No human-check
additions**: nothing here is a look, and the SDL path is pinned headless.

## 8. Deferred (named, with reason and owner)

- **Un-gating `SDLLifecycleTests` 10.2/10.3 in the image** through the same
  `offscreenRenderers` option: same mechanism, not this item. Owner: a
  follow-up on the SDL test lane; cost ~two test edits.
- **A ghost that ends before the key returns** is unchanged: the departed
  entry is dropped with the ghost and a later insertion is a new appearance —
  `Y4`'s reading, already MetalUI's.
- **`@State` across a ghost** (the rest of divergence 123): untouched; it is
  `ID-C`'s rule, not this item's.
