# SDLGPUDevice adapter info and limits for MetalCreator (XP-G23, XP-G24) — decisions

Rulings for items XP-G23 and XP-G24 of the gpui-gap priority list (MetalCreator request 2026-10-22; **not a plan task**). Prefix `DL-`.
**Next unused: `DL-O`.** Spec: [`specs/2026-10-22-sdl-gpu-device-info-design.md`](specs/2026-10-22-sdl-gpu-device-info-design.md). Record: `../record/150-sdl-gpu-device-info.md`.
Branch `feat/sdl-gpu-device-info` from `63feea05`. Continues `GA-` (record 114), `GB-` (137), `SY-` (143). Divergence labels reserved 795–804: **none taken**.

Sources of truth. SwiftUI has no GPU API: no SwiftUI-facing claim, no probe owed; gpui exposes no adapter query to an app (recalled, context only). Facts
come from `SDL_gpu.h` and `SDL_init.h` of SDL 3.4.18 (`/opt/homebrew/include/SDL3`) and the Dockerfile's `release-3.4.16`, and from `SDLGPUDevice.swift` at
`63feea05`. Backends/SDL is outside the census (`GA-L`); class M. Statements about the Vulkan, D3D12 and Metal specifications are **recalled** (the specs are
not on this machine) and marked so; the implementer re-checks them if the registry is reachable.

## DL-A — the API exists at the pinned SDL; use it, no fallback

**Evidence.** `SDL_GetGPUDeviceProperties` is "available since SDL 3.4.0", thread-safe from any thread; both 3.4.16 (CI/image) and 3.4.18 (here) have it.
**Ruling.** Read the four string properties directly; no `#if` or runtime probe. A property id of `0` or an absent key answers `nil`; an empty string is `nil`.
**Cost if wrong.** A consumer on SDL 3.2 would fail to link; the package already requires 3.4 for other calls (verify with the Package's SDL pin at implementation; if it
claims 3.2, a later ruling raises the floor).

## DL-B — `isSoftwareRasterizer` is a documented substring heuristic over name, driver name and driver info

**Evidence.** SDL: the name "has no standardized format ... Do not attempt to parse this string", yet lists `llvmpipe (...)`, `SwiftShader Device (...)`, `Microsoft Basic
Render Driver` as in-the-wild software devices, and says a device "may be emulated in software". No SDL boolean exists.
**Ruling.** Lowercased match over `adapterName`, `driverName`, `driverInfo` for the substrings `llvmpipe`, `lavapipe`, `softpipe`, `swiftshader`,
`microsoft basic render driver`, and the **whole word** `warp`; the doc comment says it is a heuristic over SDL's unstable strings, names the list, and that a
`false` is "not recognised", not "hardware". Backend `"metal"` always answers `false`: Apple exposes no software Metal device through SDL (a VM's paravirtual GPU is
hardware-backed and slow-listing it as software would mislead a chunk-size choice). The matcher is a `package` pure function so a test feeds it strings (D1).
**Cost if wrong.** A new software driver (e.g. a future Mesa name) reads `false`: a caller loses a hint, never correctness; the fix is a list entry plus a D1 row.

## DL-C — limits are guaranteed floors, not the device's limits, and say so

**Evidence.** SDL_gpu.h documents no limit and has no query (searched for `max`, `minimum`, `guarantee`: only texture-format guarantees). Direct API calls
(Vulkan `vkGetPhysicalDeviceProperties`, D3D12 `CheckFeatureSupport`, `MTLDevice`) would need each backend's handle, which SDL does not hand out portably.
**Ruling.** `SDLGPUDevice.limits` returns constants valid on every SDL_GPU backend, `areGuaranteedFloors == true`: `maxStorageBufferBindingBytes = 134_217_728`
(2^27: Vulkan's required minimum `maxStorageBufferRange` is 2^27, recalled; D3D12's minimum resource size is 128 MiB, recalled; Metal's `maxBufferLength` minimum is
256 MiB, recalled) and `maxComputeWorkgroupCount` 65 535 per dimension (Vulkan's required minimum `maxComputeWorkGroupCount`, D3D12's `Dispatch` limit of 65 535, recalled;
Metal's dispatch is larger). The doc comment quotes the SDL fact that no query exists and tells the caller to size work to these or to probe by running. No driver
call is made. **Cost if wrong.** A caller on a large GPU under-uses it (a floor is safe, never an over-claim); a wrong recalled constant would be an over-claim, which is why
the implementer re-checks the three recalled minimums and D5 pins the numbers.

## DL-D — raw strings exposed, read per call, no stored copy

**Ruling.** `driverName`, `driverVersion`, `driverInfo` are exposed beside `adapterName` (cheap: one property read each, `driverInfo` may hold newlines and a trailing newline,
returned as SDL gave it). Nothing is cached: SDL's strings are owned by the properties object and read from any thread, so a stored copy adds only a staleness risk.
**Cost if wrong.** A few extra lookups per call; callers cache if they care.

## DL-E — a new file, no new stored property, no `swift package clean`

**Ruling.** Everything lives in `SDLGPUDeviceInfo.swift` as an extension plus a struct, so `SDLGPUDevice`'s layout is untouched (no stored property crosses a module
boundary, so no clean is owed for that reason). **Cost if wrong.** None.

## DL-F — owned and borrowed devices answer through one code path

**Ruling.** Every property reads `raw`; no branch on `owned`. D6 compares a window-renderer device taken through `init(borrowing:)` with a `make()` device on the same driver.
**Cost if wrong.** A borrowed view of a different adapter than `make()` chooses (two GPUs) would differ in `adapterName`; D6 then compares only when `driver` matches and the test records
both names rather than asserting equality across adapters (decided at implementation, noted in the record).

## DL-G — thread answers (a) and (b): documented, measured, and `make` does not hop off macOS

**Evidence.** SDL: `SDL_INIT_VIDEO` "should be initialized on the main thread" and `SDL_InitSubSystem` "should only be called on the main thread"; `SDL_CreateGPUDevice` states no
thread rule. This repository's `make` takes `makeLock` and, on macOS only, runs the video init on the main thread (Cocoa fails off it) — so (b) on macOS is supported by construction.
On Linux/Windows the init runs on the caller. SDL's init is reference counted (recalled from SDL's source: a subsystem already initialised is only retained), so once an
`SDLPlatform` has initialised video on the main thread an off-thread `make` only bumps the count.
**Ruling.** (a) Supported when video is already initialised: D7 measures a detached-thread `make` plus a compute or copy batch beside a live window renderer device on macOS and in the Linux
image on lavapipe. (b) Recommended, not required: **initialise video on the main thread first** (the app's `SDLPlatform` does; a headless tool calls `make` once on the main thread before
spawning workers); an off-thread first `make` on Linux is measured by D8 and the result is recorded verbatim. `make` does not hop to the main queue off macOS: a headless process that never
pumps the main queue would deadlock (`SV-H`: SDL drains it only inside its run loop). The doc comment on `make` carries the SDL quotes and the measured result. **If D7 or D8 refute this**
(a hang, a trap, a `nil`), a later ruling amends `make` (for example a main-thread requirement as a `precondition` naming the fix) with a migration note.
**Cost if wrong.** MetalCreator hits a loader fault on a platform we did not measure (Windows is compiled by CI only); the reply-ready text says so.

## DL-H — reply-ready text for MetalCreator (final numbers filled at the Record phase)

(a) "A second engine-owned headless device from `SDLGPUDevice.make` off the main thread, beside a window renderer's device, is supported and pinned (D7: macOS and Linux lavapipe).
Creation and release take one lock; each device has its own worker threads. (b) SDL documents video init as main-thread-only; `make` hops to the main thread on macOS itself; on Linux
initialise video once on the main thread (your `SDLPlatform` already has) and later `make` calls only retain it; D8 measured the first-call-off-thread case as <result>." The record
fills `<result>`.

## DL-I — no divergence, no probe, no demo, no human check, no migration note, no census row

**Ruling.** Additive class-M API outside the census; no seam requirement; no shader change; no `Sources/` change, so the fourteen images 0 px and the root count 4371. The `Backends/SDL`
count rises by the tests of the table (8 on macOS, fewer in the Linux image where D4 is compiled out). **Cost if wrong.** A moved root number would mean the lane left `Backends/SDL`.

## DL-J — critic: D3 is required on Linux, not gated by an env var

**Defect.** D3 leaned on `METALUI_REQUIRE_SOFTWARE=1` "set by the Docker run line"; the run line is fixed by the workflow and sets no such variable, so D3 would skip silently in the image and could never be red there.
**Ruling.** On `#if os(Linux)` D3 requires `driver == "vulkan"` and, when `adapterName` contains `llvmpipe` (read raw, independent of the matcher), `isSoftwareRasterizer == true`; if no GPU exists the test is skipped by `GPUTestSupport` as the others are, and the Linux image result must be quoted from a run where it executed (a skipped D3 is not evidence). No new environment variable.

## DL-K — critic: D7/D8 never block the main actor, and D8 says whether it was the first video init

**Defect.** On macOS `make` hops to the main queue for video init; a test that waits for the detached thread on a semaphore from the main actor deadlocks that hop. And D8 cannot measure "first init off the main thread" if an earlier test of the same process initialised video (SDL's init is process-wide).
**Ruling.** The test awaits the worker through a continuation (main actor suspended, main queue free), with a bounded timeout task, never a blocking wait. D8 reads `SDL_WasInit(SDL_INIT_VIDEO)` first and records it: with video already up it measures only the refcount path and the record says so; the first-call-off-thread evidence is the Linux image run of D8 **filtered alone** (`swift test --skip-build --filter SDLGPUDeviceInfoTests/videoInitOffTheMainThreadIsMeasured`), quoted with that filter. If no filtered-alone run is possible the record states (b) as unmeasured for the first call.

## DL-L — critic: D6 borrows from a window renderer's device where a frame can run, and says what it could not compare

**Defect.** "A surface draw's context device" needs a presented frame; the Linux image's `offscreen` video driver never presents one, so D6 would not execute there.
**Ruling.** D6 takes the device from the offscreen `SDLWindowRenderer` (or whatever `SDLPlatform(offscreenRenderers:)` exposes) through `init(borrowing:)`; where no accessible window device exists it falls back to `SDLGPUDevice(borrowing: owned.raw)` of a second `make` device and the test name/record says that arm proves the single-code-path claim (`DL-F`) only, not cross-device equality. Equality is asserted only when `driver` matches (`DL-F`).

## DL-M — measured: the recalled minimums re-read, the thread answers, and what D7/D8 can and cannot see

**Limits re-checked (`DL-C`).** The Vulkan "Required Limits" table, fetched from the registry (`vkspec.html`, 2026-10-22), reads `maxStorageBufferRange` min `2^27` and `maxComputeWorkGroupCount` min `(65535, 65535, 65535)`: both constants stand. The Direct3D 12 and Metal figures stay recalled (not on this machine); they are floors the doc comment marks as such and cannot over-claim Vulkan's own table.
**Measured thread answers (`DL-G`).** (a) D7 passes on macOS (Metal, Apple M1 Max) and in the Linux image (lavapipe `llvmpipe (LLVM 20.1.2, 128 bits)`, Mesa 25.2.8): a detached `Thread` calls `make()` beside a live window renderer's device, uploads 256 bytes, copies them back through two synchronous batches and reads them equal. (b) D8, **filtered alone in the image** (`--filter SDLGPUDeviceInfoTests/videoInitOffTheMainThreadIsMeasured`, `videoAlreadyInitialised=false`, no probe or `make` before it on Linux), a first `make` with no window anywhere on a detached thread answers `vulkan llvmpipe…` with an empty `lastFailure`: **SDL video init off the main thread works on Linux with the offscreen driver and lavapipe.** SDL still documents it as main-thread-only, the measurement is one driver (offscreen) on one platform, and Windows is compiled by CI only, so the recommendation in `make`'s doc comment (initialise video on the main thread first) stands. `DL-G` is not refuted; no behaviour change to `make`.
**D7/D8 instrument findings.** On macOS, `GPUTestSupport.available` is evaluated by Swift Testing off the main thread, so a `make` that lost its main hop makes **every** gated GPU test skip silently (0.001 s; only `SDLGPUComputeTests.aRequiredGPUIsPresent` under `METALUI_REQUIRE_GPU=1` would say so). D8 therefore carries no `.enabled(if:)` trait: on macOS a main-thread probe `make()` decides whether a GPU exists, then the detached `make` must answer (M11 reddens it); off macOS, D8 asserts the answer only under `METALUI_REQUIRE_GPU=1` (set by CI; the workflow's own run line does not set it, M12 reddens D8 only with it). D7 stays green with the main hop removed because its window renderer has already initialised video (a refcount bump): D7 proves (a), D8 proves the hop.
**Survivors, named.** M10 (`make` without `makeLock`) reddens nothing on either platform (C9's recorded unproven-instrument finding stands: Vulkan's loader race is not deterministic; kept as a stress arm, not a mutation pin). M5 (`isSoftwareRasterizer` always false) survives on macOS by design (Metal is false) and is red in the Linux image through D3.

## DL-N — `isSoftwareRasterizer` on Metal: the properties answer nothing, the flag is `false`

**Measured.** On Apple M1 Max, `adapterName` is `Apple M1 Max` and `driverName`, `driverVersion` and `driverInfo` are `nil` (Metal has no driver strings); `isSoftwareRasterizer` is `false` (D4). On lavapipe: `driverName` `llvmpipe`, `driverVersion` `25.2.8`, flag `true`. **Ruling.** Unchanged `DL-B`; a caller must treat the three driver strings as optional on Metal.
