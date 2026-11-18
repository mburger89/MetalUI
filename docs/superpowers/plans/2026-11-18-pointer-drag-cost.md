# Pointer drag frame cost (`FP-U`) Implementation Plan

> **For agentic workers:** carry the plan out task by task. Planned by Opus 2026-11-18 and checked against master `328ab5eb`.

**Goal:** A pointer drag that changes nothing a frame would show asks for no frame. A terminal selection drag goes from 1 build, 2 requests and 1 surface draw to 0 builds, 0 requests and 1 surface draw.

**Architecture:** Widen `FP-T`'s helper in `Window.swift` from plain moves to unclaimed drags and to the button arena's right and other drags. The helper's guards stay the same. One path, `.beginWindowDrag`, clears unobserved state, so it now dirties the window explicitly.

**Tech stack:** Swift 6.4, Swift Testing, `MetalUITesting` headless windows.

## Corrected cause

The terminal drag is **not** a claimed event. `dispatchGestures` returns `false` for `.mouseDown` and `.mouseDragged` (`IX-D` item 6), and `dispatchTextInput` declines it (the terminal's text target is `external`). It reaches the tail of `platformWindow.onInput` (Window.swift ~1478-1491). `pointerMoveChangesNothing` (~1519) accepts only `.mouseMoved`, so the tail calls `setNeedsRedraw()`.

"The window dirties after a claimed event" is wrong. Correct it in `TRM-BP` item 2, in `TRM-BD` item 8, and in the test comments.

The claimed stages keep their dirty mark, because it is load-bearing: they write window-owned or `withState` state that raises no dirty of its own. Those stages are the drag session, menus, popovers, the context menu, the drawn alert, `applyScroll`, text input, the value track and pinch.

## 1. The rule: `FP-U`

Append to `docs/superpowers/2026-11-07-frame-timing-decisions.md`, after `FP-T`:

`## FP-U: a pointer drag that changes nothing asks for no frame (record 386)`

1. **The rule.** `FP-T`'s test now also covers a drag: an unclaimed `.mouseDragged`, and a `.rightMouseDragged` or `.otherMouseDragged` that the button arena (`CI-F`) claims. Such an event does not call `setNeedsRedraw()` when all of these hold:
   - the pointer stays over the same topmost opaque hitbox, so `isHovered`, `pointerOwner` and the pressed look can't differ;
   - `StateTable.writeCount` is unchanged;
   - the tooltip tracker is `.idle`;
   - for the unclaimed path only, the window has no `onInput`.

   The gesture callbacks still run. What they change invalidates on its own: `@State`, `@GestureState`, bindings, observation, a surface trigger. This is SwiftUI's rule: a gesture redraws because state changed.
2. **Phases.**
   - A move: `FP-T`.
   - A drag (primary, secondary, other): `FP-U`.
   - These still dirty, unchanged:
     - down and up: `active`, focus, popover dismissal, clicks;
     - scroll;
     - `pointerExited`;
     - pinch;
     - every claimed stage.
3. **Self-dirtying paths.** `.beginWindowDrag` clears `active` and now asks for its frame itself. `.beginDrag` already does (`beginDragSession`).
4. **Limit.** A drag handler that changes only unobserved state no longer redraws, as in SwiftUI. Class M, no divergence.
5. **Cost.** A terminal selection drag event goes from 1 build, 2 requests and 1 surface draw to 0 builds, 0 requests and 1 surface draw.

Pinned by T1, T1b, T2, G1-G6 and R1-R5. Next unused id: `FP-V`.

## 2. Code changes (all in `Sources/MetalUI/Window.swift`)

1. **Rename `pointerMoveChangesNothing` to `pointerEventChangesNothing`:**

   ```swift
   private func pointerEventChangesNothing(_ event: InputEvent, from before: Point<Pixels>?, writesBefore: Int, checksOnInput: Bool) -> Bool
   ```

   - Take the position from `.mouseMoved(let m)`, `.mouseDragged(let m)`, `.rightMouseDragged(let m)` or `.otherMouseDragged(let m)`. Any other event returns `false`.
   - Keep the guards: `before` non-nil, `writeCount` unchanged, tooltip `.idle`, `if checksOnInput { onInput == nil }`, and the `topmostOpaqueHitbox` comparison.
   - The doc comment cites `FP-T` and `FP-U`.
2. **The tail.** Call it as `!handled && pointerEventChangesNothing(..., checksOnInput: true)`, which keeps today's `handled` semantics. The comment names `FP-U`.
3. **The pinch and button-arena stage (~1327).** Split it, keeping the order:
   - `if dispatchPinch(event) { setNeedsRedraw(); return true }`
   - `if dispatchButtonArena(event) { if !pointerEventChangesNothing(event, from: pointerBefore, writesBefore: writesBefore, checksOnInput: false) { setNeedsRedraw() }; return true }`

   Check that `pointerBefore` and `writesBefore` are already captured before this stage. If not, move their capture up.
4. **`runGestureCallbacks` `case .beginWindowDrag:` (~3683).** Add `setNeedsRedraw()` after `endPressForDrag()`, citing `FP-U` item 3.

There is no public API change and nothing platform-specific.

## 3. Audit (the only path that needs a new explicit dirty is `.beginWindowDrag`)

| Path | What it changes | Class |
|---|---|---|
| `updatePointerState` | `lastMousePosition`; `active` on down and up only | Covered by the hitbox check; down and up still dirty |
| `updateHover` (Hover.swift) | `onHover` callbacks | `@State` and observation dirty; `withState` trips `writeCount` |
| `trackTooltip` | tracker phase | `.idle` guard |
| alert, drag session, menus, popovers, context menu | window-owned sessions | Unchanged (claimed) |
| `applyScroll` | `withState` offsets | Unchanged |
| `dispatchPinch` | arena | Unchanged |
| `dispatchButtonArena` moves | `pendingContextMenu = nil` (not drawn), callbacks | Now spared |
| `dispatchTextInput` | `withState` edit state | Unchanged; pinned by R3 |
| `dispatchValueTrack` | binding write | Unchanged; pinned by R4 |
| `dispatchGestures` drags: DragGesture, `pointerInput`, taps, long press | user callbacks; `@GestureState` uses `table.write` | Spared; they self-dirty |
| SplitView divider, TabStrip, ColorPickerPanel, TerminalView | `@State` or surface | Spared; they self-dirty |
| `.beginDrag` (`beginDragSession`) | already calls `setNeedsRedraw()` | Pinned by R1 |
| `.beginWindowDrag` (`endPressForDrag`) | `active = nil`, unobserved | **Add `setNeedsRedraw()`**; R2 |
| Window `onInput` fallback | anything | Guarded by `onInput == nil` |

## 4. Tests

Rules for every count:
- Read it after `try await window.runUntilIdle()`, never after a fixed tick.
- Sum `frameWork` over frames, never `lastFrameWork`.
- Use `Modifiers.primary`.
- Send raw events (`window.send(.mouseDown/.mouseDragged/.mouseUp(...))`), not `TestWindow.drag`, which ticks between steps.

Each test's doc comment names its mutation.

### Terminal

- **T1:** rename `aSelectionDragCostsOneBuildAndRedrawsOnlyTheSelectedRow` (TerminalPointerModifierTests.swift) to `aSelectionDragIsSurfaceOnly`.
  - Per step: `resetFrameWork`, drag to `point(1, c)`, frame, `runUntilIdle`.
  - Expect `sum(builds) == 0`, `sum(elementRequests) == 0`, surface draws +1, and `statistics.lastRows == [1]`. Keep `steady == 2`.
  - Mutation: drop `.mouseDragged` from the helper.
- **T1b:** apply the same flip in `pointerCostsAreThoseOfAnyPointerEvent` (TerminalPointerSelectionTests.swift ~223-235).
  - Expect builds 0 and requests 0, read after `runUntilIdle`.
  - Fix its doc comment (~170-176), which says "dirties itself for every pointer event".
- **T2:** new test `aReportingSecondaryDragSendsBytesAndDrawsNoFrame`.
  - `feed("\u{1b}[?1002h")`, `.rightMouseDown` at `point(1,1)`, then `.rightMouseDragged` per cell.
  - Expect one more report in `log.inputs` per step, `framesDrawn` unchanged, builds 0.
  - Mutation: an unconditional dirty in the button-arena branch.

### Generic

New file `Tests/MetalUITestingTests/PointerDragFrameCostTests.swift`, modelled on `CodeViewPointerMoveCostTests.swift`.

- **G1 `aDragWhoseHandlerWritesStateRedrawsOncePerEvent`:**
  - Setup: `@State dx` written by `DragGesture(minimumDistance: 0).onChanged`, and an `.offset(x:)` marker that reads it.
  - Expect 1 build per drag step, and the last value built is the new `dx`.
  - Mutation: implement the skip by clearing `needsRedraw`.
- **G2 `aDragWhoseHandlerChangesNothingDrawsNoFrame`:**
  - Setup: `onChanged` bumps a plain class counter that no build reads.
  - Expect `!needsRedraw` right after the send, `framesDrawn` unchanged, builds 0, and the counter +1.
  - Mutation: the helper rejects `.mouseDragged`.
- **G3 `aDragOffAPressedButtonAndBackStillDraws`:**
  - Setup: a Button beside a Rectangle.
  - Expect a drag within the button to draw 0 frames, a drag off it to draw at least 1, and a drag back to draw at least 1.
  - Mutation: the hitbox comparison is replaced by `true`.
- **G4 `aSecondaryButtonDragFollowsTheSameRule`:**
  - Setup: `DragGesture(minimumDistance: 0, button: .secondary)`.
  - Expect a `@State` writer to cost 1 build per step, and a plain counter to cost 0 frames.
- **G5 `aDragInAWindowWithOnInputStillDraws`:**
  - Setup: G2 plus `onInput = { _ in false }`.
  - Expect `needsRedraw` after each drag.
  - Mutation: drop the `onInput` guard.
- **G6 `aDragOverAHelpedElementKeepsTheTooltipFrame`:**
  - Setup: a `.help` box.
  - Expect `needsRedraw` after an in-region drag.
  - Mutation: drop the `.idle` guard.

### Regression pins (same file)

- **R1 `aDraggableOpensItsSessionAndDrawsThePreviewWithinOneHitbox`:**
  - Setup: `.draggable("x")`; press, then drag 20 pt inside.
  - Expect `dragSession != nil` and the preview captured.
  - Mutation: delete `setNeedsRedraw()` in `beginDragSession`.
- **R2 `aWindowDragThatEndsThePressAsksForAFrame`:**
  - Setup: WindowDragHeadlessTests' `dragTree()`; press at (100,16), drag to (140,16).
  - Expect `windowDrags == 1`, `active == nil`, and `needsRedraw` right after the event.
  - Mutation: remove the new dirty.
- **R3 `aTextFieldSelectionDragStillDrawsEachStep`:**
  - Expect `framesDrawn` +1 per step and the selection to grow.
  - Mutation: apply the skip to the `dispatchTextInput` claim.
- **R4 `aSliderDragOverUnobservedStorageStillMovesTheThumb`:**
  - Setup: a `Binding(get:set:)` over a plain class.
  - Expect a frame per step and the thumb or AX value to follow.
  - Mutation: apply the skip to the value-track claim.
- **R5 `aWindowWithoutAPointerFeatureKeepsItsSteadyRequests`:**
  - Expect the steady `elementRequests` literal measured on master before the change to be unchanged.

### Existing suites

These must stay green without edits:
- `CodeViewPointerMoveCostTests`
- `DragAmbientFixture` users
- `FilletDragProfileTests`, `SplitViewTests`, `TabStripTests`, `GestureStateTests`, `DragPreviewTests`, `WindowDrag*`
- `HarnessWorkTests.aWarmDragLoopCountsLayoutWorkPerFrame`

**Triage:**
- A test that pinned a frame per drag that changed nothing a build reads: update its literal and cite `FP-U`.
- A visual that depends on unobserved state a gesture wrote: stop and report it, because the audit missed a path.

## 5. Docs

- **The `FP-U` ruling** (section 1).
- **`docs/rules/decision-prefixes.md`:** FP's next id becomes `FP-V`, and add an `FP-U` line.
- **`docs/rules/input-focus.md`:** after the `FP-T` paragraph, add one sentence: a drag that changes nothing asks for no frame (`FP-U`, record 386); gestures redraw through the state they write; a callback that changes window-owned state (`active`, a session) calls `setNeedsRedraw()` itself.
- **`docs/rules/terminal.md`:** a selection drag is surface-only, 0/0/1 (`FP-U`).
- **Terminal decisions:**
  - `TRM-BP` item 2: strike through, house style as at `TRM-BK` 6(c), adding "(fixed by `FP-U`, record 386: the drag was never claimed; `FP-T` spared only `.mouseMoved`)".
  - `TRM-BD` item 8: correct it the same way.
  - The next unused id stays `TRM-BQ`.
- **Record `docs/record/386-pointer-drag-cost.md`** (check the highest number first). It covers:
  - the corrected cause;
  - the rule and the audit;
  - before and after literals;
  - each test and its mutation;
  - the `.beginWindowDrag` addition.
  
  Add a row to `docs/record/README.md`. Don't edit old records.
- **`docs/divergences.md`:** nothing.

## 6. Risks

| Possible regression | Caught by |
|---|---|
| Stale hover highlight | G3, `FP-T` test 3 |
| Pressed state not shown or not cleared | G3, R2 |
| Scroll indicators | Unchanged path; `CodeViewPointerMoveCostTests` |
| Drag-and-drop preview not following | R1, `DragPreviewTests` |
| Text selection or slider thumb lagging | R3, R4 |
| Tooltip timer stalls | G6 |

**Rollback:** remove the three drag cases from the helper.

## 7. Verification

1. On master first: record T1's current literals and R5's steady literal.
2. Filtered run: `swift test --build-system native --filter 'PointerDragFrameCost|TerminalPointer|CodeViewPointerMoveCost|KeystrokeFrame|HarnessWork|DragAmbient|FilletDrag|WindowDrag|GestureState|SplitView|TabStrip|DragPreview'`
3. Full run: `swift build --build-system native --build-tests && swift test --build-system native --no-parallel`
4. Show each mutation red, then restore; `git status --short` must be clean.
5. Linux: the PR's Linux CI job.
