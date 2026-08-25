import Foundation
import WebKit
@testable import MetalUILayout

@MainActor
public func generateGolden(fixture: String, viewport: CGSize) async throws -> GoldenFile {
    let html = try String(contentsOf: fixtureURL(name: fixture), encoding: .utf8)
    let oracle = LayoutOracle(viewport: viewport)
    let raw = try await oracle.measure(html: html)
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
