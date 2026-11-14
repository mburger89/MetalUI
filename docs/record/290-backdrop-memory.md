# 290 - Backdrop memory: region-sized targets and an idle release (Alloy "glass memory", `BB-U`)

Branch `perf/backdrop-memory` from master `d3a8258d`. Class M, no divergence label (a memory change; the pixels are
byte for byte the old ones). Ruling: `BB-U` in `docs/superpowers/2026-10-10-backdrop-blur-decisions.md`.

**Report.** Alloy's window with two backdrop records (about 600x90 and 360x70 pt, `.regular` glass over
`.thickMaterial`) costs about 4.5-5 MiB of `phys_footprint` over no glass, typing and idle. Goal: within noise.

**Step 1, what the memory is.** Measured with a scratch probe (a real Metal device, a private bgra8 2800x1800 target
as the drawable, two records of 1200x180 and 720x140 device pixels plus a lens, a one-record material, `TASK_VM_INFO`
`phys_footprint`, debug build, `BackdropFrameState.residentTextures`):

| resident texture | size | allocatedSize |
|---|---|---|
| frame target `F` | 2800x1800 | 21,168,128 B (20.19 MiB) |
| pool, 13 textures | 38x6 ... 720x140 (the region, the lens's sharp copy: 606 KB; the 1200-wide region's levels 600x90: 344 KB, 300x45, 150x23 ...) | 1,554,432 B (1.48 MiB) |

`F` is 93 % of the 21.67 MiB. `phys_footprint` over a warmed process, steady: +21.7 MiB, i.e. the textures and
nothing else: the Alloy figure is `F` plus the pool at Alloy's window size. (a) The pool textures were already sized
to the record's region (halved per level); there was nothing to crop. The memory is `F`, and the textures of an idle
window, which are kept.

Also seen, not acted on: the first draw of the Gaussian/blurred-quad pipelines in a process adds a one-time
+54 MiB `phys_footprint` (+10 MiB more for the lens variant) in a debug test process, independent of any size and
unchanged by `releaseAll`; `BackdropPipelines.init` itself adds 0.4 MiB. Alloy's 5 MiB total cannot contain it, so it is
probably the debug build or the test harness; not measured in release (a release build of the test target did not
finish in the time available).

**Step 2, idle release.** `MetalWindowRenderer` now owns a `BackdropFrameState` (it passed `nil`, so every window on a
`Renderer` shared the renderer's one: with two backdrop windows each frame dropped the other's pool) and frees it
after `idleReleaseDelay` = 1 s without a finished frame (one watcher task, started by a frame that leaves textures; the
next backdrop frame makes them again).

**Step 3, active memory.** (a) pool: already region-sized. (b) last segment into the drawable: saves the copy pass but
not `F`. (c) region-sized `F`: done as one target per record (a union box of two distant regions is nearly the window),
the scene drawn into the drawable and, shifted by the viewport origin, into each region target still to be blurred;
the lens's sharp copy is the region target. (d) `setPurgeableState`: not tried; the idle release is the stronger form.
Conditions and cost: `BB-U` items 2-4.

**Numbers** (same probe, 2800x1800, debug, two runs each, steady state; footprint noise about +-5 MiB between runs,
the texture sizes exact):

| | frame target (before) | region targets (after) |
|---|---|---|
| resident textures, active | 21.67 MiB | 2.39 MiB |
| `phys_footprint` over warm baseline, active | +21.7 MiB | +8.4 MiB |
| `phys_footprint` after the idle release | +0 (noise) | +0 (noise) |
| steady frame (encode + wait) | 1.25 ms | 1.10-1.30 ms |
| first frame after an idle release (avg of 30) | 1.93 ms | 1.29 ms |

The +8.4 MiB active delta in the region run is above the 2.4 MiB of textures: the remainder is not texture memory this
code holds (the lens pipeline's first use in the same process, driver heaps); at Alloy's window size the saving is
the whole of `F`.

**Tests** (`Tests/MetalUIRenderTests/BackdropMemoryTests.swift`, each shown to fail by mutation, `BB-U` Pins):
region pixels equal frame-target pixels byte for byte; region frames hold regions only and steady frames make no
texture; the two guards; the window idle release, shared-state and continuous-frame cases.

**Open.** SDL (`SDLBridge.c`) keeps the frame target and has no idle release (`BB-U` item 8). A cost-based choice
between the paths (instead of the run and area limits) if a scene turns up that the limits get wrong.
