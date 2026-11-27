import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// The fixture of record 439 (`FS-AA`): Alloy's chat. A transcript of `MarkdownView` rows (every 5th a swift fence wider than the column, every
// 7th a table, both scrolling sideways) over a composer, in a 420 x 600 window at scale 2, the last row streaming 12 characters a step. A row
// that moves holds a horizontal `ProposalScrollView` whose hitbox the prepaint ledger has to move with it (`hitboxScrolls`, record 439).

/// The theme of Alloy's chat: fences and tables scroll sideways, fences carry a copy button.
func atTheme() -> MarkdownTheme {
    var t = MarkdownTheme()
    t.codeWraps = false
    t.tableScrolls = true
    t.showsCodeCopyButton = true
    return t
}

/// One row: a paragraph, then a fence on every 5th and a table on every 7th. Both are wider than the column.
func atSource(_ id: Int) -> String {
    var out = "Row \(id) has some words in it, enough to wrap over a line or two in a narrow column.\n\n"
    if id.isMultiple(of: 5) {
        out += "```swift\nlet value\(id) = computeSomethingWithAVeryLongName(argumentNumberOne: \(id), argumentNumberTwo: \(id + 1), argumentNumberThree: \(id + 2))\nprint(value\(id))\n```\n\n"
    }
    if id.isMultiple(of: 7) {
        out += "| name of a column | another column name | a third column name |\n|:--|--:|:--|\n"
            + (0..<3).map { "| row \(id) cell \($0) with text | \($0 * id) | a long trailing cell of row \(id) \($0) |\n" }.joined() + "\n"
    }
    return out
}

/// The streaming row: a fence, then a paragraph that grows 12 characters a step.
func atStreamSource(_ step: Int) -> String {
    "```swift\nlet streaming = computeSomethingWithAVeryLongName(argumentNumberOne: 1, argumentNumberTwo: 2, argumentNumberThree: 3)\n```\n\n"
        + "Streaming" + " " + (0..<step).map { String(format: "tok%03d word ", $0) }.joined()
}

struct ATRow: Component, @MainActor Equatable {
    let id: Int
    let source: String
    let theme: MarkdownTheme
    var content: some ElementGroup {
        MarkdownView(MarkdownDocument(parsing: source)).markdownTheme(theme)
    }
    static func == (l: ATRow, r: ATRow) -> Bool { l.id == r.id && l.source == r.source }
}

struct ATTranscript: Component {
    let step: Int
    var content: some ElementGroup {
        let theme = atTheme()
        let rows = (0..<50).map { ATRow(id: $0, source: atSource($0), theme: theme) }
            + [ATRow(id: 999, source: atStreamSource(step), theme: theme)]
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Pixels(10)) {
                ForEach(rows, id: \.id) { row in row.equatable() }
            }.padding(g49Inset)
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ATComposerBar: Component, @MainActor Equatable {
    let side: RPSide
    var content: some ElementGroup {
        let side = self.side
        HStack(spacing: 8) {
            TextField("Message", text: Binding(get: { side.inputs.text }, set: { side.inputs.text = $0 }))
            Button("Send") {}
        }
        .padding(Edges(all: Pixels(8)))
    }
    static func == (l: ATComposerBar, r: ATComposerBar) -> Bool { l.side === r.side }
}

struct ATComposer: Component, @MainActor Equatable {
    let side: RPSide
    var content: some ElementGroup { ATComposerBar(side: side).equatable() }
    static func == (l: ATComposer, r: ATComposer) -> Bool { l.side === r.side }
}

/// The chat: the stream step is its input, so it misses on every streamed delta.
struct ATSession: Component, @MainActor Equatable {
    let step: Int
    let side: RPSide
    var content: some ElementGroup {
        VStack(spacing: 0) {
            ATTranscript(step: step)
            Divider()
            ATComposer(side: side).equatable()
        }
    }
    static func == (l: ATSession, r: ATSession) -> Bool { l.step == r.step && l.side === r.side }
}

/// The pair: both windows, graft off by default (the focus arms count a build that runs). `focused` clicks the composer's field, then the pointer leaves.
@MainActor func atPair(focused: Bool = false, graft: Bool = false) throws -> RPPair<some Element> {
    let pair = try RPPair(size: sz(420, 600), scale: 2, warm: 8, accessibility: false, graft: graft) { side in
        VStack(spacing: 0) { ATSession(step: Int(side.inputs.offset), side: side).equatable() }
    }
    if focused {
        for w in [pair.on, pair.off] { w.click(at: pt(60, 580)) }
        for w in [pair.on, pair.off] { w.exitPointer() }
    }
    for _ in 0..<2 { pair.redraw() }
    pair.frames = []; pair.work = FrameWork()
    return pair
}

/// One streamed delta on both sides, settled, one frame each; the retaining window's frames of the step.
@MainActor func atStream(_ pair: RPPair<some Element>) async -> [FrameWork] {
    pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
    pair.on.resetFrameWork()
    await rsSettle()
    pair.redraw()
    return pair.on.frameWork
}

/// A vertical wheel step over the transcript's left inset (clear of every fence), on both windows.
@MainActor func atWheel(_ pair: RPPair<some Element>, dy: Float) {
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.scroll(at: pt(4, 300), byDeltaX: 0, deltaY: dy) }
    pair.frames.append(pair.on.lastFrameWork); pair.work += pair.on.lastFrameWork
}

/// The frames the retaining window drew for the last input.
@MainActor func atFrames(_ pair: RPPair<some Element>) -> [FrameWork] { pair.on.frameWork }

/// A horizontal wheel step over the first horizontal scroller whose centre is on screen, both windows. Returns that scroller's id.
@MainActor @discardableResult func atFenceWheel(_ pair: RPPair<some Element>, dx: Float) -> GlobalElementID? {
    guard let region = pair.on.window.lastHitboxes.last(where: { $0.scroll == .horizontal && $0.bounds.size.width.value > 40 }) else { return nil }
    let c = pt(region.bounds.origin.x.value + region.bounds.size.width.value / 2, region.bounds.origin.y.value + region.bounds.size.height.value / 2)
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.scroll(at: c, byDeltaX: dx, deltaY: 0) }
    pair.frames.append(pair.on.lastFrameWork); pair.work += pair.on.lastFrameWork
    return region.id
}
