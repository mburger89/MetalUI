import Foundation
import MetalUICore
import MetalUILayout

// `Shape.trim(from:to:)` (item R3-8, rulings `PG-A`, `PG-F`; `VA-` since R4-3 PR D). SwiftUI's `_TrimmedShape` is
// `Animatable`; so is this one, over the base's data and the two fractions scaled by 128, and
// `shapeForPaint(_:_:pass:)` runs that data through a track in the window's `AnimationStore`.

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

    /// The base shape's data, then the two fractions **scaled by 128** — SwiftUI's `_TrimmedShape`
    /// (`VA3a`, `VA3a2`: an end fraction 0 to 1 reads a delta of 128). A power of two, so the scaling is
    /// exact; a trim of a trim nests (`VA3e`).
    public typealias AnimatableData = AnimatablePair<Base.AnimatableData, AnimatablePair<CGFloat, CGFloat>>

    /// The base's data and the start and end fractions, each times 128.
    public nonisolated var animatableData: AnimatablePair<Base.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shape.animatableData, AnimatablePair(startFraction * 128, endFraction * 128)) }
        set {
            shape.animatableData = newValue.first
            startFraction = Double(newValue.second.first) / 128
            endFraction = Double(newValue.second.second) / 128
        }
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

/// `shape` with its ``Animatable/animatableData`` at this frame (`PG-F`, `VA-D`) — `shape` itself for every
/// shape that animates nothing (``EmptyAnimatableData``), which touches no track and allocates nothing.
@MainActor
func shapeForPaint<S: Shape>(_ shape: S, _ id: GlobalElementID, pass: PaintPass) -> S {
    guard ObjectIdentifier(S.AnimatableData.self) != ObjectIdentifier(EmptyAnimatableData.self) else { return shape }
    let declared = shape.animatableData
    let animated = animatedVector(declared, at: layerAnimationKey(id, "animatable"), frame: pass.frame,
                                  transaction: pass.transaction ?? Animation.pendingTransaction)
    // The setter runs only for a frame that differs, so a settled shape never calls a conformer's setter.
    guard animated != declared else { return shape }
    var out = shape
    out.animatableData = animated
    return out
}
