# SDL GPU gaps for MetalCreator xp-3 — decisions

Rulings for item S11 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), requested by
MetalCreator (developer session, 2026-10-21) for its xp-3 3D viewport on SDL GPU: XP-G14 to XP-G19. Prefix `GB-`.
**Next unused: `GB-M`.** Spec: [`specs/2026-10-21-sdl-gpu-gaps-design.md`](specs/2026-10-21-sdl-gpu-gaps-design.md).
Record: `../record/137-sdl-gpu-gaps.md`. Branch `feat/sdl-gpu-gaps` from `1bdead8d`. Continues `GA-` (record 114, 125).
Divergence labels reserved 665–674: **none taken** (`GB-A`).

Sources of truth. SwiftUI has no GPU API, so nothing here is a SwiftUI-facing claim and no probe is owed. gpui gives an
app no pipeline-level access (recalled from memory; the source is not on this machine), so it is context only. The
facts come from SDL 3.4.18's `SDL_gpu.h` on this machine (the Linux image builds `release-3.4.16`; every call used
exists in both) and from this repository at `1bdead8d`. Backends/SDL is outside the census (`GA-L`); class M.

## GB-A — no divergence, no probe, class M, wrapper stays thin

**Ruling.** Every new member is named after SDL_GPU (`GA-A`, `GA-B`) and documented with the SDL call it wraps. No
divergence label is taken. **Cost if wrong.** A label would be owed; none of the six items makes a SwiftUI claim.

## GB-B — viewport and scissor: SDL's top-left pixel space, refusals return `false`, scissor clamps to the target

**Question.** XP-G15 wants `setViewport(x:y:width:height:minDepth:maxDepth:)` and `setScissor(x:y:width:height:)`;
what are the coordinates and what happens on a bad size?
**Evidence.** `SDL_gpu.h`: `SDL_GPUViewport` is `x, y, w, h, min_depth, max_depth` floats, `SDL_SetGPUScissor` takes an
`SDL_Rect`; SDL documents render-target pixels with the origin at the top left and flips internally for Vulkan (negative
height viewport) and Metal/D3D12 natively, so one convention holds on every driver (the implementer re-checks with the
pixel pins on Metal and lavapipe; D3D12 is CI-compiled only).
**Ruling.** Both verbs are `@discardableResult ... -> Bool` (adding a result to a `Void` spelling is source
compatible). `setViewport` refuses (no SDL call, `false`) a non-finite value or a width or height `<= 0`; it does **not**
clamp to the target (a viewport past the target is legal in all three APIs and is what a clipped 3D view needs).
`minDepth`/`maxDepth` are clamped to `[0, 1]` (Vulkan without the depth-range extension and D3D12 reject others) and
`minDepth > maxDepth` is allowed (reversed depth is legal). `setScissor` refuses a negative width or height; it
**clamps the rect to the pass's colour target** (an offset below 0 shrinks the rect, one past the edge or an empty
intersection gives a zero-size scissor, which draws nothing), because Metal and D3D12 treat an out-of-target scissor as an
error; the pass records its target size for this. Neither traps (a viewport arrives from layout maths that can pass
through zero). SDL resets viewport and scissor to the full target at each `Begin`, so they are per pass and are not
reset by `bind`. **Cost if wrong.** An app expecting a trap sees `false`; an app needing an unclamped scissor has `.raw`.

## GB-C — `writesColor: Bool = true`, a depth-only pass keeps one colour target

**Ruling.** The new last parameter of `SDLGPUGraphicsPipelineDescription.init` and a stored `var writesColor`. When
`false`, the one colour target's `blend_state` keeps its blend setting and gains `enable_color_write_mask = true`,
`color_write_mask = 0`. The pass still needs a colour attachment: `beginRenderPass` requires one and SDL allows zero
colour targets only through raw calls, which stays the escape hatch. Default `true` leaves `enable_color_write_mask`
false (all channels, today's bytes). **Cost if wrong.** A caller wanting a true zero-colour-target pass uses `.raw`.

## GB-D — `r32Float` is added as a new case; the enum is not frozen

**Question.** A new case in a public enum breaks a caller's exhaustive `switch`.
**Evidence.** `SDLGPUTextureFormat` is a plain public enum in a library built without library evolution, so a
caller's `switch` without `default` stops compiling; a grep of the repository's callers (`Backends/SDL/Sources`, tests,
demos) is the implementer's first step. The format is `SDL_GPU_TEXTUREFORMAT_R32_FLOAT`, four bytes, supported for
sampler and colour-target usage by Metal, D3D12 and Vulkan.
**Ruling.** Add `case r32Float` after `r32Uint`, `bytesPerTexel` 4, `sdl` mapped; `upload` and `download` need no other
change because they key on `bytesPerTexel`. Document: filtering a 32-bit float texture is optional hardware (use
`.nearest`); `docs/migration.md` gets a row naming the new case for exhaustive switches. **Cost if wrong.** A downstream
compile error with a one-line fix, announced in the migration note.

## GB-E — anisotropy: `maxAnisotropy: Float = 1`, clamped to 1…16, stored and readable

**Ruling.** Last parameter of `SDLGPUSamplerDescription.init`; enabled (`enable_anisotropy = true`,
`max_anisotropy`) only when the effective value is `> 1`. Effective value: a non-finite or `< 1` value is 1, and a value
above 16 is 16 (Vulkan, D3D12 and Metal all cap at 16; an `SDL_GPUDevice` made by `make` leaves SDL's default of the
Vulkan `samplerAnisotropy` feature on, and a borrowed window device is MetalUI's own, so `makeSampler` still answers
`nil` if SDL refuses). The description keeps the **requested** value and exposes `effectiveMaxAnisotropy`; `SDLGPUSampler`
gains `description` (it had none) so a test reads it back. Whether it looks better is a human check (`GB1`); the
`SDL_GPUSamplerCreateInfo` fields are pinned headless through an internal pure function. **Cost if wrong.** A caller
wanting a cap other than 16 reaches `.raw`.

## GB-F — synchronous readback: both spellings, built on the existing waiter thread

**Question.** XP-G14: `downloadSynchronously`, `waitBlocking`, or both, given `GA-E` (batches on a worker, fences awaited
on a waiter thread, never the main actor) and `GA-I` (typed blocking verbs trap inside a draw)?
**Ruling.** Both. `SDLGPUFence.waitBlocking()` blocks the **calling thread** until the batch signalled. It does **not**
call `SDL_WaitForGPUFences` itself and never releases the fence: it sleeps on the lock-and-condition the waiter thread's
`finish()` already signals, so the fence rule (release only after the signal, only by the waiter, `foreignThreadWaitCount`
stays 0) holds. `SDLGPUDevice.downloadSynchronously(_ texture:region:)` (region a new `SDLGPUTextureRegion` with x, y,
width, height, mip level; default the whole of level 0) enqueues one batch on the submit worker, waits on a semaphore for
the fence and then `waitBlocking()`s, returning tightly packed rows or `nil` for a multisampled or depth texture, a region
outside the level or a refusal. Both are legal on the main actor **outside a draw**: the `GA-E` rule existed so a draw
(which holds the frame's command buffer and the main actor) cannot wait on its own completion, and so a UI thread is never
blocked by default; it was not a claim that a blocked main actor is unsafe, because no completion needs the main thread
(Metal's completion and the waiter thread run elsewhere). That is Metal's `waitUntilCompleted` parity, the cost being a
stalled frame, which the doc comments say. Inside a draw both call `SDLGPUWindowGuard.assertNotInsideDraw` (debug trap
naming the verb, `GA-I`), and are pinned through `enterSimulatedDrawForTesting()` (`GA-R`). Either verb called **from the
device's own worker threads** (inside a `submitBatch` closure or a waiter callback) would deadlock and is a
`precondition`. Not built: a synchronous buffer download (carried, owner a later request; the texture form is the ask).
**Cost if wrong.** A caller that blocks the main actor drops frames; the async forms stay and are the documented default.

## GB-G — pipeline failure reason: throwing `compile…Pipeline` verbs plus a per-device `lastPipelineFailure`

**Question.** XP-G19 asks for the reason; spelling it as an overload of `makeGraphicsPipeline` would make `try?` call
sites ambiguous.
**Ruling.** Additive only. New `compileGraphicsPipeline(_:) throws -> SDLGPUGraphicsPipeline` and
`compileComputePipeline(_:) throws -> SDLGPUComputePipeline` throw `SDLGPUError` (existing type, carries SDL's text) naming the stage
that failed (vertex shader, fragment shader, pipeline) and, when `SDL_GetError()` is empty (SDL leaves it empty on some
drivers), the description's key fields (format, sample count, blob names). The optional `make…Pipeline` verbs keep their
signatures and become one-line wrappers over the throwing ones that also record `lastPipelineFailure: String?` on the
device (locked; a failure overwrites, a success does **not** clear, as `SDLGPUDevice.lastFailure` does not). SDL's error
string is thread-local, so it is read on the thread of the failing call under the device lock, at the failure site
(`makeShader` included, which today drops it). **Cost if wrong.** A stale `lastPipelineFailure` after a later success;
the throwing verbs are the authoritative form.

## GB-H — two lanes, sequential, split by file

**Ruling.** Lane 1: `SDLGPUGraphics.swift` and `SDLGPUTexture.swift` (GB-B to GB-E), two new app shaders. Lane 2, **after
lane 1 commits**: `SDLGPUFence.swift`, `SDLGPUDevice.swift`, `SDLGPUCompute.swift`, and the pipeline-making bodies in
`SDLGPUGraphics.swift` (GB-F, GB-G). The workflow runs one agent at a time, so the shared function in `SDLGPUGraphics.swift`
is edited in order, never concurrently. **Cost if wrong.** A merge edit inside `makeGraphicsPipeline`.

## GB-I — review amendments: the sampler read-back is `configuration`, worker-thread check by thread identity, scissor target size

**Ruling (rejections and fixes of GB-B, GB-E, GB-F).** (1) `SDLGPUSampler` exposes its description as
`configuration`, not `description` (a `description` property reads as `CustomStringConvertible` and the spec's A2 would
mislead); the spec's `description` is amended. (2) GB-F's `precondition` for a call from the device's own threads tests
`Thread.current === submitWorker.thread || waiterWorker.thread`, never "inside a `submitBatch` closure" (that closure's
thread is not the worker's and the claim was unmeasured); a call from a caller's closure on another thread is legal. A
test pins the waiter-thread arm through an internal hook, or records the arm unproven. (3) GB-B's target size for the
scissor clamp is the **minimum over the pass's colour targets**, or the depth target's when it has none. (4) New tests live
in `Backends/SDL/Tests/MetalUISDLTests/` beside `SDLGPUGraphicsTests.swift`. **Cost if wrong.** A rename after merge.

## GB-J — W1 shaders are existing ones

**Ruling.** W1 uses `fullscreen.vert` (depth 0) with `flat.frag` for the prepass and `tri.vert` (depths 0.3/0.5/0.7) for
pass 2, so no depth-parameterised vertex shader is added; the new blobs are `flat.frag` and `copy.frag` only.
**Cost if wrong.** An extra blob.

## GB-K — adding `-> Bool` and defaulted last parameters are source-compatible, not binary-compatible

**Ruling.** Backends/SDL ships as source (SwiftPM), so the migration note says "source compatible; a stored function
reference to `setViewport`-like verbs does not exist (they are new)"; `writesColor`/`maxAnisotropy` extend initialisers
whose old spelling no longer exists as a symbol, which is acceptable for a source-distributed class M layer.

## GB-L — lane 2 as built: no `level(_:)`, S6 added, compile verbs do not record, the worker check is shared

**Ruling.** (1) `SDLGPUTextureRegion` has no `static func level(_:)` (a whole level needs the texture's size, which the
type does not hold): `region: nil` means all of level 0, and any other whole level is spelled as a region. (2) The throwing
`compile…Pipeline` verbs do **not** record `lastPipelineFailure`; only the optional `make…Pipeline` wrappers do, so a caller
using the throwing form holds the reason already and the property means "what an optional verb refused" (GB-G said the same;
this removes the ambiguity). (3) Test S6 (`aBlockingWaitOnTheDevicesOwnWorkerIsRefused`) pins GB-I 2's waiter-thread arm
in an exit test by enqueueing `waitBlocking` on `device.waiterWorker` (the worker is internal, so no extra hook was needed);
the submit-worker arm shares the one `preconditionNotOnOwnWorker` and is not separately pinned. (4) An `SDLGPUError` whose
SDL string is empty reads `<operation> failed (SDL gave no message; <key fields>)`; lavapipe and Metal both gave a message,
so that arm is exercised by no test (carried; it is a string choice). (5) `downloadSynchronously` takes no usage flag beyond
what `download` takes. **Cost if wrong.** A caller wanting the failure after a throwing call keeps the error it caught.
(6) **The stage a refusal names is the driver's.** A fragment blob with truncated code is refused by Metal at `SDL_CreateGPUShader`
(MSL compile) but accepted there by lavapipe, which refuses at `SDL_CreateGPUGraphicsPipeline` (`vkCreateGraphicsPipelines Unhandled
VkResult!`); P1 therefore accepts either stage name and requires SDL's text to be present. Found by the Linux image run, not by macOS.
