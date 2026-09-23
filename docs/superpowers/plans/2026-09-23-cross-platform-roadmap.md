# Cross-platform roadmap

**Written 2026-09-23.** What remains between MetalUI today (macOS only) and a
MetalUI app running on Linux and Windows. Items are worked **one at a time, in
this order**, each on its own branch and PR with its own spec, record and
rulings; tick an item here in the PR that lands it.

## Where things stand

Portable today (imports no Apple framework, built on Linux by `scene-linux`,
pinned on Linux and Windows by `Tests/PortableTests`):

- `MetalUIScene` — `Scene`, glyph atlas, `FontKey` (`PS-`).
- `MetalUIFreeType` — glyph rasterizer (`FT-`).
- `MetalUIHarfBuzz` — shaper, one run (`SH-`).
- `MetalUIPortableText` — string → `MUIGlyph`s + atlas, one line (`PT-`).
- `Experiments/SDLGPU` — SDL3 GPU replays a `Scene` on Metal, Vulkan and
  Direct3D 12 at pixel parity with the Metal renderer, including portable
  text (frame 4).

Portable in source but **not built off macOS by CI**: `MetalUICore`,
`MetalUILayout` (both import nothing).

Apple-bound:

| Target | Bound to | What uses it |
|---|---|---|
| `MetalUIText` | CoreText, Foundation | `Text` measurement and drawing via `Shaper`, `FontResolver`, `ResolvedFont`, `unbreakableRuns` (`CFStringTokenizer`), `GlyphRaster` |
| `MetalUIRender` | Metal, simd | `Renderer`, `RenderSurface`, the MSL shader library |
| `MetalUIPlatform` | AppKit, QuartzCore, Metal | `PlatformWindow` (window, input, display link, appearance, accessibility) — protocol portable, only implementation AppKit |
| `MetalUI` | AppKit, Metal (`App.swift`, `Window.swift`) and all three above | `App` builds `AppKitPlatform` and a Metal device unguarded; `Window` owns a `Renderer` |

## The list

### Text

1. [ ] **Line breaking** (UAX #14, libunibreak) — `PortableText.lines(_:font:
   wrappingAt:)` with `Shaper.shape(wrappingAt:)`'s contract, oracle-checked
   against CoreText. *In progress: `feat/portable-linebreak`, spec
   `specs/2026-09-23-portable-line-breaking-design.md` (`LB-`).*
2. [ ] **Font metrics and multi-line emission** — ascent, descent, leading and
   `lineHeight` from the font's own tables (FreeType), measured against
   `FontMetrics`; `emitLines` (`LB-F`).
3. [ ] **Min- and max-content** — the portable counterpart of
   `unbreakableRuns(of:)` (TX-F: `CFStringTokenizer`'s longest word) and of
   max-content (TX-K: one line per hard break), so a portable `Text` can be
   measured by the layout engines.
4. [ ] **Font resolution** — a portable `FontResolver`: family/weight →
   font file. Bundled fonts first; system discovery (fontconfig on Linux,
   DirectWrite on Windows) after.

### The seams inside `MetalUI`

5. [ ] **Core and layout build off macOS** — add `MetalUICore` and
   `MetalUILayout` to `scene-linux` (and a Windows build), and run their
   tests there if they can.
6. [ ] **Text seam** — `Text`/`ProposalText` measure and draw through a
   text-system protocol with two implementations: today's CoreText path and
   `PortableText`. Selected once per app, not per element.
7. [ ] **Render seam** — `Window` renders through a backend protocol; the
   Metal `Renderer` is one implementation, and the SDL GPU replayer is
   promoted out of `Experiments/` into a real target as the other, with its
   HLSL shaders and compiled stages.
8. [ ] **Platform: SDL3** — a `PlatformWindow`/`Platform` over SDL3: window,
   resize, scale factor, input events, frame ticks, appearance, close.
   `publishAccessibilityTree` publishes nothing, recorded as a divergence
   (AB-R forbids a default, so the stub is explicit).
9. [ ] **`MetalUI` builds without AppKit/Metal** — `App` chooses its platform
   by `#if canImport(AppKit)`; Apple-only dependencies become
   `.when(platforms:)`; CI builds `MetalUI` on Linux and Windows.

### End to end

10. [ ] **The demo on Linux and Windows** — `MetalUIDemo` through SDL3, text
    through `PortableText`; CI captures a frame on llvmpipe and WARP and
    compares it with the macOS Metal frame of the same tree.

### After the demo runs

11. [ ] **Font fallback** — a glyph missing from the primary face comes from
    a fallback face (the CJK line in SDL frames 0–3 is CoreText's fallback;
    frame 4 avoids it).
12. [ ] **Bidi and script itemization** — UAX #9 across runs and runs split
    by script; today one call is one direction.
13. [ ] **Accessibility off Apple** — AT-SPI (Linux) and UI Automation
    (Windows) behind `publishAccessibilityTree`.
14. [ ] **Text input** — IME composition and clipboard through SDL3.

Not on this list: iOS (a UIKit `PlatformWindow`, and the `.touch` input the
spec asks for) is Apple-platform work with its own spec; the CLAUDE.md header
records it as unmet.
