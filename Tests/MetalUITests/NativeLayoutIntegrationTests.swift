import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIRender
import MetalUIText
@testable import MetalUI

private final class NativeLayoutProbe: @unchecked Sendable {
    var measureCalls = 0
    var proposals: [ProposedSize] = []
    var prepaintBounds: Bounds<Pixels>?
    var boundsByName: [String: Bounds<Pixels>] = [:]
}

@MainActor
private final class NativeTapProbe {
    var count = 0
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
        let node = pass.requestNativeLeaf { proposal in
            probe.proposals.append(proposal)
            return LayoutMeasurement(size: size)
        }
        return (node, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        if name == "trailing" { probe.prepaintBounds = bounds }
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

extension NativeProbeLeaf: ProposalElementGroup {}

/// A leaf whose width is its proposal capped at its ideal width. This mirrors
/// the flexible probe used by the companion SwiftUI priority measurement.
private struct NativeFlexibleProbe: Element {
    let idealWidth: Double
    let probe: NativeLayoutProbe
    let name: String

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let node = pass.requestNativeLeaf { proposal in
            probe.proposals.append(proposal)
            return LayoutMeasurement(size: SizeD(width: Swift.min(idealWidth, proposal.width ?? idealWidth), height: 10))
        }
        return (node, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        probe.boundsByName[name] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

extension NativeFlexibleProbe: ProposalElementGroup {}

/// The vertical counterpart of ``NativeFlexibleProbe``. It is kept separate
/// so each priority test makes the flexible axis explicit.
private struct NativeVerticallyFlexibleProbe: Element {
    let idealHeight: Double
    let probe: NativeLayoutProbe
    let name: String

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let node = pass.requestNativeLeaf { proposal in
            probe.proposals.append(proposal)
            return LayoutMeasurement(size: SizeD(width: 10, height: Swift.min(idealHeight, proposal.height ?? idealHeight)))
        }
        return (node, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        probe.boundsByName[name] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

extension NativeVerticallyFlexibleProbe: ProposalElementGroup {}

private struct NativeFillProbe: Element {
    let probe: NativeLayoutProbe

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let node = pass.requestNativeLeaf { proposal in
            LayoutMeasurement(size: proposal.replacingUnspecifiedDimensions(by: .zero))
        }
        return (node, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        probe.prepaintBounds = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

extension NativeFillProbe: ProposalElementGroup {}

private struct NativeProposalProbe: Element {
    let expectedProposal: ProposedSize
    let probe: NativeLayoutProbe

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let node = pass.requestNativeLeaf { proposal in
            #expect(proposal == expectedProposal)
            return LayoutMeasurement(size: SizeD(width: 30, height: 10))
        }
        return (node, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        probe.prepaintBounds = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

extension NativeProposalProbe: ProposalElementGroup {}

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
@Test func aProposalScrollViewMeasuresContentWithAnUnspecifiedScrollingAxis() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(90), height: Pixels(50)), scaleFactor: 1)
    var root = ProposalScrollView(.vertical) {
        VStack(spacing: Pixels(0)) {
            NativeProbeLeaf(size: SizeD(width: 90, height: 160), probe: probe, name: "trailing")
        }
    }

    frame.render(&root)

    #expect(probe.proposals.contains(ProposedSize(width: 90, height: nil)))
    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                           size: Size(width: Pixels(90), height: Pixels(160))))
}

@MainActor
@Test func aProposalScrollViewForwardsItsHorizontalAxisToTheNativeViewport() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(90), height: Pixels(50)), scaleFactor: 1)
    var root = ProposalScrollView(.horizontal) {
        HStack(spacing: Pixels(0)) {
            NativeProbeLeaf(size: SizeD(width: 160, height: 50), probe: probe, name: "trailing")
        }
    }

    frame.render(&root)

    #expect(probe.proposals.contains(ProposedSize(width: nil, height: 50)))
    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                           size: Size(width: Pixels(160), height: Pixels(50))))
}

@MainActor
@Test func aProposalScrollViewStacksDirectChildrenWithSwiftUIsDefaultSpacing() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(90), height: Pixels(50)), scaleFactor: 1)
    var root = ProposalScrollView(.vertical) {
        NativeProbeLeaf(size: SizeD(width: 90, height: 20), probe: probe, name: "leading")
        NativeProbeLeaf(size: SizeD(width: 90, height: 30), probe: probe, name: "trailing")
    }

    frame.render(&root)

    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(28)),
                                           size: Size(width: Pixels(90), height: Pixels(30))))
}

@MainActor
@Test func aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(90), height: Pixels(50)), scaleFactor: 1)
    var root = ProposalScrollView(.horizontal) {
        NativeProbeLeaf(size: SizeD(width: 20, height: 20), probe: probe, name: "leading")
        NativeProbeLeaf(size: SizeD(width: 30, height: 30), probe: probe, name: "trailing")
    }

    frame.render(&root)

    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(28)),
                                           size: Size(width: Pixels(30), height: Pixels(30))))
}

@MainActor
@Test func aProposalScrollViewsCornerRadiusMasksItsScrollingContent() throws {
    let frame = Frame(contentSize: Size(width: Pixels(50), height: Pixels(30)), scaleFactor: 1)
    var root = ProposalScrollView(.vertical) {
        VStack(spacing: Pixels(0)) {
            Rectangle(width: Pixels(50), height: Pixels(20), color: .accent)
            Rectangle(width: Pixels(50), height: Pixels(20), color: .surfaceSecondary)
        }
    }
    .cornerRadius(Pixels(14))

    frame.render(&root)

    let rects = frame.finalizedScene().rects
    try #require(rects.count == 2)
    for rect in rects {
        #expect(rect.contentMask.origin.x == 0)
        #expect(rect.contentMask.origin.y == 0)
        #expect(rect.contentMask.size.width == 50)
        #expect(rect.contentMask.size.height == 30)
        #expect(rect.maskCornerRadii.topLeft == 14)
        #expect(rect.maskCornerRadii.topRight == 14)
        #expect(rect.maskCornerRadii.bottomRight == 14)
        #expect(rect.maskCornerRadii.bottomLeft == 14)
    }
}

@MainActor
@Test func aWheelEventInsideAProposalScrollViewUpdatesItsOffset() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120) {
        ProposalScrollView(.vertical, elementID: ElementID("proposal-list")) {
            VStack(spacing: Pixels(0)) {
                Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
            }
        }
    }
    window.drawFrameIfNeeded()
    let region = try #require(window.lastScrollRegions.first)

    platformWindow.simulateInput(.scrollWheel(ScrollEvent(
        position: Point(x: Pixels(60), y: Pixels(60)),
        delta: Point(x: Pixels(0), y: Pixels(-37))
    )))

    #expect(window.stateTable.peek(region.id, as: ScrollState.self)?.offset == 37)
}

@MainActor
@Test func aPublicHStackFormsAnAllProposalLayoutSubtreeAndPlacesItsSpacer() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(40)), scaleFactor: 1)
    var root = HStack(spacing: Pixels(5)) {
        NativeProbeLeaf(size: SizeD(width: 30, height: 10), probe: probe, name: "leading")
        Spacer(minLength: Pixels(10))
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: probe, name: "trailing")
    }

    frame.render(&root)

    #expect(frame.tree.nodeCount == 4)
    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(80), y: Pixels(15)),
                                           size: Size(width: Pixels(20), height: Pixels(10))))
}

/// Layout priority changes how a constrained stack divides flexible siblings;
/// it must not make a `Spacer` stop claiming the remaining unconstrained space.
@MainActor
@Test func layoutPriorityPreservesASpacersFlexibleExpansion() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(40)), scaleFactor: 1)
    var root = HStack(spacing: Pixels(5)) {
        NativeProbeLeaf(size: SizeD(width: 30, height: 10), probe: probe, name: "leading")
        Spacer(minLength: Pixels(10)).layoutPriority(1)
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: probe, name: "trailing")
    }

    frame.render(&root)

    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(80), y: Pixels(15)),
                                           size: Size(width: Pixels(20), height: Pixels(10))))
}

/// A macOS SwiftUI probe finds that an unspecified `.frame(idealWidth: 80)`
/// proposes 80pt to a 20pt child and itself reports 80pt. HStack makes the
/// otherwise-unspecified main-axis proposal observable through its sibling.
@MainActor
@Test func anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(40)), scaleFactor: 1)
    var root = HStack(spacing: Pixels(0)) {
        ProposalFrame(idealWidth: Pixels(80)) {
            NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: probe, name: "leading")
        }
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: probe, name: "trailing")
    }

    frame.render(&root)

    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(80), y: Pixels(15)),
                                           size: Size(width: Pixels(20), height: Pixels(10))))
}

/// The companion SwiftUI probe reports the same rule for `.frame(idealHeight:)`.
@MainActor
@Test func anIdealFrameHeightBecomesItsOuterHeightWhenTheAxisIsUnspecified() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(40), height: Pixels(100)), scaleFactor: 1)
    var root = VStack(spacing: Pixels(0)) {
        ProposalFrame(idealHeight: Pixels(80)) {
            NativeProbeLeaf(size: SizeD(width: 10, height: 20), probe: probe, name: "leading")
        }
        NativeProbeLeaf(size: SizeD(width: 10, height: 20), probe: probe, name: "trailing")
    }

    frame.render(&root)

    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(15), y: Pixels(80)),
                                           size: Size(width: Pixels(10), height: Pixels(20))))
}

/// The default stack gap is a platform metric, not an accidental zero. The
/// recorded SwiftUI HStack probe measures 8pt; the explicit-zero control makes
/// a default implementation that simply forgot to set a gap visibly wrong.
@MainActor
@Test func hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt() {
    let defaultProbe = NativeLayoutProbe()
    let zeroProbe = NativeLayoutProbe()
    let defaultFrame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(40)), scaleFactor: 1)
    let zeroFrame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(40)), scaleFactor: 1)
    var defaultStack = HStack {
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: defaultProbe, name: "leading")
        NativeProbeLeaf(size: SizeD(width: 30, height: 10), probe: defaultProbe, name: "trailing")
    }
    var zeroStack = HStack(spacing: Pixels(0)) {
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: zeroProbe, name: "leading")
        NativeProbeLeaf(size: SizeD(width: 30, height: 10), probe: zeroProbe, name: "trailing")
    }

    defaultFrame.render(&defaultStack)
    zeroFrame.render(&zeroStack)

    #expect(defaultProbe.prepaintBounds?.origin.x == Pixels(28),
            "the default 8pt gap follows the 20pt leading item")
    #expect(zeroProbe.prepaintBounds?.origin.x == Pixels(20),
            "an explicit zero opts out of the platform default")
}

/// A macOS SwiftUI probe gives `HStack { 10pt; Spacer(minLength: 30); 10pt }`
/// a 50pt response even when its parent offers 20pt. The spacer's minimum is
/// a floor, not a request that stack compression may discard.
@MainActor
@Test func spacerMinimumLengthSurvivesAConstrainedStackProposal() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(20), height: Pixels(40)), scaleFactor: 1)
    var root = HStack(spacing: Pixels(0)) {
        NativeProbeLeaf(size: SizeD(width: 10, height: 10), probe: probe, name: "leading")
        Spacer(minLength: Pixels(30))
        NativeProbeLeaf(size: SizeD(width: 10, height: 10), probe: probe, name: "trailing")
    }

    frame.render(&root)

    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(40), y: Pixels(15)),
                                           size: Size(width: Pixels(10), height: Pixels(10))))
}

/// A macOS SwiftUI `Layout` probe with two 80pt-flexible children in a 100pt
/// zero-gap HStack receives 50pt proposals for both children at equal priority.
@MainActor
@Test func hStackDividesAConstrainedProposalAmongEqualPriorityFlexibleChildren() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(10)), scaleFactor: 1)
    var root = HStack(spacing: Pixels(0)) {
        NativeFlexibleProbe(idealWidth: 80, probe: probe, name: "first")
        NativeFlexibleProbe(idealWidth: 80, probe: probe, name: "second")
    }

    frame.render(&root)

    #expect(probe.boundsByName["first"] == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                                    size: Size(width: Pixels(50), height: Pixels(10))))
    #expect(probe.boundsByName["second"] == Bounds(origin: Point(x: Pixels(50), y: Pixels(0)),
                                                     size: Size(width: Pixels(50), height: Pixels(10))))
}

/// The same SwiftUI probe gives a priority-one child its 80pt ideal width
/// before proposing the 20pt remainder to its default-priority sibling.
@MainActor
@Test func hStackHonoursHigherLayoutPriorityBeforeCompressingItsSibling() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(10)), scaleFactor: 1)
    var root = HStack(spacing: Pixels(0)) {
        NativeFlexibleProbe(idealWidth: 80, probe: probe, name: "first").layoutPriority(1)
        NativeFlexibleProbe(idealWidth: 80, probe: probe, name: "second")
    }

    frame.render(&root)

    #expect(probe.boundsByName["first"] == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                                    size: Size(width: Pixels(80), height: Pixels(10))))
    #expect(probe.boundsByName["second"] == Bounds(origin: Point(x: Pixels(80), y: Pixels(0)),
                                                     size: Size(width: Pixels(20), height: Pixels(10))))
}

/// The vertical custom-Layout probe produces the same 50/50 allocation as
/// HStack for equal-priority flexible children under a 100pt proposal.
@MainActor
@Test func vStackDividesAConstrainedProposalAmongEqualPriorityFlexibleChildren() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(10), height: Pixels(100)), scaleFactor: 1)
    var root = VStack(spacing: Pixels(0)) {
        NativeVerticallyFlexibleProbe(idealHeight: 80, probe: probe, name: "first")
        NativeVerticallyFlexibleProbe(idealHeight: 80, probe: probe, name: "second")
    }

    frame.render(&root)

    #expect(probe.boundsByName["first"] == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                                    size: Size(width: Pixels(10), height: Pixels(50))))
    #expect(probe.boundsByName["second"] == Bounds(origin: Point(x: Pixels(0), y: Pixels(50)),
                                                     size: Size(width: Pixels(10), height: Pixels(50))))
}

/// The vertical probe gives the priority-one first child its 80pt ideal height
/// before it proposes the remaining 20pt to the default-priority sibling.
@MainActor
@Test func vStackHonoursHigherLayoutPriorityBeforeCompressingItsSibling() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(10), height: Pixels(100)), scaleFactor: 1)
    var root = VStack(spacing: Pixels(0)) {
        NativeVerticallyFlexibleProbe(idealHeight: 80, probe: probe, name: "first").layoutPriority(1)
        NativeVerticallyFlexibleProbe(idealHeight: 80, probe: probe, name: "second")
    }

    frame.render(&root)

    #expect(probe.boundsByName["first"] == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                                    size: Size(width: Pixels(10), height: Pixels(80))))
    #expect(probe.boundsByName["second"] == Bounds(origin: Point(x: Pixels(0), y: Pixels(80)),
                                                     size: Size(width: Pixels(10), height: Pixels(20))))
}

/// The companion macOS SwiftUI probe hosts 20 by 10 and 20 by 30 children in
/// a fitting `VStack` and measures 20 by 48: the 8pt difference is the default
/// vertical gap. The explicit-zero control keeps this from passing if both
/// initializers happen to share an accidental value.
@MainActor
@Test func vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt() {
    let defaultProbe = NativeLayoutProbe()
    let zeroProbe = NativeLayoutProbe()
    let defaultFrame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    let zeroFrame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    var defaultStack = VStack {
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: defaultProbe, name: "leading")
        NativeProbeLeaf(size: SizeD(width: 20, height: 30), probe: defaultProbe, name: "trailing")
    }
    var zeroStack = VStack(spacing: Pixels(0)) {
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: zeroProbe, name: "leading")
        NativeProbeLeaf(size: SizeD(width: 20, height: 30), probe: zeroProbe, name: "trailing")
    }

    defaultFrame.render(&defaultStack)
    zeroFrame.render(&zeroStack)

    #expect(defaultProbe.prepaintBounds?.origin.y == Pixels(18),
            "the default 8pt gap follows the 10pt leading item")
    #expect(zeroProbe.prepaintBounds?.origin.y == Pixels(10),
            "an explicit zero opts out of the platform default")
}

@MainActor
@Test func nativeCompositionUsesColumnFrameAndPaddingProposals() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    var root = ProposalFrame(width: Pixels(100), height: Pixels(80)) {
        Padding(Edges(top: Pixels(10), right: Pixels(20), bottom: Pixels(10), left: Pixels(20))) {
            VStack(spacing: Pixels(5)) {
                NativeProbeLeaf(size: SizeD(width: 30, height: 10), probe: probe, name: "leading")
                Spacer(minLength: Pixels(10))
                NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: probe, name: "trailing")
            }
        }
    }

    frame.render(&root)

    #expect(frame.tree.nodeCount == 6)
    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(40), y: Pixels(60)),
                                           size: Size(width: Pixels(20), height: Pixels(10))))
}

@MainActor
@Test func aNativeFillAcceptsEachWindowsCurrentProposal() {
    let compactProbe = NativeLayoutProbe()
    let expandedProbe = NativeLayoutProbe()
    let compactFrame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    let expandedFrame = Frame(contentSize: Size(width: Pixels(240), height: Pixels(160)), scaleFactor: 1)
    var compactRoot = ZStack { NativeFillProbe(probe: compactProbe) }
    var expandedRoot = ZStack { NativeFillProbe(probe: expandedProbe) }

    compactFrame.render(&compactRoot)
    expandedFrame.render(&expandedRoot)

    #expect(compactProbe.prepaintBounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                                  size: Size(width: Pixels(100), height: Pixels(80))))
    #expect(expandedProbe.prepaintBounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                                   size: Size(width: Pixels(240), height: Pixels(160))))
    #expect(Color.measurement(for: ProposedSize(width: 240, height: 160)).size ==
            SizeD(width: 240, height: 160))
    #expect(Color.measurement(for: ProposedSize(width: nil, height: nil)).size ==
            SizeD(width: 10, height: 10))
    #expect(Color.measurement(for: ProposedSize(width: 240, height: nil)).size ==
            SizeD(width: 240, height: 10))
    #expect(Color.measurement(for: ProposedSize(width: nil, height: 160)).size ==
            SizeD(width: 10, height: 160))
}

/// A macOS SwiftUI custom-Layout probe measures `Rectangle` as 10pt on an
/// unspecified axis and exactly the parent's concrete proposal otherwise.
@MainActor
@Test func rectangleUsesSwiftUIShapeProposalSizing() {
    #expect(Rectangle.measurement(for: ProposedSize(width: nil, height: nil)).size ==
            SizeD(width: 10, height: 10))
    #expect(Rectangle.measurement(for: ProposedSize(width: 100, height: 80)).size ==
            SizeD(width: 100, height: 80))
    #expect(Rectangle.measurement(for: ProposedSize(width: 100, height: nil)).size ==
            SizeD(width: 100, height: 10))
    #expect(Rectangle.measurement(for: ProposedSize(width: nil, height: 80)).size ==
            SizeD(width: 10, height: 80))

    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    var root = ZStack { Rectangle(color: .accent) }
    frame.render(&root)
    let rect = frame.finalizedScene().rects[0]
    #expect(rect.bounds.size.width == 100)
    #expect(rect.bounds.size.height == 80)
}

/// A macOS SwiftUI custom-Layout probe measures `Text` at its intrinsic width
/// when width is unspecified, then rewraps it for a concrete width; the height
/// proposal itself does not change that text measurement.
@MainActor
@Test func proposalTextUsesWidthDrivenSwiftUIMeasurement() {
    let cache = ShapingCache()
    let font = cache.resolveFont(family: nil, size: 13)
    cache.registerFont(font)
    let unwrapped = proposalTextMeasurement("SwiftUI proposal measurement", font: font, cache: cache,
                                            proposal: .unspecified)
    let wrapped = proposalTextMeasurement("SwiftUI proposal measurement", font: font, cache: cache,
                                          proposal: ProposedSize(width: 30, height: nil))
    let heightControl = proposalTextMeasurement("SwiftUI proposal measurement", font: font, cache: cache,
                                                proposal: ProposedSize(width: 30, height: 12))

    #expect(wrapped.size.width < unwrapped.size.width,
            "a concrete proposal width must become the wrapping question")
    #expect(wrapped.size.height > unwrapped.size.height,
            "the narrower wrapped run must report its additional line height")
    #expect(heightControl == wrapped,
            "a height proposal does not truncate or scale a SwiftUI Text measurement")
}

/// The bridge is a native leaf, so it can live in a proposal HStack and retains
/// the text renderer's glyph path rather than becoming a rectangle stand-in.
@MainActor
@Test func proposalTextParticipatesInANativeStackAndPaintsGlyphs() {
    let frame = Frame(contentSize: Size(width: Pixels(220), height: Pixels(80)), scaleFactor: 1)
    var root = HStack(spacing: Pixels(8)) {
        Text("Proposal text").proposalLayout().foregroundColor(.accent)
        Rectangle(width: Pixels(20), height: Pixels(10), color: .surface)
    }

    frame.render(&root)

    #expect(!frame.finalizedScene().glyphs.isEmpty)
}

@MainActor
@Test func nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder() {
    let probe = NativeLayoutProbe()
    let stored: ModifiedContent<NativeProbeLeaf> = NativeProbeLeaf(
        size: SizeD(width: 20, height: 10), probe: probe, name: "trailing"
    ).nativeFrame(width: Pixels(40), height: Pixels(30), alignment: .bottomTrailing)
    var root: ModifiedContent<ModifiedContent<NativeProbeLeaf>> = stored
        .padding(Edges(all: Pixels(5)))
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)

    frame.render(&root)

    #expect(frame.tree.nodeCount == 3)
    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(75), y: Pixels(65)),
                                           size: Size(width: Pixels(20), height: Pixels(10))))
}

/// A proposal-layout value selects the canonical frame overload rather than
/// the CSS-era `FrameModifier`. The explicit stored type makes overload
/// selection observable at compile time as well as checking the resulting
/// placement at runtime.
@MainActor
@Test func proposalLayoutFrameUsesTheTypedProposalWrapper() {
    let probe = NativeLayoutProbe()
    let stored: ModifiedContent<NativeProbeLeaf> = NativeProbeLeaf(
        size: SizeD(width: 20, height: 10), probe: probe, name: "trailing"
    ).frame(width: Pixels(40), height: Pixels(30), alignment: .bottomTrailing)
    var root = ZStack { stored }
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)

    frame.render(&root)

    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(50), y: Pixels(45)),
                                           size: Size(width: Pixels(20), height: Pixels(10))))
}

/// The canonical fixed-size modifier withholds only the selected proposal axis
/// from its child. This is distinct from a frame: it changes the child's
/// measurement question, not the outer bounds it is eventually placed into.
@MainActor
@Test func fixedSizeModifierWithholdsOnlyItsSelectedAxisFromTheChildProposal() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    var root = ZStack {
        NativeProposalProbe(expectedProposal: ProposedSize(width: nil, height: 80), probe: probe)
            .fixedSize(horizontal: true, vertical: false)
    }

    frame.render(&root)
    #expect(probe.prepaintBounds?.size == Size(width: Pixels(30), height: Pixels(10)))
}

/// The macOS SwiftUI probe records a 2:1 `.fit` child responding 100 by 50 to
/// a 100 by 80 proposal. Aspect-ratio is therefore a proposal modifier, not
/// the inert legacy style field: it asks its child that ratio-correct question
/// and reports the inscribed rectangle.
@MainActor
@Test func aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    var root = ZStack {
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: probe, name: "trailing")
            .aspectRatio(2)
    }

    frame.render(&root)

    #expect(probe.proposals.contains(ProposedSize(width: 100, height: 50)),
            "a 2:1 fit rectangle is inscribed in the 100 by 80 proposal")
    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(15)),
                                           size: Size(width: Pixels(100), height: Pixels(50))))
}

/// The companion macOS SwiftUI probe records a 2:1 `.fill` child responding
/// 160 by 80 to the same proposal. This makes fill's observable overflow
/// distinct from `.fit` and prevents the two modes from collapsing to one
/// min-dimension implementation.
@MainActor
@Test func aspectRatioFillCircumscribesTheParentProposalBeforeMeasuringItsChild() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    var root = ZStack {
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: probe, name: "trailing")
            .aspectRatio(2, contentMode: .fill)
    }

    frame.render(&root)

    #expect(probe.proposals.contains(ProposedSize(width: 160, height: 80)),
            "a 2:1 fill rectangle circumscribes the 100 by 80 proposal")
    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(-30), y: Pixels(0)),
                                           size: Size(width: Pixels(160), height: Pixels(80))))
}

@MainActor
@Test func chainedNativeFramesPreserveTheirDeclarationOrder() {
    let firstProbe = NativeLayoutProbe()
    let secondProbe = NativeLayoutProbe()
    let firstFrame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    let secondFrame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    var first = ZStack {
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: firstProbe, name: "trailing")
            .nativeFrame(width: Pixels(80), height: Pixels(50), alignment: .topLeading)
            .nativeFrame(width: Pixels(40), height: Pixels(30), alignment: .bottomTrailing)
    }
    var second = ZStack {
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: secondProbe, name: "trailing")
            .nativeFrame(width: Pixels(40), height: Pixels(30), alignment: .bottomTrailing)
            .nativeFrame(width: Pixels(80), height: Pixels(50), alignment: .topLeading)
    }

    firstFrame.render(&first)
    secondFrame.render(&second)

    #expect(firstProbe.prepaintBounds == Bounds(origin: Point(x: Pixels(-10), y: Pixels(5)),
                                                 size: Size(width: Pixels(20), height: Pixels(10))))
    #expect(secondProbe.prepaintBounds == Bounds(origin: Point(x: Pixels(30), y: Pixels(35)),
                                                  size: Size(width: Pixels(20), height: Pixels(10))))
}

@MainActor
@Test func builderNativeFrameExposesTheSharedFlexibleSizingSurface() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(120), height: Pixels(80)), scaleFactor: 1)
    var root = ZStack {
        ProposalFrame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity)) {
            NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: probe, name: "trailing")
        }
    }
    let rootID = GlobalElementID.child(of: nil, at: 0, name: root.elementID)
    var pass = LayoutPass(frame: frame)
    let (node, _) = root.requestLayout(rootID, pass: &pass)

    frame.computeRootLayout(root: node)

    let framedNode = frame.tree.children(node)[0]
    #expect(frame.bounds(of: framedNode) == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                             size: Size(width: Pixels(120), height: Pixels(80))))
}

@MainActor
@Test func builderFixedSizeWithholdsOnlyItsSelectedAxisFromTheChildProposal() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(120), height: Pixels(80)), scaleFactor: 1)
    var root = ProposalFrame(width: Pixels(120), height: Pixels(80)) {
        FixedSize(horizontal: true, vertical: false) {
            NativeProposalProbe(expectedProposal: ProposedSize(width: nil, height: 80), probe: probe)
        }
    }

    frame.render(&root)

    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(45), y: Pixels(35)),
                                           size: Size(width: Pixels(30), height: Pixels(10))))
}

@MainActor
@Test func nativeBackgroundWrapsTheResolvedOuterBoundsAndPaintsBeforeItsContent() {
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1,
                      theme: .light)
    var root = ZStack {
        Rectangle(width: Pixels(20), height: Pixels(10), color: .accent)
            .padding(Edges(all: Pixels(5)))
            .background(.surface)
    }

    frame.render(&root)

    let rects = frame.finalizedScene().rects
    #expect(rects.count == 2)
    #expect(rects[0].bounds.origin.x == 35)
    #expect(rects[0].bounds.origin.y == 30)
    #expect(rects[0].bounds.size.width == 30)
    #expect(rects[0].bounds.size.height == 20)
    #expect(rects[0].background.h == Theme.light.surface.h)
    #expect(rects[1].bounds.origin.x == 40)
    #expect(rects[1].bounds.origin.y == 35)
    #expect(rects[1].bounds.size.width == 20)
    #expect(rects[1].bounds.size.height == 10)
    #expect(rects[1].background.h == Theme.light.accent.h)
}

@MainActor
@Test func builderNativeBackgroundPaintsBeneathItsNativeChild() {
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1,
                      theme: .light)
    var root = ZStack {
        Background(.surface) {
            Rectangle(width: Pixels(20), height: Pixels(10), color: .accent)
        }
    }

    frame.render(&root)

    let rects = frame.finalizedScene().rects
    #expect(rects.count == 2)
    #expect(rects[0].background.h == Theme.light.surface.h)
    #expect(rects[1].background.h == Theme.light.accent.h)
}

@MainActor
@Test func nativeOverlayIsMeasuredAgainstItsPrimaryAndDoesNotEnlargeIt() {
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    var root = ZStack {
        Rectangle(width: Pixels(20), height: Pixels(10), color: .accent)
            .overlay(alignment: .bottomTrailing) {
                Rectangle(width: Pixels(50), height: Pixels(40), color: .separator)
            }
    }

    frame.render(&root)

    let rects = frame.finalizedScene().rects
    #expect(rects.count == 2)
    #expect(rects[0].bounds.origin.x == 40)
    #expect(rects[0].bounds.origin.y == 35)
    #expect(rects[0].bounds.size.width == 20)
    #expect(rects[0].bounds.size.height == 10)
    #expect(rects[1].bounds.origin.x == 10)
    #expect(rects[1].bounds.origin.y == 5)
    #expect(rects[1].bounds.size.width == 50)
    #expect(rects[1].bounds.size.height == 40)
}

@MainActor
@Test func nativeClipMasksOverflowingContentToItsOuterFrame() {
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    var root = ZStack {
        Rectangle(width: Pixels(50), height: Pixels(40), color: .accent)
            .nativeFrame(width: Pixels(20), height: Pixels(10))
            .clip(cornerRadius: Pixels(3))
    }

    frame.render(&root)

    let rect = frame.finalizedScene().rects[0]
    #expect(rect.bounds.origin.x == 25)
    #expect(rect.bounds.origin.y == 20)
    #expect(rect.contentMask.origin.x == 40)
    #expect(rect.contentMask.origin.y == 35)
    #expect(rect.contentMask.size.width == 20)
    #expect(rect.contentMask.size.height == 10)
    #expect(rect.maskCornerRadii.topLeft == 3)
}

@MainActor
@Test func nativeBorderPaintsOverContentWithoutChangingItsFrame() {
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 2,
                      theme: .light)
    var root = ZStack {
        Rectangle(width: Pixels(20), height: Pixels(10), color: .accent)
            .border(.separator, width: Pixels(2), cornerRadius: Pixels(3))
    }

    frame.render(&root)

    let rects = frame.finalizedScene().rects
    #expect(rects.count == 2)
    #expect(rects[0].bounds.size.width == 40)
    #expect(rects[0].bounds.size.height == 20)
    #expect(rects[0].background.h == Theme.light.accent.h)
    #expect(rects[1].background.a == 0)
    #expect(rects[1].borderColor.h == Theme.light.separator.h)
    #expect(rects[1].borderWidths.top == 4)
    #expect(rects[1].borderWidths.right == 4)
    #expect(rects[1].cornerRadii.topLeft == 6)
}

@MainActor
@Test func opacityMultipliesItsDescendantsPaintAlpha() {
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1,
                      theme: .light)
    var root = ZStack {
        Rectangle(width: Pixels(20), height: Pixels(10), color: .accent)
            .opacity(0.35)
    }

    frame.render(&root)

    let rect = frame.finalizedScene().rects[0]
    #expect(rect.background.a == Theme.light.accent.a * 0.35)
}

@MainActor
@Test func onTapRegistersTheResolvedNativeBoundsAsAHittableTarget() {
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    let stored: OnTapModifier<Rectangle> = Rectangle(
        width: Pixels(20), height: Pixels(10), color: .accent
    ).onTap {}
    var root = ZStack {
        stored
    }

    frame.render(&root)

    #expect(frame.topmostHitbox(at: Point(x: Pixels(50), y: Pixels(40))) != nil)
    #expect(frame.topmostHitbox(at: Point(x: Pixels(20), y: Pixels(20))) == nil)
}

/// The hover affordance belongs to the tappable wrapper rather than its native
/// child: it is visible only after the real window pointer path has resolved
/// that wrapper's hitbox. The cold/hovered comparison prevents an implementation
/// that merely paints the affordance permanently from satisfying the test.
@MainActor
@Test func onTapPaintsItsHoverOverlayOnlyWhenThePointerIsOverItsResolvedBounds() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        ZStack {
            Rectangle(width: Pixels(40), height: Pixels(40), color: .accent)
                .onTap(hoverColor: .surface) {}
        }
    }

    window.drawFrameIfNeeded()
    #expect(window.lastScene.rects.count == 1,
            "the resting native control paints only its content")

    platformWindow.simulateInput(.mouseMoved(MouseEvent(position: Point(x: Pixels(50), y: Pixels(50)))))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()

    let overlay = try #require(window.lastScene.rects.last)
    #expect(window.lastScene.rects.count == 2,
            "the resolved hover adds one paint-only overlay above the content")
    #expect(overlay.bounds.size.width == 40)
    #expect(overlay.bounds.size.height == 40)
    #expect(overlay.background.h == window.theme[.surface].h)
    #expect(overlay.background.a == window.theme[.surface].a * 0.22)
}

/// A native hit-testing wrapper scopes through a nested gesture. It must remove
/// the pointer target without suppressing paint or changing the native layout
/// node; an outer wrapper that only ignores its own handlers would leave this
/// descendant tappable.
@MainActor
@Test func allowsHitTestingFalsePreventsDescendantOnTapDispatch() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let probe = NativeTapProbe()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        ZStack {
            Rectangle(width: Pixels(40), height: Pixels(40), color: .accent)
                .onTap { probe.count += 1 }
                .allowsHitTesting(false)
        }
    }

    window.drawFrameIfNeeded()
    #expect(window.lastHitboxes.isEmpty,
            "a disabled native subtree registers no opaque pointer target")

    let center = Point(x: Pixels(50), y: Pixels(50))
    platformWindow.simulateInput(.mouseDown(MouseEvent(position: center)))
    platformWindow.simulateInput(.mouseUp(MouseEvent(position: center)))
    #expect(probe.count == 0,
            "the gesture receives neither half of a click while hit testing is disabled")
}
