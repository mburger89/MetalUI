// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation
import MetalUIShaderCompile
import MetalUIShaderRuntime

/// Why a run-time shader compile or a blob from bytes was refused (rulings `RC-B`...`RC-J`).
public enum SDLGPUShaderCompileError: Error, CustomStringConvertible, Sendable {
    /// The compiler library was not found or would not load: one `path: reason` line per place tried
    /// (lookup order `RC-C`), and a dependent the loader refused is named.
    case compilerUnavailable(tried: [String])
    /// An explicit library path differing from the one already loaded for the process (`RC-O`):
    /// the argument is never silently ignored and the library never reloaded.
    case libraryAlreadyLoaded(loaded: String, requested: String)
    /// Empty source, a bad define or entry point, a NUL byte, bytes the format check refused, or a
    /// stage other than compute.
    case invalidInput(String)
    /// A GPU driver with no run-time compile format (`RC-F`); the text names it.
    case unsupportedTarget(String)
    /// The compiler refused the source. `stage` is `"HLSL to SPIR-V"`, `"SPIR-V to MSL"`,
    /// `"SPIR-V reflection"` or `"HLSL to DXIL"`; `diagnostics` is the compiler's own text (DXC's
    /// message, with file, line and column).
    case compileFailed(stage: String, diagnostics: String)
    /// Reflection or a blob's counts and thread group that SDL could not be given; the text names the field.
    case malformedReflection(String)

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

    init(_ error: RuntimeShaderCompileError) {
        switch error {
        case .compilerUnavailable(let tried): self = .compilerUnavailable(tried: tried)
        case .libraryAlreadyLoaded(let loaded, let requested): self = .libraryAlreadyLoaded(loaded: loaded, requested: requested)
        case .invalidInput(let text): self = .invalidInput(text)
        case .unsupportedTarget(let text): self = .unsupportedTarget(text)
        case .compileFailed(let stage, let diagnostics): self = .compileFailed(stage: stage, diagnostics: diagnostics)
        case .malformedReflection(let text): self = .malformedReflection(text)
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

/// One `-D` define of a run-time compile. The name must be an identifier and no part may hold a NUL.
public struct SDLGPUShaderDefine: Sendable, Hashable {
    /// The macro name.
    public let name: String
    /// Its value, or `nil` for a bare `-DNAME`.
    public let value: String?

    /// Validates the define (`SDLGPUShaderCompileError.invalidInput` names the problem).
    public init(_ name: String, _ value: String? = nil) throws {
        do { try ComputeBlobValidation.validateDefine(name: name, value: value) }
        catch let error as ComputeValidationError { throw SDLGPUShaderCompileError(error) }
        self.name = name
        self.value = value
    }
}

/// The format a run-time compile produces: what the device's driver takes (`RC-F`).
public enum SDLGPUShaderTarget: Sendable {
    /// SPIR-V, for Vulkan.
    case spirv
    /// Metal Shading Language source (entry point `main0`), for SDL's Metal driver.
    case msl
    /// DXIL, for Direct3D 12.
    case dxil

    /// The target of an `SDL_GetGPUDeviceDriver` name (`vulkan`, `metal`, `direct3d12`); any other
    /// driver throws ``SDLGPUShaderCompileError/unsupportedTarget(_:)`` naming it.
    public init(driver: String) throws {
        let format: ComputeBlobFormat
        do { format = try ComputeBlobValidation.target(forDriver: driver) }
        catch let error as ComputeValidationError { throw SDLGPUShaderCompileError(error) }
        switch format {
        case .spirv: self = .spirv
        case .msl: self = .msl
        case .dxil: self = .dxil
        }
    }
}

/// What ``SDLGPUShaderCompiler/selfTest(for:)`` found (`RC-J`).
public struct SDLGPUShaderCompilerReport: Sendable {
    /// The device's driver (`vulkan`, `metal`, `direct3d12`), or `"none"` without a device.
    public let driver: String
    /// The compiled format, spelled as ``SDLGPUShaderTarget``'s case (`spirv` when there is no device).
    public let format: String
    /// The library that was loaded.
    public let libraryPath: String
    /// The size of the compiled test kernel.
    public let compiledBytes: Int
    /// The test kernel's entry point in the compiled format.
    public let entryPoint: String
    /// Seconds the checks took, wall clock (a dated reading, never a pin).
    public let seconds: Double
    /// What the checks did, one line each.
    public let notes: [String]
}

/// The run-time HLSL compute compiler (item XP-G25, rulings `RC-B`...`RC-S`): HLSL text in, a
/// compute blob (bytes and reflection) or a pipeline out, in the running process, through
/// SDL_shadercross's shared library loaded with `SDL_LoadObject` at the first call. MetalUI links
/// none of it; an absent library is a thrown ``SDLGPUShaderCompileError/compilerUnavailable(tried:)``
/// listing every path tried (lookup order: the explicit `libraryPath:`, `METALUI_SHADERCROSS_LIB`,
/// beside the executable, its `lib` (`<exe>/lib`, `SX-B`) and its `../lib`, the `lib` beside `METALUI_SHADERCROSS`'s `bin`, then the
/// loader path; `docs/packaging.md` 4b).
///
/// Threads: every member is `nonisolated` and **compiles run concurrently** (the pinned
/// shadercross builds one DXC instance per call; `RC-D`). A compile takes tenths of a second to
/// seconds (a 1000-line kernel about half a second), so **call it off the main actor** and cache the
/// bytes (`RC-M`); this type never traps on a bad kernel. Compute only (`RC-G`).
public struct SDLGPUShaderCompiler: Sendable {
    /// What was loaded: the path of the shadercross library.
    public var libraryPath: String { runtime.libraryPath }
    /// The one implementation and the one process load (`HX-C`, `HX-E`).
    let runtime: RuntimeShaderCompiler

    // MARK: Loading

    /// The compiler for the process, loaded on first use and then reused (`RC-B`). `libraryPath`
    /// names the library explicitly (it ranks first, and a missing file is an error, never a
    /// fall-through); after a load, a *different* path throws ``SDLGPUShaderCompileError/libraryAlreadyLoaded(loaded:requested:)``.
    /// Throws ``SDLGPUShaderCompileError/compilerUnavailable(tried:)`` when nothing loads.
    public static func shared(libraryPath: String? = nil) throws -> SDLGPUShaderCompiler {
        try ProcessCache.current.resolve(explicit: libraryPath)
    }

    /// Whether ``shared(libraryPath:)`` succeeds with the default lookup. Never throws, never traps.
    public static var isAvailable: Bool { (try? shared()) != nil }

    /// Runs the lookup's `candidates` in order, preloading the dependents beside a path first
    /// (`RC-N`), and returns the first that loads; touches no process cache and does not count in
    /// `mui_sc_loads` unless `counted` (`RC-O`).
    static func load(candidates attempts: [LibraryAttempt], counted: Bool = false) throws -> SDLGPUShaderCompiler {
        do {
            return SDLGPUShaderCompiler(runtime: try RuntimeShaderCompiler.load(candidates: attempts.map(\.raw), counted: counted))
        } catch let error as RuntimeShaderCompileError { throw SDLGPUShaderCompileError(error) }
    }

    static var isWindows: Bool { RuntimeShaderCompiler.isWindows }
    static var isMacOS: Bool { RuntimeShaderCompiler.isMacOS }

    /// One place the library may be (the lookup's `Attempt`, wrapped because `MetalUIShaderCompile`'s
    /// types are `package`: the tests of the `MetalUISDL` package see only this).
    struct LibraryAttempt: Sendable {
        let raw: RuntimeLibraryLocator.Attempt
        var path: String { raw.path }
        /// A bare loader-path name, never existence-checked.
        var isLoaderName: Bool { raw.source == .loaderPath }
        /// A loader-path name the lookup would try last.
        static func loaderName(_ name: String) -> LibraryAttempt {
            LibraryAttempt(raw: RuntimeLibraryLocator.Attempt(path: name, source: .loaderPath, exists: nil,
                                                              reason: "left to the loader path (not checked)"))
        }
    }

    /// `RuntimeLibraryLocator.attempts` with the file system as closures (the lookup of `RC-C`).
    static func libraryAttempts(explicit: String?, environment: [String: String], executableDirectory: String?,
                                windows: Bool, macOS: Bool, fileExists: (String) -> Bool,
                                directoryExists: (String) -> Bool) -> [LibraryAttempt] {
        RuntimeShaderCompiler.libraryAttempts(
            explicit: explicit, environment: environment, executableDirectory: executableDirectory,
            windows: windows, macOS: macOS, fileExists: fileExists, directoryExists: directoryExists)
            .map { LibraryAttempt(raw: $0) }
    }

    // MARK: Process cache (the seam is internal, not public: `RC-O`; one cache for both APIs, `HX-E`)

    /// Where the process's compiler is resolved: a thin wrapper over the runtime's cache.
    final class ProcessCache: @unchecked Sendable {
        let runtime: RuntimeShaderCompiler.ProcessCache

        /// A cache whose lookup is `attempts` (given the explicit path, if any).
        init(attempts: @escaping @Sendable (String?) -> [LibraryAttempt]) {
            runtime = RuntimeShaderCompiler.ProcessCache(attempts: { attempts($0).map(\.raw) })
        }

        static var current: ProcessCache { ProcessCache(wrapping: RuntimeShaderCompiler.ProcessCache.current) }
        private init(wrapping cache: RuntimeShaderCompiler.ProcessCache) { runtime = cache }

        func resolve(explicit: String?) throws -> SDLGPUShaderCompiler {
            do { return SDLGPUShaderCompiler(runtime: try runtime.resolve(explicit: explicit)) }
            catch let error as RuntimeShaderCompileError { throw SDLGPUShaderCompileError(error) }
        }
    }

    /// Runs `body` with `cache` as the process cache (a test's seam; callers are serialized).
    static func withProcessCache<R>(_ cache: ProcessCache, _ body: () async throws -> R,
                                    isolation: isolated (any Actor)? = #isolation) async rethrows -> R {
        try await RuntimeShaderCompiler.withProcessCache(cache.runtime, body)
    }

    // MARK: Compiling

    /// The text a refusal with an empty message carries (and ``selfTest(for:)`` looks for).
    static var emptyDiagnostics: String { RuntimeShaderCompiler.emptyDiagnostics }

    /// Compiles HLSL compute source to `target` with its reflection (`RC-F`): SPIR-V is
    /// `SDL_ShaderCross_CompileSPIRVFromHLSL`, MSL its transpile (entry `main0`), DXIL the direct
    /// DXC route, and the reflection always comes from the SPIR-V. `defines` are `-D` macros,
    /// `includeDirectory` the one `#include` directory. Throws ``SDLGPUShaderCompileError``
    /// (`invalidInput` for a bad argument, `compileFailed` with the compiler's text); never traps.
    /// **Call off the main actor** (class docs).
    public func compileCompute(name: String, hlsl: String, entryPoint: String = "main",
                               defines: [SDLGPUShaderDefine] = [], includeDirectory: String? = nil,
                               target: SDLGPUShaderTarget) throws -> SDLGPUShaderBlob {
        let compiled: CompiledComputeShader
        do {
            compiled = try runtime.compileCompute(
                hlsl: hlsl, entryPoint: entryPoint, defines: try defines.map { try RuntimeShaderDefine($0.name, $0.value) },
                includeDirectory: includeDirectory, target: target.runtime)
        } catch let error as RuntimeShaderCompileError { throw SDLGPUShaderCompileError(error) }
        let reflection = compiled.reflection
        let format: SDLGPUShaderBlob.Format
        switch compiled.target {
        case .spirv: format = .spirv
        case .msl: format = .msl
        case .dxil: format = .dxil
        }
        return try SDLGPUShaderBlob(
            name: name, stage: .compute, bytes: compiled.bytes, format: format, entryPoint: compiled.entryPoint,
            samplers: reflection.samplers, readOnlyStorageTextures: reflection.readOnlyStorageTextures,
            readOnlyStorageBuffers: reflection.readOnlyStorageBuffers,
            readWriteStorageTextures: reflection.readWriteStorageTextures,
            readWriteStorageBuffers: reflection.readWriteStorageBuffers, uniformBuffers: reflection.uniformBuffers,
            threadCount: (reflection.threadCountX, reflection.threadCountY, reflection.threadCountZ))
    }

    /// ``compileCompute(name:hlsl:entryPoint:defines:includeDirectory:target:)`` for `device`'s driver
    /// (`vulkan`, `metal` or `direct3d12`; any other throws ``SDLGPUShaderCompileError/unsupportedTarget(_:)``).
    public func compileCompute(name: String, hlsl: String, entryPoint: String = "main",
                               defines: [SDLGPUShaderDefine] = [], includeDirectory: String? = nil,
                               for device: SDLGPUDevice) throws -> SDLGPUShaderBlob {
        try compileCompute(name: name, hlsl: hlsl, entryPoint: entryPoint, defines: defines,
                           includeDirectory: includeDirectory, target: try SDLGPUShaderTarget(driver: device.driver))
    }

    // MARK: Self test

    /// Loads the compiler, compiles a four-line kernel, compiles a deliberately broken one and
    /// requires real diagnostics (a compile that fails with an empty message throws, `RC-D`), and,
    /// with a device, builds the pipeline and runs one dispatch with a readback (`RC-J`). Throws
    /// ``SDLGPUShaderCompileError/compilerUnavailable(tried:)`` without the library, so an app's
    /// `--self-test` fails naming what to ship. `device` nil checks the SPIR-V route only.
    public func selfTest(for device: SDLGPUDevice?) async throws -> SDLGPUShaderCompilerReport {
        let started = Date()
        var notes: [String] = ["library \(libraryPath)"]
        let target = try device.map { try SDLGPUShaderTarget(driver: $0.driver) } ?? .spirv
        // The compile and broken-kernel arms are the runtime's one (`HX-F`); the dispatch arm below stays here.
        let runtimeReport: RuntimeShaderSelfTestReport
        do { runtimeReport = try runtime.selfTest(target: target.runtime) }
        catch let error as RuntimeShaderCompileError { throw SDLGPUShaderCompileError(error) }
        notes.append(contentsOf: runtimeReport.notes.dropFirst())
        let blob = try compileCompute(name: "selftest", hlsl: RuntimeShaderCompiler.selfTestKernel, target: target)
        if let device {
            let pipeline = try device.compileComputePipeline(blob)
            let words = 64
            guard let src = device.makeBuffer(size: words * 4, usage: [.computeStorageRead]),
                  let dst = device.makeBuffer(size: words * 4, usage: [.computeStorageWrite]) else {
                throw SDLGPUShaderCompileError.compileFailed(stage: "self test", diagnostics: "no GPU buffer: \(SDLGPUDevice.lastFailure)")
            }
            let input = (0..<UInt32(words)).flatMap { value in (0..<4).map { UInt8((value >> UInt32(8 * $0)) & 0xFF) } }
            guard await device.upload(input, to: src), await device.upload([UInt8](repeating: 0, count: words * 4), to: dst) else {
                throw SDLGPUShaderCompileError.compileFailed(stage: "self test", diagnostics: "upload failed: \(SDLGPUDevice.lastFailure)")
            }
            let uniform: [UInt8] = [UInt8(words), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            let fence = try await device.submitBatch { commandBuffer in
                guard let pass = commandBuffer.beginComputePass(readWrite: [dst]) else { return }
                pass.bind(pipeline)
                pass.bind(readOnly: [src])
                pass.push(uniform: uniform, at: 0)
                pass.dispatch(x: 1, y: 1, z: 1)
                pass.end()
            }
            await fence.wait()
            guard let bytes = await device.download(dst, range: 0..<(words * 4)) else {
                throw SDLGPUShaderCompileError.compileFailed(stage: "self test", diagnostics: "readback failed: \(SDLGPUDevice.lastFailure)")
            }
            let got = (0..<words).map { index in (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[index * 4 + $1]) << UInt32(8 * $1) } }
            guard got == (0..<UInt32(words)).map({ $0 * 2 }) else {
                throw SDLGPUShaderCompileError.compileFailed(
                    stage: "self test", diagnostics: "the dispatch wrote \(got.prefix(4)) where 0, 2, 4, 6 were expected")
            }
            notes.append("dispatched 64 threads and read back 64 words on \(device.driver)")
        }
        return SDLGPUShaderCompilerReport(
            driver: device?.driver ?? "none", format: "\(target)", libraryPath: libraryPath,
            compiledBytes: blob.bytes.count, entryPoint: blob.entryPoint,
            seconds: Date().timeIntervalSince(started), notes: notes)
    }

    /// ``shared(libraryPath:)`` and then ``selfTest(for:)``: throws ``SDLGPUShaderCompileError/compilerUnavailable(tried:)``
    /// without the library, the call an app's `--self-test` makes.
    public static func selfTest(for device: SDLGPUDevice?, libraryPath: String? = nil) async throws -> SDLGPUShaderCompilerReport {
        try await shared(libraryPath: libraryPath).selfTest(for: device)
    }
}

extension SDLGPUShaderTarget {
    /// The runtime compiler's spelling of this target.
    var runtime: RuntimeShaderTarget {
        switch self {
        case .spirv: return .spirv
        case .msl: return .msl
        case .dxil: return .dxil
        }
    }
}
#endif
