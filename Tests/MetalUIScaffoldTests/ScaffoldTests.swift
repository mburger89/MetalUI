// `metalui new` (ruling SC-A). What a generated package says is pinned here as
// text; that it builds and runs is the env-gated end-to-end test at the bottom
// (`METALUI_RUN_SCAFFOLD_BUILD_TEST=1`), and record §71's launch.
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

@Test func crossPlatformWithoutALocalCheckoutIsRefused() {
    #expect(throws: ScaffoldError.crossPlatformNeedsLocalCheckout) {
        try scaffoldFiles(ScaffoldOptions(name: "MyApp", crossPlatform: true))
    }
}

@Test func crossPlatformAddsTheSDLBackendOnLinuxAndWindowsOnly() throws {
    let files = try scaffoldFiles(ScaffoldOptions(name: "MyApp", source: .local(path: "/src/MetalUI"),
                                                  crossPlatform: true))
    let manifest = try file("Package.swift", in: files).contents
    #expect(manifest.contains(#".package(path: "/src/MetalUI/Backends/SDL"),"#))
    let portable = "condition: .when(platforms: [.linux, .windows])"
    #expect(manifest.contains(#".product(name: "MetalUISDL", package: "SDL", "# + portable))
    #expect(manifest.contains(#".product(name: "MetalUIPortableText", package: "MetalUI", "# + portable))
    #expect(manifest.contains(#".product(name: "MetalUISystemFonts", package: "MetalUI", "# + portable))
    let main = try file("Sources/MyApp/main.swift", in: files).contents
    #expect(main.contains("#if canImport(MetalUISDL)"))
    #expect(main.contains("App(platform: try SDLPlatform(), textSystem: { PortableTextSystem(resolver: resolver) })"))
    #expect(main.contains("return try App()"))
    #expect(try file("Packaging/linux/com.example.MyApp.desktop", in: files).contents.contains("Icon=com.example.MyApp\n"))
    #expect(try file("Packaging/windows/MyApp.rc", in: files).contents == "1 ICON \"MyApp.ico\"\n")
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

@Test func theCommandLineDefaultsToTheGitURLAndTheWorkingDirectory() throws {
    let command = try parseScaffoldCommand(["new", "MyApp"], workingDirectory: "/work")
    #expect(command == .new(ScaffoldOptions(name: "MyApp"), parentDirectory: "/work"))
}

@Test func theCommandLineResolvesRelativePathsAgainstTheWorkingDirectory() throws {
    let command = try parseScaffoldCommand(
        ["new", "MyApp", "--path", "apps", "--local", "../MetalUI", "--bundle-id", "dev.me.app", "--cross-platform"],
        workingDirectory: "/work/here")
    #expect(command == .new(ScaffoldOptions(name: "MyApp", bundleIdentifier: "dev.me.app",
                                            source: .local(path: "/work/MetalUI"), crossPlatform: true),
                            parentDirectory: "/work/here/apps"))
}

@Test func theCommandLineTakesAnotherURLAndBranch() throws {
    let command = try parseScaffoldCommand(["new", "MyApp", "--url", "https://example.com/fork.git",
                                            "--branch", "dev"], workingDirectory: "/w")
    #expect(command == .new(ScaffoldOptions(name: "MyApp", source: .remote(url: "https://example.com/fork.git",
                                                                           branch: "dev")),
                            parentDirectory: "/w"))
}

@Test func theCommandLineRefusesWhatItCannotMean() throws {
    for arguments in [[], ["make", "MyApp"], ["new"], ["new", "A", "B"], ["new", "A", "--path"],
                      ["new", "A", "--bogus"], ["new", "A", "--local", "/x", "--branch", "dev"]] {
        #expect(throws: ScaffoldError.self, "\(arguments)") {
            try parseScaffoldCommand(arguments, workingDirectory: "/w")
        }
    }
    #expect(try parseScaffoldCommand(["new", "A", "--help"], workingDirectory: "/w") == .help)
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
