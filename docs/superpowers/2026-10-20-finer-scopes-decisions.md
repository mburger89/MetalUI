# Finer retention scopes - decisions

Rulings for item C14-d (per-row `List`, per-element `ForEach` and modifier-level retention scopes) and C14-c4 (the graft site's custom-key
test). Spec: [`specs/2026-10-20-finer-scopes-design.md`](specs/2026-10-20-finer-scopes-design.md). Record: `../record/126-finer-scopes.md`
(Record phase, not yet written). Branch `perf/finer-scopes` from `711ab9c4`. Reserved divergence labels 555-564: none taken (the design
adds no public API and no SwiftUI-visible difference). Probe and instrument: `../probes/finer-scopes/`.

Prefix **`FS-`**, lettered. **Next unused: `FS-M`.** (Moves in the commit that appends a ruling.)

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
