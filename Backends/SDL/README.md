# MetalUI SDL backend

A separate package so the root package never needs SDL3 installed. Depends on
the root's portable products (`MetalUIScene`, `MetalUIPlatform`,
`MetalUIPortableText`) and on SDL3 (Homebrew `sdl3`, apt `libsdl3-dev`, or the
prebuilt VC package on Windows — see `.github/workflows/sdl-gpu-linux.yml`)
and on AccessKit's C bindings (ruling AX-A), fetched by
`scripts/fetch-accesskit.py`.

- **`MetalUISDL`** — `SDLWindowRenderer`, the `WindowRenderer` (ruling RS-D)
  that draws MetalUI frames with SDL3's GPU API: Metal on macOS, Vulkan on
  Linux, Direct3D 12 on Windows. Into a claimed `SDL_Window`, or offscreen.
- **`MetalUISDL`** also holds `SDLPlatform`/`SDLWindow` (ruling SP-A), the
  SDL3 `Platform`: windows, input with keys in AppKit's vocabulary (SP-C),
  resize, pixel density, system theme, a run loop paced by the swapchain.
  Accessibility through AccessKit (AX-B, AX-C): AT-SPI on Linux, UI
  Automation on Windows, NSAccessibility on macOS.
- `SDLBridge` — the C side: device, the two pipelines, packing the scalar
  primitive ABI into 16-byte lanes, `mui_renderer_*` for windows and
  `replay_*` for the diagnostic replay.
- `Shaders/` — `replay.hlsl` and its compiled stages (`compiled/`, checked by
  `SOURCE.sha256` in CI; regenerate with `scripts/compile-shaders.py`).
- `ReplayFixture`, `SDLReplay`, `PortableReplay` — the parity harness that
  replays scenes the Metal renderer drew (`Experiments/SDLGPU` records them).

```sh
python3 scripts/fetch-accesskit.py            # once; prints the PKG_CONFIG_PATH to use
export PKG_CONFIG_PATH=$PWD/.accesskit        # Linux, macOS (Windows: the -Xcc/-Xswiftc flags it prints)
swift test   # the window renderer against the replay path; the platform; accessibility; the fixture format
```
