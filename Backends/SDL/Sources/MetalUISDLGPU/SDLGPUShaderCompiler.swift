// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation
import SDLBridge
import MetalUIShaderCompile

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
    public let libraryPath: String
    let handle: Handle

    /// The C handle, shared by copies; never freed (the library is never unloaded, `RC-B`).
    final class Handle: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
    }

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
        let candidates = attempts.map(\.raw)
        let order: [String]
        do { order = try RuntimeLibraryLocator.loadOrder(candidates) }
        catch let error as ComputeValidationError { throw SDLGPUShaderCompileError(error) }
        var failures: [String: String] = [:]
        for path in order {
            var preload: [String] = []
            if path.contains("/") || path.contains("\\") {
                let directory = (path as NSString).deletingLastPathComponent
                let listing = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
                do { preload = try RuntimeLibraryLocator.preloadSet(directory: directory, listing: listing, windows: isWindows, macOS: isMacOS) }
                catch let error as ComputeValidationError {
                    failures[path] = "failed dependents: " + String(describing: error).replacingOccurrences(of: "\n", with: "; ")
                    continue
                }
            }
            var error = [CChar](repeating: 0, count: 4096)
            let pointer: OpaquePointer? = withCStrings(preload) { names, count in
                path.withCString { mui_sc_load($0, names, count, counted, &error, error.count) }
            }
            if let pointer { return SDLGPUShaderCompiler(libraryPath: path, handle: Handle(pointer)) }
            let text = cText(error)
            failures[path] = text.isEmpty ? "the loader gave no message" : text
        }
        throw SDLGPUShaderCompileError.compilerUnavailable(tried: RuntimeLibraryLocator.describe(candidates, loadFailures: failures))
    }

    #if os(Windows)
    static let isWindows = true
    #else
    static let isWindows = false
    #endif
    #if os(macOS)
    static let isMacOS = true
    #else
    static let isMacOS = false
    #endif

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
        RuntimeLibraryLocator.attempts(explicit: explicit, environment: environment, executableDirectory: executableDirectory,
                                       windows: windows, macOS: macOS, fileExists: fileExists,
                                       directoryExists: directoryExists).map { LibraryAttempt(raw: $0) }
    }

    // MARK: Process cache (the seam is internal, not public: `RC-O`)

    /// Where the process's compiler is resolved. The default is the real environment and loads once;
    /// a test swaps in one whose lookup finds nothing (`withProcessCache`).
    final class ProcessCache: @unchecked Sendable {
        private let lock = NSLock()
        private var loaded: SDLGPUShaderCompiler?
        private let attempts: @Sendable (String?) -> [LibraryAttempt]

        /// A cache whose lookup is `attempts` (given the explicit path, if any).
        init(attempts: @escaping @Sendable (String?) -> [LibraryAttempt]) { self.attempts = attempts }

        /// The real lookup: the environment, the executable's directory, the loader path.
        static let standard = ProcessCache { explicit in
            let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? ".")
            return SDLGPUShaderCompiler.libraryAttempts(
                explicit: explicit, environment: ProcessInfo.processInfo.environment,
                executableDirectory: executable.deletingLastPathComponent().path,
                windows: SDLGPUShaderCompiler.isWindows, macOS: SDLGPUShaderCompiler.isMacOS,
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                directoryExists: { var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory) && isDirectory.boolValue })
        }

        nonisolated(unsafe) private static var swapped: ProcessCache?
        private static let swapLock = NSLock()
        static var current: ProcessCache {
            swapLock.lock(); defer { swapLock.unlock() }
            return swapped ?? standard
        }
        static func swap(to cache: ProcessCache?) -> ProcessCache? {
            swapLock.lock(); defer { swapLock.unlock() }
            let previous = swapped
            swapped = cache
            return previous
        }

        func resolve(explicit: String?) throws -> SDLGPUShaderCompiler {
            lock.lock(); defer { lock.unlock() }
            if let loaded {
                if let explicit, !explicit.isEmpty, explicit != loaded.libraryPath {
                    throw SDLGPUShaderCompileError.libraryAlreadyLoaded(loaded: loaded.libraryPath, requested: explicit)
                }
                return loaded
            }
            let compiler = try SDLGPUShaderCompiler.load(candidates: attempts(explicit), counted: true)
            loaded = compiler
            return compiler
        }
    }

    /// Runs `body` with `cache` as the process cache (a test's seam; callers are serialized).
    static func withProcessCache<R>(_ cache: ProcessCache, _ body: () async throws -> R,
                                            isolation: isolated (any Actor)? = #isolation) async rethrows -> R {
        let previous = ProcessCache.swap(to: cache)
        defer { _ = ProcessCache.swap(to: previous) }
        return try await body()
    }

    // MARK: Compiling

    /// The text a refusal with an empty message carries (and ``selfTest(for:)`` looks for).
    static let emptyDiagnostics = "the compiler gave no message (it may hold a different SDL instance than this app; RC-D)"

    /// Compiles HLSL compute source to `target` with its reflection (`RC-F`): SPIR-V is
    /// `SDL_ShaderCross_CompileSPIRVFromHLSL`, MSL its transpile (entry `main0`), DXIL the direct
    /// DXC route, and the reflection always comes from the SPIR-V. `defines` are `-D` macros,
    /// `includeDirectory` the one `#include` directory. Throws ``SDLGPUShaderCompileError``
    /// (`invalidInput` for a bad argument, `compileFailed` with the compiler's text); never traps.
    /// **Call off the main actor** (class docs).
    public func compileCompute(name: String, hlsl: String, entryPoint: String = "main",
                               defines: [SDLGPUShaderDefine] = [], includeDirectory: String? = nil,
                               target: SDLGPUShaderTarget) throws -> SDLGPUShaderBlob {
        do {
            try ComputeBlobValidation.validateSource(hlsl)
            try ComputeBlobValidation.validateEntryPoint(entryPoint)
            try ComputeBlobValidation.validateDefines(defines.map { (name: $0.name, value: $0.value) })
        } catch let error as ComputeValidationError { throw SDLGPUShaderCompileError(error) }
        if let includeDirectory, includeDirectory.utf8.contains(0) {
            throw SDLGPUShaderCompileError.invalidInput("includeDirectory holds a NUL byte")
        }
        let spirv = try compileHLSL(hlsl, entryPoint: entryPoint, defines: defines, includeDirectory: includeDirectory,
                                    dxil: false, stage: "HLSL to SPIR-V")
        do { try ComputeBlobValidation.validateBytes(spirv, format: .spirv, entryPoint: entryPoint) }
        catch let error as ComputeValidationError { throw SDLGPUShaderCompileError(error) }
        let reflection = try reflect(spirv)
        let bytes: [UInt8]
        let outputEntry: String
        let format: SDLGPUShaderBlob.Format
        switch target {
        case .spirv: (bytes, outputEntry, format) = (spirv, entryPoint, .spirv)
        case .msl: (bytes, outputEntry, format) = (try transpileMSL(spirv, entryPoint: entryPoint), "main0", .msl)
        case .dxil:
            (bytes, outputEntry, format) = (try compileHLSL(hlsl, entryPoint: entryPoint, defines: defines,
                                                            includeDirectory: includeDirectory, dxil: true, stage: "HLSL to DXIL"),
                                            entryPoint, .dxil)
        }
        return try SDLGPUShaderBlob(
            name: name, stage: .compute, bytes: bytes, format: format, entryPoint: outputEntry,
            samplers: reflection.samplers, readOnlyStorageTextures: reflection.readOnlyStorageTextures,
            readOnlyStorageBuffers: reflection.readOnlyStorageBuffers,
            readWriteStorageTextures: reflection.readWriteStorageTextures,
            readWriteStorageBuffers: reflection.readWriteStorageBuffers, uniformBuffers: reflection.uniformBuffers,
            threadCount: reflection.threadCount)
    }

    /// ``compileCompute(name:hlsl:entryPoint:defines:includeDirectory:target:)`` for `device`'s driver
    /// (`vulkan`, `metal` or `direct3d12`; any other throws ``SDLGPUShaderCompileError/unsupportedTarget(_:)``).
    public func compileCompute(name: String, hlsl: String, entryPoint: String = "main",
                               defines: [SDLGPUShaderDefine] = [], includeDirectory: String? = nil,
                               for device: SDLGPUDevice) throws -> SDLGPUShaderBlob {
        try compileCompute(name: name, hlsl: hlsl, entryPoint: entryPoint, defines: defines,
                           includeDirectory: includeDirectory, target: try SDLGPUShaderTarget(driver: device.driver))
    }

    private func compileHLSL(_ hlsl: String, entryPoint: String, defines: [SDLGPUShaderDefine], includeDirectory: String?,
                             dxil: Bool, stage: String) throws -> [UInt8] {
        let names = defines.map { strdup($0.name) }
        let values = defines.map { $0.value.map { strdup($0) } ?? nil }
        defer { names.forEach { free($0) }; values.forEach { free($0) } }
        var error = [CChar](repeating: 0, count: 32768)
        var out: UnsafeMutablePointer<UInt8>?
        var size = 0
        let status: Int32 = hlsl.withCString { source in
            entryPoint.withCString { entry in
                names.map { UnsafePointer($0) }.withUnsafeBufferPointer { namePointers in
                    values.map { $0.map { UnsafePointer($0) } }.withUnsafeBufferPointer { valuePointers in
                        let call = { (include: UnsafePointer<CChar>?) -> Int32 in
                            mui_sc_compile_hlsl(handle.pointer, dxil ? 1 : 0, source, entry, include,
                                                namePointers.baseAddress, valuePointers.baseAddress, UInt32(defines.count),
                                                &out, &size, &error, error.count)
                        }
                        if let includeDirectory { return includeDirectory.withCString { call($0) } }
                        return call(nil)
                    }
                }
            }
        }
        guard status == 0, let out else { throw failure(stage, error) }
        defer { mui_sc_free(out) }
        return Array(UnsafeBufferPointer(start: out, count: size))
    }

    private func transpileMSL(_ spirv: [UInt8], entryPoint: String) throws -> [UInt8] {
        var error = [CChar](repeating: 0, count: 32768)
        var out: UnsafeMutablePointer<UInt8>?
        var size = 0
        let status: Int32 = spirv.withUnsafeBufferPointer { code in
            entryPoint.withCString { entry in
                mui_sc_msl(handle.pointer, code.baseAddress, code.count, entry, &out, &size, &error, error.count)
            }
        }
        guard status == 0, let out else { throw failure("SPIR-V to MSL", error) }
        defer { mui_sc_free(out) }
        return Array(UnsafeBufferPointer(start: out, count: size))
    }

    private func reflect(_ spirv: [UInt8]) throws -> ComputeReflection {
        var error = [CChar](repeating: 0, count: 8192)
        var raw = MuiShaderCrossReflection()
        let status: Int32 = spirv.withUnsafeBufferPointer { code in
            mui_sc_reflect(handle.pointer, code.baseAddress, code.count, &raw, &error, error.count)
        }
        guard status == 0 else { throw failure("SPIR-V reflection", error) }
        let reflection = ComputeReflection(
            samplers: Int(raw.samplers), readOnlyStorageTextures: Int(raw.readonly_storage_textures),
            readOnlyStorageBuffers: Int(raw.readonly_storage_buffers),
            readWriteStorageTextures: Int(raw.readwrite_storage_textures),
            readWriteStorageBuffers: Int(raw.readwrite_storage_buffers), uniformBuffers: Int(raw.uniform_buffers),
            threadCount: (Int(raw.threadcount_x), Int(raw.threadcount_y), Int(raw.threadcount_z)))
        do { try ComputeBlobValidation.validate(reflection) }
        catch let error as ComputeValidationError { throw SDLGPUShaderCompileError(error) }
        return reflection
    }

    private func failure(_ stage: String, _ buffer: [CChar]) -> SDLGPUShaderCompileError {
        let text = cText(buffer)
        return .compileFailed(stage: stage, diagnostics: text.isEmpty ? Self.emptyDiagnostics : text)
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
        let kernel = """
            StructuredBuffer<uint> src : register(t0, space0);
            RWStructuredBuffer<uint> dst : register(u0, space1);
            cbuffer P : register(b0, space2) { uint n; };
            [numthreads(64, 1, 1)] void main(uint3 id : SV_DispatchThreadID) { if (id.x < n) dst[id.x] = src[id.x] * 2u; }
            """
        let blob = try compileCompute(name: "selftest", hlsl: kernel, target: target)
        notes.append("compiled \(blob.bytes.count) bytes to \(target)")
        do {
            _ = try compileCompute(name: "selftest-broken", hlsl: "[numthreads(1,1,1)] void main( { }", target: .spirv)
            throw SDLGPUShaderCompileError.compileFailed(stage: "self test", diagnostics: "a deliberately broken kernel compiled")
        } catch SDLGPUShaderCompileError.compileFailed(let stage, let diagnostics) where stage != "self test" {
            if diagnostics == Self.emptyDiagnostics {
                throw SDLGPUShaderCompileError.compileFailed(
                    stage: stage, diagnostics: "a broken kernel gave no message: \(Self.emptyDiagnostics)")
            }
            notes.append("a broken kernel's diagnostics: \(diagnostics.prefix(80))")
        }
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

/// Calls `body` with a C array of `strings` and its count (valid for the call).
private func withCStrings<R>(_ strings: [String], _ body: (UnsafePointer<UnsafePointer<CChar>?>?, UInt32) -> R) -> R {
    let copies = strings.map { strdup($0) }
    defer { copies.forEach { free($0) } }
    let pointers: [UnsafePointer<CChar>?] = copies.map { $0.map { UnsafePointer($0) } }
    return pointers.withUnsafeBufferPointer { body($0.baseAddress, UInt32($0.count)) }
}

/// The text of a C buffer up to its NUL.
private func cText(_ buffer: [CChar]) -> String {
    String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
#endif
