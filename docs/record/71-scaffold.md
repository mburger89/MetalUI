# 71 — `metalui new` (application scaffolding)

Branch `feat/scaffold`, first stacked on `feat/app-icon` (PR #38), rebased
onto master after #38 merged (`95234db`). **Not a plan task**: user request
2026-10-01. Rulings `SC-A`…`SC-E` in
`docs/superpowers/2026-10-01-scaffold-decisions.md` (next unused `SC-F`).
User guide: `docs/getting-started.md`. **Numbering**: §71 was free on master
at the time; `feat/metal-view` was also told to take "§71 or later" (record
§70's header) — whichever line merges second renumbers, per the 24→25
precedent.

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
