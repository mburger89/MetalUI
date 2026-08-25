/// Gamma-encoded sRGB, expressed as HSLA. Hue is normalised to 0..<1.
/// The compositor works in this space directly (spec §7.8) — do not linearize.
public struct Hsla: Hashable, Sendable {
    public var h: Float
    public var s: Float
    public var l: Float
    public var a: Float
    public init(h: Float, s: Float, l: Float, a: Float = 1) {
        self.h = h; self.s = s; self.l = l; self.a = a
    }

    public static let white = Hsla(h: 0, s: 0, l: 1, a: 1)
    public static let black = Hsla(h: 0, s: 0, l: 0, a: 1)
    public static let transparent = Hsla(h: 0, s: 0, l: 0, a: 0)

    public static func rgb(_ hex: UInt32, alpha: Float = 1) -> Hsla {
        Rgba(r: Float((hex >> 16) & 0xFF) / 255,
             g: Float((hex >> 8) & 0xFF) / 255,
             b: Float(hex & 0xFF) / 255,
             a: alpha).toHsla()
    }

    public func toRgba() -> Rgba {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Float, Float, Float) =
            switch hp {
            case ..<1: (c, x, 0)
            case ..<2: (x, c, 0)
            case ..<3: (0, c, x)
            case ..<4: (0, x, c)
            case ..<5: (x, 0, c)
            default:   (c, 0, x)
            }
        return Rgba(r: r + m, g: g + m, b: b + m, a: a)
    }
}

/// Gamma-encoded sRGB components in 0...1.
public struct Rgba: Hashable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float
    public init(r: Float, g: Float, b: Float, a: Float = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public func toHsla() -> Hsla {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        let l = (maxC + minC) / 2

        guard delta > 0 else { return Hsla(h: 0, s: 0, l: l, a: a) }

        let s = delta / (1 - abs(2 * l - 1))
        var h: Float
        if maxC == r {
            h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        h /= 6
        if h < 0 { h += 1 }
        return Hsla(h: h, s: s, l: l, a: a)
    }
}
