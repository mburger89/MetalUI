# Run-time HLSL compile without the `SDL` trait (XP-G27) - design

**Status:** designed, not built. Rulings: [`../2026-10-28-runtime-compile-no-sdl-decisions.md`](../2026-10-28-runtime-compile-no-sdl-decisions.md) (`HX-A`...). Record: `../../record/160-runtime-compile-no-sdl.md` (Record phase).
Branch `feat/runtime-shader-compile` from `3c9dc9a4`. Item XP-G27 (low; user said go, 2026-10-28), from MetalCreator `xp-c`. Supersedes `SX-E` (carried) with the measurement it asked for (`HX-B`).
Class `M`, MetalUI-only: SwiftUI and gpui have no run-time shader compiler (no SwiftUI claim, no probe). Divergence labels 885-894 reserved, **none taken**. Nothing published (`BS-H`).
No `Handlers`, seam, shader, `Window` or `PlatformWindow` change.

## 1. Behaviour

A macOS app built **without** the `SDL` trait (the default build) compiles HLSL compute source in the running process to SPIR-V, MSL (entry `main0`) or DXIL, with the compute reflection
(counts and thread group), through the same pinned SDL_shadercross shared library that `SDLGPUShaderCompiler` loads (`RC-B`), with **one implementation and one load per process** shared by both
APIs (`HX-C`, `HX-E`). The process need not link SDL3: shadercross's own SDL3 is loaded by full path from the shadercross directory (or found by shadercross's load command), and the three SDL calls the
compiler needs (`SDL_GetError`, `SDL_ClearError`, `SDL_free`) are resolved **through the shadercross library's own handle**, so they are always the instance shadercross itself calls (`HX-D`).
An absent library is the thrown `compilerUnavailable(tried:)` naming every path, never a trap (`RC-C`, unchanged lookup). Under the `SDL` trait, `SDLGPUShaderCompiler` keeps every public
spelling and behaviour and forwards to the new type; the RC tests do not change (`HX-F`).

## 2. Targets and products (`HX-C`)

| Target | Path | Kind | PC-A list | Imports | Product |
|---|---|---|---|---|---|
| `CShaderCross` | `Sources/CShaderCross` (`CShaderCross.c`, `include/CShaderCross.h`) | C | **every platform** | libc, `<dlfcn.h>` (POSIX), `<windows.h>` (Windows); **no SDL or shadercross header** | none (internal) |
| `MetalUIShaderRuntime` | `Sources/MetalUIShaderRuntime` | Swift | **every platform** | Foundation, `internal import CShaderCross`, `MetalUIShaderCompile` (package locator and validation) | **`MetalUIShaderRuntime`** (library) |
| `MetalUIShaderRuntimeTests` | `Tests/MetalUIShaderRuntimeTests` | test | every platform | `MetalUIShaderRuntime`, `MetalUIShaderCompile`, `MetalUITestSupport` | - |

Manifest edits (`Package.swift`, the every-platform list, beside `MetalUIShaderCompile`):

- `.target(name: "CShaderCross", linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))])` (glibc below 2.34 keeps `dlopen` in `libdl`; harmless above).
- `.target(name: "MetalUIShaderRuntime", dependencies: ["CShaderCross", "MetalUIShaderCompile"])`.
- `.testTarget(name: "MetalUIShaderRuntimeTests", dependencies: ["MetalUIShaderRuntime", "MetalUIShaderCompile", "MetalUITestSupport"])`.
- products: `.library(name: "MetalUIShaderRuntime", targets: ["MetalUIShaderRuntime"])` with a comment naming `HX-C` (optional; `MetalUI` does not depend on it, an app that never compiles links none of it).
- `MetalUISDLGPU` gains the dependency `"MetalUIShaderRuntime"`; `SDLBridge` gains `"CShaderCross"` (for the two forwarders, section 5).

`MetalUIShaderRuntime` is a root `Sources/` target in a library product, so it **joins the census**: `docs/probes/closeout-public-api.sh` `TARGETS` gains it, `closeout-inventory-map.tsv` gains one `F` row
(`runtime-shader-compile`, class `M`, rulings `HX-A HX-C HX-D HX-E HX-G`) and one `M` row `M	MetalUIShaderRuntime	.*	.*	.*	.*	runtime-shader-compile`; the recorded `closeout-public-api.tsv` is re-taken.
`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

## 3. The C target `CShaderCross` (the one implementation, `HX-C`)

Moved from `Backends/SDL/Sources/SDLBridge/SDLShaderCross.c` and generalised; the body of every call is today's, the only differences are where the library and the three SDL functions come from.

```c
// include/CShaderCross.h
typedef struct MuiRSC MuiRSC;                       // never freed: a library is never unloaded (RC-B)
typedef struct { uint32_t samplers, readonly_storage_textures, readonly_storage_buffers,
                 readwrite_storage_textures, readwrite_storage_buffers, uniform_buffers,
                 threadcount_x, threadcount_y, threadcount_z; } MuiRSCReflection;
// 1 when an SDL3 is already in the process (POSIX: dlsym(RTLD_DEFAULT, "SDL_GetVersion") != NULL;
// Windows: GetModuleHandleW(L"SDL3.dll") != NULL). Decides whether the SDL3 preload group runs (HX-D).
bool mui_rsc_process_has_sdl3(void);
// Loads `preload` (full paths, in order) then `path` with RTLD_NOW|RTLD_LOCAL (LoadLibraryW on Windows,
// after SetDllDirectoryW(directory of path) exactly as today), resolves the five shadercross functions
// and SDL_GetError / SDL_ClearError / SDL_free THROUGH THE SHADERCROSS HANDLE (POSIX dlsym on the handle
// searches its dependency tree; Windows: GetProcAddress on the SDL3.dll module the loader bound,
// GetModuleHandleW(L"SDL3.dll") after the load), runs SDL_ShaderCross_Init once per process (atomic).
// NULL on failure with the loader's text (dlerror / FormatMessageW) or the missing symbol in `error`.
MuiRSC *mui_rsc_load(const char *path, const char *const *preload, uint32_t preload_count,
                     bool counted, char *error, size_t error_capacity);
int32_t mui_rsc_loads(void);                         // counted loads in this process (RC-O read-back)
int32_t mui_rsc_compile_hlsl(const MuiRSC *, int32_t target /*0 spirv, 1 dxil*/, const char *source,
                             const char *entry, const char *include_dir, const char *const *define_names,
                             const char *const *define_values, uint32_t define_count,
                             uint8_t **out, size_t *out_size, char *error, size_t error_capacity);
int32_t mui_rsc_msl(const MuiRSC *, const uint8_t *spirv, size_t size, const char *entry,
                    uint8_t **out, size_t *out_size, char *error, size_t error_capacity);
int32_t mui_rsc_reflect(const MuiRSC *, const uint8_t *spirv, size_t size, MuiRSCReflection *out,
                        char *error, size_t error_capacity);
void mui_rsc_free(const MuiRSC *, void *pointer);    // that instance's SDL_free
void mui_rsc_test_empty_diagnostics(bool empty);     // test hook (RC-J), unchanged meaning
```

Kept verbatim from `SDLShaderCross.c`: the mirror structs and their `_Static_assert`s (40/16/32/36 and the offsets, measured `RC-H` arm I and again `HX-B`), the NULL-terminated define array, error read
**before any other call** on the failing thread (`RC-D`), no static output buffer (`RC-S`), compiles not serialized, Init once under an atomic (`RC-X` 5), the "not SDL_shadercross at the pin: X is missing"
text, `mui_rsc_test_empty_diagnostics`. Atomics are C11 `<stdatomic.h>` (clang on every platform). Error texts on POSIX: a failed `dlopen` writes `dlerror()`; on Windows `FormatMessageW` of
`GetLastError()` converted to UTF-8, prefixed `LoadLibrary failed (<code>): `.

## 4. The public Swift API (`MetalUIShaderRuntime`, class M, `HX-G`)

Doc-comment text sketched; every declaration carries one (`closeout-undocumented.sh`).

```swift
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
    public var description: String { get }   // same texts as SDLGPUShaderCompileError's
}

/// One `-D` define. The name must be an identifier and no part may hold a NUL.
public struct RuntimeShaderDefine: Sendable, Hashable {
    public let name: String
    public let value: String?
    /// Validates the define (`RuntimeShaderCompileError.invalidInput` names the problem).
    public init(_ name: String, _ value: String? = nil) throws
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
    public init(driver: String) throws
}

/// The resource counts and thread group of a compute kernel, read from its SPIR-V (`RC-F`).
public struct ComputeShaderReflection: Sendable, Hashable {
    public let samplers: Int
    public let readOnlyStorageTextures: Int
    public let readOnlyStorageBuffers: Int
    public let readWriteStorageTextures: Int
    public let readWriteStorageBuffers: Int
    public let uniformBuffers: Int
    public let threadCountX: Int
    public let threadCountY: Int
    public let threadCountZ: Int
}

/// A compiled compute kernel: the target's bytes (MSL as UTF-8 text), its entry point in that format and its reflection.
public struct CompiledComputeShader: Sendable, Hashable {
    public let target: RuntimeShaderTarget
    public let bytes: [UInt8]
    public let entryPoint: String
    public let reflection: ComputeShaderReflection
}

/// What `RuntimeShaderCompiler.selfTest(target:)` found (`RC-J`).
public struct RuntimeShaderSelfTestReport: Sendable {
    public let libraryPath: String
    public let target: RuntimeShaderTarget
    public let compiledBytes: Int
    public let entryPoint: String
    /// Wall clock of the checks (a dated reading, never a pin).
    public let seconds: Double
    public let notes: [String]
}

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
    /// The compiler for the process, loaded on first use and reused (`RC-B`, `RC-O`).
    public static func shared(libraryPath: String? = nil) throws -> RuntimeShaderCompiler
    /// Whether `shared()` succeeds with the default lookup. Never throws, never traps.
    public static var isAvailable: Bool { get }
    /// Compiles HLSL compute source to `target` with its reflection (always from the SPIR-V; DXIL from HLSL, `RC-F`).
    public func compileCompute(hlsl: String, entryPoint: String = "main", defines: [RuntimeShaderDefine] = [],
                               includeDirectory: String? = nil, target: RuntimeShaderTarget) throws -> CompiledComputeShader
    /// Compiles a four-line kernel to `target` and a broken one, requiring DXC's text back (`RC-J`, `HX-D`).
    public func selfTest(target: RuntimeShaderTarget = .spirv) throws -> RuntimeShaderSelfTestReport
    /// `shared(libraryPath:)` then `selfTest(target:)`: an app's `--self-test` call.
    public static func selfTest(target: RuntimeShaderTarget = .spirv, libraryPath: String? = nil) throws -> RuntimeShaderSelfTestReport
}
```

**Package seams** (root-package tests and `MetalUISDLGPU` only; the plain-import guard keeps them unreachable): `RuntimeShaderCompiler.load(candidates: [RuntimeLibraryLocator.Attempt], counted: Bool = false) throws`,
`RuntimeShaderCompiler.ProcessCache` (`init(attempts:)`, `standard`, `current`, `swap(to:)`, `resolve(explicit:)`), `withProcessCache(_:_:)`, `emptyDiagnostics` (the text `RC-X` 4 fixed), and
`RuntimeShaderCompiler.libraryAttempts(...)`, and two read-backs on a loaded compiler: `preloaded: [String]` (the full paths loaded before the library, in order) and `processHadSDL3: Bool` (what `mui_rsc_process_has_sdl3()` answered at that load). `load` takes `processHasSDL3: Bool? = nil` (nil asks the C function; a test passes it). These are today's `SDLGPUShaderCompiler` members moved, with the error type changed; `load` gains one step: when `mui_rsc_process_has_sdl3()` is false, the
SDL3 group is added to the preload set (`HX-D`).

**`MetalUIShaderCompile`** (package, additive): `RuntimeLibraryLocator.preloadSet(directory:listing:windows:macOS:includingSDL: Bool = false)`. With `includingSDL`, an **optional first** group `sdl3`
(stem exactly `sdl3`: `libSDL3.0.dylib`, `libSDL3.dylib`, `libSDL3.so.0`, `SDL3.dll`; never `libSDL3_shadercross`, `libSDL3_test.a` or `SDL3_image`), every version symlink, shortest first, before
`dxcompiler`. Default `false` keeps today's set byte for byte.

## 5. `SDLGPUShaderCompiler` forwards (`HX-F`)

- `SDLGPUShaderCompiler` stores `let runtime: RuntimeShaderCompiler` (internal) instead of `Handle`; `libraryPath` is `runtime.libraryPath`. `shared`, `isAvailable`, `compileCompute` (both overloads),
  `selfTest` (both) keep their signatures and doc comments. `compileCompute` calls `runtime.compileCompute` and builds the `SDLGPUShaderBlob` from the result (same initializer as today, so `RC-E`'s validation still runs);
  `selfTest` calls `runtime.selfTest(target:)` for the compile and broken-kernel arms, then keeps its device dispatch arm and its report shape (`driver`, `format`, ...).
- `SDLGPUShaderCompileError` gains `init(_ error: RuntimeShaderCompileError)` (internal, one to one). `SDLGPUShaderDefine`/`SDLGPUShaderTarget` stay; they convert to the runtime types internally.
- The internal seams the RC tests use stay with their spelling: `LibraryAttempt` (wrapping the locator's `Attempt`), `libraryAttempts(...)`, `load(candidates:counted:)`, `ProcessCache` (a thin internal wrapper whose
  `init(attempts:)` builds a `RuntimeShaderCompiler.ProcessCache`), `withProcessCache`, `emptyDiagnostics` (= the runtime's). **One cache**: `SDLGPUShaderCompiler.shared()` is `RuntimeShaderCompiler.shared()` wrapped.
- `Backends/SDL/Sources/SDLBridge/SDLShaderCross.c` shrinks to two unconditional forwarders: `mui_sc_loads()` -> `mui_rsc_loads()`, `mui_sc_test_empty_diagnostics(b)` -> `mui_rsc_test_empty_diagnostics(b)`;
  `SDLBridge.h` keeps those two declarations and drops `MuiShaderCross`, `MuiShaderCrossReflection`, `mui_sc_load`, `mui_sc_compile_hlsl`, `mui_sc_msl`, `mui_sc_reflect`, `mui_sc_free` (no other user; grep).
- Behaviour change under the trait, by ruling (`HX-D`): the three SDL functions come from the shadercross handle, not the linked SDL. With one SDL3 instance (the measured case, `RC-Y`) they are the same functions;
  with two, diagnostics now arrive instead of `emptyDiagnostics`. No RC test can tell (they run with one instance).

## 6. Packaging and notices (`HX-H`)

`docs/packaging.md` 4b: a new paragraph "Without the `SDL` trait (macOS default build)": add the product `MetalUIShaderRuntime`; ship the four files of the table **plus `libSDL3.0.dylib`** (size from `HX-B`,
zlib) in the same directory (`Contents/Frameworks`); a Homebrew-built shadercross names SDL3 by absolute path (`/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib`) and its dependents by `@rpath` with no
`LC_RPATH`, and the loader preloads all of them by full path, so **no `install_name_tool` step is needed** (measured, `HX-B` arms R and P). Code signing: every dylib is signed with the app (`codesign --deep`
is not enough for a hardened runtime with library validation: sign each, same team, or `com.apple.security.cs.disable-library-validation`; unmeasured, human check `HX1`). `THIRD-PARTY-NOTICES.md`: the
optional section's SDL3 sentence names the macOS no-trait case (SDL3 zlib, its `LICENSE.txt` from the SDL release, shipped by the app). The per-product table gains a `MetalUIShaderRuntime` row: links no third-party
code; loads at run time only what the app ships.

## 7. Tests

Root target `MetalUIShaderRuntimeTests` (every platform; Linux and Windows CI run it in the root job). Gated tests: `.enabled(if: RuntimeShaderSupport.available)` where `available` is
`METALUI_SHADERCROSS_LIB` set **and** `RuntimeShaderCompiler.shared()` succeeding; `aRequiredShaderCompilerIsPresent` fails when `METALUI_REQUIRE_SHADERCROSS=1` and it is not available (the RC pattern).
Each test is red before (the module does not exist). Mutation named per test; mutations are run by the implementation lane in the default (no trait) build unless the row says `--traits SDL`.

Always run (no library):

1. `aMissingLibraryThrowsCompilerUnavailableListingEveryPathTried` - `load(candidates:)` over attempts naming non-existent files; error lists each `path: no such file (...)`. Mutation: `load` throws `tried: []`.
2. `everyEntryThrowsCompilerUnavailableWithoutTheLibrary` - `withProcessCache` of an empty lookup: `shared()`, `isAvailable == false`, static `selfTest` all answer `compilerUnavailable`. Mutation: static `selfTest` returns a report when `shared()` fails.
3. `aDecoyLibraryFailsWithTheLoadersTextNotATrap` - a temp directory with zero-byte `libSDL3_shadercross.<ext>`, `libdxcompiler.<ext>`, `libspirv-cross-c-shared.<ext>`: the error line for the decoy starts `failed to load: ` and names a dependent (preload runs first). Mutation: `mui_rsc_load` skips the preload loop.
4. `theSDLGroupIsPreloadedFirstOnlyWhenAsked` (pure, `MetalUIShaderCompileTests`) - listing `libSDL3.0.dylib`, `libSDL3.dylib`, `libSDL3_shadercross.dylib`, `libSDL3_test.a`, `libdxcompiler.dylib`, `libspirv-cross-c-shared.0.dylib`: with `includingSDL` the set starts `libSDL3.dylib`, `libSDL3.0.dylib` then the dependents; without, byte-equal to today's. Same for `.so.0` and `.dll` namings. Mutations: match `hasPrefix("sdl3")` (red: shadercross itself preloaded); put the group last (red: order).
5. `aDirectoryWithoutSDLStillLoadsTheDependentsSet` (pure) - `includingSDL: true` and no SDL3 file: no error (the group is optional). Mutation: make the group required.
6. `theDefaultBuildProcessHasNoSDL3BeforeTheFirstLoad` - an **exit test** (`#expect(processExitsWith: .success)`, a fresh process, Darwin and Linux; Windows skips): `mui_rsc_process_has_sdl3()` (through a package wrapper) answers false, then `dlopen` of `METALUI_SDL3_LIB` with `RTLD_GLOBAL` (when set) makes it answer true. Mutation: the C function returns a constant (red on one arm).
7. `theRuntimeAPIIsPublicAndTheLoaderIsNot` (guard, `typecheckFile` with a plain `import MetalUIShaderRuntime`): fixture A spells every public declaration of section 4 and typechecks; fixtures B, C, D each fail: `RuntimeShaderCompiler.load(candidates: [])`, `RuntimeShaderCompiler.ProcessCache.current`, `mui_rsc_loads()` (the C module is an `internal import`). Mutations: make `ProcessCache` public (B compiles: red); `public import CShaderCross` (D compiles: red). Counts as typecheck guards (+4).
8. `theRuntimeTypesConvertOneToOneIntoTheSDLOnes` lives in `Backends/SDL/Tests` (`MetalUISDLTests`, trait build): every `RuntimeShaderCompileError` case maps to the same-named `SDLGPUShaderCompileError` case with equal payloads. Mutation: map `malformedReflection` to `invalidInput`.

Gated on `METALUI_SHADERCROSS_LIB` (the pin's install, `HX-B` path), default build, no trait:

9. `aRequiredShaderCompilerIsPresent` - fails under `METALUI_REQUIRE_SHADERCROSS=1` when unavailable. Mutation: none (the gate itself).
10. `aKernelCompilesToEveryTargetWithItsReflectionWithoutSDLLinked` - the control kernel to `.spirv` (magic `07230203`), `.msl` (contains `main0`), `.dxil` (`DXBC`), reflection `robuf=1 rwbuf=1 ubo=1 threads 64,1,1`, and the shared compiler's `processHadSDL3 == false` (nothing in the root test process links SDL3). Mutation: drop the read-write buffer count in the Swift mapping.
11. `aSyntaxErrorThrowsCompileFailedWithDXCsText` - `compileFailed(stage: "HLSL to SPIR-V", diagnostics:)` contains `error:` and `expected parameter declarator`. Mutation: the shim never reads the error (M20 of `RC-Y`, moved).
12. `anSDL3BesideShadercrossIsPreloadedLocallyAndCarriesTheDiagnostics` - an **exit test**, gated on `METALUI_SHADERCROSS_LIB` **and** `METALUI_SDL3_LIB` (a libSDL3 file): a temp directory of symlinks to every file of the shadercross directory plus `libSDL3.0.dylib` (`libSDL3.so.0`) linked to `METALUI_SDL3_LIB`; `load(candidates:)` of it in a fresh process answers `processHadSDL3 == false`, `preloaded.first` is the SDL3 link, a compile succeeds, a broken kernel's diagnostics hold DXC's text, and afterwards `dlsym(RTLD_DEFAULT, "SDL_GetError")` is NULL (SDL3 stayed `RTLD_LOCAL`, `HX-B` arm L). Mutations: `includingSDL: false` (red: `preloaded`); resolve `SDL_GetError` with `dlsym(RTLD_DEFAULT, ...)` instead of the handle (red: the load fails naming `SDL_GetError`, arm L shows it is not global); load SDL3 `RTLD_GLOBAL` (red: the last assertion).
13. `aSecondSharedCallReusesTheFirstLoad` - eight tasks times five `shared()` calls, `mui_rsc_loads() == 1`, a different explicit path throws `libraryAlreadyLoaded`. Mutation: `shared()` loads per call.
14. `eightThreadsCompileDifferentKernelsToTheirOwnSerialBytes` - `-DK=<i>` per thread, equal to serial (`RC-S`). Mutation: one static output buffer in `CShaderCross.c`.
15. `definesChangeTheCompiledKernel` - `-DK=2` and `-DK=3` give different SPIR-V, and a bare `-DFLAG` (nil value) selects an `#ifdef FLAG` branch. Mutation: defines not passed.
16. `selfTestNamesTheLibraryTheTargetAndRequiresDiagnostics` and `selfTestFailsWhenTheDiagnosticsAreEmpty` (via `mui_rsc_test_empty_diagnostics`). Mutation: the broken-kernel arm skipped.
17. `aRuntimeCompileOfTheAppShadersMatchesTheBuildToolsBlobs` (also needs `METALUI_SHADERCROSS_AT_PIN=1`): `Backends/SDL/Tests/AppShaders/append.comp.hlsl` to SPIR-V, MSL, DXIL byte-equal to the checked-in `compiled` blobs. Mutation: the C call gets entry point `"mainx"`.
18. `theMSLRunsOnMetal` (macOS only, `canImport(Metal)`, gated): the `.msl` of the control kernel builds with `MTLCreateSystemDefaultDevice()!.makeLibrary(source:options:)` and `makeFunction(name: "main0")` is non-nil (no dispatch: buffer-slot binding is SDL_GPU's convention, documented). Mutation: report entry `main` for MSL.

Unchanged and re-run (trait build, `Backends/SDL`, with and without the library): all 21 `SDLGPURuntimeCompile*` tests, guard `theLocatorTheValidationAndTheCShimAreNotPublic` (its file list gains nothing; `mui_sc_` now appears in no Swift file, which the scan allows).
The implementation lane re-runs mutations M19, M20, M23, M24 of `RC-Y` against the moved code under `--traits SDL` (`Backends/SDL`) and names the reddened tests.

**Counts:** root +17 tests (1-7 and 9-18) and +4 typecheck guards; `Backends/SDL` +1 (test 8). Re-measured by the implementation lane (`swift package clean`, native, `--no-parallel`).

## 8. Files

Add: `Sources/CShaderCross/CShaderCross.c`, `Sources/CShaderCross/include/CShaderCross.h`, `Sources/MetalUIShaderRuntime/RuntimeShaderCompiler.swift` (compiler, cache, loading), `.../RuntimeShaderTypes.swift`
(error, define, target, reflection, compiled shader, report), `Tests/MetalUIShaderRuntimeTests/*.swift`, `docs/probes/shadercross-no-sdl.c` (the `HX-B` probe, header with commands and recorded output), record 160, human checks
group `HX` (`HX1` signed `.app` with hardened runtime loads the five dylibs; `HX2` Windows: SDL3.dll resolved through `GetModuleHandleW` after a `SetDllDirectoryW` load, the no-trait path; `HX3` Linux tarball without system SDL3).
Change: `Package.swift`; `Backends/SDL/Sources/MetalUISDLGPU/SDLGPUShaderCompiler.swift`; `Backends/SDL/Sources/SDLBridge/SDLShaderCross.c` and `include/SDLBridge.h`; `Backends/SDL/Sources/MetalUIShaderCompile/RuntimeLibraryLocator.swift`
(`includingSDL`); `Tests/MetalUIShaderCompileTests/RuntimeLibraryLocatorTests.swift` (tests 4-5); `Backends/SDL/Tests/MetalUISDLTests/SDLGPURuntimeCompilerTests.swift` (test 8); `docs/probes/closeout-public-api.sh`, `.tsv`,
`closeout-inventory-map.tsv`; `docs/packaging.md` 4b; `THIRD-PARTY-NOTICES.md`; `docs/api-overview.md` (one line under GPU); `docs/superpowers/2026-10-23-shadercross-lookup-decisions.md` (`SX-E` header: "superseded by `HX-A`");
CLAUDE.md + AGENTS.md (one rule paragraph and the `HX-` prefix entry, Record phase; `cmp`).

## 9. Not built (deferred, named)

Graphics stages (`RC-L`); a compile cache (`RC-M`); warnings capture (`RC-I`); a Metal pipeline convenience (`MTLComputePipelineState` from a `CompiledComputeShader`: the binding convention is SDL_GPU's,
an app with its own Metal code maps its buffers itself; owner the first Mac-only consumer); making the `SDL` trait default (rejected, `SX-E` stands on that half).
