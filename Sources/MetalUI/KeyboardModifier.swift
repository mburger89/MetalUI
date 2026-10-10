import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform

// Key and focus scoping, lane C (rulings `KF-H`, `KF-W` item 1; spec
// `docs/superpowers/specs/2026-10-08-key-focus-design.md` §3.1, §4.4). The
// proposal path's keyboard modifiers — what a `MetalView`, a `GPUSurface` or
// any other proposal content writes to take focus and hear keys. Every one of
// them wraps once in a `KeyboardModifier`, and on a `KeyboardModifier` the same
// names return `Self`, so a chain of keyboard modifiers is **one layer and one
// id**: focusability, the focus binding, the key context and the handlers all
// sit on the focus target, as they do on a `StyledElement` (`KF-H` item 2).

extension ProposalElementGroup {
    /// Wraps this content once in a `KeyboardModifier` with `change` applied to
    /// its keyboard handlers.
    private func keyboardLayer(_ change: (inout Handlers) -> Void) -> KeyboardModifier<Self> {
        var handlers = Handlers()
        change(&handlers)
        return KeyboardModifier(content: self, handlers: handlers)
    }

    /// `StyledElement.onKeyPress(_:action:)` on the proposal path: wraps once
    /// in a `KeyboardModifier` (ruling `KF-H` item 1). A later keyboard
    /// modifier joins the same layer.
    public func onKeyPress(_ key: KeyEquivalent,
                           action: @escaping @MainActor () -> KeyPress.Result) -> KeyboardModifier<Self> {
        keyboardLayer { _ in }.onKeyPress(key, action: action)
    }

    /// `StyledElement.onKeyPress(_:phases:action:)` on the proposal path: wraps
    /// once in a `KeyboardModifier`.
    public func onKeyPress(_ key: KeyEquivalent, phases: KeyPress.Phases,
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> KeyboardModifier<Self> {
        keyboardLayer { _ in }.onKeyPress(key, phases: phases, action: action)
    }

    /// `StyledElement.onKeyPress(keys:phases:action:)` on the proposal path:
    /// wraps once in a `KeyboardModifier`.
    public func onKeyPress(keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> KeyboardModifier<Self> {
        keyboardLayer { _ in }.onKeyPress(keys: keys, phases: phases, action: action)
    }

    /// `StyledElement.onKeyPress(characters:phases:action:)` on the proposal
    /// path: wraps once in a `KeyboardModifier`.
    public func onKeyPress(characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> KeyboardModifier<Self> {
        keyboardLayer { _ in }.onKeyPress(characters: characters, phases: phases, action: action)
    }

    /// `StyledElement.onKeyPress(phases:action:)` on the proposal path: wraps
    /// once in a `KeyboardModifier`.
    public func onKeyPress(phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> KeyboardModifier<Self> {
        keyboardLayer { _ in }.onKeyPress(phases: phases, action: action)
    }

    /// `StyledElement.focusable(_:)` on the proposal path: wraps once in a
    /// `KeyboardModifier`, which is then the focus target (Tab reaches it; a
    /// click does not focus it — divergence 94).
    public func focusable(_ isFocusable: Bool = true) -> KeyboardModifier<Self> {
        keyboardLayer { _ in }.focusable(isFocusable)
    }

    /// `StyledElement.focusable(_:interactions:)` on the proposal path: wraps
    /// once in a `KeyboardModifier`. `.edit` makes a primary press focus it —
    /// the spelling for a `MetalView` viewport or a canvas (`KF-F`, `KF-H`).
    public func focusable(_ isFocusable: Bool = true,
                          interactions: FocusInteractions) -> KeyboardModifier<Self> {
        keyboardLayer { _ in }.focusable(isFocusable, interactions: interactions)
    }

    /// `StyledElement.keyContext(_:_:)` on the proposal path: wraps once in a
    /// `KeyboardModifier` contributing the context for it and its subtree.
    public func keyContext(_ name: String, _ values: [String: String] = [:]) -> KeyboardModifier<Self> {
        keyboardLayer { _ in }.keyContext(name, values)
    }

    /// `StyledElement.focused(_:)` on the proposal path: wraps once in a
    /// `KeyboardModifier` and binds its focus — the layer's own id, the one
    /// `focusable` makes focusable when both are written (`KF-H` item 2).
    public func focused(_ condition: FocusState<Bool>.Binding) -> KeyboardModifier<Self> {
        keyboardLayer { _ in }.focused(condition)
    }

    /// `StyledElement.focused(_:equals:)` on the proposal path: wraps once in a
    /// `KeyboardModifier` and binds its focus to `value`.
    public func focused<Value: Hashable>(_ binding: FocusState<Value>.Binding,
                                         equals value: Value) -> KeyboardModifier<Self> {
        keyboardLayer { _ in }.focused(binding, equals: value)
    }

    /// `StyledElement.hoverKeyRegion(_:)` on the proposal path: wraps once in a
    /// `KeyboardModifier` that is a key region (MetalUI-only, `KF-E`).
    public func hoverKeyRegion(_ isEnabled: Bool = true) -> KeyboardModifier<Self> {
        keyboardLayer { _ in }.hoverKeyRegion(isEnabled)
    }
}

/// A proposal wrapper carrying keyboard modifiers — what the proposal
/// `.onKeyPress(…)`, `.focusable(…)`, `.keyContext(_:_:)`, `.focused(…)` and
/// `.hoverKeyRegion(_:)` return (ruling `KF-H`). MetalUI-only as a type
/// (SwiftUI returns `some View`).
///
/// `HoverModifier`'s recipe: no layout node of its own, its one child numbered
/// from 0 under its id, **one identity level** for its caller. It registers
/// one set of handlers at its own bounds through the one gate
/// (`Frame.registerHandlers`): `.disabled(true)` and `.hidden()` withdraw all
/// of it, `.allowsHitTesting(false)` withdraws the press and key regions only.
///
/// **On a `KeyboardModifier` every keyboard modifier returns `Self`** (`KF-H`
/// item 2): `MetalView { … }.focusable(interactions: .edit).keyContext("V")
/// .onKeyPress("f") { … }` is one `KeyboardModifier<MetalView>`, one layer and
/// one id — focusability, the focus binding, the context and the handlers all
/// on the focus target. On that one layer `onKeyPress` and `.focusable()` are
/// order-free (divergence 185: SwiftUI's `onKeyPress` written inside
/// `.focusable()` never hears). Any other modifier between two keyboard
/// modifiers (`.padding`, `.frame`) starts a new layer, and the inner layer is
/// then a descendant of the outer one.
public struct KeyboardModifier<Content: ProposalElementGroup>: Element {
    /// The wrapped proposal content.
    public var content: Content
    var handlers: Handlers

    init(content: Content, handlers: Handlers) {
        self.content = content
        self.handlers = handlers
    }

    /// A copy with `change` applied to the layer's handlers.
    private func handling(_ change: (inout Handlers) -> Void) -> Self {
        var copy = self
        change(&copy.handlers)
        return copy
    }

    private func addingKeyPress(_ phases: KeyPress.Phases, _ filter: KeyPressHandler.Filter,
                                _ action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        handling {
            $0.keyboard = KeyboardAttachment.adding(KeyPressHandler(phases: phases, filter: filter, action: action),
                                                    to: $0.keyboard)
        }
    }

    /// Adds an `onKeyPress(_:action:)` handler to this layer — `Self`, so the
    /// chain stays one layer (`KF-H` item 2). On one layer the later-written
    /// handler runs first (K2w).
    public func onKeyPress(_ key: KeyEquivalent, action: @escaping @MainActor () -> KeyPress.Result) -> Self {
        addingKeyPress([.down, .repeat], .key(key)) { _ in action() }
    }

    /// Adds an `onKeyPress(_:phases:action:)` handler to this layer.
    public func onKeyPress(_ key: KeyEquivalent, phases: KeyPress.Phases,
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .key(key), action)
    }

    /// Adds an `onKeyPress(keys:phases:action:)` handler to this layer.
    public func onKeyPress(keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .keys(keys), action)
    }

    /// Adds an `onKeyPress(characters:phases:action:)` handler to this layer.
    public func onKeyPress(characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .characters(characters), action)
    }

    /// Adds an `onKeyPress(phases:action:)` handler to this layer.
    public func onKeyPress(phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .any, action)
    }

    /// Makes this layer focusable (or not) with the automatic interactions —
    /// `StyledElement.focusable(_:)`'s rules. A later `focusable` replaces it.
    public func focusable(_ isFocusable: Bool = true) -> Self {
        handling {
            $0.isFocusable = isFocusable
            $0.keyboard = KeyboardAttachment.interactions(nil, over: $0.keyboard)
        }
    }

    /// Makes this layer focusable (or not) with `interactions` —
    /// `StyledElement.focusable(_:interactions:)`'s rules (`.edit` focuses on
    /// a primary press). A later `focusable` replaces it.
    public func focusable(_ isFocusable: Bool = true, interactions: FocusInteractions) -> Self {
        handling {
            $0.isFocusable = isFocusable
            $0.keyboard = KeyboardAttachment.interactions(interactions, over: $0.keyboard)
        }
    }

    /// Contributes a key context for this layer and its subtree —
    /// `StyledElement.keyContext(_:_:)`'s rules. A second one replaces the first.
    public func keyContext(_ name: String, _ values: [String: String] = [:]) -> Self {
        handling { $0.keyContext = KeyContext(name, values) }
    }

    /// Binds this layer's focus to a Boolean `@FocusState` —
    /// `StyledElement.focused(_:)`'s rules (it does not make the layer
    /// focusable; a second `.focused` replaces the first).
    public func focused(_ condition: FocusState<Bool>.Binding) -> Self {
        handling { $0.focusBinding = FocusBindingTarget(state: condition.box, value: AnyHashable(true)) }
    }

    /// Binds this layer's focus to `binding` reading `value` —
    /// `StyledElement.focused(_:equals:)`'s rules.
    public func focused<Value: Hashable>(_ binding: FocusState<Value>.Binding, equals value: Value) -> Self {
        handling { $0.focusBinding = FocusBindingTarget(state: binding.box, value: AnyHashable(value)) }
    }

    /// Makes this layer a key region (or not) — `StyledElement.hoverKeyRegion(_:)`'s
    /// rules (MetalUI-only, `KF-E`).
    public func hoverKeyRegion(_ isEnabled: Bool = true) -> Self {
        handling { $0.keyboard = KeyboardAttachment.keyRegion(isEnabled, over: $0.keyboard) }
    }

    /// The content's layout.
    public struct Layout { var content: Content.GroupLayout }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "a keyboard modifier requires one native child")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // STUB (lane C red commit): registers nothing.
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension KeyboardModifier: ProposalElement {}
