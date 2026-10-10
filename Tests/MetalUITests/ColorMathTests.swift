import Testing
@testable import MetalUI

// C10 lane 1: `ColorMath`, the colour panel's pure arithmetic (rulings
// `LK-C` item 7, `LK-D` items 1, 6; spec §3.1). HSB is sRGB-gamma HSB (the
// components a `Color(.sRGB, …)` literal stores, `CR-`), hue a fraction of a
// turn. No SwiftUI claim: the hex forms and the AX print are MetalUI's rules
// (`LK-D` item 6) and AppKit's `rgb R G B A` format (probe `C1`).

/// The 17 byte values of the grid: 0, 16, …, 240 and 255.
private let gridBytes = Array(stride(from: 0, through: 240, by: 16)) + [255]

/// **1.30.** RGB → HSB → RGB returns every byte triple of a 17³ grid to the
/// same bytes (rounding to the nearest byte, `ColorMath.byte`). Mutation:
/// truncate instead of round in `ColorMath.byte`.
@Test func hsbRoundTripsEveryByteTriple() {
    var failures: [String] = []
    for r in gridBytes {
        for g in gridBytes {
            for b in gridBytes {
                let rgb = ColorMath.RGB(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
                let back = ColorMath.rgb(from: ColorMath.hsb(from: rgb))
                let bytes = [ColorMath.byte(back.red), ColorMath.byte(back.green), ColorMath.byte(back.blue)]
                if bytes != [r, g, b], failures.count < 8 { failures.append("\([r, g, b]) → \(bytes)") }
            }
        }
    }
    #expect(failures.isEmpty, "\(failures)")
}

/// **1.31.** HSB of the primaries and greys, by value: red (0, 1, 1), green
/// (⅓, 1, 1), blue (⅔, 1, 1), a 50% grey (0, 0, 0.5), and `(0.75, 0.5625,
/// 0.5625)` = (0, 0.25, 0.75) — the panel tests' seed. Mutation: brightness
/// from the minimum component.
@Test func hsbOfThePrimariesAndGreys() {
    func hsb(_ r: Double, _ g: Double, _ b: Double) -> [Double] {
        let value = ColorMath.hsb(from: ColorMath.RGB(red: r, green: g, blue: b))
        return [value.hue, value.saturation, value.brightness]
    }
    #expect(hsb(1, 0, 0) == [0, 1, 1])
    #expect(hsb(0, 1, 0) == [1.0 / 3, 1, 1])
    #expect(hsb(0, 0, 1) == [2.0 / 3, 1, 1])
    #expect(hsb(0.5, 0.5, 0.5) == [0, 0, 0.5])
    #expect(hsb(0.75, 0.5625, 0.5625) == [0, 0.25, 0.75])
}

/// **1.32.** The hex forms (`LK-D` item 6): `#RRGGBB`, `RRGGBB`, `#RGB`, and
/// with alpha allowed `#RRGGBBAA`; case-insensitive, surrounding spaces
/// trimmed; anything else `nil`, and `#RRGGBBAA` `nil` without alpha.
/// Mutation: accept a 5-digit string.
@Test func parseHexAcceptsTheFourFormsAndNothingElse() {
    let orange = ColorMath.RGBA(red: 1, green: 128.0 / 255, blue: 0, opacity: 1)
    #expect(ColorMath.parseHex("#FF8000", allowsAlpha: false) == orange)
    #expect(ColorMath.parseHex("ff8000", allowsAlpha: false) == orange)
    #expect(ColorMath.parseHex(" #ff8000 ", allowsAlpha: false) == orange)
    #expect(ColorMath.parseHex("#F80", allowsAlpha: false)
            == ColorMath.RGBA(red: 1, green: 136.0 / 255, blue: 0, opacity: 1))
    #expect(ColorMath.parseHex("#FF800080", allowsAlpha: true)
            == ColorMath.RGBA(red: 1, green: 128.0 / 255, blue: 0, opacity: 128.0 / 255))
    #expect(ColorMath.parseHex("#FF800080", allowsAlpha: false) == nil)
    for bad in ["", "#", "#12345", "12345", "#1234", "#GG0000", "#FF80000", "##FF8000", "#FF 8000", "#FF8000801"] {
        #expect(ColorMath.parseHex(bad, allowsAlpha: true) == nil, "\(bad) must not parse")
    }
}

/// **1.33.** The field's text (`LK-D` item 6): `#RRGGBB` uppercase, `#RRGGBBAA`
/// when the alpha is asked for; components rounded to the nearest byte (0.5 →
/// 0x80). Mutation: lowercase.
@Test func hexStringIsUppercaseRoundedAndCarriesAlphaOnlyWhenAsked() {
    let colour = ColorMath.RGBA(red: 1, green: 0.5, blue: 0, opacity: 0.5)
    #expect(ColorMath.hexString(colour, includesAlpha: false) == "#FF8000")
    #expect(ColorMath.hexString(colour, includesAlpha: true) == "#FF800080")
    #expect(ColorMath.hexString(ColorMath.RGBA(red: 0.2, green: 0.4, blue: 0.6, opacity: 1), includesAlpha: false)
            == "#336699")
}

/// **1.34.** The well's accessibility value (probe `C1`, `LK-C` item 7):
/// `rgb R G B A`, each component its shortest decimal with at most three
/// places — `rgb 1 0 0 1`, `rgb 0.2 0.4 0.6 0.5` for Float-stored components,
/// `0.333` for a third. Mutation: print `%.3f`.
@Test func axComponentsPrintLikeAppKit() {
    #expect(ColorMath.axComponents(ColorMath.RGBA(red: 1, green: 0, blue: 0, opacity: 1)) == "rgb 1 0 0 1")
    #expect(ColorMath.axComponents(ColorMath.RGBA(red: Double(Float(0.2)), green: Double(Float(0.4)),
                                                  blue: Double(Float(0.6)), opacity: 0.5))
            == "rgb 0.2 0.4 0.6 0.5")
    #expect(ColorMath.axComponents(ColorMath.RGBA(red: 1.0 / 3, green: 0.0625, blue: 0.9999, opacity: 1))
            == "rgb 0.333 0.063 1 1")
}
