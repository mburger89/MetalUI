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

/// **1.3** (`AS-B` items 5–6). `windowShouldClose(_:)` asks `onCloseRequest`:
/// `false` keeps the window open through `performClose(nil)` (the close
/// button's and ⌘W's path) and fires no `onClose`; `true` closes it and fires
/// `onClose` once; no handler closes.
///
/// Mutation: `windowShouldClose` answers `true` always → red.
@MainActor
@Test func appKitWindowShouldCloseAsksOnCloseRequest() throws {
    let (_, appKit, nsWindow) = try shellWindow("1.3")
    let asked = Counter(), closed = Counter()
    var answer = false
    appKit.onCloseRequest = { asked.count += 1; return answer }
    appKit.onClose = { closed.count += 1 }

    nsWindow.performClose(nil)
    #expect(asked.count == 1, "the close button's path asked once")
    #expect(nsWindow.isVisible, "a refused close leaves the window open")
    #expect(closed.count == 0, "and fires no onClose")

    answer = true
    nsWindow.performClose(nil)
    #expect(asked.count == 2)
    #expect(!nsWindow.isVisible, "an allowed close closes")
    #expect(closed.count == 1, "onClose fires once")

    let (_, unasked, unaskedWindow) = try shellWindow("1.3 nil")
    let closedToo = Counter()
    unasked.onClose = { closedToo.count += 1 }
    unaskedWindow.performClose(nil)
    #expect(!unaskedWindow.isVisible && closedToo.count == 1, "no handler: the close goes ahead")
}

/// **1.4** (`AS-B` item 5). `close()` closes without asking — the handler
/// that would refuse is not called — and `onClose` follows exactly once.
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
    appKit.performWindowDrag = { drags.append($0) }
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
/// `replyToTerminateRequest` reaches the injected replier.
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
    platform.replyToTerminateRequest(false)
    #expect(replies == [true, false], "the reply reaches NSApp.reply(toApplicationShouldTerminate:)")
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
