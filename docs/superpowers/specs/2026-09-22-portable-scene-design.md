# Portable scene — design

**Status:** approved 2026-09-22 (one target, named `MetalUIScene`).
**Ruling prefix:** `PS-` (lettered; next `PS-H`).
**Motivation:** `Experiments/SDLGPU` replays a finalized `Scene` and the glyph
atlas through SDL3 GPU at parity on Metal, Vulkan (MoltenVK, llvmpipe) and
Direct3D 12 (WARP), but only by copying bytes out through a fixture, because
the production types live in modules that import Metal (`MetalUIRender`) and
CoreText (`MetalUIText`). This step gives them a home that builds anywhere.

## What moves

| Type(s) | From | Why it can move |
|---|---|---|
| `Scene`, `DrawRun`, `PrimitiveKind` | `MetalUIRender/Scene.swift` | already imports only `MetalUIShaderTypes` |
| `GlyphAtlas`, `GlyphKey`, `AtlasSlot`, `PackedGlyph` | `MetalUIText/Atlas.swift` | arithmetic over `[UInt8]`; CoreText only via `CGGlyph` and `FontKey` |
| `GlyphImage` | `MetalUIText/GlyphRaster.swift` | a plain value; only its producer is CoreText |
| `FontKey` (struct, `==`, `hash`) | `MetalUIText/FontKey.swift` | stores `String`/`Double`s; only `init(resolved: CTFont)` reads CoreText |

Nothing else moves. Shaping (`Shaper`, `ShapedText`, `ShapingCache`), font
resolution and rasterization (`FontResolver`, `GlyphRaster`) stay in
`MetalUIText`; the renderer stays in `MetalUIRender`.

## Rulings

- **PS-A — one target, `MetalUIScene`, depending only on `MetalUIShaderTypes`.**
  It imports no Foundation, CoreText, CoreGraphics or Metal. It holds what a
  GPU backend consumes per frame: the scene and the atlas it samples.
- **PS-B — source compatibility by re-export.** `MetalUIText` and
  `MetalUIRender` each `@_exported import MetalUIScene`, the precedent being
  `MetalUIRender`'s `@_exported import MetalUIShaderTypes`. Every existing
  `import MetalUIText` / `MetalUIRender` / `MetalUI` keeps compiling.
- **PS-C — glyph ids are `UInt16`.** `GlyphKey.glyph` was `CGGlyph`, a
  typealias of `UInt16`: the same type, so no caller changes.
- **PS-D — `FontKey` keeps its one construction path.** The struct gains a
  `package init(resolvedPostScriptName:size:variations:matrix:)` that computes
  and stores the hash exactly as before; `init(resolved: CTFont)` stays in
  `MetalUIText` as an extension that reads the four components and calls it.
  The rule that there is no memberwise initializer (so no caller spells a
  *requested* name into the key) now holds outside the package: a plain-import
  typecheck guard proves an external module cannot call the `package` init.
  Inside the package, the parameter label names the obligation.
- **PS-E — `GlyphImage`'s initializer becomes `package`.** It was internal so
  only `GlyphRaster` could build one; `GlyphRaster` stays in `MetalUIText`. A
  plain-import guard proves an external module still cannot.
- **PS-F — no behaviour change.** No stored property, case, hash input or
  equality changes. Tests stay in their current targets (their imports reach
  the moved types through PS-B's re-exports). Counts: 1409 tests, 97 goldens,
  71 guards + PS-D's and PS-E's, 0 errors, 0 warnings beyond SwiftPM's notice.
- **PS-G — Linux proves the boundary.** A CI job builds `MetalUIScene` from the
  root package on Linux (`swift build --target MetalUIScene`). A reintroduced
  Apple import fails to compile there; macOS cannot see that.

## Out of scope

A renderer protocol; a non-CoreText shaper or rasterizer (FreeType); moving
`MetalUIRender`'s encode path; replacing the experiment's fixture copy with
`MetalUIScene` (a follow-up once this lands).

## Verification

- Before/after: `swift package clean`, `swift build --build-system native
  --build-tests`, unfiltered `swift test --build-system native --no-parallel`;
  read printed counts, confirm the `FR-J` guard line.
- `grep -E "^import" Sources/MetalUIScene/*.swift` lists only
  `MetalUIShaderTypes`.
- Each new guard is shown to redden by mutation (widen the init to `public`).
- The Linux job is shown able to fail: an `import CoreText` mutant in
  `MetalUIScene`, built in the Linux container (`swift build --target
  MetalUIScene`), must not compile. (`import Foundation` is no mutant: Linux
  has swift-corelibs-foundation.)
