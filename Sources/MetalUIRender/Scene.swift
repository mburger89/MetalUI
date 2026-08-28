import MetalUIShaderTypes

/// Primitives accumulated during a frame's paint phase.
///
/// One array per primitive type rather than one heterogeneous array, because
/// each type is a separate GPU pipeline and a separate instanced draw: a mixed
/// array would be re-partitioned at encode time on every frame. The cost is
/// that `order` no longer totally orders the scene — see ``finalize()``.
public struct Scene: Sendable {
    public private(set) var rects: [MUIRect] = []

    /// Glyph sprites (`monochromeSprite`, spec 7.1).
    ///
    /// **They are drawn after every rect, whatever their `order`.** See
    /// ``finalize()``.
    public private(set) var glyphs: [MUIGlyph] = []

    public init() {}

    /// **Both arrays, and each of the three members below reads both.** A
    /// `Scene` holding only glyphs is not empty: `Renderer.encode` returns early
    /// on an empty scene, so a rects-only `isEmpty` would silently draw no text
    /// in any frame whose paint emitted glyphs and no rect — a blank run with no
    /// error anywhere. Pinned by `aSceneHoldingOnlyAGlyphIsNotEmpty`.
    public var isEmpty: Bool { rects.isEmpty && glyphs.isEmpty }

    public mutating func insert(_ rect: MUIRect) {
        rects.append(rect)
    }

    public mutating func insert(_ glyph: MUIGlyph) {
        glyphs.append(glyph)
    }

    public mutating func clear() {
        rects.removeAll(keepingCapacity: true)
        glyphs.removeAll(keepingCapacity: true)
    }

    /// Sorts primitives into paint order. Stable, so equal orders keep
    /// insertion sequence — painters at the same layer must stack predictably.
    ///
    /// **`order` sorts WITHIN a primitive type and not between them.** Every
    /// glyph is drawn after every rect regardless of order, because the two are
    /// separate pipelines encoded one after the other. That is right for the
    /// only composition M2 produces — a `Text` draws its own background rect and
    /// then its glyphs — and it is wrong for a rect that should occlude text
    /// beneath it, which needs either a depth buffer or an interleaved
    /// batch-per-order encode. Named here rather than left to be discovered:
    /// nothing in this repo can see a glyph painted through a rect.
    public mutating func finalize() {
        rects = rects.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
        glyphs = glyphs.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }
}
