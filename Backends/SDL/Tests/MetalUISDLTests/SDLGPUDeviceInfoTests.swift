import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
import MetalUISDLGPU
@testable import MetalUISDL
@testable import MetalUISDLGPU
import ReplayFixture

// Adapter name, software flag, limits and the off-main-thread device
// (rulings DL-A...DL-L, XP-G23, XP-G24). D1 is pure; D2...D8 need a GPU.

private let surfaceWidth = 32, surfaceHeight = 32
private let surfaceBounds = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 16, height: 16))
private let surfaceTarget = SurfaceTarget(id: SurfaceID(rawValue: 1), width: 16, height: 16)

private func surfaceScene() -> Scene {
    var scene = Scene()
    let all = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: Float(surfaceWidth), height: Float(surfaceHeight)))
    let none = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
    let black = MUIHsla(h: 0, s: 0, l: 0, a: 1)
    scene.insert(MUIRect(bounds: all, contentMask: all, maskCornerRadii: none, background: black, borderColor: black,
                         cornerRadii: none, borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                         order: 0, shape: 0))
    scene.insert(MUIImage(bounds: surfaceBounds, contentMask: surfaceBounds, maskCornerRadii: none, opacity: 1, texture: 0,
                          filter: MUIUInt(MUIImageFilterLinear.rawValue), order: 1), surface: surfaceTarget)
    scene.finalize()
    return scene
}

private final class DeviceBox: @unchecked Sendable {
    nonisolated(unsafe) var device: SDLGPUDevice?
}

/// Resumes a continuation at most once (the result or the timeout).
private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }
    func resume(_ value: T?) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(returning: value)
    }
}

/// Runs `body` on a detached `Thread` (never the main actor) and awaits it by
/// continuation, so the main queue stays free (DL-K); `nil` on timeout.
private func onDetachedThread<T: Sendable>(seconds: Double = 60, _ body: @escaping @Sendable () -> T) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let once = Once(continuation)
        let thread = Thread { once.resume(body()) }
        thread.stackSize = 4 << 20
        thread.start()
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { once.resume(nil) }
    }
}

/// Uploads 256 patterned bytes to a buffer, copies them back, and answers
/// whether they match. Synchronous: legal off the main actor outside a draw.
private func roundTrip(on device: SDLGPUDevice) -> Bool {
    let bytes = (0..<256).map { UInt8(($0 * 37 + 5) & 0xff) }
    guard let buffer = device.makeBuffer(size: 256, usage: [.computeStorageRead, .computeStorageWrite]),
          let up = device.makeTransferBuffer(size: 256, direction: .upload),
          let down = device.makeTransferBuffer(size: 256, direction: .download),
          let memory = up.map() else { return false }
    bytes.withUnsafeBytes { memory.copyMemory(from: $0.baseAddress!, byteCount: 256) }
    up.unmap()
    guard let first = try? device.submitBatchSynchronously({ $0.copy(up, to: buffer, destinationOffset: 0, size: 256) }) else { return false }
    first.waitBlocking()
    guard let second = try? device.submitBatchSynchronously({ $0.copy(buffer, range: 0..<256, to: down) }) else { return false }
    second.waitBlocking()
    guard let out = down.map() else { return false }
    defer { down.unmap() }
    return Array(UnsafeRawBufferPointer(start: out, count: 256)) == bytes
}

@MainActor @Suite(.serialized) struct SDLGPUDeviceInfoTests {
    /// **D1.** The matcher knows the software names SDL documents, in any case, by whole word for `warp`.
    /// Mutations: drop the lowercasing; drop the `warp` word boundary; drop `microsoft basic render driver`.
    @Test func theMatcherRecognisesTheSoftwareNamesSDLDocuments() {
        func soft(_ name: String?, _ driver: String? = nil, _ info: String? = nil, backend: String = "vulkan") -> Bool {
            SDLGPUDeviceInfo.looksSoftware(adapterName: name, driverName: driver, driverInfo: info, backend: backend)
        }
        for name in ["llvmpipe (LLVM 15.0.4, 256 bits)", "SwiftShader Device (LLVM 16.0.0)", "Microsoft Basic Render Driver",
                     "Microsoft Direct3D12 (WARP)", "Microsoft Basic Render Driver".uppercased(), "LLVMPIPE (LLVM 1)", "softpipe"] {
            #expect(soft(name), "\(name) is software")
        }
        #expect(soft("lavapipe"))
        #expect(soft("Some Device", nil, "Mesa 24.0 (LLVM 17) lavapipe"))
        #expect(soft("Some Device", "llvmpipe"))
        #expect(soft("Direct3D12", nil, "WARP"))
        for name in ["NVIDIA GeForce GTX 970", "AMD Radeon (TM) Graphics", "Apple M3", "Apple M3 Max", "warpath", "Unwarped"] {
            #expect(!soft(name), "\(name) is not software")
        }
        #expect(!soft(nil))
        #expect(!soft("llvmpipe (LLVM 15.0.4, 256 bits)", backend: "metal"), "metal is never software")
        #expect(!soft("Software Renderer llvmpipe", "swiftshader", "WARP", backend: "metal"))
    }

    /// **D2.** The adapter name is SDL's `NAME_STRING`, non-empty.
    /// Mutation: read the driver-name key.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aDeviceHasANonEmptyAdapterName() throws {
        let device = try GPUTestSupport.requireDevice()
        let name = try #require(device.adapterName)
        #expect(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let props = SDL_GetGPUDeviceProperties(device.raw)
        let direct = SDL_GetStringProperty(props, SDL_PROP_GPU_DEVICE_NAME_STRING, nil).map { String(cString: $0) }
        #expect(name == direct)
        if let driverName = device.driverName, direct != nil {
            let rawDriver = SDL_GetStringProperty(props, SDL_PROP_GPU_DEVICE_DRIVER_NAME_STRING, nil).map { String(cString: $0) }
            #expect(driverName == rawDriver)
        }
        print("DL device: backend=\(device.driver) name=\(name) driverName=\(device.driverName ?? "nil") version=\(device.driverVersion ?? "nil") soft=\(device.isSoftwareRasterizer)")
    }

    /// **D3.** On Linux (the image, lavapipe) a device named `llvmpipe` is a software rasterizer (DL-J).
    /// Mutations: `isSoftwareRasterizer` answers false; the matcher without `llvmpipe`.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func lavapipeIsASoftwareRasterizerInTheLinuxImage() throws {
        #if os(Linux)
        let device = try GPUTestSupport.requireDevice()
        #expect(device.driver == "vulkan")
        let props = SDL_GetGPUDeviceProperties(device.raw)
        let raw = SDL_GetStringProperty(props, SDL_PROP_GPU_DEVICE_NAME_STRING, nil).map { String(cString: $0).lowercased() } ?? ""
        if raw.contains("llvmpipe") { #expect(device.isSoftwareRasterizer, "raw name \(raw)") }
        #expect(device.isSoftwareRasterizer == SDLGPUDeviceInfo.looksSoftware(
            adapterName: device.adapterName, driverName: device.driverName, driverInfo: device.driverInfo, backend: device.driver))
        #endif
    }

    /// **D4.** Metal is never a software rasterizer. Mutation: the matcher without the backend guard
    /// (red together with D1's metal arm).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aHardwareMacIsNotASoftwareRasterizer() throws {
        #if os(macOS)
        let device = try GPUTestSupport.requireDevice()
        if device.driver == "metal" { #expect(!device.isSoftwareRasterizer) }
        #endif
    }

    /// **D5.** Limits are at least the documented guaranteed floors.
    /// Mutation: lower a constant by one.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func limitsAreAtLeastTheDocumentedMinimums() throws {
        let limits = try GPUTestSupport.requireDevice().limits
        #expect(limits.maxStorageBufferBindingBytes >= 1 << 27)
        #expect(limits.maxComputeWorkgroupCount.x >= 65_535)
        #expect(limits.maxComputeWorkgroupCount.y >= 65_535)
        #expect(limits.maxComputeWorkgroupCount.z >= 65_535)
        #expect(limits.areGuaranteedFloors)
    }

    /// **D6.** A borrowed device answers as an owned one on the same driver (DL-F, DL-L). The window
    /// renderer's device is borrowed from a surface draw as C9 does; the second arm borrows a `make`
    /// device's own pointer and so proves the single code path only.
    /// Mutation: `adapterName` branching on ownership.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aBorrowedDeviceAnswersLikeAnOwnedOneOnTheSameDriver() throws {
        #if os(macOS)
        armMainRunLoopExitCheck()
        #endif
        let owned = try GPUTestSupport.requireDevice()
        let alias = SDLGPUDevice(borrowingRaw: owned.raw)
        #expect(alias.adapterName == owned.adapterName)
        #expect(alias.driverName == owned.driverName)
        #expect(alias.driverVersion == owned.driverVersion)
        #expect(alias.driverInfo == owned.driverInfo)
        #expect(alias.isSoftwareRasterizer == owned.isSoftwareRasterizer)
        #expect(alias.limits == owned.limits)

        let renderer = try SDLWindowRenderer(offscreenWidth: surfaceWidth, height: surfaceHeight)
        let box = DeviceBox()
        let request = SurfaceDrawRequest(target: surfaceTarget, scaleFactor: 1, time: 0, policy: .onDemand, value: nil) { ctx in
            if box.device == nil, let sdl = ctx as? SDLGPUDrawContext { box.device = SDLGPUDevice(borrowing: sdl) }
            ctx.clear(red: 0, green: 0, blue: 1, alpha: 1)
        }
        try #require(renderer.beginFrame() != nil)
        try #require(renderer.finishFrame(scene: surfaceScene(), atlas: GlyphAtlas(width: 16, height: 16), surfaces: [request]))
        let window = try #require(box.device, "the first draw handed over its device")
        if window.driver == owned.driver {
            #expect(window.isSoftwareRasterizer == owned.isSoftwareRasterizer)
            #expect(window.limits == owned.limits)
            #expect(window.driverName == owned.driverName)
            if window.adapterName != owned.adapterName {
                print("DL-F: two adapters on one driver: window \(window.adapterName ?? "nil") vs make \(owned.adapterName ?? "nil")")
            } else {
                #expect(window.adapterName == owned.adapterName)
            }
        }
    }

    /// **D7.** An engine device made by `make` off the main thread works beside a window renderer's device
    /// (DL-G (a)). Mutations: `make` without its lock; on macOS the main hop removed (Cocoa init fails off main).
    @Test func anEngineDeviceMadeOffTheMainThreadWorksBesideAWindowDevice() async throws {
        // Not `.enabled(if:)`: that probe runs off the main thread, so it would skip silently if `make`
        // lost its macOS main hop. The probe here is on the main actor, where `make` needs no hop.
        guard SDLGPUDevice.make() != nil else { return }
        #if os(macOS)
        armMainRunLoopExitCheck()
        #endif
        let renderer = try SDLWindowRenderer(offscreenWidth: surfaceWidth, height: surfaceHeight)
        _ = renderer
        let ok = await onDetachedThread { () -> Bool in
            guard !Thread.isMainThread, let device = SDLGPUDevice.make() else { return false }
            return roundTrip(on: device) && device.adapterName != nil
        }
        #expect(ok == true, "a detached thread made a device and read its bytes back; lastFailure: \(SDLGPUDevice.lastFailure)")
    }

    /// **D8.** `make` on a detached thread with no window anywhere returns and, when it answers, leaves no
    /// failure (DL-G (b), DL-K). Records whether video was already up: only a filtered-alone run is evidence of a first
    /// off-thread init. Mutation: `make` without `SDL_InitSubSystem` (the Vulkan loader fails in the image).
    @Test func videoInitOffTheMainThreadIsMeasured() async throws {
        // Not `.enabled(if:)`: that probe runs off the main thread, so it would skip silently if `make`
        // lost its macOS main hop. The probe here is on the main actor, where `make` needs no hop.
        guard SDLGPUDevice.make() != nil else { return }
        #if os(macOS)
        armMainRunLoopExitCheck()
        #endif
        let wasUp = SDL_WasInit(SDL_INIT_VIDEO) != 0
        let failureBefore = SDLGPUDevice.lastFailure
        let result = await onDetachedThread { () -> String? in
            guard let device = SDLGPUDevice.make() else { return nil }
            return "\(device.driver) \(device.adapterName ?? "nil")"
        }
        let answered = try #require(result, "make returned within the bound")
        print("DL D8: videoAlreadyInitialised=\(wasUp) offThreadMake=\(answered ?? "nil") lastFailure=\(SDLGPUDevice.lastFailure)")
        // The main-thread probe above made a device, so a GPU exists: the off-thread call must answer too.
        #expect(answered != nil, "an off-main-thread make answered: \(SDLGPUDevice.lastFailure)")
        if answered != nil, failureBefore.isEmpty { #expect(SDLGPUDevice.lastFailure.isEmpty) }
    }
}
