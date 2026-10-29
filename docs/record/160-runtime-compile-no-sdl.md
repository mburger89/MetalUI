# 160. Run-time HLSL compile without the `SDL` trait (XP-G27)

Item XP-G27 (low) of the gpui-gap priority list (user request 2026-10-02, "go ahead with XP-G27" 2026-10-28, MetalCreator `xp-c`; **not a plan task**), on `feat/runtime-shader-compile` from master `3c9dc9a4`. Rulings `HX-A`..`HX-K` in `docs/superpowers/2026-10-28-runtime-compile-no-sdl-decisions.md`; spec `docs/superpowers/specs/2026-10-28-runtime-compile-no-sdl-design.md`. Class `M`, additive, no divergence (885-894 untouched), nothing published (`BS-H`). **Supersedes `SX-E`** (record 152 carried it for want of a measurement; `HX-B` is that measurement).

## 1. What was built

- **`Sources/CShaderCross`** (portable C, `PC-A` every-platform list, no SDL or shadercross header): the mirror structs and their static asserts, the Init-once atomic, compile, MSL and reflection bodies **moved** (not copied) out of `Backends/SDL/Sources/SDLBridge/SDLShaderCross.c` (`HX-C`). `dlopen`/`dlsym` on POSIX, `LoadLibraryW`/`GetProcAddress` with `SetDllDirectoryW` on Windows. The function table holds the five shadercross functions **and** `SDL_GetError`/`SDL_ClearError`/`SDL_free`, resolved through shadercross's own handle (`HX-D` 1).
- **`MetalUIShaderRuntime`** (new library product, every platform): `RuntimeShaderCompiler`, `RuntimeShaderTarget`, `RuntimeShaderDefine`, `ComputeShaderReflection`, `CompiledComputeShader`, `RuntimeShaderSelfTestReport`, `RuntimeShaderCompileError` (`HX-G`), and the `package` `ProcessCache` (one load per process across both APIs, `HX-E`). `MetalUI` does not depend on it.
- **SDL3 rule** (`HX-D`): only when the process holds no SDL3 (`mui_rsc_process_has_sdl3()`), a file of stem `sdl3` beside shadercross is preloaded first, by full path, `RTLD_LOCAL` (`RuntimeLibraryLocator.preloadSet(includingSDL:)`); otherwise nothing, since a second SDL3 duplicates its Objective-C classes (`HX-B` arm T).
- **`SDLGPUShaderCompiler` forwards** to the runtime (`HX-F`): public spelling and behaviour unchanged, the RC tests compile as they were, `SDLShaderCross.c` shrank by about 200 lines, `SDLBridge` keeps two test-facing forwarders. No migration note.
- Docs: `docs/packaging.md` 4b no-trait paragraph (ship `libSDL3.0.dylib` beside shadercross, about 35 MB, no `install_name_tool`), `THIRD-PARTY-NOTICES.md` (SDL3 zlib sentence, the runtime links no third-party code), `docs/api-overview.md`, `docs/guides/cross-platform.md` (one sentence, no swift block), human checks group `HX` (`HX1`-`HX3`), the census (`closeout-public-api.sh` gains the target, one `F` and one `M` map row), `SX-E` marked superseded.

## 2. Measurement (`HX-B`)

A fresh build of the shadercross pin (`1ff05bec`) on this Mac: 419 s, `lib` 32 MB. `docs/probes/shadercross-no-sdl.c`, linked against libSystem only: with SDL3 preloaded `RTLD_LOCAL`, load, SPIR-V, MSL (`main0`), DXIL and reflection all pass in one SDL3 image, and a broken kernel's 431-byte diagnostics arrive through the `dlsym`'d `SDL_GetError`; a relocated shadercross naming a nonexistent SDL3 fails to load without the preload and passes with it (arm P). Cold load 0.858 s, warm 0.010 s.

## 3. Tests

Root **4489 -> 4508** (+19): `MetalUIShaderRuntimeTests` (always-run seams, gated compiles on `METALUI_SHADERCROSS_LIB`, two exit tests for "no SDL3 in the process yet", four plain-import guard fixtures), two locator tests in `MetalUIShaderCompileTests` (`theSDLGroupIsPreloadedFirstOnlyWhenAsked`, `aDirectoryWithoutSDLStillLoadsTheDependentsSet`), one mapping test in `Backends/SDL`, and `sixteenThreadsOnAFreshCacheLoadOnce` (added by verification, below).

## 4. Mutations (filter `MetalUIShaderRuntimeTests|MetalUIShaderCompileTests`, library and SDL3 variables set, 55 tests; each restored with `git checkout`)

| Mutation | Reddened |
|---|---|
| `compilerUnavailable` built with `tried: []` | `aMissingLibraryThrowsCompilerUnavailableListingEveryPathTried`, `aDecoyLibraryFailsWithTheLoadersTextNotATrap` |
| `isAvailable` always true | `everyEntryThrowsCompilerUnavailableWithoutTheLibrary` |
| `libraryAlreadyLoaded` check removed | `aSecondSharedCallReusesTheFirstLoad` |
| `ProcessCache` never stores the compiler | `aKernelCompilesToEveryTargetWithItsReflectionWithoutSDLLinked`, `aSecondSharedCallReusesTheFirstLoad` |
| DXIL result returns the SPIR-V bytes | `aKernelCompilesToEveryTargetWithItsReflectionWithoutSDLLinked` |
| MSL entry reported as the source entry, not `main0` | the same, `aRuntimeCompileOfTheAppShadersMatchesTheBuildToolsBlobs`, `selfTestNamesTheLibraryTheTargetAndRequiresDiagnostics`, `theMSLRunsOnMetal` |
| `sdl3` group appended last, not first | `anSDL3BesideShadercrossIsPreloadedLocallyAndCarriesTheDiagnostics`, `theSDLGroupIsPreloadedFirstOnlyWhenAsked` |
| `sdl3` stem matched by prefix (catches `SDL3_shadercross`) | `aRequiredShaderCompilerIsPresent`, the SDL3-beside test, `thePreloadSetIsTheDependentsInTheLibrarysDirectory`, `theSDLGroupIsPreloadedFirstOnlyWhenAsked` |
| `includingSDL` inverted | `anSDL3BesideShadercrossIsPreloadedLocallyAndCarriesTheDiagnostics` |
| `mui_rsc_process_has_sdl3` probes the wrong symbol | `theDefaultBuildProcessHasNoSDL3BeforeTheFirstLoad` |
| `open_library` uses `RTLD_GLOBAL` | `anSDL3BesideShadercrossIsPreloadedLocallyAndCarriesTheDiagnostics` |
| `@_exported public import CShaderCross` | `theRuntimeAPIIsPublicAndTheLoaderIsNot` |
| `ProcessCache.resolve` without its lock | **survived**; now reddens `sixteenThreadsOnAFreshCacheLoadOnce` (the one real gap) |

Survivors that are not gaps: a plain `public import CShaderCross` (a public import does not re-export), `ProcessCache` itself `public` (its `current`, `resolve`, `init` stay `package`), rewording `emptyDiagnostics` (tests compare against the constant; only the wording is unpinned). One mutation (`preload: preload,` to `preload: []`) never applied (pattern mismatch) and was discarded.

## 5. Verification

`swift package clean`, native build with tests: 0 errors, 354 s. Unfiltered `swift test --build-system native --no-parallel` with `METALUI_SHADERCROSS_LIB`, `METALUI_REQUIRE_SHADERCROSS=1`, `METALUI_SDL3_LIB`: **4508 tests in 12 suites passed** (805 s), 0 issues, `FR-J no-argument frame: succeeded=true deprecations=2`; HX guards G1 `succeeded=true`, G2-G4 `succeeded=false`. Closeout inventory and undocumented probes print nothing. Root `--traits SDL` (needs `-Xcc -I/opt/homebrew/include -Xlinker -L/opt/homebrew/lib`) filtered runtime, compile and `SDLGPURuntimeCompile` tests passed; `Backends/SDL` `SDLGPURuntimeCompile` 23 in 2 suites with and without the library. **Not run:** Linux, Windows (`HX2`, `HX3`), a signed hardened-runtime app (`HX1`).

## 6. Carried

Graphics stages (`RC-L`), a compile cache (`RC-M`), warning capture (`RC-I`), a Metal pipeline convenience (`HX-G`), the Linux and Windows arms of `HX-B`. The `SDL` trait is not made default (`HX-K`).
