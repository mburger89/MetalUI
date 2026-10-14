// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation

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

/// A directory of blobs built by `scripts/compile-app-shaders.py` (ruling
/// `GA-F`): `NAME.comp.{spv,msl,dxil,json}`, `NAME.vert.…`, `NAME.frag.…` and
/// `SOURCE.sha256`.
public struct SDLGPUShaderLibrary: Sendable {
    /// The directory the blobs are read from.
    public let directory: URL

    /// Opens `directory`, which must hold `SOURCE.sha256` (what the script
    /// writes beside the blobs; a directory without it does not count).
    public init(directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("SOURCE.sha256").path) else {
            throw SDLGPUShaderError(description: "\(directory.path) holds no SOURCE.sha256")
        }
        self.directory = directory
    }

    /// The directories an app's shaders are looked for, in order (ruling `GA-F`,
    /// `PX-P`'s order): `directoryName` beside the executable, then `sourceTree`.
    static func candidates(directoryName: String, sourceTree: URL?, executableDirectory: URL) -> [URL] {
        [executableDirectory.appendingPathComponent(directoryName)] + (sourceTree.map { [$0] } ?? [])
    }

    /// The first of `candidates` that holds `SOURCE.sha256`; none throws an error
    /// naming every directory tried.
    static func locate(from candidates: [URL]) throws -> SDLGPUShaderLibrary {
        for candidate in candidates {
            if let library = try? SDLGPUShaderLibrary(directory: candidate) { return library }
        }
        throw SDLGPUShaderError(description: "no app shader directory holds SOURCE.sha256; tried "
            + candidates.map(\.path).joined(separator: ", "))
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
