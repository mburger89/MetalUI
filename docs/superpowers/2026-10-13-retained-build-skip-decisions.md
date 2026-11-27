# Retained build skip — decisions

Rulings for item C14b-2 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), the continuation of
C14b (record §109, `SB-A`…`SB-AE`). Prefix `RK-`. **Next unused: `RK-AR`.**
Spec: [`specs/2026-10-13-retained-build-skip-design.md`](specs/2026-10-13-retained-build-skip-design.md). Record:
`../record/110-retained-build-skip.md`. Branch `perf/retained-build-skip` from `fb9a7e42`. Divergence labels reserved 405–414:
**none taken** (no public API, no SwiftUI-visible behaviour). Probe: `../probes/retained-build-skip/`.

Sources of truth. SwiftUI: nothing here is a SwiftUI-facing claim (same as `SB-`: how SwiftUI stores what it rendered is not
observable from outside), so **no SwiftUI probe was run and none is owed**; the one place SwiftUI-visible output is at stake
(pixels) is pinned by the fourteen images and the differential. gpui, where SwiftUI has none: `reuse_prepaint`/`reuse_paint` over
recorded ranges, and (recalled from memory, **the source is not on this machine**) its refusal to reuse when a view's bounds,
content mask or text style differ — a design precedent for `RK-C`, not a cited fact. gpui does not skip the *request-layout*
phase of a cached view (it caches prepaint and paint), which is the half this item adds and why `RK-A` measures it.

## RK-A — A graft is cheaper than the build it replaces, by 7x for the rows; the claim `SB-AE` called untested is now measured

**Question.** `SB-N` and `SB-AE` item 2: is copying a recorded occurrence's layout rows into the new tree cheaper than the
build recursion it replaces?

**Evidence.** `docs/probes/retained-build-skip/` (patch, command and output in its README): on the bracket fixture in release,
per outermost `.equatable()` occurrence **72.5 µs build against 9.7 µs graft (13 %)**, 27 nodes on average, 7392 occurrences
over three arms; about 1.4 ms of build against 0.19 ms of graft per drag frame, of a 6.0–6.4 ms frame. The graft there is the
rows alone (five side tables, an index shift): it omits the `StateTable` journal and the id remapping of the build-only
channels, which lane 2 adds to the measurement (`RK-J`).

**Ruling.** The graft is the build skip's mechanism (`SB-N` stands; `IV-H`'s persistent tree stays refused). The budget the
whole item can win, from the measured shares: build of the occurrences about 1.4 ms, prepaint about 0.8 ms (`SB-AE`/record
§10), minus the graft (0.2), the journal and the prepaint replay (unmeasured, assumed below 0.3 together): **about 1.7 ms of 6.0,
-28 %** is the ceiling, and a reading below -15 % after lane 2 is recorded as a miss, not rounded up.

**Cost if wrong.** The journal or the replay could eat the margin; `RK-J`'s stop condition catches it at lane 2's first step.

## RK-B — A grafted occurrence has no element tree: prepaint **and** paint are replayed, and `ComponentLayout`'s payload may be absent

**Question.** `SB-AE` said the four parts land together. Why, exactly, and what does the graft leave behind?

**Evidence.** `ComponentLayout<C>` holds the materialized content *with its element layout* (`ComponentLayoutStorage.withPayload`,
`PE-J`), and that payload holds `LayoutNodeID`s of the build's tree generation (`C-3`: a stale id traps in `slot(_:)`). A build
that is skipped produces no payload for this frame, and the old one cannot be reused: its ids belong to a dead generation and
the payload is a generic type no code outside the element types can rebase. So prepaint and paint, which walk the payload,
**cannot run** for a grafted occurrence; both must replay (paint already does, `SB-AA`; prepaint is `RK-E`).

**Ruling.** (1) `ComponentLayout.storage` gains an optional payload; a grafted occurrence carries `payload == nil` and a
`RetainedGraft` marker (its record, its segment, the key); `EquatableComponent.prepaintGroup`/`paintGroup` branch on the marker
before touching the payload and a `nil` payload with no marker traps by name (the way `PE-J`'s copy traps). (2) The landing order
is therefore **M1 prepaint replay and redo with the build still running; M2 the graft on top of M1** (spec §2): M1 is
independently landable and measured (it removes the 0.8 ms of prepaint), M2 is impossible without it. This corrects the reading
of `SB-AE` that all four were one indivisible change: *two* of them are (graft and journal need prepaint replay and redo), the
other two (prepaint replay, redo) stand alone.

**Cost if wrong.** If a consumer of the payload outside prepaint/paint exists (the lifecycle drain, accessibility, `frame(ofID:)`),
a grafted occurrence is a trap there; lane 2's first test greps every `withPayload` caller and names each (`aGraftedLayoutTrapsByNameWhenAnElementPhaseReadsIt`).

## RK-C — The paint-only ambient problem is solved by an optimistic decision and an exact check at paint, with a counted redo (`SB-AA`'s recorded alternative, adopted)

**Question.** `SB-AA`: opacity and the shadow, blur and composite scopes are pushed by ancestors' `paint`, after every prepaint, so
a prepaint decision cannot see them. Decide earlier, or prove the ambient equal?

**Evidence.** Proving it equal means knowing, at build or prepaint, the value of every ancestor's opacity and scope: they are
element values of ancestors, never carried down the build (`LayoutPass` holds the parent id and cursor, not the ancestors'
paint effects); a mirror stack at every pushing site was rejected by `SB-AA` for the omission risk and is still. The check at
paint is **exact** and already built: `AmbientKey` is computed at paint today for lane 1's decision. So the decision splits in
two: **at build** (graft or not) and **at prepaint** (replay prepaint or not) each from everything visible there, **assuming the
paint-only ambient is what the record saw**, and **at paint** the real ambient is compared; a mismatch for a grafted or
prepaint-replayed occurrence cannot be repaired in place (no elements), so it **redoes the frame** (`RK-D`).

**Ruling.** Optimistic-then-exact. Visible at build: the content memo hit, bound `@State` versions, observation, environment
fingerprint, transaction, the pointer/press/focus rule (`SB-X`), accessibility collection, window and entry backoff. Visible at
prepaint: absolute rects (and, translated, `RK-G`), the clip and prepaint transform effects, scroll offset, layer, scale, content
size. Visible only at paint: the opacity stack and the open paint scopes — the mismatch cases (an ancestor's `.opacity`,
`.shadow`, `.blur`, `.compositingGroup()` changing while the subtree is unchanged). A paint-time mismatch of an ordinary
retained (not grafted, prepaint run) occurrence is unchanged from lane 1: it records and paints.

**Cost if wrong.** An ancestor effect that animates every frame costs a redo then backoff then a redo again (`RK-D`): the entry
quarantine bounds it at one redo per 256 frames after four repeats, and verify mode (`RK-H`) is the instrument for a wrong
*equal* (the dangerous direction, a stale picture).

## RK-D — The redo: window-level, before adoption, with its inputs restored, backed off per window (8 frames) and per entry (doubling)

**Question.** What is a redo, where does it run, what must it undo, and what stops it recurring?

**Evidence.** `Frame.render` ends with `stateTable.sweep()`; the window adopts the frame (`buildAndAdoptFrame`) and drains the
lifecycle only afterwards, and the existing settle build already runs a second full build after a drained write, so a second
`Frame` over the same `StateTable` is an established path. The window inputs a build **consumes** (as opposed to reads): the
parked root transaction (`Animation.takeParkedRootTransaction()`, taken, not read), the scroll request queue handed to the frame,
and the focus read-back's decision; everything else in `buildAndAdoptFrame`'s setup is a read of window fields.

**Ruling.** (1) A paint-time mismatch of a grafted or prepaint-replayed occurrence sets `frame.redoRequest` (the entry keys);
`Window` runs the build again **before adoption**, with those entries disabled (`retained: .disabled`), the same transaction
value passed to the second `Frame` and `scrollRequests` snapshotted and restored (a redo that dropped a queued `scrollTo` is a
lost scroll: `aRedoFrameEqualsARetentionOffFrameAndConsumesEachInputOnce`), and the abandoned frame's scene, hitboxes, AX, focus registrations and
presentation records are simply dropped with the `Frame` — **nothing from it is adopted** (pinned by one differential: a redo
frame equals a retention-off frame). (2) At most one redo per render; the redo's own mismatch is impossible (its entries are
disabled, nothing else was replayed against a changed ambient — a second request traps in debug, runs plain in release).
(3) **Backoff** (`SB-R`): a redo suspends graft and prepaint replay window-wide for 8 frames; additionally each entry that
caused one is quarantined 8, 16, … 256 frames (the exponent resets after a hit that equalled its ambient), so a persistently
animated ancestor costs at most one redo per 256 frames. Paint-only replay (lane 1's) is never suspended: it has no redo.
(4) `FrameWork.retainedRedos` counts, `retainedBackoffFrames` counts the frames spent suspended.

**Cost if wrong.** A resize drag pays one frame at twice the cost then eight plain frames (lane 1's cost): the pin
`aRepeatedPaintOnlyChangeRedoesAtMostOncePerEightFrames` bounds it. A lifecycle or animation input consumed by the abandoned frame would be a
silent loss; the restore list above is exactly the consumed set, and lane 1's `aRedoFrameEqualsARetentionOffFrame` runs a script with
a pending `withAnimation`, a pending `scrollTo`, a focus write and a lifecycle appear across a redo.

## RK-E — Prepaint replay: what is recorded, where it is decided, and what is ineligible

**Ruling.** The prepaint ledger is `SB-E`'s **recorded** class for prepaint, replayed in recorded order: the occurrence's slice of
`hitboxes` (the *same* entries, in the same order, so `topmostHitbox(in:at:where:)` ranks identically: no second lookup, no
sort), the focus registrations in `FocusRegistry.tabOrder` order, `axEmissions`, `axNodes` and `accessibilityPressOnly`, the region
tallies (`hoverRegionCount`, `pointerStyleRegionCount`, `keyRegionCount`, `focusOnPressCount`, `resignRegionCount`), the
`contextMenuRecords`, and the prepaint states paint reads (they are the record's, since paint is replayed too). The decision is
taken at prepaint (`RK-C`): hit when the absolute rects and prepaint ambient equal the record's (translated: `RK-G`), the hovered,
pressed or focused element is not under it (`SB-X`), `collectsAccessibility` equals the recording, no observed read of the three
windows changed, no bound `@State` moved. Ineligible for prepaint replay (counted `retainedPrepaintIneligible`, by name in the
trace): a scroll region, popover, tooltip, drag source/destination, presentation or toolbar record, geometry-change note, surface
request or a `Deferred` portal in its prepaint (`SB-J`'s set, unchanged, each with a separating arm); a text field's focus
registration is *not* ineligible (focus is recorded) but a focused one is (`SB-X`).
**Handlers are replayed as closures** the recording frame made; a handler that captured a `LayoutNodeID` would hold a dead
generation, so the recorder **refuses** (counted ineligible by name) a prepaint that stored one — found by the guard
`noHandlerHoldsALayoutNodeID`, a `Mirror` scan of every recorded hitbox in the demo and bracket trees plus a per-site test list
in spec §5 (the dangerous omission; verify mode finds the rest).

**Cost if wrong.** A channel missed here is a hitbox, focus stop or AX node absent on a hit frame; the differential compares the
whole hitbox list, tab order, AX emissions and tallies against a retention-off frame at every drag step, and verify mode compares the
prepaint ledger as it already compares paint's (`SB-W`).

## RK-F — The `StateTable` journal records the build window's deltas and re-applies them through the table's own funnels

**Ruling.** `RetainedBuildWindow` (lane 1's, which journals `marks`) is extended to the **build-window delta** of every
sweep-visible channel: `marked`, `producedSlots`, `namedPositions` (`noteNamed`), `loopExtents`, `windowedParents`,
`departedNames`, the memo entries touched below (`ContentMemoStore.touched`, so a nested occurrence is not swept away: its entry
and record are carried), the lifecycle and animation touches, and the versions of the `@State` slots bound under the occurrence
(already kept, `SB-K`). Replay goes through `StateTable`'s own mutators (`reapply(journal:)` calls the same functions the build
does), never writes the sets directly, so `sweep()` is unchanged and an `ID-C`/`ID-R` reset still fires for content an *evaluated*
conditional elsewhere removes. **Build-only channels** with node ids (`lowering` records of the occurrence's top-level nodes,
`hiddenNodes`, `elementBounds`, `scrollKeys`) are journalled for the top-level nodes only and re-keyed by the graft's index map;
an occurrence whose build wrote `hiddenNodes` below its top level, `elementBounds` (a recording frame: `recordsElementBounds`) or
`scrollKeys` is **graft-ineligible** (counted `graftIneligible`, named in the trace), and the bracket's occurrences decide what
is supported first: nothing else is built until a reading needs it.
`everyFrameChannelIsClassified` (lane 1's `Mirror` guard) gains the new rows; a stored property added to the three types owes one.

**Cost if wrong.** A missed delta is a state entry reaped under a live subtree (its `@State` resets on the next frame): the
differential `aGraftedFrameKeepsTheStateTableSweepsExact` compares the table's key set and slot versions against a retention-off
build after every step of a script that includes a conditional removal elsewhere, a `ForEach` reorder and a lifecycle scope.

## RK-G — Translated replay: a subtree moved by whole device pixels at a power-of-two scale replays; anything else misses

**Question.** `SB-H`: replaying at a delta computes `(p + o₁)·s + d·s`, not `(p + (o₁ + d))·s`; exact at dyadic scales (0 of 100 000
differ at scale 2), inexact at 3 (31 of 2999 in device space). Is there a gate that makes it exact, and what must it also hold?

**Evidence.** `SB-H`'s emulation, extended here by argument and a pin, not a new probe: at a power-of-two scale `s` and with
every coordinate, offset and delta a multiple of 2⁻⁶ pt below 2¹⁵ pt, every binary32 sum in the chain is exactly representable
(21 significant bits), so addition is associative on these operands and the scale multiplication is exact; the result is
bit-identical to the fresh arithmetic by construction. Text adds a second dependence, `GlyphImage.subpixelPlacement(forDeviceX:)`
(`PT-C`): the glyph's subpixel bin comes from the **fractional device x**, so a translation changes glyph rasters unless it is a
whole number of device pixels. Rasters are keyed relative to a floored anchor (`PF-A`), so an integral shift hands back the same
`ImageTexture`. A clip cuts a recorded run at its absolute rect: translating a run that was clipped, or into a clip it was not
inside, changes the cut.

**Ruling.** Translated replay (paint **and** prepaint, M3) is taken when: the scale factor is a power of two; the delta of the
occurrence's origin in device pixels is integral (both axes); all recorded and current coordinates are multiples of 2⁻⁶ below
2¹⁵ (checked once per record, stored); the recorded subtree bounds lie inside the recorded clip and the translated bounds inside
the current one (no run was cut); every other key part (relative rects, ambient but the offset) is equal. Otherwise it misses as
today, counted `retainedTranslationRefused`. The translation applies to the scene's `x/y` fields and the hitbox and AX rects by
one addition each in device or point space as the field's own space says. **The byte-identity check is a pin, not a belief:**
`aTranslatedReplayEqualsAFreshFrameAtEveryScale` renders a pan script at scales 1, 2, 4 (taken) and 1.5, 3 (refused: the
refusal count is asserted and the frame still equals a fresh one), comparing scenes bit for bit.

**Cost if wrong.** A gate too wide shows as a differing primitive in verify mode at scale 3; too narrow, a pan at 1.5x pays
paint. The MetalCreator pan case is scale 2 with integral-pixel steps only when the user's pan lands on whole points — a
trackpad pan is fractional: the refusal is the common case there, which the spec's demo measures and `RK-L` names as the
reason translated replay may land with a **small** win.

## RK-H — Verify mode covers the build skip and the prepaint replay

**Ruling.** `METALUI_VERIFY_RETAINED=1` additionally: for a **prepaint replay** it runs the prepaint as a miss and compares the
recorded ledger (hitboxes, focus stops, AX, tallies) with the replay; for a **graft** it also builds the occurrence in full into a
scratch `LayoutTree` and compares the node rows, signatures and leaf keys with the grafted ones, and compares the `StateTable`
sets the build would have produced with the journal's, then paints as a miss and compares as `SB-W`. A difference traps with the
channel named (an exit test per channel). `METALUI_VERIFY_LAYOUT_MEMO=1` is unchanged. Both run over the whole suite at the end
of each lane and the readings are in the record; the suite's seam-count pins that a verified frame changes by design are guarded
with `layoutMemoVerifying`-style flags as `SB-AD` did.

**Cost if wrong.** Verify mode doubles a verified frame's work and is off by default: nothing in production.

## RK-I — GT-F: the criterion is fixed before the re-take; `drawText` stays deferred unless a moving label still costs `placeGlyphs`

**Question.** `SB-P`: after translated replay, are `MetalDrawContext.drawText` and its SDL twin still deferred?

**Ruling.** Re-take `aStaticLabelOverlayReplaysAndAMovingOneDoesNot` and `theOverlayCostIsLinearAndCounted` after M3. **Fixed now:**
`drawText` stays deferred if a label moved by a whole device pixel at scale 2 reads 0 `placeGlyphs` and 0 seam measures on the
replay frame (GT-A's per-label cost is gone for the moving case) or if the moving label is not under an `.equatable()` (nothing to
change); it is **built** (new API, own lane, its own decision) only if a moving label under translated replay still reads at
least one `placeGlyphs` per label per frame. A fractional move is a refusal (`RK-G`) and does not count against the deferral: it
is the documented cost.

**Cost if wrong.** The criterion could keep `drawText` deferred while a real overlay is slow at fractional pans; that is an
overlay-cost item (owner C14 close-out), not this one.

## RK-J — The slice, the lanes and the stop conditions

**Ruling.** Three milestones in two lanes, each with a gate that is a **measurement**, and anything past a failed gate carried:
- **Lane 1 (M1 + M3, `Frame`, `RetainedSubtree`, `Window`, `ComponentPrepaint`):** the redo and prepaint replay with the build still
  running (M1), then translated replay (M3). Gate for M1: after it, `elementPrepaints` on the bracket drag falls by the hits'
  share and the release `.panels` median improves at least 0.4 ms (half the prepaint share) — else rule the cost of the ledger
  copies and stop M1 as a counted-only change.
- **Lane 2 (M2, `MetalUILayout/LayoutTree.swift`, `StateTable.swift`, `ContentMemo.swift`, then `EquatableComponent.swift`):** the graft and
  the journal. **Step 1 is the measurement with the journal included** (the probe re-taken); **stop if graft plus journal exceed 50 %
  of the build they replace**: record it, carry M2 with the number, land M1/M3 alone. Lane 2's `EquatableComponent` integration waits for lane 1's merge (the
  agents run one at a time; the files are otherwise disjoint).
- Carried regardless: read-only `withState` and popovers/surfaces inside a subtree (C14b-3), custom environment keys (C14-c),
  finer scopes (C14-d), a placement memo with translation (`SB-AD` item 3, now subsumed by M3 for paint and prepaint but not for
  layout: layout of a moved subtree is still placed fresh), `drawText` (`RK-I`).

**Cost if wrong.** The two-lane sequence could stop at M1; the item is then M1 plus M3 with the carried table honest.

## RK-K — Counters and pins: work, never time

**Ruling.** `FrameWork` gains `retainedPrepaintHits`, `retainedPrepaintIneligible`, `retainedGrafts`, `retainedGraftIneligible`,
`retainedRedos`, `retainedBackoffFrames`, `retainedTranslated`, `retainedTranslationRefused` and the graft's `graftedNodes`
(`package`-readable like the rest; the public ones owe a doc comment and a census/inventory row, `FrameWork`'s existing counters being
the precedent, `SB-Z`). Each drag-frame pin is a literal **red on arrival** against `fb9a7e42`'s reading, taken by the baseline test
in lane 1's step 0 (the record keeps the table). `retained* == hits + misses + ineligible` identity of `SB-Z` is extended: a graft is
a hit whose build and prepaint are also counted skipped (`elementRequests + retainedSkippedRequests` equals the retention-off frame's).

## RK-L — What is expected, stated before the build so a reading can refute it

**Ruling.** On the bracket node drag (release, shared Mac, `perf-baselines.sh`): M1 -0.4 to -0.8 ms per frame; M2 -1.0 to -1.4 ms
more; M3 no change on the node drag (it moves no layout) and a measured win only on a pan script (`aPanOfTheWholeGraphReplays…`),
whole-point steps; ceiling -28 % (`RK-A`), refutation at -15 %. For MetalCreator's pan-50, zoom-50 and orbit-with-panel
(17.05, 18.64, 20.56 ms against 16.67 ms), zoom is **not** a translation and is not helped by M3, and orbit's panels only if
their values are equal: **this item will not by itself bring them under 16.67 ms**; the record states the per-frame saving in ms
and leaves the verdict to a MetalCreator reading.

**Cost if wrong.** A reader expects the item to fix the frame budget; this ruling says it may not.

## RK-M — The redo runs before `sweep()`, rolls back its checkpointed channels, and disables **all** graft and prepaint replay (corrects `RK-D` item 2)

**Question.** Critic review of `RK-D`: is "the redo's own mismatch is impossible" true, and is a second `Frame` over the same tables safe?

**Evidence.** (a) `RK-D` disables only the entries that requested the redo. An outer occurrence that is replayed hides its nested
occurrences from the paint check; once the outer is disabled the nested ones are decided afresh and can themselves be grafted and
mismatch, so a second request is reachable, not impossible. (b) `Frame.render` ends in `sweep()` and the build also advances
window-owned stores (`AnimationStore` frame clock and ghosts, `LifecycleStore` presence, `ContentMemoStore` touched marks and its
`endFrame` sweep, `departedNames`, `RasterCache` generation). The settle build the spec cites as precedent runs *after adoption* of a
complete frame, not after an abandoned one, so "an established path" does not cover a frame whose sweep already ran.

**Ruling.** (1) A redo is decided **before** `sweep()` (paint is the last phase that can request it) and the redo rebuilds with
**every** graft and prepaint replay off window-wide for that render (paint-only replay stays: it has no redo); a second request
traps in debug and is ignored in release, now truly impossible. (2) Before the first build the window takes a **checkpoint** of the
channels a build mutates before adoption (`StateTable`'s build-window sets via `markJournal`'s range, `ContentMemoStore.touched`, the
`AnimationStore` and `LifecycleStore` per-build state, `RasterCache` generation) and the redo restores it; which channels is
listed by `everyFrameChannelIsClassified` (one more column: *checkpointed*). (3) New pin `aRedoLeavesEveryTableAsAFreshBuildWould`
(key sets, slot versions, animation records, lifecycle presence, memo entries compared with a retention-off frame after the redo);
mutation: one channel left out of the checkpoint, one run per channel. Spec §5 test 5 gains it; test 6's quarantine is unchanged.

**Cost if wrong.** A redo that leaked a channel is a state reset or a lost animation on the one frame after a paint-only ancestor changes.

## RK-N — Verify mode for the graft is a **second full build and a whole-frame compare**, not a scratch-tree build (replaces `RK-H`'s mechanism)

**Evidence.** `RK-H` built the occurrence "into a scratch `LayoutTree`" and compared `StateTable` sets "the build would have produced",
but a build's registrars, `noteNamed`, memo touches and lifecycle records write the shared tables, so a scratch tree alone cannot be
isolated and the comparison is undefined without a snapshot — the same checkpoint `RK-M` defines.

**Ruling.** With `METALUI_VERIFY_RETAINED=1`, a frame that grafted or replayed prepaint is **built again with replay off** through the
`RK-M` redo path (checkpoint, restore) and the two frames' node rows, signatures, leaf keys, hitbox lists, tab order, AX emissions,
tallies, scene and table key sets are compared; a difference traps naming the channel. The exit tests of `RK-H` stand (one per
channel). Verify mode costs two builds a frame and is off by default.

## RK-O — Replayed handlers: a `Mirror` cannot see a closure's captures, so `noHandlerHoldsALayoutNodeID` is replaced; a captured `@State` box must be the table's

**Evidence.** Spec §5 test 9 (`noHandlerHoldsALayoutNodeID`, "a Mirror scan of recorded hitboxes") cannot be red for the case that
matters: `Mirror` reads stored properties, not a closure's captured values, so a handler that closed over a dead-generation
`LayoutNodeID` is invisible to it (a `Hitbox` field of that type is visible, the capture is not). Separately, `@State` is "a box seeded
by reflection per element per frame": a never-written default is re-seeded each build, so a handler recorded in frame N may hold a box
the table no longer owns, and a write through the replayed closure would go nowhere.

**Ruling.** (1) Test 9 becomes two: `noRecordedHitboxStoresALayoutNodeID` (Mirror over the stored fields of the recorded structs only;
mutation: add such a field to a fixture type) and **`aReplayedHandlerActsLikeAFreshOne`** (after a replay, invoke every recorded hitbox's
click, key, drag and hover handler and compare the resulting state, focus and scene with the retention-off frame's; mutation: a
fixture handler capturing a stale id or a re-seeded box must redden it). Capture is otherwise settled by verify mode (`RK-N`).
(2) An occurrence with a bound `@State` slot whose box is **not the table's entry** (never written, re-seeded) is **ineligible for
prepaint replay and graft** (counted `retainedPrepaintIneligible`, named); `RK-E`'s "no bound `@State` moved" becomes "every bound slot
is a table entry and none moved".

## RK-P — `RK-A`'s per-frame figures are derived inconsistently; they are re-taken directly, and the 13 % ratio stands only as a ratio

**Evidence.** The probe README derives "about 29 occurrences hit per drag frame" and then 1.4 ms of build; 29 x 72.5 us is 2.1 ms, and
1.4 ms implies 19. The probe's frame counter read 1 (a stated defect), so occurrences per frame were never measured, and outermost
versus nested counts are not separated.

**Ruling.** The **13 % ratio** (72.5 against 9.7 us per outermost occurrence) is the evidence for building M2; the **1.4 ms and 0.19 ms per
frame, the 1.7 ms ceiling and the -28 % are unverified** and `RK-A`'s budget is withdrawn as a number. Lane 2 step 1 measures
graft-plus-journal against build **per frame on the drag frames** (occurrences counted, outermost only), and `RK-J`'s 50 % stop and
`RK-L`'s -15 % refutation are judged on that reading. No SwiftUI claim is involved, so no SwiftUI probe is owed (confirming the header).

## RK-Q-note — Rejected after review (no change)

Rejected as defects: "no SwiftUI probe" (no SwiftUI-facing claim; gpui recall is labelled as memory); "lane 2 waits on lane 1" (serial agents,
files named); "test 3 passes on the stub" (declared an instrument, mutation named); the demo switch reaching a `package` hook
(`MetalUIDemoContent` is in the package). Translated replay's mutation arms (test 11) owe a `try #require` that the scale-3 arm
actually differs under the mutated gate (`SB-H`: 31 of 2999), added to the spec.


## RK-R — Lane 1 as built: the prepaint ledger, the prepaint key and the decision (what `RK-E` named, and what it did not)

**Evidence.** Lane 1 (`Sources/MetalUI/RetainedPrepaint.swift`, hooks in `Frame.swift`, `StateTable.withState`/`write`, `GeometryChange`,
`ModifierKeysChange`; tests `RetainedPrepaintTests`, `RetainedVerifyTests`, `TranslatedReplayTests`). One `PrepaintLog` is shared by every open
recorder (`Frame.prepaintLog`, `nil` unless one is open, one nil check at each funnel) and each recorder keeps the slice between its open and close:
the `hitboxes` and `axEmissions` ranges (copied at close, so a share patch inside is in), the journals of `focusRegistry.register`/
`registerShortcut`/`registerFocusBinding` calls (only calls that registered something are journalled), `axNodes` writes with their `$ax`
slot write, `accessibilityPressOnly`, `contextMenuRecords` and `elementBounds` (the harness records layout by default, so this one is not
optional), and the five region tallies as deltas. **Everything else a prepaint can write is audited, not recorded**: a count of
`timeVaryingNotes`, `openPopovers`, `presentationAnchors`, `presentationSpaces`, the scroll resolution and adjustment queues, the unresolved-request
count, `wantsAccessibilityRetry`, `portalCount`, `namedSpaceSnapshots`, `hitboxNamedSpaces` and `surfaceRequests` taken at open and close, a
`withState`/`write` that is not the accessibility node's own retention slot (`StateTable.prepaintLog`), `noteGeometry` and `noteModifierKeys` (explicit
taints) and a share patch that rewrites a hitbox or record registered before the window opened. A moved count makes the occurrence ineligible by name
(`retainedPrepaintIneligible`, `METALUI_TRACE_RETAINED=1`). A ledger with a draggable or a drop destination is refused too (`RK-E`'s list).
**The prepaint key** is the paint key's ambient read at prepaint (clip, offset, layer, scale, size, environment fingerprint, transaction; the opacity
and scope stacks are empty there) plus `PrepaintExtras`: the open render effects (composed map, inverse, outer clip, clip base), the pointer and
keyboard gates, the share stack, whether accessibility is collected and the suppression exceptions, the portal ordinal, the innermost scroller frame
and the hidden-node count. A context the key does not hold refuses the decision: a pending `scrollTo`, an open share collection, an open named space.
**The decision** (`retainedPrepaintDecision`): replay-able when the record's content serial, observation, coverage and bound `@State` versions are
what the paint decision requires and the key is equal; the pressed or focused element under the occurrence runs prepaint (exact); **the pointer rule**
cannot be exact (hover resolves after prepaint), so the occurrence runs prepaint when the pointer is inside **any hitbox its own ledger registered**,
a superset of the paint rule's "the hovered element is under me", which is what makes a hover entering an occurrence cost no redo
(`aFocusedOrHoveredElementUnderTheOccurrenceRunsPrepaint`).

**Ruling.** As built. `ComponentPrepaint.Storage.prepaint` is optional, `nil` only for a replayed prepaint; `withPrepaint` traps by name on it (`RK-B`),
so no element phase can walk a replayed occurrence. A window drives a redo only if it said so (`ContentMemoStore.windowRedoes`): a bare
`Frame.render` never replays a prepaint, since nobody would build its abandoned frame again.

**Cost if wrong.** A channel missed is caught by the differential (`RPSnapshot`: scene bytes, accessibility tree, every non-closure hitbox field in
order, tallies, Tab order, element bounds, menus and press-only registrations at every drag step) and by verify mode (`RK-V`).

## RK-S — Translated replay is the paint replay through the live scopes plus moved hitbox transforms; `RK-G`'s scale and device-pixel gates are not owed (narrows `RK-G`)

**Question.** `RK-G` gated a translated replay on a power-of-two scale and a whole-device-pixel delta because `SB-H` measured the float association of
`(p + o₁)·s + d·s` against `(p + (o₁ + d))·s` (0 of 100 000 differ at scale 2, 31 of 2999 at scale 3) for a translation applied to **recorded final
primitives**. Is that the translation this design makes?

**Evidence.** No. A record keeps two streams (`SB-AB`): the leaves at the boundary where the occurrence's own paint scopes end (`scene`) and the
primitives as they reached the scene after plain outer effects (`finalScene`). The occurrence's pre-scope leaves are in the space the outer render
effect maps **from**, and they do not depend on that effect's translation: glyph bins come from the text system's local device x, clips pushed inside an
effect are local (`flatteningClipBase`), and every outer scope (the effect's map, its cut by the clip at entry, the `.opacity`) is applied afterwards. So a record
whose key differs only in the translation of outer **effect** scopes replays its `scene` through `processScopes` **against the live scopes**: the
arithmetic is the fresh arithmetic, operation for operation. The final stream (the old translation in its coordinates) is not used for such a hit
(`replayPaint(_:translated:)`). The pins are bit-for-bit differentials against a retention-off window at scales 1, 1.5, 2, 3 and 4 over a pan of whole
points, a half, a quarter and a third of a point (`aTranslatedReplayEqualsAFreshFrameAtEveryScale`, 10 arms) and over the bracket graph's pan by 4, 0.3 and
2.5 points (`aPanOfTheWholeGraphReplaysEveryNodeAndEqualsAFreshFrame`): all equal, **at the scales `RK-G` refused**.

**Ruling.** (1) Paint: `ReplayKey.differsOnlyByEffectTranslation(from:)`: rects, interior and every ambient part equal, scope vectors equal except the
`tx`, `ty` of `.effect` scopes (linear parts, depth, flattening, outer mask equal); the hit counts `FrameWork.retainedTranslated`. (2) Prepaint: the
effects' composed translations moved by one amount (or not at all: a node moved inside a still canvas), linear parts, inverses' linear parts, outer clips and
clip bases equal; the ledger replays with each hitbox's `HitboxTransform.inverse` moved by the opposite amount, **exactly in `Double`, checked by round trip**
(`translatedHitboxes`); a hitbox outside every effect, or one whose outer clip is not the ambient last effect's (its clip depended on the translation), or
an accessibility record in the ledger (its frames are computed boxes, `accessibilityGeometry`) refuses and counts `retainedTranslationRefused`. Local
`bounds`, `origin` and `shape` of a hitbox, a context-menu record's bounds and element bounds are layout- or effect-local and do not move. (3) Not built, carried:
a translation that comes from **layout** (rects) or the **scroll offset** (`activeOffset`) instead of an effect, which re-bins glyphs and moves element bounds
(`RK-G` stands for that case: whole device pixels and a dyadic scale would be owed); `RK-L` expected a fractional trackpad pan to be the common refusal, and it
replays instead. (4) A translated hit in verify mode paints fresh and compares the pre-scope leaves, not the final stream.

**Cost if wrong.** A leaf that depended on the outer translation would replay stale under a pan: the pan differentials and verify mode are the instruments; a
scope kind other than an effect (a shadow, a blur, a composite) must be fully equal, so a moving shadow still misses.

## RK-T — A never-written `@State` slot does not stop a prepaint replay (refutes `RK-O` item 2; `RK-O` item 1 stands)

**Question.** `RK-O` item 2 refused prepaint replay for an occurrence with a bound `@State` slot whose box "is not the table's entry" (never written, re-seeded),
reasoning that a replayed closure's write "would go nowhere".

**Evidence.** `State.Box` holds the table and the slot id, and `wrappedValue` reads `table.peek(slot) ?? initialValue` and writes `table.write(slot, value)`:
a closure from a past frame reaches the table's entry whatever box it holds. Measured: `aReplayedHandlerActsLikeAFreshOne` clicks a never-written `@State` button
against **replayed** hitboxes (the click dispatches against the previous frame's list, with the pointer elsewhere) and the retaining window equals the
retention-off window in state, log, scene, accessibility tree and hitbox list, before and after the first write. The refusal also cost the `.panels` arm's top
bar and inspector their replay (every `@State` there is never written): with it, release `.panels` gained 0.32 ms from M1; without it 0.47 ms (record 110 §4).

**Ruling.** The version check the paint decision already makes (`versions` of the slots bound under the component) is the whole `@State` rule; nothing refuses
a slot for never having been written. `RK-O` item 1 (`noRecordedHitboxStoresALayoutNodeID`, and the handler differential in place of a `Mirror` scan of captures)
stands.

## RK-U — The redo as built: what is rolled back, what is idempotent, and what never coincides with it (corrects `RK-D` items 1–2 and `RK-M`)

**Evidence.** The abandoned frame ends after the root's paint, before the sweep and every `endFrame`; the window builds the frame again. Per channel,
read from the source and, where it mattered, from a red run: `StateTable`'s build sets (`marked`, `producedSlots`, `namedPositions`, `loopExtents`,
`windowedParents`, `departedNames`) are set unions or assignments of the same values and need no rollback; the content memo's entries re-skip (`serial`,
`pristine`) and its counters restart (`resetBuildCounters`); `LifecycleStore` is **not** idempotent: the occurrence index of a scope counted twice read as a
new key and ran `onAppear` a second time (observed: `["appear", "appear"]` against `["appear"]`, `aRedoFrameEqualsARetentionOffFrameAndConsumesEachInputOnce`),
so its in-flight accumulators (`current`, occurrences, orders, geometry and modifier notes) are empty at the start of a build and are cleared
(`rollbackBuild`); `TimelineStore.occurrences` and `SurfaceRegistry`'s occurrence counts likewise; `TransitionStore` is not idempotent (`claim` answers `false`
for a key already recorded, and `afterLayout` consumes insertions), so its per-build notes and records are cleared and its insertions, ghosts and capture
counter restored from a checkpoint; `AnimationStore.entries` is restored from the checkpoint and `touched` cleared. The checkpoint is a few reference copies
taken **only** when a build can replay a prepaint (a ledger exists, replay allowed): `ContentMemoStore.ledgerEntries`. The scroll queue is restored
(`ScrollRequestQueue.restore`), `textSystem.endFrame()` is called when the frame is abandoned (`ShapingCache.beginFrame` traps on a second begin without an
end) and the glyph atlas bracket closes.

**Ruling.** (1) A frame whose **root transaction animates** refuses every replay (`SB-J`'s refusal reads the root transaction at the occurrence), so a redo never
coincides with a parked `withAnimation`: the transaction is passed to the redo unchanged but `RK-D`'s "pending `withAnimation`" arm is not reachable, and
`aRedoFrameEqualsARetentionOffFrameAndConsumesEachInputOnce` runs an implicit animation in flight instead, the animation store's entries being what a redo
must restore. (2) A pending `scrollTo` refuses prepaint replay by name (`prepaintRefusal`); the restore matters for requests a frame **carries** (`VL-H`), which
the abandoned attempt would otherwise duplicate; it is not pinned by a window test because nothing here can make a frame both carry one and replay (carried).
(3) Backoff and quarantine as `RK-D` item 3, pinned: gaps between redos of at least 9, 17 and 33 builds under an ancestor that changes every frame
(`aPersistentlyAnimatedAncestorIsQuarantined`), the exponent resetting at a prepaint-replayed hit whose paint also hit.

**Cost if wrong.** A leaked channel is a state reset or a doubled lifecycle event on the one frame after a paint-only ancestor changes; the differential
runs a lifecycle appear, a focus request and a running animation across a redo.

## RK-V — Verify mode as built (`RK-N`): the abandoned first attempt is compared, the second is presented, the counters are the first's

**Ruling.** `METALUI_VERIFY_RETAINED=1`: a frame that replayed a prepaint captures a `RetainedVerifySnapshot` after the root's paint (the scene's arrays
element by element in bytes, every hitbox's fingerprint, the Tab order, the accessibility records, the nodes' ids, the tallies, the context-menu, press-only and
element-bounds registrations), is abandoned there like a redo, and is built again from the same checkpoint with every replay off; a difference traps naming the
channel and the first differing element (`aVerifiedPrepaintReplayThatDiffersTraps`, one exit test per ledger channel, damaged through
`Window.testingCorruptPrepaintLedgers`, and a control that draws normally). The presented frame is the second; the counters it reports are the first's
(`ContentMemoStore.reportLast`, and the element counters, `Frame.adoptElementWork`), so the suite's count pins read the build under test. **Found by running it**: (1) the
snapshot's first comparison of the accessibility nodes sorted their ids by description and called two orderings of the same set a difference (it compares sets now); (2) a tree that
displays its own build counters (the invalidation demo's readout) differs between two builds by design, so that one pin is switched off under the variable; (3) the layout counts of the
presented frame are the rebuild's (its placement memo already holds the first build's entries), so `aDragFrameRestoresTheUnmovedOccurrencesPlacement` is switched off under the variable —
with `METALUI_VERIFY_LAYOUT_MEMO=1` alone, and with prepaint replay off, it passes. The final run over the whole suite reads in record 110 §6.


## RK-W — The lane 1 readings and what they settle (`RK-J` gate, `RK-L` expectation, `RK-I` criterion)

**Evidence.** Record 110 §4: prepaint replay off and on alternating inside one process (`bracketab`, release, shared Mac), three whole-process runs, median drag frame
in thread-CPU milliseconds, off to on: `.value` 7.805 to 6.925, 7.040 to 6.678, 7.137 to 6.632 (−0.88, −0.36, −0.51); `.panels` 7.340 to 6.837, 6.988 to 6.555, 7.396 to 6.938 (−0.50,
−0.43, −0.46). The wall-clock medians agree to the microsecond when the Mac is quiet (run 2: −0.33 and −0.42) and are damaged by contention when it is not (run 1: 13.99 against
7.81 CPU, the `.value` off arm). Element prepaints of the tenth drag frame: 886 to 219 (`.value`), 176 (`.panels`), 829 (`.environment`, whose nodes `RK-O`/divergence 346 refuse).

**Ruling.** (1) `RK-J`'s gate for M1 — at least 0.4 ms on release `.panels` — is **met on thread-CPU time in three runs of three** (0.50, 0.43, 0.46 ms) and on wall time in two (the third was
contended); it was **not met before `RK-T`** (0.32 ms), so the gate is also the evidence that `RK-O` item 2 cost real time. (2) `RK-L`'s M1 expectation (−0.4 to −0.8 ms) holds at its lower edge;
`RK-A`'s ceiling and the −15 % refutation line are for M1 and M2 together and are lane 2's to judge — M1 alone is 5–8 % of a 6–7 ms frame. (3) M3 moves no drag frame (`translated == 0` in
every arm of the drag); its win is counted on the pan (`translated >= 64` over eight steps) and **not timed**. (4) `RK-I`'s criterion holds: a moving label under an `.offset`, at scales 1 and 2,
reads 0 `placeGlyphs` and 0 seam measures on the replay frames (`aStaticLabelOverlayReplaysAndAMovingOneReplaysTranslated`, 8 arms; `theOverlayCostIsLinearAndCounted`, for plain labels, is
unchanged at one `placeGlyphs` per label per frame), so **`MetalDrawContext.drawText` and its SDL twin stay deferred** (`GT-F`) and the label's remaining per-frame cost is the build. (5) The
MetalCreator frames (17.05, 18.64, 20.56 ms) are not expected under 16.67 ms from this item alone (`RK-L`); the reading is left to a MetalCreator run.

**Cost if wrong.** A reader takes M1's 0.3–0.5 ms as the item's whole win: lane 2's graft is where the build and layout share (`RK-A`'s 57 % of a render after paint replay, record §109 §10) is attacked.


## RK-X — Lane 2 step 1: graft plus journal is 17.7 % of the build it replaces, per outermost occurrence (`RK-J`'s 50 % stop did not fire; settles `RK-P`)

**Question.** `RK-A` measured the rows alone (13 %) and `RK-P` withdrew its per-frame figures. With the journal applied again, the top-level lowered items re-recorded and the dependency checks, is the graft still cheaper than the build, **per frame, outermost occurrences only**?

**Evidence.** `docs/probes/retained-build-skip/graft-journal-cost.patch` (applies to `0e32911b`; an experiment, never merged; `README.md` there has the command): inside `EquatableComponent.requestGroupLayout` it times each **outermost** occurrence's build (from after `enterComponent`'s memo to the return of `finishComponent`, with the graft window open, so the journal's recording cost is in it) and stores it in the graft record; when that record later grafts, it times the whole graft path (`graftRecord(for:)`'s checks are *not* in it, `graftOccurrence`: the rows, the item records, the journal applied again, the counters) and adds the build time the graft stood for. Release, the bracket window's three node-drag arms (30 drags each), 2026-10-14 13:41 UTC (the build and the run), MacBookPro18,2 / M1 Max, **a shared Mac with load averages of 119–148** (both timings are of one process, interleaved, so the ratio is the reading, not the milliseconds):

    RK_EXPERIMENT builds=3933 grafts=31047 graftedNodes=417138 buildMs=569.925 graftMs=333.144 buildStoodForMs=1877.341

Per grafted outermost occurrence: **60.5 µs of build stood for, 10.7 µs of graft: 17.7 %**, 13.4 nodes on average (`RK-A`'s probe: 13 % and 27 nodes: the journal, the item records and a smaller average occurrence). The figure is per occurrence and **not** a per-frame saving: the frame's saving is read in whole-process medians (record 110 §10).

**Ruling.** The 50 % stop did not fire; M2 stands and is built (`RK-Y`, `RK-Z`). `RK-A`'s per-frame budget stays withdrawn (`RK-P`); the per-frame reading is the in-process alternation below, judged against `RK-L`'s M2 expectation (-1.0 to -1.4 ms) and the item's -15 % refutation line: **the graft alone reads -1.26 to -1.61 ms of thread-CPU per drag frame (3 runs, both arms), and all of the item against `fb9a7e42`'s behaviour reads -1.74 to -2.02 ms (-23 % to -26 %)**, inside `RK-A`'s -28 % ceiling and past the -15 % line. `RK-L`'s statement that this item alone would not bring MetalCreator's frames under 16.67 ms is untouched: a 1.7 to 2.0 ms saving per frame is what the item brings; the verdict is a MetalCreator reading.

**Cost if wrong.** The probe's timer reads sit inside the thing measured (two clock reads per occurrence); the ratio is what is claimed.


## RK-Y — What a graft stands on, and what it leaves behind (builds `RK-B`; the optimistic decision of `RK-C` applied at the build)

**Question.** `RK-B` said a grafted occurrence has no element tree and that prepaint and paint replay. What is the decision at the build, and what is a graft allowed to know?

**Ruling.** (1) **The record.** Every `.equatable()` occurrence that builds with graft recording on (`ContentMemoStore.recordsGrafts`: graft switch on, prepaint replay on, retention on, a window that redoes) opens a **graft window** after its own `enterComponent` and `materialize` (`Frame.openGraftWindow`) and closes it after `finishComponent` (`closeGraftWindow`): the **`GraftRecord`** is the `LayoutSegment` of the nodes the window registered, the journal slice (`RK-Z`), the `BuildKey`, the content serial, the element requests the build made, the nested memo keys, the live `@State` entries and the animation entries it touched, and the lowered-item records of its top-level nodes. It hangs off the memo `Entry`; an occurrence that built and could leave none is counted `retainedGraftIneligible` and the reason (one name) is kept for the build (`ContentMemoStore.lastGraftRefusals`).
(2) **The decision** (`Frame.graftRecord(for:id:key:)`), taken at the build after the content memo has hit: graft allowed (switch on, retention on, replay in force, not a redo, not in the window-wide backoff), a graft record **and** a paint record with a prepaint ledger, none of them invalidated (`observedChange`, `coverageComplete`, `contentSerial` equal to the entry's serial for both the paint record and the graft record), the entry not quarantined, the `BuildKey` equal, no pending `scrollTo`, no custom environment key, no animating transaction, every `@State` slot the paint record holds at its recorded version, no pointer, press or focus under the occurrence and the pointer outside every hitbox of its ledger, and every dependency of the record still there and unchanged (`graftDependenciesHold`: nested memo entries neither stale nor observed-changed, live `@State` entries and animation entries present).
(3) **What it cannot know** is what `RK-C` named: the occurrence's rects (layout comes after) and the paint-only ambient. A graft is therefore optimistic, and the one repair is the redo: a grafted occurrence whose prepaint decision is `run` (key mismatch, a refused translation, a quarantine) or whose paint decision is not a hit **requests a redo** and draws nothing; the window builds the frame again with every graft and replay off (`RK-M`). The redo's own build is the fresh build, so it cannot ask again.
(4) **What a graft returns.** `ComponentLayout.storage.payload` is optional; a grafted occurrence has `nil` and a `RetainedGraft` marker, `withPayload` and `content` trap **by name** when read (`(RK-B)`), and `EquatableComponent.prepaintGroup` and `paintGroup` branch on the marker before anything reads the payload. The two element-phase readers of a payload are `Component.prepaintGroup` and `paintGroup` (`everyReaderOfAComponentPayloadIsNamed` scans `Sources/` for a third). The occurrence's `RetainedBuild` (top nodes, mark journal range) is made as for a build, so prepaint and paint read the same geometry.
(5) **Counters** (`RK-K`): `retainedGrafts`, `retainedGraftIneligible`, `retainedSkippedRequests` and `retainedGraftedNodes`, public on `FrameWork`; `elementRequests + retainedSkippedRequests` is the frame a graft-off build counts (`theBuildRecursionIsSkippedForAnUnchangedSubtree`), the enclosing occurrence's own record counting a nested graft's requests (`skippedRequests` is read at open and close).

**Cost if wrong.** A graft that should not have stood (a dependency the record does not hold) draws the picture of an older build; the differentials compare the scene, tree, hitboxes and state table against a retention-off window at every step, and verify mode compares the whole frame against a build (`RK-AA`).

## RK-Z — The journal as built: what it records, what it refuses, what it re-records (corrects `RK-F`)

**Evidence.** Read from the source and from the first runs (the bracket's occurrences were refused for `elementBounds` and `loweredItems` until each was settled).

**Ruling.** (1) **The journal** is one list on the memo store (`BuildJournal`), appended to **only while a window is open** (one integer test per funnel otherwise). Events, each recorded by the funnel that makes the call and applied again by that same funnel (`Frame.reapply`, so `sweep()`, `noteNamed`, `ID-C` and `ID-R` read what they always read): `mark`, `noteProduced`, `noteAbsent`, `noteNamed`, `noteLoop`, `noteWindowedParent`, `noteFocusState`, a `withState` on an animation baseline (`$anim…`, kept live without a write: `markLive`), the memo touch of every occurrence entry reached (so a nested occurrence's entry survives the sweep), the animation store's touches, and the transition store's `evaluated`, `produced` and array-extent notes. A replay appends to the journal again, so an enclosing window sees what a graft inside it stood for.
(2) **What refuses a graft by name** (`BuildAudit`, counts read at open and close; any that moved): `timeVarying` (the clock or an interpolation), presentations and their records, `hiddenNodes`, `scrollKeys`, toolbar records, open-URL and navigation notes, a colour-scheme preference, content limits, another frame wanted, an unlowerable-field report, lifecycle, timeline, transition-group and surface registrations; and any **`withState` that is not an animation baseline, and any `write`**, taint the open windows (`stateWrite`: a build that rewrites an entry is not a function of the key). A segment refuses a range that is not a clean subtree (`childOutsideRange`, `parentOutsideRange`, `strayRoots`, `top`, `noKernelCase`).
(3) **Not a refusal, against `RK-F`**: `elementBounds` (written in prepaint, which the ledger replays; the build writes none) and the lowered items. The **top-level nodes' items** are carried in the record and recorded again for the new nodes (their parent consumes them after the occurrence returns, `LR-AB`), the origin of a forwarded one remapped by offset; an **interior** item is consumed or reports nothing (a `Text` leaf under a proposal container has default fields), so it is left out; an unconsumed interior item with a field that `reportUnconsumedLoweredItems` would report refuses (`interiorItemUnconsumed`: a graft must not hide a diagnostics report). Interior aliases and text leaves are read only by the element phases a graft does not run.
(4) **`LayoutTree.graft`** appends the rows under the tree's own generation (one pass, rects and measured widths zero, a grid plan's cells moved, grid row marks given **fresh tokens** so two grafts of one segment are two row groups) and answers the new top-level ids; `captureSegment` is the registration check (`SA-I` applies: not while laying out). Both are `package`.

**Cost if wrong.** A missed event is a reaped `@State` or a reset that fires or does not; `aGraftedFrameKeepsTheStateTableSweepsExact` compares the entries and the memo count after every step, and verify mode compares the sets of the sweep-visible channels (`RK-AA`).

## RK-AA — Verify mode over the graft as built (replaces `RK-N`'s "compared whole-frame" for the tables; extends `RK-V`)

**Ruling.** A frame that replayed a prepaint (every grafted occurrence has) is already built twice under `METALUI_VERIFY_RETAINED=1`; the snapshot gains **the layout tree** (`LayoutTree.structureDigest`: per node the children, the kernel case, the leaf key, the spacer axis, the parent, the grid marks by row equivalence, the rect and the measured width after layout) and **the table channels** (`BuildChannels`: marks, produced slots, produced names, named positions, loop extents, windowed parents, the memo entries kept for the sweep, the animation entries touched), each **read after the root's paint and before the sweep**. The rebuild only adds to the sets the first build left, so equality means the first build's journal missed nothing the fresh build did. **Found by running it:** the first spelling compared the tables after the presented rebuild had **finished**, whose `sweep()` had cleared them (118 marks "missing"); the comparison is part of the snapshot now. One exit test per damaged channel (`aVerifiedGraftThatDiffersTraps`: leaf keys, marks, produced, named, loops, memo touches, through `Window.testingCorruptGraftRecords`) and a control that draws normally.

## RK-AB — The pins that read a built frame keep reading one

**Ruling.** A graft changes what `elementRequests`, `contentSkips` and the translation refusal count, so the lane 1 pins that count a build **run with the graft off by a parameter, not by an edit of the literal**: `bracketDragFrames(graft: false)` and `RPPair(graft: false)` (translated arms), `anEqualComponentSkipsItsContent` (`testingRetainedGraft = false`, the memo's own pin). Every other `RPPair` differential runs grafting by default and every one stayed green: they are the graft's differentials as much as lane 1's. The graft's own counts are `RetainedGraftTests`.

## RK-AC — The lane 2 mutation battery: what each guard's pin is, what was found to be redundant, what is carried

**Question.** Which pin kills which line of the graft, and which lines no test can see?

**Evidence.** The graft's mutations were applied through one `RK_MUTANT` environment switch on the committed code (thirty-nine spellings in two batches, one build each, a filtered run per spelling; the switch was never committed), at two moments: against the first test set (it left four mutants alive: `versionsIgnored`, `depsAlwaysHold`, `topItemsNotRecorded`, `interiorItemCheckOff`, and two that only verify mode's exit tests caught, `skipProduced`, `skipLoop`), and again after the pins this ruling names were added. **A filter that misses the new test names reads green**: the second battery's first run used a filter that did not name them (56 tests, nothing new), and the six "survivors" it printed were not survivors (re-run with the new names, same build).

**Ruling.** (1) **Killed, by name**: `versionsIgnored` by `aStateWriteFromOutsideRebuildsAGraftedOccurrence` (19d); `depsAlwaysHold` by `aNestedOccurrencesObservedChangeRebuildsTheGraftedOuter` (the outer's own value changes first, so the nested getter's read is not in its observation window and only the nested entry's staleness can stop the graft); `skipProduced` by `aConditionalInsideAGraftedOccurrenceStillResetsItsState` (15b); `skipNamed` and `skipLoop` by `aLoopInsideAGraftedOccurrenceStillResetsTheRowsItLoses` (15c: **a `ForEach(id:)` row is a named position, so the named path resets a dropped tail without the loop event; the card holds a positional `for` loop beside it so `skipLoop` has an arm of its own**); `skipCellColumns` by `aGraftedSubtreeEqualsAFreshBuild` (its grid gained a cell that spans two columns: a column count of 1 hid a skipped table); `gridPlanNotShifted` by a **trap** (the unshifted plan's cell ids carry the recording tree's generation: the run prints no summary line, which is a reddening, `C-3`).
(2) **Not separated, carried**: `topItemsNotRecorded` (the re-recording of a top-level node's lowered item for the new id) — a legacy `Row` over a grafted `Box` with a `margin` or a `flexGrow` lays out identically with and without the record in every spelling tried (the `flexGrow` one never grew even in the retention-off window, a measured property of a component's top node inside a legacy row); `theLoweredItemOfAGraftedTopNodeIsRecordedAgain` stays as a differential control and says so. And `interiorItemCheckOff` (a graft refusing an interior item that a diagnostics report would name): it needs a diagnostics-mode window over an occurrence with an unconsumed interior field, which `aGraftIneligibleBuildIsCountedByName` does not build. Neither can draw a wrong frame in a mode that ships; both are owed an arm (C14b-3's brief).
(3) **Redundant by design, recorded**: `versionsIgnored` does not redden `aStateWriteToAPlainChildRebuildsAGraftedOccurrence` (19e): a plain child's `@State` is already seen by the card's own content memo, so the paint record's version list and the content memo agree and either one stops the graft. 19d (a nested occurrence's own state, whose entry is stale while the card's memo is not) is the arm that separates the version compare.

**Cost if wrong.** (2) leaves two lines of the graft pinned only by a differential that cannot see them; a refactor that drops the top-item record would not turn the suite red.

## RK-AD — Two compared windows pin one timeline clock (the `aRedoWithATimelineInTheTreeEqualsAFreshFrame` flake)

`TimelineStore.date(at:)` anchors `clockOffset` to `Date()` at a window's **first non-zero draw** (`KF-Y`), so two `TestWindow`s compared by `RPPair` anchored a few milliseconds apart; when a wall-clock second boundary fell between the two anchors the periodic timeline showed two different ticks (`after the redone frame: ["glyphs"]`). Not a product bug: a real window has one clock. `RPPair` now sets `Window.testingTimelineClockOffset` (a `package` hook in `TestingHooks.swift`, not public) to 0 on both windows before any frame. Pin: the existing test, with a 20 ms-past-the-second sleep between the two windows' first draws, reddened before the fix and is green after.

## RK-AE — Pinning the clock after the first frame forgets the cursors made before it (the flake RK-AD did not close)

`RK-AD` set `testingTimelineClockOffset = 0` on both `RPPair` windows, but a `TestWindow` has already drawn its first frame at timestamp 0, where `TimelineStore.date(at:)` answers the wall clock (`KF-Y` item 1) and a periodic cursor is created from that `Date()`. The offset applies only to later frames, so the cursor's `shown` stayed a wall-clock bucket per window: two windows whose first draws fell either side of a wall-clock second boundary showed two different ticks again (PR #137, Windows root CI: `["glyphs", "accessibility tree"]` after `aRedoWithATimelineInTheTreeEqualsAFreshFrame`'s redone frame and a tick later; green on rerun). **Cause: inferred from the code and the measurement below, the CI failure itself not reproduced.** Measured: with the old setter a periodic timeline shows `814749105.0` after the offset is set to 0 and the clock advanced 2.4 s; with the fix it shows the simulated clock.

**Fix:** `TimelineStore.resetCursors()` (cursors and the pending wake dropped) is called by the `package` setter `Window.testingTimelineClockOffset`, so the next build anchors every cursor on the pinned clock; a pair's timeline dates are then a pure function of the simulated clock. No public API, no product behaviour change (the setter is a test hook). Pin `pinningTheTimelineClockAfterTheFirstFrameDropsTheWallClockDate` (`RetainedPrepaintTests`); mutation: remove the `resetCursors()` call, the pin reddens with the wall-clock date. Other tests setting the offset (`FinerScopesElementTests`, `RetainedWithStatePanelTests`) take the same fix; none other compares two windows with a periodic or `.animation` timeline whose first frame precedes the pin.

## RK-AF — An abandoned frame stores no record from an occurrence it left holes in (found by `METALUI_VERIFY_RETAINED=1`, record 256)

**Question.** `indicesAreStableWhileTheDocumentGrows` (`BM-L`) trapped under `METALUI_VERIFY_RETAINED=1` with `replay differs from a fresh run … scene.count 6 vs 16`, and the same document grown in a plain run drew 2 glyphs where a fresh window drew 8. It was not the copy button: the trap reproduces with no button and no prefix.
**Cause.** A transcript that grows by whole blocks moves the earlier blocks, and each is a grafted `.equatable()` occurrence whose prepaint key (offset, scroller) no longer matches. `EquatableComponent.prepaintGroup` then asks for a redo (`RK-C`) and sets `phase.abandoned`; its paint returns without emitting a leaf. The enclosing `.equatable()` occurrence (the `MarkdownView`) is still recording that frame, and `finishRetainedPaint` stored what it held: only the new blocks, a record with a hole. The redo then hit that record (same key, same serial) and replayed the hole, and every later frame did too: the earlier blocks vanished. Verify mode compared the same hole with a complete fresh run. Nothing before `BM-L` grew a retained document in a window that also verified, so no test saw it.
**Ruling.** An occurrence that returns from paint without emitting because the frame is abandoned (the three early returns of `EquatableComponent.paintGroup`: `phase.abandoned`, and the `.plain` and `.record` arms for a replayed or grafted prepaint) calls `RetainLog.noteRedoHole()`, which marks every open recorder `redoHole`. `finishRetainedPaint` returns for such a recorder, storing and comparing nothing (a standing record stays); the redo records the occurrence whole. Only the enclosing occurrences lose their record: the siblings that painted completely keep theirs, so the redo still hits them (a first version dropped every record of an abandoned frame and doubled the misses in `aMovedOccurrenceCostsOneMissAndTheNextFrameHits` and `theKeyOnlyArmCostsOneMiss`, h4 m4 became h2 m6).
**Pin.** `aTranscriptThatGrowsByBlocksDrawsWhatAFreshWindowDraws` (`MarkdownStreamingViewTests`), ungated. Mutation: the early return removed, 2 glyphs and 2 rects against 8 and 4, red; with it, green, and `indicesAreStableWhileTheDocumentGrows` no longer traps.
**Cost if wrong.** An enclosing occurrence is recorded one frame later than it could have been.

## RK-AG — A graft record is copied at the end of the frame, and only where a later frame can graft from it (G47, record 407)

**Question.** Alloy scrolls a 1M-row `Table` inside five nested `.equatable()` occurrences and types into a `TextField` inside a chain of them. On every such frame each ancestor missed its graft, built, and closed its graft window, which copied the table's whole subtree (`LayoutTree.captureSegment`: about 1,000 `NativeNode`s and their child lists, plus the journal slice) about 0.25-0.3 ms a level. The copy was wasted: the same frame's paint was ineligible (`activeAnimation` from the scroll indicator, `stateWrite` from the scroll and `TableBody`'s `lastPlan`) or ran under the pointer, a press or focus (`SB-X`), and each of those leaves the entry with no paint record, so `graftRecord` answered `nil` on the next frame whatever the graft record held.

**Ruling.** (1) `closeGraftWindow` no longer copies the children and kernel cases. It takes what a container built after the occurrence may still write (`LayoutTree.captureSegmentMarks`: the leaf keys, spacer axes, spacing marks, grid marks and right-to-left flags of the range, and the checks of the tops, `markSpacers` walking down through a top's wrappers to the spacers, a `Grid` marking its cells), the journal slice and the top-level items, and parks them in `ContentMemoStore.pendingGrafts`. (2) `Frame.flushPendingGrafts` runs after the root's paint and before `StateTable.sweep()` and makes the `GraftRecord` (`LayoutTree.completeSegment`: children, cases, parents; written once, at registration, and never afterwards, but for a top's parent, which a segment does not carry) **only if the entry then holds a paint record with a prepaint ledger and complete coverage**; otherwise `entry.graft` stays `nil` and `retained.graftCapturesSkipped` counts it. An abandoned frame drops the pending list (the frame is built again). (3) `FrameWork.retainedGraftCaptures` and `retainedGraftCapturesSkipped` count the two outcomes.

**Why it is exact.** `graftRecord` answers `nil` unless `entry.record != nil`, `entry.record.prepaint != nil` and `old.coverageComplete` hold (its first guard and the `old.coverageComplete` conjunct). Between the flush of frame N and that call in frame N+1 nothing writes `entry.record`, its `prepaint` or its coverage flags: they are written by the paint and prepaint of an occurrence, which run after the build that asks, and coverage is set once when a record is made. So an entry with none of the three at the flush cannot graft in the next frame, whether or not a graft record exists, and an occurrence that is not built in the next frame keeps `entry.record` as it is, so the answer holds in the frame it is next built. The skip turns no would-be graft into a miss; every frame whose record would have been usable captures as before. **No history is used**, so there is no backoff to recover from: the first frame after scrolling or typing stops makes a paint record, so its flush copies, and the frame after it grafts as before (the pins show the whole sequence against a build with the rule off). The deferred copy reads the same rows: the marks and the tops' checks are taken when the window closes (before the container written to them runs); the rest is immutable between registration and the flush (`childLists` and `nativeNodes` are written once per node; nodes registered later lie above the range's upper bound, which the pending record keeps).

**Evidence.** `GraftCaptureBackoffTests`: a scroll of six steps through five occurrences copies 0 rows (master 30) with the frame work unchanged (3384 requests, no hit); six keys into a focused field copy 0 (30) with 24 requests unchanged; after the scroll the pointer leaves and the indicator's fade ends, that frame copies five records and builds as before (564 requests), and the next three are one graft each standing for 564 requests; the same sequence after focus leaves. Mutations: the flush capturing always (master's behaviour: the three cost pins red, the frame work equal), and the flush never capturing (the two recovery pins red).

**Cost if wrong.** A graft record missing where the old rule had one makes that occurrence rebuild one frame more; the exactness argument above says no frame can show it, and the recovery pins would name it.

## RK-AH — A window's slice of the build journal is copied at the flush, for the occurrences that earned a record (G47, record 412)

**Question.** `closeGraftWindow` copied its slice of `BuildJournal.events` (rewriting each lifecycle note's order) into the `PendingGraft` at every window close, then `flushPendingGrafts` threw it away for any occurrence with no paint record, prepaint ledger and complete coverage (`RK-AG`). Under nested `.equatable()` occurrences each window's slice starts near the front of the journal: four 736 KB copies a frame in Alloy's probe (about 14k events each), 236-267 ms of the profile's closure `#2`, the `map`.

**Ruling.** The pending graft keeps the slice's **range** (`PendingGraft.events: Range<Int>`) and the window's `lifecycleBase`, and the journal is not cleared while any window is pending: `BuildJournal.held` is `ContentMemoStore.pendingGrafts.count` (its `didSet`), `clearIfIdle()` clears when no window is open and none is held, and the flush copies (`BuildJournal.rebased`) only for an entry it makes a record for. The journal empties when the list does (end of the flush, a redo's `resetBuildCounters`). `OutlineContentCache` clears through the same `clearIfIdle()`. **No slice of the buffer is kept**: a held `ArraySlice` would make the clearing `removeAll(keepingCapacity:)` copy the whole buffer on the next frame (the 50 MB to 309 MB blow-up of an earlier attempt); the range is two integers, the buffer stays uniquely referenced and clears in place, and its capacity is the peak of one frame as before.

**Exact.** The rebased events are the same events of the same range in the same order. The journal appends only while a window is open, so events between top-level windows do not exist; a later window opens at the current count and its range cannot overlap an earlier one's end.

**Evidence.** Record 412: 4 copies of 736 KB a frame gone (bytes per step -2.9 MB), `phys_footprint` and live blocks not above base. `ScrollAllocationChurnTests` reads the bytes.

**Cost if wrong.** A journal that stayed held after the flush would grow by a frame's events per frame; `pendingGrafts`'s `didSet` is the one place that releases it, and the flush's `defer` empties the list on every path.

## RK-AI — A redo starts from the table the abandoned attempt found: an undo log on first write (amends `RK-D` item 2, `RK-M`, `RK-U`, `RW-U`; record 417)

**Question.** `RK-U` listed what the redo restores (the animation checkpoint, the scroll queue, the surface counts) and called the `StateTable` channels idempotent. Record 416 found a redone frame whose registered element bounds sat 11 points from a fresh frame's (every lazy row, the streaming one included), and a scoped redo that was inexact for the same family of reasons. What does the abandoned attempt write that the redo reads?

**Evidence.** `ExactRedoTests.swift` (a bottom-anchored `LazyVStack` of 51 `.equatable()` rows with a rounded tinted chrome, one word streamed a frame, a replayed card under an opacity that changes every frame so the frame is redone): on master the first redo frame differs from a retention-off window in the element bounds of all 51 rows (11 points) and nothing else. The cause is the lazy container's `RowExtentIndex`, a class in a `LazyOrigin` entry: attempt 1's prepaint records the realised rows' extents into it, and the redo's layout plans the window from them, so the rows are placed against this frame's measurements. With the index's journal off the difference returns (mutations M2, M6, M7); with only the table's undo log off the bounds stay equal in this fixture (M1) and the digest tests are red: the entries the prepaint writes (the scroller's anchor memory and clamp, `LazyOrigin`, `ListOrigin`) were also left as the attempt wrote them, and a redo that read them differently would differ the same way.

**Ruling.** (1) `StateTable.beginAttempt()` is armed by `Window.buildAndAdoptFrame` under the checkpoint's own condition (`prepaintReplayAllowed && ledgerEntries > 0`) and always in verify mode. While armed, the **first** write of each id (`withState`, the compared form's write, `write`, `mark(seeding:)`), the first deletion (a mid-frame reset, `noteProduced`) and the first liveness flip of a tombstone (`mark`, `touchLive`, `markLive`) put the entry as it stood (value, generation, `isLive`, version; `nil` for an id the attempt created) into `attemptUndo`. (2) `rollbackAttempt()` restores each, deletes the created, restores `marked` (a snapshot taken at the begin) and truncates `readJournal` and `markJournal`; it returns the created ids. `versionCounter` stays monotonic and restored entries keep their versions, so a standing ledger's versions still match. It runs where the redo restores the checkpoint, and **replaces** verify mode's `discardEntries(createdSince:)` (amends `RW-U`: that rolled back only the created entries, and kept `$ax`; the rollback also restores the existing entries the first build wrote, and deletes a `$ax` the attempt created, which the fresh build creates again before anything is published). (3) `acceptAttempt()` runs at the top of `sweep()` (a frame that reaches its sweep is the one kept; an abandoned frame returns before it) and again in the window after adoption; it clears the log, keeps its capacity, and drops it above 1024 entries. (4) `onWrite` fired for the attempt's `@State` writes and is not undone: the window may draw one frame more than it needed, never one fewer. (5) Not rolled back, classified: `producedSlots`, `namedPositions`, `loopExtents`, `windowedParents`, `departedNames` (idempotent unions, `RK-U`, pinned by `BuildChannels`), the content memo's counters and records, `ScrollPositionRegistry.update` (overwritten every attempt), the shaping and layout caches. The glyph atlas is the next record's (an attempt bracket), not this one.

**Exact.** The log holds the value the entry had before the attempt's first touch, and the rollback assigns it back, so after it the table equals the table at the begin in every entry (value, generation, liveness, version), `marked` and both journals: `aRolledBackAttemptLeavesEveryStoreAsItFoundIt` compares the digest of all of it. A write after the first changes an id already logged, so the log is one entry per distinct id.

**Cost.** A branch per write when no attempt is armed; when armed, one dictionary insert per distinct written id (about 70 bytes and one hash) and a snapshot of `marked` (empty at a frame's start). A quiet frame writes nothing and logs nothing (`aQuietFrameWithAnArmedRollbackLogsNothing`); a streaming frame logs the scroller's one entry (`aStreamingFrameLogsOneEntryPerWrittenState`). Record 417 has the footprint and allocation readings.

**Cost if wrong.** A write path that bypasses `logUndo` leaves one entry as the attempt wrote it: the redo reads a value the fresh frame would not. The digest tests name the entry; a new `storage` write site owes a `logUndo` and the table test an arm.

## RK-AJ — In-place reference state in an entry owes `AttemptRestorable` (record 417)

**Question.** The undo log restores an entry's value, and a value that holds a class holds the same reference afterwards: `RowExtentIndex` (in `LazyOrigin.extents` and `ListOrigin.extents`) is mutated in place by layout (`rebuild`) and prepaint (`record`, `forgetMeasurements`). What restores it?

**Ruling.** A class mutated in place from inside a state entry conforms to `AttemptRestorable` (`beginAttempt`, `rollbackAttempt`, `endAttempt`, and `attemptContents` for the digest) and is registered with `StateTable.restorable(_:)` **before** its first mutation of the attempt (registration begins its journal; registering twice begins once; a call with no attempt open does nothing). `RowExtentIndex` journals the old height and id of each row `record` changes, the old value of **each Fenwick node** it touches (a restore by the inverse delta is not exact in floating point, and the sums are accumulated in a history-dependent order), and the arrays themselves as a snapshot on the first `rebuild` or `forgetMeasurements` (O(n) and transient, on a data or width change only; records logged before the snapshot are undone over it). Equal records journal nothing. `LazyLinePlanner.plan` and `.prepaint` (`LazyStack`, `LazyGrid`) and `List.variableWindow` and `prepaintVariableRows` register the index. A new class of this kind in a state entry owes the conformance; the census of every class held in an entry (PR 1.3 of `docs/superpowers/plans/2026-11-25-exact-redo-and-movable-records.md`, not yet built) is the net, and a class that is a cache with exact keys (`ShapingCache`, `LayoutMemo`) is classified instead.

**Cost if wrong.** An unregistered mutation shows as a frame that differs after a redo, in the element bounds first (`theRedoFrameRegistersTheElementBoundsAFreshFrameDoes`).

## RK-AK — Verify mode checks the rollback and the classes held in state; the redo backoff is a package switch (record 419)

**Question.** `RK-AI` and `RK-AJ` make a redo exact for the channels they list. What names a channel nobody listed, and what proves the window-wide backoff (`RK-D` item 3) is no longer hiding one?

**Ruling.** (1) **Verify mode's `rollback` channel.** With `METALUI_VERIFY_RETAINED=1` the window digests the state table (every entry's value description, liveness, generation and version, the mark set, the journal lengths, every `AttemptRestorable`'s contents) and the glyph atlas (glyph map with stamps, slot map, packer, counters, pixels, dirty regions) before each attempt, and again after every rollback (the redo's and the replayed frame's); a difference traps with the first differing line: `METALUI_VERIFY_RETAINED: rollback: the rolled-back attempt left ...`. (2) **The census.** `StateTable.referenceClasses()` walks every entry's value (depth 6, 16 elements a collection) for class instances; each framework class (module `MetalUI*`, `Swift`) is `AttemptRestorable` or has a row in `StateTable.classifiedReferences` (`cache`: a pure function of its key, or a hint every reader verifies; `immutable`: written by input events or copy-on-write, never by a build). Verify mode traps on one that is neither (`unclassifiedReferences`); an app's own class held in `@State` is the app's contract (a build must not write it). `everyReferenceHeldInStateIsClassified` builds 26 demo windows and fails on an unclassified class and on a stale row. Found: `AXDeclarationsBox`, `KeyPath`, `MarkdownSourceMemo`, `TableResizeDragBox`, `TableRowPositionCache` (and `RowExtentIndex`, restorable). (3) **`Window.testingRedoBackoff`** (package, default true): off, `noteRedo` does not set `prepaintSuspendedUntil`; the failing entry's own quarantine (8, 16, ... builds) stays. The product is unchanged. (4) The `TextSystem.abandonFrame()` default is `endFrame()`, not a no-op (a conformer that checks its bracket needs it closed; the cost is the double aging it had).

**Evidence.** Record 419: with the backoff off, the full suite (forced off globally for the run, not committed) gave the failures classified there; `aMirroredScrollersGrowing...` and `aZoomedNodeIsHitWhereItIsDrawn` pass, and the first needed `RK-AL`.

## RK-AL — A graft stands only while the scroll context its build read is the one in effect (record 419)

**Question.** With the backoff off, record 416's `aMirroredScrollersGrowing...` showed the lazy window stale after a scroll step (20 glyphs against 36), with the state table and the index equal to a fresh window's. Which channel?

**Evidence.** Not a rollback channel: the same difference shows with the backoff **on** when the warm-up outlasts it, in a left-to-right scroller as well, and with no redo in the run. An `.equatable()` occurrence that holds a lazy container (here `LazyHStack` in `G49LazyRow`) grafted across a scroll step: the graft's build read the scroller's offset through `LayoutPass.scrollContext`, a value of the stack of contexts outside the occurrence, which neither the graft's state reads nor its key hold (the key holds only whether a context exists). With graft off, prepaint off or translation off the window is right; with them on it is not. The nine-build backoff after a redo had been covering the one test that scrolled.

**Ruling.** `LayoutPass.scrollContext` journals the read (`BuildJournal.Event.scrollContextRead(context, depth)`, the depth of the context stack where it was read); `reapply` re-journals it for an enclosing window; `graftDependenciesHold` refuses a graft when a read made at a depth no deeper than the occurrence's own (outside every scroller the occurrence opens) differs from the context in effect now. A lazy container, a `List` or a table body in an occurrence therefore rebuilds on a scroll step and grafts again when the scroller stops; an occurrence that does not read the context pays nothing.

**Cost if wrong.** A graft kept across a scroll step shows the old window; `aScrollStepRebuildsALazyContainerInsideAnEquatableOccurrence` (both directions, backoff on, no redo).

## RK-AM — A redo rebuilds the failing occurrences and what is under them, not the window (amends `RK-D` item 3, `RK-M`; record 423)

**Question.** With the rollback exact (`RK-AI`, `GL-K`, `RK-AK`) and the suite green with the nine-build backoff off (record 419), can a redo be scoped to the occurrences that asked for it? Record 416: the window-wide suspension of graft and prepaint replay kept Alloy's transcript on the rebuild path for 24 of 30 deltas.

**Ruling.** (1) `noteRedo(entries, scoped: true)` no longer sets `prepaintSuspendedUntil`. It quarantines each failing entry (8, 16 ... builds, the entry's exponent) **and its identity as a scope** (`RK-AN`). (2) The window rolls the attempt back (state table, atlas, the animation checkpoint, the scroll queue, the surfaces) and builds attempt 2 with `memos.redoScopes` = the failing ids and `redoInProgress` set. `prepaintReplayAllowed` holds in attempt 2 while scopes exist, so every occurrence grafts and replays as in attempt 1 except the ones `isInRedoScope` names (at, under or **above** a scope, a defence: an ancestor of a failing occurrence was built in attempt 1 and decides the same in attempt 2) and the ones under a quarantined scope; the trace names the refusal `scopedRedo` (prepaint) or in `graftRefusals` (graft). Attempt 2 is armed (`beginAttempt` on the table and the atlas) because it may ask again. (3) **Exact** because attempt 2 is a legal build of the frame with fewer grafts (`RK-Y`, `SB-W`): the rollback put every channel back, a ledger or record the attempt made names versions or glyph slots the rollback invalidated (`RK-AI`, `GL-K`), and `RK-M` (a) cannot happen since the whole subtree of a failing occurrence is refused. (4) **Window-wide remains, with the nine-build backoff, when:** attempt 2 itself asks for a redo (**escalation**: a third build with every replay off, `retained.redoEscalations` = 1, `retainedRedoEscalations`; the suite asserts 0 in `RPPair.redraw` and in the fixtures); the attempt wrote a channel declared unrestorable (`Frame.noteUnrestorable`; nothing declares one today); an occurrence has no identity to scope; and verify mode, which keeps whole-frame fresh comparisons (`RK-N`). `Window.testingRedoFault` takes the last two paths and the escalation in tests.

**Evidence.** Record 423: the chrome transcript (`ChromeTranscriptFixture.swift`) redoes 3 times in 40 streamed words; window-wide 39.1 requests and 55 prepaints a step, 22 backoff builds, 151 grafts; scoped 24.9, 34.4, 0, 235. A redo frame costs 43 requests (70 window-wide) with 4 rows still grafting.

**Cost if wrong.** An occurrence that should have been rebuilt and was replayed shows as a frame that differs from a fresh one after a redo: `aScopedRedoEqualsAFreshFrameInEveryChannel`, the redo differentials of 417 to 419 and verify mode.

## RK-AN — A failed occurrence's descendants are quarantined with it (record 423)

**Question.** The entry quarantine of `RK-D` item 3 reaches only the failing entry. Record 416: a row's descendants (nested `.equatable()` paragraphs) graft in the next frame and fail the same way one level down, a redo a frame for 18 frames.

**Ruling.** `ContentMemoStore.quarantinedScopes` holds `(id, until)`, at most 64 (expired ones go first, then the soonest to expire); `until` is the entry's own `quarantineUntil`, so the doubling (8 << exponent, exponent reset when the occurrence replays) is the entry's. An occurrence at or under a scope with `until > buildSerial` neither grafts nor replays a prepaint (`graftRecord`, `retainedPrepaintDecisionInner`'s `quarantined`). The test is an ancestor walk per decision, and the list is empty in a window that has not redone.

**Cost if wrong.** A repeating redo in consecutive frames: `aRedoDoesNotCascadeIntoTheRowsDescendants`.

## RK-AO — A refused translation says which number is fractional and whose (record 425)

**Question.** Record 416 named `inexactTranslation` as one of the two reasons a grafted row's paint record cannot follow the scroll move, and proposed two cures (snap the painted offset like SwiftUI, or recompute the moved leaves). Which cure applies depends on whose number is fractional: the scroll offset the occurrence paints under, the layout origin, or a leaf's own origin. The trace said only the reason.

**Ruling.** `paintTranslation`'s trace line (`METALUI_TRACE_RETAINED=1`, `RetainedTrace.sink`) is followed, for `fractionalTranslation` and `inexactTranslation`, by a bracket built by `Frame.describeFractionalMove`: `[entry field=<dx|dy|newX|newY|oldX|oldY> value=<device pixels> fractional=<entryOffset|layoutOrigin|both|sum> ...]` for the gate on the first top node's device origin (with the layout and offset deltas, or the entry offset, in device pixels), or `[leaf=<rect|glyph|image, groupMask. when a mask> field=<bounds|contentMask>.origin.<x|y> value=<v> fractional=<leaf|sum> move=(dx,dy) entryOffsetPx=(x,y)]` for the first leaf the move cannot add exactly. The description is an autoclosure's: it is built only while something listens (`RetainedTrace.detailsBuilt` stays 0, pinned), reads the gates in their order and decides nothing. The counters keep their one name (`retainedTranslationRefusedReasons`).

**Evidence.** Record 425: a 0.3 pt wheel step at scale 2 is `fractionalTranslation ... fractional=entryOffset layoutDeltaPx=(0,0) offsetDeltaPx=(0,-0.6)`, the next whole-pixel step `inexactTranslation [entry field=newY ... fractional=entryOffset entryOffsetPx=(0,-1.6)]`; scale 1.2 names `layoutOrigin`; the transcript fixture streams with no fractional refusal at all.

**Cost if wrong.** A trace line that misnames who is fractional sends the next fix the wrong way: `aFractionalScrollIsRefusedWithItsFieldAndWhoIsFractional`, `anInexactLayoutOriginIsNamedAsTheLayoutOrigin`, `aLeafWithAFractionalOriginIsNamedByKindAndField`.

## RK-AP — A redo says why, and who is quarantined for it (record 431)

**Question.** Alloy's streamed transcript shows 203 prepaint misses tagged `quarantine` in 30 deltas and 8 paint-translation refusals (`maskCrossingChanged` 5, `innerScope` 3). Are the first a consequence of the second?

**Ruling.** (1) `Frame.requestRedo(_:site:phase:)` prints `retained redo requested <path> at <graftedPrepaint|paintPlain|paintRecord> because prepaint [<guard names, note>] paint [<refusal, translation refusal, miss reasons>] grafted= replayed=`; `ContentMemoStore.noteRedo` prints `retained redo quarantine <path> for <n> builds until build <b> exponent <e> scoped=`; a `retained prepaint miss` line that says `quarantine` appends `quarantinedBy: self until build <b>` or the scope's path. The three are built only while something listens (`RetainedTrace.emit`'s autoclosure; `RetainedPhase.paintNote` is written only under `RetainedTrace.active`), so nothing is allocated otherwise (`theRedoLinesAreBuiltOnlyWhileSomethingListens`). (2) Nothing decides on a trace value; the quarantine is `RK-D` item 3 and `RK-AN` unchanged.

**Evidence.** Record 431: on the chrome transcript every quarantine miss is held by a redo, and every redo is a grafted occurrence whose prepaint could not replay for geometry alone.

**Cost if wrong.** A trace line that says the wrong cause; no behaviour.

## RK-AQ — A retained occurrence is keyed on which element under it is focused, not refused while one is (record 440; amends `SB-F` item 4, `SB-X`, `RK-E`, `RW-J`)

**Question.** Alloy's focused composer made every `.equatable()` occurrence above its `TextField` miss prepaint and paint replay on every frame (headless: 222 misses per stream, 132 per 10-step scroll, 0 with nothing focused). The rule that refuses them, `SB-X`'s focus clause, protects the focused element's own reads; the ancestors read nothing focus-related. Can the ancestors replay?

**Ruling.** (1) **Focus is a decision input, not a refusal.** `Frame.retainedFocus(under:)` answers the focused element when it is the occurrence or under it. A `PrepaintLedger` stores it as `focusedUnder` (prepaint-time value) and a `RetainedRecord` as `focusedUnder` (paint-time value; verify mode compares it). The prepaint decision's `focusMoved` is `ledger.focusedUnder != now || record.focusedUnder != now` (trace name `focus`), so a record whose frame moved focus at the prepaint/paint boundary never replays its prepaint and this cause cannot produce a redo; the paint decision's is `record.focusedUnder != paintFocus`. It is an input to the decision, not a key field, so every relation (`shift`, `clippedShift`, `shiftAndEffects`, the effect arms) inherits it. `retainedSubtreeHasPointerOrPress(under:)` (hover, press, selected `Text`) keeps `SB-X`'s refusal at prepaint, at paint and at the store; the trace text is `pointer/press under the occurrence`. (2) **The focused leaf's frame effects are ledger entries.** `PrepaintLog.FocusCall.focused(id, retains:)` is journalled by `registerHandlers` while a recorder is open and replayed by `replayPrepaintLedger` when `focusedElement` is still `id`: it sets `focusedElementProducedThisFrame` and repeats the plain `$focus` retention write (`Frame.writeFocusRetention`, bracketed with `allowedStateWrites` as the accessibility slot is, so write counts match a fresh frame and the slot stays live). (3) **A ledger or record made under a focus is no graft's to stand on**: `graftRecord` refuses `old.focusedUnder != nil` and `ledger.focusedUnder != nil`, `flushPendingGrafts` counts the capture skipped; a graft under a steady focus is carried over. `refreshLedger` also replaces a record's ledger whose `focusedUnder` differs. (4) **A moved ledger that registered a text input's focus stop refuses by name, `focusTextInput`** (`movedPrepaintLedger`, `movedCombinedLedger`): the field's hitbox already refuses `hitboxHandlers`; this closes `allowsHitTesting(false)`, where a moved ledger would replay a stale `caretRect` into the registry the input method reads. (5) **A bounded backoff keeps a focused chain whose paint record cannot be stored no costlier than before**: a focused, blinking `CodeView` taints every record (`codeCaretBlink`). `ContentMemoStore.focusBackoffs` (limit 32, table cleared whenever the focus differs from `focusBackoffOwner`) holds an occurrence plain, prepaint unrecorded and paint plain with the same ineligible count, for 8 builds after a paint taint under focus, doubling to 256; storing a record clears it. A prepaint taint under focus (the first focused frame's plain `TextField` state write) does not back off: it would hold a field's ancestors plain for 8 frames after every click. (6) `RetainedVerifySnapshot.focused` (after `resolveFocus`) is compared, which strengthens verify mode.

**Evidence.** Record 440: the Alloy fixture's focused stream step equals the unfocused step (12 element prepaints, 15 paints, 151 requests; master 18 prepaints, 22 paints), a quiet focused frame misses 0 (master 3), the steady focused frame 19,805 allocations to 14,960 (unfocused 14,273); the blinking `CodeView` under three occurrences over 40 toggles 35,588 allocations to 25,261 with the same 120 `codeCaretBlink` ineligibles and 3 ledgers (an unbounded first version made 120 ledgers and 38,828 allocations).

**Existing tests that move, deliberately.** `aPointerOrPressOrFocusInsideASubtreeMissesAndOutsideReplays`' focus section (the frame after the record is made reads 0 misses and 4 hits, was 1 and 3; moving focus to the second card misses the card left and the card entered); `theFirstFrameAfterTypingStopsCopiesAndTheNextOneGrafts` (the records made under the focus are valid again when it leaves: the graft comes one frame sooner); `aFocusedTextFieldInsideNestedEquatablesCopiesNoRows` (the first key after focus fires the sessions the stored records armed: one more frame, all hits, 28 requests against 24, 35 captures skipped against 30; the six keys still miss 30 times and nothing is copied); the steady-frame cost pins of a **focused** `CodeView` (`colourOnlyHighlightsCostWhatMasterCosts`, `changeBarsCostWhatNoneCost`, `aViewWithoutFoldsCostsWhatMasterCosts`, `aSteadyFrameCostsWhatItDidBeforeInactiveSelection`, `aSteadyFrameCostsWhatItDidWithOneCaretWhateverTheCaretCount`, `readingVirtualRowsBackCostsTheViewNothing`, `aSteadyFrameWithAHandledRevealCostsWhatItDidBefore`, `aSteadyFrameCostsNothingMoreWithOrWithoutAState`): the same requests, each miss a hit (`hits: 0, misses: 1` to `hits: 1, misses: 0`, the two-view arms 1/1 to 2/0). The record's paint-time focus is `ContentMemoStore.Entry.recordFocus`, not a `RetainedRecord` field: `aRecordThatNeverCrossesPaysNothing` pins the record's instance size at 248.

**Cost if wrong.** A focused field that replays a stale ring or caret colour, or an input method that follows a stale rect: `focusMovingBetweenTwoFieldsInOneOccurrenceRepaintsItOnce`, `aMovedAncestorOfAHitTestDisabledFieldRefusesFocusTextInput`, `aReplayedLedgerKeepsTheFocusSlotLive`, `aFocusedCodeViewsBlinkFramesCostNoMoreThanToday`, verify mode's focused-element field. The equivalent mutant is the produced flag not set at replay: `resolveFocus` returns at `isFocusable` first, and the both-equal rule prevents a replay with a non-focusable focused element.
