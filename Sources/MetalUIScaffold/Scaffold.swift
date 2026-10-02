// `metalui new`: a new application package that depends on MetalUI (ruling
// SC-A, `docs/superpowers/2026-10-01-scaffold-decisions.md`). Everything here
// is `package`: the scaffolder is a tool, not framework API, so it adds no
// public declaration to the inventory. Foundation only — it is declared on
// every platform (PC-A) and runs where `swift` does.
import Foundation

/// Where the generated package finds MetalUI.
package enum MetalUISource: Equatable, Sendable {
    /// A git URL and branch — what an application outside this repository
    /// normally uses.
    case remote(url: String, branch: String)
    /// A checkout on disk, as an absolute path — for framework development,
    /// and required by `crossPlatform` (SC-C).
    case local(path: String)

    /// The repository's own URL and default branch.
    package static let defaultRemote = MetalUISource.remote(
        url: "https://github.com/mburger89/MetalUI.git", branch: "master")
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
    case let .remote(url, branch):
        dependencies = "        .package(url: \(swiftString(url)), branch: \(swiftString(branch))),\n"
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
    if options.crossPlatform {
        text += """

            ## Linux and Windows

            These platforms draw through MetalUI's SDL backend, which needs SDL3 and
            AccessKit. Once, in the MetalUI checkout:

            ```sh
            python3 Backends/SDL/scripts/fetch-accesskit.py
            ```

            then build and run with that checkout's `.accesskit` on the pkg-config path:

            ```sh
            PKG_CONFIG_PATH=<MetalUI checkout>/Backends/SDL/.accesskit swift run \(name)
            ```

            `Packaging/linux/\(options.bundleIdentifier).desktop` is the desktop entry
            (install it with `desktop-file-install`; run the app with
            `SDL_APP_ID=\(options.bundleIdentifier)` so the shell matches the window to
            it), and `Packaging/windows/\(name).rc` embeds `\(name).ico` as the
            executable's icon. Both are described in MetalUI's `docs/packaging.md`.

            """
    }
    return text
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
    case new(ScaffoldOptions, parentDirectory: String)
}

package let scaffoldUsage = """
    usage: metalui new <Name> [options]

    Creates <Name>/ — a SwiftPM package with an executable that opens a MetalUI
    window, and a script that bundles it as a macOS .app.

    options:
      --path <dir>          create <dir>/<Name> (default: the current directory)
      --bundle-id <id>      the app's identifier (default: com.example.<Name>)
      --local <checkout>    depend on a MetalUI checkout on disk instead of git
      --url <git URL>       MetalUI's repository (default: \(defaultRemoteURL))
      --branch <branch>     the branch of --url (default: master)
      --cross-platform      also run on Linux and Windows through the SDL backend
                            (needs --local)
      -h, --help            show this help
    """

private var defaultRemoteURL: String {
    if case let .remote(url, _) = MetalUISource.defaultRemote { return url }
    return ""
}

/// Parses `arguments` (without the program name). `workingDirectory` resolves
/// a relative `--local` or `--path`.
package func parseScaffoldCommand(_ arguments: [String], workingDirectory: String) throws -> ScaffoldCommand {
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
        case "--cross-platform": crossPlatform = true
        default:
            guard !argument.hasPrefix("-"), name == nil else {
                throw ScaffoldError.usage("unexpected argument '\(argument)'\n\n" + scaffoldUsage)
            }
            name = argument
        }
    }
    guard let name else { throw ScaffoldError.usage("missing <Name>\n\n" + scaffoldUsage) }
    if local != nil, url != nil || branch != nil {
        throw ScaffoldError.usage("--local cannot be combined with --url or --branch")
    }
    let source: MetalUISource
    if let local {
        source = .local(path: local)
    } else if case let .remote(defaultURL, defaultBranch) = MetalUISource.defaultRemote {
        source = .remote(url: url ?? defaultURL, branch: branch ?? defaultBranch)
    } else {
        preconditionFailure("the default MetalUI source is remote")
    }
    return .new(ScaffoldOptions(name: name, bundleIdentifier: bundleIdentifier, source: source,
                                crossPlatform: crossPlatform),
                parentDirectory: parent)
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
/// Returns the process's exit status.
package func runScaffold(_ arguments: [String], workingDirectory: String,
                         output: (String) -> Void, error: (String) -> Void) -> Int32 {
    do {
        switch try parseScaffoldCommand(arguments, workingDirectory: workingDirectory) {
        case .help:
            output(scaffoldUsage)
            return 0
        case let .new(options, parent):
            if case let .local(path) = options.source { try validateCheckout(path) }
            let files = try scaffoldFiles(options)
            let destination = URL(fileURLWithPath: parent).appendingPathComponent(options.name)
            try writeScaffold(files, to: destination)
            output("Created \(destination.path)\n\n  cd \(destination.path)\n  swift run \(options.name)\n")
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
