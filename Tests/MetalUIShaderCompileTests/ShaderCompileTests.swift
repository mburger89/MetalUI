import Foundation
import Testing
@testable import MetalUIShaderCompile

// Build-time app shaders (item S12, rulings BS-A...BS-J, spec §5). Portable:
// Foundation only, no shadercross unless a test says so.

private func hex(_ text: String) -> String { SHA256.hexDigest(of: Array(text.utf8)) }

private let checkout = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let appShaders = checkout.appendingPathComponent("Backends/SDL/Tests/AppShaders")

/// **Test 0** (`BS-I`). FIPS 180-4 vectors and every padding boundary. Mutation:
/// a wrong rotation constant; no length byte; a little-endian length.
@Test func sha256MatchesTheNISTVectors() {
    #expect(hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
            == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    let boundaries: [Int: String] = [
        55: "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
        56: "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
        63: "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34",
        64: "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
        65: "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0",
        119: "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb",
        120: "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c"]
    for (count, digest) in boundaries {
        #expect(SHA256.hexDigest(of: [UInt8](repeating: 0x61, count: count)) == digest, "\(count) bytes")
    }
    #expect(SHA256.hexDigest(of: [UInt8](repeating: 0x61, count: 1_000_000))
            == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
}

/// **Test 1.** The stage and stem come from the suffix. Mutation: map `frag` to compute.
@Test func aSourceNameYieldsItsStageAndStem() throws {
    let vertex = try #require(ShaderSource(fileName: "tri.vert.hlsl"))
    #expect(vertex.stem == "tri.vert" && vertex.stage == .vertex && vertex.fileName == "tri.vert.hlsl")
    let fragment = try #require(ShaderSource(fileName: "tri.frag.hlsl"))
    #expect(fragment.stage == .fragment && fragment.stage.rawValue == "fragment")
    let compute = try #require(ShaderSource(fileName: "append.comp.hlsl"))
    #expect(compute.stage == .compute && compute.stem == "append.comp")
    let dotted = try #require(ShaderSource(fileName: "a.b.vert.hlsl"))
    #expect(dotted.stem == "a.b.vert" && dotted.stage == .vertex)
}

private let allFormats = Set(ShaderFormat.allCases)

/// **Test 2.** The exact argument vectors, in order SPIR-V, MSL, DXIL, JSON.
/// Mutation: swap `-s`/`-d` of a derivation; derive from the HLSL.
@Test func theCommandPlanIsHlslToSpirvThenTheDerivations() throws {
    let vertex = try #require(ShaderSource(fileName: "tri.vert.hlsl"))
    #expect(ShaderCompilePlan.commands(for: vertex, sourceDirectory: "/s", outDirectory: "/o", formats: allFormats) == [
        ["/s/tri.vert.hlsl", "-s", "HLSL", "-d", "SPIRV", "-t", "vertex", "-o", "/o/tri.vert.spv"],
        ["/o/tri.vert.spv", "-s", "SPIRV", "-d", "MSL", "-t", "vertex", "-o", "/o/tri.vert.msl"],
        ["/o/tri.vert.spv", "-s", "SPIRV", "-d", "DXIL", "-t", "vertex", "-o", "/o/tri.vert.dxil"],
        ["/o/tri.vert.spv", "-s", "SPIRV", "-d", "JSON", "-t", "vertex", "-o", "/o/tri.vert.json"]])
    let compute = try #require(ShaderSource(fileName: "append.comp.hlsl"))
    #expect(ShaderCompilePlan.commands(for: compute, sourceDirectory: "src/", outDirectory: "out/", formats: allFormats) == [
        ["src/append.comp.hlsl", "-s", "HLSL", "-d", "SPIRV", "-t", "compute", "-o", "out/append.comp.spv"],
        ["out/append.comp.spv", "-s", "SPIRV", "-d", "MSL", "-t", "compute", "-o", "out/append.comp.msl"],
        ["out/append.comp.spv", "-s", "SPIRV", "-d", "DXIL", "-t", "compute", "-o", "out/append.comp.dxil"],
        ["out/append.comp.spv", "-s", "SPIRV", "-d", "JSON", "-t", "compute", "-o", "out/append.comp.json"]])
}

/// **Test 3.** `--formats` skips the unrequested; the SPIR-V is the intermediate
/// and always built. Mutation: drop `spv` from the always set.
@Test func formatsSkipsTheUnrequestedButAlwaysBuildsSpirv() throws {
    let source = try #require(ShaderSource(fileName: "tri.frag.hlsl"))
    let onlyMetal = ShaderCompilePlan.commands(for: source, sourceDirectory: "/s", outDirectory: "/o", formats: [.msl])
    #expect(onlyMetal.count == 2)
    #expect(onlyMetal[0].last == "/o/tri.frag.spv" && onlyMetal[1].last == "/o/tri.frag.msl")
    let none = ShaderCompilePlan.commands(for: source, sourceDirectory: "/s", outDirectory: "/o", formats: [])
    #expect(none.count == 1 && none[0].last == "/o/tri.frag.spv")
    let noDXIL = ShaderCompilePlan.commands(for: source, sourceDirectory: "/s", outDirectory: "/o", formats: [.msl, .json])
    #expect(noDXIL.map { $0.last } == ["/o/tri.frag.spv", "/o/tri.frag.msl", "/o/tri.frag.json"])
    #expect(try CompileArguments.parse(["--source", "a", "--out", "b", "--formats", "spv,msl"]).formats == [.spv, .msl])
}

/// **Test 4.** The marker over the checked-in sources equals the checked-in
/// `SOURCE.sha256` (the python script's output), byte for byte. Mutation: sort
/// descending; one space separator; CRLF.
@Test func theMarkerEqualsTheCheckedInOneByteForByte() throws {
    let names = try FileManager.default.contentsOfDirectory(atPath: appShaders.path).filter { $0.hasSuffix(".hlsl") }
    try #require(names.count >= 8)
    let sources = try names.map { (name: $0, bytes: [UInt8](try Data(contentsOf: appShaders.appendingPathComponent($0)))) }
    let expected = try String(contentsOf: appShaders.appendingPathComponent("compiled/SOURCE.sha256"), encoding: .utf8)
    #expect(SourceMarker.contents(of: sources) == expected)
    #expect(SourceMarker.contents(of: sources.reversed()) == expected, "the order of the input does not matter")
    // Bytewise, not Unicode-aware: an uppercase name sorts before a lowercase one, "é" after "z".
    let tricky = SourceMarker.contents(of: [("b.vert.hlsl", []), ("B.vert.hlsl", []), ("\u{e9}.vert.hlsl", []), ("z.vert.hlsl", [])])
    #expect(tricky.split(separator: "\n").map { $0.split(separator: " ").last.map(String.init) }
            == ["B.vert.hlsl", "b.vert.hlsl", "z.vert.hlsl", "\u{e9}.vert.hlsl"])
}

/// **Test 5.** Only `NAME.<stage>.hlsl` counts; none is an error naming the directory.
/// Mutation: accept `x.hlsl`.
@Test func sourcesWithoutAStageSuffixAreIgnoredAndNoneIsAnError() throws {
    let found = try ShaderCompilePlan.sources(in: ["x.hlsl", "b.frag.hlsl", "a.vert.hlsl", "notes.txt", "c.geom.hlsl", "d.vert.hlsl.bak"],
                                              directory: "/s")
    #expect(found.map(\.fileName) == ["a.vert.hlsl", "b.frag.hlsl"])
    do { _ = try ShaderCompilePlan.sources(in: ["x.hlsl", "readme.md"], directory: "/shaders"); Issue.record("accepted no source") }
    catch { #expect(String(describing: error).contains("/shaders"), "\(error)") }
}

private func exists(_ path: String) -> Bool { true }

/// **Test 6.** The flag, then the variable, then `PATH`. Mutation: swap two.
@Test func shadercrossIsFoundByFlagThenEnvironmentThenPath() throws {
    let environment = ["METALUI_SHADERCROSS": "/env/shadercross", "PATH": "/p1:/p2"]
    #expect(try ShadercrossLocator.locate(flag: "/flag/sc", environment: environment, fileExists: exists, windows: false) == "/flag/sc")
    #expect(try ShadercrossLocator.locate(flag: nil, environment: environment, fileExists: exists, windows: false) == "/env/shadercross")
    #expect(try ShadercrossLocator.locate(flag: nil, environment: ["PATH": "/p1:/p2"], fileExists: { $0 == "/p2/shadercross" },
                                          windows: false) == "/p2/shadercross")
    #expect(try ShadercrossLocator.locate(flag: nil, environment: ["PATH": "C:\\a;C:\\b"], fileExists: { $0 == "C:\\b/shadercross.exe" },
                                          windows: true) == "C:\\b/shadercross.exe")
    // A flag that names no file is an error, never a fall-through to the variable.
    do {
        _ = try ShadercrossLocator.locate(flag: "/nope", environment: environment, fileExists: { $0 != "/nope" }, windows: false)
        Issue.record("fell through a missing flag")
    } catch { #expect(String(describing: error).contains("/nope"), "\(error)") }
}

/// **Test 7.** A missing shadercross names all three places. Mutation: omit the variable.
@Test func aMissingShadercrossNamesAllThreePlaces() {
    do { _ = try ShadercrossLocator.locate(flag: nil, environment: ["PATH": "/p"], fileExists: { _ in false }, windows: false)
        Issue.record("found a shadercross") }
    catch {
        let text = String(describing: error)
        #expect(text.contains("--shadercross") && text.contains("METALUI_SHADERCROSS") && text.contains("PATH"), "\(text)")
    }
}

/// **Test 8.** The `lib` beside `bin` joins the loader path, first. Mutation: append.
@Test func theLibraryDirectoryBesideBinJoinsTheLoaderPath() {
    let environment = ["DYLD_LIBRARY_PATH": "/old", "OTHER": "x"]
    let unix = ShadercrossLocator.loaderEnvironment(forExecutable: "/opt/sc/bin/shadercross", environment: environment,
                                                    directoryExists: { $0 == "/opt/sc/lib" }, windows: false)
    #expect(unix["DYLD_LIBRARY_PATH"] == "/opt/sc/lib:/old")
    #expect(unix["LD_LIBRARY_PATH"] == "/opt/sc/lib")
    #expect(unix["OTHER"] == "x")
    let absent = ShadercrossLocator.loaderEnvironment(forExecutable: "/opt/sc/bin/shadercross", environment: environment,
                                                      directoryExists: { _ in false }, windows: false)
    #expect(absent == environment)
    let windows = ShadercrossLocator.loaderEnvironment(forExecutable: "C:/sc/bin/shadercross.exe", environment: environment,
                                                       directoryExists: { _ in true }, windows: true)
    #expect(windows == environment, "Windows finds DLLs beside the executable")
}

/// **Test 9.** The command line. Mutation: ignore `--no-marker`.
@Test func aMissingSourceOrOutIsAUsageError() {
    for arguments in [[], ["--source", "s"], ["--out", "o"], ["--source", "s", "--out"]] {
        #expect(throws: CompileUsageError.self) { _ = try CompileArguments.parse(arguments) }
    }
}
@Test func anUnknownFlagIsAUsageError() {
    #expect(throws: CompileUsageError.self) { _ = try CompileArguments.parse(["--source", "s", "--out", "o", "--bogus"]) }
    #expect(throws: CompileUsageError.self) { _ = try CompileArguments.parse(["--source", "s", "--out", "o", "--formats", "spv,wgsl"]) }
}
@Test func noMarkerIsParsed() throws {
    let plain = try CompileArguments.parse(["--source", "s", "--out", "o"])
    #expect(plain.writesMarker && plain.formats == allFormats && plain.shadercross == nil && plain.base == nil)
    let full = try CompileArguments.parse(["--source", "s", "--out", "o", "--no-marker", "--shadercross", "/x/sc", "--base", "/pkg"])
    #expect(!full.writesMarker && full.shadercross == "/x/sc" && full.base == "/pkg")
    #expect(full.resolvedSource == "/pkg/s" && full.resolvedOut == "/pkg/o")
    let absolute = try CompileArguments.parse(["--source", "/abs/s", "--out", "/abs/o", "--base", "/pkg"])
    #expect(absolute.resolvedSource == "/abs/s" && absolute.resolvedOut == "/abs/o")
}

// MARK: - The runner

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("metalui-shadercompile-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// `ShaderCompiler.run` calls the runner once per command in plan order, writes
/// the marker last, and a non-zero exit is an error naming the command.
/// Mutation: write the marker before compiling; ignore the exit status.
@Test func theRunnerFollowsThePlanAndWritesTheMarker() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("src"), out = root.appendingPathComponent("out")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("float4 main() : SV_Target { return 0; }".utf8).write(to: source.appendingPathComponent("a.frag.hlsl"))
    try Data("ignored".utf8).write(to: source.appendingPathComponent("x.hlsl"))
    nonisolated(unsafe) var calls: [[String]] = []
    let arguments = try CompileArguments.parse(["--source", source.path, "--out", out.path, "--shadercross", "/fake/shadercross"])
    try ShaderCompiler.run(arguments, environment: [:], windows: false, fileExists: { $0 == "/fake/shadercross" },
                           runner: { executable, args, _ in
        #expect(executable == "/fake/shadercross")
        calls.append(args)
        if let output = args.last, let index = args.firstIndex(of: "-o"), index + 1 == args.count - 1 {
            FileManager.default.createFile(atPath: output, contents: Data("{ \"samplers\": 0 }".utf8))
        }
        return 0
    }, log: { _ in })
    #expect(calls.count == 4)
    #expect(calls.map { $0.last.map { URL(fileURLWithPath: $0).lastPathComponent } }
            == ["a.frag.spv", "a.frag.msl", "a.frag.dxil", "a.frag.json"])
    let marker = try String(contentsOf: out.appendingPathComponent("SOURCE.sha256"), encoding: .utf8)
    #expect(marker == "\(hex("float4 main() : SV_Target { return 0; }"))  a.frag.hlsl\n")

    let noMarker = try CompileArguments.parse(["--source", source.path, "--out", out.appendingPathComponent("n").path,
                                               "--shadercross", "/fake/shadercross", "--no-marker"])
    try ShaderCompiler.run(noMarker, environment: [:], windows: false, fileExists: { _ in true }, runner: { _, _, _ in 0 }, log: { _ in })
    #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("n/SOURCE.sha256").path))

    do {
        try ShaderCompiler.run(arguments, environment: [:], windows: false, fileExists: { _ in true },
                               runner: { _, _, _ in 3 }, log: { _ in })
        Issue.record("ignored a failing shadercross")
    } catch { #expect(String(describing: error).contains("3") && String(describing: error).contains("a.frag"), "\(error)") }
}

// MARK: - Real shadercross (env-gated)

private let realShadercross = ProcessInfo.processInfo.environment["METALUI_SHADERCROSS"]

/// **Test 10.** With a real shadercross: compiles `tri.vert`/`tri.frag` into
/// SPIR-V (magic `0x07230203`), a reflection JSON equal to the checked-in one's
/// and the marker. Off unless `METALUI_SHADERCROSS=/path`; counts while skipped.
/// Mutation: a wrong stage flag.
@Test(.enabled(if: realShadercross != nil))
func anEnvGatedRunCompilesAFixture() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("src"), out = root.appendingPathComponent("out")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    for name in ["tri.vert.hlsl", "tri.frag.hlsl"] {
        try FileManager.default.copyItem(at: appShaders.appendingPathComponent(name), to: source.appendingPathComponent(name))
    }
    let arguments = try CompileArguments.parse(["--source", source.path, "--out", out.path])
    try ShaderCompiler.run(arguments, environment: ProcessInfo.processInfo.environment, log: { _ in })
    for stem in ["tri.vert", "tri.frag"] {
        let spirv = [UInt8](try Data(contentsOf: out.appendingPathComponent("\(stem).spv")))
        #expect(spirv.count > 20 && spirv[0] == 0x03 && spirv[1] == 0x02 && spirv[2] == 0x23 && spirv[3] == 0x07, "\(stem) magic")
        let built = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("\(stem).json"))) as? NSDictionary
        let checkedIn = try JSONSerialization.jsonObject(
            with: Data(contentsOf: appShaders.appendingPathComponent("compiled/\(stem).json"))) as? NSDictionary
        #expect(built != nil && built == checkedIn, "\(stem) reflection")
    }
    #expect(try String(contentsOf: out.appendingPathComponent("SOURCE.sha256"), encoding: .utf8).split(separator: "\n").count == 2)
}

// MARK: - The command plugin on a fixture package (env-gated)

private func shell(_ executable: String, _ arguments: [String], in directory: URL, environment: [String: String]) throws
    -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.currentDirectoryURL = directory
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// **Test 11.** A temporary package depending on this checkout by path runs
/// `swift package --allow-writing-to-package-directory compile-shaders` with a
/// **stub** `shadercross` (a shell script that writes its `-o` argument) and
/// finds the blobs and the marker; without the permission flag SwiftPM refuses.
/// The stub needs no real shadercross, so this is the always-meaningful proof
/// that the plugin builds and reaches the tool. Off unless
/// `METALUI_RUN_SHADER_PLUGIN_TEST=1` (a build of the tool, minutes cold; counts while skipped).
/// Mutation: rename the verb.
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_SHADER_PLUGIN_TEST"] == "1"))
func theCompileShadersPluginRunsOnAFixturePackage() throws {
    #if os(macOS) || os(Linux)
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let package = root.appendingPathComponent("Fixture")
    try FileManager.default.createDirectory(at: package.appendingPathComponent("Sources/Fixture"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: package.appendingPathComponent("shaders"), withIntermediateDirectories: true)
    try Data("""
        // swift-tools-version: 6.1
        import PackageDescription
        let package = Package(name: "Fixture",
            dependencies: [.package(name: "MetalUI", path: "\(checkout.path)")],
            targets: [.executableTarget(name: "Fixture", path: "Sources/Fixture")])
        """.utf8).write(to: package.appendingPathComponent("Package.swift"))
    try Data("print(\"fixture\")\n".utf8).write(to: package.appendingPathComponent("Sources/Fixture/main.swift"))
    try FileManager.default.copyItem(at: appShaders.appendingPathComponent("tri.vert.hlsl"),
                                     to: package.appendingPathComponent("shaders/tri.vert.hlsl"))
    let stub = root.appendingPathComponent("shadercross-stub")
    try Data("""
        #!/bin/sh
        while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then out="$2"; fi; shift; done
        printf '{ "samplers": 0 }' > "$out"
        """.utf8).write(to: stub)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
    var environment = ProcessInfo.processInfo.environment
    environment["METALUI_SHADERCROSS"] = stub.path

    let refused = try shell("swift", ["package", "compile-shaders", "--source", "shaders", "--out", "shaders/compiled"],
                            in: package, environment: environment)
    print("3.11 without the permission flag: status=\(refused.status)\n\(refused.output.suffix(800))")
    #expect(refused.status != 0, "\(refused.output)")
    #expect(!FileManager.default.fileExists(atPath: package.appendingPathComponent("shaders/compiled/tri.vert.spv").path))

    let ran = try shell("swift", ["package", "--allow-writing-to-package-directory", "compile-shaders",
                                  "--source", "shaders", "--out", "shaders/compiled"], in: package, environment: environment)
    print("3.11 with the permission flag: status=\(ran.status)\n\(ran.output.suffix(1500))")
    #expect(ran.status == 0, "\(ran.output)")
    for name in ["tri.vert.spv", "tri.vert.msl", "tri.vert.dxil", "tri.vert.json", "SOURCE.sha256"] {
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("shaders/compiled/\(name)").path), "\(name)")
    }
    #endif
}
