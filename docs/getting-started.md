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
| `--cross-platform` | also run on Linux and Windows through MetalUI's SDL backend (its `SDL` and `AccessKit` traits); any source — URL, `--branch`, `--revision` or `--local` (`PX-J`) |
| `--no-accesskit` | with `--cross-platform`: the `SDL` trait alone — no screen-reader support on Linux and Windows, nothing of AccessKit to install |

The name must be an ASCII Swift identifier not starting with `MetalUI`
(`SC-B`): it becomes the package, product, target and module name. Names that
would fail later are refused with the clash named (`SC-H`, each measured by
building a generated package): `Swift`; a module MetalUI imports, directly or
through AppKit or Foundation (`Foundation`, `AppKit`, `Metal`, `CoreText`,
`Combine`, `Observation`, `Glibc`, `WinSDK`, …); a target of MetalUI's root
package, the SDL backend's included (`CFreeType`, `CStbImage`, `CSDL`,
`SDLBridge`, `CAccessKit` — SwiftPM checks target names across the whole graph,
traits or not, `PX-J` item 4); and, with `--local`, the checkout directory's
name in any case. Module names are case-sensitive,
so `foundation` or `metal` is accepted, and so is a keyword such as `class`.
The list holds the measured clashes; it is not every module in AppKit's
import closure. The
destination must be absent or empty; nothing is written otherwise.

## Linux and Windows (`--cross-platform`)

```sh
swift run --package-path MetalUI metalui new MyApp --cross-platform
```

On macOS the app is the same AppKit/Metal app. On Linux and Windows it opens an
`SDLPlatform` window with `PortableTextSystem` over the platform's installed
fonts (`SystemFonts.resolver()`). The SDL backend is the root package's
`MetalUISDL` product (its sources are in `Backends/SDL/Sources`), compiled only
under MetalUI's **`SDL` trait**; **`AccessKit`** (which turns `SDL` on too) adds
the screen-reader bridge (`PX-H`). Neither is on by default, so a macOS app, and
MetalUI's own build, never needs SDL. The generated manifest asks for both on
Linux and Windows only — this is what to add to an existing package by hand:

```swift
// swift-tools-version: 6.1
#if os(Linux) || os(Windows)
let metalUITraits: Set<Package.Dependency.Trait> = ["SDL", "AccessKit"]
#else
let metalUITraits: Set<Package.Dependency.Trait> = [.defaults]
#endif
// dependencies:
.package(url: "https://github.com/mburger89/MetalUI.git", revision: "<commit>", traits: metalUITraits),
// the app target's dependencies:
.product(name: "MetalUI", package: "MetalUI"),
.product(name: "MetalUISDL", package: "MetalUI", condition: .when(platforms: [.linux, .windows])),
.product(name: "MetalUIPortableText", package: "MetalUI"),
.product(name: "MetalUISystemFonts", package: "MetalUI"),
```

`MetalUIPortableText` and `MetalUISystemFonts` are named on every platform,
not only Linux and Windows (ruling `SG-D`): with the condition, SwiftPM's
default build system on macOS drops their C modules' module maps from a test
target that names them too, and `swift build --build-tests` fails with
`error: unable to resolve module dependency: 'CFreeType'` (and `CHarfBuzz`,
`CSheenBidi`, `CUnibreak`; the native build system builds it). Both are
portable, so they build on macOS; a macOS app links them unused (2.15 MB of a
release binary, measured: 10 706 552 bytes against 8 554 184 with the
condition).

Forgetting `traits:` leaves `MetalUISDL` an empty module whose `SDLPlatform`
is unavailable with the remedy as its message ("'SDLPlatform' is unavailable:
enable the trait 'SDL' on the MetalUI dependency…"). Written inside
`App(platform: try SDLPlatform(), …)`, as the generated `main.swift` does, the
compiler reports "argument type 'SDLPlatform' does not conform to expected type
'Platform'" first — the same cause (`PX-S` item 2).

### What a Linux machine needs (`PX-I`, `PX-Q`)

1. **SDL 3.4 or later**, its headers and `libSDL3` on the compiler's default
   paths: a distribution's `libsdl3-dev` where it ships 3.4 or later (Ubuntu
   24.04 ships only SDL2), or SDL built from source and installed with
   `-DCMAKE_INSTALL_PREFIX=/usr`, as MetalUI's CI image does
   (`Backends/SDL/linux/Dockerfile`). Anywhere else, pass
   `-Xcc -I<prefix>/include -Xlinker -L<prefix>/lib` to every `swift build` and
   `swift run`: the Swift importer ignores `CPATH`, and gold does not search
   `/usr/local/lib`.
2. **AccessKit's C bindings**, once, after SwiftPM has fetched MetalUI:

   ```sh
   swift package resolve
   sudo python3 .build/checkouts/MetalUI/Backends/SDL/scripts/fetch-accesskit.py --prefix /usr
   ```

   It downloads accesskit-c 0.23.0, checks its SHA-256, stages it in a
   temporary directory and copies only `accesskit.h` and `libaccesskit.a`
   under `/usr` — nothing is written into the checkout. The release has
   prebuilt libraries for Linux x86_64 (and macOS, Windows x64); **on Linux
   aarch64 the script builds the library with a Rust toolchain (`cargo`)**,
   which must be installed first. `--print-flags` instead of `--prefix` keeps
   the files in `$ACCESSKIT_DIR` (default `Backends/SDL/.accesskit` beside the
   script) and prints the `-Xcc`/`-Xlinker` flags to pass, one per line. Or
   leave AccessKit out: `metalui new --no-accesskit`, or remove `"AccessKit"`
   from `metalUITraits` — the app then has no screen-reader support.
3. With both on the default paths the build is plain `swift build` /
   `swift run MyApp` — measured in the CI image by
   `aCrossPlatformPackageBuildsItsSDLAppByURL` (a generated package on a
   `file://` copy of MetalUI) and, without AccessKit, by
   `aCrossPlatformPackageBuildsWithoutAccessKit`.

To ship the built app, copy `.build/checkouts/MetalUI/Backends/SDL/Shaders/compiled`
beside the executable as `MetalUISDLShaders`: the backend looks there first,
then in the source tree it was built from (`PX-P`; `docs/packaging.md`).

### Windows

No pkg-config, as before: unpack SDL3's prebuilt Visual C++ package
(`SDL3-devel-3.4.16-VC.zip`), then hand SwiftPM SDL3's paths and AccessKit's,
which `fetch-accesskit.py --print-flags` prints (`-Xcc -I…`, `-Xswiftc -L…`, one
per line) — what Windows CI does; a generated app has not yet been built on
Windows (human check X4). `SDL3.dll` and `MetalUISDLShaders` go beside the
executable.

### macOS with SDL

Only for an app that chooses SDL on macOS (the default is AppKit):
`brew install sdl3`, and `-Xcc -I$(brew --prefix)/include -Xlinker
-L$(brew --prefix)/lib` plus AccessKit's flags — `fetch-accesskit.py
--print-flags` prints all of them on macOS. Homebrew's dylib links with one
`ld` deployment-target warning, Homebrew's and not MetalUI's.

The generated README gives each platform these steps (`PX-J` item 3). The
generated `Packaging/linux/<id>.desktop` and `Packaging/windows/MyApp.rc` are
`docs/packaging.md`'s Linux and Windows sections.

## Call `app.run()` from top-level code

The generated `main.swift` calls `app.run()` from **synchronous top-level
code**. Keep it that way: under an `async` main (`@main` with
`static func main() async`, or a top-level `await` before `run()`), `run()`
executes inside a main-actor job, and neither platform's loop can then drain
the main queue — a `Task { @MainActor in … }` started from a button action, or
the continuation of an awaited `window.fileDialogs.openFiles(…)`, never runs
(ruling `SV-H` item 2; probe `swift-main-queue-drain-nested.swift` `J1`, `J3`,
macOS and Linux). From top-level code SDL's loop drains the main queue once per
iteration, so such work runs on Linux and Windows too (`SV-H` item 1).
