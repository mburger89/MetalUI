# 400: the window buttons stay placed during a live resize (Alloy; `AS-U`)

Class `M`, no divergence, no public API. Branch `fix/titlebar-live-resize`, base master `595c474a`. **Number:** open PRs held 396 (twice) and 398
and another branch may take 397 and 399, so this is the first free number above 399.

## 1. The report

Alloy, `.windowTitleBarMetrics(height:controlsLeading:)` under `.hiddenTitleBar`: during a live resize the traffic lights flicker, frame to
frame between the placed position and the system one (about 20 pt higher and 20 pt left). "The stop light buttons should not move when
adjusting the window size."

## 2. Diagnosis, confirmed

AppKit resets the buttons (and the container) inside the title-bar view's own layout on every `setFrame`. `TitleBarPlacement` (record 249)
re-placed one run-loop pass later (a synchronous write from the KVO callback re-entered AppKit's layout and crashed, `AS-R` item 3a), so every
frame displayed in between showed the system layout. Measured on a real off-screen `NSWindow` (hidden style, metrics 68 / 27), 30 `setFrame`
steps of mixed width and height with a 30 ms run-loop turn between them, spy subviews in the title-bar view and the container logging the close
button's x at layout and draw:

Order within one `setFrame(display: true)`: the title-bar view's and the container's `setFrameSize`, their KVO, the buttons reset to x 9 inside
the title-bar view's own `layout()` (the buttons' own `frame` KVO does **not** fire for it), the subviews' `layout()` (already reset), the
host view's `setFrameSize`, `viewWillDraw`, `draw`, `didResize`.

## 3. The candidates, 30 steps each (system-position / total)

| Hook (deferred pass off unless stated) | Read after `setFrame` | Title-bar layouts | Draws | Notes |
|---|---|---|---|---|
| Deferred pass alone (before) | 30 / 30 | 27 / 54 | 23 / 50 | the bug |
| 1. Subview `layout()` anchor (chosen) | 0 / 30 | 0 / 27 | 0 / 27 | host `setFrameSize` also sees it placed |
| 2. `NSWindow` subclass, `setFrame(_:display:)` after `super` | 0 / 30 | n/a | as the first row | display runs inside `super`; not built: the draws are the deferred pass's |
| 3. `place()` from the host view's `setFrameSize` | 0 / 30 | 27 / 54 | 0 / 27 | after the reset here, but it is a callback the resize path happens to make; a title or toolbar reset never reaches it |
| 4. `place()` from `didResize` (gpui `window_did_resize`) | 0 / 30 | 27 / 54 | 0 / 27 | gpui calls `move_traffic_light` from the delegate's `windowDidResize`, occlusion, key and full-screen callbacks; after the layouts, before the CA commit here |

Choice: **1**. It is the only hook with no frame, layout or draw at the system position, it runs whichever call resized the window, and it
needs no `NSWindow` subclass (`AppKitWindow` makes a plain `NSWindow`). Candidates 3 and 4 also hid every draw in this off-screen test but leave
the layout pass at the system position and rely on the order of a callback AppKit does not promise. 2 was not built: its draw runs inside
`super.setFrame` before the override can place, which is the deferred pass's measured draw count. After the change the host view's resize also
reads the insets with the buttons placed, so `onReplaced` is not needed from the anchor (and the geometry report must not run in a layout).

## 4. What was built

- `AppKitTitleBarPlacement.swift`: `LayoutAnchor`, a private invisible subview of the title-bar view (fills it by autoresizing, `hitTest` nil, not an
  accessibility element, sets `needsLayout` on each size change) whose `layout()` calls `place()` (`placeInLayout`). Installed with the frame
  observers (`observesFrames`), removed in `remove()`. `place()` keeps its equality guards and `isPlacing`. The deferred pass, the KVO and the
  notification backstop stay (a title change, a toolbar, key changes, full-screen exit report no layout).
- `update(height:leading:)` stores the new pair before restoring the system layout for a dropped field (the anchor places from the stored pair during that
  resize; before the change the "leading only" arm of `appKitTitleBarMetricsApplyPerFieldAndClear` read centre 34 again).

## 5. Tests and mutations

Two new tests in `AppKitAppShellTests.swift` (root 7248 tests in 79 suites after merging master (7246, record 396), 7244 before it):

- `appKitTitleBarButtonsAreAtTheirPlacementOnEveryFrameOfALiveResize`: 40 steps, bracketed by `willStartLiveResize` / `didEndLiveResize` and the host
  view's `viewWillStartLiveResize` / `viewDidEndLiveResize`; after every `setFrame(_:display: true)`, before any run-loop turn, each button's window
  frame (x, top-down centre y), the container's frame and the title-bar view's are the settled ones; a spy subview records layouts and draws.
- `appKitTitleBarPlacementWritesNothingWhenNothingChangedAndNothingWithoutMetrics`: with the frames right, forced layouts, display, `place()`,
  `schedule()` and an equal `setFrame` leave `writeCount` where it was while `placeCount` climbs; a hidden window with no metrics has no placement and
  no extra subview; metrics add exactly one, clearing removes it.

| Mutation | Reddened |
|---|---|
| anchor never installed (deferred pass only) | the live-resize test (both the post-`setFrame` reads and the spy) and the subview-count arm of the no-work test |
| anchor never removed | the no-work test (cleared arm) |
| the button write unguarded | the no-work test (`writeCount` climbs) |

Existing title-bar tests unchanged and green (the `AS-R` 6 test, `appKitTitleBarInsetsArePublishedAgainAfterTheReplacement`, now passes through the host's resize
reading the placed buttons as well). The first draft of the leading-only arm failing is the `update` ordering above.

## 6. Not verified

A real drag. The tests step `setFrame` on an off-screen window that is never key; AppKit's live-resize loop (event tracking, `viewWillStartLiveResize` from the
window server, the CA commit timing) was not run. Human check `TBH8`.
