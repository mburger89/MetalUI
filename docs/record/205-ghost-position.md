# Record 205: a removal ghost's position, and empty content parks (round 4 item R4-3 PR B1)

Branch `feat/r4-3-ghost-position`, from master `fa4dbb6f` (PR A, #200, merged). Decisions: `docs/superpowers/2026-11-03-default-transition-decisions.md` (`XF-F`, `XF-G`). Human checks: none added (the group `XF` belongs with PR B2, which adds the fade). Divergences: **none added or retired** (208 live, next label 215); row 98's MetalUI cell notes the annotated ghost. Class `A`: a rule SwiftUI was measured to follow (`XF10`, `XF2zb`, `XF2zc`, `T1e2`, record 204). **No default fade, no unannotated ghost, no public declaration**: only an annotated `.transition` removal changes, and the closeout inventory needed no row.

## 1. What changed

- `Frame`: `pendingGhostAnchors`, `ghostAnchorSeen` (a frame-local `Set`, filled by `recordElementBounds` only while a ghost with no container exists), `hasGhostAnchors` (one flag, read by each paint hook), `paintAnchoredGhosts(at:)`. `Frame.render` resolves the anchors after prepaint and before paint, and draws a ghost into the root's run through its own hook.
- `TransitionStore`: `Ghost.anchor` and `Ghost.drawn` (in the struct, so the redo checkpoint carries them), `resolveAnchors(seen:)`, `paintGhosts(anchoredAt:frame:)`, `lastFrameUnanchoredGhosts`, `hasAnchoredGhosts`, `ghostAnchors`; `paintGhosts(_:)` now draws only what no hook drew and counts it. **Empty parking:** the ghost guard drops `!previous.captures.isEmpty` and `previous.surfaceRect` is optional (a zero rect).
- Hook sites (each behind `hasGhostAnchors`): `Element.paintGroup` before `paint(...)` when the element is not a `StyledElement`; `paintDecorationUncaptured`'s content (every `StyledElement` site, after its own fill); `ModifiedContent.paintLayer`'s innermost `inside()`; `AnyElement`'s group entry; the root in `Frame.render`. A hook that draws taints the paint recorders (`ghostInRun`).
- Docs: `Transition.swift`'s doc comment, `docs/rules/identity-state.md`, `GL-D` item 3's comment on `forgetCapturedPrimitives`, `XF-F`/`XF-G`, `docs/migration.md`, row 98's cell, `Tasks.md`.
- Tests: `GhostPositionTests` (16), and three rows in `RetainedSubtreeInternalTests`'s Frame table.

## 2. The plan's stop conditions

1. **At-rest counters and allocation pins did not move.** The unfiltered run is green apart from one table that had to learn the three new `Frame` properties (section 5). A steady tree with a retained panel and two static occurrences, before (master) and after, frames with no ghost: `grafts=3 hits=3 prepaint hits=3 redos=0 requests=1 paints=1` in all three post-fade frames, identical.
2. **A graft decision with no paint record does not redo.** `RetainedGraft.graftRecord` requires `entry.record` (the paint record) and its ledger, so an occurrence whose paint could not record is **not grafted**: it builds, prepaints and paints fresh. A redo (`RK-C`) comes only from a replayed prepaint meeting a differing paint-time ambient; a missing record replays nothing. Measured over a fade (fixture of `aGhostInARetainedOccurrenceIsNotReplayedFrozen`, an `.equatable()` panel holding the `if` beside two static `.equatable()` occurrences), frames after the flip frame and the one that follows:

   | | master | this PR |
   |---|---|---|
   | grafts | 3 | 2 (the siblings) |
   | `retainedIneligibleReasons` | empty | `ghostInRun: 1` |
   | element requests / paints | 1 / 1 | 4 / 5 |
   | redos | 0 | 0 |

   The cost is the panel's own build, prepaint and paint per frame for the fade's length, then the next unchanged frame replays again (`grafts=3, requests=1` after the ghost lands). It is bounded by the animation and counted by name.
3. **`lastFrameUnanchoredGhosts` is 0 in an ordinary tree.** A temporary `print` in `paintGhosts` over the whole unfiltered default-build run (3 267 + the other suites) fired once, in `aHiddenContainersGhostIsCountedUnanchored`, the separating arm of the counter.
4. **No verify-mode trap** (section 6).

## 3. Tests that flipped

**None.** `TransitionTests`, `MatchedGeometryTests`, `LifecycleTests` and every other existing suite read the same values: their assertions read accents by count and by colour, not by index across a sibling, and no existing test removed empty annotated content. The plan's expectation that `accents(...)` by index might flip did not occur. The one red was `everyFrameChannelIsClassified` (a new stored property needs a row), fixed by three rows.

## 4. Mutations

Applied from the committed tree with `scratchpad/mut/run.py`, restored with `git checkout -- Sources`, filter `GhostPositionTests`, default build system. Names are the tests that reddened.

| mutation (spelling) | reddened |
|---|---|
| MB1a no anchored draw (every ghost drawn after the root, as before) | `aGhostAboveASiblingDropsBelowIt`, `aGhostBelowASiblingStaysBelowIt`, `aThirdLeafStaysAboveTheGhost`, `aNestedGhostIsFirstInItsOwnContainer`, `aVStackGhostIsFirst`, `aVStackGhostLastMovesToTheFront`, `aGhostSitsAboveItsContainersOwnFill`, `aComponentAndASlotAreNotContainers`, `anErasedContainersGhostIsAnchoredAtItsEntry`, `aRedoReturnsAnchors`, `aGhostInARetainedOccurrenceIsNotReplayedFrozen`, `aGhostsAncestorsAreSeenUnderPrepaintReplay` |
| MB1b draw in place (before the first later sibling of the slot, by positional index; at the end of the window when none) | `aGhostAboveASiblingDropsBelowIt`, `aThirdLeafStaysAboveTheGhost`, `aVStackGhostLastMovesToTheFront`, `aGhostSitsAboveItsContainersOwnFill`, `aComponentAndASlotAreNotContainers`, `anErasedContainersGhostIsAnchoredAtItsEntry`, `aRedoReturnsAnchors`, `aGhostInARetainedOccurrenceIsNotReplayedFrozen`, `aGhostsAncestorsAreSeenUnderPrepaintReplay`. **`aGhostBelowASiblingStaysBelowIt` and `aNestedGhostIsFirstInItsOwnContainer` stay green, as they must**: with the leaver first in its container, in place and container-first read the same |
| MB1c anchor to the outermost seen ancestor (no `break`) | `aGhostAboveASiblingDropsBelowIt`, `aGhostBelowASiblingStaysBelowIt`, `aThirdLeafStaysAboveTheGhost`, `aNestedGhostIsFirstInItsOwnContainer` (`[120, 50, 30, 40, 20]`), `aGhostSitsAboveItsContainersOwnFill`, `aComponentAndASlotAreNotContainers`, `anErasedContainersGhostIsAnchoredAtItsEntry`, `aHiddenContainersGhostIsCountedUnanchored`, the two retained tests |
| MB1d the `paintGroup` hook for a styled element too (guard removed) | `aGhostSitsAboveItsContainersOwnFill` (the member arm; **first fixture was green**: the fill was a modifier layer's and the ghost's anchor the `Stack` inside it; re-built with the `Stack`'s own `.background`) |
| MB1e a conditional slot's parent accepted as a container without being prepainted (the component) | `aComponentAndASlotAreNotContainers` only. **Spelled differently from the plan** ("record bounds in `Component`"): `ComponentLayout` keeps no id to record |
| MB1f anchor insertions | **not applicable: no code path touches an insertion**; `anInsertionStaysInPlace` is a control, green before and after |
| MB1g the `ghostInRun` taint removed | `aGhostInARetainedOccurrenceIsNotReplayedFrozen`, `aGhostsAncestorsAreSeenUnderPrepaintReplay` |
| MB1h resolve right after `afterLayout`, before prepaint (nothing seen) | the same twelve as MB1a |
| MB1i the empty-capture and missing-rect guards restored | `anEmptyAnnotatedRemovalParksItsDisappearance`, `aHiddenContainersGhostIsCountedUnanchored` |
| MB1j `rollbackBuild` without `ghosts = saved.ghosts` | `aRedoReturnsAnchors`. **Spelled differently from the plan** (anchor omitted from `Checkpoint`): the anchor and the per-frame draw mark are fields of the `Ghost` the checkpoint already copies, so the mutation removes the restore |
| MB1k the hook removed from `AnyElement`'s group entry | `anErasedContainersGhostIsAnchoredAtItsEntry` |
| MB1l the hook removed from `paintDecoration`'s content | `aGhostSitsAboveItsContainersOwnFill` |
| MB1n the root hook removed | `aVStackGhostIsFirst`, `aVStackGhostLastMovesToTheFront` |
| MB1o the hook removed from `Element.paintGroup` | the eight tests whose container is a group member |
| MB1p `recordElementBounds` stops noting ids | the same twelve as MB1a |
| **MB1m the hook removed from `ModifiedContent`'s innermost layer** | **nothing: a green mutant, reported not fixed.** No fixture reaches the site: a proposal chain over a conditional traps on its one-node rule (`a native outer modifier must wrap exactly one native layout node`), a chain over a component whose only content is the conditional lays out no inner layer when it is absent (the ghost anchors at the member, `aModifiedComponentsGhostStaysInItsMembersRun`), and a legacy chain over `OptionalGroup` has no `.width`/`.padding` spelling that compiles. The site stays as `MC-B` requires of every hook added to the group defaults; the rule in `identity-state.md` names it |

## 5. What the plan did not say

- **The root and the erased entry are hook sites**; the plan named three. The root is a container (`recordElementBounds(rootID)`) and is not painted through `paintGroup`; `AnyElement` records its position's id and paints the wrapped element at another.
- **`paintDecoration` takes the hook, not `paintDecorationBody`**: three call sites of the body pass an empty `content` for an escaped fill or border and must not draw.
- **A modifier layer's fill is not the container's.** `Stack { ... }.frame(...).background(.x)` is a `ModifiedContent` whose outermost layer carries the fill and whose content is the `Stack`; the ghost anchors at the `Stack` (a group member) and so sits above the layer's fill and the `Stack`'s own; only `Stack { ... }.background(.x)` puts the fill on the container.
- **A retained panel that holds a ghost rebuilds each frame**, section 2. The plan predicted "no paint record while a ghost lives"; it is also not grafted.
- **The prepaint-replay claim is exercised weakly.** The frame that makes a ghost is the animation's first, and `retainedEntryRefusal` refuses every occurrence under a transaction, so no replay stands in that frame; `aGhostsAncestorsAreSeenUnderPrepaintReplay` pins that siblings replay in the following frames and the anchor is found. MB1h reddens it through the anchor, not through a replay.
- **Unmeasured, stated:** the look in a real window; a modifier chain between the container and the conditional (MetalUI's rule: the nearest prepainted ancestor); an erased container whose wrapped element is a `StyledElement` draws the ghost below that element's own fill; popovers and a `Deferred` (a ghost is drawn in the run of the container that contains the position, never in a portal).

## 6. Counts and checks

`swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel`, unfiltered, 2026-11-03 (the desktop was shared): **`Test run with 5066 tests in 14 suites passed after 275.817 seconds`** (0 failures; master's 5 050 + the 16 of `GhostPositionTests`); `FR-J no-argument frame: succeeded=true deprecations=2` (guards ran). Verify modes, filter record 201's plus `GhostPosition|TransitionTests|MatchedGeometry` under `--build-system native --no-parallel`: `METALUI_VERIFY_RETAINED=1` **504 tests in 9 suites passed (74.355 s)**; `METALUI_VERIFY_LAYOUT_MEMO=1` **504 tests in 9 suites passed (97.314 s)**; `METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500` passed (15.895 s). The earlier default-build run that found the classification table (3 267 tests in the root suite) was the only red.

`zsh docs/probes/record-05-check.sh`, `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. The counts line of `CLAUDE.md` is not replaced; `divergences.md`'s counts did not move (208 live, next 215), so `CLAUDE.md` and `AGENTS.md` are untouched.
