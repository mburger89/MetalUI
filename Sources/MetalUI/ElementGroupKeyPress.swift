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
    private func addingKeyPress(_ phases: KeyPress.Phases, _ filter: KeyPressHandler.Filter,
                                _ action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> KeyPressed {
        _addingKeyPress(KeyPressRegistration(KeyPressHandler(phases: phases, filter: filter, action: action)))
    }

    /// SwiftUI's `onKeyPress(_:action:)` on any `ElementGroup`: the handler of
    /// `StyledElement.onKeyPress(_:action:)` (ruling `KF-B`), on the layer
    /// this group already owns where it has one (a chain, a scope, an accessibility wrapper, an overlay — chosen
    /// by the conformer, so it holds in generic code, `KF-AE`), else on one wrapper layer around it. It hears a key when this group's layer holds focus or is an
    /// ancestor of the focused element and nothing nearer took the key
    /// (outermost first, `KF-C`). **It does not make the group focusable**
    /// (`focusable(_:)`), as on a `StyledElement` and as in SwiftUI. The more
    /// specific `StyledElement` and `ProposalElementGroup` spellings are still
    /// chosen for their conformers (`KF-AC` item 3).
    @_disfavoredOverload
    public func onKeyPress(_ key: KeyEquivalent,
                           action: @escaping @MainActor () -> KeyPress.Result) -> KeyPressed {
        addingKeyPress([.down, .repeat], .key(key)) { _ in action() }
    }

    /// SwiftUI's `onKeyPress(_:phases:action:)` on any `ElementGroup`;
    /// otherwise as `onKeyPress(_:action:)`.
    @_disfavoredOverload
    public func onKeyPress(_ key: KeyEquivalent, phases: KeyPress.Phases,
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> KeyPressed {
        addingKeyPress(phases, .key(key), action)
    }

    /// SwiftUI's `onKeyPress(keys:phases:action:)` on any `ElementGroup`;
    /// otherwise as `onKeyPress(_:action:)`.
    @_disfavoredOverload
    public func onKeyPress(keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> KeyPressed {
        addingKeyPress(phases, .keys(keys), action)
    }

    /// SwiftUI's `onKeyPress(characters:phases:action:)` on any `ElementGroup`;
    /// otherwise as `onKeyPress(_:action:)`.
    @_disfavoredOverload
    public func onKeyPress(characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> KeyPressed {
        addingKeyPress(phases, .characters(characters), action)
    }

    /// SwiftUI's `onKeyPress(phases:action:)` on any `ElementGroup`; otherwise
    /// as `onKeyPress(_:action:)`.
    @_disfavoredOverload
    public func onKeyPress(phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> KeyPressed {
        addingKeyPress(phases, .any, action)
    }
}
