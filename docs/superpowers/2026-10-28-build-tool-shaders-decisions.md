# App shaders on `swift build` (BS-D) - decisions

Rulings for item `BS-D` (carried by record 138, "go ahead with BS-D" 2026-10-28; **not a plan task**), the build-tool plugin MetalCreator asked for as
part of XP-G20. Prefix `BT-`. **Next unused: `BT-V`.**
Spec: [`specs/2026-10-28-build-tool-shaders-design.md`](specs/2026-10-28-build-tool-shaders-design.md). Record: `../record/161-build-tool-shaders.md` (Record phase).
Branch `feat/build-tool-shaders` from master `abc2bf46`. Continues `BS-B`, `BS-C`, `BS-E`, `BS-I` (record 138); **supersedes `BS-D`** (amended there).
Divergence labels reserved 895-904: **none taken** (`BT-A`). **Nothing is published** (`BS-H`; the user chose "no publish": no release, tag,
`binaryTarget` URL or image).

Sources of truth. SwiftUI has no shader build step: no SwiftUI claim, no probe. gpui compiles its shaders in a `build.rs` (context only, as `BS-`).
Every plugin fact below was **measured on 2026-10-28** (`BT-B`) with SwiftPM 6.4.2 (Apple Swift 6.4.2) on macOS 27.2 arm64 and in the
`metalui-portable` image (Ubuntu 24.04 aarch64, OrbStack); Windows is **unmeasured** throughout.

## BT-A - class M, no divergence, no census row

**Ruling.** A second plugin product of the root package, MetalUI-only (class `M`). A plugin is not a `public` Swift declaration, the tool's library
`MetalUIShaderCompile` is `package` (`BS-K` 3a), and `MetalUISDLGPU` lives in `Backends/SDL`, outside the census (`GA-L`), so neither
`closeout-public-api.sh` nor the inventory map moves. The one new public declaration (`BT-H`) owes a doc comment, as every `MetalUISDLGPU` member has.
**Cost if wrong.** A map row.

## BT-B - what was measured (2026-10-28)

A throwaway pair of packages under the session scratchpad (`bsd/provider`: a build-tool plugin `ProbeShaders` whose tools are the worktree's
`MetalUICompileShaders` product and a probe `EnvDump`; `bsd/app`: an executable target applying it, depending on `provider` by path, which depends on
the worktree by path, so the plugin lives in a **dependency**, as it will for an app). Each fact names the build systems it was measured under:
`native` is `--build-system native`, `swiftbuild` the default.

1. **The build command sees the build's environment** (`EnvDump` wrote `PATH` and a caller-set `METALUI_SHADERCROSS`; macOS both systems, Linux both).
   The plugin process sees it at plan time too (a `Diagnostics.warning` printed both values; `BS-B` 2 agrees).
2. **The plugin is re-planned on every build, and a changed command line reruns the command**: changing only `METALUI_SHADERCROSS` (passed as an
   argument) reran the compile, adding a `.hlsl` produced a three-source command, both systems on macOS.
3. **Incremental:** an unchanged build skips the command (macOS both; Linux `swiftbuild`; Linux `native` reran it **once** on the second build and
   skipped from the third on, four builds measured); editing an `.hlsl` or a checked-in blob listed as an input reruns it (macOS both).
4. **The macOS sandbox is no obstacle for this tool, with no `--disable-sandbox`**: the build command's write under `$HOME` is denied
   (`NSCocoaErrorDomain 513`, "Operation not permitted"; Linux has no sandbox, the same write succeeded), but reading the target's sources, reading
   and executing a shadercross **outside the package** at an absolute path and loading its libraries all work. The installed `bin/shadercross` has
   no `LC_RPATH` and fails bare (`dyld: Library not loaded: @rpath/libSDL3_shadercross.0.dylib`); under the sandbox it ran because the tool puts
   `../lib` on `DYLD_LIBRARY_PATH` (`BS-C`), which the sandbox passes through. **With the real shadercross at the pin** (`BT-C`), found by
   `METALUI_SHADERCROSS` (native and swiftbuild) and by `PATH` alone (native), the build wrote `tri.vert`/`tri.frag` `.spv`, `.msl`, `.dxil`
   (DXC's `libdxil` loaded) and `.json` **byte-identical** to `Backends/SDL/Tests/AppShaders/compiled`, and the marker's two lines equal.
5. **Outputs become resources of the target and `Bundle.module` is generated** with no `resources:` rule. Every declared output is a resource
   (the probe's `env.txt` landed in the bundle too), so **only shader outputs may be declared**. Layouts: macOS native a flat
   `app_App.bundle/`; macOS swiftbuild `app_App.bundle/Contents/Resources/`; Linux native `app_App.resources/`; Linux swiftbuild
   `app_App.bundle/` (with an `Info.plist`). Per-file outputs are flattened into that root.
6. **A directory declared as the one output works on all four** (macOS and Linux, native and swiftbuild): the bundle holds
   `MetalUIAppShaders/` with every file the tool wrote, and `Bundle.module.url(forResource: "MetalUIAppShaders", withExtension: nil)` answered the
   directory in all four layouts. The copy **mirrors** the directory: a file removed from the tool's output left the bundle on the next run
   (native, macOS); a file the tool did not remove stayed (measured: a deleted source's blobs survived until the output directory was cleared).
7. **Errors.** A tool exiting non-zero after writing `error: ...` to stderr fails `swift build` (exit 1) and the line is shown verbatim (native: the
   line and the command; swiftbuild: the line, then `CustomTask ... failed with a nonzero exit code` and `Build failed`). A plan-time
   `Diagnostics.error` also fails the build (exit 1; native printed it twice).
8. **Unhandled files.** `.hlsl` files and checked-in blobs inside the target directory that are listed as a command's `inputFiles` raise no "found N
   file(s) which are unhandled" warning, so no `exclude:` is needed; a blob not listed as an input raised it (both systems).
   `SourceModuleTarget.sourceFiles(withSuffix: "hlsl")` lists them (type `unknown`).

**Cost if wrong.** A measurement; Windows facts are human check `BT1`.

## BT-C - shadercross at the pin, rebuilt for the measurement

**Measured.** `docs/packaging.md` 4a's recipe verbatim at `1ff05bec573988a98ef9e0260b4da44f512b8367` (Homebrew SDL3 3.4.18, cmake 4.4.4, ninja 1.13.2):
configure 24.8 s, **`cmake --build build -j8` 8 min 29 s** (21:04:05 to 21:12:34, load average about 50-65 from other sessions), install into
`bsd/install`: `bin/shadercross` and a 32 MB `lib` (`libdxcompiler`, `libdxil`, `libspirv-cross-c-shared`, `libSDL3_shadercross`). Kept for the
implementation lane; nothing published. **Cost if wrong.** None.

## BT-D - one build-tool plugin, `CompileShadersOnBuild`, beside the command plugin

**Ruling.** The root package gains `.plugin(name: "CompileShadersOnBuild", capability: .buildTool(), dependencies: ["MetalUICompileShaders"],
path: "Plugins/CompileShadersOnBuild")` and the product `.plugin(name: "CompileShadersOnBuild", targets: ["CompileShadersOnBuild"])`, beside the
unchanged `CompileShaders` command plugin and tool. An app opts in per target:
`plugins: [.plugin(name: "CompileShadersOnBuild", package: "MetalUI")]`. Both plugins run the **one** tool (`BS-B` a), so there is still one
implementation of the plan, the lookup and the marker. The plugin is declared on every platform (it imports only `PackagePlugin` and Foundation,
as `CompileShaders` already does on Linux and Windows CI). **Cost if wrong.** A product rename.

## BT-E - the sources are the target's `Shaders/` directory; checked-in blobs are `Shaders/compiled/`

**Ruling.** The plugin reads `<target directory>/Shaders/NAME.<vert|frag|comp>.hlsl` (the `BS-B` source rule, `ShaderSource`) and, optionally,
checked-in blobs in `<target directory>/Shaders/compiled/` (what `swift package --allow-writing-to-package-directory compile-shaders --source
Sources/<T>/Shaders --out Sources/<T>/Shaders/compiled` writes). It lists **every** `.hlsl` there and every file in `compiled/` as `inputFiles`
(`BT-B` 3 and 8: an edit reruns, and nothing is "unhandled", so no `exclude:`). A target that applies the plugin and has no `Shaders/` directory or
no source gets **no command** and one plan-time `Diagnostics.warning` naming the directory it looked for: the build succeeds (a misapplied plugin is
not worth failing a build; a consumer that does not apply the plugin is untouched, as is every build of this repository). A source directory
named by the app is not offered (a build-tool plugin takes no arguments). **Cost if wrong.** A directory name in docs and one constant.

## BT-F - the tool decides at build time: compile when shadercross is found, else verify and copy, else fail naming both fixes

**Ruling.** The plugin runs `MetalUICompileShaders --on-build --source <Shaders> --checked-in <Shaders/compiled> --out <work>/MetalUIAppShaders
--environment-shadercross <value of METALUI_SHADERCROSS or ""> --environment-path <value of PATH or ""> --display-source <Shaders relative to the package>` (paths absolute; the last only feeds the
messages, so a fix names a path the user can paste). The two
`--environment-*` arguments carry the plugin's view of the environment **on the command line**, so a change of either reruns the command
(`BT-B` 2); the tool feeds them to the **one** `ShadercrossLocator.locate(flag: nil, environment:)` (`BS-C`; the plugin does no lookup of its own).
On Windows the plugin reads `PATH` case-insensitively (the variable is spelled `Path` there; unmeasured, `BT1`). The decision is a pure function in
`MetalUIShaderCompile` over the locator's answer, the source bytes and the checked-in names and marker:

1. **shadercross found** -> clear the output directory, compile every source to `spv`, `msl`, `dxil`, `json` and write `SOURCE.sha256` (the
   existing `ShaderCompiler.run`). The checked-in blobs are not read for the output; if a marker exists and is stale, print one
   `warning: Sources/<T>/Shaders/compiled is stale (<problems>); this build compiled fresh blobs, run compile-shaders to refresh the checked-in
   copy` line (a colleague without shadercross would fail, case 3).
2. **a variable naming a missing file** -> fail (`BS-C`: never a fall-through), the locator's message.
3. **not found, `compiled/SOURCE.sha256` present and `SourceMarker.problems` empty, and every source has its `.json` and `.spv`** -> clear the output
   directory and copy `SOURCE.sha256` plus, per source, each of `<stem>.spv/.msl/.dxil/.json` that exists (other files in `compiled/` are not
   copied); print `Verified N checked-in shader(s) against SOURCE.sha256 (no shadercross): <out>`.
4. **not found, otherwise** (a stale marker, a missing marker, no `compiled/`, a source missing its `.json` or `.spv`) -> fail, exit 1, with
   `error:` lines naming each problem and **both fixes and the pin**:
   ```text
   error: the app shaders in Sources/App/Shaders changed since Shaders/compiled/SOURCE.sha256 was written: tri.frag.hlsl changed since SOURCE.sha256 was written
   error: no shadercross was found (METALUI_SHADERCROSS is unset and none is on PATH), so the build cannot compile them and will not use stale blobs. Either:
   error:   1. install SDL_shadercross at 1ff05bec573988a98ef9e0260b4da44f512b8367 (docs/packaging.md 4a) and set METALUI_SHADERCROSS or put it on PATH, or
   error:   2. where shadercross is installed, run: swift package --allow-writing-to-package-directory compile-shaders --source Sources/App/Shaders --out Sources/App/Shaders/compiled
   error:      and commit Shaders/compiled. A CRLF checkout changes the hashes: mark *.hlsl eol=lf (docs/packaging.md 4a).
   ```
   The pin is one constant, `ShadercrossPin.commit`, pinned to `docs/packaging.md` by a test (`BT-L` 9).

**Why at build time, not plan time.** The plugin cannot import `MetalUIShaderCompile` (a plugin depends only on tools), so a plan-time decision
would duplicate the locator and the marker; the tool already has both. **Why no silent fallback.** `BS-D`'s second reason: a build that quietly used
stale blobs would hide a stale shader. The marker makes the fallback safe exactly when it is not stale; a missing marker is not "probably fine".
**Known limit.** A shadercross binary replaced **at the same path** does not rerun the command (it is not an input; the plugin does not know which
file the locator will pick); `swift package clean` or touching a source does. **Cost if wrong.** A flag spelling; a message wording.

## BT-G - the output is one directory, `MetalUIAppShaders`, a resource of the target

**Ruling.** The command declares the single output `<pluginWorkDirectory>/MetalUIAppShaders` (`BT-B` 6: measured on all four combinations) rather
than per-file outputs, so the bundle keeps the name `GA-F` already uses beside the executable, the shader files never share a flat bundle root with
the app's other resources, and the plugin need not predict file names. The tool **clears that directory first** in both arms, because the bundle
copy mirrors it and a deleted source's blobs would otherwise ship (`BT-B` 6). **Cost if wrong.** Switching to per-file outputs (the plugin knows
the stems), a plugin-only change.

## BT-H - the runtime finds it through the app's bundle, after the directory beside the executable

**Ruling.** `MetalUISDLGPU` cannot name the app's `Bundle.module`, so the app passes it: a new overload
`SDLGPUShaderLibrary.locate(directoryName: String = "MetalUIAppShaders", resourceBundle: @autoclosure () -> Bundle?, sourceTree: URL? = nil)`
(the existing `locate(directoryName:sourceTree:)` is unchanged; a required label keeps `locate()` unambiguous). Order:

1. `directoryName` **beside the executable** (`GA-F`, unchanged first): a shipped app copies the directory there (packaging 4a), and an explicit
   placement must win over whatever bundle the build left.
2. the bundle's `url(forResource: directoryName, withExtension: nil)` (`BT-B` 6: answered in all four layouts), else its `resourceURL` joined with
   the name.
3. `sourceTree`.

The bundle is an **autoclosure evaluated only when candidate 1 fails**, because SwiftPM's generated `Bundle.module` accessor **traps** when its
bundle is missing (a shipped app without the bundle but with the directory beside it must not reach it). The usual call is
`SDLGPUShaderLibrary.locate(resourceBundle: .module)`. The error still names every directory tried. **Cost if wrong.** An overload.

## BT-I - the scaffold's starter does not opt in; Jotter is untouched

**Ruling.** `metalui new --cross-platform` generates no shaders and no `MetalUISDLGPU` use, so applying the plugin there would only print `BT-E`'s
warning on every build. The generated manifest is **unchanged** (no `SC-` text moves, `METALUI_RUN_SCAFFOLD_BUILD_TEST` is not owed by this
item); `docs/packaging.md` 4a and `docs/getting-started.md` show the one-line opt-in. `Examples/Jotter` has no shaders (grep) and is not touched.
**Cost if wrong.** A starter line and the scaffold build test.

## BT-J - Linux and Windows

**Ruling.** Linux behaves as macOS minus the sandbox (`BT-B`); the plugin, the tool and the decision are portable Foundation code. Windows is
**unmeasured**: the PATH spelling (`BT-F`), `shadercross.exe` lookup (`BS-C`, already in the locator), DLLs beside the executable, the
`.resources` layout, and CRLF (the error names the `eol=lf` rule). Windows CI builds the root, which compiles every plugin target (`BT-B`: native
compiled the root's `CompileShaders` plugin inside the consumer's build), so the plugin target must build there; no root target applies it, so no
build of this repository runs it. Human check `BT1` (a Windows consumer build, both arms). **Cost if wrong.** A Windows fix found by the check.

## BT-K - what stays carried

A shadercross fetched or built by the plugin (needs a publish decision, `BS-H`), a CI job that builds shadercross (`BS-G` stands), per-app
`--formats` on build (a build-tool plugin takes no arguments; all four are built, a pin build always has DXC), rerunning when the shadercross binary
changes in place (`BT-F` limit), Windows (`BT-J`).

## BT-L - tests, each named with the mutation it is for

Always-run, `Tests/MetalUIShaderCompileTests/BuildPluginDecisionTests.swift` (pure decision, injected locator answer and file lists):

1. `withShadercrossTheBuildCompilesAndIgnoresTheCheckedInBlobs` - mutation: prefer the copy arm when the marker matches.
2. `withoutShadercrossAMatchingMarkerCopiesExactlyTheBlobsOfEachSource` - mutations: copy every file of `compiled/`; omit the marker.
3. `withoutShadercrossAChangedSourceFailsNamingBothFixesAndThePin` - mutations: ignore `SourceMarker.problems`; drop the pin or either fix from the text.
4. `withoutShadercrossAMissingMarkerOrDirectoryFails` - mutation: treat a missing marker as matching.
5. `aSourceWithoutItsReflectionOrSpirvBlobFails` - mutation: drop the completeness check.
6. `aVariableNamingAMissingShadercrossFailsAndNeverCopies` - mutation: map a locator error to "not found".
7. `onBuildArgumentsAreParsedAndAnEmptyVariableIsUnset` - mutations: `--environment-shadercross ""` treated as a path; `--checked-in` dropped.
8. `theOnBuildRunClearsItsOutputDirectoryInBothArms` - mutation: no clear (a stale file survives), per arm.
9. `theErrorsPinIsThePackagingDocsPin` - reads `docs/packaging.md`; mutation: change `ShadercrossPin.commit`.
10. `aStaleCheckedInCopyIsWarnedWhenShadercrossCompiles` - mutation: no warning line.

`Backends/SDL` (`SDLGPUShaderLibraryTests`, SDL trait, macOS and the Linux image):

11. `theShaderLibraryLooksBesideTheExecutableThenTheBundleThenTheSourceTree` - mutation: swap candidates 1 and 2.
12. `theResourceBundleIsNotEvaluatedWhenTheExecutableCandidateOpens` - mutation: evaluate the autoclosure eagerly.

Env-gated, `METALUI_RUN_BUILD_PLUGIN_TEST=1` (counts while skipped, as `METALUI_RUN_SHADER_PLUGIN_TEST`), in `ShaderCompileTests.swift`:

13. `theBuildToolPluginCompilesVerifiesAndRefusesOnAFixturePackage` - a temporary package depending on this checkout by path, one target applying the
    plugin, `Shaders/tri.vert.hlsl` plus a checked-in `compiled/`; arms, each on `swift build` and `swift build --build-system native`: (a) stub
    shadercross by `METALUI_SHADERCROSS` -> success, the bundle's `MetalUIAppShaders` holds the stub's files; (b) no shadercross (variable unset,
    `PATH` without one) and a matching marker -> success, the bundle's files byte-equal the checked-in ones; (c) the `.hlsl` edited -> exit non-zero,
    output names `1ff05bec...`, `compile-shaders` and `METALUI_SHADERCROSS`; (d) an unchanged rebuild prints neither `Compiled` nor `Verified`
    (native on Linux exempt for one build, `BT-B` 3); (e) with `METALUI_SHADERCROSS` naming a real shadercross, the blobs equal
    `Backends/SDL/Tests/AppShaders/compiled`. Mutations: the plugin passes no `--environment-shadercross` (arm a reddens); the plugin declares
    per-file outputs (the `MetalUIAppShaders` lookup reddens).

**Cost if wrong.** A test rename.

## BT-M - rejected shapes

A plan-time decision in the plugin (duplicates the locator and the marker, `BT-F`); a silent fallback to unverified blobs (`BS-D`'s reason 2); a
`binaryTarget` shadercross (`BS-H`, user decision); per-file outputs (`BT-G`); making the starter opt in (`BT-I`); `--disable-sandbox` (not needed,
`BT-B` 4); copying the outputs beside the executable (a build-tool plugin cannot write there, `BS-B` 3, and `BT-H` reaches the bundle instead).

## BT-N - implementation notes (build)

**Ruling.** (1) `ShadercrossLocator.notFoundMessage` is the one prefix the build arm uses to tell "nothing found" from a named missing file (`BT-F` 2). (2) `runOnBuild` takes injected `fileExists`, `runner`, `log` and `warn`, so the pure tests run both arms with no shadercross. (3) The env-gated test's fixture manifest declares `platforms: [.macOS(.v14)]`: the plugin product inherits the root's macOS 14 and SwiftPM refuses a lower consumer, as for every product of this package. (4) The plugin lists `compiled/` regular files by `FileManager`, as it lists the sources. Measured 2026-10-28, macOS, both build systems, with a stub and the real shadercross at the pin (the designer's install), with and without `METALUI_SHADERCROSS` set in the test's own environment.
**Cost if wrong.** None.

## BT-O - include sources are inputs (item XP-G32)

**Ruling.** MetalCreator's viewport shaders `NAME.vert.hlsl`/`NAME.frag.hlsl` all `#include "common.hlsli"` from `Shaders/`. Every regular file below
`<target>/Shaders/`, **except the top-level `compiled/` subtree**, whose name ends `.hlsli`, or ends `.hlsl` and is not a top-level `NAME.<vert|frag|comp>.hlsl`,
is an *include source*: the plugin adds it to the command's `inputFiles` (sorted bytewise, relative `/` paths, so editing a header reruns the command; the
plan-time list is the only trigger, since `inputFiles` is how SwiftPM decides). **Detail the ruling left open:** a stage-named file **below** the top level
(`lib/x.vert.hlsl`) is never compiled (the tool lists the top level only), so it is an include source; a symlink to a regular file counts, a symlink to a directory is
not entered (no cycle) and a broken link, a directory named `x.hlsli` and a `compiled/` below the top are handled (the first two skipped, the last entered). The one
selection is `IncludeSelection` in `MetalUIShaderCompile/IncludeSources.swift`; the plugin cannot import a package target, so **the marked region
`// BEGIN include-selection ... // END include-selection` is copied byte for byte into `Plugin.swift`** (internal access, because a plugin has no package name) and
`theBuildPluginSelectsIncludeSourcesExactlyAsTheToolDoes` fails on any difference and on `inputFiles` losing its include list. A pure walk test (`theWalkListsIncludeSourcesRecursivelyAndSorted`) pins the filter.
**Cost if wrong.** A header placed under `compiled/` is not an input (documented).

## BT-P - `INCLUDES.sha256`

**Ruling.** A sibling of `SOURCE.sha256`, **the same format and the same `SourceMarker` code** (`contents(of:)` over relative paths, bytewise sort, LF;
`SourceMarker.problems` gained `markerName` and `noun` parameters that only spell its messages, defaults unchanged). Written by the one tool, in both the
`--on-build` compile arm and the command plugin's `ShaderCompiler.run`, **only when include sources exist**; with none, nothing is written and a stale one in `--out`
is removed, so a package without headers produces exactly the files it produced before (measured: `MetalUICompileShaders` over `Backends/SDL/Tests/AppShaders` with the
real shadercross at the pin wrote 41 files, `diff -r` identical to the checked-in `compiled/`, and `anEnvGatedRunCompilesAFixture` asserts the `.spv` bytes and no `INCLUDES.sha256`).
`SOURCE.sha256` keeps meaning stage sources only.
**Cost if wrong.** None.

## BT-Q - the copy path

**Ruling.** Without shadercross `BuildDecision.decide` (new defaulted parameters `includes`, `includesMarker`) requires `SOURCE.sha256` to match **and**, when include
sources exist, `INCLUDES.sha256` present and matching; a missing marker (`compiled/INCLUDES.sha256 does not exist`), a changed header (`common.hlsli changed since
INCLUDES.sha256 was written`), a header with no line and a line with no header (`INCLUDES.sha256 lists X, which is not among the include sources`) are each named in the
failure text, with the pin and both fixes as before. `INCLUDES.sha256` joins the copied files. **An `INCLUDES.sha256` checked in while no include sources exist is a named
orphan problem.** With shadercross the same problems are only the stale-checked-in warning, and a missing include marker is silent as a missing `SOURCE.sha256` is.
**Cost if wrong.** A checked-in directory made before its sources gained headers must be regenerated (the failure text says how).

## BT-R - run time

**Ruling.** `SDLGPUShaderLibrary` never listed `compiled/`'s entries, so a directory holding `INCLUDES.sha256` already opened and nothing treats it as unknown (pinned
by `anIncludesMarkerIsAcceptedAndCheckedAgainstTheHeaders`). `init(directory:verifyingSources:)` now **also** checks an `INCLUDES.sha256` it finds against the include
sources below `sources` (about ten lines over the same `IncludeSources.read`): a header-only edit, a new header and a vanished one are named errors; the check runs
whether or not a `SOURCE.sha256` is present. **Chosen limit:** a directory with a `SOURCE.sha256` but **no** `INCLUDES.sha256` compares no headers (as a missing
marker compares nothing, `BS-E`); making it strict would break a caller whose sources directory holds unrelated non-stage `.hlsl` files. **Cost if wrong.** One more
`verifyingSources` refusal for a stale marker.

## BT-S - include resolution: measured, **BT-S's premise refuted**

**Measured 2026-10-30**, shadercross built at the pin `1ff05bec...` (the recipe of `docs/packaging.md` 4a, macOS arm64, install under the gitignored
`.scratch-shadercross/install`; `DYLD_LIBRARY_PATH` its `lib`, as the tool sets it). `shadercross --help` at the pin lists `-I | --include <value>  HLSL include directory.
Only used with HLSL source.` and `-D<name>[=<value>]`. A source `t.frag.hlsl` with `#include "common.hlsli"` and `#include "sub/inner.hlsli"` beside it:

| Invocation | Result |
|---|---|
| absolute source path, cwd `/` | **fails**: `hlsl.hlsl:1:10: fatal error: 'common.hlsli' file not found`, exit 1, a 0-byte `.spv` left behind |
| relative source path, cwd the source directory | compiles (352 bytes SPIR-V) |
| absolute source path, cwd `/`, `-I <source dir>` | compiles, the nested `sub/inner.hlsli` found too |
| the same with a trailing slash on `-I` | compiles |

So shadercross does **not** resolve an include relative to the source file; it resolves against `-I` directories and, incidentally, its working directory. The tool passes the
source as an absolute path and does not set the child's working directory, so **`ShaderCompilePlan.commands` now passes `-I <sourceDirectory>` on the HLSL to SPIR-V
step** (not on the derivations, which read a `.spv`). `theCommandPlanIsHlslToSpirvThenTheDerivations` pins the exact vectors; `anEnvGatedRunResolvesHeadersThroughTheSourceDirectory`
(real shadercross, test cwd the package root) compiles a nested include and reddens without `-I`. The flag moves no byte of a headerless build (41 files identical, above).
**Cost if wrong.** None.

## BT-T - docs

**Ruling.** `docs/packaging.md` 4a gains a "Headers in `Shaders/`" paragraph (headers are inputs, `INCLUDES.sha256`, the copy path, the run-time check) and the consumer
pattern of gating the plugin with `#if os(Linux) || os(Windows)` in `Package.swift`, with the caveat that the condition is evaluated on **the host building the manifest**,
so a cross-compile from macOS skips it. The tool's usage text is unchanged (no flag was added).
**Cost if wrong.** Text.

## BT-U - tests

**Ruling.** New, always run, in `Tests/MetalUIShaderCompileTests/IncludeSourcesTests.swift` (14-22): the spelling table; the walk; the marker format and messages;
the copy path (matching, header-only edit, missing, extra, vanished, orphan, headerless unchanged); the compile arm's warning; the on-disk copy run; the tool writing and
removing the marker in both runs; the plugin region identity and `inputFiles`; the checked-in fixture having no headers. `Backends/SDL`: test 17,
`anIncludesMarkerIsAcceptedAndCheckedAgainstTheHeaders`. Env-gated (counts while skipped): `anEnvGatedRunResolvesHeadersThroughTheSourceDirectory`
(`METALUI_SHADERCROSS`) and arms (f)/(g) of `theBuildToolPluginCompilesVerifiesAndRefusesOnAFixturePackage` (the source includes `common.hlsli`; editing only the header reruns the
command and the copy path refuses it by name; with a real shadercross it recompiles and warns). Mutations below.
**Cost if wrong.** A test rename.

**Mutations** (2026-10-30, each applied, `swift test --build-system native --no-parallel --filter MetalUIShaderCompileTests` (root) or `--filter SDLGPUShader` (`Backends/SDL`), restored with `git checkout`; the spelling is the line named):

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
