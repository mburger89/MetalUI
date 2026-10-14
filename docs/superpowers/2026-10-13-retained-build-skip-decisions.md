# Retained build skip — decisions

Rulings for item C14b-2 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), the continuation of
C14b (record §109, `SB-A`…`SB-AE`). Prefix `RK-`. **Next unused: `RK-M`.**
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
