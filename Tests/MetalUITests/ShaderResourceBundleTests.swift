import Testing
import Foundation
@testable import MetalUIRender

// App icon branch, the packaging fix (ruling `AI-N`): the shader resource
// bundle is found without SwiftPM's generated `Bundle.module`, whose accessor
// traps when the bundle is not where it looks, and a missing bundle throws
// `ShaderLibraryError.resourceMissing` naming every path tried. Tests R1–R6
// build a fake `.app` in a temporary directory and drive the internal seam
// (`ShaderLibrary.candidateDirectories(main:code:environment:)` and
// `ShaderLibrary.resourceBundle(candidates:)`) with it.

/// A fresh temporary directory, symlinks resolved (`/var` → `/private/var`).
private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("metalui-shader-bundle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

/// A minimal `MyApp.app` under `directory`: an `Info.plist` naming an
/// executable, the (empty) executable, and an empty `Contents/Resources`.
private func makeApp(in directory: URL) throws -> URL {
    let app = directory.appendingPathComponent("MyApp.app", isDirectory: true)
    let contents = app.appendingPathComponent("Contents", isDirectory: true)
    let fm = FileManager.default
    try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    try fm.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleExecutable": "MyApp",
        "CFBundleIdentifier": "com.example.metalui.shader-bundle-test.\(UUID().uuidString)",
        "CFBundlePackageType": "APPL",
        "CFBundleName": "MyApp",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    try Data().write(to: contents.appendingPathComponent("MacOS/MyApp"))
    return app
}

/// Puts an (empty) `MetalUI_MetalUIRender.bundle` directory in `directory`
/// and returns its URL.
@discardableResult
private func placeResourceBundle(in directory: URL) throws -> URL {
    let bundle = directory.appendingPathComponent(ShaderLibrary.resourceBundleName, isDirectory: true)
    try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Shaders"),
                                            withIntermediateDirectories: true)
    return bundle
}

private func path(_ url: URL) -> String {
    url.resolvingSymlinksInPath().standardizedFileURL.path
}

/// The bundle the seam resolves for a fake app whose main and code bundle are
/// both `app` (a statically linked executable).
private func resolve(app: URL, environment: [String: String] = [:]) throws -> Bundle {
    let main = try #require(Bundle(url: app), "the fake app is not a bundle")
    return try ShaderLibrary.resourceBundle(
        candidates: ShaderLibrary.candidateDirectories(main: main, code: main, environment: environment))
}

/// **R1** (`AI-N` item 1). A resource bundle in the app's `Contents/Resources`
/// — the only place `codesign` accepts it, on either build system — is found.
///
/// Mutation **MN1**: drop the `Bundle.main.resourceURL` candidate.
@Test func aResourceBundleInContentsResourcesIsFound() throws {
    let app = try makeApp(in: try temporaryDirectory())
    let expected = try placeResourceBundle(in: app.appendingPathComponent("Contents/Resources"))
    let main = try #require(Bundle(url: app))
    try #require(main.resourceURL.map(path) == path(app.appendingPathComponent("Contents/Resources")),
                 "the fake app's resourceURL is \(String(describing: main.resourceURL))")
    #expect(path(try resolve(app: app).bundleURL) == path(expected))
}

/// **R2** (`AI-N` item 1, the order). With a resource bundle both in
/// `Contents/Resources` and at the app's root, the one in `Contents/Resources`
/// wins — the default build system's accessor's own order, where the native
/// one looked only at the root.
///
/// Mutation **MN2**: the app root ahead of `Contents/Resources`.
@Test func contentsResourcesIsPreferredOverTheAppRoot() throws {
    let app = try makeApp(in: try temporaryDirectory())
    let resources = try placeResourceBundle(in: app.appendingPathComponent("Contents/Resources"))
    let root = try placeResourceBundle(in: app)
    try #require(path(resources) != path(root))
    #expect(path(try resolve(app: app).bundleURL) == path(resources))
}

/// **R3** (`AI-N` item 1). A bundle at the app's root alone is still found —
/// the command-line-tool candidate, `Bundle.main.bundleURL`, both accessors'
/// last — so R2's preference is an order, not an exclusion.
@Test func aResourceBundleAtTheAppRootAloneIsFound() throws {
    let app = try makeApp(in: try temporaryDirectory())
    let root = try placeResourceBundle(in: app)
    #expect(path(try resolve(app: app).bundleURL) == path(root))
}

/// **R4** (`AI-N` item 1). A bundle beside the executable
/// (`Contents/MacOS`, or a build directory's `swift run`) is found.
@Test func aResourceBundleBesideTheExecutableIsFound() throws {
    let app = try makeApp(in: try temporaryDirectory())
    let beside = try placeResourceBundle(in: app.appendingPathComponent("Contents/MacOS"))
    #expect(path(try resolve(app: app).bundleURL) == path(beside))
}

/// **R5** (`AI-N` item 2). Nothing found throws
/// `ShaderLibraryError.resourceMissing`, its message naming the bundle and
/// every directory tried — it does not trap.
///
/// Mutation **MN3**: `fatalError` in place of the throw (R6 catches it as an
/// exit; this test would truncate the run).
@Test func noResourceBundleThrowsResourceMissingNamingEveryPathTried() throws {
    let app = try makeApp(in: try temporaryDirectory())
    let main = try #require(Bundle(url: app))
    let candidates = ShaderLibrary.candidateDirectories(main: main, code: main, environment: [:])
    try #require(candidates.count >= 3, "candidates: \(candidates)")
    do {
        let found = try ShaderLibrary.resourceBundle(candidates: candidates)
        Issue.record("found \(found.bundleURL), expected resourceMissing")
    } catch let error as ShaderLibraryError {
        guard case .resourceMissing(let message) = error else {
            Issue.record("expected resourceMissing, got \(error)")
            return
        }
        #expect(message.contains(ShaderLibrary.resourceBundleName), "\(message)")
        for candidate in candidates {
            #expect(message.contains(candidate.path), "\(candidate.path) missing from: \(message)")
        }
        #expect(message.contains(path(app.appendingPathComponent("Contents/Resources"))), "\(message)")
    }
}

/// **R6** (`AI-N` item 2, mutation **MN3**'s instrument). In a child process,
/// a search over directories holding no bundle returns by throwing; a trap
/// would make the child exit with a failure.
@Test func aMissingResourceBundleThrowsRatherThanTraps() async {
    await #expect(processExitsWith: .success) {
        let nowhere = URL(fileURLWithPath: "/nonexistent-metalui-shader-bundle-\(getpid())")
        do {
            _ = try ShaderLibrary.resourceBundle(candidates: [nowhere])
            exit(2)
        } catch {
            exit(0)
        }
    }
}

/// **R7** (`AI-N` item 1). A debug build honours SwiftPM's own override,
/// `PACKAGE_RESOURCE_BUNDLE_PATH`, ahead of every other candidate, as the
/// default build system's accessor does.
@Test func theResourceBundlePathOverrideComesFirstInADebugBuild() throws {
    let directory = try temporaryDirectory()
    let app = try makeApp(in: directory)
    try placeResourceBundle(in: app.appendingPathComponent("Contents/Resources"))
    let overridden = directory.appendingPathComponent("override", isDirectory: true)
    let expected = try placeResourceBundle(in: overridden)
    let found = try resolve(app: app, environment: ["PACKAGE_RESOURCE_BUNDLE_PATH": overridden.path])
    #if DEBUG
    #expect(path(found.bundleURL) == path(expected))
    #else
    #expect(path(found.bundleURL) != path(expected))
    #endif
}
