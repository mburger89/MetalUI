# 109 — Retained subtrees (C14b)

Branch `perf/retained-subtrees` from `e85cb07a`. Not a plan task: item C14b of the gpui-gap priority list (user
request 2026-10-02), the second half of C14 (record §104), requested by MetalCreator (gap PERF-b). Spec
`docs/superpowers/specs/2026-10-13-retained-subtrees-design.md` (design phase; amended by `SB-S`…`SB-AA`), fixture spec
`docs/superpowers/specs/2026-10-13-retained-subtrees-fixture.md`; rulings `SB-A`…`SB-AA` (`SB-A`…`SB-R` the design
phase's, `SB-S`…`SB-AA` lane 1's) in `docs/superpowers/2026-10-13-retained-subtrees-decisions.md` (next unused `SB-AB`);
probes `docs/probes/retained-subtrees/`. Divergence labels reserved 395–404: **none taken** (no public API, no
SwiftUI-visible behaviour).

**Status: LANE 1 BUILT — as paint replay, not prepaint-and-paint replay (`SB-AA`).** @@STATUS@@

## §1 The measurement (design phase, `e85cb07a`)

The fixture `Tests/MetalUITestingTests/BracketFixture.swift` is MetalCreator's bracket window (1440 x 900 at scale 2, 20
nodes of which 11 pass the cull, 21 wires, a top bar, a graph panel with a library `List`, a glass inspector, a full-window
`.onDemand` `GPUSurface`); the measured drag is the node drag (a press on Fillet at (20, 400), 20 events of 2 pt, one tick
each, then the release: 21 drawn frames). Counted at `e85cb07a` per drag frame (all three arms identical in the scene):
3 occurrences evaluate and 29 are skipped (`.value`), 182 rects, 550 glyphs, 6 images, 81 layout measures, 798 element
requests, 886 element prepaints, **1084 element paints**, 78 312 pixels rasterized for the two changed wires; over the 21
frames 2898 text-system measures and 2814 `placeGlyphs`. Phase shares of a render (spec §1, §1.1, dated, shared Mac):
**release** build 33 %, paint 32 %, layout kernel 19 %, prepaint 12 %; **debug** paint 61 %, build 18 %, layout 11 %, prepaint
9 %. Record §104's "build is 51 %" was a tree of bare `Text`s; the bracket window's leaves are rounded rectangles, clips,
strokes and paths, and paint is where they cost.

## §2 What lane 1 is, and the one thing the build changed in the design

**The design** (spec §3–§8) decided hit or miss in `EquatableComponent.prepaintGroup`, recorded hitboxes, focus
registrations, accessibility records and scene primitives, and replayed prepaint and paint. **The build did that first**
and it passed every existing test and the 1.2 differential; test 1.3 (`everyKeyComponentSeparates`, one arm per key
component) then reddened three arms, `.opacity(_)`, `.shadow(radius:)` and `.blur(radius:)` outside the occurrence: the
paint-only ambient (the opacity stack, the paint scopes of shadow, blur and composite) is pushed by ancestors' `paint`, after
every prepaint, and `isPaintScopeOnly` effects have no prepaint counterpart, so **a prepaint decision cannot see it**
(`SB-AA`). The remedies (a prepaint run at paint time under a saved prepaint context; a frame redo; a mirror stack at every
site that pushes an opacity or a scope) are lane 2's or unsafe, so lane 1 **replays paint only**: the decision, the key and
the recorder moved to `paintGroup`; prepaint always runs, in an observation window of its own (`SB-V`); `ComponentPrepaint` is
as it was but for a phase field. The first build's code is the record of what lane 2 inherits (`SB-AA`, cost if wrong).

**Mechanism as built** (`Sources/MetalUI/RetainedSubtree.swift`, 567 lines; hooks in `Frame`, `StateTable`, `AnimationStore`,
`ContentMemo`, `EquatableComponent`, `Component`):

* **The record** hangs off the memo entry (`ContentMemoStore.Entry.record`, swept with it): the scene operations paint made, the
  `StateTable.mark`s and `AnimationStore` touches it made, the element work it stands for, the replay key, the content
  serial it was made under and the versions of the `@State` slots bound under the component.
* **The key** (`ReplayKey`): the absolute rect of every top-level node, a hash of every descendant's rect and unrounded measured
  width (`LayoutTree.subtreeSignature`, one pass), and the ambient read **at paint** (`AmbientKey`): clip and radii, offset,
  layer, opacity, scale, content size, clip depth and bases, the open paint scopes (kind, effect map, depth, flattening flag,
  outer mask, shadow and blur parameters), `EnvironmentFingerprint` (every built-in `EnvironmentValues` field, the provided
  objects by identity; a custom key makes the occurrence ineligible), the transaction. Plus: the hovered, pressed or
  focused element is not the component or under it (`SB-X`), no observed read of the three windows changed, the content
  was not re-evaluated, no bound `@State` moved.
* **The scene** is recorded where the occurrence's own paint scopes end (`Frame.processScopes(_:from:depth:)`, the old
  `insertThroughScopes` loop split at a scope boundary; the six direct fast paths note boundary 0) and replayed from that
  boundary, so the outer scopes treat a replayed leaf as a fresh one (`SB-T`). Rasters are looked up in `insertIntoScene` as
  ever, so a replayed path keeps its texture and rasterizes nothing.
* **Taints** (the occurrence paints as before and is counted `retainedIneligible`): a `withState` or `write` in the window,
  a `GPUSurface`, a portal, a capturing or barrier scope inside, `noteActiveAnimation`/`requestAnotherFrame`/
  `noteInterpolation` (`SB-S`), a time-varying build, a custom environment key or a non-nil transaction animation at entry.
* **Verify mode** `METALUI_VERIFY_RETAINED=1`: a hit paints as a miss and compares the new record with the old one
  (`SB-W`); `METALUI_TRACE_RETAINED=1` prints why a record missed or an occurrence was ineligible.
* **Counters** (`FrameWork`): `elementRequests`, `elementPrepaints`, `elementPaints`, `retainedHits`, `retainedMisses`,
  `retainedIneligible`, `retainedSkippedPrepaints` (always 0), `retainedSkippedPaints`, `retainedLedgerSnapshots` (2 per
  recorded occurrence), `retainedReplayedOps`; `Window.testingRetainedSubtrees` (package) is the memo-off switch.
* **Demo** `METALUI_RETAINED_DEMO=1` (`RetainedSubtreeDemo.swift`, its own function, in `DemoStackBudgetTests`): eight nodes, seven
  wires, a counts strip and a "Replay" switch. Writing its model's initialiser with closures trapped on the 1 MB thread test
  (`SIGTRAP`: a closure formed in a `@MainActor` initialiser checks its executor when the tree is built off the main
  thread); it uses loops.

@@TESTS@@

