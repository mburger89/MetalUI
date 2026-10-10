import Foundation
import MetalUICore
import MetalUIPlatform

// The window half of the app shell (rulings `AS-B`, `AS-D`, `AS-E`, `AS-J`,
// `AS-K`; spec `docs/superpowers/specs/2026-10-08-app-shell-design.md` §1.2):
// the close veto's state machine, the title, the edited marker and the
// represented file, the title-bar style and its band press, and the window's
// `.onOpenURL` handlers. `Window.swift` holds one stored `shell` and the hooks
// that call in here.

/// A window's title-bar style — SwiftUI's `.windowStyle(_:)` scene modifier,
/// given as `App.openWindow(…, windowStyle:)` and `Window.windowStyle`
/// because MetalUI has no `Scene` (ruling `AS-E`).
///
/// A closed set, where SwiftUI's `WindowStyle` is a protocol with style types:
/// `.windowStyle(HiddenTitleBarWindowStyle())` and `.plain` are not offered.
public struct WindowStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case automatic, titleBar, hiddenTitleBar }
    let kind: Kind

    /// The platform's default — the standard title bar (`.titleBar`).
    public static let automatic = WindowStyle(kind: .automatic)
    /// The standard title bar: the content sits below it.
    public static let titleBar = WindowStyle(kind: .titleBar)
    /// A transparent title bar with its title hidden and the window buttons
    /// kept; the content lays out **under** it, the whole window's height
    /// (divergence 175: SwiftUI keeps a safe area). Read
    /// `EnvironmentValues.titleBarInsets` to keep clear of the buttons; a press
    /// no element claims in the band drags the window (`AS-J`). On SDL the
    /// window keeps its system decoration and the insets read zero (`AS-E`
    /// item 6).
    public static let hiddenTitleBar = WindowStyle(kind: .hiddenTitleBar)

    /// What the platform window is asked for.
    var platformStyle: PlatformTitleBarStyle { kind == .hiddenTitleBar ? .hidden : .standard }
}

/// One `.onOpenURL` present in a build: the action and the element it is
/// dispatched to (`AS-G` item 2).
struct OpenURLHandler {
    let owner: GlobalElementID
    let action: @MainActor (URL) -> Void
}

/// `Window`'s app-shell state, one stored value (`Window.shell`).
struct WindowShellState {
    var title = ""
    var isDocumentEdited = false
    var representedURL: URL?
    var windowStyle = WindowStyle.automatic
    /// The style last sent to the platform; `.standard` until a hidden one is.
    var sentTitleBarStyle = PlatformTitleBarStyle.standard
    /// Whether the platform applied the hidden style (its answer, `AS-E`
    /// item 5); `false` under the standard one.
    var titleBarStyleApplied = false
    var onCloseRequest: (@MainActor () -> CloseRequestReply)?
    var isCloseRequestPending = false
    /// Set once by the platform's close (`onClose`) or ``Window/close()``.
    var isClosed = false
    /// Told every outcome of a pending close request — `App`'s termination
    /// walk (`AS-K` item 2).
    var closeRequestResolved: (@MainActor (Bool) -> Void)?
    /// The last build's `.navigationTitle` / `.navigationDocument`.
    var treeTitle: String?
    var treeDocument: URL?
    /// What the platform was last sent: the title (initially the opening
    /// one) and the represented path (initially none).
    var sentTitle = ""
    var sentPath: String?
    /// The last build's `.onOpenURL` handlers, in post-order.
    var openURLHandlers: [OpenURLHandler] = []
}

extension Window {
    // MARK: - Title, edited marker, represented file (`AS-D`)

    /// The window's title (ruling `AS-D` item 1, MetalUI-only): initially
    /// `openWindow(title:)`'s, settable at any time. The platform shows the
    /// tree's `.navigationTitle(_:)` while it has one, else this; it is sent
    /// only when that effective title changes. Reads back what was assigned.
    public var title: String {
        get { shell.title }
        set {
            shell.title = newValue
            reconcileTitleAndDocument()
        }
    }

    /// Whether the window's document has unsaved changes — AppKit's edited
    /// dot in the close button (`NSWindow.isDocumentEdited`; ruling `AS-D`
    /// item 4, MetalUI-only: SwiftUI marks only a `DocumentGroup`'s
    /// documents). Sent to the platform when it changes. **SDL records it and
    /// shows nothing**; the title is never altered behind the app's back.
    public var isDocumentEdited: Bool {
        get { shell.isDocumentEdited }
        set {
            guard newValue != shell.isDocumentEdited else { return }
            shell.isDocumentEdited = newValue
            platformWindow.setDocumentEdited(newValue)
        }
    }

    /// The file the window represents (ruling `AS-D` item 3, MetalUI-only;
    /// AppKit's `NSWindow.representedURL`: the proxy icon and the title's
    /// path menu). The tree's `.navigationDocument(_:)` wins while present.
    /// Only a file URL reaches the platform; any other URL represents nothing.
    /// It never changes the title. SDL records it.
    public var representedURL: URL? {
        get { shell.representedURL }
        set {
            shell.representedURL = newValue
            reconcileTitleAndDocument()
        }
    }

    /// Sends the effective title and represented path when either changed:
    /// the tree's (from the last build) else the window's own.
    func reconcileTitleAndDocument() {
        let title = shell.treeTitle ?? shell.title
        if title != shell.sentTitle {
            shell.sentTitle = title
            platformWindow.title = title
        }
        let document = shell.treeDocument ?? shell.representedURL
        let path = document.flatMap { $0.isFileURL ? $0.path : nil }
        if path != shell.sentPath {
            shell.sentPath = path
            platformWindow.setRepresentedFilePath(path)
        }
    }

    /// Reads back what the last build collected (`AS-D` item 2, `AS-G` item
    /// 2): the tree's title and document — applied at once, so a build's
    /// title is in the frame it presents — and its `.onOpenURL` handlers.
    func adoptShellPreferences(of frame: Frame) {
        shell.treeTitle = frame.collectedNavigationTitle
        shell.treeDocument = frame.collectedNavigationDocument
        shell.openURLHandlers = frame.openURLHandlers
        reconcileTitleAndDocument()
    }

    // MARK: - Title-bar style (`AS-E`, `AS-J`)

    /// The window's title-bar style (ruling `AS-E`): `openWindow`'s, settable
    /// later. `.hiddenTitleBar` lays the content out under a transparent bar
    /// and stamps `EnvironmentValues.titleBarInsets`; the platform is asked
    /// only when the style it would show changes (`.automatic` and
    /// `.titleBar` are both the standard bar).
    public var windowStyle: WindowStyle {
        get { shell.windowStyle }
        set {
            shell.windowStyle = newValue
            applyWindowStyle()
        }
    }

    /// Sends the style when the platform's would change, keeping its answer.
    func applyWindowStyle() {
        let style = shell.windowStyle.platformStyle
        guard style != shell.sentTitleBarStyle else { return }
        shell.sentTitleBarStyle = style
        let applied = platformWindow.setTitleBarStyle(style)
        shell.titleBarStyleApplied = applied && style == .hidden
        setNeedsRedraw()
    }

    /// Whether the platform applied the hidden style (`AS-E` item 5; tests).
    var titleBarStyleApplied: Bool { shell.titleBarStyleApplied }

    /// The insets the root is stamped with (`AS-E` item 4): the platform's
    /// while it shows the hidden style, zero otherwise.
    var effectiveTitleBarInsets: Edges<Pixels> {
        shell.titleBarStyleApplied ? platformWindow.titleBarInsets : Edges(all: Pixels(0))
    }

    /// The band press (ruling `AS-J`), at the end of `onInput`'s path when
    /// nothing claimed the event: a primary press in the hidden title bar's
    /// band with no opaque hitbox under it (`active`, the one ranking's
    /// answer for this press) and no gesture arena formed asks the platform
    /// to drag the window — or, for a double click, to run the title bar's
    /// double-click action. No lookup of its own.
    func answerUnclaimedTitleBarPress(_ event: InputEvent) {
        guard case .mouseDown(let mouse) = event,
              shell.windowStyle == .hiddenTitleBar, shell.titleBarStyleApplied,
              mouse.position.y.value < effectiveTitleBarInsets.top.value,
              active == nil, !hasGestureArena else { return }
        _ = platformWindow.performTitleBarPress(clickCount: mouse.clickCount)
    }

    // MARK: - The close veto (`AS-B`, `AS-K`)

    /// Asked before a user's close — the close button, ⌘W, SDL's
    /// `SDL_EVENT_WINDOW_CLOSE_REQUESTED` (the window manager's close,
    /// Alt-F4), ``performClose()``, and each window in turn on a quit with no
    /// `App.onTerminateRequest` (ruling `AS-B`, MetalUI-only: SwiftUI has no
    /// close veto). `nil` (the default) closes at once.
    ///
    /// Return `.now` to close, `.cancel` to keep the window, or `.later` to
    /// keep it and answer with ``replyToCloseRequest(_:)`` — typically from
    /// an `.alert` the handler presents by setting an `@Observable` model the
    /// tree reads. While a request is pending, further requests keep the
    /// window and run nothing. **A `.later` that is never answered leaves a
    /// window only ``close()`` can close.** It runs outside every phase.
    public var onCloseRequest: (@MainActor () -> CloseRequestReply)? {
        get { shell.onCloseRequest }
        set { shell.onCloseRequest = newValue }
    }

    /// Whether a close request answered `.later` awaits
    /// ``replyToCloseRequest(_:)``.
    public var isCloseRequestPending: Bool { shell.isCloseRequestPending }

    /// Answers a pending close request: `true` closes the window, `false`
    /// keeps it and forgets the request. With nothing pending it does
    /// nothing (``close()`` is the unconditional spelling).
    public func replyToCloseRequest(_ shouldClose: Bool) {
        guard shell.isCloseRequestPending else { return }
        shell.isCloseRequestPending = false
        if shouldClose { close() }
        shell.closeRequestResolved?(shouldClose)
    }

    /// Closes the window now, asking nobody — AppKit's `close()`. Every
    /// present `onDisappear` runs once; a pending close request is answered
    /// `true` (`AS-K` item 2). A closed window draws nothing more.
    public func close() {
        guard !shell.isClosed else { return }
        platformWindow.close()
        // The platform's `onClose` normally marked it; a window no `App`
        // opened has nobody listening.
        if !shell.isClosed {
            noteClosed()
            resolvePendingCloseRequest()
        }
    }

    /// Asks exactly as the close button does, and closes if the answer allows
    /// — AppKit's `performClose(_:)`.
    public func performClose() {
        if answerCloseRequest() { close() }
    }

    /// The platform's question (`PlatformWindow.onCloseRequest`, `AS-B` item
    /// 5) and the termination walk's: closed or pending → `false` (the
    /// handler is not run); no handler or `.now` → `true`; `.cancel` →
    /// `false`; `.later` → pending, `false`.
    func answerCloseRequest() -> Bool {
        guard !shell.isClosed, !shell.isCloseRequestPending else { return false }
        guard let handler = shell.onCloseRequest else { return true }
        switch handler() {
        case .now: return true
        case .cancel: return false
        case .later:
            shell.isCloseRequestPending = true
            return false
        }
    }

    /// Installs the window's half of the seam (from `init`): the opening
    /// title as the one already sent, and the close question.
    func installShell() {
        shell.title = platformWindow.title
        shell.sentTitle = platformWindow.title
        platformWindow.onCloseRequest = { [weak self] in self?.answerCloseRequest() ?? true }
    }

    /// The real close happened (`AS-B` item 4): marks the window closed and
    /// runs every `onDisappear` once (`LC-J`). Idempotent.
    func noteClosed() {
        guard !shell.isClosed else { return }
        shell.isClosed = true
        runDisappearancesForClose()
    }

    /// A pending request whose window really closed is answered `true`,
    /// once, whatever closed it (`AS-K` item 2).
    func resolvePendingCloseRequest() {
        guard shell.isCloseRequestPending else { return }
        shell.isCloseRequestPending = false
        shell.closeRequestResolved?(true)
    }

    // MARK: - Open URLs (`AS-G`)

    /// The owners of the last build's `.onOpenURL` handlers, in post-order
    /// (tests).
    var openURLHandlerOwners: [GlobalElementID] { shell.openURLHandlers.map(\.owner) }

    /// Runs every handler of the last build once, in reverse post-order,
    /// each under `StateDispatch` for its owner, then marks the window dirty
    /// (`AS-G` item 2).
    func deliverOpenURL(_ url: URL) {
        for handler in shell.openURLHandlers.reversed() {
            StateDispatch.dispatching(to: handler.owner) { handler.action(url) }
        }
        setNeedsRedraw()
    }
}
