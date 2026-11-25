import Foundation
import MetalUITesting
import MetalUIPlatform
import MetalUITerminal
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// Terminal click-to-focus and the default cursor style (`TRM-BE`, `TRM-BF`, record 369), headless on `TermRig`.
// Each test names the mutation it was shown red against (`docs/practices/verifying-tests-can-fail.md`).

@MainActor private func unfocused(_ rig: TermRig) async {
    await rig.settle()
    rig.window.window.focus(nil)
    await rig.settle()
}

@MainActor private func terminalIsFocused(_ rig: TermRig) -> Bool {
    let order = rig.window.window.testingTabOrder
    return order.count == 1 && rig.window.window.focusedElement == order[0]
}

/// **1** (`TRM-BE`) A plain primary press on an unfocused terminal focuses it.
/// Mutation: drop the press focus (the pointer handler's focus call, or the surface's `.focusable()`).
@MainActor @Test func aPlainPressFocusesTheTerminal() async throws {
    let rig = try TermRig()
    await unfocused(rig)
    #expect(!terminalIsFocused(rig))
    rig.press(at: rig.point(3, 3))
    #expect(terminalIsFocused(rig), "focused: \(String(describing: rig.window.window.focusedElement))")
    rig.release(at: rig.point(3, 3))
}

/// **2** A press the program's mouse reporting takes still focuses, and is still reported.
@MainActor @Test func aReportedPressFocusesTheTerminal() async throws {
    let rig = try TermRig()
    await rig.mouseMode("1000")
    await unfocused(rig)
    rig.log.inputs.removeAll()
    rig.press(at: rig.point(3, 3))
    #expect(terminalIsFocused(rig))
    #expect(!rig.log.inputs.isEmpty, "the press was reported: \(rig.log.inputs)")
    rig.release(at: rig.point(3, 3))
}

/// **3** A ⌘-press on a link focuses and activates it.
@MainActor @Test func aCommandPressOnALinkFocusesTheTerminal() async throws {
    let rig = try TermRig()
    rig.knobs.link = { q in
        q.phase == .exit ? nil : TerminalLinkTarget(columns: 4..<19, payload: "http://a.test/x")
    }
    await rig.settle()
    rig.feed("see http://a.test/x here\r\n")
    await unfocused(rig)
    rig.window.hover(at: rig.point(0, 8))
    rig.window.pressModifiers(Modifiers.primary)
    await rig.settle()
    rig.log.links = []
    rig.window.click(at: rig.point(0, 8), modifierFlags: Modifiers.primary)
    #expect(rig.log.links.last?.phase == .activate, "activated: \(rig.log.links)")
    #expect(terminalIsFocused(rig))
}

/// **4** A press elsewhere in the window moves no focus to the terminal.
@MainActor @Test func aPressElsewhereDoesNotFocusTheTerminal() async throws {
    let rig = try TermRig(extra: true)
    await unfocused(rig)
    rig.press(at: Point(x: Pixels(300), y: Pixels(10)))   // beside the 100-wide editor, above the terminal
    #expect(!terminalIsFocused(rig))
}

/// **5** (`TRM-BE`) A container's `.focused` binding (`FW-`) sees a press on the terminal, and a press elsewhere
/// does not set it. Mutation: no focus request in the press (the container never reads true).
@MainActor private final class PaneProbe { var reads: [Bool] = [] }

@MainActor private struct PressPane: Component {
    @FocusState var focused: Bool
    let probe: PaneProbe
    let source: TerminalSnapshotSource
    var content: some ElementGroup {
        let _ = probe.reads.append(focused)
        VStack(spacing: 0) {
            TerminalView(snapshotSource: source, theme: .xterm, onInput: { _ in }, onResize: { _ in }, onLink: { _ in nil })
        }.focused($focused)
    }
}

@MainActor @Test func aPressOnTheTerminalSetsAContainersFocusBinding() async throws {
    let probe = PaneProbe()
    let emulator = TerminalEmulator(cols: 80, rows: 24)
    let source = TerminalSnapshotSource(emulator: emulator, queue: .main)
    let w = try TestWindow(size: Size(width: Pixels(400), height: Pixels(300)), textSystem: { portableSystem() }) {
        VStack(spacing: 0) { PressPane(probe: probe, source: source) }
    }
    defer { withExtendedLifetime(w) {} }
    w.runsSurfaceDraws = true
    func settle() async throws { for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick(); w.advance(by: 0.05) }; try await w.runUntilIdle() }
    try await settle()
    w.window.focus(nil); try await settle()
    #expect(probe.reads.last == false)
    w.send(.mouseDown(MouseEvent(position: Point(x: Pixels(20), y: Pixels(20)), clickCount: 1, timestamp: nil)))
    try await settle()
    #expect(probe.reads.last == true, "the container read \(probe.reads.suffix(3))")
}

/// **6** A press frame costs what a press on any focusable costs: the terminal's builds and element requests equal a plain
/// `.focusable()` box's (the focus change rebuilds the one component; nothing more). Mutation: the press also asks for a
/// redraw or a second focus write (the counts rise).
@MainActor @Test func aPressFrameCostsWhatAPressOnAnyFocusableCosts() async throws {
    let rig = try TermRig()
    await unfocused(rig)
    rig.window.resetFrameWork()
    rig.press(at: rig.point(3, 3))
    await rig.pump()
    rig.window.tick()
    let t = rig.window.frameWork.reduce((0, 0)) { ($0.0 + $1.builds, $0.1 + $1.elementRequests) }
    rig.release(at: rig.point(3, 3))

    let plain = try TestWindow(size: rig.size, textSystem: { portableSystem() }) {
        VStack(spacing: 0) { FocusProbe() }
    }
    plain.window.focus(nil)
    plain.tick(); plain.advance(by: 0.05)
    plain.resetFrameWork()
    plain.send(.mouseDown(MouseEvent(position: Point(x: Pixels(50), y: Pixels(50)), clickCount: 1, timestamp: nil)))
    plain.tick()
    let p = plain.frameWork.reduce((0, 0)) { ($0.0 + $1.builds, $0.1 + $1.elementRequests) }
    #expect(t.0 == p.0 && t.1 == p.1 && p.0 >= 1, "terminal \(t) vs plain focusable \(p)")
}

@MainActor private struct FocusProbe: Component {
    @FocusState var f: Bool
    var content: some ElementGroup {
        Box().frame(width: Pixels(300), height: Pixels(300)).focusable().focused($f)
    }
}

// MARK: - The default cursor style (`TRM-BF`)

private let bar = TerminalCursorStyle(shape: .bar, blinking: false)

@MainActor private func drawn(_ rig: TermRig) async -> TerminalRowPainter.CursorShape? {
    await rig.settle()
    return rig.model.drawnCursorShape
}

/// **7** The default shape draws: a block with no parameter, the given shape with one. Mutation: ignore the parameter.
@MainActor @Test func theDefaultCursorShapeIsDrawn() async throws {
    let rig = try TermRig(cursorStyle: bar)
    #expect(await drawn(rig) == .bar)
    let plain = try TermRig()
    #expect(await drawn(plain) == .block)
    let under = try TermRig(cursorStyle: TerminalCursorStyle(shape: .underline, blinking: false))
    #expect(await drawn(under) == .underline)
}

/// **8** A program's DECSCUSR 2, 4 and 6 override the default; 0 returns to it. Mutation: DECSCUSR 0 sets a blinking block.
@MainActor @Test func aProgramsStyleOverridesAndZeroReturns() async throws {
    let rig = try TermRig(cursorStyle: bar)
    await rig.settle()
    for (code, shape): (Int, TerminalRowPainter.CursorShape) in [(2, .block), (4, .underline), (6, .bar)] {
        rig.feed("\u{1b}[\(code) q")
        #expect(await drawn(rig) == shape, "DECSCUSR \(code)")
    }
    rig.feed("\u{1b}[2 q")
    #expect(await drawn(rig) == .block)
    rig.feed("\u{1b}[0 q")
    #expect(await drawn(rig) == .bar, "DECSCUSR 0 is the user's bar")
    #expect(rig.emulator.modes.cursorStyle == bar, "the reported modes are truthful")
}

/// **9** RIS and DECSTR return to the default. Mutation: they set a steady block.
@MainActor @Test func resetsReturnToTheDefaultStyle() async throws {
    let rig = try TermRig(cursorStyle: bar)
    await rig.settle()
    rig.feed("\u{1b}[2 q")
    #expect(await drawn(rig) == .block)
    rig.feed("\u{1b}c")
    #expect(await drawn(rig) == .bar, "RIS")
    rig.feed("\u{1b}[4 q")
    #expect(await drawn(rig) == .underline)
    rig.feed("\u{1b}[!p")
    #expect(await drawn(rig) == .bar, "DECSTR")
}

/// **10** Changing the parameter at runtime redraws the cursor row only, and a program's own style stays.
/// Mutation: the change redraws nothing (the shape stays) or every row.
@MainActor @Test func aRuntimeChangeRedrawsTheCursorRowOnly() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("abc\r\ndef")
    await rig.frame(); await rig.settle()
    rig.knobs.cursorStyle = bar
    rig.window.window.setNeedsRedraw()
    await rig.frame(); await rig.frame(); await rig.pump(); await rig.frame()
    #expect(rig.model.drawnCursorShape == .bar)
    let rows = rig.model.statistics.lastRows
    #expect(rows.count <= 1, "rows redrawn \(rows)")
    rig.feed("\u{1b}[4 q")
    #expect(await drawn(rig) == .underline)
    rig.knobs.cursorStyle = TerminalCursorStyle(shape: .block, blinking: false)
    rig.window.window.setNeedsRedraw()
    await rig.frame(); await rig.settle()
    #expect(rig.model.drawnCursorShape == .underline, "the program's style is kept")
}

/// **11** Blink: a blinking default blinks only with `cursorBlink`; `cursorBlink: false` keeps it steady and the default
/// steady style never blinks. Mutation: the default's blinking ignores `cursorBlink`.
@MainActor @Test func theDefaultsBlinkFollowsCursorBlink() async throws {
    let blinking = TerminalCursorStyle(shape: .bar, blinking: true)
    let on = try TermRig(cursorStyle: blinking)
    await on.settle()
    var seen = Set<Bool>()
    for _ in 0..<12 { await on.frame(0.25); seen.insert(on.model.drawnCursorShape != nil) }
    #expect(seen == [true, false], "a blinking default blinks")
    let off = try TermRig(blink: false, cursorStyle: blinking)
    await off.settle()
    for _ in 0..<12 { await off.frame(0.25); #expect(off.model.drawnCursorShape == .bar) }
    let steady = try TermRig(cursorStyle: bar)
    await steady.settle()
    for _ in 0..<12 { await steady.frame(0.25); #expect(steady.model.drawnCursorShape == .bar) }
}

/// **12** Cost: an idle terminal left at the default adds no emulator work for the parameter (no `perform`, no publish),
/// and the parameter is part of `Equatable`. Mutation: apply the style on every build; drop it from `same`.
@MainActor @Test func theParameterCostsNothingAtTheDefaultAndIsCompared() async throws {
    let rig = try TermRig()
    await rig.settle()
    let publishes = rig.source.statistics.publishes
    for _ in 0..<5 { rig.window.window.setNeedsRedraw(); await rig.frame() }
    #expect(rig.source.statistics.publishes == publishes, "no publish from the parameter")
    // The parameter's own cost: a default view publishes one snapshot fewer than a view that hands over a style.
    let other = try TermRig(cursorStyle: bar)
    await other.settle()
    #expect(other.source.statistics.publishes == publishes + 1, "default \(publishes), bar \(other.source.statistics.publishes)")
    let source = rig.source, theme = TerminalPalette.xterm
    func view(_ style: TerminalCursorStyle) -> TerminalView {
        TerminalView(snapshotSource: source, theme: theme, cursorStyle: style, onInput: { _ in }, onResize: { _ in }, onLink: { _ in nil })
    }
    let first = view(bar), second = view(bar)
    #expect(first == second)
    #expect(view(bar) != view(TerminalCursorStyle(shape: .block, blinking: false)))
    #expect(view(TerminalCursorStyle(shape: .bar, blinking: true)) != view(bar))
}
