# 110 — Retained build skip (C14b-2): lane 1, prepaint replay, the redo and translated replay; lane 2, the graft

Branch `perf/retained-build-skip` from `fb9a7e42`. Not a plan task: item C14b-2 of the gpui-gap priority list (user request
2026-10-02), the carried half of record §109. Spec `docs/superpowers/specs/2026-10-13-retained-build-skip-design.md` (§9 is lane 1 as
built, §10 is lane 2); rulings `RK-A`…`RK-AC` in `docs/superpowers/2026-10-13-retained-build-skip-decisions.md` (next unused `RK-AD`); probe
`docs/probes/retained-build-skip/`. Divergence labels reserved 405–414: **none taken** (no SwiftUI-visible behaviour; the only public
additions are `FrameWork`'s six counters (lane 1) and four more (lane 2: `retainedGrafts`, `retainedGraftIneligible`, `retainedSkippedRequests`, `retainedGraftedNodes`)).

**Status (2026-10-14): LANE 1 BUILT — M1 (prepaint replay and the redo) and M3 (translated replay). LANE 2 BUILT — M2 (the graft and the
`StateTable` journal), §10: the sections §1 to §9 below are as lane 1 left them and say "lane 2 is not built" where that was true then.** The orchestrator's gate for M1 (at least 0.4 ms on
release `.panels`): **met** — −0.50, −0.43 and −0.46 ms of thread-CPU time in three runs of `bracketab` (wall time −0.64, −0.42 and −0.06 ms: the first and third runs were contended, `RK-W`), after `RK-T` removed
the refusal of a never-written `@State` slot; before it the same reading was −0.32 ms.

## §1 The measurement (design phase, `fb9a7e42`, 2026-10-13, shared Mac)

The graft the design of `SB-N` assumed and `SB-AE` called untested, prototyped as an experiment patch
(`docs/probes/retained-build-skip/graft-cost.patch`, README there): per outermost `.equatable()` occurrence of the bracket
fixture, release: **build 72.5 µs, graft of its rows 9.7 µs (13 %)**, 27.2 nodes, 7392 occurrences (three arms, `--quick`). The
per-frame figures the README derived (1.4 ms and 0.19 ms, the −28 % ceiling) are **withdrawn** (`RK-P`): the probe's frame counter read
1 and the occurrences per frame were never measured. Lane 2 owns that reading, with the journal included.

## §2 Step 0 and after M1: the node drag, counted (the tenth of 21 drag frames, `retained: true`)

`fb9a7e42` (`theBracketNodeDragIsCountedAtFb9a7e42`, run with `testingRetainedPrepaint = false`, which is that tree's behaviour; literals):

| arm | requests | prepaints | paints | hits / misses / ineligible | skipped paints | evaluations / skips / refusals | measures / cache hits / misses | memo hits / misses | subtree hits |
|---|---|---|---|---|---|---|---|---|---|
| `.value` | 798 | 886 | 252 | 29 / 3 / 0 | 832 | 3 / 29 / 0 | 52 / 331 / 217 | 362 / 55 | 11 |
| `.environment` | 798 | 886 | 1008 | 19 / 2 / 0 | 76 | 2 / 19 / 11 | 52 / 366 / 217 | 1258 / 55 | 0 |
| `.panels` | 798 | 886 | 184 | 31 / 3 / 1 | 900 | 3 / 32 / 0 | 52 / 331 / 217 | 362 / 55 | 11 |

After M1 (`theBracketNodeDragIsCountedAfterPrepaintReplay`, **red on arrival** against the table above; everything not named is unchanged: requests,
paints, hits, the layout counts and the scene — 182 rects, 550 glyphs, 6 images, 78312 rasterized pixels):

| arm | prepaints | skipped prepaints | prepaint hits / ineligible | redos |
|---|---|---|---|---|
| `.value` | 219 (−75 %) | 667 | 29 / 0 | 0 |
| `.environment` | 829 | 57 | 19 / 0 | 0 |
| `.panels` | 176 (−80 %) | 710 | 30 / 1 (the top bar's menu: a presentation anchor) | 0 |

`elementPrepaints + retainedSkippedPrepaints` is `fb9a7e42`'s 886 in every arm (the conservation law). The `.environment` arm's nodes read
`@Environment` (divergence 346) and are refused as before; in `.panels` the graph panel (`ScrollView`, `List`, `TextField`) runs its prepaint.

## §3 Red-first

Commit `90e5e920`: the M1 tests against the switch-off stub (counters, journal, ledger and redo loop in the tree, `replaysPrepaint` defaulting false): 28 issues
in nine tests, the step-0 literals green. Every failure line is one shape — `retainedPrepaintHits` read 0 where 1 to 4 was predicted — in the drag differential
(`prepaintHits > 0`, `skipped > 0`, both arms), the ranking (`== 3`), the four ambient arms (`== 2`), the input test (`== 1`), the quarantine (`redoFrames.count >= 3`), the
eight-frame bound (`redos >= 1`), the six kinds, hover and focus (five lines) and the handler test (three). Commit `559d2b7c`: the M3 tests with the paint relaxation
stubbed false: 23 issues in two tests — `translated >= 3 * 5` read 0 at scales 1, 1.5, 2, 3 and 4 with and without an accessibility client, `prepaintHits >= 3 * 5` and
`refused == 0` failing in the five client-free arms, and the bracket pan by 4, 0.3 and 2.5 points reading `translated 0` against `8 * 8`; the bit-for-bit differentials held with
replay off. (The code was written before the tests in both cases and its switch turned off to read the red; the commits say so.)

## §4 Readings (work counted; time dated, never pinned)

Machine line: `MacBookPro18,2` (M1 Max) / macOS 27.0.1 / Swift 6.4, **shared with other workflows**: cross-process medians of the same binary moved by 2–4 ms between
runs and are not a reading (`perf-baselines.sh bracket` read `.value` 6.3, 7.6, 8.4 and 10.1 ms for one tree). The reading is `bracketab`: prepaint replay off and on **alternating
inside one process** (eight rounds of fourteen drags of 22 frames, order swapped on odd rounds), median drag frame:

| run (2026-10-14, release) | arm | off, wall / thread CPU | on, wall / thread CPU | Δ thread CPU | Δ wall |
|---|---|---|---|---|---|
| 1 (contended) | `.value` | 13.991 / 7.805 | 7.729 / 6.925 | −0.88 | −6.26 |
| 1 | `.panels` | 9.726 / 7.340 | 9.091 / 6.837 | **−0.50** | −0.64 |
| 2 | `.value` | 7.060 / 7.040 | 6.727 / 6.678 | −0.36 | −0.33 |
| 2 | `.panels` | 7.007 / 6.988 | 6.586 / 6.555 | **−0.43** | −0.42 |
| 3 (contended) | `.value` | 7.150 / 7.137 | 6.644 / 6.632 | −0.51 | −0.51 |
| 3 | `.panels` | 8.578 / 7.396 | 8.522 / 6.938 | **−0.46** | −0.06 |

Medians of the three: `.value` −0.51 ms (−7 %), `.panels` −0.46 ms (−7 %) of thread CPU. Two earlier pairs, for the record (before and after `RK-T`, one run each, quieter machine): `.panels` 6.271 to 5.949
(−0.32), then 6.445 to 5.976 (−0.47); `.value` 6.331 to 5.948 and 6.552 to 6.227.

`RK-L` expected −0.4 to −0.8 ms for M1; the readings are its lower edge. Wall and thread-CPU milliseconds agree to the microsecond in this CPU-bound loop. Debug (a mood,
not a baseline; `perf-baselines.sh debug --quick bracketab`): `--quick` (three rounds of six drags, contended), thread CPU per frame: `.value` 54.7 to 49.2 ms, `.panels` 55.2 to 49.3 ms (−10 %); wall 74.9 and 111.4 to 49.9 and 59.6.

**What the saving is.** A throwaway timer around `EquatableComponent.prepaintGroup` read 0.58 ms a frame with replay off and 0.26 ms with it (value arm, 137 frames each): 0.32 ms,
the frame's reading; the remainder is the dragged node and its wires and the decision's own cost (a key, a pointer test and a ledger append per occurrence, about 5 µs). **M3
moves no drag frame** (nothing translates in a node drag); it is a pan win, counted: `aPanOfTheWholeGraphReplaysEveryNodeAndEqualsAFreshFrame` reads `translated >= 64` over eight pan
steps by 4, 0.3 and 2.5 points. No pan timing is taken (the fixture's pan rebuilds every wire, which a translation does not help).

**For MetalCreator** (`RK-L`): this item does not by itself bring pan-50 (17.05), zoom-50 (18.64) or orbit-with-panel (20.56 ms) under 16.67 ms. M1 saves 0.3–0.5 ms of a 6 ms bracket
frame (5–8 %); the build, the layout kernel and the dragged node's own paint remain, and M2 (the graft) is the item that attacks them. Zoom is not a translation; a pan helps only if
the app pans with an `.offset` over its nodes (the bracket fixture does). The verdict is left to a MetalCreator reading.

## §5 Mutations (each pin reddens; filtered runs, see the note)

Method (`docs/practices/verifying-tests-can-fail.md`): commit first; apply the edit to the committed file; build and run `swift test --filter` over every test of the
retained-subtree files (25 functions, about 100 s); restore from the copy; `git status --short` clean after each completed run (it was; one batch I killed part-way left one file mutated, restored with `git checkout`, and was re-run). **Deviation from the brief:** the *unfiltered*
suite was run unmutated before and after (§7), not once per mutation — a run is seven minutes on this shared Mac and the 25 functions are every test that names the
retained-subtree machinery. Independent edits share a build where the failing assertion names the channel. **A bare `return` before a function's body parses as
`return <first statement>`** (warning "expression following 'return'"): the first spelling of the rollback mutations kept their first statement and was not a no-op; they were
re-run as `if true { return }`. A run that crashes prints no "failed" line: a group that read "reddened: []" was checked for `Precondition failed` before it was believed.

| mutation (spelling applied) | reddened (first, by name) |
|---|---|
| hitboxes replayed in reverse (`.reversed()` in `replayPrepaintLedger`) | the drag differential, the ranking, the four ambient arms, the redo, the quarantine, the eight-frame bound, the kinds, hover, the handler test, the pan arms, `aRetainedFrameEqualsAFreshFrameOverAScript`, `aRestoredDragEqualsAFreshOneAtEveryStep`, `aResizedWindowPlacesLikeAFreshOneAtEverySize`, `aBackdropInsideAReplayedSubtreeIsByteIdentical`, the verify exit tests |
| the four region tallies hover / pointer style / key / resign not added back | the differentials by `tallies [0,0,0,0,0] vs [1,1,1,0,1]` (258 differences) |
| `focusOnPressCount` not added back | the differentials by the fourth tally (the card registers a `.focusable(interactions: .edit)` region) |
| focus registrations not replayed | `tab order` |
| accessibility records / nodes not replayed | `accessibility tree` (231 differences) |
| element bounds not replayed | `element bounds` (26) |
| context menus / press-only actions not replayed | `registrations [] vs [menu…, menu…, press…, press…]` (516) |
| redo disabled (`requestRedo` appends nothing) | the four ambient arms, the redo, the quarantine, the eight-frame bound, `everyKeyComponentSeparates` (a stale picture) |
| opacity out of the paint key | the four ambient arms (scene), the redo, the quarantine, `everyKeyComponentSeparates` |
| window-wide backoff removed | `aChangedPaintOnlyAmbientRedoesTheFrameOnce` (the backoff counter) and `aRedoSuspendsPrepaintReplayForEveryOccurrence` (the second occurrence redoes). **`aPersistentlyAnimatedAncestorIsQuarantined` stays green**: one entry's own quarantine gives the same gap, which is why the second test exists |
| quarantine exponent never doubling | `aPersistentlyAnimatedAncestorIsQuarantined` (gap 9 where 17 is owed) |
| the `withState` taint in prepaint | `aPrepaintThatAloneWritesAChannelRunsEveryFrame(stateWrite)` — a scroll view and a text field are also refused at paint, so their arms stay green: a guard twice |
| the `timeVarying` audit | the same test, `anotherFrame` arm |
| the `anchors` audit | the same test, `anchor` arm, and `theBracketNodeDragIsCountedAfterPrepaintReplay` `.panels` (the top bar's menu replays) |
| the `popovers` audit | **nothing**: a presented popover is also refused at paint (`portal`); recorded as an equivalent second guard |
| the drag-and-drop refusal | `aPrepaintInEachIneligibleKindRunsAsBefore(dragSource)` (the first spelling did not compile and read as green; re-run as `&& false`) |
| the `geometryChange` taint | `aPrepaintInEachIneligibleKindRunsAsBefore(geometryChange)` |
| pointer rule dropped | `aFocusedOrHoveredElementUnderTheOccurrenceRunsPrepaint`, `aReplayedHandlerActsLikeAFreshOne` |
| hitboxes not moved on a translation | `hitboxes` differences in the pan tests |
| accessibility refusal removed from the translation | `accessibility tree` differences in the arms with a client, and `refused >= 3` |
| outer-clip gate removed | `aHitboxWhoseClipDependedOnTheTranslationIsNotMoved` |
| final stream used for a translated hit | `rects`/`glyphs` differences in the pan tests |
| translation relaxation removed (`differsOnlyByEffectTranslation` returns false) | the pan tests, the clip test, `aStaticLabelOverlayReplaysAndAMovingOneReplaysTranslated`, `everyKeyComponentSeparates(offsetEffect)` |
| `testingRetainedPrepaint`'s setter ignored | `theBracketNodeDragIsCountedAtFb9a7e42` |
| `testingRetainedPrepaint` made `public` | `thePlainImportCannotTurnPrepaintReplayOffOrDamageALedger` (the new plain-import guard, mutated red once) |
| `prepaintLog` row deleted from `frameChannels` | `everyFrameChannelIsClassified` |
| a `LayoutNodeID` field on `PrepaintLedger` | `noRecordedHitboxStoresALayoutNodeID` — **its first spelling scanned five fields of the ledger and stayed green; it scans the ledger whole** |
| a verify comparison removed, per channel (hitboxes, tab order, accessibility records, tallies, element bounds, context menus, press-only) | `aVerifiedPrepaintReplayThatDiffersTraps`, the arm of that channel |
| `LifecycleStore.rollbackBuild` a no-op | `theLifecycleRollbackKeepsATwinBuildToOneAppearance`, and `aRedoFrameEqualsARetentionOffFrameAndConsumesEachInputOnce` (`["appear","appear"]`) |
| `TimelineStore.rollbackBuild` a no-op | `theTimelineRollbackKeepsATwinBuildOnTheSameCursor` (an `.animation(minimumInterval:)` cursor; a periodic or explicit schedule's twin cursor walks the same entries, so the window arm stays green) |
| `TransitionStore.rollbackBuild` a no-op | `theTransitionRollbackLetsATwinBuildClaimTheGroupAgain`, and the window arm **traps** (`LayoutNodeID from generation … used against a LayoutTree at generation …`: the claimed record's stale `nodes`, ruling `C-3`) |
| `SurfaceRegistry.rollbackBuild` a no-op | `theSurfaceRollbackCountsATwinBuildFromZero` |
| `AnimationStore.rollbackBuild` not restoring `entries` | `theAnimationStoreRollbackRestoresTheEntriesAndForgetsWhatWasTouched`, and the window transition arm |
| `ScrollRequestQueue.restore` a no-op | `theScrollQueueGivesBackWhatAnAbandonedFrameTook` |

Not separated by any test: the transition store's *insertion and ghost* restore (`afterLayout` consumes an insertion when a removal starts during one; restored from the checkpoint, the window arm
passes with the claim map alone) — carried, the checkpoint keeps it as insurance. `aRedoLeavesEveryTableAsAFreshBuildWould` (the spec's name) is the window arm
`aRedoFrameEqualsARetentionOffFrameAndConsumesEachInputOnce` plus the six store pins.

## §6 Verify mode (`METALUI_VERIFY_RETAINED=1`, `METALUI_VERIFY_LAYOUT_MEMO=1`) over the whole suite

Run with both variables set, native build system, `AppKitPresentationTests` skipped, 2026-10-14: **3737 tests, 0 issues** (a verified frame is built twice; the run took 520 s against 380 s). Seven exit tests prove the comparison can trap, one per ledger
channel, and a control proves a clean replay draws. **What the runs found, in order** (each fixed or switched off, `RK-V`): (1) the first run trapped on `accessibility nodes` — the snapshot sorted ids by description and read two orderings of a set as a
difference; it compares sets now. (2) The next trapped on `scene glyphs element 277` in `theInvalidationDemoEvaluatesOneGetterToTheOtherTreesHundredAndTwentyOne`: the demo's readout draws this build's evaluation counts, so a frame built twice shows two readouts by design; that pin is
switched off under `METALUI_VERIFY_RETAINED=1`. (3) Six issues in three tests: `everyKeyComponentSeparates(offsetEffect)` (the offset effect's translation is now the one key component that replays, `RK-S`; its arm reads the translated hit),
`theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires` (the presented frame's element counters were the rebuild's while the retained counters were the first attempt's; both are the first's now, `Frame.adoptElementWork`) and
(4) `aDragFrameRestoresTheUnmovedOccurrencesPlacement` (the layout counts of the presented frame are the rebuild's; it passes with `METALUI_VERIFY_LAYOUT_MEMO=1` alone and with `METALUI_RETAINED_PREPAINT=0`, so the attribution is to the double build; switched off under the variable). The 14 new
count-reading tests of this lane are switched off under it too (`rsVerifying`). No replay was found to differ from a fresh frame by the trap.

## §7 Gates

* **Unfiltered `swift test --build-system native --no-parallel` after `swift package clean`, on an unlocked screen, `AppKitPresentationTests` included: 3746 tests in 3 suites passed** (`fb9a7e42`: 3717; +29 test functions: 15 in `RetainedPrepaintTests`, 3 in `TranslatedReplayTests`, 2 in `RetainedVerifyTests`,
  the ledger scan, the prepaint-only writers and six rollback pins in `MetalUITests`, and the plain-import guard). `FR-J no-argument frame: succeeded=true`; 0 `error:`; the only `warning:` is SwiftPM's deprecation notice. Typecheck guards 234 + 1 = 235 (1.17c, mutated red once, §5).
  A run on a locked screen would skip `AppKitPresentationTests` (3737).
* `swift build --build-tests` (default build system): 0 `warning:`, build complete (338 s on a contended Mac).
* **The fourteen offscreen images, 0 px against `fb9a7e42`, scenes identical** (`docs/probes/demo-pixels/compare.sh`, controls as recorded: light vs dark 1048576, default vs modal 1031003, default vs animation 454895, f0 vs f3 0, prod default vs modal 491221, 544 and 216 distinct values): all fourteen `differing=0` and `scene identical` at `bc77e68c` (and at `89eb2cd4`, the commit that had the prepaint and translated code).
  `Tests/MetalUICrossPlatformTests/Expected.swift` and `DemoFrameDeterminismTests` are unedited.
* **Linux** (`swift:6.4-noble`, volume `metalui-root-retained-build-skip`, `swift build --build-tests` then `swift test --skip-build` over the root package): built in 45 s and every run passed — `MetalUITestingTests` 246, then 9, 40, 25, 217, 79 and 22 tests. The pan, redo, verify exit and rollback tests pass there.
* `Backends/SDL`, `Package.swift`, `MetalUICore`, `MetalUILayout` and `MetalUIScene` are untouched (`git diff fb9a7e42 --stat` empty), so the SDL package and the replay-parity harness were not re-run; no shader changed.
* Census 3511 to 3520 (`FrameWork`'s six counters and three members of the demo model); `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. Divergences: none taken, 152 live.
* The demo (`METALUI_RETAINED_DEMO=1`, Prepaint switch, pan slider, prepaint / redo / translated readout, its own function) launched on an unlocked screen (lock probe: no `CGSSessionScreenIsLocked`, `displayAsleep main: 0`), was alive after 8 s and was killed; what it looks like is human checks IV-R1…R4 (§9).

## §8 What was found that nobody asked for

* **`TransitionStore` is not idempotent under a second build** — a stale `LayoutNodeID` in a claimed record traps on the redo — and `LifecycleStore` doubled an `onAppear`. The differential found the second;
  the mutation of the first found the first. Both are pinned by the rollback tests (§5).
* **`RK-O` item 2 was wrong** (`RK-T`) and cost the `.panels` arm a third of M1's win.
* **`RK-G`'s gates belonged to a design this is not** (`RK-S`): a translation re-applied through the live scopes needs neither a dyadic scale nor whole device pixels. A fractional pan replays.
* The harness opens every window with an accessibility client active, so every window test before this item ran with `collectsAccessibility` on; the client-free arms are new (`RPPair(accessibility: false)`).
* A tree that displays its own build counters (the invalidation demo's readout) cannot be built twice by verify mode and read the same.

## §9 Carried, with owners

| item | reason | owner |
|---|---|---|
| M2: the graft, the `StateTable` journal, nested memo touches | built in lane 2 (§10) | done |
| translation by layout (rects) or by the scroll offset (`activeOffset`) | re-bins glyphs and moves element bounds; `RK-G`'s gates would be owed | C14b-3 or a later reading |
| the scroll-queue restore under a real redo | nothing makes a frame both carry a `scrollTo` (`VL-H`) and replay; unit-pinned | with the variable-height `List` |
| the transition store's insertion/ghost restore | no separating test (lane 2 did not add one; the graft refuses a transition group by name, `RK-Z`) | C14b-3 |
| `drawText` | `RK-I`'s criterion held: a moving label under an `.offset` reads 0 `placeGlyphs` and 0 seam measures at scales 1 and 2 | C14 close-out |
| human checks IV-R1…R4: a node drag looks the same with the switches off and on; hover, click, Tab and VoiceOver on a replayed panel; a resize and an opacity animation around the panels show no stale frame; a trackpad pan with the Prepaint switch on | an agent cannot | the Record phase adds them to `docs/verification/human-checks.md` |
| the CLAUDE.md rule | **Retained prepaint (`RK-`, record §110).** An `.equatable()` occurrence's prepaint registers into a `PrepaintLedger` (hitboxes, focus, accessibility records and nodes, press-only actions, context menus, element bounds, tallies) replayed while the prepaint key is equal; a paint-time ambient that differs for a replayed prepaint abandons the frame after paint and the window builds it again with every replay off (`Window.buildAndAdoptFrame`; checkpoint in `AnimationStore.rollbackBuild`; 8 builds of window backoff and a per-entry doubling quarantine). A render-effect translation replays through the live scopes. A store a build mutates non-idempotently owes a `rollbackBuild`. | the Record phase |

## §10 Lane 2 as built: the graft (M2)

Rulings `RK-X`…`RK-AC`; spec §10. **M2 landed: an unchanged `.equatable()` occurrence skips its build recursion**, its layout rows are appended from a recorded
`LayoutSegment` (`LayoutTree.graft`), the `StateTable` events its build made are applied again through the table's own funnels (`BuildJournal`, `Frame.reapply`), a
grafted `ComponentLayout` has no payload (`RetainedGraft` marker) and its prepaint and paint replay, and a wrong decision is the lane 1 redo.

**Step 1 (`RK-J`'s stop, `RK-X`).** Graft plus journal per outermost occurrence in release on the bracket node drag: **60.5 µs of build against 10.7 µs of graft, 17.7 %**
(13.4 nodes on average; 31047 grafts, 3933 builds; `graft-journal-cost.patch`, a shared Mac at load 119 to 148, so the ratio and not the milliseconds). The 50 % stop did not fire.

**Red-first.** The graft tests were committed red with the graft off before the implementation was wired (`e078587d`): 15 tests, 53 issues, among them
`aGraftedSubtreeEqualsAFreshBuild` (all three prefixes), `aGraftedFrameKeepsTheStateTableSweepsExact`, `aGraftWithAChangedValueBuildsAndAGraftAfterItGrafts`, `aStateWriteBelowAGraftedOccurrenceRebuildsIt`,
`aRedoAfterAGraftMismatchRestoresEverything` (both arms), `aGraftIneligibleBuildIsCountedByName` (six kinds), `aVerifiedGraftThatDiffersTraps` (six channels) and `theBracketNodeDragIsCountedAfterTheGraft` (three arms). Green after the graft: the 19 tests
of that file. The pins added at the end of the lane (`3727d702`, the commit after) were not red-first: they were found by the mutation battery (`RK-AC`) and pass on the tree that has the graft.

**Work counted on the bracket node drag** (one drag frame, `RetainedGraftTests`' literals; `fb9a7e42`'s behaviour is the `off` row, lane 1's tree the `prepaint` row):

| arm | tree | elementRequests | elementPrepaints | elementPaints | retainedHits / misses / ineligible | grafts / ineligible | skipped requests | grafted nodes | measures / places |
|---|---|---|---|---|---|---|---|---|---|
| value | fb9a7e42 | 798 | 886 | 1084 | 0 / 0 / 0 | 0 | 0 | 0 | 2898 / 2814 |
| value | + prepaint replay (lane 1) | 798 | 219 | 252 | 29 / 3 / 0 | 0 | 0 | 0 | 1174 / 1001 |
| value | + graft | **208** | 219 | 252 | 29 / 3 / 0 | 29 / 0 | 590 | 590 | 1174 / 1001 |
| panels | fb9a7e42 | 798 | 886 | 1084 | 0 / 0 / 0 | 0 | 0 | 0 | 2898 / 2814 |
| panels | + prepaint replay (lane 1) | 798 | 176 | 184 | 31 / 3 / 1 | 0 | 0 | 0 | 712 / 539 |
| panels | + graft | **167** | 176 | 184 | 31 / 3 / 1 | 30 / 1 | 631 | 641 | 712 / 539 |
| environment | + graft | 760 | 829 | 1008 | 19 / 2 / 0 | 19 / 0 | 38 | 38 | 2898 / 2814 |

Content evaluations (3 / 3 / 2), layout measure calls (52), layout memo counts, rasterized pixels (78312), new textures (2), atlas upload (0), glyphs (550) and rects (182) are the same in every row: the graft changes the build's element requests and nothing the frame draws. The environment arm
(a custom environment key at the root) keeps most of the frame building (760 requests): `RK-Y` item 2 refuses a graft under a custom key, and its 19 grafts are the occurrences the key does not reach. `placeGlyphs`, raster and upload did not move (they were already 0 on a replayed frame, lane 1).

**Time, dated, a shared Mac (never pinned).** MacBookPro18,2 (M1 Max), release, 2026-10-14, load average 100 to 150 for every run; `zsh docs/probes/perf-baselines.sh release bracketgraft` alternates graft off and on in one process
(thread-CPU time is the reading, wall time swung by a factor of three on the contended runs). **The graft alone** (prepaint replay on in both arms): value 8.01 to 6.57 ms (-1.45), panels 7.65 to 6.18 ms (-1.48), the other runs -1.26 to -1.61.
**The whole item** (`bracketab`, three runs, off arm = `fb9a7e42`'s behaviour): value -1.74, -1.85, -1.99 ms; panels -2.02, -1.84, -1.93 ms of thread-CPU per drag frame, **-23 % to -26 %** of 7.5 to 8.5 ms,
past the item's -15 % refutation line and inside `RK-A`'s -28 % ceiling. Wall-clock medians per drag frame in the quietest run: value 9.65 to 8.25 ms, panels 15.7 to 13.5 ms. Debug medians were not re-taken (the pins count work).
**MetalCreator's frames are not measured here** (17.05, 18.64 and 20.56 ms on `e85cb07a`): a saving of 1.7 to 2.0 ms per bracket-fixture frame is the item's, and whether that crosses 16.67 ms is a MetalCreator run.

**Mutations** (`RK-AC`; one `RK_MUTANT` switch over the committed code, a filtered run per spelling, thirty-nine spellings). Killed, with the first reddened tests:

| mutation | reddened |
|---|---|
| the graft off | the fifteen tests above |
| no journal replay / `mark` / `named` / `memoTouch` skipped | `aGraftedFrameKeepsTheStateTableSweepsExact` |
| `produced` event skipped | `aConditionalInsideAGraftedOccurrenceStillResetsItsState`, and the verify exit tests |
| `loop` event skipped | `aLoopInsideAGraftedOccurrenceStillResetsTheRowsItLoses` (its positional loop; the `ForEach` rows are reset by the named path, `skipNamed`) |
| version compare skipped | `aStateWriteFromOutsideRebuildsAGraftedOccurrence` |
| dependency check always true | `aNestedOccurrencesObservedChangeRebuildsTheGraftedOuter` |
| pointer / hover rule off | `aFocusedOrHoveredElementUnderTheOccurrenceRunsPrepaint`, `aReplayedHandlerActsLikeAFreshOne` |
| the skipped-request count dropped | `theBracketNodeDragIsCountedAfterTheGraft`, `theBuildRecursionIsSkippedForAnUnchangedSubtree` |
| the marker not set / the redo kept the graft / a graft with a failed prepaint not asking for a redo | the redo arms, the trap pins, the verify exit tests |
| audit off / `stateWrite` taint off | `aGraftIneligibleBuildIsCountedByName` |
| each `LayoutTree.graft` table skipped (leaf keys, spacer axes, parents, row tokens, cell columns, cell anchors), the index shift off by one, the generation not restamped | `aGraftedSubtreeEqualsAFreshBuild` (cell columns only after the grid gained a spanning cell), `twoGraftsOfOneSegmentHaveDistinctGridRowTokens`; the unshifted grid plan and the stale generation **trap** |
| a `captureSegment` check removed | `aWindowThatIsNotACleanSubtreeIsRefusedByName` |
| a verify comparison removed, per channel | `aVerifiedGraftThatDiffersTraps`, that channel's arm |

Not separated, carried (`RK-AC` item 2): the re-recording of a top node's lowered item (`topItemsNotRecorded`) and the interior-item refusal (`interiorItemCheckOff`). Redundant by design (item 3): the version compare against a plain child's state.

**Verify mode over the whole suite** (`METALUI_VERIFY_RETAINED=1`, `METALUI_VERIFY_LAYOUT_MEMO=1`, native, `AppKitPresentationTests` skipped): the run on the final tree (2026-10-14, a quieter Mac) read **3750 tests passed, 0 issues** (3771 less the five `AppKitPresentationTests` sheet tests, the sixteen skipped for `AppKitMenuTests`' set, and the `rsVerifying` pins that switch themselves off; an earlier run at the graft's first tree read 3746 in 830 s); the first spelling of the table
comparison compared after the presented rebuild's sweep and read 118 marks missing (`RK-AA`, fixed). The pins added after that run are disabled under the variable (`rsVerifying`), as lane 1's count-reading tests are.

**Gates.** Unfiltered `swift test --build-system native --no-parallel` on the final tree, after a full rebuild, on a **locked screen**: **3771 tests in 3 suites, 5 issues: exactly the five `AppKitPresentationTests` sheet issues of `CI-AF`** and nothing else
(`fb9a7e42`: 3717; lane 1: 3746; +25 in lane 2); `FR-J no-argument frame: succeeded=true`; the build 0 `error:`, the only `warning:` SwiftPM's deprecation notice. `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing (four new `FrameWork` counters, each documented and mapped). The fourteen
offscreen images: all `differing=0`, scenes identical against `fb9a7e42` (`compare.sh`, controls as in §7). `Backends/SDL`, `Package.swift`, `MetalUICore` and `MetalUIScene` are untouched; `MetalUILayout` gains `LayoutSegment`, `graft`, `captureSegment`, `structureDigest` (all `package`) and imports `MetalUICore` only.
No divergence label taken. **Linux** (`swift:6.4-noble`, a `git archive` of `HEAD` mounted, volume `metalui-root-retained-build-skip` recreated, `swift build --build-tests` 68 s then `swift test --skip-build`): `MetalUITestingTests` 262, then 9, 40, 25, 221, 79 and 22 tests, all passed (a first attempt mounting the worktree itself failed on a stale module cache path, not on code). `swift build --build-tests` on the default build system: 0 `warning:`, complete.

**Carried** (owners): the two unseparated lines above and the interior-item arm (C14b-3); a graft under a custom environment key and under an animating transaction (refused by name, an environment epoch is C14-c); popovers and surfaces inside a grafted subtree (C14b-3); a finer scope than the occurrence (C14-d);
`drawText` stays deferred (`RK-I`, GT-F): the moving-label pins still read 0 `placeGlyphs` and 0 seam measures after translated replay; human checks IV-R1 to IV-R4 now also cover the graft (Skip build switch in the demo).
