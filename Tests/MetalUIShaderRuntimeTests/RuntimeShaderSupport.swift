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

// Run-time HLSL compile without the `SDL` trait (item XP-G27, rulings HX-A..HX-K; spec section 7).
// Gated tests need the shader compiler library (`METALUI_SHADERCROSS_LIB`); `METALUI_REQUIRE_SHADERCROSS=1`
// turns a skip into a failure (the RC pattern). **One serialized suite** (`RuntimeShaderTests`): the
// process cache is global and a test that swaps it must not overlap one that reads it.

enum RuntimeShaderSupport {
    static let environment = ProcessInfo.processInfo.environment
    /// `METALUI_SHADERCROSS_LIB` set **and** `shared()` succeeding (loads the process compiler on first read).
    static let available: Bool = {
        guard let value = environment["METALUI_SHADERCROSS_LIB"], !value.isEmpty else { return false }
        return RuntimeShaderCompiler.isAvailable
    }()
    static let required = environment["METALUI_REQUIRE_SHADERCROSS"] == "1"
    static let atPin = environment["METALUI_SHADERCROSS_AT_PIN"] == "1"
    static var lastFailureText: String {
        do { _ = try RuntimeShaderCompiler.shared(); return "" } catch { return String(describing: error) }
    }

    /// The control kernel of `RC-H`: doubles `src` into `dst` times `K` (a define).
    static let scaleKernel = """
        StructuredBuffer<uint> src : register(t0, space0);
        RWStructuredBuffer<uint> dst : register(u0, space1);
        cbuffer P : register(b0, space2) { uint n; };
        [numthreads(64, 1, 1)]
        void main(uint3 id : SV_DispatchThreadID) { if (id.x < n) dst[id.x] = src[id.x] * K; }
        """
    /// A kernel whose body depends on a bare `-DFLAG`.
    static let flagKernel = """
        RWStructuredBuffer<uint> dst : register(u0, space1);
        [numthreads(8, 1, 1)]
        void main(uint3 id : SV_DispatchThreadID) {
        #ifdef FLAG
            dst[id.x] = id.x * 7u + 1u;
        #else
            dst[id.x] = id.x;
        #endif
        }
        """
    static let brokenKernel = "[numthreads(1,1,1)] void main( { }\n"

    static let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    static var appShaders: URL { repositoryRoot.appendingPathComponent("Backends/SDL/Tests/AppShaders") }

    /// The dynamic library suffix of this platform, for decoy files.
    static var librarySuffix: String {
        if RuntimeShaderCompiler.isWindows { return ".dll" }
        return RuntimeShaderCompiler.isMacOS ? ".dylib" : ".so"
    }
    /// A library file name for `stem` (`lib` prefix off Windows).
    static func libraryFile(_ stem: String) -> String {
        (RuntimeShaderCompiler.isWindows ? "" : "lib") + stem + librarySuffix
    }
    /// The file name an SDL3 link takes beside shadercross (what `preloadSet` matches).
    static var sdl3LinkName: String {
        if RuntimeShaderCompiler.isWindows { return "SDL3.dll" }
        return RuntimeShaderCompiler.isMacOS ? "libSDL3.0.dylib" : "libSDL3.so.0"
    }
}

/// Attempts naming files that do not exist, plus one bare loader name no machine has.
func missingRuntimeAttempts() -> [RuntimeLibraryLocator.Attempt] {
    var attempts = RuntimeShaderCompiler.libraryAttempts(
        explicit: nil, environment: ["METALUI_SHADERCROSS": "/nonexistent/tool/bin/shadercross"],
        executableDirectory: "/nonexistent/app/bin", windows: false, macOS: true,
        fileExists: { _ in false }, directoryExists: { _ in false }).filter { $0.source != .loaderPath }
    attempts.append(RuntimeLibraryLocator.Attempt(path: "libmui_no_such_shadercross.dylib", source: .loaderPath,
                                                  exists: nil, reason: "left to the loader path (not checked)"))
    return attempts
}

let needsCompiler = Comment(rawValue: "needs the shader compiler library (METALUI_SHADERCROSS_LIB)")

@MainActor @Suite(.serialized) struct RuntimeShaderTests {}
