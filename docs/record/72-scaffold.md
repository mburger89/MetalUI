# 72 — `metalui new` (application scaffolding)

Branch `feat/scaffold`, first stacked on `feat/app-icon` (PR #38), rebased
onto master after #38 merged (`95234db`). **Not a plan task**: user request
2026-10-01. Rulings `SC-A`…`SC-E` in
`docs/superpowers/2026-10-01-scaffold-decisions.md`, and `SC-F`…`SC-I` from
the review fixes (§6; next unused `SC-J`).
User guide: `docs/getting-started.md`. **Numbering**: written as §71; `feat/metal-view` (PR #40) merged first
and took §71, so this line renumbered to §72 at its rebase onto `65c0cc7`
(the 24→25 precedent).

**Status: LANDED.** No public declaration (`SC-A`), no SwiftUI behaviour
claimed, no divergence, no probe, no human check owed beyond what a user sees
running their own app.

## §0 What was built

- `Sources/MetalUIScaffold/Scaffold.swift` — options, validation (`SC-B`),
  generation, the writer, argument parsing and `runScaffold`; all `package`.
- `Sources/MetalUICLI/main.swift` — the `metalui` executable product.
- `Tests/MetalUIScaffoldTests/ScaffoldTests.swift` — 19 tests (one env-gated).
- Manifest: three targets and one product, all in the portable list (`PC-A`).

Generated package: `Package.swift`, `Sources/<Name>/main.swift`,
`Sources/<Name>/ContentView.swift`, `.gitignore`, `README.md`,
`Packaging/macOS/Info.plist`, `scripts/bundle-macos.sh`; with
`--cross-platform` also `Packaging/linux/<id>.desktop` and
`Packaging/windows/<Name>.rc`.

## §1 Runs (2026-10-01, macOS 27 / Swift 6.4, and `metalui-portable-ax`)

| Mode | What was run | Result |
| --- | --- | --- |
| `--local <worktree>` | `swift run metalui new HelloMetal`, `swift build`, launched the debug binary, captured the window by id | builds; window titled HelloMetal shows the heading, the button and "pressed 0 times" on the dark surface, filling the window |
| same | `scripts/bundle-macos.sh` with a 1024 px `Packaging/icon-1024.png` | release build; `Contents/Resources` holds `HelloMetal.icns` and `MetalUI_MetalUIRender.bundle`; `plutil -lint` OK; ad-hoc signed and `codesign --verify --strict` passes; `Contents/MacOS/HelloMetal` still running after 6 s |
| `--url file://<main checkout> --branch feat/scaffold` | generate, `swift build` (SwiftPM fetched and cloned the repository), launch | builds from a clone (the tracked shader-header symlink survives); running after 5 s |
| `--cross-platform --local`, macOS | generate, `swift build` | builds as the AppKit app; SwiftPM warns `'sdl': couldn't find pc file for accesskit` and about Homebrew's `-rpath` (resolution only — the SDL products are conditioned off macOS) |
| `--cross-platform --local`, Linux (`metalui-portable-ax`, SDL3 + AccessKit, `SDL_VIDEO_DRIVER=offscreen`) | the `metalui` tool itself run on Linux, then `swift build` of the generated app, then `timeout 6` on the binary | the tool runs on Linux; the app builds; it was still running at the 6 s timeout (exit 124) both with no fonts installed and with `fonts-dejavu-core` |
| `--cross-platform` without `--local` | `swift run metalui new Bad --cross-platform` | exit 1, `SC-C`'s message, nothing written |

Not run: Windows (no host); a look at the Linux window's text (offscreen);
Finder/Dock showing the generated `.icns` (a look).

## §2 Mutations

Each applied alone to `Scaffold.swift` in a separate worktree, rebuilt, the
19 tests run; the named test is the one that reddened (nothing else did).

| # | Mutation | Reddened |
| --- | --- | --- |
| M1 | drop the `MetalUI` prefix refusal | `aNameThatIsNotAModuleNameIsRefusedWithItsReason` |
| M2 | drop the first-character check | `aNameThatIsNotAModuleNameIsRefusedWithItsReason` |
| M3 | bundle id `parts.count >= 2` → `>= 1` | `aBundleIdentifierNeedsTwoNonEmptyReverseDNSParts`, `generationValidatesBeforeProducingAnything` |
| M4 | allow `--cross-platform` with a remote source | `crossPlatformWithoutALocalCheckoutIsRefused` |
| M5 | path identity always `"MetalUI"` | `aLocalCheckoutIsAPathDependencyNamedByItsDirectory`, `crossPlatformAddsTheSDLBackendOnLinuxAndWindowsOnly` |
| M6 | SDL condition gains `.macOS` | `crossPlatformAddsTheSDLBackendOnLinuxAndWindowsOnly` |
| M7 | drop the resource-bundle copy from the script | `theBundleScriptCopiesTheShaderResourcesIntoContentsResources` |
| M8 | writer's emptiness guard → `guard true` | `writingIntoANonEmptyDirectoryOrOntoAFileWritesNothing` |
| M9 | every file executable | `writingCreatesEveryFileAndMarksOnlyTheScriptExecutable` |
| M10 | allow `--local` with `--branch` | `theCommandLineRefusesWhatItCannotMean` |
| M11 | relative paths not resolved against the working directory | `theCommandLineResolvesRelativePathsAgainstTheWorkingDirectory` |
| M12 | skip the `--local` checkout check | `aLocalPathThatIsNotAMetalUICheckoutFailsBeforeAnythingIsWritten` |
| M13 | plist `CFBundleExecutable` wrong | `theInfoPlistNamesTheExecutableIdentifierAndIcon` |
| M14 | cross-platform `main.swift` without the SDL branch | `crossPlatformAddsTheSDLBackendOnLinuxAndWindowsOnly` |
| M15 | syntax error in the generated `ContentView.swift`, under `METALUI_RUN_SCAFFOLD_BUILD_TEST=1` | `aGeneratedPackageBuildsAgainstThisCheckout` |

**Instrument note**: M8's first spelling (deleting the `throw` inside a
`guard`) did not compile, and the run reported the previous mutant's stale
binary; the table's M8 is the second spelling (`guard true else {`), which
compiled.

## §3 Counts

`swift package clean`, native build, unfiltered `--no-parallel` run on the
rebased branch: **2068 tests in 3 suites passed** (2049 + 19; the env-gated
build test counts while skipped, making thirteen such tests), 0 goldens, 126
typecheck guards (none added; `FR-J no-argument frame: succeeded=true`).
`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
`Backends/SDL` and the Linux container's counts were not re-taken: nothing
under `Backends/` or the portable test package changed.

## §4 Windows CI finding

PR #39's first Windows run reddened `aLocalPathThatIsNotAMetalUICheckoutFailsBeforeAnythingIsWritten`
and `runningTheCommandWritesThePackageAndSaysWhatToRunNext`: Foundation on
Windows reports paths as `C:/…`, and the parser's absolute-path test looked
only for `/…` and `:\`, so it joined the working directory onto an absolute
path (`…/Temp/x/D:/a/MetalUI/MetalUI`). Fixed in `4ebfb25` (a drive letter
followed by `/` or `\`, or a leading `\`, is absolute). Those two tests are
the pin; on macOS they cannot see the case, so the red is Windows CI's run
`36970584289`, not a local mutation.

## §5 Counts after the rebase onto `65c0cc7` (metal view merged)

`swift package clean`, native build, unfiltered `--no-parallel`: **2112 tests
in 3 suites passed** (master's 2093 + 19), 129 typecheck guards (master's;
none added; `FR-J no-argument frame: succeeded=true`). §3's 2068 was taken on
`95234db`, before metal view.

## §6 Review fixes (2026-10-02, `fix/scaffold-review` from `6c05f3d`)

A review of PR #39 found four minor issues; each is fixed with a ruling,
`SC-F`…`SC-I` (decisions doc; next unused `SC-J`), and pinned by tests
written first.

### §6.1 What changed

| Ruling | Issue | Fix |
| --- | --- | --- |
| `SC-F` | the cross-platform README gave Windows Linux's `PKG_CONFIG_PATH` | `## Linux` (pkg-config, as run in `metalui-portable-ax`, §1) and `## Windows` (SDL3's VC package, `fetch-accesskit.py`, `-Xcc -I`/`-Xswiftc -L` for SDL3 and AccessKit, `SDL3.dll` on `Path` — `sdl-gpu-linux.yml`'s Windows job), the Windows section marked as not run for a generated app |
| `SC-G` | a cross-platform build on macOS warns about `accesskit`'s pc file and Homebrew's `-rpath` | the README's `## macOS` quotes both and says why they are harmless; not suppressed (that needs `Backends/SDL`'s manifest) |
| `SC-H` | `validateName` accepted names that fail `swift build` | the measured clashes are refused with the clash named (§6.3) |
| `SC-I` | the default dependency was unpinned `branch: "master"` | `revision:` the merge base of HEAD and `origin/master` in the checkout `#filePath` names, when its origin is the URL; `--revision`/`--branch` override; fallback to the branch with a note; README `## Updating MetalUI` |

### §6.2 Red first

Against `6c05f3d`'s `Scaffold.swift`, the new name and README tests compiled
and failed: `aNameThatClashesWithAModuleTheAppBuildsWithIsRefused` (all 40
refused arguments), `aNameThatIsADependencysPackageIdentityIsRefused`,
`theCrossPlatformReadmeGivesLinuxAndWindowsTheirOwnBuildSteps`,
`theCrossPlatformReadmeExplainsTheMacOSWarnings`;
`aLookAlikeOfARefusedNameIsAccepted` passed, as the accepted side should.
`SC-I`'s eight tests are against new API (`GitReference`, `PinLookup`,
`lookUpPin`, `runGit`, the `pinLookup:` parameters), so their red against
the base was a compile failure, not an assertion; their discrimination is
§6.4's mutations C and D.

### §6.3 The name measurements

Each name generated with `metalui new <Name> --local <worktree>` and built
with `swift build` (the default build system; one shared `--scratch-path`
so MetalUI built once). Refused (failed):

- `Swift`: "module name "Swift" is reserved for the standard library".
- "module dependency cycle" (macOS 27 / Swift 6.4): `Foundation`, `AppKit`,
  `Metal`, `CoreText`, `CoreGraphics`, `QuartzCore`, `CoreVideo`,
  `CoreImage`, `CoreFoundation`, `Dispatch`, `Darwin`, `ObjectiveC`,
  `Combine`, `Observation`, `simd`, `os`, `IOKit`, `ImageIO`,
  `UniformTypeIdentifiers`, `Accessibility`, `SwiftUICore`, `Spatial`,
  `DeveloperToolsSupport`, `SwiftShims` ("circular dependency … and
  '_Concurrency'"), `_Concurrency`, `_StringProcessing` (both with
  `--bundle-id`, since `com.example._X` is not a bundle identifier).
- "circular dependency between modules" on Linux (`metalui-portable-ax`,
  `swift:6.4-noble`, aarch64): `Glibc`, `FoundationEssentials`,
  `Foundation`, `Dispatch`. (`AppKit` and `Musl` failed there too, but on
  the default template's `App()` call — the default app is macOS-only — so
  they are not name failures.) `WinSDK` is refused by derivation; no Windows
  host.
- "target names need to be unique across the package graph": `CFreeType`,
  `CHarfBuzz`, `CUnibreak`, `CSheenBidi`; with `--cross-platform`, `CSDL`,
  `SDLBridge`, `CAccessKit`, `ReplayFixture`, `SDLReplay`, `PortableReplay`,
  `DemoCapture` (`ReplayFixtureTests`, a test target, built).
- `SDL` and `sdl` with `--cross-platform`: "product 'MetalUISDL' required by
  package 'sdl' target 'SDL' not found in package 'SDL'" — the root's
  identity is its directory, lowercased, the same as `Backends/SDL`'s. `SDL`
  without `--cross-platform` built.

Accepted (built): `swift`, `SWIFT`, `foundation` (also re-built in a fresh
scratch directory, status 0), `appkit`, `metal`, `coretext`, `observation`,
`cfreetype`, `MetalKit`, `Glibc` and `WinSDK` on macOS, `XCTest`, `Testing`,
`SwiftUI`, `PackageDescription`, `SDL3`, `class`, `Self`, `Any`, `Type`,
`func`, `Protocol`, `Cocoa`, `Synchronization`, `Accelerate`, `Distributed`,
`RegexBuilder`, and `CSDL`/`SDLBridge`/`CAccessKit`/`ReplayFixture` without
`--cross-platform`. The SDL targets are refused in every mode anyway. The
list is the measured clashes, not AppKit's whole import closure.

### §6.4 Mutations

Committed first (`bea3d84`); each applied alone to `Scaffold.swift` by a
script, restored from a copy (`git status` clean in `Sources`/`Tests`
afterwards, 0 `MUTATION` markers), unfiltered `swift test --build-system
native --no-parallel`, every run 2124 tests.

| # | Mutation | Issues | Reddened |
| --- | --- | --- | --- |
| A | drop `"Metal"` from the refused system modules | 1 | `aNameThatClashesWithAModuleTheAppBuildsWithIsRefused` (argument `Metal`) |
| B | the Windows section's body replaced by the Linux section's | 8 | `theCrossPlatformReadmeGivesLinuxAndWindowsTheirOwnBuildSteps` |
| C | the parser ignores the looked-up revision (`.revision` → `branch: master`) | 2 | `theCommandLineDefaultsToTheGitURLPinnedAndTheWorkingDirectory`, `runningTheCommandSaysWhatItPinnedOrWhyItDidNot` |
| D | no fallback: `.unavailable` throws instead of following `master` | 4 | `withNoCommitToPinThePackageFollowsMasterAndSaysWhy`, `runningTheCommandSaysWhatItPinnedOrWhyItDidNot` |

### §6.5 End to end

- Default (remote, pinned): `swift run metalui new PinnedApp` printed
  "MetalUI is pinned to 6c05f3da742dc7c1f0d858fa983244789254a33d"; the
  manifest reads `.package(url: "https://github.com/mburger89/MetalUI.git",
  revision: "6c05f3d…")`; `swift build` fetched from GitHub, resolved that
  revision (`Package.resolved` `"revision" : "6c05f3d…"`) and built (status
  0). Not launched.
- Fallback: a copy of the binary run with `PATH=/nonexistent` printed the
  note ("… is not a git checkout with an origin remote, or git is not on the
  PATH …") and wrote `branch: "master"`.
- `metalui new Foundation` and `metalui new SDL --local . --cross-platform`
  exit 1 with `SC-H`'s reasons; a cross-platform README was read through.

### §6.6 Counts

`swift package clean`; `swift build --build-system native --build-tests`: 0
`error:`, the one `warning:` SwiftPM's deprecation notice; `swift build
--build-tests`: 0 `error:`, 0 `warning:`; unfiltered `swift test
--build-system native --no-parallel`: **2124 tests in 3 suites passed** (2112
+ 12 scaffold tests; 31 in `MetalUIScaffoldTests`), FR-J
`succeeded=true`, 129 guards (none added).
`METALUI_RUN_SCAFFOLD_BUILD_TEST=1 … aGeneratedPackageBuildsAgainstThisCheckout`
passed. `closeout-inventory-check.sh` and `closeout-undocumented.sh` print
nothing (everything new is `package`). `Backends/SDL` and the Linux
container's counts not re-taken: nothing there changed.

**Not verified by a run**: the Windows README steps (no host — CI-derived);
`WinSDK`'s refusal (derived); the pin lookup on Windows (`runGit`'s `Path`
search and `git.exe` are untested there until Windows CI runs
`gitRunsFromThePathAndAFailureIsNil`).
