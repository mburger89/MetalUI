import Foundation
import Testing
import MetalUISDLGPU
@testable import MetalUISDLGPU

// Run-time HLSL compute compile (item XP-G25, rulings RC-B..RC-S; spec 5 tests 13-17). These
// run everywhere: no library, and (except 15) no GPU. The gated tests 18-27 are the same suite
// in `SDLGPURuntimeCompilerGatedTests.swift`: **one serialized suite**, because the process
// cache is global and a test that swaps it must not overlap one that reads it.

/// Attempts naming files that do not exist, plus one bare loader name no machine has, so a
/// real `load(candidates:)` runs the whole path with no library on the loader path.
func missingLibraryAttempts() -> [SDLGPUShaderCompiler.LibraryAttempt] {
    var attempts = SDLGPUShaderCompiler.libraryAttempts(
        explicit: nil, environment: ["METALUI_SHADERCROSS": "/nonexistent/tool/bin/shadercross"],
        executableDirectory: "/nonexistent/app/bin", windows: false, macOS: true,
        fileExists: { _ in false }, directoryExists: { _ in false }).filter { !$0.isLoaderName }
    attempts.append(.loaderName("libmui_no_such_shadercross.dylib"))
    return attempts
}

@MainActor @Suite(.serialized) struct SDLGPURuntimeCompilerTests {
    /// **13.** A missing library is a thrown `compilerUnavailable` that lists every path tried with
    /// its reason (a file that does not exist, a loader name the loader refused), never a trap.
    /// Through the `package` seam, which never touches the process cache (`RC-O`).
    /// Mutation: `load(candidates:)` reports an empty `tried` list.
    @Test func aMissingLibraryThrowsCompilerUnavailableListingEveryPathTried() throws {
        let attempts = missingLibraryAttempts()
        #expect(attempts.count >= 4)
        do {
            _ = try SDLGPUShaderCompiler.load(candidates: attempts)
            Issue.record("a missing library loaded")
        } catch SDLGPUShaderCompileError.compilerUnavailable(let tried) {
            #expect(tried.count == attempts.count, "one line per attempt: \(tried)")
            for attempt in attempts {
                #expect(tried.contains { $0.hasPrefix(attempt.path + ":") }, "\(attempt.path) is named")
            }
            #expect(tried.contains { $0.contains("no such file") })
            #expect(tried.contains { $0.hasPrefix("libmui_no_such_shadercross.dylib:") && $0.contains("failed to load") },
                    "the loader's refusal is the reason: \(tried)")
        }
        // An explicit path naming a missing file is an error from the lookup, never a fall-through.
        let explicit = SDLGPUShaderCompiler.libraryAttempts(
            explicit: "/nonexistent/libSDL3_shadercross.dylib", environment: [:], executableDirectory: nil,
            windows: false, macOS: true, fileExists: { _ in false }, directoryExists: { _ in false })
        do {
            _ = try SDLGPUShaderCompiler.load(candidates: explicit)
            Issue.record("a missing explicit path loaded")
        } catch SDLGPUShaderCompileError.compilerUnavailable(let tried) {
            #expect(tried.count == 1 && tried[0].contains("/nonexistent/libSDL3_shadercross.dylib"))
        }
    }

    /// **14.** Every entry that needs the compiler throws the one named error without it: `shared`,
    /// `isAvailable` (false, no throw), the static self test and the device form. Over a process
    /// cache that finds nothing, swapped in by the `package` seam.
    /// Mutation: the static `selfTest` skips its `shared()` check and answers a report.
    @Test func everyCompileEntryThrowsCompilerUnavailableWithoutTheLibrary() async throws {
        let cache = SDLGPUShaderCompiler.ProcessCache(attempts: { _ in missingLibraryAttempts() })
        let device = SDLGPUDevice.make()
        var failures: [String] = []
        await SDLGPUShaderCompiler.withProcessCache(cache) {
            func record(_ entry: String, _ error: Error?) {
                guard let error else { failures.append("\(entry) did not throw"); return }
                guard case SDLGPUShaderCompileError.compilerUnavailable(let tried) = error, !tried.isEmpty else {
                    failures.append("\(entry) threw \(error)"); return
                }
            }
            do { _ = try SDLGPUShaderCompiler.shared(); record("shared()", nil) } catch { record("shared()", error) }
            if SDLGPUShaderCompiler.isAvailable { failures.append("isAvailable is true") }
            do { _ = try await SDLGPUShaderCompiler.selfTest(for: nil); record("selfTest(for:)", nil) }
            catch { record("selfTest(for:)", error) }
            if let device {
                do { _ = try device.compileComputePipeline(hlsl: "[numthreads(1,1,1)] void main() {}", name: "k")
                    record("device.compileComputePipeline(hlsl:)", nil) }
                catch { record("device.compileComputePipeline(hlsl:)", error) }
            }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    /// **15.** The bytes initializer makes a pipeline from the checked-in app shader's bytes and
    /// reflection JSON, for this device's driver.
    /// Mutation: the initializer stores `threadCount.y` into `z`.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func theBlobInitializerMakesAPipelineFromTheCheckedInAppShaderBytes() throws {
        let device = try GPUTestSupport.requireDevice()
        let format = try #require(SDLGPUShaderBlob.Format(driver: device.driver))
        let (ext, entry) = format == .msl ? ("msl", "main0") : (format == .dxil ? ("dxil", "main") : ("spv", "main"))
        let bytes = [UInt8](try Data(contentsOf: GPUTestSupport.compiledShaders.appendingPathComponent("append.comp.\(ext)")))
        let json = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: GPUTestSupport.compiledShaders.appendingPathComponent("append.comp.json"))) as? [String: Any])
        func n(_ key: String) -> Int { json[key] as? Int ?? 0 }
        let blob = try SDLGPUShaderBlob(
            name: "append.comp", stage: .compute, bytes: bytes, format: format, entryPoint: entry,
            samplers: n("samplers"), readOnlyStorageTextures: n("readonly_storage_textures"),
            readOnlyStorageBuffers: n("readonly_storage_buffers"), readWriteStorageTextures: n("readwrite_storage_textures"),
            readWriteStorageBuffers: n("readwrite_storage_buffers"), uniformBuffers: n("uniform_buffers"),
            threadCount: (n("threadcount_x"), n("threadcount_y"), n("threadcount_z")))
        _ = try device.compileComputePipeline(blob)
    }

    /// **16.** A malformed reflection throws from the initializer itself, which takes no device, so
    /// SDL is never reached; each refusal names its field.
    /// Mutation: the initializer skips `ComputeBlobValidation.validate(_:)`.
    @Test func aMalformedReflectionThrowsBeforeSDLIsCalled() {
        let spirv: [UInt8] = [0x03, 0x02, 0x23, 0x07, 0, 0, 0, 0]
        func make(uniforms: Int = 1, threads: (x: Int, y: Int, z: Int) = (64, 1, 1)) throws -> SDLGPUShaderBlob {
            try SDLGPUShaderBlob(name: "k", stage: .compute, bytes: spirv, format: .spirv, entryPoint: "main",
                                 uniformBuffers: uniforms, threadCount: threads)
        }
        #expect(throws: Never.self) { try make() }
        for (arm, build, field) in [("threads.y 0", { try make(threads: (64, 0, 1)) }, "threadCount.y"),
                                    ("65 uniforms", { try make(uniforms: 65) }, "uniformBuffers"),
                                    ("2048 invocations", { try make(threads: (64, 32, 1)) }, "1024")] as [(String, () throws -> SDLGPUShaderBlob, String)] {
            do { _ = try build(); Issue.record("\(arm) was accepted") }
            catch SDLGPUShaderCompileError.malformedReflection(let text) { #expect(text.contains(field), "\(arm): \(text)") }
            catch { Issue.record("\(arm) threw \(error)") }
        }
        do { _ = try SDLGPUShaderBlob(name: "k", stage: .compute, bytes: [1, 2, 3, 4], format: .spirv, entryPoint: "main",
                                      threadCount: (1, 1, 1)); Issue.record("bad magic accepted") }
        catch SDLGPUShaderCompileError.invalidInput(let text) { #expect(text.contains("magic")) }
        catch { Issue.record("bad magic threw \(error)") }
        do { _ = try SDLGPUShaderBlob(name: "k", stage: .vertex, bytes: spirv, format: .spirv, entryPoint: "main",
                                      threadCount: (1, 1, 1)); Issue.record("a vertex stage was accepted") }
        catch SDLGPUShaderCompileError.invalidInput(let text) { #expect(text.contains("compute")) }
        catch { Issue.record("vertex threw \(error)") }
    }

    /// **17.** The blob keeps every count it was given in the field `compileComputePipeline` reads,
    /// and the format's raw value is the `SDL_GPUShaderFormat` bit.
    /// Mutation: the initializer swaps the read-only and read-write buffer counts.
    @Test func theBlobInitializerKeepsEveryCountItWasGiven() throws {
        let blob = try SDLGPUShaderBlob(
            name: "counts", stage: .compute, bytes: [0x03, 0x02, 0x23, 0x07], format: .spirv, entryPoint: "main",
            samplers: 1, readOnlyStorageTextures: 2, readOnlyStorageBuffers: 3, readWriteStorageTextures: 4,
            readWriteStorageBuffers: 5, uniformBuffers: 6, threadCount: (7, 8, 9))
        #expect(blob.samplers == 1 && blob.readOnlyStorageTextures == 2 && blob.readOnlyStorageBuffers == 3)
        #expect(blob.readWriteStorageTextures == 4 && blob.readWriteStorageBuffers == 5 && blob.uniformBuffers == 6)
        #expect(blob.threadCount.x == 7 && blob.threadCount.y == 8 && blob.threadCount.z == 9)
        #expect(blob.name == "counts" && blob.entryPoint == "main" && blob.stage == .compute)
        #expect(blob.format == UInt32(SDL_GPU_SHADERFORMAT_SPIRV))
        #expect(SDLGPUShaderBlob.Format.spirv.rawValue == UInt32(SDL_GPU_SHADERFORMAT_SPIRV))
        #expect(SDLGPUShaderBlob.Format.msl.rawValue == UInt32(SDL_GPU_SHADERFORMAT_MSL))
        #expect(SDLGPUShaderBlob.Format.dxil.rawValue == UInt32(SDL_GPU_SHADERFORMAT_DXIL))
    }

    /// Targets: a driver maps to its format and any other is unsupported, naming it (`RC-F`).
    /// Mutation: `metal` maps to SPIR-V.
    @Test func aDriverMapsToItsTargetAndAnyOtherIsUnsupportedNamingIt() throws {
        #expect(try SDLGPUShaderTarget(driver: "vulkan") == .spirv)
        #expect(try SDLGPUShaderTarget(driver: "metal") == .msl)
        #expect(try SDLGPUShaderTarget(driver: "direct3d12") == .dxil)
        do { _ = try SDLGPUShaderTarget(driver: "private"); Issue.record("private accepted") }
        catch SDLGPUShaderCompileError.unsupportedTarget(let text) { #expect(text.contains("private")) }
    }

    /// A define's name is an identifier and no value holds a NUL; the errors print what they hold.
    /// Mutation: `SDLGPUShaderDefine.init` skips the check.
    @Test func aDefineIsValidatedWhenItIsMadeAndTheErrorsDescribeThemselves() throws {
        #expect(try SDLGPUShaderDefine("K", "3").name == "K")
        #expect(try SDLGPUShaderDefine("BARE").value == nil)
        #expect(throws: SDLGPUShaderCompileError.self) { try SDLGPUShaderDefine("1bad") }
        #expect(throws: SDLGPUShaderCompileError.self) { try SDLGPUShaderDefine("K", "a\0b") }
        let text = String(describing: SDLGPUShaderCompileError.compileFailed(stage: "HLSL to SPIR-V", diagnostics: "boom"))
        #expect(text.contains("HLSL to SPIR-V") && text.contains("boom"))
        #expect(String(describing: SDLGPUShaderCompileError.compilerUnavailable(tried: ["a: b"])).contains("a: b"))
        let again = String(describing: SDLGPUShaderCompileError.libraryAlreadyLoaded(loaded: "/x", requested: "/y"))
        #expect(again.contains("/x") && again.contains("/y"))
    }
}
