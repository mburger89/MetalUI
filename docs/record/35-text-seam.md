# 35 — Text seam, 2026-09-23

Branch `feat/text-seam`, from `feat/portable-core-layout` (PR #16, record
§34). Spec: `docs/superpowers/specs/2026-09-23-text-seam-design.md`, rulings
`TS-A`…`TS-D` (next `TS-E`). Roadmap item 6.

## What changed

- New target `MetalUITextSystem` (portable; product too): `TextSystem`,
  `TextMeasurement`, `TextGlyph`.
- `CoreTextTextSystem` in `MetalUIText`; `PortableTextSystem` in
  `MetalUIPortableText`, which now also imports `MetalUITextSystem`.
- `Frame.textSystem` (default: CoreText over the frame's cache); `Text`,
  `ProposalText`, `Frame.draw` and the frame bracket go through it.
- `Window(…textSystem:)`, `App(device:textSystem:)`.
- `MetalUITests` depends on `MetalUIPortableText` for the seam oracle.

## Measured

- The 1681-test suite passes unchanged with every `Text` on the seam.
- `TextSystemSeamTests`: CoreText and portable sprites identical for the
  legacy tree at scale 1 and 2 (>60 sprites each) and the proposal tree
  (>40).

## Mutations

Filter `TextSystemSeamTests|ShapingCache|TextTests|GlyphEmitter`:

| # | Mutant | Result |
|---|---|---|
| S1 | `Text` paints through CoreText whatever the frame's system | **traps**: `PortableTextSystem … was not resolved by this text system` — the frame's system is asked to rasterize a CoreText key |
| S2 | `Text` lays out through CoreText whatever the frame's system | `aPortableFrameNeverShapesThroughCoreText` |
| S3 | portable total height spaced by ascent | `proposalTextDrawsTheSameSpritesThroughEitherSystem`, `theCoreTextAndPortableSystemsDrawTheSameSprites` |
| S4 | the frame brackets its `ShapingCache`, not its text system | **traps**: `ShapingCache.endFrame called without a matching beginFrame` |
| S5 | `ProposalText` paints through CoreText | **green at first** — the never-shapes test rendered only legacy `Text`; extended with a `ProposalText` tree, S5 now traps as S1 does |

Unpinned: `PortableTextSystem`'s memo sweep (dropping every entry at each
`endFrame` changes no output, only work).

## Counts

1681 + 5 = **1686**; see `CLAUDE.md`.
