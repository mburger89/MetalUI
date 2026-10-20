# Accessibility under an effect-translated replay - decisions

Rulings for item C14-g. Spec: [`specs/2026-10-20-ax-translated-replay-design.md`](specs/2026-10-20-ax-translated-replay-design.md). Record: `../record/129-ax-translated-replay.md`
(Record phase). Branch `fix/ax-translated-replay` from `c502f14c`. Reserved divergence labels 585-594: none taken.

Prefix **`AT-`**, lettered. **Next unused: `AT-F`.** (Moves in the commit that appends a ruling.)

**Carried.** `RK-G`, `RK-S`, `RK-D` (record 110), `FS-P` (record 126), divergence 107, `AB-U`, `SB-AA`.

## AT-A - Recompute the frames from stored local rects; never shift a bounding box

**Ruling.** A prepaint ledger keeps, per accessibility emission and node recorded under a render effect, the pre-effect rect and the clipped pre-effect rect (and the effect depth). An effect-translated replay
evaluates `composed.boundingBox(of:)` and the outer-clip cut against the **current** effect, the expressions `accessibilityGeometry`/`emitAXNode` use.
**Evidence.** Read from `Frame.swift`: both sites are those expressions; `translation(from:)` proves equal linear parts and outer clip, and key equality proves equal rects, offset and ambient clip, so the operands are identical and the result is bit-equal to a fresh frame.
**Rejected:** shift by `(dx, dy)` with a round-trip check (the hitbox rule): `a*x + c*y + tx` rounds once, a shifted box twice, so a non-dyadic scale (0.8, 3) would refuse constantly or, unchecked, differ by an ulp (pin 2's scale 0.8 and 1.1 arms separate).
**Cost if wrong.** A replayed frame off by a ulp or a stale visible frame: `METALUI_VERIFY_RETAINED=1` compares emissions and nodes and traps naming the channel; pins 2 and 3 compare whole trees.

## AT-B - Refuse by name only what cannot be recomputed

**Ruling.** Reasons: `accessibilityNestedEffect` (an emission recorded under more effects than the ambient: its composed map folds in an effect this decision did not compare), `effectNotTranslation` (a delta-less change of an equal-shaped
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
