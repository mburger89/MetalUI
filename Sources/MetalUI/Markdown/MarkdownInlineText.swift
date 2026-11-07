import MetalUICore
import MetalUIMarkdown

/// Raw inline Markdown from a block, lowered to a `Text` content (`BM-E`).
///
/// MetalUI's inline parser keeps a line break as written and keeps the spaces before a hard break (it is
/// `Text`'s parser, the inline-only parse); the block parser joins a paragraph's lines with `"\n"`. So a soft
/// break becomes a space (or stays a line break under ``MarkdownSoftBreak/lineBreak``) and a hard break
/// (two spaces or a backslash before the newline) stays a newline with its spaces trimmed, before parsing.
enum MarkdownInlineLowering {
    /// `raw` with its line breaks decided.
    static func prepared(_ raw: String, softBreak: MarkdownSoftBreak) -> String {
        var hasNewline = false
        for byte in raw.utf8 where byte == 10 { hasNewline = true; break }
        if !hasNewline { return raw }
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        var out = ""
        out.reserveCapacity(raw.utf8.count)
        var i = 0
        while i < lines.count {
            var line = lines[i]
            if i == lines.count - 1 { out += line; break }
            let spaced = line.hasSuffix("  ")
            if spaced { while line.hasSuffix(" ") { line = line.dropLast() } }
            out += line
            out += spaced || line.hasSuffix("\\") || softBreak == .lineBreak ? "\n" : " "
            i += 1
        }
        return out
    }

    /// The runs of `raw`: inline Markdown through the parser `Text` uses, an inline code span with the theme's
    /// background, and `weight` over the runs that name none (a table header's bold).
    static func requests(_ raw: String, theme: MarkdownTheme, weight: Font.Weight? = nil) -> [TextRunRequest] {
        let source = prepared(raw, softBreak: theme.softBreak)
        guard markdownMayApply(source) else {
            var run = TextRunRequest(string: source)
            run.weight = weight
            return [run]
        }
        var out: [TextRunRequest] = []
        for run in parseInlineMarkdown(source) {
            var request = markdownRunRequest(run.text, run)
            if run.code { request.background = theme.inlineCodeBackground }
            if request.weight == nil { request.weight = weight }
            out.append(request)
        }
        return out
    }

    /// The text of a paragraph, heading or cell.
    @MainActor
    static func text(_ raw: String, theme: MarkdownTheme, font: Font, weight: Font.Weight? = nil) -> ProposalText {
        ProposalText(content: collapsedTextContent(requests(raw, theme: theme, weight: weight))).font(font)
    }
}
