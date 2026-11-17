import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUITerminal
@testable import MetalUI
@testable import MetalUIRender
@testable import MetalUITerminalUI

// Terminal phase 5.3 (`TRM-BA`): the view on Metal. A real `Window` over `FakePlatformWindow` holds a `TerminalView`
// on the CoreText text system; a known emulator state is fed and the target read back at the centres of a few cells.
// The default palette is xterm's, so a colour is its literal. No test sleeps.

private let side = 128

@MainActor private func render(_ input: String, steps: (@MainActor (TerminalSnapshotSource, Window) async -> Void)? = nil)
    async throws -> (pixels: [UInt8], cell: (w: Int, h: Int)) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let emulator = TerminalEmulator(cols: 10, rows: 4)
    let source = TerminalSnapshotSource(emulator: emulator, queue: .main)
    let (window, platform) = try makeFakeWindow(device: device, size: side) {
        VStack(spacing: 0) {
            TerminalView(snapshotSource: source, theme: .xterm, onInput: { _ in }, onResize: { _ in }, onLink: { _ in nil })
        }
    }
    func pump() async { for _ in 0..<20 { await Task.yield() } }
    for _ in 0..<4 { window.drawFrameIfNeeded(); await pump() }
    Array(input.utf8).withUnsafeBytes { source.feed($0) }
    for _ in 0..<4 { window.drawFrameIfNeeded(); await pump() }
    if let steps { await steps(source, window) }
    for _ in 0..<2 { window.drawFrameIfNeeded(); await pump() }
    let model = try #require(TerminalViewModel.latestForTesting)
    let metrics = try #require(model.cache?.metrics)
    return (platform.fakeSurface.readPixels(), (metrics.cellWidth, metrics.cellHeight))
}

private func rgb(_ p: [UInt8], _ x: Int, _ y: Int) -> [Int] {
    let i = (y * side + x) * 4
    return [Int(p[i + 2]), Int(p[i + 1]), Int(p[i])]
}

/// **1** A known snapshot reads back in the palette's colours: a red cell, a blue cell and a default cell on the
/// first row, black elsewhere, the margin past the grid black (cleared). The cursor is hidden. Mutations: the
/// selection or cursor drawn into the wrong row (not here); ignore a cell's background (the red reads black); swap
/// the ANSI table's 1 and 4.
@Test @MainActor func aKnownSnapshotRendersItsColours() async throws {
    let (p, cell) = try await render("\u{1b}[?25l\u{1b}[41m \u{1b}[44m \u{1b}[0m \u{1b}[48;2;1;2;3m \u{1b}[0m")
    func center(_ col: Int, _ row: Int) -> [Int] { rgb(p, col * cell.w + cell.w / 2, row * cell.h + cell.h / 2) }
    #expect(center(0, 0) == [205, 0, 0], "\(center(0, 0))")
    #expect(center(1, 0) == [0, 0, 238], "\(center(1, 0))")
    #expect(center(2, 0) == [0, 0, 0])
    #expect(center(3, 0) == [1, 2, 3], "\(center(3, 0))")
    #expect(center(0, 1) == [0, 0, 0])
    #expect(rgb(p, side - 1, side - 1) == [0, 0, 0])
}

/// **2** A focused view's block cursor is the palette's cursor colour over its cell; unfocused it is a hollow block
/// (outline only). Mutation: the filled block for every focus state.
@Test @MainActor func theCursorIsABlockFocusedAndHollowUnfocused() async throws {
    let (focused, cell) = try await render("")
    func center(_ p: [UInt8]) -> [Int] { rgb(p, cell.w / 2, cell.h / 2) }
    #expect(center(focused) == [229, 229, 229], "\(center(focused))")
    let (unfocused, _) = try await render("") { _, window in
        window.focus(nil)
        for _ in 0..<3 { window.drawFrameIfNeeded(); for _ in 0..<20 { await Task.yield() } }
    }
    #expect(center(unfocused) == [0, 0, 0], "hollow: the inside is the background \(center(unfocused))")
    #expect(rgb(unfocused, 0, cell.h / 2) == [229, 229, 229], "hollow: the outline")
}
