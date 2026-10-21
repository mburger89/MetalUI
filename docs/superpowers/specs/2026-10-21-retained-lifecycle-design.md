# Retained lifecycle and translation carries - design (C14-h)

Branch `perf/retained-lifecycle` from `c55d44e8`. Rulings: [`../2026-10-21-retained-lifecycle-decisions.md`](../2026-10-21-retained-lifecycle-decisions.md) (prefix `RL-`).
Record: `docs/record/131-retained-lifecycle.md` (Record phase). Reserved divergence labels 605-614: none expected, none taken. No public API.

Source: MetalCreator's ViewportView reports `retainedIneligibleReasons['modifierKeys']`, `['lifecycle']` (and the graft refusal `lifecycle`) on every
steady frame; carries from C14-f (`RG-C`, `RG-J`), C14-g (`AT-C`, `AT-G`) and `RW-L` (`surface`).

## 1. Inventory (the code at `c55d44e8`)

- **Lifecycle scopes note in LAYOUT.** `LifecycleScope.requestGroupLayout` reserves `LifecycleStore.reserveOrder()` pre-order, then (content non-empty)
  `noteLifecycle` -> `LifecycleStore.note(write, scope, owner, order)`: one `Entry` per `Key(scope, occurrence)` (onAppear / onDisappear / change{value,
  isEqual, action, initial} / task spec). `endFrame` diffs `current` against `previous` and queues events; `rollbackBuild` clears `current`.
  A **graft** (`RetainedGraft`) skips the build recursion, so none of these calls happen. Today `BuildAudit.lifecycle = buildActivity` (= `workThisFrame +
  nextOrder`) moves in any window that registered a scope, so `graftRecord` is never made: counted `lifecycle`. The graft already replays other
  store-like effects through `BuildJournal.Event` and `Frame.reapply` (`RK-F`).
- **Modifier-key scopes note in PREPAINT.** `ModifierKeysScope.prepaintGroup` taints the prepaint log (`"modifierKeys"`) then `noteModifierKeys(watch, key, owner)`
  stores `currentModifiers & mask`. The *value is window-wide*, not derived from the subtree, so a recorded value would be stale (`RG-D`), but the *note*
  `(watch, key, owner)` is a pure function of position: nothing but the current mask value need be read at replay.
- **Geometry notes** are ledger entries since `RG-A` (`GeometryNoteRecord`, re-noted in `Frame.replayPrepaintLedger`, `Frame.swift` ~4074). `movedPrepaintLedger`
  returns `geometryTranslated` for any ledger holding one (`RG-C`); `graftRecord(for:)` returns nil, counting `geometryGraft`, for an occurrence whose ledger
  holds one (`RG-J`).
- **Layout/scroll translation** (`FS-P`, `RetainedTranslation.swift`): `movedPrepaintLedger` refuses `accessibilityRecords` (`AT-C`), `hitboxUnderEffect`.
  **Effect translation** (`RK-G`): `translatedAccessibility(of:)` recomputes every record from `AXLocalRects{frame, clipped, chain}` (`AT-A`, `AT-G`);
  `translatedHitboxes(of:by:)` shifts a hitbox registered inside an effect the occurrence opened by `-delta` only under an identity linear part, else counts
  `hitboxes` (`AT-F`, `AT-G` carried). Hitboxes carry no step chain.
- **Surfaces**: `Frame.drawSurface` taints `retainLog("surface")`; `SurfaceRegistry` is per window; `translatePrimitive` refuses `unlistedKind:surface`.

## 2. Design

**The one idea (`RL-A`).** The lifecycle store forgets any key a build did not note (`closeGeometry`'s G7; `endFrame`'s previous-minus-current), so a replay or graft
must **re-note** presence exactly as a build would, and then let the store's ordinary diff decide what is delivered. Deliveries are never computed by the
retention code; "a callback must actually run" is by construction a store diff, so the only refusals are the existing ones (the occurrence's value changed ->
the getter re-evaluates -> no graft, a fresh build notes the new value).

### Lane 1 - lifecycle and modifier-key scopes, plus the surface gate (`RL-K`; files: `Frame.drawSurface`/`PaintRecord` for the gate, `Lifecycle.swift`, `ModifierKeysChange.swift`, `RetainedGraft.swift`, new `RetainedLifecycle.swift`, tests)

1. **Modifier notes join the ledger** (`RL-B`). `ModifierNoteRecord{watch, key, owner}` appended to `PrepaintLog.modifiers`/`PrepaintLedger.modifiers`
   (parallel to `geometry`); the taint is deleted. Replay calls `LifecycleStore.noteModifierKeys(watch:key:owner:)` for each record, in order, which reads the
   *current* `currentModifiers` - so a modifier change across a replayed ledger delivers, and an unchanged one does not. Valid under translation (no geometry).
2. **Lifecycle notes join the build journal** (`RL-C`). New `BuildJournal.Event.lifecycleNote(LifecycleNote)` where `LifecycleNote{write, scope, owner, relOrder}`
   plus `.lifecycleOrders(count)` closing the window. `LifecycleStore.note` and `reserveOrder` append to the attached `buildJournal` (the `AnimationStore.attach`
   path `openGraftWindow` already uses); orders are stored **relative** to the store's `nextOrder` at window open. `Frame.reapply` re-notes: `base =
   store.nextOrder`, `note(write, scope, owner, order: base + rel)`, `nextOrder = base + count` - so pre-order numbering, occurrence ordinals, `LC-F` event
   order, `currentHasDisappearActions` (LC-I) and `.task` box carry-through (`PX-F`) are exactly a build's. `BuildKey.depths` already holds `lifecycleDepth`.
3. `BuildAudit.lifecycle` becomes **unjournaled registrations** (`buildActivity - journaled`), 0 in every window; kept as a tripwire so a new registration
   site that skips the journal refuses by name `lifecycle` instead of grafting wrongly (`RL-D`). `METALUI_VERIFY_RETAINED=1` gains channel `lifecycleStore`: the
   verify build compares the store's `current` keys, orders and presence against the graft's and traps naming it.
4. Nothing runs in a phase: actions stay in `Window.drainLifecycle` (`LC-E`); `rollbackBuild` already clears the store, and the journal is truncated with the
   redo (`aRedoLeavesEveryTableAsAFreshBuildWould` gains an arm).

### Lane 2 - translation carries (files: `GeometryChange.swift`, `RetainedTranslation.swift`, `AXEmission.swift`, `Frame.swift` `translatedHitboxes`/`translatedAccessibility`,
`RetainedPrepaint.swift` `graftRecord` site, `Frame.swift` `drawSurface`/`PaintRecord` for the surface gate, tests)

a. **Geometry under translation** (`RL-E`, `RL-F`). `GeometryNoteRecord` keeps `size`, the pre-effect `moved` rect, the `composed` map, the chain of the effects the
   occurrence opened and `outerNamed: Bool` (a named space declared **outside** the occurrence was in force). Translated replay (layout delta `d`, or a new
   ambient effect) rebuilds the `GeometryProxy` - `size` unchanged, `scrolledFrame = moved + d` (layout) or the ambient effect re-derived with
   `translatedAccessibility`'s step arithmetic (effect) - **re-runs the user's `transform`** (a fresh prepaint would; it must not write, `KF-J`) and notes
   the result. `.local`-only transforms are translation-invariant and the re-run returns the equal value. An open outer named space refuses `geometryNamedSpace`
   (its inverse map is not recorded); a space declared inside the occurrence moves with it and is fine. Inexact (non-1/16, >= 2^19) deltas keep today's gates.
b. **Lift `RG-J`** (`RL-G`): `graftRecord` stands for a geometry-holding ledger when every record is recomputable (`outerNamed == false`), because the foreseeable
   refusal that made a graft cost a redo is gone; an `outerNamed` ledger keeps `geometryGraft`. Gate: the measure step below.
c. **`AT-C`** (`RL-H`): layout/scroll translation of accessibility records is the same mechanism (recompute from `AXLocalRects`). `AXLocalRects` gains
   `clipDepth` and `entryClipCut: Bool`; `movedPrepaintLedger` replaces `accessibilityRecords` with a recompute: `frame += (windowX, windowY)`, `clipped` re-cut
   against the new ambient clip when the record was cut by the ambient clip itself, else required strictly inside before and after (the hitbox rule); records
   under an effect keep refusing (`hitboxUnderEffect` analogue `accessibilityUnderEffect`, effect translation owns them). Nodes move with their emissions.
d. **`AT-G` hitbox** (`RL-I`): the ledger records a parallel `hitboxChains: [AXEffectChain?]` (not a `Hitbox` field: size is pinned); a hitbox opened inside the
   occurrence's own effect takes `effect(for: chain).inverse/outerClip` from `translatedAccessibility`'s step walk (shared function, extracted) - exact at any
   scale. Removes the `hitboxes` refusal for this case; adds the scale-2 nested arm that catches `AT-G`'s M6.
e. **Surface gate**: moved to lane 1 (`RL-K`).

**Measure step (first commit of each lane, before code):** re-take the orbit and bracket counters at `c55d44e8` with an observer / lifecycle scopes / modifier scope
inside the occurrence and record them as the red-before numbers in the tests' headers (requests, prepaints, grafts, refusals, redos).

Lane disjointness: lane 1 owns `Lifecycle*`, `ModifierKeys*`, `RetainedGraft.swift`, `BuildJournal`/`reapply`, and the **modifier loop** in `replayPrepaintLedger`;
lane 2 owns everything else listed; the single shared function `Frame.replayPrepaintLedger` is edited by lane 1 only in a new call
`replayModifierNotes(l)` (new file), by lane 2 only in the geometry loop body. Orchestrator merges those two hunks.

## 3. Tests (name - red before at `c55d44e8` - mutation that must redden)

Lane 1 (`RetainedLifecycleTests.swift`, internal):
1. `aSteadyOccurrenceWithLifecycleScopesGrafts` - `graftRefusals["lifecycle"] > 0`, grafts 0, `retainedIneligibleReasons["lifecycle"]` > 0 - drop the journal append in `note` (1.3/1.5 also).
2. `aSteadyOccurrenceWithAModifierScopeReplaysItsLedger` - `ineligibleReasons["modifierKeys"] > 0`, prepaint replays 0 - restore the taint.
3. `lifecycleDeliveriesThroughRetentionEqualAnUnretainedWindow` - script appear, 3 steady, onChange value change, task id change, modifier change, disappear, re-insert; delivery log vs `testingRetainedSubtrees = false` and `testingGraft` off. Mutations: (i) skip the re-note (spurious onDisappear + onAppear -> red), (ii) replay the *recorded* modifier value (a modifier change is missed), (iii) re-note with `order` = 0 instead of `base + rel` (red in test 4).
4. `aGraftedOccurrenceKeepsLifecycleOrderAmongSiblings` - two scopes in the occurrence and fresh scopes before/after; `LC-F` order of simultaneous changes equals fresh - mutation (iii).
5. `aModifierChangeAcrossAReplayedLedgerDelivers` - mask-respecting (a masked-out modifier delivers nothing), old/new values - mutation (ii).
6. `aNestedOccurrencesLifecycleNotesAreJournaledOnce` - inner occurrence inside an outer graft window; no duplicate `onAppear`, ordinals equal fresh - journal appends twice for nested windows.
7. `aRedoDropsJournaledLifecycleNotes` - extends the rollback test: after a redo the store holds one note per key - leave the journal untruncated.
8. `aTaskIdChangeThroughAGraftCancelsThenStarts` - TF-A/PX-F: running-task box carried across grafts; order cancel-then-start - skip `endFrame`'s box carry (re-note returning a fresh `Entry`).
9. `verifyChannelNamesALifecycleStoreMismatch` - `METALUI_VERIFY_RETAINED` hook traps naming `lifecycleStore` when the re-note is suppressed (through `TestingHooks`' existing channel-forcing switch).
10. `anUnjournaledRegistrationRefusesTheGraftByName` - tripwire: a test-only registration bypassing the journal makes `graftRefusals["lifecycle"]` 1 - delete the audit comparison.
11. Orbit counters (`RetainedSubtreeDemoTests` style): ViewportView shape with a modifier scope and onAppear: ineligible reasons `0/0/0`, grafts > 0.

Lane 2 (`RetainedTranslationCarryTests.swift`):
12. `aLayoutShiftKeepsALocalGeometryNote` - `translationRefusedReasons["geometryTranslated"] == 1` red; delivery equals fresh - re-add the refusal.
13. `aGlobalFrameNoteIsRecomputedUnderShiftAndScroll` - fresh equality over shift, scroll, resize - keep the recorded value (stale), or omit the scroll offset.
14. `aGlobalFrameNoteUnderAPanEffectIsRecomputed` - scales 1, 2, 0.8 - recompute from the recorded ambient rather than the ambient now.
15. `anOuterNamedSpaceRefusesByName` and `aNamedSpaceDeclaredInsideTheOccurrenceIsInvariant` - `geometryNamedSpace` count 1 / 0 - delete the flag.
16. `anObserverGraftsAndAShiftNeedsNoRedo` - `retainedRedos == 0`, `geometryGraft == 0`, grafts > 0 across a shift - re-add `RG-J`; or lift it without 13 (redo 1).
17. `aLayoutShiftReplaysAccessibilityRecordsRecomputed` - tree equals a fresh window's (published tree, not counters) after shift, scroll, a clipped row at the entry clip; `accessibilityRecords` refusals 0 - shift by the old frame; skip the ambient-clip re-cut.
18. `anAccessibilityRecordUnderAnEffectStillRefusesOnLayoutShift` - the named refusal.
19. `aHitboxOpenedInsideTheOccurrencesEffectReplaysAtNonIdentityScale` - hitbox lists equal fresh at 1, 2, 0.8 - delta shift (`AT-F`'s arithmetic).
20. `aNestedEffectAccessibilityRecordIsRecomputedAtScaleTwo` - M6 ("skip nested steps") red at scale 2 (was green) - skip the steps.
21. Surface (`RL-J`): `aSteadyOnDemandSurfaceReplays` only if built; else `theSurfaceRefusalIsCountedAndCarried`.

Invariants run: whole suite under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`; fourteen images 0 px; Linux image `MetalUITestingTests` (lifecycle drain off Darwin, `MO-A`/`RU-A`: every
test settles with `tick()`, never `runUntilIdle()` after an action that needs the observation hop).

## 4. Demo, human checks, deferred

- Demo: `METALUI_RETAINED_DEMO=1` gains a "lifecycle strip" (own function, 1 MB stack): an `.equatable()` panel with `onAppear`, `onChange`, `.task(id:)` and `onModifierKeysChanged`,
  a ticking counter per callback and the ineligible-reason readout; the shift-and-scroll strip gains an `onGeometryChange(.global)` observer.
- Human checks (group `RL`): RL1 hold and release modifiers while panning the orbit: the readout shows each change once, none doubled or missed; RL2 scroll the observer list with VoiceOver on
  (a real client): the focus rect follows the row; RL3 the strip's callbacks fire once on appear, never on resize/pan.
- Deferred, named: the outer named space under translation (`RL-E`; owner a future C14, needs the space's map recorded); a hitbox clip derived inside an effect (`RG-M`); placement-memo translation
  (`FS-G`); `surface` if the `RL-J` gate fails; `AccessibilityNode`-level anything (nothing public moves).
