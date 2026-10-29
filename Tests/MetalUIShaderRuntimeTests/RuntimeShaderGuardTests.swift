import Foundation
import Testing
import MetalUITestSupport

// Test 7 (`HX-G`, `HX-I`): the public API compiles from a plain import and the loader does not.
// Four typecheck guards: one positive fixture, three separating ones.

private let canCheck = canTypecheck(module: "MetalUIShaderRuntime")
private let guardSkip = Comment(rawValue: "needs .build/<triple>/debug/Modules (the native build system)")

private let publicSurface = """
    public func spell() throws {
        let compiler = try RuntimeShaderCompiler.shared(libraryPath: nil)
        _ = RuntimeShaderCompiler.isAvailable
        _ = compiler.libraryPath
        let define: RuntimeShaderDefine = try RuntimeShaderDefine("K", "1")
        _ = (define.name, define.value)
        let out: CompiledComputeShader = try compiler.compileCompute(
            hlsl: "", entryPoint: "main", defines: [define], includeDirectory: nil, target: .spirv)
        _ = (out.target, out.bytes, out.entryPoint)
        let r: ComputeShaderReflection = out.reflection
        _ = (r.samplers, r.readOnlyStorageTextures, r.readOnlyStorageBuffers, r.readWriteStorageTextures,
             r.readWriteStorageBuffers, r.uniformBuffers, r.threadCountX, r.threadCountY, r.threadCountZ)
        let report: RuntimeShaderSelfTestReport = try compiler.selfTest(target: .msl)
        _ = (report.libraryPath, report.target, report.compiledBytes, report.entryPoint, report.seconds, report.notes)
        _ = try RuntimeShaderCompiler.selfTest(target: .dxil, libraryPath: nil)
        _ = try RuntimeShaderTarget(driver: "vulkan")
        _ = RuntimeShaderTarget.allCases
        let targets: [RuntimeShaderTarget] = [.spirv, .msl, .dxil]
        _ = targets
    }
    public func map(_ error: RuntimeShaderCompileError) {
        switch error {
        case .compilerUnavailable, .libraryAlreadyLoaded, .invalidInput, .unsupportedTarget, .compileFailed, .malformedReflection: break
        }
        _ = error.description
    }
    """

@Test(.enabled(if: canCheck, guardSkip))
func theRuntimeAPIIsPublicAndTheLoaderIsNot() throws {
    let positive = try typecheckFile(publicSurface, importing: "MetalUIShaderRuntime")
    print("HX GUARD G1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let load = try typecheckFile("public func b() throws { _ = try RuntimeShaderCompiler.load(candidates: []) }",
                                 importing: "MetalUIShaderRuntime")
    print("HX GUARD G2 load(candidates:): succeeded=\(load.succeeded)")
    let cache = try typecheckFile("public func c() { _ = RuntimeShaderCompiler.ProcessCache.current }",
                                  importing: "MetalUIShaderRuntime")
    print("HX GUARD G3 ProcessCache: succeeded=\(cache.succeeded)")
    let cModule = try typecheckFile("public func d() { _ = mui_rsc_loads() }", importing: "MetalUIShaderRuntime")
    print("HX GUARD G4 C module: succeeded=\(cModule.succeeded)")
    try #require(positive.succeeded, "every public spelling must compile from a plain import:\n\(positive.output)")
    #expect(!load.succeeded, "`load(candidates:)` is package, not public:\n\(load.output)")
    #expect(!cache.succeeded, "`ProcessCache` is package, not public:\n\(cache.output)")
    #expect(!cModule.succeeded, "the C module is an internal import:\n\(cModule.output)")
}
