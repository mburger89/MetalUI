import MetalUICore
import MetalUILayout

// MARK: - `onModifierKeysChanged(mask:initial:_:)` (ruling `IF-D`)
//
// One transparent scope, `ModifierKeysScope`, the shape of `GeometryChangeScope`
// (`KF-J`): in layout it records its position key and its content's nodes; in
// PREPAINT it notes the window's held modifiers, masked, into the window's
// `LifecycleStore`, whose `endFrame` turns a new or changed value into an event
// that `Window.drainLifecycle` runs after the build, under `StateDispatch`.
// Nothing runs in a phase. The contract is MetalUI's own: SwiftUI's timing was
// not measured (`IF-D` finding, human check IF1).

/// What one `ModifierKeysScope` watches.
struct ModifierKeysWatch {
    let mask: EventModifiers
    let initial: Bool
    let action: (EventModifiers, EventModifiers) -> Void
}

/// A `ModifierKeysScope`'s layout: its content's, the content's nodes and the
/// scope's store key (`nil` when the content registered nothing).
public struct ModifierKeysScopeLayout<ContentLayout> {
    var content: ContentLayout
    var key: GlobalElementID?
    var owner: GlobalElementID?

    /// The store key and owner of a scope at `cursor` under `parent`: the owner
    /// — which the action is dispatched to — is the position; the key is
    /// `.named("$modkeys<depth>")` under it, `depth` the modifier scopes
    /// enclosing this one. A store key, never a `StateTable` id (no reserved
    /// name, no `noteNamed`).
    static func key(under parent: GlobalElementID?, at cursor: Int,
                    depth: Int) -> (GlobalElementID?, GlobalElementID?) {
        let owner = GlobalElementID.child(of: parent, at: cursor, name: nil)
        return (GlobalElementID.child(of: owner, at: 0, name: ElementID("$modkeys\(depth)")), owner)
    }
}

/// `content` with a modifier-keys action — what `onModifierKeysChanged(mask:
/// initial:_:)` returns (ruling `IF-D`).
///
/// **Transparent** like `GeometryChangeScope`: `parent` and `cursor` are
/// forwarded, no node, no `StateTable` slot. **A `Self`-returning decoration
/// written after this scope does not compile** (divergence 120): write it
/// first.
public struct ModifierKeysScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let watch: ModifierKeysWatch

    init(content: Content, watch: ModifierKeysWatch) {
        self.content = content
        self.watch = watch
    }

    /// Lays the content out with the caller's parent and cursor.
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], ModifierKeysScopeLayout<Content.GroupLayout>) {
        let start = cursor
        let store = pass.frame.animationStore.lifecycle
        let depth = store.modifierDepth
        let (nodes, layout) = store.withModifierKeysScope {
            content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        let (key, owner) = nodes.isEmpty ? (nil, nil) : ModifierKeysScopeLayout<Content.GroupLayout>
            .key(under: parent, at: start, depth: depth)
        return (nodes, ModifierKeysScopeLayout(content: layout, key: key, owner: owner))
    }

    /// Prepaints the content, noting the masked modifiers.
    public mutating func prepaintGroup(layout: inout ModifierKeysScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        if let key = layout.key, let owner = layout.owner {
            pass.frame.animationStore.lifecycle.noteModifierKeys(watch: watch, key: key, owner: owner)
        }
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    /// Paints the content unchanged.
    public mutating func paintGroup(layout: inout ModifierKeysScopeLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension ModifierKeysScope: ProposalElementGroup where Content: ProposalElementGroup {
    /// The typed entry: a line-for-line copy of the untyped one.
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], ModifierKeysScopeLayout<Content.GroupLayout>) {
        let start = cursor
        let store = pass.frame.animationStore.lifecycle
        let depth = store.modifierDepth
        let (nodes, layout) = store.withModifierKeysScope {
            content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        let (key, owner) = nodes.isEmpty ? (nil, nil) : ModifierKeysScopeLayout<Content.GroupLayout>
            .key(under: parent, at: start, depth: depth)
        return (nodes, ModifierKeysScopeLayout(content: layout, key: key, owner: owner))
    }
}

extension ElementGroup {
    /// Runs `action` with the old and the new modifier keys held, `mask`ed, each
    /// time they change (SwiftUI's `onModifierKeysChanged(mask:initial:_:)`,
    /// macOS 15; ruling `IF-D`). Fires also while the pointer is still: a hover
    /// that reads what the action wrote sees ⌘ pressed with no move.
    ///
    /// The window owns the modifiers: it takes them from every key, pointer and
    /// scroll event and from the platform's flags-changed report, and drops them
    /// when it stops being key (reported as a change). `initial: true` reports
    /// `([], held & mask)` at the scope's first presented frame **when that is
    /// not empty**; `initial: false` stores it silently. The action runs after
    /// the build, outside every phase; a write it makes is in the frame that
    /// presents. SwiftUI's own timing and empty-first-report behaviour are
    /// unmeasured (human check IF1).
    public func onModifierKeysChanged(mask: EventModifiers = [.shift, .control, .option, .command],
                                      initial: Bool = true,
                                      _ action: @escaping (_ old: EventModifiers,
                                                           _ new: EventModifiers) -> Void)
        -> ModifierKeysScope<Self> {
        ModifierKeysScope(content: self, watch: ModifierKeysWatch(mask: mask, initial: initial, action: action))
    }
}
