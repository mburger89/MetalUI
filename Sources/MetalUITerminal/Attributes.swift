/// A cell colour: the palette default, one of the 256 indexed colours, or truecolour.
public enum TerminalColor: Hashable, Sendable {
    /// The theme's default foreground or background.
    case `default`
    /// An entry of the 256-colour palette (0-15 are the ANSI colours).
    case indexed(UInt8)
    /// A 24-bit colour.
    case rgb(UInt8, UInt8, UInt8)
}

/// How a cell's underline is drawn (SGR 4, with `4:n` sub-parameters, and 21).
public enum TerminalUnderlineStyle: Hashable, Sendable {
    /// No underline.
    case none
    /// A single line (SGR 4, `4:1`).
    case single
    /// A double line (SGR 21, `4:2`).
    case double
    /// A wavy line (`4:3`).
    case curly
    /// A dotted line (`4:4`).
    case dotted
    /// A dashed line (`4:5`).
    case dashed
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
    /// The underline style; `.none` for no underline.
    public var underlineStyle: TerminalUnderlineStyle
    /// The underline colour (SGR 58/59); `.default` draws it in the foreground colour.
    public var underlineColor: TerminalColor
    /// Underline of any style: reading is true for every style but `.none`, writing sets `.single` or `.none`.
    public var underline: Bool {
        get { underlineStyle != .none }
        set { underlineStyle = newValue ? .single : .none }
    }
    /// Blink (SGR 5 and 6).
    public var blink: Bool
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
        underlineStyle = .none
        underlineColor = .default
        blink = false
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
}
