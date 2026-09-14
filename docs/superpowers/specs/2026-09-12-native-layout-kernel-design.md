# Native layout kernel design

**Milestone:** SwiftUI replacement task 2

**Status (2026-09-14, checked against `7cfcddc`):** the first slice shipped,
and the slice then grew well past its non-goals. The design text below is kept
as written. Passages the source contradicts carry a dated *Superseded* note.

Shipped:
- `ProposedSize`, `LayoutMeasurement`, `ProposalAlignment` (nine cases),
  `ProposalStackAxis`, `AspectRatioContentMode` and
  `ProposalMeasureFunction` (`Sources/MetalUILayout/ProposedSize.swift:8-52`,
  `LayoutTree.swift:796-833`).
- Eleven public `LayoutTree.newNative*` registrars (`LayoutTree.swift:110-266`):
  leaf, overlay, overlayAttachment, frame, padding, fixedSize, aspectRatio,
  layoutPriority, spacer, scrollViewport, linearStack. Each has a
  `LayoutPass.requestNative*` mirror (`Sources/MetalUI/Passes.swift:60-129`).
- `computeNativeLayout(root:proposal:in:)`, whose `(node, proposal)`
  measurement cache is local to that call (`LayoutTree.swift:275-282`).
- Stored-rect rounding after placement, the same cumulative-edge rounding the
  legacy path uses (`roundNativeStoredRects`, `LayoutTree.swift:786-792`).
- A single root switch in `Frame.computeRootLayout` (`Frame.swift:1165-1184`).

Not shipped:
- The layout protocol and `LayoutContext`, and any type-erased algorithm: the
  kernel is a closed `private enum NativeNode` (`LayoutTree.swift:835`), so
  nobody outside `MetalUILayout` can add a layout algorithm.
- A legacy compatibility root.
- Input validation beyond the ratio and priority preconditions.
- A recursion-depth guard, work counters, or `beginLayout`/`endLayout`
  re-entrancy protection on the native path.
- Baseline producers and consumers.
- Any record of the mutation obligations in "Verification" below. No decisions
  doc exists for this milestone either.

## Purpose

Replace CSS constraint resolution with a native, frame-local layout kernel. The
kernel receives a parent size proposal, measures an element tree, and places
that tree into root-absolute rectangles. It must preserve MetalUI's existing
three-phase element pipeline and never make a second geometry store visible to
prepaint or paint.

## Non-goals of the first slice

- Porting `Row`, `Column`, `Stack`, `ScrollView`, `List`, or `Box`.
- Supporting a legacy flex node as a child of a native container, or the
  converse.
- Changing public modifiers, text shaping, scrolling, input, or animation.
- Claiming source compatibility with SwiftUI's `Layout` protocol.

> *Superseded 2026-09-14 (at `7cfcddc`).* `Row`, `Column`, `Stack`,
> `ScrollView`, `List` and `Box` are indeed unported, but parallel proposal
> types shipped beside them: `HStack`, `VStack`, `ZStack`, `Spacer`,
> `Rectangle`, `Color`, `ProposalFrame`, `Padding`, `Background`, `FixedSize`,
> `ProposalScrollView` and `ProposalText` (`Sources/MetalUI/NativeElements.swift`,
> `ProposalScrollView.swift`, `ProposalText.swift`).
>
> Public modifiers changed on both paths. The proposal path gained
> `ModifiedContent`/`LayoutModifier`, `.overlay` and `.onTap`. On the legacy
> path, `StyledElement.padding` now returns `Box<Self>` (`Box.swift:640-650`)
> and `.frame(width:height:)` returns `FrameModifier` (`FrameModifier.swift:63-67`).
>
> Input and paint changed too:
> - `Frame.registerHandlers` gained a hit-testing gate (`Frame.swift:655`).
>   Its public entry is the new `PrepaintPass.allowsHitTesting(_:_:)`
>   (`Passes.swift:422-427`), which wraps the internal
>   `Frame.withHitTestingDisabled` (`Frame.swift:518-522`).
> - `PaintPass.fill` gained `borderColor:`/`borderWidths:` (`Passes.swift:570-576`).
> - `PaintPass.opacity` was added (`Passes.swift:579-584`).
>
> Mixed trees are rejected in one direction only. A native container given a
> legacy child traps at registration (`LayoutTree.swift:379-385`, message
> "native layout subtree contains a legacy node"). No test pins that trap. The
> converse is not rejected: `newNode(style:children:)` only validates child
> generations (`LayoutTree.swift:89-90`), and the root switch inspects only the
> root. So by reading, a native subtree under a legacy container reaches the
> flex engine as `Style.default` nodes whose native measures never run. A
> native leaf arrives as a childless default node. A native container arrives
> with its structure intact, because every native registrar passes its
> children to `newNode(style: .default, children:)` (`LayoutTree.swift:125,
> 138, 159, 248`) and `FlexEngine` walks `tree.children` (`FlexEngine.swift:180`):
> an `HStack` or frame becomes a default flex row of default child nodes. That
> reading is unverified by any run or test.

## Core values

### `ProposedSize`

```swift
public struct ProposedSize: Sendable, Hashable {
    public var width: Double?
    public var height: Double?

    public static let unspecified: ProposedSize
    public static let zero: ProposedSize
    public static let infinity: ProposedSize

    public func replacingUnspecifiedDimensions(by fallback: SizeD) -> SizeD
}
```

`nil` means the parent does not constrain that axis. It does not mean zero,
infinity, or an instruction to use intrinsic size; the child chooses its answer.
`zero` and `infinity` are explicit proposals for containers that need to ask a
child for its minimum and unconstrained responses. A finite proposal must be
non-negative. An answer is always finite and non-negative.

> *Superseded in practice, 2026-09-14 (at `7cfcddc`).* The value type matches
> this sketch (`ProposedSize.swift:8-35`). The prose around it does not match
> the source in three ways:
> - No container in `Sources/` proposes `.zero` or `.infinity`; they appear
>   only at their definitions (`ProposedSize.swift:21,24`).
> - Neither the non-negative proposal rule nor the finite-answer rule is
>   enforced. The proposal-responsive `Rectangle`/`Color` answer
>   `proposal.width ?? ideal`, so an infinite proposal gets an infinite answer
>   (`NativeElements.swift:415-422`).
> - A NaN axis never equals itself, so it misses the cache every time.

The spelling deliberately resembles SwiftUI's `ProposedViewSize`, but is a
MetalUILayout value type: the framework needs a stable, renderer-independent
contract rather than an Apple-framework dependency.

### `LayoutMeasurement`

```swift
public struct LayoutMeasurement: Sendable, Equatable {
    public var size: SizeD
    public var firstBaseline: Double?
    public var lastBaseline: Double?
}
```

Baselines are optional because boxes and shapes have none. They are distances
from the measured rectangle's top edge, not root coordinates. The kernel keeps
them now so horizontal stacks can implement real text baseline alignment without
replacing the leaf measurement contract a second time.

> *Status 2026-09-14 (at `7cfcddc`).* Baselines are carried but nothing
> produces or consumes them:
> - `ProposalText`, the only text leaf, returns a size only
>   (`ProposalText.swift:87`), and nothing in `Sources/MetalUI` spells
>   `firstBaseline`.
> - Six measure cases propagate a child's baselines (`LayoutTree.swift:410-458`).
>   Frame, padding and aspectRatio rebuild the measurement and carry them
>   across. overlayAttachment, fixedSize and layoutPriority return the child's
>   (for overlayAttachment, the primary's) `LayoutMeasurement` unchanged.
>   Overlay, linearStack and scrollViewport drop them.
> - No stack aligns on a baseline.

## Kernel protocol and tree representation

The production representation after the first slice is a node holding one of:

- a leaf measurement closure,
- a typed, type-erased native layout algorithm plus child IDs, or
- an explicit legacy compatibility root while migration is in progress.

Each native layout algorithm has two calls:

```swift
func measure(_ proposal: ProposedSize, in context: inout LayoutContext)
    -> LayoutMeasurement
func place(in bounds: LayoutRect, proposal: ProposedSize,
           context: inout LayoutContext)
```

The context is the sole route to request a child's measurement or placement. It
caches measurement by `(node ID, proposal)` for the frame. Placement never
changes a measurement and measurement never writes a rect. This direction is
what makes repeated probes safe and prevents a parent from reading a child's
stale placement as part of measurement.

`LayoutTree` remains the owner of child relationships, generation checking and
the final root-absolute `LayoutRect`. It gains a separate native-node store;
the existing `Style` arrays remain unchanged until the first migrated root is
made selectable. Do not overload `Style.display` as a native layout switch.

> *Superseded 2026-09-14 (at `7cfcddc`).* No algorithm protocol and no
> `LayoutContext` parameter exist. (`LayoutContext` is already the legacy flex
> engine's class, `Sources/MetalUILayout/LayoutContext.swift:13`.) What exists
> instead:
>
> - **Measurement and placement.** The private methods `measureNative` and
>   `placeNative` switch over a closed `private enum NativeNode` with eleven
>   cases (`LayoutTree.swift:387-610, 835-849`).
> - **The cache.** An `inout [NativeMeasurementKey: LayoutMeasurement]` is
>   created inside each `computeNativeLayout` call and dies with that call. It
>   is frame-local only because `Frame` calls it once per frame. It has no
>   sweep and no counters.
> - **Measurement never writes a rect.** This holds.
> - **Placement re-measures through the cache.** A container's measurement
>   and its placement can disagree for proposal-sensitive children. A
>   linearStack measures every child with its main axis unspecified, then
>   places each one at its compression allocation (`LayoutTree.swift:464-486`
>   vs `573-608`). This is derived from source and unmeasured.
> - **Legacy storage is shared.** The separate store is
>   `nativeNodes: [Int: NativeNode]` (`LayoutTree.swift:53`), but every native
>   node also appends a `Style.default`, a nil measure, a rect and a measured
>   width to the legacy arrays through `newNode` (`LayoutTree.swift:111`).
> - **No stored rect matches this section's model.** A root is stored at the
>   full window. Padding stores its child at bounds minus insets. aspectRatio
>   stores the ratio size even for a child that answered smaller
>   (`LayoutTree.swift:495, 531-560`).

## Root and compatibility boundary

`Frame.computeRootLayout` will select exactly one root authority:

- a native root runs `NativeLayoutEngine` with
  `ProposedSize(width: contentWidth, height: contentHeight)`;
- a legacy root continues to run `computeLayout` unchanged.

There is no mixed subtree path. The frame builds one authority for a root, so
all rects used by the following phases come from one engine. A native root may
not call `computeLayout`, and `computeLayout` may not invoke native measurement.

Before the root switch lands, `LayoutPass` grows native node and leaf
registration APIs. The existing public style registration APIs stay functional
only for legacy roots and are deprecated only after custom `Element` authors
have a compile-time replacement.

> *Superseded 2026-09-14 (at `7cfcddc`).* There is no `NativeLayoutEngine`
> type. What happens instead, in order:
>
> 1. `Frame.computeRootLayout` checks only `tree.isNativeLayoutNode(root)`
>    (`Frame.swift:1166`).
> 2. It calls `LayoutTree.computeNativeLayout` with the content size as both
>    the proposal and the bounds, and discards the root's measurement
>    (`Frame.swift:1167-1174`).
> 3. The root is therefore stored at the full window rect rather than at its
>    measured size. `aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`
>    pins that, though it counts no flex work.
>
> The native registration APIs landed as specified: 11 public
> `LayoutPass.requestNative*` methods, plus the `ProposalElementGroup` marker
> protocol as the compile-time boundary. `requestNode` and `requestLeaf` are
> not deprecated (`Passes.swift:32, 49`). They are functionally restricted to
> legacy roots, as the paragraph above requires: a legacy node handed to any
> native registrar traps (`LayoutTree.swift:379-385`), so under a native root
> they cannot work. What is missing is a compile-time restriction; they still
> compile anywhere.
>
> The marker is public and has no requirements
> (`ProposalElementGroup.swift:8`). Any type can opt in, and the demo does so
> for a `Component` and a hand-written `Element` (`main.swift:907, 938`). The
> "no mixed subtree path" rule is therefore enforced only for the built-in
> constructors.
>
> The native path has no depth guard, and it does not set `isLayingOut`.
> The measured width is recorded: `roundNativeStoredRects` stores each native
> node's pre-rounding width before rounding (`LayoutTree.swift:786-788`), as
> the legacy `roundStoredRects` does (`FlexEngine.swift:177-179`), and
> `ProposalText.paint` wraps at `pass.measuredWidth(of:)`
> (`ProposalText.swift:65`). What is missing is a pin: no test asserts that
> value for a native node, and the only glyph test checks `!glyphs.isEmpty`.
>
> Like `Text.requestLayout`, `ProposalText`'s measure closure is sound only
> because native layout runs synchronously on the main actor. It relies on an
> unguarded `MainActor.assumeIsolated` (`ProposalText.swift:49`).

## First native proof

The first integrated algorithm is an overlay layout, not a stack or flex
adapter. It measures every child with the same proposal, reports the component
wise maximum of child sizes, and places each child at the resolved bounds'
origin. A fixed-size leaf plus a measured leaf must demonstrate all three
operations: proposal forwarding, maximum measurement, and root-absolute
placement. Alignment enters with the `Stack` port, not this kernel proof.

> *Superseded 2026-09-14 (at `7cfcddc`).* Overlay alignment arrived in the
> kernel itself, defaulting to `.center`, with no `Stack` port; legacy
> `Stack` is untouched.
>
> - `ProposalAlignment` is read by overlay, overlayAttachment, frame, and the
>   linear stack's **cross axis only** (`LayoutTree.swift:499-529, 594-606`).
>   `HStack(alignment: .leading)` therefore places exactly like `.center`.
>   That is deliberate: `newNativeLinearStack`'s doc comment states it
>   (`LayoutTree.swift:240-243`), and
>   `aNativeLinearStackUsesItsAlignmentOnTheCrossAxisOnly`
>   (`NativeLayoutTests.swift:364`) pins it, so that test is the one a
>   main-axis alignment change would redden.
> - The first proof is `aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndCentresEachChild`
>   (`Tests/MetalUILayoutTests/NativeLayoutTests.swift:9`).
> - All nine positions are pinned by
>   `everyProposalAlignmentPlacesAnOverlayChildAtItsNamedPosition` (`:62`).
>
> The kernel also gained algorithms beyond this proof, with these semantics by
> reading of `LayoutTree.swift`:
>
> - **Frame** (`:416-428, 722-740`). `framedSize` makes a frame larger than
>   its child in three ways: through `min` (`Swift.max(min ?? 0, …)`, `:737`),
>   through a clamped `ideal` on an unspecified axis (`:731-732`), and by
>   taking a finite proposal when `max == .infinity` (`:734-735`). It grows
>   toward a larger finite proposal only in that last case.
>   `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum` pins that a
>   finite max does not take the proposal: a 20pt child in a min-40/max-80
>   frame offered 100 measures 40, from the min clamp. No SwiftUI probe is
>   cited for that case.
> - **Spacer** (`:232-234, 397-401`). `minLength: nil` becomes 0, and the
>   spacer claims the proposal on both axes.
> - **Priority** (`:685-713`). Priority groups are allocated in descending
>   order with equal shares, and an unused share is not redistributed. The step
>   runs only when the stack overflows **and has no spacer** (`:689`).
>   Non-spacer children never receive surplus.
> - **aspectRatio** (`:753-781`). With one finite axis it ignores the content
>   mode. With none, it fits inside the intrinsic size. Only the both-axes-finite
>   branch is tested.
> - **scrollViewport** (`:619-634`). It withholds the scrolling axis from its
>   content.

## Verification

- Value tests distinguish unspecified, zero, infinity and per-axis fallback.
- Kernel tests use children whose responses differ for unspecified, zero and
  finite proposals; a closure that ignores its proposal cannot satisfy them.
- The overlay proof uses two unequal leaves, so changing max to first-child or
  last-child reddens it.
- A placement test must use a non-zero parent origin and assert root-absolute
  child rectangles.
- Mutate every claim before committing: remove a proposal axis, replace max
  with one child, and omit the parent origin. Record the named tests that fail.
- The existing full suite remains green and browser goldens do not move; no
  existing element is migrated in this slice.

> *Status 2026-09-14 (at `7cfcddc`).* The suite is green at 993 tests with 97
> goldens, the same golden count as before. The orchestrator measured both;
> this edit re-ran neither.
>
> The second bullet is not met for zero. No kernel or integration test issues
> a zero proposal: `grep -n '\.zero\|width: 0, height: 0'` over
> `NativeLayoutTests.swift` finds nothing, and the only `ProposedSize.zero`
> use is the value test in `ProposedSizeTests.swift:15-18`. Kernel code can
> produce a zero axis (`paddingProposal` clamps at 0), but no test checks a
> child's response to one, so a closure that treats zero like a finite
> proposal is not caught.
>
> No document records the named tests that fail under the mutations above,
> and nothing in this repository shows those mutations were run. Treat the
> kernel's claims as unmutated until such a record exists.
>
> Existing elements were changed in this range:
> - `StyledElement.padding` now wraps its receiver in `Box<Self>` (commit
>   `f1944f8`).
> - `Text.swift`'s file-scope `smallestWrapWidth` lost `private` (`Text.swift:21`).
> - Legacy `.frame(width:height:)` became a `FrameModifier` node.
> - A `width`/`height` rerouting (`4aaca40`) was reverted by `d0a04d3`.
>
> Kernel-level tests live in `Tests/MetalUILayoutTests/NativeLayoutTests.swift`
> and element-level tests in
> `Tests/MetalUITests/NativeLayoutIntegrationTests.swift`. Priority has no
> kernel-level test.
