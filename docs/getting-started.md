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
  Package.swift                  depends on MetalUI (git URL, branch master)
  Sources/MyApp/main.swift       App(), one window, app.run()
  Sources/MyApp/ContentView.swift  a Component with @State and a Button
  Packaging/macOS/Info.plist     identifier com.example.MyApp (--bundle-id)
  scripts/bundle-macos.sh        → build/MyApp.app
  README.md, .gitignore
```

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
| `--url <git URL>`, `--branch <b>` | another repository or branch (cannot combine with `--local`) |
| `--cross-platform` | also run on Linux and Windows through `Backends/SDL`; **needs `--local`** |

The name must be an ASCII Swift identifier not starting with `MetalUI`
(`SC-B`): it becomes the package, product, target and module name. The
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
AccessKit: once, in the checkout, `python3 Backends/SDL/scripts/fetch-accesskit.py`,
then build the app with `PKG_CONFIG_PATH=<checkout>/Backends/SDL/.accesskit`.
The generated `Packaging/linux/<id>.desktop` and `Packaging/windows/MyApp.rc`
are `docs/packaging.md`'s Linux and Windows sections.
