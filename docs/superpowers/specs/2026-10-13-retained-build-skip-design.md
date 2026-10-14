# Retained build skip (C14b-2) — design

Status: **DESIGN, reviewed (RK-M..RK-Q: redo checkpoint and replay-off, verify by double build, handler test, derived figures withdrawn)** (2026-10-13, base `fb9a7e42`). Rulings `RK-A`…`RK-L`, lane 1's `RK-R`…`RK-V` (and `RK-W` for its readings) in
[`../2026-10-13-retained-build-skip-decisions.md`](../2026-10-13-retained-build-skip-decisions.md). Continues
[`2026-10-13-retained-subtrees-design.md`](2026-10-13-retained-subtrees-design.md) (§9 and §10 are as built by record §109 §13).
No public API, no SwiftUI-visible behaviour, no divergence (labels 405–414 unused), `Backends/SDL` and every platform seam untouched.

## 0. Summary

1. **Measured first** (`RK-A`): a graft of an occurrence's layout rows costs 13 % of its build (9.7 against 72.5 µs, 27 nodes), about
   0.19 against 1.4 ms per bracket drag frame. The graft is worth building.
2. **The graft forces prepaint replay** (`RK-B`): a skipped build leaves no element payload (its ids are a dead generation), so a
   grafted occurrence replays prepaint *and* paint. Two parts are independently landable (prepaint replay, the redo); two are not
   (graft, journal). Order: **M1** prepaint replay + redo, **M2** graft + journal, **M3** translated replay.
3. **The paint-only ambient** that stopped lane 1 (`SB-AA`) is handled optimistically and checked exactly at paint; a mismatch is a
   **counted redo before adoption**, backed off 8 frames window-wide and doubling per entry (`RK-C`, `RK-D`).
4. **Ceiling** -28 % of a bracket drag frame (1.7 of 6.0 ms), refutation at -15 %; MetalCreator's pan/zoom/orbit frames are
   **not** expected to drop under 16.67 ms from this item alone (`RK-L`).

## 1. Inventory (what the item touches; read before editing)

| area | file | what is there at `fb9a7e42` |
|---|---|---|
| decision, key, recorder, replay | `Sources/MetalUI/RetainedSubtree.swift` (623 lines) | `RetainedBuildWindow` (journals `markJournal` range, time notes), `RetainedPhase`, `retainedPaintDecision`, `ReplayKey`/`AmbientKey`, `replayPaint`, ledger snapshots |
| occurrence | `Sources/MetalUI/EquatableComponent.swift` | `requestGroupLayout` (memo, build window, `markPlacementRoot`), `prepaintGroup` (always runs), `paintGroup` (hit/plain/record) |
| memo entries | `Sources/MetalUI/ContentMemo.swift` | `Entry` (`record`, three `RetainedSession`s, `touched`), `materialize`, `endFrame` sweeps untouched entries (a skipped nested occurrence would be swept: `RK-F`) |
| component payload | `Sources/MetalUI/Component.swift` (`ComponentLayout`, `ComponentPrepaint`, `finishComponent`) | payload in one heap box (`PE-J`) |
| layout storage | `Sources/MetalUILayout/LayoutTree.swift` | SoA: `childLists`, `layouts`, `measuredWidths`; dictionaries `nativeNodes`, `leafKeys`, `spacerAxes`, `nativeParents`, grid marks; `placementRoots`; `appendNode` is the only registration check |
| state sweep | `Sources/MetalUI/StateTable.swift` | `marked`, `producedSlots`, `namedPositions`, `loopExtents`, `windowedParents`, `departedNames`, `markJournal`, `entryVersion` |
| frame | `Sources/MetalUI/Frame.swift` | `hitboxes`, `focusRegistry` registration, `axEmissions`, tallies; `render` ends in `sweep()` |
| window | `Sources/MetalUI/Window.swift` `buildAndAdoptFrame` | builds one `Frame`, takes the parked transaction, hands `scrollRequests`; adoption and `drainLifecycle` after |
| measurement | `Tests/MetalUITestingTests/BracketFixture.swift`, `docs/probes/perf-baselines.sh bracket`, `docs/probes/retained-build-skip/` | the fixture; the timing harness; the graft probe |

## 2. Mechanism

**M1 — prepaint replay and the redo (lane 1).** (a) `RetainedBuild` keeps, per occurrence, a **prepaint record** beside the paint
record: the slice of `Frame.hitboxes` the occurrence's prepaint appended (indices bracketed around `component.prepaintGroup`), the
focus registrations, `axEmissions`/`axNodes`/`accessibilityPressOnly`, the tally deltas, `contextMenuRecords` (`RK-E`). (b)
`EquatableComponent.prepaintGroup` decides replay-or-run at prepaint from rects and prepaint ambient (`RK-C`) and, on replay, skips
`component.prepaintGroup` and appends the record in order; the returned `ComponentPrepaint` carries a marker with the record so paint
knows prepaint did not run. (c) `paintGroup`'s lane 1 decision stays; for a prepaint-replayed occurrence a **paint key mismatch** (the
paint-only ambient differs, or a ledger fault) cannot paint: it sets `frame.redoRequest` and returns; `Window.buildAndAdoptFrame`
re-runs the build with those entries disabled (`RK-D`). (d) The prepaint decision is *always* followed by a paint decision with the
same key, so the two share `ReplayKey` (the geometry and prepaint-visible ambient parts are checked at prepaint, the paint-only parts
at paint). Backoff, quarantine and the counters are in `RK-D`/`RK-K`.

**M2 — graft and journal (lane 2).** (a) `LayoutSegment` (`MetalUILayout`, `package`): the row range of an occurrence
(`[lo, hi)` in node index, contiguous because `finishComponent` is post-order inside the component), the five side tables' rows
for the range, signatures, grid marks, and the top-level ids' offsets; captured at the end of a *recording* build next to
`markPlacementRoot`. `LayoutTree.graft(_:) -> [LayoutNodeID]` appends the rows with an index shift under the current generation and
returns the new top-level ids, one pass, no closure copies beyond a retain. (b) `StateTable.BuildJournal` captures the build
window's delta of every sweep-visible channel (`RK-F`); `StateTable.reapply(_:)` replays it through the table's own mutators. (c)
`EquatableComponent.requestGroupLayout`: after `enterComponent` and the memo hit, if the occurrence has a valid record whose
build-visible conditions hold (`RK-C` list), it **skips `finishComponent`**: grafts, reapplies the journal, touches nested memo entries,
marks the placement roots, counts, and returns `ComponentLayout` with a `nil` payload and a `RetainedGraft` marker. (d)
Prepaint and paint of a grafted occurrence are the M1 replays; M1's mismatch redo is the only repair.

**M3 — translated replay (lane 1, after M1).** `RK-G`'s gate; the record stores its origin, bounds, the multiples-of-2⁻⁶ check and
the clip containment; the replay adds the device translation to scene `x/y`, hitbox and AX rects. Layout of a moved subtree is still
placed fresh (the placement memo misses on origin, `SB-AD`).

## 3. Interaction rulings (all of C14b's stand; the additions)

* Identity (`ID-C`, `ID-R`, `noteNamed`, `theSevenRetentionSlotsAreMutuallyDistinct`): the journal reapplies marks through the table's
  funnels; a graft adds no slot and no id level; test `aGraftedFrameKeepsTheStateTableSweepsExact`.
* Lifecycle (`LC-`): presence is membership in a *build*; a grafted subtree's scopes are journalled as touches so `onAppear`/`onDisappear`
  do not fire spuriously and a removal still disappears them; an abandoned (redo) frame feeds nothing to the store.
* Animation: a live animation inside the subtree taints the record (`SB-S`, unchanged); one outside changes only ambient/transaction,
  which is the redo case.
* Focus, hit testing, accessibility: replayed in recorded order from the same lists; the one ranking `topmostHitbox` is not touched.
* Gesture arena, presentations, `Deferred`, popovers, surfaces, backdrops, shadow cache, `List` windowing: ineligible or untouched exactly
  as `SB-J`/`SB-Y` (a `List` and `ScrollView` stay `retainedIneligible`; C14b-3).
* Stack budget: the new per-entry state lives in `ContentMemoStore.Entry` (heap); `ComponentLayout`'s payload becomes optional inside the
  existing heap box; `DecorationExtras` is not touched; `everyProductionTreeBuildsOnAOneMegabyteThread` re-run.

## 4. Files and lanes (two; the agents run serially)

**Lane 1 (M1, M3):** `Sources/MetalUI/RetainedSubtree.swift`, `Frame.swift` (ledger slice brackets, `redoRequest`), `Window.swift`
(redo), `EquatableComponent.swift` (prepaint branch), `Component.swift` (`ComponentPrepaint` marker), `FrameWork` (counters),
`Tests/MetalUITestingTests/` (new `RetainedPrepaintTests.swift`, `RetainedRedoTests.swift`, `TranslatedReplayTests.swift`, baseline
literals), `docs/divergences.md` untouched. **Lane 2 (M2):** `Sources/MetalUILayout/LayoutTree.swift` (+ a new `LayoutSegment.swift`),
`Sources/MetalUI/StateTable.swift`, `ContentMemo.swift`, then — after lane 1 — the graft branch in `EquatableComponent.swift` and
`ComponentLayout`; `Tests/MetalUILayoutTests/` for the kernel's graft tests, `Tests/MetalUITestingTests/RetainedGraftTests.swift`.
Public additions: `FrameWork`'s counters only (doc comments, `closeout-inventory-map.tsv` rows, census re-recorded). Record
`docs/record/110-retained-build-skip.md` and the CLAUDE.md rule in the Record phase.

## 5. Tests (name — red before — the mutation that must redden it)

Every red line is the read value on the stub/old behaviour; every mutation is run on the committed tree, full unfiltered suite, the
reddened tests named in the record (`docs/practices/verifying-tests-can-fail.md`).

**Lane 1**
1. `theBracketNodeDragIsCountedAtFb9a7e42` (step 0, literals incl. `elementRequests`, `elementPrepaints`, `elementPaints`, hits, content evaluations, measures, `placeGlyphs`, raster, upload) — red before: the new counter fields absent; passes at the stub after literals taken; mutation: any retention-off switch (counts rise).
2. `aPrepaintReplayedFrameEqualsAFreshFrameAtEveryDragStep` (value, panels arms: scene, hitbox list, tab order, AX emissions, tallies compared whole) — red before: `retainedPrepaintHits == 0`; mutations: replay hitboxes in reverse (ranking differs), drop one tally, skip focus stops, skip AX.
3. `aReplayedHitboxIsRankedLikeAFreshOne` (overlapping siblings, `topmostHitbox` at a grid of points) — red before: passes on the stub (instrument); mutation: append replayed hitboxes after later siblings'.
4. `aChangedPaintOnlyAmbientRedoesTheFrameOnce` (arms: `.opacity`, `.shadow`, `.blur`, `.compositingGroup()` outside the occurrence) — red before: `retainedRedos` absent/0 and a stale picture on the stub; mutations: redo disabled (stale scene), the arm's ambient dropped from `AmbientKey`.
5. `aRedoLeavesEveryTableAsAFreshBuildWould` (RK-M, one checkpoint-channel mutation each; redo disables ALL graft/prepaint replay) and `aRedoFrameEqualsARetentionOffFrame` (script with a pending `withAnimation`, `scrollTo`, a `@FocusState` write, a lifecycle appear) and `aRedoFrameConsumesEachWindowInputOnce` — red before: counter absent; mutations: no `scrollRequests` restore (lost scroll), new transaction taken in the redo (animation lost), abandoned frame adopted.
6. `aResizeDragRedoesAtMostOncePerEightFrames` and `aPersistentlyAnimatedAncestorIsQuarantined` — red before: unbounded redo count; mutations: backoff removed, quarantine exponent never doubling.
7. `aPrepaintInEachIneligibleKindRunsAsBefore` (scroll region, popover, tooltip, drag source, presentation, surface, geometry note, portal — one arm each) — red before: counter absent; mutation: each kind's refusal removed, one at a time.
8. `aFocusedOrHoveredOrPressedElementUnderTheOccurrenceRunsPrepaint` (`SB-X` extended to prepaint) — mutation: drop the rule.
9. `noRecordedHitboxStoresALayoutNodeID` and `aReplayedHandlerActsLikeAFreshOne` (RK-O; a `Mirror` cannot see closure captures) — mutations: a stored id field; a fixture handler capturing a stale id or re-seeded `@State` box; **typecheck guard** only if a new `package` surface needs one (mutate it red once).
10. `everyFrameChannelIsClassified` gains the new rows — red before: the new properties absent from the table; mutation: delete a row.
11. `aTranslatedReplayEqualsAFreshFrameAtEveryScale` (scales 1, 2, 4 taken; 1.5, 3 refused with count asserted; scenes bit-equal) — red before: `retainedTranslated == 0`; mutations: gate on power-of-two removed (reddens scale 3), integral-device gate removed (reddens fractional step), clip containment removed (cut run), translation applied to hitboxes only.
12. `aPanOfTheWholeGraphByWholePointsReplaysEveryNode` and `aFractionalPanIsRefusedAndStillEqualsAFreshFrame` — red before: hits 0 on a pan; mutations as 11.
13. `aStaticLabelOverlayReplaysAndAMovingOneDoesNot` and `theOverlayCostIsLinearAndCounted` re-taken (`RK-I`): the reading, not a new test, is the record's.

**Lane 2**
14. `aGraftedSubtreeEqualsAFreshBuild` (kernel, node-by-node differential of rows, signatures, leaf keys, parents, grid marks, then a layout over both) — red before: no `graft` (compile-red stub returns empty); mutations: index shift off by one, a table skipped (one per table), generation not restamped (traps by name).
15. `aGraftedFrameKeepsTheStateTableSweepsExact` (script: conditional removal elsewhere, `ForEach` reorder, lifecycle scope, nested occurrence) — mutations: journal not reapplied, `producedSlots` skipped, nested memo entries not touched.
16. `theBuildRecursionIsSkippedForAnUnchangedSubtree` (`elementRequests` conserved against the retention-off frame: `requests + retainedSkippedRequests`) — red before: skipped 0; mutation: graft disabled.
17. `aGraftedOccurrenceIsNeverWalkedByAnElementPhase` (every `withPayload` caller named; a nil payload with no marker traps, exit test) — mutation: marker not set.
18. `aGraftIneligibleBuildIsCountedByName` (`hiddenNodes` below top level, `recordsElementBounds`, `scrollKeys`) — mutation: eligibility removed (differential reddens).
19. `aGraftWithAChangedValueBuildsAndAGraftAfterItGrafts` and `aStateWriteBelowAGraftedOccurrenceRebuildsIt` (versions) — mutation: version compare skipped (stale colour, `SB-K`'s arm).
20. `aRedoAfterAGraftMismatchRestoresEverything` (M1's redo with grafts live) — mutation: redo leaves the entry grafted.
21. `theGraftPlusJournalCostIsMeasured` — not a test: lane 2 step 1 reading in the record against `RK-J`'s 50 % stop; the probe re-taken with the journal.
22. `theBracketNodeDragIsCountedAfterTheGraft` — the red-on-arrival literals of §6 (retained requests 0 under hits, prepaints 0, elementPaints as lane 1, redos 0 on the drag).

**Verify mode** (`RK-H`): runs over the whole suite under `METALUI_VERIFY_RETAINED=1` and `METALUI_VERIFY_LAYOUT_MEMO=1` at the end of each lane (0 traps, issues named); one exit test per channel for the new comparisons (`aVerifiedPrepaintReplayThatDiffersTraps`, `aVerifiedGraftThatDiffersTraps`).
**Unchanged gates:** 3717 + new tests in 3 suites, 0 goldens, guards 234 + new (each mutated red once), the fourteen images 0 px against `fb9a7e42`, `DemoFrameDeterminismTests` `Expected.swift` unedited, 0 `warning:` both build systems, the Linux image (`swift:6.4-noble`, volume `metalui-root-retained-build-skip` mounted at `/work/.build`) for the portable targets, `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`, `METALUI_RETAINED_DEMO=1` section in its own function.

## 6. Measurement protocol (work counted, time dated)

Per-frame `FrameWork` on the bracket node drag (`.value`, `.panels`, last drag frame) at `fb9a7e42` (taken here from the harness, to be re-taken as literals
by test 1): `measureCalls=52 cacheHits=331 cacheMisses=162 rects=182 glyphs=550 images=6`, `elementPaints=178` (`.value`)/110 (`.panels`)/1000
(`.environment`), `retainedHits=32/34/21`, `retainedIneligible=0/1/0`; `elementRequests` and `elementPrepaints` are test 1's to read. Release and
debug medians by `zsh docs/probes/perf-baselines.sh release bracket` (three whole-process runs, median) and `debug --quick bracket`,
recorded dated with the machine line and "shared Mac" (record §109 §13 readings: release `.value` 6.061, `.panels` 6.039 ms at lane 2 of
C14b; debug 46.7 and 46.0). Instrumented runs are not baselines. A pin counts work, never time.

## 7. Demo and human checks

`METALUI_RETAINED_DEMO=1` gains a "Skip build" switch (graft and prepaint replay on/off through `Window.testingRetainedSubtrees`-style
package switch) and a strip showing `retainedGrafts`, `retainedPrepaintHits`, `retainedRedos`, `retainedTranslated`; its section stays in its own
function. Human checks (group IV additions, **not run — an agent cannot**): IV-R1 a node drag with the switch off and on looks identical;
IV-R2 hover, click, Tab and VoiceOver on a replayed panel; IV-R3 a window resize and an opacity animation around the panels show no stale
frame and no stutter beyond one frame; IV-R4 a trackpad pan with the switch on.

## 8. Carried (reason, owner)

| item | reason | owner |
|---|---|---|
| read-only `withState` (TextField/ScrollView/List replay), popovers/surfaces inside a subtree | table cannot tell a read from a rewrite; per-frame requests | C14b-3 |
| custom environment keys | no equality | C14-c |
| finer scopes | no equality | C14-d |
| layout placement of a translated subtree by translation | M3 translates paint and prepaint only | C14b-3 or later reading |
| `drawText` | `RK-I` criterion | C14 close-out |
| M2 if `RK-J`'s 50 % stop fires | measured at lane 2 step 1 | recorded then |


## 9. Lane 1 as built (what moved from the design above; rulings `RK-R`…`RK-W`)

The design held for M1 and was corrected in five places by what the code and the runs showed; each is a ruling with its evidence.

| design said | built | ruling |
|---|---|---|
| the prepaint ledger is `hitboxes`, focus, AX, tallies, context menus | plus `axNodes` with the `$ax` slot write, press-only actions and element bounds (the harness records layout by default); everything else a prepaint can write is **audited by count** and a moved count makes the occurrence ineligible by name | `RK-R` |
| hover rule decided at prepaint "like paint" | hover resolves after prepaint, so the rule is the pointer inside any hitbox the occurrence's own ledger registered (a superset of paint's exact rule); no redo from a hover | `RK-R` |
| `RK-O` item 2: refuse a bound `@State` box not in the table | **refuted by the handler differential** (a box holds the table and the slot id); only the version check remains; the panels' top bar and inspector replay | `RK-T` |
| the redo restores the transaction, the scroll queue, the channels `StateTable` journals | a root transaction that animates refuses every replay (`SB-J`), so it never coincides with a redo; the channels that are **not** idempotent are `LifecycleStore` (a second `onAppear`, observed), `TimelineStore`/`SurfaceRegistry` occurrence counts, `TransitionStore` (`claim`, `afterLayout`) and `AnimationStore.entries`; `StateTable`'s build sets are unions of the same values; `textSystem.endFrame()` is owed on abandon | `RK-U` |
| translated replay gated on a power-of-two scale and whole device pixels (`RK-G`) | the leaves a record keeps are before every outer scope; replaying them through the live scopes **is** the fresh arithmetic, so no gate on scale or fraction is owed; prepaint moves each hitbox's inverse by the opposite amount (round-trip exact in `Double`); layout- and scroll-offset translations are carried | `RK-S` |
| verify mode: a scratch-tree build of the occurrence (`RK-H`), then a double build (`RK-N`) | the double build, compared after the root's paint; the presented frame is the second, its counters the first's | `RK-V` |

**Tests, by the spec's numbers.** 1 `theBracketNodeDragIsCountedAtFb9a7e42` (and `…AfterPrepaintReplay`, 1b); 2 `aPrepaintReplayedFrameEqualsAFreshFrameAtEveryDragStep`;
3 `aReplayedHitboxIsRankedLikeAFreshOne`; 4 `aChangedPaintOnlyAmbientRedoesTheFrameOnce`; 5 `aRedoFrameEqualsARetentionOffFrameAndConsumesEachInputOnce`
(`aRedoLeavesEveryTableAsAFreshBuildWould` is its lifecycle, animation-entry and focus arms; the scroll-queue restore is carried, `RK-U`); 6
`aPersistentlyAnimatedAncestorIsQuarantined`, `aRepeatedPaintOnlyChangeRedoesAtMostOncePerEightFrames`; 7 `aPrepaintInEachIneligibleKindRunsAsBefore`
(scroll region, text field, popover, drag source, geometry note; the surface, presentation and portal kinds are paint-ineligible already and never leave a record);
8 `aFocusedOrHoveredElementUnderTheOccurrenceRunsPrepaint`; 9 `noRecordedHitboxStoresALayoutNodeID` (`MetalUITests`) and `aReplayedHandlerActsLikeAFreshOne`;
10 the two classification guards gain `prepaintLog`, `redoEntries`, `verifySnapshot`, `verifyAbandoned`; 11 `aTranslatedReplayEqualsAFreshFrameAtEveryScale` (10 arms) and
`aHitboxWhoseClipDependedOnTheTranslationIsNotMoved`; 12 `aPanOfTheWholeGraphReplaysEveryNodeAndEqualsAFreshFrame`; 13 `aStaticLabelOverlayReplaysAndAMovingOneReplaysTranslated`
(renamed: the moving arm now replays); 14 `aVerifiedPrepaintReplayThatDiffersTraps` (7 arms and a control); the plain-import guard 1.17c.


## 10. Lane 2 as built (what moved from §2 M2 and §5 tests 14 to 22; rulings `RK-X`…`RK-AB`)

M2 held. The graft is cheaper than the build it replaces **with the journal included**: 17.7 % per outermost occurrence (`RK-X`, the 50 % stop did not
fire). It was corrected in six places by what the code and the runs showed; each is a ruling with its evidence.

| design said | built | ruling |
|---|---|---|
| `RK-F`: `elementBounds` below the top level and lowering records refuse a graft | `elementBounds` is written in prepaint (the ledger replays it), so it is no refusal; the lowered items of the **top-level** nodes are carried and recorded again for the new ids, interior ones are consumed or report nothing | `RK-Z` |
| the journal records "every sweep-visible channel" | thirteen events, each recorded by its funnel and applied by it; `withState`/`write` outside an animation baseline taint (`stateWrite`); eighteen audited channels refuse by name | `RK-Z` |
| the decision at the build "from the `RK-C` list" | the list is `Frame.graftRecord(for:id:key:)`; rects and the paint-only ambient stay unknown at the build, and a prepaint or paint decision against a graft is the redo | `RK-Y` |
| `ComponentLayout` payload optional with a marker | as designed; `withPayload` and `content` trap by name; `everyReaderOfAComponentPayloadIsNamed` scans `Sources/` for a third reader | `RK-Y` |
| verify mode: a second full build and a whole-frame compare, "table key sets" among them | the tables are compared **inside the snapshot, before the sweep** (the first spelling compared after the presented rebuild's sweep and read 118 marks missing); plus the layout tree digest | `RK-AA` |
| lane 1's pins unchanged | the pins that count a build run with the graft off by a parameter (`bracketDragFrames(graft:)`, `RPPair(graft:)`); the graft's counts are `RetainedGraftTests` | `RK-AB` |

**Tests, by the spec's numbers.** 14 `aGraftedSubtreeEqualsAFreshBuild` (3 offsets), `twoGraftsOfOneSegmentHaveDistinctGridRowTokens`, `aWindowThatIsNotACleanSubtreeIsRefusedByName`,
`aGraftedNodeHasNoRectUntilItIsPlaced` (`MetalUILayoutTests/GraftKernelTests.swift`); 15 `aGraftedFrameKeepsTheStateTableSweepsExact`; 16 `theBuildRecursionIsSkippedForAnUnchangedSubtree` (3 arms);
17 `everyReaderOfAComponentPayloadIsNamed`, `aGraftedLayoutTrapsByNameWhenAnElementPhaseReadsIt`, `anOrdinaryComponentLayoutHasAPayload`, `aBuiltOccurrenceLeavesAGraftRecordOfItsNodes`
(`MetalUITests/RetainedGraftInternalTests.swift`); 18 `aGraftIneligibleBuildIsCountedByName` (6 kinds); 19 `aGraftWithAChangedValueBuildsAndAGraftAfterItGrafts`, `aStateWriteBelowAGraftedOccurrenceRebuildsIt`,
`aNestedOccurrencesObservedChangeRebuildsTheGraftedOuter`; 20 `aRedoAfterAGraftMismatchRestoresEverything` (2 arms), `aGraftedOccurrenceUnderARefusedTranslationRedoesTheFrame`;
22 `theBracketNodeDragIsCountedAfterTheGraft` (3 arms); verify mode `aVerifiedGraftThatDiffersTraps` (6 arms), `anUndamagedVerifiedGraftDrawsNormally`; the plain-import guard 1.17d.
Test 21 is not a test: the reading is `RK-X`.
