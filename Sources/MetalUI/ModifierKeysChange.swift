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
/// forwarded, no node, no `StateTable` slot. **Over a `StyledElement` it is a
/// `StyledElement`** (ruling `ES-D`): a `Self`-returning decoration written
/// after it lands on the content inside it, which the scope cannot see (it
/// reads none of its content's geometry); over other groups it still does not
/// compile.
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
            pass.frame.prepaintLog?.modifiers.append(ModifierNoteRecord(watch: watch, key: key, owner: owner))   // `RL-B`
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

// MARK: - Decorations chain through the scope (`ES-D`)

/// What a `ModifierKeysScope` over an `Element` carries on the `Element` path: its store key and owner (the
/// element's own id) and its content's layout.
public struct ModifierKeysScopeElementState<ContentState> {
    var content: ContentState
    var key: GlobalElementID
    var owner: GlobalElementID
}

/// `ES-D`: the scope over an element is an element (a window root, `Deferred` content, a `List` row), owning
/// its entry by the element's own id, and over a `StyledElement` a `StyledElement` forwarding to its content,
/// so a decoration written after it lands on the content inside it. The scope reads none of its content's
/// geometry or decoration, so where the decoration sits is unobservable to it. The group entry points above
/// are unchanged.
extension ModifierKeysScope: Element where Content: Element {
    public typealias LayoutState = ModifierKeysScopeElementState<Content.LayoutState>
    public typealias PrepaintState = Content.PrepaintState

    /// The content's name, so a scope entered as an element (erased in an `AnyElement`, say) is named as its
    /// content is (`ES-K`): without it `Element`'s default `nil` hid the name from `GlobalElementID.child`.
    public var elementID: ElementID? { content.elementID }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, ModifierKeysScopeElementState<Content.LayoutState>) {
        let store = pass.frame.animationStore.lifecycle
        let depth = store.modifierDepth
        let (node, state) = store.withModifierKeysScope { content.requestLayout(id, pass: &pass) }
        let key = GlobalElementID.child(of: id, at: 0, name: ElementID("$modkeys\(depth)"))
        return (node, ModifierKeysScopeElementState(content: state, key: key, owner: id))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout ModifierKeysScopeElementState<Content.LayoutState>,
                                  pass: inout PrepaintPass) -> Content.PrepaintState {
        pass.frame.prepaintLog?.modifiers.append(ModifierNoteRecord(watch: watch, key: layout.key, owner: layout.owner))   // `RL-B`
        pass.frame.animationStore.lifecycle.noteModifierKeys(watch: watch, key: layout.key, owner: layout.owner)
        return content.prepaint(id, bounds: bounds, layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout ModifierKeysScopeElementState<Content.LayoutState>,
                               prepaint: inout Content.PrepaintState, pass: inout PaintPass) {
        content.paint(id, bounds: bounds, layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension ModifierKeysScope: StyledElement where Content: StyledElement {
    public var style: Style {
        get { content.style }
        set { content.style = newValue }
    }
    public var decoration: Decoration {
        get { content.decoration }
        set { content.decoration = newValue }
    }
    public var elementID: ElementID? {
        get { content.elementID }
        set { content.elementID = newValue }
    }
    public var handlers: Handlers {
        get { content.handlers }
        set { content.handlers = newValue }
    }
}

extension ModifierKeysScope {
    /// Names the scope **together with** its content, not the content inside it (ruling `ES-C`, carried to
    /// this scope by `ES-D`). A `StyledElement` keeps its own `id(_:) -> Self`; forwarding that through the
    /// scope would name the content inside it. This member is the `ElementGroup` spelling, and it wins over the
    /// protocol extension's.
    public func id(_ name: String) -> IdentifiedGroup<Self> {
        IdentifiedGroup(content: self, name: ElementID(name))
    }
}
