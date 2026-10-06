# 77 — Platform services: dialogs, alerts, window sizing, hover, `Divider`, menu `Picker` (all three lanes landed)

Branch `feat/platform-services` from `c2b8f48` (master: lifecycle merged, PR
#46). **Not a plan task**: user request 2026-10-02, an item of the gpui-gap
priority list — the SMK keyboard configurator port's gaps 4, 5, 7, 8, 9, 10 and
12. Spec `docs/superpowers/specs/2026-10-04-platform-services-design.md`;
rulings `SV-A`…`SV-AL` in the new decisions doc
`docs/superpowers/2026-10-04-platform-services-decisions.md` (next unused
`SV-AM`); probes `docs/probes/swiftui-platform-services.swift` (arms `D`
importer, `X` exporter, `A`/`C1` alerts and the confirmation dialog, `H` hover
— **a recorded broken instrument** —, `V` `Divider`, `P` the menu picker),
`swiftui-window-sizing.swift` (`W0`–`W5`), `swift-main-queue-drain-nested.swift`
(`J0`–`J3`) and `swiftui-alert-presenting.swift` (`R0`–`R4`, `K0`–`K3`).

**Numbering.** Master had published no record past §76 at either Record phase
(`git fetch`: `origin/master` still `c2b8f48` on 2026-10-06), so §77 stands.

**Status: IMPLEMENTED (2026-10-06) — lanes 1, 2 and 3 landed and each was
verified `ok: true`.** What the three lanes built is `SV-AC`:

| Lane | Owns | State |
|---|---|---|
| 1 — seam + window sizing | the four defaultless platform requirements, three `InputEvent` cases, two accessibility roles, AppKit panels/sheets, SDL dialogs, the SDL main-queue drain, `minSize`/`maxSize`/`WindowResizability` | **landed**, verified `ok: true` (re-verified at `3aa9898`, 2455 tests) |
| 2 — presentations + hover | `PresentationScope`, `.fileImporter`/`.fileExporter`, `FileDialogs`, `.alert`/`.confirmationDialog` and their resolver, `onHover`/`onContinuousHover` | **landed**, verified `ok: true` at `f36d470` (2506 tests; four mutations, `SV-AJ`) — the first Record phase wrote "no verdict delivered"; the verdict arrived afterwards |
| 3 — drawn alert, `Divider` view, menu `Picker`, scrolling menu panel, demo, human-check group, docs | `AlertPanel.swift`, `DividerView.swift`, `PickerMenu.swift`, `Picker.swift`'s `.menu`, `MenuSession`/`MenuPanel` scrolling, `ServicesDemo.swift`, tests 2.26–2.32, §4–§6 of the spec | **landed**, verified `ok: true` at `7ca929d` (2546 tests; 31 mutations in `SV-AL`, ten more of the verifier's, seven of which survived — §6) |

All seven items are built except clipboard beyond text (7), deferred by ruling
(`SV-R`): file dialogs (1), alerts (2), window sizing (3), hover (4), `Divider`
as a view (5) and the menu `Picker` (6) work on AppKit and SDL; an alert is a
native `NSAlert` sheet on AppKit and a drawn, modal panel on SDL. The first
Record phase (`9f97427`, lanes 1 and 2 only) wrote this record as PARTIAL; this
phase rewrote it for the finished branch. The looks are unseen: human-checks
group U (U1–U12) is not run — an agent cannot.

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
  `chooseAlertButton(_:)`, test 2.25b), which lane 3 draws (below).
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
- **The drawn alert** (`AlertPanel.swift`, `SV-J` items 2–4, `SV-AK` item 1):
  where the platform answers `false` (SDL) the window paints the held
  `Window.drawnAlert` above everything but nothing else — a scrim, a 260-wide
  panel 24 from the top, bold title, message, buttons (cancel left, the rest
  right); the accent goes on the `SV-X` default only. A **modal input stage**
  after the dialog and alert answers and ahead of the tooltip, drag session and
  menu: the ring starts on the default (nothing when there is none), Tab/→/↓
  forward and Shift-Tab/←/↑ back, wrapping; Space presses the ringed button
  (also as `.textInput(" ")`), Return only the default, Escape only the cancel
  button; pointer, wheel, keys and a drop from outside reach nothing beneath;
  an open in-window menu is dismissed; the hover set is empty. An `.alert`
  accessibility node with button children (ids from the window-reserved
  `$alert-panel` root, never a `StateTable` entry), an accessibility press on
  anything but its buttons refused.
- **`Divider` as a view** (`DividerView.swift`, `SV-O`, `SV-AK` item 2):
  `Divider: Element, ProposalElement`, a 1-point line across the nearest
  `HStack`/`Row` (vertical) or `VStack`/`Column` (horizontal; also outside any
  stack, in a `ZStack` and in a `Grid`), 10 along on a nil proposal, painted
  in the opaque `.separator` token (divergence 127: SwiftUI's is translucent
  black/white), no accessibility node. The axis is a stack on `Frame`
  (`withStackAxis`), pushed and popped around the children's requests by the
  `HStack`, `VStack`, `ZStack`, `Row`, `Column` and `Grid` — read only by layout, so no
  id moves. A menu `Divider` is the unchanged separator; the menu guard's
  negative became a `Rectangle` (its flip).
- **The menu `Picker`** (`Picker.swift`, `PickerMenu.swift`, `SV-P`, `SV-AA`,
  `SV-AK` items 3–5): `.pickerStyle(.menu)` — a pull-down button showing the
  selected title, as wide as its widest option, opening every option as a
  checked-or-not item through the menu machinery (native `NSMenu`, else the
  drawn panel opening on the selection); options are recorded without being
  laid out (one identity slot whatever the count), a non-`Text` option is titled
  by its tag (divergence 128), the button publishes `.popUpButton`; the
  automatic style stays segmented (divergence 81 narrowed; the guard
  `aMenuPickerStyleIsNotOffered` became `aMenuPickerStyleCompiles`). The width
  cache is window-owned (`Window.pickerTitleWidths`): 300 options measure 299
  titles once and none on a warm frame.
- **The scrolling in-window menu** (`MenuSession.swift`, `MenuPanel.swift`,
  `SV-Q`, `SV-AK` item 6): a menu taller than the window less its margin is
  clamped, scrolls by wheel (`ScrollView`'s sign) and ↑/↓ with the highlight
  scrolled into view, shows ▴/▾ bands only at an edge with rows past it, and
  finds visible rows by bisection (paint and hit testing O(log n + visible)).
- **The services demo** (`ServicesDemo.swift`, `SV-T`, `SV-AK` item 7):
  `METALUI_SERVICES_DEMO=1 swift run MetalUIDemo` (and the same flag on
  `MetalUISDLDemo`), 960 × 640 with a 900 × 600 minimum: Import…, Export… and
  an async "Open…", a "Delete…" alert, three hover tiles, `Divider`s in four
  stacks and a 300-option picker. Each section is a `ServicesPart` `Component`
  built at layout (Windows' 1 MB stack, `SV-AK` item 7).
- **Test-side finding** (`2.4c`, MC.2's owed test): a scope leaving the tree
  while presented is dismissed and its late answer runs nothing.

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
| `Tests/MetalUITests/AlertPanelTests.swift` | 8 | 2.26–2.32: the drawn alert's paint order and accent, Return/Escape, Tab/arrows/Space, the modal stage, a click, the `.alert` node, an open menu dismissed, the hover set emptied |
| `Tests/MetalUITests/DividerTests.swift` | 11 | 4.1–4.10 and 4.G12: the axis per stack, 10 on a nil proposal, the `.separator` token one point thick, no leak past a stack, transparency through wrappers, a menu `Divider` unchanged, and `aDividerIsBothAMenuItemAndAnElement` |
| `Tests/MetalUITests/MenuPickerTests.swift` | 12 | 5.1–5.11 and 5.17: the pull-down label and width, `.popUpButton`, openers, options laid out as nothing, option checks and tags, a non-`Text` option, the automatic style, 299 / 0 / 299 title measurements |
| `Tests/MetalUITests/MenuPanelScrollTests.swift` | 5 | 5.12–5.16: a tall menu clamps and scrolls, arrows scroll the highlight into view, the selection opens in view, hit testing follows the offset, a short menu does not scroll |
| `Tests/MetalUITests/ServicesDemoTests.swift` | 3 | 6.1–6.3: the demo's sections, its 300-option picker, its counter text |
| `Tests/MetalUITests/PresentationTests.swift` | +1 | 2.4c: a scope leaving the tree while presented |
| `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift` | edited | `everyProductionTreeBuildsOnAOneMegabyteThread` builds the services tree and each `ServicesPart` body (`SV-AK` item 7) |
| Existing files moved | — | `ContextMenuTests` (`handlersGainsOneReferenceMember` 464 → 472), `ModifierTests` (the `Handlers` size bound `+ 8`; the case count 55 → 57), `OuterModifierMatrixTests`, `DisabledTests`, `HitRegionTests`, `AccessibilityModifierTests` and `Fakes.swift` (the four members) — each reddened when the change landed and was a fix, not a regression |

**Typecheck guards** (**12 new**: 11 in lanes 1 and 2 and lane 3's one, 4.G12 `aDividerIsBothAMenuItemAndAnElement` (`typecheckFile`, mutated red as MG3.14); lane 3 also **flipped two** — `aMenuPickerStyleIsNotOffered` → `aMenuPickerStyleCompiles` (5.G13, `.inline` the separating arm) and `theMenuSpellingsCompileFromAPlainImport`'s negative from `Divider` to a `Rectangle` menu item (its flip, MG3.12); the guard total moves 151 → 163 (`typecheck`/`typecheckFile` call sites in `Tests` 279 → 280 across lane 3)):
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
and `swift test --build-system native --no-parallel`, unfiltered, at `7ca929d`
(this phase's second pass, after lane 3 landed): **`Test run with 2546 tests in 3
suites passed after 144.291 seconds` (2430 + 116)**; the `FR-J no-argument
frame: succeeded=true` line present; 0 `error:` in the build and test logs, the
only `warning:` SwiftPM's `--build-system native` deprecation notice;
`swift build --build-tests` on the default build system: 0 `warning:`. Guards
**163** (151 + 12). Counts by step: 2430 (`c2b8f48`) → 2455 (lane 1, re-verified
at `3aa9898`) → 2506 (lane 2, `f36d470`) → 2546 (lane 3, +39 new tests and 2.4c).
`Backends/SDL`: 24 XCTest + 77 Swift Testing on macOS, **24 + 74** in
`swift:6.4-noble` (`SDL_VIDEO_DRIVER=offscreen`), as the lane-3 verifier
measured at `7ca929d` and lane 1 at `3aa9898` — **not re-run by this phase**
(lane 3 changed only `Backends/SDL/Sources/MetalUISDLDemo/main.swift`, built by
the verifier; no SDL test moved). The portable census is **2421** declarations
(`closeout-public-api.sh`, 2402 → 2421; the recorded file is current);
`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
The Linux container for the root portable targets was not re-run by this
phase; the one portable test lane 3 edited is
`DemoStackBudgetTests`, whose `swift:6.4-noble` overflow lane 3 found and fixed
(`SV-AK` item 7).

## §4 Red runs

Each lane committed its tests before its source: `c5cb50f` (lane 1: guards
1.G1–1.G4, AppKit 1.1–1.9, sizing 2.33–2.42, SDL 1.10–1.20 — red as the
requirements did not exist) and `354f752` (lane 2: presentations 2.1–2.11, file
dialogs 2.12–2.19, alerts 2.20–2.25b, hover 2.43–2.57, guards 2.G5–2.G11, the
`HandlerShape`/`HandlerFingerprint` hover fields, the D2 and `allowsHitTesting`
hover arms), and for lane 3 `be806c5` (the drawn alert 2.26–2.32, 2.53's alert
half, 2.4c) and `6236386` (`Divider` 4.1–4.10 and 4.G12, menu picker 5.1–5.11
and 5.17, the scrolling menu 5.12–5.16, the flipped guard 5.G13, demo
6.1–6.4): `AlertPanel.swift` does not exist at `be806c5`, and the `Divider`,
scrolling-menu, menu-picker and demo APIs do not at `6236386`. Three reds are *fixes*, not regressions (`SV-AH` item 1): the two
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

**Lane 2's review fixes** (`SV-AJ`, baseline 2506 tests; added after this
record's Record phase): V9 (hover's `region.contains(point)`) reddens
`aCoverDrawnOutsideItsHoverAncestorDoesNotHoverTheAncestor`; P5 (the file-dialog
token check) reddens `aStaleDialogAnswerNeverReachesTheNextRequest`; PA (the
alert token check) reddens `aStaleAlertAnswerNeverReachesTheNextAlert`; each
survived (V9, P5) before its arm. V1 (`keyboardHiddenDepth == 0` on the hover
registration) is equivalent.

**Lane 2's behavioural tests** had no mutation table when this record was first
written (no verifier verdict had arrived). The verifier's verdict, at `f36d470`,
is `ok: true` with the four mutations above (V9, P5, PA, V1) on the production
readers, and `SV-AL`'s MC.2 re-run closes the registry's scope-removal path.
`updateHover`'s full ranking and the opaque-hitbox strip's draggable half are
measured only by V9 and MC.1 (§11): thin, §10.

**Lane 3** (`SV-AL`, baseline **2546 tests in 3 suites**, `FR-J no-argument
frame: succeeded=true`; 31 rows: three guard mutations MG3.12–MG3.14, 27
behaviour mutations M3.1–M3.30, and MC.2). Every row reddened the tests it
names, no hang. Highlights: M3.1 (the axes swapped) reddens six tests (16
issues); M3.7 (`.textPrimary` for `.separator`) nineteen issues; M3.14b
(`popUpButtonHint` → `menuButtonHint`) six tests; **MC.2 is now pinned** by
test 2.4c (`aScopeLeavingTheTreeWhilePresentedIsDismissedAndItsLateAnswerRunsNothing`,
four issues). Not run: spec 4.8's "emit a node" (no one-line site), 5.8's "open
regardless of the gate" (the gate is `Button`'s, `MN-AF`) and 5.10's alternative
spellings.

**The lane-3 verifier's own ten mutations** (each from the committed tree, the
whole unfiltered suite, restored with `git status --short` clean): **three
reddened, seven did not** — the survivors are §6.

| # | Mutation | Reddened |
|---|---|---|
| V2 | `pressAlertButton`: an out-of-range press `return false` → `nil` | `theDrawnAlertPublishesAnAlertNodeWithButtonChildren` |
| V4 | Escape finds `\.platform.isDefault` instead of `isCancel` | `returnPressesTheDefaultAndEscapeTheCancelOnTheDrawnAlert`, `aDrawnAlertEmptiesTheHoverSet` |
| V8 | the menu wheel's sign flipped | `aTallInWindowMenuIsClampedToTheWindowAndScrolls`, `hitTestingFollowsTheScrollOffset` |
| V1, V3, V5, V6, V7, V9, V10 | see §6 | **nothing** |

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

- **Seven lane-3 claims are unpinned** (the verifier's survivors, each applied
  to the committed tree with all 2546 tests passing; `SV-AL` lists only
  mutations that reddened, so read this list beside it). Owner: the next session
  on this branch or the gpui-gap list's follow-up, each fix a test plus its
  mutation re-run:
  1. **V10** — the drawn alert's accessibility focus on its ringed button
     (`tree.focused = rootID` in `appendAlertPanel`): the only test checks the
     no-ring case (focus on the `.alert` node), so `SV-AK` item 1's "the ring
     starts on the default" is pinned for painting and keys but not for focus.
  2. **V9** — a submenu level clamping and scrolling (`clampedHeight: nil` in
     `openSubmenu`): `SV-AK` item 6's "a submenu level clamps the same way" has
     no test.
  3. **V5 and V6** — `Column`'s `.vertical` push and `Grid`'s `nil` push: the
     only `Column` fixture sits at the root, where "no axis" already reads
     horizontal, and `DividerTests` has no `Grid` case. Needed: a `Column {
     Divider() }` inside an `HStack`/`Row` (1 tall) and a `Divider` in a `Grid`
     cell inside an `HStack` (horizontal).
  4. **V1 and V3** — the drawn alert refuses a drop from outside
     (`.drop` → `false`) and Space as `.textInput(" ")` presses the ringed
     button: `AlertPanelTests` has no `.drop` and no `.textInput` event.
  5. **V7** — `PickerTitleWidths.sweep` (entries no build used are dropped):
     the picker width cache has no test-visible count, so a picker removed from
     the tree is never seen to leave an entry. Needed: a count on the cache.

## §7 Demo comparison and looks

- **Fourteen offscreen images** (`docs/probes/demo-pixels/compare.sh <scratch>
  c2b8f48 HEAD`): **0 differing pixels and `scene identical` in all fourteen**,
  taken at `1ac200e` (lanes 1 and 2), re-taken by the lane-3 verifier at
  `7ca929d` with every control matching (light vs dark 1048576, default vs
  modal 1031003, default vs animation 454895, f0 vs f3 0).
  `DemoFrameDeterminismTests`' `Expected.swift` is unedited since `c2b8f48`
  (Linux/Windows CI confirm on push). The lane-3 demo content is behind
  `METALUI_SERVICES_DEMO`, so no existing image changes.
- **The demo**: `METALUI_SERVICES_DEMO=1 swift run MetalUIDemo` and the same
  flag on `MetalUISDLDemo` (§1). It is the only running-window exercise of a
  dialog, an alert, hover, `Divider` and the menu picker beside the tests.
- **The real-window capture was not taken** (the lock probe was not run by
  this phase; the group-U looks need a person and, for the sheets, an active app).
- **Owed — `docs/verification/human-checks.md` group U (U1–U12), none
  performed (an agent cannot)**: U1 the open panel is a sheet on the window,
  filtered, returning on both Cancel and Open; U2 the save panel's name,
  extension and prompt; U3 Linux and Windows desktop dialogs and the main-queue
  drain; U4 the `NSAlert` sheet's order, Escape and Return (with the app
  active — `SV-X` measured headless); U5 hover un-highlights on leaving the
  tile and the window, and the top tile only over an overlap; U6 dragging a
  window edge stops at the declared minimum; U7 a `.contentMinSize` window
  follows its content; **U8 the SDL drawn alert (scrim, panel, ring, keys,
  modality); U9 the AppKit menu picker's native menu and VoiceOver pop-up
  button; U10 the SDL drawn picker menu scrolling; U11 the `Divider` hairline in
  light and dark; U12 the demo's dialogs and hover on both platforms.**

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
- **The widths cache is window-owned** (`Window.pickerTitleWidths`), never on
  the `PickerScope` (re-created every build, `SV-AK` item 5).
- **Handlers is 472 bytes**; the next member moves three pins (`SV-AH` item 1).
- **An `.alert`'s builder closures run off the main thread in a stack-budget
  test**: the non-presenting forms call them while building (`SV-AH` item 7),
  and a main-actor closure called off the main thread traps under Swift 6's
  dynamic isolation check (`.signal(SIGTRAP)` in
  `everyProductionTreeBuildsOnAOneMegabyteThread`, bisected to
  `Button.alert(…) { } message: { }` alone). The demo's alert is therefore in a
  `Component` built at layout (`SV-AK` item 7).
- **A debug frame reserves a slot per temporary for the whole function**: five
  section builds written into `buildEveryProductionTree()` overflowed the
  `swift:6.4-noble` container's stack (`SIGSEGV`) although each passes alone;
  they are built in their own `@inline(never)` function. A new demo section goes
  in its own function (`SV-AK` item 7).
- **`Divider`'s axis is a `Frame` stack read only by layout**: a new linear
  container owes a `withStackAxis` push (or `nil`) around its children's
  requests, or a `Divider` inside it inherits the enclosing stack's axis
  (`V5`/`V6` in §6 show `Column` and `Grid` are unpinned).
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
- **Divergences: 92 → 96 live; next label 130.** Lane 3 took the labels the
  first Record phase reserved: **127** `Divider`'s colour (`SV-O` item 4) and
  **128** a menu picker's non-`Text` option (`SV-P` item 3); **81** narrowed
  (`.pickerStyle(.menu)` offered, the automatic style still segmented). The
  list is `docs/divergences.md`; the section is record §04's
  "2026-10-06: 127 and 128 added, 81 narrowed".

## §10 Deferrals, with owners

- **Lane 3's seven unpinned claims** (§6): V10, V9, V5/V6, V1/V3, V7. Owner:
  the next session on this branch; each is a test and a re-run of its
  mutation.
- **Lane 2's remaining mutations** (§5): `updateHover`'s full ranking and the
  draggable half of the hover strip. Owner: the same session. (MC.2, the scope
  leaving the tree, is pinned by 2.4c.)
- **Native `NSMenu` placement over the picker button** (SwiftUI's pop-up
  placement; `SV-P` item 4 opens below it, human check U9). Owner: none.
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
- **The human looks**: group U, U1–U12 (§7). An agent cannot perform them.

## §11 Branch check (adversarial, at `9f97427`; lanes 1 and 2 only)

Taken before lane 3 existed. Its counts (2503) and its "unbuilt" citations
are superseded by §3 and the table in the status block; MC.2's survivor is
closed by 2.4c (§5).

Run from the committed tree, each mutation restored from a copy with
`git status --short` clean after it.

- **Suite** (`swift package clean`, native build, unfiltered `--no-parallel`):
  `Test run with 2503 tests in 3 suites passed after 139.028 seconds`;
  `FR-J no-argument frame: succeeded=true`; 0 `error:`, the only `warning:`
  SwiftPM's `--build-system native` deprecation. `cmp CLAUDE.md AGENTS.md`
  equal. `closeout-inventory-check.sh` and `closeout-undocumented.sh` print
  nothing. `MetalUILayout` imports only `MetalUICore`, `MetalUIScene` only
  `MetalUIShaderTypes`.
- **Demo pixels** (`compare.sh <scratch> c2b8f48 HEAD`): every control at its
  recorded value, all 14 images `differing=0`, `scene identical`.
- **`Backends/SDL`**: macOS 24 + 77; the Linux image (`swift:6.4-noble`,
  offscreen driver), from a `git archive` of `9f97427` and a fresh scratch path,
  24 + 74 — §3's lane-1 Linux figure, re-measured at `9f97427`.
- **Every `SV-` id cited in a changed doc resolves** to a `## SV-` heading
  (`SV-AJ` is only the "next unused" mark). The backticked test names cited in
  added doc lines that resolve to no test are all lane 3's planned tests in the
  spec's tables (2.26–2.32, 4.x, 5.x, 6.x) — unbuilt, as the spec's Status line
  says.
- **Identity, hit testing, accessibility, animation**: no test in those
  families was edited except to add arms or a field —
  `theNewDeclarationsCostHandlersAtMostOnePointer` and
  `handlersGainsOneReferenceMember` (472 bytes), `HandlerShape`/
  `HandlerFingerprint`'s `hover` field and two `ModifierCase` rows (55 → 57),
  `DisabledTests`' D2 hover arms and `HitRegionTests`' `allowsHitTesting`
  hover arm; `theSevenRetentionSlotsAreMutuallyDistinct`, the identity, focus,
  `List` and animation files are untouched and green. `isHovered` still ranks
  through `topmostOpaqueHitbox`, which a non-opaque hover region cannot win.

**Two mutations of the checker's design**, full unfiltered suite each:

| # | Mutation | Reddened |
|---|---|---|
| MC.1 | `Frame.registerHandlers`: `pointerHandlers.hover = nil` commented out (the opaque and draggable hitboxes keep the hover attachment, `SV-AH` item 2) | `pointerExitedClearsHoverAndIsHovered` only (`m.log` read the doubled `["t true", "t true", "t false", "t false"]` shape `SV-AH` item 2 records) — 2503 tests, 1 issue. The strip is pinned, but only incidentally, by a test named for the pointer leaving; the draggable half is unpinned |
| MC.2 | `Window.reconcilePresentations`: `record(for: key)?.isShown != true` → `== false` (a scope that **left the tree** while its dialog or alert is up is no longer dismissed) | **nothing — survived**, `2503 tests in 3 suites passed` |

**MC.2 is a finding.** `SV-K` item 3's "a key in flight whose record is **gone**
→ `dismissPresentation`" has no test: every presentation test dismisses by
writing `isPresented = false` (2.4, 2.23), never by removing the scope. With
the mutant, an `if`-removed `.fileImporter`/`.alert` leaves its panel or sheet
up and its answer later runs the departed scope's completion from the stale
`presented` record. Owed: a test removing the scope while presented, asserting
one `dismissedPresentations` entry and that a late answer runs nothing — before
merge, with the lane-2 mutation table (§10).
