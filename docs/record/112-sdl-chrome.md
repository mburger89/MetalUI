# 112 — SDL custom window chrome (item S1)

Branch `feat/sdl-custom-chrome` from `fb9a7e42` (master: retained subtrees, §109; master had not moved at the Record
phase, so no merge and no renumbering — §112 stands; §110 and §111 are the parallel branches').
User request 2026-10-02 (gpui-gap priority list, item S1; **not a plan task**), reported as MetalCreator's SDL-port
gap 3 (developer-c0, 2026-10-13; read, never edited). Spec `docs/superpowers/specs/2026-10-13-sdl-chrome-design.md`;
rulings `CW-A`…`CW-T` in the new decisions doc `docs/superpowers/2026-10-13-sdl-chrome-decisions.md` (next unused
`CW-V`; `CW-U` is the Record phase's close); probe `docs/probes/swiftui-window-chrome.swift`; human checks group `CW`.
Divergences 175 and 276 amended, 425 and 426 added (range 425–434; 427 reserved for check CW6, unused).

**Status: LANDED — every agent-doable clause is built; the looks, the drag, the edges and the Windows run are owed to a
human or to CI** (`docs/verification/human-checks.md` group CW). Two lanes, each red first, each with a verifier
(`ok: true`), then this Record phase re-took the suite, the counts and the fourteen images.

## §0 What the item asked, and what a borderless SDL window needs

`App.openWindow(…, windowStyle: .hiddenTitleBar)` was a macOS-only feature: on SDL `setTitleBarStyle` answered `false`,
`titleBarInsets` was zero and `performWindowDrag()` recorded and answered `false` (divergence 276, `WD-F`), so a glass
top bar had no window to be the bar of. SDL has `SDL_SetWindowBordered`, `SDL_SetWindowHitTest` and the resize
answers of the hit test, but the hit test runs on SDL's thread and must answer synchronously, and a borderless window
has no system buttons. SwiftUI has no analogue of any of it (probe `swiftui-window-chrome.swift`: no minimise or zoom
action, no drawn control set, no title-bar double-click hook; arm P compiles, N1–N4 fail), so everything past
`.hiddenTitleBar` and `WindowDragGesture` is class M. Baseline at `fb9a7e42`: **3717 tests in 3 suites**, 0 goldens,
234 typecheck guards, `Backends/SDL` 30 + 125 on macOS was lane 1's reading after its additions (lane 2 below).

## §1 What landed

**The seam** (`CW-F`). Four defaultless `PlatformWindow` requirements, an honest answer in every conformer
(AppKit, SDL, `HeadlessPlatformWindow`, every test fake; `docs/migration.md`): `setWindowDragRegions(_:) -> Bool`
(window-point `Bounds<Pixels>` list), `performWindowAction(_:) -> Bool` over `PlatformWindowAction`
(`minimize`, `toggleZoom`), `hasNativeWindowControls`, `isZoomed`. AppKit answers its own (`true` controls, native
miniaturise and zoom); SDL below.

**Portable geometry** (`MetalUIPlatform/ChromeHit.swift`, `CW-E`, `CW-G`). `ChromeHitSnapshot` and `ChromeHit` are the
one hit-test function (rects half-open on the max edges; a 6-point border and 12-point corner squares for a borderless,
resizable, not-zoomed, not-fullscreen window; an axis with equal limits has no edge on it; corners beat edges beat
drag rects), and `ChromeHitMap.carve` (`package`) makes the drag regions: candidates minus blockers, disjoint, in
reading order, capped at 64 and counted.

**`Window`** (`WindowChrome.swift`, `ChromeRegions.swift`, `WindowControlsStrip.swift`, `CW-C`, `CW-D`, `CW-Q`). New
public API, class M: `Window.drawsWindowControls` (default `true`), `minimize()`, `toggleZoom()`, `isZoomed`. The
candidates are the unclaimed band (`AS-J`) and every `WindowDragGesture` handle; the blockers are the hitboxes that
need the pointer (a button, a tap or other gesture, a text field, a value track, a draggable, a drop destination, a
context menu); a hover region is not a blocker (divergence 425). The regions are published to the platform **on
change only** and held still while a press is in progress. The drawn system buttons are the `$windowcontrols` strip,
a fourth named root at cursor index 3 (not a `Deferred`): three 46 x 32 flat rectangles at the right of the band
(138 points), or three 12-point circles at the left (70 points, macOS under SDL), the side chosen from the platform's
insets; Close goes through the close veto (`AS-B`, `performClose`), minimise and zoom through `performWindowAction`,
zoom reads "Restore" while zoomed. With no band height (fullscreen) there is no strip and no region.
`performTitleBarPress(clickCount ≥ 2)` toggles zoom.

**`Backends/SDL`** (`SDLBridge.c`/`.h`, `SDLPlatform.swift`, `CW-B`, `CW-H`, `CW-S`). `mui_window_set_bordered`
(reads `SDL_WINDOW_BORDERLESS` back, so the answer is what the driver did), `mui_window_set_hit_test` over a
per-window `SDL_Mutex`-guarded `MUIChromeSnapshot` (an immutable copy of at most 64 rects in the window's SDL
properties, cleared before destroy), `mui_chrome_hit` (the C twin of `ChromeHitSnapshot.hit(at:)`) and
`mui_window_chrome_hit` (the callback's own body, which the tests call), lock counters, minimise/maximise/restore and
the flag reads; fullscreen, maximise and restore events reach the resize handler so the snapshot's size follows.
`SDLPlatform`: `setTitleBarStyle` (borderless; a style asked for in fullscreen is recorded, answers `true` and is
applied on the leave), `titleBarInsets` (32 band; right 138, left 70 under macOS; zero in fullscreen),
`setWindowDragRegions` (publishes with the edges, installs the callback only when there is something to answer),
`performWindowAction`, `hasNativeWindowControls` `false`, `isZoomed`, and `performWindowDrag()` still `false` (the
platform moves the window before `Window` sees the press, divergence 276).

**Test and demo support.** `HeadlessPlatform.Options.sdlChrome` (and `hiddenTitleBarInsets`), the read-backs
`TestWindow.windowDragRegions`/`windowActions`; `METALUI_CHROME_DEMO=1` in both demos (`ChromeDemo.swift`, built in
its own function, `DemoStackBudgetTests` row).

## §2 Tests and guards, per file

| file | new | what |
|---|---|---|
| `Tests/MetalUICrossPlatformTests/ChromeHitSnapshotTests.swift` | 13 | the hit function, border and corner widths, half-open edges, fixed axes, zoomed and fullscreen, `carve` |
| `Tests/MetalUITestingTests/WindowChromeTests.swift` | 26 | regions, blockers, publish-on-change, strip, close veto, insets, 2x scale, fullscreen |
| `Tests/MetalUITests/ChromeCompileGuards.swift` | 2 guards | `CW-1` `aPlatformWindowWithoutEachChromeRequirementDoesNotCompile`, `CW-2` `theChromeVerbsAreReachableFromAPlainImport` |
| `Backends/SDL/Tests/MetalUISDLTests/SDLChromeTests.swift` | 20 | bridge table, lock counters, border, insets, actions, fullscreen re-apply (12 gated off the offscreen driver) |
| existing guard files, fakes | — | the four requirements added to every fake (`AppShellSeamCompileGuards` and eight sibling files, `Fakes.swift`, `PortableFakeWindow.swift`) |

Root: 3717 + 41 = **3758 tests, 236 guards**. `Backends/SDL`: 30 + 145 on macOS, 30 + 142 in `swift:6.4-noble`
(12 chrome pins skipped by the offscreen driver, `CW-S` 2).

## §3 Probes

`docs/probes/swiftui-window-chrome.swift` (recorded 2026-10-13, header has the output and how to run it). Earlier
probes the rulings lean on: `appkit-titlebar-hit-test.swift`, `swiftui-app-shell.swift` `H0`/`H1` (the 32-point
band, the buttons' right edge 69). SDL 3.4.18's header was **read, not run**; gpui's `WindowDecorations::Client` was
used from memory only to choose the shape (`CW` evidence list).

## §4 Red runs

Lane 1: the portable and window tests failed to compile (`cannot find 'ChromeHitSnapshot' in scope`) before the
build. Lane 2: `SDLChromeTests.swift:146: cannot find type 'MUIChromeSnapshot' in scope`, then the first green run in
the Linux image failed 18 expectations in 9 tests, which were the measured offscreen facts of `CW-S` (2) and one
flawed smoke test, each fixed by a gate or a corrected pin, not by weakening an arm.

## §5 Mutation tables

The full tables are `CW-R` (lane 1, 41 mutations by one instrumented build against the new tests, plus two guard
mutations by edit) and `CW-T` (lane 2, 22: M1–M7 by edit and rebuild, the rest by one instrumented build). Method
deviation from the item's letter, stated in both: filtered runs on the new tests, not the full suite per mutation
(eight minutes a run, a rebuild four to thirty under the machine's load); the verifiers re-took one lane-1 mutation
and four lane-2 mutations with the **full unfiltered suite**, and none reddened a pre-existing test beyond the five
known locked-screen `AppKitPresentationTests` sheet issues. Findings:

- **Lane 1, left cluster unpinned** (verifier, mutation `windowControlsSpec: onRight = true`, nothing reddened): no
  window test has `hiddenTitleBarInsets.left > 0`. Fixed at the Record phase by the pin
  `theMacLikeInsetsDrawTheLeftCluster` (see §9 for the red run).
- Lane 1 mutations 22 and 34 were weak and fixed before the verifier (`CW-R`).
- Lane 2 survivors, named: M19 (minimise called maximise) survived its first pin and was repaired to read
  `SDL_WINDOW_MINIMIZED`; M21 (style answer not read back) is unobservable on macOS and reddens two tests in the
  Linux image only; M22 (destroy keeps the callback installed) is unobservable (SDL clears it first), a defensive
  line, unpinned.
- `aConcurrentPublishNeverTearsAnAnswer` stays green without the lock; **the lock counter
  `thePublishAndTheCallbackEachHoldTheLockOnce` is the lock pin, the stress run is a smoke run** (`CW-O`, `CW-T`).

## §6 Demo comparison

`docs/probes/demo-pixels/compare.sh <scratch> fb9a7e42 HEAD`: **14 of 14 offscreen images scene-identical, 0 px**,
controls at their recorded values (light vs dark 1048576, default vs modal 1031003, default vs animation 454895,
`f0` vs `f3` 0), taken by both verifiers and re-taken at §9. A window that does not ask for `.hiddenTitleBar` on a
platform that answers `false` to the four requirements computes nothing new (`aStandardStyleWindowIsUntouched`).

## §7 Hazards

- **A hit-test callback runs on SDL's thread and may fire at any time** (SDL header). The Swift side never touches it:
  it publishes an immutable snapshot under the window's `SDL_Mutex` and the callback copies it under the same lock
  (`CW-H`); the tests call `mui_window_chrome_hit`, the callback's own body. Not proved: that no other field is read
  unlocked (the counter proves the lock is taken, not that every field is under it).
- **Pointer events inside a drag region are not delivered on SDL** (divergence 425): hover, pointer style, tooltips and
  the wheel over the empty band are lost; platforms differ, so check CW5 measures it.
- **A fullscreen window cannot change its border** (SDL): the request is recorded, answers `true` and applies on the
  leave (`CW-S` 1).
- **The offscreen driver cannot change a border or install a hit test** (measured in the image): the platform
  answers `false` there, `Window` keeps the standard style, and the tests that need a working driver are gated like
  `SDLLifecycleTests`' frames. Do not read a green Linux image as proof of a real borderless window.
- A C enum's `rawValue` is `Int32` on Windows: the bridge's results are `MUI_CHROME_HIT_*` `Int32` constants converted
  explicitly (`SDLChrome.hit(fromBridge:)`), unrun on Windows.
- A new `PlatformWindow` requirement owes the headless platform an honest answer in the same change (`HT-X` 1): done,
  and `HeadlessPlatform.Options.sdlChrome` is the SDL-like preset.

## §8 Deferrals, with owners

| deferral | owner |
|---|---|
| Linux (X11, Wayland) double-click-to-zoom on the band: SDL consumes both presses of the region (`CW-I`) | check CW6 on a real desktop; divergence 427 is taken only if it fails |
| Windows 11 snap-layout flyout (`HTMAXBUTTON` is not an SDL answer), DWM shadow and rounded corners of a borderless window | platform; check CW9 |
| a real drag, resize edge, border swallow, double-click, snap, and the looks | human check group CW (CW1–CW10) |
| Windows UTM and CI runs of `Backends/SDL` (`ssh metalui-win` timed out) | the Windows CI jobs on push |
| client-side shadow and tiling on Wayland; `windowBackgroundDragBehavior`; a hover wash on the drawn buttons (it would add a hover region) | not scheduled |
| `performWindowDrag()` answering `true` on SDL (the region takes the press first) | not scheduled (divergence 276) |
| the default build system's 0-warning count on a clean build (the lane readings saw a mostly cached build) | taken at §9 |

## §9 Record-phase close (2026-10-14)

- `git fetch`: master still `fb9a7e42`; no merge, no renumbering.
- The left-cluster pin `theMacLikeInsetsDrawTheLeftCluster` was added (the lane 1 verifier's finding), red first
  against `onRight = true`.
- `swift package clean`, native build and the unfiltered native run: the suite line, the guard count, `FR-J`, the
  warning count, the fourteen images and the inventory scripts are in §10.
- CLAUDE.md gets the rule, the `CW-` prefix (next `CW-V`) and the counts bullet; `AGENTS.md` copied and compared;
  `docs/api-overview.md`, `docs/divergences.md`, `docs/migration.md`, `docs/verification/human-checks.md` (group CW),
  `docs/record/README.md`, `docs/guides/cross-platform.md` and `docs/testing.md` were written with the lanes and
  re-read here against the source.

## §10 Final counts

- Native, after `swift package clean`: build 0 `error:`, the only `warning:` SwiftPM's deprecation notice;
  **`Test run with 3759 tests in 3 suites failed after 693.643 seconds with 5 issues`** — the five issues are exactly
  the locked-screen `AppKitPresentationTests` sheet tests (`appKitOpenDialogIsASheetWithTheDeclaredTypes`,
  `appKitSaveDialogCarriesTheNameTypesAndExportPrompt`, `appKitCancelledDialogArrivesAsQueuedInput`,
  `appKitDismissPresentationEndsTheSheetAndAnswersNothing`, `appKitSecondDialogWhileASheetIsUpAnswersFalse`; `CI-AF`),
  nothing else. `FR-J no-argument frame: succeeded=true`.
- **3759 tests** (3717 + 42), 0 goldens, **236 typecheck guards** (234 + `CW-1`, `CW-2`; the lanes' count, the Record
  phase added a test, not a guard).
- The left-cluster pin `theMacLikeInsetsDrawTheLeftCluster`: measured literals x 13, 33, 53 (the 52-point cluster plus
  its 8-point pad centred in 70), y 10, size 12; red under `windowControlsSpec`'s `onRight = true` (3 issues), green
  restored, `git status --short` clean.
- Inventory and undocumented scripts print nothing; census 3526 (3511 + 15).
- Divergences: 425, 426 added, 175 and 276 amended; live 152 + 2 = 154 (the header's count and next label are the merge's).
- Not re-taken at this phase: the fourteen images (the lanes' 0 px stand; no `Sources/` change since, only a test), the
  Linux image and `Backends/SDL` (no change since the lane readings), Windows.


## §11 XP-G11: depth-ranked carving (2026-10-14)

MetalCreator's glass top bar over a full-window `DragGesture` viewport read `windowDragRegions == []`: `carve`
subtracted every opaque hitbox whatever its depth, so a view behind the bar took the band and the handles away
(no drag, no double-click zoom). Ruling `CW-V`: a handle is carved only by hitboxes ranked above its own
`(layer, registration index)`; the band, which has no element, is carved by every blocker except a window-wide
backdrop reaching below the band. Tests 2.12 to 2.15 in `WindowChromeTests.swift` (red first, then green);
mutations in the commit message of the fix. `mui_chrome_hit` and `ChromeHitSnapshot.hit(at:)` read the
published rects and needed no change. Counts not re-measured here.
