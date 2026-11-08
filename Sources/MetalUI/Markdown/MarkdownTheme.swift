import MetalUICore

/// What a soft line break inside a paragraph shows (`BM-E`).
///
/// A soft break is a newline in the source that does not end the paragraph. CommonMark and Foundation read it
/// as a space; a chat transcript often wants the line kept.
public enum MarkdownSoftBreak: Hashable, Sendable {
    /// A soft break is a space (the default).
    case space
    /// A soft break is a line break.
    case lineBreak
}

/// How a ``MarkdownView`` or ``MarkdownBlockView`` looks: fonts, colours and spacing, as a plain value.
///
/// A theme is applied with ``MarkdownView/markdownTheme(_:)`` and travels as a stored value on the view, not as
/// an environment key: a subtree under a custom environment key cannot be replayed from a retained record
/// (`SB-`), and a transcript of settled replies must be. `==` over the whole theme is what lets an
/// `.equatable()` block be skipped. MetalUI-only (SwiftUI has no block Markdown); the defaults follow the
/// semantic colours, so a theme needs no change for dark mode.
public struct MarkdownTheme: Equatable, Sendable {
    /// The font of paragraphs, list items and table cells.
    public var bodyFont: Font
    /// The fonts of heading levels 1 through 6, in that order; a level past the end takes the last.
    public var headingFonts: [Font]
    /// The font of code blocks (fenced and indented).
    public var codeFont: Font
    /// The background behind an inline `code` span.
    public var inlineCodeBackground: Color
    /// The fill of a code block's box.
    public var codeBlockBackground: Color
    /// The glyph colour of code that no highlighter run colours; `nil` keeps the inherited foreground.
    public var codeForeground: Color?
    /// The corner radius of a code block's box.
    public var codeBlockCornerRadius: Pixels
    /// The padding between a code block's box and its code.
    public var codeBlockPadding: Pixels
    /// Whether a code block's long lines wrap at the block's width. `true` is the default: `false` keeps every
    /// line whole inside a horizontal scroller. A vertical wheel over that scroller passes to the transcript around it
    /// (a one-axis scroller scrolls only the axis it declares, `XS-F`), a horizontal wheel scrolls the block. Wrapping stays
    /// the default (`BM-H`): a streaming reply keeps a long line's tail visible.
    public var codeWraps: Bool
    /// Whether a fence's language name is shown above its code.
    public var showsCodeLanguage: Bool
    /// Whether each code block shows a small copy button at its top trailing corner (`BM-K`). `false` is the
    /// default. Pressing it writes the block's whole code, as plain text, to the window's clipboard
    /// (``EnvironmentValues/clipboard``). The button is an overlay: it changes neither the block's size nor the
    /// shaping of its text, and a block nested in a list or a quote has one too.
    public var showsCodeCopyButton: Bool
    /// The font of a code block's language caption.
    public var codeCaptionFont: Font
    /// The space between two sibling blocks (and between two items of a loose list).
    public var blockSpacing: Pixels
    /// The space between two items of a tight list, and between the blocks of a tight item.
    public var listItemSpacing: Pixels
    /// The extra leading space of a list nested in a list item, per level.
    public var listIndent: Pixels
    /// The width of the column that holds a list item's marker (`•`, `1.`); markers are right-aligned in it.
    public var listMarkerWidth: Pixels
    /// The space between a list item's marker column and its content.
    public var listMarkerSpacing: Pixels
    /// The colour of a block quote's bar.
    public var quoteBar: Color
    /// The width of a block quote's bar.
    public var quoteBarWidth: Pixels
    /// The space between a block quote's bar and its content.
    public var quotePadding: Pixels
    /// The glyph colour inside a block quote; `nil` keeps the inherited foreground.
    public var quoteForeground: Color?
    /// The colour of the rules between a table's rows.
    public var tableRule: Color
    /// Whether a table scrolls sideways when it is wider than its block. `false` is the default, for the reason
    /// ``codeWraps`` is true (a table that does not scroll wraps its cells' text). A vertical wheel over a scrolling table
    /// passes to the transcript (`XS-F`).
    public var tableScrolls: Bool
    /// The space between a table's columns.
    public var tableColumnSpacing: Pixels
    /// The space between a table's rows.
    public var tableRowSpacing: Pixels
    /// What a soft line break shows.
    public var softBreak: MarkdownSoftBreak

    /// The default theme.
    public init() {
        bodyFont = .body
        headingFonts = [Font.title.bold(), Font.title2.bold(), Font.title3.bold(), .headline, Font.subheadline.bold(),
                        Font.subheadline.bold()]
        codeFont = .system(.callout, design: .monospaced)
        inlineCodeBackground = .surfaceSecondary
        codeBlockBackground = .surfaceSecondary
        codeForeground = nil
        codeBlockCornerRadius = Pixels(8)
        codeBlockPadding = Pixels(10)
        codeWraps = true
        showsCodeLanguage = true
        showsCodeCopyButton = false
        codeCaptionFont = .caption
        blockSpacing = Pixels(10)
        listItemSpacing = Pixels(3)
        listIndent = Pixels(4)
        listMarkerWidth = Pixels(18)
        listMarkerSpacing = Pixels(4)
        quoteBar = Color.secondary.opacity(0.5)
        quoteBarWidth = Pixels(3)
        quotePadding = Pixels(10)
        quoteForeground = .secondary
        tableRule = .separator
        tableScrolls = false
        tableColumnSpacing = Pixels(16)
        tableRowSpacing = Pixels(6)
        softBreak = .space
    }

    /// The font of a heading of `level` (1 through 6; others clamp).
    func headingFont(_ level: Int) -> Font {
        guard !headingFonts.isEmpty else { return bodyFont }
        return headingFonts[min(max(level, 1), headingFonts.count) - 1]
    }
}
