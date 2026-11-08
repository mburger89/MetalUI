import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
import MetalUIRender
@testable import MetalUIPlatform
@testable import MetalUIAppKit

// App shell, lane 1, tests 1.3–1.11 and 1.18 (rulings `AS-B`…`AS-H`, `AS-J`;
// spec `docs/superpowers/specs/2026-10-08-app-shell-design.md` §4.1). A real
// `AppKitPlatform` window and its own `NSWindow`, `MetalHostView` and real
// `NSEvent`s; the application delegate driven directly, its two AppKit calls
// (`NSApp.terminate`, `NSApp.reply(toApplicationShouldTerminate:)`) injected so
// no test ends the test process. Then the fakes (1.18). Nothing sleeps. Red
// before: the file does not compile at `cd0b143` (no member exists).

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private final class ConstantSignal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(false) }
}

@MainActor private final class Counter {
    var count = 0
    var values: [String] = []
}

/// A real 400 × 200 AppKit window, its `onInput` declining everything.
@MainActor private func shellWindow(_ name: String) throws -> (AppKitPlatform, AppKitWindow, NSWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let platformWindow = try platform.openWindow(title: "App shell \(name) \(UUID().uuidString)",
                                                 size: Size(width: px(400), height: px(200)))
    let appKit = try #require(platformWindow as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    appKit.onInput = { _ in false }
    return (platform, appKit, nsWindow)
}

/// A primary mouse-down at AppKit window point `(x, y)` (bottom-left origin)
/// with `clickCount` clicks.
@MainActor private func mouseDown(at x: CGFloat, _ y: CGFloat, clickCount: Int,
                                  in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: x, y: y), modifierFlags: [],
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    eventNumber: 0, clickCount: clickCount, pressure: 1))
}

// MARK: - 1.3, 1.4 — the close veto

/// **1.3** (`AS-B` items 5–6). The `NSWindow`'s delegate — the object AppKit
/// asks before the close button's and ⌘W's close (`performClose:`) — answers
/// `windowShouldClose(_:)` with `onCloseRequest`: `false` refuses and the
/// window stays open with no `onClose`; `true` allows; no handler allows.
///
/// **Asked through the delegate protocol, not by `performClose(_:)`**
/// (ruling `AS-O` item 7): `performClose(_:)` highlights the close button in
/// a nested event loop, after which HIToolbox's pending `CFRunLoopStop`
/// (record §61 §9) ended the test process with exit 0 and no summary line —
/// measured on this file, six of six filtered runs, the stop landing one to
/// three tests later even with the call inside a nested run. The button
/// itself is human check AS1.
///
/// Mutation: `windowShouldClose` answers `true` always → red.
@MainActor
@Test func appKitWindowShouldCloseAsksOnCloseRequest() throws {
    let (_, appKit, nsWindow) = try shellWindow("1.3")
    let asked = Counter(), closed = Counter()
    var answer = false
    appKit.onCloseRequest = { asked.count += 1; return answer }
    appKit.onClose = { closed.count += 1 }
    let delegate = try #require(nsWindow.delegate)
    #expect(delegate === appKit, "AppKit asks the platform window")

    #expect(delegate.windowShouldClose?(nsWindow) == false, "a refusing handler refuses the close")
    #expect(asked.count == 1, "asked once")
    #expect(nsWindow.isVisible && closed.count == 0, "the window stays open, no onClose")

    answer = true
    #expect(delegate.windowShouldClose?(nsWindow) == true, "an allowing handler allows it")
    #expect(asked.count == 2)
    appKit.onCloseRequest = nil
    #expect(delegate.windowShouldClose?(nsWindow) == true, "no handler: the close goes ahead")
    #expect(asked.count == 2 && closed.count == 0, "asking closes nothing by itself")
    nsWindow.close()
    #expect(closed.count == 1, "the close that follows fires onClose once")
}

/// **1.4** (`AS-B` item 5). `close()` closes without asking — the handler
/// that would refuse is not called — and `onClose` follows exactly once; a
/// second `close()` runs nothing (AppKit sends `windowWillClose` once).
///
/// Mutation: `close()` calls `performClose(nil)` → red.
@MainActor
@Test func appKitCloseClosesWithoutAskingAndFiresOnCloseOnce() throws {
    let (_, appKit, nsWindow) = try shellWindow("1.4")
    let asked = Counter(), closed = Counter()
    appKit.onCloseRequest = { asked.count += 1; return false }
    appKit.onClose = { closed.count += 1 }
    appKit.close()
    #expect(asked.count == 0, "close() asks nobody")
    #expect(!nsWindow.isVisible, "and closes")
    #expect(closed.count == 1, "onClose once")
    appKit.close()
    #expect(closed.count == 1, "a second close() runs nothing")
}

// MARK: - 1.5 — edited marker and represented file

/// **1.5** (`AS-D` item 5; probe `N3`). `setDocumentEdited` reaches
/// `NSWindow.isDocumentEdited`; `setRepresentedFilePath` reaches
/// `representedURL` as a file URL and `nil` clears it; neither changes the
/// title.
///
/// Mutation: `setRepresentedFilePath(nil)` ignored → red.
@MainActor
@Test func appKitDocumentEditedAndRepresentedPathReachTheNSWindow() throws {
    let (_, appKit, nsWindow) = try shellWindow("1.5")
    let title = nsWindow.title
    appKit.setDocumentEdited(true)
    #expect(nsWindow.isDocumentEdited)
    appKit.setRepresentedFilePath("/tmp/x.mcgraph")
    #expect(nsWindow.representedURL?.path == "/tmp/x.mcgraph")
    #expect(nsWindow.representedURL?.isFileURL == true)
    #expect(nsWindow.title == title, "neither changes the title (N3)")
    appKit.setDocumentEdited(false)
    #expect(!nsWindow.isDocumentEdited)
    appKit.setRepresentedFilePath(nil)
    #expect(nsWindow.representedURL == nil, "nil clears the represented file")
    #expect(nsWindow.title == title)
    nsWindow.close()
}

// MARK: - 1.6, 1.7, 1.7b — the hidden title bar

/// **1.6** (`AS-E` items 2, 4, 5; probes `H0`, `F0`). `.hidden` answers `true`
/// and sets the three flags SwiftUI sets — `.fullSizeContentView`, a
/// transparent title bar, a hidden title — so the host view fills the frame:
/// `contentSize.height` grows by the band. The insets read the band's height
/// (`frame − contentLayoutRect`) and the zoom button's right edge in window
/// coordinates. `.standard` restores all three, the content size and zero
/// insets.
///
/// Mutations: omit `titlebarAppearsTransparent` → red; insets always zero → red.
@MainActor
@Test func appKitHiddenTitleBarSetsSwiftUIsFlagsAndReportsTheBand() throws {
    let (_, appKit, nsWindow) = try shellWindow("1.6")
    let before = appKit.contentSize
    #expect(appKit.titleBarInsets == Edges(all: px(0)), "a standard window reports no band")

    #expect(appKit.setTitleBarStyle(.hidden) == true)
    #expect(nsWindow.styleMask.contains(.fullSizeContentView))
    #expect(nsWindow.titlebarAppearsTransparent)
    #expect(nsWindow.titleVisibility == .hidden)
    let band = nsWindow.frame.height - nsWindow.contentLayoutRect.height
    try #require(band > 0, "the title bar has a band: \(band)")
    #expect(appKit.contentSize.height.value == before.height.value + Float(band),
            "the content grows under the bar: \(before) → \(appKit.contentSize), band \(band)")
    let zoom = try #require(nsWindow.standardWindowButton(.zoomButton))
    let zoomRight = zoom.convert(zoom.bounds, to: nil).maxX
    #expect(appKit.titleBarInsets == Edges(top: px(Float(band)), right: px(0), bottom: px(0),
                                           left: px(Float(zoomRight))),
            "insets: \(appKit.titleBarInsets), band \(band), zoom right \(zoomRight)")
    print("AS-E band=\(band) zoomRight=\(zoomRight)")

    #expect(appKit.setTitleBarStyle(.standard) == true)
    #expect(!nsWindow.styleMask.contains(.fullSizeContentView))
    #expect(!nsWindow.titlebarAppearsTransparent)
    #expect(nsWindow.titleVisibility == .visible)
    #expect(appKit.contentSize == before, "the standard style's content size is back")
    #expect(appKit.titleBarInsets == Edges(all: px(0)))
    nsWindow.close()
}

/// **1.7** (`AS-E` item 5). Under the hidden bar, a change of the band that
/// changes no content size — a toolbar arriving — reaches `onResize` through
/// the `contentLayoutRect` observation, and the insets read the taller band.
///
/// Mutation: drop the KVO → red.
@MainActor
@Test func appKitTitleBarBandChangeReportsAResize() throws {
    let (_, appKit, nsWindow) = try shellWindow("1.7")
    #expect(appKit.setTitleBarStyle(.hidden))
    let before = appKit.titleBarInsets.top
    let sizeBefore = appKit.contentSize
    let resized = Counter()
    appKit.onResize = { _, _ in
        resized.count += 1
        resized.values.append("\(appKit.titleBarInsets.top.value)")
    }
    _ = appKit.setToolbar(PlatformToolbar(items: [
        PlatformToolbarItem(id: "a", placement: .automatic, control: .button(title: "A", image: nil)),
    ]))
    #expect(appKit.titleBarInsets.top.value > before.value,
            "the band grew with the toolbar: \(before) → \(appKit.titleBarInsets.top)")
    #expect(appKit.contentSize == sizeBefore, "the content size did not change: \(sizeBefore) → \(appKit.contentSize)")
    #expect(resized.values.contains("\(appKit.titleBarInsets.top.value)"),
            "onResize reported the new band: \(resized.values)")
    nsWindow.close()
}

/// **1.7b** (`AS-J` item 2). `performTitleBarPress(clickCount:)` acts only
/// while the host view is dispatching a mouse-down: a real `NSEvent` through
/// `mouseDown(with:)` whose `onInput` calls it with 1 drags with that very
/// event and answers `true`; called after the dispatch returned it answers
/// `false` and runs nothing; with 2 it runs the title bar's double-click
/// action; with 3 it answers `false`.
///
/// Mutations: keep the event after `mouseDown` returns → the outside arm red;
/// ignore `clickCount` → red.
@MainActor
@Test func appKitTitleBarPressDragsOnlyDuringAMouseDown() throws {
    let (_, appKit, nsWindow) = try shellWindow("1.7b")
    var drags: [NSEvent] = []
    var doubleClicks = 0
    appKit.performTitleBarDrag = { drags.append($0) }
    appKit.performTitleBarDoubleClick = { doubleClicks += 1 }
    var answers: [Bool] = []
    appKit.onInput = { event in
        if case .mouseDown(let mouse) = event {
            answers.append(appKit.performTitleBarPress(clickCount: mouse.clickCount))
        }
        return false
    }

    let single = try mouseDown(at: 100, 190, clickCount: 1, in: nsWindow)
    appKit.hostView.mouseDown(with: single)
    #expect(answers == [true], "the press acted during the dispatch")
    #expect(drags.count == 1 && drags.first === single, "the drag ran once, with the event being dispatched")
    #expect(doubleClicks == 0)

    #expect(appKit.performTitleBarPress(clickCount: 1) == false, "outside a mouse-down: nothing to act on")
    #expect(drags.count == 1, "and nothing ran")

    appKit.hostView.mouseDown(with: try mouseDown(at: 100, 190, clickCount: 2, in: nsWindow))
    #expect(answers == [true, true])
    #expect(doubleClicks == 1 && drags.count == 1, "a double click runs the double-click action, no drag")

    appKit.hostView.mouseDown(with: try mouseDown(at: 100, 190, clickCount: 3, in: nsWindow))
    #expect(answers == [true, true, false], "a triple click does nothing")
    #expect(doubleClicks == 1 && drags.count == 1)
    #expect(appKit.hostView.mouseDownCanMoveWindow == false, "AppKit never drags from the host view itself")
    nsWindow.close()
}

// MARK: - 1.8–1.11 — the application delegate

/// **1.8** (`AS-C` item 7). `applicationShouldTerminate` maps the handler's
/// answer — `.now`, `.cancel`, `.later` → `.terminateNow`, `.terminateCancel`,
/// `.terminateLater`; no handler → `.terminateNow` — and
/// `replyToTerminateRequest` reaches the injected replier once per pending
/// `.terminateLater`, never with none pending.
///
/// Mutation: `.later` → `.terminateCancel` → red.
@MainActor
@Test func appKitApplicationDelegateMapsTheTerminateReply() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let delegate = platform.applicationDelegate
    var replies: [Bool] = []
    delegate.terminateReplier = { replies.append($0) }
    delegate.terminator = { Issue.record("nothing terminates here") }
    let app = NSApplication.shared

    #expect(delegate.applicationShouldTerminate(app) == .terminateNow, "no handler: terminate")
    var answer = CloseRequestReply.now
    platform.onTerminateRequest = { answer }
    #expect(delegate.applicationShouldTerminate(app) == .terminateNow)
    answer = .cancel
    #expect(delegate.applicationShouldTerminate(app) == .terminateCancel)
    answer = .later
    #expect(delegate.applicationShouldTerminate(app) == .terminateLater)
    platform.replyToTerminateRequest(true)
    #expect(replies == [true], "the reply reaches NSApp.reply(toApplicationShouldTerminate:)")
    platform.replyToTerminateRequest(false)
    #expect(replies == [true], "with nothing pending a reply does nothing")
    #expect(delegate.applicationShouldTerminate(app) == .terminateLater)
    platform.replyToTerminateRequest(false)
    #expect(replies == [true, false])
}

/// **1.9** (`AS-C` item 7). `terminate()` approves the termination and calls
/// the injected terminator; the `applicationShouldTerminate` that follows
/// answers `.terminateNow` without asking the handler.
///
/// Mutation: `terminate()` does not set the approval → red.
@MainActor
@Test func appKitTerminateIsApprovedAndAsksNobody() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let delegate = platform.applicationDelegate
    var terminated = 0, asked = 0
    delegate.terminator = { terminated += 1 }
    delegate.terminateReplier = { _ in Issue.record("nothing is answered here") }
    platform.onTerminateRequest = { asked += 1; return .cancel }
    platform.terminate()
    #expect(terminated == 1, "terminate() ends the application")
    #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow,
            "an approved termination is not refused")
    #expect(asked == 0, "and asks nobody")
}

/// **1.10** (`AS-G` items 4–5). `application(_:open:)` hands `onOpenURLs` the
/// URLs' `absoluteString`s in order; URLs that arrive before a handler park
/// and arrive on its assignment, once.
///
/// Mutation: no parking → red.
@MainActor
@Test func appKitOpenURLsReachOnOpenURLsAndParkUntilAHandler() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let delegate = platform.applicationDelegate
    let file = URL(fileURLWithPath: "/tmp/a b.mcgraph")
    let scheme = try #require(URL(string: "metalcreator://x"))
    delegate.application(NSApplication.shared, open: [file, scheme])
    var received: [[String]] = []
    platform.onOpenURLs = { received.append($0) }
    #expect(received == [["file:///tmp/a%20b.mcgraph", "metalcreator://x"]],
            "parked URLs arrive on assignment: \(received)")
    delegate.application(NSApplication.shared, open: [scheme])
    #expect(received == [["file:///tmp/a%20b.mcgraph", "metalcreator://x"], ["metalcreator://x"]],
            "later URLs arrive at once, the parked ones not again: \(received)")
}

/// **1.11** (`AS-C` item 7). `installApplicationDelegate()` — what `run()`
/// calls before `NSApplication.run()` — makes the platform's delegate
/// `NSApp.delegate`. The previous delegate is restored.
///
/// Mutation: install nothing → red.
@MainActor
@Test func runInstallsTheApplicationDelegate() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let previous = NSApplication.shared.delegate
    defer { NSApplication.shared.delegate = previous }
    platform.installApplicationDelegate()
    #expect(NSApplication.shared.delegate === platform.applicationDelegate)
}

// MARK: - 1.18 — the fakes

/// **1.18** (`AS-H` item 4). `FakePlatformWindow` and `FakePlatform` record
/// every app-shell call and simulate the platform's requests: a close request
/// asks `onCloseRequest` and closes only on `true` (or no handler), `close()`
/// fires `onClose` once; a terminate request answers the handler's reply
/// (`.now` with none); open URLs park until a handler is set; the title-bar
/// answer and insets are scripted.
///
/// Mutation: the fake's `simulateCloseRequest` ignores `onCloseRequest` → red.
@MainActor
@Test func theFakesRecordTheAppShellCalls() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let window = try FakePlatformWindow(device: device)
    var closed = 0
    window.onClose = { closed += 1 }
    var answer = false
    window.onCloseRequest = { answer }
    #expect(window.simulateCloseRequest() == false)
    #expect(closed == 0 && !window.isClosed, "a refused request keeps the window")
    answer = true
    #expect(window.simulateCloseRequest() == true)
    #expect(closed == 1 && window.isClosed, "an allowed one closes it")
    window.close()
    #expect(closed == 1, "onClose fires once")
    #expect(window.closeCalls == 2, "close() is counted, the request's included")

    window.setDocumentEdited(true)
    window.setRepresentedFilePath("/tmp/x")
    window.setRepresentedFilePath(nil)
    #expect(window.documentEditedCalls == [true])
    #expect(window.representedPaths == ["/tmp/x", nil])
    #expect(window.setTitleBarStyle(.hidden) == true, "applies by default")
    window.titleBarStyleApplies = false
    #expect(window.setTitleBarStyle(.standard) == false, "a scripted answer")
    #expect(window.titleBarStyles == [.hidden, .standard])
    #expect(window.titleBarInsets == Edges(all: Pixels(0)))
    window.titleBarInsets = Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(69))
    #expect(window.titleBarInsets.top == Pixels(32))
    #expect(window.performTitleBarPress(clickCount: 2) == true)
    #expect(window.titleBarPresses == [2])

    let platform = FakePlatform(device: device)
    #expect(platform.simulateTerminateRequest() == .now, "no handler answers .now")
    platform.onTerminateRequest = { .later }
    #expect(platform.simulateTerminateRequest() == .later)
    platform.replyToTerminateRequest(true)
    platform.terminate()
    #expect(platform.terminateReplies == [true] && platform.terminateCalls == 1)
    platform.simulateOpenURLs(["file:///tmp/a"])
    var opened: [[String]] = []
    platform.onOpenURLs = { opened.append($0) }
    platform.simulateOpenURLs(["metalcreator://x"])
    #expect(opened == [["file:///tmp/a"], ["metalcreator://x"]], "parked, then delivered: \(opened)")
}

// MARK: - AS-R — the app-chosen title-bar band and buttons' inset

/// Installs AppKit's event-queue signal blocks once per process, as `SDLPlatform` does (record §61 §9): runs
/// `-[NSApplication run]` and stops it at once. Without them HIToolbox's event thread wakes the main thread by
/// queueing a `CFRunLoopStop` of the main run loop; the title-bar tests move real windows (live resizes, key
/// changes), and one such stop reaching Swift Testing's outermost loop ended the whole run with exit 0 and no
/// summary line (measured: the unfiltered run died in the next AppKit test). Skipped when AppKit already runs.
@MainActor private let appKitEventSignal: Void = {
    guard let app = NSApp, !app.isRunning else { return }
    let main = CFRunLoopGetMain()
    CFRunLoopPerformBlock(main, CFRunLoopMode.commonModes.rawValue) {
        app.stop(nil)
        if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                         timestamp: 0, windowNumber: 0, context: nil,
                                         subtype: 0, data1: 0, data2: 0) {
            app.postEvent(wake, atStart: true)
        }
    }
    CFRunLoopWakeUp(main)
    app.run()
}()

/// Runs the main run loop for `seconds` so a deferred placement lands (a single pass is enough; the bound is
/// generous and nothing waits on a condition). Each test ends with one, too: the window-server traffic of
/// moving real windows queues a `CFRunLoopStop` on the main loop that is harmless in a nested run and ends the
/// process (exit 0, no summary) when it reaches Swift Testing's outermost loop (record §61 §9).
@MainActor private func drainRunLoop(_ seconds: Double = 0.05) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
}

/// One button's frame in window coordinates, top-down: `(minX, centreY)`.
@MainActor private func buttonPlace(_ type: NSWindow.ButtonType, in window: NSWindow) throws -> (x: CGFloat, centreY: CGFloat) {
    let button = try #require(window.standardWindowButton(type))
    let rect = button.convert(button.bounds, to: nil)
    return (rect.minX, window.frame.height - rect.maxY + rect.height / 2)
}

/// A window under the hidden style, metrics (68, 27) applied.
@MainActor private func placedWindow(_ name: String, height: Float? = 68, leading: Float? = 27) throws
    -> (AppKitWindow, NSWindow) {
    let (_, appKit, nsWindow) = try shellWindow(name)
    _ = appKitEventSignal
    #expect(appKit.setTitleBarStyle(.hidden))
    #expect(appKit.setTitleBarMetrics(height: height, controlsLeading: leading))
    return (appKit, nsWindow)
}

/// **AS-R 1.** The three buttons centre in the chosen band and the close button's left edge is the chosen
/// inset, keeping the system spacing; the insets read the band and the zoom button's moved right edge (read
/// back, not computed); a click still reaches the zoom button (its frame holds the click point and
/// `performClick` runs its action). Mutations: `titleBarInsets` keeps `frame − contentLayoutRect` (top reads
/// the system band); the placement centres by `height / 2` of the system band (centre ≠ 34).
@MainActor
@Test func appKitTitleBarMetricsCentreTheButtonsAndReportTheBandAndEdge() throws {
    let (appKit, nsWindow) = try placedWindow("AS-R 1")
    let close = try buttonPlace(.closeButton, in: nsWindow)
    let zoom = try buttonPlace(.zoomButton, in: nsWindow)
    #expect(close.x == 27 && close.centreY == 34 && zoom.centreY == 34, "\(close) \(zoom)")
    let zoomButton = try #require(nsWindow.standardWindowButton(.zoomButton))
    let zoomRight = zoomButton.convert(zoomButton.bounds, to: nil).maxX
    #expect(appKit.titleBarInsets.top == px(68))
    #expect(appKit.titleBarInsets.left == px(Float(zoomRight)) && zoomRight > 27 + 40, "zoom right \(zoomRight)")
    // Hit testing and performClick on the moved button.
    let centre = zoomButton.convert(NSPoint(x: zoomButton.bounds.midX, y: zoomButton.bounds.midY), to: nil)
    #expect(nsWindow.contentView?.superview?.hitTest(centre) === zoomButton, "the moved button takes the click")
    let counter = Counter()
    let target = ClickTarget(counter)
    let (oldTarget, oldAction) = (zoomButton.target, zoomButton.action)
    zoomButton.target = target
    zoomButton.action = #selector(ClickTarget.hit(_:))
    zoomButton.performClick(nil)
    zoomButton.target = oldTarget
    zoomButton.action = oldAction
    #expect(counter.count == 1, "performClick runs the moved button's action")
    nsWindow.close()
    drainRunLoop()   // absorb HIToolbox's queued CFRunLoopStop in a nested loop (record §61 §9)
}

@MainActor private final class ClickTarget: NSObject {
    let counter: Counter
    init(_ counter: Counter) { self.counter = counter }
    @objc func hit(_ sender: Any?) { counter.count += 1 }
}

/// **AS-R 2.** The placement survives what resets AppKit's layout: five live `setFrame`s and a `title`
/// change (which fires no notification: only the frame observers see it). Mutations: remove the frame
/// observers (the title arm reddens); defer nothing and re-place synchronously (the process crashes in
/// AppKit's layout, run it to see).
@MainActor
@Test func appKitTitleBarMetricsSurviveResizeAndTitleChange() throws {
    let (_, nsWindow) = try placedWindow("AS-R 2")
    for _ in 0..<5 {
        var frame = nsWindow.frame
        frame.size.width += 20
        frame.size.height += 10
        nsWindow.setFrame(frame, display: true)
        drainRunLoop()
    }
    var close = try buttonPlace(.closeButton, in: nsWindow)
    #expect(close.x == 27 && close.centreY == 34, "after resizes: \(close)")
    nsWindow.title = "A new title"
    drainRunLoop()
    close = try buttonPlace(.closeButton, in: nsWindow)
    #expect(close.x == 27 && close.centreY == 34, "after the title: \(close)")
    nsWindow.close()
    drainRunLoop()   // absorb HIToolbox's queued CFRunLoopStop in a nested loop (record §61 §9)
}

/// **AS-R 3.** Only the set fields move: a height alone centres vertically and leaves x; a leading alone
/// leaves y. Clearing both gives the system layout back (x 9, centre 16 — a resize of AppKit's own), the
/// insets read the system band again, and `.standard` clears a set pair. Mutation: `remove()` skips the
/// relayout (the clear arm stays at 27 / 34).
@MainActor
@Test func appKitTitleBarMetricsApplyPerFieldAndClear() throws {
    let (appKit, nsWindow) = try placedWindow("AS-R 3", height: 68, leading: nil)
    var close = try buttonPlace(.closeButton, in: nsWindow)
    #expect(close.centreY == 34 && close.x < 27, "height only: \(close)")
    _ = appKit.setTitleBarMetrics(height: nil, controlsLeading: 27)
    drainRunLoop()
    close = try buttonPlace(.closeButton, in: nsWindow)
    #expect(close.x == 27 && close.centreY < 34, "leading only: \(close)")
    let band = nsWindow.frame.height - nsWindow.contentLayoutRect.height
    _ = appKit.setTitleBarMetrics(height: nil, controlsLeading: nil)
    drainRunLoop()
    close = try buttonPlace(.closeButton, in: nsWindow)
    #expect(close.x < 27 && close.centreY == band / 2, "cleared: \(close), band \(band)")
    #expect(appKit.titleBarPlacement == nil)
    _ = appKit.setTitleBarMetrics(height: 68, controlsLeading: 27)
    #expect(appKit.titleBarInsets.top == px(68))
    #expect(appKit.setTitleBarStyle(.standard))
    #expect(appKit.titleBarPlacement == nil && appKit.titleBarInsets == Edges(all: px(0)))
    close = try buttonPlace(.closeButton, in: nsWindow)
    #expect(close.x < 27, "the standard style restores the system layout: \(close)")
    nsWindow.close()
    drainRunLoop()   // absorb HIToolbox's queued CFRunLoopStop in a nested loop (record §61 §9)
}

/// **AS-R 4** (the hook's pieces, on `TitleBarPlacement` itself). (a) A settled placement writes nothing: the
/// write counter stays put over further run-loop turns — an unguarded write re-fires the observers and loops.
/// Mutation: drop the equality guards (the counter climbs). (b) Full screen is skipped: with the check
/// answering `true` a reset stays reset; with `false` it is placed. Mutation: drop the guard. (c) The
/// notification backstop re-places with the frame observers off. Mutation: remove the notification observers.
@MainActor
@Test func theTitleBarPlacementsHookPiecesEachHold() throws {
    let (_, appKit, nsWindow) = try shellWindow("AS-R 4")
    _ = appKitEventSignal
    _ = appKit.setTitleBarStyle(.hidden)
    var fullScreen = false
    let placement = try #require(TitleBarPlacement(window: nsWindow, height: 68, leading: 27,
                                                   isFullScreen: { fullScreen }))
    drainRunLoop()
    let settled = placement.writeCount
    drainRunLoop(0.1)
    #expect(placement.writeCount == settled, "(a) no writes once placed: \(settled) → \(placement.writeCount)")
    #expect(settled > 0)

    func reset() throws {
        for type in TitleBarPlacement.buttons {
            let button = try #require(nsWindow.standardWindowButton(type))
            button.setFrameOrigin(NSPoint(x: button.frame.minX - 18, y: button.frame.minY + 10))
        }
        drainRunLoop()
    }
    fullScreen = true
    try reset()
    placement.schedule()
    drainRunLoop()
    #expect(try buttonPlace(.closeButton, in: nsWindow).x < 27 + 1 - 18 + 1, "(b) not placed in full screen")
    fullScreen = false
    placement.schedule()
    drainRunLoop()
    #expect(try buttonPlace(.closeButton, in: nsWindow).x == 27, "(b) placed again outside it")
    placement.remove()

    let backstop = try #require(TitleBarPlacement(window: nsWindow, height: 68, leading: 27, observesFrames: false))
    try reset()
    #expect(try buttonPlace(.closeButton, in: nsWindow).x != 27)
    for name in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
        try reset()
        NotificationCenter.default.post(name: name, object: nsWindow)
        drainRunLoop()
        #expect(try buttonPlace(.closeButton, in: nsWindow).x == 27, "(c) \(name.rawValue) re-places")
    }
    backstop.remove()
    nsWindow.close()
    drainRunLoop()   // absorb HIToolbox's queued CFRunLoopStop in a nested loop (record §61 §9)
}
