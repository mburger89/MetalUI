import MetalUI
import MetalUITerminal

extension TerminalKey {
    /// The terminal's spelling of `press` (`TRM-BC`): `KeyPress` already spells arrows, function keys and the rest as
    /// `KeyEquivalent` does, which is `TerminalKey`'s own vocabulary (`TRM-AI`).
    init(_ press: KeyPress) {
        var modifiers: TerminalModifiers = []
        if press.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if press.modifiers.contains(.control) { modifiers.insert(.control) }
        if press.modifiers.contains(.option) { modifiers.insert(.option) }
        if press.modifiers.contains(.command) { modifiers.insert(.command) }
        self.init(key: press.key.character, characters: press.characters, modifiers: modifiers,
                  isKeypad: press.isKeypad)
    }
}

extension TerminalEncoder {
    /// The bytes for a ``KeyPress`` (`TRM-BC`, spec section 3), or `[]` when it encodes to nothing: forwards to
    /// ``encodeKey(_:modes:optionAsMeta:)-swift.type.method`` with the press spelled as a ``TerminalKey``.
    ///
    /// - Parameters:
    ///   - press: The press, as an `onKeyPress` handler receives it.
    ///   - modes: The terminal's modes (application cursor keys and keypad).
    ///   - optionAsMeta: Option sends an ESC prefix on the unmodified character.
    public static func encodeKey(_ press: KeyPress, modes: TerminalModes, optionAsMeta: Bool) -> [UInt8] {
        encodeKey(TerminalKey(press), modes: modes, optionAsMeta: optionAsMeta)
    }
}
