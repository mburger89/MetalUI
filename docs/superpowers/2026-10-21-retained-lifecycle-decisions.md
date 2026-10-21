# Retained lifecycle - decisions

Rulings for item C14-h. Spec: [`specs/2026-10-21-retained-lifecycle-design.md`](specs/2026-10-21-retained-lifecycle-design.md). Record: `../record/131-retained-lifecycle.md` (Record phase).
Branch `perf/retained-lifecycle` from `c55d44e8`. Reserved divergence labels 605-614: none taken.

Prefix **`RL-`**, lettered. **Next unused: `RL-K`.** (Moves in the commit that appends a ruling.)

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
