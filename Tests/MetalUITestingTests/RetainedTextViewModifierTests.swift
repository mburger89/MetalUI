import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// R3-10 part 1 (`TM-G`): a view-level text modifier reaches a retained decision and the layout memo through
// exactly one value each, `EnvironmentFingerprint.textRich`/`.isBold`. Eight `.equatable()` panels hold a
// `Text` and an underline; the parent writes `.kerning`, `.underline(pattern:)` and `.bold()` above them.
// A change must miss every panel and repaint (equal to a retention-off twin), an equal rebuild must hit.
// Counts and values, never time.

@Observable @MainActor final class TMBox {
    var kerning: Double = 1
    var pattern: Text.LineStyle.Pattern = .dash
    var bold = false
}

struct TMNode: Component, @MainActor Equatable {
    let index: Int
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hamburg \(index)")
            Text("wrapped words of a long label").frame(width: 60)
        }
    }
    // The modifiers are deliberately not part of the value: they enter from outside the occurrence.
    static func == (l: TMNode, r: TMNode) -> Bool { l.index == r.index }
}

struct TMParent: Component {
    let box: TMBox
    var content: some ElementGroup {
        let kerning = box.kerning, pattern = box.pattern, bold = box.bold
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(0..<8), id: \.self) { i in
                TMNode(index: i).equatable().kerning(kerning).underline(true, pattern: pattern).bold(bold)
            }
        }
    }
}

@MainActor func tmWindow(retain: Bool = true) throws -> (TestWindow, TMBox) {
    let box = TMBox()
    let window = try TestWindow(size: sz(900, 160), colorScheme: .light, scaleFactor: 1, textSystem: harnessTextSystem) {
        VStack(spacing: 0) { TMParent(box: box) }
    }
    window.window.testingRetainedGraft = true
    window.window.testingRetainedSubtrees = retain
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    return (window, box)
}

@Suite(.serialized) @MainActor
struct RetainedTextViewModifierTests {
    private func change(_ edit: (TMBox) -> Void) throws -> (missed: Int, onSnapshot: RPSnapshot, offSnapshot: RPSnapshot, glyphs: [Float], before: [Float]) {
        let (on, onBox) = try tmWindow()
        let (off, offBox) = try tmWindow(retain: false)
        let before = on.scene.glyphs.map { $0.bounds.origin.x }
        on.resetFrameWork()
        edit(onBox); edit(offBox)
        on.window.setNeedsRedraw(); on.tick()
        off.window.setNeedsRedraw(); off.tick()
        let missed = on.frameWork.reduce(0) { $0 + $1.retainedMisses }
        return (missed, try RPSnapshot(on), try RPSnapshot(off), on.scene.glyphs.map { $0.bounds.origin.x }, before)
    }

    /// An ancestor's `.kerning` change misses every panel, repaints wider text (the glyphs move) and equals
    /// a retention-off twin; the layout memo re-measures (the twin has it too, `verifies` off). **Mutation:**
    /// `retainedFingerprint` without `textRich` (reddens: no miss, stale glyphs).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss"))
    func anAncestorsKerningChangeMissesEveryPanelAndRepaints() throws {
        let result = try change { $0.kerning = 4 }
        #expect(result.missed >= 8, "every panel misses: \(result.missed)")
        #expect(result.glyphs != result.before, "the glyphs moved")
        #expect(result.onSnapshot.differences(from: result.offSnapshot).isEmpty)
    }

    /// A pattern change (`.dash` to `.dot`) is a change too: the decoration is painted, not measured.
    /// **Mutation:** the pattern left out of `TextRichFields`' equality (the fingerprint compares equal).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss"))
    func anAncestorsPatternChangeMissesEveryPanel() throws {
        let (on, box) = try tmWindow()
        let (off, offBox) = try tmWindow(retain: false)
        func thin(_ w: TestWindow) -> [MUIRect] { w.scene.rects.filter { $0.bounds.size.height < 5 } }
        let before = thin(on)
        on.resetFrameWork()
        box.pattern = .dot; offBox.pattern = .dot
        on.window.setNeedsRedraw(); on.tick()
        off.window.setNeedsRedraw(); off.tick()
        #expect(on.frameWork.reduce(0) { $0 + $1.retainedMisses } >= 8)
        #expect(thin(on).count != before.count || thin(on).map(\.bounds.size.width) != before.map(\.bounds.size.width), "the segments changed")
        #expect(try RPSnapshot(on).differences(from: RPSnapshot(off)).isEmpty)
    }

    /// A bold toggle misses every panel and equals the twin. **Mutation:** `retainedFingerprint`
    /// without `isBold`.
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss"))
    func anAncestorsBoldChangeMissesEveryPanel() throws {
        let result = try change { $0.bold = true }
        // The harness's text system has one face (Noto Sans Regular), so the weight moves no glyph: the miss and the
        // twin's equality are the witnesses.
        #expect(result.missed >= 8, "every panel misses: \(result.missed)")
        #expect(result.onSnapshot.differences(from: result.offSnapshot).isEmpty)
    }

    /// The same modifiers rebuilt equal every frame are no change: all eight panels hit. **Mutation:** a
    /// fingerprint comparing the box by identity.
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss"))
    func equalModifiersRebuiltAreAllHits() throws {
        let (on, box) = try tmWindow()
        on.resetFrameWork()
        box.kerning = 1; box.pattern = .dash; box.bold = false
        on.window.setNeedsRedraw(); on.tick()
        let frame = try #require(on.frameWork.last)
        #expect(frame.retainedMisses == 0 && frame.retainedHits == 8, "h\(frame.retainedHits) m\(frame.retainedMisses)")
    }
}
