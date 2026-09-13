import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIRender
@testable import MetalUI

private final class NativeLayoutProbe: @unchecked Sendable {
    var measureCalls = 0
    var prepaintBounds: Bounds<Pixels>?
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

@MainActor
@Test func nativeCompositionUsesColumnFrameAndPaddingProposals() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    var root = NativeFrame(width: Pixels(100), height: Pixels(80)) {
        NativePadding(Edges(top: Pixels(10), right: Pixels(20), bottom: Pixels(10), left: Pixels(20))) {
            NativeColumn(spacing: Pixels(5)) {
                NativeProbeLeaf(size: SizeD(width: 30, height: 10), probe: probe, name: "leading")
                NativeSpacer(minLength: Pixels(10))
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
    var compactRoot = NativeOverlay { NativeFillProbe(probe: compactProbe) }
    var expandedRoot = NativeOverlay { NativeFillProbe(probe: expandedProbe) }

    compactFrame.render(&compactRoot)
    expandedFrame.render(&expandedRoot)

    #expect(compactProbe.prepaintBounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                                  size: Size(width: Pixels(100), height: Pixels(80))))
    #expect(expandedProbe.prepaintBounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                                   size: Size(width: Pixels(240), height: Pixels(160))))
    #expect(NativeColorFill.measurement(for: ProposedSize(width: 240, height: 160)).size ==
            SizeD(width: 240, height: 160))
}

@MainActor
@Test func nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder() {
    let probe = NativeLayoutProbe()
    let stored: NativeModifiedContent<NativeProbeLeaf> = NativeProbeLeaf(
        size: SizeD(width: 20, height: 10), probe: probe, name: "trailing"
    ).nativeFrame(width: Pixels(40), height: Pixels(30), alignment: .bottomTrailing)
    var root: NativeModifiedContent<NativeModifiedContent<NativeProbeLeaf>> = stored
        .nativePadding(Edges(all: Pixels(5)))
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)

    frame.render(&root)

    #expect(frame.tree.nodeCount == 3)
    #expect(probe.prepaintBounds == Bounds(origin: Point(x: Pixels(75), y: Pixels(65)),
                                           size: Size(width: Pixels(20), height: Pixels(10))))
}

@MainActor
@Test func chainedNativeFramesPreserveTheirDeclarationOrder() {
    let firstProbe = NativeLayoutProbe()
    let secondProbe = NativeLayoutProbe()
    let firstFrame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    let secondFrame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    var first = NativeOverlay {
        NativeProbeLeaf(size: SizeD(width: 20, height: 10), probe: firstProbe, name: "trailing")
            .nativeFrame(width: Pixels(80), height: Pixels(50), alignment: .topLeading)
            .nativeFrame(width: Pixels(40), height: Pixels(30), alignment: .bottomTrailing)
    }
    var second = NativeOverlay {
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
    var root = NativeOverlay {
        NativeFrame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity)) {
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
@Test func builderNativeFixedSizeWithholdsOnlyItsSelectedAxisFromTheChildProposal() {
    let probe = NativeLayoutProbe()
    let frame = Frame(contentSize: Size(width: Pixels(120), height: Pixels(80)), scaleFactor: 1)
    var root = NativeFrame(width: Pixels(120), height: Pixels(80)) {
        NativeFixedSize(horizontal: true, vertical: false) {
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
    var root = NativeOverlay {
        NativeRectangle(width: Pixels(20), height: Pixels(10), color: .accent)
            .nativePadding(Edges(all: Pixels(5)))
            .nativeBackground(.surface)
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
    var root = NativeOverlay {
        NativeBackground(.surface) {
            NativeRectangle(width: Pixels(20), height: Pixels(10), color: .accent)
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
    var root = NativeOverlay {
        NativeRectangle(width: Pixels(20), height: Pixels(10), color: .accent)
            .nativeOverlay(alignment: .bottomTrailing) {
                NativeRectangle(width: Pixels(50), height: Pixels(40), color: .separator)
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
    var root = NativeOverlay {
        NativeRectangle(width: Pixels(50), height: Pixels(40), color: .accent)
            .nativeFrame(width: Pixels(20), height: Pixels(10))
            .nativeClip(cornerRadius: Pixels(3))
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
    var root = NativeOverlay {
        NativeRectangle(width: Pixels(20), height: Pixels(10), color: .accent)
            .nativeBorder(.separator, width: Pixels(2), cornerRadius: Pixels(3))
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
@Test func nativeOpacityMultipliesItsDescendantsPaintAlpha() {
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1,
                      theme: .light)
    var root = NativeOverlay {
        NativeRectangle(width: Pixels(20), height: Pixels(10), color: .accent)
            .nativeOpacity(0.35)
    }

    frame.render(&root)

    let rect = frame.finalizedScene().rects[0]
    #expect(rect.background.a == Theme.light.accent.a * 0.35)
}

@MainActor
@Test func onTapRegistersTheResolvedNativeBoundsAsAHittableTarget() {
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(80)), scaleFactor: 1)
    let stored: OnTapModifier<NativeRectangle> = NativeRectangle(
        width: Pixels(20), height: Pixels(10), color: .accent
    ).onTap {}
    var root = NativeOverlay {
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
        NativeOverlay {
            NativeRectangle(width: Pixels(40), height: Pixels(40), color: .accent)
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
        NativeOverlay {
            NativeRectangle(width: Pixels(40), height: Pixels(40), color: .accent)
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
