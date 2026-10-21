# 137 - SDL GPU gaps for MetalCreator xp-3 (XP-G14 to XP-G19)

Branch `feat/sdl-gpu-gaps` from `1bdead8d`. Not a plan task: item S11 of the gpui-gap list, requested by MetalCreator 2026-10-21. Spec
`docs/superpowers/specs/2026-10-21-sdl-gpu-gaps-design.md`; rulings `GB-A`...`GB-L` in `docs/superpowers/2026-10-21-sdl-gpu-gaps-decisions.md` (next `GB-M`).
Divergence labels 665-674 reserved: **none taken** (class `M`, `Backends/SDL`, outside the census, no SwiftUI claim, no probe). Two lanes in `MetalUISDLGPU`
and its tests; no root `Sources/` change, no demo. Human checks: group `GB`, `GB1`...`GB3`. Lane 1 (viewport, scissor, write mask, `r32Float`,
anisotropy: `GB-B`...`GB-E`) is section 0; lane 2 (readback, failure reasons) is sections 1 and 2.

## 0 Lane 1: what landed (`GB-B`...`GB-E`, `GB-J`)

- `SDLGPURenderPass.setViewport(x:y:width:height:minDepth:maxDepth:)` and `setScissor(x:y:width:height:)`, both `@discardableResult -> Bool`, top-left target pixels, no trap.
  A non-finite value or a size `<= 0` is refused (no SDL call, `false`); the viewport is not clamped to the target, its depths are clamped to `0...1`; the scissor
  is clamped to the pass's target (`SDLGPURenderPass.targetSize`: the minimum over the colour targets, else the depth target's, `GB-I` 3). The pass resets both at `Begin`.
- `SDLGPUGraphicsPipelineDescription.writesColor: Bool = true` (last parameter): `false` gives the one colour target `enable_color_write_mask = true`, `color_write_mask = 0`,
  blending kept (a depth-only prepass; zero colour targets stay a `.raw` matter, `GB-C`).
- `SDLGPUTextureFormat.r32Float` (`SDL_GPU_TEXTUREFORMAT_R32_FLOAT`, 4 bytes), the only new enum case (migration row).
- `SDLGPUSamplerDescription.maxAnisotropy: Float = 1` (last parameter), `effectiveMaxAnisotropy` (non-finite or `< 1` is 1, above 16 is 16), `enable_anisotropy` only when
  the effective value is `> 1`; `SDLGPUSampler.configuration` reads the requested description back (`GB-I` 1). Two app shaders, `flat.frag` and `copy.frag`, compiled by
  `compile-app-shaders.py` into `Backends/SDL/Tests/AppShaders/compiled` with `SOURCE.sha256` (`GA-F`; the vertex shaders are existing ones, `GB-J`).

Pins (`SDLGPUGapsTests`, 11 tests, one serialized suite; red on arrival by compile failure, commit `03c495f8`): V1 `aViewportConfinesADrawToItsRect`, V2 `aScissorConfinesADrawToItsRect`,
V3 `aDegenerateViewportOrScissorIsRefusedWithoutATrap`, V4 `aScissorIsClampedToTheTarget`, W1 `aPipelineThatWritesNoColourLeavesColourAndWritesDepth` (a control arm with
`writesColor: true` shows the colour), W2 `writesColorDefaultsToTrueAndIsStored`, F1 `anR32FloatTextureRoundTripsExactFloats`, F2 `anR32FloatTextureSampledNearestEqualsItsSource`,
F3 `r32FloatIsFourBytesPerTexel`, A1 `anisotropyFieldsReachTheSamplerCreateInfo` (pure, no GPU), A2 `aSamplerWithAnisotropyIsBuiltAndReadsBack`.

Mutations: the implementer's V1-V4, W1-W2, F1-F2 and A1-A2 runs reddened their named pins (reported by the implementer, tables not carried into this record). The lane verifier's own, full unfiltered
`Backends/SDL` suite, each alone, tree clean after:

| mutation | reddened |
|---|---|
| `effectiveMaxAnisotropy` cap 16 raised to 32 | `anisotropyFieldsReachTheSamplerCreateInfo` |
| `setViewport` depth clamp to `0...1` dropped | **none: unpinned** |
| width and height swapped in `SDLGPURenderPass.targetSize` (the scissor clamp) | **none: unpinned** (the clamp pins use a square target) |

The two survivors are findings, not fixed here (this phase owns docs): the depth clamp of `GB-B` and the width/height distinction of the scissor clamp have no pin (section 4).

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

Mutations, each alone on the committed tree, restored from a copy, `git status --short` clean after each; **the implementer's runs were filtered to `SDLGPUReadbackAndFailureTests`** (the nine pins live in
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

- **Root, after `swift package clean`, `swift build --build-system native --build-tests`, unfiltered `swift test --build-system native --no-parallel`:** **4117 tests in 5 suites** (unchanged from `1bdead8d`: no root test added), 0 goldens, 251 typecheck guards (none added), failed with exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` (locked screen) and nothing else; native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice; `FR-J no-argument frame: succeeded=true`; measured at `64eda50f` plus this record's docs, 911 s on a shared Mac.
- **Backends/SDL on macOS** (`swift test $(python3 scripts/fetch-accesskit.py --print-flags)`): 30 + 243 tests passed at the lane 2 verifier's head (30 + 234 at lane 1's: 243 = 234 + 9 `SDLGPUReadbackAndFailureTests`).
- **Linux image** (`metalui-portable`, lavapipe, `METALUI_REQUIRE_GPU=1`): 30 + 240 tests in 10 suites passed at the final head `e4e72b2a` (checker, 2026-10-21; 231 at lane 1's head, where it found `GB-L` 6, the stage a driver refuses at). The macOS figure 30 + 243 was re-taken the same day under `METALUI_REQUIRE_GPU=1` (three macOS-only tests).
- **Default build system `swift build --build-tests`:** 0 `warning:` at lane 1's head.
- **Fourteen images:** not re-taken; `git diff --stat 1bdead8d HEAD -- Sources Tests` is empty (every code change is under `Backends/SDL`), so 0 px follows from the diff and is unmeasured. Re-take at the merge.
- Guards: no root typecheck guard added (no root declaration; inventory and undocumented scripts print nothing, census unmoved). No divergence label.

## 4 Carried

Pins for the `setViewport` depth clamp and for a non-square scissor clamp (section 0, both survived a mutation; owner: the next change to `SDLGPUGraphics.swift`); synchronous buffer download and upload (not asked); a zero-colour-target pipeline; an SDL-gave-no-message error arm no driver here exercises; a pin for the submit-worker arm of
the worker precondition; D3D12 behaviour (check `GB2`, CI compiles Windows only).

## 5. Adversarial branch check (2026-10-21, head `e4e72b2a`)

- Root, after `swift package clean`, native build 0 `error:`, only SwiftPM's deprecation `warning:`: `Test run with 4117 tests in 5 suites failed after 895.600 seconds with 5 issues`; the five are the `AppKitPresentationTests` sheet issues of `CI-AF` (locked screen) and nothing else; `FR-J no-argument frame: succeeded=true`.
- No root file differs from `1bdead8d` (`git diff --name-only` outside `docs/`, `Backends/SDL/`, `CLAUDE.md`, `AGENTS.md` prints nothing), so identity, hit testing, accessibility and animation pins are unmoved by construction and the fourteen images are 0 px by construction; the offscreen comparison and the default-build-system warning count were **not re-taken** (no root source to change them).
- Two mutations of the checker's design, each on the committed source, restored from a copy, `git status --short` clean after: **C1** `blend.color_write_mask = 0` to `0xF` in `compileGraphicsPipeline` reddened `aPipelineThatWritesNoColourLeavesColourAndWritesDepth()` only (1 issue). **C2** `waitBlocking`'s `while !signalled { lock.wait() }` to `if false { lock.wait() }` reddened `aSynchronousDownloadReturnsTheRegionFromTheMainActor()` (2 issues) and `waitBlockingReturnsOnlyAfterTheSignalAndReleasesNothingEarly()` (2 issues). Both ran to a summary line (243 tests).
- Every ruling id (`GB-A`..`GB-L`) and test name cited in the record, decisions doc and human checks resolves by grep; `cmp CLAUDE.md AGENTS.md` clean; inventory and undocumented scripts print nothing.
- Windows D3D12 is compiled by CI only; the anisotropy looks are group `GB`, not claimed.
- Code verdict: no defect found; the two lane 1 survivors (viewport depth clamp, scissor target-size swap) stay carried. **Merge: yes.**
