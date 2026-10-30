# 161. App shaders on plain `swift build` (BS-D)

Item `BS-D` (carried by record 138; user request "go ahead with BS-D" 2026-10-28, the user chose **no publish**; **not a plan task**), on `feat/build-tool-shaders` from master `abc2bf46`. Rulings `BT-A`..`BT-N` in `docs/superpowers/2026-10-28-build-tool-shaders-decisions.md`, next `BT-V` (record 162 built `BT-O`..`BT-U`); spec `docs/superpowers/specs/2026-10-28-build-tool-shaders-design.md`. Class `M`, no divergence (895-904 untouched), no census row, nothing published (`BS-H`). **Supersedes `BS-D`** (its three reasons are answered in section 1).

## 1. What was built

- **`CompileShadersOnBuild`** (root product, a `.buildTool()` plugin on every platform) beside the unchanged `CompileShaders` command plugin and `MetalUICompileShaders` tool (`BT-D`). An app target applies it with `plugins: [.plugin(name: "CompileShadersOnBuild", package: "MetalUI")]`, keeps HLSL in `Shaders/` and optional checked-in blobs in `Shaders/compiled/` (`BT-E`). The plugin does no lookup of its own: it runs the one tool as `--on-build` with the plugin's view of `METALUI_SHADERCROSS` and `PATH` on the command line, so a change of either reruns the command (`BT-F`, `BT-B` 2).
- **The decision** (`BuildDecision`, `BuildRun`, pure over the locator's answer, the sources and the checked-in names): shadercross found -> compile all four formats plus `SOURCE.sha256`, warn when a checked-in marker is stale; a variable naming a missing file -> fail; not found and the marker matches and each source has `.json` and `.spv` -> copy exactly those blobs; not found otherwise -> fail naming each problem, the pin and both fixes (install shadercross at `1ff05bec...`, or `swift package compile-shaders` and commit). No silent stale shader (`BS-D` reason 2). `ShadercrossPin.commit` is the one pin constant, tested against `docs/packaging.md`.
- **One output directory**, `<work>/MetalUIAppShaders`, cleared first in both arms (`BT-G`): it becomes a resource of the target on all four layouts measured (`BT-B` 6), so no `resources:` rule. This answers `BS-D` reason 3.
- **Runtime lookup** (`BT-H`): `SDLGPUShaderLibrary.locate(directoryName:resourceBundle:sourceTree:)` (one new public declaration, `MetalUISDLGPU`, outside the census): beside the executable, then the bundle (an autoclosure, evaluated only then, since `Bundle.module` traps when missing), then `sourceTree`.
- Docs: `docs/packaging.md` 4a (opt-in, the two arms table, the error), `docs/getting-started.md` (one line), `docs/guides/cross-platform.md` (one sentence, no swift block), human checks group `BT` (`BT1`-`BT3`), `BS-` decisions amended. The scaffold's starter does not opt in (`BT-I`), so no `SC-` text moved and `METALUI_RUN_SCAFFOLD_BUILD_TEST` is not owed; `Examples/Jotter` has no shaders.

## 2. Measurement (`BT-B`)

A throwaway provider/app package pair (plugin in a dependency, as for an app), macOS arm64 and the Linux image, both build systems. The build command sees the build's environment; a changed command line reruns it; an unchanged build skips it (Linux native once late, `BT-B` 3); the macOS sandbox blocks writes outside the work directory but not reading and running an external shadercross; every declared output is a resource, so only shader outputs may be declared; a directory declared as the one output works on all four layouts; a non-zero exit with `error:` lines fails the build and shows them. shadercross was rebuilt at the pin for it (8 min 29 s, `BT-C`); with it the blobs were byte-identical to `Backends/SDL/Tests/AppShaders/compiled`.

## 3. Tests

Root **4508 -> 4519** (+11): ten always-run in `BuildPluginDecisionTests` and the env-gated `theBuildToolPluginCompilesVerifiesAndRefusesOnAFixturePackage` (`METALUI_RUN_BUILD_PLUGIN_TEST=1`, counts while skipped). `Backends/SDL` gains three `SDLGPUShaderLibraryTests` (the order, the lazy bundle, and `thePublicLocateDoesNotEvaluateItsBundleWhenTheExecutableCandidateOpens`, added by verification).

## 4. Mutations (each applied, run, restored with `git checkout`; root filter `MetalUIShaderCompileTests`, SDL filter `SDLGPUShaderLibraryTests`)

| Mutation | Reddened |
|---|---|
| success arm falls to copy when the marker matches | `withShadercrossTheBuildCompilesAndIgnoresTheCheckedInBlobs`, `theOnBuildRunClearsItsOutputDirectoryInBothArms` |
| marker problems ignored without shadercross | `withoutShadercrossAChangedSourceFailsNamingBothFixesAndThePin` |
| pin dropped from the error | that test, `withoutShadercrossAMissingMarkerOrDirectoryFails` |
| fix 2 dropped from the error | `withoutShadercrossAChangedSourceFailsNamingBothFixesAndThePin` |
| a missing marker counts as matching | `withoutShadercrossAMissingMarkerOrDirectoryFails` |
| copy every file of `compiled/` | `theOnBuildRunClearsItsOutputDirectoryInBothArms`, `withoutShadercrossAMatchingMarkerCopiesExactlyTheBlobsOfEachSource` |
| marker omitted from the copy | `withoutShadercrossAMatchingMarkerCopiesExactlyTheBlobsOfEachSource` |
| json/spv completeness check dropped | `aSourceWithoutItsReflectionOrSpirvBlobFails` |
| locator's missing-named-file error mapped to "not found" | `aVariableNamingAMissingShadercrossFailsAndNeverCopies` |
| output directory not cleared | `theOnBuildRunClearsItsOutputDirectoryInBothArms` |
| empty variable treated as a path | `onBuildArgumentsAreParsedAndAnEmptyVariableIsUnset`, `theOnBuildRunClearsItsOutputDirectoryInBothArms` |
| PATH ahead of the variable | `shadercrossIsFoundByFlagThenEnvironmentThenPath` |
| `ShadercrossPin.commit` changed | `theErrorsPinIsThePackagingDocsPin` |
| stale-marker warning removed | `aStaleCheckedInCopyIsWarnedWhenShadercrossCompiles` |
| parse drops `--checked-in` | four tests (stale warning, missing named shadercross, arguments, output clearing) |
| no-shadercross copy arm always fails (first spelling did not compile, a non-exhaustive switch; second did) | `theOnBuildRunClearsItsOutputDirectoryInBothArms` |
| compile arm writes no marker | `theOnBuildRunClearsItsOutputDirectoryInBothArms` |
| bundle candidate ahead of the executable | `theShaderLibraryLooksBesideTheExecutableThenTheBundleThenTheSourceTree`, `theResourceBundleIsNotEvaluatedWhenTheExecutableCandidateOpens` |
| source tree ahead of the bundle | the same two |
| **public `locate(resourceBundle:)` evaluates its autoclosure eagerly** | **survived**: the tests reached only the internal `lazyCandidates`; now reddens `thePublicLocateDoesNotEvaluateItsBundleWhenTheExecutableCandidateOpens` (the one real gap) |

## 5. Verification

`swift package clean`, native build with tests: 0 errors. Unfiltered `swift test --build-system native --no-parallel`: **4519 tests in 12 suites passed** (725 s), 0 issues, `FR-J no-argument frame: succeeded=true deprecations=2`. The env-gated plugin test passes in both arms (40.8 s with `METALUI_SHADERCROSS` at the real install, 34.1 s without); its `error:` lines are the expected refusals. Plain `swift build` of the root (default build system) and `swift build --package-path Examples/Jotter` complete. `Backends/SDL` filtered `SDLGPUShader|ShaderCompile`: 14 tests in 3 suites passed. Closeout inventory and undocumented probes print nothing. **Not run:** the scaffold build test (manifest unchanged), Linux and Windows consumer builds (`BT1`), a URL dependency (`BT2`), a shipped `.app` (`BT3`).

## 6. Carried

A shadercross fetched or built by the plugin (needs a publish decision, `BS-H`), a CI job building shadercross (`BS-G`), per-app `--formats` on build, rerunning when shadercross is replaced at the same path (`swift package clean`), Windows (`BT-J`).
