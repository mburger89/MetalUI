# MetalUI

A GPU-accelerated UI framework for Swift, modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui), written as
idiomatic Swift, with SwiftUI as the design authority. **Supported: macOS
(AppKit + Metal, the default), Linux and Windows** (`Backends/SDL`,
`App(platform:textSystem:)`, the portable text system; `XP-A`/`XP-B`,
`docs/superpowers/plans/2026-09-23-cross-platform-roadmap.md`). **iOS, iPadOS, tvOS, watchOS
and visionOS are an explicit product boundary** (`PB-A`, record §65): no UIKit
conformer, no touch, no safe areas, none planned.

**This file is rules only.** The full 2026-10-01 version (177 KB: every
milestone summary, count history, renumbering note, guard-by-guard tally and
per-stage narrative) is frozen verbatim at
`docs/record/69-claude-md-full-2026-10-01.md`; older snapshots are record §19
(2026-09-21) and §67 (counts history). Reasoning and history live in
`docs/record/` (`README.md` indexes it, one row per milestone). Citations in
the record were not all re-checked after later refactors — verify a test name
or grep before relying on it. **New milestones append their record to
`docs/record/` and add only the rule here** — one or two sentences, not a
summary.

`AGENTS.md` is a byte-identical copy for Codex: edit `CLAUDE.md`, then
`cp CLAUDE.md AGENTS.md`; `cmp CLAUDE.md AGENTS.md` before committing.

## Where things are

- **Design spec (binding):** `docs/superpowers/specs/2026-08-24-metalui-design.md`;
  per-milestone specs and plans in `docs/superpowers/specs/` and `plans/`.
  SwiftUI-alignment plan: `docs/superpowers/plans/2026-09-12-swiftui-alignment.md` (tasks 1–15;
  12 and 15 wait on human checks). **The source is the authority** over the
  2026-09-12 kernel/modifier specs.
- **Decisions docs:** `docs/superpowers/<date>-<milestone>-decisions.md`, or a
  milestone's own spec for prefixes without one. Read their "Carried…"
  sections before new work. Ruling ids are namespaced by prefix (`F-`, `CS-`,
  `LR-`, `GR-`, `ID-`, `DD-`, `TE-`, `IX-`, `AN-`, `CX-`, `DN-`, `AI-` (app
  icon, next `AI-O`; own decisions doc
  `2026-10-01-app-icon-decisions.md`), `MV-` (MetalView:
  `docs/superpowers/2026-10-01-metal-view-decisions.md`, next `MV-S`), `SC-` (scaffold, next `SC-J`;
  `2026-10-01-scaffold-decisions.md`), `GX-` (paths, shadows, transforms:
  `2026-10-02-paths-shadows-transforms-decisions.md`, next `GX-Z`), `MN-` (menus, popovers, tooltips:
  `2026-10-02-menus-popovers-decisions.md`, next `MN-AJ`), `CR-` (colour, colour scheme, palette:
  `2026-10-03-colour-decisions.md`, next `CR-AC`), `LC-` (lifecycle modifiers:
  `2026-10-03-lifecycle-decisions.md`, next `LC-W`), `SV-` (platform services:
  `2026-10-04-platform-services-decisions.md`, next `SV-AM`), `PE-` (controls in
  SwiftUI stacks, `Component` stack: `2026-10-06-proposal-controls-decisions.md`,
  next `PE-AB`), `MD-` (port gaps, medium: field chrome, environment objects,
  window toolbar: `2026-10-07-port-gaps-medium-decisions.md`, next `MD-AA`), `PX-` (portable
  app: images, `.task`, the SDL traits: `2026-10-07-portable-app-decisions.md`, next `PX-W`), `CI-` (input APIs: wheel, pinch, other
  buttons, tap location, pointer style: `2026-10-08-input-apis-decisions.md`, next `CI-AM`), `TF-` (`.task`
  follow-ups: `2026-10-08-task-followups-decisions.md`, next `TF-F`), `VL-`
  (variable-height `List`: `2026-10-08-variable-height-list-decisions.md`, next `VL-W`), `WS-` (AccessKit before the first show:
  `2026-10-08-accesskit-window-show-decisions.md`, next `WS-I`), `RT-`
  (rich text: `2026-10-08-rich-text-decisions.md`, next `RT-U`), `LK-` (controls and looks:
  `2026-10-08-controls-looks-decisions.md`, next `LK-Y`), `AS-` (app shell:
  `2026-10-08-app-shell-decisions.md`, next `AS-R`), `KF-` (key and focus:
  `2026-10-08-key-focus-decisions.md`, next `KF-AB`), `PF-` (shadow cache, `compositingGroup()`:
  `2026-10-09-shadow-cache-decisions.md`, next `PF-O`), `SG-` (SMK port gaps: the drawn menu bar,
  `EventModifiers.primary`, design families, `Window.drawnChromeHeight`:
  `2026-10-09-smk-gaps-decisions.md`, next `SG-N`), `HT-` (test harness, `MetalUITesting`:
  `2026-10-09-test-harness-decisions.md`, next `HT-Y`), `OV-` (overlays and coordinates:
  `2026-10-10-overlays-coords-decisions.md`, next `OV-U`), `IF-` (input follow-ups:
  `2026-10-10-input-followups-decisions.md`, next `IF-O`), `FI-` (`ForEach` identity:
  `2026-10-10-foreach-identity-decisions.md`, next `FI-L`), `BB-` (backdrop blur behind a `Material`:
  `2026-10-10-backdrop-blur-decisions.md`, next `BB-U`), `WD-` (window drag:
  `2026-10-12-window-drag-decisions.md`, next `WD-L`), `SL-` (text selection:
  `2026-10-12-text-selection-decisions.md`, next `SL-O`), `GT-` (text over a GPU surface:
  `2026-10-12-surface-text-decisions.md`, next `GT-J`), `GC-` (continuing press cancel:
  `2026-10-12-continuing-press-cancel-decisions.md`, next `GC-H`), `RF-` (resign on press:
  `2026-10-12-resign-on-press-decisions.md`, next `RF-J`), `MT-` (material follow-ups:
  `2026-10-12-material-followups-decisions.md`, next `MT-L`), `IM-` (input-method
  driver: `2026-10-12-ime-driver-decisions.md`, next `IM-K`), `DG-` (developer guides:
  `2026-10-12-guides-decisions.md`, then `2026-10-13-guides-followup-decisions.md`, next `DG-W`), `BL-` (performance baselines:
  `2026-10-13-perf-baselines-decisions.md`, next `BL-D`), `RU-` (`runUntilIdle()` on Linux:
  `2026-10-13-rununtilidle-linux-decisions.md`, next `RU-C`), `IV-` (incremental invalidation:
  `2026-10-13-incremental-invalidation-decisions.md`, next `IV-R`), …; the full
  prefix → document → record table is in record §69 "Where things are").
  **To find the next unused id, read the file's last `## <PREFIX>-` heading,
  not its header** — headers have lagged. A decisions doc's "next unused" line
  moves in the commit that appends the ruling. A numbered citation of a
  lettered prefix (`LR-3`, `DN-3`, `AI-3`) is a typo.
- **Record:** `docs/record/NN-*.md`, one per milestone. When two lines publish
  the same number, the later merge renumbers and says so in its header.
- **SwiftUI probes:** `docs/probes/`; headers carry recorded output and how to
  run them (`SA-O`). Window captures: `docs/probes/window-capture/capture.sh`.
- **Practices:** `docs/practices/verifying-tests-can-fail.md` — read before
  writing tests.
- **Public documents:** `docs/api-overview.md`, `docs/divergences.md` (every
  live SwiftUI difference — **152 live, next label 206** (345–354 reserved by C14: 346 used, 345 refuted, 347–354 unused; 196–204 unused by C12, 215–224 unused by item 8, 226–234 unused by C15, 237–244 unused by C16, 256–264 unused by C20, 250–254 unused by C21, 267–274 unused by C25, 278–284 unused by C22, 285–294 unused by C24, 295–296 used and 297–304 unused by C23, 305–314 unused by C26, 315 used and 316–324 unused by C27, 325–326 used and 327–334 unused by C28, 189–194 unused by C9); retired labels are
  never reused), `docs/migration.md`, `THIRD-PARTY-NOTICES.md` (licences of the vendored C code and SDL3/AccessKit, per product), `docs/verification/human-checks.md`
  (groups A–Y, VL, RT, WS, AS, CL, KF, PF, SG, HT, OV, IF, BB, WD, SL, GC, GT, RF, MT, IM, GD and IV, **not run — an agent cannot**), `docs/verification/voiceover-script.md`.
- **Public-API inventory:** `docs/probes/closeout-public-api.sh` censuses every
  public declaration; `closeout-inventory-map.tsv` classifies each (A
  SwiftUI-aligned / D divergence / M MetalUI-only / X deprecated / R absent).
  **A new public declaration owes a map row and a doc comment**:
  `zsh docs/probes/closeout-inventory-check.sh` and
  `zsh docs/probes/closeout-undocumented.sh` both print nothing when complete.

## Build and test

```bash
swift build
swift test --no-parallel
swift build --build-system native --build-tests && swift test --build-system native --no-parallel  # guards run
swift run MetalUIDemo            # and -c release
METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run MetalUIDemo   # value exactly "1"
# also METALUI_TEXT_INPUT_DEMO=1, METALUI_CONTROLS_DEMO=1, METALUI_DND_DEMO=1, METALUI_LOOKS_DEMO=1, METALUI_METALVIEW_DEMO=1, METALUI_MENUS_DEMO=1, METALUI_SERVICES_DEMO=1, METALUI_LIST_DEMO=1, METALUI_RICH_TEXT_DEMO=1, METALUI_CANVAS_DEMO=1, METALUI_APP_SHELL_DEMO=1, METALUI_SELECTION_DEMO=1, METALUI_INVALIDATION_DEMO=1
METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
```

- **Counts (2026-10-13, `perf/incremental-invalidation` from `f6f865c1`, merged with master `d279f34d` (§101, §103, §105-§107): 3654 tests run + 9 skipped (3663 expected unfiltered), 0 goldens, 232 typecheck guards** (master's 3631 + the branch's 32 tests (baseline +1, lane 1 +16, lane 2 +15), 229 + 3 guards 1.13, 2.11a, 2.11b; `swift package clean`, native run on a **locked screen with `AppKitPresentationTests` skipped** because its `NSOpenPanel.init()` hangs there, 0 recorded issues, 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`; census 3492 re-recorded after the merge; inventory and undocumented scripts print nothing; divergence 346 added, 152 live; the fourteen images 0 px against `f6f865c1` at the lanes, not re-taken after the merge; record §104 §6). Before it,
- **Counts (2026-10-13, `docs/guides-followup` from `b17aee19`, merged with master `8e7c78e3` (§105 performance baselines, §106 `runUntilIdle()` on Linux): 3631 tests, 0 goldens, 229 typecheck guards** (master's 3626 + 5 tests, no guard; 3629 before the merge; `swift build --build-system native --build-tests` then the native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else, 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`; no `Sources/` or `Backends/SDL` change, no public declaration, no divergence label taken; record §107). Before it,
  **(2026-10-13, `fix/rununtilidle-linux` from `848ee029`, merged with master `b17aee19` (§103 guides): 3626 tests, 0 goldens, 229 typecheck guards** (master's 3624 + 2 tests, no guard; `swift package clean`, native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else, 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`; no public declaration, census unmoved; the fourteen images 0 px against `848ee029`; no divergence label taken; the two mutations were run in the Linux image, the macOS `set(nil)` one on a filtered set; record §106 §5). Before it,
- **Counts (2026-10-13, `docs/guides` from `ff8a1ea4`, merged with master `848ee029` (§98, §99, §100, §101, §102): 3624 tests, 0 goldens, 229 typecheck guards** (master's 3582 + 42 tests, no guard: the doc-check's 9, lane 1's 17, lane 2's 16; `swift package clean`, native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else, 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`; inventory and undocumented scripts print nothing; no public declaration, census unmoved; no `Sources/` or `Backends/SDL` change, the fourteen images 0 px; no divergence label taken; the Linux image ran the 26 lane-1 tests, the full suite not re-taken there; record §103 §5). Before it,
- **Counts (2026-10-13, `feat/material-followups` from `930db4a`, merged with master `7f891629` (§99, §100), then `0fb2ea6e` (§98), then `f6f865c1` (§102 input-method driver): 3582 tests, 0 goldens, 229 typecheck guards** (master's 3566 + 16 tests, 225 + 4 guards; 3565 / 228 at `0fb2ea6e`'s merge; lane A's 4 tests and 2 guards, lane B's 12 tests and 2 guards; `swift package clean`, native run 0 `Issue`, 0 `error:`, `FR-J no-argument frame: succeeded=true`; inventory and undocumented scripts print nothing; the fourteen images scene-identical, 0 px against `930db4a`; divergence 315 added, 249 retired, 151 live after §102; `Backends/SDL` and the Linux image not re-taken; record §101 §6). Before it:
  **(2026-10-12, `feat/ime-driver` from `3fce05f`, merged with master `ff8a1ea` (§100 continuing press cancel), then `7f891629` (§99 text over a GPU surface), then `0fb2ea6e` (§98 resign on press): 3566 tests, 0 goldens, 225 typecheck guards** (master's 3549 + 17 tests, 224 + 1 guard 3.4; 3530 / 222 at `ff8a1ea`'s merge, 3546 / 223 at `7f891629`'s; `swift package clean`, native run 0 `error:`, `FR-J no-argument frame: succeeded=true`; census 3453 (3446 + 7: the input-method verbs and read-backs); divergences 325, 326 added, 151 live after §99; record §102 §5). Before it:
  **(2026-10-12, `feat/resign-on-press` from `5f35df6`, merged with master `ff8a1ea4` (§94 backdrop blur, §96 text selection, §97 window drag, §100 continuing press cancel), then `7f891629` (§99 text over a GPU surface): 3549 tests, 0 goldens, 224 typecheck guards** (master's 3529 + 20 tests, 222 + 2 guards; 3533 / 223 at `ff8a1ea4`'s merge; `swift package clean`, native build and run 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`, no issue recorded; inventory and undocumented scripts print nothing, one public family; the fourteen images 0 px against `5f35df6`; divergence labels 285–294 unused, no divergence; record §98 §2). Before it:
  **(2026-10-12, `feat/surface-text` from `d6a815c`, merged with master `3fce05f` (§96 text selection, §97 window drag), then `ff8a1ea4` (§100 continuing press cancel): 3529 tests, 0 goldens, 222 typecheck guards** (master's 3513 + 16 tests (3520 at `3fce05f`'s merge), 221 + 1 guard 1.11: lane 1's 11, lane 2's 5; `swift package clean`, native run on an unlocked screen, all passed, 0 `error:`, the only `warning:` SwiftPM's deprecation notice; `FR-J no-argument frame: succeeded=true`; census 3452 (3446 + 6); divergences 295, 296 added, 149 live; the fourteen images scene-identical, 0 px against `d6a815c` at both lanes; `Backends/SDL` untouched; record §99 §7).
  Before it:
  **(2026-10-12, `fix/continuing-press-cancel` from `930db4a`, merged with master `3fce05f` (§96 text selection): 3513 tests, 0 goldens, 221 typecheck guards** (master's 3504 + 9 tests, no new guard; `swift package clean`, native run 0 `error:`, `FR-J no-argument frame: succeeded=true`, no issue recorded; census 3446 unmoved, no public declaration; no divergence label taken); record §100 §3). Before it:
- **Counts (2026-10-12, `feat/text-selection` from `0abce86`, merged with master `930db4a` (§93–§95, §97): 3504 tests, 0 goldens, 221 typecheck guards** (master's 3472 + 32 tests, 218 + 3 guards G1–G3; `swift package clean`, native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else, 0 `error:`; census 3446 (master's 3424 + 22); divergences 265, 266 added, 147 live; the merge's one source edit `Window.onInput` keeps both the selection `defer` and master's modifier report; record §96 §5). Before it:
- **Counts (2026-10-12, `feat/window-drag` from `a720fba`, merged with master `5f35df6` (§95 `ForEach` identity), then master `d6a815c` (§94 backdrop blur): 3472 tests, 0 goldens, 218 typecheck guards** (master's 3446 + 26 tests, 217 + 1 guard 3.2; at `5f35df6`'s merge 3441 / 217; native run after `swift package clean` on a locked screen read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else; census 3415 (3405 + 10: `WindowDragGesture` and its members, `performWindowDrag`, `windowDrags`, `performsWindowDrag`; the tsv re-recorded after the merge for AppKit's line shifts); divergences 275–277 added, 145 live after §94, next label 206; `Backends/SDL` 24 + 114 on macOS (113 + 1), the Linux image not re-taken after the merge; the fourteen images 0 px against `a720fba` on the merged tree; record §97 §4, §6). Before it,
  **(2026-10-12, `feat/backdrop-blur` from `f2fe54a`, merged with master `5f35df6` (§91 harness, §92 overlays, §93 input follow-ups, §95 `ForEach` identity), then record 94 §11's three pins: 3446 tests, 0 goldens, 217 typecheck guards**
  (master's 3415 + 28 tests, 216 + 1 guard: lane 1's 16 (8 record, 3 scene, 4 reference, 1 guard), lane 2's 12; `swift package clean`,
  native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, the
  default build system 0 `warning:`; census 3414 (3405 + 9); `Backends/SDL` 30 + 123 on macOS (30 + 120 in the Linux image, branch checker; lane 3's 10 `SDLBackdropTests` and
  the `ReplayFixtureTests` growth), replay parity re-taken by the branch checker after the merge: 12 fixtures, SDL Metal 0 px,
  Windows D3D12 unmeasured (CI); divergences 245–249 added, 166 amended, 142 live; the fourteen images 0 px; record §94 §5, §7). Before it,
- **Counts (2026-10-12, `fix/foreach-identity` from `280d706`, merged with master `a720fba` (§92 overlays, §93 input follow-ups): 3415 tests, 0 goldens, 216 typecheck guards**
  (master's 3402 + 13 tests, 215 + 1 guard `G1`; native run after `swift package clean` on a locked screen read exactly the five
  `AppKitPresentationTests` sheet issues and nothing else; census 3361 + master's growth, count unchanged by this branch; divergence 79 retired, 255
  added, header's count 137 live; the fourteen images 0 px against `280d706` before the merge; record §95 §2). Before it,
- **Counts (2026-10-12, `feat/input-followups` from `f2fe54a`, merged with master `0abce86` (§91 harness, §92 overlays): 3402 tests, 0 goldens, 215 typecheck guards** (master's 3363 + 39 tests = 18 + 11 + 10 by lane, 213 + 2 guards, both lane 1's; native run after `swift package clean` on a locked screen read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else; census 3405 (3392 + 13); `Backends/SDL` 24 + 113 on macOS, 24 + 110 in the Linux image at the lane runs, not re-taken after the merge; divergences 235, 236, the header's count and next label the merge's; record §93 §4). Before it,
- **Counts (2026-10-12, `feat/overlays-coords` from `ebcf3c7`, merged with master `280d706`: 3363 tests, 0 goldens, 213 typecheck guards**
  (master's 3312 + 51 tests, 208 + 5 guards; the native run after `swift package clean` read exactly the five
  `AppKitPresentationTests` sheet issues of `CI-AF` on a locked screen and nothing else; census 3392 (3356 + 36);
  the fourteen images 0 px against `ebcf3c7`; divergence 225 added, the header's count and next label the merge's;
  `Backends/SDL` untouched; record §92 §2). Before it, **(2026-10-10, `feat/test-harness` from `70e9389`, merged with master `f2fe54a` (`SG-M`): 3312 tests, 0 goldens, 208 typecheck guards (3310 + the two §14 pins, record §91 §14)**
  (master's 3237 + 73 tests, 205 + 3 guards: lane 1's 37, lane 2's 30, lane 3's 5, the merge's 2.31; native
  `--build-system native` run all passed after `swift package clean`, the default build system 0 `warning:`; census 3356 (3134 +
  the product's 222); root in `swift:6.4-noble` 9 + 40 + 21 + 199 + 78 + 22 plus `MetalUITestingTests` 72; `Backends/SDL` untouched
  by this branch; the fourteen images 0 px against `70e9389` at lanes 1 and 3; record §91 §12). Before it,
  **(2026-10-10, `fix/smk-port-gaps` from `0b400b4`, merged with master `ebcf3c7`, then `SG-M` (File ▸ Close and Quit, +2): 3237 tests,
  0 goldens, 205 typecheck guards** (master's 3204 + 33 tests, 203 + 2 guards; 3237 re-measured clean by the orchestrator on `e1937ea`, record §89 §14; native run on an
  unlocked screen, all passed; census 3139 (3134 + 5); `Backends/SDL` 24 + 111 on macOS, 24 + 108
  in the Linux image; root in `swift:6.4-noble` 9 + 38 + 21 + 199 + 78 + 22; the fourteen images 0 px against
  `ebcf3c7`; divergence 195 added, 134 live, next label 206; the merge's pins were two typecheck
  fixtures and four SDL `Platform` wrappers; record §89 §10, §11). Before it, **(2026-10-10, `perf/shadow-cache` merged with master `0a9eb36` (key-focus, §88): 3204 tests, 0 goldens, 203 typecheck guards (3173 + the branch's 31 tests, 202 + 1 guard; all passed unlocked; census 3134; divergences 133 live, next label 206)** (record §90 §7). Before it, the branch alone, (2026-10-10) `perf/shadow-cache` from `2155f1e`, merged with master `70e9389`:
  3100 tests, 0 goldens, 196 typecheck guards (master's 3069 + 31 tests (3099 at the checker, + its owed C1 pin L2.13, record §90 §6), 195 + 1 guard; native
  run on an unlocked screen, all passed; census 3023 (3021 + the two `compositingGroup()`
  functions); divergence 205 added beside master's 175, 176, the header's count and next label
  the merge's; `Backends/SDL` 24 + 105 and root in `swift:6.4-noble` 6 + 35 + 21 + 199 + 67 + 22 in the Linux image, unmoved by this branch; record §90 §3). Before the merge, lane 2 at `ef3b11c`: 3051 tests (3021 + 30;
  lane 1 at `31c88a4`: 3037), one new guard. Before it, **2026-10-09, `feat/app-shell` from `c62d6ba`, merged with master `2155f1e`:
  Master before the merge, (2026-10-10) `feat/key-focus` from `c62d6ba`, merged with master `70e9389`: 3173 tests, 0 goldens, 202 typecheck guards (master's 3069 + 104 tests (3172 at the checker, + its owed MX2 pin, record §88 §13), 195 + 7 guards; record §88 §11). Before it, (2026-10-09) `feat/app-shell` from `c62d6ba`, merged with master `2155f1e`:
  3069 tests, 0 goldens, 195 typecheck guards** (master's 3021 + 48 tests, 192 + 3 guards;
  the native run on a locked screen read exactly the five `AppKitPresentationTests` sheet
  issues and nothing else; census 3021 (2977 + 44); `Backends/SDL` 24 + 108 on macOS, 24 + 105
  in the Linux image; divergences 175, 176 added, the header's count and next label the merge's;
  record §87 §12). Before the merge, the lanes on `c62d6ba`: 2921 / 0 / 188 (2873 + 48, 185 + 3;
  `Backends/SDL` 24 + 107 on macOS, 24 + 104 in the Linux image). Before it, `feat/controls-looks`
  from `cd84b0c`, merged with master `67a579e`, then
  `0b400b4` (`GX-X`, +6 tests) and `9ad2254` (`GX-Y`, +5 tests): 3021 tests, 0 goldens, 192 typecheck guards (measured on the merge, all passed); at `0b400b4`'s merge: 3016 tests, 0 goldens, 192 typecheck guards (+ `GX-X`'s 6 and
  3 merge pins; `cutToEntryClip` gains `.gradient`/`.blur` arms; record §85 §4.7); **at `67a579e`'s merge:
  3007 tests, 0 goldens, 192 typecheck guards** (master's 2873 + 134 tests, 185 + 7 guards;
  the native run on a locked screen read exactly the five `AppKitPresentationTests` sheet
  issues of `CI-AF` and nothing else; census 2977; divergences 165–169 and 171 added, the
  header 126 live, next label 175; `Backends/SDL` 24 + 99 on macOS, 24 + 96 in the Linux
  image, root in `swift:6.4-noble` 6 + 35 + 18 + 199 + 67 + 22; the merge's one source
  edit `RichTextTests`' `ValueTrackTarget(edit:)`; record §85 §4). Before the merge, the lanes on
  `cd84b0c`: 2857 / 0 / 183 (2723 + 134, 176 + 7; census 2711). Master's `GX-Y` (`fix/clip-nested-flattening` from `0b400b4`): 2884 / 0 / 185 (2879 + 5, record §73 §13). Before it, `GX-X` (`fix/clip-in-flattening-effect` from `67a579e`): 2879 / 0 / 185 (2873 + 6, record §73 §12). Before it, `feat/input-apis` from `70ed000` merged with master `dc6528c`,
  after `CI-AL`: 2873 tests, 0 goldens, 185 typecheck guards (the merge's 2870 + `CI-AL`'s
  3 tests, no guard; `Backends/SDL` and the image not re-taken, untouched; record §81 §4.7).
  On the merge itself, `1337ff6`: 2870 / 0 / 185 (2790 + 80 tests, 180 + 5 guards;
  census 2806; divergences 139–141 added beside master's 145–158, the header 120 live,
  next label 159; `RichTextTests`' `Handlers` member count 17 → 18 with a `pointer`
  arm, the merge's one source edit; `Backends/SDL` 24 + 98 on macOS, 24 + 95 in the Linux
  image, root in `swift:6.4-noble` 6 + 35 + 18 + 199 + 67 + 22, re-taken by the branch
  checker; record §81 §4, §4.5, `CI-AK`). Before the merge,
  on `409de1a`: 2752 / 0 / 180 (2672 + 80, 175 + 5; census 2657; `Backends/SDL`
  24 + 93 on macOS, 24 + 90 in the Linux image).
  Before it, `feat/rich-text` from `70ed000`, merged with master `5d6893a`:
  2790 tests, 0 goldens, 180 typecheck guards** (2723 + 67 tests, 176 + 4 guards: five
  new, `textBoldIsNotOffered` re-spelled; census 2685; the lanes' own sums 2672 + 20
  + 27 + 20 = 2739 before the merge; `Backends/SDL` 24 + 84 on macOS, 24 + 81 in the Linux image
  before master's §86 fix (24 + 88 / 24 + 85 after it, record §86 §4),
  root in the image 6 + 35 + 18 + 199 + 67 + 22; divergences 150–158 added, the header's count and next label the
  merge's; record §83 §8). Before it, `fix/accesskit-window-show` from `cd84b0c`:
  2723 tests, 0 goldens, 176 typecheck guards, unmoved (the fix is in
  `Backends/SDL`: 24 + 88 on macOS, 24 + 85 in the Linux image; census 2540
  unmoved; record §86 §4). Before it, `feat/variable-height-list` merged with `099cf80`:
  2723 tests, 0 goldens, 176 typecheck guards (2677 + 46 tests, 175 + 1 guard;
  census 2540; `Backends/SDL` 24 + 84 on macOS, 24 + 81 in the Linux image, re-taken
  after the merge; divergences 145–147 added, the header's count and
  next label the merge's; record §82 §8, §9). Before the merge, on `70ed000`: 2718 / 0 / 176. Before it,
  `fix/task-followups` from `70ed000`: 2677 / 0 / 175 (2672 + 5 tests, no guard;
  census 2536; `Backends/SDL` 24 + 84 on macOS, 24 + 81 in the Linux image; record §84 §4). Before that,
  `feat/portable-app` from `359444e`, all three lanes:
  2672 / 0 / 175 (2630 + 42 tests, 171 + 4 guards;
  census 2536; `Backends/SDL` 24 + 83 on macOS, 24 + 80 in the Linux image,
  root in the image 6 + 35 + 18 + 199 + 49 + 22; record §80 §4). Before it,
  `feat/port-gaps-medium` from `d48b26d`, all three lanes:
  2630 tests, 0 goldens, 171 typecheck guards** (2579 + 51 tests, 166 + 5 guards;
  census 2532; `Backends/SDL` 24 + 78 on macOS, 24 + 75 in the Linux container,
  lane 2's readings; record §79 §4). Before it,
  `feat/proposal-controls` from `e54c3f6`: 2579 / 0 / 166 (2546 + 33 tests,
  163 + 3 guards; census 2446; record §78 §3). Before that,
  `feat/platform-services` from `c2b8f48`: 2546 / 0 / 163 (2430 + 116 tests,
  151 + 12 guards; census 2421; `Backends/SDL` 24 + 77 on macOS, 24 + 74 in the Linux
  container, lane 3 verifier's readings; record §77 §3). Before it, at lanes 1 and 2
  (2026-10-05): 2503 / 0 / 162 (2430 + 73, 151 + 11; census 2402). Before that,
  `feat/lifecycle` from `047f0ab`: 2430
  tests, 0 goldens, 151 typecheck guards (2376 + 54 tests, 147 + 4 guards;
  `Backends/SDL` 24 + 65; census 2315; Linux container
  199 + 22 + 36 + 31 + 18 + 6, record §76 §9). Before it,
  `feat/colour` from `30a3dbf`: 2376 / 0 / 147 (2328 + 48 tests, 142 + 5 guards;
  `Backends/SDL` 24 + 63; census 2305; Linux container
  199 + 22 + 36 + 31 + 18 + 6, record §75 §2). Before that,
  `feat/menus-popovers` from `b9da519`: 2328 / 0 / 142 (2227 + 101 tests, 133 + 9 guards;
  `Backends/SDL` 24 + 62; census 2206; Linux container
  199 + 22 + 21 + 31 + 18 + 6, unmoved, record §74 §6). Before it,
  `feat/paths-shadows-transforms` from `dc96395`: 2227 / 0 / 133 (2124 + 103 tests, 129 + 4 guards;
  `Backends/SDL` 24 + 57; census 2086 in 105 families, record §73 §9). Before it,
  `fix/scaffold-review` from `6c05f3d`: 2124 / 0 / 129 (2112 + the review fixes' 12 scaffold
  tests, record §72 §6.6). Before that, `feat/scaffold` on master `65c0cc7`:
  2112 (master's 2093 + the scaffold's 19, no guard added; master's own were taken on `feat/metal-view` after merging
  `95234db`: 2072 + 21 tests, 128 + 1 guards); `Backends/SDL` 23 + 55 (branch 23 + 48, master's icon tests +7); public census 2000 in 101 families;
  Linux container 199 + 22 + 21 measured on the branch before the merge
  (`swift:6.4-noble`; MetalView's seven portable `SurfaceTargetTableTests`;
  master's own line reads 199 + 22 + 14, so the app icon added no portable
  test — not re-taken after the merge). A count is stale the moment a test
  lands — re-measure (`swift package clean`, native build, unfiltered
  `--no-parallel` run). History: record §66, §67, §68, §70, §71 (§11, the
  merge), §72, §73, §74, §75, §76, §77, §78, §81, §82, §83, §84, §85, §87, §88, §89, §90, §91, §92, §94, §98, §99, §101, §102, §103, §104, §106.
- **Read the printed counts, never the exit status.** Native prints one
  summary line ("in 3 suites"); the default build system may print several
  (sum them). Thirteen env-gated oracle/measure/build tests count while skipped.
- **`--no-parallel` always**: CoreText font registration and `malloc_logger`
  tests race under a parallel run. **Adding an AppKit test? Run the whole
  suite unfiltered** (`--filter` is a different program).
- **Guards skip silently** unless `.build/<triple>/debug/Modules` is where
  `#filePath` expects (default build system, `--scratch-path`, `-c release`
  all skip; the total does not move). Take guard counts under
  `--build-system native` and grep the log for
  `FR-J no-argument frame: succeeded=`. macOS CI sets
  `METALUI_REQUIRE_GUARDS=1` so a skipped guard fails (`CX-J`). Two helpers:
  `typecheck(_:importing:)` (fixture wrapped in a function) and
  `typecheckFile(_:importing:)` (whole-file Swift 6). **A guard about what an
  external module can write uses `typecheckFile` with a plain import** (`SA-P`).
- **`swift package clean` when the impossible happens** (SIGSEGV, no summary
  line, an impossible value, `Undefined symbols … direct field offset`):
  causes are the untracked shader header symlink
  (`Sources/MetalUIShaderTypes/include/`) and any new case/stored property on
  a public type crossing a module boundary.
- **No goldens, ever again** (stage 7a): a layout fact gets a native arm. No
  text fixture, ever (TX-B). `find Tests/MetalUILayoutTests -name "*.json"`
  reads 0 (not `find Tests` — `PortableTests/.build` holds JSON).
- **The manifest is two lists** (`PC-A`): targets importing no Apple framework
  are declared on every platform; the rest under `#if os(macOS)`. A new target
  goes in the list its imports allow. Linux/Windows CI build every portable
  target and run `MetalUILayoutTests`, `MetalUICoreTests`,
  `MetalUICrossPlatformTests`. A Darwin-only test there is gated per
  declaration with `#if canImport(Darwin)` (`PC-B`).
- **`Backends/SDL`** is a package (`MetalUISDL`) whose library targets the
  root manifest also declares by `path:` (`PX-H`, below). It links AccessKit's
  C bindings, fetched not vendored (`AX-A`): run
  `python3 Backends/SDL/scripts/fetch-accesskit.py` once, then from
  `Backends/SDL` build/test with `swift test $(python3 scripts/fetch-accesskit.py
  --print-flags)` (**not** `PKG_CONFIG_PATH`: the pkg-config route is gone,
  `PX-I`). macOS CI does not run its tests.
- **Windows locally: the UTM VM** (Windows 11 ARM64, where the machine has
  one; `ssh metalui-win`, PowerShell — `utmctl exec` does not work, ARM64 guest
  tools ship no `qemu-ga`). It runs the CI Windows jobs' commands with SDL's
  `lib\arm64` and AccessKit's ARM64 prebuilt. **Clone with `git clone -c
  core.symlinks=true`** — the shader header is a git symlink and a plain clone
  fails at its line 1. **SDL window tests, `PortableReplay` and `DemoCapture`
  fail over SSH** (session 0, DXGI `0x887A0022`): run them in the console
  session through a temporary `-LogonType Interactive` scheduled task, then
  unregister it. Scripts copied to it are ASCII-only (PowerShell 5.1). Fixtures
  come from `swift run Replay --portable --record` on the Mac. Baseline on
  `c2b8f48`: root 311 (Linux's minus the compiled-out legacy-symbol test),
  PortableTests 32, `Backends/SDL` 24 + 62 (three are macOS-only), replay 8/8
  on WARP.
  **x64 (CI's architecture) runs there under emulation**: `--build-system
  native --triple x86_64-unknown-windows-msvc --scratch-path .build-x64` —
  **the default build system ignores `--triple` and silently emits ARM64**
  (check the PE machine reads `8664`). Running needs the x64 Swift runtime,
  extracted from `Redistributables\6.4.0\rtl.shared.amd64.msm` (`MsiDb.exe -x
  MergeModule.CABinet` under `Start-Process -Wait`, then `expand`), plus the
  SDK's `Testing-6.4.0\usr\bin64` and `XCTest-6.4.0\usr\bin64` first on
  `PATH`, SDL's `lib\x64` and AccessKit's `x86_64` library passed by hand.
  Same counts and pixel deltas as ARM64 on `c2b8f48`.

### Targets and import rules (each fails silently on macOS)

Twenty-four one-way-dependent targets (`MetalUIPath`, `GX-B`, the last two
`MetalUIScaffold` and `MetalUICLI`, `SC-A`, and portable `MetalUITesting`, which imports
only `MetalUI` and `MetalUIScene`, `HT-A`) plus `Tests/MetalUITestSupport`;
`MetalUIDemoContent` holds the demo tree so tests can import it (`LR-S`).
Linux/Windows CI (`scene-linux`, `root-windows`) is the only place most of
these violations show.

- `MetalUILayout` imports only `MetalUICore` and declares no `Style` (`LR-FM`).
- `MetalUIScene` imports only `MetalUIShaderTypes` (`PS-A`); an initialiser
  that must stay unspellable outside the package is `package`, with a
  plain-import guard (`PS-D`, `PS-E`).
- `MetalUIFreeType` imports only `MetalUIScene`, `CFreeType` (`FT-K`).
  **`MetalUIPath` imports nothing** (no Foundation, no `MetalUICore`; `package`
  API; `GX-B`) — its coverage is bit-identical on every platform because its
  trigonometry is its own `PathMath.sinCos`; a libm call or a Foundation import
  there breaks that silently on macOS.
  `MetalUIHarfBuzz` imports only `CHarfBuzz` (`SH-K`). `MetalUITextSystem`
  imports only `MetalUIScene` (`TS-A`). `MetalUIPortableText` imports only
  `MetalUIScene`, `MetalUIShaderTypes`, `MetalUIHarfBuzz`, `MetalUIFreeType`,
  `CUnibreak`, `MetalUITextSystem` (`PT-A`). **`MetalUISystemFonts` is the one
  text target with Foundation/a file system** (`SF-A`); system faces are lazy
  and outside the cascade unless a platform fallback family (`SF-B`, `SF-C`).
- `MetalUIPlatform` is portable (`MetalUICore`, `MetalUIScene` only);
  `MetalUIRender` depends on it; the AppKit platform is `MetalUIAppKit`
  (`RS-C`), sharing one `Renderer` across windows. Windows draw through
  `PlatformWindow.renderer` (`RS-A`). Inside `MetalUI`, CoreText stays behind
  `#if canImport(MetalUIText)`.
- **`PlatformWindow`'s defaultless requirements** — `onAccessibilityRequest`,
  `publishAccessibilityTree(_:)`, `controlActiveState`/
  `onControlActiveStateChange`, `accessibilityReduceMotion`/
  `onAccessibilityReduceMotionChange`, `accessibilityReduceTransparency`/`onAccessibilityReduceTransparencyChange` (`MT-D`), `beginExternalDrag(_:at:)`, `presentMenu(_:at:) -> Bool`, `setPreferredColorScheme(_:)` (`CR-M`), `presentFileDialog(_:) -> Bool`, `presentAlert(_:) -> Bool`, `dismissPresentation(token:)`, `setContentSizeLimits(minimum:maximum:)` (`SV-B`), `setToolbar(_:) -> Bool` (`MD-J`), `setPointerStyle(_:)` (`CI-J`), and the app shell's seven — `onCloseRequest`, `close()`, `setDocumentEdited(_:)`, `setRepresentedFilePath(_:)`, `setTitleBarStyle(_:) -> Bool`, `titleBarInsets`, `performTitleBarPress(clickCount:) -> Bool` (`AS-H`, `AS-J`), and `performWindowDrag() -> Bool` (`WD-E`) — have no
  default so a conformer that forgets one fails to compile. Both conformers,
  the headless `HeadlessPlatform*` of `MetalUITesting` (**a new requirement owes it an honest
  answer in the same change**, `HT-X` 1) and every test fake implement all of them. **`Platform` (not a window) has
  six: `setApplicationIcon(_:)`** (`AI-B`), **`setMenuBar(_:) -> Bool`** (`MN-I`, `SG-A`: `true` when the platform shows the bar) **and the app shell's
  `onTerminateRequest`, `replyToTerminateRequest(_:)`, `terminate()`, `onOpenURLs`** (`AS-H`), beside it for the same reason,
  and so does **`WindowRenderer.finishFrame(scene:atlas:surfaces:)`** (`MV-F`
  item 1; the two-argument spelling forwards `surfaces: []`). **`TextSystem` has
  three** since rich text (styled measure, styled layout, decoration metrics,
  `RT-F`): a third-party conformer must add them (`docs/migration.md`).
- Every `LayoutTree` that could exchange ids needs a distinct `generation`
  (C-3); `Frame` is the only `Sources/` constructor.
- Pixel format is `bgra8Unorm`, never `_sRGB` (§7.8).
- Percentage `padding` resolves against the containing block's **width** on
  every edge; `Style.inset` horizontal-vs-width, vertical-vs-height (AP-D).

### Portable text rules (measured against CoreText — re-run the oracle before simplifying)

- `PortableFont` opens one file in FreeType and HarfBuzz and checks they agree
  (`PT-B`). Metrics are `hhea`'s; TrueType metrics round to a 16.16 fraction
  of the em; design units scale `units × (size / unitsPerEm)`; `drawnGlyph`
  drops default ignorables and draws the space glyph for controls/hard breaks.
- Line breaking is libunibreak under `"en-strict"` (`LB-A`, `LB-L`); the four
  fitting rules of `LB-D` are measured.
- **Every shaping path goes through `shapeCascading`** (`FB-A`) — calling
  `HarfBuzzShaper` directly loses fallback. Runs split by bidi level and
  script (`BD-B`, `BD-C`).
- The subpixel placement rule lives once, in
  `GlyphImage.subpixelPlacement(forDeviceX:)` (`PT-C`) — never re-inline it.
- The portable package's Arabic case is the only test that sees a shaping
  offset (`PT-H`).

## Architecture rules

Detail, pinning tests and history for each paragraph: record §69 (same
heading), §19, §01.

**Phases.** `requestLayout` → `prepaint` → `paint`. `isHovered`, `isActive`,
`isFocused` exist only on `PaintPass`, each typecheck-guarded; a new
paint-only query gains a guard and a bullet in `PhaseSeparationTests.swift`'s
header.

**Identity is structural; `.id()` overrides a position, never joins it.**
- An `if` with no `else` and a `for` loop/`ForEach` each take **one**
  structural slot whether or not they produce content (`ID-B`). Content an
  evaluated conditional or loop removes is **reset on return** (`ID-C`,
  `DD-C`), except `$focus`/`$ax`. An **unevaluated** conditional (a `List` row
  out of window) keeps its state (`TB-AH`).
- `.id(_:)` works on every element group via `IdentifiedGroup` (`ID-G`); a
  `StyledElement`'s own `id(_:) -> Self` wins where both apply. **`.id()` must
  be the outermost modifier.** A name an evaluated position leaves is reset
  unless produced elsewhere this frame (`ID-R`). **A new site that mints a
  named id owes a `StateTable.noteNamed` call and an arm in
  `everyNamingSiteStartsAReturningNameFresh`.** All resets run in one pass per
  `sweep()` (E3.13).
- Modifiers are one flat `ModifiedContent<Content, Modifier>` (stage 11;
  `ModifiedElement` is its legacy typealias): each modifier is one layer = one
  node = one id level; outermost takes the parent's slot, inner layers
  `positional(0)` (`MC-A`, `MC-C`). Changing layer **count** resets the
  wrapped element's state; changing values does not. A decoration written
  after a wrapper configures the outermost layer (`OM-C`).
- `.overlay`/`.background(alignment:content:)`: primary under the modifier's
  id, attachment under `.child(of: id, at: -1)` (`MC-P`, `ID-J`); nothing else
  may mean `-1`. A primary of zero or several nodes traps (divergence 73).
- `GlobalElementID.cachedHash` and `==` are safe alone, unsafe together; do
  not simplify `==`'s chain walk on a green suite.
- Prefer SwiftUI's answer where SwiftUI and CSS differ (EP-5).

**Legacy containers.** `Column`/`Row` centre the cross axis, `Box` stretches
(EP-8). **Modifier order decides which box a modifier reaches**: container and
item modifiers (`.alignItems`, `.gap`, `.flexGrow`, `.margin`) **before**
`.padding`; `.frame`, background, corner radius **after**. All wrong orders
compile. `Row`/`Column` gap is 0 vs `HStack`/`VStack`'s 8 (divergence 52) —
porting `Row {}` → `HStack {}` changes layout silently.

**Legacy `.frame`** has SwiftUI's full surface and lowers to one `Style` in
`FrameLayer.swift` `FrameSpec.style()` (`FR-C`); fixed axes via `size` +
`minSize` (never `flexShrink = 0`, `FR-P`); fill only when both maximums are
infinite (`FR-O`). `ElementGroup` keeps exactly **one** fixed `frame`
overload (`FR-S`). The two `frameStyle` oracles in `ModifiedElementTests`/
`ModifierCompositionProofTests` must change with the lowering. A greedy
frame's lower bound is its content: `.frame(minHeight: 0, maxHeight: .infinity)`
to answer below it (`LR-ET`).

**Sizing modifiers** (`width`, `height`, `min/max…`, `fraction:`) are
deprecated toward `.frame` (`FR-I`); the conversion recipe R1–R8 is `LR-ES`.
A test that needs a raw `Style` size write uses `Tests/MetalUITests/CSSSizing.swift`;
a new test that sizes a box writes `.frame`. `Component.width`/`height` are
**not** deprecated (one frame per member, `LR-BG`).

**`List`** is a windowed `Box`: `Identifiable` data, uniform `rowHeight`,
inside an enclosing `ScrollView`; windows against its own measured origin
(`DD-F`) and asks for one more frame when the window would grow. Height
answer is `rowHeight × count`, not SwiftUI's greedy one. Rows out of window
>2 generations lose `@State` once the table exceeds 256 entries (TB-AH) — keep
durable values in data. `List(selection:)` (`DD-Z`): reads the binding fresh
every frame, never prunes; click selects and focuses the list; ⌘/ctrl
toggles, ⇧ ranges; selection logic runs in input handlers so a warm frame
stays O(window). **`List(_:rowContent:)` sizes rows from content** (`VL-`,
record §82): each row exactly its content's height at the list's width (divergence 145),
the extent measured rows plus an estimate (divergence 147) through a per-list
`RowExtentIndex` (Fenwick prefix offsets, heights by id) in `ListOrigin`, the
row on top anchored across measurements and data changes by
`Frame.noteScrollAnchorAdjustment` after paint (`VL-G`, divergence 146); the
`rowHeight:` spelling is the untouched fast path (`VL-I`) — a change to one
branch must leave the other's pins and work literals unmoved.

**Controls** (`Button`, `Toggle`, `Slider`, `Stepper`, `Picker`, selectable
`List`) sit on `Binding` and the existing handler machinery: one hitbox each,
all focusable (Tab reaches them; **a click does not focus them**, divergence
94), one keyboard table `ControlKeys.swift` running after a caller's `onKey`
declines, the `.disabled` gate in `Frame.registerHandlers`. Accents and focus
rings read `controlActiveState` (`ControlLook.swift`). `Button` has `role:`,
`.buttonStyle` (`.plain`/`.borderless` drop chrome by value), a pressed wash
and `.keyboardShortcut` (fires even when hidden; gated by `isEnabled` only).

**`ScrollViewReader`/`scrollTo`** (`DD-G`…`DD-K`): one identity slot; a proxy
reaches only its own subtree; keys compared by value (`AnyHashable`); resolved
next frame against the first match; only the nearest scroller moves.

**`Deferred`** is a portal: one child, no layout node, hoists to the root
layer, resets clip and scroll offset but **not opacity** (`OM-AA`). A
`Deferred` whose content is `.position(.absolute)` is a **presentation root**
(`LR-CH`…): laid out in its own run before the root; its containing block is
always the window. An absolute box outside a `Deferred` is a permanent
refusal by name.

**`Component`** is layout-transparent and identity-opaque: one cursor index,
`@State` under its own id. `.padding` wraps each top-level node (`OM-D`);
`.width`/`.height` frame each member; `.frame` wraps the body in one layer
(divergence 56). Token `background`/`onClick`/`focusable` are not offered —
declare them on members. Over proposal content declare
`some ProposalElementGroup`.

**`@State`** is a box seeded by reflection per element per frame; slots
`.named("$state<n>")`. **Seven reserved names** (`$state<n>`, `$focus`, `$ax`,
`$anim`, `$anim-color`; `$anim-content`/`$anim-viewport` prefixes), pinned by
`theSevenRetentionSlotsAreMutuallyDistinct` — new animation state goes in
`AnimationStore`, not an eighth slot. **Write from input, never from a phase**
(keeps the display link awake forever; a phase-time `@Observable` write is
silently stale). `$state` projects a `Binding`. One element value placed
twice resolves its own occurrence under input dispatch (`ID-F`); outside
dispatch it reaches the last-bound one (divergence 71).

**`Binding<Value>`** is SwiftUI's surface but `@MainActor` (divergence 78). A
binding write is a `@State` write. `Binding.animation`/`.transaction` apply
only when the source is `State.projectedValue`; a `Binding(get:set:)` snaps
(`AN-Z`).

**`@Observable`**: the whole frame build is tracked. The `RedrawSentinel`,
the flush ordering in `drawFrameIfNeeded`, the `isFlushing` guard and both
branches of `markDirtyFromObservation` are load-bearing (RX-K).

**Hit testing.** One hitbox list, one ranking: `topmostHitbox(in:at:where:)`
(`topmostOpaqueHitbox` is its specialization; drag-and-drop uses it too) —
**never a second lookup**. `onClick`, `textInput`, `valueTrack` make an opaque
target; the keyboard gate is separate. A wheel over a non-scrolling target
passes to its nearest same-layer ancestor scroller (`DD-Y`).
`allowsHitTesting(false)` gates only `registerHandlers`' pointer hitbox
(`OM-AK`), per layer; an accessibility press still runs (`IX-Z`).
`contentShape` takes any `Shape` (`IX-L`). Handlers outlive the frame:
`.onClick { window.x() }` is a retain cycle.

**Gestures** (`IX-B`…): `TapGesture`/`LongPressGesture`/`DragGesture` and
composition, beside (not replacing) `onClick`. One arena per press from the
one ranking plus the target's ancestors **in its own hit layer** — a
`Deferred` presentation's press does not reach a declaring ancestor's gesture
(`IX-Q`). Callbacks run under `StateDispatch`.

**Drag and drop** (`DN-`, record §68): MetalUI's own synchronous
`Transferable`/`ContentType`. A draggable is a **non-opaque** gesture-arena
member that begins on the first move. The destination is found by the one
ranking (`DN-F`); destinations register inside the disabled gate and outside
`allowsHitTesting`. **A new `StyledElement` site must paint through
`paintDecoration`** or it drags with no preview (`DN-X`). An SDL test takes
`SDL_EVENT_DROP_*` from C-exported constants and arms
`armMainRunLoopExitCheck()`.

**App icon** (`AI-`, record §70): `App.icon: [ImageBitmap]` is the one
application-wide, runtime-settable icon (default `[]` = never touch the
platform's own; every assignment calls `Platform.setApplicationIcon` once with
the list sorted smallest first and `width × height` duplicates dropped). SwiftUI
has no runtime icon API (bundle asset catalog), so it is MetalUI-only by design.
**The alpha rule**: `ImageTexture` is premultiplied sRGB — AppKit wraps the
bytes as stored (`premultipliedLast`, never re-premultiplied, `AI-E`); SDL
icons are straight alpha, so `SDLIcon.straightRGBA` un-premultiplies (`AI-F`).
SDL applies the icon to every open and later window and cannot clear it.
`AppKitPlatform.run()`'s re-assignment is unpinned (`AI-K`, human check O1).
Packaging (bundle/`.desktop`/`.ico`) is build-side: `docs/packaging.md`.
**The shader resource bundle is found by `ShaderLibrary`, never
`Bundle.module`** (`AI-N`): `MetalUI_MetalUIRender.bundle` goes in an `.app`'s
`Contents/Resources` on both build systems; a missing one makes `App.init`
throw `ShaderLibraryError.resourceMissing` naming every directory tried, not
trap. A new resource lookup in `MetalUIRender` goes through
`ShaderLibrary.resourceBundle(candidates:)` too.

**Scaffolding** (`SC-`, record §72, `docs/getting-started.md`): `metalui new`
is the `MetalUICLI` executable over `MetalUIScaffold` — Foundation only, every
declaration `package` (a tool, not API: no inventory row). `--cross-platform`
works from any source, `--local` or the URL (the SDL backend is a root-package product behind traits, `PX-J`, which supersedes `SC-C`). **A change to
`docs/packaging.md`'s recipe, `App`'s initialisers or the starter's API
changes the generated text too** — re-run
`METALUI_RUN_SCAFFOLD_BUILD_TEST=1 swift test --filter aGeneratedPackageBuildsAgainstThisCheckout`.
The default dependency is **pinned** (`SC-I`): `revision:` the merge base of
HEAD and `origin/master` in the checkout `#filePath` names, falling back to
`branch: "master"` with a note; the lookup is injected, so a test never runs
git on the checkout's history. **A refused name is a measured build failure**
(`SC-H`): add one only after generating and building a package with it.

**`StyledElement`** has four requirements (`style`, `decoration`, `elementID`,
`handlers`). A conformer calls `registerAndScope(...)` in `prepaint` and
`paintDecoration(...)` in `paint`, doing its work **inside** the closures —
each half has its own per-site guard (`OM-AI`). `registerHandlers` holds the
hitbox, focus, AX record and disabled gate; skipping it makes an element
ungated and invisible to VoiceOver. **Any hook added to `Element`'s group
defaults must be mirrored per layer in `ModifiedContent` and in
`AnyElement`'s group entry** (`MC-B`, `LR-AA`). `Handlers` has **nineteen**
members (the eighteenth, `pointer`, one box for the wheel closure and the style, `CI-Q`; the nineteenth, `keyboard`, one box for the `onKeyPress` handlers, the focus interactions and the key-region flag, `KF-I`); `HandlerShape` (`ModifierTests`) and `HandlerFingerprint`
(`OuterModifierMatrixTests`) each gain a field when it gains one.

**Environment (`EV-`).** `EnvironmentScope` is layout- and
identity-transparent; nearest writer wins; **a modifier written after a scope
sits outside it** (`EV-X`). `theme` is readable only in `PaintPass`.
`@Environment` unbound silently reads defaults. `Window.environment` writes
always dirty — write from input. `theme`, `displayScale`,
`controlActiveState` and `accessibilityReduceMotion` are stamped by
`Window`/`Frame`, not sourced from `Window.environment`.
`accessibilityReduceMotion` is `public internal(set)`. `.disabled(d)` is an
`isEnabled` transform; the one gate is `Frame.registerHandlers`' 5-argument
implementation — **a new handler-registering site gains an arm in the D2
guard**. Scroll regions are outside the gate. `KeyBinding` (the keymap's
type) is unrelated to `Binding<Value>`.

**Accessibility (`AB-`, `IX-U`…).** Nothing recorded until a client activates
the window (sticky). Synthesized nodes are records (`Frame.axEmissions`),
never `axNodes` or `$ax` (`AB-U`). Every `NSAccessibility` override answers
through `mainActorAnswer(_:fallback:_:)`, never a bare `assumeIsolated`
(`AB-AE`). A hidden layer suppresses everything inside
(`Frame.suppressingAccessibilityIfHidden`). A text-painting conformer passes
`accessibleText:`. Both bridges translate every neutral field — enforced by a
`Mirror` count; a new `AccessibilityNode` field needs a row on both bridges.
Qualify `MetalUIPlatform.AccessibilityRequest` in files importing AppKit.
`AXNode.actions`/`AXActionKind` are deprecated. **An agent cannot run
VoiceOver or claim the validation** (`IX-AE`).

**Focus.** Clicking does not focus, except `TextField`/`TextEditor`, a
selectable `List` and `.focusable(interactions: .edit)` (`KF-F`). Focus leaves with its identity and does not return
(`IX-I`); a `List` row out of window keeps it. `@FocusState` writes apply from
input, before the next frame. `.hidden()` removes focus/Tab/keys but not a
keyboard shortcut. Keys go Keymap → `onKeyPress` (outermost first, `KF-C`) →
focused field's editing keys → bubbling `onKey` (controls' `ControlKeys` there) → unclaimed Tab traverses
(`FocusRegistry.tabOrder`). With nothing focused `onKey` sees nothing.

**Text input (`TI-`).** `TextField` is controlled and one line; `TextEditor`
multi-line; both take `Binding<String>`. While a field is focused printable
keys arrive as `.textInput` — **plain-letter `Keymap` bindings are silent**.
`Window.editedText` lets two edits between frames compose. Caret positions
come only from `TextSystem.caretOffsets` (`TI-E`) — never re-derive from
advances. Undo history (`TI-G`) is valid only for the text its last edit
produced.

**Text selection (`SL-`, record §96).** `TextField(_:text:selection:)`/`TextEditor(_:text:selection:)`
over `Binding<TextSelection?>` (macOS 15 like `RangeSet`; the field's state holds it type-erased,
`SL-L`) are **two-way and echo-free**: one `defer` in `Window`'s `onInput` publishes the focused field's
selection after an input that changed it (against `currentText`, under `StateDispatch`), and `prepaint`
applies a binding value that differs from the last one published (`seenBinding`); nil is never an
instruction, a write is held back while composing, a stale index clamps, and a write ends the typing
group but touches no undo stack (`SL-B`…`SL-I`). A field focused from code keeps its stored caret and
focus or resign writes nothing (divergences 265, 266). `TextInputTarget` keeps `Handlers` at 488 bytes
through class-boxed closures (`SL-M`); the demo is `METALUI_SELECTION_DEMO=1`, a root of its own (`SL-N`).

**Text.** `Text`/`ProposalText` measure and draw **only through
`Frame.textSystem`** (`TS-A`); a new text-drawing element goes through the
seam too. Fonts, weight, italic and colour resolve through **one** function,
`resolveTextStyle` (`TE-AA`) — a new text element must call it for both
measure and paint. A finite height proposal caps lines (`textLines`). Never
key a cache on a family or PostScript name — use `FontKey` (its `==` uses the
stored hash as early reject only). `FontResolver.resolve` traps on
non-finite/non-positive sizes. `fonts`/`resolvedFonts` are never swept — move
both or neither. The glyph atlas is grow-only; `evictUnusedSince` has no
caller and would strand pixels. Baseline alignment works in a horizontal
stack only.

**Rich text (`RT-`, record §83).** Styled runs in one `Text` cross the seam as
`StyledText` (`MetalUITextSystem`, Foundation-free: text plus runs of
`TextRunStyle` and paint indices; zero-length runs dropped, equal neighbours merged,
a length mismatch traps) through **three defaultless `TextSystem` requirements**
(styled measure, styled layout, decoration metrics) that every conformer and test
fake implements (`RT-F`). **A one-run unstyled `Text` takes the plain calls byte for
byte** — pixels and work of plain text must not move (`RT-M`, test 1.19, the
fourteen images); a `Text` with runs resolves each run once through
`resolveTextStyle`, and CoreText (one `CTTypesetter`) and the portable system
(`shapeCascading` per run, one break table, spacing once per grapheme, ligatures off
for tracked units by feature ranges) agree under the CoreText oracle. Underline,
strikethrough and background are **ordinary rects inside the text's one shadow leaf**
(no shader change, `RT-J`); colours snap (`RT-L`); a link is accent-coloured and
**inert** (divergence 150); accessibility gets the concatenated string. Markdown in
a string **literal** (`LocalizedStringKey`) is parsed by MetalUI's own inline
parser (`MarkdownInline.swift`, checked against Foundation's on 2498 sources); a
`String` value, `Text(verbatim:)` and control titles are never parsed;
`Text(AttributedString)` reads MetalUI's attribute scope (per-key subscripts, never
a generic one: `RT-D`, `RT-T`). `+` is deprecated and traps on a decorated operand
(divergence 155). `TextField`/`TextEditor` stay plain. A new `Text` modifier owes
its field to `resolveRichText`, `ProposalText` and a values test (`RT-S`); the rich
`Text`-level fields stay boxed (`TextRichBox`, the 1 MB stack, `RT-R` 4).

**GPU surfaces — `GPUSurface`/`MetalView` (`MV-`, record §71).** App code
encodes its own GPU work into an offscreen target that MetalUI composites as
an `Image` (clip, radii, opacity, layer, transitions, drag preview), through
the image pipeline with **no shader change on either renderer**. The portable
leaf is `GPUSurface(redraw:value:draw:)`, sized like `Canvas` (the proposal,
10 on a nil axis); its closure takes `any GPUSurfaceContext` and downcasts to
the backend's context (`MetalDrawContext`; `SDLGPUDrawContext` in
`Backends/SDL`); `MetalView` is the macOS-only typed spelling and traps on a
non-Metal context. **The draw contract**: `WindowRenderer.finishFrame(scene:
atlas:surfaces:)` is **defaultless**; each draw runs on the main actor inside
it, into the frame's own command buffer, **before** MetalUI's pass, and must
not commit, enqueue, present or wait (Metal traps, SDL cannot tell). **Redraw**:
`.onDemand` draws on a new target or a changed `value:` — read what the draw
depends on as `value:`, since reads inside `draw` are untracked (divergence
103); `.continuous` draws every painted frame through `noteActiveAnimation()`,
never `requestAnotherFrame()`; a hidden, zero-size, clipped or transparent
surface does no GPU work and releases its target. **Portability split**:
`MetalUIScene` holds only an opaque `SurfaceTarget` (`PS-A`: no Metal, SDL or
closure type); `MetalUIPlatform` holds `SurfaceTargetTable<Handle>`, **the one
per-window target lifecycle every renderer must use** (a copy would drift);
`MetalUIRender` and `Backends/SDL` supply `create`/`release` and composite;
targets are `bgra8Unorm`, never `_sRGB`, premultiplied, clamped to 8192,
**per window** (not on the shared `Renderer`), and are **not** `StateTable`
entries (`SurfaceRegistry`, the seven slots unmoved). **A new backend** adds the
`finishFrame` requirement, composites `.surface` runs as image runs, never adds
a submission for a surface (the fence rule), records a draw only after its
frame commits, and clears a new target. A `FixtureRun` cannot record a surface.
A draw's counter or state must be passed in, never a never-written `@State`
(re-seeded every build).

**Shapes, images, renderer.** **A new drawable capability lands in both
`Sources/MetalUIRender/Shaders/shaders.metal` and
`Backends/SDL/Shaders/replay.hlsl` identically, checked through the SDL
replay-parity harness, or it is a documented renderer constraint** — never a
silent approximation (`TE-AD`). `Shape.geometry(in:)` returns a rounded rect,
an ellipse or (`GX-D`) a `Path`; `path(in:)` and `geometry(in:)` each default to
the other, so a conformer writes one. Proposal-path `.clipShape` clips hitboxes
to the bounding rect; legacy `.cornerRadius` stays paint-only (divergence 47).
An ellipse or path clip traps (divergence 91). Renderer: no semaphore; the atlas is uploaded
**before** encode (`MetalWindowRenderer.finishFrame`). **Never release an SDL
GPU fence the GPU has not signalled** (`retire_fence`). Image textures are
cached per identity and released when a frame stops referencing them
(`TE-AF`). `Text.requestLayout` uses unguarded `MainActor.assumeIsolated` —
layout must stay synchronous on the main actor.

**Paths, shadows, transforms (`GX-`, record §73).** **A path is rasterized on
the CPU** by `MetalUIPath` (exact-area coverage, nonzero/even-odd, strokes with
caps/joins/miter/dashes) in **device pixels after the composed transform**, and
reaches the scene as an ordinary `MUIImage` (never a new primitive, no shader
change for paths); it stays a vector (`CapturedPrimitive.path`) until
`insertIntoScene`, and a window-owned `RasterCache` keyed by value hands back
the same `ImageTexture` identity on a hit (a key missing a field draws a stale
raster). **Render effects** (`.rotationEffect`/`.scaleEffect`/`.offset`) are
layout-transparent: a 64-byte `MUITransform` side table indexed from words the
primitives already have (`MUIRect.shape` bits 8…31, `MUIImage.filter` bits
8…31, `MUIGlyph.transform`; **index 0 is identity and never stored**, so no
stride or old scene byte moved); a new effect-aware primitive lands in
`shaders.metal` and `replay.hlsl` identically (`TE-AD`). One
`Frame.paintScopes` stack carries transitions, effects and shadows; an empty
stack is the old fast path. **Hitboxes follow the transform** (local rect +
inverse affine + outer clip; `Hitbox.contains` is the one test hover, gestures
and drag read); accessibility frames are the transformed bounding box
(divergence 107). A handler written after an effect shares it through the
**share floor** (a `ZStack`/overlay/background between stops it, `GX-U`).
Proposal effects are `LayoutModifier` layers (one id level each); legacy ones
return `Self` into `Decoration.renderEffects`, around the whole element
(divergence 108). **Shadows are per leaf** (a text draw's glyphs are one leaf
via `beginLeafGroup`/`endLeafGroup` — a new text-drawing site brackets its
draw), silhouette on the CPU, blur sigma = radius, a shadow never hits and a
`Deferred` stops it; text and images under a scale are resampled, not
re-rasterized (divergence 106). **A clip pushed inside a flattening effect (`.offset`, uniform
`.scaleEffect`) is local and, once mapped, cut by the clip at the effect's entry**
(`flatteningClipBase`, `cutToEntryClip`; `GX-X`, record §73 §12); **a nested flattening
effect opened before any clip is pushed inside the enclosing one has no entry clip of its own**
— the outermost's cut, after its map, covers it (`Frame.atFlatteningEntry`, `GX-Y`, §13). A new public declaration spelled
`nonisolated public` hides from the census — write `public nonisolated`.

**Shadow cache (`PF-`, record §90).** The shadow, blur, path and full-gradient rasters are keyed
**relative to a floored device anchor** (`RasterAnchor.swift`: anchor `R`, integer offset `S`,
fractional offset `f` stays in the key): the raster is a pure function of its key, cached
canonical and placed at `+S`, so a whole-device-pixel move or pan hands back the **same
`ImageTexture`** and does no CPU work; a sub-pixel move, a raster cut by its clip (mode 2: the key
holds `clip − S`) and a local mask (mode 3: 2155f1e's absolute key) miss as before (`PF-A`,
`PF-B`, `PF-J`). `keyLeaf` keys a mask only when it decides a byte (`PF-I`); **a new raster site
keys through `RasterAnchor`, never an absolute position, and its extent `E` is conservative**
(`BoxBlur.padding`, nested reach). Pixels equal 2155f1e's (0 px, fourteen images; `PF-N` records the
measured 2× rounding). `RasterCache.lastTexturesMade` joins the work counters (`PF-G`); pins count
work, never time. `.shadow`/`.blur` stay **per leaf**; one shadow of a container is SwiftUI's
`.compositingGroup()` (both vocabularies, one `LayoutModifier` layer, `PF-E`): a
`PaintScope.Kind.composite` pushed **only when a shadow or blur scope is open outside it**,
collecting leaves with their clip depths (`captureDepths`) and re-emitting them as one leaf, stopped
by a `Deferred` barrier; alone it changes nothing, and it does **not** composite an opacity
(divergence 205). `BoxBlur` in `MetalUIPath` runs over unchecked `Int32` buffers, byte-identical to
its reference copy, still importing nothing (`PF-F`).

**Input follow-ups (`IF-`, record §93).** `SpatialTapGesture.Value.modifiers` (the last
press's) and `DragGesture.Value.clickCount` (the press's, never the move's) are MetalUI-only
values (divergence 235); `onCancelled` on drag, magnify and rotate runs **once, only for a
leaf that had reported**, from a dropped primary arena, a replaced stale button or pinch arena,
a `.mouseMoved` while a button arena is live (a lost release), key loss and window close —
never for a disabled gesture or a removed owner (`IF-E`, `IF-K` 3; divergence 236; no
`@GestureState`). A wheel scroll **latches** to the cover of its `.began` through its momentum
(`ScrollLatch`, `IF-G`) and ends with a synthesized `.cancelled` to the latched handlers on key
loss or close (`IF-H`); the platforms send `.modifiersChanged` on becoming key (`IF-I`).
`onModifierKeysChanged(mask:initial:_:)` is one transparent `ModifierKeysScope` (the shape of
`GeometryChangeScope`; `$modkeys<depth>` a `LifecycleStore` key, never a `StateTable` slot):
`Window.currentModifiers` comes from every key, pointer and scroll event and the flags report,
drops to `[]` on leaving key, dirties the window **only when the last build held a scope**, and
the action runs in the lifecycle drain after the build; SwiftUI's timing is **unprobed**
(human check IF1, `IF-D`). A `.modifiersChanged` event returns before the hook's blanket
`setNeedsRedraw()` unless the app's `onInput` claims it (`IF-N` item 3).

**Window drag (`WD-`, record §97).** `WindowDragGesture` is SwiftUI's spelling (no
`.windowDragArea()`): one arena leaf, live in a **press** arena only, an opaque pointer target on
its element's hitbox, **ready at a `tapSlop` move** and blocked as a draggable is (a tap, long
press or click ahead yields, an undecided `DragGesture` ahead wins). When it acts it ends,
runs the `onCancelled` of members that had reported, fails the rest (divergence 275) and
`Window` calls the defaultless `PlatformWindow.performWindowDrag() -> Bool` then
`endPressForDrag()` **whatever the answer**. AppKit answers `true` only while dispatching the
mouse-dragged of a held primary press (`performDrag(with:)` with its mouse-down, the unproven
call, check WD1); SDL records and answers `false` (divergence 276, no hit-test region list:
`WD-F`). `AS-J`'s band drag is unchanged (unclaimed presses only); the three gates are the
gesture rule and `.opacity(0)` does not disable it (divergence 277). Not built:
`windowBackgroundDragBehavior` (a Scene modifier), a double-click zoom in a handle.

**Text over a GPU surface (`GT-`, record §99).** A `Text` overlay over a `GPUSurface` costs
1 leaf measure, 2 seam measures and 1 `placeGlyphs` per label per frame, linear in N, no raster or
upload (`GT-A`; re-take with `theOverlayCostIsLinearAndCounted`), so **`MetalDrawContext.drawText`
and its SDL twin are deferred** (`GT-F`, owner C14's close-out). `@Environment(\.textMeasurer)` is a
get-only `TextMeasurer` (no public initialiser; SwiftUI's `resolve(_:)` + `ResolvedText.measure(in:)`
carried by the environment, divergence 296) that calls the one layout measure through
`resolveTextStyle` and `Frame.textSystem`: the **unrounded** leaf answer, a laid-out frame being
it rounded; an empty `Text` is one line tall (divergence 295, `GT-I`); the frame stamps its system
box and a `\.self` reset keeps it (`GT-D`). `PortableTextSystem` caches an **origin-free**
`[LaidOutLine]` per `MeasureKey` (two-frame lifetime) so a moving plain label shapes once; rich text
still shapes per frame there (`GT-E`, `GT-H`).

**Continuing press cancel (`GC-`, record §100).** A reported leaf owes `onCancelled` whatever
ends it. `GestureArena.press(… continuing: true)` takes `cancelCallback(leaf)` before it fails an
undecided drag (`GC-B`), and `Window`'s `.mouseDown` treats a press that finds the arena **still
pressing** as a lost release, not a tap sequence's second press: `abandon()` and a fresh arena
form, as for a press on another element (`GC-C`; SwiftUI agrees, probe `swiftui-lost-release.swift`).
A real double-click (arena released) still continues. A bare `.mouseMoved` does not cancel the
primary arena (rejected, `GC-C`). No public API, no divergence.

**Resign on press (`RF-`, record §98).** `.resignsFocusOnPress(_ isEnabled: Bool = true)`
(`StyledElement` returns `Self`; proposal content merges into the one `KeyboardModifier` layer,
`KF-H`) is an opt-in container modifier: a primary press inside it resigns a focused field and
**routes no key by hover**. It is `KeyboardAttachment.resignsOnPress` (every factory carries all four
fields; `Handlers` keeps nineteen members) registered by the same non-opaque region and gates as a
key region and counted apart (`resignRegionCount`, never `keyRegionCount`: `hoveredKeyRegion`,
`keyChain`, `coversKeys(withPressRegions: false)` and `onKeyPress` routing are untouched, `KF-U`,
test 2b); it widens only `focusOnPress`'s region predicate, so `KF-E` item 5's ladder holds (a text
field or click-focusable inside focuses directly, one change and no `nil` between) and the one
ranking is the only lookup. A secondary or other press never resigns (`MN-B`), a `Deferred`
presentation's press does not reach a region below (`IX-Q`), a `Button` inside fires **and**
resigns. MetalUI-only (class `M`, no divergence): SwiftUI has no such modifier (probe
`swiftui-resign-on-press.swift`); `KF-G`'s default stands. Rejected: `hoverKeyRegion(routesKeys:)`
(`RF-B`); not built: a per-subtree opt-out, a window option.

**Material follow-ups (`MT-`, record §101).** `Material.tint(in: ColorScheme) -> Color` is the
fitted table's tint as API (MetalUI-only, class `M`; SwiftUI has no read, probe
`swiftui-material-followups.swift` `A3`/`A4`); a material takes no colour and has no initialiser
(`MT-C`). `EnvironmentValues.accessibilityReduceTransparency` is SwiftUI's read-only key
(`public internal(set)`), stamped by `Window` from two **defaultless** `PlatformWindow` requirements
(`accessibilityReduceTransparency`, `onAccessibilityReduceTransparencyChange`) the reduce-motion way
(guarded `didSet`, never a `Window.environment` write; AppKit's one display-options observer serves both
values; SDL answers `false` and never fires, `MT-E`; `HeadlessPlatform.Options` and
`TestWindow.setReduceTransparency(_:)`, `MT-G`). **Every material site draws through
`Frame.fillMaterial`** (a guard scans for any other `fillBackdrop(` or `material.color` read): off, it is
`fillBackdrop` byte for byte; on, an ordinary rect or path of `Material.opaqueColor(in:)` (the table's
grey at alpha 1) with no backdrop record, so no split, no blur pass, no copy, and a change snaps.
SwiftUI's own fallback is unmeasured (the probe cannot move it), so the grey is a ruling (divergence
315; 249 retired).

**Incremental invalidation (`IV-`, record §104).** Slice 1 of C14, two parts, both leaving every phase
and channel running on an equal value. **The layout memo** is automatic: `LayoutMemo` (`AnimationStore`'s,
`MetalUILayout`, `package`) keys a measurement and a root placement by a 128-bit **structural signature**
(`LayoutTree.nodeSignature`, one pre-order pass at the start of every `computeNativeLayout`/
`measureNativeLayout`; no node id enters, grid tokens are normalised); only plain `Text`/`ProposalText`,
`Divider`, the built-in shapes, the gradient leaf and `GPUSurface` carry a key (`LayoutLeafKeys.swift`) and any other
leaf, or a non-`Hashable` custom layout, taints exactly its ancestors. **A new registrar parameter owes a
line in the signature** (`everyRegistrarParameterIsInItsSignature`); a new keyed leaf owes a key that covers
its closure and a covering test; `METALUI_VERIFY_LAYOUT_MEMO=1` recomputes every hit and traps (`IV-J`).
**`Component.equatable()`** (`where Self: Equatable`; `EquatableComponent`, opt-in, no identity level or cursor
index) skips the `content` getter while the value is `==`, its own `@State` unwritten (`StateTable.entryVersion`)
and its observed reads unchanged (one observation session per memo over the getter only, `ContentMemoStore` on
`StateTable`, swept last); `==` decides; `@Environment`/`@FocusState` components are refused, evaluated every
frame and counted (divergence 346). Build recursion, prepaint and paint stay whole, so the win is **counted, not
timed** (`FrameWork` memo and content counters; pins count work). Carried: retained subtrees (C14-b, `IV-H`),
an environment epoch (C14-c), per-row `List` scopes (C14-d). GT-F stands: `drawText` is deferred (`IV-O`).
A main-actor test off macOS does not idle after a tracked frame (the observation hop), so a session-count pin
is Darwin-only (`IV-Q`). The demo is `METALUI_INVALIDATION_DEMO=1`.

**Menus, popovers, tooltips (`MN-`, record §74).** A secondary press is its own
`InputEvent` and **never presses, taps, drags or focuses** (divergence 110);
`.contextMenu { }` (both vocabularies, a closed `MenuContent` evaluated at each
open) goes to the platform through the defaultless `PlatformWindow.presentMenu`
— a native `NSMenu` on AppKit, MetalUI's drawn menu where it answers `false`
(SDL) — and the choice returns as a queued `InputEvent.menuAction`, run under
`StateDispatch`. `App.commands { CommandMenu/CommandGroup }` reaches
`Platform.setMenuBar` (every AppKit app gets the standard main menu); **the
window's shortcut pipeline is the one shortcut path** (`Button` first, commands
one stage after, AppKit offering a ⌘- or ⌃-key to it before the main menu,
once; a ⌃-key not while composing — `MN-J`, `MN-AI`). `.popover` is an anchored presentation root, flipped then clamped
inside the window, no arrow, dismissed from input; `.help` is the accessibility
hint plus a drawn, tick-timed tooltip. The new handler member `contextual` is
non-opaque and sits inside the `allowsHitTesting` gate; **a new accessibility
role/request needs a row on both bridges**; a new `StyledElement` modifier
cannot follow a legacy `.popover` (divergence 115).

**Colour and colour scheme (`CR-`, record §75).** `Color` is SwiftUI's **value**
(`Color.swift`: literals are gamma sRGB, drawn on the P3 layer like a token,
divergence 1; 24 bytes, nonisolated; `opacity(_:)` multiplies; `Color(light:dark:)`,
a palette `Color(Key.self)` and a token `Color(.surface)` never fade on a scheme
switch). Every colour-taking site has a `Color` implementation **and** a
`@_disfavoredOverload` `ColorToken` twin forwarding `Color(token)` — a new site
owes both, or `.background(.surface)` is ambiguous (guards 1.24/1.25); `Element`
stays on `Color`'s `@MainActor` extension, never its primary declaration
(`CR-D`, `CR-W` 2). **One resolution function**, `PaintPass.resolve(_:)`, reads
the element's scoped theme and scheme; no renderer or shader change. An app
palette is a `ThemeColorKey` (`Theme[key]`, part of `Theme`'s equality); the nine
built-in tokens keep the exhaustive switch. **The window stamps
`EnvironmentValues.colorScheme` (never a `Window.environment` write: that
dirties every draw) and selects `lightTheme`/`darkTheme`**; `.preferredColorScheme`
is window-wide, collected during the element walk, and reaches the platform
through the defaultless `PlatformWindow.setPreferredColorScheme(_:)` (SDL records
only, `CR-M`). A scheme from the tree is in the first presented frame: two
ordinary builds, the second snapping every change (`CR-Q`, `CR-Z`). `Appearance`
is a typealias of `ColorScheme`.

**Lifecycle (`LC-`, record §76).** `.onAppear`/`.onDisappear`/
`.onChange(of:initial:_:)` are one transparent `LifecycleScope` on every
`ElementGroup` (no node, no id level, no `Element` hook, `Handlers` unchanged;
a legacy decoration after it, or it as a window root, does not compile —
divergence 120). **Presence is membership in a build, keyed in the
window-owned `LifecycleStore` (`AnimationStore`'s), never a `StateTable` slot**
(`$lifecycle<depth>` is a store key, no `noteNamed`; the seven slots unmoved);
a modifier on a group fires once while it has content. **Actions run after
`buildAndAdoptFrame`, outside every phase and `withObservationTracking`, under
`StateDispatch`** (`Window.drainLifecycle`, not re-entrant); a write dirties
the window and costs one settle build, so an `onAppear` write is in the first
frame — never run an action from `Frame.render`. Order: changes, appears,
disappears, each reverse pre-order (`LC-F`). A disappearance under a removal
ghost is parked until it ends, and re-insertion cancels both callbacks
(`LC-H`); `onDisappear` reads departed `@State` through `StateTable`'s overlay,
only while an `onDisappear` exists (`LC-I`). A never-written `@State` default
is re-seeded every build: assign the instance in `onAppear` (divergence 125).
A window close runs every `onDisappear` once (`App`'s `onClose` →
`runDisappearancesForClose`); a headless `renderFrame` runs nothing.
**`.task { }`/`.task(id:priority:_:)` are built** (`PX-F`, record §80):
one more `LifecycleWrite` — started with `Task.immediate` as an appearance
(macOS 14–25: `Task`, one frame late, divergence 137), cancelled as a
disappearance (parked under a removal ghost, the box carried back on
re-insertion), an id change cancels the old task **then** starts the new one
in the change bucket; `LC-L`'s blocker went with `SV-H`. A steady frame costs 3K for K scopes and 0
with none. **A key returning from a removal ghost compares its `task(id:)` id and
`onChange` value against the entry it left with** (`TF-A`, record §84; the
departed entry is parked, not dropped; a value read from the content's own reset
`@State` still compares fresh, divergence 123). `.task` under SDL in CI's Linux
image is tested through `@_spi(Checks)` `SDLPlatform(offscreenRenderers:)`, which
renders each window offscreen so frames and the lifecycle drain run with no
presented frame (`TF-C`, `TF-E`; test 3.20b). Consumer test 1.7 refuses every
`warning:` line (`TF-B`).

**A MetalUI app on Linux and Windows (`PX-`, record §80).** **One decoder
everywhere**: PNG and JPEG go through the vendored stb_image 2.30
(`CStbImage`, `PC-A` list, imports nothing; `Sources/MetalUI/ImageDecoding.swift`)
on every platform, macOS included, 16-bit samples *rounded*, colour profiles
ignored (divergence 138), premultiplied once by `ImageTexture`; a corrupt or
truncated file is `nil` (PNG chunk CRCs and `IEND`, JPEG end marker checked
first — never trap); ImageIO stays only for other formats on macOS.
`ImageBitmap(contentsOfFile:)`, `init?(data:)`, `init?(resource:…bundle:)`
(decoded once per path); `Image(_:bundle:)` is not offered (`PX-E`).
**The SDL backend is a root-package product** behind traits `SDL` and
`AccessKit`: `MetalUISDL`/`SDLBridge`/`CSDL`/`CAccessKit` are declared by
`path:` into `Backends/SDL/Sources`, **no `pkgConfig:`** (it makes the default
build system warn in every consumer); without `SDL` the module declares an
unavailable `SDLPlatform` naming the trait. A change to those targets is run
in `Backends/SDL` and in the Linux image; SDL shaders are found beside the
executable (`PX-P`). **An SDL window is created hidden**: everything that must
precede its first show (the AccessKit adapter — Windows' panics on a visible
window) runs before `SDL_ShowWindow`, then the renderer, on every platform;
`hiddenWindows` windows are never shown (`WS-B`, record §86).

**Input APIs (`CI-`, record §81).** `SpatialTapGesture`, `MagnifyGesture`,
`RotateGesture` and `DragGesture(minimumDistance:coordinateSpace:button:)` live
in the one arena (`IX-B`), which has three modes: a **press** arena fails pinch
leaves; a **pinch** arena (formed from the one ranking at a `.magnify`/`.rotate`
event) runs only pinch leaves, ordered per kind; a **button** arena (a secondary
or other press) runs only that button's drags. A press of the arena's own button
or a `.began` of an active pinch kind replaces a stale arena (`CI-AB`).
Locations are local (`Hitbox.localPoint`); `.global` is the content space
(divergence 139); magnification is additive from 1, rotation clockwise-positive.
**`MN-B` holds**: a secondary or other press reaches only the menu stage,
outside-dismissal, the tooltip, hover and a drag naming its button; a context
menu waits for the release only when a secondary drag is declared on the chain
(`CI-F` item 4). **`.onScrollWheel` (`-> Bool`, `true` claims) dispatches
innermost first along the cover's chain from `topmostHitbox`**: each id's
handler before its scroll region, so a handler on a scroller's *content* can
veto it and one on or around the scroller sees nothing (`CI-AH`; `DD-Y` kept); a
declining handler falls through to its own element's opaque hitbox and `TI-H`
scroll, and a pinch recomputes hover and the pointer style (`CI-AL`).
**`.pointerStyle(_:)` resolves with hover through the one ranking** (innermost
wins, a press holds the pressed chain's style, sent only on a change, forgotten
on exit) through the defaultless `PlatformWindow.setPointerStyle(_:)`; SDL has
no hand or zoom cursor (`MOVE`/arrow, `CI-H` item 8), no rotate, no pinch on
Windows and no wheel phase. Both new regions sit inside the disabled,
`allowsHitTesting` and `hidden()` gates. `CoordinateSpace.named` is built (`OV-D`, below); an image
cursor would still add an enum case (`CI-AC`).

**Platform services (`SV-`, record §77).**
`.fileImporter`/`.fileExporter`/`.alert`/`.confirmationDialog` are one
transparent `PresentationScope` (no node, no id level; the record lives in the
window's registry keyed `$presentation<depth>`, never a `StateTable` slot; a
legacy decoration after it does not compile, divergence 120); they present
after the frame, one in flight per window (`FileDialogs` async calls share the
slot, `.busy`), and answers come back as queued `InputEvent`s that the window
claims first (`SV-B`, `SV-K`, `SV-AH`). AppKit shows sheets (`NSOpenPanel`,
`NSSavePanel`, `NSAlert`); SDL shows file dialogs and **declines alerts, which
the window draws and holds modal** (`AlertPanel.swift`: an input stage ahead of
the menu, Return the default, Escape the cancel, `SV-AK` item 1). SDL
drains the main queue each iteration (`SV-H`; macOS cannot see it, only the
Linux image can). `Window.minSize`/`maxSize`/`windowResizability` reach the
platform through `setContentSizeLimits` only on change; `.automatic` asks the
content nothing (divergence 126); SDL's bridge lifts the maximum before
raising the minimum (`SV-AG`). **Hover is `Handlers`' seventeenth member, a
non-opaque region through the one ranking** (`SV-N`); the opaque and draggable
hitboxes carry no hover attachment (`SV-AH` item 2); `.pointerExited` clears
the sticky pointer. **`Divider` is a view** whose axis is `Frame`'s stack,
pushed by every linear container and read only by layout (a new container owes
a `withStackAxis`, `SV-AK` item 2); `.pickerStyle(.menu)` opens a native menu or
the **scrolling** drawn one, options recorded without layout, widths cached on
the window (`SV-AK` items 3–6). A demo section's alert builds in a `Component`
at layout, never in the tree's own function (`SV-AK` item 7).

**Controls in SwiftUI stacks (`PE-`, record §78).** The SwiftUI-named
containers (`HStack`, `VStack`, `ZStack`, `Grid`, `GridRow`, `ProposalScrollView`,
`ProposalLayoutContainer`, a `ProposalLayout`'s `callAsFunction`) build their
content with `ProposalContentBuilder`: proposal content passes through with its
type, **any other element, group or `Component` is wrapped in `LegacyContent`**,
which is identity- and layout-transparent (caller's parent and cursor, no level),
drops presentations, registers nothing, and **consumes no record — a legacy item
field (`.flexGrow`, `.margin`) there is reported by name and traps in
production** (`PE-C`; a window test over a tree that holds one pre-flights in
diagnostics mode, `PE-Z`). `ProposalFrame`, `Padding`, `Background`,
`FixedSize` and `nativeOverlay` do not take legacy content (they are the
guards' separating controls, `PE-E`, `PE-H`); `ForEach` keeps `ElementBuilder`,
so a `ForEach` of legacy rows in a stack is adopted whole (`PE-E`). `TextField`/`Slider` answer an
infinite width, `TextEditor` either axis, with infinity (`PE-D`; legacy `Row`s
too); `List` keeps divergence 84; style modifiers go on the control before any
wrapper (`PE-R`). A `ProposalScrollView` publishes its `ScrollContext` so a
`List` windows in it (`PE-V`). **`ComponentLayout` keeps its content and layout
in one heap box** (`PE-J`; `withPayload` mutates in place — a copy traps): a
`switch` over `Component` panes does not grow a debug stack with their sum, but an
inline `switch` in one builder still does, so **a branch holding a large subtree
goes in its own `Component`** (`PE-K`). `StackMeter` (debug, internal) is the
instrument; **its `Window` warning is suspended** (`PE-T`: four production trees
exceed the 512 KiB threshold, owner a `PE-L` re-take).

**Field chrome, environment objects, toolbar (`MD-`, record §79).** `TextField`
draws SwiftUI's bordered field by default (24 tall, `.surface` fill,
`.separator` border, the control focus ring from `controlActiveState`;
`.textFieldStyle(_:)`/`.textEditorStyle(_:)` on the control or a container,
innermost wins, `MD-B`, `MD-C`); caret, selection and IME are untouched.
A legacy container sees through a `layoutPriority` layer (`MD-G`).
`@Environment(Type.self)` reads an `@Observable` object provided by
`.environment(_ object:)`, nearest writer wins, a missing one traps
(divergence 134, `MD-H`). `.toolbar`/`.searchable` are one transparent
`ToolbarScope` (not an `Element`: write it inside the root's first container,
`MD-S`) over a **closed item set** (divergence 135); the platform seam is the
defaultless `PlatformWindow.setToolbar(_:) -> Bool` — a native `NSToolbar` on
AppKit, **`false` on SDL, where the window draws a 39-point strip under the
named root `$toolbar` and lays the root out below it** (`MD-K`, `MD-Z`;
divergence 136); outcomes return as queued `InputEvent.toolbarAction`.

**Controls and looks (`LK-`, record §85).** `Slider(onEditingChanged:)` runs
`true` at a press or an edit's first key and `false` once at its end, one pair per
gesture: the end runs at the top of `Window`'s input hook for `.mouseUp` **and**
`.mouseDown`, and on close; `ValueTrackTarget.edit` is the one closure, so
`Handlers` keeps its size (`LK-Q`, `LK-U`). `ColorPicker` is a drawn well and a
drawn popover panel on every platform (divergence 165; edits write gamma-sRGB
literals; `LK-C`, `LK-D`); the well's and `ProgressView`'s roles reach the
element side as `AXNode.colorWellHint`/`progressHint` (internal, stripped in
`registerHandlers`, `LK-G`), and a new `AccessibilityRole` owes a row on both
bridges. The spinner steps by the frame clock only while visibly painted
(`LK-F`); keyframes are a transparent scope whose records live in
`AnimationStore` (`$keyframes<depth>`, never a `StateTable` slot; `LK-I`);
`phaseAnimator` is not built. **A gradient is rasterized on the CPU through the
image path** (Oklab table; a one-texel strip when linear along one axis, else a
full raster in `RasterCache`; no shader change; `LK-J`); `.blur(radius:)` is per
leaf with sigma = radius, the shadow pipeline in colour keyed by
`Frame.keyLeaf(…colours:)` (a GPU surface leaf draws unblurred, divergence 167;
`LK-K`); a `Material` is a tint over a **real backdrop blur** (`BB-`, below;
divergence 166; `LK-L`). **A new stored property on `Decoration` goes in
`DecorationExtras`** (the 1 MB thread, `LK-W` item 10); a new
`CapturedPrimitive` or `LayoutModifier` kind owes its arm in both fade
flattenings (`multiplyAlpha`, `RenderEffect.apply`).

**App shell (`AS-`, record §87).** `Window.onCloseRequest` answers
`CloseRequestReply` (`.now`, `.cancel`, `.later` plus `replyToCloseRequest(_:)`);
`close()` never asks, `performClose()` does; `App.onTerminateRequest`/
`replyToTerminateRequest(_:)`/`terminate()` hook a quit, and **with no app handler
the walk asks every window in turn and owns the end** (a `.later` pauses it, the
window's real close resumes it); closing one of several windows no longer
terminates and the last close ends the app asking nobody (`AS-B`, `AS-C`,
`AS-K`). MetalUI-only by ruling: SwiftUI has no veto API. The platform seam is
**eleven defaultless requirements** (seven on `PlatformWindow`, four on
`Platform`; a conformer adds them, `AS-H`, `AS-J`); AppKit asks through
`windowShouldClose` and `AppKitApplicationDelegate`, SDL through
`SDL_EVENT_WINDOW_CLOSE_REQUESTED`/`SDL_EVENT_QUIT` with its quit-on-last-window
hint off (`AS-L`). `.navigationTitle`, `.navigationDocument` and `.onOpenURL`
are three transparent `EnvironmentWrite` cases (no node, no id level, first
report in post-order wins, handlers run in reverse post-order under
`StateDispatch`); `Window.title`/`isDocumentEdited`/`representedURL` reach the
platform on change only (SDL records the edited marker and path, no-ops).
`windowStyle: .hiddenTitleBar` lays the root **under** the bar (divergence 175)
and `@Environment(\.titleBarInsets)` is stamped by `Window` from the
platform's *answer* (zero on SDL, which answers `false`; client decorations
deferred, `AS-E` item 6); an unclaimed primary press in the band drags the
window (`AS-J`). An open-document event goes to the key window with a handler,
else the first window with one, else `App.onOpenURL`, never a new window (divergence 176);
AppKit delivers no launch argument, so `App.open(_:)` is the recipe (`AS-M`);
URLs arriving before `App`'s initialiser are dropped (`AS-Q`). A test never
calls a real `performClose(_:)` (its nested loop ends the process, `AS-O`
item 7).

**Key and focus scoping (`KF-`, record §88).** `onKeyPress` (SwiftUI's five spellings,
`KeyPress`, `FocusInteractions`) runs **after the Keymap and before a focused field's editing
keys, outermost handler first** (the opposite of `onKey`'s bubble); a command's ⌘-key is declined
by it and runs the command, a `Button`'s ⌘-key and every native-only menu item stay after it
(`KX`, divergence 188); a typed character on a focused field is offered once as `.down`, one
grapheme, never during composition (`KF-Q`, divergence 187). **The key chain** is the focus chain,
else the innermost `.hoverKeyRegion()`'s (the one ranking, found on demand at a key or press, never
per pointer move) and feeds the Keymap's contexts, actions and `onKeyPress` **only** — `onKey` and
every control's keys still need focus (`KF-U`). `.focusable(interactions: .edit)` focuses on a
primary press in the non-claiming `focusOnPress` stage; plain `.focusable()` does not (divergence
94, narrowed); a press elsewhere does not resign a focused field (SwiftUI, `KF-G`). Proposal
content (`MetalView`, `GPUSurface`) takes the keyboard modifiers as **one `KeyboardModifier`
layer** that every further keyboard modifier merges into (`KF-H`, divergence 185), registered
inside `sharingRegistrationsWithEffects`. A Return with the platform's shortcut modifier is not a
`TextEditor` editing key (`KF-Z`). `.onGeometryChange` is a transparent `GeometryChangeScope` (no
node, `$geometry<depth>` a `LifecycleStore` key, never a `StateTable` slot): the value is noted in
prepaint and the action runs in the lifecycle drain, so the first presented frame carries what it
wrote (`KF-J`, divergence 120). `TimelineView(.animation)` calls `noteActiveAnimation()`, never
`requestAnotherFrame()`; other schedules wake the window once through `TimelineStore`
(`$timeline<depth>`, `AnimationStore`; `KF-K`). **`for` over an opaque-returning helper in a
builder is a Swift 6.4 defect, not fixable in the builder** (`KF-M`, guard C1): use `ForEach` or a
concrete helper.

**SMK port gaps (`SG-`, record §89).** `Platform.setMenuBar(_:) -> Bool` (defaultless;
`true` AppKit, `false` SDL): where it answers `false` and the app declared `commands`, **every
window draws the bar** — a 25-point strip above the toolbar strip under the named root `$menubar`
at cursor index 2 (a name, not a slot; `noteNamed`), titles are `Text`+`onClick` (opens on the
click; divergence 195), a `MenuSession` remembering the bar index (hover switches, Left/Right
wrap), **F10** an unclaimed-key stage after `onKeyPress` and the command stage
(`MenuBarStrip.swift`); the model's drawn style has no application menu, and its Edit items are
delivered as AppKit's seven keys (Delete `\u{7f}`) and enabled only while a text field is
focused. **`EventModifiers.primary`** (`.command` on Apple, `.control` elsewhere) is the default
of every shortcut, so macOS is value-identical and `.command` stays Super off Apple (`SG-B`);
`SystemFonts.designFamilies` registers monospaced/serif lazily (`SG-C`); the cross-platform
manifest names the two portable-text products unconditionally (a SwiftPM defect, `SG-D`);
**`Window.drawnChromeHeight`** is the bar plus the strip, and an explicit `minSize`/`maxSize` is
measured below it (`SG-F`). A `Component`'s prepaint record is one heap box (`ComponentPrepaint`,
`SG-E`).

**Test harness (`HT-`, record §91, `docs/testing.md`).** `MetalUITesting` is a portable library
product for test targets only (`MetalUI` never links it): `TestApp`/`TestWindow` run the **real**
`App.openWindow` and `Window` over `HeadlessPlatform`/`HeadlessPlatformWindow`/
`HeadlessWindowRenderer`, which implement every platform requirement honestly (options default to
AppKit's answers). Input is XCUITest's names with AppKit's key routing; a **simulated clock**
(`tick`, `advance(by:)`, `runUntilIdle()` — four quiet yields, bounded at 64 rounds); **an action
draws one frame, `tick` draws the next**, and a test's model is a plain class plus
`setNeedsRedraw()` or `@Observable` with `runUntilIdle()` (the observation hop is asynchronous off
macOS); queries read the accessibility tree (`element(label:)` also matches a static text's string)
and `frame(ofID:)` is the laid-out rect before scroll and effects; presentations are read and
answered at the seam, or driven through the tree where the option makes the window draw them
(`presentsAlertsNatively`, `presentsMenusNatively`, `showsToolbarNatively`,
`HeadlessPlatform.showsMenuBarNatively`); `FrameWork` counts a frame's work (benchmarks count work,
never time). `MetalUI` gains only `package` read-back hooks in `TestingHooks.swift` and
`TestingMenuHooks.swift` (plain-import guards 3.1–3.4 pin them unreachable); no pixels, no GPU
surface draws. `metalui new` generates a test target over it, and `Testing` is a refused name
(`HT-V`). MetalUI-only by class `M`: SwiftUI tests out of process.

**Input-method driver (`IM-`, record §102, `docs/testing.md`).** `TestWindow.setMarkedText(_:selectedRange:)`,
`commitMarkedText()` (AppKit's `unmarkText`, which is a commit), `commitMarkedText(_:)` (`insertText`) and
`cancelMarkedText()` (SDL's empty `TEXT_EDITING`) send the platforms' own `InputEvent`s through `onInput`, so the
real `Window` composition path runs, never a test-only shortcut; with no text field holding the caret they send
nothing and answer `false` (`IM-B`, `IM-C`). `HeadlessPlatformWindow.markedText` mirrors `MetalHostView`'s. A field's
AX value is the **committed** text while composing (divergence 325) and a selection write while composing is held
back until the commit (`SL-H`, divergence 326). `Window.focusedElement`'s `didSet` drops the composition of a field
that lost focus (`IM-I`). A selection write ends the open typing group (`SL-O`, measured and pinned).

**Developer guides (`DG-`, record §103, `docs/guides/README.md`).** Six task-led guides (layout, state
and identity, input, presentations and the app shell, drawing and GPU, cross-platform) for an author
coming from SwiftUI. **Every `swift` block is compiled**: copied by hand, byte for byte, into a
`// guide: <file> #<n>` region of `Tests/MetalUITestingTests/GuideMirrors*.swift` (an ordinary
target, so no build system skips it, `DG-C`), and `GuideDocCheck.swift` fails on a differing byte,
an unmirrored block, a fence other than `swift`/`text`/`sh`, a dead pin, divergence label or link,
an unmerged-API name and a behaviour word with no `(pin: \`test\`)`. **A new block is written in the
guide, then copied by hand** (no generator, `DG-D`); SDL snippets are `text` fences (`DG-L`); a
mirror test settles with `setNeedsRedraw()` and `tick()`, never `runUntilIdle()` after a click
(`DG-P`). The C23/C24/C27/C28 sections are in (record §107): `frame(ofID:)` does not see a proposal
element's `.id`, so a guide test reads an accessibility frame (`DG-T`). No public API.

**Observation off the main thread (`RU-`, record §106).** `Window.markDirtyFromObservation` recognises
the flush's own sentinel `onChange` by **thread** (`Window.flushingThread`, set around the sentinel
write), never by `Thread.isMainThread`: Swift Testing runs the main actor on a pool thread, so the old
test hopped and dirtied the window for ever (`runUntilIdle()` threw `notIdle` after a click on Linux,
item C29; macOS value-identical). A write from another thread still hops. No public API.

**Overlays and coordinates (`OV-`, record §92).** `CoordinateSpace.named` and `.coordinateSpace(_:)` (a
transparent `CoordinateSpaceScope`: no node, no id level) resolve against the **nearest ancestor so
named**, moving with scrolls and effects; a missing or degenerate space reads `.global`, never an
outer one of the same name; a frame composes the maps **before** boxing (`OV-M`); hitboxes snapshot
the named stack only while a scope is open, and a gesture arena takes the snapshot of each member
and joining ancestor (`OV-H`, `OV-Q`). `onContinuousHover(coordinateSpace:)`, named
`onGeometryChange`/`DragGesture`/`SpatialTapGesture` and the MetalUI-only
`EnvironmentValues.windowSize` (the frame's `contentSize`, chrome included; `renderFrame` stamps it
too) belong to it. **`anchoredOverlay(at:in:anchor:)`** (MetalUI-only, both vocabularies) is a
`PopoverModifier` of kind `.overlay`: no panel, border, shadow or padding; the point is resolved
**at layout**, a `.local`/`.named` one through the declarer's recorded space one frame later
(`OV-K`, `OV-S`); flipped per axis then clamped; dismissed by an outside press of any button that
**still lands** (the popover stage runs before the menu, text-input and value-track stages) and by
Escape, never claiming a key; a press on the declarer dismisses and reaches it. `.popover` takes
SwiftUI's `attachmentAnchor:` (divergence 225). `presentationBackground(_:)` is not built (`OV-C`).

**Backdrop blur (`BB-`, record §94).** A `Material` is one scene primitive, `PrimitiveKind.backdrop`
(`MUIBackdrop`, 96 bytes, `Scene.backdrops`): the blurred backdrop and the tint together,
`c · o · (T + (1 − T.a) · B)`, so an opacity is a half-weight composite over the **sharp** backdrop
(`BB-A`, `BB-B`); the proposal `.background(material)` is the `LayoutModifier.backgroundMaterial`
case, the legacy `Box`'s lives in `DecorationExtras` (`BB-P`). **A scene with no backdrop takes the old
single pass byte for byte** (every counter 0); one with backdrops renders in segments, split at each
backdrop run, into a per-window frame target and copies it to the drawable, which stays
`framebufferOnly` (`BB-C`). The blur is sigma 52 pt in device pixels: `L` bilinear 2× downsamples until
`sigma_dev / 2^L ≤ 4`, a separable Gaussian, then the quad's read at `(p + ½)/2^L − ½` over the
transformed bounding box clamped to the target — `Scene.backdropRegion` is the one region function,
`BackdropBlurReference` (`MetalUIPath`) the one reference (`BB-D`, `BB-R`). **`shaders.metal` and
`replay.hlsl` hold the same arithmetic** (`TE-AD`; `ReplayFixture` v4, parity frames 9–11); counters
count `L + 2` passes a record, never time (`BB-E`, `BB-S` 1). **It degrades to the flat tint rect
`c · o · T` (`MUIBackdrop.flatTintRect`) by name**: a `Path` fill and a leaf inside a CPU-rasterized
`.shadow`/`.blur`/`.compositingGroup()` (divergence 248), and wherever a renderer cannot blur
(`BB-I`); Reduce Transparency is not honoured (249). **A shader test needs a field that varies on both
axes**: a vertical step let four mutations survive (§94 §6).

**`ForEach` identity (`FI-`, record §95).** A `ForEach` element is identified by its id's **Hashable
value**, as SwiftUI: ids that print alike and differ in value are two elements with separate `@State`
(divergence 79 is retired). For an id type that is not a `DescriptionInjectiveID` (Int family, String,
UUID, Bool, Character, Double, Float) every element's `ElementID` also carries an internal
`IdentityKey` (`ElementID(name:key:)`, never public, plain-import guard G1); injective types mint
today's description-only names, byte for byte (`FI-B`). `GlobalElementID.==`/`cachedHash` are
untouched (`FI-C`); a floating-point id keeps the name dedupe because a NaN is unequal to itself
(`FI-K`). `ElementID` is 24 bytes, a `GlobalElementID` the same 64-byte malloc bucket (`FI-G`).
**`List` rows still name by description** (divergence 255, `FI-I`): a fix reuses
`ElementID(name:key:)` and owns the 100k work re-take.

**Animation (`AN-`).** `withAnimation` = `withTransaction`; the frame's
transaction is a stack; `.transaction`/`.animation(_:value:)` are transparent
scopes. One root transaction per build (divergence 99). Legacy fields animate
in `animated(_:_:for:pass:)` (layout) and `animatedBackground`/`animatedColor`
(paint) — **a site that skips its helper is silently unanimated**; guards
`everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`,
`everyBackgroundPaintingSiteAnimatesItsColour`. Proposal `LayoutModifier`s
animate through the window-owned `AnimationStore`. "Live" is
`Frame.noteActiveAnimation()` → `hasActiveAnimations`, **not**
`wantsAnotherFrame` — never raise both. In-flight values are clamped;
declared values never. Structure snaps, values interpolate (`LR-AS`); a new
read of `Style` in the lowering owes an animated arm. Interpolation is
per-component RGB. Transitions: only the outermost group transitions;
insertion needs the conditional evaluated last frame; removal draws a ghost;
no default transition (divergence 98). Reduce Motion changes only
transitions (to a cross-fade). **Tests never sleep: drive
`simulateTick(timestamp:)`.**

## The proposal layout path

The CSS engine is gone (stage 9); every element lays out through the
propose/measure/place kernel (`NativeNode` in `LayoutTree.swift`, twelve
cases + `custom(any ProposalLayout)`; a new case must choose its zero-spacing
edges). A root is placed centred at its own answer (`CN-J`).

- **Legacy elements lower** (content → padding → fixed frame, from the
  **animated** style, structure from the **declared**). An unlowerable field
  traps naming `<site>.<field>`, or reports with `reportsUnlowerableFields`
  (tests only). Every report is a permanent refusal (`owner: nil`). **A new
  legacy registration site gains its own check and an arm in
  `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`.**
- **Item fields are lowered by the parent** (`LR-AB`…): a lowered container
  consumes its children's `LoweredItem` records; **a record nobody consumes is
  reported by name** (`LR-AQ`) and, in production, traps — a new lowering site
  that receives children consumes or marks them. A `ScrollView`'s content
  record is left unconsumed, so a later field belongs on the declared content
  style.
- **Differential harness**: `LayoutDifferential.compare` under
  `DifferentialRoot`, asserting hand-derived literals; never a wrapping `Text`
  or greedy child directly under the root; a diagnostics-mode test
  pre-flights with `try #require` on an empty report. **A window test in a
  mode that traps pre-flights in a mode that reports.**
- **`ProposalLayout`**: `sizeThatFits` + `placeSubviews`, no cache;
  measurement cannot place; unplaced is centred. Migration: leaf →
  `requestNativeLeaf`; algorithm → `ProposalLayout`; container with
  paint/input → `requestGroupLayout` + `requestNativeLayout`.
- **Stacks are SwiftUI's** (`CN-B`…`CN-I`, probe `swiftui-stack-algorithms.swift`).
  Flexible frame is greedy (`FR-A`, `FR-M`).
- `ProposalElementGroup` has one requirement returning `[ProposalNodeID]`
  (init internal, `MC-G`). One id under two parents traps (`CN-L`). **A copy
  of a pinned entry is unpinned**: each builder-group/`EnvironmentScope` copy
  has its own pin; a new group gets its own.
- **Invalidation**: the cache lives for one call; `setLayout` traps during
  measurement; **one `isLayingOut` flag — do not split it.**
- **Validation**: reject a parameter only if SwiftUI does or it would make a
  node non-finite at a finite proposal. Stored rects finite, nothing NaN.
  Trap → clamp later is additive; the reverse breaks callers.
- **Depth guard** `NativeLayoutRun.maxDepth` = **72**; raise only after
  re-bisecting all four node kinds in **both** debug and release
  (`docs/probes/native-depth-ceiling/`). Demo deepest level ~30.
- **Work counters** `LayoutTree.lastNativeLayoutWork` (`SA-M`): branching
  tree, literals derived before the run.
- **`Grid`/`GridRow`** (`GR-`) is a kernel case, not a `ProposalLayout`. A
  `GridRow` has its own identity level; cell modifiers are transparent. The
  outermost row mark wins; the innermost cell attribute wins;
  `gridCellColumns` sums. Spacing `nil` is per-boundary (`GR-D`). A grid
  consumes no `LoweredItem`. Lazy grids are not built (stage G2).
- **Registrars**: 13 on `LayoutPass` and on `LayoutTree` — count by type, not
  by file (`requestNativeGrid` lives in `Grid.swift`).
- **`ScrollView` and `ProposalScrollView` share one `ScrollChrome`** (computed,
  never stored). A byte-identical re-inline reddens nothing — don't.
- `SA-N`'s "probed, and the kernel disagrees" list is empty. Do not re-add a
  row without a probe run.

## Workflows and subagents — token budget

A five-lane stage has cost 6–12M tokens. Two or three lanes, split only on
disjoint files. Opus for design, implementation and mutation verification;
`model: 'sonnet'` for record, docs, counts and greps. Merge adjacent agents
over the same material. Re-verify only on a finding. Pass paths, not
content; agents return conclusions. Stay under the session's workflow size
guideline.

## Practices — the short form

Read `docs/practices/verifying-tests-can-fail.md`; history in record §02.

- **Findings come from mutation, not inspection.** Mutate the declaration a
  test is named for and run it. A mutation that reddens nothing is a broken
  instrument or the finding. Name the reddened tests, not a count. Record
  which branch **and which spelling** a mutation was applied to.
- Any count a later loop indexes on is `try #require`.
- A `@testable` test cannot prove an access-level narrowing — use a
  plain-import typecheck guard, in the change that introduces the hazard.
- When a claim is refuted, fix everywhere it was copied (spec, plan, source
  comment, this file, the record). Re-take whole tables.
- Re-run a mutation a doc comment names when the code under it changes.
- A confident "cannot" that was not measured is the tell.
- Reviewer dispatches say not to invoke the `code-review` skill. Mutate in an
  isolated `git worktree` when another agent is live.
- Performance tests count work, never wall clock; red on arrival; branching
  tree.
- A probe needs a separating arm before a ruling rests on it (`FR-M`).
- A helper with two halves needs two per-site guards (`OM-AI`); an order test
  needs a two-layer chain (`OM-AD`).
- A harness decision is a mutation site. A fixture of fixed-size leaves cannot
  see a container lowering. A green mutant may be the correct spelling (`LR-X`).
- Parallel tracks owe tests for the merge; a clause both tracks share can be
  pinned by neither.

## Reference tables

- **Divergences**: `docs/divergences.md` (151 live, next label 206). A new
  divergence gets the next label, a row there, a section in record §04 and a
  pin. Many rows are pinned wrong on purpose — a reddening test may be a fix.
- **Declared but inert**: record §05 (plan task 15's section is the final
  list). Adding an unimplementable property: add a row.
- **Human verification**: `docs/verification/human-checks.md`. Paint order,
  portals, scroll direction, presentation, the display link and real hover
  are looks; nothing in the suite sees them.
- **Performance**: record §105 (`BL-`, 2026-10-13, `848ee029`; §07's CSS-engine tables are history). Wall clock is re-taken by `zsh docs/probes/perf-baselines.sh` and recorded dated, never pinned; a pin counts work.
- **CI hazards** (record §08, §61 §9):
  - A proposal-path regression that reports an `…unconsumed` or presentation
    field **traps in a `Window` test and truncates the run with no summary
    line** — read the last lines of the log.
  - **Windows CI's compiler is 6.4.0+Asserts; macOS's is not.** A `Component`
    whose content is a loop, nested in a container inside another
    `Component`'s content, crashes SILGen there (`verifyLexicalLowering`,
    `LK-X`, MG-27) — fixed for a `Component` by its prepaint record being one
    heap box (`ComponentPrepaint`, `SG-E`); code with its own protocols of that
    shape still needs the inner one as a function. Reproduce with the asserts
    dev snapshot in `~/Library/Developer/Toolchains`
    (`METALUI_RUN_ASSERTS_COMPILER_TEST=1`, macOS and Linux only).
  - **Windows threads have 1 MB stacks.** A new demo section goes in its own
    function passed to a generic composer, not inline
    (`everyProductionTreeBuildsOnAOneMegabyteThread`); that test builds each
    large tree in its own `@inline(never)` frame — inline in its composer the
    canvas tree passed on macOS and overflowed only in `swift:6.4-noble` (`CI-AI`).
  - **A C enum's `rawValue` is `Int32` on Windows, `UInt32` on Apple** —
    always convert explicitly.
  - `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` is compiled out on
    Windows by design.
  - **A macOS test process that initialises SDL video can `exit(0)`
    mid-run.** `SDLPlatform.init` runs `NSApp.run()` once; a new entry point
    owes the same, and **every new SDL test helper creating an `SDLPlatform`
    arms `armMainRunLoopExitCheck()`**.
  - E24 hard-fails under the root locale; seven `AnimationTests` need a
    display device.
