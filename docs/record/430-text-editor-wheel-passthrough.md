# 430: a TextEditor passes a wheel it cannot use to the scroll view around it (`XS-V`)

Class `A`, no divergence row, no public API. Branch `fix/text-editor-wheel-passthrough`, base master `3de15d73`. Reported by Alloy: its Settings is a long `ScrollView` holding a `TextArea` (MetalUI's `TextEditor`); a user scrolling Settings got stuck when the field passed under the pointer.

## Root cause

`Window.dispatchScrollChain`'s multi-line arm (`TI-H`) claimed every vertical wheel at its cover and wrote `scrollY` clamped to `0...maxScrollY`, with room or not ("its edge chaining is not built", `XS-G`'s record). An editor whose lines fit has `maxScrollY == 0`, so the claim moved nothing and the outer scroller never saw the event. A trackpad scroll is latched on the cover (`IF-G`) and re-walks the same chain per event, so it was swallowed the same way, momentum included.

## What changed

The arm takes the wheel only while the editor has room in the wheel's direction (`scrollY < maxScrollY` growing, `scrollY > 0` otherwise), as a one-axis scroller does (`XS-F`, probes `N6b`, `N8`). Otherwise the chain continues to the next scroller. No focus gate (a vertical `TextField` has one, `VT-E`). Two `scrollY` reads per vertical wheel at an editor cover; no storage, closure or per-frame work.

- A gesture that began over an editor that fits goes to the outer scroller for its whole life. A gesture that began with room and reaches the end mid-gesture gives the outer the rest, as a nested `ScrollView` does (probe `N8b`). No probe measures an `NSTextView`, so AppKit's behaviour there is an assumption (human check `XSV1`); the brief's "stays on the editor" would be a new rule against `N8b`, so it was not built.
- `aTextEditorStillSwallowsTheWheel` (`VT-E`, M15) used a one-word editor, which has no room; it now uses 20 lines, so it still pins "an unfocused editor with room swallows".

## Tests

`TextEditorWheelPassthroughTests`: `W1` wheel over a fitting editor moves the outer; `W2` trackpad `.began`/`.changed`/`.ended` plus momentum does too; `W3` an editor with room keeps the wheel, passes it at its end and takes it back going up; `W4` the top edge (the outer is at 0 as well, nothing moves); `W5` mid-gesture end gives the outer the rest. Mutation (drop the room condition): W1, W2, W3 and W5 fail (5 issues); restored, all pass. The nested-scroller tests are untouched.

## Cost

No pin moved or raised (`ScrollAllocationChurnTests`, `ScrollOffsetPixelSnapTests`' idle pin are in the full run).
