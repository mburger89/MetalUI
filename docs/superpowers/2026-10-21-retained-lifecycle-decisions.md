# Retained lifecycle - decisions

Rulings for item C14-h. Spec: [`specs/2026-10-21-retained-lifecycle-design.md`](specs/2026-10-21-retained-lifecycle-design.md). Record: `../record/131-retained-lifecycle.md`.
Branch `perf/retained-lifecycle` from `c55d44e8`. Reserved divergence labels 605-614: none taken.

Prefix **`RL-`**, lettered. **Next unused: `RL-R`.** (Moves in the commit that appends a ruling.)

**Carried.** `RK-E`, `RK-F`, `RG-A`, `RG-C`, `RG-D`, `RG-J`, `AT-C`, `AT-G`, `RW-L`, `KF-J`, `IF-D`, `LC-C`...`LC-I`, `PX-F`, `TF-A`.
No SwiftUI probe: no observable behaviour moves (`RG-B`'s argument); the oracle is differential against a window with retention off. gpui has no lifecycle-scope analogue to compare.

## RL-A - Replay re-notes presence; the store's diff decides every delivery

**Ruling.** A replay or graft re-notes each scope into `LifecycleStore` exactly as a build would and never computes a delivery. **Evidence.** The store forgets any key a build did not note
(`endFrame` previous-minus-current; `closeGeometry`/`closeModifierKeys` drop silently), so a skipped note is a spurious disappear, appear or `initial` re-report; a re-noted one is silent when equal.
"Refuse only when a callback must run" therefore needs no new refusal: a changed `onChange` value or `.task` id comes from a re-evaluated getter (value or observed read changed), which cannot graft; a
first appearance is a new key; a modifier change is the current value differing from the stored one. **Alternatives rejected.** A retention-side prediction of which callbacks fire (a second source of truth for `LC-F`/`LC-H`).
**Cost if wrong.** A value captured from non-tracked mutable state (outside `.equatable()`'s contract, already true of `RG-A`) replays stale; test 3 compares with an unretained window.

## RL-B - A modifier note is a ledger entry holding no value

**Ruling.** `ModifierNoteRecord{watch,key,owner}` replaces the `modifierKeys` taint; replay reads `currentModifiers` itself. Amends `RG-D` ("stale by construction": true of a recorded *value*, false of a recorded *note*).
Valid under translation. **Cost if wrong.** A missed change reddens tests 3 and 5 (mutation ii).

## RL-C - Lifecycle layout notes are journal events with relative orders

**Ruling.** `LifecycleStore.note`/`reserveOrder` append to the attached `BuildJournal`; `Frame.reapply` re-notes at `base + rel` and advances `nextOrder` by the window's count. **Reasoning.** Layout is what a graft
skips, `RK-F` already replays other stores through the journal, and absolute orders would collide with siblings (`LC-F`). Scopes with empty content reserve an order but note nothing: the count, not the note list, advances. **Alternatives rejected.**
Recording the scopes in `LayoutSegment` (layout rows are restamped, not store calls); re-running only the lifecycle `requestGroupLayout` (needs the element tree). **Cost if wrong.** Wrong `LC-F` order among simultaneous changes: test 4. Not a `StateTable` write site, the seven slots unmoved.

## RL-D - The audit stays as a tripwire, not a gate

**Ruling.** `BuildAudit.lifecycle` counts registrations that bypassed the journal; it is 0 in every window and refuses by name if a new site forgets. `METALUI_VERIFY_RETAINED=1` compares the store after a graft (`lifecycleStore`).
**Cost if wrong.** A new unjournaled site grafts wrongly only if both tripwires are removed.

## RL-E - Geometry under translation: re-run the transform on a rebuilt proxy

**Ruling.** A translated replay of a ledger with geometry notes rebuilds the `GeometryProxy` from the recorded size, pre-effect rect and recorded effect steps against the current ambient, calls `transform` again and notes the result;
`RG-C`'s blanket refusal becomes `geometryNamedSpace` (an outer named space in force) only. **Reasoning.** `RG-C` named exactly this as the cost of lifting; `RG-A` rejected re-running for the *equal-key* case, where it is wasted, not for
a translated one, where the value changed. The transform already runs once per fresh prepaint and must not write. **Cost if wrong.** A non-pure transform runs one extra time per translated replay; tests 13-14 compare with fresh.

## RL-F - An outer named space refuses; an inner one is invariant

**Ruling.** Recording the outer space's map is more state than this item buys (carried). **Cost if wrong.** A list of observers under `.coordinateSpace` keeps building (today's cost).

## RL-G - `RG-J` lifts only after the redo is measured gone

**Ruling.** Gate in lane 2: with `RL-E` in, test 16 must show `retainedRedos == 0` across a shift for a grafted observer; otherwise `RG-J` stays and the lift is re-carried with the measured redo count.
**Cost if wrong.** A graft that redoes costs two builds plus backoff (`RG-J`'s own figure): the gate exists to prevent it.

## RL-H - Layout translation of accessibility is the same mechanism

**Ruling.** Built, not carried (amends `AT-C`): frames follow `window delta` applied to the recorded post-scroll rect, the visible cut recomputed against the ambient clip by the hitbox rule (`hitboxClipped`'s `inside` test), records under an effect still refuse by name.
**Evidence.** `AXLocalRects.frame` is already the post-offset pre-effect rect (`Frame.swift` share patch); `AT-C`'s stated prerequisite is met by `AT-A`. **Cost if wrong.** A stale visible frame: the verify run compares emissions; test 17 compares published trees.

## RL-I - A hitbox inside the occurrence's own effect carries the step chain, off `Hitbox`

**Ruling.** A ledger-side parallel `hitboxChains` array (the `axNodeLocals` pattern); `translatedHitboxes` reuses `translatedAccessibility`'s step walk. `Hitbox`'s layout is untouched. Closes `AT-G`'s carry and adds the scale-2 nested arm for M6. **Cost if wrong.** Hitbox transform off by an ulp: the verify run fingerprints hitboxes; test 19 compares whole lists.

## RL-J - `surface`: measure first, default re-carry

**Ruling.** The last lane-2 commit measures an `.onDemand` surface (unchanged `value:`) inside an `.equatable()` occurrence. It is built only if all hold: paint-only (no build or layout registry write other than the `occurrence(for:)` count), the replay can re-emit the quad
and re-touch the target without a draw, `.continuous` and changed `value:` still refuse, and the fourteen images stay 0 px. A replayed paint must re-do `surfaceRegistry.occurrence(for:)` and the target-retention touch or the registry releases the target (`MV-`); that is a
second store like the lifecycle one, so the default is `RW-L` carried with the measured counts. **Cost if wrong.** A surface inside a retained occurrence keeps painting (today's behaviour).

## RL-K - The surface gate moves to lane 1 (critic)

**Ruling.** `RL-J`'s measurement and any build belong to lane 1, not lane 2. **Reasoning.** A replayed surface must re-do `SurfaceRegistry.occurrence(for:)` and the target touch: a per-window store re-noted by a replay, the lifecycle store's shape (`RL-A`), and
lane 2 already carries geometry, two accessibility mechanisms and a hitbox chain (10 of 21 tests). The only shared file is `Frame.drawSurface`/`PaintRecord`, which lane 2 does not edit. **Cost if wrong.** A merge hunk in `PaintRecord`; the default remains `RW-L` carried.

## RL-L - A replayed or journaled closure is the standing one (rejected alternative: re-capture)

**Ruling.** A replayed `onChange` action, `.task` body and journaled lifecycle `write` are the closures of the build that recorded them; this is `.equatable()`'s contract, as for `RG-A`'s transform and the ledger's press-only actions. Rejected: refusing any scope whose closure is non-`Equatable`
(there is no way to compare it, and every scope would refuse again). **Pins.** Test 3 gains an arm where the action reads `@State` through a binding (current value delivered, not a stale copy); the journal holds closures only on the memo entry's record, so
`MemoryReleaseTests` gains an arm for a window closed while an occurrence with `.task` and `onChange` is grafted (`IV-R`). **Cost if wrong.** A stale captured plain value, outside the contract.

## RL-L2 - Demo and pixels (note, not a ruling)

The lifecycle strip is behind `METALUI_RETAINED_DEMO=1`, so the fourteen offscreen images (default demo) cannot move; the 0 px comparison is still run. The strip is its own function (1 MB stack).

## RL-M - `surface` stays refused (`RW-L` carried, measured; closes `RL-J`/`RL-K`)

**Ruling.** Not built. **Measurement.** `RetainedWithStateTests`' channel table (`RW-M`, re-run at this branch's base) already reads, for an `.onDemand` surface in an `.equatable()` occurrence: paint refused once (`surface`), prepaint replays, graft 0 refusals
(`GPUSurface` registers nothing at build or layout beyond the `.surface` leaf; `SurfaceRegistry.buildActivity` moves only at paint), so the whole cost is **one element paint per surface per frame**. A paint replay would owe: (1) a `.surface` arm in `CapturedPrimitive`/`translatePrimitive`
(today `unlistedKind:surface`); (2) re-appending the frame's `SurfaceDrawRequest` with the current `time` and the `draw` closure of the record that made it (`RL-L`'s contract, but a closure the renderer **calls**); (3) re-doing `SurfaceRegistry.occurrence(for:)` and `id(for:occurrence:)` so
the target is not released by `endFrame` (`MV-E`); (4) the same on SDL's table. Sound in principle (the lifecycle store's shape, `RL-A`), but for one leaf's paint, with a renderer-visible closure that must be the standing one and no way to pin "the GPU did not redraw" on the headless platform
(no surface draws, `HT-`). **Cost if wrong.** A surface inside a retained occurrence keeps painting (today's behaviour); owner a future C14 with a GPU-backed measurement.

## RL-N - Where the build came out different from the spec (lane 1)

**Rulings.** (1) The reserved-order count is a field of `GraftRecord` (`lifecycleOrders = nextOrder at close - lifecycleBase`), not a `.lifecycleOrders` event: a nested window's count then includes what an inner graft advanced, and `reapply(_:lifecycleOrders:)` advances once after the notes.
Notes are relative to `GraftRecorder.lifecycleBase` at close (the journal holds absolute orders while recording, so every open window converts from the same numbers). (2) `RL-D`'s tripwire is `buildActivity = workThisFrame + nextOrder - journaledActivity`, the
journal's own counter reset at `endFrame` and `rollbackBuild` (test 7). (3) Verify mode's `lifecycleStore` channel digests the lifecycle, geometry and modifier notes of the build in progress (keys, orders, presence; a modifier's masked value), so a replayed modifier or geometry note that differs also traps by that name.
(4) The old pin `aGraftIneligibleBuildIsCountedByName(kind: .lifecycle)` is now a control arm (grafts), like `.scroll` after `RW-H`. **Cost if wrong.** As `RL-C`/`RL-D`.


## RL-O - An outer named space never reaches the geometry note (amends `RL-E`, `RL-F`)

**Ruling.** `prepaintRefusal()` already refuses a prepaint window opened while `Frame.namedSpaces` is non-empty (`namedSpaces`, counted ineligible), so **no ledger exists for an occurrence under an outer named space** and `geometryNamedSpace` can never name one. `RL-F`'s "outer refuses" is therefore the existing upstream gate, pinned
as such (test 15a: hits 0, ineligible reason `namedSpaces`, no geometry refusal). Every named space a note sees is declared **inside** the occurrence and moves with it. A translated replay moves each such space's `toWindow` by what the position moved, exactly: a layout shift by `a*dx + c*dy`, `b*dx + d*dy`
(the window delta in the space's pre-effect frame), an effect translation by the ambient composed map's translation delta, `toSpace` its inverse; **only when the space's linear part is made of multiples of 1/16** (identity, scale 2, 0.5), because the products and sums are then exact in `Double`
whatever the order they are added in, so the moved map is bit-equal to the one a fresh prepaint composes. A non-dyadic linear part (a 0.8 scale) refuses by name `geometryNamedSpace` (and keeps `RG-J`'s graft refusal, `RL-Q`). **Cost if wrong.** A named frame an ulp off a fresh one under a dyadic space: test 15b compares deliveries to a fresh window's at scales 1 and 2, layout shift and pan.

## RL-P - Where the build came out different from the spec (lane 2)

**Rulings.** (1) `GeometryNoteRecord` holds `size`, `moved`, `composed`, `chain` (an `AXEffectChain`) and `namedSpaces` beside the value: `Frame.movedGeometryNotes` (layout, scroll) and `Frame.translatedGeometryNotes` (effect) rebuild the proxy and call `transform` again, in `RetainedTranslationCarries.swift`; the replay takes the made-again notes through a new `geometry:` parameter
of `replayPrepaintLedger` and the `.replay` case, and appends them to an enclosing log, so a nested ledger holds the moved values. A note made under an effect the occurrence opened refuses a **layout** shift by name `geometryUnderEffect` (such an effect's map is anchored to the occurrence's own position: the recorded steps do not re-derive it for a layout move) and is fine under an effect translation (the step walk).
(2) `RL-G`: `graftRecord` refuses `geometryGraft` only when a note is not recomputable (`Frame.geometryNotesRecomputable`: an inner effect or a non-dyadic named space), because those are the notes whose translated replay refuses and would cost the redo. Measured: test 16, a grafted two-card observer, steady frames graft 2/2 and three shifts across the graft cost `retainedRedos == 0`, backoff 0.
(3) `RL-H` as built: `AXEmission` gains `clipDepth` (the hitbox's own rule: a record at the entry depth is cut again against the ambient clip, one deeper moves only if it stays strictly inside the clip before and after, refusing `accessibilityClipped`), `Frame.movedAccessibility` moves emissions and nodes by the window delta; a record with `local != nil` refuses `accessibilityUnderEffect`. `AXLocalRects` is unchanged (the spec's `clipDepth`/`entryClipCut` fields were not needed: no record under an effect is recomputed on a layout shift). `rebased` carries `axNodeLocals` and the moved records.
(4) `RL-I` as built: the chain is a `Frame.hitboxChains[index]` side table kept only while a prepaint log records and only for a hitbox under an effect, copied into `PrepaintLedger.hitboxChains` (lock-step with `hitboxes`, empty when none sat under an effect). `translatedHitboxes` re-derives such a hitbox from the shared `Frame.walkEffectSteps` and
**validates the walk first**: the walk from the ambient *as recorded* must reproduce the transform (inverse and outer clip) the hitbox carries, else a share patch rewrote it and it refuses `hitboxes`; then the walk from the ambient now gives the transform. This replaces the old identity-linear delta rule for a chained hitbox, at every scale, and also lifts the refusal of a hitbox whose outer clip depended on the translation (`RK-S` item 2):
the walk recomputes that clip. Two pins of earlier records were superseded and amended in this commit: `aHitboxWhoseClipDependedOnTheTranslationIsNotMoved` (now `...IsRecomputedFromItsSteps`, refusals 0, prepaint hits 5) and `aGraftedOccurrenceUnderARefusedTranslationRedoesTheFrame` (its refusal is now a fractional device-pixel shift, `fractionalTranslation`), as `RG`'s tests 5 and 7 (refusal -> recomputed) and `FSRefusal.accessibility` (removed; test 18 owns the surviving refusal).
(5) Refusal names added: `geometryUnderEffect`, `geometryNamedSpace`, `geometryUnrecorded`, `accessibilityUnderEffect`, `accessibilityClipped`, `accessibilityUnrecorded`; `geometryTranslated` and the layout `accessibilityRecords` are gone. Order of refusal names in `movedPrepaintLedger` changed for an occurrence with two causes: the press-only and context-menu checks now come first (`pressOnly` shows where `accessibilityRecords` did).
**Cost if wrong.** As `RL-E`, `RL-H`, `RL-I`.

## RL-Q - A graft keeps its refusal only for a note a translation cannot recompute

**Ruling.** The `RG-J` refusal narrows to `Frame.geometryNotesRecomputable == false`; see `RL-P` (2). **Carried.** The outer named space is not reachable (`RL-O`); a note under an effect the occurrence opened on a layout shift (needs the effect's anchor re-derived: `RG-M`'s neighbour); named spaces with a non-dyadic linear part.
