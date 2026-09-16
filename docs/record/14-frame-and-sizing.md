## Frame and sizing (plan task 4) — `feat/frame-sizing`, from 2026-09-15

The record for plan task 4. Spec
`docs/superpowers/specs/2026-09-15-frame-sizing-design.md`; rulings `FR-A`…
`FR-R` in `docs/superpowers/2026-09-15-frame-sizing-decisions.md` (next unused
`FR-S`); probes `docs/probes/swiftui-frame-semantics.swift` (54 arms) and
`docs/probes/swiftui-frame-negative-sizes.swift` (17 arms). The track runs in
its own worktree, `/Users/maxburger/Developer/MetalUI-frame-sizing`, beside the
paint-modifier track, and is merged by an integration step that owns
`CLAUDE.md`, the plan, `docs/record/README.md` and the other track's files.
**Nothing in this file has been copied into those yet.**

Integration obligations this track creates for CLAUDE.md, which it may not edit
itself: a **declared-but-inert row** for a single-axis
`.frame(maxWidth: .infinity)` on the legacy path (`FR-O`); the fact that
`.frame(width:height:alignment:)`'s lowering now pins its declared axis with an
axis-named `minSize` (`FR-P`) and that `ElementGroup` must keep exactly ONE
fixed `frame` overload (`FR-S`, or long modifier chains stop compiling); and, from lane 1, that **a frame with a maximum
is greedy on the proposal path** (`FR-A`) with two divergences worth a line —
an infinite proposal answers the child rather than infinity (`FR-B`), and a
negative maximum or fixed size **traps** where SwiftUI floors it at 0 (`FR-L`,
`FR-R` item 2). The suite total moves 1226 → **1234** on lane 1 and → **1245** after lane 2;
guards 61 → 62 → **63**.

### Design session, 2026-09-15, at `c4b5853`

No source file changed. Baseline, re-taken in this worktree with
`swift test --build-system native --no-parallel`: **1226 tests passed**, 0
`error:`, 0 `warning:`; `find Tests -name '*.json' | wc -l` = **97**;
`grep -c canTypecheck` per file sums to 62 with one comment hit in
`UnitSafetyTests.swift`, so **61** guards.

Toolchains: macOS 26.6.2 (25G83); `/usr/bin/swift` and `xcrun swiftc` report
Apple Swift 6.4 (swiftlang-6.4.0.33.1); PATH `swiftc` (swiftly) reports Apple
Swift 6.3.3.

| run | result | where recorded |
|---|---|---|
| SwiftUI probe `swiftui-frame-semantics.swift`, 54 arms, `/usr/bin/swift <file>` and compiled `xcrun swiftc` + `OS_ACTIVITY_DT_MODE=1` | `diff` of the two forms EMPTY, 295 lines, exit 0 both ways, no SwiftUI diagnostic in either (every input is one SwiftUI accepts) | the probe's header; `FR-A`, `FR-B`, `FR-C`, `FR-D`, `FR-E`, `FR-J` |
| the probe's first pass, which placed the view under test at `bounds.origin` | arm D12 (`frame(maxWidth: .infinity)` at an infinite proposal) **crashed SwiftUI**: `SwiftUICore/Layout.swift:1535: Fatal error: view origin is invalid: (nan, 190.0), UnitPoint(x: 0.0, y: 0.0), (20.0, 20.0)`. Placing at `.zero` instead, the same arm answers `inf x 20` and places the child at `x = inf` | the probe's header (arm D12's comment); `FR-B` |
| trial conversion: `StyledElement.width/height` → `frame(width:)`/`frame(height:)`, `swift build --build-system native` | fails to compile. `Sources/MetalUIDemo/main.swift` (the stored `typealias Chrome` and `button(_:_:) -> Box<Text>`); then, after patching those, `EnvironmentTests` (`surfaceBox -> Box<EmptyGroup>`, `typealias Leaf`), `ModifierTests` (its `ModifierCase` table, which asserts each modifier returns `Self` and writes a named `Style` field), `AccessibilityTreeTests`, `AccessibilityEndToEndTests`, `AnimationTests`, `ProposalNodeIDTests` | `FR-F` |
| `grep -rno` | `.width(` 348, `.height(` 338 across `Sources/` and `Tests/` (one of each is the percentage overload), over 378 distinct lines; `min*`/`max*` 10 in `Tests/` and **one live** in `Sources/` (`main.swift:881`), the other four `Sources/` matches being inside comments | `FR-F`, `FR-G`, `FR-I` |
| scratch `Tests/MetalUITests/ZZScratchFrameTests.swift`, 13 measurements, `swift test --build-system native --no-parallel --filter zzScratch`, **deleted before commit** (`git status --short` then showed only the probe) | below | `FR-C`…`FR-H` |

**Restores.** The trial conversion was reverted from `cp` backups of
`Box.swift`, `main.swift` and `EnvironmentTests.swift`; `git status --short`
afterwards showed only the untracked probe. The scratch test file was deleted.

### What the legacy CSS path actually does — the scratch measurements

Every figure below came from `Frame.render` or a direct `requestLayout` +
`computeRootLayout`, in a 300×200 root unless stated. They are quoted here
because the file that produced them is gone. `Mark` is a childless
`StyledElement` probe recording the bounds its `prepaint` receives.

| arm | shape | measured | SwiftUI (probe arm) |
|---|---|---|---|
| L1 | `Text(…).frame(width: 60)` **as the root** | 60×200, and identical for `.width(60)` and for a `Box` wrapper — the root's auto height takes the offered space (divergence 4), so the root contaminates this measurement | — (superseded by L11) |
| L2 | `Mark.frame(width: 60, height: 40)` | root 60×40; the **Mark is 0×0** at (30, 20) | matches: a contentless child answers 0 and is centred (A-control shape) |
| L3 | `Mark.width(200).height(160).frame(width: 60, height: 40)` | the Mark is **(0, −60, 60, 160)** — width shrunk to the frame, height overflowing. Re-measured in the critic round as **N5** (a `Row` parent instead of the root, so the y differs: (0, 20, 60, 160)); both agree the width is squeezed. Ruled on by `FR-N`, pinned wrong on purpose by test 2.8 | A5: the child keeps 200×160 at (−70, −60) |
| L4 | `Box { Mark }.onClick {}.frame(width: 60, height: 40)` | the hitbox is **0×0 at (30, 20)** | the same in SwiftUI: a handler declared before a frame sits on the content |
| L6 | nine `justifyContent` × `alignItems` combinations on a 60×40 layer over a 20×20 child | `(0,0) (0,10) (0,20) (20,0) (20,10) (20,20) (40,0) (40,10) (40,20)` | B1–B8 exactly |
| L9 | `Row { Mark.frame(200×20); Mark.frame(200×20) }` in 300pt | marks at x = **75 and 225** — each layer shrank to 150. The critic round's **N10** re-took it at x = 65/215 with a slightly different probe and reached the same finding | a fixed frame never shrinks |
| L10 | in a 300pt `Row`, width read from a 5pt sibling's x | `maxWidth 80` over a 20pt child → **20**; `minWidth 40` → **40**; `maxWidth 80` over a 200pt child → **80**; `.frame(width: 80)` → 80 with the child centred at 30 | D4 → 80 (**diverges**); D7 → 40; D14 → 80; A1 |
| L11 | `Column { Text("alpha bravo charlie delta").font(size: 12).frame(width: 60); marker }` | the marker sits at y = **60** — four 15pt lines — against y = **15** unframed; `.width(60)` reads 60 too. In a `Row` the framed and styled advances are 60 against the bare text's **139** | F1 60×60, F control 139×15 — the same numbers |
| L12 | `ScrollView { List(40 rows).frame(width: 200) }` | **40** painted row rects, the same as unframed and as `.width(200)` | — |
| L13 | `Row` of two frames whose children declare 200pt | no shrink either way; the automatic minimum floors them | — |
| L14 | L9 plus `.flexShrink(0)` on each layer | marks at **100 and 300** — 200 each, no shrink. **Superseded as the lowering** by `FR-P`: N11 shows `flexShrink = 0` pins an axis the caller never declared, and N10 shows an axis-named `minSize` is equivalent where it was right | matches SwiftUI |
| M1 | `Mark(20).frame(width: 100).frame(width: 50)` | root **50**, leaf at x = **15**. Reversed: root **100**, leaf at x = **40**. Unchanged without `.flexShrink(0)` — the inner frame does not shrink inside another frame | E1 (50, leaf 15) and E2 (100, leaf 40) exactly |
| M2 | greediness in a 300pt `Row` | `flexGrow(1)` fills to 295; `flexGrow(1) + maxWidth(80)` stops at **80**; plain reads 20. In a `Column`, `alignSelf(.stretch)` puts a child at x = 0 where an unstretched box's child is centred at 140 | D4's 80 — reachable, but only on the axis that happens to be main |
| M4 | `width(percent: 100)` | in a `Row` the sibling moves to x = **300** (fills); capped by `maxWidth(80)` it reads 80. **In a `Column` the child lands at x ≈ −14850**, implying a box about 30000pt wide. Mechanism not investigated | — |

**Three claims the plan made about the reverted 2026-09-12 conversion, tested.**
The plan says the trial "broke list virtualization, hit testing, and text
measurement", and record §09 notes no measurement of it exists.

- **Text measurement: refuted.** L11 — a frame layer's width reaches a measured
  leaf and re-wraps it, to SwiftUI's own numbers.
- **List virtualization: refuted.** L12 — the framed list paints the same rows.
- **Hit testing: confirmed, and it is not a defect.** L4 — a handler declared
  before the frame stays on the content, which is what SwiftUI does with
  `.background` before `.frame`. What actually blocks the conversion is the
  type-level blast radius and the 0-warning gate (`FR-F`).

### Critic round, 2026-09-15, still at `c4b5853`

Sixteen findings. **Fifteen applied, one refused with a measurement.** Two of
the applied ones produced better answers than the finding asked for, and chasing
one of them produced two findings nobody had raised. The per-finding ledger is
the last table in the decisions doc; the measurements are below. No source file
changed: every patch was applied, run, and restored from a `cp` backup, with
`git status --short` empty afterwards each time.

#### The overload skeleton — a standalone module, not MetalUI

A throwaway package in the scratch directory: `Pixels`, `ProposalAlignment`,
`protocol ElementGroup`, `protocol ProposalElementGroup: ElementGroup`,
`ModifiedElement<Base>`, `ModifiedContent<C, M>`, the two `frame` overloads on
each protocol plus the deprecated `frame()`, and `Leaf: ProposalElementGroup` /
`LegacyBox: ElementGroup`. Compiled and run with `xcrun swiftc -swift-version 6`
(Apple Swift 6.4).

| question | answer |
|---|---|
| does the refined protocol win when the two signatures are IDENTICAL? | yes, every shape: `.frame(width:)`, `.frame(width:height:alignment:)`, `.frame(minWidth:idealWidth:maxWidth:)`, `.frame(idealWidth:)`, `.frame(maxWidth:)`, `.frame(alignment:)` all infer `ModifiedContent<Leaf, …>`. Nothing ambiguous |
| is `ProposalLayoutCompileGuards`' expected diagnostic still right with the overload set doubled? | **yes** — `extra argument 'minWidth' in call` and `extra argument 'minHeight' in call`, verbatim. No re-fixture owed (finding 4) |
| can `frame()` be declared on `ElementGroup` alone (finding 11)? | **no.** `Leaf().frame()` then infers **`ModifiedContent<Leaf, FrameModifier>`** with **no deprecation warning** — the refined protocol's all-defaulted `frame(width:height:alignment:)` is more specialized and wins. That is `SA-N` item 9 surviving on the path the ruling exists to fix. With both declarations it infers `Leaf` and warns on both paths |

#### The negative-sizes probe — and the finding nobody raised

`docs/probes/swiftui-frame-negative-sizes.swift`, 17 arms, script and compiled
forms diffed EMPTY (101 lines, exit 0 both ways). The compiled form printed
**exactly two** SwiftUI diagnostics, `[SwiftUI] Invalid frame dimension
(negative or non-finite).`, on H6 (`maxWidth: -10`) and H10 (`width: -60`); a
negative *minimum* and a negative *proposal* are not diagnosed.

| arm | frame | proposal | child | SwiftUI |
|---|---|---|---|---|
| H2 | `maxWidth: 80` | −30 | 20 | 20 (child proposed −30) |
| H4 | `minWidth: −50, maxWidth: 80` | −30 | 20 | **0** (child proposed **0**) |
| H6 | `minWidth: −50, maxWidth: −10` | 100 | 20 | 0 |
| H7 | `maxWidth: 80` | 0 | 20 | **20** |
| H8 | `maxWidth: 80` | **10** | 20 | **20** |
| H10 | `width: −60` | 100 | 20 | 0 |
| H11 | `minWidth: 5, maxWidth: 80` | 10 | 20 | **10** |
| H13 | `minWidth: 5, maxWidth: 80` | 10 | 200 | 10 |
| H14 | **`minWidth: 0`**, `maxWidth: 80` | 10 | 20 | **10** |
| H15 | `maxWidth: 80` | 10 | 200 | 80 |
| H16 | `maxWidth: .infinity` | 100 | 200 | **200** |

Three things came out of it, and only the first was asked for:

1. **SwiftUI never answers a negative size** (finding 12). Every *declared*
   bound is floored at 0 before use; an *absent* minimum is not, which is why H2
   forwards −30 to its child and H4 forwards 0. `FR-L`.
2. **An absent minimum is not `minWidth: 0`** — `FR-M`, raised by nobody. H8 and
   H14 are the same numbers differing only in whether a zero minimum is written,
   and answer 20 and 10. The design's own kernel rule (`base = proposal`) was
   fitted to 54 arms none of which could distinguish it, because every arm with
   a maximum proposes MORE than its child answers.
3. **The shipped kernel has a live bug at an infinite maximum.** H16 answers
   200; `framedSize`'s `max == .infinity` branch returns
   `Swift.max(min ?? 0, proposal)` = 100. The demo's proposal preview ends in
   that spelling (`main.swift:1032`), which is why lane 4's pixel expectation
   changed.

#### The kernel patch, run over the whole suite

`FR-A` + `FR-L` + `FR-M` applied to `framedSize` and `framedProposal`, then
`swift test --build-system native --no-parallel`:
`Test run with 1226 tests in 1 suite failed after 32.756 seconds with 2 issues`.
**Exactly two**, and nothing else:

- `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum` — 80×60 against
  the pinned 40×70 (the spec already listed it);
- `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes` — 70×60 against the
  pinned 70×20 (**finding 1**, unlisted; its doc comment states the rule the
  lane deletes and is rewritten, not renumbered).

Both tests' **child-rect** assertions stayed green, so only the measurement
fixtures move. Checked green in the same run and therefore not owed a
re-fixture: `aNativeFrameWithInfiniteMaximumExpandsToItsFiniteProposal` (its
child is smaller than its proposal, so `FR-M` changes nothing),
`negativeAndNegativeInfiniteFrameMinimumsAndAnInfiniteMaximumAreAccepted` (the
one existing negative-minimum test — its four arms still read 20, 20, 100, 20),
`TrackInteractionTests:62/64`, `ModifierCompositionProofTests:855`,
`ProposalLayoutTests:364/380`, `NativeLayoutWorkTests:81`,
`SizingFixtureTests:324` (a CSS `newNode`) and all of
`NativeLayoutIntegrationTests`.

#### The legacy lowering — scratch `ZZScratchFrame2Tests.swift` (N1–N15)

Deleted before commit; `git status --short` afterwards showed only the new
probe. `Mark` is a childless `StyledElement` recording the bounds its `prepaint`
receives; `frameBox` is a hand-built stand-in for `FrameSpec.style()`.

| arm | shape | measured |
|---|---|---|
| N1 | `.frame(200×100)` ×2 in a 150pt `Column` | no pin: marks at y = 28/103 (layers 75 each). `flexShrink 0`: y = 40/140 (100 each) |
| N2 | `.frame(height: 40)` ×2 over 200pt content in a 300pt `Row` | identical with and without `flexShrink 0` — the automatic minimum already floors them, so this arm does not discriminate |
| N3 | both axes fixed, 100×100 ×2 in a 150pt `Column` | as N1 |
| N4 | a bare mark vs a mark in an empty-styled layer | node count **2 → 3**, geometry identical: a lowering-to-nothing costs a node and does nothing (finding 7) |
| **N5** | `.frame(60×40)` over a child declaring 200×160 | the child is **(0, 20) 60×160** — width **squeezed** to the frame, height overflowing. SwiftUI's A5 keeps 200×160 at (−70, −60). `FR-N` |
| N6 | N5 with `flexShrink 0` on the layer | identical — the layer did not shrink, the **child** was shrunk as its flex item |
| N7 | the demo's shape, `.minHeight(px(0))` on the growing box | inner content **120** |
| N8 | the same with no `minHeight` — the control | inner content **400** |
| N9 | `.frame(minHeight: 0)` layer, `flexGrow`/`flexBasis` on the LAYER | **400** |
| N9b | the same with `flexGrow`/`flexBasis` on the inner box | **400** |
| **N10** | L9's shape: `.frame(200×20)` ×2 in a 300pt `Row` | no pin: marks at 65/215 (layers 150 each). `flexShrink 0`: 90/290. **`minSize.width = 200`: 90/290 — identical** |
| **N11** | `.frame(height: 40)` around a wrapping `Text` in an over-constrained 300pt `Row`, sibling's x reads the layer's width | no pin: **154**. `flexShrink 0`: **210** (the text did not wrap — a WIDTH the caller never declared). `minSize.height = 40`: **154**, identical to no pin |
| N12 | `.frame(width: 200)` ×2 in a height-constrained `Column` | all three identical — the automatic minimum floors them; does not discriminate |
| N13 | `.frame(100)` inside `.frame(50)` and the reverse, with and without the `minSize` pin | 15 and 40 in all four — the probe's E1/E2, unchanged by the pin. **Also records that M1 never discriminated**: a 100pt inner overflowing a 50pt outer and one shrunk to 50 both centre a 20pt leaf at 15 |
| **N14** | a 20×20 mark in a layer with `flexGrow 1` + `alignSelf .stretch`, in a 300×200 frame | `Row`: (0, 90) → **(140, 90)**. `Column`: (140, 0) → **(140, 90)**. It fills both axes in both parents |
| N15 | N14 with a sibling present | the fill lowering in a `Column` pushes the sibling from y = 20 to **y = 195** — why it must not be applied to a single infinite axis |

#### The legacy lowering's blast radius, run rather than predicted

Each candidate applied in turn to the live `ElementGroup.frame(width:height:)`
and the **whole** suite run:

| lowering | result |
|---|---|
| `size` + axis-named `minSize` (`FR-P`) | `Test run with 1231 tests in 1 suite passed` |
| `flexShrink = 0` on any fixed axis | `Test run with 1231 tests in 1 suite passed` |

1231 is 1226 plus the five scratch tests. **No existing test moved either way**,
across the 52 `.frame(` call sites in ten test files. So the spec's "one oracle
edit" claim is refuted as a *redness* obligation and restated as a *drift* one:
`ModifierCompositionProofTests`'s hand-built `frameStyle(width:height:)`
(line 503) is a duplicate of the lowering, and the suite has just demonstrated
it will not tell you when the two diverge.

### Lanes

*Each lane appends here: its commits, red runs (quoted `Test run with N tests`
lines and issue text), mutation runs with the tests each reddened, the
suite/guard/golden counts it re-took, and lane 4's pixel comparison — image
dimensions, differing-pixel counts and the control counts that must be
non-zero.*

#### Lane 1 — the shared-file seam, then the kernel's flexible frame, 2026-09-15

Three commits, in this order:

| commit | what |
|---|---|
| `901917a` | **step 0, alone**: `ModifiedElement.swift`'s trailing `frame(width:height:)` extension replaced IN PLACE by a forwarding declaration into the new `Sources/MetalUI/FrameLayer.swift` (`FrameSpec` + `style()`, today's style verbatim). No behaviour change, no test touched |
| `9bd130c` | the red tests: 1.1–1.6 and 1.9 new, 1.7 and 1.8 re-fixtured in place, 1.10 a new typecheck fixture in `Tests/MetalUITests/FrameSizingCompileGuards.swift` |
| `389c452` | the source: `framedSize`, `framedProposal`, `newNativeFrame`'s doc comment, and the deprecated `frame()` on both protocols |

**Step 0's run.** `Test run with 1226 tests in 1 suite passed after 30.990
seconds`, 0 `error:`, 0 `warning:`; 97 goldens, `git diff --stat c4b5853 --
'*.json'` empty. The seam moved none of the three counts, which is what it was
for.

**The red run**, `swift test --build-system native --no-parallel` on `9bd130c`:
`Test run with 1234 tests in 1 suite failed after 30.849 seconds with 11
issues`.

| test | issue, verbatim |
|---|---|
| 1.7 `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum` | `NativeLayoutTests.swift:173:5: Expectation failed: (measurement.size → SizeD(width: 40.0, height: 70.0)) == (SizeD(width: 80, height: 60) → …)` |
| 1.8 `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes` | `:214:5: (measurement.size → SizeD(width: 70.0, height: 20.0)) == (SizeD(width: 70, height: 60) → …)` |
| 1.1 `aFrameWithAMinimumAndAMaximumGrowsTowardItsProposal` | `:297:5: (dControl.answer → 40.0) == (80 → 80.0)` and `:301:5: (d1.answer → 40.0) == (60 → 60.0)`. **D2 and D13 stayed green** — the arms that read the same under both rules, this test's internal controls |
| 1.4 `anIdealDimensionIsUsedOnlyWhenThatAxisHasNoProposal` | `:374:5: (… minWidth: 40, idealWidth: 80, maxWidth: 120).answer → 40.0) == (120 → 120.0)`, C5. C1, C control, C3 and C4 green |
| 1.5 `aFrameWithoutAMinimumNeverAnswersLessThanItsChild` | `:394:9: (h8.answer → 20.0) != (h14.answer → 20.0)` — the opening shape-15 `#require`; the two arms agreed, which is `FR-M` |
| 1.6 `aFrameNeverAnswersANegativeSize` | `:432:9: (h2.childProposals → [Optional(-30.0)]) != (h4.childProposals → [Optional(-30.0)])` — the opening `#require`; both forwarded −30 |
| 1.9 `aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI` | `NativeLayoutIntegrationTests.swift:1019:5: (probe.prepaintBounds?.origin.x → Pixels(value: 10.0)) == (Pixels(30) → …)` — exactly the 40-and-x-10 the spec predicted |
| 1.10 `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths` | `:102/:104/:106` — `succeeded=false deprecations=0`, `error: cannot convert value of type 'ModifiedContent<ProposalLeaf>' to specified type 'ProposalLeaf'` and `'ModifiedElement<LegacyLeaf>'` likewise |

1.2 and 1.3 were **green on arrival**, as the spec says; their proof is their
mutations below.

**The green run**, on `389c452`: `Test run with 1234 tests in 1 suite passed
after 30.393 seconds`, 0 `error:`, 0 `warning:`. Goldens 97, diff against
`c4b5853` empty. Guards: per-file `grep -c canTypecheck` sums to **63** outside
`Typecheck.swift`, one of which is the comment in `UnitSafetyTests.swift`, so
**62** real — 61 → 62 as designed.

**Test 1.9's container, chosen by mechanism.** The spec said "in a 200-wide
root"; three containers had to be reasoned through before one could show the
finding, and the reasoning is recorded so nobody re-derives it. An `HStack`
proposes `nil` on its main axis (`stackChildProposal`), so a greedy frame there
answers its child either way and the arm cannot discriminate. A `ZStack`, and
the framed element as the root, both place the frame in the FULL window bounds
— `placeNative`'s `.frame` case places its child inside the bounds it was
handed, not inside its own measurement — so the leaf lands at x = 90 under both
rules. A **`VStack(alignment: .leading)`** proposes its own width to every
child and places each at `bounds.x` at the child's *measured* width, which is
the only shape in which the frame's answer is observable as an x: 80 → x = 30,
40 → x = 10.

**Mutations**, each applied to a `cp` backup's file, the WHOLE suite run, the
file restored and `git status --short` checked empty. Every run read `Test run
with 1234 tests`.

| # | mutation | tests reddened |
|---|---|---|
| M1 | `max != nil` → `max == .infinity` (the shipped greedy gate) | **7**: 1.1, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9 |
| M2 | the greedy branch unconditional (`if let proposal, proposal.isFinite`) | **5**: 1.2, 1.4, 1.6, and two nobody wrote for it — `aNativeFrameForwardsAnOptionalAxisAndAdoptsThatChildResponse`, `negativeAndNegativeInfiniteFrameMinimumsAndAnInfiniteMaximumAreAccepted` |
| M3 | `proposal.isFinite` dropped | **1**: 1.3 only. Nothing else in 1234 tests sees `FR-B` |
| M4 | the first two branches **swapped** | **none** — they are mutually exclusive. `FR-R` item 3; the spec's claim is withdrawn |
| M5 | `min == nil` → `(min ?? 0) == 0` | **1**: 1.5, at its `#require` (`h8.answer → 20.0 != h14.answer → 20.0`). H14 is the only arm that can see it |
| M6 | `Swift.max(proposal, child)` → `proposal` | **2**: 1.5 (`h8 → 10.0 != h14 → 10.0`) and 1.6 (`h2.answer → 0.0 == 20`) |
| M7a | `framedSize`'s `lo` unfloored | **1**: 1.6 (`h4.answer → -30.0 == 0`) |
| M7b | `framedSize`'s **`hi`** unfloored | **none** — unreachable; `SA-J` traps on a negative maximum first. `FR-R` item 2 |
| M8 | `framedProposal`'s `lo` unfloored | **1**: 1.6, at its `#require` |
| M9 | the ideal branch deleted | **4**: 1.4, 1.8, `anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified`, `anIdealFrameHeightBecomesItsOuterHeightWhenTheAxisIsUnspecified` |
| M10 | the `frame()` declaration on `ElementGroup` deleted | **1**: 1.10 — `succeeded=false deprecations=1`, `error: cannot convert value of type 'ModifiedElement<LegacyLeaf>' to specified type 'LegacyLeaf'`. The LEGACY call falls through to `frame(width:height:)` |
| M11 | the `frame()` declaration on `ProposalElementGroup` deleted | **1**: 1.10 — `succeeded=false deprecations=1`, `error: cannot convert value of type 'ModifiedContent<ProposalLeaf>' to specified type 'ProposalLeaf'`. **Critic finding 11's simplification, reinstating `SA-N` item 9, now measured on the real module rather than on the skeleton** |

M10 and M11 each needed `swift build --build-system native --build-tests` before
the suite run, because the fixture typechecks against the built `MetalUI`
module, not against the sources. **That is also the proof the new guard RUNS in
this worktree** (CLAUDE.md, "When CI lands"): it was red on arrival at `9bd130c`,
green at `389c452`, and red again under each of two source deletions.

**The sweep the critic round predicted, confirmed.** The design said applying
`FR-A` + `FR-L` + `FR-M` reddens exactly two existing tests, 1.7 and 1.8. The
green run confirms it from the other side: with those two re-fixtured and
nothing else edited, all 1234 pass. M1 and M2 additionally name three existing
tests that would have caught a *wrong* fix —
`aNativeFrameForwardsAnOptionalAxisAndAdoptsThatChildResponse`,
`negativeAndNegativeInfiniteFrameMinimumsAndAnInfiniteMaximumAreAccepted` and
the two ideal-frame integration tests — which is the coverage the design could
not see by reading.

**Three design corrections, ruling `FR-R`:** the expected total is 1234 (a
typecheck guard is a `@Test`); probe arms H6 and H10 have no MetalUI spelling,
so test 1.6 carries four arms and `framedSize`'s `hi` floor is an unreachable
backstop; and swapping `framedSize`'s first two branches is not a mutation.

**Left for lane 2 and after.** `FrameSpec` still carries only `width`/`height`
and `style()` still produces exactly the pre-existing style — step 0 was a move,
not a change. `ProposalAlignment`, the min/max bounds and the lowering table are
lane 2's.

#### Lane 2 — the legacy frame's SwiftUI surface, 2026-09-15

Three commits:

| commit | what |
|---|---|
| `c5a02a0` | the red tests: 2.1–2.10 in the new `Tests/MetalUITests/FrameSizingTests.swift`, plus the broadened overload fixture in `FrameSizingCompileGuards.swift` |
| `44a79b5` | the source: `FrameSpec`'s six bounds and alignment, `style()`'s lowering table, the flexible overload with `FR-D`'s trap, the fixed overload amended in place in `ModifiedElement.swift` (`FR-S`), and BOTH hand-spelled `frameStyle` oracles |
| `dda9c6f` | tests 2.7 and 2.9 strengthened after two mutations reddened nothing |

**Step 1, before any test: the overload skeleton, re-run and then re-taken
against the real module.** The skeleton is now committed as
`docs/probes/swift-frame-overload-resolution.swift` (three variants by flag,
every `frame` body printing which declaration ran, so two overloads returning
the same type can be told apart). All seven inference rows hold — the refined
protocol wins `.frame(width:)`, `.frame(width:height:alignment:)`,
`.frame(minWidth:idealWidth:maxWidth:)`, `.frame(idealWidth:)`,
`.frame(maxWidth:)`, `.frame(alignment:)` and `.frame()` — and both
`extra argument 'minWidth' in call` / `extra argument 'minHeight' in call`
diagnostics are verbatim, on both paths, against the largest overload set. **No
row moved, so no test was written against a changed row.** The same seven rows
were then asserted against the real module by the new guard.

**What the skeleton could not see, and the suite could** (ruling `FR-S`). With
both a two- and a three-parameter fixed legacy overload the skeleton is happy:
nothing ambiguous, `.frame(width:)` silently takes the two-parameter body. The
whole-suite run on the scratch stub reddened
`aTwentyFourModifierChainTypechecksWithinASolverWorkBudget` (`MC-A`) instead.
Measured directly against the built module with that guard's own command line:

| fixed legacy overloads | `-solver-scope-threshold` |
|---|---|
| two | fails at 1000, 2000, 4000, 8000, **16000** |
| one (`width:height:alignment:`) | **186** ok, 180 fails — the same 186 `MC-A` measured before this lane |

So `ModifiedElement.swift` is touched exactly once more, in place: the fixed
overload's signature gains `alignment:` and forwards it. Two lines.

**Red run 1**, `swift build --build-system native --build-tests` on the tests
alone: the target does not compile, 13 errors —
`FrameSizingTests.swift:141:66: error: extra argument 'alignment' in call` and
`:308:69` likewise (2.1 and 2.5's aligned arm), and `argument passed to call
that takes no arguments` at `:205 :208 :211 :243 :250 :254 :449 :455 :460 :479`
(every flexible spelling; the deprecated no-argument `frame()` is the only
candidate left).

**Red run 2**, against a scratch stub declaring both overloads and lowering
exactly as step 0 did (applied, run, restored from a `cp` backup, `git status
--short` clean afterwards): `Test run with 1245 tests in 1 suite failed after
34.371 seconds with 10 issues`.

| test | issue, verbatim |
|---|---|
| 2.1 | `:148:9: (topLeading → (20.0, 10.0)) != (centre → (20.0, 10.0))` — the shape-15 `#require` |
| 2.2 | `:194:5 Origin(…["a"]).x == 90` and `:195:5 … == 290` (the layers shrank to 150) |
| 2.3 | `:224:9: (minimum → 20.0) != (maximumOverASmallChild → 20.0)` — no bounds lowered |
| 2.4 | `:252:23: .failure → .exitCode(0)`, `:257:5: (widthError → "").contains("idealWidth")`, `:260:11: .failure → .exitCode(0)` |
| 2.5 | `:324:5: Origin(…["leaf"]) == Origin(20, 10)` — the aligned third arm |
| 2.9 | `:480:9: (filledOrigin → (0.0, 90.0)) != (inertOrigin → (0.0, 90.0))` |

2.6, 2.7, 2.8 and 2.10 were **green on arrival**, as characterizations. The
tenth issue was `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget`,
which is `FR-S` above.

**The green run**, on `44a79b5`: `Test run with 1245 tests in 1 suite passed
after 34.599 seconds`, 0 `error:`, 0 `warning:`. Goldens 97, diff against
`c4b5853` empty. Guards: per-file `grep -c canTypecheck` sums to **64** outside
`Typecheck.swift`, one of which is the comment in `UnitSafetyTests.swift`, so
**63** — 62 → 63 as designed. The oracle edit was made in the same commit and
the suite read 1245 passed **both before and after it**, which is the
measurement behind calling it a drift obligation rather than a redness one;
`modifierOrderChangesSizeAndPlacementAsSwiftUIDoes` was then run alone and
passes untouched.

**Two mutations reddened nothing, and both were the instrument** (commit
`dda9c6f`).

- **`alignSelf = .stretch` dropped → nothing in 1245 tests.** Test 2.9's fill
  arms centred their mark, and a mark centred in a 20pt-tall layer at y = 90
  and one centred in a 200pt-tall layer at y = 0 sit at the same y. Two
  `.topLeading` arms were added — (0, 0) filled, (0, 90) in a `Row` and
  (140, 0) in a `Column` unstretched — and the mutation then reddens exactly
  those two.
- **A fixed `size.height` of 40 on the frame layer → 2.6 and 2.9, never 2.7.**
  Tried twice: with forty 14pt rows in a 600pt viewport (every arm builds every
  row, so the count could not move) and then against a real window (forty 40pt
  rows, two frames sharing a `StateTable`, because frame 0 has no measured
  viewport and builds every row, MP-I). The mechanism is divergence 14: `List`
  computes its window against the enclosing **scroller's** origin and viewport,
  ignoring where the list itself sits, so no geometry the layer imposes can
  reach the window. 2.7's doc comment now says so, and its only mutation is the
  broad one below.

  Looking for an observable the lowering *does* reach turned up a finding worth
  keeping, now pinned by 2.7: with 400pt rows the three arms read **400**
  unframed, **200** under `.width(200)` and **400** under `.frame(width: 200)`.
  A 200pt frame layer cannot narrow the list inside it, because flex §4.5's
  automatic minimum floors the list at its rows' min-content width — `FR-G`'s
  mechanism from the other side, and the sharpest available statement of
  `FR-F`.

**Mutations**, each applied to a `cp` backup's file, the WHOLE suite run under
`swift test --build-system native --no-parallel`, the file restored and `git
status --short` checked. Every run read `Test run with 1245 tests`.

| # | mutation | tests reddened |
|---|---|---|
| M1 | the alignment switch's `justifyContent` dropped | **8**: 2.1 (six arms), 2.2, 2.5, 2.9, `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`, `chainedFramesRemainConcreteAndNestTheirLayoutNodes`, `aGenericWrapOverAChainIsIdenticalToTheFlatChain`, `aModifierChainIsIdenticalToHandBuiltNestedBoxes`, `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes` (27 issues) |
| M2 | the switch's `alignItems` dropped | **8**: 2.1 (six arms), 2.5, 2.6, 2.8, 2.9 and the same four oracles (29 issues). A first attempt reached only three of the nine cases and reddened two arms — a mutation that does less than it says |
| M3 | the switch's two axes swapped | **1**: 2.1, at six arms |
| M4 | `minSize` dropped from the fixed rows | **1**: 2.2 only |
| M5 | the axis-named pin replaced by `flexShrink = 0` | **1**: **2.10** only — `(framed → 0.0) == (bare → 123.0)`; 2.2 stays green, which is `FR-P`'s whole finding |
| M6 | `minSize` dropped from the flexible minimum row | **1**: 2.3, at its `#require` |
| M7 | `maxSize` dropped | **1**: 2.3, at its second arm |
| M8 | the `idealWidth` precondition made unconditional | **1**: 2.4, at the `idealWidth` arm and the stderr assertion |
| M9 | `size.width` dropped from the fixed rows | **4**: 2.1, 2.5, 2.6, 2.8 |
| M10 | a fixed `size.height` of 40 on the layer | **2**: 2.6, 2.9 — **not 2.7**, twice, see above |
| M11 | `flexDirection` set to `.column` | **4**: 2.8 (both arms), 2.1, and the two `ComponentTests` frame tests |
| M12 | `alignSelf = .stretch` dropped | **1**: 2.9, at both `.topLeading` arms (**none** before they existed) |
| M13 | `flexGrow = 1` dropped | **1**: 2.9, at its opening `#require` |
| M14 | the fill extended to a single infinite maximum | **1**: 2.9, at the same `#require` |
| M15 | `ProposalElementGroup`'s fixed overload removed | **the package stops compiling**: `main.swift:1004` (`.border` on a `ModifiedElement`) and `ModifierCompositionProofTests.swift:768` (`HStack` requires `ProposalElementGroup`). The mis-resolution is caught by 52 existing call sites — as a cascade, which is why the new guard asserts the inferred type instead |
| M16 | the two-parameter fixed overload re-declared | **1**: `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget` (`FR-S`) |
| M17 | the outermost layer's child list dropped (`ModifiedElement.requestLayout`) | **~25 tests, 102 issues**, 2.7 among them — the only mutation that reddens 2.7, and the reason it is recorded here rather than claimed as that test's own |
| M18 | `ProposalElementGroup`'s flexible overload's `idealWidth:` label renamed | **2**: the new guard (`cannot convert value of type 'ModifiedElement<ProposalLeaf>' to specified type 'ModifiedContent<ProposalLeaf>'`) and 2.4's proposal control (`.success → .signal(SIGTRAP)` — the proposal element fell into the legacy trap). **This is the proof the new guard runs in this worktree** rather than skipping |

**The demo's pixels cannot move, and it is a compile-time fact rather than a
comparison.** `Sources/MetalUIDemo/main.swift` contains exactly two `.frame(`
call sites, 1003 and 1032, and **both are on proposal elements** — the chain at
1003 ends in `.border(...)` and the one at 1032 is the preview's outermost
element, and neither of those spellings exists on a `ModifiedElement`. So the
demo reaches `FrameSpec.style()` nowhere, and lane 2 changed nothing else that
a rendered frame can see. (Mutation M15 is the same fact read backwards: remove
the proposal path's fixed overload and `main.swift:1004` stops compiling,
because the chain becomes a `ModifiedElement`.) Lane 4 still owes the offscreen
comparison of the whole demo and preview against `c4b5853`, for lane 1's kernel
change.

**Stale-comment sweep.** `NativeModifiedContent.swift`'s fixed proposal frame
and `EnvironmentScope.swift`'s "`.frame(width:height:)` may follow a scope" were
refreshed (`316237b`). **`ModifiedElement.swift`'s file header, line 4, still
spells the legacy frame `.frame(width:height:)`** and was left alone on purpose:
it is the top of a file the parallel paint-modifier track also edits, and a
second hunk there trades a comment's accuracy for a merge conflict. Integration
owns that one word.

**Left for lane 3 and after.** `Box.swift`'s `MARK: Size` documentation, the
percentage divergence test (3.1) and the node-count/automatic-minimum test
(3.2) are untouched; `FR-F`…`FR-I` and `FR-Q` are still design only. Lane 2
added no integration obligation beyond the ones §14 already lists, except that
`FR-S` makes "there is exactly one fixed `frame` overload on `ElementGroup`" a
property a merge must not break: re-introducing a second one compiles, and only
`MC-A`'s solver-budget guard will say so.

### Open at the end of the critic round

- Two of `MC-Q` finding 7's four handed-over shapes are **not** covered by this
  design: a **nil axis** in a modifier-order chain, and a **stretching `Box`
  parent** (EP-8). The shrinking row is `FR-P`'s `minSize` pin (test 2.2) and
  the smaller frame is tests 2.5 and 2.8.
- The `Column` percentage defect (M4, ≈30000pt) is pinned as measured by spec
  test 3.1 and its mechanism is not investigated.
- `FR-D`'s `flexBasis`-as-ideal idea is unmeasured.
- **`SA-J` still accepts a negative minimum**, which `FR-L` now floors at 0 in
  `framedSize` rather than rejecting at registration. SwiftUI diagnoses a
  negative fixed size and a negative maximum and tolerates a negative minimum;
  MetalUI traps on the first two and floors the third. Tightening the
  registration is the kernel track's ruling to change — task 7. **Lane 1 found
  the consequence**: `framedSize`'s `hi` floor is unreachable and no test can
  see it (`FR-R` item 2).
- N2 and N12 did not discriminate: the flex automatic minimum floors those
  shapes before any pin can matter. The cross-axis finding rests on N11 alone,
  which is why N11 gets its own test (2.10) rather than an arm inside 2.2.
- The release-window captures stay owed (`MC-J`, `EV-P`); lane 4 checks
  `IOConsoleLocked` and records the refusal if the session is locked.
