import MetalUICore
import MetalUILayout

/// The builder of a SwiftUI-vocabulary container's content: `ElementBuilder`,
/// plus one rule — proposal content keeps its type, and any other element,
/// group or `Component` is adopted as ``LegacyContent`` (ruling `PE-B`,
/// `docs/superpowers/2026-10-06-proposal-controls-decisions.md`).
///
/// ```swift
/// HStack { Spacer(); Rectangle() }      // HStack<Pair<Spacer, Rectangle>>
/// HStack { Text("Name"); TextField("Name", text: $name) }
///                                       // HStack<Pair<LegacyContent<Text>, LegacyContent<TextField>>>
/// ```
///
/// It takes the place of `@ElementBuilder` on `HStack`, `VStack`, `ZStack`,
/// `Grid`, `GridRow`, `ProposalScrollView`, `ProposalLayoutContainer` and
/// `ProposalLayout.callAsFunction` (ruling `PE-E`) — SwiftUI's `ViewBuilder`
/// role. The MetalUI-only native wrappers (`ProposalFrame`, `Padding`,
/// `Background`, `FixedSize`) keep `@ElementBuilder`, and with it the
/// `ProposalElementGroup` rejection.
///
/// **The wrapping is per expression statement**, so an `if`, `switch` or `for`
/// over legacy content wraps each branch's statements, and the builder products
/// (`Pair`, `OptionalGroup`, `EitherGroup`, `ArrayGroup`) stay the typed copies
/// every proposal container already reaches (`MC-H`). A `ForEach` is one
/// expression: a `ForEach` of legacy rows is adopted whole.
///
/// **The proposal overload must rank first**: `buildExpression` over
/// `ProposalElementGroup` is the plain overload and the `ElementGroup` one is
/// `@_disfavoredOverload`. Were the order lost, proposal content would be
/// wrapped too — the same nodes and ids, but the typed copies unreached. Pinned
/// by the type guard `proposalContentKeepsItsTypeAndLegacyContentIsAdopted`.
///
/// Every other method forwards to `ElementBuilder`'s, so the two builders cannot
/// drift and `StackMeter`'s samples (`PE-L` item 2) cover both.
@MainActor
@resultBuilder
public enum ProposalContentBuilder {
    /// Proposal content, unchanged: it keeps its type and its typed path.
    public static func buildExpression<Element: ProposalElementGroup>(_ element: Element) -> Element {
        element
    }

    /// Any other element, group or `Component`, adopted as ``LegacyContent``:
    /// an identity- and layout-transparent adapter over its native nodes
    /// (`PE-C`).
    @_disfavoredOverload
    public static func buildExpression<Group: ElementGroup>(_ group: Group) -> LegacyContent<Group> {
        LegacyContent(group)
    }

    /// `HStack { }` — no children. Forwards to `ElementBuilder.buildBlock()`.
    public static func buildBlock() -> EmptyGroup { ElementBuilder.buildBlock() }

    /// A block's first statement, unchanged. Forwards to `ElementBuilder`.
    public static func buildPartialBlock<Group: ElementGroup>(first: Group) -> Group {
        ElementBuilder.buildPartialBlock(first: first)
    }

    /// Folds the next statement onto the ones before it as a left-nested `Pair`,
    /// so node order is source order. Forwards to `ElementBuilder`.
    public static func buildPartialBlock<Accumulated: ElementGroup, Next: ElementGroup>(
        accumulated: Accumulated, next: Next
    ) -> Pair<Accumulated, Next> {
        ElementBuilder.buildPartialBlock(accumulated: accumulated, next: next)
    }

    /// `if` with no `else`: one structural slot (`ID-B`). Forwards to `ElementBuilder`.
    public static func buildOptional<Group: ElementGroup>(_ group: Group?) -> OptionalGroup<Group> {
        ElementBuilder.buildOptional(group)
    }

    /// The `if` branch of an `if`/`else` (or a `switch` case). Forwards to `ElementBuilder`.
    public static func buildEither<First: ElementGroup, Second: ElementGroup>(
        first: First
    ) -> EitherGroup<First, Second> {
        ElementBuilder.buildEither(first: first)
    }

    /// The `else` branch of an `if`/`else` (or a later `switch` case). Forwards
    /// to `ElementBuilder`.
    public static func buildEither<First: ElementGroup, Second: ElementGroup>(
        second: Second
    ) -> EitherGroup<First, Second> {
        ElementBuilder.buildEither(second: second)
    }

    /// `for … in …`: one structural slot. Forwards to `ElementBuilder`.
    ///
    /// **A loop body that calls a helper returning `some …` does not compile**
    /// ("underlying type for opaque result type … could not be inferred"): the
    /// Swift 6.4 builder transform types the loop's accumulator before this
    /// method is consulted, so no spelling of it can help (ruling `KF-M`,
    /// probe `docs/probes/swift-builder-for-opaque.sh`, guard
    /// `aForLoopOverAnOpaqueHelperIsAToolchainLimitation`). Write
    /// `ForEach(items, id: \.self) { helper($0) }`, a helper returning a
    /// concrete type, or the chain inline.
    public static func buildArray<Group: ElementGroup>(_ groups: [Group]) -> ArrayGroup<Group> {
        ElementBuilder.buildArray(groups)
    }
}

/// A legacy element, group or `Component` inside a SwiftUI-vocabulary container
/// — made by ``ProposalContentBuilder``, never written by hand (ruling `PE-C`,
/// `docs/superpowers/2026-10-06-proposal-controls-decisions.md`).
///
/// 1. **Identity-transparent.** Both entries hand the wrapped group the
///    caller's parent and cursor: no index, no level. A legacy control takes
///    exactly the id a proposal element in its position would (`MC-A`/`MC-C`,
///    the seven slots unchanged; `.id()` stays outermost, inside the adapter).
/// 2. **Layout-transparent, native.** The typed entry returns the wrapped
///    group's nodes as `ProposalNodeID`s — sound because every node is native
///    under the proposal authority (`LR-T`). It is the second minting site
///    inside `MetalUI` after the registrars (`ProposalNodeID.swift`'s header).
/// 3. **Drops presentation placeholders** (`LR-CK`): a `Deferred` presentation
///    in a stack takes no slot and no spacing.
/// 4. **Consumes no record** (`LR-AQ`): a legacy item field — `flexGrow`,
///    `margin`, `alignSelf`, `minSize`, … — on content in a proposal container
///    is reported `<site>.<field>.unconsumed` (a production trap). SwiftUI has
///    no flex item fields; its spellings are `.frame(maxWidth: .infinity)`,
///    `Spacer()` and `.layoutPriority`.
/// 5. **Registers nothing** — no hitbox, handler or lowering site: hit testing,
///    focus, accessibility, animation and drag previews are the legacy
///    element's own, in either vocabulary (`PE-I`).
public struct LegacyContent<Content: ElementGroup>: ProposalElementGroup {
    /// The adopted element, group or `Component`.
    public var content: Content

    /// Adopts `content`. ``ProposalContentBuilder`` calls this; a hand-written
    /// one is the same value.
    public init(_ content: Content) {
        self.content = content
    }

    /// The untyped entry (a legacy container or a root): the content's own,
    /// unchanged — a legacy collection site drops presentations itself.
    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Content.GroupLayout) {
        content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
    }

    /// The typed entry: the content's nodes, presentations dropped, minted as
    /// `ProposalNodeID`s (items 2–4 above).
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], Content.GroupLayout) {
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (pass.frame.lowering.droppingPresentations(nodes).map(ProposalNodeID.init), layout)
    }

    /// The content's prepaint, once.
    public mutating func prepaintGroup(layout: inout Content.GroupLayout,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout, pass: &pass)
    }

    /// The content's paint.
    public mutating func paintGroup(layout: inout Content.GroupLayout, prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}
