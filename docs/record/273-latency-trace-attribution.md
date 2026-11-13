# 273. Re-entrant input attribution, trace summary (G34, `FP-K`)

Branch `fix/latency-trace-async-dirty` (master `227af741`). Ruling `FP-K`. Class `M`; no divergence.

After `FP-J` Alloy's trace had the header and no data line over about 600 keys posted with `CGEvent.postToPid`.

## What was checked

- `Window.swift:1064-1072`: `noteInput` then `defer { settleInput(dirtied: needsRedraw) }`.
- Text: `MetalHostView.keyDown` -> `inputContext.handleEvent` -> `insertText` -> `onInput(.textInput)` (`AppKitPlatform.swift:475`). `insertText` runs outside `onInput`, so there is no nesting; `dispatchTextInput` claims the event and calls `setNeedsRedraw()` before the handler returns, so the text path dirties synchronously, as in the harness. The leading hypothesis (asynchronous dirtying of a typed key) is therefore **not** the Alloy cause as far as source reading shows.
- Not reproduced on screen (no windows allowed in this run). Alloy's benchmark note column was empty in the runs on file, so whether its recorder held samples with an input kind is unconfirmed.

## Fixed

Re-entrant dispatch: an inner clean event replaced `candidate` and nulled it, so a dirtying outer event was dropped (`aReentrantDispatchDoesNotClobberTheOuterInput`; with the nesting guard removed it fails on kind and count). A late-claim heuristic for inputs that dirty the window after the handler was written and removed: the real text path dirties synchronously and the heuristic could attribute a timer frame to an input.

## Counters

`metalui-latency-summary written=N presentedNoInput=N dropped=N settledClean=N`, on demand (`writeTraceSummary()`) and every 100 presentation reports. For the next Alloy run: `written=0` with `presentedNoInput` large means frames present but carry no input kind; `dropped` large, the display reports nothing; no summary line at all means no presentation report reached `notePresented` (observer unbound or token mismatch), the remaining suspect.
