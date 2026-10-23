# Run-time HLSL compute shaders on SDL_GPU (XP-G25) — decisions

Rulings for item XP-G25 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), requested by MetalCreator's `xp-c`
track. Prefix `RC-`. **Next unused: `RC-O`.**
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
