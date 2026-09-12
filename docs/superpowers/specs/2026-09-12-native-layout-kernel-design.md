# Native layout kernel design

**Milestone:** SwiftUI replacement task 2

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

## First native proof

The first integrated algorithm is an overlay layout, not a stack or flex
adapter. It measures every child with the same proposal, reports the component
wise maximum of child sizes, and places each child at the resolved bounds'
origin. A fixed-size leaf plus a measured leaf must demonstrate all three
operations: proposal forwarding, maximum measurement, and root-absolute
placement. Alignment enters with the `Stack` port, not this kernel proof.

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
