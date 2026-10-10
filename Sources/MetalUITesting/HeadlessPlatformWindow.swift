import MetalUI
import MetalUIScene

/// A `PlatformWindow` with no screen behind it (ruling `HT-D`): it implements
/// **every** requirement honestly — what the window asks of its platform is
/// recorded, in call order, and the platform's own events (input, display-link
/// ticks, resizes, scale and appearance changes, key state, Reduce Motion,
/// close requests, accessibility requests) are simulated by the test.
///
/// Presentation answers are ``Options``: the defaults are AppKit's (menus,
/// alerts, file dialogs and the toolbar shown natively — recorded here, and
/// answered by the test), `false` gives SDL's (the window draws them itself).
/// ``TestWindow`` drives one for you; use this class directly to host a
/// `Window` your own way. MetalUI-only (`HT-B`).
@MainActor
public final class HeadlessPlatformWindow: PlatformWindow {
    /// How the window answers its platform questions, and the state it opens
    /// in. Every field defaults to AppKit's answer.
    public struct Options: Sendable, Equatable {
        /// The system appearance the window opens with (``ColorScheme``).
        public var appearance: Appearance
        /// The backing scale factor the window opens with.
        public var scaleFactor: Float
        /// What `presentMenu` answers: `true` (AppKit) records the menu for
        /// the test to answer; `false` (SDL) makes the window draw it.
        public var presentsMenusNatively: Bool
        /// What `presentAlert` answers: `true` (AppKit) records the alert;
        /// `false` (SDL) makes the window draw it.
        public var presentsAlertsNatively: Bool
        /// What `presentFileDialog` answers: `true` records the dialog for the
        /// test to answer; `false` makes the window complete it as unavailable.
        public var presentsFileDialogs: Bool
        /// What `setToolbar` answers: `true` (AppKit) records the toolbar;
        /// `false` (SDL) makes the window draw its toolbar strip.
        public var showsToolbarNatively: Bool
        /// What `setTitleBarStyle` answers: `true` (AppKit) or `false` (SDL).
        public var appliesTitleBarStyle: Bool
        /// What `beginExternalDrag` answers: `false` (SDL) keeps a drag in the
        /// window.
        public var externalDragResult: Bool
        /// Whether an accessibility client is already running when the window
        /// opens: the window then activates the accessibility tree as soon as
        /// `Window` installs its request handler, so the tree is in the first
        /// frame (ruling `HT-D` item 4).
        public var accessibilityClientActive: Bool

        /// Options with every field given, each defaulting to AppKit's answer.
        public init(appearance: Appearance = .light, scaleFactor: Float = 1,
                    presentsMenusNatively: Bool = true, presentsAlertsNatively: Bool = true,
                    presentsFileDialogs: Bool = true, showsToolbarNatively: Bool = true,
                    appliesTitleBarStyle: Bool = true, externalDragResult: Bool = false,
                    accessibilityClientActive: Bool = true) {
            self.appearance = appearance
            self.scaleFactor = scaleFactor
            self.presentsMenusNatively = presentsMenusNatively
            self.presentsAlertsNatively = presentsAlertsNatively
            self.presentsFileDialogs = presentsFileDialogs
            self.showsToolbarNatively = showsToolbarNatively
            self.appliesTitleBarStyle = appliesTitleBarStyle
            self.externalDragResult = externalDragResult
            self.accessibilityClientActive = accessibilityClientActive
        }
    }

    /// The answers this window gives (read at each question).
    public var options: Options

    /// The renderer frames are presented through.
    public let headlessRenderer: HeadlessWindowRenderer

    /// A headless window of content size `size` in `options`' state.
    public init(title: String, size: Size<Pixels>, options: Options = Options()) {
        self.options = options
        self.contentSize = size
        self.scaleFactor = options.scaleFactor
        self.appearance = options.appearance
        self.headlessRenderer = HeadlessWindowRenderer(scaleFactor: options.scaleFactor)
        self.title = title
        self.titleWrites = []
    }

    // MARK: Geometry and state

    /// The content size in window points; changed by ``simulateResize(to:)``
    /// and by content size limits the window sets.
    public private(set) var contentSize: Size<Pixels>
    /// The backing scale factor; changed by ``simulateScaleFactorChange(to:)``.
    public private(set) var scaleFactor: Float
    /// ``headlessRenderer``.
    public var renderer: any WindowRenderer { headlessRenderer }
    /// The window title; every assignment is recorded in ``titleWrites``.
    public var title: String {
        didSet { titleWrites.append(title) }
    }
    /// Every assignment to ``title`` after the window was made, in order.
    public private(set) var titleWrites: [String]
    /// The system appearance; changed by ``simulateAppearanceChange(to:)``.
    public private(set) var appearance: Appearance
    /// The key state; `.key` until ``simulateControlActiveStateChange(to:)``.
    public private(set) var controlActiveState: ControlActiveState = .key
    /// Reduce Motion; `false` until ``simulateReduceMotionChange(to:)``.
    public private(set) var accessibilityReduceMotion = false

    // MARK: Callbacks the window installs

    /// Installed by `Window`; ``simulateInput(_:)`` calls it.
    public var onInput: ((InputEvent) -> Bool)?
    /// Installed by `Window`; resizes and scale changes call it.
    public var onResize: ((Size<Pixels>, Float) -> Void)?
    /// Installed by `Window`; ``simulateAppearanceChange(to:)`` calls it.
    public var onAppearanceChange: ((Appearance) -> Void)?
    /// Installed by `Window`; ``simulateControlActiveStateChange(to:)`` calls it.
    public var onControlActiveStateChange: ((ControlActiveState) -> Void)?
    /// Installed by `Window`; ``simulateReduceMotionChange(to:)`` calls it.
    public var onAccessibilityReduceMotionChange: ((Bool) -> Void)?
    /// Installed by the app; fires once when the window closes.
    public var onClose: (() -> Void)?
    /// Installed by `Window`; asked by ``simulateCloseRequest()``.
    public var onCloseRequest: (() -> Bool)?
    /// Installed by `Window`; ``simulateAccessibilityRequest(_:)`` calls it.
    /// With ``Options/accessibilityClientActive`` the first handler installed
    /// is sent `.activate` at once (`HT-D` item 4).
    public var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)? {
        didSet {
            // STUB: no activation
        }
    }
    private var hasActivatedAccessibility = false

    // MARK: Recorded requests

    /// Every `setPreferredColorScheme` argument, in order.
    public private(set) var preferredColorSchemeRequests: [ColorScheme?] = []
    /// Every `setPointerStyle` argument, in order.
    public private(set) var pointerStyles: [PlatformPointerStyle] = []
    /// Every `setTextInputArea` argument, in order; a non-`nil` last entry
    /// means a text field has the caret.
    public private(set) var textInputAreas: [Bounds<Pixels>?] = []
    /// Every `setContentSizeLimits` call, in order.
    public private(set) var contentSizeLimits: [(minimum: Size<Pixels>?, maximum: Size<Pixels>?)] = []
    /// Every `setDocumentEdited` argument, in order.
    public private(set) var documentEditedCalls: [Bool] = []
    /// Every `setRepresentedFilePath` argument, in order.
    public private(set) var representedPaths: [String?] = []
    /// Every `setTitleBarStyle` argument, in order.
    public private(set) var titleBarStyles: [PlatformTitleBarStyle] = []
    /// Every `performTitleBarPress` click count, in order.
    public private(set) var titleBarPresses: [Int] = []
    /// Every `beginExternalDrag` call, in order.
    public private(set) var externalDrags: [([DragRepresentation], Point<Pixels>)] = []
    /// Every `presentMenu` call, in order.
    public private(set) var presentedMenus: [(menu: PlatformMenu, at: Point<Pixels>)] = []
    /// Every `presentAlert` request, in order.
    public private(set) var presentedAlerts: [PlatformAlert] = []
    /// Every `presentFileDialog` request, in order.
    public private(set) var presentedFileDialogs: [PlatformFileDialog] = []
    /// Every `dismissPresentation` token, in order.
    public private(set) var dismissedPresentations: [Int] = []
    /// Every `setToolbar` argument, in order (`nil` for a removal).
    public private(set) var toolbars: [PlatformToolbar?] = []
    /// The trees the window published — only the latest unless
    /// ``keepsAccessibilityHistory`` (a benchmark must not grow an array per
    /// frame).
    public private(set) var publishedAccessibilityTrees: [AccessibilityTree] = []
    /// Keeps every published tree in ``publishedAccessibilityTrees``.
    public var keepsAccessibilityHistory = false
    /// Every `setDisplayLinkPaused` argument, in order.
    public private(set) var displayLinkPauses: [Bool] = []
    /// The window's clipboard, private to it: `readClipboard` reads it and
    /// `writeClipboard` replaces it.
    public var clipboard: String?
    /// Whether the window has closed.
    public private(set) var isClosed = false
    /// How far a title bar overlaps the content; zero by default. A test that
    /// changes it reports the change with ``simulateResize(to:)``.
    public var titleBarInsets = Edges(all: Pixels(0))

    /// The display link's callback, fired by ``simulateTick(timestamp:)``.
    private var tick: ((Double) -> Void)?
    /// The timestamp of the last ``simulateTick(timestamp:)``, stamped on a
    /// wheel event that carries none.
    private var currentTime: Double = 0

    // MARK: PlatformWindow requirements

    /// Records the request.
    public func setPreferredColorScheme(_ colorScheme: ColorScheme?) {
        preferredColorSchemeRequests.append(colorScheme)
    }

    /// Records the tree (only the latest unless ``keepsAccessibilityHistory``).
    public func publishAccessibilityTree(_ tree: AccessibilityTree) {
        if keepsAccessibilityHistory {
            publishedAccessibilityTrees.append(tree)
        } else {
            publishedAccessibilityTrees = [tree]
        }
    }

    /// Records the caret rect (`nil`: text input stopped).
    public func setTextInputArea(_ caret: Bounds<Pixels>?) { textInputAreas.append(caret) }

    /// Reads ``clipboard``.
    public func readClipboard() -> String? { clipboard }

    /// Replaces ``clipboard``.
    public func writeClipboard(_ text: String) { clipboard = text }

    /// Keeps `tick` for ``simulateTick(timestamp:)``; nothing fires on its own.
    public func startDisplayLink(_ tick: @escaping (Double) -> Void) { self.tick = tick }

    /// Records the call and answers ``Options/externalDragResult``.
    public func beginExternalDrag(_ representations: [DragRepresentation], at position: Point<Pixels>) -> Bool {
        externalDrags.append((representations, position))
        return options.externalDragResult
    }

    /// Records the menu and answers ``Options/presentsMenusNatively``.
    public func presentMenu(_ menu: PlatformMenu, at position: Point<Pixels>) -> Bool {
        presentedMenus.append((menu, position))
        return options.presentsMenusNatively
    }

    /// Records the dialog and answers ``Options/presentsFileDialogs``.
    public func presentFileDialog(_ dialog: PlatformFileDialog) -> Bool {
        presentedFileDialogs.append(dialog)
        return options.presentsFileDialogs
    }

    /// Records the alert and answers ``Options/presentsAlertsNatively``.
    public func presentAlert(_ alert: PlatformAlert) -> Bool {
        presentedAlerts.append(alert)
        return options.presentsAlertsNatively
    }

    /// Records the token.
    public func dismissPresentation(token: Int) { dismissedPresentations.append(token) }

    /// Records the limits and, as a platform does (`SV-M`), resizes a content
    /// size outside them into them, reporting it through `onResize`.
    public func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {
        contentSizeLimits.append((minimum, maximum))
        let lowW = minimum?.width.value ?? 0, lowH = minimum?.height.value ?? 0
        let highW = maximum?.width.value ?? .greatestFiniteMagnitude
        let highH = maximum?.height.value ?? .greatestFiniteMagnitude
        let clamped = Size(width: Pixels(min(max(contentSize.width.value, lowW), highW)),
                           height: Pixels(min(max(contentSize.height.value, lowH), highH)))
        if clamped != contentSize { simulateResize(to: clamped) }
    }

    /// Records the toolbar and answers ``Options/showsToolbarNatively``.
    public func setToolbar(_ toolbar: PlatformToolbar?) -> Bool {
        toolbars.append(toolbar)
        return options.showsToolbarNatively
    }

    /// Records the style.
    public func setPointerStyle(_ style: PlatformPointerStyle) { pointerStyles.append(style) }

    /// Records the call.
    public func setDisplayLinkPaused(_ paused: Bool) { displayLinkPauses.append(paused) }

    /// Closes without asking: ``onClose`` fires the first time only.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        onClose?()
    }

    /// Records the marker.
    public func setDocumentEdited(_ edited: Bool) { documentEditedCalls.append(edited) }

    /// Records the path.
    public func setRepresentedFilePath(_ path: String?) { representedPaths.append(path) }

    /// Records the style and answers ``Options/appliesTitleBarStyle``.
    public func setTitleBarStyle(_ style: PlatformTitleBarStyle) -> Bool {
        titleBarStyles.append(style)
        return options.appliesTitleBarStyle
    }

    /// Records the click count and answers `false`: a headless window has no
    /// title bar to drag or zoom.
    public func performTitleBarPress(clickCount: Int) -> Bool {
        titleBarPresses.append(clickCount)
        return false
    }

    // MARK: Simulated platform events

    /// Delivers `event` as the platform would and answers what the window
    /// said. A wheel event's `location` is set to its `position` and, when
    /// its `timestamp` is 0, it is stamped with the last tick's.
    @discardableResult
    public func simulateInput(_ event: InputEvent) -> Bool {
        if case .scrollWheel(var scroll) = event {
            if scroll.timestamp == 0 { scroll.timestamp = currentTime }
            scroll.location = scroll.position
            return onInput?(.scrollWheel(scroll)) ?? false
        }
        return onInput?(event) ?? false
    }

    /// Fires one display-link tick at `timestamp` (seconds).
    public func simulateTick(timestamp: Double) {
        currentTime = timestamp
        tick?(timestamp)
    }

    /// Resizes the content to `size` and reports it through `onResize`.
    public func simulateResize(to size: Size<Pixels>) {
        contentSize = size
        onResize?(size, scaleFactor)
    }

    /// Moves the window to a display of backing scale `scale`: the renderer's
    /// scale follows and the change is reported through `onResize`.
    public func simulateScaleFactorChange(to scale: Float) {
        scaleFactor = scale
        headlessRenderer.scaleFactor = scale
        onResize?(contentSize, scale)
    }

    /// Switches the system appearance and notifies, the getter already
    /// reporting the new value.
    public func simulateAppearanceChange(to appearance: Appearance) {
        self.appearance = appearance
        onAppearanceChange?(appearance)
    }

    /// Changes the key state and notifies.
    public func simulateControlActiveStateChange(to state: ControlActiveState) {
        controlActiveState = state
        onControlActiveStateChange?(state)
    }

    /// Changes Reduce Motion and notifies.
    public func simulateReduceMotionChange(to value: Bool) {
        accessibilityReduceMotion = value
        onAccessibilityReduceMotionChange?(value)
    }

    /// A user's close request (the close button, ⌘W, Alt-F4): ``onCloseRequest``
    /// is asked and the window closes only on `true` or with no handler.
    /// Answers whether it closed.
    @discardableResult
    public func simulateCloseRequest() -> Bool {
        guard !isClosed else { return false }
        guard onCloseRequest?() ?? true else { return false }
        close()
        return true
    }

    /// Sends `request` as an accessibility client would and answers the
    /// window's reply.
    @discardableResult
    public func simulateAccessibilityRequest(_ request: AccessibilityRequest) -> Bool {
        onAccessibilityRequest?(request) ?? false
    }
}
