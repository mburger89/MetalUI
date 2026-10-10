#if os(macOS)
import AppKit
import MetalUIPlatform

/// `AppKitPlatform`'s `NSApplicationDelegate` (rulings `AS-C` item 7, `AS-G`
/// item 5): it answers `applicationShouldTerminate(_:)` from the platform's
/// `onTerminateRequest` and hands `application(_:open:)`'s URLs to
/// `onOpenURLs`, parking them until a handler is set. Owned by the platform
/// (`NSApp.delegate` is weak) and installed as `NSApp.delegate` by
/// ``AppKitPlatform/run()`` — never in a test process, which does not call
/// `run()`; a test drives it directly.
@MainActor
final class AppKitApplicationDelegate: NSObject, NSApplicationDelegate {
    /// The platform's ``Platform/onTerminateRequest``.
    var onTerminateRequest: (() -> CloseRequestReply)?

    /// Set by ``terminate()``: the termination that follows was approved by
    /// `App`, so `applicationShouldTerminate(_:)` answers `.terminateNow`
    /// without asking.
    private(set) var terminationApproved = false

    /// Ends the application — `NSApp.terminate(nil)` in production; a test
    /// injects a recorder so the test process survives.
    var terminator: @MainActor () -> Void = { NSApplication.shared.terminate(nil) }

    /// Answers a `.terminateLater` — `NSApp.reply(toApplicationShouldTerminate:)`
    /// in production; injectable for the same reason.
    var terminateReplier: @MainActor (Bool) -> Void = { NSApplication.shared.reply(toApplicationShouldTerminate: $0) }

    /// URL strings that arrived before ``onOpenURLs`` was set, in order.
    private var parkedURLs: [[String]] = []

    /// The platform's ``Platform/onOpenURLs``; assigning a handler delivers
    /// the parked URLs to it, each batch once.
    var onOpenURLs: (([String]) -> Void)? {
        didSet {
            guard let onOpenURLs, !parkedURLs.isEmpty else { return }
            let parked = parkedURLs
            parkedURLs = []
            for batch in parked { onOpenURLs(batch) }
        }
    }

    /// ⌘Q, Quit, a logout or shutdown, and ``terminate()``'s own call: the
    /// handler's `.now`/`.cancel`/`.later` as AppKit's
    /// `.terminateNow`/`.terminateCancel`/`.terminateLater`, `nil` answering
    /// `.terminateNow`; an approved termination is not asked about. Pinned by
    /// `appKitApplicationDelegateMapsTheTerminateReply`.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationApproved { return .terminateNow }
        switch onTerminateRequest?() ?? .now {
        case .now: return .terminateNow
        case .cancel: return .terminateCancel
        case .later:
            terminateLaterPending = true
            return .terminateLater
        }
    }

    /// Documents and URLs the system asks the application to open: a Finder
    /// double-click, `open -a`, a drop on the Dock icon, Open Recent, a URL
    /// scheme (the bundle declares `CFBundleDocumentTypes`/`CFBundleURLTypes`,
    /// `docs/packaging.md`). Delivered as `absoluteString`s, in order, or
    /// parked. Pinned by `appKitOpenURLsReachOnOpenURLsAndParkUntilAHandler`.
    func application(_ application: NSApplication, open urls: [URL]) {
        let strings = urls.map(\.absoluteString)
        guard !strings.isEmpty else { return }
        if let onOpenURLs { onOpenURLs(strings) } else { parkedURLs.append(strings) }
    }

    /// Whether a `.terminateLater` awaits its reply.
    private(set) var terminateLaterPending = false

    /// Answers the pending `.terminateLater` (ruling `AS-C` item 6); with
    /// none pending it does nothing — AppKit's reply outside a pending
    /// termination is not called.
    func replyToTerminateRequest(_ shouldTerminate: Bool) {
        guard terminateLaterPending else { return }
        terminateLaterPending = false
        terminateReplier(shouldTerminate)
    }

    /// Ends the application asking nobody: the approval first, then
    /// `NSApp.terminate(nil)`. Pinned by `appKitTerminateIsApprovedAndAsksNobody`.
    func terminate() {
        terminationApproved = true
        terminator()
    }
}
#endif
