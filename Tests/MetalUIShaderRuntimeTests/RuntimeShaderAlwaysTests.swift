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

// Tests 1, 2, 3 and 6 of the spec (section 7): no library needed.

extension RuntimeShaderTests {
    /// **1.** A missing library is a thrown `compilerUnavailable` that lists every path tried with its reason.
    /// Mutation: `load(candidates:)` throws `tried: []`.
    @Test func aMissingLibraryThrowsCompilerUnavailableListingEveryPathTried() throws {
        let attempts = missingRuntimeAttempts()
        try #require(attempts.count >= 4)
        do {
            _ = try RuntimeShaderCompiler.load(candidates: attempts)
            Issue.record("a missing library loaded")
        } catch RuntimeShaderCompileError.compilerUnavailable(let tried) {
            #expect(tried.count == attempts.count, "one line per attempt: \(tried)")
            for attempt in attempts { #expect(tried.contains { $0.hasPrefix(attempt.path + ":") }, "\(attempt.path) is named") }
            #expect(tried.contains { $0.contains("no such file") })
            #expect(tried.contains { $0.hasPrefix("libmui_no_such_shadercross.dylib:") && $0.contains("failed to load") }, "\(tried)")
        }
    }

    /// **2.** With an empty lookup every entry answers `compilerUnavailable`. Mutation: the static `selfTest`
    /// returns a report when `shared()` fails.
    @Test func everyEntryThrowsCompilerUnavailableWithoutTheLibrary() async throws {
        let cache = RuntimeShaderCompiler.ProcessCache(attempts: { _ in missingRuntimeAttempts() })
        var failures: [String] = []
        await RuntimeShaderCompiler.withProcessCache(cache) {
            func check(_ name: String, _ body: () throws -> Void) {
                do { try body(); failures.append("\(name) did not throw") }
                catch RuntimeShaderCompileError.compilerUnavailable {} catch { failures.append("\(name) threw \(error)") }
            }
            check("shared()") { _ = try RuntimeShaderCompiler.shared() }
            if RuntimeShaderCompiler.isAvailable { failures.append("isAvailable is true") }
            check("selfTest") { _ = try RuntimeShaderCompiler.selfTest() }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    /// **3.** A decoy library fails with the loader's text, not a trap, and the dependents are preloaded first
    /// (the line names a dependent). Mutation: `mui_rsc_load` skips the preload loop.
    @Test func aDecoyLibraryFailsWithTheLoadersTextNotATrap() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mui-hx-decoy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let names = ["SDL3_shadercross", "dxcompiler", "spirv-cross-c-shared"].map(RuntimeShaderSupport.libraryFile)
        for name in names { try Data().write(to: directory.appendingPathComponent(name)) }
        let path = directory.appendingPathComponent(names[0]).path
        let attempt = RuntimeLibraryLocator.Attempt(path: path, source: .explicit, exists: true, reason: "a decoy")
        do {
            _ = try RuntimeShaderCompiler.load(candidates: [attempt])
            Issue.record("a zero-byte library loaded")
        } catch RuntimeShaderCompileError.compilerUnavailable(let tried) {
            let line = try #require(tried.first)
            #expect(line.hasPrefix(path + ": failed to load: "), "\(line)")
            #expect(line.contains("failed to load dependent"), "the preload ran first: \(line)")
        }
    }

    /// **6.** In a fresh process the default build holds no SDL3 before the first load, and preloading one
    /// (`METALUI_SDL3_LIB`, when set) with `RTLD_GLOBAL` is seen. Mutation: `mui_rsc_process_has_sdl3` returns a constant.
    @Test func theDefaultBuildProcessHasNoSDL3BeforeTheFirstLoad() async {
        #if os(Windows)
        return
        #else
        await #expect(processExitsWith: .success) {
            #expect(!RuntimeShaderCompiler.processHasSDL3, "a fresh test process links no SDL3")
            if let path = ProcessInfo.processInfo.environment["METALUI_SDL3_LIB"], !path.isEmpty {
                #expect(dlopen(path, RTLD_NOW | RTLD_GLOBAL) != nil, "\(path) loads")
                #expect(RuntimeShaderCompiler.processHasSDL3, "a global SDL3 is seen")
            }
        }
        #endif
    }
}
