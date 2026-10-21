# 133 - Retained zoom (C14-i), fillet-drag profile and `@FocusState` under `.equatable()`

Branch `perf/retained-zoom` from `1bdead8d`, merged with master `11dca65e` (§136 sample app, §137 SDL GPU gaps; docs and `Examples/`/`Backends/SDL` only, no overlap). Not a plan task: item C14-i of the gpui-gap list, round 2, requested 2026-10-21 after MetalCreator's
zoom and fillet-drag benches. Spec `docs/superpowers/specs/2026-10-21-retained-zoom-design.md` (status: built); rulings `RZ-A`...`RZ-T` in `docs/superpowers/2026-10-21-retained-zoom-decisions.md` (next `RZ-U`).
Class: value-identical, **no public API, no census change, no divergence label taken** (625-634 reserved, unused; divergence 346 narrowed in place). Two lanes on disjoint files; lane 1 is section 1, lane 2 section 2.
No SwiftUI probe: no observable behaviour moves (the facts leaned on, divergence 106 and hitboxes following the transform, were probed in `GX-`); the oracle is differential against a window with retention off, plus `METALUI_VERIFY_RETAINED=1`.

## 1 Lane 1 - retained zoom (`RZ-A`...`RZ-R`)

**What landed.** A render-effect scale change (any affine change of the effect above an `.equatable()` occurrence: scale, rotation, translation) now **replays the paint, replays the prepaint and grafts** where it used to refuse `effectNotTranslation`, rebuild and re-prepaint, redo the frame
and back prepaint replay off for eight builds. The mechanism needed no CPU re-pointing (`RZ-A`): a replayed record goes through `processScopes` with the **live** scopes, exactly as the translated replay did, so a flattening effect maps its numbers and a non-flattening one picks its `MUITransform` at
`insertIntoScene` from the live scope; text and images are resampled under a scale (divergence 106), and vector rasters (path, gradient, shadow, blur) reach `RasterAnchor`-keyed `pathImage`/`gradientImage`/`shadowItem` at insert, so a new scale is a new key with raster work equal to a fresh frame's (`RZ-C`, Z4: no raster refusal).
- `ReplayKey.differsOnlyByEffectAffine(from:)` and `PrepaintExtras.change(from:)` admit a difference confined to the six affine numbers of `.effect` scopes (and the inverse's six) with equal flattens class, alpha, entry depth, outer clip, `hasInverse`, saved clip base, scope and effect count and no shadow or blur on a differing scope (`RZ-B`); the pure translation keeps its arm byte for byte.
- The prepaint effect vector gains index 18, `effectFlattens` (appended: 0...17 unmoved), so a class change refuses at prepaint as it does at paint (`RZ-M`).
- `translatedHitboxes` runs with no delta for an affine change (ambient inverse swapped for the current one, `AT-F`; hitboxes of an effect the occurrence opened walk their recorded steps, `RL-I`; the delta arm refuses `hitboxes`); accessibility recomputes through `translatedAccessibility` (`AT-A`); a geometry note re-runs on a rebuilt proxy (`RL-E`) and a note holding a **named space** refuses `geometryNamedSpace` (`RZ-D`, `RZ-E`).
- The pointer is read against the **moved** hitboxes in both effect arms (`RZ-O`): a carried, un-grafted node runs its prepaint instead of costing a redo.
- `effectNotTranslation` is **retired**; every refusal is named in the existing `retainedTranslationRefusedReasons`: `effectFlatteningChanged`, `effectClipChanged`, `effectInverseChanged`, `effectScopeChanged`, `effectCountChanged`, `prepaintContextChanged`, `geometryNamedSpace`, `presentationAnchor`, `contextMenus`, `hitboxes` (`RZ-B`, `RZ-F`, `RZ-N`). No new counter (`RZ-G`).
- Source: `Frame.swift`, `RetainedPrepaint.swift`, `RetainedSubtree.swift`, `RetainedTranslationCarries.swift`; the demo gains a zoom strip of ten occurrences (`RetainedSubtreeDemo.swift`, `METALUI_RETAINED_DEMO=1`).

**Pins** (new `Tests/MetalUITestingTests/RetainedZoomTests.swift`, fixture `ZoomFixture.swift`: ten `.equatable()` nodes of text, rect, stroked path and accessibility labels under `.scaleEffect` + fixed `.offset`, stepping 1.0, 1.1, 1.21; all but the last two compare a retaining window against a twin with retention off): Z1 `aZoomStepGraftsWithoutARedo` (grafts > 0, redos 0, requests O(changed)),
Z2 `aZoomPublishesTheFreshAccessibilityTree` (4 arms, non-dyadic scales included), Z3 `aZoomedNodeIsHitWhereItIsDrawn`, Z4 `aStrokedPathUnderAZoomIsRerasteredNotStale` (3 steps), Z5 `anEffectChangeThatIsNotAnAffineMoveIsRefusedByName` (one arm per refusal name), Z6 `aRotationStepIsReplayedExactly`, Z7 `aHitboxInsideAnEffectTheOccurrenceOpenedFollowsTheZoom`,
Z8 `aZoomThatCarriesTheContentUnderAStationaryPointerRunsThePrepaint`, Z9 `aZoomBeforeAndAfterOnTheBracketFixtureIsReported` (the report test, no assertions by design), Z10 `aPurePanStillTakesTheTranslationArm` (2 scales; a context menu on every node, which the affine arm refuses and the translation arm does not, so a pan misclassified as affine shows).
**Red at `1bdead8d`** (commit `18cd577e`, before the source change `86eab87d`): the pins' refusal expectations (grafts 0, redos, `effectNotTranslation`) failed; Z9 reports. No new typecheck guard (no public declaration).
**Existing pins amended in place with their reasons** (`RZ-Q`): `aScaleChangeRefusesByName` became `aScaleChangeIsAnAffineReplayNotARefusal`; the `rotation` arm of `everyKeyComponentSeparates` (a rotation now replays like the offset arm); `aGeometryNoteUnderAChangedRenderEffectMissesAndDelivers` became `...IsRecomputedAndDelivers`;
`theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires` (+10 occurrences; skipped under `METALUI_VERIFY_RETAINED=1`, where it reads 0 misses at `1bdead8d` too, a pre-existing fact).

**Measured** (counts, debug; `RZ-R`). Zoom fixture, ten nodes, one step: element requests **115 to 5**, grafts **0 to 10** per step, redos **1 to 0**, backoff 3 to 0; the last step's frame: element prepaints 9 of 119, paints 10 of 160, 10 translated paints, 10 prepaint hits; the stroked path's raster work equals a fresh frame's. The bracket fixture has no zoom axis (its canvas pans): its pan line reads
195 requests, 220 prepaints, 258 paints, 10 grafts, 0 redos, **identical to `1bdead8d`**. MetalCreator's own 1857-request zoom-50-warm is not reproduced here (app code outside this checkout); the fixture's per-node arithmetic is the predictor.

**Mutations** (verifier's, full unfiltered with `AppKitPresentationTests` skipped, each restored, `git status --short` clean after):

| mutation | reddened |
|---|---|
| M1 `differsOnlyByEffectAffine` false for `.affine` (paint arm refuses) | Z1, Z2 x4, Z3, Z6, `aScaleChangeIsAnAffineReplayNotARefusal`, Z8, the geometry-note pin, `everyKeyComponentSeparates` x15 |
| M3 `translatedHitboxes` re-points an ambient hitbox at the recorded inverse | Z1, Z3, Z2 x4, Z4 x3, Z6, the scale pin, Z8, Z10 x2, the pan-under-effect pins (`aPanUnderAnEffectGraftsWithAccessibilityOn`, `...PublishesTheFreshTree` x4, `aPanThatCrossesTheClipRecomputesTheVisibleFrame`), `aTranslatedReplayEqualsAFreshFrameAtEveryScale` x10 |
| M4 `translatedAccessibility` keeps the ledger's frames | Z1, Z3, Z7, Z2 x4, Z4 x3, Z6, the scale pin, Z8, Z10 x2, `anEffectOpenedInsideTheOccurrenceIsRecomputedFromItsSteps` x2, `aNestedEffectAccessibilityRecordIsRecomputedAtScaleTwo` x2, the pan pins, `everyKeyComponentSeparates` x15, `theAccessibilityNodeRetentionSlotFollowsAReplay` |
| M6a the flattens-class equality dropped in `change(from:)` and `effectRelation` | Z5's `flattensChanged` arm only (its refusal expectation; the frame stays equal to a fresh one, `RZ-M`) |
| M8 the moved-hitbox pointer read disabled | Z8 |
| M9 the named-space guard in `translatedGeometryNotes` disabled | Z5's `namedSpaceNote` arm |

The implementer's own M2 (`change(from:)` refuses affine), M5 (path replayed from the old stream), M6b-M6e (clip, anchor, context-menu arms singly), M7 and M10 reddened named pins (reported by the implementer, not re-run by the verifier; the path-raster claim rests on Z4 plus M5).
Verifier's findings, minor: Z7 ends in `_ = replayed` and is reddened only through M4's broken click and tree, not by a rebuild (candidate: assert `replayed > 0`); the Linux image and the demo launch were not re-taken on the lane's final tree (no `Backends/SDL`, shader or `MetalUIRender` file changed; the screen was locked).

**Hazards.** `effectNotTranslation` no longer exists: a dashboard or doc that greps the reasons table for it reads 0 for ever (the new names replace it). The prepaint effect vector is positional: index 18 is appended and a future entry appends. Z5's `flattensChanged`, `presentationAnchor` and `contextMenus` arms
test conservative refusals (`RZ-M`, `RZ-P`); a lift is a deletion plus the arm's amendment, with the equal-frame evidence in `RZ-M`/`RZ-P`.

## 2 Lane 2 - fillet-drag profile and `@FocusState` (RZ-H, RZ-I, RZ-S, RZ-T)

### (a) Fillet drag: no framework cause, no source change

`FilletDragFixture` (six `.equatable()` panels of text, rect, stroked path and six rows; a slider; a readout `Text` outside every panel that changes every frame; scale 2, an 8-step drag, 9 frames) in five arms.
Per frame, retained against retention off (counts, debug build):

| arm | requests | getters | misses | grafts | redo / refusals |
|---|---|---|---|---|---|
| sliderOutside | 40 (+189 skipped) of 229 | 0.9 | 0.9 | 5.1 | 0 / none |
| sliderInside (pressed panel) | 44 of 229 | 0.9 | 1.0 | 5.0 | 0 / none |
| observedRead | 40 of 229 | 0.9 | 0.9 | 5.1 | 0 / none |
| sliderEverywhereObjects (one `@Observable` per panel) | 44 of 239 | 0.9 | 1.0 | 5.0 | 0 / none |
| sliderEverywhere (one array property) | **217 of 239** | 0.9 | **5.4** | 0.6 | 0 / none |

The reasons tables (`retainedIneligibleReasons`, `retainedTranslationRefusedReasons`, `contentRefusals`) are empty in every arm; the trace names the one dragged panel's miss (`serial`, `interior`, `versions`; with a slider inside it also `observed`, `pointer/press/focus`: by design). The only arm that costs what MetalCreator's 888 suggests is a
shared observable collection: a write to one element is an observed change of every panel whose binding read the array (`observed` on each, `RZ-S`). **By design**, `.equatable()` observation is per property; the lead for MetalCreator is to give each node's parameters its own object. **MetalCreator's own 888 is not reproduced here.** Pins F1: `theFilletDragReasonsAreProfiled` (5 arms) and
`theFilletDragFrameEqualsAnUnretainedOne` (5 arms), characterizations (nothing moved, so none can be red at the merge base).

### (b) `@FocusState` is memoized by its slot's version (C14-c2)

`StateBinder` puts a `@FocusState` ordinal among the memo's slots; `memoShape` no longer refuses. The `$state<n>` slot is written with a version bump by `reconcile` on every focus change the window applies, which is the changed reading. **The planned re-note on a memo skip is not built** (`RZ-T`): `enterComponent` binds (and notes the focus state) before the memo decides, and a graft's journal arm covers a **nested** component's state.
Red at `f2ba9def` (the commit before): F2, F3, F4 (evaluations), F6, F7 reddened on `contentRefusals` and every-frame evaluation; F5 was green (refused components are trivially right). Pins `FocusStateMemoTests`: F2 `aFocusStateComponentIsSkippedWhileFocusIsUnchanged`, F3 `aFocusMoveReEvaluatesExactlyTheReadersOfTheMovedState`, F4 `aPendingFocusWriteAppliesToAComponentThatWasSkipped`,
F5 `aSkippedFocusStateIsStillReconciled`, F6 `aGraftedFocusStateComponentReconciles`, F6b `aPendingWriteWhileGraftedIsApplied`, F7 `aFocusReaderUnderRetentionRepaintsWhenFocusLeaves`; the replaced `aFocusStateComponentStaysRefused` is gone. Each compares a retaining window with a twin of the same tree (memo and retention off) on scene, accessibility tree, hitboxes, tab order and bounds.

**Mutations (filtered to the set named, each restored from git, `git status` clean after):**
- M1 `if false, let stateOrdinals = memoShape` (everything refused): F2, F3, F4, F6, F7 red.
- M2 focus ordinals left out of the entry's slots: F3, F4, F5, F6, F7 red.
- M3 `table.noteFocusState` removed from `FocusState.bind`: F3, F5, F6 red (F4 stays green: a click's own frame binds).
- M4 the `.focusState` arm of `RetainedGraft`'s journal replay removed: F6b red (it needs a nested component: with the state on the grafted occurrence itself `enterComponent` binds first, and the mutation is invisible, found by measurement and fixed in the pin).
- M5 `FDPanel.==` ignoring its value: `theFilletDragReasonsAreProfiled` red (the twin carries the same `==`, so the equality pin cannot see it).
- M6 `Entry.observedChange` forced `false`: `theFilletDragReasonsAreProfiled` red (the array arm's misses vanish).

**Divergence 346** narrowed in place (the `@FocusState` clause removed, pins renamed). No label taken, no public API, no census change (`FrameWork.contentRefusals`'s doc comment amended).

### Verification (lane 2 tree, debug)

Native unfiltered run on a locked screen: **4134 tests in 5 suites, exactly the five `AppKitPresentationTests` sheet issues of `CI-AF`, nothing else**, `FR-J no-argument frame: succeeded=true`, 0 `error:`. With `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` and `AppKitPresentationTests` skipped: 4125 passed, 0 issues.
Test arithmetic: lane 1's tree + 6 focus tests (F2-F7) + F6b - the replaced W8 + 10 fillet cases.

## 3 Verification on the merged tree (master `11dca65e`)

`swift package clean`, `swift build --build-system native --build-tests`: 0 `error:`, the only `warning:` SwiftPM's deprecation notice. Native unfiltered `swift test --build-system native --no-parallel` on a **locked screen**: **4138 tests in 5 suites, 5 issues, exactly the five `AppKitPresentationTests` sheet issues of `CI-AF`** (`appKitCancelledDialogArrivesAsQueuedInput`, `appKitDismissPresentationEndsTheSheetAndAnswersNothing`,
`appKitOpenDialogIsASheetWithTheDeclaredTypes`, `appKitSaveDialogCarriesTheNameTypesAndExportPrompt`, `appKitSecondDialogWhileASheetIsUpAnswersFalse`) and nothing else; `FR-J no-argument frame: succeeded=true`. Arithmetic: master's 4120 + lane 1 (4117 to 4127) + lane 2 (4127 to 4135) + the three root tests §136 added = 4138 (the lanes' 4127 and 4135 were measured before the merge).
**No typecheck guard added** (no public declaration; 251 as master's, not re-counted by a log line: guards are not printed). Inventory and undocumented scripts print nothing; census unmoved. The merge brought docs, `Examples/Jotter` and `Backends/SDL` only: the fourteen images were 0 px against `1bdead8d` on the lane-2 tree and `Sources/MetalUIRender` is untouched.
One comment fix at the merge: a stray `****` in `.equatable()`'s doc comment (`EquatableComponent.swift`), a comment only.

**Owed on the merged tree** (not taken: no `Backends/SDL`, shader or renderer file changed by this branch, the screen was locked): the Linux image (`metalui-portable`) for `MetalUITestingTests` and the portable tests, the `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` run (lane 1: 4118 passed, lane 2: 4125 passed, both before the merge), the default-build-system warning count (0 at both lanes), the demo launch and the human checks of group RZ.

## 4 Deferred, with owners

| Deferred | Reason | Owner |
|---|---|---|
| layout move and effect change together (`effectAndLayoutMoved`) | two translations are not combined (`FS-O`) | next C14 round |
| crossing the identity effect, a graft under a changed clip inside the effect (`effectClipChanged`) | counted by name, not met by a fixture | C14 follow-up, C14-d residue |
| lifting `RZ-M`'s flattens refusal and `RZ-P`'s anchor and context-menu refusals | conservative; the frame is equal without them (evidence in the rulings) | a round that wants a zoom through identity rotation or a popover under zoom |
| a named space under a zoom (`geometryNamedSpace`) | a named space moves by a translation only | C14 follow-up |
| MetalCreator's 888-request fillet drag | not reproduced; the lead is one `@Observable` object per node's parameters, an app-side check | MetalCreator |
| Z7 asserts no replay count | reddened only through M4's broken click and tree (verifier's note) | optional pin hardening |
