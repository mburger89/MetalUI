import MetalUICore
import MetalUITerminal

/// An opaque 8-bit sRGB colour.
package struct TerminalRGB: Hashable, Sendable {
    package var r: UInt8
    package var g: UInt8
    package var b: UInt8

    package init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// From `0xRRGGBB`.
    package init(hex: UInt32) {
        self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
    }

    /// The colour as the renderer's `Hsla`, with `alpha`.
    package func hsla(alpha: Float = 1) -> Hsla {
        Rgba(r: Float(r) / 255, g: Float(g) / 255, b: Float(b) / 255, a: alpha).toHsla()
    }

    /// `self` moved `fraction` of the way to `other`, per channel, rounded to nearest.
    package func mixed(with other: TerminalRGB, fraction: Double) -> TerminalRGB {
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8(max(0, min(255, (Double(a) + (Double(b) - Double(a)) * fraction).rounded())))
        }
        return TerminalRGB(mix(r, other.r), mix(g, other.g), mix(b, other.b))
    }
}

/// How a cell's rendition becomes colours (`TRM-AZ`): the 16 ANSI colours, the default foreground and
/// background, and the `boldIsBright` flag (`TRM-C` item 7). Palette indices 16-231 are the xterm 6 x 6 x 6 cube
/// (levels 0, 95, 135, 175, 215, 255) and 232-255 the 24 greys (`8 + 10 i`); truecolour is itself.
///
/// `package`: the public `TerminalPalette` of the view (Phase 5.3, `Color`-valued) resolves into one of these.
package struct TerminalColorScheme: Equatable, Sendable {
    /// Exactly 16 entries: 0-7 normal, 8-15 bright.
    package var ansi: [TerminalRGB]
    /// The default foreground.
    package var foreground: TerminalRGB
    /// The default background.
    package var background: TerminalRGB
    /// Whether bold text in ANSI colours 0-7 uses the bright 8-15 (default false: bold is the bold face only).
    package var boldIsBright: Bool

    package init(ansi: [TerminalRGB], foreground: TerminalRGB, background: TerminalRGB, boldIsBright: Bool = false) {
        precondition(ansi.count == 16, "a terminal scheme has exactly 16 ANSI colours")
        self.ansi = ansi
        self.foreground = foreground
        self.background = background
        self.boldIsBright = boldIsBright
    }

    /// xterm's default colours on black.
    package static let xterm = TerminalColorScheme(
        ansi: [0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd, 0xe5e5e5,
               0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff, 0x00ffff, 0xffffff].map(TerminalRGB.init(hex:)),
        foreground: TerminalRGB(hex: 0xe5e5e5), background: TerminalRGB(hex: 0x000000))

    private static let cubeLevels: [UInt8] = [0, 95, 135, 175, 215, 255]

    /// The colour of palette entry `index`.
    package func indexed(_ index: UInt8) -> TerminalRGB {
        let i = Int(index)
        if i < 16 { return ansi[i] }
        if i < 232 {
            let n = i - 16
            return TerminalRGB(Self.cubeLevels[n / 36], Self.cubeLevels[(n / 6) % 6], Self.cubeLevels[n % 6])
        }
        let grey = UInt8(8 + 10 * (i - 232))
        return TerminalRGB(grey, grey, grey)
    }

    /// What a cell draws with.
    package struct Resolved: Equatable, Sendable {
        /// The glyph colour (already dimmed and inverted).
        package var foreground: TerminalRGB
        /// The cell's background.
        package var background: TerminalRGB
        /// True when the glyph is not drawn (SGR 8); the background still is.
        package var hidden: Bool
        /// The underline colour (SGR 58, else the glyph colour).
        package var underline: TerminalRGB
    }

    /// The colours of a cell with `attributes`, in order: bold-as-bright (when the flag is on and the foreground
    /// is ANSI 0-7), inverse swaps foreground and background (the defaults too), dim mixes the foreground half
    /// way to the background, hidden keeps the background and drops the glyph.
    package func resolve(_ attributes: TerminalAttributes) -> Resolved {
        var fgColor = attributes.foreground
        if boldIsBright, attributes.bold, case .indexed(let i) = fgColor, i < 8 { fgColor = .indexed(i + 8) }
        var fg = rgb(fgColor, default: foreground)
        var bg = rgb(attributes.background, default: background)
        if attributes.inverse { swap(&fg, &bg) }
        if attributes.dim { fg = fg.mixed(with: bg, fraction: 0.5) }
        let underline: TerminalRGB
        if case .default = attributes.underlineColor { underline = fg } else {
            underline = rgb(attributes.underlineColor, default: fg)
        }
        return Resolved(foreground: fg, background: bg, hidden: attributes.hidden, underline: underline)
    }

    private func rgb(_ color: TerminalColor, default fallback: TerminalRGB) -> TerminalRGB {
        switch color {
        case .default: fallback
        case .indexed(let i): indexed(i)
        case .rgb(let r, let g, let b): TerminalRGB(r, g, b)
        }
    }
}
