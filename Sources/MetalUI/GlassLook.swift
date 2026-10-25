import MetalUICore
import MetalUILayout

// Liquid Glass's look, as numbers (rulings `LG-C`, `LG-D`, `LG-E`, `LG-F`, `LG-U`): the one table the record, the
// flat fallback and Reduce Transparency read, as `Material.fill(for:)` is for materials. Everything the shaders
// need is resolved here on the CPU, so a shader reads numbers and never a scheme (`LG-D` 3).

/// The glass's tint table and the lens, rim and press constants. **Non-public** (guard `GlassCompileGuards`).
enum GlassLook {
    /// The base tint `T` of a variant in a scheme: a gamma grey at an alpha (`LG-C`, from probe W2 over a black,
    /// a grey 142 and a white backdrop; `out = T.a·T + (1 − T.a)·B`).
    ///
    /// regular light: I 139, s 0.40 → grey 0.908 at 0.60; clear light: I 71, s 0.68 → 0.870 at 0.32; clear dark:
    /// I 25, s 0.71 → 0.338 at 0.29. **Regular dark is not affine** (SwiftUI's chord misses the grey point by
    /// 24/255): the table holds the minimax line through the three readings (19, 132, 169 at backdrop 0, 142, 255),
    /// slope 0.588 and intercept 33.75/255, so grey 0.321 at alpha 0.412, off by at most 14.8/255 (divergence 825,
    /// `LG-U` 3). `.identity` has no tint (it draws nothing).
    static func base(_ variant: Glass.Variant, scheme: ColorScheme) -> Hsla {
        let (grey, alpha): (Float, Float)
        switch (variant, scheme == .dark) {
        case (.regular, false): (grey, alpha) = (0.908, 0.60)
        case (.clear, false): (grey, alpha) = (0.870, 0.32)
        case (.clear, true): (grey, alpha) = (0.338, 0.29)
        case (.regular, true): (grey, alpha) = (0.321, 0.412)
        case (.identity, _): (grey, alpha) = (0, 0)
        }
        return Hsla(h: 0, s: 0, l: grey, a: alpha)
    }

    /// `tint` composited source-over on `base`, both straight alpha (`LG-E`): the one tint a record carries.
    static func composited(_ tint: Hsla?, over base: Hsla) -> Hsla {
        guard let tint, tint.a > 0 else { return base }
        let t = tint.toRgba(), b = base.toRgba()
        let alpha = t.a + b.a * (1 - t.a)
        guard alpha > 0 else { return Hsla(h: 0, s: 0, l: 0, a: 0) }
        func channel(_ top: Float, _ under: Float) -> Float { (top * t.a + under * b.a * (1 - t.a)) / alpha }
        return Rgba(r: channel(t.r, b.r), g: channel(t.g, b.g), b: channel(t.b, b.b), a: alpha).toHsla()
    }

    /// The record's tint: the variant's base with the glass's tint source-over on it.
    static func tint(_ glass: Glass, scheme: ColorScheme, resolve: (Color) -> Hsla) -> Hsla {
        composited(glass.tintColor.map(resolve), over: base(glass.variant, scheme: scheme))
    }

    /// The grey a glass draws as under Reduce Transparency (`LG-F`): the record's tint at alpha 1, the tint
    /// source-over already folded in. SwiftUI's own fallback is unmeasured, so this is a ruling.
    static func opaque(_ glass: Glass, scheme: ColorScheme, resolve: (Color) -> Hsla) -> Hsla {
        var color = tint(glass, scheme: scheme, resolve: resolve)
        color.a = 1
        return color
    }

    /// The lens band's width in points (`LG-D` 2): `min(0.5 · shortest side, 12)`.
    static func band(shortestSide: Float) -> Float { min(0.5 * shortestSide, 12) }

    /// How far the lens bends the backdrop at the edge, as a fraction of the band: half of it, so at most 6 pt.
    static let lensDepthOfBand: Float = 0.5

    /// The rim's alpha at the edge (white over the result), light and dark (`LG-D` 2).
    static func rimStrength(dark: Bool) -> Float { dark ? 0.30 : 0.45 }

    /// The white lift of a pressed interactive glass, as the alpha at press 1 (`LG-J`).
    static let pressLift: Float = 0.12
}
