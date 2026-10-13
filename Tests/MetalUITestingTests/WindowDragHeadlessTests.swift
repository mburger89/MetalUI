import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Window drag (item C22, rulings `WD-E`, `WD-D`; spec
// `docs/superpowers/specs/2026-10-12-window-drag-design.md` §5, tests 2.1 and
// 2.2): the headless window records what `Window` asks of the platform.

/// A 300 × 300 window: a 32-point handle over a full-window viewport.
@MainActor private func dragTree() -> some Element {
    ZStack(alignment: .top) {
        Rectangle().frame(width: Pixels(300), height: Pixels(300))
        Rectangle().frame(width: Pixels(300), height: Pixels(32)).gesture(WindowDragGesture())
    }
}

private func at(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

/// **2.1** (`WD-E`). The headless window counts `performWindowDrag()` calls and
/// answers `Options.performsWindowDrag` (default `true`, AppKit's answer during
/// a drag). Mutation: answer a constant `true`, or drop the count.
@Test @MainActor func aHeadlessWindowRecordsWindowDragsAndAnswersItsOption() throws {
    let yes = try harnessWindow(size: Size(width: Pixels(300), height: Pixels(300))) { dragTree() }
    #expect(yes.platformWindow.windowDrags == 0)
    #expect(yes.platformWindow.performWindowDrag() == true, "the default answers like AppKit")
    #expect(yes.platformWindow.windowDrags == 1)

    let no = try harnessWindow(size: Size(width: Pixels(300), height: Pixels(300)),
                               options: .init(performsWindowDrag: false)) { dragTree() }
    #expect(no.platformWindow.performWindowDrag() == false, "SDL's answer")
    #expect(no.platformWindow.windowDrags == 1, "and it still records")
}

/// **2.2** (`WD-E`). `TestWindow.windowDrags` reads the platform window's count
/// after a real press-drag on the handle through the real `Window`.
/// Mutation: the read-through answers 0.
@Test @MainActor func aTestWindowExposesWindowDrags() throws {
    let window = try harnessWindow(size: Size(width: Pixels(300), height: Pixels(300))) { dragTree() }
    #expect(window.windowDrags == 0)
    window.drag(from: at(100, 16), to: at(140, 16))
    window.tick()
    #expect(window.windowDrags == 1, "one press-drag on the handle asks once")
    #expect(window.windowDrags == window.platformWindow.windowDrags)
}
