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
public struct KeyEquivalent: Hashable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
    /// The character the key produces.
    public let character: Character

    /// The key that produces `character`.
    public init(_ character: Character) { self.character = character }

    /// A key from a character literal: `.keyboardShortcut("k")`.
    public init(extendedGraphemeClusterLiteral character: Character) {
        self.character = character
    }

    /// The Return key.
    public static let `return` = KeyEquivalent("\r")
    /// The Escape key.
    public static let escape = KeyEquivalent("\u{1b}")
    /// The Space bar.
    public static let space = KeyEquivalent(" ")
    /// The Tab key.
    public static let tab = KeyEquivalent("\t")
    /// The Delete (backspace) key.
    public static let delete = KeyEquivalent("\u{7f}")
    /// The forward-delete key.
    public static let deleteForward = KeyEquivalent("\u{f728}")
    /// The up arrow key.
    public static let upArrow = KeyEquivalent("\u{f700}")
    /// The down arrow key.
    public static let downArrow = KeyEquivalent("\u{f701}")
    /// The left arrow key.
    public static let leftArrow = KeyEquivalent("\u{f702}")
    /// The right arrow key.
    public static let rightArrow = KeyEquivalent("\u{f703}")
    /// The Home key.
    public static let home = KeyEquivalent("\u{f729}")
    /// The End key.
    public static let end = KeyEquivalent("\u{f72b}")
    /// The Page Up key.
    public static let pageUp = KeyEquivalent("\u{f72c}")
    /// The Page Down key.
    public static let pageDown = KeyEquivalent("\u{f72d}")
    /// The Clear key.
    public static let clear = KeyEquivalent("\u{f739}")
}

/// A key and the modifiers that must be held with it — SwiftUI's
/// `KeyboardShortcut`.
///
/// **The modifiers match exactly** (`IX-F` item 2, probe `B4e`–`B4g`): ⌘K fires
/// a ⌘K shortcut, plain K does not, and a `modifiers: []` shortcut fires on
/// plain K and not on ⌘K.
public struct KeyboardShortcut: Equatable, Sendable {
    /// The key that must be pressed, compared case-folded.
    public let key: KeyEquivalent
    /// The modifiers that must be held, matched exactly (`IX-F` item 2).
    public let modifiers: EventModifiers

    /// A shortcut of `key` with `modifiers` — by default `.primary`: ⌘ on
    /// macOS, as SwiftUI's `.command`, and Ctrl on Linux and Windows (ruling
    /// `SG-B` item 3).
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .primary) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Return, no modifiers (`B4a`).
    public static let defaultAction = KeyboardShortcut(.return, modifiers: [])
    /// Escape, no modifiers (`B4b`).
    public static let cancelAction = KeyboardShortcut(.escape, modifiers: [])

    /// A desktop whose shortcut spelling `displayText(for:)` produces (`KF-AG`).
    ///
    /// MetalUI-only (class M): SwiftUI's menus are drawn by the system, so it has no
    /// such type. It is public so a settings screen can show a shortcut as
    /// another desktop would, and has a Windows case that the internal
    /// `TextEditing.Platform` (`.mac`/`.other`) lacks.
    public enum Platform: Hashable, Sendable, CaseIterable {
        /// macOS: glyphs, `⌃⌥⇧⌘K`.
        case macOS
        /// Linux: names, `Ctrl+Super+Alt+Shift+K`.
        case linux
        /// Windows: names, `Ctrl+Win+Alt+Shift+K`.
        case windows

        /// The platform this build runs on, decided at compile time by the
        /// same conditions as `Modifiers.primary`, `TextEditing.platform` and
        /// the drawn menu's Super/Win name: Apple (macOS) is `.macOS`,
        /// Windows `.windows`, anything else `.linux`.
        public static var current: Platform {
            #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
            return .macOS
            #elseif os(Windows)
            return .windows
            #else
            return .linux
            #endif
        }

        /// The modifier `.primary` means on this platform: `.command` on
        /// macOS, `.control` on Linux and Windows. Use it to build another
        /// platform's shortcut, since `.primary` itself resolves to the host's
        /// modifier when the code is compiled.
        public var primaryModifiers: EventModifiers {
            switch self {
            case .macOS: .command
            case .linux, .windows: .control
            }
        }
    }

    /// The shortcut as the current platform spells it: `⇧⌘P` on macOS,
    /// `Ctrl+Shift+P` elsewhere (`KF-AG`). Equal to `displayText(for: .current)`.
    public var displayText: String { displayText(for: .current) }

    /// The shortcut as `platform` spells it (`KF-AG`): on macOS the modifier
    /// glyphs in ⌃⌥⇧⌘ order then the key (`⇧⌘P`, `⌘↩`, `⌥F12`); on Linux and
    /// Windows each held key by name joined by `+`, in the order Ctrl, Super
    /// (Linux) or Win (Windows), Alt, Shift, then the key (`Ctrl+Shift+P`,
    /// `Alt+Page Up`). Named keys read as glyphs (macOS) or names (elsewhere);
    /// any other key is upper-cased unless that would change its length.
    ///
    /// **Modifiers are shown exactly as stored.** `.primary` resolves when the
    /// code is compiled, so another platform's text of a `.primary` shortcut
    /// shows the host's modifier (⌘ on a Mac host reads `Super+P` for
    /// `.linux`). Build the shortcut with `Platform.primaryModifiers` to get
    /// another platform's text.
    public func displayText(for platform: Platform) -> String {
        ShortcutText.format(key: String(key.character), modifiers: modifiers, mac: platform == .macOS,
                            superKeyName: platform == .windows ? "Win" : "Super")
    }

    /// Whether `event` is this shortcut: the key compared lower-cased with
    /// `charactersIgnoringModifiers` (AppKit reports a shifted letter upper-case
    /// there), the modifiers compared exactly.
    func matches(_ event: KeyEvent) -> Bool {
        guard event.modifiers == modifiers else { return false }
        let wanted = String(key.character).lowercased()
        // AppKit sends ⇧Tab as the backtab character (`KF-AL`); it is the Tab key.
        let typed = event.charactersIgnoringModifiers == "\u{19}" ? "\t" : event.charactersIgnoringModifiers.lowercased()
        if typed == wanted { return true }
        // The unshifted base key with Shift (`KF-AL`): ⇧/ fires "/" on AppKit as on SDL.
        return modifiers.contains(.shift) && !event.unshiftedKey.isEmpty && event.unshiftedKey.lowercased() == wanted
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

/// The one shortcut formatter (`KF-AG`): `KeyboardShortcut.displayText` and the
/// drawn menu's `MenuPanel.shortcutText` both call it, so they cannot differ.
enum ShortcutText {
    /// `key` and `modifiers` spelled for macOS (`mac`: glyphs, ⌃⌥⇧⌘ order, no
    /// separators) or elsewhere (names, `Ctrl+<superKeyName>+Alt+Shift+Key`).
    static func format(key: String, modifiers: EventModifiers, mac: Bool, superKeyName: String) -> String {
        let keyText = keyName(key, mac: mac)
        if mac {
            var s = ""
            if modifiers.contains(.control) { s += "⌃" }
            if modifiers.contains(.option) { s += "⌥" }
            if modifiers.contains(.shift) { s += "⇧" }
            if modifiers.contains(.command) { s += "⌘" }
            return s + keyText
        }
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.command) { parts.append(superKeyName) }
        if modifiers.contains(.option) { parts.append("Alt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        return (parts + [keyText]).joined(separator: "+")
    }

    /// A key's text: the named keys (AppKit's characters) as glyphs or names,
    /// F1...F35 (U+F704...U+F726) as `F<n>`, any other key upper-cased only
    /// when the result is still one character (`ß` stays `ß`).
    static func keyName(_ key: String, mac: Bool) -> String {
        let scalars = key.unicodeScalars
        if scalars.count == 1, let scalar = scalars.first {
            switch scalar.value {
            case 0x0D, 0x0A: return mac ? "↩" : "Enter"
            case 0x1B: return mac ? "⎋" : "Esc"
            case 0x09, 0x19: return mac ? "⇥" : "Tab"   // AppKit sends ⇧Tab as U+0019
            case 0x20: return "Space"
            case 0x7F: return mac ? "⌫" : "Backspace"
            case 0xF728: return mac ? "⌦" : "Delete"
            case 0xF700: return mac ? "↑" : "Up"
            case 0xF701: return mac ? "↓" : "Down"
            case 0xF702: return mac ? "←" : "Left"
            case 0xF703: return mac ? "→" : "Right"
            case 0xF729: return mac ? "↖" : "Home"
            case 0xF72B: return mac ? "↘" : "End"
            case 0xF72C: return mac ? "⇞" : "Page Up"
            case 0xF72D: return mac ? "⇟" : "Page Down"
            case 0xF739: return mac ? "⌧" : "Clear"
            case 0xF704...0xF726: return "F\(scalar.value - 0xF704 + 1)"
            default: break
            }
        }
        let upper = key.uppercased()
        return upper.count == 1 ? upper : key
    }
}
