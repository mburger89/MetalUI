# Record 207: the leaver moves as it fades (round 4 item R4-3 PR C)

Branch `feat/r4-3-leaver-moves`, from `feat/r4-3-default-fade` (PR B2, #202, CI blocked, not merged). Decisions: `docs/superpowers/2026-11-03-default-transition-decisions.md` (`XF-M`; `XF-K` replaced). Human checks: `XF6` (**not run**), MG1 and MG6 reworded. Divergences: **none added or retired**, row 897 **narrowed** in place with its residues named (208 live, next label 215 unchanged). Class `A`. **No shader, renderer or `replay.hlsl` change**: `RenderEffect` already applies a `.translate` atom (`Transition.swift:264`), the ghost's atoms are `[.opacity, .translate]`. No public declaration.

## 1. What changed

- `MatchedGeometryStore.afterLayout`: the `transitions.handOver` call is gone; a new loop over records claimed last frame and not now computes, for a leaver whose properties contain `.position`, that has a `displayed` rect and whose group has a current source, the delta between the anchor points (default centre) of the source's laid-out rect and of the leaver's `displayed` rect, and calls `TransitionStore.leaverMoves`. It runs whether or not a handoff or flight happened (S12).
- `TransitionStore.leaverMoves` (replaces `handOver`): an annotated leaver's standing ghost (`old.transitionKey`) gains `.translate(sizeX: 0, sizeY: 0, x: dx, y: dy)` when its atoms contain `.opacity`; otherwise the leaver's sequence range is carved out of every default ghost holding it into a ghost of its own (key `.child(of: leaverPosition, at: 0, name: "$matched-leaver")`, atoms `[.opacity, .translate]`, the donor's animation/start/activeness), the donors' `exempt` gains the leaver's position (its `onDisappear` parks on the new ghost). `Ghost.atoms` became `var`; `Ghost.carvedFrom` added so `advanceDefaultUnits` removes the leaver ghosts with the unit's ghost on re-insertion. The newcomer's default insertion is **no longer dropped** on a flight.
- `Lifecycle.parkedOn` (internal, test read). Docs: `XF-M`, row 897, `MG-E` item 3 amended, `identity-state.md`, migration, human checks, README, `decision-prefixes.md`, `Tasks.md` (left unticked), `matchedGeometryEffect` doc comment.

## 2. Differences from the plan

- `dropDefaultInsertion` does not exist; the equivalent was the insertion-dropping loop at the end of `handOver` (B2). Removed.
- "Carve-and-ghost": B2 carved only when a flight started; now the carve happens whenever the leaver moves (zero move: no carve, `aLeaverAtTheSourcesCentreKeepsItsUnitsGhost`).
- MC1 was spelled "origin delta instead of centre delta" (no full-frame map exists: the leaver is translated only). MC4 spelled "append the move to the donor ghost, no ghost of its own".
- Not done: S1's bitmap does not distinguish the anchor position (stated in row 897); an annotated `.alpha` leaver does not move (plan said opacity).
- Added beyond the plan: re-insertion cleanup (`carvedFrom`), parking exemption, the zero-move guard, the replay pin.

## 3. The item to check first: replay

**A leaver whose last paint was a replay hands nothing over and does not move.** `displayed` is written only in `beginPaint`, `sequences` only in the live paint. An `.equatable()` occurrence with a matched group is built every frame but its paint is replayed after a few steady frames; the record then has `displayed == nil` and the handoff guard skips. Measured (`aLeaverInAReplayedOccurrenceHandsNothingOverToday`): six steady frames then a flip: flights 0, ghosts 1; retention off, or one steady frame: flights 1, ghosts 2. Same flights 0 on the head of B2 with this PR's `Sources/` stashed. **Existing bug, reported, not fixed; pinned wrong on purpose.** `aFlightInsideRetainedOccurrencesLeavesTheStillSiblingAlone` passes only because it ticks three steady frames.

## 4. Tests that flipped

| test | before | after |
|---|---|---|
| `aNewcomerFliesFromTheLeaversFrameToItsOwn`, `propertiesSelectWhichPartOfTheFrameIsHandedOver`, `anAnchorPicksTheCornerThatIsHandedOver`, `onlyAMatchingSourceLeaverHandsItsFrameOver` (last arm), `aFlightInterruptedByAnotherSwapStartsWhereTheViewWasDrawn` | `one(frame)` read the single accent rect | **red on first run; expected values unchanged**, the reading helper `one` now takes the newcomer from the two rects (last drawn; first for the B to A swap, `newcomerIsLast: false`) |
| `aHandedOverLeaverDrawsNothingAndItsNewcomerIsOpaque` (`DefaultTransitionTests`) | one opaque rect | **deleted**, replaced by `aLeaverMovesToTheSourceAsItFades` and `theNewcomerFadesWhileItFlies` (leaver alpha 0.5 at (112.5, 127.5, 50x30), newcomer alpha 0.5 at (100, 120, 75x45) at 0.5 of 1 s) |

Nothing outside `MatchedGeometryTests`/`DefaultTransitionTests` flipped in the filtered run; the unfiltered result is in section 6.

## 5. Mutations

Applied with `scratchpad/mutc/run.py` from the committed tree (restored with `git checkout -- Sources`), filter `MatchedGeometryTests|DefaultTransitionTests|TransitionTests|LifecycleTests|GhostPositionTests`.

| mutation | reddened |
|---|---|
| MC1 origin delta, not centre | `aLeaverMovesToTheSourceAsItFades`, `aMultiMemberUnitMovesOnlyTheMatchedMember`, `aNonSourceLeaverMovesToo`, `aSizeOnlyLeaverStays`, `anAnnotatedLeaverMovesOnlyWhenItFades` |
| MC2 ignore `properties` | `aSizeOnlyLeaverStays` |
| MC3 source leavers only | `aNonSourceLeaverMovesToo` |
| MC3b a missing source falls back to any record | `noSourceNoMotion` |
| MC4 translate the unit's ghost, no ghost of its own | 9: `aLeaverMovesToTheSourceAsItFades`, `aMultiMemberUnitMovesOnlyTheMatchedMember`, `aMovingLeaverStillParksItsDisappearAndLeavesTwoGhosts`, `reinsertingTheUnitRemovesTheLeaversGhost`, `theNewcomerFadesWhileItFlies` and 4 more |
| MC5 drop the newcomer's default insertion on a flight (B2's) | `theNewcomerFadesWhileItFlies` |
| MC6 the move never handed to the store | 8, first `aLeaverMovesToTheSourceAsItFades`, `aNonSourceLeaverMovesToo`, `anAnnotatedLeaverMovesOnlyWhenItFades` |
| MC7 donor does not exempt the leaver | `aMovingLeaverStillParksItsDisappearAndLeavesTwoGhosts` (**green until `parkedOn` was added**: the first run reddened nothing) |
| MC8 leaver ghost outlives its unit | `reinsertingTheUnitRemovesTheLeaversGhost`, `aFlightInterruptedByAnotherSwapStartsWhereTheViewWasDrawn` |
| MC9 `displayed` never written | 16, incl. `aLeaverMovesToTheSourceAsItFades`, `aFlightKeepsTheDisplayLinkAwakeThenLeavesNothing` |
| MC10 annotated ghost gets no atom | `anAnnotatedLeaverMovesOnlyWhenItFades` |
| MC11 atom appended without the opacity check | `anAnnotatedLeaverMovesOnlyWhenItFades` |
| MC12 captures not removed from the donor | 10, incl. `aLeaverMovesToTheSourceAsItFades`, `aMultiMemberUnitMovesOnlyTheMatchedMember` |
| MC13 zero move still carves | `aLeaverAtTheSourcesCentreKeepsItsUnitsGhost` (**green until that test was added**) |

No mutant is green after the added pins.

## 6. Counts and checks

Steady frame (`aSteadyFrameCapturesAndOpensNothing`, `anEquatableOccurrenceWithAnIfStillGrafts`, unchanged and green): allocations 455, `lastFrameCapturedPrimitives` 0, grafts 4, hits 4, prepaint hits 4, requests 1, prepaints 2 — before and after (at rest `afterLayout` adds one dictionary lookup per matched record of last frame, no allocation, and nothing for a tree without a matched group).

`swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel`, unfiltered, 2026-11-04: **`Test run with 5107 tests in 14 suites passed after 283.510 seconds`** (5096 + 12 new - 1 deleted); `FR-J no-argument frame: succeeded=true deprecations=2`. **The first unfiltered run after the clean read one failure, `anUnannotatedInsertionAndRemovalFadeByDefault` (`TransitionTests.swift:464`, the removal ghost alpha), and the identical rerun, plus three reruns of `MatchedGeometryTests|TransitionTests|DefaultTransitionTests`, passed**: an order-dependent flake not explained (record 206 saw the same test read one issue in its first default-build run); reported, not fixed. `METALUI_VERIFY_RETAINED=1`: `5107 tests in 14 suites passed after 276.324 seconds`; `METALUI_VERIFY_LAYOUT_MEMO=1`: `5107 tests in 14 suites passed after 327.312 seconds`; `METALUI_RUN_100K_LIST_TEST=1 ... aListsWorkIsTheSameFor100kRowsAsFor500`: `1 test in 1 suite passed after 15.769 seconds`.

**Not run:** `Backends/SDL`, Linux and Windows CI; pixels and every look (`XF6`, MG1); a real backing scale; S1's curve beyond the linear readings of S12 (red moves linearly with the ramp, consistent with one curve).
