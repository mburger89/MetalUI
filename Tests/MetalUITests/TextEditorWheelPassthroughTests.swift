import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// A `TextEditor` takes the vertical wheel only while it has room in the wheel's direction (`XS-V`, record 430), as a
// one-axis scroller does (`XS-F`, probes `N6b`, `N8`, `N8b`); otherwise the wheel, and a trackpad scroll latched on the
// editor, go on to the `ScrollView` around it. Geometry (200-point window): an outer scroller over a 100 box, the
// editor 200 x 80 at y 100..180, a 600 box. The pointer is at (100, 120), on the editor while the outer has moved
// less than 20.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private let onEditor = pt(100, 120)

private func wheel(dy: Float, timestamp: Double = 1) -> InputEvent {
    .scrollWheel(ScrollEvent(position: onEditor, delta: pt(0, dy), phase: .none, momentumPhase: .none,
                             isPrecise: true, timestamp: timestamp))
}

private func phased(_ phase: InputPhase, _ momentum: InputPhase = .none, dy: Float = 0) -> InputEvent {
    .scrollWheel(ScrollEvent(position: onEditor, delta: pt(0, dy), phase: phase, momentumPhase: momentum,
                             isPrecise: true, timestamp: 1))
}

@MainActor
private final class Notes {
    var text: String
    init(lines: Int) { text = (1...lines).map { "line \($0)" }.joined(separator: "\n") }
}

@MainActor
private func windowFor(lines: Int, _ notes: Notes? = nil) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let notes = notes ?? Notes(lines: lines)
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        ScrollView(.vertical) {
            Column {
                Box().frame(width: px(200), height: px(100))
                TextEditor(text: notes.text) { notes.text = $0 }.frame(width: px(200), height: px(80))
                Box().frame(width: px(200), height: px(600))
            }
        }
    }
    settle(window)
    return (window, platform)
}

@MainActor
private func settle(_ window: Window) {
    window.setNeedsRedraw()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// (outer scroller offset, editor's own scroll).
@MainActor
private func offsets(_ window: Window) throws -> (outer: Double, editor: Double) {
    let region = try #require(window.lastScrollRegions.first)
    let editor = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    return (window.stateTable.peek(region.id, as: ScrollState.self)?.offset ?? 0, window.editState(editor.id).scrollY)
}

/// **W1** (`XS-V`). A phaseless wheel over an editor whose lines fit moves the `ScrollView` around it, and the editor
/// stays at 0. Mutation: restore the unconditional editor claim (drop the room test in `dispatchScrollChain`'s
/// multi-line arm): the editor takes the wheel and the outer stays 0.
@Test @MainActor func aWheelOverAnEditorThatFitsMovesTheScrollViewAroundIt() throws {
    let (window, platform) = try windowFor(lines: 2)
    platform.simulateInput(wheel(dy: -10))
    settle(window)
    let o = try offsets(window)
    #expect(o.outer == 10 && o.editor == 0, "\(o)")
}

/// **W2** (`XS-V`, `IF-G`). A trackpad scroll that begins over an editor that fits goes to the outer scroller for its
/// whole life: the finger stage and the momentum. Mutation: as W1.
@Test @MainActor func aTrackpadScrollOverAnEditorThatFitsMovesTheScrollViewAroundIt() throws {
    let (window, platform) = try windowFor(lines: 2)
    for event in [phased(.began, dy: -4), phased(.changed, dy: -4), phased(.ended, dy: -2),
                  phased(.none, .began, dy: -2), phased(.none, .changed, dy: -2), phased(.none, .ended)] {
        platform.simulateInput(event)
        settle(window)
    }
    let o = try offsets(window)
    #expect(o.outer == 14 && o.editor == 0, "\(o)")
}

/// **W3** (`XS-V`, `TI-H`). An editor with lines past its height keeps the wheel while it has room in the wheel's
/// direction: the editor moves, the outer stays 0. Once at its end a further wheel reaches the outer; scrolling back
/// up the editor takes it again, and at the top an upward wheel goes to the outer too.
@Test @MainActor func anEditorWithRoomKeepsTheWheelAndPassesItOnAtItsEdges() throws {
    let (window, platform) = try windowFor(lines: 60)
    let editor = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    let maxY = try #require(editor.handlers.textInput).maxScrollY
    #expect(maxY > 0)
    platform.simulateInput(wheel(dy: -10))
    settle(window)
    var o = try offsets(window)
    #expect(o.outer == 0 && o.editor == 10, "room: the editor takes it \(o)")
    platform.simulateInput(wheel(dy: -Float(maxY) * 2))       // past the end: the editor clamps at its end
    settle(window)
    o = try offsets(window)
    #expect(o.outer == 0 && o.editor == maxY, "to the end \(o)")
    platform.simulateInput(wheel(dy: -10))
    settle(window)
    o = try offsets(window)
    #expect(o.outer == 10 && o.editor == maxY, "at the end the outer takes it \(o)")
    platform.simulateInput(wheel(dy: 5))
    settle(window)
    o = try offsets(window)
    #expect(o.outer == 10 && o.editor == maxY - 5, "scrolling back, the editor takes it \(o)")
}

/// **W4** (`XS-V`, `XS-F`, probe `N8b`). At its top an upward wheel over an editor with overflow goes to the outer.
@Test @MainActor func anEditorAtItsTopPassesAnUpwardWheelToTheOuterScroller() throws {
    let (window, platform) = try windowFor(lines: 60)
    platform.simulateInput(wheel(dy: -15))   // outer down: the editor has room below, so it takes it
    settle(window)
    platform.simulateInput(wheel(dy: 10))    // up: the editor at 10 takes it back to 5
    settle(window)
    platform.simulateInput(wheel(dy: 5))
    settle(window)
    var o = try offsets(window)
    #expect(o.outer == 0 && o.editor == 0, "\(o)")
    platform.simulateInput(wheel(dy: 5))     // at the top, the outer is at 0 too: nothing moves, nothing breaks
    settle(window)
    o = try offsets(window)
    #expect(o.outer == 0 && o.editor == 0, "\(o)")
}

/// **W5** (`XS-V`, `IF-G`, probe `N8b`). A trackpad scroll that began on an editor with room stays on it until the
/// editor's end, then, as a nested scroller does mid-gesture, gives the outer the rest.
@Test @MainActor func aTrackpadScrollThatReachesTheEditorsEndGivesTheOuterTheRest() throws {
    let (window, platform) = try windowFor(lines: 60)
    let editor = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    let maxY = Float(try #require(editor.handlers.textInput).maxScrollY)
    platform.simulateInput(phased(.began, dy: -(maxY - 4)))
    settle(window)
    var o = try offsets(window)
    #expect(o.outer == 0 && o.editor == Double(maxY - 4), "\(o)")
    platform.simulateInput(phased(.changed, dy: -4))
    settle(window)
    platform.simulateInput(phased(.changed, dy: -6))
    settle(window)
    platform.simulateInput(phased(.ended))
    settle(window)
    o = try offsets(window)
    #expect(o.outer == 6 && o.editor == Double(maxY), "\(o)")
}
