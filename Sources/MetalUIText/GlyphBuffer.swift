/// Capacity classes and a kept buffer for per-text glyph arrays (`G50`, record 415).
///
/// **Why.** A growing text is placed again on every frame at a few glyphs longer, and an array reserved
/// at its exact count is a slightly larger malloc request than the block the frame before freed, so
/// malloc's large-block cache can never reuse one: a 14 KB streamed message left sixty freed 3 MB
/// blocks behind (190 MiB of `phys_footprint`). A capacity rounded up to a quarter-power-of-two step
/// is the same request for the next dozens of frames, and a buffer kept between calls is the same block.
///
/// **Bounds.** At most one kept buffer per system, never above ``maximumKeptCapacity`` elements, dropped
/// when the next request needs under a quarter of it; rounding wastes at most 25 percent.
package enum GlyphCapacity {
    /// The largest buffer a system keeps between calls: 64 Ki glyphs, 5 MB of `TextGlyph`.
    package static let maximumKeptCapacity = 65_536

    /// `count` rounded up to the next quarter step of its power of two (exact below 64).
    package static func rounded(_ count: Int) -> Int {
        guard count > 64 else { return count }
        let power = 1 << (Int.bitWidth - 1 - count.leadingZeroBitCount)
        let step = power / 4
        return (count + step - 1) / step * step
    }
}

/// One array's storage, handed out empty with room for `minimumCapacity` and taken back by `keep`.
package struct KeptBuffer<Element> {
    private var kept: [Element] = []
    /// Times `take` handed back the storage it kept.
    package private(set) var reuses = 0

    package init() {}

    /// An empty array with room for `minimumCapacity`; the kept storage when it fits and is not wastefully large.
    package mutating func take(minimumCapacity: Int) -> [Element] {
        var buffer = kept
        kept = []
        let wanted = GlyphCapacity.rounded(minimumCapacity)
        if buffer.capacity >= minimumCapacity, buffer.capacity <= wanted * 4 + 256 {
            reuses += 1
            buffer.removeAll(keepingCapacity: true)
            return buffer
        }
        buffer = []
        buffer.reserveCapacity(wanted)
        return buffer
    }

    /// Keeps `buffer`'s storage for the next `take`, unless it is above the bound.
    package mutating func keep(_ buffer: [Element]) {
        kept = buffer.capacity <= GlyphCapacity.maximumKeptCapacity ? buffer : []
    }
}
