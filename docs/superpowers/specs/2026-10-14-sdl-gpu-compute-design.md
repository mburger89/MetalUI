# SDL GPU for apps — design (S5 + S6)

Status: design, `feat/sdl-gpu-compute` from `fb9a7e42`. Rulings: [`GA-A`…`GA-J`](../2026-10-14-sdl-gpu-compute-decisions.md).
Origin: MetalCreator SDL-port gaps 1 and 2 (RAISED; blocks its xp-c track). Never edit MetalCreator.

## 1. Today (inventory)

- `SDLGPUDrawContext` (`Backends/SDL/Sources/MetalUISDL/SDLGPUDrawContext.swift`): raw `device`, `commandBuffer`,
  `target`, plus `pixelSize`, `scaleFactor`, `time`, `frameIndex`, `isNewTarget`, `clear(...)`.
- `SDLWindowRenderer.finishFrame` (`SDLWindowRenderer.swift:290`): `surfaceTable.update`, one draw per due surface
  into the frame's command buffer, MetalUI's pass after; one submission.
- `CSDL` is a `.systemLibrary` (root `Package.swift:245`), not a product. `SDLBridge` (C) owns the device
  (`ReplayGPU`, `mui_renderer_device`), pipelines for the drawable kinds, `replay_*` for a windowless device.
- Shader build: `scripts/compile-shaders.py` over `Shaders/replay.hlsl`; `SOURCE.sha256` checked in
  `sdl-gpu-linux.yml`; runtime lookup `MetalUISDLShaders` beside the executable (`PX-P`).
- No compute, no storage buffer, no readback API for apps. Linux CI image: SDL `release-3.4.16`, lavapipe
  (Vulkan, `SDL_VIDEO_DRIVER=offscreen`); this Mac: SDL 3.4.18, no shadercross.

## 2. Public API (module `MetalUISDLGPU`, `@_exported import CSDL`; all `public`, class `M`)

Names follow SDL_GPU; every wrapper has `raw: OpaquePointer`. Signatures are the contract; bodies are the lanes'.

```swift
public final class SDLGPUDevice: @unchecked Sendable {
    public static func make(debug: Bool = false, preferring driver: String? = nil) -> SDLGPUDevice?  // standalone, owns SDL_GPUDevice (GA-D)
    public static var lastFailure: String { get }                         // why make returned nil (names the driver tried)
    public init(borrowing context: SDLGPUDrawContext)                     // not owned (GA-D)
    public let raw: OpaquePointer
    public var driver: String { get }                                     // "metal" | "vulkan" | "direct3d12"
    public func makeBuffer(size: Int, usage: SDLGPUBufferUsage) -> SDLGPUBuffer?
    public func makeTransferBuffer(size: Int, direction: SDLGPUTransferDirection) -> SDLGPUTransferBuffer?
    public func makeTexture(_ description: SDLGPUTextureDescription) -> SDLGPUTexture?
    public func makeSampler(_ description: SDLGPUSamplerDescription) -> SDLGPUSampler?
    public func makeComputePipeline(_ shader: SDLGPUShaderBlob) -> SDLGPUComputePipeline?
    public func makeGraphicsPipeline(_ description: SDLGPUGraphicsPipelineDescription) -> SDLGPUGraphicsPipeline?
    /// One command buffer, recorded and submitted on the worker thread (GA-E); the fence is the batch's.
    public func submitBatch(_ record: @Sendable (SDLGPUCommandBuffer) -> Void) async -> SDLGPUFence
    public func upload(_ bytes: UnsafeRawBufferPointer, to buffer: SDLGPUBuffer, at offset: Int = 0) async -> Bool
    public func download(_ buffer: SDLGPUBuffer, range: Range<Int>) async -> [UInt8]?      // copy, fence, map (GA-G)
    public func download(_ texture: SDLGPUTexture, mipLevel: Int = 0) async -> [UInt8]?    // tightly packed rows
    public func waitForIdle()                                                              // traps inside a surface draw (GA-I)
}
public final class SDLGPUFence: @unchecked Sendable {
    public func wait() async                       // waiter thread; never blocks the main actor; cancellation keeps the release (GA-E)
    public var isSignalled: Bool { get }
}
public final class SDLGPUCommandBuffer {          // thread-confined; no submit (the batch submits)
    public func beginComputePass(readWrite buffers: [SDLGPUBuffer]) -> SDLGPUComputePass?
    public func beginRenderPass(_ description: SDLGPURenderPassDescription) -> SDLGPURenderPass?
    public func copyBuffer(...)  public func clear(_ buffer: SDLGPUBuffer, range: Range<Int>)  // zeroes a counter
    public func generateMipmaps(_ texture: SDLGPUTexture)
}
public struct SDLGPUComputePass { bind(pipeline:) bind(readOnly:) bind(readWrite:) push(uniform:at:) dispatch(x:y:z:) end() }
public struct SDLGPURenderPass  { bind(pipeline:) bindVertexBuffers bindVertexStorageBuffers bindFragmentSamplers
                                  setViewport setScissor draw(vertices:instances:first:firstInstance:) drawIndexed(...) end() }
public struct SDLGPUShaderBlob { /* bytes + format + entry + counts from reflection (GA-F) */ }
public struct SDLGPUShaderLibrary {
    public init(directory: URL) throws
    public static func locate(directoryName: String = "MetalUIAppShaders", sourceTree: URL? = nil) throws -> SDLGPUShaderLibrary
    public func compute(_ name: String, for device: SDLGPUDevice) throws -> SDLGPUShaderBlob     // "kernel" -> kernel.comp.*
    public func vertex(_ name: String, for device: SDLGPUDevice) throws -> SDLGPUShaderBlob
    public func fragment(_ name: String, for device: SDLGPUDevice) throws -> SDLGPUShaderBlob
}
extension SDLGPUDrawContext { public var view: SDLGPUFrameView }   // non-owning commandBuffer+target; beginRenderPass, no submit/wait (GA-H)
```

Lane 2 adds `SDLGPUTextureDescription` (size, format incl. `r8Unorm`/`d32Float`/`r32Uint`, `sampleCount`,
`levelCount`, usage), `SDLGPUSamplerDescription`, `SDLGPUGraphicsPipelineDescription` (shaders, vertex layout,
colour format, sample count, depth state, primitive type, blend) and `SDLGPURenderPassDescription`
(colour with load/store/resolve, optional depth).

## 3. Files

Lane 1 (new unless noted):
- `Package.swift` (root) and `Backends/SDL/Package.swift`: target + product `MetalUISDLGPU` behind `SDL` (`GA-B`).
- `Backends/SDL/Sources/MetalUISDLGPU/{SDLGPUDevice,SDLGPUBuffer,SDLGPUCompute,SDLGPUFence,SDLGPUWorker,SDLGPUShaderLibrary}.swift`
- `Backends/SDL/scripts/compile-app-shaders.py`
- `Backends/SDL/Tests/MetalUISDLTests/{SDLGPUComputeTests,SDLGPUShaderLibraryTests}.swift`, and
  `Backends/SDL/Tests/MetalUISDLTests/AppShaders/{append.comp.hlsl,compiled/*,compiled/SOURCE.sha256}`
- `docs/packaging.md` (new 4a), `Backends/SDL/README.md`, `docs/migration.md` (one line),
  `docs/guides/cross-platform.md` (compute section; `text` fences, `DG-L`).

Lane 2 (after lane 1's core types are committed):
- `Backends/SDL/Sources/MetalUISDLGPU/{SDLGPUTexture,SDLGPUGraphics,SDLGPUFrameView,SDLGPUContractGuard}.swift`
- `Backends/SDL/Sources/MetalUISDL/SDLGPUDrawContext.swift` (the `view`, the doc sentence of `GA-I`) and
  `SDLWindowRenderer.swift` (guard flag around the draw call, two lines).
- `Backends/SDL/Tests/MetalUISDLTests/{SDLGPUGraphicsTests,SDLGPUContractTests}.swift`,
  `…/AppShaders/{tri.vert.hlsl,tri.frag.hlsl,id.frag.hlsl,compiled/*}` (lane 2 extends `SOURCE.sha256`).
- `docs/guides/drawing-and-gpu.md` (SDL graphics section; `text` fences), `docs/verification/human-checks.md` (§7).

Shared: `Backends/SDL` is outside the public-API census (`closeout-public-api.sh` reads `Sources/` only), so no
map row or census move is owed (`GA-L`); doc comments on every public declaration are still the rule. Record (`114-sdl-gpu-compute.md`), CLAUDE.md rule, README rows: Record phase, not a lane.
Divergences: none. `MetalUIScene`, `MetalUILayout`, `shaders.metal`, `replay.hlsl`, `SurfaceTargetTable`
untouched.

## 4. How tests drive it headless

No window is needed for compute or for offscreen graphics: `SDLGPUDevice.make()` creates a device. macOS (Metal, run by hand)
and the Linux image (lavapipe, which supports compute and 32-bit buffer atomics) run it; Windows CI runs it
on WARP/D3D12. **Skip rule:** a test body begins `guard let device = SDLGPUDevice.make() else { skip }` via a
shared helper `requireGPUDevice()` whose `.enabled(if:)` condition is `SDLGPUDevice.make() != nil`; the skip
reason printed is `SDLGPUDevice.lastFailure` (named, e.g. "no Vulkan ICD"). The skip is itself measured: a
test asserts that in the Linux image job and the Windows job (`METALUI_REQUIRE_GPU=1`, set by those two workflows;
the macOS CI job runs no `Backends/SDL` tests, so macOS is run by hand, `GA-L`) `make()` is non-nil, so a skip
cannot hide a regression. The surface graphics test draws through
`SDLPlatform(offscreenRenderers:)` (`TF-C`) if that path reaches `finishFrame`; lane 2 measures it and, if
not, gates on `windowsPresentFrames` like `SDLLifecycleTests` and also runs the same draw on an offscreen
texture, so the pipeline is covered either way. Every helper creating an `SDLPlatform` arms
`armMainRunLoopExitCheck()`. Compiled blobs are checked in (`GA-F`); no test needs shadercross.

## 5. Lanes

1. **Lane 1** (compute + shader path), sequential with 2. Item order: (i) the `MetalUISDLGPU` product and
   whether `@_exported import CSDL` crosses a package (`GA-B`; consumer build); (ii) obtain shadercross, write
   `append.comp.hlsl`, `compile-app-shaders.py`, check in blobs (`GA-F`); (iii) device, buffers, worker, fence,
   upload/download; (iv) compute pass; (v) library + locate; (vi) tests C1–C9; (vii) docs; (viii) Linux image
   and Windows VM runs.
2. **Lane 2** (graphics, debug, inventory).

## 6. Tests, each with its red-before and the mutation that must redden it

Red-before = fails before the code exists (does not compile or the symbol is absent); each mutation is applied
to a committed tree, restored from a copy, the full unfiltered suite run, reddened tests named in the record.

Lane 1:
- **C1 `anAtomicAppendKernelEmitsExactlyTheThreadsThatPass`**: `append.comp.hlsl`, 1024 threads, each with
  `v = i*7 % 13`, appends `i` when `v < 5` through `InterlockedAdd` on word 0; downloads the buffer; asserts the
  counter equals the CPU-computed count and the sorted payload equals the CPU list. Mutations: (a) the shader's
  predicate `<5` to `<6` (reddens count); (b) `download` skipping the fence wait (zeros read); (c) dispatch
  group count halved (half the threads). All three must redden C1 only.
- **C2 `aStorageBufferRoundTripsUploadedBytes`**: upload 4 KiB pattern, download, equal; and a ranged
  download returns exactly the range. Mutation: the download offset ignored.
- **C3 `theFenceIsAwaitedOffTheMainActor`**: a long kernel; `await fence.wait()` from `@MainActor`; during the
  wait a main-actor counter task must advance (`await Task.yield()` loop bounded by a work count, no sleep),
  and `SDLGPUFence.lastWaitThreadWasMain == false` (package hook). Mutation: `wait()` calls
  `SDL_WaitForGPUFences` inline on the caller (reddens both asserts).
- **C4 `aFenceIsNeverReleasedBeforeItSignals`**: cancel a `Task` awaiting a fence; `unsignalledReleaseCount == 0`
  after the batch drains. Mutation: release in the cancellation handler (counter becomes 1).
- **C5 `reflectionFillsEveryPipelineCount`**: `append.comp.json` parsed into samplers/ro/rw storage/uniform
  counts and thread counts equal to the literals; mutation: swap the ro/rw fields in the parser.
- **C6 `theShaderLibraryLooksBesideTheExecutableThenTheSourceTree`** (like `SDLShaderDirectoryTests`): order and
  the error naming both directories; mutation: swap the search order.
- **C7 `aCheckedInAppShaderBlobMatchesItsSource`**: recompute SHA-256 of each source; equals `SOURCE.sha256`.
  Mutation: add one byte to `append.comp.hlsl`.
- **C8 `aMissingGPUIsNamedNotTrapped`**: `make()` with `SDL_GPU_DRIVER` forced to an unknown name returns nil
  and `lastFailure` contains that name. Mutation: `make` force-unwraps (traps).
- **C9 `aBatchOnTheWorkerRacesTheWindowFrameWithoutFault`** (borrowed device, `windowsPresentFrames` gated):
  200 frames of a surface draw while 50 batches run on the same device; no SDL error, all fences signal, results
  correct. Mutation: remove the creation lock (no deterministic red expected; recorded as an unproven
  instrument per the practices, kept as a stress pin, not counted as a mutation-verified one).
- **C10 `aBorrowedDeviceIsNotDestroyed`**: counter `devicesDestroyed` unchanged after the wrapper deinits;
  an owned one moves it by one. Mutation: destroy in `deinit` regardless.

Lane 2:
- **G1 `anInstancedDepthTestedMSAAResolvedTriangleSetMatchesItsReference`**: three instances of one triangle at
  different depths with overlapping area, 4x MSAA resolved into the surface target (or an offscreen texture
  when no frame presents); read back; interior points equal the CPU reference's colours exactly (nearest
  instance wins by depth), and at least one edge pixel is strictly between its neighbours' colours (proves the
  resolve). Mutations: sample count 4→1 (edge assert red); depth compare `LESS`→`ALWAYS` (overlap colour red);
  instance count 3→2 (a triangle missing); resolve store-op `STORE`→`DONT_CARE` (target not written).
- **G2 `anIDPassReadsBackTheInstanceUnderAPixel`**: instance index written to an `R32_UINT` target; the
  downloaded word at three pixels equals the instances' ids, background 0. Mutation: write the vertex index.
- **G3 `generatedMipmapsOfAnR8TextureAverageTheirParents`**: uploads a 16×16 R8 checker, generates mipmaps,
  mip 2 downloaded equals the box-average within one level of quantisation. Mutation: skip `generateMipmaps`.
- **G4 `aVertexStageReadsAStorageBuffer`**: positions come from a storage buffer; image equals the reference.
  Mutation: bind the buffer at slot 1.
- **D1 `anOpenPassAtTheEndOfADrawTrapsInDebug`**, **D2 `aWaitInsideADrawTrapsInDebug`** (exit tests, `#if DEBUG`,
  macOS and Linux): the draw leaves a pass open / calls `waitForIdle`; the process traps with the contract's
  sentence. Mutation: the guard's flag set after the draw instead of before (D2 red); the open-pass count not
  incremented (D1 red).
- **D3 `theFrameViewDeclaresNoSubmittingVerb`** (source scan of `SDLGPUFrameView.swift` for `submit|cancel|wait|
  acquire`): mutation: add `func submit()` to the view. A typecheck guard cannot reach here (the root package
  builds without the `SDL` trait), recorded as the reason.
- **D4 `theSurfaceDrawStillAddsNoSubmission`**: `mui_renderer_submission_count` unchanged by a frame whose draw
  uses the typed view (the `MV-L` item 4 pin, repeated). Mutation: the view's `beginRenderPass` submits.

Plus: the inventory/undocumented scripts print nothing (unchanged, `GA-L`); `swift test --build-system native` unfiltered shows the
printed count (3717 plus root tests added: none expected, the new tests live in `Backends/SDL`); the Linux
image runs `Backends/SDL` (`docker run … swift test --skip-build`); the Windows VM/CI runs C1–C8 (blob DXIL).

## 7. Demo, guides, human checks

- **Demo:** none. `MetalUIDemo` is the macOS app and `MetalUISDLDemo` draws MetalUI content; the guide
  carries the worked compute example (`text` fences). The fourteen demo images are 0 px (`compare.sh`).
- **Guides:** `cross-platform.md` section "Your own GPU work on SDL" (compute, shaders, off-main fence, the
  window-device caveat of `GA-D`); `drawing-and-gpu.md` section "A pipeline of your own into a `GPUSurface`".
  Both `text` fences, so `GuideDocCheck` needs no mirror (`DG-L`); behaviour words carry `(pin: …)` where the
  checker applies. `docs/packaging.md` 4a: build with the script, ship `MetalUIAppShaders` beside the executable.
- **Human checks (new group `GA`):** GA1 Linux or Windows desktop, a window with an instanced MSAA surface
  draws and resizes without a stale target; GA2 compute on real GPU hardware on Windows (D3D12) and Linux
  (Vulkan), not lavapipe/WARP; GA3 a moved, shipped app finds `MetalUIAppShaders` (like `X1`); GA4 the debug
  trap's message reads clearly in a real console.

## 8. Deferred (named, with owner)

Indirect dispatch/draw; compute storage textures; a window-device accessor outside a draw; raw-call detection;
buffer-pooling/streaming helpers; a portable (c) API. Owner: the follow-up the xp-c integration asks for.
Unproven and measured by lane 1 first: `@_exported import CSDL` across a package; MSL atomics through
shadercross; thread safety of a borrowed device under load (`GA-B`, `GA-G`, `GA-E`).
