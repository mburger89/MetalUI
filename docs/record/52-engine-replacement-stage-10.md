# §52 — Engine replacement, stage 10: `Style`'s CSS fields and the closing check

Spec `docs/superpowers/specs/2026-09-24-engine-stage-10-design.md`; rulings
`LR-FM`…`LR-FQ` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`;
instrument `docs/probes/stage-10-legacy-symbols.txt`. Branch
`feat/engine-stage-10` from `8095fd9`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-10`.

## 1. Baseline at `8095fd9` (2026-09-24, PDT)

`swift build --build-system native --build-tests`: 0 `error:`, one
`warning:` (SwiftPM's deprecation notice). Unfiltered `swift test
--build-system native --no-parallel`: **`Test run with 1411 tests in 3 suites
passed after 76.551 seconds.`**, the log carrying `FR-J no-argument frame:
succeeded=true`. 79 guards, 0 goldens, eleven gated tests. `@Test` counts of
the portable targets (`git grep -h "@Test" -- Tests/<target> | wc -l`):
`MetalUICoreTests` 22, `MetalUILayoutTests` 192, `MetalUICrossPlatformTests` 5
(the two `DemoStackBudgetTests` came with PR #30 at the stage-9 merge).

## 2. The entry measurement (design, 2026-09-24)

Every scratch patch below was applied in the worktree, built, run and restored
(`git checkout Sources Tests` or `git reset --hard`); the patch of §2.2–§2.3 is
kept in the session scratchpad (`m1m2.patch`), never committed.

### 2.1 Who reads and writes each field

Reads, `grep -rnE --include='*.swift' "[A-Za-z_\)\]]\.<field>\b" Sources`
(member access, not modifier calls), and writes, `git grep -nP
"\.<field>(\.\w+)?\s*=[^=]" -- Sources/MetalUI Sources/MetalUIDemoContent`:

| field | readers (`Sources`) | production writers | disposition |
|---|---|---|---|
| `display` | `LegacyLowering` 10, `ModifiedElement` 2, `Stack`, `TextField` | `hidden()`, `Stack`, `ModifiedElement`, the lowering's own | kept |
| `position` | `LegacyLowering` 5, `LoweringState` 2, `Deferred` | `.position(_:)` | kept (`.relative` deleted) |
| `inset` | `LegacyLowering` 7, `LoweringState` 2, `AnimatedStyle` 4 | `.inset(_:)` ×2 | kept |
| `size`, `minSize`, `maxSize` | the lowering, `FrameLayer`, `List`/`ListRows`, `AnimatedStyle` | the eight deprecated modifiers, `FrameSpec.style()`, `List` | kept |
| `aspectRatio` | **none** | **none** | deleted |
| `margin` | `LegacyLowering` 4, `LoweringState` 2, `AnimatedStyle` 4 | `.margin(_:)` ×2 | kept |
| `padding` | the lowering, `AnimatedStyle`, `Text`, `Component` | `.padding(Edges<Length>)`'s layer, `Component`'s wrapper, the demo's `chrome` | kept |
| `border` | `LegacyLowering` 5 (`paddedAndSized`'s insets, `border.percent`), `AnimatedStyle` 4 | **none** (`Box.swift:358/1218/1223` write `Decoration.border`) | deleted |
| `overflow` | **none** (`ScrollView.swift:321` writes it, commented inert) | that write | deleted |
| `flexDirection` | the lowering 7, `Flex`, `List`, `ScrollView` | `Row`/`Column`, `.flexDirection(_:)`, `List`, `ScrollView`, the demo | kept |
| `flexWrap` | `legacyContainerDiagnostics` only (reports `flexWrap`) | `.flexWrap(_:)` | deleted |
| `gap` | the lowering 2, `Flex`, `AnimatedStyle` | `.gap`, `Row`/`Column`, the demo | kept |
| `justifyContent` | the lowering 3, `FrameLayer` | `.justifyContent(_:)`, `FrameSpec.style()` | kept |
| `alignItems` | the lowering 8, `Flex`, `FrameLayer`, `Stack` | `.alignItems(_:)`, `Row`/`Column`, `Stack`, `FrameSpec.style()`, the demo | kept |
| `alignContent` | `legacyContainerDiagnostics` only | `.alignContent(_:)` | deleted |
| `justifyItems` | the lowering 3, `FrameLayer`, `Stack` | `Stack`, `FrameSpec.style()` | kept (`package` type) |
| `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf` | the lowering, `LoweringState`, `AnimatedStyle` (not `alignSelf`), `FrameLayer`, `List` | their modifiers, `FrameSpec.style()`, `List` | kept |

`MetalUILayout` itself reads no `Style` field (`grep -n Style
Sources/MetalUILayout/LayoutTree.swift` prints only history comments; stage 9
deleted `newNode`/`style`/`setStyle` and the placeholder rows). Outside the
root package: `Backends/SDL`, `Tests/PortableTests` and `Experiments` name no
`Style` member; `docs/probes/modifier-composition-skeletons/*.swift` declare
their own `Style`; `docs/probes/swiftui-*.swift`'s `aspectRatio` is SwiftUI's.

Test writes of a `Style` field (`git grep -nP
"\b\w*[sS]tyle\w*\.(<fields>)(\.\w+)?\s*=[^=]|\$0\.(<fields>)(\.\w+)?\s*=[^=]" -- Tests`,
an under-count — it misses receivers not named `*style*`, such as `s.`):
**250 lines in 25 files**; by field padding 30, size 29, margin 27, flexGrow 23,
flexDirection 22, maxSize 17, alignItems 17, border 15, display 14, minSize 12,
flexShrink 12, justifyItems 9, justifyContent 9, alignSelf 9, position 7, gap 7,
inset 6, flexWrap 5, flexBasis 3, alignContent 3, overflow 1, aspectRatio 1.
The compiler's count of the writes that name a **deleted** field is §2.2's.
`Style()` appears 163 times in `Tests` (651 at stage 8, record §50 §2). The
`css*` helpers of `CSSSizing.swift` are called on 818 lines.

### 2.2 The deletion, by the compiler

Scratch D1: `aspectRatio`, `overflow`, `flexWrap`, `alignContent` removed from
`Style`, the enums `FlexWrap`, `Overflow`, `AlignContent` and the case
`Position.relative` removed, `StyledElement.flexWrap(_:)`/`alignContent(_:)`
removed. `swift build --build-system native --build-tests`:

- **7 errors, 2 files**: `LegacyLowering.swift:208–209` (the two diagnostic
  lines), `:787` (`.relative`); `ScrollView.swift:321` (the inert write).
- those patched: 5 errors in `Tests/MetalUILayoutTests/StyleTests.swift`
  (lines 10, 27, 31, 33);
- those patched: **35 errors in 9 `MetalUITests` files** — `AnimationTests`
  1453 (`aspectRatio`), `GoldenReplacementStackTests` 321/330/338,
  `LayoutAuthorityTests` 194–207 (six `.relative`), `LoweringContainerTests`
  446/447/642/643, `LoweringLeafTests` 199/371–375, `LoweringStackAndLayerTests`
  154–155, `ModifierTests` 248–252, `PresentationLoweringTests` 414.

Scratch D2, on top: `Style.border` removed, `AnimatedStyle.swift:389–392` and
`LegacyLowering.swift:585–588/781` patched (the inset becomes the padding's
alone; the `border.percent` line goes) — **14 errors in those 2 files before
the patch**; then `StyleTests` 1 and **28 errors in 7 files**:
`AnimationTests` 1287–1290/1438, `GoldenReplacementFlexTests` 139–155,
`GoldenReplacementStackTests` 230/276/285, `LoweringBoxModelTests` 117–146/523,
`LoweringContainerTests` 396, `LoweringLeafTests` 198/234,
`PresentationContainingBlockTests` 87/89.

Each error site mapped to its enclosing `@Test` (a script walking back to the
nearest `@Test` and its `func`): spec §6's lane-1 table, T1.2 and T1.5–T1.16
plus D1.1–D1.2.

### 2.3 The narrowing

Scratch N (alone, from `8095fd9`): every `public var` in `Style.swift` →
`package var` (20 lines). `swift build --build-system native --build-tests`:
**0 errors** (the one matching line was SwiftPM's notice). Unfiltered suite:
**`Test run with 1411 tests in 3 suites passed after 76.955 seconds.`**, FR-J
line present — no guard fixture reads a `Style` field (their `Style()` and
`public var style = Style()` stay legal). A plain-import fixture typechecked
by hand against the built modules (`swiftc -typecheck -I
.build/arm64-apple-macosx/debug/Modules` plus each target's module map
directory, `-swift-version 6`) printed:

```
fx.swift:2:31: error: 'flexGrow' is inaccessible due to 'package' protection level
fx.swift:2:79: error: 'size' is inaccessible due to 'package' protection level
```

`nm -gU .build/arm64-apple-macosx/debug/MetalUILayout.build/Style.swift.o`,
taken with N applied on top of D1 (the first build of N; the suite run above was
N alone), still printed `T _$s13MetalUILayout5StyleV8flexGrowSfvg` and `…vs`: a
`package` accessor is an exported symbol, so it can be a `dlsym` positive
control.

### 2.4 The move

Scratch M (alone): `git mv Sources/MetalUILayout/Style.swift
Sources/MetalUI/Style.swift` → **17 errors, all in
`Tests/MetalUILayoutTests/StyleTests.swift`** (the kernel's test target cannot
see `MetalUI`). With that file moved to `Tests/MetalUICrossPlatformTests/` and
`@testable import MetalUILayout` → `@testable import MetalUI`: 0 errors,
unfiltered **`1411 tests in 3 suites passed after 77.187 seconds.`**, FR-J line
present. After `git reset --hard`, a filtered run of a scratch test died with
**signal 11** until `swift package clean` — the CLAUDE.md hazard for a public
type crossing a module boundary, measured here; lane 2 cleans after the move.

### 2.5 `dlsym` in the test process

A scratch test (`scratchDlsym`, in `Tests/MetalUICrossPlatformTests`, deleted
after) resolved five names with `dlsym(RTLD_DEFAULT, …)`. macOS, native and
default build systems alike, and Linux (`swift:6.4-noble` under OrbStack,
aarch64, `git archive HEAD` plus the scratch file, `swift build --build-tests`
then `swift test --skip-build --filter scratchDlsym`) alike:

```
$s13MetalUILayout5StyleV8flexGrowSfvg true
$s13MetalUILayout5StyleV8flexWrapAA04FlexE0Ovg true
$s7MetalUI10LayoutPassV17requestNativeLeaf7measure… true
$s7MetalUI5FrameC17requestNativeLeaf7measure… true
$s13MetalUILayout13computeLayout_4root9available… false
```

Stage 9's deleted names were printed from `b9a5d7f` (a `git archive`, `swift
build --build-system native --target MetalUI`, `nm -gU` of the objects); the
`computeLayout` name equals record §18's measurement at `c2290fc`. Windows was
not measured. Every name and command: the instrument file.

### 2.6 Size

A standalone `swiftc -Onone` build of `Sources/MetalUICore/*.swift` with each
variant of `Style.swift` and a `main` printing `MemoryLayout<Style>`: **226**
(stride 228) at `8095fd9`; **210** with D1; **178** (stride 180) with D1 + D2.
In the suite's own process at `8095fd9`, on an 8 MB thread:
`MemoryLayout<Style>.size` 226, `Box<EmptyGroup>` 616,
`MemoryLayout.size(ofValue: demoContent())` **34 808**,
`nativeLayoutPreviewContent()` 935. The probe runs the build on its own 8 MB
`Thread` because the demo needs 528 KB of stack (record §50 §14) and macOS gives
a secondary thread 512 KB. Two earlier attempts — on the Swift Testing worker,
then on the 8 MB thread — both died with signal 11 **before** `swift package
clean` (§2.4's stale objects); after it the 8 MB run printed the figures above.
The worker-thread attempt was not repeated after the clean, so which of the two
causes killed it is not known.

## 3. Critic round 1 (design, 2026-09-24)

One critic-and-reviser agent over `07e7c49`; ruling `LR-FR` (F1–F6 applied,
R1–R4 rejected). No `Sources/`/`Tests/` file touched.

- **The closing check's names after the move** (F1, F3): a standalone
  two-module `swiftc` compile whose control variant reprinted block A's two
  `requestNode(style:children:)` names, block B's two modifier names and block
  D's two `flexGrow` names byte for byte showed that each of those spells the
  module of `Style`/`FlexWrap`/`AlignContent`, so a regression re-adding one
  after the move exports a different string (`AG5StyleV` → `AA5StyleV`,
  `0A8UILayout04FlexF0OF` → `AA04FlexF0OF`). Block C grows 4 → 12, the absent
  list 22 → 30; the three predicted getters printed as predicted.
  `computeLayout` and both `requestLeaf` names spell the deleted
  `AvailableSpace` and cannot be re-exported by any source.
- **Mutations added** (F2): M2f (re-add `LayoutPass.requestNode(style:children:)`
  over the moved `Style`) and M2g (re-add `enum LayoutAuthority`) — `LR-P` item
  0's "restore a symbol".
- **M1b's list** (F4): T1.4 removed — it asserts window-placed hitboxes
  whatever surrounds the root.
- **`Box(style:)`** (F5): inert outside the package once every field is
  `package`; kept, a record §05 row at the Record phase, handed to task 15.
- **The golden-count spelling** (F6): `git ls-files 'Tests/*.json'` and
  `find Tests -name "*.json"` both read 0 at `8095fd9`; the reason for the
  former is in spec §8.

## 4. Lane 1 — tests off the deleted fields; reports made permanent (2026-09-24)

Commits `51c288a` (red first: N1.1, T1.1–T1.16, D1.1/D1.2 retired, the
`CSSSizing.swift` doc comment) and `84ad1e6` (`UnlowerableField.owningStage:
String` → `owner: String?`, `LayoutAuthority.swift` only). Ruling `LR-FS`.

### 4.1 Red first

The red commit carried a scratch `owner` forwarding to the old
`owningStage`, so the tree built. **`Test run with 1410 tests in 3 suites
failed after 76.899 seconds with 644 issues.`** Five tests failed:

| test | issues | first failure line |
|---|---|---|
| N1.1 `everyReportNamesALiveOwnerOrIsRefusedByName` | 639 | `LayoutAuthorityTests.swift:344:9: Expectation failed: field.owner == owner` (and `:349:13` `message.contains("(\(owner))")`) |
| T1.1 `anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame` | 1 | `AbsoluteOverlayTests.swift:49:5: Expectation failed: stderr.contains("MetalUI: box.position has no proposal lowering and is refused by name "…` — the child printed `(plan task 7, stage 10)` |
| T1.2 `aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName` | 2 | `PresentationLoweringTests.swift:477:9: Expectation failed: field.owner == nil` |
| T1.3 `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable` | 1 | `LoweringScrollTests.swift:1015:5: Expectation failed: UnlowerableField(site: .scrollView, field: "flexGrow.weights").owner == nil` |
| T1.4 `aPresentationsContainingBlockIsTheWindowWhateverSurroundsIt` | 1 | `PresentationContainingBlockTests.swift:133:9: Expectation failed: field.owner == "plan task 7, stage 11"` |

T1.5–T1.16 were green at the red commit, as designed: each is a re-spelling
that compiles and passes against the old `Style` (spec §6 lane 1).

### 4.2 Green

`swift build --build-system native --build-tests` at `84ad1e6`: 0 `error:`,
the one `warning:` SwiftPM's deprecation notice. Unfiltered
`swift test --build-system native --no-parallel`: **`Test run with 1410
tests in 3 suites passed after 81.065 seconds.`**, the log carrying
`FR-J no-argument frame: succeeded=` (guards ran). **1411 − 3 + 2 = 1410**:
removed D1.1 `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs`, D1.2
`aStyleBorderLowersAsInsetsInsideTheDeclaredSize` and T1.16's old name
`allTwentyEightAnimatableFieldsInterpolateAndLeaveInFlightOnSettle`; added
N1.1 and `allTwentyFourAnimatableFieldsInterpolateAndLeaveInFlightOnSettle`.
Guards 79 (no guard file touched). Every retained T row's literals are
unchanged (the border folds are `padding + border` edge by edge, the
lowering's own inset).

### 4.3 Mutations

Each applied by a script to the committed tree, built, run unfiltered,
restored from a copy; `git status --short` empty after each. Every mutant
built with 0 `error:`.

| id | mutation (file) | suite | reddened |
|---|---|---|---|
| M1a | `UnlowerableField.owner`'s `nil` arm returns `"plan task 7, stage 10"` for a field prefixed `position`/`inset` (`LayoutAuthority.swift`) | 97 issues | N1.1 (96), T1.1 (1) — as predicted |
| M1b | `paddedAndSized`'s inset `resolvedLength(padding) + resolvedLength(border)` → `resolvedLength(border)` (`LegacyLowering.swift`) | 236 issues, 50 tests | T1.13 `paddingAndBorderInsetTheContentBoxEdgeByEdge` (10), T1.15 `aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding` (2); **not T1.14** (refuted prediction, `LR-FS` item 1), not T1.4 (`LR-FR` F4). All fifty: `aChainsOuterLayerScopesContainTheLayersInsideIt`, `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer`, `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt`, `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`, `aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding`, `aDeclaredSizeBelowThePaddingKeepsItsFixedFrame`, `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScroll`, `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`, `aGrowInsideAOneChildPaddingFillsTheWrapper`, `aHiddenInnerModifierLayerSkipsPaintAndHitsPerLayer`, `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`, `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten`, `aLoweredBoxPaddingSitsInsideItsDeclaredSize`, `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork`, `aLoweredChainAtTheNativeDepthLimitLaysOut`, `aLoweredChainOneLevelPastTheNativeDepthLimitTraps`, `aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap`, `aLoweredContainerPaddingSitsInsideItsDeclaredSize`, `aLoweredItemChainWithThreeWrappersPerLevelAtTheNativeDepthLimitLaysOut`, `aLoweredItemChainWithThreeWrappersPerLevelOnePastTheNativeDepthLimitTraps`, `aLoweredListLaysOutEveryWindowedShape`, `aLoweredPaddingLayerInsetsItsContentByEachEdge`, `aLoweredStackLaysOutItsAnimatedWidthAndPadding`, `aLoweredStackPlacesFixedChildrenAtAllNineAlignments`, `aLoweredWindowDispatchesClicksFocusAndKeys`, `aLoweredWindowPublishesItsAccessibilityTree`, `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`, `aModifierChainRegistersAndPaintsOuterLayersFirst`, `anAlignSelfInsideAOneChildWrapperFillsTheWrapper`, `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt`, `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot`, `aScrolledListsSpacerDoesNotShrinkUnderPadding`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `everyDecorationPaintingSiteDrawsItsBorder`, `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`, `everyProductionRootsDeepestNativeLevelIsMeasured`, `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`, `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`, `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`, `paddingAndBorderInsetTheContentBoxEdgeByEdge`, `paddingOnAListDoesNotShrinkItsRowsBelowRowHeight`, `paddingOnALoweredTextPadsItsLeaf`, `spriteDestinationsAreThePenPositionPlusTheRasterizersBearings`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer`, `theIndicatorIsClippedByTheViewportsRoundedCornerWithoutScrollingWithIt`, `theOrderOfAComponentsDistributingModifiersIsObservable`, `theStageOneCorpusLowersWithNoDiagnostic`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` |
| M1b′ | the stretched axis's `lo` floored at the item's padding + border (stage 9's M2f on the folded fixture; `LegacyLowering.swift`, `planLegacyItems`) | 2 issues | T1.14 `aStretchedStackChildIsNotFlooredByItsPaddingAndBorder` (2) only |
| M1c | `fields + legacyLeafDiagnostics(declared, site:)` → `legacyLeafDiagnostics(…) + fields` (`LegacyLowering.swift`) | 3 issues | T1.9 (3) — as predicted |
| M1d | the leaf `inset` row deleted from `legacyLeafDiagnostics` (`LegacyLowering.swift`) | 9 issues | T1.5 (6, one per `inset` arm), T1.6 (2), T1.9 (1); **not N1.1** (refuted prediction, `LR-FS` item 2 — N1.1 is a static table) |

**Site coverage** (stage 9 `LR-FH` item 2): M1d reddening T1.5 once per
`inset` arm shows each of the six re-spelled site arms (`box`, `stack`,
`text`, `textField`, both `modifierLayer` registrars) still reaches its
site; the `scrollView`, `List` and two `Component` arms are untouched.

### 4.4 The demo

`docs/probes/demo-pixels/compare.sh <scratch>/pix 8095fd9 84ad1e6` (the
stage-9 harness copy for both, since neither `Fakes.swift` declares a
`layoutAuthority:` parameter): controls light vs dark 1048576, default vs
modal 1031003, default vs animation 454895, f0 vs f3 0, preview light vs dark
1048576, chrome pair 0, distinct 544 / 216, prod default vs modal 491221,
distinct prod-default-light 529, indicator rects 0 — the stage-9 corrected
values. **All fourteen images 0 differing, every scene identical.**


## 5. Lane 2 — the deletion, the narrowing, the move, the closing check (2026-09-24)

Commits `79cca7e` (red first: N2.1, G1–G3) and `133f634` (the deletion, the
narrowing, the move), then the docs commit carrying this section (and one
`Sources` doc comment, `NativeModifiedContent.swift`'s `Style.aspectRatio`
sentence, found by the §8 grep). Ruling `LR-FT`.

### 5.1 Red first

At `79cca7e`, unfiltered: **`Test run with 1414 tests in 3 suites failed
after 80.960 seconds with 17 issues.`** Four tests failed:

| test | issues | first failure line |
|---|---|---|
| N2.1 `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` | 1 | `LegacyEngineSymbolTests.swift:115:13: Expectation failed: resolves(name)` — the first positive control, `$s7MetalUI5StyleV8flexGrowSfvg`, does not exist before the move |
| G1 `aPlainImportCannotWriteAStyleField` | 1 | `StyleSurfaceCompileGuards.swift:44:9: Expectation failed: write.succeeded != control.succeeded` — the `Style` write compiles |
| G2 `theDeletedStyleSpellingsDoNotCompile` | 14 | `StyleSurfaceCompileGuards.swift:86:9: Expectation failed: !result.succeeded` and `:87:9` `result.messages.contains(fixture.message)`, once each for all seven fixtures |
| G3 `theLayoutKernelDeclaresNoStyle` | 1 | `StyleSurfaceCompileGuards.swift:112:9: Expectation failed: kernel.succeeded != control.succeeded` — `MetalUILayout.Style` exists |

**The second reading of N2.1** (spec §6): with the positive-control
`#require` set aside in scratch (restored after, `git status --short` clean),
`--filter theLegacyEngineSymbolsAreAbsent` failed with **11 issues, exactly
block B's eleven names** resolving (`$s13MetalUILayout5StyleV8flexGrowSfvg`,
the five field getters, the three enum accessors, the two modifiers); every
block-A and block-C name was already absent.

### 5.2 Green

`Style.swift` rewritten (four deleted fields, `border`, `.relative`, three
enums gone; every stored field, `Display` and `JustifyItems` `package`; doc
comments for the one engine) and `git mv`d to `Sources/MetalUI/`;
`StyleTests.swift` `git mv`d to `Tests/MetalUICrossPlatformTests/` with
`@testable import MetalUI` and its five deleted-field lines removed (T2.1–T2.4,
names unchanged). The compiler named exactly spec §2.2's `Sources` sites:
`AnimatedStyle.swift` (the `border` arm), `LegacyLowering.swift` (the
`flexWrap`/`alignContent`/`border.percent`/`.relative` report lines and
`paddedAndSized`'s `padding + border` inset, now `resolvedLength(padding)`),
`ScrollView.swift` (the inert `overflow` write); `Box.swift` lost the two
modifiers. Doc comments that described a deleted field as present were
re-worded as history in `LegacyLowering`, `AnimatedStyle`, `StateTable`,
`ScrollView`, `Frame`, `Box` and `NativeModifiedContent`.

After `swift package clean`: `swift build --build-system native
--build-tests` 0 `error:`, one `warning:` (SwiftPM's notice); `swift build
--build-tests` (default build system) 0 `error:`, 0 `warning:`. Unfiltered
`swift test --build-system native --no-parallel`: **`Test run with 1414
tests in 3 suites passed after 79.845 seconds.`** (and `82.232` at the docs
commit), the log carrying `FR-J no-argument frame: succeeded=`; eleven gated
tests skipped. **1410 + 4 − 0 = 1414** (added N2.1, G1, G2, G3; removed
none). Guards `grep -c canTypecheck`: 83 hits across seventeen files, minus
`UnitSafetyTests`' comment and `Typecheck.swift`'s declaration = **82**
(`StyleSurfaceCompileGuards` 3 new). Goldens 0 (`git ls-files 'Tests/*.json'`).

The guards' measured messages (the log's `STYLE-SURFACE GUARD` lines): G1
`'flexGrow' is inaccessible due to 'package' protection level`; G2
`value of type 'Box<EmptyGroup>' has no member 'flexWrap'` / `…'alignContent'`,
`type 'Position' has no member 'relative'`, `cannot find type 'FlexWrap' in
scope` (and `AlignContent`, `Overflow`), `value of type 'Style' has no member
'border'`; G3 `module 'MetalUILayout' has no member named 'Style'`. Every
control compiled.

**`MetalUILayout`**: `grep -h '^import' Sources/MetalUILayout/*.swift | sort
-u` prints one line, `import MetalUICore`; `grep -rn 'Style'
Sources/MetalUILayout` prints three history comments only —
`LayoutTree.swift:36–37` (the deleted `style`/`setStyle` API and placeholder
`Style.default` rows) and `LayoutTree.swift:144` (`setStyle`).

### 5.3 Mutations

Each applied to the committed `133f634` by a script, built, run unfiltered,
restored from a copy; `git status --short` empty after each. `swift package
clean` before M2a–M2d (M2a and M2c change a public type's stored layout or
module). Every mutant built with 0 `error:`.

| id | mutation | suite | reddened |
|---|---|---|---|
| M2a | `public enum FlexWrap`, `public var flexWrap: FlexWrap` on the moved `Style` and `StyledElement.flexWrap(_:)` re-added (`Style.swift`, `Box.swift`) | 7 issues | N2.1 (3: block C's `$s7MetalUI5StyleV8flexWrapAA04FlexE0Ovg`, `$s7MetalUI13StyledElementPAAE8flexWrapyxAA04FlexF0OF`, `$s7MetalUI8FlexWrapOMa` resolve), G2 (4: the `flexWrap(.wrap)` and `FlexWrap?` fixtures compile) — as predicted; the three names confirmed by `nm` (instrument block F) |
| M2b | `Style.flexGrow` `package` → `public` | 1 issue | G1 alone — as predicted |
| M2c | `Style.swift` moved back to `Sources/MetalUILayout/` | 2 issues | N2.1 (1: `$s7MetalUI5StyleV8flexGrowSfvg` does not resolve — the positive control ends the test, `LR-FT` item 2; `nm` shows the mutant exports block B's `$s13MetalUILayout5StyleV8flexGrowSfvg`), G3 (1) |
| M2d | `resolves(_:)` returns `false` for every name (`LegacyEngineSymbolTests.swift`) | 1 issue | N2.1 at `LegacyEngineSymbolTests.swift:116:13` (the positive-control `#require`) and nothing else — as predicted |
| M2e | `newStyle.padding = …` deleted from `animated(_:_:for:pass:)` (`AnimatedStyle.swift`) | 13 issues | `allTwentyFourAnimatableFieldsInterpolateAndLeaveInFlightOnSettle` (5), `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority` (3), `aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap` (2), `aLoweredStackLaysOutItsAnimatedWidthAndPadding` (2), `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer` (1) |
| M2f | `extension LayoutPass { public func requestNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID { fatalError() } }` in `MetalUI` | 2 issues | N2.1 (1: block C's `$s7MetalUI10LayoutPassV11requestNode5style8children0A8UILayout0cF2IDVAA5StyleV_SayAIGtF`, confirmed by `nm`), stage 9's `aPlainImportCallerOfTheLegacyRegistrarsNoLongerCompiles` (1) |
| M2g | `enum LayoutAuthority { case proposal }` (internal, unused) in `MetalUI` | 1 issue | N2.1 (1: `$s7MetalUI15LayoutAuthorityOMa`) — no stored use needed (`LR-FT` item 3) |

**Fix round (verifier finding V3, major).** G1 as first committed pinned one
declaration of the nineteen the narrowing made `package`: the verifier widened
`package enum Display` and `Style.padding` to `public` and the unfiltered suite
still read `Test run with 1414 tests in 3 suites passed after 80.155 seconds.`
(guards ran). G1 was extended in place (the guard count stays **82**, the
test count **1414**): one plain-import fixture now reads all **17** surviving
stored fields (`display`, `position`, `inset`, `size`, `minSize`, `maxSize`,
`margin`, `padding`, `flexDirection`, `gap`, `justifyContent`, `alignItems`,
`justifyItems`, `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf`, each
`try #require`-counted) and names `Display` and `JustifyItems`, and the guard
expects one message per name — `'<field>' is inaccessible due to 'package'
protection level` per field and, measured, `cannot find type '<Enum>' in scope`
per enum (swiftc hides a `package` type from a plain import rather than naming
its access level). The control compiles `Box().flexGrow(1)` and names the
public `Position`. Re-run of the mutation on the fixed guard:

| id | mutation | suite | reddened |
|---|---|---|---|
| V3 | `package enum Display` → `public`, `package var padding` → `public` (`Style.swift`), after `swift package clean` | `Test run with 1414 tests in 3 suites failed after 81.080 seconds with 2 issues.` (FR-J line present) | `aPlainImportCannotWriteAStyleField` alone, 2 issues: "`Display` is nameable from outside the package" and "`Style.padding` is not rejected by access" |

Restored from a copy, `git status --short` empty; after `swift package clean`
the unfiltered suite read `Test run with 1414 tests in 3 suites passed after
82.152 seconds.` with the FR-J line present.

### 5.4 Size and the Windows stack budget

Measured with a scratch test (deleted after) in `MetalUICrossPlatformTests`,
at `8095fd9` (a `git archive` in the scratchpad, never a worktree) and at
`133f634`, the same test file in both, debug, macOS arm64:

| | `8095fd9` | `133f634` |
|---|---|---|
| `MemoryLayout<Style>.size` | 226 | **178** (spec §2.6's prediction) |
| `MemoryLayout<Box<EmptyGroup>>.size` | 616 | 568 |
| `MemoryLayout.size(ofValue: demoContent())` (built on an 8 MB thread) | 34 808 | **32 216** (−2 592 = 54 × 48) |
| smallest thread stack building every production tree (`buildEveryProductionTree(onAThreadOf:)` in an exit test) | fails 512 KB, passes 528 KB | fails 480 KB, passes **484 KB** |

`everyProductionTreeBuildsOnAOneMegabyteThread` and
`aThreadTooSmallForTheDemoFailsTheSameHarness` green unedited;
`theDemoFrameMatchesTheValuesRecordedOnMacOS` green, `Expected.swift`
unedited (`git diff --stat 8095fd9 -- Tests/MetalUICrossPlatformTests/Expected.swift`
empty).

### 5.5 The demo

`docs/probes/demo-pixels/compare.sh <scratch>/pix 8095fd9 133f634`: controls
light vs dark 1048576, default vs modal 1031003, default vs animation 454895,
f0 vs f3 0, preview light vs dark 1048576, chrome pair 0, distinct 544 / 216,
prod default vs modal 491221, distinct prod-default-light 529, indicator
rects 0 — the stage-9 corrected values. **All fourteen images 0 differing,
every scene identical.**

### 5.6 Off the root package

- **`Backends/SDL`** (`python3 Backends/SDL/scripts/fetch-accesskit.py`, then
  `PKG_CONFIG_PATH=$PWD/.accesskit swift build --build-tests` and `swift
  test`): 0 `error:`; `Test run with 21 tests` and `19 tests` passed
  (`ReplayFixtureTests`, `MetalUISDLTests`; `PortableReplay`/`DemoCapture`
  unedited). The package's `ld: warning: building for macOS-14.0, but linking
  with dylib … libSDL3.0.dylib … built for newer version 26.0` and `'sdl':
  prohibited flag(s)` lines are the host's Homebrew SDL3, not this change.
- **`Tests/PortableTests`**: builds with 0 `error:`/`warning:`; 18 + 6 + 5
  passed.
- **`swift:6.4-noble`** (OrbStack, aarch64) over `git archive HEAD` at
  `133f634`: `swift build --build-tests` 0 `error:`, 0 `warning:`; `swift
  test --skip-build --filter 'MetalUICoreTests|MetalUILayoutTests|MetalUICrossPlatformTests'`
  → **22 + 188 + 10** passed, `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
  green (the closing check off Apple).

### 5.7 The recorded grep (spec §8 item 1), at lane 2's head

- `grep -rn "FlexEngine\|computeLayout(\|requestNode(style" Sources`: four
  history comments — `DemoContent.swift:768,772` (`FlexEngine`),
  `Passes.swift:32` and `Frame.swift:1604` (stage 9's deleted registrars) —
  record §51 §7.7's list.
- `git ls-files 'Tests/*.json' | wc -l` → 0. `find Tests -name "*.json" | wc
  -l` → 45, every one under `Tests/PortableTests/.build/` (0 with `-not -path
  '*/.build/*'`) — `LR-FR` F6's reason for the `git ls-files` spelling.
- `grep -rnE 'flexWrap|alignContent|aspectRatio|\bOverflow\b|\.relative\b|FlexWrap|AlignContent' Sources Tests/MetalUITests Tests/MetalUICrossPlatformTests Tests/MetalUILayoutTests`:
  the proposal `.aspectRatio(_:)` family (`NativeElements`,
  `NativeModifiedContent`, `LayoutTree`, `ProposalLayout`, their tests),
  vendored C (`CFreeType`, `CHarfBuzz`: "Overflow"), N2.1's names and G2's
  fixtures, and history comments: `Style.swift:11–12,27`,
  `Box.swift:431,1041,1109–1112`, `LegacyLowering.swift:189,778`,
  `AnimatedStyle.swift:24,47`, `NativeModifiedContent.swift:336`, and lane 1's
  test comments (`ModifierTests.swift:24,396–397`,
  `PresentationLoweringTests.swift:389–390`, `LoweringStackAndLayerTests.swift:106`,
  `GoldenReplacementStackTests.swift:307–311`, `LoweringContainerTests.swift:293,346,640,655`,
  `LayoutAuthorityTests.swift:185–186,266`, `LoweringLeafTests.swift:178,362–363`,
  `AnimationTests.swift:1209–1463`, `StyleTests.swift:4–5`).
  **One is present-tense and not lane 2's to edit**:
  `LoweringContainerTests.swift:293` lists "`.wrap`: `flexWrap`; an
  `alignContent`: `alignContent`" among the container rows in a doc comment
  above a test whose arms lane 1 already removed — handed to the Record phase.
  **Fixed in lane 2's fix round**: the line now reads as history ("until
  stage 10 deleted both fields, `LR-FN`"), so the grep's hit there is a
  history comment like the rest.
- `grep -rn 'Style' Sources/MetalUILayout`: the three history comments of §5.2.
