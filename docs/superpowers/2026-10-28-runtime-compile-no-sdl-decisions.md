# Run-time HLSL compile without the `SDL` trait (XP-G27) - decisions

Rulings for item XP-G27 of the gpui-gap priority list (user request 2026-10-02, "go ahead with XP-G27" 2026-10-28; **not a plan task**), from MetalCreator's `xp-c` track.
Prefix `HX-`. **Next unused: `HX-L`.**
Spec: [`specs/2026-10-28-runtime-compile-no-sdl-design.md`](specs/2026-10-28-runtime-compile-no-sdl-design.md). Record: `../record/160-runtime-compile-no-sdl.md` (Record phase).
Branch `feat/runtime-shader-compile` from `3c9dc9a4`. Continues `RC-B`...`RC-Y` (record 151) and `SX-B`/`SX-C` (record 152); **supersedes `SX-E`** (carried, now built: `HX-B` is the measurement `SX-E` asked for).
Divergence labels reserved 885-894: **none taken** (`HX-A`). **Nothing is published** (`BS-H`).

Sources of truth. SwiftUI and gpui have no run-time shader compiler: no SwiftUI claim, no probe. Facts about shadercross are from a fresh build of the pin on this Mac (`HX-B`) and the code at `3c9dc9a4`
(`SDLShaderCross.c`, `SDLGPUShaderCompiler.swift`, `RuntimeLibraryLocator.swift`). Anything not measured here is marked **unmeasured**.

## HX-A - class M, additive, a new product, no divergence; the census grows

**Ruling.** A new library product `MetalUIShaderRuntime` (Swift, every platform) over a new portable C target `CShaderCross`. Every public declaration is MetalUI-only (class `M`). Unlike `RC-A`/`SX-A`
(`Backends/SDL`, outside the census), the new target is a root `Sources/` target in a product, so `docs/probes/closeout-public-api.sh` gains it in `TARGETS`, the inventory map gains an `F` row and an `M` row, and
every declaration has a doc comment (`closeout-inventory-check.sh`, `closeout-undocumented.sh` print nothing). Nothing existing breaks: `SDLGPUShaderCompiler`'s public surface is unchanged (`HX-F`), so **no migration note**.
`MetalUI` does not depend on the product: an app that never compiles links and ships none of it. **Cost if wrong.** A map row.

## HX-B - the measurement owed by SX-E: shadercross at the pin loads and compiles with libSDL3 only `dlopen`ed

**Build** (2026-10-28, macOS 27.2 arm64, 10 cores, load average 118-225 from other sessions, Homebrew SDL3 3.4.18, cmake 4.4.4, ninja 1.13.2): `docs/packaging.md` 4a's recipe verbatim
(`-DSDLSHADERCROSS_VENDORED=ON -DSDLSHADERCROSS_INSTALL=ON`, Release, `cmake --build build -j8`) into `$SCRATCH/xpg27/install`: clone and submodules 21 s, **build 419 s** for 1303 steps, install 1 s. `lib` is 32 MB:
`libdxcompiler.dylib` 27,884,944, `libdxil.dylib` 2,045,120, `libspirv-cross-c-shared.0.68.0.dylib` 3,582,768, `libSDL3_shadercross.0.0.0.dylib` 72,064 (+ version symlinks). `otool -L` of shadercross:
`@rpath/libspirv-cross-c-shared.0.dylib`, `@rpath/libdxcompiler.dylib`, **`/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib` (absolute)**, no `LC_RPATH` (as `RC-H` arm H). Homebrew's `libSDL3.0.dylib` is **2,520,816 bytes**, install name
`/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib`.

**Probe** `docs/probes/shadercross-no-sdl.c`: a C program linked against **libSystem only** (`otool -L`), no SDL or shadercross header (`SDLShaderCross.c`'s mirror structs, the same `_Static_assert`s 40/32/36 held), that
`dlopen`s SDL3 (or not), the dependents by full path (`RC-N`), then shadercross, and resolves the five shadercross functions **and `SDL_GetError`, `SDL_ClearError`, `SDL_free` with `dlsym` on the shadercross handle**
(which searches that image's dependency tree). Arms and output:

- **L (the shipped shape: SDL3 preloaded by full path with `RTLD_NOW|RTLD_LOCAL`, as `SDL_LoadObject` does):** every load succeeds, total 0.858 s cold (`libdxcompiler` 0.484 s of it; warm reruns 0.010 s). One SDL3 image in the process.
  `SDL_GetError` through the shadercross handle is the same address as through the SDL3 handle (one instance); **through `RTLD_DEFAULT` it is NULL** (a local SDL3 stays out of the global namespace).
  Init 1. **A** SPIR-V 1092 bytes, magic `07230203`, first compile 0.025 s, second 0.005 s. **D** MSL 577 characters, contains `main0`. **C** `samplers=0 rotex=0 robuf=1 rwtex=0 rwbuf=1 ubo=1 threads=64,1,1`.
  **E** DXIL 3368 bytes, `DXBC`. **B (separating arm)** a broken kernel returns NULL and the `dlsym`'d `SDL_GetError` holds **431 bytes**: `HLSL compilation failed: hlsl.hlsl:1:32: error: expected parameter declarator`
  with the source line (431, not `RC-H`'s 467: SDL 3.4.18 against 3.4.0, same message).
- **SDL3 preloaded `RTLD_GLOBAL`:** the same results; `RTLD_DEFAULT` then finds the same `SDL_GetError`.
- **SDL3 not preloaded:** shadercross's own load command finds Homebrew's SDL3 by its absolute path and every arm passes, and that SDL3 **is** then visible through `RTLD_DEFAULT`. So on this Mac dyld finds libSDL3
  without help; on a Mac without Homebrew it does not (arm P).
- **P (negative, a Mac without Homebrew):** a relocated copy whose shadercross names SDL3 at `/nonexistent/hx/libSDL3.0.dylib` (install_name_tool + ad hoc re-sign): without the SDL3 preload the load fails with
  `Library not loaded: /nonexistent/hx/libSDL3.0.dylib ... (no such file)`.
- **R (positive, the same copy):** preloading the relocated `libSDL3.0.dylib` (install name `/nonexistent/hx/libSDL3.0.dylib`) by full path, `RTLD_LOCAL`, first: **every arm passes**. dyld binds an absolute-path
  dependency to an already-loaded image of that install name, so a shipped `.app` needs **no `install_name_tool` step**: the copied Homebrew SDL3 keeps the install name shadercross names.
- **T (two SDL3 instances, an app linking one SDL3 and a second preloaded):** the Objective-C runtime prints `Class SDL3Window is implemented in both ... This may cause spurious casting failures and mysterious crashes`
  (19 classes); shadercross binds to the second; the compiler's text arrives through the shadercross handle's `SDL_GetError` (431 bytes) while the **global** `SDL_GetError` holds **0 bytes**.

**Reading.** (1) `SX-E`'s open question is answered yes: shadercross needs no SDL3 linked into the process. (2) Reading the three SDL functions **through the shadercross handle** is correct in every arm, including
the two-instance one where today's code (the app's linked `SDL_GetError`) reads nothing (`HX-D`). (3) A second SDL3 instance is harmful beyond diagnostics (duplicate Objective-C classes), so the SDL3 preload must be
skipped when the process already has one (`HX-D`). **Not measured here (owed, named):** the Linux arms (glibc `dlsym` on a handle searching its dependents is documented behaviour; `RC-U` measured the SONAME match of preloaded
dependents; the implementation lane runs a `.so` port of the probe in the `metalui-portable` image if the volume `metalui-shadercross-sdl-gpu-runtime-shaders` still holds the pin's install, else it stays owed);
Windows (`GetModuleHandleW(L"SDL3.dll")` after the load, compiled by CI only, human check `HX2`); a hardened-runtime signed `.app` (`HX1`). **Cost if wrong.** None: facts, never pinned; the pins of `HX-I` count results.

The pin's install from this build stays at `/private/tmp/claude-501/-Users-maxburger-Developer-MetalUI/01573661-1faa-4d09-b112-f4aa683e9750/scratchpad/xpg27/install/lib` for the implementation lane (`METALUI_SHADERCROSS_LIB`); scratch, not referenced by any test.

## HX-C - one implementation: the C shim moves to a portable target that both APIs use

**Question.** `SX-E` rejected an SDL-free route because it would be "a second, hand-written loader" forking `RC-B`. Can it be one?
**Ruling.** Yes, by moving, not copying. `SDLShaderCross.c`'s mirror structs, static asserts, Init-once atomic, compile, MSL and reflection bodies move to **`Sources/CShaderCross`** (C, the `PC-A` every-platform list,
no SDL or shadercross header; `dlopen`/`dlsym` on POSIX, `LoadLibraryW`/`GetProcAddress` with today's `SetDllDirectoryW` on Windows), behind a function-pointer table that holds the five shadercross functions **and**
`SDL_GetError`/`SDL_ClearError`/`SDL_free`. **`MetalUIShaderRuntime`** (Swift, `internal import CShaderCross`, plus `MetalUIShaderCompile`'s package locator and validation) is the one Swift wrapper; `SDLGPUShaderCompiler`
forwards to it (`HX-F`). `SDLBridge` keeps only the two test-facing symbols as forwarders (`mui_sc_loads`, `mui_sc_test_empty_diagnostics`) so the RC tests compile unchanged. Names: `CShaderCross` follows the
vendored-C convention (`CStbImage`, `CFreeType`); `MetalUIShaderRuntime` says "at run time" beside `MetalUIShaderCompile` (build time, `BS-`). Both live in root `Sources/` because neither is SDL code.
**Alternatives rejected.** (a) A second C loader beside `SDLShaderCross.c` (the fork `SX-E` named). (b) Keeping the shim in `SDLBridge` and compiling it without the trait: `SDLBridge`'s header and C file are SDL's, and a
no-trait build of it would be two personalities in one file. (c) Swift `dlopen` without a C target: the mirror structs and their static asserts are the contract (`RC-B`) and belong in C. **Cost if wrong.** A file move.

## HX-D - which SDL3: never a second instance, always the one shadercross calls

**Ruling.** (1) The three SDL functions are resolved **through the shadercross library's handle** (POSIX `dlsym(handle, ...)`; Windows `GetProcAddress` on `GetModuleHandleW(L"SDL3.dll")` taken after the load, the module the loader
bound), never from the process's own SDL or `RTLD_DEFAULT`, so the diagnostics text and `SDL_free` are always the instance shadercross used (`HX-B` arms L, T). (2) libSDL3 is found by **no second lookup list**: when the
process has **no** SDL3 (`mui_rsc_process_has_sdl3()`: POSIX `dlsym(RTLD_DEFAULT, "SDL_GetVersion") != NULL`, Windows `GetModuleHandleW(L"SDL3.dll") != NULL`), a file of stem `sdl3` in the **shadercross directory**
is preloaded first, by full path, `RTLD_LOCAL` (an optional group of `preloadSet`, `includingSDL:`); when there is none, shadercross's own load command finds SDL3 or the load fails naming it. When the process already
has SDL3 (the `SDL` trait, an app linking SDL3 itself), nothing is preloaded: a second instance duplicates SDL's Objective-C classes (arm T). (3) `RTLD_LOCAL`, as `SDL_LoadObject` does today: a preloaded SDL3 stays
out of the global namespace (arm L), so an app or plugin that later looks for SDL globally is not handed MetalUI's copy.
**Consequence for `RC-D`.** Its "one SDL3 instance or the text is lost" rule is no longer a precondition: with two instances the text still arrives (arm T). The self test's empty-diagnostics arm stays as the check that
the C read is wired (`RC-J`, test hook unchanged).
**Alternatives rejected.** A `METALUI_SDL3_LIB` variable or a locator list for SDL3 (the install keeps SDL3 beside shadercross, `RC-K`'s one-directory rule; a variable is a second place to drift; the test variable of
`HX-I` is a test input only); linking SDL3 into `MetalUIShaderRuntime` (every default-build consumer would need SDL3 to link); `RTLD_GLOBAL` (pollutes the namespace for no gain, arm L). **Cost if wrong.** On Windows the
`GetModuleHandleW` read could name a different `SDL3.dll` when two are loaded (unmeasured, `HX2`); the fallback is the load failing with the missing symbol named, never a crash.

## HX-E - one load per process, across both APIs

**Ruling.** The process cache (`RC-O`'s `ProcessCache`) moves to `MetalUIShaderRuntime` as `package`; `SDLGPUShaderCompiler.shared()` is `RuntimeShaderCompiler.shared()` wrapped, so whichever API calls first
loads, the other reuses, `mui_rsc_loads()` (read back as `mui_sc_loads()`) stays 1, and an explicit path differing from the loaded one throws `libraryAlreadyLoaded` from either API. `SDL_ShaderCross_Init` stays once per
process (atomic, `RC-X` 5). **Cost if wrong.** Two loads of DXC (about 32 MB resident each, `RC-B`).

## HX-F - `SDLGPUShaderCompiler` forwards; its public spelling, behaviour and the RC tests are unchanged

**Ruling.** It keeps every public declaration and doc comment, holds a `RuntimeShaderCompiler`, maps `RuntimeShaderCompileError` one to one onto `SDLGPUShaderCompileError`, builds `SDLGPUShaderBlob` from the compiled
kernel through today's validating initializer (`RC-E`), and runs its device dispatch arm after the runtime's self-test arms. Its internal test seams (`LibraryAttempt`, `libraryAttempts`, `load(candidates:counted:)`,
`ProcessCache`, `withProcessCache`, `emptyDiagnostics`) keep their spelling as thin wrappers (`RC-X` 1: `package` is invisible to the `MetalUISDL` tests). The only behaviour change is `HX-D` (1), invisible with one
SDL3 instance, which is how every RC test runs. The implementation lane re-runs `RC-Y`'s M19, M20, M23, M24 against the moved code under `--traits SDL`. **Cost if wrong.** An RC test reddens at the first commit.

## HX-G - the public API: `RuntimeShaderCompiler` and five value types, named for what they are, not for SDL

**Ruling.** `RuntimeShaderCompiler` (`shared(libraryPath:)`, `isAvailable`, `compileCompute(hlsl:entryPoint:defines:includeDirectory:target:)`, `selfTest(target:)` and its static twin), `RuntimeShaderTarget`
(`spirv`, `msl`, `dxil`; `init(driver:)` for SDL_GPU driver names), `RuntimeShaderDefine`, `ComputeShaderReflection` (nine `Int`s, `Hashable`: three named thread axes, not a tuple), `CompiledComputeShader`
(`target`, `bytes`, `entryPoint`, `reflection`), `RuntimeShaderSelfTestReport`, and `RuntimeShaderCompileError` with `SDLGPUShaderCompileError`'s six cases and texts (spec section 4). Synchronous and `Sendable`;
compiles run concurrently (`RC-D`). **Not offered:** a Metal pipeline convenience (`MTLComputePipelineState` from a kernel): the MSL's buffer slots follow SDL_GPU's convention, which a Mac-only app that writes its own Metal
code maps itself; the spec's test 18 shows the MSL builds an `MTLLibrary` with function `main0`. A `name:` parameter is not taken (the SDL blob's name is SDL-side). **Alternatives rejected.** Reusing the `SDLGPU`-prefixed
names in a non-SDL module (misleading, and they live in `MetalUISDLGPU` which is empty without the trait). **Cost if wrong.** A rename before anyone depends on it.

## HX-H - packaging: a no-trait Mac app ships libSDL3 beside shadercross

**Ruling.** `docs/packaging.md` 4b gains the no-trait case: add the product `MetalUIShaderRuntime`; ship `RC-K`'s four files **plus `libSDL3.0.dylib`** (Homebrew 3.4.18 arm64: 2,520,816 bytes, so about 35 MB in all) in one
directory (`Contents/Frameworks`), found by `RC-C`'s lookup; **no `install_name_tool`** (`HX-B` R). Each dylib is signed with the app; a hardened runtime with library validation needs the same team signature on each, or the
`disable-library-validation` entitlement (unmeasured, `HX1`). `THIRD-PARTY-NOTICES.md`: the optional compiler section's SDL3 sentence covers the macOS no-trait case (zlib; SDL3's `LICENSE.txt` from the SDL release, shipped by
the app); the per-product table says `MetalUIShaderRuntime` links no third-party code. **Cost if wrong.** A doc line.

## HX-I - tests: always-run seams everywhere, gated compiles in fresh processes where order would matter

**Ruling.** A root test target `MetalUIShaderRuntimeTests` (every platform, so Linux and Windows CI run its always-run tests) plus two locator tests in `MetalUIShaderCompileTests` and one mapping test in `Backends/SDL`.
Gated tests follow the RC pattern (`METALUI_SHADERCROSS_LIB`; `METALUI_REQUIRE_SHADERCROSS=1` makes a skip fail). Two tests are **exit tests** (`#expect(processExitsWith:)`, Darwin and Linux) because their subject is
"no SDL3 in the process yet", which another test's load changes for the rest of the process (`HX-B`: the load-command route makes SDL3 global). The SDL3-beside test needs a second variable `METALUI_SDL3_LIB` (a test input,
not a lookup, `HX-D`). The plain-import guard (`typecheckFile`, four fixtures) keeps `ProcessCache`, `load(candidates:)` and the C module unreachable. Full list and mutations: spec section 7. **Cost if wrong.** An order-dependent pin.

## HX-J - SX-E superseded; what stays carried

**Ruling.** `SX-E` is superseded: its measurement (`HX-B`) and its two named costs (a loader, an app shipping SDL3) are answered by `HX-C` (one loader, moved) and `HX-H` (2.5 MB, zlib). Its other half stands: the `SDL`
trait is **not** made default. `docs/superpowers/2026-10-23-shadercross-lookup-decisions.md` gains "superseded by `HX-A`...`HX-J`" in `SX-E`'s heading at the implementation commit. Still carried: graphics stages (`RC-L`),
a compile cache (`RC-M`), warning capture (`RC-I`), a Metal pipeline convenience (`HX-G`), the Linux and Windows arms of `HX-B`. **Cost if wrong.** None.

## HX-K - rejected shapes, recorded

**Rulings.** (1) Making the `SDL` trait default on macOS: every Mac consumer would link SDL3 and AccessKit's graph for a feature few use. (2) A static SDL3 inside shadercross: changes the pin's recipe (`RC-N`'s rejection of a rebuild
applies). (3) Keeping `SDLShaderCross.c` and adding a parallel no-SDL file: the fork. (4) A process-wide `SDL_SetLogOutputFunction` for warnings: `RC-I` stands. **Cost if wrong.** None.
