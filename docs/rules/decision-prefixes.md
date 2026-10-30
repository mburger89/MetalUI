# Decisions docs and ruling prefixes

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

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
  `2026-10-10-input-followups-decisions.md`, next `IF-P`), `FI-` (`ForEach` identity:
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
  `2026-10-20-finer-scopes-decisions.md`, next `FS-U`), `CF-` (warm and cold frame gaps: `2026-10-20-warm-settle-decisions.md`, next `CF-L`), `RZ-` (retained zoom, fillet-drag profile, `@FocusState` memo: `2026-10-21-retained-zoom-decisions.md`, next `RZ-U`), `RG-` (retained geometry observers, placement translation, per-shelf atlas uploads: `2026-10-20-retained-geometry-decisions.md`, next `RG-Q`), `AT-` (accessibility under an effect-translated replay: `2026-10-20-ax-translated-replay-decisions.md`, next `AT-H`), `RL-` (retained lifecycle and translation carries: `2026-10-21-retained-lifecycle-decisions.md`, next `RL-R`), `AP-` (SDL application id: `2026-10-21-sdl-app-id-decisions.md`, next `AP-G`), `EX-` (the sample app: `2026-10-21-sample-app-decisions.md`, next `EX-T`), `GB-` (SDL GPU gaps: `2026-10-21-sdl-gpu-gaps-decisions.md`, next `GB-M`), `IS-` (header-only image format sniff: `2026-10-20-image-sniff-decisions.md`, next `IS-L`), `LZ-` (lazy containers: `2026-10-21-lazy-containers-decisions.md`, next `LZ-AA`), `GS-` (`@GestureState`, `phaseAnimator`: `2026-10-21-gesture-state-decisions.md`, next `GS-T`), `BS-` (build-time app shaders: `2026-10-21-build-shaders-decisions.md`, next `BS-M`), `WR-` (Windows release-build SIL crash: `2026-10-21-windows-release-crash-decisions.md`, next `WR-H`), `DT-` (`drawText` in a GPU surface: `2026-10-22-draw-text-decisions.md`, next `DT-M`), `SM-` (small items carried: `2026-10-22-small-items-decisions.md`, next `SM-F`), `AM-` (retained move miss, drag ambient miss: `2026-10-22-retained-move-miss-decisions.md`, next `AM-P`), `SY-` (synchronous render batch: `2026-10-22-sync-batch-decisions.md`, next `SY-I`), `CP-` (clipboard extras: `2026-10-22-clipboard-extras-decisions.md`, next `CP-P`), `DM-` (one miss per changed occurrence, the retained trace: `2026-10-21-retained-single-miss-decisions.md`, next `DM-P`), `BG-` (presentation extras: `2026-10-22-presentation-extras-decisions.md`, next `BG-T`), `LH-` (`List` row identity by value: `2026-10-22-list-row-identity-decisions.md`, next `LH-L`), `EO-` (retained environment override, C14-m refuted: `2026-10-22-retained-env-override-decisions.md`, next `EO-I`), `TH-` (retained theme pin, C14-n: `2026-10-22-retained-theme-pin-decisions.md`, next `TH-F`), `DL-` (SDL GPU device info and limits: `2026-10-22-sdl-gpu-device-info-decisions.md`, next `DL-O`), `RC-` (run-time HLSL compute shaders on SDL_GPU: `2026-10-22-sdl-gpu-runtime-shaders-decisions.md`, next `RC-Z`), `SX-` (shadercross lookup in `<exe>/lib`, Microsoft DXC note, XP-G27 carried: `2026-10-23-shadercross-lookup-decisions.md`, next `SX-G`), `MA-` (menu anchor under render effects: `2026-10-26-menu-anchor-decisions.md`, next `MA-I`), `LG-` (Liquid Glass, `glassEffect`: `2026-10-23-liquid-glass-decisions.md`, next `LG-W`), `TL-` (hung SDL test helpers: `2026-10-24-sdl-test-hangs-decisions.md`, next `TL-L`), `TP-` (SDL precise scroll: `2026-10-24-sdl-precise-scroll-decisions.md`, next `TP-R`), `EL-` (layout and outer effect moved together: `2026-10-26-effect-and-layout-moved-decisions.md`, next `EL-O`), `WG-` (SDL test guard on Windows, record 150's parallel hang: `2026-10-27-test-guard-windows-decisions.md`, next `WG-M`), `HX-` (run-time shader compile without the `SDL` trait: `2026-10-28-runtime-compile-no-sdl-decisions.md`, next `HX-L`), `BT-` (app shaders on `swift build`, the build-tool plugin: `2026-10-28-build-tool-shaders-decisions.md`, next `BT-U`), …; the full
  prefix → document → record table is in record §69 "Where things are").
  **To find the next unused id, read the file's last `## <PREFIX>-` heading,
  not its header** — headers have lagged. A decisions doc's "next unused" line
  moves in the commit that appends the ruling. A numbered citation of a
  lettered prefix (`LR-3`, `DN-3`, `AI-3`) is a typo.
