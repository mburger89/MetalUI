// `metalui new` (ruling SC-A). What a generated package says is pinned here as
// text; that it builds and runs is the env-gated end-to-end test at the bottom
// (`METALUI_RUN_SCAFFOLD_BUILD_TEST=1`), and record §72's launches.
import Foundation
import Testing
@testable import MetalUIScaffold

private func file(_ path: String, in files: [ScaffoldFile]) throws -> ScaffoldFile {
    try #require(files.first { $0.path == path }, "no generated \(path)")
}

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("metalui-scaffold-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// The repository root, from this file's own path.
private let checkout = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

// MARK: - Validation (SC-B)

@Test(arguments: ["MyApp", "my_app", "_Tool", "App2"])
func aSwiftIdentifierIsAnAcceptedName(_ name: String) throws {
    try validateName(name)
}

@Test(arguments: [("", "it is empty"),
                  ("2Fast", "it must start with a letter or '_'"),
                  ("my-app", "use only ASCII letters, digits and '_'"),
                  ("Café", "use only ASCII letters, digits and '_'"),
                  ("MetalUIThing", "names starting with MetalUI collide with the framework's modules"),
                  ("metaluiapp", "names starting with MetalUI collide with the framework's modules")])
func aNameThatIsNotAModuleNameIsRefusedWithItsReason(_ name: String, _ reason: String) {
    #expect(throws: ScaffoldError.invalidName(name, reason: reason)) { try validateName(name) }
}

// SC-H: each refused name below failed `swift build` of a generated package
// (record §72 §6.3; WinSDK is derived, not measured — no Windows host). The
// reasons are spelled out here, not read from the scaffolder (shape 12).
private let cycle = "MetalUI imports a module of that name (directly or through AppKit or Foundation), "
    + "so the app's own module would be a dependency cycle"

@Test(arguments: [
    ("Swift", "the module name \"Swift\" is reserved for the standard library"),
    ("Foundation", cycle), ("AppKit", cycle), ("Metal", cycle), ("CoreText", cycle), ("CoreGraphics", cycle),
    ("QuartzCore", cycle), ("CoreVideo", cycle), ("CoreImage", cycle), ("CoreFoundation", cycle),
    ("Dispatch", cycle), ("Darwin", cycle), ("ObjectiveC", cycle), ("Combine", cycle), ("Observation", cycle),
    ("simd", cycle), ("os", cycle), ("IOKit", cycle), ("ImageIO", cycle), ("UniformTypeIdentifiers", cycle),
    ("Accessibility", cycle), ("SwiftUICore", cycle), ("Spatial", cycle), ("DeveloperToolsSupport", cycle),
    ("SwiftShims", cycle), ("_Concurrency", cycle), ("_StringProcessing", cycle),
    ("Glibc", cycle), ("FoundationEssentials", cycle), ("WinSDK", cycle),
    ("CFreeType", "MetalUI has a target of that name, and target names must be unique across the package graph"),
    ("CHarfBuzz", "MetalUI has a target of that name, and target names must be unique across the package graph"),
    ("CUnibreak", "MetalUI has a target of that name, and target names must be unique across the package graph"),
    ("CSheenBidi", "MetalUI has a target of that name, and target names must be unique across the package graph"),
    ("CSDL", "MetalUI's SDL backend has a target of that name, and target names must be unique across the package graph"),
    ("SDLBridge", "MetalUI's SDL backend has a target of that name, and target names must be unique across the package graph"),
    ("CAccessKit", "MetalUI's SDL backend has a target of that name, and target names must be unique across the package graph"),
    ("ReplayFixture", "MetalUI's SDL backend has a target of that name, and target names must be unique across the package graph"),
    ("SDLReplay", "MetalUI's SDL backend has a target of that name, and target names must be unique across the package graph"),
    ("PortableReplay", "MetalUI's SDL backend has a target of that name, and target names must be unique across the package graph"),
    ("DemoCapture", "MetalUI's SDL backend has a target of that name, and target names must be unique across the package graph"),
])
func aNameThatClashesWithAModuleTheAppBuildsWithIsRefused(_ name: String, _ reason: String) {
    #expect(throws: ScaffoldError.invalidName(name, reason: reason)) { try validateName(name) }
}

/// SC-H: module lookup is case-sensitive even on case-insensitive APFS — each
/// of these built (record §72 §6.3) — and a keyword is a valid module name.
@Test(arguments: ["foundation", "appkit", "metal", "swift", "SWIFT", "coretext", "observation", "cfreetype",
                  "MetalKit", "SwiftUI", "XCTest", "Testing", "Cocoa", "Accelerate", "class", "func", "Self",
                  "ReplayFixtureTests", "Distributed", "RegexBuilder"])
func aLookAlikeOfARefusedNameIsAccepted(_ name: String) throws {
    try validateName(name)
}

/// SC-H: SwiftPM identifies a package by its directory, lowercased, so an app
/// whose name is a dependency's identity in any case collides with it
/// (measured for `SDL`/`sdl` beside `Backends/SDL`, record §72 §6.3).
@Test func aNameThatIsADependencysPackageIdentityIsRefused() throws {
    let sdl = "a dependency's package identity is 'sdl' (its directory's name), and SwiftPM identifies "
        + "this package by its directory's name too"
    for name in ["SDL", "sdl", "Sdl"] {
        #expect(throws: ScaffoldError.invalidName(name, reason: sdl)) {
            try scaffoldFiles(ScaffoldOptions(name: name, source: .local(path: "/src/MetalUI"), crossPlatform: true))
        }
    }
    _ = try scaffoldFiles(ScaffoldOptions(name: "SDL", source: .local(path: "/src/MetalUI")))
    let fork = "a dependency's package identity is 'tools' (its directory's name), and SwiftPM identifies "
        + "this package by its directory's name too"
    #expect(throws: ScaffoldError.invalidName("Tools", reason: fork)) {
        try scaffoldFiles(ScaffoldOptions(name: "Tools", source: .local(path: "/src/tools")))
    }
}

@Test func aBundleIdentifierNeedsTwoNonEmptyReverseDNSParts() throws {
    try validateBundleIdentifier("com.example.MyApp")
    try validateBundleIdentifier("org.my-team.app2")
    for bad in ["MyApp", "com..app", ".com.app", "com.app.", "com.my app", "com.app_x"] {
        #expect(throws: ScaffoldError.invalidBundleIdentifier(bad)) { try validateBundleIdentifier(bad) }
    }
}

@Test func generationValidatesBeforeProducingAnything() {
    #expect(throws: ScaffoldError.invalidName("my-app", reason: "use only ASCII letters, digits and '_'")) {
        try scaffoldFiles(ScaffoldOptions(name: "my-app"))
    }
    #expect(throws: ScaffoldError.invalidBundleIdentifier("nodots")) {
        try scaffoldFiles(ScaffoldOptions(name: "MyApp", bundleIdentifier: "nodots"))
    }
}

// MARK: - The generated package

@Test func theDefaultPackageIsMacOSOnlyAndDependsOnTheRepositoryByGitURL() throws {
    let files = try scaffoldFiles(ScaffoldOptions(name: "MyApp"))
    #expect(files.map(\.path) == ["Package.swift", "Sources/MyApp/main.swift", "Sources/MyApp/ContentView.swift",
                                  ".gitignore", "README.md", "Packaging/macOS/Info.plist",
                                  "scripts/bundle-macos.sh"])
    let manifest = try file("Package.swift", in: files).contents
    #expect(manifest.contains(#".package(url: "https://github.com/mburger89/MetalUI.git", branch: "master"),"#))
    #expect(manifest.contains(#".product(name: "MetalUI", package: "MetalUI"),"#))
    #expect(manifest.contains(#".executable(name: "MyApp", targets: ["MyApp"]),"#))
    #expect(!manifest.contains("MetalUISDL"))
    let main = try file("Sources/MyApp/main.swift", in: files).contents
    #expect(main.contains("let app = try App()"))
    #expect(main.contains(#"title: "MyApp""#))
    #expect(!main.contains("SDL"))
}

@Test func aLocalCheckoutIsAPathDependencyNamedByItsDirectory() throws {
    // SwiftPM names a path dependency by its last path component, so a
    // checkout in a directory not called MetalUI must be named as that.
    let files = try scaffoldFiles(ScaffoldOptions(name: "MyApp", source: .local(path: "/src/metalui-fork")))
    let manifest = try file("Package.swift", in: files).contents
    #expect(manifest.contains(#".package(path: "/src/metalui-fork"),"#))
    #expect(manifest.contains(#".product(name: "MetalUI", package: "metalui-fork"),"#))
    #expect(!manifest.contains(".package(url:"))
}

/// The block a cross-platform manifest turns MetalUI's SDL traits on with,
/// on Linux and Windows only (ruling PX-J item 1).
private let traitsBlock = """
    #if os(Linux) || os(Windows)
    let metalUITraits: Set<Package.Dependency.Trait> = ["SDL", "AccessKit"]
    #else
    let metalUITraits: Set<Package.Dependency.Trait> = [.defaults]
    #endif
    """

/// 1.1 (PX-J item 1; replaces `crossPlatformWithoutALocalCheckoutIsRefused`,
/// SC-C amended): the SDL backend is the root package's `MetalUISDL` behind
/// the `SDL` trait, so a package depending on MetalUI by URL reaches it.
/// Mutation: restore the `crossPlatformNeedsLocalCheckout` throw in
/// `scaffoldFiles`.
@Test func crossPlatformNoLongerNeedsALocalCheckout() throws {
    let files = try scaffoldFiles(ScaffoldOptions(name: "MyApp", crossPlatform: true))
    let manifest = try file("Package.swift", in: files).contents
    #expect(manifest.hasPrefix("// swift-tools-version: 6.1\n"))
    #expect(manifest.contains(traitsBlock))
    #expect(manifest.contains(#".package(url: "https://github.com/mburger89/MetalUI.git", branch: "master", traits: metalUITraits),"#))
    let portable = "condition: .when(platforms: [.linux, .windows])"
    #expect(manifest.contains(#".product(name: "MetalUISDL", package: "MetalUI", "# + portable + ")"))
    #expect(manifest.contains(#".product(name: "MetalUIPortableText", package: "MetalUI", "# + portable + ")"))
    #expect(manifest.contains(#".product(name: "MetalUISystemFonts", package: "MetalUI", "# + portable + ")"))
    #expect(manifest.components(separatedBy: ".package(").count == 2, "one dependency:\n\(manifest)")
    // A pinned revision carries the traits too.
    let pinnedManifest = try file("Package.swift", in: try scaffoldFiles(ScaffoldOptions(
        name: "MyApp", source: .remote(url: "https://github.com/mburger89/MetalUI.git", reference: .revision(pinned)),
        crossPlatform: true))).contents
    #expect(pinnedManifest.contains(#"revision: ""# + pinned + #"", traits: metalUITraits),"#))
    // Without --cross-platform: tools 6.0 and no traits, unchanged.
    let plain = try file("Package.swift", in: try scaffoldFiles(ScaffoldOptions(name: "MyApp"))).contents
    #expect(plain.hasPrefix("// swift-tools-version: 6.0\n"))
    #expect(!plain.contains("traits"))
}

/// 1.2 (PX-J item 1): `--local` names the checkout once; the `Backends/SDL`
/// package is no longer a dependency. Mutation: re-add the `sdlDependency`
/// string.
@Test func theLocalCrossPlatformManifestNamesNoBackendsSDLPackage() throws {
    let files = try scaffoldFiles(ScaffoldOptions(name: "MyApp", source: .local(path: "/src/MetalUI"),
                                                  crossPlatform: true))
    let manifest = try file("Package.swift", in: files).contents
    #expect(manifest.components(separatedBy: ".package(path:").count == 2, "one path dependency:\n\(manifest)")
    #expect(manifest.contains(#".package(path: "/src/MetalUI", traits: metalUITraits),"#))
    #expect(!manifest.contains("Backends/SDL"))
    let portable = "condition: .when(platforms: [.linux, .windows])"
    #expect(manifest.contains(#".product(name: "MetalUISDL", package: "MetalUI", "# + portable))
    #expect(manifest.contains(#".product(name: "MetalUIPortableText", package: "MetalUI", "# + portable))
    #expect(manifest.contains(#".product(name: "MetalUISystemFonts", package: "MetalUI", "# + portable))
    let main = try file("Sources/MyApp/main.swift", in: files).contents
    #expect(main.contains("#if canImport(MetalUISDL)"))
    #expect(main.contains("App(platform: try SDLPlatform(), textSystem: { PortableTextSystem(resolver: resolver) })"))
    #expect(main.contains("return try App()"))
    #expect(try file("Packaging/linux/com.example.MyApp.desktop", in: files).contents.contains("Icon=com.example.MyApp\n"))
    #expect(try file("Packaging/windows/MyApp.rc", in: files).contents == "1 ICON \"MyApp.ico\"\n")
}

/// 1.3 (PX-J item 2): `--no-accesskit` asks for `SDL` alone and says the app
/// has no screen reader support. Mutation: ignore the flag (always
/// `["SDL", "AccessKit"]`).
@Test func noAccessKitDropsOnlyTheAccessKitTrait() throws {
    let command = try parseScaffoldCommand(["new", "MyApp", "--cross-platform", "--no-accesskit"],
                                           workingDirectory: "/w", pinLookup: { _ in .revision(pinned) })
    guard case let .new(options, _, _) = command else {
        Issue.record("not a new command: \(command)")
        return
    }
    #expect(options.crossPlatform)
    #expect(!options.accessKit)
    let files = try scaffoldFiles(options)
    let manifest = try file("Package.swift", in: files).contents
    #expect(manifest.contains(#"let metalUITraits: Set<Package.Dependency.Trait> = ["SDL"]"# + "\n"))
    #expect(!manifest.contains(#""AccessKit""#))
    let readme = try file("README.md", in: files).contents
    #expect(readme.contains("This app has no screen-reader support on Linux and Windows"))
    #expect(!readme.contains("fetch-accesskit.py"))
    // The default keeps both.
    #expect(ScaffoldOptions(name: "MyApp", crossPlatform: true).accessKit)
    // Without --cross-platform the flag means nothing: refused.
    #expect(throws: ScaffoldError.self) {
        try parseScaffoldCommand(["new", "MyApp", "--no-accesskit"], workingDirectory: "/w", pinLookup: noLookup)
    }
}

/// The README's text from `heading` to the next `## ` heading.
private func section(_ heading: String, of readme: String) throws -> String {
    let start = try #require(readme.range(of: "\n## \(heading)\n"), "no section \(heading)")
    let rest = readme[start.upperBound...]
    return String(rest[..<(rest.range(of: "\n## ")?.lowerBound ?? rest.endIndex)])
}

/// 1.4 (PX-I item 1 as amended by PX-Q; PX-P): what a consumer installs on
/// Linux — SDL 3.4+ on the default paths or the flags, `swift package
/// resolve` first, the fetch script from the resolved checkout with
/// `--prefix /usr`, cargo on aarch64, or no `AccessKit` — and how the
/// shaders ship. No pkg-config anywhere. Mutation: restore the old section.
@Test func theCrossPlatformReadmeSaysWhatAConsumerInstalls() throws {
    let files = try scaffoldFiles(ScaffoldOptions(name: "MyApp", crossPlatform: true))
    let readme = try file("README.md", in: files).contents
    let linux = try section("Linux", of: readme)
    #expect(linux.contains("SDL 3.4 or later"))
    #expect(linux.contains("-DCMAKE_INSTALL_PREFIX=/usr"))
    #expect(linux.contains("`-Xcc -I<prefix>/include -Xlinker -L<prefix>/lib`"))
    #expect(linux.contains("swift package resolve\nsudo python3 .build/checkouts/MetalUI/Backends/SDL/scripts/fetch-accesskit.py --prefix /usr\n"))
    #expect(linux.contains("aarch64"))
    #expect(linux.contains("(`cargo`)"))
    #expect(linux.contains("`--print-flags`"))
    #expect(linux.contains(#"remove `"AccessKit"` from `metalUITraits`"#))
    #expect(linux.contains("swift run MyApp"))
    #expect(linux.contains("copy `.build/checkouts/MetalUI/Backends/SDL/Shaders/compiled` beside the executable as `MetalUISDLShaders`"))
    let windows = try section("Windows", of: readme)
    #expect(windows.contains("python .build/checkouts/MetalUI/Backends/SDL/scripts/fetch-accesskit.py --print-flags"))
    #expect(windows.contains(#""-Xcc", "-IC:\SDL3\include", "-Xswiftc", "-LC:\SDL3\lib\x64""#))
    #expect(windows.contains("swift run @flags MyApp"))
    #expect(windows.contains("SDL3.dll"))
    #expect(windows.contains("`MetalUISDLShaders`"))
    #expect(windows.contains("not yet been built on Windows"))
    let macOS = try section("macOS", of: readme)
    #expect(macOS.contains("nothing of SDL is compiled or linked on macOS"))
    for text in ["couldn't find pc file", "PKG_CONFIG_PATH", "pkg-config", "harmless"] {
        #expect(!readme.contains(text), "\(text)")
    }
    // A checkout on disk names its own scripts and shaders.
    let local = try section("Linux", of: try file("README.md", in: try scaffoldFiles(ScaffoldOptions(
        name: "MyApp", source: .local(path: "/src/MetalUI"), crossPlatform: true))).contents)
    #expect(local.contains("sudo python3 /src/MetalUI/Backends/SDL/scripts/fetch-accesskit.py --prefix /usr\n"))
    #expect(local.contains("copy `/src/MetalUI/Backends/SDL/Shaders/compiled` beside"))
    // A fork's checkout directory is its repository's name.
    let fork = try section("Linux", of: try file("README.md", in: try scaffoldFiles(ScaffoldOptions(
        name: "MyApp", source: .remote(url: "https://example.com/me/ui-fork.git", reference: .branch("dev")),
        crossPlatform: true))).contents)
    #expect(fork.contains("python3 .build/checkouts/ui-fork/Backends/SDL/scripts/fetch-accesskit.py"))
}

@Test func theInfoPlistNamesTheExecutableIdentifierAndIcon() throws {
    let files = try scaffoldFiles(ScaffoldOptions(name: "Notes", bundleIdentifier: "org.example.notes"))
    let data = Data(try file("Packaging/macOS/Info.plist", in: files).contents.utf8)
    let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(plist["CFBundleExecutable"] as? String == "Notes")
    #expect(plist["CFBundleIdentifier"] as? String == "org.example.notes")
    #expect(plist["CFBundleIconFile"] as? String == "Notes")
    #expect(plist["CFBundlePackageType"] as? String == "APPL")
    #expect(plist["LSMinimumSystemVersion"] as? String == "14.0")
}

@Test func theBundleScriptCopiesTheShaderResourcesIntoContentsResources() throws {
    // AI-N: the one place a packaged app's shader bundle is found on both
    // build systems.
    let script = try file("scripts/bundle-macos.sh", in: try scaffoldFiles(ScaffoldOptions(name: "MyApp")))
    #expect(script.executable)
    #expect(script.contents.hasPrefix("#!/bin/sh\n"))
    #expect(script.contents.contains(#"cp -R "$BIN/MetalUI_MetalUIRender.bundle" "$APP/Contents/Resources/""#))
    #expect(script.contents.contains("NAME=MyApp\n"))
}

// MARK: - Writing

@Test func writingCreatesEveryFileAndMarksOnlyTheScriptExecutable() throws {
    let root = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("MyApp")
    let files = try scaffoldFiles(ScaffoldOptions(name: "MyApp"))
    try writeScaffold(files, to: destination)
    for generated in files {
        let path = destination.appendingPathComponent(generated.path).path
        #expect(try String(contentsOfFile: path, encoding: .utf8) == generated.contents)
        #if !os(Windows)
        let mode = try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
        #expect((mode & 0o100 != 0) == generated.executable, "\(generated.path) mode \(String(mode, radix: 8))")
        #endif
    }
}

@Test func writingIntoANonEmptyDirectoryOrOntoAFileWritesNothing() throws {
    let root = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let files = try scaffoldFiles(ScaffoldOptions(name: "MyApp"))

    let occupied = root.appendingPathComponent("occupied")
    try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: occupied.appendingPathComponent("notes.txt"))
    #expect(throws: ScaffoldError.destinationNotEmpty(occupied.path)) { try writeScaffold(files, to: occupied) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: occupied.path) == ["notes.txt"])

    let plainFile = root.appendingPathComponent("file")
    try Data("x".utf8).write(to: plainFile)
    #expect(throws: ScaffoldError.destinationNotEmpty(plainFile.path)) { try writeScaffold(files, to: plainFile) }

    let empty = root.appendingPathComponent("empty")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    try writeScaffold(files, to: empty)
    #expect(FileManager.default.fileExists(atPath: empty.appendingPathComponent("Package.swift").path))
}

// MARK: - Command line

private let pinned = String(repeating: "ab12", count: 10)

/// A lookup that must not be asked.
private func noLookup(_ url: String) -> PinLookup {
    Issue.record("the pin was looked up for \(url)")
    return .unavailable("unused")
}

@Test func theCommandLineDefaultsToTheGitURLPinnedAndTheWorkingDirectory() throws {
    var asked: [String] = []
    let command = try parseScaffoldCommand(["new", "MyApp"], workingDirectory: "/work") {
        asked.append($0)
        return .revision(pinned)
    }
    #expect(asked == ["https://github.com/mburger89/MetalUI.git"])
    #expect(command == .new(ScaffoldOptions(name: "MyApp", source: .remote(
        url: "https://github.com/mburger89/MetalUI.git", reference: .revision(pinned))), parentDirectory: "/work"))
}

@Test func theCommandLineResolvesRelativePathsAgainstTheWorkingDirectory() throws {
    let command = try parseScaffoldCommand(
        ["new", "MyApp", "--path", "apps", "--local", "../MetalUI", "--bundle-id", "dev.me.app", "--cross-platform"],
        workingDirectory: "/work/here", pinLookup: noLookup)
    #expect(command == .new(ScaffoldOptions(name: "MyApp", bundleIdentifier: "dev.me.app",
                                            source: .local(path: "/work/MetalUI"), crossPlatform: true),
                            parentDirectory: "/work/here/apps"))
}

@Test func theCommandLineTakesAnotherURLAndBranch() throws {
    let command = try parseScaffoldCommand(["new", "MyApp", "--url", "https://example.com/fork.git",
                                            "--branch", "dev"], workingDirectory: "/w", pinLookup: noLookup)
    #expect(command == .new(ScaffoldOptions(name: "MyApp", source: .remote(url: "https://example.com/fork.git",
                                                                           reference: .branch("dev"))),
                            parentDirectory: "/w"))
}

/// SC-I: `--revision` and `--branch` are explicit and are never looked up;
/// `--url` without either is looked up for that URL.
@Test func anExplicitRevisionOrBranchOverridesThePin() throws {
    #expect(try parseScaffoldCommand(["new", "MyApp", "--revision", "0123abc"], workingDirectory: "/w",
                                     pinLookup: noLookup)
        == .new(ScaffoldOptions(name: "MyApp", source: .remote(url: "https://github.com/mburger89/MetalUI.git",
                                                               reference: .revision("0123abc"))),
                parentDirectory: "/w"))
    #expect(try parseScaffoldCommand(["new", "MyApp", "--branch", "master"], workingDirectory: "/w",
                                     pinLookup: noLookup)
        == .new(ScaffoldOptions(name: "MyApp", source: .remote(url: "https://github.com/mburger89/MetalUI.git",
                                                               reference: .branch("master"))),
                parentDirectory: "/w"))
    var asked: [String] = []
    _ = try parseScaffoldCommand(["new", "MyApp", "--url", "https://example.com/fork.git"], workingDirectory: "/w") {
        asked.append($0)
        return .revision(pinned)
    }
    #expect(asked == ["https://example.com/fork.git"])
}

/// SC-I: no commit to pin → the branch, and a note saying why and what to do.
@Test func withNoCommitToPinThePackageFollowsMasterAndSaysWhy() throws {
    let command = try parseScaffoldCommand(["new", "MyApp"], workingDirectory: "/w") { _ in
        .unavailable("no git here")
    }
    #expect(command == .new(ScaffoldOptions(name: "MyApp", source: .remote(
        url: "https://github.com/mburger89/MetalUI.git", reference: .branch("master"))), parentDirectory: "/w",
        note: "MetalUI is not pinned to a commit: no git here. The package follows branch master instead; "
            + "pin it with --revision <commit> (README.md, \"Updating MetalUI\")."))
}

@Test func aPinnedRevisionIsARevisionDependency() throws {
    let files = try scaffoldFiles(ScaffoldOptions(name: "MyApp", source: .remote(
        url: "https://github.com/mburger89/MetalUI.git", reference: .revision(pinned))))
    let manifest = try file("Package.swift", in: files).contents
    #expect(manifest.contains(#".package(url: "https://github.com/mburger89/MetalUI.git", revision: ""# + pinned + #""),"#))
    #expect(manifest.contains(#"// One commit of MetalUI, until you move it: README.md, "Updating MetalUI"."#))
    #expect(!manifest.contains("branch:"))
    #expect(manifest.contains(#".product(name: "MetalUI", package: "MetalUI"),"#))
}

/// SC-I: the README says how the app moves to another MetalUI, per source.
@Test func theReadmeSaysHowToUpdateMetalUI() throws {
    func updating(_ source: MetalUISource) throws -> String {
        try section("Updating MetalUI", of: try file("README.md", in: try scaffoldFiles(
            ScaffoldOptions(name: "MyApp", source: source))).contents)
    }
    let url = "https://github.com/mburger89/MetalUI.git"
    let pin = try updating(.remote(url: url, reference: .revision(pinned)))
    #expect(pin.contains("pins MetalUI to one commit of <\(url)>,\n`\(pinned)`"))
    #expect(pin.contains("put a newer commit of its `master` branch in the\n`revision:`"))
    #expect(pin.contains("swift package update\nswift build\n"))
    let branch = try updating(.remote(url: url, reference: .branch("dev")))
    #expect(branch.contains("follows the `dev` branch"))
    #expect(branch.contains(#"replace `branch: "dev"` with"# + "\n" + #"`revision: "<commit>"`"#))
    #expect(try updating(.local(path: "/src/MetalUI")).contains("the MetalUI checkout at `/src/MetalUI`"))
}

/// SC-I: the pin is the merge base of HEAD and origin/master, taken only when
/// the checkout's origin is the URL, in any of git's spellings.
@Test func thePinIsTheMergeBaseOfHeadAndOriginMasterInACloneOfTheURL() {
    let url = "https://github.com/mburger89/MetalUI.git"
    var asked: [[String]] = []
    func git(origin: String?, base: String?) -> ([String]) -> String? {
        { arguments in
            asked.append(arguments)
            return arguments.contains("config") ? origin : base
        }
    }
    #expect(lookUpPin(of: url, in: "/co", git: git(origin: "git@github.com:mburger89/MetalUI.git", base: pinned))
        == .revision(pinned))
    #expect(asked == [["-C", "/co", "config", "--get", "remote.origin.url"],
                      ["-C", "/co", "merge-base", "HEAD", "refs/remotes/origin/master"]])
    #expect(lookUpPin(of: url, in: "/co", git: git(origin: "https://github.com/MBurger89/MetalUI/", base: pinned))
        == .revision(pinned))
    #expect(lookUpPin(of: url, in: "/co", git: git(origin: nil, base: pinned))
        == .unavailable("/co, which this metalui was built from, is not a git checkout with an origin remote, "
            + "or git is not on the PATH"))
    #expect(lookUpPin(of: url, in: "/co", git: git(origin: "https://example.com/fork.git", base: pinned))
        == .unavailable("/co, which this metalui was built from, is a clone of https://example.com/fork.git, not \(url)"))
    let noBase = PinLookup.unavailable("/co has no origin/master that HEAD shares a commit with "
        + "(`git fetch origin` there, then run metalui again)")
    #expect(lookUpPin(of: url, in: "/co", git: git(origin: url, base: nil)) == noBase)
    #expect(lookUpPin(of: url, in: "/co", git: git(origin: url, base: "not a commit")) == noBase)
}

@Test func gitRunsFromThePathAndAFailureIsNil() throws {
    let version = try #require(runGit(["--version"]))
    #expect(version.hasPrefix("git version"))
    #expect(runGit(["-C", "/nonexistent-metalui-dir", "status"]) == nil)
}

@Test func runningTheCommandSaysWhatItPinnedOrWhyItDidNot() throws {
    let root = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var output: [String] = []
    var errors: [String] = []
    #expect(runScaffold(["new", "Pinned"], workingDirectory: root.path, pinLookup: { _ in .revision(pinned) },
                        output: { output.append($0) }, error: { errors.append($0) }) == 0)
    let pinnedApp = root.appendingPathComponent("Pinned").path
    #expect(output == ["Created \(pinnedApp)\n\n  cd \(pinnedApp)\n  swift run Pinned\n"
        + "\nMetalUI is pinned to \(pinned); README.md says how to update it.\n"])
    #expect(errors.isEmpty)
    output = []
    #expect(runScaffold(["new", "Floating"], workingDirectory: root.path, pinLookup: { _ in .unavailable("why") },
                        output: { output.append($0) }, error: { errors.append($0) }) == 0)
    #expect(errors == ["metalui: note: MetalUI is not pinned to a commit: why. The package follows branch master "
        + "instead; pin it with --revision <commit> (README.md, \"Updating MetalUI\")."])
    let manifest = try String(contentsOfFile: root.appendingPathComponent("Floating/Package.swift").path,
                              encoding: .utf8)
    #expect(manifest.contains(#"branch: "master")"#))
}

@Test func theCommandLineRefusesWhatItCannotMean() throws {
    for arguments in [[], ["make", "MyApp"], ["new"], ["new", "A", "B"], ["new", "A", "--path"],
                      ["new", "A", "--bogus"], ["new", "A", "--local", "/x", "--branch", "dev"],
                      ["new", "A", "--local", "/x", "--revision", "abc"], ["new", "A", "--revision"],
                      ["new", "A", "--branch", "dev", "--revision", "abc"]] {
        #expect(throws: ScaffoldError.self, "\(arguments)") {
            try parseScaffoldCommand(arguments, workingDirectory: "/w", pinLookup: noLookup)
        }
    }
    #expect(try parseScaffoldCommand(["new", "A", "--help"], workingDirectory: "/w", pinLookup: noLookup) == .help)
}

@Test func aLocalPathThatIsNotAMetalUICheckoutFailsBeforeAnythingIsWritten() throws {
    let root = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var errors: [String] = []
    let status = runScaffold(["new", "MyApp", "--local", root.path], workingDirectory: root.path,
                             output: { _ in }, error: { errors.append($0) })
    #expect(status == 1)
    #expect(errors == ["metalui: not a MetalUI checkout (no MetalUI Package.swift): \(root.path)"])
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    try validateCheckout(checkout.path)
}

@Test func runningTheCommandWritesThePackageAndSaysWhatToRunNext() throws {
    let root = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var output: [String] = []
    let status = runScaffold(["new", "MyApp", "--local", checkout.path], workingDirectory: root.path,
                             output: { output.append($0) }, error: { Issue.record("unexpected error: \($0)") })
    #expect(status == 0)
    let destination = root.appendingPathComponent("MyApp").path
    #expect(output == ["Created \(destination)\n\n  cd \(destination)\n  swift run MyApp\n"])
    #expect(FileManager.default.fileExists(atPath: destination + "/Sources/MyApp/main.swift"))
}

// MARK: - End to end (env-gated: builds MetalUI a second time)

/// A generated package resolves against this checkout and compiles. Off by
/// default — it is a full second build of MetalUI, minutes long. Counts
/// while skipped.
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_SCAFFOLD_BUILD_TEST"] == "1"))
func aGeneratedPackageBuildsAgainstThisCheckout() throws {
    #if os(macOS) || os(Linux)
    let root = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let files = try scaffoldFiles(ScaffoldOptions(name: "Smoke", source: .local(path: checkout.path)))
    let destination = root.appendingPathComponent("Smoke")
    try writeScaffold(files, to: destination)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "build", "--package-path", destination.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    #endif
}

// MARK: - A URL consumer of the SDL backend (env-gated, Linux: PX-L item 3)

/// Tests 1.7 and 1.8 run only on Linux with `METALUI_RUN_SDL_CONSUMER_BUILD_TEST=1`
/// — in CI's image (`Backends/SDL/linux/Dockerfile`: SDL3 and AccessKit on the
/// default paths, PX-I item 5). Each is a full build of MetalUI. Count while
/// skipped.
private let runsSDLConsumerBuild: Bool = {
    #if os(Linux)
    ProcessInfo.processInfo.environment["METALUI_RUN_SDL_CONSUMER_BUILD_TEST"] == "1"
    #else
    false
    #endif
}()

/// Runs `executable` with `arguments` in `directory`; its exit status and its
/// standard output and error, interleaved.
private func run(_ executable: String, _ arguments: [String], in directory: URL) throws -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// A git repository named `MetalUI` under `root` holding this checkout's
/// manifest, `Sources/`, `Tests/` and the SDL backend's sources and shaders —
/// not the checkout's own `.git`, which a worktree mounted in a container
/// cannot read (PX-L item 3). Returns its URL and commit.
private func metalUIRepository(in root: URL) throws -> (url: URL, commit: String) {
    let repository = root.appendingPathComponent("MetalUI")
    let fileManager = FileManager.default
    for path in ["Package.swift", "Sources", "Tests", "Backends/SDL/Sources", "Backends/SDL/Shaders"] {
        let destination = repository.appendingPathComponent(path)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: checkout.appendingPathComponent(path), to: destination)
    }
    // Never a build directory (a stale one would be read as sources).
    if let walker = fileManager.enumerator(at: repository, includingPropertiesForKeys: nil) {
        let builds = walker.compactMap { $0 as? URL }.filter { $0.lastPathComponent == ".build" }
        for build in builds { try? fileManager.removeItem(at: build) }
    }
    let identity = ["-c", "user.email=consumer@metalui.test", "-c", "user.name=consumer"]
    for arguments in [["init", "-q"], ["add", "-A"], identity + ["commit", "-qm", "MetalUI"]] {
        let (status, output) = try run("git", arguments, in: repository)
        try #require(status == 0, "git \(arguments): \(output)")
    }
    let (status, commit) = try run("git", ["rev-parse", "HEAD"], in: repository)
    try #require(status == 0)
    return (repository, commit.trimmingCharacters(in: .whitespacesAndNewlines))
}

/// Generates `options` under `root` and runs `swift build` there with
/// `extraArguments`; the exit status and output.
private func buildConsumer(_ options: ScaffoldOptions, in root: URL,
                           extraArguments: [String] = []) throws -> (Int32, String) {
    let destination = root.appendingPathComponent(options.name)
    try writeScaffold(try scaffoldFiles(options), to: destination)
    return try run("swift", ["build"] + extraArguments, in: destination)
}

/// 1.7 (PX-H, PX-J, PX-L item 3, PX-Q's last paragraph): a package generated
/// by `metalui new --cross-platform`, depending on MetalUI by (file://) URL at
/// one commit, builds its SDL app with plain `swift build` — SDL3 and
/// AccessKit on the image's default paths, no flags — and no warning names a
/// MetalUI path. Mutation: generate without `traits:` → `MetalUISDL` is the
/// unavailable stub → `SDLPlatform()` fails to compile.
@Test(.enabled(if: runsSDLConsumerBuild))
func aCrossPlatformPackageBuildsItsSDLAppByURL() throws {
    let root = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (repository, commit) = try metalUIRepository(in: root)
    let (status, output) = try buildConsumer(ScaffoldOptions(
        name: "Consumer", source: .remote(url: repository.absoluteString, reference: .revision(commit)),
        crossPlatform: true), in: root)
    print("1.7 consumer build: status=\(status)\n\(output.suffix(2000))")
    #expect(status == 0, "\(output)")
    let warnings = output.split(separator: "\n").filter { $0.contains("warning:") && $0.contains(repository.path) }
    #expect(warnings.isEmpty, "\(warnings)")
}

/// 1.8 (PX-H item 2, PX-J item 2, PX-L item 3): a `--no-accesskit` package
/// never compiles AccessKit — built with `-Xcc -I` naming a directory whose
/// `accesskit.h` is an `#error`, so any `CAccessKit` import under `SDL` alone
/// fails the build. Mutation: guard `AccessKitAdapter.swift` with `#if SDL`
/// instead of `#if AccessKit`.
@Test(.enabled(if: runsSDLConsumerBuild))
func aCrossPlatformPackageBuildsWithoutAccessKit() throws {
    let root = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (repository, commit) = try metalUIRepository(in: root)
    let poison = root.appendingPathComponent("poison")
    try FileManager.default.createDirectory(at: poison, withIntermediateDirectories: true)
    try Data("#error \"AccessKit must not be compiled\"\n".utf8).write(to: poison.appendingPathComponent("accesskit.h"))
    let (status, output) = try buildConsumer(ScaffoldOptions(
        name: "Plain", source: .remote(url: repository.absoluteString, reference: .revision(commit)),
        crossPlatform: true, accessKit: false), in: root, extraArguments: ["-Xcc", "-I\(poison.path)"])
    print("1.8 no-AccessKit build: status=\(status)\n\(output.suffix(2000))")
    #expect(status == 0, "\(output)")
    #expect(!output.contains("AccessKit must not be compiled"))
}
