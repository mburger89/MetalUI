import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIPrimitives

// R4-5 PR D — a gradient `foregroundStyle` on text (ruling prefix `TG-`, record 221, divergence 975 narrowed). The glyphs are
// the mask and the gradient raster is the content: one masked group per gradient (`CM-A`'s destination-in pass, no shader
// line and no fixture field moves, `TE-AD` by construction). The gradient spans the **ink** of every run that carries it,
// decorations included (probe `swiftui-text-gradient.swift`: `TG1`..`TG5`, `TG10`), not the layout box.

extension PaintPass {
    /// A text draw's glyphs painted with `fill` (`TG-C`): inside one leaf group (`GX-J`, so a shadow still sees the whole text
    /// as one leaf), the glyphs the mask of one gradient over their ink. The plain `Text` and `ProposalText` path.
    func drawGradientGlyphs<S: Sequence>(_ glyphs: S, fill: GradientFill, color: Hsla) where S.Element == TextGlyph {
        frame.beginLeafGroup()
        defer { frame.endLeafGroup() }
        var ink: [CapturedPrimitive] = []
        for glyph in glyphs { if let primitive = frame.inkGlyph(glyph, color: color) { ink.append(primitive) } }
        drawGradientInk(ink, fill: fill)
    }

    /// `ink` (glyph and decoration records built by `Frame.inkGlyph`/`Frame.inkRect`) as the mask of `fill` over its bounds
    /// (`TG-C`). The stops resolve here, as `drawGradient`'s do.
    func drawGradientInk(_ ink: [CapturedPrimitive], fill: GradientFill) {
        let stops = GradientStops(fill.gradient, resolve: { resolve($0) })
        guard !stops.isEmpty else { return }
        frame.drawGradientInk(ink, fill: fill, stops: stops)
    }
}

extension Frame {
    /// A decoration rect (an underline or strikethrough piece) as an element of a gradient text's ink (`TG-C`): `fill`'s
    /// arithmetic with no clip of its own and no opacity, alpha 1 (see ``inkGlyph(_:)``).
    func inkRect(_ bounds: Bounds<Pixels>, color: Hsla) -> CapturedPrimitive {
        let translated = Bounds(
            origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                          y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
            size: bounds.size)
        let zero = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
        let rect = MUIRect(bounds: MUIBounds(translated.scaled(by: scaleFactor)), contentMask: Self.unboundedMask,
                           maskCornerRadii: zero, background: MUIHsla(h: color.h, s: color.s, l: color.l, a: 1),
                           borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0), cornerRadii: zero,
                           borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0,
                           shape: PrimitiveShape.roundedRectangle.rawValue)
        return CapturedPrimitive(kind: .rect(rect), layer: activeLayer, innerMask: false)
    }

    /// The device-pixel box of `ink`: the union of its glyph and rect records (`nil` for none).
    static func inkBounds(_ ink: [CapturedPrimitive]) -> (minX: Float, minY: Float, maxX: Float, maxY: Float)? {
        var box: (minX: Float, minY: Float, maxX: Float, maxY: Float)?
        func add(_ b: MUIBounds) {
            let x0 = b.origin.x, y0 = b.origin.y, x1 = b.origin.x + b.size.width, y1 = b.origin.y + b.size.height
            guard x1 > x0, y1 > y0 else { return }
            if let c = box { box = (min(c.minX, x0), min(c.minY, y0), max(c.maxX, x1), max(c.maxY, y1)) } else { box = (x0, y0, x1, y1) }
        }
        for p in ink {
            switch p.kind {
            case let .glyph(g): add(g.bounds)
            case let .rect(r): add(r.bounds)
            default: break
            }
        }
        return box
    }

    /// One gradient text group (`TG-C`): `fill` over the box of `ink`, the content of a masked group whose mask is `ink`.
    /// The box is the ink's device bounds mapped back to points (the gradient spans what is drawn, probe `TG3`), the content
    /// carries the fade (`activeOpacity`) and the clip, the ink neither. It travels the paint scopes as one primitive with
    /// one mark, so a shadow, an effect, an opacity group or a retained replay treats it as any masked leaf; **no
    /// `PaintScope` is pushed**, so a moved `.equatable()` occurrence does not refuse with `innerScope`.
    func drawGradientInk(_ ink: [CapturedPrimitive], fill: GradientFill, stops: GradientStops) {
        guard let box = Self.inkBounds(ink) else { return }
        let s = scaleFactor
        let rect = Bounds(origin: Point(x: Pixels(box.minX / s - activeOffset.x.value),
                                        y: Pixels(box.minY / s - activeOffset.y.value)),
                          size: Size(width: Pixels((box.maxX - box.minX) / s), height: Pixels((box.maxY - box.minY) / s)))
        let geometry = ShapeGeometry.roundedRectangle(rect, cornerRadii: Corners(all: Pixels(0)))
        let style = FillStyle()
        guard var content = gradientPrimitive(Path(geometry), mode: .fill(style.rule, antialiased: style.isAntialiased),
                                              rect: rect, radii: geometry.cornerRadii, axis: fill.axis(in: rect),
                                              stops: stops) else { return }
        content.groups = [GroupMark(token: GroupToken(), alpha: 1, mask: ink, maskDepth: clipDepth, inkMask: true)]
        if paintScopes.isEmpty {
            retainLog?.noteDirect(content, depth: clipDepth)
            insertLeaves([content])
        } else {
            insertThroughScopes(content)
        }
    }
}
