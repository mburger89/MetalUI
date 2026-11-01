import Foundation
import MetalUIShaderCompile
internal import CShaderCross

/// The run-time HLSL compute compiler without SDL (item XP-G27, rulings `HX-A`...): HLSL text in, a compiled
/// kernel and its reflection out, through SDL_shadercross's shared library loaded at the first call. MetalUI
/// links none of it, **and the app need not link SDL3**: shadercross's SDL3 is loaded from the shadercross
/// directory when the process has none (`HX-D`). Lookup: the explicit `libraryPath:`, `METALUI_SHADERCROSS_LIB`,
/// beside the executable, its `lib`, its `../lib`, the `lib` beside `METALUI_SHADERCROSS`'s `bin`, then the loader
/// path (`docs/packaging.md` 4b). One load per process, shared with `SDLGPUShaderCompiler` (`HX-E`).
/// Compiles run concurrently; a 1000-line kernel takes about half a second, so call it off the main actor
/// and cache the bytes (`RC-M`). Compute only (`RC-G`). Never traps on a bad kernel.
public struct RuntimeShaderCompiler: Sendable {
    /// The path of the loaded shadercross library.
    public let libraryPath: String
    let handle: Handle
    /// The full paths loaded before the library, in order (a test's read-back, `HX-D`).
    package let preloaded: [String]
    /// What `mui_rsc_process_has_sdl3()` answered at this load (`HX-D`).
    package let processHadSDL3: Bool

    /// The C handle, shared by copies; never freed (the library is never unloaded, `RC-B`).
    final class Handle: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
    }

    // MARK: Loading

    /// The compiler for the process, loaded on first use and then reused (`RC-B`). `libraryPath`
    /// names the library explicitly (it ranks first, and a missing file is an error, never a
    /// fall-through); after a load, a *different* path throws ``RuntimeShaderCompileError/libraryAlreadyLoaded(loaded:requested:)``.
    /// Throws ``RuntimeShaderCompileError/compilerUnavailable(tried:)`` when nothing loads.
    public static func shared(libraryPath: String? = nil) throws -> RuntimeShaderCompiler {
        try ProcessCache.current.resolve(explicit: libraryPath)
    }

    /// Whether ``shared(libraryPath:)`` succeeds with the default lookup. Never throws, never traps.
    public static var isAvailable: Bool { (try? shared()) != nil }

    /// How many counted loads happened in this process (`mui_rsc_loads`; the one-load pin's read-back).
    package static var loadCount: Int { Int(mui_rsc_loads()) }

    /// Whether the process holds an SDL3 right now (`mui_rsc_process_has_sdl3`).
    package static var processHasSDL3: Bool { mui_rsc_process_has_sdl3() }

    /// The test hook of `RC-J`: while set, every failure's text is emptied.
    package static func testingEmptyDiagnostics(_ empty: Bool) { mui_rsc_test_empty_diagnostics(empty) }

    /// Runs the lookup's `candidates` in order, preloading the dependents beside a path first (`RC-N`) and,
    /// when the process has no SDL3, an SDL3 beside the library (`HX-D`), and returns the first that loads;
    /// touches no process cache and does not count in `loadCount` unless `counted` (`RC-O`). `processHasSDL3`
    /// nil asks the process.
    package static func load(candidates: [RuntimeLibraryLocator.Attempt], counted: Bool = false,
                             processHasSDL3: Bool? = nil) throws -> RuntimeShaderCompiler {
        let order: [String]
        do { order = try RuntimeLibraryLocator.loadOrder(candidates) }
        catch let error as ComputeValidationError { throw RuntimeShaderCompileError(error) }
        let hadSDL3 = processHasSDL3 ?? mui_rsc_process_has_sdl3()
        var failures: [String: String] = [:]
        for path in order {
            var preload: [String] = []
            if path.contains("/") || path.contains("\\") {
                let directory = (path as NSString).deletingLastPathComponent
                let listing = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
                do {
                    preload = try RuntimeLibraryLocator.preloadSet(directory: directory, listing: listing,
                                                                   windows: isWindows, macOS: isMacOS,
                                                                   includingSDL: !hadSDL3)
                } catch let error as ComputeValidationError {
                    failures[path] = "failed dependents: " + String(describing: error).replacingOccurrences(of: "\n", with: "; ")
                    continue
                }
            }
            var error = [CChar](repeating: 0, count: 4096)
            let pointer: OpaquePointer? = withCStrings(preload) { names, count in
                path.withCString { mui_rsc_load($0, names, count, counted, &error, error.count) }
            }
            if let pointer {
                return RuntimeShaderCompiler(libraryPath: path, handle: Handle(pointer), preloaded: preload,
                                             processHadSDL3: hadSDL3)
            }
            let text = cText(error)
            failures[path] = text.isEmpty ? "the loader gave no message" : text
        }
        throw RuntimeShaderCompileError.compilerUnavailable(tried: RuntimeLibraryLocator.describe(candidates, loadFailures: failures))
    }

    #if os(Windows)
    package static let isWindows = true
    #else
    package static let isWindows = false
    #endif
    #if os(macOS)
    package static let isMacOS = true
    #else
    package static let isMacOS = false
    #endif

    // MARK: Process cache (a package seam, not public: `RC-O`)

    /// Where the process's compiler is resolved. The default is the real environment and loads once;
    /// a test swaps in one whose lookup finds nothing (`withProcessCache`).
    package final class ProcessCache: @unchecked Sendable {
        private let lock = NSLock()
        private var loaded: RuntimeShaderCompiler?
        private let attempts: @Sendable (String?) -> [RuntimeLibraryLocator.Attempt]

        /// A cache whose lookup is `attempts` (given the explicit path, if any).
        package init(attempts: @escaping @Sendable (String?) -> [RuntimeLibraryLocator.Attempt]) { self.attempts = attempts }

        /// The real lookup: the environment, the executable's directory, the loader path.
        package static let standard = ProcessCache { explicit in
            let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? ".")
            return RuntimeShaderCompiler.libraryAttempts(
                explicit: explicit, environment: ProcessInfo.processInfo.environment,
                executableDirectory: executable.deletingLastPathComponent().path,
                windows: RuntimeShaderCompiler.isWindows, macOS: RuntimeShaderCompiler.isMacOS,
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                directoryExists: { var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory) && isDirectory.boolValue })
        }

        nonisolated(unsafe) private static var swapped: ProcessCache?
        private static let swapLock = NSLock()
        /// The cache `shared()` resolves through: the swapped one, else `standard`.
        package static var current: ProcessCache {
            swapLock.lock(); defer { swapLock.unlock() }
            return swapped ?? standard
        }
        /// Installs `cache` (nil restores `standard`) and returns the previous swap.
        package static func swap(to cache: ProcessCache?) -> ProcessCache? {
            swapLock.lock(); defer { swapLock.unlock() }
            let previous = swapped
            swapped = cache
            return previous
        }

        /// The loaded compiler, loading it on first use; a different explicit path throws `libraryAlreadyLoaded`.
        package func resolve(explicit: String?) throws -> RuntimeShaderCompiler {
            lock.lock(); defer { lock.unlock() }
            if let loaded {
                if let explicit, !explicit.isEmpty, explicit != loaded.libraryPath {
                    throw RuntimeShaderCompileError.libraryAlreadyLoaded(loaded: loaded.libraryPath, requested: explicit)
                }
                return loaded
            }
            let compiler = try RuntimeShaderCompiler.load(candidates: attempts(explicit), counted: true)
            loaded = compiler
            return compiler
        }
    }

    /// `RuntimeLibraryLocator.attempts` with the file system as closures (the lookup of `RC-C`).
    package static func libraryAttempts(explicit: String?, environment: [String: String], executableDirectory: String?,
                                        windows: Bool, macOS: Bool, fileExists: (String) -> Bool,
                                        directoryExists: (String) -> Bool) -> [RuntimeLibraryLocator.Attempt] {
        RuntimeLibraryLocator.attempts(explicit: explicit, environment: environment, executableDirectory: executableDirectory,
                                       windows: windows, macOS: macOS, fileExists: fileExists, directoryExists: directoryExists)
    }

    /// Runs `body` with `cache` as the process cache (a test's seam; callers are serialized).
    package static func withProcessCache<R>(_ cache: ProcessCache, _ body: () async throws -> R,
                                            isolation: isolated (any Actor)? = #isolation) async rethrows -> R {
        let previous = ProcessCache.swap(to: cache)
        defer { _ = ProcessCache.swap(to: previous) }
        return try await body()
    }

    // MARK: Compiling

    /// The text a refusal with an empty message carries (and ``selfTest(target:)`` looks for).
    package static let emptyDiagnostics = "the compiler gave no message (it may hold a different SDL instance than this app; RC-D)"

    /// Compiles HLSL compute source to `target` with its reflection (always from the SPIR-V; DXIL from HLSL, `RC-F`).
    /// `defines` are `-D` macros, `includeDirectory` the one `#include` directory. Throws
    /// ``RuntimeShaderCompileError`` (`invalidInput` for a bad argument, `compileFailed` with the compiler's text);
    /// never traps. **Call off the main actor** (type docs).
    public func compileCompute(hlsl: String, entryPoint: String = "main", defines: [RuntimeShaderDefine] = [],
                               includeDirectory: String? = nil, target: RuntimeShaderTarget) throws -> CompiledComputeShader {
        do {
            try ComputeBlobValidation.validateSource(hlsl)
            try ComputeBlobValidation.validateEntryPoint(entryPoint)
            try ComputeBlobValidation.validateDefines(defines.map { (name: $0.name, value: $0.value) })
        } catch let error as ComputeValidationError { throw RuntimeShaderCompileError(error) }
        if let includeDirectory, includeDirectory.utf8.contains(0) {
            throw RuntimeShaderCompileError.invalidInput("includeDirectory holds a NUL byte")
        }
        let spirv = try compileHLSL(hlsl, entryPoint: entryPoint, defines: defines, includeDirectory: includeDirectory,
                                    dxil: false, stage: "HLSL to SPIR-V")
        do { try ComputeBlobValidation.validateBytes(spirv, format: .spirv, entryPoint: entryPoint) }
        catch let error as ComputeValidationError { throw RuntimeShaderCompileError(error) }
        let reflection = try reflect(spirv)
        // A declared register the compiler dropped shifts every later slot (XP-G36, UB-D): refuse, naming it.
        let counts = ShaderSlotCheck.Counts(
            samplers: reflection.samplers, readOnlyStorageTextures: reflection.readOnlyStorageTextures,
            readOnlyStorageBuffers: reflection.readOnlyStorageBuffers,
            readWriteStorageTextures: reflection.readWriteStorageTextures,
            readWriteStorageBuffers: reflection.readWriteStorageBuffers, uniformBuffers: reflection.uniformBuffers)
        let slotProblems = ShaderSlotCheck.problems(name: "compute shader (entry point \(entryPoint))", stage: .compute,
                                                    source: hlsl, counts: counts)
        if !slotProblems.isEmpty {
            throw RuntimeShaderCompileError.compileFailed(stage: "register slot check", diagnostics: slotProblems.joined(separator: "\n"))
        }
        switch target {
        case .spirv:
            return CompiledComputeShader(target: .spirv, bytes: spirv, entryPoint: entryPoint, reflection: reflection)
        case .msl:
            return CompiledComputeShader(target: .msl, bytes: try transpileMSL(spirv, entryPoint: entryPoint),
                                         entryPoint: "main0", reflection: reflection)
        case .dxil:
            let dxil = try compileHLSL(hlsl, entryPoint: entryPoint, defines: defines, includeDirectory: includeDirectory,
                                       dxil: true, stage: "HLSL to DXIL")
            return CompiledComputeShader(target: .dxil, bytes: dxil, entryPoint: entryPoint, reflection: reflection)
        }
    }

    private func compileHLSL(_ hlsl: String, entryPoint: String, defines: [RuntimeShaderDefine], includeDirectory: String?,
                             dxil: Bool, stage: String) throws -> [UInt8] {
        let names = defines.map { duplicateCString($0.name) }
        let values = defines.map { $0.value.map { duplicateCString($0) } ?? nil }
        defer { names.forEach { free($0) }; values.forEach { free($0) } }
        var error = [CChar](repeating: 0, count: 32768)
        var out: UnsafeMutablePointer<UInt8>?
        var size = 0
        let status: Int32 = hlsl.withCString { source in
            entryPoint.withCString { entry in
                names.map { UnsafePointer($0) }.withUnsafeBufferPointer { namePointers in
                    values.map { $0.map { UnsafePointer($0) } }.withUnsafeBufferPointer { valuePointers in
                        let call = { (include: UnsafePointer<CChar>?) -> Int32 in
                            mui_rsc_compile_hlsl(handle.pointer, dxil ? 1 : 0, source, entry, include,
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
        defer { mui_rsc_free(handle.pointer, out) }
        return Array(UnsafeBufferPointer(start: out, count: size))
    }

    private func transpileMSL(_ spirv: [UInt8], entryPoint: String) throws -> [UInt8] {
        var error = [CChar](repeating: 0, count: 32768)
        var out: UnsafeMutablePointer<UInt8>?
        var size = 0
        let status: Int32 = spirv.withUnsafeBufferPointer { code in
            entryPoint.withCString { entry in
                mui_rsc_msl(handle.pointer, code.baseAddress, code.count, entry, &out, &size, &error, error.count)
            }
        }
        guard status == 0, let out else { throw failure("SPIR-V to MSL", error) }
        defer { mui_rsc_free(handle.pointer, out) }
        return Array(UnsafeBufferPointer(start: out, count: size))
    }

    private func reflect(_ spirv: [UInt8]) throws -> ComputeShaderReflection {
        var error = [CChar](repeating: 0, count: 8192)
        var raw = MuiRSCReflection()
        let status: Int32 = spirv.withUnsafeBufferPointer { code in
            mui_rsc_reflect(handle.pointer, code.baseAddress, code.count, &raw, &error, error.count)
        }
        guard status == 0 else { throw failure("SPIR-V reflection", error) }
        let reflection = ComputeReflection(
            samplers: Int(raw.samplers), readOnlyStorageTextures: Int(raw.readonly_storage_textures),
            readOnlyStorageBuffers: Int(raw.readonly_storage_buffers),
            readWriteStorageTextures: Int(raw.readwrite_storage_textures),
            readWriteStorageBuffers: Int(raw.readwrite_storage_buffers), uniformBuffers: Int(raw.uniform_buffers),
            threadCount: (Int(raw.threadcount_x), Int(raw.threadcount_y), Int(raw.threadcount_z)))
        do { try ComputeBlobValidation.validate(reflection) }
        catch let error as ComputeValidationError { throw RuntimeShaderCompileError(error) }
        return ComputeShaderReflection(reflection)
    }

    private func failure(_ stage: String, _ buffer: [CChar]) -> RuntimeShaderCompileError {
        let text = cText(buffer)
        return .compileFailed(stage: stage, diagnostics: text.isEmpty ? Self.emptyDiagnostics : text)
    }

    // MARK: Self test

    /// The four-line kernel the self test compiles.
    package static let selfTestKernel = """
        StructuredBuffer<uint> src : register(t0, space0);
        RWStructuredBuffer<uint> dst : register(u0, space1);
        cbuffer P : register(b0, space2) { uint n; };
        [numthreads(64, 1, 1)] void main(uint3 id : SV_DispatchThreadID) { if (id.x < n) dst[id.x] = src[id.x] * 2u; }
        """

    /// Compiles a four-line kernel to `target`, then a deliberately broken one, requiring DXC's own text back
    /// (a compile that fails with an empty message throws, `RC-J`, `HX-D`).
    public func selfTest(target: RuntimeShaderTarget = .spirv) throws -> RuntimeShaderSelfTestReport {
        let started = Date()
        var notes: [String] = ["library \(libraryPath)"]
        let kernel = try compileCompute(hlsl: Self.selfTestKernel, target: target)
        notes.append("compiled \(kernel.bytes.count) bytes to \(target)")
        do {
            _ = try compileCompute(hlsl: "[numthreads(1,1,1)] void main( { }", target: .spirv)
            throw RuntimeShaderCompileError.compileFailed(stage: "self test", diagnostics: "a deliberately broken kernel compiled")
        } catch RuntimeShaderCompileError.compileFailed(let stage, let diagnostics) where stage != "self test" {
            if diagnostics == Self.emptyDiagnostics {
                throw RuntimeShaderCompileError.compileFailed(
                    stage: stage, diagnostics: "a broken kernel gave no message: \(Self.emptyDiagnostics)")
            }
            notes.append("a broken kernel's diagnostics: \(diagnostics.prefix(80))")
        }
        return RuntimeShaderSelfTestReport(libraryPath: libraryPath, target: target, compiledBytes: kernel.bytes.count,
                                           entryPoint: kernel.entryPoint, seconds: Date().timeIntervalSince(started), notes: notes)
    }

    /// ``shared(libraryPath:)`` then ``selfTest(target:)``: an app's `--self-test` call.
    public static func selfTest(target: RuntimeShaderTarget = .spirv, libraryPath: String? = nil) throws -> RuntimeShaderSelfTestReport {
        try shared(libraryPath: libraryPath).selfTest(target: target)
    }
}

/// Calls `body` with a C array of `strings` and its count (valid for the call).
private func withCStrings<R>(_ strings: [String], _ body: (UnsafePointer<UnsafePointer<CChar>?>?, UInt32) -> R) -> R {
    let copies = strings.map { duplicateCString($0) }
    defer { copies.forEach { free($0) } }
    let pointers: [UnsafePointer<CChar>?] = copies.map { $0.map { UnsafePointer($0) } }
    return pointers.withUnsafeBufferPointer { body($0.baseAddress, UInt32($0.count)) }
}

/// The text of a C buffer up to its NUL.
private func cText(_ buffer: [CChar]) -> String {
    String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

/// `strdup`, spelled `_strdup` where the UCRT deprecates the POSIX name.
private func duplicateCString(_ string: String) -> UnsafeMutablePointer<CChar>? {
    #if os(Windows)
    _strdup(string)
    #else
    strdup(string)
    #endif
}
