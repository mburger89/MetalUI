// Rich text, lane 3 — MetalUI's own inline Markdown parser (ruling RT-B).
// Pure Swift, no Foundation: `AttributedString(markdown:)` does not exist on
// Linux (`L2`), so one parser runs on every platform, macOS included, and the
// suite holds it to Foundation's answers on macOS (spec test 3.2).

/// One run of parsed inline Markdown: its text and the attributes the
/// Markdown gave it (ruling RT-B item 5).
struct MarkdownRun: Equatable, Sendable, CustomStringConvertible {
    var text: String
    var bold = false
    var italic = false
    var strikethrough = false
    var code = false
    /// A link's destination (`RT-K`), as Foundation's `URL.absoluteString`
    /// prints it.
    var link: String?

    var description: String {
        var parts = [text.debugDescription]
        if bold { parts.append("bold") }
        if italic { parts.append("italic") }
        if strikethrough { parts.append("strike") }
        if code { parts.append("code") }
        if let link { parts.append("link=\(link)") }
        return "[" + parts.joined(separator: " ") + "]"
    }

    /// Whether every attribute but the text equals `other`'s.
    func hasSameAttributes(as other: MarkdownRun) -> Bool {
        bold == other.bold && italic == other.italic && strikethrough == other.strikethrough
            && code == other.code && link == other.link
    }
}

/// One piece of a parsed format: text, or the interpolated value at that
/// position (its index), each with the attributes the Markdown gave it.
struct MarkdownPiece: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case text(String)
        case placeholder(Int)
    }
    var content: Content
    var attributes: MarkdownRun
}

/// `source` parsed as SwiftUI's inline Markdown (ruling RT-B): runs in order,
/// neighbours with equal attributes joined.
func parseInlineMarkdown(_ source: String) -> [MarkdownRun] {
    joinedMarkdownRuns(parseInlineMarkdown([.format(source)]).compactMap { piece in
        guard case .text(let text) = piece.content else { return nil }
        var run = piece.attributes
        run.text = text
        return run
    })
}

/// `segments` parsed as one format (ruling RT-C item 3): each value is a
/// placeholder the parser never reads as markup, returned at its position.
func parseInlineMarkdown(_ segments: [LocalizedStringKey.Segment]) -> [MarkdownPiece] {
    var pieces: [MarkdownPiece] = []
    var index = 0
    for segment in segments {
        switch segment {
        case .format(let string):
            pieces.append(MarkdownPiece(content: .text(string), attributes: MarkdownRun(text: "")))
        case .value, .runs:
            pieces.append(MarkdownPiece(content: .placeholder(index), attributes: MarkdownRun(text: "")))
            index += 1
        }
    }
    return pieces
}

/// `runs` with neighbours whose attributes agree joined, and empty runs
/// dropped.
func joinedMarkdownRuns(_ runs: [MarkdownRun]) -> [MarkdownRun] {
    var result: [MarkdownRun] = []
    for run in runs where !run.text.isEmpty {
        if let last = result.last, last.hasSameAttributes(as: run) {
            result[result.count - 1].text += run.text
        } else {
            result.append(run)
        }
    }
    return result
}
