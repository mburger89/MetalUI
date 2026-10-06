import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Platform services, lane 3 — the in-window menu scrolls (ruling `SV-Q`,
// amending `MN-F` items 1–3; spec §6.3 tests 5.12–5.16). MetalUI's own: the
// native menu (AppKit) scrolls itself, and SDL's drawn panel had no answer for
// a level taller than the window (a 300-option key chooser, the configurator's
// common case). Red before: `MenuSession.Level` has no scroll offset at
// `be806c5`, so every test here fails by not compiling.
//
// A 400 × 400 window that draws its menus; a context menu over the whole
// window with `count` rows, opened at the top-left by a secondary press.

@MainActor private final class SLog { var chosen: [Int] = [] }

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func key(_ c: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: [], timestamp: 0))
}
private let downArrow = "\u{f701}"
private func wheel(_ x: Float, _ y: Float, dy: Float) -> InputEvent {
    .scrollWheel(ScrollEvent(position: pt(x, y), delta: pt(0, dy)))
}

/// The window, with the menu of `count` rows open at (10, 10).
@MainActor private func scrollMenu(_ count: Int, _ log: SLog) throws -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 400) {
        Column {
            Box().frame(width: px(400), height: px(400)).background(.surface).contextMenu {
                for index in 0..<count { Button("Row \(index)") { log.chosen.append(index) } }
            }
        }
    }
    platform.presentsMenusNatively = false
    window.drawFrameIfNeeded()
    platform.simulateInput(.rightMouseDown(MouseEvent(position: pt(10, 10))))
    platform.simulateInput(.rightMouseUp(MouseEvent(position: pt(10, 10))))
    try #require(window.menuSession?.isNative == false, "an in-window menu is open")
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    return (window, platform)
}

@MainActor private func level(_ window: Window, sourceLocation: SourceLocation = #_sourceLocation) throws
    -> MenuSession.Level {
    try #require(window.menuSession?.levels.first, sourceLocation: sourceLocation)
}

/// Whether row `index` lies wholly inside the level's visible band.
private func isInBand(_ level: MenuSession.Level, _ index: Int) -> Bool {
    let row = level.rowFrame(index), band = level.visibleBand
    return row.origin.y.value >= band.origin.y.value
        && row.origin.y.value + row.size.height.value <= band.origin.y.value + band.size.height.value
}

/// **5.12** (`SV-Q`). A 300-row level is clamped to the window less its two
/// 4-pt margins (`400 − 8 = 392`), starts unscrolled, and a wheel over it
/// scrolls it (`delta.y = −100` → offset 100, `ScrollView`'s sign); only the
/// rows meeting the visible band are painted — at most the band's 392 / 22
/// rows plus one, counted, never 300. Mutation: paint every row.
@MainActor
@Test func aTallInWindowMenuIsClampedToTheWindowAndScrolls() throws {
    let log = SLog()
    let (window, platform) = try scrollMenu(300, log)
    let open = try level(window)
    #expect(open.frame.size.height.value == 392, "clamped: \(open.frame)")
    #expect(open.frame.origin.y.value == 4, "inside the top margin")
    #expect(open.scrollOffset == 0)
    let limit = Int((392 / MenuPanel.rowHeight).rounded(.up)) + 1
    #expect(window.lastMenuRowsPainted <= limit, "rows painted \(window.lastMenuRowsPainted) ≤ \(limit)")
    #expect(window.lastMenuRowsPainted > 0)
    platform.simulateInput(wheel(50, 100, dy: -100))
    #expect(try level(window).scrollOffset == 100, "the wheel scrolls the level")
    platform.simulateInput(wheel(50, 100, dy: 1_000_000))
    #expect(try level(window).scrollOffset == 0, "clamped at the top")
    platform.simulateInput(wheel(50, 100, dy: -1_000_000))
    let bottom = try level(window)
    #expect(bottom.scrollOffset == bottom.layout.size.height.value - bottom.frame.size.height.value,
            "clamped at the bottom: \(bottom.scrollOffset)")
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.lastMenuRowsPainted <= limit, "scrolled: rows painted \(window.lastMenuRowsPainted)")
    withExtendedLifetime(window) {}
}

/// **5.13** (`SV-Q`). Moving the highlight by ↓ past the band scrolls it into
/// view: after 41 presses row 40 is highlighted and wholly visible. Mutation:
/// move the highlight only.
@MainActor
@Test func arrowKeysScrollTheHighlightIntoView() throws {
    let log = SLog()
    let (window, platform) = try scrollMenu(300, log)
    for _ in 0...40 { platform.simulateInput(key(downArrow)) }
    let open = try level(window)
    try #require(open.highlighted == 40, "row 40 highlighted: \(String(describing: open.highlighted))")
    #expect(isInBand(open, 40), "row 40 is in view: offset \(open.scrollOffset)")
    #expect(open.scrollOffset > 0)
    withExtendedLifetime(window) {}
}

/// **5.14** (`SV-Q`, `SV-P` item 4). A menu picker's in-window menu opens
/// with the selected row highlighted and in view. Mutation: open at row 0.
@MainActor
@Test func aPickersMenuOpensWithTheSelectionHighlightedAndVisible() throws {
    let log = SLog()
    log.chosen = [150]
    let binding = Binding(get: { log.chosen[0] }, set: { log.chosen[0] = $0 })
    let (window, platform) = try controlWindow {
        controlRoot(width: 400, height: 400) {
            Picker("Key", selection: binding) {
                for index in 0..<300 { Text("Key \(index)").tag(index) }
            }
            .pickerStyle(.menu)
        }
    }
    platform.presentsMenusNatively = false
    controlRedraw(window)
    let button = try #require(window.lastElementBounds[controlID([0, 0, 1])])
    controlClick(platform, at: controlCentre(button))
    let open = try level(window)
    #expect(open.highlighted == 150, "the selection highlighted: \(String(describing: open.highlighted))")
    #expect(isInBand(open, 150), "and in view: offset \(open.scrollOffset)")
    withExtendedLifetime(window) {}
}

/// **5.15** (`SV-Q`). Hit testing follows the offset: after a wheel scroll a
/// click chooses the row drawn under the pointer — the row index derived from
/// the panel origin, its 4-pt top padding, 22-pt rows and the offset. Mutation:
/// ignore the offset in the hit test.
@MainActor
@Test func hitTestingFollowsTheScrollOffset() throws {
    let log = SLog()
    let (window, platform) = try scrollMenu(300, log)
    platform.simulateInput(wheel(50, 100, dy: -220))
    let open = try level(window)
    try #require(open.scrollOffset == 220)
    let y: Float = 200
    let expected = Int((y - open.frame.origin.y.value - MenuPanel.verticalPadding + 220) / MenuPanel.rowHeight)
    platform.simulateInput(.mouseMoved(MouseEvent(position: pt(50, y))))
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(50, y))))
    platform.simulateInput(.mouseUp(MouseEvent(position: pt(50, y))))
    #expect(log.chosen == [expected], "\(log.chosen) vs \(expected)")
    withExtendedLifetime(window) {}
}

/// **5.16** (`SV-Q`). A menu that fits does not scroll: its frame is its
/// layout's height, its band its whole frame, its offset 0, and a wheel over
/// it changes nothing. Mutation: always reserve the indicator band.
@MainActor
@Test func aShortMenuDoesNotScroll() throws {
    let log = SLog()
    let (window, platform) = try scrollMenu(5, log)
    let open = try level(window)
    #expect(open.frame.size == open.layout.size)
    #expect(open.visibleBand == open.frame, "no indicator band")
    #expect(!open.isScrollable)
    platform.simulateInput(wheel(50, 30, dy: -50))
    #expect(try level(window).scrollOffset == 0)
    withExtendedLifetime(window) {}
}
