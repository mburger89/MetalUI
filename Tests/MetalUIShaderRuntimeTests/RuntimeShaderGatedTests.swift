import Foundation
import Testing
@testable import MetalUIShaderRuntime
@testable import MetalUIShaderCompile
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
#if canImport(Metal)
import Metal
#endif

// Tests 9-18 of the spec (section 7): they need `METALUI_SHADERCROSS_LIB` (the pin's install, `HX-B`).

#if !os(Windows)
/// `RTLD_DEFAULT`, which Swift does not import (Darwin: -2, glibc: nil).
private func defaultSymbolScope() -> UnsafeMutableRawPointer? {
    #if canImport(Darwin)
    UnsafeMutableRawPointer(bitPattern: -2)
    #else
    nil
    #endif
}
#endif

private let sdl3Gate = (RuntimeShaderSupport.environment["METALUI_SHADERCROSS_LIB"] ?? "").isEmpty
    ? false : !(RuntimeShaderSupport.environment["METALUI_SDL3_LIB"] ?? "").isEmpty

extension RuntimeShaderTests {
    /// **9.** `METALUI_REQUIRE_SHADERCROSS=1` makes a missing library a failure, so a skip cannot hide it.
    @Test func aRequiredShaderCompilerIsPresent() {
        guard RuntimeShaderSupport.required else { return }
        #expect(RuntimeShaderSupport.available, "METALUI_REQUIRE_SHADERCROSS=1 but \(RuntimeShaderSupport.lastFailureText)")
    }

    /// **10.** The control kernel compiles to every target with its reflection, with no SDL3 linked into the
    /// test process (`processHadSDL3 == false`). Mutation: the Swift mapping drops the read-write buffer count.
    @Test(.enabled(if: RuntimeShaderSupport.available, needsCompiler))
    func aKernelCompilesToEveryTargetWithItsReflectionWithoutSDLLinked() throws {
        let compiler = try RuntimeShaderCompiler.shared()
        #expect(!compiler.processHadSDL3, "nothing in the root test process links SDL3")
        let defines = [try RuntimeShaderDefine("K", "2")]
        for target in RuntimeShaderTarget.allCases {
            let kernel = try compiler.compileCompute(hlsl: RuntimeShaderSupport.scaleKernel, defines: defines, target: target)
            #expect(kernel.target == target)
            let r = kernel.reflection
            #expect(r.samplers == 0 && r.readOnlyStorageTextures == 0 && r.readOnlyStorageBuffers == 1, "\(target) \(r)")
            #expect(r.readWriteStorageTextures == 0 && r.readWriteStorageBuffers == 1 && r.uniformBuffers == 1, "\(target) \(r)")
            #expect(r.threadCountX == 64 && r.threadCountY == 1 && r.threadCountZ == 1, "\(target) \(r)")
            switch target {
            case .spirv:
                #expect(Array(kernel.bytes.prefix(4)) == [0x03, 0x02, 0x23, 0x07]); #expect(kernel.entryPoint == "main")
            case .msl:
                #expect(String(decoding: kernel.bytes, as: UTF8.self).contains("main0")); #expect(kernel.entryPoint == "main0")
            case .dxil:
                #expect(Array(kernel.bytes.prefix(4)) == Array("DXBC".utf8)); #expect(kernel.entryPoint == "main")
            }
        }
    }

    /// **11.** A syntax error throws `compileFailed` naming the stage with DXC's own text. Mutation: the shim
    /// never reads the error (M20 of `RC-Y`, moved).
    @Test(.enabled(if: RuntimeShaderSupport.available, needsCompiler))
    func aSyntaxErrorThrowsCompileFailedWithDXCsText() throws {
        let compiler = try RuntimeShaderCompiler.shared()
        do {
            _ = try compiler.compileCompute(hlsl: "[numthreads(1,1,1)] void main(\n", target: .spirv)
            Issue.record("a syntax error compiled")
        } catch RuntimeShaderCompileError.compileFailed(let stage, let diagnostics) {
            #expect(stage == "HLSL to SPIR-V")
            #expect(diagnostics.contains("error:"), "\(diagnostics)")
        }
        do {
            _ = try compiler.compileCompute(hlsl: RuntimeShaderSupport.brokenKernel, target: .spirv)
            Issue.record("a syntax error compiled")
        } catch RuntimeShaderCompileError.compileFailed(_, let diagnostics) {
            #expect(diagnostics.contains("expected parameter declarator"), "\(diagnostics)")
        }
    }

    /// **12.** An SDL3 beside shadercross is preloaded locally (fresh process, `RTLD_LOCAL`) and the diagnostics
    /// still arrive. Needs `METALUI_SDL3_LIB` too. Mutations: `includingSDL: false` (red: `preloaded`); resolve
    /// `SDL_GetError` with `dlsym(RTLD_DEFAULT, ...)` (red: the load fails); load SDL3 `RTLD_GLOBAL` (red: the last assertion).
    @Test(.enabled(if: sdl3Gate, Comment(rawValue: "needs METALUI_SHADERCROSS_LIB and METALUI_SDL3_LIB")))
    func anSDL3BesideShadercrossIsPreloadedLocallyAndCarriesTheDiagnostics() async {
        #if os(Windows)
        return
        #else
        await #expect(processExitsWith: .success) {
            let env = ProcessInfo.processInfo.environment
            let fm = FileManager.default
            var shadercross = URL(fileURLWithPath: try #require(env["METALUI_SHADERCROSS_LIB"]))
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: shadercross.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                shadercross = shadercross.deletingLastPathComponent()
            }
            let temp = fm.temporaryDirectory.appendingPathComponent("mui-hx-sdl3-\(UUID().uuidString)")
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: temp) }
            for name in try fm.contentsOfDirectory(atPath: shadercross.path) {
                try fm.createSymbolicLink(at: temp.appendingPathComponent(name),
                                          withDestinationURL: shadercross.appendingPathComponent(name))
            }
            let sdl3 = temp.appendingPathComponent(RuntimeShaderSupport.sdl3LinkName)
            try? fm.removeItem(at: sdl3)
            try fm.createSymbolicLink(at: sdl3, withDestinationURL: URL(fileURLWithPath: try #require(env["METALUI_SDL3_LIB"])))
            let name = try #require(RuntimeLibraryLocator.libraryNames(windows: false, macOS: RuntimeShaderCompiler.isMacOS)
                .first { fm.fileExists(atPath: temp.appendingPathComponent($0).path) })
            let attempt = RuntimeLibraryLocator.Attempt(path: temp.appendingPathComponent(name).path, source: .explicit,
                                                        exists: true, reason: "a linked copy")
            let compiler = try RuntimeShaderCompiler.load(candidates: [attempt])
            #expect(!compiler.processHadSDL3)
            #expect(compiler.preloaded.first?.hasSuffix(RuntimeShaderSupport.sdl3LinkName) == true, "\(compiler.preloaded)")
            let kernel = try compiler.compileCompute(hlsl: RuntimeShaderSupport.scaleKernel,
                                                     defines: [try RuntimeShaderDefine("K", "2")], target: .spirv)
            #expect(kernel.reflection.readWriteStorageBuffers == 1)
            do { _ = try compiler.compileCompute(hlsl: RuntimeShaderSupport.brokenKernel, target: .spirv); Issue.record("compiled") }
            catch RuntimeShaderCompileError.compileFailed(_, let diagnostics) {
                #expect(diagnostics.contains("error:"), "DXC's text: \(diagnostics)")
            }
            #expect(dlsym(defaultSymbolScope(), "SDL_GetError") == nil, "the preloaded SDL3 stayed RTLD_LOCAL")
        }
        #endif
    }

    /// **13.** Eight tasks of five `shared()` calls load once; a different explicit path throws `libraryAlreadyLoaded`.
    /// Mutation: `shared()` loads per call.
    @Test(.enabled(if: RuntimeShaderSupport.available, needsCompiler))
    func aSecondSharedCallReusesTheFirstLoad() async throws {
        let first = try RuntimeShaderCompiler.shared()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { for _ in 0..<5 { _ = try? RuntimeShaderCompiler.shared() } } }
        }
        #expect(RuntimeShaderCompiler.loadCount == 1, "loads: \(RuntimeShaderCompiler.loadCount)")
        let again = try RuntimeShaderCompiler.shared()
        #expect(again.libraryPath == first.libraryPath)
        #expect(throws: RuntimeShaderCompileError.libraryAlreadyLoaded(loaded: first.libraryPath, requested: first.libraryPath + ".other")) {
            _ = try RuntimeShaderCompiler.shared(libraryPath: first.libraryPath + ".other")
        }
        #expect(try RuntimeShaderCompiler.shared(libraryPath: first.libraryPath).libraryPath == first.libraryPath)
    }

    /// **13b.** Sixteen threads resolving through a **fresh** process cache load once: the first-load race, which
    /// 13 cannot see (the compiler is loaded before its tasks start). Mutation: `ProcessCache.resolve` drops its lock.
    @Test(.enabled(if: RuntimeShaderSupport.available, needsCompiler))
    func sixteenThreadsOnAFreshCacheLoadOnce() async throws {
        let environment = RuntimeShaderSupport.environment
        let cache = RuntimeShaderCompiler.ProcessCache(attempts: { explicit in
            RuntimeShaderCompiler.libraryAttempts(
                explicit: explicit, environment: environment, executableDirectory: nil,
                windows: RuntimeShaderCompiler.isWindows, macOS: RuntimeShaderCompiler.isMacOS,
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                directoryExists: { var d: ObjCBool = false
                    return FileManager.default.fileExists(atPath: $0, isDirectory: &d) && d.boolValue })
        })
        let before = RuntimeShaderCompiler.loadCount
        let paths = LockedBox<[String]>([])
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            if let compiler = try? cache.resolve(explicit: nil) { paths.mutate { $0.append(compiler.libraryPath) } }
        }
        #expect(paths.value.count == 16, "every resolve answered: \(paths.value.count)")
        #expect(Set(paths.value).count == 1)
        #expect(RuntimeShaderCompiler.loadCount - before == 1, "counted loads: \(RuntimeShaderCompiler.loadCount - before)")
    }

    /// **14.** Eight threads compile different kernels to their own serial bytes (`RC-S`). Mutation: one static
    /// output buffer in `CShaderCross.c`.
    @Test(.enabled(if: RuntimeShaderSupport.available, needsCompiler))
    func eightThreadsCompileDifferentKernelsToTheirOwnSerialBytes() async throws {
        let compiler = try RuntimeShaderCompiler.shared()
        let compile: @Sendable (Int) throws -> [UInt8] = { k in
            try compiler.compileCompute(hlsl: RuntimeShaderSupport.scaleKernel, defines: [try RuntimeShaderDefine("K", String(k + 2))],
                                        target: .spirv).bytes
        }
        let serial = try (0..<8).map(compile)
        #expect(Set(serial).count == 8, "the eight kernels differ")
        let parallel = await withTaskGroup(of: (Int, [UInt8]?).self) { group in
            for k in 0..<8 { group.addTask { (k, try? compile(k)) } }
            var out = [[UInt8]?](repeating: nil, count: 8)
            for await (k, bytes) in group { out[k] = bytes }
            return out
        }
        for k in 0..<8 { #expect(parallel[k] == serial[k], "thread \(k) got another kernel's bytes") }
    }

    /// **15.** Defines change the compiled kernel; a bare `-DFLAG` selects an `#ifdef` branch. Mutation: defines not passed.
    @Test(.enabled(if: RuntimeShaderSupport.available, needsCompiler))
    func definesChangeTheCompiledKernel() throws {
        let compiler = try RuntimeShaderCompiler.shared()
        func scale(_ k: String) throws -> [UInt8] {
            try compiler.compileCompute(hlsl: RuntimeShaderSupport.scaleKernel, defines: [try RuntimeShaderDefine("K", k)], target: .spirv).bytes
        }
        #expect(try scale("2") != scale("3"))
        let plain = try compiler.compileCompute(hlsl: RuntimeShaderSupport.flagKernel, target: .spirv).bytes
        let flagged = try compiler.compileCompute(hlsl: RuntimeShaderSupport.flagKernel, defines: [try RuntimeShaderDefine("FLAG")],
                                                  target: .spirv).bytes
        #expect(plain != flagged, "a bare define reaches the preprocessor")
    }

    /// **16a.** The self test names the library and the target and requires DXC's text. Mutation: the broken-kernel arm skipped.
    @Test(.enabled(if: RuntimeShaderSupport.available, needsCompiler))
    func selfTestNamesTheLibraryTheTargetAndRequiresDiagnostics() throws {
        let compiler = try RuntimeShaderCompiler.shared()
        let report = try compiler.selfTest(target: .msl)
        #expect(report.libraryPath == compiler.libraryPath && report.target == .msl && report.entryPoint == "main0")
        #expect(report.compiledBytes > 0)
        #expect(report.notes.contains { $0.hasPrefix("a broken kernel's diagnostics:") }, "\(report.notes)")
        let viaStatic = try RuntimeShaderCompiler.selfTest(target: .spirv)
        #expect(viaStatic.target == .spirv && viaStatic.libraryPath == compiler.libraryPath)
    }

    /// **16b.** With the diagnostics emptied the self test fails. Mutation: the broken-kernel arm skipped.
    @Test(.enabled(if: RuntimeShaderSupport.available, needsCompiler))
    func selfTestFailsWhenTheDiagnosticsAreEmpty() throws {
        let compiler = try RuntimeShaderCompiler.shared()
        RuntimeShaderCompiler.testingEmptyDiagnostics(true)
        defer { RuntimeShaderCompiler.testingEmptyDiagnostics(false) }
        do { _ = try compiler.selfTest(); Issue.record("a self test passed with no diagnostics") }
        catch RuntimeShaderCompileError.compileFailed(_, let diagnostics) {
            #expect(diagnostics.contains("no message"), "\(diagnostics)")
        }
    }

    /// **17.** The run-time compile of the checked-in app shader gives the build tool's bytes when the library is
    /// the pin (`METALUI_SHADERCROSS_AT_PIN=1`), else the entry points and reflection only. Mutation: the C call
    /// gets entry point `"mainx"`.
    @Test(.enabled(if: RuntimeShaderSupport.available, needsCompiler))
    func aRuntimeCompileOfTheAppShadersMatchesTheBuildToolsBlobs() throws {
        let compiler = try RuntimeShaderCompiler.shared()
        let source = try String(contentsOf: RuntimeShaderSupport.appShaders.appendingPathComponent("append.comp.hlsl"), encoding: .utf8)
        for (target, ext, entry) in [(RuntimeShaderTarget.spirv, "spv", "main"), (.msl, "msl", "main0"), (.dxil, "dxil", "main")] {
            let kernel = try compiler.compileCompute(hlsl: source, target: target)
            #expect(kernel.entryPoint == entry, "\(ext)")
            #expect(kernel.reflection.readWriteStorageBuffers == 1 && kernel.reflection.uniformBuffers == 1 && kernel.reflection.threadCountX == 64, "\(ext)")
            if RuntimeShaderSupport.atPin {
                let expected = [UInt8](try Data(contentsOf: RuntimeShaderSupport.appShaders.appendingPathComponent("compiled/append.comp.\(ext)")))
                #expect(kernel.bytes == expected, "\(ext): \(kernel.bytes.count) bytes against the build tool's \(expected.count)")
            }
        }
    }

    #if canImport(Metal)
    /// **18.** The `.msl` of the control kernel builds an `MTLLibrary` with function `main0` (no dispatch: buffer
    /// slots follow SDL_GPU's convention). Mutation: report entry `main` for MSL.
    @Test(.enabled(if: RuntimeShaderSupport.available, needsCompiler))
    func theMSLRunsOnMetal() throws {
        let compiler = try RuntimeShaderCompiler.shared()
        let kernel = try compiler.compileCompute(hlsl: RuntimeShaderSupport.scaleKernel,
                                                 defines: [try RuntimeShaderDefine("K", "2")], target: .msl)
        let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device")
        let library = try device.makeLibrary(source: String(decoding: kernel.bytes, as: UTF8.self), options: nil)
        #expect(library.makeFunction(name: kernel.entryPoint) != nil, "main0 builds a function")
        #expect(kernel.entryPoint == "main0")
    }
    #endif
}

/// A value behind a lock, for a concurrent test's collected results.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ body: (inout Value) -> Void) { lock.lock(); defer { lock.unlock() }; body(&stored) }
}
