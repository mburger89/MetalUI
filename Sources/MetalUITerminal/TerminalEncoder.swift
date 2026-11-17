/// Turns keys, mouse events, pastes and focus changes into the bytes a child expects. Pure: no emulator state, only the `TerminalModes` the
/// program asked for.
public enum TerminalEncoder {
    private static let esc: UInt8 = 0x1B

    // MARK: Keys

    /// The bytes for a key press, or `[]` when it encodes to nothing (a Command key, an unmapped function key).
    ///
    /// - Parameters:
    ///   - key: The press.
    ///   - modes: DECCKM (`applicationCursorKeys`) picks `SS3` over `CSI` for unmodified arrows, Home, End and F1-F4.
    ///   - modes: `applicationKeypad` (DECKPAM) makes a `isKeypad` key send its `SS3` sequence.
    ///   - optionAsMeta: Option sends an ESC prefix on the unmodified character instead of composing (`TRM-AJ`).
    public static func encodeKey(_ key: TerminalKey, modes: TerminalModes, optionAsMeta: Bool) -> [UInt8] {
        let mods = key.modifiers
        if mods.contains(.command) { return [] }
        let shift = mods.contains(.shift), ctrl = mods.contains(.control), alt = mods.contains(.option)
        let code = key.key.unicodeScalars.count == 1 ? key.key.unicodeScalars.first!.value : 0

        // xterm modifier parameter: 1 + shift + 2 alt + 4 ctrl.
        let param = 1 + (shift ? 1 : 0) + (alt ? 2 : 0) + (ctrl ? 4 : 0)

        if key.isKeypad, modes.applicationKeypad, let final = keypadFinal(key.key) {
            // DECKPAM: SS3 final, or SS3 m final with the xterm modifier parameter.
            return param == 1 ? [esc, 0x4F, final] : [esc, 0x4F] + Array("\(param)".utf8) + [final]
        }

        if let special = specialKey(code) {
            switch special {
            case .final(let letter):
                if param == 1 {
                    return [esc, modes.applicationCursorKeys ? 0x4F : 0x5B, letter]
                }
                return csi("1;\(param)", letter)
            case .function(let letter):
                if param == 1 { return [esc, 0x4F, letter] }
                return csi("1;\(param)", letter)
            case .tilde(let number):
                return param == 1 ? csi("\(number)", 0x7E) : csi("\(number);\(param)", 0x7E)
            }
        }
        if code >= 0xF700 && code <= 0xF8FF { return [] }

        let meta = alt && optionAsMeta
        let prefix: [UInt8] = meta ? [esc] : []

        switch code {
        case 0x09:
            return prefix + (shift ? [esc, 0x5B, 0x5A] : [0x09])
        case 0x0D, 0x0A:
            return prefix + [0x0D]
        case 0x1B:
            return prefix + [esc]
        case 0x7F:
            return prefix + [ctrl ? 0x08 : 0x7F]
        default:
            break
        }

        if ctrl, let c0 = controlByte(for: key.key, shift: shift) {
            return prefix + [c0]
        }
        if meta {
            guard code > 0, code < 0x80 else {
                return key.characters.isEmpty ? [] : prefix + Array(key.characters.utf8)
            }
            var base = UInt8(code)
            if shift, base >= 0x61, base <= 0x7A { base -= 0x20 }
            return prefix + [base]
        }
        if !key.characters.isEmpty { return Array(key.characters.utf8) }
        return []
    }

    /// The final byte after `SS3` for a keypad key in application mode (xterm ctlseqs, "PC-Style Function Keys" keypad rows).
    private static func keypadFinal(_ key: Character) -> UInt8? {
        switch key {
        case "0": 0x70
        case "1": 0x71
        case "2": 0x72
        case "3": 0x73
        case "4": 0x74
        case "5": 0x75
        case "6": 0x76
        case "7": 0x77
        case "8": 0x78
        case "9": 0x79
        case "*": 0x6A
        case "+": 0x6B
        case ",": 0x6C
        case "-": 0x6D
        case ".": 0x6E
        case "/": 0x6F
        case "\r", "\n", "\r\n": 0x4D
        case "=": 0x58
        default: nil
        }
    }

    private enum Special {
        case final(UInt8)
        case function(UInt8)
        case tilde(Int)
    }

    private static func specialKey(_ code: UInt32) -> Special? {
        switch code {
        case 0xF700: return .final(0x41)
        case 0xF701: return .final(0x42)
        case 0xF703: return .final(0x43)
        case 0xF702: return .final(0x44)
        case 0xF729: return .final(0x48)
        case 0xF72B: return .final(0x46)
        case 0xF704...0xF707: return .function(UInt8(0x50 + code - 0xF704))
        case 0xF727: return .tilde(2)
        case 0xF728: return .tilde(3)
        case 0xF72C: return .tilde(5)
        case 0xF72D: return .tilde(6)
        case 0xF708...0xF717:
            let numbers = [15, 17, 18, 19, 20, 21, 23, 24, 25, 26, 28, 29, 31, 32, 33, 34]
            return .tilde(numbers[Int(code - 0xF708)])
        default: return nil
        }
    }

    private static func controlByte(for key: Character, shift: Bool) -> UInt8? {
        guard let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1, scalar.value < 0x80 else { return nil }
        let v = UInt8(scalar.value)
        switch v {
        case 0x61...0x7A: return v & 0x1F
        case 0x41...0x5A: return v & 0x1F
        case 0x40, 0x20, 0x60, 0x32: return 0x00        // @ space ` 2
        case 0x5B, 0x33: return 0x1B                    // [ 3
        case 0x5C, 0x34: return 0x1C                    // \ 4
        case 0x5D, 0x35: return 0x1D                    // ] 5
        case 0x5E, 0x36: return 0x1E                    // ^ 6
        case 0x5F, 0x2D, 0x37: return 0x1F              // _ - 7
        case 0x2F: return shift ? 0x7F : 0x1F           // / and ?
        case 0x3F, 0x38: return 0x7F                    // ? 8
        default: return nil
        }
    }

    private static func csi(_ params: String, _ final: UInt8) -> [UInt8] {
        [esc, 0x5B] + Array(params.utf8) + [final]
    }

    // MARK: Mouse

    /// The report for a mouse event at a viewport cell (0-based), or `[]` when the tracking mode does not report it or a legacy
    /// coordinate is out of range.
    ///
    /// - Parameters:
    ///   - event: The event.
    ///   - cell: The viewport row and column, from 0.
    ///   - modes: Supplies the tracking mode and the report encoding.
    public static func encodeMouse(_ event: TerminalMouseEvent, at cell: TerminalPosition, modes: TerminalModes) -> [UInt8] {
        let tracking = modes.mouseTracking
        guard tracking != .off, cell.row >= 0, cell.col >= 0 else { return [] }

        let base: Int
        var isRelease = false
        switch event.kind {
        case .press:
            guard let b = buttonCode(event.button) else { return [] }
            base = b
        case .release:
            guard tracking != .x10, let b = buttonCode(event.button) else { return [] }
            base = b
            isRelease = true
        case .move:
            guard tracking == .buttonEvent || tracking == .anyEvent else { return [] }
            if tracking == .buttonEvent && event.button == .none { return [] }
            base = (buttonCode(event.button) ?? 3) + 32
        case .wheelUp:
            guard tracking != .x10 else { return [] }
            base = 64
        case .wheelDown:
            guard tracking != .x10 else { return [] }
            base = 65
        case .wheelLeft:
            guard tracking != .x10 else { return [] }
            base = 66
        case .wheelRight:
            guard tracking != .x10 else { return [] }
            base = 67
        }

        var code = base
        if tracking != .x10 {
            if event.modifiers.contains(.shift) { code += 4 }
            if event.modifiers.contains(.option) { code += 8 }
            if event.modifiers.contains(.control) { code += 16 }
        }
        let col = cell.col + 1, row = cell.row + 1

        switch modes.mouseEncoding {
        case .sgr:
            return csi("<\(code);\(col);\(row)", isRelease ? 0x6D : 0x4D)
        case .legacy:
            if isRelease { code = 3 + (code - base) }
            guard col <= 223, row <= 223 else { return [] }
            return [esc, 0x5B, 0x4D, UInt8(32 + code), UInt8(32 + col), UInt8(32 + row)]
        case .utf8:
            if isRelease { code = 3 + (code - base) }
            guard col <= 2015, row <= 2015 else { return [] }
            return [esc, 0x5B, 0x4D] + utf8(32 + code) + utf8(32 + col) + utf8(32 + row)
        }
    }

    private static func buttonCode(_ button: TerminalMouseEvent.Button) -> Int? {
        switch button {
        case .left: 0
        case .middle: 1
        case .right: 2
        case .none: nil
        }
    }

    private static func utf8(_ value: Int) -> [UInt8] {
        if value < 0x80 { return [UInt8(value)] }
        return [UInt8(0xC0 | (value >> 6)), UInt8(0x80 | (value & 0x3F))]
    }

    // MARK: Paste and focus

    /// The bytes for pasted text: every C0 control except tab, CR and LF is dropped (so no ESC, and `ESC[201~` loses its ESC and cannot end
    /// a bracketed paste early), then wrapped in `ESC[200~ ... ESC[201~` when `bracketedPaste` is on.
    public static func encodePaste(_ text: String, modes: TerminalModes) -> [UInt8] {
        var body: [UInt8] = []
        body.reserveCapacity(text.utf8.count)
        for byte in text.utf8 where byte >= 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            body.append(byte)
        }
        guard modes.bracketedPaste else { return body }
        return csi("200", 0x7E) + body + csi("201", 0x7E)
    }

    /// `ESC[I` (focus in) or `ESC[O` (focus out) when `focusEvents` is on, else `[]`.
    public static func encodeFocus(_ focused: Bool, modes: TerminalModes) -> [UInt8] {
        guard modes.focusEvents else { return [] }
        return [esc, 0x5B, focused ? 0x49 : 0x4F]
    }
}
