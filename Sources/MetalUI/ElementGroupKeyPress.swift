import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform

// `onKeyPress` on any `ElementGroup` (ruling `KF-AC`; record 316). SwiftUI offers
// the five spellings on every `View`; MetalUI had them on `StyledElement`
// (`KeyPress.swift`), on `ProposalElementGroup` (`KeyboardModifier.swift`, one
// `KeyboardModifier` layer, `KF-H`) and on `KeyboardModifier`. A plain
// `ElementGroup` — a helper returning `some ElementGroup`, a `Pair`, a
// `ForEach` — had none.

extension ElementGroup {
    /// Wraps this group once in the legacy wrapper's own layer — a default
    /// `Style` (what `.padding(0)` writes), one node, one identity level — and
    /// returns it, a `StyledElement`, so the layer's own `onKeyPress` and later
    /// keyboard modifiers (`.focusable()`, `.keyContext`, `.focused`) join the
    /// same layer (`KF-AC` item 2).
    private func keyPressLayer() -> ModifiedElement<LayerBase> {
        _wrap(ModifierLayer(style: Style()))
    }

    /// SwiftUI's `onKeyPress(_:action:)` on any `ElementGroup`: the handler of
    /// `StyledElement.onKeyPress(_:action:)` (ruling `KF-B`), on a layer around
    /// this group. It hears a key when this group's layer holds focus or is an
    /// ancestor of the focused element and nothing nearer took the key
    /// (outermost first, `KF-C`). **It does not make the group focusable**
    /// (`focusable(_:)`), as on a `StyledElement` and as in SwiftUI. The more
    /// specific `StyledElement` and `ProposalElementGroup` spellings are still
    /// chosen for their conformers (`KF-AC` item 3).
    @_disfavoredOverload
    public func onKeyPress(_ key: KeyEquivalent,
                           action: @escaping @MainActor () -> KeyPress.Result) -> ModifiedElement<LayerBase> {
        keyPressLayer().onKeyPress(key, action: action)
    }

    /// SwiftUI's `onKeyPress(_:phases:action:)` on any `ElementGroup`;
    /// otherwise as `onKeyPress(_:action:)`.
    @_disfavoredOverload
    public func onKeyPress(_ key: KeyEquivalent, phases: KeyPress.Phases,
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> ModifiedElement<LayerBase> {
        keyPressLayer().onKeyPress(key, phases: phases, action: action)
    }

    /// SwiftUI's `onKeyPress(keys:phases:action:)` on any `ElementGroup`;
    /// otherwise as `onKeyPress(_:action:)`.
    @_disfavoredOverload
    public func onKeyPress(keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> ModifiedElement<LayerBase> {
        keyPressLayer().onKeyPress(keys: keys, phases: phases, action: action)
    }

    /// SwiftUI's `onKeyPress(characters:phases:action:)` on any `ElementGroup`;
    /// otherwise as `onKeyPress(_:action:)`.
    @_disfavoredOverload
    public func onKeyPress(characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> ModifiedElement<LayerBase> {
        keyPressLayer().onKeyPress(characters: characters, phases: phases, action: action)
    }

    /// SwiftUI's `onKeyPress(phases:action:)` on any `ElementGroup`; otherwise
    /// as `onKeyPress(_:action:)`.
    @_disfavoredOverload
    public func onKeyPress(phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> ModifiedElement<LayerBase> {
        keyPressLayer().onKeyPress(phases: phases, action: action)
    }
}
