import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

private final class NativeLayoutProbe: @unchecked Sendable {
    var measureCalls = 0
    var prepaintBounds: Bounds<Pixels>?
}

private struct NativeRoot: Element {
    let probe: NativeLayoutProbe

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let leaf = pass.requestNativeLeaf { proposal in
            probe.measureCalls += 1
            #expect(proposal == ProposedSize(width: 140, height: 90))
            return LayoutMeasurement(size: SizeD(width: 40, height: 20))
        }
        return (pass.requestNativeOverlay(children: [leaf]), ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        probe.prepaintBounds = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

private struct NativeProbeLeaf: Element {
    let size: SizeD
    let probe: NativeLayoutProbe
    let name: String

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let node = pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }
        return (node, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        if name == "trailing" { probe.prepaintBounds = bounds }
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

@MainActor
@Test func aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1)
    var root = NativeRoot(probe: probe)

    frame.render(&root)

    #expect(probe.measureCalls == 1)
    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                           size: Size(width: Pixels(140), height: Pixels(90))))
}

@MainActor
@Test func aPublicNativeRowFormsAnAllNativeSubtreeAndPlacesItsSpacer() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(40)), scaleFactor: 1)
    var root = NativeRow(spacing: Pixels(5)) {
        NativeProbeLeaf(size: SizeD(width: 30, height: 10), probe: probe, name: "leading")
        NativeSpacer(minLength: Pixels(10))
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: probe, name: "trailing")
    }

    frame.render(&root)

    #expect(frame.tree.nodeCount == 4)
    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(80), y: Pixels(15)),
                                           size: Size(width: Pixels(20), height: Pixels(10))))
}
