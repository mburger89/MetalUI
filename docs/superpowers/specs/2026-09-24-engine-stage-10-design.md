# Engine replacement, stage 10 — `Style`'s CSS fields and the closing check (plan task 7)

Parent design: [`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 row 10, `LR-P`, §8. Rulings `LR-FM`…`LR-FT` in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md)
(next unused `LR-FU`; `LR-FR` is critic round 1's, `LR-FS` lane 1's, `LR-FT` lane 2's).
Record: `docs/record/52-engine-replacement-stage-10.md` (§1 baseline, §2 the
entry measurement).
Instrument: `docs/probes/stage-10-legacy-symbols.txt` (every mangled name the
closing check resolves, each with the command that printed it, and the
macOS/Linux measurement that `dlsym` sees them in the test process).
**No SwiftUI probe**: the stage makes no SwiftUI claim. Nothing a user sees
moves; the one arithmetic fact the design leans on — `Style.border` lowered as
`padding + border` insets, so folding the border into the padding keeps every
rect — is `paddedAndSized`'s own code (`LegacyLowering.swift:582–588` at
`8095fd9`), not a SwiftUI answer.
Branch `feat/engine-stage-10` from `8095fd9`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-10`.

**Status, 2026-09-24 (PDT): designed.** In the design phase no `Sources/` or
`Tests/` file changed in a commit; every scratch patch was applied, built, run
and restored with `git checkout`/`git reset --hard` (and a `swift package
clean` after the scratch move of `Style` across modules — without it a filtered
run died with SIGSEGV, the CLAUDE.md hazard), `git status --short` showing only
this design's files after.

**What this stage is.** Row 10 was written when the lowering was expected to
read no CSS field by now. It does: stage 2 gave `flexGrow`, stretch,
`alignSelf`, `margin`, `justifyContent` and the rest a SwiftUI-backed lowering
(`LR-AB`…`LR-BA`), and the demo leans on it (its `flexGrow` ×11, `alignItems`
×15). So "delete `Style`'s CSS fields" is read field by field (`LR-FM`):

1. **Deleted** — the fields no lowering reads to produce a layout
   (`aspectRatio`, `overflow`: read by nothing; `flexWrap`, `alignContent`:
   read only to be reported) and the one no production code writes
   (`Style.border`: its only public writer was `Box(style:)`), with
   `Position.relative` (read only to be reported), the enums `FlexWrap`,
   `AlignContent`, `Overflow`, and the public modifiers `flexWrap(_:)` and
   `alignContent(_:)`.
2. **Narrowed** — every surviving stored field of `Style` becomes `package`,
   as do `Display` and `JustifyItems`: outside the package `Style` is an opaque
   value (`init()`, `default`, `==`), and an element's layout is spelled only
   through its modifiers — row 10's "`StyledElement.style` narrowed", realised
   by access rather than by a shorter field list.
3. **Moved** — `Style.swift` moves from `MetalUILayout` to `MetalUI`, its only
   reader since stage 9 deleted `LayoutTree`'s placeholder `styles` rows: the
   layout kernel declares no CSS vocabulary at all.

Every `Style`-field report the stage inherited becomes a **permanent refusal
by name** with a trap message that no longer names a finished stage (`LR-FO`),
and the mechanical closing check lands: `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
(`dlsym`, on macOS and Linux, compiled out on Windows), three plain-import
guards, and the recorded grep (`LR-FP`). **It does not pre-empt stage 11**:
`ModifiedElement`/`ModifiedContent` stay separate, legacy `.overlay` and
`.opacity` (G4) are untouched, `deferred.amended` stays stage 11's, and
`Component.width`/`height` keep their meaning.

## Contents

1. [Baseline](#1-baseline)
2. [The entry measurement](#2-the-entry-measurement)
3. [Decisions](#3-decisions)
4. [API and files](#4-api-and-files)
5. [Every stage-10-owned item](#5-every-stage-10-owned-item)
6. [Lanes, and every test by name](#6-lanes-and-every-test-by-name)
7. [What must not move; the demo](#7-what-must-not-move-the-demo)
8. [Exit criteria](#8-exit-criteria)
9. [Handed on](#9-handed-on)

## 1. Baseline

At `8095fd9`, 2026-09-24, in the worktree: `swift build --build-system native
--build-tests` (0 `error:`, one `warning:`, SwiftPM's deprecation notice), then
unfiltered `swift test --build-system native --no-parallel` →
**`Test run with 1411 tests in 3 suites passed`**, the log carrying `FR-J
no-argument frame: succeeded=true`. 0 goldens, **79 guards** (`grep -c
canTypecheck` per file, `Typecheck.swift`'s declaration excluded), eleven gated
tests. Portable targets by `@Test` count: `MetalUICoreTests` 22,
`MetalUILayoutTests` 192, `MetalUICrossPlatformTests` 5.
`MemoryLayout<Style>.size` **226**, `Box<EmptyGroup>` 616,
`MemoryLayout.size(ofValue: demoContent())` **34 808** (built on an 8 MB
`Thread`: the demo needs 528 KB of stack, record §50 §14, above macOS's 512 KB
secondary-thread default).

## 2. The entry measurement

Record §52 §2 has the commands and the raw lists; in short:

- **The field inventory** (§52 §2.1): every `Style` field's readers and
  writers in `Sources`, `Tests`, `Backends/SDL`, `Tests/PortableTests`,
  `Experiments`, `docs/probes`. `MetalUILayout` reads **no** `Style` field
  since stage 9; `MetalUI` reads every field except `aspectRatio` (0 readers)
  and `overflow` (1 writer, `ScrollView.swift:321`, commented inert);
  `flexWrap`/`alignContent` are read only by `legacyContainerDiagnostics`;
  `Position.relative` only by `legacyLeafDiagnostics`; `Style.border` has **no
  production writer** (`Box.swift`'s `border(_:width:)` family writes
  `Decoration.border`; `AnimatedStyle.swift:389` copies). `Backends/SDL`,
  `Tests/PortableTests` and `Experiments` name no `Style` member; the
  `docs/probes/modifier-composition-skeletons/*.swift` files declare their own
  `Style` and are not compiled against `MetalUI`.
- **The deletion, in scratch** (§52 §2.2): the four fields, the three enums,
  `Position.relative` and the two modifiers → **7 errors in 2 `Sources` files**
  (`LegacyLowering.swift` 5, `ScrollView.swift` 2), then with those patched
  **40 test errors in 10 files** (`StyleTests.swift` 5 and 35 in nine
  `MetalUITests` files). `Style.border` alone → 14 errors in 2 `Sources` files
  (`AnimatedStyle.swift` 9, `LegacyLowering.swift` 5), then **29 test errors
  in 8 files** (`StyleTests.swift` 1 and 28 in seven). The union is §6's
  lane-1 file list.
- **The narrowing, in scratch** (§52 §2.3): every `public var` in `Style` →
  `package var`: **0 errors**; unfiltered suite `1411 tests in 3 suites
  passed`, FR-J line present (the guards ran). A plain-import fixture
  `var s = Style(); s.flexGrow = 1` fails with **"'flexGrow' is inaccessible
  due to 'package' protection level"**; the package accessor is still an
  exported symbol (`T _$s13MetalUILayout5StyleV8flexGrowSfvg`).
- **The move, in scratch** (§52 §2.4): `git mv` of `Style.swift` into
  `Sources/MetalUI/` → 17 errors, all in `Tests/MetalUILayoutTests/StyleTests.swift`;
  with that file moved to `Tests/MetalUICrossPlatformTests/` and its import
  changed, 0 errors and `1411 tests in 3 suites passed`.
- **`dlsym` in the test process** (§52 §2.5, the instrument file's block E):
  on macOS under both build systems and in a `swift:6.4-noble` container, a
  `Style` accessor, `LayoutPass.requestNativeLeaf` and `Frame.requestNativeLeaf`
  resolve and stage 9's `computeLayout` does not.
- **Size** (§52 §2.6): `MemoryLayout<Style>.size` **226 → 210** with the four
  fields and `.relative` gone, **→ 178** with `border` gone too (a standalone
  `swiftc -Onone` build of `MetalUICore`'s sources plus each `Style.swift`
  variant): 48 bytes off every `Style` a tree value carries.

## 3. Decisions

| question | answer | ruling |
|---|---|---|
| which fields are "CSS fields"? | those no lowering reads to lay out, plus one no production code writes: `aspectRatio`, `overflow`, `flexWrap`, `alignContent`, `border`, and `Position.relative` | `LR-FM` item 1 |
| the fields the lowering reads? | kept, `package`: their meaning is the lowering's SwiftUI answer | `LR-FM` item 2 |
| `StyledElement.style` narrowed? | by access: `Style` opaque outside the package; the requirement stays `Style { get set }` | `LR-FM` item 2 |
| where does `Style` live? | `MetalUI`; `MetalUILayout` declares no `Style` | `LR-FM` item 3 |
| each public API change | removed/narrowed/unchanged, each with its migration spelling | `LR-FN` |
| the eight deprecated sizing modifiers, the `fraction:`/`percent:` spellings | unchanged (their fields survive) | `LR-FN` item 5 |
| every inherited `Style`-field report | a permanent refusal by name; the trap message names a live owner or none | `LR-FO` items 1–3 |
| `position`/`inset` outside a `Deferred`, `inset` on a static box, `…absolute` | permanent refusals | `LR-FO` item 2 |
| the public spelling of a presentation's insets | unchanged: `.position(.absolute).inset(…)` inside a `Deferred` | `LR-FO` item 4 |
| `Style()` writes in tests | writes of a surviving field stay; writes of a deleted one move or retire | `LR-FO` item 5 |
| `CSSSizing.swift` | kept, doc amended (its fields survive) | `LR-FO` item 6 |
| `LegacyLowering` name | kept | `LR-FO` item 7 |
| the closing check | `dlsym` test (macOS + Linux; compiled out on Windows), three guards, the grep | `LR-FP` |
| lanes | two, in order; the deletion in the last | `LR-FQ` |
| `Box(style:)`'s `style:` parameter once every field is `package` | kept, inert outside the package; a record §05 row; removal handed to task 15 | `LR-FR` F5 |
| the closing check after the move | every block-A/B name whose mangling names a type the stage moves gets its `MetalUI` twin (block C 4 → 12; 30 absent names); two restore-a-symbol mutations | `LR-FR` F1–F2 |

## 4. API and files

### 4.1 `Style` after the stage (`Sources/MetalUI/Style.swift`, moved)

```swift
package enum Display: Sendable, Equatable { case flex, stack, none }
public enum Position: Sendable, Equatable { case `static`, absolute }         // .relative deleted
public enum FlexDirection: Sendable, Equatable { … }                           // unchanged
public enum AlignItems: Sendable, Equatable { … }                              // unchanged (.baseline: task 11)
package enum JustifyItems: Sendable, Equatable { case start, center, end, stretch }
public enum AlignSelf: Sendable, Equatable { … }                               // unchanged
public enum JustifyContent: Sendable, Equatable { … }                          // unchanged
// FlexWrap, Overflow, AlignContent: deleted.

public struct Style: Sendable, Equatable {
    package var display: Display = .flex
    package var position: Position = .static
    package var inset: Edges<Dimension> = Edges(all: .auto)
    package var size: Size<Dimension> = …
    package var minSize: Size<Dimension> = …
    package var maxSize: Size<Dimension> = …
    package var margin: Edges<Dimension> = …
    package var padding: Edges<Length> = …
    package var flexDirection: FlexDirection = .row
    package var gap: Axes<Length> = …
    package var justifyContent: JustifyContent? = nil
    package var alignItems: AlignItems? = nil
    package var justifyItems: JustifyItems? = nil
    package var flexGrow: Float = 0
    package var flexShrink: Float = 1
    package var flexBasis: Dimension = .auto
    package var alignSelf: AlignSelf? = nil
    public init() {}
    public static let `default` = Style()
}
// aspectRatio, overflow, flexWrap, alignContent, border: deleted.
```

The type's doc comments are rewritten for the one engine (every
`positionStackItems`/WebKit/fixture citation is history since stage 9).

### 4.2 Public API, each change (`LR-FN`)

| API | change | migration |
|---|---|---|
| `StyledElement.flexWrap(_:)`, `FlexWrap` | **removed** | none — delete the call. A wrapping line has no lowering (reported `flexWrap`, a production trap since stage 6b); lay rows out explicitly, or use `Grid` |
| `StyledElement.alignContent(_:)`, `AlignContent` | **removed** | none — delete the call (it placed wrapped lines; reported, a trap since 6b) |
| `Position.relative` | **removed** | delete `.position(.relative)`: the window is the only containing block (`LR-FF`); reported, a trap since 6b |
| `Overflow`, `Style.overflow`, `Style.aspectRatio` | **removed** | none — read by nothing (CLAUDE.md's inert rows); clipping is `.clipped()`, scrolling is `ScrollView` |
| `Style.border` | **removed** | `.padding(_:)` for the inset (the lowering added it to the padding); `.border(_:width:)` paints (it never did through `Style`) |
| every other `Style` stored field | **`package`** | the element's modifier: `hidden()`/`Stack` (`display`); `.position(_:)`/`.inset(_:)`; `.frame(…)` (`size`/`minSize`/`maxSize`); `.margin(_:)`; `.padding(_:)` (a layer, `MC-A`); `Row`/`Column`/`.flexDirection(_:)`; `.gap(_:)`; `.justifyContent(_:)`; `.alignItems(_:)`; `Stack(alignment:)`/`.frame(alignment:)` (`justifyItems`); `.flexGrow`/`.flexShrink`/`.flexBasis`/`.alignSelf` |
| `Display`, `JustifyItems` | **`package`** | no public writer remained; `Stack`, `hidden()`, `.frame(alignment:)` |
| `Style` (the type) | **moves** `MetalUILayout` → `MetalUI`; `init()`, `default`, `==` stay public | `import MetalUI` (which re-exports `MetalUILayout`, so an app's imports do not change) |
| `Box(style:decoration:…)` and `Stack`'s, every `public var style` | **unchanged** | — but **inert outside the package** (`Style()` is the only value an external caller can pass, so the parameter configures nothing; `decoration:` is a separate parameter and unaffected). Kept, with a declared-but-inert row (record §05, Record phase) and removal handed to task 15 (`LR-FR` F5) |
| `width(_:)`, `height(_:)`, `min*`/`max*` (deprecated, stage 8), `width(fraction:)`/`height(fraction:)` and their `percent:` renames, `flexBasis(fraction:)`/`flexBasis(percent:)` | **unchanged** | not this stage's (`LR-FN` item 5) |

### 4.3 `UnlowerableField`'s owner (`Sources/MetalUI/LayoutAuthority.swift`, `LR-FO` item 3)

`owningStage: String` becomes `owner: String?`:

- `site == .deferred` → `"plan task 7, stage 11"` (`deferred.amended`, `LR-FF`);
- `field` has the prefix `alignItems.baseline` or `alignSelf.baseline` →
  `"plan task 11"` (baselines, parent spec §8);
- everything else → `nil`: a **permanent refusal**.

`trapMessage` reads `"MetalUI: <site>.<field> has no proposal lowering
(<owner>); a tree containing it cannot run under the proposal layout
authority."` for an owned entry and `"MetalUI: <site>.<field> has no proposal
lowering and is refused by name (plan task 7, LR-FO); a tree containing it
cannot run under the proposal layout authority."` for a permanent one. The
prefix `"MetalUI: <site>.<field> has no proposal lowering"` every existing
`stderr` assertion reads is unchanged.

### 4.4 Files

**Lane 1** (tests, plus one `Sources` file): `Sources/MetalUI/LayoutAuthority.swift`;
`Tests/MetalUITests/{AbsoluteOverlayTests, AnimationTests, CSSSizing,
GoldenReplacementFlexTests, GoldenReplacementStackTests, LayoutAuthorityTests,
LoweringBoxModelTests, LoweringContainerTests, LoweringLeafTests,
LoweringScrollTests, LoweringStackAndLayerTests, ModifierTests,
PresentationContainingBlockTests, PresentationLoweringTests}.swift`.

**Lane 2** (the deletion): `Sources/MetalUILayout/Style.swift` →
`Sources/MetalUI/Style.swift`; `Sources/MetalUI/{Box, LegacyLowering,
AnimatedStyle, ScrollView}.swift` (the deleted fields' readers, writers and doc
comments); doc comments naming a deleted field anywhere else in `Sources/`
(`grep -rnE 'flexWrap|alignContent|aspectRatio|Overflow|\.relative|Style\.border'
Sources` at lane 2's base — comments only, found by the lane);
`Tests/MetalUILayoutTests/StyleTests.swift` → `Tests/MetalUICrossPlatformTests/StyleTests.swift`;
new `Tests/MetalUICrossPlatformTests/LegacyEngineSymbolTests.swift`; new
`Tests/MetalUITests/StyleSurfaceCompileGuards.swift`;
`docs/probes/stage-10-legacy-symbols.txt` (block C's predicted names
corrected if a mutant prints otherwise). No file is in both lanes.

## 5. Every stage-10-owned item

| item (source) | disposition |
|---|---|
| `Style`'s CSS fields (parent row 10) | `LR-FM`: five deleted, the rest `package`, the type moved — lane 2 |
| `StyledElement.style` narrowed (row 10) | by access (`LR-FM` item 2) — lane 2 |
| the `Style()` writes of CSS fields in tests (`LR-ER` item 6, record §50 §2: 232 lines, 50 files at stage 8) | a write of a surviving field stays (package-visible to every in-package test, `@testable` or not); a write of a deleted field is moved or retired (§6, lane 1) — `LR-FO` item 5 |
| `CSSSizing.swift` (stage 8, `LR-EW`, `LR-FB`) | kept; its "die at stage 10" sentence corrected (`Style.size`/`minSize`/`maxSize` survive) — `LR-FO` item 6, lane 1 |
| `position`/`inset` outside a `Deferred` (§29, `LR-CK`) | permanent refusal — `LR-FO` item 2, lane 1 |
| `Position.relative` (§29) | deleted — lane 2 (its report arms moved off in lane 1) |
| `inset` on a static box (§29) | permanent refusal — `LR-FO` item 2 |
| the public spelling of a presentation's insets (§29) | unchanged — `LR-FO` item 4 |
| `…absolute` (§29, re-owned to 10 by stage 8's `LR-EZ` item 3) | permanent refusal — `LR-FO` item 2 |
| `LR-ER` item 4's families: percentages, a non-greedy `maxSize`, a length `flexBasis`, a floored `space-*`, a root's auto-axis min/max and margin, `…absolute` on a `Style`-written box; `LR-AQ`'s `…unconsumed` item fields; `flexGrow.weights` (7a's "the field is stage 10's") | permanent refusals — `LR-FO` item 1 |
| `border.percent`, `flexWrap`, `alignContent`, `position` from `.relative` | deleted with their fields (lane 2); no test reads them after lane 1 |
| `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` (`LR-P` item 0, stage 9 §9) | lane 2, N2.1 (`LR-FP`) |
| plain-import guards (`LR-P` item 1) | lane 2, G1–G3 (`LR-FP` item 5) |
| the recorded grep (`LR-P` item 3) | §8 item 1 |
| `LegacyLowering`'s name (stage 9 §9) | kept — `LR-FO` item 7 |
| `StyleTests.defaultStyleMatchesCSSInitialValues` (7b's K row, `LR-EE`: "until stage 10 deletes its CSS fields") | kept, T (its deleted-field lines go; it moves with the type) — lane 2 |
| divergence 52 | not stage 10's: plan task 15 (`LR-EY` items 1–2); untouched |

## 6. Lanes, and every test by name

Two lanes, in order 1 → 2, on one branch (`LR-FQ`). Lane 1 changes one
`Sources` file; lane 2 changes no test outside its list. Each lane's head is
green (unfiltered suite, 0 `error:`, only SwiftPM's notice as `warning:`),
except lane 2's red-first commit (N2.1 and G1–G3 before the deletion, stage 9's
N3.1 precedent). Every mutation: commit first, restore from a copy, full
unfiltered suite, `git status --short` after, name every test reddened. Every
removed `@Test` is a row (R replaced by a named test; D a deleted concept
named; T kept and changed — re-spelled, renamed, arms removed — never a
retained expected value re-valued except where the row says the value was the
deleted field's own) in the lane's record section; before − removed + added =
after is read off the summary line.

### Lane 1 — every test that names a deleted field, moved off it; the reports made permanent (`LR-FO`)

Sources: `LayoutAuthority.swift` only (§4.3). No field is deleted yet: every
re-spelling below compiles and passes against the old `Style`.

**New test**

- **N1.1** `everyReportNamesALiveOwnerOrIsRefusedByName` (`LayoutAuthorityTests.swift`):
  a table of every `(site, field)` the lowering can raise at lane 1's head
  **except** the three lane 2 deletes (`flexWrap`, `alignContent`,
  `border.percent`) — the container rows (`gap.percent`,
  `alignItems.baseline`), the leaf rows (`size.percent`, `padding.percent`,
  `position`, `inset`), the item rows (`flexGrow.weights`, `flexGrow`,
  `flexShrink`, `flexBasis`, `alignSelf.baseline`, `minSize.percent`,
  `maxSize.percent`, `maxSize`, `margin.percent`,
  `justifyContent.spaceBetween`/`spaceAround`/`spaceEvenly`), the presentation
  rows (`minSize.absolute`, `maxSize.absolute`), each `<field>.unconsumed` the
  unconsumed report can raise, and `deferred.amended`, crossed with the sites
  that raise each (found by grepping `entry(`, `reports.append(`,
  `names.append(` and `UnlowerableField(` in `LegacyLowering.swift`,
  `LoweringState.swift`, `Component.swift`, `Deferred.swift`; `try #require`
  on the table's count). Asserts `owner` per §4.3 and that each `trapMessage`
  contains its owner text, or the permanent text and no `"stage "`.
  **Red before**: `owner` does not exist (build); with a scratch `owner` that
  forwards to the old `owningStage`, every permanent row reads a stage number.
  **Mutation M1a** (the `nil` arm returns `"plan task 7, stage 10"` for a
  `position`/`inset` field): reddens N1.1 and T1.1.

**T rows (kept, changed)**

| # | test (file) | change | why the answer holds |
|---|---|---|---|
| T1.1 | `anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame` (`AbsoluteOverlayTests`) | the `stderr` literal: `"(plan task 7, stage 10)"` → the permanent text | the trap and its field are unchanged; only the owner clause |
| T1.2 | `aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName` (`PresentationLoweringTests`) | the "inside a `.relative` ancestor" arm removed; the `owningStage == "10"` check → `owner == nil` | the arm's field is deleted in lane 2; the `.absolute` owner is now permanent |
| T1.3 | `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable` (`LoweringScrollTests`, its `owningStage == "3"` line) | → `owner == nil` | `flexGrow.weights` at `scrollView` is permanent; the site stays reachable, which is the test's subject |
| T1.4 | `aPresentationsContainingBlockIsTheWindowWhateverSurroundsIt` (`PresentationContainingBlockTests`) | the two bordered styles → the same widths as `padding`; its `owningStage == "11"` line → `owner == "plan task 7, stage 11"` | a root's surroundings do not move a presentation; padding is a surrounding as the border was (every rect is the window's); the amended entry's owner is unchanged, only spelled |
| T1.5 | `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (`LayoutAuthorityTests`) | each `.position(.relative)` arm → `.inset(px(1))` on the static element, expecting `inset`; the inner-layer arm → `Box().padding(px(4)).cssWidth(fraction: 0.5).padding(px(8)).inset(px(3))`, expecting `[modifierLayer.size.percent, modifierLayer.inset]` | the test is about every SITE reporting by name, not about `position`; `inset` on a static box and `size.percent` are leaf rows every site runs |
| T1.6 | `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (`LoweringLeafTests`) | the `border.percent` and `position` (`.relative`) rows removed; the combined "padding and border percent" arm → "size and padding percent", expecting `["size.percent", "padding.percent"]` | the two rows' fields are deleted; the combined arm keeps "two entries, in table order" |
| T1.7 | `everyContainerFieldIsIgnoredOnALoweredLeaf` (`LoweringLeafTests`) | the `flexWrap.wrap`, `alignContent.spaceAround`, `aspectRatio`, `overflow.hidden` rows removed | deleted fields |
| T1.8 | `everyContainerFieldEitherLowersOrIsReportedByName` (`LoweringContainerTests`) | the `wrap` and `alignContent` arms removed; the "border percent on a container" arm → "padding percent on a container", expecting `[box.padding.percent]` | deleted fields; the every-node row stays represented |
| T1.9 | `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst` (`LoweringContainerTests`) | `fourFieldContainer`: `flexWrap = .wrap` → `alignItems = .baseline`, `position = .relative` → `size.width = .percent(0.5)`; expected `[gap.percent, alignItems.baseline, size.percent, inset]`; the trap still names `box.gap.percent` | two container rows then two every-node rows, as before (**V2** still discriminates) |
| T1.10 | `aLoweredStackPlacesFixedChildrenAtAllNineAlignments` (`LoweringStackAndLayerTests`) | `.flexWrap(.wrap).alignContent(.center)` removed from the `ignoring` arm | deleted modifiers; the arm keeps its other ignored container fields |
| T1.11 | `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` (`ModifierTests`) | the `alignContent(_:)` and `flexWrap(_:)` cases removed (its count literal −2) | deleted modifiers |
| T1.12 | `percentagesStillReportByNameWithTheirOwner` (`LoweringBoxModelTests`) | the `border.percent` arm removed (`#require(arms.count == 7)`) | deleted field |
| T1.13 | `paddingAndBorderInsetTheContentBoxEdgeByEdge` (`GoldenReplacementFlexTests`) | every `border = B` folded into `padding = P + B` edge by edge; literals unchanged | `paddedAndSized` inset each edge by `padding + border` |
| T1.14 | `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder` (`GoldenReplacementStackTests`) | fold as T1.13 | as T1.13 |
| T1.15 | `aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding` (`GoldenReplacementStackTests`) | fold as T1.13 | as T1.13 |
| T1.16 | `allTwentyEightAnimatableFieldsInterpolateAndLeaveInFlightOnSettle` → **renamed** `allTwentyFourAnimatableFieldsInterpolateAndLeaveInFlightOnSettle` (`AnimationTests`) | the four `border.*` keys removed from its table, `animatableFieldOrder` and `allAnimatableFields` (`expectedKeys.count == 24`); the `aspectRatio` differing-fixture arm removed with its doc | `Style.border` is deleted (its animation with it, lane 2); `aspectRatio` was the only non-animatable numeric field, and goes |

**D rows (retired)**

| # | test (file) | deleted concept | replacement |
|---|---|---|---|
| D1.1 | `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` (`GoldenReplacementStackTests`) | **wrap** (`flex-wrap`, a 7a D pin, `LR-DY`) — now unspellable | G2 (lane 2) pins that neither `flexWrap(_:)` nor `FlexWrap` exists |
| D1.2 | `aStyleBorderLowersAsInsetsInsideTheDeclaredSize` (`LoweringBoxModelTests`) | **`Style.border`** — CSS border widths with no production writer (`LR-FM` item 1) | the inset arithmetic it pinned is `padding`'s, pinned by T1.13–T1.15; G2 pins `Style.border`'s absence |

`CSSSizing.swift`: doc comment only (`LR-FO` item 6).

**Lane 1's count**: removed 3 names (D1.1, D1.2, T1.16's old name), added 2
(N1.1, T1.16's new name): **1411 − 3 + 2 = 1410**. Guards 79, unchanged.

**Mutations** (besides M1a):

- **M1b** `paddedAndSized`'s `inset(_:_:)` returns `resolvedLength(border)`
  only (the padding dropped): must redden T1.13–T1.15 (they now carry the
  border's widths as padding); the lane names every test it reddens. **Not
  T1.4** (`LR-FR` F4): its arms assert the presentation's hitbox
  `cbBounds(185, 85, 10, 10)` whatever the root's surroundings, so no inset
  mutation can redden it — that insensitivity is its subject.
  **Amended, lane 1 (`LR-FS` item 1): measured, M1b reddens T1.13 and T1.15
  but not T1.14** — T1.14's boxes have no content, so an inset moves no rect
  it asserts; its subject is the floor. **M1b′** (the stretched axis's
  `lo` floored at the item's padding + border, stage 9's M2f re-run on the
  folded fixture) reddens T1.14 alone.
- **M1c** (**V2**, re-run on the re-spelled fixture) `legacyLeafDiagnostics(…)
  + fields`: reddens T1.9.
- **M1d** the leaf `inset` row deleted from `legacyLeafDiagnostics`: reddens
  T1.5 (every site's arm) and N1.1. **Amended, lane 1 (`LR-FS` item 2):
  measured, M1d reddens T1.5 (all six `inset` arms), T1.6 and T1.9, and
  not N1.1** — N1.1 is a static `(site, field)` table checking each entry's
  `owner` and trap text; it never runs the lowering, so deleting a report row
  cannot reach it. M1a is N1.1's instrument.
- The site-coverage rule (stage 9 `LR-FH` item 2) at the head: every test that
  exercised a lowering site at `8095fd9` still does, less the two D rows.

### Lane 2 — the deletion, the narrowing, the move, and the closing check (`LR-FM`, `LR-FN`, `LR-FP`)

**Commit 1, red first**: N2.1, G1, G2, G3 added — the suite reads **1414
tests with 4 failing** (N2.1 at its positive-control `#require`; G1: the
fixture compiles; G2: the fixtures compile; G3: `Style` is found in
`MetalUILayout`). **Commit 2**: the deletion, `swift package clean`, all
green.

**New tests**

- **N2.1** `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
  (`Tests/MetalUICrossPlatformTests/LegacyEngineSymbolTests.swift`, the whole
  file inside `#if canImport(Darwin) || canImport(Glibc)`): `dlsym(RTLD_DEFAULT,
  name)` (`UnsafeMutableRawPointer(bitPattern: -2)` on Darwin, `nil` on Glibc)
  over the instrument file's lists, the names written into the test with a
  comment naming the file and each block's command. `try #require` that every
  **positive control** (block D, five names) resolves and that the absent list
  has its literal count (block A 7 + B 11 + C 12 = **30**, `LR-FR` F1), then `#expect` each
  absent name resolves `nil`, naming it. No `.enabled(if:)`, no early return:
  it cannot skip; a broken instrument fails the positive controls.
  **Red before** (commit 1): the positive-control `#require` fails — block D's
  `$s7MetalUI5StyleV8flexGrowSfvg` does not exist until the move — and, with
  that control set aside in scratch, the eleven block-B names resolve (the lane
  records both readings).
  **Mutations**: **M2a** `public var flexWrap: FlexWrap` and `enum FlexWrap`
  re-added to the moved `Style` (+ `StyledElement.flexWrap(_:)`) → N2.1 naming
  block C's three `MetalUI`-module twins — the getter
  `$s7MetalUI5StyleV8flexWrapAA04FlexE0Ovg`, the modifier
  `$s7MetalUI13StyledElementPAAE8flexWrapyxAA04FlexF0OF` and the accessor
  `$s7MetalUI8FlexWrapOMa` — and G2. **Not block B's modifier name**: block B
  spells `FlexWrap` as `MetalUILayout`'s, which a re-add after the move cannot
  export (`LR-FR` F1). The lane confirms the three with `nm` on the mutant. **M2c** `Style.swift` moved back
  to `MetalUILayout` → N2.1 (block B's `$s13MetalUILayout5StyleV8flexGrowSfvg`
  resolves; block D's `$s7MetalUI5StyleV8flexGrowSfvg` does not) and G3.
  **Amended, lane 2 (`LR-FT` item 2): measured, N2.1 reports only the
  positive control** — its first `try #require` ends the test before the
  absent loop; block B's name is exported by the mutant (`nm`), not reported.
  **M2d** the resolver returns `false` for every name → N2.1's positive-control
  `#require` (and nothing else).
  **M2f** (`LR-P` item 0's "restore a symbol", `LR-FR` F2) after the move,
  `public func requestNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID
  { fatalError() }` re-added to `LayoutPass` in `MetalUI` → N2.1 names block C's
  `$s7MetalUI10LayoutPassV11requestNode5style8children0A8UILayout0cF2IDVAA5StyleV_SayAIGtF`
  (and would read green without F1: block A's spelling encodes
  `MetalUILayout.Style`). **M2g** `enum LayoutAuthority { case proposal }`
  re-added to `MetalUI` → N2.1 names `$s7MetalUI15LayoutAuthorityOMa`; if the
  unused enum's accessor is not emitted, the lane gives it a stored use and
  records which (**measured, lane 2, `LR-FT` item 3: emitted with no stored
  use**). Block A's `computeLayout` and both `requestLeaf` names
  **cannot be re-exported by any source** — their signatures name
  `AvailableSpace`, deleted by stage 9 — so those three rows are a record of
  the deletion, not a tripwire; a re-added engine under a new signature is the
  renamed-entry-point case the guards and grep cover (`LR-FP` item 3).
- **G1** `aPlainImportCannotWriteAStyleField` (`StyleSurfaceCompileGuards.swift`,
  `typecheckFile`, `SA-P`): the fixture `var s = Style(); s.flexGrow = 1`
  fails with `'flexGrow' is inaccessible due to 'package' protection level`;
  the control `Box().flexGrow(1)` compiles; `#require` that they disagree.
  **Red before** (commit 1): the fixture compiles. **Mutation M2b**
  `Style.flexGrow` made `public` → G1 alone.
- **G2** `theDeletedStyleSpellingsDoNotCompile`: one negative fixture per
  spelling — `Box().flexWrap(.wrap)`, `Box().alignContent(.center)`,
  `Box().position(.relative)`, `let _: FlexWrap? = nil`, `let _:
  AlignContent? = nil`, `let _: Overflow? = nil`, `_ = Style().border` — each
  expected to fail with its own message (`has no member`, `cannot find type`,
  recorded by the lane); the control
  `Box().position(.absolute).inset(Pixels(0)).alignItems(.center).flexBasis(Pixels(0))`
  compiles. **Red before**: every fixture compiles. **Mutation**: M2a (the
  `flexWrap` fixture compiles).
- **G3** `theLayoutKernelDeclaresNoStyle`: `import MetalUILayout` with
  `let _ = MetalUILayout.Style()` fails (`module 'MetalUILayout' has no member
  named 'Style'` or the message the lane records); the control, the same line
  under `import MetalUI` without the module qualifier, compiles.
  **Red before**: the negative compiles. **Mutation**: M2c.

**T rows**

| # | test (file) | change |
|---|---|---|
| T2.1–T2.4 | `defaultStyleMatchesCSSInitialValues`, `defaultStaticIsExactlyTheMemberwiseDefault`, `flexDirectionKnowsItsAxis`, `styleIsValueSemantic` (`StyleTests`, moved to `MetalUICrossPlatformTests`) | `@testable import MetalUILayout` → `@testable import MetalUI`; `defaultStyleMatchesCSSInitialValues` loses its five deleted-field lines. Names unchanged |

**Lane 2's count**: added 4 (N2.1, G1–G3), removed 0: **1410 + 4 = 1414**.
Guards 79 → **82**. Portable targets: `MetalUICoreTests` 22,
`MetalUILayoutTests` 192 − 4 = **188**, `MetalUICrossPlatformTests` 5 + 4 + 1
= **10** on macOS and Linux, **9** on Windows (N2.1 compiled out).

**Also in lane 2** (no new test; pinned by existing ones):

- The animated `border` arm leaves `animated(_:_:for:pass:)`; the other 23
  `Style` keys keep animating — `allTwentyFourAnimatableFieldsInterpolateAndLeaveInFlightOnSettle`,
  `everyRegisteringSiteAnimatesItsStyle`, `everyBackgroundPaintingSiteAnimatesItsColour`
  green unedited. **Mutation M2e** `newStyle.padding = …` deleted from
  `animated` → reddens T1.16's test (the lane names the rest).
- `paddedAndSized`'s inset becomes `resolvedLength(padding)`; the
  `border.percent`, `flexWrap`, `alignContent` and `.relative` report lines go;
  `ScrollView`'s `viewportStyle.overflow` write goes.
- `swift package clean` after the move (measured necessary in the design: a
  stale object gave a SIGSEGV).

## 7. What must not move; the demo

- **Production behaviour and pixels**: `docs/probes/demo-pixels/compare.sh
  <scratch> 8095fd9 <lane head>` reads **0 differing, scene identical, in all
  fourteen images** at both lanes' heads (the stage-9 harness copy is chosen
  for both commits; lane 1 changes only a trap message's text in `Sources`).
  No production tree writes a deleted field: the demo's one `Box(style:)`
  (`chrome`, `DemoContent.swift:302–305`) writes `flexDirection`, `gap`,
  `padding`, `alignItems`, all kept. `theDemoFrameMatchesTheValuesRecordedOnMacOS`
  green with `Expected.swift` unedited.
- **The Windows stack budget**: `everyProductionTreeBuildsOnAOneMegabyteThread`
  green; lane 2 records `MemoryLayout<Style>.size` (226 at `8095fd9`, 178
  predicted by §2) and `MemoryLayout.size(ofValue: demoContent())` (34 808) at
  its head, on an 8 MB thread — both must not grow, and are expected to shrink
  by 48 bytes per `Style` a value carries (every `Box`, `Text`, `Stack` and
  modifier layer).
- **Identity, hit testing, accessibility, animation, focus, the scrim, `List`
  windowing, `Deferred` presentations**: no lowering changes but the deleted
  fields' branches, which no production tree reaches. Pinned by the suite
  unedited outside §6's lists.
- **`MetalUILayout` imports only `MetalUICore`** (`grep -h '^import'
  Sources/MetalUILayout/*.swift | sort -u` one line) **and declares no
  `Style`** (`grep -rn 'Style' Sources/MetalUILayout` prints only history
  comments, which the lane lists).
- **0 `warning:`** besides SwiftPM's notice on both build systems.
- **Linux and Windows CI**: lane 2 builds `Backends/SDL` (`python3
  Backends/SDL/scripts/fetch-accesskit.py`, then
  `PKG_CONFIG_PATH=$PWD/.accesskit swift build --build-tests` and `swift
  test`; `PortableReplay`/`DemoCapture` green unedited), `Tests/PortableTests`
  (`swift build --build-tests`, 18 + 6 + 5), and in a `swift:6.4-noble`
  container `swift build --build-tests` plus
  `swift test --filter 'MetalUICoreTests|MetalUILayoutTests|MetalUICrossPlatformTests'`,
  reading **22 + 188 + 10** (N2.1 green there — the Linux run is what shows the
  closing check off Apple).
- **Depth**: `NativeLayoutRun.maxDepth` 72 and the depth tests unchanged.

## 8. Exit criteria

1. **The recorded grep** (`LR-P` item 3, widened): `grep -rn
   "FlexEngine\|computeLayout(\|requestNode(style" Sources` prints only the
   history comments record §51 §7.7 lists; `git ls-files 'Tests/*.json' | wc -l`
   reads 0 (the `LR-P` item 3 spelling, `find Tests -name "*.json" | wc -l`, is
   recorded beside it: both read 0 at `8095fd9` in the worktree, but `find`
   also counts `Tests/PortableTests/.build`'s JSON build artifacts once that
   package has been built, CLAUDE.md's goldens bullet — `LR-FR` F6); `grep -rnE 'flexWrap|alignContent|aspectRatio|\bOverflow\b|\.relative\b|FlexWrap|AlignContent' Sources Tests/MetalUITests Tests/MetalUICrossPlatformTests Tests/MetalUILayoutTests`
   prints only G2's and N2.1's fixtures/names, the proposal `.aspectRatio(_:)`
   modifier family (`NativeElements`, `NativeModifiedContent`, `LayoutTree`,
   `ProposalLayout` and their tests — a SwiftUI modifier, not the `Style`
   field), and history comments the record lists; `grep -rn 'Style' Sources/MetalUILayout`
   prints only history comments.
2. Unfiltered `swift test --build-system native --no-parallel` → **`Test run
   with 1414 tests in 3 suites passed`** (or the lanes' re-derived figure, with
   its equation), FR-J line present; **82 guards**; 0 goldens; eleven gated
   tests, unchanged.
3. 0 `error:`, 0 `warning:` besides SwiftPM's notice, on `swift build
   --build-system native --build-tests` **and** `swift build --build-tests`.
4. The fourteen-image comparison against `8095fd9`: 0 differing, scene
   identical; `DemoFrameDeterminismTests` and `DemoStackBudgetTests` green
   unedited; `Backends/SDL`'s `PortableReplay`/`DemoCapture` green;
   `Tests/PortableTests` builds and passes; the Linux container's three targets
   pass at 22 + 188 + 10.
5. N1.1, N2.1, G1–G3 green; every named mutation reddened what §6 names.
6. Every removed `@Test` has a row; **1411 − 3 + 2 + 4 = 1414**.

## 9. Handed on

- **To stage 11** (unchanged by this stage): `ModifiedElement`/`ModifiedContent`
  unification, legacy `.overlay`, `.opacity` G4, `deferred.amended` with
  `Component.width` over a presentation member.
- **To plan task 15** (closeout): divergence 52; whether the eight
  deprecated sizing modifiers and the `fraction:` spellings are removed
  (`LR-FN` item 5); whether `Box(style:)`/`Stack`'s public `style:`
  parameter, inert outside the package after this stage, is deprecated or
  removed (`LR-FR` F5); whether any permanent refusal of `LR-FO` item 1 becomes a
  compile error by narrowing its modifier's parameter type.
- **To the Record phase** (not before): CLAUDE.md/AGENTS.md — the counts
  (suite, guards 82, portable CI 22 + 188 + 10 and Windows' 9), `LR-` next
  unused, the "Eight constraints" (`MetalUILayout` declares no `Style`), the
  `Legacy .frame`/`Sizing modifiers`/`StyledElement` paragraphs where they
  describe `Style` as public, the Animation paragraph's field count, a stage-10
  alignment bullet, the CI hazards (N2.1 compiled out on Windows); record §04
  (no divergence number moves; re-read 9, 10 and 54 for the permanent-refusal
  wording), record §05 (delete the `Style.aspectRatio`/`overflow`,
  `Style.border` on a container, and `Position.relative` offset rows; the
  `margin: .auto` row becomes package-only; **add** a row for the public
  `style:` parameter of `Box`'s three initialisers, inert outside the package,
  `LR-FR` F5), record README (§52), the parent
  spec's §4.1 row 10 status, the plan's task 7 note.
