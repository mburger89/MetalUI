import Foundation
import Testing
@testable import MetalUIShaderCompile

// Include sources of an app's `Shaders/`: the plugin's input list, `INCLUDES.sha256`, the copy path and the
// run time check (item XP-G32, rulings BT-O...BT-R). Pure and portable: no shadercross, no SwiftPM.

private let checkout = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("metalui-includes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, _ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private let stageSources: [(name: String, bytes: [UInt8])] = [
    (name: "a.vert.hlsl", bytes: [UInt8]("v".utf8)), (name: "a.frag.hlsl", bytes: [UInt8]("f".utf8)),
]
private let headers: [(name: String, bytes: [UInt8])] = [
    (name: "common.hlsli", bytes: [UInt8]("common".utf8)), (name: "lib/util.hlsl", bytes: [UInt8]("util".utf8)),
]
private let display = "Sources/App/Shaders"
private let blobs = ["SOURCE.sha256", "INCLUDES.sha256", "a.vert.spv", "a.vert.msl", "a.vert.dxil", "a.vert.json",
                     "a.frag.spv", "a.frag.msl", "a.frag.dxil", "a.frag.json"]

private func decide(_ located: Result<String, ShaderCompileError>? = nil,
                    includes: [(name: String, bytes: [UInt8])] = headers,
                    includesMarker: String? = SourceMarker.contents(of: headers),
                    checkedIn: [String]? = blobs) -> BuildDecision {
    BuildDecision.decide(located: located, sources: stageSources, includes: includes, includesMarker: includesMarker,
                         checkedIn: checkedIn, marker: SourceMarker.contents(of: stageSources), displaySource: display)
}

private func failureText(_ decision: BuildDecision) -> String? {
    if case .fail(let lines) = decision { return lines.joined(separator: "\n") }
    return nil
}

/// **14.** Which names are include sources: `.hlsli` anywhere, `.hlsl` that is not a top-level stage source
/// (a stage-named file in a subdirectory is never compiled, so it is an include). Mutations: drop the `.hlsli` arm;
/// treat every `.hlsl` as a stage-or-nothing; let a nested `x.vert.hlsl` be a stage; accept the bare names `.hlsli`/`.hlsl`.
@Test func includeSourcesAreHeadersAndNonStageHlslBySpelling() {
    let yes = ["common.hlsli", "lib/util.hlsli", "util.hlsl", "x.geom.hlsl", "lib/util.hlsl", "lib/x.vert.hlsl", "a.b.c.hlsl", "common.vert.hlsli"]
    let no = ["a.vert.hlsl", "b.frag.hlsl", "c.comp.hlsl", "notes.txt", "a.vert.spv", ".hlsl", ".hlsli", "common.hlsli.bak", "hlsli", "x.hlsl.orig"]
    for name in yes { #expect(IncludeSelection.isIncludeSource(relativePath: name), "\(name)") }
    for name in no { #expect(!IncludeSelection.isIncludeSource(relativePath: name), "\(name)") }
}

/// **15.** The walk: recursive, sorted bytewise, `compiled/` skipped (only at the top), a symlink to a file counts,
/// a symlink to a directory is not entered (no cycle), a broken link and a directory named `x.hlsli` are skipped.
/// Mutations: no recursion; skip every directory named `compiled`; follow directory links; list directories.
@Test func theWalkListsIncludeSourcesRecursivelyAndSorted() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = FileManager.default
    try write("v", root.appendingPathComponent("a.vert.hlsl"))
    try write("h", root.appendingPathComponent("common.hlsli"))
    try write("h", root.appendingPathComponent("Zeta.hlsli"))
    try write("u", root.appendingPathComponent("lib/util.hlsl"))
    try write("d", root.appendingPathComponent("lib/deep/more/deep.hlsli"))
    try write("n", root.appendingPathComponent("lib/nested.vert.hlsl"))
    try write("b", root.appendingPathComponent("compiled/blob.hlsli"))
    try write("b", root.appendingPathComponent("lib/compiled/kept.hlsli"))
    try write("t", root.appendingPathComponent("notes.txt"))
    try manager.createDirectory(at: root.appendingPathComponent("dir.hlsli"), withIntermediateDirectories: true)
    try manager.createSymbolicLink(atPath: root.appendingPathComponent("link.hlsli").path, withDestinationPath: "common.hlsli")
    try manager.createSymbolicLink(atPath: root.appendingPathComponent("linkdir.hlsli").path, withDestinationPath: "lib")
    try manager.createSymbolicLink(atPath: root.appendingPathComponent("lib/loop").path, withDestinationPath: "..")
    try manager.createSymbolicLink(atPath: root.appendingPathComponent("broken.hlsli").path, withDestinationPath: "nowhere.hlsli")
    #expect(IncludeSelection.relativePaths(under: root.path) == [
        "Zeta.hlsli", "common.hlsli", "lib/compiled/kept.hlsli", "lib/deep/more/deep.hlsli", "lib/nested.vert.hlsl",
        "lib/util.hlsl", "link.hlsli"])
    #expect(IncludeSelection.relativePaths(under: root.path + "/") == IncludeSelection.relativePaths(under: root.path))
    #expect(IncludeSelection.relativePaths(under: root.appendingPathComponent("missing").path).isEmpty)
}

/// **16.** `INCLUDES.sha256` is `SOURCE.sha256`'s format over relative paths and its messages name the file.
/// Mutations: `problems` ignores `markerName`; the contents sort by something other than bytes.
@Test func theIncludesMarkerHasTheSourceMarkersFormatAndNamesItselfInProblems() {
    let marker = SourceMarker.contents(of: headers)
    #expect(marker.split(separator: "\n").map { $0.components(separatedBy: "  ")[1] } == ["common.hlsli", "lib/util.hlsl"])
    #expect(marker.hasSuffix("\n") && !marker.contains("\r"))
    var edited = headers
    edited[0].bytes = [UInt8]("common edited".utf8)
    let problems = SourceMarker.problems(marker: marker, sources: edited, markerName: "INCLUDES.sha256", noun: "include sources")
    #expect(problems == ["common.hlsli changed since INCLUDES.sha256 was written"])
    let extra = SourceMarker.problems(marker: marker, sources: [headers[0]], markerName: "INCLUDES.sha256", noun: "include sources")
    #expect(extra == ["INCLUDES.sha256 lists lib/util.hlsl, which is not among the include sources"])
    #expect(SourceMarker.problems(marker: "", sources: [headers[0]], markerName: "INCLUDES.sha256", noun: "include sources")
            == ["common.hlsli has no line in INCLUDES.sha256"])
    // The default spelling is unchanged.
    #expect(SourceMarker.problems(marker: "", sources: [headers[0]]) == ["common.hlsli has no line in SOURCE.sha256"])
}

/// **17.** The copy path with headers: a header-only edit fails by name; a missing, orphan or extra line fails by name;
/// matching markers copy `INCLUDES.sha256` too; with no headers and no marker the list is today's.
/// Mutations: ignore `includeProblems`; do not require the marker when headers exist; drop `INCLUDES.sha256` from the copy list;
/// drop the orphan check.
@Test func theCopyPathChecksTheIncludesMarker() throws {
    // Matching: copies the includes marker, sorted bytewise.
    #expect(decide() == .copy(files: ["INCLUDES.sha256", "SOURCE.sha256", "a.frag.dxil", "a.frag.json", "a.frag.msl", "a.frag.spv",
                                      "a.vert.dxil", "a.vert.json", "a.vert.msl", "a.vert.spv"]))
    // A header-only edit (the stage sources are unchanged and match SOURCE.sha256).
    var edited = headers
    edited[0].bytes = [UInt8]("common edited".utf8)
    let changed = try #require(failureText(decide(includes: edited)))
    #expect(changed.contains("common.hlsli changed since INCLUDES.sha256 was written"), "\(changed)")
    #expect(!changed.contains("changed since SOURCE.sha256"), "\(changed)")
    #expect(changed.contains(ShadercrossPin.commit) && changed.contains("compile-shaders"), "\(changed)")
    // Headers but no INCLUDES.sha256 (a checked-in directory from before the headers existed).
    let missing = try #require(failureText(decide(includesMarker: nil)))
    #expect(missing.contains("\(display)/compiled/INCLUDES.sha256 does not exist"), "\(missing)")
    // A new header with no line, and a line whose header is gone.
    let grown = try #require(failureText(decide(includes: headers + [(name: "new.hlsli", bytes: [1])])))
    #expect(grown.contains("new.hlsli has no line in INCLUDES.sha256"), "\(grown)")
    let shrunk = try #require(failureText(decide(includes: [headers[0]])))
    #expect(shrunk.contains("INCLUDES.sha256 lists lib/util.hlsl, which is not among the include sources"), "\(shrunk)")
    // No headers: an INCLUDES.sha256 checked in is an orphan; none is today's behaviour.
    let orphan = try #require(failureText(decide(includes: [])))
    #expect(orphan.contains("INCLUDES.sha256 is checked in but \(display) has no include sources"), "\(orphan)")
    let plain = decide(includes: [], includesMarker: nil, checkedIn: blobs.filter { $0 != "INCLUDES.sha256" })
    #expect(plain == .copy(files: ["SOURCE.sha256", "a.frag.dxil", "a.frag.json", "a.frag.msl", "a.frag.spv",
                                   "a.vert.dxil", "a.vert.json", "a.vert.msl", "a.vert.spv"]))
}

/// **18.** With shadercross, a header edit is a stale-checked-in warning, not a failure; an absent include marker is silent
/// and an absent SOURCE marker keeps both silent. Mutation: fail instead of compiling; warn on a missing marker.
@Test func withShadercrossAHeaderEditOnlyWarns() {
    var edited = headers
    edited[0].bytes = [UInt8]("x".utf8)
    #expect(decide(.success("/s"), includes: edited)
            == .compile(shadercross: "/s", staleCheckedIn: ["common.hlsli changed since INCLUDES.sha256 was written"]))
    #expect(decide(.success("/s"), includesMarker: nil) == .compile(shadercross: "/s", staleCheckedIn: []))
    #expect(decide(.success("/s")) == .compile(shadercross: "/s", staleCheckedIn: []))
}

/// A scratch `Shaders` with the stage sources, `headers` on disk and `compiled/` holding `blobs`
/// (markers computed from what is on disk unless `includesMarker` overrides).
private func buildArguments(_ root: URL, headersOnDisk: [(name: String, bytes: [UInt8])] = headers,
                            includesMarker: String?? = .none) throws -> CompileArguments {
    let shaders = root.appendingPathComponent("Shaders"), compiled = shaders.appendingPathComponent("compiled")
    try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
    for source in stageSources + headersOnDisk { try write(String(decoding: source.bytes, as: UTF8.self), shaders.appendingPathComponent(source.name)) }
    for name in blobs where !name.hasSuffix(".sha256") { try write("blob \(name)", compiled.appendingPathComponent(name)) }
    try write(SourceMarker.contents(of: stageSources), compiled.appendingPathComponent("SOURCE.sha256"))
    switch includesMarker {
    case .none: try write(SourceMarker.contents(of: headersOnDisk), compiled.appendingPathComponent("INCLUDES.sha256"))
    case .some(.some(let text)): try write(text, compiled.appendingPathComponent("INCLUDES.sha256"))
    case .some(.none): break
    }
    return try CompileArguments.parse(["--on-build", "--source", shaders.path, "--checked-in", compiled.path,
                                       "--out", root.appendingPathComponent("out/MetalUIAppShaders").path,
                                       "--environment-shadercross", "", "--environment-path", "", "--display-source", display])
}

private func runCopy(_ arguments: CompileArguments) throws -> [String] {
    nonisolated(unsafe) var logs: [String] = []
    try ShaderCompiler.runOnBuild(arguments, environment: [:], windows: false, fileExists: { _ in false },
                                  runner: { _, _, _ in Issue.record("ran shadercross"); return 0 }, log: { logs.append($0) }, warn: { _ in })
    return logs
}

/// **19.** Through the run on disk (no shadercross): matching headers copy `INCLUDES.sha256`; a header-only edit on disk
/// fails naming the header; the headerless fixture copies no `INCLUDES.sha256` (byte-identical to before).
/// Mutations: the run reads no includes; the run reads includes outside `Shaders/compiled`'s exclusion.
@Test func theOnBuildCopyRunVerifiesHeadersOnDisk() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let arguments = try buildArguments(root)
    let out = URL(fileURLWithPath: arguments.out)
    let logs = try runCopy(arguments)
    #expect(try Data(contentsOf: out.appendingPathComponent("INCLUDES.sha256")) == Data(SourceMarker.contents(of: headers).utf8))
    #expect(logs.contains { $0.contains("and 2 include(s) against INCLUDES.sha256") }, "\(logs)")
    // Header-only edit on disk.
    try write("common edited", URL(fileURLWithPath: arguments.source).appendingPathComponent("common.hlsli"))
    do { _ = try runCopy(arguments); Issue.record("accepted a stale header") } catch {
        #expect("\(error)".contains("common.hlsli changed since INCLUDES.sha256 was written"), "\(error)")
    }
    // The headerless package: no INCLUDES.sha256 anywhere.
    let plainRoot = try makeRoot()
    defer { try? FileManager.default.removeItem(at: plainRoot) }
    let plain = try buildArguments(plainRoot, headersOnDisk: [], includesMarker: .some(nil))
    let plainLogs = try runCopy(plain)
    #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: plain.out).appendingPathComponent("INCLUDES.sha256").path))
    #expect(plainLogs.contains { $0.hasPrefix("Verified 2 checked-in shader(s) against SOURCE.sha256 (no shadercross)") }, "\(plainLogs)")
    // A blob under compiled/ is never an include source: a `.hlsli` there changes nothing.
    try write("x", URL(fileURLWithPath: plain.source).appendingPathComponent("compiled/blob.hlsli"))
    _ = try runCopy(plain)
}

/// **20.** The compile arm and the command plugin's run (`ShaderCompiler.run`) write `INCLUDES.sha256` only when include
/// sources exist, and remove a stale one when they no longer do. Mutations: write it always; never remove; skip it in `run`.
@Test func theToolWritesTheIncludesMarkerOnlyWhenHeadersExist() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var arguments = try buildArguments(root)
    arguments.environmentShadercross = "/stub/shadercross"
    let out = URL(fileURLWithPath: arguments.out)
    let marker = out.appendingPathComponent("INCLUDES.sha256")
    let stub: ShaderRunner = { _, args, _ in
        if let index = args.firstIndex(of: "-o") { _ = FileManager.default.createFile(atPath: args[index + 1], contents: Data("{}".utf8)) }
        return 0
    }
    try ShaderCompiler.runOnBuild(arguments, environment: [:], windows: false, fileExists: { $0 == "/stub/shadercross" },
                                  runner: stub, log: { _ in }, warn: { _ in })
    #expect(try Data(contentsOf: marker) == Data(SourceMarker.contents(of: headers).utf8))
    // The command plugin's path: `--source` and `--out`, an `out` that is `compiled/` itself.
    let source = URL(fileURLWithPath: arguments.source), compiled = source.appendingPathComponent("compiled")
    let command = try CompileArguments.parse(["--source", source.path, "--out", compiled.path, "--shadercross", "/stub/shadercross"])
    try ShaderCompiler.run(command, environment: [:], windows: false, fileExists: { $0 == "/stub/shadercross" }, runner: stub, log: { _ in })
    #expect(try Data(contentsOf: compiled.appendingPathComponent("INCLUDES.sha256")) == Data(SourceMarker.contents(of: headers).utf8))
    #expect(try Data(contentsOf: compiled.appendingPathComponent("SOURCE.sha256")) == Data(SourceMarker.contents(of: stageSources).utf8),
            "SOURCE.sha256 keeps meaning stage sources only")
    // Headers gone: the stale marker goes with them, in both runs.
    for header in headers { try FileManager.default.removeItem(at: source.appendingPathComponent(header.name)) }
    try ShaderCompiler.run(command, environment: [:], windows: false, fileExists: { $0 == "/stub/shadercross" }, runner: stub, log: { _ in })
    #expect(!FileManager.default.fileExists(atPath: compiled.appendingPathComponent("INCLUDES.sha256").path))
    try ShaderCompiler.runOnBuild(arguments, environment: [:], windows: false, fileExists: { $0 == "/stub/shadercross" },
                                  runner: stub, log: { _ in }, warn: { _ in })
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

/// **21.** The plugin cannot import the tool's library, so its selection is the library's text: the marked region is
/// byte-identical in both files, and the plugin hands the selected files to the build command as inputs.
/// Mutations: edit the region in `Plugin.swift` only (one suffix); drop `includes` from `inputFiles`.
@Test func theBuildPluginSelectsIncludeSourcesExactlyAsTheToolDoes() throws {
    func region(_ path: String) throws -> String {
        let text = try String(contentsOf: checkout.appendingPathComponent(path), encoding: .utf8)
        let begin = try #require(text.range(of: "// BEGIN include-selection"), "\(path) has no region")
        let end = try #require(text.range(of: "// END include-selection"), "\(path) has no region end")
        return String(text[begin.lowerBound..<end.upperBound])
    }
    let plugin = "Plugins/CompileShadersOnBuild/Plugin.swift"
    let library = try region("Backends/SDL/Sources/MetalUIShaderCompile/IncludeSources.swift")
    #expect(try region(plugin) == library)
    #expect(library.contains("enum IncludeSelection"), "the region must be the selection itself")
    let source = try String(contentsOf: checkout.appendingPathComponent(plugin), encoding: .utf8)
    #expect(source.contains("IncludeSelection.relativePaths(under: shaders.path)"))
    #expect(source.contains("includes.map { shaders.appendingPathComponent($0) }"))
    let inputs = try #require(source.range(of: "inputFiles:"))
    let line = String(source[inputs.lowerBound...].prefix { $0 != "\n" })
    #expect(line.contains("includes.map") && line.contains("sources.map") && line.contains("blobs.map"), "\(line)")
}

/// **22.** The shipped fixture directory has no headers, so its output and checked-in blobs carry no `INCLUDES.sha256`.
/// Mutation: write the marker with no headers.
@Test func theCheckedInAppShadersHaveNoIncludeSourcesAndNoIncludesMarker() {
    let shaders = checkout.appendingPathComponent("Backends/SDL/Tests/AppShaders")
    #expect(IncludeSelection.relativePaths(under: shaders.path).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: shaders.appendingPathComponent("compiled/INCLUDES.sha256").path))
}
