import Foundation
import MetalUIShaderCompile

/// Why a run-time shader compile was refused (rulings `RC-B`...`RC-J`, `HX-G`). The same six cases as
/// `SDLGPUShaderCompileError`, which maps one to one.
public enum RuntimeShaderCompileError: Error, CustomStringConvertible, Sendable, Equatable {
    /// The compiler library was not found or would not load: one `path: reason` line per place tried
    /// (lookup order `RC-C`, `SX-B`); a dependent or SDL3 the loader refused is named.
    case compilerUnavailable(tried: [String])
    /// An explicit library path differing from the one already loaded for the process (`RC-O`).
    case libraryAlreadyLoaded(loaded: String, requested: String)
    /// Empty source, a bad define or entry point, a NUL byte.
    case invalidInput(String)
    /// A driver name with no run-time compile format; the text names it.
    case unsupportedTarget(String)
    /// The compiler refused the source. `stage` is `"HLSL to SPIR-V"`, `"SPIR-V to MSL"`, `"SPIR-V reflection"`
    /// or `"HLSL to DXIL"`; `diagnostics` is DXC's own text with file, line and column.
    case compileFailed(stage: String, diagnostics: String)
    /// Reflection SDL_GPU could not be given; the text names the field.
    case malformedReflection(String)

    /// The refusal as text, the same wording as `SDLGPUShaderCompileError`'s.
    public var description: String {
        switch self {
        case .compilerUnavailable(let tried):
            return "shader compiler library not found; tried:\n" + tried.joined(separator: "\n")
        case .libraryAlreadyLoaded(let loaded, let requested):
            return "the shader compiler is already loaded from \(loaded); \(requested) was requested"
        case .invalidInput(let text), .unsupportedTarget(let text), .malformedReflection(let text): return text
        case .compileFailed(let stage, let diagnostics): return "\(stage) failed: \(diagnostics)"
        }
    }

    init(_ error: ComputeValidationError) {
        switch error {
        case .invalidInput(let text): self = .invalidInput(text)
        case .malformedReflection(let text): self = .malformedReflection(text)
        case .unsupportedTarget(let text): self = .unsupportedTarget(text)
        case .libraryMissing(let lines): self = .compilerUnavailable(tried: lines)
        }
    }
}

/// One `-D` define. The name must be an identifier and no part may hold a NUL.
public struct RuntimeShaderDefine: Sendable, Hashable {
    /// The macro name.
    public let name: String
    /// Its value, or `nil` for a bare `-DNAME`.
    public let value: String?

    /// Validates the define (`RuntimeShaderCompileError.invalidInput` names the problem).
    public init(_ name: String, _ value: String? = nil) throws {
        do { try ComputeBlobValidation.validateDefine(name: name, value: value) }
        catch let error as ComputeValidationError { throw RuntimeShaderCompileError(error) }
        self.name = name
        self.value = value
    }
}

/// The format a run-time compile produces.
public enum RuntimeShaderTarget: String, Sendable, Hashable, CaseIterable {
    /// SPIR-V (Vulkan, SDL_GPU's Vulkan driver).
    case spirv
    /// Metal Shading Language source, entry point `main0`, buffer slots in SDL_GPU's convention
    /// (`MTLDevice.makeLibrary(source:options:)` takes it on a Mac).
    case msl
    /// DXIL (Direct3D 12).
    case dxil

    /// The target of an SDL_GPU driver name (`vulkan`, `metal`, `direct3d12`); any other throws `unsupportedTarget`.
    public init(driver: String) throws {
        let format: ComputeBlobFormat
        do { format = try ComputeBlobValidation.target(forDriver: driver) }
        catch let error as ComputeValidationError { throw RuntimeShaderCompileError(error) }
        switch format {
        case .spirv: self = .spirv
        case .msl: self = .msl
        case .dxil: self = .dxil
        }
    }
}

/// The resource counts and thread group of a compute kernel, read from its SPIR-V (`RC-F`).
public struct ComputeShaderReflection: Sendable, Hashable {
    /// Sampled textures with a sampler.
    public let samplers: Int
    /// Read-only storage textures.
    public let readOnlyStorageTextures: Int
    /// Read-only storage buffers.
    public let readOnlyStorageBuffers: Int
    /// Read-write storage textures.
    public let readWriteStorageTextures: Int
    /// Read-write storage buffers.
    public let readWriteStorageBuffers: Int
    /// Uniform buffers.
    public let uniformBuffers: Int
    /// The thread group's x size.
    public let threadCountX: Int
    /// The thread group's y size.
    public let threadCountY: Int
    /// The thread group's z size.
    public let threadCountZ: Int
}

/// A compiled compute kernel: the target's bytes (MSL as UTF-8 text), its entry point in that format and its reflection.
public struct CompiledComputeShader: Sendable, Hashable {
    /// The format of `bytes`.
    public let target: RuntimeShaderTarget
    /// The compiled bytes (MSL is UTF-8 text without a NUL).
    public let bytes: [UInt8]
    /// The entry point in that format (`main0` for MSL).
    public let entryPoint: String
    /// The counts and thread group, always read from the SPIR-V.
    public let reflection: ComputeShaderReflection
}

/// What `RuntimeShaderCompiler.selfTest(target:)` found (`RC-J`).
public struct RuntimeShaderSelfTestReport: Sendable {
    /// The library that was loaded.
    public let libraryPath: String
    /// The compiled format.
    public let target: RuntimeShaderTarget
    /// The size of the compiled test kernel.
    public let compiledBytes: Int
    /// The test kernel's entry point in the compiled format.
    public let entryPoint: String
    /// Wall clock of the checks (a dated reading, never a pin).
    public let seconds: Double
    /// What the checks did, one line each.
    public let notes: [String]
}

extension ComputeShaderReflection {
    init(_ reflection: ComputeReflection) {
        self.init(samplers: reflection.samplers, readOnlyStorageTextures: reflection.readOnlyStorageTextures,
                  readOnlyStorageBuffers: reflection.readOnlyStorageBuffers,
                  readWriteStorageTextures: reflection.readWriteStorageTextures,
                  readWriteStorageBuffers: reflection.readWriteStorageBuffers, uniformBuffers: reflection.uniformBuffers,
                  threadCountX: reflection.threadCount.x, threadCountY: reflection.threadCount.y,
                  threadCountZ: reflection.threadCount.z)
    }
}

