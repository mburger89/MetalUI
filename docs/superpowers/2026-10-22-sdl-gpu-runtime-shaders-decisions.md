# Run-time HLSL compute shaders on SDL_GPU (XP-G25) — decisions

Rulings for item XP-G25 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), requested by MetalCreator's `xp-c`
track. Prefix `RC-`. **Next unused: `RC-Z`.**
Spec: [`specs/2026-10-22-sdl-gpu-runtime-shaders-design.md`](specs/2026-10-22-sdl-gpu-runtime-shaders-design.md). Record: `../record/151-sdl-gpu-runtime-shaders.md`.
Branch `feat/sdl-gpu-runtime-shaders` from `63feea05`. Continues `GA-F` (record 114), `GB-G` (record 137), `BS-` (record 138), `SY-` (record 143).
Divergence labels reserved 805–814: **none taken** (`RC-A`). **Nothing is published** by this item (`BS-H`).

Sources of truth. SwiftUI has no shader API: no SwiftUI claim, no SwiftUI probe. Facts about shadercross are from the pinned source and header
(`1ff05bec573988a98ef9e0260b4da44f512b8367`, read 2026-10-22) and from `docs/probes/sdl-shadercross-runtime.c` run against a local build of the pin (output
under `RC-H`, the arm letters A-G match the probe's).

## RC-A — class M, no divergence, no census row, additive

**Ruling.** Every declaration is MetalUI-only (class M) in `MetalUISDLGPU`; `Backends/SDL` is outside the census (`GA-L`), so no inventory row; each public
declaration still carries a doc comment. Nothing breaks, so **no migration note**. **Cost if wrong.** A map row.

## RC-B — the compiler is optional: loaded at run time, process-wide, never unloaded, never linked

**Question.** Link shadercross, or load it?
**Evidence.** The pinned `CMakeLists.txt` makes `SDL3_shadercross` a shared library (default when SDL3 is shared) that **links DXC and SPIRV-Cross itself**
(`DxcCreateInstance` is an `extern` of the library, `src/SDL_shadercross.c` line 314), so one `SDL_LoadObject` of it pulls the dependents through the loader.
Linking it from SwiftPM would need a `pkgConfig:` or a binary target (PX-J forbids the first, BS-H the second) and every consumer would need DXC (about 1300 ninja steps to build)
installed to build at all.
**Ruling.** `SDL_LoadObject`/`SDL_LoadFunction` (SDL3 is already linked and they are portable) behind a C file in `SDLBridge` that carries **our own mirror structs** of the
five shadercross structs it calls, so MetalUI builds with no shadercross header. Loaded once under a lock, `SDL_ShaderCross_Init` once, **no `Quit`, no unload** (DXC cannot be unloaded safely
and a second load would double the resident set). An absent library is a thrown, named `compilerUnavailable`, never a trap (`RC-C`).
**Cost if wrong.** The mirror structs drift from a newer shadercross: the pin is the contract; a probe arm prints the real `sizeof`/`offsetof` and a lane-B test compares them when the header is on the machine.

## RC-C — lookup order mirrors `BS-C`, as a pure function

**Ruling.** (1) the explicit `libraryPath:`, (2) `METALUI_SHADERCROSS_LIB` (a file, or a directory holding the platform's library name), (3) beside the executable and its `../lib`,
(4) the sibling `lib` of the `METALUI_SHADERCROSS` executable (the pin's install layout, which `BS-C` already knows), (5) the plain library name on the loader path. **An explicit path
or variable naming a missing file is an error, not a fall-through** (`BS-C`'s rule). The list is `MetalUIShaderCompile`'s pure `RuntimeLibraryLocator` (no SDL trait, runs on
every platform's CI), so the order is pinned where no GPU and no library exist; the error text names every path with its reason. **Cost if wrong.** An app sets one more variable.

## RC-D — thread safety: compiles run concurrently; diagnostics are read with the app's own `SDL_GetError` on the calling thread

**Evidence (source, corroborated by probe arms B and F, RC-H).** `CompileFromHLSL` builds a **non-static** `IDxcCompiler3` per call, with the comment "since the functions we call on it are not thread-safe";
the header marks the HLSL and reflection calls "safe from any thread"; `SDL_ShaderCross_Init` only loads `D3DCompile` (Windows DXBC) and always answers true, but "should only be called once, from a single thread".
Failures are `SDL_SetError` (thread-local), for example `"HLSL compilation failed: <DXC text>"`; warnings are `SDL_LogWarn` (RC-I).
**Ruling.** `Init` under the loader's lock; **compiles are not serialized** (a serialized compile would make two engines on two threads wait for each other for seconds). The error text is read on the
failing thread **before any other call** with the app's `SDL_GetError`. That only holds when shadercross and the app share one SDL3 instance, which a plain shared install does and a static SDL in the app would
not: `selfTest` therefore compiles a deliberately broken kernel and requires non-empty diagnostics, and a compile that fails with an empty message throws `compileFailed` saying so (`RC-J`).
**Cost if wrong.** A DXC race would show as a flaky identical-bytes test (`eightThreadsCompileTheSameKernelToIdenticalBytes`); the lock is a one-line change to the C shim.

## RC-E — a bytes initializer on `SDLGPUShaderBlob`, validated before SDL sees it

**Ruling.** A public throwing `SDLGPUShaderBlob.init(name:stage:bytes:format:entryPoint:…counts…:threadCount:)` plus a public `Format` enum (`spirv`, `msl`, `dxil`; the raw value is the `SDL_GPUShaderFormat` bit
converted explicitly, Windows `Int32`), for an app that loads a cached blob its own run-time compile made. It validates what is checkable without a device: non-empty bytes and entry, SPIR-V magic and whole words, DXIL's
`DXBC` container magic, MSL containing its entry point, compute thread axes all >= 1 and x*y*z <= 1024 (D3D12's limit, the tightest of the three), every count in `0...64` (a **sanity bound**: `SDL_gpu.h` documents no per-kind maximum, so the
real refusal is SDL's, which `compileComputePipeline` already throws naming the stage, `GB-G`). `compileComputePipeline(_:)` and `makeComputePipeline(_:)` are unchanged: they read the blob's fields, so one path serves a directory blob and a compiled one.
**Alternative rejected.** A second pipeline-from-bytes verb on the device: two paths to keep equal. **Cost if wrong.** A tighter or looser sanity bound is one constant.

## RC-F — the target is the device's driver; reflection always comes from the SPIR-V; DXIL from HLSL

**Ruling.** `SDLGPUShaderTarget(driver:)` maps `vulkan` to SPIR-V, `metal` to MSL (entry `main0`), `direct3d12` to DXIL, any other driver (SDL's `private`, a future one) to `unsupportedTarget` naming it, like `SDLGPUShaderLibrary`'s
`load`. MSL is `TranspileMSLFromSPIRV` of the SPIR-V; DXIL is `CompileDXILFromHLSL`, the route the build tool takes, so the bytes agree with a checked-in blob; **the reflection is always `ReflectComputeSPIRV` of the SPIR-V**, so an MSL or DXIL compile also runs
HLSL to SPIR-V once (the cost is in `RC-H`). DXBC (`D3D12` without `dxil`) is not offered: SDL's D3D12 driver takes DXBC as well, but the build tool and the app shaders already name DXIL only. **Cost if wrong.** A DXBC arm.

## RC-G — compute only

**Ruling.** Only `SDL_SHADERCROSS_SHADERSTAGE_COMPUTE`. The user asked for compute (MetalCreator's kernels); the graphics reflection, resource-info and I/O metadata is a separate surface with no consumer. Named in the spec's deferred list. **Cost if wrong.** A follow-up item on a request.

## RC-H — measurements (dated, never pinned; pins count work)

**Probe** `docs/probes/sdl-shadercross-runtime.c`, **2026-10-22**, a local build of the pin (Release, vendored, `-DSDLSHADERCROSS_INSTALL=ON`, Ninja `-j6` on a loaded Mac, **about 25 minutes of wall clock**
for 1303 steps, other sessions building at the same time; docs/packaging.md §4a quotes 8 min 30 s on an idle 10-core one), macOS arm64, SDL 3.4.0 (Homebrew), the library loaded by full path with `SDL_LoadObject`. Output, arm by arm:

- **A (positive control).** `spirv ok, 1092 bytes, magic 07230203`.
- **B (separating arm).** A kernel with a syntax error returns NULL and `SDL_GetError()` holds 467 bytes starting `HLSL compilation failed: hlsl.hlsl:1:32: error: expected parameter declarator` with the source line and a caret.
  So DXC's own text, with file, line and column, reaches the app through the app's own `SDL_GetError` (one SDL3 instance).
- **C.** Reflection of the control kernel (one `StructuredBuffer`, one `RWStructuredBuffer`, one `cbuffer` in the `space0/space1/space2` convention): `samplers=0 rotex=0 robuf=1 rwtex=0 rwbuf=1 ubo=1 threads=64,1,1`.
- **D.** MSL of it: 577 characters, contains `main0`.
- **E.** DXIL from HLSL: 3368 bytes, `DXBC` container, a **non-zero** digest, **identical bytes with and without `libdxil.dylib` in the directory** (so on macOS DXIL does not need it; whether Windows' D3D12 accepts it without
  `dxil.dll` beside is **unmeasured**, human check RC1, and the package ships it regardless, `RC-K`).
- **F.** Eight threads, three SPIR-V compiles each: 0 mismatches against the serial bytes.
- **G.** Compile times of generated kernels (every line a `float` expression with a call, a `sqrt`, an `abs`, a `floor`): **200 lines 0.044 s to SPIR-V (47,736 bytes), 1000 lines 0.421 s (242,936 bytes), 2000 lines 1.372 s (471,020 bytes)**;
  SPIR-V to MSL **0.004 s, 0.019 s, 0.043 s**. HLSL to SPIR-V is **DXC, about 99 % of a Metal-route compile**, and grows faster than linear. Run time of the first compile in a process (library load, DXC start) is in `runtime-compile-measure.sh` (lane B).
- **H.** The install has **no `LC_RPATH`** (`otool -l`), so `dlopen` by full path fails: `Library not loaded: @rpath/libspirv-cross-c-shared.0.dylib` (the CLI works because `bin/shadercross` has one). **Preloading the two dependents by full path first makes the load work** (arm H, `RC-N`).
- **I.** The real layout: `HLSL_Info` 40 bytes (source 0, entrypoint 8, include_dir 16, defines 24, shader_stage 32, props 36), `HLSL_Define` 16, `SPIRV_Info` 32 (bytecode 0, size 8, entrypoint 16, shader_stage 24, props 28), `ComputePipelineMetadata` 36 (nine `Uint32`). The C mirror's `_Static_assert`s are these numbers.

**Still owed to lane B (named, not measured here):** the Linux aarch64 image (shadercross built there into the volume `metalui-shadercross-sdl-gpu-runtime-shaders`; probe arms A-I and G's SPIR-V times, and arm H's SONAME matching on glibc);
the same three kernels' DXIL times; the first-compile cost; a real dispatch of a compiled kernel (Metal via MSL here, lavapipe via SPIR-V there). **Cost if wrong.** None: no pin rests on a time.

## RC-I — warnings are not captured

**Ruling.** DXC warnings go to `SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, …)` in the pinned source. Capturing them needs `SDL_SetLogOutputFunction`, **process-wide**, which a library must not take from the app. A compile that succeeds with warnings succeeds, and the warning stays in SDL's log. **Cost if wrong.** A warning text API later.

## RC-J — `selfTest` fails by throwing, and tests its own diagnostics path

**Ruling.** `selfTest(for:)` throws `compilerUnavailable` without the library (an app's `--self-test` then exits non-zero naming the paths), compiles a four-line kernel, compiles a broken one and requires diagnostics, and with a device runs one dispatch with a readback. The report names driver, format, library path, compiled bytes and seconds. **Cost if wrong.** A report field.

## RC-K — packaging: what ships, where, under which licence

**Evidence.** The install of the pin (`cmake --install`, same build as `RC-H`): `lib/libSDL3_shadercross.0.0.0.dylib` (+ symlinks), `libdxcompiler.dylib` **27,868,432 bytes**, `libdxil.dylib` 2,045,120, `libspirv-cross-c-shared.0.68.0.dylib` (small), **32 MB** of `lib` in all,
`libSDL3.0.dylib` linked by absolute Homebrew path (the app's own SDL3, which is why one `SDL_GetError` serves, `RC-D`), **no LC_RPATH** anywhere in the library (`RC-N`). `share/licenses/SDL3_shadercross/LICENSE.txt` is installed.
Licences read in the checkout at the pin: shadercross **zlib**; the DXC fork (`external/DirectXShaderCompiler/LICENSE.TXT`) **LLVM Release License, University of Illinois/NCSA Open Source License**, 2003-2015, with a bundled third-party list;
SPIRV-Cross **Apache-2.0**; SPIRV-Tools **Apache-2.0**; SPIRV-Headers Khronos MIT-style.
**Ruling.** Four files ship per platform: shadercross, dxcompiler, spirv-cross (`libspirv-cross-c-shared`), and **dxil** (Linux `libdxil.so`, Windows `dxil.dll`, macOS `libdxil.dylib`: needed to sign DXIL on Windows, unproven absent, so shipped), **all in one directory** that `RC-C` finds
(Linux tarball `lib/` with `bin/` beside it; AppImage `usr/lib`; Windows zip beside the `.exe`; macOS `.app` `Contents/Frameworks`), **about 32 MB** (a MetalCreator package grows by that; this is the cost the user accepted by ruling xp-c). `THIRD-PARTY-NOTICES.md` gains an
"optional run-time shader compiler (not vendored, not published)" section with these five licences. An app that does not call the compiler ships none of it. **Cost if wrong.** A `LICENSE` list edit.

## RC-L — graphics shaders deferred

See `RC-G`. **Owner:** the first app that asks.

## RC-M — no compile cache in MetalUI

**Ruling.** The app owns the source hash and a cache directory; MetalUI gives the bytes initializer (`RC-E`) to load a cached blob and nothing else. A cache keyed wrongly (a different shadercross build or driver format) is the app's bug and the initializer's validation catches a wrong magic. **Cost if wrong.** A `SDLGPUShaderCache` type later.

## RC-N — dependents are preloaded by full path; nothing relies on an rpath or the loader environment

**Evidence.** `RC-H` arm H: the pin's install has no `LC_RPATH`; loading `libSDL3_shadercross` by full path fails on its `@rpath` dependents; loading `libdxcompiler` and `libspirv-cross-c-shared` first by full path, then it, succeeds and every arm passes.
dyld (and glibc by SONAME) treat an already-loaded image of the same install name as satisfying a dependency (glibc: **to be measured in the Linux image by lane B**; the ruling falls back to `$ORIGIN` rpath advice in packaging if it fails).
**Ruling.** After `RC-C` finds the main library, the loader preloads every sibling file of the same directory whose name holds `dxcompiler`, `spirv-cross` or `dxil` (a required two named in the error if they are missing, `dxil` optional) **before** it; on Windows the C file also calls
`SetDllDirectoryW` on that directory (compiled by CI only). The app never sets `DYLD_LIBRARY_PATH`/`LD_LIBRARY_PATH` (SIP strips the first from a hardened or system process anyway). The preload set is a pure function of the directory listing in `RuntimeLibraryLocator`
(`thePreloadSetIsTheDependentsInTheLibrarysDirectory`). **Alternative rejected.** Requiring the packager to rebuild with `CMAKE_INSTALL_RPATH`: it changes the pin's recipe and every consumer's build. **Cost if wrong.** A renamed dependent (a different shadercross build) is not preloaded and the load error names it.

## RC-O — the process cache is not a test seam; an explicit path after a load is checked

**Defect found by the critic.** Spec 5 tests 13-14 need "no library" after another test loaded one; `shared()` is process-cached. **Ruling.** A `package` seam `SDLGPUShaderCompiler.load(candidates:)` runs the locator list and returns a compiler (or the `compilerUnavailable`) **without touching the cache** (and the C recorder `mui_sc_loads` counts only cached loads); `shared(libraryPath:)` with a path that differs from the already-loaded library throws `SDLGPUShaderCompileError.libraryAlreadyLoaded(loaded:requested:)` (never silently ignores the argument, never reloads). **Cost if wrong.** One more error case.

## RC-P — the compile guard is a plain-import file plus a source scan, not a root typecheck fixture

**Defect found.** The spec said the guard sits in root `Tests/` or "lane B decides". `MetalUISDLGPU` is empty without the `SDL` trait, so a root fixture cannot name it. **Ruling.** See spec 5 "Guard". **Cost if wrong.** none.

## RC-Q — corrections of fact: lane A's tests are root tests, and the C declarations go in `SDLBridge.h`

**Defects found.** (1) `MetalUIShaderCompileTests` is a **root** target at `Tests/MetalUIShaderCompileTests` (`Package.swift` line 288), not under `Backends/SDL/Tests`, so the root count moves (4371 + lane A's tests) and Linux/Windows CI run them (wanted: that is where the lookup order is pinned). (2) `SDLBridge` has one umbrella header `include/SDLBridge.h` and no module map, so `include/SDLShaderCross.h` would not reach Swift: declarations are appended there. **Cost if wrong.** A build failure, caught at lane B's first commit.

## RC-R — lane split rebalanced

**Defect found.** Lane B held the shim, the Swift API, three test files, the packaging doc, notices and every measurement (a 25-minute DXC build in two environments). **Ruling.** Lane A takes packaging, notices, the Linux-image shadercross build and measurements (independent files, no dependency on B's code); lane B is shim, API and tests, and depends only on lane A's pure `package` types. The macOS `selfTest`/dispatch numbers B records in its own record section lines; A merges them into RC-H at the Record phase.

## RC-S — the concurrency test uses different kernels per thread

**Defect found.** `eightThreadsCompileTheSameKernelToIdenticalBytes` could not redden for a shared output buffer (identical bytes hide a race). **Ruling.** Each thread compiles a kernel differing by `-DK=<i>`; each result must equal that K's serial compile. **Cost if wrong.** none.

## RC-T — lane A's `package` API, as lane B calls it

**Ruling.** `MetalUIShaderCompile` (portable, Foundation-free for these two files, `package`): `RuntimeLibraryLocator.attempts(explicit:environment:executableDirectory:windows:macOS:fileExists:directoryExists:)`
returns the ordered `[Attempt]` (path, `Source`, `exists: Bool?`, reason; the spec's `candidates(...)` spelling is this), `loadOrder(_:)` is the list of paths to `SDL_LoadObject` in order and the one place that
turns an explicit or variable path naming a missing file into an error (`ComputeValidationError.libraryMissing`), `describe(_:loadFailures:)` is the `path: reason` text (a refused load replaces the reason with
`failed to load: <SDL text>`), `libraryNames(windows:macOS:)`, `preloadSet(directory:listing:windows:macOS:)`. `ComputeBlobValidation.validate(bytes:format:entryPoint:stage:reflection:)`, `validate(_ reflection:)`,
`validateBytes`, `validateEntryPoint`, `validateSource`, `validateDefine(s)`, `target(forDriver:)` over `ComputeBlobFormat`, `ComputeBlobStage`, `ComputeReflection` and the error `ComputeValidationError`
(`invalidInput`, `malformedReflection`, `unsupportedTarget`, `libraryMissing`), which lane B maps onto the public `SDLGPUShaderCompileError`. Choices a lane-B author must not undo: SPIR-V magic is
**little-endian only** (`03 02 23 07`; a big-endian word stream is refused, as shadercross never writes one); a define value may be empty or nil, a name is an ASCII identifier, an entry point likewise;
a count is `0...64`, a thread axis `>= 1`, `x*y*z <= 1024` with an overflowing product refused; a **preload group matches by file stem** (`dxcompiler`, `dxil`, prefix `spirv-cross`), so `libdxilconv` and
`libdxcompiler.dylib.bak` are ignored, every version symlink of a group is preloaded (one image), shortest name first. The loader names left to the loader path are a bare list, never existence-checked.
**Cost if wrong.** A signature moves with lane B's first commit.

## RC-U — Linux aarch64 (glibc) facts: arm H and the dependents, measured 2026-10-22

**Evidence** (the pin built in the image `metalui-portable`, Ubuntu 24.04 aarch64, clang, Release, volume `metalui-shadercross-sdl-gpu-runtime-shaders`; **a first build stopped at step 1115 of 1304 with `No space left on device`** when the OrbStack VM filled, and the resumed build finished). `readelf -d`: `libSDL3_shadercross.so.0.0.0` NEEDED
`libSDL3.so.0`, `libspirv-cross-c-shared.so.0`, `libdxcompiler.so`, **no RPATH or RUNPATH** (`ldd`: both dependents `not found`); `libdxcompiler.so` carries RUNPATH `$ORIGIN/../lib` and SONAME `libdxcompiler.so`; `libdxil.so` SONAME `libdxildll.so`, RUNPATH `$ORIGIN/../lib`.
Probe arms on glibc, all as on macOS (RC-H): **H negative**, load by full path alone: `libspirv-cross-c-shared.so.0: cannot open shared object file`. **H positive**, after preloading `libdxcompiler.so` and `libspirv-cross-c-shared.so.0` by full path: every arm passes, so glibc, like dyld, accepts an
already-loaded image of the same SONAME (the ruling of RC-N stands; no `$ORIGIN` advice needed). A (1092 bytes, magic `07230203`), B (467 bytes of DXC text, `hlsl.hlsl:1:32: error: expected parameter declarator`), C (`robuf=1 rwbuf=1 ubo=1 threads=64,1,1`), D (577 characters, `main0`), F (8 threads x 3 compiles, 0 mismatches), I (the same struct sizes and offsets as macOS: 40, 16, 32, 36). **E:
DXIL is 3,368 bytes with a non-zero digest, identical with `libdxil.so` absent and present** (a relocated copy of the four other files), and the same bytes on macOS (also `libdxil`-independent there: `libdxil.dylib`'s install name is `libdxildll.dylib`, found only through `@executable_path/../lib`). So `libdxil` is not needed on Linux aarch64 or macOS to *produce* DXIL; Windows is unmeasured (human check RC1) and the zip ships it (`RC-K`).
Install sizes: aarch64 Linux `lib` 39 MB (`libdxcompiler.so` 33,305,136, `libdxil.so` 2,724,952, `libspirv-cross-c-shared.so.0.68.0` 4,033,808, `libSDL3_shadercross.so.0.0.0` 74,016); macOS `lib` 32 MB (`libdxcompiler.dylib` 27,868,432 as in RC-K).
**Cost if wrong.** None: facts for packaging.

## RC-V — compile-time measurements, dated 2026-10-22 (never pinned)

**Instrument.** `docs/probes/runtime-compile-measure.sh` (+ `.c`): median of 3 of HLSL to SPIR-V, SPIR-V to MSL and HLSL to DXIL for generated kernels of 200, 1000 and 2000 lines, the first compile in a process, the library load. **Linux aarch64 image, idle (load 0.16): 200 lines 0.056 s to SPIR-V (47,736 bytes), 0.005 s to MSL, 0.085 s to DXIL (18,356 bytes); 1000 lines 0.564 / 0.021 / 0.679 s (242,936 / 84,372 bytes); 2000 lines 2.658 / 0.057 / 2.904 s (471,020 / 159,860 bytes);**
first compile 0.056 s, load 7 ms. **macOS arm64 under a load average of 265 to 470 (other sessions: an upper bound, not a reading of the machine):** 0.081 / 0.004 / 0.121 s, 0.441 / 0.018 / 0.567 s, 1.588 / 0.063 / 2.546 s; first compile 0.081 s, load 0.146 s. The idle-Mac figures of RC-H (0.044 / 0.421 / 1.372 s to SPIR-V) stand as the quieter reading.
**Reading.** DXC's HLSL to SPIR-V is more than 95 % of a Metal-route compile, grows faster than linearly (2000 lines is about 4.7 times the 1000-line kernel on Linux) and DXIL costs 9 to 52 % more than SPIR-V; a 1000-line kernel compiles in about half a second, so a solid that changes should compile off the main actor and be cached by the app (`RC-M`).
**Cost if wrong.** None: no pin rests on a time.

## RC-W — lane A's mutations ran as filtered sets (see record)

**Ruling.** Lane A's 18 tests live in a pure target no other test references, so each mutation ran the **`MetalUIShaderCompileTests` filter** (33 tests, 0.4 to 1.1 s per run) and the full unfiltered root suite ran once on the final tree (4389 tests, 4371 + 18). Twenty-one mutations, each applied to one spelling and restored with `git checkout`, `git status --short` clean after each: one survived
(M9a, an accepted empty byte array, because the SPIR-V magic check also refused it and the test only looked for the word "bytes"); the test now requires `bytes is empty` and the mutation reddens `emptyBytesAnEmptyEntryPointAndAGraphicsStageAreRefused`. **Cost if wrong.** None.

## RC-X — lane B's API corrections of fact: `package` is invisible to the `MetalUISDL` tests, `selfTest` is async, and the seam is internal

**Defects found while building.** (1) The `Backends/SDL` tests are the package `MetalUISDL`; `MetalUIShaderCompile` and `MetalUISDLGPU` are root-package targets, so a **`package` symbol is not reachable from those tests** (only `internal` through `@testable`). The spec's `package` seam (`load(candidates:)`, `ProcessCache`) is therefore **internal**, and its parameter type is `SDLGPUShaderCompiler.LibraryAttempt`, a wrapper of lane A's `RuntimeLibraryLocator.Attempt` (whose memberwise initializer is internal: lane A's file gained one `package init`, additive). The plain-import guard (`RC-P`) scans that these stay non-public. (2) A device self test builds a pipeline, dispatches and reads a **buffer** back, and the only buffer readback is `async` (`download`): `selfTest(for:)` is **`async throws`** (the spec said `throws`), as an instance member and as a static convenience `selfTest(for:libraryPath:)` that does `shared()` first, so an app's `--self-test` is one call that throws `compilerUnavailable` without the library. (3) The report's `format` is the target's case name as a `String` (`spirv`, `msl`, `dxil`), its `driver` `"none"` without a device. (4) The empty-diagnostics test hook is `mui_sc_test_empty_diagnostics(_:)` in the C shim; an empty compiler message is turned into `compileFailed` carrying a fixed sentence (`emptyDiagnostics`) and the self test refuses to pass on it (`RC-D`). (5) `SDL_ShaderCross_Init` runs once per process even when several loads succeed (a seam load in a test): the shim guards it with an atomic. **Cost if wrong.** A signature.

## RC-Y — lane B's verification, mutations and measurements (2026-10-22)

**Red first.** Commit `96fd5539` (tests only, the C shim already built): `cannot find 'SDLGPUShaderCompiler' in scope`, `cannot find 'SDLGPUShaderDefine' in scope`, `cannot find 'SDLGPUShaderTarget' in scope`,
`cannot find type 'SDLGPUShaderCompileError' in scope`, `type 'SDLGPUShaderBlob' has no member 'Format'`, `'SDLGPUShaderBlob' initializer is inaccessible due to 'internal' protection level` (29 errors in all).
**Green:** `Backends/SDL` on macOS with `METALUI_REQUIRE_GPU=1 METALUI_REQUIRE_SHADERCROSS=1` and the pin's install in `METALUI_SHADERCROSS_LIB`: **291 tests in 16 suites passed**, of which 21 are the new `SDLGPURuntimeCompile*` ones (every gated one ran, none skipped); without the variable the eleven gated tests skip naming the variable and the other ten pass.
`METALUI_SHADERCROSS_AT_PIN=1`: SPIR-V, MSL and DXIL of the run-time compile of `append.comp.hlsl` are **byte-equal** to the checked-in build-tool blobs (test 19). **Linux image** (`metalui-portable`, aarch64, lavapipe, shadercross from volume `metalui-shadercross-sdl-gpu-runtime-shaders`, `METALUI_SHADERCROSS_LIB=/vol/install/lib`): **288 tests in 16 suites passed**, every gated test ran, the dispatch test read back through SPIR-V on lavapipe; the 30 XCTests also passed. Root native suite: **4389 tests in 10 suites passed** (4371 + lane A's 18; lane B adds no root test), `FR-J no-argument frame: succeeded=true`; default build 0 `warning:`; inventory and undocumented scripts print nothing.
Self test, wall clock of the test (dated, loaded machines, never pinned): macOS Metal (MSL route, one dispatch) 0.039 s, Linux lavapipe (SPIR-V route) 0.052 s.

**Mutations** (each applied to one spelling, restored with `git checkout`, `git status --short` empty after each, the full unfiltered `Backends/SDL` suite run with the library and a GPU; tests named, not counted):

| Mutation (spelling) | Reddened |
|---|---|
| M13 `load(candidates:)` throws `tried: []` | `aMissingLibraryThrowsCompilerUnavailableListingEveryPathTried`, `everyCompileEntryThrowsCompilerUnavailableWithoutTheLibrary` |
| M14 static `selfTest` answers a report when `shared()` fails | `everyCompileEntryThrowsCompilerUnavailableWithoutTheLibrary` |
| M15 initializer maps `threadCount` as `(y, x, z)` | `theBlobInitializerMakesAPipelineFromTheCheckedInAppShaderBytes`, `theBlobInitializerKeepsEveryCountItWasGiven`, `aCompiledKernelDispatchesAndReadsBack` and six more compile tests |
| M16 initializer validates the bytes but not the reflection | `aMalformedReflectionThrowsBeforeSDLIsCalled` |
| M17 initializer swaps the read-only and read-write buffer counts | `theBlobInitializerKeepsEveryCountItWasGiven`, `theBlobInitializerMakesAPipelineFromTheCheckedInAppShaderBytes`, `aValidKernelCompilesToTheDevicesFormatWithItsReflection` and three more |
| M18 `compileCompute` drops the read-write buffer count | `aValidKernelCompilesToTheDevicesFormatWithItsReflection`, `aCompiledKernelDispatchesAndReadsBack` and five more |
| M19 the C call gets entry point `"mainx"` | eight tests, `eightThreadsCompileDifferentKernelsToTheirOwnSerialBytes` among them |
| M20 the shim never reads `SDL_GetError` | `aSyntaxErrorThrowsCompileFailedWithDXCsText`, `selfTestNamesTheDriverTheFormatAndTheLibrary` |
| M21 the MSL route reports thread count 1 | `aCompiledKernelDispatchesAndReadsBack`, `aValidKernelCompilesToTheDevicesFormatWithItsReflection`, `definesChangeTheCompiledKernel` and two more |
| M22 defines are not passed | `definesChangeTheCompiledKernel`, `eightThreadsCompileDifferentKernelsToTheirOwnSerialBytes`, `aCompiledKernelDispatchesAndReadsBack`, `aValidKernelCompilesToTheDevicesFormatWithItsReflection` |
| M23 `shared()` loads on every call | `aSecondSharedCallReusesTheFirstLoad` |
| M24 one static output buffer in the C shim (and no free) | `eightThreadsCompileDifferentKernelsToTheirOwnSerialBytes` (alone: the identical-kernel arm of the old spec could not have seen it, `RC-S`) |
| M25 the self test skips the broken-kernel arm | `selfTestFailsWhenTheDiagnosticsAreEmpty` |
| M27 the shim fails a compile when `SDL_GetError` is non-empty after a success | **survived**, and is unrealizable at that spelling: DXC's warnings go to `SDL_LogWarn`, not to `SDL_GetError` (`RC-I`). The test now proves its arm is real instead: it counts SDL's warn-priority log lines through `SDL_SetLogOutputFunction` (an unused variable does **not** warn; an implicit vector truncation does) and requires at least one |
| G1 `RuntimeLibraryLocator` made `public` | `theLocatorTheValidationAndTheCShimAreNotPublic` |
| G2 the bytes initializer made `internal` | build failure of `SDLGPURuntimeCompileGuardTests.swift` (`'SDLGPUShaderBlob' initializer is inaccessible due to 'internal' protection level`), reverted |

No mutation was left applied. **Cost if wrong.** None.
