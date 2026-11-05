# Record 213: hierarchical styles (round 4 item R4-4 PR A)

Branch `feat/hierarchical-styles`, on `docs/r4-3b-line-height` (9896b343); records 210-212 and PR #208 assumed. Rulings `HY-A`..`HY-E` in `docs/superpowers/2026-11-04-hierarchical-styles-decisions.md` (new prefix, row in `docs/rules/decision-prefixes.md`). Divergences: **119 retired** (209 live to 208, next label 217; the label is not reused). Probe `docs/probes/swiftui-hierarchical-paint.swift`. Human group `HY`.

## 1. What was measured

- [MEASURED] The plan's readings were taken through `swift -` on stdin and never committed. They are transcribed into the probe (arm bodies rebuilt from the plan's descriptions, ids kept) and recorded: `ImageRenderer`, compiled, macOS 27.2, Swift 6.4.2, run twice, 62 lines byte-identical (shasum `d5d13f00df4154177d7637983ef9d9b9b23a9a67`), screen locked. **Every plan table reading reproduced; none differs materially.** New: a red parent in the dark scheme (`RD1`..`RD5`) has the same alphas as light (1, .502, .251, .180, .180); only the red differs. `P13b`/`P13c`: with three styles `.secondary` is the second and `.quaternary` repeats the last. `T9b`: `Color.red.secondary` under a blue parent stays red at .502.
- [MEASURED, REAL MODULES] **The plan's overload design is refuted.** Disfavouring every sink's `Color` and generic overload and adding a concrete level overload ties, in the real modules, between the disfavoured `Color` overload and the already-disfavoured `ColorToken` twin for every leading-dot token that exists on both types (`.surface`, `.background`, `.accent`, `.separator`, `.textPrimary`): "ambiguous use of" at `ClipShape.swift:91`, `MenuBarStrip.swift:99`, `ToolbarStrip.swift:79`, `WindowControlsStrip.swift:81`. The plan's skeleton had not modelled the token twins. A `where T == ColorToken` twin is a compile error ("same-type requirement makes generic parameter non-generic").
- [MEASURED] The replacement (set by the coordinator): leave every sink untouched, add `ShapeStyle where Self == HierarchicalShapeStyle` statics and put `@_disfavoredOverload` on `Color.primary` and `Color.secondary`. The guard `everyHierarchicalOverloadArmTypechecksWithoutAmbiguity` (plain import, Swift 6, every sink, ternaries included) passes with it, and the pixel tests pin the binding.

## 2. What changed

`HierarchicalShapeStyle` (public, `Equatable`, not `Hashable`: SwiftUI's is neither; the `Equatable` keeps an erased level equal to itself under retention, mapped as an extra); `Color.Provider.hierarchical(Level, over: Color?)`; `Color.init(level:over:)` and `strippingLevel`; `inherited:` on `Color.resolved`, `ColorContext`, `Frame.resolve` and `Color.resolve(in:)`. **A deviation from the plan (HY-B):** the parent is read where a colour resolves, not in `resolveTextStyle`, so `Text`, a legacy `Box` fill and border and a proposal `.border` all get it. `TextMeasurer` and `SurfaceText` pass `inherited`. Docs: divergence 119 retired (row, retired table, header paragraph, R-table row 312), `api-overview`, `drawing.md`, `decision-prefixes`, colour decisions erratum, `SS-G`, inventory map (family `hierarchical-styles`, class A, and `presentation-background` loses its 119 label), human group `HY`, `Tasks.md`, `CLAUDE.md` + `AGENTS.md` counts (208 live).

## 3. Existing tests whose expected value changed

One: `aLiteralColourReachesEveryColourTakingSite`'s `CR-U` arm. A `ProposalText` under `.foregroundStyle(.red)` with its own `.foregroundStyle(.secondary)` was `Color.secondary`'s grey (text x .588, no red); it is now red (FF383C) at alpha .5 and no grey. The first unfiltered run (5162 tests) had that one failure and no other. No library call site changed meaning (see section 5).

## 4. Mutations (the committed tree, each restored, `git status` clean after each)

The plan's nine, remapped where the design changed (1 and 6: there is no `resolveTextStyle` rebase or `shapeStyleStorage` arm; 7: per static; 8: there is no generic to disfavour, so the `ShapeStyle` statics are deleted). The run was the 116 tests that name colour, shape style or hierarchy.

| # | mutation | reddened |
|---|---|---|
| 1 | drop the inherited parent (`over ?? inherited` to `over`) | `aLevelIsAFactorOfTheParentAtEverySink`, `aLiteralColourReachesEveryColourTakingSite` |
| 2 | compound instead of strip | `levelsDoNotCompoundAndTheLaterModifierIsTheParent` |
| 3 | the theme table under a parent | `aGradientParentLowersToItsFirstStopAndATintParentIsTheTint`, `aLevelIsAFactorOfTheParentAtEverySink`, `aLiteralColourReachesEveryColourTakingSite`, `anEquatableChildUnderAChangedParentRepaintsItsLevel`, `levelsDoNotCompoundAndTheLaterModifierIsTheParent`, `ternariesBindLikeTheirArms` |
| 4 | over-parent quaternary .098 | `aLevelIsAFactorOfTheParentAtEverySink` |
| 5 | replace opacity instead of multiply | `levelsDoNotCompoundAndTheLaterModifierIsTheParent` (`P10`) |
| 6 | the sink ignores the environment's parent (`HierarchicalShapeStyle.resolve` over `nil`) | `aGradientParentLowersToItsFirstStopAndATintParentIsTheTint`, `aLevelIsAFactorOfTheParentAtEverySink`, `levelsDoNotCompoundAndTheLaterModifierIsTheParent` |
| 7a | `@_disfavoredOverload` off `Color.secondary` | `aGradientParentLowersToItsFirstStopAndATintParentIsTheTint`, `aLiteralColourReachesEveryColourTakingSite`, `anEquatableChildUnderAChangedParentRepaintsItsLevel`, `levelsDoNotCompoundAndTheLaterModifierIsTheParent` |
| 7b | `@_disfavoredOverload` off `Color.primary` | **green** on the first run, see below |
| 8 | the `ShapeStyle` statics deleted | `aGradientParentLowersToItsFirstStopAndATintParentIsTheTint`, `aLiteralColourReachesEveryColourTakingSite`, `anEquatableChildUnderAChangedParentRepaintsItsLevel`, `everyHierarchicalOverloadArmTypechecksWithoutAmbiguity`, `levelsDoNotCompoundAndTheLaterModifierIsTheParent`, `ternariesBindLikeTheirArms` |
| 9 | `Color.Provider` equality ignores `over` | **green** on the first run, see below |

**Two green mutants, both pin gaps, both closed.** 7b: every sink test took a typed level value, and the only leading-dot `.primary` was in a compile guard; the new `aLeadingDotPrimaryAndSecondaryBindTheLevelNotTheColour` writes the leading-dot spellings at eight sinks under a red parent (`Color.primary` is opaque text, the level is red at 1). 9: the retained test put a plain red/blue `Color` in the environment, whose key differs on the plain colour alone; the level now sits in the environment (`.foregroundStyle(.secondary)` under the changing parent), so the retained key holds a `.hierarchical` colour. Re-run results are in section 6.

## 5. Library audit: leading-dot `.primary` and `.secondary`

No `Sources/`, `Backends/` or `Examples/` call site passes a leading-dot `.primary` or `.secondary` to a `ShapeStyle` sink, so none changes meaning. Every use is `foregroundColor(.secondary)` (a `Color?` parameter, grey before and after: `AppShellDemo:156`, `RichTextDemo:55`, `LooksDemo:488`, `RetainedSubtreeDemo:138` and `:221`, Jotter `StatsView:12`, `DetailView:14`, `:54`, `:57`, `NoteRow:20`), a `Color`-typed tuple element (`LooksDemo:420`), or an unrelated `.primary` (`MouseButton`, `Modifiers`, `EventModifiers`). `ProgressView:109` writes `Color.secondary` explicitly. The user-visible control look is therefore unchanged. Not audited: downstream apps beyond the two clones (section 6).

## 6. Verification

- [MEASURED] After `swift package clean`, `swift build --build-system native --build-tests`, then unfiltered `swift test --build-system native --no-parallel`: **5164 tests in 14 suites passed (406 s)**, `FR-J no-argument frame: succeeded=true`, the guard printed `succeeded=true`. Again with `METALUI_VERIFY_RETAINED=1` (5164 passed, 428 s) and `METALUI_VERIFY_LAYOUT_MEMO=1` (5164 passed, 413 s). The baseline on this branch's parent is 4817 + later landings; the 5162 of the first run (before the flip) had one failure, the flipped `CR-U` arm; this head adds 7 tests (guard 1, paint 6, retained 1) over that head's 5157.
- `record-05-check.sh`, `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; `cmp CLAUDE.md AGENTS.md` is identical.
- [MEASURED] MetalCreator and MetalFlow (scratch copies with `../MetalUI` pointing at this worktree, `swift build --build-tests`): both build, exit 0. Their suites were not run.
- **The asserts compiler is absent.** `~/Library/Developer/Toolchains` holds `swift-6.4.2-RELEASE.xctoolchain` and `swift-latest.xctoolchain`, a symlink to it; neither reports `+Asserts`, and the snapshot the existing test defaults to (`swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a`) is not installed. So `theComponentSwitchShapeAgainstAnAssertsCompiler` was not run and the guard fixtures were not checked against an asserts compiler. As a weaker substitute the guard's own fixture file (all four functions) was compiled as a target against this checkout with the 6.4.2 release toolchain, `swift build --target`, debug and release, both exit 0. That exercises SIL generation but not the assertion-only verifier (`verifyLexicalLowering`). The new code has no `Component` whose content is a loop, and `Color.Provider` already had an `indirect` case, so no new shape of the known hazard; this is an inference, not a measurement. Windows CI's 6.4.0+Asserts compiler is the first place it would show.
- Not run: Linux and Windows builds (no portable target changed: every edit is in `Sources/MetalUI`, which `scene-linux` and `root-windows` also build), `Backends/SDL`, the human checks `HY1`..`HY3`.
