import Testing
import Foundation
import MetalUI
import MetalUIText
import MetalUITesting
import MetalUIScene

#if os(macOS)
// `CodeView` through the CoreText text system (record 227 run 2, `CV-M`): the rest of `CodeViewTests` runs on
// the portable system, which every platform shares; this proves the cache, the tab placement and the
// selection over CoreText's shaping and caret offsets, with a Retina scale. The numbers are CoreText's own
// (SF Mono), so they are relations (visible + 1, one row per row scrolled), never pixel literals.

@MainActor private func coreTextText(lines: Int) -> String {
    var out = ""
    for i in 0..<lines {
        switch i % 4 {
        case 0: out += "let value\(i) = \(i * 31 % 977) // line \(i)\n"
        case 1: out += "\tif x\(i) > 0 { return \"caf\u{E9} \u{4E16}\u{754C} \(i)\" }\n"
        case 2: out += "// \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} family \(i) \u{1F600}\n"
        default: out += "func f\(i)(_ a: Int) -> Int { a &+ \(i) }\n"
        }
    }
    return out
}

/// **CT.1** — a `CodeView` over `CoreTextTextSystem` at 2x: opening shapes the visible rows plus one, at 1k and
/// 100k lines alike; a one-row scroll shapes one line; a warm frame shapes none; a double click selects a word and
/// the copy key writes it; a tab line (CoreText answers a control differently from the portable system) places
/// its text after the stop. **Mutation:** the row loop over every row shapes 100 000 on open.
@Test(arguments: [1_000, 100_000]) @MainActor func aCodeViewRunsThroughTheCoreTextSystem(lines: Int) throws {
    let buffer = CodeBuffer(coreTextText(lines: lines))
    let decorations = CodeDecorations(buffer: buffer)
    let window = try TestWindow(size: Size(width: Pixels(500), height: Pixels(240)), scaleFactor: 2,
                                textSystem: { CoreTextTextSystem() }) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 13)
    }
    func work() -> FrameWork { window.frameWork.reduce(FrameWork(), +) }
    let open = work()
    #expect(open.codeLinesPainted >= 8 && open.codeLinesPainted <= 30, "painted \(open.codeLinesPainted)")
    #expect(open.codeLinesShaped == open.codeLinesPainted + 1, "shaped \(open.codeLinesShaped), painted \(open.codeLinesPainted)")
    #expect(open.codeGlyphsEmitted > 100)
    window.window.setNeedsRedraw(); window.tick()
    window.resetFrameWork()
    window.window.setNeedsRedraw(); window.tick()
    #expect(work().codeLinesShaped == 0, "a warm frame shapes nothing")

    // One row of wheel travel enters one row.
    let pitchPts = Float(240) / Float(open.codeLinesPainted)   // an upper bound of the pitch; scroll by a bit more than one row
    window.scroll(at: Point(x: Pixels(250), y: Pixels(120)), byDeltaX: 0, deltaY: -1)
    window.resetFrameWork()
    window.scroll(at: Point(x: Pixels(250), y: Pixels(120)), byDeltaX: 0, deltaY: -pitchPts * 2)
    #expect(work().codeLinesShaped >= 1 && work().codeLinesShaped <= 3, "shaped \(work().codeLinesShaped) lines for about one row")

    // Selection and copy over CoreText's caret offsets.
    buffer.select(0..<0, reveal: false)
    window.scroll(at: Point(x: Pixels(250), y: Pixels(120)), byDeltaX: 0, deltaY: 100_000_000)
    window.doubleClick(at: Point(x: Pixels(120), y: Pixels(8)))
    let selected = buffer.snapshot().text(in: buffer.primarySelection.range)
    #expect(!selected.isEmpty && !selected.contains(" "), "a word: \(selected.debugDescription)")
    window.typeKey("c", modifierFlags: .command)
    let copied = try #require(window.clipboardRepresentations.first)
    #expect(String(decoding: copied.bytes, as: UTF8.self) == selected)
}
#endif
