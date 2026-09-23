# MetalUI without AppKit or Metal — design

**Status: implemented** on `feat/metalui-portable` (record §39; written as §38, renumbered when stage 6a took §38); roadmap
item 9 of `plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:**
`XP-` (`XP-A`…`XP-C`, next `XP-D`; rulings here — `MP-` is the
measure-performance milestone's).

## Rulings

### XP-A — `MetalUI` is declared on every platform

The manifest's portable list (`PC-A`) now holds `MetalUI` and
`MetalUIDemoContent`, both library products. `MetalUI`'s dependencies are
`MetalUICore`, `MetalUILayout`, `MetalUITextSystem`, `MetalUIPlatform` and
`MetalUIPrimitives` everywhere, plus `MetalUIText`, `MetalUIRender` and
`MetalUIAppKit` on macOS (a manifest-level list, since those targets do not
exist off macOS). `MetalUIPrimitives` is new: `ShaderTypesBridge.swift` —
the `MetalUICore` → `MUIRect`/`MUIGlyph` conversions `Frame` paints with —
moved out of `MetalUIRender`, which re-exports it; its six internal
initialisers became `package`, since the render tests reached them through
`@testable import MetalUIRender`.

Inside `MetalUI`, CoreText is behind `#if canImport(MetalUIText)`: the
`PlacedGlyph` `draw`s, the CoreText test wrappers of `textMeasure` and
`proposalTextMeasurement`, and the default text system. `Frame` and
`Window` keep their `shapingCache:` parameter on every platform — off
Apple an empty `ShapingCache` stands in for it, because Swift has no `#if`
inside a parameter list — and read nothing from it there.

### XP-B — `App` takes any platform; off Apple the text system is required

`App.init(platform:textSystem:)` exists everywhere (on macOS it also runs
an app on `SDLPlatform`). Off Apple `textSystem` is non-optional; a `Frame`
or `Window` made without one there traps with the reason. On macOS
`App()`/`App(device:)` are unchanged; `App.device` became optional (`nil`
for an app on another platform). Closing the last window terminates through
AppKit only for the AppKit platform; SDL's `run()` returns on its own.

### XP-C — The whole frame, pinned across platforms

`MetalUICrossPlatformTests` (a portable test target) renders the demo's own
`demoContent()` through a `Frame` with `PortableTextSystem` over Noto Sans
at 920×560, scale 1 and 2, and hashes every primitive **field** (never raw
struct bytes, whose padding is undefined), the draw list and the atlas
coverage. Recorded on macOS: 518 rects, 15,710 glyphs, 1,008 runs.
**Measured equal on Linux aarch64** (`swift:6.4-noble`) — layout, both
text engines, line breaking and paint agree to the bit; CI measures Linux
x86_64 and Windows.
