import MetalUICore
import MetalUILayout

// SwiftUI's built-in shapes (plan task 11, part 2; ruling `TE-AG` item 2).
// `Rectangle` is in `NativeElements.swift` (`TE-AH`). Every built-in is
// `Hashable`, so it can be a legacy `clipShape` (`TE-AQ` item 3).

/// A rectangle with rounded corners — SwiftUI's
/// `RoundedRectangle(cornerRadius:style:)`. The radius clamps to half the
/// shorter side and a negative one is 0 (probes S4, S5); `.continuous`, the
/// default, is drawn circular (divergence 90).
public struct RoundedRectangle: Shape, Hashable {
    /// The corner radius, clamped to half the shorter side.
    public var cornerRadius: Pixels
    public var style: RoundedCornerStyle

    /// A rounded rectangle with `cornerRadius` corners drawn in `style`.
    public init(cornerRadius: Pixels, style: RoundedCornerStyle = .continuous) {
        self.cornerRadius = cornerRadius
        self.style = style
    }

    public func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
        .roundedRectangle(rect, cornerRadii: Corners(all: cornerRadius), style: style)
    }
}

/// A circle — SwiftUI's `Circle()`: the square of the smaller proposed side
/// (a nil axis takes the other's value; nil × nil is 10 × 10, probe S1),
/// drawn centred in its frame (S2).
public struct Circle: Shape, Hashable {
    /// A circle.
    public init() {}

    public nonisolated func sizeThatFits(_ proposal: ProposedSize) -> SizeD {
        switch (proposal.width, proposal.height) {
        case let (width?, height?):
            let side = min(width, height)
            return SizeD(width: side, height: side)
        case let (width?, nil): return SizeD(width: width, height: width)
        case let (nil, height?): return SizeD(width: height, height: height)
        case (nil, nil): return SizeD(width: 10, height: 10)
        }
    }

    public func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
        let side = min(rect.size.width.value, rect.size.height.value)
        let square = Bounds(origin: Point(x: Pixels(rect.origin.x.value + (rect.size.width.value - side) / 2),
                                          y: Pixels(rect.origin.y.value + (rect.size.height.value - side) / 2)),
                            size: Size(width: Pixels(side), height: Pixels(side)))
        return .roundedRectangle(square, cornerRadii: Corners(all: Pixels(side / 2)), style: .circular)
    }
}

/// A capsule — SwiftUI's `Capsule(style:)`: a rounded rectangle whose radius
/// is half the shorter side (S6). `.continuous`, the default, is drawn
/// circular (divergence 90).
public struct Capsule: Shape, Hashable {
    public var style: RoundedCornerStyle

    /// A capsule whose ends are drawn in `style`.
    public init(style: RoundedCornerStyle = .continuous) {
        self.style = style
    }

    public func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
        let radius = min(rect.size.width.value, rect.size.height.value) / 2
        return .roundedRectangle(rect, cornerRadii: Corners(all: Pixels(radius)), style: style)
    }
}

/// An ellipse inscribed in its frame — SwiftUI's `Ellipse()`, drawn by the
/// renderer's ellipse kind (`TE-AE`). It cannot be a clip (divergence 91).
public struct Ellipse: Shape, Hashable {
    /// An ellipse.
    public init() {}

    public func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
        .ellipse(rect)
    }
}

/// The four corner radii of an ``UnevenRoundedRectangle`` — SwiftUI's
/// `RectangleCornerRadii`. Leading is the left edge and trailing the right
/// (a shape does not read the layout direction).
public struct RectangleCornerRadii: Hashable, Sendable {
    /// The top-left corner's radius.
    public var topLeading: Pixels
    /// The bottom-left corner's radius.
    public var bottomLeading: Pixels
    /// The bottom-right corner's radius.
    public var bottomTrailing: Pixels
    /// The top-right corner's radius.
    public var topTrailing: Pixels

    /// Radii for the four corners, each zero by default.
    public init(topLeading: Pixels = Pixels(0), bottomLeading: Pixels = Pixels(0),
                bottomTrailing: Pixels = Pixels(0), topTrailing: Pixels = Pixels(0)) {
        self.topLeading = topLeading
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
        self.topTrailing = topTrailing
    }

    /// These radii as the renderer's per-corner record, unclamped.
    var corners: Corners<Pixels> {
        Corners(topLeft: topLeading, topRight: topTrailing, bottomRight: bottomTrailing, bottomLeft: bottomLeading)
    }

    /// These radii fitted to a `width` × `height` rectangle by SwiftUI's rule
    /// (probes UR1–UR3, X1, Y1–Y7, ruling `PG-G`): a negative radius is 0; on
    /// each side whose two radii sum past its length, the smaller one stays
    /// (when it is under half the side) and the larger shrinks to fill the
    /// rest, or both become half the side; a corner takes the smaller of its
    /// two sides' answers. A single radius may therefore exceed half the
    /// shorter side (`TL` 45 on 100×60 stays 45).
    func fitted(width: Double, height: Double) -> Corners<Double> {
        func fit(_ a: Double, _ b: Double, _ side: Double) -> (Double, Double) {
            guard side > 0 else { return (0, 0) }
            guard a + b > side else { return (a, b) }
            let m = min(a, b)
            if m >= side / 2 { return (side / 2, side / 2) }
            return a < b ? (a, side - a) : (side - b, b)
        }
        let tl = max(0, Double(topLeading.value)), tr = max(0, Double(topTrailing.value))
        let br = max(0, Double(bottomTrailing.value)), bl = max(0, Double(bottomLeading.value))
        let top = fit(tl, tr, width), bottom = fit(bl, br, width)
        let left = fit(tl, bl, height), right = fit(tr, br, height)
        return Corners(topLeft: min(top.0, left.0), topRight: min(top.1, right.0),
                       bottomRight: min(bottom.1, right.1), bottomLeft: min(bottom.0, left.1))
    }
}

/// A rectangle with a radius of its own at each corner — SwiftUI's
/// `UnevenRoundedRectangle` (item R3-8, ruling `PG-G`).
///
/// **Drawn by the renderer's per-corner rounded rectangle whenever it can**:
/// when every fitted radius is at most half the shorter side (the SDF's
/// limit) the shape is that primitive, fill and stroke, and it can be a
/// `clipShape`. A radius past that — legal in SwiftUI, where one corner may
/// take most of a side the others leave free (probe X2) — is drawn as a
/// ``Path``, rasterized on the CPU, which cannot be a clip (divergence 91).
/// `.continuous` is drawn circular (divergence 90). Its outline starts on the
/// right edge and runs down, as SwiftUI's does (probe UR1), so `trim` and
/// dashes begin where SwiftUI's do.
public struct UnevenRoundedRectangle: Shape, Hashable {
    /// The four corner radii, before fitting to the rectangle.
    public var cornerRadii: RectangleCornerRadii
    /// How the corners are drawn.
    public var style: RoundedCornerStyle

    /// An uneven rounded rectangle with `cornerRadii`.
    public init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
        self.cornerRadii = cornerRadii
        self.style = style
    }

    /// An uneven rounded rectangle from four radii.
    public init(topLeadingRadius: Pixels = Pixels(0), bottomLeadingRadius: Pixels = Pixels(0),
                bottomTrailingRadius: Pixels = Pixels(0), topTrailingRadius: Pixels = Pixels(0),
                style: RoundedCornerStyle = .continuous) {
        self.init(cornerRadii: RectangleCornerRadii(topLeading: topLeadingRadius,
                                                    bottomLeading: bottomLeadingRadius,
                                                    bottomTrailing: bottomTrailingRadius,
                                                    topTrailing: topTrailingRadius),
                  style: style)
    }

    /// The fitted radii in `rect`, and whether the SDF can draw them.
    private func fitted(in rect: Bounds<Pixels>) -> (radii: Corners<Pixels>, isSDF: Bool) {
        let w = Double(rect.size.width.value), h = Double(rect.size.height.value)
        let f = cornerRadii.fitted(width: w, height: h)
        let limit = max(0, min(w, h) / 2)
        let sdf = f.topLeft <= limit && f.topRight <= limit && f.bottomRight <= limit && f.bottomLeft <= limit
        return (Corners(topLeft: Pixels(Float(f.topLeft)), topRight: Pixels(Float(f.topRight)),
                        bottomRight: Pixels(Float(f.bottomRight)), bottomLeft: Pixels(Float(f.bottomLeft))), sdf)
    }

    /// The per-corner rounded rectangle when its fitted radii fit the renderer's
    /// limit, else the outline as a path (`PG-G`).
    public func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
        let (radii, isSDF) = fitted(in: rect)
        if isSDF { return .roundedRectangle(rect, cornerRadii: radii, style: style) }
        return .path(Path(ShapeGeometry(rect: rect, kind: .roundedRectangle(radii, style))))
    }

    /// The outline in the local `rect`, SwiftUI's start and order (`PG-G`, `PG-H`).
    public func path(in rect: Bounds<Pixels>) -> Path {
        Path(ShapeGeometry(rect: rect, kind: .roundedRectangle(fitted(in: rect).radii, style)))
    }
}
