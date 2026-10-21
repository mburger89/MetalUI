# SDL GPU gaps (XP-G14 to XP-G19) — design

Item S11, MetalCreator xp-3. Rulings: `../2026-10-21-sdl-gpu-gaps-decisions.md` (`GB-A`…`GB-K` (GB-I amends this spec)). Record `§137`.
Base `1bdead8d`; `Backends/SDL` only (library `MetalUISDLGPU`, tests, app shaders, docs). Class M, no census row (`GA-L`),
no divergence (labels 665–674 untouched), no SwiftUI claim, no probe. No `Sources/` (root) change, so the fourteen images
must stay 0 px.

## Inventory (what exists at `1bdead8d`)

`SDLGPUGraphics.swift` (sampler description at 20, pipeline description at 198, `makeSampler` at 345,
`makeGraphicsPipeline` at 366, `SDLGPURenderPass` at 506, no viewport or scissor verb); `SDLGPUTexture.swift` (the format enum
with `bytesPerTexel`, `upload` and `download` async); `SDLGPUFence.swift` (async `wait()`, waiter thread owns the SDL wait and release);
`SDLGPUDevice.swift` (`submitBatch`, static `lastFailure`, `SDLGPUError`, `waitForIdle`); `SDLGPUCompute.swift`;
`Sources/MetalUISDL/SDLGPUWindowGuard.swift` (the drawing-thread flag and the `package` test hook).

## Public API (all documented, each naming its SDL call)

```swift
// SDLGPURenderPass
@discardableResult public func setViewport(x: Float, y: Float, width: Float, height: Float,
                                           minDepth: Float = 0, maxDepth: Float = 1) -> Bool
@discardableResult public func setScissor(x: Int, y: Int, width: Int, height: Int) -> Bool
// SDLGPUGraphicsPipelineDescription: last init parameter, stored var
public var writesColor: Bool            // init(..., depth:, writesColor: Bool = true)
// SDLGPUTextureFormat
case r32Float                           // bytesPerTexel 4
// SDLGPUSamplerDescription: last init parameter
public var maxAnisotropy: Float         // init(..., maxLevel:, maxAnisotropy: Float = 1)
public var effectiveMaxAnisotropy: Float
// SDLGPUSampler
public let configuration: SDLGPUSamplerDescription   // GB-I
// readback
public struct SDLGPUTextureRegion { x, y, width, height, mipLevel }   // + static func level(_:) whole level
extension SDLGPUFence { public func waitBlocking() }
extension SDLGPUDevice { public func downloadSynchronously(_ texture: SDLGPUTexture,
                                                           region: SDLGPUTextureRegion? = nil) -> [UInt8]? }
// pipeline reasons
extension SDLGPUDevice {
    public func compileGraphicsPipeline(_:) throws -> SDLGPUGraphicsPipeline
    public func compileComputePipeline(_:) throws -> SDLGPUComputePipeline
    public var lastPipelineFailure: String? { get }
}
```

Existing `make…Pipeline`, `wait()`, `download` unchanged. `docs/api-overview.md` gets one row per group;
`docs/migration.md` one row: the new `SDLGPUTextureFormat.r32Float` case (exhaustive `switch` owes an arm).
`SDLGPUTextureRegion` is an addition to `SDLGPUTexture.swift` (lane 2 adds it with `downloadSynchronously`).

## Implementation notes

- Viewport/scissor: `SDLGPURenderPass` gains an internal `targetSize` set by `beginRenderPass`; the clamp rules are `GB-B`.
- `writesColor`: in `makeGraphicsPipeline` after the blend block (`GB-C`). `r32Float`: the `sdl` and `bytesPerTexel` switches (`GB-D`).
- Anisotropy: an internal pure `SDLGPUSamplerDescription.createInfo()` builds the `SDL_GPUSamplerCreateInfo`; `makeSampler` calls it (`GB-E`).
- Sync readback: `SDLGPUFence` gains an `NSCondition`-style wait on `signalled`; `downloadSynchronously` mirrors
  `download` but submits through an internal blocking submit (`GB-F`). Every C enum `rawValue` is converted explicitly.
- Pipeline reason: failure text captured at the failing call site under the device lock (`GB-G`).
- New app shaders (lane 1), compiled by `Backends/SDL/scripts/compile-app-shaders.py` into `Tests/AppShaders/compiled`
  with `SOURCE.sha256` (`GA-F`; an HLSL fragment keeps every vertex output of its partner in order, `GA-Q`):
  `flat.frag.hlsl` (partner `fullscreen.vert`: writes red) and `copy.frag.hlsl` (partner `fullscreen.vert`: samples level 0
  of a `Texture2D<float>` and writes `float4(v,0,0,0)` so an `r32Float` colour target holds the sampled float). If
  `shadercross` is unavailable the lane stops and reports it; it does not hand-write blobs.

## Lanes

**Lane 1 (first):** GB-B…GB-E, shaders, tests V1–V4, W1–W3, F1–F3, A1–A2 in a new `SDLGPUGapsTests.swift`
(a new file, so lane 2 never edits it), docs rows for these. **Lane 2 (after lane 1's commit):** GB-F, GB-G, tests S1–S5, P1–P3
in a new `SDLGPUReadbackAndFailureTests.swift`, docs rows for these. Both use the `GPUTestSupport.available` gate, `armMainRunLoopExitCheck()` in any helper that
creates an `SDLPlatform`, and `.serialized` suites.

## Tests (name — red before — mutation that must redden it)

"Red before" for every test is a compile failure (the API is absent); a behavioural red is the mutation.

| id | name | what it asserts | mutation (each alone, full suite) |
|---|---|---|---|
| V1 | `aViewportConfinesADrawToItsRect` | fullscreen red draw into a 32×32 cleared target under `setViewport(8,8,16,16)`: pixels inside red, outside clear (away from the edge by one) | `setViewport` ignores its arguments (full-target viewport) |
| V2 | `aScissorConfinesADrawToItsRect` | same with `setScissor(4,12,10,8)` | `setScissor` body empty |
| V3 | `aDegenerateViewportOrScissorIsRefusedWithoutATrap` | zero, negative, NaN width: `false`, whole target drawn | refusal guards removed (returns `true`) |
| V4 | `aScissorIsClampedToTheTarget` | `setScissor(-4,-4,12,12)` and `(28,28,100,100)` draw only the intersection; an empty intersection draws nothing | clamp removed |
| W1 | `aPipelineThatWritesNoColourLeavesColourAndWritesDepth` | pass 1 depth-only prepass (`writesColor:false`, depth write) at depth 0 over a blue-cleared target; pass 2 (`.load` depth, `less`) draws the triangle set: target stays blue; control arm: same with `writesColor:true` shows red after pass 1; second control: pass 2 with a **cleared** depth shows triangles | mask never set (colour written: the target turns red) |
| W2 | `writesColorDefaultsToTrueAndIsStored` | description default `true`, stored when false | stored property ignored by the initialiser |
| F1 | `anR32FloatTextureRoundTripsExactFloats` | upload `[0.1, -2.5, 1e20, .infinity, 0]` bit patterns, `downloadAsync`, equal | `sdl` maps to `R32_UINT` or `bytesPerTexel` 0 (upload refuses) |
| F2 | `anR32FloatTextureSampledNearestEqualsItsSource` | `copy.frag` into an `r32Float` colour target, download, bit-equal floats | `copy` writes `.x` scaled; or sampler `linear` |
| F3 | `r32FloatIsFourBytesPerTexel` | `bytesPerTexel == 4`, `byteCount` | table arm 0 |
| A1 | `anisotropyFieldsReachTheSamplerCreateInfo` | internal `createInfo()`: 1 → disabled; 4 → enabled 4; 64 → 16; NaN, 0.5 → disabled | enable test `>= 1` |
| A2 | `aSamplerWithAnisotropyIsBuiltAndReadsBack` | `makeSampler` non-nil on `make()`'s device with 16; `sampler.configuration.maxAnisotropy == 16`, default 1 | configuration not stored on the sampler |
| S1 | `aSynchronousDownloadReturnsTheRegionFromTheMainActor` | `@MainActor`: upload a 16×16 gradient, `downloadSynchronously` whole and a region `(3,5,4,2)`, bytes equal the CPU slice | region origin ignored |
| S2 | `waitBlockingReturnsOnlyAfterTheSignalAndReleasesNothingEarly` | held `waiterGate`: a background thread blocked in `waitBlocking` is still blocked (checked by a flag set after return) until the gate opens; afterwards `isSignalled`; `unsignalledReleaseCount == 0`, `foreignThreadWaitCount == 0` | `waitBlocking` returns at once |
| S3 | `aSynchronousDownloadInsideADrawTrapsInDebug` | exit test via `enterSimulatedDrawForTesting`, stderr contains `SDLGPUDevice.downloadSynchronously was called inside a surface draw` | assert line removed |
| S4 | `aBlockingWaitInsideADrawTrapsInDebug` | same for `SDLGPUFence.waitBlocking` (fence made before the mark) | assert line removed |
| S5 | `aSynchronousDownloadRefusesWhatItCannotRead` | region outside the level, zero size, depth and multisample textures: `nil` | bounds check removed |
| P1 | `aRefusedGraphicsPipelineSaysWhy` | a fragment blob with truncated bytes (else an invalid colour/sample combination): `compileGraphicsPipeline` throws with a non-empty description naming the stage; `makeGraphicsPipeline` is `nil` and `lastPipelineFailure` non-empty | reason dropped (empty string) |
| P2 | `aRefusedComputePipelineSaysWhy` | the compute twin, same truncation | same |
| P3 | `theOptionalPipelineVerbsKeepTheirSpelling` | `let p: SDLGPUGraphicsPipeline? = device.makeGraphicsPipeline(d)` and `try?` still compile and succeed on a good description | optional verbs removed or made throwing |

S3 and S4 run only under `#if DEBUG`. Lane 1's W1 needs a depth texture (`d32Float`, `.depthStencilTarget`); V1–V4
need read-back of an `r8g8b8a8Unorm` target through the async `download`.

## Verification (both lanes, then the orchestrator)

Root: `swift package clean`, `swift build --build-system native --build-tests`, unfiltered `swift test --build-system native --no-parallel` (summary
**4117 tests in 3 suites** expected unchanged: no root test is added), `FR-J no-argument frame: succeeded=true`, default-system build 0 `warning:`,
inventory and undocumented scripts print nothing (no root declaration). `Backends/SDL`: `fetch-accesskit.py` once, then
`swift test $(python3 scripts/fetch-accesskit.py --print-flags)` on macOS; the Linux image (`docker build` then the run with volume
`metalui-sdl-build-sdl-gpu-gaps`) on lavapipe, `METALUI_REQUIRE_GPU=1` as CI sets it. Fourteen images 0 px against `1bdead8d`
(`docs/probes/demo-pixels/compare.sh`). Mutation each pin red alone, named, `git status --short` clean after each.

## Demo expectation

None: no demo section (the layer has no demo, and a new section would owe a 1 MB-stack function). The tests are the evidence.

## Human checks (group `GB`, added at the Record phase, agent cannot run them)

- **GB1** anisotropy looks: a textured ground plane at a grazing angle with `maxAnisotropy` 1 against 16 on Metal (macOS), Vulkan (Linux) and D3D12 (Windows); expect visibly sharper distant texels at 16.
- **GB2** Windows D3D12: viewport/scissor sub-rect, depth-only prepass (`writesColor:false`), `r32Float` sampling and `downloadSynchronously` pins' behaviour on a real D3D12 device (CI compiles Windows only; the UTM VM runs the SDL GPU tests when reachable).
- **GB3** the main actor stall of `downloadSynchronously` in a real 3D viewport app (picking readback): one frame hitch, no deadlock.

## Deferred, with owner

- A zero-colour-target pipeline and pass (SDL allows it; the wrapper keeps one target): MetalCreator request if the depth-only prepass cost shows.
- Synchronous buffer download and a synchronous upload: not asked; owner a later gap request.
- Cancellation of a blocked wait: none (SDL has no cancel for `SDL_WaitForGPUFences`).
- Viewport/scissor on compute passes: n/a. Stencil, depth bias, per-target write masks: not asked.
