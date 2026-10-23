# Run-time HLSL compute shaders on SDL_GPU (XP-G25) — design

Item XP-G25 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), requested by MetalCreator's `xp-c` track
(`MetalCreator-xp-c/docs/superpowers/plans/2026-10-22-xp-c-sdl-gpu-meshing.md`, read only). Prefix `RC-`. Rulings:
[`../2026-10-22-sdl-gpu-runtime-shaders-decisions.md`](../2026-10-22-sdl-gpu-runtime-shaders-decisions.md). Record §151.
Branch `feat/sdl-gpu-runtime-shaders` from `63feea05`. Divergence labels 805–814 reserved: **none expected** (class M, `Backends/SDL`
is outside the census, `GA-L`). Continues `GA-F` (record 114), `GB-G` (record 137), `BS-` (record 138), `SY-` (record 143).

**Sources of truth.** SwiftUI has no GPU or shader API, so no SwiftUI claim is made and no SwiftUI probe is owed. gpui compiles its
Metal shaders in a `build.rs` and has no run-time shader compiler for its own renderer (recalled; not on this machine), so it is
context only. Every shadercross fact below comes from the **pinned source and header** (`1ff05bec573988a98ef9e0260b4da44f512b8367`,
`include/SDL3_shadercross/SDL_shadercross.h`, `src/SDL_shadercross.c`, read 2026-10-22) and from the probe
`docs/probes/sdl-shadercross-runtime.c`, run against a **local build of the pin** (recorded in the decisions doc).

## 1. What MetalCreator needs, and the gap

`MetalImplicitEngine` writes one compute kernel per implicit solid and compiles it when the solid changes. `SDLGPUShaderBlob` has no
public initializer and is only loaded from a directory of build-time blobs (`SDLGPUShaderLibrary`), so on SDL_GPU a generated kernel cannot be
run at all. The user ruled that xp-c follows macOS: **generate HLSL, compile it in the running app, on Linux and Windows**, no precompiled
interpreter fallback. This item is the MetalUI half: *HLSL text in, a compute pipeline out, in the running process*.

## 2. Public API (all in `MetalUISDLGPU`, class M, under the `SDL` trait, nothing in the census)

New file `SDLGPUShaderCompiler.swift` (lane B; `SDLGPUShaderBlob` and `SDLGPUDevice` are **extended, not edited**: no edit of
`SDLGPUDevice.swift` or `SDLGPUShaderLibrary.swift`, so the sibling `feat/sdl-gpu-device-info` merges clean).

```swift
public struct SDLGPUShaderCompiler: Sendable {
    /// The compiler for the process, loaded on first use (RC-B). Throws .compilerUnavailable (lists every path tried).
    public static func shared(libraryPath: String? = nil) throws -> SDLGPUShaderCompiler
    public static var isAvailable: Bool { get }                  // shared() succeeds; never throws, never traps
    public let libraryPath: String                               // what was loaded
    public func compileCompute(name: String, hlsl: String, entryPoint: String = "main",
                               defines: [SDLGPUShaderDefine] = [], includeDirectory: String? = nil,
                               target: SDLGPUShaderTarget) throws -> SDLGPUShaderBlob
    public func compileCompute(name:hlsl:entryPoint:defines:includeDirectory:for device: SDLGPUDevice) throws -> SDLGPUShaderBlob
    public func selfTest(for device: SDLGPUDevice?) throws -> SDLGPUShaderCompilerReport   // RC-J
}
public struct SDLGPUShaderDefine: Sendable, Hashable { public init(_ name: String, _ value: String? = nil) throws }
public enum SDLGPUShaderTarget: Sendable { case spirv, msl, dxil; public init(driver: String) throws }   // vulkan, metal, direct3d12
public enum SDLGPUShaderCompileError: Error, CustomStringConvertible, Sendable {
    case compilerUnavailable(tried: [String])        // each "path: reason"
    case invalidInput(String)                        // empty source, bad define, bad entry point, NUL byte
    case unsupportedTarget(String)                   // a driver with no compiled format (RC-F)
    case compileFailed(stage: String, diagnostics: String)   // "HLSL to SPIR-V", "SPIR-V to MSL", "HLSL to DXIL"; DXC's text
    case malformedReflection(String)                 // names the field
}
public struct SDLGPUShaderCompilerReport: Sendable { driver, format, libraryPath, compiledBytes, entryPoint, seconds, notes }

extension SDLGPUShaderBlob {   // loading from bytes (RC-E)
    public init(name: String, stage: Stage, bytes: [UInt8], format: SDLGPUShaderBlob.Format, entryPoint: String,
                samplers: Int = 0, readOnlyStorageTextures: Int = 0, readOnlyStorageBuffers: Int = 0,
                readWriteStorageTextures: Int = 0, readWriteStorageBuffers: Int = 0, uniformBuffers: Int = 0,
                threadCount: (x: Int, y: Int, z: Int)) throws   // throws SDLGPUShaderCompileError.malformedReflection / invalidInput
}
extension SDLGPUDevice {
    public func compileComputePipeline(hlsl: String, name: String, entryPoint: String = "main",
                                       defines: [SDLGPUShaderDefine] = []) throws -> SDLGPUComputePipeline   // shared compiler + for: self + compileComputePipeline(blob)
}
```

`SDLGPUShaderBlob.Format` is a new `public enum { spirv, msl, dxil }` whose `rawValue` is the `SDL_GPUShaderFormat` bit converted
explicitly (Windows `Int32`); the existing `format: UInt32` member stays (additive). Everything is `nonisolated`; a compile
takes tenths of a second to seconds (RC-H measurements), so **call it off the main actor**; it is documented, never trapped.
Graphics stages are **not** built (RC-L; owner: the first app that asks).

## 3. Implementation

**Loading (RC-B, RC-C).** One C file `Backends/SDL/Sources/SDLBridge/SDLShaderCross.c` (+ header `include/SDLShaderCross.h`; `SDLBridge`
already depends on `CSDL`): our own mirror structs of the five shadercross structs we call (`SDL_ShaderCross_HLSL_Info`,
`_HLSL_Define`, `_SPIRV_Info`, `_ComputePipelineMetadata`, enums as `int`), loaded with `SDL_LoadObject` / `SDL_LoadFunction`
(cross-platform, SDL3 is already linked) so **no shadercross header or library is needed to build MetalUI** and no `pkgConfig:` is added
(PX-J). The C file exposes `mui_sc_load(path)`, `mui_sc_compile_spirv`, `mui_sc_compile_dxil`, `mui_sc_msl`, `mui_sc_reflect`, each returning
a malloc'd result plus the error text read with **the app's own `SDL_GetError()` on the calling thread** (RC-D), and `mui_sc_loads`
(a recorder: how many times the library was loaded, for the one-load pin). Windows: before `SDL_LoadObject` the C file calls
`SetDllDirectoryW` for the library's directory so `dxcompiler.dll` and `dxil.dll` beside it resolve (compiled by CI only).
**Dependents are preloaded by full path first** (`RuntimeLibraryLocator.preloadSet`, RC-N: the pin's install has no rpath, so a full-path load alone fails, measured). No `SDL_ShaderCross_Quit` is ever called and the library is never unloaded (DXC cannot be unloaded safely).

**Lookup order (RC-C).** Pure Swift in `MetalUIShaderCompile` (portable, `package`, no SDL trait; lane A): `RuntimeLibraryLocator.candidates(
explicit:environment:executableDirectory:windows:macOS:)`: (1) the `libraryPath:` argument, (2) `METALUI_SHADERCROSS_LIB` (a file, or a directory that holds the
platform's library name), (3) beside the executable and `../lib` of it, (4) the sibling `lib` of the `METALUI_SHADERCROSS` executable (the pin's install layout, `BS-C`),
(5) the plain name on the loader path (`libSDL3_shadercross.dylib` / `libSDL3_shadercross.so.0` then `.so` / `SDL3_shadercross.dll`). **An explicit path or variable that
names a missing file is an error, never a fall-through** (as `BS-C`); with none found the error names every path tried with its reason.

**Compile path (RC-F, RC-G).** SPIR-V target: `SDL_ShaderCross_CompileSPIRVFromHLSL`. MSL: that SPIR-V, then `TranspileMSLFromSPIRV` (entry `main0`).
DXIL: `CompileDXILFromHLSL` (the build tool's own route, so bytes agree with a checked-in blob). **Reflection always comes from the SPIR-V**
(`ReflectComputeSPIRV`), so a DXIL or MSL compile also runs HLSL to SPIR-V once. The SPIR-V is validated (magic, whole words) and the reflection
validated by the same code the bytes initializer uses; compute only (`SDL_SHADERCROSS_SHADERSTAGE_COMPUTE`). Compiles are **not serialized** (RC-D: the pinned source
makes a DXC instance per call, "since the functions we call on it are not thread-safe"); the one `SDL_ShaderCross_Init` is under a lock.
Diagnostics: `SDL_GetError()` carries DXC's text (`"HLSL compilation failed: …"`); warnings go to `SDL_LogWarn` and are not captured (RC-I).

**Loading from bytes (RC-E).** `SDLGPUShaderBlob.init(…) throws` validates: non-empty bytes, entry point non-empty, SPIR-V (magic `0x07230203`, length % 4),
DXIL (`DXBC` container), MSL (UTF-8 containing the entry point); compute needs every thread-group axis >= 1 and x*y*z <= 1024, every count within
`0...64` (a **sanity bound**, not SDL's limits: `SDL_gpu.h` at SDL 3 documents no per-kind maximum, so a count SDL or the driver refuses still throws from `compileComputePipeline` naming the stage, GB-G; RC-E).
`makeComputePipeline(_:)`/`compileComputePipeline(_:)` are **unchanged** and take the result (GB-G: a pipeline refusal still throws naming the stage).

**Self test (RC-J).** `SDLGPUShaderCompiler.selfTest(for:)` loads, compiles a four-line kernel, compiles a deliberately broken one and requires
non-empty diagnostics (detects a second SDL instance, RC-D), and with a device builds the pipeline and runs one dispatch with a readback; the report names the driver,
the format and the library path. Without the library it **throws `compilerUnavailable`** (an app's `--self-test` fails naming what to ship).

## 4. Files and lanes (at most two, disjoint)

**Lane A (pure, portable; `Backends/SDL/Sources/MetalUIShaderCompile` + its tests; cheap):**
- `RuntimeLibraryLocator.swift` (the lookup order, platform names, the error text with reasons) and `ComputeBlobValidation.swift` (the blob and reflection checks above, as
  `package` pure functions over plain values, the counts' limits, SPIR-V/DXIL/MSL byte checks, the define and entry-point checks, `target(forDriver:)`).
- `Tests/MetalUIShaderCompileTests/RuntimeLibraryLocatorTests.swift`, `ComputeBlobValidationTests.swift` (**the root test target**, `Package.swift` line 288: the root count moves from 4371 by exactly lane A's test count, RC-Q).
- **Lane A also owns the long, independent measurement work** (RC-R): building shadercross in the Linux image volume `metalui-shadercross-sdl-gpu-runtime-shaders`, the probe arms A-I there (glibc SONAME/preload, arm H), `docs/probes/runtime-compile-measure.sh`, `docs/packaging.md` §4b and `THIRD-PARTY-NOTICES.md`, so lane B is only the shim, Swift API and its tests.

**Lane B (SDL; `MetalUISDLGPU`, `SDLBridge`, tests, packaging):**
- `SDLBridge/SDLShaderCross.c` and its declarations **appended to `include/SDLBridge.h`** (the target's one umbrella header; a second header in `include/` is not exposed to Swift, RC-Q); `MetalUISDLGPU/SDLGPUShaderCompiler.swift` (types, load, compile, selfTest), `SDLGPUShaderBlob+Bytes.swift`,
  `SDLGPUDevice+RuntimeCompile.swift`; `Backends/SDL/Tests/MetalUISDLTests/SDLGPURuntimeCompilerTests.swift`, `SDLGPURuntimeCompilerGatedTests.swift`, `SDLGPURuntimeCompileGuardTests.swift`.
- Lane B depends on lane A's validation and locator (`package` symbols in `MetalUIShaderCompile`, already a dependency of `MetalUISDLGPU`): **A lands first**; B's first commit
  is the C shim and loader, which needs none of A.
- Neither lane edits `SDLGPUDevice.swift`, `SDLGPUShaderLibrary.swift`, `Package.swift` (the C file joins an existing target; a new test file joins an existing test target) or the root `Sources/`.

## 5. Tests (name, red before, the mutation that must redden it)

All names are Swift Testing functions; "pure" runs everywhere with no GPU and no library. **Red before** is the missing symbol unless stated. Each mutation is applied to one
spelling, the full unfiltered suites (root native, `Backends/SDL`) are run, the tests reddened are named in the record.

*Lane A, pure (`MetalUIShaderCompileTests`):*
1. `theLookupOrderIsExplicitThenVariableThenBesideThenSiblingThenLoaderPath` — swap the variable and explicit candidates.
2. `anExplicitPathThatDoesNotExistIsAnErrorAndNotAFallThrough` — `continue` past a missing explicit path.
3. `aVariableNamingADirectoryFindsThePlatformLibraryInIt` — drop the directory join.
4. `theShadercrossExecutableVariableOffersItsSiblingLibDirectory` — look in `bin` instead of `../lib`.
5. `theErrorNamesEveryPathTriedWithItsReason` — drop one candidate's reason.
6. `thePlatformLibraryNamesAreDylibSoAndDll` — return the `.so` name on macOS.
7. `aZeroThreadAxisIsRefusedByName`, `aThreadGroupOf1025InvocationsIsRefused` and `aThreadGroupOf1024InvocationsIsAccepted` — compare `> 1025`.
8. `everyCountOverItsLimitIsRefusedNamingTheField` (one arm per field) — skip the uniform-buffer arm.
9. `emptyBytesAnEmptyEntryPointAndAGraphicsStageAreRefused` — accept empty bytes.
10. `spirvMustHaveItsMagicAndWholeWords`, `dxilMustBeADXBCContainer`, `mslMustContainItsEntryPoint` — test the wrong magic byte order.
11. `aDefineNameMustBeAnIdentifierAndNoValueMayHoldANUL`, `twoDefinesWithOneNameAreRefused`.
12b. `thePreloadSetIsTheDependentsInTheLibrarysDirectory` (dxcompiler, spirv-cross required, dxil optional, unrelated files ignored) — preload nothing.
12. `aDriverMapsToItsFormatAndAnyOtherIsUnsupportedNamingIt` (vulkan, metal, direct3d12, "gpu"?) — map `metal` to spirv.

*Lane B, always run (`SDLGPURuntimeCompilerTests`):*
13. `aMissingLibraryThrowsCompilerUnavailableListingEveryPathTried` — through the `package` seam `SDLGPUShaderCompiler.load(candidates:)` that never touches the process cache (RC-O); mutation: the empty list.
14. `everyCompileEntryThrowsCompilerUnavailableWithoutTheLibrary` (compile, device form, selfTest, `isAvailable`) over a compiler value built from the seam's failure — one entry skips the check. A call with an explicit path differing from the loaded library throws `libraryAlreadyLoaded` (RC-O).
15. `theBlobInitializerMakesAPipelineFromTheCheckedInAppShaderBytes` (GPU; reads `AppShaders/compiled` bytes and JSON, builds the blob through the new initializer, `compileComputePipeline` succeeds) — wrong threadCount.y mapping.
16. `aMalformedReflectionThrowsBeforeSDLIsCalled` (a recorder: zero `SDL_CreateGPUComputePipeline` calls) — validate after the SDL call.
17. `theBlobInitializerKeepsEveryCountItWasGiven` — swap read-only and read-write buffer counts (the existing `compileComputePipeline` reads those fields).

*Lane B, gated on the library (`METALUI_SHADERCROSS_LIB`, or found by the lookup; skip reason names the paths; `METALUI_REQUIRE_SHADERCROSS=1` turns a skip into a failure — Linux CI jobs that build it set it; a CI job that builds shadercross is **not** added, `BS-G` stays carried):*
18. `aValidKernelCompilesToTheDevicesFormatWithItsReflection` (SPIR-V reflection counts and thread group equal `AppShaders/compiled`'s JSON) — drop the readwrite count.
19. `aRuntimeCompileOfTheAppShadersMatchesTheBuildToolsBlobs` (`METALUI_SHADERCROSS_AT_PIN=1` only: SPIR-V, MSL and, with dxil, DXIL bytes equal; otherwise reflection only) — pass `entryPoint` wrong.
20. `aSyntaxErrorThrowsCompileFailedWithDXCsText` (contains `HLSL compilation failed` and a line number) — never read `SDL_GetError`.
21. `aCompiledKernelDispatchesAndReadsBack` (GPU too; 256 words doubled; **macOS Metal via MSL, Linux lavapipe via SPIR-V**) — hand the MSL reflection's thread count 1.
22. `definesChangeTheCompiledKernel` (`-DK=3` versus `-DK=5` read back) — ignore defines.
23. `aSecondSharedCallReusesTheFirstLoad` (`mui_sc_loads == 1` after N calls from several threads) — load per call.
24. `eightThreadsCompileDifferentKernelsToTheirOwnSerialBytes` (SPIR-V; thread i compiles the kernel with `-DK=i`, each result equals the serial result for that K; RC-S) — mutation: one static output buffer in the C shim (identical-kernel threads could not see it).
25. `selfTestNamesTheDriverTheFormatAndTheLibrary` (GPU) and `selfTestFailsWhenTheDiagnosticsAreEmpty` (the C shim's test hook empties `SDL_GetError` text) — skip the broken-kernel arm.
26. `aKernelOf200And1000LinesCompiles` (always counted; the **timings are recorded by `runtime-compile-measure.sh`, never asserted**).
27. `aWarningOnlyKernelStillCompiles` (an unused variable) — treat a log warning as failure.

**Guard (RC-P).** A root typecheck fixture cannot import `MetalUISDLGPU` (it exists only under the `SDL` trait; `SDLGPUContractTests` D3's own note), so: `SDLGPURuntimeCompileGuardTests.swift` is a separate file with a **plain** `import MetalUISDLGPU` (no `@testable`) that calls `SDLGPUShaderCompiler.shared()`, `compileCompute`, the bytes initializer and `device.compileComputePipeline(hlsl:name:)` (compile-time proof they are public), plus a source scan that `RuntimeLibraryLocator`, `ComputeBlobValidation` and every `mui_sc_*` use are not `public`. Mutations, each once: make `RuntimeLibraryLocator` public (scan red); make the bytes initializer `internal` (plain-import file fails to compile: recorded as a build failure, then reverted).

## 6. Packaging, notices, speed (lane B, `docs/packaging.md` new §4b)

The files an app ships to compile at run time (read from the **install of the local build of the pin**, recorded in RC-K with sizes): `libSDL3_shadercross` (zlib), DXC's
`libdxcompiler` (the libsdl-org DXC fork's `LICENSE.TXT` read at the pin: **LLVM Release License, University of Illinois/NCSA Open Source License**, 2003-2015, with its own list of bundled third-party licences; not Apache-2.0), `libdxil` / `dxil.dll` (needed for DXIL output; whether the pinned fork signs without it is measured), SPIRV-Cross (Apache-2.0, read), SPIRV-Tools (Apache-2.0, read), SPIRV-Headers (Khronos MIT-style, read), shadercross itself zlib (read); SPIRV-Cross static or shared by
`SDLSHADERCROSS_SPIRVCROSS_SHARED`), Placement: Linux tarball `lib/` beside `bin/` (rpath `$ORIGIN/../lib`, verified with `readelf -d`/`ldd` in the image),
AppImage `usr/lib`, Windows zip beside the `.exe`, macOS `.app` `Contents/Frameworks` or `Contents/MacOS` (`@loader_path`, verified with `otool -L`). `THIRD-PARTY-NOTICES.md` gains a
"run-time shader compiler (optional, not vendored)" section. **Nothing is published or vendored** (BS-H).
Speed: `docs/probes/runtime-compile-measure.sh` records, dated, HLSL to SPIR-V, to MSL and to DXIL for ~200, ~1000 and ~2000 line kernels on this Mac (the designer's probe run has the first
figures, RC-H) and in the Linux aarch64 image (SPIR-V; shadercross built there into a Docker volume named for this slug).

## 7. Demo, human checks, what does not move

No demo section (a library capability; the compiled twin of the recipe is `selfTest`). **Human checks, group `RC` (added at the Record phase):** RC1 a Windows x64 machine with
`dxcompiler.dll` and `dxil.dll` beside the exe compiles and dispatches (CI compiles the Swift only); RC2 a Linux tarball and an AppImage find the library from `$ORIGIN`;
RC3 `--self-test` on a machine **without** the library prints the named error and exits non-zero; RC4 a desktop GPU's compile time for MetalCreator's real ~1000-line kernel;
RC5 a macOS `.app` with the libraries in `Contents/Frameworks` launches from Finder (library validation / hardened runtime may refuse an unsigned dylib).
Pixels 0 px against `63feea05` (no rendering code touched), `Expected.swift` unedited, no root `Sources/` change (the root suite is 4371 + lane A's tests, RC-Q), `Package.swift` unedited.

## 8. Deferred, by name

- **Graphics-stage run-time compile** (RC-L): no consumer; owner the first app that asks; `SDL_ShaderCross_ReflectGraphicsSPIRV` exists at the pin.
- **A CI job that builds shadercross** (BS-G stays carried): 7-10 minutes of DXC on every run; env-gated tests cover it where a developer has a build.
- **Capturing DXC warnings** (RC-I): they go to `SDL_LogWarn`; capturing needs a process-wide log hook.
- **A compile cache on disk** (RC-M): the app's job (it owns the source hash and the directory); MetalUI offers the bytes initializer to load a cached blob.
- **`#include` resolution beyond one include directory**, **debug info properties** (`SDL_SHADERCROSS_PROP_*`): not needed by the consumer.
