// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation
import MetalUISDL

/// The compute limits an app can rely on (ruling `DL-C`).
///
/// **These are guaranteed floors, not the device's real limits.** SDL_GPU
/// documents no limit query: `SDL_gpu.h` has no storage-buffer size, no
/// workgroup count and no per-limit property (SDL 3.4.18; its only guarantees
/// concern texture formats). So every value is a minimum valid on all three
/// backends: size work to it, or find a larger real limit by running. A real
/// device usually allows more. ``areGuaranteedFloors`` is `true` in this build.
///
/// The floors are the Vulkan specification's required limits (its "Required
/// Limits" table: `maxStorageBufferRange` 2^27 and `maxComputeWorkGroupCount`
/// (65535, 65535, 65535), re-read from the registry) which Direct3D 12 (a
/// dispatch of 65 535 groups per dimension, a 128 MiB minimum resource size)
/// and Metal (a larger dispatch and buffer length) meet; the D3D12 and Metal
/// figures are recalled, not re-read.
public struct SDLGPUDeviceLimits: Equatable, Sendable {
    /// Three counts, one per dispatch dimension.
    public struct Dimensions: Equatable, Sendable {
        /// The x count.
        public var x: Int
        /// The y count.
        public var y: Int
        /// The z count.
        public var z: Int
        /// A value per dimension.
        public init(x: Int, y: Int, z: Int) { self.x = x; self.y = y; self.z = z }
    }

    /// The largest storage buffer range a shader may bind, in bytes: 2^27 (134 217 728).
    public var maxStorageBufferBindingBytes: Int
    /// The most workgroups one dispatch may launch per dimension: 65 535 each.
    public var maxComputeWorkgroupCount: Dimensions
    /// `true` when the values are the documented guaranteed minimums rather
    /// than what the device allows; always `true` in this build.
    public var areGuaranteedFloors: Bool

    /// The guaranteed floors every SDL_GPU backend meets.
    public static let guaranteedFloors = SDLGPUDeviceLimits(
        maxStorageBufferBindingBytes: 1 << 27,
        maxComputeWorkgroupCount: Dimensions(x: 65_535, y: 65_535, z: 65_535),
        areGuaranteedFloors: true)
}

/// The software-rasterizer heuristic behind ``SDLGPUDevice/isSoftwareRasterizer`` (ruling `DL-B`).
enum SDLGPUDeviceInfo {
    /// Lowercased substrings that name a software rasterizer in SDL's
    /// device strings (llvmpipe and lavapipe are Mesa's, softpipe Mesa's
    /// reference, SwiftShader Google's, "Microsoft Basic Render Driver" is
    /// Windows' software adapter).
    static let softwareSubstrings = ["llvmpipe", "lavapipe", "softpipe", "swiftshader", "microsoft basic render driver"]

    /// Whether the strings name a software rasterizer. `warp` (Direct3D 12's
    /// software adapter) matches only as a whole word, so "warpath" does not.
    /// `"metal"` is never software (ruling `DL-B`).
    package static func looksSoftware(adapterName: String?, driverName: String?, driverInfo: String?,
                                      backend: String) -> Bool {
        if backend.lowercased() == "metal" { return false }
        for text in [adapterName, driverName, driverInfo] {
            guard let lowered = text?.lowercased() else { continue }
            if softwareSubstrings.contains(where: { lowered.contains($0) }) { return true }
            let words = lowered.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            if words.contains("warp") { return true }
        }
        return false
    }
}

extension SDLGPUDevice {
    /// One string property of the device (`SDL_GetGPUDeviceProperties`, since
    /// SDL 3.4.0, safe from any thread); `nil` when the property is absent or
    /// empty. Read per call, never cached (ruling `DL-D`).
    private func string(_ key: UnsafePointer<CChar>) -> String? {
        let properties = SDL_GetGPUDeviceProperties(raw)
        guard properties != 0, let text = SDL_GetStringProperty(properties, key, nil) else { return nil }
        let value = String(cString: text)
        return value.isEmpty ? nil : value
    }

    /// The adapter's name (`SDL_PROP_GPU_DEVICE_NAME_STRING`), for example
    /// `llvmpipe (LLVM 15.0.4, 256 bits)` or `Apple M3`. SDL says it "has no
    /// standardized format ... Do not attempt to parse": show it, never branch
    /// on it (use ``isSoftwareRasterizer``). `nil` when SDL gives none.
    public var adapterName: String? { string(SDL_PROP_GPU_DEVICE_NAME_STRING) }

    /// The driver's name (`SDL_PROP_GPU_DEVICE_DRIVER_NAME_STRING`), or `nil`.
    public var driverName: String? { string(SDL_PROP_GPU_DEVICE_DRIVER_NAME_STRING) }

    /// The driver's version (`SDL_PROP_GPU_DEVICE_DRIVER_VERSION_STRING`), or `nil`.
    public var driverVersion: String? { string(SDL_PROP_GPU_DEVICE_DRIVER_VERSION_STRING) }

    /// The driver's extra information (`SDL_PROP_GPU_DEVICE_DRIVER_INFO_STRING`),
    /// returned as SDL gave it (it may span several lines), or `nil`.
    public var driverInfo: String? { string(SDL_PROP_GPU_DEVICE_DRIVER_INFO_STRING) }

    /// Whether the device looks like a CPU software rasterizer (llvmpipe or
    /// lavapipe, softpipe, SwiftShader, Direct3D 12's WARP and "Microsoft Basic
    /// Render Driver"), so an app can pick smaller chunks or say so in a bug
    /// report. **A heuristic over SDL's unstable strings** (case-insensitive
    /// substrings of the adapter name, driver name and driver info; `warp` as a
    /// whole word): `false` means "not recognised", not "hardware". Metal always
    /// answers `false`: SDL exposes no software Metal device. Owned and borrowed
    /// devices answer alike (ruling `DL-F`).
    public var isSoftwareRasterizer: Bool {
        SDLGPUDeviceInfo.looksSoftware(adapterName: adapterName, driverName: driverName,
                                       driverInfo: driverInfo, backend: driver)
    }

    /// The compute limits to size work against: SDL_GPU's **guaranteed
    /// floors**, not the device's real limits (SDL has no query; see
    /// ``SDLGPUDeviceLimits``).
    public var limits: SDLGPUDeviceLimits { .guaranteedFloors }
}
#endif
