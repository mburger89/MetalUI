# Retained subtrees (C14b) — design

Item C14b of the gpui-gap priority list (user request 2026-10-02; **not a plan task**),
the second half of C14. Prefix `SB-`; rulings in
[`../2026-10-13-retained-subtrees-decisions.md`](../2026-10-13-retained-subtrees-decisions.md);
record `docs/record/109-retained-subtrees.md` (Record phase). Branch `perf/retained-subtrees`
from `e85cb07a`. Fixture spec (from MetalCreator's developer, read-only input):
[`2026-10-13-retained-subtrees-fixture.md`](2026-10-13-retained-subtrees-fixture.md).
C14 slice 1 is record §104 (`IV-A`…`IV-Q`; its `IV-H` ruled this item's design and `IV-C` its
observation); this document supersedes `IV-H` where it differs and says where (`SB-B`, `SB-N`).

**Status: LANE 1 BUILT AS PAINT REPLAY (`SB-AA`).** The text below is the design as written; where lane 1's
build differs it is amended by `SB-S`…`SB-AA` in the decisions document, chiefly: **the decision, the key and the
recorder are in `paintGroup`, prepaint always runs** (§3, §4.2/§4.3, §5, §6 items 5–9, §8.1 tests 1.5, 1.15 and
the counter list read with "paint" for "prepaint and paint"), the pointer/press/focus rule is "the hovered,
pressed or focused element is under the component" (`SB-X`), a time read is not a channel (`SB-S`), and
prepaint replay moves to lane 2 with the build skip. Original status: Two lanes, sequential. **Lane 1 is built to completion** and lands a
measured win behind unchanged semantics. **Lane 2 is designed here and gated on lane 1's own
measurement** (§9). Nothing in this document is built yet except the fixture and its baseline
test (§1), which are on the branch.

## 0. Summary

* **What is retained.** The *render products* of one `.equatable()` component occurrence
  (`EquatableComponent`, record §104 §5): the hitboxes, focus stops, accessibility emissions,
  scene primitives and the cache touches its `prepaint` and `paint` produced. On a frame where
  the occurrence is unchanged and its **replay key** (§4) is equal, its prepaint and paint are
  **replayed from the record instead of run**. No public API: `.equatable()` is the opt-in
  (`IV-B`), and a package switch turns replay off for the memo-off arm of every test.
* **What is not saved by lane 1.** The build recursion (`requestLayout`) still runs on the
  pristine content, so a miss is always safe: every element's layout record exists, and a
  failed key runs prepaint and paint as today. That is the reason lane 1 comes first (`SB-C`).
* **Lane 2 (gated)** removes the build recursion too: graft the subtree's layout nodes into the
  new frame's tree, replay the `StateTable` frame-set deltas, and fall back to a one-subtree
  frame redo on a miss (§9, `SB-N`). It carries the subtree **placement memo** of record §104
  spec §4.1 (§10).
* **Measured start** (§1, the node drag of the fixture). Release, 6.0 ms per frame: build 33 %,
  paint 32 %, layout kernel 19 %, prepaint 12 %. Debug, 55 ms: paint 61 %, build 18 %, layout 11 %,
  prepaint 9 %. Prepaint plus paint (lane 1) are 44 % in release; build plus layout (lane 2) 52 %.
* **Not decided by feel**: the release readings are in §1.1 and open lane 2's gate.

## 1. The fixture and the measurement (design phase, `e85cb07a`)

`Tests/MetalUITestingTests/BracketFixture.swift` (no `Testing` import: the perf harness copies it)
is MetalCreator's bracket window: 1440 x 900 at scale 2; a 36 pt top bar (a `Text`, a menu
`Picker`, two `Button`s, a `Menu`); a 460 pt graph panel (a header with breadcrumbs and 7 `Button`s,
a node library of a caption, a `TextField` and a windowed `List`, then the canvas); a 280 pt inspector
on `.regularMaterial` (backdrop blur) with 3 sections of `Slider`s, a `Toggle`, a summary row and a
`Button`; and a full-window `.onDemand` `GPUSurface` under all of it. The canvas holds 20 nodes
(82 rows, 82 socket dots, the fixture's table) and 21 wires, each wire one cubic `Path` stroked at
2 pt and framed to its padded bounds (control offset `max(40, |dx|·0.5)`).

Choices the fixture spec left open, each fixed in the file:

* **The cull.** Nodes sit 40 pt apart, 168 wide, so any 40 pt spacing keeps 23 of them inside a
  460 + 2·160 pt window; "roughly half" is not reachable by spacing. The fixture pans the canvas
  by -680 pt so nodes 9…19 (**11 of 20**) pass the cull and Fillet (index 17) sits flush left in the
  canvas. The cull is `BracketModel.visibleNodes`, read by the canvas at build time.
* **Overlap.** Node 18 (Chamfer) overlaps Fillet from x = 40, so the press is at x = 20 (the first
  version pressed at 40 and dragged Chamfer; the trace is why this is written down).
* **Equatable arms.** `.value`: `BracketNodeView` and `BracketWireView` are `.equatable()` on their
  node value plus the palette (a value); the panels are plain components. `.environment`: the node
  view reads `@Environment(\.colorScheme)` and is refused every frame (divergence 346's cost).
  `.panels`: `.value` plus every panel `.equatable()` (what MetalCreator would do once it adopts C14).
* **Where the drag lives.** The `DragGesture(minimumDistance: 0)` and the `.offset` are on the node's
  *slot* (outside the equatable view), the node's data carries `x`/`y`, so the dragged node's `==`
  is false and its content re-evaluates, as MetalCreator's does. A node view whose value does not
  carry the position (the `.offset` alone moves it) is the *translated replay* case, carried (`SB-H`).

**Counted baseline** (`theBracketNodeDragRebuildsTheWholeWindow`, 3 warm frames, a press at (20, 400)
and 20 drag events of 2 pt, one tick each, then the release: 21 drawn frames; Fillet ends at x = 720):

| per drag frame | `.value` | `.environment` | `.panels` |
|---|---|---|---|
| node bodies / wire bodies | 1 / 2 | 11 / 2 | 1 / 2 |
| `contentEvaluations` / `contentSkips` / `contentRefusals` | 3 / 29 / 0 | 2 / 19 / 11 | 3 / 32 / 0 |
| layout measure calls / cache hits / misses | 81 / 805 / 527 | same | same |
| layout memo hits / misses / root hits | 1106 / 30 / 0 | same | same |
| signature nodes hashed | 844 | same | same |
| rects / glyphs / images in the scene | 182 / 550 / 6 | same | same |
| CPU-rasterized pixels / new textures (the two changed wires) | 78312 / 2 | same | same |
| text system: measures / `placeGlyphs` over 21 frames | 2898 / 2814 | same | same |
| element `prepaint` / `paint` calls (the `Element` group defaults; instrument patch) | 798 / 798 | same | same |
| element `requestLayout` calls through the same defaults (the typed proposal defaults are not counted by the instrument; lane 1's counter covers both) | 288 (partial) | same | same |

The scene is identical in all three arms (the arm changes who evaluates, not what is drawn). The
two changed wires are rasterized every frame whatever this item does (`GX-B`: a path is rasterized
on the CPU in device pixels; the changed wires are new keys). The root layout memo hits **never**
(`layoutMemoRootHits: 0`): the wires' frames change size, so the signature changes (§10).

**Phase shares, debug** (`docs/probes/retained-subtrees/phase-timing.patch`, 15 reps x 22 frames,
macOS arm64, other workflows running; ms per frame, wall clock as an instrument only):

| arm | build | layout kernel | prepaint | paint | sweeps | render | `tick` |
|---|---|---|---|---|---|---|---|
| `.value` | 9.96 | 5.98 | 5.06 | **33.73** | 0.72 | 55.56 | 61.50 |
| `.environment` | 9.26 | 5.39 | 4.21 | 30.03 | 0.62 | 49.60 | 55.01 |
| `.panels` | 8.50 | 5.41 | 4.23 | 30.09 | 0.63 | 48.95 | 54.41 |

`.value`: paint 61 %, build 18 %, layout 11 %, prepaint 9 %, sweeps 1 %. **Release readings: §1.1.**

### 1.1 Release readings

Dated measurement, 2026-10-13, `e85cb07a` plus the instrument patch, **release** (`-c release
-Xswiftc -enable-testing`), macOS arm64, `Mac14,*`-class Apple silicon, **the Mac was shared with
other workflows** (load average 7 at the first run), 30 reps x 22 frames per run, three whole-process
runs; the range of the three runs is given, the median in the table. Wall clock is an instrument:
no pin reads it.

| arm | build | layout kernel | prepaint | paint | sweeps | render | `tick` |
|---|---|---|---|---|---|---|---|
| `.value` | 1.993 (1.984-2.014) | 1.151 (1.146-1.162) | 0.748 (0.740-0.755) | 1.915 (1.908-1.927) | 0.182 | **6.001** (5.969-6.053) | 7.149 (7.115-7.195) |
| `.environment` | 2.105 (2.095-2.106) | 1.146 | 0.741 | 1.904 | 0.180 | 6.088 (6.084-6.094) | 7.241 (7.224-7.247) |
| `.panels` | 1.983 (1.962-2.055) | 1.151 | 0.747 | 1.909 | 0.182 | 5.983 (5.946-6.150) | 7.113 (7.073-7.339) |

Release shares of `render`, `.value`: **build 33 %, paint 32 %, layout kernel 19 %, prepaint 12 %**,
sweeps 3 %; `tick` adds 1.15 ms for the headless platform and scene finalisation. Three readings:

* **Debug and release disagree about the order.** Debug puts paint at 61 % (generic `Element`
  code is slow unoptimised); release puts build and paint level. Prepaint plus paint is **44 %** in
  release, the work lane 1 removes for unchanged subtrees; build plus layout kernel is **52 %**, the
  work lane 2 targets. Neither lane can be dropped on this tree; lane 1 goes first for risk (`SB-C`).
* **Divergence 346's refusal costs 0.09 ms here (1.5 % of render):** the `.environment` arm
  re-evaluates the 11 node bodies per frame (`build` 2.105 vs 1.993) and nothing else, because the
  build recursion and layout run on the pristine content in either arm. Slice 1 saved the *getters*;
  the figure above is what a getter costs in this tree. The refusal becomes expensive only when
  prepaint and paint are replayed (the `.environment` arm gets no hits: spec §4.2).
* **MetalCreator's 15 ms** (its heavier nodes, a loaded Mac, its shadows and strokes) against this
  tree's 6.0 ms is a factor 2.5; the fixture has the right *shape* (counts, shares), not the right
  absolute cost, and the pins are counts for that reason.

### 1.2 What the measurement says

1. **Prepaint plus paint are 44 % of a release render and 70 % of a debug one; build is 33 % and
   18 %.** Slice 1's synthetic tree had build at 51 % because its leaves were bare `Text`s; the
   bracket window's leaves carry rounded rectangles, clips, strokes, `Capsule`s, circles and `Path`s,
   and paint is where they cost. A design that began with the build recursion (`IV-H`) would have
   begun with the riskier half (`SB-C`) and left the larger half for later.
2. **A node drag leaves 29 of 32 equatable occurrences unchanged per frame** (`.value`), and the 3
   that change are exactly the dragged node and its two wires: the retained set is large and the
   changed set small, which is the case retention exists for.
3. **`.panels` skips 3 more** (top bar, panel, inspector) but the panel holds a `List` and a `ScrollView`,
   which lane 1 declares ineligible (§5, `SB-J`): the panel is a miss, its three children are hits.
   The inspector (sliders, a toggle, buttons, a `Material`) is the largest retainable panel.

## 2. What a retained subtree is

**Unit.** One `EquatableComponent` occurrence, keyed exactly as its content memo is
(`ContentMemoStore.Key`: identity plus type). Finer scopes (a modifier, a `List` row, a `ForEach`
element) are not offered: they need an equality the framework does not have for them (C14-d,
`SB-B`). `IV-H`'s "any `Component`" is refused for the same reason `IV-K` refused automatic
skipping: replay trusts the value, and only `.equatable()` says the author vouches for it.

**Record.** `RetainedRecord`, a heap object in the memo entry (`ContentMemoStore.Entry.record`;
swept with the entry, `ContentMemo.endFrame`), holding:

* the **replay key** (§4) of the frame it was recorded in;
* the **products**, in registration order: hitboxes, focus stops, accessibility emissions and
  `axNodes`, the scene operations (§3.3), the integer tallies prepaint adds, and the **touch lists**
  (raster-cache keys, animation-store ids, `StateTable` slot marks) paint adds;
* the **validity inputs** (§6): the subtree's bound-state versions, a per-record observation session,
  and the owned-id sets used by the pointer/active/focus rule (§4.3);
* its **work** (`elementPrepaints`, `elementPaints` it stands for), so a hit can report the work it
  skipped as a conservation law (§8, test 1.1).

**No new public API.** `equatable()`'s doc comment gains the paragraph on what is now saved
(prepaint and paint) and the author's contract (§6.2). Package API only: the record, the ledger,
`Window.testingRetainedSubtrees` (test switch), `METALUI_VERIFY_RETAINED` (read once). No inventory
map row; the new `FrameWork` fields are covered by the harness regex as slice 1's were.

## 3. Mechanism

### 3.1 Where the decision is made

`EquatableComponent.prepaintGroup(layout:pass:)` decides, because only there are the layout results
known (the key needs bounds) and no hitbox of the subtree is registered yet:

```
hit    = entry.record exists ∧ record.isValid ∧ eligibleNow ∧ key(now) == record.key
if hit    → replayPrepaint(record); return an empty ComponentPrepaint (payload nil)
if !hit   → record = recorder.begin(); prepaint as today; recorder.end(into: entry)   // miss or first
```

`paintGroup` mirrors it: a `ComponentPrepaint` with a nil payload replays the paint operations, else
it paints and finishes the record. `ComponentPrepaint.Storage.prepaint` becomes optional (an internal
change in `Component.swift`; the type is already a heap box, so no stack or `Decoration` growth,
`SB-L`). The decision is taken once in prepaint and carried to paint by that nil, so prepaint and paint
never disagree.

### 3.2 Recording: bracketing, not interception

The recorder does not interpose on the 100 mutation sites of `Frame`. It **brackets** the
subtree's prepaint and paint:

* **Before and after** each phase it takes a `LedgerSnapshot` (§5): the lengths of the append-only
  channels (`hitboxes`, `axEmissions`, the focus registry's stops, `surfaceRequests`, …), the
  counts of the keyed dictionaries, and the integer tallies. The difference is the product (the
  `hitboxes[lo..<hi]` slice, the new `axEmissions`, the tally deltas) and any channel that moved
  **and is not in the replayable set** makes the record `ineligible` (counted, with the channel's
  name, `retainedIneligible`).
* **Scene products are the exception**: they are captured at the `Frame.emit(_:)` funnel (§3.3),
  because the scene array alone cannot be sliced (paint scopes may capture a primitive into an outer
  shadow's leaf group instead of the scene).
* **Touches** (rasters, animation entries, slot marks) are journalled by the stores themselves while
  a recorder is open: `RasterCache.touch(key)`, `AnimationStore.touch(id)`, `StateTable.mark(id)` /
  `noteProduced(id)` each append to the open journal if there is one (a nil check on a miss frame, no
  cost on a hit).

### 3.3 The scene funnel

Today `Frame` has 14 `scene.insert` sites and an `insertThroughScopes(_:)` for a primitive made
inside an open paint scope. The refactor (behaviour-preserving, 0 px, first commit of lane 1) routes
every primitive through `Frame.emit(_ primitive: CapturedPrimitive)` =
`paintScopes.isEmpty ? insertIntoScene(primitive) : insertThroughScopes(primitive)`, plus
`beginLeafGroup`/`endLeafGroup` as two more operations. A recorder records
`emit`/`beginLeafGroup`/`endLeafGroup` calls made **at the paint-scope height the subtree started
at** (an internal scope's own leaves are emitted at a greater height and are not recorded; the
primitive the scope produces when it closes is emitted at the entry height and is). Replay calls the
same funnel with the same values, so a replay inside an outer `.shadow`/`.blur`/`compositingGroup()`
is captured by that scope exactly as a fresh paint is (`PF-E`), and a backdrop degrades by the same
rule (`BB-H`). The recorded values carry their context (translated bounds, clip, radii, opacity,
layer, scale), which is why §4 keys it.

### 3.4 Replay

Prepaint replay appends the recorded hitboxes (value copies; `Handlers` closures are the recorded
frame's, which the `==` contract makes equal to a fresh frame's, §6.2), registers the focus stops
through the registry's own `register` (so `focusedElementProducedThisFrame` and `$focus` retention
follow), appends the `axEmissions` and `axNodes`, adds the tallies (`hoverRegionCount`,
`keyRegionCount`, …) and the touches. Paint replay re-emits the scene operations and touches the
rasters. Both happen **at the same position in the traversal** as the fresh run, so registration order
(the one hitbox ranking, `topmostHitbox`; focus order; accessibility order) and draw order
(`Scene.insert`'s layer then insertion order) are those of a fresh frame.

## 4. The replay key

A record is replayed only if every component below equals its value at recording. The key is one
`Equatable` struct (`ReplayKey`), built in prepaint from the layout and the frame's ambient stacks.

### 4.1 Geometry

* The **absolute rect of every top-level node** the component returned (`EquatableComponent` stores
  its `[LayoutNodeID]` in its layout box), bit-equal, and the subtree's **node count**.
* A **hash of every descendant rect** (four floats per node, one pass over the node range). The
  structural argument says the interior is a function of the final rect and the (unchanged)
  structure; the hash is the cheap guard against the case that argument misses, and the verify mode
  (§7) is the instrument that says whether it is needed. It is kept if verify mode ever sees it
  separate; removed with a recorded justification if not (`SB-F` item 3).

### 4.2 Ambient context (everything prepaint and paint read that is not in the subtree)

`activeClip` and its radii, `activeOffset`, `activeLayer`, `activeOpacity`, `scaleFactor`, the open
paint scopes (kind and parameters of each, because an outer shadow captures), `prepaintEffects`'
top (the hitbox transform), `shareFloor`/`shareFloorAtEntry`, `clipBase`/`flatteningClipBase`, the
named-space stack's identity (hitbox snapshots), the scroll context and scroller frame (both must be
nil in lane 1), `stackAxis`, the disabled / hit-testing-disabled / keyboard-hidden / accessibility-
suppressed gates, `collectsAccessibility`, the theme identity and colour scheme, and the
**environment fingerprint**: an `Equatable` struct of the built-in `EnvironmentValues` fields plus
`customKeyCount`. **A non-zero `customKeyCount` anywhere on the path makes the occurrence
ineligible** (counted `retainedIneligible`): an app-defined key's value has no equality
(`SB-G`; C14-c, the environment epoch, owns lifting it). A guard fails when `EnvironmentValues` gains
a stored property that is neither in the fingerprint nor declared irrelevant (`SB-G`).

### 4.3 Pointer, press and focus

Hover, active and focus reach a subtree's paint only through the hitboxes it owns. The key therefore
holds three booleans computed from the **owned** hitbox set: *the pointer is inside any owned hitbox
bound* (`mousePosition`), *`activeElement` is an owned id*, *`focusedElement` is an owned focus
stop*, and the record is replayed only when all three are false now **and were false at recording**
(a subtree the pointer just left re-paints once). Owned hitboxes are the recorded ones; the key is
evaluated against them before replay. A node with no hitbox of its own (the fixture's plain
labels) is never affected, and the neighbour overlap of the fixture costs nothing (§1: the slot's
`DragGesture` is outside the equatable view).

### 4.4 Deliberately not in the key

The window title and preferences (build-phase reports), `timestamp` (a subtree that reads it is
ineligible: the pass counts reads, §5), `mousePosition` outside §4.3, and the glyph atlas (grow-only,
`evictUnusedSince` has no caller; a guard greps for a caller and fails when one appears, `SB-I`).

## 5. The ledger

A **channel** is anything prepaint or paint can change outside the element's own record. Lane 1
classifies every stored property of `Frame`, `StateTable` and `AnimationStore` (the 100 + 33 + 11
found, reflected with `Mirror` so private ones count) into:

| class | meaning | examples |
|---|---|---|
| **recorded** | replayed | `hitboxes`, `axEmissions`, `axNodes`, `accessibilityPressOnly`, `contextMenuRecords` (see below), focus registry stops, `scene`, the region tallies (`hoverRegionCount`, `pointerStyleRegionCount`, `keyRegionCount`, `focusOnPressCount`, `resignRegionCount`), raster / animation / slot-mark touches |
| **keyed** | in the replay key | `clipStack`, `layerStack`, `opacityStack`, `paintScopes`, `prepaintEffects`, `namedSpaces`, `environmentTop`, `scaleFactor`, `theme`, `hitTestingDisabledDepth`, `keyboardHiddenDepth`, `accessibilitySuppressionExceptions`, `stackAxes` |
| **ledger** | a change makes the record ineligible | `scrollRegions`, `scrollRequests`, `surfaceRequests`, `presentationRecords`, `presentationAnchors`, `presentationSpaces`, `openPopovers`, `toolbarRecords`, `tooltip`, `dragSourceID`, `menuPanelLevels`, `hasActiveAnimations`, `wantsAnotherFrame`, `transactionDepth`, `lifecycleDepth` writes, `AnimationStore.interpolationsThisFrame`, foreign `StateTable` reads, timestamp reads, `GeometryChangeScope` notes |
| **frame-local** | not touched by prepaint or paint, or constant for the frame | `contentSize`, `tree`, `textSystem`, `glyphAtlas`, `shapingCache`, `reportsUnlowerableFields`, … |
| **build-only** | written in the layout phase only (build runs in lane 1) | `lowering`, `hiddenNodes`, `elementBounds`, `forEachIdentityWork`, `scrollKeys`, `StateTable.namedPositions`/`loopExtents`/`windowedParents`/`departedNames` |

* `contextMenuRecords`: **recorded** (a context menu is a hitbox handler plus a record keyed by id).
* The **classification guard** (`everyFrameChannelIsClassified`) reflects the three types and fails
  on any property absent from the table, the way `theSevenRetentionSlotsAreMutuallyDistinct` fails on
  an eighth slot; adding a stored property to `Frame` now owes a table row.
* A **ledger snapshot** is about 30 integer reads taken twice per recorded phase. A miss frame pays
  that plus the journals; `retainedLedgerSnapshots` counts them so a pin can bound the cost.

## 6. Every interaction, ruled

Each line is a ruling in the decisions document; the pinning test (§8) is named.

1. **Identity** (`ID-B`, `ID-C`, `ID-R`, `noteNamed`, the sweep). The build recursion runs in lane 1,
   so every `noteNamed`, `StateBinder.bind`, `marked`, `producedSlots`, `loopExtents` and
   `windowedParents` write happens every frame as today. What *prepaint and paint* write into the
   table is journalled and replayed through the same funnels: the **marks** (`StateTable.mark`, the
   steady-state keep-alive of `$anim`/`$anim-color` slots at `AnimatedColor.swift:594` and
   `AnimatedStyle.swift:518`, and `registerHandlers`' `$focus`/`$ax` retention), so a sweep never
   sees a replayed subtree's slot as unproduced; a paint-time **write** (`withState` in the same two
   files, an animation in flight) is a ledger channel and makes the record ineligible. The
   `noteProduced`/`noteAbsent`/`noteOptional` calls of `ElementGroup.swift` and
   `ProposalElementGroup.swift` are build-phase and run every frame
   (`aReplayedFrameKeepsItsAnimatedColourSlotsAlive`). A removed occurrence's record dies with its
   memo entry (`ContentMemoStore.endFrame`); an `if`/`ForEach` flip is a different identity and a
   different entry. `.id()` outermost and MC-A numbering are untouched: no identity level is added.
2. **State and observation.** The record is valid only while (a) every `@State` slot **bound under the
   component** during the recording build still has the version it had (the bind journal; includes
   descendants' state, not only the component's own, because lane 1 reuses a descendant's *old*
   prepaint/paint); (b) the **render session** has not fired: `withObservationTracking` brackets the
   build recursion (`finishComponent`), prepaint and paint of a recorded occurrence (three windows,
   one entry, serial-checked exactly as `IV-L` item 5), so an `@Observable` read in a descendant's
   getter, in `Element.prepaint` or in `Element.paint` marks the record stale and the window dirty.
   The slice-1 getter session is unchanged and separate: a child's observed change re-evaluates the
   child, not its equatable parent's getter (`SB-D`). `@Environment`/`@FocusState` components stay
   refused (divergence 346, `IV-D`); the fixture's `.environment` arm is the cost. The author's
   contract, written on `equatable()`: *the subtree's output is a function of the value, the
   component's `@State`, the `@Observable` properties it reads and the built-in environment; a
   `Binding` input read in `paint` is a value and belongs in `==`* (`IV-B`'s sentence, extended).
3. **Lifecycle** (`LC-`). Presence is membership in a build; the build runs; unchanged.
   `onGeometryChange`'s note is made in prepaint → ledger (ineligible) in lane 1 (`SB-J`).
4. **Animation** (`AN-`, `AnimationStore`, transactions). `Frame.hasActiveAnimations` raised or any
   `AnimationStore` entry interpolating in the subtree's paint → ineligible; a keyframe animator
   *idle* (the fixture's refusal shake) touches its entry without interpolating → recorded touch,
   replayed (`aKeyframeIdleSubtreeReplays`); `TimelineView`, transitions' ghosts and a transaction
   in flight (`transactionDepth > 0` at entry with a non-snapping animation) → ineligible.
5. **Focus and `tabOrder`**. Stops are replayed in order through the registry's `register`; a
   focused owned stop → miss (§4.3), so `focusedElementProducedThisFrame`/`resolveFocus` run on a
   fresh registration. `@FocusState` components are refused already.
6. **The one hitbox ranking.** Replay appends at the same position, so `topmostHitbox`'s
   (layer, registration order) is a fresh frame's. A hitbox is a value; `HitboxID` (a per-frame
   index) is held only by element prepaint state that a hit never creates.
7. **Accessibility** (`AB-`). `axEmissions` and `axNodes` replayed in order; `collectsAccessibility`
   false at either frame → ineligible (an empty recording would be replayed into a client-attached
   frame); a hidden-layer suppression is keyed (§4.2). Both bridges untouched: the products are the
   neutral records they already read.
8. **Gesture arena** (`IX-`). Gesture members are `Handlers` on hitboxes; replayed with them. The
   arena of a press in flight holds ids and the hitboxes of the press frame; unchanged.
9. **Presentations and `Deferred`**. A `Deferred` portal inside a subtree hoists to the root layer
   and resets clip/offset: its products go to the portal's list. Lane 1: a subtree that contains a
   portal, a presentation record, a popover, a tooltip registration or a drag source is ineligible.
   A subtree *inside* a `Deferred` is eligible, and `activeLayer` is keyed.
10. **Paint scopes** (transforms, shadows, `compositingGroup`, clips). §3.3: recorded at the entry
    height; the open scopes are keyed (§4.2); `GX-U`'s share floor is keyed.
11. **`RasterCache`, scene order, the shadow cache** (`PF-`). Raster keys touched in paint are
    journalled and re-touched on replay (`RasterCache.endFrame` drops what a frame did not draw), so a
    replayed image keeps the same `ImageTexture` identity and no raster is redone
    (`aReplayTouchesItsRastersSoTheyAreNotDropped`). `RasterAnchor` keys are relative to a floored
    anchor; an anchor shift makes the *recorded primitive* wrong, but the primitive's absolute
    bounds are in the key, so the subtree misses (translated replay, `SB-H`, is where `PF-A` pays).
12. **GPU surfaces** (`MV-`). A `GPUSurface`/`MetalView` leaf appends a `surfaceRequests` entry →
    ledger → ineligible (its draw is a per-frame request, not a primitive). A subtree *beside* a
    surface (the fixture's) is unaffected.
13. **Backdrop materials** (`BB-`). A backdrop primitive is an ordinary operation; replayed, it is
    byte-identical and is blurred by the renderer from whatever is behind it at render time (the
    backdrop's dependency on content *outside* the subtree is the renderer's, not the scene's). The
    degrade rule depends on the open scopes, which are keyed.
14. **`List` windowing** (`VL-`, `DD-F`, `TB-AH`). `List`/`ScrollView` register scroll regions →
    ledger → ineligible in lane 1 (`SB-J`; carried to C14b-3 with the scroll-offset-as-state
    argument written down). A `List` is still built each frame by its parent; windowing and
    `TB-AH` retention are build-phase and untouched.
15. **Text input.** A `TextField`/`TextEditor` owns a focus stop and a text-input handler; unfocused
    it is replayable, focused it misses (§4.3), composing implies focused. Caret blink reads
    `timestamp` → ineligible while focused anyway.
16. **Stack budget** (1 MB threads, `DecorationExtras`). The record, the journals and the recorder
    are heap objects hung off the memo entry; `Decoration` and `Handlers` do not grow
    (`MemoryLayout` pins exist); `ComponentPrepaint` stays one heap box;
    `EquatableComponent.prepaintGroup`'s frame holds no new large local (the recorder is a class).
    `everyProductionTreeBuildsOnAOneMegabyteThread` is run unfiltered and the demo's new section is in
    its own function.

## 7. Verification: output equality, not work counts

* **Verify mode** (`METALUI_VERIFY_RETAINED=1`, read once, package): on a hit, replay *and* run the
  fresh prepaint and paint into a scratch (the hitbox/focus/AX/scene lengths are saved and the
  scratch is truncated away) and `precondition` that the products are equal element for element
  (bounds, ids, layer, opacity, text, scene operations including texture identity). The memo-off
  arm of the same window is the second comparison. The whole suite runs once under it (test 1.12);
  a trap is a finding.
* **Differential** (test 1.2): the same script (the fixture's drag, a scheme toggle, a resize, a hover,
  a press, a focus move, a `@State` write in a descendant, an `@Observable` write) on two windows,
  retention on and off, comparing scene arrays, hitboxes, the accessibility tree and focus order
  after every frame. This is the instrument that says the key is complete.
* **Pixels**: the fourteen offscreen images 0 px against `e85cb07a` (`docs/probes/demo-pixels/
  compare.sh <scratch> e85cb07a HEAD`); `DemoFrameDeterminismTests`' `Expected.swift` unedited.

## 8. Lane 1: files, steps, tests

**Files owned.** New: `Sources/MetalUI/RetainedSubtree.swift` (record, recorder, replay, key),
`Sources/MetalUI/RetainedLedger.swift` (snapshot, channel table, classification), tests below.
Edited: `EquatableComponent.swift`, `ContentMemo.swift` (`Entry.record`, the render session),
`Component.swift` (`ComponentPrepaint` optional payload), `Frame.swift` (`emit`, journals, the
snapshot reads, counters), `Passes.swift` (timestamp-read counter, hooks), `StateTable.swift` (mark
journal, bind journal, per-id version listing), `AnimationStore.swift` and `RasterCache` (touch
journals), `ElementGroup.swift`/`Element.swift` (`elementPrepaints`/`elementPaints` counters),
`Sources/MetalUITesting/FrameWork.swift`, `Sources/MetalUI/TestingHooks.swift`, the demo
(`Sources/MetalUIDemoContent/RetainedSubtreeDemo.swift`, `METALUI_RETAINED_DEMO=1`, own function,
`DemoStackBudgetTests`), `docs/probes/perf-harness` (a `bracket` scenario) and
`docs/probes/perf-baselines.sh`. Lane 2 does not start until lane 1 is verified.

**Steps.** (1) Counters and the `emit` funnel, behaviour-preserving; fixture pins recorded at their
baseline literals. (2) Ledger and the classification guard. (3) Recorder + replay for hitboxes,
focus, AX and scene, behind the switch, no key yet (always miss, record only). (4) The key and
eligibility; replay on. (5) Observation and the version journal. (6) Verify mode, differential, the
suite under verify. (7) Demo, docs, release readings.

**New `FrameWork` fields** (census covered by the harness regex): `elementRequests`,
`elementPrepaints`, `elementPaints`, `retainedHits`, `retainedMisses`, `retainedIneligible`,
`retainedSkippedPrepaints`, `retainedSkippedPaints`, `retainedLedgerSnapshots`, `retainedReplayedOps`.

### 8.1 Tests (name, red before, the mutation that must redden it)

"Red before" is the stub (the counters exist and report the whole-window figures; replay is off), so
each hit-count and conservation assertion fails on arrival with the literal shown.

| # | test (file `RetainedSubtreeWindowTests` unless noted) | red before | mutation that must redden it |
|---|---|---|---|
| 1.1 | `theBracketNodeDragReplaysEveryUnchangedSubtree(arm:)` (value, environment, panels): per drag frame `retainedHits + retainedMisses + retainedIneligible == contentEvaluations + contentSkips` (a refused occurrence, counted in `contentRefusals` only, has no memo entry and so no record; the sum with refusals is 32 in all three arms, §1); hits == 29 / 19 (the 11 refused never record) / up to 32 (panels, minus the occurrences that register a scroll region, tooltip or similar, e.g. the graph panel's `List`: predicted 31, fixed before the run); `elementPaints + retainedSkippedPaints == elementPaints(memo off)`; same for prepaints; scene counts 182 / 550 / 6 unmoved; `rasterizedPixels` unmoved | hits 0, skipped 0 | `hit = false` in `prepaintGroup`; `retainedSkippedPaints` not added |
| 1.2 | `aRetainedFrameEqualsAFreshFrameOverAScript` (differential, §7), three arms | green by construction against the stub, red once replay is on and any key component is missing | drop any one key component (1.3 names them) |
| 1.3 | `everyKeyComponentSeparates(component:)`: one arm per §4.2 item and per §4.1 item changes exactly that input between two frames and expects a miss (`retainedMisses == 1`) and an unchanged scene vs fresh | arms compile, hits wrongly 1 | omit that component from `ReplayKey.==` (one run per component) |
| 1.4 | `aPointerOrPressOrFocusInsideASubtreeMissesAndOutsideReplays` | hits 0 | `pointerInside` forced false; or forced true |
| 1.5 | `everyLedgerChannelMakesTheSubtreeIneligible(channel:)`: scroll region, popover, tooltip registration, drag source, surface, presentation record, geometry-change note, timestamp read, active animation, custom environment key, foreign state read, `collectsAccessibility` false | ineligible 0 | remove the channel from the snapshot comparison |
| 1.6 | `aDescendantStateChangeInvalidatesTheRecord` (non-equatable child `@State` button in an equatable parent; tap; the child's colour must change) | green (no replay) | skip the bind-journal version compare: the child's old colour is replayed |
| 1.7 | `anObservedReadInPaintInvalidatesTheRecord` (a custom `Element` reads an `@Observable` in `paint`) | green | `onChange` of the render session made a no-op |
| 1.8 | `aChildGetterReadInvalidatesItsEquatableParentsRecord` (the child's getter reads `model.x`, the parent is `==`-equal) | green | session bracket drops `finishComponent` |
| 1.9 | `aReplayedFrameKeepsItsAnimatedColourSlotsAlive` and `aReplayedFrameKeepsItsAccessibilityAndFocusSlotsAlive` (`StateTable.contains` after two replayed frames) | green | slot-mark journal not replayed |
| 1.10 | `aLiveAnimationNeverReplaysAndAnIdleKeyframeSubtreeDoes` | hits 0 | `hasActiveAnimations` not in the ledger |
| 1.11 | `everyFrameChannelIsClassified`, `everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant` (`Mirror`, in `MetalUITests`) | n/a (new) | add a stored property to `Frame`; to `EnvironmentValues` |
| 1.12 | the whole suite under `METALUI_VERIFY_RETAINED=1`: 0 verification traps (a record, not a test) | n/a | a deliberately wrong replay (hitbox order reversed) traps it |
| 1.13 | `aReplayTouchesItsRastersSoTheyAreNotDropped` (the same `ImageTexture` identity two frames on, `newTextures == 0`) | green | raster touches not replayed |
| 1.14 | `aBackdropInsideAReplayedSubtreeIsByteIdentical`, `aReplayInsideAnOuterShadowIsCapturedByIt` (the `.panels` inspector; an outer `.shadow`) | green | `emit` bypassed with `scene.insert` in replay |
| 1.15 | `replayedPrimitivesKeepTheirDrawOrderAmongSiblings`, `aReplayedHitboxKeepsTheRankingAtAnOverlap` (the fixture's overlapping nodes Fillet and Chamfer; a `.help` tooltip registration is ineligible, `SB-J`, so it is not the ranking's witness) | green | replay appends at the end of the frame |
| 1.16 | `aMissCostsTheOldWorkPlusFourSnapshots` (`retainedLedgerSnapshots == 4` per recorded occurrence: before and after each of prepaint and paint; elements' work equal to memo off) | counter absent | snapshot taken per element |
| 1.17 | `theRecordIsUnreachableFromAPlainImport`, `thePlainImportCannotTurnReplayOff` (typecheck guards, each mutated red once: make a member `public`) | n/a | `public` |
| 1.18 | `theOverlayCostIsLinearAndCounted` re-taken (GT-F) plus `aStaticLabelOverlayReplaysAndAMovingOneDoesNot` (§11) | passes unchanged | n/a |
| 1.19 | `theGlyphAtlasHasNoEvictionCaller` (greps `Sources/` and `Backends/` for `evictUnusedSince(` outside its definition; the only callers today are `AtlasEvictionTests`) | n/a | add a caller |

Step 1 also **converts the design phase's print-only fixture tests into `#expect` literals** (the counted baseline table of §1 becomes `theBracketNodeDragRebuildsTheWholeWindow`'s pins, red-on-arrival once replay lands) and deletes the debugging test `bracketDebugLocations`; a print is not a pin (`SB-Q`).

Predictions for 1.1 are fixed before the run and recorded in the record with the observed values.

## 9. Lane 2 (gated): the build skip

**Gate.** Lane 2 starts only if, after lane 1 is verified, the fixture's `.panels` arm in the
**release** readings has *build + layout kernel* at or above 35 % of `render` (the share the
retained subtrees would then still pay in full). **The baseline already reads 52 % (§1.1) and lane 1
only shrinks prepaint and paint, so the gate is expected to open with a wide margin** (a rough
projection: render about 3.7 ms after lane 1, build plus layout about 85 % of it); it is a
measurement to be taken, not a hedge. Below 35 % lane 2 is carried to C14b-2 with the design below
and the readings recorded; the placement memo (§10) is judged on the same readings.

**Design** (`SB-N`; refines `IV-H`, whose persistent-tree option is kept as the fallback):

1. **A graft, not a persistent tree.** Nodes of one component are allocated contiguously by
   `finishComponent` (post-order inside the component, parent registrars wrap after it returns). The
   record keeps a `LayoutSegment`: the index range, the side-table rows of that range (`nativeNodes`
   including closures, `childLists`, `leafKeys`, `spacerAxes`, `nativeParents` inside the range, grid
   marks) and the returned top-level ids' offsets. `LayoutTree.graft(segment)` appends the rows with
   an index shift under the current generation (O(subtree), no element work). `LayoutTree` stays a
   fresh tree per frame (C-3 unchanged).
2. **Replay needs no element records**, so a grafted subtree must replay prepaint *and* paint; a
   miss after the graft (key mismatch known only after layout, §3.1) **redoes the frame**: the
   window builds a second `Frame` with `retained: .disabled(entry)` for the missing entries (one
   settle-build-shaped redo, counted `retainedRedos`), with a per-entry backoff of 8 frames so a
   subtree that keeps missing is not rebuilt twice per frame. The common misses (a changed value, a
   `@State` write, an observation) are detected **before** the graft (they are what makes `==` or a
   version fail), so redo is the rare path; the translation case (`SB-H`) is where it would not be.
3. **The `StateTable` journal.** The build's frame-set deltas for the subtree (`marked`,
   `producedSlots`, `namedPositions`, `loopExtents`, `windowedParents`, `departedNames`) are recorded
   and re-applied through the table's own funnels so `sweep()` is unchanged; the lifecycle and
   animation touches and `noteNamed` calls are journalled the same way.
4. **Subtree placement memo** (record §104 spec §4.1's carried item): the segment also holds the
   subtree's rects *relative to its root*; the kernel places a grafted segment by translation when
   its root proposal and bounds equal the recorded, bit-exactly (the arithmetic is the recorded
   one, not a re-derivation, which is what §4.1 said a moved subtree's rects need).
5. **Redo policy** (`SB-R`): a redo is window-wide, not per entry; any redo suspends grafting for the whole window for 8 frames (so a resize or scheme drag, where every geometry key misses, costs one redo then plain builds), and the ambient part of the key (§4.2) is checked before the graft. Pins: `aResizeDragRedoesAtMostOncePerEightFrames` (red before: counter absent; mutation: backoff removed).
6. **Tests owed if built**, each with red-before and its mutation written in the lane's own table before code (a lane-2 test without both is not accepted, `SB-R`): `aGraftedSubtreeEqualsAFreshBuild`
   (a node-by-node differential of `LayoutTree`), `aRedoIsCountedAndBacksOff`,
   `aGraftedFrameKeepsTheStateTableSweepsExact`, `theBuildRecursionIsSkippedForAnUnchangedSubtree`
   (`elementRequests` conservation), `aSubtreePlacementHitEqualsAFreshRun` with the `IV-N`-style
   memo-off control, each with its mutation recorded.

## 10. The subtree placement memo

Ruled into lane 2 (`SB-O`): on the fixture the *root* placement memo never hits (the wires' sizes
change every frame), so a memo of the unchanged remainder is what layout needs, and a segment's
relative rects are exactly that. Lane 1 does not carry it: layout is 11 % (debug) and the reading
that decides is the release one; building a second memo before the retained products exist would
be measuring the wrong tree.

## 11. GT-F, re-taken

`theOverlayCostIsLinearAndCounted` passes unchanged at `e85cb07a` (N = 20, 100: layout 0, one
`placeGlyphs` and one seam measure per label per frame). Lane 1 adds `aStaticLabelOverlayReplaysAndAMovingOneDoesNot`:
N `.equatable()` labels over a camera-driven `GPUSurface`, the labels **static** (their offset not
changing): hits N, `placeGlyphs` 0, seam measures 0; the same labels **moving** by `.offset` (the
overlay case GT-F is about): every one misses on `activeOffset`, cost unchanged. **`drawText` stays
deferred** (`SB-P`): retained subtrees remove the cost of a label that does not move and none of a
label that does, and the moving label is the one a world-anchored overlay is; translated replay
(`SB-H`) is its owner, C14b-2, with `drawText` re-taken there.

## 12. Release timing of slice 1

The close-out owes record §104 §4's untimed question: what do slice 1's signature pass and the content
memo's `==` cost in a release build? Measured on the fixture's `.value` arm (`bracketSlice1Costs`, the
patch of `docs/probes/retained-subtrees`), release, per drag frame, three whole-process runs on a shared
Mac (the third run was the quietest, load average falling; the first two read 25-35 % slower
throughout, so absolute figures vary with the machine and the ratios are what repeats):

| quantity (ms per frame) | run 1 | run 2 | run 3 (quiet) |
|---|---|---|---|
| signature pass (844 nodes hashed per frame) | 0.195 | 0.166 | **0.136** |
| layout phase, layout memo on / off | 1.527 / 1.713 | 1.464 / 1.682 | 1.190 / 1.378 |
| net saving of the layout memo (off - on, the pass paid) | 0.186 | 0.218 | **0.188** |
| gross saving (net + pass) | 0.381 | 0.384 | 0.324 |
| content memo `==` (32 comparisons) | 0.009 | 0.009 | **0.008** |
| build phase, content memos on / off | 2.659 / 2.772 | 2.707 / 2.792 | 2.071 / 2.130 |
| net saving of the content memos | 0.113 | 0.085 | **0.059** |

* **The signature pass costs 0.14-0.20 ms per frame: 0.16-0.23 us per node, 2.1-2.5 % of a 6.2-7.9 ms
  render and 11-13 % of the memo-on layout phase.** It is about 42-51 % of the layout memo's gross
  saving, so **the layout memo is a net win of 0.19 ms per frame (3 % of render, 14 % of the layout
  phase)** on this tree, not the larger figure its counted win (1106 hits against 30 misses) suggests:
  the kernel is cheap per node here and the pass is not free. The root placement memo never hits
  in a node drag (§1), so none of the saving is the whole-window hit that record §104's overlay
  case enjoys.
* **The content memo's `==` is 0.008-0.009 ms per frame (0.25-0.3 us per comparison), under 0.2 % of a
  render and 14 % of the memo's own saving.** The memos' net saving of 0.06-0.11 ms (3-4 % of the
  build phase) is 29 skipped getters at 2-4 us each; the `==` is not the cost to worry about, the
  small size of what a getter does in this tree is.
* **Reading.** Slice 1 is a small, real, positive win on the node drag (about 0.25 ms of 6.2, 4 %) and
  an overlay-case win elsewhere; it was never going to be MetalCreator's 15 ms, which is why this
  item exists. Neither cost is a reason to change slice 1; the pass is the larger and `IV-M`'s counter
  (`layoutSignatureNodes`) already pins it. A perf harness scenario re-takes these figures:
  `zsh docs/probes/perf-baselines.sh release bracket` (public API, no hooks; total frame time only).


## 13. Demo and human checks

* **Demo**: `METALUI_RETAINED_DEMO=1` — a small bracket-shaped window (a reduced `BracketFixture`: eight
  nodes, the wires, a panel) with a counters strip (hits, misses, ineligible, replayed ops) and a
  checkbox for replay off, in its own function (`everyProductionTreeBuildsOnAOneMegabyteThread`),
  listed in `DemoStackBudgetTests`. The expectation: dragging a node shows hits ≈ all but the dragged
  node and its wires; replay off shows 0 and identical pixels.
* **Human checks** (`docs/verification/human-checks.md`, group `SB`, not run, an agent cannot):
  SB1 a real-window drag of a retained node looks identical with replay on and off (`Window` menu or
  env switch); SB2 hover and focus ring on a retained node appear and clear the frame the pointer
  or focus arrives and leaves; SB3 VoiceOver walks a retained subtree as a fresh one; SB4 a
  light/dark switch and a window resize repaint every retained subtree; SB5 an in-flight animation
  inside a retained region plays; SB6 a text field inside a retained region edits.

## 14. Carried, with owner and reason

| item | reason | owner |
|---|---|---|
| translated replay (an `.offset`/position change moves a retained subtree without a miss) | float association: a recorded `p + o₁` plus a delta is not always a fresh `p + (o₁ + d)`; exact only at dyadic scales and whole device pixels; needs the verify mode's reading first | C14b-2 (with the redo) |
| lane 2 (build skip, graft, placement memo) | gated on the release reading (§9) | C14b-2 |
| scroll regions, `List`/`ScrollView` inside a retained subtree | offsets are state read in paint; windowing reads the layout origin | C14b-3 |
| popovers, tooltips, drag sources, presentations inside a retained subtree | their registries are per-frame lists the window reads by position | C14b-3 |
| `GPUSurface` inside a retained subtree | a draw is a per-frame request | C14b-3 |
| custom environment keys | no equality; C14-c (environment epoch) | C14-c |
| finer scopes (modifier, `List` row, `ForEach` element) | no equality | C14-d |
| `drawText` | `SB-P` | C14b-2 |
| divergences | none taken; labels 395–404 unused | — |
