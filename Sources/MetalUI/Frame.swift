import MetalUICore
import MetalUILayout
import MetalUIRender
import MetalUIText

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

    /// The active theme (spec §7.9), fixed for the whole frame.
    ///
    /// A `let`, so the two halves of one frame cannot resolve the same token
    /// differently: a theme swapped mid-paint would give the first half of the
    /// tree light colours and the second half dark ones, and every rect would
    /// still be individually correct. `Window` swaps the theme *between* frames
    /// and marks §4.4's dirty flag.
    ///
    /// Reachable from `PaintPass` only. Nothing in layout or prepaint consumes a
    /// colour — `LayoutPass` contributes `Style`, which has no colour field at
    /// all, and `PrepaintPass` reads resolved rects — so exposing it there would
    /// be an API with no reader. Adding it to another pass is one forwarding
    /// property when a phase acquires a use for it.
    let theme: Theme

    /// Layout nodes for this frame.
    ///
    /// **A `LayoutNodeID` *can* outlive the frame that minted it, which is why
    /// the tree is stamped.** It was tempting to argue the opposite — a `Frame`
    /// is built per frame, its tree is never `reset`, so id and storage die
    /// together — but that is a claim about the tree, not about the id, and the
    /// id is a `Sendable` value an element may copy anywhere. The carrier that
    /// makes m1a's ruling C-3 reachable here is `pass.withState`: its `S` is
    /// unconstrained, so an element may stash a `LayoutNodeID` in the
    /// cross-frame state table and read it back next frame, against a tree that
    /// no longer knows it. Nothing in the type system prevents that, and a
    /// stored property on a reused element value is a second, narrower route.
    ///
    /// So the hazard is closed rather than argued away: every `Frame` draws a
    /// fresh generation from `nextTreeGeneration`, and `LayoutTree` rejects an
    /// id from any other. A stale id now traps at the accessor instead of
    /// silently returning whatever node shares its index.
    let tree: LayoutTree

    /// Source of `LayoutTree` generations, one per `Frame`, never reused.
    ///
    /// A plain `static var` and not an atomic: it is isolated to the main actor
    /// by `Frame`'s own `@MainActor`, so the compiler — not a comment — is what
    /// rules out a concurrent increment. `UInt64` at one per frame overflows
    /// after about 10^11 years at 120 Hz.
    private static var nextTreeGeneration: UInt64 = 1

    /// Primitives emitted during paint. Written only through `fill`.
    private(set) var scene = Scene()

    /// The cross-frame state table (§4.3).
    ///
    /// **Not owned here — `Frame` is per-frame and this outlives it.** The
    /// window owns it and hands the same instance to every frame; that is the
    /// whole point, and a `Frame` that constructed its own would give every
    /// element fresh state each frame while every test still passed.
    let stateTable: StateTable

    /// The shaping cache (spec §3.2), owned **by the window** exactly as
    /// `stateTable` is, and handed to every frame.
    ///
    /// **A per-frame cache would be a cache that never hits.** It would re-shape
    /// every string on every frame — through CoreText, three times per text item
    /// per layout, since §4.5's automatic minimum probes every item — while
    /// leaving the entire suite green, because a single-frame test cannot tell
    /// a warm cache from a cold one. That is the `StateTable` hazard in a second
    /// place, and `twoFramesShareOneShapingCacheRatherThanReShapingEachFrame`
    /// is the test that can see it: it renders two frames and asserts the miss
    /// count did not double.
    ///
    /// It is keyed on content — `(string, FontKey, width)` — not on element
    /// identity, so two `Text`s showing the same string share one entry and a
    /// `Text` that moves keeps its shape.
    let shapingCache: ShapingCache

    /// The glyph atlas (spec §3.5), owned **by the window** for exactly the
    /// reasons `stateTable` and `shapingCache` are, and with a sharper
    /// consequence than either.
    ///
    /// **A per-frame atlas would re-rasterize every glyph on every frame** —
    /// `CTFontDrawGlyphs` per glyph per variant, the single most expensive step
    /// in drawing text — *and* would upload a whole fresh texture to the GPU
    /// each time, while every test in the repo stayed green: a single-frame
    /// test cannot tell a warm atlas from a cold one, and the pixels are
    /// identical either way. `theAtlasSurvivesTheFrameThatFilledIt` is what can
    /// see it.
    ///
    /// It is keyed on ``MetalUIText/GlyphKey`` — face, glyph id, size, subpixel
    /// variant and scale factor — so two `Text`s in one font share every glyph
    /// they have in common, and a window dragged onto a display with a
    /// different backing scale re-rasterizes rather than serving a 1x bitmap
    /// into a 2x frame.
    let glyphAtlas: GlyphAtlas

    init(contentSize: Size<Pixels>, scaleFactor: Float, rootFontSize: Double = 16,
         stateTable: StateTable = StateTable(),
         shapingCache: ShapingCache = ShapingCache(),
         glyphAtlas: GlyphAtlas = GlyphAtlas(width: Window.atlasExtent,
                                             height: Window.atlasExtent),
         theme: Theme = .light) {
        self.tree = LayoutTree(generation: Frame.nextTreeGeneration)
        Frame.nextTreeGeneration += 1
        self.contentSize = contentSize
        self.scaleFactor = scaleFactor
        self.rootFontSize = rootFontSize
        self.stateTable = stateTable
        self.shapingCache = shapingCache
        self.glyphAtlas = glyphAtlas
        self.theme = theme
    }

    // MARK: - Layout phase

    func requestNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID {
        tree.newNode(style: style, children: children)
    }

    /// Registers a **leaf** — a childless node that reports its own content size
    /// through `measure` (spec §3.1).
    ///
    /// This is `newLeaf`'s only production call site. Everything the engine can
    /// do with a measured content size — §9.2's content branch, §4.5's automatic
    /// minimum, an `auto` cross size — was reachable only for containers before
    /// it existed, because `tree.measure()` was `nil` on every production node.
    func requestLeaf(style: Style, measure: @escaping MeasureFunction) -> LayoutNodeID {
        tree.newLeaf(style: style, measure: measure)
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

    /// Emits one filled rect, optionally with rounded corners.
    ///
    /// Borders, clip stacks and explicit z-order are still ahead (§7.3): every
    /// rect here is emitted at `order: 0`, and `Scene.finalize()` sorts stably,
    /// so equal orders keep emission sequence — which is why a container's own
    /// background paints under its children provided it emits first.
    /// `contentMask` is the whole surface: nothing clips yet, and the fragment
    /// shader does not read the field in any case.
    ///
    /// **`borderColor` is `.transparent` and there is no way to set it**, even
    /// though `MUIRect` carries it and the fragment shader draws it — the M0
    /// demo proved that end to end. The blocker is the *width*, not the colour:
    /// a border width is `Style.border`, an `Edges<Length>` whose percentage
    /// case resolves against the **containing block's width**, and the engine
    /// computes that inside `contentBox` and discards it rather than storing it
    /// on the node. So paint has no resolved width to pair a colour with, and
    /// re-resolving one here against the box's own width is the exact mistake
    /// CLAUDE.md's percentage-inset constraint records. Storing the resolved
    /// edges on `LayoutTree` is what unblocks it.
    func fill(_ bounds: Bounds<Pixels>, color: Hsla,
              cornerRadii: Corners<Pixels> = Corners(all: Pixels(0))) {
        let surface = Bounds(
            origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
            size: contentSize.scaled(by: scaleFactor))
        scene.insert(MUIRect(
            bounds: bounds.scaled(by: scaleFactor),
            contentMask: surface,
            background: color,
            borderColor: .transparent,
            cornerRadii: cornerRadii.scaled(by: scaleFactor),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: 0))
    }

    /// Emits one glyph sprite, taking its bitmap from the atlas and rasterizing
    /// it there on first sight.
    ///
    /// **Everything here is already in device pixels and nothing is scaled**,
    /// which is the opposite of `fill` above and is deliberate. A glyph bitmap
    /// is rasterized *on* the device grid — `GlyphKey` carries the scale factor
    /// and `GlyphImage`'s bearings are in device pixels — so the conversion has
    /// already happened, in `ShapedText.placedGlyphs`, once. Scaling again here
    /// would double-scale exactly the way `PaintPass.fill`'s doc warns about.
    ///
    /// **The bearings come from the atlas, not from a second look at the
    /// font.** `PackedGlyph.left`/`.top` are the values the rasterizer computed
    /// with the same `floor`/`ceil` that produced the bitmap's width and height;
    /// re-deriving them from `CTFontGetBoundingRectsForGlyphs` here is the
    /// percentage-inset mistake CLAUDE.md records — one quantity resolved twice,
    /// free to disagree with itself by a pixel.
    ///
    /// Two returns without an error, and they are different situations:
    ///
    /// - **The atlas is full** (`nil`). Nothing this frame can do about it: the
    ///   packer never revisits a closed shelf, so there is no smaller correct
    ///   answer than dropping the glyph. It is silent because a `throw` here
    ///   would take down a frame that is otherwise entirely drawable.
    /// - **The glyph has no ink** (a zero-area slot — a space, and the
    ///   commonest glyph in a paragraph). Emitting it would add an instance
    ///   whose quad is degenerate and whose sampler reads nothing; the atlas
    ///   still records it so `rasterize` is not re-run for every space.
    func draw(_ placed: PlacedGlyph, color: Hsla) {
        guard let packed = glyphAtlas.packed(for: placed.key, rasterize: {
            GlyphRaster.rasterize(glyph: placed.key.glyph, font: placed.font,
                                  subpixelVariant: placed.key.subpixelVariant,
                                  scaleFactor: placed.key.scaleFactor)
        }) else { return }
        guard packed.slot.width > 0, packed.slot.height > 0 else { return }

        let bounds = Bounds(
            origin: Point(x: ScaledPixels(Float(placed.pixelX + packed.left)),
                          y: ScaledPixels(Float(placed.baselineY - packed.top))),
            size: Size(width: ScaledPixels(Float(packed.slot.width)),
                       height: ScaledPixels(Float(packed.slot.height))))
        scene.insert(MUIGlyph(bounds: bounds, slot: packed.slot, color: color, order: 0))
    }

    /// This frame's primitives, in paint order. Call after `render`.
    ///
    /// A copy, so `scene` stays the *emission* record: a test that asserts
    /// which element painted first reads `scene`, and one that asserts what the
    /// GPU receives reads this.
    func finalizedScene() -> Scene {
        var finalized = scene
        finalized.finalize()
        return finalized
    }

    // MARK: - Driving the three phases

    /// Walks `element` through layout, prepaint and paint, running the flex
    /// engine in between.
    ///
    /// Builds the root's `GlobalElementID` from the element's own `elementID`
    /// and hands it down, then **sweeps after the frame** (§4.3).
    ///
    /// Only the root's path is built here. Every deeper path comes from a
    /// container calling `GlobalElementID.child(of:at:name:)` through
    /// `ElementGroup`'s conformances, so a deep tree is identified all the way
    /// down **whether or not any container on the path is named** — an unnamed
    /// one contributes its own positional component instead of stopping the
    /// path. See `ElementGroup.swift` for the cursor that supplies the index.
    func render<E: Element>(_ element: inout E) {
        // The root is the only id with no parent, and the only one this file
        // builds. `at: 0` is not inert: an unnamed root element takes
        // `.positional(0)`, which is what gives a `Row { … }` rendered straight
        // into a frame an identity for its children to hang from. A named root
        // takes `.named` instead — the constructor decides, here as everywhere.
        let rootID = GlobalElementID.child(of: nil, at: 0, name: element.elementID)

        var layoutPass = LayoutPass(frame: self)
        let (root, layoutState) = element.requestLayout(rootID, pass: &layoutPass)
        var state = layoutState

        computeRootLayout(root: root)
        let rootBounds = bounds(of: root)

        var prepaintPass = PrepaintPass(frame: self)
        var prepaintState = element.prepaint(rootID, bounds: rootBounds,
                                             layout: &state, pass: &prepaintPass)

        // The atlas's frame brackets go around the paint phase and nothing
        // else, because scene construction is the whole of what they protect:
        // `GlyphAtlas.evictUnusedSince` traps while a frame is being built, so
        // that a glyph this scene still holds an `AtlasSlot` for cannot be
        // dropped underneath it (spec §3.5). They also stamp every slot handed
        // out here with this frame's generation, which is what eviction reads.
        //
        // **Not a `defer`, and the reason is a mechanism rather than taste.**
        // The only way `paint` fails to reach `endFrame` is a Swift trap, and a
        // trap aborts the process — there is no later frame to be left with
        // `isBuildingFrame` still true. A `defer` here would be insurance
        // against a case that cannot occur, and would additionally hold the
        // bracket open across `stateTable.sweep()` below, which is not scene
        // construction.
        glyphAtlas.beginFrame()
        var paintPass = PaintPass(frame: self)
        element.paint(rootID, bounds: rootBounds,
                      layout: &state, prepaint: &prepaintState, pass: &paintPass)
        glyphAtlas.endFrame()

        // After the frame, not before — but **not for the reason it is tempting
        // to write down.** Sweeping first does *not* discard everything the
        // previous frame established: `marked` is cleared only inside `sweep()`,
        // so a sweep at frame start still sees the previous frame's marks. The
        // real cost of that ordering is a **one-frame eviction lag** — an
        // element that stops being produced keeps its state for one extra frame.
        // Witnessed by `anElementThatStopsBeingProducedIsSweptByTheNextFrame`,
        // which is the only test that reddens if this call moves above the
        // phases.
        stateTable.sweep()
    }
}

extension Size where Unit == Pixels {
    func scaled(by factor: Float) -> Size<ScaledPixels> {
        Size<ScaledPixels>(width: width.scaled(by: factor), height: height.scaled(by: factor))
    }
}

extension Corners where Unit == Pixels {
    func scaled(by factor: Float) -> Corners<ScaledPixels> {
        Corners<ScaledPixels>(
            topLeft: topLeft.scaled(by: factor), topRight: topRight.scaled(by: factor),
            bottomRight: bottomRight.scaled(by: factor), bottomLeft: bottomLeft.scaled(by: factor))
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
