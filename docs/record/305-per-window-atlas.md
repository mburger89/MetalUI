# 305 — One atlas texture per window (`PW-A`)

Branch `fix/per-window-atlas` from `9639c33f`. Reported by Alloy: with two windows open (Settings via
`App.openWindow`), text in the other window rendered as garbled glyph fragments.

**Cause.** `App` makes one `Renderer`; every window wraps it in its own `MetalWindowRenderer`. Each `Window` owns
its own `GlyphAtlas`, whose `AtlasSlot`s are UVs into that atlas only, but `Renderer` kept a single `atlasTexture`
and `atlasTextureWasEncoded`. Window B's `upload` replaced the texture window A sampled; with nothing dirty on its
next frame A kept drawing its own UVs against B's atlas.

**Fix.** `WindowTextureState` (package class in `Renderer.swift`) holds a window's atlas texture, its `wasEncoded`
flag (the in-flight-frame invariant, unchanged: a texture is written only before it is first bound) and its image
texture cache. Each `MetalWindowRenderer` owns one (`atlasState`) and passes it to `Renderer.upload(_:into:)`,
`encode(..., atlasState:)` and `encodeSurfaceText(..., atlasState:)`; the renderer points a scratch `activeTextures`
at it for the (synchronous, main-actor) encode. The public `upload(_:)`, `atlasTexture` and the headless paths use
the renderer's default state, so no public API changed.

**Audit of the rest of the shared `Renderer`.**
- Image texture cache: the same bug in a weaker form. `prepareImageTextures` drops every cached texture the current
  scene does not reference, so two windows showing different images released and re-uploaded each other's every
  frame (correct pixels, wasted upload). Moved into the per-window state.
- Backdrop/blur/group pools: already per window (`MetalWindowRenderer.backdropState`, `BB-C`).
- Surface (MetalView) targets: already per window (`surfaceTable`, `MV-E`).
- Pipelines, library, unit-quad and zero-transform buffers: immutable after `init`, safe to share.
- `lastBackdrop*`/`last*Passes` counters and `heldGroupTextures`: per-encode diagnostics/scratch, reset or emptied
  within one synchronous `encode`.
- SDL backend: no sharing. `SDLPlatform` makes one `SDLWindowRenderer` (own `MUIRenderer`, atlas, texture and
  surface tables) per window.

**Tests** (`GlyphABITests.swift`): `twoWindowsOnOneRendererEachSampleTheirOwnAtlas` (A, B, A with the same slot,
different glyph; A's second frame equals its first and its texture holds A's atlas) and
`twoWindowsOnOneRendererDoNotReuploadEachOthersImages`. Both go red with `MetalWindowRenderer` routed back to the
shared default state (the first on `secondA == firstA`) and green with the fix.

**Memory.** One R8 atlas texture per window instead of one shared: a 1024x1024 atlas is 1 MiB per extra window
(it grows only as that window packs glyphs). A single-window app holds exactly the one texture it did before; the
image cache is per window, so an image shown in two windows is uploaded twice (4 bytes a pixel each).
