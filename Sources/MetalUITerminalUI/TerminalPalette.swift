import MetalUI

/// The colours a ``TerminalView`` draws with (Alloy gap 2, `TRM-BA`): the 16 ANSI colours, the default
/// foreground and background, the cursor, the glyph under a block cursor, the selection, and whether bold
/// brightens ANSI 0-7.
///
/// **The background is opaque.** A damaged row is redrawn over the retained target, so the view draws
/// `background` (and every cell background) with alpha 1 whatever alpha the `Color` carries; there is no glass in
/// v1. **`selection` composites over the selected cells' own backgrounds**, so a translucent colour (alpha about
/// 0.4) keeps the text and the cell colours visible; an opaque one hides only the background. Colours resolve at
/// the view's position (a dynamic colour follows the scheme), and palette indices 16-255 are the fixed xterm cube
/// and greys.
///
/// **`boldIsBright`** (default false): bold is the bold face only, unless set, in which case bold text in ANSI
/// 0-7 draws in 8-15 (`TRM-C` item 7). The view's own `boldIsBright` parameter turns it on too; either does.
public struct TerminalPalette: Sendable, Equatable {
    /// Exactly 16 entries: 0-7 normal, 8-15 bright.
    public var ansi: [Color]
    /// The default foreground.
    public var foreground: Color
    /// The default background (drawn opaque).
    public var background: Color
    /// The cursor's colour: the block's fill, the bar's and underline's stroke, the hollow block's outline.
    public var cursor: Color
    /// The glyph under a filled block cursor.
    public var cursorText: Color
    /// The selection's colour, composited over the selected cells' backgrounds.
    public var selection: Color
    /// Whether bold text in ANSI colours 0-7 uses the bright 8-15 (default false).
    public var boldIsBright: Bool

    /// A palette. Traps unless `ansi` has exactly 16 entries.
    public init(ansi: [Color], foreground: Color, background: Color, cursor: Color, cursorText: Color,
                selection: Color, boldIsBright: Bool = false) {
        precondition(ansi.count == 16, "a terminal palette has exactly 16 ANSI colours (TRM-BA)")
        self.ansi = ansi
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.cursorText = cursorText
        self.selection = selection
        self.boldIsBright = boldIsBright
    }

    /// xterm's default colours: light grey on black, a light cursor, a translucent blue selection.
    public static let xterm = TerminalPalette(
        ansi: [0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd, 0xe5e5e5,
               0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff, 0x00ffff, 0xffffff].map { Color(hex: $0) },
        foreground: Color(hex: 0xe5e5e5), background: Color(hex: 0x000000),
        cursor: Color(hex: 0xe5e5e5), cursorText: Color(hex: 0x000000),
        selection: Color(hex: 0x3366cc).opacity(0.5))
}
