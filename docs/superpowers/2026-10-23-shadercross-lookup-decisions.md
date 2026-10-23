# shadercross lookup in `<exe dir>/lib`, the Microsoft DXC note, run-time compile in the macOS default build (XP-G26, XP-G27) - decisions

Rulings for items XP-G26 and XP-G27 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), from MetalCreator's `xp-c` tasks 11-13.
Prefix `SX-`. **Next unused: `SX-F`.**
Spec: [`specs/2026-10-23-shadercross-lookup-design.md`](specs/2026-10-23-shadercross-lookup-design.md). Record: `../record/152-shadercross-lookup.md` (written at the Record phase).
Branch `feat/shadercross-lookup` from `722f0cd6`. Continues `RC-C`, `RC-N` (record 151) and `BS-H`. Divergence labels reserved 815-824: **none taken** (`SX-A`). **Nothing is published** (`BS-H`).

Sources of truth. SwiftUI and gpui have no run-time shader compiler lookup: no SwiftUI claim, no probe. Facts about the library layout are from the code at `722f0cd6`
(`RuntimeLibraryLocator.swift`, `SDLShaderCross.c`) and from `RC-N`/`RC-U`'s measurements; anything not re-measured here is marked **unmeasured**.

## SX-A - class M, additive, no public declaration, no divergence

**Ruling.** `RuntimeLibraryLocator` is `package`; `SDLGPUShaderCompiler.libraryPath`/`compilerUnavailable(tried:)` keep their spelling. One `package` enum case is added, so no census row, no inventory
row, no divergence. **Cost if wrong.** None visible outside `MetalUIShaderCompile`.

## SX-B - `<exe dir>/lib` ranks directly after `<exe dir>` and before `<exe dir>/../lib`, on every platform

**Ruling.** New `Source.besideExecutableSubLib`, rank between `besideExecutable` and `besideExecutableLib`: explicit, variable, `<exe>`, **`<exe>/lib`**, `<exe>/../lib`, `METALUI_SHADERCROSS`'s sibling `lib`, loader path.
Reasoning: the order is nearest first (the directory itself, one level down, one level up, then outside the app); a tarball or AppImage with RUNPATH `$ORIGIN/lib` keeps its libraries in `<exe>/lib`, and a build
that has both `<exe>/lib` and `../lib` is the app's own deliberate layout, where the closer one is the one it just wrote. **Windows keeps the candidate** (one extra stat, no branch): Windows has no `lib/` convention
for an app, but a zip with a `lib\` folder is legal and loads (the preload by full path, `RC-N`, resolves dependents without a DLL search path), and a uniform list means the three platforms' pins are one test
over three namings. The load order stays "existing files in lookup order", so a file in `<exe>` still wins over one in `<exe>/lib`. **Cost if wrong.** An app with two copies picks the nearer one; it sets
`METALUI_SHADERCROSS_LIB` or `libraryPath:` to choose.

## SX-C - the preload runs from whichever directory won, and the error lists the new place

**Ruling.** No new load code: `SDLGPUShaderCompiler.load(candidates:)` already derives the dependents' directory from the winning path (`RC-N`), so `<exe>/lib/libSDL3_shadercross.*` preloads `dxcompiler`,
`spirv-cross` and `dxil` from `<exe>/lib`. `compilerUnavailable(tried:)` lists the new path because `describe` walks every attempt, with reason `"in lib beside the executable"`. Pins: the pure order test, a pure
"preload directory is the winner's directory" test, and a `MetalUISDLTests` test that a decoy library file in a temp `<exe>/lib` fails with `failed dependents ... <exe>/lib: the dxcompiler library is missing`,
which can only be said if the preload directory is that one (no real shadercross needed, runs everywhere the SDL tests run). **Cost if wrong.** A loader that skipped the preload would fail with the loader's text, caught by that test.

## SX-D - Microsoft's prebuilt DXC may replace the libsdl-org fork; compatibility is unmeasured

**Ruling.** `docs/packaging.md` 4b says an app may ship Microsoft's DXC release (MetalCreator uses v1.9.2602 on Windows) instead of the fork: then `dxcompiler.dll` and `dxil.dll` are Microsoft's and come
under **their** licence files (the release's `LICENSE-LLVM.txt` and `LICENSE-MIT.txt`, read from the release archive by the app, not from this repo), which the app ships; `THIRD-PARTY-NOTICES.md` names the fork row as "or
Microsoft's release". **No compatibility is claimed**: shadercross at the pin was built against the fork (branch `1.8.2502-SDL`) and **was not run against Microsoft's DXC here**; the doc says so, names the one thing
that could differ (the `IDxcCompiler3` interface and its flags, and `dxil.dll` signing that Microsoft's release does ship), and points to a human check (`SX1`). **Cost if wrong.** A reader trusts an unmeasured pairing; the
sentence "unmeasured" is the guard. **Measurement owed:** build shadercross at the pin against the release's `dxcompiler.dll` on Windows and run probe arm A-E.

## SX-E - XP-G27 carried: a portable run-time compile needs libSDL3 in the process, which the macOS default build does not link

**Evidence (code, `RC-D`, `RC-N`; no new build was made).** `SDLShaderCross.c` loads shadercross with `SDL_LoadObject` and every failure text is `SDL_GetError()`; `RC-D`'s measured rule is that the app's SDL3 and
shadercross's SDL3 must be **one instance** or the compiler's text is lost (the self test checks it). shadercross itself is an SDL3 library: its own errors, its allocations (`mui_sc_free` is `SDL_free`) and
its logging are SDL3's. So an SDL-free route is `dlopen("libSDL3")` plus the five shadercross symbols plus `SDL_GetError`/`SDL_free`/`SDL_ClearError` by `dlsym`: a **second, hand-written loader** (a new C target in the `PC-A` portable
list beside `SDLShaderCross.c`, or `SDLGPUShaderCompiler` forwarding to it, with libSDL3 itself found by a second lookup list) and an **app that ships libSDL3** (about 3 MB, zlib) on a Mac that never needed it.
**Not measured:** whether shadercross loads with libSDL3 only `dlopen`ed (not linked) - needs a build of the pin (10-25 minutes, the previous one deleted) - and it would not change the first two costs. **Ruling:** carried, not built.
It is not cheap (new target, a second lookup, a second set of platform pins, an SDL3 licence note for macOS apps) and not clean (it would fork `RC-B`'s "one implementation, one load"). The macOS answer today is the
`SDL` trait: `swift test --traits SDL` in the root on a Mac compiles and loads (`RC-` record 151, measured). **Re-open when** a Mac-only app (no SDL) asks, with the one measurement above and the cost of shipping libSDL3 stated.
`SDLGPUShaderCompiler` is **not** changed and the `SDL` trait is not made default. **Owner:** the first Mac-only consumer. **Cost if wrong.** A Mac test of run-time HLSL needs the trait.
