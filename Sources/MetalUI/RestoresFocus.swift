import MetalUICore
import MetalUILayout

// MARK: - `restoresFocusOnDismiss()` (ruling `KF-AM`) and a popover's implicit scope (`MN-AS`)
//
// One transparent scope, `RestoresFocusScope`, `PresentationScope`'s shape: layout- and identity-transparent, no
// `@State` move. Layout only gives it a key (its position); prepaint pushes the key onto the frame's scope stack, so
// every focusable registered under it names it (`FocusRegistry.scopeChain(of:)`). The window keeps the records
// (`Window.restoreRecords`); the frame restores at the two places it drops focus (`Frame.dropFocus`).

/// Where a restoring scope sits: the position it was written at, plus how many restoring scopes were open around it in
/// layout (stacked modifiers share a position). A popover's implicit scope is keyed by its modifier's id with `at: -1`.
struct RestoreScopeKey: Hashable {
    var owner: GlobalElementID?
    var at: Int
    var depth: Int
}

/// What a window hands a frame so it can restore focus at a drop (`KF-AM`): the focused element's scopes at hand-in
/// (innermost first) and the records of every live scope. `nil` on a frame of a window with no scope.
struct RestoreInput {
    var chain: [RestoreScopeKey]
    var records: [RestoreScopeKey: GlobalElementID]
}

/// A `RestoresFocusScope`'s layout: its content's, and the scope's key.
public struct RestoresFocusScopeLayout<ContentLayout> {
    var content: ContentLayout
    var key: RestoreScopeKey?
}

/// `content` that returns keyboard focus to the element focused when focus entered it, once the focused element inside
/// it is dropped because the content went away — what `.restoresFocusOnDismiss(_:)` returns (ruling `KF-AM`).
///
/// **Transparent**: no layout node, no identity level; adding or removing the modifier moves no `@State`, focus or
/// animation baseline. Presented popovers are such scopes already (ruling `MN-AS`).
///
/// **A `Self`-returning decoration written after this scope over a `StyledElement` compiles and lands on the content**
/// (ruling `ES-A`); over other groups it still does not.
public struct RestoresFocusScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let enabled: Bool

    init(content: Content, enabled: Bool) {
        self.content = content
        self.enabled = enabled
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], RestoresFocusScopeLayout<Content.GroupLayout>) {
        let key = pass.frame.openRestoreScopeKey(owner: parent, at: cursor, enabled: enabled)
        defer { if enabled { pass.frame.closeRestoreScopeLayout() } }
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, RestoresFocusScopeLayout(content: layout, key: key))
    }

    public mutating func prepaintGroup(layout: inout RestoresFocusScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        pass.frame.withRestoreScope(layout.key) { content.prepaintGroup(layout: &layout.content, pass: &pass) }
    }

    public mutating func paintGroup(layout: inout RestoresFocusScopeLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension RestoresFocusScope: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], RestoresFocusScopeLayout<Content.GroupLayout>) {
        let key = pass.frame.openRestoreScopeKey(owner: parent, at: cursor, enabled: enabled)
        defer { if enabled { pass.frame.closeRestoreScopeLayout() } }
        let (nodes, layout) = content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, RestoresFocusScopeLayout(content: layout, key: key))
    }
}

/// `ES-A`: the scope is an element when its content is.
extension RestoresFocusScope: Element where Content: Element {
    public typealias LayoutState = Content.LayoutState
    public typealias PrepaintState = Content.PrepaintState

    /// The content's name (`ES-K`).
    public var elementID: ElementID? { content.elementID }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Content.LayoutState) {
        // The element form keys on its own id: `at: -2` keeps it apart from a popover's `-1`.
        _ = pass.frame.openRestoreScopeKey(owner: id, at: -2, enabled: enabled)
        defer { if enabled { pass.frame.closeRestoreScopeLayout() } }
        return content.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Content.LayoutState, pass: inout PrepaintPass) -> Content.PrepaintState {
        let key = enabled ? pass.frame.restoreKey(owner: id, at: -2) : nil
        return pass.frame.withRestoreScope(key) { content.prepaint(id, bounds: bounds, layout: &layout, pass: &pass) }
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Content.LayoutState, prepaint: inout Content.PrepaintState,
                               pass: inout PaintPass) {
        content.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension RestoresFocusScope: StyledElement where Content: StyledElement {
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

extension RestoresFocusScope {
    /// Names the scope together with its content (ruling `ES-C`), as `PresentationScope` does.
    public func id(_ name: String) -> IdentifiedGroup<Self> {
        IdentifiedGroup(content: self, name: ElementID(name))
    }
}

extension ElementGroup {
    /// Returns focus to the element that was focused when focus entered this content, when the focused element inside
    /// it goes away because the content does (ruling `KF-AM`).
    ///
    /// SwiftUI has no such modifier (`focusScope` and `resetFocus` re-evaluate default focus; they do not return to
    /// the previous element), so this is a MetalUI addition, the in-tree counterpart of what a popover or sheet window
    /// does for free. **Recording**: when focus moves from outside the content to an element inside it, the scope
    /// remembers the element focused before; focus leaving the content any other way forgets it. **Restoring**: when
    /// the focused element is dropped (an `if` removed it, a `.id` departed) and the scope itself was not produced in
    /// that frame, focus moves to the remembered element if it is focusable then, one extra frame later painting its
    /// ring; if something else took focus that frame there is nothing to restore, and if the remembered element is gone
    /// focus is `nil`, as today. Removing only the element while the scope stays keeps the drop to `nil`. Nested scopes
    /// restore the innermost. Transparent: no node, no identity level.
    ///
    /// - Parameter enabled: `false` makes the modifier inert, so a condition needs no `if`.
    public func restoresFocusOnDismiss(_ enabled: Bool = true) -> RestoresFocusScope<Self> {
        RestoresFocusScope(content: self, enabled: enabled)
    }
}

// MARK: - Frame side

extension Frame {
    /// Layout: the key of a scope opening at `(owner, at)`, one level deeper than the scopes open around it; `nil` (and
    /// no depth change) when the scope is disabled.
    func openRestoreScopeKey(owner: GlobalElementID?, at: Int, enabled: Bool) -> RestoreScopeKey? {
        guard enabled else { return nil }
        defer { restoreLayoutDepth += 1 }
        return RestoreScopeKey(owner: owner, at: at, depth: restoreLayoutDepth)
    }

    func closeRestoreScopeLayout() { restoreLayoutDepth -= 1 }

    /// The key the layout of an element-form scope gave itself: its depth is the number of scopes open in prepaint.
    func restoreKey(owner: GlobalElementID?, at: Int) -> RestoreScopeKey {
        RestoreScopeKey(owner: owner, at: at, depth: restoreScopeStack.count)
    }
}
