import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// `CodeView.onTextClick` (`CV-AL`, Alloy G35 B): the go-to-definition click. A press whose modifiers are exactly the
// handler's, on the text of a buffer row, is the app's and nothing else; every other press is as without a handler.

private struct TextClickFixture {
    var window: TestWindow
    var buffer: CodeBuffer
    var geometry: CodeViewGeometry
    var clicks: Cell<[CodeHit]>
}

@MainActor private func textClickFixture(modifiers: EventModifiers? = nil, virtualRow: Bool = false) throws -> TextClickFixture {
    let buffer = CodeBuffer((0..<30).map { "row\($0) = value" }.joined(separator: "\n") + "\n")
    let decorations = CodeDecorations(buffer: buffer)
    if virtualRow {
        decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 3), lines: ["- removed"])], asOf: buffer.version)
    }
    let geometry = CodeViewGeometry()
    let clicks = Cell<[CodeHit]>([])
    let window = try harnessWindow(size: sz(400, 600)) {
        if let modifiers {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off).geometry(geometry)
                .onTextClick(modifiers: modifiers) { clicks.value.append($0) }
        } else {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off).geometry(geometry)
                .onTextClick { clicks.value.append($0) }
        }
    }
    buffer.selections = [CodeSelection(caret: 0)]
    window.tick()
    return TextClickFixture(window: window, buffer: buffer, geometry: geometry, clicks: clicks)
}

/// The centre of `range`'s first rectangle (a point on its text).
@MainActor private func textPoint(_ f: TextClickFixture, _ range: Range<Int>) throws -> Point<Pixels> {
    let r = try #require(f.geometry.rects(for: range).first)
    return pt(r.origin.x.value + r.size.width.value / 2, r.origin.y.value + r.size.height.value / 2)
}

/// 1 — a primary click on text reports the hit (offset, grapheme, row, region), calls the action once, and leaves the
/// caret and the selection where they were. **Mutation:** `press` not returning after the action (the caret moves).
@Test @MainActor func aPrimaryClickReportsItsOffsetAndLeavesTheCaret() throws {
    let f = try textClickFixture()
    let row = f.buffer.snapshot().lineRange(5).lowerBound
    let point = try textPoint(f, (row + 5)..<(row + 6))   // inside "5 = value", on the "=" area
    f.window.click(at: point, modifierFlags: .primary)
    let hit = try #require(f.clicks.value.first)
    #expect(f.clicks.value.count == 1)
    #expect(hit.region == .text && hit.row == 5)
    #expect(hit.offset == f.geometry.hit(at: point)?.offset)
    #expect(hit.character != nil)
    #expect(f.buffer.primarySelection == CodeSelection(caret: 0), "the caret did not move")
    // A drag after the consumed press does not start a selection either.
    f.window.click(at: point, modifierFlags: .primary)
    #expect(f.buffer.primarySelection == CodeSelection(caret: 0))
}

/// 2 — shift-primary is not primary: the modifier set must be equal, not contain the handler's. **Mutation:**
/// `modifiers == click.modifiers` replaced by `modifiers.contains(click.modifiers)`.
@Test @MainActor func aShiftPrimaryClickIsNotAPrimaryClick() throws {
    let f = try textClickFixture()
    let row = f.buffer.snapshot().lineRange(5).lowerBound
    let point = try textPoint(f, (row + 5)..<(row + 6))
    let expected = try #require(f.geometry.hit(at: point)).offset
    f.window.click(at: point, modifierFlags: [.primary, .shift])
    #expect(f.clicks.value.isEmpty)
    #expect(f.buffer.primarySelection == CodeSelection(anchor: 0, head: expected), "shift extends as ever")
}

/// 3 — a plain click, an option click and a click with only the other modifier place the caret as without a handler.
@Test @MainActor func aPlainClickStillPlacesTheCaretWithAHandlerSet() throws {
    let f = try textClickFixture()
    let row = f.buffer.snapshot().lineRange(5).lowerBound
    let point = try textPoint(f, (row + 5)..<(row + 6))
    let expected = try #require(f.geometry.hit(at: point)).offset
    f.window.click(at: point)
    #expect(f.clicks.value.isEmpty)
    #expect(f.buffer.primarySelection == CodeSelection(caret: expected))
    f.buffer.selections = [CodeSelection(caret: 0)]
    f.window.click(at: point, modifierFlags: .option)
    #expect(f.clicks.value.isEmpty)
    #expect(f.buffer.primarySelection == CodeSelection(caret: expected))
}

/// 4 — a primary click right of a line's last character is a normal click (answer 5): the caret goes to the line's
/// end and the action is not called.
@Test @MainActor func aPrimaryClickPastTheLineEndPlacesTheCaret() throws {
    let f = try textClickFixture()
    let snap = f.buffer.snapshot()
    let r = try #require(f.geometry.rects(for: snap.lineRange(5).lowerBound..<(snap.lineRange(5).lowerBound + 1)).first)
    let point = pt(380, r.origin.y.value + r.size.height.value / 2)
    f.window.click(at: point, modifierFlags: .primary)
    #expect(f.clicks.value.isEmpty)
    #expect(f.buffer.primarySelection == CodeSelection(caret: f.geometry.hit(at: point)!.offset))
    #expect(f.geometry.hit(at: point)?.region == .pastLineEnd)
}

/// 5 — a primary click in the gutter or on a virtual row is a normal click.
@Test @MainActor func aPrimaryClickInTheGutterOrOnAVirtualRowActsAsNormal() throws {
    let f = try textClickFixture(virtualRow: true)
    let pitch = codePitch(scale: 1)
    // The gutter on row 6 (display row 7): a press selects the line.
    f.window.click(at: pt(3, 7.5 * pitch), modifierFlags: .primary)
    #expect(f.clicks.value.isEmpty)
    #expect(!f.buffer.primarySelection.range.isEmpty, "a gutter press selects the line")
    // The virtual row (display row 3): the text of "- removed".
    f.buffer.selections = [CodeSelection(caret: 0)]
    let point = pt(60, 3.5 * pitch)
    #expect(f.geometry.hit(at: point)?.region == .virtualRow)
    f.window.click(at: point, modifierFlags: .primary)
    #expect(f.clicks.value.isEmpty)
    #expect(f.buffer.primarySelection == CodeSelection(caret: f.buffer.snapshot().lineRange(3).lowerBound), "a virtual row's press places the caret at its buffer row's start")
}

/// 6 — the default modifier is the platform's primary (Command on Apple, Control elsewhere), and a handler given
/// `.control` on Apple is not triggered by Command. **Mutation:** the default `[]` (on Apple `.command` is the same bit, so only `[]` or `.shift` are caught there; the Control half runs on Linux and Windows CI).
@Test @MainActor func theDefaultModifierIsThePlatformsPrimary() throws {
    #if os(macOS)
    #expect(EventModifiers.primary == .command)
    #else
    #expect(EventModifiers.primary == .control)
    #endif
    let f = try textClickFixture()
    let row = f.buffer.snapshot().lineRange(5).lowerBound
    let point = try textPoint(f, (row + 5)..<(row + 6))
    f.window.click(at: point, modifierFlags: .primary)
    #expect(f.clicks.value.count == 1)
    let g = try textClickFixture(modifiers: .option)
    let p2 = try textPoint(g, (row + 5)..<(row + 6))
    g.window.click(at: p2, modifierFlags: .primary)
    #expect(g.clicks.value.isEmpty, "a handler for option ignores the platform primary")
    g.window.click(at: p2, modifierFlags: .option)
    #expect(g.clicks.value.count == 1)
}
