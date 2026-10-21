import Testing
import MetalUICore
@testable import MetalUILayout

// Lazy containers, lane 2: `GridTrackSolver` (test 3.1, ruling `LZ-K`; probe
// `docs/probes/swiftui-lazy-containers.swift` arms C1-C7, C12, C15-C17, whose recorded figures are the
// literals here). The solver is pure and Foundation-free, so Linux runs it in this target. Red-before
// (record section 134): the type did not exist, so the file failed to compile
// (`cannot find 'GridTrackSolver' in scope`).
//
// Each helper returns the tracks' sizes and the x origin of each track (the grid origin plus the
// sizes and gaps before it), the two facts a probe cell position is derived from.

private func sizes(_ resolution: GridTrackResolution) -> [Double] { resolution.tracks.map(\.size) }

private func starts(_ resolution: GridTrackResolution) -> [Double] {
    var x = resolution.origin
    var result: [Double] = []
    for track in resolution.tracks {
        result.append(x)
        x += track.size + track.gapAfter
    }
    return result
}

private func near(_ a: [Double], _ b: [Double], _ tolerance: Double = 1e-9) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
}

/// **3.1a (probe C1-C3, C16, C17; `LZ-K`).** Adaptive items: `n = floor((rest + s) / (min + s))` columns of
/// `(rest - (n - 1) s) / n`, clamped to the maximum, `rest` being what the fixed items and the gaps leave.
/// C1: `adaptive(20...50)` at 200, spacing 8: n = floor(208 / 28) = 7 of (200 - 48) / 7 = 21.714.
/// C2: `(60...70)`: n = floor(208 / 68) = 3 of (200 - 16) / 3 = 61.333. C3: `adaptive(45)` spacing 20:
/// n = floor(220 / 65) = 3 of (200 - 40) / 3 = 53.333. C16: `(60...70)` at 100: n = floor(108 / 68) = 1,
/// 100 clamped to 70, centred at (100 - 70) / 2 = 15. C17: `fixed(40)` then `adaptive(30)`: rest = 200 -
/// 40 - 8 = 152, n = floor(160 / 38) = 4 of (152 - 24) / 4 = 32 (the fixed item at 0 and the four tracks at 48, 88, 128, 168).
/// Mutations: `floor` -> `ceil` (C1: 8 columns); the maximum clamp dropped (C2 and C16 widths).
@Test func adaptiveItemsPackAsTheProbeSays() {
    let c1 = GridTrackSolver.resolve([.adaptive(minimum: 20, maximum: 50)], available: 200, alignment: 0.5)
    #expect(c1.tracks.count == 7)
    #expect(near(sizes(c1), Array(repeating: 152.0 / 7.0, count: 7)), "\(sizes(c1))")
    #expect(abs(c1.origin) < 1e-9 && abs(c1.width - 200) < 1e-9)

    let c2 = GridTrackSolver.resolve([.adaptive(minimum: 60, maximum: 70)], available: 200, alignment: 0.5)
    #expect(near(sizes(c2), Array(repeating: 184.0 / 3.0, count: 3)), "\(sizes(c2))")

    let c3 = GridTrackSolver.resolve([.adaptive(minimum: 45, spacing: 20)], available: 200, alignment: 0.5)
    #expect(near(sizes(c3), Array(repeating: 160.0 / 3.0, count: 3)), "\(sizes(c3))")
    #expect(c3.tracks.dropLast().allSatisfy { $0.gapAfter == 20 })

    let c16 = GridTrackSolver.resolve([.adaptive(minimum: 60, maximum: 70)], available: 100, alignment: 0.5)
    #expect(sizes(c16) == [70] && c16.origin == 15 && c16.width == 100, "\(sizes(c16)) \(c16.origin)")

    let c17 = GridTrackSolver.resolve([.fixed(40), .adaptive(minimum: 30)], available: 200, alignment: 0.5)
    #expect(sizes(c17) == [40, 32, 32, 32, 32], "\(sizes(c17))")
    #expect(starts(c17) == [0, 48, 88, 128, 168], "\(starts(c17))")
}

/// **3.1b (probe C4, C5, C6, C15; `LZ-K`).** Flexible items: a minimum above the equal share is taken first and
/// the rest share what is left; the share is clamped to the maximum WITHOUT giving the excess back.
/// C4: `fixed(50), flexible(), flexible(20...40)`: rest = 200 - 50 - 16 = 134, share 67, the last clamps to 40:
/// tracks 50, 67, 40, total 50 + 67 + 40 + 16 = 173 placed centred at (200 - 173) / 2 = 13.5. C5: two
/// `flexible(minimum: 120)`: share 96 < 120, both take 120: total 248 > 200, origin 0, width 248. C6:
/// `flexible(), flexible(maximum: 30)`: share 96, tracks 96 and 30, total 134, origin 33. C15:
/// `flexible(minimum: 150), flexible()`: share 96, the first takes 150, the last gets 192 - 150 = 42.
/// Mutations: the min-first pass removed (C15: 96 and 96); the clamp giving back (C4: the first 80).
@Test func flexibleItemsFollowTheProbe() {
    let c4 = GridTrackSolver.resolve([.fixed(50), .flexible(), .flexible(minimum: 20, maximum: 40)],
                                     available: 200, alignment: 0.5)
    #expect(sizes(c4) == [50, 67, 40], "\(sizes(c4))")
    #expect(c4.origin == 13.5 && c4.total == 173 && c4.width == 200, "\(c4.origin) \(c4.total)")

    let c5 = GridTrackSolver.resolve([.flexible(minimum: 120), .flexible(minimum: 120)], available: 200, alignment: 0.5)
    #expect(sizes(c5) == [120, 120] && c5.origin == 0 && c5.total == 248 && c5.width == 248,
            "\(sizes(c5)) \(c5.origin) \(c5.width)")

    let c6 = GridTrackSolver.resolve([.flexible(), .flexible(maximum: 30)], available: 200, alignment: 0.5)
    #expect(sizes(c6) == [96, 30] && c6.origin == 33, "\(sizes(c6)) \(c6.origin)")

    let c15 = GridTrackSolver.resolve([.flexible(minimum: 150), .flexible()], available: 200, alignment: 0.5)
    #expect(sizes(c15) == [150, 42], "\(sizes(c15))")
}

/// **3.1c (probe C7, C8).** The gap after a track is its item's `spacing` (C7: 30, gap 20, 30 centred at
/// (200 - 80) / 2 = 60, so a 10-wide cell sits at 70 and 120); the last item's gap is not counted; the tracks
/// together are placed by the alignment factor in the available extent (C8: leading 0, centre 76 for a
/// 10 cell in the first of two 30 tracks with gap 8: (200 - 68) / 2 = 66 + 10).
/// Mutation: the origin always 0 (the centred and trailing cases move).
@Test func gapsAndAlignmentPlaceTheTracks() {
    let c7 = GridTrackSolver.resolve([.fixed(30, spacing: 20), .fixed(30, spacing: 0)], available: 200, alignment: 0.5)
    #expect(c7.tracks.map(\.gapAfter) == [20, 0] && c7.origin == 60 && c7.total == 80, "\(c7)")
    let leading = GridTrackSolver.resolve([.fixed(30), .fixed(30)], available: 200, alignment: 0)
    #expect(leading.origin == 0 && starts(leading) == [0, 38])
    let centre = GridTrackSolver.resolve([.fixed(30), .fixed(30)], available: 200, alignment: 0.5)
    #expect(centre.origin == 66 && starts(centre) == [66, 104])
    let trailing = GridTrackSolver.resolve([.fixed(30), .fixed(30)], available: 200, alignment: 1)
    #expect(trailing.origin == 132 && starts(trailing) == [132, 170])
}

/// **3.1d (probe LZ4 of the grid-scope probe, C12, C13).** With no available extent the container asks the
/// solver for the extent the FIRST line's cells ask for: two flexible columns holding cells 30 and 20 wide
/// give 30 + 8 + 20 = 58, the tracks (58 - 8) / 2 = 25 each; an adaptive item is one column whose cell is 10
/// wide: extent 10, n = max(1, floor(18 / 53)) = 1 of 10; no items is no tracks and width 0 (C13).
/// Mutation: the first line's widths replaced by their maximum (58 becomes 68).
@Test func anUnspecifiedExtentIsTheFirstLinesCells() {
    let flexible: [GridTrackSpec] = [.flexible(), .flexible()]
    let extent = GridTrackSolver.availableForUnspecified(flexible, firstLine: [30, 20])
    #expect(extent == 58)
    #expect(sizes(GridTrackSolver.resolve(flexible, available: extent, alignment: 0.5)) == [25, 25])

    let adaptive: [GridTrackSpec] = [.adaptive(minimum: 45)]
    let one = GridTrackSolver.availableForUnspecified(adaptive, firstLine: [10])
    #expect(one == 10)
    #expect(sizes(GridTrackSolver.resolve(adaptive, available: one, alignment: 0.5)) == [10])

    let none = GridTrackSolver.resolve([], available: 200, alignment: 0.5)
    #expect(none.tracks.isEmpty && none.width == 0 && none.total == 0)

    // A fixed item answers its own size whatever its cell asks.
    #expect(GridTrackSolver.availableForUnspecified([.fixed(40), .flexible()], firstLine: [5, 20]) == 40 + 8 + 20)
}

/// **3.1e (`LZ-K`, MetalUI's own ruling, no probe arm).** An adaptive item beside a flexible one is unprobed:
/// the rest after the fixed items and gaps is shared equally between them and the adaptive item packs its
/// share. `flexible(), adaptive(minimum: 20)` at 200: rest 200 - 8 = 192, shares 96 and 96; the adaptive
/// item packs n = floor(104 / 28) = 3 columns of (96 - 16) / 3 = 26.667. Pinned as the ruling, claiming no
/// SwiftUI figure. Mutation: the whole rest given to the adaptive item (the flexible track becomes 0).
@Test func anAdaptiveItemBesideAFlexibleOneSharesTheRestEqually() {
    let resolution = GridTrackSolver.resolve([.flexible(), .adaptive(minimum: 20)], available: 200, alignment: 0.5)
    #expect(resolution.tracks.count == 4)
    #expect(near(sizes(resolution), [96, 80.0 / 3.0, 80.0 / 3.0, 80.0 / 3.0]), "\(sizes(resolution))")
    #expect(abs(resolution.total - 200) < 1e-9)
}
