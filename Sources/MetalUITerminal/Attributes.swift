/// A cell colour: the palette default, one of the 256 indexed colours, or truecolour.
public enum TerminalColor: Hashable, Sendable {
    /// The theme's default foreground or background.
    case `default`
    /// An entry of the 256-colour palette (0-15 are the ANSI colours).
    case indexed(UInt8)
    /// A 24-bit colour.
    case rgb(UInt8, UInt8, UInt8)
}

/// The rendition of a run of cells (SGR state plus the OSC 8 hyperlink id).
public struct TerminalAttributes: Hashable, Sendable {
    /// The foreground colour.
    public var foreground: TerminalColor
    /// The background colour.
    public var background: TerminalColor
    /// Bold.
    public var bold: Bool
    /// Dim (faint).
    public var dim: Bool
    /// Italic.
    public var italic: Bool
    /// Underline.
    public var underline: Bool
    /// Strikethrough.
    public var strikethrough: Bool
    /// Inverse video.
    public var inverse: Bool
    /// Hidden (concealed).
    public var hidden: Bool
    /// The OSC 8 hyperlink id, keyed into ``TerminalSnapshot/links``; `nil` for no link.
    public var hyperlink: UInt32?

    /// The default rendition: default colours, no flags, no link.
    public init() {
        foreground = .default
        background = .default
        bold = false
        dim = false
        italic = false
        underline = false
        strikethrough = false
        inverse = false
        hidden = false
        hyperlink = nil
    }
}

/// One cell of a row, produced on demand from the row's compact storage.
public struct TerminalCell: Sendable, Hashable {
    /// The grapheme cluster shown in the cell (a space for a blank cell).
    public let grapheme: Character
    /// The columns the cell covers, 1 or 2.
    public let width: Int
    /// The cell's rendition.
    public let attributes: TerminalAttributes

    init(grapheme: Character, width: Int, attributes: TerminalAttributes) {
        self.grapheme = grapheme
        self.width = width
        self.attributes = attributes
    }
}
