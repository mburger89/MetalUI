import MetalUICore
import MetalUILayout
@testable import MetalUI

// Width-dependent leaves for the variable-height `List` (spec §3.5, ruling
// `VL-Q`): a deterministic stand-in for wrapping text — **no `Text` fixture**
// (TX-B). Each answers `height = area / width` at the width it is offered, and
// `naturalWidth` at a nil width, so a row's height depends on the width it was
// measured at exactly as a wrapping paragraph's does, with literals a test can
// derive in its comment.

/// Where a fixture leaf records its prepaint bounds, by name.
@MainActor
final class LeafBoundsLog {
    var byName: [String: Bounds<Pixels>] = [:]
}

/// `height = area / width`; width the offered width, else `naturalWidth`. A
/// native leaf, for proposal content (`ProposalLayoutContainer`, `VStack`).
struct AreaLeaf: ProposalElement {
    var area: Double
    var naturalWidth: Double = 100
    var name: String = ""
    var log: LeafBoundsLog?

    init(_ area: Double, naturalWidth: Double = 100, name: String = "", log: LeafBoundsLog? = nil) {
        self.area = area
        self.naturalWidth = naturalWidth
        self.name = name
        self.log = log
    }

    /// The answer at `proposal` — shared with `LoweredAreaLeaf`.
    nonisolated static func measure(area: Double, naturalWidth: Double, _ proposal: ProposedSize) -> LayoutMeasurement {
        let offered = proposal.width ?? naturalWidth
        let width = offered.isFinite ? offered : naturalWidth
        let height = width > 0 ? area / width : 0
        return LayoutMeasurement(size: SizeD(width: width, height: height))
    }

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let area = area, natural = naturalWidth
        return (pass.requestNativeLeaf { Self.measure(area: area, naturalWidth: natural, $0) }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        log?.byName[name] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

/// `AreaLeaf` registered through `lowerLegacyLeaf`, for legacy content — a
/// `List` row's `Box` (`ListLoweringTests.LoweredProbeLeaf`'s reason: a row's
/// content is stretched by its row `Box` only when it records a lowered item).
struct LoweredAreaLeaf: Element {
    var area: Double
    var naturalWidth: Double = 100
    var name: String = ""
    var log: LeafBoundsLog?

    init(_ area: Double, naturalWidth: Double = 100, name: String = "", log: LeafBoundsLog? = nil) {
        self.area = area
        self.naturalWidth = naturalWidth
        self.name = name
        self.log = log
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let area = area, natural = naturalWidth
        let node = pass.lowerLegacyLeaf(Style(), declared: Style(), site: .box) {
            pass.frame.requestNativeLeaf { AreaLeaf.measure(area: area, naturalWidth: natural, $0) }
        }
        return (node, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        log?.byName[name] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}
