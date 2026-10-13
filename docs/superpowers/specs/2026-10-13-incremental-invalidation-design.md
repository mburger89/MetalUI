# Incremental invalidation — design (C14)

Item C14 of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**), requested by MetalCreator (gap PERF-b in its `docs/metalui-gaps.md`).
Branch `perf/incremental-invalidation` from `f6f865c1`. Prefix `IV-`; rulings in
[`../2026-10-13-incremental-invalidation-decisions.md`](../2026-10-13-incremental-invalidation-decisions.md)
(next unused `IV-N`); record `docs/record/104-incremental-invalidation.md`.
Divergence labels reserved for this branch: 345–354. Probes:
`docs/probes/swiftui-incremental-invalidation.swift`,
`docs/probes/swift-observation-nested-scopes.swift`,
`docs/probes/incremental-invalidation/` (phase-timing instrument and readings).
SwiftUI is the design authority where it has an answer; gpui has none to borrow
(it re-renders a view entity when the entity is `notify`-ed and has no retained
layout tree — every `request_layout` is whole, and its `Element` caching is by an
explicit `cx.notify()` boundary); where this spec says "SwiftUI" the claim is a
probe arm, where it says "MetalUI" the claim is a design choice.

## 0. The problem, in numbers

Today every observed change (`@Observable` read in a frame, `@State` write, any
`Window.environment` write) dirties the **window**, and the next frame is built
whole: root closure, every `Component.content`, every `requestLayout` /
`requestGroupLayout` recursion, the layout kernel over the whole tree, prepaint,
paint, sweeps (`Window.buildAndAdoptFrame`, `Frame.renderOutsideDispatch`).
RX-K's machinery (one `withObservationTracking` around the whole build, the
`RedrawSentinel` flush, `isFlushing`, both branches of `markDirtyFromObservation`)
is the reason a change reaches the window, and it is load-bearing.

**Measured** (`docs/probes/incremental-invalidation/README.md`; release, one
`@Observable` leaf written per frame, a 3-ary tree of `Component`s with one
`Text` per leaf; counts exact, times are shares and move 10% between runs):

| leaves | nodes | build | layout kernel | prepaint | paint | sweeps | render |
|---|---|---|---|---|---|---|---|
| 81 | ~202 | 1.006 ms (51%) | 0.363 (19%) | 0.201 (10%) | 0.265 (14%) | 0.113 (6%) | 1.955 |

Inside build, the `Component.content` getters are 21%; the other 79% is the
recursion registering nodes, ids, state marks and bindings. A release `sample`
shows no hot spot (retain/release, dictionary finds, `Hasher`, generic-metadata
lookups, exclusivity checks, spread everywhere), so **only doing less work
helps**. One frame of that tree, counted (`IncrementalInvalidationBaselineTests`,
committed): 1 build, **81 leaf bodies and 40 branch bodies evaluated**, 81 leaf
measures, 832 layout-cache hits and 337 misses, **162 text-system measures**, 81
`placeGlyphs`. MetalCreator's bracket graph (20 nodes, 12–13 ms release) is 50×
heavier per node and, by its own `sample`, 43% in `requestLayout` (the build
phase) and the rest in paint — the layout kernel is not where its time goes,
which is why the first slice cannot be layout alone (§2).

## 1. What a full fix needs, and why it is not one item

SwiftUI's behaviour (probe `swiftui-incremental-invalidation.swift`): a change
re-evaluates **exactly the bodies that read the changed observed property**
(R, T, O, ES); a parent's re-evaluation skips a child whose stored inputs are
plain equal values or the same class instance (S, U, V); a *custom* `Layout`
container gets **no** per-sibling layout skipping (L-colour re-measured every
row). So "re-measure only dirty paths" is this item's goal, not SwiftUI's
behaviour; "re-evaluate only readers" is both.

MetalUI cannot reach SwiftUI's retained attribute graph in one item. The
obstacles, each found by reading the code, each ruled in `IV-H`:

1. **The layout tree is per frame** (`Frame` allocates a `LayoutTree`; ids carry
   its generation, C-3). A skipped subtree has no nodes unless the tree persists.
2. **A `Component`'s retained record cannot be replayed**: `prepaint`/`paint`
   are `mutating` and write into the content and its layout through
   `ComponentLayout`'s box; a second run over the same box starts from a
   post-paint state, and nested boxes are shared by a struct copy. Idempotence
   across ~100 element types is unproven and apps may write their own `Element`s.
3. **A subtree contributes to ~110 per-frame channels** (`Frame`'s stored
   properties alone: hitboxes, focus registry, accessibility emissions, scroll
   keys, presentation/toolbar records, collected preferences, named spaces,
   lifecycle and animation touches, `StateTable`'s marks and loop extents).
   Skipping the recursion means replaying every channel.
4. **Observation does not attribute**: access lists merge upward (probe
   `swift-observation-nested-scopes.swift`, N and M), so a scope session nested
   in the window's whole-frame session cannot be told from it. Per-scope
   attribution therefore needs the whole-frame session gone, and then every read
   site (root closure, `ForEach` rows, `Canvas` draws, user layouts) must be
   wrapped or it goes silently stale. The whole-frame session is today's safety net.
5. **`EnvironmentValues` cannot be compared** (`[ObjectIdentifier: Any]`;
   `Window.environment` doc), so no memo can tell whether the environment a
   `Component` reads changed.

## 2. The first slice (this item, two lanes, sequential)

Rule `IV-A`…`IV-K` give the reasoning. The slice is the two halves of the user's
request that can land **behind unchanged semantics** and that the evidence
supports; everything that skips the build *recursion* is carried (§7).

**Lane 1 — layout memo** (automatic; no API). A window-owned `LayoutMemo` keyed by
a **structural signature**, never by node id (so C-3 and "the cache lives for one
call" hold: the per-call run cache is untouched, and the memo holds no
`LayoutNodeID`). Leaves opt in with a key; an unkeyed leaf makes its ancestors
unmatchable and leaves its siblings alone. Two uses: **(M)** `measureNative`
consults `(signature, proposal) -> LayoutMeasurement` after the run cache misses;
**(P)** a run whose root signature, proposal and bounds equal the previous run's
copies the previous run's unrounded rects and measured widths and skips both
measurement and placement. This is what a drag by `.offset`/`.scaleEffect`, a
colour/opacity/shadow change, or a `GPUSurface` redraw costs in layout: one
lookup.

**Lane 2 — content memo** (opt-in API). `Component.equatable()` (SwiftUI's
spelling) where `Self: Equatable`: the `content` getter is not evaluated again
while the component's value is `==` to its last evaluation's, its own `@State` is
unwritten, and the observed properties its last evaluation read are unchanged
(a per-memo observation session, §4.3). The pristine getter result is reused and
everything after it — `requestGroupLayout`, layout, prepaint, paint, sweeps —
runs exactly as today on an equal value, which is why no channel needs replay and
no existing behaviour moves.

**What this does and does not buy** (the numbers `IV-G` rules):

| per changed frame, 81 leaves, one leaf written | today | after lane 1 | after lanes 1+2 |
|---|---|---|---|
| builds | 1 | 1 | 1 |
| leaf / branch bodies evaluated | 81 / 40 | 81 / 40 | **1 / 0** (all `.equatable()`) |
| layout measure calls | 81 | **≤ 2** | ≤ 2 |
| layout cache misses | 337 | **≤ 2·(L+3) = 14** | ≤ 14 |
| text-system measures (seam) | 162 | **≤ 4** | ≤ 4 |
| a pure offset/colour change: layout measure calls / misses | 81 / 337 | **0 / 0** | 0 / 0 |
| `placeGlyphs` (paint) | 81 | 81 | 81 |
| build recursion, prepaint, paint | whole | whole | **whole** |

Time, by the shares of §0: lane 1 removes up to the layout kernel's 19% (more with
CoreText text, where a seam measure costs microseconds); lane 2 removes the getters'
21% of build (≈ 10% of render) in the synthetic tree and whatever a real
`content` costs in an app. **Together ≈ 25–30% of render in the synthetic tree.
The target PERF-b names (8.3 ms for 20 bracket nodes) is not reached by this
slice and the spec does not claim it**; reaching it is `IV-H`'s retained subtrees
(build 51% + prepaint 10% + paint 14%), carried as C14-b.

## 3. Public API (lane 2)

```swift
extension Component where Self: Equatable {
    /// SwiftUI's `View.equatable()`: ...
    public func equatable() -> EquatableComponent<Self>
}
public struct EquatableComponent<Content: Component & Equatable>: ElementGroup {
    // GroupLayout == ComponentLayout<Content>, GroupPrepaint == ComponentPrepaint<Content>
}
```

* `EquatableComponent` has **no initialiser** outside the module (a typecheck
  guard pins it with a plain import); it adds **no identity level and no cursor
  index** beyond the wrapped `Component`'s own (the same `GlobalElementID`, the
  same `@State` slots, the same `noteNamed`) — `MC-A`/`MC-C` numbering unmoved.
* Modifiers after it wrap it as for any `ElementGroup` (`ModifiedContent`).
* `==` **decides** (no divergence: probe arms S2/S3 show SwiftUI honours `==` for
  closure and class inputs too; the first-bump re-run in arm S was an artefact,
  `IV-L`): MetalUI honours the author's `==` for every stored property. This is the whole contract: *the content is a
  function of the value, the component's own `@State`, and the `@Observable`
  properties it reads.* A `Binding` input is a value; an author who reads
  `binding.wrappedValue` in `content` includes it in `==`.
* **Refused, evaluated every frame, counted** (divergence 346): a `Component` that
  declares `@Environment` or `@FocusState`. `FrameWork.contentRefusals` counts
  frames×components; a test or an author reads it. No trap, no log line.
* Public additions: `Component.equatable()`, `EquatableComponent` (+ its
  `GroupLayout`/`GroupPrepaint` typealiases are inherited), `FrameWork`'s four
  fields (§5). Each owes a doc comment and a `closeout-inventory-map.tsv` row
  (class A for `equatable()`; D for the refusal, 346; M for `EquatableComponent`
  and the `FrameWork` fields), and `zsh docs/probes/closeout-inventory-check.sh`
  and `closeout-undocumented.sh` print nothing.
* **No new `PlatformWindow`/`Platform`/`WindowRenderer`/`TextSystem` requirement**,
  no `Handlers` member, no `Element` hook, no new `StyledElement`/`LayoutModifier`
  kind, no shader. No migration note (nothing a conformer must add).

## 4. Design

### 4.1 Layout memo (lane 1)

**Signature.** A 128-bit value (two independent 64-bit mixers over the same
canonical byte stream; a collision is a silently wrong layout, so 64 bits is not
enough). Computed by **one post-order pass over the nodes reachable from the run's
root, at the start of every `computeNativeLayout`/`measureNativeLayout`** — not at
registration — because three kinds of context are written after a node registers:
the spacer axis a stack marks (`spacerAxes`, CN-C), grid row/cell marks (tokens are
fresh each frame, so the pass normalises them to "same row / different row"
pairs, GR-A) and `nativeParents`. Per kind it hashes a tag, every parameter of the
`NativeNode` case (`frame`'s nine optionals, `padding`'s four edges, `linearStack`'s
axis/spacing/alignment/baseline, `grid`'s resolved `NativeGridPlan`, `overlay`'s
alignment, …), the node's contextual marks and its children's signatures in order.
`custom(any ProposalLayout)` hashes the layout value when it is `Hashable`
(dynamic cast) and is unkeyed otherwise. A `leaf` hashes its **key**; `nil` key
means *unique per run* (a counter), which taints exactly the ancestors.

**Leaf keys (this lane keys only these; everything else is unkeyed):** plain
`ProposalText` and plain legacy `Text` (key = the string, the resolved `FontKey`,
every `TextStyleResolution` field the measure reads, the line limit, the
`ObjectIdentifier` of the `TextSystem` and the scale factor — i.e. the arguments
the closure passes to the seam), `Divider` (axis), a built-in `Shape` leaf
(its type tag and corner parameters), the gradient fill leaf (constant). Rich text,
images, `GPUSurface`, controls' leaves and third-party layouts stay unkeyed in this
item. Adding a key to a site is a one-line change plus a "key covers the closure"
test (§6).

**(M) Measurement memo.** `[MemoKey(signature, proposal)] -> LayoutMeasurement`,
consulted in `measureNative` after the run cache misses and before the body runs;
a hit counts `memoHits`, not `cacheMisses`; a computed result for a **keyed**
subtree is stored. Entries untouched for two runs are dropped (two-generation
sweep, as `ShapingCache`), so memory is bounded by two frames' distinct keyed
subtrees.

**(P) Root placement memo.** After a run, store `(rootSignature, proposal, bounds)
-> [(unrounded rect, measuredWidth)] in traversal order`. A run whose triple is
bit-equal writes the stored rects and widths by traversal order and runs the same
`roundNativeStoredRects(root)` as today. Subtree placement memo (a moved subtree's
rects need the same arithmetic as a fresh placement to stay bit-exact) is carried.

**Invariants.** Pixels 0 px (fourteen images); measure closures of keyed leaves are
pure (no side effects; a text leaf's only is touching the `ShapingCache`, whose
two-frame lifetime merely re-shapes on a later miss); `LayoutTree` ids, generations,
`isLayingOut`, `setLayout`'s trap and the depth guard are untouched; the memo is
attached to a tree by `Frame` only (a tree built by a `LayoutTree`-level test has
none, so `NativeLayoutWorkTests` & co. are unmoved). A package-only
`LayoutMemo.verifies` flag recomputes every hit fresh and `precondition`s bit
equality; the whole suite is run once with it on (§6, test 1.12).

### 4.2 Content memo (lane 2)

State per memoized component, in a window-owned `ContentMemoStore` (hosted on
`StateTable`, which `Frame` already receives; keyed by `GlobalElementID` plus the
component's `ObjectIdentifier`):

```
Entry { typeID, previous: C, pristine: C.Content, stateVersions: [UInt64],
        token: ScopeToken (@Observable), serial: Int, stale: Bool, touched: Bool }
```

`requestGroupLayout` for an `EquatableComponent<C>` runs the bare `Component`'s
code verbatim (id, `noteNamed`, `StateBinder.bind`, cursor) and replaces only
`var materialized = content`:

1. **Eligible?** `C`'s cached reflection shape (`StateBinder.Shape`, extended) has
   no `Environment` and no `FocusState` child; else evaluate normally and count a
   refusal.
2. **Hit?** an entry exists with the same `typeID`, `!stale`, `previous == self`,
   and the versions of `self`'s own `@State` slots (`StateTable.entryVersion`,
   bumped by `write`/`withState`-mutation) equal the recorded ones. A hit
   `materialized = entry.pristine` (a value copy) and counts `contentSkips`.
3. **Miss:** `entry.serial += 1`, then `entry.token.tick &+= 1` (fires and consumes
   the previous session; its handler sees a stale serial and does nothing), then
   `withObservationTracking { _ = entry.token.tick; materialized = content } onChange:
   { ... }`; store `previous = self`, `pristine = materialized` (a copy taken
   **before** `requestGroupLayout` runs on `materialized`, so the retained value
   never carries a layout, prepaint or paint mutation of its own), the versions,
   `stale = false`. Counts `contentEvaluations`.
4. The handler (nonisolated, both branches of `markDirtyFromObservation`: main
   thread `assumeIsolated`, else a `Task { @MainActor }`) checks its captured
   serial against the entry's: equal means a real change, so `stale = true` and
   `Window` is dirtied through the **same** entry point `markDirtyFromObservation`
   uses (the `isFlushing` guard and `observationDirtyings` included); unequal is a
   flush and does nothing.
5. `Frame` end: entries not touched this frame are removed and their token written
   (their session fires once, harmlessly); live sessions never exceed live entries
   (test 2.7). A session is **not** read through the window's `RedrawSentinel`, so
   the per-frame flush never invalidates a memo; and because a skip frame re-arms
   nothing, an unchanged memoized component adds no observer per frame.

The window's own whole-frame session is unchanged. A memo evaluation's reads merge
into it (probe N), so the window is also dirtied by the whole-frame session when
a memoized component's property changes — harmless, it is dirty anyway — and a
**skipped** component's reads are *not* in the whole-frame session (it was not
re-evaluated), which is exactly why the memo's own session must dirty the window
(test 2.2 pins the stale-content failure this prevents).

### 4.3 Interactions (each ruled in `IV-F`; none moves)

Every phase after the getter runs on the same value, so the rulings are about why
nothing is skipped by accident. Identity/`ID-C`/`ID-R`/`DD-C` resets and
`noteNamed` run in `requestGroupLayout` (kept); the lifecycle drain, `.task`,
`onChange` values and `GeometryChangeScope` are elements in the retained value,
presence by build membership (kept); animation transactions and `AnimationStore`
touches happen in `requestGroupLayout`/paint (kept); `List` windowing and `TB-AH`
(rows are produced by `List.requestLayout`, not a getter); presentations,
toolbar, preferences (registered by elements, kept); focus, `@FocusState` (refused),
accessibility emission, the gesture arena, the hitbox list and its one ranking
(registered in prepaint, kept); text input (`TextField` is an element; its state is
`StateTable` entries; kept).

## 5. Counters and the harness

`NativeLayoutWork` (package) gains `memoHits`, `memoMisses`, `memoRootHits`, `signatureNodesHashed` (`IV-M`);
`FrameWork` (public, MetalUITesting) gains `layoutMemoHits`, `layoutMemoMisses`,
`contentEvaluations`, `contentSkips`, `contentRefusals`, default 0, added to `init`
and `+`; `TestingHooks.swift`/`BuildWork` carry them. `docs/testing.md` documents
the fields (record phase). The baseline test's `IVStats` counts bodies at user
level, so the content pins do not depend on the new counters.

## 6. Lanes, files, tests

Two lanes, **sequential** (Agents run one at a time; lane 1 first so `FrameWork`
has the layout fields), disjoint files except `FrameWork.swift`/`TestingHooks.swift`
(lane 1 adds the layout fields; lane 2 appends the content fields in its own
commit). Both lanes follow `docs/practices/verifying-tests-can-fail.md`: each test
red first (red-before below), each mutation applied to the **named declaration** and
**its spelling** recorded, the full unfiltered suite after each, `git status
--short` after each, every reddened test named.

### Lane 1 — layout memo

Files: `Sources/MetalUILayout/LayoutMemo.swift` (new), `LayoutTree.swift` (signature
pass, `newNativeLeaf(key:measure:)`, memo consults), `NativeLayoutRun.swift`
(`NativeLayoutWork` fields), `NativeGrid.swift` (plan hashing);
`Sources/MetalUI/Passes.swift`, `Frame.swift` (`requestNativeLeaf(key:measure:)`,
attach the memo, end-of-frame sweep), `AnimationStore.swift` (hosts the window-owned
memo, as it hosts `rasters`), `ProposalText.swift`, `Text.swift`, `DividerView.swift`,
`Shape.swift`, `Gradient.swift` (keys), `TestingHooks.swift`,
`Sources/MetalUITesting/FrameWork.swift`; tests below; the closeout map and
`docs/probes/closeout-public-api.tsv` re-record. `Backends/SDL` untouched.

| # | test (file) | what it pins | red before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aSteadyOffsetFrameMeasuresNothing` (`LayoutMemoWindowTests`) | GT-A's overlay re-take (§8): N moving `.offset` labels over a `GPUSurface`: per frame `layoutMeasureCalls == 0`, `layoutCacheMisses == 0`, `layoutMemoHits >= 1`, seam `measures == 0`, `places == N` | the same asserts with the memo disabled (`LayoutMemo.isEnabled = false`) read N+1 / N+2 / 0 / 2N | `isEnabled` forced true but `(P)` lookup always misses: reddens `layoutCacheMisses == 0` |
| 1.2 | `oneChangedTextRemeasuresOnlyItsPath` (`LayoutMemoWindowTests`) | baseline tree L=2,3,4, one leaf's text changes: `layoutMeasureCalls <= 2`, `layoutCacheMisses <= 2*(L+3)`, seam `measures <= 4`; derived by hand from the stack algorithm (`CN-B`…) before the run and replaced by literals | `isEnabled = false`: 81 / 337 / 162 at L=4 | drop the key's string from `ProposalText`'s key: the changed leaf hits stale (reddens 1.3 too) |
| 1.3 | `aMemoHitEqualsAFreshLayoutBitForBit` (`LayoutMemoWindowTests`) | with `LayoutMemo.verifies` on, a 40-step script (resize, text change, spacing change, font size, scale factor 1↔2, theme, section toggle) never traps and every rect equals a fresh tree's | verify mode absent (does not compile) → red by the stub returning a wrong rect | any signature field omitted (see 1.5) |
| 1.4 | `anUnkeyedLeafTaintsOnlyItsAncestors` (`LayoutMemoTests`) | tree with an unkeyed leaf: ancestors miss, siblings' subtrees hit | memo off | key `nil` mapped to a constant instead of a per-run unique |
| 1.5 | `everyRegistrarParameterIsInItsSignature` (`LayoutMemoTests`) | table-driven over every `LayoutTree.newNative*` parameter (two values each; the 13 registrars): the signature differs | memo off (signatures equal trivially → the test constructs `LayoutMemo` directly) | omit one parameter from one case's hash (`frame.maxHeight`) — a named arm reddens |
| 1.6 | `aSpacersSignatureCarriesItsStacksAxis` (`LayoutMemoTests`) | the same spacer under a vertical then a horizontal stack has different signatures (CN-C) | hashing at registration instead of the post-pass | hash the spacer's own case only |
| 1.7 | `aGridRowMarkIsNormalisedNotHashedAsAToken` (`LayoutMemoTests`) | two frames of one grid have equal signatures though their tokens differ (GR-A) | hashing raw tokens | hash the raw token |
| 1.8 | `theMemoHoldsNoNodeID` (`LayoutMemoTests`) | a `Mirror` walk of `LayoutMemo` finds no `LayoutNodeID`; a memo outlives a tree (C-3) | — | add a `[LayoutNodeID: …]` member |
| 1.9 | `aWindowResizeAndAScaleChangeMissByProposalAndKey` (`LayoutMemoWindowTests`) | resize misses `(M)`; scale 1→2 changes the text key | memo off | omit the scale factor from the text key |
| 1.10 | `aRootPlacementHitRestoresMeasuredWidths` (`LayoutMemoWindowTests`) | after a `(P)` hit, `Text.paint`'s wrap width equals a fresh run's (same glyph runs) | — | skip restoring `measuredWidths` |
| 1.11 | `memoOffFramesAreUnchanged` | `FrameWork` of a first frame (cold memo) equals f6f865c1's literals in the existing multi-frame work pins; `NativeLayoutWorkTests` & co. unmoved | — | attach the memo to a bare `LayoutTree(generation:)` |
| 1.12 | whole-suite run with `LayoutMemo.verifies` forced on (`METALUI_VERIFY_LAYOUT_MEMO=1`, read once at launch) | 0 traps over 3566+ tests | — | — |
| 1.13 | `thePlainImportCannotReachTheMemo` (typecheck guard) | `LayoutMemo`, `LayoutTree.memo` are `package` | — | make `memo` public |

Existing pins that move, by name, with the new literals recorded in the record:
`SurfaceTextOverlayCostTests.theOverlayCostIsLinearAndCounted` (its doc says it
moves: the layout counts and `measures` go to 0), and any window-level multi-frame
count in `HarnessWorkTests`/`MeasurePerformanceTests` that reads
`layoutCacheMisses`/`layoutMeasureCalls` on a second frame (to be listed by
`grep -rn 'layoutMeasureCalls\|layoutCacheMisses\|lastNativeLayoutWork' Tests` at the
start of the lane and each re-derived by hand).

### Lane 2 — content memo

Files: `Sources/MetalUI/EquatableComponent.swift` (new), `ContentMemo.swift` (new:
store, entry, `ScopeToken`), `Component.swift` (shared entry point
`requestGroupLayoutCore(…, memo:)`; the bare `Component` path keeps its code and its
mutation notes), `StateTable.swift` (`entryVersion`), `StateReflection.swift`
(shape kinds), `Window.swift` (the dirty entry point shared with
`markDirtyFromObservation`; store hosted on `StateTable`), `Frame.swift` only for the
end-of-frame sweep call (one line, the one overlap with lane 1, sequential),
`FrameWork.swift`/`TestingHooks.swift` (append), `Sources/MetalUIDemoContent/`
(demo section in its **own function**), `Sources/MetalUIDemo` (env var), tests,
closeout map, `docs/probes/closeout-public-api.tsv`.

| # | test (file) | what it pins | red before | mutation that must redden it |
|---|---|---|---|---|
| 2.1 | `anEqualComponentSkipsItsContent` (`ContentMemoWindowTests`) | baseline tree, every `IVBranch`/`IVLeaf` `.equatable()`, L=2,3,4, one leaf written: `IVStats.leaves == frames`, `branches == 0`, `contentSkips == frames * (components - 1)`, builds `== frames` | `ContentMemo.isEnabled = false`: 81 / 40 (the committed baseline) | store `previous` after the compare instead of before |
| 2.2 | `anObservedReadBeatsAnEqualValue` | `==` always true, content reads `cell.value`, the cell changes: content re-evaluates once, and the drawn text is the new value | — | remove the session (`onChange` empty): stale text, red |
| 2.3 | `anOwnStateWriteBeatsAnEqualValue` | `==` always true, a button writes the component's `@State`: re-evaluates, text updates; **2.3b** (`IV-L`): a button closure built at frame 1 is invoked after 5 skipped frames and still writes | — | compare no versions |
| 2.4 | `anUnequalValueReEvaluates` | control: an input differs, content re-evaluates, the subtree below it still skips | — | `==` replaced by `true` in the entry check |
| 2.5 | `aComponentWithAnEnvironmentOrFocusStateIsRefusedAndStillEvaluates` | `contentRefusals == frames`, content correct after an environment write | — | drop the shape check: a stale environment read |
| 2.6 | `aSkippedSubtreeKeepsItsStateAndItsIdentity` | descendants' `@State` (counter, text field text, focus) retained over 6 skipped frames; `theSevenRetentionSlotsAreMutuallyDistinct` unmoved; `ID-C` reset when an `if` inside a *re-evaluated* content flips; `.id()` outermost | — | skip `noteNamed` on a hit |
| 2.7 | `sessionsNeverExceedLiveEntries` | (`IV-L`: a component re-evaluating every frame lets the window idle) 200 re-evaluating frames then 200 skipped: armed sessions <= live entries (`package` counter); remove the component: its session count returns to 0 after one frame | — | drop the serial check: flush callbacks dirty the window every frame (the window never idles; `runUntilIdle` throws) |
| 2.8 | `aMemoSessionIsNotFlushedByTheWindowSentinel` | a skipped component survives 50 forced redraws without re-evaluating | — | read `redrawSentinel.tick` inside the memo session |
| 2.9 | `aMemoizedSubtreeDrawsTheSceneOfAnUnmemoizedOne` | **differential**: the same tree with and without `.equatable()`, 12 scripted writes: `Scene` rect/glyph/image arrays, hitboxes (`testingHitboxes`), accessibility tree and focus order equal after every frame | — | pristine copy taken after `requestGroupLayout` (stale layout state leaks) — reddens this |
| 2.10 | `lifecycleAnimationAndListInsideAMemoizedComponent` | `.onAppear`/`.onDisappear`/`.task` counts, a `keyframeAnimator` trigger, a `List` windowed row's TB-AH retention, a presentation: identical to the unmemoized tree | — | key the entry by type alone, ignoring the id (`IV-M`) |
| 2.11 | `aPlainImportCannotConstructAnEquatableComponent` + `equatableIsOfferedOnlyToEquatableComponents` (typecheck guards) | initialiser unreachable; `.equatable()` on a non-`Equatable` component does not compile | — | make the initialiser public |
| 2.12 | (not a test, `IV-M`) re-run of the existing `ComponentTests` mutations:  existing `ComponentTests` mutations (the two recorded in `Component.swift`) redden the same tests | — | — |
| 2.13 | `aBackgroundThreadWriteDirtiesAMemoWithinOneFrame` | an off-main write: at most one stale frame (RX-K's limitation, pinned as-is) | — | — |

Existing pins that move: none (opt-in); `theSevenRetentionSlotsAreMutuallyDistinct`,
`PhaseSeparationTests`' header (no new paint-only query), the D2 guard (no new
handler-registering site) and `everyNamingSiteStartsAReturningNameFresh` (no new
named-id site) are unchanged.

### Both lanes

* `swift build --build-system native --build-tests` / `swift test --build-system
  native --no-parallel` unfiltered, one summary line read (3566 + the new tests,
  recorded), `FR-J no-argument frame: succeeded=` present, 0 `error:`, the only
  `warning:` SwiftPM's deprecation notice; `swift build --build-tests` 0 warnings.
* The fourteen images 0 px against f6f865c1:
  `docs/probes/demo-pixels/compare.sh <scratch> f6f865c1 HEAD`;
  `DemoFrameDeterminismTests` `Expected.swift` unedited.
* `Backends/SDL` and a `swift:6.4-noble` container build
  (`docker run … swift build --build-tests` for the root; `MetalUILayout` is portable
  and `MetalUILayoutTests` runs there); lane 1 runs the Linux image once.
* `swift package clean` after lane 1 (a stored property on a public class
  crossing a module boundary: `LayoutTree.memo` is `package`, but the field
  addition still warrants it, CN-R) and after lane 2 (`StateTable`).
* Mutate each new typecheck guard red once.

## 7. Deferred, with reason and owner

| item | reason | owner |
|---|---|---|
| **Retained subtrees** (skip the build *recursion*, prepaint and paint of an unchanged `Component`) — the 51% + 10% + 14% | needs a persistent append-only layout tree (epochs, re-parenting rule for CN-L), output replay for ~110 channels or an idempotence proof for `prepaint`/`paint` (`IV-H`); too large for one item | **C14-b**, to be queued after this item's close-out |
| `@Environment`-bearing components in the memo | `EnvironmentValues` is not comparable; needs an environment epoch stamped by writers | C14-c |
| Automatic (reflective, SwiftUI-default) skipping | would change every existing app that reads a plain-class model in `content` (the GT-A test's own pattern); opt-in only (`IV-K`) | not planned |
| Per-`ForEach`-row and per-`List`-row scopes | `List` rows are produced by `List.requestLayout`; row reads are in the whole-frame session | C14-d |
| Subtree placement memo (a moved subtree) | bit-exactness of translated placement unproven | C14-b |
| Keys for rich text, images, `GPUSurface`, controls | each is a "key covers the closure" test | follow-ups of lane 1 |
| `MetalDrawContext.drawText` and its SDL twin | `GT-F` re-taken in `IV-I`: still deferred | decided at C14-b's close-out |
| MetalCreator adoption (`NodeView.equatable()`, palette as a value input) | MetalCreator is never edited from here | its own plan, after merge |

## 8. GT-F close-out (record §99)

`theOverlayCostIsLinearAndCounted` is re-taken by lane 1 (test 1.1). Prediction
recorded before the run, from the design: per camera frame, N labels moving by
`.offset`: builds 1, layout measure calls **0**, cache misses **0**, seam measures
**0**, `placeGlyphs` N, atlas/raster/texture 0. **`drawText` stays deferred** (`IV-I`):
what remains per label is the root closure's element construction, the build
recursion, prepaint (an accessibility record) and one `placeGlyphs` — the first three
are what C14-b removes for an unchanged label, and `drawText` would also drop the
label's accessibility record. The decision is re-taken at C14-b's close-out with the
same test.

## 9. Demo expectation

`METALUI_INVALIDATION_DEMO=1 swift run MetalUIDemo` (a new root, `MetalUIDemoContent`'s
own function per `everyProductionTreeBuildsOnAOneMegabyteThread`; added to CLAUDE.md's
env list in the Record phase): two copies of the 81-cell tree side by side, the left
`.equatable()`, the right plain; a "bump a cell" button; a counter under each reads the
number of `content` getters evaluated in the last frame (the demo counts them itself,
as `IVStats` does). Expectation: after a bump the left reads **1**, the right **121**;
both draw identically; typing in a `TextField` placed in a memoized cell keeps its
caret, selection and focus across bumps of other cells; resizing the window and
changing the display's scale redraw the text correctly. The fourteen standard demo
images are unchanged (the new root is not among them).

## 10. Human checks (group IV, added in the Record phase; not run — an agent cannot)

IV1 — drag feel: in the invalidation demo (and MetalCreator after adoption) drag a
node: no stale frame, no flicker, no node left behind. IV2 — type in a memoized cell's
field: caret, IME and selection behave. IV3 — drag the window between a 1x and a 2x
display, and switch light/dark: text is crisp and correctly sized (layout memo key:
scale factor; theme). IV4 — VoiceOver reads a memoized subtree as the unmemoized one
(the accessibility tree equality is pinned by 2.9; the reading is a human's, `IX-AE`).
