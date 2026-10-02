// `metalui new`: a new application package that depends on MetalUI (ruling
// SC-A, `docs/superpowers/2026-10-01-scaffold-decisions.md`). Everything here
// is `package`: the scaffolder is a tool, not framework API, so it adds no
// public declaration to the inventory. Foundation only — it is declared on
// every platform (PC-A) and runs where `swift` does.
import Foundation

/// Which commit of a git dependency the generated manifest asks for (SC-I).
package enum GitReference: Equatable, Sendable {
    /// `.package(url:, branch:)`: follows the branch; `swift package update`
    /// moves it to the branch's newest commit, breaking changes included.
    case branch(String)
    /// `.package(url:, revision:)`: one commit, until the user changes it.
    case revision(String)
}

/// Where the generated package finds MetalUI.
package enum MetalUISource: Equatable, Sendable {
    /// A git URL and the commit or branch to use — what an application outside
    /// this repository normally uses.
    case remote(url: String, reference: GitReference)
    /// A checkout on disk, as an absolute path — for framework development,
    /// and required by `crossPlatform` (SC-C).
    case local(path: String)

    /// The repository's own URL.
    package static let defaultURL = "https://github.com/mburger89/MetalUI.git"
    /// The repository's default branch: where a pin is taken from, and what an
    /// unpinned package follows (SC-I).
    package static let defaultBranch = "master"
    /// The repository, unpinned: what `metalui new` falls back to when it finds
    /// no commit to pin (SC-I).
    package static let defaultRemote = MetalUISource.remote(url: defaultURL, reference: .branch(defaultBranch))
}

/// What `metalui new` was asked for.
package struct ScaffoldOptions: Equatable, Sendable {
    /// The package, product, target and executable name.
    package var name: String
    /// Reverse-DNS; `com.example.<name>` unless given.
    package var bundleIdentifier: String
    package var source: MetalUISource
    /// Adds `Backends/SDL` on Linux and Windows (SC-C).
    package var crossPlatform: Bool

    package init(name: String, bundleIdentifier: String? = nil,
                 source: MetalUISource = .defaultRemote, crossPlatform: Bool = false) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier ?? "com.example.\(name)"
        self.source = source
        self.crossPlatform = crossPlatform
    }
}

/// One generated file, its path relative to the package root.
package struct ScaffoldFile: Equatable, Sendable {
    package var path: String
    package var contents: String
    /// Written with the owner's execute bit (the packaging script).
    package var executable: Bool

    package init(path: String, contents: String, executable: Bool = false) {
        self.path = path
        self.contents = contents
        self.executable = executable
    }
}

package enum ScaffoldError: Error, Equatable, CustomStringConvertible {
    case invalidName(String, reason: String)
    case invalidBundleIdentifier(String)
    case crossPlatformNeedsLocalCheckout
    case notAMetalUICheckout(String)
    case destinationNotEmpty(String)
    case usage(String)

    package var description: String {
        switch self {
        case let .invalidName(name, reason): "invalid application name '\(name)': \(reason)"
        case let .invalidBundleIdentifier(id):
            "invalid bundle identifier '\(id)': use letters, digits, '-' and '.', e.g. com.example.MyApp"
        case .crossPlatformNeedsLocalCheckout:
            "--cross-platform needs --local <MetalUI checkout>: the SDL backend is the package at "
                + "Backends/SDL inside the MetalUI repository, which SwiftPM cannot fetch by URL"
        case let .notAMetalUICheckout(path): "not a MetalUI checkout (no MetalUI Package.swift): \(path)"
        case let .destinationNotEmpty(path): "destination exists and is not empty: \(path)"
        case let .usage(message): message
        }
    }
}

// MARK: - Validation

/// Rejects a name that is not a Swift identifier SwiftPM uses unchanged as the
/// module name, or one that would collide with a MetalUI module (SC-B).
package func validateName(_ name: String) throws {
    guard let first = name.unicodeScalars.first else {
        throw ScaffoldError.invalidName(name, reason: "it is empty")
    }
    let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    let rest = letters.union(CharacterSet(charactersIn: "0123456789_"))
    guard letters.contains(first) || first == "_" else {
        throw ScaffoldError.invalidName(name, reason: "it must start with a letter or '_'")
    }
    guard name.unicodeScalars.allSatisfy(rest.contains) else {
        throw ScaffoldError.invalidName(name, reason: "use only ASCII letters, digits and '_'")
    }
    guard !name.lowercased().hasPrefix("metalui") else {
        throw ScaffoldError.invalidName(name, reason: "names starting with MetalUI collide with the framework's modules")
    }
    if let reason = clashingModuleNames[name] {
        throw ScaffoldError.invalidName(name, reason: reason)
    }
}

/// Names of modules a MetalUI app is built with, each of which failed
/// `swift build` of a generated package (SC-H, record §72 §6.3). Matched
/// case-sensitively: module lookup is case-sensitive even on case-insensitive
/// APFS, and `foundation`, `appkit`, `swift`, `cfreetype` all built. Not
/// exhaustive — any module in MetalUI's transitive import closure on the build
/// platform clashes (on macOS that is AppKit's, dozens of frameworks); these
/// are the measured ones, plus `WinSDK`, derived from `Glibc` on Linux (Windows
/// Foundation imports it the same way; no Windows host to measure).
let clashingModuleNames: [String: String] = {
    let cycle = "MetalUI imports a module of that name (directly or through AppKit or Foundation), "
        + "so the app's own module would be a dependency cycle"
    let unique = "target names must be unique across the package graph"
    var names = ["Swift": "the module name \"Swift\" is reserved for the standard library"]
    for system in ["Foundation", "AppKit", "Metal", "CoreText", "CoreGraphics", "QuartzCore", "CoreVideo",
                   "CoreImage", "CoreFoundation", "Dispatch", "Darwin", "ObjectiveC", "Combine", "Observation",
                   "simd", "os", "IOKit", "ImageIO", "UniformTypeIdentifiers", "Accessibility", "SwiftUICore",
                   "Spatial", "DeveloperToolsSupport", "SwiftShims", "_Concurrency", "_StringProcessing",
                   // Linux (measured in `swift:6.4-noble`) and Windows (derived).
                   "Glibc", "FoundationEssentials", "WinSDK"] {
        names[system] = cycle
    }
    for target in ["CFreeType", "CHarfBuzz", "CUnibreak", "CSheenBidi"] {
        names[target] = "MetalUI has a target of that name, and \(unique)"
    }
    // Refused in every mode: they clash once `--cross-platform` adds
    // Backends/SDL, and a name is not worth changing later.
    for target in ["CSDL", "SDLBridge", "CAccessKit", "ReplayFixture", "SDLReplay", "PortableReplay", "DemoCapture"] {
        names[target] = "MetalUI's SDL backend has a target of that name, and \(unique)"
    }
    return names
}()

/// SwiftPM identifies every package, the root included, by its directory's
/// name, lowercased; an app named after a dependency's identity, in any case,
/// collides with it (SC-H; measured for `SDL` beside `Backends/SDL`).
func validateIdentity(_ options: ScaffoldOptions) throws {
    var identities: [String] = []
    if case let .local(path) = options.source {
        identities.append(packageIdentity(ofPath: path))
        if options.crossPlatform {
            identities.append(packageIdentity(ofPath: URL(fileURLWithPath: path).appendingPathComponent("Backends/SDL").path))
        }
    }
    for identity in identities where identity.lowercased() == options.name.lowercased() {
        throw ScaffoldError.invalidName(options.name, reason: "a dependency's package identity is '\(identity.lowercased())' "
            + "(its directory's name), and SwiftPM identifies this package by its directory's name too")
    }
}

package func validateBundleIdentifier(_ identifier: String) throws {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
    let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }),
          identifier.unicodeScalars.allSatisfy(allowed.contains) else {
        throw ScaffoldError.invalidBundleIdentifier(identifier)
    }
}

// MARK: - Generation

/// The generated package's files, in a fixed order.
package func scaffoldFiles(_ options: ScaffoldOptions) throws -> [ScaffoldFile] {
    try validateName(options.name)
    try validateBundleIdentifier(options.bundleIdentifier)
    if options.crossPlatform, case .remote = options.source {
        throw ScaffoldError.crossPlatformNeedsLocalCheckout
    }
    try validateIdentity(options)
    let name = options.name
    var files = [
        ScaffoldFile(path: "Package.swift", contents: manifest(options)),
        ScaffoldFile(path: "Sources/\(name)/main.swift", contents: mainSource(options)),
        ScaffoldFile(path: "Sources/\(name)/ContentView.swift", contents: contentViewSource(options)),
        ScaffoldFile(path: ".gitignore", contents: gitignore),
        ScaffoldFile(path: "README.md", contents: readme(options)),
        ScaffoldFile(path: "Packaging/macOS/Info.plist", contents: infoPlist(options)),
        ScaffoldFile(path: "scripts/bundle-macos.sh", contents: bundleScript(options), executable: true),
    ]
    if options.crossPlatform {
        files += [
            ScaffoldFile(path: "Packaging/linux/\(options.bundleIdentifier).desktop", contents: desktopEntry(options)),
            ScaffoldFile(path: "Packaging/windows/\(name).rc", contents: "1 ICON \"\(name).ico\"\n"),
        ]
    }
    return files
}

/// SwiftPM's identity for a path dependency is its directory's last path
/// component, and `.product(package:)` names it by that (SC-C).
package func packageIdentity(ofPath path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.lastPathComponent
}

private func swiftString(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

func manifest(_ options: ScaffoldOptions) -> String {
    let name = options.name
    let dependencies: String
    let metalUIPackage: String
    switch options.source {
    case let .remote(url, .branch(branch)):
        dependencies = "        .package(url: \(swiftString(url)), branch: \(swiftString(branch))),\n"
        metalUIPackage = "MetalUI"
    case let .remote(url, .revision(revision)):
        dependencies = "        // One commit of MetalUI, until you move it: README.md, \"Updating MetalUI\".\n"
            + "        .package(url: \(swiftString(url)), revision: \(swiftString(revision))),\n"
        metalUIPackage = "MetalUI"
    case let .local(path):
        dependencies = "        .package(path: \(swiftString(path))),\n"
        metalUIPackage = packageIdentity(ofPath: path)
    }
    var products = "                .product(name: \"MetalUI\", package: \(swiftString(metalUIPackage))),\n"
    var sdlDependency = ""
    if options.crossPlatform, case let .local(path) = options.source {
        let sdlPath = URL(fileURLWithPath: path).appendingPathComponent("Backends/SDL").path
        sdlDependency = "        // The SDL backend, which MetalUI's portable text draws through on Linux and\n"
            + "        // Windows. It depends on MetalUI by relative path, so it is only reachable\n"
            + "        // from a checkout (`metalui new --cross-platform` needs `--local`).\n"
            + "        .package(path: \(swiftString(sdlPath))),\n"
        let sdlPackage = swiftString(packageIdentity(ofPath: sdlPath))
        let portable = ".when(platforms: [.linux, .windows])"
        products += "                .product(name: \"MetalUISDL\", package: \(sdlPackage), condition: \(portable)),\n"
            + "                .product(name: \"MetalUIPortableText\", package: \(swiftString(metalUIPackage)), condition: \(portable)),\n"
            + "                .product(name: \"MetalUISystemFonts\", package: \(swiftString(metalUIPackage)), condition: \(portable)),\n"
    }
    return """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: \(swiftString(name)),
            platforms: [.macOS(.v14)],
            products: [
                .executable(name: \(swiftString(name)), targets: [\(swiftString(name))]),
            ],
            dependencies: [
        \(dependencies)\(sdlDependency)    ],
            targets: [
                .executableTarget(
                    name: \(swiftString(name)),
                    dependencies: [
        \(products)            ]
                ),
            ],
            swiftLanguageModes: [.v6]
        )

        """
}

func mainSource(_ options: ScaffoldOptions) -> String {
    let name = options.name
    if options.crossPlatform {
        return #"""
            import MetalUI
            #if canImport(MetalUISDL)
            import MetalUIPortableText
            import MetalUISDL
            import MetalUISystemFonts
            #endif

            /// AppKit and Metal on macOS; SDL3 with MetalUI's portable text, over the
            /// platform's installed fonts, on Linux and Windows.
            @MainActor
            func makeApp() throws -> App {
                #if canImport(MetalUISDL)
                let resolver = try SystemFonts.resolver()
                return App(platform: try SDLPlatform(), textSystem: { PortableTextSystem(resolver: resolver) })
                #else
                return try App()
                #endif
            }

            let app = try makeApp()
            try app.openWindow(title: "\#(name)",
                               size: Size(width: Pixels(640), height: Pixels(400)),
                               content: rootView)
            app.run()

            """#
    }
    return #"""
        import MetalUI

        // AppKit and Metal, text through CoreText. Closing the window quits.
        let app = try App()
        try app.openWindow(title: "\#(name)",
                           size: Size(width: Pixels(640), height: Pixels(400)),
                           content: rootView)
        app.run()

        """#
}

func contentViewSource(_ options: ScaffoldOptions) -> String {
    #"""
    import MetalUI

    /// The window's one root element, rebuilt every frame.
    @MainActor
    func rootView() -> some Element {
        Column(gap: Pixels(16)) {
            ContentView()
        }
        .padding(Pixels(24))
        .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
        .background(.surface)
    }

    /// `@State` lives as long as this component keeps its place in the tree.
    struct ContentView: Component {
        @State var presses = 0

        var content: some ElementGroup {
            Text("Hello from \#(options.name)").font(size: 24)
            Row(gap: Pixels(12)) {
                Button("Press me") { presses += 1 }
                Text("pressed \(presses) times")
            }
        }
    }

    """#
}

let gitignore = """
    .DS_Store
    /.build
    /build
    /.swiftpm
    /Packages

    """

func readme(_ options: ScaffoldOptions) -> String {
    let name = options.name
    var text = """
        # \(name)

        A [MetalUI](https://github.com/mburger89/MetalUI) application, generated by
        `metalui new`.

        ```sh
        swift run \(name)
        ```

        ## Package a macOS app

        ```sh
        scripts/bundle-macos.sh        # → build/\(name).app, signed ad hoc
        ```

        Put a 1024 × 1024 `Packaging/icon-1024.png` in place first to give the bundle
        an icon; `CODESIGN_IDENTITY="Developer ID Application: …"` signs for
        distribution. The bundle carries MetalUI's shader resources
        (`MetalUI_MetalUIRender.bundle`) in `Contents/Resources`. The identifier is
        `\(options.bundleIdentifier)` (`Packaging/macOS/Info.plist`). Background:
        MetalUI's `docs/packaging.md`.

        """
    text += updatingSection(options.source)
    if options.crossPlatform, case let .local(checkout) = options.source {
        text += crossPlatformSections(name: name, bundleIdentifier: options.bundleIdentifier, checkout: checkout)
    }
    return text
}

/// How the app moves to another MetalUI (SC-I).
private func updatingSection(_ source: MetalUISource) -> String {
    switch source {
    case let .remote(url, .revision(revision)):
        return """

            ## Updating MetalUI

            `Package.swift` pins MetalUI to one commit of <\(url)>,
            `\(revision)`, so nothing that changes in MetalUI reaches this app until
            you choose it. To update, put a newer commit of its `master` branch in the
            `revision:` (or `branch: "master"` to follow the branch, accepting every
            change as it lands), then:

            ```sh
            swift package update
            swift build
            ```

            `Package.resolved` records the commit you built; commit it with the app.

            """
    case let .remote(url, .branch(branch)):
        return """

            ## Updating MetalUI

            `Package.swift` follows the `\(branch)` branch of <\(url)>.
            `swift package update` moves the app to that branch's newest commit, breaking
            changes included; `Package.resolved` records the commit you built — commit it
            with the app. To stay on one commit, replace `branch: "\(branch)"` with
            `revision: "<commit>"`.

            """
    case let .local(path):
        return """

            ## Updating MetalUI

            `Package.swift` depends on the MetalUI checkout at `\(path)`; the app builds
            against whatever that checkout holds.

            """
    }
}

/// macOS, Linux and Windows, each with what that platform needs (SC-F, SC-G).
private func crossPlatformSections(name: String, bundleIdentifier: String, checkout: String) -> String {
    let sdl = checkout + "/Backends/SDL"
    return """

        ## macOS

        The same AppKit and Metal app as without `--cross-platform`. `swift build`
        prints two warnings here (the second only with SDL3 installed by Homebrew):

        ```
        warning: 'sdl': couldn't find pc file for accesskit
        warning: 'sdl': prohibited flag(s): -Wl,-rpath,/opt/homebrew/lib
        ```

        They are harmless on macOS. SwiftPM loads every dependency on every
        platform, so it asks pkg-config about the SDL backend's two system libraries,
        AccessKit and SDL3, and refuses the `-rpath` flag Homebrew's `sdl3.pc` carries;
        but every SDL product this app uses is conditioned on Linux and Windows, so
        nothing of SDL is compiled or linked on macOS.

        ## Linux

        Needs SDL3 (3.4) with pkg-config — Ubuntu 24.04 ships only SDL2, so MetalUI's
        CI builds SDL3 from source (`Backends/SDL/linux/Dockerfile`) — and AccessKit's
        C bindings. Once:

        ```sh
        python3 \(sdl)/scripts/fetch-accesskit.py
        ```

        (it downloads AccessKit's release; on aarch64 it builds the library with
        cargo), then build and run with its `.accesskit` on the pkg-config path:

        ```sh
        PKG_CONFIG_PATH=\(sdl)/.accesskit swift run \(name)
        ```

        `Packaging/linux/\(bundleIdentifier).desktop` is the desktop entry (install it
        with `desktop-file-install`; run the app with `SDL_APP_ID=\(bundleIdentifier)`
        so the shell matches the window to it).

        ## Windows

        *These steps are what MetalUI's Windows CI does to build its SDL backend
        (`.github/workflows/sdl-gpu-linux.yml`); an app generated by `metalui new` has
        not yet been built on Windows.*

        There is no pkg-config: SwiftPM is handed SDL3's and AccessKit's include and
        library paths. Unpack SDL3's prebuilt Visual C++ package
        (`SDL3-devel-3.4.16-VC.zip`, from SDL's GitHub releases) — say to `C:\\SDL3` —
        then, in PowerShell:

        ```powershell
        python \(sdl)/scripts/fetch-accesskit.py   # prints the AccessKit flags used below
        $flags = @("-Xcc", "-IC:\\SDL3\\include", "-Xswiftc", "-LC:\\SDL3\\lib\\x64",
                   "-Xcc", "-I\(sdl)/.accesskit/accesskit-c-0.23.0/include",
                   "-Xswiftc", "-L\(sdl)/.accesskit/lib")
        $env:Path += ";C:\\SDL3\\lib\\x64"   # SDL3.dll, at run time
        swift run @flags \(name)
        ```

        `Packaging/windows/\(name).rc` embeds `\(name).ico` as the executable's icon.
        Both packaging files are described in MetalUI's `docs/packaging.md`.

        """
}

func infoPlist(_ options: ScaffoldOptions) -> String {
    let name = options.name
    return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>         <string>\(name)</string>
            <key>CFBundleIdentifier</key>         <string>\(options.bundleIdentifier)</string>
            <key>CFBundleName</key>               <string>\(name)</string>
            <key>CFBundlePackageType</key>        <string>APPL</string>
            <key>CFBundleShortVersionString</key> <string>1.0</string>
            <key>CFBundleVersion</key>            <string>1</string>
            <key>CFBundleIconFile</key>           <string>\(name)</string>
            <key>LSMinimumSystemVersion</key>     <string>14.0</string>
            <key>NSHighResolutionCapable</key>    <true/>
        </dict>
        </plist>

        """
}

func bundleScript(_ options: ScaffoldOptions) -> String {
    let name = options.name
    return #"""
        #!/bin/sh
        # Builds build/\#(name).app from a release build: the executable, MetalUI's
        # shader resources in Contents/Resources, an .icns when
        # Packaging/icon-1024.png exists, signed ad hoc unless CODESIGN_IDENTITY is
        # set. The steps are MetalUI's docs/packaging.md.
        set -eu
        cd "$(dirname "$0")/.."

        NAME=\#(name)
        swift build -c release --product "$NAME"
        BIN=$(swift build -c release --product "$NAME" --show-bin-path)
        APP="build/$NAME.app"

        rm -rf "$APP"
        mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
        cp "$BIN/$NAME" "$APP/Contents/MacOS/"
        cp -R "$BIN/MetalUI_MetalUIRender.bundle" "$APP/Contents/Resources/"
        cp Packaging/macOS/Info.plist "$APP/Contents/Info.plist"

        if [ -f Packaging/icon-1024.png ]; then
            ICONSET="$(mktemp -d)/$NAME.iconset"
            mkdir -p "$ICONSET"
            for n in 16 32 128 256 512; do
                sips -z $n $n Packaging/icon-1024.png --out "$ICONSET/icon_${n}x${n}.png" >/dev/null
                sips -z $((n * 2)) $((n * 2)) Packaging/icon-1024.png --out "$ICONSET/icon_${n}x${n}@2x.png" >/dev/null
            done
            iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$NAME.icns"
        fi

        plutil -lint "$APP/Contents/Info.plist" >/dev/null
        codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
        codesign --verify --strict "$APP"
        echo "$APP"

        """#
}

func desktopEntry(_ options: ScaffoldOptions) -> String {
    """
    [Desktop Entry]
    Type=Application
    Name=\(options.name)
    Comment=A MetalUI application
    Exec=\(options.name)
    Icon=\(options.bundleIdentifier)
    Terminal=false
    Categories=Utility;
    StartupWMClass=\(options.name)

    """
}

// MARK: - Writing

/// Writes `files` under `directory`, which must be absent or empty. Refuses
/// before writing anything, so a refusal leaves the file system unchanged.
package func writeScaffold(_ files: [ScaffoldFile], to directory: URL) throws {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
        // A file in the way, or a directory with anything in it.
        guard isDirectory.boolValue, (try fileManager.contentsOfDirectory(atPath: directory.path)).isEmpty else {
            throw ScaffoldError.destinationNotEmpty(directory.path)
        }
    }
    for file in files {
        let url = directory.appendingPathComponent(file.path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(file.contents.utf8).write(to: url)
        #if !os(Windows)
        if file.executable {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        #endif
    }
}

// MARK: - Command line

package enum ScaffoldCommand: Equatable {
    case help
    /// `note` is printed to standard error: why the dependency was left
    /// unpinned (SC-I).
    case new(ScaffoldOptions, parentDirectory: String, note: String? = nil)
}

package let scaffoldUsage = """
    usage: metalui new <Name> [options]

    Creates <Name>/ — a SwiftPM package with an executable that opens a MetalUI
    window, and a script that bundles it as a macOS .app.

    options:
      --path <dir>          create <dir>/<Name> (default: the current directory)
      --bundle-id <id>      the app's identifier (default: com.example.<Name>)
      --local <checkout>    depend on a MetalUI checkout on disk instead of git
      --url <git URL>       MetalUI's repository (default: \(MetalUISource.defaultURL))
      --revision <commit>   pin MetalUI to this commit (default: the newest commit
                            of origin/\(MetalUISource.defaultBranch) that the checkout this metalui was
                            built from contains; no such commit: follow \(MetalUISource.defaultBranch))
      --branch <branch>     follow a branch instead of pinning a commit
      --cross-platform      also run on Linux and Windows through the SDL backend
                            (needs --local)
      -h, --help            show this help
    """

/// What looking for a commit to pin found (SC-I).
package enum PinLookup: Equatable, Sendable {
    case revision(String)
    /// Why there is no pin.
    case unavailable(String)
}

/// The checkout this `metalui` was compiled from (SC-I): `#filePath` is this
/// file's path at build time, `<checkout>/Sources/MetalUIScaffold/Scaffold.swift`.
/// A copy of the executable moved elsewhere still names it; if it is gone, git
/// finds no repository there and the lookup falls back.
package let scaffolderCheckout = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path

/// The commit of `url` to pin (SC-I): `git merge-base HEAD origin/master` in
/// `checkout`, when `checkout`'s `origin` is `url` — the newest commit of the
/// remote's default branch, as last fetched, that the scaffolder's own source
/// contains. So the pin exists on the remote (a local, unpushed HEAD is never
/// pinned) and is as close as the remote gets to the code that wrote the
/// template. `git` runs one git command and returns its trimmed standard
/// output, or `nil` when it fails.
package func lookUpPin(of url: String, in checkout: String, git: ([String]) -> String?) -> PinLookup {
    guard let origin = git(["-C", checkout, "config", "--get", "remote.origin.url"]) else {
        return .unavailable("\(checkout), which this metalui was built from, is not a git checkout "
            + "with an origin remote, or git is not on the PATH")
    }
    guard normalizedRepository(origin) == normalizedRepository(url) else {
        return .unavailable("\(checkout), which this metalui was built from, is a clone of \(origin), not \(url)")
    }
    let branch = MetalUISource.defaultBranch
    guard let commit = git(["-C", checkout, "merge-base", "HEAD", "refs/remotes/origin/\(branch)"]),
          isCommitHash(commit) else {
        return .unavailable("\(checkout) has no origin/\(branch) that HEAD shares a commit with "
            + "(`git fetch origin` there, then run metalui again)")
    }
    return .revision(commit)
}

/// `https://host/a/b.git`, `ssh://git@host/a/b` and `git@host:a/b.git` are
/// one repository: `host/a/b`, lowercased.
func normalizedRepository(_ url: String) -> String {
    var text = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for scheme in ["https://", "http://", "ssh://", "git://"] where text.hasPrefix(scheme) {
        text.removeFirst(scheme.count)
    }
    let firstSlash = text.firstIndex(of: "/") ?? text.endIndex
    if let at = text.firstIndex(of: "@"), at < firstSlash { text = String(text[text.index(after: at)...]) }
    if let colon = text.firstIndex(of: ":"), colon < (text.firstIndex(of: "/") ?? text.endIndex) {
        text.replaceSubrange(colon...colon, with: "/")
    }
    while text.hasSuffix("/") { text.removeLast() }
    if text.hasSuffix(".git") { text.removeLast(4) }
    return text
}

private func isCommitHash(_ text: String) -> Bool {
    (text.count == 40 || text.count == 64) && text.unicodeScalars.allSatisfy { "0123456789abcdef".unicodeScalars.contains($0) }
}

/// Runs `git` from the PATH; its trimmed standard output, or `nil` when git is
/// missing or exits non-zero.
package func runGit(_ arguments: [String]) -> String? {
    let environment = ProcessInfo.processInfo.environment
    #if os(Windows)
    let (separator, names): (Character, [String]) = (";", ["git.exe", "git"])
    #else
    let (separator, names): (Character, [String]) = (":", ["git"])
    #endif
    let directories = (environment["PATH"] ?? environment["Path"] ?? "").split(separator: separator)
    guard let git = directories.lazy.flatMap({ directory in
        names.lazy.map { URL(fileURLWithPath: String(directory)).appendingPathComponent($0) }
    }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return nil }
    let process = Process()
    process.executableURL = git
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Parses `arguments` (without the program name). `workingDirectory` resolves
/// a relative `--local` or `--path`; `pinLookup` is asked for a commit of the
/// URL only when neither `--revision` nor `--branch` (nor `--local`) is given
/// (SC-I).
package func parseScaffoldCommand(_ arguments: [String], workingDirectory: String,
                                  pinLookup: (String) -> PinLookup) throws -> ScaffoldCommand {
    var remaining = arguments[...]
    guard let verb = remaining.popFirst() else { throw ScaffoldError.usage(scaffoldUsage) }
    if verb == "-h" || verb == "--help" || verb == "help" { return .help }
    guard verb == "new" else { throw ScaffoldError.usage("unknown command '\(verb)'\n\n" + scaffoldUsage) }

    var name: String?
    var parent = workingDirectory
    var bundleIdentifier: String?
    var local: String?
    var url: String?
    var branch: String?
    var revision: String?
    var crossPlatform = false

    func value(for option: String) throws -> String {
        guard let next = remaining.popFirst(), !next.hasPrefix("-") else {
            throw ScaffoldError.usage("\(option) needs a value\n\n" + scaffoldUsage)
        }
        return next
    }
    while let argument = remaining.popFirst() {
        switch argument {
        case "-h", "--help": return .help
        case "--path": parent = absolute(try value(for: argument), in: workingDirectory)
        case "--bundle-id": bundleIdentifier = try value(for: argument)
        case "--local": local = absolute(try value(for: argument), in: workingDirectory)
        case "--url": url = try value(for: argument)
        case "--branch": branch = try value(for: argument)
        case "--revision": revision = try value(for: argument)
        case "--cross-platform": crossPlatform = true
        default:
            guard !argument.hasPrefix("-"), name == nil else {
                throw ScaffoldError.usage("unexpected argument '\(argument)'\n\n" + scaffoldUsage)
            }
            name = argument
        }
    }
    guard let name else { throw ScaffoldError.usage("missing <Name>\n\n" + scaffoldUsage) }
    if local != nil, url != nil || branch != nil || revision != nil {
        throw ScaffoldError.usage("--local cannot be combined with --url, --branch or --revision")
    }
    if branch != nil, revision != nil {
        throw ScaffoldError.usage("--branch and --revision cannot be combined")
    }
    let source: MetalUISource
    var note: String?
    if let local {
        source = .local(path: local)
    } else {
        let url = url ?? MetalUISource.defaultURL
        if let revision {
            source = .remote(url: url, reference: .revision(revision))
        } else if let branch {
            source = .remote(url: url, reference: .branch(branch))
        } else {
            switch pinLookup(url) {
            case let .revision(commit):
                source = .remote(url: url, reference: .revision(commit))
            case let .unavailable(why):
                let fallback = MetalUISource.defaultBranch
                source = .remote(url: url, reference: .branch(fallback))
                note = "MetalUI is not pinned to a commit: \(why). The package follows branch \(fallback) "
                    + "instead; pin it with --revision <commit> (README.md, \"Updating MetalUI\")."
            }
        }
    }
    return .new(ScaffoldOptions(name: name, bundleIdentifier: bundleIdentifier, source: source,
                                crossPlatform: crossPlatform),
                parentDirectory: parent, note: note)
}

private func absolute(_ path: String, in workingDirectory: String) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    // Absolute: `/…`, a Windows root or UNC path `\…`, or a drive, `C:/…` or
    // `C:\…` — Foundation on Windows reports paths with forward slashes.
    let scalars = Array(expanded.unicodeScalars.prefix(3))
    let drive = scalars.count == 3 && CharacterSet.letters.contains(scalars[0])
        && scalars[1] == ":" && (scalars[2] == "/" || scalars[2] == "\\")
    let url = expanded.hasPrefix("/") || expanded.hasPrefix("\\") || drive
        ? URL(fileURLWithPath: expanded)
        : URL(fileURLWithPath: workingDirectory).appendingPathComponent(expanded)
    return url.standardizedFileURL.path
}

/// Checks that a `--local` path is a MetalUI checkout (its manifest declares
/// the `MetalUI` package), so a typo fails here rather than in `swift build`.
package func validateCheckout(_ path: String) throws {
    let manifest = URL(fileURLWithPath: path).appendingPathComponent("Package.swift")
    guard let text = try? String(contentsOf: manifest, encoding: .utf8),
          text.contains("name: \"MetalUI\"") else {
        throw ScaffoldError.notAMetalUICheckout(path)
    }
}

/// `metalui` itself: parses, generates, writes, and says what to run next.
/// Returns the process's exit status. `pinLookup` defaults to git in the
/// checkout this executable was built from (SC-I).
package func runScaffold(_ arguments: [String], workingDirectory: String,
                         pinLookup: (String) -> PinLookup = { lookUpPin(of: $0, in: scaffolderCheckout, git: runGit) },
                         output: (String) -> Void, error: (String) -> Void) -> Int32 {
    do {
        switch try parseScaffoldCommand(arguments, workingDirectory: workingDirectory, pinLookup: pinLookup) {
        case .help:
            output(scaffoldUsage)
            return 0
        case let .new(options, parent, note):
            if case let .local(path) = options.source { try validateCheckout(path) }
            let files = try scaffoldFiles(options)
            let destination = URL(fileURLWithPath: parent).appendingPathComponent(options.name)
            try writeScaffold(files, to: destination)
            if let note { error("metalui: note: \(note)") }
            var message = "Created \(destination.path)\n\n  cd \(destination.path)\n  swift run \(options.name)\n"
            if case let .remote(_, .revision(commit)) = options.source {
                message += "\nMetalUI is pinned to \(commit); README.md says how to update it.\n"
            }
            output(message)
            return 0
        }
    } catch let failure as ScaffoldError {
        error("metalui: \(failure)")
        return 1
    } catch let failure {
        error("metalui: \(failure)")
        return 1
    }
}
