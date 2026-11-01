import Foundation
import Testing
@testable import MetalUIShaderCompile

// XP-G36 (rulings UB-A...UB-H): a declared register the compiler dropped must be a named error, because
// SDL_GPU binds uniform buffers, samplers and storage resources by count from slot 0. Portable: no shadercross.

private let checkout = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// MetalCreator's `zebra_mesh.frag.hlsl` shape: b0..b3, the first version never reads `Draw`.
private let zebra = """
    // Draw is declared first but never read.
    cbuffer Draw : register(b0, space3) { float4 drawConstants; };
    cbuffer Shade : register(b1, space3) { float4 shade; };
    cbuffer Clip : register(b2, space3) { float4 clip; };
    cbuffer Zebra : register(b3, space3) { float4 zebra; };
    float4 main() : SV_Target0 { return shade + clip + zebra; }
    """

private func counts(uniform: Int) -> ShaderSlotCheck.Counts { .init(uniformBuffers: uniform) }

/// **UB-1.** The report's shader: four declared, three reflected. Mutation: compare with `>=`; drop the uniform arm.
@Test func aDroppedUniformBufferIsNamedWithItsRegisters() throws {
    let problems = ShaderSlotCheck.problems(name: "zebra_mesh.frag.hlsl", stage: .fragment, source: zebra, counts: counts(uniform: 3))
    let text = try #require(problems.first)
    #expect(problems.count == 1)
    for part in ["zebra_mesh.frag.hlsl", "4 uniform buffer(s) in space3", "b0 `Draw`", "b1 `Shade`", "b2 `Clip`", "b3 `Zebra`",
                 "reflects 3", "by count from slot 0", "contiguous from b0"] {
        #expect(text.contains(part), "missing \(part): \(text)")
    }
}

/// **UB-2.** The control: all four read, four reflected; and a vertex shader's uniforms live in space1, not space3.
/// Mutation: ignore the space (the vertex arm then sees the fragment's b registers).
@Test func aContiguousFullyReadSetPassesAndTheSpaceSelectsTheStage() {
    #expect(ShaderSlotCheck.problems(name: "z", stage: .fragment, source: zebra, counts: counts(uniform: 4)).isEmpty)
    #expect(ShaderSlotCheck.problems(name: "z", stage: .vertex, source: zebra, counts: counts(uniform: 0)).isEmpty,
            "space3 is not a vertex shader's uniform space")
    let vertex = "cbuffer V : register(b0, space1) { float a; };\ncbuffer W : register(b1, space1) { float b; };"
    #expect(ShaderSlotCheck.problems(name: "v", stage: .vertex, source: vertex, counts: counts(uniform: 1)).count == 1)
    let compute = "cbuffer P : register(b0, space2) { uint n; };"
    #expect(ShaderSlotCheck.problems(name: "c", stage: .compute, source: compute, counts: counts(uniform: 0)).count == 1)
}

/// **UB-3.** A source gap (b0, b2) is refused even when the count matches. Mutation: drop the contiguity arm.
@Test func aGapInTheDeclaredSetIsRefused() throws {
    let source = "cbuffer A : register(b0, space3) { float a; };\ncbuffer C : register(b2, space3) { float c; };"
    let problems = ShaderSlotCheck.problems(name: "g.frag.hlsl", stage: .fragment, source: source, counts: counts(uniform: 2))
    let text = try #require(problems.first)
    #expect(problems.count == 1 && text.contains("b0, b2") && text.contains("Renumber them to b0, b1"), "\(text)")
}

/// **UB-4.** Samplers, textures and storage count too (`s` against samplers; `t` against samplers plus read-only
/// storage; `u` against read-write storage). Mutation: drop one relation each.
@Test func droppedSamplersTexturesAndStorageAreNamedToo() throws {
    let source = """
        Texture2D<float4> a : register(t0, space2);
        Texture2D<float4> b : register(t1, space2);
        SamplerState aS : register(s0, space2);
        SamplerState bS : register(s1, space2);
        StructuredBuffer<float4> p : register(t2, space2);
        """
    #expect(ShaderSlotCheck.problems(name: "f", stage: .fragment, source: source,
                                     counts: .init(samplers: 2, readOnlyStorageBuffers: 1)).isEmpty)
    let dropped = ShaderSlotCheck.problems(name: "f", stage: .fragment, source: source, counts: .init(samplers: 1, readOnlyStorageBuffers: 1))
    #expect(dropped.count == 2, "\(dropped)")
    #expect(dropped.contains { $0.contains("2 sampler(s)") && $0.contains("s1 `bS`") })
    #expect(dropped.contains { $0.contains("3 sampled texture or read-only storage resource(s)") && $0.contains("t2 `p`") })
    let kernel = "RWByteAddressBuffer o : register(u0, space1);\nRWTexture2D<float4> w : register(u1, space1);"
    #expect(ShaderSlotCheck.problems(name: "k", stage: .compute, source: kernel, counts: .init(readWriteStorageBuffers: 1)).count == 1)
    #expect(ShaderSlotCheck.problems(name: "k", stage: .compute, source: kernel,
                                     counts: .init(readWriteStorageTextures: 1, readWriteStorageBuffers: 1)).isEmpty)
}

/// **UB-5.** What the scan must not count: comments, and a reflected count above the declared one (a header's
/// registers are not read). Conditional registers do not make a gap or an overcount. The opt-out text skips.
/// Mutation: stop stripping comments; treat conditional registers as certain.
@Test func commentsConditionalsHeadersAndTheOptOutAreNotFindings() {
    let commented = """
        // cbuffer Old : register(b1, space3) { float x; };
        /* cbuffer Older : register(b2, space3) {
           float y; }; */
        cbuffer A : register(b0, space3) { float a; };
        """
    #expect(ShaderSlotCheck.declarations(in: commented).map(\.slot) == [0])
    #expect(ShaderSlotCheck.problems(name: "c", stage: .fragment, source: commented, counts: counts(uniform: 1)).isEmpty)
    #expect(ShaderSlotCheck.problems(name: "h", stage: .fragment, source: commented, counts: counts(uniform: 2)).isEmpty,
            "a header's buffer raises the reflected count above the declared")
    let conditional = """
        cbuffer A : register(b0, space3) { float a; };
        #ifdef WITH_CLIP
        cbuffer C : register(b1, space3) { float c; };
        #endif
        cbuffer D : register(b2, space3) { float d; };
        """
    let found = ShaderSlotCheck.declarations(in: conditional)
    #expect(found.map(\.conditional) == [false, true, false] && found.map(\.line) == [1, 3, 5])
    #expect(ShaderSlotCheck.problems(name: "k", stage: .fragment, source: conditional, counts: counts(uniform: 2)).isEmpty,
            "b1 is under #ifdef: neither a gap nor a dropped slot")
    #expect(ShaderSlotCheck.problems(name: "z", stage: .fragment, source: "// \(ShaderSlotCheck.optOut)\n" + zebra,
                                     counts: counts(uniform: 3)).isEmpty)
}

/// **UB-6.** The reflection JSON in both spellings. Mutation: read only `readonly_storage_*`.
@Test func countsReadBothJsonSpellings() throws {
    let graphics = try #require(ShaderSlotCheck.Counts(json: #"{ "samplers": 1, "storage_textures": 2, "storage_buffers": 3, "uniform_buffers": 4 }"#))
    #expect(graphics == .init(samplers: 1, readOnlyStorageTextures: 2, readOnlyStorageBuffers: 3, uniformBuffers: 4))
    let compute = try #require(ShaderSlotCheck.Counts(json: #"{ "samplers": 0, "readonly_storage_textures": 1, "readonly_storage_buffers": 2, "readwrite_storage_textures": 3, "readwrite_storage_buffers": 4, "uniform_buffers": 5 }"#))
    #expect(compute == .init(readOnlyStorageTextures: 1, readOnlyStorageBuffers: 2, readWriteStorageTextures: 3,
                             readWriteStorageBuffers: 4, uniformBuffers: 5))
    #expect(ShaderSlotCheck.Counts(json: "not json") == nil)
}

// MARK: - Through the tool

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("metalui-slots-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A stub shadercross that writes `json` where the JSON command's `-o` points.
private func stubRunner(json: String) -> ShaderRunner {
    { _, args, _ in
        if let dash = args.firstIndex(of: "JSON"), args[dash - 1] == "-d", let out = args.last {
            try Data(json.utf8).write(to: URL(fileURLWithPath: out))
        }
        return 0
    }
}

private func compileArguments(_ root: URL) throws -> CompileArguments {
    let source = root.appendingPathComponent("src"), out = root.appendingPathComponent("out")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data(zebra.utf8).write(to: source.appendingPathComponent("zebra_mesh.frag.hlsl"))
    return try CompileArguments.parse(["--source", source.path, "--out", out.path, "--shadercross", "/stub/shadercross"])
}

/// **UB-7.** The tool's compile arm: the report's case fails naming the shader, the control passes; both through
/// `ShaderCompiler.run`. Mutation: delete the `checkSlots` call in `run`.
@Test func theCompileRunFailsOnADroppedSlotAndPassesTheControl() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let arguments = try compileArguments(root)
    func run(_ json: String) throws {
        try ShaderCompiler.run(arguments, environment: [:], windows: false, fileExists: { $0 == "/stub/shadercross" },
                               runner: stubRunner(json: json), log: { _ in })
    }
    let error = #expect(throws: ShaderCompileError.self) {
        try run(#"{ "samplers": 0, "storage_textures": 0, "storage_buffers": 0, "uniform_buffers": 3 }"#)
    }
    #expect(error?.description.contains("zebra_mesh.frag.hlsl: the source declares 4 uniform buffer(s)") == true, "\(String(describing: error))")
    try run(#"{ "samplers": 0, "storage_textures": 0, "storage_buffers": 0, "uniform_buffers": 4 }"#)
}

/// **UB-8.** The build plugin's copy arm (no shadercross): checked-in blobs whose reflection lost a slot are refused,
/// matching ones copied. Mutation: delete the check in the `.copy` case.
@Test func theCopyArmChecksCheckedInBlobsAgainstTheirSources() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let shaders = root.appendingPathComponent("Shaders"), compiled = shaders.appendingPathComponent("compiled")
    try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
    let sourceBytes = Array(zebra.utf8)
    try Data(sourceBytes).write(to: shaders.appendingPathComponent("zebra_mesh.frag.hlsl"))
    try Data(SourceMarker.contents(of: [(name: "zebra_mesh.frag.hlsl", bytes: sourceBytes)]).utf8)
        .write(to: compiled.appendingPathComponent("SOURCE.sha256"))
    try Data("spv".utf8).write(to: compiled.appendingPathComponent("zebra_mesh.frag.spv"))
    let arguments = try CompileArguments.parse(["--on-build", "--source", shaders.path, "--checked-in", compiled.path,
                                                "--out", root.appendingPathComponent("out").path,
                                                "--environment-shadercross", "", "--environment-path", ""])
    func runOnBuild() throws {
        try ShaderCompiler.runOnBuild(arguments, environment: [:], windows: false, fileExists: { _ in false },
                                      runner: { _, _, _ in Issue.record("ran shadercross"); return 0 }, log: { _ in }, warn: { _ in })
    }
    try Data(#"{ "samplers": 0, "uniform_buffers": 3 }"#.utf8).write(to: compiled.appendingPathComponent("zebra_mesh.frag.json"))
    let error = #expect(throws: ShaderCompileError.self) { try runOnBuild() }
    #expect(error?.description.contains("reflects 3") == true)
    try Data(#"{ "samplers": 0, "uniform_buffers": 4 }"#.utf8).write(to: compiled.appendingPathComponent("zebra_mesh.frag.json"))
    try runOnBuild()
}

/// **UB-9.** No false positive on what is checked in: every app-shader source against its own checked-in reflection.
/// Mutation: count `t` registers against `samplers` only (the replay-style storage buffers then fail).
@Test func everyCheckedInAppShaderPassesItsOwnReflection() throws {
    let directory = checkout.appendingPathComponent("Backends/SDL/Tests/AppShaders")
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    let sources = names.compactMap(ShaderSource.init(fileName:))
    #expect(sources.count >= 8)
    for source in sources {
        let text = try String(contentsOf: directory.appendingPathComponent(source.fileName), encoding: .utf8)
        let json = try String(contentsOf: directory.appendingPathComponent("compiled/\(source.stem).json"), encoding: .utf8)
        let counts = try #require(ShaderSlotCheck.Counts(json: json))
        #expect(ShaderSlotCheck.problems(name: source.fileName, stage: source.stage, source: text, counts: counts).isEmpty, "\(source.fileName)")
    }
}
