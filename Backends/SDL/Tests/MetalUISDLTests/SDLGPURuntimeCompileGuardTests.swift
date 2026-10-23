import Foundation
import Testing
import MetalUISDLGPU   // a plain import, never @testable: this file proves what an app can write (RC-P)

// Guard (RC-P, spec 5): a root typecheck fixture cannot name `MetalUISDLGPU` (it exists only under
// the `SDL` trait), so the compile-time proof is this file's plain import, and the source scan
// below proves the lookup, the validation and the C shim are not public.

@Suite struct SDLGPURuntimeCompileGuardTests {
    /// Every public entry compiles from outside the module. Mutation: the bytes initializer becomes
    /// `internal` (this file stops compiling: a build failure, then reverted).
    @Test func theRuntimeCompileSurfaceIsPublic() async throws {
        func spell() async throws {
            let compiler = try SDLGPUShaderCompiler.shared(libraryPath: nil)
            _ = SDLGPUShaderCompiler.isAvailable
            _ = compiler.libraryPath
            _ = try compiler.compileCompute(name: "k", hlsl: "", entryPoint: "main",
                                            defines: [try SDLGPUShaderDefine("K", "1")], includeDirectory: nil, target: .spirv)
            _ = try await SDLGPUShaderCompiler.selfTest(for: nil)
            _ = try await compiler.selfTest(for: nil)
            _ = try SDLGPUShaderBlob(name: "k", stage: .compute, bytes: [], format: .spirv, entryPoint: "main",
                                     samplers: 0, readOnlyStorageTextures: 0, readOnlyStorageBuffers: 0,
                                     readWriteStorageTextures: 0, readWriteStorageBuffers: 0, uniformBuffers: 0,
                                     threadCount: (1, 1, 1))
            _ = try SDLGPUShaderTarget(driver: "vulkan")
            _ = SDLGPUShaderBlob.Format(driver: "metal")
        }
        _ = spell   // compiled, never run
        _ = { (device: SDLGPUDevice) throws -> SDLGPUComputePipeline in
            try device.compileComputePipeline(hlsl: "", name: "k", entryPoint: "main", defines: [])
        }
        _ = { (device: SDLGPUDevice, compiler: SDLGPUShaderCompiler) throws -> SDLGPUShaderBlob in
            try compiler.compileCompute(name: "k", hlsl: "", for: device)
        }
        _ = { (error: SDLGPUShaderCompileError) in
            switch error {
            case .compilerUnavailable, .libraryAlreadyLoaded, .invalidInput, .unsupportedTarget, .compileFailed, .malformedReflection: break
            }
        }
    }

    /// The lookup, the validation and every C entry stay `package` or internal. Mutation: make
    /// `RuntimeLibraryLocator` public (this scan reddens).
    @Test func theLocatorTheValidationAndTheCShimAreNotPublic() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")
        let files = ["MetalUIShaderCompile/RuntimeLibraryLocator.swift", "MetalUIShaderCompile/ComputeBlobValidation.swift",
                     "MetalUISDLGPU/SDLGPUShaderCompiler.swift", "MetalUISDLGPU/SDLGPUShaderBlob+Bytes.swift",
                     "MetalUISDLGPU/SDLGPUDevice+RuntimeCompile.swift"]
        // `\.isNewline`, never `"\n"`: a CRLF checkout (Windows) makes "\r\n" one Character.
        var text: [String: String] = [:]
        for file in files { text[file] = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8) }
        for file in ["MetalUIShaderCompile/RuntimeLibraryLocator.swift", "MetalUIShaderCompile/ComputeBlobValidation.swift"] {
            let lines = try #require(text[file]).split(whereSeparator: \.isNewline).map(String.init)
            for line in lines where line.contains("public ") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                Issue.record("\(file) declares public API: \(line)")
            }
        }
        // `mui_sc_*` is spelled only by the compiler's own file, never from a public signature.
        for (file, body) in text where file != "MetalUISDLGPU/SDLGPUShaderCompiler.swift" {
            #expect(!body.contains("mui_sc_"), "\(file) reaches the C shim")
        }
        let compiler = try #require(text["MetalUISDLGPU/SDLGPUShaderCompiler.swift"])
        for line in compiler.split(whereSeparator: \.isNewline) where line.contains("public") && line.contains("MuiShaderCross") {
            Issue.record("a public signature names the C handle: \(line)")
        }
        // The process cache and the loading seam are package, not public.
        for needle in ["public final class ProcessCache", "public static func load(candidates", "public static func withProcessCache"] {
            #expect(!compiler.contains(needle), Comment(rawValue: needle))
        }
    }
}
