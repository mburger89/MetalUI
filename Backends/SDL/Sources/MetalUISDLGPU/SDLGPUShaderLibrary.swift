// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation
import MetalUIShaderCompile

/// A shader the library could not give (ruling `GA-F`): the message names the
/// file, directory or driver.
public struct SDLGPUShaderError: Error, CustomStringConvertible, Sendable {
    /// What is missing or malformed.
    public let description: String
}

/// One compiled stage for one driver, with the counts SDL's pipeline
/// descriptions need, read from the reflection JSON beside it so the app never
/// counts by hand (ruling `GA-F`).
public struct SDLGPUShaderBlob: Sendable {
    /// The stage, from the file suffix.
    public enum Stage: Sendable { case vertex, fragment, compute }
    /// The file stem, e.g. `append.comp`.
    public let name: String
    /// The stage.
    public let stage: Stage
    /// The compiled bytes: SPIR-V, MSL source or DXIL, by driver.
    public let bytes: [UInt8]
    /// The `SDL_GPUShaderFormat` bit of ``bytes``.
    public let format: UInt32
    /// The entry point: `main0` in MSL, `main` otherwise.
    public let entryPoint: String
    /// Samplers the shader declares.
    public let samplers: Int
    /// Read-only storage textures (a graphics stage's `storage_textures`).
    public let readOnlyStorageTextures: Int
    /// Read-only storage buffers (a graphics stage's `storage_buffers`).
    public let readOnlyStorageBuffers: Int
    /// Read-write storage textures (compute only).
    public let readWriteStorageTextures: Int
    /// Read-write storage buffers (compute only).
    public let readWriteStorageBuffers: Int
    /// Uniform buffers.
    public let uniformBuffers: Int
    /// The thread group size (compute only; 0 for a graphics stage).
    public let threadCount: (x: Int, y: Int, z: Int)
}

/// A directory of blobs built by `MetalUICompileShaders` (the `compile-shaders`
/// command plugin; rulings `GA-F`, `BS-B`): `NAME.comp.{spv,msl,dxil,json}`,
/// `NAME.vert.…`, `NAME.frag.…` and, unless the build omitted it, `SOURCE.sha256`.
/// The directory comes from the `compile-shaders` command plugin (checked in or
/// shipped beside the executable) or from the `CompileShadersOnBuild` build-tool
/// plugin, which puts it in the target's resource bundle (``locate(directoryName:resourceBundle:sourceTree:)``,
/// ruling `BT-H`).
public struct SDLGPUShaderLibrary: Sendable {
    /// The directory the blobs are read from.
    public let directory: URL

    /// Opens `directory`, which must hold `SOURCE.sha256` (what the tool writes
    /// beside the blobs) **or** at least one `NAME.<vert|frag|comp>.json`
    /// reflection file, the last thing the tool writes for a stage (ruling
    /// `BS-E`): a build product made on the spot is never stale, so it needs no
    /// marker. A directory with neither does not count. Reads no source.
    public init(directory: URL) throws {
        let manager = FileManager.default
        let hasMarker = manager.fileExists(atPath: directory.appendingPathComponent("SOURCE.sha256").path)
        let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        let hasReflection = names.contains { name in
            ["vert", "frag", "comp"].contains { name.hasSuffix(".\($0).json") && name.count > ".\($0).json".count }
        }
        guard hasMarker || hasReflection else {
            throw SDLGPUShaderError(description:
                "\(directory.path) holds no SOURCE.sha256 and no NAME.<vert|frag|comp>.json reflection file")
        }
        self.directory = directory
    }

    /// Opens `directory` as ``init(directory:)`` does, then, **when it holds a
    /// `SOURCE.sha256`**, checks it against `sources` (ruling `BS-E`, `GA-Q`'s
    /// staleness detector): every `NAME.<vert|frag|comp>.hlsl` there must hash to
    /// its line, have one, and no line may stand without its source, each a named
    /// error. Without a marker nothing is compared.
    public init(directory: URL, verifyingSources sources: URL) throws {
        try self.init(directory: directory)
        let markerURL = directory.appendingPathComponent("SOURCE.sha256")
        guard let marker = try? String(contentsOf: markerURL, encoding: .utf8) else { return }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: sources.path) else {
            throw SDLGPUShaderError(description: "cannot read the shader sources in \(sources.path)")
        }
        let listed = try names.filter { ShaderSource(fileName: $0) != nil }.map { name in
            (name: name, bytes: [UInt8](try Data(contentsOf: sources.appendingPathComponent(name))))
        }
        let problems = SourceMarker.problems(marker: marker, sources: listed)
        guard problems.isEmpty else {
            throw SDLGPUShaderError(description: "\(markerURL.path) is stale: " + problems.joined(separator: "; "))
        }
    }

    /// The directories an app's shaders are looked for, in order (ruling `GA-F`,
    /// `PX-P`'s order): `directoryName` beside the executable, then `sourceTree`.
    static func candidates(directoryName: String, sourceTree: URL?, executableDirectory: URL) -> [URL] {
        [executableDirectory.appendingPathComponent(directoryName)] + (sourceTree.map { [$0] } ?? [])
    }

    /// The first of `candidates` that opens (a `SOURCE.sha256` or a reflection file, `BS-E`);
    /// none throws an error naming every directory tried.
    static func locate(from candidates: [URL]) throws -> SDLGPUShaderLibrary {
        for candidate in candidates {
            if let library = try? SDLGPUShaderLibrary(directory: candidate) { return library }
        }
        throw SDLGPUShaderError(description: "no app shader directory holds SOURCE.sha256 or a reflection file; tried "
            + candidates.map(\.path).joined(separator: ", "))
    }

    /// A candidate directory computed only when the search reaches it.
    typealias LazyCandidate = () -> URL?

    /// The first of `candidates`, evaluated in order and only until one opens, that
    /// opens; none throws an error naming every directory **evaluated** (a
    /// bundle never reached is not named; ruling `BT-H`).
    static func locate(lazily candidates: [LazyCandidate]) throws -> SDLGPUShaderLibrary {
        var tried: [String] = []
        for candidate in candidates {
            guard let url = candidate() else { continue }
            if let library = try? SDLGPUShaderLibrary(directory: url) { return library }
            tried.append(url.path)
        }
        throw SDLGPUShaderError(description: "no app shader directory holds SOURCE.sha256 or a reflection file; tried "
            + tried.joined(separator: ", "))
    }

    /// The candidates of ``locate(directoryName:resourceBundle:sourceTree:)``: beside the
    /// executable, the bundle's `directoryName` resource (else its `resourceURL` joined with
    /// the name), `sourceTree`. The bundle is read only when the first fails.
    static func lazyCandidates(directoryName: String, resourceBundle: @escaping () -> Bundle?, sourceTree: URL?,
                               executableDirectory: URL) -> [LazyCandidate] {
        [{ executableDirectory.appendingPathComponent(directoryName) },
         { guard let bundle = resourceBundle() else { return nil }
           return bundle.url(forResource: directoryName, withExtension: nil)
               ?? bundle.resourceURL?.appendingPathComponent(directoryName) },
         { sourceTree }]
    }

    /// Finds the app's shaders when a build-tool plugin put them in a resource bundle
    /// (ruling `BT-H`): `directoryName` **beside the executable first** (an explicit
    /// placement wins), then the bundle's, then `sourceTree`. Call it as
    /// `SDLGPUShaderLibrary.locate(resourceBundle: .module)`. `resourceBundle` is evaluated
    /// **only when the first candidate fails**, because SwiftPM's generated `Bundle.module`
    /// traps when its bundle is missing. None found throws an error naming every directory tried.
    public static func locate(directoryName: String = "MetalUIAppShaders", resourceBundle: @autoclosure () -> Bundle?,
                              sourceTree: URL? = nil) throws -> SDLGPUShaderLibrary {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? ".")
        let bundle = resourceBundle
        return try withoutActuallyEscaping(bundle) { escapable in
            try locate(lazily: lazyCandidates(directoryName: directoryName, resourceBundle: escapable, sourceTree: sourceTree,
                                              executableDirectory: executable.deletingLastPathComponent()))
        }
    }

    /// Finds the app's shaders (ruling `GA-F`): `directoryName` (default
    /// `MetalUIAppShaders`) **beside the executable first**, so a built app can be
    /// moved, then `sourceTree`, the directory the app passes for a build from
    /// source (typically `#filePath`-relative, spelled by the app). None throws an
    /// error naming both.
    public static func locate(directoryName: String = "MetalUIAppShaders", sourceTree: URL? = nil) throws -> SDLGPUShaderLibrary {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? ".")
        return try locate(from: candidates(directoryName: directoryName, sourceTree: sourceTree,
                                           executableDirectory: executable.deletingLastPathComponent()))
    }

    /// The compute stage `NAME.comp` for `device`'s driver.
    public func compute(_ name: String, for device: SDLGPUDevice) throws -> SDLGPUShaderBlob {
        try compute(name, driver: device.driver)
    }

    /// The vertex stage `NAME.vert` for `device`'s driver.
    public func vertex(_ name: String, for device: SDLGPUDevice) throws -> SDLGPUShaderBlob {
        try vertex(name, driver: device.driver)
    }

    /// The fragment stage `NAME.frag` for `device`'s driver.
    public func fragment(_ name: String, for device: SDLGPUDevice) throws -> SDLGPUShaderBlob {
        try fragment(name, driver: device.driver)
    }

    /// The compute stage for a driver named as `SDL_GetGPUDeviceDriver` spells it.
    public func compute(_ name: String, driver: String) throws -> SDLGPUShaderBlob {
        try load(name, suffix: "comp", stage: .compute, driver: driver)
    }

    /// The vertex stage for a driver named as `SDL_GetGPUDeviceDriver` spells it.
    public func vertex(_ name: String, driver: String) throws -> SDLGPUShaderBlob {
        try load(name, suffix: "vert", stage: .vertex, driver: driver)
    }

    /// The fragment stage for a driver named as `SDL_GetGPUDeviceDriver` spells it.
    public func fragment(_ name: String, driver: String) throws -> SDLGPUShaderBlob {
        try load(name, suffix: "frag", stage: .fragment, driver: driver)
    }

    private func load(_ name: String, suffix: String, stage: SDLGPUShaderBlob.Stage, driver: String) throws -> SDLGPUShaderBlob {
        let (extensionName, entry, format): (String, String, UInt32)
        switch driver {
        case "metal": (extensionName, entry, format) = ("msl", "main0", UInt32(SDL_GPU_SHADERFORMAT_MSL))
        case "vulkan": (extensionName, entry, format) = ("spv", "main", UInt32(SDL_GPU_SHADERFORMAT_SPIRV))
        case "direct3d12": (extensionName, entry, format) = ("dxil", "main", UInt32(SDL_GPU_SHADERFORMAT_DXIL))
        default: throw SDLGPUShaderError(description: "no compiled shader format for driver \"\(driver)\"")
        }
        let stem = "\(name).\(suffix)"
        let blobURL = directory.appendingPathComponent("\(stem).\(extensionName)")
        let reflectionURL = directory.appendingPathComponent("\(stem).json")
        guard let data = try? Data(contentsOf: blobURL) else {
            throw SDLGPUShaderError(description: "\(blobURL.path) is missing")
        }
        guard let json = try? Data(contentsOf: reflectionURL) else {
            throw SDLGPUShaderError(description: "\(reflectionURL.path) is missing")
        }
        guard let reflection = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else {
            throw SDLGPUShaderError(description: "\(reflectionURL.path) is not a JSON object")
        }
        func count(_ keys: String...) -> Int {
            for key in keys { if let value = reflection[key] as? Int { return value } }
            return 0
        }
        return SDLGPUShaderBlob(
            name: stem, stage: stage, bytes: [UInt8](data), format: format, entryPoint: entry,
            samplers: count("samplers"),
            readOnlyStorageTextures: count("readonly_storage_textures", "storage_textures"),
            readOnlyStorageBuffers: count("readonly_storage_buffers", "storage_buffers"),
            readWriteStorageTextures: count("readwrite_storage_textures"),
            readWriteStorageBuffers: count("readwrite_storage_buffers"),
            uniformBuffers: count("uniform_buffers"),
            threadCount: (count("threadcount_x"), count("threadcount_y"), count("threadcount_z")))
    }
}
#endif
