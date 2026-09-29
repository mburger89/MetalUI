import MetalUICore
import MetalUIPlatform

// Plan task 12 part 1, lane 2 — `.keyboardShortcut` (ruling `IX-F`). SwiftUI's
// spellings (the SDK's `KeyEquivalent`, `KeyboardShortcut`, `EventModifiers`),
// offered on `Button` only; a shortcut rides `Handlers` into the focus registry
// in tree order and is dispatched by `Window` after the raw `onKey` bubble and
// before Tab traversal (spec §5).

/// SwiftUI's `EventModifiers`, **narrower** (ruling `IX-F` item 1, `IX-O`
/// correction 8): MetalUI's `Modifiers` — `.shift`, `.control`, `.option`,
/// `.command` — with no `.capsLock`, `.numericPad`, `.function` or `.all`,
/// which no platform event MetalUI receives reports. Adding them is additive.
public typealias EventModifiers = Modifiers

/// A key a shortcut names — SwiftUI's `KeyEquivalent`: one character, compared
/// case-insensitively with a key event's `charactersIgnoringModifiers`.
///
/// The named keys are AppKit's characters (which SDL's keys are translated to,
/// `SP-C`): Return `\r`, Escape `\u{1b}`, Delete `\u{7f}`, and the function-key
/// range for the arrows, Home, End, Page Up/Down, Clear and forward delete.
public struct KeyEquivalent: Equatable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
    /// The character the key produces.
    public let character: Character

    public init(_ character: Character) { self.character = character }

    public init(extendedGraphemeClusterLiteral character: Character) {
        self.character = character
    }

    public static let `return` = KeyEquivalent("\r")
    public static let escape = KeyEquivalent("\u{1b}")
    public static let space = KeyEquivalent(" ")
    public static let tab = KeyEquivalent("\t")
    public static let delete = KeyEquivalent("\u{7f}")
    public static let deleteForward = KeyEquivalent("\u{f728}")
    public static let upArrow = KeyEquivalent("\u{f700}")
    public static let downArrow = KeyEquivalent("\u{f701}")
    public static let leftArrow = KeyEquivalent("\u{f702}")
    public static let rightArrow = KeyEquivalent("\u{f703}")
    public static let home = KeyEquivalent("\u{f729}")
    public static let end = KeyEquivalent("\u{f72b}")
    public static let pageUp = KeyEquivalent("\u{f72c}")
    public static let pageDown = KeyEquivalent("\u{f72d}")
    public static let clear = KeyEquivalent("\u{f739}")
}

/// A key and the modifiers that must be held with it — SwiftUI's
/// `KeyboardShortcut`.
///
/// **The modifiers match exactly** (`IX-F` item 2, probe `B4e`–`B4g`): ⌘K fires
/// a ⌘K shortcut, plain K does not, and a `modifiers: []` shortcut fires on
/// plain K and not on ⌘K.
public struct KeyboardShortcut: Equatable, Sendable {
    public let key: KeyEquivalent
    public let modifiers: EventModifiers

    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Return, no modifiers (`B4a`).
    public static let defaultAction = KeyboardShortcut(.return, modifiers: [])
    /// Escape, no modifiers (`B4b`).
    public static let cancelAction = KeyboardShortcut(.escape, modifiers: [])

    /// Whether `event` is this shortcut: the key compared lower-cased with
    /// `charactersIgnoringModifiers` (AppKit reports a shifted letter upper-case
    /// there), the modifiers compared exactly.
    func matches(_ event: KeyEvent) -> Bool {
        event.modifiers == modifiers
            && event.charactersIgnoringModifiers.lowercased() == String(key.character).lowercased()
    }
}

/// What a `Button` hands the focus registry for its shortcut: the shortcut and
/// the action a click runs. **A class**, so `Handlers` carries one reference
/// (`IX-N`'s Windows stack budget).
final class ShortcutTarget {
    let shortcut: KeyboardShortcut
    let action: @MainActor () -> Void

    init(_ shortcut: KeyboardShortcut, action: @escaping @MainActor () -> Void) {
        self.shortcut = shortcut
        self.action = action
    }
}

extension Window {
    /// Runs the first shortcut, in tree order, that `event` matches (`IX-F`
    /// items 2–5), against `lastFocusRegistry` as every key stage resolves.
    /// **Focus is not needed** (`B4e`); the stage runs after the keymap, a
    /// focused field's editing keys and the raw `onKey` bubble, so each of those
    /// claims a key first (`B4i`, `X2`), and before Tab traversal.
    func dispatchShortcut(_ event: InputEvent) -> Bool {
        guard case .keyDown(let key) = event else { return false }
        guard let (id, target) = lastFocusRegistry.shortcut(matching: key) else { return false }
        StateDispatch.dispatching(to: id) { target.action() }   // ID-F: the button that owns it
        return true
    }
}
