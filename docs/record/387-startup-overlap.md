# 387: Metal setup overlaps AppKit's startup (`FP-V`)

Class `M`; no divergence. Branch `perf/startup-overlap`, base master `e692f2b2`.

## Before

`App()` took about 58 ms on the main thread: `NSApplication.shared` 47-50 ms (forced late, by `AppKitPlatform.setMenuBar`), `MTLCreateSystemDefaultDevice` 3-4 ms, `ShaderLibrary.make` about 1.2 ms, the four eager pipelines about 2 ms more.

## Change

- `Renderer.makePipelines(device:)` (package, `nonisolated`) returns a `RendererPipelines` (`@unchecked Sendable`: the library and the rect, continuous-rect, glyph and image pipeline states). `Renderer.init(device:pipelines:)` takes it; `Renderer.init(device:)` is now both calls. `Renderer.pixelFormat` became `nonisolated`.
- `App.init()` runs device creation and `makePipelines` on a global `.userInitiated` job while the main thread calls `AppKitPlatform.prepareApplication()` (`_ = NSApplication.shared`, nothing more), then joins on a `DispatchGroup`. `App.init(device:textSystem:)` does the same with only `makePipelines` in the job. Both continue through the package `App.init(device:pipelines:textSystem:)`, which holds the old body.
- Errors cross the join as a `Result`: nil device throws `AppError.noMetalDevice`.

## Measured

Release probe, warm, two alternating rounds of 8 runs each (first run of each round dropped), medians:

| | `App()` | `openWindow` | first Task (ms since main) |
|---|---|---|---|
| master, round 1 / 2 | 57.6 / 59.1 | 26.6 / 26.7 | 121.8 / 124.0 |
| overlap, round 1 / 2 | 50.9 / 52.3 | 27.8 / 27.1 | 116.2 / 118.1 |

About 6.7 ms off `App()` and the first Task; `openWindow` unchanged.

## Tests

`StartupOverlapTests`: `pipelinesBuildOffTheMainThreadAndDrawLikeAPlainRenderer` (build in `Task.detached`, same pixels as `Renderer(device:)`; mutation: the rect pipeline built from the glyph shaders, red) and `anAppBuiltWithTheOverlapHasAWorkingAppKitPlatform` (`App()` yields an `AppKitPlatform`, the default menu bar and a window; mutation: `installMenuBar()` removed from the shared init, red). The thread assertion itself has no mutation check. Full root run: 7042 tests in 79 suites, green.
