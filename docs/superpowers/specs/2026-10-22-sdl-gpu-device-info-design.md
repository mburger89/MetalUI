# SDLGPUDevice adapter info, software flag and compute limits (XP-G23, XP-G24) — design

Items XP-G23 and XP-G24 of the gpui-gap priority list (MetalCreator xp-c plan, branch xp-c `8342d72`; **not a plan task**). Rulings:
`../2026-10-22-sdl-gpu-device-info-decisions.md` (`DL-A`…`DL-N`). Record `§150`. **Status: built and verified (2026-10-22), see record §150.** Base `63feea05`, branch
`feat/sdl-gpu-device-info`. `Backends/SDL` only (`MetalUISDLGPU` and its tests) plus docs. Class M, no census row (`GA-L`), no divergence
(labels 795–804 untouched), no SwiftUI claim and no probe (SwiftUI has no GPU API; gpui gives an app no adapter query, recalled, context only).
No root `Sources/` change: the fourteen images stay 0 px and the root count stays 4371.

## The gaps

`SDLGPUDevice` exposes only `driver`, `make(debug:preferring:)` and `init(borrowing:)`. MetalCreator needs (XP-G23) to know which adapter it got and
whether it is a software rasterizer (to pick chunk sizes and to say so in a bug report), (XP-G24) the compute limits its meshing kernels size against,
and two thread answers: (a) may an engine-owned headless device made by `make` **off the main thread** live beside a window renderer's device, (b) is
SDL video init off the main thread on Linux acceptable.

## Facts (SDL 3.4.18 headers on this Mac, `release-3.4.16` in the Linux image; both >= the API's 3.4.0)

- `SDL_GetGPUDeviceProperties(device)` exists since 3.4.0, "safe to call from any thread", properties `SDL_PROP_GPU_DEVICE_NAME_STRING`,
  `..._DRIVER_NAME_STRING`, `..._DRIVER_VERSION_STRING`, `..._DRIVER_INFO_STRING`. The header says the name "has no standardized format ... Do not attempt
  to parse" and lists in-the-wild names including `llvmpipe (LLVM 15.0.4, 256 bits)`, `SwiftShader Device (LLVM 16.0.0)` and `Microsoft Basic Render Driver`.
- The header documents **no** limit query (no storage-buffer size, no workgroup count) and no per-limit property.
- `SDL_InitSubSystem`/`SDL_Init` header: `SDL_INIT_VIDEO` "should be initialized on the main thread"; `\threadsafety` "only be called on the main thread".
  `SDL_CreateGPUDevice` carries **no** `\threadsafety` line. Existing `make` already hops to the main thread on macOS for the video init (`GA-E`).

## Public API (additive, documented, in a new file `SDLGPUDeviceInfo.swift`)

```swift
extension SDLGPUDevice {
    public var adapterName: String?          // SDL_PROP_GPU_DEVICE_NAME_STRING, nil when absent or empty
    public var driverName: String?           // ..._DRIVER_NAME_STRING
    public var driverVersion: String?        // ..._DRIVER_VERSION_STRING
    public var driverInfo: String?           // ..._DRIVER_INFO_STRING (may hold newlines)
    public var isSoftwareRasterizer: Bool    // SDLGPUDeviceInfo.looksSoftware(...) over the three strings, false on "metal"
    public var limits: SDLGPUDeviceLimits    // documented guaranteed floors, DL-C
}
public struct SDLGPUDeviceLimits: Equatable, Sendable {
    public struct Dimensions: Equatable, Sendable { public var x, y, z: Int }
    public var maxStorageBufferBindingBytes: Int      // 134_217_728 (2^27)
    public var maxComputeWorkgroupCount: Dimensions   // 65_535 each
    public var areGuaranteedFloors: Bool              // always true in this build: not queried from the device
}
```
`SDLGPUDeviceInfo.looksSoftware(adapterName:driverName:driverInfo:backend:)` is `package` (a pure function, testable with strings and no GPU). Owned and
borrowed devices read the same `raw` pointer through the same code, so they answer identically on one driver (`DL-F`).

## Implementation (one lane; files disjoint from every sibling)

1. `Backends/SDL/Sources/MetalUISDLGPU/SDLGPUDeviceInfo.swift` (new): the extension, `SDLGPUDeviceLimits`, the pure matcher. Properties are read each call
   with `SDL_GetGPUProperties`-free `SDL_GetStringProperty(SDL_GetGPUDeviceProperties(raw), name, nil)`; a `0` property id answers nil/false (`DL-D`).
2. `SDLGPUDevice.swift`: doc comment on `make` naming the thread answer (`DL-G`, `DL-H`); no behaviour change unless the measured result (tests T6, T7)
   refutes `DL-G`.
3. Tests: new `Backends/SDL/Tests/MetalUISDLTests/SDLGPUDeviceInfoTests.swift`.
4. Docs at Record: record 150, `docs/record/README.md` row, `docs/api-overview.md` line 506 block, CLAUDE.md sentence on the `GB-`/`SY-` paragraph and `DL-` in
   the prefix list, AGENTS.md copy. The guide `drawing-and-gpu.md` lists no device API (grep at design time), so no mirror. Migration note: none.

## Tests (all in `SDLGPUDeviceInfoTests`, `@Suite(.serialized)`; GPU ones `.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason)`)

Red before: every test is a compile failure (the declarations are absent). A mutation that reddens nothing is recorded as the finding.

| # | Test | Asserts | Mutation that must redden it |
|---|------|---------|------------------------------|
| D1 | `theMatcherRecognisesTheSoftwareNamesSDLDocuments` | pure: `llvmpipe (LLVM 15.0.4, 256 bits)`, `SwiftShader Device (LLVM 16.0.0)`, `Microsoft Basic Render Driver`, `Microsoft Direct3D12 (WARP)`, a driverInfo `Mesa 24.0 (LLVM 17)` with name `lavapipe` are software, in any case; `NVIDIA GeForce GTX 970`, `AMD Radeon (TM) Graphics`, `Apple M3`, `MoltenVK`-driver `Apple M3 Max` are not; `warpath` is not (word match); backend `"metal"` is false even for a software-looking name | drop the lowercasing; drop `warp` word boundary; drop `microsoft basic render driver` |
| D2 | `aDeviceHasANonEmptyAdapterName` | `make()` -> `adapterName` non-nil and non-empty after trimming | read the wrong property key (driver name key) -> on Linux lavapipe name is `llvmpipe…`, driver name `llvmpipe`/`Mesa…`: assert `adapterName != driverName` where both exist, plus `adapterName == String(cString: SDL_GetStringProperty(…NAME_STRING))` |
| D3 | `lavapipeIsASoftwareRasterizerInTheLinuxImage` | `.enabled(if: driver == "vulkan" && name contains llvmpipe)` is the gate for the cross-check; on Linux the test **requires** `isSoftwareRasterizer == true` when the raw name contains `llvmpipe` (`DL-J`; no env var) | `isSoftwareRasterizer` returns `false`; matcher without `llvmpipe` |
| D4 | `aHardwareMacIsNotASoftwareRasterizer` | `driver == "metal"` and `METALUI_REQUIRE_GPU=1` -> `isSoftwareRasterizer == false` (macOS only, `#if os(macOS)`) | matcher run on Metal without the backend guard AND a name containing "software"; (separating arm: D1 backend case) |
| D5 | `limitsAreAtLeastTheDocumentedMinimums` | `maxStorageBufferBindingBytes >= 1<<27`, each workgroup count `>= 65535`, `areGuaranteedFloors` | lower a constant by 1 |
| D6 | `aBorrowedDeviceAnswersLikeAnOwnedOneOnTheSameDriver` | a surface draw's context device (`SDLGPUDevice(borrowing:)`, as C9) vs `make()`: equal `driver`, `adapterName`, `driverVersion`, `isSoftwareRasterizer`, `limits` | `adapterName` reads a stored string set only in `make`; (or `limits` branching on `owned`) |
| D7 | `anEngineDeviceMadeOffTheMainThreadWorksBesideAWindowDevice` | with an offscreen `SDLWindowRenderer` live (its device exists) a detached `Thread` (not the main actor) calls `make()`, runs an `append`-style compute or a copy batch (`upload` + `submitBatch` + `download`) and reads back the CPU-expected bytes; box carries the result, semaphore wait with 60 s bound; main actor never touches the second device | `make` without `makeLock`; on macOS the main hop removed (SDL's Cocoa init fails off main -> `nil` -> test reddens) |
| D8 | `videoInitOffTheMainThreadIsMeasured` | no window anywhere (before any `SDLPlatform`): a detached Thread calls `make()`; records `adapterName` and the answer in the record; Linux image result is the evidence for `DL-G`; asserts only that the call returns (does not trap or hang within 60 s) and that `lastFailure` is empty when it answers non-nil | `make` removing `SDL_InitSubSystem` (Vulkan loader then fails in the image) |

D7/D8 run on macOS (`armMainRunLoopExitCheck()` in every test that creates an `SDLPlatform` or touches SDL video) and in the Linux image on lavapipe.
D7/D8 wait by continuation, never blocking the main actor; D8 is quoted from a filtered-alone image run (`DL-K`); D6 borrows per `DL-L`. Timing-free: bounded waits fail on timeout and never hang; no sleeps.

## Demo, human checks, divergences

None: no pixel, no look, no root change. Human-checks group `DL` is **not** added (nothing an agent cannot run; Windows D3D12/WARP naming is compiled by CI
only, and D1 pins the string table without WARP hardware). Divergences 795–804 untouched.

## Not built (named, with owners)

- **Real device limits** (`vkGetPhysicalDeviceProperties`, `ID3D12Device::CheckFeatureSupport`, `MTLDevice` properties): SDL_GPU exposes none and `DL-C` refuses
  direct driver calls; owner: an upstream SDL request or a later ruling when MetalCreator measures a floor too low.
- **Workgroup size / shared-memory limits**: not asked; carried with the same refusal.
- **A `make` that hops to the main thread off macOS**: refused (`DL-G`); it deadlocks a headless process that never pumps the main queue (`SV-H`).
