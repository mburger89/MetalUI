# shadercross lookup in `<exe dir>/lib`, Microsoft DXC note, XP-G27 (design)

Items XP-G26 (must), the packaging note (must), XP-G27 (low). Rulings: [`../2026-10-23-shadercross-lookup-decisions.md`](../2026-10-23-shadercross-lookup-decisions.md) (`SX-A`..`SX-E`). Branch `feat/shadercross-lookup` from `722f0cd6`.
No SwiftUI/gpui claim, no probe. No public API, no divergence (815-824 untouched), no `Package.swift` change, no `Handlers`/seam/shader change. One lane (disjoint files below).

## 1. Behaviour

`RuntimeLibraryLocator.attempts` lookup after the explicit/variable ranks: `<exe>`, **`<exe>/lib`**, `<exe>/../lib`, `METALUI_SHADERCROSS` sibling `lib`, loader names (`SX-B`). Every platform's naming. The
winner's directory supplies the preload set (`SX-C`, existing code). `compilerUnavailable(tried:)` lists the new path (reason `in lib beside the executable`).

## 2. Files (lane 1, single)

- `Backends/SDL/Sources/MetalUIShaderCompile/RuntimeLibraryLocator.swift`: `Source.besideExecutableSubLib` between `besideExecutable` and `besideExecutableLib` (raw values shift; nothing stores them); the loop over
  `(source, base)` gains the third pair and its place text; doc comments of the file and of `SDLGPUShaderCompiler` (lookup sentence).
- `Backends/SDL/Sources/MetalUISDLGPU/SDLGPUShaderCompiler.swift`: doc comment only.
- `Tests/MetalUIShaderCompileTests/RuntimeLibraryLocatorTests.swift`: tests 1 and 5 amended, new tests below.
- `Backends/SDL/Tests/MetalUISDLTests/SDLGPURuntimeCompilerTests.swift`: test 13b below.
- `docs/packaging.md` 4b (placement list; Microsoft DXC paragraph; unverified list gains `<exe>/lib` and Microsoft's DXC), `THIRD-PARTY-NOTICES.md` (DXC row wording), `docs/verification/human-checks.md` group `SX` (`SX1` shadercross at the pin against Microsoft's DXC on Windows; `SX2` a Linux tarball with `bin/lib` finding `<exe>/lib`), record 152, CLAUDE.md paragraph (Record phase).

## 3. Tests (each red before: the case does not exist)

1. `theLookupOrderIsExplicitThenVariableThenBesideThenSubLibThenParentLibThenSiblingThenLoaderPath` (amends test 1: fake files add `/app/bin/lib/<dylib>`; expected order `[/app/bin/<dylib>, /app/bin/lib/<dylib>, /app/lib/<dylib>, /sdk/lib/<dylib>, <dylib>]`; sources sorted, contains `.besideExecutableSubLib`). Mutations: drop the arm (red: order), put it after `../lib` (red: order).
2. `aLibraryOnlyInExecutableLibIsChosenOnEveryPlatformNaming` (`.dylib`, `.so.0` then `.so`, `.dll`; only `<exe>/lib/<name>` exists; `loadOrder` first is that path, ahead of the loader name). Mutation: join `"lib"` onto the parent instead of the directory (red).
3. `theLibraryInTheExecutableDirectoryOutranksOneInItsLibSubdirectory` (both exist; `<exe>` first). Mutation: swap the two sources' order (red with test 1 too; named here for the arm).
4. `thePreloadSetComesFromTheDirectoryOfTheChosenLibrary` (`preloadSet(directory: parent of chosen path)` over a `<exe>/lib` listing returns `/app/bin/lib/...` paths for dxcompiler, spirv-cross, dxil). Mutation: `preloadSet` joins onto a fixed directory (red).
5. `theErrorListsTheExecutableLibPath` (amends test 5: `/app/bin/lib/<dylib>: no such file (in lib beside the executable)` is a line). Mutation: omit the pair's place text (red).
6. `aLibraryInExecutableLibIsPreloadedFromThere` (`MetalUISDLTests`, 13b; temp directory `<tmp>/bin/lib` holding a zero-byte decoy `libSDL3_shadercross.*`; `load(candidates:)` over `libraryAttempts(executableDirectory: <tmp>/bin, fileExists/directoryExists real)` throws `compilerUnavailable` whose line for the decoy contains `failed dependents` and `<tmp>/bin/lib`). Red before: the decoy is never an attempt. Mutation: preload from `<exe>` (red).
7. Doc check: `packaging.md` 4b names `<exe>/lib` in its lookup sentence and Microsoft's DXC with the word `unmeasured` (an existing doc test pattern, or a plain `String.contains` test in `MetalUIShaderCompileTests` reading the file by `#filePath`).

Mutations run unfiltered (root suite 4398 at `722f0cd6`, and `Backends/SDL` on macOS), `git status --short` after each, names of every reddened test recorded. The Linux image runs `Backends/SDL` (a Swift change in `MetalUIShaderCompile`).

## 4. Demo and human checks

No demo, no pixel change (fourteen images 0 px). Human checks group `SX`: `SX1`, `SX2` above (agents cannot run Windows with Microsoft's DXC, nor a packaged tarball).

## 5. Scope

Deferred: XP-G27 (`SX-E`; owner the first Mac-only consumer; one measurement owed), compatibility of shadercross with Microsoft's DXC (`SX-D`; owner a Windows run, `SX1`). Not changed: the `SDL` trait default, `RC-B`'s single load.
