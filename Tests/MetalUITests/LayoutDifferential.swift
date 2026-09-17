import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIRender
@testable import MetalUI

// Test support for plan task 7's differential harness
// (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §5.2, ruling
// LR-D). A tree is rendered twice — under the legacy layout authority, then under
// the proposal authority with diagnostics on — inside `DifferentialRoot`, and the
// two frames are compared element by element (`Frame.elementBounds`) and
// observation by observation (scene bytes, hitboxes, accessibility records with
// their geometry, `StateTable` ids).
//
// `compareInWindows` (the same comparison through a real `Window`) is lane 5's.

/// The harness root: a top-leading, fixed-size root on both sides (ruling LR-D).
///
/// - legacy authority: one `display: .stack` node sized `width`×`height`, aligned
///   `.topLeading` (what `Stack(alignment: .topLeading) { … }.width(W).height(H)`
///   registers);
/// - proposal authority: a native `.topLeading` overlay of the content inside a
///   native fixed `width`×`height` frame aligned `.topLeading`.
///
/// **Its own divergence** (spec §5.3): the legacy `Stack` offers a child
/// fit-content, the overlay offers `width`×`height` (divergence 53), so a wrapping
/// or greedy child placed directly under this root disagrees because of the root.
/// Put such content in a container of its own.
@MainActor
struct DifferentialRoot<Content: ElementGroup>: Element {
    var width: Float
    var height: Float
    var content: Content

    init(width: Float, height: Float, @ElementBuilder content: () -> Content) {
        self.width = width
        self.height = height
        self.content = content()
    }

    struct Layout {
        var content: Content.GroupLayout
    }

    mutating func requestLayout(_ id: GlobalElementID,
                                pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestGroupLayout(under: id, at: &cursor,
                                                                   pass: &pass)
        if pass.lowersToProposal {
            let overlay = pass.frame.requestNativeOverlay(children: children,
                                                          alignment: .topLeading)
            let node = pass.frame.requestNativeFrame(child: overlay,
                                                     width: Double(width), height: Double(height),
                                                     alignment: .topLeading)
            return (node, Layout(content: contentLayout))
        }
        var style = Style()
        style.display = .stack
        style.alignItems = Alignment.topLeading.blockAxis
        style.justifyItems = Alignment.topLeading.inlineAxis
        style.size = Size(width: .length(.pixels(Pixels(width))),
                          height: .length(.pixels(Pixels(height))))
        return (pass.frame.requestNode(style: style, children: children), Layout(content: contentLayout))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Layout, pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                        pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// A fixed-size leaf that registers a legacy leaf under the legacy authority and a
/// native leaf under the proposal authority, answering `width`×`height` on both —
/// except for the knobs, each of which makes the two authorities disagree on
/// purpose so a harness test has an arm that can fail:
///
/// - `proposalWidthOffset`: added to the width under the proposal authority only;
/// - `clickable`: an `onClick` and an accessibility label, registered in `prepaint`;
/// - `mintsProbeStateUnder`: a `$probe` state entry minted only under that authority;
/// - `onLayout`: called with `pass.lowersToProposal` during layout;
/// - `paintsOnRaisedLayerUnder`: its fill is emitted inside `Frame.pushLayer()`
///   only under that authority, so the emitted rect bytes are identical and only
///   the finalized paint order (layer sorts first) differs.
///
/// It paints a fill over its bounds, so its rect reaches the scene.
@MainActor
struct ProbeLeaf: Element {
    var width: Float
    var height: Float
    var proposalWidthOffset: Float = 0
    var clickable = false
    var mintsProbeStateUnder: LayoutAuthority? = nil
    var onLayout: (@MainActor (Bool) -> Void)? = nil
    var paintsOnRaisedLayerUnder: LayoutAuthority? = nil

    mutating func requestLayout(_ id: GlobalElementID,
                                pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        onLayout?(pass.lowersToProposal)
        let authority: LayoutAuthority = pass.lowersToProposal ? .proposal : .legacy
        if mintsProbeStateUnder == authority {
            pass.withState(GlobalElementID.child(of: id, at: 0, name: ElementID("$probe")), initial: 0) { _ in }
        }
        let h = Double(height)
        if pass.lowersToProposal {
            let w = Double(width + proposalWidthOffset)
            return (pass.frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: w, height: h)) }, ())
        }
        let w = Double(width)
        return (pass.requestLeaf(style: Style()) { _, _ in SizeD(width: w, height: h) }, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {
        guard clickable else { return }
        var handlers = Handlers()
        handlers.onClick = {}
        handlers.axNode.label = "probe"
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        let raised = paintsOnRaisedLayerUnder == pass.frame.layoutAuthority
        if raised { pass.frame.pushLayer() }
        pass.fill(bounds, color: Hsla(h: 0.6, s: 0.5, l: 0.5))
        if raised { pass.frame.popLayer() }
    }
}

/// Renders `DifferentialRoot { make() }` under each authority and compares.
@MainActor
enum LayoutDifferential {
    struct Report {
        /// Ids recorded under either authority (their union).
        var elements: Int
        var agreeing: [GlobalElementID]
        var disagreeing: [(id: GlobalElementID, legacy: Bounds<Pixels>, lowered: Bounds<Pixels>)]
        var legacyOnly: [GlobalElementID]
        var loweredOnly: [GlobalElementID]
        /// The proposal frame's diagnostics, in registration order.
        var unlowerable: [UnlowerableField]
        /// Scene rects and glyphs, byte for byte.
        var scenesEqual: Bool
        /// Id, bounds, layer and opacity of every hitbox, in order.
        var hitboxesEqual: Bool
        /// Id, declared node, text and geometry of every accessibility record, in order.
        var accessibilityEqual: Bool
        /// The two `StateTable`s' ids.
        var stateSlotsEqual: Bool
        /// Each side's element bounds, for literal assertions.
        var legacyBounds: [GlobalElementID: Bounds<Pixels>]
        var loweredBounds: [GlobalElementID: Bounds<Pixels>]
    }

    /// The frame one side renders, kept for a test that needs more than the report.
    static func render<Content: ElementGroup>(authority: LayoutAuthority,
                                              width: Float, height: Float, scaleFactor: Float = 1,
                                              @ElementBuilder _ make: @MainActor () -> Content) -> Frame {
        var root = DifferentialRoot(width: width, height: height, content: make)
        let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)),
                          scaleFactor: scaleFactor,
                          stateTable: StateTable(),
                          collectsAccessibility: true,
                          layoutAuthority: authority,
                          reportsUnlowerableFields: authority == .proposal,
                          recordsElementBounds: true)
        frame.render(&root)
        return frame
    }

    static func compare<Content: ElementGroup>(width: Float, height: Float, scaleFactor: Float = 1,
                                               @ElementBuilder _ make: @MainActor () -> Content) -> Report {
        let legacy = render(authority: .legacy, width: width, height: height,
                            scaleFactor: scaleFactor, make)
        let lowered = render(authority: .proposal, width: width, height: height,
                             scaleFactor: scaleFactor, make)
        return report(legacy: legacy, lowered: lowered)
    }

    static func report(legacy: Frame, lowered: Frame) -> Report {
        let a = legacy.elementBounds, b = lowered.elementBounds
        let ids: [GlobalElementID] = Set(a.keys).union(b.keys).sorted { (x: GlobalElementID, y: GlobalElementID) in "\(x)" < "\(y)" }
        var agreeing: [GlobalElementID] = []
        var disagreeing: [(id: GlobalElementID, legacy: Bounds<Pixels>, lowered: Bounds<Pixels>)] = []
        var legacyOnly: [GlobalElementID] = [], loweredOnly: [GlobalElementID] = []
        for id in ids {
            switch (a[id], b[id]) {
            case let (x?, y?):
                if x == y { agreeing.append(id) } else { disagreeing.append((id, x, y)) }
            case (_?, nil): legacyOnly.append(id)
            case (nil, _?): loweredOnly.append(id)
            case (nil, nil): break
            }
        }
        func bytes<T>(_ xs: [T]) -> [UInt8] { xs.withUnsafeBytes { Array($0) } }
        let scenesEqual = bytes(legacy.scene.rects) == bytes(lowered.scene.rects)
            && bytes(legacy.scene.glyphs) == bytes(lowered.scene.glyphs)
        func hitboxKey(_ frame: Frame) -> [String] {
            frame.hitboxes.map { "\($0.id)|\($0.bounds)|\($0.layer)|\($0.opaque)" }
        }
        func axKey(_ frame: Frame) -> [String] {
            frame.axEmissions.map {
                "\($0.id)|\($0.declared)|\(String(describing: $0.text))|\($0.geometry)"
            }
        }
        return Report(elements: ids.count, agreeing: agreeing, disagreeing: disagreeing,
                      legacyOnly: legacyOnly, loweredOnly: loweredOnly,
                      unlowerable: lowered.unlowerableFields,
                      scenesEqual: scenesEqual,
                      hitboxesEqual: hitboxKey(legacy) == hitboxKey(lowered),
                      accessibilityEqual: axKey(legacy) == axKey(lowered),
                      stateSlotsEqual: legacy.stateTable.ids == lowered.stateTable.ids,
                      legacyBounds: a, loweredBounds: b)
    }
}
