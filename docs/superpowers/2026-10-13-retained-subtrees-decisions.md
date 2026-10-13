# Retained subtrees — decisions

Rulings for item C14b of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**), the second half of C14 (record §104, `IV-A`…`IV-Q`). Prefix `SB-`. **Next unused: `SB-Q`.**
Spec: [`specs/2026-10-13-retained-subtrees-design.md`](specs/2026-10-13-retained-subtrees-design.md);
fixture: [`specs/2026-10-13-retained-subtrees-fixture.md`](specs/2026-10-13-retained-subtrees-fixture.md).
Record: `../record/109-retained-subtrees.md` (Record phase). Branch `perf/retained-subtrees` from
`e85cb07a`. Divergence labels reserved 395–404: **none taken** (the item has no public API and no
SwiftUI-visible behaviour; `SB-B`).

Sources of truth. SwiftUI: nothing in this item is a SwiftUI-facing claim. SwiftUI skips a view whose
inputs are equal (record §104 §2, `docs/probes/swiftui-incremental-invalidation.swift`, arms S, U, V,
ES, `IV-L`), which is what `.equatable()` already does; how SwiftUI stores or replays what it
rendered is not observable from outside the framework and is not claimed. gpui, where SwiftUI has none:
gpui's cached views reuse a view's previous prepaint and paint ranges when its bounds, content
mask and text style are unchanged and the view was not notified (`Window::reuse_prepaint`,
`reuse_paint`, `AnyView::cached`) — **recalled from memory; the gpui source is not on this machine and
was not read here**, so it is a design precedent for `SB-D`/`SB-F`, not a cited fact. MetalUI's own
numbers: `Tests/MetalUITestingTests/BracketFixture.swift`,
`RetainedSubtreesBaselineTests.swift`, `docs/probes/retained-subtrees/`.

## SB-A — Measure first: in the bracket window prepaint plus paint (44 %) and build plus layout (52 %) are the two halves

**Question.** Where does a node drag's frame go in MetalCreator's window, and does record §104's
"build is 51 %" hold for it?

**Evidence.** The fixture (spec §1) at `e85cb07a`, `.value` arm, ms per frame. **Release** (30 reps x
22, three runs, shared Mac): build 1.99 (33 %), layout kernel 1.15 (19 %), prepaint 0.75 (12 %),
**paint 1.92 (32 %)**, sweeps 0.18 (3 %), render 6.00, `tick` 7.15. Debug (15 x 22): build 9.96
(18 %), layout 5.98 (11 %), prepaint 5.06 (9 %), paint 33.73 (61 %), render 55.56. Counts per drag
frame: 3 equatable occurrences evaluate (the dragged node, two wires), 29 are skipped
(`contentSkips`), 182 rects / 550 glyphs / 6 images are drawn, 2 wires are rasterized on the CPU
(78 312 px). Slice 1's 51 % was a tree of 81 bare `Text`s.

**Ruling.** Both halves are real, so both lanes are justified; the first lane attacks **prepaint and
paint** because it is the safe half (`SB-C`), the second the build and the layout kernel
(`SB-N`, `SB-O`). Shares are the instrument, never a pin (pins count work).

**Cost if wrong.** If the release reading were to invert on MetalCreator's real nodes (heavier
paint), lane 1's share only grows; if it were to shrink paint, lane 2's gate opens earlier.

## SB-B — The unit is an `.equatable()` occurrence; `IV-H`'s finer scopes and "any Component" are refused

**Question.** What is a retained subtree, and what makes the framework allowed to replay it?

**Evidence.** Replay trusts that nothing the subtree reads changed. The only equality the framework
has is the author's `==` on a `Component` (`IV-B`); `IV-K` refused automatic reflective skipping
because a `==` the author did not write is not vouched for. `IV-H` ruled "an unchanged `Component`";
the memo entry (`ContentMemoStore.Key`: identity plus type) already carries exactly the lifetime, sweep
and observation machinery a record needs.

**Ruling.** One record per `EquatableComponent` occurrence, hung off its memo entry. No new public
API, no `.retained()` modifier, no opt-out beyond a package test switch
(`Window.testingRetainedSubtrees`) and `METALUI_VERIFY_RETAINED`. `equatable()`'s doc comment is
extended with what is now saved and the author's contract (spec §6 item 2). Refused: a record per
bare `Component` (no equality), per modifier layer or `ForEach` element (C14-d), a user-facing
`.drawingGroup`-like retention (a different feature: it would cache pixels).

**Cost if wrong.** An author who writes a `==` that ignores an input the subtree *paints* now gets a
stale picture where before they got a stale getter only. The contract sentence is the mitigation; the
verify mode (`SB-M`) is how a suspect component is diagnosed; the cost is bounded by `.equatable()`
being opt-in.

## SB-C — Lane 1 replays prepaint and paint with the build running; the build skip is lane 2, gated

**Question.** `IV-H` ruled build skip, prepaint and paint as one design. Should the first lane be
that?

**Evidence.** Three facts from the source. (1) Prepaint and paint read the elements' layout records,
which hold `LayoutNodeID`s of **this frame's** tree (`Frame` allocates a tree per frame, C-3). A
subtree whose build is skipped has no element records and so *must* replay both later phases; a
failed key after layout then has nothing to run, and the only recovery is to redo the frame
(spec §9). (2) With the build running, a failed key is free: the records exist and prepaint and
paint run as today. (3) The measurement (`SB-A`): prepaint plus paint are 44 % of the release
render (70 % debug), build 33 % (18 % debug): the safe half is also the larger one.

**Ruling.** Lane 1 = replay of prepaint and paint, build running, **zero redo paths**. Lane 2 =
graft of layout segments, `StateTable` journal, frame redo with backoff, subtree placement memo
(`SB-N`, `SB-O`), started only if lane 1's release reading leaves build plus layout kernel at
or above 35 % of render on the `.panels` arm. The 35 % is the share at which skipping the
remainder of an unchanged window's build is worth a second `Frame` on the (rare) miss; below it
the redo risk is not paid for. The gate is a number fixed before the reading; the baseline
already reads 52 % (build 33 % + layout kernel 19 %, release), and lane 1 only shrinks the rest, so
it is expected to open.

**Cost if wrong.** If lane 2 never opens, the build recursion of every unchanged subtree is still paid
(33 % of a release render here). If it opens and its redo proves frequent, the backoff caps the damage at the
pre-lane-2 cost plus one wasted prefix per eight frames per subtree.

## SB-D — Recording brackets the subtree; the scene is captured at one funnel; observation is three windows

**Question.** How are the products captured without a hook at each of `Frame`'s ~100 mutation sites?

**Evidence.** `Frame.registerHandlers` is the one funnel for hitboxes, focus stops and accessibility
(Frame.swift ~1420–1800); its other products are append-only arrays and counters. The scene is not
sliceable by index: a primitive made inside an open paint scope is captured into the scope's leaf
group (`insertThroughScopes`) and reaches the scene later as a raster. There are 14 direct
`scene.insert` sites. Slice 1's probe (`swift-observation-nested-scopes.swift`, arms N, M, T, U):
nested `withObservationTracking` merges its access list upward, and a per-scope token gives one live
session.

**Ruling.** (1) Channels that are append-only arrays or counters are **bracketed** by a
`LedgerSnapshot` before and after each phase and the difference is the product; a channel outside the
replayable set that moved makes the record ineligible. (2) The scene is captured by routing the 14
sites through `Frame.emit(_:)` (behaviour-preserving, 0 px) and recording the calls made at the
paint-scope height the subtree started at; replay calls the same funnel, so an outer
shadow/blur/composite scope captures a replayed primitive as it captures a fresh one. (3) The stores
journal their own touches (`RasterCache`, `AnimationStore`, `StateTable.mark`) while a recorder is
open. (4) **Observation is three sessions per recorded occurrence**, over `finishComponent` (the
build recursion, so a descendant getter's read counts), prepaint and paint, each serial-checked as
`IV-L` item 5; they are separate from slice 1's getter session, so a child's observed change
re-evaluates the child and invalidates the parent's *record*, not the parent's *getter memo*.
Refused: wrapping `Frame` in a recording proxy (100 sites, every new channel a silent hole);
recording at the `Scene` array (not sliceable); one session spanning the three windows (not
nestable).

**Cost if wrong.** A channel the table misclassifies as replayable and that has a side the bracket
does not see is a stale or missing product: the classification guard (`SB-E`), the differential and
the verify mode (`SB-M`) are the three instruments; the guard catches an *unclassified* channel, the
other two a *misclassified* one. Three sessions cost three `withObservationTracking` calls per
recorded (miss) occurrence; measured in release at the close-out.

## SB-E — The ledger: every stored channel of `Frame`, `StateTable` and `AnimationStore` is classified

**Question.** `IV-H` item 3 asked for an eligibility gate by ledger and a Mirror guard. What are the
classes?

**Ruling.** Five: **recorded** (replayed), **keyed** (in the replay key), **ledger** (a change makes
the record ineligible), **frame-local** (untouched by prepaint and paint or constant per frame),
**build-only** (written in the layout phase, which runs in lane 1). Spec §5 lists the members. A
`Mirror` guard (`everyFrameChannelIsClassified`) reflects the three types, private properties included
(`Mirror` sees stored properties regardless of access), and fails on any property absent from the
table, as `theSevenRetentionSlotsAreMutuallyDistinct` fails on an eighth slot. **Adding a stored
property to `Frame`, `StateTable` or `AnimationStore` now owes a row.** CLAUDE.md gains one sentence in the
Record phase.

**Cost if wrong.** A property classified frame-local that prepaint does write is a stale product the
differential would have to find; the guard cannot see a *wrong* class, only a missing one. The
table rows carry the line of the site that justifies them.

## SB-F — The replay key: geometry, ambient context, and the pointer/press/focus rule

**Question.** What must be equal for a record to be replayed?

**Evidence.** The scene primitives carry their context baked in (`Frame.fill`: translated bounds,
`activeClip`, radii, `activeOpacity`, scale, `activeLayer`); hitboxes are stored translated and
intersected with the active clip (`insertHitbox`). Hover is resolved after prepaint, before paint
(`Frame.renderOutsideDispatch`), and reaches a subtree's paint only through hitboxes the subtree
owns (`isHovered(_:)` by element id).

**Ruling.** (1) Geometry: the absolute rect of each top-level node and the node count, bit-equal.
(2) Ambient context: spec §4.2's list, as one `Equatable` struct. (3) **A descendant rect hash** is
included at first and kept only if the verify mode ever separates a case where it matters; the
structural argument (the interior is a function of the final rect and the unchanged structure) says it
never does, and the instrument is how that is checked rather than assumed. (4) **Pointer, press and
focus**: the key holds three booleans over the subtree's *owned* hitboxes and stops, false now and at
recording, so a subtree the pointer entered or left re-paints once; a node without hitboxes (the
fixture's labels) is never affected, so overlapping neighbours of a dragged node still hit.
Refused: a conservative "pointer inside the node's rect" (the fixture's nodes overlap by 128 pt,
so five neighbours of every dragged node would miss every frame).

**Cost if wrong.** A missing key component is a stale picture in exactly the scenario it names;
test 1.3 has one separating arm per component and the differential runs a script that moves every
one. A component that is in the key and need not be costs a miss, never a wrong frame.

## SB-G — The environment: a fingerprint of the built-in fields; a custom key is a refusal

**Question.** A subtree's build reads `frame.environmentTop`; the content memo refused
`@Environment` readers (`IV-D`, divergence 346). What does replay need?

**Evidence.** `EnvironmentValues` is not `Equatable`; its writes are closures
(`EnvironmentWrite.transform`); custom keys hold `Any`. Prepaint and paint read the built-in fields
(font, foreground, scheme, theme, `isEnabled`, `displayScale`, …) through the frame.

**Ruling.** The key holds an `Equatable` **fingerprint** of the built-in fields (enumerated; a guard
fails when `EnvironmentValues` gains a stored property that is neither in it nor declared
irrelevant) and `customKeyCount`. A non-zero count anywhere on the occurrence's path makes it
**ineligible and counted** (a refusal like divergence 346's, with the same remedy: pass the value as
an input). C14-c (an environment epoch, carried from slice 1) owns lifting it. No divergence is taken:
the refusal costs a miss, never a wrong frame, and SwiftUI has no equivalent to differ from.

**Cost if wrong.** An app whose root sets a custom key (MetalCreator's `ThemeStore`) gets no
replay under it until it passes the palette as a value, which is the fixture's `.value` arm and
slice 1's advice; the `.environment` arm measures the refusal.

## SB-H — Translated replay is carried: float association

**Question.** A node moved by an `.offset` outside an `.equatable()` view changes the context and
misses. Could replay translate the recorded primitives instead (the case `IV-H` item 4 keyed away)?

**Evidence.** The fresh arithmetic is `translated = p + offset` then `device = translated · scale`
(`Frame.fill`). A recorded value is `(p + o₁) · s`; replaying at a delta `d` computes
`(p + o₁) · s + d · s`, which is not `(p + (o₁ + d)) · s` in general. Emulated in IEEE binary32
(Python `struct` round trips, the Swift operations are binary32 with the same order): layout
coordinates at scale 2 (multiples of 0.5), 0 of 100 000 differ; at scale 3 (`i/3`), `(p+o)+d` vs
`p+(o+d)` differ in 2 of 2999 and the device-space form in 31 of 2999. So exactness holds at dyadic
scales and fails at others, and 1.5x and 3x displays exist.

**Ruling.** Not in this item. Translated replay needs either dyadic-scale gating plus the verify
mode's reading, or recording the pre-translation values and re-applying the context (a bigger
funnel). The dragged node is not a case for it in the fixture (its `==` is false because its data
carries the position). Owner C14b-2, with the redo path of lane 2.

**Cost if wrong.** A drag of a node whose value does not carry its position pays the node's full
prepaint and paint every frame, as today; its neighbours still hit.

## SB-I — Rasters, the atlas, surfaces, backdrops

**Question.** What do cache touches, the glyph atlas, GPU surfaces and backdrops need?

**Evidence.** `RasterCache.endFrame` drops every raster the frame did not draw (`GX-K`); the atlas
is grow-only (`Atlas.swift`: `evictUnusedSince` has no caller, record §69 CLAUDE.md text, grepped
here); a surface leaf appends a `surfaceRequests` entry every painted frame (`Frame.swift:2906`); a
backdrop is one primitive blurred by the renderer from what is behind it (`BB-A`).

**Ruling.** Raster keys touched in paint are journalled and re-touched on replay (same
`ImageTexture` identity, 0 new textures, 0 rasterized pixels for a replayed path). Atlas slots in
recorded glyphs stay valid because nothing evicts; **a test greps `Sources/` for an
`evictUnusedSince(` caller and fails when one appears** (`theGlyphAtlasHasNoEvictionCaller`),
so the day eviction gets a caller replay owes the stamps. A surface leaf in a subtree makes it
ineligible (a draw is a per-frame request, not a primitive; the fixture's viewport is a sibling). A
backdrop is an ordinary operation; its degrade rule reads the open paint scopes, which are keyed.

**Cost if wrong.** A raster touched but not journalled is redone and re-uploaded one frame later:
test 1.13 reads `newTextures` and `rasterizedPixels` on the frame after a hit.

## SB-J — What lane 1 declares ineligible, and why each is carried and not hard

**Ruling.** A recorded occurrence that, in prepaint or paint, registers a scroll region, a
popover, a tooltip, a drag source, a presentation record, a toolbar record, a surface request, a
geometry-change note or a context it cannot key (a custom environment key, an unkeyable open paint
scope), reads `timestamp`, reads a `StateTable` entry outside its own bound set, writes the table
(`withState`), raises `hasActiveAnimations` or `wantsAnotherFrame`, or runs while
`collectsAccessibility` differs from the recording, is **ineligible**: it runs as today, is counted
(`retainedIneligible`) and is re-tried on the next frame. `List`/`ScrollView` are the large member
(scroll offsets are `StateTable` state read in paint and windowing reads the measured origin,
`DD-F`): C14b-3 owns them with the argument that a scroll offset is a bound state the record's version
journal already covers, plus `DD-F`'s origin. Each member has one separating arm in test 1.5.

**Cost if wrong.** An over-broad ineligible rule costs hits (the fixture's graph panel, with its
`List`, is a miss and its three children still hit); an under-broad one is a stale product the
differential and verify mode exist to find.

## SB-K — State, observation and descendants: the record depends on everything built under it

**Question.** Slice 1's content memo skipped only the getter, so a descendant's state or observed read
was re-evaluated by the build. What changes when prepaint and paint of the descendants are replayed?

**Evidence.** In lane 1 the build recursion runs on the pristine content, so a stateful
**non-equatable** child gets its new `@State` and getter value this frame, and its new elements'
prepaint and paint would be skipped in favour of the old record: a counter button inside an equatable
parent would show its old colour.

**Ruling.** The record's validity includes the **versions of every `@State` slot bound under the
component during the recording build** (the bind journal; one `entryVersion` read per slot per
hit) and the render session over the build recursion (`SB-D`). Test 1.6 is this case; its
mutation (skip the version compare) must show the stale colour. `@FocusState` and `@Environment`
components remain refused (`IV-D`).

**Cost if wrong.** This is the dangerous case of the item; it is the first differential arm and the
first mutation.

## SB-L — The stack budget and `Decoration`: nothing inline grows

**Ruling.** The record, the journals and the recorder are classes hung off the memo entry;
`ComponentPrepaint` is already a heap box and its payload becomes optional; `Decoration`,
`DecorationExtras` and `Handlers` get no field (their `MemoryLayout` pins stay); the decision in
`EquatableComponent.prepaintGroup` holds no large local. The demo section is in its own function.
`everyProductionTreeBuildsOnAOneMegabyteThread` and `DemoStackBudgetTests` run unfiltered at the
close-out; a debug stack sample (`StackMeter`) of the fixture before and after is recorded.

**Cost if wrong.** A Windows 1 MB overflow shows only in the Linux image or CI
(`CI-AI`); the image run is part of the close-out.

## SB-M — Verification: a verify mode and a differential, because counts do not prove output

**Ruling.** As `IV-J`: (1) `METALUI_VERIFY_RETAINED=1` (read once) replays and also runs the fresh
prepaint and paint into a scratch, then `precondition`s equal products (bounds, ids, layer, opacity,
text, scene operations including texture identity); (2) a differential on two windows (retention on
and off) over a script that moves every key component, after every frame comparing scene arrays,
hitboxes, accessibility tree and focus order; (3) the whole suite once under the verify variable;
(4) the fourteen images 0 px against `e85cb07a` and `Expected.swift` unedited. A mutation that leaves
the differential green is a finding about the instrument, to be reported.

**Cost if wrong.** The instruments are the cost; the verify run adds a fresh paint per hit, so it is
slower than the suite by the amount of retained work and is run once, not in CI.

## SB-N — Lane 2 (the build skip): a graft, a journal, a counted redo

**Question.** `IV-H` ruled a persistent append-only tree with epochs. Is that still the design?

**Evidence.** `LayoutTree` is structure-of-arrays with per-index side tables, reset per frame; a
component's nodes are one contiguous index range (`finishComponent` is post-order inside the
component, parents wrap after it returns); every id carries the tree's generation (C-3), so reuse of
ids across frames needs either a persistent tree (every consumer that stashes ids is affected) or a
copy.

**Ruling.** A **graft** (copy the rows of the recorded index range into the new tree under the
current generation, O(subtree), no element work) replaces the persistent tree; `IV-H` item 1 is kept
as the fallback if grafting proves slower than the build it replaces. A miss known only after layout
**redoes the frame** with the missing entries disabled (counted, backed off, spec §9 item 2). The
`StateTable` frame-set deltas are journalled and re-applied through the table's own funnels so
`sweep()` is unchanged. Gated by `SB-C`'s 35 %. Written here so the gate is a measurement and not a
design session.

**Cost if wrong.** A graft slower than the build (side-table dictionary inserts per node) would show
in the first release reading of lane 2's own step 1; the lane stops there and records it.

## SB-O — The subtree placement memo rides with lane 2

**Ruling.** Record §104's carried item (a moved subtree's rects need the same arithmetic as a fresh
placement) is the recorded segment's relative rects, placed by translation when the root proposal
and bounds are bit-equal. On the fixture the root placement memo never hits
(`layoutMemoRootHits: 0`: the wires' frames change size), so the remainder is what layout can save.
Lane 1 does not build it: layout is 11 % of the debug render, and the release reading decides.

**Cost if wrong.** Layout stays at its slice-1 cost for any frame whose signature changes.

## SB-P — GT-F: `drawText` stays deferred

**Question.** Record §99 owes C14's close-out: `MetalDrawContext.drawText` and its SDL twin.

**Evidence.** `theOverlayCostIsLinearAndCounted` passes unchanged at `e85cb07a` (run in the design
phase: N = 20 and 100, layout 0, one seam measure and one `placeGlyphs` per label per frame).
What lane 1 removes is the prepaint and paint of an unchanged equatable subtree; a **moving** label
changes `activeOffset`, which is in the key (`SB-F`), so it misses (translated replay, `SB-H`).

**Ruling.** Stays deferred. Lane 1 adds the pair `aStaticLabelOverlayReplaysAndAMovingOneDoesNot` so
the boundary is a measured fact: static labels cost 0 `placeGlyphs` after the first frame, moving
labels the unchanged 1 each. Re-taken at C14b-2 (translated replay), which is where moving labels
could become hits.

**Cost if wrong.** An app drawing thousands of world-anchored labels pays the build, one measure
and one `placeGlyphs` per label per frame (spec §11, `IV-O`'s table).
