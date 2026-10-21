# C14-g: effect-translated prepaint replay carries accessibility records - design

Branch `fix/ax-translated-replay` from `c502f14c`. Decisions: [`../2026-10-20-ax-translated-replay-decisions.md`](../2026-10-20-ax-translated-replay-decisions.md)
(prefix `AT-`). Record (written at the Record phase): `docs/record/129-ax-translated-replay.md`. No public API, no divergence label taken
(range 585-594 untouched), no SwiftUI-facing claim (divergence 107 is the existing ruling; no new probe: nothing here is a SwiftUI answer,
and gpui has no accessibility layer to consult). One lane.

**Status: implemented and recorded (2026-10-20, record 129).** Amended at implementation by `AT-F` and `AT-G`; change 2's nested-effect refusal and test 5's name are superseded, layout translation is carried to C14-h (`AT-C`).

## The defect, read in the source (not re-measured; MetalCreator's trace stands as the premise)

`Frame.retainedPrepaintDecision` (`RetainedPrepaint.swift`, the block commented "The same occurrence under render effects that moved by a
translation (`RK-G`, `RK-S`)") replays an effect-translated ledger only when `ledger.axEmissions.isEmpty && ledger.axNodes.isEmpty`, else
`noteTranslationRefused(reason: "accessibilityRecords")` and `.run`. A grafted occurrence then takes `requestRedo` (`EquatableComponent.prepaintGroup`),
`noteRedo` backs prepaint replay off 8 frames, doubling, so `graftAllowed` is false and every node subtree builds. Cause: an `AXEmission`'s
`geometry` and an `AXNode`'s `frame` are computed boxes (`Frame.accessibilityGeometry(for:)`, `emitAXNode`), so a ledger replayed unmoved would publish
stale frames.

## Mechanism: recompute from the pre-effect rect, do not shift

Inside an effect both frames are `effect.composed.boundingBox(of: local)`, with `local = bounds + activeOffset` (the node's pre-effect rect) and
`visibleFrame = intersect(effect.outerClip, composed.boundingBox(of: intersect(activeClip, local)))` (`Frame.swift`, `accessibilityGeometry`, `emitAXNode`,
and the share patch at the `candidate.accessibility` loop, which recomputes the same two expressions). Adding `(dx, dy)` to a stored bounding box is **not**
exact in `Float` for a non-dyadic scale (`a*x + c*y + tx` rounds once, a shifted box rounds twice), so the hitbox method (round-trip check, refuse
`inexactTranslation`) would refuse often. Instead the ledger keeps the two **local** rects and a replay evaluates the same two expressions against the
**current** effect. This is exact by construction (identical expression, identical operands: `PrepaintKey` equality gives equal `rects`, `ambient` incl. clip and offset,
equal linear parts and outer clip via `translation(from:)`'s `rest == oldRest` and per-effect `a == b`), covers every clip-crossing case (the
visible frame is cut again at the new place, which a shift cannot do), and needs no exactness refusal. `translation(from:)` still gates the branch: it
returns a delta only for an equal-linear-part, same-count, translation-only change (verified at `Frame.swift` `translation(from:)`: `rest == oldRest`, `a == b` with
`tx ty inverseTx inverseTy` zeroed); the delta is used for the hitboxes only, never for accessibility.

## Changes (lane 1; files)

1. `AXEmission.swift`: `AXEmission` gains `var local: AXLocalRects?` (internal; `struct AXLocalRects { frame: Bounds<Pixels>; clipped: Bounds<Pixels>; effectDepth: Int }`),
   set by `accessibilityGeometry` callers (`registerHandlers`' record, `recordAccessibility`) when `prepaintEffects` is non-empty, `nil` otherwise. Nothing reads it but the replay;
   the builder, both bridges and `AccessibilityNode` are untouched (no new node field, the `Mirror` counts hold). The share patch loop updates `local` with the geometry (it knows `candidate.rect` and
   `Self.intersect(candidate.clip, candidate.rect)`).
2. `Frame.swift`: `emitAXNode` also appends the node's local frame (`translatedByActiveOffset(bounds)`) and effect depth to a new `PrepaintLog.axNodeLocals` (lock-step with `log.axNodes`, only while a
   prepaint log is open; outside an effect `nil`); `replayPrepaintLedger` gains `accessibility: AXTranslation? = nil` (the recomputed emissions and nodes) and uses it in place of `l.axEmissions`/`l.axNodes`
   when given. New `Frame.translatedAccessibility(of:) -> Result<AXTranslation, reason>`: refuses `accessibilityNestedEffect` when any local's `effectDepth != prepaintEffects.count` (an effect opened inside
   the occurrence: its composed map includes the outer translation but the hitbox-style key check does not prove the inner one), and `accessibilityUnrecorded` when an emission under an effect has no
   `local` (defensive; unreachable by construction, pinned by a verify-run trap not a test).
3. `RetainedPrepaint.swift`, **effect-translation branch only** (the lines from the `RK-G, RK-S` comment through `noteTranslationRefused(reason: ... "accessibilityRecords")`): the `axEmissions.isEmpty` condition
   becomes `translatedAccessibility(of:)`, reasons `accessibilityNestedEffect` (new), hitbox reasons as today; `RetainedPrepaintMode.replay` gains `accessibility: AXTranslation? = nil` (default, so
   C14-f's `.replay(rebased, moved: nil)` sites compile unchanged); `PrepaintLedger.axNodeLocals` is filled in `closePrepaintWindow` beside `ledger.axNodes` (one added line);
   `differsOnlyByEffectTranslation` true with a `nil` delta (a scale or rotation change) now counts `noteTranslationRefused(reason: "effectNotTranslation")` then `.run` (was a silent `.run`).
4. `EquatableComponent.swift`: the `case .replay(let ledger, let moved, let movedBounds)` line gains the fourth binding and passes it on (2 lines).
5. Tests: new `Tests/MetalUITestingTests/AXTranslatedReplayTests.swift`; nothing else edited in tests except `everyUntranslatableKindRefusesByName`-style arrays only if a case must change (none expected: that test covers layout translation).

**Merge plan with C14-f (`perf/retained-geometry`, `RG-`).** C14-f edits `movedPrepaintLedger` and its `hitboxClipped` guard (the `memos.translatesLayout` block above the effect branch), `GeometryChange.swift`,
LayoutMemo and the atlas. This lane touches in `RetainedPrepaint.swift` only (a) the effect-translation `if` block, which is the last block of `retainedPrepaintDecision` (textual conflict only if C14-f edits within
10 lines of it), (b) one line in `closePrepaintWindow`, (c) two struct members (`PrepaintLedger`, `PrepaintLog`). `Frame.swift`: the two geometry sites, `emitAXNode`, `replayPrepaintLedger`'s signature and
the ledger's ax loop. If C14-f also changes `replayPrepaintLedger`'s signature, take both parameters.

## Carried, with reasons

* **C14-d layout translation (`FS-P`, `movedPrepaintLedger`) keeps refusing `accessibilityRecords`** (`AT-C`). It is not the same mechanism: its frames are `rect + activeOffset` with the layout rect changed by
  the shift, so the local rects would have to be re-derived from the *new* layout rect plus the new scroll offset, and the ledger is rebased, so a stored local goes stale per step. It is also in C14-f's file region. Owner: a follow-up
  after the merge (name it C14-h); the recorded `local` rects of this design are its prerequisite.
* Share patches that rewrite an emission recorded before a recorder opened already taint (`sharePatchesOutside`): unchanged.
* A `GPUSurface`/popover/alert inside the occurrence stays ineligible (`RW-L`).

## Tests (all in `AXTranslatedReplayTests.swift`, MetalUITesting, `TestWindow` with a client reading the tree; counts from `FrameWork`; fixture: 10 `.equatable()` `ATNode` components, 8 labelled rows each, in a `ZStack` under `.scaleEffect(2)` (constant) then `.offset` stepped by whole points, 12 warm frames then 6 pan frames)

1. `aPanUnderAnEffectGraftsWithAccessibilityOn` - on the 6 pan frames `retainedGrafts > 0`, `retainedRedos == 0`, `retainedBackoffFrames == 0`, element requests <= 15% of the warm unchanged-nothing baseline,
   `retainedTranslationRefusedReasons["accessibilityRecords"] == nil`. **Red before**: redos > 0 and grafts 0 at `c502f14c` (the refusal). **Mutation that must redden**: restore the `ledger.axEmissions.isEmpty` condition in the effect branch.
2. `aPanUnderAnEffectPublishesTheFreshTree` (arguments: scale 1, 2, 0.8 and 1.1 (non-dyadic: 3 is exact in Float and would not separate) with a step of 0.37 points) - after each step the published tree (`nodes`, `geometry` frame and visibleFrame, `order`, `layer`, `roots`) equals a fresh `TestWindow` built at that offset,
   under `METALUI_VERIFY_RETAINED=1` silent. **Red before**: not red at `c502f14c` (the refusal publishes fresh frames), so it separates by mutation: replaying `l.axEmissions` unrecomputed (a shifted-by-zero ledger) reddens every step; shifting by `delta` instead of recomputing reddens the scale 0.8 and 1.1 arms (the rounding case).
3. `aPanThatCrossesTheClipRecomputesTheVisibleFrame` - a `.clipped()` window the pan moves rows across: tree equals fresh and the visible frame of a half-cut row is the cut one. Mutation: reuse the old `visibleFrame` reddens it; a mutation that drops the `clipped` local reddens too.
4. `aScaleChangeRefusesByName` - changing the `.scaleEffect` factor between frames counts `retainedTranslationRefusedReasons["effectNotTranslation"]`, tree equals fresh. **Red before**: the reason is absent (silent `.run`). Mutation: delete the new `noteTranslationRefused` call.
5. `anEffectOpenedInsideTheOccurrenceRefusesByName` - a node whose body holds its own `.offset` over labelled content, under a panning outer effect: refuses `accessibilityNestedEffect`, tree equals fresh. Mutation: drop the `effectDepth` comparison reddens it (stale inner frames) under the tree comparison.
6. `theAccessibilityNodeRetentionSlotFollowsAReplay` - after a replayed pan step `axNode(for:)` of a labelled element reports the moved frame and `isValid`, as a fresh window's. Mutation: skip the `$ax` write in the replay's node loop.
7. `theBracketPanGraftsUnderAccessibility` - the bracket fixture (`BracketFixture.swift`) node drag with the tree read each frame: before/after counters reported in the record; asserted only `retainedRedos == 0` on steady frames.
8. Guard-free: no new typecheck guard (all `internal`/`package`); `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` whole-suite run is the invariant.

## Demo, human checks

No demo change (`METALUI_RETAINED_DEMO=1` already pans under an effect); human check group `SI`-style addition: none (no look changes; VoiceOver cannot be claimed by an agent, `IX-AE`). Add one line to `docs/verification/human-checks.md` at the Record phase: a VoiceOver focus rectangle follows a canvas pan with graft on.

## Amendments found at implementation (rulings AT-F, AT-G)

* **AT-F.** `translation(from:)` and `translatedHitboxes` assumed an identity linear part, so a canvas under `.scaleEffect` + `.offset` never reached the effect branch (the "verify" this design asked for was
  run: it returns `nil` under any scale). The inverse-shift check now applies to an identity linear part only; a hitbox carrying the ledger's recorded ambient inverse takes the current effect's inverse. Touches `Frame.swift`'s
  `translation(from:)` (the inverse block) and `translatedHitboxes`.
* **AT-G.** The nested-effect refusal (design change 2, AT-B) is replaced by recomputation from recorded effect steps: `PrepaintEffect` gains `map`/`clipLocal`, `AXLocalRects` holds an `AXEffectChain` instead of `effectDepth`,
  `RenderEffects.swift` records the two fields at the push and drops the cached chain at the push, pop and `withoutRenderEffects`. Test 5 becomes `anEffectOpenedInsideTheOccurrenceIsRecomputedFromItsSteps`; test 7 asserts grafts and no redo.
