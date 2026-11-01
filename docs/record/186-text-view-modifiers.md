# 186 - text dash patterns and view-level text modifiers (`TM-A`..`TM-H`)

2026-11-01, branch `feat/text-view-modifiers` from master `b83efde2`; round-3 item R3-10 part 1. Rulings:
`docs/superpowers/2026-11-01-text-view-modifiers-decisions.md`. Probe: `docs/probes/text-line-patterns.swift` (output recorded in its header). Rule: `docs/rules/text.md`
("View-level text modifiers and dash patterns"). No divergence label taken (995-1004 reserved).

## 1. What was there

`Text.LineStyle.Pattern` had one value, `.solid` ("a dash emitter and probe are owed first", `RT-A`), and `bold`, `underline`, `strikethrough`,
`kerning`, `tracking`, `baselineOffset` and `monospaced` existed only on `Text` and `ProposalText` ("additive later as environment keys"). Two rows of
the divergences page's "Not offered" table said so; both are removed.

## 2. The probe, in one table

Measured with `ImageRenderer` at 8x, the on/off run lengths along the middle row of the decoration band, `HHHH...` with a clear foreground and an explicit
line colour; lengths in points, thickness t:

| pattern | on / off cycle | at 13 pt (t = 1) | at 28 pt (t = 2) |
|---|---|---|---|
| dot | 3t / 3t | 3 / 3 | 6 / 6 |
| dash | 10t / 5t | 10 / 5 | 20 / 10 |
| dashDot | 10t / 3t / 3t / 3t | 10 3 3 3 | 20 6 6 6 |
| dashDotDot | 10t / 3t / 3t / 3t / 3t / 3t | 10 3 3 3 3 3 | 20 6 6 6 6 6 |

Underline and strikethrough alike. SwiftUI's thickness is a whole number: 1 (9-17 pt), 2 (20-28), 3 (36-48), 5 (72) - `ceil` of CoreText's underline
thickness (0.527, 0.762, 0.996 -> 1; 1.172, 1.641 -> 2; 2.109, 2.812 -> 3; 4.219 -> 5). Phase: every line starts "on" at its own start (including
centred and trailing lines), a mid-line underline is cut from the line's cycle (8.38 on after 76.62 of plain text), neighbouring runs continue the
cycle whatever their colour, a pattern change takes the same x with its own cycle from the line start. View-level modifiers (`V`, `W`): equal to
the `Text`'s own; own beats environment; nearest writer beats outer; an own underline replaces the environment's whole; `underline(false)` is "none"; bold is
a last-resort weight (light stays light in either order). `B`: a `Button` label reads `.kerning`.

## 3. Design

`Text.LineStyle.Pattern` gets its five statics. `linePatternSegments`/`linePatternUnit` (`TextLinePattern.swift`, pure) split a band into segment rects
from a cycle table and the rounded-up thickness; `drawStyledText` calls them per band with the line's start as the origin and joins only neighbours of one
colour and pattern. The view-level layer is `EnvironmentValues.textRichBox` (a boxed `TextRichFields`) plus `isBold`, written by `ElementGroup` modifiers
and read as the last link of `run ?? Text ?? environment` in `resolveRichText`; `resolveTextStyle` reads `isBold` as a last-resort weight;
`plainTextForm` returns `nil` while the environment sets a rich field. Both fingerprint rows exist, so retained subtrees and the layout memo see it.

## 4. Source breaks

None for a call site. A file declaring its own `ElementGroup` extension named `bold`, `underline`, `strikethrough`, `kerning`, `tracking`, `baselineOffset`
or `monospaced` collides (`docs/migration.md`). A stored property on `EnvironmentValues`/`EnvironmentFingerprint`: `swift package clean`. The guard
`theTextModifiersComposeAsSwiftUIs` lost its two "does not compile" dash arms.

## 5. Tests

`TextViewModifierTests.swift` (MetalUICrossPlatformTests, portable system; 12), `TextViewModifierSpyTests.swift` (2), `RetainedTextViewModifierTests.swift`
(4), the `TM-1` plain-import guard in `RichTextCompileGuards.swift`; updated: the fingerprint field count 27 -> 29 and its table
(`RetainedAmbientMissTests`, `RetainedSubtreeInternalTests`).

**Counts** (2026-11-01, `feat/text-view-modifiers` on master `b83efde2`, `--build-system native --build-tests` then an unfiltered `--no-parallel` run): **4836 tests in 14 suites passed, 0 issues** (re-run by the orchestrator; the agent first reported 4635 in 12, a misread log);
`FR-J no-argument frame: succeeded=true` printed (the run's log kept only its tail, so `TM GUARD 1 compiles: succeeded=true` was read from a filtered native run of the guard). The guard was mutated in the native build: `Pattern.dot` made `internal` reddens
`theLinePatternsAndViewLevelTextModifiersAreSwiftUIs` (`'dot' is inaccessible due to 'internal' protection level`). The count is this tree's own tally (the baseline master figure was not re-taken).

## 6. Mutations

Each applied to the declaration named (default build system, then restored from the commit), run against the 17 new/updated test names plus `RetainedAmbientMiss`/`everyEnvironmentField`
and the neighbours `aPlainTextTakesThePlainCalls`, `anUnderlineIsARectAtTheFacesPosition`, `sameColouredUnderlinesMerge...` (none of the neighbours reddened). File is the one named; branch is the spelling shown.

| Mutation (file, spelling) | Reddened |
|---|---|
| `Pattern.cycle` dash `[10, 5]` -> `[9, 5]` | `eachPatternsCycleIsTheProbes`, `theCycleStartsAtTheOriginNotTheInterval` |
| dot `[3, 3]` -> `[3, 2]` | `eachPatternsCycleIsTheProbes` |
| dashDotDot loses two gap entries | `eachPatternsCycleIsTheProbes` |
| dashDot last gap 3 -> 4 | `eachPatternsCycleIsTheProbes` |
| `linePatternSegments`: first cycle starts at `low` | `theCycleBelongsToTheLineAndCarriesAcrossRuns`, `theCycleStartsAtTheOriginNotTheInterval` |
| same: `.rounded(.down)` -> `.up` | the same two |
| `linePatternUnit`: `.up` -> `.toNearestOrEven` | `theUnitIsTheThicknessRoundedUp` |
| same: drop `Swift.max(1, ...)` | green at first (no row below 1e-4); after adding the 0 and 0.00005 rows: `theUnitIsTheThicknessRoundedUp` |
| `band(_:)` guard forced to the solid branch (pattern ignored) | `aDashedUnderlineIsThePatternsSegments`, `aViewLevelLineIsTheTextsOwnAndTheTextsOwnReplacesItWhole`, `anAncestorsPatternChangeMissesEveryPanel`, `eachWrappedLineStartsItsOwnCycle`, `theCycleBelongsToTheLineAndCarriesAcrossRuns`, `theUnderlineAndTheStrikethroughHaveTheirOwnPatterns` |
| `band(_:)` guard forced to the segment branch (a solid line through `linePatternSegments`) | **green, equivalent**: `linePatternSegments(.solid, ...)` returns the one interval, so the same single rect; the two spellings are interchangeable |
| strikethrough band reads `underlinePattern` | `theUnderlineAndTheStrikethroughHaveTheirOwnPatterns`, `aViewLevelLineIsTheTextsOwnAndTheTextsOwnReplacesItWhole` |
| `origin: x + lines[line].offsetX` -> `x` | `eachWrappedLineStartsItsOwnCycle` |
| `origin:` the band's `low` | `theCycleBelongsToTheLineAndCarriesAcrossRuns` |
| the join ignores the pattern | `theCycleBelongsToTheLineAndCarriesAcrossRuns` |
| drop `view.kerning` / `view.tracking` / `view.baselineOffset` from the chain | `aViewLevelSpacingReachesTheTextBelowAndTheTextsOwnWins` (kerning also `anAncestorsKerningChangeMissesEveryPanelAndRepaints`) |
| environment kerning ahead of the run's own | `aViewLevelSpacingReachesTheTextBelowAndTheTextsOwnWins` |
| drop `view.underline` / `view.strikethrough` | `aViewLevelLineIsTheTextsOwnAndTheTextsOwnReplacesItWhole` (underline also `anAncestorsPatternChangeMissesEveryPanel`) |
| environment underline ahead of the own | `aViewLevelLineIsTheTextsOwnAndTheTextsOwnReplacesItWhole` |
| `ElementGroup.underline(false)` writes `nil` instead of `.none` | **green, equivalent**: a write of `nil` replaces an outer line as `.none` does; both read as no line below |
| bold ignoring the font's own weight; bold before `environment.fontWeight`; `isBold` ignored | `aViewLevelBoldIsAWeightOfLastResort` (each) |
| drop `view.monospaced` | `aViewLevelMonospacedResolvesTheMonospacedFace` |
| `plainTextForm` without `viewLevel.isEmpty` | `aTextUnderAViewLevelModifierTakesTheStyledPath...`, `aViewLevelLineIsTheTexts...`, `aViewLevelSpacingReaches...`, `anAncestorsKerningChange...` and more |
| fingerprint with `textRich` neutralised | `anAncestorsKerningChangeMissesEveryPanelAndRepaints`, `anAncestorsPatternChangeMissesEveryPanel` |
| fingerprint with `isBold` neutralised | `anAncestorsBoldChangeMissesEveryPanel` |
| `textTracking` setter writes kerning | `theEnvironmentFieldsAreIndependentAndAnEmptySetStoresNoBox` |
| `TextRichFields.isEmpty` ignoring `monospaced` | `aTextUnderAViewLevel...`, `aViewLevelMonospacedIsReadByTheTextBelow`, `aViewLevelMonospacedResolvesTheMonospacedFace`, `theEnvironmentFieldsAre...` |
| `ElementGroup.kerning` writes tracking | `aViewLevelSpacingReachesTheTextBelowAndTheTextsOwnWins` |
| `ElementGroup.bold` ignoring `isActive` | `anAncestorsBoldChangeMissesEveryPanel` |

Named limits: the painted-dash tests derive their expectation from `linePatternSegments`, so a wrong cycle constant is pinned by `eachPatternsCycleIsTheProbes` alone (the probe's numbers) - by design. The plain-import guard `TM-1` is mutated in the next line (native build).

## 7. Carried

`TextField`/`TextEditor` reach of the view-level modifiers other than bold/italic (unmeasured: `ImageRenderer` draws no `TextField`, so SwiftUI's answer is
unknown); `monospacedDigit`, `fontWidth`, `fontDesign`; the phase under right-to-left lines; `Text.LineStyle` patterns on the SDL GPU path are the same
rects (no carry). Human check group TM (unrun).
