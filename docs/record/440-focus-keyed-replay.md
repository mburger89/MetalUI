# 440: a retained occurrence replays while the focused element under it is the one it was made with (`RK-AQ`; class M, no divergence)

Branch `perf/focus-keyed-replay`, base master `26187430`. No public API, no divergence (243 live, next label unchanged). The Alloy fixture is copied from `origin/perf/fence-translation` (#456) byte for byte (`AlloyTranscriptFixture.swift`); the two copies reconcile at the later merge.

**Why.** Alloy's chat focuses its composer's `TextField`, and every `.equatable()` occurrence above it then missed prepaint and paint replay on every frame (the `SB-X` focus clause, applied at prepaint, at paint and at the store): headless, 222 misses per stream and 132 per 10-step scroll, 0 with nothing focused. The clause protects the focused element's own reads (the ring, caret and selection colour, `followExternalText`, the IME rect); the ancestors read nothing focus-related, they depend on focus only because they contain the leaf.

**What changed.**
- Focus is a decision input. `retainedFocus(under:)` is the focused element when it is the occurrence or under it; the ledger stores it at prepaint, the record at paint, and each replays only while the focus now is that id (`focusMoved`, trace `focus`). Hover, press and a selected `Text` keep the refusal (`retainedSubtreeHasPointerOrPress`). `refreshLedger` replaces a standing record's ledger whose `focusedUnder` differs.
- The focused leaf's `focusedElementProducedThisFrame` and `$focus` retention write are a ledger entry (`FocusCall.focused`), replayed under `allowedStateWrites`.
- Graft and capture skip a ledger or record made under a focus. A moved ledger that registered a text input's focus stop refuses `focusTextInput`.
- A paint record that cannot be stored under a focus (a blinking focused `CodeView`) backs the occurrence off 8 builds, doubling to 256 (limit 32).
- Verify mode compares the focused element after `resolveFocus`.

**Numbers (Alloy fixture, 420 x 600 at scale 2, graft off, debug build).**

| | master | here |
|---|---|---|
| quiet focused frame: misses / prepaint hits | 3 / 9 | 0 / 1 |
| focused stream step: prepaints / paints / hits | 18 / 22 / 9 | 12 / 15 / 10 (equals the unfocused step) |
| focused wheel step: prepaints / paints | 104 / 22 | 98 / 15 (equals the unfocused step) |
| steady focused frame, allocations | 19,805 | 14,960 (unfocused 14,273) |
| unfocused steady frame | 14,273 | 14,270 |
| blinking `CodeView` under three occurrences, 40 toggles: allocations / ledgers made | 35,588 / 0 | 25,261 / 3 |

Misses naming focus: 3 a frame on master, 0 here. The occurrences above the transcript still miss for `serial`, `observed` or `versions`, exactly as unfocused. The `CodeView` blink keeps its 120 `codeCaretBlink` ineligibles; the first, unbounded version made 120 ledgers and 38,828 allocations, which is why the backoff exists.

**Deviations from the plan.**
- A prepaint taint under focus (the first focused frame's plain `TextField` state write, `stateWrite`) does not back off: it held every ancestor plain for 8 frames after each click. Only a paint taint does.
- `aFocusedTextFieldInsideNestedEquatablesCopiesNoRows` is not unchanged: records exist under the focus now, so the first key's build fires the four sessions they armed and one more frame draws (all hits): 28 requests against 24, 35 captures skipped against 30, still 0 copied and 30 misses.
- `theFirstFrameAfterTypingStopsCopiesAndTheNextOneGrafts` moves one frame sooner (records made under the focus are valid again when it leaves). `aFocusedOrHoveredElementUnderTheOccurrenceRunsPrepaint` did not move.
- Eight steady-frame cost tests of a focused `CodeView` (listed in `RK-AQ`) read a hit where they read a miss, same requests: improved, not on the plan's list of moving tests.
- The record's paint-time focus lives on `ContentMemoStore.Entry.recordFocus`: a `RetainedRecord` field moved `aRecordThatNeverCrossesPaysNothing`'s pinned instance size (248).
- The Alloy-side trace partition (step 0) was not run: Alloy is another repository.

**Mutations.** Reddened: `focusMoved` forced false (`focusMovingBetweenTwoFieldsInOneOccurrenceRepaintsItOnce`, `aFocusedFieldInsideARetainedPanelMissesAndTypingWorks` (RW-J test 7), and a verify-mode trap `replay differs from a fresh run ... focusedUnder`), the `.focused` write not replayed (`aReplayedLedgerKeepsTheFocusSlotLive`), the capture skip removed (`aFocusedTextFieldInsideNestedEquatablesCopiesNoRows`), the backoff removed (`aFocusedCodeViewsBlinkFramesCostNoMoreThanToday`: ledgers and allocations), `focusTextInput` removed (`aMovedAncestorOfAHitTestDisabledFieldRefusesFocusTextInput`). **Not reddened, and why:** the prepaint comparing only the ledger's focus (`aFocusBoundaryChangeNeverRedoes`) is an equivalent mutant on this tree: a record whose paint cleared the request holds `nil`, the ledger of that frame `x`, and the frame that replays the ledger under the same request again finds paint agreeing (`nil`) with the record, so nothing is redone and the frame equals a fresh one; and the graft's `focusedUnder` check removed (`focusLeavingTheChainRepaintsOnceAndNeverRedoes`) is behind the capture skip and the current-focus refusal, which already keep a focus-made record from a graft, so the check is defence in depth. The plan's equivalent mutant (the produced flag not set at replay) is as documented: `resolveFocus` returns at `isFocusable` first and the both-equal rule prevents a replay with a non-focusable focused element.

**Carried.** Graft under a steady focus (the chain's build requests); hover keyed like focus (`pointerInLedger` with the pointer over the composer); a time-varying leaf as a live hole (code mode, 4,824 misses by design).

**Tests.** `FocusKeyedReplayTests` (12, one with two arms): `aFocusedComposersAncestorsReplayWhileFocusStays`, `aFocusedComposerCostsWhatAnUnfocusedOneCosts`, `noPrepaintMissNamesFocusWithThePointerAway`, `aTypedCharacterAppearsAndOnlyTheKeyFrameMisses`, `focusMovingBetweenTwoFieldsInOneOccurrenceRepaintsItOnce`, `focusLeavingTheChainRepaintsOnceAndNeverRedoes`, `aReplayedLedgerKeepsTheFocusSlotLive`, `aFocusBoundaryChangeNeverRedoes`, `aMovedAncestorOfAHitTestDisabledFieldRefusesFocusTextInput`, `aFocusedComposerIdlesWithNoFrame`, `aFocusedCodeViewsBlinkFramesCostNoMoreThanToday`, `theAlloyTranscriptEqualsAFreshWindowAtEveryStep`.
