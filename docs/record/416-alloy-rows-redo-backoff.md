# 416: why Alloy's transcript rows still rebuild after #429 (`G49-B`, attribution only)

Class `M`, no code, no divergence. Branch `perf/g49b-alloy-rows`, base master `5af26f94` (#429 merged). **No fix is landed**: the exact-looking one failed the suite for reasons below, and each is a latent issue the backoff hides.

## The report

On master Alloy's `TranscriptRowRerunTests.measureStreamingRows` read 423, 430, 461 element requests and 448, 455, 487 prepaints a delta (489 and 515 before #429), `BlockChrome` bodies 4.4 to 4.9 a delta.

## Attribution (Alloy at 3aa0691 against this base, the test edited locally to print each delta's `FrameWork`)

Reproduced exactly: 423.3 requests, 448.1 prepaints, `BlockChrome` 4.43. The per-delta lines:

- `backoff=1` in deltas 0 to 23, then `req=98 backoff=0 grafts=31..36` in 24 to 29. **The rows graft (98 requests for the screen); the window is in the redo backoff for 24 of 30 deltas.** `redo=1` at deltas 6 and 15 re-arm the nine-build window; where a redo lands in it depends on which frame each delta's wrap and the observation hop fall in, which is why the runs differ (the number of redos is the same, the phase is not).
- Every redo has the same first-attempt line for a settled row (`tool0`, `m3#0`, `m6#0`, the permission card ...): `retained prepaint miss …/named(tool0)/… reasons=[recordCannotMove] frame: grafted=true`. `recordCannotMove` (`RetainedPrepaint.swift`) is the occurrence's paint record being unable to follow this frame's scroll move, with `retained paint translation refused … maskStraddlesEntryClip` (a row's rounded chrome, `BlockChrome`'s `.background(tint).cornerRadius(8)`, straddling the viewport edge: the cut of a moved mask is not the moved cut) or `inexactTranslation` (a fractional device-pixel move). A grafted occurrence has no element layout to prepaint, so `requestRedo` abandons the frame and `noteRedo` suspends prepaint replay **and grafting** for the whole window for nine builds. The bottom-anchored stream moves the rows by a few points every frame, a row near the edge cannot translate, and each redo starts the nine builds again before they end.
- A second mechanism inside the first: the redo quarantines the failing entry only, and a row's descendants (`AssistantText`, `MarkdownText`, the paragraph) are separate `.equatable()` occurrences that graft in the next frame and fail the same way one nesting level down: a redo a frame for 18 frames when the backoff is removed.
- Ruled out: the HSplitView chrome, the pending permission card, the 4 pt stripe, the island clip (the 6 `stateWrite` ineligibilities a frame are identical before and after and cost nothing), the observable collapse bindings (a row that reads one is evaluated, not ineligible), hash or timing order (the variance is the backoff phase above).

The throw-away fixture (about 9 visible rows with a rounded tinted chrome per row, nested `.equatable()` paragraphs, a button, the stripe and the island's `clipShape`, streaming one word a frame under `defaultScrollAnchor(.bottom)`) reproduces the regime: `redo=1 backoff=1 grafts=0 req=69` for 27 of 30 frames against 14 quiet.

## What was tried

1. `requestRedo(_:windowWide: false)` for a grafted occurrence's own failure: quarantine its entry, keep the window's replay on, and no grafting under a quarantined occurrence. Alloy: **423 to 268 requests, 448 to 282 prepaints a delta**, fixture 57 to 37.
2. A targeted rebuild (only the quarantined entries off the graft path, the rest as in the first attempt): **162 requests, 142 prepaints** (3 runs, 161.9, 162.3, 161.9). It is **not exact**: the first attempt writes state (the scroller's anchor and clamp write-back, a lazy container's `LazyOrigin`) that the rollback does not cover, so a replayed neighbour holds results made against the old state: `aMirroredScrollersGrowing…` showed the lazy window stale (glyph counts 20 against 36).
3. With 1 alone (a whole-frame redo, no backoff) the suite is red in three places that the backoff hides: `aZoomedNodeIsHitWhereItIsDrawn` (glyphs differ in the frame after a redo), the mirrored lazy window (same stale cells), and the `BackgroundProminenceTests` and two `FrameWork` steady-count pins; `everyFrameChannelIsClassified` wants the new `Frame` fields. The first three are a replayed frame **after a redo frame** differing from a fresh one, so the nine-build backoff is doing a second job (letting the atlas, the lazy windows' convergence frames and the anchor state settle) beside the one it documents (`RK-D`).

The experiment is kept as `g49b-experiment-full.patch` in the session scratchpad only; it is not a candidate.

## What a fix needs

- **A real rollback of what the abandoned attempt wrote** (the `StateTable` writes of prepaint: scroll anchor and clamp write-back, `LazyOrigin`, the glyph atlas's per-frame state), or a build that does not write before the frame is accepted. Then a targeted rebuild is exact and the 162 above is available. That is a change to the redo contract (`RK-M`), not to the replay key.
- **Or avoid the redo**: decide at graft time (build) that an occurrence whose last record could not move should not graft this frame. The shift is not known at build, so this needs a prediction (a scroller that moved last frame, the occurrence's last refusal) and is a heuristic, not exact; a wrong guess costs one redo.
- **Or make the move exact**: `maskStraddlesEntryClip` and `inexactTranslation` are the refusals. A moved mask whose cut is re-derived (the cut of the moved rect against the clip, as `FS-M` does for rects) or glyph runs re-keyed at fractional offsets would let the rows translate, and no redo would be asked. That is `FS-` work and the larger of the three.
- **Found, separate:** the registered element bounds of a frame that was redone are 10 points (the stack's spacing) from a fresh frame's while scene, hitboxes, tallies and Tab order are equal, with the whole-frame redo as well (record 414 step 3). The abandoned attempt's anchor adjustment is seen again by the redo; same family as the rollback above.

## Alloy's side

Nothing wrong in Alloy's shape: the rows are memoised correctly (`ChatBlockView`, `AssistantText`, `MarkdownText` 1.0 a delta), and the rounded chrome per row is what makes a row's record unable to move at the viewport edge. Dropping the rounded `BlockChrome` background would stop the `maskStraddlesEntryClip` refusals (the `inexactTranslation` ones remain while a line height is fractional), at a visual cost.
