// The sample app, `Examples/Jotter` (ruling EX-A..EX-E, record §136): its own package, a
// path dependency on this checkout, built the way a user's app is. What its manifest says is
// pinned as text against the scaffold's, so it cannot drift from the shape `metalui new
// --cross-platform` writes; that it builds and its own tests pass is the env-gated test below
// (`METALUI_RUN_SAMPLE_APP_TEST=1`), which counts while skipped.
import Foundation
import Testing
@testable import MetalUIScaffold

/// The repository root, from this file's own path.
private let checkout = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private let jotter = checkout.appendingPathComponent("Examples/Jotter")

/// The product names a manifest mentions (`.product(name: "X", …)`), as a set.
private func productNames(in manifest: String) -> Set<String> {
    var names: Set<String> = []
    var rest = Substring(manifest)
    while let range = rest.range(of: #".product(name: ""#) {
        rest = rest[range.upperBound...]
        if let end = rest.firstIndex(of: "\"") { names.insert(String(rest[..<end])) }
    }
    return names
}

/// The `#if os(Linux) || os(Windows)` … `#endif` block, comments dropped: the traits the
/// manifest turns on.
private func traitsBlock(in manifest: String) throws -> [String] {
    let lines = manifest.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    let start = try #require(lines.firstIndex(of: "#if os(Linux) || os(Windows)"), "no traits block")
    let end = try #require(lines[start...].firstIndex(of: "#endif"), "unterminated traits block")
    return lines[start...end].filter { !$0.hasPrefix("//") && !$0.isEmpty }
}

/// EX-D, always on. The example's manifest names every product a generated cross-platform
/// package names, turns on the same traits, and keeps the tools version, platform and language
/// mode. It also names the dependency (`name:` and `package:` = `MetalUI`, EX-B) so the example
/// builds in a checkout directory of any name. Mutation: drop `MetalUISystemFonts` from the
/// example's test target, or `.v14` to `.v13`, or the Linux trait list to `["SDL"]`.
@Test func theSampleAppsManifestHasTheShapeOfAGeneratedCrossPlatformPackage() throws {
    let example = try String(contentsOf: jotter.appendingPathComponent("Package.swift"), encoding: .utf8)
    let generated = manifest(ScaffoldOptions(name: "Jotter", source: .local(path: "../.."), crossPlatform: true))
    // Every product the generated app and test targets use, and the example's: the same set
    // (the example adds none: `JotterKit` is its own target, not a MetalUI product).
    #expect(productNames(in: example) == productNames(in: generated),
            "update Examples/Jotter/Package.swift and Scaffold.swift's manifest together")
    #expect(try traitsBlock(in: example) == traitsBlock(in: generated))
    for line in ["// swift-tools-version: 6.1", "platforms: [.macOS(.v14)],", "swiftLanguageModes: [.v6]"] {
        #expect(example.contains(line) && generated.contains(line), "\(line)")
    }
    #expect(example.contains(#".package(name: "MetalUI", path: "../..", traits: metalUITraits)"#), "EX-B: the dependency is named")
    #expect(!example.contains("branch:") && !example.contains("url:"), "a path dependency, never a remote")
    // Every product is taken from `package: "MetalUI"` (the identity the `name:` above gives it).
    #expect(example.components(separatedBy: #"package: "MetalUI""#).count - 1 == example.components(separatedBy: ".product(").count - 1)
}

@Test func theSampleAppHasItsTestsAndItsDocs() throws {
    let fileManager = FileManager.default
    for path in ["README.md", "Package.swift", "Sources/Jotter/main.swift", "Sources/JotterKit/NotesModel.swift",
                 "Tests/JotterTests/FlowTests.swift"] {
        #expect(fileManager.fileExists(atPath: jotter.appendingPathComponent(path).path), "Examples/Jotter/\(path)")
    }
}

// MARK: - The end-to-end build (env-gated)

private func run(_ arguments: [String], in directory: URL) throws -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift"] + arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// EX-D: `Examples/Jotter` builds against this checkout and its own tests pass, on macOS and
/// Linux (with the SDL trait the manifest turns on there). Off by default: a second build of
/// MetalUI, minutes long. Counts while skipped.
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_SAMPLE_APP_TEST"] == "1"))
func aSampleAppBuildsAndItsTestsPassAgainstThisCheckout() throws {
    #if os(macOS) || os(Linux)
    for arguments in [["build"], ["build", "--build-tests"], ["test", "--skip-build"]] {
        let (status, output) = try run(arguments, in: jotter)
        print("EX-D swift \(arguments.joined(separator: " ")): status=\(status)\n\(output.suffix(1500))")
        #expect(status == 0, "swift \(arguments): \(output)")
        if arguments.first == "test" {
            for name in ["launchShowsTheSeededNotesAndSelectsTheFirst()", "deleteAsksForConfirmationAndOnlyConfirmDeletes()",
                         "exportWritesVersionedJSONAndImportReadsItBack()", "draggingARowOntoAnotherReordersTheModel()",
                         "theCommandsMenuShortcutsRunTheirActions()"] {
                #expect(output.contains("Test \(name) passed"), "\(name): \(output)")
            }
            #expect(!output.contains("recorded an issue"), "\(output)")
            let summary = output.components(separatedBy: "Test run with ").last ?? ""
            let count = Int(summary.prefix { $0.isNumber }) ?? 0
            #expect(count >= 20, "the example's test count: \(summary.prefix(60))")
        }
    }
    #endif
}
