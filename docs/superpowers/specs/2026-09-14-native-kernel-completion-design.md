# Native kernel completion design

**Milestone:** SwiftUI replacement task 2, the part still open at `34e2841`
(`plans/2026-09-12-swiftui-alignment.md`, task 2's "Not done" list).

**Status (2026-09-14):** design only. Written against `34e2841` on
`feat/kernel-completion`. No source has changed. Rulings are prefixed **`SA-`**
and lettered, in `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`.
A bare `SA-3` is a typo, not a citation.

This spec **replaces** two sections of
`specs/2026-09-12-native-layout-kernel-design.md`: "Kernel protocol and tree
representation" and "Root and compatibility boundary". That spec's Status list
and record §09's "Hazards this range introduced" are the inventory this design
closes. Everything else in the 2026-09-12 spec stands as annotated.

## What this design delivers

Plan task 2 names five missing pieces, (a) to (e). Each goes to exactly one
lane, and the lanes are implemented **in this order**:

| lane | items | one line |
|---|---|---|
| 1. **protocol** | (a) a layout protocol; (e) the migration story for external custom elements | `ProposalLayout`, two pairs of subview proxies, one new node kind, one public container element, and compile guards that an outside module can use them |
| 2. **boundaries** | (b) an invalidation contract; (c) mixing, which has no adapter and is not even rejected one way | a trap in every direction a legacy and a native node can meet, a written and pinned cache contract, and `isLayingOut` protection on the native path |
| 3. **robustness** | (d) validation, a depth guard, work counters | reject only what SwiftUI rejects or what makes an answer non-finite; a native depth guard; three counters and a count test on a branching tree |

**Why this order.** Lane 1 replaces the `inout` cache dictionary with an
internal run object. Lane 2's contract and re-entrancy checks and lane 3's
counters and depth counter all live on that object. Lane 2 must also cover the
node kind lane 1 adds: a custom layout is one more native registrar that must
reject legacy children, and one more measurement path the contract pins. Lane 3
validates proposals and rects that proxies produce, and proxies exist only
after lane 1. Running lane 3 before lane 2 would validate a tree whose authority
boundary is still open in one direction.

**Not in this design.** Ruling `SA-N` lists what the probes found and who owns
it. Excluded: the root sizing rule; frame min/max semantics; `Spacer()`'s
default minimum; the aspect ratio's unspecified branch; where padding places
its child; porting any legacy container; the typed-modifier foundation (task
3); animation on the proposal path; replacing `Style` resolution.

## Where the kernel stands at `34e2841`

Read in full for this design. Line numbers are `34e2841`'s.

- **`Sources/MetalUILayout/LayoutTree.swift`.**
  - Eleven public `newNative*` registrars (`:110-266`). Each routes through
    public `newNode(style: .default, children:)` (`:89`), which checks child
    generations only.
  - The kernel entry is `computeNativeLayout(root:proposal:in:)` (`:274-282`).
    It creates one `[NativeMeasurementKey: LayoutMeasurement]` per call and
    threads it `inout` through private `measureNative` (`:387-490`) and
    `placeNative` (`:492-610`).
  - Both functions switch over `private enum NativeNode` (`:835-849`).
    Rounding follows (`:786-792`).
  - A native registrar given a legacy child traps in `nativeNode(_:)`
    (`:379-385`).
- `isLayingOut` (`:74`) is set only by legacy `computeLayout`
  (`FlexEngine.swift:102-103`). `setStyle`'s precondition (`:291-295`)
  therefore cannot fire during native layout.
- `ProposalAlignment.horizontalFactor`/`verticalFactor` are internal
  (`:818-832`).
- `Sources/MetalUI/Passes.swift:60-134`: eleven public `LayoutPass.requestNative*`
  mirrors. `Frame.computeRootLayout` (`Frame.swift:1165-1184`) switches on
  `tree.isNativeLayoutNode(root)` alone.
- The proposal elements live in `NativeElements.swift`,
  `NativeModifiedContent.swift`, `NativeOverlayModifier.swift`,
  `NativeTappable.swift`, `ProposalScrollView.swift` and `ProposalText.swift`.
  All of them compose kernel registrars; none adds an algorithm.
- `NativeModifiedContent.swift:271-272` and `:279` repeat the kernel's ratio
  and priority preconditions at the modifier.
- Tests:
  - 18 kernel tests in `Tests/MetalUILayoutTests/NativeLayoutTests.swift`;
  - 41 element tests in `Tests/MetalUITests/NativeLayoutIntegrationTests.swift`;
  - 4 proposal typecheck guards in `ElementGroupTrapTests.swift`.

**Counts at `34e2841`, re-taken for this design:**
- **993 tests.** Measured as 995 with two uncommitted probe tests present, which
  were then deleted.
- **97 goldens.**
- **39 guards:** 19 + 10 + 5 + 2 + 3, per-file `grep -c canTypecheck`, with
  `UnitSafetyTests`' comment hit excluded.

## Evidence this design stands on

All of it was run in this session. Nothing here is quoted from an earlier
document. Commands and raw output are in the decisions doc under the ruling
named.

1. **`docs/probes/swiftui-layout-protocol-contract.swift`**: SwiftUI's custom
   `Layout` contract. It covers:
   - the per-pass memo (arms A/B/C) and the cross-pass memo (F/G/H);
   - placing during measurement (D);
   - the proxy surface (E/E2), and priority under an outer modifier (L);
   - an unplaced subview (I/I2) and a subview placed twice (J);
   - placement proposal plus anchor (K);
   - non-finite answers (N) and non-finite positions (M).

   The output is recorded in its header.
2. **`docs/probes/swiftui-layout-input-validation.swift`**: what SwiftUI
   accepts, diagnoses, answers non-finitely, traps on or hangs on. It covers
   spacing, padding and where padding places its child, frame dimensions,
   spacer minimum, proposals, priority and aspect ratio. Every group has a
   positive control, and the output is recorded in its header.
3. **How the probes run** (`SA-O`).
   - `/usr/bin/swift <file>` (Apple Swift 6.4) runs both as scripts. It
     reproduces every size and placement line.
   - It prints none of SwiftUI's os_log diagnostics. Those need the compiled
     form, `swiftc` then `OS_ACTIVITY_DT_MODE=1`.
   - The PATH's swiftly 6.3.3 `swift` fails with a JIT "Symbols not found"
     error.
4. **Native mixing today, run.** A native leaf inside a legacy `Column`,
   rendered through `Frame` at 140×90:
   - its measure closure ran **0 times**;
   - its prepaint bounds were **(70, 0, 0×0)**.

   That confirms record §09 hazard 1 by execution. With a temporary
   `newNode` precondition rejecting native children, the suite read **995
   tests passed**: the 993 existing tests plus the two env-gated probe tests,
   which returned early. No existing test mixes the engines. A temporary
   `setStyle` precondition rejecting native nodes gave the same 995. `SA-G`.
5. **Native stack depth, bisected in this pass.**
   - Setup: debug, a `Thread` with a 1 MB stack, one `swift test --skip-build`
     per candidate depth, from an uncommitted probe test.
   - A chain of `padding` or `frame` nodes survives **193** levels and dies at
     194.
   - A chain of one-child `linearStack` nodes survives **171** and dies at 172.
   - Both reproduce an earlier pass's numbers exactly. `SA-L`.
6. **The lane 1 API typechecks from outside.**
   - A temporary skeleton of the public API in this spec was built with
     `swift build --build-system native`. Fixtures were then typechecked with a
     plain `import MetalUI`, using the flags `typecheck(_:importing:)` uses.
   - The positive fixture compiles: a custom layout, a leaf, a generic container
     element, `Diagonal() { … }`, `Diagonal { … }` and
     `ProposalLayoutContainer(Diagonal()) { … }`, nested in `HStack` and
     `VStack`.
   - The three negatives fail with the diagnostics quoted in lane 1's guard
     table.
   - The skeleton was then deleted. `SA-P`.
7. **A plain import in one test file does not see internals granted by
   `@testable` in another file of the same test target.** This was measured on
   a two-file scratch package, for a free function and for a member of a public
   enum. `SA-P`.

## Shared mechanism: the run object (introduced by lane 1)

```swift
// Sources/MetalUILayout/NativeLayoutRun.swift  (internal)
final class NativeLayoutRun {
    unowned let tree: LayoutTree
    var cache: [NativeMeasurementKey: LayoutMeasurement] = [:]
    var isActive = true            // lane 1: false once the entry point returns
    var activePlacement: UInt64 = 0 // lane 1: token of the innermost placeSubviews in progress, 0 = none
    var nextPlacementToken: UInt64 = 1
    var measureDepth = 0           // lane 1: > 0 while any measurement body runs
    var depth = 0                  // lane 3: the recursion guard
    var work = NativeLayoutWork()  // lane 3: the counters
}
```

- **It must be a `final class`, not a struct.** `LayoutContext.swift:4-8`
  records why: a struct copied per recursion level shares no cache.
- **Its lifetime is one call.** Each public entry point creates one, marks it
  inactive on return, and drops it. It never lives on the tree
  (`LayoutContext.swift:10-12`, ruling C-3's footing).
- **Proxies hold the run strongly, not `unowned`.** An escaped proxy then
  reaches the `isActive` precondition and its message, instead of an unowned-read
  crash with no attribution.
- **Each lane adds only the fields it owns.** The listing above is the end
  state.

---

## Lane 1 — protocol

### Rulings

- `SA-A`: the protocol shape.
- `SA-B`: built-ins stay enum cases.
- `SA-C`: measurement cannot place.
- `SA-D`: the proxy surface.
- `SA-E`: placement semantics.
- `SA-F`: registration and the migration story.

### Public API

```swift
// Sources/MetalUILayout/ProposalLayout.swift  (new)

/// A proposal-layout algorithm: measure subviews at proposals, then place them.
/// MetalUI's value counterpart to SwiftUI's `Layout`, not a source-compatible copy.
public protocol ProposalLayout: Sendable {
    /// The subviews handed in can measure and cannot place (SA-C).
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement

    /// `bounds` is root-absolute. A subview this never places is centred in
    /// `bounds` at its answer to `proposal`; a subview placed twice keeps its
    /// last placement (SA-E).
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize,
                       subviews: PlacementSubviews)
}

public struct MeasurementSubviews: RandomAccessCollection {
    public var startIndex: Int { get }
    public var endIndex: Int { get }
    public subscript(position: Int) -> MeasurementSubview { get }
}

public struct MeasurementSubview {
    /// The value of a `layoutPriority` node that IS this subview, else 0.
    /// The built-in stack's rule (`nativeLayoutPriority`); SwiftUI agrees (probe L).
    public var priority: Double { get }
    /// True for a spacer node, directly or under any depth of `layoutPriority`
    /// nodes, and never through frame, padding or any other wrapper — the rule
    /// of `isNativeSpacer` (SA-D).
    public var isSpacer: Bool { get }
    /// Measures through the run's cache: once per distinct proposal (SA-H).
    public func sizeThatFits(_ proposal: ProposedSize) -> LayoutMeasurement
}

public struct PlacementSubviews: RandomAccessCollection {
    public var startIndex: Int { get }
    public var endIndex: Int { get }
    public subscript(position: Int) -> PlacementSubview { get }
}

public struct PlacementSubview {
    public var priority: Double { get }
    public var isSpacer: Bool { get }
    public func sizeThatFits(_ proposal: ProposedSize) -> LayoutMeasurement
    /// Stores the subview at its answer to `proposal`, offset from `position`
    /// by `anchor`'s factors times that size (probe K), then places its subtree.
    public func place(at position: Point<Double>,
                      anchor: ProposalAlignment = .topLeading,
                      proposal: ProposedSize)
}
// No proxy type has a public initializer.
```

`ProposalAlignment.horizontalFactor` and `.verticalFactor` become **`public`**.
An external layout that takes an alignment otherwise cannot compute a
cross-axis offset, and the reference stack below is exactly such a layout.

```swift
// LayoutTree (MetalUILayout)
public func newNativeLayout(_ layout: some ProposalLayout,
                            children: [LayoutNodeID]) -> LayoutNodeID

// LayoutPass (MetalUI): a one-to-one mirror, like the other eleven
public func requestNativeLayout(_ layout: some ProposalLayout,
                                children: [LayoutNodeID]) -> LayoutNodeID

// Sources/MetalUI/ProposalLayoutContainer.swift  (new)
public struct ProposalLayoutContainer<L: ProposalLayout, Content: ProposalElementGroup>: Element {
    public var layout: L
    public var content: Content
    public init(_ layout: L, @ElementBuilder content: () -> Content)
}
extension ProposalLayoutContainer: ProposalElementGroup {}

extension ProposalLayout {
    /// `MyLayout() { A(); B() }`, as SwiftUI's `Layout.callAsFunction`.
    @MainActor
    public func callAsFunction<Content: ProposalElementGroup>(
        @ElementBuilder _ content: () -> Content) -> ProposalLayoutContainer<Self, Content>
}
```

### Kernel changes

1. **Add `case custom(any ProposalLayout)` to `NativeNode`.** The eleven
   built-in cases stay (`SA-B`). `newNativeLayout` validates every child with
   `nativeNode(_:)`, as `newNativeLinearStack` does (`:247`).
   `isNativeLayoutNode` is true for it: it lives in the same `nativeNodes`
   store, so `Frame.computeRootLayout` needs no change.
2. **Replace the `inout` cache with `NativeLayoutRun`** in `measureNative`,
   `placeNative` and every private helper that forwards the cache. The change
   is mechanical: no built-in case's arithmetic changes. The 18 kernel tests and
   41 integration tests are the regression net, and they must pass before
   anything else in this lane lands.
3. **`measureNative` for `.custom`.** Build `MeasurementSubviews` over
   `(run, children)`. Then `run.measureDepth += 1`, call
   `layout.sizeThatFits(proposal:subviews:)`, and `run.measureDepth -= 1`.
   A proxy's `sizeThatFits` calls `measureNative(child, proposal:, run:)`, so
   every proxy measurement goes through the cache.
   - Every proxy member first checks
     `precondition(run.isActive, "a layout subview outlived its layout run")`.
   - For symmetry, wrap the built-in cases' bodies in the same `measureDepth`
     bracket.
4. **`placeNative` for `.custom`.**
   1. Store `bounds` for the node, as every case does (`:495`).
   2. Take a fresh token from `nextPlacementToken`, and save
      `run.activePlacement` before setting it to that token.
   3. Build `PlacementSubviews` carrying the token and a `placed` flag per child,
      held in a small reference box shared by the collection's proxies.
   4. Call `placeSubviews`, then restore `run.activePlacement`.
   5. Place every child whose flag is still false: measure it at the parent's
      `proposal`, and place it centred in `bounds` at that answer (probe I/I2).
5. **`PlacementSubview.place`** runs in this order:
   1. `precondition(token == run.activePlacement, "a PlacementSubview was used outside its placeSubviews call")`.
   2. `precondition(run.measureDepth == 0, "a PlacementSubview was used during measurement")`.
      This is the dynamic backstop behind the static one (`SA-C`, probe D).
   3. Measure at `proposal` through the cache.
   4. Compute the rect as `position − anchorFactor × size`.
   5. Set the flag and call `placeNative(child, in: rect, proposal:)`.

   A second `place` of the same child re-runs `placeNative` and overwrites, so
   the last placement wins (probe J).

### Migration story for external custom elements (item e)

This table goes into the inventory's "Completion criteria for task 1", and into
a dated note in `specs/2026-09-12-native-layout-kernel-design.md`.

| an external module wants | it writes, using only public API |
|---|---|
| a leaf | an `Element` whose `requestLayout` returns `pass.requestNativeLeaf { proposal in … }`, plus `extension X: ProposalElementGroup {}`. This works today; the demo's `PriorityPreviewPanel` does it (`main.swift:930-955`). |
| a container algorithm | a `struct X: ProposalLayout`, used as `X() { … }`, `X { … }` or `ProposalLayoutContainer(X()) { … }` |
| a container element with its own paint or input | an `Element` that calls `content.requestGroupLayout(under:at:pass:)`, then `pass.requestNativeLayout(layout, children:)`, and delegates `prepaintGroup`/`paintGroup` |
| a legacy root | unchanged: `requestNode`/`requestLeaf`. Neither is deprecated in this milestone (`SA-F`). |

**What stays unchecked, named so nobody assumes otherwise.**
`ProposalElementGroup` still has no requirements. A conformer that registers a
legacy node compiles, then traps at registration. Lane 2 pins that trap from
both the kernel and an element.

### Files

- **New in `Sources/MetalUILayout/`:** `ProposalLayout.swift` (the protocol and
  four proxy types) and `NativeLayoutRun.swift`.
- **Changed:** `Sources/MetalUILayout/LayoutTree.swift` (the case, the
  registrar, the run refactor, the public factors).
- **New in `Sources/MetalUI/`:** `ProposalLayoutContainer.swift`, holding the
  element, its conformance and `callAsFunction`.
- **Changed:** `Sources/MetalUI/Passes.swift` (`requestNativeLayout`) and
  `Sources/MetalUI/Frame.swift` (its internal mirror).

### Tests

**Order.** Land the public API first as a skeleton:
- `.custom` measures `.zero` and places nothing;
- proxies answer 0, false and `.zero`;
- `place` does nothing.

Each test below must then be **red by assertion** (for an exit test, red is
exit 0 or the wrong stderr), never merely unable to compile. Record the red run,
then build the real behaviour. Run every mutation in a separate `git worktree`
off the lane branch. Name the tests each one reddens in the decisions doc,
under the ruling.

**`Tests/MetalUILayoutTests/ReferenceLinearStack.swift` (new).** It uses a
**plain `import MetalUICore` and `import MetalUILayout`, never `@testable`**,
which evidence 7 shows is a per-file property.
- **`ReferenceLinearStack: ProposalLayout`** reimplements the `linearStack` case
  line for line: `stackChildProposal`, `resolvedStackMainSize`, spacer surplus,
  `stackMainAllocations` and cross-axis alignment. It uses only `priority`,
  `isSpacer`, `sizeThatFits`, `place` and the alignment factors.
- **Two positive controls** each differ from it in one rule:
  `PriorityBlindLinearStack` reads every priority as 0, and
  `SpacerBlindLinearStack` reads every `isSpacer` as false.
- **The plain import is the proof** that the algorithm needs nothing internal.
  If it compiles only with `@testable`, the protocol is insufficient.

`Tests/MetalUILayoutTests/ProposalLayoutTests.swift` (new, `@testable` for the
internals it reads):

| test | red before (skeleton) | mutation that must redden it after |
|---|---|---|
| `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects`: one tree builder, described below, is run once through `newNativeLinearStack` and once through `newNativeLayout(ReferenceLinearStack(…))` | every comparison fails, because the custom stack stores nothing | (1) proxy `priority` returns 0; (2) `isSpacer` stops recursing through `layoutPriority`; (3) `place` sizes the child at the parent's proposal instead of the placement proposal; (4) `placeNative` for `.custom` drops `bounds.x`. Each must redden this test. The two controls exist to prove (1) and (2) change the rects at all. |
| `aSubviewMeasuresOncePerDistinctProposalWithinOneRun`: a custom layout asks child 0 at (50, 50) twice, then at (70, 50), in `sizeThatFits`; `placeSubviews` asks (50, 50) again. The leaf closure's count goes 1, then +1, then +0. Probe A/B/C. | counts 0 | the proxy's `sizeThatFits` calls the leaf closure directly instead of `measureNative` |
| `placingASubviewUsesItsAnswerToThePlacementProposalAndTheAnchor`: parent bounds `(25, 25, 150, 150)`, three proposal-echoing leaves, probe K's placements; expected rects `(25, 25, 70, 40)`, `(110, 115, 30, 20)` and `(95, 105, 30, 20)` | all zero | anchor factors transposed h↔v; `place` ignores `proposal` |
| `anUnplacedSubviewIsCentredInItsParentAtTheParentsProposal`: probe I2's numbers, bounds `(120, 70, 100, 100)`, proposal 100×100, a fixed 30×30 child, expected `(155, 105, 30, 30)`; a proposal-echoing second child is expected at `(120, 70, 100, 100)` | zero rect | unplaced children left at the zero rect; unplaced children placed at the bounds origin |
| `aSubviewPlacedTwiceKeepsItsLastPlacement`: probe J, expected `(100, 100, 40, 40)` in bounds `(50, 50, 100, 100)` | zero | `place` returns early when the child's flag is already set |
| `aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules`: priority 2.5 reads 2.5; priority 2 under a `frame` reads 0 (probe L); a spacer under two `layoutPriority` nodes is a spacer; a spacer under `frame` is not; a plain leaf reads 0 and false | the skeleton answers 0 and false | `priority` looks through one wrapper; `isSpacer` recurses through `frame` too |
| `aPlacementSubviewUsedOutsideItsPlaceSubviewsCallTraps` (exit test): sibling A stashes its `PlacementSubviews` in a file-scope `@unchecked Sendable` box, and sibling B's `placeSubviews` calls `place` on it. stderr contains `"used outside its placeSubviews call"`. | exits 0 | delete the token precondition |
| `aPlacementSubviewUsedDuringMeasurementTraps` (exit test): a parent stashes its `PlacementSubviews`; its child's `sizeThatFits` runs during placement, because the child is placed at a proposal not yet measured, and calls `place`. stderr contains `"used during measurement"`. | exits 0 | delete the `measureDepth` precondition. The token check alone passes here, because the parent's `placeSubviews` is still active. |
| `aSubviewUsedAfterItsLayoutRunTraps` (exit test): a layout stashes `MeasurementSubviews`; after `computeNativeLayout` returns, the test calls `sizeThatFits` on it. stderr contains `"outlived its layout run"`. | exits 0 | delete the `isActive` precondition |

**The reference tree.**
- **Root:** a vertical stack, spacing 7, `.trailing`, placed at bounds
  `(13, 17, 157, 91)`.
- **Child A:** a horizontal stack, spacing 3, `.bottom`, that overflows with no
  spacer. It holds flexible leaves of ideal 80 (priority 1), 60 (priority 0)
  and 50 (priority −1), plus a fixed 20×13 leaf.
- **Child B:** a horizontal stack, spacing 5, holding in order:
  - a 30×10 leaf;
  - `Spacer(minLength: 10)`;
  - a 20×17 leaf;
  - a spacer under `layoutPriority(2)`;
  - an 11×9 leaf.

The test compares the two trees. Every node's stored rect and `measuredWidth`
must be equal, and so must the root `LayoutMeasurement`. It also asserts three
literal rects, derived by hand **before** the run with the arithmetic in the doc
comment: A's priority-0 leaf, B's second spacer, and B's last leaf.

It then `try #require`s that the two controls' rects **differ** from the
built-in's (shape 15). Adjust the geometry until no edge falls on x.5, and
record the adjustment.

`Tests/MetalUITests/ProposalLayoutIntegrationTests.swift` (new):

| test | red before | mutation |
|---|---|---|
| `aProposalLayoutContainerRendersThroughTheFramePipeline`: a test `DiagonalLayout` places each child at the previous child's bottom-trailing corner, inside `.padding(Edges(top: 11, right: 0, bottom: 0, left: 7))` for a non-zero origin, in a 140×90 `Frame`. Probe leaves record prepaint bounds by name, and the expected literals are hand-derived. It also asserts that `Diagonal() { … }`, `Diagonal { … }` and `ProposalLayoutContainer(Diagonal()) { … }` produce the same bounds. | the skeleton places nothing, so every bound is zero | `ProposalLayoutContainer.requestLayout` registers `requestNativeOverlay` instead of `requestNativeLayout` |

`Tests/MetalUITests/ProposalLayoutCompileGuards.swift` (new).
- **Each fixture is compiled against a plain `import MetalUI`** by
  `typecheck(_:importing:)`. `MetalUI` re-exports `MetalUILayout`
  (`App.swift:9`).
- The test file's own import is irrelevant; the fixture's is what counts
  (shape 16).
- Use sites go inside `@MainActor func probe()`.
- The diagnostics below were printed from the evidence-6 skeleton. Re-print
  them from the real implementation before trusting any substring.

| guard | kind | must hold | measured diagnostic |
|---|---|---|---|
| `anExternalModuleCanBuildACustomLeafAndContainerFromPublicAPI` | positive | The fixture declares a `ProposalLayout` that reads `priority`, `isSpacer`, `sizeThatFits`, `place(at:anchor:proposal:)` and both factors. It also declares a leaf `Element & ProposalElementGroup` over `requestNativeLeaf`, and a generic container `Element` that calls `requestGroupLayout` then `requestNativeLayout`. It uses all three: in `HStack { MyLayout() { Leaf(); Spacer() }; Container { Leaf() } }`, as `MyLayout { Leaf() }.padding(…)` in a `VStack`, and as `ProposalLayoutContainer(MyLayout()) { Leaf() }`. Must succeed. | exit 0 |
| `aMeasurementSubviewCannotBePlaced` | negative | `subviews[0].place(at: Point(x: 0, y: 0), proposal: .unspecified)` inside `sizeThatFits` fails | `value of type 'MeasurementSubview' has no member 'place'` |
| `subviewProxiesCannotBeConstructedOutsideTheKernel` | negative | `_ = MeasurementSubviews()` fails, and, as a second fixture, `_ = PlacementSubview()` fails | `'MeasurementSubviews' initializer is inaccessible due to 'internal' protection level` (likewise `'PlacementSubview'`) |
| `aCustomLayoutContainerRejectsLegacyContent` | negative | `_ = MyLayout() { Text("legacy") }` fails, and so does `_ = ProposalLayoutContainer(MyLayout()) { Text("legacy") }` | `instance method 'callAsFunction' requires that 'Text' conform to 'ProposalElementGroup'`; `generic struct 'ProposalLayoutContainer' requires that 'Text' conform to 'ProposalElementGroup'` |

**Prove each new guard runs.** A guard skips silently when the modules directory
is missing (CLAUDE.md, "When CI lands").
1. Build once with `swift build --build-system native`.
2. Run the four guards.
3. In a worktree, mutate each one red once:
   - make `MeasurementSubview` gain a `place` method;
   - give `MeasurementSubviews` a `public init()`;
   - drop the `Content: ProposalElementGroup` constraint from `callAsFunction`;
   - rename `requestNativeLayout`.
4. Record that each went red.

Guard count: **39 → 43**. Test count: **+14** (9 kernel, 1 integration, 4
guards).

### Docs owed by lane 1

- **`specs/2026-09-12-native-layout-kernel-design.md`:** a dated *Superseded*
  note under "Kernel protocol and tree representation" pointing here. Remove
  "The layout protocol" from its Not shipped list.
- **`2026-09-12-swiftui-layout-replacement-inventory.md`:** the migration-story
  table goes under "Completion criteria for task 1". Strike "Custom containers
  cannot", with a date.
- **`plans/2026-09-12-swiftui-alignment.md`, task 2:** move "A layout protocol"
  and the migration story to Done, with the commit.
- **Record §09:** a dated "Kernel completion — lane 1" subsection with counts
  and the mutation table. Correct "Users can add leaves, not algorithms."
- **Decisions doc:** fill in `SA-A`…`SA-F`'s "Mutations" lines.
- **`CLAUDE.md`:**
  - one Architecture bullet: `ProposalLayout`, measurement proxies that cannot
    place, built-ins stay enum cases, and sufficiency pinned by the reference
    stack;
  - the guard count.

---

## Lane 2 — boundaries

### Rulings

- `SA-G`: mixing is rejected in every direction, with no adapter.
- `SA-H`: the invalidation contract.
- `SA-I`: one `isLayingOut` flag for both engines.

### Public API

No new public symbol. Existing public entry points gain preconditions:

```swift
public func newNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID
//  no child is a native node
//  "legacy layout node given a native child — a proposal subtree cannot sit under a CSS container (SA-G)"
public func setStyle(_ id: LayoutNodeID, _ s: Style)
//  existing: !isLayingOut (now also true during native layout, SA-I)
//  new: id is not a native node
//  "setStyle on a native layout node — the proposal engine never reads Style (SA-G)"
public func computeLayout(_ tree: LayoutTree, root: LayoutNodeID, available: AvailableSpaceSize, rootFontSize: Double)
//  !tree.isNativeLayoutNode(root)
//  "computeLayout called on a native root — use computeNativeLayout (SA-G)"
public func setLayout(_ id: LayoutNodeID, _ r: LayoutRect)
//  no native measurement is running on this tree
//  "setLayout called during native measurement — measurement never writes a rect (SA-H)"
// every newNative* registrar, including newNativeLayout:
//  !isLayingOut
//  "native layout node registered while layout is running (SA-I)"
```

Internal additions:

- **`private func appendNode(style:children:)`.** This is the storage append
  without the new check. Every native registrar calls it, so native nodes keep
  appending their `Style.default` row, `nil` measure, rect and measured width.
  Public `newNode` becomes the check plus `appendNode`, and `newLeaf` is
  unaffected, since it has no children.
- **`LayoutTree` holds a weak or optional reference to the active run**, or an
  `activeMeasureDepth` mirror, so `setLayout` can read it. It holds no cache:
  the reference is `nil` outside a call.
- **`func measureNativeLayout(root:proposal:) -> LayoutMeasurement`** (internal).
  It measures only and writes no rect, because the contract's "measurement
  never writes a rect" needs an entry point that does nothing else.
- **`computeNativeLayout` and `measureNativeLayout` bracket their bodies** with
  `beginLayout()` / `defer { endLayout() }`. `setStyle`'s existing precondition
  then fires on the native path unchanged. A re-entrant call of either engine,
  from inside either engine, hits `beginLayout`'s existing
  "computeLayout re-entered on the same tree".

### The invalidation contract (`SA-H`), stated once

1. **Scope.** A measurement cache lives for exactly one `computeNativeLayout` or
   `measureNativeLayout` call.
   - Nothing survives the call: not across frames, not across two calls on one
     tree, not across `reset(generation:)`.
   - Invalidation is therefore by construction. `Frame` builds a fresh tree per
     frame, each call builds a fresh run, and there are no dirty flags.
   - **This deliberately diverges from SwiftUI**, whose memo survives passes.
     Probe F: a forced same-size relayout re-ran nothing. Probe G: a resize
     re-ran no child whose proposal was unchanged.
2. **Within a call**, each `(node, proposal)` pair's measurement body runs at
   most once. That covers a leaf closure, a built-in case body and a custom
   `sizeThatFits`. A second ask, from measurement or from placement, is a cache
   hit. Probe A/B/C agrees.
3. **Proposal equality** is `ProposedSize`'s synthesized `Hashable`.
   - A NaN axis never equals itself. Lane 3 traps on a NaN proposal before the
     lookup, so the key needs no `bitPattern` treatment.
   - `-0` and `0` share an entry. That is accepted, because no built-in answers
     differently for them.
4. **Direction.** Measurement never writes a rect: `setLayout` traps while
   `measureDepth > 0`. Placement reads measurements only through the cache. It
   adds entries only for proposals not yet measured, and never replaces one.
5. **A different proposal is a different key** and is measured afresh. That
   holds within a call and, trivially, across calls.
6. **A layout's answer must be a function of its value, its proposal and its
   subviews' answers.** The kernel memoizes on `(node, proposal)` and does not
   detect an impure layout. SwiftUI's memo makes the same assumption.
7. **Mutation during a call traps.** That covers `setStyle`, any native
   registration, a re-entrant layout call of either engine, and `setLayout`
   from inside measurement.

### Tests

**On red-first for clauses that already hold.** Several clauses of `SA-H` are
satisfied by the kernel today, so a test for them cannot be red before the
change. For those tests, the named mutation **is** the red run. Run it and
record it before the test is committed; a green run with no recorded red run is
not accepted. They are marked "green on arrival" below. Every other test in
this lane is genuinely red before its change.

`Tests/MetalUILayoutTests/NativeBoundaryTrapTests.swift` (new). It uses a plain
`import MetalUICore` and `import MetalUILayout`, because everything these tests
touch is public.
- Exit tests are non-capturing, so each arm is its own test
  (`ElementGroupTrapTests.swift:207-210`).
- A layout-time arm reaches its tree through a file-scope value, as
  `LayoutContextTests`' re-entrancy test does.
- Each test asserts its message fragment on stderr as well as `.failure`,
  because a trap elsewhere must not pass.

| test | red before | mutation after |
|---|---|---|
| `aNativeNodeRegisteredUnderALegacyNodeTraps`: `newNode(style: Style(), children: [nativeLeaf])`; fragment `"given a native child"` | exits 0 | delete the precondition |
| `aLegacyNodeRegisteredUnderANativeStackTraps`: fragment `"contains a legacy node"` | **green on arrival** (pins `:379-385`, unpinned since `b8ba46d`) | delete the child loop from `newNativeLinearStack`. The test registers without laying out, so it exits 0. |
| `aLegacyNodeRegisteredUnderACustomLayoutTraps`: same fragment | green once lane 1 lands | delete the child loop from `newNativeLayout` |
| `everyNativeRegistrarAcceptsNativeChildrenWithoutTrapping`: exit `.success`; all twelve registrars over native children, with `precondition`s on the node count and on each `style(id) == .default` | green on arrival | route native registrars through the checking `newNode`, which then traps |
| `computeLayoutRejectsANativeRoot`: fragment `"called on a native root"` | exits 0, because flex runs on a default style | delete the precondition |
| `aStyleWrittenOntoANativeNodeTraps`: `setStyle(nativeLeaf, Style())` outside any layout; fragment `"setStyle on a native layout node"` | exits 0 | delete the precondition |
| `computeNativeLayoutReenteredFromAMeasureClosureTraps`: a leaf closure calls `computeNativeLayout` on the same file-scope tree; fragment `"re-entered on the same tree"` | the stack is exhausted. The process fails, but stderr lacks the fragment, so the test is red on its second assertion. | drop `beginLayout()` from `computeNativeLayout` |
| `computeLayoutCalledFromANativeMeasureClosureTraps`: a native leaf closure calls legacy `computeLayout` on a separate legacy root in the same tree; fragment `"re-entered on the same tree"` | exits 0 | give the native path its own flag |
| `setStyleOnALegacyNodeDuringNativeLayoutTraps`: a native closure writes the style of a legacy node in the same tree; fragment `"setStyle called while"` | exits 0 | drop `beginLayout()` |
| `registeringANativeNodeDuringNativeLayoutTraps`: the closure calls `newNativeLeaf`; fragment `"registered while layout is running"` | exits 0 | delete the registrar precondition |
| `writingARectDuringNativeMeasurementTraps`: the closure calls `setLayout`; fragment `"during native measurement"` | exits 0 | move `measureDepth += 1` after the leaf closure call |

`Tests/MetalUILayoutTests/NativeInvalidationContractTests.swift` (new,
`@testable`, since it reads `isLayingOut` and `measureNativeLayout`):

| test | red before | mutation after |
|---|---|---|
| `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns`: exit `.success`; `precondition(tree.isLayingOut)` inside a closure, `!isLayingOut` after return, and `setStyle` on a legacy node succeeds after | the inside flag is false, so it exits non-zero | drop the `defer { endLayout() }` |
| `measuringANativeTreeWritesNoRect`: `measureNativeLayout` over lane 1's reference tree leaves every stored rect at `LayoutRect(x: 0, y: 0, width: 0, height: 0)`, and its measurement equals `computeNativeLayout`'s on a twin tree | red by assertion against a skeleton `measureNativeLayout` that delegates to `computeNativeLayout` | add a `setLayout` to `measureNative`'s leaf branch. That also reddens `writingARectDuringNativeMeasurementTraps`'s precondition path, so name both. |
| `aSecondComputeNativeLayoutCallReMeasuresEveryLeaf`: same tree, same proposal, twice; each leaf's closure count doubles. This pins `SA-H` item 1's divergence from probe F. | green on arrival | hoist the cache to a stored property on `LayoutTree` |
| `aDifferentRootProposalReMeasuresAndMovesTheRects`: 120×80, then 90×80, on a horizontal stack under compression; the closures see 90's allocations, and the stored rects change | green on arrival | memoize `computeNativeLayout`'s result on the root id alone |
| `aResetTreeMeasuresItsNewRegistrationsFromScratch`: compute, `reset(generation: 1)`, register leaves at the same indices that answer differently, compute again; the new answers and new calls show up | green on arrival | a persistent cache keyed on `(id.index, proposal)` that `reset` does not clear |

`SA-H` item 2 is pinned by lane 1's
`aSubviewMeasuresOncePerDistinctProposalWithinOneRun`, and lane 3's count test
pins it on a branching tree. Do not add a third.

`Tests/MetalUITests/NativeBoundaryIntegrationTests.swift` (new):

| test | red before | mutation after |
|---|---|---|
| `aProposalElementInsideALegacyContainerTrapsAtRegistration`: exit test, `await MainActor.run { var root = Column { Rectangle() }; Frame(…).render(&root) }`; fragment `"given a native child"` | exits 0. Evidence 4 measured today's behaviour: the closure runs 0 times, and the leaf's bounds are (70, 0, 0×0). | delete the `newNode` precondition |
| `aLegacyStyleModifierOnAProposalComponentTrapsAtLayout`: exit test. A `Component, ProposalElementGroup` whose content is `Rectangle()`, rendered as `Toggle().width(Pixels(70))`, a spelling that compiles; fragment `"setStyle on a native layout node"` | exits 0, with the width silently inert | delete the `setStyle` precondition |
| `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer`: exit test. An `Element, ProposalElementGroup` whose `requestLayout` calls `pass.requestNode`, placed in an `HStack`; fragment `"contains a legacy node"` | **green on arrival** | delete the child loop from `newNativeLinearStack` |

### Files

- **`Sources/MetalUILayout/LayoutTree.swift`:** `appendNode`, the `newNode` and
  `setStyle` checks, registrar preconditions, `setLayout`'s check,
  `beginLayout`/`endLayout` in the native entry points, and
  `measureNativeLayout`.
- **`Sources/MetalUILayout/FlexEngine.swift`:** the `computeLayout`
  precondition.
- **`LayoutTree.isLayingOut`'s doc comment** (`:64-74`): it now covers both
  engines.
- **The three test files above.**

Test count: **+19** (16 kernel, 3 integration).

### Docs owed by lane 2

- **Record §09 "Hazards":** item 1 closed, with test names. Item 2's trap is now
  pinned. Correct §1's "No re-entrancy guard" bullet.
- **`specs/2026-09-12-native-layout-kernel-design.md`:** a dated follow-up to
  the superseded note "Mixed trees are rejected in one direction only".
- **Inventory, "One authority per rendered subtree":** rewrite the bullets.
  There is still no adapter (`SA-G`).
- **`CLAUDE.md`, Architecture:** "One layout authority per root. A native node
  under a legacy node, a legacy node under a native one, and a `Style` written
  onto a native node all trap. The native cache lives for one call (`SA-H`), and
  measurement never writes a rect."
- **Plan task 2:** move items (b) and (c) to Done, and state that "(c) an
  adapter" is ruled out, not built (`SA-G`).
- **Decisions doc:** mutation lines for `SA-G`…`SA-I`.

---

## Lane 3 — robustness

### Rulings

- `SA-J`: the validation policy.
- `SA-K`: the relaxations and repairs that policy forces.
- `SA-L`: the depth guard.
- `SA-M`: the work counters.

### Validation (`SA-J`, `SA-K`)

**The rule.** Reject an input only if **SwiftUI rejects it** or it would make
**MetalUI's answer non-finite**.
- **SwiftUI rejects** an input by logging "Invalid frame dimension" or
  "Contradictory frame constraints", by trapping, by hanging, or by having no
  spelling for it.
- **A rejection is a `precondition`** whose message names the parameter.
  MetalUI has no runtime-warning channel (`FontResolver.resolve`'s precedent).

The corollary for values: **a measurement may be infinite; a stored rect may
not; nothing may be NaN.**

**Where the checks live.** Parameters are checked once, at registration. Values
the kernel computes are checked at **three checkpoints** that every node kind,
built-in or custom, passes through:

1. **`measureNative` entry:** a proposal with a NaN axis traps, naming the node.
   This covers the root proposal, proxy proposals and internal arithmetic
   (for example, ∞ − ∞ in a stack).
2. **`measureNative` exit:** a measurement with a NaN size or baseline traps,
   naming the node. It covers leaf closures, custom `sizeThatFits` and built-in
   arithmetic.
3. **`placeNative` entry:** a rect with any non-finite field traps, naming the
   node, before `setLayout`. It covers root bounds, proxy positions and
   ∞-answering children.

| input | rejected | accepted, with the answer the lane must produce | probe |
|---|---|---|---|
| stack `spacing` | NaN, +∞, −∞ | negative: `{20; 20}` at −10 answers 30; at −100 it answers −60, unclamped, at `nil` and at a 50 proposal | P1, P9 |
| padding insets | NaN, +∞, −∞ | negative, with the **response clamped at 0 per axis** (`SA-K`): −5 on 20 answers 10; −15 on 20 answers 0, where the kernel answers −10 today; leading −30 / trailing 5 on 20 answers 0×20; −5 on a proposal-filling child offered 100 answers 100 | P2, P2b, P2c, P9 |
| frame fixed `width`/`height` | negative (so also −∞), NaN, +∞ | zero | P3, P9 |
| frame `min…` | NaN, +∞ | negative, including −∞: −10 and −∞ both answer the child's 20 | P4, P4b, P9 |
| frame `max…` | negative (so also −∞), NaN | +∞: 100 at a 100 proposal, the child's 20 at `nil` | P4, P4c, P9 |
| frame `ideal…` | negative, NaN, +∞ | — | P4b, P4d |
| frame ordering | min > max, min > ideal, ideal > max | equal values | P4, P4c |
| a fixed and a flexible dimension on one axis | both given | — | no SwiftUI overload spells it |
| `Spacer` `minLength` | NaN, +∞, −∞ | negative: −30 between two 20s answers 10 | P5, P9 |
| `layoutPriority` | NaN (SwiftUI hangs) | **±∞, a trap today (`SA-K`)**: +∞ orders like 1 (80/20), −∞ like −1 (20/80) | P7, P7b |
| `aspectRatio` ratio | 0 (∞ on a one-axis proposal), NaN, +∞, −∞ | **negative, a trap today (`SA-K`)**: −2 `.fit` at 100×80 gives 100×−50; `.fill` at 100×80 gives −160×80; `.fit` at `nil`×80 gives −160×80; `.fit` at 100×`nil` gives 100×−50 | P8, P8b, P9 |
| root and every internal proposal | a NaN axis (checkpoint 1) | negative, zero, ∞ (`Color` offered ∞ answers ∞) | P6 |
| a measurement | a NaN size or baseline (checkpoint 2) | ±∞ | P6, N |
| a stored rect | any non-finite field (checkpoint 3) | negative width or height | M, P2c |

**Four of these rows call for a decision beyond the rule's first clause, recorded
in `SA-J`:**
- **`ideal` +∞.** SwiftUI does not diagnose it, but it answers ∞ at an
  unspecified proposal. That is the proposal every stack child and every scroll
  viewport's content receives on its main axis. So it is rejected at
  registration, where the message can name the parameter, rather than at a rect
  three nodes away.
- **Padding NaN.** SwiftUI answers 0×0 and then traps placing the child (P2c).
- **Padding −∞.** SwiftUI answers 0×0 and places the child at −∞ (P2c), so it
  fails the rect rule.
- **Ratio 0** is finite on a 2-D proposal and infinite on a one-axis proposal
  (P8).

**`SA-K`: what the policy changes in source.**
- **`newNativeLayoutPriority`:** `priority.isFinite` becomes `!priority.isNaN`.
- **`newNativeAspectRatio`:** `ratio.isFinite && ratio > 0` becomes
  `ratio.isFinite && ratio != 0`. `aspectRatioSize`'s two-axis comparison
  becomes `width / ratio <= height` for `.fit` and `>=` for `.fill`. For a
  positive ratio and a positive height this is the same predicate as today's
  `width / height <= ratio`. For a negative ratio it is P8/P8b's.
- **Padding's measured size** becomes `max(0, child + leading + trailing)` per
  axis. For positive insets over a non-negative child this is unchanged.
- **The MetalUI modifier preconditions** (`NativeModifiedContent.swift:271-272`,
  `:279`) change to the kernel's rule, so the two layers cannot disagree.
- **`ProposedSize.swift`'s doc** loses "a finite proposal must be non-negative",
  which P6 refutes. The rule is "never NaN".

**One existing test changes, and why.**
`aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes`
(`NativeLayoutTests.swift:168`) declares `minWidth: 40, idealWidth: 90,
maxWidth: 80`, and ideal > max is rejected. Re-fixture it with `idealWidth: 70`.
- Re-derive its expectations by hand before running: proposal (70, 60),
  measurement 70×20, child rect unchanged at `(10, 14, 30, 10)`.
- The re-fixture loses the "ideal clamped by max" case. That clamp is
  unreachable once the ordering is validated, so it is not a lost pin.

### Depth guard (`SA-L`)

- **`NativeLayoutRun.maxDepth` is its own constant**, not an alias of
  `LayoutContext.maxDepth`. Its value is **64**, for parity: a tree the legacy
  engine accepts must not be rejected by its proposal port for depth alone.
- **Its doc table records the debug ceilings on a 1 MB thread:**
  padding/frame 193 (≈5.3 KB/level) and linearStack 171 (≈6.0 KB/level),
  against legacy's 107 (≈9.8 KB). Release is unmeasured.
- **One counter covers both recursions.** `run.depth` is entered at the top of
  `measureNative`, before checkpoint 1 and the cache lookup, and at the top of
  `placeNative`. It is left on return.
  - Placement calls measurement from inside itself, so the counter tracks real
    stack depth across both.
  - Message: `"native layout recursion exceeded \(maxDepth) levels at node \(id)"`.
  - **Tests assert the fragment `"native layout recursion exceeded"`**, because
    legacy's `"layout recursion exceeded"` is a substring of it.
- **The lane bisects the custom kind before committing the number.** The chain
  is one-child `ProposalLayout` nodes whose `placeSubviews` places through the
  proxy. Use evidence 5's procedure. **Keep 64 if 64 ≤ 0.60 × the smallest
  ceiling across padding, frame, stack and custom.** Otherwise take the largest
  multiple of 8 under that bound and say so in the doc table. Raising 64 is out
  of scope.

### Work counters (`SA-M`)

```swift
struct NativeLayoutWork: Equatable {   // internal: a test observable
    var measureCalls = 0   // leaf-closure and custom sizeThatFits invocations: user code
    var cacheHits = 0      // lookups that found the key
    var cacheMisses = 0    // measurement bodies run, every node kind
}
// LayoutTree: internal private(set) var lastNativeLayoutWork: NativeLayoutWork
// assigned from the call's run when computeNativeLayout or measureNativeLayout returns
```

- **`cacheMisses ≥ measureCalls` always.** The difference is built-in bodies,
  which run no user code.
- **The work record lives on the tree; the cache never does.** It holds counts
  and no `LayoutNodeID`, so it is outside ruling C-3's hazard. It is readable
  after a real `Frame.render` through `@testable import MetalUILayout`, and
  `LayoutContext`'s counters are not.

### Tests

`Tests/MetalUILayoutTests/NativeValidationTrapTests.swift` (new, plain import).
**One exit test per rejected arm** (non-capturing bodies), each asserting a
fragment of its parameter's message.
- **Red before:** every test is red before its change, because it exits 0. The
  exceptions are the three marked below, where the kernel already traps.
- **Mutation:** "delete that precondition", unless a different one is named.

| group | tests |
|---|---|
| spacing (`isFinite`) | `aNaNStackSpacingTraps`, `anInfiniteStackSpacingTraps`, `aNegativeInfiniteStackSpacingTraps`. Mutation `!= .infinity` must redden the NaN and −∞ arms. |
| padding (`isFinite`) | `aNaNPaddingInsetTraps`, `anInfinitePaddingInsetTraps`, `aNegativeInfinitePaddingInsetTraps` |
| fixed dimension (`>= 0 && isFinite`) | `aNegativeFixedFrameDimensionTraps`, `aNaNFixedFrameDimensionTraps`, `anInfiniteFixedFrameDimensionTraps`. No −∞ arm: both halves reject it, so it cannot tell a mutation of either half. |
| minimum (`!isNaN && != +∞`) | `aNaNFrameMinimumTraps`, `anInfiniteFrameMinimumTraps` |
| maximum (`!isNaN && >= 0`) | `aNegativeFrameMaximumTraps`, `aNaNFrameMaximumTraps` |
| ideal (`>= 0 && isFinite`) | `aNegativeFrameIdealTraps`, `aNaNFrameIdealTraps`, `anInfiniteFrameIdealTraps` |
| ordering and combination | `aFrameMinimumAboveItsMaximumTraps`, `aFrameMinimumAboveItsIdealTraps`, `aFrameIdealAboveItsMaximumTraps`, `aFixedFrameDimensionCombinedWithAFlexibleOneTraps` |
| spacer (`isFinite`) | `aNaNSpacerMinimumTraps`, `anInfiniteSpacerMinimumTraps`, `aNegativeInfiniteSpacerMinimumTraps` |
| priority | `aNaNLayoutPriorityTraps` (**green on arrival**: today's `isFinite` rejects it too; the mutation is "delete the precondition") |
| ratio (`isFinite && != 0`) | `aZeroAspectRatioTraps`, `aNaNAspectRatioTraps`, `anInfiniteAspectRatioTraps` (all three **green on arrival**, since today's rule is `> 0`; the mutation `ratio != 0` alone reddens NaN and ∞), `aNegativeInfiniteAspectRatioTraps` (green on arrival; the mutation `!ratio.isNaN && ratio != .infinity` reddens it) |
| checkpoints | `aNaNRootProposalTraps` (1), `aNaNSubviewProposalTraps` (1, from a custom layout's proxy), `aNaNMeasurementTraps` (2, from a leaf), `aNaNCustomMeasurementTraps` (2, from a custom `sizeThatFits`), `aNonFiniteRootBoundsTraps` (3), `anInfiniteStoredRectTraps` (3: a custom layout places a leaf that answers ∞ at an ∞ proposal), `aNonFinitePlacementPositionTraps` (3: `place(at: Point(x: .infinity, y: 0), …)`) |

`Tests/MetalUILayoutTests/NativeValidationAcceptanceTests.swift` (new).
- **Every test here is an exit `.success` test**, with `precondition`s on the
  values.
- **The reason: the mutation that must redden each one is a rejection.** An
  in-process trap would truncate the suite instead of reddening one test
  (shapes 11 and 13).

| test | red before | mutation after |
|---|---|---|
| `negativeStackSpacingAnswersSwiftUIsUnclampedSum`: 30; −60 at `nil` and at 50 | green on arrival | reject negative spacing; clamp gaps at 0 |
| `negativePaddingIsAcceptedAndItsResponseClampsPerAxis`: 10, 0, 0×20 and 100. Also the child's stored origin is the padding's origin plus the leading and top insets (P2b: −15 and −30). The child's stored **width** is asserted at today's bounds-minus-insets value (30 for −15 on 20, where SwiftUI's is 20) and **pinned wrong on purpose**, citing `SA-N` item 4, so task 5's fix reddens it deliberately. | the 0 arm reads −10 | remove the clamp; clamp both axes together |
| `negativeAndNegativeInfiniteFrameMinimumsAndAnInfiniteMaximumAreAccepted`: 20, 20; 100 and 20 | green on arrival | reject a negative minimum |
| `aNegativeSpacerMinimumIsAccepted`: 10 | green on arrival | clamp `minLength` at 0 |
| `infiniteLayoutPrioritiesAreAcceptedAndOrderLikeFinitePriorities`: +∞ gives 80/20, −∞ gives 20/80 | traps | map ±∞ to 0 |
| `aNegativeAspectRatioIsAcceptedOnEveryProposedBranch`: the four P8/P8b answers | traps | keep `width / height <= ratio`. The `.fit` 100×80 arm then reads −160×80. |
| `anInfiniteMeasurementIsAcceptedUntilItBecomesARect`: a custom layout asks a leaf at `.infinity`, gets ∞, then places it at a finite proposal | green on arrival | move checkpoint 3's non-finite test to checkpoint 2 |
| `aNegativeProposalIsAccepted`: a proposal-echoing leaf offered −10×−20 answers −10×−20, as `Color` does in P6 | green on arrival | reject negative proposal axes at checkpoint 1 |
| `theProposalModifiersAcceptWhatTheKernelAccepts` (in `MetalUITests`): `Rectangle().layoutPriority(.infinity)` and `.aspectRatio(-2)` render | traps at construction | leave `NativeModifiedContent.swift`'s preconditions unchanged |

`Tests/MetalUILayoutTests/NativeDepthGuardTests.swift` (new, `@testable`).
- Each trap test runs its layout on an explicit 4 MB `Thread`
  (`LayoutContextTests.swift:177-189` says why) and asserts the fragment.
- 65 levels fit in 4 MB several times over (evidence 5).

| test | red before | mutation after |
|---|---|---|
| `layingOutANativeTreeDeeperThanTheLimitTraps`: a leaf plus `maxDepth` padding nodes, `computeNativeLayout` | exits 0 | delete `enter` from both `measureNative` and `placeNative` |
| `measuringANativeTreeDeeperThanTheLimitTraps`: the same chain through `measureNativeLayout` | exits 0 | delete `enter` from `measureNative` only. The test above stays green under this mutation, because placement still traps. |
| `aPlacementOnlyChainOfCustomLayoutsDeeperThanTheLimitTraps`: a leaf plus `maxDepth` custom layouts. Each `sizeThatFits` returns a constant without measuring, and each `placeSubviews` places its child at a fixed proposal, so only placement recurses. | exits 0 | delete `enter` from `placeNative` only. The two tests above stay green under this mutation, because measurement still traps in each. |
| `aNativeTreeAtTheDepthLimitDoesNotTrap`: exit `.success`, same thread, a leaf plus `maxDepth − 1` padding nodes | green on arrival | `depth < maxDepth` in the guard |

`Tests/MetalUILayoutTests/NativeLayoutWorkTests.swift` (new, `@testable`):

| test | red before | mutation after |
|---|---|---|
| `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` (tree below) | red by assertion against a zero-filled `NativeLayoutWork` for (2) and (3). (1) is green on arrival because the cache exists, and its doc comment says so. | **"disable the cache"** (delete the hit branch) must redden (1), (2) and (3). "Key on node only" must redden (4). "Count a hit before checking the key" must redden (3). |
| `nativeLayoutWorkIsPerCall`: two calls on one tree at the same proposal; the second call's counters equal the first's, not double them | green on arrival once (1)–(3) exist; the red run is the mutation | accumulate into `lastNativeLayoutWork` instead of assigning it |

**The branching tree.**
- **Root:** a vertical stack of three branches, offered (100, 200) at bounds
  (7, 11, 100, 200).
- **Branch (i):** a horizontal stack that **overflows**. It holds four capped
  leaves (width `min(ideal, proposal.width ?? ideal)`) with ideals
  40/30/30/20 under priorities 1/0/0/−1, so allocation proposals differ from
  natural ones.
- **Branch (ii):** an overlay of three leaves, one under `aspectRatio(2)`, which
  measures its child twice.
- **Branch (iii):** a lane 1 `ReferenceLinearStack` over three leaves, one under
  `frame(idealWidth: 25)`.

Every leaf closure records its proposals into a per-leaf `Set`. The test
asserts:
1. for each leaf, closure calls == distinct proposals seen;
2. `lastNativeLayoutWork.measureCalls` == the sum of those counts, plus the
   custom node's own distinct proposals, recorded by its `sizeThatFits`;
3. `cacheHits` and `cacheMisses` equal **literals derived by hand before the
   run**, from the kernel's proposal sequence, which is written out in the doc
   comment. Never read them off a green run (shape 12);
4. one compressed leaf's stored rect equals its hand-derived allocation.

Counts that a later assertion indexes on are `try #require` (shape 13). The tree
branches three ways at the root and again inside each branch, never a chain
(practices).

### Files

- **`Sources/MetalUILayout/LayoutTree.swift`:** registrar preconditions, the
  three checkpoints, the padding clamp, the ratio comparison, the priority
  relaxation, `enter`/`leave`, `lastNativeLayoutWork`, and doc comments on every
  changed registrar.
- **`Sources/MetalUILayout/NativeLayoutRun.swift`:** `depth`, `maxDepth` with
  its table, `work`.
- **`Sources/MetalUILayout/ProposedSize.swift`:** the doc correction.
- **`Sources/MetalUI/NativeModifiedContent.swift`:** the two modifier
  preconditions.
- **`Tests/MetalUILayoutTests/NativeLayoutTests.swift`:** the one re-fixtured
  test.
- **The five new test files above.**

Test count: **+50** (35 traps, 9 acceptance, 4 depth, 2 work), one existing test
re-fixtured.

### Docs owed by lane 3

- **Record §09, §1:** close "No validation", "No depth guard", and "The
  practices rule … cannot yet be applied to this engine", each with a date and a
  test name. Add `SA-N`'s carried findings to "Unprobed, and material". Three of
  them are now probed, and they disagree with the kernel.
- **`specs/2026-09-12-native-layout-kernel-design.md`:** supersede "A finite
  proposal must be non-negative. An answer is always finite and non-negative"
  with `SA-J`'s corollary.
- **`CLAUDE.md`:**
  - Architecture: the validation rule's one-liner and the native depth guard.
  - Performance: "native path: count work with `lastNativeLayoutWork`".
  - "Declared but inert": add `LayoutTree.lastNativeLayoutWork` to the
    test-observables row.
  - Re-take the test and guard counts.
- **Plan task 2:** move item (d) to Done. If all three lanes and their mutation
  records are in, tick task 2, and state from `SA-N` what stays open for tasks
  4, 5, 6 and 7.
- **Decisions doc:** mutation lines for `SA-J`…`SA-M`, and the custom kind's
  bisection in `SA-L`.

---

## Verification common to every lane

- **Run `swift test --no-parallel` and read the summary line.**
  - The total must equal the previous total plus the lane's added tests exactly:
    993 → 1007 → 1026 → 1076 if the counts above hold.
  - A shortfall is a truncated run (shape 11).
  - `grep -c "error:"` and `grep -c "warning:"` must both read 0.
- **Goldens.** `git diff --stat -- '*.json'` must be empty, and
  `find Tests -name "*.json" | wc -l` must read 97.
  - `Sources/MetalUILayout/` changes in every lane, so a moved golden means the
    **CSS** engine moved. Stop and find out why.
  - `computeLayout`'s native-root precondition and `newNode`'s native-child
    precondition are the only legacy-reachable edits. Evidence 4 shows no
    existing test reaches them.
- **Guards.** Count them per file with `grep -c canTypecheck` under
  `--build-system native`, and prove each new guard executes by mutating it red
  once.
- **Mutations.** Run them in a separate `git worktree`, one at a time, and
  confirm the restore with `git status --short` clean.
  - **Name the tests each mutation reddens** in the decisions doc and in record
    §09.
  - A mutation that reddens nothing is either a broken instrument or the
    finding. Decide which before moving on.
- **No test sleeps.** The exit tests' `while !t.isFinished { usleep(1000) }` spin
  is the existing idiom (`LayoutContextTests.swift:205`). It never completes on
  the passing path of a trap test, and it is not a sleep in any assertion's
  timeline.
- **No test reads wall-clock time.** Performance claims come from
  `lastNativeLayoutWork` only.
