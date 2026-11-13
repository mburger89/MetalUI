# 274. Latency experiment switches and the presentedTime finding (G34, `FP-L`)

Branch `perf/latency-experiments` (master `cc55b92b`). Ruling `FP-L`. Class `M`; no divergence.

Alloy (release, on screen, 60 Hz, about 600 keys): about 38 ms median end to end, about 12 ms from input to commit, about 26 ms from commit to visible, and `MTLDrawable.presentedTime` 0 for every frame.

## presentedTime

- Registration is right: `drawable.addPresentedHandler` before `commandBuffer.present(drawable)` (`MetalLayerSurface.swift`), read inside the handler, as Apple's example does. Apple documents 0 only for a drawable that was not presented or whose frame was dropped (macOS 10.15.4+).
- Searched Apple documentation, developer forums, MoltenVK, Flutter's embedder and wgpu-hal: nothing explains an always-zero value for a windowed `CAMetalLayer` on macOS. Not reproduced here (no on-screen window). **Cause unconfirmed; no fix was found, so none is claimed.**
- Added an honest estimate instead, in its own trace column: `est>screen`, commit to the first vsync at or after it, from `tickTarget` (or the last one seen). It never fills `presented`.

## Switches (package, read once, one check each)

`METALUI_EXP_DRAWABLES=2`, `METALUI_EXP_LATE_DRAWABLE=1`, `METALUI_EXP_IMMEDIATE_INPUT=1`, `METALUI_EXP_TRANSACTION=1`; the trace header ends `exp=...`. Mechanisms and risks are in `docs/frame-timing.md`; the ruling is `FP-L`.

## Found on the way

An idle tick left its stamp pending, so a frame drawn outside a tick claimed a stale tick. `discardTick()` on the idle path fixes it (`immediateInputDrawsInsideTheHandlerAndTheTickDrawsNothingMore` fails without it).

## Pinned (fail-before)

With the immediate draw disabled the immediate test fails on the frame count; with the nested guard removed the nested test overflows the stack; with the late acquire skipped the late test fails on three expectations; with `discardTick` removed the immediate test fails on `tickStart`.

## Not done

No on-screen run: whether any switch lowers the 38 ms is for the Alloy bench.
