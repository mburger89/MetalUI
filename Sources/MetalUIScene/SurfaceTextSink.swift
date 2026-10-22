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
}
