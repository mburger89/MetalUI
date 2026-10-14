# SDL custom window chrome — design

Item S1 (user request 2026-10-02; MetalCreator SDL-port gap 3). Rulings: `../2026-10-13-sdl-chrome-decisions.md`
(`CW-A`…`CW-T`). Status: lane 1 built (seam, `Window`, strip, headless, rulings `CW-Q`); lane 2 (`Backends/SDL`: bridge, platform, SDL tests, Linux image) built, rulings `CW-S`, `CW-T` (a style asked for in fullscreen answers `true` and applies on the leave; the style answer is what the driver did). Base `fb9a7e42` (3717 tests, 234 guards).

## Goal

On Linux and Windows (macOS through SDL where it works) `windowStyle: .hiddenTitleBar` gives a borderless,
resizable window that MetalUI's content fills; the band is draggable except where the app has a control;
the window draws minimise/zoom/close unless the app opts out; the edges resize. A test drives all of it headless.

## Public API (all class M, no SwiftUI analogue; probe `swiftui-window-chrome.swift`)

```swift
// MetalUI
extension Window {
    public var drawsWindowControls: Bool          // default true; only effective where the platform has no native buttons
    public func minimize()                         // PlatformWindow.performWindowAction(.minimize)
    public func toggleZoom()                       // .toggleZoom
    public var isZoomed: Bool { get }
}
// MetalUIPlatform
public enum PlatformWindowAction: Sendable, Equatable { case minimize, toggleZoom }
public protocol PlatformWindow {   // four defaultless requirements (CW-F)
    func setWindowDragRegions(_ regions: [Rect<Pixels>]) -> Bool
    func performWindowAction(_ action: PlatformWindowAction) -> Bool
    var hasNativeWindowControls: Bool { get }
    var isZoomed: Bool { get }
}
public struct ChromeHitSnapshot: Sendable, Equatable { … func hit(at: Point<Pixels>) -> ChromeHit }
public enum ChromeHit: Sendable, Equatable { case normal, draggable, resize(Edge/corner) }
// MetalUITesting
HeadlessPlatform.Options.sdlChrome; .usesWindowDragRegions; .hasNativeWindowControls; .isZoomed
TestWindow.windowDragRegions: [Rect<Pixels>]; TestWindow.windowActions: [PlatformWindowAction]
```
`App.openWindow(…, windowStyle:)`, `Window.windowStyle`, `titleBarInsets`, `WindowDragGesture`,
`performClose()` are unchanged in spelling. Divergences: 175 amended (SDL now applies the style and reads
insets 32 + cluster), 276 amended (SDL moves the window from a handle through a region; `performWindowDrag`
still `false`), **425** (pointer events inside a drag region are not delivered on SDL), **426** (a handle with a
button or tap inside is draggable only around it; blockers carved), **427 reserved** (Linux double-click zoom,
taken only if a real-display run confirms the failure). Header's next-label line is left to the merge.

## Mechanism (decisions CW-B…CW-J)

1. `SDLPlatformWindow.setTitleBarStyle` → `mui_window_set_bordered`; answers SDL's result; re-applies the last
   requested style on leaving fullscreen.
2. `titleBarInsets`: band 32 + cluster (138 right / 70 left on macOS), zero in fullscreen; `Window` zeroes the
   cluster side when `drawsWindowControls` is false.
3. `Window` (post-frame, only if the platform wants regions): candidates (band, drag-gesture rects) minus
   blockers (opaque, gesture/draggable, drop, contextual hitboxes; conservative bounds) → ≤ 64 disjoint rects,
   empty while any presentation is open, sent only on change. New file `Sources/MetalUI/ChromeRegions.swift`
   (`ChromeRegions.compute(…)`, pure over a hitbox list, plus `ChromeHitMap.carve`).
4. Drawn controls: `Sources/MetalUI/WindowControlsStrip.swift`, a `Deferred` presentation root named
   `$windowcontrols` (precedent `MenuBarStrip.swift`), three `Button`s calling `performClose()`/`minimize()`/
   `toggleZoom()`.
5. Bridge: `mui_window_set_bordered`, `mui_window_set_hit_test(window, snapshot*)` (installs a C callback over
   an `SDL_Mutex`-guarded snapshot copy; NULL clears), `mui_chrome_hit`, `mui_window_minimize/maximize/restore`,
   `mui_window_is_maximized`/`is_fullscreen`. Edges (6 pt) only for a borderless, unzoomed window on axes whose
   limits differ; order corner, edge, drag rect, normal.
6. `performTitleBarPress(clickCount ≥ 2)` toggles zoom on SDL (`true`); native on Windows via `HTCAPTION`.

## Files

Lane 1 (root; no `Backends/SDL` file except the stub conformer lines): `Sources/MetalUIPlatform/Platform.swift`,
`AppShell.swift`, new `ChromeHit.swift`; `Sources/MetalUI/Window*.swift` (`WindowShell.swift:163,174`
`effectiveTitleBarInsets`), new `ChromeRegions.swift`, `WindowControlsStrip.swift`; `Sources/MetalUIAppKit`
(four members); `Sources/MetalUITesting/HeadlessPlatformWindow.swift`, `TestWindow*.swift`; every root test fake;
`Sources/MetalUIDemoContent` (new `ChromeDemo.swift`, `METALUI_CHROME_DEMO=1`, own function for the 1 MB stack);
inventory map and census; docs: `docs/divergences.md`, `docs/api-overview.md`, `docs/migration.md`,
`docs/verification/human-checks.md` group **CW**, `docs/testing.md` (preset).
Lane 2 (`Backends/SDL`; also `docs/guides/cross-platform.md`, CW-P): `SDLBridge.c`, `SDLBridge.h`, `SDLPlatform.swift` (window members at 950–985),
`Backends/SDL/Tests/MetalUISDLTests/SDLChromeTests.swift`, SDL test fakes, Linux image run.

## Tests (name — red before — mutation that must redden it)

All new root tests are red on arrival (the symbols do not exist). Mutations follow the practice: commit first,
restore from a copy, full unfiltered suite, `git status --short` after, name the reddened tests.

Lane 1, `Tests/MetalUIPlatformTests/ChromeHitSnapshotTests.swift` (portable; runs on Linux CI):
- `aPointInADragRectIsDraggable` — `hit` returns `.normal` — mutate `hit` to skip the rect loop.
- `aRectCarvedByABlockerLeavesTheRemainderOnly` — no `carve` — mutate `carve` to ignore the blocker's y range.
- `cornersBeatEdgesBeatDragRects` — mutate the order (drag before edge): reddens the band-top row case.
- `noEdgeOnAnAxisWithEqualLimits`, `noEdgesWhenZoomedOrFullscreen`, `anUnborderedWindowHasNoEdges` — one mutation each.
- `aListBeyondSixtyFourRectsIsCappedAndCounted` — mutate the cap to 65.
Lane 1, `Tests/MetalUITestingTests/WindowChromeTests.swift` (root, `Options.sdlChrome`):
- `aHiddenStyleOnAnSDLLikePlatformStampsBandAndClusterInsets` — mutate the CW-D clause (ignore `drawsWindowControls`).
- `theBandIsOneRegionWhenNothingIsInIt`, `aButtonInTheBandIsCarvedOut`, `aTapGestureInTheBandIsCarvedOut`,
  `aTextFieldInTheBandIsCarvedOut`, `aHoverRegionInTheBandIsNotABlocker` — mutate the blocker predicate
  (drop `valueTrack`, drop gesture members, add hover): each reddens its own arm.
- `aWindowDragHandleOutsideTheBandIsARegion`, `aHandleWithAButtonInsideIsRegionsAroundIt`.
- `anOpenPopoverAlertOrMenuPublishesNoRegions` — mutate to ignore presentations.
- `regionsArePublishedOnlyOnChange` (counter on the headless platform) — mutate to publish every frame.
- `aPlatformDecliningRegionsIsNeverAskedAgain` (AppKit-like options; `FrameWork` carve counter stays 0).
- `theStripDrawsThreeButtonsWhereThePlatformHasNone`, `aNativeControlsPlatformDrawsNoStrip`,
  `drawsWindowControlsFalseDrawsNoStripAndZeroesTheCluster`.
- `theCloseButtonGoesThroughTheCloseVeto` (`onCloseRequest` `.cancel` keeps the window),
  `theMinimiseAndZoomButtonsSendTheirActions`, `zoomShowsRestoreAfterIsZoomed` — mutate close to `close()`.
- `fullscreenPublishesNoRegionsAndNoStrip`.
- `aStandardStyleWindowIsUntouched` (no regions, no strip, no actions) and the existing
  `aPlatformAnsweringFalseStillEndsThePress`, 2.21 keep passing.
- Typecheck guards (new, `typecheck`/plain import): `thePlatformWindowChromeRequirementsHaveNoDefaults` (a conformer
  omitting `performWindowAction` fails — mutate by adding an extension default: guard reddens),
  `theChromeVerbsAreReachableFromAPlainImport`. Each guard mutated red once.
- Pixels: fourteen images 0 px against `fb9a7e42` (`compare.sh`); `DemoFrameDeterminismTests` untouched.
Lane 2, `Backends/SDL/Tests/MetalUISDLTests/SDLChromeTests.swift` (every helper `armMainRunLoopExitCheck()`):
- `hiddenStyleMakesTheWindowBorderlessAndAnswersTrue`, `standardStyleRestoresTheBorder` — read
  `SDL_WINDOW_BORDERLESS` through a bridge getter (gated `.enabled(if:)` if the offscreen driver drops it) —
  mutate the bridge to pass `true`.
- `theBridgeCallbackAgreesWithTheSwiftReferenceOverATable` — `mui_chrome_hit` vs `ChromeHitSnapshot.hit` (mutate
  one C comparison `<` → `<=`).
- `aConcurrentPublishNeverTearsAnAnswer` (two threads, 10⁵ iterations, answers always from one of two known
  snapshots) — mutate to drop the lock; may be flaky-red, so also assert the mutex is held across the copy via a
  bridge counter.
- `clearingTheRegionsAndEdgesRemovesTheCallback`, `aPlainWindowNeverInstallsOne`.
- `insetsAreBandPlusClusterPerPlatformAndZeroInFullscreen` (fullscreen part gated on a presenting driver).
- `performWindowActionSendsMinimizeAndZoomRestore` (flag reads gated), `aDoubleClickPressTogglesZoom`,
  `leavingFullscreenReappliesTheLastRequestedStyle`.
- Existing `SDLAppShellTests` cases for the old `false` answers are re-pinned to the new ones.
- Linux image run; Windows UTM/CI; the real drag and resize are human checks.

## Demo

`METALUI_CHROME_DEMO=1`: `.hiddenTitleBar`, a 32-pt glass bar padded by `titleBarInsets`, a title, a button,
a `WindowDragGesture` handle and a text field in the band, a body of ordinary content. Expectation (human check
CW1): the window drags by empty bar and handle, the button and field work, edges resize, the three buttons
close/minimise/zoom, the content is not covered by the cluster.

## Human checks (group CW, an agent cannot run them)

CW1 looks of the demo on Windows 11 and Linux X11 and Wayland, CW2 drag from empty band and handle, CW3 a
button, field and tap in the band still work (the swallow carve), CW4 resize at each edge and corner, the
6-pt border over a scrollbar, CW5 hover/pointer-style loss inside a drag region (divergence 425), CW6
double-click zoom on Windows and Linux (CW-I), CW7 macOS-through-SDL left cluster, CW8 fullscreen enter/leave
restores the borderless style, CW9 a borderless Windows window's shadow and corners.

## Scope not built

Linux double-click zoom (CW-A, CW-I; owner: CW6's measuring session); snap layouts; tiled/maximised Wayland
shadows; `windowBackgroundDragBehavior`; a public `WindowControls` view (rejected, CW-C); per-window control
placement. Cross-platform guide statements land with lane 2 only after the Linux image run.
