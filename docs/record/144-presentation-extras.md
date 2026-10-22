# 144 — Presentation extras: `presentationBackground`, `windowBackgroundDragBehavior`, `PointerStyle.shape`

Branch `feat/presentation-extras` from `dd9a072f`, merged with master `4d166812` (records 140–143 and 147; **144 was free on master, no renumbering**). **Not a plan task**: round 2 item 7 (user
request 2026-10-21; carried gaps `OV-C` record §92, `WD-` record §97 "Not built", `IC-G` record §116). Spec
`docs/superpowers/specs/2026-10-22-presentation-extras-design.md` (Status: BUILT); rulings `BG-A`…`BG-S` in `docs/superpowers/2026-10-22-presentation-extras-decisions.md` (next unused `BG-T`);
probes `docs/probes/swiftui-presentation-extras.swift` and `swiftui-presentation-extras-typecheck.sh`. Divergences 735–737 (738–744 unused). Human checks group `BG`.

## §1 What landed

All three carried gaps are **built**; what the probes decided shaped each.
- **`presentationBackground`** (`PresentationBackground.swift`, lane 1): `ElementGroup` spellings for `Color`, `ColorToken` (the `CR-D` twin), `Material`, `LinearGradient`, `RadialGradient` and
  `presentationBackground(alignment:content:)`, one new `EnvironmentWrite` case reporting after its content builds into a slot opened by the existing `beginPresentationPreferences` bracket
  (`Frame.presentationBackgroundSlot`; innermost wins, a report outside a presentation is nothing: probe `B4`, `B7`). Only `.popover` reads it (`BG-A`); `AnchoredPresentation.paintPanel` fills
  the panel with the spec, keeps the 1-pt border and radius; a `Material` goes through `Frame.fillMaterial` and has **no drop shadow** (`BG-P`); the content spelling is an overlay attachment under
  `$presentationbackground` at `child(of: id, at: 0)`. Nothing in `Retained*.swift`, no `Handlers` member, no state slot.
- **`windowBackgroundDragBehavior`** (`WindowInteractionBehavior.swift`, lane 2): `WindowInteractionBehavior` (`automatic`/`enabled`/`disabled`, class A) and `Window.backgroundDragBehavior` (class M, divergence 736).
  `.enabled` makes a primary press no stage claimed drag the window: AppKit through `performTitleBarPress(clickCount: 1)` (`BG-H`: never `isMovableByWindowBackground`, which SwiftUI does not use), SDL through
  one more `ChromeRegions` candidate, the content rect carved by every blocker without the band's backdrop exemption and dropped whole when it cannot fit the 64-rect cap (`BG-I`). The band is untouched (`BG-J`).
- **`PointerStyle.shape(_:eoFill:size:hotSpot:fill:outline:)`** (`ShapeCursor.swift`, lane 2): SwiftUI has it on **visionOS only** (probe `T1`), so it is MetalUI's own spelling (class M, divergence 735): CPU raster
  through `MetalUIPath` at the display scale rounded up, black fill with a 1-pt white outline, hot spot centre, resolved at send time into the existing `PlatformPointerStyle.image` through a window `ShapeCursorCache`
  (LRU 8). **No new `PlatformWindow`/`Platform`/`WindowRenderer` requirement, no migration note, no shader.**

## §2 Tests and guards

| File | Count | What it pins |
|---|---|---|
| `Tests/MetalUITests/PresentationBackgroundTests.swift` | 13 | panel fill by colour, material, gradient, token (both scheme arms and the explicit token twin); innermost wins; a declarer-level report does nothing; border kept; alignment of the content spelling; an overlay or stray scope paints nothing; retained occurrence unchanged; no hitbox; no scheme preference leak |
| `Tests/MetalUITests/PresentationBackgroundCompileGuards.swift` | 2 guards (`BG1.1` twin ambiguity, `BG1.2` radial overload) | each mutated red once |
| `Tests/MetalUITestingTests/WindowBackgroundDragTests.swift` | 10 | `.automatic`/`.disabled` never drag; opaque target, nested gesture, draggable and handle never drag; secondary press and double click do not; band keeps its drag; regions carved by every blocker, empty while a popover/alert/menu is up or zoomed, republished once on a change |
| `Tests/MetalUITestingTests/ShapeCursorTests.swift` | 9 | image cursor at the display scale; `eoFill` hole; value identity of a rebuilt shape; cache LRU of 8; hot spot and clamp; 128 clamp and arrow fallback; no frame raster work (`keyProbes`); one re-send on a scale change |
| `Tests/MetalUITests/AppKitWindowDragTests.swift` | 1 | AppKit drags only during a mouse-down |
| `Tests/MetalUITests/BackgroundDragCompileGuards.swift` | 3 guards (`G1`–`G3`) | three values; setter public; the visionOS-shaped `shape` call compiles |
| `Backends/SDL/Tests/MetalUISDLTests/SDLChromeTests.swift` | 1 | the region reaches the SDL hit-test snapshot (a characterization; gated on a window-manager driver) |

Root: 13 + 9 + 10 + 1 = 33 tests and 5 guards over `dd9a072f` (lane readings 4279 and 4302 each over 4264; on the merged tree master's 4307 + 33 tests + 5 guards = **4345 tests in 7 suites**, 271 typecheck guards). `Backends/SDL` 30 + 257 on macOS and 30 + 254 in the Linux image at lane 2's head.
`everyProductionTreeBuildsOnAOneMegabyteThread` gained the chrome demo's new section; `RetainedSubtreeInternalTests` gained two `buildOnly` rows (`presentationBackgroundSlot`, `presentationBracketDepth`).

## §3 Probes

`swiftui-presentation-extras.swift` (compiled, screen **locked**, 65 lines byte-identical over two runs): B arms on a macOS popover (`B2` a uniform fill including the ring, `B4` the declarer separating arm equals the
control, `B7` innermost wins, `B8` the content is placed by alignment, not stretched) and D arms on a real `App` (only `.enabled` logs "Window move completed without beginning"; `isMovableByWindowBackground` is
`false` in every arm). `swiftui-presentation-extras-typecheck.sh`: `T0` `.image` compiles, `T1` `shape` unavailable on macOS, `T2` the modifier refused on a View, `T3` accepted on a scene. Re-taken at the critic pass
(`BG-O`); the D arms need an unlocked screen and are not re-taken.

## §4 Red runs and mutations

Every test red first (lane 1 test files red against an absent API; lane 2 `bfaa0842`). Mutations ran commit-first, restore, `git status --short` empty after each (full tables `BG-Q`, `BG-S`).
- **Lane 1:** `M1` paint ignores the slot -> tests 1, 2, 5, 6, 7; `M2` overwrite not keep-first -> 2; `M3` report before the body -> 2, 3; `M4` border width 0 -> 4; `M5` `fillBackdrop` called directly -> the `MT-` scan
  guard `noMaterialSiteBypassesFillMaterial` (the lane test stays green: byte-equal output); `M6` token twin against `Theme.light` -> 7; `M7`, `M7b` alignment ignored / a ZStack -> 8; `M9` the report taints the graft journal
  -> 11; `M10` an opaque hitbox -> 12; `M11` an overlay paints a panel -> 10; `M12` a scheme-preference leak -> 13. **`M8` (the `noteNamed` call) reddens nothing** (a constant name at its position): kept for `ID-R`, unpinned, named.
  Guards `BG1.1`, `BG1.2` red once each.
- **Lane 2:** `M1`…`M9`, `S1`…`S9`, `G1`…`G3` (all named in `BG-S`). **`M2b` and `S8` reddened nothing at first** (a draggable is the only case the arena check alone catches; the frame zeroes its raster counter so `S8` hid): both pins strengthened and re-run red.
- **Verifier re-runs (full unfiltered suites):** lane 1 `M5` -> `noMaterialSiteBypassesFillMaterial`; `M8` -> only an unrelated load flake (`aTaskCompletesUnderRunUntilIdle`, load average ~74); lane 2 `M2b` ->
  `aPressOnAnOpaqueTargetANestedGestureOrAHandleNeverDragsFromTheBackground` and `anUnclaimedPressInTheHiddenBandAsksThePlatformToDrag`; `M3b` -> `aChangeOfBehaviorRepublishesTheRegionsOnceAndNeverOnAnEqualFrame`.

## §5 Demo comparison

The fourteen offscreen images are **0 px and scene-identical against `dd9a072f`** at both lanes: a popover is closed, the behavior `.automatic` and no shape cursor is sent in the default frame. The menus demo's popover gains a gradient
fill (`menusPopoverBackground()`) and the chrome demo a `Background drag` switch and a star pointer region (`ChromeDemoModel.backgroundDrag`, class M); neither shows in the default images.

## §6 Hazards found

1. **A material panel cannot carry a drop shadow:** a backdrop record inside a shadow scope degrades to a flat tint (`BB-H`, divergence 248), so `BG-P` draws it outside the scope; a shadow-only primitive is a renderer change (`TE-AD`), carried.
2. **On SDL the platform moves the window before `Window` sees the press** (`CW-E`): the `.enabled` press must not also call `performTitleBarPress` there (`BG-O`).
3. **A main-actor closure in a demo section trapped the 1 MB harness** (`HP-C`): `chromeDemoStar()` took `.map { }`; plain calls fixed it (`BG-S`).
4. **A frame zeroes its work counters**, so work done at send time outside a frame is invisible to `lastRasterizedPixels`: a pin reads `RasterCache.keyProbes` (never reset) too.
5. A `Color` fill of a shape cursor resolves in the **light** theme and scheme (a cursor is outside every scheme-scoped tree), documented on `shape`.

## §7 Deferrals, with owners

`presentationBackground` on `anchoredOverlay`, alerts and menus (none, `BG-A`: no panel or not views); a material panel's shadow (renderer, none); a `.sheet` (none exists); a drag from a control under `.enabled` and
`.disabled` against the band (check `BG4`); background drag while zoomed on SDL and in fullscreen (`BG-I`); `isMovableByWindowBackground` (`BG-H`); animated or stroked shape cursors (none); the SwiftUI D arms re-take on an unlocked
screen (`BG4`); looks (group `BG`, record §03). Nothing carried has an owner outside this list.

## §8 Verification

Record phase, merged tree: `swift package clean`, native build 0 `error:` (only SwiftPM's deprecation `warning:`), native unfiltered run **4345 tests in 7 suites passed**, `FR-J no-argument frame: succeeded=true`; inventory and undocumented scripts print nothing;
census re-recorded after the merge (`closeout-public-api.tsv`, 3798 lines). The fourteen images, `Backends/SDL` and the Linux image were taken at the lanes, not re-taken after the merge (master's changes there are the clipboard and GPU sync batch, disjoint).
