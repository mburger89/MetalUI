import MetalUIShaderTypes

/// Primitives accumulated during a frame's paint phase.
///
/// M0 has a single primitive type. The `order` field and `finalize()` exist now
/// so z-ordering semantics are fixed before more primitives arrive (spec 7.3).
public struct Scene: Sendable {
    public private(set) var rects: [MUIRect] = []

    public init() {}

    public var isEmpty: Bool { rects.isEmpty }

    public mutating func insert(_ rect: MUIRect) {
        rects.append(rect)
    }

    public mutating func clear() {
        rects.removeAll(keepingCapacity: true)
    }

    /// Sorts primitives into paint order. Stable, so equal orders keep
    /// insertion sequence — painters at the same layer must stack predictably.
    public mutating func finalize() {
        rects = rects.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }
}
