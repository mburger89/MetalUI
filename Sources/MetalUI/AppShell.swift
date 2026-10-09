import Foundation
import MetalUIPlatform

// The application half of the app shell (rulings `AS-C`, `AS-G`, `AS-K`;
// spec `docs/superpowers/specs/2026-10-08-app-shell-design.md` §1.2): the
// terminate hook and its window-by-window walk, the last-window rule, closed
// windows retired, and open-URL routing. `App.swift` holds one stored `shell`
// and calls in here.

/// What a pending termination waits on, and who asked.
enum PendingTermination {
    /// The app handler answered `.later`.
    case app(fromPlatform: Bool)
    /// The walk waits on this window's `.later`.
    case window(ObjectIdentifier, fromPlatform: Bool)
}

/// `App`'s app-shell state, one stored value (`App.shell`).
struct AppShellState {
    var onTerminateRequest: (@MainActor () -> CloseRequestReply)?
    var onOpenURL: (@MainActor (URL) -> Void)?
    /// Set once the app's end is approved: later requests answer `.now`, and
    /// a closing window applies no last-window rule.
    var endingApproved = false
    /// Set while a termination request is being decided (`AS-K` item 1): a
    /// window's close then applies no last-window rule — the walk alone ends
    /// the app.
    var terminationInProgress = false
    var pending: PendingTermination?
    /// Closed windows, kept until the main queue's next turn so a `Window`
    /// outlives its platform's close callback (`AS-K` item 3).
    var retiredWindows: [Window] = []
}

extension App {
    // MARK: - Termination (`AS-C`, `AS-K`)

    /// Asked before the application ends — ⌘Q and the application menu's
    /// Quit, a logout or shutdown (AppKit's `applicationShouldTerminate`),
    /// SDL's `SDL_EVENT_QUIT` (⌘Q under SDL on macOS, SIGINT on Unix, a
    /// session's end) and ``terminate()`` (ruling `AS-C`, MetalUI-only:
    /// SwiftUI has no terminate hook).
    ///
    /// **When set it alone decides**: `.now` ends the app, `.cancel` keeps
    /// it, `.later` waits for ``replyToTerminateRequest(_:)``. **When `nil`
    /// (the default), every open window's `Window.onCloseRequest` is asked in
    /// turn**, in open order — `.now` closes that window and moves on,
    /// `.cancel` cancels the quit (windows already closed stay closed),
    /// `.later` waits for that window's reply — and the app ends when every
    /// window has closed. Either way an approved end closes every remaining
    /// window first, so each `onDisappear` runs once. While a request is
    /// pending a repeated one asks nobody.
    public var onTerminateRequest: (@MainActor () -> CloseRequestReply)? {
        get { shell.onTerminateRequest }
        set { shell.onTerminateRequest = newValue }
    }

    /// Answers a termination ``onTerminateRequest`` deferred with `.later`:
    /// `true` closes every window and ends the app, `false` keeps it. With
    /// nothing pending it does nothing.
    public func replyToTerminateRequest(_ shouldTerminate: Bool) {
        guard case .app(let fromPlatform) = shell.pending else { return }
        shell.pending = nil
        if shouldTerminate {
            endEverything()
            finishApprovedTermination(fromPlatform: fromPlatform)
        } else {
            cancelTermination(fromPlatform: fromPlatform)
        }
    }

    /// Asks to end the application exactly as ⌘Q does (``onTerminateRequest``,
    /// else every window in turn) and, once approved — now or by a later
    /// reply — closes every window and ends the platform's event loop.
    public func terminate() {
        if answerTerminateRequest(fromPlatform: false) == .now { platform.terminate() }
    }

    /// The platform's question (`Platform.onTerminateRequest`, `AS-C` item 6)
    /// and ``terminate()``'s.
    func answerTerminateRequest(fromPlatform: Bool) -> CloseRequestReply {
        if shell.endingApproved { return .now }
        if shell.pending != nil { return .later }
        shell.terminationInProgress = true
        if let handler = shell.onTerminateRequest {
            switch handler() {
            case .now:
                endEverything()
                return .now
            case .cancel:
                shell.terminationInProgress = false
                return .cancel
            case .later:
                shell.pending = .app(fromPlatform: fromPlatform)
                return .later
            }
        }
        return walkWindows(fromPlatform: fromPlatform)
    }

    /// Asks each open window in open order (`AS-C` item 2): a `true` answer
    /// closes it and moves on; a window left pending makes the termination
    /// pending on it; any other refusal cancels. All closed → the end.
    private func walkWindows(fromPlatform: Bool) -> CloseRequestReply {
        for window in windows where !window.shell.isClosed {
            if window.answerCloseRequest() {
                window.close()
                continue
            }
            if window.isCloseRequestPending {
                shell.pending = .window(ObjectIdentifier(window), fromPlatform: fromPlatform)
                return .later
            }
            shell.terminationInProgress = false
            return .cancel
        }
        endEverything()
        return .now
    }

    /// A window's pending close request was answered (`AS-K` item 2): when
    /// the walk waits on it, `true` resumes the walk and `false` cancels.
    func windowCloseRequestResolved(_ window: Window, _ closed: Bool) {
        guard case .window(let id, let fromPlatform) = shell.pending, id == ObjectIdentifier(window) else {
            return
        }
        shell.pending = nil
        guard closed else { return cancelTermination(fromPlatform: fromPlatform) }
        switch walkWindows(fromPlatform: fromPlatform) {
        case .now: finishApprovedTermination(fromPlatform: fromPlatform)
        case .cancel: if fromPlatform { platform.replyToTerminateRequest(false) }
        case .later: break
        }
    }

    /// An end approved after `.later`: the platform that asked is answered;
    /// ``terminate()``'s ends the loop itself.
    private func finishApprovedTermination(fromPlatform: Bool) {
        if fromPlatform {
            platform.replyToTerminateRequest(true)
        } else {
            platform.terminate()
        }
    }

    private func cancelTermination(fromPlatform: Bool) {
        shell.terminationInProgress = false
        if fromPlatform { platform.replyToTerminateRequest(false) }
    }

    /// The approved end (`AS-C` item 3): every remaining window closes, so
    /// each `onDisappear` runs once before the process ends.
    private func endEverything() {
        shell.endingApproved = true
        for window in windows { window.close() }
    }

    // MARK: - Windows (`AS-C` item 5, `AS-K` item 3)

    /// Wires a new window to the app: its platform's close and its pending
    /// close request's outcome.
    func adoptShell(_ window: Window, _ platformWindow: any PlatformWindow) {
        platformWindow.onClose = { [weak self, weak window] in
            guard let window else { return }
            if let self { self.windowDidClose(window) } else { window.noteClosed() }
        }
        window.shell.closeRequestResolved = { [weak self, weak window] closed in
            guard let self, let window else { return }
            self.windowCloseRequestResolved(window, closed)
        }
    }

    /// The platform closed `window`: every `onDisappear` once (`LC-J`), the
    /// window retired, a pending close request answered (`AS-K` item 2), and
    /// — when it was the last window and no termination is being decided —
    /// the app ends without asking (`AS-C` item 5: the close was the answer).
    private func windowDidClose(_ window: Window) {
        window.noteClosed()
        retire(window)
        window.resolvePendingCloseRequest()
        if windows.isEmpty, !shell.endingApproved, !shell.terminationInProgress {
            shell.endingApproved = true
            platform.terminate()
        }
    }

    /// Moves `window` from ``windows`` to the retired list, emptied on the
    /// main queue's next turn (both platforms drain it; `SV-H`).
    private func retire(_ window: Window) {
        windows.removeAll { $0 === window }
        shell.retiredWindows.append(window)
        guard shell.retiredWindows.count == 1 else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.shell.retiredWindows.removeAll() }
        }
    }

    // MARK: - Open URLs (`AS-G`)

    /// Run for a URL the application is asked to open when no open window
    /// has an `.onOpenURL` (ruling `AS-G` item 2, MetalUI-only): the place to
    /// open a window for a document. `nil` (the default) drops it.
    public var onOpenURL: (@MainActor (URL) -> Void)? {
        get { shell.onOpenURL }
        set { shell.onOpenURL = newValue }
    }

    /// Delivers `urls` exactly as the platform delivers an open (ruling `AS-G`
    /// items 2 and 6): each to one window's `.onOpenURL` handlers — the key
    /// window with one, else the first open window with one — else to
    /// ``onOpenURL``. MetalUI reads no command line: to open launch arguments
    /// on Linux, Windows or under `swift run`, pass the ones that are
    /// documents, e.g. `app.open(CommandLine.arguments.dropFirst().filter {
    /// FileManager.default.fileExists(atPath: $0) }.map(URL.init(fileURLWithPath:)))`.
    public func open(_ urls: [URL]) {
        for url in urls {
            let candidates = windows.filter { !$0.shell.isClosed && !$0.shell.openURLHandlers.isEmpty }
            if let target = candidates.first(where: { $0.controlActiveState == .key }) ?? candidates.first {
                target.deliverOpenURL(url)
            } else {
                shell.onOpenURL?(url)
            }
        }
    }

    /// Installs the app's half of the seam (from every initialiser).
    func installShellHandlers() {
        platform.onTerminateRequest = { [weak self] in
            self?.answerTerminateRequest(fromPlatform: true) ?? .now
        }
        platform.onOpenURLs = { [weak self] strings in
            self?.open(strings.compactMap(URL.init(string:)))
        }
    }
}
