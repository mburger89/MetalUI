# 131 — Retained lifecycle and translation carries (C14-h)

Branch `perf/retained-lifecycle` from `c55d44e8`, merged at the Record phase with master `05bb9a31` (§130 image sniff; docs and `ImageSniff*` only, a clean merge, no renumbering: this record is §131).
Not a plan task: item C14-h of the gpui-gap list (user request 2026-10-02), from MetalCreator's ViewportView findings of 2026-10-20 (`retainedIneligibleReasons['modifierKeys']`,
`['lifecycle']` and the graft refusal `lifecycle` on every steady frame) and the carries of C14-f (§128, `RG-C`, `RG-J`), C14-g (§129, `AT-C`, `AT-G`) and `RW-L`.
Spec `docs/superpowers/specs/2026-10-21-retained-lifecycle-design.md`; rulings `RL-A`…`RL-Q` in `docs/superpowers/2026-10-21-retained-lifecycle-decisions.md` (next unused `RL-R`).
Divergence labels 605–614 reserved: none taken. No public declaration, no census row, no SwiftUI claim (no observable behaviour moves, so no probe; the oracle is a window with
`Window.testingRetainedSubtrees = false`), no shader or pixel change, `Backends/SDL` untouched. Two implementation lanes, each red first and verified `ok: true` by a separate checker.

## §1 The defects

1. **Lifecycle scopes refused the graft.** `onAppear`/`onDisappear`/`onChange`/`.task` note into `LifecycleStore` in **layout**; a graft skips layout, so `BuildAudit.lifecycle` (= `workThisFrame + nextOrder`)
   moved in any window with a scope and `graftRecord` was never made (`graftRefusals["lifecycle"]`, `retainedIneligibleReasons["lifecycle"]` on every steady frame).
2. **A modifier scope tainted the prepaint ledger.** `ModifierKeysScope.prepaintGroup` tainted the log (`"modifierKeys"`, `RG-D`: "the value is window-wide, so a recorded value is stale"). That is true of a
   recorded *value*, false of a recorded *note*.
3. **Translation walls (C14-f, C14-g carries).** A translated replay (effect, layout or scroll) of a ledger holding a geometry note refused `geometryTranslated` (`RG-C`) and such a ledger was never grafted
   (`geometryGraft`, `RG-J`); layout translation refused `accessibilityRecords` (`AT-C`); a hitbox opened inside the occurrence's own effect under a non-identity scale refused `hitboxes` (`AT-G`).

## §2 What landed

**Replay re-notes presence; the store's diff decides every delivery (`RL-A`).** The lifecycle store forgets any key a build did not note (`endFrame`'s previous-minus-current, `closeGeometry`/`closeModifierKeys`),
so a skipped note is a spurious disappear, appear or `initial` re-report. A replay or graft therefore re-notes each scope exactly as a build would and never computes a delivery. "Refuse only when a callback must
run" needs no new refusal: a changed `onChange` value or `.task` id comes from a re-evaluated getter (which cannot graft), a first appearance is a new key, a modifier change is the current value differing from the stored one.

**Modifier notes are ledger entries holding no value (`RL-B`).** `ModifierNoteRecord{watch,key,owner}` in `PrepaintLog.modifiers`/`PrepaintLedger.modifiers` replaces the taint; the replay reads `currentModifiers` itself
(amends `RG-D`). Valid under translation.

**Lifecycle notes are build-journal events with relative orders (`RL-C`, `RL-N`).** `LifecycleStore.note`/`reserveOrder` append to the attached `BuildJournal`; `Frame.reapply` re-notes at `base + rel` and
advances `nextOrder` by the window's count, so pre-order numbering, occurrence ordinals, `LC-F` order, `LC-I` and the `.task` box carry-through (`PX-F`, `TF-A`) are a build's. The count is a `GraftRecord` field
(`lifecycleOrders`), not an event, so a nested window's count includes what an inner graft advanced. Not a `StateTable` write site; the seven slots are unmoved. Actions still run in `Window.drainLifecycle`, outside every phase.

**The audit is a tripwire (`RL-D`, `RL-N` 2).** `BuildAudit.lifecycle` is `buildActivity = workThisFrame + nextOrder - journaledActivity`: registrations that bypassed the journal, 0 in every window, refusing by name if a
new site forgets. `METALUI_VERIFY_RETAINED=1` gains channel `lifecycleStore` (the build in progress's lifecycle, geometry and modifier notes: keys, orders, presence, a modifier's masked value).

**Geometry notes are recomputed under translation (`RL-E`, `RL-O`, `RL-P` 1).** `GeometryNoteRecord` keeps `size`, `moved`, `composed`, `chain` and `namedSpaces`; `Frame.movedGeometryNotes` (layout, scroll) and
`Frame.translatedGeometryNotes` (effect), in `RetainedTranslationCarries.swift`, rebuild the `GeometryProxy` and call `transform` again, and the replay notes the result (a nested ledger's log holds the moved values). A named space
declared **inside** the occurrence moves with it: its `toWindow` moves by exactly what the position moved, **only when its linear part is made of multiples of 1/16** (identity, 2, 0.5), because the sums are then exact in `Double` in any
order and the moved map is bit-equal to a fresh one; a non-dyadic space (a 0.8 scale) refuses `geometryNamedSpace`. A note made under an effect the occurrence opened refuses a **layout** shift `geometryUnderEffect` (the effect's map is
anchored to the occurrence's position). An outer named space needs no new refusal: `prepaintRefusal()` already refuses a window opened while `namedSpaces` is non-empty, so no ledger exists (`RL-O`, pinned as such).
`geometryTranslated` and the layout `accessibilityRecords` refusals are gone.

**`RG-J` lifted for recomputable notes (`RL-G`, `RL-Q`).** `graftRecord` refuses `geometryGraft` only when `Frame.geometryNotesRecomputable` is false (an inner effect or a non-dyadic named space). Measured, test 16: a grafted
two-card observer grafts 2/2 on steady frames and three shifts across the graft cost `retainedRedos == 0`, backoff 0.

**Layout and scroll translation of accessibility (`RL-H`, `RL-P` 3; amends `AT-C`).** `AXEmission` gains `clipDepth`; `Frame.movedAccessibility` moves emissions and nodes by the window delta with the hitbox rule (a record at the entry
depth is cut again against the ambient clip; one deeper moves only if strictly inside the clip before and after, else `accessibilityClipped`); a record with `local != nil` (made under an effect) refuses `accessibilityUnderEffect`.
`rebased` carries `axNodeLocals` and the moved records. `AXLocalRects` is unchanged.

**A hitbox inside the occurrence's own effect carries its step chain (`RL-I`, `RL-P` 4; closes `AT-G`).** `Frame.hitboxChains[index]` (kept only while a log records and only for a hitbox under an effect) is copied into
`PrepaintLedger.hitboxChains`. `translatedHitboxes` re-derives such a hitbox from the shared `Frame.walkEffectSteps` and **validates the walk first** (the walk from the ambient as recorded must reproduce the transform the hitbox
carries, else a share patch rewrote it and it refuses `hitboxes`). This replaces the identity-linear delta rule at every scale and lifts `RK-S` item 2's "outer clip depended on the translation" refusal. `Hitbox` itself is untouched.

**`surface` stays refused (`RL-J`, `RL-K`, `RL-M`).** Measured: an `.onDemand` surface in an `.equatable()` occurrence costs one element paint per frame (paint refused once, prepaint replays, graft 0 refusals). A replay would owe a `.surface`
arm in `CapturedPrimitive`, a re-appended `SurfaceDrawRequest` with the standing `draw` closure the renderer calls, a re-done `SurfaceRegistry.occurrence(for:)`/`id(for:occurrence:)` (else `endFrame` releases the target) and the same on SDL's table,
with no way to pin "the GPU did not redraw" on the headless platform. `RW-L` stays carried.

## §3 Tests and guards, per file

No new typecheck guard (no public declaration): 250 before and after. Tests, with their red state at `c55d44e8`:

`Tests/MetalUITests/RetainedLifecycleTests.swift` (new, lane 1; red first at `9cb2d55b`, tests 1, 2, 5 hits arm, 8 graft arm, 9, 11 red):
`aSteadyOccurrenceWithLifecycleScopesGrafts`, `aSteadyOccurrenceWithAModifierScopeReplaysItsLedger`, `lifecycleDeliveriesThroughRetentionEqualAnUnretainedWindow` (appear, steady, onChange value change, task id change, modifier change,
disappear, re-insert; a `testingRetainedSubtrees = false` window is the oracle, plus an arm where the action reads `@State` through a binding, `RL-L`), `aGraftedOccurrenceKeepsLifecycleOrderAmongSiblings` (grafted disappearances included),
`aModifierChangeAcrossAReplayedLedgerDelivers` (a masked-out modifier delivers nothing), `aNestedOccurrencesLifecycleNotesAreJournaledOnce`, `aTaskIdChangeThroughAGraftCancelsThenStarts`,
`verifyChannelNamesALifecycleStoreMismatch`, `aViewportShapedTreeIsRetainedEligible` (ineligible reasons 0/0/0, grafts > 0), `aRedoDropsJournaledLifecycleNotes`, `anUnjournaledRegistrationRefusesTheGraftByName`.
`Tests/MetalUITestingTests/MemoryReleaseTests.swift`: `aGraftedOccurrenceWithLifecycleScopesReleasesItsWindowAndModel` (`IV-R`, `RL-L`: the journal holds closures only on the memo entry's record).
`Tests/MetalUITestingTests/RetainedTranslationCarryTests.swift` (new, lane 2; red first at `612e722d`, 33 issues in 8 of 10 tests): `aLayoutShiftKeepsALocalGeometryNote`, `aGlobalFrameNoteIsRecomputedUnderShiftAndScroll(mode:)` (plain, scrolled),
`aGlobalFrameNoteUnderAPanEffectIsRecomputed(arm:)` (1, 2, 0.8), `anOuterNamedSpaceIsIneligibleBeforeAnyGeometryNote` (green at base by design: the upstream `namedSpaces` refusal), `aNamedSpaceDeclaredInsideTheOccurrenceIsInvariant(arm:)` (1, 2),
`aNamedSpaceUnderANonDyadicScaleRefusesByName`, `anObserverGraftsAndAShiftNeedsNoRedo`, `aLayoutShiftReplaysAccessibilityRecordsRecomputed` (published tree equals a fresh window's), `anAccessibilityRecordUnderAnEffectStillRefusesOnLayoutShift(mode:)`,
`aHitboxOpenedInsideTheOccurrencesEffectReplaysAtNonIdentityScale(arm:)` (1, 2, 0.8), `aNestedEffectAccessibilityRecordIsRecomputedAtScaleTwo(arm:)` (the arm C14-g's mutation M6 needed).
Amended, superseded pins (`RL-P` 4): `RetainedGeometryTests` tests 5 and 7 (refusal to recomputed), `aHitboxWhoseClipDependedOnTheTranslationIsRecomputedFromItsSteps` (was `...IsNotMoved`), `aGraftedOccurrenceUnderARefusedTranslationRedoesTheFrame`
(its refusal is now `fractionalTranslation`), `FSRefusal.accessibility` (removed), `RetainedGraftTests`' `.lifecycle` arm (now a control arm that grafts, as `.scroll` after `RW-H`), `RetainedSubtreeInternalTests` (two lines), `Frame.hitboxChains` classified in the state-write census.

## §4 Probes

None: nothing here answers for SwiftUI (`RL-` preamble). gpui has no lifecycle-scope analogue.

## §5 Verification

Implementation-time (lane 2's checker, at `225b1ed0`, before this merge): `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, native unfiltered run **4104 tests in 5 suites**, the only issues the
five known `AppKitPresentationTests` sheet issues of `CI-AF` (screen locked), `FR-J no-argument frame: succeeded=true`; `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` run 4095 passed; default build system `swift build --build-tests` 0 `warning:`;
inventory and undocumented scripts print nothing; the fourteen offscreen images 0 px, scene-identical against `c55d44e8` (controls non-zero); Linux image (`metalui-portable`): `MetalUITestingTests` 431, `MetalUILayoutTests` 233, `MetalUICoreTests` 128,
`MetalUICrossPlatformTests` 22 passed. Lane 1's checker: native run skipping `AppKitPresentationTests` 4084 passed (a lane-1-only tree), fourteen images 0 px.
Merged tree, Record phase: see the counts line of `CLAUDE.md` (re-measured after the merge; the numbers are quoted there).

## §6 Mutation tables

Mutations were run as **filtered family runs** (70 tests) at the implementer, and re-run by the checkers as filtered family runs, **not unfiltered** (the checkers re-ran three of the implementer's seventeen: the geometry refusal in the layout branch, the hitbox chain result, the clipDepth rule;
the red-first state at `c55d44e8` rests on the implementer's report and on the restored-refusal mutations reddening the same tests).

| Mutation (spelling) | Reddened | Expected |
|---|---|---|
| `geometryTranslated` refusal restored at the top of `movedPrepaintLedger` (layout) | `aLayoutShiftKeepsALocalGeometryNote`, `aGlobalFrameNoteIsRecomputedUnderShiftAndScroll(mode:)`, `aNamedSpaceDeclaredInsideTheOccurrenceIsInvariant(arm:)`, `anObserverGraftsAndAShiftNeedsNoRedo`, `aTranslatedReplayOfAGeometryNoteIsRecomputedNotRefused`, `aPanOfTheWholeGraphReplaysEveryNodeAndEqualsAFreshFrame(step:)` | yes |
| the same in the effect branch | `aGlobalFrameNoteUnderAPanEffectIsRecomputed` (3 arms), `aNamedSpaceDeclaredInsideTheOccurrenceIsInvariant`, `RetainedGeometryTests` 7 | yes |
| `transform` not run again | 12 tests incl. all three recompute tests | yes |
| scroll offset dropped from the moved rect | `aGlobalFrameNoteIsRecomputedUnderShiftAndScroll(scrolled)` only | yes |
| recorded ambient composed map used instead of the current | the pan arms | yes |
| `toSpace` left as recorded | `aNamedSpaceDeclaredInsideTheOccurrenceIsInvariant` only | yes |
| `geometryGraft` refusal restored | `anObserverGraftsAndAShiftNeedsNoRedo` only | yes |
| accessibility visible frame not re-cut / frame not shifted | `aLayoutShiftReplaysAccessibilityRecordsRecomputed`, `aShiftedCardStackEqualsAFreshWindow`, `aScrolledListReplaysTheRowsStillInTheWindow` | yes |
| emission `underEffect` arm deleted | `anAccessibilityRecordUnderAnEffectStillRefusesOnLayoutShift(effectText)` | yes |
| `axNodeLocals` not carried by `rebased` | `aLayoutShiftReplaysAccessibilityRecordsRecomputed` | yes |
| hitbox transform left as recorded / chain ignored / chains not recorded / nested steps skipped | `aHitboxOpenedInsideTheOccurrencesEffectReplaysAtNonIdentityScale(arm:)`, `aHitboxWhoseClipDependedOnTheTranslationIsRecomputedFromItsSteps`, `anEffectOpenedInsideTheOccurrenceIsRecomputedFromItsSteps(arm:)`, `aNestedEffectAccessibilityRecordIsRecomputedAtScaleTwo(arm:)` | yes |
| `movedAccessibility`: `emission.clipDepth == entryDepth` replaced by `true` | none (101 tests) | **no, survivor** |
| `movedAccessibility`'s nodes arm; the dyadic clause | none (shadowed by the emission arm; by the round-trip clause) | equivalent |
| lane 1: the spec's mutation sites (skip the re-note, replay the recorded modifier value, drop the journal append, leave the journal untruncated on a redo, skip the task-box carry, delete the audit comparison) | the lane-1 tests of §3; the lane's commits carry no table, only `RL-B` (modifier value: tests 3 and 5) and `58236fe8` (order test mutation-verified) name results; the per-mutation reddened lists were not recorded | partly unrecorded |
| lane 1's checker: `PrepaintLedger.rebased` without `copy.modifiers = modifiers` (full unfiltered run, 4084 passed, `/tmp/rl_v_mA.log`) | none | **no, survivor** |

## §7 Hazards

- **A replayed or journaled closure is the standing one** (`RL-L`): an `onChange` action, a `.task` body, a lifecycle write is the closure of the build that recorded it. A captured plain mutable value outside `.equatable()`'s contract replays stale
  (as `RG-A`'s transform does). State read through a binding is current (test 3's arm).
- **A new lifecycle-registering site must go through the journal**, or `BuildAudit.lifecycle` refuses it by name (the tripwire, `RL-D`), and verify mode's `lifecycleStore` channel traps if both are removed.
- **`geometryTranslated` and the layout `accessibilityRecords` names are gone**; refusal names added: `geometryUnderEffect`, `geometryNamedSpace`, `geometryUnrecorded`, `accessibilityUnderEffect`, `accessibilityClipped`, `accessibilityUnrecorded`.
  For an occurrence with two causes the press-only and context-menu checks now come first (`pressOnly` shows where `accessibilityRecords` did).
- The dyadic rule (multiples of 1/16) is what makes a moved named-space map bit-equal to a fresh one: do not widen it without a probe of the order of the sums (`RL-O`).

## §8 Open residues and deferrals

- **Two unpinned arms (checker findings, minor):** (1) the modifier-note copy in `PrepaintLedger.rebased` (a modifier scope inside an occurrence that translates while steady; consequence inferred from `RL-A`, not measured); (2) the
  `emission.clipDepth != entryDepth` arm of `movedAccessibility` (reachable only if a record cut by a clip derived inside the occurrence reaches a prepaint replay; the `inner: true` arm's comment says that is a paint-record refusal first). Owner: the next C14 item;
  each owes a differential test (delivery sequence against a retention-off window; a layout-shift arm comparing the published tree), or, for (2), a trap or a named refusal if unreachable.
- **No demo strip and no `RL` human checks beyond the three below were built**: the spec's lifecycle strip in `METALUI_RETAINED_DEMO=1` did not land; the fourteen default images cannot move either way (0 px confirmed).
- Carried, named: a note made under an effect the occurrence opened on a **layout** shift (`geometryUnderEffect`, needs the effect's anchor re-derived, `RG-M`'s neighbour); named spaces with a non-dyadic linear part (`geometryNamedSpace`, keeps the graft refusal);
  an outer named space under translation (unreachable today, `RL-O`); `surface` (`RW-L`, `RL-M`, owner a C14 with a GPU-backed measurement); placement-memo translation (`FS-G`); `hitboxClipped` under a moved effect (`RG-M`).
- Owed, not looks: the Linux image on the merged tree (§130 is docs and `ImageSniff*` only), the unlocked `AppKitPresentationTests` run.
- Looks owed: `docs/verification/human-checks.md` group `RL` (RL1 to RL3), none performed; record §03.
