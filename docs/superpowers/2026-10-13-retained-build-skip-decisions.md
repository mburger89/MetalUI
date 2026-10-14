# Retained build skip — decisions

Rulings for item C14b-2 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), the continuation of
C14b (record §109, `SB-A`…`SB-AE`). Prefix `RK-`. **Next unused: `RK-AC`.**
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
a grafted occurrence is a trap there; lane 2's first test greps every `withPayload` caller and names each (`aGraftedOccurrenceIsNeverWalkedByAnElementPhase`).

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
lost scroll: `aRedoFrameConsumesEachWindowInputOnce`), and the abandoned frame's scene, hitboxes, AX, focus registrations and
presentation records are simply dropped with the `Frame` — **nothing from it is adopted** (pinned by one differential: a redo
frame equals a retention-off frame). (2) At most one redo per render; the redo's own mismatch is impossible (its entries are
disabled, nothing else was replayed against a changed ambient — a second request traps in debug, runs plain in release).
(3) **Backoff** (`SB-R`): a redo suspends graft and prepaint replay window-wide for 8 frames; additionally each entry that
caused one is quarantined 8, 16, … 256 frames (the exponent resets after a hit that equalled its ambient), so a persistently
animated ancestor costs at most one redo per 256 frames. Paint-only replay (lane 1's) is never suspended: it has no redo.
(4) `FrameWork.retainedRedos` counts, `retainedBackoffFrames` counts the frames spent suspended.

**Cost if wrong.** A resize drag pays one frame at twice the cost then eight plain frames (lane 1's cost): the pin
`aResizeDragRedoesAtMostOncePerEightFrames` bounds it. A lifecycle or animation input consumed by the abandoned frame would be a
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
