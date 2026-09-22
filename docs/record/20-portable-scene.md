# 20 — Portable scene (`MetalUIScene`), 2026-09-22

Spec and rulings: `docs/superpowers/specs/2026-09-22-portable-scene-design.md`
(`PS-A`…`PS-G`). Branch `feat/portable-scene` from `772c3ed`.

## Why

`Experiments/SDLGPU` (branch `codex/sdl-gpu-experiment`) replays a finalized
`Scene` and the glyph atlas through SDL3 GPU at parity with the production
Metal renderer on Metal, Vulkan (MoltenVK, Mesa llvmpipe on Linux x86_64 and
aarch64) and Direct3D 12 (WARP on Windows CI). It had to copy the bytes out
through a fixture format because `Scene` lived in `MetalUIRender` (imports
Metal) and `GlyphAtlas` in `MetalUIText` (imports CoreText).

## What was measured before moving

- `Scene.swift` imported only `MetalUIShaderTypes`.
- `Atlas.swift` imported CoreText and Foundation but used neither beyond
  `CGGlyph` (a `UInt16` typealias) and `FontKey`.
- `FontKey` stores `String`/`Double`s; only `init(resolved: CTFont)` reads
  CoreText. `FontMetrics`, in the same file, stays in `MetalUIText`.
- `GlyphImage` is a plain value whose only producer, `GlyphRaster`, is
  CoreText.
- No typecheck guard pinned `FontKey`'s missing memberwise init or
  `GlyphImage`'s internal init — so widening either to `package` would have
  been silent without new guards.
- Linux (`swift:6.4-noble`) resolves the root manifest and builds
  `MetalUIShaderTypes` (its header symlink is tracked).

## What changed

- New target `MetalUIScene` → `MetalUIShaderTypes` only. Moved:
  `Scene.swift` (git mv), `Atlas.swift` (git mv; imports dropped,
  `GlyphKey.glyph` spelled `UInt16`), the `FontKey` struct (new file; its
  `init(resolved:)` stays in `MetalUIText/FontKey.swift` as an extension that
  calls `package init(resolvedPostScriptName:size:variations:matrix:)`), and
  `GlyphImage` (extracted from `GlyphRaster.swift`; `package init`,
  `package static let empty`). `precomputedHash` and the nested
  `VariationCoordinate`/`Matrix` inits are `package`.
- `MetalUIText/SceneReexport.swift` and `MetalUIRender/ShaderTypesBridge.swift`
  `@_exported import MetalUIScene`. No source file outside the moved ones and
  two tests changed.
- Two tests used `DrawRun`/`AtlasSlot` implicit memberwise inits through
  `@testable import MetalUIRender`; they now also `@testable import
  MetalUIScene` (and `MetalUIRenderTests` depends on it).
- Guards: `Tests/MetalUITests/SceneBoundaryCompileGuards.swift`,
  `anExternalModuleCannotSpellAFontKeyByHand` and
  `anExternalModuleCannotMakeAGlyphImage` (plain `import MetalUIText`,
  `typecheckFile`, control + negative).
- Swift workflow: `scene-linux` job, `swift build --target MetalUIScene` in
  `swift:6.4-noble`.

## Mutations

| Mutant | Reddened |
|---|---|
| `FontKey`'s package init (and its nested inits) → `public` | `anExternalModuleCannotSpellAFontKeyByHand` only |
| `GlyphImage`'s package init → `public` | `anExternalModuleCannotMakeAGlyphImage` only |
| `import CoreText` atop `MetalUIScene/Atlas.swift`, built on Linux | `no such module 'CoreText'` |

The `FontKey` negative is refused as "extra arguments at positions #1–#4":
with the `package` init invisible the compiler matches `init(resolved:)`. The
guard accepts that wording or "inaccessible".

## Counts

After `swift package clean`, `--build-system native`: 0 `error:`, 0
`warning:` (SwiftPM's deprecation notice aside); **1411 tests** (1409 + the two
guards), **97 goldens**, **73 guards** (74 `canTypecheck` hits, one a comment
in `UnitSafetyTests`); the `FR-J` line present, so guards ran.

## Open

- The SDL experiment still round-trips through its fixture format; it can now
  depend on `MetalUIScene` directly.
- Shaping and rasterization remain CoreText-only; `MetalUIRender` remains
  Metal-only. No renderer protocol yet (spec, "Out of scope").
