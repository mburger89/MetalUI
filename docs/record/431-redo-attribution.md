# 431: what a redo costs and why it happens (`RK-AP`; attribution, a trace, and one lever measured and not landed)

Class `M`, no divergence, no public API. Branch `perf/redo-attribution`, base master `e051f257`. **Evidence plus a trace; no behaviour changed.** Alloy's streamed transcript (30 deltas, `METALUI_TRACE_RETAINED=1`) showed 203 prepaint misses tagged `quarantine`, 8 left paint-translation refusals (`maskCrossingChanged` 5, `innerScope` 3) and 140 element requests a delta. The hypothesis under test: each refusal on a grafted row causes a redo, and each redo a long quarantine of the row and its descendants (`RK-D` item 3, `RK-AN`), so the 203 follow from about 8 refusals.

## The trace (landed)

A redo had no line naming its cause. `Frame.requestRedo(_:site:phase:)` now prints, under `METALUI_TRACE_RETAINED=1` only,

- `retained redo requested <path> at <graftedPrepaint|paintPlain|paintRecord> because prepaint [<guard names, note>] paint [<refusal | translation refused: <reason> | miss [<reasons>]>] grafted= replayed=`;
- `retained redo quarantine <path> for <n> builds until build <b> exponent <e> scoped=<bool>` from `noteRedo`;
- `quarantinedBy: self until build <b>` (or the scope's path) on every `retained prepaint miss` line that says `quarantine`.

`RetainedPhase.paintNote` is written only while `RetainedTrace.active`; the lines sit inside `emit`'s autoclosure. `theRedoLinesAreBuiltOnlyWhileSomethingListens` pins `linesBuilt` and `pathsBuilt` at 0 over 40 redoing words. Nothing is stored per frame.

## Attribution: the chrome transcript (`ChromeTranscriptFixture`), 30 words

Two redos in 30 words (three in 40), and **neither is a paint-translation refusal**. Both are `graftedPrepaint`: a grafted occurrence whose prepaint decision could not replay.

| Step | Occurrence that asked | Site | Cause named | Builds quarantined |
|---|---|---|---|---|
| 7 | row 42's chrome (a row with a button, cut by the viewport edge) | graftedPrepaint | prepaint `translationRefused: hitboxClipped` (the button's hitbox is cut by the rounded clip, which a move cannot re-derive) | 8, entry and scope |
| 7 | the streaming row's second paragraph | graftedPrepaint | prepaint `ledgerKey.rects, interior, ambient.clip, ambient.offset`: the row's own clip grew with the streamed text, so the key is no shift of the ledger's | 8, entry and scope |
| 22 | row 45's chrome | graftedPrepaint | `hitboxClipped` | 8, entry and scope |
| 22 | the streaming row's second paragraph | graftedPrepaint | the same key mismatch | 8, entry and scope |

The 44 `quarantine` prepaint misses of the 30 words are held 12 by the step-7 redo (until build 27) and 32 by the step-22 redo (until build 42) (`quarantinedBy`); **every one** is held by these four entries or their scopes, none by another cause. (Rows far from the viewport edge are not in it: only the two cut rows and the streaming row's paragraph ever fail.) The chrome transcript's 76 quarantine misses in 40 words are three redos.

So the second half of the hypothesis holds (every quarantine miss is a consequence of a redo, 12 to 32 for each) and the first half does not: the redos here are a hitbox clip and a clip-and-offset ledger mismatch, both **prepaint** refusals that the paint-translation counters (`maskCrossingChanged`, `innerScope`) do not see. `noteTranslationRefused` counts `hitboxClipped` under its own name; a reader looking only at the paint refusals would miss it. The same fixture with a content-shaped button (`RAShapedRow`) shows the paint side: 3 redo frames in 40 words, causes `prepaint [translationRefused: hitboxShape]` and `prepaint [recordCannotMove] paint [paint translation refused: innerScope]` (the paragraph's rounded scope, which the add cannot move).

### The other buckets

In the chrome fixture every non-quarantine miss is under the streaming row: `[observed, serial]` (30) and `[serial]` (29) on its text and its first paragraph, `[noRecord]`/`[scopedRedo, noRecord, observed]` (2 each) on the row rebuilt in the redo, and for paint `[observed, serial, key.interior, key.shapeInterior]` (8) and `[serial, key.interior, key.shapeInterior]` (7): the streaming text's own layout changes by a line. All of these are the rebuild the stream asks for. The fixture has no `[noLedger, observed]` and no `key.nodeCount` bucket, so they are explained from the code, not reproduced: `noLedger` is a record that holds no prepaint ledger (`PrepaintInvalidation.names`: `hasRecord` and not `hasLedger`; the prepaint window was tainted or refused, so nothing was kept to replay) and `observed` an observed property that fired; `key.nodeCount` is the occurrence's layout node count changing. An occurrence on the path from the streaming leaf to the scroller meets all of them every delta by construction (the 145 a bucket over 30 deltas is about 5 a delta, the depth of that path). **Unverified against Alloy itself**: whether the 145 are only that path needs the same trace taken in Alloy with the new lines, which this record makes possible.

## One lever, measured, not landed

Candidate (b): a redo whose every request was a geometry refusal (the prepaint found every conjunct but the geometry holding, or the paint decision was `valid` with a key that is no shift) quarantines the entry, and its scope, for **one build** the first time (`8 << exponent` ever after, the exponent growing as ever, so a parked row's schedule is 1, 16, 32 ... 256 against 8, 16, 32 ... 256). Measured in the fixtures, 40 words (diff kept outside the repo):

| | requests | prepaints | quarantine misses | redos | allocations a frame (G51, 12 frames) | G51 requests |
|---|---|---|---|---|---|---|
| master | 638 | 852 | 76 | 3 | 161,070 | 150 |
| one build | 537 (-16 %) | 722 (-15 %) | 37 | 5 | 161,015 | 136 |
| two builds | 580 | 777 | 54 | 5 | | |
| four builds | 649 | 864 | 81 | 5 | | |
| entry only, one build | 533 | 718 | 19 | 5 | | |

With the content-shaped button every row refuses every move: master 1946 requests in 40 words and redos in frames [7, 16, 29], one build 979 and [7, 15, 22, 29, 36], never two frames running (the backoff holds). Verify mode and the equality with a fresh frame were not the obstacle; the frames compared equal.

**Not landed, and why.** `aRedoDoesNotCascadeIntoTheRowsDescendants` (`ScopedRedoTests`) pins the chrome transcript at **at most 3 redos in 40 words**; the lever makes it 5, so it needs that pin moved **up** while the requests, prepaints and quarantine misses it protects fall by 16 %, 15 % and 51 %. The rule is that no pin moves up, so the lever stays measured, not landed, for the owner of that rule to decide: either the pin is re-read as what it guards (no redo in two frames running, and the cost) or the lever is dropped. Candidate (a), making `maskCrossingChanged` and `innerScope` translate, would not have helped this fixture: no redo here is a paint refusal.

## Tests (`RedoAttributionTests`, 4) and their mutations

| Test | Mutation that reddens it |
|---|---|
| `everyRedoNamesItsCauseAndItsQuarantine` | the `requestRedo` line removed; the cause left empty; `quarantineOwner` answering `none` |
| `theRedoLinesAreBuiltOnlyWhileSomethingListens` | the line built outside `emit`'s autoclosure |
| `theChromeTranscriptRedoesOnlyForGeometry` | a redo of another kind on the transcript |
| `aRowThatAlwaysRefusesNamesItsCausesAndRedoesNoMoreOftenThanTheBackoffAllows` | a cause left off the line; the quarantine off |
