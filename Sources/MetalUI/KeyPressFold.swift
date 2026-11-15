import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform

// `onKeyPress` folded into a proposal chain (ruling `KF-AD`; record 319). On a
// proposal group `onKeyPress` wrapped the receiver in a `KeyboardModifier`, an
// `Element`: one more group member entered, and counted, on every frame
// (`Frame.elementRequests`), where a chain's own layers cost none. On a
// `ModifiedContent<_, LayoutModifier>` — and on a `LifecycleScope` over one,
// the shape `.frame(…).onChange(of:…) { … }` makes — the five spellings now add
// (or join) one `LayoutModifier.keyboard` layer of the chain and return `Self`.

/// The `onKeyPress` handlers of one `LayoutModifier.keyboard` layer. MetalUI-only
/// and opaque: built by the chain's `onKeyPress` spellings, never directly.
public struct KeyboardLayer: @unchecked Sendable {
    /// In written order; `nil` once a `KeyboardModifier` over the chain took
    /// them (`KeyboardLayerHolder`), so the layer then registers nothing.
    var presses: [KeyPressHandler]?

    init(presses: [KeyPressHandler]) { self.presses = presses }

    /// This layer with `handler` added, or a layer of it alone after a `KeyboardModifier` took the rest.
    mutating func add(_ handler: KeyPressHandler) {
        presses = (presses ?? []) + [handler]
    }

    var handlers: Handlers? {
        guard let presses, !presses.isEmpty else { return nil }
        var handlers = Handlers()
        handlers.keyboard = KeyboardAttachment(keyPresses: presses)
        return handlers
    }
}

/// A chain whose outermost layer may hold `onKeyPress` handlers a `KeyboardModifier`
/// written over it must own: the focus target is the `KeyboardModifier`, and a
/// handler on a layer inside it would not be on the focus chain (`KF-AD` item 3).
@MainActor
protocol KeyboardLayerHolder {
    /// Removes and returns the outermost keyboard layer's handlers, leaving the
    /// layer (and its identity level) in place, empty.
    mutating func takeKeyPresses() -> [KeyPressHandler]?
}

extension ModifiedContent: KeyboardLayerHolder where Modifier == LayoutModifier {
    mutating func takeKeyPresses() -> [KeyPressHandler]? {
        guard case let .keyboard(layer) = outermost, let presses = layer.presses else { return nil }
        var taken = layer
        taken.presses = nil
        outermost = .keyboard(taken)
        return presses
    }
}

extension LifecycleScope: KeyboardLayerHolder where Content: KeyboardLayerHolder {
    mutating func takeKeyPresses() -> [KeyPressHandler]? { content.takeKeyPresses() }
}

/// A proposal group whose `onKeyPress` joins a keyboard layer of its chain instead of wrapping
/// it in a `KeyboardModifier` (ruling `KF-AD`): a proposal `ModifiedContent` chain and a
/// `LifecycleScope` over one. **Not for conformers.** MetalUI-only; the protocol exists so the
/// five `onKeyPress` spellings below are one more specific candidate than
/// `ProposalElementGroup`'s.
public protocol _KeyPressFolding: ProposalElementGroup {
    /// This group with `change` applied to its outermost keyboard layer, added if the outermost layer is not one.
    func _foldingKeyboardLayer(_ change: (inout KeyboardLayer) -> Void) -> Self
}

extension ModifiedContent: _KeyPressFolding where Content: ProposalElementGroup, Modifier == LayoutModifier {
    /// The chain with `change` applied to its outermost layer when that is a keyboard layer, else with a new one
    /// appended (ruling `KF-AD`). Framework entry point, not for callers.
    public func _foldingKeyboardLayer(_ change: (inout KeyboardLayer) -> Void) -> Self {
        if case var .keyboard(layer) = outermost, layer.presses != nil {
            change(&layer)
            var copy = self
            copy.outermost = .keyboard(layer)
            return copy
        }
        var layer = KeyboardLayer(presses: [])
        change(&layer)
        return _wrapLayout(.keyboard(layer))
    }
}

extension LifecycleScope: _KeyPressFolding where Content: _KeyPressFolding {
    /// The scope around its content's fold: the scope stays transparent. Framework entry point, not for callers.
    public func _foldingKeyboardLayer(_ change: (inout KeyboardLayer) -> Void) -> Self {
        LifecycleScope(content: content._foldingKeyboardLayer(change), write: write)
    }
}

extension _KeyPressFolding {
    private func addingKeyPress(_ phases: KeyPress.Phases, _ filter: KeyPressHandler.Filter,
                                _ action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        let handler = KeyPressHandler(phases: phases, filter: filter, action: action)
        return _foldingKeyboardLayer { $0.add(handler) }
    }

    /// SwiftUI's `onKeyPress(_:action:)` on a proposal chain, or a `LifecycleScope` over one
    /// (`.frame(…).onChange(of:…) { … }`): the handler joins the chain as one `keyboard`
    /// layer — no `KeyboardModifier`, no further element, `Self` back (ruling `KF-AD`). Semantics
    /// are `KeyboardModifier.onKeyPress`'s (`KF-B`, `KF-C`, `KF-H`); it does not make the group
    /// focusable, and a `.focusable()` written after takes the handlers into its own layer.
    public func onKeyPress(_ key: KeyEquivalent,
                           action: @escaping @MainActor () -> KeyPress.Result) -> Self {
        addingKeyPress([.down, .repeat], .key(key)) { _ in action() }
    }

    /// SwiftUI's `onKeyPress(_:phases:action:)` on a proposal chain; otherwise as `onKeyPress(_:action:)`.
    public func onKeyPress(_ key: KeyEquivalent, phases: KeyPress.Phases,
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .key(key), action)
    }

    /// SwiftUI's `onKeyPress(keys:phases:action:)` on a proposal chain; otherwise as `onKeyPress(_:action:)`.
    public func onKeyPress(keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .keys(keys), action)
    }

    /// SwiftUI's `onKeyPress(characters:phases:action:)` on a proposal chain; otherwise as `onKeyPress(_:action:)`.
    public func onKeyPress(characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .characters(characters), action)
    }

    /// SwiftUI's `onKeyPress(phases:action:)` on a proposal chain; otherwise as `onKeyPress(_:action:)`.
    public func onKeyPress(phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .any, action)
    }
}

/// One `onKeyPress` handler on its way to `ElementGroup._addingKeyPress(_:)`. MetalUI-only and opaque: made by the
/// `onKeyPress` spellings, never directly (ruling `KF-AE`).
public struct KeyPressRegistration: @unchecked Sendable {
    let handler: KeyPressHandler
    init(_ handler: KeyPressHandler) { self.handler = handler }
}

extension ElementGroup where KeyPressed == ModifiedElement<LayerBase> {
    /// A group with no layer of its own: one wrapper layer (a default `Style`, one node, one identity level) holding
    /// the handler, the `KF-AC` shape.
    public func _addingKeyPress(_ registration: KeyPressRegistration) -> ModifiedElement<LayerBase> {
        let h = registration.handler
        return _wrap(ModifierLayer(style: Style())).addingKeyPress(h.phases, h.filter, h.action)
    }
}
