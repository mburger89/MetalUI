# Record 202: the default-spacing probe and row 89 (round 4 item R4-2 PR A)

Branch `feat/r4-2-default-spacing`, from master `32613381`. Decisions: `docs/superpowers/2026-11-03-default-spacing-decisions.md` (`DS-A`..`DS-D`). Human checks: none yet (the group belongs with PR B). Divergences: **89 retired**; 51 and 65 unchanged (207 live; next label 213). **No `Sources/` change.** PR B (rows 51 and 65) is a separate decision, made after this record.

**The triage grouped 89 with the spacing rows 51 and 65 in error** (record 197): 89 is a spacer-priority row. It was retired here as an instrument artifact, and 51 and 65 were not touched.

## 0. The machine (lock state)

`docs/probes/appkit-screen-lock-state.swift`, run first, 2026-11-03 (macOS 27.2 26B123): `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 0`, `displayActive main: 1`, `preflightScreenCaptureAccess: false`, one screen (1920x1080, scale 1.0). **The session was locked with no Screen Recording permission.** No arm needs pixels (layout only, `NSHostingView` + `layoutSubtreeIfNeeded`), so none was left unmeasured for that reason; **`ImageRenderer` was not used anywhere** (it is the instrument behind K1/K4). The probe was run twice (`/usr/bin/swift`, Apple Swift 6.4.2): the outputs are byte-identical (`cmp` empty, 1239 lines; kept in `docs/probes/swiftui-default-spacing-run.txt`), `=== instruments: 922 pairs, 0 DISAGREE`.

## 1. What the probe showed (`swiftui-default-spacing.swift`; the header holds the reading)

| arm | reading | consequence |
|---|---|---|
| `DS0` | every S, K0, K1b, K1, K1c, K3, K3a, SP8 and GS7 line MATCHES the record (4.742 and 8.151 print where the record rounded to 4.74 and 8.15) | stop condition 1 did not fire |
| all | the three instruments (size difference, background leaf, `ViewSpacing.distance`) agree to 0.001 on 922 pairs; the size-difference one is invalid for a flexible neighbour and a two-spacer `Edge` is never asked | stop condition 2 did not fire (the 15 first-run disagreements were these two cases) |
| `DS1`, `DS1b`, `DS2` | 107 font-size rows: rect above text `d + ceil((a + d) / 10)`, text above rect that `+ (a - c)`, text above text `ceil(leading)` of the lower text; horizontal always 8 | a closed rule fits (residual 0.0000 / 0.0010 / 0.0000); stop conditions 3 and 6 did not fire; **condition 5 fired** (cap height) |
| `DS3`, `DS4` | `displayScale` 1, 2, 3 as an environment value, `dynamicTypeSize`, `controlSize` (only through the default font it selects), bold, italic: nothing moves | stop condition 4 did not fire (a real backing scale is unmeasured) |
| `DS4b`, `DS5` | text|text is not always 0: a text-style font gives its preferred font's leading, ceil'd (`.body` 1, `.largeTitle` 2, `.title3` 3), `.system(size:)` and an unset font give 0; unequal fonts take the lower text's | a finding the plan did not predict |
| `DS6` | empty `Text` has no vertical edge; `Text + Text` takes the larger font's; `lineSpacing`, `baselineOffset`, `kerning`, a second line change nothing | |
| `DS7`, `DS7b` | standard for rect, bitmap, `Color`, `Divider`, `TextField`, `Slider`, `Picker`, `Stepper`, default `Button`, `.switch`, `ScrollView`, `Grid`, `ProgressView`; text edges for a `.plain` `Button` and a `Label`; a checkbox `Toggle` 6 beside a rect; an SF Symbol 2 above / 3 below at 13 pt and 0 against text | edges are not just zero, standard and text: stop condition 8 is for PR B |
| `DS8` | padding(0), flexible frame, background, overlay, fixedSize, layoutPriority, offset, opacity, border, `ZStack`, `Pass{}` keep the text edges; a fixed frame and non-zero padding give standard (8) on the edges they touch | |
| `DS9` | across a composite a text edge beats a standard one and the larger font's beats a smaller; along it the first and last child's edge passes | FM0's "text wins" is not max-of-distances |
| `DS10` | a font on the stack is inherited by its Texts and changes nothing else | stop condition 7 did not fire |
| `DS11` | `Spacer()`'s nil minimum is a constant 8 at 9, 13 and 48 pt; no default spacing beside it | |
| `DS12` | a Grid's row gap is the stack rule; a mixed row takes the largest pair; the column gap is 8; as a stack child its edges are its first and last row's | 65 follows 51's rule |
| `DS13` | `LazyVStack`, a one-column `LazyVGrid` and a `ScrollView`'s implicit stack follow the same rule as `VStack`; `LazyHStack` 8; `ScrollView` as a child is standard | MetalUI's lazy containers use one constant (a difference, not SwiftUI's) |
| `DS14` | bare `VStack(0){para; Spacer()}` text 48 / 80 / 96 at 60 / 100 / 200 (3, 5, 6 lines), with `minLength: 0` 48 / 96 / 96; `Where{Spacer()}` replays K1 and K4 (16 / 48 / 96); `Pass{Spacer()}`, `Spacer().padding(0)`, `Color.clear` read 16 / 48 / 96 | **stop condition 9 did not fire; 89 retired** |

## 2. The fitted rule, residuals, and what `TextFontMetrics` can express

With a = ascent, d = descent, c = capHeight, l = leading (all CoreText), `ceil` upward, over the 107 rows of `DS1`, `DS1b` and `DS2` (17 + 54 SF sizes, then 12 families at 13, 26 and 48 pt):

| quantity | rule | max residual | mean |
|---|---|---|---|
| rect above text | `d + ceil((a + d) / 10)` | 0.0000 | 0.0000 |
| text above rect | that `+ (a - c)` | 0.0010 | 0.0003 |
| text above text | `ceil(l)` of the lower text (the 12 leading rows of `DS2`, and `DS4`, `DS4b`, `DS5`) | 0.0000 | 0.0000 |
| H0 constant 4.742 / 8.151 | | 61.446 / 110.478 | 5.81 / 10.02 |
| H1 proportional to size | | 6.766 / 11.272 | 0.80 / 1.21 |
| H2 `d + 2` (no step); text-over-rect without cap height | | 22.0; 9.268 | 1.96; 0.41 |
| step `ceil(a / 8)`, `floor(a / 8) + 1` | | fail at 6 of 107 rows | |

The 0.001 on text-over-rect is the probe's three-decimal print. A search over `{a, d, a + d, line height, size, cap, xHeight}` x `{ceil, floor+1, round, floor}` x divisor 2..30 found exactly one zero-miss form (`a + d` over 10, `ceil`).

**`TextFontMetrics` on macOS** (`CoreTextTextSystem.fontMetrics`, `CTFontGetAscent/Descent/Leading`, the same values `NSFont` printed): ascent, descent and leading exist, so rect-above-text and the leading part of text-over-text are expressible; **text-over-rect needs `capHeight`, which the type does not have** (adding it changes a public type and every third-party `TextSystem` conformer: a defaulted initialiser argument, a map row, a doc comment, `swift package clean`; stop condition 5, not done here). **Through the portable system** (`hhea` via `MetalUIFreeType.horizontalHeader`): for both `Tests/Fonts` faces `hhea` gives CoreText's ascent and descent to three decimals (Noto Sans 13.897 / 3.809 at 13 pt, Source Sans 3 13 / 4.238), and the rule's predictions equal the SwiftUI figures (`rect|text` 5.809 and 6.238 at 13 pt); the cap height would be `OS/2.sCapHeight` (714 and 660 per mille), which `MetalUIFreeType` does not read. **The text-style leading is not expressible on either**: MetalUI resolves `.body` to a plain system font of 13 pt whose leading is 0, where SwiftUI's carries `NSFont.preferredFont`'s (0.689, ceil 1); making `.body` text|text 1 needs a table of the eleven styles' ceil'd leadings (2, 1, 2, 3, 1, 2, 1, 1, 2, 2, 2). Whether to make MetalUI's gap this function on Linux and Windows (SwiftUI cannot be measured there) is a ruling for PR B.

## 3. What changed

- `docs/probes/swiftui-default-spacing.swift` (new) and `swiftui-default-spacing-run.txt` (the recorded output).
- `Tests/MetalUITests/LineLimitTests.swift`: `aStackSharesItsHeightWithAWrappingTextAsSwiftUIDoes` keeps its values, its comment and messages say the arms agree with SwiftUI; new `aBareSpacerBesideAWrappingTextTakesOnlyItsMinimum` (with the `minLength: 0` arms) and `aSpacerInACustomLayoutSharesLikeAnyFlexibleChild` (a `ProposalLayoutContainer` with a pass-through `ProposalLayout`, default and `minLength: 0`).
- Divergence 89 retired (`divergences.md` row, header, Retired table; `04-divergences.md` section and a forward note on the 89 bullet); `api-overview.md`; `CLAUDE.md` (both counts: 207 live, next label 213) and `AGENTS.md`; `decision-prefixes.md`, `Tasks.md` (R4-1a now names #197 and its merge; R4-2 stays unticked with PR A's result).
- **The refuted K1/K4 claim, corrected where it was copied:** `swiftui-text-in-stacks.swift` (a CORRECTED block above the reading), `TE-R` and `TE-Z` (forward notes), spec row 3.23, record 59 (two places), record 04, record 66's row, `LineLimitTests`. `197-divergence-triage.md` keeps its text as history.
- **Not changed, listed by the plan for PR B or for 51/65:** `CN-H`, `GR-D`, `GR-O` item 5, `swiftui-grid.swift:171`, `swiftui-controls-in-stacks.swift:76`, `swiftui-lazy-containers.swift:47` and the source comments at `ProposalSpacing.swift:6-8`, `LayoutTree.swift:479` and `:1300`, `NativeGrid.swift:166` state the "font-derived" claim about 51 and 65, which this probe measured but did not retire; they are corrected with PR B.

## 4. Mutations (applied from the committed tree, restored with `git checkout`; names are the tests that reddened; filter `aBareSpacer|aSpacerInACustom|aStackSharesItsHeight`, default build system)

| mutation (spelling) | reddened |
|---|---|
| M20 `nativeLayoutPriority` gains `case .custom:` returning the child's priority for a one-child node (in the `switch`, before `.grid`) | `aSpacerInACustomLayoutSharesLikeAnyFlexibleChild` only: the 60 and 100 arms of both spellings (4 issues). The 200 arms stay green (every arm draws 6 there, the separating control) |
| M20b `case .spacer: return 0` instead of `-.infinity` | `aBareSpacerBesideAWrappingTextTakesOnlyItsMinimum` (the `minLength: 0` 60 and 100 arms and the default 100 arm), `aStackSharesItsHeightWithAWrappingTextAsSwiftUIDoes` (60 and 100), and the existing `aBareSpacerCellIsPriorityMinusInfinityAndFlexibleOnBothAxes`; **not** `aSpacerInACustomLayoutSharesLikeAnyFlexibleChild` (the wrapped spacer is already priority 0) |

No mutation was green. Both new tests were green on arrival, which is the finding: MetalUI already agrees with SwiftUI on the bare spacer and on the wrapped one, so no divergence stays.

## 5. For callers (MetalCreator, MetalFlow)

Nothing in `Sources/` changed, so no layout moves. Row 89 is gone from the divergence list: a text beside a bare `Spacer` is the same in both. What PR B would change, from the measurements above, is a `VStack` or `Grid` next to a `Text`: gaps vary with the font, the first-line text of a `VStack` of two Texts tightens by the leading, and a lazy stack changes too. The grep for it is `\b(VStack|Grid)(\(alignment: *[.a-zA-Z]+\))? *\{` next to text; plan section 3 found no default `VStack` or `Grid` in either app's `Sources/` (single-line spellings only).

## 6. Counts and checks

`swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel`, unfiltered, 2026-11-03: **`Test run with 5019 tests in 14 suites passed after 318.003 seconds`** (0 failures; record 201 read 5017, this branch adds 2 test cases); `FR-J no-argument frame: succeeded=true` (guards ran). The run started before a coordinator hold on window and test runs and finished during it; nothing failed, so no focus-sensitive result needed a re-run. `zsh docs/probes/record-05-check.sh`, `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing (the first inventory check printed `LIVE stacks 89` until the `stacks` row of `closeout-inventory-map.tsv` dropped the retired label; fixed). The counts line of `CLAUDE.md` is not replaced.

**Not run / not measured:** `METALUI_VERIFY_*` modes and the 100k-list test (no layout or retained code changed); `Backends/SDL`, Linux and Windows CI; pixels (locked session); a real backing scale.
