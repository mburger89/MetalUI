# 360 - What a pointer move that changes nothing costs (`FP-T`)

Branch `perf/codeview-pointer-move` from master `7d4d38ff`. Alloy's fold-gutter work: every pointer move over a `CodeView` cost 1 frame and 2 plain state writes, "attributed to the scroll chrome". Class M, no divergence.

## Measured cause

A write tracer in `StateTable.withState` (temporary, removed) over four moves on a gutter-on `CodeView`: every move drew a frame, and the two writes were `Frame.registerHandlers` (the `$focus` retention slot of a focusable) and `Frame.emitAXNode` (the `$ax` slot), both taken by every frame the view is in. The scroll chrome wrote nothing on a move: its writers are the wheel (`Window.scroll`, `CodeView`'s wheel handler) and the compared prepaint write-back. The frame came from the tail of `Window`'s input handler, which called `setNeedsRedraw()` for every event no stage claimed (only an unclaimed key release was exempt, `FP-N`). So the fix is the frame, not the writes.

## Fix

`Window.pointerMoveChangesNothing`: an unclaimed `.mouseMoved` skips the dirty when the pointer stays over the same topmost opaque hitbox, the event moved `StateTable.writeCount` not at all, the tooltip tracker is idle and the window has no `onInput`. A first draft that skipped on the hitbox alone broke the text hover: its input side writes the hover track with `withState`, which raises no dirty, and the next frame starts the delay (test 4 went red: no `.active`). The write count is what keeps that frame.

## Literals (`CodeViewPointerMoveCostTests`)

Before / after, four moves within the text, four within the gutter, scrollbars faded: 4 frames and 8 plain writes each / 0 and 0. Scrollbars shown: the fade is an animation that draws its own frames, so the moved window equals a ticked twin (the moves add none). `ScrollView` and `List`: 0 / 0 (ScrollView measured 4 frames before in the faded state). A move onto a `Button` beside the view, back, and the wheel's reveal each cost at least a frame. Entering a text-hover target writes the track and draws; moves within the grapheme cost 0; `.active` arrives after the delay. A pending tooltip keeps its frames and shows. The fade is identical to a twin with no moves, step by step on the simulated clock.

## Mutations (each red, restored from a copy)

The helper returning `false` (tests 1, 2, 4), the hitbox comparison replaced by `true` (test 3), the write-count term dropped (test 4), the `.idle` guard dropped (test 5). The fade test (6) has no mutation of its own: it pins that a move stamps no scroll time, which no edit short of writing one into the move path reddens. `noHoverHandlerNoStateWrites` (`CodeViewTextHoverTests`) moved 8 -> 4: its `blank` point lies below the view, so two of its four moves cross the view's edge.

## State-write guard

`everyStateWriteSiteIsClassified` is unchanged: no `withState` site was added, moved or converted.
