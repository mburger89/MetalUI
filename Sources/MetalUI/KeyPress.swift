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

    /// Whether `press` reaches this handler (`KF-B` items 2 and 3): its phase
    /// is one of `phases`, and the filter matches — a key or a set of keys
    /// compared exactly with `press.key` (case-sensitive, modifiers ignored:
    /// K8), a character set holding every scalar of `press.characters` (K7).
    func accepts(_ press: KeyPress) -> Bool {
        guard phases.contains(press.phase) else { return false }
        switch filter {
        case .key(let key): return press.key == key
        case .keys(let keys): return keys.contains(press.key)
        case .characters(let set):
            return !press.characters.isEmpty && press.characters.unicodeScalars.allSatisfy { set.contains($0) }
        case .any: return true
        }
    }
}

/// What the keyboard modifiers of this item attach to an element: one class
/// box riding `Handlers.keyboard` (ruling `KF-I`) — the `onKeyPress` handlers
/// in written order, the focus interactions and the key-region flag. Each
/// modifier makes a new box (a value's copies never share a change).
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

    /// The box with these fields, or `nil` when every one is the default —
    /// so an element no keyboard modifier configures keeps `keyboard == nil`.
    static func make(keyPresses: [KeyPressHandler], focusInteractions: FocusInteractions?,
                     isKeyRegion: Bool) -> KeyboardAttachment? {
        if keyPresses.isEmpty && focusInteractions == nil && !isKeyRegion { return nil }
        return KeyboardAttachment(keyPresses: keyPresses, focusInteractions: focusInteractions,
                                  isKeyRegion: isKeyRegion)
    }

    /// `existing` with `handler` appended.
    static func adding(_ handler: KeyPressHandler, to existing: KeyboardAttachment?) -> KeyboardAttachment? {
        make(keyPresses: (existing?.keyPresses ?? []) + [handler],
             focusInteractions: existing?.focusInteractions, isKeyRegion: existing?.isKeyRegion ?? false)
    }

    /// `existing` with its focus interactions replaced.
    static func interactions(_ interactions: FocusInteractions?,
                             over existing: KeyboardAttachment?) -> KeyboardAttachment? {
        make(keyPresses: existing?.keyPresses ?? [], focusInteractions: interactions,
             isKeyRegion: existing?.isKeyRegion ?? false)
    }

    /// `existing` with its key-region flag replaced.
    static func keyRegion(_ isKeyRegion: Bool, over existing: KeyboardAttachment?) -> KeyboardAttachment? {
        make(keyPresses: existing?.keyPresses ?? [], focusInteractions: existing?.focusInteractions,
             isKeyRegion: isKeyRegion)
    }
}

extension StyledElement {
    func addingKeyPress(_ phases: KeyPress.Phases, _ filter: KeyPressHandler.Filter,
                        _ action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        handling {
            $0.keyboard = KeyboardAttachment.adding(KeyPressHandler(phases: phases, filter: filter, action: action),
                                                    to: $0.keyboard)
        }
    }

    /// Runs `action` when `key` goes down or repeats while this element holds
    /// focus, or is an ancestor of the focused element (or, with nothing
    /// focused, of the hovered key region, `hoverKeyRegion(_:)`) — SwiftUI's
    /// `onKeyPress(_:action:)` (ruling `KF-B`).
    ///
    /// **Return `.handled` to take the key**: no later handler and no later
    /// stage sees it — not a focused `TextField`'s editing keys (so ↑ never
    /// moves its caret and Return never submits, K4c, K4g), not a `Button`'s
    /// keyboard shortcut (K10), not Tab traversal. `.ignored` passes it on.
    /// The key is compared exactly with the key the event reports, ignoring
    /// modifiers: `"a"` fires for `a` and ⌘A, not for ⇧A, which reports `A`
    /// (K8).
    ///
    /// **Order** (`KF-C`): the window's `Keymap` first; then every `onKeyPress`
    /// along the chain **outermost first** — an ancestor's before the focused
    /// element's, the opposite of `onKey(_:)`'s bubble (K2t, K2v) — and on one
    /// element the later-written first (K2w); then the focused field's
    /// editing keys, `onKey`, shortcuts, the app's commands and Tab. On a
    /// focused `TextField` a typed character is offered too, as `.down` only
    /// (divergence 187, `KF-Q`); an input method's composition is never
    /// offered.
    ///
    /// Runs from input, on the main actor, dispatched to this element, so
    /// `@State` and `Binding` writes are legal. **It does not make the element
    /// focusable** (`focusable(_:)`), and on one element it hears in either
    /// order relative to `.focusable()` (divergence 185). What `action`
    /// captures outlives the frame — `onClick(_:)`'s retain-cycle note
    /// applies. Disabled and hidden elements' handlers are not registered.
    /// Each `onKeyPress` adds a handler (they do not replace each other).
    public func onKeyPress(_ key: KeyEquivalent,
                           action: @escaping @MainActor () -> KeyPress.Result) -> Self {
        addingKeyPress([.down, .repeat], .key(key)) { _ in action() }
    }

    /// Runs `action` with the `KeyPress` when `key` reaches this element in one
    /// of `phases` — SwiftUI's `onKeyPress(_:phases:action:)`; otherwise as
    /// `onKeyPress(_:action:)`. `.up` hears the release (K5c).
    public func onKeyPress(_ key: KeyEquivalent, phases: KeyPress.Phases,
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .key(key), action)
    }

    /// Runs `action` when any of `keys` reaches this element in one of
    /// `phases` — SwiftUI's `onKeyPress(keys:phases:action:)` (K6); otherwise
    /// as `onKeyPress(_:action:)`. `[.upArrow, .downArrow]` on a palette's
    /// focused search field claims ↑/↓ before the field moves its caret.
    public func onKeyPress(keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .keys(keys), action)
    }

    /// Runs `action` when a key whose produced characters all lie in
    /// `characters` reaches this element in one of `phases` — SwiftUI's
    /// `onKeyPress(characters:phases:action:)` (K7: the characters with
    /// modifiers applied, `KeyPress.characters`); otherwise as
    /// `onKeyPress(_:action:)`. On a focused `TextField`,
    /// `.decimalDigits.inverted` answering `.handled` keeps only digits.
    public func onKeyPress(characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .characters(characters), action)
    }

    /// Runs `action` for every key that reaches this element in one of
    /// `phases` — SwiftUI's `onKeyPress(phases:action:)`; otherwise as
    /// `onKeyPress(_:action:)`.
    public func onKeyPress(phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self {
        addingKeyPress(phases, .any, action)
    }

    /// Lets this element hold keyboard focus when `isFocusable`, and says how it
    /// takes it — SwiftUI's `focusable(_:interactions:)` (ruling `KF-F`).
    ///
    /// **`.edit` focuses on a primary press** (SwiftUI's FC3): the element
    /// registers a non-opaque press region — it blocks no click, hover, wheel,
    /// drop or gesture aimed at what it covers, and the press still reaches
    /// the gesture arena and click dispatch (FC6: focus and tap). The
    /// innermost such element under the press, on the topmost layer by the
    /// one ranking, takes focus; a `TextField` inside it focuses itself. A
    /// secondary press focuses nothing. `.disabled(true)`, `.hidden()` and
    /// `.allowsHitTesting(false)` withdraw the press region.
    ///
    /// `.activate` and `.automatic` focus by Tab and `Window.focus(_:)` only —
    /// `.automatic` is where MetalUI differs from SwiftUI's macOS, which
    /// focuses on click (divergence 94). A later `focusable` replaces this.
    public func focusable(_ isFocusable: Bool = true, interactions: FocusInteractions) -> Self {
        handling {
            $0.isFocusable = isFocusable
            $0.keyboard = KeyboardAttachment.interactions(interactions, over: $0.keyboard)
        }
    }
}

/// Runs the first `onKeyPress` handler along `chain` that claims `press`, and
/// reports whether one did (ruling `KF-C` item 2).
///
/// **Outermost first**: `chain` is innermost first (`focusChain(from:)`), so it
/// is walked reversed — root to the focused element (or the hovered key
/// region) — and each element's handlers last-written first (K2v, K2w). Each
/// runs under `StateDispatch.dispatching(to:)` its own element (ID-F). A free
/// function over an explicit chain and registry, for `dispatchKey(_:along:in:)`'s
/// reason; a registry with no handler costs one comparison.
@MainActor
func dispatchKeyPress(_ press: KeyPress, along chain: [GlobalElementID], in registry: FocusRegistry) -> Bool {
    guard registry.keyPressCount > 0 else { return false }
    for id in chain.reversed() {
        for handler in registry.keyPresses(for: id).reversed() where handler.accepts(press) {
            if StateDispatch.dispatching(to: id, { handler.action(press) }) == .handled { return true }
        }
    }
    return false
}
