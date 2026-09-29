import MetalUICore
import MetalUILayout
import MetalUIScene

/// SKELETON.
public struct Image: ProposalElement {
    public enum Interpolation: Sendable, Hashable {
        case none, low, medium, high
    }

    let bitmap: ImageBitmap
    let scale: Float
    var isResizable = false
    var interpolationValue: Interpolation = .low

    public init(decorative bitmap: ImageBitmap, scale: Float) {
        self.bitmap = bitmap
        self.scale = scale
    }

    public func resizable() -> Image { self }

    public func interpolation(_ interpolation: Interpolation) -> Image {
        var copy = self
        copy.interpolationValue = interpolation
        return copy
    }

    var filter: ImageFilter { .linear }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let size = SizeD(width: Double(bitmap.width), height: Double(bitmap.height))
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }, ())
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Void, pass: inout PrepaintPass) {}

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        pass.drawImage(bitmap.texture, in: bounds, filter: filter)
    }
}
