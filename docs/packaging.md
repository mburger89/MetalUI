# Packaging a MetalUI application with its icon

**Build-side, not framework API** (ruling `AI-H`,
`docs/superpowers/2026-10-01-app-icon-decisions.md`). Nothing on this page is
a MetalUI type or function: it is how each operating system finds an
application's icon *before the program runs* — in Finder, a file manager, a
launcher, Explorer — which no runtime API can reach.

**`App.icon` is the other half.** `app.icon = [ImageBitmap]` (`AI-A`) is the
runtime override: it sets the Dock icon of an unbundled `swift run`
executable (`NSApplication.applicationIconImage`, `AI-E`) and every SDL
window's icon (`SDL_SetWindowIcon`, `AI-F`). A properly packaged application
normally needs **neither** — the bundle's, the `.desktop` file's or the
executable's own icon is shown from launch — and leaving `App.icon` at `[]`
(its default) never touches it (`AI-C` item 1). Use both only when the
running icon should differ from the installed one. SwiftUI has no runtime icon API;
a SwiftUI app's icon is its bundle's, exactly as below.

**What "verified" means here.** Every command was either run on 2026-10-01
(macOS 27 on Apple silicon, or a `swift:6.4-noble` Linux container) and is
marked **verified** with what was checked, or is marked **unverified**. No
command was run on Windows. Looking at an icon on screen is a human check
(`docs/verification/human-checks.md`, group O).

The examples use one 1024 × 1024 PNG, `icon-1024.png`, and an application
called `MyApp`, built from a SwiftPM executable product `MyApp`.

## Third-party notices

A MetalUI binary contains third-party code, so a package must carry its
notices. `stb_image` is in **every** `MetalUI` binary, macOS included; FreeType,
HarfBuzz, libunibreak and SheenBidi come with the portable text system
(`MetalUIPortableText`, always on Linux and Windows); SDL3 and AccessKit come
with the `SDL` and `AccessKit` traits. `THIRD-PARTY-NOTICES.md` (repo root)
says which product contains what and where each licence text is. Ship that
file and the licence files it names beside the application: in an `.app`
`Contents/Resources`, under `/usr/share/doc/<app>/` on Linux, next to the
`.exe` on Windows. From a checkout (a SwiftPM dependency is under
`.build/checkouts/MetalUI`):

```bash
mkdir -p "$DEST" && cp THIRD-PARTY-NOTICES.md "$DEST"/
for f in CStbImage/LICENSE CFreeType/FTL.TXT CFreeType/LICENSE.TXT CHarfBuzz/COPYING CUnibreak/LICENCE CSheenBidi/LICENSE; do
  cp "Sources/$f" "$DEST/$(dirname "$f")-$(basename "$f")"
done
```

(Drop the directories your product does not contain, see the table in the
notices file.) SDL3's and
AccessKit's licence texts are not in this repo.

## macOS: an `.app` bundle with an `.icns`

A SwiftPM executable is a bare Mach-O file; Finder shows it with the generic
executable icon, and the Dock does too unless `App.icon` is set while it
runs. Build the executable, then lay the bundle out by hand.

### 1. The `.icns` — verified

```sh
mkdir MyApp.iconset
for n in 16 32 128 256 512; do
  sips -z $n $n icon-1024.png --out MyApp.iconset/icon_${n}x${n}.png
  sips -z $((n*2)) $((n*2)) icon-1024.png --out MyApp.iconset/icon_${n}x${n}@2x.png
done
iconutil -c icns MyApp.iconset -o MyApp.icns
```

**Verified**: `file MyApp.icns` reads `Mac OS X icon, … "ic12" type`, and
`iconutil -c iconset MyApp.icns` round-trips all ten images. The iconset's
file names are `iconutil`'s convention (`icon_<size>x<size>[@2x].png`). An asset catalog (`AppIcon` in
an `.xcassets`, compiled by `actool`) is the Xcode route and needs an Xcode
project or `xcrun actool` — **unverified** here.

### 2. The bundle — verified (signed ad hoc, launched)

```sh
swift build -c release --product MyApp
BIN=$(swift build -c release --product MyApp --show-bin-path)
mkdir -p MyApp.app/Contents/MacOS MyApp.app/Contents/Resources
cp "$BIN/MyApp" MyApp.app/Contents/MacOS/
cp MyApp.icns MyApp.app/Contents/Resources/
# MetalUI's Metal shaders are a SwiftPM resource bundle (target MetalUIRender).
cp -R "$BIN/MetalUI_MetalUIRender.bundle" MyApp.app/Contents/Resources/
```

`MyApp.app/Contents/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>         <string>MyApp</string>
    <key>CFBundleIdentifier</key>         <string>com.example.MyApp</string>
    <key>CFBundleName</key>               <string>MyApp</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>CFBundleIconFile</key>           <string>MyApp</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>NSHighResolutionCapable</key>    <true/>
</dict>
</plist>
```

`CFBundleIconFile` names the `.icns` in `Contents/Resources`, with or without
its extension. Then:

```sh
plutil -lint MyApp.app/Contents/Info.plist
codesign --force --sign - MyApp.app          # ad hoc; a Developer ID for distribution
codesign --verify --strict --verbose=2 MyApp.app
```

**Verified** with `MetalUIDemo` as `MyApp` (Swift 6.4), built in release
under **both** build systems (`swift build -c release --product MetalUIDemo`,
and again with `--build-system native`), the resource bundle in
`Contents/Resources`: `plutil -lint` reads `OK`; the ad-hoc signature verifies
`valid on disk` and `satisfies its Designated Requirement` under `codesign
--verify --strict`; launched from `Contents/MacOS`, each app was still running
after six seconds (`AI-N`, record §70 §9). **The missing-bundle case** is
checked by the unit tests, not a launch: with no candidate holding the bundle,
the lookup throws `ShaderLibraryError.resourceMissing` naming every directory
it tried (`noResourceBundleThrowsResourceMissingNamingEveryPathTried`; in a
child process, `aMissingResourceBundleThrowsRatherThanTraps`). Before `AI-N`
the same bundle without its resource bundle exited at once (status 133,
SwiftPM's `unable to find bundle named MetalUI_MetalUIRender`). The binary links no non-system dynamic library
(`otool -L`). Whether Finder and the Dock show the `.icns` is a look, not
checked (the demo also sets `App.icon` at runtime, which would hide the
bundle's icon once running; a check of the bundle icon alone needs an app
that leaves `App.icon` at `[]`). Notarization (`notarytool`) — **unverified**.

**Where the resource bundle goes: `Contents/Resources`, on both build
systems** (`AI-N`). MetalUI finds `MetalUI_MetalUIRender.bundle` itself
(`ShaderLibrary.candidateDirectories`) rather than through SwiftPM's generated
`Bundle.module`, searching in order: in a debug build SwiftPM's
`PACKAGE_RESOURCE_BUNDLE_PATH` override; `Bundle.main.resourceURL` (the
`.app`'s `Contents/Resources`); the resources of the bundle holding MetalUI's
code; `Bundle.main.bundleURL` (a command-line tool's directory, an `.app`'s
root); the executable's directory; the directory holding MetalUI's code
bundle; and in a debug build this package's build directories. If none holds
it, `App.init` (through `Renderer.init`) **throws**
`ShaderLibraryError.resourceMissing`, whose description reads `MetalUI shader
resource missing from bundle: MetalUI_MetalUIRender.bundle (not found in any
of: <every directory tried, comma-separated>)` — it no longer traps. History:
before `AI-N` the generated accessor was the only lookup, and under
`--build-system native` it searched only the `.app`'s root (which `codesign
--sign` refuses: `unsealed contents present in the bundle root`) and the
absolute build directory, then called `fatalError`, so packaging had to use
the default build system.

## Linux: SDL in the image, and the library an app bundles (`VD-A`..`VD-E`)

`Backends/SDL/linux/Dockerfile` builds SDL 3.4.16 with the **X11 and Wayland video
drivers** (and libdecor for Wayland decorations), plus offscreen and dummy; the
image's `libSDL3.so.0` therefore runs on a real desktop. An app's tarball or
AppImage ships that one file (found with `ldconfig -p | grep libSDL3.so.0` in the image). The X11, Wayland and
libdecor libraries are **not** linked: SDL `dlopen`s them from the user's system,
so a machine without Wayland runs the X11 driver and the reverse. The build fails
if cmake cannot enable either driver, and `scripts/check-video-drivers.c` fails the
image build unless `SDL_GetVideoDriver` lists `x11`, `wayland`, `offscreen` and
`dummy`. The image sets `SDL_VIDEO_DRIVER=offscreen` so CI is headless; a packaged
app must not set it. Ship `THIRD-PARTY-NOTICES.md`'s SDL3 licence with it. Unverified: a real
Wayland compositor, a real X server with hardware GL (an Xvfb X11 session was
measured, `VD-C`).

## Linux: a `.desktop` file and the hicolor icon theme

Desktop shells find an application's icon through its **desktop entry**,
which names an icon by theme name; the icon itself lives in the hicolor
theme, one PNG per size.

### 1. The icons — verified (layout)

```sh
for n in 16 32 48 64 128 256 512; do
  mkdir -p hicolor/${n}x${n}/apps
  # any resizer; on macOS: sips -z $n $n, elsewhere e.g. ImageMagick's
  # `magick icon-1024.png -resize ${n}x${n}` (unverified)
  sips -z $n $n icon-1024.png --out hicolor/${n}x${n}/apps/com.example.MyApp.png
done
# per user:
mkdir -p ~/.local/share/icons && cp -r hicolor ~/.local/share/icons/
# system-wide (packages): /usr/share/icons/hicolor/<size>/apps/
```

**Verified**: the tree copied into `~/.local/share/icons/hicolor/<n>x<n>/apps/`
inside the container. `gtk-update-icon-cache ~/.local/share/icons/hicolor`
refreshes a GTK cache where one exists — **unverified** (not installed in the
container).

### 2. The desktop entry — verified (validator)

`com.example.MyApp.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=My App
Comment=A MetalUI application
Exec=/opt/myapp/MyApp
Icon=com.example.MyApp
Terminal=false
Categories=Utility;
StartupWMClass=MyApp
```

```sh
desktop-file-validate com.example.MyApp.desktop
desktop-file-install --dir="$HOME/.local/share/applications" com.example.MyApp.desktop
```

**Verified** in `swift:6.4-noble` with `apt-get install desktop-file-utils`:
`desktop-file-validate` prints nothing (valid) and `desktop-file-install`
installs it. `Icon=` is the theme name (no path, no extension).

### 3. Matching the running window to the entry

A shell associates a *running* window with its desktop entry by the window's
application id: the Wayland `app_id`, or the X11 `WM_CLASS` (which
`StartupWMClass` matches). SDL3's application id is its `SDL_APP_ID` hint
(`SDL_hints.h`: "used by desktop compositors to identify and group windows
together, as well as match applications with associated desktop settings and
icons"; it must be set before SDL initialises). MetalUI's SDL platform sets it
for you, before `SDL_Init` (ruling `AP-A`):

```swift
let platform = try SDLPlatform(options: .init(applicationID: "com.example.MyApp"))
```

Name the desktop file after that id (`com.example.MyApp.desktop`, and
`StartupWMClass=com.example.MyApp` when the file is named otherwise); GNOME
Shell on Wayland shows the entry's icon only when they match. An app that
launches through `SDLPlatform.launchingSingleInstance(id:forwarding:options:)`
gets its `id` as the application id unless `options.applicationID` is set
(`AP-C`), so the one reverse-DNS id serves both. With neither, nothing is set,
as before. An empty, whitespace-only or NUL-bearing value is ignored (`AP-D`).
The id applies to the whole process, not per window. macOS and Windows group by
the bundle and the AppUserModelID instead, so the option has no visible effect
there (`AP-E`).

**Override.** The `SDL_APP_ID` environment variable still wins over the code
(`AP-B`, probe `docs/probes/sdl-app-id-hint.c`), so a packager can correct an id
without a rebuild:

```sh
SDL_APP_ID=com.example.MyApp /opt/myapp/MyApp
```

**Verified:** the hint is set before `SDL_Init` (tests `SDLAppIDTests`) and the
environment overrides it (the probe, arm A2; no test exports the variable). **Unverified** — no Linux desktop session
was available: the shell's icon and grouping, and whether SDL's X11 backend
derives `WM_CLASS` from the hint; human checks AP1 and O3.

### 4. The SDL backend's shaders — lookup verified, a moved app unverified

An app built against the SDL backend (`MetalUISDL`, MetalUI's `SDL` trait,
`docs/getting-started.md`) loads its compiled shader stages at its first
window. It looks for them in **`MetalUISDLShaders` beside the executable
first**, then in the source tree it was built from
(`Backends/SDL/Shaders/compiled`, found by `#filePath` — valid only on the
build machine), and fails naming both directories when neither holds
`SOURCE.sha256` (ruling `PX-P`). So a shipped app carries a copy:

```sh
BIN=$(swift build -c release --product MyApp --show-bin-path)
mkdir -p dist
cp "$BIN/MyApp" dist/
cp -R .build/checkouts/MetalUI/Backends/SDL/Shaders/compiled dist/MetalUISDLShaders
```

(From a `--local` checkout, `<checkout>/Backends/SDL/Shaders/compiled`.)
**Verified**: the lookup order and the error — `SDLShaderDirectoryTests`
(`Backends/SDL`, macOS and the Linux CI image). **Unverified**: a moved
application opening its window (human check X1).

### 4a. An app's own SDL_GPU shaders — compile command, lookup and marker rules verified on macOS and the Linux image; shadercross built at its pin on macOS arm64 and Linux aarch64, not on Windows

An app that runs its own compute or graphics work through `MetalUISDLGPU` ships HLSL it compiled
itself, found the way section 4's are (ruling `GA-F`, after `PX-P`). **Build** with one command, over a
directory of `NAME.vert.hlsl`, `NAME.frag.hlsl` and `NAME.comp.hlsl` (the stage is the suffix, the entry
point `main`; read-only storage is `register(t…, space0)`, read-write storage `register(u…, space1)`,
uniforms `register(b…, space2)` for a compute stage). MetalUI exports the tool and a command plugin over
it from the root package (rulings `BS-B`, `BS-C`; no SDL trait is needed to compile a shader):

```sh
# as a command plugin of a package that depends on MetalUI (measured by path; see "Unmeasured")
swift package --allow-writing-to-package-directory compile-shaders --source shaders --out shaders/compiled
# or the tool, the certain fallback (--local checkout or .build/checkouts/MetalUI)
swift run --package-path .build/checkouts/MetalUI MetalUICompileShaders --source "$PWD/shaders" --out "$PWD/shaders/compiled"
```

Flags: `--source DIR` and `--out DIR` (both required; relative paths resolve against the package for the
plugin, against the working directory for the tool), `--shadercross PATH`, `--formats spv,msl,dxil,json`
(default all; `spv` is the intermediate and always built, so a Vulkan/Metal app can leave `dxil` out),
`--no-marker`. It writes `NAME.<stage>.spv`, `.msl`, `.dxil` and a reflection `.json` per source and
`SOURCE.sha256` (one `<sha256>  <file>` line per source, sorted bytewise; the python script this
replaces wrote the same bytes, pinned by `theMarkerEqualsTheCheckedInOneByteForByte`).

**shadercross** is found by `--shadercross`, then the `METALUI_SHADERCROSS` variable, then `PATH`
(`shadercross.exe` on Windows); a missing one is an error naming all three. A release-style archive keeps
its shared libraries in a `lib` directory beside `bin`, which the tool puts first on the loader path of
the child (Windows finds DLLs beside the executable). A command plugin writes only inside the package
(`--allow-writing-to-package-directory`, without it SwiftPM refuses), so `--out` belongs under the
package; the tool has no such limit.

**The pin.** MetalCreator, the first app to build shaders this way, pins `libsdl-org/SDL_shadercross` at
commit `1ff05bec573988a98ef9e0260b4da44f512b8367` (2026-09-03; upstream has no release or tag, checked
2026-10-21). MetalUI publishes no binary of it (ruling `BS-H`); build it from source:

```sh
git clone https://github.com/libsdl-org/SDL_shadercross.git && cd SDL_shadercross
git checkout 1ff05bec573988a98ef9e0260b4da44f512b8367
git submodule update --init --depth 1   # SPIRV-Cross, SPIRV-Headers, SPIRV-Tools, libsdl-org/DirectXShaderCompiler (branch 1.8.2502-SDL)
git -C external/DirectXShaderCompiler submodule update --init --depth 1 external/DirectX-Headers   # DXC's own nested submodule
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DSDLSHADERCROSS_VENDORED=ON -DSDLSHADERCROSS_INSTALL=ON
cmake --build build && cmake --install build --prefix "$HOME/shadercross"
export METALUI_SHADERCROSS="$HOME/shadercross/bin/shadercross"
```

Its dependencies, read from the pin's `.gitmodules` and `CMakeLists.txt`: **SDL3** (found as a package;
Homebrew `sdl3`, Debian/Ubuntu from source or `libsdl3-dev` where it exists, vcpkg or the SDL release
on Windows), **SPIRV-Cross** (shared `spirv-cross-c-shared` by default), **SPIRV-Headers** and
**SPIRV-Tools** (submodules), and **DirectXShaderCompiler**, a libsdl-org fork on branch
`1.8.2502-SDL`, an LLVM-based build (`dxcompiler` and `dxildll`, 1303 ninja steps, the long step:
**measured 8 min 30 s of wall clock at `-j8` on a loaded 10-core Mac**, 2026-10-21). `-DSDLSHADERCROSS_DXC=OFF`
skips building it, but the configure step still wants the submodule checked out, and the CLI then
**cannot compile HLSL at all** (the HLSL to SPIR-V step is DXC's), only convert SPIR-V to MSL and
JSON (measured: it reproduced the checked-in `.msl` and `.json` byte for byte).
Per platform:

- **macOS (arm64 or x86_64), Linux x86_64, Windows x64**: the recipe above; DXC builds natively and
  shadercross can write DXIL (DXIL needs `dxil.dll`/`libdxil` beside `dxcompiler`, which the install step
  places in `bin`/`lib`). On Windows use the Visual Studio generator or Ninja from a developer prompt and
  put the install's `bin` (with `dxcompiler.dll`, `dxil.dll`, `SDL3.dll`) in `METALUI_SHADERCROSS`'s directory or on `PATH`.
- **Linux aarch64**: libsdl-org ships no prebuilt DXC for it (its binaries are Linux x86_64 and Windows
  only), but **a source build of the fork works natively** (measured in the `metalui-portable` image,
  Ubuntu 24.04 aarch64 under OrbStack, 2026-10-21): configure with **clang** (`-DCMAKE_C_COMPILER=clang
  -DCMAKE_CXX_COMPILER=clang++`, the Swift toolchain's; the default `cc` is gcc and DXC's flags
  `-fcolor-diagnostics` make it fail at the first file), SDL3 on the default paths, the four submodules as
  above, plus DXC's nested `external/DirectX-Headers` (without it a fresh shallow checkout fails inside the fork with
  `d3d12shader.h file not found`; reported from MetalCreator's Linux aarch64 Docker stage, 2026-10-22, not re-measured here); **6 min 45 s at `-j8`**. The installed `bin/shadercross` with `lib/libdxcompiler.so`, `libdxil.so`
  beside it then compiled `Backends/SDL/Tests/AppShaders` through `MetalUICompileShaders` to **41 files
  byte-identical to the checked-in ones, DXIL included**. So neither emulation nor SPIR-V-only is needed
  there; they remain fallbacks. `--formats` can still leave `dxil` out of a Vulkan or Metal app's build
  (the derivation is skipped; HLSL to SPIR-V always goes through DXC).
  Compiling on another machine and shipping the blobs is the plain alternative.

**Check in the compiled directory, or not.** A directory the tool just wrote is never stale, so
`SDLGPUShaderLibrary(directory:)` accepts one with no `SOURCE.sha256` as long as it holds a
`NAME.<vert|frag|comp>.json` reflection file (ruling `BS-E`); a build product kept out of the repository
needs no marker. A directory **with** a marker can be checked against its sources:
`SDLGPUShaderLibrary(directory:verifyingSources:)` throws a named error for a changed source, a source with
no line and a line with no source, and compares nothing when there is no marker. A checked-in directory
is therefore still protected: a test can recompute each source's SHA-256 against `SOURCE.sha256` with no
shadercross (the repository's own kernel does this, `aCheckedInAppShaderBlobMatchesItsSource`).

**Two Windows rules** (ruling `GA-Q`, found by Windows CI): **a fragment stage must read every vertex output it declares as an input** — the cross-compiled stage numbers only the inputs it reads, and D3D12 links stages by register, so a fragment that skips `TEXCOORD0` puts `TEXCOORD1` at the wrong register and pipeline creation fails with `E_INVALIDARG` (`0x80070057`); and **mark the shader files `eol=lf` (`*.dxil`, `*.spv` binary) in `.gitattributes`**, or a CRLF checkout changes the sources' hashes.
**Ship** the directory as `MetalUIAppShaders` beside the executable:

```sh
cp -R shaders/compiled dist/MetalUIAppShaders
```

`SDLGPUShaderLibrary.locate(directoryName:sourceTree:)` looks in `MetalUIAppShaders` beside the
executable first, then in the `sourceTree` URL the app passes (a source build; the library reads no
`#filePath` for the app) and fails naming both directories when neither holds a `SOURCE.sha256` or a
reflection file.

**On plain `swift build` (`CompileShadersOnBuild`, rulings `BT-A`...`BT-M`, item `BS-D`).** An app target opts in and keeps its
HLSL in `Sources/App/Shaders/NAME.<vert|frag|comp>.hlsl`, optionally with checked-in blobs in `Sources/App/Shaders/compiled/`:

```text
.executableTarget(name: "App",
                  dependencies: [.product(name: "MetalUISDLGPU", package: "MetalUI")],
                  plugins: [.plugin(name: "CompileShadersOnBuild", package: "MetalUI")])
let shaders = try SDLGPUShaderLibrary.locate(resourceBundle: .module)
```

| shadercross (`METALUI_SHADERCROSS`, else `PATH`) | `Shaders/compiled/` | Result |
|---|---|---|
| found | any | compiles all four formats and the marker into the target's resource bundle (`MetalUIAppShaders`); warns when a checked-in marker is stale |
| variable names a missing file | any | the build fails |
| not found | marker matches, each source has `.json` and `.spv` | copies those blobs and the marker |
| not found | stale or missing marker, a missing blob, no directory | the build fails naming the problems, the pin and both fixes |

**Headers in `Shaders/` (`BT-O`...`BT-T`, item XP-G32).** A stage source may `#include "common.hlsli"` from its own directory. Every regular
file below `Shaders/` ending `.hlsli`, or ending `.hlsl` but not a top-level `NAME.<vert|frag|comp>.hlsl`, **except the `compiled/` subtree**, is an
*include source*: the plugin lists it among the build command's inputs (so editing a header reruns the command) and the tool writes
`INCLUDES.sha256` beside `SOURCE.sha256`, the same `<sha256>  <file>` lines over the `/`-separated relative paths, sorted bytewise, **only when
include sources exist** (a package with none writes exactly what it wrote before, and a stale `INCLUDES.sha256` is removed). `SOURCE.sha256` still
covers stage sources only. Without shadercross the copy path now also requires `Shaders/compiled/INCLUDES.sha256` to match when include
sources exist (a changed, new or vanished header is a named problem), and an `INCLUDES.sha256` checked in while there are none is a named
orphan; with shadercross a mismatch is the usual stale warning. `SDLGPUShaderLibrary(directory:verifyingSources:)` checks an `INCLUDES.sha256`
it finds in the directory the same way (and compares no headers when there is none). Commit `compiled/` again after a header edit
(`compile-shaders`), as after a stage edit.

To apply the plugin only where the toolchain exists, gate it in the consumer's `Package.swift` with a host condition:

```text
#if os(Linux) || os(Windows)
let shaderPlugins: [Target.PluginUsage] = [.plugin(name: "CompileShadersOnBuild", package: "MetalUI")]
#else
let shaderPlugins: [Target.PluginUsage] = []
#endif
```

`#if os(...)` in a manifest is evaluated **on the host that builds the manifest**, not on the build's target: a cross-compile from macOS to
Linux or Windows skips the plugin, and a macOS host never applies it.

No published shadercross is assumed (`BS-H`): install one at the pin of 4a, or run `compile-shaders` where one is installed and commit
`Shaders/compiled`. A shadercross replaced at the same path does not rerun the step (`swift package clean`). `locate(resourceBundle:)` looks
beside the executable first, then in the bundle (evaluated only then, since `Bundle.module` traps when its bundle is missing), then in `sourceTree`;
to ship, copy `MetalUIAppShaders` beside the executable or ship the resource bundle as `MetalUI_MetalUIRender.bundle` is shipped. A target
applying the plugin with no source gets a warning and no command. Windows is unmeasured (human check `BT1`).

**Verified** (macOS, 2026-10-28): a fixture package depending on this checkout by path, on both build systems, with a stub and the real shadercross
at the pin, with and without one on the path, a stale source refused, an unchanged rebuild running nothing
(`theBuildToolPluginCompilesVerifiesAndRefusesOnAFixturePackage`, env-gated). **Unverified:** Windows, a dependency by URL, a shipped `.app` (`BT1`...`BT3`).

**Verified** (macOS, 2026-10-21): the plugin from a fixture package depending on this checkout **by
path**, refused without `--allow-writing-to-package-directory` and writing blobs and the marker with it
(`theCompileShadersPluginRunsOnAFixturePackage`, with a stub shadercross); the argument vectors, the
lookup order, the loader path and the marker bytes (`MetalUIShaderCompileTests`); the library rules
(`SDLGPUShaderBuildProductTests`, `Backends/SDL`, macOS and the Linux image); the order and the error,
`theShaderLibraryLooksBesideTheExecutableThenTheSourceTree`. **Verified with a real shadercross at the pin** (macOS arm64 and Linux aarch64, the builds above): `MetalUICompileShaders` over
`Backends/SDL/Tests/AppShaders` wrote 41 files byte-identical to the checked-in `compiled` directory (SPIR-V,
MSL, DXIL, reflection JSON, marker), `anEnvGatedRunCompilesAFixture` with `METALUI_SHADERCROSS`.
**Unverified**: Linux x86_64 and Windows builds of it (human checks BS1, BS4),
a dependency **by URL** reaching the plugin (BS3), Windows lookup and DLLs (BS4), a
moved shipped app finding its directory (GA3).

### 4b. Compiling HLSL compute shaders in the running app (optional) — Linux aarch64 and macOS measured, Windows unmeasured

`SDLGPUShaderCompiler` (`MetalUISDLGPU`, item XP-G25, rulings `RC-B`...`RC-V`, record 151) turns HLSL text into a compute
pipeline in the running process, for an app that generates its kernels (MetalCreator's implicit solids). It needs the same
shadercross as section 4a, **as shared libraries next to the app**, and loads them with `SDL_LoadObject` at the first call:
MetalUI links none of it, an app that never compiles ships none of it, and a missing library is a thrown
`compilerUnavailable` naming every path tried, never a trap. MetalUI publishes no binary of any of it (`BS-H`): build it from
source with the recipe of 4a (pin `1ff05bec573988a98ef9e0260b4da44f512b8367`), then **ship these files, all in one directory**:

| File (Linux / macOS / Windows) | Measured size (aarch64 Linux / arm64 macOS) | Licence | Needed for |
|---|---|---|---|
| `libSDL3_shadercross.so.0` (+ `.so`) / `libSDL3_shadercross.dylib` / `SDL3_shadercross.dll` | 74 KB / 72 KB | zlib | the API itself |
| `libdxcompiler.so` / `.dylib` / `dxcompiler.dll` | 33.3 MB / 27.9 MB | LLVM Release License (NCSA) | HLSL to SPIR-V and to DXIL (DXC) |
| `libspirv-cross-c-shared.so.0` / `.dylib` / `spirv-cross-c-shared.dll` | 4.0 MB / 3.6 MB | Apache-2.0 | reflection and SPIR-V to MSL |
| `libdxil.so` / `libdxil.dylib` / `dxil.dll` | 2.7 MB / 2.0 MB | LLVM Release License (NCSA) | signing DXIL for D3D12 (see below) |

About **39 MB** on Linux aarch64 and **32 MB** on macOS in all. The licences are listed in `THIRD-PARTY-NOTICES.md` ("Optional
run-time shader compiler"); the DXC fork's licence is not Apache-2.0 and its `LICENSE.TXT` and `ThirdPartyNotices.txt` travel with the binary.

**Placement.** The lookup (`RuntimeLibraryLocator`, `RC-C`; a pure function with pins on every platform) tries, in order: the explicit
`libraryPath:`, `METALUI_SHADERCROSS_LIB` (the library file, or a directory holding it), the executable's directory, its `lib` subdirectory (`<exe>/lib`, `SX-B`: RUNPATH `$ORIGIN/lib` layouts), its `../lib`, the
`lib` beside the `bin` of `METALUI_SHADERCROSS` (the install layout of 4a), then the plain library name on the loader path. **An explicit
path or variable that names a missing file is an error, never a fall-through.** So: a **Linux tarball** puts the four files in `lib/` beside
`bin/` (found as `../lib`), or in `lib/` beside the executable itself (found as `<exe>/lib`); an **AppImage** puts them in `usr/lib` beside `usr/bin`; a **Windows zip** puts them beside the `.exe`
(before loading, the library's directory is added to the DLL search path so `dxcompiler.dll` and `dxil.dll` resolve; compiled by CI only);
a **macOS `.app`** needs `METALUI_SHADERCROSS_LIB` or `libraryPath:` pointed at `Contents/Frameworks` (not found by default there), and
**library validation or the hardened runtime may refuse an unsigned dylib** (human check RC5; sign every file with the app's identity).

**The install has no rpath for the library itself** (measured on both, `RC-N`, `RC-U`): `libSDL3_shadercross` names `libspirv-cross-c-shared`
and `libdxcompiler` as `@rpath`/bare-SONAME dependents and carries no `LC_RPATH`/`RUNPATH`, so loading it by full path alone fails
(macOS: `Library not loaded: @rpath/libspirv-cross-c-shared.0.dylib`; glibc: `libspirv-cross-c-shared.so.0: cannot open shared object file`).
MetalUI therefore **preloads `dxcompiler`, `spirv-cross` and `dxil` by full path from the library's directory first**
(`RuntimeLibraryLocator.preloadSet`; `dxcompiler` and `spirv-cross` required and named in the error when missing, `dxil` optional); an
already-loaded image satisfies a dependent of the same install name (dyld) or SONAME (glibc, measured in the Linux image: preloading
by the full path of `libspirv-cross-c-shared.so.0` and `libdxcompiler.so`, then the library, works and every probe arm passes). **An app never
sets `LD_LIBRARY_PATH` or `DYLD_LIBRARY_PATH`** (SIP strips the second from a hardened process). The unversioned `.so`/`.dylib` symlinks may
be left out when the full name is shipped.

**Is `libdxil` needed?** **Not on Linux aarch64 or macOS** to produce DXIL: the DXIL container's digest was non-zero and the bytes identical
(3,368 bytes) with `libdxil` absent and present, on both (probe arm E). SPIR-V and MSL, the formats Vulkan and Metal take, never use it. Whether
Windows' D3D12 accepts DXIL compiled without `dxil.dll` beside `dxcompiler.dll` is **unmeasured** (human check RC1), so the Windows zip ships it. The pin's
`libdxcompiler.so` carries a `RUNPATH` of `$ORIGIN/../lib` (it would find a `libdxil` there), and on macOS `@executable_path/../lib`.

**Microsoft's DXC instead of the fork.** An app may ship Microsoft's prebuilt DXC release (MetalCreator uses v1.9.2602 on Windows) as `dxcompiler.dll` and
`dxil.dll` instead of the libsdl-org fork. Those two files are then Microsoft's and come under **Microsoft's own licence files**, taken from that release
archive and shipped by the app (`THIRD-PARTY-NOTICES.md`); this repository holds none of them. **Compatibility is unmeasured**: shadercross at the pin was
built against the fork and was **not** run against Microsoft's DXC here. What could differ is the `IDxcCompiler3` interface and flags it was built for,
and `dxil.dll` signing (Microsoft's release is believed to ship a signing `dxil.dll`; unmeasured). Human check `SX1`.

**Without the `SDL` trait (the macOS default build; item XP-G27, rulings `HX-A`...`HX-K`, record 160).** Add the product
`MetalUIShaderRuntime` and call `RuntimeShaderCompiler` (`shared(libraryPath:)`, `compileCompute(hlsl:entryPoint:defines:includeDirectory:target:)`,
`selfTest(target:)`): the same loader as `SDLGPUShaderCompiler` (one implementation, one load per process, `HX-C`, `HX-E`), and the app **need not link SDL3**.
Ship the four files above **plus `libSDL3.0.dylib`** (Homebrew's 3.4.18 arm64 is 2,520,816 bytes, zlib; about 35 MB in all) in the same directory
(`Contents/Frameworks`): when the process holds no SDL3, the loader preloads the SDL3 file it finds beside shadercross first, by full path, `RTLD_LOCAL`, and reads
`SDL_GetError`, `SDL_ClearError` and `SDL_free` through shadercross's own handle, so they are always the instance shadercross calls (`HX-D`). When the process
already holds SDL3 (the `SDL` trait, an app linking SDL3) nothing is preloaded: a second SDL3 duplicates SDL's Objective-C classes (measured, `HX-B` arm T).
A Homebrew-built shadercross names SDL3 by absolute path (`/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib`) and its other dependents by `@rpath` with no `LC_RPATH`;
the preload by full path satisfies all of them, so **no `install_name_tool` step is needed** (measured, `HX-B` arms R and P). Code signing: sign every dylib with
the app's team (`codesign --deep` alone is not enough for a hardened runtime with library validation), or add `com.apple.security.cs.disable-library-validation`;
**unmeasured**, human check `HX1`. Windows (`SDL3.dll` read through `GetModuleHandleW` after a `SetDllDirectoryW` load) is compiled by CI only, human check `HX2`;
Linux without a system SDL3 is human check `HX3`.

**Self test.** `SDLGPUShaderCompiler.selfTest(for:)` (lane B, `RC-J`) is the call for an app's `--self-test`: it loads the compiler, compiles a
four-line kernel, compiles a broken one and requires DXC's diagnostics, and with a device runs one dispatch and reads it back; it
**throws `compilerUnavailable`** where the library is missing, so a packaging mistake fails the check naming the paths tried.

**Speed** (`docs/probes/runtime-compile-measure.sh`, dated; wall clock, **never pinned**: a pin counts work). Generated kernels of about 200,
1000 and 2000 lines (every line a float expression with a call, a `sqrt`, an `abs`, a `floor`), median of 3, 2026-10-22:

| Machine | Lines | HLSL to SPIR-V | SPIR-V to MSL | HLSL to DXIL |
|---|---|---|---|---|
| Linux aarch64 image (`metalui-portable`, 10 cores, load 0.16, idle) | 200 / 1000 / 2000 | 0.056 / 0.564 / 2.658 s | 0.005 / 0.021 / 0.057 s | 0.085 / 0.679 / 2.904 s |
| macOS arm64 (10 cores, **load average 265 to 470 from other sessions**: noisy, an upper bound) | 200 / 1000 / 2000 | 0.081 / 0.441 / 1.588 s | 0.004 / 0.018 / 0.063 s | 0.121 / 0.567 / 2.546 s |

The first compile in a process costs nothing beyond itself (0.056 s Linux, 0.081 s macOS for 200 lines, the library load 7 ms and 146 ms loaded).
**DXC's HLSL to SPIR-V is more than 95 % of a Metal-route compile and grows faster than linearly** (2000 lines costs about 5 times the 1000-line
kernel); the Metal route adds SPIR-V to MSL, under 0.07 s. Compile on a worker thread, never the main actor, and cache by source hash: the app
owns the cache (`RC-M`) and loads a cached blob through `SDLGPUShaderBlob`'s bytes initializer.

**Unverified:** `<exe>/lib` in a real tarball (human check SX2), Microsoft's DXC with shadercross at the pin (unmeasured, human check SX1), Windows (compile and load, `dxil.dll`'s need, the DLL search path; human check RC1), Linux x86_64 (the build is the same recipe), an AppImage and a tarball
finding `../lib` (RC2), `--self-test` without the library (RC3), a macOS `.app` with the files in `Contents/Frameworks` (RC5).

## Windows: an `.ico` embedded as a resource

Explorer, the Start menu and a shortcut show the icon embedded in the `.exe`
(the first `ICON` group resource); `SDL_SetWindowIcon` (`App.icon`) sets only
the running window's title-bar and taskbar icon.

### 1. The `.ico` — verified (on macOS)

An `.ico` with PNG entries (Windows Vista and later), from square PNGs of 256
px or less — no external tool needed:

```python
#!/usr/bin/env python3
# make-ico.py out.ico 16.png 24.png 32.png 48.png 64.png 256.png
import struct, sys
out, pngs = sys.argv[1], sys.argv[2:]
images = []
for path in pngs:
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG"
    width, height = struct.unpack(">II", data[16:24])
    assert width == height <= 256, f"{path} is {width}x{height}"
    images.append((width, data))
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries, blobs = b"", b""
for side, data in images:
    entries += struct.pack("<BBBBHHII", side % 256, side % 256, 0, 0, 1, 32, len(data), offset)
    blobs += data
    offset += len(data)
open(out, "wb").write(header + entries + blobs)
```

**Verified**: from six `sips`-resized PNGs, `file MyApp.ico` reads `MS
Windows icon resource - 6 icons, 16x16 with PNG image data, …` and `sips`
opens it (256 px). ImageMagick's
`magick icon-1024.png -define icon:auto-resize=256,64,48,32,24,16 MyApp.ico`
does the same — **unverified** (not installed).

### 2. The resource script and the link — partly verified

`MyApp.rc`:

```
1 ICON "MyApp.ico"
```

Compile it to a `.res` with the Windows SDK's `rc.exe` (installed with the
Visual Studio components the Swift toolchain on Windows requires) or LLVM's
`llvm-rc`:

```bat
rc.exe /fo MyApp.res MyApp.rc
:: or
llvm-rc /FO MyApp.res MyApp.rc
```

then hand the `.res` to the linker, which accepts it as an input file:

```bat
swift build -c release --product MyApp -Xlinker MyApp.res
```

**Verified**: only the compile, with `llvm-rc` (LLVM 18, `apt-get install
llvm` in `swift:6.4-noble`): it writes `MyApp.res`, and `llvm-readobj
--coff-resources` lists `ICON (ID 3)`, name 1. **Unverified**: `rc.exe`, the
`-Xlinker MyApp.res` link (whether `lld-link`/`link.exe` as driven by
`swift build` takes the path as given — it may need to be absolute, or to go
in a `linkerSettings: [.unsafeFlags([...])]` of the executable target, which
a package depended on by others cannot use), and the icon Explorer then
shows. Human check O4 covers the running window's icon only.

### 3. The SDL backend's runtime files — unverified

Beside `MyApp.exe`: `SDL3.dll` (from SDL3's VC package, `lib\x64`) and the
compiled shaders as `MetalUISDLShaders`, copied from
`.build\checkouts\MetalUI\Backends\SDL\Shaders\compiled` exactly as on Linux
(section 4 above, ruling `PX-P`). AccessKit is a static library and ships
inside the executable. No command here was run on Windows (human check X4).

### 4. Release builds and the asserts compiler — verified on macOS with an asserts snapshot

Windows CI installs Swift **6.4.0+Asserts**: a compiler built with assertions,
which runs SIL verifiers that the macOS and Linux release compilers skip. One of
them, `verifyLexicalLowering` in `TypeLowering.cpp` ("Found non-trivial lexical
leaf in non-trivial non-lexical type?!"), crashed a release build of the SMK
configurator on Windows ARM64 (gap MG-27) and MetalUI's own looks demo in CI
(`LK-X`), while emitting a `Component`'s `prepaintGroup` witness. The shape: a
`Component` whose content holds — beside other content, or as one branch of an
`if`/`else` or a `switch` — a nested `Component` whose own content is a loop
(`ForEach` or `for`). Nothing on macOS or Linux reports it.

**Fixed in MetalUI** (ruling `SG-E`): a `Component`'s prepaint record is one
heap box (`ComponentPrepaint`), so an enclosing record no longer holds the
loop's `Array` through an opaque type. With the box, both shapes compile under
the asserts snapshot in debug and release; MetalUI's own demo content and the
Windows-portable targets build under it too. Nothing to change in an app.

**The compiler bug remains** for code with its own protocols of the same shape
(a protocol extension's witness returning an associated type of an opaque
`some P` content, whose underlying record holds an `Array`, `String`, `Set`,
`Dictionary` or `Substring`) — the reduction and the upstream report are in
`SG-E`. On a MetalUI checkout *before* the box, or for such code, the
workaround is `LK-X`'s: make the looping member a `@MainActor` function
returning `some Element`/`some ElementGroup` instead of a nested `Component`
(it gives up the member's own identity level and `@State`).
`-Xswiftc -Xfrontend -Xswiftc -enable-lexical-lifetimes=false` does **not**
avoid it (MG-27, and measured on the reduction); `-Xswiftc -Xllvm -Xswiftc
-sil-verify-none` does on the reduction (it disables the verifier; measured on
macOS only, not on Windows).

**Checking with an asserts toolchain on macOS.** Install a swift.org
development snapshot (its compiler is built with assertions) and select it by
bundle identifier:

```sh
TOOLCHAINS=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" \
  ~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a.xctoolchain/Info.plist) \
  swift build -c release --scratch-path .build-asserts
```

(A separate `--scratch-path` keeps the everyday build directory.) MetalUI's
guard does this against a scratch package:
`METALUI_RUN_ASSERTS_COMPILER_TEST=1 swift test --filter
theComponentSwitchShapeAgainstAnAssertsCompiler` (toolchain path in
`METALUI_ASSERTS_TOOLCHAIN`). **Verified** on macOS 27 with that snapshot
(Swift 6.5-dev). **Unverified** on Windows: the guard finds `swift.exe` on `PATH` there and
launches it directly (it compiles, but has never run), and the UTM VM did not
answer on 2026-10-10 (human check SG6).

## Documents and URLs an application opens (app shell)

**Build-side too** (ruling `AS-G` items 5–6, `AS-M`,
`docs/superpowers/2026-10-08-app-shell-decisions.md`). At runtime a MetalUI
app hears an open through `.onOpenURL { url in }` in a window's tree (or
`App.onOpenURL` when no window has one); which files and URL schemes the
system sends it is declared here, outside the program.

### macOS: document types and URL schemes in `Info.plist` — lint verified

Add to the bundle's `Info.plist` (section 2 above) — an exported type for a
new extension, a document type naming it, and a URL scheme:

```xml
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>         <string>MyApp Document</string>
            <key>CFBundleTypeRole</key>         <string>Editor</string>
            <key>LSHandlerRank</key>            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array><string>com.example.myapp.document</string></array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>         <string>com.example.myapp.document</string>
            <key>UTTypeDescription</key>        <string>MyApp Document</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.data</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>myapp</string></array>
            </dict>
        </dict>
    </array>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>          <string>com.example.MyApp</string>
            <key>CFBundleURLSchemes</key>
            <array><string>myapp</string></array>
        </dict>
    </array>
```

**Verified** (2026-10-09): `plutil -lint` reads `OK` on these keys in a
property list. `AppKitPlatform.run()` installs MetalUI's application delegate,
whose `application(_:open:)` receives Finder's double-click, `open -a MyApp
file.myapp`, a drop on the Dock icon, Open Recent and `myapp://…` links, and
passes them to `.onOpenURL` — a launch-time open arrives during `run()`,
before `applicationDidFinishLaunching` (probe
`appkit-launch-arguments-open.swift` `A6`), so **open the window before
`run()`** or set `App.onOpenURL` there (`AS-Q`: nothing is queued for a
receiver that comes later). **No `NSDocumentClass` is needed** (probe
`appkit-open-without-document-class.swift`, 2026-10-09): with a document type
of exactly this shape and no `NSDocumentClass`, `open -a` delivers the file to
`application(_:open:)` with no alert, at launch and with the app already
running (`W0`, `W2`); AppKit's "cannot open files in this format" alert comes
up only for a delegate that does not implement `application(_:open:)` (`W1`,
the separating arm) — so do not replace `NSApp.delegate` after `run()`
installs MetalUI's. **Unverified**: a Finder double-click, a Dock drop and Open
Recent from a packaged MetalUI app — human check AS9.

### Launch arguments — the recipe (every platform)

**MetalUI reads no `CommandLine.arguments`** (`AS-G` item 6): a test
runner's and SwiftPM's flags are there too, and only the app knows which
arguments are documents. AppKit delivers none of them by itself (probe `A1`,
`A3`, `A5`), so on macOS too the app delivers them, each once, after opening
its window:

```swift
let window = try app.openWindow(title: "MyApp", size: size) { MyAppRoot() }
app.open(CommandLine.arguments.dropFirst()
    .filter { FileManager.default.fileExists(atPath: $0) }
    .map { URL(fileURLWithPath: $0) })
app.run()
```

This is how `swift run MyApp file.myapp` opens a file, and how Linux and
Windows file associations (below) reach the app. The app shell demo uses it
(`appShellDemoLaunchURLs(_:)`, `METALUI_APP_SHELL_DEMO=1`). A second
instance forwarding its arguments to the first (single-instance apps on Linux
and Windows) is the next recipe.

### One instance on Linux and Windows — forwarding a second launch (SDL, item S7)

A file manager runs `Exec=MyApp %F` once per open, so on Linux and Windows a
second document starts a second process. On macOS a bundled app needs nothing
(LaunchServices delivers the open to the running one, `application(_:open:)`).
On SDL the app opts in with one call **before any window exists**, keyed by an
application identifier:

```swift
let documents = CommandLine.arguments.dropFirst().filter { FileManager.default.fileExists(atPath: $0) }
guard let platform = try SDLPlatform.launchingSingleInstance(id: "com.example.MyApp",
                                                             forwarding: Array(documents)) else { exit(0) }
let app = try App(platform: platform, textSystem: …)   // then openWindow, app.open(documents), app.run() as above
```

The first launch becomes the primary and keeps the role while its platform lives.
A later launch hands its arguments (relative paths made absolute against its own
working directory; URLs untouched) to the primary and gets `nil`: it exits 0. The
primary delivers them as one `onOpenURLs` batch per launch (so `.onOpenURL` and
`App.open(_:)`'s routing apply, `AS-G`; with no handler yet the batch is parked, as
a window-0 drop's is) and raises its key window, else its first. The primary's own
arguments stay `app.open(documents)`.

- **API:** `SingleInstance.claim(id:forwarding:configuration:)` returns `.primary(role)`,
  `.forwarded` or `.unavailable(failure)`; put a `.primary` in
  `SDLPlatform.Options.singleInstance`. `launchingSingleInstance` does both. An
  `.unavailable` claim (a wedged primary, an unusable directory) runs the launch as
  an independent instance rather than lose the document (`SN-F`).
- **Transport (per user, never across users):** Linux and macOS use `flock` on
  `msui-<hash>.lock` to elect and a Unix socket `msui-<hash>.sock` to carry, in
  `$XDG_RUNTIME_DIR` (else the user's temporary directory on macOS, else
  `/tmp/metalui-<uid>`), which must be a real directory owned by the user with no
  group or other access; the socket is 0600 and a peer of another user is dropped
  unread. A crashed primary leaves a socket file and no lock, which the next launch
  replaces. Windows uses a named semaphore and pipe scoped to the user's session, the
  pipe created `FILE_FLAG_FIRST_PIPE_INSTANCE` with a descriptor for the user only.
- **Limits:** a message is `MSI1`, a length and at most 1024 strings of 1 to 32768
  UTF-8 bytes (no NUL), 1 MiB in all; at most 64 are pending; a stalled sender is cut
  off after the read timeout (2 s). Nothing received is run, expanded or opened.
- **A claim blocks** up to the connect timeout plus the read timeout (about four
  seconds worst case) when the primary is wedged; it never blocks when there is none.
- **Raising** is best effort: X11 usually honours it; Windows grants the foreground
  only to a process that recently had input, so the primary's taskbar entry flashes
  instead; Wayland needs an activation token this version does not forward (`SN-L`).
  `Configuration.raisesWindow = false` turns it off.
- **A `.desktop` file** keeps `Exec=/opt/myapp/MyApp %F`; no D-Bus activation is built.

### Linux: `MimeType=` and `%F` in the desktop entry — unverified

Extend the desktop entry of section 2 above so the file manager offers the
app for a MIME type and passes the files as arguments:

```ini
Exec=/opt/myapp/MyApp %F
MimeType=application/x-myapp-document;
```

A new MIME type also needs a shared-mime-info package
(`/usr/share/mime/packages/myapp.xml` mapping `*.myapp`, then
`update-mime-database`). Not validated: `desktop-file-validate` was not run
on these lines. SDL also reports a file dropped on the application itself (no
window) — SDL's Cocoa backend does on macOS — to `.onOpenURL`; a file dropped
on a window stays a drag and drop (`DN-M`).

### Windows: a file association — unverified

Register a ProgID whose `shell\open\command` is `"C:\Program
Files\MyApp\MyApp.exe" "%1"` and point the extension at it (an installer's
job: WiX, Inno Setup or MSIX). The path arrives as an argument and the recipe
above delivers it. No command here was run on Windows (human check AS10).

## A smoke test of the built app in CI

A Linux or Windows job with no display can open the real SDL window and run a
`.task` in its first frame with `SDLPlatform(options: .headless)`; the recipe is
in [`testing.md`](testing.md#a-ci-smoke-test-of-the-real-window).
