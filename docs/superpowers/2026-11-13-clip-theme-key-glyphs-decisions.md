# Theme-key glyph colours under a clip - decisions (prefix `CT-`)

Alloy gap G44: with `.clipShape(RoundedRectangle(cornerRadius: 10))` around the chat column, `window.scene.glyphs` kept its count but lost the syntax colours, and `fenceHighlighterFollowsTheTheme` and six `CodeBlockTests` failed. Branch `fix/clip-theme-key-glyphs` from master `1b545d3b`; record 291. Class `M` (a test-harness accessor), no divergence. Next unused: `CT-D`.

**Diagnosis (evidence).** Not a render bug. A copy of Alloy's `feat/islands` sources with the island clip added, built against this branch, drew the fence's four key-coloured glyphs inside one masked group: `scene.glyphs` 220 (the rest of the window), `scene.groupScenes.count` 1, the group's 9 glyphs carrying hues `0.6667` (the key's blue, 4 of them) and `0.6078`. The rounded island clip is per-primitive and builds no group; the code block's own rounded box crossing it does (`CM-B`). The pixels of the minimal repro are identical with and without the clip (`ClipThemeKeyGlyphPixelTests`), and a plain `Text`, an `AttributedString` run and a Markdown fence are the same colours in every wrap through `TestWindow.allGlyphs`. The colours were never lost; `scene.glyphs` is the root target's list and the group's text is in `scene.groupScenes`.

## CT-A: `TestWindow.allGlyphs`

`TestWindow.allGlyphs` is `scene.glyphs` plus, recursively, every `groupScenes` entry's glyphs (an opacity group, a blur or shadow, a masked clip). Group scenes are in the parent's coordinates (`Scene.groupScenes`), so a test that filters by bounds needs no mapping. Mask scenes (`groupMasks`: a gradient text's coverage) are not ink and are left out. `scene` keeps its meaning (the root target); a test that asks what colour or where the window's text is reads `allGlyphs`.

## CT-B: the colour is resolved before the group

Glyph colours resolve at paint (`PaintPass.resolve` against the environment theme and scheme, `CR-H`), before a group is opened; a group holds primitives with their final colours, so no stage after paint resolves a key and nothing in a mask or group changes a theme. Pinned in pixels (`ClipThemeKeyGlyphPixelTests`: blue override, no red ink, the unclipped coverage, in none, `.clipped()`, a rounded `clipShape`, an ellipse and two crossing rounded clips) and in the scene (`ClipThemeKeyGlyphTests`: the same hues and counts as the unclipped window for a `Text`, an `AttributedString` and a Markdown fence).

## CT-C: a theme or scheme change under a clip

A window theme assignment or a light/dark switch recolours the key's glyphs in every wrap, group or not (`aSchemeSwitchUnderTheClipRecolours`, `aSchemeSwitchRecoloursTheInkInEveryClip`): the retained and equatable paths already carry the theme in the environment fingerprint (`TH-A`).
