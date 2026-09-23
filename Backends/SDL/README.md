# MetalUI SDL backend

A separate package so the root package never needs SDL3 installed. Depends on
the root's portable products (`MetalUIScene`, `MetalUIPlatform`,
`MetalUIPortableText`) and on SDL3 (Homebrew `sdl3`, apt `libsdl3-dev`, or the
prebuilt VC package on Windows — see `.github/workflows/sdl-gpu-linux.yml`).

- **`MetalUISDL`** — `SDLWindowRenderer`, the `WindowRenderer` (ruling RS-D)
  that draws MetalUI frames with SDL3's GPU API: Metal on macOS, Vulkan on
  Linux, Direct3D 12 on Windows. Into a claimed `SDL_Window`, or offscreen.
- `SDLBridge` — the C side: device, the two pipelines, packing the scalar
  primitive ABI into 16-byte lanes, `mui_renderer_*` for windows and
  `replay_*` for the diagnostic replay.
- `Shaders/` — `replay.hlsl` and its compiled stages (`compiled/`, checked by
  `SOURCE.sha256` in CI; regenerate with `scripts/compile-shaders.py`).
- `ReplayFixture`, `SDLReplay`, `PortableReplay` — the parity harness that
  replays scenes the Metal renderer drew (`Experiments/SDLGPU` records them).

```sh
swift test   # the window renderer against the replay path; the fixture format
```
