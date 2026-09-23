# 38 — MetalUI without AppKit or Metal, 2026-09-23

Branch `feat/metalui-portable`, from `feat/sdl-platform` (PR #20, record
§37). Spec: `docs/superpowers/specs/2026-09-23-metalui-portable-design.md`,
rulings `XP-A`…`XP-C` (next `XP-D`). Roadmap item 9.

## What changed

- `MetalUIPrimitives` (new, portable): the shader-struct bridge, moved from
  `MetalUIRender` (re-exported there).
- `MetalUI`, `MetalUIDemoContent`: portable targets and products;
  Apple-only dependencies appended on macOS.
- `MetalUI` sources: CoreText paths under `#if canImport(MetalUIText)`; an
  empty `ShapingCache` off Apple; `Window` imports Foundation (it had
  `Thread` through `import Metal`); `App.init(platform:textSystem:)`.
- `MetalUICrossPlatformTests` (new, portable): the demo frame, pinned.

## Measured

| Where | Result |
|---|---|
| macOS | builds, 0 warnings; the new target's 3 tests pass |
| Linux container (`swift:6.4-noble`, aarch64) | `MetalUI` and `MetalUIDemoContent` build, 0 warnings; 486 + 22 + **3** pass — the demo frame equal to macOS at scale 1 and 2 |

## Mutations

| # | Mutant | Result |
|---|---|---|
| X1 | portable text height + 1 pt | `theDemoFrameMatchesTheValuesRecordedOnMacOS` (macOS) |
| X2 | the CoreText `textMeasure` wrapper unguarded | Linux build fails: `cannot find type 'ResolvedFont'` |

## Counts

Root: 1686 + 3 (one gated recorder) = **1689**; see `CLAUDE.md`.
