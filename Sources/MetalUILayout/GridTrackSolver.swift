// `GridTrackSolver` (item L1, lane 2, ruling `LZ-K`; probe `docs/probes/swiftui-lazy-containers.swift` arms
// C1-C7, C12, C13, C15-C17 and `swiftui-lazy-grid-scope.swift` LZ4).
//
// Pure and Foundation-free (no `floor`: the one rounding is an integer division of a non-negative `Double`
// truncated through `Int`), so Linux and Windows run it in `MetalUILayoutTests` and a lazy grid's tracks are
// bit-identical on every platform. A `GridItem`'s lengths arrive as `Double`s through `GridTrackSpec`.

/// One declared grid item, as the solver reads it.
package struct GridTrackSpec: Sendable, Hashable {
    package enum Kind: Sendable, Hashable { case fixed, flexible, adaptive }

    package var kind: Kind
    /// A fixed item's size, a flexible or adaptive item's minimum.
    package var minimum: Double
    /// A flexible or adaptive item's maximum (`.infinity` when unbounded); a fixed item's size.
    package var maximum: Double
    /// The gap after the item's track (its last track, for an adaptive item), `8` by default (probe C7).
    package var spacing: Double

    package init(kind: Kind, minimum: Double, maximum: Double, spacing: Double) {
        self.kind = kind
        self.minimum = minimum
        self.maximum = maximum
        self.spacing = spacing
    }

    /// A track of exactly `size`.
    package static func fixed(_ size: Double, spacing: Double = 8) -> GridTrackSpec {
        GridTrackSpec(kind: .fixed, minimum: size, maximum: size, spacing: spacing)
    }

    /// A track that shares the room equally, between `minimum` and `maximum`.
    package static func flexible(minimum: Double = 10, maximum: Double = .infinity,
                                 spacing: Double = 8) -> GridTrackSpec {
        GridTrackSpec(kind: .flexible, minimum: minimum, maximum: maximum, spacing: spacing)
    }

    /// As many tracks of at least `minimum` as fit.
    package static func adaptive(minimum: Double, maximum: Double = .infinity,
                                 spacing: Double = 8) -> GridTrackSpec {
        GridTrackSpec(kind: .adaptive, minimum: minimum, maximum: maximum, spacing: spacing)
    }
}

/// One resolved track.
package struct GridTrack: Sendable, Hashable {
    /// Its extent along the cross axis.
    package var size: Double
    /// The gap after it (the last track's is not counted in `total`).
    package var gapAfter: Double
    /// The declared item it came from (an adaptive item makes several).
    package var item: Int
}

/// The tracks of a grid, placed in an available extent.
package struct GridTrackResolution: Sendable, Hashable {
    package var tracks: [GridTrack]
    /// Where the first track starts, from the available extent's start.
    package var origin: Double
    /// The tracks and the gaps between them.
    package var total: Double
    /// The grid's extent across: `max(available, total)`, 0 for no tracks.
    package var width: Double
}

package enum GridTrackSolver {
    /// Resolves `items` in `available` (probe C1-C7, C15-C17).
    ///
    /// Fixed items are exact. The room left after them and the declared gaps (every item's `spacing`
    /// but the last item's) is shared equally by the flexible and adaptive items: a flexible item whose
    /// minimum exceeds the equal share takes its minimum first and the rest share what is left (C15), then
    /// each flexible item takes the share clamped to its maximum WITHOUT giving the excess back (C4, C6);
    /// an adaptive item packs its share into `n = max(1, (share + s) / (minimum + s))` tracks (integer
    /// division) of `(share - (n - 1) s) / n` clamped to its maximum (C1-C3, C16, C17). The tracks together
    /// are placed in `available` by `alignment` (0 leading, 0.5 centre, 1 trailing; C8) and overflow to the
    /// right from the origin 0 when they do not fit (C5). **Two adaptive items, or an adaptive beside a
    /// flexible one, are unprobed:** the equal share is MetalUI's own ruling (`LZ-K`).
    package static func resolve(_ items: [GridTrackSpec], available: Double, alignment: Double) -> GridTrackResolution {
        guard !items.isEmpty else { return GridTrackResolution(tracks: [], origin: 0, total: 0, width: 0) }
        let room = Swift.max(0, available)
        var rest = room
        for (index, item) in items.enumerated() {
            if item.kind == .fixed { rest -= item.minimum }
            if index < items.count - 1 { rest -= item.spacing }
        }
        // The shared pool: flexible and adaptive items.
        var pool = items.indices.filter { items[$0].kind != .fixed }
        var shares = [Int: Double]()
        var remaining = rest
        var share = pool.isEmpty ? 0 : remaining / Double(pool.count)
        while !pool.isEmpty {
            let overflowing = pool.filter { items[$0].kind == .flexible && items[$0].minimum > share }
            if overflowing.isEmpty { break }
            for index in overflowing {
                shares[index] = items[index].minimum
                remaining -= items[index].minimum
            }
            pool.removeAll { overflowing.contains($0) }
            share = pool.isEmpty ? 0 : remaining / Double(pool.count)
        }
        var tracks: [GridTrack] = []
        for (index, item) in items.enumerated() {
            switch item.kind {
            case .fixed:
                tracks.append(GridTrack(size: item.minimum, gapAfter: item.spacing, item: index))
            case .flexible:
                let size = shares[index] ?? Swift.min(Swift.max(share, item.minimum), item.maximum)
                tracks.append(GridTrack(size: size, gapAfter: item.spacing, item: index))
            case .adaptive:
                let room = Swift.max(0, share)
                let gap = item.spacing
                let step = item.minimum + gap
                let count = step > 0 ? Swift.max(1, Int((room + gap) / step)) : 1
                let size = Swift.max(0, Swift.min((room - Double(count - 1) * gap) / Double(count), item.maximum))
                for _ in 0..<count { tracks.append(GridTrack(size: size, gapAfter: gap, item: index)) }
            }
        }
        var total = 0.0
        for (position, track) in tracks.enumerated() {
            total += track.size
            if position < tracks.count - 1 { total += track.gapAfter }
        }
        let origin = total < room ? (room - total) * alignment : 0
        return GridTrackResolution(tracks: tracks, origin: origin, total: total, width: Swift.max(room, total))
    }

    /// The extent a grid asks for when it is offered none (probe LZ4, C12): each declared item is one
    /// track (an adaptive item makes one), a fixed item its own size and any other the width its first-line
    /// cell asks for (`0` for a missing cell), the declared gaps between them. The result is then resolved
    /// as an ordinary available extent, so two flexible columns holding cells 30 and 20 wide share 50 as 25
    /// each.
    package static func availableForUnspecified(_ items: [GridTrackSpec], firstLine: [Double]) -> Double {
        var extent = 0.0
        for (index, item) in items.enumerated() {
            extent += item.kind == .fixed ? item.minimum : (index < firstLine.count ? firstLine[index] : 0)
            if index < items.count - 1 { extent += item.spacing }
        }
        return extent
    }
}
