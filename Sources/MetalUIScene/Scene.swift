import MetalUIShaderTypes

/// Which pipeline a primitive belongs to. One case per instanced draw.
///
/// `.surface` (MetalView, ruling `MV-C`) is an app-owned GPU surface's quad:
/// an `MUIImage` record drawn by the image pipeline with the surface's render
/// target bound as its texture. **Public break** (`MV-C` item 3): an
/// exhaustive `switch` outside the package adds a `.surface` arm.
public enum PrimitiveKind: Sendable, Equatable { case rect, glyph, image, surface }

/// One instanced draw: `count` primitives of `kind`, starting at `start` in
/// that kind's own array.
///
/// **The number of runs IS the draw-call count** (spec §7.3: "draw-call count
/// is the number of type transitions in z-order"). That makes the promise
/// assertable rather than architectural — see `DrawListTests`.
public struct DrawRun: Sendable, Equatable {
    /// The primitive type the run draws.
    public let kind: PrimitiveKind
    /// The index of the run's first primitive in that type's array.
    public let start: Int
    /// The number of primitives in the run.
    public let count: Int
}

/// Primitives accumulated during a frame's paint phase.
///
/// One array per primitive type rather than one heterogeneous array, because
/// each type is a separate GPU pipeline and a separate instanced draw: a mixed
/// array would be re-partitioned at encode time on every frame. `finalize()`
/// restores a total order across both arrays by building ``drawList``, so
/// `order` totally orders the scene even though the storage is split.
public struct Scene: Sendable {
    /// The rectangles, in insertion order.
    public private(set) var rects: [MUIRect] = []

    /// Glyph sprites (`monochromeSprite`, spec 7.1).
    public private(set) var glyphs: [MUIGlyph] = []

    /// Image quads (ruling TE-AF). `MUIImage.texture` indexes ``textures``.
    public private(set) var images: [MUIImage] = []

    /// The pixels ``images`` sample, one entry per distinct `ImageTexture`
    /// identity, in first-use order. The scene carries them so a renderer can
    /// never receive an image without its pixels, and
    /// `WindowRenderer.finishFrame(scene:atlas:)` keeps its signature (`RS-A`).
    public private(set) var textures: [ImageTexture] = []

    /// App-owned GPU surfaces' quads (MetalView, ruling `MV-C`): the image
    /// record, drawn by the image pipeline, its `texture` field indexing
    /// ``surfaceTargets`` rather than ``textures``.
    public private(set) var surfaces: [MUIImage] = []

    /// The render targets ``surfaces`` sample, one per distinct `SurfaceID`,
    /// in first-use order — an opaque id and a device-pixel size each, which
    /// every renderer resolves to its own texture (`MV-E`).
    public private(set) var surfaceTargets: [SurfaceTarget] = []

    /// Per-instance affines (ruling GX-F), in first-use order; a primitive
    /// names entry `i` by storing `i + 1` (``insert(_:layer:transform:)``):
    /// `MUIRect.shape` and `MUIImage.filter` bits 8…31, `MUIGlyph.transform`.
    /// **Never reordered** by ``finalize()`` (primitives keep their index
    /// through the permutation) and never a run boundary — a transform is
    /// per instance, so one draw call carries any mix of them.
    public private(set) var transforms: [MUITransform] = []

    /// 1 + the index `transform` gets in ``transforms``, or 0 for `nil`.
    /// **Equal consecutive records share one entry** (one effect's
    /// primitives all name the same record), compared byte for byte.
    private mutating func transformIndex(_ transform: MUITransform?) -> MUIUInt {
        guard var transform else { return 0 }
        transform._reserved = 0
        if let last = transforms.last, Self.sameBytes(last, transform) { return MUIUInt(transforms.count) }
        transforms.append(transform)
        precondition(transforms.count < 1 << 24, "Scene: more than 2^24 − 1 transforms (GX-F)")
        return MUIUInt(transforms.count)
    }

    private static func sameBytes(_ a: MUITransform, _ b: MUITransform) -> Bool {
        withUnsafeBytes(of: a) { ra in withUnsafeBytes(of: b) { rb in ra.elementsEqual(rb) } }
    }

    /// Built by ``finalize()``. Empty until then.
    public private(set) var drawList: [DrawRun] = []

    /// Emission sequence per kind, so `finalize()` can tiebreak equal orders
    /// across types. Not public: it is bookkeeping for one method.
    ///
    /// **Plain arrays — eight since the surface kind (ruling `MV-C` item 2),
    /// six since the image kind (ruling TE-AF), four before — not
    /// `[PrimitiveKind: [Int]]` dictionaries.**
    /// The dictionary form did a subscript per `insert` and two per element in
    /// `finalize()`, each handing back a whole `[Int]` before the integer index,
    /// and `clear()` replaced both dictionaries outright, dropping their
    /// capacity. Pinned by `sceneSideTablesArePlainIntArraysThatKeepCapacityAcrossClear`.
    private var rectSequence: [Int] = []
    private var glyphSequence: [Int] = []
    private var imageSequence: [Int] = []
    private var surfaceSequence: [Int] = []
    private var nextSequence = 0

    /// Layer per primitive, parallel to `rectSequence`/`glyphSequence`.
    /// CPU-side sort metadata only — the GPU never reads it, it only changes
    /// which order primitives are drawn in. A higher layer always draws after a
    /// lower one, ahead of `order`, so a subtree can be lifted above its
    /// siblings (e.g. absolute positioning) without touching how `order` works
    /// within a layer.
    private var rectLayer: [Int] = []
    private var glyphLayer: [Int] = []
    private var imageLayer: [Int] = []
    private var surfaceLayer: [Int] = []

    /// An empty scene.
    public init() {}

    /// **Every primitive array, and each of the three members below reads
    /// all of them.** A `Scene` holding only glyphs, or only images, is not
    /// empty: `Renderer.encode` returns early on an empty scene, so an
    /// `isEmpty` that missed one array would silently draw nothing in any
    /// frame whose paint emitted only that kind — a blank run with no error
    /// anywhere. Pinned by `aSceneHoldingOnlyAGlyphIsNotEmpty` and
    /// `aSceneHoldingOnlyAnImageIsNotEmpty` (ruling TE-AF item 4) and
    /// `aSceneHoldingOnlyASurfaceIsNotEmpty` (`MV-C` item 2).
    public var isEmpty: Bool { rects.isEmpty && glyphs.isEmpty && images.isEmpty && surfaces.isEmpty }

    /// Adds a rectangle on `layer`, under `transform` when given (ruling
    /// GX-F): its `bounds` and `contentMask` are then local, mapped by the
    /// record; `nil` draws it exactly as before transforms existed. **The
    /// index is always written**: `nil` clears `shape` bits 8…31 (and the
    /// glyph's `transform`, the image's `filter` bits 8…31), so a primitive
    /// captured from one scene and re-inserted into another never keeps a
    /// stale index into a table the new scene does not hold — a replay that
    /// must stay transformed passes its record again. Pinned by
    /// `aNilInsertClearsAStaleTransformIndex`.
    public mutating func insert(_ rect: MUIRect, layer: Int = 0, transform: MUITransform? = nil) {
        var rect = rect
        let index = transformIndex(transform)
        rect.shape = (rect.shape & 0xFF) | index << 8
        rects.append(rect)
        rectSequence.append(nextSequence)
        rectLayer.append(layer)
        nextSequence += 1
    }

    /// Adds a glyph on `layer`, under `transform` when given (see the rect
    /// overload).
    public mutating func insert(_ glyph: MUIGlyph, layer: Int = 0, transform: MUITransform? = nil) {
        var glyph = glyph
        let index = transformIndex(transform)
        glyph.transform = index
        glyphs.append(glyph)
        glyphSequence.append(nextSequence)
        glyphLayer.append(layer)
        nextSequence += 1
    }

    /// Appends `image`, sampling `texture`. Its `texture` field is set here,
    /// to `texture`'s index in ``textures`` — a texture drawn twice is carried
    /// once.
    public mutating func insert(_ image: MUIImage, texture: ImageTexture, layer: Int = 0,
                                transform: MUITransform? = nil) {
        var image = image
        let index = transformIndex(transform)
        image.filter = (image.filter & 0xFF) | index << 8
        if let index = textures.firstIndex(where: { $0 === texture }) {
            image.texture = MUIUInt(index)
        } else {
            image.texture = MUIUInt(textures.count)
            textures.append(texture)
        }
        images.append(image)
        imageSequence.append(nextSequence)
        imageLayer.append(layer)
        nextSequence += 1
    }

    /// Appends `quad`, sampling `surface`'s render target (ruling `MV-C`). Its
    /// `texture` field is set here, to the target's index in
    /// ``surfaceTargets`` — a surface drawn twice (a drag preview replaying
    /// its source) is carried once. **One id, one size per scene**: the same
    /// id at a different size traps, since a renderer can bind only one
    /// texture per target.
    public mutating func insert(_ quad: MUIImage, surface: SurfaceTarget, layer: Int = 0,
                                transform: MUITransform? = nil) {
        var quad = quad
        let index = transformIndex(transform)
        quad.filter = (quad.filter & 0xFF) | index << 8
        if let index = surfaceTargets.firstIndex(where: { $0.id == surface.id }) {
            precondition(surfaceTargets[index] == surface,
                         "Scene: surface \(surface.id.rawValue) inserted at \(surface.width)×\(surface.height) "
                         + "and \(surfaceTargets[index].width)×\(surfaceTargets[index].height) (MV-C)")
            quad.texture = MUIUInt(index)
        } else {
            quad.texture = MUIUInt(surfaceTargets.count)
            surfaceTargets.append(surface)
        }
        surfaces.append(quad)
        surfaceSequence.append(nextSequence)
        surfaceLayer.append(layer)
        nextSequence += 1
    }

    /// The highest layer any primitive was inserted on, or `nil` for an empty
    /// scene — what a drag preview rises above (ruling `DN-J`). Computed, so
    /// a frame that never asks pays nothing.
    public var highestLayer: Int? {
        [rectLayer.max(), glyphLayer.max(), imageLayer.max(), surfaceLayer.max()].compactMap { $0 }.max()
    }

    /// The layer of the `index`th primitive of `kind` — in emission order
    /// before ``finalize()``, in paint order after it (the side tables are
    /// permuted with the primitives).
    public func layer(of kind: PrimitiveKind, at index: Int) -> Int {
        switch kind {
        case .rect: rectLayer[index]
        case .glyph: glyphLayer[index]
        case .image: imageLayer[index]
        case .surface: surfaceLayer[index]
        }
    }

    /// Removes every primitive, keeping the arrays' capacity.
    public mutating func clear() {
        rects.removeAll(keepingCapacity: true)
        glyphs.removeAll(keepingCapacity: true)
        images.removeAll(keepingCapacity: true)
        textures.removeAll(keepingCapacity: true)
        surfaces.removeAll(keepingCapacity: true)
        surfaceTargets.removeAll(keepingCapacity: true)
        transforms.removeAll(keepingCapacity: true)
        drawList.removeAll(keepingCapacity: true)
        rectSequence.removeAll(keepingCapacity: true)
        glyphSequence.removeAll(keepingCapacity: true)
        imageSequence.removeAll(keepingCapacity: true)
        surfaceSequence.removeAll(keepingCapacity: true)
        rectLayer.removeAll(keepingCapacity: true)
        glyphLayer.removeAll(keepingCapacity: true)
        imageLayer.removeAll(keepingCapacity: true)
        surfaceLayer.removeAll(keepingCapacity: true)
        nextSequence = 0
    }

    /// Sorts primitives into paint order **across types** and builds the draw
    /// list.
    ///
    /// Each kind keeps its own array, because each maps to one pipeline and one
    /// instanced draw and a heterogeneous array would be re-partitioned every
    /// frame. What changes here is that `order` now totally orders the scene:
    /// the merged index below is sorted once, each array is permuted into that
    /// global order so every run is contiguous within it, and the run
    /// boundaries fall wherever the kind changes.
    ///
    /// **The insertion-sequence tiebreak is load-bearing.** Painters at the same
    /// layer and order must stack predictably, and a merged sort across two
    /// arrays has no inherent order between them — the sequence number is what
    /// supplies one. Pinned by `equalOrdersKeepEmissionSequenceAcrossTypes`.
    ///
    /// **The sort IS the interleave, so it is not an optimisation target.**
    /// `merged` is built all-rects-then-all-glyphs, and `Frame.pushLayer()`
    /// raises the layer mid-emission, so neither half is already in
    /// `(layer, order, sequence)` order: the sort is what puts a glyph between
    /// two rects. A merge that assumes sorted halves, or a counting sort on
    /// `layer` alone, draws every glyph after every rect on a layer —
    /// `equalOrdersKeepEmissionSequenceAcrossTypes` and
    /// `finalizeReproducesTheCapturedDrawListAndPerKindOrder` both see it.
    ///
    /// **Layer sorts ahead of order.** A higher layer always draws after a
    /// lower one, whatever its `order`, so a subtree lifted onto its own layer
    /// paints above every sibling regardless of how those siblings' `order`
    /// values compare. Within one layer, `order` decides exactly as before.
    ///
    /// **Idempotent by construction, and that is a checked property, not an
    /// accident.** `rects`/`glyphs` are permuted into global order below, and
    /// the `sequence` and `layer` arrays are rebuilt in that same permuted
    /// order in the same pass — so after this method returns,
    /// `rectSequence[i]` and `rectLayer[i]` are always the sequence
    /// number and layer of `rects[i]` (and likewise for glyphs). A version
    /// that permutes the primitive arrays but leaves `sequence`/`layer` as
    /// they were would still pass on a scene's *first* `finalize()` — the
    /// arrays are still in emission order at that point — and only misbehave
    /// on a second call, where the stale entries no longer correspond to the
    /// now-reordered primitives and can silently tiebreak equal orders the
    /// other way. Pinned by `finalizingTwiceGivesTheSameDrawList`.
    ///
    /// Measured by mutation on the four-array form, the two halves have
    /// different pins: leaving `rectSequence`/`glyphSequence` unpermuted
    /// reddens `finalizingTwiceGivesTheSameDrawList`, leaving
    /// `rectLayer`/`glyphLayer` unpermuted reddens
    /// `finalizingTwiceWithDistinctLayersStaysStable`, neither reddens the
    /// other's test, and `aSecondFinalizeReproducesTheCapturedOutput` catches
    /// both.
    ///
    /// **An image run also breaks where the texture changes** (ruling TE-AF
    /// item 4): a run is one instanced draw with one texture bound, so two
    /// adjacent images sampling different textures are two runs, and the
    /// number of runs stays the draw-call count. Images keep their
    /// `texture` index through the permutation — it indexes ``textures``,
    /// which is never reordered. Pinned by `imageRunsBreakWhereTheTextureChanges`.
    /// **A surface run breaks where its target changes**, for the same reason
    /// (ruling `MV-C` item 2); pinned by `surfaceRunsBreakWhereTheTargetChanges`.
    public mutating func finalize() {
        let rectCount = rects.count
        let glyphCount = glyphs.count
        let imageCount = images.count
        let surfaceCount = surfaces.count

        // (layer, order, sequence, kind, indexWithinKind)
        var merged: [(Int, MUIUInt, Int, PrimitiveKind, Int)] = []
        merged.reserveCapacity(rectCount + glyphCount + imageCount + surfaceCount)
        for i in 0..<rectCount {
            merged.append((rectLayer[i], rects[i].order, rectSequence[i], .rect, i))
        }
        for i in 0..<glyphCount {
            merged.append((glyphLayer[i], glyphs[i].order, glyphSequence[i], .glyph, i))
        }
        for i in 0..<imageCount {
            merged.append((imageLayer[i], images[i].order, imageSequence[i], .image, i))
        }
        for i in 0..<surfaceCount {
            merged.append((surfaceLayer[i], surfaces[i].order, surfaceSequence[i], .surface, i))
        }
        merged.sort { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }

        // One walk over `merged` fills every permuted array and the draw list.
        // Written into locals and assigned once at the end, so no stored array
        // is read while it is being rebuilt: `rects[entry.4]` below always
        // indexes the pre-permutation array.
        var sortedRects: [MUIRect] = []
        var sortedGlyphs: [MUIGlyph] = []
        var sortedRectSequence: [Int] = []
        var sortedGlyphSequence: [Int] = []
        var sortedRectLayer: [Int] = []
        var sortedGlyphLayer: [Int] = []
        var sortedImages: [MUIImage] = []
        var sortedImageSequence: [Int] = []
        var sortedImageLayer: [Int] = []
        var sortedSurfaces: [MUIImage] = []
        var sortedSurfaceSequence: [Int] = []
        var sortedSurfaceLayer: [Int] = []
        var runs: [DrawRun] = []
        sortedRects.reserveCapacity(rectCount)
        sortedRectSequence.reserveCapacity(rectCount)
        sortedRectLayer.reserveCapacity(rectCount)
        sortedGlyphs.reserveCapacity(glyphCount)
        sortedGlyphSequence.reserveCapacity(glyphCount)
        sortedGlyphLayer.reserveCapacity(glyphCount)
        sortedImages.reserveCapacity(imageCount)
        sortedImageSequence.reserveCapacity(imageCount)
        sortedImageLayer.reserveCapacity(imageCount)
        sortedSurfaces.reserveCapacity(surfaceCount)
        sortedSurfaceSequence.reserveCapacity(surfaceCount)
        sortedSurfaceLayer.reserveCapacity(surfaceCount)

        for entry in merged {
            let kind = entry.3
            // Rebuild sequence AND layer in the SAME merged order as the
            // primitive arrays, so both stay aligned with them across repeated
            // `finalize()` calls (ruling PF-1) — a version that left the old
            // arrays in place would desync from `rects`/`glyphs` after this
            // permutation.
            let start: Int
            // An image continues the previous run only while it samples the
            // same texture as that run's images; a surface only while it
            // samples the same target (`MV-C` item 2).
            var sameTexture = true
            switch kind {
            case .rect:
                start = sortedRects.count
                sortedRects.append(rects[entry.4])
                sortedRectSequence.append(entry.2)
                sortedRectLayer.append(entry.0)
            case .glyph:
                start = sortedGlyphs.count
                sortedGlyphs.append(glyphs[entry.4])
                sortedGlyphSequence.append(entry.2)
                sortedGlyphLayer.append(entry.0)
            case .image:
                start = sortedImages.count
                let image = images[entry.4]
                if let previous = sortedImages.last { sameTexture = previous.texture == image.texture }
                sortedImages.append(image)
                sortedImageSequence.append(entry.2)
                sortedImageLayer.append(entry.0)
            case .surface:
                start = sortedSurfaces.count
                let quad = surfaces[entry.4]
                if let previous = sortedSurfaces.last { sameTexture = previous.texture == quad.texture }
                sortedSurfaces.append(quad)
                sortedSurfaceSequence.append(entry.2)
                sortedSurfaceLayer.append(entry.0)
            }
            if let last = runs.last, last.kind == kind, sameTexture {
                runs[runs.count - 1] =
                    DrawRun(kind: kind, start: last.start, count: last.count + 1)
            } else {
                runs.append(DrawRun(kind: kind, start: start, count: 1))
            }
        }

        rects = sortedRects
        glyphs = sortedGlyphs
        rectSequence = sortedRectSequence
        glyphSequence = sortedGlyphSequence
        rectLayer = sortedRectLayer
        glyphLayer = sortedGlyphLayer
        images = sortedImages
        imageSequence = sortedImageSequence
        imageLayer = sortedImageLayer
        surfaces = sortedSurfaces
        surfaceSequence = sortedSurfaceSequence
        surfaceLayer = sortedSurfaceLayer
        drawList = runs
    }
}
