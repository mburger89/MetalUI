import MetalUIShaderTypes

/// Where `drawText` records a surface's glyph sprites for the frame (`DT-F`, record 141).
///
/// A renderer makes one per `finishFrame`, holding the frame's glyph atlas, calls
/// ``beginSurface(_:)`` before each surface's draw, hands it to the draw's context
/// (``SurfaceTextSinkProviding``) and, after every draw has returned and the atlas is uploaded
/// (`DT-B`), runs one MetalUI-owned pass per ``Batch`` over ``glyphs`` (`DT-A`). `package`: the one public
/// verb is `drawText`; a backend in this package reads the records, an app never sees them.
///
/// The records are the scene's own `MUIGlyph`, so the renderers' existing glyph pipelines draw them
/// unchanged (`TE-AD`: no shader moves).
///
/// **The grid sink (`TRM-AU`).** The same sink also records solid rectangles - cell backgrounds, a cursor, a
/// selection, an underline - through ``fillRect(_:color:clip:)``: each is a glyph instance over the one
/// reserved ``solidSlot`` of the atlas (a fully covered square), so a terminal view draws its whole grid, glyphs
/// and rects in call order, in the one pass and with no C, shader or pipeline change. Because one pass draws
/// the instances in order, a row redrawn later in a frame (an opaque background rect, then its glyphs) replaces
/// that row's pixels on a retained target and leaves every other row as it was.
@MainActor
package final class SurfaceTextSink {
    /// The glyphs one surface recorded, as a range of ``glyphs``.
    package struct Batch {
        /// The surface whose target the glyphs are drawn into.
        package let target: SurfaceID
        /// The range of ``glyphs`` (call order).
        package var range: Range<Int>
    }

    /// The frame's glyph atlas: a `drawText` rasterizes into it on a miss, and the renderer uploads it after
    /// the draws.
    package let atlas: GlyphAtlas
    /// Every recorded sprite, surface by surface, in call order.
    package private(set) var glyphs: [MUIGlyph] = []
    /// The surfaces that recorded text, in request order.
    package private(set) var batches: [Batch] = []
    private var current: SurfaceID?
    private var cachedSolid: AtlasSlot?

    /// The atlas key of the solid square (`TRM-AU`): a font no resolver can produce, so no real glyph ever shares it.
    package static let solidKey = GlyphKey(
        font: FontKey(resolvedPostScriptName: "MetalUI.GridSink.Solid", size: 1, variations: [],
                      matrix: FontKey.Matrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)),
        glyph: 0, size: 1, subpixelVariant: 0, scaleFactor: 1)

    /// The side of the solid square, in atlas texels. Only the inner ``solidInset`` ring-free square is sampled,
    /// so a linear filter at the quad's edges never reaches a neighbour's texels.
    package static let solidSide = 4
    /// The border, in texels, between the slot's edge and the sampled square.
    package static let solidInset = 1

    /// The slot of a fully covered ``solidSide`` square, packed on first use (the atlas keeps it for as long as
    /// a frame asks for it, like any glyph), or `nil` if the atlas has no room.
    package var solidSlot: AtlasSlot? {
        if let cachedSolid { return cachedSolid }
        let side = Self.solidSide
        cachedSolid = atlas.packed(for: Self.solidKey, rasterize: {
            GlyphImage(width: side, height: side, bytes: [UInt8](repeating: 255, count: side * side))
        })?.slot
        return cachedSolid
    }

    /// An empty sink over `atlas`.
    package init(atlas: GlyphAtlas) {
        self.atlas = atlas
    }

    /// The surface the next ``append(_:)`` calls belong to.
    package func beginSurface(_ id: SurfaceID) {
        current = id
    }

    /// Records one sprite for the current surface.
    package func append(_ glyph: MUIGlyph) {
        guard let target = current else {
            preconditionFailure("SurfaceTextSink.append before beginSurface (DT-F)")
        }
        let index = glyphs.count
        glyphs.append(glyph)
        if var last = batches.last, last.target == target {
            last.range = last.range.lowerBound..<(index + 1)
            batches[batches.count - 1] = last
        } else {
            batches.append(Batch(target: target, range: index..<(index + 1)))
        }
    }

    /// Records a solid rectangle of `color` over `bounds` (device pixels in the target's own space), clipped to
    /// `clip` (`nil`: the rectangle itself), in call order with the glyphs. Returns `false` and records nothing
    /// when the atlas has no room for the solid slot.
    ///
    /// The instance's source is the slot's inner square (``solidInset`` texels in), so the sampled coordinate
    /// across the whole quad stays inside the slot's texels and a rect of any size reads full coverage at every
    /// pixel, edge pixels included (`TRM-AU`).
    @discardableResult
    package func fillRect(_ bounds: MUIBounds, color: MUIHsla, clip: MUIBounds? = nil) -> Bool {
        guard let slot = solidSlot else { return false }
        let inset = Float(Self.solidInset), inner = Float(Self.solidSide - 2 * Self.solidInset)
        append(MUIGlyph(
            bounds: bounds,
            atlasBounds: MUIBounds(origin: MUIPoint(x: Float(slot.x) + inset, y: Float(slot.y) + inset),
                                   size: MUISize(width: inner, height: inner)),
            contentMask: clip ?? bounds,
            maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            color: color, order: 0, transform: 0))
        return true
    }
}
