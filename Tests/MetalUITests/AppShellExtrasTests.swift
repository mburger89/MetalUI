import Testing
import Foundation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// App-shell extras (ruling family `AE-`; probe `docs/probes/swiftui-app-shell.swift` arms `N6`…`N13`,
// `D2`…`D6`; decisions `docs/superpowers/2026-11-01-app-shell-extras-decisions.md`). `navigationTitle` over
// a `Text`/`LocalizedStringKey`, `navigationSubtitle` (pre-order precedence, unlike the title) and
// `windowDismissBehavior`, headless over `FakePlatform`.

private func px(_ v: Float) -> Pixels { Pixels(v) }

@Observable @MainActor private final class ExtrasModel {
    var mode = 0
    var subtitle = "s"
}

@MainActor private func box() -> some Element { Box().frame(width: px(10), height: px(10)) }

/// **AE-1** (`AE-A`, `N6`, `N7`). A `Text` title is its plain string, styles dropped; a literal is a
/// `LocalizedStringKey` whose Markdown is parsed and shown as plain text; a `String` value is shown as written.
/// Mutations: `Text.string` swapped for the key's raw format (the literal arm reads `**`), the `Text` overload
/// forwarding `"Text"`.
@MainActor
@Test func aTextOrKeyTitleIsItsPlainString() throws {
    let (app, platform) = try shellApp()
    let model = ExtrasModel()
    let window = try app.openWindow(title: "W", size: Size(width: px(64), height: px(64)), startsDisplayLink: false) {
        Column {
            if model.mode == 0 { box().navigationTitle(Text("Plain **bold** `code`").bold().foregroundColor(.red)) }
            if model.mode == 1 { box().navigationTitle("Lit **bold** `code`") }
            if model.mode == 2 { let s = "As **written**"; box().navigationTitle(s) }
        }
    }
    let fake = try #require(platform.openedWindows.last)
    #expect(fake.title == "Plain bold code", "a Text: its string, styles dropped (N6)")
    model.mode = 1
    window.drawFrameIfNeeded()
    #expect(fake.title == "Lit bold code", "a literal is a key: Markdown parsed, shown plain (N7)")
    model.mode = 2
    window.drawFrameIfNeeded()
    #expect(fake.title == "As **written**", "a String value is never parsed")
}

/// **AE-2** (`AE-B`, `N8`, `N9`, `N12`, `N13`). The subtitle reaches the platform on change only; an enclosing
/// subtitle beats an inner one and the first sibling beats the second (pre-order); it clears when the content
/// leaves; a `Text` is its plain string. Mutations: post-order (nesting arm red), last report wins (siblings
/// red), send on every build (count red), the `Text` overload forwarding the raw format.
@MainActor
@Test func theSubtitleIsPreOrderAndSentOnChangeOnly() throws {
    let (app, platform) = try shellApp()
    let model = ExtrasModel()
    let window = try app.openWindow(title: "W", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        Column {
            if model.mode == 0 {
                Column { box().navigationSubtitle("inner") }.navigationSubtitle("outer")
            }
            if model.mode == 1 {
                box().navigationSubtitle("first")
                box().navigationSubtitle("second")
            }
            if model.mode == 2 { box().navigationSubtitle(model.subtitle) }
            if model.mode == 3 { box().navigationSubtitle(Text("T **b**")) }
        }
    }
    let fake = try #require(platform.openedWindows.last)
    #expect(fake.subtitleCalls == ["outer"], "an enclosing subtitle beats an inner one (N13): \(fake.subtitleCalls)")
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(fake.subtitleCalls == ["outer"], "unchanged: not re-sent")
    model.mode = 1
    window.drawFrameIfNeeded()
    #expect(fake.subtitleCalls.last == "first", "the first sibling wins (N12)")
    model.mode = 2
    window.drawFrameIfNeeded()
    #expect(fake.subtitleCalls.last == "s")
    model.subtitle = "t"
    window.drawFrameIfNeeded()
    #expect(fake.subtitleCalls.last == "t", "a changed subtitle is followed")
    model.mode = 3
    window.drawFrameIfNeeded()
    #expect(fake.subtitleCalls.last == "T b", "a Text: plain string (N11)")
    model.mode = 4
    window.drawFrameIfNeeded()
    #expect(fake.subtitleCalls.last == "", "removed: no subtitle")
}

/// **AE-3** (`AE-C`, `AE-D`, `D0`…`D5`). `.disabled` tells the platform once and refuses the user's close
/// (`performClose`, the platform's request) without asking the handler; inner beats outer (`D2`, `D3`), the
/// first sibling beats the second (`D4`); `.enabled`/`.automatic` allow it; leaving reverts. `close()` still
/// closes. Mutations: ignore the platform call; gate in `answerCloseRequest` regardless of `userInitiated`
/// (AE-4 red); outer wins (nesting arms red); last sibling wins.
@MainActor
@Test func dismissDisabledRefusesTheUsersCloseAndFollowsPostOrderPrecedence() throws {
    let (app, platform) = try shellApp()
    let model = ExtrasModel()
    var asked = 0
    let window = try app.openWindow(title: "W", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        Column {
            if model.mode == 0 { box().windowDismissBehavior(.disabled) }
            if model.mode == 1 { Column { box().windowDismissBehavior(.enabled) }.windowDismissBehavior(.disabled) }
            if model.mode == 2 { Column { box().windowDismissBehavior(.disabled) }.windowDismissBehavior(.enabled) }
            if model.mode == 3 {
                box().windowDismissBehavior(.disabled)
                box().windowDismissBehavior(.enabled)
            }
            if model.mode == 4 { box().windowDismissBehavior(.automatic) }
        }
    }
    window.onCloseRequest = { asked += 1; return .now }
    let fake = try #require(platform.openedWindows.last)
    #expect(fake.dismissEnabledCalls == [false], "\(fake.dismissEnabledCalls)")
    window.performClose()
    #expect(!fake.isClosed && asked == 0, "the user's close is refused and the handler not asked")
    #expect(fake.onCloseRequest?() == false, "the platform's request is refused too")

    model.mode = 1
    window.drawFrameIfNeeded()
    #expect(fake.dismissEnabledCalls == [false, true], "inner .enabled beats outer .disabled (D2)")
    model.mode = 2
    window.drawFrameIfNeeded()
    #expect(fake.dismissEnabledCalls == [false, true, false], "inner .disabled beats outer .enabled (D3)")
    model.mode = 3
    window.drawFrameIfNeeded()
    #expect(fake.dismissEnabledCalls.last == false && fake.dismissEnabledCalls.count == 3,
            "the first sibling wins, no new call (D4)")
    model.mode = 4
    window.drawFrameIfNeeded()
    #expect(fake.dismissEnabledCalls.last == true, ".automatic leaves the window closable (D5)")
    window.performClose()
    #expect(fake.isClosed && asked == 1)
}

/// **AE-4** (`AE-D`). A dismissal is not a quit and `close()` is not a dismissal: the termination walk and
/// `Window.close()` close a window whose tree says `.disabled`. Mutation: gate the walk (`userInitiated`
/// ignored) — the quit stays cancelled.
@MainActor
@Test func aDisabledWindowStillClosesForQuitAndForClose() throws {
    let (app, platform) = try shellApp()
    let a = try app.openWindow(title: "A", size: Size(width: px(64), height: px(64)), startsDisplayLink: false) {
        Column { box().windowDismissBehavior(.disabled) }
    }
    let fakeA = try #require(platform.openedWindows.last)
    #expect(platform.simulateTerminateRequest() == .now, "the walk is not refused by a disabled dismiss")
    #expect(fakeA.isClosed)

    let (app2, platform2) = try shellApp()
    let b = try app2.openWindow(title: "B", size: Size(width: px(64), height: px(64)), startsDisplayLink: false) {
        Column { box().windowDismissBehavior(.disabled) }
    }
    let fakeB = try #require(platform2.openedWindows.last)
    b.close()
    #expect(fakeB.isClosed, "close() never asks and is not a dismissal")
    withExtendedLifetime((a, b)) {}
}
