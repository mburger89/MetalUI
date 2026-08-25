import Foundation
import WebKit
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

@MainActor
public func generateGolden(fixture: String, viewport: CGSize) async throws -> GoldenFile {
    let html = try String(contentsOf: fixtureURL(name: fixture), encoding: .utf8)
    let oracle = LayoutOracle(viewport: viewport)
    let raw = try await oracle.measure(html: html)

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
