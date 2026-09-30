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
/// in paint so the two phases agree (1.8), and its content's layout.
public struct TransactionScopeLayout<ContentLayout> {
    var transaction: Transaction
    var content: ContentLayout
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
public struct TransactionScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let write: TransactionWrite

    init(content: Content, write: TransactionWrite) {
        self.content = content
        self.write = write
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], TransactionScopeLayout<Content.GroupLayout>) {
        let transaction = pass.frame.scopedTransaction(applying: write, under: parent, at: cursor)
        let (nodes, layout) = pass.frame.withTransactionScope(transaction) {
            content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        return (nodes, TransactionScopeLayout(transaction: transaction, content: layout))
    }

    public mutating func prepaintGroup(layout: inout TransactionScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // No push: nothing in prepaint reads the transaction.
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paintGroup(layout: inout TransactionScopeLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        // The transaction layout resolved, not the write run again: a value
        // compared twice would read "unchanged" in paint.
        pass.frame.withTransactionScope(layout.transaction) {
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        }
    }
}

/// **The typed entry is a line-for-line copy of the untyped one, pinned on its
/// own** (spec test 1.4's proposal arm): a copy of a pinned implementation is
/// unpinned.
extension TransactionScope: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], TransactionScopeLayout<Content.GroupLayout>) {
        let transaction = pass.frame.scopedTransaction(applying: write, under: parent, at: cursor)
        let (nodes, layout) = pass.frame.withTransactionScope(transaction) {
            content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        return (nodes, TransactionScopeLayout(transaction: transaction, content: layout))
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
        var transaction = transactionTop
        switch write {
        case .transform(let transform):
            transform(&transaction)
        case .animation(let animation, let value, let isEqual):
            let position = GlobalElementID.child(of: parent, at: cursor, name: nil)
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
