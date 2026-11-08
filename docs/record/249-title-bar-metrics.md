# Record 249: the app-chosen hidden title-bar band and window-button inset (MetalCreator gap AS-a)

Branch `feat/title-bar-height` (master `60c2998c`). Ruling `AS-R` in `docs/superpowers/2026-10-08-app-shell-decisions.md`. Class `M`, no divergence. One new public modifier, `ElementGroup.windowTitleBarMetrics(height:controlsLeading:)`, and one defaultless `PlatformWindow` requirement, `setTitleBarMetrics(height:controlsLeading:) -> Bool`.

## 1. The gap

MetalCreator's hidden-title-bar window wants a 68-point band with the traffic lights centred in it (centre y 34) and the first button's left edge at about 27 (AppKit's is about 9). `titleBarInsets` only reported what AppKit gave.

## 2. The probe (standalone AppKit, `fullSizeContentView`, transparent bar, hidden title, 700 x 400 window)

Baseline: band 32, buttons x 9..23 / 32..46 / 55..69, centre y 16, container height 32.

| Approach | Band | Close x | Centre y |
|---|---|---|---|
| empty `NSToolbar`, `.unified` / `.automatic` | 52 | 19 | 26 |
| `.unifiedCompact` | 40 | 12 | 20 |
| `.expanded` | 48 | 9 | 16 (top-aligned) |
| `.preference` | 88 | 20 | 44 |
| `.expanded` with a 60-point custom item | 100 | 9 | 16 |
| `.unified` with a 60-point custom item | 52 (no change) | 19 | 26 |
| `.bottom` accessory, view height 20 / 40 / 68 | 68 for all three (unexplained) | 9 | 16 |
| manual placement (container 68, buttons centred, leading 27) | `contentLayoutRect` stays 32; container 68 | 27 | 34 |

No toolbar style reaches an arbitrary height and none moves the buttons horizontally except as a side effect of the style. A bottom accessory grows the band but never re-centres or moves the buttons. Manual placement is the only route to (68, 34, 27); it is what Electron's `trafficLightPosition` does.

What resets a manual placement (no hook): the first `setFrame` (all five resizes), a `title` change, a toolbar added, full screen. Notifications alone (`didResize`, key, full screen) hold through `setFrame` but not through a `title` change, which fires none. KVO on the buttons' and the two views' `frame` held through resize, title and key changes. A synchronous re-place inside the observer segfaulted (re-entrant layout); deferred one run-loop pass without an equality guard it ran 1.9 million times; with both it ran 26 times across the whole sequence. Placing in full screen put the buttons at y 2094 (the container is above the screen there), so it is skipped. `needsLayout`, `layoutSubtreeIfNeeded` and `layoutIfNeeded` do not give the system layout back; a one-point resize and back (no display) does. Hit testing of the moved zoom button works (`themeFrame.hitTest` returns the zoom widget, `performClick` runs its action). Full-screen exit could not be completed in the probe session (the app was never active, the window never key): human check TBH4.

## 3. What was built

- `.windowTitleBarMetrics(height: Pixels? = nil, controlsLeading: Pixels? = nil)`: an `EnvironmentScope` case reported post-order into `Frame.collectedTitleBarMetrics` (first wins), counted by the build audit and listed as `.buildOnly` in `RetainedSubtreeInternalTests`.
- `Window.reconcileTitleBarMetrics()` (`WindowShell.swift`): sends the tree's pair while the hidden style is applied, empty otherwise, only on change; the platform's answer feeds `titleBarMetricsHonoured`, which the SDL drawn cluster reads.
- AppKit: `TitleBarPlacement` (`AppKitTitleBarPlacement.swift`, `place()` and the hook), `AppKitWindow.setTitleBarMetrics`, `titleBarInsets.top` = the chosen height, `.left` = the zoom button's right edge read back (87 for leading 27, 69 for the system). Installed only under `.hidden` with a field set; removed on `.standard`, on `(nil, nil)` and when a field is dropped (the one-point resize restores the system layout). The geometry is re-reported when the placement changes.
- SDL: `top` follows `height`; under macOS the drawn circles are centred in the band at the leading (the cluster rect grows by `leading - 8`, `left` = leading + 62); Windows/Linux follow the height and ignore the inset.
- Headless: records requests, `Options.appliesTitleBarMetrics`, and answers as AppKit (`top` = height, `left` = leading + 60 where `left > 0`).
- Demo: `METALUI_CHROME_DEMO=1` opens with the metrics on (68, 27) and a button to switch them off.

## 4. Tests and mutations

`TitleBarMetricsTests` (10, headless, portable); four AppKit tests in `AppKitAppShellTests.swift`; two in `SDLChromeTests.swift`; the compile-guard table gained `setTitleBarMetrics`.

| Mutation | Reddened |
|---|---|
| equality guards removed (container, bar, button) | `theTitleBarPlacementsHookPiecesEachHold` (a) |
| full-screen skip removed | `theTitleBarPlacementsHookPiecesEachHold` (b) |
| notification backstop removed | `theTitleBarPlacementsHookPiecesEachHold` (c) |
| frame observers off | `appKitTitleBarMetricsSurviveResizeAndTitleChange` |
| `titleBarInsets.top` keeps the system band | `appKitTitleBarMetricsCentreTheButtonsAndReportTheBandAndEdge`, `appKitTitleBarMetricsApplyPerFieldAndClear` |
| `remove()` skips the relayout | `appKitTitleBarMetricsApplyPerFieldAndClear` |
| headless `top` ignores the height | `aHeightAloneIsTheBandAndKeepsTheSystemLeft`, `bothFieldsMoveTheBandAndTheButtonsEdge`, `leavingTheHiddenStyleClearsTheMetrics`, `anInnerModifierBeatsAnEnclosingOne`, `theModifierLeavingRestoresTheSystemLayout`, `theDrawnLeftClusterCentresInTheBandAtTheInset`, `aRightHandClusterIgnoresTheInset` |
| headless `left` keeps the system edge | `bothFieldsMoveTheBandAndTheButtonsEdge` |
| `Window` sends under the standard style | `theStandardStyleIgnoresTheMetrics`, `leavingTheHiddenStyleClearsTheMetrics` |
| `Window` keeps the metrics when the tree reports none | `theModifierLeavingRestoresTheSystemLayout` |
| `honoured` ignores the platform's answer | `aPlatformThatRefusesKeepsTheSystemBandAndCluster` |
| the strip ignores `leading` | `theDrawnLeftClusterCentresInTheBandAtTheInset` |

Not testable headlessly: the deferral (without it the process crashes in AppKit's layout, observed in the probe, not pinned), real key changes, full-screen enter/exit and a live drag-resize (group TBH). The full-screen skip is pinned through the injectable `isFullScreen`, not a real full-screen window.

## 5. The run-loop finding

The first unfiltered native run ended with exit 0 and no summary line inside the fourth AppKit test (`appKitTitleBarMetricsApplyPerFieldAndClear`), a filtered run passing. A final nested `RunLoop.main.run` moved the death to the next AppKit test (`theEditMenuReachesTheFocusedFieldAsItsKeys`), deterministically over two runs; `--skip` of the four new AppKit tests gave a full pass (5741). This is record §61 §9's hazard (HIToolbox queues `CFRunLoopStop` on the main loop when AppKit's event signal blocks are absent). The four tests now run `-[NSApplication run]` once and stop it (`appKitEventSignal`, copied from `SDLPlatform.installAppKitEventSignal`), and the unfiltered native run passes: **5745 tests in 26 suites, 0 failures, `FR-J no-argument frame: succeeded=true`** (after `swift package clean`; guards and the portable image not re-counted).

## 6. Carried

A system toolbar under a placed band is not re-laid-out to the band's height. `Options.appliesTitleBarMetrics` is the only refusing headless knob. The accessory band of 68 for any height is unexplained. The reliance on `NSTitlebarContainerView` is the cost named in `AS-R`.
