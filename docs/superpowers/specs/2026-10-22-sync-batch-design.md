# Synchronous render batch (XP-G22) — design

Item XP-G22 of the gpui-gap priority list (MetalCreator request 2026-10-22, not blocking; **not a plan task**). Rulings:
`../2026-10-22-sync-batch-decisions.md` (`SY-A`…`SY-F`). Record `§143` (written at the Record phase). Base `d062168c`, branch
`feat/sync-batch`. `Backends/SDL` only (`MetalUISDLGPU` and its tests) plus docs. Class M, no census row (`GA-L`), no divergence (labels
725–734 untouched), no SwiftUI claim, no probe (SwiftUI has no GPU API; gpui gives an app no command-buffer access, recalled, context only).
No root `Sources/` change, so the fourteen images must stay 0 px and the root count stays 4248.

## The gap

`SDLGPUDevice.submitBatch(_:)` is `async`, and an `SDLGPUCommandBuffer` exists only inside a batch. Main-actor code that must answer a
click exactly and at once (render an ID pass, read one pixel) cannot render synchronously. `downloadSynchronously(_:region:)` and
`SDLGPUFence.waitBlocking()` (`GB-F`, record 137) cover the read and the wait, not the render.

## Inventory (at `d062168c`)

`SDLGPUDevice.swift`: `submitBatch` (281) acquires a buffer on `submitWorker`, runs `record`, checks `openPasses == 0`, submits with a fence,
wraps it in an `SDLGPUFence`, `startWaiting(gate:)` on the waiter worker, resumes a continuation. `preconditionNotOnOwnWorker(_:)` (264).
`SDLGPUReadback.swift`: `downloadSynchronously` runs its own copy-pass job on `submitWorker` and hands the fence back through a private
`Submitted` (semaphore + fence), then `fence.waitBlocking()`. `SDLGPUFence.swift`: `waitBlocking()`, the test counters
`unsignalledReleaseCount`, `foreignThreadWaitCount`. `SDLGPUWindowGuard.assertNotInsideDraw`, `enterSimulatedDrawForTesting()` (`GA-I`, `GA-R`).
Existing pins to copy the shape of: `SDLGPUReadbackAndFailureTests` S1–S6.

## Public API (one verb, documented, naming its SDL calls)

```swift
extension SDLGPUDevice {
    public func submitBatchSynchronously(_ record: @escaping @Sendable (SDLGPUCommandBuffer) -> Void) throws -> SDLGPUFence
}
```

Behaviour: the calling thread blocks only until the batch is **submitted** (`SDL_SubmitGPUCommandBufferAndAcquireFence` returned), never until
it finishes; the returned fence is normally unsignalled. `record` runs on the device's submit worker, not the caller (`GA-E`). The caller then
calls `fence.waitBlocking()` or `downloadSynchronously(_:)`, whose job the one FIFO submit worker orders after this batch. Rules (`SY-B`,
`SY-C`): legal on the main actor outside a surface draw; a debug trap named `SDLGPUDevice.submitBatchSynchronously` inside one; a `precondition`
failure naming the verb on the device's own submit or waiter thread; throws `SDLGPUError` for the three failures `submitBatch` throws (acquire,
open pass at the end, submit). `record` must not block on the caller (it is waiting for it): no main-actor hop, no blocking verb (the latter
is the precondition).

## Implementation (one lane, files disjoint from every sibling)

1. `SDLGPUDevice.swift`: extract the worker job body of `submitBatch` into one `internal func recordAndSubmit(_ record:, gate:) -> Result<SDLGPUFence, SDLGPUError>`
   (run on `submitWorker`); `submitBatch` calls it and resumes its continuation with the result (behaviour unchanged, `gate` kept);
   `submitBatchSynchronously` enqueues it, waits on a semaphore and returns or throws its result, passing the device's `waiterGate` exactly as `submitBatch` does (nil in production; the Y2 hook, `SY-G`). One recorder, never forked (`SY-A`).
2. `SDLGPUReadback.swift`: `Submitted` goes from `private` to `internal` and carries a `Result` so both blocking verbs share one hand-back box (`SY-D`).
   `downloadSynchronously`'s own copy-pass job is **not** rewritten onto `recordAndSubmit` (it needs a raw texture copy `SDLGPUCommandBuffer` has no verb for; carried, `SY-D`).
3. Tests: new `Backends/SDL/Tests/MetalUISDLTests/SDLGPUSyncBatchTests.swift`.
4. Docs at Record: `docs/guides/drawing-and-gpu.md` (a `text` fence mirror if it lists the verbs, DG-L; the doc check wants a `(pin: \`test\`)` after a behaviour word),
   record 143, `docs/record/README.md` row, CLAUDE.md sentence appended to the `GB-` paragraph and `SY-` in the prefix list, AGENTS.md copy.
Migration note: none (additive). Windows D3D12 is compiled by CI only.

## Tests (all in `SDLGPUSyncBatchTests`, `@MainActor @Suite(.serialized)`, `.enabled(if: GPUTestSupport.available, …)`, `METALUI_REQUIRE_GPU=1` in CI)

Red before: every test is a compile failure (the verb is absent). A mutation a pin owes is on its line; if one survives the implementer names
another and records it (practice: a mutation that reddens nothing is the finding).

| # | Test | Asserts | Mutation that must redden it |
|---|------|---------|------------------------------|
| Y1 | `aSynchronousBatchRendersATextureTheMainActorReadsWithoutAwaiting` | 16×16 `r8g8b8a8Unorm` target, a clear render pass of (1,0,0.5,1) recorded with `beginRenderPass`/`end`, `submitBatchSynchronously`, `MainActor.assertIsolated()`, `downloadSynchronously` returns all texels the clear colour (no `await` after the texture is made) | `record(commandBuffer)` not called in `recordAndSubmit`; second: the verb's fence skipped, so the download reads before the render (red or flaky, Y3 is the loop) |
| Y2 | `aSynchronousBatchReturnsOnceSubmittedNotOnceFinished` | with `device.waiterGate` held, a background `Thread` calls the verb and signals; it returns within 20 s (test fails on timeout, never hangs), the fence is `!isSignalled`; after `gate.signal()` and `waitBlocking()` it is `isSignalled` | the verb calls `fence.waitBlocking()` before returning (the call blocks on the gate, the timeout reddens) |
| Y3 | `aDownloadIssuedRightAfterReadsTheBatchsOutput` | two synchronous batches clearing green then blue into one texture, **no wait between**, then `downloadSynchronously` reads blue on every texel; repeated 20 times with alternating colours | (spec's enqueue-on-`waiterWorker` mutation measured to survive: ordering is the blocking return's, `SY-H`; Y4 reddens it) |
| Y4 | `theRecordClosureRunsOnTheSubmitWorker` | the closure's `Thread.current === device.submitWorker.thread` and `!Thread.isMainThread`, the caller's thread is the main thread after return | `record` invoked inline on the caller |
| Y5 | `aSynchronousBatchInsideADrawTrapsInDebug` (`#if DEBUG`, exit test, `enterSimulatedDrawForTesting()`) | stderr contains `SDLGPUDevice.submitBatchSynchronously was called inside a surface draw` | the `assertNotInsideDraw` line removed |
| Y6 | `aSynchronousBatchOnTheDevicesOwnWorkerIsRefused` (exit test: the verb called from a `submitWorker.enqueue` job) | stderr contains `SDLGPUDevice.submitBatchSynchronously was called on the device's own`; also the waiter-thread arm (second child, `waiterWorker.enqueue`) | the `preconditionNotOnOwnWorker` line removed (child deadlocks, the exit test's timeout reddens) |
| Y7 | `everySynchronousFenceIsReleasedOnceAfterItsSignal` | 8 batches, each fence `waitBlocking()`ed, then `isSignalled`; `SDLGPUFence.unsignalledReleaseCount` and `foreignThreadWaitCount` unchanged; 8 more batches whose fences are dropped unawaited, then `device.waitForIdle()` and a bounded poll of the counters unchanged | the verb skips `result.startWaiting` (fences never signal: `waitBlocking` hangs, run on a bounded background thread), second: `startWaiting` replaced by an immediate release (`unsignalledReleaseCount` rises) |
| Y8 | `aBatchThatLeavesAPassOpenThrowsAndTheNextOneStillWorks` | `record` calls `beginRenderPass` and never `end()`: the verb throws an `SDLGPUError` naming the open pass; a following good batch returns a fence and renders (Y1's check) | the `openPasses == 0` check removed from `recordAndSubmit` (reddens the async twin too) |
| Y9 | existing `submitBatch` tests and S1–S6 | unchanged and green: the extraction moved nothing | n/a (the refactor's own regression net: mutate `recordAndSubmit`'s `startWaiting(gate:)` to `gate: nil` and `waitBlockingReturnsOnlyAfterTheSignal…` (S2) must redden) |

Reddened tests are named in the record, never counted. Run: Backends/SDL on macOS (`METALUI_REQUIRE_GPU=1 swift test $(python3 scripts/fetch-accesskit.py --print-flags)`)
and the `metalui-portable` image on lavapipe (volume `metalui-sdl-build-sync-batch`); root suite unfiltered after `swift package clean` (4248 unchanged); `swift build`
0 warnings both build systems; the fourteen images 0 px against `d062168c`; inventory and undocumented scripts print nothing.

## Demo and human checks

No demo (a library verb; `MetalUIDemo` is root and untouched). Human checks: none added. Every pin runs on Metal and lavapipe; the Windows D3D12 run is
compiled by CI and is covered by group `GA` (a real-hardware item); a stall measurement of a main-actor pick is the app's, not the library's.

## Not built (named, with owner)

- A synchronous buffer download and upload: not asked; owner a later gap request.
- `downloadSynchronously` on `recordAndSubmit`: needs a texture copy verb on `SDLGPUCommandBuffer`; owner a later cleanup if one is added (`SY-D`).
- A combined `renderSynchronously(...) -> [UInt8]` convenience: refused (`SY-E`); the three-line composition is the API.
- Cancelling a blocked wait: none (SDL has none).
