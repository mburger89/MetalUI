import AppKit

// App-chosen title-bar band and window-button inset under the hidden title bar (ruling `AS-R`; MetalCreator
// gap AS-a). AppKit has no public API for either: a toolbar style, a bottom accessory and the toolbar's items
// each give a fixed per-style height and leave the buttons at the system x. So the placement is manual, as
// Electron's `trafficLightPosition` does it: resize the title-bar container view — the buttons' superview's
// superview — and move the three standard buttons inside it. **That relies on the private view hierarchy**
// (`standardWindowButton(_:).superview` is an `NSTitlebarView`, its superview an `NSTitlebarContainerView`);
// when the buttons have no such superview the placement does nothing and the system layout stands.
//
// AppKit resets that layout on the first `setFrame`, on a toolbar change and on full screen, so a hook keeps
// it: KVO on the three buttons' and the two views' `frame`, **deferred one run-loop pass** (a synchronous
// re-place from inside the observer re-enters AppKit's layout and crashes) and coalesced; every write is
// **guarded by equality** (a write re-fires the observer, so an unguarded one loops forever); and nothing
// is written in full screen, where the system lays the buttons out and the container sits above the screen.
// `NSWindow` notifications are a backstop for a reset the observers miss (probe: a `title` change fires none,
// the observers catch it). Measured in the AS-a probe (record 249).

@MainActor
final class TitleBarPlacement {
    private weak var window: NSWindow?
    private(set) var height: CGFloat?
    private(set) var leading: CGFloat?
    private let isFullScreen: () -> Bool
    private var frameObservations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var pending = false
    private var isPlacing = false
    private var removed = false
    /// Each button's left edge relative to the close button's, captured once from the system layout.
    private var offsets: [NSWindow.ButtonType: CGFloat] = [:]
    /// How many frame writes ``place()`` made (tests: a settled placement writes nothing more).
    private(set) var writeCount = 0
    /// How many times ``place()`` ran past its guards.
    private(set) var placeCount = 0

    static let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    static let backstopNotifications: [Notification.Name] = [
        NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
        NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
        NSWindow.didResignKeyNotification,
    ]

    /// Places at once and hooks the window. `observesFrames` is a test seam: `false` leaves the
    /// notification backstop alone.
    init?(window: NSWindow, height: CGFloat?, leading: CGFloat?, observesFrames: Bool = true,
          isFullScreen: (() -> Bool)? = nil) {
        guard Self.views(of: window) != nil else { return nil }
        self.window = window
        self.height = height
        self.leading = leading
        self.isFullScreen = isFullScreen ?? { [weak window] in window?.styleMask.contains(.fullScreen) ?? true }
        if let close = window.standardWindowButton(.closeButton) {
            for type in Self.buttons {
                if let button = window.standardWindowButton(type) { offsets[type] = button.frame.minX - close.frame.minX }
            }
        }
        if observesFrames, let (container, bar) = Self.views(of: window) {
            var views: [NSView] = [container, bar]
            views += Self.buttons.compactMap { window.standardWindowButton($0) }
            for view in views {
                frameObservations.append(view.observe(\.frame, options: []) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.schedule() }
                })
            }
        }
        for name in Self.backstopNotifications {
            notificationTokens.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
        place()
    }

    /// The container and the titlebar view, or `nil` when the buttons do not sit where this expects.
    static func views(of window: NSWindow) -> (container: NSView, bar: NSView)? {
        guard let bar = window.standardWindowButton(.closeButton)?.superview, let container = bar.superview else {
            return nil
        }
        return (container, bar)
    }

    /// Changes the pair and places again.
    func update(height: CGFloat?, leading: CGFloat?) {
        // A field that was set and no longer is has to be given back: AppKit only lays out afresh on a resize.
        if (self.height != nil && height == nil) || (self.leading != nil && leading == nil) { restoreSystemLayout() }
        self.height = height
        self.leading = leading
        place()
    }

    /// Re-places in the next run-loop pass, once however many resets arrive before it.
    func schedule() {
        guard !pending, !removed else { return }
        pending = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                self?.pending = false
                self?.place()
            }
        }
    }

    /// Writes the container and the buttons where the pair puts them, each only if it differs; does nothing
    /// in full screen. Height centres the buttons vertically in a band that tall; leading puts the close
    /// button's left edge there and keeps the system spacing between the three.
    func place() {
        guard !removed, !isPlacing, !isFullScreen(), let window, let (container, bar) = Self.views(of: window),
              let host = container.superview else { return }
        isPlacing = true
        defer { isPlacing = false }
        placeCount += 1
        if let height {
            let frame = NSRect(x: 0, y: host.bounds.height - height, width: host.bounds.width, height: height)
            if container.frame != frame { container.frame = frame; writeCount += 1 }
            if bar.frame != container.bounds { bar.frame = container.bounds; writeCount += 1 }
        }
        for type in Self.buttons {
            guard let button = window.standardWindowButton(type) else { continue }
            var origin = button.frame.origin
            if height != nil { origin.y = ((bar.bounds.height - button.frame.height) / 2).rounded() }
            if let leading { origin.x = leading + (offsets[type] ?? 0) }
            if button.frame.origin != origin { button.setFrameOrigin(origin); writeCount += 1 }
        }
    }

    /// Stops the hook and gives the system layout back. AppKit lays the title bar out afresh on a resize
    /// (measured; `needsLayout` and `layoutIfNeeded` do not), so the window is made one point wider and
    /// narrower again without display.
    func remove() {
        guard !removed else { return }
        removed = true
        frameObservations.removeAll()
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        notificationTokens.removeAll()
        restoreSystemLayout()
    }

    /// Makes AppKit lay the title bar out afresh (see ``remove()``).
    private func restoreSystemLayout() {
        guard let window, !isFullScreen() else { return }
        var frame = window.frame
        let original = frame
        frame.size.width += 1
        window.setFrame(frame, display: false)
        window.setFrame(original, display: false)
    }
}
