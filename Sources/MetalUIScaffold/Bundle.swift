// `metalui bundle` (ruling BU-A): builds a SwiftPM executable product in release and lays it out
// as a signed macOS `.app` — the recipe `docs/packaging.md` explains, automated. A pure planner
// (`parseBundleCommand`, `bundlePlan`, `minimumMacOSVersion`) decides what goes where; a thin
// executor (`runBundle`) does it, with every process behind `BundleProcessRunner` so a test never
// runs `swift build`.
import Foundation

/// A command the executor runs: `executable` is looked up on the PATH.
package struct ProcessInvocation: Equatable, Sendable {
    package var executable: String
    package var arguments: [String]
    package var directory: String?
    /// `true` lets the child write to this process's own output (a long `swift build`).
    package var inheritsOutput: Bool

    package init(_ executable: String, _ arguments: [String], directory: String? = nil, inheritsOutput: Bool = false) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.inheritsOutput = inheritsOutput
    }
}

package struct ProcessResult: Equatable, Sendable {
    package var status: Int32
    /// Standard output (empty when the invocation inherited it).
    package var output: String

    package init(status: Int32, output: String = "") {
        self.status = status
        self.output = output
    }
}

package typealias BundleProcessRunner = (ProcessInvocation) -> ProcessResult

package struct BundleOptions: Equatable, Sendable {
    package var product: String
    package var bundleIdentifier: String
    /// Absolute path of a `.icns` or `.png`, or `nil`.
    package var icon: String?
    package var version: String
    /// Absolute path of the directory that receives `<Product>.app`.
    package var output: String
    /// Absolute path of the package to build.
    package var packagePath: String

    package var appPath: String { URL(fileURLWithPath: output).appendingPathComponent("\(product).app").path }
}

package enum BundleCommandError: Error, Equatable, CustomStringConvertible {
    case invalidProduct(String)
    case invalidVersion(String)
    case invalidIcon(String)
    case missingIcon(String)
    case missingExecutable(String)
    case failed(step: String, status: Int32)
    case unsupportedPlatform

    package var description: String {
        switch self {
        case let .invalidProduct(name): "invalid product name '\(name)': it must be non-empty with no '/' and not start with '-'"
        case let .invalidVersion(version): "invalid version '\(version)': use x, x.y or x.y.z (digits)"
        case let .invalidIcon(path): "unsupported icon '\(path)': use a .icns or a .png file"
        case let .missingIcon(path): "icon not found: \(path)"
        case let .missingExecutable(path): "the build produced no executable at \(path)"
        case let .failed(step, status): "\(step) failed (exit status \(status))"
        case .unsupportedPlatform: "metalui bundle builds a macOS .app and runs only on macOS"
        }
    }
}

package let bundleUsage = """
    usage: metalui bundle --product <Product> --bundle-id <id> [options]

    Builds the SwiftPM executable product in release and packs it as a signed
    macOS <output>/<Product>.app (macOS only; docs/packaging.md explains each step).

    options:
      --product <name>      the executable product to build (required)
      --bundle-id <id>      CFBundleIdentifier, e.g. com.example.MyApp (required)
      --icon <path>         a .icns (copied) or a .png (converted with sips and iconutil)
      --version <x.y.z>     CFBundleShortVersionString and CFBundleVersion (default 1.0)
      --output <dir>        the directory for the .app (default <package>/.build/bundle);
                            an existing <Product>.app there is replaced
      --package-path <dir>  the package to build (default: the current directory)
      -h, --help            show this help
    """

package enum BundleCommand: Equatable {
    case help
    case bundle(BundleOptions)
}

/// Parses the arguments after `bundle`. Paths resolve against `workingDirectory`.
package func parseBundleCommand(_ arguments: [String], workingDirectory: String) throws -> BundleCommand {
    var remaining = arguments[...]
    var product: String?
    var bundleIdentifier: String?
    var icon: String?
    var version = "1.0"
    var output: String?
    var packagePath = workingDirectory

    func value(for option: String) throws -> String {
        guard let next = remaining.popFirst(), !next.hasPrefix("-") else {
            throw ScaffoldError.usage("\(option) needs a value\n\n" + bundleUsage)
        }
        return next
    }
    while let argument = remaining.popFirst() {
        switch argument {
        case "-h", "--help": return .help
        case "--product": product = try value(for: argument)
        case "--bundle-id": bundleIdentifier = try value(for: argument)
        case "--icon": icon = absolute(try value(for: argument), in: workingDirectory)
        case "--version": version = try value(for: argument)
        case "--output": output = absolute(try value(for: argument), in: workingDirectory)
        case "--package-path": packagePath = absolute(try value(for: argument), in: workingDirectory)
        default: throw ScaffoldError.usage("unexpected argument '\(argument)'\n\n" + bundleUsage)
        }
    }
    guard let product else { throw ScaffoldError.usage("missing --product\n\n" + bundleUsage) }
    guard let bundleIdentifier else { throw ScaffoldError.usage("missing --bundle-id\n\n" + bundleUsage) }
    guard !product.isEmpty, !product.contains("/"), !product.hasPrefix("-") else {
        throw BundleCommandError.invalidProduct(product)
    }
    try validateBundleIdentifier(bundleIdentifier)
    let parts = version.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...3).contains(parts.count),
          parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy { ("0"..."9").contains($0) } }) else {
        throw BundleCommandError.invalidVersion(version)
    }
    if let icon {
        let ext = (icon as NSString).pathExtension.lowercased()
        guard ext == "icns" || ext == "png" else { throw BundleCommandError.invalidIcon(icon) }
    }
    let resolvedOutput = output ?? URL(fileURLWithPath: packagePath).appendingPathComponent(".build/bundle").path
    return .bundle(BundleOptions(product: product, bundleIdentifier: bundleIdentifier, icon: icon,
                                 version: version, output: resolvedOutput, packagePath: packagePath))
}

/// The macOS deployment target a manifest declares (`platforms: [.macOS(.v14)]` reads `14.0`,
/// `.macOS(.v10_15)` reads `10.15`, `.macOS("13.3")` reads `13.3`); `fallback` when it declares none.
package func minimumMacOSVersion(inManifest manifest: String, fallback: String = "14.0") -> String {
    guard let range = manifest.range(of: ".macOS(") else { return fallback }
    let rest = manifest[range.upperBound...]
    guard let close = rest.firstIndex(of: ")") else { return fallback }
    var argument = rest[..<close].trimmingCharacters(in: .whitespaces)
    if argument.hasPrefix("\""), argument.hasSuffix("\""), argument.count >= 2 {
        let version = String(argument.dropFirst().dropLast())
        return version.isEmpty ? fallback : version
    }
    guard argument.hasPrefix(".v") else { return fallback }
    argument.removeFirst(2)
    let numbers = argument.split(separator: "_")
    guard !numbers.isEmpty, numbers.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return fallback }
    return numbers.count == 1 ? "\(numbers[0]).0" : numbers.joined(separator: ".")
}

/// An `Info.plist`'s entries.
package struct BundleInfoPlist: Equatable, Sendable {
    package var strings: [String: String]
    package var highResolutionCapable: Bool

    /// XML property-list bytes.
    package func data() throws -> Data {
        var dictionary: [String: Any] = strings
        dictionary["NSHighResolutionCapable"] = highResolutionCapable
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}

/// A file or directory copy the executor performs, paths relative to the `.app` unless absolute.
package struct BundleCopy: Equatable, Sendable {
    package var source: String
    package var destination: String
}

/// What `metalui bundle` lays down, decided before anything is touched.
package struct BundlePlan: Equatable, Sendable {
    package var appPath: String
    /// Directories to create, relative to `appPath`.
    package var directories: [String]
    /// Copies; a destination is relative to `appPath`.
    package var copies: [BundleCopy]
    package var infoPlist: BundleInfoPlist
    /// Processes that turn a `.png` into the `.icns` copied afterwards (empty for an `.icns` or no icon).
    package var iconConversion: [ProcessInvocation]
    /// Scratch directory the conversion uses (removed afterwards), or `nil`.
    package var iconScratch: String?
    package var signing: ProcessInvocation
}

private let iconsetSizes = [16, 32, 128, 256, 512]

/// The plan for `options` given the build's `binPath` and the `*.bundle` names found there.
package func bundlePlan(_ options: BundleOptions, binPath: String, resourceBundles: [String],
                        minimumSystemVersion: String) -> BundlePlan {
    let app = options.appPath
    var copies = [BundleCopy(source: URL(fileURLWithPath: binPath).appendingPathComponent(options.product).path,
                             destination: "Contents/MacOS/\(options.product)")]
    for name in resourceBundles.sorted() {
        copies.append(BundleCopy(source: URL(fileURLWithPath: binPath).appendingPathComponent(name).path,
                                 destination: "Contents/Resources/\(name)"))
    }
    var strings = [
        "CFBundleExecutable": options.product,
        "CFBundleIdentifier": options.bundleIdentifier,
        "CFBundleName": options.product,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": options.version,
        "CFBundleVersion": options.version,
        "LSMinimumSystemVersion": minimumSystemVersion,
        "NSPrincipalClass": "NSApplication",
    ]
    var conversion: [ProcessInvocation] = []
    var scratch: String?
    if let icon = options.icon {
        strings["CFBundleIconFile"] = options.product
        let ext = (icon as NSString).pathExtension.lowercased()
        if ext == "png" {
            let iconset = URL(fileURLWithPath: options.output).appendingPathComponent("\(options.product).iconset").path
            let icns = URL(fileURLWithPath: iconset).deletingLastPathComponent()
                .appendingPathComponent("\(options.product).icns").path
            scratch = iconset
            for size in iconsetSizes {
                conversion.append(ProcessInvocation("sips", ["-z", "\(size)", "\(size)", icon, "--out", "\(iconset)/icon_\(size)x\(size).png"]))
                conversion.append(ProcessInvocation("sips", ["-z", "\(size * 2)", "\(size * 2)", icon, "--out", "\(iconset)/icon_\(size)x\(size)@2x.png"]))
            }
            conversion.append(ProcessInvocation("iconutil", ["-c", "icns", iconset, "-o", icns]))
            copies.append(BundleCopy(source: icns, destination: "Contents/Resources/\(options.product).icns"))
        } else {
            copies.append(BundleCopy(source: icon, destination: "Contents/Resources/\(options.product).icns"))
        }
    }
    return BundlePlan(appPath: app, directories: ["Contents/MacOS", "Contents/Resources"], copies: copies,
                      infoPlist: BundleInfoPlist(strings: strings, highResolutionCapable: true),
                      iconConversion: conversion, iconScratch: scratch,
                      signing: ProcessInvocation("codesign", ["--force", "--sign", "-", "--deep", app]))
}

/// Executes `options`: build, locate, plan, lay out, sign. Returns the `.app` path.
package func performBundle(_ options: BundleOptions, run: BundleProcessRunner) throws -> String {
    let fileManager = FileManager.default
    func require(_ step: String, _ invocation: ProcessInvocation) throws -> ProcessResult {
        let result = run(invocation)
        guard result.status == 0 else { throw BundleCommandError.failed(step: step, status: result.status) }
        return result
    }
    if let icon = options.icon, !fileManager.fileExists(atPath: icon) { throw BundleCommandError.missingIcon(icon) }

    let build = ["build", "-c", "release", "--product", options.product]
    _ = try require("swift build", ProcessInvocation("swift", build, directory: options.packagePath, inheritsOutput: true))
    let binResult = try require("swift build --show-bin-path",
                                ProcessInvocation("swift", build + ["--show-bin-path"], directory: options.packagePath))
    let binPath = binResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
    let executable = URL(fileURLWithPath: binPath).appendingPathComponent(options.product).path
    guard fileManager.isExecutableFile(atPath: executable) else { throw BundleCommandError.missingExecutable(executable) }

    let resourceBundles = ((try? fileManager.contentsOfDirectory(atPath: binPath)) ?? []).filter { $0.hasSuffix(".bundle") }
    let manifest = (try? String(contentsOfFile: URL(fileURLWithPath: options.packagePath)
        .appendingPathComponent("Package.swift").path, encoding: .utf8)) ?? ""
    let plan = bundlePlan(options, binPath: binPath, resourceBundles: resourceBundles,
                          minimumSystemVersion: minimumMacOSVersion(inManifest: manifest))

    if let scratch = plan.iconScratch {
        try? fileManager.removeItem(atPath: scratch)
        try fileManager.createDirectory(atPath: scratch, withIntermediateDirectories: true)
    }
    defer { if let scratch = plan.iconScratch { try? fileManager.removeItem(atPath: scratch) } }
    for invocation in plan.iconConversion { _ = try require(invocation.executable, invocation) }

    let app = URL(fileURLWithPath: plan.appPath)
    try? fileManager.removeItem(at: app)
    for directory in plan.directories {
        try fileManager.createDirectory(at: app.appendingPathComponent(directory), withIntermediateDirectories: true)
    }
    for copy in plan.copies {
        try fileManager.copyItem(atPath: copy.source, toPath: app.appendingPathComponent(copy.destination).path)
    }
    try plan.infoPlist.data().write(to: app.appendingPathComponent("Contents/Info.plist"))
    _ = try require("codesign", plan.signing)
    return plan.appPath
}

#if os(macOS)
/// Runs `invocation` through `/usr/bin/env` (PATH lookup).
package func runProcess(_ invocation: ProcessInvocation) -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [invocation.executable] + invocation.arguments
    if let directory = invocation.directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
    let pipe = Pipe()
    if !invocation.inheritsOutput { process.standardOutput = pipe }
    do { try process.run() } catch { return ProcessResult(status: 127) }
    let data = invocation.inheritsOutput ? Data() : pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ProcessResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
}
#else
package func runProcess(_ invocation: ProcessInvocation) -> ProcessResult { ProcessResult(status: 127) }
#endif

/// `metalui bundle`: on any platform but macOS an error and status 1.
package func runBundle(_ options: BundleOptions, run: BundleProcessRunner, platformIsMacOS: Bool = isMacOS,
                       output: (String) -> Void, error: (String) -> Void) -> Int32 {
    guard platformIsMacOS else {
        error("metalui: \(BundleCommandError.unsupportedPlatform)")
        return 1
    }
    do {
        output(try performBundle(options, run: run))
        return 0
    } catch let failure {
        error("metalui: \(failure)")
        return 1
    }
}

#if os(macOS)
package let isMacOS = true
#else
package let isMacOS = false
#endif
