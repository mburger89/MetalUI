import Foundation
#if canImport(WebKit)
import WebKit
#endif
@testable import MetalUILayout

/// A fixture whose CSS does not put the root box at the viewport origin.
public struct FixtureHygieneError: Error, CustomStringConvertible {
    public let fixture: String
    public let x: Double
    public let y: Double

    public var description: String {
        """
        Fixture '\(fixture)' lays its root box out at (\(x), \(y)), not (0, 0). \
        Almost always a missing `body { margin: 0 }`, which UA stylesheets \
        default to 8px. Generating a golden from it would bake that offset in, \
        and every later mismatch would look like an engine bug instead of a \
        fixture bug. Fix the fixture's CSS.
        """
    }
}

/// A fixture that measured to no boxes at all.
///
/// `LayoutOracle.measure` returns `[]` when the page yields no `[data-id]`
/// elements — a typo'd `data-id`, a fixture that failed to parse, or a JS shape
/// mismatch. Without this check the fixture-hygiene test below no-ops (there is
/// no `raw.first` to inspect) and an **empty golden** is written and committed,
/// which no test can then fail on: an empty golden agrees with everything.
public struct EmptyMeasurementError: Error, CustomStringConvertible {
    public let fixture: String

    public var description: String {
        """
        Fixture '\(fixture)' measured to zero boxes. The oracle found no \
        `[data-id]` elements in it — check for a typo'd or missing `data-id` \
        attribute, or HTML that does not parse. Writing this as a golden would \
        commit an empty file that every later comparison trivially agrees with.
        """
    }
}

#if canImport(WebKit)
@MainActor
public func generateGolden(fixture: String, viewport: CGSize) async throws -> GoldenFile {
    let html = try String(contentsOf: fixtureURL(name: fixture), encoding: .utf8)
    let oracle = LayoutOracle(viewport: viewport)
    let raw = try await oracle.measure(html: html)

    // An empty measurement must never become a golden: the hygiene check below
    // silently passes on it, and an empty golden agrees with every engine.
    guard !raw.isEmpty else { throw EmptyMeasurementError(fixture: fixture) }

    // Fail at the moment the fixture is authored, not later as a phantom engine
    // bug. The root is the box tagged `root` by convention; otherwise the first
    // `[data-id]` in document order, which is the outermost element.
    if let rootBox = raw.first(where: { $0.id == "root" }) ?? raw.first,
       rootBox.x != 0 || rootBox.y != 0 {
        throw FixtureHygieneError(fixture: fixture, x: rootBox.x, y: rootBox.y)
    }

    return GoldenFile(fixture: fixture,
                      viewport: [Double(viewport.width), Double(viewport.height)],
                      raw: raw,
                      rounded: roundBoxes(raw))
}
#endif

/// Write a golden into the *source tree*, not the build bundle, so it can be
/// committed. `root` is the package root.
public func writeGolden(_ g: GoldenFile, toSourceTree root: String) throws {
    let dir = URL(fileURLWithPath: root)
        .appendingPathComponent("Tests/MetalUILayoutTests/Golden", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(g).write(to: dir.appendingPathComponent("\(g.fixture).json"))
}
