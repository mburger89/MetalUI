# 137 - SDL GPU gaps for MetalCreator xp-3 (XP-G14 to XP-G19)

Branch `feat/sdl-gpu-gaps` from `1bdead8d`. Not a plan task: item S11 of the gpui-gap list, requested by MetalCreator 2026-10-21. Spec
`docs/superpowers/specs/2026-10-21-sdl-gpu-gaps-design.md`; rulings `GB-A`...`GB-L` in `docs/superpowers/2026-10-21-sdl-gpu-gaps-decisions.md` (next `GB-M`).
Divergence labels 665-674 reserved: **none taken** (class `M`, `Backends/SDL`, outside the census, no SwiftUI claim, no probe). Two lanes in `MetalUISDLGPU`
and its tests; no root `Sources/` change, no demo. Human checks: group `GB`, `GB1`...`GB3`. Lane 1 (viewport, scissor, write mask, `r32Float`,
anisotropy: `GB-B`...`GB-E`) is recorded in its own commits and the decisions doc; this record covers lane 2.

## 1 Lane 2: what landed (`GB-F`, `GB-G`, `GB-I`, `GB-L`)

- `SDLGPUFence.waitBlocking()`: the fence's lock became an `NSCondition`; the verb sleeps on it until the waiter thread's `finish()` broadcasts. It never calls
  `SDL_WaitForGPUFences` and never releases the fence, so the fence rule holds (`foreignThreadWaitCount` and `unsignalledReleaseCount` stay put). It calls
  `assertNotInsideDraw` (debug trap naming the verb) and `preconditionNotOnOwnWorker` (a `precondition`, every build, by thread identity, `GB-I` 2).
- `SDLGPUDevice.downloadSynchronously(_:region:)` and `SDLGPUTextureRegion` (new file `SDLGPUReadback.swift`): validates the region against the level, makes a
  download transfer buffer, records one copy pass in a batch on the submit worker, hands the fence back through a semaphore, `waitBlocking()`s and returns tight rows.
  `nil` for a multisampled or depth texture, an empty, negative or outside region, a missing level. Legal on the main actor outside a draw (Metal's
  `waitUntilCompleted` parity); the reason it was not before is `GB-F`.
- `compileGraphicsPipeline(_:)` and `compileComputePipeline(_:)` throw `SDLGPUError` naming the stage ("vertex shader", "fragment shader", "graphics pipeline",
  "compute pipeline") with `SDL_GetError()` read on the failing call's thread inside the create closure (`makeShader` included, which used to drop it; now
  `compileShader`); an empty SDL string falls back to the blob's or description's key fields. The optional `make...Pipeline` verbs keep their signatures and are wrappers that
  record `lastPipelineFailure` (a success does not clear it). The throwing verbs do not record (`GB-L` 2).

## 2 Pins (`SDLGPUReadbackAndFailureTests`, 9 tests, one serialized suite)

Red on arrival: a compile failure (the API was absent): `waitBlocking`, `downloadSynchronously`, `SDLGPUTextureRegion`, `compileGraphicsPipeline`,
`compileComputePipeline` and `lastPipelineFailure` all unknown (commit `41dfbcc8`). All 9 pass on the implementation. S1 `aSynchronousDownloadReturnsTheRegionFromTheMainActor`,
S2 `waitBlockingReturnsOnlyAfterTheSignalAndReleasesNothingEarly`, S3 `aSynchronousDownloadInsideADrawTrapsInDebug` and S4 `aBlockingWaitInsideADrawTrapsInDebug` (debug only),
S5 `aSynchronousDownloadRefusesWhatItCannotRead`, S6 `aBlockingWaitOnTheDevicesOwnWorkerIsRefused` (added, `GB-L` 3), P1 `aRefusedGraphicsPipelineSaysWhy`, P2 `aRefusedComputePipelineSaysWhy`,
P3 `theOptionalPipelineVerbsKeepTheirSpelling`. S2's "still blocked" arm is a 0.3 s bounded wait for a semaphore that must time out, not a sleep.

Mutations, each alone on the committed tree, restored from a copy, `git status --short` clean after each; **run filtered to `SDLGPUReadbackAndFailureTests`** (the nine pins live in
that suite and the lane's own files are untouched elsewhere; the full macOS and Linux runs are in section 3):

| mutation | reddened |
|---|---|
| region origin ignored (`from.x = 0`) | `aSynchronousDownloadReturnsTheRegionFromTheMainActor` |
| `waitBlocking` does not wait | `waitBlockingReturnsOnlyAfterTheSignalAndReleasesNothingEarly` (its 30 s bound), `aSynchronousDownloadReturnsTheRegionFromTheMainActor` |
| `assertNotInsideDraw` removed from `downloadSynchronously` | `aSynchronousDownloadInsideADrawTrapsInDebug` |
| `assertNotInsideDraw` removed from `waitBlocking` | `aBlockingWaitInsideADrawTrapsInDebug` |
| `preconditionNotOnOwnWorker` removed from `waitBlocking` | `aBlockingWaitOnTheDevicesOwnWorkerIsRefused` |
| right/bottom bounds check removed | `aSynchronousDownloadRefusesWhatItCannotRead` |
| `SDLGPUError(_:context:)` description empty | `aRefusedGraphicsPipelineSaysWhy`, `aRefusedComputePipelineSaysWhy`, `theOptionalPipelineVerbsKeepTheirSpelling` |
| a successful `makeGraphicsPipeline` overwrites the record with `""` | `theOptionalPipelineVerbsKeepTheirSpelling` |

## 3 Measured

See the lane's final report for the macOS `Backends/SDL` run, the Linux image run (lavapipe, `METALUI_REQUIRE_GPU=1`), the root native suite after `swift package clean`
and the fourteen-image comparison; the numbers are entered at the merge.

## 4 Carried

Synchronous buffer download and upload (not asked); a zero-colour-target pipeline; an SDL-gave-no-message error arm no driver here exercises; a pin for the submit-worker arm of
the worker precondition; D3D12 behaviour (check `GB2`, CI compiles Windows only).
