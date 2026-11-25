import Foundation
import MetalUITesting
import MetalUITerminal
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// A `.focused` binding on a container around a `TerminalView` (`FW-A`, record 365): Alloy's pane wrapper reads true while
// the terminal's focusable surface holds focus, with no parameter on the view, and writing true focuses the terminal.

@MainActor private final class PaneModel {
    var reads: [Bool] = []
    var setPane: (Bool) -> Void = { _ in }
}

@MainActor private struct Pane: Component {
    @FocusState var focused: Bool
    let model: PaneModel
    let source: TerminalSnapshotSource
    var content: some ElementGroup {
        // swiftlint:disable:next redundant_discardable_let - a result builder needs the declaration; `_ =` would be a stray statement
        let _ = model.reads.append(focused)
        // swiftlint:disable:next redundant_discardable_let - a result builder needs the declaration; `_ =` would be a stray statement
        let _ = model.setPane = { [focused = $focused] in focused.wrappedValue = $0 }
        VStack(spacing: 0) {
            TerminalView(snapshotSource: source, theme: .xterm, onInput: { _ in }, onResize: { _ in }, onLink: { _ in nil })
        }.focused($focused)
    }
}

/// **1** The container reads true while the terminal has focus and false after focus is cleared; a write of true
/// focuses the terminal's surface. Mutation: reconcile with the focused element's own binding only (the container never
/// reads true), or refuse a write to a non-focusable container (the focus assertion).
@MainActor @Test func aContainerAroundATerminalViewReadsItsFocus() async throws {
    let model = PaneModel()
    let emulator = TerminalEmulator(cols: 80, rows: 24)
    let source = TerminalSnapshotSource(emulator: emulator, queue: .main)
    let w = try TestWindow(size: Size(width: Pixels(400), height: Pixels(300)), textSystem: { portableSystem() }) {
        VStack(spacing: 0) { Pane(model: model, source: source) }
    }
    defer { withExtendedLifetime(w) {} }
    w.runsSurfaceDraws = true
    func settle() async throws { for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick(); w.advance(by: 0.05) }; try await w.runUntilIdle() }
    try await settle()
    w.window.focus(nil); try await settle()
    #expect(model.reads.last == false)
    let order = w.window.testingTabOrder
    try #require(order.count == 1, "the terminal's surface is the one focusable: \(order.count)")
    w.window.focus(order[0]); try await settle()
    #expect(model.reads.last == true, "focus is within the container: \(model.reads.suffix(3))")
    w.window.focus(nil); try await settle()
    #expect(model.reads.last == false)
    model.setPane(true); try await settle()
    #expect(w.window.focusedElement == order[0] && model.reads.last == true, "a write focuses the terminal")
}
