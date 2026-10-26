# Retained replay when layout and the outer effect moved together (FS-O) - decisions

Rulings for item FS-O of the gpui-gap priority list (user request 2026-10-02; carried by `RG-N`, `RZ-` "Carried", not a plan task). Prefix `EL-`.
**Next unused: `EL-K`.** Spec: [`specs/2026-10-26-effect-and-layout-moved-design.md`](specs/2026-10-26-effect-and-layout-moved-design.md). Record: `../record/157-effect-and-layout-moved.md`.
Branch `perf/effect-and-layout-moved` from `aad9faf4`. Amends `RG-N` and `FS-O` (the "not combined" clause). Divergence labels reserved 865-874: none taken.

Sources of truth: `RetainedTranslation.swift`, `RetainedSubtree.swift` (`effectRelation`, the paint decision), `RetainedPrepaint.swift` (the prepaint decision), `Frame.swift` (`translatedHitboxes`, `translatedAccessibility`), `RetainedTranslationCarries.swift`. Predecessors: `FS-D`..`FS-P`, `RK-G`/`RK-S`, `RZ-A`..`RZ-T`, `RL-E`/`RL-H`/`RL-I`, `AT-A`/`AT-F`, `MA-H`/`MA-I`.

## EL-A - No SwiftUI or gpui claim; the contract is "equal to a fresh frame"

**Ruling.** The item adds no SwiftUI-facing behaviour: a replay is value-identical to a fresh frame, so there is no SwiftUI probe and no divergence. gpui's `reuse_prepaint`/`reuse_paint` replay at an unchanged element offset; its handling of a moved offset is **recalled, not verified here** and is not relied on. The oracle is the retention-off window of the `RPPair` harness plus `METALUI_VERIFY_RETAINED=1`. **Evidence.** `RG-N` test 12 already compares to a retention-off window at each step. **Cost if wrong.** none (no behaviour claim).

## EL-B - Compose the two existing moves, the layout delta first in the occurrence's own space, the effect second

**Ruling.** Recorded leaves and ledger rects are in pre-effect space (`RZ-A`: leaves are recorded before any outer scope applies; hitboxes keep local `bounds` and a separate `transform`). The combined replay is `effect_now(local + delta)`: add the whole-device-pixel layout delta (`FS-M` exactness) to leaves, hitbox `bounds`/`origin`/`unclipped`, accessibility locals, geometry `moved` rects; then let the live scopes (paint) or the current inverse/composed map (prepaint) apply the effect. **Reasoning.** It is what a fresh frame computes; any other order differs under a scale (`s*delta`). **Evidence.** `movedPaintRecord` reads only rects, offset, clip and depths; `translatedHitboxes` rewrites only the transform: the two halves touch disjoint fields, so they commute in code and the order is a property of space, pinned by T2/T5b. **Cost if wrong.** A wrong order draws or hits at a stale spot only when scale != 1; verify mode and the retention-off comparison trap it.

## EL-C - One new relation, delegating to the old two

**Ruling.** `shiftAndEffects` accepts keys whose shape moved **and** whose outer effect scopes differ in the affine numbers only (`EffectChange.translation`/`.affine`); it delegates to `shift(from:)`/`shift(to:)` when the scopes are equal, so the layout arm cannot change, and the effect arm (rects equal) stays the first branch. The effect-scope normalisation loop of `effectRelation` is factored into one helper both read. **Reasoning.** Two copies of "which fields of a scope are the affine ones" drift (the `RZ-M` appended-index rule). **Cost if wrong.** A key field one relation omits makes a stale replay; the verify-mode channel check and T11 (old arms unedited) catch it.

## EL-D - A hitbox, record or note inside an occurrence-opened effect refuses under a layout shift: `effectAndLayoutInner`

**Ruling.** An effect the occurrence itself opens (`chain.steps.count > base`) has a map anchored at the occurrence's own position (`.scaleEffect(anchor:)` reads the node's rect), so a layout shift changes it in a way neither the delta nor the ambient re-derivation names; paint already refuses it (`innerScope`). The prepaint refuses by the **new name** `effectAndLayoutInner` instead of a quiet fall-through. **Cost if wrong.** An occurrence with an inner effect under a combined move keeps building (as today).

## EL-E - A geometry note holding a named space refuses `geometryNamedSpace` in the combined arm

**Ruling.** A named space would need `L*delta` plus the effect delta with dyadic checks on both (`RL-E` checks one). The affine arm already refuses it (`RZ-E`); the combined arm inherits the refusal. Notes without a named space are remade (delta, then the current composed map). **Cost if wrong.** A named-space observer under a zoom while the layout moves rebuilds.

## EL-F - Presentation anchors and context-menu records refuse in the combined arm

**Ruling.** They are drawn window rects. `MA-H` shifts them by an effect translation, valid because the layout is unmoved; with a layout move the window shift is `L*delta` for the effect's linear part, which `windowShift` does not carry, and an affine change already refuses them (`RZ-F`). The combined arm refuses both, even for a pure-translation effect (`presentationAnchor`, `contextMenus`). **Cost if wrong.** A popover declarer or `.contextMenu` inside a zooming, shifting subtree rebuilds; the common case (cards, text, buttons) replays. Owner: the next retained item.

## EL-G - A rebase carries the **moved** locals; a ledger and a record rebase to the whole new key

**Ruling.** On a combined hit the paint record's `key` becomes the new key whole (scene is pre-effect and `finalScene` is nil under any scope, so the effect numbers in the key are sound), and the ledger is rebased with its moved hitboxes, element bounds, **accessibility locals** and geometry notes, so the next unchanged frame is an exact hit and not a second move. **Evidence.** `FS-O` rebase; `PrepaintLedger.rebased(to:_:)` copies `hitboxChains` and locals (`T4`, `T7`). **Cost if wrong.** A skipped locals rebase makes the next frame's AX frame wrong by the delta (T7 settle step).

## EL-H - The graft is not touched; its pin may find a refusal

**Ruling.** The graft decision does not read the shift relation; no change is planned. T6 pins grafts > 0 across the combined frame. If the graft site refuses for a reason the combined key introduces, the lane reports the name and stops: the graft is a separate decision (`RK-`, `RL-`), not widened here. **Cost if wrong.** The combined arm replays paint and prepaint but still builds the subtree (requests do not fall as far).

## EL-I - `hitboxUnderEffect` and `accessibilityUnderEffect` stay for the layout-only arm

**Ruling.** A layout shift under an **unchanged** effect still refuses a transformed hitbox and an effect-made accessibility record (`FS-P`, `RL-H`'s rule). Lifting that is the same machinery, but it is a different relation and changes existing pins; out of scope, named in the spec as carried. **Cost if wrong.** none new.

## EL-J - Counter retirement and expectations

**Ruling.** `effectAndLayoutMoved` is retired (never emitted; T13), like `effectNotTranslation`; the pure-translation line in `retainedPrepaintDecision` goes with it and the silent affine + layout fall-through gets a name for every refusal. Demo expectation: a combined step costs element requests ~5-6 and prepaints ~5-6 for six panels against 115/117 off, **dated and re-taken at the Record phase**, never pinned (pins count work on the fixture). **Cost if wrong.** A test or doc citing the old name reddens; `RG-N` is amended in the record, not in `docs/record/` before the Record phase.
