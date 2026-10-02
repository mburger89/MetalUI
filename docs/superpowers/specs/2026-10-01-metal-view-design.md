# MetalView — the app-owned GPU surface — design

User request 2026-10-01 (not a plan task). Binding design spec §7.7
("`MetalView` — app-owned rendering"), with §1 (the "core primitive"), §3.2
(device loss), §4.3 (side-table state), §4.4 (the redraw link and timebase),
§7.4 (frame graph: "App Metal passes" first) and §7.8 (gamma-space
`bgra8Unorm`). Rulings `MV-A`…`MV-L` (`MV-L` the critic round's corrections) in
[`../2026-10-01-metal-view-decisions.md`](../2026-10-01-metal-view-decisions.md);
probe [`../../probes/swiftui-metal-view.swift`](../../probes/swiftui-metal-view.swift)
(arms P1–P3, G1–G3, C1–C4, D1, R0–R3, recorded 2026-10-01 with the screen
unlocked). Record: `docs/record/69-metal-view.md` (the Record phase).

Branch `feat/metal-view` from `330f02b`. Baseline **2028 tests in 3 suites**,
0 goldens, 69 live divergences (next label 103).

## 1. What is built

App code encodes its own GPU work into an offscreen render target sized to
the element's laid-out bounds × the window's scale; MetalUI composites that
target into the scene at the element's z-order with the existing clip, corner
mask, opacity, layer, transitions and drag preview, and the element takes
input and accessibility exactly as an ordinary proposal leaf does.

```swift
// Portable (every platform).
public enum RedrawPolicy: Sendable, Hashable { case onDemand, continuous }   // MetalUIPlatform

@MainActor public protocol GPUSurfaceContext {                               // MetalUIPlatform
    var pixelSize: Size<DevicePixels> { get }
    var scaleFactor: Float { get }
    var time: Double { get }          // the frame's display-link target timestamp (§4.4)
    var frameIndex: UInt64 { get }    // the renderer's finished-frame count
    var isNewTarget: Bool { get }     // freshly created (cleared to transparent) this frame
    func clear(red: Float, green: Float, blue: Float, alpha: Float)   // premultiplied, gamma space
}

public struct GPUSurface: ProposalElement {                                  // MetalUI
    public init(redraw: RedrawPolicy = .onDemand,
                draw: @escaping @MainActor (any GPUSurfaceContext) -> Void)
    public init<V: Hashable>(redraw: RedrawPolicy = .onDemand, value: V,
                             draw: @escaping @MainActor (any GPUSurfaceContext) -> Void)
}

// Apple (macOS; MetalUIRender, and MetalUI behind #if canImport(MetalUIRender)).
public struct MetalDrawContext: GPUSurfaceContext {
    public let device: any MTLDevice
    public let commandBuffer: any MTLCommandBuffer   // the frame's own; do not commit
    public let target: any MTLTexture                // bgra8Unorm, renderTarget|shaderRead, private
    public func renderPassDescriptor(loadAction: MTLLoadAction = .clear,
                                     clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0))
        -> MTLRenderPassDescriptor
    // + the protocol's members
}
public struct MetalView: ProposalElement {
    public init(redraw: RedrawPolicy = .onDemand, draw: @escaping @MainActor (MetalDrawContext) -> Void)
    public init<V: Hashable>(redraw: RedrawPolicy = .onDemand, value: V,
                             draw: @escaping @MainActor (MetalDrawContext) -> Void)
}

// SDL (Backends/SDL, MetalUISDL).
public struct SDLGPUDrawContext: GPUSurfaceContext {
    public let device: OpaquePointer          // SDL_GPUDevice *
    public let commandBuffer: OpaquePointer   // SDL_GPUCommandBuffer *, the frame's own
    public let target: OpaquePointer          // SDL_GPUTexture *, B8G8R8A8_UNORM, COLOR_TARGET|SAMPLER
    // + the protocol's members
}
```

Usage:

```swift
GPUSurface(redraw: .continuous) { ctx in
    if let metal = ctx as? MetalDrawContext { encodeViewport(metal) }
    else { ctx.clear(red: 0.1, green: 0.1, blue: 0.2, alpha: 1) }
}
.clipShape(RoundedRectangle(cornerRadius: 12))
.overlay(alignment: .topLeading) { ProposalText("Preview") }
.onTapGesture { paused.toggle() }

MetalView(value: model.version) { ctx in   // redraws only when model.version changes
    let pass = ctx.renderPassDescriptor()
    let encoder = ctx.commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
    // … app pipeline, sized from ctx.pixelSize …
    encoder.endEncoding()                  // never commit/present/wait (MV-F item 5)
}
```

## 2. Sizing (`MV-B`)

The proposal on each axis; 10 on a nil axis; inf answered at inf (probe G1 =
`Canvas` = P1 `Color`; G2, an `MTKView` representable, is the separating arm
at 0). Layout is unchanged otherwise — it is a `requestNativeLeaf`.

## 3. The scene primitive (`MV-C`)

`MetalUIScene`: `PrimitiveKind.surface`; `SurfaceID(rawValue: UInt64)`;
`SurfaceTarget(id:width:height:)` (device pixels, both > 0 or trap);
`Scene.surfaces: [MUIImage]`, `Scene.surfaceTargets: [SurfaceTarget]`,
`insert(_:surface:layer:)` (dedupes by id; the quad's `texture` field indexes
`surfaceTargets`). `finalize()` breaks a surface run where the target index
changes; `isEmpty`/`clear()`/`highestLayer`/`layer(of:at:)` cover the new
arrays (side tables 6 → 8). `FixtureRun.init(scene:)` traps on `.surface`.

## 4. Each renderer (`MV-D`, `MV-E`, `MV-F`, `MV-H`)

**Portable lifecycle** — `SurfaceTargetTable<Handle>` (`MetalUIPlatform`):

```swift
public struct SurfaceTargetTable<Handle> {
    public init()
    /// Releases unreferenced entries, creates/replaces requested ones, and
    /// returns what to draw, in request order.
    public mutating func update(references: [SurfaceTarget], requests: [SurfaceDrawRequest],
                                create: (SurfaceTarget) -> Handle?, release: (Handle) -> Void)
        -> [(request: SurfaceDrawRequest, handle: Handle, isNew: Bool)]
    public mutating func didDraw(_ request: SurfaceDrawRequest)   // records value + scale
    public func handle(for id: SurfaceID) -> Handle?
    package var createdCount, releasedCount, drawnCount, liveCount: Int
}
```

(Public, because `Backends/SDL` is another package. **The table's counters
are `package`, and `package` does not cross a package boundary** (`MV-L`
item 2): `Backends/SDL` cannot read them, so `SDLWindowRenderer` keeps its
**own** `package` counters (`surfaceTargetsCreated`, `…Released`,
`surfaceDraws`), incremented inside the `create`/`release` closures it hands
the table and after each draw, as `textureUploadCount` is counted in its own
upload path. The root package's tests read the table's counters directly.) Draw decision: new → draw;
`.continuous` → draw; else `value != lastDrawnValue || scale != lastScale`.
A `create` returning nil drops that request this frame (the run draws
nothing; the frame still succeeds).

**Metal** (`MetalWindowRenderer`, per window): owns a
`SurfaceTargetTable<any MTLTexture>`. `finishFrame(scene:atlas:surfaces:)`:
atlas upload → `table.update` (create = `bgra8Unorm`, `[.renderTarget,
.shaderRead]`, `.private`, clamped to 8192, default (tracked) hazard tracking — never
`.untracked`, which would drop the cross-command-buffer ordering `MV-E`
item 6 rests on (`MV-L` item 5); release = drop the reference,
Metal keeps it alive while an in-flight buffer holds it) → for each to-draw:
if new, one clear pass to (0,0,0,0); build `MetalDrawContext`; call `draw`;
**`precondition(commandBuffer.status == .notEnqueued)`** naming `MV-F`;
`didDraw` → `renderer.encode(scene, view:, in:, surfaces: [SurfaceID: any MTLTexture])`
→ present → commit. `Renderer.encode`'s `.surface` case calls
`encodeImages` with the run's target texture (no texture → skip the run);
the old three-argument `encode` forwards `[:]`. `renderOffscreen` gains a
`surfaces:` overload for renderer-level tests.

**SDL** (`SDLWindowRenderer`, per window): owns a
`SurfaceTargetTable<UnsafeMutableRawPointer>` (create =
`mui_renderer_create_target`, release = `mui_renderer_release_texture`).
After `prepareTextures`, before `mui_renderer_finish`: `table.update`; for
each to-draw, if new `mui_gpu_clear_texture(cmd, target, 0,0,0,0)`; build
`SDLGPUDrawContext` from `mui_renderer_device`/`mui_renderer_command_buffer`;
call `draw`; `didDraw`. Then the image array passed to `mui_renderer_finish`
is `scene.images + scene.surfaces` (each surface quad's `texture` +=
`scene.textures.count`), the handle array is `textures + surfaceHandles`
(a missing handle: that run is dropped from the run list), and each
`.surface` run becomes `kind 2` with `start += scene.images.count`. No
change to `mui_renderer_finish`, `images_valid` or `replay.hlsl`. `deinit`
releases every live target. No new submission, so no new fence (the fence
rule, CLAUDE.md "Renderer") — **measured, not asserted**: the bridge gains a
fifth function, `mui_renderer_submission_count(r)` (incremented at every
`SDL_Submit…` in `SDLBridge.c` — `mui_renderer_finish`'s and
`mui_renderer_create_texture`'s), which test 3.4 reads (`MV-L` item 4).

**MetalUI** (`Frame`, `Window`): `GPUSurface.paint` →
`Frame.drawSurface(id:bounds:policy:value:draw:)`: translate and scale like
`drawImage`; pixel size `Int((pt × scale).rounded())` clamped to 8192; return
emitting nothing if a side is 0, the translated bounds miss `activeClip`, or
`activeOpacity == 0`; otherwise `surfaceRegistry.id(for: id)` (a window-owned
map from **(`GlobalElementID`, occurrence)** to `SurfaceID` — the occurrence
is how many surfaces with that same id this frame has already painted, so
two siblings sharing one `.id` (divergence 72) get two targets rather than
two requests for one, which the table traps on, `MV-L` item 1 — minting on
first sight, swept by `Window` after each frame of every key not painted
that frame), emit the quad
through `insertThroughTransitions(.surface(…))`, append a
`SurfaceDrawRequest` (time = `timestamp`) to `surfaceRequests`, and
`noteActiveAnimation()` if `.continuous`. `Window` passes
`frame.surfaceRequests` to `finishFrame`. `renderFrame` (headless) uses a
fresh registry and drops requests (doc comment says so).

## 5. Redraw policy (`MV-G`)

`.onDemand`: new target or changed `value:`/scale. `.continuous`: every
painted frame + `noteActiveAnimation()` (never `requestAnotherFrame`). No GPU
work when not painted, zero-size, fully clipped or transparent; its target is
released that frame. Divergence 103 (Canvas re-runs whenever its declaring
body re-runs, R1; MetalUI only on `value:`).

## 6. Input and accessibility (`MV-I`)

No hitbox, focus entry or accessibility record of its own; the existing
proposal modifiers and a legacy wrapper supply all of them.

## 7. Demo and human checks (`MV-J`)

`METALUI_METALVIEW_DEMO=1 swift run MetalUIDemo` (Metal: an animated fragment
shader quad compiled from MSL source at runtime, a translucent label over it,
tap to pause/resume, a second `.onDemand` surface redrawn by a `Stepper`, a
draw counter); `METALUI_METALVIEW_DEMO=1` under `MetalUISDLDemo` (SDL: the
same tree, `ctx.clear` cycling with `ctx.time`). The tree is
`metalViewDemoContent(surface:)` in `MetalUIDemoContent`, its own function
(1 MB stacks). **Expectation**: a rounded viewport animating smoothly at the
display's rate with crisp UI over it; tapping stops the animation and the
draw counter, and the window goes idle (link paused); the stepper redraws
only the small surface. `docs/verification/human-checks.md` section O lists
the looks (on-screen look, live resize, smoothness, idle when paused, 1× vs
2× and a move between displays, clip/overlay, SDL on Linux/Windows) — an
agent cannot perform them.

## 8. Lanes — three, strictly in order, disjoint files

### Lane 1 — the portable core

Files: `Sources/MetalUIScene/Scene.swift`, **new**
`Sources/MetalUIScene/SurfaceTarget.swift`; `Sources/MetalUIPlatform/Platform.swift`
(the requirement + the forwarding extension), **new**
`Sources/MetalUIPlatform/GPUSurface.swift` (`RedrawPolicy`,
`GPUSurfaceContext`, `SurfaceDrawRequest`, `SurfaceTargetTable`); **new**
`Sources/MetalUI/GPUSurface.swift`, **new** `Sources/MetalUI/SurfaceRegistry.swift`,
`Sources/MetalUI/Frame.swift`, `Window.swift`, `Transition.swift`,
`DragSession.swift`, `RenderFrame.swift` (doc), `StateTable.swift` (the
refuted line-89 comment, `MV-E` item 6). **Hand-off edits in lane 2/3 files,
signature only**: `MetalWindowRenderer.finishFrame(scene:atlas:surfaces:)`
and `SDLWindowRenderer.finishFrame(scene:atlas:surfaces:)` ignoring
`surfaces`, `Renderer.encode`'s and `SDLWindowRenderer`'s switches skipping
`.surface` runs, `FixtureRun.init(scene:)`'s `.surface` trap — so both
packages compile; nothing else of lanes 2/3. Tests: `Tests/MetalUIRenderTests`
(scene), **new** `Tests/MetalUICrossPlatformTests/SurfaceTargetTableTests.swift`
(add `MetalUIPlatform` to that target's dependencies if the import needs it),
**new** `Tests/MetalUITests/GPUSurfaceTests.swift`, **new**
`Tests/MetalUITests/GPUSurfaceCompileGuards.swift`, `Tests/MetalUITests/Fakes.swift`
(an optional spy renderer on `FakePlatformWindow`), the three test switches
over `PrimitiveKind` (`DragPreviewTests`, `DecorationPaintTests`,
`SceneFinalizeIdentityTests` — a `.surface` arm, no answer change).
Docs: `docs/divergences.md` (row 103, the "Not offered" rows of `MV-F`
item 6, header count 69 → 70, next label 104), `docs/migration.md` (`MV-K`
item 3).

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 1.1 | `surfaceRunsBreakWhereTheTargetChanges` (RenderTests) | `insert(_:surface:)` absent | M1a: drop the target-index check from `finalize()`'s run continuation for `.surface` |
| 1.2 | `aSceneHoldingOnlyASurfaceIsNotEmpty` | ditto | M1b: `isEmpty` omits `surfaces` |
| 1.3 | `aSurfaceTargetIsCarriedOncePerID` | ditto | M1c: append a target per insert (no dedupe) |
| T1 | `sceneSideTablesArePlainIntArraysThatKeepCapacityAcrossClear` | literal 6 → 8 (T row, `MV-C` item 2) | M1d: `clear()` leaves `surfaceLayer` un-cleared |
| 1.4 | `aRequestedTargetIsCreatedAndDrawnOnceThenReused` (CrossPlatform) | table absent | M1e: drop the value comparison (always draw) |
| 1.5 | `aChangedValueRedrawsAndAnUnchangedOneDoesNot` | ditto | M1f: `didDraw` does not store the value |
| 1.6 | `aContinuousRequestDrawsEveryFrame` | ditto | M1g: treat `.continuous` as `.onDemand` |
| 1.7 | `aResizeReplacesTheTargetAndARescaleRedrawsWithoutReallocating` | ditto | M1h: compare only width; M1i: ignore scale |
| 1.8 | `anUnreferencedTargetIsReleasedAndAGhostsTargetIsKeptUndrawn` | ditto | M1j: release every entry without a request; M1k: never release |
| 1.9 | `aReferenceWithoutARequestOrEntryCreatesNothing` | ditto | M1l: create on reference |
| 1.10 | `twoRequestsForOneSurfaceTrap` (exit test) | ditto | M1m: drop the precondition |
| 1.11 | `aSurfaceAnswersItsProposalAndTenOnANilAxis` (G1, G2) | element absent | M1n: answer 0 on a nil axis |
| 1.12 | `aSurfacesTargetIsItsBoundsTimesTheScaleRounded` (D1; 100×60@2 → 200×120; 101×61@1.5 → 152×92; 9000 pt@1 → 8192) | ditto | M1o: `floor` for `rounded`; M1p: drop the clamp |
| 1.13 | `aSurfaceKeepsItsIDAcrossFramesAndTwoPlacementsGetTwo` | ditto | M1q: mint a fresh id every frame |
| 1.13b | `twoSiblingSurfacesSharingOneIDGetTwoTargets` (`MV-L` item 1; divergence 72's shape, `HStack { GPUSurface{…}.id("a"); GPUSurface{…}.id("a") }`, through a real `Window` with the **spy** renderer, which records requests and runs no table, so the unfixed case reads as a wrong answer rather than a process trap: two requests with distinct `SurfaceID`s, the same two on a second frame; `try #require` on the count before indexing) | ditto | M1q′: key the registry by `GlobalElementID` alone (one id twice) |
| 1.14 | `aZeroSizedClippedOrTransparentSurfaceRequestsNothing` (three arms + a painted control arm) | ditto | M1r: drop the clip test; M1s: drop the opacity test (each reddens only its arm) |
| 1.15 | `aContinuousSurfaceKeepsTheWindowAnimatingOnlyWhilePainted` — asserts `hasActiveAnimations == true` **and** `wantsAnotherFrame == false` while painted, both false after it leaves (`MV-L` item 3: without the second clause M1u stays green, since either flag keeps the window drawing) | ditto | M1t: delete `noteActiveAnimation()`; M1u: `requestAnotherFrame()` in its place |
| 1.16 | `theWindowHandsTheFramesSurfaceRequestsToItsRenderer` (spy renderer) | requirement absent | M1v: `Window` calls `finishFrame(scene:atlas:)` |
| 1.17 | `aSurfaceQuadTakesTheActiveClipRadiiOpacityAndLayerAsAnImageDoes` (C1–C3; an `Image` arm in the same place is the comparison, an unclipped arm separates) | ditto | M1w: emit with no `activeClip` |
| 1.18 | `aRemovedSurfacesGhostReferencesItsTargetWithoutARequest` (`.transition(.opacity)`) | ditto | M1x: drop `.surface` from `TransitionEffect.apply`'s replay (ghost loses the quad) |
| 1.19 | `aDraggedSurfacesPreviewReplaysItsQuad` | ditto | M1y: `replayed(mask:layer:)` drops `.surface` |
| 1.20 | `aSurfaceRegistersNoHitboxOrAccessibilityButTakesATapThroughOnTapGesture` | ditto | M1z: `GPUSurface.prepaint` inserts a hitbox (bare arm reddens) |
| 1.21 | `theSevenRetentionSlotsAreMutuallyDistinct` | unchanged, green | — (must not move) |
| G1.1 | `theGPUSurfaceSpellingsCompileFromAPlainImport` (whole-file) | — | mutate once red: misspell `RedrawPolicy.continuous` in the fixture |
| G1.2 | `aWindowRendererWithoutTheSurfacesFinishFrameDoesNotCompile` (whole-file, plain `import MetalUIPlatform`) | — | mutate once red: add a default implementation in a scratch copy |

### Lane 2 — the Metal renderer, `MetalView`, the demo

Files: `Sources/MetalUIRender/MetalWindowRenderer.swift`, `Renderer.swift`,
**new** `Sources/MetalUIRender/MetalDrawContext.swift`, **new**
`Sources/MetalUI/MetalView.swift`, `Sources/MetalUIDemo/main.swift`, **new**
`Sources/MetalUIDemoContent/MetalViewDemo.swift`, `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift`
(the new tree added). Tests: **new** `Tests/MetalUITests/MetalViewTests.swift`,
**new** `Tests/MetalUIRenderTests/SurfaceCompositingTests.swift`, **new**
`Tests/MetalUITests/MetalViewCompileGuards.swift`. The shared parity literal
(§4) is defined here in a comment-documented constant both lanes cite.

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 2.1 | `aSurfaceFillIsCompositedOnTheFirstFrame` (window, `ctx.clear` red, pixel read inside and outside) | lane 1's stub ignores surfaces | M2a: run the draws after `renderer.encode`; M2b: skip `.surface` runs in `encode` |
| 2.2 | `anOnDemandSurfaceKeepsItsContentsWhenTheWindowRedrawsForAnotherReason` (draw count stays 1, pixel stays red) | ditto | M2c: release and recreate every target every frame |
| 2.3 | `aSurfaceIsClippedRoundedAndFadedExactlyAsAnImage` (C1–C3; pixel-equal to an `Image` of the same colour; an unclipped arm separates; the parity literal) | ditto | M2d: bind the atlas/wrong texture for surface runs |
| 2.4 | `aSurfaceDrawReceivesItsDevicePixelBgraTargetScaleAndTime` (scale 2, `simulateTick(timestamp:)`) | ditto | M2e: allocate `.bgra8Unorm_srgb`; M2f: size in points |
| 2.5 | `aContinuousSurfaceDrawsOnEveryTickAndAnOnDemandOneOnce` | ditto | M2g: draw only new targets |
| 2.6 | `twoWindowsKeepTheirOwnTargets` (both at `SurfaceID(1)`, **different sizes**, one shared `Renderer`; frames drawn **alternately** A, B, A, B — each window's draw count stays 1 and `createdCount` 1, pixels per window; `MV-L` item 6: drawn A, A, B, B a shared table would release once and still read 1 on the second of each pair) | ditto | M2h: move the table onto the shared `Renderer` |
| 2.7 | `aSurfacesTargetIsReleasedWhenItsElementLeaves` (`package` counters) | ditto | M2i: never call `release` |
| 2.8 | `aSurfaceDrawThatCommitsTheCommandBufferTraps` (exit test) | no check | M2j: drop the status precondition |
| 2.9 | `aMetalViewDrawsWithTheRenderersDeviceAndTheFramesCommandBuffer` (encodes its own pass → no "encoder already active") | `MetalView` absent | M2k: `MetalView` forwards a fresh command buffer |
| 2.10 | `aMetalViewGivenANonMetalContextTraps` (exit test, internal thunk) | ditto | M2l: skip instead of trap |
| 2.11 | `aSurfaceRunSamplesItsTargetThroughTheImagePipeline` (RenderTests, `renderOffscreen(_:size:surfaces:)`, a hand-filled texture under a rounded mask) | overload absent | M2m: offset the texture index by one |
| 2.12 | `theMetalViewDemoTreeRequestsOneContinuousAndOneOnDemandSurface` | tree absent | M2n: demo's main surface `.onDemand` |
| — | `everyProductionTreeBuildsOnAOneMegabyteThread` (gains the tree) | — | must stay green |
| — | new target cleared to transparent (`MV-E` item 5) | **unpinned by pixels**: fresh private memory usually reads zero; stated, not hidden | — |
| G2.1 | `theMetalViewSpellingsCompileFromAPlainImport` (whole-file) | — | mutate once red |

### Lane 3 — the SDL renderer, the SDL demo, the checks

Files: `Backends/SDL/Sources/SDLBridge/SDLBridge.c` and its header,
`Backends/SDL/Sources/MetalUISDL/SDLWindowRenderer.swift`, **new**
`Backends/SDL/Sources/MetalUISDL/SDLGPUDrawContext.swift`,
`Backends/SDL/Sources/MetalUISDLDemo/main.swift`; tests **new**
`Backends/SDL/Tests/MetalUISDLTests/SDLSurfaceTests.swift`,
`Backends/SDL/Tests/ReplayFixtureTests/ReplayFixtureTests.swift` (one exit
test); docs `docs/verification/human-checks.md` (section O),
`docs/api-overview.md` (a "GPU surfaces" section). Arm
`armMainRunLoopExitCheck()` in every new helper that creates an
`SDLPlatform`; convert every SDL enum explicitly (Windows).

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 3.1 | `anSDLSurfaceFillMatchesTheMetalParityLiteral` (offscreen renderer; lane 2's scene and literal, `ParityTolerance`) | lane 1's stub skips `.surface` | M3a: skip the quad append; M3b: forget the texture-index offset |
| 3.2 | `anSDLSurfaceIsDrawnBeforeTheSceneAndKeptAcrossFrames` (draw count 1 over two frames, pixels equal) | ditto | M3c: draw after `mui_renderer_finish`; M3d: recreate each frame |
| 3.3 | `anSDLSurfaceTargetIsReleasedWhenNoLongerReferenced` | ditto | M3e: never release |
| 3.4 | `surfaceFramesSubmitOnceAndNeverReleaseAnUnsignaledFence` (back-to-back offscreen frames each holding a NEW surface: `mui_renderer_submission_count` rises by exactly 1 per frame, `unsignaledFenceReleaseCount == 0`; `MV-L` item 4) | ditto | M3f: submit the new target's clear in its own command buffer (reddens the submission clause only); M3f′: `retire_fence` → `release_fence` in `mui_renderer_finish` (reddens the fence clause and the existing `backToBackFramesNeverReleaseAnUnsignaledFence` — name both) |
| 3.5 | `theSDLDrawContextCarriesTheFramesCommandBufferAndTarget` (handles non-nil, `pixelSize`, `isNewTarget` true then false) | context absent | M3g: pass a fresh command buffer |
| 3.6 | `aSceneWithASurfaceIsNotRecordable` (exit test, `ReplayFixtureTests`) | lane 1's trap present → green on arrival; mutate | M3h: map `.surface` to `.image` |

### Every lane

Commit first; mutations from a copy; full unfiltered `swift test
--build-system native --no-parallel`, read the summary line, `git status
--short` after each, name every reddened test. Each new guard mutated red
once. `swift package clean` after the `Scene`/`PrimitiveKind` change (public
stored properties and a public enum case cross module boundaries). Test
comments cite the probe arm ids they rest on (G1, G2, D1, C1–C3, R0–R3), so
the closeout inventory's `CITE` check can map the new public families (the
Record phase updates `docs/probes/closeout-inventory-map.tsv`).

## 9. Expected counts and checks

Root suite **2028 + 23 (lane 1: 1.1–1.20, 1.13b and G1.1–G1.2; T1 and 1.21
are existing tests) + 13 (lane 2: 2.1–2.12 and G2.1) = 2064**; `Backends/SDL` +6
(ReplayFixtureTests +1, MetalUISDLTests +5) on macOS and Linux. Each lane
reports its measured figure; the Record phase re-takes. Guards +3. 0 px
against `330f02b` in all fourteen offscreen images; `Expected.swift`
unedited; `swift:6.4-noble` builds the root package (the portable half) and
`Backends/SDL`. The real-window capture runs if the lock probe reads
unlocked (it did at design time).

## 10. Not built (`MV-F` item 6)

Depth attachment, EDR/`rgba16Float`, a per-element error channel,
device-loss rebuild, `NSViewRepresentable`, direct-mode drawing into
MetalUI's pass (spec §14 already rules texture mode only),
`IOSurface`/`CVPixelBuffer` content (§7.7's "later"), an SDL replay fixture
holding a surface.
