import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender
import MetalUIScene
import MetalUIDemoContent
@testable import MetalUI

// MetalView lane 2, tests 2.1–2.10 and 2.12 (rulings `MV-A` item 2, `MV-D`,
// `MV-E`, `MV-F`, `MV-G`, `MV-J`, `MV-L` item 6; spec
// `docs/superpowers/specs/2026-10-01-metal-view-design.md` §4, §5, §7, §8).
// The Metal half of an app-owned surface: `MetalWindowRenderer`'s per-window
// `SurfaceTargetTable`, the draw contract inside `finishFrame`, compositing
// through `Renderer.encode`, `MetalDrawContext`, `MetalView` and the demo
// tree. SwiftUI's side is `docs/probes/swiftui-metal-view.swift` (D1: the
// drawable is the bounds × the backing scale; C1–C3: an app's Metal surface is
// composited through clip and opacity like any view; R0–R3 and D1's draw
// count: when it redraws).
//
// **No test sleeps.** Frames are a real `Window` over `FakePlatformWindow`,
// whose renderer is a real `MetalWindowRenderer` drawing into a `.shared`
// texture the test reads back (`FakeRenderSurface.readPixels()`, which waits
// on the frame's own command buffer); ticks are `simulateTick(timestamp:)`.

// MARK: - Fixtures

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor
private final class Counter {
    var value = 0
}

/// A value a draw closure records, read back by the test.
@MainActor
private final class Captured<T> {
    var value: T?
}

/// A weak reference a draw closure fills.
@MainActor
private final class WeakTexture {
    weak var value: (any MTLTexture)?
}

@MainActor
private final class Flag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

/// A `side × side` window over `content`, no frame drawn yet.
@MainActor
private func window<Root: Element>(side: Int = 64, startsDisplayLink: Bool = false,
                                   _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    return try makeFakeWindow(device: device, size: side, startsDisplayLink: startsDisplayLink, content: content)
}

/// An exit test's standard error, decoded.
private func stderrText(_ result: ExitTest.Result?) -> String {
    String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
}

@MainActor
private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

/// The (r, g, b, a) at `(x, y)` of a BGRA readback `side` wide.
private func rgba(_ pixels: [UInt8], _ x: Int, _ y: Int, side: Int) -> [Int] {
    let i = (y * side + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

/// The centre of the scene's first surface quad, in device pixels.
@MainActor
private func surfaceCentre(_ window: Window) throws -> (x: Int, y: Int) {
    let quad = try #require(window.lastScene.surfaces.first, "set up: one surface quad")
    return (Int(quad.bounds.origin.x + quad.bounds.size.width / 2),
            Int(quad.bounds.origin.y + quad.bounds.size.height / 2))
}

/// A draw that clears to opaque red and counts itself.
@MainActor
private func redFill(_ draws: Counter) -> @MainActor (any GPUSurfaceContext) -> Void {
    { ctx in
        draws.value += 1
        ctx.clear(red: 1, green: 0, blue: 0, alpha: 1)
    }
}

// MARK: - 2.1 the first frame

/// **2.1** (`MV-F` item 3). A surface's fill is composited on the very first
/// frame: the app's draw runs into the frame's command buffer **before**
/// `Renderer.encode`, so the composite (GPU-ordered after it) samples what
/// the app wrote. Inside the quad: the fill; outside: the window's clear.
///
/// Mutations **M2a**: run the draws after `renderer.encode` (the composite
/// samples the target before the app's clear — the first frame reads
/// transparent); **M2b**: skip `.surface` runs in `encode`.
@Test @MainActor func aSurfaceFillIsCompositedOnTheFirstFrame() throws {
    let draws = Counter()
    let (window, platform) = try window {
        GPUSurface(draw: redFill(draws)).frame(width: px(20), height: px(20))
    }
    window.drawFrameIfNeeded()
    try #require(draws.value == 1, "set up: the draw ran once")
    let centre = try surfaceCentre(window)
    let pixels = platform.fakeSurface.readPixels()
    #expect(rgba(pixels, centre.x, centre.y, side: 64) == [255, 0, 0, 255], "inside: the app's fill")
    #expect(rgba(pixels, 1, 1, side: 64) == [0, 0, 0, 0], "outside: the window's clear")
}

// MARK: - 2.2 kept contents

/// **2.2** (`MV-G` item 2; probe R0: an idle `Canvas` never re-runs). An
/// `.onDemand` surface is drawn once; a window redraw for any other reason
/// composites its target's last contents with no GPU work for it — the draw
/// count stays 1 and the pixel stays red.
///
/// Mutation **M2c**: release and recreate every target every frame (each
/// frame's target is new, so it draws again).
@Test @MainActor func anOnDemandSurfaceKeepsItsContentsWhenTheWindowRedrawsForAnotherReason() throws {
    let draws = Counter()
    let (window, platform) = try window {
        GPUSurface(draw: redFill(draws)).frame(width: px(20), height: px(20))
    }
    window.drawFrameIfNeeded()
    redraw(window)
    redraw(window)
    #expect(draws.value == 1, "drawn once over three frames")
    let centre = try surfaceCentre(window)
    #expect(rgba(platform.fakeSurface.readPixels(), centre.x, centre.y, side: 64) == [255, 0, 0, 255],
            "the third frame composites the first frame's contents")
    #expect(platform.windowRenderer.surfaceTable.createdCount == 1, "one target, reused")
}

// MARK: - 2.3 compositing exactly as an image

/// **2.3** (`MV-D`; probe C1–C3 against P2: SwiftUI composites an app's
/// Metal surface through the same clip and opacity as any view). A surface
/// cleared to `SurfaceParity`'s colour A, under a rounded clip at half
/// opacity, is pixel-for-pixel an `Image` of the same colour in the same
/// place — every byte of the readback equal — and its centre is the parity
/// literal's half-A (over the window's transparent clear here, so alpha is
/// half of 255, 127 or 128 by the GPU's rounding; the RGB is exact). The
/// unclipped arm separates: its corner is filled where the clipped one's is
/// not.
///
/// Mutation **M2d**: bind the wrong texture (the atlas) for surface runs.
@Test @MainActor func aSurfaceIsClippedRoundedAndFadedExactlyAsAnImage() throws {
    let (r, g, b) = (Float(200) / 255, Float(100) / 255, Float(40) / 255)
    let bitmap = ImageBitmap(width: 1, height: 1, rgba: [200, 100, 40, 255])
    func clipped<C: ProposalElementGroup>(_ content: C) -> some Element & ProposalElementGroup {
        HStack(spacing: px(0)) { content }.clipShape(RoundedRectangle(cornerRadius: px(8))).opacity(0.5)
    }
    let (surfaceWindow, surfacePlatform) = try window {
        clipped(GPUSurface { ctx in ctx.clear(red: r, green: g, blue: b, alpha: 1) }
            .frame(width: px(40), height: px(40)))
    }
    let (imageWindow, imagePlatform) = try window {
        clipped(Image(decorative: bitmap, scale: 1).resizable().frame(width: px(40), height: px(40)))
    }
    let (bareWindow, barePlatform) = try window {
        HStack(spacing: px(0)) {
            GPUSurface { ctx in ctx.clear(red: r, green: g, blue: b, alpha: 1) }.frame(width: px(40), height: px(40))
        }.opacity(0.5)
    }
    for w in [surfaceWindow, imageWindow, bareWindow] { w.drawFrameIfNeeded() }
    let surface = surfacePlatform.fakeSurface.readPixels()
    let image = imagePlatform.fakeSurface.readPixels()
    let bare = barePlatform.fakeSurface.readPixels()
    let quad = try #require(surfaceWindow.lastScene.surfaces.first, "set up: one surface quad")
    let corner = (Int(quad.bounds.origin.x), Int(quad.bounds.origin.y))
    try #require(rgba(surface, corner.0, corner.1, side: 64) != rgba(bare, corner.0, corner.1, side: 64),
                 "the unclipped arm must separate at the corner")
    #expect(surface == image, "every byte equal to the image in the same place")
    let centre = try surfaceCentre(surfaceWindow)
    let mid = rgba(surface, centre.x, centre.y, side: 64)
    // `SurfaceParity.expected[0]`'s RGB (`Tests/MetalUIRenderTests/SurfaceCompositingTests.swift`,
    // another test target): half of (200, 100, 40), exact.
    #expect(Array(mid.prefix(3)) == [100, 50, 20], "the parity literal's half-A: \(mid)")
    #expect(abs(mid[3] - 127) <= 1, "half alpha over the transparent clear: \(mid)")
    #expect(rgba(surface, corner.0, corner.1, side: 64) == [0, 0, 0, 0], "C2: the clipped corner is clear")
}

// MARK: - 2.4 what the draw receives

/// **2.4** (`MV-E` items 2 and 4, `MV-F` item 4; probe D1: a 100 × 60-pt
/// `MTKView` at scale 2.0 has a 200 × 120-px drawable). At scale 2 a 30 × 20-pt
/// surface's draw receives a 60 × 40 `bgra8Unorm` target (never `_sRGB`,
/// §7.8), render target and shader read, private storage, hazard-tracked
/// (`MV-L` item 5) — with the frame's scale, its display-link timestamp, the
/// renderer's frame index and `isNewTarget`. A changed `value:` redraws into
/// the SAME texture, no longer new, at the next tick's time.
///
/// Mutations **M2e**: allocate `.bgra8Unorm_srgb`; **M2f**: size the target in
/// points (each side ÷ the scale).
@Test @MainActor func aSurfaceDrawReceivesItsDevicePixelBgraTargetScaleAndTime() throws {
    struct Seen {
        var target: any MTLTexture
        var pixelSize: [Int32]
        var scale: Float
        var time: Double
        var frameIndex: UInt64
        var isNew: Bool
    }
    let log = Captured<[Seen]>()
    log.value = []
    let version = Counter()
    let (window, platform) = try window(startsDisplayLink: true) {
        GPUSurface(value: version.value) { ctx in
            let metal = ctx as! MetalDrawContext
            log.value!.append(Seen(target: metal.target, pixelSize: [ctx.pixelSize.width.value, ctx.pixelSize.height.value],
                             scale: ctx.scaleFactor, time: ctx.time, frameIndex: ctx.frameIndex,
                             isNew: ctx.isNewTarget))
        }
        .frame(width: px(30), height: px(20))
    }
    platform.scaleFactor = 2
    platform.fakeSurface.scaleFactor = 2
    platform.simulateTick(timestamp: 3.25)
    var seen: [Seen] { log.value! }
    try #require(seen.count == 1, "set up: the first tick drew once")
    let first = seen[0]
    #expect(first.target.pixelFormat == .bgra8Unorm, "bgra8Unorm, never _sRGB (§7.8)")
    #expect([first.target.width, first.target.height] == [60, 40] as [Int], "D1: bounds × scale")
    #expect(first.pixelSize == [60, 40] as [Int32])
    #expect(first.target.usage.contains(.renderTarget) && first.target.usage.contains(.shaderRead))
    #expect(first.target.storageMode == .private)
    #expect(first.target.hazardTrackingMode != .untracked, "tracked (MV-L item 5)")
    #expect(first.scale == 2 && first.time == 3.25 && first.isNew)

    platform.simulateTick(timestamp: 3.5)
    #expect(seen.count == 1, "nothing changed: no redraw")
    version.value = 1
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 3.75)
    try #require(seen.count == 2, "a changed value: redraws")
    let second = seen[1]
    #expect(second.target === first.target, "into the same target")
    #expect(!second.isNew && second.time == 3.75)
    #expect(second.frameIndex > first.frameIndex, "the renderer's frame count advanced")
}

// MARK: - 2.5 continuous vs on demand

/// **2.5** (`MV-G` items 2–3; probe D1: an `MTKView` left unpaused draws on
/// every display tick; R0: an idle `Canvas` does not). Over four ticks a
/// `.continuous` surface draws on every one — its paint keeps the link awake
/// through `noteActiveAnimation()` — while an `.onDemand` sibling draws once.
///
/// Mutation **M2g**: draw only new targets (the continuous one draws once).
@Test @MainActor func aContinuousSurfaceDrawsOnEveryTickAndAnOnDemandOneOnce() throws {
    let continuous = Counter(), onDemand = Counter()
    let (window, platform) = try window(startsDisplayLink: true) {
        HStack(spacing: px(0)) {
            GPUSurface(redraw: .continuous, draw: redFill(continuous)).frame(width: px(20), height: px(20))
            GPUSurface(redraw: .onDemand, draw: redFill(onDemand)).frame(width: px(20), height: px(20))
        }
    }
    defer { withExtendedLifetime(window) {} }
    for tick in 1...4 { platform.simulateTick(timestamp: Double(tick)) }
    #expect(continuous.value == 4, "every tick")
    #expect(onDemand.value == 1, "once")
}

// MARK: - 2.6 per-window targets

/// **2.6** (`MV-E` item 3, `MV-L` item 6). Two windows sharing one `Renderer`
/// (as `AppKitPlatform`'s do, `RS-C`) each hold their own target, though both
/// windows mint `SurfaceID(1)`: at different sizes, drawn **alternately** A, B,
/// A, B, each window's surface draws once and creates one target, and each
/// window shows its own fill. A table on the shared `Renderer` would see the
/// other window's scene not reference its target (or reference it at another
/// size) and release it every frame.
///
/// Mutation **M2h**: the table shared across windows (on the `Renderer`).
@Test @MainActor func twoWindowsKeepTheirOwnTargets() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let shared = try Renderer(device: device)
    let drawsA = Counter(), drawsB = Counter()
    let platformA = try FakePlatformWindow(device: device, size: 64, renderer: shared)
    let platformB = try FakePlatformWindow(device: device, size: 64, renderer: shared)
    let windowA = Window(platformWindow: platformA, startsDisplayLink: false) {
        GPUSurface { ctx in drawsA.value += 1; ctx.clear(red: 1, green: 0, blue: 0, alpha: 1) }
            .frame(width: px(20), height: px(20))
    }
    let windowB = Window(platformWindow: platformB, startsDisplayLink: false) {
        GPUSurface { ctx in drawsB.value += 1; ctx.clear(red: 0, green: 0, blue: 1, alpha: 1) }
            .frame(width: px(30), height: px(30))
    }
    for _ in 0..<2 {
        redraw(windowA)
        redraw(windowB)
    }
    try #require(windowA.lastScene.surfaceTargets.map(\.id) == windowB.lastScene.surfaceTargets.map(\.id),
                 "set up: both windows mint the same SurfaceID")
    #expect(drawsA.value == 1 && drawsB.value == 1, "each drawn once: A \(drawsA.value), B \(drawsB.value)")
    #expect(platformA.windowRenderer.surfaceTable.createdCount == 1, "A created one target")
    #expect(platformB.windowRenderer.surfaceTable.createdCount == 1, "B created one target")
    let a = try surfaceCentre(windowA), b = try surfaceCentre(windowB)
    #expect(rgba(platformA.fakeSurface.readPixels(), a.x, a.y, side: 64) == [255, 0, 0, 255], "A's own fill")
    #expect(rgba(platformB.fakeSurface.readPixels(), b.x, b.y, side: 64) == [0, 0, 255, 255], "B's own fill")
}

// MARK: - 2.7 release

/// **2.7** (`MV-E` item 1, `MV-G` item 4). When its element leaves, a
/// surface's target is released at that frame — the table's counters say so —
/// and the `MTLTexture` itself is freed once the frame that last sampled it
/// completes: a weak reference to it reads `nil` (no leak across frames).
///
/// Mutation **M2i**: the renderer's `release` keeps the handle alive (a leak:
/// the counters still move, the weak reference does not clear).
@Test @MainActor func aSurfacesTargetIsReleasedWhenItsElementLeaves() throws {
    let target = WeakTexture()
    let shown = Flag(true)
    let (window, platform) = try window {
        HStack {
            if shown.value {
                GPUSurface { ctx in
                    target.value = (ctx as! MetalDrawContext).target
                    ctx.clear(red: 1, green: 0, blue: 0, alpha: 1)
                }
                .frame(width: px(20), height: px(20))
            }
        }
    }
    autoreleasepool { window.drawFrameIfNeeded() }
    try #require(target.value != nil, "set up: the draw saw its target")
    let table = { platform.windowRenderer.surfaceTable }
    try #require(table().liveCount == 1 && table().createdCount == 1)
    shown.value = false
    autoreleasepool { redraw(window) }
    #expect(table().releasedCount == 1 && table().liveCount == 0, "released at the frame it left")
    autoreleasepool {
        redraw(window)  // a later frame replaces the fake surface's last command buffer
        _ = platform.fakeSurface.readPixels()
    }
    #expect(target.value == nil, "the texture itself was freed")
}

// MARK: - 2.8 the command-buffer contract

/// **2.8** (`MV-F` item 5). A draw that commits the frame's command buffer
/// traps, naming `MV-F`: after each draw the renderer checks
/// `commandBuffer.status == .notEnqueued`. (Pinned by an exit test that reads
/// the trap's message; the positive case — a draw that leaves it alone — is
/// every other test here.)
///
/// Mutation **M2j**: drop the status precondition.
@Test func aSurfaceDrawThatCommitsTheCommandBufferTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let pair = try? makeFakeWindow(device: device, content: {
                      GPUSurface { ctx in (ctx as! MetalDrawContext).commandBuffer.commit() }
                          .frame(width: Pixels(20), height: Pixels(20))
                  }) else { return }
            pair.0.drawFrameIfNeeded()
        }
    }
    // Metal itself aborts a doubly committed buffer later in the frame, so a
    // bare `.failure` cannot tell the renderer's check from Metal's: the
    // message must be MV-F's (the first run of M2j stayed green on exactly that).
    #expect(stderrText(result).contains("MV-F item 5"), "aborted, but not at MV-F's check:\n\(stderrText(result))")
}

// MARK: - 2.9 MetalView

/// **2.9** (`MV-A` item 2, `MV-F` items 3–4). `MetalView`'s typed context is
/// the renderer's own device and the frame's own command buffer — the one the
/// window presents — and no MetalUI encoder is open while it runs, so it can
/// begin its own render pass from `renderPassDescriptor(clearColor:)`; the
/// pass's colour is composited that same frame.
///
/// Mutation **M2k**: `MetalView` forwards a fresh command buffer (never
/// committed — the identity fails and the pixel stays clear).
@Test @MainActor func aMetalViewDrawsWithTheRenderersDeviceAndTheFramesCommandBuffer() throws {
    let device = Captured<any MTLDevice>()
    let commandBuffer = Captured<any MTLCommandBuffer>()
    let (window, platform) = try window {
        MetalView { ctx in
            device.value = ctx.device
            commandBuffer.value = ctx.commandBuffer
            let pass = ctx.renderPassDescriptor(clearColor: MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1))
            let encoder = ctx.commandBuffer.makeRenderCommandEncoder(descriptor: pass)
            encoder?.endEncoding()
        }
        .frame(width: px(20), height: px(20))
    }
    window.drawFrameIfNeeded()
    let pixels = platform.fakeSurface.readPixels()
    try #require(device.value != nil && commandBuffer.value != nil, "set up: the MetalView drew")
    #expect(device.value === platform.windowRenderer.renderer.device, "the renderer's device")
    #expect(commandBuffer.value === platform.fakeSurface.lastCommandBuffer, "the frame's own command buffer")
    let centre = try surfaceCentre(window)
    #expect(rgba(pixels, centre.x, centre.y, side: 64) == [0, 255, 0, 255], "its own pass, composited")
}

/// A context that is not Metal's — what `Backends/SDL` would hand on macOS.
@MainActor
private struct NotMetal: GPUSurfaceContext {
    var pixelSize: Size<DevicePixels> { Size(width: DevicePixels(1), height: DevicePixels(1)) }
    var scaleFactor: Float { 1 }
    var time: Double { 0 }
    var frameIndex: UInt64 { 0 }
    var isNewTarget: Bool { true }
    func clear(red: Float, green: Float, blue: Float, alpha: Float) {}
}

/// **2.10** (`MV-A` item 2). A `MetalView` handed a context that is not a
/// `MetalDrawContext` traps, naming `MV-A` — a blank viewport with no error
/// would be the silent alternative. The control: the same thunk over a
/// `MetalDrawContext` runs the closure (2.9).
///
/// Mutation **M2l**: skip instead of trap.
@Test func aMetalViewGivenANonMetalContextTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            MetalView.drawThunk { _ in }(NotMetal())
        }
    }
    #expect(stderrText(result).contains("MV-A item 2"), "aborted, but not at MV-A's check:\n\(stderrText(result))")
}

// MARK: - 2.12 the demo tree

/// **2.12** (`MV-J` item 1). The MetalView demo's tree (`metalViewDemoContent`)
/// paints exactly two surfaces: the main viewport `.continuous` (the animation
/// a tap pauses) and the small stepper-driven one `.onDemand` with a `value:`.
///
/// Mutation **M2n**: the demo's main surface `.onDemand`.
@Test @MainActor func theMetalViewDemoTreeRequestsOneContinuousAndOneOnDemandSurface() throws {
    var root = metalViewDemoContent(draws: MetalViewDemoDraws()) { _ in }
    let frame = Frame(contentSize: Size(width: px(920), height: px(560)), scaleFactor: 1)
    frame.render(&root)
    let requests = frame.surfaceRequests
    try #require(requests.count == 2, "two surfaces: \(requests.map(\.target))")
    #expect(requests.map(\.policy).sorted { "\($0)" < "\($1)" } == [.continuous, .onDemand])
    let onDemand = try #require(requests.first { $0.policy == .onDemand })
    #expect(onDemand.value != nil, "the small surface redraws on its stepper's value")
    let main = try #require(requests.first { $0.policy == .continuous })
    #expect(main.target.width > onDemand.target.width, "the continuous one is the main viewport")
}

// MARK: - 2.13 the demo's draw count advances

/// **2.13** (`MV-N` item 4, corrected). The MetalView demo's header counts the
/// large surface's draws, and the count it shows **advances**: over six ticks
/// of a real `Window` (its content closure rebuilding the tree every frame,
/// as `main.swift`'s does) the header reads the counter the draws incremented,
/// one frame behind. A counter held in a never-written `@State` would read 0
/// forever — an absent `StateTable` entry re-seeds from the freshly built
/// struct's initial value every frame — so the counter is created once,
/// outside the content closure, and passed in.
///
/// Mutation **M2o**: hold the counter in `@State` again (the header reads 0).
@Test @MainActor func theMetalViewDemosDrawCountAdvances() throws {
    let draws = MetalViewDemoDraws()
    let (window, platform) = try window(side: 920, startsDisplayLink: true) {
        metalViewDemoContent(draws: draws) { _ in }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateResize(to: Size(width: px(920), height: px(560)))
    platform.simulateAccessibilityRequest(.activate)
    for tick in 1...6 { platform.simulateTick(timestamp: Double(tick)) }
    try #require(draws.count >= 5, "set up: the continuous surface drew on every tick: \(draws.count)")
    let tree = try #require(platform.publishedAccessibilityTrees.last, "no tree published")
    let header = tree.nodes.values.compactMap(\.value).filter { $0.hasPrefix("Viewport draws: ") }
    try #require(header.count == 1, "one count line (a static text's string is its value): \(header)")
    let shown = try #require(Int(header[0].dropFirst("Viewport draws: ".count)))
    #expect(shown >= 4 && shown <= draws.count, "the header shows the advancing count: \(shown) of \(draws.count)")
}

// MARK: - 2.14 a resize on the Metal renderer

/// **2.14** (`MV-E` items 1–2, at the Metal level; probe D1: the drawable
/// follows the bounds × the backing scale). An `.onDemand` surface whose frame
/// grows between ticks gets a **new** `bgra8Unorm` texture at the new
/// bounds × 2 and draws once into it, `isNewTarget` set; an unchanged tick
/// after that draws nothing. The table-level twin is lane 1's
/// `aResizeReplacesTheTargetAndARescaleRedrawsWithoutReallocating`.
///
/// Mutation **M2p**: `SurfaceTargetTable.update` ignores a size change (lane
/// 1's V1, re-run here so the Metal renderer's own path is seen to redden).
@Test @MainActor func aResizedSurfaceGetsANewTargetAtItsNewDeviceSizeAndRedrawsOnce() throws {
    struct Seen { var texture: any MTLTexture; var isNew: Bool }
    let log = Captured<[Seen]>()
    log.value = []
    let width = Counter()
    width.value = 30
    let (window, platform) = try window(startsDisplayLink: true) {
        GPUSurface { ctx in
            let metal = ctx as! MetalDrawContext
            log.value!.append(Seen(texture: metal.target, isNew: ctx.isNewTarget))
        }
        .frame(width: px(Float(width.value)), height: px(20))
    }
    defer { withExtendedLifetime(window) {} }
    platform.scaleFactor = 2
    platform.fakeSurface.scaleFactor = 2
    platform.simulateTick(timestamp: 1)
    var seen: [Seen] { log.value! }
    try #require(seen.count == 1, "set up: the first tick drew once")
    #expect([seen[0].texture.width, seen[0].texture.height] == [60, 40] as [Int])

    width.value = 45
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 2)
    try #require(seen.count == 2, "the resize redrew: \(seen.count)")
    #expect(seen[1].texture !== seen[0].texture, "into a new texture")
    #expect([seen[1].texture.width, seen[1].texture.height] == [90, 40] as [Int], "at the new bounds × 2")
    #expect(seen[1].texture.pixelFormat == .bgra8Unorm && seen[1].isNew)

    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 3)
    #expect(seen.count == 2, "an unchanged size: no redraw")
}
