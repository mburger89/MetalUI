import Testing
import Foundation
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// App shell, lane 2, tests 2.2–2.15, 2.21, 2.21b, 2.22 (rulings `AS-B`,
// `AS-C`, `AS-E`, `AS-J`, `AS-K`; spec
// `docs/superpowers/specs/2026-10-08-app-shell-design.md` §4.2). Headless:
// an `App` over `FakePlatform`, whose windows are `FakePlatformWindow`s
// (lane 1's fakes, `AS-O` item 5). A close request is the fake's
// `simulateCloseRequest()` (the close button, ⌘W, SDL's
// `SDL_EVENT_WINDOW_CLOSE_REQUESTED`); a termination request is
// `simulateTerminateRequest()` (⌘Q, `SDL_EVENT_QUIT`).

// MARK: - Harness

/// What the trees and handlers below record, in order.
@MainActor final class ShellLog {
    var entries: [String] = []
}

/// An `App` over a fresh `FakePlatform`.
@MainActor func shellApp() throws -> (App, FakePlatform) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platform = FakePlatform(device: device)
    return (App(platform: platform), platform)
}

/// Opens a window whose root `Column` holds one box whose `onDisappear`
/// appends `"<name> disappeared"` to `log`, and answers the window and its fake.
@MainActor func shellWindow(_ app: App, _ platform: FakePlatform, _ name: String, _ log: ShellLog,
                            windowStyle: WindowStyle = .automatic) throws -> (Window, FakePlatformWindow) {
    let window = try app.openWindow(title: name, size: Size(width: Pixels(64), height: Pixels(64)),
                                    windowStyle: windowStyle, startsDisplayLink: false) {
        Column {
            Box().frame(width: Pixels(20), height: Pixels(20))
                .onDisappear { log.entries.append("\(name) disappeared") }
        }
    }
    return (window, try #require(platform.openedWindows.last))
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

// MARK: - 2.2–2.7: the window's close request

/// **2.2** (`AS-B` item 2). With no handler a close request closes: the
/// window's installed question answers `true`. The control for 2.3.
@MainActor
@Test func aCloseRequestWithNoHandlerCloses() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (window, fake) = try shellWindow(app, platform, "A", log)
    try #require(fake.onCloseRequest != nil, "the window installs its question (AS-B item 5)")
    #expect(fake.simulateCloseRequest())
    #expect(fake.isClosed)
    #expect(log.entries == ["A disappeared"])
    withExtendedLifetime(window) {}
}

/// **2.3** (`AS-B` item 2). `.cancel` keeps the window and forgets the
/// request; no `onDisappear` runs (item 4: only the real close runs
/// `onClose`). Mutation: `answerCloseRequest` returns `true` for `.cancel`.
@MainActor
@Test func aCancelledCloseRequestKeepsTheWindowAndRunsNoOnDisappear() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (window, fake) = try shellWindow(app, platform, "A", log)
    var asked = 0
    window.onCloseRequest = { asked += 1; return .cancel }
    #expect(!fake.simulateCloseRequest())
    #expect(!fake.isClosed && fake.closeCalls == 0)
    #expect(!window.isCloseRequestPending)
    #expect(log.entries.isEmpty)
    #expect(!fake.simulateCloseRequest(), "a cancelled request is forgotten: the next one asks again")
    #expect(asked == 2)
}

/// **2.4** (`AS-B` item 2). `.later` keeps the window and marks the request
/// pending; a second request while pending runs no handler; `reply(false)`
/// forgets it (the next request asks again); `reply(true)` closes through the
/// platform once, and `onDisappear` runs once. Mutations: re-run the handler
/// while pending; `reply(true)` without `close()`.
@MainActor
@Test func aDeferredCloseWaitsForTheReplyAndAsksOnlyOnce() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (window, fake) = try shellWindow(app, platform, "A", log)
    var asked = 0
    window.onCloseRequest = { asked += 1; return .later }

    #expect(!fake.simulateCloseRequest())
    #expect(window.isCloseRequestPending && asked == 1)
    #expect(!fake.simulateCloseRequest(), "pending: refused")
    #expect(asked == 1, "pending: the handler is not run again (no second alert)")

    window.replyToCloseRequest(false)
    #expect(!window.isCloseRequestPending && !fake.isClosed)
    #expect(!fake.simulateCloseRequest())
    #expect(asked == 2, "after a refusal the next request asks again")

    window.replyToCloseRequest(true)
    #expect(fake.closeCalls == 1 && fake.isClosed)
    #expect(!window.isCloseRequestPending)
    #expect(log.entries == ["A disappeared"])
    window.replyToCloseRequest(true)
    #expect(fake.closeCalls == 1, "a reply with nothing pending does nothing")
}

@Observable @MainActor final class CloseAlertModel {
    var asking = false
    var binding: Binding<Bool> { Binding(get: { self.asking }, set: { self.asking = $0 }) }
}

/// Holds the window a tree's buttons reply to, set after `openWindow`.
@MainActor final class WindowRef {
    weak var window: Window?
}

/// **2.5** (M6-b end to end; `AS-B` item 3). The close handler sets the
/// model an `.alert` reads and answers `.later`; the next frame presents the
/// alert — drawn (the fake declines, SDL's answer) — and a press on its
/// "Don't Save" closes the window, running `onDisappear`. Second arm: the
/// fake presents natively (AppKit's sheet) and the `.alertResult` for
/// "Cancel" keeps the window. Mutation: `replyToCloseRequest(true)` forgets
/// the request without closing.
@MainActor
@Test func theCloseHandlerPresentsTheDrawnAlertAndItsButtonClosesTheWindow() throws {
    for native in [false, true] {
        let (app, platform) = try shellApp()
        let log = ShellLog()
        let model = CloseAlertModel()
        let ref = WindowRef()
        let window = try app.openWindow(title: "Doc", size: Size(width: px(400), height: px(400)),
                                        startsDisplayLink: false) {
            Column {
                Box().frame(width: px(400), height: px(400))
                    .onDisappear { log.entries.append("disappeared") }
                    .alert("Save changes?", isPresented: model.binding) {
                        Button("Don't Save", role: .destructive) { ref.window?.replyToCloseRequest(true) }
                        Button("Cancel", role: .cancel) { ref.window?.replyToCloseRequest(false) }
                    }
            }
        }
        ref.window = window
        let fake = try #require(platform.openedWindows.last)
        fake.presentsAlertsNatively = native
        fake.simulateResize(to: Size(width: px(400), height: px(400)))
        window.drawFrameIfNeeded()
        window.onCloseRequest = { model.asking = true; return .later }

        #expect(!fake.simulateCloseRequest())
        #expect(window.isCloseRequestPending)
        window.drawFrameIfNeeded()   // the frame that presents the alert
        if !native {
            let drawn = try #require(window.drawnAlert, "the alert is drawn, not native")
            window.setNeedsRedraw()
            window.drawFrameIfNeeded()   // the frame that draws it
            let panel = try #require(window.drawnAlertPanel)
            let index = try #require(drawn.buttons.firstIndex { $0.platform.title == "Don't Save" })
            let button = panel.layout.buttons[index]
            let centre = pt(button.origin.x.value + button.size.width.value / 2,
                            button.origin.y.value + button.size.height.value / 2)
            fake.simulateInput(.mouseDown(MouseEvent(position: centre)))
            fake.simulateInput(.mouseUp(MouseEvent(position: centre)))
            #expect(fake.isClosed, "Don't Save closed the window")
            #expect(log.entries == ["disappeared"])
            #expect(!window.isCloseRequestPending)
        } else {
            let alert = try #require(fake.presentedAlerts.first, "presented natively")
            let index = try #require(alert.buttons.firstIndex { $0.title == "Cancel" })
            fake.simulateInput(.alertResult(AlertResultEvent(token: alert.token, button: index)))
            #expect(!fake.isClosed, "Cancel kept the window")
            #expect(!window.isCloseRequestPending, "and forgot the request")
            #expect(log.entries.isEmpty)
        }
        withExtendedLifetime(window) {}
    }
}

/// **2.6** (`AS-B` item 1). `performClose()` asks as the close button does;
/// `close()` never asks. Mutation: `close()` asks.
@MainActor
@Test func performCloseAsksAndCloseDoesNot() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (window, fake) = try shellWindow(app, platform, "A", log)
    let log2 = ShellLog()
    window.onCloseRequest = {
        log2.entries.append("asked")
        return log2.entries.count == 1 ? .cancel : .now
    }
    window.performClose()
    #expect(log2.entries.count == 1 && !fake.isClosed, "performClose asked, and .cancel kept it")
    window.performClose()
    #expect(log2.entries.count == 2 && fake.isClosed && fake.closeCalls == 1)

    let (other, otherFake) = try shellWindow(app, platform, "B", log)
    var otherAsked = 0
    other.onCloseRequest = { otherAsked += 1; return .cancel }
    other.close()
    #expect(otherAsked == 0, "close() never asks")
    #expect(otherFake.isClosed && otherFake.closeCalls == 1)
}

/// **2.7** (`AS-B` item 4). After the real close the window draws nothing
/// more. Mutation: drop the early return in `drawFrameIfNeeded`.
@MainActor
@Test func aClosedWindowDrawsNoMoreFrames() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (window, fake) = try shellWindow(app, platform, "A", log)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let before = fake.fakeSurface.presentCalls
    try #require(before >= 1, "control: the open window draws")
    window.close()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    fake.simulateTick(timestamp: 1)
    #expect(fake.fakeSurface.presentCalls == before, "no frame after the close")
}

// MARK: - 2.8–2.15: termination

/// **2.8** (`AS-C` item 5). Closing one of two windows does not end the app;
/// the last one's close does, once; `App.windows` drops each closed window.
/// Mutation: terminate on every close.
@MainActor
@Test func closingOneOfTwoWindowsDoesNotTerminate() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (a, fakeA) = try shellWindow(app, platform, "A", log)
    let (b, fakeB) = try shellWindow(app, platform, "B", log)
    try #require(app.windows.count == 2)
    fakeA.simulateCloseRequest()
    #expect(platform.terminateCalls == 0)
    #expect(app.windows.count == 1 && app.windows.first === b)
    fakeB.simulateCloseRequest()
    #expect(platform.terminateCalls == 1)
    #expect(app.windows.isEmpty)
    #expect(platform.terminateReplies.isEmpty)
    withExtendedLifetime(a) {}
}

/// **2.9** (`AS-C` items 2–3, `AS-K` item 1). A quit with no handlers
/// answers `.now`, closing both windows first (each `onDisappear` once); the
/// platform asked, so it ends itself — no `terminate()` from the last close.
/// Mutations: skip `endEverything()`'s closes; apply the last-window rule
/// during the walk (`terminateCalls` 1). The walk closes each window as it
/// goes, so `endEverything()`'s own closes are reached through the app
/// handler's `.now` — the second arm (`AS-P` item 9).
@MainActor
@Test func aQuitWithNoHandlersClosesEveryWindowThenEnds() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (a, fakeA) = try shellWindow(app, platform, "A", log)
    let (b, fakeB) = try shellWindow(app, platform, "B", log)
    #expect(platform.simulateTerminateRequest() == .now)
    #expect(fakeA.isClosed && fakeB.isClosed)
    #expect(log.entries.sorted() == ["A disappeared", "B disappeared"])
    #expect(platform.terminateCalls == 0, "the platform asked: it ends itself on .now")
    #expect(platform.terminateReplies.isEmpty)
    #expect(app.windows.isEmpty)

    // An app handler's `.now`: no window is asked, every window still closes
    // first, each `onDisappear` once.
    let (app2, platform2) = try shellApp()
    let log2 = ShellLog()
    let (c, fakeC) = try shellWindow(app2, platform2, "C", log2)
    let (d, fakeD) = try shellWindow(app2, platform2, "D", log2)
    app2.onTerminateRequest = { .now }
    #expect(platform2.simulateTerminateRequest() == .now)
    #expect(fakeC.isClosed && fakeD.isClosed)
    #expect(log2.entries.sorted() == ["C disappeared", "D disappeared"])
    #expect(platform2.terminateCalls == 0)
    withExtendedLifetime((a, b, c, d)) {}
}

/// **2.10** (`AS-C` item 2). With `onTerminateRequest` set it alone decides:
/// `.cancel` answers `.cancel`, no window's handler runs, nothing closes.
/// Mutation: ask the windows too.
@MainActor
@Test func theAppHandlerAloneDecides() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (a, fakeA) = try shellWindow(app, platform, "A", log)
    var windowAsked = 0
    a.onCloseRequest = { windowAsked += 1; return .now }
    var appAsked = 0
    app.onTerminateRequest = { appAsked += 1; return .cancel }
    #expect(platform.simulateTerminateRequest() == .cancel)
    #expect(appAsked == 1 && windowAsked == 0)
    #expect(!fakeA.isClosed && log.entries.isEmpty)
    #expect(platform.terminateCalls == 0 && platform.terminateReplies.isEmpty)
}

/// **2.11** (`AS-C` item 4). The app handler's `.later` ends only on the
/// reply: `reply(false)` → the platform is answered `false` and nothing
/// closes; again `.later`, `reply(true)` → every window closed and the
/// platform answered `true`. Mutation: `reply(true)` calls `terminate()`
/// instead of replying.
@MainActor
@Test func aDeferredTerminateEndsOnlyOnTheReply() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (a, fakeA) = try shellWindow(app, platform, "A", log)
    app.onTerminateRequest = { .later }
    #expect(platform.simulateTerminateRequest() == .later)
    app.replyToTerminateRequest(false)
    #expect(platform.terminateReplies == [false])
    #expect(!fakeA.isClosed && log.entries.isEmpty)

    #expect(platform.simulateTerminateRequest() == .later)
    app.replyToTerminateRequest(true)
    #expect(fakeA.isClosed && log.entries == ["A disappeared"])
    #expect(platform.terminateReplies == [false, true])
    #expect(platform.terminateCalls == 0)
    app.replyToTerminateRequest(true)
    #expect(platform.terminateReplies == [false, true], "a reply with nothing pending does nothing")
    withExtendedLifetime(a) {}
}

/// **2.12** (`AS-C` item 2). Without an app handler each window is asked in
/// open order: A `.now`, B `.later` → `.later`, A closed, B open; B's
/// `reply(true)` closes B and answers the platform `true`; the variant
/// `reply(false)` answers `false` and the app runs on. Mutations: ask only the
/// first window; ask B before A closes (the order log).
@MainActor
@Test func withoutAnAppHandlerQuitAsksEachWindowInTurn() throws {
    for approve in [true, false] {
        let (app, platform) = try shellApp()
        let log = ShellLog()
        let (a, fakeA) = try shellWindow(app, platform, "A", log)
        let (b, fakeB) = try shellWindow(app, platform, "B", log)
        a.onCloseRequest = { log.entries.append("ask A"); return .now }
        b.onCloseRequest = { log.entries.append("ask B"); return .later }
        #expect(platform.simulateTerminateRequest() == .later)
        #expect(log.entries == ["ask A", "A disappeared", "ask B"], "\(log.entries)")
        #expect(fakeA.isClosed && !fakeB.isClosed)
        #expect(b.isCloseRequestPending)

        b.replyToCloseRequest(approve)
        if approve {
            #expect(fakeB.isClosed)
            #expect(platform.terminateReplies == [true])
        } else {
            #expect(!fakeB.isClosed)
            #expect(platform.terminateReplies == [false])
            #expect(app.windows.count == 1, "the app runs on with B")
        }
        #expect(platform.terminateCalls == 0, "the platform asked: answered, never terminated")
        withExtendedLifetime((a, b)) {}
    }
}

/// **2.12b** (`AS-K` item 2). A window pending in the walk that the app
/// closes with `close()` resolves its request: the walk resumes and the
/// platform is answered `true`. Mutation: `close()` leaves the pending flag
/// and tells nobody.
@MainActor
@Test func aPendingWindowClosedDirectlyResumesTheQuit() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (a, fakeA) = try shellWindow(app, platform, "A", log)
    let (b, fakeB) = try shellWindow(app, platform, "B", log)
    b.onCloseRequest = { .later }
    #expect(platform.simulateTerminateRequest() == .later)
    #expect(fakeA.isClosed && !fakeB.isClosed)
    b.close()
    #expect(fakeB.isClosed && !b.isCloseRequestPending)
    #expect(platform.terminateReplies == [true])
    #expect(platform.terminateCalls == 0)
    withExtendedLifetime((a, b)) {}
}

/// **2.13** (`AS-C` items 1, 6). `App.terminate()` with no handlers closes
/// every window and ends through `platform.terminate()` once — nothing
/// asked the platform, so nothing is replied. Mutation: reply instead of
/// terminate.
@MainActor
@Test func appTerminateAsksThenEndsThroughThePlatform() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (a, fakeA) = try shellWindow(app, platform, "A", log)
    let (b, fakeB) = try shellWindow(app, platform, "B", log)
    app.terminate()
    #expect(fakeA.isClosed && fakeB.isClosed)
    #expect(platform.terminateCalls == 1)
    #expect(platform.terminateReplies.isEmpty)

    // A deferred `App.terminate()` approved by a window's reply also ends
    // through `terminate()`.
    let (app2, platform2) = try shellApp()
    let (c, fakeC) = try shellWindow(app2, platform2, "C", log)
    c.onCloseRequest = { .later }
    app2.terminate()
    #expect(!fakeC.isClosed && platform2.terminateCalls == 0)
    c.replyToCloseRequest(true)
    #expect(fakeC.isClosed && platform2.terminateCalls == 1 && platform2.terminateReplies.isEmpty)
    withExtendedLifetime((a, b, c)) {}
}

/// **2.14** (`AS-C` item 5). The last window's close ends the app without
/// asking: `terminateCalls == 1`, the app handler's count 0. Mutation: route
/// the last close through `answerTerminateRequest`.
@MainActor
@Test func theLastWindowsCloseEndsTheAppWithoutAsking() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (a, fakeA) = try shellWindow(app, platform, "A", log)
    var appAsked = 0
    app.onTerminateRequest = { appAsked += 1; return .cancel }
    fakeA.simulateCloseRequest()
    #expect(platform.terminateCalls == 1)
    #expect(appAsked == 0)
    withExtendedLifetime(a) {}
}

/// **2.14b** (`AS-K` item 3). A closed window outlives its own close
/// callback: it is retired, not dropped inside `onClose` (released after the
/// main queue's next turn — documented, unpinned: tests do not wait).
/// Mutation: drop it from `windows` inside `onClose`.
@MainActor
@Test func aClosedWindowOutlivesItsOwnCloseCallback() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    weak var weakWindow: Window?
    let fake: FakePlatformWindow
    do {
        let (window, opened) = try shellWindow(app, platform, "A", log)
        weakWindow = window
        fake = opened
        _ = try shellWindow(app, platform, "B", log)   // so the close does not end the app
    }
    try #require(weakWindow != nil, "control: App holds the open window")
    fake.close()
    #expect(weakWindow != nil, "the window outlives the platform's close callback")
    #expect(!app.windows.contains { $0 === weakWindow })
}

/// **2.15** (`AS-C` item 4). A repeated termination request while one is
/// pending answers `.later` and asks nobody. Mutation: re-ask.
@MainActor
@Test func aRepeatedTerminateRequestWhilePendingAsksNobody() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (a, _) = try shellWindow(app, platform, "A", log)
    var appAsked = 0
    app.onTerminateRequest = { appAsked += 1; return .later }
    #expect(platform.simulateTerminateRequest() == .later)
    #expect(platform.simulateTerminateRequest() == .later)
    #expect(appAsked == 1)

    // The walk's pending window is not asked twice either.
    let (app2, platform2) = try shellApp()
    let (b, _) = try shellWindow(app2, platform2, "B", log)
    var windowAsked = 0
    b.onCloseRequest = { windowAsked += 1; return .later }
    #expect(platform2.simulateTerminateRequest() == .later)
    #expect(platform2.simulateTerminateRequest() == .later)
    #expect(windowAsked == 1)
    withExtendedLifetime((app, a, b)) {}
}

// MARK: - 2.21, 2.21b, 2.22: the hidden title bar

/// A greedy leaf recording the `titleBarInsets` it reads in layout and in
/// paint, and the bounds it is painted at.
private struct InsetsProbe: Element {
    @Environment(\.titleBarInsets) var insets
    let record: InsetsRecord
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        record.layout = insets
        return (pass.requestNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? 10, height: proposal.height ?? 10))
        }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        record.paint = insets
        record.bounds = bounds
    }
}

@MainActor private final class InsetsRecord {
    var layout: Edges<Pixels>?
    var paint: Edges<Pixels>?
    var bounds: Bounds<Pixels>?
}

private let zeroInsets = Edges(all: Pixels(0))
private let barInsets = Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(69))

/// **2.21** (`AS-E` items 3–5). The hidden style is applied (`true`) with
/// insets top 32, left 69 and the content grown to 450: the root lays out at
/// 450 and reads (32, 69) in layout and paint. `.titleBar` tells the fake
/// `.standard` and the insets read zero. Mutations: stamp zero; never call
/// `setTitleBarStyle`.
@MainActor
@Test func aHiddenTitleBarLaysTheRootOutUnderTheBarAndStampsTheInsets() throws {
    let (app, platform) = try shellApp()
    let record = InsetsRecord()
    let window = try app.openWindow(title: "W", size: Size(width: px(400), height: px(418)),
                                    startsDisplayLink: false) {
        InsetsProbe(record: record)
    }
    let fake = try #require(platform.openedWindows.last)
    #expect(fake.titleBarStyles.isEmpty, "the standard style asks the platform nothing")
    #expect(record.layout == zeroInsets && record.paint == zeroInsets)

    fake.titleBarInsets = barInsets
    fake.simulateResize(to: Size(width: px(400), height: px(450)))
    window.windowStyle = .hiddenTitleBar
    window.drawFrameIfNeeded()
    #expect(fake.titleBarStyles == [.hidden])
    #expect(window.titleBarStyleApplied)
    #expect(record.bounds?.size.height == px(450), "the root lays out over the band")
    #expect(record.layout == barInsets && record.paint == barInsets)

    window.windowStyle = .titleBar
    fake.simulateResize(to: Size(width: px(400), height: px(418)))
    window.drawFrameIfNeeded()
    #expect(fake.titleBarStyles == [.hidden, .standard])
    #expect(record.layout == zeroInsets && record.paint == zeroInsets,
            "zero under the standard style whatever the platform reports")
}

/// A probe whose band row holds a `Button` (0…60), a draggable box
/// (60…120) and a plain box (120…400), each 20 tall, over a 380-tall box.
@MainActor private func bandTree(_ log: ShellLog) -> some Element {
    Column {
        Row {
            Button("B") { log.entries.append("button") }.frame(width: px(60), height: px(20))
            Box().frame(width: px(60), height: px(20)).draggable("payload")
            Box().frame(width: px(280), height: px(20))
        }
        Box().frame(width: px(400), height: px(380))
    }
}

/// **2.21b** (`AS-J`). Under the hidden style with a 32-point band, a press
/// no stage claims on an empty band point asks the platform to drag (one
/// `titleBarPresses` entry, click count 1); a press on a `Button` in the band
/// does not (its action runs on release); nor one on a `.draggable`; nor one
/// below the band; nor any under `.titleBar`; a double click on the empty band
/// passes click count 2. Mutations: drop `active == nil` (the button arm);
/// drop the arena check (the draggable arm).
@MainActor
@Test func anUnclaimedPressInTheHiddenBandAsksThePlatformToDrag() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let window = try app.openWindow(title: "W", size: Size(width: px(400), height: px(400)),
                                    startsDisplayLink: false) { bandTree(log) }
    let fake = try #require(platform.openedWindows.last)
    fake.simulateResize(to: Size(width: px(400), height: px(400)))
    fake.titleBarInsets = Edges(top: px(32), right: px(0), bottom: px(0), left: px(69))
    window.windowStyle = .hiddenTitleBar
    window.drawFrameIfNeeded()
    try #require(window.titleBarStyleApplied)

    func press(_ x: Float, _ y: Float, clickCount: Int = 1) {
        fake.simulateInput(.mouseDown(MouseEvent(position: pt(x, y), clickCount: clickCount)))
        fake.simulateInput(.mouseUp(MouseEvent(position: pt(x, y), clickCount: clickCount)))
        window.drawFrameIfNeeded()
    }

    let buttonPoint = pt(30, 10)
    try #require(window.lastHitboxes.contains { $0.opaque && $0.bounds.contains(buttonPoint) },
                 "control: the button's opaque hitbox is in the band")
    press(30, 10)
    #expect(fake.titleBarPresses.isEmpty, "a press on a Button is the button's")
    #expect(log.entries == ["button"], "and its action ran on release")

    press(90, 10)
    #expect(fake.titleBarPresses.isEmpty, "a press on a draggable is the drag's (an arena formed)")

    press(200, 100)
    #expect(fake.titleBarPresses.isEmpty, "below the band")

    press(300, 10)
    #expect(fake.titleBarPresses == [1], "an unclaimed band press drags the window")

    press(300, 10, clickCount: 2)
    #expect(fake.titleBarPresses == [1, 2], "a double click passes its click count")

    window.windowStyle = .titleBar
    window.drawFrameIfNeeded()
    press(300, 10)
    #expect(fake.titleBarPresses == [1, 2], "the standard style never asks")
}

/// **2.22** (`AS-E` item 1). `openWindow(windowStyle:)` reaches the platform
/// before the first frame is presented. Mutation: apply after the first frame.
@MainActor
@Test func openWindowAppliesTheWindowStyleBeforeTheFirstFrame() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (window, fake) = try shellWindow(app, platform, "A", log, windowStyle: .hiddenTitleBar)
    #expect(fake.titleBarStyles == [.hidden])
    #expect(fake.titleBarStylePresentsBefore == [0], "applied before the first frame")
    #expect(fake.fakeSurface.presentCalls >= 1, "control: the first frame was drawn")
    #expect(window.windowStyle == .hiddenTitleBar)
}
