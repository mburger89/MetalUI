// The release path of `metalui new` (ruling SC-J): the dependency order a
// framework checkout, a release build and a development build each get, and
// `metalui --version`. Generation is pure text, so these run in milliseconds;
// that the generated manifest is valid SwiftPM was checked by hand with
// `swift package dump-package` (record 385).
//
// Mutations run against these tests (each failed at least one, then reverted):
//   1. (a) before (b) swapped: a release build ignores the checkout's pin;
//   2. dropping the default-URL check on (b): a fork gets a version tag it lacks;
//   3. `isReleaseVersion` taking any 3+ parts, or any non-empty part: a dev tree writes a requirement;
//   4. `releaseRequirement` always `from:`: a 0.x app crosses a breaking minor;
//   5. `--version` printing the usage instead of `metalui <version>`;
// The tag/version match is the release workflow's check, not a unit test.
import Foundation
import Testing
@testable import MetalUIScaffold

private let url = MetalUISource.defaultURL
private let commit = String(repeating: "ab", count: 20)

private func parsed(_ arguments: [String], version: String, lookup: PinLookup) throws -> ScaffoldCommand {
    try parseScaffoldCommand(arguments, workingDirectory: "/w", version: version) { _ in lookup }
}

private func source(of command: ScaffoldCommand) throws -> (MetalUISource, String?) {
    guard case let .new(options, _, note) = command else { throw ScaffoldError.usage("not a new command") }
    return (options.source, note)
}

@Test func theEmbeddedVersionIsAReleaseVersion() {
    #expect(isReleaseVersion(metaluiVersion))
}

@Test(arguments: [("0.1.0", true), ("1.20.3", true), ("0.2.0-dev", false), ("1.0", false),
                  ("", false), ("v0.1.0", false), ("1.0.0.1", false), ("1..0", false), ("1.0.x", false)])
func aReleaseVersionIsThreeNumbersAndNothingElse(_ version: String, _ expected: Bool) {
    #expect(isReleaseVersion(version) == expected)
}

/// (a): a git checkout of the URL with a commit to pin wins over the version.
@Test func aFrameworkCheckoutPinsItsCommitEvenInAReleaseBuild() throws {
    let (found, note) = try source(of: parsed(["new", "A"], version: "0.1.0", lookup: .revision(commit)))
    #expect(found == .remote(url: url, reference: .revision(commit)))
    #expect(note == nil)
}

/// (b): no checkout, a release version → a version requirement, no note.
@Test func aReleaseBuildWithoutACheckoutAsksForItsOwnRelease() throws {
    let (found, note) = try source(of: parsed(["new", "A"], version: "0.1.0", lookup: .unavailable("gone")))
    #expect(found == .remote(url: url, reference: .release("0.1.0")))
    #expect(note == nil)
}

/// (c): no checkout, a development version → the branch, with its warning.
@Test func aDevelopmentBuildWithoutACheckoutFollowsMasterAndSaysWhy() throws {
    let (found, note) = try source(of: parsed(["new", "A"], version: "0.2.0-dev", lookup: .unavailable("gone")))
    #expect(found == .remote(url: url, reference: .branch("master")))
    #expect(note?.contains("not pinned to a commit: gone") == true)
}

/// A fork has no tag for this version: it is never given a requirement.
@Test func aForkIsNotGivenAVersionRequirement() throws {
    let (found, note) = try source(of: parsed(["new", "A", "--url", "git@github.com:me/fork.git"],
                                              version: "0.1.0", lookup: .unavailable("gone")))
    #expect(found == .remote(url: "git@github.com:me/fork.git", reference: .branch("master")))
    #expect(note != nil)
    // The default URL spelled another way is still the default repository.
    let (same, _) = try source(of: parsed(["new", "A", "--url", "git@github.com:mburger89/MetalUI"],
                                          version: "0.1.0", lookup: .unavailable("gone")))
    #expect(same == .remote(url: "git@github.com:mburger89/MetalUI", reference: .release("0.1.0")))
}

@Test func explicitFlagsOutrankTheVersion() throws {
    let lookup = PinLookup.unavailable("gone")
    #expect(try source(of: parsed(["new", "A", "--revision", "abc"], version: "0.1.0", lookup: lookup)).0
        == .remote(url: url, reference: .revision("abc")))
    #expect(try source(of: parsed(["new", "A", "--branch", "dev"], version: "0.1.0", lookup: lookup)).0
        == .remote(url: url, reference: .branch("dev")))
    #expect(try source(of: parsed(["new", "A", "--local", "/x"], version: "0.1.0", lookup: lookup)).0
        == .local(path: "/x"))
}

@Test func aZeroMajorReleaseIsUpToTheNextMinorAndLaterOnesUpToTheNextMajor() throws {
    func line(_ version: String, crossPlatform: Bool = false) throws -> String {
        let files = try scaffoldFiles(ScaffoldOptions(name: "MyApp", source: .remote(url: url, reference: .release(version)),
                                                      crossPlatform: crossPlatform))
        let text = try #require(files.first { $0.path == "Package.swift" }).contents
        return try #require(text.split(separator: "\n").first { $0.contains(".package(url:") }).trimmingCharacters(in: .whitespaces)
    }
    #expect(try line("0.1.0") == #".package(url: "\#(url)", .upToNextMinor(from: "0.1.0")),"#)
    #expect(try line("1.2.0") == #".package(url: "\#(url)", from: "1.2.0"),"#)
    #expect(try line("0.1.0", crossPlatform: true) == #".package(url: "\#(url)", .upToNextMinor(from: "0.1.0"), traits: metalUITraits),"#)
    let files = try scaffoldFiles(ScaffoldOptions(name: "MyApp", source: .remote(url: url, reference: .release("0.1.0"))))
    let text = try #require(files.first { $0.path == "Package.swift" }).contents
    #expect(!text.contains("branch:") && !text.contains("revision:"))
    let readme = try #require(files.first { $0.path == "README.md" }).contents
    #expect(readme.contains("release 0.1.0") && readme.contains("minor version"))
}

@Test func versionPrintsTheEmbeddedVersionAndAppearsInTheUsage() throws {
    for flag in ["--version", "-V"] {
        var output: [String] = []
        #expect(runScaffold([flag], workingDirectory: "/w", output: { output.append($0) }, error: { _ in }) == 0)
        #expect(output == ["metalui \(metaluiVersion)"])
    }
    var output: [String] = []
    #expect(runScaffold(["--version"], workingDirectory: "/w", version: "9.8.7", output: { output.append($0) },
                        error: { _ in }) == 0)
    #expect(output == ["metalui 9.8.7"])
    #expect(scaffoldUsage.contains("--version"))
}

@Test func runningTheCommandSaysItAskedForTheRelease() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("metalui-release-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var output: [String] = []
    var errors: [String] = []
    #expect(runScaffold(["new", "Rel"], workingDirectory: root.path, version: "0.1.0",
                        pinLookup: { _ in .unavailable("gone") },
                        output: { output.append($0) }, error: { errors.append($0) }) == 0)
    #expect(errors.isEmpty)
    #expect(output.first?.contains("MetalUI is set to release 0.1.0") == true)
    let manifest = try String(contentsOfFile: root.appendingPathComponent("Rel/Package.swift").path, encoding: .utf8)
    #expect(manifest.contains(#".upToNextMinor(from: "0.1.0")"#))
}
