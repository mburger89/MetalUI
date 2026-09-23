import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIRender
import MetalUIPlatform
import Metal
@testable import MetalUI

// Test support for plan task 7's differential harness
// (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §5.2, ruling
// LR-D). A tree is rendered twice — under the legacy layout authority, then under
// the proposal authority with diagnostics on — inside `DifferentialRoot`, and the
// two frames are compared element by element (`Frame.elementBounds`) and
// observation by observation (scene bytes as emitted and as finalized, hitboxes, accessibility records with
// their geometry, `StateTable` ids).
//
// `compareInWindows` (lane 5) is the same comparison through a real `Window` per
// authority, `DifferentialRoot` as the window's root content.

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
        /// The scene, byte for byte, twice: as emitted (`Frame.scene`: rects and
        /// glyphs in emission order, each carrying its clip) and as the GPU receives
        /// it (`Frame.finalizedScene()`: rects, glyphs and `drawList`, after the
        /// `(layer, order, sequence)` sort) — so paint order, clip, layer and the
        /// rect/glyph interleave are all compared. The `drawList` clause is not
        /// separately pinned: no harness arm emits glyphs.
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
    ///
    /// **`frames` and `stateTable` exist because one frame cannot window a
    /// `List`** (ruling `LR-BY`, plan task 7 stage 4 lane 1, critic round 1
    /// defect D4). `ScrollContext.viewportExtent` is one frame stale by
    /// construction — only `ScrollChrome.resolvedOffset`'s `PrepaintPass`
    /// overload ever writes it, into the scroller's `ScrollState` — so on the
    /// first frame it is 0, `List.visibleRange` takes its
    /// `context.viewportExtent > 0` guard and returns `0..<count`, and
    /// `windowIsBounded` is false, which sends `List.prepaint` down the branch
    /// that publishes the table and **no rows**. Every `List` arm of every
    /// differential test was therefore comparing an unwindowed list, and its
    /// `accessibilityEqual` was comparing one record with one record and
    /// passing vacuously.
    ///
    /// `frames > 1` renders that many frames of ONE side over one
    /// `StateTable` — the same object a real `Window` threads across its
    /// frames — and returns the last. **An arm that relies on this owes a
    /// `try #require` that the window really is bounded and the row-record set
    /// really is non-empty**, on both sides, before it asserts anything; the
    /// anti-vacuity check is part of the arm, not a review note. Pinned by
    /// `aListInTheDifferentialHarnessReachesABoundedWindow` (`ListTests.swift`),
    /// whose mutation M1f forces `frames` back to 1.
    static func render<Content: ElementGroup>(authority: LayoutAuthority,
                                              width: Float, height: Float, scaleFactor: Float = 1,
                                              stateTable: StateTable? = nil,
                                              frames: Int = 1,
                                              @ElementBuilder _ make: @MainActor () -> Content) -> Frame {
        precondition(frames >= 1, "a side renders at least one frame")
        let table = stateTable ?? StateTable()
        var last: Frame?
        for _ in 0..<frames {
            var root = DifferentialRoot(width: width, height: height, content: make)
            let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)),
                              scaleFactor: scaleFactor,
                              stateTable: table,
                              collectsAccessibility: true,
                              layoutAuthority: authority,
                              reportsUnlowerableFields: authority == .proposal,
                              recordsElementBounds: true)
            frame.render(&root)
            last = frame
        }
        return last!
    }

    /// **`compare` grows `frames:` and deliberately does NOT grow
    /// `stateTable:`.** `LR-BY` says it "grows the same two"; it cannot. The
    /// report's `stateSlotsEqual` is `legacy.stateTable.ids ==
    /// lowered.stateTable.ids`, so handing both sides one table would make that
    /// field compare a set with itself and pass for every tree — the exact
    /// vacuity the `frames:` parameter exists to remove. Each side therefore
    /// gets its own fresh `StateTable`, threaded through its own `frames`
    /// frames (`LR-CC`).
    static func compare<Content: ElementGroup>(width: Float, height: Float, scaleFactor: Float = 1,
                                               frames: Int = 1,
                                               @ElementBuilder _ make: @MainActor () -> Content) -> Report {
        let legacy = render(authority: .legacy, width: width, height: height,
                            scaleFactor: scaleFactor, frames: frames, make)
        let lowered = render(authority: .proposal, width: width, height: height,
                             scaleFactor: scaleFactor, frames: frames, make)
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
        let finalA = legacy.finalizedScene(), finalB = lowered.finalizedScene()
        let scenesEqual = bytes(legacy.scene.rects) == bytes(lowered.scene.rects)
            && bytes(legacy.scene.glyphs) == bytes(lowered.scene.glyphs)
            && bytes(finalA.rects) == bytes(finalB.rects)
            && bytes(finalA.glyphs) == bytes(finalB.glyphs)
            && finalA.drawList == finalB.drawList
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

/// Two real `Window`s over `FakePlatformWindow`s — one per layout authority — each
/// showing `DifferentialRoot(size × size) { make() }`, for plan task 7's lane 5
/// (spec 5.4–5.6): what a frame registers is compared as `compare` does, and what
/// a window does with it afterwards — click dispatch through `Window.lastHitboxes`,
/// focus, the keymap, the published accessibility tree, `@State` and animation —
/// is driven identically on both.
///
/// **Square, and the root the window's size**, because the fake surface is square
/// and a native root is centred at its answer (`CN-J`) where the legacy root sits
/// at the origin: a root the window's own size is at (0, 0) under both.
///
/// **No diagnostics.** A `Window` builds production frames, so under the proposal
/// authority anything unlowerable **traps** rather than reports. **So the init
/// first renders the same content through `LayoutDifferential.compare`, with
/// diagnostics, and requires an empty report**: without that pre-flight a mutant
/// that makes the tree report (lane 5's re-run of M4h) trapped inside a window
/// test and ended the whole run with no summary line (practices shape 13, record
/// §18 lane 5). A tree whose report changes between frames (an animation's end
/// state) needs its own pre-flight per state.
@MainActor
struct WindowPair {
    let legacy: (window: Window, platform: FakePlatformWindow)
    let lowered: (window: Window, platform: FakePlatformWindow)

    init<Content: ElementGroup>(device: any MTLDevice, size: Int,
                                startsDisplayLink: Bool = false,
                                @ElementBuilder _ make: @escaping @MainActor () -> Content) throws {
        func open(_ authority: LayoutAuthority) throws -> (window: Window, platform: FakePlatformWindow) {
            let (window, platform) = try makeFakeWindow(device: device, size: size,
                                                        startsDisplayLink: startsDisplayLink) {
                DifferentialRoot(width: Float(size), height: Float(size), content: make)
            }
            window.layoutAuthority = authority
            window.recordsElementBounds = true
            return (window, platform)
        }
        let preflight = LayoutDifferential.compare(width: Float(size), height: Float(size), make)
        try #require(preflight.unlowerable.isEmpty,
                     "this tree would trap in a proposal-authority window: \(preflight.unlowerable)")
        legacy = try open(.legacy)
        lowered = try open(.proposal)
    }

    /// Runs `step` on the legacy window, then on the lowered one.
    func both(_ step: @MainActor (Window, FakePlatformWindow) throws -> Void) rethrows {
        try step(legacy.window, legacy.platform)
        try step(lowered.window, lowered.platform)
    }

    /// The two windows' last frames compared, as `LayoutDifferential.report` compares
    /// two frames: element bounds (`Window.lastElementBounds`), the finalized scene
    /// (`Window.lastScene`: rects, glyphs and draw list), `Window.lastHitboxes`,
    /// every accessibility tree each window has published (in order, geometry
    /// included), and the `StateTable` ids. `unlowerable` is always empty: a
    /// window's frames trap instead of reporting.
    func report() -> LayoutDifferential.Report {
        let a = legacy.window.lastElementBounds, b = lowered.window.lastElementBounds
        let ids = Set(a.keys).union(b.keys).sorted { (x: GlobalElementID, y: GlobalElementID) in "\(x)" < "\(y)" }
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
        let sa = legacy.window.lastScene, sb = lowered.window.lastScene
        let scenesEqual = bytes(sa.rects) == bytes(sb.rects) && bytes(sa.glyphs) == bytes(sb.glyphs)
            && sa.drawList == sb.drawList
        func hitboxKey(_ window: Window) -> [String] {
            window.lastHitboxes.map { "\($0.id)|\($0.bounds)|\($0.layer)|\($0.opaque)" }
        }
        return LayoutDifferential.Report(
            elements: ids.count, agreeing: agreeing, disagreeing: disagreeing,
            legacyOnly: legacyOnly, loweredOnly: loweredOnly, unlowerable: [],
            scenesEqual: scenesEqual,
            hitboxesEqual: hitboxKey(legacy.window) == hitboxKey(lowered.window),
            accessibilityEqual: legacy.platform.publishedAccessibilityTrees
                == lowered.platform.publishedAccessibilityTrees,
            stateSlotsEqual: legacy.window.stateTable.ids == lowered.window.stateTable.ids,
            legacyBounds: a, loweredBounds: b)
    }
}

extension LayoutDifferential {
    /// Opens a `WindowPair`, runs `drive` on each window, and compares their last
    /// frames (spec §5.2's `compareInWindows`; square, see `WindowPair`).
    static func compareInWindows<Content: ElementGroup>(
        device: any MTLDevice, size: Int,
        @ElementBuilder _ make: @escaping @MainActor () -> Content,
        drive: @MainActor (Window, FakePlatformWindow) throws -> Void
    ) throws -> Report {
        let pair = try WindowPair(device: device, size: size, make)
        try pair.both(drive)
        return pair.report()
    }
}
