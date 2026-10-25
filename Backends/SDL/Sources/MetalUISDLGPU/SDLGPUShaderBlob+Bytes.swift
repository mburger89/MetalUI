// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation
import MetalUIShaderCompile

extension SDLGPUShaderBlob {
    /// The shader format of a blob's bytes (item XP-G25, `RC-E`). The raw value is the
    /// `SDL_GPUShaderFormat` bit, converted explicitly (a C enum's raw type differs by platform).
    public enum Format: Sendable, Equatable {
        /// SPIR-V (Vulkan).
        case spirv
        /// Metal Shading Language source (SDL's Metal driver).
        case msl
        /// DXIL (Direct3D 12).
        case dxil

        /// The `SDL_GPUShaderFormat` bit.
        public var rawValue: UInt32 {
            switch self {
            case .spirv: return UInt32(SDL_GPU_SHADERFORMAT_SPIRV)
            case .msl: return UInt32(SDL_GPU_SHADERFORMAT_MSL)
            case .dxil: return UInt32(SDL_GPU_SHADERFORMAT_DXIL)
            }
        }

        /// The format `driver` (`vulkan`, `metal`, `direct3d12`) takes, or `nil` for any other.
        public init?(driver: String) {
            switch driver {
            case "vulkan": self = .spirv
            case "metal": self = .msl
            case "direct3d12": self = .dxil
            default: return nil
            }
        }
    }

    /// A compute blob from bytes at run time (`RC-E`): the bytes of a cached compile, or what
    /// ``SDLGPUShaderCompiler`` returned, with the counts SDL's pipeline description needs. Checked
    /// before SDL sees it, with no device: non-empty bytes and entry point, SPIR-V's magic and whole
    /// words, DXIL's `DXBC` container, MSL text holding its entry point, every thread axis at least 1
    /// with `x * y * z <= 1024`, and every count in `0...64` (a sanity bound; SDL's own refusal
    /// still throws from ``SDLGPUDevice/compileComputePipeline(_:)`` naming the stage). Only compute
    /// is built (`RC-G`). Throws ``SDLGPUShaderCompileError/invalidInput(_:)`` or
    /// ``SDLGPUShaderCompileError/malformedReflection(_:)``.
    public init(name: String, stage: Stage, bytes: [UInt8], format: Format, entryPoint: String,
                samplers: Int = 0, readOnlyStorageTextures: Int = 0, readOnlyStorageBuffers: Int = 0,
                readWriteStorageTextures: Int = 0, readWriteStorageBuffers: Int = 0, uniformBuffers: Int = 0,
                threadCount: (x: Int, y: Int, z: Int)) throws {
        let blobFormat: ComputeBlobFormat
        switch format {
        case .spirv: blobFormat = .spirv
        case .msl: blobFormat = .msl
        case .dxil: blobFormat = .dxil
        }
        let blobStage: ComputeBlobStage
        switch stage {
        case .vertex: blobStage = .vertex
        case .fragment: blobStage = .fragment
        case .compute: blobStage = .compute
        }
        do {
            try ComputeBlobValidation.validate(
                bytes: bytes, format: blobFormat, entryPoint: entryPoint, stage: blobStage,
                reflection: ComputeReflection(
                    samplers: samplers, readOnlyStorageTextures: readOnlyStorageTextures,
                    readOnlyStorageBuffers: readOnlyStorageBuffers, readWriteStorageTextures: readWriteStorageTextures,
                    readWriteStorageBuffers: readWriteStorageBuffers, uniformBuffers: uniformBuffers, threadCount: threadCount))
        } catch let error as ComputeValidationError { throw SDLGPUShaderCompileError(error) }
        self.init(name: name, stage: stage, bytes: bytes, format: format.rawValue, entryPoint: entryPoint,
                  samplers: samplers, readOnlyStorageTextures: readOnlyStorageTextures,
                  readOnlyStorageBuffers: readOnlyStorageBuffers, readWriteStorageTextures: readWriteStorageTextures,
                  readWriteStorageBuffers: readWriteStorageBuffers, uniformBuffers: uniformBuffers, threadCount: threadCount)
    }
}
#endif
