import Foundation
import Testing
@testable import MetalUISDL

// Where `SDLWindowRenderer` finds its compiled shaders (ruling `PX-P`; spec
// `docs/superpowers/specs/2026-10-07-portable-app-design.md` §4.1, test 1.10):
// `MetalUISDLShaders` beside the executable first, so a built app can be
// moved; then the `#filePath` directory of a build from source. A directory
// counts when it holds `SOURCE.sha256` (what `scripts/compile-shaders.py`
// writes beside the stages). Portable: no SDL call, no window — runs on macOS
// and in the Linux image.

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("metalui-sdl-shaders-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Makes `directory` look like a compiled-shader directory.
private func markAsShaderDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("sha  replay.hlsl\n".utf8).write(to: directory.appendingPathComponent("SOURCE.sha256"))
}

/// Arm 1: with both present, the executable-adjacent directory wins.
/// Mutation: swap the candidate order → the `#filePath` one is chosen → red.
@Test func theShaderDirectoryBesideTheExecutableWins() throws {
    let executable = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: executable) }
    let adjacent = executable.appendingPathComponent("MetalUISDLShaders")
    try markAsShaderDirectory(adjacent)
    let candidates = SDLWindowRenderer.shaderDirectoryCandidates(executableDirectory: executable.path)
    #expect(candidates == [adjacent.path, SDLWindowRenderer.bundledShaderDirectory])
    // The source tree's own directory holds SOURCE.sha256 too (checked in CI).
    #expect(FileManager.default.fileExists(
        atPath: SDLWindowRenderer.bundledShaderDirectory + "/SOURCE.sha256"))
    #expect(try SDLWindowRenderer.shaderDirectory(from: candidates) == adjacent.path)
}

/// Arm 2: with nothing beside the executable, the `#filePath` directory is used.
@Test func theSourceTreesShaderDirectoryIsUsedWhenItAloneExists() throws {
    let executable = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: executable) }
    // A directory without SOURCE.sha256 does not count.
    try FileManager.default.createDirectory(at: executable.appendingPathComponent("MetalUISDLShaders"),
                                            withIntermediateDirectories: true)
    let candidates = SDLWindowRenderer.shaderDirectoryCandidates(executableDirectory: executable.path)
    #expect(try SDLWindowRenderer.shaderDirectory(from: candidates) == SDLWindowRenderer.bundledShaderDirectory)
}

/// Arm 3: neither → the error names every directory tried (`AI-N`'s
/// precedent). Mutation: drop the paths from the description → red.
@Test func noShaderDirectoryIsAnErrorNamingEveryDirectoryTried() throws {
    let root = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("beside/MetalUISDLShaders").path
    let second = root.appendingPathComponent("source/Shaders/compiled").path
    do {
        let found = try SDLWindowRenderer.shaderDirectory(from: [first, second])
        Issue.record("found \(found) where no directory exists")
    } catch {
        let description = String(describing: error)
        #expect(description.contains(first), "\(description)")
        #expect(description.contains(second), "\(description)")
        #expect(description.contains("SOURCE.sha256"), "\(description)")
    }
}
