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
- `MetalUIPortableText` — string → `MUIGlyph`s + atlas (`PT-`), and display
  lines at a width (`LB-`, item 1), line metrics and wrapped emission
  (item 2).
- `Backends/SDL` — `SDLWindowRenderer`, SDL3 GPU drawing a `Scene` on Metal,
  Vulkan and Direct3D 12 at pixel parity with the Metal renderer (item 7);
  `Experiments/SDLGPU` records the parity fixtures, including portable text
  (frame 4).

`MetalUICore` and `MetalUILayout` are built and tested on Linux and
Windows CI (item 5).

Apple-bound:

| Target | Bound to | What uses it |
|---|---|---|
| `MetalUIText` | CoreText, Foundation | `Text` measurement and drawing via `Shaper`, `FontResolver`, `ResolvedFont`, `unbreakableRuns` (`CFStringTokenizer`), `GlyphRaster` |
| `MetalUIRender` | Metal, simd | `Renderer`, `RenderSurface`, the MSL shader library |
| `MetalUIPlatform` | AppKit, QuartzCore, Metal | `PlatformWindow` (window, input, display link, appearance, accessibility) — protocol portable, only implementation AppKit |
| `MetalUI` | AppKit, Metal (`App.swift`, `Window.swift`) and all three above | `App` builds `AppKitPlatform` and a Metal device unguarded; `Window` owns a `Renderer` |

## The list

### Text

1. [x] **Line breaking** (UAX #14, libunibreak) — `PortableText.lines(_:font:
   wrappingAt:)` with `Shaper.shape(wrappingAt:)`'s contract, equal to
   CoreText over 13,464 cases. `feat/portable-linebreak`, spec
   `specs/2026-09-23-portable-line-breaking-design.md` (`LB-`), record §30.
2. [x] **Font metrics and multi-line emission** — `PortableFont.metrics` from
   `hhea`, exact against `FontMetrics` on TrueType faces; `emitLines`, equal
   in placement to `placedGlyphs` over 26,928 cases. `feat/portable-lines-emit`,
   spec `specs/2026-09-23-portable-lines-emit-design.md` (`LB-F`, `LB-H`…`LB-K`),
   record §31.
3. [x] **Min- and max-content** — `PortableText.unbreakableRuns`,
   `minContentWidth`, `maxContentWidth`, equal to the Apple path; break
   opportunities now `"en-strict"`, equal to `CFStringTokenizer` over 4,418
   class pairs. `feat/portable-content-sizes`, spec
   `specs/2026-09-23-portable-content-sizes-design.md` (`LB-L`…`LB-O`),
   record §32.
4. [x] **Font resolution** — `PortableFontResolver`: registered font files
   matched by name with CoreText's rules, `nil`/unmatched to a default face.
   `feat/portable-font-resolver`, spec
   `specs/2026-09-23-portable-font-resolver-design.md` (`FN-`), record §33.
   System discovery moved to 8b (it needs a file system).

### The seams inside `MetalUI`

5. [x] **Core and layout build off macOS** — the root package declares its
   Apple-bound targets on macOS only; Linux and Windows CI build every
   portable target and run the Core and Layout suites (486 + 22 on Linux).
   `feat/portable-core-layout`, spec
   `specs/2026-09-23-portable-core-layout-design.md` (`PC-`), record §34.
6. [x] **Text seam** — `TextSystem` (`MetalUITextSystem`), with
   `CoreTextTextSystem` and `PortableTextSystem`; `Text`/`ProposalText` draw
   identical sprites through either. `feat/text-seam`, spec
   `specs/2026-09-23-text-seam-design.md` (`TS-`), record §35.
7. [x] **Render seam** — `WindowRenderer` (portable `MetalUIPlatform`);
   `MetalWindowRenderer`; AppKit in `MetalUIAppKit`; the SDL replayer
   promoted to `Backends/SDL` with `SDLWindowRenderer`. `feat/render-seam`,
   spec `specs/2026-09-23-render-seam-design.md` (`RS-`), record §36.
8. [x] **Platform: SDL3** — `SDLPlatform`/`SDLWindow` in `Backends/SDL`:
   windows, input (keys in AppKit's vocabulary), resize, scale, frame ticks,
   theme, close; accessibility an explicit no-op. `feat/sdl-platform`, spec
   `specs/2026-09-23-sdl-platform-design.md` (`SP-`), record §37.
   8b. [ ] **System font discovery** — find installed fonts (fontconfig on
   Linux; the Fonts directory or DirectWrite on Windows) and register them
   with `PortableFontResolver`, choosing the platform's default face for
   `family: nil`.
9. [x] **`MetalUI` builds without AppKit/Metal** — declared everywhere,
   Apple dependencies appended on macOS; `App(platform:textSystem:)`; the
   demo's whole frame pinned across platforms and equal on Linux.
   `feat/metalui-portable`, spec `specs/2026-09-23-metalui-portable-design.md`
   (`XP-`), record §38.

### End to end

10. [x] **The demo on Linux and Windows** — `MetalUISDLDemo`; `DemoCapture`
    rebuilds the demo natively and matches macOS's Metal frame (scene
    byte-for-byte, pixels within parity) on llvmpipe and WARP.
    `feat/demo-cross-platform`, spec
    `specs/2026-09-23-demo-cross-platform-design.md` (`DC-`), record §39.

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
