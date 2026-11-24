import Testing
import Foundation
import Observation
import MetalUI
import MetalUIScene
import MetalUITesting

// `SB-AF` (record 403), Alloy's report: a `CodeDecorations` write after the window went idle redrew nothing under two nested
// `.equatable()` occurrences (EditorGroupView over CodePanel). The outer occurrence re-armed its windows in a frame where the
// panel replayed, so only the panel's own sessions read `decorations.revision`, and the outer record replayed over it.
// PLAIN imports; the harness text system.

@Observable @MainActor private final class GateModel { var count = 0 }

private struct OuterGroup: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    let gate: GateModel
    var content: some ElementGroup {
        let _ = gate.count
        VStack(spacing: 0) {
            InnerPanel(buffer: buffer, decorations: decorations).equatable()
        }
    }
    static func == (l: OuterGroup, r: OuterGroup) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations && l.gate === r.gate }
}

private struct InnerPanel: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off)
    }
    static func == (l: InnerPanel, r: InnerPanel) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations }
}

@MainActor private func bars(_ window: TestWindow) -> Int {
    window.scene.rects.filter { $0.bounds.size.width == 3 }.count
}

/// **Mutation:** `ContentMemoStore.flagAncestorsOfFires` returning at once: the write fires the panel's sessions alone and the
/// gutter bar is never drawn (the cases with a gate write fail; the control without one passes).
@Test(arguments: [0, 1, 2, 4]) @MainActor
func aDecorationWriteAfterTheGroupRebuiltRedrawsUnderEquatableOccurrences(gateWrites: Int) async throws {
    let buffer = CodeBuffer((0..<40).map { "row\($0) = x" }.joined(separator: "\n") + "\n")
    let decorations = CodeDecorations(buffer: buffer)
    let gate = GateModel()
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            OuterGroup(buffer: buffer, decorations: decorations, gate: gate).equatable()
        }
    }
    try await window.runUntilIdle()
    window.window.focus(nil); window.tick()   // the window seats the view first; a focused view under an occurrence is never replayed, and in Alloy focus lives elsewhere
    try await window.runUntilIdle()
    window.tick()
    for _ in 0..<gateWrites {
        gate.count += 1
        try await window.runUntilIdle()
        window.tick()
    }
    #expect(bars(window) == 0)
    decorations.setLineDecorations([CodeLineDecoration(lines: 2..<5, gutterBar: .blue, tag: 1)], asOf: buffer.version)
    #expect(window.window.needsRedraw, "the write dirtied the window (gate writes \(gateWrites))")
    window.tick()
    #expect(bars(window) == 1, "bars \(bars(window)) (gate writes \(gateWrites))")
    // A second write, after the first frame, must redraw as well (Alloy: repeating the write did not help).
    decorations.setLineDecorations([CodeLineDecoration(lines: 2..<5, gutterBar: .blue, tag: 1),
                                    CodeLineDecoration(lines: 8..<9, gutterBar: .green, tag: 2)], asOf: buffer.version)
    #expect(window.window.needsRedraw, "the second write dirtied the window")
    window.tick()
    #expect(bars(window) == 2, "bars \(bars(window))")
}
