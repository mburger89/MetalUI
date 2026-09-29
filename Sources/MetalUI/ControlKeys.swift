import MetalUICore
import MetalUIPlatform

/// The controls' keys, one table for every control (ruling `DD-T` item 2; spec
/// `2026-09-26-controls-and-selection-design.md` §5), keyed on
/// `TextEditing.platform` — the precedent `TI-D` set for the editing keys.
///
/// **Written by lane 1 and read by lanes 2 and 3; edited by nobody else**
/// (`DD-Q`): `Slider`, `Stepper` and a selectable `List` read their rows here,
/// so a changed convention is one row, not three copies.
///
/// A control consults this only from its own `onKey`, which runs after the
/// window's `Keymap` and after a caller's own `onKey` declined the key (spec
/// §4). **SwiftUI's controls take none of these keys here** (divergence 80):
/// with Full Keyboard Access off, a focused `Button`, `Toggle` or `Slider`
/// ignores Space, Return and the arrows (probe KY1, KY4, KY4b, KY5, KY7). Only
/// `List`'s arrows are SwiftUI's measured behaviour (KY6, KY8). This table is
/// MetalUI's own convention and reads no system setting.
enum ControlKeys {
    typealias Platform = TextEditing.Platform

    static let space = " "
    /// AppKit's (and SDL's translated, `SP-C`) character for Return.
    static let returnKey = "\r"

    /// Which way a key moves a value or a selection: toward the lower bound /
    /// previous option, or toward the upper bound / next option.
    enum Direction: Equatable, Sendable {
        case backward
        case forward
    }

    /// A `Button`'s activation: Space on Apple; Space and Return elsewhere.
    /// No modifiers.
    static func activatesButton(_ event: KeyEvent, platform: Platform = TextEditing.platform) -> Bool {
        guard event.modifiers.isEmpty else { return false }
        switch event.charactersIgnoringModifiers {
        case space: return true
        case returnKey: return platform == .other
        default: return false
        }
    }

    /// A `Toggle`'s toggle: Space, on every platform. No modifiers.
    static func togglesToggle(_ event: KeyEvent, platform: Platform = TextEditing.platform) -> Bool {
        event.modifiers.isEmpty && event.charactersIgnoringModifiers == space
    }

    /// A `Picker`'s previous/next option: ← and ↑ previous, → and ↓ next, on
    /// every platform. No modifiers; the picker does not wrap (`DD-T` item 2).
    static func pickerMove(_ event: KeyEvent, platform: Platform = TextEditing.platform) -> Direction? {
        guard event.modifiers.isEmpty else { return nil }
        switch event.charactersIgnoringModifiers {
        case TextEditing.leftArrow, TextEditing.upArrow: return .backward
        case TextEditing.rightArrow, TextEditing.downArrow: return .forward
        default: return nil
        }
    }

    /// A `Slider`'s adjustment (lane 2, `DD-W`): ← and ↓ decrement, → and ↑
    /// increment, by the accessibility step. No modifiers.
    static func sliderStep(_ event: KeyEvent, platform: Platform = TextEditing.platform) -> Direction? {
        guard event.modifiers.isEmpty else { return nil }
        switch event.charactersIgnoringModifiers {
        case TextEditing.leftArrow, TextEditing.downArrow: return .backward
        case TextEditing.rightArrow, TextEditing.upArrow: return .forward
        default: return nil
        }
    }

    /// A `Stepper`'s step (lane 2, `DD-X`): ↓ decrement, ↑ increment. No
    /// modifiers.
    static func stepperStep(_ event: KeyEvent, platform: Platform = TextEditing.platform) -> Direction? {
        guard event.modifiers.isEmpty else { return nil }
        switch event.charactersIgnoringModifiers {
        case TextEditing.downArrow: return .backward
        case TextEditing.upArrow: return .forward
        default: return nil
        }
    }

    /// A focused selectable `List`'s move (lane 3, `DD-Z` item 6; KY6, KY8):
    /// ↑ previous row, ↓ next; with ⇧ the move extends from the anchor. Any
    /// other modifier declines the key (⌘A and Space do nothing, KY8c/KY8d).
    static func listMove(_ event: KeyEvent,
                         platform: Platform = TextEditing.platform) -> (direction: Direction, extends: Bool)? {
        guard event.modifiers.isEmpty || event.modifiers == .shift else { return nil }
        let extends = event.modifiers == .shift
        switch event.charactersIgnoringModifiers {
        case TextEditing.upArrow: return (.backward, extends)
        case TextEditing.downArrow: return (.forward, extends)
        default: return nil
        }
    }

    /// The modifier that toggles one row in a multi-selection `List` on click
    /// (lane 3, `DD-Z` item 4): ⌘ on Apple, ctrl elsewhere.
    static func selectionToggleModifier(platform: Platform = TextEditing.platform) -> Modifiers {
        platform == .mac ? .command : .control
    }
}
