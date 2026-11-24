# 397: `CodeStyle` italic and weight (`CV-BY`, Sift G15)

Class `M` (MetalUI-only API; SwiftUI has no code highlighting), no divergence (236 live, next label 244, unchanged). Branch `feat/code-style-faces`, base master `595c474a`. Requested by Sift (its SQL editor wants comments in `.secondary` italic; Alloy will want bold keywords). The design is `docs/superpowers/specs/2026-11-23-code-style-faces-design.md`; the ruling is `CV-BY`, amending `CV-L` and `CV-M`. **Numbering:** written as 396; `fix/typetext-newline` merged as 396 first, so this is 397.

## Change

- **API** (`CodeDecorations.swift`): `CodeStyle(foreground:background:underline:italic: Bool? = nil, weight: Font.Weight? = nil)`. `nil` keeps the layer below's value, `false` and `.regular` turn the face off. No `font:` field (a family or size would break the fixed row height). The inventory-map row `code-decorations` names it.
- **Run partition**: every part is `(bytes, style, face: UInt8)` at all nine declarations (`LineStyling.foreground`, `digest(of:)`, `slice`, `splittingParts`, `buildCodeLine`, `lineLayout` and the paintedRuns scratch). `computeForeground` picks the winner of `foreground`, `italic` and `weight` independently per stretch, the highest layer that sets a field; a part splits where any of them changes. The digest mixes a face term **only when the face is not 0**.
- **`anyLayerHasFaces`** (set where `anyLayerHasUnderlines` is, and by a virtual row's style run; reset on a resync) keeps `computeForeground` from reading `italic` or `weight` and the view from building its face closure until some run sets a face.
- **Resolution** (`CodeLineCache.face(_:base:request:system:)`): the view's own `FontDescriptor` with the code's weight and slope, resolved by the text system, cached by (base `FontKey`, code, system); `faceResolutions` counts the misses. The descriptor is asked only on a miss.
- **Shaping** (`buildCodeLine`): one run per part, each in its face; a segment with a face takes its caret offsets per run (`caretOffsets` of the run's text in its own face, shifted by `laid.segments[i].minX`), and its glyphs are put back on the view font's baseline (`underlineMetrics.baselinePx`). A segment with no face takes the old single-call path, byte for byte.
- **`paintedRuns`** reports the winning face (`italic` only when true, `weight` only when not regular).
- **Test fonts**: `Tests/Fonts/NotoSans-Bold.ttf` and `NotoSans-Italic.ttf` (OFL, from the official notofonts `NotoSans-v2.015` release; URL and SHA-256 in `Tests/Fonts/SOURCES.md`), loaded only by `CodeStyleFacesTests`' own resolver, never `harnessTextSystem`.

## Deviations from the design

- **`buildCodeLine` takes a `CodeFaces` (two closures: a face code to its `FontKey`, and the view font's baseline in pixels), not `faceFonts: [FontKey]`**, and `makePlan` resolves nothing up front. A cache hit therefore resolves no face and computes no baseline; only a shaped line asks. The design's array would have resolved every code on the first faced frame.
- **Test 12 (`aVirtualRowRunCanBeItalic`) landed in T3**, not T2: a virtual line's styling is not readable from outside the module, and the useful assertion is the shaped one, which needs the faces resolver.
- **Test 4's allocation ceiling uses the existing 6.2 fixture** (1000 fixed-width rows, numbers off, here with a colour on 30 rows). On `codeText(lines: 60)` the same warm scroll frame allocates about 1050 with or without highlights (the fixture is wider per row), so that fixture says nothing about faces; `aWarmScrollFrameAllocatesTheSameAt1kAnd100kLinesAndAtAnyPosition` itself is unchanged and its 910 is kept.
- **Test 13's portable arm** also accepts Menlo (it runs there on macOS, where DejaVu, Consolas and Cascadia are absent) and is a second function, `monospacedFacesKeepOneAdvanceOnThePortableSystem`, so `.enabled(if:)` can skip it; `MetalUITests` gained `MetalUISystemFonts` and `MetalUITextSystem` as test dependencies.

## Cost evidence

- A view that sets no faces: digests and cache keys are bit-identical (`aFaceFreePartitionDigestsAsBefore` pins the digest master computes for a fixed partition as a literal, `0xA11DAC709782B74F`, also after another row gains a face); five idle frames of a colour-only view shape 0 lines, resolve 0 faces and cost 2 element requests with retention 0/1/0, as `changeBarsCostWhatNoneCost` pins; the warm-scroll allocation ceiling stays 910 (`colourOnlyHighlightsCostWhatMasterCosts`). No existing cost number moved and none was edited.
- With faces: adding italic to one row (the colour partition unchanged) shapes exactly 1 line and resolves 1 face; idle repaints shape, compute and resolve nothing; scrolling resolves each distinct code once (3 codes, 3 resolutions).

## Tests

Root 7242 to 7256 tests in 79 suites (+14), `--build-system native`, `--no-parallel`: `CodeStyleFacesTests` (12: tests 1 to 12 of the design) and `CodeStyleFacesFontsTests` (2: test 13's CoreText arm, and its portable arm, which here ran over Menlo). The full run was green except `aDirectoryScanFindsEveryFaceWithItsNamesInPathOrder`, which listed exactly three files in `Tests/Fonts`; it now lists the five (an expectation about the fixture directory, not a cost number), and passes. The demo (`swift build --product MetalUIDemo`) builds. `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

## Mutations

Each test's doc comment names its mutation; the rounds below were run on the committed code and restored (`git checkout Sources`, then `git status --short`).

| test | mutation | red |
|---|---|---|
| `aStyleCarriesItalicAndWeightAndInternsThem` | `self.italic = italic` removed from the init | itself |
| `theHighestLayerThatSetsAFaceWinsPerStretch` | the first layer to set a face keeps it (`if italic == nil { italic = i }`) | itself |
| `aFaceFreePartitionDigestsAsBefore` | the face term mixed into the digest for every part | itself |
| `paintedRunsReportTheWinningFace` | `painted.italic = true` removed from `paintedRuns` | itself (and test 2) |
| `anItalicRunShapesInTheItalicFace` | every run shaped in the view font | itself, 9 and 12 |
| `aBoldRunKeepsCaretHitAndSelectionOnItsShapedAdvances` | the per-run caret offsets taken from the view font | itself |
| `aFacedLineSitsOnTheViewFacesBaseline` | the baseline shift multiplied by 0 | itself |
| `aFamilyWithoutAnItalicKeepsItsUprightFace` | italic glyphs shifted 2 px (a faked slant) | itself |
| `aVirtualRowRunCanBeItalic` | `resolveVirtualGroup` gives every part face 0 | itself |
| `colourOnlyHighlightsCostWhatMasterCosts` | `makePlan` resolves an italic face every frame | itself (`faceResolutions` 1) |
| `aFaceRestyleReshapesOnlyTheRowsItChanges` | the face term dropped from `digest(of:)` (first attempt restyled bytes 0..<4 against a 0..<3 colour run, which changes the partition, so it stayed green: the test now restyles the colour run's own bytes) | itself (shaped 0) |
| `anIdleRepaintWithFacesRecomputesNothing` | the resolved face not stored in `faceTable` | itself, and test 5 |
| `monospacedFacesKeepOneAdvance` (both arms) | each run's `minX` dropped from the per-run carets | both |

Test 9's end-to-end half cannot go red by itself: Noto Sans' faces share one ascent, so the shift is 0 there. Its second half drives `buildCodeLine` with a `CodeFaces` whose baseline differs and asserts the glyphs follow it.
