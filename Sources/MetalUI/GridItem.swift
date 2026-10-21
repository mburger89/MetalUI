import MetalUICore
import MetalUILayout

/// SwiftUI's `GridItem`: the description of one column of a `LazyVGrid`, or one row of a `LazyHGrid`
/// (item L1; probe `docs/probes/swiftui-lazy-containers.swift` arms C1-C17).
///
/// ```swift
/// LazyVGrid(columns: [GridItem(.fixed(80)), GridItem(.adaptive(minimum: 60, maximum: 120))]) { ... }
/// ```
///
/// How the tracks are sized (the probe's figures, `LZ-K`): a `.fixed` item is exact; the room left after
/// the fixed items and the gaps is shared equally by the flexible and adaptive items, a flexible item whose
/// minimum exceeds its share taking the minimum first and the others the rest, a share above a maximum
/// clamped to it with the excess NOT given back; an `.adaptive` item packs as many tracks of at least its
/// minimum as fit. The tracks together are placed in the grid's extent by the grid's `alignment:` and the
/// grid is as wide as the larger of the proposal and the tracks. **Differences from SwiftUI:** lengths are
/// `Pixels` and `alignment` is the nine-case ``ProposalAlignment`` (`nil` takes the grid's alignment, as
/// SwiftUI's `Alignment?`); an adaptive item beside a flexible or another adaptive item is unprobed and
/// shares the room equally between them.
public struct GridItem: Sendable, Hashable {
    /// How a track is sized.
    public enum Size: Sendable, Hashable {
        /// A track of exactly this length.
        case fixed(Pixels)
        /// A track that shares the room equally, between `minimum` and `maximum`.
        case flexible(minimum: Pixels = Pixels(10), maximum: Pixels = .infinity)
        /// As many tracks of at least `minimum` (and at most `maximum` each) as fit, sharing the room.
        case adaptive(minimum: Pixels, maximum: Pixels = .infinity)
    }

    /// How the track (or tracks, for an adaptive item) is sized.
    public var size: Size
    /// The gap after this item's track (its last track, for an adaptive item); `nil` is 8, the grid's
    /// default. The last item's gap is not drawn. The grid's own `spacing:` is the gap between lines.
    public var spacing: Pixels?
    /// Where a cell sits in its track; `nil` takes the grid's `alignment:`.
    public var alignment: ProposalAlignment?

    /// A grid item.
    ///
    /// - Parameters:
    ///   - size: How the track is sized; `.flexible()` by default.
    ///   - spacing: The gap after the track; `nil` is 8.
    ///   - alignment: Where a cell sits in its track; `nil` is the grid's.
    public init(_ size: Size = .flexible(), spacing: Pixels? = nil, alignment: ProposalAlignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }

    /// The solver's description of this item (`LZ-K`).
    var spec: GridTrackSpec {
        let gap = Double((spacing ?? Pixels(8)).value)
        switch size {
        case .fixed(let length):
            return .fixed(Double(length.value), spacing: gap)
        case .flexible(let minimum, let maximum):
            return .flexible(minimum: Double(minimum.value), maximum: Double(maximum.value), spacing: gap)
        case .adaptive(let minimum, let maximum):
            return .adaptive(minimum: Double(minimum.value), maximum: Double(maximum.value), spacing: gap)
        }
    }
}
