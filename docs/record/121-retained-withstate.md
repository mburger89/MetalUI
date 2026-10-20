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

## §6 Green mutations and pins that prove less than they look

- **M4: `ListOrigin.sameEntry` always `true` reddens only an existing test** (`aListWhoseOriginChangesIsReWindowedOnTheNextFrame`), no RW pin.
  `aListWindowIsAFunctionOfTheStateItReads` compares a retained window with a fresh one after a scroll, a data change and a resize, and the
  scroll's own input write (always a bump, `RW-G`) carries the miss on its own, so the list origin's compared write is not what that test
  isolates. Carried (§9): a list test that moves `ListOrigin` with no scroll write (a data change that re-anchors a variable-height list,
  `VL-G`) and reads the window.
- **M9 (`noteRead` returning early) is seen only by the three unit tests.** A window test over a plain read still passes because the record also
  names the entry through `markJournal` or the creating write; a read of a slot no other channel names is what the journal alone covers
  (`ListOrigin`, `ScrollState`), and no window test isolates it. The unit tests are the instrument; verify mode (`unrecordedRead`) is the guard in
  a running window (§7).
- **The orbit pins do not exercise the reasons funnel** (M12): nothing is refused on those arms. Their doc comments claimed it; corrected. The
  funnel is pinned by `aPlainWithStateWriteStaysIneligibleByName` and `everyIneligibleOccurrenceIsCountedByItsReason(channel:)`.
- **G3 is green by construction** (`StateTable` is internal; a member's spelling cannot reach a plain import).
- **Lane A's `readStateAndAnUnchangedWriteDoNotBumpTheVersion` and the window tests are separated by different mutations** (the table of §5):
  the unit test sees `readState` bumping, the window tests see a conversion reverting; neither alone covers both.
- The spec's `retainedReadChecks`/`retainedReadMisses` counters were **not built** (`RW-R` 6): a version miss is a counted miss and traced
  `versions`, and no pin needed the figure.

## §7 Readings and gates (2026-10-19)

**Work, counted** (the pins; before `f557d339`, after the head). Orbit with panels, the fourth of six frames: element requests 115 to 6, skipped
683 to 792 (conserving 798), prepaints 117 to 7, paints 110 to 7, retained hits 34 to 3 (the three panels), ineligible / prepaint-ineligible /
graft-ineligible 1/2/1 to 0/0/0, redos 0, grafts 33 to 3, grafted nodes 693 to 837, reasons `{stateWrite: 3, presentationAnchor: 1}` to empty. The
`.value` arm is unmoved (156 / 642 / 160 / 178 / 32). Bracket `.panels` node drag: §3.

**Time, dated, never pinned.** `zsh docs/probes/perf-baselines.sh release bracketorbit` (8 rounds x 40 orbit frames per process), base `f557d339`
(`/private/tmp/claude-501/rw-base`, the head's harness overlaid) and the head alternating, three runs each, 2026-10-20 UTC (06:23 to 06:27), M1 Max,
macOS 27.0.1, load average 6 to 7 (1 minute, the Mac otherwise quiet); orbit frame, wall median / minimum ms (CPU median equal to wall within 0.002):

| run | base | head |
|---|---|---|
| 1 | 3.119 / 2.964 | 2.319 / 2.178 |
| 2 | 3.129 / 2.956 | 2.261 / 2.176 |
| 3 | 3.128 / 2.981 | 2.220 / 2.158 |

Means 3.125 and 2.267 ms: **-27.5 % per orbit frame** (minima -26.4 %). Lane A's head (instruments only, no conversion) read +4 % against base inside
the noise (`docs/probes/retained-withstate/README.md`), so the whole gain is the conversions. The harness named in the brief (`Prof`) is not on this
machine; `bracketorbit` is its replacement. The absolute figures are this fixture's, not MetalCreator's 20.56 ms (`e85cb07a`), which owes RW5.

**Suite.** `swift package clean`, `swift build --build-system native --build-tests` 0 `error:`, the only `warning:` SwiftPM's deprecation notice;
native unfiltered run on the merged tree (master `4d91f27f`): **3993 tests in 4 suites passed**, 0 recorded issues, `FR-J no-argument frame:
succeeded=true` (master's 3971 + 22). The suite reads **4 suites**, not the 3 of earlier records: the log's four are the FreeType oracle suite,
`HarfBuzzOracleTests`, `MemoryReleaseTests` and `MeasurePerformanceTests` (an existing type, no `@Suite` was added by this branch); why the fourth now
counts was not traced. 249 typecheck guards (master's 248 + `RW.1`, not re-counted guard by guard). `swift build --build-tests` on the default build system
0 `warning:`. **Verify mode over the whole suite**: `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`, unfiltered, 3993 passed, 0 issues, no trap
(82 tests print `skipped`: the count pins gated `.enabled(if: !rsVerifying)` and the env-gated measures, by design). `closeout-inventory-check.sh` and
`closeout-undocumented.sh` print nothing; the census gains `FrameWork.retainedIneligibleReasons` and `RetainedSubtreeDemoModel.reasons`.
**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> f557d339 HEAD`: the fourteen images 0 px, scene identical (controls intact: light vs dark 1048576,
f0 vs f3 0, chrome legacy vs proposal 0, 544 and 216 distinct values; default vs modal 1031003 against the recorded 1030498, as at record 120's era);
`DemoFrameDeterminismTests` `Expected.swift` unedited. **Linux**: `swift:6.4-noble` (image `metalui-portable`, a `git archive` of the head mounted,
volume `metalui-root-build-retained-withstate`) ran `MetalUITestingTests` (363 tests), `MetalUILayoutTests`, `MetalUICoreTests`,
`MetalUICrossPlatformTests` (226 and 22 further): all passed. `Backends/SDL` untouched (`git diff f557d339 HEAD -- Backends` is master's §122 only), so its
package was not re-run. Windows by CI only.

## §8 Hazards

- **A read a record does not name is a stale replay.** Any new framework read of state must go through `readState` or `peek` (journaled while
  retaining); a private store or a `Mirror`-style read is invisible to the record and to verify mode's subset check.
- **A compared write whose `unchanged:` says equal too often drops the write's effect on the version, not on the value**: the body's result is
  stored only on a change, so a closure that lies makes a scroller or a list stop moving (M1, M4, M11 are the measured shapes). Each site's closure
  owes a mutation that makes it constant (§5).
- **A creating frame is a write** (`RW-F`); a record made then holds no ledger until one counted miss (`RW-S`). A test that wants steady state
  warms past it.
- **An input write always bumps** (`RW-G`): an equal-value wheel or a re-typed character is one spurious miss, safe by design.
- **A fading scroll indicator is counted `requestAnotherFrame`-ineligible, not a miss** (`RW-H`).
- **A pointer resting in a panel, or a focus anywhere in it, is `SB-X`**: a wheel or a click leaves both there, so a retained panel under the pointer
  misses every frame. An orbit with the pointer over a panel is a different measurement from the bracket's (pointer elsewhere).
- **`everyStateWriteSiteIsClassified` is a source scan**: a call spelled across lines or through a wrapper is not seen; the three `Passes.swift`
  spellings and `StateTable.swift` are excluded by name.
- A locked screen hangs `AppKitPresentationTests` (`NSOpenPanel.init()`); this run recorded 0 issues, so the five sheet issues of `CI-AF` did not appear
  (the screen was not locked; the probe was not run).

## §9 Deferrals, with owners

| Item | Reason | Owner |
|---|---|---|
| `GPUSurface` inside a subtree (`.onDemand`, unchanged `value:`) | designed in `RW-L` (the scene op, the `SurfaceDrawRequest` with the same `value`, `SurfaceRegistry`'s occurrence journal event, the target-table touch, the draw closure held weakly through the memo entry, `IV-R`); no orbit win (the fixture's surface is a sibling); the `surface` reason stays counted | C14b-4 |
| open popover, alert, file dialog and any presentation under a retained subtree | a per-frame presentation root that flips against the live window (`SB-J`, `RW-K`) | C14b-4 |
| equal-value skip for input-time writes | a spurious miss is cheap (`RW-G`) | none until measured |
| layout or scroll translation of a retained subtree | float association (`SB-H`) | C14b-4 |
| a list test that isolates `ListOrigin`'s compared write; a window test that isolates the read journal | §6 M4, M9 | next touch of `List` or `RetainedSubtree` |
| custom environment keys without equality, finer scopes (`List` row, `ForEach` element), `@FocusState` memo | no equality / C14-c2 | C14-c follow-up, C14-d |
| `retainedReadChecks`/`retainedReadMisses` counters | no pin needs them (`RW-R` 6) | if a conversion needs one |
| MetalCreator's own orbit | no agent touches MetalCreator | the owner, RW5 |
| `drawText` | `GT-F` | unchanged |

## §10 The Record phase (2026-10-19)

Merged master `4d91f27f` (§122 single instance; clean, no conflict: master's side is `Backends/SDL`, docs and a few root test edits). Ran the clean build and the unfiltered suite on the merged tree, the verify-mode run, the pixel comparison, the Linux image, the default-build
warnings, the orbit timing and **lane B's mutation table, which its verifier had skipped** (§5; it found two comments that claimed a mutation the pin does
not see, corrected in `RetainedWithStateTests.swift`, and two pins that prove less, §6). The census was re-recorded (`docs/probes/closeout-public-api.tsv`:
the demo model's `reasons` had been added after lane A recorded it). Docs: `CLAUDE.md`/`AGENTS.md` (the `RW-` prefix, one paragraph, the SB paragraph's
ineligibility sentence, the counts bullet, the record list), `docs/api-overview.md`, `docs/migration.md` (a section), `README.md`, `docs/record/README.md`,
`docs/record/03-verified-on-real-hardware.md` and `docs/verification/human-checks.md` (group **RW**, RW1 to RW5, none run: an agent cannot), the decisions
doc (`RW-T`) and the spec's status. **No divergence label taken** (515–524 untouched, the header's next label left for the merge), no new public declaration
beyond `FrameWork.retainedIneligibleReasons`.
