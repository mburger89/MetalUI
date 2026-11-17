/// The modifier keys held with a key or a mouse event.
public struct TerminalModifiers: OptionSet, Hashable, Sendable {
    /// The raw bits.
    public let rawValue: Int

    /// Creates a set from raw bits.
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Shift.
    public static let shift = TerminalModifiers(rawValue: 1 << 0)
    /// Control.
    public static let control = TerminalModifiers(rawValue: 1 << 1)
    /// Option (Alt).
    public static let option = TerminalModifiers(rawValue: 1 << 2)
    /// Command. A key with it encodes to nothing (`TRM-AJ`).
    public static let command = TerminalModifiers(rawValue: 1 << 3)
}

/// A key press, in `KeyEquivalent`'s spelling and free of any UI type.
///
/// Arrows, Home, End, the page keys, Insert, forward delete and the function keys use the private-use
/// codes `U+F700...` (`"\u{F700}"` up, `"\u{F701}"` down, `"\u{F702}"` left, `"\u{F703}"` right,
/// `"\u{F704}"`...`"\u{F717}"` F1-F20, `"\u{F727}"` Insert, `"\u{F728}"` forward delete, `"\u{F729}"` Home,
/// `"\u{F72B}"` End, `"\u{F72C}"` Page Up, `"\u{F72D}"` Page Down); Backspace is `"\u{7F}"`. The keypad has
/// no spelling, so `applicationKeypad` has no effect on keys (`TRM-AI`).
public struct TerminalKey: Sendable {
    /// The key, with modifiers ignored.
    public var key: Character
    /// The characters the key produced (empty for non-text keys).
    public var characters: String
    /// The modifiers held.
    public var modifiers: TerminalModifiers

    /// Creates a key press.
    public init(key: Character, characters: String, modifiers: TerminalModifiers) {
        self.key = key
        self.characters = characters
        self.modifiers = modifiers
    }
}

/// A mouse event, before it is encoded for the child.
public struct TerminalMouseEvent: Sendable {
    /// What happened.
    public enum Kind: Sendable {
        /// A button went down.
        case press
        /// A button went up.
        case release
        /// The pointer moved, with or without a button held.
        case move
        /// The wheel scrolled up.
        case wheelUp
        /// The wheel scrolled down.
        case wheelDown
    }

    /// The button involved.
    public enum Button: Sendable {
        /// The primary button.
        case left
        /// The middle button.
        case middle
        /// The secondary button.
        case right
        /// No button (plain motion, or a wheel).
        case none
    }

    /// What happened.
    public var kind: Kind
    /// The button involved.
    public var button: Button
    /// The modifiers held.
    public var modifiers: TerminalModifiers

    /// Creates an event.
    public init(kind: Kind, button: Button = .none, modifiers: TerminalModifiers = []) {
        self.kind = kind
        self.button = button
        self.modifiers = modifiers
    }
}
