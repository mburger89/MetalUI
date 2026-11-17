import MetalUIScene
import MetalUITerminal
import MetalUITextSystem
import Testing
@testable import MetalUITerminalUI
#if os(macOS)
import MetalUIText
#endif

// Terminal phase 5.2 (`TRM-AZ`...): cell metrics and the palette. Portable.

/// **1** (`TRM-AZ` item 1). Cell metrics are whole device pixels measured once at the scale, and the two scales
/// agree to the pixel: the cell at scale 2 is within one pixel of twice the cell at scale 1 in each dimension
/// (`round(2x)` against `2 round(x)`), the baseline and decorations stay inside the cell, the underline is below
/// the baseline, and the thickness is at least one pixel. Mutation: truncate instead of round, ignore the scale.
@Test @MainActor func cellMetricsAreWholePixelsThatAgreeAcrossScales() {
    let system = portableSystem()
    let font = system.resolveFont(family: nil, size: 14)
    let one = TerminalCellMetrics.measure(font, in: system, scale: 1)
    let two = TerminalCellMetrics.measure(font, in: system, scale: 2)
    let advance = system.measure("M", font: font, wrappingAt: nil).widestLine
    let line = system.fontMetrics(font).lineHeight
    #expect(one.cellWidth == Int(advance.rounded()), "the advance of M, rounded to nearest")
    #expect(two.cellWidth == Int((advance * 2).rounded()))
    #expect(one.cellHeight == Int(line.rounded()) && two.cellHeight == Int((line * 2).rounded()))
    #expect(abs(two.cellWidth - 2 * one.cellWidth) <= 1 && abs(two.cellHeight - 2 * one.cellHeight) <= 1)
    for m in [one, two] {
        #expect(m.cellWidth >= 1 && m.cellHeight >= 1)
        #expect(m.baseline >= 1 && m.baseline <= m.cellHeight)
        #expect(m.underlineThickness >= 1)
        #expect(m.underlineTop > m.baseline - 1 && m.underlineTop + m.underlineThickness <= m.cellHeight)
        #expect(m.strikeTop >= 0 && m.strikeTop + m.underlineThickness <= m.cellHeight)
        #expect(m.strikeTop < m.baseline, "the strikethrough is above the baseline")
    }
    #expect(two.underlineThickness >= one.underlineThickness)
}

/// **2** (`TRM-AZ` item 1, Noto Sans 14 pt, the portable system). The literal cell sizes at both scales, so a
/// change of the rounding rule or the line height reads red on every platform.
@Test @MainActor func theNotoCellAtBothScalesIsPinned() {
    let system = portableSystem()
    let font = system.resolveFont(family: nil, size: 14)
    let one = TerminalCellMetrics.measure(font, in: system, scale: 1)
    let two = TerminalCellMetrics.measure(font, in: system, scale: 2)
    #expect([one.cellWidth, one.cellHeight] == [13, 20], "scale 1: \(one)")
    #expect([two.cellWidth, two.cellHeight] == [25, 40], "scale 2: \(two)")
}

#if os(macOS)
/// **3** (`TRM-AZ` item 1). Menlo through CoreText: monospace, so the advance of "M" is every ASCII glyph's
/// advance, and the metrics are stable across the two scales.
@Test @MainActor func aMonospaceFaceGivesOneCellForEveryAsciiGlyph() {
    let system = CoreTextTextSystem()
    let font = system.resolveFont(family: "Menlo", size: 13)
    let m1 = TerminalCellMetrics.measure(font, in: system, scale: 1)
    let m2 = TerminalCellMetrics.measure(font, in: system, scale: 2)
    #expect(abs(m2.cellWidth - 2 * m1.cellWidth) <= 1 && abs(m2.cellHeight - 2 * m1.cellHeight) <= 1)
    for text in ["i", "W", "0", "~", "M"] {
        let advance = system.measure(text, font: font, wrappingAt: nil).widestLine
        #expect(Int((advance * 2).rounded()) == m2.cellWidth, "\(text) is as wide as M")
    }
    #expect(m1.cellWidth == 8 && m1.cellHeight == 16, "Menlo 13 pt at scale 1: \(m1)")
}
#endif

// MARK: Palette

private func attributes(fg: TerminalColor = .default, bg: TerminalColor = .default, bold: Bool = false, dim: Bool = false,
                        inverse: Bool = false, hidden: Bool = false) -> TerminalAttributes {
    var a = TerminalAttributes()
    a.foreground = fg
    a.background = bg
    a.bold = bold
    a.dim = dim
    a.inverse = inverse
    a.hidden = hidden
    return a
}

/// **4** (`TRM-AZ` item 5). The palette table: the 16 ANSI entries, the 6 x 6 x 6 cube (levels 0, 95, 135, 175,
/// 215, 255), the 24 greys (`8 + 10 i`) and truecolour. Mutation: a cube level off by one, grey step 11.
@Test func theIndexedColoursAreTheXtermTable() {
    let s = TerminalColorScheme.xterm
    #expect(s.indexed(1) == TerminalRGB(hex: 0xcd0000) && s.indexed(15) == TerminalRGB(hex: 0xffffff))
    #expect(s.indexed(16) == TerminalRGB(0, 0, 0))
    #expect(s.indexed(17) == TerminalRGB(0, 0, 95))
    #expect(s.indexed(21) == TerminalRGB(0, 0, 255))
    #expect(s.indexed(46) == TerminalRGB(0, 255, 0))
    #expect(s.indexed(196) == TerminalRGB(255, 0, 0))
    #expect(s.indexed(110) == TerminalRGB(135, 175, 215))
    #expect(s.indexed(231) == TerminalRGB(255, 255, 255))
    #expect(s.indexed(232) == TerminalRGB(8, 8, 8))
    #expect(s.indexed(244) == TerminalRGB(128, 128, 128))
    #expect(s.indexed(255) == TerminalRGB(238, 238, 238))
    var seen = Set<TerminalRGB>()
    for i in 16...231 { seen.insert(s.indexed(UInt8(i))) }
    #expect(seen.count == 216, "every cube entry is distinct")
}

/// **5** (`TRM-AZ` item 5, `TRM-C` item 7). Bold-as-bright: off by default (bold is the bold face only), on it
/// moves ANSI 0-7 to 8-15 and nothing else (not the default colour, not 8-15, not a cube entry, not truecolour).
@Test func boldIsBrightMovesOnlyTheLowAnsiColoursAndOnlyWhenOn() {
    var s = TerminalColorScheme.xterm
    let red = attributes(fg: .indexed(1), bold: true)
    #expect(s.resolve(red).foreground == s.ansi[1], "off: bold keeps the colour")
    s.boldIsBright = true
    #expect(s.resolve(red).foreground == s.ansi[9], "on: ANSI 1 becomes 9")
    #expect(s.resolve(attributes(fg: .indexed(1))).foreground == s.ansi[1], "not bold: unchanged")
    #expect(s.resolve(attributes(fg: .indexed(9), bold: true)).foreground == s.ansi[9])
    #expect(s.resolve(attributes(fg: .indexed(100), bold: true)).foreground == s.indexed(100))
    #expect(s.resolve(attributes(fg: .rgb(1, 2, 3), bold: true)).foreground == TerminalRGB(1, 2, 3))
    #expect(s.resolve(attributes(bold: true)).foreground == s.foreground, "the default foreground is not brightened")
}

/// **6** (`TRM-AZ` item 5). Inverse swaps the two (the defaults too), dim mixes the foreground half way to the
/// background, hidden keeps the background and marks the glyph hidden, and the underline colour follows SGR 58
/// or the final glyph colour. Mutation: dim before inverse; hidden drops the background.
@Test func inverseDimAndHiddenResolveInOrder() {
    let s = TerminalColorScheme.xterm
    let plain = s.resolve(attributes())
    #expect(plain.foreground == s.foreground && plain.background == s.background && !plain.hidden)
    let inverse = s.resolve(attributes(inverse: true))
    #expect(inverse.foreground == s.background && inverse.background == s.foreground)
    let both = s.resolve(attributes(fg: .rgb(200, 100, 0), bg: .rgb(0, 100, 200), inverse: true))
    #expect(both.foreground == TerminalRGB(0, 100, 200) && both.background == TerminalRGB(200, 100, 0))
    let dim = s.resolve(attributes(fg: .rgb(200, 100, 0), bg: .rgb(0, 0, 0), dim: true))
    #expect(dim.foreground == TerminalRGB(100, 50, 0), "half way to the background")
    let dimInverse = s.resolve(attributes(fg: .rgb(200, 100, 0), bg: .rgb(0, 0, 100), dim: true, inverse: true))
    #expect(dimInverse.foreground == TerminalRGB(0, 0, 100).mixed(with: TerminalRGB(200, 100, 0), fraction: 0.5),
            "dim applies to the inverted foreground, towards the inverted background")
    let hidden = s.resolve(attributes(fg: .indexed(2), bg: .indexed(4), hidden: true))
    #expect(hidden.hidden && hidden.background == s.ansi[4])
    var underlined = attributes(fg: .indexed(2))
    #expect(s.resolve(underlined).underline == s.ansi[2], "the underline follows the glyph")
    underlined.underlineColor = .rgb(9, 8, 7)
    #expect(s.resolve(underlined).underline == TerminalRGB(9, 8, 7))
}

/// **7** (`TRM-AZ` item 5). Greys and primaries convert to the renderer's colour exactly (so a pixel test can
/// compare bytes): white, black, mid grey and the primaries round-trip through `Hsla`.
@Test func theRendererColourOfAGreyIsExact() {
    #expect(TerminalRGB(0, 0, 0).hsla().l == 0 && TerminalRGB(255, 255, 255).hsla().l == 1)
    let grey = TerminalRGB(128, 128, 128).hsla()
    #expect(grey.s == 0 && abs(grey.l - 128.0 / 255) < 1e-6)
    let red = TerminalRGB(255, 0, 0).hsla()
    #expect(red.h == 0 && red.s == 1 && red.l == 0.5)
}
