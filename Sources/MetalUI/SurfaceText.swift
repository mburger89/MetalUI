import MetalUICore
import MetalUIPlatform
import MetalUIPrimitives
import MetalUIScene
import MetalUITextSystem

extension GPUSurfaceContext {
    /// Draws `text` into this surface's target (MetalUI-only, class `M`: SwiftUI has no GPU context;
    /// `GraphicsContext.draw(_:at:anchor:)` is the arithmetic's twin, probe `swiftui-draw-text.swift`).
    ///
    /// `text` is a ``TextMeasurer/ResolvedText`` from `@Environment(\.textMeasurer)`: its font, weight,
    /// italic and foreground colour were fixed when it was resolved, through the one function a `Text` is laid
    /// out and painted with, so a label here is the label the same `Text` is (`DT-C`). `point` is in the
    /// surface's own space, points from its top-left with y down; the context's ``scaleFactor`` turns it into
    /// device pixels. `anchor` places the laid-out box at `point` (`.center` by default, as SwiftUI's
    /// `draw(_:at:)`); `width` is the width it wraps at (`nil` is one unbounded line, as SwiftUI's `at:`),
    /// and the line cap is the box's own. `color` replaces the resolved foreground.
    ///
    /// **The text is drawn over everything the app drew into this surface, after the app's draw returns,
    /// in the order of the `drawText` calls** (`DT-A`): the call only *records* sprites, and the renderer runs
    /// one MetalUI-owned pass per surface that recorded text, in the frame's own command buffer, so the call
    /// never touches the app's encoder, the commit rule or the atlas's upload order. It cannot put text
    /// *under* the app's own later drawing (use a second surface or a `Text` overlay; `DT-E`). A label that
    /// must be accessible, selectable or themed through the element tree stays a `Text` overlay.
    ///
    /// Plain text only: a rich `ResolvedText` (runs, links, decorations) traps naming `DT-E`; a context
    /// the renderer did not make (no sink) traps naming `DT-F`.
    @MainActor
    public func drawText(_ text: TextMeasurer.ResolvedText, at point: Point<Pixels>,
                         anchor: UnitPoint = .center, width: Pixels? = nil, color: Color? = nil) {
        guard let sink = (self as? any SurfaceTextSinkProviding)?.textSink else {
            preconditionFailure("drawText on a GPUSurfaceContext the renderer did not make: it has no text sink (DT-F)")
        }
        guard case .plain(let string, let font, let style) = text.form else {
            preconditionFailure("drawText takes plain text: a rich ResolvedText (runs, links, decorations) is not built (DT-E)")
        }
        let system = text.system
        // The layout box under the proposal, then `Text.paint`'s own arithmetic (`DT-C`): wrap at the measured
        // width, cap lines at the measured height, place with the frame's scale.
        let proposal = Size(width: width ?? Pixels.infinity, height: Pixels.infinity)
        let size = text.measurement(in: proposal).size
        let originX = Double(point.x.value) - anchor.x * size.width
        let originY = Double(point.y.value) - anchor.y * size.height
        let wrapWidth = max(size.width, smallestWrapWidth)
        let laid = textLines(string, font: font, system: system, wrappingAt: wrapWidth,
                             height: size.height, style: style)
        let placed = system.placeGlyphs(string, font: font, wrappingAt: wrapWidth, options: laid.options,
                                        origin: (x: originX, y: originY), scaleFactor: scaleFactor)
        let hsla = (color ?? style.foreground).resolved(theme: text.colors.theme, scheme: text.colors.scheme, tint: text.colors.tint)
        let whole = Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                           size: Size(width: ScaledPixels(Float(pixelSize.width.value)),
                                      height: ScaledPixels(Float(pixelSize.height.value))))
        for glyph in placed {
            // `Frame.drawSprite`'s own lookup and bearings; a miss rasterizes through the frame's system.
            guard let packed = sink.atlas.packed(for: glyph.key, rasterize: { system.rasterize(glyph.key) }),
                  packed.slot.width > 0, packed.slot.height > 0 else { continue }
            let bounds = Bounds(
                origin: Point(x: ScaledPixels(Float(glyph.pixelX + packed.left)),
                              y: ScaledPixels(Float(glyph.baselineY - packed.top))),
                size: Size(width: ScaledPixels(Float(packed.slot.width)),
                           height: ScaledPixels(Float(packed.slot.height))))
            sink.append(MUIGlyph(bounds: bounds, slot: packed.slot, contentMask: whole, color: hsla, order: 0))
        }
    }
}
