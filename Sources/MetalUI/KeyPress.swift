import Foundation
import MetalUICore
import MetalUIPlatform

// Key and focus scoping, lane A (rulings `KF-B`, `KF-C`, `KF-F`, `KF-I`, `KF-Q`;
// spec `docs/superpowers/specs/2026-10-08-key-focus-design.md` §3.1, §4.1).
// SwiftUI's `onKeyPress` family and `focusable(_:interactions:)`, spelled as
// the MacOSX27.0 SDK's `SwiftUI.swiftinterface` spells them (`KF-P` item 3),
// measured by `docs/probes/swiftui-key-focus.swift` (arms K1–K12, FC1–FC7).

/// One key event as an `onKeyPress` handler sees it — SwiftUI's `KeyPress`
/// (ruling `KF-B` item 1). MetalUI makes them; the initializer is internal.
public struct KeyPress: Sendable {
    /// Which phases of a key's life a handler hears — SwiftUI's
    /// `KeyPress.Phases`. The default everywhere is `[.down, .repeat]`.
    public struct Phases: OptionSet, Sendable {
        /// The bits of the set.
        public let rawValue: Int
        /// The set with `rawValue`'s bits.
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// The key went down (a `keyDown` that is not an auto-repeat).
        public static let down = Phases(rawValue: 1 << 0)
        /// The key auto-repeated while held (a `keyDown` with `isRepeat`).
        public static let `repeat` = Phases(rawValue: 1 << 1)
        /// The key was released (a `keyUp`).
        public static let up = Phases(rawValue: 1 << 2)
        /// Every phase: down, repeat and up.
        public static let all: Phases = [.down, .repeat, .up]
    }

    /// What a handler answers — SwiftUI's `KeyPress.Result`.
    public enum Result: Sendable {
        /// The handler took the key: no later handler or stage sees it.
        case handled
        /// Not this handler's key: the walk continues to the next handler, then
        /// to the later stages (a focused field's editing keys, `onKey`, a
        /// `Button`'s shortcut, the app's commands, Tab traversal, `onInput`).
        case ignored
    }

    /// The phase of this event — exactly one of `.down`, `.repeat`, `.up`.
    public let phase: Phases
    /// The key: the first character the unmodified layout reports for it
    /// (`KeyEvent.charactersIgnoringModifiers`), as `KeyEquivalent` spells the
    /// arrows and function keys.
    public let key: KeyEquivalent
    /// The characters the key produced with its modifiers applied.
    public let characters: String
    /// The modifier keys held.
    public let modifiers: EventModifiers

    init(phase: Phases, key: KeyEquivalent, characters: String, modifiers: EventModifiers) {
        self.phase = phase
        self.key = key
        self.characters = characters
        self.modifiers = modifiers
    }
}

/// The ways a focusable element takes focus — SwiftUI's `FocusInteractions`
/// (ruling `KF-F`). In MetalUI only `.edit` changes anything: an element whose
/// interactions contain it **takes focus on a primary press** (SwiftUI's FC3).
/// `.activate` and `.automatic` leave it reachable by Tab and programmatic
/// focus only — `.automatic` is where MetalUI differs from SwiftUI's macOS
/// answer, which focuses on click (divergence 94, narrowed).
public struct FocusInteractions: OptionSet, Sendable {
    /// The bits of the set.
    public let rawValue: Int
    /// The set with `rawValue`'s bits.
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Focus for activation (a button-like element): Tab and programmatic
    /// focus only, never a press (SwiftUI's FC2).
    public static let activate = FocusInteractions(rawValue: 1 << 0)
    /// Focus for editing (a text-like surface, a canvas): a primary press
    /// focuses it, as Tab does (SwiftUI's FC3).
    public static let edit = FocusInteractions(rawValue: 1 << 1)
    /// The platform's choice — in MetalUI, `.activate`'s behaviour (divergence
    /// 94: SwiftUI's macOS automatic focuses on click). A bit of its own, so
    /// `.automatic` never contains `.edit`.
    public static let automatic = FocusInteractions(rawValue: 1 << 2)
}

/// One `onKeyPress` registration: the phases it hears, what it matches and the
/// action (ruling `KF-B`).
struct KeyPressHandler {
    enum Filter {
        case key(KeyEquivalent)
        case keys(Set<KeyEquivalent>)
        case characters(CharacterSet)
        case any
    }

    let phases: KeyPress.Phases
    let filter: Filter
    let action: @MainActor (KeyPress) -> KeyPress.Result
}

/// What the keyboard modifiers of this item attach to an element: one class
/// box riding `Handlers.keyboard` (ruling `KF-I`) — the `onKeyPress` handlers
/// in written order, the focus interactions and the key-region flag.
final class KeyboardAttachment {
    let keyPresses: [KeyPressHandler]
    let focusInteractions: FocusInteractions?
    let isKeyRegion: Bool

    init(keyPresses: [KeyPressHandler] = [], focusInteractions: FocusInteractions? = nil,
         isKeyRegion: Bool = false) {
        self.keyPresses = keyPresses
        self.focusInteractions = focusInteractions
        self.isKeyRegion = isKeyRegion
    }
}

extension StyledElement {
    /// SwiftUI's `onKeyPress(_:action:)` — stub.
    public func onKeyPress(_ key: KeyEquivalent,
                           action: @escaping @MainActor () -> KeyPress.Result) -> Self {
        self
    }

    /// SwiftUI's `onKeyPress(_:phases:action:)` — stub.
    public func onKeyPress(_ key: KeyEquivalent, phases: KeyPress.Phases,
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        self
    }

    /// SwiftUI's `onKeyPress(keys:phases:action:)` — stub.
    public func onKeyPress(keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        self
    }

    /// SwiftUI's `onKeyPress(characters:phases:action:)` — stub.
    public func onKeyPress(characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        self
    }

    /// SwiftUI's `onKeyPress(phases:action:)` — stub.
    public func onKeyPress(phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        self
    }

    /// SwiftUI's `focusable(_:interactions:)` — stub.
    public func focusable(_ isFocusable: Bool = true, interactions: FocusInteractions) -> Self {
        handling { $0.isFocusable = isFocusable }
    }
}
