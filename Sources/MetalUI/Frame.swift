import MetalUICore
import MetalUILayout
import MetalUIRender

/// The single owner of one frame's mutable state (spec §4.1).
///
/// `LayoutPass`, `PrepaintPass` and `PaintPass` are thin structs over this
/// class; the state lives here exactly once, and each pass exposes the slice of
/// it that its phase may touch. Making the *passes* own state instead would
/// force it to be copied or shared between phases, which is the bug the split
/// exists to prevent.
///
/// **`init` and every phase operation are `internal` on purpose.** The
/// compile-time guarantee that an element cannot paint during layout rests
/// entirely on an element being unable to obtain a pass it was not handed: from
/// outside `MetalUI` there is no way to construct a `Frame` and no way to
/// construct a `PaintPass`. Inside the module the compiler does not stop you —
/// that half is a convention, and `codeOutsideTheFrameworkCannotFabricateAPaintPass`
/// pins the half that is enforced.
@MainActor
public final class Frame {
    /// The space offered to the root element, in logical points.
    public let contentSize: Size<Pixels>

    /// Logical points to device pixels for this frame's target. Applied once,
    /// in `fill`, so element code never has to think about it.
    public let scaleFactor: Float

    /// CSS's `rem` basis. One value per frame; the text system may make it
    /// settable in M2.
    let rootFontSize: Double

    /// Layout nodes for this frame.
    ///
    /// A `Frame` is built per frame and its tree is never `reset()`, so a
    /// `LayoutNodeID` cannot outlive the tree that issued it: the id and the
    /// storage are deallocated together. That is what closes m1a's ruling C-3
    /// hazard (a `LayoutNodeID` has no generation counter, so a stale one
    /// silently addresses a different node after a `reset()`) for this design.
    /// **Reusing one `LayoutTree` across frames to keep its capacity would
    /// reopen it**, and would need a generation counter first.
    let tree = LayoutTree()

    /// Primitives emitted during paint. Written only through `fill`.
    private(set) var scene = Scene()

    /// The cross-frame state table (§4.3).
    ///
    /// **Not owned here — `Frame` is per-frame and this outlives it.** The
    /// window owns it and hands the same instance to every frame; that is the
    /// whole point, and a `Frame` that constructed its own would give every
    /// element fresh state each frame while every test still passed.
    let stateTable: StateTable

    init(contentSize: Size<Pixels>, scaleFactor: Float, rootFontSize: Double = 16,
         stateTable: StateTable = StateTable()) {
        self.contentSize = contentSize
        self.scaleFactor = scaleFactor
        self.rootFontSize = rootFontSize
        self.stateTable = stateTable
    }

    // MARK: - Layout phase

    func requestNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID {
        tree.newNode(style: style, children: children)
    }

    /// Runs the flex engine over the tree, between `requestLayout` and
    /// `prepaint`. Not reachable from any pass: elements contribute nodes, the
    /// frame runs the engine on the finished root.
    func computeRootLayout(root: LayoutNodeID) {
        computeLayout(
            tree,
            root: root,
            available: AvailableSpaceSize(
                width: .definite(Double(contentSize.width.value)),
                height: .definite(Double(contentSize.height.value))),
            rootFontSize: rootFontSize)
    }

    // MARK: - Post-layout phases

    /// A node's resolved bounds, **absolute to the root** — the engine stores
    /// absolute rects, so no parent offset is added here.
    func bounds(of node: LayoutNodeID) -> Bounds<Pixels> {
        let rect = tree.layout(node)
        return Bounds(
            origin: Point(x: Pixels(Float(rect.x)), y: Pixels(Float(rect.y))),
            size: Size(width: Pixels(Float(rect.width)), height: Pixels(Float(rect.height))))
    }

    // MARK: - Paint phase

    /// Emits one filled rect.
    ///
    /// Corner radii, borders, clip stacks and explicit z-order are the paint
    /// task's business (§7.3); every rect here is emitted at `order: 0`, and
    /// `Scene.finalize()` sorts stably, so equal orders keep emission sequence.
    /// `contentMask` is the whole surface: nothing clips yet, and the fragment
    /// shader does not read the field in any case.
    func fill(_ bounds: Bounds<Pixels>, color: Hsla) {
        let surface = Bounds(
            origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
            size: contentSize.scaled(by: scaleFactor))
        scene.insert(MUIRect(
            bounds: bounds.scaled(by: scaleFactor),
            contentMask: surface,
            background: color,
            borderColor: .transparent,
            cornerRadii: Corners(all: ScaledPixels(0)),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: 0))
    }

    // MARK: - Driving the three phases

    /// Walks `element` through layout, prepaint and paint, running the flex
    /// engine in between.
    ///
    /// Builds the root's `GlobalElementID` from the element's own `elementID`
    /// and hands it down, then **sweeps after the frame** (§4.3).
    ///
    /// Only the root's path is built here. Every deeper path comes from a
    /// container calling `GlobalElementID.child(of:_:)`, and **no container
    /// exists yet** — `Box`/`Column`/`Row` are Task 4 — so a tree deeper than
    /// one element currently has one identified node and anonymous descendants.
    /// Grep `child(of:` in `Sources/` to see whether that is still true.
    func render<E: Element>(_ element: inout E) {
        let rootID = GlobalElementID.child(of: .root, element.elementID)

        var layoutPass = LayoutPass(frame: self)
        let (root, layoutState) = element.requestLayout(rootID, pass: &layoutPass)
        var state = layoutState

        computeRootLayout(root: root)
        let rootBounds = bounds(of: root)

        var prepaintPass = PrepaintPass(frame: self)
        var prepaintState = element.prepaint(rootID, bounds: rootBounds,
                                             layout: &state, pass: &prepaintPass)

        var paintPass = PaintPass(frame: self)
        element.paint(rootID, bounds: rootBounds,
                      layout: &state, prepaint: &prepaintState, pass: &paintPass)

        // After the frame, never before: sweeping first would discard every
        // entry the previous frame established, which is the table's purpose.
        stateTable.sweep()
    }
}

extension Size where Unit == Pixels {
    func scaled(by factor: Float) -> Size<ScaledPixels> {
        Size<ScaledPixels>(width: width.scaled(by: factor), height: height.scaled(by: factor))
    }
}

extension Bounds where Unit == Pixels {
    /// Logical points to the render target's space. Every component is scaled,
    /// including the origin — scaling the size alone leaves everything but the
    /// top-left element in the wrong place on a Retina display.
    func scaled(by factor: Float) -> Bounds<ScaledPixels> {
        Bounds<ScaledPixels>(
            origin: Point(x: origin.x.scaled(by: factor), y: origin.y.scaled(by: factor)),
            size: size.scaled(by: factor))
    }
}
