// `metalui bundle` (ruling BU-A). The planner and parser are pure and pinned as text; the executor
// runs against a fake process runner (no `swift build`); that the real command makes a signed app
// is the env-gated test at the bottom (`METALUI_RUN_BUNDLE_TEST=1`), which counts while skipped.
import Foundation
import Testing
@testable import MetalUIScaffold

private let cwd = "/work/pkg"

private func parse(_ arguments: [String]) throws -> BundleOptions {
    guard case let .bundle(options) = try parseBundleCommand(arguments, workingDirectory: cwd) else {
        throw ScaffoldError.usage("not a bundle command")
    }
    return options
}

private func options(icon: String? = nil) -> BundleOptions {
    BundleOptions(product: "Flow", bundleIdentifier: "com.example.Flow", icon: icon, version: "1.2.3",
                  output: "/out", packagePath: cwd)
}

private func plist(_ plan: BundlePlan) throws -> [String: Any] {
    let object = try PropertyListSerialization.propertyList(from: try plan.infoPlist.data(), format: nil)
    return try #require(object as? [String: Any])
}

// MARK: - Arguments

@Test func theMinimalCommandDefaultsVersionOutputAndPackagePath() throws {
    let parsed = try parse(["--product", "Flow", "--bundle-id", "com.example.Flow"])
    #expect(parsed == BundleOptions(product: "Flow", bundleIdentifier: "com.example.Flow", icon: nil,
                                    version: "1.0", output: "/work/pkg/.build/bundle", packagePath: cwd))
    #expect(parsed.appPath == "/work/pkg/.build/bundle/Flow.app")
}

@Test func everyOptionIsReadAndRelativePathsResolveAgainstTheWorkingDirectory() throws {
    let parsed = try parse(["--product", "Flow", "--bundle-id", "com.example.Flow", "--icon", "art/i.PNG",
                            "--version", "2.1", "--output", "dist", "--package-path", "../other"])
    #expect(parsed.icon == "/work/pkg/art/i.PNG")
    #expect(parsed.version == "2.1")
    #expect(parsed.output == "/work/pkg/dist")
    #expect(parsed.packagePath == "/work/other")
}

@Test func theDefaultOutputFollowsTheGivenPackagePath() throws {
    let parsed = try parse(["--product", "Flow", "--bundle-id", "com.example.Flow", "--package-path", "/elsewhere"])
    #expect(parsed.output == "/elsewhere/.build/bundle")
}

@Test func aMissingProductOrBundleIdentifierIsAUsageError() {
    #expect(throws: (any Error).self) { try parse(["--bundle-id", "com.example.Flow"]) }
    #expect(throws: (any Error).self) { try parse(["--product", "Flow"]) }
    do { _ = try parse(["--bundle-id", "com.example.Flow"]) } catch {
        #expect("\(error)".contains("missing --product"))
    }
    do { _ = try parse(["--product", "Flow"]) } catch {
        #expect("\(error)".contains("missing --bundle-id"))
    }
}

@Test func anOptionWithoutAValueAndAnUnknownArgumentAreRefused() {
    #expect(throws: (any Error).self) { try parse(["--product"]) }
    #expect(throws: (any Error).self) { try parse(["--product", "--bundle-id", "com.example.Flow"]) }
    #expect(throws: (any Error).self) { try parse(["--product", "Flow", "--bundle-id", "com.example.Flow", "--nope"]) }
}

@Test(arguments: ["icon.jpg", "icon", "icon.icns.txt", "icon.ico"])
func anIconThatIsNeitherIcnsNorPngIsRefused(_ icon: String) {
    #expect(throws: BundleCommandError.invalidIcon("/work/pkg/\(icon)")) {
        try parse(["--product", "Flow", "--bundle-id", "com.example.Flow", "--icon", icon])
    }
}

@Test(arguments: ["a.icns", "a.ICNS", "a.png"])
func anIcnsOrPngIconIsAccepted(_ icon: String) throws {
    #expect(try parse(["--product", "Flow", "--bundle-id", "com.example.Flow", "--icon", icon]).icon == "/work/pkg/\(icon)")
}

@Test(arguments: ["", "1.", "a.b", "1.2.3.4", "v1"])
func aMalformedVersionIsRefused(_ version: String) {
    #expect(throws: BundleCommandError.invalidVersion(version)) {
        try parse(["--product", "Flow", "--bundle-id", "com.example.Flow", "--version", version])
    }
}

@Test func aBadBundleIdentifierOrProductNameIsRefused() {
    #expect(throws: ScaffoldError.invalidBundleIdentifier("Flow")) { try parse(["--product", "Flow", "--bundle-id", "Flow"]) }
    #expect(throws: BundleCommandError.invalidProduct("a/b")) { try parse(["--product", "a/b", "--bundle-id", "com.example.Flow"]) }
}

@Test func theTopLevelParserRoutesBundleAndItsHelp() throws {
    let routed = try parseScaffoldCommand(["bundle", "--product", "Flow", "--bundle-id", "com.example.Flow"],
                                          workingDirectory: cwd, pinLookup: { _ in .unavailable("x") })
    #expect(routed == .bundle(options().with { $0.version = "1.0"; $0.output = "/work/pkg/.build/bundle" }))
    #expect(try parseScaffoldCommand(["bundle", "--help"], workingDirectory: cwd, pinLookup: { _ in .unavailable("x") }) == .bundleHelp)
}

private extension BundleOptions {
    func with(_ change: (inout BundleOptions) -> Void) -> BundleOptions { var copy = self; change(&copy); return copy }
}

// MARK: - Deployment target

@Test(arguments: [("platforms: [.macOS(.v14)],", "14.0"), ("platforms: [.iOS(.v17), .macOS(.v10_15)]", "10.15"),
                  ("platforms: [.macOS(\"13.3\")]", "13.3"), ("name: \"X\"", "14.0"), ("platforms: [.macOS(.v26)]", "26.0")])
func theMinimumSystemVersionComesFromTheManifest(_ manifest: String, _ expected: String) {
    #expect(minimumMacOSVersion(inManifest: manifest) == expected)
}

// MARK: - The plan

@Test func theInfoPlistCarriesEveryKeyTheRecipeNeeds() throws {
    let plan = bundlePlan(options(), binPath: "/bin", resourceBundles: [], minimumSystemVersion: "14.0")
    let values = try plist(plan)
    #expect(values["CFBundleExecutable"] as? String == "Flow")
    #expect(values["CFBundleIdentifier"] as? String == "com.example.Flow")
    #expect(values["CFBundleName"] as? String == "Flow")
    #expect(values["CFBundlePackageType"] as? String == "APPL")
    #expect(values["CFBundleShortVersionString"] as? String == "1.2.3")
    #expect(values["CFBundleVersion"] as? String == "1.2.3")
    #expect(values["LSMinimumSystemVersion"] as? String == "14.0")
    #expect(values["NSHighResolutionCapable"] as? Bool == true)
    #expect(values["NSPrincipalClass"] as? String == "NSApplication")
    #expect(values["CFBundleIconFile"] == nil, "no icon, no CFBundleIconFile")
}

@Test func theLayoutCopiesTheExecutableAndEveryResourceBundleIntoTheRightFolders() {
    let plan = bundlePlan(options(), binPath: "/bin", resourceBundles: ["Z_Z.bundle", "MetalUI_MetalUIRender.bundle"],
                          minimumSystemVersion: "14.0")
    #expect(plan.appPath == "/out/Flow.app")
    #expect(plan.directories == ["Contents/MacOS", "Contents/Resources"])
    #expect(plan.copies == [
        BundleCopy(source: "/bin/Flow", destination: "Contents/MacOS/Flow"),
        BundleCopy(source: "/bin/MetalUI_MetalUIRender.bundle", destination: "Contents/Resources/MetalUI_MetalUIRender.bundle"),
        BundleCopy(source: "/bin/Z_Z.bundle", destination: "Contents/Resources/Z_Z.bundle"),
    ])
    #expect(plan.iconConversion.isEmpty && plan.iconScratch == nil)
    #expect(plan.signing == ProcessInvocation("codesign", ["--force", "--sign", "-", "--deep", "/out/Flow.app"]))
}

@Test func anIcnsIconIsCopiedAndNamedInTheInfoPlist() throws {
    let plan = bundlePlan(options(icon: "/art/i.icns"), binPath: "/bin", resourceBundles: [], minimumSystemVersion: "14.0")
    #expect(try plist(plan)["CFBundleIconFile"] as? String == "Flow")
    #expect(plan.copies.last == BundleCopy(source: "/art/i.icns", destination: "Contents/Resources/Flow.icns"))
    #expect(plan.iconConversion.isEmpty)
}

@Test func aPngIconIsConvertedThroughAnIconsetOfTenSizesAndIconutil() throws {
    let plan = bundlePlan(options(icon: "/art/i.png"), binPath: "/bin", resourceBundles: [], minimumSystemVersion: "14.0")
    #expect(try plist(plan)["CFBundleIconFile"] as? String == "Flow")
    #expect(plan.iconConversion.count == 11)
    #expect(plan.iconConversion.prefix(10).allSatisfy { $0.executable == "sips" })
    #expect(plan.iconConversion[0] == ProcessInvocation("sips", ["-z", "16", "16", "/art/i.png", "--out", "/out/Flow.iconset/icon_16x16.png"]))
    #expect(plan.iconConversion[9].arguments.contains("/out/Flow.iconset/icon_512x512@2x.png"))
    #expect(plan.iconConversion[10] == ProcessInvocation("iconutil", ["-c", "icns", "/out/Flow.iconset", "-o", "/out/Flow.icns"]))
    #expect(plan.iconScratch == "/out/Flow.iconset")
    #expect(plan.copies.last == BundleCopy(source: "/out/Flow.icns", destination: "Contents/Resources/Flow.icns"))
}

// MARK: - The executor, with a fake runner

private func fakeBuild(into root: URL, resourceBundles: [String] = ["MetalUI_MetalUIRender.bundle"],
                       executable: Bool = true) throws -> (bin: URL, runner: BundleProcessRunner, log: Log) {
    let bin = root.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    if executable {
        let path = bin.appendingPathComponent("Flow")
        try Data("#!/bin/sh\n".utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }
    for name in resourceBundles {
        try FileManager.default.createDirectory(at: bin.appendingPathComponent(name), withIntermediateDirectories: true)
        try Data("shaders".utf8).write(to: bin.appendingPathComponent(name).appendingPathComponent("default.metallib"))
    }
    let log = Log()
    let runner: BundleProcessRunner = { invocation in
        log.invocations.append(invocation)
        if invocation.arguments.contains("--show-bin-path") { return ProcessResult(status: 0, output: bin.path + "\n") }
        if invocation.executable == "iconutil", let out = invocation.arguments.last {
            try? Data("icns".utf8).write(to: URL(fileURLWithPath: out))
        }
        return ProcessResult(status: log.failing == invocation.executable ? 3 : 0)
    }
    return (bin, runner, log)
}

private final class Log: @unchecked Sendable {
    var invocations: [ProcessInvocation] = []
    var failing: String?
}

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("metalui-bundle-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func theExecutorBuildsInReleaseThenLaysTheBundleOutAndSigns() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let (_, runner, log) = try fakeBuild(into: root)
    let opts = options().with { $0.output = root.appendingPathComponent("out").path; $0.packagePath = root.path }
    let app = try performBundle(opts, run: runner)

    #expect(app == root.appendingPathComponent("out/Flow.app").path)
    #expect(log.invocations.map(\.executable) == ["swift", "swift", "codesign"])
    #expect(log.invocations[0].arguments == ["build", "-c", "release", "--product", "Flow"])
    #expect(log.invocations[0].directory == root.path && log.invocations[0].inheritsOutput)
    #expect(log.invocations[1].arguments == ["build", "-c", "release", "--product", "Flow", "--show-bin-path"])
    let fileManager = FileManager.default
    #expect(fileManager.isExecutableFile(atPath: app + "/Contents/MacOS/Flow"))
    #expect(fileManager.fileExists(atPath: app + "/Contents/Resources/MetalUI_MetalUIRender.bundle/default.metallib"))
    let info = try #require(NSDictionary(contentsOfFile: app + "/Contents/Info.plist"))
    #expect(info["CFBundleIdentifier"] as? String == "com.example.Flow")
    #expect(info["LSMinimumSystemVersion"] as? String == "14.0", "no manifest: the fallback")
}

@Test func anExistingBundleIsReplacedNotMerged() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let (_, runner, _) = try fakeBuild(into: root)
    let opts = options().with { $0.output = root.path + "/out"; $0.packagePath = root.path }
    let stale = root.appendingPathComponent("out/Flow.app/Contents/Resources/stale.txt")
    try FileManager.default.createDirectory(at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("old".utf8).write(to: stale)
    _ = try performBundle(opts, run: runner)
    #expect(!FileManager.default.fileExists(atPath: stale.path))
}

@Test func aPngIconRunsTheConversionAndShipsTheIcns() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let (_, runner, log) = try fakeBuild(into: root)
    let png = root.appendingPathComponent("i.png")
    try Data("png".utf8).write(to: png)
    let opts = options(icon: png.path).with { $0.output = root.path + "/out"; $0.packagePath = root.path }
    let app = try performBundle(opts, run: runner)
    #expect(log.invocations.map(\.executable).filter { $0 == "sips" }.count == 10)
    #expect(log.invocations.contains { $0.executable == "iconutil" })
    #expect(try String(contentsOfFile: app + "/Contents/Resources/Flow.icns", encoding: .utf8) == "icns")
    #expect(!FileManager.default.fileExists(atPath: root.path + "/out/Flow.iconset"), "scratch iconset removed")
}

@Test func aMissingIconFileFailsBeforeAnythingIsBuilt() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let (_, runner, log) = try fakeBuild(into: root)
    #expect(throws: BundleCommandError.missingIcon("/nope/i.icns")) {
        try performBundle(options(icon: "/nope/i.icns"), run: runner)
    }
    #expect(log.invocations.isEmpty)
}

@Test func aFailingBuildOrSignatureIsReportedWithItsStep() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let opts = options().with { $0.output = root.path + "/out"; $0.packagePath = root.path }
    let (_, buildFails, log) = try fakeBuild(into: root)
    log.failing = "swift"
    #expect(throws: BundleCommandError.failed(step: "swift build", status: 3)) { try performBundle(opts, run: buildFails) }
    log.failing = "codesign"
    #expect(throws: BundleCommandError.failed(step: "codesign", status: 3)) { try performBundle(opts, run: buildFails) }
}

@Test func aBuildThatProducedNoExecutableIsReported() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let (bin, runner, _) = try fakeBuild(into: root, executable: false)
    let opts = options().with { $0.output = root.path + "/out"; $0.packagePath = root.path }
    #expect(throws: BundleCommandError.missingExecutable(bin.path + "/Flow")) { try performBundle(opts, run: runner) }
}

@Test func theManifestsPlatformSetsTheMinimumSystemVersion() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("platforms: [.macOS(.v13)]".utf8).write(to: root.appendingPathComponent("Package.swift"))
    let (_, runner, _) = try fakeBuild(into: root)
    let opts = options().with { $0.output = root.path + "/out"; $0.packagePath = root.path }
    let app = try performBundle(opts, run: runner)
    #expect(NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["LSMinimumSystemVersion"] as? String == "13.0")
}

// MARK: - Platform and the top-level entry

@Test func offMacOSTheCommandPrintsAnErrorAndFailsWithoutRunningAnything() {
    var errors: [String] = []
    let log = Log()
    let status = runBundle(options(), run: { log.invocations.append($0); return ProcessResult(status: 0) },
                           platformIsMacOS: false, output: { _ in }, error: { errors.append($0) })
    #expect(status == 1 && log.invocations.isEmpty)
    #expect(errors.joined().contains("only on macOS"))
}

@Test func runScaffoldRoutesBundleToTheRunnerAndPrintsThePath() throws {
    #if os(macOS)
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let (_, runner, _) = try fakeBuild(into: root)
    var printed: [String] = []
    let status = runScaffold(["bundle", "--product", "Flow", "--bundle-id", "com.example.Flow", "--output", "out"],
                             workingDirectory: root.path, processRunner: runner,
                             output: { printed.append($0) }, error: { Issue.record("\($0)") })
    #expect(status == 0)
    #expect(printed == [root.appendingPathComponent("out/Flow.app").path])
    #endif
}

// MARK: - The end-to-end bundle (env-gated)

/// BU-A: the real command bundles a tiny package and the result is a signed `.app` that
/// `codesign --verify` accepts. Off by default (a release build). Counts while skipped.
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_BUNDLE_TEST"] == "1"))
func theRealCommandProducesASignedAppThatVerifies() throws {
    #if os(macOS)
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("""
        // swift-tools-version:6.0
        import PackageDescription
        let package = Package(name: "Tiny", platforms: [.macOS(.v14)],
            targets: [.executableTarget(name: "Tiny")])
        """.utf8).write(to: root.appendingPathComponent("Package.swift"))
    let sources = root.appendingPathComponent("Sources/Tiny")
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    try Data("print(\"hi\")\n".utf8).write(to: sources.appendingPathComponent("main.swift"))

    var printed: [String] = []
    let status = runScaffold(["bundle", "--product", "Tiny", "--bundle-id", "com.example.Tiny",
                              "--package-path", root.path], workingDirectory: root.path,
                             output: { printed.append($0) }, error: { Issue.record("\($0)") })
    #expect(status == 0)
    let app = try #require(printed.last)
    #expect(app == root.appendingPathComponent(".build/bundle/Tiny.app").path)
    #expect(FileManager.default.isExecutableFile(atPath: app + "/Contents/MacOS/Tiny"))
    let verify = runProcess(ProcessInvocation("codesign", ["--verify", "--strict", app]))
    #expect(verify.status == 0, "codesign --verify")
    #endif
}
