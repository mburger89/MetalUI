# Engine replacement, stage 7a — the goldens retired (plan task 7)

Parent design: [`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 row 7a, §8. Rulings `LR-DS`…`LR-DX` in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md).
Record: `docs/record/42-engine-replacement-stage-7a.md` (its §4 is the 97-row
retirement table this design commits). Probe:
`docs/probes/swiftui-engine-stage-7a.swift` (arms W, G, S, A, B, run
2026-09-23). Instrument: `docs/probes/stage-7a-transcription-instrument.patch`.
Branch `feat/engine-stage-7a` from `2cc763d`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-7a`.

**Status, 2026-09-23 (PDT): design.** Nothing under `Sources/`, `Tests/` or
`Package.swift` changed in a commit.

**What this stage is.** Each of the 97 WebKit goldens
(`Tests/MetalUILayoutTests/Golden/*.json`) is retired with a row naming either
the native test arm that asserts its geometric fact under the proposal
authority, or the CSS-only concept it dies with. Then the golden machinery —
`GeneratorTests`, `OracleTests`, `Fixtures/`, `Oracle/`, `Golden/` — and the
golden-consuming tests are removed (96 whole, one trimmed). **It does not pre-empt 7b**: no
non-golden test is removed (one consumer is trimmed rather than removed because
it asserts a non-golden tree, `LR-DT`), and the legacy engine, `FlexEngine` and
every `.legacy`-pinned test stay.

## Contents

1. [Baseline](#1-baseline)
2. [The entry measurement](#2-the-entry-measurement)
3. [Decisions](#3-decisions)
4. [API and files](#4-api-and-files)
5. [The retirement, by family](#5-the-retirement-by-family)
6. [Lanes, and every test by name](#6-lanes-and-every-test-by-name)
7. [What must not move; the demo](#7-what-must-not-move-the-demo)
8. [Exit criteria](#8-exit-criteria)
9. [Handed on](#9-handed-on)

## 1. Baseline

At `2cc763d`, measured 2026-09-23 in the worktree: `swift build
--build-system native --build-tests` (0 `error:`, one `warning:` — SwiftPM's
deprecation notice), unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1704 tests in 3 suites passed`**, the log
carrying `FR-J no-argument frame: succeeded=true`. **97** goldens
(`find Tests/MetalUILayoutTests -name "*.json" | wc -l`), 78 guards. Every
golden has exactly one consumer `@Test` (record §42 §1).

## 2. The entry measurement

Record §42 §2 in full. Each fixture's CSS was transcribed into `Box(style:)`
trees with every golden id named by `.id(_:)`, and rendered under **both**
authorities through `LayoutDifferential.render`. 74 of 97 were transcribed (the
23 others each hold a `flex-wrap` box, which reports by name whatever its
place, `LegacyLowering.swift:209`). The legacy authority reproduces all 74
goldens exactly — the transcription is right. The proposal authority:

| outcome | trees | verdict |
|---|---|---|
| reproduces the golden exactly, empty report | **44** (43 whole + `stack_stretch_max` minus its percentage child) | **R** |
| reports a field by name, lays out a 0×0 leaf | 23 (+ the 23 untranscribed wrap trees) | **D** |
| lays out silently with a different answer | 7 | **D**, pinned natively |

## 3. Decisions

| ruling | decides |
|---|---|
| `LR-DS` | the two verdicts, R and D; an R golden's replacement is a **new arm asserting the golden's own boxes on its own tree** under the proposal authority, not a citation of a lowering test on other numbers |
| `LR-DT` | the consumer tests go with their goldens (96 whole, 1 trimmed), the machinery with them; the 7b boundary; the count arithmetic |
| `LR-DU` | the seven deleted concepts, each with its CSS-only reason, its native pin and — where a SwiftUI claim is made — its probe arm |
| `LR-DV` | the seven silent D shapes get native pins of the golden's own tree (2.5–2.7); the reported ones cite the existing report tests |
| `LR-DW` | the new tests are characterization: green on arrival, their red-before is a named mutation run before they are committed |
| `LR-DX` | three lanes, the removal last and only after every replacement is green; `Sources/` untouched but one doc comment |

## 4. API and files

**No API change.** No `Sources/` code changes; the only `Sources/` edit is
`roundLayout`'s doc comment (`Sources/MetalUILayout/Rounding.swift`, the `///`
block above `public func roundLayout`), whose caller list names `roundBoxes` in
`GoldenFile.swift` and whose "the corpus now detects a missing rounding pass"
paragraphs describe the deleted goldens and their consumers. Lane 3 rewrites
those paragraphs to the callers that remain (`git diff 2cc763d -- Sources` must
show only `///` lines of that block).

| file | lane | change |
|---|---|---|
| `Tests/MetalUITests/GoldenReplacementSupport.swift` | 1 | new: `goldenArm` and `bounds(named:in:)` (below) |
| `Tests/MetalUITests/GoldenReplacementFlexTests.swift` | 1 | new: tests 1.1–1.8, 29 arms |
| `Tests/MetalUITests/GoldenReplacementStackTests.swift` | 2 | new: tests 2.1–2.7, 15 R arms (incl. `stack_stretch_max` partial) + 7 D-pin arms |
| `Tests/MetalUILayoutTests/Golden/` (97 JSON + `.gitkeep`), `Fixtures/` (97 HTML), `Oracle/` (3 files), `GeneratorTests.swift`, `OracleTests.swift` | 3 | deleted |
| `AbsoluteFixtureTests.swift`, `StackFixtureTests.swift`, `FitContentFixtureTests.swift`, `ContentSizingFixtureTests.swift` | 3 | deleted (every test a consumer) |
| `FlexEngineTests.swift` (16 consumers + `assertMatchesGolden`), `WrappingTests.swift` (17), `FreezeLoopTests.swift` (13), `BoxModelTests.swift` (12), `SizingFixtureTests.swift` (8 removed, 1 trimmed) | 3 | consumers removed; every other test byte-identical |
| `Package.swift` | 3 | `MetalUILayoutTests`' `resources: [.copy("Fixtures"), .copy("Golden")]` removed (no other `Bundle.module` in that target) |
| `Sources/MetalUILayout/Rounding.swift` | 3 | `roundLayout`'s doc comment only (above) |

**The shared helper** (lane 1, `GoldenReplacementSupport.swift`, internal so
lane 2 reuses it rather than copying it — a copy would be unpinned):

```swift
/// One expected box of a retired golden, by its `data-id`.
struct GoldenBox { let id: String; let x, y, width, height: Float }

/// Renders `make()` under the PROPOSAL authority inside a `window`-sized
/// `DifferentialRoot` and asserts, for the retired golden `golden`:
/// the frame reported nothing (`try #require`, message names the golden and the
/// fields), each expected id names exactly ONE element (`try #require`), and that
/// element's `Frame.elementBounds` rect equals the box exactly.
@MainActor
func goldenArm<C: ElementGroup>(_ golden: String, window: (Float, Float) = (800, 600),
                                _ boxes: [GoldenBox],
                                sourceLocation: SourceLocation = #_sourceLocation,
                                @ElementBuilder _ make: @MainActor () -> C) throws
```

Trees are written as the instrument patch writes them: `Box(style:)` with the
fixture's `Style` fields, children in fixture order, each golden id on
`.id("<data-id>")` (the outermost modifier), absolute boxes inside `Deferred`
with the window sized to the fixture's root. No `computeLayout(` call (7b's exit
greps for it).

## 5. The retirement, by family

The table is record §42 §4, one row per golden: consumer removed, the fact it
pins, the verdict, the replacement or deleted concept. The literals each R arm
asserts are record §42 §5.1 (the golden's `rounded` boxes, read before deletion);
the D pins' native answers are §5.2.

| family | R (new arm) | D (deleted concept → native pin) |
|---|---|---|
| fixed packing, gap | 3 → 1.1 | — |
| `justifyContent` | 5 → 1.2 | — |
| `alignItems`/`alignSelf`/stretch | 3 → 1.3 | — |
| reverse | 2 → 1.4 | — |
| padding + border | 3 → 1.5 | — |
| margins | 8 → 1.6 | — |
| grow | 3 → 1.7 | weights 2 → report; sub-one 2 → 2.5 |
| content-sized main axis | 2 → 1.8 | — |
| shrink, length basis | — | 6 → report / 2.7 |
| stack (`display: .stack`) | 10 → 2.1–2.3 (`stack_stretch_max` partial) | border-box floor 1 → 2.6 |
| absolute | 5 → 2.4 | — |
| sizing (§4.5 automatic minimum, `BM-4` floor) | — | 5 → report / 2.7 |
| percentages | — | 7 → report |
| wrap (and wrapping content, TX-H fit-content) | — | 30 → report |
| **total** | **44** | **53** |

## 6. Lanes, and every test by name

Three lanes, sequential (`LR-DX`). Every test renders under
`LayoutDifferential.render(authority: .proposal, …)` through `goldenArm`; every
arm is labelled by the golden it retires. **Red-before** (`LR-DW`): each test
pins behaviour that already exists, so it is green on arrival; its red-before is
the named mutation, applied to the committed source (commit the test first,
restore the source from a copy), run in the **full unfiltered suite**, with
`git status --short` clean after the restore. The lane records every test the
mutation reddened, by name, and each arm that reddened.

### Lane 1 — flex R arms (Opus)

Files: `GoldenReplacementSupport.swift`, `GoldenReplacementFlexTests.swift`.

| # | test | arms (goldens) | mutation that must redden it → predicted arms |
|---|---|---|---|
| 1.1 | `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap` | `flex_row_three_fixed`, `flex_column_three_fixed`, `flex_row_gap` | **M1a** `arrangeLegacyMainAxis`: `var spacing = gap` → `0` → `flex_row_gap` |
| 1.2 | `justifyContentDistributesADeclaredMainSizesFreeSpace` | `flex_row_justify_between`, `_around`, `_evenly`, `_between_gap`, `flex_column_justify_center` | **M1b** `distributedLegacyItems`: `betweenCount` always 1 → `flex_row_justify_around` (reads evenly's 60/160/290) |
| 1.3 | `alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis` | `flex_row_align_center`, `flex_row_align_end_with_self`, `flex_row_stretch_mixed` | **M1c** `alignmentFactor(_: AlignItems?)`: `.flexEnd` → 0 → `flex_row_align_end_with_self` (a, c) |
| 1.4 | `aReverseDirectionPacksItemsFromTheMainEnd` | `flex_row_reverse`, `flex_column_reverse_justify_end` | **M1d** `arrangeLegacyMainAxis`: the `nodes.reverse()` line deleted → both arms (and 1.6's three reverse arms) |
| 1.5 | `paddingAndBorderInsetTheContentBoxEdgeByEdge` | `flex_row_padding_border`, `flex_column_padding_asymmetric`, `flex_nested_padding` | **M1e** `paddedAndSized`: `inset(_:_:)` returns the padding only (border dropped) → all three |
| 1.6 | `marginsOffsetEachItemOutsideItsBorderBox` | `flex_row_margins`, `flex_row_margin_with_grow`, `flex_row_reverse_margins`, `flex_column_reverse_margins`, `flex_row_stretch_with_margins`, `flex_row_grow_space_between_margins`, `flex_row_stretch_min_height_margins`, `flex_row_reverse_stretch` | **M1f** `planLegacyItems`: `marginInsets`' `left:`/`right:` swapped → the five arms with unequal horizontal margins, not the two stretch-margin arms (0 horizontal) nor `flex_row_reverse_stretch` |
| 1.7 | `equalGrowersShareTheLineAndAMaximumCapsItsGrower` | `flex_row_seven_equal` (window 400×200), `flex_row_grow_with_max`, `flex_column_grow_with_max` | **M1g** `planLegacyItems.axis`, the `if greedy` branch: the maximum → `.infinity` → both `grow_with_max` arms; also expected: 1.3 `stretch_mixed`, 1.6 `stretch_with_margins`, `grow_space_between_margins`, `reverse_stretch` (recorded, not required) |
| 1.8 | `autoMainSizesSumTheirContentAndAGrowerIsFlooredByIt` | `flex_auto_height_two_levels`, `flex_item_floored_by_content` | **M1h** `planLegacyItems.axis`, the `if greedy` branch: `lo` → `resolvedDimension(animatedMin) ?? 0` for a grown axis too (stage 2's M2b) → `flex_item_floored_by_content` (50/50) |
| — | the helper | — | **MH** (a harness decision is a mutation site): the missing-id `try #require` replaced by `continue`, with 1.1's `y` renamed `yy` in a scratch edit — 1.1 must go **green** (the broken instrument), and red again with the require restored |

### Lane 2 — stack, absolute and D-pin arms (Opus)

File: `GoldenReplacementStackTests.swift` (uses lane 1's helper).

| # | test | arms | mutation → predicted arms |
|---|---|---|---|
| 2.1 | `aStackPlacesAFixedChildAtItsAlignment` | `stack_alignment_center`, `_topleading`, `_bottomtrailing` | **M2a** `alignmentFactor(_: JustifyItems?)`: `.end` → 0.5 → `_bottomtrailing` (x 140) |
| 2.2 | `aStretchedStackChildFillsOnlyItsAutoAxesWithinItsOwnBounds` | `stack_stretch`, `stack_stretch_declared_size`, `stack_stretch_min`, `stack_stretch_max` (the golden's tree **minus `p`**, asserting root, `h`, `w`) | **M2b** `planLegacyItems`, the `.stack` case: `&& d.size.width == .auto` dropped → `stack_stretch_declared_size` (child 300 wide) |
| 2.3 | `aStackHugsItsLargestChildInsideARowAndAroundOne` | `stack_sizes_to_largest`, `stack_in_flex`, `flex_in_stack` | **M2c** `LayoutTree`'s `.overlay` measurement answers its first child's size, not the per-axis maximum → `stack_sizes_to_largest`, `stack_in_flex` (stack 50×40) |
| 2.4 | `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow` | `abs_containing_block_skips_static`, `abs_percent_insets_nonsquare`, `abs_over_constrained`, `abs_single_inset_auto_size` (window 200×100), `abs_removed_from_flow` (800×600) | **M2d** `lowerPresentation`: the vertical axis resolved against `window.width` → `abs_percent_insets_nonsquare` (y 20) |
| 2.5 | `aGrowFactorSumBelowOneStillFillsTheLine` | D pins: `flex_row_fractional_grow` (133/134/133), `flex_row_fractional_grow_clamped` (50/350) | **M2e** `planLegacyItems`: `d.flexGrow > 0` → `d.flexGrow >= 1` for `grownH`/`grownV` → both arms |
| 2.6 | `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder` | D pin: `stack_stretch_border_box_floor` (f 100×100, c 40×50) | **M2f** `planLegacyItems.axis`, stretched axis of a non-frame-layer item: `lo` = the item's padding + border on that axis (CSS's `BM-4` floor) → both boxes (120×140) |
| 2.7 | `aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding` | D pins: `flex_row_shrink_padded_weighting`, `sizing_specified_suggestion`, `sizing_specified_suggestion_is_used_value`, `sizing_over_constrained_grows` | **M2g** `paddedAndSized`: each folded declared size raised to its padding + border sum (stage 2's M4c) → `sizing_over_constrained_grows` (120×140), `sizing_specified_suggestion_is_used_value` (a 120) |

Each D-pin test's doc comment names the golden, WebKit's answer, the native
answer and the concept (record §42 §2's table), so a later reader who sees the
native number knows it is a deliberate divergence and not a regression.

### Lane 3 — the removal (Opus)

Runs only when lanes 1 and 2 are committed and green in an unfiltered run.

1. **Verify every row first.** For each of record §42 §4's 97 rows: an R row's
   test exists and contains an arm labelled with the golden's name
   (`grep -n '"<golden>"' Tests/MetalUITests/GoldenReplacement*Tests.swift`
   → one hit); a D row's cited tests exist (`grep -n "func <name>"`). A row
   that fails blocks the deletion.
2. **Delete** the files of §4's table; remove the 96 consumer `@Test`s whole and
   trim `theClampedAutomaticMinimumIsStillFlooredByPaddingAndBorderMatchesWebKit`
   to its two `build(...)` arms minus `loadGolden`/`assertMatchesGolden` (every
   `#expect` it had stays, byte-identical); delete `assertMatchesGolden`; drop
   the `resources:` line; rewrite `roundLayout`'s doc comment (§4).
3. **Dangling references.** `grep -rn -E
   "loadGolden|allFixtures|GeneratorTests|OracleTests|LayoutOracle|assertMatchesGolden|GoldenFile|roundBoxes|Golden/|Fixtures/"
   Tests Sources` — each surviving hit in a comment is rewritten or listed in
   the record with why it stays (`FlexEngine.swift:1342`'s historical "verified
   against this repo's own `LayoutOracle`" may stay: it describes a measurement
   that was taken, and stage 9 deletes the file).
4. **Re-run one mutation per family with the goldens gone** — M1b, M1f, M2d,
   M2g — to show the replacements still redden without them.
5. The exit checks of §8, and the pixel comparison of §7.

## 7. What must not move; the demo

| must not move | pinned by |
|---|---|
| production behaviour, identity, hit testing, accessibility, animation | no `Sources/` code change (`git diff 2cc763d -- Sources` = `///` lines of `roundLayout`'s doc comment only) |
| pixels | `docs/probes/demo-pixels/compare.sh <scratch> 2cc763d <HEAD>`: all twelve images **0 px**, every control as record §41 read it |
| cross-platform demo pin | `DemoFrameDeterminismTests` green and unedited (`git diff 2cc763d -- Tests/PortableTests Backends` empty) |
| every non-golden test's assertion | lane 3's diff of the five surviving consumer files touches only removed consumers, `assertMatchesGolden` and the trimmed test's two golden lines |
| 0 `warning:` | both build systems, as at baseline |

**Demo expectation: 0 px.** Nothing the demo runs changes.

## 8. Exit criteria

- `find Tests/MetalUILayoutTests -name "*.json" | wc -l` → **0** (not `find
  Tests`: `Tests/PortableTests/.build/` holds JSON build artifacts);
- `ls Tests/MetalUILayoutTests/Fixtures Tests/MetalUILayoutTests/Oracle
  Tests/MetalUILayoutTests/Golden` fails; `GeneratorTests.swift` and
  `OracleTests.swift` absent;
- every one of record §42 §4's 97 rows verified by lane 3 step 1;
- unfiltered `swift test --build-system native --no-parallel` → **`Test run
  with 1615 tests in 3 suites passed`** = 1704 − 96 − 5 − 3 + 8 + 7, the log
  carrying `FR-J no-argument frame: succeeded=`; four gated tests skipped where
  five were;
- 0 `error:`; the only `warning:` SwiftPM's deprecation notice (native) and none
  under the default build system;
- the mutation table of §6 run and recorded, every reddened test named.

## 9. Handed on

| item | owner |
|---|---|
| the non-golden CSS-engine tests of the five surviving consumer files, and the trimmed `theClampedAutomaticMinimum…` (its `cMinZero` arm is 7b's) | 7b (`LR-U`) |
| the new tests use `Style` fields (`margin`, `justifyContent`, `alignSelf`, `display: .stack`, `position`/`inset`) that stages 8 and 10 respell or delete; they are lowering tests and go with the lowering suites | 8, 10 |
| `CLAUDE.md`/`AGENTS.md`: the "97 goldens" counts, "Goldens must not move", five → four gated tests, the golden `find` command; records §03/§04/§05/`README`; the plan | this stage's Record phase |
| `FlexEngine.swift:1342`'s `LayoutOracle` mention | 9 (deletes the file) |
