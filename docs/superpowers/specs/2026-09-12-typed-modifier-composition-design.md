# Typed modifier composition design

**Milestone:** SwiftUI replacement task 3

**Status (2026-09-14, checked against `7cfcddc`): not implemented as
designed.** The design text below is kept as written; the passages the source
contradicts carry a dated *Superseded* note. Neither `ModifiedElement` nor
`ElementModifier` exists anywhere in `Sources/` or `Tests/`. Two separate
things shipped instead.

- **Legacy path: `FrameModifier<Content: ElementGroup>`**
  (`Sources/MetalUI/FrameModifier.swift:10-67`), returned by
  `.frame(width:height:)` on every `ElementGroup`.
  - It is a standalone `Element`/`StyledElement`, not a generic modifier
    wrapper, and it registers a CSS node centred with
    `alignItems`/`justifyContent = .center`.
  - It is also a live registering site: `animated(...)` at `:40`,
    `registerHandlers` at `:48`, and `animatedBackground` plus `pass.fill` at
    `:55-57`.
  - Every `StyledElement` modifier compiles on it, and a later `.width(_:)`
    overwrites the frame's own size rather than nesting.
  - No per-conformer guard has an arm for it. `FrameModifier` and `.frame(width`
    appear in `Tests/` only in `ComponentTests.swift` and one overload test in
    `NativeLayoutIntegrationTests.swift`.
  - `StyledElement.padding` separately became an outer `Box<Self>` wrapper
    (`Box.swift:640-650`, commit `f1944f8`). `width`/`height` still mutate
    `Style` (`Box.swift:593-599`).
- **Proposal path: `ModifiedContent<Content: ProposalElementGroup>`**
  (`Sources/MetalUI/NativeModifiedContent.swift:31`), carrying one value of a
  **closed** `public enum LayoutModifier` (`:9-23`: frame, padding, fixedSize,
  aspectRatio, layoutPriority, background, clip, border, opacity,
  allowsHitTesting).
  - It has no modifier protocol, so callers cannot define a modifier.
  - `.overlay` and `.onTap` are separate wrapper types: `OverlayModifier`
    (`NativeOverlayModifier.swift:8`) and `OnTapModifier`
    (`NativeTappable.swift:8`).
  - None of these proposal wrappers calls `animated`, `animatedBackground` or
    `noteActiveAnimation`, so all of them snap under `withAnimation`.

## Problem

MetalUI's legacy modifiers usually return `Self` by mutating `Style`. That
matches CSS declarations, but not SwiftUI's ordered modifier wrappers. The
first direct conversion of `width` and `height` to `Box<Self>` exposed the
constraint: ordinary stored `Box<Text>` and other concrete generic trees no
longer typecheck when every chained modifier changes the outer type.

> *Unverified, 2026-09-14 (at `7cfcddc`).* No commit in history makes `width`
> or `height` return `Box<Self>`: `git log --all -G'func (width|height)\(.*\)
> -> Box'` finds nothing. This paragraph was written in `24da5ea` (00:54,
> 2026-09-12), before any committed width/height trial. The nearest committed
> shapes are `.frame(width:height:)` returning `Box<Self>` (`11ed79e`) and the
> later `width`/`height` → `FrameModifier<Self>` trial (`4aaca40`, reverted by
> `d0a04d3`). If the experiment described here happened, it was never
> committed, and the typecheck failure it names has no recorded output.

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

> *Superseded 2026-09-14 (at `7cfcddc`).* No `ElementModifier` protocol
> exists; see the Status paragraph. The placement categories hold as follows
> in the source.
>
> **Proposal path**
> - frame, padding, fixedSize, aspectRatio and layoutPriority register an
>   outer native node.
> - background, border, clip, opacity and allowsHitTesting wrap prepaint and
>   paint.
> - `.allowsHitTesting(false)` gates only `Frame.registerHandlers`' pointer
>   hitbox (`Frame.swift:655`). `registerScrollRegion` bypasses it
>   (`Frame.swift:501-503`), so a scroll view beneath it still takes the wheel.
>   That consequence is by reading and untested.
>
> **Legacy path**
> - `.frame` and `.padding` add a node and an identity level.
> - On a `Component`, `.frame` wraps the body in one node
>   (`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`), while
>   `.padding`/`.width`/`.height` still distribute through `StyledComponent`
>   (`Component.swift:391-452`).
> - The same `.padding` spelling therefore wraps and accumulates on an element
>   but distributes and replaces on a component. No SwiftUI probe for either
>   category is saved in the repository.

## First feature

Port `.frame(width:height:)` onto `ModifiedElement`, preserving its current
additive API and nested-order behavior. It will be tested with a stored,
concretely typed subtree so the regression that broke `Box<Text>` boundaries is
observable. No legacy `width` or `height` API changes in this feature.

> *Superseded 2026-09-14 (at `7cfcddc`).* Legacy `.frame(width:height:)` was
> not ported onto a generic wrapper. It went from `Box<Self>` (`11ed79e`) to a
> plain struct (`24da5ea`) to a `StyledElement` (`0b835b1`), which is today's
> `FrameModifier`.
>
> Its nesting is pinned by `chainedFramesRemainConcreteAndNestTheirLayoutNodes`
> (`ComponentTests.swift:637`), which is also its stored-concrete-subtree
> proof: it declares `let stored: FrameModifier<TwoLeaves>` and
> `var tree: Row<FrameModifier<FrameModifier<TwoLeaves>>>`, and its doc
> comment names the explicit stored type as the regression shape
> (`ComponentTests.swift:630-641`).
>
> `width`/`height` were briefly routed through it (`4aaca40`) and reverted 12
> minutes later (`d0a04d3`). They still mutate `Style`.

## Required proofs

- Two chained modifiers have two structural identities and preserve distinct
  `@State` slots.
- A stored concrete subtree still compiles after a modifier chain is added.
- The wrapper invokes child layout, prepaint and paint exactly once.
- Frame ordering changes the measured/placed result where SwiftUI does.
- Explicit `AnyElement` remains opt-in; no ordinary modifier path introduces it.
- Each claim is mutation-tested before its commit.

> *Status 2026-09-14 (at `7cfcddc`).* Proof by proof:
>
> 1. **Distinct `@State` across two chained modifiers: no test.**
>    `NativeLayoutIntegrationTests.swift` contains no `@State`.
>
>    The identity side has a known hazard. `OverlayModifier.requestLayout`
>    requests both groups `under: id` with independent cursors starting at 0
>    (`NativeOverlayModifier.swift:28-33`). Each group's element takes
>    `GlobalElementID.child(of: id, at: 0, …)` (`ElementGroup.swift:111`), so
>    by reading the primary element and the overlay element themselves share
>    one `GlobalElementID` unless one of them carries an `elementID`.
>
>    The legacy wrappers move the wrapped element one identity level down.
>    That puts it under a new path, so adding or removing `.padding`/`.frame`
>    re-seeds its `@State` and focus, and `.id(_:)` must be the outermost
>    modifier to name the wrapper's slot.
>
>    Neither consequence is pinned.
> 2. **A stored concrete subtree compiles after a modifier chain: partially.**
>    `ModifiedContent<ModifiedContent<T>>` stays concrete:
>    `nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder` stores
>    `var root: ModifiedContent<ModifiedContent<NativeProbeLeaf>>`
>    (`NativeLayoutIntegrationTests.swift:645-648`).
>    `proposalLayoutFrameUsesTheTypedProposalWrapper` stores only a
>    single-level `ModifiedContent<NativeProbeLeaf>` (`:666`).
>
>    The legacy `.padding` return-type change breaks
>    `Text(s).padding(4).font(...)`, because `font` and `foregroundColor` are
>    `Text`-only (`Text.swift:172, 182`). That follows from the signatures and
>    has not been compiled.
> 3. **The wrapper invokes child layout, prepaint and paint exactly once: no
>    call-count test** for a wrapper.
> 4. **Frame ordering changes the result where SwiftUI does: half.**
>    `chainedNativeFramesPreserveTheirDeclarationOrder`
>    (`NativeLayoutIntegrationTests.swift:736-760`) shows that declaration
>    order changes MetalUI's placement on the proposal path. It has no doc
>    comment and cites no SwiftUI probe, and no probe source is versioned, so
>    "where SwiftUI does" is unverified.
> 5. **No `AnyElement` on an ordinary modifier path:** true by reading. No
>    modifier in `NativeModifiedContent.swift`, `FrameModifier.swift` or
>    `Box.swift`'s padding constructs one.
> 6. **Mutation-tested before commit:** no mutation record exists for this
>    milestone.
