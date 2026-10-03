import MetalUICore
import MetalUILayout

// Plan task 13, lane 3 — `.transition(_:)` (ruling `AN-AE` as amended by
// `AN-AH` item 4; spec §6.5). See `AnyTransition` for the supported surface.

/// A `TransitionGroup`'s layout: its store key when it claimed its position
/// (it is the outermost group of content a conditional or loop inserts or
/// removes), `nil` when it is inert, and its content's layout.
public struct TransitionGroupLayout<ContentLayout> {
    var key: GlobalElementID?
    var content: ContentLayout
}

/// `content` with a transition for when a conditional or loop inserts or
/// removes it — what `.transition(_:)` returns.
///
/// **Layout- and identity-TRANSPARENT** (`AN-AH` item 4), the shape of
/// `EnvironmentScope` and `TransactionScope`: `parent` and `cursor` are
/// forwarded unchanged, so adding or removing `.transition` moves no id and
/// resets no `@State`, focus or `$anim` baseline — SwiftUI's modifiers carry
/// no identity. Its bookkeeping lives in the window's `AnimationStore`'s
/// transition store under `.named("$transition")` at the position it sits at,
/// never in `StateTable`.
///
/// **Inert unless it is the outermost group of inserted content** — its parent
/// an `if`'s slot, an `if`/`else` branch, a `ForEach` element's scope or a
/// `for` loop's slot (X15, X15b, X16). A claimed group records its content's
/// nodes in layout and, in paint, applies the insertion's effect and captures
/// what its content emits for a ghost.
public struct TransitionGroup<Content: ElementGroup>: ElementGroup {
    var content: Content
    let transition: AnyTransition

    init(content: Content, transition: AnyTransition) {
        self.content = content
        self.transition = transition
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], TransitionGroupLayout<Content.GroupLayout>) {
        let key = pass.frame.claimTransition(transition, under: parent, at: cursor)
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        if let key { pass.frame.animationStore.transitions.setNodes(nodes, for: key) }
        return (nodes, TransitionGroupLayout(key: key, content: layout))
    }

    public mutating func prepaintGroup(layout: inout TransitionGroupLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // Nothing: hit testing, focus and accessibility use the final geometry.
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paintGroup(layout: inout TransitionGroupLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        guard let key = layout.key,
              let scope = pass.frame.animationStore.transitions.beginPaint(key, frame: pass.frame) else {
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
            return
        }
        pass.frame.paintScopes.append(scope)
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        pass.frame.paintScopes.removeLast()
        pass.frame.animationStore.transitions.endPaint(key, scope: scope)
    }
}

/// **The typed entry is a line-for-line copy of the untyped one, pinned on its
/// own** (spec test 3.20's proposal arm): a copy of a pinned implementation is
/// unpinned.
extension TransitionGroup: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], TransitionGroupLayout<Content.GroupLayout>) {
        let key = pass.frame.claimTransition(transition, under: parent, at: cursor)
        let (nodes, layout) = content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        if let key { pass.frame.animationStore.transitions.setNodes(nodes.map(\.layoutNodeID), for: key) }
        return (nodes, TransitionGroupLayout(key: key, content: layout))
    }
}

extension Frame {
    /// Claims `(parent, cursor)` for a group carrying `transition`, reading
    /// Reduce Motion at the group (`AN-AD`), and returns its store key — or
    /// `nil` when the group is inert.
    func claimTransition(_ transition: AnyTransition, under parent: GlobalElementID?,
                         at cursor: Int) -> GlobalElementID? {
        let key = TransitionStore.key(under: parent, at: cursor)
        let claimed = animationStore.transitions.claim(
            key: key, under: parent, at: cursor, transition: transition,
            reduceMotion: environmentTop.accessibilityReduceMotion)
        return claimed ? key : nil
    }

    /// The animation a conditional or loop records for its transitions: the
    /// transaction in effect at it, the lexical slot as a fallback — the same
    /// order every helper reads (`AN-AI` item 4).
    var conditionalAnimation: Animation? {
        transactionTop.animation ?? Animation.pendingTransaction
    }
}

extension ElementGroup {
    /// How this group enters when a conditional or loop inserts it and leaves
    /// when one removes it (SwiftUI's `transition(_:)`). Applies only when this
    /// group IS the content an `if`, `if`/`else`, `switch`, `ForEach` or `for`
    /// produces; nested deeper it does nothing. See ``AnyTransition`` for the
    /// supported transitions, the animation it runs on, Reduce Motion, and what
    /// is not supported.
    public func transition(_ transition: AnyTransition) -> TransitionGroup<Self> {
        TransitionGroup(content: self, transition: transition)
    }
}
