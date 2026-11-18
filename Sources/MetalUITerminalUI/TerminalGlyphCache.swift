import MetalUIScene
import MetalUITextSystem

/// Shaped graphemes and synthesised glyphs for one face at one scale (`TRM-AZ`).
///
/// A grapheme cluster, bold and italic select a face (regular, bold, italic or bold italic of the same family);
/// the text system places the cluster once, at the cell's left edge on the cell's top, through its own font
/// fallback (CoreText's cascade on macOS, `shapeCascading` on the portable system, `FB-A`), and the placements
/// (atlas key, whole-pixel offset, baseline row) are kept. A cell's draw is then a table read and an atlas probe
/// per glyph, with no shaping. ASCII is a flat table index (`style * 128 + byte`): no hashing, no allocation.
/// A wide cluster is placed as one run and spans two cells; a combining mark is part of its cluster.
///
/// **Invalidation.** The cache is for one text system, family and scale (a new scale makes a new cache), and is
/// emptied whenever the atlas's `layoutGeneration` differs from the one it last saw (`GL-D`), which
/// ``prepare(for:)`` checks once per frame. Colour emoji draw monochrome through the R8 atlas and ligatures are
/// off: a cluster is placed one cluster at a time, so no cross-cell shaping happens (`TRM-C` item 10).
@MainActor
package final class TerminalGlyphCache {
    /// One placed glyph of a cluster: its atlas key and its pen offset from the cell's top-left, in device pixels.
    package struct Placed: Equatable {
        package let key: GlyphKey
        package let pixelX: Int
        package let baselineY: Int
    }

    /// What a cell draws.
    package enum Drawing: Equatable {
        /// Nothing (a space).
        case blank
        /// The shaped glyphs of entry `index` (``glyphs(at:)``).
        case glyphs(Int)
        /// The synthesised glyph of entry `index` (``synthetic(at:)``).
        case synthetic(Int)
    }

    /// A synthesised glyph: rectangles in the cell, or a cell-sized bitmap under `key`.
    package struct SyntheticEntry {
        package let scalar: UInt32
        package let rects: [CellRect]?
        package let key: GlyphKey?
    }

    /// The text system placing and rasterizing.
    package let system: any TextSystem
    /// The cell grid.
    package let metrics: TerminalCellMetrics
    /// Regular, bold, italic and bold italic.
    package let fonts: [FontKey]

    /// How many clusters were handed to the text system, since creation: the count a warm frame leaves unchanged.
    package private(set) var shapedClusters = 0
    /// How many synthesised glyphs were built.
    package private(set) var syntheticBuilds = 0
    /// How many times a new atlas generation emptied the cache.
    package private(set) var rebuilds = 0

    private var entries: [[Placed]] = []
    private var asciiIndex = [Int32](repeating: -1, count: 4 * 128)
    private struct ClusterKey: Hashable {
        let cluster: String
        let style: UInt8
    }
    private var clusterIndex: [ClusterKey: Int32] = [:]
    private var syntheticEntries: [SyntheticEntry] = []
    private var syntheticIndex: [UInt32: Int32] = [:]
    private var seenGeneration: Int?
    private weak var seenAtlas: GlyphAtlas?

    /// A placed glyph with its atlas slot (`TRM-BL`).
    package struct Sprite {
        package let pixelX: Int
        package let baselineY: Int
        package let packed: PackedGlyph
    }
    /// Per entry: the drawable sprites in this atlas layout, or nil until first drawn, and the atlas frame whose
    /// `packed(for:)` stamp last covered them.
    private var sprites: [[Sprite]?] = []
    private var stamps: [Int] = []

    /// A cache over `family` at `size` points and `scale`. `family` names a monospace face (`nil`: the system's
    /// default face, which is rarely monospace, so a caller passes one); bold uses weight 0.4 (SwiftUI's `.bold`).
    package init(system: any TextSystem, family: String?, size: Double, scale: Float, design: FontDesign = .default) {
        self.system = system
        let styles: [(Double?, Bool)] = [(nil, false), (0.4, false), (nil, true), (0.4, true)]
        fonts = styles.map { weight, italic in
            system.resolveFont(FontDescriptor(family: family, size: size, weight: weight, italic: italic, design: design))
        }
        metrics = TerminalCellMetrics.measure(fonts[0], in: system, scale: scale)
    }

    /// Empties the cache if `atlas` was rebuilt since the last call (`layoutGeneration` moved).
    package func prepare(for atlas: GlyphAtlas) {
        guard seenGeneration != atlas.layoutGeneration || seenAtlas !== atlas else { return }
        if seenGeneration != nil { rebuilds += 1 }
        seenGeneration = atlas.layoutGeneration
        seenAtlas = atlas
        entries.removeAll(keepingCapacity: true)
        sprites.removeAll(keepingCapacity: true)
        stamps.removeAll(keepingCapacity: true)
        for i in asciiIndex.indices { asciiIndex[i] = -1 }
        clusterIndex.removeAll(keepingCapacity: true)
        syntheticEntries.removeAll(keepingCapacity: true)
        syntheticIndex.removeAll(keepingCapacity: true)
    }

    /// The drawing of the cluster whose UTF-8 is `bytes`, shaping it on first sight.
    package func drawing(for bytes: ArraySlice<UInt8>, bold: Bool, italic: Bool) -> Drawing {
        let style = (bold ? 1 : 0) | (italic ? 2 : 0)
        // `bytes[startIndex]`, not `first`: the generic `first` allocates in a debug build.
        if bytes.count == 1, bytes[bytes.startIndex] < 0x80 {
            let byte = bytes[bytes.startIndex]
            if byte == 0x20 { return .blank }
            let slot = style * 128 + Int(byte)
            let found = asciiIndex[slot]
            if found >= 0 { return .glyphs(Int(found)) }
            let index = shape(String(UnicodeScalar(byte)), style: style)
            asciiIndex[slot] = Int32(index)
            return .glyphs(index)
        }
        let cluster = String(decoding: bytes, as: UTF8.self)
        let scalars = cluster.unicodeScalars
        if scalars.count == 1, let scalar = scalars.first, SyntheticGlyphs.kind(of: scalar.value) != nil {
            return .synthetic(syntheticEntry(scalar.value))
        }
        if cluster.isEmpty || scalars.allSatisfy({ $0 == " " }) { return .blank }
        let key = ClusterKey(cluster: cluster, style: UInt8(style))
        if let found = clusterIndex[key] { return .glyphs(Int(found)) }
        let index = shape(cluster, style: style)
        clusterIndex[key] = Int32(index)
        return .glyphs(index)
    }

    /// The placements of entry `index`.
    package func glyphs(at index: Int) -> [Placed] { entries[index] }

    /// The sprites of entry `index` in `atlas` (those with ink), packing them on first use. The atlas probe, a hash of the
    /// glyph key, is made once per entry per layout and once more per atlas frame (the stamp that keeps a glyph live,
    /// `GL-A`), not once per cell (`TRM-BL`). An entry the atlas could not hold is not kept, so it is retried.
    package func sprites(at index: Int, in atlas: GlyphAtlas) -> [Sprite] {
        if let kept = sprites[index] {
            if stamps[index] != atlas.currentGeneration {
                for placed in entries[index] { _ = atlas.packed(for: placed.key, rasterize: { system.rasterize(placed.key) }) }
                stamps[index] = atlas.currentGeneration
            }
            return kept
        }
        var out: [Sprite] = []
        var complete = true
        for placed in entries[index] {
            guard let packed = atlas.packed(for: placed.key, rasterize: { system.rasterize(placed.key) }) else {
                complete = false
                continue
            }
            if packed.slot.width > 0, packed.slot.height > 0 {
                out.append(Sprite(pixelX: placed.pixelX, baselineY: placed.baselineY, packed: packed))
            }
        }
        if complete {
            sprites[index] = out
            stamps[index] = atlas.currentGeneration
        }
        return out
    }

    /// The synthesised glyph of entry `index`.
    package func synthetic(at index: Int) -> SyntheticEntry { syntheticEntries[index] }

    private func shape(_ cluster: String, style: Int) -> Int {
        shapedClusters += 1
        let placed = system.placeGlyphs(cluster, font: fonts[style], wrappingAt: nil, options: TextLayoutOptions(),
                                        origin: (x: 0, y: 0), scaleFactor: metrics.scale)
        entries.append(placed.map { Placed(key: $0.key, pixelX: $0.pixelX, baselineY: $0.baselineY) })
        sprites.append(nil)
        stamps.append(-1)
        return entries.count - 1
    }

    private func syntheticEntry(_ scalar: UInt32) -> Int {
        if let found = syntheticIndex[scalar] { return Int(found) }
        syntheticBuilds += 1
        let cw = metrics.cellWidth, ch = metrics.cellHeight
        let entry: SyntheticEntry
        if SyntheticGlyphs.kind(of: scalar) == .rects {
            entry = SyntheticEntry(scalar: scalar, rects: SyntheticGlyphs.rects(for: scalar, cellWidth: cw, cellHeight: ch),
                                   key: nil)
        } else {
            entry = SyntheticEntry(scalar: scalar, rects: nil, key: Self.syntheticKey(scalar: scalar, cellWidth: cw, cellHeight: ch))
        }
        syntheticEntries.append(entry)
        syntheticIndex[scalar] = Int32(syntheticEntries.count - 1)
        return syntheticEntries.count - 1
    }

    /// The atlas key of a synthesised bitmap: a font no resolver can produce, naming the cell size, so a glyph of
    /// one cell size never serves another (`TRM-AZ`).
    package static func syntheticKey(scalar: UInt32, cellWidth: Int, cellHeight: Int) -> GlyphKey {
        GlyphKey(font: FontKey(resolvedPostScriptName: "MetalUI.Terminal.Synthetic.\(cellWidth)x\(cellHeight)", size: 1,
                               variations: [], matrix: FontKey.Matrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)),
                 glyph: UInt16(truncatingIfNeeded: scalar), size: 1, subpixelVariant: 0, scaleFactor: 1)
    }
}
