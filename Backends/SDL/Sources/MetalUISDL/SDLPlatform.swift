import MetalUICore
import MetalUIPlatform
import SDLBridge

public struct SDLPlatformError: Error, CustomStringConvertible {
    public let description: String
    init(_ what: String) { description = "\(what): \(String(cString: replay_error()))" }
}

/// MetalUI's `Platform` over SDL3 (ruling SP-A): windows, input, frame ticks,
/// appearance and close on Linux, Windows and macOS, each window drawing
/// through an ``SDLWindowRenderer``.
@MainActor
public final class SDLPlatform: Platform {
    private var windows: [UInt32: SDLWindow] = [:]
    private let hidden: Bool
    private var running = false

    /// - Parameter hiddenWindows: open windows hidden — for tests, which need
    ///   a real window and its events but nothing on screen.
    public init(hiddenWindows: Bool = false) throws {
        guard mui_platform_init() else { throw SDLPlatformError("SDL_Init") }
        hidden = hiddenWindows
    }

    public func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
        try openSDLWindow(title: title, size: size)
    }

    /// ``openWindow(title:size:)``, typed.
    public func openSDLWindow(title: String, size: Size<Pixels>) throws -> SDLWindow {
        guard let handle = mui_window_create(title, Int32(size.width.value.rounded()),
                                             Int32(size.height.value.rounded()), hidden) else {
            throw SDLPlatformError("SDL_CreateWindow")
        }
        let window: SDLWindow
        do {
            window = try SDLWindow(handle: OpaquePointer(handle))
        } catch {
            mui_window_destroy(handle)
            throw error
        }
        windows[window.id] = window
        return window
    }

    /// Runs until every window has closed or ``stop()`` is called: events are
    /// dispatched, and while any window's display link is running each frame
    /// ticks it (the swapchain acquire paces the loop to the display); with
    /// every link paused the loop sleeps in `SDL_WaitEvent`.
    public func run() { run(maxIterations: nil) }

    /// ``run()`` for at most `maxIterations` passes — so a test of the loop
    /// fails by count, not by hanging, when the loop would never end.
    func run(maxIterations: Int?) {
        running = true
        var iterations = 0
        while running && !windows.isEmpty {
            iterations += 1
            if let maxIterations, iterations > maxIterations { break }
            if windows.values.contains(where: { $0.linkRunning }) {
                pumpEvents()
                let now = mui_now()
                for window in windows.values where window.linkRunning { window.tick(now) }
            } else {
                var event = MUIEvent()
                if mui_wait_event(&event, 250) { dispatch(event) }
                pumpEvents()
            }
        }
        running = false
    }

    /// Windows open and not yet closed.
    var openWindowCount: Int { windows.count }

    /// Ends ``run()`` after the current iteration.
    public func stop() { running = false }

    /// Dispatches every pending event without waiting — one run-loop pass
    /// minus the ticks. Tests drive the platform with it.
    public func pumpEvents() {
        var event = MUIEvent()
        while mui_poll_event(&event) { dispatch(event) }
    }

    private func dispatch(_ event: MUIEvent) {
        switch Int(event.kind) {
        case Int(MUI_EVENT_QUIT):
            stop()
        case Int(MUI_EVENT_THEME):
            for window in windows.values { window.appearanceChanged() }
        case Int(MUI_EVENT_CLOSE):
            guard let window = windows.removeValue(forKey: event.window_id) else { return }
            window.close()
        case Int(MUI_EVENT_ACCESSIBILITY):
            windows[event.window_id]?.deliverAccessibilityRequests()
        default:
            windows[event.window_id]?.handle(event)
        }
    }
}

/// One SDL window as a MetalUI `PlatformWindow` (ruling SP-A).
@MainActor
public final class SDLWindow: PlatformWindow {
    private let handle: OpaquePointer
    let id: UInt32
    /// Optional only so `deinit` can release it — and the window's GPU
    /// claim with it — before the window itself is destroyed.
    private var windowRenderer: SDLWindowRenderer?
    private var displayLinkTick: ((Double) -> Void)?
    private var displayLinkPaused = false
    private var closed = false
    /// Optional for the same reason as `windowRenderer`: released before the
    /// window it subclasses is destroyed.
    private var accessKit: AccessKitAdapter?
    private let accessKitIDs = AccessKitIDs()
    /// Requests that arrived before `Window` installed its handler — parked,
    /// as the AppKit bridge parks `.activate` (AB-B).
    private var parkedAccessibilityRequests: [AccessibilityRequest] = []

    init(handle: OpaquePointer) throws {
        self.handle = handle
        id = mui_window_id(UnsafeMutableRawPointer(handle))
        windowRenderer = try SDLWindowRenderer(window: handle)
        let raw = UnsafeMutableRawPointer(handle)
        accessKit = AccessKitAdapter(windowID: id, title: String(cString: mui_window_title(raw)),
                                     nativeWindow: mui_window_native_handle(raw))
        updateAccessibilityWindowBounds()
    }

    public var renderer: any WindowRenderer { windowRenderer! }

    var rawHandle: UnsafeMutableRawPointer { UnsafeMutableRawPointer(handle) }

    /// Points, as `PlatformWindow` wants them.
    public var contentSize: Size<Pixels> {
        var width: Int32 = 0, height: Int32 = 0
        mui_window_size(UnsafeMutableRawPointer(handle), &width, &height)
        return Size(width: Pixels(Float(width)), height: Pixels(Float(height)))
    }

    /// Device pixels per point (`SDL_GetWindowPixelDensity`).
    public var scaleFactor: Float { mui_window_pixel_density(UnsafeMutableRawPointer(handle)) }

    public var title: String {
        get { String(cString: mui_window_title(UnsafeMutableRawPointer(handle))) }
        set { _ = mui_window_set_title(UnsafeMutableRawPointer(handle), newValue) }
    }

    /// The system's light or dark theme (`SDL_GetSystemTheme`); SDL has no
    /// per-window appearance.
    public var appearance: Appearance { mui_system_theme() == 1 ? .dark : .light }

    public var onInput: ((InputEvent) -> Bool)?
    public var onResize: ((Size<Pixels>, Float) -> Void)?
    public var onAppearanceChange: ((Appearance) -> Void)?
    public var onClose: (() -> Void)?

    /// Called with AccessKit's requests (ruling AX-C): `.activate` when a
    /// screen reader first asks for the tree, then the actions it performs.
    /// Delivered on the main thread from ``SDLPlatform/pumpEvents()``.
    public var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)? {
        didSet { deliverAccessibilityRequests() }
    }

    /// Hands the tree to AccessKit — AT-SPI on Linux, UI Automation on
    /// Windows, NSAccessibility on macOS (ruling AX-B).
    public func publishAccessibilityTree(_ tree: AccessibilityTree) {
        accessKit?.publish(.translate(tree, title: title, scale: Double(scaleFactor), ids: accessKitIDs))
    }

    /// Whether AccessKit's platform adapter exists for this window.
    public var isAccessibilityConnected: Bool { accessKit?.isConnected ?? false }

    /// AccessKit's own rendering of the tree it holds — Linux only, and only
    /// once a screen reader (or ``simulateAccessibilityActivation()``) asked.
    var accessKitDebugDescription: String? { accessKit?.debugDescription }

    /// Queues requests as AccessKit's callbacks would — for tests, which have
    /// no screen reader.
    func simulateAccessKitRequest(_ queued: AccessKitAdapter.Queued) { accessKit?.enqueueForTesting(queued) }

    func deliverAccessibilityRequests() {
        if let accessKit {
            for queued in accessKit.drain() {
                switch queued {
                case .activate: parkedAccessibilityRequests.append(.activate)
                case let .action(action, number):
                    if let request = AccessKitSnapshot.request(action, number: number, ids: accessKitIDs) {
                        parkedAccessibilityRequests.append(request)
                    }
                }
            }
        }
        guard let onAccessibilityRequest, !parkedAccessibilityRequests.isEmpty else { return }
        let requests = parkedAccessibilityRequests
        parkedAccessibilityRequests = []
        for request in requests { _ = onAccessibilityRequest(request) }
    }

    /// AT-SPI asks no window handle, so Linux is told where the window is.
    private func updateAccessibilityWindowBounds() {
        var x: Int32 = 0, y: Int32 = 0
        mui_window_position(UnsafeMutableRawPointer(handle), &x, &y)
        let scale = Double(scaleFactor), size = contentSize
        accessKit?.setWindowBounds(x: Double(x) * scale, y: Double(y) * scale,
                                   width: Double(size.width.value) * scale,
                                   height: Double(size.height.value) * scale)
    }

    // MARK: Text input (ruling TI-A)

    /// The caret `setTextInputArea` last set; nil while text input is off.
    private(set) var textInputCaret: Bounds<Pixels>?

    public func setTextInputArea(_ caret: Bounds<Pixels>?) {
        guard caret != textInputCaret else { return }
        textInputCaret = caret
        let raw = UnsafeMutableRawPointer(handle)
        if let caret {
            _ = mui_window_start_text_input(raw, Int32(caret.origin.x.value.rounded(.down)),
                                            Int32(caret.origin.y.value.rounded(.down)),
                                            Int32(max(1, caret.size.width.value.rounded(.up))),
                                            Int32(max(1, caret.size.height.value.rounded(.up))))
        } else {
            _ = mui_window_stop_text_input(raw)
        }
    }

    public func readClipboard() -> String? {
        guard let text = mui_clipboard_text() else { return nil }
        defer { mui_free(text) }
        return String(cString: text)
    }

    public func writeClipboard(_ text: String) { _ = mui_set_clipboard_text(text) }

    /// Whether a key-down is one SDL will also send as `SDL_EVENT_TEXT_INPUT`
    /// — a printable keycode with no control or command — and so, while text
    /// input is on, not a key (ruling TI-A).
    nonisolated static func producesText(keycode: UInt32, modifiers: Modifiers) -> Bool {
        guard modifiers.isDisjoint(with: [.control, .command]) else { return false }
        return keycode >= 0x20 && keycode < 0x7F
    }

    public func startDisplayLink(_ tick: @escaping (Double) -> Void) {
        displayLinkTick = tick
        displayLinkPaused = false
    }

    public func setDisplayLinkPaused(_ paused: Bool) { displayLinkPaused = paused }

    /// Whether the platform should tick this window this pass.
    var linkRunning: Bool { displayLinkTick != nil && !displayLinkPaused && !closed }

    func tick(_ now: Double) { displayLinkTick?(now) }

    /// Shows a window opened hidden.
    public func show() { _ = mui_window_show(UnsafeMutableRawPointer(handle)) }

    func appearanceChanged() { onAppearanceChange?(appearance) }

    func close() {
        closed = true
        onClose?()
    }

    func handle(_ event: MUIEvent) {
        let position = Point(x: Pixels(event.x), y: Pixels(event.y))
        let modifiers = SDLKeys.modifiers(event.modifiers)
        switch Int(event.kind) {
        case Int(MUI_EVENT_RESIZE), Int(MUI_EVENT_EXPOSED):
            updateAccessibilityWindowBounds()
            onResize?(contentSize, scaleFactor)
        case Int(MUI_EVENT_MOUSE_DOWN):
            _ = onInput?(.mouseDown(MouseEvent(position: position, modifiers: modifiers,
                                               clickCount: Int(event.clicks))))
        case Int(MUI_EVENT_MOUSE_UP):
            _ = onInput?(.mouseUp(MouseEvent(position: position, modifiers: modifiers,
                                             clickCount: Int(event.clicks))))
        case Int(MUI_EVENT_MOUSE_MOVE):
            _ = onInput?(.mouseMoved(MouseEvent(position: position, modifiers: modifiers)))
        case Int(MUI_EVENT_MOUSE_DRAG):
            _ = onInput?(.mouseDragged(MouseEvent(position: position, modifiers: modifiers)))
        case Int(MUI_EVENT_TEXT_INPUT):
            guard textInputCaret != nil, let text = event.text else { return }
            _ = onInput?(.textInput(String(cString: text)))
        case Int(MUI_EVENT_TEXT_EDITING):
            guard textInputCaret != nil, let text = event.text else { return }
            _ = onInput?(.textComposition(SDLKeys.composition(String(cString: text),
                                                             start: Int(event.start), length: Int(event.length))))
        case Int(MUI_EVENT_WHEEL):
            _ = onInput?(.scrollWheel(ScrollEvent(position: position,
                                                  delta: SDLKeys.scrollDelta(x: event.dx, y: event.dy),
                                                  modifiers: modifiers, timestamp: event.timestamp)))
        case Int(MUI_EVENT_KEY_DOWN), Int(MUI_EVENT_KEY_UP):
            if textInputCaret != nil, Self.producesText(keycode: event.keycode, modifiers: modifiers) { return }
            let keys = SDLKeys.characters(forKeycode: event.keycode, modifiers: modifiers)
            let key = KeyEvent(charactersIgnoringModifiers: keys.ignoringModifiers,
                               characters: keys.characters, modifiers: modifiers,
                               isRepeat: event.repeat, timestamp: event.timestamp)
            _ = onInput?(Int(event.kind) == Int(MUI_EVENT_KEY_DOWN) ? .keyDown(key) : .keyUp(key))
        default:
            break
        }
    }

    // The window outlives no one but its platform; deinit is its end.
    nonisolated deinit {
        MainActor.assumeIsolated {
            windowRenderer = nil
            accessKit = nil
            mui_window_destroy(UnsafeMutableRawPointer(handle))
        }
    }
}

/// SDL keys and wheels in the vocabulary AppKit's events use, which is the one
/// `Keymap` spells bindings in (ruling SP-C).
public enum SDLKeys {
    /// `(charactersIgnoringModifiers, characters)` for an SDL keycode: printable
    /// keycodes are their Unicode scalar (letters lowercase; shift uppercases
    /// `characters`), and keys with no printable spelling map to AppKit's
    /// private-use function-key characters, which `Keymap.namedKeys` reads.
    public static func characters(forKeycode keycode: UInt32, modifiers: Modifiers)
        -> (ignoringModifiers: String, characters: String) {
        if let named = named[keycode] { return (named, named) }
        guard keycode < 0x4000_0000, let scalar = Unicode.Scalar(keycode) else { return ("", "") }
        let plain = String(scalar)
        return (plain, modifiers.contains(.shift) ? plain.uppercased() : plain)
    }

    /// SDL keycodes whose AppKit character is not the keycode itself.
    static let named: [UInt32: String] = [
        0x08: "\u{7f}",            // SDLK_BACKSPACE → AppKit's delete (NSDeleteCharacter)
        0x7F: "\u{f728}",          // SDLK_DELETE → NSDeleteFunctionKey (forward delete)
        0x0D: "\r", 0x09: "\t", 0x1B: "\u{1b}", 0x20: " ",
        0x4000_0052: "\u{f700}", 0x4000_0051: "\u{f701}",   // up, down
        0x4000_0050: "\u{f702}", 0x4000_004F: "\u{f703}",   // left, right
        0x4000_004A: "\u{f729}", 0x4000_004D: "\u{f72b}",   // home, end
        0x4000_004B: "\u{f72c}", 0x4000_004E: "\u{f72d}",   // page up, page down
        0x4000_003A: "\u{f704}", 0x4000_003B: "\u{f705}", 0x4000_003C: "\u{f706}", 0x4000_003D: "\u{f707}",
        0x4000_003E: "\u{f708}", 0x4000_003F: "\u{f709}", 0x4000_0040: "\u{f70a}", 0x4000_0041: "\u{f70b}",
        0x4000_0042: "\u{f70c}", 0x4000_0043: "\u{f70d}", 0x4000_0044: "\u{f70e}", 0x4000_0045: "\u{f70f}",
    ]

    /// SDL's editing event as a composition: `start`/`length` are code
    /// points (SDL's unit), converted to Character offsets and clamped; an
    /// empty text ends the composition. A negative start is "no selection":
    /// the caret at the end.
    static func composition(_ text: String, start: Int, length: Int) -> TextComposition {
        guard !text.isEmpty else { return .none }
        // The Characters that end at or before `codePoints` — rounding down
        // inside a grapheme.
        func characters(upTo codePoints: Int) -> Int {
            var scalars = 0, characters = 0
            for character in text {
                scalars += character.unicodeScalars.count
                if scalars > codePoints { break }
                characters += 1
            }
            return characters
        }
        guard start >= 0 else { return TextComposition(text: text, selection: text.count..<text.count) }
        let lower = characters(upTo: start)
        return TextComposition(text: text, selection: lower..<max(lower, characters(upTo: start + max(0, length))))
    }

    static func modifiers(_ bits: UInt32) -> Modifiers {
        var result: Modifiers = []
        if bits & UInt32(MUI_MOD_SHIFT) != 0 { result.insert(.shift) }
        if bits & UInt32(MUI_MOD_CONTROL) != 0 { result.insert(.control) }
        if bits & UInt32(MUI_MOD_OPTION) != 0 { result.insert(.option) }
        if bits & UInt32(MUI_MOD_COMMAND) != 0 { result.insert(.command) }
        return result
    }

    /// Points per wheel line — AppKit's `pointsPerScrollLine`, so a notched
    /// wheel scrolls the same distance on both platforms.
    public static let pointsPerScrollLine: Float = 10

    /// SDL reports wheel motion in lines, positive `y` away from the user
    /// (with "natural" scrolling already applied); AppKit's `scrollingDeltaY`
    /// is positive the same way.
    public static func scrollDelta(x: Float, y: Float) -> Point<Pixels> {
        Point(x: Pixels(x * pointsPerScrollLine), y: Pixels(y * pointsPerScrollLine))
    }
}
