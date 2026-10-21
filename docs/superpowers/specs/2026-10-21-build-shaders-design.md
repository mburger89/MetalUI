# Build-time app shaders (S12, XP-G20) — design

Rulings: [`../2026-10-21-build-shaders-decisions.md`](../2026-10-21-build-shaders-decisions.md) (`BS-A`…`BS-H`).
Branch `feat/build-shaders` from `11dca65e`. Class M, no divergence (675–684 untouched), **nothing published** (`BS-H`).
No SwiftUI claim, so no probe; plugin behaviour was measured (decisions, `BS-B`).

## 1. Gap

An app's HLSL is compiled by hand (`compile-app-shaders.py`, packaging §4a, `GA-F`) and the blobs are checked in;
`swift build` compiles nothing, and MetalCreator wants none in its repo. We give it a command it can run (and wire into its
own build) with one portable implementation, a documented shadercross pin, and a library that accepts the result.

## 2. Public surface (all class M)

- **Tool** `MetalUICompileShaders` (executable product, root package, outside the `SDL` trait):
  `MetalUICompileShaders --source DIR --out DIR [--shadercross PATH] [--formats spv,msl,dxil,json] [--no-marker]`.
  Same inputs and outputs as the python script (`NAME.{vert,frag,comp}.hlsl` to `NAME.<stage>.{spv,msl,dxil,json}` and
  `SOURCE.sha256`); exit non-zero with a message on any failure.
- **Plugin** `CompileShaders` (command plugin product, verb `compile-shaders`, permission `writeToPackageDirectory`):
  `swift package --allow-writing-to-package-directory compile-shaders --source shaders --out shaders/compiled`; forwards
  the tool's arguments, runs the tool found by `context.tool(named:)`.
- **Library** `SDLGPUShaderLibrary`: `init(directory:)` accepts a marker-free build product (`BS-E`); new
  `init(directory:verifyingSources:)`; new `SDLGPUShaderError` text only. Doc comments on every member.
- Docs: `docs/packaging.md` §4a rewritten (tool, plugin, `METALUI_SHADERCROSS`, the pin and per-platform build recipes,
  the aarch64 DXIL limit, the two Windows rules kept); `docs/migration.md` row (the script is gone: the same flags now go to
  `MetalUICompileShaders`); `Backends/SDL/README.md` and `Experiments/SDLGPU/README.md` references updated.

## 3. Files (one lane)

Disjoint from siblings (retained, layout, gestures): new `Backends/SDL/Sources/MetalUIShaderCompile/` (library:
`ShaderStage`, `ShaderCompilePlan`, `ShadercrossLocator`, `SourceMarker`, `CompileArguments`, `ShaderCompiler.run`),
`Backends/SDL/Sources/MetalUICompileShaders/main.swift`, `Plugins/CompileShaders/Plugin.swift`, root `Package.swift` (two
targets in the portable list, two products, one plugin target and product, one test target), `Tests/MetalUIShaderCompileTests/`,
`Backends/SDL/Sources/MetalUISDLGPU/SDLGPUShaderLibrary.swift`, `Backends/SDL/Tests/MetalUISDLTests/SDLGPUShaderLibraryTests.swift`,
`Backends/SDL/scripts/compile-app-shaders.py` (deleted), docs above, `docs/probes/closeout-public-api.sh` census re-record if the
tooling counts it, the record `docs/record/138-build-shaders.md`, human checks group `BS`. **Lanes: 1.**
`MetalUIShaderCompile` imports only Foundation (`PC-A`: a portable target, declared on every platform); the Linux/Windows CI
builds it, so no Apple import and `Process` only through Foundation.

## 4. Behaviour of the port (pinned against the script)

Per source: `shadercross SRC -s HLSL -d SPIRV -t <stage> -o NAME.spv`, then for each of MSL, DXIL, JSON
`shadercross NAME.spv -s SPIRV -d <FMT> -t <stage> -o NAME.<ext>` (`--formats` skips the unrequested; `spv` is always built, it
is the intermediate). Stage from the suffix (`vert`→vertex, `frag`→fragment, `comp`→compute); other `*.hlsl` ignored; no
source is an error. Marker: one `<sha256>  <file>` line per source, sorted by name, LF. Lookup and loader-path per `BS-C`.

## 5. Tests (each with its red-before and the mutation that must redden it)

Root target `MetalUIShaderCompileTests` (portable, Foundation only; the lane names the reddened tests):
1. `aSourceNameYieldsItsStageAndStem` — red before: no type. Mutation: map `frag` to `compute`.
2. `theCommandPlanIsHlslToSpirvThenTheDerivations` — exact argument vectors for one vertex and one compute source, order SPIR-V,
   MSL, DXIL, JSON. Mutation: swap `-s`/`-d` of the derivations; derive from HLSL instead of the `.spv`.
3. `formatsSkipsTheUnrequestedButAlwaysBuildsSpirv` — Mutation: drop `spv` from the always set.
4. `theMarkerEqualsTheCheckedInOneByteForByte` — computes the marker over `Backends/SDL/Tests/AppShaders/*.hlsl` and
   compares with `…/compiled/SOURCE.sha256` (the python script's output), by `#filePath`. Mutation: sort descending; one space
   separator; CRLF.
5. `sourcesWithoutAStageSuffixAreIgnoredAndNoneIsAnError` — Mutation: accept `x.hlsl`.
6. `shadercrossIsFoundByFlagThenEnvironmentThenPath` — injected environment and file-exists closure. Mutation: swap two.
7. `aMissingShadercrossNamesAllThreePlaces` — Mutation: omit the variable's name.
8. `theLibraryDirectoryBesideBinJoinsTheLoaderPath` — pure function of the executable path, per-OS variable names. Mutation:
   append instead of prepend.
9. `arguments` — `aMissingSourceOrOutIsAUsageError`, `anUnknownFlagIsAUsageError`, `noMarkerIsParsed`. Mutation: ignore `--no-marker`.
10. `anEnvGatedRunCompilesAFixture` (gated `METALUI_SHADERCROSS=/path`; skipped otherwise, counted) — copies `tri.vert/frag.hlsl`
    to a temp directory, runs `ShaderCompiler.run`, expects `.spv` magic `0x07230203`, a JSON whose counts equal the checked-in
    one's, the marker. Red before: no runner. Mutation: stage flag wrong.
11. `theCompileShadersPluginRunsOnAFixturePackage` (gated `METALUI_RUN_SHADER_PLUGIN_TEST=1`, like the scaffold build test,
    **and** `METALUI_SHADERCROSS`): a temp package depending on the checkout by path runs
    `swift package --allow-writing-to-package-directory compile-shaders` and finds the blobs; a variant without the permission
    flag expects the refusal. Also records whether a dependent can reach the dependency's plugin (`BS-B`). Mutation: rename the verb.
    **This is also the always-checked "plugin compiles" proof**: the lane runs it once with a stub `shadercross` script (a shell
    or batch file that writes the output argument), which needs no real shadercross; the gate stays only for the real binary.

`Backends/SDL` `SDLGPUShaderLibraryTests` additions (portable, GPU-free):
12. `aBuildProductWithoutAMarkerIsAccepted` — blobs of `vulkan` and `metal` only (no `.dxil`), JSONs, no `SOURCE.sha256`:
    opens, `compute(_, driver: "vulkan")` and `"metal"` answer, `"direct3d12"` is a named error. Red before: refused. Mutation:
    drop the reflection-file alternative.
13. `aDirectoryWithNeitherMarkerNorReflectionIsRefused` — error names `SOURCE.sha256`. Mutation: accept any existing directory.
14. `aStaleMarkerIsRefusedWhenSourcesAreGiven` — one edited source, one extra source, one extra line; each a distinct named error.
    Mutation: compare only the count of lines.
15. `aMatchingMarkerIsAcceptedAndAbsentMarkerSkipsTheCheck` — Mutation: require a marker when sources are given.
16. `locateKeepsItsOrderForAMarkerFreeDirectory` — extends `theShaderLibraryLooksBesideTheExecutableThenTheSourceTree`. Mutation: swap.
Existing C5/C6/`aCheckedInAppShaderBlobMatchesItsSource` stay unedited and green: today's behaviour is value-identical.
No new typecheck guard (no access-level narrowing); the plugin and tool are not public Swift declarations.

## 6. Verification the lane owes

Root native suite unfiltered after `swift package clean` (count: 4120 plus the new root tests, the Backends/SDL ones separate),
`FR-J` line, 0 `warning:` on both build systems, inventory and undocumented scripts, `Backends/SDL` tests on macOS
(`METALUI_REQUIRE_GPU=1`) and in the Linux image (`metalui-portable`, volume `metalui-sdl-build-build-shaders`), the root
portable library built in `swift:6.4-noble`, the fourteen images 0 px (nothing in rendering moves). End to end: try building the
pin on macOS (cmake, SDL3 via Homebrew, DXC and SPIRV-Cross as submodules) and in the Linux image, time it, run test 10 and
the plugin test for real; if a build does not fit in ~20 minutes, rule the run owed and add check BS1.

## 7. Demo expectation

None: no demo section, no pixel moves.

## 8. Human checks added (group `BS`, not run)

- **BS1.** On a machine with the pinned shadercross (macOS arm64, Linux x86_64, Windows x64), `swift package
  --allow-writing-to-package-directory compile-shaders` over `Backends/SDL/Tests/AppShaders` writes blobs that open in the
  SDL GPU tests (GPU on the machine).
- **BS2.** Linux aarch64: the SPIR-V/MSL-only route compiles and a Vulkan app runs; the emulated amd64 route, if used.
- **BS3.** A package depending on MetalUI **by URL** reaches the plugin (or the tool, the documented fallback) from its own root.
- **BS4.** Windows: `shadercross.exe` found on `PATH` and by `METALUI_SHADERCROSS`; its DLLs beside it load.

## 9. Deferred (named, with reason and owner)

- Build-tool plugin running on `swift build` (`BS-D`): outputs reach a resource bundle, not beside the executable, and a missing
  shadercross would fail every consumer build. Owner: after the publishing decision.
- CI job building the pin (`BS-G`) unless the lane measures it cheap. Owner: the same decision.
- A published prebuilt shadercross / binaryTarget, release, tag or image (`BS-H`): the user's decision, to be asked.
- Bundle-resource candidate in `locate` (follows `BS-D`).
