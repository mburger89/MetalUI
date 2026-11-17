import MetalUIScene
import MetalUITextSystem

/// The cell grid of a monospace face at one scale, in whole device pixels (`TRM-AZ`).
///
/// **Rounding.** Every quantity is measured in points and turned into device pixels once, at the window's scale
/// factor, so a cell is a whole number of pixels and the grid never drifts from the pixel grid:
/// - `cellWidth` is the advance of "M" times the scale, rounded to nearest, at least 1;
/// - `cellHeight` is the face's line height (already `ceil`ed in points, divergence 86) times the scale, rounded
///   to nearest, at least 1;
/// - `baseline` is the text system's own baseline row for a line of this face placed at the cell's top (the
///   row `Text` would use), clamped into the cell;
/// - `underlineThickness` is the face's thickness times the scale, rounded, at least 1; `underlineTop` puts the
///   underline's centre where the face says (below the baseline), kept at least one pixel below the baseline and
///   inside the cell; `strikeTop` centres a stroke of the same thickness on the face's strikethrough position.
///
/// A size in points is `pixels / scale`, so the cell at scale 2 is within half a pixel (a quarter point) of
/// twice the cell at scale 1 in each dimension: the scales agree to the pixel, not exactly.
package struct TerminalCellMetrics: Equatable, Sendable {
    /// The cell width in device pixels.
    package let cellWidth: Int
    /// The cell height in device pixels.
    package let cellHeight: Int
    /// Device pixels from the cell's top to the baseline row.
    package let baseline: Int
    /// Device pixels from the cell's top to the top of the underline.
    package let underlineTop: Int
    /// The underline's thickness, and the strikethrough's, in device pixels.
    package let underlineThickness: Int
    /// Device pixels from the cell's top to the top of the strikethrough.
    package let strikeTop: Int
    /// Device pixels per point the metrics were measured at.
    package let scale: Float

    package init(cellWidth: Int, cellHeight: Int, baseline: Int, underlineTop: Int, underlineThickness: Int,
                 strikeTop: Int, scale: Float) {
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.baseline = baseline
        self.underlineTop = underlineTop
        self.underlineThickness = underlineThickness
        self.strikeTop = strikeTop
        self.scale = scale
    }

    /// The metrics of `font` in `system` at `scale` (device pixels per point).
    @MainActor package static func measure(_ font: FontKey, in system: any TextSystem, scale: Float) -> TerminalCellMetrics {
        let s = Double(scale)
        let advance = system.measure("M", font: font, wrappingAt: nil).widestLine
        let face = system.fontMetrics(font)
        let width = max(1, Int((advance * s).rounded()))
        let height = max(1, Int((face.lineHeight * s).rounded()))
        let placed = system.placeGlyphs("M", font: font, wrappingAt: nil, origin: (x: 0, y: 0), scaleFactor: scale)
        let rawBaseline = placed.first?.baselineY ?? Int((face.ascent * s).rounded())
        let baseline = min(max(rawBaseline, 1), height)
        let decoration = system.decorationMetrics(font)
        let thickness = max(1, Int((decoration.underlineThickness * s).rounded()))
        // The underline's centre sits `-underlinePosition` below the baseline (the position is negative below it).
        let centre = baseline + Int((-decoration.underlinePosition * s).rounded())
        var underline = centre - thickness / 2
        underline = max(underline, baseline + 1)
        underline = min(underline, height - thickness)
        underline = max(underline, 0)
        let strikeCentre = baseline - Int((decoration.strikethroughPosition * s).rounded())
        let strike = min(max(strikeCentre - thickness / 2, 0), max(height - thickness, 0))
        return TerminalCellMetrics(cellWidth: width, cellHeight: height, baseline: baseline,
                                   underlineTop: underline, underlineThickness: thickness, strikeTop: strike,
                                   scale: scale)
    }
}
