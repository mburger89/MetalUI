import MetalUIShaderTypes

/// Which pipeline a primitive belongs to. One case per instanced draw.
public enum PrimitiveKind: Sendable, Equatable { case rect, glyph }

/// One instanced draw: `count` primitives of `kind`, starting at `start` in
/// that kind's own array.
///
/// **The number of runs IS the draw-call count** (spec §7.3: "draw-call count
/// is the number of type transitions in z-order"). That makes the promise
/// assertable rather than architectural — see `DrawListTests`.
public struct DrawRun: Sendable, Equatable {
    public let kind: PrimitiveKind
    public let start: Int
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
    public private(set) var rects: [MUIRect] = []

    /// Glyph sprites (`monochromeSprite`, spec 7.1).
    public private(set) var glyphs: [MUIGlyph] = []

    /// Built by ``finalize()``. Empty until then.
    public private(set) var drawList: [DrawRun] = []

    /// Emission sequence per kind, so `finalize()` can tiebreak equal orders
    /// across types. Not public: it is bookkeeping for one method.
    private var sequence: [PrimitiveKind: [Int]] = [.rect: [], .glyph: []]
    private var nextSequence = 0

    public init() {}

    /// **Both arrays, and each of the three members below reads both.** A
    /// `Scene` holding only glyphs is not empty: `Renderer.encode` returns early
    /// on an empty scene, so a rects-only `isEmpty` would silently draw no text
    /// in any frame whose paint emitted glyphs and no rect — a blank run with no
    /// error anywhere. Pinned by `aSceneHoldingOnlyAGlyphIsNotEmpty`.
    public var isEmpty: Bool { rects.isEmpty && glyphs.isEmpty }

    public mutating func insert(_ rect: MUIRect) {
        rects.append(rect)
        sequence[.rect]!.append(nextSequence)
        nextSequence += 1
    }

    public mutating func insert(_ glyph: MUIGlyph) {
        glyphs.append(glyph)
        sequence[.glyph]!.append(nextSequence)
        nextSequence += 1
    }

    public mutating func clear() {
        rects.removeAll(keepingCapacity: true)
        glyphs.removeAll(keepingCapacity: true)
        drawList.removeAll(keepingCapacity: true)
        sequence = [.rect: [], .glyph: []]
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
    /// layer must stack predictably, and a merged sort across two arrays has no
    /// inherent order between them — the sequence number is what supplies one.
    /// Pinned by `equalOrdersKeepEmissionSequenceAcrossTypes`.
    ///
    /// **Idempotent by construction, and that is a checked property, not an
    /// accident.** `rects`/`glyphs` are permuted into global order below, and
    /// the `sequence` arrays are rebuilt in that same permuted order in the
    /// same pass — so after this method returns, `sequence[.rect]![i]` and
    /// `sequence[.glyph]![i]` are always the sequence numbers of `rects[i]` and
    /// `glyphs[i]`. A version that permutes the primitive arrays but leaves
    /// `sequence` as it was would still pass on a scene's *first* `finalize()`
    /// — the arrays are still in emission order at that point — and only
    /// misbehave on a second call, where the stale sequence numbers no longer
    /// correspond to the now-reordered primitives and can silently tiebreak
    /// equal orders the other way. Pinned by `finalizingTwiceGivesTheSameDrawList`.
    public mutating func finalize() {
        // (order, sequence, kind, indexWithinKind)
        var merged: [(MUIUInt, Int, PrimitiveKind, Int)] = []
        merged.reserveCapacity(rects.count + glyphs.count)
        for (i, r) in rects.enumerated() { merged.append((r.order, sequence[.rect]![i], .rect, i)) }
        for (i, g) in glyphs.enumerated() { merged.append((g.order, sequence[.glyph]![i], .glyph, i)) }
        merged.sort { ($0.0, $0.1) < ($1.0, $1.1) }

        let sortedRects = merged.filter { $0.2 == .rect }
        let sortedGlyphs = merged.filter { $0.2 == .glyph }
        rects = sortedRects.map { rects[$0.3] }
        glyphs = sortedGlyphs.map { glyphs[$0.3] }
        // Rebuild sequence in the SAME merged order as the primitive arrays
        // above, so it stays aligned with them across repeated `finalize()`
        // calls (ruling PF-1) — a version that left the old sequence arrays in
        // place would desync from `rects`/`glyphs` after this permutation.
        sequence[.rect] = sortedRects.map(\.1)
        sequence[.glyph] = sortedGlyphs.map(\.1)

        drawList = []
        var rectCursor = 0
        var glyphCursor = 0
        for entry in merged {
            let kind = entry.2
            let cursor = kind == .rect ? rectCursor : glyphCursor
            if let last = drawList.last, last.kind == kind {
                drawList[drawList.count - 1] =
                    DrawRun(kind: kind, start: last.start, count: last.count + 1)
            } else {
                drawList.append(DrawRun(kind: kind, start: cursor, count: 1))
            }
            if kind == .rect { rectCursor += 1 } else { glyphCursor += 1 }
        }
    }
}
