/// Which mouse events the program asked to receive.
public enum MouseTracking: Hashable, Sendable {
    /// No reporting.
    case off
    /// X10 compatibility (mode 9): presses only.
    case x10
    /// Presses and releases (1000).
    case normal
    /// Presses, releases and drags (1002).
    case buttonEvent
    /// Every motion (1003).
    case anyEvent
}

/// How mouse reports are encoded.
public enum MouseEncoding: Hashable, Sendable {
    /// The legacy single-byte encoding.
    case legacy
    /// UTF-8 coordinates (1005).
    case utf8
    /// SGR (1006).
    case sgr
}

/// The cursor's shape and blinking.
public struct TerminalCursorStyle: Hashable, Sendable {
    /// The cursor shape.
    public enum Shape: Hashable, Sendable {
        /// A filled cell.
        case block
        /// A vertical bar.
        case bar
        /// A line under the cell.
        case underline
    }

    /// The shape.
    public var shape: Shape
    /// Whether the cursor blinks.
    public var blinking: Bool

    /// Creates a style.
    public init(shape: Shape, blinking: Bool) {
        self.shape = shape
        self.blinking = blinking
    }
}

/// The modes a program has switched on.
public struct TerminalModes: Hashable, Sendable {
    /// DECCKM: arrows send application sequences.
    public var applicationCursorKeys: Bool
    /// DECKPAM: the keypad sends application sequences.
    public var applicationKeypad: Bool
    /// Mode 2004: pastes are bracketed.
    public var bracketedPaste: Bool
    /// Mode 1004: focus changes are reported.
    public var focusEvents: Bool
    /// Modes 47/1047/1049: the alternate screen is showing.
    public var alternateScreen: Bool
    /// DECTCEM (25): the cursor is visible.
    public var cursorVisible: Bool
    /// DECAWM (7): text wraps at the last column.
    public var autowrap: Bool
    /// DECOM (6): cursor addressing is relative to the scroll region.
    public var originMode: Bool
    /// The mouse events reported.
    public var mouseTracking: MouseTracking
    /// The mouse report encoding.
    public var mouseEncoding: MouseEncoding
    /// The cursor shape and blinking.
    public var cursorStyle: TerminalCursorStyle

    /// The power-on state: autowrap on, cursor visible and a steady block (`TRM-F`); everything else off.
    public init() {
        applicationCursorKeys = false
        applicationKeypad = false
        bracketedPaste = false
        focusEvents = false
        alternateScreen = false
        cursorVisible = true
        autowrap = true
        originMode = false
        mouseTracking = .off
        mouseEncoding = .legacy
        cursorStyle = TerminalCursorStyle(shape: .block, blinking: false)
    }
}

/// The cursor in viewport coordinates.
public struct TerminalCursor: Hashable, Sendable {
    /// The viewport row.
    public var row: Int
    /// The viewport column.
    public var col: Int
    /// Whether the cursor is shown.
    public var visible: Bool
    /// Whether the next character wraps first (the cursor sits past the last column).
    public var pendingWrap: Bool
}
