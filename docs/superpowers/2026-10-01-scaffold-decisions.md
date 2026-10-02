# Scaffold decisions (`SC-`)

`metalui new`: a new application package that depends on MetalUI. User
request 2026-10-01 (not a plan task), on `feat/scaffold`. Record §72. The
user chose, up front: a CLI in this package; macOS by default with an opt-in
SDL path; a git-URL dependency overridable to a local path; `.app` packaging
generated, built on the app-icon line's `docs/packaging.md` (PR #38).

Next unused: `SC-F`.

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
