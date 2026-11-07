# Record 222: frame timing and signposts (Alloy gap G7)

Branch `feat/frame-signposts` (master `9116adff`). Rulings `FP-A`..`FP-H` in `docs/superpowers/2026-11-07-frame-timing-decisions.md` (new prefix; `FS-` was taken by the retained-translation rulings; next `FP-I`). Class `M`; no divergence added (209 live, next label 226). Guide `docs/frame-timing.md`.

## 1. What was built

`FrameTiming` (a ring of `FrameTimingSample`, `onFrame`, `onPresented`, optional `OSSignposter`), `Window.frameTiming`, the defaulted `WindowRenderer.setPresentationObserver(_:)`, Metal's `addPresentedHandler` path, the headless renderer's scripted display. Tests `Tests/MetalUITestingTests/FrameTimingTests.swift` (portable: macOS, Linux, Windows; the allocation pin is Darwin-only like `countAllocations`).

## 2. Deviations from the approved design

- **`Frame.swift` was edited** (a `timing` property and three one-line stamps): the phase boundaries live inside `Frame.renderOutsideDispatch`, and every non-editing alternative (hooking `GlyphAtlas.beginFrame`, `animationStore.transitions.afterLayout`) would have stamped by accident of another call's position.
- **`inputTimestamp` is not always the platform's**: a platform timestamp on a different clock (SDL, the harness) cannot be compared with `now()`, so it falls back to the receive time (`FP-G`); `inputReceived` is always kept.
- **A clean event is not an input** (`FP-G`): the design said "earliest input event handled since the previous frame"; a mouse move that dirtied nothing would otherwise stamp a later animation frame with seconds of "latency".
- **`presented` is delivered through a defaulted protocol method** (`FP-F`), not a stored property on the renderer (a protocol extension cannot hold state).

## 3. Mutations (each applied alone, `swift test --no-parallel --filter FrameTimingTests`, reverted)

See the table in section 4 once measured.

## 4. Results

Filled in at the end of the work (mutation table, counts, SDL and portable runs).
