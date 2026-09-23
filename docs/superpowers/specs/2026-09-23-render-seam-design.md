# Render seam — design

**Status: implemented** on `feat/render-seam` (record §36); roadmap item 7
of `plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:** `RS-`
(`RS-A`…`RS-D`, next `RS-E`; rulings here).

## Goal

`Window` drew with the Metal `Renderer` directly — a Metal command buffer, a
`RenderSurface` handed that buffer, `upload` and `encode` inline — and
`PlatformWindow.surface` made `MetalUIPlatform` import `MetalUIRender`. This
item puts a platform-neutral protocol between them, keeps the Metal renderer
as one implementation, and promotes the SDL GPU replayer to a real backend
as the other.

## Rulings

### RS-A — `WindowRenderer`, in a portable `MetalUIPlatform`

`MetalUIPlatform` now imports only `MetalUICore` and `MetalUIScene`, is
declared on every platform (`PC-A`) and is a library product.
`PlatformWindow.surface` is replaced by `renderer: any WindowRenderer`:

- `beginFrame() -> Float?` — acquire the next drawable and return its scale
  factor (the frame is built at it), or `nil`: no drawable this tick, the
  window stays dirty and retries.
- `finishFrame(scene:atlas:) -> Bool` — upload the atlas if it changed, draw,
  present; `false` means not drawn, retry.

`Window` calls nothing else; it no longer holds a `Renderer`, and
`Window.init` lost its `renderer:` argument.

### RS-B — `MetalWindowRenderer` is the old inline sequence

In `MetalUIRender` (which now depends on `MetalUIPlatform`, reversing the old
edge): a shared `Renderer` and one window's `RenderSurface` — next frame,
command buffer, atlas upload **before** encode (the first frame of text is
not blank), encode, present, commit. The test fakes wrap their
`FakeRenderSurface` in one, so every surface counter and pixel readback the
suite asserts is unchanged: 1686 pass.

### RS-C — AppKit moves to `MetalUIAppKit`

`AppKitPlatform`, `AppKitWindow`, `MetalLayerSurface` and the accessibility
bridge move to a new macOS-only target. The platform shares one `Renderer`
across windows — `App`'s (`AppKitPlatform(renderer:)`) or one made on the
first window. `AccessibilityTreeChanges` becomes `package` (the bridge reads
it across the module boundary), and the moved files spell
`MetalUIPlatform.AccessibilityRequest` in full, AppKit declaring its own.

### RS-D — `Backends/SDL`: `SDLWindowRenderer`

`Experiments/SDLGPU/Portable` moves to `Backends/SDL` (package `MetalUISDL`;
separate so the root package never requires SDL3). Its C bridge gains
`mui_renderer_*`: one SDL GPU device and the replay's two pipelines, drawing
into a claimed `SDL_Window`'s swapchain or an offscreen target, **keeping its
atlas texture between frames** (re-uploaded when the atlas is dirty or
resized) and not waiting for the GPU after a window frame. `SDLWindowRenderer`
(Swift, `MetalUISDL`) is the `WindowRenderer` over it; like the Metal one it
clears the atlas' dirty rect after a frame.

Oracle: its offscreen frame is **byte-for-byte the replay path's** frame for
the same scene — the path `PortableReplay` holds to the Metal renderer in CI
(≤1 step outside glyphs, ≤8 inside) on Metal, Vulkan and Direct3D 12 — and a
second frame with a clean atlas draws the same pixels while one after new
glyphs matches the replay again (the upload happened). CI runs these tests on
llvmpipe Vulkan and D3D12 WARP (`sdl-gpu-linux.yml`, which now builds
`Backends/SDL`); locally on SDL Metal. Experiments/SDLGPU keeps only the
Apple half (`Replay`), recording fixtures as before.

**Not here:** a window to draw into — `SDLWindowRenderer(window:)` takes an
`SDL_Window *` the SDL platform (roadmap item 8) will create.
