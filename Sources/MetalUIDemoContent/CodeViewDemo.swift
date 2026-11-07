import MetalUI
import Observation

/// The code view demo (`CV-`, record 227; human checks group CV), reached with
/// `METALUI_CODE_DEMO=1 swift run MetalUIDemo`: a generated 100 000-line source file in a read-only
/// ``CodeView`` with
///
/// - syntax colours from a ``CodeHighlightProvider`` that colours only the rows asked for (keywords, numbers,
///   strings and comments), so the colours arrive as the view scrolls;
/// - author bars in the gutter (a different colour every 40 lines) and, behind them, an authorship tint layer;
/// - diff tints (green blocks) and, before each block, three **virtual rows** of removed lines with a red tint, a
///   red bar and a `-` marker, which are not selectable and have no line numbers;
/// - a second, narrow view of the same buffer scrolled with the first through ``CodeScrollState`` and
///   ``CodeView/onScroll(_:)``, to see the synced scroll and the shared selection;
/// - buttons: Top, "Line 50 000" (`select(_:reveal:)` centres it in both views) and "Insert a line at the top"
///   (the reader's row and the decorations hold still).
///
/// **The human looks** (group CV): scrolling stays smooth over the whole file with a trackpad on both axes, the
/// colours fill in without a flash of plain text, the virtual rows scroll with the text and cannot be selected,
/// the two views stay on the same rows, and the selection and tint colours read in light and dark.
/// Nothing here is in the default demo, so the fourteen offscreen images and `Expected.swift` do not move.
/// **Each part is its own function** passed to a generic composer (the Windows 1 MB stack rule); built on a 1 MB
/// thread by `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func codeViewDemoContent(model: CodeViewDemoModel = codeViewDemoModel) -> some Element {
    codeDemoRoot(header: codeDemoHeader(model), buttons: codeDemoButtons(model), main: codeDemoMainView(model),
                 side: codeDemoSideView(model))
}

/// The demo's state: one buffer of 100 000 generated lines, its decorations and the two scroll states.
@MainActor
public final class CodeViewDemoModel {
    /// The generated file.
    public let buffer: CodeBuffer
    /// Highlights, author bars, diff tints and virtual rows of ``buffer``.
    public let decorations: CodeDecorations
    /// The main view's scroll position.
    public let mainScroll = CodeScrollState()
    /// The side view's scroll position.
    public let sideScroll = CodeScrollState()
    let highlighter: CodeDemoHighlighter

    /// The 100 000-line file with all of its decorations.
    public init(lines: Int = 100_000) {
        buffer = CodeBuffer(Self.source(lines: lines))
        decorations = CodeDecorations(buffer: buffer)
        highlighter = CodeDemoHighlighter(decorations: decorations)
        decorations.highlightProvider = highlighter
        decorate(lines: lines)
    }

    /// Distinct lines of Swift-looking code, so a line cache of content cannot collapse them.
    static func source(lines: Int) -> String {
        var out = ""
        out.reserveCapacity(lines * 44)
        for i in 0..<lines {
            switch i % 6 {
            case 0: out += "// section \(i / 6): generated line \(i)\n"
            case 1: out += "func compute\(i)(_ value: Int) -> Int {\n"
            case 2: out += "    let scaled = value * \(i % 97 + 2) + \(i)\n"
            case 3: out += "    if scaled > \(i * 3) { return scaled - \(i % 13) }\n"
            case 4: out += "    return \"result \(i): \\(scaled)\".count\n"
            default: out += "}\n"
            }
        }
        return out
    }

    private func decorate(lines: Int) {
        let palette = [Color(red: 0.2, green: 0.6, blue: 1), Color(red: 0.9, green: 0.6, blue: 0.1), Color(red: 0.7, green: 0.3, blue: 0.9)]
        var bars: [CodeLineDecoration] = []
        var start = 0
        while start < lines {
            let block = start / 40
            bars.append(CodeLineDecoration(lines: start..<min(lines, start + 40), gutterBar: palette[block % palette.count]))
            start += 40
        }
        // Diff tints: a green block every 500 lines.
        let green = Color(red: 0.2, green: 0.7, blue: 0.3).opacity(0.18)
        var row = 0
        while row + 10 < lines {
            bars.append(CodeLineDecoration(lines: (row + 100)..<min(lines, row + 110), background: green))
            row += 500
        }
        decorations.setLineDecorations(Self.merge(bars, lines: lines), asOf: buffer.version)
        // Virtual rows: three removed lines before each green block.
        let red = Color(red: 0.9, green: 0.2, blue: 0.2)
        let removedStyle = decorations.register(CodeStyle(foreground: red))
        var removed: [CodeVirtualRow] = []
        row = 0
        while row + 100 < lines {
            let texts = ["    let old\(row) = legacy(\(row))", "    if old\(row) > 0 { return old\(row) }", "    // removed in this hunk"]
            removed.append(CodeVirtualRow(anchor: .before(line: row + 100), lines: texts,
                                          styleRuns: texts.map { [CodeStyleRun(range: 0..<$0.utf8.count, style: removedStyle)] },
                                          gutterBar: red, background: red.opacity(0.12), gutterMarker: CodeGutterMarker("-", color: red)))
            row += 500
        }
        decorations.setVirtualRows(removed, asOf: buffer.version)
    }

    /// Bars are one decoration per row range; a later one (a tint block) replaces an earlier on the rows it
    /// covers in this store, so the two kinds are merged per row range here.
    private static func merge(_ all: [CodeLineDecoration], lines: Int) -> [CodeLineDecoration] {
        var bars: [CodeLineDecoration] = [], tints: [CodeLineDecoration] = []
        for d in all { if d.gutterBar != nil { bars.append(d) } else { tints.append(d) } }
        var result: [CodeLineDecoration] = []
        var tintIndex = 0
        for bar in bars {
            var cursor = bar.lines.lowerBound
            while cursor < bar.lines.upperBound {
                while tintIndex < tints.count, tints[tintIndex].lines.upperBound <= cursor { tintIndex += 1 }
                if tintIndex < tints.count, tints[tintIndex].lines.lowerBound <= cursor {
                    let end = min(bar.lines.upperBound, tints[tintIndex].lines.upperBound)
                    result.append(CodeLineDecoration(lines: cursor..<end, gutterBar: bar.gutterBar, background: tints[tintIndex].background))
                    cursor = end
                } else {
                    let end = tintIndex < tints.count ? min(bar.lines.upperBound, tints[tintIndex].lines.lowerBound) : bar.lines.upperBound
                    result.append(CodeLineDecoration(lines: cursor..<end, gutterBar: bar.gutterBar))
                    cursor = end
                }
            }
        }
        return result
    }
}

/// Colours the rows it is asked for: keywords, numbers, strings and `//` comments.
@MainActor
final class CodeDemoHighlighter: CodeHighlightProvider {
    private unowned let decorations: CodeDecorations
    private let keyword: CodeStyleID, number: CodeStyleID, string: CodeStyleID, comment: CodeStyleID
    private static let keywords: Set<String> = ["func", "let", "if", "return", "var", "struct"]

    init(decorations: CodeDecorations) {
        self.decorations = decorations
        keyword = decorations.register(CodeStyle(foreground: Color(red: 0.75, green: 0.3, blue: 0.85)))
        number = decorations.register(CodeStyle(foreground: Color(red: 0.9, green: 0.55, blue: 0.1)))
        string = decorations.register(CodeStyle(foreground: Color(red: 0.85, green: 0.3, blue: 0.3)))
        comment = decorations.register(CodeStyle(foreground: Color(red: 0.3, green: 0.65, blue: 0.35)))
    }

    func decorations(_ decorations: CodeDecorations, needHighlightsForRows rows: Range<Int>, in snapshot: CodeSnapshot) {
        var runs: [CodeStyleRun] = []
        for row in rows {
            let range = snapshot.lineRange(row)
            let bytes = Array(snapshot.text(in: range).utf8)
            var i = 0
            while i < bytes.count {
                let b = bytes[i]
                if b == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2F {
                    runs.append(CodeStyleRun(range: (range.lowerBound + i)..<range.upperBound, style: comment))
                    break
                } else if b == 0x22 {
                    var j = i + 1
                    while j < bytes.count, bytes[j] != 0x22 { j += 1 }
                    j = min(bytes.count, j + 1)
                    runs.append(CodeStyleRun(range: (range.lowerBound + i)..<(range.lowerBound + j), style: string))
                    i = j
                } else if b >= 0x30 && b <= 0x39 {
                    var j = i
                    while j < bytes.count, bytes[j] >= 0x30 && bytes[j] <= 0x39 { j += 1 }
                    runs.append(CodeStyleRun(range: (range.lowerBound + i)..<(range.lowerBound + j), style: number))
                    i = j
                } else if (b >= 0x61 && b <= 0x7A) || b == 0x5F {
                    var j = i
                    while j < bytes.count, (bytes[j] >= 0x61 && bytes[j] <= 0x7A) || (bytes[j] >= 0x30 && bytes[j] <= 0x39) || bytes[j] == 0x5F { j += 1 }
                    if Self.keywords.contains(String(decoding: bytes[i..<j], as: UTF8.self)) {
                        runs.append(CodeStyleRun(range: (range.lowerBound + i)..<(range.lowerBound + j), style: keyword))
                    }
                    i = j
                } else {
                    i += 1
                }
            }
        }
        let lo = snapshot.lineRange(rows.lowerBound).lowerBound, hi = snapshot.lineRange(rows.upperBound - 1).upperBound
        decorations.setHighlights(runs, in: lo..<hi, layer: .syntax, asOf: snapshot.version)
    }
}

/// The one model the demo and its tests share.
@MainActor public let codeViewDemoModel = CodeViewDemoModel()

@MainActor
private func codeDemoHeader(_ model: CodeViewDemoModel) -> some Element {
    let top = Int(model.mainScroll.position.row)
    return Text("CodeView: \(model.buffer.lineCount) lines, \(model.decorations.virtualLineCount) virtual rows; top display row \(top)")
        .font(size: 13)
}

@MainActor
private func codeDemoButtons(_ model: CodeViewDemoModel) -> some Element {
    return Row(gap: Pixels(8)) {
        Button("Top") { model.mainScroll.position = CodeScrollPosition(row: 0, x: 0) }
        Button("Line 50 000") {
            let offset = model.buffer.snapshot().offset(of: CodePoint(row: 50_000, column: 0))
            model.buffer.select(offset..<offset, reveal: true)
        }
        Button("Insert a line at the top") { model.buffer.replace(0..<0, with: "// inserted\n") }
    }
}

@MainActor
private func codeDemoMainView(_ model: CodeViewDemoModel) -> some Element {
    return CodeView(buffer: model.buffer, decorations: model.decorations)
        .font(size: 12)
        .scrollState(model.mainScroll)
        .onScroll { model.sideScroll.position = $0 }
        .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
        .accessibilityIdentifier("code-main")
}

@MainActor
private func codeDemoSideView(_ model: CodeViewDemoModel) -> some Element {
    return CodeView(buffer: model.buffer, decorations: model.decorations)
        .font(size: 9)
        .showsLineNumbers(false)
        .scrollState(model.sideScroll)
        .onScroll { model.mainScroll.position = $0 }
        .frame(width: Pixels(260))
        .frame(maxHeight: Pixels(.infinity))
        .accessibilityIdentifier("code-side")
}

@MainActor
private func codeDemoRoot(header: some Element, buttons: some Element, main: some Element, side: some Element) -> some Element {
    Column(gap: Pixels(8)) {
        header
        buttons
        Row(gap: Pixels(8)) {
            main
            side
        }
        .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
    }
    .padding(Pixels(16))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}
