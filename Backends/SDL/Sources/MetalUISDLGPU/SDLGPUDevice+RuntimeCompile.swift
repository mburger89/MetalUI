// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation

extension SDLGPUDevice {
    /// Compiles HLSL compute source for this device's driver with the process's shared compiler and
    /// builds the pipeline (item XP-G25): ``SDLGPUShaderCompiler/shared(libraryPath:)``, then
    /// ``SDLGPUShaderCompiler/compileCompute(name:hlsl:entryPoint:defines:includeDirectory:for:)``, then
    /// ``compileComputePipeline(_:)``. Throws ``SDLGPUShaderCompileError`` for a missing library or
    /// a refused source and ``SDLGPUError`` (naming the compute stage) when SDL refuses the pipeline
    /// (`GB-G`). **Call off the main actor**: a compile takes tenths of a second to seconds.
    public func compileComputePipeline(hlsl: String, name: String, entryPoint: String = "main",
                                       defines: [SDLGPUShaderDefine] = []) throws -> SDLGPUComputePipeline {
        let blob = try SDLGPUShaderCompiler.shared().compileCompute(
            name: name, hlsl: hlsl, entryPoint: entryPoint, defines: defines, for: self)
        return try compileComputePipeline(blob)
    }
}
#endif
