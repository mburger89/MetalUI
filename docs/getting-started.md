# Starting a new MetalUI app

`metalui new` writes a SwiftPM package with an executable that opens a MetalUI
window, and a script that bundles it as a signed macOS `.app` (ruling `SC-A`,
`docs/superpowers/2026-10-01-scaffold-decisions.md`).

```sh
git clone https://github.com/mburger89/MetalUI.git
swift run --package-path MetalUI metalui new MyApp
cd MyApp
swift run MyApp
```

`swift run --package-path` leaves the current directory where it is, so
`MyApp/` is created beside the clone. `metalui --help` lists every option.

## What you get

```
MyApp/
  Package.swift                  depends on MetalUI (git URL, pinned to one commit)
  Sources/MyApp/main.swift       App(), one window, app.run()
  Sources/MyApp/ContentView.swift  a Component with @State and a Button
  Packaging/macOS/Info.plist     identifier com.example.MyApp (--bundle-id)
  scripts/bundle-macos.sh        → build/MyApp.app
  README.md, .gitignore
```

## Which MetalUI the app gets

The generated `Package.swift` pins MetalUI to **one commit** (`SC-I`):
`.package(url: "https://github.com/mburger89/MetalUI.git", revision: "<commit>")`,
so nothing that changes on MetalUI's `master` reaches the app until you move
the pin. The commit is `git merge-base HEAD origin/master` in the checkout
`metalui` was built from — the newest commit of the remote's `master`, as that
checkout last fetched it, that the scaffolder's own source contains — so it
always exists on GitHub, never a local unpushed one. `metalui` prints it. To
start from today's `master`, `git pull` the clone first.

When there is no such commit — git not on the `PATH`, the clone's `origin` is
not the `--url`, or no `origin/master` — the manifest follows
`branch: "master"` and `metalui` prints a note saying why. `--revision
<commit>` pins a commit you choose; `--branch <b>` follows a branch instead.
The app's README, under "Updating MetalUI", says how to move the pin
deliberately: put a newer commit in `revision:`, then `swift package update`.

`scripts/bundle-macos.sh` is `docs/packaging.md`'s macOS recipe: a release
build, MetalUI's shader resources (`MetalUI_MetalUIRender.bundle`) in
`Contents/Resources` (`AI-N`), an `.icns` made from
`Packaging/icon-1024.png` when that file exists, and an ad-hoc signature
(`CODESIGN_IDENTITY=…` signs with a real identity).

## Options

| Option | Effect |
| --- | --- |
| `--path <dir>` | create `<dir>/MyApp` instead of `./MyApp` |
| `--bundle-id <id>` | the app's identifier (default `com.example.<Name>`) |
| `--local <checkout>` | depend on a MetalUI checkout on disk (`.package(path:)`) — for framework development |
| `--url <git URL>` | another repository (pinned only from a clone of it) |
| `--revision <commit>` | pin this commit instead of the looked-up one |
| `--branch <b>` | follow a branch instead of pinning (not with `--revision`; neither with `--local`) |
| `--cross-platform` | also run on Linux and Windows through `Backends/SDL`; **needs `--local`** |

The name must be an ASCII Swift identifier not starting with `MetalUI`
(`SC-B`): it becomes the package, product, target and module name. Names that
would fail later are refused with the clash named (`SC-H`, each measured by
building a generated package): `Swift`; a module MetalUI imports, directly or
through AppKit or Foundation (`Foundation`, `AppKit`, `Metal`, `CoreText`,
`Combine`, `Observation`, `Glibc`, `WinSDK`, …); a target of MetalUI or of
`Backends/SDL` (`CFreeType`, `CSDL`, …); and a dependency's package identity
in any case (`SDL` with `--cross-platform`). Module names are case-sensitive,
so `foundation` or `metal` is accepted, and so is a keyword such as `class`.
The list holds the measured clashes; it is not every module in AppKit's
import closure. The
destination must be absent or empty; nothing is written otherwise.

## Linux and Windows (`--cross-platform`)

```sh
swift run --package-path MetalUI metalui new MyApp --local MetalUI --cross-platform
```

On macOS the app is the same AppKit/Metal app. On Linux and Windows it opens an
`SDLPlatform` window with `PortableTextSystem` over the platform's installed
fonts (`SystemFonts.resolver()`). The SDL backend is the separate package at
`Backends/SDL`, which depends on MetalUI by relative path, so SwiftPM can only
reach it from a checkout — hence `--local` (`SC-C`). It needs SDL3 and
AccessKit, and the generated README gives each platform its own steps
(`SC-F`): on Linux, `python3 <checkout>/Backends/SDL/scripts/fetch-accesskit.py`
once, then build with `PKG_CONFIG_PATH=<checkout>/Backends/SDL/.accesskit`; on
Windows, which has no pkg-config, the same script prints AccessKit's
`-Xcc -I…`/`-Xswiftc -L…` flags, passed to `swift run` with SDL3's, as
Windows CI does (not yet run for a generated app). On macOS `swift build`
prints two SwiftPM warnings about the SDL package (`accesskit`'s missing pc
file, Homebrew's `-rpath`); they are harmless — nothing of SDL is compiled on
macOS — and the README's macOS section says so (`SC-G`).
The generated `Packaging/linux/<id>.desktop` and `Packaging/windows/MyApp.rc`
are `docs/packaging.md`'s Linux and Windows sections.
