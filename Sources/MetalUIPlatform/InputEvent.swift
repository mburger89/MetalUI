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

/// The phase of a trackpad gesture or a scroll (ruling `CI-I` item 1): AppKit's
/// `NSEvent.Phase`, one value per event. `.none` where the platform reports no
/// phase — a wheel mouse, and every event on SDL.
public enum InputPhase: Sendable, Hashable {
    /// No phase: the event is not part of a gesture the platform tracks.
    case none
    /// A touch rests on the trackpad and a gesture may begin.
    case mayBegin
    /// The gesture's first event.
    case began
    /// The gesture continues.
    case changed
    /// The gesture's last event.
    case ended
    /// The system cancelled the gesture.
    case cancelled
}

/// A pointer press, release or move.
public struct MouseEvent: Sendable {
    /// The pointer's position in window points, y down.
    public var position: Point<Pixels>
    /// The modifier keys held.
    public var modifiers: Modifiers
    /// The click count: 2 for the second press of a double click.
    public var clickCount: Int
    /// The button, in AppKit's numbering (ruling `CI-E` item 1): 0 primary, 1
    /// secondary, 2 middle, 3 back, 4 forward, and so on. The primary and
    /// secondary cases of `InputEvent` carry 0 and 1 by construction on every
    /// platform; `Window` reads it only on the `other…` cases.
    public var buttonNumber: Int
    /// A mouse event at `position`.
    public init(position: Point<Pixels>, modifiers: Modifiers = [], clickCount: Int = 1,
                buttonNumber: Int = 0) {
        self.position = position; self.modifiers = modifiers; self.clickCount = clickCount
        self.buttonNumber = buttonNumber
    }
}

/// A scroll-wheel or trackpad scroll.
public struct ScrollEvent: Sendable {
    /// The pointer's position in window points.
    public var position: Point<Pixels>
    /// How far to scroll, in points on each axis — a non-precise device's lines
    /// × 10 on both platforms (`isPrecise` says which). Never transformed by
    /// render effects: it is the device's motion (ruling `CI-I` item 1).
    public var delta: Point<Pixels>
    /// The modifier keys held.
    public var modifiers: Modifiers
    /// The trackpad gesture's phase (`NSEvent.phase`); `.none` for a wheel
    /// mouse, for momentum events, and on SDL (ruling `CI-I` items 1 and 6).
    public var phase: InputPhase
    /// The momentum phase (`NSEvent.momentumPhase`): not `.none` while the
    /// system coasts after the fingers lift; `.none` on SDL.
    public var momentumPhase: InputPhase
    /// Whether `delta` came from a precise device (a trackpad, a Magic Mouse)
    /// in points; `false` for a wheel mouse's lines × 10, and always on SDL.
    public var isPrecise: Bool
    /// The pointer in the receiving element's local space, render effects
    /// undone (ruling `CI-I` item 1). At the platform seam and in
    /// `Window.onInput` it equals `position`.
    public var location: Point<Pixels>
    /// Whether this is a momentum event: `momentumPhase != .none`. Honouring
    /// this is what makes scrolling feel native rather than web-like (spec
    /// 8.2). Assignable (ruling `CI-V` item 1): `true` marks a `.none` momentum
    /// phase `.changed` and keeps one already under way; `false` sets `.none`.
    public var isMomentum: Bool {
        get { momentumPhase != .none }
        set {
            if !newValue { momentumPhase = .none } else if momentumPhase == .none { momentumPhase = .changed }
        }
    }
    /// When the event occurred, on the same clock as `CADisplayLink.timestamp`
    /// (both trace to `mach_absolute_time`) — `NSEvent.timestamp` on AppKit.
    /// `Window.applyScroll` stamps `ScrollState.lastScrollTime` from this
    /// rather than from the display link's last tick, because the link pauses
    /// while the window is clean (spec §4.4): a wheel event arriving after an
    /// idle period would otherwise be stamped with a stale tick and the fade
    /// ramp would compute an `age` large enough to suppress the indicator on
    /// the very frame that should show it.
    public var timestamp: Double
    /// A scroll event at `position` by `delta`: no gesture phase, a precise
    /// delta, and a momentum phase of `.changed` when `isMomentum` (the
    /// spelling before ruling `CI-I`, meaning unchanged).
    public init(position: Point<Pixels>, delta: Point<Pixels>,
                modifiers: Modifiers = [], isMomentum: Bool = false, timestamp: Double = 0) {
        self.init(position: position, delta: delta, modifiers: modifiers, phase: .none,
                  momentumPhase: isMomentum ? .changed : .none, isPrecise: true, timestamp: timestamp)
    }
    /// A scroll event with every field the platforms fill (ruling `CI-I` item
    /// 1); `location` is `position`.
    public init(position: Point<Pixels>, delta: Point<Pixels>, modifiers: Modifiers = [],
                phase: InputPhase, momentumPhase: InputPhase, isPrecise: Bool, timestamp: Double) {
        self.position = position; self.delta = delta
        self.modifiers = modifiers
        self.phase = phase; self.momentumPhase = momentumPhase; self.isPrecise = isPrecise
        self.location = position
        self.timestamp = timestamp
    }
}

/// One step of a trackpad pinch (ruling `CI-J` item 1): AppKit's
/// `magnify(with:)`, SDL's `SDL_EVENT_PINCH_*`.
public struct MagnifyEvent: Sendable {
    /// The pointer's position in window points (on SDL, which gives a pinch
    /// none, the window's last pointer position — `CI-K` item 2).
    public var position: Point<Pixels>
    /// **This event's** additive delta (`NSEvent.magnification`): +0.1 is ten
    /// percent larger; a gesture's magnification is 1 plus the sum (`CI-C`).
    public var magnification: Double
    /// The gesture's phase.
    public var phase: InputPhase
    /// The modifier keys held.
    public var modifiers: Modifiers
    /// When the event occurred, on `ScrollEvent.timestamp`'s clock.
    public var timestamp: Double
    /// A pinch step at `position` by `magnification`.
    public init(position: Point<Pixels>, magnification: Double, phase: InputPhase,
                modifiers: Modifiers = [], timestamp: Double = 0) {
        self.position = position; self.magnification = magnification; self.phase = phase
        self.modifiers = modifiers; self.timestamp = timestamp
    }
}

/// One step of a trackpad rotation (ruling `CI-J` item 1): AppKit's
/// `rotate(with:)`. SDL has none (`CI-K` item 3).
public struct RotateEvent: Sendable {
    /// The pointer's position in window points.
    public var position: Point<Pixels>
    /// **This event's** delta in degrees, **clockwise-positive** on screen
    /// (y down): the negative of AppKit's `NSEvent.rotation`, negated once at
    /// the seam (`CI-C` item 2, probe `Q1`).
    public var rotation: Double
    /// The gesture's phase.
    public var phase: InputPhase
    /// The modifier keys held.
    public var modifiers: Modifiers
    /// When the event occurred, on `ScrollEvent.timestamp`'s clock.
    public var timestamp: Double
    /// A rotation step at `position` by `rotation` degrees clockwise.
    public init(position: Point<Pixels>, rotation: Double, phase: InputPhase,
                modifiers: Modifiers = [], timestamp: Double = 0) {
        self.position = position; self.rotation = rotation; self.phase = phase
        self.modifiers = modifiers; self.timestamp = timestamp
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
    /// A drag from outside the window — another application, the Finder, or
    /// this application's own drag handed to the platform and returning
    /// (ruling `DN-C`). `onInput`'s `Bool` answers "an accepting destination is
    /// under the pointer" for `.entered`/`.moved` and "a destination took the
    /// drop" for `.performed`.
    ///
    /// **Migration** (`DN-C` item 3): an exhaustive `switch` over `InputEvent`
    /// outside this package adds a `.drop` case or a `default:`.
    case drop(DropEvent)
    /// A secondary-button press (ruling `MN-B`): the right button on every
    /// platform, and on AppKit a control-modified primary press too (`MN-AC`
    /// item 1). It runs no `onClick`, gesture or drag; `Window` hands it only
    /// to the context-menu stage (divergence 110).
    ///
    /// **Migration** (`MN-B` item 1): an exhaustive `switch` over `InputEvent`
    /// outside this package adds the three menu cases or a `default:`.
    case rightMouseDown(MouseEvent)
    /// The release of a secondary press (`MN-B`).
    case rightMouseUp(MouseEvent)
    /// A natively presented menu's outcome (ruling `MN-C` item 4): the item
    /// chosen from the `PlatformMenu` whose token it names, or `nil` for a
    /// dismissal. Delivered after `PlatformWindow.presentMenu(_:at:)` returned,
    /// never inside it.
    case menuAction(MenuActionEvent)
    /// The pointer left the window (ruling `SV-N` item 7): AppKit's tracking
    /// area's `mouseExited`, SDL's `SDL_EVENT_WINDOW_MOUSE_LEAVE`. `Window`
    /// forgets the pointer's position, so nothing reads as hovered.
    ///
    /// **Migration** (`SV-B` item 5): an exhaustive `switch` over `InputEvent`
    /// outside this package adds the three platform-services cases or a
    /// `default:`.
    case pointerExited
    /// A file dialog's answer (ruling `SV-B` item 2), delivered after
    /// `PlatformWindow.presentFileDialog(_:)` returned, never inside it.
    case fileDialogResult(FileDialogResultEvent)
    /// A natively shown alert's answer (ruling `SV-B` item 2), delivered after
    /// `PlatformWindow.presentAlert(_:)` returned, never inside it.
    case alertResult(AlertResultEvent)
    /// A native toolbar control's outcome (ruling `MD-J` item 4): the
    /// `PlatformToolbarItem` it names and what its control did. Delivered by a
    /// platform whose `PlatformWindow.setToolbar(_:)` answered `true`, from the
    /// control's own action, never inside `setToolbar`. `Window` runs the item
    /// under `StateDispatch` against the last evaluated toolbar; an unknown id
    /// runs nothing.
    ///
    /// **Migration** (`MD-J` item 6): an exhaustive `switch` over `InputEvent`
    /// outside this package adds a `.toolbarAction` case or a `default:`.
    case toolbarAction(ToolbarActionEvent)
    /// Pointer motion with the secondary button held (ruling `CI-E` item 1) —
    /// on AppKit a control-press's drag too (`CI-E` item 3). Like the secondary
    /// press it never drags a primary-style control (`MN-B`); only a
    /// `DragGesture` naming the secondary button follows it (`CI-F`).
    ///
    /// **Migration** (`CI-E` item 5): an exhaustive `switch` over `InputEvent`
    /// outside this package adds `.rightMouseDragged`, `.otherMouseDown`,
    /// `.otherMouseDragged`, `.otherMouseUp`, `.magnify` and `.rotate` arms (or
    /// a `default:`).
    case rightMouseDragged(MouseEvent)
    /// A press of any button but the primary and the secondary (ruling `CI-E`
    /// item 1): the middle button (`buttonNumber` 2), back (3), forward (4)….
    case otherMouseDown(MouseEvent)
    /// Pointer motion with an other button held (`CI-E` item 1).
    case otherMouseDragged(MouseEvent)
    /// The release of an other button (`CI-E` item 1).
    case otherMouseUp(MouseEvent)
    /// A trackpad pinch step (ruling `CI-J` item 1).
    case magnify(MagnifyEvent)
    /// A trackpad rotation step (ruling `CI-J` item 1); never on SDL.
    case rotate(RotateEvent)
    // Reserved: focusMove (tvOS), spatial (visionOS). See spec 3.2.
}

/// The outcome of a natively presented menu (ruling `MN-C` item 4).
public struct MenuActionEvent: Sendable, Equatable {
    /// The presented `PlatformMenu`'s `token`.
    public var menu: Int
    /// The chosen item's `PlatformMenuItem.id`; `nil` when the menu was
    /// dismissed with no choice.
    public var item: Int?

    /// The outcome of the menu `menu`: `item` chosen, or none.
    public init(menu: Int, item: Int?) {
        self.menu = menu
        self.item = item
    }
}

// MARK: - Drag and drop (ruling `DN-C`)

/// A pasteboard type at the platform seam: a uniform type identifier and the
/// identifiers it conforms to, transitively (ruling `DN-B` item 4). The seam
/// carries no Foundation type, so this is MetalUI's `ContentType` reduced to
/// strings.
public struct PasteboardType: Sendable, Hashable {
    /// The uniform type identifier, e.g. `public.utf8-plain-text`.
    public var identifier: String
    /// Every identifier this type conforms to, transitively; never contains
    /// `identifier` itself.
    public var conformsTo: [String]

    /// A pasteboard type named `identifier`, conforming to `conformsTo`.
    public init(identifier: String, conformsTo: [String] = []) {
        self.identifier = identifier
        self.conformsTo = conformsTo
    }

    /// Whether this type is `identifier` or conforms to it.
    public func satisfies(_ identifier: String) -> Bool {
        self.identifier == identifier || conformsTo.contains(identifier)
    }
}

/// One representation of an outgoing drag's payload: its type and its bytes
/// (ruling `DN-B` item 4). Handed to `PlatformWindow.beginExternalDrag`.
public struct DragRepresentation: Sendable, Equatable {
    /// The representation's type.
    public var type: PasteboardType
    /// The payload exported as `type`.
    public var bytes: [UInt8]

    /// A representation of `bytes` as `type`.
    public init(type: PasteboardType, bytes: [UInt8]) {
        self.type = type
        self.bytes = bytes
    }
}

/// One dragged item offered to a window: the types it can be read as, most
/// preferred first, and a loader that reads one of them (ruling `DN-C`).
///
/// **`load` is lazy on purpose** (`DN-L`): the window calls it only for a type
/// a destination imports, so a large file dragged over a text field reads
/// nothing it does not deliver.
public struct DropItem: Sendable {
    /// The types this item is offered as, most preferred first.
    public var types: [PasteboardType]
    /// Reads the item as the type named `identifier`; `nil` when it cannot.
    public var load: @MainActor @Sendable (_ identifier: String) -> [UInt8]?

    /// An item offered as `types`, read through `load`.
    public init(types: [PasteboardType], load: @escaping @MainActor @Sendable (_ identifier: String) -> [UInt8]?) {
        self.types = types
        self.load = load
    }
}

/// One step of a drag arriving from outside the window (ruling `DN-C` item 1).
/// Positions are window points, y down, as `MouseEvent.position`.
public enum DropEvent: Sendable {
    /// The drag entered the window. `items` is `nil` when the platform cannot
    /// know the payload until it is dropped (SDL, ruling `DN-M`).
    case entered(position: Point<Pixels>, items: [DropItem]?)
    /// The drag moved within the window.
    case moved(position: Point<Pixels>)
    /// The drag left the window, or was cancelled.
    case exited
    /// The drag was dropped at `position`, carrying `items`.
    case performed(position: Point<Pixels>, items: [DropItem])
}
