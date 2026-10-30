# 162. Shader include sources as build inputs (XP-G32)

Item `XP-G32` (MetalCreator gap: a header-only edit did not rebuild or invalidate checked-in blobs; carried from record 161; computed workflow task 2026-10-30, **not a plan task**), on `feat/shader-includes` from master `0ddfd1c4`. Rulings `BT-O`..`BT-U` in `docs/superpowers/2026-10-28-build-tool-shaders-decisions.md`, next `BT-V`. Class `M`, no divergence (895-904 untouched), no census row, nothing published (`BS-H`). Extends record 161; no `Sources/` change outside `Backends/SDL`.

## 1. What was built

- **Include sources are build inputs** (`BT-O`): every `.hlsli` and every non-stage `.hlsl` below `Shaders/` (recursive, not the top-level `compiled/`, symlinked directories skipped, bytewise sorted; a stage-named file below the top level such as `lib/x.vert.hlsl` is never compiled, so it counts) is listed by one function, `IncludeSources.swift`. A plugin cannot import the target, so the marked region is copied byte for byte into `Plugins/CompileShadersOnBuild/Plugin.swift` (internal access, no package name) and a test fails on any difference. A header edit now reruns the build command.
- **`INCLUDES.sha256`** (`BT-P`): reuses `SourceMarker` (message-only `markerName`/`noun` parameters), written by the one tool in both the `--on-build` and command-plugin runs only when headers exist, a stale one removed otherwise.
- **Copy path** (`BT-Q`): with headers present it requires a matching `INCLUDES.sha256`, copies it with the blobs, and names a missing, changed, extra or vanished entry; an `INCLUDES.sha256` with no headers is a named orphan. With shadercross a mismatch is only the existing stale warning.
- **Run time** (`BT-R`): `SDLGPUShaderLibrary.init(directory:verifyingSources:)` also checks `INCLUDES.sha256` when present, with or without a `SOURCE.sha256`. A directory with `SOURCE.sha256` but no `INCLUDES.sha256` compares no headers (strict would break callers whose source directory holds unrelated non-stage `.hlsl`).
- **`-I <source dir>`** (`BT-S`, premise refuted, section 2) on the HLSL to SPIR-V step.
- **Docs** (`BT-T`): `docs/packaging.md` 4a (headers as inputs, `INCLUDES.sha256`, the host-evaluated `#if os(Linux) || os(Windows)` plugin gate; a cross-compile from macOS skips it), `docs/rules/sdl.md`, `docs/rules/decision-prefixes.md`.

## 2. Measurement (`BT-S`)

shadercross built at pin `1ff05bec...` (4a recipe, gitignored `.scratch-shadercross/`). `--help` lists `-I | --include <value>  HLSL include directory`. Absolute source path from cwd `/` fails (`'common.hlsli' file not found`, exit 1, 0-byte `.spv`); a relative source with cwd the source directory compiles (incidental); absolute source plus `-I <dir>` compiles, nested `sub/inner.hlsli` included, trailing slash or not. So shadercross does not resolve includes relative to the source file. A headerless build is unchanged: `MetalUICompileShaders` over `Backends/SDL/Tests/AppShaders` wrote 41 files, `diff -r` identical to `compiled/`.

## 3. Tests

Root **4519 -> 4529** (+10): `IncludeSourcesTests` 14-22 plus changed arms in `ShaderCompileTests`; env-gated `anEnvGatedRunResolvesHeadersThroughTheSourceDirectory` and arms (f)/(g) of the plugin fixture test count while skipped. `Backends/SDL` gains test 17, `anIncludesMarkerIsAcceptedAndCheckedAgainstTheHeaders`. Guards unchanged (277, not re-tallied).

## 4. Mutations (each applied, run, restored with `git checkout`; root filter `MetalUIShaderCompileTests`, SDL filter `SDLGPUShader`)

| Mutant | Reddened |
|---|---|
| `isIncludeSource`: the `.hlsli` arm returns `false` | `includeSourcesAreHeadersAndNonStageHlslBySpelling`, `theWalkListsIncludeSourcesRecursivelyAndSorted`, `theOnBuildCopyRunVerifiesHeadersOnDisk`, `theToolWritesTheIncludesMarkerOnlyWhenHeadersExist`, `theBuildPluginSelectsIncludeSourcesExactlyAsTheToolDoes` |
| walk never recurses | `theWalkListsIncludeSourcesRecursivelyAndSorted`, `theOnBuildCopyRunVerifiesHeadersOnDisk`, `theToolWritesTheIncludesMarkerOnlyWhenHeadersExist`, the region test; in `Backends/SDL` `anIncludesMarkerIsAcceptedAndCheckedAgainstTheHeaders` |
| walk skips every directory named `compiled` | `theWalkListsIncludeSourcesRecursivelyAndSorted`, the region test |
| a symlink to a directory is listed (the `isDirectory` guard dropped) | `theWalkListsIncludeSourcesRecursivelyAndSorted` (first run: **survived** until `linkdir.hlsli` was added to its fixture), the region test |
| a nested `x.vert.hlsl` counts as a stage | `includeSourcesAreHeadersAndNonStageHlslBySpelling`, `theWalkListsIncludeSourcesRecursivelyAndSorted`, the region test |
| bare `.hlsli` accepted | `includeSourcesAreHeadersAndNonStageHlslBySpelling`, the region test |
| `SourceMarker.problems` ignores `markerName` | `theIncludesMarkerHasTheSourceMarkersFormatAndNamesItselfInProblems`, `theCopyPathChecksTheIncludesMarker` |
| copy arm ignores the include problems | `theCopyPathChecksTheIncludesMarker`, `theOnBuildCopyRunVerifiesHeadersOnDisk` |
| no `INCLUDES.sha256` requirement when headers exist | `theCopyPathChecksTheIncludesMarker` |
| copy list lacks `INCLUDES.sha256` | `theCopyPathChecksTheIncludesMarker`, `theOnBuildCopyRunVerifiesHeadersOnDisk` |
| no orphan problem | `theCopyPathChecksTheIncludesMarker` |
| compile arm ignores include problems | `withShadercrossAHeaderEditOnlyWarns` |
| `runOnBuild` reads no includes | `theOnBuildCopyRunVerifiesHeadersOnDisk` |
| tool writes `INCLUDES.sha256` with no headers | `theToolWritesTheIncludesMarkerOnlyWhenHeadersExist` |
| tool never removes a stale one | `theToolWritesTheIncludesMarkerOnlyWhenHeadersExist` |
| tool never writes it | `theToolWritesTheIncludesMarkerOnlyWhenHeadersExist` |
| plugin: includes dropped from `inputFiles` | `theBuildPluginSelectsIncludeSourcesExactlyAsTheToolDoes`; the env-gated fixture arm (f) (**survived on its first run**: the restored source after arm (c) had rerun the command by itself; a settling build was added before the header edit, then the mutant reddens `f.status != 0` and the by-name check on both build systems) |
| plugin: region edited in `Plugin.swift` only | `theBuildPluginSelectsIncludeSourcesExactlyAsTheToolDoes` |
| plan drops `-I` | `theCommandPlanIsHlslToSpirvThenTheDerivations`; with `METALUI_SHADERCROSS` also `anEnvGatedRunResolvesHeadersThroughTheSourceDirectory` (`'common.hlsli' file not found`) |
| `Backends/SDL`: the `INCLUDES.sha256` check skipped | `anIncludesMarkerIsAcceptedAndCheckedAgainstTheHeaders` |
| `Backends/SDL`: the check only when a `SOURCE.sha256` exists | `anIncludesMarkerIsAcceptedAndCheckedAgainstTheHeaders` |

Verification re-ran four of these (`.hlsli` arm, plan drops `-I`, copy list lacks `INCLUDES.sha256`, plugin drops includes from `inputFiles`) with the same reddening. Two survived first and were closed: the directory symlink (fixture gained `linkdir.hlsli`) and the plugin `inputFiles` mutant (a settling build before the header edit).

## 5. Verification

`swift package clean`, native build with tests, unfiltered `swift test --build-system native --no-parallel`: **`Test run with 4529 tests in 12 suites passed after 558.960 seconds`** (implementer's run 557.777), `FR-J no-argument frame: succeeded=true deprecations=2`, no issues. The env-gated plugin fixture test passed with the real shadercross on both build systems. `Backends/SDL` `swift test --filter SDLGPUShader`: 14 tests passed. Closeout inventory and undocumented probes print nothing. Verification found one doc defect (the "next unused" id read `BT-U`, which is used) and fixed it to `BT-V`.

## 6. Carried

Windows is unmeasured (check `BT1`, plus the header arm there, `BT4`); a strict `INCLUDES.sha256` requirement at run time; the carried items of record 161.
