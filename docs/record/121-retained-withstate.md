# 121 — Retained read-only state (C14b-3): a read is not a write

Branch `perf/retained-withstate` from `f557d339`, merged with master `4d91f27f` (§122 single instance; master's last record was 122, so 121
stands, nothing renumbered). Not a plan task: item C14b-3 of the gpui-gap list (user request 2026-10-02), the carried half of §109 §11 and §110
§9. Spec `docs/superpowers/specs/2026-10-19-retained-withstate-design.md`; rulings `RW-A`…`RW-S` in
`docs/superpowers/2026-10-19-retained-withstate-decisions.md` (next unused `RW-T`). **No SwiftUI probe**: the item makes no claim about SwiftUI,
only that MetalUI's replay equals a fresh frame (`RW-N`; gpui's `AnyView::cached` is cited from memory and is not an authority). Divergence
labels reserved 515–524: **none taken**. One public declaration, `FrameWork.retainedIneligibleReasons` (`MetalUITesting`, class `M`, doc
comment and inventory row in the `test-harness-host` line, `RW-M`); the census gains it and the demo model's `reasons`
(`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing).

**Status: LANDED in two lanes (A the instruments and the core mechanism, B the conversions, anchors, demo and after pins), both verified `ok`.
Slice ruled in `RW-A`: items 1 (read-only `withState`), 2 (`ScrollView`/`List`), 3 (unfocused `TextField`/`TextEditor`) and the anchor half of
item 4 land; an open popover, an alert, a dialog and `GPUSurface` inside a subtree are carried by name (§9). Lane B's own mutation table was
not run by its verifier (§5, run by the Record phase).**

## §0 The measurement the item started from (design phase, `f557d339`, 2026-10-19, headless, counts)

The `.panels` arm of `BracketFixture` (1440 x 900 at scale 2; top bar, graph panel with a `TextField` and a `ScrollView { List }`, a glass
inspector, a full-window `.onDemand` `GPUSurface` under all of it), nothing in the panels changing, each frame
`viewport.token += 1; setNeedsRedraw(); tick()` (an orbit), after three warm frames, frame 3 of 6: element requests 115 (skipped by the graft
683, sum 798, the retention-off count), prepaints 117, paints 110, hits 34, ineligible 1, prepaint-ineligible 2, graft-ineligible 1. Three
occurrences carried it: the **graph panel** (`stateWrite`: the first untainted `withState` in its window is `TextField.paintText`'s read, then
the scroller's and the list's), the **top bar** (`presentationAnchor`: its `Picker` and `Menu` record an anchor every frame, even closed) and,
only in the warm-up frames, the inspector (`animatedColor`'s first baseline write). The surface is a sibling of the panels, so item 5 moves no
orbit number. MetalCreator's 20.56 ms window CPU per frame (`e85cb07a`) is the same shape. These are the **before** pins.

## §1 What landed

- **Three entry points on `StateTable`** (`RW-C`): `readState(_:initial:)` (an entry present and of the type: return it, mark it live, record a
  read, **no version bump and no taint**; absent: exactly today's creation), the compared
  `withState(_:initial:unchanged:_:)` (run the body on a copy; `unchanged(old, new)` is `readState`, else today's write: version, `writeCount`,
  every open window's `stateWrite` taint), and the plain `withState`, **unchanged**, so a new framework site is conservative until it picks.
  The `PaintPass`/`PrepaintPass`/`LayoutPass` wrappers gain the same two spellings as `package`. `unchanged:` is a call-site closure; an
  `Equatable` protocol on `ScrollState`/`ListOrigin` is rejected (`RW-Q`: `ScrollState` is public).
- **A frame-long read journal** (`RW-R`): `StateTable.readJournal`, appended while retaining, emptied by `sweep()`; a build, prepaint and paint
  window each keep the id range they covered, so one record gets the three phases' reads. `peek` appends too; a slot with a channel of its own
  (`$ax…`, `$focus…`, `$anim…`) is **not** a read. `record.versions` is `markJournal` united with those ranges; the paint, prepaint and graft
  decisions already compared `old.versions`, and the graft record keeps its own `stateReads` (journal event `.stateRead(id, version)`) checked
  again in `graftDependenciesHold`. A version mismatch is a counted **miss**, never an ineligibility (`RW-D`).
- **Liveness in three channels** (`RW-E`): a read keeps its entry in the paint record's `marks`, the ledger's `liveStates` (replayed through
  `StateTable.touchLive`, which touches no version) and the graft's `.liveState(id)` event; a creating read or a changed compared write also ends
  in `noteLiveRead`. A replay re-notes what it stands for (`replayPaint`, `replayPrepaintLedger`, `reapply`), so an enclosing window's read set
  is the same on a hit as on a run.
- **Counted ineligibility by reason** (`RW-M`): `FrameWork.retainedIneligibleReasons`, one funnel `noteIneligible(kind, reason:)` behind the
  three increment sites; the sum equals the three counters (an occurrence refused at paint, prepaint and graft counts three times).
- **Conversions, lane B** (15 of the 34 `withState` sites, spec §2): `ScrollView.swift`/`ProposalScrollView.swift` raw-offset read to
  `readState`; `ScrollChrome.resolvedOffset`'s clamp a compared write over `ScrollState` (`sameScrollState`), its paint read and the indicator's
  `lastScrollTime` read `readState` (`RW-H`); `List`'s `noteOriginAndStaleness` offset write and the variable-row entry write compared by
  `ListOrigin.sameEntry` (`RW-I`); `TextField`/`TextEditor` four sites each: reads `readState`, the geometry `scrollX` write and the bound-selection
  reconcile compared with `==` (`TextEditState` is `Equatable`; `RW-J`). The other 12 input-time or hook writes stay plain and always bump
  (`RW-G`); the 3 focus/`$ax` slots and 4 `$anim` baselines keep their channels. `everyStateWriteSiteIsClassified` pins each file's census.
- **Anchors replay** (`RW-K`): `Frame.recordPresentationAnchor` also appends `(id, window-space bounds)` to `PrepaintLog.anchors`; the ledger stores
  them and replays through `Frame.replayPresentationAnchor`; `PrepaintAudit.anchors` is no longer an audited channel. A closed `Picker`, `Menu` or
  `.popover` declarer stops making its occurrence prepaint-ineligible.
- **Two defects found by the unfiltered suite and fixed** (`RW-S`): a paint record made in a creating frame had `prepaint == nil` and never gained a
  ledger (every later frame ran the prepaint and threw the ledger away because the paint decision hit the old record): `retainedPaintDecision`
  now treats `old.prepaint == nil && phase.ledger != nil` as invalid, one counted miss records it again; and verify mode compared read journals the
  sweep had already emptied (a Range trap): `StateTable` keeps `lastReadJournal` and `lastMarkJournal`.
- **Verify mode learns the read set** (`RW-O`): `METALUI_VERIFY_RETAINED=1` traps `unrecordedRead <id>` when the fresh run's reads are not a subset of
  the replayed frame's named set, and `writeMissed` when a compared write wrote in the fresh frame while the replay skipped it.
- **Instruments**: `bracketOrbitFrames(arm:frames:)` beside `BracketFixture`; three `package` `Window` hooks (`testingWriteState`,
  `testingStateVersion`, `testingStateIsLive`); the Prof harness named in the brief is not on this machine, so the repository's `perf-harness`
  carries the scenario `bracketorbit` (`docs/probes/retained-withstate/README.md`).
- **Demo**: `METALUI_RETAINED_DEMO=1` gains a panel strip (a `TextField`, a `ScrollView { List }`, a `Picker`) in its own function passed to the generic
  composer (added to `DemoStackBudgetTests`); the strip reads 16 occurrences, 13 hits in steady state and shows the reasons.

## §2 Tests and guards, per file

Lane A: `Tests/MetalUITests/RetainedWithStateInternalTests.swift` (`readStateAndAnUnchangedWriteDoNotBumpTheVersion`,
`aReadJoinsTheJournalAndKeepsItsEntryLive`, `aReadFillsEveryLivenessChannelAndTheGraftJournal`, `aChangedCompareWriteTaintsEveryOpenWindow`,
`aReplayedReadAndLivenessMoveNoVersionAndTaintNothing`); `RetainedWithStateCompileGuards.swift` — **one new typecheck guard `RW.1`**
`theReadOnlyStateSurfaceIsUnreachableFromAPlainImport` (plain import: `readState`, `touchLive`, `stateReads`, `unchanged:` unreachable);
`Tests/MetalUITestingTests/RetainedWithStateTests.swift`: `theOrbitWithPanelIsCountedBeforeReadOnlyState` (the before row, `.value`),
`theOrbitWithPanelHasNoIneligibleOccurrencesAfterReadOnlyState` (the after pin, **red on arrival at lane A with 6 issues, green at lane B**),
`aReadOnlyOccurrenceReplaysAndAnInputWriteToItsStateMisses(label:)` (modes x phases x graft), `aReadOnlyEntryStaysLiveAcrossManyReplays(phase:)`,
`aNestedReplayKeepsItsReadsInTheEnclosingRecord(phase:)`, `aPlainWithStateWriteStaysIneligibleByName`,
`everyIneligibleOccurrenceIsCountedByItsReason(channel:)`, `aRetainedReadSetHoldsNoStrongReference` (`IV-R`); `RetainedWithStateSupport.swift`
(the probe elements).
Lane B: `RetainedWithStatePanelTests.swift` — `aWheelInsideARetainedPanelMissesOnTheScrollStateVersionAndMatchesAFreshWindow`,
`aListWindowIsAFunctionOfTheStateItReads`, `anUnfocusedFieldKeepsItsStateAcrossThreeHundredReplays`,
`aFocusedFieldInsideARetainedPanelMissesAndTypingWorks`, `aSelectionChangeInsideARetainedListMisses`,
`aPickerOpensFromAReplayedAnchorWhereAFreshWindowOpensIt`, `aScriptedSessionOnThePanelsArmEqualsAFreshWindowEveryFrame` (the differential: orbit,
wheel, click, type, slider drag, toggle, resize; scene, hitboxes, AX, focus order and state entries equal frame by frame),
`everyStateWriteSiteIsClassified` (source scan). Edited by ruling (`RW-` named in the comment, `RW-S`): the `.panels` rows of
`RetainedPrepaintTests`, `RetainedGraftTests`, `RetainedSubtreeSemanticsTests`, `RetainedSubtreeWindowTests`, `RetainedPrepaintRefusalTests`,
`RetainedSubtreeInternalTests`, `RetainedSubtreeDemoTests`, `DemoStackBudgetTests`, and the kind/channel/prepaint-write tests, which now keep a
**plain-write leaf** (`PlainWriteLeaf`: a `withState` with no `unchanged:` in all three phases) as the separating `stateWrite` arm and move `.scroll`
to the graft-eligible side.

## §3 Moved expectations (each with its number)

The bracket `.panels` node drag: the graph panel (the drag is inside it) was ineligible (`stateWrite`) and is now a counted **miss** each frame (`SB-X`:
the pointer is pressed inside it): misses 3 to 4, ineligible 1 to 0, hits 31; with the graft element requests 167 to 144, prepaints 176 to 153, grafts 30
to 31, graft-ineligible 1 to 0, grafted nodes 641 to 677, skipped requests 631 to 654 (conservation 798 and 886 holds). The `.value` and `.environment`
arms and every scene, paint and layout count are unmoved. **The orbit frame** (the item's own scenario): requests 115 to **6**, skipped 683 to 792, prepaints
117 to **7**, paints 110 to **7**, hits 34 to 3 (the three panels each replay and stand for their nested occurrences), ineligible 1/2/1 to 0/0/0, reasons
`{stateWrite: 3, presentationAnchor: 1}` to empty, redos 0. The spec's prediction (counters read 0, requests fall to the few unretained leaves) holds.

## §4 Red first

Lane A wrote its pins before the mechanism: the unit tests (`readState`, the compared write, the journal, the liveness channels) were red by
absence (a stub `readState` forwarding to the plain `withState`), the before row was green at `f557d339` on the `.value` arm, and
`theOrbitWithPanelHasNoIneligibleOccurrencesAfterReadOnlyState` was **left red on arrival by design at lane A's head** (`c7655fda`: 11 issues = the five
`AppKitPresentationTests` sheet issues of `CI-AF` plus the pin's six: ineligible 1/2/1, hits 34, requests 115, prepaints 117, paints 110,
reasons `{stateWrite: 3, presentationAnchor: 1}`); it went green at lane B (`71194132`). At lane B's first unfiltered run the suite read 80 issues
(`RW-S`): two defects (the ledger-less record, the swept journals), the rest expectations the conversions moved on purpose (§3).

## §5 Mutation tables

**Lane A** (the verifier's, on the full unfiltered suite, `git status` clean after each):

| Mutation | Reddened |
|---|---|
| `StateTable.readState`'s hit path also performs a plain `withState` write | `aNestedReplayKeepsItsReadsInTheEnclosingRecord(phase:)`, `aReadFillsEveryLivenessChannelAndTheGraftJournal`, `aReadOnlyEntryStaysLiveAcrossManyReplays(phase:)`, `aReadOnlyOccurrenceReplaysAndAnInputWriteToItsStateMisses(label:)`, `aRetainedReadSetHoldsNoStrongReference`, `everyIneligibleOccurrenceIsCountedByItsReason(channel:)`, `readStateAndAnUnchangedWriteDoNotBumpTheVersion` |
| compared `withState` treats every write as unchanged (`if true \|\| unchanged(...)`) | `aChangedCompareWriteTaintsEveryOpenWindow`, `readStateAndAnUnchangedWriteDoNotBumpTheVersion` |
| `touchLive` a no-op | `aReadJoinsTheJournalAndKeepsItsEntryLive`, `aReadOnlyEntryStaysLiveAcrossManyReplays(phase:)`, `aReadOnlyOccurrenceReplaysAndAnInputWriteToItsStateMisses(label:)` |

**Lane B** (its verifier ran the clean build and the unfiltered suite only, **no mutations**; the Record phase ran the table below, 2026-10-19).
Each mutation applied to the one site named, **restored with `git checkout` after the run, `git status --short` empty after each**, on a
**filtered** run of the retained, orbit, bracket, panel, graft, prepaint and verify suites (260 tests; a filter, not the whole suite: the brief's
"unfiltered where practical" was not practical at 5 minutes each on a Mac at load 80–150; the unfiltered suite ran green before and after).

| # | Mutation (site) | Reddened (new RW tests in **bold**) |
|---|---|---|
| M1 | `sameScrollState` returns `true` (`ScrollChrome.swift`, the clamp's `unchanged:`) | 30 tests, 111 issues, among them **`aWheelInsideARetainedPanelMissesOnTheScrollStateVersionAndMatchesAFreshWindow`, `aListWindowIsAFunctionOfTheStateItReads`, `anUnfocusedFieldKeepsItsStateAcrossThreeHundredReplays`, `aFocusedFieldInsideARetainedPanelMissesAndTypingWorks`, `aPickerOpensFromAReplayedAnchorWhereAFreshWindowOpensIt`, `aScriptedSessionOnThePanelsArmEqualsAFreshWindowEveryFrame`, `aSelectionChangeInsideARetainedListMisses`, `theOrbitWithPanelHasNoIneligibleOccurrencesAfterReadOnlyState`, `theOrbitWithPanelIsCountedBeforeReadOnlyState`**, and the existing list-window, scroll-clamp and bracket tests (an offset the clamp never writes back is a broken scroller everywhere) |
| M2 | `sameScrollState` returns `false` (every clamp a write) | **`aFocusedFieldInside…`, `aPickerOpensFromAReplayedAnchor…`, `aScriptedSession…`, `aSelectionChangeInsideARetainedListMisses`, `aWheelInside…`, `anUnfocusedFieldKeepsItsState…`, `theOrbitWithPanelHasNoIneligibleOccurrencesAfterReadOnlyState`**, `aGraftIneligibleBuildIsCountedByName`, `aPrepaintInEachIneligibleKindRunsAsBefore`, `everyLedgerChannelMakesTheSubtreeIneligible`, `theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires` |
| M3 | `ScrollView`'s raw-offset `readState` replaced by a plain `withState` | the M2 set plus **`everyStateWriteSiteIsClassified`** and `theBracketNodeDragIsCountedAfterTheGraft` (12 tests) |
| M4 | `ListOrigin.sameEntry` returns `true` | `aListWhoseOriginChangesIsReWindowedOnTheNextFrame` only. **None of the new RW tests reddens**: a list whose origin is written equal never moves its window in a way the new pins read (§6) |
| M5 | `ListOrigin.sameEntry` returns `false` | **`aFocusedField…`, `aPickerOpensFromAReplayedAnchor…`, `aScriptedSession…`, `aSelectionChangeInside…`, `aWheelInside…`, `anUnfocusedFieldKeepsItsState…`, `theOrbitWithPanelHasNoIneligibleOccurrencesAfterReadOnlyState`**, `theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires` |
| M6 | `TextField`'s paint-time `readState` replaced by a plain `withState` | **`aFocusedField…`, `aScriptedSession…`, `aWheelInside…`, `anUnfocusedFieldKeepsItsState…`, `everyStateWriteSiteIsClassified`, `theOrbitWithPanelHasNoIneligibleOccurrencesAfterReadOnlyState`**, `aPrepaintInEachIneligibleKindRunsAsBefore`, three bracket node-drag families, the demo test |
| M7 | the ledger's anchors loop dropped (`replayPrepaintLedger`) | **`aPickerOpensFromAReplayedAnchorWhereAFreshWindowOpensIt`** only (the instrument the spec named) |
| M8 | `retainedPaintDecision`'s ledger-less-record upgrade removed (`RW-S` 1) | `aGraftIneligibleBuildIsCountedByName`, `aPrepaintInEachIneligibleKindRunsAsBefore` (the very tests that found it) |
| M9 | `noteRead` returns before appending (the read journal) | **`aReadJoinsTheJournalAndKeepsItsEntryLive`, `aReadFillsEveryLivenessChannelAndTheGraftJournal`, `aReplayedReadAndLivenessMoveNoVersionAndTaintNothing`** (three unit tests; no window test sees it, §6) |
| M10 | a plain `withState` added to `ScrollView.swift` | **`everyStateWriteSiteIsClassified`** plus the M3 set (12 tests) |
| M11 | `TextField`'s bound-selection `reconcile` compared as always equal | `aSelectionWriteDoesNotCorruptUndoAndEndsTheTypingGroup`, `aSelectionWrittenWhileComposingIsHeldBackAndSupersededByTheCommit` |
| M12 | `noteIneligible` records the reason `"?"` | **`aPlainWithStateWriteStaysIneligibleByName`, `everyIneligibleOccurrenceIsCountedByItsReason`** (the orbit pins stay green: nothing is refused there; their doc comments said otherwise and are corrected) |
| G1 | `PaintPass.readState` made `public` (guard `RW.1`, first arm) | `theReadOnlyStateSurfaceIsUnreachableFromAPlainImport` (2 issues: "is package API", "rejected, but not for the member") |
| G2 | `PaintPass.withState(...unchanged:...)` made `public` | the same guard (`the compared withState is package API`) |
| G3 | `StateTable.touchLive` spelled `public` | **green by construction**: `StateTable` is internal, so a member's spelling cannot reach a plain import; only the type's visibility could, and it is not mutated |

Lane A's 3 and the three rows M7, M9, M12 are the spec's named mutations that hold; the spec's mutation for test 4 ("`ListOrigin` read not recorded") is M4
in a stronger spelling and is not separated by an RW test (§6).
