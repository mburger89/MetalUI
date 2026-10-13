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

## §3 The pins, their predictions and what the run read

Counts, never time. Every test below is in `Tests/MetalUITestingTests` (`RetainedSubtreeWindowTests`,
`RetainedSubtreeSemanticsTests`, `RetainedSubtreeOverlayTests`, `RetainedSubtreesBaselineTests`), `Tests/MetalUITests`
(`RetainedSubtreeInternalTests`, `RetainedSubtreeCompileGuards`, `RetainedSubtreeDemoTests`) or `Tests/MetalUILayoutTests`
(`SubtreeSignatureTests`); the mutation that must redden each is in §5.

| # | test | pins |
|---|---|---|
| step 1 | `theBracketNodeDragRebuildsTheWholeWindow(arm:)` | the design phase's prints as `#expect` literals with replay off (`SB-Q`): 3 / 29 / 0, 2 / 19 / 11 and 3 / 32 / 0 evaluations / skips / refusals, 886 prepaints, 1084 paints, scene 182 / 550 / 6, 78 312 px, 2898 / 2814 text-system calls |
| 1.1 | `theBracketNodeDragReplaysEveryUnchangedSubtree(arm:)` | every drag frame, three arms: hits / misses / ineligible 29 / 3 / 0, 19 / 2 / 0, 31 / 3 / 1; `hits + misses + ineligible == evaluations + skips`; `elementPaints + retainedSkippedPaints == the unretained frame's` frame by frame; prepaints, requests, measures, scene and rasters equal the unretained frame's |
| 1.2 | `aRetainedFrameEqualsAFreshFrameOverAScript` | cards under an offset, a shadow and a rotation, a stateful holder, an observed reader, an inspector with a material, a hover card and a scroll view; 24 script steps (hover, press, Tab, clicks, scroll, model writes, resize, appearance, scale): scene bytes, accessibility tree, hitbox list, Tab order, element bounds and hover events equal an unretained window's after every frame |
| 1.3 | `everyKeyComponentSeparates(arm:)` | 13 arms, one per component: top rect, clip, opacity, shadow, blur, rotation, offset effect, foreground, font, disabled, colour scheme, scale, content size; the probe re-records (the control too for the window's own events) and the scene equals the unretained one; `SubtreeSignatureTests` is the interior hash's arm at the kernel |
| 1.4 | `aPointerOrPressOrFocusInsideASubtreeMissesAndOutsideReplays` | the hovered, pressed or focused element under a card makes it miss, once the pointer leaves it records once and replays |
| 1.5 | `everyLedgerChannelMakesTheSubtreeIneligible(channel:)` | scroll view, `GPUSurface`, animation, custom environment key, `TextField`, popover: each occurrence ineligible, its plain neighbour still replays |
| 1.6 / 1.8 | `aDescendantStateChangeInvalidatesTheRecord`, `aChildGetterReadInvalidatesItsEquatableParentsRecord` | a non-equatable child's `@State`, and its getter's `@Observable` read, beat an always-equal parent's record |
| 1.7 / 1.7b | `anObservedReadInPaintInvalidatesTheRecord`, `anObservedReadInPrepaintInvalidatesTheRecord` | a custom element's paint read, and its prepaint read carried to paint in a `PrepaintState` |
| 1.9 | `aReplayedFrameKeepsItsAnimatedColourSlotsAlive` | a legacy box's `$anim-color` slot stays live over replayed frames (the marks are replayed) |
| 1.10 | `aLiveAnimationNeverReplaysAndAnIdleKeyframeSubtreeDoes` | an `.animation(value:)` flip: the opacity moves every frame and nothing replays; the idle keyframe animator replays; both replay once settled |
| 1.11 | `everyFrameChannelIsClassified`, `everyStateTableAndAnimationStoreChannelIsClassified`, `everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant` | `Mirror` guards: a stored property of `Frame`, `StateTable`, `AnimationStore` or `EnvironmentValues` with no row fails with its name |
| 1.13 | `aReplayTouchesItsRastersSoTheyAreNotDropped` | a replayed stroke keeps its `ImageTexture`: no pixel rasterized and no texture made in six frames |
| 1.14 | `aBackdropInsideAReplayedSubtreeIsByteIdentical` | a material's backdrop and a card under an outer shadow replay byte for byte |
| 1.15 | `aReplayedHitboxKeepsTheRankingAtAnOverlap` | two overlapping equatable cards: hitbox list and the click's recipient equal the unretained window's |
| 1.16 | `aMissCostsTheOldWorkPlusTwoSnapshots` | 2 ledger snapshots per recorded occurrence, 0 on a hit |
| 1.17 | `theRecordIsUnreachableFromAPlainImport`, `thePlainImportCannotTurnReplayOff` | plain-import guards: the counters type and the switch are `package` |
| 1.18 | `aStaticLabelOverlayReplaysAndAMovingOneDoesNot(labels:moving:)` | GT-F, §8 |
| 1.19 | `theGlyphAtlasHasNoEvictionCaller` | greps `Sources/` and `Backends/SDL/Sources` for an `evictUnusedSince(` caller |
| demo | `theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires` | 15 occurrences, 12 hits, 3 misses; replay off draws the same rects |

**Predictions fixed before the first run** (test 1.1): `.value` 29 / 3 / 0, `.environment` 19 / 2 / 0, `.panels` 30 / 3 / 2.
The run of the first design (prepaint and paint replayed, decided at prepaint) read 28 / 4 / 0 in the first nine drag frames
and 29 / 3 / 0 from the tenth, 19 / 2 / 0 throughout, and 29 / 4 / 2 then 30 / 3 / 2: the extra miss was the pointer over node
14's status badge, whose `.help` hitbox the conservative "pointer inside an owned hitbox" rule counts (`SB-X`). The paint-only
build reads 29 / 3 / 0, 19 / 2 / 0 and **31 / 3 / 1**: the one prediction that did not hold is the top bar (a menu `Picker`,
buttons, a `Menu`), predicted ineligible: its paint writes nothing a record cannot replay, so it replays.

**Findings the instruments made, in order** (each a fix or a ruling): (1) test 1.3's opacity, shadow and blur arms red on the
prepaint design (`SB-AA`); (2) the demo's model initialiser trapped the 1 MB thread test with `SIGTRAP`, a closure formed in a
`@MainActor` initialiser (fixed with loops); (3) the first release reading showed **no gain** (7.466 ms against 7.475):
two `withObservationTracking` windows per occurrence per frame (64 a frame) cost what the replay saved, so the build and
prepaint windows now open only for an occurrence with no record or a record that covers only its paint, and a hit opens
none (`SB-V`; 6.900 ms); (4) replay through the outer scopes cost about as much as the paint it replaced, so a record keeps
the final primitives too and replays them straight when every outer scope is a plain effect and no other recorder is open
(`SB-AB`; 6.569 ms); (5) on Linux the observation hop is asynchronous, three of the new tests wanted `rsSettle()`.

@@MUTATIONS@@

## §6 Counts

@@COUNTS@@

## §7 Timing (dated measurements; the Mac is shared; no pin reads a time)

**Machine.** MacBookPro18,2 / Apple M1 Max / macOS 27.0.1 / Swift 6.4, 2026-10-13. **Shared with other workflows** (load average
2 during the release runs below, 20-30 during the builds before them): read ranges and ratios, never a single figure. Wall clock is
an instrument; no pin reads it.

**Release, the node drag, public API** (`zsh docs/probes/perf-baselines.sh release bracket`; 30 drags of 20 events per arm, per-frame
total including the harness's input and tick; three whole-process runs, the median of each; the "before" is the same script and
fixture against a `git archive` of `e85cb07a`):

| arm | before, ms (3 runs) | after, ms (3 runs) | change |
|---|---|---|---|
| `.value` | 7.448, 7.422, 7.403 (median 7.422) | 6.546, 6.534, 6.524 (6.534) | **-0.89 ms, -12.0 %** |
| `.environment` (nodes refused, divergence 346) | 7.622, 7.596, 7.579 (7.596) | 7.605, 7.608, 7.597 (7.605) | +0.01 ms: the refusal gets nothing, and costs nothing |
| `.panels` | 7.459, 7.453, 7.417 (7.453) | 6.520, 6.511, 6.519 (6.519) | **-0.93 ms, -12.5 %** |

**Debug**, same script (two runs; the first is `--quick`): `.value` 54.79, 54.57, 54.59 -> 50.13, 48.76, 48.82 (-10.5 %); `.environment` 55.32,
55.09, 55.41 -> 55.42, 54.21, 54.08; `.panels` 54.03, 54.27, 54.65 -> 48.75, 48.22, 48.25 (-10.7 %). Debug paint is 61 % of a render
(spec §1), but the window's unretained parts (the top bar, the library `List`, the inspector in the `.value` arm; the graph panel in the
`.panels` arm) are most of it, so the replay's win is a smaller share there than the 29-of-32 hit count suggests.

**Phase shares, release** (the patched copy of this branch, `SB_RETAIN=1|0`, 30 drags x 22 frames, two whole-process runs each, ms per frame):

| arm | replay | build | layout kernel | prepaint | paint | sweeps | render | tick |
|---|---|---|---|---|---|---|---|---|
| `.value` | off | 2.127, 2.153 | 1.183, 1.190 | 0.798, 0.807 | **1.974, 1.985** | 0.19 | 6.285, 6.342 | 7.485, 7.537 |
| `.value` | on | 2.034, 2.136 | 1.153, 1.179 | 0.779, 0.813 | **1.158, 1.208** | 0.18 | 5.313, 5.536 | 6.461, 6.724 |
| `.environment` | off | 2.298, 2.279 | 1.200, 1.193 | 0.818, 0.813 | 2.001, 1.997 | 0.20 | 6.526, 6.492 | 7.746, 7.708 |
| `.environment` | on | 2.143, 2.261 | 1.151, 1.180 | 0.773, 0.814 | 1.907, 1.971 | 0.18 | 6.166, 6.431 | 7.321, 7.645 |
| `.panels` | off | 2.087, 2.122 | 1.176, 1.181 | 0.786, 0.798 | 1.960, 1.984 | 0.19 | 6.211, 6.291 | 7.383, 7.479 |
| `.panels` | on (before `SB-AB`'s tainted-recorder fast path) | 2.088, 2.227 | 1.165, 1.212 | 0.810, 0.852 | 1.443, 1.526 | 0.18 | 5.698, 6.022 | 6.875, 7.260 |

The replay removes **0.78 ms of 1.97 ms of paint** in `.value` (40 %), not the 80 % the element count suggests (1084 -> 178 element paints):
the rest of paint is the unretained window parts, the three occurrences that missed (the two wires rasterize 78 312 pixels on the CPU,
`GX-B`, every frame) and the replay itself (a `sample` of the `.value` arm put `replayPaint` at 3.3 % of frame time and the decision and key at
1.4 %). Build, layout kernel and prepaint did not move, as designed (the first build's sessions raised build by 0.12 and prepaint by 0.15 ms
before `SB-V`'s fix).

## §10 The lane 2 gate (`SB-C`)

Fixed before the reading: build plus layout kernel at or above 35 % of `render` in the `.panels` arm, release, after lane 1. **Reads
57 % in `.panels` (build 2.158 + layout 1.190 over render 5.698; `.value` 59.9 %: 2.085 + 1.166 over 5.425)**: the gate opens with a margin
of 22 points, and prepaint (0.8 ms, 14 %) joins the work lane 2 removes. Lane 2 (graft, journal, counted redo, prepaint replay, the subtree
placement memo) is designed in spec §9 and `SB-N`, `SB-O`, `SB-R` and is **not built in this lane**; `SB-AA` adds the paint-ambient problem
to its list.


## §8 GT-F, re-taken (`SB-P`)

`theOverlayCostIsLinearAndCounted` passes unchanged at every commit of the branch (N = 20 and 100: layout 0, one seam
measure and one `placeGlyphs` per label per frame, no raster or upload). The pair `aStaticLabelOverlayReplaysAndAMovingOneDoesNot`
(N = 20 and 100, five camera frames, every label an `.equatable()` component under an `.offset`): **static labels** are all
hits after warm-up and cost **0 `placeGlyphs` and 0 seam measures**; **moving labels** (the overlay case GT-F is about) all
miss on the offset's paint scope and cost the unchanged `frames * n` of each. **`MetalDrawContext.drawText` and its SDL twin
stay deferred** (`SB-P`): retained subtrees remove the cost of a label that does not move and none of one that does, which
is what a world-anchored label is; translated replay (`SB-H`, carried to lane 2) is the owner, and `drawText` is re-taken there.

## §9 Slice 1's costs in release (owed by record §104 §4)

Measured in the design phase (spec §12; the instrument is `docs/probes/retained-subtrees/phase-timing.patch`,
`bracketSlice1Costs`) on the fixture's `.value` arm, release, per drag frame, three whole-process runs, shared Mac: the
signature pass (844 nodes hashed) costs **0.14-0.20 ms** (0.16-0.23 us per node, 2.1-2.5 % of a 6.2-7.9 ms render, 11-13 % of
the memo-on layout phase); the layout memo's net saving is **0.19 ms** per frame (3 % of render; gross 0.32-0.38 ms, the pass
paid 42-51 % of it); the content memo's `==` costs **0.008-0.009 ms** per frame (32 comparisons, 0.25-0.3 us each) and the
content memos save 0.06-0.11 ms net (29 skipped getters at 2-4 us). Neither is a reason to change slice 1; this item
exists because their combined win on the node drag is 4 % of a frame.

## §11 Carried, with owner and reason

| item | reason | owner |
|---|---|---|
| prepaint replay (hitboxes, focus, accessibility, tallies) | the decision cannot be taken at prepaint: paint-only ambient (`SB-AA`); the first build's code and the tests that found it are the branch's commit `0683d847` | lane 2 / C14b-2 |
| the build skip, the graft, the placement memo | gated on the release reading (§10) | C14b-2 |
| translated replay (a moved subtree without a miss) | float association, `SB-H` | C14b-2 |
| read-only `withState` so a `TextField`, `ScrollView` and `List` can replay | the table cannot tell a read from a rewrite | C14b-3 |
| popovers, presentations, `GPUSurface` inside a retained subtree | per-frame requests, `SB-J` | C14b-3 |
| custom environment keys | no equality | C14-c |
| finer scopes (modifier, `List` row, `ForEach` element) | no equality | C14-d |
| `drawText` | `SB-P` | C14b-2 |
| divergences | none taken; labels 395-404 unused | - |

## §12 Instruments, demo, human checks

* `METALUI_VERIFY_RETAINED=1` (`SB-W`): run the whole suite under it once (§6); a trap names the first difference between the
  record a replay would have used and a fresh one. `METALUI_TRACE_RETAINED=1`: why a record missed, why an occurrence was ineligible
  and which session fired. `zsh docs/probes/perf-baselines.sh release bracket` (three runs, the median): the public-API harness
  prints the retained counters on the last frame; the before column is the same script against a `git archive` of `e85cb07a`
  with `BracketFixture.swift` and the harness copied in. `docs/probes/retained-subtrees/phase-timing.patch` (README there) gives
  the phase shares; the patched copy of this branch toggles replay with `SB_RETAIN=0`.
* Demo: `METALUI_RETAINED_DEMO=1 swift run MetalUIDemo`: drag a node, read hits / misses / ineligible of the last frame; untick
  "Replay" and the same drag reads 0 hits.
* Human checks `docs/verification/human-checks.md` group **SB** (SB1-SB6), not run: an agent cannot.
