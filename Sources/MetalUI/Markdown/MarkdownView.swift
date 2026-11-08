import MetalUICore
import MetalUIMarkdown

/// A Markdown document as a stack of blocks: paragraphs, headings, lists, quotes, rules, code blocks and
/// tables, built from existing views and meant for a chat reply that streams in (`BM-E`).
///
/// Hold a ``MarkdownDocument`` and call `append(_:)` per token (O(token)), or pass the whole `String` each
/// time: the view keeps the last source and, when the new one extends it, parses only the added text. Equality
/// is O(1) on the document (its storage identity and version), the theme and the highlighter's identity; each
/// block is its own `.equatable()` component, so a token changes the last block alone and earlier replies in a
/// transcript are skipped and replayed. Links open through `\.openURL`; headings are accessibility headings.
/// **No text selection, no copy accessory, no reference links, HTML blocks or task-list boxes in v1** (`BM-J`).
/// MetalUI-only: SwiftUI has no block Markdown, and the parse is cmark-gfm's block structure.
public struct MarkdownView: Component, ProposalElementGroup, @MainActor Equatable {
    enum Source {
        case document(MarkdownDocument)
        case string(String)
    }

    var source: Source
    var theme = MarkdownTheme()
    var highlighter: (any MarkdownCodeHighlighter)?
    @State private var memo = MarkdownSourceMemo()

    /// A view of `document`.
    public init(_ document: MarkdownDocument) {
        source = .document(document)
    }

    /// A view of the Markdown in `source`. When a later `source` extends the earlier one, only the added text
    /// is parsed; any other change parses it all again.
    public init(_ source: String) {
        self.source = .string(source)
    }

    /// This view in `theme` (a value, not an environment key: `BM-G`).
    public func markdownTheme(_ theme: MarkdownTheme) -> MarkdownView {
        var copy = self
        copy.theme = theme
        return copy
    }

    /// This view with `highlighter` colouring its code blocks; `nil` is plain text. The view compares it by
    /// identity: give it another instance to change the colours.
    public func codeHighlighter(_ highlighter: (any MarkdownCodeHighlighter)?) -> MarkdownView {
        var copy = self
        copy.highlighter = highlighter
        return copy
    }

    /// The document's blocks, in a stack.
    public var content: some ProposalElementGroup {
        let theme = theme, highlighter = highlighter
        let blocks: [MarkdownBlock]
        switch source {
        case .document(let document): blocks = document.blocks
        case .string(let string): blocks = memo.document(for: string).blocks
        }
        return VStack(alignment: .leading, spacing: theme.blockSpacing) {
            ForEach(blocks, id: \.id) { block in
                MarkdownBlockView(block, theme: theme, highlighter: highlighter, depth: 0).equatable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    public static func == (l: MarkdownView, r: MarkdownView) -> Bool {
        guard l.theme == r.theme,
              markdownHighlighterIdentity(l.highlighter) == markdownHighlighterIdentity(r.highlighter)
        else { return false }
        switch (l.source, r.source) {
        case (.document(let a), .document(let b)): return a.identity == b.identity && a.version == b.version
        case (.string(let a), .string(let b)): return a == b
        default: return false
        }
    }
}

/// What a `MarkdownView(String)` remembers between frames: the last source and its document. An idempotent
/// memo (asking twice for one source answers the same), so a retained double build is safe.
final class MarkdownSourceMemo {
    private var source = ""
    private var document = MarkdownDocument()

    /// The document of `string`: the last one appended to when `string` extends the last source, else parsed
    /// anew.
    func document(for string: String) -> MarkdownDocument {
        if string == source { return document }
        let old = source.utf8.count
        if string.utf8.count > old, Self.extends(string, source) {
            document.append(String(decoding: string.utf8.dropFirst(old), as: UTF8.self))
        } else {
            document = MarkdownDocument(parsing: string)
        }
        source = string
        return document
    }

    /// Whether `longer` starts with the bytes of `prefix`; counted as `bytesCompared`.
    private static func extends(_ longer: String, _ prefix: String) -> Bool {
        var a = prefix.utf8.makeIterator(), b = longer.utf8.makeIterator()
        var compared = 0
        defer { MarkdownParseStats.bytesCompared += compared }
        while let x = a.next() {
            compared += 1
            guard let y = b.next(), x == y else { return false }
        }
        return true
    }
}
