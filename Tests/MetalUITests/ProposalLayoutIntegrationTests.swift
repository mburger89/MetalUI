import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

private final class DiagonalProbe: @unchecked Sendable {
    var boundsByName: [String: Bounds<Pixels>] = [:]
}

/// A fixed-size proposal leaf that records its prepaint bounds by name.
private struct DiagonalProbeLeaf: Element {
    let size: SizeD
    let name: String
    let probe: DiagonalProbe

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let size = size
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        probe.boundsByName[name] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

extension DiagonalProbeLeaf: ProposalElementGroup {}

/// Places each child at the previous child's bottom-trailing corner, each at
/// its unspecified-proposal answer; answers the sum of the answers.
private struct DiagonalLayout: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified).size }
        return LayoutMeasurement(size: SizeD(width: sizes.reduce(0) { $0 + $1.width },
                                             height: sizes.reduce(0) { $0 + $1.height }))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        var corner = Point(x: bounds.x, y: bounds.y)
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified).size
            subview.place(at: corner, anchor: .topLeading, proposal: .unspecified)
            corner = Point(x: corner.x + size.width, y: corner.y + size.height)
        }
    }
}

private func bounds(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(Float(x)), y: Pixels(Float(y))),
           size: Size(width: Pixels(Float(width)), height: Pixels(Float(height))))
}

/// A `ProposalLayout` reaches the screen through `ProposalLayoutContainer` and
/// `Frame`'s native root, in all three spellings (ruling SA-F).
///
/// Hand-derived before the run, in a 140×90 frame. The root is padding with
/// top 11 and left 7, so the diagonal is stored at the padding's bounds minus
/// its insets, (7, 11, 133, 79) (record §09 hazard 4 decides the size; only
/// the origin matters here). Leaves are 20×10, 30×15 and 25×5:
/// - first at the bounds origin: (7, 11, 20, 10);
/// - second at its corner (27, 21): (27, 21, 30, 15);
/// - third at (57, 36): (57, 36, 25, 5).
@MainActor
@Test func aProposalLayoutContainerRendersThroughTheFramePipeline() {
    func expectDiagonal(_ probe: DiagonalProbe, _ spelling: String) {
        #expect(probe.boundsByName["first"] == bounds(7, 11, 20, 10), "\(spelling)")
        #expect(probe.boundsByName["second"] == bounds(27, 21, 30, 15), "\(spelling)")
        #expect(probe.boundsByName["third"] == bounds(57, 36, 25, 5), "\(spelling)")
    }
    let insets = Edges(top: Pixels(11), right: Pixels(0), bottom: Pixels(0), left: Pixels(7))

    let called = DiagonalProbe()
    var calledRoot = DiagonalLayout()() {
        DiagonalProbeLeaf(size: SizeD(width: 20, height: 10), name: "first", probe: called)
        DiagonalProbeLeaf(size: SizeD(width: 30, height: 15), name: "second", probe: called)
        DiagonalProbeLeaf(size: SizeD(width: 25, height: 5), name: "third", probe: called)
    }.padding(insets)
    Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1).render(&calledRoot)
    expectDiagonal(called, "DiagonalLayout() { … }")

    let trailing = DiagonalProbe()
    var trailingRoot = DiagonalLayout {
        DiagonalProbeLeaf(size: SizeD(width: 20, height: 10), name: "first", probe: trailing)
        DiagonalProbeLeaf(size: SizeD(width: 30, height: 15), name: "second", probe: trailing)
        DiagonalProbeLeaf(size: SizeD(width: 25, height: 5), name: "third", probe: trailing)
    }.padding(insets)
    Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1).render(&trailingRoot)
    expectDiagonal(trailing, "DiagonalLayout { … }")

    let container = DiagonalProbe()
    var containerRoot = ProposalLayoutContainer(DiagonalLayout()) {
        DiagonalProbeLeaf(size: SizeD(width: 20, height: 10), name: "first", probe: container)
        DiagonalProbeLeaf(size: SizeD(width: 30, height: 15), name: "second", probe: container)
        DiagonalProbeLeaf(size: SizeD(width: 25, height: 5), name: "third", probe: container)
    }.padding(insets)
    Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1).render(&containerRoot)
    expectDiagonal(container, "ProposalLayoutContainer(DiagonalLayout()) { … }")
}
