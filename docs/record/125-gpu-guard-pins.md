# 125 — Pinning the async draw guards on SDL

Branch `fix/gpu-guard-pins` from `4d91f27f`. **Not a plan task**: item S10, the carried half of `GA-P` (record 114).
Ruling `GA-R` in `docs/superpowers/2026-10-14-sdl-gpu-compute-decisions.md` (next unused `GA-S`). **No public API,
no divergence, no census row** (`Backends/SDL` is outside it, `GA-L`). `Backends/SDL` only.

## §1 Change

`SDLGPUWindowGuard.enterSimulatedDrawForTesting()` and `leaveSimulatedDrawForTesting()` (`package`, debug bodies): mark
the calling thread as drawing. Two exit tests in `SDLGPUContractTests`: D6 `aSubmitBatchInsideADrawTrapsInDebug`, D7
`aFenceWaitInsideADrawTrapsInDebug`, each asserting the trap message names the verb.

## §2 Mutations (each applied alone, restored from git, suite `SDLGPUContractTests` run)

- `assertNotInsideDraw("SDLGPUDevice.submitBatch")` line removed: `aSubmitBatchInsideADrawTrapsInDebug` reddened; nothing else.
- `assertNotInsideDraw("SDLGPUFence.wait")` line removed: `aFenceWaitInsideADrawTrapsInDebug` reddened; nothing else.

Both pass with the guards in place. The old attempt's unrelated crash (`GA-P`) cannot pass these: the message is asserted.

## §3 Counts

`Backends/SDL` unfiltered: macOS 30 + 217 tests, Linux image (lavapipe, `METALUI_REQUIRE_GPU=1`) 30 + 214, all passed. Root `swift build --build-system native --build-tests` 0 `error:`.
