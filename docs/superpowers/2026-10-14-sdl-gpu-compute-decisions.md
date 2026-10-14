# SDL GPU for apps (compute, graphics, shaders) — decisions

Rulings for items S5 and S6 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**),
MetalCreator's SDL-port gaps 1 and 2 (developer-c0, 2026-10-13/14), RAISED: they block its xp-c track (GPU
meshing of implicit geometry on all three platforms). Prefix `GA-`. **Next unused: `GA-N`.**
Spec: [`specs/2026-10-14-sdl-gpu-compute-design.md`](specs/2026-10-14-sdl-gpu-compute-design.md).
Record: `../record/114-sdl-gpu-compute.md` (Record phase). Branch `feat/sdl-gpu-compute` from `fb9a7e42`.
Divergence labels reserved 445–454: **none taken** (`GA-J`).

Sources of truth. SwiftUI has no GPU API: nothing here is a SwiftUI-facing claim and no probe is owed
(`GA-J`). gpui, where SwiftUI has none: gpui reaches the GPU through its own renderer abstraction and gives an
app no compute or pipeline access — **recalled from memory, the gpui source is not on this machine**, so it is
context, not a cited precedent. The facts below come from SDL 3.4.18's headers on this machine
(`/opt/homebrew/include/SDL3/SDL_gpu.h`) and from this repository's source at `fb9a7e42`; the Linux image
builds SDL `release-3.4.16` (`Backends/SDL/linux/Dockerfile`), so every SDL call used must exist there.

## GA-A — (b) a thin typed wrapper in the SDL backend, with (a) the raw module as the escape hatch; (c) is refused

**Question.** Raw SDL export, a typed wrapper, or a portable GPU API?

**Evidence.** `SDLGPUDrawContext` today hands out three `OpaquePointer`s (`SDLGPUDrawContext.swift:40`), and
`CSDL` is a `.systemLibrary` that is not a product (root `Package.swift:245`), so an app cannot call
`SDL_BeginGPURenderPass` without its own SDL3 binding. The contract an app must keep (never submit, cancel,
wait, present, release the target; end every pass it begins) is undetectable on raw pointers: SDL3 has no
command-buffer state query (the doc comment's own words). MetalCreator already does Metal itself through
`MetalDrawContext`.

**Ruling.** (b) a small Swift layer over SDL_GPU named after it (`SDLGPUDevice`, `SDLGPUBuffer`,
`SDLGPUTransferBuffer`, `SDLGPUTexture`, `SDLGPUSampler`, `SDLGPUShader`, `SDLGPUGraphicsPipeline`,
`SDLGPUComputePipeline`, `SDLGPUCommandBuffer`, `SDLGPURenderPass`, `SDLGPUComputePass`, `SDLGPUFence`;
`SDL_CreateGPUBuffer` is `device.makeBuffer`, so SDL's documentation applies), every wrapper exposing its raw
pointer (`.raw: OpaquePointer`); and (a) the raw C module re-exported by the same product (`GA-B`), so what the
wrapper omits is still reachable. No (c): a portable cross-backend GPU API is a product boundary of its own,
Metal apps have `MetalDrawContext`, and a lowest-common-denominator layer would hide Metal's features from
them. The wrapper adds no verb SDL lacks except three conveniences that are SDL sequences, not inventions
(`download`: transfer buffer, copy pass, fence, map; `generateMipmaps`; shader-library lookup, `GA-F`).
**Cost if wrong.** A wrapper type that hides a needed SDL field forces the app to the raw pointer (always
available), so the cost of a missing wrapper is bounded by the escape hatch; the cost of a wrong
name is a rename before any release. (b) without (a) would trap an app at the first missing call.

## GA-B — A new product `MetalUISDLGPU`, a Swift target over `MetalUISDL`, re-exporting `CSDL`

**Question.** Where does it live, and how does the raw module reach an app?

**Evidence.** `MetalUISDL`/`SDLBridge` are products behind traits `SDL`/`AccessKit` (`PX-J`); `CSDL` is a
system-library target that `SDLBridge` depends on under the `SDL` trait only, with the `SDL3` link declared in
`SDLBridge`'s linker settings because a module map's `link` applies only where Swift imports `CSDL` (root
`Package.swift:248`). A compute-only app needs no window, so it should not need `SDLPlatform`.

**Ruling.** A target `MetalUISDLGPU` (path `Backends/SDL/Sources/MetalUISDLGPU`), a library product of the same
name behind the `SDL` trait, depending on `MetalUISDL` (for `SDLGPUDrawContext`, `GA-D`), `SDLBridge` and
`CSDL`, declaring `@_exported import CSDL` so **one `import MetalUISDLGPU` gives the wrapper and every `SDL_`
symbol**. The `SDL3` link is declared on this target too (the `SDLBridge` reason). Both manifests declare it
(root, and `Backends/SDL/Package.swift`). **Unproven, lane 1 item 1:** that `@_exported import` of a system
library crosses a package boundary in a consumer built with the `SDL` trait; the scaffold's cross-platform
build test (`aGeneratedPackageBuildsAgainstThisCheckout`) is the measure. If it does not, the product ships a
module map copy `SDLGPURaw` (a `.systemLibrary` cannot be a product, `SwiftPM` refuses it) and the guide tells
an app to depend on `CSDL` by path; the ruling's wrapper half is unchanged. `MetalUIScene` stays free of SDL
and Metal types (`PS-A`): nothing here touches it.
**Cost if wrong.** An app writes one more dependency line.

## GA-C — Slice: compute, storage buffers, atomics, readback, off-main fence and the shader path first; graphics and the debug check second

**Question.** Full scope or a slice?

**Evidence.** The user's order: compute blocks xp-c. Graphics needs the same device, buffer and shader types,
so it cannot go first; it is mostly passes and pipeline descriptions over them.

**Ruling.** All of S5+S6 is in scope, in two lanes on disjoint files, lane 1 first (spec §5): **lane 1**
device, buffers, transfer, compute pipeline and pass, fence, readback, the shader library and script,
packaging doc; **lane 2** textures (MSAA, depth, mipmapped r8), samplers, graphics pipeline and render pass,
the surface-draw views and the debug check. Lane 2 starts when lane 1's core types are committed. Deferred and
carried, named: `SDL_DispatchGPUComputeIndirect` and `SDL_DrawGPU…Indirect` (no MetalCreator need; they are one
raw call, `GA-A`), compute **storage textures** (`readwrite` textures need `SIMULTANEOUS`, a limited format
set: MetalCreator's list asks for buffers; owner a follow-up), a tracked hook on raw calls (impossible, `GA-I`).
**Cost if wrong.** The carried items are reachable through `.raw` today.

## GA-D — Two ways to a device: a standalone headless device, and a borrowed view of the window's

**Question.** Does compute run on the window's device or its own?

**Evidence.** `SDLWindowRenderer` owns one `SDL_GPUDevice` (`mui_renderer_device`, `SDLBridge.h`); the replay
path already makes devices with no window (`replay_create`, `SDL_CreateGPUDevice(format, true, driver)`).
SDL resources belong to one device: a buffer made on a standalone device cannot be bound in the frame's
command buffer. xp-c meshes into a buffer the surface then draws, so it needs the window's device; an offline
batch with no window (a CLI, a test) needs its own.

**Ruling.** `SDLGPUDevice.make(debug:preferring:)` creates and owns a standalone device (`SDL_CreateGPUDevice`
with the formats the build ships: SPIRV | DXIL | MSL, so the app's blobs choose the driver, `GA-F`) and
destroys it on `deinit`; it returns `nil` with a reason string (`SDLGPUDevice.lastFailure`) when no GPU or driver
answers. `SDLGPUDevice(borrowing: ctx)` wraps `SDLGPUDrawContext.device`: not owned, never destroyed, valid for
the window renderer's life (documented; a use after the window closes is the app's bug, and the wrapper's
`isAlive` token turns a stale handle into a trap in debug, `GA-I`). A compute batch on the window's device
**adds a submission, but it is the app's explicit one**: the fence rule and "no added submission for a surface"
bind surface *draws* (they run inside the frame's buffer); an offline batch is its own command buffer, submitted
by the wrapper, counted on the wrapper's own counter, never on `mui_renderer_submission_count`.
Ordering across the two: SDL guarantees only that a submission's commands begin before a later submission's, so
**a batch whose output a frame reads must be awaited (its fence) before the draw that reads it**; the guide says
so. No platform accessor for the window's device outside a draw is added (`GA-C` carried): an app borrows it
from its first draw and keeps the wrapper.
**Cost if wrong.** If a borrowed device proves unsafe off the main thread (`GA-E`), apps lose the shared-buffer
path and fall back to a standalone device plus an upload (one copy).

## GA-E — Threads: a command buffer lives and dies on one thread; the fence is awaited on a dedicated thread

**Question.** Which SDL_GPU calls are safe off the main thread, and how does the app await off the main actor?

**Evidence (headers, 3.4.18).** `SDL_AcquireGPUCommandBuffer`: "may only be used on the thread it was acquired
on … should be submitted on the thread it was acquired on"; `SDL_SubmitGPUCommandBufferAndAcquireFence`: "must
be called from the thread the command buffer was acquired on"; swapchain calls: the window's thread
(`\threadsafety` at lines 4141…4351); `SDL_GetGPUDeviceProperties`: any thread; `SDL_Map/UnmapGPUTransferBuffer`
and release of a buffer or texture: **not thread safe against concurrent use of the same object**
(lines 2949, 2972). The header documents no general guarantee that resource creation, `SDL_WaitForGPUFences`
or `SDL_QueryGPUFence` are callable from any thread, though SDL's own multi-threaded design note (line 53:
"multiple command buffers, maybe configured across multiple threads") implies command-buffer recording is.

**Ruling.** (1) One **batch** is recorded and submitted on one thread: `device.submitBatch { cb in … }` is
`async`, runs the closure on a dedicated serial `SDLGPUWorker` thread (a `Thread`, not the cooperative pool, so
a blocking wait cannot starve it) that acquires, records, submits with `SDL_SubmitGPUCommandBufferAndAcquireFence`
and returns the fence. (2) `await fence.wait()` hops to a second dedicated waiter thread that calls
`SDL_WaitForGPUFences`, then resumes the continuation; the main actor is never blocked. (3) Resource creation
(`make…`) and release take one `device.lock` (an `NSLock`-equivalent portable `Mutex`) because the headers do
not promise them thread-safe: the cost is nanoseconds against GPU object creation, and it removes the question for the app's calls. It does **not** cover the window renderer's own main-thread creations on a borrowed device: that is the unproven half, which is why C9 is a stress pin and the degrade path stands.
The one thing the lock cannot cover is the header's rule that a buffer is not used while another thread
releases it: handles are classes whose `deinit` releases, and a batch retains every handle it touches until its
fence is released. (4) The window's own frame (main actor) and a batch on the worker run concurrently on the
borrowed device; **verified on macOS only by the stress test C9 (the Linux image's offscreen driver presents no frame, so C9 is gated off there; Linux and Windows are human check GA2). If the borrowed device races, the ruling degrades to "borrowed devices submit on the main actor"
(`GA-D` cost) rather than blocking compute.** Cancelling a waiting `Task` does not release the fence: the waiter
thread keeps it and releases it after it signals (the fence rule: never release an unsignalled fence, §61 §10).
**Cost if wrong.** An undocumented thread-safety assumption is exactly what the lock and the stress test are for;
a failure appears as a measured crash in C9, not in a user's app.

## GA-F — Shaders: checked-in blobs, built by a script from app HLSL, found like `PX-P`

**Question.** How does an app build and ship its own shaders, and does CI regenerate them?

**Evidence.** `Backends/SDL/scripts/compile-shaders.py` runs shadercross (HLSL to SPIR-V, then SPIR-V to MSL,
DXIL and reflection JSON) over `replay.hlsl` and writes `SOURCE.sha256`, which the macOS workflow checks
(`sdl-gpu-linux.yml:101`); shadercross is **not installed on this machine** and not in the Linux image, so
CI cannot rebuild blobs; the runtime finds the renderer's own beside the executable first
(`MetalUISDLShaders`, `PX-P`, `docs/packaging.md` section 4).

**Ruling.** The test kernels' blobs are **checked in and verified by hash, not regenerated** — the
`replay.hlsl` way — so CI stays reproducible with no shadercross: `Backends/SDL/Tests/…/Shaders/` holds
sources and `compiled/` with a `SOURCE.sha256` listing every source, and test C7 recomputes it
(`aCheckedInAppShaderBlobMatchesItsSource`, so a source edit without a rebuild is red on any machine). For
apps, `Backends/SDL/scripts/compile-app-shaders.py --shadercross P --source DIR --out DIR` takes every
`*.vert.hlsl`, `*.frag.hlsl` and `*.comp.hlsl` (stage from the suffix, entry `main`), emits `.spv`, `.msl`,
`.dxil` and `.json` exactly as the renderer's script does, and writes `SOURCE.sha256`; it is a generalisation of
`compile-shaders.py`, which is left as is. At runtime `SDLGPUShaderLibrary(directory:)` loads blobs for the
device's driver (`SDL_GetGPUDeviceDriver`: metal→`.msl` entry `main0`, vulkan→`.spv`, direct3d12→`.dxil`, as the
renderer does at `SDLBridge.c:208`) and reads the reflection JSON for the sampler, storage and uniform counts
and the thread counts, so the app never counts by hand and a mismatch cannot reach the driver.
`SDLGPUShaderLibrary.locate(directoryName:sourceTree:)` searches **`MetalUIAppShaders` beside the executable
first** (name overridable), then an `sourceTree` URL the app passes (no `#filePath` magic in the library: the
renderer's source-tree fallback is its own, the app's is its argument), and fails naming both directories — the
`PX-P` order and error shape. `docs/packaging.md` gains section 4a with the copy recipe.
Obtaining shadercross is the author's job: SDL_shadercross's release binaries or a source build; the guide says
so and names `--shadercross` as the only dependency. **Cost if wrong.** A reviewer cannot rebuild a blob on a
machine without shadercross, but the hash check still proves it is the committed source's.

## GA-G — Atomic append is a storage-buffer counter; SDL_GPU has no append buffer

**Question.** How does a kernel emit a variable triangle count per brick?

**Evidence.** SDL_GPU has no append/consume buffer type. HLSL `InterlockedAdd` on a `RWByteAddressBuffer`
word compiles through shadercross to SPIR-V `OpAtomicIAdd` and MSL `atomic_fetch_add_explicit`; the header's
atomics note (line 894) concerns textures only. **Unmeasured on this machine's Metal path** — no shadercross.

**Ruling.** The pattern is the documented one: a read-write storage buffer holds `[counter | payload…]`; a
thread claims a slot with `InterlockedAdd(buf.counter, n, slot)`; the app downloads the 4-byte counter first
(`device.download(buffer, range: 0..<4)` or the whole buffer) then the first `counter` payload records.
`SDLGPUBuffer` is created with `.computeStorageWrite | .computeStorageRead` (and `.vertex`/`.indirect`
where the graphics path reads it); a `fill(zero:)` convenience records a copy-pass clear of the counter
before a dispatch. Test C1 is the measurement: if the MSL path refuses the atomic on macOS the lane records it,
and the ruling becomes a documented constraint "append on Metal needs `InterlockedAdd` on a `uint` word of a
byte-address buffer only", never a silent approximation.
**Cost if wrong.** A backend without 32-bit buffer atomics (none of Metal, Vulkan, D3D12 lacks them) would make
the counter pattern unavailable; apps would two-pass (count, then emit).

## GA-H — Graphics: pipelines into a surface through a view of the frame's own buffer

**Question.** How does an app draw its own pipeline into a `GPUSurface` target?

**Evidence.** The target is `B8G8R8A8_UNORM`, colour-target + sampler usage, persistent, premultiplied, cleared
when new (`SDLGPUDrawContext` doc); the draw runs inside `finishFrame` in the frame's own buffer, before
MetalUI's pass (`MV-F`). MSAA needs a multisample texture and `STORE_OP_RESOLVE` into the single-sample target;
depth needs its own `D32_FLOAT` texture; both persist per surface or the app re-makes them every frame.

**Ruling.** `SDLGPUDrawContext` gains `view: SDLGPUFrameView` (non-owning wrapper of `commandBuffer` and
`target`, a `package` initialiser, so app code cannot forge one) with `beginRenderPass(color:depth:)` returning
`SDLGPURenderPass`, `uploadAndCopy` helpers, and **no** `submit`, `cancel`, `acquireSwapchain`, `wait`; the
forbidden verbs are absent by construction (`GA-I`). `SDLGPUTexture` covers `sampleCount: 1|2|4|8`, `D32_FLOAT`
depth, `R8_UNORM` with `levelCount` and `generateMipmaps(in:)` (`SDL_GenerateMipmapsForGPUTexture`, which
needs a command buffer, hence a frame view or a batch), 2D only (the list asks for no more). Pipelines take
`SDLGPUGraphicsPipelineDescription` mirroring `SDL_GPUGraphicsPipelineCreateInfo` field for field with
defaults (`colorFormat: .b8g8r8a8Unorm`, `sampleCount: .one`, depth off), built from library shaders (`GA-F`).
Instancing is SDL's `SDL_DrawGPUPrimitives(…, numInstances, …)`; vertex-stage storage buffers are
`bindVertexStorageBuffers`. The **ID pass with CPU readback for picking** is a batch: render to an
`R32_UINT` or `R8G8B8A8_UNORM` texture (an offscreen target on any device, not the surface), then
`device.download(texture:)`; it needs no frame view, so picking runs off the frame. A surface target stays
managed by `SurfaceTargetTable` and MetalUI: the app never makes, releases or resizes it, and MSAA/depth
textures are the app's own, kept in its state keyed on `ctx.pixelSize` (a new size is `ctx.isNewTarget`).
**No renderer change**: `SDLWindowRenderer`, `SurfaceTargetTable` and the fence rule are untouched; no shader
change in `replay.hlsl`/`shaders.metal` (`TE-AD` is not engaged: the app's shaders are not MetalUI's
drawable primitives). **Cost if wrong.** A pixel-format or sample-count the field list omits is `.raw` again.

## GA-I — The debug check covers what the typed layer can see, and says what it cannot

**Question.** Can contract violations inside a draw be detected on SDL?

**Evidence.** SDL3 has no command-buffer state query; `MetalWindowRenderer` traps on Metal's `status`, SDL has
no equivalent (`SDLGPUDrawContext` doc). A raw `SDL_SubmitGPUCommandBuffer` call cannot be intercepted.

**Ruling.** Three checks, `#if DEBUG` only (release costs one branch removed): (1) **compile time**: the frame
view has no forbidden verb (`GA-H`), pinned by a source-scan test; (2) **run time, typed layer**:
`SDLGPUWindowGuard` (a main-actor flag set by `SDLWindowRenderer` around each surface draw, `package` setter)
makes `SDLGPUDevice.submitBatch`, `fence.wait`, `acquireSwapchain`-style calls and `device.waitForIdle` trap
inside a draw naming the contract (`MV-F` item 3), and the renderer traps when a draw returns with a
typed pass still open (the wrapper counts open passes per frame view) or after it consumed `target`'s lifetime;
(3) **raw calls stay undetected, and the doc comment of `SDLGPUDrawContext` keeps saying so** (its sentence is
narrowed from "not detected" to "not detected through the raw pointers"). The renderer edit is two lines at the
draw call in `finishFrame` (`SDLWindowRenderer.swift:316`), lane 2's only change to existing code.
**Cost if wrong.** An app that goes raw gets today's behaviour, no worse.

## GA-J — Class M, no divergence, no SwiftUI probe, no new platform requirement

**Ruling.** Everything is MetalUI-only (class `M`, like `MetalView`): SwiftUI has no GPU API; the inventory map
gets class `M` rows for every public declaration the census sees, each with a doc comment. No divergence label
of 445–454 is taken. No `PlatformWindow`, `Platform` or `WindowRenderer` requirement is added, so there is no
conformer to implement and no migration note beyond a `docs/migration.md` line naming the new product. The
fourteen demo images are 0 px against `fb9a7e42` by construction (no `Sources/` change); the lanes confirm with
`compare.sh`. **Cost if wrong.** None beyond the map rows.

## GA-K — Rejected from review: lavapipe skips, `preferring:` on `make`, and a missing shadercross are named, not assumed

**Ruling.** (1) The spec's `make(debug:)` is `make(debug:preferring:)` as `GA-D` says (`preferring` sets
`SDL_HINT_GPU_DRIVER` only for that call). (2) If shadercross cannot be obtained on this Mac, lane 1 builds it in
the Linux image (volume `metalui-sdl-build-sdl-gpu-compute`) to produce `.spv`, `.msl` and `.dxil`; a DXIL blob
that cannot be produced is recorded and the Windows run of C1 is carried, never faked. (3) A kernel's MSL is
untested until it runs on this Mac's Metal (GA-G stands).

## GA-L — `Backends/SDL` is outside the census; macOS CI runs no SDL tests

**Evidence.** `closeout-public-api.sh` globs `Sources/*.swift` only; `sdl-gpu-linux.yml`'s macOS job records
fixtures, it runs no `Backends/SDL` test (CLAUDE.md says so).
**Ruling.** The spec's inventory-map and census duty is struck: new public declarations in `MetalUISDLGPU` get
doc comments (the rule) and no map row; the two scripts are expected unchanged. `METALUI_REQUIRE_GPU=1` is set by
the Linux and Windows jobs only; macOS GPU tests are a hand run recorded in the record.

## GA-M — The Linux image presents no frame, so surface-draw tests there use an offscreen texture

**Ruling.** G1–G4 run their pipelines into an app-made texture on every platform (the pipeline is covered), and
additionally into the real surface target where `windowsPresentFrames`; D1/D2 exit tests need no frame. The
guard flag is set by `SDLWindowRenderer` only around a real draw, so D1/D2 drive the guard through a `package`
test entry that sets the same flag; the renderer's two lines are pinned by D4 on macOS only.
