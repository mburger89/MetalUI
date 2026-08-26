import Testing
import Foundation
@testable import MetalUILayout

@MainActor
@Test func generatorProducesRawAndRoundedForAFixture() async throws {
    let g = try await generateGolden(fixture: "flex_row_fixed_and_grow",
                                     viewport: CGSize(width: 800, height: 600))
    #expect(g.fixture == "flex_row_fixed_and_grow")
    #expect(g.viewport == [800, 600])
    #expect(g.raw.count == 4)
    #expect(g.rounded.count == g.raw.count)
    #expect(g.rounded.map(\.id) == g.raw.map(\.id))

    // This fixture is exact, so rounding is the identity.
    #expect(g.raw == g.rounded)
}

@MainActor
@Test func generatorRoundsWhenTheBrowserQuantizes() async throws {
    let g = try await generateGolden(fixture: "flex_row_seven_equal",
                                     viewport: CGSize(width: 400, height: 200))
    // Raw carries WebKit's 1/64 values; rounded closes the row on its parent.
    #expect(g.raw.contains { abs($0.width - 14.28125) < 1e-9 })
    let children = g.rounded.filter { $0.id != "root" }
    #expect(children.map(\.width).reduce(0, +) == 100)
}

/// Regenerates every golden from its fixture. Disabled by default: it writes
/// into the source tree, and a golden that regenerates itself on every run
/// cannot catch a regression. Enable deliberately:
///   METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_REGENERATE_GOLDENS"] == "1"))
func regenerateAllGoldens() async throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // MetalUILayoutTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root
        .path
    for (fixture, viewport) in allFixtures {
        let g = try await generateGolden(fixture: fixture, viewport: viewport)
        try writeGolden(g, toSourceTree: root)
    }
}

/// Every fixture in the corpus, with the viewport it is measured at.
@MainActor
let allFixtures: [(String, CGSize)] = [
    ("flex_row_fixed_and_grow", CGSize(width: 800, height: 600)),
    ("flex_row_seven_equal",    CGSize(width: 400, height: 200)),
    ("flex_row_three_fixed",    CGSize(width: 800, height: 600)),
    ("flex_column_three_fixed", CGSize(width: 800, height: 600)),
    ("flex_row_gap",            CGSize(width: 800, height: 600)),
    ("flex_row_grow_uneven",    CGSize(width: 800, height: 600)),
    ("flex_row_shrink",         CGSize(width: 800, height: 600)),
    ("flex_row_fractional_grow", CGSize(width: 800, height: 600)),
    ("flex_row_fractional_grow_clamped", CGSize(width: 800, height: 600)),
    ("flex_row_grow_with_max",  CGSize(width: 800, height: 600)),
    ("flex_row_grow_nonzero_basis", CGSize(width: 800, height: 600)),
    ("flex_row_fractional_shrink", CGSize(width: 800, height: 600)),
    ("flex_column_grow_with_max", CGSize(width: 800, height: 600)),
    ("flex_row_explicit_min",    CGSize(width: 800, height: 600)),
    ("flex_row_percent_basis",   CGSize(width: 800, height: 600)),
    ("flex_row_shrink_to_zero",  CGSize(width: 800, height: 600)),
    ("flex_row_justify_between", CGSize(width: 800, height: 600)),
    ("flex_row_justify_around",  CGSize(width: 800, height: 600)),
    ("flex_row_justify_evenly",  CGSize(width: 800, height: 600)),
    ("flex_column_justify_center", CGSize(width: 800, height: 600)),
    ("flex_row_justify_between_gap", CGSize(width: 800, height: 600)),
    ("flex_row_align_center",        CGSize(width: 800, height: 600)),
    ("flex_row_align_end_with_self", CGSize(width: 800, height: 600)),
    ("flex_row_stretch_mixed",       CGSize(width: 800, height: 600)),
    ("flex_row_reverse",             CGSize(width: 800, height: 600)),
    ("flex_column_reverse_justify_end", CGSize(width: 800, height: 600)),
    ("flex_row_padding_border",         CGSize(width: 800, height: 600)),
    ("flex_column_padding_asymmetric",  CGSize(width: 800, height: 600)),
    ("flex_row_margins",                CGSize(width: 800, height: 600)),
    ("flex_row_margin_with_grow",       CGSize(width: 800, height: 600)),
]

/// The committed goldens must still be what the browser says.
///
/// This is the ONLY test that drives WebKit to check the corpus, and it is the
/// counterweight to the engine comparisons reading `Golden/*.json` instead of
/// regenerating. It fails when a fixture's HTML or CSS is edited without
/// `METALUI_REGENERATE_GOLDENS=1` being re-run, which would otherwise leave the
/// engine cheerfully agreeing with a golden that no longer describes its fixture.
///
/// Exact equality, not a tolerance: WebKit is deterministic for a given fixture
/// and viewport, and the JSON round-trip is lossless. A mismatch here means the
/// fixture changed, the browser changed, or the golden was hand-edited — all of
/// which want a human to look, not a tolerance to paper over.
@MainActor
@Test func committedGoldensMatchTheBrowser() async throws {
    for (fixture, viewport) in allFixtures {
        let fresh = try await generateGolden(fixture: fixture, viewport: viewport)
        let committed = try loadGolden(fixture)
        guard fresh != committed else { continue }

        // Report only the boxes that actually differ. Expanding two whole
        // GoldenFiles buries the one changed number in a wall of struct dump.
        let committedByID = Dictionary(uniqueKeysWithValues: committed.rounded.map { ($0.id, $0) })
        let diffs = fresh.rounded.compactMap { box -> String? in
            guard let old = committedByID[box.id] else { return "\(box.id): absent from golden" }
            guard old != box else { return nil }
            return "\(box.id): browser \(box.x),\(box.y) \(box.width)x\(box.height) "
                 + "vs golden \(old.x),\(old.y) \(old.width)x\(old.height)"
        }
        Issue.record("""
            Golden '\(fixture)' no longer matches the browser.
            \(diffs.isEmpty ? "differs outside `rounded` (raw or viewport)" : diffs.joined(separator: "\n"))
            Regenerate with:
              METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
            """)
    }
}

/// A fixture missing from `allFixtures` never generates a golden and is never
/// compared against anything — it just sits in the directory looking checked.
/// Nothing else in the suite notices, so this counts the files and makes the
/// omission a failure.
@MainActor
@Test func everyFixtureFileIsListedInTheCorpus() throws {
    let onDisk = Bundle.module.urls(forResourcesWithExtension: "html",
                                    subdirectory: "Fixtures") ?? []
    let names = Set(onDisk.map { $0.deletingPathExtension().lastPathComponent })
    let listed = Set(allFixtures.map(\.0))

    #expect(allFixtures.count == onDisk.count,
            "allFixtures lists \(allFixtures.count) fixtures but Fixtures/ holds \(onDisk.count) .html files")
    #expect(names.subtracting(listed).isEmpty,
            "fixtures on disk but absent from allFixtures: \(names.subtracting(listed).sorted())")
    #expect(listed.subtracting(names).isEmpty,
            "fixtures listed in allFixtures but absent from disk: \(listed.subtracting(names).sorted())")
}
