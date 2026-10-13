# Developer guides follow-up — design

Item 10c, a follow-up to 10b (record §103, rulings `DG-A`…`DG-Q`). While 10b was on its branch
four items merged: C23 (text over a GPU surface, §99), C24 (resign on press, §98), C27 (material
follow-ups, §101) and C28 (the input-method driver, §102). The guides omitted their APIs, two of
which sat on the denylist test `noGuideNamesAnApiThatIsNotOnMaster`. No `Sources/` change.

## 1. Scope

| Guide | New section | API | Item | Divergences named |
|---|---|---|---|---|
| 3 `input.md` | How do I end editing when the user clicks empty chrome? | `.resignsFocusOnPress()` | C24, `RF-` | none (class M) |
| 3 `input.md` | How do I test a field with an input method? | `TestWindow.setMarkedText(_:selectedRange:)`, `commitMarkedText()`, `commitMarkedText(_:)`, `cancelMarkedText()` | C28, `IM-` | 325, 326 |
| 5 `drawing-and-gpu.md` | How do I put a label over a GPU surface? | `@Environment(\.textMeasurer)`, `TextMeasurer`, `ResolvedText.measure(in:)` | C23, `GT-` | 295, 296 |
| 5 `drawing-and-gpu.md` | How do I make a material respect Reduce Transparency? | `@Environment(\.accessibilityReduceTransparency)`, `Material.tint(in:)` | C27, `MT-` | 315 |

## 2. Form

Each section follows `DG-B`: a task heading, short prose with a `(pin: …)` on every behaviour claim,
one compiled block, mirrored byte for byte in `GuideMirrorsLane1.swift` (input #6, #7) or
`GuideMirrorsLane2.swift` (drawing #6, #7), and a test that drives it in a headless window.
`testing.md` is linked, not edited.

## 3. Tests

| Test | Pins | Mutation |
|---|---|---|
| `theInputGuideAClickOnInertChromeEndsEditing` | the resign section | delete `.resignsFocusOnPress()` |
| `theInputGuideAnInputMethodComposesCommitsAndCancels` | the IME section | delete the write in the field's closure |
| `theDrawingGuideASurfaceIsSizedFromTheMeasuredLabel` | the measurer section | change `+ 16` |
| `theDrawingGuideAPanelFollowsReduceTransparency` | the panel | delete `.background(.regularMaterial)` |
| `theDrawingGuideATintOpacityIsTheTable` | `tint(in:)` | make `drawingTintOpacity` ignore its scheme |

The denylist loses `resignsFocusOnPress` and `TextMeasurer` (`PhaseAnimator` is not built and stays).
Red first: the mirrors were committed before the guides (`everyGuideBlockIsCompiledVerbatim` red), and
the denylist test was run with the names present in the guides (two issues) before the removal.
