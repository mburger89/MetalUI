# 143. Synchronous render batch (XP-G22)

Item XP-G22 (MetalCreator, 2026-10-22, not blocking; not a plan task). Branch `feat/sync-batch` from `d062168c`, one implementer lane, `Backends/SDL`'s `MetalUISDLGPU` only.
Spec `docs/superpowers/specs/2026-10-22-sync-batch-design.md`; rulings `docs/superpowers/2026-10-22-sync-batch-decisions.md` (`SY-A`...`SY-H`). No divergence (725-734 untouched), no probe (SwiftUI has no GPU API), no census row (`GA-L`).

## 1. What was built

`SDLGPUDevice.submitBatchSynchronously(_:) throws -> SDLGPUFence` (class M). The worker job body of `submitBatch` is now one internal `recordAndSubmit(_:gate:) -> Result<SDLGPUFence, SDLGPUError>` run on
the submit worker (`SY-A`); `submitBatch` resumes its continuation with the result, the synchronous verb waits on a semaphore for it, passing `waiterGate` like the async verb (`SY-G`). The caller blocks until the
buffer is **submitted**, not finished; the fence is normally unsignalled and the caller then uses `waitBlocking()` or `downloadSynchronously`. Rules are `GB-F`'s: debug trap inside a draw, `precondition` on the
device's own workers (`SY-C`). `Submitted` (semaphore plus a `Result`) is internal and shared with `downloadSynchronously`, whose copy-pass job is not moved (`SY-D`). No combined render-and-read verb (`SY-E`).

## 2. Red first

Tests alone at `ecaf1862`: `SDLGPUSyncBatchTests.swift:69:24: error: value of type 'SDLGPUDevice' has no member 'submitBatchSynchronously'` (every pin Y1-Y8 a compile failure).

## 3. Mutations (each on a clean tree, committed first, restored by `git checkout`, `git status --short` clean after; filtered to `SDLGPUSyncBatchTests|SDLGPUReadbackAndFailureTests`)

- M1 `record` not called: reddened `aSynchronousBatchRendersATextureTheMainActorReadsWithoutAwaiting` (Y1), `aDownloadIssuedRightAfterReadsTheBatchsOutput` (Y3), `theRecordClosureRunsOnTheSubmitWorker` (Y4), `aBatchThatLeavesAPassOpenThrowsAndTheNextOneStillWorks` (Y8), and `aSynchronousDownloadReturnsTheRegionFromTheMainActor` (S1).
- M2 the verb waits on the fence before returning: `aSynchronousBatchReturnsOnceSubmittedNotOnceFinished` (Y2) alone (20 s timeout, never a hang).
- M3 the verb enqueues on the waiter worker: **Y3 survived** (the blocking return orders it, `SY-H`); `theRecordClosureRunsOnTheSubmitWorker` (Y4) reddened.
- M4 `record` inline on the caller: Y4. M5 `assertNotInsideDraw` removed: `aSynchronousBatchInsideADrawTrapsInDebug` (Y5). M6 `preconditionNotOnOwnWorker` removed: `aSynchronousBatchOnTheDevicesOwnWorkerIsRefused` (Y6, on its timeout).
- M7 `startWaiting` skipped: the full filtered run **hangs at device teardown** after Y2 and Y4 had reddened (an unsignalled fence leaks into `SDL_DestroyGPUDevice`); Y7 alone, run by itself, reddens on its bounded waits (three issues, 60 s). The first draft's unbounded waits in Y2/Y4 were bounded after this.
- M8 the `openPasses == 0` check removed: the process aborts in Metal ("commit command buffer with uncommitted encoder") while running Y8, so Y8 is reddened by a crash.
- M9 `startWaiting(gate: nil)`: `waitBlockingReturnsOnlyAfterTheSignalAndReleasesNothingEarly` (S2) and, after the held-wait observation was added to it, `aSynchronousBatchReturnsOnceSubmittedNotOnceFinished` (Y2; the first draft's single `isSignalled` read survived a race).
- Not run: Y7's second mutation (an immediate release in place of `startWaiting`); `unsignalledReleaseCount` is asserted unchanged but its rise is unproven for this verb (S2 pins the counter for `submitBatch`).

## 4. Verification

- `Backends/SDL` on macOS (`METALUI_REQUIRE_GPU=1`): 30 tests in the first run and 258 in the second; the one issue seen (`SDLSingleInstanceTests.theClaimIsReleasedWhenThePlatformGoesAway`, under load from a concurrent Docker build) passed alone and is unrelated.
- Linux image `metalui-portable` (lavapipe, volume `metalui-sdl-build-sync-batch`): 30 + 255 tests passed at the final head. Its first run caught Y4's `Thread.isMainThread` assertion (off Darwin the main actor is a pool thread, `RU-A`); Y4 now compares against the caller's captured thread. macOS `SDLGPUSyncBatchTests` 8 of 8 at the final head.
- Root suite (`swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice): **4248 tests in 5 suites**, the only issues the five `AppKitPresentationTests` sheet issues of `CI-AF` (the screen was locked during part of the 955 s run), `FR-J no-argument frame: succeeded=true`. Count unchanged, as required. `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
- The fourteen offscreen images: no `Sources/`, `Tests/` or `Package.swift` change since `d062168c` (`git diff --stat d062168c HEAD -- Sources Package.swift Tests` empty), so 0 px by construction; the comparison script was not run.

## 5. Carried

A synchronous buffer download or upload; `downloadSynchronously` on `recordAndSubmit` (needs a texture copy verb on `SDLGPUCommandBuffer`); Windows D3D12 is compiled by CI only.

## 6. After the merge with master `dd9a072f` (§141 draw text)

Merged `origin/master` (record 141 stays 141; this record stays 143; CLAUDE.md prefix list, record index and `AGENTS.md` conflicts resolved by keeping both entries, `cmp CLAUDE.md AGENTS.md` identical). `swift package clean`, native build 0 `error:`, native unfiltered run: **4264 tests in 5 suites passed** (master's count, unchanged by this branch), `FR-J no-argument frame: succeeded=true`, no issue recorded. `docs/api-overview.md` gained the verb's line; no human-check group (no look added).
