import MetalUICore
import MetalUIMarkdown

/// One block of a Markdown document: a paragraph, heading, list, quote, rule, code block or table, drawn from
/// existing views (`BM-E`).
///
/// A ``MarkdownView`` is a stack of these. Public so an app can put blocks straight into its own lazy stack
/// (`LazyVStack { ForEach(document.blocks, id: \.id) { MarkdownBlockView($0).equatable() } }`): a long reply
/// then windows block by block. It is `Equatable` over the block, the theme and the highlighter's identity,
/// so `.equatable()` skips a block that did not change while a later one streams. Headings are accessibility
/// headings; links open through `\.openURL`; there is no text selection and no copy accessory (`BM-J`).
/// MetalUI-only (SwiftUI has no block Markdown); the parse is cmark-gfm's block structure.
public struct MarkdownBlockView: Component, ProposalElementGroup, @MainActor Equatable {
    var block: MarkdownBlock
    var theme: MarkdownTheme
    var highlighter: (any MarkdownCodeHighlighter)?
    /// How many lists enclose this block: the bullet glyph and the extra indent follow it.
    var depth: Int

    /// A view of `block` in the default theme.
    public init(_ block: MarkdownBlock) {
        self.init(block, theme: MarkdownTheme(), highlighter: nil, depth: 0)
    }

    init(_ block: MarkdownBlock, theme: MarkdownTheme, highlighter: (any MarkdownCodeHighlighter)?, depth: Int) {
        self.block = block
        self.theme = theme
        self.highlighter = highlighter
        self.depth = depth
    }

    /// This view in `theme` (a value, not an environment key: `BM-G`).
    public func markdownTheme(_ theme: MarkdownTheme) -> MarkdownBlockView {
        var copy = self
        copy.theme = theme
        return copy
    }

    /// This view with `highlighter` colouring its code blocks; `nil` is plain text.
    public func codeHighlighter(_ highlighter: (any MarkdownCodeHighlighter)?) -> MarkdownBlockView {
        var copy = self
        copy.highlighter = highlighter
        return copy
    }

    /// The block's views.
    public var content: some ProposalElementGroup {
        VStack(alignment: .leading, spacing: Pixels(0)) {
            switch block.kind {
            case .paragraph(let text):
                MarkdownInlineLowering.text(text, theme: theme, font: theme.bodyFont)
            case .heading(let level, let text):
                MarkdownInlineLowering.text(text, theme: theme, font: theme.headingFont(level))
                    .accessibilityAddTraits(.isHeader)
            case .thematicBreak:
                Divider()
            case .blockQuote(let blocks):
                MarkdownQuote(blocks: blocks, theme: theme, highlighter: highlighter, depth: depth).equatable()
            case .list(let ordered, let start, let tight, let items):
                MarkdownList(ordered: ordered, start: start, tight: tight, items: items, theme: theme,
                             highlighter: highlighter, depth: depth).equatable()
            case .codeBlock(let language, let code, let isClosed):
                MarkdownCodeFence(language: language, code: code, isClosed: isClosed, theme: theme,
                                  highlighter: highlighter).equatable()
            case .table(let alignments, let header, let rows):
                MarkdownTable(alignments: alignments, header: header, rows: rows, theme: theme).equatable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    public static func == (l: MarkdownBlockView, r: MarkdownBlockView) -> Bool {
        l.depth == r.depth && l.block == r.block && l.theme == r.theme
            && markdownHighlighterIdentity(l.highlighter) == markdownHighlighterIdentity(r.highlighter)
    }
}

/// A block quote: its blocks behind a bar (`BM-E`). The bar is a background attachment, so it is proposed
/// the quote's own size and is as tall as the content (a bar inside an `HStack` would be 10 tall).
struct MarkdownQuote: Component, ProposalElementGroup, @MainActor Equatable {
    let blocks: [MarkdownBlock]
    let theme: MarkdownTheme
    let highlighter: (any MarkdownCodeHighlighter)?
    let depth: Int

    var content: some ProposalElementGroup {
        let theme = theme, highlighter = highlighter, depth = depth
        return VStack(alignment: .leading, spacing: theme.blockSpacing) {
            ForEach(blocks, id: \.id) { block in
                MarkdownBlockView(block, theme: theme, highlighter: highlighter, depth: depth).equatable()
            }
        }
        .foregroundColor(theme.quoteForeground)
        .padding(.leading, theme.quoteBarWidth + theme.quotePadding)
        .background(alignment: .leading) {
            theme.quoteBar.frame(width: theme.quoteBarWidth)
        }
    }

    static func == (l: MarkdownQuote, r: MarkdownQuote) -> Bool {
        l.depth == r.depth && l.blocks == r.blocks && l.theme == r.theme
            && markdownHighlighterIdentity(l.highlighter) == markdownHighlighterIdentity(r.highlighter)
    }
}

/// A bullet or ordered list: one equatable row per item, so only the item that streams is built (`BM-E`).
struct MarkdownList: Component, ProposalElementGroup, @MainActor Equatable {
    let ordered: Bool
    let start: Int
    let tight: Bool
    let items: [[MarkdownBlock]]
    let theme: MarkdownTheme
    let highlighter: (any MarkdownCodeHighlighter)?
    let depth: Int

    /// The glyph of a bullet at nesting `depth`.
    static func bullet(depth: Int) -> String {
        ["\u{2022}", "\u{25E6}", "\u{25AA}"][depth % 3]
    }

    var content: some ProposalElementGroup {
        let theme = theme, highlighter = highlighter, depth = depth, tight = tight, ordered = ordered, start = start
        let items = items
        return VStack(alignment: .leading, spacing: tight ? theme.listItemSpacing : theme.blockSpacing) {
            ForEach(Array(items.indices), id: \.self) { index in
                MarkdownListItem(marker: ordered ? "\(start + index)." : Self.bullet(depth: depth),
                                 isBullet: !ordered, blocks: items[index], tight: tight, theme: theme,
                                 highlighter: highlighter, depth: depth + 1).equatable()
            }
        }
        .padding(.leading, depth > 0 ? theme.listIndent : Pixels(0))
    }

    static func == (l: MarkdownList, r: MarkdownList) -> Bool {
        l.depth == r.depth && l.ordered == r.ordered && l.start == r.start && l.tight == r.tight
            && l.items == r.items && l.theme == r.theme
            && markdownHighlighterIdentity(l.highlighter) == markdownHighlighterIdentity(r.highlighter)
    }
}

/// One list item: the marker in a fixed column, first-baseline aligned with the item's first block.
struct MarkdownListItem: Component, ProposalElementGroup, @MainActor Equatable {
    let marker: String
    let isBullet: Bool
    let blocks: [MarkdownBlock]
    let tight: Bool
    let theme: MarkdownTheme
    let highlighter: (any MarkdownCodeHighlighter)?
    /// The depth of the lists inside this item.
    let depth: Int

    var content: some ProposalElementGroup {
        let theme = theme, highlighter = highlighter, depth = depth
        return HStack(alignment: .firstTextBaseline, spacing: theme.listMarkerSpacing) {
            ProposalText(verbatim: marker)
                .font(theme.bodyFont)
                .accessibilityHidden(isBullet)
                .frame(width: theme.listMarkerWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: tight ? theme.listItemSpacing : theme.blockSpacing) {
                ForEach(blocks, id: \.id) { block in
                    MarkdownBlockView(block, theme: theme, highlighter: highlighter, depth: depth).equatable()
                }
            }
        }
    }

    static func == (l: MarkdownListItem, r: MarkdownListItem) -> Bool {
        l.depth == r.depth && l.marker == r.marker && l.isBullet == r.isBullet && l.tight == r.tight
            && l.blocks == r.blocks && l.theme == r.theme
            && markdownHighlighterIdentity(l.highlighter) == markdownHighlighterIdentity(r.highlighter)
    }
}
