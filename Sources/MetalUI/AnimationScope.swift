import MetalUICore
import MetalUILayout

// MARK: - `.animation(_:value:)` and `.transaction(_:)` (plan task 13, ruling `AN-Y`)
//
// Probe `docs/probes/swiftui-transactions-animation.swift`, arms T1–T8. Both
// return one `TransactionScope`: layout- and identity-TRANSPARENT, the shape of
// `EnvironmentScope` (SwiftUI's modifiers carry no identity, so adding or
// removing one resets nothing below it), pushing its resolved transaction
// around its content in layout and in paint — the two phases a helper reads it
// in — and popping after. Prepaint pushes nothing. A sibling and a modifier
// written after the scope are outside it (T3, T3b; `EV-X`'s rule).

/// What a `TransactionScope` does to the transaction it inherits.
enum TransactionWrite {
    /// `.transaction(_:)`: the closure, run on a copy of the inherited
    /// transaction every frame — root animation or not (T6, T7, T7c).
    case transform((inout Transaction) -> Void)
    /// `.animation(_:value:)`: override the inherited animation with
    /// `animation` when `value` changed since last frame and animations are
    /// not disabled (T1, T2, T4, T4n, T8, T8b).
    case animation(Animation?, value: Any, isEqual: (Any) -> Bool)
}

/// A `TransactionScope`'s layout: the transaction layout resolved, re-pushed
/// in paint so the two phases agree (1.8), and its content's layout — or, for
/// a scope with a decoration written after it (ruling `ES-H`), the layout of the
/// one legacy layer that wraps the undecorated scope.
public struct TransactionScopeLayout<ContentLayout> {
    var transaction: Transaction
    var content: ContentLayout?
    var layered: Any?
}

/// `content` under a transaction of its own — what `.animation(_:value:)` and
/// `.transaction(_:)` return (ruling `AN-Y`).
///
/// **Transparent**: `parent` and `cursor` are forwarded unchanged, so the
/// content keeps the ids it would have without the scope and no `@State`,
/// focus or `$anim` baseline moves when a scope is added or removed.
/// `.animation(_:value:)`'s previous value lives in the window's
/// `AnimationStore`, keyed by the position the scope sits at
/// (`.child(of: parent, at: cursor)`) and the transaction-stack depth — never
/// in `StateTable` (1.12).
///
/// **A `Self`-returning decoration written after it sits outside the
/// transaction** (ruling `ES-H`, lifting `ES-G`): over a `StyledElement` the
/// scope is a `StyledElement` whose accessors read and write one legacy layer
/// of its own (`outer`, a `.padding(0)` layer), created by the first decoration
/// written after it. A decorated scope lays out, prepaints and paints as
/// `ModifiedElement<Self>` over the undecorated scope — exactly
/// `.animation(_:value:).padding(0).background(...)` — so the layer's animated
/// style and colours are resolved before the scope pushes its transaction and
/// after it pops: a `.background` after `.animation(_:value:)` snaps while the
/// content inside animates, as SwiftUI's T3b. Forwarding the decoration onto the
/// content instead animated it (record 168). The layer is one node and one
/// identity level, present whenever a decoration is written after the scope.
public struct TransactionScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let write: TransactionWrite
    /// The legacy layer a decoration written after the scope configures; `nil`
    /// until one is (ruling `ES-H`).
    var outer: ModifierLayer?

    init(content: Content, write: TransactionWrite) {
        self.content = content
        self.write = write
        self.outer = nil
    }

    /// `body` run on the decorated form, `ModifiedElement<Self>` over this scope
    /// without its layer, and what it changed written back (a layer stores its
    /// animated style in layout, which later phases read).
    private mutating func withLayer<R>(_ body: (inout ModifiedElement<Self>) -> R) -> R {
        var bare = self
        bare.outer = nil
        var layered = ModifiedElement(content: bare, layer: outer ?? ModifierLayer(style: Style()))
        defer {
            content = layered.content.content
            outer = layered.outermost
        }
        return body(&layered)
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], TransactionScopeLayout<Content.GroupLayout>) {
        if outer != nil {
            let (nodes, layout) = withLayer { $0.requestGroupLayout(under: parent, at: &cursor, pass: &pass) }
            return (nodes, TransactionScopeLayout(transaction: pass.frame.transactionTop, content: nil, layered: layout))
        }
        let transaction = pass.frame.scopedTransaction(applying: write, under: parent, at: cursor)
        let (nodes, layout) = pass.frame.withTransactionScope(transaction) {
            content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        return (nodes, TransactionScopeLayout(transaction: transaction, content: layout, layered: nil))
    }

    public mutating func prepaintGroup(layout: inout TransactionScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        if var layered = layout.layered as? SingleElementLayout<ModifiedElement<Self>> {
            defer { layout.layered = layered }
            return withLayer { $0.prepaintGroup(layout: &layered, pass: &pass) }
        }
        // No push: nothing in prepaint reads the transaction.
        return content.prepaintGroup(layout: &layout.content!, pass: &pass)
    }

    public mutating func paintGroup(layout: inout TransactionScopeLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        if var layered = layout.layered as? SingleElementLayout<ModifiedElement<Self>> {
            defer { layout.layered = layered }
            withLayer { $0.paintGroup(layout: &layered, prepaint: &prepaint, pass: &pass) }
            return
        }
        // The transaction layout resolved, not the write run again: a value
        // compared twice would read "unchanged" in paint.
        pass.frame.withTransactionScope(layout.transaction) {
            content.paintGroup(layout: &layout.content!, prepaint: &prepaint, pass: &pass)
        }
    }
}

/// **The typed entry is a line-for-line copy of the untyped one, pinned on its
/// own** (spec test 1.4's proposal arm): a copy of a pinned implementation is
/// unpinned. A decoration can be written after the scope only over a
/// `StyledElement`, which is never proposal content, so a decorated scope takes
/// the untyped entry's layer path (`ES-H`).
extension TransactionScope: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], TransactionScopeLayout<Content.GroupLayout>) {
        if outer != nil {
            let (nodes, layout) = requestGroupLayout(under: parent, at: &cursor, pass: &pass)
            return (nodes.map(ProposalNodeID.init), layout)
        }
        let transaction = pass.frame.scopedTransaction(applying: write, under: parent, at: cursor)
        let (nodes, layout) = pass.frame.withTransactionScope(transaction) {
            content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        return (nodes, TransactionScopeLayout(transaction: transaction, content: layout, layered: nil))
    }
}

// MARK: - Decorations after the scope sit outside the transaction (`ES-H`)

/// `ES-H`: the scope over an element is an element (a window root, `Deferred` content, a `List` row) — its
/// transaction resolved at the element's own id and pushed around the content's layout and paint — and over a
/// `StyledElement` a `StyledElement` whose accessors configure the scope's own layer, outside the transaction. A
/// decorated scope on this path is its layer as an element over the undecorated scope as that layer's content.
extension TransactionScope: Element where Content: Element {
    public typealias LayoutState = ScopeLayerState<TransactionScopeLayout<Content.LayoutState>>
    public typealias PrepaintState = ScopeLayerState<Content.PrepaintState>

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, ScopeLayerState<TransactionScopeLayout<Content.LayoutState>>) {
        if outer != nil {
            let (node, layout) = withLayer { $0.requestLayout(id, pass: &pass) }
            return (node, ScopeLayerState(plain: nil, layered: layout))
        }
        let transaction = pass.frame.scopedTransaction(applying: write, at: id)
        let (node, state) = pass.frame.withTransactionScope(transaction) {
            content.requestLayout(id, pass: &pass)
        }
        return (node, ScopeLayerState(plain: TransactionScopeLayout(transaction: transaction, content: state,
                                                                    layered: nil),
                                      layered: nil))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout ScopeLayerState<TransactionScopeLayout<Content.LayoutState>>,
                                  pass: inout PrepaintPass) -> ScopeLayerState<Content.PrepaintState> {
        if var layered = layout.layered as? ModifiedElement<Self>.Layout {
            defer { layout.layered = layered }
            let inner = withLayer { $0.prepaint(id, bounds: bounds, layout: &layered, pass: &pass) }
            return ScopeLayerState(plain: nil, layered: inner)
        }
        // No push: nothing in prepaint reads the transaction.
        let state = content.prepaint(id, bounds: bounds, layout: &layout.plain!.content!, pass: &pass)
        return ScopeLayerState(plain: state, layered: nil)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout ScopeLayerState<TransactionScopeLayout<Content.LayoutState>>,
                               prepaint: inout ScopeLayerState<Content.PrepaintState>, pass: inout PaintPass) {
        if var layered = layout.layered as? ModifiedElement<Self>.Layout,
           var inner = prepaint.layered as? Content.GroupPrepaint {
            defer { layout.layered = layered; prepaint.layered = inner }
            withLayer { $0.paint(id, bounds: bounds, layout: &layered, prepaint: &inner, pass: &pass) }
            return
        }
        pass.frame.withTransactionScope(layout.plain!.transaction) {
            content.paint(id, bounds: bounds, layout: &layout.plain!.content!, prepaint: &prepaint.plain!, pass: &pass)
        }
    }
}

extension TransactionScope: StyledElement where Content: StyledElement {
    public var style: Style {
        get { outer?.style ?? Style() }
        set { configureLayer { $0.style = newValue } }
    }
    public var decoration: Decoration {
        get { outer?.decoration ?? Decoration() }
        set { configureLayer { $0.decoration = newValue } }
    }
    public var elementID: ElementID? {
        get { outer?.elementID }
        set { configureLayer { $0.elementID = newValue } }
    }
    public var handlers: Handlers {
        get { outer?.handlers ?? Handlers() }
        set { configureLayer { $0.handlers = newValue } }
    }
}

extension TransactionScope {
    /// Writes the scope's own layer, creating it (a `.padding(0)` layer) on the
    /// first decoration written after the scope (`ES-H`).
    mutating func configureLayer(_ change: (inout ModifierLayer) -> Void) {
        var layer = outer ?? ModifierLayer(style: Style())
        change(&layer)
        outer = layer
    }

    /// Names the scope **together with** its content and layer (ruling `ES-C`,
    /// carried by `ES-H`): this member wins over `StyledElement`'s own
    /// `id(_:) -> Self`, which would name the layer only.
    public func id(_ name: String) -> IdentifiedGroup<Self> {
        IdentifiedGroup(content: self, name: ElementID(name))
    }
}

extension Frame {
    /// A scope's transaction: `write` applied to a copy of the current top.
    /// Called once per scope per frame, in layout.
    ///
    /// `.animation(_:value:)` compares `value` with the one stored at its key
    /// last frame; **a first sighting stores and does not animate**. The key is
    /// `.named("$anim-value<depth>")` under `.child(of: parent, at: cursor)` —
    /// the position the scope sits at, which is its content's first position,
    /// and the depth of the transaction stack there, so two scopes nested at
    /// one position keep separate values (1.11). An `AnimationStore` key, not a
    /// `StateTable` one: no reserved name and no table entry.
    func scopedTransaction(applying write: TransactionWrite,
                           under parent: GlobalElementID?, at cursor: Int) -> Transaction {
        scopedTransaction(applying: write, at: GlobalElementID.child(of: parent, at: cursor, name: nil))
    }

    /// `scopedTransaction(applying:under:at:)` keyed at `position` itself — the
    /// `Element` path's (`ES-H`), where the scope is the element at `position`.
    func scopedTransaction(applying write: TransactionWrite, at position: GlobalElementID) -> Transaction {
        var transaction = transactionTop
        switch write {
        case .transform(let transform):
            transform(&transaction)
        case .animation(let animation, let value, let isEqual):
            let key = GlobalElementID.child(of: position, at: 0,
                                            name: ElementID("$anim-value\(transactionDepth)"))
            let changed = animationStore.value(at: key).map { !isEqual($0) } ?? false
            animationStore.set(value, at: key)
            if changed && !transaction.disablesAnimations {
                transaction.animation = animation
            }
        }
        return transaction
    }
}

extension ElementGroup {
    /// Animates a change under this group with `animation` when `value`
    /// changed since the last frame — with or without a `withAnimation` —
    /// and leaves every other change as it would be (SwiftUI's
    /// `animation(_:value:)`; T1, T2). Overrides an explicit transaction's
    /// animation below it (T4; `nil` snaps, T4n) and is suppressed by
    /// `disablesAnimations` (T8, T8b). Reaches only this group: a sibling and
    /// a modifier written after it are outside (T3, T3b).
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> TransactionScope<Self> {
        TransactionScope(content: self,
                         write: .animation(animation, value: value,
                                           isEqual: { ($0 as? V) == value }))
    }

    /// Rewrites the transaction this group's changes happen under — every
    /// frame, whether or not anything set one (SwiftUI's `transaction(_:)`;
    /// T6, T7, T7c). `{ $0.animation = nil }` snaps the group; `{ $0.animation
    /// = .linear(duration: 1) }` animates any change in it.
    public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> TransactionScope<Self> {
        TransactionScope(content: self, write: .transform(transform))
    }
}
