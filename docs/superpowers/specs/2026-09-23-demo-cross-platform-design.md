# The demo on Linux and Windows — design

**Status: implemented** on `feat/demo-cross-platform` (record §40; written as §39); roadmap
item 10 of `plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:**
`DC-` (`DC-A`…`DC-C`, next `DC-D`; rulings here).

## Rulings

### DC-A — `renderFrame`: one frame of a tree, headless

`MetalUI.renderFrame(_:size:scaleFactor:textSystem:atlas:theme:)` renders an
element tree into a `Scene` as a fresh window's first frame would — no
pointer, focus or animation — with no platform, window or GPU. Public, for
snapshot tests and headless capture.

### DC-B — The demo, built on each platform, checked against macOS

- `Experiments/SDLGPU`'s `Replay` records **frame 5**: `demoContent()` at
  920×560, scale 1, through `PortableTextSystem` over Noto Sans, drawn by
  the production Metal renderer (518 rects, 15,710 glyphs, 1,008 runs;
  SDL Metal live 0 px).
- `Backends/SDL`'s **`DemoCapture`** builds the same tree **natively**
  (MetalUI's layout and portable text on this platform), requires its
  primitives, draw list and atlas to be **byte-for-byte** frame 5's, then
  draws it with `SDLWindowRenderer` and requires the pixels within the replay
  parity tolerance of the Metal pixels (≤1 step outside glyph quads, ≤8
  inside). CI runs it on llvmpipe (Linux x86_64, aarch64) and D3D12/WARP.
- `PortableReplay` expects six fixtures, and its draw-order control stays on
  frame 3 (the Apple side's), since reordering the demo frame's runs moves
  nothing.

Measured locally: macOS (SDL Metal) scene equal, 0 px; **Linux aarch64
(llvmpipe Vulkan, the CI image) scene equal, max Δ1 outside and inside
glyphs** — PASS.

### DC-C — `MetalUISDLDemo`

The demo in an SDL window: `App(platform: SDLPlatform(), textSystem:
PortableTextSystem…)` with the same keymap and actions as the AppKit demo;
**Q** stops the SDL loop. Runs on macOS as well.

**Open, a human look:** the interactive window has not been seen — the
local screen was locked (screenshot black) — and nothing in CI shows one.
