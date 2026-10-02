# Scaffold decisions (`SC-`)

`metalui new`: a new application package that depends on MetalUI. User
request 2026-10-01 (not a plan task), on `feat/scaffold`. Record §72. The
user chose, up front: a CLI in this package; macOS by default with an opt-in
SDL path; a git-URL dependency overridable to a local path; `.app` packaging
generated, built on the app-icon line's `docs/packaging.md` (PR #38).

Next unused: `SC-J`.

## SC-A — a portable `metalui` executable over a `package`-access library

`MetalUIScaffold` (Foundation only) generates and writes the files and parses
the command line; `MetalUICLI` is the `metalui` executable product, a
three-line `main.swift`. Both import no Apple framework, so they sit in the
manifest's portable list (`PC-A`) and build in the Linux and Windows CI jobs.
Every declaration is `package`, not `public`: the scaffolder is a tool, not
framework API, so it adds nothing to the public-API census and owes no
inventory row. Rejected: a SwiftPM command plugin (it may write only inside
the package that invokes it, so it cannot create a fresh package), a shell
script (no Windows, no tests), a template directory alone (copying by hand is
the problem being solved). No SwiftUI counterpart exists (Xcode's templates
are an IDE feature), so no probe and no divergence.

## SC-B — the name is a module name

The name becomes the package, product, target and module. It must be an ASCII
Swift identifier (letter or `_` first, then letters, digits, `_`) so SwiftPM
uses it unchanged as the module name, and must not start with `MetalUI` (any
case), which would collide with the framework's modules. The bundle
identifier needs at least two non-empty dot-separated parts of letters,
digits and `-`. Both are checked before anything is generated; the writer
refuses a destination that is a file or a non-empty directory before writing
anything.

## SC-C — `--cross-platform` needs `--local`

`Backends/SDL` is its own package depending on MetalUI by `path: "../.."`.
SwiftPM cannot fetch a package from a subdirectory of a git repository, and a
URL-fetched MetalUI beside a path-fetched `Backends/SDL` would be two
different MetalUI packages. So the cross-platform manifest uses two path
dependencies on one checkout, and the scaffolder refuses `--cross-platform`
without `--local`. A path dependency's identity is its directory's last
component (a checkout in `metalui-fork/` is `package: "metalui-fork"`), which
the generated `.product(package:)` follows. The SDL, portable-text and
system-font products are conditioned on `.linux, .windows`, so a macOS build
never compiles SDL (SwiftPM still resolves it and warns about the missing
`accesskit.pc`; harmless).

## SC-D — packaging is `docs/packaging.md`, generated

`Packaging/macOS/Info.plist` is packaging.md's plist with the app's name and
identifier; `scripts/bundle-macos.sh` is its bundle recipe, with the resource
bundle in `Contents/Resources` (`AI-N`) and the `.icns` made only when
`Packaging/icon-1024.png` exists (no binary is generated). Cross-platform adds
the `.desktop` entry and the one-line `.rc`. The generated app leaves
`App.icon` at `[]`, so a bundled app shows its bundle's icon (`AI-C` item 1).

## SC-E — what is tested, what was run

19 unit tests pin the generated text, validation, the writer and the command
line; each of fourteen mutations reddens its named test (record §72 §2). That
a generated package *builds* is `aGeneratedPackageBuildsAgainstThisCheckout`,
env-gated (`METALUI_RUN_SCAFFOLD_BUILD_TEST=1`) because it is a second full
MetalUI build; it counts while skipped. The launches in record §72 §1 are
runs, not tests.

## SC-F — the generated README gives Linux and Windows their own build steps

Review finding (2026-10-02, `fix/scaffold-review`): the cross-platform README
told Windows to set `PKG_CONFIG_PATH`, which Windows does not have. The
README now has a `## Linux` and a `## Windows` section, each with what CI
actually does to build `Backends/SDL` there. **Linux**: SDL3 with pkg-config
(Ubuntu 24.04 ships only SDL2, so CI builds SDL3 from source,
`Backends/SDL/linux/Dockerfile`), `python3 <checkout>/Backends/SDL/scripts/fetch-accesskit.py`,
then `PKG_CONFIG_PATH=<checkout>/Backends/SDL/.accesskit swift run <Name>` —
run for a generated app in `metalui-portable-ax` (record §72 §1). **Windows**:
SDL3's prebuilt VC package, the same script (which prints the flags), and
`swift run @flags <Name>` with `-Xcc -I`/`-Xswiftc -L` for SDL3 and AccessKit
and SDL3's `lib\x64` on `Path` for the DLL — `sdl-gpu-linux.yml`'s Windows
job, line for line. The Windows section says in italics that a generated app
has **not been built on Windows**: it is CI-derived, not run. The checkout
path is the `--local` path, written in. Pinned by
`theCrossPlatformReadmeGivesLinuxAndWindowsTheirOwnBuildSteps`.

## SC-G — the macOS warnings are explained, not hidden

A `--cross-platform` app built on macOS prints
`warning: 'sdl': couldn't find pc file for accesskit` and (with Homebrew's
SDL3) `warning: 'sdl': prohibited flag(s): -Wl,-rpath,/opt/homebrew/lib`
(re-measured 2026-10-02). SwiftPM loads every dependency's system-library
targets on every platform, whatever the products' conditions; nothing of SDL
compiles or links on macOS. Making them disappear needs a change to
`Backends/SDL`'s manifest (dropping `pkgConfig:` on macOS), which would move
that package's own macOS build and is out of scope; the README's new
`## macOS` section quotes both warnings and says why they are harmless.
Pinned by `theCrossPlatformReadmeExplainsTheMacOSWarnings`.

## SC-H — names that fail later are refused now, from measurement

`SC-B` accepted names that pass validation and then fail `swift build`. Each
candidate was generated with `--local` and built (record §72 §6.3); the
refused list is what failed, with the reason the build gave:

- `Swift` — "module name "Swift" is reserved for the standard library".
- A module MetalUI imports, directly or through AppKit or Foundation — a
  module dependency cycle: on macOS `Foundation`, `AppKit`, `Metal`,
  `CoreText`, `CoreGraphics`, `QuartzCore`, `CoreVideo`, `CoreImage`,
  `CoreFoundation`, `Dispatch`, `Darwin`, `ObjectiveC`, `Combine`,
  `Observation`, `simd`, `os`, `IOKit`, `ImageIO`, `UniformTypeIdentifiers`,
  `Accessibility`, `SwiftUICore`, `Spatial`, `DeveloperToolsSupport`,
  `SwiftShims`, `_Concurrency`, `_StringProcessing`; on Linux
  (`swift:6.4-noble`) `Glibc`, `FoundationEssentials` (and `Foundation`,
  `Dispatch` again). `WinSDK` is **derived**, not measured (no Windows host):
  Foundation imports it on Windows as it imports `Glibc` on Linux.
- A target of MetalUI (`CFreeType`, `CHarfBuzz`, `CUnibreak`, `CSheenBidi`)
  or of `Backends/SDL` (`CSDL`, `SDLBridge`, `CAccessKit`, `ReplayFixture`,
  `SDLReplay`, `PortableReplay`, `DemoCapture`) — "target names need to be
  unique across the package graph". The SDL ones fail only with
  `--cross-platform` and are refused in every mode.
- A dependency's **package identity** in any case — SwiftPM identifies the
  root by its directory's name too: `SDL`/`sdl` beside `Backends/SDL` fails
  ("product 'MetalUISDL' … not found in package 'SDL'"); by the same
  mechanism, an app named after its `--local` checkout's directory. Checked at
  generation, since it depends on the options.

**Accepted, measured**: lowercase look-alikes (`foundation`, `appkit`,
`metal`, `swift`, `coretext`, `observation`, `cfreetype` — module lookup is
case-sensitive even on case-insensitive APFS; `foundation` re-built in a
fresh scratch directory), Swift keywords (`class`, `func`, `Self`, `Any`,
`Type`, `Protocol`: a keyword is a valid module name), and modules a MetalUI
app does not import (`MetalKit`, `SwiftUI`, `XCTest`, `Testing`, `Cocoa`,
`Accelerate`, `Synchronization`, `Distributed`, `RegexBuilder`, `SDL3`,
`PackageDescription`). **The list is not exhaustive**: any module in MetalUI's
transitive import closure on the build platform clashes, and on macOS that is
AppKit's, dozens of frameworks; it holds the measured ones. Matching is
case-sensitive (identity is not). Pinned by
`aNameThatClashesWithAModuleTheAppBuildsWithIsRefused`,
`aLookAlikeOfARefusedNameIsAccepted`,
`aNameThatIsADependencysPackageIdentityIsRefused`.

## SC-I — the default dependency is pinned to a commit on the remote

`branch: "master"` let a generated app pick up any breaking change on its next
`swift package update` (master had just gained defaultless requirements).
Now `metalui new` writes `.package(url:, revision: <commit>)`:

- **The commit** is `git merge-base HEAD refs/remotes/origin/master` in the
  checkout the scaffolder was built from — the newest commit of the remote's
  default branch, as last fetched, that the scaffolder's own source contains.
  It is on the remote (an unpushed local HEAD is never pinned) and is the
  remote commit closest to the code that wrote the template.
- **The checkout** is found by `#filePath` at build time
  (`<checkout>/Sources/MetalUIScaffold/Scaffold.swift`, three levels up):
  `metalui` is run with `swift run` from that checkout. The process's own
  path was rejected — `--scratch-path` moves it anywhere.
- **Only a clone of the URL** is asked: its `remote.origin.url`, normalized
  (`https://…`, `ssh://git@…`, `git@host:…`, case, a trailing `.git` or `/`),
  must equal the target URL — `--url` of a fork is pinned only from a clone of
  that fork.
- **Fallback**: no git on the PATH, no repository at that path (the executable
  outlived its checkout), another origin, or no `origin/master` sharing a
  commit with HEAD → `branch: "master"` and a note on standard error saying
  why and to pin with `--revision`.
- **Overrides**: `--revision <commit>` pins that commit, `--branch <b>`
  follows a branch; neither is looked up; they cannot be combined with each
  other or with `--local`.
- The generated README gains `## Updating MetalUI` (per source: how to move a
  pin, what following a branch means, a local checkout), and the manifest a
  comment pointing at it.

Generation stays pure: `parseScaffoldCommand` takes the lookup as a closure,
`lookUpPin` takes the git runner as one, and `runScaffold` defaults to the
real ones. Pinned by `theCommandLineDefaultsToTheGitURLPinnedAndTheWorkingDirectory`,
`anExplicitRevisionOrBranchOverridesThePin`,
`withNoCommitToPinThePackageFollowsMasterAndSaysWhy`,
`aPinnedRevisionIsARevisionDependency`, `theReadmeSaysHowToUpdateMetalUI`,
`thePinIsTheMergeBaseOfHeadAndOriginMasterInACloneOfTheURL`,
`gitRunsFromThePathAndAFailureIsNil`,
`runningTheCommandSaysWhatItPinnedOrWhyItDidNot`.
