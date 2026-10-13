# Retained subtrees — decisions

Rulings for item C14b of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**), the second half of C14 (record §104, `IV-A`…`IV-Q`). Prefix `SB-`. **Next unused: `SB-AF`.**
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

## SB-Q — A print is not a pin: the baseline tests become literals in lane 1's step 1

**Question.** The design phase committed `theBracketNodeDragRebuildsTheWholeWindow` and
`bracketDebugLocations`, which only print. Do they satisfy "red-on-arrival pins"?

**Ruling.** No. A test that asserts nothing cannot be red (`verifying-tests-can-fail.md`). Step 1 of lane 1
turns the spec §1 table into `#expect` literals (evaluations, skips, refusals, scene counts, pixels,
text-system calls), deletes `bracketDebugLocations`, and mutates one literal red per arm. The
conservation identity is `hits + misses + ineligible == contentEvaluations + contentSkips`; a refused
occurrence (`contentRefusals`) has no memo entry, so no record (the earlier draft subtracted refusals,
which is wrong: they are not in the other two counters). Rejected: keeping the prints as the record.

**Cost if wrong.** A fixture that drifts silently; the literals fail on any change to it.

## SB-R — Lane 2's redo is window-wide with backoff, and its tests are specified before it starts

**Question.** A graft happens before geometry is known, so a changed geometry key is found only after
layout. Per-entry redo (`SB-N`) would redo the frame on every window resize or scheme-driven re-layout.

**Ruling.** One redo disables grafting window-wide for 8 frames; ambient key parts are checked before the
graft. Lane 2's tests are written with red-before and mutation in a table before any code, as lane 1's are
(spec §9 item 5 was "named, not specified"). Rejected: per-entry backoff alone (N entries can each
redo once, N frames of doubled cost).

**Cost if wrong.** A resize drag pays one redo then plain builds for 8 frames; no worse than lane 1.

## SB-S — Corrections to the design from the build: a time read is not a channel

**Question.** Spec §5 and §6 item 4 named "timestamp reads" a ledger channel (and §8.1 test 1.15 a
"tooltip registration" ineligible). Do they survive contact with the source?

**Evidence.** `Frame.timestamp` is read every frame by idle machinery: a `.trigger`-mode `keyframeAnimator`
reads `frame.timestamp` in its build (`KeyframeAnimator.currentValue`), every `.animation(_:value:)` track
reads it in `advanceColor` and `animateField` whether or not anything is in flight. A "timestamp was read"
ledger would make the fixture's nodes (which hold an idle shake) permanently ineligible, against spec §6 item
4's own `aKeyframeIdleSubtreeReplays`. What is time-varying is what *says so*: `Frame.noteActiveAnimation()`,
`requestAnotherFrame()` and `AnimationStore.noteInterpolation()`, which every running animation, spinner and
timeline calls. (`.help` is a contextual hitbox attachment and the tooltip is the window's, `Tooltip.swift`;
with prepaint running every frame, `SB-AA`, it is moot.)

**Ruling.** The time-varying signal is `Frame.timeVaryingNotes` (the first two calls) and
`AnimationStore.interpolationsSoFar`: an occurrence whose **build** moved either is time-varying and **never
keys** (`retainedEntryRefusal`: `timeVarying`), and one whose **paint** moved either, or tainted the log
through those calls, is **ineligible**. The timestamp is not read-counted. An animation that has just ended is
not time-varying on the frame it settles and has no record from its running frames, so its first quiet frame
records and the next replays (`aLiveAnimationNeverReplaysAndAnIdleKeyframeSubtreeDoes`). Cost: a view that varies
with the time **without** noting an animation would be replayed stale; no such element exists in `Sources/`
(the framework's own contract is that a time-varying frame keeps the display link awake), and the verify mode
would name one.

## SB-T — The scene is recorded where a subtree's own paint scopes end

**Question.** `SB-D` item 2 routed 14 sites through one `Frame.emit`. What is the funnel actually?

**Evidence.** Every primitive reaches the scene by `insertIntoScene`, from one of two places: the direct fast
paths (`fill`, `fillBackdrop`, `drawImage`, `drawSprite`, `drawPath`, `drawGradient`, taken when `paintScopes`
is empty) and the loop of `insertThroughScopes(leaf:depths:)` (every leaf, a text draw's glyph group and a
composite's re-emission). The loop already is a pipeline of scopes, innermost first; a subtree's own scopes (a
keyframe animator's `.offset`, an inner `.shadow`) are applied inside it, and its outer scopes (the fixture's
per-node `.offset`) are the ones a replay must meet.

**Ruling.** The loop is split into `Frame.processScopes(_:from:depth:)`, which notes the leaves at every
boundary an open recorder wants (`RetainLog.noteBoundary`), and a recorded subtree's scene is **the leaves as
they stand where its own scopes end** (boundary = `paintScopes.count` when its paint window opens), with the
clip depth they were emitted at. A replay calls `processScopes` from that boundary with those leaves: the outer
scopes capture, shadow, blur, composite, flatten and cut them exactly as they treat a fresh emission, and
`RasterCache` lookups for paths, shadows, gradients and blurs happen in `insertIntoScene` as they always did (so
a replayed raster is touched without a journal, and `rasterizedPixels` and `newTextures` are the fresh frame's).
The direct fast paths call `retainLog?.noteDirect` before inserting (boundary 0). A scope **pushed inside** the
subtree that captures (a transition, a drag source) or is a barrier (a `Deferred`) taints the recorder
(`taint(scopeIndex:)`: only recorders whose own scopes include that index); `pushLayer` taints too. Behaviour
is unchanged with no recorder open (0 px, the fourteen images; every existing test green with replay on).
Rejected: capturing at the `Scene` arrays (not sliceable, `SB-D`); recording only with no outer scope (every
fixture node sits under a per-node `.offset`).

**Cost if wrong.** A scope kind that reads state besides its parameters would replay stale; the key holds each
scope's kind, effect map, depth, flattening flag, outer mask, shadow and blur parameters.

## SB-U — What paint records, and what outside that set taints it

**Question.** How are the products captured without a hook at every mutation?

**Ruling.** Paint's products are the **scene operations** (`SB-T`), the **marks** (`StateTable.mark`: the
steady-state keep-alive of an `$anim`/`$anim-color` slot, `AnimatedColor.swift`, `AnimatedStyle.swift`) and the
**touches** (`AnimationStore.value(at:)`/`set(_:at:)`) it makes, each logged by the funnel that makes it while
a recorder is open (one nil check otherwise). A replay calls the same functions again, so a nested replay is
logged for the occurrence around it. **Outside this set the recorder is tainted** (the occurrence is
`ineligible`, counted, retried): a `StateTable.withState` (an `$anim-color` snap or first sighting, a
`TextField`'s or `ScrollView`'s state), a `StateTable.write`, a `GPUSurface` leaf, a portal (`pushLayer`), a
capturing or barrier scope pushed inside, a raised `noteActiveAnimation`/`requestAnotherFrame`/
`noteInterpolation`, and any move of `surfaceRequests`. The write-versus-read cut for `withState` is the
journal's: a `withState` always counts, because the table cannot tell a read from a rewrite. Carried: a
read-only spelling, which would let a `TextField` and a `ScrollView` replay (C14b-3).

**Cost if wrong.** A channel paint writes that is neither logged nor pinned is a stale or missing product: the
three instruments are the classification guard (`everyFrameChannelIsClassified`, `SB-E`), the differential and
the verify mode.

## SB-V — Observation is three windows per occurrence

**Question.** `SB-D` item 4 wrote three sessions over `finishComponent`, prepaint and paint.

**Ruling.** Each memo entry owns a `RetainedSession` per window. The **paint** window opens whenever the
occurrence records. The **build** and **prepaint** windows open only when the occurrence **needs observing**
(`Entry.needsObservation`): it has no record, or its record covers only its paint. A record made while all three
windows were observed (`coverageComplete`) keeps their sessions armed, so a steady hit opens none, and while none has
fired every later frame's reads are the reads those sessions saw (the key, the content serial and the `@State`
versions assert every other input equal). A record made on a frame that skipped the build and prepaint windows (a
valid record missed on a key, a version or an observed read) covers only its paint, is not replayed, and makes the
next frame observe all three: **a miss costs one extra recording frame before hits resume**. The first build opened
every window every frame (64 `withObservationTracking` a frame on the fixture) and read no gain in release (7.466 ms
against 7.475): the sessions cost what the replay saved. A session that fires sets `entry.observedChange`; a record is
replayed only while that is false, and the flag is cleared when a new record is made. Prepaint is observed because its
states feed paint (`anObservedReadInPrepaintInvalidatesTheRecord`). The window's own sentinel still dirties the window
(the reads inside a nested window merge upward), so the sessions need only invalidate. The getter memo's session is
unchanged and separate: a child's observed read re-evaluates the child and kills the parent's record, not the parent's
getter memo (`aChildGetterReadInvalidatesItsEquatableParentsRecord`).

## SB-W — The verify mode compares records, not frames

**Question.** `SB-M` item 1 wrote "on a hit, replay and also run the fresh paint into a scratch and truncate
away". A frame cannot truncate the scene's raster cache touches, the state table's marks or the animation
store's touched set.

**Ruling.** With `METALUI_VERIFY_RETAINED=1` a hit **runs the occurrence's paint as a miss** (the frame is the
fresh one) and compares the record it makes with the record a replay would have used
(`RetainedRecord.differences`): every scene operation (kind, layer, masks, texture identity, raster key), the
marks, the touches and the element work the record stands for. A trap names the first difference. The replay
mechanism itself (calling the recorded operations back) is compared with a fresh frame by the differential over
the script, which runs on every build. `METALUI_TRACE_RETAINED=1` prints why a record missed and why an
occurrence was ineligible (a diagnostic).

## SB-X — The pointer, press and focus rule is exact: the hovered element is under the component

**Evidence.** The first build decided at prepaint with "the pointer is inside a hitbox the record owns" and
read 28 hits and 4 misses against the predicted 29 and 3 in the first nine drag frames: the pointer (press at
x = 20, 2 pt per event) is over the status badge of node 14, whose `.help` hitbox is the occurrence's own, but
the hovered element is the node on top of it.

**Ruling.** At paint the hover is resolved (`Frame.hoveredElement`), so the rule is **the hovered, pressed or
focused element is the component's id or descends from it** (`GlobalElementID.isOrDescends(from:)`; identity is
structural, so an element inside the occurrence has the component's id as an ancestor). A hover elsewhere
costs the occurrence nothing, and a record made while one of the three is inside is not stored (a subtree the
pointer just left re-paints once). The predictions of `RetainedSubtreeWindowTests` hold in every drag frame.

## SB-Y — The lane 1 ineligible set as built, and what is carried

**Ruling.** Ineligible in lane 1 (counted `retainedIneligible`, retried each frame): a paint that snaps an
animated colour or border or keys one for the first time (`withState`: the first frame of every
`.background(color)` on a legacy element, so a window records on its second frame and replays from its
third), a `TextField`/`TextEditor`/`ScrollView`/`List` (paint reads its state through `withState`), a subtree
with a popover, a `GPUSurface`, a portal, a capturing scope, a time-varying build or paint, a custom
environment key at its entry (`customKeyCount`), a non-nil transaction animation at its entry, or a leaf group
open at its entry. Carried: the read-only `withState` (C14b-3), custom environment keys (C14-c), translated
replay (`SB-H`), prepaint replay and the build skip (lane 2, `SB-AA`).

## SB-Z — Counters

**Ruling.** `hits + misses + ineligible == contentEvaluations + contentSkips` for a tree in which no
occurrence sits inside a hit (an occurrence inside another's replay is not painted, so it counts in the
build only). `misses` counts an occurrence that ran paint and left a record or ran because the pointer, a press
or focus is inside it; `ineligible` one that ran and left none (counted when its paint window closes, or at
entry for a refusal). `retainedLedgerSnapshots` is 2 per occurrence that opened a paint window, 0 on a hit and on
an entry refusal. `retainedSkippedPaints` is the element paints a hit stood for, so `elementPaints +
retainedSkippedPaints` is the unretained frame's (pinned frame by frame in
`theBracketNodeDragReplaysEveryUnchangedSubtree`); `retainedSkippedPrepaints` stays 0 in lane 1.

## SB-AA — The decision is taken at paint: prepaint replay is carried to lane 2

**Question.** The design decided hit or miss in `EquatableComponent.prepaintGroup` and replayed prepaint and paint
(spec §3.1). Is that sound?

**Evidence.** The first build did it, left every existing test and the differential green, and then test 1.3 (`everyKeyComponentSeparates`,
one arm per key component) reddened three arms: `.opacity(_)`, `.shadow(radius:)` and `.blur(radius:)` written
outside the occurrence changed what paint draws and nothing the key held. The paint-only ambient — the opacity
stack and the open paint scopes of shadow, blur and composite, which register nothing in prepaint and so have no
prepaint counterpart — **is not on the frame at prepaint**: ancestors push it in their own `paint`, after every
prepaint has run. `PrepaintPass.withRenderEffect` mirrors a transform effect (its map is a hitbox transform) but
`isPaintScopeOnly` effects return their body unmodified. A prepaint decision can therefore never see them, and
replaying prepaint would need a recovery on a paint-time mismatch (a prepaint run at paint time under the saved
prepaint context, or a frame redo) that the design called lane 2's.

**Ruling.** Lane 1 **replays paint only**. The decision, the key and the recorder live in `paintGroup`
(`Frame.retainedPaintDecision`); prepaint always runs, in its own observation window (`SB-V`), so hit testing,
focus, accessibility and the prepaint states paint reads are always current, and every prepaint channel of
spec §5 (hitboxes, focus registry, accessibility, tallies, scroll regions, popovers, tooltips) leaves lane 1's
ledger: `ComponentPrepaint` is as it was. The cost is the prepaint's share (12 % of a release render on the
fixture, spec §1.1) which lane 2 owns with the build skip; the gain is that the key holds only paint's ambient
and the hover rule is exact (`SB-X`). Spec §3 and §4 are read with "paint" for "prepaint and paint" and the
prepaint half of §4.2/§4.3 struck; spec §5's table keeps only the scene, marks, touches and the paint-time
ledger. Rejected: a prepaint decision with a paint-time fallback (a sandboxed prepaint at paint time under a
saved context: it reproduces prepaint's registrations twice and was judged less safe than not replaying
prepaint at all); a mirror stack of paint-only ambient pushed in prepaint (a counterpart at every site that
pushes an opacity or a scope, one omission being a stale picture).

**Cost if wrong.** Lane 2 inherits the prepaint replay with the paint-ambient problem written down.

## SB-AB — A record keeps the final primitives too, and replays them when nothing else wants the leaves

**Question.** Replaying through `processScopes` runs the outer scopes' per-leaf logic again. What does that cost?

**Evidence.** After `SB-V`'s fix a perf `sample` of the fixture's `.value` arm put `replayPaint` at 123 of 3681
frame samples (3.3 %), with the fresh path's per-leaf scope work (`apply`, `cutToEntryClip`, the group copies of
`CapturedPrimitive`) the cost; a 736-leaf frame replays 736 leaves through the fixture's one outer `.offset` scope per
node.

**Ruling.** The recorder collects the leaves at boundary 0 (the scene itself) beside those at its own boundary. When
**every outer scope is a plain `.effect`** (a pure map of the leaf by parameters the key holds: transform, flattening
flag, outer mask) the record keeps them as `finalScene`; a shadow, blur, composite, capture or barrier outside means
the leaves must be handed to that scope and `finalScene` is `nil`. `replayPaint` inserts the final primitives straight
when **no live recorder wants the leaves** (`RetainLog.needsLeaves`: none open, or every open one already tainted);
with a live one open (the occurrence sits in another's recording) it replays the boundary stream so the outer recorder
sees the leaves pass its own boundary. A `withState` taints the recorder at once (the separate `withStates` list went). Verify mode compares both
streams. Release, `.value`: 6.900 → 6.569 ms per drag frame.

**Cost if wrong.** A scope kind that is not a pure map of parameters in the key (a future `.effect` that reads state)
would replay stale final primitives; the key's scope vector and `everyKeyComponentSeparates` (shadow, blur, rotation,
offset arms) are the instruments.

## SB-AC — A descendant whose content ran this frame kills its ancestor's record

**Question.** `METALUI_VERIFY_RETAINED=1` over the unfiltered suite trapped in `anEqualComponentSkipsItsContent`: a
parent replayed a leaf's old text. Which hole is that?

**Evidence.** The parent's build window opens only when it has no complete record (`SB-V`). A parent that records
in a frame where an equatable descendant's content is skipped by the content memo never reads that descendant's
`@Observable` properties inside its window, so its sessions are not subscribed to them. The descendant changes later: its own memo
re-evaluates it, the parent's armed sessions stay silent, the parent's key, serial and versions are unchanged, and
the parent replays a stale picture. Test 1.8b reproduces it with two leaves (the first changes so the parent records
while the second is skipped, then the second changes); the verify run found it, no hand-written test had.

**Ruling.** `EquatableComponent.requestGroupLayout` reads `ContentMemoStore.evaluationsSoFar` after its own
materialize and after its build recursion; a difference sets `entry.observedChange`, so the occurrence misses and
records again. Two integers a frame per occurrence, no tracking. Mutation: the comparison replaced by `_ = ...`
reddens 1.8b at its last glyph comparison and nothing else (the 1.8 test covers the getter-read hole it was named for).

**Cost if wrong.** A descendant that changes its picture without a memo evaluation (a plain component reading an
`@Observable` it also read when the record was made is subscribed by the armed window; one first read in a skipped frame is the hole this closes)
would still be stale; the verify-mode run over the whole suite is the instrument.

## SB-AD — Lane 2 lands the placement memo alone: marked subtree roots restore their placement in place

**Question.** The gate (`SB-C`) read 57 % and opened lane 2: a graft, a journal, a counted redo, prepaint replay and
the subtree placement memo (`SB-N`, `SB-O`, `SB-R`). Which of these lands behind unchanged semantics with a measured win?

**Evidence.** The placement memo is the one piece with no dependency on the others. `LayoutTree` stores root-absolute
rects, placement of a subtree is a pure function of its structural signature (`IV-E`), the proposal it is placed at and
the bounds it is placed in, and slice 1 already restores a *root* placement on those three (`placeFromMemo`). A marked
node can use the same key anywhere in the tree. On the fixture the root never hits (the wires change size every drag
frame, `layoutMemoRootHits: 0`), the 32 occurrences are the `.equatable()` components, and a drag frame did 1258 measure-memo
lookups and 366 cache hits (counted after the key change below) of which the placement of 10 unmoved nodes was most.

**Ruling.**
1. `LayoutTree.markPlacementRoot(_:)` (`package`) marks a node; `EquatableComponent` marks each top-level node of
   an occurrence **while retention is on** (`retainsSubtrees`, so `testingRetainedSubtrees = false` is the unmarked arm).
   A fresh tree has no marks.
2. In `placeNative`, after the node's rect is stored, a marked node with a signature and at least one child asks the memo
   for `PlacementKey(signature, proposal, bounds)` — **all four bounds fields bit for bit, origin included**. A hit writes the
   subtree's recorded unrounded rects in pre-order and returns: nothing under the node is measured or placed. A miss places
   as before and stores the subtree's rects on the way out. The memo's two-frame lifetime, the rounding walk and the
   measured-width recording are untouched (the rounding walk runs over the whole tree after placement, as for a root hit).
3. **No translation.** `SB-O` and spec §9 item 4 said "by translation". Rects are root-absolute and a fresh placement
   computes `parent.origin + offset` along the chain: translating a recorded rect by a delta is a different association of
   the same additions, and the output must be byte-identical (`SB-H`'s float-association finding, re-used here without
   a new probe). A moved subtree is placed fresh; translation is carried with `SB-H`.
4. `METALUI_VERIFY_LAYOUT_MEMO=1` / `LayoutMemo(verifies: true)` recomputes every subtree hit from zeroed rects with the memo
   suspended and traps on a difference (`IV-J`).
5. Counter `NativeLayoutWork.memoSubtreeHits` (`BuildWork`, `FrameWork.layoutSubtreeHits`): work, never time.
6. **Two more leaves are keyed** (`IV-E`'s rule: a key covering everything the closure reads): a `Color` used as a view
   (`ColorLeafKey`: its measure is the proposal, 10 on a nil axis) and an empty legacy container's 0 x 0 leaf
   (`EmptyContainerLeafKey`: constant). The fixture's nodes hold both, and one unkeyed leaf makes every ancestor unmatchable
   — without them no node had a signature and the memo restored nothing (debug counts: 0 hits). This moves slice 1's
   counts for any tree holding either leaf (more memo hits, fewer measures): `theBracketNodeDragRebuildsTheWholeWindow`'s
   layout literals are re-counted (81/805/527/1106/30 at `e85cb07a` -> 52/366/217/1258/55) and the suite's other pins
   that moved are named in record 109 §11.

**Not built, and why (carried to C14b-2, evidence in record 109 §11).** The build skip needs prepaint replay: with the
build recursion skipped no element exists to prepaint, so hitboxes, focus, accessibility, scroll regions and tallies must
be replayed, and `SB-AA` found that the decision to replay prepaint cannot be taken there (a paint-only ambient — an
ancestor's opacity, shadow or blur scope — is not on the frame until the ancestors paint). The design's answer is a
frame redo on a paint-time mismatch (`SB-R`), whose correctness rests on restoring `StateTable`, `LifecycleStore`,
`AnimationStore` and `Frame` channels that a first build has already mutated: a journal of nine channels each with its
own funnel, none of which this lane had a verify-mode instrument for. Landing the placement memo first costs nothing:
a graft would reuse its keys.

**Cost if wrong.** A key that does not cover its closure restores a stale rect: the verify mode over the whole suite
(record 109 §11) and the differential `aRestoredDragEqualsAFreshOneAtEveryStep` are the instruments. A tree with
nothing marked (retention off, or no `.equatable()`) is byte-for-byte slice 1.
