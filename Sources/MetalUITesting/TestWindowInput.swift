import MetalUI

// Input by point (ruling `HT-F`): XCUITest's action names where it has one,
// gpui's `simulate_*` shapes where it has none. Every event goes through the
// platform window's `onInput` — the closure `Window` installed — stamped
// ``TestWindow/now``; every verb but `send(_:)` then draws one frame
// (`HT-E` item 2).

extension TestWindow {
    // MARK: Pointer

    /// A primary click at `point` (window points): the pointer moves there
    /// first if it is elsewhere, then a press and a release, then one frame.
    public func click(at point: Point<Pixels>, modifierFlags: EventModifiers = []) {
        // STUB
    }

    /// Two primary clicks at `point`, the second with click count 2, then one
    /// frame.
    public func doubleClick(at point: Point<Pixels>, modifierFlags: EventModifiers = []) {
        // STUB
    }

    /// A secondary click at `point`, then one frame — what opens a context
    /// menu; it never presses, taps or focuses (`MN-B`).
    public func rightClick(at point: Point<Pixels>, modifierFlags: EventModifiers = []) {
        // STUB
    }

    /// A click of another button (`.middle` by default) at `point`, then one
    /// frame.
    public func otherClick(at point: Point<Pixels>, button: MouseButton = .middle,
                           modifierFlags: EventModifiers = []) {
        // STUB
    }

    /// Moves the pointer to `point`, then one frame.
    public func hover(at point: Point<Pixels>) {
        // STUB
    }

    /// The pointer leaves the window, then one frame.
    public func exitPointer() {
        // STUB
    }

    /// A wheel or trackpad scroll by (`dx`, `dy`) at `point`, then one frame.
    /// Deltas are the platform's: positive `dy` scrolls content down (toward
    /// its top), as AppKit's `scrollingDeltaY` does.
    public func scroll(at point: Point<Pixels>, byDeltaX dx: Float, deltaY dy: Float,
                       modifierFlags: EventModifiers = []) {
        // STUB
    }

    /// XCUITest's press-and-drag: a press at `point`, held for `seconds`
    /// (the clock advances, so a long press matures), dragged to `end` in 8
    /// steps one frame apart, released, then one frame.
    public func click(at point: Point<Pixels>, forDuration seconds: Double, thenDragTo end: Point<Pixels>) {
        // STUB
    }

    /// A drag of `button` from `start` to `end`: a press, `steps` drag events
    /// each followed by one frame 1/60 s on, a release, then one frame.
    public func drag(from start: Point<Pixels>, to end: Point<Pixels>, steps: Int = 8,
                     button: MouseButton = .primary, modifierFlags: EventModifiers = []) {
        // STUB
    }

    /// A trackpad pinch at `point` growing the magnification by
    /// `magnification − 1` in `steps` equal steps: `.began`, the steps, then
    /// `.ended`, each followed by one frame.
    public func magnify(at point: Point<Pixels>, by magnification: Double, steps: Int = 4) {
        // STUB
    }

    /// A trackpad rotation at `point` by `degrees` (clockwise-positive on
    /// screen) in `steps` equal steps: `.began`, the steps, then `.ended`,
    /// each followed by one frame.
    public func rotate(at point: Point<Pixels>, byDegrees degrees: Double, steps: Int = 4) {
        // STUB
    }

    /// A drag from outside the window dropped at `point`: entered, moved,
    /// performed, then one frame.
    public func drop(_ items: [DropItem], at point: Point<Pixels>) {
        // STUB
    }

    // MARK: Keyboard

    /// Types `text`, one key per `Character`, then one frame. While a text
    /// field has the caret each arrives as committed text (`.textInput`),
    /// otherwise as a key press and release — as AppKit and SDL route them
    /// (ruling `HT-F` item 3). An uppercase letter is typed with Shift.
    public func typeText(_ text: String) {
        // STUB
    }

    /// One key with `modifierFlags`, then one frame. A letter with Shift is
    /// delivered uppercased in both `characters` and
    /// `charactersIgnoringModifiers`, as AppKit delivers it.
    public func typeKey(_ key: KeyEquivalent, modifierFlags: EventModifiers = []) {
        // STUB
    }

    /// Holds `modifiers` (and only them) from now on: a `.modifiersChanged`
    /// event, then one frame. Later mouse and key events carry them.
    public func pressModifiers(_ modifiers: EventModifiers) {
        // STUB
    }

    // MARK: Delivery

    /// Whether a text field has the caret: the window's last text input area
    /// is non-`nil`.
    var isTextInputActive: Bool {
        guard let last = platformWindow.textInputAreas.last else { return false }
        return last != nil
    }

    /// One key: committed text while a field has the caret and the key
    /// produces text with no ⌘ or ⌃ (`MetalHostView.keyDown`, SDL's
    /// `producesText`), else a key press and release.
    func deliverKey(_ characters: String, modifiers: EventModifiers) {
        if isTextInputActive, Self.producesText(characters),
           !modifiers.contains(.command), !modifiers.contains(.control) {
            send(.textInput(characters))
            return
        }
        let event = KeyEvent(charactersIgnoringModifiers: characters, characters: characters,
                             modifiers: modifiers, timestamp: now)
        send(.keyDown(event))
        send(.keyUp(event))
    }

    /// Whether `characters` is text: no control character and nothing in the
    /// function-key range AppKit uses for arrows, Home, End and the rest.
    static func producesText(_ characters: String) -> Bool {
        guard !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            !(scalar.value < 0x20 || scalar.value == 0x7f || (0xf700...0xf8ff).contains(scalar.value))
        }
    }

    /// A pointer event at `point` carrying the held modifiers and `modifierFlags`.
    func mouse(_ point: Point<Pixels>, _ modifierFlags: EventModifiers, clickCount: Int = 1,
               buttonNumber: Int = 0) -> MouseEvent {
        MouseEvent(position: point, modifiers: heldModifiers.union(modifierFlags),
                   clickCount: clickCount, buttonNumber: buttonNumber)
    }

    /// A real pointer travels: a move to `point` when it is not already there.
    func moveIfNeeded(to point: Point<Pixels>) {
        guard pointer != point else { return }
        pointer = point
        send(.mouseMoved(mouse(point, [])))
    }

    func deliverClick(at point: Point<Pixels>, clickCount: Int, modifierFlags: EventModifiers) {
        let event = mouse(point, modifierFlags, clickCount: clickCount)
        send(.mouseDown(event))
        send(.mouseUp(event))
    }

    static func interpolate(_ a: Point<Pixels>, _ b: Point<Pixels>, _ t: Float) -> Point<Pixels> {
        Point(x: Pixels(a.x.value + (b.x.value - a.x.value) * t),
              y: Pixels(a.y.value + (b.y.value - a.y.value) * t))
    }

    static func press(_ button: MouseButton, _ event: MouseEvent) -> InputEvent {
        switch button {
        case .primary: .mouseDown(event)
        case .secondary: .rightMouseDown(event)
        default: .otherMouseDown(event)
        }
    }

    static func drag(_ button: MouseButton, _ event: MouseEvent) -> InputEvent {
        switch button {
        case .primary: .mouseDragged(event)
        case .secondary: .rightMouseDragged(event)
        default: .otherMouseDragged(event)
        }
    }

    static func release(_ button: MouseButton, _ event: MouseEvent) -> InputEvent {
        switch button {
        case .primary: .mouseUp(event)
        case .secondary: .rightMouseUp(event)
        default: .otherMouseUp(event)
        }
    }
}
