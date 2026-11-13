# 268. Input-to-present latency trace (Alloy gap G34, `FP-I`)

Branch `research/input-latency` (master `e6875f34`). Ruling `FP-I` in `docs/superpowers/2026-11-07-frame-timing-decisions.md`. Class `M`; no divergence. Alloy measures about 38 ms key to screen at 60 Hz (Zed about 50 ms); cutting per-frame CPU by 65% did not move it, so the latency is pacing-bound. Nothing was run on a display in this session: **every number below is a prediction until the Alloy run.**

## The path (macOS)

1. `MetalHostView.keyDown(with:)` (`AppKitPlatform.swift` ~420) calls `onInput`; `Window`'s handler (`Window.swift` ~1066) dispatches, writes state and ends in `setNeedsRedraw()`, which sets `needsRedraw` and un-pauses the link. **No frame is built in the handler.**
2. `startDisplayLink` (`AppKitPlatform.swift` ~1212) is `NSView.displayLink` (a `CADisplayLink` on the main run loop, `.common`; no thread hop). The tick closure (`Window.swift` ~1360) advances gestures and calls `drawFrameIfNeeded()`. An idle window pauses the link; resuming still waits for the next vsync tick.
3. `drawFrameIfNeeded` acquires the drawable first (`renderer.beginFrame()` -> `MetalLayerSurface.nextFrame` -> `nextDrawable()`, ~33, blocking), then builds, then `finishFrame` encodes, `commandBuffer.present(drawable)` (~59) and commits.
4. `MetalLayerSurface` sets pixel format, sRGB, `isOpaque = false`, `framebufferOnly = true`; the rest is default: `maximumDrawableCount` 3, `displaySyncEnabled` true, `presentsWithTransaction` false, `allowsNextDrawableTimeout` true, no `present(afterMinimumDuration:)`.

## Frame count (60 Hz, one key, predicted)

Tick wait 0 to 1 interval (mean 0.5, about 8 ms); `nextDrawable()` returns at once unless the queue of three is full (then up to 1 interval); build and GPU 1 to 4 ms; present at the next vsync (about 1 interval). About 1.7 intervals, 28 ms, against 38 ms measured: the remaining 10 ms is probably queue depth or a blocking `nextDrawable()`, which the trace separates.

## Ranked candidates (untried)

1. `maximumDrawableCount = 2`: 0 to 16 ms when the queue is full; risk: more blocking, a late GPU frame drops a frame.
2. Acquire the drawable after build and paint: up to 1 interval when `nextDrawable()` stalls; needs `beginFrame()` split into scale-factor query and late acquire.
3. Draw immediately on input when idle (link paused, nothing in flight): about 8 ms mean, up to 16; risk: extra frames, a pacing stutter near vsync, power in bursts; must coalesce with an in-flight frame.
4. `present(afterMinimumDuration:)`: pacing only, not latency. `presentsWithTransaction` stays off (adds latency; only for live-resize sync).

If `drawable` reads about 0 and `commit>screen` about one interval, 1 and 2 are not the cause and 3 is the remaining lever.

## The trace

`METALUI_LATENCY_TRACE=1` (stderr) or `=<path>` (appended): a header, then one line per presented input-caused frame with per-stage milliseconds from `NSEvent.timestamp`, the total and the total in refresh intervals; columns and stamps in `FP-I`. New `FrameTimingSample` fields `tickStart`, `tickTarget`, `drawableAcquired`, derived `inputToTick`, `drawableWait`. Tests: `aKeyThenATickStampsTheTickAndTheDrawableInOrder`, `theLatencyTraceWritesAHeaderThenOneLinePerPresentedInputFrame`.
