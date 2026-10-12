import Testing
import Metal
import Observation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI
@testable import MetalUIText

// `onModifierKeysChanged(mask:initial:_:)` — input follow-ups, lane 3 (ruling
// `IF-D`; spec `docs/superpowers/specs/2026-10-10-input-followups-design.md`
// §3, ids 3.1–3.9). The contract is MetalUI's own: SwiftUI's timing was not
// measured (`IF-D` finding, human check IF1).
//
// **No test sleeps**: `makeFakeWindowOnDefaultDevice` windows driven by
// `drawFrameIfNeeded()`, the fake's `onInput` and
// `simulateControlActiveStateChange(to:)`. Red before, for every test: the file
// does not compile without `onModifierKeysChanged` (recorded in the lane's red
// commit).

@MainActor private final class MKLog {
    var entries: [String] = []
    var builds = 0
}

@Observable @MainActor private final class MKModel {
    var tick = 0
    var shown = true
    var modifiers: EventModifiers = []
    var hoverActive = false
}

private func mk(_ m: EventModifiers) -> String {
    var s = ""
    if m.contains(.control) { s += "c" }
    if m.contains(.option) { s += "o" }
    if m.contains(.shift) { s += "s" }
    if m.contains(.command) { s += "k" }
    return s.isEmpty ? "." : s
}

private func pxl(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private func mkSettle(_ window: Window) {
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// A window over `content`, with no frame drawn yet (so a test can set the
/// held modifiers before the first one).
@MainActor private func mkWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    try makeFakeWindowOnDefaultDevice(size: 200, content: content)
}

@MainActor private func send(_ platform: FakePlatformWindow, _ m: EventModifiers) {
    _ = platform.onInput?(.modifiersChanged(m))
}

/// A 20 × 7 accent tile, widened by 5 per `tick` — a model write's mark.
@MainActor private func mkTile(width: Float) -> some StyledElement {
    Box().frame(width: pxl(width), height: pxl(7)).background(.accent)
}

@MainActor private func mkRectWidth(_ window: Window) -> Float? {
    let matches = window.lastScene.rects.filter { $0.bounds.size.height == 7 }
    return matches.count == 1 ? matches[0].bounds.size.width : nil
}

// MARK: - 3.1

/// **3.1** (`IF-D` items 1, 3). A change runs the action with `(old, new)`
/// after the build, outside every phase: its model write is in the very frame
/// that presents. Mutation: skip the drain / run inside the build.
@MainActor
@Test func aModifierChangeRunsTheActionWithOldAndNewAfterTheBuild() throws {
    let log = MKLog()
    let model = MKModel()
    let (window, platform) = try mkWindow {
        Column {
            mkTile(width: Float(20 + model.tick * 5))
                .onModifierKeysChanged { old, new in
                    log.entries.append("\(mk(old))>\(mk(new))")
                    model.tick += 1
                }
        }
    }
    mkSettle(window)
    #expect(log.entries.isEmpty, "an empty first report is not made: \(log.entries)")
    #expect(mkRectWidth(window) == 20)
    send(platform, [.shift])
    window.drawFrameIfNeeded()
    #expect(log.entries == [".>s"], "\(log.entries)")
    #expect(mkRectWidth(window) == 25, "the action's write is in the presented frame")
    send(platform, [.shift, .command])
    mkSettle(window)
    #expect(log.entries == [".>s", "s>sk"], "\(log.entries)")
}

// MARK: - 3.2

/// **3.2** (`IF-D` item 3). `mask` filters: both values are masked and a change
/// outside the mask runs nothing. Mutation: ignore the mask.
@MainActor
@Test func aMaskFiltersTheChange() throws {
    let log = MKLog()
    let (window, platform) = try mkWindow {
        Column {
            mkTile(width: 20).onModifierKeysChanged(mask: .command) { old, new in
                log.entries.append("\(mk(old))>\(mk(new))")
            }
        }
    }
    mkSettle(window)
    send(platform, [.shift])
    mkSettle(window)
    #expect(log.entries.isEmpty, "shift is outside the mask: \(log.entries)")
    send(platform, [.shift, .command])
    mkSettle(window)
    #expect(log.entries == [".>k"], "both masked: \(log.entries)")
    send(platform, [.command])
    mkSettle(window)
    #expect(log.entries == [".>k"], "shift leaving is outside the mask: \(log.entries)")
    send(platform, [])
    mkSettle(window)
    #expect(log.entries == [".>k", "k>."], "\(log.entries)")
}

// MARK: - 3.3

/// **3.3** (`IF-D` item 3). `initial: true` reports `([], held & mask)` at the
/// first presented frame when that is not empty; `initial: false` stores it
/// silently; nothing held reports nothing. Mutation: invert `initial`.
@MainActor
@Test func initialTrueReportsAtTheFirstFrameAndFalseDoesNot() throws {
    let on = MKLog(), off = MKLog(), none = MKLog()
    let (w1, p1) = try mkWindow {
        Column { mkTile(width: 20).onModifierKeysChanged { o, n in on.entries.append("\(mk(o))>\(mk(n))") } }
    }
    send(p1, [.shift])
    mkSettle(w1)
    #expect(on.entries == [".>s"], "\(on.entries)")

    let (w2, p2) = try mkWindow {
        Column {
            mkTile(width: 20).onModifierKeysChanged(initial: false) { o, n in
                off.entries.append("\(mk(o))>\(mk(n))")
            }
        }
    }
    send(p2, [.shift])
    mkSettle(w2)
    #expect(off.entries.isEmpty, "initial: false stores silently: \(off.entries)")
    send(p2, [.shift, .command])
    mkSettle(w2)
    #expect(off.entries == ["s>sk"], "the stored value is the old one: \(off.entries)")

    let (w3, _) = try mkWindow {
        Column { mkTile(width: 20).onModifierKeysChanged { o, n in none.entries.append("\(mk(o))>\(mk(n))") } }
    }
    mkSettle(w3)
    #expect(none.entries.isEmpty)
    withExtendedLifetime((w1, w2, w3)) {}
}

// MARK: - 3.4

/// **3.4** (`IF-D` item 2). The modifiers come from any event that carries
/// them — SDL sends no flags-changed event, a modifier key's own key event
/// carries the state. Mutation: read `.modifiersChanged` only.
@MainActor
@Test func modifiersCanComeFromAKeyEventAlone() throws {
    let log = MKLog()
    let (window, platform) = try mkWindow {
        Column { mkTile(width: 20).onModifierKeysChanged { o, n in log.entries.append("\(mk(o))>\(mk(n))") } }
    }
    mkSettle(window)
    _ = platform.onInput?(.keyDown(KeyEvent(charactersIgnoringModifiers: "x", characters: "x",
                                            modifiers: [.command], timestamp: 0)))
    mkSettle(window)
    #expect(log.entries == [".>k"], "a key event: \(log.entries)")
    _ = platform.onInput?(.keyUp(KeyEvent(charactersIgnoringModifiers: "x", characters: "x",
                                          modifiers: [], timestamp: 0)))
    mkSettle(window)
    #expect(log.entries == [".>k", "k>."], "a key release: \(log.entries)")
    _ = platform.onInput?(.mouseMoved(MouseEvent(position: Point(x: pxl(150), y: pxl(150)),
                                                 modifiers: [.shift])))
    mkSettle(window)
    #expect(log.entries.last == ".>s", "a pointer event: \(log.entries)")
    _ = platform.onInput?(.scrollWheel(ScrollEvent(position: Point(x: pxl(150), y: pxl(150)),
                                                   delta: Point(x: pxl(0), y: pxl(-1)), modifiers: [])))
    mkSettle(window)
    #expect(log.entries.last == "s>.", "a scroll event: \(log.entries)")
}

// MARK: - 3.5

/// **3.5** (`IF-D` item 4). Leaving key reports the modifiers as released; the
/// platform's `.modifiersChanged` on becoming key reports the held ones.
/// Mutation: remove the reset.
@MainActor
@Test func leavingKeyReportsTheModifiersAsReleasedAndBecomingKeyTheCurrentOnes() throws {
    let log = MKLog()
    let (window, platform) = try mkWindow {
        Column { mkTile(width: 20).onModifierKeysChanged { o, n in log.entries.append("\(mk(o))>\(mk(n))") } }
    }
    mkSettle(window)
    send(platform, [.command])
    mkSettle(window)
    #expect(log.entries == [".>k"])
    platform.simulateControlActiveStateChange(to: .inactive)
    mkSettle(window)
    #expect(log.entries == [".>k", "k>."], "leaving key: \(log.entries)")
    platform.simulateControlActiveStateChange(to: .key)
    send(platform, [.shift])   // what the platform sends on becoming key (`IF-I`)
    mkSettle(window)
    #expect(log.entries == [".>k", "k>.", ".>s"], "becoming key: \(log.entries)")
}

// MARK: - 3.6

/// **3.6** (`IF-D` item 2). A window whose last frame had no scope is not
/// dirtied by a modifier change; one with a scope is. Mutation: always dirty.
@MainActor
@Test func aWindowWithNoScopeIsNotDirtiedByAModifierChange() throws {
    let plainBuilds = MKLog(), scopedBuilds = MKLog()
    let (plain, plainPlatform) = try mkWindow {
        plainBuilds.builds += 1
        return Column { mkTile(width: 20) }
    }
    let (scoped, scopedPlatform) = try mkWindow {
        scopedBuilds.builds += 1
        return Column { mkTile(width: 20).onModifierKeysChanged { _, _ in } }
    }
    mkSettle(plain)
    mkSettle(scoped)
    let before = plainBuilds.builds
    send(plainPlatform, [.shift])
    #expect(!plain.needsRedraw, "no scope, no dirt")
    mkSettle(plain)
    #expect(plainBuilds.builds == before, "no extra build")
    send(scopedPlatform, [.shift])
    #expect(scoped.needsRedraw, "the separating arm: a scope is dirtied")
    withExtendedLifetime((plain, scoped)) {}
}

// MARK: - 3.7

/// **3.7** (`IF-D` item 1). A removed scope stops reporting and stops dirtying
/// the window; its return reports again. Mutation: leak the store entry.
@MainActor
@Test func aRemovedScopeStopsReporting() throws {
    let log = MKLog()
    let model = MKModel()
    let (window, platform) = try mkWindow {
        Column {
            if model.shown {
                mkTile(width: 20).onModifierKeysChanged { o, n in log.entries.append("\(mk(o))>\(mk(n))") }
            }
        }
    }
    mkSettle(window)
    model.shown = false
    mkSettle(window)
    send(platform, [.shift])
    #expect(!window.needsRedraw, "the last frame had no scope")
    mkSettle(window)
    #expect(log.entries.isEmpty, "\(log.entries)")
    model.shown = true
    mkSettle(window)
    #expect(log.entries == [".>s"], "a return reports its initial value again: \(log.entries)")
}

/// **3.7b** (`IF-D` item 1). Two scopes stacked on one element both report,
/// each with its own entry. Mutation: share a key.
@MainActor
@Test func twoStackedScopesBothReport() throws {
    let log = MKLog()
    let (window, platform) = try mkWindow {
        Column {
            mkTile(width: 20)
                .onModifierKeysChanged { o, n in log.entries.append("a:\(mk(o))>\(mk(n))") }
                .onModifierKeysChanged(mask: .command) { o, n in log.entries.append("b:\(mk(o))>\(mk(n))") }
        }
    }
    mkSettle(window)
    send(platform, [.command])
    mkSettle(window)
    #expect(log.entries.sorted() == ["a:.>k", "b:.>k"], "\(log.entries)")
}

// MARK: - 3.8

/// **3.8** (`IF-D`; composition pin). A still pointer's hover sees a ⌘ press:
/// the action stores the modifiers in the model, the hovered content reads them
/// next frame, the pointer never moved.
@MainActor
@Test func aStillPointerHoverSeesACommandPress() throws {
    let model = MKModel()
    let (window, platform) = try mkWindow {
        Column {
            mkTile(width: model.modifiers.contains(.command) ? 40 : 20)
                .onContinuousHover { phase in
                    if case .active = phase { model.hoverActive = true } else { model.hoverActive = false }
                }
                .onModifierKeysChanged(mask: .command) { _, new in model.modifiers = new }
        }
    }
    mkSettle(window)
    let tile = try #require(window.lastScene.rects.first { $0.bounds.size.height == 7 }?.bounds)
    _ = platform.onInput?(.mouseMoved(MouseEvent(position: Point(x: pxl(tile.origin.x + 5), y: pxl(tile.origin.y + 3)))))
    mkSettle(window)
    #expect(model.hoverActive)
    #expect(mkRectWidth(window) == 20)
    send(platform, [.command])
    mkSettle(window)
    #expect(model.hoverActive, "the pointer is still over it")
    #expect(model.modifiers == [.command])
    #expect(mkRectWidth(window) == 40, "the hover's content saw the press")
}

// MARK: - 3.9

/// **3.9** (`LC-J` item 4's shape). A headless `renderFrame` runs no modifier
/// action: it has no window to hold a modifier, and its store is never drained.
@MainActor
@Test func aHeadlessRenderRunsNoModifierAction() {
    let log = MKLog()
    _ = renderFrame({ Column { mkTile(width: 20).onModifierKeysChanged { _, _ in log.entries.append("ran") } } },
                    size: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1,
                    textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 64, height: 64))
    #expect(log.entries.isEmpty)
}
