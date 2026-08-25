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
]
