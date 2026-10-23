# 152. shadercross lookup in `<exe dir>/lib`, Microsoft DXC note, XP-G27 carried (XP-G26, packaging note, XP-G27)

Items XP-G26 (must), the packaging note (must) and XP-G27 (low) of the gpui-gap priority list (user request 2026-10-02, MetalCreator `xp-c` tasks 11-13; **not a plan task**), on `feat/shadercross-lookup` from `722f0cd6`. Rulings `SX-A`..`SX-F` in `docs/superpowers/2026-10-23-shadercross-lookup-decisions.md`; spec `docs/superpowers/specs/2026-10-23-shadercross-lookup-design.md`. Class `M`, additive, no public declaration, no divergence (815-824 untouched), no root `Sources/`, `Package.swift`, seam or shader change. Nothing published (`BS-H`).

## 1. What was built

- `RuntimeLibraryLocator.Source.besideExecutableSubLib` (`MetalUIShaderCompile`, `package`) between `besideExecutable` and `besideExecutableLib`: the lookup is explicit, variable, `<exe>`, **`<exe>/lib`**, `<exe>/../lib`, `METALUI_SHADERCROSS` sibling `lib`, loader names, on every platform (`SX-B`). Place text `in lib beside the executable`, so `compilerUnavailable(tried:)` lists it. No load code changed: `load(candidates:)` already preloads dependents from the winner's directory (`SX-C`, `RC-N`).
- Doc comments of the locator and `SDLGPUShaderCompiler`; `docs/packaging.md` 4b (lookup sentence, tarball placement, the Microsoft DXC paragraph with compatibility **unmeasured**, unverified list); `THIRD-PARTY-NOTICES.md` DXC row; human checks group `SX` (`SX1`, `SX2`).
- XP-G27 **carried, not built** (`SX-E`): a portable run-time compile needs libSDL3 in the process (shadercross is an SDL3 library, `RC-D`); that is a second hand-written loader and an app shipping libSDL3. Unmeasured: shadercross with libSDL3 only `dlopen`ed (needs a pin build). The macOS answer is `swift test --traits SDL`.

## 2. Tests

Root (**4398 -> 4402**, `Tests/MetalUIShaderCompileTests/RuntimeLibraryLocatorTests.swift`): tests 1 and 5 amended; new `aLibraryOnlyInExecutableLibIsChosenOnEveryPlatformNaming`, `theLibraryInTheExecutableDirectoryOutranksOneInItsLibSubdirectory`, `thePreloadSetComesFromTheDirectoryOfTheChosenLibrary`, `packagingNamesTheExecutableLibLookupAndMarksMicrosoftDXCUnmeasured` (splits on `\.isNewline`, `SX-F`). `Backends/SDL`: `aLibraryInExecutableLibIsPreloadedFromThere` (13b; **+1**).

## 3. Red runs and mutations

Red first: the tests alone failed to compile (`type 'RuntimeLibraryLocator.Source' has no member 'besideExecutableSubLib'`, three errors), committed as `SX: red pins`. Mutations on the root target ran as the **filtered `MetalUIShaderCompileTests` set** (37 tests, under a second), **a deviation from the full-suite rule**, justified because only that target references the locator (as record 151 lane A); the unmutated full suite passed (4402 in 11 suites). `git status --short` clean after each.

| Mutation | Reddened |
|---|---|
| M1 drop the `<exe>/lib` arm | `aLibraryOnlyInExecutableLibIsChosenOnEveryPlatformNaming`, `theErrorNamesEveryPathTriedWithItsReason`, `theLibraryInTheExecutableDirectoryOutranksOneInItsLibSubdirectory`, the order test, `thePreloadSetComesFromTheDirectoryOfTheChosenLibrary` |
| M2 `<exe>/lib` after `../lib` | the order test (two expectations) |
| M3 join `lib` onto the parent | the same five as M1 |
| M4 omit the place text | `theErrorNamesEveryPathTriedWithItsReason` |
| M5 swap `<exe>` and `<exe>/lib` | `theLibraryInTheExecutableDirectoryOutranksOneInItsLibSubdirectory`, the order test |
| M6 packaging says `measured?` for `unmeasured` | `packagingNamesTheExecutableLibLookupAndMarksMicrosoftDXCUnmeasured` |

`Backends/SDL` (full unfiltered, macOS, `METALUI_REQUIRE_GPU=1`): M7 preload from the parent of the winner's directory **survived the first 13b** (the line named `<exe>/lib` through the path itself); 13b now asserts `<exe>/lib: the dxcompiler library is missing`, and M7 then reddens `aLibraryInExecutableLibIsPreloadedFromThere`. Test 4's "fixed directory" mutation is the pure analogue and is covered by M1/M3.

## 4. Verification

Root native unfiltered after the build: **4402 tests in 11 suites passed**, `FR-J no-argument frame: succeeded=true`, 0 `error:`, only SwiftPM's deprecation `warning:`. `Backends/SDL` macOS **30 + 300** passed; Linux image (`metalui-portable`) **30 + 297** passed. Inventory and undocumented scripts print nothing; no census change (no public declaration). Fourteen images: see the comparison run recorded by the orchestrator (no `Sources/` change, so 0 px by construction). Not run: Windows, a real tarball, Microsoft's DXC against shadercross (human checks `SX1`, `SX2`).
