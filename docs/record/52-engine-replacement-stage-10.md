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
