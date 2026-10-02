import MetalUICore
import MetalUIPath

// Paths, shadows and transforms, lane 3 — fill and stroke styles (ruling
// `GX-E`). Spec `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md`
// §1 and §4.1; SwiftUI's side is `docs/probes/swiftui-paths-shadows-transforms.swift`,
// arms PA2 and ST1–ST10.

/// How a filled shape's interior is decided — SwiftUI's `FillStyle`.
///
/// `isEOFilled` chooses the even-odd rule over the default nonzero winding
/// rule (probe PA2: even-odd empties a ring whose two subpaths run the same
/// way; a reversed inner ring is a hole under both). `isAntialiased: false`
/// thresholds each pixel's coverage at one half.
public struct FillStyle: Hashable, Sendable {
    /// Whether the even-odd rule decides the interior (default: nonzero).
    public var isEOFilled: Bool
    /// Whether edges are antialiased (default: `true`).
    public var isAntialiased: Bool

    /// A fill style — SwiftUI's `FillStyle(eoFill:antialiased:)`.
    public init(eoFill: Bool = false, antialiased: Bool = true) {
        isEOFilled = eoFill
        isAntialiased = antialiased
    }

    var rule: FillRule { isEOFilled ? .evenOdd : .nonZero }
}

/// How an open stroke ends — SwiftUI's `CGLineCap` case names (probe ST1–ST3:
/// butt at the endpoint; round and square half the width past it).
public enum LineCap: Hashable, Sendable {
    /// Flat, at the endpoint (the default).
    case butt
    /// A half disc past the endpoint.
    case round
    /// A half square past the endpoint.
    case square
}

/// How two stroke segments meet — SwiftUI's `CGLineJoin` case names (probe
/// ST5: miter tip, bevel, round).
public enum LineJoin: Hashable, Sendable {
    /// A sharp corner, falling back to a bevel past `miterLimit` (the default).
    case miter
    /// A circular corner.
    case round
    /// The corner cut flat.
    case bevel
}

/// A stroke's geometry — SwiftUI's `StrokeStyle`, with its defaults (probe
/// ST4–ST6: width 1, `.butt`, `.miter`, limit 10, no dash).
///
/// `lineWidth` is in points. A width ≤ 0 strokes nothing (ST10). `dash`
/// alternates on/off lengths from `dashPhase` along the path's arc length
/// (ST7); an empty pattern is a solid line. The stroke is computed on the
/// CPU and drawn as an image (`GX-B`, `GX-E`); a plain-width stroke of a
/// built-in shape keeps the renderer's exact band instead.
public struct StrokeStyle: Hashable, Sendable {
    /// The stroke's width, in points.
    public var lineWidth: Pixels
    /// How open ends are drawn.
    public var lineCap: LineCap
    /// How corners are drawn.
    public var lineJoin: LineJoin
    /// The miter length, as a multiple of the width, past which a miter join
    /// becomes a bevel.
    public var miterLimit: Double
    /// Alternating dash and gap lengths, in points.
    public var dash: [Pixels]
    /// How far into the dash pattern the stroke starts, in points.
    public var dashPhase: Pixels

    /// A stroke style — SwiftUI's `StrokeStyle(lineWidth:lineCap:lineJoin:miterLimit:dash:dashPhase:)`.
    public init(lineWidth: Pixels = Pixels(1), lineCap: LineCap = .butt, lineJoin: LineJoin = .miter,
                miterLimit: Double = 10, dash: [Pixels] = [], dashPhase: Pixels = Pixels(0)) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.dash = dash
        self.dashPhase = dashPhase
    }

    /// `MetalUIPath`'s parameters, in path units (points).
    var parameters: StrokeParameters {
        let cap: LineCapStyle = switch lineCap {
        case .butt: .butt
        case .round: .round
        case .square: .square
        }
        let join: LineJoinStyle = switch lineJoin {
        case .miter: .miter
        case .round: .round
        case .bevel: .bevel
        }
        return StrokeParameters(width: Double(lineWidth.value), cap: cap, join: join, miterLimit: miterLimit,
                                dash: dash.map { Double($0.value) }, dashPhase: Double(dashPhase.value))
    }

    /// Whether this style, stroking a built-in shape's closed outline, draws
    /// exactly the renderer's SDF band (`GX-E`): SwiftUI's default apart from
    /// the width — any cap (a closed outline has no ends), a miter join whose
    /// limit reaches a right angle's ratio (√2), no dash.
    var isPlainBand: Bool {
        lineJoin == .miter && miterLimit >= 2.0.squareRoot() && dash.isEmpty
    }
}
