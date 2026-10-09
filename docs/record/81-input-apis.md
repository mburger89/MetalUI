# 81 — Input APIs for viewports and canvases: scroll wheel, magnify/rotate, other buttons, tap location, pointer style (complete)

Branch `feat/input-apis` from `70ed000` (master: portable app merged, PR #51).
**Not a plan task**: user request 2026-10-02, an item of the gpui-gap
priority list. MetalCreator motivated it: a node-based CAD app on MetalUI
with a 3D viewport inside `GPUSurface`/`MetalView` and a pannable, zoomable
node-graph canvas. Its `docs/metalui-gaps.md` sections "Reported 2026-10-07
(C7)" and "C7 status and provisional API names" list the gaps; that file was
never edited from here. Spec
`docs/superpowers/specs/2026-10-08-input-apis-design.md`; rulings `CI-A`…`CI-AL`
in `docs/superpowers/2026-10-08-input-apis-decisions.md` (next unused
`CI-AM`); probe `docs/probes/swiftui-input-apis.swift`.

**Status: complete (2026-10-08).** Three lanes: lane 1 (seam and platforms),
lane 2 (gestures end to end), and lane 3. The second critic re-cut lane 3 into
lanes A (lane 2's verification and `CI-AB`), B (the wheel and the pointer
style) and C (the demo, the registries, this Record phase) (`CI-AE`). One
agent at a time, in one worktree. **Numbering**: this branch took 81 at its
design, while `70ed000`'s record ended at 80. Records 82–86 landed on master
from other lines meanwhile, so 81 is free. A later merge renumbers only if
another 81 appears.

> **For MetalCreator.** Every provisional name in its C7 list is kept
> (`SpatialTapGesture` `.location`, `.onTapGesture(count:coordinateSpace:perform:)`,
> `MagnifyGesture` `.magnification`/`.startLocation`/`.startAnchor`,
> `RotateGesture` `.rotation`/`.startAnchor`, `.pointerStyle(_:)` with
> `.grabIdle`/`.grabActive`/`.rectSelection`, `.onScrollWheel` handing a
> `ScrollEvent`, `DragGesture(…, button:)`, `DragGesture.Value.modifiers`).
> There are three refinements. `.onScrollWheel`'s closure returns `Bool`
> (`true` claims). The local pointer is `ScrollEvent.location`.
> `RotateGesture.Value.rotation` is clockwise-positive. One addition is the
> located context menu, `.contextMenu { (location: Point<Pixels>?) in … }`
> (`CI-R`). **The crosshair is `.rectSelection`**: SwiftUI has no
> `.crosshair` (probe `P2`).

## 0. Design

### 0.1 Baseline

`70ed000`, native build, unfiltered `--no-parallel`: **2672 tests in 3
suites** passed, the `FR-J` line present, the only `warning:` SwiftPM's
deprecation notice. Guards 175, census 2536 in 138 families, divergences 105
live / next label 139, human checks A–X.

### 0.2 What was measured, and what it decided

`swiftui-input-apis.swift` has positive controls and separating arms
(`T0`…`T4`, `R0`…`R4`, `M0`…`M3`, `Q0`/`Q1`, `P00`…`P14`, `C0`…`C2`) and an
interface census of SwiftUI's `.swiftinterface`. It ran twice at design and
twice more at `CI-AE`, byte-identical each time (61 lines).

- **Tap location**: local by default. `.global` in a titled window reads 32
  points lower than the content point (`T2`), so MetalUI's `.global` is the
  content space (divergence 139, `CI-B`).
- **Magnify**: cumulative and additive from 1 (AppKit +0.1, +0.1 → 1.1, 1.2).
  **Rotate**: cumulative, clockwise-positive, the negative of
  `NSEvent.rotation` (`M1`, `M2`, `Q1`, `CI-C`). **No pinch from
  control+scroll** (`M3`).
- **Other buttons**: SwiftUI's `DragGesture` follows the primary button only
  (`R2`, `R4`; `R1` was an instrument artefact). No SwiftUI gesture has a
  button parameter, so `DragGesture(…, button:)` is MetalUI-only (`CI-F`).
  AppKit opens a context menu on the press (`C0`, `C2`). MetalUI defers the
  menu to the release only when a secondary drag is declared on the press's
  chain, and the threshold is the drag's own `minimumDistance` (`CI-F` item 4).
- **Pointer style**: AppKit's mapping was measured style by style (`P1`…`P10`).
  The innermost style wins (`P11`). `nil` defers (`P12`). An opaque view
  above covers the style (`P13`). A paint-only view covers it too in SwiftUI
  (`P14`, divergence 141, `CI-H`).
- **Scroll wheel**: SwiftUI has no per-view wheel hook on macOS (census:
  `onScrollWheel` 0), so `.onScrollWheel` is MetalUI-only by ruling (`CI-I`).
- **Modifiers during a drag**: SwiftUI's `DragGesture.Value` has none
  (census, divergence 140, `CI-G`).
- **SDL** (3.4.16 source, read): pinch exists on cocoa (a per-event ratio)
  and on x11/wayland (cumulative). There is no pinch on Windows and no rotate
  anywhere. `SDL_MouseWheelEvent` has no phase, momentum or precision. There
  is no hand or zoom system cursor (`CI-K`, `CI-H` item 8).

## 1. Lane 1 — the seam and both platforms (`CI-X`, `CI-Y`, `CI-Z`)

Commits `77a7b90` (red), `04e6be1`, then the review's `7157e67`.

- `InputEvent` gained `.rightMouseDragged`, `.otherMouseDown/Dragged/Up`,
  `.magnify(MagnifyEvent)` and `.rotate(RotateEvent)`. `MouseEvent` gained
  `buttonNumber`. `ScrollEvent` gained `phase`, `momentumPhase`, `isPrecise`
  and `location` (`isMomentum` became computed, with a setter, `CI-V`). New
  types: `InputPhase`, `PlatformPointerStyle`, `PlatformResizeEdge`.
- **`PlatformWindow.setPointerStyle(_:)`**, defaultless (`CI-J`). It is
  implemented on `AppKitWindow` (an `NSCursor` per style, set at once while
  the pointer is inside, kept by `cursorUpdate(with:)` through the tracking
  area; macOS 14 fallbacks in `CI-X` item 2), on `SDLWindow` (cached system
  cursors in the bridge, every request recorded), and on every fake.
- AppKit: `otherMouse*`, `rightMouseDragged`, `magnify(with:)` and
  `rotate(with:)` are overridden. A control-drag is now `.rightMouseDragged`
  (migration, `CI-T`).
- SDL: middle, X1 and X2 map to buttons 2, 3 and 4. Motion maps by the
  held-button mask. `SDL_EVENT_PINCH_*` becomes `.magnify` through the pure
  `SDLPinch` (ratio vs cumulative by driver). A window-0 pinch goes to the
  window with mouse focus. Bridge kinds and fields were appended only.
- The review (`CI-Z`) found that SDL's right-drag change broke the drawn
  menu's press-drag-release and the tooltip's return. Both were fixed, red
  first, along with five seam pins. R1 (the AppKit immediate cursor set) is
  unpinnable and is human check **Y12**.

## 2. Lane 2 — gestures end to end (`CI-AA`)

Commits `179c65a` (red) and `164d241`.

- `SpatialTapGesture`, `MagnifyGesture`, `RotateGesture`, `MouseButton`,
  `CoordinateSpace` (`.local`, `.global`), `DragGesture(minimumDistance:coordinateSpace:button:)`,
  `DragGesture.Value.modifiers`, `.onTapGesture(count:coordinateSpace:perform:)`
  and the located `.contextMenu` on both vocabularies. Overloads resolve by
  closure arity, pinned by guards 2.1 and 2.2.
- The arena gained modes. A **press** arena fails pinch leaves at formation.
  A **pinch** arena is formed from the one ranking at a `.magnify`/`.rotate`
  event; only pinch leaves are live, and its order is per kind. A **button**
  arena is formed by a secondary or other press, with only `DragGesture`
  leaves of that button live. A press arena with no live gesture leaf is no
  arena. The context menu waits for the release when a secondary drag is
  declared, and a drag that activates cancels it.
- **`CI-AB`** (the second critic, lane A): a stale button or pinch arena (its
  end event lost) is replaced by the next press of its own button or the next
  `.began` of an active kind (pins 2.26, 2.27). Its other halves are pinned
  by 2.28 and 2.29 (`CI-AG`).
- Lane A verified every lane-2 mutation, with each named test reddened
  (`CI-AF`). **The five `AppKitPresentationTests` sheet issues seen in
  locked-screen runs are environmental**: they depend on the number of AppKit
  windows opened before them and appear only under a locked screen. Unlocked,
  the suite read 2725 tests with 0 issues (`CI-AF` item 1, `CI-AG` item 3).

## 3. Lane B — the wheel and the pointer style (`CI-AH`)

Commits `401882f` (red) and `e93ddbe`, with the verification in `c101fe6`.

- **`.onScrollWheel { (event: ScrollEvent) -> Bool }`** on both vocabularies.
  It is dispatched innermost first along the cover's chain from the one
  ranking. At each id the wheel handler runs before that id's scroll region,
  then the multi-line editor at the cover. An inner claim stops an outer
  `ScrollView`. `DD-Y` is preserved. **A handler on or around a scroller sees
  nothing over it; a handler on its content runs first and can veto**
  (`CI-AH` item 1; the built-in scrollers — a custom conformer sharing its
  scroller's id is narrowed out by `CI-AL` item 3). A declining handler falls
  through to its own element's opaque hitbox and `TI-H` scroll (`CI-AL`
  item 1). `location` is local through the region's inverse
  transform. Deltas are not transformed.
- **`.pointerStyle(_:)`**: a non-opaque style region inside the disabled,
  `allowsHitTesting` and `hidden()` gates. It is resolved with hover through
  `topmostHitbox` ("opaque, hover, or style" eligibility), and the innermost
  wins. During a press the pressed target's chain holds the style. It is
  recomputed where hover is, sent only on a change, `.default` under an
  in-window menu or drawn alert, and forgotten on exit (`CI-S`). On one
  legacy element the first `.pointerStyle` written wins (`CI-AH` item 2).
- **`Handlers` gained an eighteenth member**: one `PointerAttachment` box
  holding the wheel closure and the style (`CI-Q`). `MemoryLayout<Handlers>`
  went from 472 to 480 bytes. `HandlerShape` and `HandlerFingerprint` each
  gained the field.
- Every mutation (3.2–3.25, 3.37, 3.5b/3.5c, 3.16b) reddened its named test.
  The spec's 3.6 spelling is green, and that is the measurement of `CI-AH`
  item 1.

## 4. Lane C — the demo, the registries, the close (`CI-AI`)

Commits `ef139f4` (red: three `cannot find … in scope` lines), `28c266a`,
`6678e60`, and this phase's verification and docs commits.

- **The canvas demo** (`METALUI_CANVAS_DEMO=1`, both demo mains):
  middle-drag, right-drag or top-strip pan, two-finger scroll pan, ⌘/⌃-scroll
  and pinch zoom about the pointer, tap pick, a located node menu on release,
  a crosshair and link cursor, a rotate-able node, a style strip and a status
  line (`CI-AI` items 1 and 2). Pinned headlessly by 3.35.
- **3.36's arm** builds the canvas tree in its own frame. In the composer's
  frame it overflowed the 1 MB thread in `swift:6.4-noble` but passed on
  macOS (`CI-AI` item 3).
- The registries: divergences 139–141, six Not-offered rows, three class-D
  families (`input-apis-global-space`, `input-apis-drag-modifiers`,
  `input-apis-pointer-style-modifier`), `CI-AC`'s sentences in the doc
  comments, the census re-recorded, `docs/api-overview.md`, and human checks
  group Y.

### 4.1 Suite, guards, census

Tree: `6678e60` plus this phase's docs (no source change). `swift package
clean`, `swift build --build-system native --build-tests` (0 `error:`, the
only `warning:` SwiftPM's `--build-system native` deprecation notice), `swift
test --build-system native --no-parallel`, unfiltered, screen unlocked:
**`Test run with 2752 tests in 3 suites passed`** (169.2 s; 2672 + 80), with
the `FR-J no-argument frame: succeeded=true` line present and **0 issues**.
The five locked-screen `AppKitPresentationTests` sheet issues do not appear
unlocked (`CI-AF`).

| Count | At `70ed000` | Now | By |
|---|---|---|---|
| Tests | 2672 | **2752** | lane 1 +11 (2683) and its review +4 (2687); lane 2 +36 (2723); lane A +2 (2725) and +2 (2727, `CI-AG`); lane B +24 (2751); lane C +1 (2752, 3.35; 3.36 is an arm) |
| Typecheck guards | 175 | **180** | +5 `canTypecheck`-gated declarations (`git grep "enabled(if: canTypecheck"`, 174 → 179): 1.1, 1.2 (lane 1), 2.1, 2.2, 2.25 (lane 2), each mutated red once (`CI-Y`, `CI-AF`) |
| Goldens | 0 | 0 | `find Tests/MetalUILayoutTests -name "*.json"` reads 0 |
| Public census | 2536 | **2657** (+121) | `closeout-public-api.sh` (lane C's 2639 at `28c266a` missed `CanvasDemo.swift`'s 18 `MetalUIDemoContent` declarations; re-recorded at the close, `CI-AI` item 4); 146 inventory families (+8 `input-apis-*`: seam, wheel and gestures-metalui M; gestures and pointer-style A; global-space, drag-modifiers and pointer-style-modifier D) |
| Live divergences | 105 | **108** | 139–141; next label **142** |
| `Backends/SDL` | 24 + 83 (macOS), 24 + 80 (Linux image) | **24 + 93**, **24 + 90** | lane 1 +8, its review +2; three lifecycle tests skipped in the image (`windowsPresentFrames`) |
| Linux container, root | 6 + 35 + 18 + 199 + 49 + 22 | 6 + 35 + 18 + 199 + 49 + 22 | unchanged: the new tests are macOS-only (`MetalUITests`), and 3.36 is an arm (`swift:6.4-noble`, `git archive` of `6678e60`, 0 warnings) |

`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
`swift build --build-tests` (default build system), after the clean: **0 warnings** (1101 steps, a full rebuild).

**After the merge with master** (`dc6528c`, section 4.5): `swift package clean`,
native build 0 `error:`, unfiltered native suite **`Test run with 2870 tests
in 3 suites passed`** (173.6 s; 2790 + 80), `FR-J` line present. The first run
read one issue, `RichTextTests.theOperandCheckSeesEveryHandlersMember`
(`children.count == 17`): rich text pinned the `Handlers` count it knew, this
branch made it 18. The test now expects 18 and gains a `pointer` arm (its own
doc comment had promised both). Guards 185 (`git grep "enabled(if:
canTypecheck"` reads 184), census 2806, goldens 0. The default-build-system
warning count, the demo-pixel comparison, `Backends/SDL` and the Linux image
were not re-taken by the merge itself; the branch checker re-took them (§4.6).

### 4.2 Demo pixels, platforms, what was not taken

- `compare.sh <scratch> 70ed000 6678e60`: **0 differing pixels, scene
  identical, in all fourteen images**. The controls are at `70ed000`'s
  values: light vs dark 1048576, default vs modal 1031003, default vs
  animation 454895, f0 vs f3 0. `DemoFrameDeterminismTests`' `Expected.swift`
  is unedited (Linux and Windows CI confirm on push). No shader change.
  `MetalUILayout` imports only `MetalUICore` and `MetalUIScene` imports only
  `MetalUIShaderTypes` (neither was touched).
- Not taken: any real-window capture, and every group Y look (an agent
  cannot). On Windows nothing was built or run here. The SDL changes are
  portable C and Swift with explicit enum conversions, and they are
  unexercised on Windows until a push.

### 4.3 Mutations

Recorded where each was run: lane 1 in `CI-Y` item 4 and `CI-Z` item 6,
lane 2 and lane A in `CI-AF` and `CI-AG`, lane B in `CI-AH` item 3, and lane C
in `CI-AI` item 5 (3.35: zoom about the canvas origin reddens only 3.35, three expectations; 3.36: the noble overflow is its
measurement).

### 4.4 Spec §8.3, discharged

`CLAUDE.md`/`AGENTS.md` got the `CI-` prefix with next `CI-AK`, a rule
paragraph, "`Handlers` has **eighteen** members", `setPointerStyle(_:)` in the
defaultless list, divergences 108 / next 142 (120 / 159 after the merge below), group Y, `METALUI_CANVAS_DEMO=1`
and the counts. `README.md`, `docs/record/README.md` (row 81), record §03 (the
looks owed) and §04 (139–141) were updated too.

### 4.5 The merge with master (`CI-AJ` item 6)

Master had moved to `dc6528c` (records 82, 83, 84, 86; this record keeps 81).
Conflicts were additive and resolved by keeping both sides: the macOS and SDL
demo composers (canvas, rich text, list, services…), `DemoStackBudgetTests`
(three `@inline(never)` builders), `SDLPlatform.init`, the divergence table and
header (live 120, next label 159), the record map, §03/§04, human checks (groups
A–Y with VL and RT), `CLAUDE.md`/`AGENTS.md` (the `CI-` prefix, next `CI-AK`),
and the census, re-recorded from the merged tree (2806 lines). The measured
counts of the merged tree are in `CLAUDE.md`'s counts bullet.

### 4.6 The branch checker (`CI-AK`)

On the merged tree `1337ff6`: a clean native build and unfiltered suite,
**`Test run with 2870 tests in 3 suites passed after 179.614 seconds`**, `FR-J`
line present; `swift build --build-tests` 0 warnings; guards 185; the census
re-run byte-identical (2806); both closeout checks silent; `cmp CLAUDE.md
AGENTS.md` identical; every cited `CI-` id and test name resolves.
`compare.sh <scratch> 70ed000 HEAD`: 0 differing, scene identical, in all
fourteen images. `Backends/SDL` 24 + 98 on macOS and 24 + 95 in the Linux
image; root in `swift:6.4-noble` 6 + 35 + 18 + 199 + 67 + 22, 0 warnings.
Mutations: dropping the wheel chain's layer filter reddens
`aDeferredScrimDeclaredInsideAScrollViewStillSwallowsTheWheel`,
`aPopoverAboveACanvasTakesItsWheelPinchStyleAndButtonDrags` and
`theDemoModalDismissesOnAScrimClickAndSwallowsTheWheel`; removing the
release-time drag check alone is green (an equivalent mutant: the move clears
the pending menu first), and removing it with the move's clearing reddens
`aSecondaryDragOpensNoContextMenu` only. One new open finding: a declining
`.onScrollWheel` on a `TextEditor` stops the editor scrolling itself (`CI-AK`
item 6, the same cause as `CI-AJ` item 1).

### 4.7 The open findings fixed (`CI-AL`)

Red first on `2723d56`, fixed in `e5f9da5`. **`CI-AJ` item 1 and `CI-AK`
item 6 resolved** (one cause): when the ranking's top wheel match is a
handler-only region and the same id's opaque hitbox on its layer is under the
point, `applyScroll` makes that hitbox the cover (the one ranking again), so a
declining `.onScrollWheel` on a click target still stops the wheel and one on a
`TextEditor` leaves it scrolling itself, in a `Box` and inside a `ScrollView`
(`aDecliningWheelHandlerOnAClickTargetStillSwallowsTheWheel`,
`aDecliningWheelHandlerOnATextEditorLeavesItScrollingItself`; red lines:
`→ false`, `raw 1`; editor `0.0`, outer scroller `30.0`). **`CI-AJ` item 3
resolved**: a `.magnify`/`.rotate` moves `lastMousePosition` and recomputes
hover and the pointer style
(`aPinchRecomputesTheHoverAndThePointerStyleAtItsPosition`; red: `[]`,
`[.arrow]`). **`CI-AJ` item 2 resolved, doc only**: `CI-AH` item 1 holds for
the built-in scrollers; a custom conformer's shared-id order stays unpinned.
Mutations M1–M6 each red on the full suite, naming only the new tests except
M4 (four existing wheel tests). Clean native suite **`Test run with 2873
tests in 3 suites passed after 177.500 seconds`**, `FR-J` line present
(one earlier run stopped silently mid-suite and did not reproduce, `CI-AL`
item 5); default build 0 warnings; guards 185; closeout checks silent;
fourteen images 0 px.

## 5. Owed and deferred

- **Verifier findings** (`CI-AJ` items 1–4): items 1–3 **resolved by
  `CI-AL`** (item 2 by narrowing the sentence; a custom conformer's shared-id
  order is unpinned, owner none). Item 4 stays open, owner none: the canvas
  demo's ⌃-scroll zoom, zoom clamp and momentum pan are unpinned (mutations
  m2, m6, m7 green).
- **Branch checker's finding** (`CI-AK` item 6): **resolved by `CI-AL`
  item 1**, with `CI-AJ` item 1.

- **Human checks group Y** (Y1–Y13, `docs/verification/human-checks.md`):
  trackpad momentum, pinch centre, rotate sign, nested magnify/rotate, every
  cursor on AppKit and SDL, SDL pinch speed on Linux, real mouse buttons,
  modifiers mid-drag, the Windows touchpad pinch as ⌃-wheel, wheel-mouse
  steps, the immediate cursor set (Y12), and the glide across elements
  (Y13, no latching, `CI-AD`).
- **Deferred** (spec §9, owner none): gesture `time`/`velocity`/`predictedEnd*`;
  image and shape cursors and the directional resizes; `onModifierKeysChanged`;
  `CoordinateSpace.named`; a default I-beam or hand on MetalUI's controls;
  rotate on SDL, pinch on Windows, and wheel phase/momentum/precision on SDL;
  `inputKinds:`; scroll chaining; wheel latching. **Two of these are not
  additive** (`CI-AC`): `CoordinateSpace.named` and an image cursor each add
  an enum case.
