# 327 - The buffer lane of per-view CodeView selections: `CodeSelectionState` (`CV-AV`, `CV-AW`, `CV-AX`)

Branch `feat/codeview-selection-buffer` from master `fd0292ca`. Lane 2 of the work designed in `docs/superpowers/specs/2026-11-16-codeview-selection-state-design.md` (probes: record 325). Class M, no divergence. No view change: `Sources/MetalUI/Code` is untouched; lane 3 wires `CodeView` (`CV-AY`) and `CV-AZ` (marked text) stays provisional.

**What landed** (`Sources/MetalUICodeBuffer/CodeSelectionState.swift`, `CodeBuffer.swift`). `@MainActor @Observable public final class CodeSelectionState` in the `MetalUICodeBuffer` module (AlloyCore links it): `init(buffer:selections:)`, `buffer`, `selections` (get/set; a write ends undo coalescing), `primarySelection`, `revealSerial`, `select(_:reveal:)`, `replaceSelections(with:origin:)`, `replace(_:with:origin:)`, `transaction(_:)`, `undo()`, `redo()`. `CodeBuffer.selectionState` is the default state (a lazy property); the buffer's `selections`, `primarySelection`, `select`, `revealSerial` forward to it, and `replace`, `transaction`, `replaceSelections`, `undo`, `redo` run with the *acting* state (the one whose API call is running, else the default). The buffer holds every state weakly (like `CodeEditCursor`), sweeps dead ones in `trimLog`, and moves every live one in `applyEvent` (internal edits, undo/redo replays and `applyValidated`).

**Move rule as implemented** (offsets, edit `a..<b` replaced by `L` bytes):

| Selection of | Edit | Result |
|---|---|---|
| the acting state | any | the `CV-D` per-offset rule: sticky after `.typing`/`.paste` insertions, otherwise a caret at the point stays in front; inside a replaced span `a + min(o - a, L)` |
| any state, external edit | any | the same `CV-D` rule, never sticky (no acting state) |
| other state, caret or range start | insertion at it | after the insertion (`o + L`, whole range shifted) |
| other state, range | insertion at its end or later; edit wholly after | unchanged |
| other state | edit wholly before (incl. ending at its start) | shifted by `L - (b - a)` |
| other state, caret | strictly inside a deletion | `a` |
| other state, caret | strictly inside a replacement | `a + L` (the end) |
| other state, range | the edit overlaps its interior (inside, over, across an end) | a caret: `a` for a deletion, `a + L` otherwise |
| other state, several | any | range by range; carets that land together merge |

**Undo (`CV-AX`)**: one stack per buffer; a group records the acting state's selections (`state.transaction` the state's); `state.undo()`/`redo()` replay (other states move by `CV-AW`) then write the group's selections into the calling state. Coalescing: `openState` beside `openKind`; an edit by a different state ends the run, an explicit write on any state ends it, the buffer moving a state does not. Observation: a non-default state whose selections did not change is not mutated.

**Conflicts with the binding decisions** (existing tests are the pin, so the compatibility rule won):
- The default state is **always** mutated on an edit, moved or not (`versionAndSelectionsAreObservable` expects the buffer's `selections` to fire on an edit that does not move the caret). "Unmoved state isn't notified" holds for every other state.
- `CV-AW` says external edits use the non-acting rule; applied to the default state it would change today's single-view moves (a caret at an external insertion would jump after it). External edits therefore move every state by the `CV-D` rule. The one existing external test coincides with both rules (`5 + 3`).

**Tests** (`Tests/MetalUICodeBufferTests/SelectionStateTests.swift`, 24 tests, one a 23-row parameterised move table): default state equals the buffer selection and still wakes observers; independence; the move table; acting state sticky and replaced-span distance; undo and redo into the calling state; nothing to undo; no cross-state coalescing, an explicit write on any state; external edits; released states dropped (`liveStateCount`, `stateMoveCount` back to 1 per event); the one-state work guard; unmoved state not notified. Every existing buffer test passes unchanged. Mutations, each turned the suite red (two survived at first and got a test each: the registry sweep, now `registeredStateCount`, and the acting state's stickiness): a caret at an insertion staying in front; a replacement collapsing to its start; undo and redo writing into the default state; coalescing ignoring the state; only the acting state moving; always notifying; external edits by the non-acting rule; an explicit write not ending the run; a transaction recording the default state's selections; no sweep; acting not sticky.

**Bookkeeping.** `docs/rules/code-view.md` rule line, decision-prefixes CV row, README row, inventory family `code-selection-state` (M), `docs/api-overview.md`.
