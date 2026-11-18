# 386 - A pointer drag that changes nothing asks for no frame (`FP-U`)

Branch `perf/pointer-drag-cost` on master `328ab5eb`. Class M, no divergence, no public API (`Window.pointerEventChangesNothing` is `private`). Plan: `docs/superpowers/plans/2026-11-18-pointer-drag-cost.md`.

**The corrected cause.** `TRM-BP` (record 384) pinned a terminal selection drag event at 1 build, 2 element requests and 1 surface draw and blamed "a claimed pointer event dirties the window". The drag is not claimed: `dispatchGestures` returns `false` for `.mouseDown` and `.mouseDragged` (`IX-D` item 6) and `dispatchTextInput` declines it (the terminal's text target is external), so the event reaches the tail of `platformWindow.onInput`, where `FP-T`'s helper (`pointerMoveChangesNothing`) accepted only `.mouseMoved` and the tail called `setNeedsRedraw()`. `TRM-BP` item 2 and `TRM-BD` item 8 are struck and corrected.

**The rule.** The helper is renamed `pointerEventChangesNothing(_:from:writesBefore:checksOnInput:)` and also accepts an unclaimed `.mouseDragged` and the button arena's (`CI-F`) `.rightMouseDragged` and `.otherMouseDragged`; the guards are `FP-T`'s (same topmost opaque hitbox, `StateTable.writeCount` unchanged, tooltip `.idle`, and for the unclaimed tail no window `onInput`). The pinch and button-arena stage is split so only the arena's events use the helper (`checksOnInput: false`: a claimed event never reached `onInput`); a press, release or pinch still dirties. Every other claimed stage keeps its dirty, because it writes window-owned or `withState` state that raises no dirty of its own: the drag session, menus, popovers, the context menu, the drawn alert, `applyScroll`, text input, the value track and pinch.

**The audit** found one path that needs a new explicit dirty: `.beginWindowDrag` (`runGestureCallbacks`) calls `endPressForDrag`, which clears `active`, observed by nothing, so it now calls `setNeedsRedraw()` itself (`FP-U` item 3). `.beginDrag` already does (`beginDragSession`). `updatePointerState` (`active` changes only on down and up), `updateHover` (`@State` and observation dirty; `withState` trips `writeCount`), `trackTooltip` (the `.idle` guard), `dispatchGestures` drags (user callbacks; `@GestureState` writes through the table), and `dispatchButtonArena` moves (`pendingContextMenu = nil`, not drawn) are covered by the guards.

**Before and after (counted, `--build-system native --no-parallel`).**

| Quantity | Before (master `328ab5eb`) | After |
|---|---|---|
| Terminal selection drag event: builds / element requests / surface draws | 1 / 2 / 1 | 0 / 0 / 1 |
| Terminal selection drag event: rows redrawn | `[1]` | `[1]` |
| Steady rebuilt frame's element requests, terminal | 2 | 2 |
| Window with no terminal, steady frame's element requests (R5's chip window) | 6 | 6 |
| Drag event, handler writes a `@State` a build reads (G1) | 1 build | 1 build |
| Drag event, handler changes nothing a build reads (G2) | 1 frame, 1 build | 0 frames, 0 builds |
| Drag within a pressed `Button` (G3) | 1 frame | 0 frames |

**Tests and mutations** (each shown red against the committed code, then restored; `git status --short` clean).

| Test | Pins | Mutation shown red |
|---|---|---|
| T1 `aSelectionDragIsSurfaceOnly` | terminal drag 0 / 0 / 1, rows `[1]` | `.mouseDragged` dropped from the helper (M1) |
| T1b `pointerCostsAreThoseOfAnyPointerEvent` | the same, in the cost twin test | M1 |
| T2 `aReportingSecondaryDragSendsBytesAndAsksForNoBuild` | a reporting secondary drag asks for no build | unconditional dirty in the arena branch (M2) |
| G1 `aDragWhoseHandlerWritesStateRedrawsOncePerEvent` | a `@State` writer costs 1 build per event and shows the value | skip implemented by clearing `needsRedraw`, `writeCount` guard dropped (M3); R5 and R1 also red under it |
| G2 `aDragWhoseHandlerChangesNothingDrawsNoFrame` | 0 frames, 0 builds, window clean after the send | M1 |
| G3 `aDragOffAPressedButtonAndBackStillDraws` | off and back draw; within does not | hitbox comparison replaced by `true` (M4); also red under M1 |
| G4 `aSecondaryButtonDragFollowsTheSameRule` | arena drags: writer 1 build, counter 0 frames | M2 |
| G5 `aDragInAWindowWithOnInputStillDraws` | `onInput` keeps the frame | `onInput` guard dropped (M5) |
| G6 `aDragOverAHelpedElementKeepsTheTooltipFrame` | tooltip keeps the frame | `.idle` guard dropped (M6) |
| R1 `aDraggableOpensItsSessionAndDrawsThePreviewWithinOneHitbox` | session and preview frame | `setNeedsRedraw()` deleted in `beginDragSession` (M7) |
| R2 `aWindowDragThatEndsThePressAsksForAFrame` | `.beginWindowDrag` dirties | new dirty removed (M8) |
| R3 `aTextFieldSelectionDragStillDrawsEachStep` | one frame a step, selection grows | the skip on the `dispatchTextInput` claim with `writeCount` ignored (M9b). With the guard intact (M9) it stays green: the field's edit state is a `withState` write and the guard already sees it |
| R4 `aSliderDragOverUnobservedStorageStillMovesTheThumb` | a frame a step, thumb follows | the skip on the `dispatchValueTrack` claim (M10) |
| R5 `aWindowWithoutAPointerFeatureKeepsItsSteadyRequests` | steady 6 and 1 build with 6 requests per `@State`-writing drag event | a pin, no mutation of its own; red under M3 |

**One expectation of the plan did not hold.** T2 expected `framesDrawn` unchanged over a reporting terminal's secondary drag; the view draws its own surface-only frame per event (0 builds, 0 requests, `surfaceOnlyFrames` equals the frames drawn), so the test (renamed `aReportingSecondaryDragSendsBytesAndAsksForNoBuild`) pins 0 builds, 0 requests and every frame surface-only.

**Existing literals updated:** `HarnessInputTests.aDragDeliversStepsDraggedEventsEachWithAFrame` expected `steps` + 1 = 9 frames and now 2 (the press and the release; its handler writes only a log), per the plan's triage rule; `aSelectionDragCostsOneBuildAndRedrawsOnlyTheSelectedRow` is `aSelectionDragIsSurfaceOnly` (builds 0, requests 0), and `pointerCostsAreThoseOfAnyPointerEvent`'s drag loop (builds 0, requests 0), both citing `FP-U`. Every other existing test is unedited.

**Limit.** A drag handler that changes only unobserved state no longer redraws, as in SwiftUI (class M).

**Counts.** Root run, `--build-system native --no-parallel`: 7039 tests in 79 suites, green (master 6996 in 75 at record 379; the counts moved with other merges since, plus this branch's 12 new tests: 11 in `PointerDragFrameCostTests` and `aReportingSecondaryDragSendsBytesAndAsksForNoBuild`). Filtered run (`PointerDragFrameCost`, `TerminalPointer`, `CodeViewPointerMoveCost`, `KeystrokeFrame`, `HarnessWork`, `DragAmbient`, `FilletDrag`, `WindowDrag`, `GestureState`, `SplitView`, `TabStrip`, `DragPreview`, `HarnessInputTests`): 207 tests green. `aSelectionDragIsSurfaceOnly` failed in a filtered run that was not `--no-parallel` (shared `TerminalViewModel.latestForTesting`), green alone and serial.
