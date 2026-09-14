# Native kernel completion design

**Milestone:** SwiftUI replacement task 2, the part still open at `34e2841`
(`plans/2026-09-12-swiftui-alignment.md`, task 2's "Not done" list).

**Status (2026-09-14):** design only. Written against `34e2841` on
`feat/kernel-completion`. No source has changed. Rulings are prefixed **`SA-`**
and lettered, in `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`.
A bare `SA-3` is a typo, not a citation.

**Revised the same day (third pass)** after a critic's review of `3bb1ca1`.
Each of its eighteen findings is applied or rejected, with reasoning, in the
decisions doc's `SA-S`. The revision re-ran both probes with new arms, rebuilt
the lane 1 skeleton to re-print every guard diagnostic at file scope in Swift 6
mode, and ran the suite once with lane 2's re-entrancy checks and lane 3's
frame-overload split applied temporarily. `SA-R` is new: it amends plan item
(e)'s "compile-time" criterion explicitly rather than ticking it quietly.

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
| 1. **protocol** | (a) a layout protocol; (e) the migration story for external custom elements, under `SA-R`'s amended criterion | `ProposalLayout`, two pairs of subview proxies, one new node kind, one public container element, and compile guards, at file scope in Swift 6 mode, that an outside module can use them |
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
its child; a single-child stack passing its child's priority through; the
deprecation of an argument-less `.frame()`; porting any legacy container; the
typed-modifier foundation (task 3), and with it a compile-time check of
`ProposalElementGroup` conformers (`SA-R`); animation on the proposal path;
replacing `Style` resolution.

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
   - the proxy surface (E/E2); priority under fifteen outer modifiers (L, L2)
     and inside containers (L3);
   - an unplaced subview (I/I2) and a subview placed twice, with its subtree's
     placement counted (J, J2);
   - placement proposal plus anchor, including two asymmetric anchors (K, K2),
     and the order subtrees are placed in (K's log order);
   - non-finite answers (N) and non-finite positions (M).

   The output is recorded in its header. The third pass re-ran it both ways;
   every earlier line reproduced.
2. **`docs/probes/swiftui-layout-input-validation.swift`**: what SwiftUI
   accepts, diagnoses, answers non-finitely, traps on or hangs on. It covers
   spacing, padding and where padding places its child, frame dimensions,
   spacer minimum, proposals, priority and aspect ratio, including the ratio's
   two-axis branch at zero and negative proposal axes (P8c, 24 arms, third
   pass). Every group has a positive control, and the output is recorded in its
   header.
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
6. **The lane 1 API typechecks from outside, at file scope, in Swift 6 mode.**
   - A temporary skeleton of the public API in this spec, plus lane 3's
     frame-overload split, was built with `swift build --build-system native`.
   - The second pass typechecked its fixtures through `typecheck(_:importing:)`'s
     own shape: the body wrapped in `func fixture() { … }`, no
     `-swift-version`, so Swift 5 mode. **That shape cannot hold the migration
     table's own spelling**: the third pass's positive fixture, fed through it,
     fails with `declaration is only valid at file scope` (on
     `extension Leaf: ProposalElementGroup {}`) and `attribute 'public' can only
     be used in a non-local scope`.
   - The third pass typechecked every fixture **at file scope with
     `-swift-version 6`**: public types, public extensions, a `@MainActor`
     public use site. The positive fixture exits 0. Every negative's
     diagnostic, re-printed this way, is quoted in the guard tables below.
   - **The language mode is observable.** A `ProposalLayout` storing a
     non-`Sendable` class fails in Swift 6 mode (`stored property 'box' of
     'Sendable'-conforming struct 'Leaky' has non-Sendable type 'Box'`) and
     only warns in Swift 5 mode, exit 0.
   - The skeleton was then deleted and `Sources/` restored (`git status`
     clean). `SA-P`.
7. **A plain import in one test file does not see internals granted by
   `@testable` in another file of the same test target.** This was measured on
   a two-file scratch package, for a free function and for a member of a public
   enum. `SA-P`.
8. **Lane 2's re-entrancy checks and lane 3's frame split break no existing
   test (third pass).** With these applied temporarily at once:
   - `computeNativeLayout` bracketed by `beginLayout()`/`defer { endLayout() }`;
   - `precondition(!isLayingOut)` in `newNode` (so also `newLeaf` and every
     native registrar, which route through it today) and in
     `reset(generation:)`;
   - the frame split of `SA-J` (two modifier overloads, two `ProposalFrame`
     initializers, two `LayoutModifier` cases) and the lane 1 skeleton;

   `swift test --no-parallel` read `Test run with 993 tests in 1 suite passed`,
   with 0 `error:` and 0 `warning:`. The experiment's message strings were
   confirmed present in the test binary (`strings -a`), so the run exercised
   them. Everything was reverted, and a clean re-run read 993 again. `SA-I`,
   `SA-J`.
9. **Where a legacy style modifier on a proposal `Component` can be hosted
   (third pass, against the skeleton).** With `Toggle: Component,
   ProposalElementGroup` whose content is `Rectangle()`:
   - `Column { Toggle().width(Pixels(70)) }` compiles;
   - `Toggle().width(Pixels(70))` as a root does not: `return type of global
     function 'probe()' requires that 'StyledComponent<Toggle>' conform to
     'Element'`;
   - `HStack { Toggle().width(Pixels(70)) }` does not: `generic struct 'HStack'
     requires that 'StyledComponent<Toggle>' conform to 'ProposalElementGroup'`;
   - an external `Container<Content: ElementGroup>: Element` that declares
     `extension Container: ProposalElementGroup {}` unconditionally and calls
     `requestNativeLayout` compiles, and so does
     `HStack { Container { Toggle().width(Pixels(70)) } }`. On that path no
     legacy `newNode` is ever called, so the `setStyle` trap is the only one
     that fires. `SA-G`, `SA-R`.

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
- `SA-R`: item (e)'s "compile-time" criterion, amended explicitly.

### Public API

```swift
// Sources/MetalUILayout/ProposalLayout.swift  (new)

/// A proposal-layout algorithm: measure subviews at proposals, then place them.
/// MetalUI's value counterpart to SwiftUI's `Layout`, not a source-compatible copy.
public protocol ProposalLayout: Sendable {
    /// The subviews handed in can measure and cannot place (SA-C).
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement

    /// `bounds` is root-absolute. A subview this never places is centred in
    /// `bounds` at its answer to `proposal`; a subview placed more than once
    /// keeps its last placement. Every subview's own subtree is placed ONCE,
    /// after this returns (SA-E, probe J and K's log order).
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize,
                       subviews: PlacementSubviews)
}

public struct MeasurementSubviews: RandomAccessCollection {
    public var startIndex: Int { get }
    public var endIndex: Int { get }
    public subscript(position: Int) -> MeasurementSubview { get }
}

public struct MeasurementSubview {
    /// The value of a `layoutPriority` node that IS this subview, looking
    /// through any depth of overlay attachments (`.overlay`) to their primary
    /// child, else 0. The built-in stack's rule (`nativeLayoutPriority`, which
    /// lane 1 changes to look through attachments). SwiftUI agrees for every
    /// modifier MetalUI's proposal path has (probes L, L2); a single-child
    /// stack is the one place it does not, and that is carried (L3, SA-N).
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
    /// Records a placement. After `placeSubviews` returns, the subview is
    /// stored at its answer to `proposal`, offset from `position` by
    /// `anchor`'s factors times that size (probes K, K2), and its subtree is
    /// placed. A later call for the same subview replaces the record (probe J).
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
3. **`nativeLayoutPriority` looks through `.overlayAttachment`** to
   `children(id)[0]`, recursively. This is the one built-in **rule** lane 1
   changes, in its own commit with its own red test, because the proxy's
   `priority` must equal the built-in stack's (`SA-D`) and probe L2 shows
   SwiftUI's priority survives `.overlay`. `isNativeSpacer` is not changed.
4. **`measureNative` for `.custom`.** Build `MeasurementSubviews` over
   `(run, children)`. Then `run.measureDepth += 1`, call
   `layout.sizeThatFits(proposal:subviews:)`, and `run.measureDepth -= 1`.
   A proxy's `sizeThatFits` calls `measureNative(child, proposal:, run:)`, so
   every proxy measurement goes through the cache.
   - Every proxy member first checks
     `precondition(run.isActive, "a layout subview outlived its layout run")`.
   - For symmetry, wrap the built-in cases' bodies in the same `measureDepth`
     bracket.
5. **`placeNative` for `.custom`.**
   1. Store `bounds` for the node, as every case does (`:495`).
   2. Take a fresh token from `nextPlacementToken`, and save
      `run.activePlacement` before setting it to that token.
   3. Build `PlacementSubviews` carrying the token and one optional
      **placement record** per child — `(position, anchor, proposal)` —
      held in a small reference box shared by the collection's proxies.
   4. Call `placeSubviews`, then restore `run.activePlacement`.
   5. Then, **in one loop over the children in index order**, place each child
      exactly once:
      - with a record: measure it at the record's `proposal` through the cache,
        compute the rect as `position − anchorFactor × size`, and call
        `placeNative(child, in: rect, proposal:)`;
      - without one: measure it at the parent's `proposal`, and place it centred
        in `bounds` at that answer (probe I2).
6. **`PlacementSubview.place`** runs in this order:
   1. `precondition(token == run.activePlacement, "a PlacementSubview was used outside its placeSubviews call")`.
   2. `precondition(run.measureDepth == 0, "a PlacementSubview was used during measurement")`.
      This is the dynamic backstop behind the static one (`SA-C`, probe D).
   3. Write the record into the box, replacing any earlier record for this
      child. Nothing is measured or placed here.

   **Why deferred.** Probe J shows a subview placed twice runs its own
   `placeSubviews` once, and J2 is that counter's positive control. Probe K's
   log order shows SwiftUI places subtrees only after the parent's
   `placeSubviews` returns. An eager `place` that recursed on every call would
   run a twice-placed subtree twice, a visible side effect in a custom child's
   `placeSubviews`, and would double the work at every level of a chain of
   layouts that each re-place a child: 2^depth. The last record wins, so the
   last placement wins (probe J). The index-order loop is MetalUI's own order;
   SwiftUI's is the reverse, and nothing may rely on either.

### Migration story for external custom elements (item e)

This table goes into the inventory's "Completion criteria for task 1", and into
a dated note in `specs/2026-09-12-native-layout-kernel-design.md`.

| an external module wants | it writes, using only public API |
|---|---|
| a leaf | an `Element` whose `requestLayout` returns `pass.requestNativeLeaf { proposal in … }`, plus `extension X: ProposalElementGroup {}`. This works today; the demo's `PriorityPreviewPanel` does it (`main.swift:930-955`). |
| a container algorithm | a `struct X: ProposalLayout`, used as `X() { … }`, `X { … }` or `ProposalLayoutContainer(X()) { … }` |
| a container element with its own paint or input | an `Element` that calls `content.requestGroupLayout(under:at:pass:)`, then `pass.requestNativeLayout(layout, children:)`, and delegates `prepaintGroup`/`paintGroup` |
| a legacy root | unchanged: `requestNode`/`requestLeaf`. Neither is deprecated in this milestone (`SA-F`). |

**What stays unchecked, named so nobody assumes otherwise (`SA-R`).**
`ProposalElementGroup` still has no requirements, so the marker is a promise the
compiler does not check. Two shapes compile and are caught only at run time:
- a conformer whose `requestLayout` registers a legacy node traps at native
  registration ("contains a legacy node"), inside any proposal container;
- a conformer that declares the marker unconditionally over unconstrained
  `ElementGroup` content, and so hosts `StyledComponent`, compiles
  (evidence 9) and traps at `setStyle`.

Lane 2 pins both traps. Closing them at compile time needs a typed node id in
`Element`'s layout requirement, which `SA-R` assigns to plan task 3 and
records as an explicit amendment of item (e)'s criterion.

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
| `aSubviewMeasuresOncePerDistinctProposalWithinOneRun`: a custom layout asks child 0 at (50, 50) twice, then at (70, 50), in `sizeThatFits`; `placeSubviews` asks (50, 50) again and **places child 0 at (50, 50)**, as probe A/B/C's parent does. The leaf closure's count goes 1, then +1, then +0, and reads **2** after the call returns. Placing the child matters: an unplaced child is measured at the parent's proposal (`SA-E`), which would add a call on a correct kernel unless the root proposal happened to be (50, 50) or (70, 50). | counts 0 | the proxy's `sizeThatFits` calls the leaf closure directly instead of `measureNative` |
| `placingASubviewUsesItsAnswerToThePlacementProposalAndTheAnchor`: parent bounds `(25, 25, 150, 150)`, five proposal-echoing leaves, probe K and K2's placements; expected rects `(25, 25, 70, 40)` topLeading, `(110, 115, 30, 20)` center, `(95, 105, 30, 20)` bottomTrailing, `(95, 125, 30, 20)` **topTrailing** and `(125, 115, 30, 20)` **leading** | all zero | (1) anchor factors transposed h↔v, which only the topTrailing and leading arms can see, since the other three anchors have equal factors; (2) the rect ignores the record's `proposal` |
| `anUnplacedSubviewIsCentredInItsParentAtTheParentsProposal`: probe I2's numbers, bounds `(120, 70, 100, 100)`, proposal 100×100, a fixed 30×30 child, expected `(155, 105, 30, 30)`; a proposal-echoing second child is expected at `(120, 70, 100, 100)`. Arm I is not used: its `(0, 0, 200, 200)` cannot tell centring from a placement at the root origin. | zero rect | unplaced children left at the zero rect; unplaced children placed at the bounds origin |
| `aSubviewPlacedTwiceKeepsItsLastPlacement`: probe J, expected `(100, 100, 40, 40)` in bounds `(50, 50, 100, 100)` | zero | `place` keeps the first record instead of replacing it |
| `aSubviewPlacedTwicePlacesItsSubtreeOnce`: the child is itself a custom layout that counts its `placeSubviews` runs into a file-scope box; its parent places it twice, as probe J's does. The count reads **1**. | 0: the skeleton places nothing | `place` recurses into `placeNative` on every call, eagerly: the count reads 2 |
| `aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules`: priority 2.5 reads 2.5; priority 2 under a `frame` reads 0 (probe L); priority 2 under one overlay attachment reads 2, and under two reads 2 (probe L2); priority 2 as the only child of a linear stack reads **0, pinned wrong on purpose** (SwiftUI reads 2, probe L3, `SA-N`); a spacer under two `layoutPriority` nodes is a spacer; a spacer under `frame` is not; a spacer under an overlay attachment is not; a plain leaf reads 0 and false | the skeleton answers 0 and false | `priority` looks through one wrapper of any kind; `priority` stops looking through attachments; `isSpacer` recurses through `frame` too |
| `aPlacementSubviewUsedOutsideItsPlaceSubviewsCallTraps` (exit test): sibling A stashes its `PlacementSubviews` in a file-scope `@unchecked Sendable` box, and sibling B's `placeSubviews` calls `place` on it. stderr contains `"used outside its placeSubviews call"`. | exits 0 | delete the token precondition |
| `aPlacementSubviewUsedDuringMeasurementTraps` (exit test): a parent stashes its `PlacementSubviews`; inside its own `placeSubviews` it asks `subviews[1].sizeThatFits` at a proposal not yet measured, so the child's `sizeThatFits` runs while the parent's call is active, and calls `place` on the stash. stderr contains `"used during measurement"`. | exits 0 | delete the `measureDepth` precondition. The token check alone passes here, because the parent's `placeSubviews` is still active. |
| `aSubviewUsedAfterItsLayoutRunTraps` (exit test): a layout stashes `MeasurementSubviews`; after `computeNativeLayout` returns, the test calls `sizeThatFits` on it. stderr contains `"outlived its layout run"`. | exits 0 | delete the `isActive` precondition |

`Tests/MetalUILayoutTests/NativeLayoutTests.swift` (existing) gains one test:

| test | red before | mutation after |
|---|---|---|
| `aLinearStackReadsPriorityThroughAnOverlayAttachment`: a horizontal stack offered 100 holds two flexible leaves of ideal 80; the first is under `layoutPriority(1)` then an overlay attachment. Expected allocations 80 and 20, hand-derived; SwiftUI's P7 control gives the same split with the priority outermost. | 50/50: today's rule reads 0 through the attachment | remove the look-through from `nativeLayoutPriority` |

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

`Tests/MetalUITestSupport/Typecheck.swift` gains a second helper, and
`Tests/MetalUITests/ProposalLayoutCompileGuards.swift` (new) uses only it.

```swift
/// Typechecks `source` verbatim as a whole file after `import <module>`, in the
/// Swift 6 language mode: file-scope declarations, `public` types and
/// extensions, exactly as an external module writes them.
public func typecheckFile(_ source: String, importing module: String) throws -> TypecheckResult
//  arguments: the same as typecheck(_:importing:), plus "-swift-version", "6"
```

**Why a second helper** (evidence 6). `typecheck(_:importing:)` wraps its body
in `func fixture() { … }` and passes no `-swift-version`:
- the wrapper makes every fixture type a **local** type, and rejects the
  migration table's own `extension X: ProposalElementGroup {}` with
  `declaration is only valid at file scope`;
- Swift 5 mode reports a `Sendable` violation in an external `ProposalLayout`
  as a warning, exit 0, where the package's own Swift 6 mode rejects it.

The existing helper and its 39 guards are unchanged.

- **Each fixture is a whole file compiled against a plain `import MetalUI`.**
  `MetalUI` re-exports `MetalUILayout` (`App.swift:9`). The test file's own
  import is irrelevant; the fixture's is what counts (shape 16).
- **Types and extensions are `public` and at file scope.** Use sites go in
  `@MainActor public func probe()`.
- The diagnostics below were re-printed in the third pass from the evidence-6
  skeleton, at file scope in Swift 6 mode. Re-print them from the real
  implementation before trusting any substring.

| guard | kind | must hold | measured diagnostic |
|---|---|---|---|
| `typecheckFileChecksInTheSwift6LanguageMode` | instrument | a public `struct Leaky: ProposalLayout` with a stored `public var box = Box()`, where `Box` is a non-`Sendable` final class, fails | `stored property 'box' of 'Sendable'-conforming struct 'Leaky' has non-Sendable type 'Box'` (in Swift 5 mode the same fixture exits 0 with a warning) |
| `anExternalModuleCanBuildACustomLeafAndContainerFromPublicAPI` | positive | The fixture declares a public `ProposalLayout` that reads `priority`, `isSpacer`, `sizeThatFits`, `place(at:anchor:proposal:)` and both factors. It also declares a public leaf `Element` over `requestNativeLeaf` with `extension Leaf: ProposalElementGroup {}`, and a public generic container `Element` that calls `requestGroupLayout` then `requestNativeLayout`, with its own file-scope conformance extension. It uses all three: in `HStack { Diagonal() { Leaf(); Spacer() }; Container { Leaf() }; Diagonal(alignment: .top) { Leaf() } }` inside a `VStack`, as `ProposalLayoutContainer(Diagonal()) { Leaf() }` and as `Diagonal { Leaf() }.padding(…)`. Must succeed. | exit 0, no diagnostic |
| `aMeasurementSubviewCannotBePlaced` | negative | `subviews[0].place(at: Point(x: 0, y: 0), proposal: .unspecified)` inside `sizeThatFits` fails | `value of type 'MeasurementSubview' has no member 'place'` |
| `subviewProxiesCannotBeConstructedOutsideTheKernel` | negative | `_ = MeasurementSubviews()` fails, and, as a second fixture, `_ = PlacementSubview()` fails | `'MeasurementSubviews' initializer is inaccessible due to 'internal' protection level` (likewise `'PlacementSubview'`). The skeleton's collection init took an argument, so it also printed `missing argument for parameter 'n' in call`; match the inaccessible fragment only. |
| `aCustomLayoutContainerRejectsLegacyContent` | negative | three fixtures fail: `_ = Diagonal() { Text("legacy") }`, `_ = Diagonal { Text("legacy") }` and `_ = ProposalLayoutContainer(Diagonal()) { Text("legacy") }` | `instance method 'callAsFunction' requires that 'Text' conform to 'ProposalElementGroup'` (both call spellings); `generic struct 'ProposalLayoutContainer' requires that 'Text' conform to 'ProposalElementGroup'` |

**Prove each new guard runs.** A guard skips silently when the modules directory
is missing (CLAUDE.md, "When CI lands").
1. Build once with `swift build --build-system native`.
2. Run the five guards.
3. In a worktree, mutate each one red once:
   - give `MeasurementSubview` a `place` method → `aMeasurementSubviewCannotBePlaced`;
   - give `MeasurementSubviews` a `public init()` → `subviewProxiesCannotBeConstructedOutsideTheKernel`;
   - relax `ProposalLayoutContainer`'s own constraint to `Content: ElementGroup`
     (its conformance becomes `where Content: ProposalElementGroup`) →
     `aCustomLayoutContainerRejectsLegacyContent`, **on its container fixture
     only**: the two `callAsFunction` fixtures still fail, on the method's own
     constraint (measured on the skeleton);
   - relax `callAsFunction`'s constraint to `Content: ElementGroup` **as well** →
     all three fixtures compile (measured on the skeleton);
   - rename `requestNativeLayout` → the positive guard;
   - delete `"-swift-version", "6"` from `typecheckFile` →
     `typecheckFileChecksInTheSwift6LanguageMode`.
4. Record that each went red.

**A mutation that is not one.** Dropping only `callAsFunction`'s explicit
`Content: ProposalElementGroup` changes nothing: Swift infers the requirement
from the return type `ProposalLayoutContainer<Self, Content>`. Measured on the
skeleton: the library builds, and both `callAsFunction` fixtures still fail with
the same diagnostic. Do not list it as a guard mutation.

Guard count: **39 → 44**. Test count: **+17** (10 kernel in the new files, 1 in
`NativeLayoutTests.swift`, 1 integration, 5 guards).

### Docs owed by lane 1

- **`specs/2026-09-12-native-layout-kernel-design.md`:** a dated *Superseded*
  note under "Kernel protocol and tree representation" pointing here. Remove
  "The layout protocol" from its Not shipped list.
- **`2026-09-12-swiftui-layout-replacement-inventory.md`:** the migration-story
  table goes under "Completion criteria for task 1". Strike "Custom containers
  cannot", with a date. Under "Nothing checks that a marker conformer registers
  native nodes", add a dated note quoting `SA-R`: the criterion is amended, the
  check is a run-time trap pinned by lane 2, and the compile-time check is task
  3's.
- **`plans/2026-09-12-swiftui-alignment.md`, task 2:** move "A layout protocol"
  to Done, with the commit. Move the migration story to Done **with the words
  "under `SA-R`'s amended criterion"**, and add the marker-conformance check to
  task 3's open proofs.
- **Record §09:** a dated "Kernel completion — lane 1" subsection with counts
  and the mutation table. Correct "Users can add leaves, not algorithms."
- **Decisions doc:** fill in `SA-A`…`SA-F`'s and `SA-R`'s "Mutations" lines.
- **`CLAUDE.md`:**
  - one Architecture bullet: `ProposalLayout`, measurement proxies that cannot
    place, subtrees placed once after `placeSubviews` returns, built-ins stay
    enum cases, and sufficiency pinned by the reference stack;
  - the guard count, and that the five new guards use `typecheckFile` (file
    scope, Swift 6 mode) while the older 39 do not.

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
// every registration — newNode, newLeaf and every newNative* registrar,
// including newNativeLayout — through the one check in appendNode:
//  !isLayingOut
//  "layout node registered while layout is running (SA-I)"
public func reset(generation: UInt64)
//  existing: generation advances
//  new: !isLayingOut
//  "reset(generation:) called while layout is running (SA-I)"
```

Evidence 8 ran the suite with the registration and `reset` checks applied to
both engines at once: 993 passed, so no existing caller registers or resets
mid-layout.

Internal additions:

- **`private func appendNode(style:children:)`.** This is the storage append.
  It holds the `!isLayingOut` registration check and **not** the native-child
  check. Every native registrar calls it, so native nodes keep appending their
  `Style.default` row, `nil` measure, rect and measured width. Public `newNode`
  becomes the native-child check plus `appendNode`, and `newLeaf` still routes
  through `newNode`, so one registration check covers every path.
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
7. **Mutation of the tree during a call traps**, through exactly these checks:
   - `setStyle`;
   - any registration: `newNode`, `newLeaf` and every native registrar;
   - `reset(generation:)`;
   - a re-entrant layout call of either engine;
   - `setLayout` from inside native measurement.

   **Not checked:** `setLayout` from a custom layout's `placeSubviews`, or from
   any code that runs during placement but outside a measurement body. A later
   `placeNative` may overwrite such a rect, or may not. The kernel's own
   placement writes through the same method, so a check there would need a
   second flag, and no caller exists.

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
| `registeringANativeNodeDuringNativeLayoutTraps`: the closure calls `newNativeLeaf`; fragment `"registered while layout is running"` | exits 0 | delete the precondition from `appendNode` |
| `registeringALegacyLeafDuringNativeLayoutTraps`: a native closure calls `newLeaf` on the same tree; same fragment | exits 0 | delete the precondition from `appendNode` (reddens the arm above too); route `newLeaf` around `appendNode` (reddens this arm only) |
| `registeringANodeDuringLegacyLayoutTraps`: a legacy `computeLayout` measure closure calls `newNode(style: Style(), children: [])`; same fragment | exits 0 | delete the precondition from `appendNode` |
| `resettingATreeDuringLayoutTraps`: a native closure calls `reset(generation: 1)`; fragment `"reset(generation:) called while layout is running"` | the arrays empty mid-run and the run dies on an out-of-range index. The process fails, but stderr lacks the fragment, so the test is red on its second assertion. | delete the `reset` precondition |
| `writingARectDuringNativeMeasurementTraps`: the closure calls `setLayout`; fragment `"during native measurement"` | exits 0 | move `measureDepth += 1` after the leaf closure call |

`Tests/MetalUILayoutTests/NativeInvalidationContractTests.swift` (new,
`@testable`, since it reads `isLayingOut` and `measureNativeLayout`):

| test | red before | mutation after |
|---|---|---|
| `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns`: exit `.success`; `precondition(tree.isLayingOut)` inside a closure, `!isLayingOut` after return, and `setStyle` on a legacy node succeeds after | the inside flag is false, so it exits non-zero | **(A)** move `endLayout()` out of the `defer` to directly after `beginLayout()`. In-process callers that lay one tree out twice keep working, so the suite completes; this test reddens, and so do the exit tests that need the flag during native layout (`setStyleOnALegacyNodeDuringNativeLayoutTraps`, `computeLayoutCalledFromANativeMeasureClosureTraps`, `computeNativeLayoutReenteredFromAMeasureClosureTraps`, `registeringANativeNodeDuringNativeLayoutTraps`, `registeringALegacyLeafDuringNativeLayoutTraps` and `resettingATreeDuringLayoutTraps`; the legacy-path `registeringANodeDuringLegacyLayoutTraps` stays green). Name them all. **(B)** drop the `defer { endLayout() }` entirely. This does **not** redden one test: every in-process test that lays out one tree twice traps "re-entered" — at least `aNativeLinearStackUsesItsAlignmentOnTheCrossAxisOnly` (`NativeLayoutTests.swift:365-382`), `aSecondComputeNativeLayoutCallReMeasuresEveryLeaf`, `aDifferentRootProposalReMeasuresAndMovesTheRects` and `aResetTreeMeasuresItsNewRegistrationsFromScratch` — and the run truncates (shape 11). Record (B)'s outcome as that truncation and its summary shortfall, and read this test's red under (B) from a `--filter` run of this test alone. |
| `measuringANativeTreeWritesNoRect`: `measureNativeLayout` over lane 1's reference tree leaves every stored rect at `LayoutRect(x: 0, y: 0, width: 0, height: 0)`, and its measurement equals `computeNativeLayout`'s on a twin tree | red by assertion against a skeleton `measureNativeLayout` that delegates to `computeNativeLayout` | `measureNativeLayout` also calls `placeNative` on the root. Placement runs outside any measurement body, so nothing traps and rects are written. **Not** "add a `setLayout` to `measureNative`'s leaf branch": lane 1 wraps the leaf case in the `measureDepth` bracket, so lane 2's own `setLayout` check traps in-process and truncates `MetalUILayoutTests` instead of reddening this test, and `writingARectDuringNativeMeasurementTraps`, which expects exactly that trap, stays green. |
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
| `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration`: exit test. A `Component, ProposalElementGroup` named `Toggle` whose content is `Rectangle()`, rendered as `var root = Column { Toggle().width(Pixels(70)) }`, which compiles (evidence 9; `StyledComponent` is not an `Element`, so it cannot be the root itself). Fragment `"setStyle on a native layout node"`. **Why the fragment discriminates although `Column` also traps:** `StyledComponent.requestGroupLayout` registers the `Rectangle`'s native leaf and calls `setStyle` on it before it returns, and `Column` calls `newNode` only after its content returns, so the `setStyle` trap fires first. | exits 0, with the width silently inert | delete the `setStyle` precondition. The process then traps at `Column`'s `newNode` ("given a native child"), so the test is red on its fragment assertion. |
| `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer`: exit test. An `Element, ProposalElementGroup` whose `requestLayout` calls `pass.requestNode`, placed in an `HStack`; fragment `"contains a legacy node"` | **green on arrival** | delete the child loop from `newNativeLinearStack` |

### Files

- **`Sources/MetalUILayout/LayoutTree.swift`:** `appendNode` and its
  registration check, the `newNode`, `setStyle` and `reset(generation:)`
  checks, `setLayout`'s check,
  `beginLayout`/`endLayout` in the native entry points, and
  `measureNativeLayout`.
- **`Sources/MetalUILayout/FlexEngine.swift`:** the `computeLayout`
  precondition.
- **`LayoutTree.isLayingOut`'s doc comment** (`:64-74`): it now covers both
  engines.
- **The three test files above.**

Test count: **+22** (19 kernel, 3 integration).

### Docs owed by lane 2

- **Record §09 "Hazards":** item 1 closed, with test names. Item 2's trap is now
  pinned. Correct §1's "No re-entrancy guard" bullet.
- **`specs/2026-09-12-native-layout-kernel-design.md`:** a dated follow-up to
  the superseded note "Mixed trees are rejected in one direction only".
- **Inventory, "One authority per rendered subtree":** rewrite the bullets.
  There is still no adapter (`SA-G`).
- **`CLAUDE.md`, Architecture:** "One layout authority per root. A native node
  under a legacy node, a legacy node under a native one, and a `Style` written
  onto a native node all trap. The native cache lives for one call (`SA-H`),
  measurement never writes a rect, and registering, resetting or restyling a
  tree while either engine is laying it out traps."
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

**The rule.** Reject a parameter only if one of two clauses holds:
1. **SwiftUI rejects it**, by logging "Invalid frame dimension" or
   "Contradictory frame constraints", by trapping, by hanging, or by having no
   spelling for it;
2. **it would make the node's measurement, or a rect the node places,
   non-finite at a proposal with no infinite axis** — every axis finite or
   unspecified.

- **A rejection is a `precondition`** whose message names the parameter.
  MetalUI has no runtime-warning channel (`FontResolver.resolve`'s precedent).
- Where SwiftUI's own answer is to **log and draw** (the diagnosed frame rows),
  MetalUI traps instead. That is deliberate, and `SA-J` says what it costs.

The corollary for **computed values**, checked at the checkpoints below: **a
measurement may be infinite; a stored rect may not; nothing may be NaN.** The
corollary does not contradict clause 2. An infinite measurement is legitimate
as the answer to a proposal with an infinite axis (P6's `Color` offered ∞
answers ∞), or when user code answers it. Clause 2 rejects only a **parameter**
that produces one at a proposal with no infinite axis, where the value must
have come from the parameter itself.

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
| frame `ideal…` | negative, NaN (clause 1); +∞ (clause 2: ∞ at the unspecified proposal) | — | P4b, P4d |
| frame ordering | min > max, min > ideal, ideal > max | equal values | P4, P4c |
| a fixed and a flexible dimension together | **at compile time** in the element API: `frame` splits into SwiftUI's two overloads, so neither one axis nor two axes can mix them (guarded). **At registration** in the kernel: `newNativeFrame`/`requestNativeFrame` keep one registrar, and a fixed and a flexible dimension **on one axis** trap there as a backstop | a fixed dimension on one axis and a flexible one on the other, through the kernel registrar only | no SwiftUI overload spells either (measured: `Color.red.frame(width: 10, minWidth: 5)` → `extra argument 'minWidth' in call`; likewise `minHeight`) |
| `Spacer` `minLength` | NaN, +∞, −∞ | negative: −30 between two 20s answers 10 | P5, P9 |
| `layoutPriority` | NaN (SwiftUI hangs) | **±∞, a trap today (`SA-K`)**: +∞ orders like 1 (80/20), −∞ like −1 (20/80) | P7, P7b |
| `aspectRatio` ratio | 0 (∞ on a one-axis proposal), NaN, +∞, −∞ | **negative, a trap today (`SA-K`)**: −2 `.fit` at 100×80 gives 100×−50; `.fill` at 100×80 gives −160×80; `.fit` at `nil`×80 gives −160×80; `.fit` at 100×`nil` gives 100×−50 | P8, P8b, P9 |
| root and every internal proposal | a NaN axis (checkpoint 1) | negative, zero, ∞ (`Color` offered ∞ answers ∞) | P6 |
| a measurement | a NaN size or baseline (checkpoint 2) | ±∞ | P6, N |
| a stored rect | any non-finite field (checkpoint 3) | negative width or height | M, P2c |

**Four of these rows are decided by clause 2 rather than clause 1, recorded in
`SA-J`:**
- **`ideal` +∞.** SwiftUI does not diagnose it, but it answers ∞ at an
  unspecified proposal (P4b). That is the proposal every stack child and every
  scroll viewport's content receives on its main axis. Clause 2 rejects it at
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
  becomes `width / ratio <= height` for `.fit` and `>=` for `.fill`.
  - **Probed on every sign, P8c.** For ratio 2 and −2, `.fit` and `.fill`, at
    100×−10, 100×0, −100×80, 0×80, −100×−80 and −100×−10, the new predicate
    picks SwiftUI's branch in **24 of 24** arms; today's `width / height <=
    ratio` in **12**.
  - **So this is also a repair for positive ratios** at a zero or negative
    axis. Today 2 `.fit` at 100×−10 answers 100×50, where SwiftUI answers
    −20×−10. For a positive ratio and both axes positive the two predicates
    agree.
- **Padding's measured size** becomes `max(0, child + leading + trailing)` per
  axis. For positive insets over a non-negative child this is unchanged.
- **The MetalUI modifier preconditions** (`NativeModifiedContent.swift:271-272`,
  `:279`) change to the kernel's rule, so the two layers cannot disagree.
- **The frame element API splits into SwiftUI's two overloads.** Measured
  against the third-pass skeleton (evidence 6, 8):
  - `ProposalElementGroup.frame(width:height:alignment:)` and
    `.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`,
    replacing the one nine-parameter `frame`;
  - the same two for `nativeFrame`, which stays undeprecated, because four
    integration tests call it and a deprecation would print `warning:`;
  - `ProposalFrame.init(width:height:alignment:content:)` and
    `init(minWidth:…:maxHeight:alignment:content:)`; its stored properties
    stay;
  - `LayoutModifier.frame(width:height:alignment:)` and a new
    `.flexibleFrame(minWidth:…:maxHeight:alignment:)`, so
    `ModifiedContent(content:modifier:)` cannot spell the combination either.
  - `Text("…").frame(width:)` still selects the legacy `FrameModifier`, and a
    proposal element's `.frame(width:height:)` still returns
    `ModifiedContent`; both measured. No `Sources/` or `Tests/` caller used a
    combined spelling: the whole suite compiled and passed with the split.
  - `.frame()` and `.frame(alignment:)` still compile with no diagnostic, where
    SwiftUI deprecates `frame()` ("Please pass one or more parameters").
    Carried to task 4 (`SA-N`).
- **No source doc changes for the non-negative proposal rule.** The sentence
  "a finite proposal must be non-negative" exists only in
  `specs/2026-09-12-native-layout-kernel-design.md:107`, and lane 3's docs owed
  already supersede it there. `ProposedSize.swift` has no such text (grep).

**One existing test changes, and why.**
`aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes`
(`NativeLayoutTests.swift:168`) declares `minWidth: 40, idealWidth: 90,
maxWidth: 80`, and ideal > max is rejected. Re-fixture it with `idealWidth: 70`.
- Re-derive its expectations by hand before running: measurement 70×20, child
  rect unchanged at `(10, 14, 30, 10)`, and **the leaf closure's own
  `#expect(proposal == ProposedSize(width: 80, height: 60))` changes to
  `(70, 60)`**. That in-closure expectation is easy to miss, and it is the one
  that sees the ideal reach the child.
- The re-fixture loses the "ideal clamped by max" case. That clamp is
  unreachable once the ordering is validated, so it is not a lost pin.

### Depth guard (`SA-L`)

- **`NativeLayoutRun.maxDepth` is its own constant**, not an alias of
  `LayoutContext.maxDepth`, and it counts **native nodes**.
- **Its value comes from legacy's safety fraction, not from legacy's number.**
  Legacy chose 64 = 0.60 × its 107-level debug ceiling on a 1 MB thread. Native
  takes **the largest multiple of 8 not above 0.60 × the smallest native
  ceiling**, measured the same way. From evidence 5's ceilings (padding and
  frame 193, linearStack 171) that is 0.60 × 171 = 102.6, so **96**, before the
  custom kind is bisected (below).
- **No parity is claimed.** An earlier draft said "a tree the legacy engine
  accepts must not be rejected by its proposal port for depth alone". That was
  never measured, and it is not true in general. Legacy stores size, aspect
  ratio and padding in one node's `Style`, while natively `frame`, `padding`,
  `aspectRatio`, `layoutPriority`, `fixedSize` and `.overlay` each add a node.
  So one legacy level ported as `.padding(…).frame(width:)` is at least three
  native levels. How a real ported tree's native depth compares with its
  legacy depth is **unmeasured**. A deeper native tree traps with the node
  named, rather than overflowing.
- **Its doc table records the debug ceilings on a 1 MB thread:**
  padding/frame 193 (≈5.3 KB/level) and linearStack 171 (≈6.0 KB/level),
  against legacy's 107 (≈9.8 KB), plus the custom kind's once bisected.
  Release is unmeasured.
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
  proxy. Use evidence 5's procedure, re-bisect padding, frame and linearStack
  on the lane's own build (the run object changes every frame's size), and set
  `maxDepth` by the formula above from the smallest of the four. Record all
  four ceilings and the arithmetic in the doc table and in `SA-L`.

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
| fixed dimension (`>= 0 && isFinite`) | `aNegativeFixedFrameDimensionTraps`, `aNaNFixedFrameDimensionTraps`, `anInfiniteFixedFrameDimensionTraps`. No −∞ arm: both halves reject it, so it cannot tell a mutation of either half. NaN is also rejected by both halves, so deleting either half leaves the NaN arm green; its own mutation is the NaN-blind spelling `!(x < 0) && x != .infinity`, which still rejects −10 and +∞. |
| minimum (`!isNaN && != +∞`) | `aNaNFrameMinimumTraps`, `anInfiniteFrameMinimumTraps` |
| maximum (`>= 0`) | `aNegativeFrameMaximumTraps`, `aNaNFrameMaximumTraps`. `>= 0` is false for NaN, so the rule needs no `!isNaN` clause, which could never be reddened alone. The NaN arm's own mutation is the NaN-blind spelling `!(maximum < 0)`: it still rejects −10 and accepts NaN. |
| ideal (`>= 0 && isFinite`) | `aNegativeFrameIdealTraps`, `aNaNFrameIdealTraps`, `anInfiniteFrameIdealTraps`. The NaN arm's mutation is the NaN-blind spelling, as for the fixed dimension. |
| ordering and combination | `aFrameMinimumAboveItsMaximumTraps`, `aFrameMinimumAboveItsIdealTraps`, `aFrameIdealAboveItsMaximumTraps`, `aFixedFrameDimensionCombinedWithAFlexibleOneTraps` (kernel registrar only; the element API cannot spell it) |
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
| `aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes`: four P8c arms each of which today's predicate gets wrong — 2 `.fit` at 100×−10 answers −20×−10; 2 `.fill` at 100×−10 answers 100×50; −2 `.fit` at 100×0 answers 100×−50; 2 `.fill` at −100×−80 answers −100×−50 | traps on the negative ratio arm; the other three read today's branch | keep `width / height <= ratio` (reddens all four) |
| `theProposalModifiersAcceptWhatTheKernelAccepts` (in `MetalUITests`): **exit `.success`**, because its red run is a trap at construction, which in-process would abort the whole `MetalUITests` process. `Rectangle().layoutPriority(.infinity)` and `.aspectRatio(-2)` render, with `precondition`s on the rendered bounds. | traps at construction | leave `NativeModifiedContent.swift`'s preconditions unchanged |

`Tests/MetalUITests/ProposalLayoutCompileGuards.swift` gains one guard, through
`typecheckFile`:

| guard | kind | must hold | measured diagnostic (third-pass skeleton, file scope, Swift 6) |
|---|---|---|---|
| `aFixedAndAFlexibleFrameDimensionCannotBeCombined` | negative | five fixtures fail: `Leaf().frame(width: Pixels(10), minWidth: Pixels(5))`; `Leaf().frame(width: Pixels(10), minHeight: Pixels(5))`; `ProposalFrame(width: Pixels(10), maxWidth: Pixels(20)) { Leaf() }`; `ModifiedContent(content: Leaf(), modifier: .frame(width: Pixels(10), minWidth: Pixels(5)))`; `Leaf().nativeFrame(width: Pixels(10), minWidth: Pixels(5))`. A positive half in the same guard: `Leaf().frame(width: Pixels(10), alignment: .leading)` and `Leaf().frame(minWidth: Pixels(5), maxWidth: Pixels(20))` compile. | `extra argument 'minWidth' in call` (modifier, `LayoutModifier` case, `nativeFrame`); `extra argument 'minHeight' in call`; `extra arguments at positions #2, #3 in call` (`ProposalFrame`) |

Mutation: restore the nine-parameter `frame` modifier alongside the two
overloads. Its first two fixtures then compile, so the guard reddens.

`Tests/MetalUILayoutTests/NativeDepthGuardTests.swift` (new, `@testable`).
- Each trap test runs its layout on an explicit 4 MB `Thread`
  (`LayoutContextTests.swift:177-189` says why) and asserts the fragment.
- `maxDepth + 1` levels fit in 4 MB several times over: at most 97 levels of
  at most ≈6.0 KB each is ≈0.6 MB (evidence 5).

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
2. `lastNativeLayoutWork.measureCalls` == **a literal derived by hand before the
   run**, from the same proposal sequence as (3). Not "the sum of the closure
   counts": those counts are closure-call counters, so disabling the cache
   raises both sides together and the comparison cannot redden (shape 15);
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
- **`Sources/MetalUI/NativeModifiedContent.swift`:** the two modifier
  preconditions; the `frame`/`nativeFrame` overload split; the
  `LayoutModifier.flexibleFrame` case.
- **`Sources/MetalUI/NativeElements.swift`:** `ProposalFrame`'s two
  initializers.
- **`Tests/MetalUITests/ProposalLayoutCompileGuards.swift`:** the one new
  guard.
- **`Tests/MetalUILayoutTests/NativeLayoutTests.swift`:** the one re-fixtured
  test.
- **The five new test files above.**

Test count: **+52** (35 traps, 10 acceptance, 4 depth, 2 work, 1 guard), one
existing test re-fixtured. Guard count: **44 → 45**.

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
    993 → 1010 → 1032 → 1084 if the counts above hold. Guards: 39 → 44 → 44 →
    45.
  - A shortfall is a truncated run (shape 11).
  - `grep -c "error:"` and `grep -c "warning:"` must both read 0.
- **Goldens.** `git diff --stat -- '*.json'` must be empty, and
  `find Tests -name "*.json" | wc -l` must read 97.
  - `Sources/MetalUILayout/` changes in every lane, so a moved golden means the
    **CSS** engine moved. Stop and find out why.
  - `computeLayout`'s native-root precondition, `newNode`'s native-child
    precondition, and the registration and `reset` checks are the only
    legacy-reachable edits. Evidence 4 and 8 show no existing test reaches
    them.
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
