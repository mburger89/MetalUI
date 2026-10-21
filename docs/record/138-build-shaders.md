# 138 - Build-time app shaders (XP-G20)

Branch `feat/build-shaders` from `11dca65e`. Not a plan task: item S12 of the gpui-gap list, requested by MetalCreator 2026-10-21 as XP-G20 (wanted, not blocking).
Spec `docs/superpowers/specs/2026-10-21-build-shaders-design.md`; rulings `BS-A`...`BS-L` in `docs/superpowers/2026-10-21-build-shaders-decisions.md` (next `BS-M`).
Divergence labels 675-684 reserved: **none taken** (class `M`, no SwiftUI claim, no probe). **Nothing was published** (`BS-H`): no release, tag, package, image or registry
push, no CI. One lane. Human checks: group `BS`, `BS1`...`BS4`.

## 1 What landed

- `MetalUIShaderCompile` (root manifest, `path:` into `Backends/SDL/Sources/`, **outside the `SDL` trait**, in the portable list, Foundation only, every declaration `package`): `SHA256`
  (`BS-I`), `ShaderStage`/`ShaderFormat`/`ShaderSource`, `ShaderCompilePlan` (the argument vectors), `ShadercrossLocator` (`--shadercross`, `METALUI_SHADERCROSS`, `PATH`; the `lib` beside `bin` first on the
  loader path, `BS-C`), `SourceMarker` (the `SOURCE.sha256` bytes and its problems), `CompileArguments`, `ShaderCompiler.run`.
- `MetalUICompileShaders` (executable product) and the `CompileShaders` **command plugin** (product, verb `compile-shaders`, `writeToPackageDirectory`), which runs the tool with
  `--base <package directory>`. `Backends/SDL/scripts/compile-app-shaders.py` is **deleted** (one implementation, `BS-B`); its checked-in output is the parity oracle.
- `SDLGPUShaderLibrary(directory:)` accepts a directory with **a `SOURCE.sha256` or a `NAME.<vert|frag|comp>.json`**; new `init(directory:verifyingSources:)` (with a marker, a changed source, a source with no
  line and a line with no source are each a named error; without one nothing is compared; `BS-E`). Today's checked-in directories open exactly as before and the error still names `SOURCE.sha256`.
- Docs: `docs/packaging.md` 4a rewritten (tool, plugin, the pin and per-platform recipes, the library rules, what was verified); `docs/migration.md` row; the two guide prose lines, `Backends/SDL/README.md`
  and `SDLGPUTestSupport.swift`'s comment (`BS-J`); human checks group `BS`. No public Swift declaration in `Sources/` (census unmoved; the inventory and undocumented scripts print nothing).
  CLAUDE.md/AGENTS.md rule paragraph: the Record phase's (see section 6).

## 2 Pins and their mutations

Root `MetalUIShaderCompileTests` (15 tests; 13 run everywhere, 2 env-gated and counted while skipped): `sha256MatchesTheNISTVectors`, `aSourceNameYieldsItsStageAndStem`,
`theCommandPlanIsHlslToSpirvThenTheDerivations`, `formatsSkipsTheUnrequestedButAlwaysBuildsSpirv`, `theMarkerEqualsTheCheckedInOneByteForByte` (**the python script's own output, byte for byte**),
`sourcesWithoutAStageSuffixAreIgnoredAndNoneIsAnError`, `shadercrossIsFoundByFlagThenEnvironmentThenPath`, `aMissingShadercrossNamesAllThreePlaces`, `theLibraryDirectoryBesideBinJoinsTheLoaderPath`,
`aMissingSourceOrOutIsAUsageError`, `anUnknownFlagIsAUsageError`, `noMarkerIsParsed`, `theRunnerFollowsThePlanAndWritesTheMarker` (an injected runner; added beyond the spec), and the gated
`anEnvGatedRunCompilesAFixture` (`METALUI_SHADERCROSS`) and `theCompileShadersPluginRunsOnAFixturePackage` (`METALUI_RUN_SHADER_PLUGIN_TEST=1`, a **stub** shadercross, no real one needed).
`Backends/SDL` `SDLGPUShaderBuildProductTests` (5): `aBuildProductWithoutAMarkerIsAccepted`, `aDirectoryWithNeitherMarkerNorReflectionIsRefused`, `aStaleMarkerIsRefusedWhenSourcesAreGiven`,
`aMatchingMarkerIsAcceptedAndAbsentMarkerSkipsTheCheck`, `locateKeepsItsOrderForAMarkerFreeDirectory`. **Red on arrival** by compile failure (commits `088db5cd`: `cannot find 'SHA256' in
scope`, `'ShaderFormat'`, `'ShaderSource'`; `5a16d82d`: `extra argument 'verifyingSources' in call`). No new typecheck guard (no access-level narrowing; the declarations are `package`).

Mutations, **each alone against the committed tree, the filtered target** (`MetalUIShaderCompileTests`; for the SDL rows `SDLGPUShader*` in `Backends/SDL`, macOS), restored from the commit after each, `git status --short`
clean after the batch. **Deviation from the brief: not the full unfiltered suite per mutation**: the targets are pure Foundation and the machine was loaded (load average 70-140); the unmutated full suite is section 3.

| mutation (file) | reddened |
|---|---|
| 0a wrong rotation constant `rotr(e,6)`->7 (`SHA256`) | `sha256MatchesTheNISTVectors`, `theMarkerEqualsTheCheckedInOneByteForByte` |
| 0b no length bytes | the same two |
| 0c little-endian length | the same two |
| 1 `frag` suffix to `comp` (`ShaderStage`) | `aSourceNameYieldsItsStageAndStem`, `theCommandPlanIsHlslToSpirvThenTheDerivations`, `formatsSkipsTheUnrequestedButAlwaysBuildsSpirv`, `sourcesWithoutAStageSuffixAreIgnoredAndNoneIsAnError`, `theRunnerFollowsThePlanAndWritesTheMarker` |
| 2a swap `-s`/`-d` of the derivations | `theCommandPlanIsHlslToSpirvThenTheDerivations` |
| 2b derive from the HLSL instead of the `.spv` | `theCommandPlanIsHlslToSpirvThenTheDerivations` |
| 3 drop `spv` from the always set | `formatsSkipsTheUnrequestedButAlwaysBuildsSpirv` |
| 4a marker sorted descending | `theMarkerEqualsTheCheckedInOneByteForByte` |
| 4b one space separator | `theMarkerEqualsTheCheckedInOneByteForByte`, `theRunnerFollowsThePlanAndWritesTheMarker` |
| 4c CRLF | the same two |
| 4d Unicode-aware sort (`<` on `String`) | **green on the first fixture** (`e-acute` does not separate it); with U+212B against U+00C6 added: `theMarkerEqualsTheCheckedInOneByteForByte` (`BS-K` 3b) |
| 5 accept `x.hlsl` | `sourcesWithoutAStageSuffixAreIgnoredAndNoneIsAnError`, `theRunnerFollowsThePlanAndWritesTheMarker` |
| 6 the variable beats the flag | `shadercrossIsFoundByFlagThenEnvironmentThenPath` |
| 7 error omits the variable's name | `aMissingShadercrossNamesAllThreePlaces` |
| 8 append instead of prepend on the loader path | `theLibraryDirectoryBesideBinJoinsTheLoaderPath` |
| 9 ignore `--no-marker` | `noMarkerIsParsed`, `theRunnerFollowsThePlanAndWritesTheMarker` |
| R1 ignore a non-zero exit status | `theRunnerFollowsThePlanAndWritesTheMarker` |
| R2 always write the marker | `theRunnerFollowsThePlanAndWritesTheMarker` |
| R3 reverse the sources before the marker | **equivalent** (`contents(of:)` sorts); not a pin, no test reddens, by design |
| plugin verb renamed `compile-shaderz` (`Package.swift`, `METALUI_RUN_SHADER_PLUGIN_TEST=1`) | `theCompileShadersPluginRunsOnAFixturePackage` (6 issues: unknown plugin) |
| stage flag of the first command fixed to `vertex` (`ShaderPlan`, with a **real** shadercross) | `anEnvGatedRunCompilesAFixture`, `theCommandPlanIsHlslToSpirvThenTheDerivations` |
| 12 `guard hasMarker` (drop the reflection alternative) | `aBuildProductWithoutAMarkerIsAccepted`, `aMatchingMarkerIsAcceptedAndAbsentMarkerSkipsTheCheck`, `locateKeepsItsOrderForAMarkerFreeDirectory` |
| 13 accept any directory | `aDirectoryWithNeitherMarkerNorReflectionIsRefused`, `theShaderLibraryLooksBesideTheExecutableThenTheSourceTree`, `locateKeepsItsOrderForAMarkerFreeDirectory` |
| 14a no hash comparison | `aStaleMarkerIsRefusedWhenSourcesAreGiven` |
| 14b ignore a line with no source | `aStaleMarkerIsRefusedWhenSourcesAreGiven` |
| 14c ignore a source with no line | `aStaleMarkerIsRefusedWhenSourcesAreGiven` |
| 15 require a marker when sources are given | `aMatchingMarkerIsAcceptedAndAbsentMarkerSkipsTheCheck` |
| 16 swap the candidate order | `locateKeepsItsOrderForAMarkerFreeDirectory`, `theShaderLibraryLooksBesideTheExecutableThenTheSourceTree` |

## 3 Verification (2026-10-21, a locked screen, the machine shared with four other workflows)

- Root, after `swift package clean`, `swift build --build-system native --build-tests`: 0 `error:`, the only `warning:` SwiftPM's deprecation notice. Native unfiltered run: **4135 tests in 5 suites**
  (4120 + the 15 above), **exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else** (`turn { nsWindow.attachedSheet != nil }`; the locked screen), `FR-J no-argument frame:
  succeeded=true`. `swift build --build-tests` on the default build system: 0 `warning:`. Inventory and undocumented scripts print nothing (no public declaration in `Sources/`).
- `Backends/SDL` on macOS (`METALUI_REQUIRE_GPU=1`): 250 tests passed (245 + 5). In the Linux image (aarch64, `metalui-portable`, volume `metalui-sdl-build-build-shaders`): 247 tests passed (the
  GPU-less skips as before). Root portable tests in the image (`metalui-root-build-build-shaders`): the `MetalUIShaderCompileTests` 13 passed, the two gated skipped; the library, tool and plugin build on Linux.
  Windows is compiled by CI only (`MetalUIShaderCompile` imports only Foundation; `Process` through Foundation).
- **End to end, a real shadercross at the pin** (`BS-L`): macOS arm64 (full build with DXC 8 min 30 s) and **Linux aarch64** (native, clang, 6 min 45 s): `MetalUICompileShaders` over `Backends/SDL/Tests/AppShaders`
  wrote **41 files byte-identical to the checked-in `compiled` directory on both**, DXIL included; `anEnvGatedRunCompilesAFixture` passed on macOS.
- Plugin: `theCompileShadersPluginRunsOnAFixturePackage` (stub shadercross, fixture package depending on the checkout **by path**): refused without `--allow-writing-to-package-directory`, wrote blobs and marker with it.
- The fourteen offscreen images against `11dca65e`: see section 4.

## 4 Pixels

PIXELS_PLACEHOLDER

## 5 Deferred (named)

- A build-tool plugin on `swift build` (`BS-D`); a CI job building the pin (`BS-G`, measured 8.5 min uncached on a Mac, 6.75 min on aarch64 Linux: still no); a published prebuilt shadercross, binaryTarget, release, tag or image (`BS-H`, **the user's decision, to be asked**);
  a bundle-resource candidate in `locate`. A dependency **by URL** reaching the plugin (human check BS3; by path measured). Linux x86_64 and Windows builds (BS1, BS4); an aarch64 Linux GPU app (BS2).
- A decision for the user: pin a prebuilt per platform (the builds above are 7-9 minutes, so a release asset is convenience, not necessity).

## 6 Rule owed to CLAUDE.md (the Record phase's, one paragraph, class `M`)

**Build-time app shaders (`BS-`, record §138).** `MetalUICompileShaders` / `swift package compile-shaders` (`MetalUIShaderCompile`, portable, outside the `SDL` trait) replaces `compile-app-shaders.py`; shadercross by
`--shadercross`, `METALUI_SHADERCROSS`, `PATH`; `SDLGPUShaderLibrary` accepts a marker-free build product and `init(directory:verifyingSources:)` checks a marker when present; the pin is documented, nothing is published.
