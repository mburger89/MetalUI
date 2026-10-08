// Compiled only under the `SDL` trait (ruling PX-H item 2); without it this
// file declares only the unavailable `SDLPlatform` at its end.
#if SDL
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import SDLBridge

public struct SDLPlatformError: Error, CustomStringConvertible {
    public let description: String
    init(_ what: String) { description = "\(what): \(String(cString: replay_error()))" }
}

/// MetalUI's `Platform` over SDL3 (ruling SP-A): windows, input, frame ticks,
/// appearance and close on Linux, Windows and macOS, each window drawing
/// through an ``SDLWindowRenderer``.
///
/// **Input constraints of SDL 3.4** (rulings `CI-I` item 6, `CI-K`): a wheel
/// event has no gesture phase, momentum phase or precise flag (`.none`,
/// `.none`, `false`); a trackpad pinch arrives as `.magnify` (no position:
/// the window's last pointer position) where the video driver sends one — not
/// on Windows, whose precision touchpads send control+wheel; there is **no
/// rotate** event; the pointer styles map to system cursors, with both grab
/// hands as the move cursor and both zooms as the default one (SDL has no hand
/// or zoom cursor).
@MainActor
public final class SDLPlatform: Platform {
    private var windows: [UInt32: SDLWindow] = [:]
    private let hidden: Bool
    private var running = false
    /// The window of this platform with keyboard focus, if any (ruling EV-AB,
    /// amended by EV-AF). Tracked from SDL's focus events rather than read
    /// from `SDL_GetWindowFlags`, which a pushed event does not update; the
    /// flags seed it once, when a window opens.
    private var focusedID: UInt32?

    /// Whether this platform's video driver sends a pinch's cumulative scale
    /// (ruling `CI-K` item 1): read once, at init, from
    /// `SDL_GetCurrentVideoDriver`. Settable for a test on a ratio driver.
    var pinchIsCumulative = true

    /// - Parameter hiddenWindows: open windows hidden — for tests, which need
    ///   a real window and its events but nothing on screen.
    public init(hiddenWindows: Bool = false) throws {
        guard mui_platform_init() else { throw SDLPlatformError("SDL_Init") }
        hidden = hiddenWindows
        pinchIsCumulative = SDLPinch.isCumulative(driver: String(cString: mui_current_video_driver()))
        #if canImport(AppKit)
        Self.installAppKitEventSignal()
        #endif
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
        window.platform = self
        applyIcon(to: [window])
        if mui_window_has_input_focus(handle) { focusedID = window.id }
        window.noteControlActiveState()
        publishControlActiveStates()
        return window
    }

    /// `.key` for the focused window, `.active` for another of this
    /// platform's windows while one has focus, `.inactive` when none does —
    /// SDL has no application-activation state apart from window focus
    /// (ruling EV-AB).
    func controlActiveState(of id: UInt32) -> ControlActiveState {
        focusedID == id ? .key : (focusedID != nil ? .active : .inactive)
    }

    /// Fires each window's callback whose state changed since it last
    /// reported — once per drain, so a switch between two of this platform's
    /// windows (`FOCUS_LOST(A)` then `FOCUS_GAINED(B)`) reports no transient
    /// `.inactive` to A (ruling EV-AF).
    private func publishControlActiveStates() {
        for window in windows.values { window.publishControlActiveStateIfChanged() }
    }

    /// Runs until every window has closed or ``stop()`` is called: events are
    /// dispatched, and while any window's display link is running each frame
    /// ticks it (the swapchain acquire paces the loop to the display); with
    /// every link paused the loop sleeps in `SDL_WaitEvent`.
    ///
    /// **Each pass also drains the main queue** (ruling `SV-H`, the gap-10
    /// fix): main-actor work — a `Task` started from a button's action, an
    /// `await` resuming on the main actor — runs in the pass it was enqueued
    /// from input, and within one 250 ms wait when enqueued from another
    /// thread while every display link is paused. **Call it from synchronous
    /// top-level code**, as every MetalUI `main.swift` does: inside a
    /// main-actor job — an `async` main — the drain cannot run main-actor
    /// work on either platform (probes `swift-main-actor-task-loop.swift` `B2`
    /// and `swift-main-queue-drain-nested.swift` `J1`).
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
                drainMainQueue()   // SV-H: after the events, before the ticks
                let now = mui_now()
                for window in windows.values where window.linkRunning { window.tick(now) }
            } else {
                var event = MUIEvent()
                if mui_wait_event(&event, 250) { dispatch(event) }
                pumpEvents()
                drainMainQueue()   // SV-H
            }
        }
        running = false
    }

    /// Windows open and not yet closed.
    var openWindowCount: Int { windows.count }

    /// The application icon: the textures last set, applied to every window
    /// this platform opens (ruling AI-F item 4). `[]` after a clear.
    private var icon: [ImageTexture] = []

    /// Sets every window's icon — SDL3's icon is per window; every desktop
    /// shell shows one application's windows under one icon, and on macOS
    /// SDL's Cocoa backend also makes it the Dock icon (ruling AI-F). Applied
    /// at once to every open window and, from `openSDLWindow`, to every
    /// window opened later. `images` is ordered smallest area first with no
    /// repeated size (the `Platform` contract, `AI-B`); the first is the
    /// primary, the rest high-DPI alternates. Best effort: a backend that
    /// refuses (Wayland without `xdg-toplevel-icon-v1`) is not reported
    /// (`AI-D`).
    ///
    /// **`[]` cannot clear on SDL** (`AI-F` item 5): SDL3 has no way back to
    /// a window's default icon and is never handed `NULL`, so open windows
    /// keep the icon they have and windows opened afterwards get none.
    public func setApplicationIcon(_ images: [ImageTexture]) {
        icon = images
        applyIcon(to: Array(windows.values))
    }

    /// The menu bar `App` last installed (ruling `MN-I` item 3), read by a
    /// test.
    private(set) var menuBar: PlatformMenuBar?

    /// Records the menu bar and draws nothing (ruling `MN-I` item 3): SDL3 has
    /// no menu-bar API, and Linux and Windows SDL windows show none. A
    /// command's keyboard shortcut still works — `Window`'s command stage
    /// (`MN-J`) needs no platform menu. An in-window menu bar is deferred,
    /// owner none.
    public func setMenuBar(_ menuBar: PlatformMenuBar) {
        self.menuBar = menuBar
    }

    /// Builds one surface for the stored icon, sets it on `targets` and
    /// destroys it at once (`SDL_SetWindowIcon` keeps its own copy), so no
    /// surface outlives the call. Nothing with no icon or no target.
    private func applyIcon(to targets: [SDLWindow]) {
        guard !icon.isEmpty, !targets.isEmpty else { return }
        let surface = SDLIcon.makeSurface(icon)
        defer { if let surface { mui_surface_destroy(surface) } }
        for window in targets { window.applyIcon(surface, textures: icon) }
    }

    /// Ends ``run()`` after the current iteration.
    public func stop() { running = false }

    /// Dispatches every pending event without waiting — one run-loop pass
    /// minus the ticks. Tests drive the platform with it.
    public func pumpEvents() {
        var event = MUIEvent()
        while mui_poll_event(&event) { dispatch(event) }
        publishControlActiveStates()
    }

    /// Waits up to `timeoutMilliseconds` for one event and dispatches it — the
    /// loop's own bounded wait (`mui_wait_event`), so a test waiting on an
    /// answer from another thread waits for the event, not for a clock.
    func waitForEvent(timeoutMilliseconds: Int32) {
        var event = MUIEvent()
        if mui_wait_event(&event, timeoutMilliseconds) { dispatch(event) }
        publishControlActiveStates()
    }

    private func dispatch(_ event: MUIEvent) {
        switch Int(event.kind) {
        case Int(MUI_EVENT_QUIT):
            stop()
        case Int(MUI_EVENT_THEME):
            for window in windows.values { window.appearanceChanged() }
        case Int(MUI_EVENT_CLOSE):
            guard let window = windows.removeValue(forKey: event.window_id) else { return }
            if focusedID == event.window_id { focusedID = nil }
            window.close()
        case Int(MUI_EVENT_FOCUS_GAINED):
            // A window this platform does not own is not ours to focus.
            guard windows[event.window_id] != nil else { return }
            focusedID = event.window_id
        case Int(MUI_EVENT_FOCUS_LOST):
            if focusedID == event.window_id { focusedID = nil }
        case Int(MUI_EVENT_ACCESSIBILITY):
            windows[event.window_id]?.deliverAccessibilityRequests()
        case Int(MUI_EVENT_PINCH):
            // A pinch names no window on cocoa (ruling `CI-K` item 2): the
            // mouse-focus window, else the keyboard-focused one, else dropped.
            guard let id = SDLPinch.route(windowID: event.window_id, mouseFocus: mui_mouse_focus_window_id(),
                                          keyboardFocus: focusedID ?? 0) else { return }
            windows[id]?.handlePinch(event, cumulative: pinchIsCumulative)
        case Int(MUI_EVENT_DIALOG):
            // A file dialog's answer (ruling `SV-G` item 2), already copied
            // into the bridge's queue by SDL's callback. A window gone since
            // the request leaves nobody to tell: the answer is freed.
            if let window = windows[event.window_id] {
                window.deliverDialogResult(token: event.start)
            } else {
                mui_dialog_result_free(mui_take_dialog_result(event.start))
            }
        default:
            windows[event.window_id]?.handle(event)
        }
    }
}

/// One SDL window as a MetalUI `PlatformWindow` (ruling SP-A).
@MainActor
public final class SDLWindow: PlatformWindow {
    private let handle: OpaquePointer
    /// SDL's window id (`SDL_GetWindowID`) — public so an executable driving
    /// the bridge's test hooks can name the window (`MainQueueDrainCheck`,
    /// ruling `SV-H` item 3).
    public let id: UInt32
    /// Optional only so `deinit` can release it — and the window's GPU
    /// claim with it — before the window itself is destroyed.
    private var windowRenderer: SDLWindowRenderer?
    private var displayLinkTick: ((Double) -> Void)?
    private var displayLinkPaused = false
    private var closed = false
    /// Optional for the same reason as `windowRenderer`: released before the
    /// window it subclasses is destroyed.
    #if AccessKit
    private var accessKit: AccessKitAdapter?
    private let accessKitIDs = AccessKitIDs()
    #endif
    /// Requests that arrived before `Window` installed its handler — parked,
    /// as the AppKit bridge parks `.activate` (AB-B).
    private var parkedAccessibilityRequests: [AccessibilityRequest] = []

    init(handle: OpaquePointer) throws {
        self.handle = handle
        id = mui_window_id(UnsafeMutableRawPointer(handle))
        windowRenderer = try SDLWindowRenderer(window: handle)
        #if AccessKit
        let raw = UnsafeMutableRawPointer(handle)
        accessKit = AccessKitAdapter(windowID: id, title: String(cString: mui_window_title(raw)),
                                     nativeWindow: mui_window_native_handle(raw))
        #endif
        updateAccessibilityWindowBounds()
    }

    public var renderer: any WindowRenderer { windowRenderer! }

    /// The application icon this window was last given (ruling AI-F, `AI-D`):
    /// the textures' identities and `SDL_SetWindowIcon`'s answer (`false`
    /// too when the surface could not be built). `nil` until one is applied.
    /// For tests — the platform does not surface a refusal.
    private(set) var iconResult: (textures: [ObjectIdentifier], applied: Bool)?

    /// Sets `surface` as this window's icon, recording the result. A `nil`
    /// surface is recorded as not applied and never passed to SDL.
    func applyIcon(_ surface: UnsafeMutableRawPointer?, textures: [ImageTexture]) {
        let applied = surface.map { mui_window_set_icon(rawHandle, $0) } ?? false
        iconResult = (textures.map(ObjectIdentifier.init), applied)
    }

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

    /// The last `setPreferredColorScheme(_:)` argument (ruling `CR-M`),
    /// recorded for tests; nothing else reads it.
    public private(set) var preferredColorScheme: ColorScheme?

    /// Records the preference and does nothing else (ruling `CR-M`): SDL3 has
    /// no per-window appearance, so `appearance` keeps reporting the system
    /// theme and `SDL_EVENT_SYSTEM_THEME_CHANGED` still reaches
    /// `onAppearanceChange`. `Window` applies the preference to the content
    /// itself; the native decorations follow the system — a documented
    /// platform constraint, not a SwiftUI divergence.
    public func setPreferredColorScheme(_ colorScheme: ColorScheme?) {
        preferredColorScheme = colorScheme
    }

    // MARK: Pointer style (ruling `CI-H` item 8)

    /// Every `setPointerStyle(_:)` argument, in order — recorded so a test
    /// under the offscreen driver, where a cursor may not be creatable, still
    /// sees the request.
    private(set) var pointerStyles: [PlatformPointerStyle] = []

    /// Sets the system cursor `SDLCursorTable` maps `style` to — created once
    /// per kind and cached by the bridge, then `SDL_SetCursor` — and records
    /// the request. **SDL's cursor is process-global**, not per window (hence
    /// `CI-S`'s re-send on re-entry). Both grab hands show SDL's move cursor
    /// and both zooms the default one: SDL has no hand or zoom cursor, a
    /// documented platform constraint (human check Y6). A cursor SDL cannot
    /// create (the offscreen driver) leaves the current one.
    public func setPointerStyle(_ style: PlatformPointerStyle) {
        pointerStyles.append(style)
        _ = mui_set_system_cursor(SDLCursorTable.systemCursor(for: style).bridgeValue)
    }

    public var onInput: ((InputEvent) -> Bool)?
    public var onResize: ((Size<Pixels>, Float) -> Void)?
    public var onAppearanceChange: ((Appearance) -> Void)?
    public var onClose: (() -> Void)?

    // MARK: Control active state (ruling EV-AB, amended by EV-AF)

    /// The platform whose focus tracking this window reads.
    weak var platform: SDLPlatform?
    /// The state last reported through ``onControlActiveStateChange`` (or
    /// noted before anyone listened) — what a change is measured against.
    private var reportedControlActiveState: ControlActiveState = .inactive

    /// This window's key state: `.key` while it has keyboard focus, `.active`
    /// while another window of its platform does, `.inactive` otherwise. Read
    /// from the platform's tracked focus, not SDL's window flags.
    public var controlActiveState: ControlActiveState {
        platform?.controlActiveState(of: id) ?? .inactive
    }

    /// Fired with the new value when ``controlActiveState`` changes — once per
    /// ``SDLPlatform/pumpEvents()``, and never for an unchanged state.
    public var onControlActiveStateChange: ((ControlActiveState) -> Void)?

    func noteControlActiveState() { reportedControlActiveState = controlActiveState }

    // MARK: Reduce Motion (plan task 13, ruling AN-AD)

    /// Always `false`: SDL3 has no Reduce Motion query. A per-OS read (GNOME's
    /// `enable-animations`, Windows' `SPI_GETCLIENTAREAANIMATION`, macOS's
    /// `NSWorkspace`) is a cross-platform roadmap item, not built here.
    public var accessibilityReduceMotion: Bool { false }

    /// Never fired — the value never changes (see ``accessibilityReduceMotion``).
    public var onAccessibilityReduceMotionChange: ((Bool) -> Void)?

    func publishControlActiveStateIfChanged() {
        let state = controlActiveState
        guard state != reportedControlActiveState else { return }
        reportedControlActiveState = state
        onControlActiveStateChange?(state)
    }

    /// Called with AccessKit's requests (ruling AX-C): `.activate` when a
    /// screen reader first asks for the tree, then the actions it performs.
    /// Delivered on the main thread from ``SDLPlatform/pumpEvents()``.
    public var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)? {
        didSet { deliverAccessibilityRequests() }
    }

    #if AccessKit
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
    #else
    /// Accepts the tree and drops it: built without the `AccessKit` trait,
    /// this window has no screen-reader bridge (ruling PX-H item 2).
    public func publishAccessibilityTree(_ tree: AccessibilityTree) {}

    /// Always `false` without the `AccessKit` trait — no adapter exists, so
    /// ``onAccessibilityRequest`` never fires.
    public var isAccessibilityConnected: Bool { false }
    #endif

    func deliverAccessibilityRequests() {
        #if AccessKit
        if let accessKit {
            for queued in accessKit.drain() {
                if let request = AccessKitSnapshot.request(for: queued, ids: accessKitIDs) {
                    parkedAccessibilityRequests.append(request)
                }
            }
        }
        #endif
        guard let onAccessibilityRequest, !parkedAccessibilityRequests.isEmpty else { return }
        let requests = parkedAccessibilityRequests
        parkedAccessibilityRequests = []
        for request in requests { _ = onAccessibilityRequest(request) }
    }

    /// AT-SPI asks no window handle, so Linux is told where the window is.
    private func updateAccessibilityWindowBounds() {
        #if AccessKit
        var x: Int32 = 0, y: Int32 = 0
        mui_window_position(UnsafeMutableRawPointer(handle), &x, &y)
        let scale = Double(scaleFactor), size = contentSize
        accessKit?.setWindowBounds(x: Double(x) * scale, y: Double(y) * scale,
                                   width: Double(size.width.value) * scale,
                                   height: Double(size.height.value) * scale)
        #endif
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

    /// Always `false` (ruling `DN-K` item 4): SDL3 has no API to start an
    /// operating-system drag — `SDL_events.h` lists only the five incoming
    /// `SDL_EVENT_DROP_*` events — so a drag stays in the window, and SDL's
    /// mouse auto-capture keeps its motion arriving outside it.
    public func beginExternalDrag(_ representations: [DragRepresentation], at position: Point<Pixels>) -> Bool {
        false
    }

    /// Always `false` (ruling `MN-C` item 3): SDL3 has no menu API, so
    /// `Window` draws the menu in the window (`MN-F`).
    public func presentMenu(_ menu: PlatformMenu, at position: Point<Pixels>) -> Bool {
        false
    }

    // MARK: Platform services (rulings `SV-G`, `SV-J`, `SV-M`)

    /// Calls `SDL_ShowOpenFileDialog` (`allow_many` as asked) or
    /// `SDL_ShowSaveFileDialog` (`default_location` = the default name) with
    /// this window as parent, filtered by ``dialogFilters(_:)``, and answers
    /// `true` (ruling `SV-G` item 1): every outcome — chosen, cancelled, or
    /// failed with `SDL_GetError()`'s text — arrives through SDL's callback,
    /// on whatever thread SDL calls it from, hopped onto the main thread by
    /// the bridge as `MUI_EVENT_DIALOG` and delivered as `.fileDialogResult`.
    /// The seam's `title`/`prompt` are not SDL3 parameters of these calls
    /// and are not shown. `false` only for a token outside `Int32`.
    public func presentFileDialog(_ dialog: PlatformFileDialog) -> Bool {
        guard let token = Int32(exactly: dialog.token) else { return false }
        let isSave: Bool, allowMany: Bool, location: String?
        switch dialog.kind {
        case .open(let allowsMultipleSelection):
            (isSave, allowMany, location) = (false, allowsMultipleSelection, nil)
        case .save(let defaultFilename):
            (isSave, allowMany, location) = (true, false, defaultFilename)
        }
        guard let request = mui_dialog_request_new(token, isSave, allowMany, location) else { return false }
        for filter in Self.dialogFilters(dialog.allowedTypes) {
            _ = mui_dialog_request_add_filter(request, filter.name, filter.pattern)
        }
        return mui_dialog_request_show(request, rawHandle)
    }

    /// SDL's filters for `types` (ruling `SV-E`, divergence 129): one per type
    /// that has filename extensions — named by its identifier, its extensions
    /// joined by `;` — and none for a type without (`public.data`), so a list
    /// with no extension anywhere filters nothing (SDL is passed `NULL`). Off
    /// Apple a type is matched by extension only.
    nonisolated static func dialogFilters(_ types: [PlatformFileType]) -> [(name: String, pattern: String)] {
        types.compactMap { type in
            type.filenameExtensions.isEmpty
                ? nil : (type.identifier, type.filenameExtensions.joined(separator: ";"))
        }
    }

    /// Takes the answer the bridge queued for `token` and delivers it as
    /// `.fileDialogResult` — an empty list a cancel, SDL's `NULL` a failure.
    func deliverDialogResult(token: Int32) {
        guard let result = mui_take_dialog_result(token) else { return }
        defer { mui_dialog_result_free(result) }
        let outcome: FileDialogResultEvent.Outcome
        switch mui_dialog_result_status(result) {
        case 1:
            outcome = .chosen((0..<mui_dialog_result_count(result)).compactMap { index in
                mui_dialog_result_path(result, index).map { String(cString: $0) }
            })
        case 0:
            outcome = .cancelled
        default:
            outcome = .failed(String(cString: mui_dialog_result_error(result)))
        }
        _ = onInput?(.fileDialogResult(FileDialogResultEvent(token: Int(token), outcome: outcome)))
    }

    /// Always `false` (ruling `SV-J` item 2): SDL's `SDL_ShowMessageBox`
    /// blocks in a nested loop — no frames, no display link, no AccessKit
    /// updates while it is up — and fails under the offscreen driver, so
    /// `Window` draws its in-window alert, as it draws the in-window menu.
    public func presentAlert(_ alert: PlatformAlert) -> Bool {
        false
    }

    /// Does nothing (ruling `SV-G` item 5): SDL3 has no call that closes a
    /// file dialog it showed, and this platform shows no alert. The answer
    /// that eventually arrives is delivered as input; `Window` has forgotten
    /// the token and runs nothing.
    public func dismissPresentation(token: Int) {}

    /// The last `setToolbar(_:)` argument (ruling `MD-J` item 5), recorded for
    /// tests; nothing else reads it.
    public private(set) var toolbar: PlatformToolbar?

    /// Records `toolbar` and answers `false` (ruling `MD-J` item 5): SDL3 has
    /// no native toolbar, so `Window` draws the toolbar inside the window
    /// (`MD-K`). `nil` clears the record.
    public func setToolbar(_ toolbar: PlatformToolbar?) -> Bool {
        self.toolbar = toolbar
        return false
    }

    /// `SDL_SetWindowMinimumSize`/`SDL_SetWindowMaximumSize` (ruling `SV-M`):
    /// the minimum rounded up, the maximum down, `nil` — and an axis beyond
    /// `Int32` (the seam's unbounded `greatestFiniteMagnitude`) — as 0, SDL's
    /// "no limit". SDL resizes a window outside the new limits itself, and
    /// its resize reaches `onResize`.
    public func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {
        func points(_ value: Float?, _ rule: FloatingPointRoundingRule) -> Int32 {
            guard let value, value.isFinite, value > 0 else { return 0 }
            return Int32(exactly: value.rounded(rule)) ?? 0
        }
        let minW = points(minimum?.width.value, .up), minH = points(minimum?.height.value, .up)
        // A maximum that rounds below its minimum (the same fractional value
        // rounds the two apart) is raised to it; 0 stays "no limit" (`SV-AG`
        // item 1).
        func atLeast(_ high: Int32, _ low: Int32) -> Int32 { high == 0 ? 0 : max(high, low) }
        let maxW = atLeast(points(maximum?.width.value, .down), minW)
        let maxH = atLeast(points(maximum?.height.value, .down), minH)
        _ = mui_window_set_size_limits(rawHandle, minW, minH, maxW, maxH)
    }

    // MARK: Drops in (ruling `DN-M`)

    /// The drop session SDL's events are building, or `nil` between them.
    /// `entered` is whether `.entered` was sent; `position` the last place the
    /// drop was reported.
    private struct DropSession {
        var entered = false
        var position = Point(x: Pixels(0), y: Pixels(0))
        var items: [DropItem] = []
    }
    private var dropSession: DropSession?

    /// `public.file-url` and `public.utf8-plain-text` with their parents —
    /// `ContentType.fileURL`'s and `.utf8PlainText`'s conformance, spelled as
    /// strings because this package does not import `MetalUI`.
    nonisolated static let fileURLType = PasteboardType(identifier: "public.file-url",
                                                        conformsTo: ["public.data", "public.item", "public.url"])
    nonisolated static let utf8TextType = PasteboardType(identifier: "public.utf8-plain-text",
                                                         conformsTo: ["public.data", "public.item",
                                                                      "public.plain-text", "public.text"])

    /// One run of `SDL_EVENT_DROP_*` events as one drop session (`DN-M` item
    /// 1): the first position — or, if none came, the first item's — enters
    /// with the items unknown (SDL gives none until the drop); each later
    /// position moves; `COMPLETE` performs at the last position with every
    /// item gathered, or exits when none arrived. Each event's text is copied
    /// here, at once: SDL owns it until the next poll.
    private func handleDrop(_ event: MUIEvent) {
        let position = Point(x: Pixels(event.x), y: Pixels(event.y))
        func enter() {
            dropSession?.position = position
            guard dropSession?.entered == false else { return }
            dropSession?.entered = true
            _ = onInput?(.drop(.entered(position: position, items: nil)))
        }
        switch Int(event.kind) {
        case Int(MUI_EVENT_DROP_BEGIN):
            dropSession = DropSession()
        case Int(MUI_EVENT_DROP_POSITION):
            if dropSession == nil { dropSession = DropSession() }
            if dropSession?.entered == true {
                dropSession?.position = position
                _ = onInput?(.drop(.moved(position: position)))
            } else {
                enter()
            }
        case Int(MUI_EVENT_DROP_FILE), Int(MUI_EVENT_DROP_TEXT):
            guard let text = event.text else { return }
            if dropSession == nil { dropSession = DropSession() }
            let string = String(cString: text)
            let isFile = Int(event.kind) == Int(MUI_EVENT_DROP_FILE)
            let type = isFile ? Self.fileURLType : Self.utf8TextType
            let bytes = Array((isFile ? Self.fileURLString(fromPath: string) : string).utf8)
            dropSession?.items.append(DropItem(types: [type]) { $0 == type.identifier ? bytes : nil })
            if dropSession?.entered == false { enter() }
        case Int(MUI_EVENT_DROP_COMPLETE):
            guard let session = dropSession else { return }
            dropSession = nil
            if !session.items.isEmpty {
                _ = onInput?(.drop(.performed(position: session.position, items: session.items)))
            } else if session.entered {
                _ = onInput?(.drop(.exited))
            }
        default:
            break
        }
    }

    /// Ends an open drop session with `.exited` — an ordinary pointer motion
    /// means the drag left without a `COMPLETE` (`DN-M` item 1).
    private func endDropSessionOnMotion() {
        guard let session = dropSession else { return }
        dropSession = nil
        if session.entered { _ = onInput?(.drop(.exited)) }
    }

    /// A dropped path as a `file://` URL string (`DN-M` item 1): RFC 3986's
    /// unreserved characters and `/` kept, every other byte of its UTF-8
    /// percent-encoded; a Windows path's backslashes become slashes, and a
    /// drive path `C:\…` becomes `file:///C:/…` (the drive's colon kept).
    nonisolated static func fileURLString(fromPath path: String) -> String {
        var slashed = path.replacingBackslashes()
        var prefix = "file://"
        let scalars = Array(slashed.unicodeScalars)
        if scalars.count >= 2, scalars[1] == ":", scalars[0].isASCIILetter {
            prefix = "file:///" + String(scalars[0]) + ":"
            slashed = String(String.UnicodeScalarView(scalars.dropFirst(2)))
        } else if !slashed.hasPrefix("/") {
            prefix = "file:///"
        }
        var encoded = ""
        for byte in slashed.utf8 {
            let c = Character(Unicode.Scalar(byte))
            if byte < 0x80, c.isASCIILetterOrDigit || "-._~/".contains(c) {
                encoded.append(c)
            } else {
                let hex = String(byte, radix: 16, uppercase: true)
                encoded += "%" + (hex.count == 1 ? "0" + hex : hex)
            }
        }
        return prefix + encoded
    }

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

    /// The last pointer position a motion, button or wheel event delivered —
    /// where a pinch, which has none in SDL, is placed (ruling `CI-K` item 2).
    private var lastPointerPosition = Point(x: Pixels(0), y: Pixels(0))
    /// The previous scale of the pinch under way (1 at its start), for a
    /// cumulative driver's delta.
    private var pinchPreviousScale: Double = 1

    /// A pinch step as `.magnify` (ruling `CI-K` item 1): BEGIN and END carry
    /// no delta; an UPDATE's is `SDLPinch.delta` against the previous scale.
    func handlePinch(_ event: MUIEvent, cumulative: Bool) {
        let phase: InputPhase
        var magnification = 0.0
        switch Int(event.phase) {
        case Int(MUI_PINCH_BEGIN):
            phase = .began
            pinchPreviousScale = 1
        case Int(MUI_PINCH_UPDATE):
            phase = .changed
            let scale = Double(event.scale)
            magnification = SDLPinch.delta(scale: scale, previous: pinchPreviousScale, cumulative: cumulative)
            pinchPreviousScale = scale
        default:
            phase = .ended
            pinchPreviousScale = 1
        }
        _ = onInput?(.magnify(MagnifyEvent(position: lastPointerPosition, magnification: magnification,
                                           phase: phase, modifiers: SDLKeys.modifiers(event.modifiers),
                                           timestamp: event.timestamp)))
    }

    func handle(_ event: MUIEvent) {
        let position = Point(x: Pixels(event.x), y: Pixels(event.y))
        let modifiers = SDLKeys.modifiers(event.modifiers)
        switch Int(event.kind) {
        case Int(MUI_EVENT_MOUSE_DOWN), Int(MUI_EVENT_MOUSE_UP), Int(MUI_EVENT_RIGHT_DOWN),
             Int(MUI_EVENT_RIGHT_UP), Int(MUI_EVENT_OTHER_DOWN), Int(MUI_EVENT_OTHER_UP),
             Int(MUI_EVENT_MOUSE_MOVE), Int(MUI_EVENT_MOUSE_DRAG), Int(MUI_EVENT_RIGHT_DRAG),
             Int(MUI_EVENT_OTHER_DRAG), Int(MUI_EVENT_WHEEL):
            lastPointerPosition = position
        default:
            break
        }
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
        case Int(MUI_EVENT_RIGHT_DOWN):   // the secondary button (ruling MN-B item 3)
            _ = onInput?(.rightMouseDown(MouseEvent(position: position, modifiers: modifiers,
                                                    clickCount: Int(event.clicks), buttonNumber: 1)))
        case Int(MUI_EVENT_RIGHT_UP):
            _ = onInput?(.rightMouseUp(MouseEvent(position: position, modifiers: modifiers,
                                                  clickCount: Int(event.clicks), buttonNumber: 1)))
        case Int(MUI_EVENT_OTHER_DOWN):   // middle, X1, X2… in AppKit's numbering (ruling CI-E item 4)
            _ = onInput?(.otherMouseDown(MouseEvent(position: position, modifiers: modifiers,
                                                    clickCount: Int(event.clicks),
                                                    buttonNumber: SDLButtons.appKitNumber(sdlButton: event.button))))
        case Int(MUI_EVENT_OTHER_UP):
            _ = onInput?(.otherMouseUp(MouseEvent(position: position, modifiers: modifiers,
                                                  clickCount: Int(event.clicks),
                                                  buttonNumber: SDLButtons.appKitNumber(sdlButton: event.button))))
        case Int(MUI_EVENT_RIGHT_DRAG):
            endDropSessionOnMotion()
            _ = onInput?(.rightMouseDragged(MouseEvent(position: position, modifiers: modifiers, buttonNumber: 1)))
        case Int(MUI_EVENT_OTHER_DRAG):
            endDropSessionOnMotion()
            _ = onInput?(.otherMouseDragged(MouseEvent(position: position, modifiers: modifiers,
                                                       buttonNumber: SDLButtons.appKitNumber(sdlButton: event.button))))
        case Int(MUI_EVENT_MOUSE_MOVE):
            endDropSessionOnMotion()
            _ = onInput?(.mouseMoved(MouseEvent(position: position, modifiers: modifiers)))
        case Int(MUI_EVENT_MOUSE_DRAG):
            endDropSessionOnMotion()
            _ = onInput?(.mouseDragged(MouseEvent(position: position, modifiers: modifiers)))
        case Int(MUI_EVENT_MOUSE_LEAVE):   // the pointer left the window (ruling SV-N item 7)
            _ = onInput?(.pointerExited)
        case Int(MUI_EVENT_DROP_BEGIN), Int(MUI_EVENT_DROP_POSITION), Int(MUI_EVENT_DROP_FILE),
             Int(MUI_EVENT_DROP_TEXT), Int(MUI_EVENT_DROP_COMPLETE):
            handleDrop(event)
        case Int(MUI_EVENT_TEXT_INPUT):
            guard textInputCaret != nil, let text = event.text else { return }
            _ = onInput?(.textInput(String(cString: text)))
        case Int(MUI_EVENT_TEXT_EDITING):
            guard textInputCaret != nil, let text = event.text else { return }
            _ = onInput?(.textComposition(SDLKeys.composition(String(cString: text),
                                                             start: Int(event.start), length: Int(event.length))))
        case Int(MUI_EVENT_WHEEL):
            // SDL 3.4 has no scroll phase, momentum or precise flag (ruling
            // `CI-I` item 6): its delta is lines, scaled to points.
            _ = onInput?(.scrollWheel(ScrollEvent(position: position,
                                                  delta: SDLKeys.scrollDelta(x: event.dx, y: event.dy),
                                                  modifiers: modifiers, phase: .none, momentumPhase: .none,
                                                  isPrecise: false, timestamp: event.timestamp)))
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
            #if AccessKit
            accessKit = nil
            #endif
            mui_window_destroy(UnsafeMutableRawPointer(handle))
        }
    }
}

private extension String {
    func replacingBackslashes() -> String { String(map { $0 == "\\" ? "/" : $0 }) }
}

private extension Unicode.Scalar {
    var isASCIILetter: Bool { ("a"..."z").contains(self) || ("A"..."Z").contains(self) }
}

private extension Character {
    var isASCIILetterOrDigit: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        return scalar.isASCIILetter || ("0"..."9").contains(scalar)
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
        0x4000_0065: "\u{f735}",   // SDLK_APPLICATION → NSMenuFunctionKey, the Menu key (ruling MN-G)
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
#else
/// Not built: the `SDL` trait is off (ruling PX-H item 4). `MetalUISDL` is
/// compiled with SDL3 only when a dependent enables the trait on its MetalUI
/// dependency — `.package(url: …, traits: ["SDL", "AccessKit"])`, or
/// `["SDL"]` without the screen-reader bridge — so a package that forgot it
/// reads the remedy in the error instead of "cannot find 'SDLPlatform'".
@available(*, unavailable, message: "enable the trait 'SDL' on the MetalUI dependency: .package(url: …, traits: [\"SDL\", \"AccessKit\"]) — docs/getting-started.md")
public final class SDLPlatform {
    /// The real initialiser's spelling, public so a call reports the class's
    /// unavailability — an implicit internal `init()` would report only
    /// "inaccessible due to 'internal' protection level" (guard 1.6).
    public init(hiddenWindows: Bool = false) throws {}
}
#endif
