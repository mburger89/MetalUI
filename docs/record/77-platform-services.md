# 77 — Platform services: dialogs, alerts, window sizing, hover (lanes 1 and 2 landed; lane 3 not built)

Branch `feat/platform-services` from `c2b8f48` (master: lifecycle merged, PR
#46). **Not a plan task**: user request 2026-10-02, an item of the gpui-gap
priority list — the SMK keyboard configurator port's gaps 4, 5, 7, 8, 9, 10 and
12. Spec `docs/superpowers/specs/2026-10-04-platform-services-design.md`;
rulings `SV-A`…`SV-AI` in the new decisions doc
`docs/superpowers/2026-10-04-platform-services-decisions.md` (next unused
`SV-AJ`); probes `docs/probes/swiftui-platform-services.swift` (arms `D`
importer, `X` exporter, `A`/`C1` alerts and the confirmation dialog, `H` hover
— **a recorded broken instrument** —, `V` `Divider`, `P` the menu picker),
`swiftui-window-sizing.swift` (`W0`–`W5`), `swift-main-queue-drain-nested.swift`
(`J0`–`J3`) and `swiftui-alert-presenting.swift` (`R0`–`R4`, `K0`–`K3`).

**Numbering.** Master had published no record past §76 at the Record phase
(`git fetch`: `origin/master` still `c2b8f48`), so §77 stands.

**Status: PARTIAL — lanes 1 and 2 are built; lane 3 was never run.** Read this
before relying on anything below. What the three lanes were to build is
`SV-AC`; what exists is the first two:

| Lane | Owns | State |
|---|---|---|
| 1 — seam + window sizing | the four defaultless platform requirements, three `InputEvent` cases, two accessibility roles, AppKit panels/sheets, SDL dialogs, the SDL main-queue drain, `minSize`/`maxSize`/`WindowResizability` | **landed**, verified `ok: true` (re-verified at `3aa9898`) |
| 2 — presentations + hover | `PresentationScope`, `.fileImporter`/`.fileExporter`, `FileDialogs`, `.alert`/`.confirmationDialog` and their resolver, the drawn alert's **model only**, `onHover`/`onContinuousHover` | **landed**; **no verifier verdict was delivered** (the orchestration's lane-2 verdict is `null`); this record's §3 suite re-run and SV-AI's guard mutations are the only evidence beyond the lane's own red runs |
| 3 — drawn alert, `Divider` view, menu `Picker`, scrolling menu panel, demo, human-check group, docs | `AlertPanel.swift`, `DividerView.swift`, `Picker.swift`'s `.menu`, `MenuPanel` scrolling, `ServicesDemo.swift`, tests 2.26–2.32 and §6.3 | **not built**: none of those files exists, `Divider` is still menu-only, `.pickerStyle(.menu)` is still not offered, the drawn alert is a model nothing paints, there is no demo flag |

So **the feature the user asked for is two-thirds of its items**: file dialogs
(1), window sizing (3) and hover (4) work end to end on AppKit and SDL; alerts
(2) are native on AppKit and **invisible on SDL** (the platform declines, the
window holds the model, nothing draws it — `SV-AH` item 5); `Divider` as a view
(5) and the menu `Picker` (6) are unbuilt; clipboard beyond text (7) is
deferred by ruling (`SV-R`). The docs below say so wherever they list a
spelling. Lane 3 is owed (§10).

## §0 Baseline, design session and critic pass

- **Baseline** at `c2b8f48`: **2430 tests in 3 suites**, 0 goldens, 151
  typecheck guards, `Backends/SDL` 24 + 65, 92 live divergences (next label
  126), public census 2315 (spec §0).
- **Carried items** (decisions doc header): `MN-C`'s one defaultless `Bool`
  requirement with a queued answer (the shape the dialogs and alerts copy),
  `MN-F`'s window-owned panel (the drawn alert's model), `MN-Q`'s one
  `Handlers` member per attachment (hover), `LC-B`/`LC-C`/`LC-U` (a transparent
  scope with a registry outside `StateTable`: `PresentationScope`), `LC-L`
  (`.task` deferred behind the SDL loop: `SV-H` is its owner), `IX-D`/`DN-F`
  (the one ranking), `GX-I`/`GX-P` (hitboxes follow transforms).
- **Probes.** `swiftui-platform-services.swift` ran twice, 163 lines
  byte-identical; `swiftui-window-sizing.swift` one build per arm, run twice
  from clean defaults; `swift-main-queue-drain-nested.swift` on macOS and in
  `swift:6.4-noble`. **`H` (hover) is a recorded broken instrument**: SwiftUI's
  hover cannot be driven headless, so every hover semantic is MetalUI's own
  ruling (`SV-N`) with gpui as the comparison, not evidence, and the inventory
  family is class A on the spelling alone (`SV-AH` item 8). Human check U-hover
  owns the SwiftUI reading.
- **Critic pass** (`SV-X`…`SV-AD`): six corrections — Return on an alert
  re-measured (`SV-X`, probe `K0`–`K3`: SwiftUI's headless Return did not press
  Save), `alert(presenting:)` with `nil` data still presents (`SV-Y`, `R0`–`R4`),
  a hover region covers the regions beneath it (`SV-Z`), a menu picker measures
  its option titles once per change (`SV-AA`), SDL's real dialog in the Linux
  image measured before it is asserted (`SV-AB`), and the lanes rebalanced
  (`SV-AC`: window sizing to lane 1, the drawn alert to lane 3).

## §1 What landed

- **The platform seam** (`Sources/MetalUIPlatform/Presentations.swift`, `SV-B`):
  four **defaultless** `PlatformWindow` requirements — `presentFileDialog(_:) ->
  Bool`, `presentAlert(_:) -> Bool`, `dismissPresentation(token:)`,
  `setContentSizeLimits(minimum:maximum:)` — and three `InputEvent` cases,
  `.pointerExited`, `.fileDialogResult(_:)`, `.alertResult(_:)`; answers come
  back as queued input, never re-entrantly (`MN-C`). `PlatformFileType`,
  `PlatformFileDialog`, `FileDialogResultEvent`, `PlatformAlert`,
  `PlatformAlertButton`, `AlertResultEvent`; `AccessibilityRole.popUpButton`
  and `.alert` (both bridges, `SV-S`; AccessKit has no pop-up role, so
  `.popUpButton` is `COMBO_BOX` with `has_popup = MENU`). Every conformer — the
  AppKit window, the SDL window and all test fakes — implements all four; five
  of the seven compile-guard fixtures held a `PlatformWindow` and gained them
  (`SV-AE` item 7). Migration notes: `docs/migration.md`.
- **File dialogs** (`FileDialogs.swift`, `Presentations.swift`, `SV-C`…`SV-G`):
  `.fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)`
  (and the one-file form) and `.fileExporter(isPresented:item:contentTypes:defaultFilename:onCompletion:onCancellation:)`
  on every element group, each returning `PresentationScope<Content>`, a
  transparent scope whose record lives in a window registry keyed by position,
  depth and occurrence (`$presentation<depth>`; never a `StateTable` slot, no
  `noteNamed`, the seven slots unmoved — `SV-AH` item 6). Presented after the
  frame in which `isPresented` turned `true`; `isPresented` is written `false`
  before the callback. **The async call**: `FileDialogs.openFiles(…) async
  throws -> [URL]` and `saveFile(…) async throws -> URL?`, `@MainActor`,
  holding its window weakly, from `@Environment(\.fileDialogs)` or
  `Window.fileDialogs`; a cancelled awaiting task dismisses the dialog. One
  presentation or call in flight per window (`SV-AH` item 4: a call while
  anything is up throws `.busy`). `ContentType` gains filename extensions and
  `.json` (`SV-E`). **AppKit**: `NSOpenPanel`/`NSSavePanel` as **sheets on the
  window** (`SV-F`). **SDL**: `SDL_ShowOpenFileDialog`/`SDL_ShowSaveFileDialog`,
  the callback on any thread pushing one SDL user event that the window
  translates to `.fileDialogResult` (`SV-G`); a type filters by **extension
  only** off Apple (divergence 129).
- **The SDL main-queue drain** (`SDLPlatform+MainQueue.swift`, `SV-H`; the plan's
  gap 10, `LC-L`'s owner): the SDL loop drains the main dispatch queue each
  iteration, so a main-actor `Task` and an `await` on a dialog answer resume
  under `SDLPlatform.run()`. **Measured, and not what the ruling first
  said** (`SV-AE` item 2): on Linux a task resumes after tens to hundreds of
  loop passes (36 and 133 in two runs; a dialog answer after 44), macOS after 2
  and 5 — latency is wall-clock, not a pass count. **macOS cannot see the
  drain** (SDL's Cocoa pump drains the queue itself); the Linux image is the
  separating run (`SV-AF` M1.18). `Backends/SDL/Sources/MainQueueDrainCheck` is
  the executable both tests run. `.task` itself is still not built (§10).
- **Alerts** (`Alert.swift`, `SV-I`, `SV-J`, `SV-X`, `SV-Y`): `.alert` in
  four spellings (`isPresented:actions:`, `…message:`, `presenting:`, both with
  `message:`) and `.confirmationDialog` (the same alert, `actions:` and
  `message:`; **`titleVisibility:` is not offered** — guard
  `titleVisibilityIsNotOffered`). Actions are the closed `AlertActions` (a
  `Button` with a `Text` label, `role: .cancel`/`.destructive`) through
  `@AlertActionsBuilder`; SwiftUI's resolution: the cancel button last and on
  Escape, a synthesized "Cancel" beside a lone destructive, one "OK" for none,
  Return on the first plain button only when none is destructive (probes `A1`–`A9`,
  `K0`–`K3`). The non-presenting forms evaluate their actions and message
  while building; the `presenting:` closures run at presentation and never for
  `nil` data (`SV-AH` item 7). **AppKit** shows an `NSAlert` sheet; its key
  equivalents are applied *after* `beginSheetModal` because `NSAlert`
  re-derives them when it lays itself out (`SV-AE` item 4). **SDL answers
  `false`** and the window holds the resolved model (`Window.drawnAlert`,
  `chooseAlertButton(_:)`, test 2.25b) — **no paint, no input stage, no
  accessibility record: lane 3**.
- **Window sizing** (`WindowSizing.swift`, `Window.swift`, `App.swift`,
  `SV-L`, `SV-M`): `App.openWindow(title:size:minSize:maxSize:windowResizability:…)`
  and settable `Window.minSize`, `Window.maxSize`, `Window.windowResizability`;
  `WindowResizability` `.automatic` (asks the content nothing — divergence 126,
  where SwiftUI's `.automatic` is `.contentMinSize` plus a 32-point title-bar
  inset), `.contentMinSize` (the root's answer at a zero proposal follows the
  content), `.contentSize` (adds its answer at an infinite proposal as the
  maximum). The limits are measured once per frame before the real layout
  (`LayoutTree.measureNativeLayout` became `package`), reach the platform
  through `setContentSizeLimits` only when they change, and exactly once before
  the first frame (`SV-AE` item 6). AppKit `contentMinSize`/`contentMaxSize`
  and a resize into the limits; SDL `SDL_SetWindowMinimumSize`/`Maximum`.
- **Hover** (`Hover.swift`, `Frame.swift`, `Handlers.swift`, `Window.swift`,
  `SV-N`, `SV-Z`): `.onHover(perform:)` and `.onContinuousHover(perform:)` with
  `HoverPhase` on both vocabularies. **`hover` is `Handlers`' seventeenth
  member** (464 → 472 bytes, `SV-AH` item 1). A hover region is a **non-opaque**
  hitbox inside the disabled and `allowsHitTesting` gates, read through the one
  ranking; an element is hovered while nothing opaque or another region covers
  it on its layer (nested regions all hover); callbacks run from input under
  `StateDispatch`, and after a frame in which content moved under a still
  pointer; leavings innermost first, then enterings outermost first; the set is
  empty while an in-window menu or a drawn alert is up. **`.pointerExited`
  (AppKit `mouseExited`, SDL mouse-leave) clears `lastMousePosition`**, so
  `PaintPass.isHovered` is no longer sticky when the pointer leaves the window
  (migration note). The pointer target's and the draggable's own hitboxes carry
  no hover attachment (`SV-AH` item 2: they hovered twice).
- **Ordering inside a frame** (`SV-AH` item 3): after the lifecycle's drain and
  settle build and the resize re-raise, `reconcilePresentations()` then
  `updateHover(at:reportsMoves: false)`, before accessibility and
  `finishFrame`. A resize that lands inside a build owes the next frame
  (`SV-AG` item 3: the settle build's `needsRedraw = false` had cleared it).
- **Review fixes** (`SV-AG`): SDL applies the limits in either order (it refuses
  a minimum above the maximum still set, which kept the old minimum on Linux and
  Windows — the bridge lifts the maximum, sets the minimum, then the maximum,
  and `SDLWindow.setContentSizeLimits` raises a maximum that rounds below its
  minimum); the `maxSize` NaN trap pinned; leaving `.contentSize` drops the
  content maximum at once.

## §2 Tests and guards, per file

Counts are `@Test` declarations; a parameterised test is one declaration.

| File | Tests | Covers |
|---|---|---|
| `Tests/MetalUITests/AppKitPresentationTests.swift` | 9 | spec 1.1–1.9: panel sheets, types and names, queued answers, dismiss, one sheet at a time, `NSAlert` keys/order/index, limits, `mouseExited` |
| `Tests/MetalUITests/WindowSizingTests.swift` | 12 | 2.33–2.42 and the review's two: `.automatic` asks nothing, change-only calls, zero/infinite proposals, per-axis combination, measured before layout, limits before the first frame, clamps, both NaN arms, the settle-build resize, leaving `.contentSize` |
| `Tests/MetalUITests/PresentationTests.swift` | 11 | 2.1–2.11: importer/exporter presentation, `isPresented`, cancel, late results, failure, single URL, representation choice, `nil` item, turns |
| `Tests/MetalUITests/FileDialogTests.swift` | 8 | 2.12–2.19: the async call, cancel, task cancellation, `.busy`, `.noWindow`, the environment, `ContentType.json`, `PlatformFileType` |
| `Tests/MetalUITests/AlertTests.swift` | 7 | 2.20–2.25b: button resolution, presentation, result order, dismiss, `presenting: nil`, confirmation dialog, the held drawn model |
| `Tests/MetalUITests/HoverTests.swift` | 15 | 2.43–2.57: enter/leave, nesting, opaque covers, never blocks a click, gates, transforms, higher layers, `pointerExited`, leaving elements, content under a still pointer, menu/alert suppression, continuous phases, zero cost unused, a visit per hitbox, sibling cover |
| `Backends/SDL/Tests/MetalUISDLTests/SDLPresentationTests.swift` | 9 | 1.10–1.16 and 1.15b, plus dismiss: dialog thread hop, outcomes, the Linux image's `.failed`, filters, `presentAlert` declines, limits, either order, mouse-leave |
| `Backends/SDL/Tests/MetalUISDLTests/SDLMainQueueDrainTests.swift` | 3 | 1.18–1.19 and the check executable's presence |
| Existing files moved | — | `ContextMenuTests` (`handlersGainsOneReferenceMember` 464 → 472), `ModifierTests` (the `Handlers` size bound `+ 8`; the case count 55 → 57), `OuterModifierMatrixTests`, `DisabledTests`, `HitRegionTests`, `AccessibilityModifierTests` and `Fakes.swift` (the four members) — each reddened when the change landed and was a fix, not a regression |

**Typecheck guards** (**11 new**; the guard total moves 151 → 162 (the `canTypecheck`-gated declaration count 150 → 161 by `grep`)):
`PlatformServicesCompileGuards.swift` (4, lane 1: a `PlatformWindow` without
`presentFileDialog`, without `presentAlert`, without `dismissPresentation`,
without `setContentSizeLimits` does not compile) and
`PresentationCompileGuards.swift` (7, lane 2:
`anOutsideTypeCannotConformToAlertActions`, `aNonTextButtonIsNotAnAlertAction`,
`thePresentationSpellingsTypecheckFromAnExternalModule`,
`aLegacyDecorationAfterAPresentationModifierDoesNotCompile`,
`fileDialogsIsReadOnlyOutsideMetalUI`, `titleVisibilityIsNotOffered`,
`onHoverTypechecksOnBothVocabularies`). **Tests never sleep**; the SDL tests
that need a presented frame or a real dialog are gated `.enabled(if:)` on the
offscreen driver (`SV-AB`).

## §3 The suite at the Record phase

`swift package clean`, then `swift build --build-system native --build-tests`
and `swift test --build-system native --no-parallel`, unfiltered (re-taken at
``1ac200e` plus this phase's docs`): **`Test run with 2503 tests in 3 suites passed after 143.340 seconds` (2430 + 73)**; the `FR-J no-argument frame: succeeded=` line
present; 0 `error:` in the build and test logs, the only `warning:` SwiftPM's `--build-system native` deprecation notice (the default-build-system `swift build --build-tests` 0-warning check was lane 1's `3aa9898` reading and was not re-run here). `Backends/SDL`: 24 XCTest + 77 Swift Testing on macOS, **24 +
74** in `swift:6.4-noble` (`SDL_VIDEO_DRIVER=offscreen`), lane 1's last
measurement at `3aa9898` — **not re-run by this phase** (lane 2 changed no
`Backends/SDL` file; `git diff 3aa9898 HEAD --stat -- Backends` is empty). The
Linux container for the root portable targets was not re-run: no portable
target changed after lane 1's run apart from `MetalUIPlatform`'s seam (built
there by lane 1).

## §4 Red runs

Each lane committed its tests before its source: `c5cb50f` (lane 1: guards
1.G1–1.G4, AppKit 1.1–1.9, sizing 2.33–2.42, SDL 1.10–1.20 — red as the
requirements did not exist) and `354f752` (lane 2: presentations 2.1–2.11, file
dialogs 2.12–2.19, alerts 2.20–2.25b, hover 2.43–2.57, guards 2.G5–2.G11, the
`HandlerShape`/`HandlerFingerprint` hover fields, the D2 and `allowsHitTesting`
hover arms). Three reds are *fixes*, not regressions (`SV-AH` item 1): the two
`Handlers` size pins and the modifier case count, which reddened when the member
landed and moved with a note.

## §5 Mutation tables

**Lane 1** (`SV-AF`, 36 rows, baseline 2453 then 2455 root, 76/77 macOS SDL,
73/74 Linux SDL; the full table is `SV-AF`). Findings: **M2.41 survived** (the
per-value clamp to 0 was dead code — deleted, `ce632d1`; M2.41b, the live
spelling, reddens `negativeLimitsClampAndInfiniteMaximumMeansNone`); **M1.18
(the drain removed) reddens Linux only** — `theSDLLoopRunsAMainActorTaskStartedFromTopLevelCode`
and `aDialogAnsweredOnAnotherThreadResumesAnAwaitingTask` — and nothing on
macOS; the re-verification's rows are, applied after `9b2c32e` and each restored
from a copy with `git status --short` clean:

| # | Mutation | Reddened |
|---|---|---|
| M1.15b | `bool lifted = true;` in `mui_window_set_size_limits` (the original order: minimum, then maximum) | `sdlContentSizeLimitsApplyInEitherOrder`, on macOS and in `swift:6.4-noble` (the raised minimum reads `[100,100,1440,400]`; the `600.5` pair refused too) |
| M1.15c | `SDLPlatform.setContentSizeLimits`' `atLeast` spelled `{ high }` | `sdlContentSizeLimitsApplyInEitherOrder` (`[601,50,601,60]`) |
| M2.42b | `ContentSizeLimits.requireNotNaN(maxSize, …)` deleted from `Window.maxSize` | `aNaNLimitTraps` (before the review's arm, green) |
| M2.43 | `if resizeCount != resizesBeforeBuild { setNeedsRedraw() }` deleted | `aResizeIntoContentLimitsOnALifecycleFrameOwesTheNextFrame` |
| M2.44 | `if windowResizability != .contentSize { contentLimits.maximum = nil }` deleted | `leavingContentSizeDropsTheContentMaximumAtOnce` |

**Lane 2's guards** (`SV-AI`, baseline 2503 tests, each mutant one issue):

| # | Mutation | Reddened |
|---|---|---|
| MG2.5 | `@_spi(AlertInternals)` dropped from `_AlertButtons` and the `AlertActions` requirement | `anOutsideTypeCannotConformToAlertActions` |
| MG2.6 | `extension Button: AlertActions` with no `where Label == Text` | `aNonTextButtonIsNotAnAlertAction` |
| MG2.7 | fixture: `allowedContentTypes:` → `contentTypes:` | `thePresentationSpellingsTypecheckFromAnExternalModule` |
| MG2.8 | fixture: the negative's `.onClick {}` moved before `.alert` | `aLegacyDecorationAfterAPresentationModifierDoesNotCompile` |
| MG2.9 | `EnvironmentValues.fileDialogs` `public internal(set)` → `public` | `fileDialogsIsReadOnlyOutsideMetalUI` |
| MG2.10 | an added `confirmationDialog(…titleVisibility:…)` overload and a public `Visibility` | `titleVisibilityIsNotOffered` |
| MG2.11 | fixture: `.onContinuousHover` → `.onContinousHover` | `onHoverTypechecksOnBothVocabularies` |

**Lane 2's behavioural tests (2.1–2.25b, 2.43–2.57) have no mutation table.**
No verifier ran, and `SV-AI` covers only the seven guards. This is a hole, not a
pass: the findings of lane 2 (`SV-AH`) came from implementing and from red
runs, and the production readers of its new state (the registry's one in-flight
slot, `updateHover`'s ranking, the opaque-hitbox hover strip) were never
mutated. Owed (§10).

**An unreverted mutation was found and reverted by this phase.** The worktree
held an uncommitted edit to `Sources/MetalUI/Presentations.swift`'s alert-result
handler, swapping `record.isPresented.wrappedValue = false` and `action?()`
(`SV-AH`/`SV-I`: `isPresented` is written `false` *before* the action runs) — an
interrupted mutation from the lane-2 verifier. It was reverted with `git
checkout` before the suite above; HEAD never contained it. The test that
should redden is `anAlertResultWritesIsPresentedFalseThenRunsTheAction`; this
phase did not run that mutation, so the claim that it reddens is **not
measured here**.

## §6 Green mutations and pins that prove less than they look

- **M2.41** survived and was a dead clamp (deleted).
- **The drain is invisible on macOS** (M1.18): the two drain tests are green on
  macOS with the drain removed. They are real only in the Linux image; a macOS
  green says nothing about gap 10.
- **Hover's SwiftUI parity is not evidenced** (probe `H` is broken): the nine
  hover pins pin MetalUI's own rulings, so a SwiftUI that behaves differently
  would not redden any of them.
- **The native sheets are tested in a nested run** (`SV-AE` item 5): ending an
  `NSSavePanel` sheet stops the main run loop it is called in, which from a
  Swift Testing job exits the process 0 with no summary line. `inNestedRun` is
  load-bearing in every AppKit presentation test.
- **The SDL dialog tests run a real dialog only where one can open**; in the
  Linux image the driver answers `.failed("File dialog driver unsupported …")`,
  which test 1.12 asserts. That pins the failure path, not a chosen file.

## §7 Demo comparison and looks

- **Fourteen offscreen images** (`docs/probes/demo-pixels/compare.sh <scratch>
  c2b8f48 HEAD`): **0 differing pixels and `scene identical` in all fourteen** (`c2b8f48` → `1ac200e`), controls non-zero (light vs dark 1048576, default vs modal 1031003, default vs animation 454895, f0 vs f3 0). No demo file changed on this branch (lane 3 owns
  the demo); `DemoFrameDeterminismTests`' `Expected.swift` is unedited.
- **There is no demo for this feature** (`METALUI_SERVICES_DEMO` was lane 3's):
  nothing exercises a dialog, an alert or hover in a running window except the
  tests.
- **The real-window capture was not taken** (not attempted; the lock probe was
  not run — there is nothing new to capture).
- **Owed — `docs/verification/human-checks.md` group U, none performed (an agent
  cannot)**: U1 the open panel is a sheet on the window, filtered, returning on
  both Cancel and Open; U2 the save panel's name, extension and prompt; U3
  Linux and Windows desktop dialogs and the main-queue drain; U4 the `NSAlert`
  sheet's order, Escape and Return (with the app active — `SV-X` measured
  headless); U5 hover un-highlights on leaving the tile and the window, and the
  top tile only over an overlap; U6 dragging a window edge stops at the
  declared minimum; U7 a `.contentMinSize` window follows its content. The
  drawn alert, `Divider` and the menu picker's looks are not listed because
  they do not exist.

## §8 Hazards

- **`NSSavePanel` ending stops the enclosing main run loop** (§6): an AppKit
  presentation test outside `inNestedRun` ends the whole run with exit 0 and no
  summary line — read the last log lines.
- **A new `PlatformWindow` conformer owes four members** and the SDL bridge's
  C enum rawValues convert explicitly (Windows `Int32`).
- **SDL refuses a minimum above the still-set maximum**; any new limit call
  keeps `mui_window_set_size_limits`' lift-then-set order.
- **`PresentationScope`'s group layout is `LifecycleScopeLayout`**; a change to
  one moves both.
- **Handlers is 472 bytes**; the next member moves three pins (`SV-AH` item 1).
- **`Window.drawnAlert` is held and never painted on SDL**: an `.alert`
  presented there is never shown, so nothing can answer it — its `isPresented`
  binding stays `true` until the app sets it from elsewhere (not
  run on SDL by this phase; read from `SV-AH` item 5, which says nothing is
  painted). Do not ship an `.alert` to an SDL user before lane 3.
- **Cost of the drain** (`SV-H`): at most one main-queue pass per loop
  iteration; a frame depends on none of it.

## §9 The Record phase's own close

- `git fetch`: `origin/master` is `c2b8f48`; nothing to merge.
- Suite and counts: §3. Inventory: `closeout-inventory-check.sh` and
  `closeout-undocumented.sh` — both print nothing; the census was re-recorded (`closeout-public-api.sh`, 2315 → 2402 declarations; line numbers in `Lifecycle.swift` had drifted by one).
- Docs written by the lanes (`api-overview.md`, `divergences.md` 126 and 129 and
  the amended 120, `migration.md`, the inventory map and census) were read
  against source here; this phase added the record, the spec's Status, the
  README rows, `CLAUDE.md`/`AGENTS.md`, record §03's looks and
  `human-checks.md` group U.
- **Divergences: 92 → 94 live; next label 130.** Labels 127 and 128 were
  reserved for lane 3 (`Divider` in a stack; the menu picker) and are **unused**
  — a retired label is never reused, a reserved one is not retired; lane 3
  takes them or releases them in its own change.

## §10 Deferrals, with owners

- **Lane 3, entire — owner: the next session on this branch.** `AlertPanel.swift`
  (paint, the modal input stage, the accessibility record, calling
  `chooseAlertButton`), tests 2.26–2.32 and 2.53's alert half; `Divider()` as a
  view and the stack-axis environment (`SV-O`; the user's 13 `Divider`s);
  `.pickerStyle(.menu)` (`SV-P`, `SV-AA`; hundreds of options, divergence 81's
  `aMenuPickerStyleIsNotOffered` → `aMenuPickerStyleCompiles`); the scrolling
  in-window menu (`SV-Q`); `METALUI_SERVICES_DEMO`, `ServicesDemo.swift`, the
  `DemoStackBudgetTests` entry and `Backends/SDL`'s demo; the probes' remaining
  readings; divergences 127/128. **Until it lands, an SDL app has no visible
  alert.**
- **Lane 2's mutations** (§5): the behavioural tests were never mutated.
  Owner: the lane-3 session, as its first step.
- **`.task(perform:)` / `.task(id:)`**: its blocker is removed (`SV-H`), the
  modifier is a lifecycle follow-up with `K1`/`K2`'s semantics. Owner: the
  gpui-gap priority list.
- **Clipboard images and typed data** (`SV-R`): two more requirements on both
  platforms for a use the configurator lacks. Owner: the gpui-gap priority
  list.
- **Not built**, owner none (`SV-W`, spec §11): `fileExporter(document:)`/
  `FileDocument`, `fileMover`, folder selection, the file-dialog customisation
  modifiers, alert text fields and `titleVisibility:`, an SDL native message
  box, closing an SDL file dialog from code (SDL3 has no call), type-select in
  the drawn menu, `onContinuousHover(coordinateSpace:)` other than `.local`,
  main-actor tasks under an `async` main.
- **Linux/Windows CI** confirm on push: the C-enum conversions, the
  `Backends/SDL` dialog and limit tests on Vulkan/D3D12, and
  `DemoFrameDeterminismTests`.
- **The human looks**: group U (§7). An agent cannot perform them.
