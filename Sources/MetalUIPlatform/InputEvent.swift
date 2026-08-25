import MetalUICore

public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let shift   = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option  = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
}

public struct MouseEvent: Sendable {
    public var position: Point<Pixels>
    public var modifiers: Modifiers
    public var clickCount: Int
    public init(position: Point<Pixels>, modifiers: Modifiers = [], clickCount: Int = 1) {
        self.position = position; self.modifiers = modifiers; self.clickCount = clickCount
    }
}

public struct ScrollEvent: Sendable {
    public var position: Point<Pixels>
    public var delta: Point<Pixels>
    public var modifiers: Modifiers
    /// Trackpad phase. Honouring this is what makes scrolling feel native
    /// rather than web-like (spec 8.2).
    public var isMomentum: Bool
    public init(position: Point<Pixels>, delta: Point<Pixels>,
                modifiers: Modifiers = [], isMomentum: Bool = false) {
        self.position = position; self.delta = delta
        self.modifiers = modifiers; self.isMomentum = isMomentum
    }
}

public struct KeyEvent: Sendable {
    /// Matching uses this, not a physical key code — physical matching is the
    /// long-standing source of Dvorak and AZERTY breakage (spec 8.3).
    public var charactersIgnoringModifiers: String
    public var characters: String
    public var modifiers: Modifiers
    public var isRepeat: Bool
    public init(charactersIgnoringModifiers: String, characters: String,
                modifiers: Modifiers = [], isRepeat: Bool = false) {
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.characters = characters
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
}

public enum InputEvent: Sendable {
    case mouseDown(MouseEvent)
    case mouseUp(MouseEvent)
    case mouseMoved(MouseEvent)
    case scrollWheel(ScrollEvent)
    case keyDown(KeyEvent)
    case keyUp(KeyEvent)
    case modifiersChanged(Modifiers)
    // Reserved: focusMove (tvOS), spatial (visionOS). See spec 3.2.
}
