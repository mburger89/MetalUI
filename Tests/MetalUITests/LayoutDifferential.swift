import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIRender
import MetalUIPlatform
import Metal
@testable import MetalUI

// Test support for plan task 7's lowering tests
// (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §5.2, ruling
// LR-D). **Single-authority since stage 9** (ruling `LR-FE` item 5): until then
// a tree was rendered twice — under the legacy layout authority, then under the
// proposal authority — and the two frames were compared element by element and
// observation by observation. The legacy authority and its CSS engine are gone,
// so a tree is rendered once, inside `DifferentialRoot`, with diagnostics on and
// element bounds recorded, and a test asserts the one frame's answers by
// hand-derived literal. The name is kept so the record's citations still resolve.

/// The harness root: a top-leading, fixed-size root (ruling LR-D) — a native
/// `.topLeading` overlay of the content inside a native fixed `width`×`height`
/// frame aligned `.topLeading`.
///
/// **It offers its content `width`×`height`** (the overlay's proposal), so a
/// wrapping or greedy child placed directly under it fills that offer. Until
/// stage 9 the legacy side offered fit-content (divergence 53), which is why the
/// older tests put such content in a container of its own.
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
        let overlay = pass.frame.requestNativeOverlay(children: children,
                                                      alignment: .topLeading)
        let node = pass.frame.requestNativeFrame(child: overlay,
                                                 width: Double(width), height: Double(height),
                                                 alignment: .topLeading)
        return (node, Layout(content: contentLayout))
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

/// A fixed-size native leaf answering `width`×`height`, painting a fill over its
/// bounds so its rect reaches the scene; `clickable` adds an `onClick` and an
/// accessibility label, registered in `prepaint`. (Its stage-1 knobs, each of
/// which made the two authorities disagree on purpose, retired with the
/// comparison at stage 9, `LR-FE` item 5.)
@MainActor
struct ProbeLeaf: Element {
    var width: Float
    var height: Float
    var clickable = false

    mutating func requestLayout(_ id: GlobalElementID,
                                pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let w = Double(width), h = Double(height)
        return (pass.frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: w, height: h)) }, ())
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
        pass.fill(bounds, color: Hsla(h: 0.6, s: 0.5, l: 0.5))
    }
}

/// Renders `DifferentialRoot { make() }` once, with diagnostics on and element
/// bounds recorded.
@MainActor
enum LayoutDifferential {
    struct Report {
        /// Ids the frame recorded (`Frame.elementBounds`).
        var elements: Int
        /// The frame's diagnostics, in registration order.
        var unlowerable: [UnlowerableField]
        /// Each element's recorded rect, for literal assertions.
        var bounds: [GlobalElementID: Bounds<Pixels>]
        /// The frame itself, for a test that asserts its scene, hitboxes,
        /// accessibility records or state table by literal.
        var frame: Frame
    }

    /// The frame a tree renders, kept for a test that needs more than the report.
    ///
    /// **`frames` and `stateTable` exist because one frame cannot window a
    /// `List`** (ruling `LR-BY`, plan task 7 stage 4 lane 1, critic round 1
    /// defect D4). `ScrollContext.viewportExtent` is one frame stale by
    /// construction — only `ScrollChrome.resolvedOffset`'s `PrepaintPass`
    /// overload ever writes it, into the scroller's `ScrollState` — so on the
    /// first frame it is 0, `List.visibleRange` takes its
    /// `context.viewportExtent > 0` guard and returns `0..<count`, and
    /// `windowIsBounded` is false, which sends `List.prepaint` down the branch
    /// that publishes the table and **no rows**.
    ///
    /// `frames > 1` renders that many frames over one `StateTable` — the same
    /// object a real `Window` threads across its frames — and returns the last.
    /// **An arm that relies on this owes a `try #require` that the window
    /// really is bounded and the row-record set really is non-empty** before it
    /// asserts anything. Pinned by
    /// `aListInTheDifferentialHarnessReachesABoundedWindow` (`ListTests.swift`),
    /// whose mutation M1f forces `frames` back to 1.
    static func render<Content: ElementGroup>(width: Float, height: Float, scaleFactor: Float = 1,
                                              stateTable: StateTable? = nil,
                                              frames: Int = 1,
                                              @ElementBuilder _ make: @MainActor () -> Content) -> Frame {
        precondition(frames >= 1, "a tree renders at least one frame")
        let table = stateTable ?? StateTable()
        var last: Frame?
        for _ in 0..<frames {
            var root = DifferentialRoot(width: width, height: height, content: make)
            let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)),
                              scaleFactor: scaleFactor,
                              stateTable: table,
                              collectsAccessibility: true,
                              reportsUnlowerableFields: true,
                              recordsElementBounds: true)
            frame.render(&root)
            last = frame
        }
        return last!
    }

    /// `render`, summarized: the recorded element count, the diagnostics and the
    /// element bounds (stage 9's single-authority replacement for `compare`,
    /// `LR-FE` item 5).
    static func report<Content: ElementGroup>(width: Float, height: Float, scaleFactor: Float = 1,
                                              frames: Int = 1,
                                              @ElementBuilder _ make: @MainActor () -> Content) -> Report {
        report(render(width: width, height: height, scaleFactor: scaleFactor, frames: frames, make))
    }

    static func report(_ frame: Frame) -> Report {
        Report(elements: frame.elementBounds.count, unlowerable: frame.unlowerableFields,
               bounds: frame.elementBounds, frame: frame)
    }
}

/// A real `Window` over a `FakePlatformWindow` showing `DifferentialRoot(size ×
/// size) { make() }`, recording element bounds — stage 9's one window where a
/// `WindowPair` opened two, one per layout authority (`LR-FE` item 4).
///
/// **Square, and the root the window's size**, because the fake surface is square
/// and a native root is centred at its answer (`CN-J`): a root the window's own
/// size is at (0, 0).
///
/// **No diagnostics.** A `Window` builds production frames, so anything
/// unlowerable **traps** rather than reports. **So it first renders the same
/// content through `LayoutDifferential.render`, with diagnostics, and requires
/// an empty report**: without that pre-flight a mutant that makes the tree report
/// (lane 5's re-run of M4h) trapped inside a window test and ended the whole run
/// with no summary line (practices shape 13, record §18 lane 5). A tree whose
/// report changes between frames (an animation's end state) needs its own
/// pre-flight per state.
@MainActor
func makeLoweredWindow<Content: ElementGroup>(device: any MTLDevice, size: Int,
                                              startsDisplayLink: Bool = false,
                                              @ElementBuilder _ make: @escaping @MainActor () -> Content)
    throws -> (window: Window, platform: FakePlatformWindow) {
    let preflight = LayoutDifferential.render(width: Float(size), height: Float(size), make)
    try #require(preflight.unlowerableFields.isEmpty,
                 "this tree would trap in a production window: \(preflight.unlowerableFields)")
    let (window, platform) = try makeFakeWindow(device: device, size: size,
                                                startsDisplayLink: startsDisplayLink) {
        DifferentialRoot(width: Float(size), height: Float(size), content: make)
    }
    window.recordsElementBounds = true
    return (window, platform)
}

@MainActor
extension LayoutDifferential.Report {
    /// Each hitbox's rect by owner (`Frame.hitboxes`, a later registration by
    /// the same owner winning), for a literal where a test's doc names hitboxes
    /// (stage 9, `LR-FE` item 2: what the two-engine `hitboxesEqual` carried).
    var hitboxRects: [GlobalElementID: Bounds<Pixels>] {
        Dictionary(frame.hitboxes.map { ($0.id, $0.bounds) }, uniquingKeysWith: { _, last in last })
    }

    /// Each accessibility record's unclipped frame by element
    /// (`Frame.axEmissions`, a later record by the same element winning), for a
    /// literal where a test's doc names accessibility (what `accessibilityEqual`
    /// carried).
    var accessibilityFrames: [GlobalElementID: Bounds<Pixels>] {
        Dictionary(frame.axEmissions.map { ($0.id, $0.geometry.frame) }, uniquingKeysWith: { _, last in last })
    }
}

@MainActor
extension LayoutDifferential.Report {
    /// Every emitted scene rect's bounds, in emission order (`Frame.scene.rects`),
    /// in the frame's scaled pixels — what `scenesEqual` compared byte for byte.
    var sceneRects: [Bounds<Pixels>] {
        frame.scene.rects.map {
            Bounds(origin: Point(x: Pixels($0.bounds.origin.x), y: Pixels($0.bounds.origin.y)),
                   size: Size(width: Pixels($0.bounds.size.width), height: Pixels($0.bounds.size.height)))
        }
    }

    /// The string of each text accessibility record, by element.
    var accessibilityTexts: [GlobalElementID: String] {
        Dictionary(frame.axEmissions.compactMap { e in e.text.map { (e.id, $0) } },
                   uniquingKeysWith: { _, last in last })
    }
}

@MainActor
extension LayoutDifferential.Report {
    /// How many distinct text rows the scene's glyphs fall in, counting from
    /// `top` in rows `lineHeight` tall (13pt text: 16) — a glyph's row is the one
    /// its centre falls in. For a literal on where a text wraps, which the
    /// two-engine `scenesEqual` carried until stage 9.
    func glyphRowCount(top: Float, lineHeight: Float = 16) -> Int {
        Set(frame.scene.glyphs.map { Int((($0.bounds.origin.y + $0.bounds.size.height / 2) - top) / lineHeight) }).count
    }
}
