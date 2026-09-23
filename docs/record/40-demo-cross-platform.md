# 40 — The demo on Linux and Windows, 2026-09-23

Branch `feat/demo-cross-platform`, from `feat/metalui-portable` (PR #21,
record §39). Spec: `docs/superpowers/specs/2026-09-23-demo-cross-platform-design.md`,
rulings `DC-A`…`DC-C` (next `DC-D`). Roadmap item 10.

## What changed

- `MetalUI.renderFrame` (`DC-A`).
- `Replay` frame 5 — the demo tree (`DC-B`).
- `Backends/SDL`: `DemoCapture` and `MetalUISDLDemo` executables;
  `PortableReplay`'s control on frame 3.
- CI (`sdl-gpu-linux.yml`): six fixtures, `DemoCapture` on Linux and
  Windows, path triggers for the framework sources frame 5 depends on.

## Measured

| Where | Scene vs macOS | Pixels vs Metal |
|---|---|---|
| macOS, SDL Metal (`DemoCapture`) | byte-for-byte | 0 px |
| Linux aarch64, llvmpipe Vulkan (CI image, locally) | byte-for-byte | max Δ1 outside and inside glyphs (≤1 / ≤8) |
| Linux x86_64, Windows D3D12 | CI | CI |

Also in the Linux image: `Backends/SDL`'s 21 + 9 tests pass (the
`SDL_Quit` fix from record §36 holding), and `PortableReplay` over six
fixtures passes once its control moved to frame 3 — on the last fixture (the
demo) the order mutation moved 0 pixels, a broken instrument caught by its
own guard.

## Open

- The interactive `MetalUISDLDemo` window is unseen (locked screen).
