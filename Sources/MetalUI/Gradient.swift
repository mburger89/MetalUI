import Foundation
import MetalUICore
import MetalUILayout

// C10 lane 3 — gradients (ruling `LK-J`, amended by `LK-R`). Spec
// `docs/superpowers/specs/2026-10-08-controls-looks-design.md` §1, §3.3;
// SwiftUI's side is `docs/probes/swiftui-controls-looks.swift`, arms G1–G11,
// R1, R2. A gradient travels the paint scopes as a vector
// (`CapturedPrimitive.gradient`) and is rasterized on the CPU at
// `insertIntoScene` (`GradientRaster.swift`): no shader changes on either
// renderer, so `TE-AD` holds by construction.

/// SwiftUI's `Gradient`: colour stops along a unit parameter (`LK-J` item 1).
/// Stops are **sorted by location** when drawn (probe G4b), two at one
/// location make a hard edge (G4c), and beyond the first and last stop the
/// end colours **pad** (G7). Colours interpolate in premultiplied Oklab (G11,
/// G2, G5). A gradient does not animate: a change snaps (`LK-J` item 7).
public struct Gradient: Hashable, Sendable {
    /// One colour at a location in `0…1` (a location outside pads, as
    /// SwiftUI's does).
    public struct Stop: Hashable, Sendable {
        /// The stop's colour, resolved at paint like any `Color`.
        public var color: Color
        /// Where along the gradient the colour sits.
        public var location: Double

        /// A stop of `color` at `location`.
        public init(color: Color, location: Double) {
            self.color = color
            self.location = location
        }
    }

    /// The stops, in the order given (sorted when drawn).
    public var stops: [Stop]

    /// `colors` spaced evenly from 0 to 1 — SwiftUI's `Gradient(colors:)`.
    /// One colour sits at 0 (so it fills); none draws nothing.
    public init(colors: [Color]) {
        let last = Double(max(colors.count - 1, 1))
        stops = colors.enumerated().map { Stop(color: $1, location: Double($0) / last) }
    }

    /// The given stops — SwiftUI's `Gradient(stops:)`.
    public init(stops: [Stop]) {
        self.stops = stops
    }
}

/// SwiftUI's `LinearGradient` (`LK-J`): a **view** — a greedy leaf whose
/// ideal size is 10 × 10 like a shape (probe G10) — and a fill for
/// `Shape.fill(_:)`, `Shape.stroke(_:lineWidth:)` and `.background(_:)`.
/// The unit points map to the filled rectangle; the parameter is the
/// projection onto start → end **in points** (isolines perpendicular on
/// screen, G3), sampled at pixel centres (G1); start == end draws the last
/// colour (G6).
public struct LinearGradient: Hashable, Sendable {
    /// The colour stops.
    public var gradient: Gradient
    /// Where the parameter is 0, in the filled rectangle's unit space.
    public var startPoint: UnitPoint
    /// Where the parameter is 1.
    public var endPoint: UnitPoint

    /// A linear gradient of `gradient` from `startPoint` to `endPoint`.
    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    /// A linear gradient of `colors`, evenly spaced.
    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    /// A linear gradient of `stops`.
    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }
}

/// SwiftUI's `RadialGradient` (`LK-J`): the parameter is the distance from
/// `center`, **circular in points** whatever the rectangle's aspect (probe
/// R2), 0 at `startRadius` and 1 at `endRadius`, padded beyond (R1). Equal
/// radii draw the last colour. A view and a fill, as ``LinearGradient``.
public struct RadialGradient: Hashable, Sendable {
    /// The colour stops.
    public var gradient: Gradient
    /// The centre, in the filled rectangle's unit space.
    public var center: UnitPoint
    /// The distance (points) where the parameter is 0.
    public var startRadius: Pixels
    /// The distance (points) where the parameter is 1.
    public var endRadius: Pixels

    /// A radial gradient of `gradient` about `center`.
    public init(gradient: Gradient, center: UnitPoint, startRadius: Pixels, endRadius: Pixels) {
        self.gradient = gradient
        self.center = center
        self.startRadius = startRadius
        self.endRadius = endRadius
    }

    /// A radial gradient of `colors`, evenly spaced.
    public init(colors: [Color], center: UnitPoint, startRadius: Pixels, endRadius: Pixels) {
        self.init(gradient: Gradient(colors: colors), center: center, startRadius: startRadius,
                  endRadius: endRadius)
    }

    /// A radial gradient of `stops`.
    public init(stops: [Gradient.Stop], center: UnitPoint, startRadius: Pixels, endRadius: Pixels) {
        self.init(gradient: Gradient(stops: stops), center: center, startRadius: startRadius,
                  endRadius: endRadius)
    }
}

// MARK: - The fill both gradients are (internal)

/// A gradient as a fill (`LK-J`): what a `ShapeView` layer and a legacy
/// `Decoration` store.
enum GradientFill: Hashable, Sendable {
    case linear(LinearGradient)
    case radial(RadialGradient)

    var gradient: Gradient {
        switch self {
        case let .linear(g): g.gradient
        case let .radial(g): g.gradient
        }
    }

    /// The gradient's geometry over `rect` (window points): unit points
    /// mapped onto the rectangle, radii in points.
    func axis(in rect: Bounds<Pixels>) -> GradientAxis {
        func point(_ u: UnitPoint) -> (Double, Double) {
            (Double(rect.origin.x.value) + u.x * Double(rect.size.width.value),
             Double(rect.origin.y.value) + u.y * Double(rect.size.height.value))
        }
        switch self {
        case let .linear(g):
            let s = point(g.startPoint), e = point(g.endPoint)
            return .linear(sx: s.0, sy: s.1, ex: e.0, ey: e.1)
        case let .radial(g):
            let c = point(g.center)
            return .radial(cx: c.0, cy: c.1, r0: Double(g.startRadius.value), r1: Double(g.endRadius.value))
        }
    }
}

/// A gradient's geometry in the space its outline is in (`LK-J` item 2).
enum GradientAxis: Hashable {
    case linear(sx: Double, sy: Double, ex: Double, ey: Double)
    case radial(cx: Double, cy: Double, r0: Double, r1: Double)

    /// The axis moved by `(dx, dy)`.
    func offsetBy(dx: Double, dy: Double) -> GradientAxis {
        switch self {
        case let .linear(sx, sy, ex, ey): .linear(sx: sx + dx, sy: sy + dy, ex: ex + dx, ey: ey + dy)
        case let .radial(cx, cy, r0, r1): .radial(cx: cx + dx, cy: cy + dy, r0: r0, r1: r1)
        }
    }

    /// The parameter at `(x, y)` (same space), unclamped; a degenerate axis
    /// (start == end, equal radii) answers 1, the last colour (G6).
    func parameter(x: Double, y: Double) -> Double {
        switch self {
        case let .linear(sx, sy, ex, ey):
            let dx = ex - sx, dy = ey - sy
            let length = dx * dx + dy * dy
            guard length > 0 else { return 1 }
            return ((x - sx) * dx + (y - sy) * dy) / length
        case let .radial(cx, cy, r0, r1):
            guard r1 != r0 else { return 1 }
            let d = ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot()
            return (d - r0) / (r1 - r0)
        }
    }

    var words: [Double] {
        switch self {
        case let .linear(sx, sy, ex, ey): [0, sx, sy, ex, ey]
        case let .radial(cx, cy, r0, r1): [1, cx, cy, r0, r1]
        }
    }
}

/// A gradient's stops resolved at paint (`LK-J` item 3): gamma sRGB colours,
/// straight alpha, **sorted by location** (a stable sort, so equal locations
/// keep their written order — a hard edge, G4c).
struct GradientStops: Hashable {
    /// `r, g, b, a` per stop, gamma-encoded, straight.
    var colors: [Float]
    var locations: [Double]

    var isEmpty: Bool { locations.isEmpty }

    init(colors: [Float], locations: [Double]) {
        self.colors = colors
        self.locations = locations
    }

    /// `gradient`'s stops, each colour resolved by `resolve`.
    @MainActor
    init(_ gradient: Gradient, resolve: (Color) -> Hsla) {
        let order = gradient.stops.indices.sorted {
            let a = gradient.stops[$0].location, b = gradient.stops[$1].location
            return a < b || (a == b && $0 < $1)
        }
        var colors: [Float] = []
        var locations: [Double] = []
        for i in order {
            let stop = gradient.stops[i]
            precondition(stop.location.isFinite, "Gradient.Stop location \(stop.location) is not finite (LK-J)")
            let rgba = resolve(stop.color).toRgba()
            colors += [rgba.r, rgba.g, rgba.b, rgba.a]
            locations.append(stop.location)
        }
        self.colors = colors
        self.locations = locations
    }

    var keyWords: [UInt64] {
        colors.map { UInt64($0.bitPattern) } + locations.map(\.bitPattern)
    }
}

/// The 1024-entry colour table of a gradient (`LK-J` item 3): premultiplied
/// RGBA8 packed `r | g << 8 | b << 16 | a << 24`, entry `i` the colour at
/// `t = i / 1023`, interpolated in premultiplied Oklab between the stops that
/// bracket `t`, the end colours padding beyond them.
enum GradientTable {
    static let count = 1024

    /// The table of `stops`.
    static func make(_ stops: GradientStops) -> [UInt32] {
        let n = stops.locations.count
        guard n > 0 else { return [UInt32](repeating: 0, count: count) }
        // Each stop in premultiplied Oklab (L·a, A·a, B·a, a): the probe's
        // arithmetic (`gradient-raster-cost.swift`, G5).
        var lab: [(Double, Double, Double, Double)] = []
        for i in 0..<n {
            let r = Double(stops.colors[i * 4]), g = Double(stops.colors[i * 4 + 1])
            let b = Double(stops.colors[i * 4 + 2]), a = Double(min(max(stops.colors[i * 4 + 3], 0), 1))
            let (l, aa, bb) = toOklab(r, g, b)
            lab.append((l * a, aa * a, bb * a, a))
        }
        var out = [UInt32](repeating: 0, count: count)
        var segment = 0
        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            let p: (Double, Double, Double, Double)
            if t <= stops.locations[0] {
                p = lab[0]
            } else if t >= stops.locations[n - 1] {
                p = lab[n - 1]
            } else {
                // The stops bracketing t: locations[segment] <= t < locations[segment + 1]
                // (an empty interval — equal locations — is never chosen: a hard edge).
                while segment + 1 < n - 1 && stops.locations[segment + 1] <= t { segment += 1 }
                let l0 = stops.locations[segment], l1 = stops.locations[segment + 1]
                let f = l1 > l0 ? (t - l0) / (l1 - l0) : 1
                let a = lab[segment], b = lab[segment + 1]
                p = (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f, a.3 + (b.3 - a.3) * f)
            }
            let alpha = p.3
            guard alpha > 1e-6 else { continue }
            let (r, g, b) = fromOklab(p.0 / alpha, p.1 / alpha, p.2 / alpha)
            func byte(_ v: Double) -> UInt32 { UInt32(min(max(v, 0), 1) * 255 + 0.5) }
            out[i] = byte(r * alpha) | byte(g * alpha) << 8 | byte(b * alpha) << 16 | byte(alpha) << 24
        }
        return out
    }

    private static func srgbToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : Foundation.pow((c + 0.055) / 1.055, 2.4)
    }

    private static func linearToSrgb(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * Foundation.pow(max(c, 0), 1 / 2.4) - 0.055
    }

    private static func toOklab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let lr = srgbToLinear(r), lg = srgbToLinear(g), lb = srgbToLinear(b)
        let l = Foundation.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = Foundation.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = Foundation.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private static func fromOklab(_ L: Double, _ A: Double, _ B: Double) -> (Double, Double, Double) {
        let l = Foundation.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = Foundation.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = Foundation.pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
        return (linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }

    /// The entry for parameter `t` (clamped).
    @inline(__always)
    static func index(_ t: Double) -> Int {
        let clamped = t.isNaN ? 0 : min(max(t, 0), 1)
        return Int(clamped * Double(count - 1) + 0.5)
    }
}

// MARK: - The gradient as a view (`G10`)

/// A gradient view's layout state: its one native leaf.
public struct GradientViewLayout {
    var node: LayoutNodeID
}

extension LinearGradient: ProposalElement {
    /// One native leaf answering the proposal, a nil axis 10 (probe G10: own
    /// 300 × 120, fitting 10 × 10), as a shape does.
    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, GradientViewLayout) {
        gradientViewLayout(pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout GradientViewLayout, pass: inout PrepaintPass) {}

    /// Fills the view's bounds.
    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout GradientViewLayout, prepaint: inout Void,
                               pass: inout PaintPass) {
        paintGradientView(.linear(self), bounds: bounds, pass: pass)
    }
}

extension RadialGradient: ProposalElement {
    /// One native leaf answering the proposal, a nil axis 10, as
    /// ``LinearGradient`` does.
    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, GradientViewLayout) {
        gradientViewLayout(pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout GradientViewLayout, pass: inout PrepaintPass) {}

    /// Fills the view's bounds.
    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout GradientViewLayout, prepaint: inout Void,
                               pass: inout PaintPass) {
        paintGradientView(.radial(self), bounds: bounds, pass: pass)
    }
}

@MainActor
private func gradientViewLayout(pass: inout LayoutPass) -> (ProposalNodeID, GradientViewLayout) {
    let node = pass.requestNativeLeaf { LayoutMeasurement(size: SizeD(width: $0.width ?? 10, height: $0.height ?? 10)) }
    return (node, GradientViewLayout(node: node.layoutNodeID))
}

@MainActor
private func paintGradientView(_ fill: GradientFill, bounds: Bounds<Pixels>, pass: PaintPass) {
    paintGradientFill(fill, .roundedRectangle(bounds, cornerRadii: Corners(all: Pixels(0))), style: nil, pass: pass)
}
