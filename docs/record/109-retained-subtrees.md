# 109 — Retained subtrees (C14b)

Branch `perf/retained-subtrees` from `e85cb07a`. Not a plan task: item C14b of the gpui-gap priority list (user
request 2026-10-02), the second half of C14 (record §104), requested by MetalCreator (gap PERF-b). Spec
`docs/superpowers/specs/2026-10-13-retained-subtrees-design.md` (design phase; amended by `SB-S`…`SB-AC`), fixture spec
`docs/superpowers/specs/2026-10-13-retained-subtrees-fixture.md`; rulings `SB-A`…`SB-AE` (`SB-A`…`SB-R` the design
phase's, `SB-S`…`SB-AC` lane 1's, `SB-AD`, `SB-AE` lane 2's) in `docs/superpowers/2026-10-13-retained-subtrees-decisions.md` (next unused `SB-AF`);
probes `docs/probes/retained-subtrees/`. Divergence labels reserved 395–404: **none taken** (no SwiftUI-visible
behaviour; the new public declarations are `FrameWork`'s ten counters and the demo's content, census 3492 -> 3510).

**Status: LANE 1 BUILT — as paint replay, not prepaint-and-paint replay (`SB-AA`). LANE 2 BUILT AS THE SUBTREE PLACEMENT MEMO ALONE (`SB-AD`, §13); the graft, the journal, the redo and prepaint replay are carried (`SB-AE`).** Built: a retained record per `.equatable()` occurrence replays its paint on a hit; build, layout and prepaint still
run (lane 2). The node drag's release median per frame is **-10 to -14 %** (`.value` 7.44 -> 6.68 ms, `.panels` 7.62 -> 6.56 ms in the final
head's reading, 7.42 -> 6.53 and 7.45 -> 6.52 in the quiet one) and its element paints 1084 -> 178; the lane 2 gate reads 57 % and opens (§10).
Verify mode ran over the whole suite with no trap after finding `SB-AC` (§5). Deferred: prepaint replay, the build skip, the graft and the
placement memo, translated replay, read-only `withState`, popovers/surfaces inside a subtree, custom environment keys, finer scopes, `drawText`
(§11).

## §1 The measurement (design phase, `e85cb07a`)

The fixture `Tests/MetalUITestingTests/BracketFixture.swift` is MetalCreator's bracket window (1440 x 900 at scale 2, 20
nodes of which 11 pass the cull, 21 wires, a top bar, a graph panel with a library `List`, a glass inspector, a full-window
`.onDemand` `GPUSurface`); the measured drag is the node drag (a press on Fillet at (20, 400), 20 events of 2 pt, one tick
each, then the release: 21 drawn frames). Counted at `e85cb07a` per drag frame (all three arms identical in the scene):
3 occurrences evaluate and 29 are skipped (`.value`), 182 rects, 550 glyphs, 6 images, 81 layout measures, 798 element
requests, 886 element prepaints, **1084 element paints**, 78 312 pixels rasterized for the two changed wires; over the 21
frames 2898 text-system measures and 2814 `placeGlyphs`. Phase shares of a render (spec §1, §1.1, dated, shared Mac):
**release** build 33 %, paint 32 %, layout kernel 19 %, prepaint 12 %; **debug** paint 61 %, build 18 %, layout 11 %, prepaint
9 %. Record §104's "build is 51 %" was a tree of bare `Text`s; the bracket window's leaves are rounded rectangles, clips,
strokes and paths, and paint is where they cost.

## §2 What lane 1 is, and the one thing the build changed in the design

**The design** (spec §3–§8) decided hit or miss in `EquatableComponent.prepaintGroup`, recorded hitboxes, focus
registrations, accessibility records and scene primitives, and replayed prepaint and paint. **The build did that first**
and it passed every existing test and the 1.2 differential; test 1.3 (`everyKeyComponentSeparates`, one arm per key
component) then reddened three arms, `.opacity(_)`, `.shadow(radius:)` and `.blur(radius:)` outside the occurrence: the
paint-only ambient (the opacity stack, the paint scopes of shadow, blur and composite) is pushed by ancestors' `paint`, after
every prepaint, and `isPaintScopeOnly` effects have no prepaint counterpart, so **a prepaint decision cannot see it**
(`SB-AA`). The remedies (a prepaint run at paint time under a saved prepaint context; a frame redo; a mirror stack at every
site that pushes an opacity or a scope) are lane 2's or unsafe, so lane 1 **replays paint only**: the decision, the key and
the recorder moved to `paintGroup`; prepaint always runs, in an observation window of its own (`SB-V`); `ComponentPrepaint` is
as it was but for a phase field. The first build's code is the record of what lane 2 inherits (`SB-AA`, cost if wrong).

**Mechanism as built** (`Sources/MetalUI/RetainedSubtree.swift`, 567 lines; hooks in `Frame`, `StateTable`, `AnimationStore`,
`ContentMemo`, `EquatableComponent`, `Component`):

* **The record** hangs off the memo entry (`ContentMemoStore.Entry.record`, swept with it): the scene operations paint made, the
  `StateTable.mark`s and `AnimationStore` touches it made, the element work it stands for, the replay key, the content
  serial it was made under and the versions of the `@State` slots bound under the component.
* **The key** (`ReplayKey`): the absolute rect of every top-level node, a hash of every descendant's rect and unrounded measured
  width (`LayoutTree.subtreeSignature`, one pass), and the ambient read **at paint** (`AmbientKey`): clip and radii, offset,
  layer, opacity, scale, content size, clip depth and bases, the open paint scopes (kind, effect map, depth, flattening flag,
  outer mask, shadow and blur parameters), `EnvironmentFingerprint` (every built-in `EnvironmentValues` field, the provided
  objects by identity; a custom key makes the occurrence ineligible), the transaction. Plus: the hovered, pressed or
  focused element is not the component or under it (`SB-X`), no observed read of the three windows changed, the content
  was not re-evaluated, no bound `@State` moved.
* **The scene** is recorded where the occurrence's own paint scopes end (`Frame.processScopes(_:from:depth:)`, the old
  `insertThroughScopes` loop split at a scope boundary; the six direct fast paths note boundary 0) and replayed from that
  boundary, so the outer scopes treat a replayed leaf as a fresh one (`SB-T`). Rasters are looked up in `insertIntoScene` as
  ever, so a replayed path keeps its texture and rasterizes nothing.
* **Taints** (the occurrence paints as before and is counted `retainedIneligible`): a `withState` or `write` in the window,
  a `GPUSurface`, a portal, a capturing or barrier scope inside, `noteActiveAnimation`/`requestAnotherFrame`/
  `noteInterpolation` (`SB-S`), a time-varying build, a custom environment key or a non-nil transaction animation at entry.
* **Verify mode** `METALUI_VERIFY_RETAINED=1`: a hit paints as a miss and compares the new record with the old one
  (`SB-W`); `METALUI_TRACE_RETAINED=1` prints why a record missed or an occurrence was ineligible.
* **Counters** (`FrameWork`): `elementRequests`, `elementPrepaints`, `elementPaints`, `retainedHits`, `retainedMisses`,
  `retainedIneligible`, `retainedSkippedPrepaints` (always 0), `retainedSkippedPaints`, `retainedLedgerSnapshots` (2 per
  recorded occurrence), `retainedReplayedOps`; `Window.testingRetainedSubtrees` (package) is the memo-off switch.
* **Demo** `METALUI_RETAINED_DEMO=1` (`RetainedSubtreeDemo.swift`, its own function, in `DemoStackBudgetTests`): eight nodes, seven
  wires, a counts strip and a "Replay" switch. Writing its model's initialiser with closures trapped on the 1 MB thread test
  (`SIGTRAP`: a closure formed in a `@MainActor` initialiser checks its executor when the tree is built off the main
  thread); it uses loops.

## §3 The pins, their predictions and what the run read

Counts, never time. Every test below is in `Tests/MetalUITestingTests` (`RetainedSubtreeWindowTests`,
`RetainedSubtreeSemanticsTests`, `RetainedSubtreeOverlayTests`, `RetainedSubtreesBaselineTests`), `Tests/MetalUITests`
(`RetainedSubtreeInternalTests`, `RetainedSubtreeCompileGuards`, `RetainedSubtreeDemoTests`) or `Tests/MetalUILayoutTests`
(`SubtreeSignatureTests`); the mutation that must redden each is in §5.

| # | test | pins |
|---|---|---|
| step 1 | `theBracketNodeDragRebuildsTheWholeWindow(arm:)` | the design phase's prints as `#expect` literals with replay off (`SB-Q`): 3 / 29 / 0, 2 / 19 / 11 and 3 / 32 / 0 evaluations / skips / refusals, 886 prepaints, 1084 paints, scene 182 / 550 / 6, 78 312 px, 2898 / 2814 text-system calls |
| 1.1 | `theBracketNodeDragReplaysEveryUnchangedSubtree(arm:)` | every drag frame, three arms: hits / misses / ineligible 29 / 3 / 0, 19 / 2 / 0, 31 / 3 / 1; `hits + misses + ineligible == evaluations + skips`; `elementPaints + retainedSkippedPaints == the unretained frame's` frame by frame; prepaints, requests, measures, scene and rasters equal the unretained frame's |
| 1.2 | `aRetainedFrameEqualsAFreshFrameOverAScript` | cards under an offset, a shadow and a rotation, a stateful holder, an observed reader, an inspector with a material, a hover card and a scroll view; 24 script steps (hover, press, Tab, clicks, scroll, model writes, resize, appearance, scale): scene bytes, accessibility tree, hitbox list, Tab order, element bounds and hover events equal an unretained window's after every frame |
| 1.3 | `everyKeyComponentSeparates(arm:)` | 13 arms, one per component: top rect, clip, opacity, shadow, blur, rotation, offset effect, foreground, font, disabled, colour scheme, scale, content size; the probe re-records (the control too for the window's own events) and the scene equals the unretained one; `SubtreeSignatureTests` is the interior hash's arm at the kernel |
| 1.4 | `aPointerOrPressOrFocusInsideASubtreeMissesAndOutsideReplays` | the hovered, pressed or focused element under a card makes it miss, once the pointer leaves it records once and replays |
| 1.5 | `everyLedgerChannelMakesTheSubtreeIneligible(channel:)` | scroll view, `GPUSurface`, animation, custom environment key, `TextField`, popover: each occurrence ineligible, its plain neighbour still replays |
| 1.6 / 1.8 | `aDescendantStateChangeInvalidatesTheRecord`, `aChildGetterReadInvalidatesItsEquatableParentsRecord` | a non-equatable child's `@State`, and its getter's `@Observable` read, beat an always-equal parent's record |
| 1.7 / 1.7b | `anObservedReadInPaintInvalidatesTheRecord`, `anObservedReadInPrepaintInvalidatesTheRecord` | a custom element's paint read, and its prepaint read carried to paint in a `PrepaintState` |
| 1.9 | `aReplayedFrameKeepsItsAnimatedColourSlotsAlive` | a legacy box's `$anim-color` slot stays live over replayed frames (the marks are replayed) |
| 1.10 | `aLiveAnimationNeverReplaysAndAnIdleKeyframeSubtreeDoes` | an `.animation(value:)` flip: the opacity moves every frame and nothing replays; the idle keyframe animator replays; both replay once settled |
| 1.11 | `everyFrameChannelIsClassified`, `everyStateTableAndAnimationStoreChannelIsClassified`, `everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant` | `Mirror` guards: a stored property of `Frame`, `StateTable`, `AnimationStore` or `EnvironmentValues` with no row fails with its name |
| 1.13 | `aReplayTouchesItsRastersSoTheyAreNotDropped` | a replayed stroke keeps its `ImageTexture`: no pixel rasterized and no texture made in six frames |
| 1.14 | `aBackdropInsideAReplayedSubtreeIsByteIdentical` | a material's backdrop and a card under an outer shadow replay byte for byte |
| 1.15 | `aReplayedHitboxKeepsTheRankingAtAnOverlap` | two overlapping equatable cards: hitbox list and the click's recipient equal the unretained window's |
| 1.16 | `aMissCostsTheOldWorkPlusTwoSnapshots` | 2 ledger snapshots per recorded occurrence, 0 on a hit |
| 1.17 | `theRecordIsUnreachableFromAPlainImport`, `thePlainImportCannotTurnReplayOff` | plain-import guards: the counters type and the switch are `package` |
| 1.18 | `aStaticLabelOverlayReplaysAndAMovingOneDoesNot(labels:moving:)` | GT-F, §8 |
| 1.19 | `theGlyphAtlasHasNoEvictionCaller` | greps `Sources/` and `Backends/SDL/Sources` for an `evictUnusedSince(` caller |
| demo | `theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires` | 15 occurrences, 12 hits, 3 misses; replay off draws the same rects |

**Predictions fixed before the first run** (test 1.1): `.value` 29 / 3 / 0, `.environment` 19 / 2 / 0, `.panels` 30 / 3 / 2.
The run of the first design (prepaint and paint replayed, decided at prepaint) read 28 / 4 / 0 in the first nine drag frames
and 29 / 3 / 0 from the tenth, 19 / 2 / 0 throughout, and 29 / 4 / 2 then 30 / 3 / 2: the extra miss was the pointer over node
14's status badge, whose `.help` hitbox the conservative "pointer inside an owned hitbox" rule counts (`SB-X`). The paint-only
build reads 29 / 3 / 0, 19 / 2 / 0 and **31 / 3 / 1**: the one prediction that did not hold is the top bar (a menu `Picker`,
buttons, a `Menu`), predicted ineligible: its paint writes nothing a record cannot replay, so it replays.

**Findings the instruments made, in order** (each a fix or a ruling): (1) test 1.3's opacity, shadow and blur arms red on the
prepaint design (`SB-AA`); (2) the demo's model initialiser trapped the 1 MB thread test with `SIGTRAP`, a closure formed in a
`@MainActor` initialiser (fixed with loops); (3) the first release reading showed **no gain** (7.466 ms against 7.475):
two `withObservationTracking` windows per occurrence per frame (64 a frame) cost what the replay saved, so the build and
prepaint windows now open only for an occurrence with no record or a record that covers only its paint, and a hit opens
none (`SB-V`; 6.900 ms); (4) replay through the outer scopes cost about as much as the paint it replaced, so a record keeps
the final primitives too and replays them straight when every outer scope is a plain effect and no other recorder is open
(`SB-AB`; 6.569 ms); (5) on Linux the observation hop is asynchronous, three of the new tests wanted `rsSettle()`.

## §5 Mutations (every pin mutated; spellings and reddened tests named)

Run in a `git clone` of the branch (`/tmp/sb-mut-clone`), one source edit at a time, `swift build --build-system native --build-tests`
then the 37 retained-subtree tests, the edit restored from a copy and `git status --short` read clean after each (the driver is
scratch; the table is its output). Two batches: the first found nine tests missing or too weak, which were fixed and the mutation
re-run (marked in the text after the table); the table is the final reading of each mutation on the commit it names.

| mutation | spelling | result | reddened |
|---|---|---|---|
| `key-clip` | `clip:` of the ambient key made `[]` | RED | `everyKeyComponentSeparates` |
| `key-offset` | `offset:` made `[]` | RED | `everyKeyComponentSeparates` |
| `key-opacity` | opacity constant 1 in `layerOpacityScale` | RED | `everyKeyComponentSeparates` |
| `key-scale` | the scale factor constant 1 in `layerOpacityScale` | GREEN | - |
| `key-contentsize` | `contentSize` zeroed in `layerOpacityScale` | GREEN | - |
| `key-depths` | `depths:` made `[]` | GREEN | - |
| `key-scopes` | `scopes:` made `[]` | RED | `aStaticLabelOverlayReplaysAndAMovingOneDoesNot`, `everyKeyComponentSeparates` |
| `key-environment` | `environment:` an empty `EnvironmentValues` | RED | `aRetainedFrameEqualsAFreshFrameOverAScript`, `everyKeyComponentSeparates` |
| `key-rects` | `rects:` made `[]` | GREEN | - |
| `key-interior` | `interior:` made 0 | GREEN | - |
| `skipped-paints-not-added` | `skippedPaints += 0` in `replayPaint` | RED | `aStaticLabelOverlayReplaysAndAMovingOneDoesNot`, `theBracketNodeDragReplaysEveryUnchangedSubtree`, `theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires` |
| `hover-false` | the hover test `&& false` | RED | `aPointerOrPressOrFocusInsideASubtreeMissesAndOutsideReplays` |
| `press-false` | the press test `&& false` | RED | `aPointerOrPressOrFocusInsideASubtreeMissesAndOutsideReplays` |
| `focus-false` | the focus test `&& false` | RED | `aPointerOrPressOrFocusInsideASubtreeMissesAndOutsideReplays`, `aRetainedFrameEqualsAFreshFrameOverAScript` |
| `pointer-true` | the pointer/press/focus test always `true` | RED | `aBackdropInsideAReplayedSubtreeIsByteIdentical`, `aChildGetterReadInvalidatesItsEquatableParentsRecord`, `aDescendantStateChangeFromAShortcutInvalidatesTheRecordByVersion`, `aDescendantStateChangeInvalidatesTheRecord`, `aLiveAnimationNeverReplaysAndAnIdleKeyframeSubtreeDoes`, `aMissCostsTheOldWorkPlusTwoSnapshots`, `aPointerOrPressOrFocusInsideASubtreeMissesAndOutsideReplays`, `aReplayKeepsTheAnimationStoresEntriesSoTheNextChangeAnimates`, `aReplayTouchesItsRastersSoTheyAreNotDropped`, `aReplayedFrameKeepsItsAnimatedColourSlotsAlive`, `aReplayedHitboxKeepsTheRankingAtAnOverlap`, `aRetainedFrameEqualsAFreshFrameOverAScript`, `aSkippedDescendantsLaterChangeInvalidatesItsAncestorsRecord`, `aStaticLabelOverlayReplaysAndAMovingOneDoesNot`, `anObservedReadInPaintInvalidatesTheRecord`, `anObservedReadInPrepaintInvalidatesTheRecord`, `everyKeyComponentSeparates`, `everyLedgerChannelMakesTheSubtreeIneligible`, `theBracketNodeDragReplaysEveryUnchangedSubtree`, `theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires` |
| `versions-skipped` | the bind-journal version compare made `true` | RED | `aDescendantStateChangeFromAShortcutInvalidatesTheRecordByVersion` |
| `session-paint-dropped` | `RetainedSession.run` runs the paint body outside an observation window | RED | `anObservedReadInPaintInvalidatesTheRecord` |
| `session-build-dropped` | same, the build session | RED | `aChildGetterReadInvalidatesItsEquatableParentsRecord`, `aRetainedFrameEqualsAFreshFrameOverAScript` |
| `session-prepaint-dropped` | same, the prepaint session | RED | `anObservedReadInPrepaintInvalidatesTheRecord` |
| `timevarying-build-ignored` | `build.timeVarying` ignored in `retainedEntryRefusal` | RED | `aLiveAnimationNeverReplaysAndAnIdleKeyframeSubtreeDoes`, `everyLedgerChannelMakesTheSubtreeIneligible` |
| `taint-activeanimation` | `Frame.noteActiveAnimation` no longer taints the log | GREEN | - |
| `channel-customenv` | the custom-environment-key refusal removed | RED | `everyLedgerChannelMakesTheSubtreeIneligible` |
| `channel-surface-taint` | `drawSurface` no longer taints | GREEN | - |
| `channel-surface-ledger` | the `surfaceRequests` ledger channel removed | GREEN | - |
| `channel-portal` | `pushLayer` no longer taints | RED | `everyLedgerChannelMakesTheSubtreeIneligible` |
| `channel-statewrite` | `StateTable` write/`withState` no longer taints | RED | `aReplayedFrameKeepsItsAnimatedColourSlotsAlive`, `everyLedgerChannelMakesTheSubtreeIneligible`, `theBracketNodeDragReplaysEveryUnchangedSubtree` |
| `descendant-eval-ignored` | the `evaluationsSoFar` comparison in `EquatableComponent.requestGroupLayout` removed (`SB-AC`) | RED | `aSkippedDescendantsLaterChangeInvalidatesItsAncestorsRecord` |
| `channel-capturing-scope` | the capturing-scope taint in `processScopes` removed | RED | `aSubtreeHoldingATransitionIsIneligibleInFlightAndSettled` |
| `scene-replay-dropped` | the recorded scene ops not replayed | RED | `aBackdropInsideAReplayedSubtreeIsByteIdentical`, `aRetainedFrameEqualsAFreshFrameOverAScript`, `aSkippedDescendantsLaterChangeInvalidatesItsAncestorsRecord` |
| `marks-dropped` | the recorded `mark`s not replayed | RED | `aReplayedFrameKeepsItsAnimatedColourSlotsAlive` |
| `snapshot-per-element` | a ledger snapshot per element prepaint | RED | `aMissCostsTheOldWorkPlusTwoSnapshots` |
| `plain-switch-public` | `testingRetainedSubtrees` made `public` | RED | `thePlainImportCannotTurnReplayOff` |
| `plain-counters-public` | `RetainedCounters` made `public` | RED | `theRecordIsUnreachableFromAPlainImport` |
| `eviction-caller` | a caller of `GlyphAtlas.evictUnusedSince` added | RED | `theGlyphAtlasHasNoEvictionCaller` |
| `frame-stored-property` | a stored property added to `Frame` | RED | `everyFrameChannelIsClassified` |
| `environment-stored-property` | a stored field added to `EnvironmentValues` | RED | `everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant` |
| `touches-dropped` | the recorded animation-store touches not replayed | RED | `aReplayKeepsTheAnimationStoresEntriesSoTheNextChangeAnimates` |
| `noteboundary-height` | `|| boundary == 0` removed from `RetainLog.noteBoundary` (no final stream) | RED | `aReplayedHitboxKeepsTheRankingAtAnOverlap`, `aRetainedFrameEqualsAFreshFrameOverAScript`, `theBracketNodeDragReplaysEveryUnchangedSubtree`, `theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires` |
| `finalscene-always` | `finalScene` kept whatever the outer scopes are | RED | `aRetainedFrameEqualsAFreshFrameOverAScript` |
| `needsleaves-ignored` | `needsLeaves` ignored: the final stream replayed even into a live outer recorder | RED | `aSkippedDescendantsLaterChangeInvalidatesItsAncestorsRecord` |
| `pair-rects-interior` | `rects:` and `interior:` both constant | RED | `everyKeyComponentSeparates` |
| `pair-scale-displayscale` | the scale factor in the ambient key and `displayScale` in the environment fingerprint both constant | RED | `aRetainedFrameEqualsAFreshFrameOverAScript`, `everyKeyComponentSeparates` |
| `pair-contentsize-windowsize` | `contentSize` in the ambient key and `windowSize` in the environment fingerprint both constant | GREEN | - |
| `pair-surface-taint-ledger` | both the `drawSurface` taint and the `surfaceRequests` channel removed | RED | `everyLedgerChannelMakesTheSubtreeIneligible` |
| `pair-activeanimation-taint-ledger` | both the `noteActiveAnimation` taint and the `timeNotes` channel removed | RED | `everyLedgerChannelMakesTheSubtreeIneligible` |
| `hit-false` | the hit test `&& Int.random(in: 0...0) == 1` (never a hit) | RED | `aBackdropInsideAReplayedSubtreeIsByteIdentical`, `aChildGetterReadInvalidatesItsEquatableParentsRecord`, `aDescendantStateChangeFromAShortcutInvalidatesTheRecordByVersion`, `aDescendantStateChangeInvalidatesTheRecord`, `aLiveAnimationNeverReplaysAndAnIdleKeyframeSubtreeDoes`, `aMissCostsTheOldWorkPlusTwoSnapshots`, `aPointerOrPressOrFocusInsideASubtreeMissesAndOutsideReplays`, `aReplayKeepsTheAnimationStoresEntriesSoTheNextChangeAnimates`, `aReplayTouchesItsRastersSoTheyAreNotDropped`, `aReplayedFrameKeepsItsAnimatedColourSlotsAlive`, `aReplayedHitboxKeepsTheRankingAtAnOverlap`, `aRetainedFrameEqualsAFreshFrameOverAScript`, `aSkippedDescendantsLaterChangeInvalidatesItsAncestorsRecord`, `aStaticLabelOverlayReplaysAndAMovingOneDoesNot`, `aSubtreeHoldingATransitionIsIneligibleInFlightAndSettled`, `anObservedReadInPaintInvalidatesTheRecord`, `anObservedReadInPrepaintInvalidatesTheRecord`, `everyKeyComponentSeparates`, `everyLedgerChannelMakesTheSubtreeIneligible`, `theBracketNodeDragReplaysEveryUnchangedSubtree`, `theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires` |
| `coverage-ignored` | `old.coverageComplete` left out of the hit test | RED | `aFrameRightAfterAMissObservesAgainSoASecondWriteIsSeen` |
| `serial-ignored` | `old.contentSerial == entry.serial` left out | RED | `aReplayKeepsTheAnimationStoresEntriesSoTheNextChangeAnimates`, `aSkippedDescendantsLaterChangeInvalidatesItsAncestorsRecord` |
| `observedchange-ignored` | `!entry.observedChange` left out | RED | `aChildGetterReadInvalidatesItsEquatableParentsRecord`, `aRetainedFrameEqualsAFreshFrameOverAScript`, `aSkippedDescendantsLaterChangeInvalidatesItsAncestorsRecord`, `anObservedReadInPaintInvalidatesTheRecord`, `anObservedReadInPrepaintInvalidatesTheRecord` |
| `key-ignored` | `old.key == key` left out | RED | `aRetainedFrameEqualsAFreshFrameOverAScript`, `aStaticLabelOverlayReplaysAndAMovingOneDoesNot`, `everyKeyComponentSeparates` |

**Green mutants, each explained** (a green mutation is a broken instrument or the finding):

* `key-scale`, `key-contentsize`: the scale factor and the window size are also in `EnvironmentFingerprint` (`displayScale`,
  `windowSize`), so each is covered twice. `pair-scale-displayscale` reddens `everyKeyComponentSeparates` and the
  differential: the ambient part is redundant, not unpinned. **`pair-contentsize-windowsize` is green: no arm can separate the
  window's size**, because no scene byte of a retained subtree depends on it (the backdrop's region is computed by the renderer
  from the scene, not stored in it). Both parts stay, as the conservative key; the finding is carried to lane 2.
* `key-depths`: the clip depth, the clip base and the scope count are functions of the tree above the occurrence, which its
  identity fixes: no input moves one for one identity (a structural change is a new identity and a first record). An equivalent
  mutant by construction; kept as the cheap guard if a lane-2 graft ever moves a subtree.
* `key-rects`, `key-interior`: each is redundant with the other (the signature of the interior covers the top nodes too, and a
  single painting node has no interior, which the `flexRect` arm tries). `pair-rects-interior` is red (`everyKeyComponentSeparates`,
  arm `topRect`). **No arm separates the interior alone**: every input that moves an interior rect with the top rect fixed
  also moves a key part already held (a proposal, the environment, a `@State` version, an observation). Kept for lane 2's graft,
  where the top may not be laid out again; the claim "every part has a separating arm" in `AmbientKey`'s doc is weakened to "or is covered twice" for
  the parts named here.
* `taint-activeanimation`, `channel-surface-taint`, `channel-surface-ledger`: a taint hook and a ledger channel watch the same
  event (the snapshot compares the counters the hook raises); each alone is redundant, `pair-activeanimation-taint-ledger` and
  `pair-surface-taint-ledger` redden `everyLedgerChannelMakesTheSubtreeIneligible` (arms `spinner` and `surface`).

**What the first batch found, and the fix** (the first batch's greens that are now red): `key-offset` (arm `scroll`
added: the paint offset moves with no rect); `press-false` (the press test, shadowed by the hover test, now pinned with the
pointer dragged away while held); `versions-skipped` (the bind-journal version compare, shadowed by a pointer and a colour write,
now pinned by `aDescendantStateChangeFromAShortcutInvalidatesTheRecordByVersion`: a shortcut changes a descendant's `@State`
with the pointer, press and focus elsewhere); `session-build-dropped` (test 1.8's child set a colour, whose `$anim-color` slot
version hid the observation window: the child is text only now); `channel-capturing-scope` (arm: a `.transition` element keeps a
capturing scope open, so the occurrence is ineligible **settled too**, `aSubtreeHoldingATransitionIsIneligibleInFlightAndSettled`);
`touches-dropped` (a legacy border's `$anim-border` track is the one animation-store touch paint makes: pinned by
`aReplayKeepsTheAnimationStoresEntriesSoTheNextChangeAnimates`); `plain-counters-public` (the guard now names the type, not a
member); `finalscene-always` (a `.compositingGroup().shadow` card joined the differential); `coverage-ignored` (1.8c: the frame
after a miss observes again). Two mutations of the first draft's list were skipped for a changed spelling and re-spelled.

**Verify mode as an instrument** (`SB-W`): run over the whole suite it trapped twice in the first reading, and both were findings.
(1) `SB-AC`: a parent that records in a frame where an equatable descendant's content is skipped by the content memo never
subscribes to that descendant's reads, and replayed a stale label when the descendant later changed (`anEqualComponentSkipsItsContent`
trapped; test 1.8b reproduces it with two leaves, and the mutation `descendant-eval-ignored` reddens it). (2) A verified hit
compared touch *counts* where a first sighting touches twice and a later frame once, and replaced the record with one whose
coverage was incomplete: now ids are compared and the old record stays. Run again: **3701 tests, 0 traps**; four tests that read
paint-skipped or nested hit counts are switched off under it (`rsVerifying`: a verified hit paints). A demonstration that it
catches what the key misses: with `key-opacity` mutated, `METALUI_VERIFY_RETAINED=1 swift test --filter everyKeyComponentSeparates`
traps in `finishRetainedPaint` with "replay differs from a fresh run at <path>: scene op ... rect(...)".


## §6 Counts

Measured on the final head of lane 1 (`f2a39999`, 2026-10-13), after `swift package clean`:

* **`swift build --build-system native --build-tests`: 0 `error:`, 0 `warning:`** but SwiftPM's deprecation notice; the default build
  system's `swift build --build-tests` also 0 `error:` and 0 `warning:`.
* **`swift test --build-system native --no-parallel`, unfiltered: 3705 tests** (baseline 3675 at `e85cb07a`: +30 tests), 0 goldens,
  **234 typecheck guards** (232 + the two of `RetainedSubtreeCompileGuards.swift`; the `Mirror` classification tests are not typecheck
  guards). The run read exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` (the screen is locked: each takes 61 s) and
  nothing else; `FR-J no-argument frame: succeeded=true`; 0 `error:` in the log.
* **`METALUI_VERIFY_RETAINED=1`, the same run: 3705 tests, the same five issues, no trap** (four count-reading tests are off under it,
  `rsVerifying`).
* The Linux root package in `swift:6.4-noble` (volume `metalui-root-retained-subtrees`, `swift build --build-tests` then `swift test
  --skip-build`): **218 + 9 + 40 + 25 + 209 + 79 + 22 tests, 0 failures** (the first number is `MetalUITestingTests`, which runs the
  retained-subtree tests on Linux with `rsSettle()`; the portable `MetalUILayout` signature tests are in the 209).
* `Backends/SDL` (macOS): `swift build $(python3 scripts/fetch-accesskit.py --print-flags)` completes; the only warnings are the linker's
  note that Homebrew's SDL3 was built for a newer macOS. Untouched by this branch; its tests were not re-run.
* Census **3510** (3492 + 18: `FrameWork`'s ten counters and the demo's eight public declarations); `closeout-inventory-check.sh` and
  `closeout-undocumented.sh` print nothing; divergences: none taken (152 live, labels 395-404 unused).
* The fourteen offscreen demo images: **0 px against `e85cb07a`, scenes identical, at `5ae374be` and again at `f2a39999`**
  (`docs/probes/demo-pixels/compare.sh <scratch> e85cb07a HEAD`; the controls separate as they should: 11 of 11).
  `DemoFrameDeterminismTests`' `Expected.swift` unedited; `MetalUILayout` imports only `MetalUICore` (3 imports), `MetalUIScene` only
  `MetalUIShaderTypes`; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green.
* The retained-subtree tests are 37 (filtered run: 37 passed). A count is stale the moment a test lands: re-measure.


## §7 Timing (dated measurements; the Mac is shared; no pin reads a time)

**Machine.** MacBookPro18,2 / Apple M1 Max / macOS 27.0.1 / Swift 6.4, 2026-10-13. **Shared with other workflows** (load average
2 during the release runs below, 20-30 during the builds before them): read ranges and ratios, never a single figure. Wall clock is
an instrument; no pin reads it.

**Release, the node drag, public API** (`zsh docs/probes/perf-baselines.sh release bracket`; 30 drags of 20 events per arm, per-frame
total including the harness's input and tick; three whole-process runs, the median of each; the "before" is the same script and
fixture against a `git archive` of `e85cb07a`):

| arm | before, ms (3 runs) | after, ms (3 runs) | change |
|---|---|---|---|
| `.value` | 7.448, 7.422, 7.403 (median 7.422) | 6.546, 6.534, 6.524 (6.534) | **-0.89 ms, -12.0 %** |
| `.environment` (nodes refused, divergence 346) | 7.622, 7.596, 7.579 (7.596) | 7.605, 7.608, 7.597 (7.605) | +0.01 ms: the refusal gets nothing, and costs nothing |
| `.panels` | 7.459, 7.453, 7.417 (7.453) | 6.520, 6.511, 6.519 (6.519) | **-0.93 ms, -12.5 %** |

Taken at `d6d4dd22`, load average about 2. **Re-taken at the final head** (`SB-AC` and the verify changes are in; load average 22 from
another workflow, so everything is slower): `.value` 7.648, 7.444, 7.435 (median 7.444) -> 6.733, 6.655, 6.677 (6.677), **-0.77 ms,
-10.3 %**; `.environment` 7.814, 7.625, 7.767 -> 7.871, 7.697, 7.783 (no change); `.panels` 7.645, 7.466, 7.620 (7.620) -> 6.555,
6.554, 6.681 (6.555), **-1.07 ms, -14 %**. The last frame of the final run reads `builds=1`, `elementPaints=178`, `retainedHits=32`,
`retainedMisses=0`, `retainedIneligible=0` for `.value` (1084 element paints without replay) and `elementPaints=110`, `retainedHits=34`,
`retainedIneligible=1` for `.panels`. (The `.environment` arm's nodes read `@Environment`, so the content memo refuses them and evaluates every frame, divergence 346:
21 hits, 1000 element paints.)

**Debug**, same script (two runs; the first is `--quick`): `.value` 54.79, 54.57, 54.59 -> 50.13, 48.76, 48.82 (-10.5 %); `.environment` 55.32,
55.09, 55.41 -> 55.42, 54.21, 54.08; `.panels` 54.03, 54.27, 54.65 -> 48.75, 48.22, 48.25 (-10.7 %). Debug paint is 61 % of a render
(spec §1), but the window's unretained parts (the top bar, the library `List`, the inspector in the `.value` arm; the graph panel in the
`.panels` arm) are most of it, so the replay's win is a smaller share there than the 29-of-32 hit count suggests.

**Phase shares, release** (the patched copy of this branch, `SB_RETAIN=1|0`, 30 drags x 22 frames, two whole-process runs each, ms per frame):

| arm | replay | build | layout kernel | prepaint | paint | sweeps | render | tick |
|---|---|---|---|---|---|---|---|---|
| `.value` | off | 2.127, 2.153 | 1.183, 1.190 | 0.798, 0.807 | **1.974, 1.985** | 0.19 | 6.285, 6.342 | 7.485, 7.537 |
| `.value` | on | 2.034, 2.136 | 1.153, 1.179 | 0.779, 0.813 | **1.158, 1.208** | 0.18 | 5.313, 5.536 | 6.461, 6.724 |
| `.environment` | off | 2.298, 2.279 | 1.200, 1.193 | 0.818, 0.813 | 2.001, 1.997 | 0.20 | 6.526, 6.492 | 7.746, 7.708 |
| `.environment` | on | 2.143, 2.261 | 1.151, 1.180 | 0.773, 0.814 | 1.907, 1.971 | 0.18 | 6.166, 6.431 | 7.321, 7.645 |
| `.panels` | off | 2.087, 2.122 | 1.176, 1.181 | 0.786, 0.798 | 1.960, 1.984 | 0.19 | 6.211, 6.291 | 7.383, 7.479 |
| `.panels` | on (before `SB-AB`'s tainted-recorder fast path) | 2.088, 2.227 | 1.165, 1.212 | 0.810, 0.852 | 1.443, 1.526 | 0.18 | 5.698, 6.022 | 6.875, 7.260 |

The replay removes **0.78 ms of 1.97 ms of paint** in `.value` (40 %), not the 80 % the element count suggests (1084 -> 178 element paints):
the rest of paint is the unretained window parts, the three occurrences that missed (the two wires rasterize 78 312 pixels on the CPU,
`GX-B`, every frame) and the replay itself (a `sample` of the `.value` arm put `replayPaint` at 3.3 % of frame time and the decision and key at
1.4 %). Build, layout kernel and prepaint did not move, as designed (the first build's sessions raised build by 0.12 and prepaint by 0.15 ms
before `SB-V`'s fix).

## §10 The lane 2 gate (`SB-C`)

Fixed before the reading: build plus layout kernel at or above 35 % of `render` in the `.panels` arm, release, after lane 1. **Reads
57 % in `.panels` (build 2.158 + layout 1.190 over render 5.698; `.value` 59.9 %: 2.085 + 1.166 over 5.425)**: the gate opens with a margin
of 22 points, and prepaint (0.8 ms, 14 %) joins the work lane 2 removes. Lane 2 (graft, journal, counted redo, prepaint replay, the subtree
placement memo) is designed in spec §9 and `SB-N`, `SB-O`, `SB-R` and is **not built in this lane**; `SB-AA` adds the paint-ambient problem
to its list.


## §8 GT-F, re-taken (`SB-P`)

`theOverlayCostIsLinearAndCounted` passes unchanged at every commit of the branch (N = 20 and 100: layout 0, one seam
measure and one `placeGlyphs` per label per frame, no raster or upload). The pair `aStaticLabelOverlayReplaysAndAMovingOneDoesNot`
(N = 20 and 100, five camera frames, every label an `.equatable()` component under an `.offset`): **static labels** are all
hits after warm-up and cost **0 `placeGlyphs` and 0 seam measures**; **moving labels** (the overlay case GT-F is about) all
miss on the offset's paint scope and cost the unchanged `frames * n` of each. **`MetalDrawContext.drawText` and its SDL twin
stay deferred** (`SB-P`): retained subtrees remove the cost of a label that does not move and none of one that does, which
is what a world-anchored label is; translated replay (`SB-H`, carried to lane 2) is the owner, and `drawText` is re-taken there.

## §9 Slice 1's costs in release (owed by record §104 §4)

Measured in the design phase (spec §12; the instrument is `docs/probes/retained-subtrees/phase-timing.patch`,
`bracketSlice1Costs`) on the fixture's `.value` arm, release, per drag frame, three whole-process runs, shared Mac: the
signature pass (844 nodes hashed) costs **0.14-0.20 ms** (0.16-0.23 us per node, 2.1-2.5 % of a 6.2-7.9 ms render, 11-13 % of
the memo-on layout phase); the layout memo's net saving is **0.19 ms** per frame (3 % of render; gross 0.32-0.38 ms, the pass
paid 42-51 % of it); the content memo's `==` costs **0.008-0.009 ms** per frame (32 comparisons, 0.25-0.3 us each) and the
content memos save 0.06-0.11 ms net (29 skipped getters at 2-4 us). Neither is a reason to change slice 1; this item
exists because their combined win on the node drag is 4 % of a frame.

## §11 Carried, with owner and reason

| item | reason | owner |
|---|---|---|
| prepaint replay (hitboxes, focus, accessibility, tallies) | the decision cannot be taken at prepaint: paint-only ambient (`SB-AA`); the first build's code and the tests that found it are the branch's commit `0683d847` | lane 2 / C14b-2 |
| the build skip, the graft, the journal, the counted redo | the gate opened (§10); carried whole (`SB-AE`): none lands alone | C14b-2 |
| the subtree placement memo | **built** in lane 2 (§13, `SB-AD`), without translation | - |
| translated replay (a moved subtree without a miss) | float association, `SB-H` | C14b-2 |
| read-only `withState` so a `TextField`, `ScrollView` and `List` can replay | the table cannot tell a read from a rewrite | C14b-3 |
| popovers, presentations, `GPUSurface` inside a retained subtree | per-frame requests, `SB-J` | C14b-3 |
| custom environment keys | no equality | C14-c |
| finer scopes (modifier, `List` row, `ForEach` element) | no equality | C14-d |
| `drawText` | `SB-P` | C14b-2 |
| divergences | none taken; labels 395-404 unused | - |

## §12 Instruments, demo, human checks

* `METALUI_VERIFY_RETAINED=1` (`SB-W`): run the whole suite under it once (§6); a trap names the first difference between the
  record a replay would have used and a fresh one. `METALUI_TRACE_RETAINED=1`: why a record missed, why an occurrence was ineligible
  and which session fired. `zsh docs/probes/perf-baselines.sh release bracket` (three runs, the median): the public-API harness
  prints the retained counters on the last frame; the before column is the same script against a `git archive` of `e85cb07a`
  with `BracketFixture.swift` and the harness copied in. `docs/probes/retained-subtrees/phase-timing.patch` (README there) gives
  the phase shares; the patched copy of this branch toggles replay with `SB_RETAIN=0`.
* Demo: `METALUI_RETAINED_DEMO=1 swift run MetalUIDemo`: drag a node, read hits / misses / ineligible of the last frame; untick
  "Replay" and the same drag reads 0 hits.
* Human checks `docs/verification/human-checks.md` group **SB** (SB1-SB6), not run: an agent cannot.


## §13 Lane 2: the subtree placement memo (`SB-AD`, `SB-AE`)

The gate read 57 % (§10) and lane 2 landed **one of its four parts** behind unchanged semantics: marked subtree roots restore
their placement in place. The graft, the `StateTable` journal, the counted redo and prepaint replay are carried together
(`SB-AE`: none can land alone; no graft was prototyped, so "a graft is cheaper than the build" is untested).

**What it is.** `LayoutTree.markPlacementRoot` (`package`), called by `EquatableComponent` for the top-level nodes of each
retained occurrence while retention is on; in `placeNative` a marked node with a signature and children asks `LayoutMemo` for
`PlacementKey(signature, proposal, bounds)` (all four bounds fields bit for bit, origin included); a hit writes the recorded
unrounded pre-order rects and returns, a miss places as before and stores on the way out. No translation (`SB-H`).
Verify mode (`LayoutMemo(verifies:)`, `METALUI_VERIFY_LAYOUT_MEMO=1`) recomputes every subtree hit from zeroed rects and traps.
Counter `memoSubtreeHits` (`BuildWork`, `FrameWork.layoutSubtreeHits`, census 3510 -> 3511).

**What the first run found.** (1) Nothing restored: every marked subtree had no signature because a `Color` used as a view
and an empty legacy container were unkeyed leaves (a temporary print of the unkeyed leaves under each marked root, then of the registrar's caller). Both are now keyed (`ColorLeafKey`, `EmptyContainerLeafKey`: pure functions of the proposal), which moved slice 1's counts
for any tree holding either: the baseline test's retention-off layout literals 81/805/527/1106/30 at `e85cb07a` read 52/366/217/1258/55
(`theBracketNodeDragRebuildsTheWholeWindow`), and `aStretchedBranchingTreeRegistersAHandDerivedAmountOfNativeWork` (hand-derived
without a memo; its `Box()` leaves are empty containers) now renders with `layoutMemo: false`, a parameter `LayoutDifferential.render`
gained, so its derivation stands. (2) The prediction "at least 15 restores" was wrong: **11**, because 11 of the 20 nodes are on screen
(canvas cull) and the list, inspector and top bar hold unkeyed leaves. (3) `.offset` is a render effect, so the drag never moves a
node's *layout*: the fixture cannot see the origin in the key; the resize arm can (`aResizedWindowPlacesLikeAFreshOneAtEverySize`).
(4) Restores do not refresh the measure entries below them (they lapse after two frames), so the first miss after a rest re-measures
its subtree: frame 0 of the drag measures 135 leaves against 52 (`SB-AE` 1, pinned).

**Pins and their red lines (stub: the marks recorded, the kernel never consulting them).**

| pin | red before | mutation (§13 table) |
|---|---|---|
| `aMarkedSubtreeInTheSamePlaceIsRestoredNotPlaced` | `memoSubtreeHits == 1` read 0 | M1, M2, M11, M14 |
| `aRestoredSubtreeIsNotDescended` | requests not fewer than the unmarked control's | M1, M5, M11, M14, M15 |
| `aMovedSubtreeIsPlacedFreshNotRestored` | passes on the stub (a mutation instrument) | M3 |
| `aDifferentProposalOverTheSameBoundsIsPlacedFresh` | passes on the stub | M4 |
| `onlyAMarkedKeyedSubtreeIsRestored` | passes on the stub | M5, M6 |
| `aVerifiedRestoreStillCountsAndAgrees` | count read 0 | M1, M11, M14 |
| `aRestoreIsRoundedLikeAFreshPlacement` | `restored == 3` read 0 | M1, M2, M7, M11, M14 |
| `aVerifiedRestoreThatDiffersFromAFreshPlacementTraps` (exit test) | (new with the verify branch) | M1, M8, M11, M14 |
| `aDragFrameRestoresTheUnmovedOccurrencesPlacement` (value, panels) | `layoutSubtreeHits == 11` read 0 (6 issues) | M1, M5, M6, M10-M15 |
| `aRestoredDragEqualsAFreshOneAtEveryStep` (value, panels) | `restores > 0` read 0 (2 issues) | M1, M2, M6, M7, M10-M12, M14 |
| `aResizedWindowPlacesLikeAFreshOneAtEverySize` (value, panels) | passes on the stub | M3 |
| `aColorAndAnEmptyContainerKeepTheirAncestorsMatchable` | 0 root hits | M12, M13 |

Red lines at the stub commits (kernel): `memoSubtreeHits == 1` (read 0) in tests 2.1 and 2.6, `aRestoredSubtreeIsNotDescended` (deepest level;
re-specified after the mutation batch showed M15 survived), `restored == 3` in the rounding test; (window): `f.layoutSubtreeHits >= 15`,
`f.layoutMemoHits < g.layoutMemoHits`, `f.layoutCacheHits < g.layoutCacheHits` for both arms and `restores > 0` for both arms
(8 issues).

**Mutations** (each run on the committed tree, the full unfiltered suite with `AppKitPresentationTests` skipped, the mutated file
restored from git, `git status --short` clean after each; spelling in `/tmp` scripts, reproduced here):

| id | mutation | tests reddened |
|---|---|---|
| M1 | lookup disabled (`order.count < 0` added to the restore guard) | the five kernel pins above + `aVerifiedRestoreThatDiffers...` (exit status success) + both window pins + `theBracketNodeDragReplaysEveryUnchangedSubtree` (16 issues) |
| M2 | restore writes nothing | `aMarkedSubtree...`, `aRestoreIsRounded...`, `aRestoredDragEquals...` (24), `aRetainedFrameEqualsAFreshFrameOverAScript` (37), `aBackdropInsideAReplayedSubtreeIsByteIdentical`, `lifecycleAnimationAndListInsideAMemoizedComponent`, `theBracketNodeDragReplays...` (21), `theRetainedSubtreeDemoReplays...` (113 issues) |
| M3 | key origin zeroed | **first batch: only `aRetainedFrameEqualsAFreshFrameOverAScript` (5)**: the kernel pin did not separate (the proposal moved with the origin) and the drag never moves layout. After the rewrite (trailing alignment, centred root) and the resize arm: `aMovedSubtreeIsPlacedFreshNotRestored` (3), `aResizedWindowPlacesLikeAFreshOneAtEverySize` (6), `aRetainedFrameEqualsAFreshFrameOverAScript` (5) |
| M4 | proposal ignored in the key | `aDifferentProposalOverTheSameBoundsIsPlacedFresh` (3) |
| M5 | every node treated as marked (first spelling kept the `isEmpty` fast path, so the unmarked arm's empty set never reached it: a no-op mutant; second spelling `if true`) | `aDragFrame...` (8), `aRestoredSubtreeIsNotDescended` (2), `onlyAMarkedKeyedSubtreeIsRestored`, `everyProductionRootsDeepestNativeLevelIsMeasured` (8), `oneChangedTextRemeasuresOnlyItsPath` (7), `theBracketNodeDragRebuildsTheWholeWindow` (9), `theBracketNodeDragReplays...` (38 issues) |
| M6 | a missing signature hashed as a constant | `onlyAMarkedKeyedSubtreeIsRestored`, both window pins (the restores run over unkeyed subtrees and miss the differential), `theBracketNodeDragReplays...` (20) |
| M7 | restore rounds x and y | `aRestoreIsRoundedLikeAFreshPlacement` (3), `aRestoredDragEquals...` (24), `aRetainedFrameEqualsAFreshFrameOverAScript` (21), `aBackdropInsideAReplayedSubtreeIsByteIdentical` (49) |
| M8 | verify branch not consulted | `aVerifiedRestoreThatDiffersFromAFreshPlacementTraps` (2) |
| M10 | occurrences not marked | `aDragFrame...` (6), `aRestoredDragEquals...` (2), `theBracketNodeDragReplays...` (2) |
| M11 | `markPlacementRoot` inserts nothing | the kernel pins (except 2.3-2.5, which pass without a hit) and both window pins (16) |
| M12 | `Color` unkeyed | `aColorAndAnEmptyContainer...`, `aDragFrame...` (8), `aRestoredDragEquals...` (2), `theBracketNodeDragRebuildsTheWholeWindow` (15), `theBracketNodeDragReplays...` (29) |
| M13 | empty container unkeyed | `aColorAndAnEmptyContainer...`, `aDragFrame...` (6), `theBracketNodeDragRebuildsTheWholeWindow` (12), `theBracketNodeDragReplays...` (22) |
| M14 | nothing stored | as M11 (16) |
| M15 | restore falls through to the placement below | first batch: `aDragFrame...` (4) and `theBracketNodeDragReplays...` (2) only (`aRestoredSubtreeIsNotDescended` survived: its control had a warm memo that hit the whole root); after the control was re-specified: those + `aRestoredSubtreeIsNotDescended` (7) |

Instruments that found the survivors: M3 and M5 and M15 each left a kernel pin green in the first batch; each was re-specified (the
tests are `SubtreePlacementTests.swift` 2.2, 2.3, 2.5) and the three mutations re-run. Verify modes over the whole suite:
`METALUI_VERIFY_RETAINED=1` 3707 passed; `METALUI_VERIFY_LAYOUT_MEMO=1` trapped nothing and read exactly three issues (one per arm), the baseline test's
seam-measure count (`counting.measures == 2898`), which a verified hit changes by design (guarded with `layoutMemoVerifying` as the
other seam pins are).

**Timing** (dated measurements, 2026-10-13, M1 Max, **shared Mac**; release, `zsh docs/probes/perf-baselines.sh release bracket`, three
whole-process runs, per-frame total including the harness's input and tick; never a pin):

| arm | `e85cb07a` | lane 1 | lane 2 (`88b9e7b4`, three runs) | lane 2 vs `e85cb07a` |
|---|---|---|---|---|
| `.value` | 7.422 | 6.534 | 6.062, 6.044, 6.061 (median 6.061) | **-1.36 ms, -18 %** (lane 2 alone -0.47) |
| `.environment` (nodes refused) | 7.596 | 7.605 | 7.504, 7.489, 7.491 (7.491) | -0.11 ms, -1.4 % (the key widening only) |
| `.panels` | 7.453 | 6.519 | 6.052, 6.019, 6.039 (6.039) | **-1.41 ms, -19 %** (lane 2 alone -0.48) |

Counted: the harness's last frame reads `measureCalls=52 cacheHits=331 cacheMisses=162` (`bracket_*`); the baseline test's mid-drag frame
reads, retention off, 52 / 366 / 217 with 1258 memo hits and, retention on, 331 cache hits and 362 memo hits with 11 restores
(`aDragFrameRestoresTheUnmovedOccurrencesPlacement`).

**Debug**, same script (`debug --quick bracket`, three runs, ms per drag frame): `.value` 46.619, 46.842, 46.722 (median 46.722; 54.57 at `e85cb07a`,
48.82 after lane 1), `.environment` 54.054, 54.410, 53.163 (54.054; 55.09, 54.08), `.panels` 46.617, 45.921, 45.962 (45.962; 54.27, 48.25):
**-14 % and -15 %** against `e85cb07a` on the two arms that retain.

**Counts** (final head of this lane, after the commit that fixed the Linux modifier, 2026-10-13; the screen is locked, so
`AppKitPresentationTests` is skipped by `--skip`, as its `NSOpenPanel` sheets time out there): `swift build --build-system native --build-tests`
0 `error:`, only SwiftPM's deprecation notice; **`swift build --build-tests` (default build system) 0 warnings**; `swift test
--build-system native --no-parallel --skip AppKitPresentationTests`: **3708 tests in 3 suites passed**, 0 `error:`, `FR-J no-argument
frame: succeeded=true`; the same under `METALUI_VERIFY_RETAINED=1` 3708 passed, and under `METALUI_VERIFY_LAYOUT_MEMO=1` 3708 passed. New pins:
8 kernel tests (`SubtreePlacementTests`), 7 window cases (`RetainedPlacementTests`, arguments counted), no typecheck guard (all `package` API
behind `package` access; guard 1.13's plain-import check is unchanged). Census **3511**; `closeout-inventory-check.sh` and
`closeout-undocumented.sh` print nothing. The Linux root package in `swift:6.4-noble` (volume `metalui-root-retained-subtrees` mounted at
`/work/.build`: a volume built under another module-cache path fails with "missing required module 'SwiftShims'"): **226 + 9 + 40 + 25 + 217 + 79 + 22
tests, 0 failures** (`MetalUITestingTests` first; the kernel pins are in the 217). **One fix to lane 1's test:** `aDescendantStateChangeFromAShortcutInvalidatesTheRecordByVersion` sent
`.command` for a shortcut whose default is `.primary` (control off Apple) and failed on Linux; it now sends `.primary` (value-identical on macOS).
`Backends/SDL` untouched. The fourteen offscreen demo images: **0 px against `e85cb07a`, scenes identical, at `d7c7297b`** (controls 11 of 11).
`MetalUILayout` imports only `MetalUICore`; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green.

**Not changed:** pixels (the fourteen offscreen images 0 px against `e85cb07a`, scenes identical, at `d7c7297b`; table in §6's method);
a tree with nothing marked (retention off, no `.equatable()`) is slice 1 byte for byte except for the two keyed leaves.
