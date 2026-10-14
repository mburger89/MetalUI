# 114 — SDL GPU for apps: compute, graphics and a shader path (items S5 and S6)

Branch `feat/sdl-gpu-compute` from `fb9a7e42`, merged at the Record phase with master `ceca59f6` (§111 hot paths, §112 SDL
chrome, §113 image decoding; no record numbered 114 existed, so §114 stands, and `110` is still unused). User request
2026-10-02 (gpui-gap priority list, items S5 and S6; **not a plan task**), reported as MetalCreator's SDL-port gaps 1 and 2
(developer-c0, 2026-10-13/14; read, never edited), RAISED: they block its xp-c track, GPU meshing of implicit geometry on
all three platforms (Metal on macOS, which MetalCreator does itself through `MetalDrawContext`; SDL3 GPU compute on Linux
and Windows). Spec `docs/superpowers/specs/2026-10-14-sdl-gpu-compute-design.md`; rulings `GA-A`…`GA-P` in the new
decisions doc `docs/superpowers/2026-10-14-sdl-gpu-compute-decisions.md` (next unused `GA-Q`); human checks group `GA`.
No divergence label taken (range 445–454 unused, `GA-J`); no `Sources/` change, no `Platform`/`PlatformWindow`/
`WindowRenderer` requirement, no shader change on either renderer (`TE-AD` is not engaged: the app's shaders are not
MetalUI's drawable primitives).

**Status: LANDED on macOS Metal and in the Linux image (lavapipe); Windows (D3D12) and real GPU hardware are owed to CI
and to a human** (`docs/verification/human-checks.md` group GA). Two lanes, each red first, each with a verifier tail,
both `ok: true`; the Record phase merged master, re-took the suite and added one finding of the lane 2 verifier's
(`GA-P`).

## §1 What shipped

All of it is in `Backends/SDL`, class `M` (SwiftUI has no GPU API), behind the `SDL` trait (`GA-J`).

- **A new product `MetalUISDLGPU`** (`Backends/SDL/Sources/MetalUISDLGPU`, declared once in the root manifest, `GA-B`),
  a Swift layer over SDL_GPU named after it, with `@_exported import CSDL` so **one `import MetalUISDLGPU` gives the
  wrapper and every `SDL_` symbol** (the escape hatch; every wrapper also has `.raw`). The option ruled (`GA-A`) is (b)
  plus (a); (c) a portable cross-backend GPU API is refused: a product boundary of its own, and Metal apps have
  `MetalDrawContext`.
- **Compute (lane 1, the slice that blocks xp-c).** `SDLGPUDevice` (`make(debug:preferring:)` owns a standalone device
  and answers `nil` with `SDLGPUDevice.lastFailure`; `init(borrowing:)` wraps the window renderer's device, never
  destroyed, `GA-D`), `SDLGPUBuffer`, `SDLGPUTransferBuffer`, `SDLGPUComputePipeline`, `SDLGPUComputePass`,
  `upload`, `download` (copy pass, fence, map: the three SDL sequences the wrapper adds, `GA-A`), `clear(range)` for a
  counter. **An atomic append is a storage-buffer counter** (SDL_GPU has no append buffer, `GA-G`).
- **The off-main fence (`GA-E`).** `device.submitBatch { cb in … }` is `async`, records and submits on a dedicated serial
  worker thread, and returns an `SDLGPUFence`; `await fence.wait()` hops to a dedicated waiter thread, so the main actor
  is never blocked. Every fence's wait is queued on the waiter **at submission**, so each is released after its signal
  whether or not anyone awaits it (the fence rule, §61 §10; cancelling the waiting task releases nothing early).
  Creation and release take one device lock, `make` one process-wide lock (`GA-N` item 8).
- **Shaders (`GA-F`).** `Backends/SDL/scripts/compile-app-shaders.py` (HLSL to `.spv`, `.msl`, `.dxil` and reflection
  `.json` through shadercross, with a `SOURCE.sha256`), `SDLGPUShaderLibrary` (looks in `MetalUIAppShaders` beside the
  executable, then the source tree; names every directory tried; reflection fills every count of a pipeline), checked-in
  blobs (`Backends/SDL/Tests/AppShaders/compiled/`, CI-reproducible with no shadercross, the `replay.hlsl` way);
  `docs/packaging.md` section 4a is the shipping rule, after `PX-P`.
- **Graphics into a surface (lane 2, `GA-H`).** `SDLGPUTexture` (4x MSAA, `D32_FLOAT` depth, mipmapped `R8`,
  `R32_UINT` ID target, `generateMipmaps`), `SDLGPUSampler`, `SDLGPUGraphicsPipeline` (instanced draws, vertex buffers,
  storage buffers, premultiplied blend, depth state), `SDLGPURenderPass` with one colour attachment, an optional resolve
  and an optional depth attachment, and `ctx.view`, an `SDLGPUFrameView` over the frame's **own** command buffer and a
  **non-owning** target. The view has no submit, cancel, wait or acquire verb; MetalUI submits once, as before.
- **The debug check (`GA-I`, `GA-O`, `GA-P`).** `SDLGPUWindowGuard` (`package`, `MetalUISDL`, `#if DEBUG` bodies only),
  bracketed around each surface draw in `SDLWindowRenderer.finishFrame` (three lines): a draw that returns with a typed
  pass open and a typed `waitForIdle` inside a draw trap naming the contract; a raw SDL call stays undetected, and
  `SDLGPUDrawContext`'s doc comment says so.

## §2 Tests, per file (`Backends/SDL/Tests/MetalUISDLTests`)

27 new tests, all in `Backends/SDL`, none in the root package (so the root suite is the merged master's unchanged;
`GA-L`: `Backends/SDL` is outside the census and macOS CI runs no SDL test).

| file | tests | what |
|---|---|---|
| `SDLGPUComputeTests` | 8 | `aRequiredGPUIsPresent`; C1 the atomic append emits exactly the threads that pass (counter and sorted payload, ten downloads); C2 a storage buffer round-trips, a ranged download is exact; C11 `clear` zeroes only its range; C3 the fence is awaited off the main actor; C4 a cancelled waiter never releases an unsignalled fence; C8 no GPU is a named failure, not a trap; C10 a borrowed device is not destroyed (per-handle count) |
| `SDLGPUShaderLibraryTests` | 5 | C5 reflection fills every pipeline count; a missing stage or driver is named; C6 lookup order (beside the executable, then the source tree); C7 every checked-in blob belongs to its source (`SOURCE.sha256`, any machine); the SHA-256 standard vectors |
| `SDLGPUWindowDeviceTests` | 1 | C9 200 frames of a continuously drawn surface while 50 append batches run on the worker, on a borrowed device |
| `SDLGPUReExportTests` | 1 | one import of the product reaches `SDL_GetError` (it cannot prove `@_exported` alone: the consumer build is the instrument, `GA-N` 1) |
| `SDLGPUGraphicsTests` | 7 | G1 instanced, depth-tested, 4x MSAA resolved triangle set against its reference (offscreen texture); G1s the same into a real surface target; G2 an ID pass (instance + 1) read back; G3 mip chain of an `R8` texture; G4 the vertex stage reads a storage buffer; G5 a fragment stage samples a mip level through a sampler with a push-constant uniform; G6 interleaved vertex buffer and premultiplied blend |
| `SDLGPUContractTests` | 5 | D1 an open pass at the end of a draw traps; D2 `waitForIdle` in a draw traps; D3 the frame view declares no submitting verb (source scan); D4 a typed draw adds no submission (buffer identity, delta, 0 unsignalled releases); D5 the guard is off after the draw returns |

No typecheck guard: a guard cannot reach the layer (the root package builds without the `SDL` trait, D3's source scan is
the stand-in, `GA-O` 7). The root package's guard count is the merged master's, **238**.

## §3 Probes

None owed and none run (`GA-J`): nothing here is a SwiftUI-facing claim. The facts the rulings rest on are SDL 3.4.18's
headers on this machine (the Linux image builds `release-3.4.16`, so every call used exists there) and measurements:
the thread rules of `GA-E` are the headers' (`\threadsafety`) plus C9; the Metal and lavapipe behaviour is `GA-N`/`GA-O`.

## §4 Red runs

Lane 1 (`a95cdc8c`): the compute and shader-library tests did not compile (`error: cannot find 'SDLGPUDevice' in scope`,
`SDLGPUTestSupport.swift:23` and `:26`); the re-export test passed (`GA-B` holds). Lane 2 (`8c894ebf`): `cannot find
'SDLGPUColorAttachment' in scope`, `value of type 'SDLGPUDrawContext' has no member 'view'`, `cannot find
'SDLGPUWindowGuard' in scope`.

## §5 Mutation tables

**Lane 2** (`GA-O`, committed tree, restored from git, whole `Backends/SDL` suite, nothing else reddened): G1-a samples 4
to 1: G1, G1s. G1-b compare `LESS` to `ALWAYS`: G1, G1s, G2. G1-c `instanceCount` 3 to 2: G1, G1s. G1-d `.resolve` mapped
to `DONT_CARE`: G1, G1s. G2 `id.frag.hlsl` `+ 2` (blobs rebuilt, `SOURCE.sha256` consistent): G2. G3 mip generation
skipped: G3, G5. G4 storage buffer at slot 1: G4. G5 level 2 to 1: G5. G6-a blend never enabled: G6. G6-b colour offset 8
to 0: G6. D2 the `waitForIdle` guard line removed: D2. D3 `public func submit()` added to the view: D3. D5 `endDraw`
leaves `drawingThread` set: D5. D4 the view recording into a buffer of its own: D4, G1s, D3. **Hangs, counted reddened
because the unmutated suite finishes in 7 s:** `beginDraw` moved after the draw (D1b) and `endDraw`'s open-pass check
dropped (D1c): Metal never finishes a frame with a pass open. **A crash that counts:** D1-a (`passBegan` not counted)
takes the count to -1 and the guard traps in G1s, so D1 itself was not seen red there.

**Lane 1** (implementer's table, partly re-taken by the verifier): `download` without its fence wait: C1, C2, C11 (the
verifier's run finished "failed with 23 issues"; it read the names for the implementer's run only); `SDLGPUDevice.deinit`
destroying without the `owned` check: C10 (issue at `SDLGPUComputeTests.swift:183`, then signal 11 on the double
destroy). C5's binding-count swap **hangs** a later GPU test on Metal (killed after 6 minutes; counts because the
unmutated suite finishes and `reflectionFillsEveryPipelineCount` itself reads red, `GA-N` 7). The other lane 1 mutations
(the test comments name them: C1 predicate and halved dispatch, C3 inline blocking wait, C4 release in the cancel handler,
C6 order swap, C7 one-byte source change, C8 force-unwrap) are the implementer's; the per-mutation reddened lists were not
re-taken by the verifier and are not reconstructed here. C9 is a stress pin that no mutation turns red deterministically
(removing the creation lock reddens nothing); `SDLGPUReExportTests` cannot go red alone (`GA-N`).

**Verifier findings and the Record phase's answer.** (1) *Major:* the checks in `submitBatch` and `SDLGPUFence.wait`
reddened nothing when removed; only `waitForIdle` is pinned. The Record phase wrote exit tests for both
(`Task.immediate` from the draw) and they could not tell the guard from an unrelated crash with the guard removed
(`dispatch_assert_queue` in `SDLWindowRenderer.deinit`), so they were **not kept**: `GA-P` rules the claim narrowed, the
doc comments of `SDLGPUDrawContext` and `SDLGPUWindowGuard` now say "pinned" only for `waitForIdle` and an open pass, and
the hook that would make them reachable is carried. (2) *Minor:* D1 was never seen red on its own (hang or crash);
carried as `GA-O` says, D1b/D1c are its observed reds.

## §6 Counts and verification

Root, after merging master and `swift package clean`, `swift build --build-system native --build-tests`, then
`swift test --build-system native --no-parallel` unfiltered: **3799 tests in 3 suites passed** after 799 s (3717 at `fb9a7e42` plus master's 82 from §112, §113 and §111; this branch adds no root test), 0 `error:`, the only `warning:` SwiftPM's deprecation notice; 238 typecheck guards (master's, unchanged: `git diff ceca59f6 HEAD -- Tests Sources` is empty). `FR-J no-argument frame: succeeded=true`: read in the log.
Default build system `swift build --build-tests`: 0 `warning:`.
`Backends/SDL` on macOS (lane 2 at its head, before the merge): **152 tests in 4 suites passed**, 0 warnings; the Linux
image (lavapipe, `SDL_VIDEO_DRIVER=offscreen`): **149 tests in 4 suites passed**, the three skips the older
presented-frame tests, none of the new ones. Lane 1 alone: macOS 140 + 30, Linux 136. The inventory and undocumented
scripts print nothing (`GA-L`: no map row, census unmoved). `compare.sh` against `fb9a7e42`: all fourteen offscreen
images **0 px, scene identical** (by construction: no `Sources/` change by this branch).

## §7 Hazards

- **Windows is unmeasured.** The UTM VM did not answer (`ssh metalui-win` timed out) in both lanes. The DXIL blobs have
  never run; CI's Windows job runs the suite with `METALUI_REQUIRE_GPU=1` on WARP, which is where an `R32_UINT` colour
  target and 4x MSAA on `R8G8B8A8` first meet D3D12 (check GA2).
- **Metal hangs, not fails, on a wrong binding or an open pass** (GA-N 7, GA-O): a mutation of either hangs the suite
  rather than reddening a pixel. A suite with no summary line after 12 minutes is a hang.
- **macOS video init is main-thread only** (`GA-N` 5): `make` hops to the main queue for `SDL_InitSubSystem`.
- **A borrowed device is raced by the worker and the window's main-thread frame**; C9 passes on macOS and in the Linux
  image, but removing its lock reddens nothing, and the degrade path of `GA-E` item 4 (borrowed devices submit on the
  main actor) is unproven and unneeded so far.
- **Three hours-old `swiftpm-testing-helper` processes of this worktree's `Backends/SDL` build** (pids 2476, 33729,
  34030: earlier lanes' hung mutation runs, not the Record phase's) were alive at the Record phase; the sandbox refused a
  `kill` of them, so they were left. They belong to this worktree's `.build` only; the orchestrator may reap them.

## §8 Deferrals, with owners

- Compute **storage textures**, indirect dispatch and indirect draws, multiple render targets, stencil, 3D and array
  textures, viewport and scissor: `.raw` and SDL cover them; owner the xp-c integration (`GA-C`, `GA-O` 2).
- A hook that sets the draw flag from a test on the calling thread, to pin `submitBatch` and `fence.wait` inside a draw:
  owner the xp-c integration (`GA-P`).
- `MetalDrawContext.drawText` and its SDL twin stay deferred (`GT-F`).
- Windows D3D12 and real-hardware runs: CI and human check GA2; the looks GA1, GA3, GA4: a person.
- A macOS run is a hand run: macOS CI executes no `Backends/SDL` test (`GA-L`).

### Windows CI fixes, 2026-10-14

Run 38616601574 (Windows x64, D3D12) failed three tests; macOS and Linux were green (ruling `GA-Q`).
- `aCheckedInAppShaderBlobMatchesItsSource` and `theFrameViewDeclaresNoSubmittingVerb`: `split(separator: "\n")` does not
  split a `"\r\n"` (one `Character`) in a CRLF checkout. Both split on `isNewline`; a root `.gitattributes` fixes
  `*.hlsl`, `SOURCE.sha256`, `*.msl`, `*.json` to LF and `*.dxil`, `*.spv` to binary. Mutation on macOS: a flipped hash byte is red;
  a CRLF `SOURCE.sha256` is green.
- `anIDPassReadsBackTheInstanceUnderAPixel`: `E_INVALIDARG` from the PSO. `id.frag` read only `TEXCOORD1`, so its input
  register differed from the vertex stage's; it now also reads `color` (never true), the blobs were rebuilt with
  SDL_shadercross 3.0.0 (old blobs rebuilt byte-identical first). The D3D12 cause is inferred; CI is the evidence.
