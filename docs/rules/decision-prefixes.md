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
  `2026-10-04-platform-services-decisions.md`, next `SV-AQ`), `PE-` (controls in
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
  `2026-10-09-smk-gaps-decisions.md`, next `SG-N`), `TK-` (test hygiene: sheet-test skip, Linux flake, SDL launch drops:
  `2026-10-31-test-hygiene-decisions.md`, next `TK-E`), `PG-` (path operations: `trimmedPath`/`trim`, `strokedPath`, `addRelativeArc`,
  `Transform2D`, `UnevenRoundedRectangle`: `2026-10-31-path-ops-decisions.md`, next `PG-I`), `HT-` (test harness, `MetalUITesting`:
  `2026-10-09-test-harness-decisions.md`, next `HT-AA`), `OV-` (overlays and coordinates:
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
  `2026-10-14-sdl-gpu-compute-decisions.md`, next `GA-T`), `CB-` (clipboard beyond text:
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
  `2026-10-20-finer-scopes-decisions.md`, next `FS-U`), `GL-` (glyph atlas reclaim: growth in place, a rebuild between frames, the cap and the drop counter, retained keying on the atlas generation: `2026-11-01-atlas-reclaim-decisions.md`, next `GL-K`), `GE-` (gesture composition: `sequenced(before:)`, a custom `body`, composed `updating`, `DragGesture.Value` velocity:
  `2026-10-31-gesture-composition-decisions.md`, next `GE-J`), `CF-` (warm and cold frame gaps: `2026-10-20-warm-settle-decisions.md`, next `CF-L`), `RZ-` (retained zoom, fillet-drag profile, `@FocusState` memo: `2026-10-21-retained-zoom-decisions.md`, next `RZ-U`), `RG-` (retained geometry observers, placement translation, per-shelf atlas uploads: `2026-10-20-retained-geometry-decisions.md`, next `RG-Q`), `AT-` (accessibility under an effect-translated replay: `2026-10-20-ax-translated-replay-decisions.md`, next `AT-H`), `RL-` (retained lifecycle and translation carries: `2026-10-21-retained-lifecycle-decisions.md`, next `RL-R`), `AP-` (SDL application id: `2026-10-21-sdl-app-id-decisions.md`, next `AP-G`), `EX-` (the sample app: `2026-10-21-sample-app-decisions.md`, next `EX-T`), `GB-` (SDL GPU gaps: `2026-10-21-sdl-gpu-gaps-decisions.md`, next `GB-M`), `IS-` (header-only image format sniff: `2026-10-20-image-sniff-decisions.md`, next `IS-L`), `LZ-` (lazy containers: `2026-10-21-lazy-containers-decisions.md`, next `LZ-AA`), `GS-` (`@GestureState`, `phaseAnimator`: `2026-10-21-gesture-state-decisions.md`, next `GS-T`), `BS-` (build-time app shaders: `2026-10-21-build-shaders-decisions.md`, next `BS-M`), `WR-` (Windows release-build SIL crash: `2026-10-21-windows-release-crash-decisions.md`, next `WR-H`), `DT-` (`drawText` in a GPU surface: `2026-10-22-draw-text-decisions.md`, next `DT-M`), `SM-` (small items carried: `2026-10-22-small-items-decisions.md`, next `SM-F`), `AM-` (retained move miss, drag ambient miss: `2026-10-22-retained-move-miss-decisions.md`, next `AM-P`), `SY-` (synchronous render batch: `2026-10-22-sync-batch-decisions.md`, next `SY-I`), `CP-` (clipboard extras: `2026-10-22-clipboard-extras-decisions.md`, next `CP-P`), `DM-` (one miss per changed occurrence, the retained trace: `2026-10-21-retained-single-miss-decisions.md`, next `DM-P`), `BG-` (presentation extras: `2026-10-22-presentation-extras-decisions.md`, next `BG-T`), `LH-` (`List` row identity by value: `2026-10-22-list-row-identity-decisions.md`, next `LH-L`), `EO-` (retained environment override, C14-m refuted: `2026-10-22-retained-env-override-decisions.md`, next `EO-I`), `TH-` (retained theme pin, C14-n: `2026-10-22-retained-theme-pin-decisions.md`, next `TH-F`), `DL-` (SDL GPU device info and limits: `2026-10-22-sdl-gpu-device-info-decisions.md`, next `DL-O`), `RC-` (run-time HLSL compute shaders on SDL_GPU: `2026-10-22-sdl-gpu-runtime-shaders-decisions.md`, next `RC-Z`), `SX-` (shadercross lookup in `<exe>/lib`, Microsoft DXC note, XP-G27 carried: `2026-10-23-shadercross-lookup-decisions.md`, next `SX-G`), `MA-` (menu anchor under render effects: `2026-10-26-menu-anchor-decisions.md`, next `MA-I`), `LG-` (Liquid Glass, `glassEffect`: `2026-10-23-liquid-glass-decisions.md`, next `LG-W`), `TL-` (hung SDL test helpers: `2026-10-24-sdl-test-hangs-decisions.md`, next `TL-L`), `TP-` (SDL precise scroll: `2026-10-24-sdl-precise-scroll-decisions.md`, next `TP-R`), `EL-` (layout and outer effect moved together: `2026-10-26-effect-and-layout-moved-decisions.md`, next `EL-O`), `WG-` (SDL test guard on Windows, record 150's parallel hang: `2026-10-27-test-guard-windows-decisions.md`, next `WG-M`), `HX-` (run-time shader compile without the `SDL` trait: `2026-10-28-runtime-compile-no-sdl-decisions.md`, next `HX-L`), `BT-` (app shaders on `swift build`, the build-tool plugin: `2026-10-28-build-tool-shaders-decisions.md`, next `BT-Z`), `HS-` (HSplitView/VSplitView: `2026-10-30-split-view-decisions.md`, next `HS-I`), `WA-` (window activation, public `Color(hex:)`: `2026-10-30-window-activation-decisions.md`, next `WA-D`), `BU-` (`metalui bundle`: `2026-10-30-bundle-command-decisions.md`, next `BU-F`), `SE-` (per-segment Picker identifiers: `2026-10-30-segment-accessibility-decisions.md`, next `SE-C`), `VD-` (SDL desktop video and dialog filter names: `2026-10-30-sdl-desktop-video-decisions.md`, next `VD-H`), `DA-` (identified text fields keep role and text, `.contain` for container identifiers: `2026-10-30-dashboard-ax-decisions.md`, next `DA-D`), `DX-` (harness timeline clock, SwiftUI padding spellings: `2026-10-30-dashboard-text-timeline-decisions.md`, next `DX-D`), `ES-` (decorations after transparent scopes: `2026-10-31-scope-decorations-decisions.md`, next `ES-L`), `SP-` (scroll extras: pinned section views, `scrollPosition(id:)`, animated `scrollTo`, `@Bindable`: `2026-10-31-scroll-position-decisions.md`, next `SP-M`), `BY-` (open `ButtonStyle`/`PrimitiveButtonStyle`/`ToggleStyle`, `.borderedProminent`, `.link`, `.pickerStyle(.inline)`: `2026-10-31-styles-decisions.md`, next `BY-L`), `MG-` (matched geometry, the `Transition` protocol: `2026-10-31-matched-geometry-decisions.md`, next `MG-I`), `UB-` (dropped shader register slots, XP-G36: `2026-11-01-uniform-slots-decisions.md`, next `UB-I`), `SS-` (`ShapeStyle`, `AnyShapeStyle`, `.tint(_:)`: `2026-11-01-shape-styles-decisions.md`, next `SS-H`), `PH-` (pointer extras: one-way `columnResize`/`rowResize`, `pointerVisibility`: `2026-11-01-pointer-extras-decisions.md`, next `PH-K`), `SD-` (segmented picker selected fill in dark: `2026-11-01-segmented-dark-decisions.md`, next `SD-C`), `TM-` (`Text.LineStyle` dash patterns, view-level text modifiers: `2026-11-01-text-view-modifiers-decisions.md`, next `TM-I`), `AE-` (app-shell extras: `navigationTitle(Text/LocalizedStringKey)`, `navigationSubtitle`, `windowDismissBehavior`: `2026-11-01-app-shell-extras-decisions.md`, next `AE-G`), …; the full
  prefix → document → record table is in record §69 "Where things are").
  **To find the next unused id, read the file's last `## <PREFIX>-` heading,
  not its header** — headers have lagged. A decisions doc's "next unused" line
  moves in the commit that appends the ruling. A numbered citation of a
  lettered prefix (`LR-3`, `DN-3`, `AI-3`) is a typo.

**X11 window icon (`WI-`, record §183).** Class `M`, no divergence (975-984 untouched), nothing published; decisions `2026-11-01-x11-window-icon-decisions.md`, next `WI-F`. SDL writes `_NET_WM_ICON` from the primary surface alone, so `mui_window_set_icon` writes every size itself under the x11 driver (`WI-B`, `WI-C`); an empty xprop for an icon over about 250 px is xprop's printer, read raw (`WI-A`).

**`labelsHidden()` (`LB-`, record §189).** Class `A`, divergences 1025-1026 (reserved 1025-1034); decisions `2026-11-01-labels-hidden-decisions.md`, next `LB-D`. A hidden label is removed from layout (its `OptionalGroup` slot stays reserved) and an empty title keeps the gap (`LB-A`, probe `swiftui-labels-hidden.swift`).

**Right-to-left layout direction (`LD-`, record §191).** Class `A`, retires divergence 25 and adds 1045 (reserved 1045-1054, 1046-1054 unused); decisions `2026-11-01-layout-direction-decisions.md`, next `LD-I`. A node registered under a right-to-left environment reflects each child's rect about its own bounds at placement (`LD-A`, `LD-B`; probe `swiftui-layout-direction.swift`); effects, text alignment and a horizontal scroller's logical offset follow (`LD-C`..`LD-E`).

**`DropDelegate` (`DE-`, record §192).** Class `A` (`DropDelegate`, `DropProposal`, `DropOperation`) and `D` (`DropInfo`, `onDrop(of:delegate:)`), divergences 1055-1056 (reserved 1055-1064; 1057 fixed, not recorded); decisions `2026-11-01-drop-delegate-decisions.md`, next `DE-K`. It reverses `DN-A` item 2 for the delegate (`DropItem` stands in for `NSItemProvider`, `DE-A`); a defaultless `PlatformWindow.setDropOperation(_:)` carries the proposal to the platform (`DE-H`).

**3D render effects (`PJ-`, record §193).** Class `A` (`rotation3DEffect`, `projectionEffect`, `transformEffect`, `ProjectionTransform`) and `D` (divergences 1065-1069, reserved 1065-1074, 1070-1074 unused); decisions `2026-11-02-projection-effects-decisions.md`, next `PJ-N`.

**Accessibility display settings (`AD-`, record §194).** Class `A` (`colorSchemeContrast`, `accessibilityDifferentiateWithoutColor`, `accessibilityInvertColors`, `accessibilityShowBorders`, `accessibilityDimFlashingLights`, `accessibilityPlayAnimatedImages`, `legibilityWeight`) and `D` (divergences 1075, 1076, 1078, 1079, reserved 1075-1084, 1077 and 1080-1084 unused); decisions `2026-11-02-accessibility-display-decisions.md`, next `AD-M`. The seam is one defaultless pair on `PlatformWindow` (`AD-C`).

**Record §05 re-derived (`RD-`, record §196).** No class and no divergence; nothing public. Rulings `RD-A`..`RD-F` (what a row is, the boundary with `docs/divergences.md`, census keys, history, the check, carried findings); decisions `2026-11-02-record-05-rederive-decisions.md`, next `RD-G`. The check is `zsh docs/probes/record-05-check.sh`.

**Silent results (`SR-`, record §198).** Class `A`; retires divergences 81 and 885, adds 886 (BY's reserved 885-894), narrows 154, rewords 295 and 208; decisions `2026-11-03-silent-results-decisions.md`, next `SR-G`. The automatic `Picker` is the pop-up (`SR-B`); a control's string literal title parses and a `String` value is verbatim (`SR-C`); the switch knob slides on a fixed spring the transaction does not drive, mirrored under right-to-left (`SR-D`); an empty `Text` is a constant 14 tall in SwiftUI, not 0 by 0 (`SR-A`).

**State first value (`FV-`, record §199).** Class `A`; retires divergence 125, adds 210 (`AnyElement` type swap); decisions `2026-11-03-state-first-value-decisions.md`, next `FV-E`. A `@State` keeps its default's first evaluation: `State.bind` seeds a slot with no entry through `StateTable.mark(_:seeding:)` (`FV-A`, overturns `LC-S` item 1), a seed is not a write and journals as a plain `.mark` (`FV-B`, amends `RW-F`), and an erased type swap shares the old slot (`FV-C`, divergence 210).

**Layer colour space (`LS-`, record §200).** Class `A`; narrows divergence 1, no label added or retired; decisions `2026-11-03-layer-colour-space-decisions.md`, next `LS-D`. The AppKit presentation layer is tagged sRGB (`LS-A`, amends spec §7.8, `CR-I`, `CR-C` item 6); wide gamut stays unoffered (`LS-B`); the window gate and group LS are owed to a person (`LS-C`).