# 42 — Portable font fallback, 2026-09-23

Branch `feat/font-fallback`, from `feat/demo-cross-platform` (PR #22, record
§40). Written as §40 and renumbered 40→41 when stage 6a took §38, and 41→42 when stage 6b took §41. Spec: `docs/superpowers/specs/2026-09-23-font-fallback-design.md`,
rulings `FB-A`…`FB-C` (next `FB-D`). Roadmap item 11.

## What changed

- `PortableFont.fallbacks`, `PortableText.shapeCascading` (`FontFallback.swift`),
  used by every shaping path; glyphs carry their face.
- `PortableFontResolver`: the cascade (`FB-B`).
- `PortableTextSystem`: fallback faces registered under their own keys.

## Measured

First run of the oracle: **1,008 cases, 7,728 fallback glyphs, 0
differences.** The earlier suites (portable text, seam, cross-platform) pass
unchanged — no pinned value moved, since none of them registers a second face.

## Mutations

| # | Mutant | Result |
|---|---|---|
| F1 | every grapheme in the requested face | `fallbackPlacesEveryGlyphAsCoreTextsCascadeDoes`, `theTextSystemRasterizesAFallbackGlyphFromItsOwnFace` |
| F2 | one run for the whole string | same two |
| F3 | resolver sets no cascade | same two |
| F4 | text system does not register fallback faces | traps (`… was not resolved by this text system`) |
| F5 | whitespace needs a glyph too | **none** — equivalent on this corpus |

## Counts

Root 1689 + 4 (one gated measurement) = **1693** before the stage-6a merge;
**1695** (1691 + 4) after it.
