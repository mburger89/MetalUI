# Accessibility under an effect-translated replay - decisions

Rulings for item C14-g. Spec: [`specs/2026-10-20-ax-translated-replay-design.md`](specs/2026-10-20-ax-translated-replay-design.md). Record: `../record/129-ax-translated-replay.md`
(Record phase). Branch `fix/ax-translated-replay` from `c502f14c`. Reserved divergence labels 585-594: none taken.

Prefix **`AT-`**, lettered. **Next unused: `AT-H`.** (Moves in the commit that appends a ruling.)

**Carried.** `RK-G`, `RK-S`, `RK-D` (record 110), `FS-P` (record 126), divergence 107, `AB-U`, `SB-AA`.

## AT-A - Recompute the frames from stored local rects; never shift a bounding box

**Ruling.** A prepaint ledger keeps, per accessibility emission and node recorded under a render effect, the pre-effect rect and the clipped pre-effect rect (and the effect depth). An effect-translated replay
evaluates `composed.boundingBox(of:)` and the outer-clip cut against the **current** effect, the expressions `accessibilityGeometry`/`emitAXNode` use.
**Evidence.** Read from `Frame.swift`: both sites are those expressions; `translation(from:)` proves equal linear parts and outer clip, and key equality proves equal rects, offset and ambient clip, so the operands are identical and the result is bit-equal to a fresh frame.
**Rejected:** shift by `(dx, dy)` with a round-trip check (the hitbox rule): `a*x + c*y + tx` rounds once, a shifted box twice, so a non-dyadic scale (0.8, 3) would refuse constantly or, unchecked, differ by an ulp (pin 2's scale 0.8 and 1.1 arms separate).
**Cost if wrong.** A replayed frame off by a ulp or a stale visible frame: `METALUI_VERIFY_RETAINED=1` compares emissions and nodes and traps naming the channel; pins 2 and 3 compare whole trees.

## AT-B - Refuse by name only what cannot be recomputed

**Ruling (amended by AT-G: `accessibilityNestedEffect` is not built; a nested effect is recomputed).** Reasons: ~~`accessibilityNestedEffect`~~ (see AT-G), `effectNotTranslation` (a delta-less change of an equal-shaped
key, scale or rotation, now counted; was silent), existing hitbox reasons. A clip the effect moved across is **not** a refusal: the visible frame is recomputed at the new place (AT-A). The task's "refuse where the shift is not exact" is met by construction, not by a refusal.
**Cost if wrong.** A missing refusal reddens pin 5 and the verify run; an extra one is a counted miss, never a wrong frame.

## AT-C - Layout translation (`FS-P`) keeps refusing `accessibilityRecords`

**Ruling.** Not the same mechanism (frames follow a changed layout rect and the ledger is rebased) and in C14-f's file region; carried to C14-h with the local rects as prerequisite.
**Cost if wrong.** A wheel scroll with a client keeps the counted redo per backoff window (FS-P's known cost): unchanged from today.

## AT-D - Internal fields only

**Ruling.** `AXEmission.local`, the ledger/log `axNodeLocals` and `AXTranslation` are internal; `AccessibilityNode` and both bridges are untouched; no census row, no divergence, no probe (nothing here answers for SwiftUI).
**Cost if wrong.** A new public field would owe a map row, a doc comment and a label from 585-594.

## AT-E - Critic's review: design stands, one test argument corrected

**Ruling.** The source claims were re-read (`accessibilityGeometry` at `Frame.swift` 2109 is exactly the two cited expressions; `translation(from:)` at 3845; the refusal at `RetainedPrepaint.swift` 262; layout translation refuses at `RetainedTranslation.swift` 309). No SwiftUI claim, public spelling, platform requirement, shader or pixel change is made, so none needs a probe. One defect fixed: pin 2's "non-dyadic scale 3" is wrong (3 is exact in `Float`, so it cannot separate shifting from recomputing); the arms are now scale 0.8 and 1.1 with a 0.37-point step.
**Rejected:** widening to layout translation (AT-C stands: C14-f's file region). **Cost if wrong.** A pin that cannot redden: the shift-by-delta mutation is run on the 0.8 arm at the Verify phase.

## AT-F - The translation relation and the hitbox move assumed an identity linear part; a scaled canvas never translated

**Ruling.** Implementation measured what the design (AT-A..AT-E) took on trust: `PrepaintExtras.translation(from:)` returned `nil` for every effect with a non-identity linear part, because it required each effect's inverse translation to have moved by exactly `-Δ`; under `.scaleEffect(s)` it moves by `-L⁻¹Δ`. `translatedHitboxes` shifted the hitbox inverse by `-Δ` with the same assumption. So a canvas under `.scaleEffect` + `.offset` (MetalCreator's) never reached the effect-translation branch at all (trace: `effectNotTranslation`, 10 of 10 nodes at the first pan frame); the accessibility refusal was a second wall behind the first. Both are fixed together, because pin 1 is unreachable otherwise:
(1) `translation(from:)` checks the inverse's `-Δ` shift only for an identity linear part (elsewhere the inverse is a function of the composed map, whose linear part, outer clip and has-inverse flag are compared equal);
(2) `translatedHitboxes` gives a hitbox whose inverse equals the ledger's recorded innermost-ambient inverse the **current** effect's inverse (the fresh frame's own value, bit-equal by construction, for any linear part), and moves any other hitbox (registered inside an effect the occurrence opened) by `-Δ` only under an identity linear part, else refuses `hitboxes`.
**Cost if wrong.** A hitbox transform that differs from a fresh frame's: `METALUI_VERIFY_RETAINED=1` compares hitbox fingerprints and traps; `aPanUnderAnEffectPublishesTheFreshTree`'s differential compares whole hitbox lists at scales 1, 2, 0.8, 1.1. Touches `Frame.swift`'s `translation(from:)` and `translatedHitboxes` (no overlap with C14-f's `movedPrepaintLedger`).

## AT-G - A nested effect is re-derived from recorded steps, not refused (amends AT-B)

**Ruling.** AT-B refused an emission recorded under more effects than the occurrence began in. Measured against the bracket fixture (MetalCreator's shape: a node's sockets are `.offset` inside a node that is itself under an `.offset`), that refusal alone left the pan at 0 grafts, 1 redo, 6 backoff frames (`accessibilityNestedEffect`, 51 refusals in the trace), so the item's real subject is the nested case. A nested effect is the ambient effect composed with its own map, so it **can** be recomputed exactly: each `PrepaintEffect` now carries its own `map` and the clip in force at its entry (`clipLocal`, only when a clip was pushed inside the enclosing effect), a record keeps the stack of those steps (`AXEffectChain`, one shared box per stack, dropped when the stack changes), and the replay applies the steps after the ambient depth to the **current** ambient effect with `prepaintWithRenderEffect`'s own arithmetic (`composed = enclosing.concatenating(map)`, `outerClip = clipLocal.map { intersect(enclosing.outerClip, enclosing.composed.boundingBox(of: $0)) } ?? enclosing.outerClip`). Bit-equal to a fresh prepaint by construction. Only a record with no recorded rects (`accessibilityUnrecorded`, unreachable by construction) is refused.
**Carried (not built).** A **hitbox** registered inside an effect the occurrence opened still moves only under an identity linear part (the delta shift, AT-F), else `hitboxes` is counted and the prepaint runs: a hitbox carries no step chain. Owner: C14-h, with layout translation (AT-C).
**Cost if wrong.** A nested record's frame off by an ulp or stale: pins 2, 5 and the bracket differential compare whole trees; `METALUI_VERIFY_RETAINED=1` compares emissions. Extra stored per record under an effect: one pointer; per effect stack, one array.
