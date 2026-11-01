import MetalUICore
import MetalUILayout

// `Shape.trim(from:to:)` (item R3-8, rulings `PG-A`, `PG-F`). SwiftUI's
// `_TrimmedShape` is `Animatable` over `AnimatablePair<CGFloat, CGFloat>`;
// MetalUI has no `Animatable` protocol (divergence 169), so a shape that
// animates a value does it the way the proposal path's other paint-time
// values do: its element paints through `shapeForPaint(_:_:pass:)`, which
// runs the declared fractions through a track in the window's
// `AnimationStore` (divergence 947).

/// A shape drawing part of another shape's outline — SwiftUI's `_TrimmedShape`,
/// made by ``Shape/trim(from:to:)``.
///
/// Its path is the base shape's path trimmed by arc length
/// (``Path/trimmedPath(from:to:)``), so the start of a closed built-in is
/// SwiftUI's: the right edge's midpoint for a rounded rectangle or capsule,
/// the rightmost point for an ellipse, the top-left corner for a rectangle
/// (probe TS), running visually clockwise. It lays out as the base shape does.
///
/// **Under `withAnimation` the two fractions animate** (`PG-F`), so
/// `trim(from: 0, to: progress)` drawn with `stroke` grows the line over the
/// transaction. A first sighting and a change without a transaction snap.
public struct TrimmedShape<Base: Shape>: Shape {
    /// The shape being trimmed.
    public var shape: Base
    /// Where the drawn part starts, as a fraction of the outline's arc length.
    public var startFraction: Double
    /// Where the drawn part ends, as a fraction of the outline's arc length.
    public var endFraction: Double

    /// `shape` trimmed to `startFraction…endFraction` of its arc length.
    public init(shape: Base, startFraction: Double = 0, endFraction: Double = 1) {
        self.shape = shape
        self.startFraction = startFraction
        self.endFraction = endFraction
    }

    /// The base shape's path in `rect`, trimmed.
    public func path(in rect: Bounds<Pixels>) -> Path {
        shape.path(in: rect).trimmedPath(from: startFraction, to: endFraction)
    }

    public nonisolated func sizeThatFits(_ proposal: ProposedSize) -> SizeD {
        shape.sizeThatFits(proposal)
    }
}

extension Shape {
    /// This shape's outline from `startFraction` to `endFraction` of its arc
    /// length — SwiftUI's `trim(from:to:)` (ruling `PG-A`). Animatable: see
    /// ``TrimmedShape``.
    public func trim(from startFraction: Double = 0, to endFraction: Double = 1) -> TrimmedShape<Self> {
        TrimmedShape(shape: self, startFraction: startFraction, endFraction: endFraction)
    }
}

/// A shape whose paint-time numbers animate (`PG-F`): it returns itself with
/// the values for this frame.
protocol PaintAnimatedShape {
    @MainActor func animatedForPaint(_ id: GlobalElementID, pass: PaintPass) -> Self
}

/// `shape` with its animating numbers at this frame — `shape` itself for every
/// shape that animates nothing.
@MainActor
func shapeForPaint<S: Shape>(_ shape: S, _ id: GlobalElementID, pass: PaintPass) -> S {
    guard let animating = shape as? any PaintAnimatedShape else { return shape }
    return (animating.animatedForPaint(id, pass: pass) as? S) ?? shape
}

extension TrimmedShape: PaintAnimatedShape {
    @MainActor
    func animatedForPaint(_ id: GlobalElementID, pass: PaintPass) -> TrimmedShape<Base> {
        let wide = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude
        let values = animatedNumbers([startFraction, endFraction], at: layerAnimationKey(id, "trim"),
                                     frame: pass.frame, transaction: pass.transaction ?? Animation.pendingTransaction,
                                     range: wide)
        var out = self
        out.startFraction = values[0] ?? startFraction
        out.endFraction = values[1] ?? endFraction
        out.shape = shapeForPaint(shape, .child(of: id, at: 0, name: ElementID("$anim-trim.base")), pass: pass)
        return out
    }
}
