# 289. Per-frame GPU time in the latency trace (`FP-P`)

Branch `feat/trace-gpu-time` (master `0a20962b`). Ruling `FP-P`. Class `M`; no divergence.

## Why

Alloy wants the cost of backdrop blur (glass). The trace had commit and presentation but no GPU time.

## Change

1. `FrameTimingSample.gpuNanos` and a `gpu` column, last of the trace's `ms:` group; summary gains `gpuMissing=N`.
2. `WindowRenderer.setGPUTimeObserver(_:) -> Bool` (defaulted, `false`); `MetalWindowRenderer` adds one completed handler per frame, only while an observer is set, reading `gpuEndTime - gpuStartTime` and hopping to the main actor under the frame token. `Window` installs and removes it with the `FrameTiming`.
3. Late times: the line is written at presentation; with no GPU time yet it is held and written by `noteGPU` on arrival (older held lines first), or flushed with `-` when a later frame is presented. Frame order is kept; `gpuMissing` counts the `-` lines of a renderer that reports GPU time. Simplest correct choice: no second line per frame, no unbounded wait (one frame).
4. One command buffer per window frame on Metal, so no summing. SDL: `-`; SDL_GPU exposes no cheap timing, not added.
5. Headless: `reportsGPUTime` and `deliverGPUTimes(nanos:)` script it.

## Tests

`FrameTimingGPUTests` (real Metal device): a rendered frame gets `gpuNanos > 0` and a `gpu` value; no completion handler with no timing (`gpuCompletionHandlersInstalled`). `FrameTimingTests`: GPU before presentation, after it, and never; `-` on a renderer with none; format tests updated. Each mutated once: handler never installed, installed unconditionally, flush removed.
