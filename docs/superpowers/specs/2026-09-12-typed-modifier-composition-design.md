# Typed modifier composition design

**Milestone:** SwiftUI replacement task 3

## Problem

MetalUI's legacy modifiers usually return `Self` by mutating `Style`. That
matches CSS declarations, but not SwiftUI's ordered modifier wrappers. The
first direct conversion of `width` and `height` to `Box<Self>` exposed the
constraint: ordinary stored `Box<Text>` and other concrete generic trees no
longer typecheck when every chained modifier changes the outer type.

Erasing routine modifier chains into `AnyElement` is not acceptable. Element
identity, `@State`, handler registration and per-phase mutation depend on the
structural tree; `AnyElement` exists only for explicit heterogeneous storage and
must remain opt-in.

## Design

Introduce a typed `ModifiedElement<Content, Modifier>: Element`, analogous to
SwiftUI's `ModifiedContent`. It owns exactly one content value and exactly one
value modifier. It receives a distinct structural identity node, delegates its
content through all three phases, and may contribute a layout wrapper node when
the modifier needs one.

The first modifier protocol separates three categories:

```swift
protocol ElementModifier {
    associatedtype Body: Element
    func body(content: Content) -> Body
}
```

The actual protocol will use a generic method or type-erased internal adapter
only where Swift's associated-type rules require it; the public result remains
fully typed. It must not expose raw `LayoutNodeID` mutation to callers.

### Placement rules

- Layout modifiers (`frame`, padding, clipping) create an outer node and own
  its placement semantics.
- Paint modifiers (`background`, opacity) wrap the paint phase without changing
  the child proposal unless documented otherwise.
- A modifier on `Component` follows the already measured distribution rule only
  if a SwiftUI probe confirms that modifier's category. It must not be made to
  distribute merely because legacy `StyledComponent` can amend `Style`.

## First feature

Port `.frame(width:height:)` onto `ModifiedElement`, preserving its current
additive API and nested-order behavior. It will be tested with a stored,
concretely typed subtree so the regression that broke `Box<Text>` boundaries is
observable. No legacy `width` or `height` API changes in this feature.

## Required proofs

- Two chained modifiers have two structural identities and preserve distinct
  `@State` slots.
- A stored concrete subtree still compiles after a modifier chain is added.
- The wrapper invokes child layout, prepaint and paint exactly once.
- Frame ordering changes the measured/placed result where SwiftUI does.
- Explicit `AnyElement` remains opt-in; no ordinary modifier path introduces it.
- Each claim is mutation-tested before its commit.
