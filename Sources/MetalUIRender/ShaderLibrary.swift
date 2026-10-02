import Foundation
import Metal

/// Why the shader library could not be built.
public enum ShaderLibraryError: Error, CustomStringConvertible {
    case resourceMissing(String)
    case compilationFailed(String)

    public var description: String {
        switch self {
        case .resourceMissing(let name):
            "MetalUI shader resource missing from bundle: \(name)"
        case .compilationFailed(let message):
            "MetalUI shader compilation failed: \(message)"
        }
    }
}

/// Builds the Metal library at run time.
///
/// SwiftPM's default build system has no Metal build rule — a `.metal` file
/// beside Swift sources produces no metallib and only an "unhandled files"
/// warning — so shaders ship as resources and compile here instead. See spec 7.2.
public enum ShaderLibrary {
    /// The shared C header concatenated ahead of the Metal source.
    ///
    /// `MTLCompileOptions` exposes no include search path, so `#include` cannot
    /// be relied on from a runtime-compiled source string. Prepending is the
    /// supported route. The sources are read from ``resourceBundleName``,
    /// found by ``candidateDirectories(main:code:environment:)`` rather than
    /// SwiftPM's trapping `Bundle.module` (`AI-N`).
    ///
    /// - Throws: ``ShaderLibraryError/resourceMissing(_:)`` when the resource
    ///   bundle or a source in it is missing.
    public static func combinedSource() throws -> String {
        let bundle = try resourceBundle(
            candidates: candidateDirectories(main: .main, code: Bundle(for: BundleFinder.self),
                                             environment: ProcessInfo.processInfo.environment))

        guard let headerURL = bundle.url(forResource: "Shaders/MetalUIShaderTypes",
                                         withExtension: "h") else {
            throw ShaderLibraryError.resourceMissing("Shaders/MetalUIShaderTypes.h")
        }
        guard let shaderURL = bundle.url(forResource: "Shaders/shaders",
                                         withExtension: "metal") else {
            throw ShaderLibraryError.resourceMissing("Shaders/shaders.metal")
        }

        let header = try String(contentsOf: headerURL, encoding: .utf8)
        let shaders = try String(contentsOf: shaderURL, encoding: .utf8)
        return header + "\n" + shaders
    }

    /// The resource bundle SwiftPM builds for this target, holding the shader
    /// sources.
    static let resourceBundleName = "MetalUI_MetalUIRender.bundle"

    /// The directories searched for ``resourceBundleName``, in order (`AI-N`).
    ///
    /// SwiftPM's generated `Bundle.module` accessor is not used: when the
    /// bundle is not where it looks it calls `fatalError`, and the two build
    /// systems look in different places — Swift 6.4's default one in
    /// `Bundle.main.resourceURL`, the code's bundle's resources and
    /// `Bundle.main.bundleURL`; `--build-system native` only in
    /// `Bundle.main.bundleURL` (a `.app`'s root, which `codesign` refuses) and
    /// the absolute build directory. This list is the union, so a packaged
    /// `.app` built either way finds its bundle in `Contents/Resources`:
    /// 1. in a debug build, SwiftPM's own `PACKAGE_RESOURCE_BUNDLE_PATH`
    ///    (or `…_URL`) override;
    /// 2. `main.resourceURL` — an app's `Contents/Resources`;
    /// 3. `code.resourceURL` — a framework's resources;
    /// 4. `main.bundleURL` — a command-line tool's directory, an app's root;
    /// 5. the directory holding `main`'s executable;
    /// 6. the directory holding `code`'s bundle — beside a test bundle in a
    ///    build directory;
    /// 7. in a debug build, this package's build directories under both build
    ///    systems (`.build/<triple>/debug`, `.build/out/Products/Debug`).
    ///
    /// A directory already listed is not repeated.
    static func candidateDirectories(main: Bundle, code: Bundle,
                                     environment: [String: String]) -> [URL] {
        var candidates: [URL?] = []
        #if DEBUG
        if let override = environment["PACKAGE_RESOURCE_BUNDLE_PATH"]
            ?? environment["PACKAGE_RESOURCE_BUNDLE_URL"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        #endif
        candidates += [
            main.resourceURL,
            code.resourceURL,
            main.bundleURL,
            main.executableURL?.deletingLastPathComponent(),
            code.bundleURL.deletingLastPathComponent(),
        ]
        #if DEBUG
        candidates += debugBuildDirectories()
        #endif

        var seen = Set<String>()
        return candidates.compactMap { $0 }.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    #if DEBUG
    /// This package's debug build directories, as the native build system's
    /// accessor bakes in its own: the package root is three components above
    /// this file (`Sources/MetalUIRender/ShaderLibrary.swift`).
    private static func debugBuildDirectories() -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let build = root.appendingPathComponent(".build", isDirectory: true)
        #if arch(arm64)
        let triple = "arm64-apple-macosx"
        #else
        let triple = "x86_64-apple-macosx"
        #endif
        return [
            build.appendingPathComponent("\(triple)/debug", isDirectory: true),
            build.appendingPathComponent("out/Products/Debug", isDirectory: true),
        ]
    }
    #endif

    /// The first ``resourceBundleName`` found in `candidates`, in order.
    ///
    /// - Throws: ``ShaderLibraryError/resourceMissing(_:)`` naming the bundle
    ///   and every directory tried, when none holds it — never a trap (`AI-N`).
    static func resourceBundle(candidates: [URL]) throws -> Bundle {
        for directory in candidates {
            let url = directory.appendingPathComponent(resourceBundleName, isDirectory: true)
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        let tried = candidates.map(\.path).joined(separator: ", ")
        throw ShaderLibraryError.resourceMissing(
            "\(resourceBundleName) (not found in any of: \(tried))")
    }

    /// Compiles the bundled shaders, with the shared type header prepended,
    /// into a library on `device`.
    public static func make(device: any MTLDevice) throws -> any MTLLibrary {
        let source = try combinedSource()
        do {
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw ShaderLibraryError.compilationFailed("\(error)")
        }
    }
}

/// A class in this module, so `Bundle(for:)` finds the bundle holding its code.
private final class BundleFinder {}
