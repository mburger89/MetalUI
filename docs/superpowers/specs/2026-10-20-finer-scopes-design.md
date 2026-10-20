# Finer retention scopes - design

Item C14-d of the gpui-gap priority list (user request 2026-10-02; not a plan task), carried by record 104 section 7, 109 section 11
(`SB-AE`), 110, 120 (`EE-O`, C14-c4) and 121. Rulings: [`../2026-10-20-finer-scopes-decisions.md`](../2026-10-20-finer-scopes-decisions.md)
(`FS-`). Record: `../../record/126-finer-scopes.md` (Record phase). Branch `perf/finer-scopes` from `711ab9c4`.
Divergence labels 555-564 reserved: **none taken**. **Public API: none** in `MetalUI`; one `MetalUITesting` field (`FS-J`).

## 0 What the item turned out to be

The brief says: one changed row/element/node makes its enclosing `.equatable()` occurrence miss and every sibling rebuild. Measured at
`711ab9c4` (decisions doc, F1-F4) that holds for none of the three named cases when the row is an `.equatable()` component: 23 of 24 rows
hit, 8 element requests with the graft. It holds for two things the brief did not name:

1. **A row that moves** (a row inserted above, a header above that resizes, a scroll) misses **every** row: 171-190 requests, 172-191
   prepaints, 244-271 paints a frame, against 3 / 4 / 4 when nothing moves. Cause: `ReplayKey`/`PrepaintKey` hold absolute rects and an
   absolute interior hash, and `AmbientKey.offset` holds the scroll offset; only a **render-effect** translation (`.offset`, `RK-G`) is
   replayed moved.
2. **A `List` row** hits at paint but never at prepaint and never grafts (84 requests, 85 prepaints for 9 rows, nothing moving): its
   prepaint key's `suppression` part differs every frame.

So the item is two lanes plus a ruling: no implicit scopes (`FS-A`, `FS-B`).

## 1 Lane 1 - rows that participate (`FS-C`, `FS-H`)

**Goal.** An `.equatable()` row in a `List` (both branches) replays prepaint and grafts like the same row in a `VStack`; and C14-c4 is
settled. **Files** (`FS-L`): `List.swift`, `ListRows.swift`, `ForEach.swift` (read-only unless the cause is there), `EquatableComponent.swift`,
`RetainedGraft.swift`, `Frame.swift` (`accessibilitySuppressionExceptions`, `PrepaintExtras.suppression`), tests
`Tests/MetalUITestingTests/FinerScopesElementTests.swift` and `FinerScopesFixture.swift`, `Tests/MetalUITests/` for an internal pin.

**Steps.**
1. Port `FinerScopesMeasure` into `FinerScopesFixture.swift` (the scenarios, a `FrameWork` snapshot helper). Write the baseline pins at
   `711ab9c4` with the figures of the decisions doc (F1-F4) as literals; they are green and stay as the "before" record.
2. Root cause of the `suppression` mismatch: print each part of `PrepaintKey` once (a throw-away, reverted), with accessibility **on and
   off**, uniform and variable branch. Commit the diagnosis as a decision (`FS-M`).
3. Fix at the cause. Constraint: the AX tree, the hitboxes and the scene of a list row equal a fresh unretained window bit for bit
   (test 1.5). If the fix must widen a key or add a counter, say so in the decision.
4. C14-c4 (`FS-H`): mutation first (`uncomparableCustomCount == 0` replaced by `true`), full unfiltered suite and verify run; remove the
   conjunct if nothing reddens.

**Tests** (name; red before; mutation that must redden it):

| id | test | red before | mutation |
|---|---|---|---|
| 1.1 | `aChangedRowMissesAloneAndItsSiblingsReplayAndGraft` (`ForEach` in a `VStack`, graft on: 23 hits, 1 miss, 23 grafts, 8 requests) | green on arrival (F1) | `EquatableComponent`: `entry.observedChange = true` for every occurrence after any evaluation (the `SB-AC` kill applied to siblings) |
| 1.2 | `aStaticListOfEquatableRowsReplaysPrepaintAndGrafts(branch:)` for `.uniform` and `.variable` | yes: prepaint hits 0, grafts 0, requests 84 | restore the cause (a fresh exception id / flag in `suppression`) |
| 1.3 | `aChangedListRowMissesAloneAndTheOthersGraft(branch:)` | yes: grafts 0 | as 1.2; plus `graftRecord` guard `old.prepaint` replaced by `nil` |
| 1.4 | `aListRowReplayEqualsAFreshWindowWithAccessibilityOnAndOff` (scene, hitboxes in order, AX tree, Tab order, against `testingRetainedSubtrees = false`) | green after the fix; red under the mutation | the fix reverted in the direction that drops a suppressed row's record (AX tree differs) |
| 1.5 | `theListBranchesKeepTheirWorkLiterals`: the existing `VL-`/`DD-` work pins, **unedited** (a diff of `Tests/**/List*` shows only added tests) | n/a | n/a (a moved literal is a finding) |
| 1.6 | `aGraftIsRefusedUnderAnUncomparableKey` (an occurrence under a closure-valued custom key: 0 grafts, a refusal reason counted, the frame equals a fresh one) | green on arrival | `custom` dropped from `BuildKey.environment` (the conjunct already removed) |
| 1.7 | typecheck: none (no new type) | | |

**Demo.** None for lane 1 beyond lane 2's section. **Human checks** `FS2` (a long `List` of retained rows scrolled with a wheel and
a trackpad, a row edited while scrolling, VoiceOver reading the rows).

## 2 Lane 2 - translation (`FS-D`, `FS-E`, `FS-F`, `FS-G`)

**Goal.** An occurrence whose origin moved by layout, or whose scroll offset moved, replays moved instead of missing. **Files** (`FS-L`):
`RetainedSubtree.swift` (`ReplayKey`, `differsOnlyByTranslation`, `replayPaint(_:translated:)`, `retainedPaintDecision`),
`RetainedPrepaint.swift` (`PrepaintKey`, the translation branch of `retainedPrepaintDecision`, `translatedHitboxes`), `Frame.swift`
(`readRetainedGeometry`, `PrepaintExtras.translation`), `Sources/MetalUILayout/LayoutTree.swift` (`subtreeSignature(of:relativeTo:)`),
`Sources/MetalUITesting/FrameWork.swift` (`retainedTranslationRefusedReasons`), `Sources/MetalUIDemoContent` (one section in its own
function, below), tests `FinerScopesTranslationTests.swift`, `Tests/MetalUILayoutTests` for the signature, `Tests/MetalUITests` for the key.

**Design.**
* **Key split.** `ReplayKey.rects`/`interior` and `PrepaintKey.rects`/`interior` become `shape` (rects and interior relative to the
  first top node's origin, plus `nodeCount`) and `origin`. `==` compares both, so today's decisions are unchanged; the relation
  `differsOnlyByTranslation(from:)` compares `shape` and the ambient and reports a `Translation { dx, dy, kind }`:
  K1 (origin moved, ambient equal), K2 (origin equal, only `ambient.offset` moved, clip equal), or K1 + the existing effect translation.
* **Exactness gate.** Store at record time whether the record's coordinates are multiples of 1/16 and below 2^19; accept a translation
  only if it is too. Else count a refusal named `inexactTranslation`.
* **Paint replay.** `replayPaint` adds the delta to the final-stream ops (`RetainedRecord.finalScene`) and, when another recorder is
  open or an outer scope captures, to `scene` ops, through a `CapturedPrimitive.translated(by:)` over the allow-list (rect, glyph run,
  image, path and gradient raster placed by `RasterAnchor`, shadow leaf). A mask equal to the entry clip is left; a mask inside the entry
  clip before and after moves; any other mask, and any kind not listed, refuses by name (`unlistedKind:<kind>`, `maskStraddlesEntryClip`).
* **Prepaint replay.** `translatedHitboxes(of:by:)` takes the delta of K1/K2 as well as the effect delta; focus stops, element bounds
  and context-menu anchors move by it; accessibility emissions and nodes refuse (`accessibilityRecords`).
* **Graft** is untouched; a grafted occurrence whose prepaint or paint key fails to translate is the existing redo.
* **Counters.** `retainedTranslated` and `retainedTranslationRefused` are reused (K1/K2 occurrences count); the reasons are the one new
  public field `retainedTranslationRefusedReasons` (a `[String: Int]`, filled only on refusal).

**Steps.**
1. Fixture arms in `FinerScopesFixture.swift`: `shift` (id inserted first), `header` (a header above resizes), `scroll` (non-lazy
   `ScrollView`), `listScroll`, and the bracket arms (existing). Baseline pins at `711ab9c4` (F2, F3) as literals, hits 0.
2. **Spike (`FS-E`)**: K1 and K2 for rect/glyph/image, differential at scales 1, 2, 4, AX on and off. Kill criteria in `FS-E`.
3. The rest of the allow-list, hitbox/ledger translation, refusal names.
4. Demo section; measurement (ms per frame, dated) on `bracketorbit` and a new `shiftscroll` arm of `perf-baselines.sh`.

**Tests:**

| id | test | red before | mutation |
|---|---|---|---|
| 2.1 | `aStackShiftedByAnInsertionReplaysItsRowsTranslated` (23-24 translated, 1 miss for the new row; requests, prepaints, paints at most the literal derived at the spike, strictly fewer than F2) | yes: hits 0 | the K1 branch of `differsOnlyByTranslation` returns `false` |
| 2.2 | `aHeaderThatResizesShiftsTheRowsAndTheyReplay` | yes | `shape` computed from absolute rects (relative hash dropped) |
| 2.3 | `aScrolledScrollViewReplaysItsRowsTranslated` (K2) | yes | the K2 branch returns `false` |
| 2.4 | `aScrolledListReplaysTheRowsStillInTheWindow(branch:)` (rows entering the window record, those staying translate; needs lane 1) | yes | `translationRefused` for every list occurrence |
| 2.5 | `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale` (scales 1, 1.5, 2, 3, 4 x AX on/off; bit-for-bit scene, hitboxes, AX tree; at 1, 2, 4 `translated > 0`, at 1.5 and 3 `refused > 0` reason `inexactTranslation`) | yes (translated 0) | exactness gate removed (reddens 1.5/3 arms); the add applied to the y axis twice (reddens all) |
| 2.6 | `aClickAndHoverAfterAShiftReachTheMovedRow`, `focusRingAndTabOrderFollowTheShiftedRow` | yes | hitboxes not moved (the scene still equals) |
| 2.7 | `everyUntranslatableKindRefusesByName` (surface, backdrop, a mask straddling the entry clip, accessibility records, an unlisted primitive) | n/a | the allow-list widened to `true` |
| 2.8 | `aShiftThatAlsoResizesTheOccurrenceMisses` (separating arm for the shape comparison) | green | `shape` comparison ignoring sizes |
| 2.9 | `aFractionalShiftIsRefusedNotApproximated` | n/a | the 1/16 test replaced by `true` |
| 2.10 | `theBracketNodeDragAndTheOrbitAreUnmoved` (144 / 153 and 6 / 7 / 7 stay, the existing literals unedited) | green | n/a |
| 2.11 | `aRelativeSubtreeSignatureIsTranslationInvariant` (`MetalUILayoutTests`) | yes | the origin subtracted from x only |
| 2.12 | `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` over the whole suite | | a 1 ulp error in the add must trap or redden 2.5 |

**Demo.** `METALUI_RETAINED_DEMO=1` gains a "shift and scroll" strip: a header with a +/- 4 pt control above a `ScrollView` of 24
cards, and its counters line (requests, translated, refused with reasons), built in its **own function** passed to the generic
composer (Windows 1 MB stack, `everyProductionTreeBuildsOnAOneMegabyteThread`). Expectation: pressing + reads `translated 24`, requests
single digits with the graft; a wheel scroll reads the same; on a 1.5 or 3 scale display it reads `refused ... inexactTranslation` and the
requests of today.

**Human checks** (`docs/verification/human-checks.md`, group `FS`, added at the Record phase, not run by an agent):
`FS1` the owner's MetalCreator orbit and pan with the graph panel open, CPU per frame against 25.8 ms (no agent touches MetalCreator);
`FS2` (lane 1); `FS3` the demo strip at scales 1, 2 and a non-dyadic scale: scroll, resize the header, no tearing, no stale row after a
fast wheel and a data change; `FS4` VoiceOver on the shifted strip reads the same rows (accessibility refuses, so this is the unretained
path).

## 3 Verification, both lanes

`swift package clean`; `swift build --build-system native --build-tests`, 0 `error:`, only SwiftPM's deprecation `warning:`; native
unfiltered `--no-parallel`, one summary line (4000 plus the added tests, in the suites count it prints), `FR-J no-argument frame:
succeeded=true`; the same under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`; `swift build --build-tests` on the default
system, 0 `warning:`; `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing after re-recording the
census; the fourteen images 0 px against `711ab9c4` (`docs/probes/demo-pixels/compare.sh <scratch> 711ab9c4 HEAD`),
`DemoFrameDeterminismTests` `Expected.swift` unedited; the Linux image `metalui-portable` runs `MetalUITestingTests`, `MetalUILayoutTests`,
`MetalUICoreTests`, `MetalUICrossPlatformTests` (volume `metalui-root-build-finer-scopes`); `Backends/SDL` is untouched (a diff of
`Backends/` is empty), so its package is not re-run; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green. Every pin is
mutation-verified in the table order with `git status --short` after each and the reddened tests named. The 100k list test is not owed
unless row naming is touched (`FS-K` 4).

## 4 Deferred (`FS-K`)

Implicit equality scopes; list rows as groups without a wrapper; placement-memo translation (C14-e, if `FS-G`'s figures say so); a
translated replay across a surface, popover or presentation; lazy grids; MetalCreator's reading (`FS1`).

## 5 Risks, ranked

1. The mask rule is too strict for real content (rows with their own `.clipped()` at a viewport edge refuse): costs the win, not
   correctness; the refusal name says so. 2. The exactness gate excludes scales 1.5 and 3; the spike measures whether a wider rule
   (exact per op) is cheap, and the decision records it. 3. The `suppression` cause may be a harness effect; lane 1 step 2's AX on/off
   arms decide, and a harness-only cause makes lane 1 a pin-only lane. 4. Touching both keys changes every retained decision's
   comparison: test 2.10 and the whole verify run are the guard.

## 6 Lane 2 as built (amends section 2; rulings `FS-O`..`FS-S`)

* **Key.** `ReplayKey` and `PrepaintKey` keep their absolute `rects` and `interior` (so `==` and every old decision are unchanged) and gain
  `shapeInterior`; the relation is `RetainedShape.shift` (`Sources/MetalUI/RetainedTranslation.swift`), not a method named
  `differsOnlyByTranslation`. `LayoutTree.subtreeSignatures(of:relativeTo:)` returns both hashes in one walk.
* **Gate.** Whole device pixels (`FS-M`) then multiples of 1/16 below 2^19. Scales 1.5 and 3 are **not** refused wholesale (layout is in
  whole points there); test 2.5 reads "bit-identical at every scale, translated at all five". The `inexactTranslation` reachable case is
  scale 1.2 (test 2.9b); `fractionalTranslation` is 1 point at 1.5 (test 2.9).
* **Paint.** Leaves are moved at the record's own scope height through `processScopes` (the translated path of `RK-S`), allow-list rect,
  glyph, image; a record that passed an inner paint scope refuses (`innerScope`); masks by depth (entry: left, inner: moved only strictly inside
  the entry clip, else `maskStraddlesEntryClip`). After a successful translated hit the record and the ledger are **rebased** at the new
  position (not in verify mode).
* **Prepaint.** The ledger's hitboxes and element bounds move; the paint record must be movable first or the prepaint runs (no redo).
* **Hitboxes** keep their uncut rect and clip depth (`Hitbox.unclipped`, `Hitbox.clipDepth`): a hitbox cut by the ambient clip moves as
  `clip ∩ (rect + delta)`; the pointer is read against the moved hitboxes (`FS-P`).
* **Switch.** `METALUI_RETAINED_TRANSLATION=0` / `Window.testingRetainedTranslation` is the A/B of the figures.
* **Tests.** 2.1 to 2.3 `aShiftedOrScrolledRowReplaysTranslated`; 2.1b `aShiftedCardStackEqualsAFreshWindow`; 2.4
  `aScrolledListReplaysTheRowsStillInTheWindow`; 2.5 `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale`; 2.6
  `aClickAfterAShiftReachesTheMovedButton`; 2.7 `everyUntranslatableKindRefusesByName`; 2.8 `aShiftThatAlsoResizesTheOccurrenceMisses`;
  2.9 `aFractionalShiftIsRefusedNotApproximated`; 2.13 `theSwitchOffMissesEveryShiftedRowAndOnTranslatesThem` (the A/B figures as literals); 2.14
  `aFrameAfterAShiftReplaysAnExactLedgerNotAMovedOne`; 2.15 `aHitboxTheScrollersClipCutIsRecomputedAtItsNewPlace`; 2.9b `anInexactCoordinateIsRefusedNotApproximated`; 2.11 (layout)
  `aRelativeSubtreeSignatureIsTranslationInvariant`; 2.10 is the existing bracket and orbit pins, unedited.
* **Demo.** `METALUI_RETAINED_DEMO=1` gains the section `RetainedDemoShift` (its own function; the window is 700 points tall); the perf arm is
  `zsh docs/probes/perf-baselines.sh release shiftscroll`.
