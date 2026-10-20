# Finer retention scopes - decisions

Rulings for item C14-d (per-row `List`, per-element `ForEach` and modifier-level retention scopes) and C14-c4 (the graft site's custom-key
test). Spec: [`specs/2026-10-20-finer-scopes-design.md`](specs/2026-10-20-finer-scopes-design.md). Record: `../record/126-finer-scopes.md`
(Record phase, not yet written). Branch `perf/finer-scopes` from `711ab9c4`. Reserved divergence labels 555-564: none taken (the design
adds no public API and no SwiftUI-visible difference). Probe and instrument: `../probes/finer-scopes/`.

Prefix **`FS-`**, lettered. **Next unused: `FS-U`.** (Moves in the commit that appends a ruling.)

**Carried.** `IV-` (record 104 section 7), `SB-AC`, `SB-AE`, `SB-X` (record 109), `RK-G`, `RK-S` (translated replay, record 110), `EE-O`
(C14-c4, record 120), `RW-` (record 121), `MO-` (record 123), `VL-I` (the two list branches), `FI-I` (list rows name by description).

**What was measured first.** The item's premise is that one changed row makes its whole enclosing scope miss and every sibling rebuild.
At `711ab9c4` that is false for a row that is an `.equatable()` `Component` (reading F1 below) and true for something the premise did not
name: a row that **moves** (F2, F3) and a `List` row (F4). Every figure is a `FrameWork` count from
`docs/probes/finer-scopes/FinerScopesMeasure.swift.txt` (24 cards, scale 2, retention and prepaint replay on, a frame of three):

| # | scenario | graft | requests | prepaints | paints | hits / misses | grafts |
|---|---|---|---|---|---|---|---|
| F1 | one row's value changes (`ForEach` in a `VStack`) | off | 169 | 9 | 11 | 23 / 1 | 0 |
| F1 | same | on | 8 (161 skipped) | 9 | 11 | 23 / 1 | 23 |
| F2 | an id inserted first (24 rows shift by one row) | off | 176 / 183 / 190 | 177 / 184 / 191 | 251 / 261 / 271 | 0 / 25-27 | 0 |
| F2 | a header above the rows grows 4 pt | off or on | 171 | 172 | 244 | 0 / 24 | 0 |
| F3 | wheel -30 over a `ScrollView` of the 24 rows | off or on | 171 | 172 | 244 | 0 / 24 | 0 |
| F3 | the same, nothing moving (the ceiling) | on | 3 (168 skipped) | 4 | 4 | 24 / 0 | 24 |
| F4 | `List(rowHeight: 22)` of 9 visible card rows, nothing moving | off or on | 84 | 85 | 22 | 9 / 0 | **0** |
| F4 | same, one row's value changes | off or on | 84 | 85 | 32 | 8 / 1 | **0** |

Miss reasons (`METALUI_TRACE_RETAINED=1`): F2 `rects`, `interior`; F3 `offset` and `rects`, `interior`; F4's rows hit at paint but their
**prepaint** key differs from the record's in exactly one part, `PrepaintExtras.suppression` (the accessibility suppression exceptions),
every frame, with the ledger otherwise valid; that is why no row's prepaint replays and no row grafts. Bracket node drag, `.panels`, graft
on (record 121 section 3): 144 requests, 153 prepaints. Orbit with panels (record 121 section 7): 6 requests, 7 prepaints, 7 paints.

## FS-A - No implicit element or row scope: the retention unit stays an `.equatable()` `Component`

**Ruling.** A `ForEach` element and a `List` row do **not** become retention scopes by themselves, by element equality or by any other
rule. The unit is the existing `.equatable()` occurrence (`IV-B`), which F1 shows already isolates rows: one changed row of 24 is 1 miss
and 23 hits, 8 element requests with the graft (169 without), siblings' records and grafts untouched.
**Evidence.** F1. A row's picture is a function of its closure's captures (a model, a palette, `@Environment`), not of the element; the
closure cannot be compared, so "equal" can only mean a type the author declared equal. The ancestor rule `SB-AC` (a descendant whose content
ran kills its ancestors' records) concerns ancestors only; a sibling is not touched, which is why 23 rows hit.
**Alternatives rejected.** (1) Element-equality scopes (id plus the element's `Equatable`): replays a stale row whenever the closure
captured anything else; the contract buying paint replay is already "a function of the value" (`EquatableComponent` doc) and this one
cannot state it. (2) An `.equatableRows()` opt-in on `ForEach`/`List`: the same hole with one more spelling and a public declaration (an
inventory row, a divergence label, a SwiftUI probe) for a case F1 shows is covered. SwiftUI's own skip rule for a plain view struct is not
claimed here and was not probed. gpui's `AnyView::cached` is opt-in per entity (from memory, not run).
**Cost if wrong.** An author who wants rows retained writes `.equatable()` on a row component, as the bracket fixture does; nothing new to
learn, nothing to migrate. If an implicit rule is wanted later it is a new item with its own probe.

## FS-B - A "modifier-level scope" is not a separate mechanism

**Ruling.** No retention scope is placed at a modifier boundary. A modifier layer is re-run every frame (it is a cheap layer: one element
request) while the occurrence inside it replays; the two cases the item names are covered by what exists and by `FS-D`: a changing
`.offset` is translated replay (`RK-G`, `RK-S`, measured by `TranslatedReplayTests` and the bracket drag, unchanged by this item), a
changing layout modifier (`.padding`, `.frame`, a sibling above that resizes, a stack that gains a row) is the layout translation of `FS-D`.
**Evidence.** F1 and the bracket drag: the wrappers are the residue (144 requests of 798) and they are the dragged node's and the
panel's own elements; a scope with a value would need equality of the modifier's closures (a `.gesture`'s `onChanged`) which does not exist.
**Alternatives rejected.** A scope keyed by the modifier's declared value with the closure ignored: replays a stale closure
(`Handlers` outlive the frame, the retain-cycle rule). **Cost if wrong.** The wrapper requests stay; they are 10 to 20 percent of the
bracket drag's remaining requests and are named as the residue in the record.

## FS-C - The List gap is a prepaint-key defect, fixed first, in `List` and the key's `suppression` part

**Ruling.** Lane 1 finds why a `List` row's prepaint key differs frame to frame in `PrepaintExtras.suppression` (the exceptions of
`Frame.withAccessibilitySuppressed(except:)`, which `List.prepaint` opens around its rows while its window is unbounded, `AB-X`), and
fixes it so a row's key is equal when nothing moved, **without changing what accessibility records, hitboxes or the tree emit** (the
suppression decides whether a row may emit; an equal exception must compare equal). Both branches: `rowHeight:` and
`List(_:rowContent:)` (`VL-I`: each branch's pins and work literals stay unmoved except the lines this item is the point of, named in the
spec). `List`'s row closure stays `Row: Element`; a `Component` row is written inside a `Column`/`Box` (one more legacy element per row,
documented), no public change.
**Evidence.** F4: hits 9 at paint, 0 at prepaint, 0 grafts; trace parts `[rects, interior, nodeCount, ambient, scroller, scrollerID,
effects, share, hiddenNodes]` equal and `suppression` not. The cause inside `suppression` (an id that compares unequal, a flag, the
window's `windowIsBounded`) is **not yet known**: the design phase localised it, lane 1's first commit proves it, and the arms are
accessibility on and off (`collectsAccessibility`), because production has no client until VoiceOver asks and the probe's harness
state at the moment of the reading is not established.
**Alternatives rejected.** Dropping `suppression` from the key: a layer hidden by an ancestor changes what a ledger holds (`AB-O`), so it
is a real key part. **Cost if wrong.** If the cause is not in `suppression` alone, the lane reports it and rules the List half not
justified rather than widening the key.

## FS-D - Generalise translated replay from "render effect moved" to "the occurrence's origin or its scroll offset moved"

**Ruling.** `ReplayKey` and `PrepaintKey` split into a **shape** (the occurrence's top rects and its interior hash taken relative to its
first top node's origin, plus the node count) and an **origin** (that origin, device pixels). Today's `rects`/`interior` are absolute, so
any shift of the occurrence misses (F2). A new key relation `differsOnlyByTranslation` accepts two kinds, each independently:
**K1 layout origin**, shape equal and ambient equal, origin moved; **K2 scroll offset**, shape and origin equal, `AmbientKey.offset`
moved, the clip unmoved. It sits **beside** `differsOnlyByEffectTranslation` (render effects, `RK-G`) and composes with it (an occurrence
shifted by layout under a moved effect translates by the sum), reusing the one replay path (`replayPaint(_:translated:)`,
`translatedHitboxes(of:by:)`, the `translated` and `translationRefused` counters): extended, not forked. The relative interior hash is a
new `LayoutTree.subtreeSignature(of:relativeTo:)` in `MetalUILayout` (imports unchanged).
**Gate (refused and counted, never approximated).** The translation `delta` is applied by one add to recorded coordinates, so it equals a
fresh paint only when every participating number is exact in `Float`: the delta and the recorded origins are multiples of 1/16 and below
2^19, i.e. layout grids of scale 1, 2, 4 (and 8); scales 1.5 and 3 (thirds) **refuse**, by name, and miss as today. A primitive whose
content mask is neither the entry clip (left alone) nor wholly inside it before and after (translated) refuses. Recorded kinds are an
allow-list (rect, glyph run, image, path/gradient raster, shadow leaf); a surface, a backdrop and anything unlisted refuse by kind name.
**Evidence.** F2, F3: figure ceilings are F3's "nothing moving" row (3 / 4 / 4 against 171 / 172 / 244); `RK-S`'s own note that a
final-stream translation is inexact for fractions (`SB-H`) is why the gate exists; the PF design (`PF-A`: a whole-device-pixel move hands
back the same raster) already assumes whole-pixel moves are exact.
**Alternatives rejected.** (1) Record leaves in occurrence-local coordinates and replay inside a synthetic flattening effect scope, to
inherit `GX-X`'s clip handling: changes every record's arithmetic at record time, so the 0 px against `711ab9c4` is at risk on the whole
suite; kept as the fallback if the mask rule above proves too strict in the spike. (2) Re-running paint on a shifted occurrence and caching
rasters only: the shape of `PF`, already done; F2's paints are element walks, not rasters.
**Cost if wrong.** The relation is a key relaxation behind a gate: a wrong accept is a stale pixel, so every accept is checked by
`METALUI_VERIFY_RETAINED=1` (`SB-W`) over the whole suite and by the scale differential of the spec (test 2.5); a gate set too tight costs
only the win.

## FS-E - The translation lane has a spike with kill criteria

**Ruling.** Lane 2's first commit is a spike on the final-stream path: K1 and K2 for rect, glyph run and image at scales 1, 2 and 4,
bitwise equal to a fresh frame in the scale differential, with accessibility on and off. **If it cannot reach bitwise equality for those
kinds it lands nothing but the instrument and the pins of the refusal names, and the record says why** (the brief's "not justified"
rule). Shadow leaf, path and gradient rasters follow only if the spike's differential extends to them without a new rule.
**Cost if wrong.** A lane that ends as measurement and refusal pins; the figures F2/F3 stay the owner's.

## FS-F - What a translated prepaint replays, and what refuses

**Ruling.** A translated ledger moves its hitboxes' bounds (and the hit transform, as `RK-S` does), focus stops' and element bounds'
rects, press-only actions' and context-menu anchors' rects; the clip of a hitbox moves only when it was derived inside the occurrence
(the mask rule of `FS-D`). **Accessibility emissions and nodes refuse** (their frames are computed boxes, as in `RK-S`), as does any
channel the ledger holds that is not on that list, by name in `translationRefusedReasons` (one public `MetalUITesting` field, class M,
an inventory row and a doc comment, as `retainedIneligibleReasons` was: `RW-M`). The graft is unaffected by translation: a grafted
occurrence's rows come from its segment and are positioned by layout; its prepaint and paint decisions translate or the frame is redone.
**Cost if wrong.** An accessibility client sees the shifted rows build every frame (the cost of today); everything else is pinned equal to
a fresh window by the differential.

## FS-G - Placement of a shifted subtree is not made translation-aware here

**Ruling.** `SB-AD`'s placement memo keys origin in (`PlacementKey(signature, proposal, bounds)`), so a shifted subtree re-places. Lane 2
reports the layout counters (`layoutMemoRootHits/Misses`, `layoutSignatureNodes`) before and after; **if placement is then the dominant
remaining cost of F2/F3 it is carried as C14-e with those figures**, not widened into this item (the kernel is the `MUST NOT MOVE` list's
neighbour). **Cost if wrong.** Layout of shifted rows stays whole; it is measure-memoised (`IV-`) already.

## FS-H - C14-c4 is a dead conjunct, not a separable site

**Ruling.** The graft site's `environmentTop.uncomparableCustomCount == 0` (`RetainedGraft.swift`, `graftRecord`) cannot refuse alone: an
uncomparable custom reading is `.uncomparable`, which `EnvironmentReading.==` answers `false` against anything, itself included, so
`EnvironmentFingerprint.custom`, and with it `BuildKey.environment`, can never equal a recorded key that held one (`graft.key == key`, the
guard line above it), and the record and prepaint refusals dominate it besides. Lane 1 first applies the mutation (the conjunct replaced
by `true`) to the full unfiltered suite **and** `METALUI_VERIFY_RETAINED=1`; if nothing reddens, the conjunct is **removed** with a
comment naming `BuildKey` as the refusing site, and the pin is `aGraftIsRefusedUnderAnUncomparableKey` through the key: green on arrival
by construction, red under the mutation "`custom` dropped from `BuildKey.environment`" (which `EE-N`'s `retainedFingerprint` mutation does
not reach for the graft alone). If the mutation reddens something, that test is the separating case C14-c4 owed and the lane records it.
**Why not red on arrival.** A pin of behaviour that three conditions already guarantee passes at `711ab9c4`; a red-on-arrival version
would need the code to be wrong, and it is not. **Cost if wrong.** One extra guard conjunct left in place if the mutation finds a case.

## FS-I - Targets, and the figures the pins are written against

**Ruling.** Every pin counts work. Red on arrival at `711ab9c4` (written first, failing, then the lane that turns it green): lane 1's
`aStaticListOfEquatableRowsReplaysPrepaintAndGrafts` (F4: prepaint hits 0, grafts 0) on both branches; lane 2's F2, F3 and list-scroll
pins (hits 0). Green-on-arrival characterisations, named as such: F1 (`aChangedRowMissesAloneAndItsSiblingsReplayAndGraft`), the bracket
drag (144 / 153 stay, the `.value` 208 / 219), the orbit (6 / 7 / 7), `aGraftIsRefusedUnderAnUncomparableKey`. The figures to reach are the
implementer's to derive and write as literals before the fix (the F3 "nothing moving" row is the ceiling, not the target: the shifted row
that is new, and the dragged one, still miss). Release ms per frame is a dated measurement in the record (`zsh docs/probes/perf-baselines.sh`,
fixture `bracketorbit` plus a new `shiftscroll` arm), never a pin.
**Cost if wrong.** None beyond a re-derived literal.

## FS-J - Public API: one `MetalUITesting` field, nothing else

**Ruling.** No public type or modifier is added to `MetalUI`. `FrameWork.retainedTranslationRefusedReasons: [String: Int]` (`FS-F`) is the
one public declaration, class M. No divergence label from 555-564 is taken: replay is value-identical, and the SwiftUI claims the item
makes are none (`FS-A` makes no SwiftUI statement).
**Cost if wrong.** A second field would owe a second inventory row.

## FS-K - Carried, with reasons and owners

(1) An implicit `Equatable` auto-detection of plain components (`FS-A`): a new item with a probe. (2) `List`/`ForEach` rows as groups
without a `Column` wrapper (`FS-C`): a public generic change to `List.Row`; owner a SwiftUI-alignment item. (3) Placement-memo translation
(`FS-G`): C14-e, if the figures say so. (4) Divergence 255 / `FI-I` (list rows name by description): untouched, so the 100k re-take
(`METALUI_RUN_100K_LIST_TEST=1`) is **not** owed unless lane 1's fix touches row naming, which it must not. (5) Out-of-window rows
(`TB-AH`): untouched. (6) A translated replay of an occurrence holding a surface, a popover or an open presentation: refuses (`RW-L`).
(7) MetalCreator's own reading of the orbit and the graph panel: human check `FS1`, no agent touches it.

## FS-L - Lane split

**Ruling.** Two lanes, run one after the other on one branch (agents here run one at a time): **lane 1** owns `ListRows.swift`,
`List.swift`, `ForEach.swift`, `EquatableComponent.swift`, `RetainedGraft.swift` (the conjunct), the `suppression` source in `Frame.swift`
(`accessibilitySuppressionExceptions`, `PrepaintExtras.suppression` only) and `FinerScopesElementTests.swift`; **lane 2** owns
`RetainedSubtree.swift`, `RetainedPrepaint.swift`, `Frame.swift`'s `PrepaintExtras.translation` and `ledgerSnapshot`, `LayoutTree.swift`
(`subtreeSignature(of:relativeTo:)`), `FrameWork.swift`, the demo section and `FinerScopesTranslationTests.swift`. Lane 1 may edit
`RetainedPrepaint.swift` only in the commit that fixes `FS-C` if the cause is in a decision function, and lane 2 starts after that commit.
**Cost if wrong.** A merge conflict in `Frame.swift`, resolved by lane 2 (the later).

## FS-M - Critic: the translation gate also requires a whole-device-pixel delta (amends FS-D, FS-E)

**Defect found.** `FS-D`'s gate (recorded numbers and delta multiples of 1/16, below 2^19) makes the add exact in `Float` but not equal to a
fresh paint: a glyph run's subpixel bin (`GlyphImage.subpixelPlacement(forDeviceX:)`, `PT-C`), an image's resampling phase and a
`RasterAnchor` raster (`PF-A`: only a whole-device-pixel move hands back the same raster) are functions of the **fractional** device
position, so a fractional delta (e.g. 0.25 px) adds exactly and draws different pixels, and `METALUI_VERIFY_RETAINED` would trap on it late.
**Ruling.** A translation is accepted only if the delta is a **whole number of device pixels on both axes** (checked in device pixels after
the scale, so 4 pt at scale 1.5 = 6 px is accepted while a 1 pt shift at 1.5 refuses), **and** the recorded coordinates satisfy the 1/16 /
2^19 exactness test. A rect-only occurrence may be relaxed to the 1/16 rule only if the spike's differential shows equality; the default is
whole pixels for every kind. Refusal name `fractionalTranslation` (new reason beside `inexactTranslation`). Test 2.9 uses a 0.25 px shift
(scale 4, 1 pt) and a 1 pt shift at 1.5; 2.5 gains a whole-pixel arm at 1.5 (accepted when recorded origins are exact, else
`inexactTranslation`); mutation for 2.9: the whole-pixel test replaced by `true` must redden the glyph-run differential.
**Rejected.** Relying on the verify switch alone to catch it: it is a development switch, not a gate. **Cost if wrong.** Fewer accepts
(fractional layout shifts miss as today).

## FS-N - Lane 1 diagnosis: a stale prepaint ledger on a standing record, fixed by refreshing it (settles FS-C, FS-H)

**Cause (measured, 711ab9c4).** `PrepaintExtras.suppression` was never the defect; it is where a *stale* ledger showed. With an accessibility
client collecting, `List.prepaint` opens `withAccessibilitySuppressed(except: listID)` around its rows while its window is unbounded (the
first frame, `AB-X` rule 1), so an `.equatable()` row's first ledger is keyed `suppression == [listID]` (and holds no accessibility
records). Every later frame is bounded, its key reads `suppression == []`, and every other part of the key is equal (printed per part, both
branches). The prepaint then **runs** (a miss), makes a correct ledger for the new key, and `retainedPaintDecision` finds the paint record
still valid and hits: `finishRetainedPaint` is not reached, so the record keeps `old.prepaint` for ever. Prepaint never replays, and no graft
stands (`graftRecord` needs a replayable prepaint; a graft built on the old ledger whose key fails is the redo, which then suspends replay
window-wide for 9 builds and quarantines the entry for 9, `RK-D`: that is why the F4 probe's three measured frames, taken 4 frames after
the first, sat inside the backoff). With **no client** the exception never exists (`withAccessibilitySuppressed` is a no-op while not
collecting), the key never changes and the same list already replays and grafts (pin `aStaticListWithNoAccessibilityClientAlreadyReplays`,
green on arrival). Uniform and variable branches share the code, both red. Not a harness effect.
**Ruling.** `RetainedSubtree.refreshLedger(of:from:)`: on a paint **hit** whose prepaint ran this frame (`phase.ledger != nil`, nothing
replayed), the fresh ledger replaces the record's when its key differs and every entry it read is one the record already versions
(`ledger.reads` a subset of `record.versions`; otherwise the old one stays). The ledger is exact for the same, still valid occurrence, so
the replacement is sound; it needs no key widening and no counter. `suppression` stays a real key part (`FS-C`): the mutation that
removes it from the key reddens `aSuppressedFirstFrameLedgerReplaysTheSameTreeAsAFreshWindow` on the accessibility tree (a ledger made
while the rows were suppressed would replay with no rows).
**Figures** (per frame, 24 cards at scale 2, 16 warm frames, graft on, window 320 x 400 / scroller 300 x 150): uniform static
84 requests, 85 prepaints, 22 paints, prepaint hits 0, grafts 0 -> **21 requests (63 skipped), 22, 22, 9, 9**; variable static
-> 23 requests (70 skipped), 24, 24, 10 hits, 10 grafts; uniform with one row's value changing: 28 requests, 29 prepaints, 32 paints,
8 hits / 1 miss, 8 grafts (variable 30 / 31 / 34, 9 / 1, 9). Four warm frames, as the design probe used, sit inside the redo backoff
(9 builds) and read the old figures on the unfixed tree; the pins warm 16.
**Mutations.** Refresh body skipped (`return` first): `aStaticListOfEquatableRowsReplaysPrepaintAndGrafts` (both branches),
`aChangedListRowMissesAloneAndTheOthersGraft` (both) and `aSuppressedFirstFrameLedgerReplaysTheSameTreeAsAFreshWindow` (both) redden;
`suppression` dropped from `retainedPrepaintKey`: the last one reddens (accessibility tree). The `ledger.reads` subset guard is pinned by
`aFreshLedgerThatReadAnUnversionedEntryIsNotSwappedIn` (a row element whose prepaint reads, from the second frame, an entry a sibling
outside the list created in the first: the suppressed first ledger read nothing, the fresh one reads an entry the record does not
version). Mutation: the guard line deleted reddened that test alone (the five `AppKitPresentationTests` sheet issues of `CI-AF` on a
locked screen aside). A `TextField` row cannot reach the guard: its creating read taints the first frame, so no suppressed ledger exists.
**Characterisation status:** `aGraftIsRefusedUnderAnUncomparableKey` is green on arrival and reached by no window-level mutation (the paint refusal dominates); the graft-site half is pinned at `BuildKey` level only.
**C14-c4 (`FS-H`), measured.** The graft site's `uncomparableCustomCount == 0` conjunct replaced by `true`: the whole native unfiltered
run (3996 passed, `AppKitPresentationTests` skipped on a locked screen) and the same under `METALUI_VERIFY_RETAINED=1
METALUI_VERIFY_LAYOUT_MEMO=1` (3996 passed) reddened nothing. Removed, with a comment naming `BuildKey`. Pins: `aBuildKeyUnderAnUncomparableReadingEqualsNothing`
(`MetalUITests`, red when `custom` leaves `retainedFingerprint`: a rebuilt `BuildKey` unequal to itself; a key is not compared with itself,
a `Dictionary` sharing storage answers `==` by identity) and `aGraftIsRefusedUnderAnUncomparableKey` (window level, green by construction:
0 grafts, 1 ineligible, scene equal to a retention-off window; the paint refusal dominates, so no window mutation reaches it).
**Not done here.** No row-naming change (`FI-I`, divergence 255 untouched): the 100k re-take is not owed. Every existing `VL-`/`DD-`
test and literal is unedited. The lane-2 translation work (`FS-D`..`FS-G`) is not part of this commit series.

## FS-O - Lane 2 as built: translated replay for a layout shift (K1) and a scroll offset (K2), behind one switch

**Ruling.** The spike of `FS-E` succeeded and the translation lands. `ReplayKey` and `PrepaintKey` gain `shapeInterior`, the subtree's
signature taken relative to the first top node's origin (`LayoutTree.subtreeSignatures(of:relativeTo:)`, `package`, one walk for both
hashes; `subtreeSignature(of:relativeTo:)` is the single-hash spelling `FS-D` names). Their `==` is unchanged (all parts), so every
existing decision compares as before. `RetainedShape.shift` is the one relation: same node count, same relative signature, same top
rect **sizes**, same top origins relative to the first (all `Float` subtractions, equal or no translation), and the shift of the first
origin (K1) and of where it lands with the ambient offset (K2) not both zero. `ReplayKey.shift(from:)` adds "ambient equal but for
`offset`"; `PrepaintKey.shift(to:)` adds "extras equal but for the scroller's offset (index 7)". An occurrence under a **moved render
effect** is not combined with these (the effect branch of `RK-G` runs first and needs equal rects): the sum of the two is deferred.
**The move** (`Frame.movedPaintRecord`): the first top node's device origin is computed with `fill`'s own arithmetic
(`(x + offset) * scale`, `Float`), the delta is the difference of the new and the old, and the record's leaves at its own scope height
(`RetainedRecord.scene`, and its `finalScene` when no paint scope is open around the occurrence) are moved by one add of that delta
through `processScopes` (the translated path of `RK-S`: the live outer scopes still apply). Allow-list: **rect, glyph, image**. Each
other kind refuses by its name (`unlistedKind:path|gradient|surface|shadow|blur|backdrop`); a `CapturedPrimitive.transform`
refuses (`transformedPrimitive`); a record whose leaves passed a paint scope opened **inside** the occurrence (a flattening
`.offset`, a shadow, a composite, a transition) refuses (`innerScope`: `RetainLog.noteBoundary` marks the recorder when a leaf stands above
its own scope height), because the scope's map is not an add. **Masks:** a primitive whose mask was read at the entry clip depth (its
emission depth equals `ambient.depths[0]`) keeps it, equal by the key; one read deeper holds a clip derived inside the occurrence and moves
with it only when it lies **strictly inside** the entry clip before and after (a mask that touches an edge of the entry may have been cut
by it, and the cut of a moved mask is not the moved cut: `maskStraddlesEntryClip`).
**Gate (`FS-M`, as ruled, with one measured amendment).** The delta must be a whole number of device pixels on both axes
(`fractionalTranslation`), and the origins, the delta and every moved number a multiple of 1/16 below 2^19 and the add exact
(`inexactTranslation`). **Measured: scales 1.5 and 3 are not refused wholesale.** Layout rounds coordinates to whole points (and
halves), so `x * 1.5` and `x * 3` are multiples of 1/16 and a 4 point shift (6 or 12 pixels) translates at both; what refuses there is a
fraction (1 point at 1.5 is 1.5 pixels; a third of a point at 3 gives coordinates that are not multiples of 1/16). The scale differential
(test 2.5) is bit-identical to a retention-off window at 1, 1.5, 2, 3 and 4, with and without a client.
**Switch and rebase.** `ContentMemoStore.translatesLayout` (`METALUI_RETAINED_TRANSLATION=0`, `Window.testingRetainedTranslation`)
turns the lane off: the window then behaves as the lane-1 head (the A/B of the figures below, one binary). A successful translated hit
**rebases** the record (`key`, `scene`, `finalScene`) and the prepaint ledger (a new `PrepaintLedger` at the new key, hitboxes and element
bounds moved) at the new position, so the next frame at that position is an exact hit on the `finalScene` fast path instead of a second
move; verify mode (`METALUI_VERIFY_RETAINED=1`) keeps the old record and compares the fresh run with `RetainedRecord.moved(to:)`.
**Evidence.** `FinerScopesTranslationTests.swift`; the lane's red lines are in the commit `c4adb920` message.

## FS-P - What a translated prepaint moves, and the order of the two decisions

**Ruling.** `Frame.movedPrepaintLedger` moves the ledger's hitboxes (the element origin by the window-point shift, K1 plus K2) and its
element bounds (the layout shift alone: they are layout rects), and replays focus, tallies, live states and reads unchanged.
**A hitbox keeps its uncut rect** (`Hitbox.unclipped`, the rect translated by the active offset before the clip cut it, and
`Hitbox.clipDepth`, the clip depth the cut was read at; additive, read by nothing else): registered at the ambient depth, its moved `bounds` are
**recomputed** as `clip ∩ (rect + delta)`, the arithmetic of `insertHitbox`, so a row the scroller's edge cuts, or one wholly outside
the viewport (an empty cut), moves exactly; registered deeper (a clip pushed inside the occurrence by legacy `clipped(to:offsetBy:)`), it moves only when its bounds lie
strictly inside the ambient clip before and after, else `hitboxClipped`. (Measured: the proposal `.clipped()`/`.clipShape` register
their hitboxes at the ambient depth, so `hitboxClipped` has no construction in this suite: the guard is conservative and **unpinned**, its
mutation survives, `FS-T`.) **Refused by name:** `accessibilityRecords` (any emission or node: their frames are computed boxes), `pressOnly`,
`contextMenus`, `presentationAnchor`, and per hitbox `hitboxUnderEffect`, `hitboxShape`, `hitboxScrolls`, `hitboxHandlers` (a text input, a
value track, a drop destination or a contextual attachment, whose closures hold positions), `hitboxClipped`, `inexactTranslation`.
**The pointer is read against the moved hitboxes.** Hover resolves after prepaint, so the decision tests the pointer against the hitboxes
where they will stand (`mousePosition` inside one: run the prepaint); testing the old rects let a card scroll under a resting pointer, replay its
prepaint, and meet the paint's pointer rule: a redo (found by `aHitboxTheScrollersClipCutIsRecomputedAtItsNewPlace`, red under the mutation).
**The paint record must be able to follow before a prepaint is replayed.** A replayed prepaint leaves no element state, so a paint that
then misses is the redo (`RK-D`). The prepaint decision therefore asks, from the geometric part of the paint key, whether the record
stands elsewhere and can be moved (`Frame.paintTranslation`, memoised in the phase and counted once), and **runs the prepaint** when it
cannot; a refusal at either decision goes through `RetainedCounters.noteTranslationRefused(reason:)` into
`FrameWork.retainedTranslationRefusedReasons`.
**Known cost, unchanged in kind.** An occurrence that is grafted (`RK-B`) and whose translated prepaint is refused is the counted redo, as
a refused effect translation was; with a client active every translated prepaint meets `accessibilityRecords`, so the graft and a shift
cost one redo per backoff window (the paint still translates: 171 requests and 4 paints, against 244).

## FS-Q - Figures (work counts per frame: element requests / prepaints / paints; scale 2, 24 `FSCard` rows, three frames after 16 warm ones)

Taken in one binary with `testingRetainedTranslation` off (the lane-1 head) and on; AX off unless named; `skip` is `retainedSkippedRequests`.

| scenario | off (lane-1 head) | on, graft off | on, graft on |
|---|---|---|---|
| header +4 (K1) | 171 / 172 / 244, hits 0 | 171 / 4 / 4, hits 24, translated 24 | 3 (168 skip) / 4 / 4, 24 grafts |
| id inserted first (K1 + 1 new row) | 176, 183, 190 / 177, 184, 191 / 251, 261, 271, hits 0 | same requests / 9 / 11, hits 24-26 | 8 (168-182 skip) / 9 / 11, 24-26 grafts |
| wheel -30 over a `ScrollView` (K2) | 171 / 172 / 244, hits 0 | 171 / 4 / 4, translated 24 on the moving frame, 0 on the settle frame (exact hit) | 3 / 4 / 4 |
| wheel -30 over a `List`, uniform (9 to 11 rows) | 102-111 / 103-112 / 116-148, hits 0-2 | not measured | 32-41 (63-77 skip) / 33-42 / 36-50, 9-11 translated and grafted |
| wheel -30 over a `List`, variable | 111 / 112 / 128-148 | not measured | 34-43 / 35-44 / 38-50 |
| AX on, header, graft off | 171 / 172 / 244 | 171 / 172 / 4, refused `accessibilityRecords` 24 | one redo, then as left |

Unmoved (existing pins, unedited): the bracket node drag 144 / 153 and 208 / 219, the orbit 6 / 7 / 7, the fourteen images (0 px against
`711ab9c4`). Release ms per frame is `zsh docs/probes/perf-baselines.sh release shiftscroll`, a dated measurement, in the record.

## FS-R - Existing pins this item moves

`everyKeyComponentSeparates` arms `topRect` and `flexRect` (`RetainedSubtreeSemanticsTests.swift`): the neighbour of a padding or of a resized
sibling moved without changing, and read as the arm's "reaction" (a miss); it now replays translated, so the two arms read
`translated` (2 and 1) and no miss. The key components they separated (a changed **size**, a changed interior) keep their separating arm in
`aShiftThatAlsoResizesTheOccurrenceMisses` and the rest of the table. No other existing test or literal moved.

## FS-S - Carried from lane 2

(1) A translated prepaint of a row at a scroller's edge that holds a hitbox (`hitboxClipped`): the hitbox would have to remember its
unclipped rect and the clip depth it was cut at (two fields on `Hitbox`); owner C14-e with the placement memo. (2) Combining a layout shift with a
moved render effect (`RK-S` plus `FS-D`). (3) Path, gradient and shadow rasters as translated leaves (their keys are anchored,
`PF-A`, so a whole-pixel move should hand back the same raster; the spike did not need them). (4) Placement-memo translation (`FS-G`): after the
move the layout counters of the shifted frames read `layoutMemoMisses` 23 to 175 (the signature includes origin), the dominant remaining cost
of a shifted frame once requests are 8 and paints 11. (5) Avoiding the one redo of a graft with a client active. (6) Human checks `FS3`, `FS4`.

## FS-T - Lane 2 mutations, and the three that survive

Applied one at a time to the committed tree (restored from git, `git status --short` clean after each), the retained-related set
(`MetalUITestingTests` plus every test whose name holds Retained, Graft, Prepaint, Translat or Ledger: 447 tests; `AppKitPresentationTests` skipped,
the screen was locked) run after each build. Reddened, by test name (counts are issues):

* **K1 off** (an offset-only movement is the only translation): `aShiftedOrScrolledRowReplaysTranslated` 28, `aShiftedCardStackEqualsAFreshWindow` 12,
  `everyUntranslatableKindRefusesByName` 5, `aClickAfterAShiftReachesTheMovedButton` 4, `everyKeyComponentSeparates` 2, `aFractionalShiftIsRefusedNotApproximated` 2,
  `anInexactCoordinateIsRefusedNotApproximated` 1. **K2 off**: `aShiftedOrScrolledRowReplaysTranslated` 26, `aShiftedCardStackEqualsAFreshWindow` 6,
  `aScrolledListReplaysTheRowsStillInTheWindow` 4, `everyUntranslatableKindRefusesByName` 1.
* **The add applied to y twice**: `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale` 120, `aShiftedCardStackEqualsAFreshWindow` 66, the graft sweep
  pins (`aGraftedFrameKeepsTheStateTableSweepsExact` 18, `aRedoAfterAGraftMismatchRestoresEverything` 10, `aLoopInsideAGraftedOccurrenceStillResetsTheRowsItLoses`,
  `aConditionalInsideAGraftedOccurrenceStillResetsItsState`, `lifecycleAnimationAndListInsideAMemoizedComponent`), `aScrolledList...` 12, `aClickAfterAShift...` 12.
* **Exactness test replaced by `true`**: `anInexactCoordinateIsRefusedNotApproximated` (the refusal name; the pixels still equal, since Float add of the
  whole delta happened to be exact there). **Whole-pixel test removed**: `aFractionalShiftIsRefusedNotApproximated` 5.
* **Inner masks left unmoved**: `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale` 160, `aListRowReplayEqualsAFreshWindowWithAccessibilityOnAndOff` 44,
  `everyUntranslatableKindRefusesByName` 4, `everyKeyComponentSeparates` 4. **Strict-inside test removed**: the same, 160 / 36 / 4 / 2.
* **Hitboxes replayed unmoved**: `aClickAfterAShiftReachesTheMovedButton` 12, `aHitboxTheScrollersClipCutIsRecomputedAtItsNewPlace` 5. **Element bounds
  unmoved**: `aShiftedCardStackEqualsAFreshWindow` 24, `aClickAfterAShift...` 16, `aFractionalShift...` 3. **Element bounds moved by the scroll offset too**:
  `aShiftedCardStackEqualsAFreshWindow` 9, `aScrolledList...` 6. **The cut recomputed by a shift of the cut rect**: `aHitboxTheScrollersClipCutIsRecomputedAtItsNewPlace` 5.
  **The pointer read against the old hitboxes**: the same test, 2 (redos).
* **Allow-list widened (path, gradient, shadow)**: `everyUntranslatableKindRefusesByName` 10. **Inner-scope refusal removed**: the same, 2. **Accessibility refusal
  removed**: `aShiftedCardStackEqualsAFreshWindow` 33, `aScrolledList...` 6, `aTranslatedLayout...` 5, `everyUntranslatable...` 4, `everyKeyComponentSeparates` 2, two graft pins.
* **Paint rebase removed**: `aShiftedOrScrolledRowReplaysTranslated` 2 (the settle frame translates again). **Ledger rebase removed**: `aFrameAfterAShiftReplaysAnExactLedgerNotAMovedOne` 1.
  **The record-follows precheck removed**: `everyUntranslatableKindRefusesByName` 4 (the redo), `anInexactCoordinate...` 1, `aFractionalShift...` 1.
  **The switch left out of the paint decision**: `theSwitchOffMissesEveryShiftedRowAndOnTranslatesThem` 12.

**Survivors.** (1) Each of the two explicit shape guards alone (the top rects' sizes, the relative subtree signature) is an **equivalent mutant**: the
signature hashes every node's size, tops included, so the explicit size test is an early-out and the signature a complete test; removed **together** the old width's
pixels replay and `aShiftThatAlsoResizesTheOccurrenceMisses` reddens (3 issues). (2) `hitboxClipped` (FS-P): no tree in this suite registers a
hitbox below the ambient clip depth, so the guard has no pin; it stays as the conservative answer for a legacy `clipped(to:offsetBy:)` inside an occurrence.

The 100k list test (`METALUI_RUN_100K_LIST_TEST=1`) is not owed: row naming is untouched.
