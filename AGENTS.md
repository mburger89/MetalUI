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
  `2026-10-12-material-followups-decisions.md`, next `MT-L`), `TW-` (`frame(ofID:)` on proposal `.id`:
  `2026-10-13-frame-of-id-decisions.md`, next `TW-G`), `IM-` (input-method
  driver: `2026-10-12-ime-driver-decisions.md`, next `IM-K`), `DG-` (developer guides:
  `2026-10-12-guides-decisions.md`, then `2026-10-13-guides-followup-decisions.md`, next `DG-X`), `BL-` (performance baselines:
  `2026-10-13-perf-baselines-decisions.md`, next `BL-D`), `RU-` (`runUntilIdle()` on Linux:
  `2026-10-13-rununtilidle-linux-decisions.md`, next `RU-C`), `IV-` (incremental invalidation:
  `2026-10-13-incremental-invalidation-decisions.md`, next `IV-S`), `SB-` (retained subtrees:
  `2026-10-13-retained-subtrees-decisions.md`, next `SB-AF`), `RK-` (retained build skip, prepaint replay, the graft:
  `2026-10-13-retained-build-skip-decisions.md`, next `RK-AD`), `HP-` (hot paths:
  `2026-10-13-hot-paths-decisions.md`, next `HP-K`), `CW-` (window chrome on SDL:
  `2026-10-13-sdl-chrome-decisions.md`, next `CW-W`), `IB-` (public image decoding and orientation:
  `2026-10-13-image-decode-api-decisions.md`, next `IB-N`), `GA-` (SDL GPU for apps:
  `2026-10-14-sdl-gpu-compute-decisions.md`, next `GA-S`), `CB-` (clipboard beyond text:
  `2026-10-14-clipboard-types-decisions.md`, next `CB-R`), `IC-` (image cursors, headless SDL launch:
  `2026-10-14-cursors-headless-decisions.md`, next `IC-S`), `IH-` (header-only image read and bounded decode:
  `2026-10-14-image-info-decisions.md`, next `IH-Q`), `PN-` (pan path rasters:
  `2026-10-14-pan-rasters-decisions.md`, next `PN-L`), `PA-` (layout and build allocations:
  `2026-10-14-layout-allocations-decisions.md`, next `PA-S`), `EE-` (environment epoch:
  `2026-10-14-environment-epoch-decisions.md`, next `EE-P`), `SN-` (single-instance launch on SDL:
  `2026-10-19-single-instance-decisions.md`, next `SN-Q`), `RW-` (retained read-only state:
  `2026-10-19-retained-withstate-decisions.md`, next `RW-U`), `MO-` (memo and retained observation off the main thread:
  `2026-10-19-memo-observation-thread-decisions.md`, next `MO-I`), `OS-` (raster overscan, pooled rasterizer scratch:
  `2026-10-20-raster-overscan-decisions.md`, next `OS-Q`), `FS-` (finer retention scopes:
  `2026-10-20-finer-scopes-decisions.md`, next `FS-U`), `CF-` (warm and cold frame gaps: `2026-10-20-warm-settle-decisions.md`, next `CF-L`), `RZ-` (retained zoom, fillet-drag profile, `@FocusState` memo: `2026-10-21-retained-zoom-decisions.md`, next `RZ-U`), `RG-` (retained geometry observers, placement translation, per-shelf atlas uploads: `2026-10-20-retained-geometry-decisions.md`, next `RG-Q`), `AT-` (accessibility under an effect-translated replay: `2026-10-20-ax-translated-replay-decisions.md`, next `AT-H`), `RL-` (retained lifecycle and translation carries: `2026-10-21-retained-lifecycle-decisions.md`, next `RL-R`), `AP-` (SDL application id: `2026-10-21-sdl-app-id-decisions.md`, next `AP-G`), `EX-` (the sample app: `2026-10-21-sample-app-decisions.md`, next `EX-T`), `GB-` (SDL GPU gaps: `2026-10-21-sdl-gpu-gaps-decisions.md`, next `GB-M`), `IS-` (header-only image format sniff: `2026-10-20-image-sniff-decisions.md`, next `IS-L`), `LZ-` (lazy containers: `2026-10-21-lazy-containers-decisions.md`, next `LZ-AA`), `GS-` (`@GestureState`, `phaseAnimator`: `2026-10-21-gesture-state-decisions.md`, next `GS-T`), `BS-` (build-time app shaders: `2026-10-21-build-shaders-decisions.md`, next `BS-M`), `WR-` (Windows release-build SIL crash: `2026-10-21-windows-release-crash-decisions.md`, next `WR-H`), …; the full
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
  live SwiftUI difference — **164 live, next label 206** (625–634 unused by C14-i; 635–638 used and 639–644 unused by L1; 645, 646 used and 647–654 unused by G1; 655–664 unused by E1; 665–674 unused by S11; 675–684 unused by S12; 685–694 unused by XP-G21; 695–704 reserved by C14-j; 455, 456 used by S3; 465 used and 466–474 unused by S4+S8; 425, 426 used and 427–434 unused by S1; 435 used and 436–444 unused by S2; 345–354 reserved by C14: 346 used, 345 refuted, 347–354 unused; 196–204 unused by C12, 215–224 unused by item 8, 226–234 unused by C15, 237–244 unused by C16, 256–264 unused by C20, 250–254 unused by C21, 267–274 unused by C25, 278–284 unused by C22, 285–294 unused by C24, 295–296 used and 297–304 unused by C23, 305–314 unused by C26, 315 used and 316–324 unused by C27, 325–326 used and 327–334 unused by C28, 189–194 unused by C9); retired labels are
  never reused), `docs/migration.md`, `THIRD-PARTY-NOTICES.md` (licences of the vendored C code and SDL3/AccessKit, per product), `docs/verification/human-checks.md`
  (groups A–Y, VL, RT, WS, AS, CL, KF, PF, SG, HT, OV, IF, BB, WD, SL, GC, GT, RF, MT, IM, GD, IV, GA, SB, HP, IB, CW, CB, IC, RK, SI, RO, FS, RG, AT, RL, AP, EX, GB, GS, BS, LZ and RZ, **not run — an agent cannot**), `docs/verification/voiceover-script.md`.
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
# also METALUI_TEXT_INPUT_DEMO=1, METALUI_CONTROLS_DEMO=1, METALUI_DND_DEMO=1, METALUI_LOOKS_DEMO=1, METALUI_METALVIEW_DEMO=1, METALUI_MENUS_DEMO=1, METALUI_SERVICES_DEMO=1, METALUI_LIST_DEMO=1, METALUI_RICH_TEXT_DEMO=1, METALUI_CANVAS_DEMO=1, METALUI_APP_SHELL_DEMO=1, METALUI_SELECTION_DEMO=1, METALUI_INVALIDATION_DEMO=1, METALUI_RETAINED_DEMO=1, METALUI_CHROME_DEMO=1, METALUI_CLIPBOARD_DEMO=1, METALUI_LAZY_DEMO=1
METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
```

- **Counts (2026-10-21, `fix/windows-release-crash` from `68975774`, merged with master `195ff2c8` (§133 retained zoom, §134, §135, §138): 4248 tests, 0 goldens, 261 typecheck guards** (master's 4247 + 1: `everyLegacyRenderEffectOpensItsScopeAtItsIndex`, no guard; `swift package clean`, native build 0 `error:`, native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; the env-gated asserts-compiler release arms (record §139 §3) passed at the branch head before the merge, not re-taken after it, `RenderEffects.swift` untouched by master; no public declaration; no divergence label taken; record §139). Before it,
  **Counts (2026-10-21, `perf/retained-zoom` + the C14-i refusal pins, merged with master `68975774` (§134 lazy containers, §135 gesture state, §138 build-time shaders): 4247 tests (measured unfiltered after `swift package clean` on the merged tree, only the five locked-screen `AppKitPresentationTests` issues; 4238 passed under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` with them skipped; 4139 on the branch before this merge), 0 goldens, 261 typecheck guards** (4138 + 1: `aZoomStepWithAnAlphaOrEntryDepthChangeIsRefusedByName` (`EffectRelationKeyTests`, 2 arms) and a `gateWithZoom` arm on `anEffectChangeThatIsNotAnAffineMoveIsRefusedByName`, no guard; native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues and nothing else, `FR-J no-argument frame: succeeded=true`; 4130 passed with `AppKitPresentationTests` skipped under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`; record §133 M11, M12). Before it,
  **(2026-10-21, `feat/lazy-containers` from `1bdead8d`, merged with master `11dca65e` (§136 sample app, §137 SDL GPU gaps), then master `4365e674` (§135 gesture state, §138 build-time shaders): 4228 tests (measured unfiltered after `swift package clean` on the merged tree, only the five locked-screen `AppKitPresentationTests` issues of `CI-AF`), 0 goldens, 261 typecheck guards** (master's 251 + 3: `LazyStackGuards` 2, `LazyGridGuards` 1; the branch's 43 tests over 1bdead8d's 4117, 4161 at lane 2's head before the merge; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`; inventory and undocumented scripts print nothing, census 3720; the fourteen images 0 px against `1bdead8d` at the lanes; divergences 635-638 added (header's count and next label left to the merge); Linux image and `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` re-take on the merged tree: see record §134 §5; record §134). Before it,
  **Counts (2026-10-21, `perf/retained-zoom` from `1bdead8d`, merged with master `11dca65e` (§136 sample app, §137 SDL GPU gaps): 4138 tests, 0 goldens, 251 typecheck guards** (master's 4120 + 18 tests (lane 1's 10 pins and their arms net of one rewritten, lane 2's 6 focus tests, F6b and 10 fillet cases net of the replaced W8), no guard; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; the lanes' `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` runs read 4118 and 4125 passed with `AppKitPresentationTests` skipped, no trap; default build 0 `warning:` and inventory and undocumented scripts print nothing at the lanes, the fourteen images 0 px against `1bdead8d`; no public declaration, census unmoved; no divergence label taken (625-634 untouched), 346 narrowed; Linux image, the verify-switch run and the demo launch owed on the merged tree; record §133). Before it,
  **Counts (2026-10-21, `feat/sdl-gpu-gaps` from `1bdead8d`, merged with master `9849f4ea` (§136 sample app): 4120 tests (master's 4120 unchanged: the branch adds `Backends/SDL` tests only, 30 + 245 on macOS, 240 + 2 expected in the Linux image, not re-taken), 0 goldens, 251 typecheck guards** (no root test or guard; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; default build 0 `warning:` at lane 1; no public root declaration, census unmoved; no divergence label taken (665-674 untouched); two lane-1 mutations that survived the checker (viewport depth clamp, non-square scissor clamp) are pinned by S11 (`aViewportDepthRangeIsClampedToUnitInterval`, `aScissorIsClampedOnANonSquareTarget`; macOS now 30 + 245); Linux-image and fourteen-image re-takes at the final head owed; record §137). Before it,
  **(2026-10-21, `feat/sample-app` from `1bdead8d`: 4120 tests expected unlocked (4111 run with `AppKitPresentationTests` skipped on a locked screen), 0 goldens, 251 typecheck guards** (master's 4117 + 3 root tests, no guard: the manifest-shape and docs tests and the env-gated `aSampleAppBuildsAndItsTestsPassAgainstThisCheckout`; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native run `--skip AppKitPresentationTests` **4111 tests in 5 suites passed**, 0 issues, `FR-J no-argument frame: succeeded=true`; `Examples/Jotter` 21 tests on macOS, 20 in the Linux image; no `Sources/`, `Backends/` or `Package.swift` change, no public declaration, no divergence label; unlocked re-take and fourteen-image re-take owed; record §136). Before it,
  **(2026-10-21, `perf/retained-lifecycle` from `c55d44e8`, merged with master `05bb9a31` (§130 image sniff), then `b39d68d6` (§132 SDL application id): 4117 tests (the pin pass: +2, the modifier-note and inner-clip accessibility arms; 4108 run with `AppKitPresentationTests` skipped, also passed under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`; native unfiltered run read exactly the five sheet issues of `CI-AF`), 0 goldens, 251 typecheck guards** (master's 4092 + this branch's 23 tests, no guard; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native run `--skip AppKitPresentationTests` on the merged tree **4106 tests in 5 suites passed**, `FR-J no-argument frame: succeeded=true`; before the merge the lane checker read 4104 unfiltered on a locked screen (only the five `AppKitPresentationTests` sheet issues of `CI-AF`), 4095 under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`, `swift build --build-tests` 0 `warning:`, the fourteen images 0 px against `c55d44e8`, Linux image `MetalUITestingTests` 431, Layout 233, Core 128, CrossPlatform 22; inventory and undocumented scripts print nothing, no public declaration, census unmoved; no divergence label taken (605-614 untouched); mutations ran as filtered family sets with two named survivors; unlocked re-take, verify-switch, fourteen-image and Linux-image re-takes on the merged tree owed; record §131). Before it,
  **(2026-10-21, `feat/sdl-app-id` from `05bb9a31`: 4092 tests expected unlocked (4083 run with `AppKitPresentationTests` skipped on a locked screen), 0 goldens, 251 typecheck guards** (unmoved: no root test, no new guard; guard `1.6b`'s fixture gained `applicationID`; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; `Backends/SDL` 30 + 223 on macOS (five new `SDLAppIDTests`); inventory and undocumented scripts print nothing, census unmoved; no divergence label taken; Linux image, the fourteen images and the default-build-system warning re-take owed on the merged tree; record §132). Before it,
  **(2026-10-21, `feat/image-sniff` from `b15e038c`, merged with master `c55d44e8` (§128 retained geometry, §129 AT-): 4092 tests expected unlocked (4083 run with `AppKitPresentationTests` skipped on a locked screen), 0 goldens, 251 typecheck guards** (master's 4081 + 10 tests and guard `G-IS1`, 250 + 1; the 10th is the checker's DIB-size pin, 4091 + 1, re-measured after it with the 9 `AppKitPresentationTests` skipped, 4083 passed, `FR-J no-argument frame: succeeded=true`, no issue; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; census 3683 (3680 + 3), inventory and undocumented scripts print nothing; no divergence label taken; the lane's mutations ran on filtered sets; the root portable run in the Linux image passed (`MetalUICoreTests` 137); record §130). Before it,
  **(2026-10-20, `perf/retained-geometry` from `99b21a1c`, merged with master `b15e038c` (§129 AT- accessibility translated replay): 4081 tests, 0 goldens, 250 typecheck guards** (master's 4060 + this branch's 21 tests (the checker's geometryTranslated pin included; measured 4081 unfiltered after `swift package clean`, only the five locked-screen `AppKitPresentationTests` issues; 4072 passed under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` with them skipped), 250 guards (master added none); re-measured by the orchestrator on the merged tree, record §128). Before it,
  **(2026-10-20, `perf/retained-geometry` from `99b21a1c`, merged with master `c502f14c` (§127 warm settle): 4073 tests, 0 goldens, 250 typecheck guards** (master's 4053 + 20 tests (lane 1's 6, lane 2's 8, lane 3's 6), 249 + guard `dirtyRectStaysReadableAsATuple`; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on an unlocked screen all passed, 0 issues, `FR-J no-argument frame: succeeded=true`; verify-switch run 4073 passed, no trap; census 3680 (3679 + `GlyphAtlas.dirtyRects`), inventory and undocumented scripts print nothing; the fourteen images 0 px against `99b21a1c`; Linux image root 412 + 9 + 40 + 28 + 233 + 128 + 22 and `Backends/SDL` 30 + 215 passed, macOS `Backends/SDL` 30 + 218; no divergence label taken (575-584 untouched); record §128). Before it,
  **(2026-10-20, `fix/ax-translated-replay` from `c502f14c`: 4060 tests, 0 goldens, 249 typecheck guards** (4053 + 7 tests, no guard; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; also green under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` at the checker; inventory and undocumented scripts print nothing, no public declaration, no divergence label taken; the fourteen images 0 px against `c502f14c`, the Linux image (`MetalUITestingTests` 410, `MetalUILayoutTests` 230, `MetalUICoreTests` 128) and the default-build-system warning re-take at the lane, owed on the merged tree; record §129). Before it,
  **(2026-10-20, `perf/warm-settle` from `679f5d7d`, merged with master `99b21a1c` (§126 finer scopes): 4053 tests, 0 goldens, 249 typecheck guards** (master's 4038 + 15 tests, no guard; re-measured by the orchestrator on the merged tree, record §127). Before it,
  **(2026-10-20, `perf/warm-settle` from `679f5d7d`: 4030 tests, 0 goldens, 249 typecheck guards** (4015 + 15 tests (lane 1's 10, lane 2's 5), no guard; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; also 4021 passed with `AppKitPresentationTests` skipped under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`, no trap; `swift build --build-tests` on the default build system 0 `warning:`; inventory and undocumented scripts print nothing, no public declaration, census unmoved; the fourteen images 0 px against `679f5d7d`; Linux image `MetalUITestingTests` 382, `MetalUILayoutTests` 229, `MetalUICoreTests` 128 passed at lane 2; `Backends/SDL` untouched; no divergence label taken, 346 narrowed; unlocked re-take and the merge re-takes owed; record §127). Before it,
  **(2026-10-20, `perf/finer-scopes` from `711ab9c4`, merged with master `679f5d7d` (§124 raster overscan): 4038 tests, 0 goldens, 249 typecheck guards** (master's 4015 + 23 tests (lane 1's 10, lane 2's 13), no guard; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; census 3679 unmoved by the merge (one `MetalUITesting` field, `FrameWork.retainedTranslationRefusedReasons`), inventory and undocumented scripts print nothing; no divergence label taken; the lanes' mutation runs were filtered sets; Linux image, the `METALUI_VERIFY_RETAINED=1`/`METALUI_VERIFY_LAYOUT_MEMO=1` re-take, the fourteen images against `711ab9c4` and the default-build-system warning re-take owed on the merged tree; record §126). Before it,
  **(2026-10-20, `perf/raster-overscan` from `4d91f27f`, merged with master `711ab9c4` (§121, §123, §125): 4015 tests expected unlocked (4006 run with `AppKitPresentationTests` skipped on a locked screen), 0 goldens, 249 typecheck guards** (master's 4000 + 15 tests (lane 1's 10, lane 2's 5), no guard; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native run `--skip AppKitPresentationTests` 0 issues, `FR-J no-argument frame: succeeded=true`; also 3977 before the merge under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`, no trap; inventory and undocumented scripts print nothing; no public declaration, census unmoved; the fourteen images 0 px against `4d91f27f` at the lanes, not re-taken after the merge; Linux image `MetalUIPathTests` and the portable tests passed at lane 2; unlocked re-take, the verify-switch re-take and the default-build-system warning re-take owed after the merge** (record §124). Before it,
  **(2026-10-20, `perf/retained-withstate` from `f557d339`, merged with master `fa6464ba` (§123 memo observation off the main thread): 4000 tests, 0 goldens, 249 typecheck guards** (master's 3978 + 22 tests, 248 + guard `RW.1`; re-measured by the orchestrator on the merged tree, record §121). Before it,
  **(2026-10-19, `perf/retained-withstate` from `f557d339`, merged with master `4d91f27f` (§122 single instance): 3993 tests, 0 goldens, 249 typecheck guards** (master's 3971 + 22 tests, 248 + guard `RW.1`; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run all passed, 0 issues, in **4 suites**, `FR-J no-argument frame: succeeded=true`; also 3993 passed with `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`, no trap; `swift build --build-tests` on the default build system 0 `warning:`; inventory and undocumented scripts print nothing, census +2 (`FrameWork.retainedIneligibleReasons`, the demo model's `reasons`); the fourteen images 0 px against `f557d339`; Linux image `MetalUITestingTests` 363 and the Layout/Core/CrossPlatform tests passed, `Backends/SDL` untouched; no divergence label taken; record §121). Before it,
  **(2026-10-19, `fix/memo-observation-thread` from `4d91f27f`: 3978 tests, 0 goldens, 248 typecheck guards** (3971 + 7, no guard; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; no public declaration, no divergence label taken; verify switches, default-build warnings, the fourteen images and the Linux image re-take owed after the final commit, two pins unproven, record §123 §6). Before it,
  **(2026-10-19, `feat/single-instance` from `ffbabb5c`: 3971 tests, 0 goldens, 248 typecheck guards** (3970 + 1, 247 + guard 1.6b; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; `Backends/SDL` 30 + 215 on macOS, 30 + 212 in the Linux image; the fourteen images 0 px against `ffbabb5c`; no root declaration, census unmoved; no divergence label taken; Windows transport compiled by CI only; record §122). Before it,
  **(2026-10-19, `perf/layout-allocations` from `6273e3a4`, merged with master `41a2180f` (§120 environment epoch): 3968 tests, 0 goldens, 247 typecheck guards** (master's 3957 + 11 tests, no guard; re-measured by the orchestrator on the merged tree, record §119). Before it,
  **(2026-10-14, `perf/layout-allocations` from `6273e3a4`, merged with master `298c23d4` (§118 pan rasters): 3937 tests, 0 goldens, 246 typecheck guards** (master's 3926 + 11 tests (lane 1's 8, lane 2's 3), no guard; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on an unlocked screen all passed, `FR-J no-argument frame: succeeded=true`; inventory and undocumented scripts print nothing; no public declaration, no divergence label taken; the fourteen images 0 px against `6273e3a4` at the lanes, not re-taken after the merge; record §119). Before it,
  **(2026-10-19, `perf/environment-epoch` from `6273e3a4`, merged with master `01631221` (§104 `IV-R` memo leak fix): 3957 tests, 0 goldens, 247 typecheck guards** (master's 3930 + 27 tests, 246 + guard G1; `swift package clean`, native build 0 `error:`, native unfiltered run on an unlocked screen all passed, `FR-J no-argument frame: succeeded=true`, default build 0 `warning:`; also 3948 passed with `AppKitPresentationTests` skipped under `METALUI_VERIFY_RETAINED=1` and `METALUI_VERIFY_LAYOUT_MEMO=1`, no trap; re-measured by the orchestrator, record §120). Before it,
  **(2026-10-14, `perf/environment-epoch` from `6273e3a4`, merged with master `298c23d4` (§118 pan rasters): 3953 tests expected unlocked (3944 run with `AppKitPresentationTests` skipped on a locked screen), 0 goldens, 247 typecheck guards** (master's 3926 + 27 tests, 246 + guard G1; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native run `--skip AppKitPresentationTests` 0 issues, `FR-J no-argument frame: succeeded=true`; no public declaration, census unmoved; the fourteen images 0 px against `6273e3a4` at the lanes; divergence 346 narrowed, no label taken; unlocked re-take and default-build-system warnings re-take owed; record §120). Before it,
  **(2026-10-14, `perf/pan-rasters` from `34491ff4`, merged with master `6273e3a4` (§110 retained build skip): 3926 tests expected unlocked (3917 run with `AppKitPresentationTests` skipped on a locked screen), 0 goldens, 246 typecheck guards** (master's 3918 + 8 `PanRasterTests` (the seven and T8, `PN-K`), no guard; `swift package clean`, native build 0 `error:`, `swift build --build-tests` 0 `warning:`, native run `--skip AppKitPresentationTests` 0 issues, `FR-J no-argument frame: succeeded=true`; also run once with `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`, 3917 passed, no trap; inventory and undocumented scripts print nothing; no public declaration, no divergence label taken; the merge touched docs only; unlocked re-take owed; record §118. Before it,
  **(2026-10-14, `perf/retained-build-skip` from `fb9a7e42`, merged with master `d3ebfa18` (§115 clipboard, §117 image info): 3918 tests, 0 goldens, 246 typecheck guards** (master's 3864 + 54 tests, 244 + 2 guards; re-measured by the orchestrator on the merged tree, record §110 §11). Before it,
  **(2026-10-14, `perf/retained-build-skip` from `fb9a7e42`, merged with master `565abe67` (§111, §112, §113, §114, §116): 3869 tests, 0 goldens, 243 typecheck guards** (master's 3815 + 54 tests (lane 1's 29, lane 2's 25), 241 + 2 guards, one a plain-import guard per lane; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on a **locked screen** read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`; census 3603 (3587 + 16: `FrameWork`'s ten counters, six demo-model members); inventory and undocumented scripts print nothing; the fourteen images 0 px against `fb9a7e42` at the lanes, not re-taken after the merge; no divergence label taken; Linux image and `Backends/SDL` not re-taken after the merge (untouched; lane 2's image run on its own tree); record §110 §11). Before it,
  **(2026-10-14, `feat/image-cursors-headless` from `fb9a7e42`, merged with master `34491ff4` (§114 SDL GPU for apps): 3815 tests, 0 goldens, 241 typecheck guards** (master's 3803 + 12 tests, 238 + 3 guards; S5+S6 added no root test; re-measured by the orchestrator on the merged tree, record §116). Before it,
  **(2026-10-14, `perf/pan-rasters` from `34491ff4`, merged with master `d3ebfa18` (§115, §116, §117): 3871 tests expected unlocked (3862 run with `AppKitPresentationTests` skipped on a locked screen), 0 goldens, 244 typecheck guards** (master's 3864 + 7 tests, no guard; `swift package clean`, native build and run 0 `error:`, 0 `warning:`, `FR-J no-argument frame: succeeded=true`; no public declaration, census unmoved; the fourteen images 0 px against `34491ff4`; no divergence label taken; unlocked re-take owed at merge** (record §118). Before it,
  **(2026-10-14, `feat/image-info` from `ceca59f6`, merged with master `31e82bf5` (§115 clipboard, §116 image cursors and headless launch): 3864 tests, 0 goldens, 244 typecheck guards** (master's 3844 + 20 tests, 243 + guard G-IH1; re-measured by the orchestrator on the merged tree, record §117). Before it,
  **(2026-10-14, `feat/image-info` from `ceca59f6`, merged with master `34491ff4` (§114 SDL GPU for apps): 3823 tests, 0 goldens, 239 typecheck guards** (master's 3803 + 20 tests, 238 + guard G-IH1; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else, `FR-J no-argument frame: succeeded=true`; census 3592 unmoved by the merge; inventory and undocumented scripts print nothing; the fourteen images 0 px against `ceca59f6`; no divergence label taken; `Backends/SDL` untouched; record §117 §3). Before it,
  **(2026-10-14, `feat/sdl-gpu-compute` from `fb9a7e42`, merged with master `a4ebe288` (§112 §11 depth-ranked carving): 3803 tests, 0 goldens, 238 typecheck guards** (master's, unchanged: the branch adds `Backends/SDL` tests only; re-measured by the orchestrator on the merged tree, record §114). Before it,
  **(2026-10-14, `feat/clipboard-types` from `fb9a7e42`, merged with master `565abe67` (§114 SDL GPU, §116 image cursors and headless launch): 3844 tests, 0 goldens, 243 typecheck guards** (master's 3815 + 29 tests, 241 + 2 guards 3.1, 3.2; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`; the native unfiltered run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else; census 3638 re-recorded after the merge, inventory and undocumented scripts print nothing; divergences 455, 456 added beside master's 465, 158 live; the guide's `input` mirrors renumbered #8 cursor, #9 clipboard; record §115). Before it,
  **(2026-10-14, `feat/image-cursors-headless` from `fb9a7e42`, merged with master `a4ebe288` (§112 §11 depth-ranked carving): 3815 tests, 0 goldens, 241 typecheck guards** (master's 3803 + 12 tests, 238 + 3 guards; re-measured by the orchestrator on the merged tree, record §116). Before it,
  **(2026-10-14, `feat/image-cursors-headless` from `fb9a7e42`, merged with master `ceca59f6` (§111 hot paths, §112 SDL chrome, §113 image decoding): 3811 tests, 0 goldens, 241 typecheck guards** (master's 3799 + 12 tests, 238 + 3 guards: 6 `ImageCursorTests`, 2 `AppKitImageCursorTests`, the two guards of `ImageCursorCompileGuards.swift`, `IC-22` and the guide mirror's test; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `swift build --build-tests` 0 warnings, native unfiltered run on an unlocked screen all passed, `FR-J no-argument frame: succeeded=true`; `Backends/SDL` 30 + 157 on macOS, 30 + 154 in `swift:6.4-noble`; census 3587, inventory and undocumented scripts print nothing; divergence 465 added, 156 live; the fourteen images were 0 px against `fb9a7e42` at the lanes, not re-taken on the merge; Windows and a real window not run, human checks group `IC`; record §116 §11). Before it,
  **(2026-10-14, `feat/sdl-gpu-compute` from `fb9a7e42`, merged with master `ceca59f6` (§111 hot paths, §112 SDL chrome, §113 image decoding): 3799 tests, 0 goldens, 238 typecheck guards** (master's, unchanged: the branch adds 27 `Backends/SDL` tests and no root test or guard; `swift package clean`, native build 0 `error:`, native unfiltered run all passed, `FR-J no-argument frame: succeeded=true`; `Backends/SDL` 152 tests in 4 suites on macOS at lane 2's head, 149 in `swift:6.4-noble` on lavapipe; inventory and undocumented scripts print nothing, census unmoved; the fourteen images 0 px against `fb9a7e42`; no divergence label taken; Windows and real hardware not run, human checks group `GA`; record §114). Before it,
  **(2026-10-14, `fix/chrome-regions-depth` from `ceca59f6`: 3803 tests, 0 goldens, 238 typecheck guards** (3799 + 4 tests, no guard; `swift package clean`, native unfiltered run on an unlocked screen all passed, 0 `error:`, `FR-J no-argument frame: succeeded=true`, default build 0 warnings; no public declaration; divergence 425 amended; record §112 §11). Before it,
  **(2026-10-14, `feat/clipboard-types` from `fb9a7e42`, merged with master `ceca59f6` (§112 SDL chrome, §111, §113), then `a4ebe288`: 3832 tests, 0 goldens, 240 typecheck guards** (master's 3803 + 29 tests, 238 + 2 guards 3.1, 3.2; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `swift build --build-tests` 0 warnings, `FR-J no-argument frame: succeeded=true`; the native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else after guard 3.1a's fixture gained window chrome's four requirements; census 3625; inventory and undocumented scripts print nothing; `Backends/SDL` 30 + 133 on macOS, 30 + 130 in the Linux image at the lanes; divergences 455 (provisional), 456; record §115). Before it,
  **(2026-10-14, `feat/sdl-custom-chrome` from `fb9a7e42`, merged with master `dea698ca` (§111 hot paths, §113 image decoding): 3799 tests, 0 goldens, 238 typecheck guards** (master's 3757 + 42 tests, 236 + 2 guards `CW-1`, `CW-2`; re-measured by the orchestrator on the merged tree, record §112). Before it, the branch alone:
  **(2026-10-14, `feat/sdl-custom-chrome` from `fb9a7e42`: 3759 tests, 0 goldens, 236 typecheck guards** (3717 + 42 tests: lane 1's 13 portable snapshot tests and 26 window tests, the left-cluster pin added at the Record phase, 2 guards `CW-1`, `CW-2`; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run all passed, `FR-J no-argument frame: succeeded=true`; `Backends/SDL` 30 + 145 on macOS, 30 + 142 in `swift:6.4-noble` (12 chrome pins skipped by the offscreen driver); inventory and undocumented scripts print nothing, census 3526; the fourteen images 0 px against `fb9a7e42`; divergences 425, 426 added and 175, 276 amended, the header's count and next label the merge's; Windows and a real window not run, human checks group `CW`; record §112). Before it,
  **(2026-10-14, `perf/hot-paths` from `fb9a7e42`, merged with master `8e66689f` (§113 image decoding): 3757 tests, 0 goldens, 236 typecheck guards** (master's 3737 + 20 tests, 235 + guard HP.1; re-measured by the orchestrator on the merged tree, record §111 §4). Before it, the branch alone:
  **(2026-10-14, `perf/hot-paths` from `fb9a7e42`: 3737 tests, 0 goldens, 235 typecheck guards** (3717 + 20 tests, 234 + guard HP.1; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run all passed, `FR-J no-argument frame: succeeded=true`; no public declaration, census 3511 unmoved, inventory and undocumented scripts print nothing; no divergence label taken; the fourteen images 0 px against `fb9a7e42`; `Backends/SDL` 30 + 122 and the root portable tests passed in the Linux image; record §111 §4). Before it,
  **(2026-10-14, `feat/image-decode-api` from `fb9a7e42`: 3737 tests, 0 goldens, 235 typecheck guards** (3717 + 20 tests (lane 1's 15, lane 2's 5), 234 + `G-IB1`; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `swift build --build-tests` 0 warnings, native unfiltered run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else, `FR-J no-argument frame: succeeded=true`; census 3531; inventory and undocumented scripts print nothing; the fourteen images 0 px against `fb9a7e42`; divergence 435 added; record §113 §2). Before it,
  **(2026-10-13, `perf/retained-subtrees` from `e85cb07a`: 3717 tests, 0 goldens, 234 typecheck guards** (3675 + 42 tests, 232 + the two of `RetainedSubtreeCompileGuards.swift`; `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `swift build --build-tests` 0 warnings, native unfiltered run on an unlocked screen all passed, `FR-J no-argument frame: succeeded=true`; also 3708 passed with `AppKitPresentationTests` skipped, and under `METALUI_VERIFY_RETAINED=1` and `METALUI_VERIFY_LAYOUT_MEMO=1`; census 3511; the fourteen images 0 px against `e85cb07a`; no divergence label taken; record §109 §6, §13). Before it,
  **(2026-10-13, `perf/incremental-invalidation` from `f6f865c1`, merged with master `d279f34d` (§101, §103, §105-§107), then `aa42fbc8` (§108 `frame(ofID:)`): 3675 tests, 0 goldens, 232 typecheck guards** (master's 3643 + the branch's 32 tests (baseline +1, lane 1 +16, lane 2 +15), 229 + 3 guards 1.13, 2.11a, 2.11b; re-measured by the orchestrator on the merged tree, record §104 §6). Before it, at `d279f34d`'s merge:
  **(2026-10-13, `perf/incremental-invalidation` from `f6f865c1`, merged with master `d279f34d` (§101, §103, §105-§107): 3654 tests run + 9 skipped (3663 expected unfiltered), 0 goldens, 232 typecheck guards** (master's 3631 + the branch's 32 tests (baseline +1, lane 1 +16, lane 2 +15), 229 + 3 guards 1.13, 2.11a, 2.11b; `swift package clean`, native run on a **locked screen with `AppKitPresentationTests` skipped** because its `NSOpenPanel.init()` hangs there, 0 recorded issues, 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`; census 3492 re-recorded after the merge; inventory and undocumented scripts print nothing; divergence 346 added, 152 live; the fourteen images 0 px against `f6f865c1` at the lanes, not re-taken after the merge; record §104 §6). Before it,
  **(2026-10-13, `fix/frame-of-id` from `d279f34d`: 3643 tests, 0 goldens, 229 typecheck guards** (3631 + 12 tests, no guard; `swift package clean`, native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else, 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`; no public declaration, census unmoved, no divergence label taken; the `MetalUITestingTests` set passed in the `metalui-portable` image; record §108). Before it,
  **(2026-10-13, `docs/guides-followup` from `b17aee19`, merged with master `8e7c78e3` (§105 performance baselines, §106 `runUntilIdle()` on Linux): 3631 tests, 0 goldens, 229 typecheck guards** (master's 3626 + 5 tests, no guard; 3629 before the merge; `swift build --build-system native --build-tests` then the native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else, 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`; no `Sources/` or `Backends/SDL` change, no public declaration, no divergence label taken; record §107). Before it,
  **(2026-10-13, `fix/rununtilidle-linux` from `848ee029`, merged with master `b17aee19` (§103 guides): 3626 tests, 0 goldens, 229 typecheck guards** (master's 3624 + 2 tests, no guard; `swift package clean`, native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else, 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`; no public declaration, census unmoved; the fourteen images 0 px against `848ee029`; no divergence label taken; the two mutations were run in the Linux image, the macOS `set(nil)` one on a filtered set; record §106 §5). Before it,
  **(2026-10-13, `docs/guides` from `ff8a1ea4`, merged with master `848ee029` (§98, §99, §100, §101, §102): 3624 tests, 0 goldens, 229 typecheck guards** (master's 3582 + 42 tests, no guard: the doc-check's 9, lane 1's 17, lane 2's 16; `swift package clean`, native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else, 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`; inventory and undocumented scripts print nothing; no public declaration, census unmoved; no `Sources/` or `Backends/SDL` change, the fourteen images 0 px; no divergence label taken; the Linux image ran the 26 lane-1 tests, the full suite not re-taken there; record §103 §5). Before it,
  **(2026-10-13, `feat/material-followups` from `930db4a`, merged with master `7f891629` (§99, §100), then `0fb2ea6e` (§98), then `f6f865c1` (§102 input-method driver): 3582 tests, 0 goldens, 229 typecheck guards** (master's 3566 + 16 tests, 225 + 4 guards; 3565 / 228 at `0fb2ea6e`'s merge; lane A's 4 tests and 2 guards, lane B's 12 tests and 2 guards; `swift package clean`, native run 0 `Issue`, 0 `error:`, `FR-J no-argument frame: succeeded=true`; inventory and undocumented scripts print nothing; the fourteen images scene-identical, 0 px against `930db4a`; divergence 315 added, 249 retired, 151 live after §102; `Backends/SDL` and the Linux image not re-taken; record §101 §6). Before it:
  **(2026-10-12, `feat/ime-driver` from `3fce05f`, merged with master `ff8a1ea` (§100 continuing press cancel), then `7f891629` (§99 text over a GPU surface), then `0fb2ea6e` (§98 resign on press): 3566 tests, 0 goldens, 225 typecheck guards** (master's 3549 + 17 tests, 224 + 1 guard 3.4; 3530 / 222 at `ff8a1ea`'s merge, 3546 / 223 at `7f891629`'s; `swift package clean`, native run 0 `error:`, `FR-J no-argument frame: succeeded=true`; census 3453 (3446 + 7: the input-method verbs and read-backs); divergences 325, 326 added, 151 live after §99; record §102 §5). Before it:
  **(2026-10-12, `feat/resign-on-press` from `5f35df6`, merged with master `ff8a1ea4` (§94 backdrop blur, §96 text selection, §97 window drag, §100 continuing press cancel), then `7f891629` (§99 text over a GPU surface): 3549 tests, 0 goldens, 224 typecheck guards** (master's 3529 + 20 tests, 222 + 2 guards; 3533 / 223 at `ff8a1ea4`'s merge; `swift package clean`, native build and run 0 `error:`, the only `warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`, no issue recorded; inventory and undocumented scripts print nothing, one public family; the fourteen images 0 px against `5f35df6`; divergence labels 285–294 unused, no divergence; record §98 §2). Before it:
  **(2026-10-12, `feat/surface-text` from `d6a815c`, merged with master `3fce05f` (§96 text selection, §97 window drag), then `ff8a1ea4` (§100 continuing press cancel): 3529 tests, 0 goldens, 222 typecheck guards** (master's 3513 + 16 tests (3520 at `3fce05f`'s merge), 221 + 1 guard 1.11: lane 1's 11, lane 2's 5; `swift package clean`, native run on an unlocked screen, all passed, 0 `error:`, the only `warning:` SwiftPM's deprecation notice; `FR-J no-argument frame: succeeded=true`; census 3452 (3446 + 6); divergences 295, 296 added, 149 live; the fourteen images scene-identical, 0 px against `d6a815c` at both lanes; `Backends/SDL` untouched; record §99 §7).
  Before it:
  **(2026-10-12, `fix/continuing-press-cancel` from `930db4a`, merged with master `3fce05f` (§96 text selection): 3513 tests, 0 goldens, 221 typecheck guards** (master's 3504 + 9 tests, no new guard; `swift package clean`, native run 0 `error:`, `FR-J no-argument frame: succeeded=true`, no issue recorded; census 3446 unmoved, no public declaration; no divergence label taken); record §100 §3). Before it:
  **(2026-10-12, `feat/text-selection` from `0abce86`, merged with master `930db4a` (§93–§95, §97): 3504 tests, 0 goldens, 221 typecheck guards** (master's 3472 + 32 tests, 218 + 3 guards G1–G3; `swift package clean`, native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues and nothing else, 0 `error:`; census 3446 (master's 3424 + 22); divergences 265, 266 added, 147 live; the merge's one source edit `Window.onInput` keeps both the selection `defer` and master's modifier report; record §96 §5). Before it:
  **(2026-10-12, `feat/window-drag` from `a720fba`, merged with master `5f35df6` (§95 `ForEach` identity), then master `d6a815c` (§94 backdrop blur): 3472 tests, 0 goldens, 218 typecheck guards** (master's 3446 + 26 tests, 217 + 1 guard 3.2; at `5f35df6`'s merge 3441 / 217; native run after `swift package clean` on a locked screen read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else; census 3415 (3405 + 10: `WindowDragGesture` and its members, `performWindowDrag`, `windowDrags`, `performsWindowDrag`; the tsv re-recorded after the merge for AppKit's line shifts); divergences 275–277 added, 145 live after §94, next label 206; `Backends/SDL` 24 + 114 on macOS (113 + 1), the Linux image not re-taken after the merge; the fourteen images 0 px against `a720fba` on the merged tree; record §97 §4, §6). Before it,
  **(2026-10-12, `feat/backdrop-blur` from `f2fe54a`, merged with master `5f35df6` (§91 harness, §92 overlays, §93 input follow-ups, §95 `ForEach` identity), then record 94 §11's three pins: 3446 tests, 0 goldens, 217 typecheck guards**
  (master's 3415 + 28 tests, 216 + 1 guard: lane 1's 16 (8 record, 3 scene, 4 reference, 1 guard), lane 2's 12; `swift package clean`,
  native run on a locked screen read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, the
  default build system 0 `warning:`; census 3414 (3405 + 9); `Backends/SDL` 30 + 123 on macOS (30 + 120 in the Linux image, branch checker; lane 3's 10 `SDLBackdropTests` and
  the `ReplayFixtureTests` growth), replay parity re-taken by the branch checker after the merge: 12 fixtures, SDL Metal 0 px,
  Windows D3D12 unmeasured (CI); divergences 245–249 added, 166 amended, 142 live; the fourteen images 0 px; record §94 §5, §7). Before it,
  **(2026-10-12, `fix/foreach-identity` from `280d706`, merged with master `a720fba` (§92 overlays, §93 input follow-ups): 3415 tests, 0 goldens, 216 typecheck guards**
  (master's 3402 + 13 tests, 215 + 1 guard `G1`; native run after `swift package clean` on a locked screen read exactly the five
  `AppKitPresentationTests` sheet issues and nothing else; census 3361 + master's growth, count unchanged by this branch; divergence 79 retired, 255
  added, header's count 137 live; the fourteen images 0 px against `280d706` before the merge; record §95 §2). Before it,
  **(2026-10-12, `feat/input-followups` from `f2fe54a`, merged with master `0abce86` (§91 harness, §92 overlays): 3402 tests, 0 goldens, 215 typecheck guards** (master's 3363 + 39 tests = 18 + 11 + 10 by lane, 213 + 2 guards, both lane 1's; native run after `swift package clean` on a locked screen read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else; census 3405 (3392 + 13); `Backends/SDL` 24 + 113 on macOS, 24 + 110 in the Linux image at the lane runs, not re-taken after the merge; divergences 235, 236, the header's count and next label the merge's; record §93 §4). Before it,
  **(2026-10-12, `feat/overlays-coords` from `ebcf3c7`, merged with master `280d706`: 3363 tests, 0 goldens, 213 typecheck guards**
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
  merge), §72, §73, §74, §75, §76, §77, §78, §81, §82, §83, §84, §85, §87, §88, §89, §90, §91, §92, §94, §98, §99, §101, §102, §103, §104, §106, §109, §110, §112, §114, §115, §116, §121, §122, §123, §124, §126, §127, §128, §129, §130, §131, §132, §133, §134, §135, §136, §137, §138.
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
  `onAccessibilityReduceMotionChange`, `accessibilityReduceTransparency`/`onAccessibilityReduceTransparencyChange` (`MT-D`), `beginExternalDrag(_:at:)`, `presentMenu(_:at:) -> Bool`, `setPreferredColorScheme(_:)` (`CR-M`), `presentFileDialog(_:) -> Bool`, `presentAlert(_:) -> Bool`, `dismissPresentation(token:)`, `setContentSizeLimits(minimum:maximum:)` (`SV-B`), `setToolbar(_:) -> Bool` (`MD-J`), `setPointerStyle(_:)` (`CI-J`), and the app shell's seven — `onCloseRequest`, `close()`, `setDocumentEdited(_:)`, `setRepresentedFilePath(_:)`, `setTitleBarStyle(_:) -> Bool`, `titleBarInsets`, `performTitleBarPress(clickCount:) -> Bool` (`AS-H`, `AS-J`), and `performWindowDrag() -> Bool` (`WD-E`), and the clipboard's four — `writeClipboard(_ representations:) -> Bool`, `clipboardTypeIdentifiers()`, `readClipboard(identifier:)`, `setClipboardCommands(_:)` (`CB-E`) — have no
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

**Environment epoch (`EE-`, record §120).** No epoch counter: an `.equatable()` component that declares `@Environment` is skipped
while the **readings** of its declared properties are unchanged (`Environment.probe`, collected by `StateBinder.bind` into
`Frame.environmentReadings`, stored in `ContentMemoStore.Entry.readings`): an `Equatable` value by `==` (one `as? any Equatable` per custom-key
write; an isolated conformance compares on the main actor only), a class or `@Observable` instance by identity (the probe reads
`values.object(_:)`, **never the trapping `read`**), read properties by the one observation session; a declared property the getter never
reads still counts (`EE-A`…`EE-D`). **Still refused and counted** (divergence 346, narrowed; `@FocusState` is memoized since `RZ-`, below): any uncomparable reading
(a closure, a struct holding one, `\.self`, `\.textMeasurer`). Retention keeps its whole-position ambient (`EE-F`): the fingerprint gains
`custom` readings and provided object **instances** (`EE-K`), an unread change at the position skips the getter but misses the replay
(C14-c3), and `uncomparableCustomCount` replaces `customKeyCount` at the three retention sites (the graft site is unseparated, C14-c4).
No public declaration. Pins count work (`EnvironmentReadingTests`, `EnvironmentEpoch*Tests`).

**Retained read-only state (`RW-`, record §121).** C14b-3: a framework **read of `StateTable` is not a write**. `readState` (no version
bump, no taint, marks the entry live, records a read) and the compared `withState(_:initial:unchanged:_:)` (an equal result is a read, a changed
one today's write) sit beside the **plain `withState`, which keeps bumping and tainting**: a new framework site picks one of the three and
`everyStateWriteSiteIsClassified` counts them per file; input-time writers stay plain and always bump (`RW-G`); `unchanged:` is a call-site
closure, never a protocol on `ScrollState`/`ListOrigin` (public, `RW-Q`). **A frame-long read journal** (`StateTable.readJournal`, appended
while retaining, `peek` included; a slot with its own channel (`$ax`, `$focus`, `$anim`) is not a read) gives the paint record, the prepaint
ledger and the graft record a read set of `(id, version)` that must be unchanged for a hit, a mismatch being a counted **miss**; liveness
runs in three channels (the record's `marks`, the ledger's `liveStates` through `touchLive`, the graft's `.liveState`) so a replayed field's
`TextEditState` is not swept (`RW-E`); a replay re-notes what it stands for. A creating read, a clamp that changes the offset and a first
sighting are writes (`RW-F`); a record made then gains its ledger one counted miss later (`RW-S`). **Eligible now:** an unfocused
`TextField`/`TextEditor`, a settled `ScrollView`/`ProposalScrollView`, a `List` whose window did not move, a closed `Picker`/`Menu`/`.popover`
declarer (its anchor replays from the ledger, `RW-K`). **Still miss or refuse, by name:** a focused field, a typed character, a wheel or drag, a
selection change, `scrollTo`, an open popover, alert or dialog, a `GPUSurface` (`surface`, carried `RW-L`), `.continuous` always.
`FrameWork.retainedIneligibleReasons` counts the three ineligible counters by channel name (`RW-M`); `METALUI_VERIFY_RETAINED=1` also traps
`unrecordedRead` and `writeMissed` (`RW-O`). **A read a record does not name is a stale replay**: a new framework read of state goes through
`readState`/`peek`, never a private store. Orbit with panels: element requests 115 to 6, prepaints 117 to 7, ineligible 1/2/1 to 0/0/0. One
public `MetalUITesting` field, no divergence (labels 515–524 untouched), no SwiftUI probe. The demo's panel strip is `METALUI_RETAINED_DEMO=1`.

**Pan rasters (`PN-`, record §118).** Value-identical, no public API, no divergence (labels 485–494 untouched). A path with
**no local mask** whose conservative extent `E` (`RasterAnchor.pathExtent`: bounds with the stroke pad, grown 1) meets the clip, has
area ≤ `RasterAnchor.overscanLimit` (2^20) and lies within half the target's size of it on every side is rasterized over `E`
and keyed `.uncut`, **not by its clip**: the image's content mask cuts at draw time, so a whole-device-pixel pan across a
`.clipped()` edge hands back the same `ImageTexture` and rasterizes 0 pixels (`PN-A`, `PN-B`; amends `PF-J` item 2 for paths only,
bytes measured equal, T2). A placed mask wholly outside the clip draws no image (`PN-G`). Mode 3 keeps today's keys (`PN-C`); shadows, blurs and full
gradients took the same overscan in `OS-` (below). `RasterCache.tint` zero-fills and multiplies only the 8-byte words holding
coverage, byte for byte the reference loop (`RasterCache.lastTintedPixels` counts the pixels multiplied, `PN-D`); R8 coverage with a
shader tint is not built (P3c, `TE-AD`). A cubic whose endpoint moves and a sub-pixel pan miss by design (`PN-E`). Pins count work
(`PanRasterTests`).

**Layout and build allocations (`PA-`, record §119).** Value-identical, no public API, no divergence (labels 495–504 untouched). Hot
loops of the kernel and build do not allocate per node: `roundedRect(_:)` is the scalar `roundLayout` forwards to, `graft` reserves
**geometrically** (`reserveCapacity` is exact in Swift: never `base + n` per call, `PA-C`), a leaf key's signature words are a
`LeafKey` computed at registration and mixed in the old order so every signature is unchanged (`PA-D`), `NativeMeasurementKey`/
`MeasureKey` hash one folded word with `==` complete (`PA-K`, `PA-N`), `StateTable.mark` writes through `index(forKey:)`. The
`measureNative` order and arguments, the four layout counters and `ForEach`'s `FI-B`/`FI-K` names are untouched. **An allocation pin
is thread-filtered (`countAllocations`, Darwin only), differential and floor-corrected**: a debug build logs several events per
`malloc` and allocates per `for-in` turn (`PA-J`, `PA-O`, `PA-Q`); release allocation figures are dated measurements, not pins.
Deferred: `AmbientKey` reshape (C14-c), array-indexed measure cache (P3); the isolation-site share is unre-measured after the loops.

**Finer retention scopes (`FS-`, record §126).** No implicit element, row or modifier scope: the retention unit stays an `.equatable()` `Component`, whose
changed row already misses alone (`FS-A`, `FS-B`). **A `List` row replays its prepaint and grafts** because a paint **hit** whose prepaint ran refreshes the standing
record's stale ledger (`RetainedSubtree.refreshLedger`, only when `ledger.reads` is a subset of `record.versions`, `FS-N`); the graft site's `uncomparableCustomCount`
conjunct is gone, `BuildKey.environment` refuses (`FS-H`). **A row that moved by layout (K1) or scroll offset (K2) replays translated** (`RetainedShape.shift`,
`ReplayKey`/`PrepaintKey.shapeInterior`, `Frame.movedPaintRecord`/`movedPrepaintLedger`, `RetainedTranslation.swift`; extends `RK-G`/`RK-S`, never forks it): accepted only for
a **whole-device-pixel** delta on exact (1/16, below 2^19) numbers (`FS-M`), leaves rect, glyph, image (path, gradient, surface, shadow, blur, backdrop, an inner paint scope, a
transformed primitive refuse by name), a mask moved only when strictly inside the entry clip; hitboxes keep their uncut rect and clip depth (`Hitbox.unclipped`) so a scroller's cut
is recomputed, and the pointer is read against the moved hitboxes (`FS-P`); accessibility records, press-only actions, menus and handler hitboxes refuse; a hit rebases record and
ledger. `METALUI_RETAINED_TRANSLATION=0` / `Window.testingRetainedTranslation` is the A/B. One public field, `FrameWork.retainedTranslationRefusedReasons` (class M); no
divergence (labels 555-564 untouched). Shifted frame 171 / 172 / 244 -> 3 / 4 / 4 with the graft; pins count work. Carried then, built or pinned in record §128 (`RG-`): placement-memo translation (`FS-G`), the unpinned
`hitboxClipped`, a shift under a moved render effect. Demo: `METALUI_RETAINED_DEMO=1`'s shift-and-scroll strip.

**Sample app (`EX-`, record §136, `Examples/Jotter/README.md`).** `Examples/Jotter` is the repo's one real app: a notes app in **its own SwiftPM
package** (library `JotterKit`, executable, `JotterTests`) depending on the checkout by path with the scaffold's products and traits (`EX-A`, `EX-B`;
not a root target, so no PC-A list, census or CI build of the root grows), built and tested on macOS and in the Linux image with the SDL trait. It uses
only existing API: no `Sources/` change, no divergence, no public declaration. Its tests run over `MetalUITesting` the way `docs/testing.md` tells an
author (21, 20 off Darwin). **A change to `docs/packaging.md`'s recipe, `App`'s initialisers, the scaffold's manifest or an API the app uses can break
it**: run `METALUI_RUN_SAMPLE_APP_TEST=1 swift test --filter aSampleAppBuildsAndItsTestsPassAgainstThisCheckout` (the root's two manifest/docs tests run always,
CI runs `swift test --package-path Examples/Jotter` on macOS and in the Linux image). Every section is its own `Component` (1 MB stacks); a `List` row is one
`Element` (a `Column` around an `.equatable()` component); `.focused($flag)` goes on the control before any wrapper (`EX-N`). Rough edges are findings in
record §136 §2, not fixes.

**Windows release-build crash (`WR-`, record §139).** Value-identical, no public API, no divergence (685-694 untouched). The asserts compiler (Windows CI's 6.4.0+Asserts, the Mac development snapshot) crashed in **release only**
verifying SIL for a closure-specialised `PaintPass.withRenderEffects` ("return with stack allocs that haven't been deallocated"; debug green): **`withRenderEffects` is an `@_optimize(none)` entry with no guard over a private
index-based `openingRenderEffects(_:upTo:...)`** (`WR-B`; optnone alone, or a guarded entry, still crashes, measured). The index form passes `count - 1` to `legacyShadowColourKey`, as the shrinking slice did (`WR-C`, pinned by
`everyLegacyRenderEffectOpensItsScopeAtItsIndex`). **Guards:** every release arm of the env-gated `AssertsCompilerTests` (all build MetalUI; the `Effects` fixture names this one) and a `root-windows` step `swift build -c release --product MetalUI`
(cost unmeasured on Windows, human check WR2). Remove the optnone when a toolchain bump makes `docs/probes/windows-release-crash/repro.sh` pass on the unmodified function (`WR-E`).

**Warm and cold frames (`CF-`, record §127).** Value-identical, no public API, no divergence label (565–574 untouched; 346 narrowed). `@Environment(\.textMeasurer)` is a
comparable `EnvironmentReading`: the text system **instance** (never the per-frame `TextSystemBox`) plus the two default `ResolvedTextStyle`s it resolves, so an
`.equatable()` reader is skipped, not refused (`CF-A`). A redo frame's `contentEvaluations` carries the abandoned attempt's getters; every other counter is the redo's own
(`CF-C`, `CF-D`). **A subtree placement restored from `LayoutMemo` touches its `Footprint`** (the `MeasureKey`s and inner `PlacementKey`s its recording looked up, run-cache hits
included), so the next frame's grafted occurrence still finds its measurements and `warm[n] == warm[n+1]` holds over the whole `FrameWork` from the frame after the records
exist (`CF-E`, `CF-J`); the root placement has no footprint, a named residue. The cold-frame profile found no ledger-snapshot cost and landed no fix (`CF-K`). Pins count work.

**Retained lifecycle (`RL-`, record §131).** Value-identical, no public API, no divergence (labels 605-614 untouched). **A replay or graft re-notes presence into the store and never computes a delivery** (`RL-A`): `LifecycleStore` forgets any key a build did
not note, so `onAppear`/`onDisappear`/`onChange`/`.task` inside an `.equatable()` occurrence no longer refuse the graft: their notes are build-journal events with relative orders re-noted by `Frame.reapply` (`RL-C`, `GraftRecord.lifecycleOrders`; not a `StateTable`
write site), `onModifierKeysChanged` is a ledger `ModifierNoteRecord` holding no value (`RL-B`, amends `RG-D`), and the store's diff decides every delivery in `drainLifecycle`, outside every phase (LC-F, LC-H, TF-A, PX-F). A replayed closure is the standing one (`RL-L`).
`BuildAudit.lifecycle` is now a tripwire for a registration that bypassed the journal (**a new lifecycle-registering site goes through the journal**, `RL-D`); verify mode gains channel `lifecycleStore`. **Translation carries:** a layout, scroll or effect translated replay
**recomputes** a geometry note (proxy rebuilt, `transform` run again; a named space declared inside moves with it only for a linear part of multiples of 1/16, else `geometryNamedSpace`; a note under the occurrence's own effect refuses a layout shift `geometryUnderEffect`; an outer
named space never reaches a note, `RL-E`, `RL-O`) and `RG-J` narrows to a note a translation cannot recompute (`RL-G`, `RL-Q`: a grafted observer costs 0 redos across a shift); layout translation moves accessibility records by the hitbox rule (`AXEmission.clipDepth`,
`accessibilityClipped`, `accessibilityUnderEffect`, `RL-H`, amends `AT-C`); a hitbox inside the occurrence's own effect is re-derived from a **validated** step chain (`Frame.hitboxChains`, `RL-I`, closes `AT-G`). **`surface` stays refused** (`RW-L`, `RL-M`: one paint per
frame, a replay would owe the registry touch and the standing draw closure). Carried: a note under an effect on a layout shift, a non-dyadic named space, `FS-G`. The `rebased` modifier copy and `movedAccessibility`'s `clipDepth` arm are pinned (`aRebasedLedgerCarriesItsModifierNote`, `aLayoutShiftMovesARecordCutByAClipInsideTheOccurrence`, record §131 §8). Pins count work.

**Retained zoom (`RZ-`, record §133).** Value-identical, no public API, no divergence label (625-634 untouched; 346 narrowed). **An affine change of an outer render effect (scale, rotation, translation) replays and grafts** instead of refusing: a replayed record re-enters the **live**
scopes through `processScopes`, so nothing is re-pointed (`RZ-A`), text and images are resampled under a scale (divergence 106) and a vector raster (path, gradient, shadow, blur) re-keys through `RasterAnchor` at insert, work equal to a fresh frame (`RZ-C`). The key relation admits a change confined to the
six affine numbers (and the inverse's) of `.effect` scopes with equal flattens class, alpha, outer clip, entry depth and counts (`ReplayKey.differsOnlyByEffectAffine`, `PrepaintExtras.change(from:)`, `RZ-B`); the prepaint effect vector gains index 18, `effectFlattens`, **appended: a new entry appends, indices 0...17 are read by number** (`RZ-M`);
hitboxes re-derive with no delta (`AT-F`, `RL-I`), accessibility through `AT-A`, geometry notes through `RL-E`, and the pointer is read against the **moved** hitboxes in both effect arms (`RZ-D`, `RZ-O`). **`effectNotTranslation` is retired; every refusal is named** in `retainedTranslationRefusedReasons`: `effectFlatteningChanged`, `effectClipChanged`,
`effectInverseChanged`, `effectScopeChanged`, `effectCountChanged`, `prepaintContextChanged`, `geometryNamedSpace`, `presentationAnchor`, `contextMenus` (the last three and the flattens class are conservative: the frame stays equal to a fresh one without them, `RZ-M`, `RZ-P`; a lift cites that evidence). Ten nodes, one zoom step: element requests 115 to 5, grafts 0 to 10, redos 1 to 0.
**`@FocusState` is memoized** (`RZ-T`, C14-c2): its `$state<n>` slot is a memo slot (`stateOrdinals`) and `FocusState.Box.reconcile`'s version bump is the changed reading, so an `.equatable()` focus reader is skipped while focus is unchanged and evaluated when it moves; a graft's journal `.focusState` arm re-notes it. **Fillet drag** (`RZ-S`): no framework refusal found; a panel set bound to **one `@Observable` array property** misses on every panel (observation is per property), by design: give each panel its own object. Carried: layout move plus effect change together (`effectAndLayoutMoved`, `FS-O`), a named space under a zoom, lifting the conservative refusals.

**Retained geometry (`RG-`, record §128).** An `.onGeometryChange` scope in an `.equatable()` occurrence no longer taints its prepaint ledger (`RK-E` is replaced): `Frame.noteGeometry` records a
`GeometryNoteRecord` and an equal-key replay **re-notes it in order into the lifecycle store** (a skipped note is a G7 re-report of `initial`, since `closeGeometry` drops an un-noted key); `KF-J`'s
delivery is unchanged (`RG-A`, `RG-B`). A translated replay of a ledger with a note refused `geometryTranslated` (`RG-C`) and such a ledger was never grafted (`RG-J`); `onModifierKeysChanged` stayed a taint (`RG-D`): **all three superseded by `RL-` (above)**. **A subtree placement restored from `LayoutMemo` at another origin is translated**
(`translatedPlacements`, origin-free key `(signature, proposal, width, height)`, per axis a bit-equal or exact-sixteenth origin against an exact record, never a subtree holding a `.custom` layout, checked by
`METALUI_VERIFY_LAYOUT_MEMO=1`; it carries the `CF-E` footprint, `RG-L`, `RG-P`); a card in a plain stack misses (the proposal moves). `hitboxClipped` is pinned (reachable only where the clipped region paints
nothing, `RG-M`) and a shift under a moved render effect still refuses, now counted `effectAndLayoutMoved` (`RG-N`). **`GlyphAtlas.dirtyRects`** is a list (same-shelf x-adjacent slots merge, cap 8, then one
sticky bounding rect until `clearDirtyRect()`), `dirtyRect` its computed union: Metal `replace`s per rect, SDL packs one transfer and copies per rect (`mui_renderer_finish` takes rects), the headless counter is the
sum of areas (`RG-H`, `RG-I`, `RG-O`). One public declaration (`dirtyRects`, class M), no divergence (575-584 untouched), no shader change. Pins count work.

**Accessibility under an effect-translated replay (`AT-`, record §129).** Value-identical, no public API, no divergence (labels 585-594 untouched). An effect-translated prepaint replay
(`RK-G`, `RK-S`) **carries accessibility records**: a record made under a render effect keeps the operands of its frame (`AXEmission.local`, `PrepaintLedger.axNodeLocals`: the pre-effect rect, the
clipped rect, the effect steps as `AXEffectChain`) and the replay **recomputes** the frame and visible frame against the current effect with `prepaintWithRenderEffect`'s own arithmetic, never shifts a
bounding box (a shifted box rounds twice; `AT-A`, `AT-G`). `translation(from:)` and `translatedHitboxes` no longer assume an identity linear part: a hitbox carrying the ledger's ambient inverse takes the current
effect's (`AT-F`). A scale or rotation change replays since `RZ-` (below; `effectNotTranslation` is retired). **A new record made under an effect owes its local rects** (else `accessibilityUnrecorded`, a counted miss). Layout translation's `accessibilityRecords` refusal and a hitbox opened inside the occurrence's own effect under a non-identity scale (`hitboxes`) were carried here and are built in `RL-` (above). Pins count work
(`AXTranslatedReplayTests`).

**Raster overscan and the pooled scratch (`OS-`, record §124).** Value-identical, no public API, no divergence (labels 545–554 untouched).
`shadowImage`, `blurImage` and the full `gradientImage` call `RasterAnchor.overscanned` as `pathImage` does (`PN-A`; `OS-A`): rastered over
the kind's conservative extent `E` (`RasterAnchor.shadowExtent`/`blurExtent`/`gradientExtent`, the expressions the keys already held, nested
reach and `BoxBlur.padding` included), keyed `.uncut`, the image's content mask cutting at draw time, so a whole-device-pixel pan across a
`.clipped()` edge hands back the same `ImageTexture` and rasterizes 0 pixels. Same predicate and `overscanLimit` as paths (`OS-D`); **mode 3
(a local mask) and the gradient strip keep today's keys** (`OS-E`, `OS-G`; S7 characterizes the miss). **A pin that reads a raster's bounds
reads the extent `E`, not the clip.** `RGBALayer.init(mask:color:)` returns `.empty` for an empty mask (`OS-N`, a latent
`0×12 has a zero side` trap). **`RasterScratch`** (`MetalUIPath`, `package`, imports nothing) is one reusable cell buffer and three `Int32`
buffers owned by `RasterCache` and borrowed `inout` per call, zero-filled on take, an over-`2^22` buffer dropped on return, empty while out so
a nested raster cannot alias (`OS-L`); a call site never holds `&cache.scratch` across a `make` closure. Its win is memory traffic
(allocated bytes -20.6 % on `shadow-drag`), **not time** (`OS-P`). Pins count work, never time (`RasterOverscanTests`, `RasterScratchTests`).

**Lazy containers (`LZ-`, record §134).** `LazyVStack`/`LazyHStack`/`LazyVGrid`/`LazyHGrid`/`GridItem` are SwiftUI's spellings (class A; probe `swiftui-lazy-containers.swift`)
over non-`Hashable` `ProposalLayout`s (`LazyStackLayout`, `LazyGridLayout`) that taint exactly their ancestors (`LZ-F`, `IV-`). A container's content is read as **units**
(`LazyUnits.swift`: a `ForEach` element, a static leaf or component, legacy rows through `LegacyContent`); an `if`/`switch`/`for` member makes it **eager and counted**
(`FrameWork.lazyUnbounded`, divergence 636). **One window, never forked:** `LazyLinePlanner` runs `List`'s variable-row window over lines (a stack's child, a grid's row) on the
**unchanged `RowExtentIndex`** (`LZ-C`); the viewport plus two lines each side are realised (divergence 637), a cold slice is 32 lines, unrealised lines count as the measured mean,
the anchor holds across measurements (`VL-G`), and outside a scroller everything is realised. A scrolled-out child keeps `@State` the `List` way (`TB-AH`); accessibility exposes
realised children only and no list position (`LZ-J`). A stack's cross size is the proposal else the **first** child's (the "widest realised child" premise was refuted). Grid tracks
come from `GridTrackSolver` (`MetalUILayout`, `package`, pure); `GridItem.alignment` is `ProposalAlignment?` (nil takes the grid's); an adaptive item's count is decided at build time
from the previous frame's width and corrected by one more frame (divergence 638, `LZ-L`, `LZ-Y`); a `ForEach` element producing several views is one cell (635). `pinnedViews:`/`Section`
are not built (`LZ-N`). A new framework state write in these files is classified in `everyStateWriteSiteIsClassified`. Pins count work (`lazyUnitsRealized`, `lazyLinesRealized`). Demo `METALUI_LAZY_DEMO=1`.

**Memo observation off the main thread (`MO-`, record §123).** An `.equatable()` occurrence's decision flags (`stale`, `observedChange`, the
serials a handler compares, a monotonic `changes`) live in one **locked** `MemoFlags` per entry (and per `RetainedSession` for its serial) and
are set **synchronously by whichever thread the observation `onChange` fires on**, never behind a `Thread.isMainThread` hop: off Darwin Swift
Testing's main actor is a pool thread, so the old flag arrived after the next frame's skip, replay or graft decision (`MO-A`; the same fact as
`RU-A`). `Entry.stale`/`observedChange`/`serial` are forwarding properties — a stored `var` of those names reopens the bug. The handle holds the
`MemoFlags` strongly and the entry, store and session weakly (`MO-B`, `IV-R`); `armed` and `markDirty` stay behind the old branch and decide
nothing (`MO-C`; `armedSessions` lags off Darwin). `materialize` clears `stale` in the locked step that bumps the serial, before the getter
(`MO-D`); a record's clear is a no-op when a fire landed since its phase opened (`MO-F`). No public API, no divergence. **Pins:** both red on macOS: a real `Thread`
writing a retained-only model (`MO-G`) and `MO-F` through the `package` seam `RetainedTestingHooks.beforeRecordClear` (record §123 §6).

**Single-instance launch on SDL (`SN-`, record §122).** `SingleInstance.claim(id:forwarding:configuration:)` (`MetalUISDL`, trait `SDL`,
MetalUI-only class `M`, in `Backends/SDL` so outside the census, no seam change, no divergence label) elects a **per-user** primary and
returns `.primary(role)`, `.forwarded` or `.unavailable(Failure)`; the role goes in `SDLPlatform.Options.singleInstance` (`launchingSingleInstance`
does both and returns `nil` for the second launch to exit 0). The transport is the pure C file `SDLInstance.c` (`CB-H`: no Swift closure, no
actor hop): Linux and macOS elect by `flock` and carry on a 0600 Unix socket in a user-owned 0700 directory, Windows elects with a **named
semaphore** (a mutex is recursive on its thread, `SN-P`) and carries on a session-scoped pipe; peer uid or SID is checked and never executed.
A message is magic, count and length-prefixed UTF-8 strings (1024 strings, 32768 bytes each, 1 MiB, no NUL, a declared length over the limit
allocates nothing); a malformed one is refused and the listener serves on. The listener queues (64 pending) and pushes an SDL wake; `pumpEvents()`
drains on the main actor into `handleApplicationOpen` (`AS-G` routing, parked until a handler, one `onOpenURLs` batch per launch) and raises the
key window, else the first, never a hidden one. A failed forward runs the launch independently (`SN-F`). **A new `SDLPlatform` test arms
`armMainRunLoopExitCheck()`; Windows is compiled by CI only (check SI3).** Deferred (`SN-L`): D-Bus activation, activation tokens, a reply channel.

**SDL application id (`AP-`, record §132).** `SDLPlatform.Options.applicationID: String?` (`MetalUISDL`, trait `SDL`, MetalUI-only class `M`, `Backends/SDL` so outside the
census, no divergence label, no SwiftUI claim) is what Linux shells match to a `.desktop` entry (Wayland `app_id`, X11 `WM_CLASS`): `mui_platform_init` sets `SDL_HINT_APP_ID`
at **normal priority immediately before `SDL_Init`**, on every path (`.headless` and offscreen included), so an exported `SDL_APP_ID` still overrides (`AP-A`, `AP-B`; probe
`docs/probes/sdl-app-id-hint.c`). `launchingSingleInstance(id:)` fills a `nil` field with its `id`, an explicit option winning; a `SingleInstance` passed straight through
`Options` defaults nothing, and with neither nothing is set (`AP-C`). `Options.usableApplicationID` ignores an empty, whitespace-only or NUL-bearing value, never a trap; no
`SDL_APP_NAME` (`AP-D`). **Order is pinned by C recorders** (`mui_app_id_*`, written in the production path), never by an `SDL_GetHint` read-back, because SDL is refcounted
(`AP-E`, `AP-F`). macOS and Windows accept it with no visible effect. Check `AP1`. Deferred: `SDL_APP_NAME`, a Windows AppUserModelID, per-window ids.

**Input follow-ups (`IF-`, record §93).** `SpatialTapGesture.Value.modifiers` (the last
press's) and `DragGesture.Value.clickCount` (the press's, never the move's) are MetalUI-only
values (divergence 235); `onCancelled` on drag, magnify and rotate runs **once, only for a
leaf that had reported**, from a dropped primary arena, a replaced stale button or pinch arena,
a `.mouseMoved` while a button arena is live (a lost release), key loss and window close —
never for a disabled gesture or a removed owner (`IF-E`, `IF-K` 3; divergence 236; the
reset is `@GestureState`, `GS-`). A wheel scroll **latches** to the cover of its `.began` through its momentum
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
call, check WD1); SDL answers `false` (divergence 276: its drag is a hit-test region, `CW-E`; before `CW-` no region list:
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
`StateTable`, swept last); `==` decides; an `@Environment` component with an uncomparable reading is refused, evaluated every
frame and counted (divergence 346; `@FocusState` is memoized, `RZ-T`). Build recursion, prepaint and paint stay whole, so the win is **counted, not
timed** (`FrameWork` memo and content counters; pins count work). Retained subtrees are built as paint replay and the placement memo (`SB-`, below); carried:
an environment epoch (C14-c), per-row `List` scopes (C14-d). GT-F stands: `drawText` is deferred (`IV-O`).
A main-actor test off macOS does not idle after a tracked frame (the observation hop), so a session-count pin
is Darwin-only (`IV-Q`). **A memo or retained observation handle holds its entry and store weakly** (`IV-R`): its `onChange` lives in the observed model's registrar and the entry's pristine content holds the model, so a strong hold is a cycle that outlives the window (`MemoryReleaseTests`). The demo is `METALUI_INVALIDATION_DEMO=1`.

**Retained subtrees (`SB-`, record §109).** C14b, two lanes, no public API beyond `FrameWork`'s ten counters, no divergence.
**Lane 1 replays an `.equatable()` occurrence's paint, not prepaint** (`SB-AA`: the paint-only ambient — opacity stack, shadow, blur and
composite scopes — is pushed by ancestors' `paint` after every prepaint, so a prepaint decision cannot see it): the decision, the
`ReplayKey` and the recorder are in `paintGroup`; build, layout and prepaint still run. A record hangs off the `ContentMemoStore` entry
(swept with it) and hits only while the value, bound `@State` versions, observed reads, layout, the ambient at paint and the whole
environment are equal and the hovered, pressed or focused element is not under it (`SB-X`); a descendant whose content ran kills its
ancestors' records (`SB-AC`); a subtree that scrolls, edits text, animates, shows a popover/alert or draws a surface, or sits under a
custom environment key, is ineligible (a settled scroller, an unfocused field, a `List` and a closed popover declarer are not, since `RW-`, record §121). **Scene output equals a fresh frame:** `METALUI_VERIFY_RETAINED=1` runs the fresh paint beside
every replay and traps (`SB-W`); a test that must see every prepaint sets package `Window.testingRetainedSubtrees = false`. **Lane 2 is
the subtree placement memo alone** (`SB-AD`): `LayoutTree.markPlacementRoot` roots restore their unrounded pre-order rects from
`LayoutMemo` under `PlacementKey(signature, proposal, bounds)`, origin included, no translation; `Color` and empty containers are keyed
leaves; `METALUI_VERIFY_LAYOUT_MEMO=1` covers it. Carried together (`SB-AE`): the graft, the `StateTable` journal, the counted redo,
prepaint replay and the build skip. Measured on the bracket fixture (`BracketFixture.swift`, node drag): element paints 1084 -> 178 per
frame, release median -18 %, debug -14 %; **pins count work, never time**. A new `Frame` site that pushes paint-only ambient owes a
field in `AmbientKey`. The demo is `METALUI_RETAINED_DEMO=1`.

**Retained build skip (`RK-`, record §110).** C14b-2, no public API beyond ten more `FrameWork` counters, no divergence (405–414 unused),
`Backends/SDL` untouched. **Prepaint replay:** an `.equatable()` occurrence's prepaint registers into a `PrepaintLedger` (hitboxes in
the one ranking's order, focus, accessibility records and nodes, press-only actions, context menus, element bounds, tallies) replayed
while its key is equal; **a paint-time ambient (SB-AA) that differs for a replayed prepaint abandons the frame after paint and
`Window.buildAndAdoptFrame` builds it again once with every replay off** (the redo; `AnimationStore.checkpoint`/`rollbackBuild`, 8
builds of window backoff, a per-entry doubling quarantine): **a store a build mutates non-idempotently owes a `rollbackBuild`**. A
render-effect translation replays through the live scopes (translated replay; a hitbox clip that depended on it refuses, `RK-G`, `RK-S`).
**The graft:** an unchanged occurrence skips its build recursion (`RetainedGraft`): its layout rows come from a recorded
`LayoutSegment` (`LayoutTree.graft`, every table restamped), the `StateTable` events its build made are applied again through the
table's own funnels (`BuildJournal`, `Frame.reapply`: ID-C/ID-R sweeps, `noteNamed`, `entryVersion`), a grafted `ComponentLayout` has
no payload, a pointer, press, focus or hover under it grafts nothing, and a wrong decision is the same redo; a refusal is counted by
name. **A new `StateTable` write site owes a journal event**. `METALUI_VERIFY_RETAINED=1` builds every replayed or grafted frame twice
and traps naming the channel (`RK-N`, `RK-V`, `RK-AA`). Measured on the bracket node drag: element requests 798 -> 208 (`.value`) and 167 (`.panels`),
prepaints 886 -> 219 and 176, release thread-CPU -23 % to -26 % (dated, a shared Mac); **pins count work, never time**. `drawText`
stays deferred (`RK-I`). Carried: layout or scroll translation, popovers and surfaces inside a subtree (C14b-3), an environment epoch
(C14-c), finer scopes (C14-d). The demo's switches are in `METALUI_RETAINED_DEMO=1`.

**Hot paths (`HP-`, record §111).** P1, value-identical, no public API, no divergence: every change leaves the fourteen images
0 px and every work counter equal. CoreText placement is cached **per `ShapedText`** in a `PlacementBox` (runs read once; the
finished `[PlacedGlyph]` and the rich layout memoised by origin x/y, scale and requested font as bit patterns — a key missing a
component draws stale glyphs, pinned per component for plain and rich); `GlyphRaster.subpixelPlacement` stays the one rule (PT-C),
run on a miss. `GlyphKey` and `RasterKey` store a hash folded by their initialisers/`add…` (bijections, `==` still compares fields;
`MetalUIScene` stays Foundation-free); a raster hit is one probe; a `LocalizedStringKey` literal parses once per process
(`MarkdownContentTable`, lock-guarded). Settled animation paths return before allocating (`inFlight` empty and every value
bit-equal; NaN and -0.0 take the old path). **A closure passed from `@MainActor` code to a stdlib generic costs a dynamic
isolation check per call: a hot loop uses a plain loop or a nonisolated function** (`HP-C`, `HP-I`). Counters are read-backs
(`PlacementBox`, `AnimationStore.borderKeyBuilds`/`numberTrackRebuilds`, `RasterCache.keyProbes`), pins count work. Carried:
`Frame.swift` hot sites and `RetainedSubtree` (C14b-2), layout pre-sizing, `measureNative` hashing, `ForEach` (P2), path-raster
clip key and R8 coverage (P3: pixels and shaders).
**Window chrome on SDL (`CW-`, record §112).** `.hiddenTitleBar` on SDL is a borderless window (`SDL_SetWindowBordered`, the answer read back from `SDL_WINDOW_BORDERLESS`, so an `offscreen` driver answers `false` and the window stays standard; a style asked for in fullscreen applies on the leave): `titleBarInsets` reads the 32-point band and the drawn buttons' cluster (right 138; left 70 under macOS), `Window` draws that cluster (the `$windowcontrols` named root at cursor index 3, never a `Deferred`; Close through the close veto) where `PlatformWindow.hasNativeWindowControls` is `false`, unless `drawsWindowControls = false`. **Drag and resize are hit-test regions**: `Window` publishes the unclaimed band and the `WindowDragGesture` handles minus what needs the pointer **and ranks above it** (a handle is carved only by hitboxes above its own, the band by all but a window-wide backdrop reaching below it: `CW-V`, `ChromeHitMap.carve`) through the four defaultless requirements `setWindowDragRegions(_:)`, `performWindowAction(_:)`, `hasNativeWindowControls`, `isZoomed`, on change only and held still during a press; SDL copies them into an immutable snapshot behind a per-window `SDL_Mutex` that its thread reads (`mui_chrome_hit` is the C twin of `ChromeHitSnapshot.hit(at:)`), and the platform moves the window before `Window` sees the press, so `performWindowDrag()` stays `false` and pointer events inside a region are lost (divergences 425, 426, 276). API is class M (SwiftUI has none, probe `swiftui-window-chrome.swift`): `Window.drawsWindowControls`/`minimize()`/`toggleZoom()`/`isZoomed`. A new `PlatformWindow` requirement owes the headless platform an honest answer (`Options.sdlChrome`). Pins call the callback's own body; the Linux image cannot change a border (its pins are gated). Linux double-click zoom is unmeasured (`CW-I`, check CW6); the looks, drag and edges are group `CW`. The demo is `METALUI_CHROME_DEMO=1`.

**SDL GPU for apps (`GA-`, record §114).** `MetalUISDLGPU` (`Backends/SDL`, a product behind the `SDL` trait, class `M`, no
divergence, no census row: `Backends/SDL` is outside it, `GA-L`) is a thin typed layer over SDL_GPU named after it
(`SDLGPUDevice`, buffers, transfer buffers, textures, samplers, compute and graphics pipelines, passes, `SDLGPUFence`),
every wrapper with `.raw` and `@_exported import CSDL` so one import also gives every `SDL_` call (`GA-A`, `GA-B`); a
portable cross-backend GPU API is refused. **A batch** (`device.submitBatch`) is recorded and submitted on a dedicated
worker thread and its fence awaited on a waiter thread, never the main actor; every fence is released after its signal
whether or not anyone awaits it (`GA-E`); `make` is serialized, and `SDLGPUDevice(borrowing:)` never destroys the
window's device. An atomic append is a storage-buffer counter (`GA-G`). App shaders are HLSL built by
`MetalUICompileShaders` (`BS-`, below) into checked-in `.spv/.msl/.dxil/.json` blobs with `SOURCE.sha256` and found in
`MetalUIAppShaders` beside the executable (`GA-F`, `docs/packaging.md` 4a). **`ctx.view` records into the frame's own
buffer and has no submit, cancel, wait or acquire verb** (`GA-H`); the debug guard traps a typed `waitForIdle`, `submitBatch` and
`fence.wait` in a draw and a pass left open (the async two through a `package` test hook, `GA-R`); a raw SDL call is undetected (`GA-I`). A new SDL GPU test needs
`armMainRunLoopExitCheck()` on macOS, runs the Linux image on lavapipe and takes `METALUI_REQUIRE_GPU=1` in CI.

**`@GestureState` and `phaseAnimator` (`GS-`, record §135).** `GestureState<Value>` is a `@MainActor` wrapper over a `State<Value>` plus a dirty set: a **`$state<n>` slot, no eighth
reserved name** (`BindableState`, `StateTable.write`/`peek`, so the memo, retained and prepaint logs already see its writes), get-only `wrappedValue`, itself its `projectedValue`. `updating(_:body:)` is on
the concrete gestures (a tap's compiles and never runs; none on a composition), returns the receiver's own type and runs in declaration order with `onChanged`. **The reset is one `finished` hook on the
arena leaf, queued in `fail(_:)` and in `act(_:)` before the ended callback and handed back by `cancel()`/`abandon()` (`owesFinish`)**: a new exit from an arena owes a pin that the state resets once
(`everyCancelPathResetsOnce`). Every body of one event starts from the value committed before it; two simultaneous writers resolve in declaration order (divergence 645, probe arms `G7`/`G7e` not re-taken). The
update's transaction applies only when the body set an animation, the reset's only when it animates (divergence 99's one root). `phaseAnimator`/`PhaseAnimator` are `keyframeAnimator`'s transparent scope
with a `PhaseRecord` in `AnimationStore` at **`$phase<depth>`** (never a `StateTable` slot, `keyframeDepth`'s counter shared): no trigger cycles forever, a trigger runs once through the phases back to the
first, each held for `Animation.nominalDuration`; it calls `noteActiveAnimation()`, **never `requestAnotherFrame()`**; Reduce Motion is not changed (`GS-K`, unmeasured); it is refused by the retained paths by
name while cycling. No `Retained*.swift` edit, no `Handlers` change, no seam requirement. Demos: `METALUI_CANVAS_DEMO=1` chips, `METALUI_LOOKS_DEMO=1` pulse. Pins count work and values.

**SDL GPU gaps (`GB-`, record §137).** Class `M`, `MetalUISDLGPU` only, no divergence (665-674 untouched), no root change. `SDLGPURenderPass.setViewport`/`setScissor` are
`@discardableResult -> Bool`: top-left target pixels, a non-finite value or size `<= 0` answers `false` and never traps, the scissor **clamps to the pass's target**, the viewport does not
(`GB-B`); `writesColor: false` is a zero colour write mask on the one colour target (`GB-C`); `r32Float` is a new enum case (exhaustive switches owe an arm, migration note) and
`maxAnisotropy` clamps to 1...16 (`GB-D`, `GB-E`). **Blocking the main actor is allowed outside a draw**: `SDLGPUFence.waitBlocking()` sleeps on the fence's condition the waiter thread
signals and never calls `SDL_WaitForGPUFences` or releases (the fence rule holds), `SDLGPUDevice.downloadSynchronously(_:region:)` builds on it; both trap in a draw (`GA-I`) and
`precondition` off the device's own worker threads (`GB-F`, `GB-I`, `GB-L`). `compileGraphicsPipeline`/`compileComputePipeline` throw an `SDLGPUError` naming the stage with SDL's text read on
the failing thread; the optional `make...Pipeline` verbs keep their spelling and record `lastPipelineFailure` (`GB-G`); **the stage a refusal names is the driver's** (`GB-L` 6).

**Build-time app shaders (`BS-`, record §138).** Class `M`, no divergence (675-684 untouched), nothing published (`BS-H`). `MetalUICompileShaders` (executable) and the `CompileShaders` command plugin (`swift package compile-shaders --allow-writing-to-package-directory`) over `MetalUIShaderCompile` (portable, Foundation only, `package`, **outside the `SDL` trait**) replace `compile-app-shaders.py`: one implementation, its checked-in output the byte-for-byte oracle (`BS-B`). shadercross is found by `--shadercross`, `METALUI_SHADERCROSS`, then `PATH`, its `lib` joining the loader path (`BS-C`); the pin is SDL_shadercross `1ff05bec573988a98ef9e0260b4da44f512b8367`, documented in `docs/packaging.md` 4a, built and run at the pin on macOS arm64 and Linux aarch64 with 41 files byte-identical (`BS-L`). **`SDLGPUShaderLibrary` accepts a directory with a `SOURCE.sha256` or a reflection `.json`** (a marker-free build product is trusted); `init(directory:verifyingSources:)` checks a marker only when present and then refuses a stale, missing or orphan entry by name (`BS-E`). Carried: a build-tool plugin on `swift build` (`BS-D`), a CI job building shadercross (`BS-G`), any prebuilt, release or tag (the user's decision, to be asked).

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
`allowsHitTesting` and `hidden()` gates. `CoordinateSpace.named` is built (`OV-D`, below); the image
cursor is built (`IC-`, below), and `shape(_:eoFill:size:)` is carried (`IC-G`).

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
`phaseAnimator` is built (`GS-H`). **A gradient is rasterized on the CPU through the
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
platform's *answer* (on SDL the band and the drawn buttons' cluster, `CW-D`; zero where the
platform answers `false`); an unclaimed primary press in the band drags the
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
never time). `frame(ofID:)` finds an `.id` on proposal content too: an `IdentifiedGroup` records the union of its nodes' rects in a recording frame only and is never a `scrollTo` target (`TW-A`…`TW-C`, record §108). `MetalUI` gains only `package` read-back hooks in `TestingHooks.swift` and
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

**Image decoding and orientation (`IB-`, record §113).** `DecodedImage` (MetalUI-only) is the public pixel
read: PNG/JPEG bytes through the one vendored decoder to **straight** RGBA8 or 8-bit grey (grey sources
native, otherwise stb's Rec. 601 integer luma, alpha dropped, `IB-B`), `bytesPerRow` unpadded; it is a type of its own
because `ImageTexture` stays premultiplied (`AI-E`, `IB-A`). It **reports** the EXIF orientation (JPEG `APP1`, PNG
`eXIf`, whole entries only, every read bounds-checked, damaged or absent is `.up`, never a trap) and **does not
apply it**: `applyingOrientation()` or `Image(…orientation:)` (no default, `IB-K`) does, through
`ImageBitmap.oriented(_:)`, one cached texture per orientation, `.up` the same bitmap; `ImageBitmap(data:)` keeps
the stored pixels, unlike SwiftUI's `NSImage` route (divergence 435, `IB-G`). `Image.Orientation` has SwiftUI's
raw values. No C, shader or `ImageTexture` change; a new reader of the file bytes stays Foundation-free.

**Image cursors and the headless SDL launch (`IC-`, record §116).** `PointerStyle.image(_:hotSpot:)` is SwiftUI's
spelling (class A): the cursor is the `Image`'s one bitmap at `pixels / scale` points (probe `swiftui-image-cursor.swift`;
`resizable()`/`interpolation` ignored), the hot spot a `UnitPoint` of that size from the top-left, **clamped per axis**
(divergence 465). It reaches the platform as the seam case `PlatformPointerStyle.image(PlatformCursorImage)` (`CI-AC`: an
outside exhaustive `switch` owes an arm), **compared by texture identity, never bytes**, so a bitmap rebuilt into an `Image`
every frame is one cursor and `Window` still sends on a change only (`IC-A`, `IC-F`). AppKit wraps the premultiplied pixels
as stored in an `NSCursor` (LRU 16 per window); SDL un-premultiplies through `SDLIcon.straightRGBA` (`AI-F`) into
`SDL_CreateColorCursor` (an integer scale >= 2 adds the bitmap as an alternate), through `SDLImageCursorTable` (pure,
LRU 8, **the platform's**, a shown cursor parked and destroyed at the next sweep, all destroyed on the last close; tests
read the C recorders `mui_cursor_*`, which count even a refused create). **No hand or zoom art is bundled**: the app
supplies SDL's (`IC-H`). `.shape` is not built. `SDLPlatform.Options` (`.default`, `.headless` = hidden windows + offscreen
renderers, `headlessIfRequested()` reading `METALUI_SDL_HEADLESS` exactly `"1"`, never read by `init`) with
`SDLPlatform(options:)` is the public CI smoke-test launch (`IC-J`…`IC-M`); the `@_spi(Checks)` initialiser forwards. A
`.task` can run before `platform.run()` starts, so a smoke test stops from the display-link tick (`IC-Q`); the recipe is
`docs/testing.md`, `HeadlessLaunchCheck` its compiled twin. Cursor looks and the SDL recipe are group IC.

**Clipboard beyond text (`CB-`, record §115).** `.copyable(_:)`, `.cuttable(for:action:)` and
`.pasteDestination(for:action:validator:)` are SwiftUI's signatures (probe arm S) over MetalUI's own synchronous `Transferable`
(spell `MetalUI.Transferable` beside CoreTransferable), on every `StyledElement` and once on proposal content (the
`KeyboardModifier` layer, `ClipboardAttachment` a class box in `KeyboardAttachment`'s fifth field, `Handlers` stays nineteen).
**One stage, `dispatchClipboardKey`, after `onKey` and before the context-menu key and every shortcut** (`CB-B`): exact
`EventModifiers.primary` + C/X/V for an element holding focus or an ancestor of it, innermost first; the Keymap, `onKeyPress` and a
focused text field (whose path is untouched, `CB-M`) still win; the Edit menu needs no code (AppKit's `cut:`/`copy:`/`paste:` and the
drawn bar already send these keys). A copy writes **the first item**, one representation per exported type, the text fallback being the
type's own `.utf8PlainText` entry (`CB-C`, divergence 456); a paste walks the **destination's** `importedContentTypes()` against the
platform's list and **declines** (the next stage runs) unless the action ran (`CB-P`). **Four defaultless `PlatformWindow` requirements**
(`writeClipboard(_ representations:) -> Bool`, `clipboardTypeIdentifiers()`, `readClipboard(identifier:)`, `setClipboardCommands(_:)`;
`CB-E`; every conformer, the headless platform and every fake implements them, migration note); the text-only pair stays. AppKit's
identifier is the pasteboard type; **SDL's mime is a pure table plus `application/x-` + the identifier with every byte outside
`[a-z0-9.+-]` percent-encoded** (`ClipboardMime`, `CB-D`). **SDL's data callback is pure**: one `malloc`'d box copied at copy time, a
lookup by mime, a pointer into the box, one cleanup that frees (`CB-H`, `CB-Q`) — no Swift closure, no actor hop, so any thread is safe;
zero-byte representations are dropped, an all-empty write keeps the clipboard (`CB-I`). Enablement is by presence, not the validator
(divergence 455, provisional until `CB1`). `Window.clipboard` is the MetalUI-only imperative API, no public initialiser (`CB-J`); an AppKit
test uses a private `NSPasteboard(name:)`, never `.general` (`CB-K`). Not built: `PasteButton`, `@Environment(\.clipboard)`, lazy export,
multi-item (`CB-N`). The demo is `METALUI_CLIPBOARD_DEMO=1`.
**Header-only image read and bounded decode (`IH-`, record §117).** `ImageInfo(data:)`/`(contentsOfFile:)` (MetalUI-only,
class `M`, no divergence) reads a PNG's IHDR (length 13, CRC, legal colour/depth pairs) or a JPEG's first SOF (all thirteen
dimension-bearing markers, never DHT/DAC) plus the EXIF orientation: `format`, stored size, `orientation`, `bitDepth`,
`channelCount`, `orientedSize`; PNG and JPEG only, anything else or a damaged header is `nil`, no pixel work, no stb, no limit
of its own (`IH-A`…`IH-C`). **One header walk** (`ImageHeader.swift`) serves `ImageInfo`, `DecodedImage` and `ImageEXIF`'s two
wrappers (`IH-H`); the file form seeks over the pixels through one 64 KiB window and refuses non-regular files (`IH-M`, `IH-O`).
`DecodedImage.Limits(maxInputBytes:maxSide:maxPixels:)` (all optional, inclusive) with the two `limits:` initialisers refuses
from the header **before stb allocates** (an overflowing product is a refusal, `IH-N`); **`decodeImage` refuses a stb size that
disagrees with the header** (`IH-I`), so the unlimited init is `nil` on a header it cannot read. A JPEG damaged after its first
SOF still answers `ImageInfo` (`IH-P`). Cancellation is not built (`IH-K`); `ImageBitmap` is untouched (`IH-L`). A new reader of
image bytes goes through the one walk; `HeaderSource` stays unreachable (guard G-IH1).

**Header-only format sniff (`IS-`, record §130).** `ImageFileFormat` (`png jpeg gif tiff bmp webp heif avif unknown`, a **separate enum**: `ImageInfo.Format` stays `png`/`jpeg` so no exhaustive
switch breaks and `ImageInfo.format` never holds a format no `ImageInfo` can, `IS-A`) and `ImageInfo.sniffedFormat(of:)`/`(ofFile:)` (MetalUI-only, class `M`, no divergence, no probe) are total and
`.unknown` answers every miss: one read of `min(size, 18)` bytes at offset 0 through the one header source (`IS-F`; the file form is `IH-M`'s regular-file window), never stb, never a trap. **A sniff names a
prefix, never a promise** (`IS-C`): `.png`/`.jpeg` with a `nil` `ImageInfo` is damaged, another case with `nil` is unsupported, `.unknown` is not a picture. Whole signatures only (one byte short is
`.unknown`); BMP needs a DIB size at offset 14, `ftyp` is matched on the major brand only (an `mif1` AVIF reads `.heif`), AVIF is its own case, BigTIFF and OS/2 are `.unknown` (`IS-D`, `IS-E`). A new case
owes an arm in the minimal-prefix table (`CaseIterable` pins every case). `FileHeaderSource.testingTraceForUntracedOpens` is a `--no-parallel` test seam (`IS-K`); guard `G-IS1`.

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
  consumes no `LoweredItem`. Lazy grids are built outside the kernel (`LZ-`, record §134).
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

- **Divergences**: `docs/divergences.md` (164 live, next label 206). A new
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
