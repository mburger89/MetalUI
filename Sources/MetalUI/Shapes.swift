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
    public var cornerRadius: Pixels
    public var style: RoundedCornerStyle

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
    public init() {}

    public func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
        .ellipse(rect)
    }
}
