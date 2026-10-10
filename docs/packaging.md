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

### 3. Matching the running window to the entry — unverified

A shell associates a *running* window with its desktop entry by the window's
application id: the Wayland `app_id`, or the X11 `WM_CLASS` (which
`StartupWMClass` matches). SDL3's application id is its `SDL_APP_ID` hint
(`SDL_hints.h`: "used by desktop compositors to identify and group windows
together, as well as match applications with associated desktop settings and
icons"; set before SDL initialises), which an environment variable of the
same name sets, as SDL hints generally can:

```sh
SDL_APP_ID=com.example.MyApp /opt/myapp/MyApp
```

Name the desktop file after that id (`com.example.MyApp.desktop`); GNOME
Shell on Wayland shows the entry's icon only when they match. MetalUI's SDL
platform does not set an application id itself. **Unverified** — no Linux
desktop session was available, and whether SDL's X11 backend also derives
`WM_CLASS` from the hint was not checked; human check O3 covers the running
icon.

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
and Windows) is not built (owner none).

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
