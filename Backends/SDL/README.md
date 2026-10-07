# MetalUI SDL backend

The backend's sources live here; its library targets — `CSDL`, `CAccessKit`,
`SDLBridge`, `MetalUISDL` — are declared by MetalUI's **root** package behind
its `SDL` and `AccessKit` traits (ruling PX-H), so an application depending on
MetalUI by URL reaches them (`docs/getting-started.md`). Neither trait is on by
default: the root package never needs SDL3 installed. This directory's own
package holds the tools and tests and depends on the root by path with both
traits on. It needs SDL3 (3.4 or later: Homebrew `sdl3`, a source build
installed to `/usr` as `linux/Dockerfile` does, or the prebuilt VC package on
Windows — see `.github/workflows/sdl-gpu-linux.yml`) and AccessKit's C bindings
(ruling AX-A), fetched by `scripts/fetch-accesskit.py`. No pkg-config (PX-I).

- **`MetalUISDL`** — `SDLWindowRenderer`, the `WindowRenderer` (ruling RS-D)
  that draws MetalUI frames with SDL3's GPU API: Metal on macOS, Vulkan on
  Linux, Direct3D 12 on Windows. Into a claimed `SDL_Window`, or offscreen. Its
  shaders are found in `MetalUISDLShaders` beside the executable, then in
  `Shaders/compiled` here (PX-P).
- **`MetalUISDL`** also holds `SDLPlatform`/`SDLWindow` (ruling SP-A), the
  SDL3 `Platform`: windows, input with keys in AppKit's vocabulary (SP-C),
  resize, pixel density, system theme, a run loop paced by the swapchain.
  Accessibility through AccessKit (AX-B, AX-C) under the `AccessKit` trait:
  AT-SPI on Linux, UI Automation on Windows, NSAccessibility on macOS.
- `SDLBridge` — the C side: device, the two pipelines, packing the scalar
  primitive ABI into 16-byte lanes, `mui_renderer_*` for windows and
  `replay_*` for the diagnostic replay.
- `Shaders/` — `replay.hlsl` and its compiled stages (`compiled/`, checked by
  `SOURCE.sha256` in CI; regenerate with `scripts/compile-shaders.py`).
- `ReplayFixture`, `SDLReplay`, `PortableReplay` — the parity harness that
  replays scenes the Metal renderer drew (`Experiments/SDLGPU` records them).

```sh
# macOS: Homebrew's SDL3 and AccessKit's flags, one per line (PX-I item 6)
swift test $(python3 scripts/fetch-accesskit.py --print-flags)
# Linux with SDL3 and AccessKit on the default paths (the CI image): no flags
swift test
# Windows: SDL3's -Xcc -I…/-Xswiftc -L… plus what --print-flags prints
```
