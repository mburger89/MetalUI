# 150. SDLGPUDevice adapter info, software flag and limits (XP-G23, XP-G24)

Items XP-G23 and XP-G24 (MetalCreator xp-c plan, 2026-10-22; **not a plan task**). Branch `feat/sdl-gpu-device-info` from `63feea05`, `Backends/SDL`'s `MetalUISDLGPU` only. Spec `docs/superpowers/specs/2026-10-22-sdl-gpu-device-info-design.md`; rulings `docs/superpowers/2026-10-22-sdl-gpu-device-info-decisions.md` (`DL-A`...`DL-N`, next `DL-O`). Class M, outside the census (`GA-L`), no divergence (795-804 untouched), no probe (SwiftUI has no GPU API), no root `Sources/` or `Package.swift` change.

## 1. What was built

`SDLGPUDeviceInfo.swift` (new): `SDLGPUDevice.adapterName`, `driverName`, `driverVersion`, `driverInfo` (SDL 3.4's `SDL_GetGPUDeviceProperties`, read per call, `nil` when absent or empty, `DL-A`, `DL-D`), `isSoftwareRasterizer` (a `package` pure matcher `SDLGPUDeviceInfo.looksSoftware(adapterName:driverName:driverInfo:backend:)`: lowercased substrings `llvmpipe`, `lavapipe`, `softpipe`, `swiftshader`, `microsoft basic render driver` and the whole word `warp`; Metal always `false`, `DL-B`) and `limits: SDLGPUDeviceLimits` (**guaranteed floors, not the device's limits**: SDL has no query; `maxStorageBufferBindingBytes` 2^27, `maxComputeWorkgroupCount` 65 535 per dimension, `areGuaranteedFloors == true`, `DL-C`). One code path for owned and borrowed devices (`DL-F`); no stored property, so no `swift package clean` owed (`DL-E`). `make`'s doc comment carries SDL's thread quotes and the measured answer (`DL-G`); no behaviour change. No docs/packaging.md or guide edit (neither lists the device API); no migration note (additive).

## 2. Red first

Tests alone at the "red tests D1-D8" commit: every test a compile failure, for example `value of type 'SDLGPUDevice' has no member 'adapterName'` (also `driverName`, `driverVersion`, `driverInfo`, `isSoftwareRasterizer`, `limits`).

## 3. Mutations (committed first, restored by `git checkout -- Sources`, `git status --short` clean after; filtered to `SDLGPUDeviceInfoTests`, **not** the full Backends/SDL suite, a deviation from the full-suite rule justified by 10 s builds against a 14 s suite and a mutation touching only this file or `make`)

macOS (Metal): M1 no lowercasing: D1 (+ others, 6 issues). M2 `warp` as a substring: D1. M3 no `microsoft basic render driver`: D1. M4 adapter name reads the driver-name key: D2. M7 no Metal backend guard: D1. M8 floor minus one: D5. M9 `adapterName` nil on a borrowed device: D6. M11 `make` without the macOS main hop: **D8** (after the gate fix of `DL-M`; before it every GPU test skipped silently and nothing reddened). **M5 (flag always false) survives on macOS by design** (Metal is false) and **M10 (no `makeLock`) survives on both platforms** (the recorded C9 finding: not deterministic).
Linux image (lavapipe): M5: D3 (2 issues). M6 no `llvmpipe`: D3 (+ D1). M12 `make` without `SDL_InitSubSystem`: D8, **only with `METALUI_REQUIRE_GPU=1`** (CI sets it; without it all GPU tests skip and D8 accepts `nil`). M10: survives.

## 4. Verification

- `Backends/SDL` macOS, `METALUI_REQUIRE_GPU=1`, `--no-parallel`: 30 + 278 passed (the 8 new). **A parallel run of the whole suite hung on a window test (output stopped at `SDLImageCursorTests.closingTheLastWindowDestroysEveryImageCursor`'s neighbourhood) for 18 minutes and was killed**; not investigated (the new tests were not running), `--no-parallel` is the rule.
- Linux image (`swift:6.4-noble` via `metalui-portable`, volume `metalui-sdl-build-sdl-gpu-device-info`): 30 + 275 passed, all of `SDLGPUDeviceInfoTests` executed. D3 ran and read `true`: `DL device: backend=vulkan name=llvmpipe (LLVM 20.1.2, 128 bits) driverName=llvmpipe version=25.2.8 soft=true`. D8 **filtered alone**: `videoAlreadyInitialised=false offThreadMake=vulkan llvmpipe (LLVM 20.1.2, 128 bits) lastFailure=` passed.
- macOS device: `backend=metal name=Apple M1 Max driverName=nil version=nil soft=false` (`DL-N`).
- Root, native, after the branch (no root source change): **4371 tests in 10 suites passed**, `FR-J no-argument frame: succeeded=true`, 0 `error:`, the only `warning:` SwiftPM's deprecation notice; `swift build --build-tests` 0 `warning:`; inventory and undocumented scripts print nothing; census unmoved (`Backends/SDL` is outside it). Fourteen images: 0 px by construction, `git diff 63feea05 HEAD -- Sources Package.swift` is empty (the comparison script was not re-run).
- Not run: Windows (D1 pins the WARP and Basic Render Driver strings without WARP hardware; CI compiles the rest), a second GPU (`DL-F`'s two-adapter case prints instead of asserting).

## 5. Reply-ready text for MetalCreator (`DL-H`)

(a) A second, engine-owned headless device from `SDLGPUDevice.make` off the main thread, beside a window renderer's device, is supported and pinned (D7; macOS Metal and Linux lavapipe): creation and release take one lock, each device has its own submit and waiter threads. (b) SDL documents video init as main-thread-only (`SDL_INIT_VIDEO` "should be initialized on the main thread"). `make` hops to the main thread itself on macOS (do not block the main thread waiting for it). On Linux, measured: a first `make` on a detached thread with no window anywhere answered `vulkan llvmpipe (LLVM 20.1.2, 128 bits)` with no failure (offscreen video driver, lavapipe; Windows unmeasured). The documented-safe pattern still holds: initialise video on the main thread first (your `SDLPlatform` already has) so later off-thread `make` calls only retain the subsystem. `limits` returns guaranteed floors, not the device's real limits (SDL has no query): 2^27 bytes storage-buffer range, 65 535 workgroups per dimension; `isSoftwareRasterizer` is a name heuristic (`llvmpipe`, `lavapipe`, `softpipe`, `swiftshader`, `Microsoft Basic Render Driver`, WARP) and `false` on Metal.

## 6. Carried

Real device limits (SDL has no query; a later ruling when a floor proves too low), workgroup size and shared-memory limits (not asked), a main-thread hop off macOS (refused, `SV-H`), the unexplained parallel-run hang of the whole `Backends/SDL` suite on macOS.
