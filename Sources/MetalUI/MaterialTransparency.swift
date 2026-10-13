import MetalUICore
import MetalUILayout

// C27 lane B -- Reduce Transparency for materials (rulings `MT-D`, `MT-F`, `MT-I`;
// spec `docs/superpowers/specs/2026-10-12-material-followups-design.md`). Every
// material site draws through `fillMaterial`, the one chokepoint that reads
// `accessibilityReduceTransparency`: off, it is `fillBackdrop(tint:)` byte for byte
// (`MT-H`); on, it is an ordinary opaque rect and the renderer never sees a backdrop
// record, so it does no split, no blur pass and no frame-target copy (`BB-C`).

extension Material {
    /// The grey this material draws as a plain rect when Reduce Transparency is on
    /// (`MT-F`): the fitted tint of `fill(for:)` at alpha 1, so the panel is the
    /// scheme's material grey (light ultraThin 0.925 ... bar 1.0; dark 0.2248 ...
    /// 0.1779). SwiftUI's own fallback is unmeasured (`MT-A`); this is a ruling,
    /// divergence 315.
    func opaqueColor(in scheme: ColorScheme) -> Color {
        let grey = fill(for: scheme).resolve(in: EnvironmentValues()).red
        return Color(white: Double(grey), opacity: 1)
    }
}

extension Frame {
    /// The colour a material's flat tint draws in at this position: the opaque
    /// grey under Reduce Transparency, else the translucent table tint. What a path
    /// fill (divergence 248's flat branch) and `fillMaterial` resolve.
    func materialTint(_ material: Material) -> Hsla {
        if environmentTop.accessibilityReduceTransparency {
            return resolve(material.opaqueColor(in: colorScheme))
        }
        return resolve(material.color)
    }

    /// Fills `bounds` with `material`: one backdrop record (`BB-A`), or, under Reduce
    /// Transparency, a plain rect of the opaque grey through the ordinary `fill`
    /// (clips, radii, opacity, transforms and shadow scopes compose as for any rect).
    /// A change of the setting snaps -- the colour never goes through the animation
    /// store.
    func fillMaterial(_ bounds: Bounds<Pixels>, material: Material,
                      cornerRadii: Corners<Pixels> = Corners(all: Pixels(0)),
                      shape: PrimitiveShape = .roundedRectangle) {
        if environmentTop.accessibilityReduceTransparency {
            fill(bounds, color: materialTint(material), cornerRadii: cornerRadii, shape: shape)
        } else {
            fillBackdrop(bounds, tint: resolve(material.color), cornerRadii: cornerRadii, shape: shape)
        }
    }
}

extension PaintPass {
    /// ``Frame/fillMaterial(_:material:cornerRadii:shape:)`` at this position.
    func fillMaterial(_ bounds: Bounds<Pixels>, material: Material,
                      cornerRadii: Corners<Pixels> = Corners(all: Pixels(0)),
                      shape: PrimitiveShape = .roundedRectangle) {
        frame.fillMaterial(bounds, material: material, cornerRadii: cornerRadii, shape: shape)
    }

    /// ``Frame/materialTint(_:)`` at this position.
    func materialTint(_ material: Material) -> Hsla { frame.materialTint(material) }
}
