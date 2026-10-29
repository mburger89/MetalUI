import Foundation
import Testing
@testable import MetalUIShaderCompile

// The build-tool plugin's `--on-build` decision and run (item BS-D, rulings BT-F, BT-G, BT-L).
// Pure and portable: no shadercross, no SwiftPM.

private let tri = [UInt8]("tri".utf8)
private let sources: [(name: String, bytes: [UInt8])] = [
    (name: "a.comp.hlsl", bytes: [UInt8]("a".utf8)), (name: "b.frag.hlsl", bytes: [UInt8]("b".utf8)),
]
private let goodMarker = SourceMarker.contents(of: sources)
private let fullDirectory = ["SOURCE.sha256", "a.comp.spv", "a.comp.msl", "a.comp.dxil", "a.comp.json",
                             "b.frag.spv", "b.frag.msl", "b.frag.dxil", "b.frag.json", "notes.txt", "extra.comp.spv"]
private let display = "Sources/App/Shaders"

private func decide(_ located: Result<String, ShaderCompileError>?, checkedIn: [String]? = fullDirectory,
                    marker: String? = goodMarker, sources: [(name: String, bytes: [UInt8])] = sources) -> BuildDecision {
    BuildDecision.decide(located: located, sources: sources, checkedIn: checkedIn, marker: marker, displaySource: display)
}

private func failure(_ decision: BuildDecision) -> String? {
    if case .fail(let lines) = decision { return lines.map { "error: " + $0 }.joined(separator: "\n") }
    return nil
}

/// **1.** With shadercross the build compiles even when the checked-in blobs match.
/// Mutation: prefer the copy arm when the marker matches.
@Test func withShadercrossTheBuildCompilesAndIgnoresTheCheckedInBlobs() {
    #expect(decide(.success("/x/shadercross")) == .compile(shadercross: "/x/shadercross", staleCheckedIn: []))
    #expect(decide(.success("/x/shadercross"), checkedIn: nil, marker: nil) == .compile(shadercross: "/x/shadercross", staleCheckedIn: []))
}

/// **2.** Copies exactly the marker and each source's blobs (not `notes.txt`, not a blob of a source that is gone).
/// Mutation: copy every file of `compiled/`; omit the marker.
@Test func withoutShadercrossAMatchingMarkerCopiesExactlyTheBlobsOfEachSource() {
    #expect(decide(nil) == .copy(files: ["SOURCE.sha256", "a.comp.dxil", "a.comp.json", "a.comp.msl", "a.comp.spv",
                                         "b.frag.dxil", "b.frag.json", "b.frag.msl", "b.frag.spv"]))
    // A missing optional blob (msl, dxil) is not copied and not an error.
    #expect(decide(nil, checkedIn: ["SOURCE.sha256", "a.comp.spv", "a.comp.json", "b.frag.spv", "b.frag.json"])
            == .copy(files: ["SOURCE.sha256", "a.comp.json", "a.comp.spv", "b.frag.json", "b.frag.spv"]))
}

/// **3.** A changed source fails, naming the problem, the pin and both fixes.
/// Mutations: ignore `SourceMarker.problems`; drop the pin or either fix from the text.
@Test func withoutShadercrossAChangedSourceFailsNamingBothFixesAndThePin() throws {
    var changed = sources
    changed[0].bytes = [UInt8]("a edited".utf8)
    let text = try #require(failure(decide(nil, sources: changed)))
    #expect(text.contains("a.comp.hlsl changed since SOURCE.sha256 was written"), "\(text)")
    #expect(text.contains(ShadercrossPin.commit), "\(text)")
    #expect(text.contains("METALUI_SHADERCROSS") && text.contains("PATH"), "\(text)")
    #expect(text.contains("compile-shaders --source \(display) --out \(display)/compiled"), "\(text)")
    #expect(text.contains("eol=lf"), "\(text)")
    #expect(text.hasPrefix("error: "), "\(text)")
}

/// **4.** No marker, or no directory, fails. Mutation: treat a missing marker as matching.
@Test func withoutShadercrossAMissingMarkerOrDirectoryFails() throws {
    let noMarker = try #require(failure(decide(nil, marker: nil)))
    #expect(noMarker.contains("SOURCE.sha256 does not exist") && noMarker.contains(ShadercrossPin.commit), "\(noMarker)")
    let noDirectory = try #require(failure(decide(nil, checkedIn: nil, marker: nil)))
    #expect(noDirectory.contains("\(display)/compiled does not exist"), "\(noDirectory)")
}

/// **5.** A source without its `.json` or `.spv` fails even with a matching marker. Mutation: drop the completeness check.
@Test func aSourceWithoutItsReflectionOrSpirvBlobFails() throws {
    let noJson = try #require(failure(decide(nil, checkedIn: fullDirectory.filter { $0 != "b.frag.json" })))
    #expect(noJson.contains("b.frag.json is missing in compiled/"), "\(noJson)")
    let noSpv = try #require(failure(decide(nil, checkedIn: fullDirectory.filter { $0 != "a.comp.spv" })))
    #expect(noSpv.contains("a.comp.spv is missing in compiled/"), "\(noSpv)")
}

/// **6.** A variable naming a missing file fails with the locator's message and never copies.
/// Mutation: map a locator error to "not found".
@Test func aVariableNamingAMissingShadercrossFailsAndNeverCopies() throws {
    let error = ShaderCompileError("METALUI_SHADERCROSS=/nope does not exist")
    #expect(decide(.failure(error)) == .fail(lines: ["METALUI_SHADERCROSS=/nope does not exist"]))
    // And through the runner: the named-missing error is not the not-found one.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var arguments = try buildArguments(root)
    arguments.environmentShadercross = root.appendingPathComponent("missing").path
    do {
        try ShaderCompiler.runOnBuild(arguments, environment: [:], windows: false, fileExists: { _ in false },
                                      runner: { _, _, _ in 0 }, log: { _ in }, warn: { _ in })
        Issue.record("accepted a missing named shadercross")
    } catch { #expect("\(error)".contains("does not exist"), "\(error)") }
}

/// **7.** The on-build flags parse; an empty value is unset, not a path; restricted flags are refused.
/// Mutations: `--environment-shadercross ""` treated as a path; `--checked-in` dropped.
@Test func onBuildArgumentsAreParsedAndAnEmptyVariableIsUnset() throws {
    let parsed = try CompileArguments.parse(["--on-build", "--source", "s", "--checked-in", "c", "--out", "o",
                                             "--environment-shadercross", "", "--environment-path", "/a:/b", "--display-source", "Sources/App/Shaders"])
    #expect(parsed.mode == .onBuild && parsed.checkedIn == "c" && parsed.environmentShadercross == "" && parsed.environmentPath == "/a:/b")
    #expect(parsed.displaySource == "Sources/App/Shaders" && parsed.writesMarker && parsed.formats == Set(ShaderFormat.allCases))
    // The locator sees "" as unset and falls to PATH.
    let found = try ShadercrossLocator.locate(flag: nil, environment: ["METALUI_SHADERCROSS": "", "PATH": "/a:/b"],
                                              fileExists: { $0 == "/b/shadercross" }, windows: false)
    #expect(found == "/b/shadercross")
    #expect(throws: CompileUsageError.self) { try CompileArguments.parse(["--on-build", "--source", "s", "--out", "o", "--environment-shadercross", "", "--environment-path", ""]) }
    #expect(throws: CompileUsageError.self) { try CompileArguments.parse(["--on-build", "--source", "s", "--checked-in", "c", "--out", "o", "--environment-path", ""]) }
    #expect(throws: CompileUsageError.self) { try CompileArguments.parse(["--on-build", "--source", "s", "--checked-in", "c", "--out", "o", "--environment-shadercross", "", "--environment-path", "", "--formats", "spv"]) }
    #expect(throws: CompileUsageError.self) { try CompileArguments.parse(["--source", "s", "--out", "o", "--checked-in", "c"]) }
    #expect(try CompileArguments.parse(["--source", "s", "--out", "o"]).mode == .compile)
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("metalui-buildplugin-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A scratch `Shaders` with the two `sources`, and a `compiled` holding `fullDirectory`'s named blobs.
private func buildArguments(_ root: URL, withCompiled: Bool = true) throws -> CompileArguments {
    let shaders = root.appendingPathComponent("Shaders"), compiled = shaders.appendingPathComponent("compiled")
    try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
    for source in sources { try Data(source.bytes).write(to: shaders.appendingPathComponent(source.name)) }
    if withCompiled {
        for name in fullDirectory where name != "SOURCE.sha256" { try Data("blob \(name)".utf8).write(to: compiled.appendingPathComponent(name)) }
        try Data(goodMarker.utf8).write(to: compiled.appendingPathComponent("SOURCE.sha256"))
    }
    return try CompileArguments.parse(["--on-build", "--source", shaders.path, "--checked-in", compiled.path,
                                       "--out", root.appendingPathComponent("out/MetalUIAppShaders").path,
                                       "--environment-shadercross", "", "--environment-path", "", "--display-source", display])
}

/// **8.** Both arms clear the output first (the bundle copy mirrors it, `BT-G`).
/// Mutation: no clear, per arm.
@Test func theOnBuildRunClearsItsOutputDirectoryInBothArms() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var arguments = try buildArguments(root)
    let out = root.appendingPathComponent("out/MetalUIAppShaders")
    func plant() throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: out.appendingPathComponent("gone.comp.spv"))
    }
    // Copy arm: no shadercross anywhere.
    try plant()
    var logs: [String] = []
    try ShaderCompiler.runOnBuild(arguments, environment: [:], windows: false, fileExists: { _ in false },
                                  runner: { _, _, _ in Issue.record("ran shadercross"); return 0 }, log: { logs.append($0) }, warn: { _ in })
    #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("gone.comp.spv").path), "copy arm kept a stale file")
    #expect(try Data(contentsOf: out.appendingPathComponent("a.comp.json")) == Data("blob a.comp.json".utf8))
    #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("notes.txt").path))
    #expect(logs.contains { $0.hasPrefix("Verified 2 checked-in shader(s)") }, "\(logs)")
    // Compile arm: a stub runner, shadercross named by the variable.
    arguments.environmentShadercross = "/stub/shadercross"
    try plant()
    var commands = 0
    try ShaderCompiler.runOnBuild(arguments, environment: [:], windows: false, fileExists: { $0 == "/stub/shadercross" },
                                  runner: { _, _, _ in commands += 1; return 0 }, log: { _ in }, warn: { _ in })
    #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("gone.comp.spv").path), "compile arm kept a stale file")
    #expect(commands == 8, "two sources, four formats")
    #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("SOURCE.sha256").path))
}

/// **9.** The error's pin is the one `docs/packaging.md` names. Mutation: change `ShadercrossPin.commit`.
@Test func theErrorsPinIsThePackagingDocsPin() throws {
    let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(contentsOf: checkout.appendingPathComponent("docs/packaging.md"), encoding: .utf8)
    #expect(text.contains("git checkout \(ShadercrossPin.commit)"))
    #expect(text.contains("commit `\(ShadercrossPin.commit)`"))
}

/// **10.** A stale checked-in copy is warned about when shadercross compiles. Mutation: no warning line.
@Test func aStaleCheckedInCopyIsWarnedWhenShadercrossCompiles() throws {
    var changed = sources
    changed[1].bytes = [UInt8]("b edited".utf8)
    #expect(decide(.success("/s"), sources: changed)
            == .compile(shadercross: "/s", staleCheckedIn: ["b.frag.hlsl changed since SOURCE.sha256 was written"]))
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var arguments = try buildArguments(root)
    try Data("b edited".utf8).write(to: URL(fileURLWithPath: arguments.source).appendingPathComponent("b.frag.hlsl"))
    arguments.environmentShadercross = "/stub/shadercross"
    var warnings: [String] = []
    try ShaderCompiler.runOnBuild(arguments, environment: [:], windows: false, fileExists: { $0 == "/stub/shadercross" },
                                  runner: { _, _, _ in 0 }, log: { _ in }, warn: { warnings.append($0) })
    #expect(warnings.count == 1 && warnings[0].hasPrefix("warning: \(display)/compiled is stale"), "\(warnings)")
}
