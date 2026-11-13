# 275. Immediate input is the macOS default, paced; the no-gain switches are removed (G34, `FP-M`)

Branch `perf/immediate-input-default` (master `ac4bd366`). Ruling `FP-M`. Class `M`; no divergence (a pacing detail, not observable against SwiftUI).

## A/B (Alloy editor, release, real window, 60 Hz, screen-capture keystroke to visible, about 200 keys per arm, two alternating rounds)

| Arm | Median ms | p95 ms |
|---|---|---|
| baseline | 37.6 / 39.0 | 48 / 51 |
| `METALUI_EXP_DRAWABLES=2` | 36.4 / 37.1 | |
| `METALUI_EXP_LATE_DRAWABLE=1` | 38.4 / 38.6 | |
| `METALUI_EXP_TRANSACTION=1` | 37.5 / 37.7 | |
| `METALUI_EXP_IMMEDIATE_INPUT=1` | 16.4 / 16.2 | 23.7 / 23.8 |
| immediate + drawables 2 + late drawable | 18.1 / 16.2 | |

## Done

- Immediate input is the default on the AppKit platform (`App(device:)`); SDL keeps the tick path; `METALUI_IMMEDIATE_INPUT=1|0` overrides on any platform. `TestWindow` stays tick-driven (`Window.drawsImmediatelyOnInput` is set by `App.openWindow` only), so no existing test changed behaviour.
- Pacing: an immediate frame only when the last frame (tick or immediate) was committed at least one refresh interval ago; the interval is the smallest display-link tick gap of 2 to 50 ms, 1/60 s until known. Otherwise the event dirties the window and the tick draws it.
- Removed: `METALUI_EXP_DRAWABLES`, `_LATE_DRAWABLE`, `_TRANSACTION`, `LatencyExperiments`, `LateDrawableWindowRenderer`, `ExperimentalRenderSurface`/`didCommit`, `lateDrawableAcquired`, the headless renderer's deferred-drawable hooks. `discardTick` kept.
- Trace: header `immediate=default|on|off` (was `exp=`); a zero presentation report writes the input's line (`commit>screen`, `total` as `-`, `est>screen` filled) and counts in `dropped` and `written`.

## Pinned (fail-before)

With the interval check removed the pacing and composition tests fail; with the commit stamp removed the same; with `.textComposition` removed the composition test fails; with `hasActiveAnimations` removed the animation test fails; with the `isDrawingFrame` guard removed the nested test overflows the stack; with `discardTick` removed the immediate test fails on `tickStart`; with the idle `setDisplayLinkPaused(true)` removed the idle-cost test fails; with the immediate draw leaving the window dirty the no-double-draw and idle tests fail; with the learned interval ignored the 120 Hz test fails; with the zero-report trace write gated on a time the zero-report test fails.

## Not done

No on-screen run here (key repeat on a real window is for the Alloy bench).
