import Foundation
import Testing
import SDLBridge
import MetalUISDLGPU
@testable import MetalUISDLGPU

// Tests 18-27 of the run-time compile spec: they need the shader compiler library
// (`METALUI_SHADERCROSS_LIB`, or found by the lookup of `RC-C`). Without it each is skipped and
// the skip reason names the paths tried; `METALUI_REQUIRE_SHADERCROSS=1` turns the skip into a
// failure (a CI job that builds shadercross sets it; none is added, `BS-G`). Same suite as
// `SDLGPURuntimeCompilerTests` (serialized, the process cache is global).

enum RuntimeCompilerSupport {
    /// Loads the process-wide compiler on first read.
    static let available: Bool = SDLGPUShaderCompiler.isAvailable
    static let required = ProcessInfo.processInfo.environment["METALUI_REQUIRE_SHADERCROSS"] == "1"
    static let atPin = ProcessInfo.processInfo.environment["METALUI_SHADERCROSS_AT_PIN"] == "1"
    static var skipReason: Comment {
        Comment(rawValue: "no shader compiler library here (set METALUI_SHADERCROSS_LIB): \(lastFailureText)")
    }
    static var lastFailureText: String {
        do { _ = try SDLGPUShaderCompiler.shared(); return "" } catch { return String(describing: error) }
    }

    /// Doubles `src` into `dst` times `K` (a define), `n` words: the probe's control kernel.
    static let scaleKernel = """
        StructuredBuffer<uint> src : register(t0, space0);
        RWStructuredBuffer<uint> dst : register(u0, space1);
        cbuffer P : register(b0, space2) { uint n; };
        [numthreads(64, 1, 1)]
        void main(uint3 id : SV_DispatchThreadID) { if (id.x < n) dst[id.x] = src[id.x] * K; }
        """
    /// A generated kernel of about `lines` lines (every line a float expression with calls).
    static func generated(lines: Int) -> String {
        var text = "RWStructuredBuffer<float> dst : register(u0, space1);\n[numthreads(64, 1, 1)]\nvoid main(uint3 id : SV_DispatchThreadID) {\n    float a0 = (float)id.x;\n"
        for i in 1..<max(lines - 4, 2) {
            text += "    float a\(i) = sqrt(abs(a\(i - 1) * 1.0001 + \(i % 7).5)) + floor(a\(i - 1) * 0.5);\n"
        }
        text += "    dst[id.x] = a\(max(lines - 5, 1));\n}\n"
        return text
    }
    static func target(for device: SDLGPUDevice) throws -> SDLGPUShaderTarget { try SDLGPUShaderTarget(driver: device.driver) }
    static func appShaderSource() throws -> String {
        try String(contentsOf: GPUTestSupport.sources.appendingPathComponent("append.comp.hlsl"), encoding: .utf8)
    }
}

private let needsCompiler = Comment(rawValue: "needs the shader compiler library (METALUI_SHADERCROSS_LIB)")

extension SDLGPURuntimeCompilerTests {
    /// `METALUI_REQUIRE_SHADERCROSS=1` makes a missing library a failure, so a skip cannot hide it.
    @Test func aRequiredShaderCompilerIsPresent() {
        guard RuntimeCompilerSupport.required else { return }
        #expect(RuntimeCompilerSupport.available, "METALUI_REQUIRE_SHADERCROSS=1 but \(RuntimeCompilerSupport.lastFailureText)")
    }

    /// **18.** A valid kernel compiles to the device's format with the reflection of the checked-in
    /// build-tool blob (`append.comp.json`) and with the control kernel's own counts.
    /// Mutation: the Swift side drops the read-write buffer count from the reflection.
    @Test(.enabled(if: RuntimeCompilerSupport.available, needsCompiler))
    func aValidKernelCompilesToTheDevicesFormatWithItsReflection() throws {
        let compiler = try SDLGPUShaderCompiler.shared()
        let blob = try compiler.compileCompute(name: "append", hlsl: try RuntimeCompilerSupport.appShaderSource(), target: .spirv)
        let json = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: GPUTestSupport.compiledShaders.appendingPathComponent("append.comp.json"))) as? [String: Any])
        func n(_ key: String) -> Int { json[key] as? Int ?? 0 }
        #expect(blob.samplers == n("samplers") && blob.readOnlyStorageTextures == n("readonly_storage_textures"))
        #expect(blob.readOnlyStorageBuffers == n("readonly_storage_buffers"))
        #expect(blob.readWriteStorageTextures == n("readwrite_storage_textures"))
        #expect(blob.readWriteStorageBuffers == n("readwrite_storage_buffers") && blob.readWriteStorageBuffers == 1)
        #expect(blob.uniformBuffers == n("uniform_buffers") && blob.uniformBuffers == 1)
        #expect(blob.threadCount.x == n("threadcount_x") && blob.threadCount.y == n("threadcount_y") && blob.threadCount.z == n("threadcount_z"))
        #expect(blob.format == SDLGPUShaderBlob.Format.spirv.rawValue && blob.entryPoint == "main" && blob.stage == .compute)
        #expect(Array(blob.bytes.prefix(4)) == [0x03, 0x02, 0x23, 0x07])
        let scale = try compiler.compileCompute(name: "scale", hlsl: RuntimeCompilerSupport.scaleKernel,
                                                defines: [SDLGPUShaderDefine("K", "2")], target: .spirv)
        #expect(scale.readOnlyStorageBuffers == 1 && scale.readWriteStorageBuffers == 1 && scale.uniformBuffers == 1)
        #expect(scale.threadCount.x == 64 && scale.threadCount.y == 1 && scale.threadCount.z == 1)
        let msl = try compiler.compileCompute(name: "scale", hlsl: RuntimeCompilerSupport.scaleKernel,
                                              defines: [SDLGPUShaderDefine("K", "2")], target: .msl)
        #expect(msl.entryPoint == "main0" && msl.format == SDLGPUShaderBlob.Format.msl.rawValue)
        #expect(String(decoding: msl.bytes, as: UTF8.self).contains("main0"))
        #expect(msl.readWriteStorageBuffers == 1 && msl.threadCount.x == 64)
    }

    /// **19.** The run-time compile of the checked-in app shader gives the build tool's bytes
    /// (`METALUI_SHADERCROSS_AT_PIN=1`: the library is the pin the blobs were built with; SPIR-V,
    /// MSL and DXIL), otherwise the entry points and reflection only.
    /// Mutation: the entry point passed to the C shim is hard-coded `"mainx"`.
    @Test(.enabled(if: RuntimeCompilerSupport.available, needsCompiler))
    func aRuntimeCompileOfTheAppShadersMatchesTheBuildToolsBlobs() throws {
        let compiler = try SDLGPUShaderCompiler.shared()
        let source = try RuntimeCompilerSupport.appShaderSource()
        for (target, ext, entry) in [(SDLGPUShaderTarget.spirv, "spv", "main"), (.msl, "msl", "main0"), (.dxil, "dxil", "main")] {
            let blob = try compiler.compileCompute(name: "append", hlsl: source, target: target)
            #expect(blob.entryPoint == entry, "\(ext)")
            #expect(blob.readWriteStorageBuffers == 1 && blob.uniformBuffers == 1 && blob.threadCount.x == 64, "\(ext)")
            if RuntimeCompilerSupport.atPin {
                let expected = [UInt8](try Data(contentsOf: GPUTestSupport.compiledShaders.appendingPathComponent("append.comp.\(ext)")))
                #expect(blob.bytes == expected, "\(ext): \(blob.bytes.count) bytes against the build tool's \(expected.count)")
            }
        }
    }

    /// **20.** A syntax error throws `compileFailed` naming the stage and carrying DXC's own text,
    /// with its line, never a crash. Mutation: the C shim never reads `SDL_GetError`.
    @Test(.enabled(if: RuntimeCompilerSupport.available, needsCompiler))
    func aSyntaxErrorThrowsCompileFailedWithDXCsText() throws {
        let compiler = try SDLGPUShaderCompiler.shared()
        do {
            _ = try compiler.compileCompute(name: "bad", hlsl: "[numthreads(1,1,1)] void main( { }\n", target: .spirv)
            Issue.record("a syntax error compiled")
        } catch SDLGPUShaderCompileError.compileFailed(let stage, let diagnostics) {
            #expect(stage == "HLSL to SPIR-V")
            #expect(diagnostics.contains("HLSL compilation failed"), "\(diagnostics)")
            #expect(diagnostics.contains(":1:"), "a line number: \(diagnostics)")
        }
        do {
            _ = try compiler.compileCompute(name: "bad", hlsl: "[numthreads(1,1,1)] void main( { }\n", target: .dxil)
            Issue.record("a syntax error compiled to DXIL")
        } catch SDLGPUShaderCompileError.compileFailed(let stage, _) {
            #expect(stage == "HLSL to SPIR-V" || stage == "HLSL to DXIL")
        }
        #expect(throws: SDLGPUShaderCompileError.self) {
            try compiler.compileCompute(name: "empty", hlsl: "", target: .spirv)
        }
        #expect(throws: SDLGPUShaderCompileError.self) {
            try compiler.compileCompute(name: "entry", hlsl: RuntimeCompilerSupport.scaleKernel, entryPoint: "no such",
                                        defines: [SDLGPUShaderDefine("K", "1")], target: .spirv)
        }
    }

    /// **21.** A compiled kernel dispatches on this device and reads back: 256 words times K.
    /// macOS Metal runs the MSL route, the Linux image's lavapipe the SPIR-V one.
    /// Mutation: the MSL route reports thread count 1 (the dispatch then covers 1/64 of the words).
    @Test(.enabled(if: RuntimeCompilerSupport.available && GPUTestSupport.available, needsCompiler))
    func aCompiledKernelDispatchesAndReadsBack() async throws {
        let device = try GPUTestSupport.requireDevice()
        let result = try await dispatchScale(on: device, factor: 3)
        #expect(result == (0..<256).map { UInt32($0) * 3 })
    }

    /// **22.** A define changes the compiled kernel: K=3 and K=5 read back different words.
    /// Mutation: the C shim ignores the defines.
    @Test(.enabled(if: RuntimeCompilerSupport.available && GPUTestSupport.available, needsCompiler))
    func definesChangeTheCompiledKernel() async throws {
        let device = try GPUTestSupport.requireDevice()
        let three = try await dispatchScale(on: device, factor: 3)
        let five = try await dispatchScale(on: device, factor: 5)
        #expect(three[7] == 21 && five[7] == 35)
        #expect(three != five)
    }

    /// **23.** The library is loaded once per process however many calls and threads reach
    /// `shared()` (`mui_sc_loads` counts the process cache's loads). Mutation: `shared()` loads per call.
    @Test(.enabled(if: RuntimeCompilerSupport.available, needsCompiler))
    func aSecondSharedCallReusesTheFirstLoad() async throws {
        let first = try SDLGPUShaderCompiler.shared()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { for _ in 0..<5 { _ = try? SDLGPUShaderCompiler.shared() } } }
        }
        let again = try SDLGPUShaderCompiler.shared()
        #expect(again.libraryPath == first.libraryPath)
        #expect(mui_sc_loads() == 1, "loads: \(mui_sc_loads())")
        // A different explicit path after the load is a named error, not a silent ignore or a reload (RC-O).
        do {
            _ = try SDLGPUShaderCompiler.shared(libraryPath: first.libraryPath + ".other")
            Issue.record("a different path was accepted after the load")
        } catch SDLGPUShaderCompileError.libraryAlreadyLoaded(let loaded, let requested) {
            #expect(loaded == first.libraryPath && requested == first.libraryPath + ".other")
        }
        #expect(try SDLGPUShaderCompiler.shared(libraryPath: first.libraryPath).libraryPath == first.libraryPath)
        #expect(mui_sc_loads() == 1)
    }

    /// **24.** Eight threads compile different kernels at once (`-DK=<i>`); each result equals that
    /// kernel's serial compile (`RC-S`: identical kernels could not see a shared output buffer).
    /// Mutation: one static output buffer in the C shim.
    @Test(.enabled(if: RuntimeCompilerSupport.available, needsCompiler))
    func eightThreadsCompileDifferentKernelsToTheirOwnSerialBytes() throws {
        let compiler = try SDLGPUShaderCompiler.shared()
        let compile: @Sendable (Int) throws -> [UInt8] = { k in
            try compiler.compileCompute(name: "k\(k)", hlsl: RuntimeCompilerSupport.scaleKernel,
                                        defines: [SDLGPUShaderDefine("K", String(k + 2))], target: .spirv).bytes
        }
        let serial = try (0..<8).map { try compile($0) }
        #expect(Set(serial).count == 8, "the eight kernels differ")
        let results = Results(count: 8)
        DispatchQueue.concurrentPerform(iterations: 8) { index in
            var ok = true
            for _ in 0..<3 { if (try? compile(index)) != serial[index] { ok = false } }
            results.set(index, ok)
        }
        #expect(results.values == Array(repeating: true, count: 8))
    }

    /// **25.** The self test names the driver, the format and the library; and it fails when the
    /// diagnostics of a broken kernel come back empty (a second SDL instance, `RC-D`).
    /// Mutation: the broken-kernel arm is skipped.
    @Test(.enabled(if: RuntimeCompilerSupport.available && GPUTestSupport.available, needsCompiler))
    func selfTestNamesTheDriverTheFormatAndTheLibrary() async throws {
        let device = try GPUTestSupport.requireDevice()
        let report = try await SDLGPUShaderCompiler.selfTest(for: device)
        #expect(report.driver == device.driver)
        let format = try SDLGPUShaderTarget(driver: device.driver)
        #expect(report.format == "\(format)")
        #expect(report.libraryPath == (try SDLGPUShaderCompiler.shared()).libraryPath)
        #expect(report.compiledBytes > 0 && report.seconds >= 0)
        let headless = try await SDLGPUShaderCompiler.selfTest(for: nil)
        #expect(headless.driver == "none" && headless.format == "spirv")
    }

    @Test(.enabled(if: RuntimeCompilerSupport.available, needsCompiler))
    func selfTestFailsWhenTheDiagnosticsAreEmpty() async throws {
        mui_sc_test_empty_diagnostics(true)
        defer { mui_sc_test_empty_diagnostics(false) }
        do {
            _ = try await SDLGPUShaderCompiler.selfTest(for: nil)
            Issue.record("the self test passed with empty diagnostics")
        } catch SDLGPUShaderCompileError.compileFailed(_, let diagnostics) {
            #expect(diagnostics.contains("no message") || diagnostics.contains("empty"), "\(diagnostics)")
        }
    }

    /// **26.** Kernels of about 200 and 1000 lines compile (always counted; the timings are
    /// `runtime-compile-measure.sh`'s, never asserted here). Mutation: none (an instrument).
    @Test(.enabled(if: RuntimeCompilerSupport.available, needsCompiler))
    func aKernelOf200And1000LinesCompiles() throws {
        let compiler = try SDLGPUShaderCompiler.shared()
        for lines in [200, 1000] {
            let source = RuntimeCompilerSupport.generated(lines: lines)
            #expect(source.split(separator: "\n").count >= lines - 2)
            let blob = try compiler.compileCompute(name: "gen\(lines)", hlsl: source, target: .spirv)
            #expect(blob.bytes.count > lines * 10, "\(lines) lines gave \(blob.bytes.count) bytes")
            #expect(blob.readWriteStorageBuffers == 1 && blob.threadCount.x == 64)
        }
    }

    /// **27.** A kernel that only warns (an unused variable) still compiles.
    /// Mutation: the C shim treats a non-empty `SDL_GetError` after a success as failure.
    @Test(.enabled(if: RuntimeCompilerSupport.available, needsCompiler))
    func aWarningOnlyKernelStillCompiles() throws {
        let compiler = try SDLGPUShaderCompiler.shared()
        let source = "RWStructuredBuffer<uint> dst : register(u0, space1);\n[numthreads(8,1,1)]\nvoid main(uint3 id : SV_DispatchThreadID) { float unused = 1.0; uint dead; dst[id.x] = id.x; }\n"
        let blob = try compiler.compileCompute(name: "warn", hlsl: source, target: .spirv)
        #expect(blob.threadCount.x == 8 && blob.readWriteStorageBuffers == 1)
    }

    /// Compiles the control kernel for `device` with `K = factor`, dispatches it over 256 words
    /// 0...255 and returns what the kernel wrote.
    private func dispatchScale(on device: SDLGPUDevice, factor: Int) async throws -> [UInt32] {
        let compiler = try SDLGPUShaderCompiler.shared()
        let blob = try compiler.compileCompute(name: "scale", hlsl: RuntimeCompilerSupport.scaleKernel,
                                               defines: [SDLGPUShaderDefine("K", String(factor))],
                                               for: device)
        let pipeline = try device.compileComputePipeline(blob)
        let words = 256
        let src = try #require(device.makeBuffer(size: words * 4, usage: [.computeStorageRead]))
        let dst = try #require(device.makeBuffer(size: words * 4, usage: [.computeStorageWrite]))
        try #require(await device.upload(GPUTestSupport.bytes(of: (0..<UInt32(words)).map { $0 }), to: src))
        try #require(await device.upload([UInt8](repeating: 0, count: words * 4), to: dst))
        let fence = try await device.submitBatch { commandBuffer in
            guard let pass = commandBuffer.beginComputePass(readWrite: [dst]) else { return }
            pass.bind(pipeline)
            pass.bind(readOnly: [src])
            pass.push(uniform: GPUTestSupport.bytes(of: [UInt32(words), 0, 0, 0]), at: 0)
            pass.dispatch(x: words / 64, y: 1, z: 1)
            pass.end()
        }
        await fence.wait()
        let bytes = try #require(await device.download(dst, range: 0..<(words * 4)))
        return GPUTestSupport.words(from: bytes)
    }
}

/// A lock-guarded array a concurrent loop writes by index.
private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool]
    init(count: Int) { storage = Array(repeating: false, count: count) }
    func set(_ index: Int, _ value: Bool) { lock.lock(); storage[index] = value; lock.unlock() }
    var values: [Bool] { lock.lock(); defer { lock.unlock() }; return storage }
}
