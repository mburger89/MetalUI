// RED-FIRST SKELETON — replaced by the implementation in the next commit.

package enum PathMath {
    package static func sinCos(_ x: Double) -> (sin: Double, cos: Double) { (0, 1) }
}

package struct Polyline: Hashable, Sendable {
    package var points: [PathPoint]
    package var closed: Bool
    package init(points: [PathPoint], closed: Bool) { self.points = points; self.closed = closed }
}

package enum Flattener {
    package static let defaultTolerance = 0.1
    package static func flatten(_ geometry: PathGeometry, tolerance: Double = defaultTolerance) -> [Polyline] { [] }
}

package enum LineCapStyle: Hashable, Sendable { case butt, round, square }
package enum LineJoinStyle: Hashable, Sendable { case miter, round, bevel }

package struct StrokeParameters: Hashable, Sendable {
    package var width: Double
    package var cap: LineCapStyle
    package var join: LineJoinStyle
    package var miterLimit: Double
    package var dash: [Double]
    package var dashPhase: Double
    package init(width: Double, cap: LineCapStyle = .butt, join: LineJoinStyle = .miter,
                 miterLimit: Double = 10, dash: [Double] = [], dashPhase: Double = 0) {
        self.width = width; self.cap = cap; self.join = join; self.miterLimit = miterLimit
        self.dash = dash; self.dashPhase = dashPhase
    }
}

package enum Stroker {
    package static func stroke(_ lines: [Polyline], _ style: StrokeParameters,
                               tolerance: Double = Flattener.defaultTolerance) -> [Polyline] { [] }
}

package enum FillRule: Hashable, Sendable { case nonZero, evenOdd }

package struct CoverageRasterizer: Sendable {
    package private(set) var lastRasterizedPixels = 0
    package init() {}
    package mutating func rasterize(_ polygons: [Polyline], rule: FillRule, clip: RasterRect,
                                    antialiased: Bool = true) -> AlphaMask { .empty }
}

package enum BoxBlur {
    package static func boxWidths(sigma: Double) -> [Int] { [] }
    package static func padding(sigma: Double) -> Int { 0 }
    package static func blur(_ mask: AlphaMask, sigma: Double) -> AlphaMask { mask }
}

package enum AlphaCompositor {
    package enum Filter: Hashable, Sendable { case nearest, bilinear }
    package static func union(_ a: AlphaMask, _ b: AlphaMask) -> AlphaMask { a }
    package static func resample(source: [UInt8], width: Int, height: Int, channels: Int,
                                 transform: PathAffine, into rect: RasterRect, filter: Filter) -> AlphaMask {
        AlphaMask(rect: rect, alpha: [UInt8](repeating: 0, count: rect.area))
    }
}

package enum PathRaster {
    package static func fill(_ geometry: PathGeometry, rule: FillRule, transform: PathAffine = .identity,
                             clip: RasterRect, antialiased: Bool = true,
                             tolerance: Double = Flattener.defaultTolerance,
                             rasterizer: inout CoverageRasterizer) -> AlphaMask { .empty }
    package static func stroke(_ geometry: PathGeometry, style: StrokeParameters, transform: PathAffine = .identity,
                               clip: RasterRect, tolerance: Double = Flattener.defaultTolerance,
                               rasterizer: inout CoverageRasterizer) -> AlphaMask { .empty }
}
