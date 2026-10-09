import Testing
import Foundation
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// App shell, lane 2, tests 2.23–2.26 (ruling `AS-G`; probe
// `docs/probes/swiftui-app-shell.swift` `O0`–`O5`; divergence 176; spec
// §4.2). `.onOpenURL` handlers present in a window's last build; `App` routes
// each URL to one window — the key window with a handler, else the first open
// window with one — and runs every handler there once, in reverse post-order,
// each under `StateDispatch` for its owner; no window → `App.onOpenURL`;
// none → dropped. URLs come from `Platform.onOpenURLs` (the fake's
// `simulateOpenURLs`) or `App.open(_:)`.

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// One `@State` counter its own box's `.onOpenURL` increments.
private struct URLCounter: Component {
    @State var n = 0
    var content: some ElementGroup {
        Box().frame(width: px(10), height: px(10)).onOpenURL { _ in n += 1 }
    }
}

/// **2.23** (`AS-G` items 2–3). Every handler in the window runs once in
/// reverse post-order — later sibling first, outer before inner — and a
/// `@State` write in a handler lands in its own occurrence (`StateDispatch`;
/// one `URLCounter` value placed twice). Mutations: pre-order; no dispatch
/// (both writes reach the last-bound occurrence).
@MainActor
@Test func everyOnOpenURLInTheTargetWindowRunsInReversePostOrder() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let window = try app.openWindow(title: "W", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        let counter = URLCounter()
        return Column {
            Column {
                Box().frame(width: px(4), height: px(4)).onOpenURL { log.entries.append("inner1 \($0.lastPathComponent)") }
                Box().frame(width: px(4), height: px(4)).onOpenURL { log.entries.append("inner2 \($0.lastPathComponent)") }
            }
            .onOpenURL { log.entries.append("outer \($0.lastPathComponent)") }
            counter
            counter
        }
    }
    platform.simulateOpenURLs(["file:///tmp/doc.mcgraph"])
    #expect(log.entries == ["outer doc.mcgraph", "inner2 doc.mcgraph", "inner1 doc.mcgraph"], "\(log.entries)")

    // The two counters' handlers ran first (they are last in post-order, the
    // order `openURLHandlerOwners` keeps); each wrote its own occurrence.
    let owners = window.openURLHandlerOwners
    try #require(owners.count == 5)
    let components = try owners.suffix(2).map { try #require($0.parent) }
    try #require(components[0] != components[1], "control: two occurrences")
    let counts = components.map {
        window.stateTable.peek(.child(of: $0, at: 0, name: ElementID("$state0")), as: Int.self) ?? 0
    }
    #expect(counts.sorted() == [1, 1], "each handler wrote its own occurrence; last-bound reads [0, 2]: \(counts)")
}

/// A window whose root holds a box with an `.onOpenURL` logging `"<name>"`.
@MainActor private func urlWindow(_ app: App, _ platform: FakePlatform, _ name: String,
                                  _ log: ShellLog) throws -> (Window, FakePlatformWindow) {
    let window = try app.openWindow(title: name, size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        Column { Box().frame(width: px(4), height: px(4)).onOpenURL { _ in log.entries.append(name) } }
    }
    return (window, try #require(platform.openedWindows.last))
}

/// **2.24** (`AS-G` item 2). The key window with a handler first; else the
/// first open window with one; a key window with no handler is skipped; with
/// no handler anywhere, `App.onOpenURL`. Mutation: ignore key state.
@MainActor
@Test func anOpenGoesToTheKeyWindowThenTheFirstWithAHandlerThenTheApp() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    app.onOpenURL = { log.entries.append("app \($0.lastPathComponent)") }
    let (a, fakeA) = try urlWindow(app, platform, "A", log)
    let (b, fakeB) = try urlWindow(app, platform, "B", log)
    fakeA.simulateControlActiveStateChange(to: .inactive)
    fakeB.simulateControlActiveStateChange(to: .key)
    platform.simulateOpenURLs(["file:///tmp/1"])
    #expect(log.entries == ["B"], "the key window: \(log.entries)")

    fakeB.simulateControlActiveStateChange(to: .inactive)
    platform.simulateOpenURLs(["file:///tmp/2"])
    #expect(log.entries == ["B", "A"], "no key window: the first with a handler")

    let (c, fakeC) = try shellWindow(app, platform, "C", log)   // no handler
    fakeC.simulateControlActiveStateChange(to: .key)
    platform.simulateOpenURLs(["file:///tmp/3"])
    #expect(log.entries == ["B", "A", "A"], "a key window without a handler is skipped")

    fakeA.close()
    fakeB.close()
    platform.simulateOpenURLs(["file:///tmp/4", "file:///tmp/5"])
    #expect(log.entries == ["B", "A", "A", "app 4", "app 5"], "no handler in any window: the app's, per URL")
    withExtendedLifetime((a, b, c)) {}
}

/// **2.25** (`AS-G` items 1, 4). A URL nobody handles is dropped (no window
/// handler, no `App.onOpenURL`); `App.open(_:)` delivers exactly as the
/// platform does; an unparsable string is dropped.
@MainActor
@Test func anOpenURLNobodyHandlesIsDroppedAndAppOpenDeliversAsThePlatformDoes() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let (plain, _) = try shellWindow(app, platform, "Plain", log)
    platform.simulateOpenURLs(["file:///tmp/dropped"])
    #expect(log.entries.isEmpty)

    var received: [URL] = []
    let window = try app.openWindow(title: "W", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        Column { Box().frame(width: px(4), height: px(4)).onOpenURL { received.append($0) } }
    }
    platform.simulateOpenURLs(["file:///tmp/a%20b.mcgraph", "", "metalcreator://doc/1"])
    app.open([URL(fileURLWithPath: "/tmp/a b.mcgraph"), URL(string: "metalcreator://doc/1")!])
    #expect(received == [URL(fileURLWithPath: "/tmp/a b.mcgraph"), URL(string: "metalcreator://doc/1")!,
                         URL(fileURLWithPath: "/tmp/a b.mcgraph"), URL(string: "metalcreator://doc/1")!],
            "\(received)")
    withExtendedLifetime((plain, window)) {}
}

@Observable @MainActor private final class ListeningModel {
    var listening = true
}

/// **2.26** (`AS-G` item 2). Presence is the last build: a removed
/// `.onOpenURL` no longer hears URLs (the app's catch-all does). Mutation:
/// keep handlers across builds.
@MainActor
@Test func aRemovedOnOpenURLNoLongerHearsURLs() throws {
    let (app, platform) = try shellApp()
    let log = ShellLog()
    let model = ListeningModel()
    app.onOpenURL = { _ in log.entries.append("app") }
    let window = try app.openWindow(title: "W", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        Column {
            Box().frame(width: px(4), height: px(4))
            if model.listening {
                Box().frame(width: px(4), height: px(4)).onOpenURL { _ in log.entries.append("window") }
            }
        }
    }
    platform.simulateOpenURLs(["file:///tmp/1"])
    #expect(log.entries == ["window"])
    model.listening = false
    window.drawFrameIfNeeded()
    platform.simulateOpenURLs(["file:///tmp/2"])
    #expect(log.entries == ["window", "app"])
}
