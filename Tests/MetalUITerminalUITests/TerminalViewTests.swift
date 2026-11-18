import Foundation
import MetalUITesting
import MetalUIPlatform
import MetalUITerminal
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// Terminal phase 5.3 (`TRM-BA`): the view's layout, redraw policy and cost, headless on the portable text system
// (every platform). `TermRig` puts a `TerminalView` over the main queue so a feed runs inline and its wake calls the
// trigger on the main actor. Each test names the mutation it was shown red against.

/// The rig's window content: an optional editor above an optional `TerminalView`.
@MainActor func rigStack(source: TerminalSnapshotSource, log: TermRig.Log, knobs: TermRig.Knobs, extra: Bool, terminal: Bool,
                         blink: Bool, stops: Bool) -> some Element {
    VStack(spacing: 0) {
        if extra { TextField("t", text: .constant("")).accessibilityIdentifier("ed").frame(width: Pixels(100), height: Pixels(20)) }
        if knobs.shown && terminal {
            TerminalView(snapshotSource: source, theme: knobs.palette, keyCaptureExceptions: knobs.exceptions,
                         optionAsMeta: knobs.optionAsMeta, cursorBlink: blink, blinkStopsAfterIdle: stops, cursorStyle: knobs.cursorStyle,
                         onInput: { log.inputs.append($0) }, onResize: { log.resizes.append($0) },
                         onLink: { query in log.links.append(query); return knobs.link(query) },
                         onPaste: knobs.paste)
        }
    }
}

@MainActor final class TermRig {
    final class Log { var resizes: [TerminalSize] = []; var inputs: [[UInt8]] = []; var commands: [String] = []; var links: [TerminalLinkQuery] = []; var opened: [URL] = [] }
    final class Knobs { var palette = TerminalPalette.xterm; var shown = true; var cursorStyle = TerminalCursorStyle(shape: .block, blinking: false); var optionAsMeta = false; var exceptions: [KeyboardShortcut] = []; var link: (TerminalLinkQuery) -> TerminalLinkTarget? = { _ in nil }; var paste: (@MainActor (String, TerminalModes) -> Bool)? }
    let emulator: TerminalEmulator
    let source: TerminalSnapshotSource
    let log = Log()
    let knobs = Knobs()
    var resizes: [TerminalSize] { log.resizes }
    let window: TestWindow
    let size: Size<Pixels>
    var model: TerminalViewModel { TerminalViewModel.latestForTesting! }

    init(cols: Int = 80, rows: Int = 24, size: Size<Pixels> = Size(width: Pixels(400), height: Pixels(300)),
         blink: Bool = true, stops: Bool = true, extra: Bool = false, terminal: Bool = true, commands: Bool = false,
         opens: Bool = false, cursorStyle: TerminalCursorStyle = TerminalCursorStyle(shape: .block, blinking: false),
         accessibility: Bool = true,
         paste: (@MainActor (String, TerminalModes) -> Bool)? = nil) throws {
        self.size = size
        knobs.paste = paste
        knobs.cursorStyle = cursorStyle
        emulator = TerminalEmulator(cols: cols, rows: rows)
        source = TerminalSnapshotSource(emulator: emulator, queue: .main)
        let source = self.source, log = self.log, knobs = self.knobs
        let start = Size(width: size.width, height: Pixels(size.height.value + 40))
        // An `OpenURLAction` written at the root is an uncomparable custom key (`LI-C`): a window that writes one refuses
        // retention, so only a test that reads `log.opened` writes it. (A real app's window stamps an identity reading, `LI-D`.)
        if opens {
            window = try TestWindow(size: start, options: .init(accessibilityClientActive: accessibility), textSystem: { portableSystem() }) {
                rigStack(source: source, log: log, knobs: knobs, extra: extra, terminal: terminal, blink: blink, stops: stops)
                    .environment(\.openURL, OpenURLAction { url in log.opened.append(url); return .handled })
            }
        } else {
            window = try TestWindow(size: start, options: .init(accessibilityClientActive: accessibility), textSystem: { portableSystem() }) {
                rigStack(source: source, log: log, knobs: knobs, extra: extra, terminal: terminal, blink: blink, stops: stops)
            }
        }
        window.runsSurfaceDraws = true
        window.resize(to: size)
        if commands { window.testApp.app.commands { CommandMenu("Tools") { Button("Go") { log.commands.append("go") }.keyboardShortcut("k", modifiers: .command) } } }

    }

    /// Lets the source's queued work and the trigger's hops land, then draws and zeroes the counters.
    func settle() async {
        await pump()
        for _ in 0..<3 { window.tick(); window.advance(by: 0.05); await pump() }
        window.resetFrameWork()
    }

    /// Lets main-queue work run (a source resize, a trigger hop).
    func pump() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func feed(_ text: String) {
        Array(text.utf8).withUnsafeBytes { source.feed($0) }
    }

    /// One frame at `seconds` later.
    func frame(_ seconds: Double = 0.05) async { await pump(); window.advance(by: seconds) }
}

/// **1** (`TRM-BA` item 1) `onResize` fires once for the first layout and once per real change of the cell count; the
/// same size, and any number of further frames, fire nothing; the source is resized to the same grid first.
/// Mutation: report on every layout (the geometry action called unconditionally).
@MainActor @Test func onResizeFiresOncePerRealChange() async throws {
    let rig = try TermRig()
    await rig.settle()
    let first = rig.resizes
    #expect(first.count == 2, "\(first)")        // the first layout, then the settle at the test's size
    let size = try #require(first.last)
    for _ in 0..<5 { await rig.frame() }
    rig.window.resize(to: rig.size)
    await rig.frame()
    #expect(rig.resizes == first, "same size, no call")
    rig.window.resize(to: Size(width: Pixels(200), height: Pixels(150)))
    await rig.settle()
    #expect(rig.resizes.count == first.count + 1 && rig.resizes.last != size, "\(rig.resizes)")
    rig.window.resize(to: Size(width: Pixels(10), height: Pixels(5)))
    await rig.settle()
    #expect(rig.resizes.last == TerminalSize(cols: 2, rows: 1), "clamped to 2 x 1")
    rig.feed("x")
    await rig.settle()
    #expect(rig.model.statistics.snapshotsTaken >= 1)
}

/// **2** The source follows the view's grid. Mutation: `gridChanged` skips `source.resize`.
@MainActor @Test func theSourceIsResizedToTheViewsGrid() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("a")
    await rig.settle()
    let want = try #require(rig.resizes.last)
    #expect(rig.emulator.publishSnapshot().size == want)
}

/// **3** (`REQUIRED`) Output then a tick: 0 builds, 0 element requests, one surface-only frame, one draw, one snapshot.
/// Mutation: the wake calls `setNeedsRedraw` (builds 1).
@MainActor @Test func outputIsASurfaceOnlyFrame() async throws {
    let rig = try TermRig()
    await rig.settle()
    let draws = rig.window.surfaceDrawCount
    rig.feed("hello")
    await rig.frame()
    let work = rig.window.lastFrameWork
    #expect(work.builds == 0 && work.elementRequests == 0 && work.surfaceOnlyFrames == 1, "\(work.builds) \(work.elementRequests) \(work.surfaceOnlyFrames)")
    #expect(rig.window.surfaceDrawCount == draws + 1)
}

/// **4** (`REQUIRED`) A hundred feeds before one frame are one draw and one snapshot take; the next frames draw nothing.
/// Mutation: every feed requests its own redraw after the take.
@MainActor @Test func aHundredFeedsAreOneDraw() async throws {
    let rig = try TermRig()
    await rig.settle()
    let draws = rig.window.surfaceDrawCount, takes = rig.model.statistics.snapshotsTaken
    for i in 0..<100 { rig.feed("line \(i)\r\n") }
    await rig.frame()
    #expect(rig.window.surfaceDrawCount == draws + 1)
    #expect(rig.model.statistics.snapshotsTaken == takes + 1)
    await rig.frame(); await rig.frame()
    #expect(rig.window.surfaceDrawCount == draws + 1)
}

/// **5** (`REQUIRED`) Unfocused and idle: no frames over many ticks, no timer. Mutation: schedule a blink while unfocused.
@MainActor @Test func anUnfocusedIdleViewDrawsNothing() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("\u{1b}[1 q")
    rig.window.window.focus(nil)
    await rig.settle()
    await rig.settle()
    await rig.frame(1)
    let frames = rig.window.framesDrawn, draws = rig.window.surfaceDrawCount
    for _ in 0..<200 { await rig.frame(0.25) }
    #expect(rig.window.framesDrawn == frames && rig.window.surfaceDrawCount == draws,
            "\(rig.window.framesDrawn - frames) frames")
    #expect(rig.window.window.testingSurfaceDeadlineCount == 0)
}

/// **6** (`REQUIRED`) A focused, blinking, idle view over 35 simulated seconds: at most 61 surface frames (two a second
/// for 30 s), 0 builds and 0 element requests in them, then none. Mutation: no idle stop (frames keep coming).
@MainActor @Test func theBlinkStopsThirtySecondsAfterTheLastOutput() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("\u{1b}[1 q")
    await rig.frame()
    await rig.settle()
    rig.feed("x")
    await rig.frame()
    rig.window.resetFrameWork()
    var surface = 0, builds = 0, requests = 0, lastAt = 0.0
    let base = rig.window.surfaceDrawCount
    for step in 1...350 {
        let before = rig.window.surfaceDrawCount
        await rig.frame(0.1)
        if rig.window.surfaceDrawCount > before { surface += 1; lastAt = Double(step) * 0.1 }
        builds += rig.window.lastFrameWork.builds
        requests += rig.window.lastFrameWork.elementRequests
    }
    #expect(rig.window.surfaceDrawCount - base == surface)
    #expect(surface >= 55 && surface <= 61, "\(surface) frames, last at \(lastAt) s")
    #expect(builds == 0 && requests == 0, "builds \(builds) requests \(requests)")
    #expect(lastAt <= 30.2, "the last draw at \(lastAt) s")
}

/// **7** Without `blinkStopsAfterIdle` the blink goes on past 30 s. Mutation: ignore the flag.
@MainActor @Test func theBlinkGoesOnWhenItDoesNotStop() async throws {
    let rig = try TermRig(stops: false)
    await rig.settle()
    rig.feed("\u{1b}[1 q")
    await rig.frame()
    await rig.settle()
    var late = 0
    for step in 1...450 {
        let before = rig.window.surfaceDrawCount
        await rig.frame(0.1)
        if step > 400, rig.window.surfaceDrawCount > before { late += 1 }
    }
    #expect(late >= 5, "\(late)")
}

/// **8** A steady cursor (the power-on style) and `cursorBlink: false` schedule nothing. Mutation: blink without
/// asking the style.
@MainActor @Test func aSteadyCursorSchedulesNothing() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("x")
    await rig.settle()
    let draws = rig.window.surfaceDrawCount
    for _ in 0..<100 { await rig.frame(0.25) }
    #expect(rig.window.surfaceDrawCount == draws)
    let off = try TermRig(blink: false)
    await off.settle()
    off.feed("\u{1b}[1 q")
    await off.settle()
    let d = off.window.surfaceDrawCount
    for _ in 0..<100 { await off.frame(0.25) }
    #expect(off.window.surfaceDrawCount == d)
}

/// **9** (`REQUIRED`) A hidden view's trigger does nothing: output starts no frame; shown again it draws. Mutation: the
/// trigger stays bound after the surface left the frame.
@MainActor @Test func aHiddenViewDoesNothing() async throws {
    let rig = try TermRig()
    await rig.settle()
    let hiddenModel = rig.model
    rig.knobs.shown = false
    rig.window.window.setNeedsRedraw()
    await rig.frame()
    await rig.settle()
    let frames = rig.window.framesDrawn, draws = rig.window.surfaceDrawCount
    rig.feed("hidden output")
    for _ in 0..<5 { await rig.frame() }
    #expect(rig.window.framesDrawn == frames && rig.window.surfaceDrawCount == draws)
    #expect(!hiddenModel.trigger.isBound)
    rig.knobs.shown = true
    rig.window.window.setNeedsRedraw()
    await rig.frame()
    await rig.settle()
    #expect(rig.window.surfaceDrawCount > draws, "shown again, it draws")
    #expect(rig.model.statistics.lastRows.count > 1 || rig.model.statistics.fullRedraws > 0)
}

/// **10** (`REQUIRED`) A damaged-row redraw draws only the damaged rows and the cursor's old and new rows.
/// Mutation: redraw every row on each draw.
@MainActor @Test func onlyDamagedRowsAreRedrawn() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("abc\r\ndef")
    await rig.frame(); await rig.settle()
    #expect(rig.model.statistics.fullRedraws >= 1)
    rig.feed("g")                      // row 1 only; the cursor stays on it
    await rig.frame()
    #expect(rig.model.statistics.lastRows == [1], "\(rig.model.statistics.lastRows)")
    rig.feed("\u{1b}[5;1Hz")           // row 4 damaged; the cursor leaves row 1
    await rig.frame()
    #expect(rig.model.statistics.lastRows == [1, 4], "\(rig.model.statistics.lastRows)")
    rig.feed("\u{1b}[5;1H")            // nothing damaged, the cursor moves within its row
    await rig.frame()
    #expect(rig.model.statistics.lastRows == [4], "\(rig.model.statistics.lastRows)")
}

/// **11** A palette change redraws every row; so does a scroll of the viewport and a resize. Mutation: palette
/// change ignored (damage only).
@MainActor @Test func aPaletteChangeRedrawsEveryRow() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("x")
    await rig.frame(); await rig.settle()
    let full = rig.model.statistics.fullRedraws
    var palette = TerminalPalette.xterm
    palette.background = Color(hex: 0x102030)
    rig.knobs.palette = palette
    rig.window.window.setNeedsRedraw()
    await rig.frame()
    await rig.pump()
    #expect(rig.model.statistics.fullRedraws == full + 1)
    #expect(rig.model.statistics.lastRows.count == 16 || rig.model.statistics.lastRows.count == 18, "\(rig.model.statistics.lastRows.count)")
}

/// **12** The selection redraws the rows it covers, and clearing it redraws them again. Mutation: ignore the
/// selection's change.
@MainActor @Test func aSelectionRedrawsItsRows() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("one\r\ntwo\r\nthree")
    await rig.frame(); await rig.settle()
    rig.source.perform { $0.selection = .linear(TerminalRange(lowerBound: TerminalPosition(row: 0, col: 1),
                                                              upperBound: TerminalPosition(row: 1, col: 1))) }
    await rig.frame()
    #expect(rig.model.statistics.lastRows == [0, 1], "\(rig.model.statistics.lastRows)")   // the rows it covers; the cursor's row 2 is unchanged
    rig.source.perform { $0.selection = nil }
    await rig.frame()
    #expect(rig.model.statistics.lastRows == [0, 1], "\(rig.model.statistics.lastRows)")
    #expect(rig.model.selectedColumns(.linear(TerminalRange(lowerBound: TerminalPosition(row: 5, col: 2),
                                                           upperBound: TerminalPosition(row: 7, col: 3))), top: 5, row: 1, columns: 10) == 0..<10)
    #expect(rig.model.selectedColumns(.block(TerminalRange(lowerBound: TerminalPosition(row: 5, col: 2),
                                                          upperBound: TerminalPosition(row: 7, col: 4))), top: 5, row: 1, columns: 10) == 2..<5)
}

/// **13** A scrolled-back viewport draws the rows the snapshot lists. Mutation: draw the live rows.
@MainActor @Test func aScrolledBackViewportRedrawsAll() async throws {
    let rig = try TermRig()
    await rig.settle()
    for i in 0..<60 { rig.feed("row \(i)\r\n") }
    await rig.frame(); await rig.settle()
    rig.source.perform { $0.scrollViewport(toOffset: 10) }
    await rig.frame()
    #expect(rig.model.statistics.lastRows.count >= 16, "\(rig.model.statistics.lastRows.count)")
}

/// **14** (`REQUIRED`) An editor key frame in a window that also shows a terminal. The public `TerminalView` is retained by
/// default (`TRM-BD`: its content is the internal field under `.equatable()`, and surface replay, `TRM-BB`, lets that
/// replay a `GPUSurface`), so the frame costs exactly what the window without the terminal costs: 2 element requests, 1 build
/// (it was 4 before the default: the terminal's 2). Mutation: remove the `.equatable()` from `TerminalView.content` (4).
@MainActor @Test func aKeystrokeFrameCostIsPinned() async throws {
    func keyFrame(terminal: Bool) async throws -> (requests: Int, builds: Int) {
        let rig = try TermRig(extra: true, terminal: terminal)
        await rig.settle()
        try rig.window.focus(rig.window.element(identifier: "ed"))
        await rig.settle()
        rig.window.typeText("a")
        await rig.frame()
                return (rig.window.lastFrameWork.elementRequests, rig.window.lastFrameWork.builds)
    }
    let with = try await keyFrame(terminal: true), without = try await keyFrame(terminal: false)
    #expect(with.builds == without.builds && with.requests == without.requests, "with \(with) without \(without)")
    #expect(with.requests == 2 && without.requests == 2 && with.builds == 1)
}
