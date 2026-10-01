import MetalUICore

/// The modifier keys held during an event.
public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    /// A modifier set from its raw bits; prefer the named statics.
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    /// Shift.
    public static let shift   = Modifiers(rawValue: 1 << 0)
    /// Control.
    public static let control = Modifiers(rawValue: 1 << 1)
    /// Option (Alt).
    public static let option  = Modifiers(rawValue: 1 << 2)
    /// Command on Apple platforms; the Super/Windows key elsewhere.
    public static let command = Modifiers(rawValue: 1 << 3)
}

/// A pointer press, release or move.
public struct MouseEvent: Sendable {
    /// The pointer's position in window points, y down.
    public var position: Point<Pixels>
    /// The modifier keys held.
    public var modifiers: Modifiers
    /// The click count: 2 for the second press of a double click.
    public var clickCount: Int
    /// A mouse event at `position`.
    public init(position: Point<Pixels>, modifiers: Modifiers = [], clickCount: Int = 1) {
        self.position = position; self.modifiers = modifiers; self.clickCount = clickCount
    }
}

/// A scroll-wheel or trackpad scroll.
public struct ScrollEvent: Sendable {
    /// The pointer's position in window points.
    public var position: Point<Pixels>
    /// How far to scroll, in points on each axis.
    public var delta: Point<Pixels>
    /// The modifier keys held.
    public var modifiers: Modifiers
    /// Trackpad phase. Honouring this is what makes scrolling feel native
    /// rather than web-like (spec 8.2).
    public var isMomentum: Bool
    /// When the event occurred, on the same clock as `CADisplayLink.timestamp`
    /// (both trace to `mach_absolute_time`) — `NSEvent.timestamp` on AppKit.
    /// `Window.applyScroll` stamps `ScrollState.lastScrollTime` from this
    /// rather than from the display link's last tick, because the link pauses
    /// while the window is clean (spec §4.4): a wheel event arriving after an
    /// idle period would otherwise be stamped with a stale tick and the fade
    /// ramp would compute an `age` large enough to suppress the indicator on
    /// the very frame that should show it.
    public var timestamp: Double
    /// A scroll event at `position` by `delta`.
    public init(position: Point<Pixels>, delta: Point<Pixels>,
                modifiers: Modifiers = [], isMomentum: Bool = false, timestamp: Double = 0) {
        self.position = position; self.delta = delta
        self.modifiers = modifiers; self.isMomentum = isMomentum
        self.timestamp = timestamp
    }
}

/// A key press or release.
public struct KeyEvent: Sendable {
    /// Matching uses this, not a physical key code — physical matching is the
    /// long-standing source of Dvorak and AZERTY breakage (spec 8.3).
    public var charactersIgnoringModifiers: String
    /// The characters the key produced with its modifiers applied.
    public var characters: String
    /// The modifier keys held.
    public var modifiers: Modifiers
    /// Whether this is an auto-repeat of a held key.
    public var isRepeat: Bool
    /// When the keystroke occurred, on the same clock as `ScrollEvent.timestamp`
    /// (`NSEvent.timestamp` on AppKit).
    ///
    /// **This exists for §8.3's two-stroke timeout, and it has NO default
    /// value on purpose.** The timeout asks how old a pending prefix is, and
    /// the obvious other sources are both wrong: a display-link tick freezes
    /// while the link is paused — the bug the clipping milestone shipped, and
    /// which `ScrollEvent.timestamp` above exists to avoid — and a wall clock
    /// read at dispatch time measures the *handler's* schedule rather than the
    /// user's typing.
    ///
    /// **The missing default is what makes the timeout testable at all.** A
    /// defaulted `timestamp` would let two events be constructed at the same
    /// instant, giving a prefix an age of zero that never expires, so a
    /// two-stroke timeout test would pass against a timeout that was never
    /// implemented (taxonomy shape 1). Every construction site states one; that
    /// churn is the point.
    public var timestamp: Double
    /// A key event; every construction site states its timestamp.
    public init(charactersIgnoringModifiers: String, characters: String,
                modifiers: Modifiers = [], isRepeat: Bool = false,
                timestamp: Double) {
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.characters = characters
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.timestamp = timestamp
    }
}

/// An input method's uncommitted ("marked") text (ruling TI-A): shown at the
/// caret until committed through `.textInput`, or cancelled with an empty
/// composition. `selection` is in Character offsets into `text`.
public struct TextComposition: Sendable, Equatable {
    /// The marked text.
    public var text: String
    /// The selection within the marked text, in Character offsets.
    public var selection: Range<Int>

    /// A composition of `text` with `selection`.
    public init(text: String, selection: Range<Int>) {
        self.text = text
        self.selection = selection
    }

    /// No composition in progress.
    public static let none = TextComposition(text: "", selection: 0..<0)
}

/// One input event a platform window delivers to its `Window`.
public enum InputEvent: Sendable {
    case mouseDown(MouseEvent)
    case mouseUp(MouseEvent)
    case mouseMoved(MouseEvent)
    /// Pointer motion with the primary button held (ruling TI-A).
    case mouseDragged(MouseEvent)
    case scrollWheel(ScrollEvent)
    case keyDown(KeyEvent)
    case keyUp(KeyEvent)
    case modifiersChanged(Modifiers)
    /// Committed text — a typed character after the keyboard layout and dead
    /// keys, or an input method's commit (ruling TI-A). Sent only while text
    /// input is active (`PlatformWindow.setTextInputArea`).
    case textInput(String)
    /// An input method's marked text; ``TextComposition/none`` ends it.
    case textComposition(TextComposition)
    // Reserved: focusMove (tvOS), spatial (visionOS). See spec 3.2.
}
