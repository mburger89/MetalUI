import Foundation
import MetalUITesting
import MetalUIPlatform
import MetalUITerminal
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// Terminal phase 5.5 (`TRM-BD`): hit testing, the wheel, mouse reports, selection, copy and links, headless on `TermRig`.
// Each test names the mutation it was shown red against (`docs/practices/verifying-tests-can-fail.md`).

private func esc(_ s: String) -> [UInt8] { [0x1B] + Array(s.utf8) }

extension TermRig {
    /// The centre of viewport cell (`row`, `col`) in window points (the terminal fills the window).
    func point(_ row: Int, _ col: Int) -> Point<Pixels> {
        let c = model.cellSize ?? (width: 8, height: 16)
        return Point(x: Pixels(Float((Double(col) + 0.5) * c.width)), y: Pixels(Float((Double(row) + 0.5) * c.height)))
    }

    /// The point `rows` below (or above, negative) the view's last row: past the edge.
    func pointBelowEdge(rows extra: Double, col: Int = 2) -> Point<Pixels> {
        let c = model.cellSize ?? (width: 8, height: 16)
        let grid = model.snapshot?.size.rows ?? 24
        return Point(x: Pixels(Float((Double(col) + 0.5) * c.width)), y: Pixels(Float((Double(grid) + extra) * c.height)))
    }

    /// Output that fills the screen and `extra` rows of scrollback: "row 0", "row 1", ...
    func fill(_ lines: Int) async {
        for i in 0..<lines { feed("row \(i)\r\n") }
        await settle()
    }

    /// One scroll event, `precise` or a wheel mouse's lines, at `point`.
    func wheel(at point: Point<Pixels>, dx: Float = 0, dy: Float, precise: Bool = false, modifiers: Modifiers = [],
               phase: InputPhase = .none) {
        window.send(.scrollWheel(ScrollEvent(position: point, delta: Point(x: Pixels(dx), y: Pixels(dy)), modifiers: modifiers,
                                             phase: phase, momentumPhase: .none, isPrecise: precise, timestamp: 0)))
        window.tick()
    }

    func press(at point: Point<Pixels>, modifiers: Modifiers = [], clickCount: Int = 1) {
        window.send(.mouseDown(MouseEvent(position: point, modifiers: modifiers, clickCount: clickCount, timestamp: nil)))
        window.tick()
    }
    func dragged(to point: Point<Pixels>, modifiers: Modifiers = []) {
        window.send(.mouseDragged(MouseEvent(position: point, modifiers: modifiers, timestamp: nil)))
        window.tick()
    }
    func release(at point: Point<Pixels>, modifiers: Modifiers = []) {
        window.send(.mouseUp(MouseEvent(position: point, modifiers: modifiers, timestamp: nil)))
        window.tick()
    }

    /// The emulator's selection after the queue and its publish landed.
    func selection() async -> TerminalSelection? {
        await settle()
        return model.snapshot?.selection
    }
    func selectedText() async -> String? {
        await settle()
        return emulator.selectedText()
    }

    var viewportOffset: Int { model.snapshot?.viewportOffset ?? -1 }

    func mouseMode(_ tracking: String, encoding: String? = "1006") async {
        await feedModes("\u{1B}[?\(tracking)h" + (encoding.map { "\u{1B}[?\($0)h" } ?? ""))
    }
}

private func sgr(_ code: Int, _ col: Int, _ row: Int, release: Bool = false) -> [UInt8] {
    esc("[<\(code);\(col + 1);\(row + 1)\(release ? "m" : "M")")
}

/// **1** (`TRM-BD` item 1) `hitTest` maps a view-local point to the viewport cell under it, clamped to the grid, and the
/// cell's absolute row follows the snapshot's top row once the viewport is scrolled back.
/// Mutation: floor the row with `rounded()` (the point at a cell's lower half hits the next row).
@MainActor @Test func hitTestMapsPointsToCells() async throws {
    let rig = try TermRig()
    await rig.settle()
    let m = rig.model
    let cell = try #require(m.cellSize)
    func at(_ x: Double, _ y: Double) -> Point<Pixels> { Point(x: Pixels(Float(x)), y: Pixels(Float(y))) }
    #expect(m.hitTest(at(0, 0)) == TerminalPosition(row: 0, col: 0))
    #expect(m.hitTest(at(cell.width * 3 + 1, cell.height * 2 + cell.height - 0.5)) == TerminalPosition(row: 2, col: 3), "the lower half of a cell is still that cell")
    #expect(m.hitTest(at(-20, -20)) == TerminalPosition(row: 0, col: 0))
    let size = try #require(m.snapshot?.size)
    #expect(m.hitTest(at(100000, 100000)) == TerminalPosition(row: size.rows - 1, col: size.cols - 1))
    await rig.fill(60)
    #expect(m.absolute(TerminalPosition(row: 0, col: 4)).row == m.snapshot?.topRow)
    rig.wheel(at: rig.point(2, 2), dy: 10)
    await rig.settle()
    let scrolled = try #require(m.snapshot)
    #expect(scrolled.viewportOffset == 3 && m.absolute(TerminalPosition(row: 5, col: 1)) == TerminalPosition(row: scrolled.topRow + 5, col: 1))
}

/// **2** (`REQUIRED`) The wheel scrolls scrollback: a wheel mouse's line is three rows (positive delta scrolls back), a
/// trackpad's points accumulate into whole rows (the remainder stays), scrolling forward past the live bottom stays at 0,
/// and output while scrolled back keeps the rows in view (`TRM-AR`).
/// Mutation: apply `rowsPerWheelLine` to a precise delta (the trackpad rows triple); drop the accumulator remainder.
@MainActor @Test func theWheelScrollsScrollback() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.fill(80)
    let cell = try #require(rig.model.cellSize)
    #expect(rig.viewportOffset == 0)
    rig.wheel(at: rig.point(3, 3), dy: 10)
    await rig.settle()
    #expect(rig.viewportOffset == 3, "one wheel line is three rows: \(rig.viewportOffset)")
    rig.wheel(at: rig.point(3, 3), dy: 30)
    await rig.settle()
    #expect(rig.viewportOffset == 12)
    // A trackpad: 0.6 of a row twice is one row, the remainder carried; two rows at once are two.
    rig.wheel(at: rig.point(3, 3), dy: Float(cell.height * 0.6), precise: true, phase: .began)
    await rig.settle()
    #expect(rig.viewportOffset == 12, "0.6 of a row moves nothing")
    rig.wheel(at: rig.point(3, 3), dy: Float(cell.height * 0.6), precise: true, phase: .changed)
    await rig.settle()
    #expect(rig.viewportOffset == 13, "the remainder made a row")
    rig.wheel(at: rig.point(3, 3), dy: Float(cell.height * 2), precise: true, phase: .changed)
    await rig.settle()
    #expect(rig.viewportOffset == 15)
    // Output keeps the view where it was.
    let top = try #require(rig.model.snapshot?.topRow)
    for i in 0..<5 { rig.feed("late \(i)\r\n") }
    await rig.settle()
    #expect(rig.model.snapshot?.topRow == top, "the same rows stay in view (offset \(rig.viewportOffset))")
    // Forward to the bottom, and no further.
    rig.wheel(at: rig.point(3, 3), dy: -1000)
    await rig.settle()
    #expect(rig.viewportOffset == 0)
    let draws = rig.window.surfaceDrawCount
    rig.wheel(at: rig.point(3, 3), dy: -10)
    await rig.settle()
    #expect(rig.window.surfaceDrawCount == draws, "a wheel the viewport cannot take draws nothing")
}

/// **3** (`REQUIRED`) With mouse reporting on, the wheel is reported at the pointer's cell through `encodeMouse` (up 64, down
/// 65, left 66, right 67; one report per line), modifiers included, in the program's encoding; the viewport does not move.
/// X10 reports no wheel. ⇧ bypasses reporting and scrolls the viewport.
/// Mutation: scroll the viewport instead of reporting; drop the modifiers; ignore the shift bypass.
@MainActor @Test func theWheelIsReportedToAProgramThatAskedForTheMouse() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.fill(60)
    await rig.mouseMode("1000")
    rig.wheel(at: rig.point(4, 7), dy: 10)
    #expect(rig.sent == [sgr(64, 7, 4)], "\(rig.sent)")
    rig.log.inputs = []
    rig.wheel(at: rig.point(4, 7), dy: -20)
    #expect(rig.sent == [sgr(65, 7, 4) + sgr(65, 7, 4)], "two lines, two reports: \(rig.sent)")
    rig.log.inputs = []
    rig.wheel(at: rig.point(4, 7), dx: 10, dy: 0)
    rig.wheel(at: rig.point(4, 7), dx: -10, dy: 0)
    #expect(rig.sent == [sgr(66, 7, 4), sgr(67, 7, 4)], "\(rig.sent)")
    rig.log.inputs = []
    rig.wheel(at: rig.point(4, 7), dy: 10, modifiers: .control)
    #expect(rig.sent == [sgr(64 + 16, 7, 4)], "control adds 16: \(rig.sent)")
    #expect(rig.viewportOffset == 0, "a reported wheel does not scroll")
    rig.log.inputs = []
    rig.wheel(at: rig.point(4, 7), dy: 10, modifiers: .shift)
    await rig.settle()
    #expect(rig.sent.isEmpty && rig.viewportOffset == 3, "shift scrolls locally: \(rig.sent) \(rig.viewportOffset)")
    await rig.feedModes("\u{1B}[?1000l\u{1B}[?9h")
    rig.wheel(at: rig.point(4, 7), dy: -10)
    #expect(rig.sent.isEmpty, "X10 has no wheel: \(rig.sent)")
}

/// **4** (`REQUIRED`) On the alternate screen without mouse reporting the wheel is the up and down arrow keys (three per
/// wheel line, one per trackpad row), in application cursor mode when set; mouse reporting still wins there. (Terminal.app,
/// VTE and Alacritty do this; xterm's 1007 defaults off, the spec says the wheel goes to the program.)
/// Mutation: scroll the viewport on the alternate screen (nothing is sent); ignore DECCKM.
@MainActor @Test func theWheelOnTheAlternateScreenIsArrowKeys() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.feedModes("\u{1B}[?1049h")
    rig.wheel(at: rig.point(2, 2), dy: 10)
    #expect(rig.sentBytes == esc("[A") + esc("[A") + esc("[A"), "\(rig.sent)")
    rig.log.inputs = []
    rig.wheel(at: rig.point(2, 2), dy: -10)
    #expect(rig.sentBytes == esc("[B") + esc("[B") + esc("[B"))
    rig.log.inputs = []
    let cell = try #require(rig.model.cellSize)
    rig.wheel(at: rig.point(2, 2), dy: Float(cell.height * 2), precise: true)
    #expect(rig.sentBytes == esc("[A") + esc("[A"), "a trackpad row is one arrow: \(rig.sent)")
    await rig.feedModes("\u{1B}[?1h")
    rig.wheel(at: rig.point(2, 2), dy: 10)
    #expect(rig.sentBytes == esc("OA") + esc("OA") + esc("OA"), "application cursor keys: \(rig.sent)")
    await rig.mouseMode("1000")
    rig.wheel(at: rig.point(2, 2), dy: 10)
    #expect(rig.sent == [sgr(64, 2, 2)], "reporting wins over arrows: \(rig.sent)")
}

/// **5** (`REQUIRED`) Presses, drags and releases are reported per tracking mode with modifiers, at the pointer's cell
/// (1-based on the wire), in SGR and in the legacy encoding: X10 reports presses only (no modifiers); normal adds
/// releases; button-event adds drags (one report per cell entered); any-event adds plain motion (code 35).
/// Mutation: report every drag event (cell dedupe); send releases in X10; drop the modifier bits.
@MainActor @Test func mouseReportsFollowTheTrackingMode() async throws {
    let rig = try TermRig()
    await rig.settle()
    let a = rig.point(3, 5), b = rig.point(3, 9)
    // X10: the press only.
    await rig.mouseMode("9")
    rig.press(at: a); rig.dragged(to: b); rig.release(at: b)
    #expect(rig.sent == [sgr(0, 5, 3)], "x10: \(rig.sent)")
    // Normal: press and release; no drags; ctrl adds 16, option 8.
    await rig.feedModes("\u{1B}[?9l"); await rig.mouseMode("1000")
    rig.press(at: a, modifiers: [.control, .option]); rig.dragged(to: b); rig.release(at: b, modifiers: [.control, .option])
    #expect(rig.sent == [sgr(24, 5, 3), sgr(24, 9, 3, release: true)], "normal: \(rig.sent)")
    // Button-event: drags report once per cell.
    await rig.feedModes("\u{1B}[?1000l"); await rig.mouseMode("1002")
    rig.press(at: a); rig.dragged(to: rig.point(3, 6)); rig.dragged(to: rig.point(3, 6)); rig.dragged(to: b); rig.release(at: b)
    #expect(rig.sent == [sgr(0, 5, 3), sgr(32, 6, 3), sgr(32, 9, 3), sgr(0, 9, 3, release: true)], "button: \(rig.sent)")
    rig.log.inputs = []
    rig.window.hover(at: rig.point(6, 6))
    #expect(rig.sent.isEmpty, "no motion without a button in 1002")
    // Any-event: plain motion, once per cell.
    await rig.feedModes("\u{1B}[?1002l"); await rig.mouseMode("1003")
    rig.window.hover(at: rig.point(6, 6)); rig.window.hover(at: rig.point(6, 6)); rig.window.hover(at: rig.point(6, 7))
    #expect(rig.sent == [sgr(35, 6, 6), sgr(35, 7, 6)], "any: \(rig.sent)")
    // The legacy encoding.
    await rig.feedModes("\u{1B}[?1003l\u{1B}[?1006l"); await rig.mouseMode("1000", encoding: nil)
    rig.press(at: a); rig.release(at: a)
    let legacyPress: [UInt8] = [0x1B, 0x5B, 0x4D, 32, 38, 36], legacyRelease: [UInt8] = [0x1B, 0x5B, 0x4D, 35, 38, 36]
    #expect(rig.sent == [legacyPress, legacyRelease], "legacy: \(rig.sent)")
    // The middle and secondary buttons.
    await rig.feedModes("\u{1B}[?1000l"); await rig.mouseMode("1000")
    rig.window.send(.otherMouseDown(MouseEvent(position: a, buttonNumber: 2))); rig.window.tick()
    rig.window.send(.otherMouseUp(MouseEvent(position: a, buttonNumber: 2))); rig.window.tick()
    #expect(rig.sent == [sgr(1, 5, 3), sgr(1, 5, 3, release: true)], "middle: \(rig.sent)")
}

/// **6** ⇧ held at the press bypasses reporting: a drag selects locally and nothing is sent, while a drag begun without ⇧
/// goes on reporting after ⇧ is pressed (the press decided).
/// Mutation: ignore the shift test.
@MainActor @Test func shiftBypassesMouseReporting() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("hello world\r\n")
    await rig.mouseMode("1002")
    rig.window.drag(from: rig.point(0, 0), to: rig.point(0, 4), modifierFlags: .shift)
    #expect(rig.sent.isEmpty, "\(rig.sent)")
    #expect(await rig.selectedText() == "hello")
    rig.log.inputs = []
    rig.press(at: rig.point(1, 0)); rig.dragged(to: rig.point(1, 3), modifiers: .shift); rig.release(at: rig.point(1, 3), modifiers: .shift)
    #expect(rig.sent == [sgr(0, 0, 1), sgr(32 + 4, 3, 1), sgr(0 + 4, 3, 1, release: true)], "\(rig.sent)")
}
