# 129 — Accessibility under an effect-translated replay (C14-g: the pan graft redo loop)

Branch `fix/ax-translated-replay` from `c502f14c` (master had not moved at the Record phase, so no merge and no renumbering). Not a plan task: item C14-g of the
gpui-gap list (user request 2026-10-02), from MetalCreator's graft trace of 2026-10-20. Spec `docs/superpowers/specs/2026-10-20-ax-translated-replay-design.md`;
rulings `AT-A`…`AT-G` in `docs/superpowers/2026-10-20-ax-translated-replay-decisions.md` (next unused `AT-H`). Divergence labels 585–594 reserved: none taken.
No public declaration, no census row, no SwiftUI claim (nothing here answers for SwiftUI, so no probe), no shader or pixel change, `Backends/SDL` untouched.
One implementation lane, verified `ok: true` by a separate checker.

## §1 The defect

`Frame.retainedPrepaintDecision`'s effect-translation branch (`RK-G`, `RK-S`) replayed a ledger only when `ledger.axEmissions.isEmpty && ledger.axNodes.isEmpty`: an
`AXEmission`'s `geometry` and an `AXNode`'s `frame` are computed boxes, so a ledger replayed unmoved would publish stale frames. With a client reading the tree every
node registers its emissions, so every translated occurrence fell to `.run`; a grafted occurrence then took `requestRedo` (`EquatableComponent.prepaintGroup`),
`noteRedo` suspended prepaint replay (8 frames, doubling, `RK-D`), `graftAllowed` stayed false and the whole subtree built every frame. MetalCreator measured 22 of 23
pan frames without a graft, 1409 element requests per warm pan frame.

## §2 What landed

**Recompute from the pre-effect rect, never shift a bounding box (`AT-A`).** A record made under a render effect keeps the operands `accessibilityGeometry` and `emitAXNode`
evaluate: `AXEmission.local` and `PrepaintLog`/`PrepaintLedger.axNodeLocals` (lock-step with `axNodes`), an `AXLocalRects` of the rect after the active offset, that rect cut by
the clip in force, and the effect stack. A translated replay (`Frame.translatedAccessibility(of:)`) evaluates the same two expressions against the **current** effect, so the
result is bit-equal to a fresh frame by construction (a shifted box rounds twice where `a*x + c*y + tx` rounds once: a non-dyadic scale would differ by an ulp or refuse
constantly). A clip the effect moved across needs no refusal: the visible frame is cut again at the new place. The replay also writes each node into its `$ax` slot as a run does.

**A nested effect is re-derived from recorded steps, not refused (`AT-G`, amends `AT-B`).** Measured on the bracket fixture, refusing a record made under more effects than the
occurrence began in left 0 grafts, 1 redo, 6 backoff frames (`accessibilityNestedEffect`, 51 refusals), so the item's real subject was the nested case. `PrepaintEffect` gains
`map` and `clipLocal` (set at the push, `RenderEffects.swift`), a record keeps the stack (`AXEffectChain`, one shared box per stack, `Frame.axEffectChain` dropped at the push,
pop and `withoutRenderEffects`), and the replay applies the steps after the ambient depth with `prepaintWithRenderEffect`'s own arithmetic. Only a record with no recorded rects
is refused (`accessibilityUnrecorded`, unreachable by construction).

**The translation relation assumed an identity linear part (`AT-F`, found at implementation).** `PrepaintExtras.translation(from:)` returned `nil` for any non-identity linear
part (it required the inverse to move by exactly `-Δ`; under `.scaleEffect(s)` it moves by `-L⁻¹Δ`), and `translatedHitboxes` shifted the hitbox inverse by `-Δ` likewise: a
canvas under `.scaleEffect` + `.offset` (MetalCreator's) never reached the branch (trace: `effectNotTranslation`, 10 of 10 nodes), the accessibility refusal being a second wall
behind the first. The inverse check now applies to an identity linear part only; a hitbox carrying the ledger's recorded ambient inverse takes the **current** effect's inverse
(the fresh frame's value), and a hitbox registered inside an effect the occurrence opened still moves by `-Δ` only under an identity linear part, else counts `hitboxes`.

**A scale or rotation change counts `effectNotTranslation`** (was a silent `.run`). `Window.testingAXRetainedNode(_:)` is a `package` read-back of the `$ax` slot.

**Carried (`AT-C`, `AT-G`): layout translation (`FS-P`) keeps refusing `accessibilityRecords`** (a different mechanism: frames follow a changed layout rect and the ledger is rebased;
also in C14-f's file region), and a **hitbox** registered inside an effect the occurrence opened under a non-identity scale still refuses `hitboxes` (a hitbox carries no step chain).
Owner of both: C14-h, with the recorded local rects as prerequisite.

**Files touched** (merge plan with C14-f, `RG-`, which edits `movedPrepaintLedger` and its `hitboxClipped` guard): `RetainedPrepaint.swift` only the effect-translation `if` block (the
last block of `retainedPrepaintDecision`), one line in `closePrepaintWindow`, the `PrepaintLog`/`PrepaintLedger` members, the `RetainedPrepaintMode.replay` case (fourth, defaulted
payload `accessibility:`, so C14-f's `.replay(rebased, moved: nil)` sites compile unchanged); `Frame.swift` the two geometry sites, `emitAXNode`, `replayPrepaintLedger`'s signature (a
defaulted parameter: take both if C14-f adds one), `translation(from:)`'s inverse block, `translatedHitboxes`; `EquatableComponent.swift` two lines; `RenderEffects.swift`; `AXEmission.swift`;
`TestingHooks.swift`.

## §3 Tests and guards

No typecheck guard (everything is `internal`/`package`): **249** unchanged. Root **4060** (4053 + 7: `AXTranslatedReplayTests.swift`, with parameterised arms, and two existing
tests were edited, below). Whole suite also green under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` (checker's run).

`Tests/MetalUITestingTests/AXTranslatedReplayTests.swift` (ten `ATNode` `.equatable()` components of eight labelled buttons in a `ZStack` under `.scaleEffect` then `.offset`; a `TestWindow` pair, one
retaining, one not, a client reading the tree):
1. `aPanUnderAnEffectGraftsWithAccessibilityOn`: six whole-point pan frames graft, 0 redos, 0 backoff frames, requests <= 15 % of the unretained frame, no `accessibilityRecords`.
2. `aPanUnderAnEffectPublishesTheFreshTree` (scale 1, 2, 0.8, 1.1; 0.37-point steps; 3 would be exact in `Float` and cannot separate): the published tree (nodes, frame, visible frame, order, layer, roots) equals the unretained window's every step.
3. `aPanThatCrossesTheClipRecomputesTheVisibleFrame`: a `.clipped()` window rows are panned across; tree equals fresh, half-cut rows carry the cut frame.
4. `aScaleChangeRefusesByName`: a factor change counts `effectNotTranslation`, tree equals fresh.
5. `anEffectOpenedInsideTheOccurrenceIsRecomputedFromItsSteps` (scale 1, 2; was `…RefusesByName` until `AT-G`).
6. `theAccessibilityNodeRetentionSlotFollowsAReplay`: `testingAXRetainedNode` reports the moved frame, live, as a fresh window's.
7. `theBracketPanGraftsUnderAccessibility`: grafts, 0 redos, tree read every frame.
Edited: `TranslatedReplayTests.aTranslatedReplayEqualsAFreshFrameAtEveryScale` (the accessibility arm no longer expects a refusal: `prepaintHits >= 3 * 5`, `refused == 0`);
`RetainedGraftTests.aGraftedOccurrenceUnderARefusedTranslationRedoesTheFrame` (its refusal is now a clip-dependent hitbox, `hitboxes`, not an accessibility record);
`RetainedSubtreeInternalTests` classifies the new `Frame.axEffectChain` as frame-local.

## §4 Red first, and mutations

**Red at `c502f14c`** (commit `823b0e35`): `aPanUnderAnEffectGraftsWithAccessibilityOn` (grafts 0, redos 1, backoff 6, requests 335 of 335), `aScaleChangeRefusesByName`,
`anEffectOpenedInsideTheOccurrenceRefusesByName` (then), `theBracketPanGraftsUnderAccessibility` (redos 1, grafts 0). Pin 2 is not red before (the refusal publishes fresh frames) and
separates by mutation.

**Mutations** (implementer M1–M8, each on the full unfiltered suite, restored from a copy; the checker re-read each site and test, and re-ran one of its own on a filtered set).
The five AppKit sheet issues (`appKit…Dialog…`, `CI-AF`, locked screen) and `everyKeyComponentSeparates` below are the run's background and a changed key, not findings.

| # | mutation | reddened |
|---|---|---|
| M1 | restore the `axEmissions.isEmpty` condition in the effect branch | `aPanUnderAnEffectGraftsWithAccessibilityOn`, `theBracketPanGraftsUnderAccessibility`, `aTranslatedReplayEqualsAFreshFrameAtEveryScale`, `anEffectOpenedInsideTheOccurrenceIsRecomputedFromItsSteps` |
| M2 | replay `l.axEmissions` unrecomputed | `aPanUnderAnEffectPublishesTheFreshTree`, `aPanThatCrossesTheClipRecomputesTheVisibleFrame`, `aPanUnderAnEffectGraftsWithAccessibilityOn`, `aTranslatedReplayEqualsAFreshFrameAtEveryScale`, `anEffectOpenedInsideTheOccurrenceIsRecomputedFromItsSteps` |
| M3 | shift the frames by the delta instead of recomputing | `aPanUnderAnEffectPublishesTheFreshTree` (the 0.8 and 1.1 arms), `anEffectOpenedInsideTheOccurrenceIsRecomputedFromItsSteps` |
| M4 | reuse the old `visibleFrame` | `aPanThatCrossesTheClipRecomputesTheVisibleFrame`, `aPanUnderAnEffectPublishesTheFreshTree`, `aPanUnderAnEffectGraftsWithAccessibilityOn`, `aTranslatedReplayEqualsAFreshFrameAtEveryScale`, `anEffectOpened…` |
| M5 | drop the `effectNotTranslation` count | `aScaleChangeRefusesByName` |
| M6 | skip the nested effect steps | `anEffectOpenedInsideTheOccurrenceIsRecomputedFromItsSteps` (scale-1 arm only, below) |
| M7 | skip the `$ax` write in the replay's node loop | `theAccessibilityNodeRetentionSlotFollowsAReplay`, `everyStateWriteSiteIsClassified`, and the retained-panel and list tests that read the slot |
| M8 | node frames not recomputed | `theAccessibilityNodeRetentionSlotFollowsAReplay` |
| M9 (checker) | `translatedHitboxes`: the branch giving a hitbox the current effect's inverse (`AT-F`) disabled | the `AXTranslatedReplayTests` and `TranslatedReplayTests` set, 9 issues in 10 tests (filtered set, individual names not extracted) |

M6 is caught only by the scale-1 arm: at scale 2 the nested hitbox refuses before any replay (`AT-G`'s carried hitbox), so nothing reaches the nested recompute; C14-h adds the scale-2 arm
when the hitbox carry is lifted. Nothing is left applied.

## §5 Counters, before and after (`c502f14c` against this branch)

| fixture | before | after |
|---|---|---|
| ten `ATNode`s, six whole-point pans, tree read | grafts 0, redos 1, backoff 6, element requests 335 per frame (the unretained 335) | grafts 60, redos 0, backoff 0, requests **5** per frame (baseline 335) |
| bracket fixture node pan (`.value`), tree read, 8 frames | grafts 0, redos 1, requests 798, 711 ×7 | grafts 81, redos 0, requests 198, 195 ×7 |

MetalCreator's own pan (~25 nodes, 1409 element requests) was not run (no agent touches MetalCreator): owner check `AT1`.

## §6 Verification

Native build after `swift package clean`: 0 `error:`, the only `warning:` SwiftPM's deprecation notice; suite line and `FR-J` in §7. Inventory and undocumented scripts print nothing (no public
declaration). The fourteen images 0 px against `c502f14c` (implementer; not re-taken in this phase). Linux image (`metalui-portable`): `MetalUITestingTests` 410, `MetalUILayoutTests` 230,
`MetalUICoreTests` 128, 22 further (implementer's run). `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` whole suite silent.

## §7 Counts

Measured by the Record phase after `swift package clean` on a **locked screen**: native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice; `Test run with 4060 tests in 5 suites failed after 807.979 seconds with 5 issues`, the five being exactly `AppKitPresentationTests`' sheet issues of `CI-AF` (`attachedSheet != nil`) and nothing else; `FR-J no-argument frame: succeeded=true`; 0 goldens; 249 typecheck guards (none added). `AT pin 1: grafts 60 redos 0 backoff 0 requests [5…] baseline [335…]`; `AT pin 7: grafts 81 redos 0 requests [198, 195…]` re-read from this run.

## §8 Hazards and deferrals

* **A new record under a render effect owes its local rects** (`AXEmission.local`, `axNodeLocals`): a site that appends an emission or node inside an effect without them is refused as `accessibilityUnrecorded`
  and costs a counted miss, and `METALUI_VERIFY_RETAINED=1` is the instrument.
* **Hitbox inverses are the current effect's, not shifted** (`AT-F`): a new hitbox site registered under an effect keeps carrying the ambient inverse, or it refuses `hitboxes` under a scale.
* Owed to C14-h: layout-translation accessibility (`FS-P`), a nested-effect hitbox under a non-identity scale, the scale-2 nested arm.
* No look changes. Human check group `AT` (one line: a VoiceOver focus rectangle follows a canvas pan with the graft on; an agent cannot run VoiceOver, `IX-AE`).
