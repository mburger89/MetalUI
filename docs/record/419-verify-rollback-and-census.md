# 419: verify mode checks the rollback, the census of references held in state, and what the redo backoff hid (`RK-AK`, `RK-AL`; PR 1.3 of the exact-redo plan)

Class `M`, no divergence, no public API. Branch `fix/exact-redo-verify`, **stacked on #435** (record 418), itself on #434 (record 417). The answer to "is Piece 2 (the scoped redo) safe to start" is at the end.

## What is added

- **Verify mode's `rollback` channel** (`RK-AK`). `METALUI_VERIFY_RETAINED=1` digests the state table (entry values, liveness, generation, **version**, marks, journal lengths, every `AttemptRestorable`'s contents) and the atlas (glyph map, slot map, packer, counters, pixels, dirty regions) before each attempt and after each rollback, the redo's and the replayed frame's, and traps with `METALUI_VERIFY_RETAINED: rollback: the rolled-back attempt left <line>`. A run with the undo log mutated off traps with the first differing entry line. It replaces nothing: `RW-U`'s `discardEntries` went in 417.
- **The census** (`RK-AK`). `StateTable.referenceClasses()` walks every entry's value for class instances; each framework class (module `MetalUI*` or `Swift`) is `AttemptRestorable` or has a row in `StateTable.classifiedReferences`. `everyReferenceHeldInStateIsClassified` builds 26 demo windows (about 35 s) and fails on an unclassified class and on a stale row; verify mode traps on an unclassified framework class (`unclassifiedReferences`); an app's own class in `@State` (the demo's `LazyDemoPinnedModel`) is the app's contract. Found: `RowExtentIndex` (restorable), `AXDeclarationsBox` and `KeyPath` (immutable: copy-on-write, immutable), `TableResizeDragBox` (immutable: written by the drag gesture only), `MarkdownSourceMemo` and `TableRowPositionCache` (cache: a pure memo, a hint every reader verifies).
- **`Window.testingRedoBackoff`** (package, default true; `ContentMemoStore.redoBackoff`): off, `noteRedo` leaves `prepaintSuspendedUntil` alone; the failing entry's own quarantine stays.
- **`TextSystem.abandonFrame()`'s default is `endFrame()`**, not a no-op: a conformer that checks its bracket (`ShapingCache`) needs it closed, so a no-op default would trap at the redo's `beginFrame()`; the price is the double aging it had before (cache residency only). The doc comment says so.
- **The fixtures** (`ExactRedoTests.swift`): the **mirrored lazy row** arm (a `LazyHStack` in a right-to-left horizontal scroller, scrolled each step); a `multi` fixture (thirty replayed cards, each under an opacity that changes once, so with the backoff off nearly every step is a redo: the pin is at least 20 of 30); `aRedoneFrameDeliversEachEventOnceAndKeepsTheTimelineCursors` (a `TimelineView` and an `onAppear`/`onDisappear` element beside the container: the delivered events in order, the drawn date, the pending wake, equal to the plain window's over 30 redone steps with the clock advanced); `theFixturesHoldWithTheRedoBackoffOff` (all five arms, backoff off, scene, hitboxes, bounds, atlas, no dangling glyph record) and `theRecord416FixturesHoldWithTheRedoBackoffOff` (`aMirroredScrollersGrowing...` both shapes and `aZoomedNodeIsHitWhereItIsDrawn`). The digest test now runs with the backoff off over `multi` and requires an attempt that changed an index, a glyph, and state.

## A channel nobody had listed, found by the switch (`RK-AL`) — a pre-existing bug

With the backoff off, `aMirroredScrollersGrowing...` was red: the lazy window stayed where it was after a scroll step (20 glyphs against 36), with the state table, the index and the atlas equal to a fresh window's. **It is not a rollback gap.** An `.equatable()` occurrence that holds a lazy container was **grafted across a scroll step**: its build read the scroller's offset through `LayoutPass.scrollContext`, which neither the graft's read set (state versions) nor its key (only whether a context exists) held. With graft off, prepaint off or translation off the window was right. The nine-build backoff after the warm-up's redo had been covering the one test that scrolls. **It reproduces on bare `origin/master`** (this branch's regression test, run against a checkout of master's `Sources` and `Tests` with the test file alone added: the right-to-left arm shows `glyphs counts [2, 20, 0] vs [2, 36, 0]` and a difference in element bounds after a scroll of 900, with no redo before the scroll in the left-to-right shape), so a lazy container, a `List` or a table body inside an `.equatable()` occurrence showed a stale window after a scroll step whenever the occurrence grafted. The fix: the read is journalled (`BuildJournal.Event.scrollContextRead(context, depth)`), re-journalled by `reapply` for an enclosing window, and `graftDependenciesHold` refuses a graft when a read made at or above the occurrence's own depth differs from the context in effect now. An occurrence that does not read the context pays nothing. `aScrollStepRebuildsALazyContainerInsideAnEquatableOccurrence` (both directions, backoff on, a warm-up long enough that no redo precedes the scroll, a graft required before it).

## Mutations (against the 17 tests of the filter; each run rebuilt)

| mutation | reddened |
|---|---|
| V1 `kind(ofReference:)` answers for every class | `aClassHeldInStateNeitherRestorableNorClassifiedIsNamed` |
| V2 the `TableRowPositionCache` row removed | `everyReferenceHeldInStateIsClassified` (a first version of the census read the wrong string for the module and checked nothing; this mutation found it) |
| V3 the backoff switch ignored | `theFixturesHoldWithTheRedoBackoffOff` (all arms: a build is suspended) |
| V4 the scroll-context check removed | `aScrollStepRebuilds...`, `theRecord416Fixtures...` |
| V5 the read not journalled | the same two |
| V6 the animation checkpoint not restored by the redo | `aRedoneFrameDeliversEachEvent...` (30 issues), `theFixturesHold...` |
| V7 the index journal off | `aRolledBackAttemptLeavesEveryStoreAsItFoundIt` (the fixtures of 417/418 had stopped exercising it: the streaming letters changed where wraps fall; the `multi` fixture does), `aRolledBackIndexIsTheIndexItWas`, `theFixturesHold...` |
| V8 the undo log off | the digest test (5 arms), the table test, the streaming-log pin |
| verify trap | the undo log off under `METALUI_VERIFY_RETAINED=1`: `Fatal error: ... rollback: the rolled-back attempt left ...` |

## The whole suite with the backoff forced off (temporary, not committed)

`ContentMemoStore.redoBackoff` defaulting to false, and `rpRedoBackoff` to false so the pairs follow it. Full run: **7378 tests, 8 fail, 86 issues, all in 8 tests; every scene, hitbox, bounds, Tab order, tally and log differential passes.** None is a real difference:

| failing test | what it pins | class |
|---|---|---|
| `aChangedPaintOnlyAmbientRedoesTheFrameOnce` (4 arms) | the 8 builds after a redo replay no prepaint and count a backoff frame each | the backoff itself |
| `aRedoSuspendsPrepaintReplayForEveryOccurrence` | a second change inside the backoff costs no redo | the backoff itself |
| `aRedoAfterAGraftMismatchRestoresEverything` (2 arms) | no graft in the 8 builds after the redo | the backoff itself |
| `aRedoFrameKeepsTheRedosOtherCounters`, `theFrameAfterARedoReportsNoCarriedEvaluation` (`RedoCounterTests` 71, 72, 82) | the frame after a redo equals the redo's counts and reports a backoff frame | the backoff itself: the next frame now replays |
| `equatableLabelsThatNeverReadTheValueMissOnlyAtTheTwoRows`, `aContentListThatNeverReadsTheValueKeepsItsWork` (`BackgroundProminenceTests`) | steady counts after a redo: 41 to 40 and 32 to 31 requests (prepaints the same minus one) | count literal: the frame after the redo replays one more occurrence than the backoff allowed |

**Piece 2 is safe to start**: with the window-wide backoff off, no scene or channel differs from a fresh window anywhere in the suite (the one real difference found, `RK-AL`, was the pre-existing graft bug above, fixed here). What Piece 2 owes: the literals above, moving to the scoped redo's values with the reason, and the eight tests' backoff expectations rewritten to the scoped quarantine; and the `multi` fixture and the digest test already run the every-step redo it makes common. The literals are **not** edited here: the product default keeps the backoff, so they are right as they stand.

## Fixed after merge: a pair's two atlases started different (a harness flake, not a rollback difference)

`theFixturesHoldWithTheRedoBackoffOff(arm: .transcript)` failed on CI (macOS) on every step, `testingAtlasSlots` unequal and `differences → ["glyphs"]`, and on about 1 run in 12 here. The cause is in `RPPair`, not the rollback or #435's slot rule: `TestWindow` draws its first frame before the pair pins the timeline clock (`RK-AD`), on the simulated clock anchored on `Date()` per window, a few ms apart. The `TimelineView` text of `extras: true` packed the digits of two different instants, each atlas kept them, and the later frames packed the rest after them in an order the other window did not share. With no timeline in the tree (`extras: false`) 0 of 60 pairs differed; with one, 5 of 60 did, backoff on or off. The slot layout is meant to be identical (that is what `slotDigest` is for), so the assertion is unchanged; `RPPair.init` now empties both atlases (`Window.testingReclaimAtlas`) right after the pin, before the warm frames. 150 pairs then agreed. New test `aPairOfWindowsWithATimelineStartsWithTheSameAtlas` (60 pairs, with the line removed it failed 3 runs of 3: 2, 1 and 3 pairs of 60).

## Suite, lint

Root 7378 tests in 80 suites, green (`--build-system native`, `--no-parallel`); `swiftlint lint --strict --baseline` 0; the closeout checks print nothing.
