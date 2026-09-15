# Modifier composition design

**Milestone:** SwiftUI replacement task 3
(`plans/2026-09-12-swiftui-alignment.md`, "Build a typed modifier-composition
foundation", and its four open proofs).

**Status (2026-09-15): lanes 1 and 2 done; lane 3 not started.** Designed
against `f64e58a` on `feat/modifier-composition`, in the worktree
`/Users/maxburger/Developer/MetalUI-modifier-composition`, and revised after
design review. **Lane 1** landed as `6d89906` (its ten tests, four red),
`6ff2d31` (the overlay fix) and `2571d4a` (a shape-13 fix its mutations found):
1094 tests, 45 guards, 97 goldens; its measurements are in record §10 and its
departures from this text in `MC-O`. **Lane 2** landed as `e9248c3` (its tests,
guards and arms, red on a skeleton), `5fe5a30` (`ModifiedElement`'s phases and
the allocation test) and `49270c7` (one test spelling): 1103 tests, 47 guards,
97 goldens; its measurements are in record §10 and its departures in `MC-R` —
among them that the default demo's window capture could not be taken (the
screen was locked) and is owed. Rulings are prefixed **`MC-`** and lettered, in
`docs/superpowers/2026-09-15-modifier-composition-decisions.md`; a bare `MC-3`
is a typo. The track's record is `docs/record/10-modifier-composition.md`.

**The critic round after lane 1** (eight findings, `MC-Q`) changed, at
`661efd9`/`39f6237` and this docs commit:

- **the overlay's identity** (`MC-P`, replacing `MC-E`'s threaded cursor): the
  overlay numbers under `.child(of: id, at: -1)`, independent of the primary's
  shape, as a new SwiftUI probe shows SwiftUI's is; lane 1 tests 1 and 9
  inverted, test 9 renamed;
- **lane 1 test 4** gains an equal-layer-count `$anim` disagreeing oracle, and
  test 10's doc its scope;
- **lane 2 test 6** becomes a solver-work-budget typecheck guard, and **test 5**
  must animate inside the `withAnimation` body and `#require` a mid-flight
  reading;
- **lane 3** gains test 9 (`MC-G` hole 7, a stored typed id);
- **the merge notes**: `feat/environment` at `f4dcad8` as committed, AB-O's
  per-layer obligation, the `NativeTappable.swift` conflict.

**The design review** (twelve findings) is dispositioned finding by finding in
`MC-N`. It changed three things of substance:

- **`MC-A`'s overloads.** Their type-checking time was measured to grow
  exponentially with chain length. They are replaced by ONE overload per
  modifier, dispatched through an associated type on `ElementGroup`.
- **`MC-H`'s copied defaults.** They are replaced by one shared internal
  helper, because the environment track changes the copied call.
- **New tests and named holes:**
  - three new tests, one each for:
    - a layer added at run time (`MC-C`);
    - the overlay's index shifting (`MC-E`; inverted after lane 1's critic round to the overlay's identity NOT shifting, `MC-P`);
    - modifier order against SwiftUI (`MC-L`);
  - a disagreeing oracle per observation (`MC-B`);
  - three more named holes in `MC-G`, two of them newly measured.

This spec **supersedes** the design sections of
`specs/2026-09-12-typed-modifier-composition-design.md` ("Design", "First
feature", "Required proofs") for the legacy path. That file's Status block
stays the inventory of what existed at `7cfcddc`. It is not edited here. Its
two required proofs that the first draft of this spec dropped are now owned:
lane 2 test 1 and lane 1 test 10 (`MC-L`).

## What this design delivers

| lane | closes | one line |
|---|---|---|
| 1. **proofs** | open proofs 1–3 on today's code; the overlay collision fixed | end-to-end `@State` tests across chains on both paths; one once-per-phase test over every wrapper; the overlay collision measured red, then fixed (first with one threaded cursor, since `MC-P` with an overlay-side id that keeps SwiftUI's independence from the primary's shape); a hand-built-`Box` oracle for lane 2, with one disagreeing oracle per observation; modifier order pinned to SwiftUI's measured numbers |
| 2. **representation** | the task's wrapper representation | `ModifiedElement<Content>`: one flat type for legacy `.padding` and `.frame`, one overload per modifier through `ElementGroup.LayerBase`; `FrameModifier` deleted; the oracle stays green; per-site guard arms; allocations counted at 1, 2 and 3 layers; the default demo captured against a build of `f64e58a` |
| 3. **typed node id** | open proof 4 (`SA-R`) | `ProposalNodeID` with an internal init, returned by a new `ProposalElementGroup` requirement; five lies become compile errors; one shared member-entry helper instead of copied defaults; seven named holes, each pinned or cited |

**Why this order.**

- **Lane 1 first.** It writes, against today's `Box`/`FrameModifier`, the tests
  lane 2 must keep green. That turns "preserves identity, `@State`, handlers,
  phase order" into a measurement rather than a promise (`MC-B`). The overlay
  fix is one line with no dependency.
- **Lane 2 before lane 3.**
  - The two are independent: one is the legacy path, the other the proposal
    path.
  - Lane 3 is the largest churn, and it edits the files the parallel tracks are
    likeliest to touch.
  - If the track stops early, lanes 1–2 are a complete deliverable on their
    own.
- **Lane 3 last.** Lane 1's proposal `@State` test is the mutation target for
  lane 3's shared helper (`MC-H`), so it must exist first. `CombinedKit.swift`
  shows lane 2's `LayerBase` and lane 3's typed entry coexist on one
  `ElementGroup`.

**Not in this design:** `MC-L` lists every deferred item and its owner. In
brief:

- no `width`/`height` conversion (task 4);
- no change to `Component` distribution (task 5);
- no paint-only legacy layers (task 5);
- no unification with proposal `ModifiedContent` (task 7).

## Where things stand at `f64e58a`

All by reading, except where marked as measured.

- **Legacy `.padding`** returns `Box<Self>` (`Box.swift:640-650`).
- **Legacy `.frame(width:height:)`** returns `FrameModifier<Self>`
  (`FrameModifier.swift:62-67`), a `StyledElement` whose three phases are
  `Box`'s, with a centred style.
- **Each wrapper adds one node and one identity level.** Chained wrappers nest
  types (`chainedFramesRemainConcreteAndNestTheirLayoutNodes` stores
  `Row<FrameModifier<FrameModifier<TwoLeaves>>>`).
- **No stored type in `Sources/` spells a `.padding`/`.frame` chain today**
  (grep). The demo's `CounterPanel` type
  `Box<Pair<Pair<Box<Text>, Box<Text>>, Box<Text>>>` comes from hand-built
  `Box {}` calls (`main.swift:244-290`), which this design does not change
  (`MC-A`).
- **Modifier order matches SwiftUI for a fixed-size leaf — measured.** Seven
  chains (`swiftui-modifier-order.swift`, arms K0–K2, O1–O4) read the same
  outer size and leaf origin through today's `Box`/`FrameModifier` as in
  SwiftUI.
- **`OverlayModifier` gives primary and overlay one id — measured**
  (`MC-E`; fixed by lane 1 at `6ff2d31` with a threaded cursor, and re-fixed at
  `661efd9` with an overlay-side id, `MC-P`, after the threaded cursor was
  measured to reset the overlay's state where SwiftUI keeps it):
  - an overlay never clicked read the primary's 3 taps;
  - hovering the primary painted both hover fills.
- **`ProposalElementGroup` has no requirements**, so a conformer registering a
  legacy node compiles and traps at run time (`SA-R`, `SA-G`).
- **One native node registered twice — measured, no trap** (`MC-G` hole 4). A
  node listed twice in one container reserves two slots and is drawn in the
  second. A node handed to two containers is drawn where the last one places
  it.
- **Counts carried from `553b980`** (docs-only since): 1084 tests, 45 guards,
  97 goldens. Re-measured with the overlay fix applied temporarily: 1085 with
  one scratch test.

## Evidence

- `docs/probes/swiftui-modifier-identity.swift`: arms T, A–H (`MC-A`, `MC-C`,
  `MC-E`).
- `docs/probes/swiftui-overlay-primary-shape.swift`: controls A, B, P5, Q and
  arms P1–P4 (`MC-P`).
- `docs/probes/modifier-composition-skeletons/chain-solver-scope-guard.sh`: the
  solver-scope thresholds and the lane 2 test 6 guard's shape (`MC-A`, `MC-Q`
  finding 3).
- `docs/probes/swiftui-modifier-order.swift`: arms K0–K2, O1–O4, and the
  matching MetalUI numbers from a deleted scratch test (`MC-L`, lane 1 test 10).
- `docs/probes/modifier-composition-skeletons/`:
  - `chain-typecheck-timing.py`: the type-check-time table (`MC-A`);
  - `LayerBaseKit.swift` and its five `layer-client-*.swift` clients:
    inference, the unreachable nested shape, and the `_wrap` hole (`MC-A`,
    `MC-B`);
  - `LayerAllocationModel.swift`: allocations at 1, 2 and 3 layers (`MC-K`);
  - `TypedNodeKit.swift` and its eight `typed-client-*.swift` clients (`MC-G`);
  - `CombinedKit.swift` with `combined-client-layered.swift`: lanes 2 and 3
    together;
  - `FlatChainOverloads.swift`: the superseded first `MC-A`, kept as record.
- The scratch end-to-end runs recorded under `MC-E` and `MC-G` holes 2, 4 and
  6. Their shapes are lane 1's tests 1–3 and lane 3's tests 7–8.

---

## Lane 1 — proofs, and the overlay fix

### Rulings

`MC-B` (writes the oracle), `MC-D`, `MC-E`, `MC-F`, `MC-L` (modifier order).

### Source change

`Sources/MetalUI/NativeOverlayModifier.swift`, `requestLayout`.

**Superseded after lane 1's critic round by `MC-P` (`661efd9`):** the primary
keeps its cursor from 0 under `id`; the overlay gets its own cursor from 0
under `GlobalElementID.child(of: id, at: -1, name: nil)`. The doc comment
records the collision, the threaded cursor's divergence with the probe's
numbers, why `-1`, and the four pinning tests. As lane 1 first built it:

- delete `var overlayCursor = 0`, and pass `&contentCursor` to
  `overlay.requestGroupLayout`;
- rename the variable `cursor`, and add a doc comment. The comment says:
  - that one cursor is threaded, as `Pair` threads it;
  - what the collision did, with `MC-E`'s measured numbers;
  - that the overlay's index now depends on how many indices the primary
    consumed (test 9);
  - which tests pin it.

No other source changes in this lane.

### Files

- `Sources/MetalUI/NativeOverlayModifier.swift` (edit, above).
- `Tests/MetalUITests/ModifierCompositionProofTests.swift` (new). Private
  helpers:
  - **`CompositionLog`** (named `PhaseLog` in the first draft, which
    `PipelineTests.swift` already declares; `MC-O` item 4), a
    `@MainActor final class`. It records:
    - per-name counts of `requestLayout`/`prepaint`/`paint`;
    - per-name `GlobalElementID` (last prepaint);
    - per-name `taps` read in paint;
    - an ordered event list.
  - **`CountingLeaf`**, a legacy `StyledElement` (all four requirements):
    - it registers `requestNode` with a declared pixel size (20×20 unless the
      test says otherwise);
    - it holds `@State var taps = 0`;
    - in prepaint it registers `handlers`, with `onClick` defaulted to
      `{ taps += 1 }` when the caller set none;
    - paint logs, and paints a `.textPrimary` fill over its bounds when
      `pass.isHovered(id)`. No chain in this file uses `.textPrimary` as a
      layer colour; test 4's chain uses `.accent`, `.surface` and `.separator`.
  - **`CountingProposalLeaf`**, an `Element` + `ProposalElementGroup`
    registering `requestNativeLeaf` at a fixed size. It has the same `@State`,
    handler, log and hover fill. It also takes an optional click action and an
    optional displayed value, so a `Component` can route its own `@State`
    through it. Lane 3 converts it to `ProposalElement`.
  - **`CountingProposalComponent`**, a `Component` + `ProposalElementGroup`
    (the `Toggle` precedent in `NativeBoundaryIntegrationTests.swift`). It
    holds its own `@State var taps`. Its content is one `CountingProposalLeaf`
    whose click increments the component's state and whose paint logs it.
    Lane 3 changes its `content` to `some ProposalElementGroup`.
  - **`EmptyProposalComponent`**, a `Component` whose content is
    `EmptyGroup()`, retro-conformed to `ProposalElementGroup`. It consumes one
    index and contributes zero nodes (test 9).

### Tests

Each row gives three things:

- what the test pins;
- its state before the change;
- the mutation that must redden it after.

"Green on arrival" marks a characterization of correct behaviour today. Its
proof is the mutation, run in this lane on today's code, and run again by lane
2 or 3 on theirs.

**The oracle's disagreement rule (`MC-B`, shape 15, per observation).** Test 4
compares five observations. For each one, a disagreeing oracle that differs in
exactly that observation is built and `try #require`d to differ **before** the
real comparison runs:

| observation | disagreeing oracle | required to differ |
|---|---|---|
| rects (order, bounds, colour) | paddings 4 and 8 swapped | the rect list |
| wrapped element id, hitbox ids | `.id("mid")` moved from the padding-4 layer it follows (`MC-C`) to the outermost padding-8 layer (`MC-O` item 1) | the leaf's id and the hitbox id list |
| hitbox list (ids, bounds, order) | the middle layer's `onClick` dropped | the hitbox list, in count |
| `$anim` liveness per layer id | the `.frame` layer omitted (one layer fewer) | the set of layer ids with a live `$anim` slot, and `tree.nodeCount` |
| `$anim` liveness at an EQUAL layer count (`MC-Q` finding 6) | the frame layer built as a test-local `BoxWithoutAnimated` (`Box`'s phases minus `animated`) | `animLive` reads `[true, false, true]` against `[true, true, true]`, with the layer ids equal |

| # | test | pins | before | mutation that must redden it |
|---|---|---|---|---|
| 1 | `theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities` | `Frame` only. First arm: `ZStack { primary(60).overlay(.topLeading) { overlay(10) } }`. The ids differ; `primary.id == .child(of: modifier, at: 0)`; **since `MC-P`** `overlay.id == .child(of: .child(of: modifier, at: -1), at: 0)` (as lane 1 first built it: `.child(of: modifier, at: 1)`). Second arm, with an `HStack { A; B }` primary: the overlay's id has the same `-1` shape under `A.id.parent!.parent` | **red, measured**: ids equal | restore a second cursor starting at 0 (R2); **also** `MC-E`'s threaded cursor (R1) and a reserved `$overlay` name (R3), each reddening both arms |
| 2 | `aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState` | real `Window`, 100×100. Three clicks at (70, 70) hit the primary only; one click at (25, 25) hits the overlay. The primary reads 3 and the overlay reads 1 | **red, measured**: the overlay reads 3 after the primary's clicks | same |
| 3 | `hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay` | With the pointer at (70, 70), exactly one hover fill is painted, 60pt wide. At (25, 25), exactly one, 10pt wide | **red, measured**: two fills, `[60, 10]` | same |
| 4 | `aModifierChainIsIdenticalToHandBuiltNestedBoxes` (`MC-B`) | The chain `leaf.background(.accent).onClick{}.padding(4).id("mid").frame(width: 60, height: 40).background(.surface).onClick{}.padding(8).background(.separator).onClick{}`, in a `Row`, against hand-built `Box(style:decoration:content:)` values, one per wrapper, with the same styles, handlers and `.id`. It compares: the leaf's id and bounds; `lastHitboxes` ids, bounds and order; the scene's rect order, bounds and colour; `tree.nodeCount`; and `isLive(animRetentionSlot(for:))` per layer id. The five disagreeing oracles in the table above are each `try #require`d first. **It does not compare accessibility records or anything else `Element`'s group defaults do per element** (`MC-B`; the AB-O merge obligation below) | green on arrival | **today:** `FrameModifier.prepaint` registers its handlers after its content; `FrameModifier.requestLayout` skips `animated` (R4, also reddens test 5). **Lane 2**, each run separately: the layer loop runs innermost-first in prepaint; every inner layer takes the outermost id; `.id` lands on the wrong layer; **one inner layer skips `animated`** |
| 5 | `stateSurvivesFramesUnderALegacyModifierChain` (`MC-D`) | window. `Row { CountingLeaf().padding(4).frame(width: 60, height: 40).padding(8) }`: 3 clicks, then 2 more frames; it reads 3. The leaf and its two nearest ancestors each have component `.positional(0)`. Its third ancestor equals `.child(of: rootID, at: 0, name: nil)`, where `rootID = .child(of: nil, at: 0, name: nil)` is the `Row`'s. Each of the three ancestors has a live `$anim` slot | green on arrival | **today:** `FrameModifier.requestLayout`'s cursor starts at 1. **Lane 2:** content laid out under the outermost layer's id |
| 6 | `stateSurvivesFramesUnderAProposalModifierChain` (`MC-D`) | window. `HStack { CountingProposalLeaf("a").padding(…).frame(width: 40, height: 40).background(.surface); CountingProposalLeaf("b"); CountingProposalComponent("c") }`. After 3 clicks on a, 2 clicks on c, then 2 frames: a reads 3, b reads 0, c reads 2. `a` and its two nearest ancestors each have component `.positional(0)`, and its third ancestor is the `HStack`'s child at index 0 | green on arrival | **today:** `ModifiedContent.requestLayout`'s cursor starts at 1. **Lane 3:** its `MC-H` mutations |
| 7 | `everyModifierWrapperDelegatesEachPhaseExactlyOnce` (`MC-F`) | one arm per wrapper and code path, as listed in `MC-F`, each reading `[1, 1, 1]`. The control arm `Pair(leaf, leaf)` reads `[2, 2, 2]`. Counts are `try #require`d | green on arrival | **today**, each separately, with the arm it reddens: the `allowsHitTesting` branch calls `prepaintGroup` twice (that arm); the `clip` paint branch loses its `else` (that arm); `OverlayModifier.paint` skips `overlay.paintGroup` (the overlay-side arm); `FrameModifier.prepaint` calls content twice. **Lane 2:** `ModifiedElement.paint` calls content once per layer |
| 8 | `aModifierChainRegistersAndPaintsOuterLayersFirst` (`MC-F`) | The chain `leaf.background(.accent).onClick{"inner"}.padding(4).background(.surface).onClick{"outer"}`. Hitbox order is `[outer, leaf]`. `.surface` is emitted before `.accent`. A click in the padding ring logs `outer`; one inside the leaf logs `inner` | green on arrival | **today:** `Box.prepaint` registers after content. **Lane 2:** the layer loop reversed in prepaint, and separately in paint |
| 9 | **`anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`** (`MC-P`; lane 1 built it as `anOverlaysIdentityFollowsTheIndicesItsPrimaryConsumed` under `MC-E`) | window, 100×100. The primary is an `@ElementBuilder` block `{ if flag { EmptyProposalComponent() }; CountingProposalLeaf("p", 60×60) }`, which has one node either way. Overlay: `CountingProposalLeaf("o")` at `.topLeading`, 10×10. The steps: with `flag` true, 3 clicks at (5, 5); then `flag` false, one frame; then `flag` true, one frame. **Control (the probe's P5), `#require`d:** `p`'s component reads `.positional(1)`, `(0)`, `(1)`. **Pinned at all three steps:** the overlay's path `[.positional(0), .positional(-1)]`, its exact id, 3 taps, its `$state0` slot live — SwiftUI's P1–P4 | **as lane 1 first pinned it (`MC-E`, measured):** index 2 / 3 taps / index-2 slot live, then index 1 / 0 / not live, then index 2 / 3 / live. **Since `MC-P`:** green at `661efd9`/`39f6237` | `MC-E`'s threaded cursor (R1): index 2/1/2, taps 3/0/3. The original shared id (R2). A reserved `$overlay` name (R3): path and id only, taps stay 3 |
| 10 | `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes` (`MC-L`) | **Scope (`MC-Q` finding 7): a fixed leaf, both axes given, frames no smaller than content, an unconstrained `.flexStart` parent; a nil axis, a smaller frame, a stretching `Box` parent (EP-8) and a shrinking row (SZ-L) are task 4's.** A 20×20 `CountingLeaf`, outer width read from a 1pt sibling in a `Row` and outer height from one in a `Column`, both `.alignItems(.flexStart)`. Expected, from `swiftui-modifier-order.swift`: K1 `.padding(8)` 36×36 at (8, 8); O1 `.padding(8).frame(60×60)` 60×60 at (20, 20); O2 `.frame(60×60).padding(8)` 76×76 at (28, 28); O3 `.padding(4).frame(40×40).padding(8)` 56×56 at (18, 18); O4 `.frame(40×40).padding(4).padding(8)` 64×64 at (22, 22). `try #require` that O1 ≠ O2 and O3 ≠ O4 before comparing with SwiftUI's numbers | **green, measured** by a deleted scratch test at `f64e58a` (all seven equal) | **today:** `FrameModifier.init` drops `justifyContent = .center` (O1's x moves). **Lane 2:** `requestLayout` mints layer nodes outermost-first around the content (O1 and O2 swap) |

**Mutation discipline.**

- Commit before mutating. Back up each mutated file with `cp` and restore from
  the copy. Confirm with `git status --short` and a grep for the marker.
- Run the whole suite per mutation (`swift test --build-system native
  --no-parallel`), and read the `Test run with N tests` line.
- Name the tests each mutation reddens in `MC-D`/`MC-E`/`MC-F`'s Mutations
  lines.
- Word coverage as a differential between named tests, never as exclusivity.

### Expected counts

1084 → **1094** tests; guards unchanged at 45; goldens 97, unmoved. **Measured
by lane 1** at `2571d4a`: `Test run with 1094 tests in 1 suite passed`, 0
`error:`, 0 `warning:`; `grep -c canTypecheck` per file sums to 45 (one hit in
`UnitSafetyTests.swift` is a comment); `git diff --stat f64e58a -- '*.json'`
empty.

**Files beyond this list** (`MC-O`): `NativeLayoutIntegrationTests.swift`,
four `#expect(rects.count == 2)` made `try #require` (`2571d4a`). Tests 4, 7
and 10 render through `Frame` rather than a `Window`, and test 10 also pins K0
and K2 (`MC-O` items 2-3).

### Docs owed by lane 1 (track files only)

- `MC-D`, `MC-E`, `MC-F` Mutations lines; `MC-L`'s order row.
- Record §10: red lines for tests 1–3; test 9's measured readings; the suite
  count.

---

## Lane 2 — `ModifiedElement`

### Rulings

`MC-A`, `MC-B`, `MC-C`, `MC-I`, `MC-J` (default demo), `MC-K`.

### Public API

```swift
// ElementGroup.swift — ADDITIVE: two requirements in the protocol body, with doc
@MainActor
public protocol ElementGroup {
    // … existing requirements unchanged …

    /// The type a legacy wrapper modifier wraps: `Self` for every conformer but
    /// `ModifiedElement`, whose layers wrap its content (MC-A).
    associatedtype LayerBase: ElementGroup = Self
    /// Framework entry point for `.padding`/`.frame`: adds one outer layer.
    /// Not for conformers to implement (MC-A's hole).
    func _wrap(_ layer: ModifierLayer) -> ModifiedElement<LayerBase>
}

// ModifiedElement.swift (new)
public struct ModifierLayer {             // public type, internal members and init
    var style: Style; var decoration: Decoration; var handlers: Handlers; var elementID: ElementID?
}

/// One flat wrapper for the legacy path's outer modifiers (MC-A).
public struct ModifiedElement<Content: ElementGroup>: Element, StyledElement {
    public typealias LayerBase = Content
    public var content: Content
    // internal storage:
    //   var outermost: ModifierLayer
    //   var inner: [ModifierLayer]   // innermost first; empty for one layer (MC-K)
    init(content: Content, layer: ModifierLayer)          // internal
    public func _wrap(_ layer: ModifierLayer) -> ModifiedElement<Content>   // appends

    // StyledElement: style / decoration / handlers / elementID read and write `outermost`.
    public struct Layout { /* internal: per-layer id + node, content's GroupLayout */ }
}

extension ElementGroup where LayerBase == Self {
    public func _wrap(_ layer: ModifierLayer) -> ModifiedElement<Self>     // wraps
}

extension StyledElement {   // Box.swift, return types change; ONE overload per spelling
    public func padding(_ points: Pixels) -> ModifiedElement<LayerBase>
    public func padding(_ edges: Edges<Length>) -> ModifiedElement<LayerBase>
}

extension ElementGroup {    // moved from FrameModifier.swift into ModifiedElement.swift
    public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<LayerBase>
}
```

- **A padding layer** is `Style()` with `padding = edges`.
- **A frame layer** is `Style()` with `alignItems = .center`,
  `justifyContent = .center`, and `size.width`/`size.height` set for each
  non-nil argument. That is `FrameModifier.init`, verbatim.
- **`ModifiedElement` does not redeclare `padding` or `frame`.** Redeclaring
  them concretely is the first design's shape, and its type-checking time is
  exponential in chain length (`MC-A`).

### Phases (`MC-B`, `MC-C`)

Let n be the layer count and `L[k]` the layer at depth k, 0 innermost.

- **`requestLayout(id)`:**
  - ids from the outside in: `id(L[n-1]) = id`, then
    `id(L[k]) = .child(of: id(L[k+1]), at: 0, name: L[k].elementID)`;
  - `content.requestGroupLayout(under: id(L[0]), at: &cursor)`, with `cursor`
    starting at 0;
  - then for k = 0 up to n-1: `(L[k].style, L[k].decoration) =
    animated(L[k].style, L[k].decoration, for: id(L[k]), pass:)`, and
    `node[k] = pass.requestNode(style: L[k].style, children: k == 0 ?
    contentNodes : [node[k-1]])`;
  - return `node[n-1]`.

  This is the order, node minting included, that nested `Box`es produce.
- **`prepaint`:** for k = n-1 down to 0,
  `pass.registerHandlers(L[k].handlers, at: pass.bounds(of: node[k]), id: id(L[k]))`;
  then `content.prepaintGroup` once.
  - **Write it so that layer k's registration AND everything inside it can be
    wrapped in one scoped call** (recursion over k, or equivalent), because
    `Element.prepaintGroup` wraps a whole element's prepaint that way and the
    AX-bridge track adds exactly such a wrap (AB-O, `MC-B`, merge notes). A
    nested `Box` receives `Element`'s group defaults at every level; a layer
    does not, so **any hook in those defaults is mirrored per layer** — on
    this branch the defaults only enter the id and bind/re-bind `@State`,
    and layers hold no `@State`.
- **`paint`:** for k = n-1 down to 0, if
  `animatedBackground(L[k].decoration, for: id(L[k]), pass:)` returns a colour,
  fill `bounds(of: node[k])` with `Corners(all: L[k].decoration.cornerRadius)`;
  then `content.paintGroup` once.
- **`Element`'s default `requestGroupLayout`** gives the whole chain its slot,
  named by `elementID`, which is the outermost layer's.

### Files

- `Sources/MetalUI/ElementGroup.swift` (**shared, additive**): the two
  requirements above and their doc comments. No existing line changes.
- `Sources/MetalUI/ModifiedElement.swift` (new):
  - `ModifierLayer` and `ModifiedElement`;
  - the `where LayerBase == Self` default `_wrap`;
  - `ElementGroup.frame`.

  The doc comment cites `MC-A`…`MC-C`, `MC-K`, the `_wrap` hole and the
  pinning tests.
- `Sources/MetalUI/FrameModifier.swift`: **deleted**.
- `Sources/MetalUI/Box.swift`: the two `padding` return types and their doc
  comments, which today say "applies that style to a new outer box".
- `Tests/MetalUITests/ModifiedElementTests.swift` (new).
- `Tests/MetalUITests/ModifiedElementCompileGuards.swift` (new): plain import,
  file scope, Swift 6 mode, `typecheckFile`. Holds guard 7 and, since `MC-Q`
  finding 3, test 6.
- `Tests/MetalUITestSupport/Typecheck.swift` (**shared test support,
  additive**): `typecheckFile(_:importing:frontendArguments:)`, passing each
  argument as `-Xfrontend <arg>` after `-swift-version 6`. The existing
  two-argument `typecheckFile` stays and forwards with `[]`, so no existing
  guard changes.
- `Tests/MetalUITests/ComponentTests.swift`:
  `chainedFramesRemainConcreteAndNestTheirLayoutNodes` stores
  `ModifiedElement<TwoLeaves>` and `Row<ModifiedElement<TwoLeaves>>`. The node
  count stays 5. Its doc comment says the type is flat and the nodes still
  nest.
- `Tests/MetalUITests/NativeLayoutIntegrationTests.swift`: the doc comment at
  `:660` that names `FrameModifier`.
- One additive arm block in each of the six guards `MC-I` names:
  - `AnimationTests.swift` (2);
  - `BackgroundChainTests.swift` (2);
  - `InputDispatchTests.swift` (1);
  - `AXEmitSiteTests.swift` (1).

  Each arm uses a **two-layer** chain and asserts on the **inner** layer as
  well as the outermost.

### Tests

Build a **skeleton commit first**. `ModifiedElement` gets its storage, its
accessors, `_wrap`, and the `StyledElement`/`ElementGroup` return types. It
does **not** get `typealias LayerBase = Content`: it keeps the default `Self`,
so a chain nests `ModifiedElement<ModifiedElement<…>>`. Its phases register
**only the outermost layer**, around the content, under the outermost id. Take
the red runs below on the skeleton.

**As run (`MC-R` item 1): two skeletons.** A nesting skeleton cannot compile
tests 1, 2, 3 and 5, which spell a chain as one `ModifiedElement<Leaf>`. The
committed skeleton `e9248c3` (**S1**) is flat (`LayerBase = Content`, the
appending `_wrap`) with outermost-only phases; tests 2, 3, 5 and the `MC-I`
inner arms were red there. The nesting skeleton (**S2**, uncommitted) gave
tests 1 and 2's type claims as build errors and guard 7's red run. The
"before" column below says which.

| # | test | pins | before (on the skeleton) | mutation that must redden it after |
|---|---|---|---|---|
| 1 | `legacyModifierChainsInferOneConcreteType` (`MC-A`; the superseded spec's "no ordinary modifier path introduces `AnyElement`") | Three chains: `String(describing: type(of:))` of `Leaf().padding(4).frame(width: 60).padding(Edges(all: .pixels(8))).width(70)` is `"ModifiedElement<Leaf>"`; of a component's `.frame(width:).padding(_:)` is `"ModifiedElement<Comp>"`; of an external generic group's `.frame` is `"ModifiedElement<Group<Leaf>>"`. No name contains `AnyElement`. Also a stored `let s: ModifiedElement<Leaf>` and a `Row<ModifiedElement<Leaf>>` built from chains | **red**: `ModifiedElement<ModifiedElement<…>>` | add a concrete `extension ModifiedElement { public func padding(_ points: Pixels) -> ModifiedElement<Self> }`: the chain nests, and the build still succeeds |
| 2 | `aGenericWrapOverAChainIsIdenticalToTheFlatChain` (`MC-B`; the flat chain's padding-8 is spelled with `Edges`, `MC-R` item 3) | `func wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T.LayerBase> { t.padding(8) }` applied to `leaf.padding(4).frame(…)`, against the flat `leaf.padding(4).frame(…).padding(8)`. `try #require` that the two type names are EQUAL, and that the layer counts are 3 and 3. Then every observation from lane 1 test 4 is compared, with its disagreeing oracles | **red on S1** (14 issues): every observation; the type-name and layer-count `#require`s were green, the type being flat. **On S2** the flat return types do not compile | `ModifiedElement._wrap` replaces `outermost` instead of appending (a layer is lost) |
| 3 | `addingALayerAtRunTimeResetsTheWrappedElementsState` (`MC-C`) | window. `generation` is captured by the content closure: `var c = CountingLeaf().padding(4); if generation > 0 { c = c.padding(8) }`. Three clicks at generation 0, flip, one frame: it reads **0** | **red**: the skeleton lays content out under the outermost id whatever the count, so it reads 3 | content laid out under the outermost id |
| 4 | `changingALayersValueKeepsTheWrappedElementsState` (`MC-C`) | the same, with `.padding(generation == 0 ? 4 : 12).frame(width: generation == 0 ? 60 : 80, height: 40)`: it reads **3** | green on the skeleton | name each layer by its style, e.g. `ElementID("\(style.padding)")` when `elementID` is nil |
| 5 | `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer` (`MC-C`, candidate divergence) | window, a 20×20 `CountingLeaf`. Generation 0 is `.padding(4)`; generation 1 is `.padding(4).padding(8)`. **The change is made INSIDE the animation body** (`MC-Q` finding 4): `withAnimation(.linear(duration: 1)) { generation.value = 1; window.setNeedsRedraw() }` — or a `@State`/`@Observable` write there. `withAnimation` rolls its parked transaction back when no redraw was requested inside its body and none was already pending (`Animation.swift:717-720`), so `withAnimation { generation.value = 1 }; window.setNeedsRedraw()` **snaps**, and a snap reads x = 12 at t = 0, which is exactly this row's named mutation's reading. The outermost id is P. Driven by `simulateTick(timestamp:)`, **before any value is pinned, `try #require` that the t = 0.5 reading lies strictly between the t = 0 reading and the settled one** (a snap cannot pass). Then the leaf's x reads, **as predicted by reading and measured exactly so by lane 2**, **8** at t = 0 (the padding-8 layer starts from P's old baseline of 4; the new inner layer at P/0 snaps to 4), **10** at t = 0.5, and **12** once settled. P's `$anim` slot is live at both generations. P/0's is not live at generation 0 and is live at generation 1. The leaf's `taps` reads 0 (test 3's half) | **red on S1**: x read 4, 6, 8 | give the outermost layer an id keyed on the layer count (`name: ElementID("\(n)")`): x reads 12 at t = 0, and the betweenness `#require` fails. **Also run:** move `setNeedsRedraw()` out of the body; the `#require` must fail (the instrument's check) |
| 6 | guard **`aTwentyFourModifierChainTypechecksWithinASolverWorkBudget`** (`MC-A`; **was a run-time type-name test with a compiler time-out as its only red, replaced after `MC-Q` finding 3**) | `ModifiedElementCompileGuards.swift`, `typecheckFile(_:importing:frontendArguments: ["-solver-scope-threshold=T"])`. **Positive fixture:** `@MainActor func probeBody(flag: Bool) -> some Element { Leaf().padding(1).frame(width: 1)…padding(12).frame(width: 12).background(flag ? .accent : .surface) }` (24 integer-literal modifiers on a fixture-local legacy leaf) is accepted. **In-test negative:** the same file plus a fixture-local `extension ModifiedElement { public func padding(_: Pixels) -> ModifiedElement<Content> { fatalError() }; public func padding(_: Edges<Length>) -> … ; public func frame(width: Pixels? = nil, height: Pixels? = nil) -> … }` (the first design's concrete overloads) is rejected with "unable to type-check this expression in reasonable time". `#require` that the two disagree; print both diagnostics. **T is set from a measurement against the real module:** binary-search the positive fixture's minimum passing threshold under both toolchains (`chain-solver-scope-guard.sh`'s `minpass`, pointed at the real modules directory), record it, and take T ≈ 5× that minimum, provided the negative still fails at T; if it does not, record the numbers and fall back to a recorded build sentinel with no mutation claim. Model numbers: minimum 190, negative fails at every threshold up to 10⁶, T = 1000, ~0.1 s per fixture, identical on 6.4 and 6.3.3. **Measured by lane 2 against the real module: minimum 186 under both toolchains; T = 1000; the negative fails at 500–5000 under both; ~0.16 s per fixture** | **green on the skeleton, by the model** (a nested chain's solver work is linear too: 172 scopes at 24 in the model, the same as the chosen design's); its red run is the mutation, taken once | move the negative fixture's three concrete overloads into `ModifiedElement.swift` (the first design): the positive fixture reddens with the "unable to type-check" diagnostic at T, deterministically. Record the line. Type names stay test 1's |
| 7 | guard `aNestedModifiedElementCannotBeSpelled` (`MC-B`) | Three fixtures. `let _: ModifiedElement<ModifiedElement<Leaf>> = Leaf().padding(4).padding(8)` is rejected, fragment "cannot assign value of type". `func wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T> { t.padding(8) }` is rejected, fragment "cannot convert return expression". The positive fixture, `-> ModifiedElement<T.LayerBase>`, is accepted. Each real diagnostic is printed before asserting on it, and `#require` checks that the negatives and the positive disagree | **red on S2**: the annotated negative compiles (`MC-R` item 1); the positive also calls the generic wrap over a chain (`MC-R` item 4) | test 1's mutation (the concrete nesting overload), measured red |
| — | lane 1 tests 4, 5, 7, 8, 10 | the migration proof | green before (on `Box`/`FrameModifier`); must stay green | their lane-2 mutations in lane 1's table |
| — | six guard arms (`MC-I`) | the inner and the outer layer each: animate style; animate colour; honour and fade hover/focus; fire `onClick`; emit a declared AX node | red on the skeleton for the inner layer | outermost-only `animated`; outermost-only `animatedBackground`; outermost-only `registerHandlers` (the onClick, AX and hover arms) |

**`MC-K`, allocations.**

- Copy `FreezeLoopAllocationTests.swift`'s `countAllocations` and its
  calibration into `ModifiedElementTests.swift`.
- Count `requestLayout` over 500 chains of **1, 2 and 3 layers**, and over 500
  hand-built nested `Box<Leaf>`, `Box<Box<Leaf>>` and `Box<Box<Box<Leaf>>>`
  with the same styles. Take the counts in the configuration the suite runs.
- Record all six counts and the per-chain differences under `MC-K`, next to
  the model's (`LayerAllocationModel.swift`, swift.org `-Onone`: +0, +3, +5
  over nested).
- Keep a test `aModifierChainAllocatesABoundedAmountOverNestedBoxes` **only
  if** each arm reddens under a named mutation:
  - the one-layer arm's bound is "no more than nested", with the mutation "one
    `layers` array for all layers";
  - the two- and three-layer arms' bounds are the measured difference, with
    the mutation "one extra array per inner layer in `requestLayout`" (e.g.
    `let _ = inner.map { $0.style }`).
- On a swiftlang toolchain, fall back as `FreezeLoopAllocationTests` does, and
  say so in the log.
- Either way, the cost is named in `MC-K`.

**The real module's type-check time (`MC-A`), a recorded measurement, not a
test.** Build twice with `-Xswiftc -Xfrontend -Xswiftc
-warn-long-expression-type-checking=100` and `-Xswiftc -Xfrontend -Xswiftc
-warn-long-function-bodies=100`:

- the baseline build (below), for `MetalUIDemo`;
- this lane's build, for `MetalUIDemo` and the tests.

Record every warning line either build prints that names a function containing
a `.padding` or `.frame` chain. The expectation, from the model, is none. The
flags are passed only for this measurement, never committed, so the 0-warning
baseline is not affected.

**The default demo (`MC-J`).**

- **Baseline, from `f64e58a` itself, not from the lane's start commit:**
  `git archive f64e58a | tar -x -C <scratchpad>/mc-base`, then
  `swift build -c release` there. The archive keeps the shader-header symlink.
  It is a plain directory, not a worktree.
- **After the lane**, rebuild release in this worktree, re-capture, and count
  the differing pixels.
- **Record in record §10:** both captures' dimensions; the count; the
  coordinates of any difference; the logged pointer position.
- **The threshold.** Anything beyond record §03's desktop-corner pixels is a
  regression, and it is fixed before commit.
- **As run (`MC-J`, `MC-R` item 5): not captured.** The session was locked with
  the display asleep; `screencapture` produced no image. An offscreen scene
  comparison of `demoContent()` through `Frame.render`, `f64e58a` against
  `49270c7`, was byte-identical and shown able to disagree. **The window
  capture is owed.**

### Expected counts

1094 → **1101** tests (**1102** with the allocation test): five tests and two
guards (test 6 is now a guard). Guards 45 → **47**. Goldens 97.

**Measured by lane 2** (`MC-R` item 2): the base was 1095 (lane 1's test 11), so
`Test run with 1103 tests in 1 suite passed` with the allocation test, which
was kept; guards 47; goldens 97, `git diff --stat f64e58a -- '*.json'` empty.

### Docs owed by lane 2 (track files and the lines it makes false)

- `MC-A`, `MC-B`, `MC-C`, `MC-I`, `MC-K` Mutations lines; `MC-A`'s real-module
  type-check measurement **and test 6's real-module minimum threshold under
  both toolchains**; `MC-J`'s capture result.
- Source doc comments the change makes false, corrected at the line (practices
  record-mechanism 1):
  - `Box.swift`'s `padding` docs;
  - `Component.swift:387-405`'s `Box.swift:NNN` line citations, if the
    `Box.swift` edit moves them. Its parameter-signature claim stays true.
    This is a doc-only edit.
- Record §10:
  - **The per-site accounting change.** `FrameModifier`'s layout and background
    sites are gone. `ModifiedElement` is one layout site and one background
    site, looping per layer.
  - **The candidate divergence from test 5.**
  - CLAUDE.md's counts are the integration step's.

---

## Lane 3 — the typed native node id

### Rulings

`MC-G`, `MC-H`, `MC-J` (preview).

### Public API

```swift
// Sources/MetalUI/ProposalNodeID.swift (new)
public struct ProposalNodeID: Hashable, Sendable {
    public let layoutNodeID: LayoutNodeID
    init(_ id: LayoutNodeID)
}

@MainActor
public protocol ProposalElement: Element, ProposalElementGroup {
    associatedtype LayoutState            // restated: inference fails without it (MC-G)
    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, LayoutState)
}

extension ProposalElement {
    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutState)
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], SingleElementLayout<Self>)
        // id, bind and cursor through the shared helper (MC-H), then requestProposalLayout
}

extension Component where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], ComponentLayout<Self>)
        // id, bind and cursor through the shared helper (MC-H); content materialized
        // once and laid out under the component's id from 0
}

// Sources/MetalUI/GroupMember.swift (new, internal) — MC-H
extension GlobalElementID {
    /// The one place a group member's identity is entered: `child(of:at:name:)`,
    /// `StateBinder.bind`, `cursor += 1`. Called by Element's untyped default
    /// and by both typed defaults. Component's untyped default is the one
    /// remaining copy (Component.swift is not edited); its tests are named here.
    static func enteringGroupMember<E>(_ element: E, name: ElementID?,
                                       under parent: GlobalElementID?,
                                       at cursor: inout Int,
                                       pass: inout LayoutPass) -> GlobalElementID
}

// Sources/MetalUI/ProposalElementGroup.swift
public protocol ProposalElementGroup: ElementGroup {
    mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                             at cursor: inout Int,
                                             pass: inout LayoutPass) -> ([ProposalNodeID], GroupLayout)
}
// EmptyGroup, and conditionally Pair, OptionalGroup and ArrayGroup, implement it
// beside their existing conformance lines, mirroring their untyped bodies. The
// 13 element types' conformances become `ProposalElement`.
```

**`LayoutPass` (`Passes.swift`, registrar block only).**

- Every `requestNative*` registrar and `requestNativeLayout(_:children:)`
  returns `ProposalNodeID`.
- Each `child:`/`overlay:`/`children:` parameter takes `ProposalNodeID`.
- The bodies wrap and unwrap around `Frame`'s internal registrars, which stay
  unchanged.

**Every proposal container and wrapper** calls
`content.requestProposalGroupLayout`: `HStack`, `VStack`, `ZStack`,
`ProposalFrame`, `Padding`, `Background`, `FixedSize`, `ModifiedContent`,
`OnTapModifier`, `OverlayModifier`, `ProposalScrollView`,
`ProposalLayoutContainer`, `callAsFunction`.

- `Spacer`, `Rectangle`, `Color` and `ProposalText` implement
  `requestProposalLayout` over the typed leaf registrar.
- `OnTapModifier` returns its child's typed id.
- `ModifiedContent`'s passthrough cases return the child's typed id.

### Files

- **Sources:**
  - `Sources/MetalUI/ProposalNodeID.swift` (new);
  - `Sources/MetalUI/GroupMember.swift` (new);
  - `ElementGroup.swift` (**shared, one localized edit**): in `Element`'s
    default `requestGroupLayout`, the three lines `let id = …`,
    `StateBinder.bind(…)` and `cursor += 1` become one call to the helper.
    That default's `prepaintGroup`/`paintGroup` re-binds are untouched;
  - `ProposalElementGroup.swift`;
  - `Passes.swift` (the registrar block);
  - `NativeElements.swift`, `NativeModifiedContent.swift`,
    `NativeOverlayModifier.swift`, `NativeTappable.swift`,
    `ProposalScrollView.swift`, `ProposalText.swift`,
    `ProposalLayoutContainer.swift`.
- **Demo:** `Sources/MetalUIDemo/main.swift`. `PreviewToggle.content` becomes
  `some ProposalElementGroup`; `PriorityPreviewPanel` becomes `ProposalElement`
  with `requestProposalLayout`.
- **Not edited:** `Element.swift`, `Component.swift`, `Frame.swift` (`MC-H`).
- **Tests:**
  - helper conversions to `ProposalElement`:
    - `NativeLayoutIntegrationTests.swift` (5);
    - `ProposalLayoutIntegrationTests.swift` (1);
    - `ProposalModifierValidationTests.swift` (1);
    - `ModifierCompositionProofTests.swift` (**2**: `CountingProposalLeaf`
      becomes a `ProposalElement`; `CountingProposalComponent`'s and
      `EmptyProposalComponent`'s content become `some ProposalElementGroup`
      where spelled opaquely);
    - `NativeBoundaryIntegrationTests.swift`. There, `Toggle`'s content becomes
      `some ProposalElementGroup`; `RegisteredAfterTheContainer` becomes a
      `ProposalElement`; and `LegacyNodeUnderAProposalMarker` becomes a
      `ProposalElement` whose typed entry returns
      `ProposalNodeID(pass.requestNode(style: Style(), children: []))` through
      `@testable`'s internal init, so the existing trap test still reaches the
      trap (`MC-G` hole 3);
  - `ProposalLayoutCompileGuards.swift`: its external fixtures now write the
    typed entry, keeping each guard's assertion and diagnostic;
  - `Tests/MetalUITests/ProposalNodeIDCompileGuards.swift` (new), plain import,
    file scope, Swift 6 mode, `typecheckFile` as `SA-P` requires;
  - `Tests/MetalUITests/ProposalNodeIDTests.swift` (new): tests 7 and 8.

### Tests

**Before and during the guard runs:**

- Run `swift build --build-system native` before the first guard run.
- **Mutate each new guard red once** and record the red line, since guards skip
  silently when the modules directory is not found.
- **Print each real diagnostic before asserting on it.** The expected fragments
  below are the skeleton's, and must be confirmed against the real module.

| # | test | pins | before | mutation that must redden it |
|---|---|---|---|---|
| 1 | guard `aMarkerConformerThatRegistersALegacyNodeDoesNotCompile` | today's `LegacyNodeUnderAProposalMarker` shape (`Element` + marker, `requestNode`) is rejected with "does not conform to protocol 'ProposalElementGroup'" | **red**: it compiles today (`SA-R`) | add `extension ProposalElementGroup { public mutating func requestProposalGroupLayout(…) -> … { preconditionFailure() } }` |
| 2 | guard `aProposalNodeIDCannotBeMintedOutsideMetalUI` | `ProposalNodeID(pass.requestNode(…))` fails with "initializer is inaccessible due to 'internal' protection level" | **red**: "cannot find 'ProposalNodeID' in scope" lacks the fragment | make the init `public` |
| 3 | guard `aComponentOnlyTakesTheProposalMarkerWithProposalContent` | Three fixtures. Two are rejected with "does not conform to protocol 'ProposalElementGroup'": a `Component` with `Text` content, and one with `var content: some ElementGroup` over a `Rectangle`. The third, with `some ProposalElementGroup`, is accepted. `#require` that the fixtures disagree | **red**: both negatives compile today | an unconstrained `extension Component { requestProposalGroupLayout … preconditionFailure() }` |
| 4 | guard `aNativeRegistrarRejectsALegacyChild` | `pass.requestNativeFrame(child: pass.requestNode(style: Style(), children: []))` fails with "cannot convert value of type 'LayoutNodeID' to expected argument type 'ProposalNodeID'" | **red**: compiles today | add a `requestNativeFrame(child: LayoutNodeID, …)` overload |
| 5 | guard `aProposalLayoutContainerOnlyAcceptsTypedChildren` | an external element over `requestNativeLayout(_:children:)` passing `[LayoutNodeID]` is rejected, and passing `requestProposalGroupLayout`'s result is accepted | **red**: untyped compiles today, and the typed spelling does not exist | a `children: [LayoutNodeID]` overload |
| 6 | guard `aProposalGroupWhoseEntryPointsDisagreeStillCompiles` (**pinned wrong on purpose**, `MC-G` hole 1) | Two fixtures against the real module. The **positive** is `liar4`'s shape (both entry points written, legacy nodes from one, zero typed nodes from the other): it typechecks. The **in-test negative** is the same fixture with its `requestProposalGroupLayout` deleted: it is rejected with "does not conform to protocol 'ProposalElementGroup'". `#require` that the two disagree, so a broken instrument cannot pass, and print both results | **red**: the requirement does not exist, so the negative compiles and the `#require` fails | **after lane 3 lands:** delete the positive fixture's `requestProposalGroupLayout`, making it identical to the negative. The positive assertion reddens. Record that red line. It exists to be inverted by whoever closes the hole |
| 7 | `anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected` (**pinned wrong on purpose**, `MC-G` holes 2 and 6) | Two arms, each a `ProposalElement` inside `VStack { HStack { it }; Rectangle(width: 5, height: 5, color: .accent) }`, 140×90. **Arm a:** its typed entry calls `pass.requestNode(style: Style(), children: [])`, discards the result, and returns a typed leaf. It renders: prepaint bounds 10×10, 1 rect. **Arm b:** its typed entry lays out a discarded `Box { StatefulLegacyLeaf() }.background(.accent)` through `requestGroupLayout(under: id, at: &c)` (the leaf writes its `@State` from 7 to 8 in `requestLayout`), then returns a typed leaf. Measured at `f64e58a` in the `HStack`-only form: no trap; the leaf's `$state0` slot reads 8 and is live; the orphan `Box`'s `$anim` slot is live; nothing of the orphan subtree is painted; `nodeCount` is 5 (2 orphan nodes). The test pins the measured values in its own `VStack` form | **green, as measured** (`MC-G`) | an orphan check in `LayoutPass.requestNode` during native registration reddens arm a. Nothing is available for arm b short of unregistered-state detection; the doc comment says so |
| 8 | `aNativeNodeRegisteredTwiceIsNotRejected` (**pinned wrong on purpose**, `MC-G` hole 4) | Each arm in `VStack { HStack { it } }`, 140×90. **Arm a:** one typed leaf (10×10) passed twice to `requestNativeLinearStack(children: [leaf, leaf], axis: .horizontal)`. **Arm b:** one typed leaf handed to two frames (30×30 `.topLeading`, 50×50 `.bottomTrailing`) in one horizontal stack. Measured at `f64e58a` with untyped ids, which the typed ids wrap unchanged: arm a gives stack bounds (60, 0, 20×10), leaf bounds (70, 0, 10×10), measure calls 1, `nodeCount` 4; arm b gives stack (30, 0, 80×50), leaf (100, 40, 10×10), measure calls 2, `nodeCount` 6 | **green, as measured** | a duplicate-parent precondition in `LayoutTree.appendNode` closes the hole. It **traps** this test's process, so whoever closes it converts the test to an exit test; the doc comment says so |
| 9 | `aTypedNodeIDStoredFromAnEarlierFrameTraps` (`MC-G` hole 7, **added after `MC-Q` finding 8**) | exit test (`#expect(processExitsWith: .failure)`, stderr fragment "outlived the tree that issued it"). A `@MainActor final class` box captured by the content closure; a `ProposalElement` whose typed entry stores its `ProposalNodeID` in the box on frame 1 and returns the stored one on frame 2, inside `HStack`, through a real `Frame` each frame. **Control:** the same element returning a fresh id on frame 2 exits with success | does not compile before lane 3 (no typed id) | the element returns a fresh id on frame 2 as well: the child exits 0 and the failure expectation reddens. Record which registrar's child loop reports the trap (by reading, `LayoutTree.appendNode` → `slot`) |
| — | lane 1 test 6 | the typed defaults bind state and advance the cursor, through the helper (`MC-H`) | green | four mutations, each run separately: delete `StateBinder.bind` from the helper (a and c read 0, and legacy `@State` tests redden too); `ProposalElement`'s typed default computes its id with `.child` directly instead of calling the helper (a reads 0); `Component`'s typed default does the same (c reads 0); delete the helper's `cursor += 1` (a and b share an id) |
| — | `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer` (existing, rewritten helper) | the run-time backstop survives | green | its existing mutation: delete `newNativeLinearStack`'s child loop (`SA-T` item 1) |
| — | `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration` (existing) | `MC-G` hole 5: `Toggle().width(Pixels(70))` still compiles after lane 3 and still traps | green | its existing mutation (the `setStyle` check deleted) |
| — | the existing SA-F guards | an external leaf, container and algorithm still build from public API, on the typed entry | green after the fixture edits | make `ProposalElement`'s `requestLayout` default `internal`; the external leaf fixture must redden |

**The demo (`MC-J`).**

- **Baselines from `f64e58a`**, built from the same `git archive` directory as
  lane 2's: the release preview window (`METALUI_NATIVE_LAYOUT_PREVIEW=1`) and
  the default window.
- **After the lane**, re-capture both and count the differing pixels. The
  expected difference is none, beyond desktop corners.

### Expected counts

1101 (or 1102) → **1110** (or 1111) tests: five new guards, the hole guard,
and tests 7, 8 and 9. Guards 47 → **53**, re-counted by `grep -c canTypecheck`
per file, not from this number. Goldens 97.

### Docs owed by lane 3

- `MC-G`, `MC-H` Mutations lines; each guard's red line and real diagnostic;
  guard 6's post-landing red line; the preview capture.
- Doc comments made false at their lines:
  - `ProposalElementGroup.swift`'s ("Marks … subtree");
  - `Passes.swift`'s registrar docs;
  - `ProposalLayoutContainer`'s "calls `content.requestGroupLayout`";
  - `NativeBoundaryIntegrationTests`' "The marker has no requirements, so this
    compiles (ruling SA-R)";
  - `ElementGroup.swift`'s doc on `Element`'s default, and `AnyElement`'s
    "Identical to `Element`'s default for the CURSOR", which name the lines
    the helper replaces.
- Record §10: that `SA-R`'s amended criterion is now met, with `MC-G`'s seven
  holes. Editing the SA doc itself is the integration step's.

---

## Verification common to every lane

- **The suite.** Run `swift test --no-parallel` (and `--build-system native`
  for the guards). Read the `Test run with N tests` line, not the exit status.
  Grep the log for `error:` and `warning:`: both must be 0, apart from
  SwiftPM's own deprecation notice under `--build-system native`, which
  CLAUDE.md records.
- **Goldens.** `find Tests -name '*.json' | wc -l` is 97, and
  `git diff --stat f64e58a -- '*.json'` is empty.
- **No sleeps; counts, not clocks.**
  - Window tests drive `drawFrameIfNeeded`, `simulateInput` and
    `simulateTick`.
  - The allocation measurement counts.
  - The type-check-time measurement is recorded, never asserted.
- **Traps** are exit tests (`#expect(processExitsWith:)`) asserting a stderr
  fragment, as in `FontResolverTrapTests.swift`.
- **Mutation.** This worktree runs one agent at a time, so it is not
  contended. Commit first, restore from `cp` backups, and verify with
  `git status --short`. Discard and re-take any run taken while another
  process was editing the tree.
- **`swift package clean`** before the recorded run, in two cases (CLAUDE.md's
  build rule):
  - after lane 2 deletes a public type and adds requirements to `ElementGroup`;
  - after lane 3 changes public signatures across modules.
- **Demo captures.** `MC-J`'s method:
  - the baseline is built from `git archive f64e58a`;
  - no input is sent, and the pointer is not moved;
  - the pointer position is logged.

## Merge notes for the integration step

- **Shared files edited:**
  - `ElementGroup.swift`:
    - lane 2, two additive requirements (`LayerBase`, `_wrap`);
    - lane 3, `Element`'s default `requestGroupLayout` entry replaced by the
      helper call (3 lines → 1);
  - `Passes.swift`: lane 3, the registrar block's types only;
  - `Box.swift`: lane 2, the two `padding` signatures and docs;
  - `AXEmitSiteTests.swift`, `AnimationTests.swift`,
    `BackgroundChainTests.swift`, `InputDispatchTests.swift`: lane 2, one
    additive arm block each.
- **Shared files NOT edited:** `Element.swift`, `Component.swift`,
  `Handlers.swift`, `Frame.swift`, `Window.swift`, `Platform.swift`,
  `Tests/MetalUITests/Fakes.swift`.

### Collisions with the environment track (`feat/environment` at `f4dcad8`, as committed)

**Revised after lane 1's critic round (`MC-Q` finding 5).** The first version
was written against that track's spec, not its commits.

1. **`EnvironmentScope`'s proposal conformance stops compiling.**
   - **What breaks.** `feat/environment:Sources/MetalUI/EnvironmentScope.swift`
     declares `extension EnvironmentScope: ProposalElementGroup where Content: ProposalElementGroup {}`
     and its doc names this merge as an obligation (ruling EV-W). With lane
     3's requirement, that is a compile error ("does not conform"). Loud.
   - **The silent half.** The typed `requestProposalGroupLayout` the merge
     writes must go through the same resolve-once-then-push path as its
     untyped `requestGroupLayout` (`pass.frame.scopedValues(applying:)`, then
     `pass.frame.withEnvironment(values) { … }`, storing `values` in the
     layout for the later phases, EV-V). A bare forward skips the layout-phase
     push, and layout-time reads on the proposal path silently read the
     parent's values.
   - **The test already exists on that branch:** E11,
     `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase`
     (`feat/environment:Tests/MetalUITests/EnvironmentTests.swift:468`). It
     reads layout, prepaint and paint (`[7, 7, 7]`) under an `HStack` and
     under a `ProposalScrollView`, and its doc names the layout slot as the one
     a merge could break. **Its mutation at merge:** the typed entry as a bare
     forward reddens the layout slot of both triples. The test the first
     version of these notes invented (`aProposalContainerReadsTheEnvironmentDuringLayout`)
     is withdrawn.
2. **`StateBinder.bind` is `bind(_:in:id:)` on that branch**
   (`feat/environment:Sources/MetalUI/StateReflection.swift:104`): the frame is
   passed, not a `table:` and an `environment:`, and by EV-W no overload keeps
   the old `bind(_:table:id:)` spelling and the frame never gains a default.
   - **Lane 3 adds no call sites.** Both typed defaults and `Element`'s
     untyped default go through `GroupMember.swift`'s one helper (`MC-H`).
   - **The same five sites remain** (`ElementGroup.swift:112,129,139`,
     `Component.swift:130`, `Frame.swift:1349` at `f64e58a`);
     `ElementGroup.swift:112` moves into the helper.
   - **At merge:** a textual conflict at `ElementGroup.swift:112`, and a
     compile error in `GroupMember.swift` until the helper calls
     `StateBinder.bind(element, in: pass.frame, id: id)`. Neither is silent.
   - **`Component.swift:130` stays the one copy** outside the helper; the
     environment track has already edited it.
   - **That track's record is behind this one:**
     `feat/environment:docs/record/11-environment.md:258-259` still says this
     spec adds "two `StateBinder.bind` call sites (`MC-H`)", which
     `8cdb25e`'s helper superseded. Integration corrects it; this track does
     not edit another track's record.
3. **`EnvironmentScope` is a phase-delegating wrapper on both paths and has no
   arm in `everyModifierWrapperDelegatesEachPhaseExactlyOnce`** (lane 1 test
   7). `MC-F`'s rule makes an armless wrapper a gap. **Owed at merge:** two
   arms, `Row { CountingLeaf("x").environment(\.probe, 1) }` (legacy) and
   `HStack { CountingProposalLeaf("x").environment(\.probe, 1) }` (proposal,
   through the typed entry), each `[1, 1, 1]`. **Mutation:** the typed entry
   calls `content.requestProposalGroupLayout` twice (proposal arm reads
   `[2, 1, 1]`, or traps a one-node precondition, which the arm's `try #require`
   of the count must survive).

### AB-O and every per-element hook in `Element`'s group defaults (AX-bridge track)

**Added after lane 1's critic round (`MC-Q` finding 2).**

- **The hazard.** `feat/ax-bridge:Sources/MetalUI/ElementGroup.swift:130-140`
  (ruling AB-O) suppresses a `display: none` node's subtree from accessibility
  inside `Element.prepaintGroup`, once per ELEMENT. Nested `Box`es pass that
  check at every level; `ModifiedElement`'s layers are not elements and do
  not. After merge, `Text("x").padding(4).hidden().frame(width: 60)` — whose
  hidden padding layer is inner after `.frame` wraps — publishes the text
  where nested boxes hide it. `MC-B`'s oracle (test 4) cannot see it: it
  compares no accessibility records.
- **The rule for integration:** **any hook added to `Element`'s default
  `requestGroupLayout`, `prepaintGroup` or `paintGroup` is mirrored per layer
  in `ModifiedElement`.** On this branch those defaults enter the id and
  bind/re-bind `@State`; layers hold no `@State`, so nothing is mirrored yet.
- **AB-O's mirroring.** Move AB-O's check into one internal helper, e.g.
  `Frame.prepaintingNode(_ node: LayoutNodeID, _ body: () -> R) -> R`
  (suppress when collecting and the node's style is `display: none`), called
  by `Element.prepaintGroup` around `prepaint(…)` and by
  `ModifiedElement.prepaint` around layer k's registration and everything
  inside it (lane 2 writes the loop so that wrap is possible).
- **The owed test:** `anInnerHiddenLayerHidesItsSubtreeFromAccessibilityAsNestedBoxesDo`,
  in an active fake window, compares `Frame.axEmissions` ids for
  `Row { Text("x").onClick {}.padding(4).hidden().frame(width: 60) }` against
  the hand-built `Box(frameStyle, content: Box(paddingStyle, content: Text("x").onClick {}).hidden())`;
  `#require` first that a disagreeing oracle (the same boxes without
  `.hidden()`) publishes the text, then expect the chain to publish nothing
  the boxes do not. **Mutation:** remove the per-layer call in
  `ModifiedElement.prepaint`; the chain publishes the text.
- **Also named in `feat/ax-bridge`'s spec:** `FrameModifier` as an emit site
  and "untouched" (below).

### `NativeTappable.swift`: lane 3 against AX lane 3

Lane 3 rewrites `OnTapModifier`'s layout entry to the typed one and returns its
child's typed id (`NativeTappable.swift`). AX-bridge lane 3 edits
`OnTapModifier.prepaint` in the same file (one line, passing
`synthesizesAccessibility: false`, ruling AB-Y;
`feat/ax-bridge:docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md:703`).
Different functions, same file: expect a textual conflict; keep both.

### `FrameModifier` is deleted by lane 2; three places in the other tracks name it

Rule: **every per-site list that names `FrameModifier` gets its arm changed to
`ModifiedElement` (a two-layer chain, asserting on the inner layer too). The
arm is never deleted.**

1. **Environment track, D2:** `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`
   has an arm "frame (`.frame(width:height:)`'s `FrameModifier`)".
2. **AX-bridge track** (`2026-09-15-accessibility-bridge-design.md`):
   - §"Scope boundaries" lists `FrameModifier` as an in-scope emit site;
   - line 513 says `FrameModifier` is "untouched".

   After merge, the emit site is `ModifiedElement`, once per layer.
3. **`InputDispatchTests.swift` and `AXEmitSiteTests.swift`:** `MC-I` adds
   `ModifiedElement` arms to the same lists those tracks extend. Expect
   textual conflicts in both arm lists; keep both sides' arms.

### Other likely textual conflicts

- any parallel track that adds AX, focus or environment reads to proposal
  elements, which lane 3 rewrites the layout entry of;
- `ElementGroup.swift`'s protocol body, if another track adds a requirement
  (lane 2 adds two).

### For CLAUDE.md, owned by integration

- the guard count;
- "seven registering points" and the background-site count (`FrameModifier`
  gone, `ModifiedElement` in);
- a Component-section note that a caller's `.frame` now returns
  `ModifiedElement`;
- `SA-R`'s status;
- the overlay collision's removal from record §09's hazards, and the
  identity-section note that an overlay numbers under a synthetic
  `.positional(-1)` child of its modifier, so its state is independent of the
  primary's shape (`MC-P`, SwiftUI parity; lane 1's "index depends on the
  primary" note is withdrawn);
- the rule that `Element`'s group-default hooks are mirrored per layer
  (AB-O above);
- the candidate divergence from lane 2 test 5 (`MC-C`), if kept;
- `MC-G`'s seven holes, and the `_wrap` hole (`MC-A`), for the
  declared-but-inert and holes lists;
- the guard count (47 after lane 2, 53 after lane 3, re-counted) and that lane
  2's test 6 guard reads `-solver-scope-threshold`, a frontend flag CI's
  toolchain must still accept.
