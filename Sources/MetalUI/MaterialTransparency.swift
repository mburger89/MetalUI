import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIScene
import MetalUIShaderTypes

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

// MARK: - Liquid Glass (`LG-F`, `LG-I`, `LG-L`)
//
// `fillGlass` is `fillMaterial`'s sibling and the **one home of a glass-tailed `fillBackdrop`** (guard
// `everyGlassEmissionSiteGoesThroughFillGlass`): off, it is one backdrop record with a glass tail (`LG-B`); under
// Reduce Transparency it is an ordinary opaque rect per member, no record, so no split, no blur pass, no sharp
// copy. A change of the setting snaps.

/// One shape a glass fills: its rect, corner radii and kind.
struct GlassMemberShape {
    let rect: Bounds<Pixels>
    let radii: Corners<Pixels>
    let isEllipse: Bool
}

extension ShapeGeometry {
    /// This geometry as a glass member, or `nil` for a `Path` (`LG-L`: a path draws its flat tint).
    var glassMemberShape: GlassMemberShape? {
        guard pathAndStyle == nil else { return nil }
        return GlassMemberShape(rect: rect, radii: cornerRadii, isEllipse: primitiveShape == .ellipse)
    }
}

extension Frame {
    /// The colour a glass's flat tint draws in at this position: the opaque grey under Reduce Transparency, else the
    /// translucent tint. What a path fill (divergence 829) resolves.
    func glassFlatTint(_ glass: Glass) -> Hsla {
        if environmentTop.accessibilityReduceTransparency {
            return GlassLook.opaque(glass, scheme: colorScheme, resolve: { resolve($0) })
        }
        return GlassLook.tint(glass, scheme: colorScheme, resolve: { resolve($0) })
    }

    /// Fills `members` with `glass`: one record whose tail carries the look and, for two or more members, each
    /// member normalised to the record's bounds (`LG-B`) and the blend radius `blendK` points (`LG-G`); under Reduce
    /// Transparency, one opaque rect per member. `press` is the interactive lift's weight (`LG-J`). Nothing for
    /// `.identity` or no member.
    func fillGlass(_ glass: Glass, members: [GlassMemberShape], blendK: Pixels = Pixels(0), press: Float = 0) {
        guard glass.variant != .identity, let first = members.first else { return }
        let scheme = colorScheme
        if environmentTop.accessibilityReduceTransparency {
            let grey = GlassLook.opaque(glass, scheme: scheme, resolve: { resolve($0) })
            for m in members {
                fill(m.rect, color: grey, cornerRadii: m.radii, shape: m.isEllipse ? .ellipse : .roundedRectangle)
            }
            return
        }
        let tint = GlassLook.tint(glass, scheme: scheme, resolve: { resolve($0) })
        let count = min(members.count, GlassReference.maxMembers)
        let used = Array(members.prefix(count))
        var minX = first.rect.origin.x.value, minY = first.rect.origin.y.value
        var maxX = minX + first.rect.size.width.value, maxY = minY + first.rect.size.height.value
        for m in used.dropFirst() {
            minX = min(minX, m.rect.origin.x.value); minY = min(minY, m.rect.origin.y.value)
            maxX = max(maxX, m.rect.origin.x.value + m.rect.size.width.value)
            maxY = max(maxY, m.rect.origin.y.value + m.rect.size.height.value)
        }
        // A blob's smooth-min bulges up to a quarter of the blend radius past the union of its members.
        let pad = count > 1 ? blendK.value / 4 + 1 : 0
        let bounds = Bounds(origin: Point(x: Pixels(minX - pad), y: Pixels(minY - pad)),
                            size: Size(width: Pixels(maxX - minX + 2 * pad), height: Pixels(maxY - minY + 2 * pad)))
        let scale = scaleFactor
        let shortest = used.map { min($0.rect.size.width.value, $0.rect.size.height.value) }.min() ?? 0
        let band = GlassLook.band(shortestSide: shortest) * scale
        let dark = scheme == .dark
        let radii = count == 1 ? first.radii : Corners(all: Pixels(0))
        let single = count == 1
        let tail: (inout MUIBackdrop) -> Void = { record in
            record.glassFlags = GlassReference.flags(lensRim: true, dark: dark, memberCount: count,
                                                     ellipses: used.map(\.isEllipse))
            record.lensDepth = band * GlassLook.lensDepthOfBand
            record.band = band
            record.rimStrength = GlassLook.rimStrength(dark: dark)
            record.blendK = single ? 0 : blendK.value * scale
            record.press = press
            record.pressLift = GlassLook.pressLift
            guard !single else { return }
            let w = max(bounds.size.width.value, 1e-6), h = max(bounds.size.height.value, 1e-6)
            let shorter = max(min(w, h), 1e-6)
            let slots = used.map { m -> MUIGlassMember in
                MUIGlassMember(
                    bounds: MUIBounds(origin: MUIPoint(x: (m.rect.origin.x.value - bounds.origin.x.value) / w,
                                                       y: (m.rect.origin.y.value - bounds.origin.y.value) / h),
                                      size: MUISize(width: m.rect.size.width.value / w, height: m.rect.size.height.value / h)),
                    radii: MUICorners(topLeft: m.radii.topLeft.value / shorter, topRight: m.radii.topRight.value / shorter,
                                      bottomRight: m.radii.bottomRight.value / shorter,
                                      bottomLeft: m.radii.bottomLeft.value / shorter))
            }
            record.member0 = slots[0]
            if slots.count > 1 { record.member1 = slots[1] }
            if slots.count > 2 { record.member2 = slots[2] }
            if slots.count > 3 { record.member3 = slots[3] }
        }
        fillBackdrop(bounds, tint: tint, cornerRadii: radii, shape: single && first.isEllipse ? .ellipse : .roundedRectangle, glassTail: tail)
    }
}

extension PaintPass {
    /// A glass layer's paint at `bounds` (`LG-I`): nothing inside a container that emits it (a `Path` shape is
    /// the exception, it draws its own flat tint, `LG-L`), a flat path fill for a path, else one record in the
    /// shape. `press` is the interactive lift (`LG-J`).
    func paintGlassLayer(_ glass: Glass, shape: any Shape, bounds: Bounds<Pixels>, press: Float = 0,
                         mergesInContainer: Bool = true) {
        guard glass.variant != .identity else { return }
        let geometry = shape.geometry(in: bounds)
        if let (path, style) = geometry.pathAndStyle {
            drawPath(path, fill: style, color: frame.glassFlatTint(glass))
            return
        }
        if mergesInContainer && frame.glassContainerPaintDepth > 0 { return }
        guard let member = geometry.glassMemberShape else { return }
        frame.fillGlass(glass, members: [member], press: press)
    }
}
