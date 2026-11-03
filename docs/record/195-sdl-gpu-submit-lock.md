# 195 - SDL GPU submit and map under the device lock (`GA-S`, MetalCreator XP-G37)

2026-11-02, branch `fix/sdl-gpu-submit-lock` from master `76b03e58`. Ruling `GA-S` in `docs/superpowers/2026-10-14-sdl-gpu-compute-decisions.md`
(amends `GA-E`); rule in `docs/rules/sdl.md`. No divergence.

## 1. Cause

An intermittent SIGSEGV in SDL 3.4.16's `VULKAN_Submit` (lavapipe, Linux x86_64). On a device with no claimed window `VULKAN_Submit` runs the inlined
`VULKAN_INTERNAL_DefragmentMemory` under `submitLock` and `allocatorLock`. For each used region it checks `!markedForDestroy`, creates a new buffer, then writes
`newBuffer->container->buffers[...]`. `SDL_ReleaseGPUBuffer` on another thread takes only `disposeLock`, sets `container = NULL` and frees the container: the NULL+8
read. Textures have the same shape (a use-after-free). SDL `main` has it; there is no upstream fix or issue, so the fix is ours. A defragment is only
scheduled when an allocation request finds no free region that fits (`VULKAN_INTERNAL_MarkAllocationsForDefrag`), so a stress needs 16 MiB allocations filled with
mixed 1 KiB - 4 MiB buffers and holes later requests do not fit. `SDL_MapGPUTransferBuffer`/`Unmap` during a defragment is a related hazard (SDL issues 11107, 12242).

## 2. Evidence

Source and disassembly of a rebuilt `SDL_gpu_vulkan.c` at `release-3.4.16`. Reproduced here under lldb in the Linux image (aarch64): `stop reason = signal SIGSEGV:
address not mapped to object (fault address=0x8)`, `frame #0: libSDL3.so.0 VULKAN_Submit + 1732`, thread `DispatchWorker`.

## 3. Fix

`SDLGPUDevice.submitWithFence(_:)`, `mapTransfer(_:)` and `unmapTransfer(_:)` wrap `SDL_SubmitGPUCommandBufferAndAcquireFence`, `SDL_MapGPUTransferBuffer`
and `SDL_UnmapGPUTransferBuffer` in the device lock that creation and release already took. Sites changed: `SDLGPUDevice.recordAndSubmit` (batch and synchronous batch),
`SDLGPUDevice.downloadSynchronously` (`SDLGPUReadback.swift`), `SDLGPUTransferBuffer.map()`/`unmap()` (`SDLGPUBuffer.swift`). Lock order: device lock -> SDL's `submitLock`
-> `allocatorLock`/`disposeLock` (doc comment on `submitWithFence`). The lock is never held across `SDL_WaitForGPUFences`, and no helper takes the lock then calls another
that does. Not covered: `SDLBridge.c`'s own submit/map sites (the window renderer's device, a different owner of the lock) and SDL's own window-frame submits.

## 4. Tests (`Backends/SDL/Tests/MetalUISDLTests/SDLGPUSubmitLockTests.swift`)

- `submitAndMapRunUnderTheDeviceLock` (L1): hook counters `submitLockedCount`/`submitUnlockedCount`/`mapLockedCount`/`mapUnlockedCount`, observed by `lock.try()` inside the helpers.
- `submitAgainstConcurrentReleaseDoesNotCrash` (L2): one submit thread, three threads creating and dropping mixed-size storage and transfer buffers (map/unmap on the transfer ones);
  `METALUI_SUBMIT_STRESS_SECONDS` (default 5).

## 5. Mutations (macOS, each applied alone)

| Mutation | Reddened |
| --- | --- |
| `lock.lock()` removed from `submitWithFence` | `submitAndMapRunUnderTheDeviceLock` (submit locked count and unlocked == 0) |
| `lock.lock()` removed from `mapTransfer` | `submitAndMapRunUnderTheDeviceLock` (map locked count and unlocked == 0) |
| `downloadSynchronously` calls `SDL_SubmitGPUCommandBufferAndAcquireFence` directly | `submitAndMapRunUnderTheDeviceLock` (locked submits 2, not >= 3) |
| all three locks removed (Linux) | `submitAgainstConcurrentReleaseDoesNotCrash` (SIGSEGV) |

`unmapTransfer` is not observed by a hook; its lock is unpinned by L1 (L2 covers it only by crash, probabilistically).

## 6. Linux runs (Docker, `Backends/SDL/linux/Dockerfile`, native aarch64, Mesa lavapipe, SDL release-3.4.16)

- First stress shape (256 B - 512 KiB buffers, 48 live per thread), locks removed: 5 attempts x 60 s, no crash. That shape never triggers a defragment (section 1).
- Final shape (1 KiB - 4 MiB, 40 live per thread), locks removed: 3 of 3 attempts crashed (SIGSEGV, `VULKAN_Submit`, lldb run above). 
- Final shape, with the fix: 3 attempts x 60 s, all passed; full `--filter SDLGPU` on Linux: 103 tests in 13 suites passed.
- x86_64 (the reporter's platform) was not run; emulation was not tried.

## 7. macOS

`Backends/SDL` `swift test`: 352 tests in 20 suites, 2 issues, both the known `SDLGPUShaderLibraryTests` temp-directory permission (NSCocoaErrorDomain 513).
