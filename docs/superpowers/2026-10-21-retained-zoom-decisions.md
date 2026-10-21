# Retained zoom - decisions

Rulings for item C14-i. Spec: [`specs/2026-10-21-retained-zoom-design.md`](specs/2026-10-21-retained-zoom-design.md). Record: `../record/133-retained-zoom.md`.
Branch `perf/retained-zoom` from `1bdead8d`. Reserved divergence labels 625-634: none taken (346 narrowed in place if `RZ-I` lands).

Prefix **`RZ-`**, lettered. **Next unused: `RZ-S`.** (Moves in the commit that appends a ruling.)

**Carried.** `RK-G`, `RK-S`, `FS-D`, `FS-O`, `FS-P`, `RG-A`, `AT-A`, `AT-F`, `AT-G`, `RL-E`, `RL-I`, `EE-A`...`EE-D`, `IV-D`, `GX-` (effects, text and images resampled, divergence 106), `RW-S`.
No SwiftUI probe: no observable behaviour moves; the oracle is differential against a window with retention off plus `METALUI_VERIFY_RETAINED=1`.

## RZ-A - A zoom replays by re-entering the live scopes; nothing is re-pointed

**Ruling.** A paint record replayed under a changed outer effect goes through `processScopes` with the live scopes, as the translated replay already does; no `MUITransform` index is rewritten and
no leaf is edited. **Evidence.** `RetainedRecord.scene` holds leaves before any outer scope; `replayPaint(translated: true)` calls `processScopes(op.leaves, from: op.boundary, ...)`;
`effect.apply(to:flattens:outer:)` maps a flattening effect's numbers, and a non-flattening one's `MUITransform` is chosen at `insertIntoScene(transform:)`: both are functions of the
live scope, so replay is arithmetic-for-arithmetic a fresh paint. **Alternatives rejected.** Rewriting transform indices in the record (valid only for the non-flattening kind, and
the flattening one maps coordinates, so it would need the map anyway); a second replay path. **Cost if wrong.** Stale pixels at a new scale: `METALUI_VERIFY_RETAINED=1` compares fresh
paint beside every replay (Z4 is the instrument).

## RZ-B - The key relation admits an affine change of an effect scope, and names what it refuses

**Ruling.** `ReplayKey.differsOnlyByEffectAffine(from:)` and `PrepaintExtras.change(from:)` accept a difference confined to the six affine numbers of `.effect` scopes (and the inverse's six
in the extras) with equal `flattens`, `alpha`, entry depth, outer clip, `hasInverse`, saved clip base, scope and effect count, and no shadow or blur on a differing scope; the pure
translation keeps its existing arm unchanged. Refusals are counted by name: `effectFlatteningChanged`, `effectClipChanged`, `effectInverseChanged`, `effectScopeChanged`, `effectCountChanged`.
**Reasoning.** An outer clip is derived from the composed map and the clip local to it, so a changed linear part with a clip in the effect changes what is cut, which a re-entry cannot
reproduce from a record made at another clip; equal clips make the re-entry exact. **Cost if wrong.** A missed condition replays a wrong cut: Z5's per-arm mutations.

## RZ-C - Rasters are not a refusal: a vector reaches the raster at insert, and a new scale is a new key

**Ruling.** Paths, gradients, shadows and blurs under a zoomed effect are re-rastered by the ordinary `RasterAnchor`-keyed cache on the step (work equal to a fresh frame), with no retention
refusal. **Evidence.** `CapturedPrimitive.path`/`.gradient` carry the vector and `local`; `insertIntoScene` composes the `PrimitiveTransform` and rasters (`pathImage`, `gradientImage`,
`shadowItem`); the key is a pure function of the composed map. **Fallback.** If Z4 or verify mode shows any raster kind differing, that kind refuses `effectRasterUnderScale` and this
ruling is amended before the lane lands. **Cost if wrong.** A stale raster at a new scale (a key missing a field): Z4.

## RZ-D - Hitboxes are re-derived from the current effect; the pointer is read against the moved ones

**Ruling.** For an affine change `translatedHitboxes` runs with no delta: the ambient inverse is swapped for the current one (`AT-F`), hitboxes registered in an effect the occurrence opened
walk their recorded steps (`RL-I`), and the delta arm (valid only for an identity linear part) refuses `hitboxes`. The pointer is tested against the **moved** hitboxes, as `FS-P`
does; a hit runs the prepaint. **Reasoning.** Zoom moves content under a stationary pointer, which the old-hitbox superset (`retainedPointerIsInside(ledger)`) does not see.
**Cost if wrong.** A stale hover or a click on the old geometry: Z3, Z7, Z8.

## RZ-E - Accessibility recomputes, geometry notes with named spaces refuse

**Ruling.** Accessibility frames recompute through `translatedAccessibility(of:)` (`AT-A`), unchanged. A geometry note re-runs on a rebuilt proxy (`RL-E`); a named space
moves by a translation only, so a note holding one refuses `geometryNamedSpace` under a changed linear part. **Cost if wrong.** A published frame an ulp off a fresh window's: Z2's
non-dyadic arms; Z5's named-space arm.

## RZ-F - Anchors and context-menu rects refuse under an affine change until pinned

**Ruling.** A ledger holding presentation anchors or context-menu records refuses an affine change by name (`presentationAnchor`, `contextMenus`). The translation arm replays them
unmoved today; the Z5 anchor arm audits that, and a finding is fixed in this lane by the same refusal. **Reasoning.** Both hold window-space rects whose recomputation is not recorded;
a refusal is the cheap, safe choice. **Cost if wrong.** A popover that opens at a pre-zoom place: Z5.

## RZ-G - No public API and no new counter

**Ruling.** A zoom hit counts under the existing `retainedTranslated`/`retainedPrepaintHits`; a refusal under `retainedTranslationRefusedReasons`. No public declaration, no inventory row, no
divergence. **Alternative rejected.** A `retainedEffectChanged` field (a census row and a doc comment to say what `retainedTranslated` plus the refusal table already say).

## RZ-H - The fillet-drag profile is measured first; a fix owes a measured cause, and a lane-1 site is carried

**Ruling.** Lane 2 fixes only causes its reasons table names (each its own ruling `RZ-M...` with before/after rows) or rules them by design; none is guessed. A fix whose site is in lane 1's files
(`RetainedSubtree`, `RetainedPrepaint`, `RetainedTranslation*`, `RetainedGraft`) is carried with its measurement to a follow-up after lane 1 lands, never edited concurrently.
**Candidates** are listed in the spec 2.1; the pressed slider's panel and a non-`.equatable()` container above a replayed panel are expected to be by design.

## RZ-I - A `@FocusState` reading is its slot's version; a skipped getter re-notes its focus states

**Ruling.** `@FocusState` is no longer a memo refusal: its slot is a `$state<n>` written with `table.write` (version bump) on every focus change the window reconciles, so the existing
own-`@State` condition is the "changed reading". The entry remembers the focus states its evaluation bound and a memo skip re-notes them (`noteFocusState`, as a graft's `reapply` does), so
`Window`'s pending-write and write-back passes see the same set a build gives. **Evidence.** `EE-` evidence (record §120 C14-c2) said focus writes sit "outside the `StateTable`
entry versions"; the source says otherwise for the value (`FocusState.Box.reconcile` writes the slot) and the real hazard is the missing bind, which this fixes. **Gate.** F3-F6 and verify
mode; if the bound ordinals omit the slot or the re-note cannot reproduce `lastFocusStates`, **re-carried** with the measured reason and nothing else changes.
**Cost if wrong.** A focus move that does not reach a skipped reader, or a pending write never applied: F3-F5.

## RZ-J - Divergence 346 narrows in place

**Ruling.** If `RZ-I` lands, 346's `@FocusState` clause is removed and `aFocusStateComponentStaysRefused` is replaced; the uncomparable-reading clause stays. No label taken from 625-634.

## RZ-K - What stays refused, by name, with an owner

**Ruling.** Layout-moved-and-effect-changed (`effectAndLayoutMoved`, `FS-O`), the identity-effect crossing, an effect with a clip that changes with the map, and a named space or anchor under
an affine change stay refusals, counted, none silent. Owners in the spec section 4. **Cost if wrong.** A workload that zooms and drags nodes at once keeps rebuilding: counted, visible in the table.

## RZ-L - Critic pass: no probe is owed, one dependency is made explicit, the rest stands

**Ruling.** The critic found no SwiftUI claim, public spelling, Apple type, shader or platform requirement moved by this design, so no probe arm is re-run (nothing to re-run: the facts leaned on, divergence 106 and
hitboxes following the transform, were probed in `GX-`). **Made explicit:** (1) `RZ-C` and `RZ-A` are hypotheses read from source; Z4 and verify mode are their gate, and a failing raster kind refuses by name and
amends `RZ-C` in the same lane, not later. (2) `RZ-F`'s audit of the translation arm's unmoved anchors may find an existing defect: that fix is in scope for lane 1 only as the same named refusal. (3) Lane 2's
`RZ-I` soundness gate decides before any other lane-2 edit: if it fails, lane 2 ships the (a) profile and the re-carry only. (4) A zoom hit that reaches the paint record but whose prepaint refuses is a redo, counted
under the existing reasons; Z1 asserts redos 0 so it cannot hide. **Rejected:** a new `FrameWork` affine counter (`RZ-G` stands); splitting into three lanes (the lanes own disjoint files, two is the cap).


## RZ-M - The prepaint effect vector carries the paint scope's class, so a class change refuses at prepaint (amends RZ-B)

**Ruling.** `Frame.prepaintExtras()` appends one number to each effect vector, index 18 (`PrepaintExtras.effectFlattens`): 1 when the effect's own map is a uniform positive scale plus a translation, the class the paint scope flattens
on (`GX-G`). `PrepaintExtras.change(from:)` and `ReplayKey.effectRelation(from:)` both refuse a change of that class by name, `effectFlatteningChanged`. **Why prepaint too.** The prepaint could not see the class, so an affine change that crossed it
replayed the prepaint, the paint then missed, and a grafted occurrence redid the frame (and backed prepaint replay off for eight builds); with the bit the prepaint runs instead, counted once. **Measured.** An identity rotation is a flattening
scope and a real one is not, so the first rotation step of a zoom refuses once (`aRotationStepIsReplayedExactly` settles it before it measures; Z6). **Finding, carried.** With the check dropped in both places the frame still equals a fresh one (mutation M6a,
Z5 `flattensChanged` reddened only on its refusal expectations): the re-entry of the live scopes is exact across the class, so the refusal is conservative, not required; lifting it is a candidate for the round that wants a zoom through identity rotation.
**Appended, not inserted:** indices 0...17 are unmoved (`translation(from:)` and `translatedHitboxes` read them by number).

## RZ-N - A name for every refusal: `prepaintContextChanged`, and the effect arm now runs for any effect-only difference

**Ruling.** The effect arm's gate is `PrepaintKey.differsOnlyByEffects(to:)` (rects, interior, node count and ambient equal; the effect count may differ), and `change(from:)` names what differs: `effectCountChanged`, `prepaintContextChanged` (something other than the effects
differs: a scroller, a gate, the share stack), `effectScopeChanged`, `effectFlatteningChanged`, `effectInverseChanged`, `effectClipChanged`. **`effectNotTranslation` is retired**: it named every non-translation, including a zoom that now replays and a context change that
was never an effect change. Counters are the existing `retainedTranslationRefusedReasons`; no new field (`RZ-G`). **A refusal only the paint sees** (after a replayed prepaint) is counted by the paint decision, once, never when the prepaint already counted it.

## RZ-O - Hover is read against the moved hitboxes in both effect arms (amends RZ-D)

**Ruling.** After `translatedHitboxes`, a pointer inside one of the moved hitboxes makes the occurrence run its prepaint, in the translation arm as well as the affine one. **Measured (Z8, mutation M8).** Hover resolves after prepaint and before paint, so a prepaint that replayed under a pointer
carried onto it leaves its paint (a miss: hovered) with no element prepaint state, and the frame is redone. Without the read, with no graft: 10 prepaint replays and one redo; with it: 9 replays, the carried node runs, no redo (Z8 builds without grafts for that reason). **With a graft** the
carried node has no element to prepaint whatever the read says, so the frame is redone once either way: the read is neutral there, an observation not a defect (Z8 first measured against a grafted window, where the mutant could not be told from the original, and was re-aimed). The compare against
a fresh window is green in every arm: nothing is drawn differently, only whether the frame is redone.

## RZ-P - Audit of RZ-F: anchors and context-menu records are pre-effect values in a fresh frame too; the refusal stays, as a conservative choice with its evidence

**Ruling.** `presentationAnchor` and `contextMenus` refuse an affine change as `RZ-F` ruled. **Audit.** `recordPresentationAnchor` and the context-menu record store `bounds + activeOffset`: pre-effect rects, in a fresh frame as in a replay, so replaying them unmoved is exactly what a fresh prepaint
computes. Mutations M6d and M6e (each guard dropped) reddened only the Z5 arms' refusal expectations: the frame stays equal to a fresh one (scene, tree, hitboxes, logs), and so does the translation arm's unmoved replay (Z10 with a context menu on every node, green; no defect found, none fixed). The
refusals cost coverage under a zoom for a node that declares a popover or a menu and are not needed for exactness here: a candidate to lift, with this evidence, once a probe-backed reason or a refuting arm turns up. They stay because the lane brief names them and an unproven lift is the cheaper mistake.

## RZ-Q - Pins the change supersedes are amended in place, each with its reason

**Ruling.** Four existing pins asserted the refusal this lane removes and are rewritten to the new fact (each differential half unchanged, each green): `aScaleChangeRefusesByName` (now `aScaleChangeIsAnAffineReplayNotARefusal`: `effectNotTranslation` 0, prepaint replays), the `rotation` arm of
`everyKeyComponentSeparates` (a rotation from 5 to 3 degrees replays like the offset arm: 0 reaction, 1 translated), `aGeometryNoteUnderAChangedRenderEffectMissesAndDelivers` (now `...IsRecomputedAndDelivers`: hits > 0, delivered values equal fresh), and `theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires`
(+10 occurrences of the new zoom strip: 51 and 48 hits; skipped under `METALUI_VERIFY_RETAINED=1`, where it cannot read misses, as `InvalidationDemoTests` is). **Pre-existing, not mine:** that demo test reads 0 misses under the verify switch at 1bdead8d too; the skip makes the verify run silent.

## RZ-R - Measured, and what stays carried

**Measured (release not taken: counts).** Zoom fixture, ten `.equatable()` nodes, one zoom step 1.1 / 1.21 / 1.331, retained window: **before** (1bdead8d) element requests 115 (= unretained), grafts 0, one redo and backoff 3 in the first step, `effectNotTranslation` then a paint miss
(`scopes`); **after** requests 5, grafts 10 per step (30 over three), redos 0, backoff 0; the last step's frame: element prepaints 9 of 119, paints 10 of 160, 10 translated paints, 10 prepaint hits. The raster work of the stroked path equals a fresh frame's (`rasterizedPixels`, `newTextures`:
`RZ-C` confirmed, no raster refusal). The bracket fixture has no zoom axis (its canvas pans by an offset): its pan line reads 195 requests, 220 prepaints, 258 paints, 10 grafts, 0 redos, identical to 1bdead8d. **Carried:** layout move plus effect change together (`effectAndLayoutMoved`),
lifting the conservative refusals of `RZ-M` and `RZ-P`, a named space under a zoom (`geometryNamedSpace`), a grafted occurrence whose geometry note holds a named space (it redoes one frame, `RG-J`).
