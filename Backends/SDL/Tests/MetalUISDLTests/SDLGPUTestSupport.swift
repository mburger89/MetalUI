import Foundation
import Testing
import MetalUISDLGPU
@testable import MetalUISDLGPU

/// Shared by the `SDLGPU*` tests (ruling `GA-F`, spec §4): where the checked-in
/// app shaders are, and whether this machine has a GPU at all.
enum GPUTestSupport {
    /// `Backends/SDL/Tests/AppShaders/compiled`: the append kernel's blobs, built by
    /// `MetalUICompileShaders` (`swift package compile-shaders`), verified by hash and never regenerated
    /// by a test (`GA-F`, so CI needs no shadercross).
    static var compiledShaders: URL { sources.appendingPathComponent("compiled") }
    static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("AppShaders")
    }

    /// Whether `SDLGPUDevice.make()` answers here. A test needing a GPU is
    /// `.enabled(if: GPUTestSupport.available, …)`; the skip reason names
    /// `SDLGPUDevice.lastFailure`. The Linux and Windows jobs set
    /// `METALUI_REQUIRE_GPU=1`, and `aRequiredGPUIsPresent` turns a skip there
    /// into a failure.
    static let available: Bool = SDLGPUDevice.make() != nil
    static let required = ProcessInfo.processInfo.environment["METALUI_REQUIRE_GPU"] == "1"
    static var skipReason: Comment {
        Comment(rawValue: "no GPU device here: \(SDLGPUDevice.lastFailure)")
    }

    /// A device, or a failure naming `SDLGPUDevice.lastFailure`.
    static func requireDevice() throws -> SDLGPUDevice {
        guard let device = SDLGPUDevice.make() else {
            throw GPUUnavailable(reason: SDLGPUDevice.lastFailure)
        }
        return device
    }

    /// `count` 32-bit words as bytes.
    static func bytes(of words: [UInt32]) -> [UInt8] {
        words.withUnsafeBytes { Array($0) }
    }
    static func words(from bytes: [UInt8]) -> [UInt32] {
        stride(from: 0, to: bytes.count - 3, by: 4).map { offset in
            bytes[offset..<offset + 4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32(8 * $1.offset) }
        }
    }
}

/// `SDLGPUDevice.make()` answered `nil`: the reason is SDL's own.
struct GPUUnavailable: Error, CustomStringConvertible {
    let reason: String
    var description: String { "no GPU device: \(reason)" }
}
