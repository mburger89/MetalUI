import Foundation

/// The colour panel's pure arithmetic (C10 lane 1, rulings `LK-C` item 7,
/// `LK-D` items 1, 6; spec `2026-10-08-controls-looks-design.md` §3.1).
///
/// **Gamma-sRGB HSB**: the components are the ones a `Color(.sRGB, …)`
/// literal stores (`CR-`, divergence 1), hue a fraction of a turn (0…1, not
/// degrees), so `rgb(from:)` is `Color(hue:saturation:brightness:)`'s
/// conversion and the panel never leaves 0…1. Nothing here is a SwiftUI
/// claim: the hex forms are MetalUI's rule (`LK-D` item 6) and the AX print is
/// AppKit's `rgb R G B A` (probe `C1`).
enum ColorMath {
    /// Gamma-sRGB components, 0…1.
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// Gamma-sRGB components and an opacity, 0…1.
    struct RGBA: Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var opacity: Double

        /// The colour without its opacity.
        var rgb: RGB { RGB(red: red, green: green, blue: blue) }
    }

    /// Hue (a fraction of a turn, 0..<1), saturation and brightness, 0…1.
    struct HSB: Equatable {
        var hue: Double
        var saturation: Double
        var brightness: Double
    }

    /// HSB of `rgb`: brightness the largest component, saturation the spread
    /// over it (0 for black), hue the hexcone angle (0 for a grey).
    static func hsb(from rgb: RGB) -> HSB {
        let r = clamp(rgb.red), g = clamp(rgb.green), b = clamp(rgb.blue)
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        let saturation = maxC > 0 ? delta / maxC : 0
        guard delta > 0 else { return HSB(hue: 0, saturation: saturation, brightness: maxC) }
        var sector: Double
        if maxC == r {
            sector = (g - b) / delta
            if sector < 0 { sector += 6 }
        } else if maxC == g {
            sector = (b - r) / delta + 2
        } else {
            sector = (r - g) / delta + 4
        }
        let hue = sector / 6
        return HSB(hue: hue >= 1 ? hue - 1 : hue, saturation: saturation, brightness: maxC)
    }

    /// The sRGB components of `hsb` — `Color(hue:saturation:brightness:)`'s
    /// hexcone conversion, the hue taken modulo one turn.
    static func rgb(from hsb: HSB) -> RGB {
        let turn = hsb.hue.isFinite ? hsb.hue - hsb.hue.rounded(.down) : 0
        let h = turn * 6
        let s = clamp(hsb.saturation), v = clamp(hsb.brightness)
        let chroma = v * s
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - chroma
        let (r, g, b): (Double, Double, Double) =
            switch h {
            case ..<1: (chroma, x, 0)
            case ..<2: (x, chroma, 0)
            case ..<3: (0, chroma, x)
            case ..<4: (0, x, chroma)
            case ..<5: (x, 0, chroma)
            default:   (chroma, 0, x)
            }
        return RGB(red: r + m, green: g + m, blue: b + m)
    }

    /// A component as its nearest byte, 0…255.
    static func byte(_ value: Double) -> Int {
        Int((clamp(value) * 255).rounded())
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when `includesAlpha`, uppercase (`LK-D` item 6).
    static func hexString(_ color: RGBA, includesAlpha: Bool) -> String {
        var bytes = [byte(color.red), byte(color.green), byte(color.blue)]
        if includesAlpha { bytes.append(byte(color.opacity)) }
        return "#" + bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// `text` as a colour (`LK-D` item 6): `#RRGGBB`, `RRGGBB`, `#RGB` (each
    /// digit doubled) and, when `allowsAlpha`, `#RRGGBBAA`; hex digits in
    /// either case, surrounding whitespace trimmed. Anything else is `nil`.
    static func parseHex(_ text: String, allowsAlpha: Bool) -> RGBA? {
        var digits = Substring(text.trimmingCharacters(in: .whitespaces))
        if digits.first == "#" { digits = digits.dropFirst() }
        let values = digits.compactMap { $0.isASCII ? $0.hexDigitValue : nil }
        guard values.count == digits.count else { return nil }
        let expanded: [Int]
        switch values.count {
        case 3: expanded = values.flatMap { [$0, $0] }
        case 6: expanded = values
        case 8 where allowsAlpha: expanded = values
        default: return nil
        }
        let bytes = stride(from: 0, to: expanded.count, by: 2).map {
            Double(expanded[$0] * 16 + expanded[$0 + 1]) / 255
        }
        return RGBA(red: bytes[0], green: bytes[1], blue: bytes[2], opacity: bytes.count == 4 ? bytes[3] : 1)
    }

    /// The well's accessibility value, `rgb R G B A`, each component printed as
    /// AppKit prints it (probe `C1`: `rgb 1 0 0 1`) — its shortest decimal, at
    /// most three places.
    static func axComponents(_ color: RGBA) -> String {
        "rgb " + [color.red, color.green, color.blue, color.opacity].map(axNumber).joined(separator: " ")
    }

    /// `value` rounded to three places, trailing zeros and a bare point dropped.
    static func axNumber(_ value: Double) -> String {
        let thousandths = Int((clamp(value) * 1000).rounded())
        guard thousandths % 1000 != 0 else { return String(thousandths / 1000) }
        var fraction = String(format: "%03d", thousandths % 1000)
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return "\(thousandths / 1000).\(fraction)"
    }

    /// `value` clamped to 0…1, NaN to 0.
    static func clamp(_ value: Double) -> Double { value.isNaN ? 0 : min(max(value, 0), 1) }
}
