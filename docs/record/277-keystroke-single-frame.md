# 277. One frame per keystroke; `est>screen` from the next vsync (`FP-N`, `FP-O`)

Branch `perf/keyup-frame` (master `ddfc97bb`). Rulings `FP-N`, `FP-O`. Class `M`; no divergence.

## Finding

The Alloy trace showed a second frame, attributed to `key`, on the display-link tick after each keystroke's immediate frame. Cause: the window's input handler ends every event that no stage claimed with `setNeedsRedraw()`. AppKit delivers a typed character as committed text (`textInput`, drawn at once by `FP-M`) and then a `keyUp`; the unclaimed `keyUp` re-dirtied the clean window and the next tick drew an identical frame. The second frame changed no pixels, so it is removed.

## Change

1. `Window`'s input handler: an unclaimed `keyUp` does not call `setNeedsRedraw()` (`FP-N`). A claimed one (`onKeyPress(phases: .up)`, keymap, `onInput` true) does; state a handler changes dirties the window itself.
2. `FrameTiming.estimatedVsync` (`FP-O`): the reference tick is stepped back to the first vsync at or after the commit when it lies after it (an immediate frame is reported after later ticks moved the phase on); a phase more than one second from the commit, or no interval, gives `-`.

## Numbers (headless, 200 characters typed as committed text then release, immediate input on, one tick per character)

| Target | Frames per keystroke before | after |
|---|---|---|
| `TextField` | 2.0 (400 frames) | 1.0 (200) |
| `CodeView` | 2.0 (400 frames) | 1.0 (200) |

`est>screen`: before, a phase one to three intervals past the commit returned that later tick (k=1..3 gave 16.7, 33.3, 50 ms too late, the 21-32 ms of the trace); after, all give the first vsync after the commit (4 ms in the test).

## Tests and mutations

`KeystrokeFrameTests` (4) and `FrameTimingTests` `theVsyncEstimate...` (2). Each mutated and seen red: exemption removed (2.0 frames per keystroke; the clean-window test fails); step back removed (k=1..3 and the exact-hit case fail).
