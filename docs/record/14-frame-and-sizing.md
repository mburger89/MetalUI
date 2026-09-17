## Frame and sizing (plan task 4) — `feat/frame-sizing`, from 2026-09-15

The record for plan task 4. Spec
`docs/superpowers/specs/2026-09-15-frame-sizing-design.md`; rulings `FR-A`…
`FR-V` in `docs/superpowers/2026-09-15-frame-sizing-decisions.md` (next unused
`FR-W`); probes `docs/probes/swiftui-frame-semantics.swift` (54 arms),
`docs/probes/swiftui-frame-negative-sizes.swift` (17 arms),
`docs/probes/swift-frame-overload-resolution.swift` (the Swift compiler, three
variants by flag) and `docs/probes/appkit-screen-lock-state.swift` (the
pre-capture check; a probe of the machine, not of SwiftUI). The track runs in
its own worktree, `/Users/maxburger/Developer/MetalUI-frame-sizing`, beside the
paint-modifier track, and is merged by an integration step that owns
`CLAUDE.md`, the plan, `docs/record/README.md` and the other track's files.
**Nothing in this file has been copied into those yet**; "For the integrator",
the last section, says what each should say.

**How this file was written.** The design-session, critic-round and lane
sections were written as each landed (commits `4796bbb`, `d70a4a5`, `8a0fd9c`,
`66e5498`, `798b1fb`, `b513fa3`, `7d5a3a7`, `6c18389`). The session that ran
lanes 1 and 2 and verified them was cut off by a usage limit on 2026-09-15 at
21:46 PDT: lane 3's and lane 4's verifier verdicts survive and are quoted in
their "Verifier round" subsections; lane 1's and lane 2's do not, and "Lanes 1
and 2 — the verifier tables, reconstructed" says what can and cannot be
recovered, figure by figure. The summary sections from "What landed, in one
place" onward were written on 2026-09-16 at `6c18389`, in the commit after it.

Integration obligations this track creates for CLAUDE.md, which it may not edit
itself, are itemised under "For the integrator". The short list: a
**declared-but-inert row** for a single-axis `.frame(maxWidth: .infinity)` on
the legacy path (`FR-O`); `.frame(width:height:alignment:)`'s lowering pins
its declared axis with an axis-named `minSize` (`FR-P`); `ElementGroup` must
keep exactly ONE fixed `frame` overload (`FR-S`, or long modifier chains stop
compiling); **a frame with a maximum is greedy on the proposal path** (`FR-A`,
`FR-M`) with two divergences worth a line — an infinite proposal answers the
child rather than infinity (`FR-B`), and a negative maximum or fixed size
**traps** where SwiftUI floors it at 0 (`FR-L`, `FR-R` item 2); three legacy
divergences pinned wrong on purpose (`FR-E`, `FR-N`, `FR-O`);
`idealWidth`/`idealHeight` trap on the legacy path (`FR-D`);
**`width(percent:)` takes a fraction** (`FR-T`); and `IOConsoleLocked` is not
the screen-lock check (`FR-V`). The suite total moves 1226 → 1234 (lane 1) →
1245 (lane 2) → **1247** (lane 3); guards 61 → 62 → **63**; goldens **97**
throughout, `git diff --stat c4b5853 -- '*.json'` empty at every lane.

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
| L4 | `Box { Mark }.onClick {}.frame(width: 60, height: 40)` | the hitbox is **0×0 at (30, 20)** | **by reading, unprobed**: no saved probe measures a gesture's hit area before a frame. Only the background half is probed (`swiftui-modifier-order.swift` O1: a `GeometryReader` background before the outer frame reads 20×20). *(Corrected at `957b068`'s verifier round; this cell said "the same in SwiftUI".)* |
| L6 | nine `justifyContent` × `alignItems` combinations on a 60×40 layer over a 20×20 child | `(0,0) (0,10) (0,20) (20,0) (20,10) (20,20) (40,0) (40,10) (40,20)` | B1–B8 exactly |
| L9 | `Row { Mark.frame(200×20); Mark.frame(200×20) }` in 300pt | marks at x = **75 and 225** — each layer shrank to 150. The critic round's **N10** re-took it at x = 65/215 with a slightly different probe and reached the same finding | a fixed frame never shrinks |
| L10 | in a 300pt `Row`, width read from a 5pt sibling's x | `maxWidth 80` over a 20pt child → **20**; `minWidth 40` → **40**; `maxWidth 80` over a 200pt child → **80**; `.frame(width: 80)` → 80 with the child centred at 30 | D4 → 80 (**diverges**); D7 → 40; D14 → 80; A1 |
| L11 | `Column { Text("alpha bravo charlie delta").font(size: 12).frame(width: 60); marker }` | the marker sits at y = **60** — four 15pt lines — against y = **15** unframed; `.width(60)` reads 60 too. In a `Row` the framed and styled advances are 60 against the bare text's **139** | F1 60×60, F control 139×15 — the same numbers |
| L12 | `ScrollView { List(40 rows).frame(width: 200) }` | **40** painted row rects, the same as unframed and as `.width(200)` | — |
| L13 | `Row` of two frames whose children declare 200pt | no shrink either way; the automatic minimum floors them | — |
| L14 | L9 plus `.flexShrink(0)` on each layer | marks at **100 and 300** — 200 each, no shrink. **Superseded as the lowering** by `FR-P`: N11 shows `flexShrink = 0` pins an axis the caller never declared, and N10 shows an axis-named `minSize` is equivalent where it was right | matches SwiftUI |
| M1 | `Mark(20).frame(width: 100).frame(width: 50)` | root **50**, leaf at x = **15**. Reversed: root **100**, leaf at x = **40**. Unchanged without `.flexShrink(0)` — the inner frame does not shrink inside another frame | E1 (50, leaf 15) and E2 (100, leaf 40) exactly |
| M2 | greediness in a 300pt `Row` | `flexGrow(1)` fills to 295; `flexGrow(1) + maxWidth(80)` stops at **80**; plain reads 20. In a `Column`, `alignSelf(.stretch)` puts a child at x = 0 where an unstretched box's child is centred at 140 | D4's 80 — reachable, but only on the axis that happens to be main |
| M4 | `width(percent: 100)` | in a `Row` the sibling moves to x = **300** (fills); capped by `maxWidth(80)` it reads 80. **In a `Column` the child lands at x ≈ −14850**, implying a box about 30000pt wide. Mechanism not investigated — **investigated by lane 3 and it is not a defect**: `percent:` takes a FRACTION, so this is 100 × 300 centred on EP-8's cross axis. Ruling `FR-T` | — |

**Three claims the plan made about the reverted 2026-09-12 conversion, tested.**
The plan says the trial "broke list virtualization, hit testing, and text
measurement", and record §09 notes no measurement of it exists.

- **Text measurement: refuted.** L11 — a frame layer's width reaches a measured
  leaf and re-wraps it, to SwiftUI's own numbers.
- **List virtualization: refuted.** L12 — the framed list paints the same rows.
- **Hit testing: confirmed, and it is not a defect.** L4 — a handler declared
  before the frame stays on the content, which is what SwiftUI does with
  `.background` before `.frame` (probe O1); that a SwiftUI gesture's hit area
  does the same is by reading, unprobed. What actually blocks the conversion is the
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

#### Lanes 1 and 2 — the verifier tables, reconstructed, 2026-09-16

Both lanes were verified `ok` by independent agents in the session that was
cut off on 2026-09-15 at 21:46 PDT, and **both verdicts are lost** with it:
neither the verifiers' suite lines, their own mutations, their issue lists nor
the required changes they asked for survive anywhere in the repo or the
scratchpad. This subsection is the honest substitute, written on 2026-09-16
at `6c18389`. Every figure below is labelled **quoted** (it is in a committed
file and can be re-read), **corroborated** (an independent later run reproduced
it), or **reconstructed** (inferred from what the commits and the decisions doc
say; not itself a measurement).

**What survives of the verdicts themselves.** One sentence, from the
continuation brief: "Lanes 1 and 2 verified ok (suite 1245 at lane 2's
verification)." That 1245 is consistent with lane 2's own green run
(`44a79b5`, `Test run with 1245 tests in 1 suite passed`) and with `FR-R`
item 1's corrected count; it is the only verifier-originated number for either
lane. **Reconstructed**: that both verdicts had `goldensUnchanged: true`
(every lane's own run read 97 with an empty diff, and lane 4's clean re-take
at `b513fa3` and again at `7d5a3a7` read the same), and that whatever issues
they raised were applied before the lane's record commit — commit `dda9c6f`
("strengthen 2.7 and 2.9, which two mutations could not redden") is the shape
a verifier-fix commit takes, and lane 2's record says those two mutations
were run by the lane itself, so it may equally be the lane's own finding.
Nothing distinguishes the two readings now.

**The mutation tables, cross-checked today.** The lane sections above carry
the implementers' tables (`8a0fd9c`: eleven mutations; `66e5498`: eighteen).
The decisions doc carries a per-ruling "Mutations" line for each ruling the
lanes landed. The two were compared line by line on 2026-09-16, and **every
row in one appears in the other with the same reddened set** — so the tables
are internally consistent, which is the most that can be said without the
verifiers' independent runs:

| ruling | its Mutations line names | record rows | consistent |
|---|---|---|---|
| `FR-A` | the greedy gate restored to `== .infinity`; the branch made unconditional; the ideal branch deleted; the two branches swapped (none) | lane 1 M1, M2, M9, M4 | yes, sets identical |
| `FR-B` | `proposal.isFinite` dropped → 1.3 alone | M3 | yes |
| `FR-J` | the `ElementGroup` and the `ProposalElementGroup` `frame()` declarations deleted, each → 1.10 alone | M10, M11 | yes |
| `FR-L` | `lo` unfloored in `framedSize` and in `framedProposal`; `hi` unfloored (none) | M7a, M8, M7b | yes |
| `FR-M` | presence test as a value test; `Swift.max` dropped | M5, M6 | yes |
| `FR-C` | `justifyContent` dropped; `alignItems` dropped; axes swapped; `size.width` dropped; `flexDirection = .column` | lane 2 M1, M2, M3, M9, M11 | yes |
| `FR-D` | the `idealWidth` precondition unconditional | M8 | yes |
| `FR-E` | `minSize` dropped from the flexible minimum row; `maxSize` dropped | M6, M7 | yes |
| `FR-N` | `flexDirection = .column` | M11 | yes |
| `FR-O` | `alignSelf` dropped; `flexGrow` dropped; the fill extended to a single axis | M12, M13, M14 | yes |
| `FR-P` | `minSize` dropped from the fixed rows; the pin replaced by `flexShrink = 0` | M4, M5 | yes |
| `FR-S` | the two-parameter overload re-declared; the proposal fixed overload removed; the proposal `idealWidth:` label renamed | M16, M15, M18 | yes |
| (record only) | the frame layer's `size.height` of 40 (critic finding 16); the outermost layer's child list dropped | M10, M17 | in the record and the critic ledger, not under a ruling |

**What was independently re-run later, and by whom** — the only corroboration
of any lane 1 or lane 2 mutation that exists:

| lane / mutation | re-run by | result |
|---|---|---|
| lane 1 M10, `ElementGroup.frame()` deleted | lane 4 (A), twice: 2026-09-15 at `b513fa3`, 2026-09-16 at `7d5a3a7`; lane 4's verifier a third time at `6c18389` | **corroborated**: `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths` alone, `succeeded=false deprecations=1`, `1247 … failed … with 2 issues` |
| lane 2 M18, the proposal `idealWidth:` label renamed | lane 4 (B), the same three times | **corroborated**: `everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload` and `anIdealDimensionOnTheLegacyFrameTraps`, `failed … with 2 issues` |
| lane 2's `_wrap` on `frame(width:height:alignment:)` doubled | lane 3 (L4) and lane 3's verifier (M4) | **corroborated with a smaller set**: 7 tests / 13 issues, not the lane's 8 / 18 — see lane 3's L4 row and its verifier round |
| the kernel patch sweep (`FR-A` + `FR-L` + `FR-M`: exactly two existing tests redden) | the critic round, then lane 1's green run from the other side | **quoted**, both in this file |

Everything else in the two lane tables — the reddened sets of lane 1's M1–M9
and M11 and lane 2's M1–M17 — is **quoted from the implementer's commit and
uncorroborated**. The guard-runs-in-this-worktree claims (lane 1's M10/M11,
lane 2's M18) are corroborated by lane 4's re-runs above; lane 1's second
guard proof, M11, has no re-run of its own.

**What cannot be reconstructed, said plainly.** Whether either verifier ran a
mutation the lane had not; whether either raised an issue the lane's record
commit does not reflect; and the verifier's own suite line for lane 1. The
practices doc's rule — findings come from mutation, not inspection — is met
for lanes 1 and 2 by the implementers' runs and by the four corroborations,
not by the independent verification the process intended.

#### Lane 3 — the sizing inventory, 2026-09-15

Two commits:

| commit | what |
|---|---|
| `10dcc60` | the tests: 3.1 and 3.2 appended to `Tests/MetalUITests/FrameSizingTests.swift`, reusing lane 2's `Mark`/`render`/`widthInRow`/`nodeCount` fixtures (they are file-private, which is why the tests live in that file rather than a new one) |
| `a316916` | the documentation: `Box.swift`'s `MARK: Size` section and the three `Edges<Length>` overloads, plus `flexBasis(percent:)` and `Length.percent` in `MetalUICore/Units.swift` |

**There was no red run, and that is the lane's shape rather than a lapse.**
Lane 3 is the documentation lane: both of its tests characterize shipped
behaviour, so they were green the moment they compiled (`Test run with 1247
tests in 1 suite passed after 32.741 seconds` on `10dcc60`, 0 `error:`, 0
`warning:`). Their whole proof is the mutation table below; the same treatment
lane 2 gave its tests 2.6, 2.7, 2.8 and 2.10.

**The design's own arms were run first, and two of them were wrong** — ruling
`FR-T`, which quotes the original spec row. A scratch file
(`ZZScratchLane3Tests.swift`, deleted before `10dcc60`; `git status --short`
showed only the modified test file afterwards) measured the percentage matrix
across three parents and two spellings:

| spelling | 300pt `Row`, sibling's x | as the ROOT | in a 300pt `Column`, the mark's rect |
|---|---|---|---|
| `percent: 0.5` | **150** | **150** | 150 at x = 75 |
| `percent: 1.0` | 295 | 300 | 300 at x = 0 |
| `percent: 50` | 300, shrunk back, sibling squeezed to 0 | **15000** | 15000 at x = **−7350** |
| `percent: 100` | 300, likewise | **30000** | 30000 at x = **−14850** |
| `Pixels(150)`, the control | 150 | 150 | 150 at x = 75 |

`Length.percent` is a fraction (`resolveLength` is `f * parent`), the three
`percent:` modifiers forward it untouched, and `ModifierTests`' table — the
only caller — asserts the `Style` field rather than a layout. So the design's
arm 1 (`percent: 50` "reads 150") and arm 2 (the root "falls back to the
offered space", fixed by `SZ-A` and deleted from CLAUDE.md) are refuted, and
arm 3's "≈30000pt, mechanism not investigated" is 100 × 300 through EP-8's
cross-axis centring. The test asserts exact rects rather than the range the
design asked for.

**Test 3.2's numbers, re-measured rather than carried.** Node counts on a
`Row` holding one 20×20 mark: bare **2**; `.width`, `.height`, `.minWidth`,
`.maxWidth`, `.minHeight`, `.maxHeight` **2** each; `.frame(width:)` and
`.frame(minWidth:)` **3**. The automatic minimum, on the demo's shape (an 80pt
header above a `flexGrow(1)`/`flexBasis(0)` `Column` holding a 400pt mark, in a
300×200 frame) reproduced `N7`…`N9b` exactly: **120 / 400 / 400 / 400**.

**Mutations.** Each applied to a `cp` backup's file, the WHOLE suite run under
`swift test --build-system native --no-parallel`, the file restored and `git
status --short` checked empty. No other agent was live in this worktree. Every
run read `Test run with 1247 tests`.

| # | mutation | tests reddened |
|---|---|---|
| L1 | `width(percent:)` writes `.percent(percent / 100)` — **the candidate fix** | **2** (6 issues): 3.1 at five arms (`fractionInRow → 2.0`, both `Column` rects, the root rect, the row control) and `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`. This is the measured blast radius `FR-T` quotes |
| L2 | `resolveRootSize`'s `withoutMeasuring` resolves against no basis (`declared(dim)`, the pre-`SZ-A` spelling) | **2** (3 issues): 3.1's **root arm alone** — arms A and C stay green, so the arm discriminates — and the engine oracle `rootPercentageMatchesWebKit` |
| L3 | `minHeight(_:)` writes nothing | **2**: 3.2's opening `#require` (`(demoSpelling → 400.0) != (noMinimum → 400.0)`) and `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` |
| L4 | `frame(width:height:alignment:)` `_wrap`s twice | **as the lane recorded it: 8 tests, 18 issues**, 2.6 and 2.8 among them. **Re-taken by the lane's verifier (its M4, below) with an identical-style second `_wrap`: 7 tests, 13 issues, and 2.6 and 2.8 stay green** — an identical frame nested in an identical frame gives identical geometry, so only node-count, type-shape and identity tests see it: 3.2's frame arm (`(framed → 4) == (bare + 1 → 3)`), `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`, `chainedFramesRemainConcreteAndNestTheirLayoutNodes`, `legacyModifierChainsInferOneConcreteType`, `aGenericWrapOverAChainIsIdenticalToTheFlatChain`, `aModifierChainIsIdenticalToHandBuiltNestedBoxes`, `stateSurvivesFramesUnderALegacyModifierChain`. The lane's spelling of the mutant that reddened 2.6 and 2.8 was not recorded and could not be reproduced, so the verifier's set is the one to cite; the essential claim, that 3.2's frame arm reddens, holds either way |
| L5 | `width(_:)`/`height(_:)` routed through `frame(width:)`/`frame(height:)` — **`FR-F`'s refusal made executable** | **the package stops compiling**, which is the finding: a modifier returning `Self` cannot add a node, so the conversion must change the return type. `swift build --build-tests` halts in `MetalUIDemo` at **2** errors (`main.swift:266`'s `-> Box<Text>` helper, `:290`'s `typealias Chrome`); building `MetalUITests` alone, which skips the demo, reports **70** distinct error sites across six files — `AccessibilityTreeTests` 60, `AccessibilityEndToEndTests` 4, `ModifierTests` 2, `EnvironmentTests` 2, `ProposalNodeIDTests` 1, `AnimationTests` 1 |

**What has no mutation, said plainly.** 3.2's six-modifier arms cannot be
mutated while the package still compiles: "returns `Self`, therefore adds no
node" is enforced by the return type, and L5 is what that looks like when you
try. 3.2's two `.frame(minHeight: 0)` arms are pinned against a *future* fix
(making a layer's `minSize` reach into its child, plan task 6) and have no
mutation short of building it. Neither gap is hidden behind a count.

**Stale source comments corrected.** `Box.swift`'s `width(percent:)` claimed
the root "falls back to the offered space, so `width(percent: 50)` in an
800-wide window gives 800 where WebKit gives 400" and pointed at CLAUDE.md;
`SZ-A` fixed that and `resolveRootSize`'s own comment records that the CLAUDE.md
row was deleted. The design copied the claim into spec test 3.1's arm 2, which
is how a stale comment became a planned test. `Length.percent` had **no** doc
comment at all, which is the root of `FR-T`: nothing in the type said what the
unit was.

**Counts, on `a316916` after `swift package clean`.** `Test run with 1247 tests
in 1 suite passed after 33.455 seconds`, 0 `error:`, 0 `warning:`. Goldens 97,
`git diff --stat c4b5853 -- '*.json'` empty. Guards: per-file
`grep -c canTypecheck` sums to **64** outside `Typecheck.swift`, one the comment
in `UnitSafetyTests.swift`, so **63** — unmoved, as designed. Lane 3 adds no
guard and therefore mutated none red.

**Untouched by this lane, for the merge**: no shared file was edited.
`Box.swift` changed in comments only, in the `MARK: Size` block and on three
`Edges<Length>` overloads; `Units.swift` (`MetalUICore`) gained one doc comment
on an existing case. No declaration, signature or body moved, so the parallel
paint-modifier track's appends to `Box.swift` cannot conflict with anything but
comment text.

**Left for lane 4.** The whole-suite/goldens/guards re-take after a clean, the
demo and preview pixel comparison against `c4b5853`, and the
`IOConsoleLocked` check with real release-window captures. Lane 3 changed no
executable line in `Sources/`, so it cannot move a pixel; lane 1's kernel change
is still the thing that comparison is for.

#### Lane 3 — verifier round, 2026-09-16 (at `b513fa3`)

**Verdict `ok: true`**, quoted: `Test run with 1247 tests in 1 suite passed
after 44.839 seconds` (`swift test --build-system native --no-parallel` after
`swift build --build-system native --build-tests`; 0 `error:`, 0 `warning:` in
the test log, the only warning SwiftPM's own `--build-system native`
deprecation notice on stderr; only `regenerateAllGoldens` and
`aListsWorkIsTheSameFor100kRowsAsFor500` skipped; `FREEZE-ALLOC` strict half
not checked on this toolchain, as documented). Goldens 97, diff against
`c4b5853` empty. Guards: per-file `grep -c canTypecheck` sums to 64 outside
`Typecheck.swift`, one the `UnitSafetyTests.swift` comment, so **63**; lane 3
adds none (`FrameSizingTests.swift` has 0). The verifier confirmed by diff
that lane 3's `Sources/` change (`798b1fb..b513fa3 -- Sources`) is comment
lines and two blank lines only, so it cannot move a demo or preview pixel;
the display read `IOConsoleLocked false` and the real-window captures were
left to lane 4, as the spec assigns. Red-first: both tests are declared
characterizations, green on arrival by the lane's own account (`10dcc60` at
21:33 precedes the doc commits at 21:43 and 21:46; no implementation commit
exists), their proof the mutation table — consistent with lane 2's treatment
of its own characterizations. Worktree clean afterwards.

**Mutations, the verifier's**, each over the whole suite:

| # | mutation | tests reddened |
|---|---|---|
| M1 = the lane's L1 | `Box.swift` `width(percent:)` writes `.percent(percent / 100)` — the candidate fix | **2**: `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock` (5 issues) and `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` (1). Lane 3's L1 exactly |
| M2 = L2 | `FlexEngine.swift` `resolveRootSize`/`withoutMeasuring` resolves `declared(dim)` against no basis (the pre-`SZ-A` spelling) | **2**: 3.1 at **the root arm alone** (`FrameSizingTests.swift:698`; arms A and C stayed green) and `rootPercentageMatchesWebKit` (2 issues). L2 exactly |
| M3 = L3 | `minHeight(_:)` writes nothing | **2**: 3.2 at its opening `#require` (`demoSpelling == noMinimum`) and `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`. L3 exactly |
| M4 = L4 | `frame(width:height:alignment:)` `_wrap`s twice with the same `FrameSpec` style | **7** (13 issues): 3.2's frame arm (`framed == bare + 1`), `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`, `aGenericWrapOverAChainIsIdenticalToTheFlatChain`, `aModifierChainIsIdenticalToHandBuiltNestedBoxes` (5 issues), `chainedFramesRemainConcreteAndNestTheirLayoutNodes`, `legacyModifierChainsInferOneConcreteType` (3 issues), `stateSurvivesFramesUnderALegacyModifierChain`. **2.6 and 2.8 stayed green**, against the lane's 8 / 18 — the L4 row above is amended |
| M5 = L5, a compile result | `width(_:)` returns `ModifiedElement<LayerBase>` via `frame(width:)`; `swift build --build-system native --build-tests` | the build halts in `MetalUIDemo` at **2** errors in `main.swift` (matches the lane's "2 errors"; the 70-site `MetalUITests` figure was not re-taken) |
| M6, the verifier's own | `height(percent:)` writes `.percent(percent / 100)` | **2**: 3.1 at its `halfHigh` arm alone, and `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` |
| M7, an instrument | scratch `ZZVerifierRemInsetTests.swift`: an absolutely positioned `Mark` with `.inset(left: .length(.rems(Rems(2))))` against a 0px control; deleted afterwards | **none — it PASSED**, `VERIFIER-M7 inset left: control 0.0, 2rem 32.0`, which is the finding: `Length.rems` is publicly reachable through `inset(_ edges: Edges<Dimension>)` (`FlexEngine.swift`'s `placeAbsolute` resolves each inset with `rootFontSize`), a fourth entry point the `FR-Q` inventory and the new `padding(_ edges:)` comment said did not exist |

**Five minor issues, and where each went** (all applied 2026-09-16 in the
commit after `6c18389`, `957b068`, by the record writer):

| # | issue | disposition |
|---|---|---|
| 1 | the rem inventory is short by one entry point (`inset(_ edges:)`, M7) | **applied**: `Box.swift`'s `padding(_ edges:)`, `margin(_ edges:)` and `borderWidth(_ edges:)` comments say four; `inset(_ edges:)` gains the sentence with M7's numbers; `FR-Q` gains an addendum; this file records it here. `FR-Q`'s disposition (keep, out of this task) is unaffected |
| 2 | the decisions doc's header said "next unused is `FR-T`" and its latest status line was lane 2's | **overtaken before it was read**: lane 4's `7d5a3a7` bumped the header to `FR-W` and added a lane-4 status line; the record round added a further status line. Nothing more to do |
| 3 | `FR-H`'s body still asserts the three arms `FR-T` refutes, with no pointer | **applied**: a "Read `FR-T` first" paragraph at the top of `FR-H` |
| 4 | the L4 row overstates its reddened set (8 / 18 with 2.6 and 2.8; re-taken 7 / 13 without them) | **applied**: the row now carries both figures, names the verifier's set as the one to cite, and says the lane's mutant spelling was not recorded and could not be reproduced |
| 5 | three sentences in `Box.swift`'s `MARK: Size` comment were unprobed, unpinned or stale: the "handler … as it does in SwiftUI" clause has a probe for its background half only (`swiftui-modifier-order.swift` O1) and none for a gesture; the `Box(decoration:).frame(width: 36)` sentence is scratch L8 with no committed test; "685 of them" was already 706 on `HEAD` (686 at `c4b5853`) | **applied**: O1 cited for the background half; the handler half split into MetalUI's measured L4 and a "by reading, unprobed" tag for SwiftUI's gesture area; the decoration sentence tagged "scratch L8, UNPINNED"; the literal replaced by the grep (`git grep -oE '\.(width\|height)\(' -- Sources Tests \| wc -l`, 686 at `c4b5853`), re-checked today: 686 / 706 |

#### Lane 4 — verification, 2026-09-15

No source or test file changed; the lane's commits are documentation only.
Every step below was run in the worktree `feat/frame-sizing` at `b513fa3`,
after `swift package clean` (spec item 1, critic finding 14), with `swift build
--build-system native --build-tests` first so that the typecheck guards had a
`.build/<triple>/debug/Modules` to run against. No other agent was live in this
worktree; the parallel paint-modifier track's scratch files share the
scratchpad directory and were left alone (every file of this lane is prefixed
`l4-`).

**Suite, goldens, guards** (spec items 2–4):

| check | result |
|---|---|
| `swift test --build-system native --no-parallel` | `Test run with 1247 tests in 1 suite passed after 37.954 seconds`; `grep -c error:` **0**; `grep -c warning:` **1**, and it is SwiftPM's own `'--build-system native' has been deprecated` notice, not a compiler warning (CLAUDE.md records the same lone hit); both gated tests skipped (`regenerateAllGoldens`, `aListsWorkIsTheSameFor100kRowsAsFor500`) |
| goldens | `git diff --stat c4b5853 -- '*.json'` empty; `find Tests -name '*.json' \| wc -l` = **97** |
| guards | per-file `grep -c canTypecheck`: `PhaseSeparationTests` 19, `ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8, `ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6, `ElementGroupTrapTests` 5, `AXNodeTests` 3, `UnitSafetyTests` 3 (line 13 is the comment), `ModifiedElementCompileGuards` 2, **`FrameSizingCompileGuards` 2** — 64, less the comment, **63**; `Typecheck.swift`'s declaration excluded |
| the guards RAN, not skipped | the baseline log carries both fixtures' prints: `FR-J no-argument frame: succeeded=true deprecations=2` and `FR-S overload resolution: succeeded=true messages=[]` |

**The two new guards, each mutated red once in this worktree** (spec item 4).
Each patch was applied to a `cp` backup's file, the WHOLE suite run under
`swift test --build-system native --no-parallel`, the file restored from the
copy and `git status --short` checked empty:

| # | mutation | tests reddened |
|---|---|---|
| A | `ElementGroup`'s deprecated `frame()` deleted (`FrameLayer.swift`) | **1**: `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths` at `FrameSizingCompileGuards.swift:102` and `:104` — `succeeded=false deprecations=1`, `error: cannot convert value of type 'ModifiedElement<LegacyLeaf>' to specified type 'LegacyLeaf'`. The proposal declaration's deprecation still fires, so the count reads 1, not 0; `Test run with 1247 tests in 1 suite failed … with 2 issues` |
| B | `ProposalElementGroup`'s flexible overload's `idealWidth:` label renamed (`NativeModifiedContent.swift`) | **2**: `everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload` at `:171` (`cannot convert value of type 'ModifiedElement<ProposalLeaf>' to specified type 'ModifiedContent<ProposalLeaf>'`, twice — the flexible and the ideal spellings fell to the legacy overload) and `anIdealDimensionOnTheLegacyFrameTraps` at `FrameSizingTests.swift:268` (test 2.4's proposal control met `FR-D`'s trap). Exactly the pair `FR-S` predicted from lane 2's own run |

Both are the mutations `FR-J` and `FR-S` already record from lanes 1 and 2;
re-running them here is what a worktree owes, since a worktree whose `.build`
has never been built natively runs no guard at all and reads the same 1247.

**Pixels, by record §13's stand-in** (spec item 5). `git archive c4b5853` and
`git archive b513fa3` into `l4-base` and `l4-head`; in each, a generated
`Tests/MetalUITests/SIPixelStandIn.swift` holds that tree's `main.swift` up to
`runDemo()` (its `import MetalUI` dropped for the test file's `@testable` one,
every top-level `let`/`var` made `nonisolated(unsafe)`, and only `Increment`
and `Decrement` — the two names that collide with existing `MetalUITests`
declarations — prefixed `SI`, with their two `"Increment"`/`"Decrement"` text
literals restored so no rendered string changed) and a test that renders
through a real `Window` over `FakePlatformWindow` (1024×1024, scale 1),
`drawFrameIfNeeded()` once for a frame-0 image and three `setNeedsRedraw()` +
`simulateTick` pairs for a frame-3 one, writing `fakeSurface.readPixels()`.
Debug builds. Ten images per tree, compared byte-for-byte per pixel:

| comparison | differing pixels |
|---|---|
| control: base light vs base dark, frame 0 | 1 048 576 (all) |
| control: base default vs base modal | 1 030 498 |
| control: base default vs base animation look (settled, no transaction) | 210 027, bbox (16, 113, 966×895) |
| control: base preview light vs dark | 1 048 576 |
| base f0 vs base f3 | 0 (deterministic clock) |
| **base vs head, the eight non-preview images** (default light/dark × f0/f3, modal light/dark, animation light/dark) | **0, 0, 0, 0, 0, 0, 0, 0** |
| **base vs head, preview light and dark** | **0, 0** |

The controls match record §13's shapes to within the demo's own drift since
`f64e58a` (§13 read 1 030 499 and 210 043 with the same bbox).

**The preview's zero, investigated as spec item 5 requires — and it is the
fix landing invisibly, not the fix missing.** The spec expected `FR-M` to move
the preview "if its content is wider or taller than the window offers", and
at 1024×1024 it is not. So a second instrument, `siRectDump`, renders both
roots through a bare `@testable` `Frame` at the real window's proportions
(920×560, the demo's request; 828×503, the 828×531 the window actually opened
as under MC-J's method less a title bar assumed to be 28pt — a reading; and
1024×1024), scale 2, light
theme, and writes every `MUIRect` and `MUIGlyph`. Default: 518 rects, 15 711
glyphs at every size (§13's numbers); preview: 16 rects, 97 glyphs. **All six
dumps are identical between base and head.** At 920×560 the preview's inner
surface rect reads origin `(0, −34)`, size `1840×1188` device px — **594pt
tall in a 560pt window, centred, overflowing 17pt top and bottom**. So the
content IS taller than the offer, exactly the H16/H17 shape, and the pixels
still do not move. Two instruments on the head scratch tree's kernel
(`LayoutTree.swift`, `cp`-restored after each, the scratch copy only) say why:

| instrument | preview dump vs base | default dump vs base |
|---|---|---|
| I1: `framedSize`'s greedy line put back to the pre-`FR-M` rule, `base = proposal` | **0** differing lines | 0 |
| I2: `framedProposal` proposes `proposal − 10` to the child | **224** differing lines | 0 |

I2 shows the dump sees the preview's kernel frame and is blind to the legacy
default, as it should be; I1 shows the old and new rules produce the same
rects. The mechanism, ruling `FR-U`: the `.frame(maxWidth: ∞, maxHeight: ∞)`
is not the root — the outer `ZStack` is — and both the `ZStack` and the frame
align `.center`. Base answers 560 and centres the 594pt child inside it at
−17; head answers 594 (H16, pinned at the kernel by
`aFrameWithoutAMinimumNeverAnswersLessThanItsChild`), the `ZStack` centres
that at −17 and the child sits at 0 inside it. The same pixel both ways. The
frame's answer did change; nothing downstream of it can show that in this
demo, and the stand-in's zero is therefore a regression check on the preview
and no evidence about `FR-M` either way.

**Real-window captures: refused again, and the brief's check said the session
was open** (spec item 6, ruling `FR-V`). `ioreg -n Root -d1 -a | grep -A1
IOConsoleLocked` printed `<false/>`, so the captures were attempted:
`swift build -c release --product MetalUIDemo` in both scratch trees, the
pointer logged at (602.15, 674.36) and not moved, each demo launched alone
with no suite running (an AppKit test window could otherwise sit over it), no
input sent. Each window opened at (614, 259) 828×531 by
`CGWindowListCopyWindowInfo` — `MetalUI — Milestones 1 to 3` and `MetalUI —
Native Layout Preview`, from both builds — and every `screencapture -x
-R614,259,828,531` printed `could not create image from rect`. A full-screen
`screencapture -x` wrote a 4112×2658 PNG with **0 non-black pixels of
10 929 696**. `CGSessionCopyCurrentDictionary` read `CGSSessionScreenIsLocked =
1`, `CGDisplayIsAsleep(main) = 1`, `CGDisplayIsActive(main) = 0`,
`CGPreflightScreenCaptureAccess() = true`: the display was asleep and the
screen locked while `IOConsoleLocked` said otherwise. `MC-J` stays owed, with
the same standing as after §13, and the check to run first is the CGS one.

**Counts at the end of the lane** are the table's: 1247 / 0 / 1 (SwiftPM's)
/ 97 / 63. Nothing in `Sources/` or `Tests/` moved; `git status --short` is
empty after every mutation and instrument.

**Re-taken in full, 2026-09-16 04:02–04:08 PDT, at `7d5a3a7`** (first written as 04:02–04:20; the last artifact, `l4-px-inst-I2/rects-preview-920x560.txt`, is stamped 04:07:39 and the commit `6c18389` 04:08:40 — corrected by the lane's verifier) — the lane's
implementer report was lost with the session that wrote it, and a count is
stale the moment it is trusted rather than measured, so the whole table above
was re-run in this worktree rather than read back. `swift package clean`,
`swift build --build-system native --build-tests` (27 s), then:

| check | re-take | matches the table |
|---|---|---|
| suite | `Test run with 1247 tests in 1 suite passed after 36.731 seconds`; `error:` 0; `warning:` 1, SwiftPM's notice; both `FR-J`/`FR-S` fixture prints present, so the new guards ran | yes |
| goldens | diff against `c4b5853` empty; 97 | yes |
| guards | the same ten files, the same per-file counts, 64 − 1 = **63** | yes |
| mutation A (`ElementGroup.frame()` deleted, `FrameLayer.swift:197-198`) | `1247 … failed … with 2 issues`; **1** test, `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths` at `:102` and `:104`; `FR-J … succeeded=false deprecations=1` | yes |
| mutation B (`idealWidth:` label renamed on the proposal overload, `NativeModifiedContent.swift:296`) | `1247 … failed … with 2 issues`; **2** tests, `everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload` at `:171` and `anIdealDimensionOnTheLegacyFrameTraps` at `FrameSizingTests.swift:268` | yes |
| stand-in controls, fresh images | 1 048 576 / 1 030 498 / 210 027, bbox (16, 113, 966×895); preview light vs dark 1 048 576; f0 vs f3 0 | yes |
| base vs head, ten images | **0 ×10** | yes |
| fresh images vs the 2026-09-15 images, both trees | 0 in every pair checked (five per tree) — the stand-in is deterministic across runs, not only across frames | new |
| rect dumps, six per tree | 518 / 15 711 and 16 / 97 at every size; base vs head **0 lines ×6**; fresh vs 2026-09-15 0 ×12 | yes |
| I1 (`base = proposal`) / I2 (`framedProposal − 10`) on the scratch head kernel | I1 **0** lines on all six; I2 **224** on each of the three preview dumps, 0 on the three default dumps | yes |
| captures | `IOConsoleLocked` now reads **`true`**; `CGSSessionScreenIsLocked = 1` (locked at 1789543593), `CGDisplayIsAsleep = 1`, `CGDisplayIsActive = 0`, `CGPreflightScreenCaptureAccess = true`. Not attempted — `FR-V`'s check says no, and the flag that said yes last time now agrees with it | refused, as before |

The scratch trees were re-checked before use: `l4-base/Sources` is
byte-identical to `git archive c4b5853` and `l4-head/Sources` to this worktree
at `7d5a3a7` (`b513fa3..7d5a3a7` touches no `Sources/` or `Tests/` file). The
worktree read `git status --short` empty after each mutation and the scratch
kernel diffed clean against it after each instrument. Nothing in the table
moved, so no ruling changes; `FR-V` gains its corroborating re-read.

#### Lane 4 — verifier round, 2026-09-16 (at `6c18389`)

**Verdict `ok: true`**, quoted: `Test run with 1247 tests in 1 suite passed
after 39.530 seconds` (after `swift package clean` + `swift build
--build-system native --build-tests`; `error:` 0; `warning:` 1 = SwiftPM's own
`--build-system native` deprecation notice; exactly two tests skipped; both new
guards' fixture prints present — `FR-J no-argument frame: succeeded=true
deprecations=2`, `FR-S overload resolution: succeeded=true messages=[]` — so
they ran rather than skipped; guards 64 hits in 10 test files minus the
`UnitSafetyTests.swift:13` comment = **63**; goldens 97, diff against
`c4b5853` empty; `git status --short` empty at the end, HEAD `6c18389`).

**Mutations and instruments, the verifier's**, each over the whole suite or
the stand-in:

| # | mutation | result |
|---|---|---|
| A (lane 4 / `FR-J`) | the deprecated `ElementGroup.frame()` deleted, `FrameLayer.swift:197-198` | **1**: `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths` (`FrameSizingCompileGuards.swift:102`, `:104`; `succeeded=false deprecations=1`); `1247 … failed after 38.896 seconds with 2 issues` |
| B (lane 4 / `FR-S`) | the proposal flexible overload's `idealWidth:` label renamed, `NativeModifiedContent.swift:296` | **2**: `everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload` (`:171`, `cannot convert value of type 'ModifiedElement<ProposalLeaf>' to specified type 'ModifiedContent<ProposalLeaf>'` at the flexible and ideal spellings) and `anIdealDimensionOnTheLegacyFrameTraps` (`FrameSizingTests.swift:268`); `failed … with 2 issues` |
| L3 (lane 3 spot-check, never independently verified before this) | `minHeight(_:)` writes nothing (`Box.swift:697`) | **2**: 3.2 (`FrameSizingTests.swift:817`) and `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` (`ModifierTests.swift:305`); `failed … with 2 issues`, exactly lane 3's pair |
| L1 (lane 3 spot-check, `FR-T`'s candidate fix) | `width(percent:)` writes `.percent(percent / 100)` (`Box.swift:659`) | **2**: 3.1 at `:696`, `:698`, `:700`, `:705`, `:707` — five arms — and `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`; `failed … with 6 issues`, exactly the blast radius `FR-T` quotes |
| I1 (`FR-U`'s instrument, scratch head kernel only) | `framedSize`'s greedy line put back to the pre-`FR-M` rule `base = proposal` (`LayoutTree.swift:1105`); `siRectDump` at 920×560, 828×503, 1024×1024 vs base | **nothing** — 0 differing lines in all six dumps, which is the finding `FR-U` records (double centring; the child at −17pt either way); the head kernel restored and diffed identical to the worktree |
| I2 (I1's positive control) | `framedProposal` returns `proposal − 10` (`LayoutTree.swift:1067`) | 224 differing lines in each of the three preview dumps; 0 in the three default dumps — the instrument sees the preview's kernel frame and is blind to the legacy path, as recorded |
| the pixel stand-in, re-taken fresh in both scratch trees | `l4-base/Sources` byte-identical to `git archive c4b5853`; `l4-head/Sources` and `Tests` identical to the worktree bar the generated `SIPixelStandIn.swift`; ten 1024×1024 images per tree through a real `Window` over `FakePlatformWindow` | controls: light vs dark 1 048 576; default vs modal 1 030 498; default vs animation look 210 027, bbox (16, 113, 966×895); preview light vs dark 1 048 576; f0 vs f3 0. **Base vs head: 0 differing pixels in all ten**; the fresh images byte-identical to the 2026-09-15/16 `l4-px-*` images (20 / 20); rect dumps 518 rects / 15 711 glyphs (default) and 16 / 97 (preview) at all three sizes, 0 differing lines × 6; the preview's 920×560 inner surface rect confirmed at (0, −34) 1840×1188 device px = 594pt in a 560pt window |

**Two minor issues, and where each went** (both applied 2026-09-16 in the
commit after `6c18389`, `957b068`):

| # | issue | disposition |
|---|---|---|
| 1 | the re-take paragraph dated the run 04:02–04:20 PDT; the last artifact (`l4-px-inst-I2/rects-preview-920x560.txt`) is stamped 04:07:39 and `6c18389` is 04:08:40 | **applied**: the paragraph reads 04:02–04:08 and says why. Numbers unaffected |
| 2 | `FR-V` rules that the check runs "from a swiftc-compiled probe", but no such probe was saved; the working `l4-diag.swift` lived only in the scratchpad and the scratchpad's `l4-lockcheck.swift` variant does not compile (`CGSessionCopyCurrentDictionary()` returns `CFDictionary?`, so `.takeRetainedValue()` is an error) | **applied**: saved as `docs/probes/appkit-screen-lock-state.swift`, the `l4-diag.swift` shape (`as? [String: Any]`, `CGDisplayIsAsleep`, `CGDisplayIsActive`, `CGPreflightScreenCaptureAccess`), with the two lane-4 readings and a third taken when the file was saved (2026-09-16 04:20:39 PDT: still locked, still asleep, `IOConsoleLocked` `<true/>`) in its header, the `CFDictionary?` note, and no positive control — every reading so far is locked, and the header says the first unlocked one is the control it lacks. `FR-V` and this file cite it |

#### Lane 4 — second verifier round, 2026-09-16 (at `957b068`)

A second verification of lane 4, run after `957b068` had already set the
spec's Status to "verified `ok`" — so that Status line was written ahead of
this round. It is true now; the order is recorded here, not rewritten.

**Verdict `ok: true`**, quoted: `Test run with 1247 tests in 1 suite passed
after 39.025 seconds` (after `swift build --build-system native
--build-tests`, `swift test --build-system native --no-parallel`; `error:` 0
in the build and test logs; `warning:` 1, SwiftPM's own `--build-system native`
deprecation notice; both guard fixture prints present, `FR-J ... succeeded=true
deprecations=2` and `FR-S ... succeeded=true`, so the guards ran). Goldens 97,
diff against `c4b5853` empty. Guards 64 `canTypecheck` hits across ten files,
less the `UnitSafetyTests` comment, **63**. Pixel stand-in re-taken from
scratch trees: base `Sources` byte-identical to `git archive c4b5853`, head
`Sources` synced to `957b068` (`diff -rq` clean); **0 differing pixels in all
ten** BGRA images and **0 differing lines in all six rect dumps** (16 229
lines per default dump, 113 per preview dump). Controls that differ: light vs
dark f0, 1 048 576 pixels; the preview vs the default demo, 373 313. Red-first
order holds (`9bd130c` before `389c452`, `c5a02a0` before `44a79b5`).
`a316916` and lane 4's `7d5a3a7`, `6c18389`, `957b068` change only comments and
docs in `Sources`, checked by diffing non-comment lines.

**Mutations and instruments, this verifier's:**

| # | mutation | result |
|---|---|---|
| M1 (`FR-M`'s pin) | `LayoutTree.swift` `framedSize`: `base = min == nil ? Swift.max(proposal, child) : proposal` → `base = proposal`, full unfiltered suite | **2**: `aFrameWithoutAMinimumNeverAnswersLessThanItsChild` (`NativeLayoutTests.swift:394`, `h8.answer != h14.answer`) and `aFrameNeverAnswersANegativeSize` (`:435`, `h2.answer == 20`). **Not** `aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI`, which `FR-U` had cited — issue 2 below |
| I1 (`FR-U`) | the same revert on the scratch head kernel; `siRectDump` at 920×560, 828×503, 1024×1024 | **nothing**: 0 differing lines × 6, as `FR-U` predicts (the two centre alignments cancel). An instrument reading, not a test |
| I2 (I1's control) | `framedProposal` returns its value minus 10 | 224 differing lines in each preview dump at all 3 sizes; the default dumps stay 0 — the dump can see the preview's frame |
| I3 (the verifier's own) | `base = child` (the greedy branch answers the child) | **nothing**: 0 × 6. Consistent with `FR-U`: in the preview the child (594) exceeds the proposal (560), so `max(proposal, child)` is the child |
| A (`FR-J` guard) | delete the deprecated `ElementGroup.frame()`, `FrameLayer.swift:197-198`; filtered run | **1**: `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths` (`FrameSizingCompileGuards.swift:102` `succeeded`, `:104` `deprecations == 2`); fixture print `succeeded=false deprecations=1` |
| B (`FR-S` guard) | rename the proposal flexible `frame(minWidth:idealWidth:…)`'s external label to `idealWidthX`, `NativeModifiedContent.swift:296` | **2**: `everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload` (`:171`; `cannot convert ModifiedElement<ProposalLeaf> to ModifiedContent<ProposalLeaf>`) and `anIdealDimensionOnTheLegacyFrameTraps` (`FrameSizingTests.swift:268`, the exit test's success arm got SIGTRAP) |

Mutations A and B repeat the first round's A and B with the same result, taken
independently. M1 and I3 are new.

**Four minor issues, and where each went** (applied in the commit after
`957b068`, by the record writer):

| # | issue | disposition |
|---|---|---|
| 1 | the lane 4 implementer report stops at `6c18389`, but `957b068` (04:32 PDT) edits `Box.swift` (46 comment lines), adds the lock probe and sets the spec Status to verified before this round ran | **applied**: `957b068` is listed as lane 4's in "What landed" and in the spec's Status, which now says which round verified what and in which order |
| 2 | `FR-U` cites `aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI` as `FR-M`'s second pin; M1 leaves it green (it pins `FR-A`) | **applied**: `FR-U` now cites `aFrameNeverAnswersANegativeSize`, with a correction note |
| 3 | this file's L4 row said a handler before a frame sits on the content "the same in SwiftUI", against `Box.swift`'s "by reading, unprobed" | **applied**: the row and the hit-testing paragraph say unprobed and cite O1 for the background half only. No probe added |
| 4 | `FR-V`'s lock probe has no positive control | **not closable today**: a fourth reading at 09:07:08 PDT was locked and asleep (`CGSSessionScreenIsLocked = 1`, a new lock time 1789569027, `IOConsoleLocked` `<true/>`), added to the probe's header; `FR-V` gains an "unvalidated" paragraph naming the control owed |

### Open at the end of the critic round

- Two of `MC-Q` finding 7's four handed-over shapes are **not** covered by this
  design: a **nil axis** in a modifier-order chain, and a **stretching `Box`
  parent** (EP-8). The shrinking row is `FR-P`'s `minSize` pin (test 2.2) and
  the smaller frame is tests 2.5 and 2.8.
- ~~The `Column` percentage defect (M4, ≈30000pt)~~ — **closed by lane 3**, see
  `FR-T`. There is no `Column` defect; `width(percent:)` takes a fraction and
  30000 is 100 × 300. What replaced it as an open item is the unit itself,
  deferred to plan task 6.
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
- The release-window captures stay owed (`MC-J`, `EV-P`); lane 4 checked
  `IOConsoleLocked`, found it `false`, launched, and was refused anyway — the
  screen was locked and the display asleep by the CGS session dictionary, which
  is the check to run instead (`FR-V`). The check is saved as
  `docs/probes/appkit-screen-lock-state.swift`.

### What landed, in one place

Eighteen commits on `feat/frame-sizing` from `c4b5853`, in order; `Sources/`
moved in four of them and `Tests/` in five:

| commit | lane | what |
|---|---|---|
| `4796bbb` | design | spec, decisions doc (`FR-A`…`FR-K`), the 54-arm probe |
| `d70a4a5` | critic round | 15 of 16 findings applied, one refused with a measurement; `FR-L`…`FR-Q`; the 17-arm negative-sizes probe |
| `901917a` | 1, step 0 | `ModifiedElement.swift`'s trailing `frame(width:height:)` replaced in place by a forwarding declaration into the new `Sources/MetalUI/FrameLayer.swift` — the shared-file seam, no behaviour change |
| `9bd130c` | 1, red | 1.1–1.6 and 1.9 new, 1.7/1.8 re-fixtured, 1.10 the first guard in the new `FrameSizingCompileGuards.swift` |
| `389c452` | 1, green | `framedSize`/`framedProposal` (`LayoutTree.swift`): greedy at any maximum, `max(proposal, child)` when no minimum, declared bounds floored at 0, `proposal.isFinite` kept; the deprecated `frame()` on both protocols |
| `8a0fd9c` | 1, record | `FR-R`; eleven mutations |
| `c5a02a0` | 2, red | 2.1–2.10 in the new `FrameSizingTests.swift`; the second guard broadened |
| `44a79b5` | 2, green | `FrameSpec`'s six bounds and alignment, `style()`'s lowering table, the flexible overload with `FR-D`'s trap, the fixed overload amended in place to carry `alignment:` (`FR-S`), both hand-spelled `frameStyle` oracles given the `minSize` pin |
| `dda9c6f` | 2 | 2.7 and 2.9 strengthened after two mutations reddened nothing |
| `66e5498` | 2, record | `FR-S`; eighteen mutations |
| `316237b` | 2 | two source doc comments refreshed (`NativeModifiedContent.swift`, `EnvironmentScope.swift`) |
| `798b1fb` | 2, record | why the demo's pixels cannot move (a compile-time fact) |
| `10dcc60` | 3, tests | 3.1 and 3.2 appended to `FrameSizingTests.swift`; the fraction finding |
| `a316916` | 3, docs | `Box.swift`'s `MARK: Size` section and three `Edges<Length>` overloads; `flexBasis(percent:)` and `Length.percent` (`Units.swift`) — comments only |
| `b513fa3` | 3, record | `FR-T`; five mutations; two stale claims |
| `7d5a3a7` | 4, record | verification; `FR-U`, `FR-V` |
| `6c18389` | 4, record | the whole of lane 4 re-taken at `7d5a3a7`, every figure identical |
| `957b068` | 4, record | this file's summary sections; the lane 3 and lane 4 verifiers' seven minor issues applied (comments in `Box.swift`, `FR-H`/`FR-Q`/`FR-V`, the saved lock probe, three record corrections); the spec's Status |
| the commit after `957b068` | record | lane 4's second verifier round and its four minor issues (`FR-U`'s pin, `FR-V` unvalidated with a fourth reading, the L4 row, the spec's Status order) |

**Source files, `git diff --stat c4b5853..6c18389 -- Sources`:**

| file | lines | what changed |
|---|---|---|
| `Sources/MetalUI/FrameLayer.swift` | +199, new | `FrameSpec` (internal, `FR-C`) and `style()`, the one CSS lowering of a SwiftUI frame; the flexible legacy overload; the deprecated `ElementGroup.frame()` |
| `Sources/MetalUILayout/LayoutTree.swift` | 104 | `framedSize`, `framedProposal`, `newNativeFrame`'s doc comment — lane 1's kernel change and its comments |
| `Sources/MetalUI/NativeModifiedContent.swift` | 30 | the deprecated `ProposalElementGroup.frame()`; the fixed proposal frame's doc comment |
| `Sources/MetalUI/ModifiedElement.swift` | 22 | step 0's forwarding declaration, then `alignment:` added in place (`FR-S`); **its file header, line 4, still spells the legacy frame `.frame(width:height:)`** — left for integration on purpose (lane 2's stale-comment sweep) |
| `Sources/MetalUI/Box.swift` | 118 + this commit | comments only: the `MARK: Size` section, the eight sizing modifiers, four `Edges` overloads (`padding`, `margin`, `borderWidth`, `inset`), `flexBasis(percent:)` |
| `Sources/MetalUI/EnvironmentScope.swift` | 8 | a comment: "`.frame(width:height:)` may follow a scope" refreshed |
| `Sources/MetalUICore/Units.swift` | 11 | a doc comment on `Length.percent`, which had none |

No shared file beyond `ModifiedElement.swift` and `Box.swift` was touched, and
`Box.swift` in comments only; `Component.swift`, `Element.swift`,
`ElementGroup.swift`, `Frame.swift`, `Passes.swift` and `Handlers.swift` are
untouched (`git diff --stat c4b5853..HEAD -- Sources` lists none of them).

**Counts after this record's own commit**, which touches `Sources/` in
`Box.swift` comments only (re-taken rather than assumed, 2026-09-16 04:30 PDT,
`swift build --build-system native --build-tests` then `swift test
--build-system native --no-parallel`): `Test run with 1247 tests in 1 suite
passed after 41.538 seconds`; `error:` 0; `warning:` 2, both SwiftPM's own
`'--build-system native' has been deprecated` notice (build and test share one
log); `FR-J no-argument frame: succeeded=true deprecations=2` and `FR-S
overload resolution: succeeded=true messages=[]` printed, so both new guards
ran; only the two gated tests skipped; goldens 97, `git diff --stat c4b5853 --
'*.json'` empty; guards 64 hits across the ten files less the
`UnitSafetyTests.swift` comment = **63**.

### Tests and guards, per file

**1226 → 1247, +21, all additions** (`git diff c4b5853..HEAD -- Tests` adds 21
`@Test` lines and removes none):

| file | new tests | re-fixtured in place | guards |
|---|---|---|---|
| `Tests/MetalUILayoutTests/NativeLayoutTests.swift` (19 → 25) | 6: 1.1 `aFrameWithAMinimumAndAMaximumGrowsTowardItsProposal`, 1.2 `aFrameWithNoMaximumAnswersItsChildRatherThanItsProposal`, 1.3 `aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity`, 1.4 `anIdealDimensionIsUsedOnlyWhenThatAxisHasNoProposal`, 1.5 `aFrameWithoutAMinimumNeverAnswersLessThanItsChild`, 1.6 `aFrameNeverAnswersANegativeSize` | 1.7 `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum` (40×70 → 80×60), 1.8 `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes` (70×20 → 70×60, doc comment rewritten) | 0 |
| `Tests/MetalUITests/NativeLayoutIntegrationTests.swift` (41 → 42) | 1: 1.9 `aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI` | | 0 |
| `Tests/MetalUITests/FrameSizingCompileGuards.swift` (new) | 2, both guards | | **2**, both `typecheckFile` (whole file, Swift 6): 1.10 `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths` (lane 1), `everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload` (lane 2). Each prints its fixture result (`FR-J …`, `FR-S …`) so a log shows whether it ran |
| `Tests/MetalUITests/FrameSizingTests.swift` (new) | 12: 2.1 `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments`, 2.2 `aLegacyFixedFrameDoesNotShrinkAsAFlexItem`, 2.3 `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal`, 2.4 `anIdealDimensionOnTheLegacyFrameTraps` (exit tests), 2.5 `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`, 2.6 `aLegacyFrameProposesItsWidthToAMeasuredLeaf`, 2.7 `aLegacyFrameAroundAListStillBuildsEveryRow`, 2.8 `aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`, 2.9 `anInfiniteMaximumFillsOnlyWhenBothAxesAreInfinite`, 2.10 `aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare`, 3.1 `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock`, 3.2 `theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt` | | 0 |
| `Tests/MetalUITests/ModifiedElementTests.swift`, `ModifierCompositionProofTests.swift` | 0 | the two hand-spelled `frameStyle(width:height:)` oracles gained `minSize` — **drift obligations**, kept in step by hand (`FR-P`) | |

Guards **61 → 63**, per file at `6c18389`: `PhaseSeparationTests` 19,
`ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8,
`ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6,
`ElementGroupTrapTests` 5, `AXNodeTests` 3, `UnitSafetyTests` 2 (3 hits, line
13 a comment), `ModifiedElementCompileGuards` 2, **`FrameSizingCompileGuards`
2**. Each new guard was mutated red in this worktree at least three times
(lane 1's M10/M11 and lane 2's M18 on arrival; lane 4's A and B twice; the
lane 4 verifier's A and B). Goldens **97** at every commit, diff against
`c4b5853` empty; `Sources/MetalUILayout/LayoutTree.swift` changed and no
golden moved, which is expected — the change is inside `framedSize`, behind
`isNativeLayoutNode(root)`, and no fixture builds a native node (record §09).

### Probes

| probe | arms | what it settled | positive controls |
|---|---|---|---|
| `docs/probes/swiftui-frame-semantics.swift` | 54 (`A`…`F`) | the whole frame rule: child proposal, response, the nine alignments, chaining, measured leaves; that a finite `maxWidth` frame GROWS (`SA-N` item 1, closed) | every group opens with a control whose answer must differ; script and compiled forms diffed EMPTY (295 lines); its first pass crashed SwiftUI at D12 (`view origin is invalid: (nan, 190.0)`), recorded |
| `docs/probes/swiftui-frame-negative-sizes.swift` | 17 (`H`) | SwiftUI never answers a negative size and floors DECLARED bounds at 0 (`FR-L`); an absent minimum is not `minWidth: 0` (`FR-M`: H8 20 vs H14 10); `maxWidth: .infinity` over an oversized child answers the child (H16) — the shipped kernel's live bug | script and compiled forms diffed EMPTY (101 lines); the compiled form prints exactly two SwiftUI diagnostics (H6, H10) |
| `docs/probes/swift-frame-overload-resolution.swift` | 3 variants × 8 spellings | a probe of the COMPILER: the refined protocol wins every `frame` spelling; `frame()` on `ElementGroup` alone reinstates `SA-N` item 9 (`FR-J`); two fixed legacy overloads are silently ambiguous-free and exponentially slow (`FR-S`, measured on the real module: fails at threshold 16000 with two, 186 with one) | each `frame` body prints which declaration ran; variant C is the pre-lane-2 shape |
| `docs/probes/appkit-screen-lock-state.swift` | — | a probe of the MACHINE: `CGSSessionScreenIsLocked` + `CGDisplayIsAsleep` are the pre-capture check, `IOConsoleLocked` is not (`FR-V`) | **none yet** — four locked readings (the fourth 2026-09-16 09:07 PDT, after a re-lock); the first unlocked reading taken with a capture whose non-black count is above 0 is the control it lacks, so `FR-V`'s check is unvalidated; the full-screen non-black pixel count is the backstop |
| cited, not new: `docs/probes/swiftui-modifier-order.swift` arm O1 | | a `.background` before a `.frame` sits at the content's size in SwiftUI — the background half of `Box.swift`'s section comment | (task 3's) |

Seventy-one SwiftUI arms across the two frame probes; the rule they fix, in
one place, is the spec's "The rule, in one place" block.

### Red runs, in one place

| lane | red | green |
|---|---|---|
| 1 | `9bd130c`: `Test run with 1234 tests in 1 suite failed after 30.849 seconds with 11 issues` — 1.1, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10 red; 1.2 and 1.3 green on arrival (proved by M2 and M3) | `389c452`: `1234 … passed after 30.393 seconds` |
| 2 | red run 1, `c5a02a0` against the unchanged source: the test target does not compile, 13 errors (`extra argument 'alignment' in call` ×2, `argument passed to call that takes no arguments` ×10 — every flexible spelling — and the ideal arm); red run 2 against a scratch stub declaring the overloads with step 0's lowering: `1245 … failed after 34.371 seconds with 10 issues` — 2.1, 2.2, 2.3, 2.4, 2.5, 2.9 red, plus `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget` (`FR-S`); 2.6, 2.7, 2.8, 2.10 green on arrival as characterizations | `44a79b5`: `1245 … passed after 34.599 seconds` |
| 3 | none — both tests are characterizations, green at `10dcc60` (`1247 … passed after 32.741 seconds`); their proof is L1–L5 | `a316916` after `swift package clean`: `1247 … passed after 33.455 seconds` |
| 4 | no test | `b513fa3` after clean: `1247 … passed after 37.954 seconds`; `7d5a3a7` after clean: `36.731 seconds`; the verifier: `39.530 seconds` |

### Mutations that stayed green, and what has no mutation

Each is a coverage statement, named rather than hidden in a count:

- **Lane 1 M4**, `framedSize`'s first two branches swapped: **nothing** — they
  are mutually exclusive, so the order is documentation (`FR-R` item 3). The
  spec's claim that it reddens 1.4 is withdrawn.
- **Lane 1 M7b**, `framedSize`'s `hi` unfloored: **nothing** — `SA-J` traps on
  a negative maximum at registration, so the floor is an unreachable backstop
  (`FR-R` item 2). Tightening `SA-J` is task 7's.
- **Lane 2's first `alignSelf = .stretch` drop**: nothing in 1245 — a mark
  centred in a 20pt-tall layer at y = 90 and one centred in a 200pt-tall layer
  at y = 0 sit at the same y. Fixed by adding two `.topLeading` arms to 2.9
  (`dda9c6f`); M12 then reddens exactly those.
- **Lane 2 M10**, a fixed `size.height` of 40 on the frame layer: 2.6 and 2.9,
  **never 2.7**, twice (divergence 14: `List` windows against the scroller,
  not the layer). 2.7's only mutation is the broad M17 (the outermost layer's
  child list dropped, ~25 tests / 102 issues), and its doc comment says so.
- **Lane 3's 3.2, six `Self`-returning arms**: no mutation while the package
  compiles — "returns `Self`, therefore adds no node" is enforced by the return
  type, and L5/M5 is what an attempt looks like (a build halt).
- **Lane 3's 3.2, the two `.frame(minHeight: 0)` arms**: pinned against a
  *future* fix (a layer's `minSize` reaching its child, plan task 6); no
  mutation short of building it.
- **Lane 4 I1**, the greedy line put back to `base = proposal`: 0 differing
  dump lines by design — `FR-U`'s finding, with I2 (224 lines) as its control.
- **Lane 3's verifier M7**: an instrument that PASSED and thereby found the
  fourth rem entry point.

**Unpinned or unprobed, by reading:** `Box(decoration:).frame(width: 36)`
painting the decoration at the child's size (scratch L8; no committed test);
SwiftUI's gesture hit area for a handler declared before a `.frame` (the
background half is probed, O1); the nil axis in a modifier-order chain and a
stretching `Box` parent (EP-8), handed over by `MC-Q` finding 7 and not
covered; `FR-D`'s `flexBasis`-as-ideal idea; whether SwiftUI's preview-shaped
content overflows its window 17pt top and bottom as the kernel's now does
(`FR-U`); lane 1's M11 (the `ProposalElementGroup` `frame()` deleted) has no
re-run beyond the lane's own; and, on the legacy path, that `Style.padding` on
a `Text` behaves as it does on a custom leaf (CLAUDE.md already says so).

### Hazards this track introduced or exposed

1. **`ElementGroup` must keep exactly ONE fixed `frame` overload** (`FR-S`). A
   second one compiles, resolves without ambiguity, and makes a twelve-modifier
   chain fail `-solver-scope-threshold=16000` where one needs 186; the only
   test that says so is `MC-A`'s `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget`.
   A merge that re-introduces `frame(width:height:)` beside
   `frame(width:height:alignment:)` breaks it.
2. **Two hand-spelled `frameStyle` oracles are drift obligations.**
   `ModifiedElementTests.swift` and `ModifierCompositionProofTests.swift` each
   duplicate `FrameSpec.style()`'s fixed rows, and running each candidate
   lowering over the whole suite showed nothing moves when they diverge
   (1231/1231). Change the lowering and the oracles in one commit.
3. **`width(percent:)`, `height(percent:)` and `flexBasis(percent:)` take a
   FRACTION** (`FR-T`): `percent: 50` is 5000%, and in a `Row` flex-shrink
   hides it — the box reads exactly its parent's width, which looks like
   `width: 100%` working. Pinned wrong on purpose by 3.1; the unit is task 6's.
4. **`.frame(idealWidth:)`/`.frame(idealHeight:)` on a legacy element TRAP**
   at run time (`FR-D`, exit test 2.4). A port from the proposal path to the
   legacy one is a type change and then a crash, with a message naming the
   parameter.
5. **A single-axis `.frame(maxWidth: .infinity)` on the legacy path is inert**
   (`FR-O`): a node, an id level and a `$anim` entry that does not fill; only
   the both-axes spelling lowers to `flexGrow = 1` + `alignSelf = .stretch`.
   Owes CLAUDE.md a declared-but-inert row.
6. **Two more legacy divergences, pinned wrong on purpose**: a finite maximum
   clamps but never grows into the proposal (`FR-E`, 2.3: `.frame(maxWidth: 80)`
   over 20 reads 20, SwiftUI 80), and a child bigger than its frame is squeezed
   on the layer's main axis and overflows the cross axis, where SwiftUI
   overflows both (`FR-N`, 2.8: (0, 20) 60×160 against SwiftUI's 200×160 at
   (−70, −60)).
7. **The kernel's frame floors declared negative bounds at 0 and forwards a
   negative proposal when no minimum is declared** (`FR-L`, H2/H4); a negative
   fixed size or maximum traps first (`SA-J`) where SwiftUI diagnoses and
   floors — so `framedSize`'s `hi` floor is unreachable (`FR-R` item 2).
8. **An infinite proposal answers the child** (`FR-B`, 1.3) where SwiftUI
   answers infinity and then traps on placement. Reachable from
   `ProposalScrollView`'s scrolling axis.
9. **`FR-M` moved the preview's outermost frame answer by 34pt with no pixel
   change** (`FR-U`): the `ZStack` and the frame both centre. Any later demo
   edit that gives either a non-centred alignment, or a sibling that reads the
   frame's size, will show the change — and it will be the fix landing, not a
   regression. The preview's content overflows its 920×560 window 17pt top and
   bottom, centred; the preview's first human look is still owed and will see
   a clipped border.
10. **`IOConsoleLocked` is not the screen-lock check** (`FR-V`): it read
    `<false/>` on a locked, asleep display and `<true/>` on the same session
    later. Run `docs/probes/appkit-screen-lock-state.swift` first; the
    full-screen non-black count is the backstop.
11. **The typecheck guards skip in a worktree that has never been built
    natively** and the count reads the same; both new guards print their
    fixture result (`FR-J …`, `FR-S …`) so a log shows whether they ran.
12. **`Length.rems` is publicly reachable through four `Edges` modifiers**
    (`padding`, `margin`, `borderWidth`, `inset`) and resolves against a single
    per-frame `rootFontSize` (`FR-Q` and its addendum); there is no rem sizing
    modifier. The inventory was short by one until the lane 3 verifier's
    instrument found `inset`.
13. **`ModifiedElement.swift`'s header, line 4, still names the legacy frame
    `.frame(width:height:)`**; left for integration to avoid a hunk at the
    parallel track's append point.

### Deferred, each with an owner

| deferral | why | owner |
|---|---|---|
| deprecating `width`/`height`/`min*`/`max*` with `renamed:` hints, and moving them onto the frame representation | 706 `.width(`/`.height(` sites (686 at `c4b5853`) against a 0-`warning:` gate; a trial conversion fails to compile in the demo and five test files; `.minHeight(0)` cancels flex §4.5's automatic minimum on the element itself, which no frame layer can (`FR-G`, measured 120 / 400 / 400 / 400) | plan task 7; `FR-F` holds the recipe, `FR-I` the schedule |
| a greedy FINITE maximum on the legacy path | needs the parent's main axis, which a layer cannot see (M2, M4; `FR-E`) | task 6 |
| a SINGLE-axis infinite maximum filling | same reason; the both-axes case is delivered (`FR-O`, N14/N15) | task 6 |
| an oversized child overflowing both axes rather than being squeezed on one | one flex node cannot; the inner node is the caller's element (`FR-N`) | task 6 |
| `idealWidth`/`idealHeight` on the legacy path, possibly through `flexBasis` | unmeasured idea (`FR-D`) | task 7 |
| renaming `ProposalAlignment` to `Alignment` | collides with the parallel track; cosmetic until the legacy path is gone (`FR-K`) | task 7 |
| correcting `percent:`'s unit (divide by 100, or rename the parameter `fraction:`) | a silent behaviour change to public API with no oracle above CSS; blast radius measured at 2 tests (`FR-T`) | task 6 |
| tightening `SA-J` to reject a negative minimum at registration | `FR-L` matches SwiftUI's answers; changing what `SA-J` accepts is the kernel track's ruling | task 7 |
| `Component` distribution of `.frame`, and B-7's snap | `MC-L` assigns it | task 5 |
| the nil axis in a modifier-order chain and a stretching `Box` parent (EP-8) | `MC-Q` finding 7's two uncovered shapes | task 6 |
| the release-window captures of the default demo and the preview against `c4b5853` (`MC-J`'s method) | refused by a locked, asleep display on two attempts and one further read; the stand-in reads 0 × 10 | whoever next has an unlocked session — check with the saved probe first |
| the preview's first human look, now including the 17pt overflow (`FR-U`) | no look recorded | CLAUDE.md's human-verification table |
| a test that renders a `Box(decoration:)` inside a `.frame` | scratch L8 is unpinned | whoever next touches `FrameSpec.style()` |

### For the integrator

**Verdict: all four lanes verified `ok: true`** — lanes 1 and 2 in the
session cut off on 2026-09-15 (verdicts lost; the brief's "suite 1245 at lane
2's verification" is the only surviving figure; see "Lanes 1 and 2 — the
verifier tables, reconstructed"), lane 3 at `b513fa3` and lane 4 at `6c18389`
in the continuation, each with minor issues only, all applied in the commit
after `6c18389`; lane 4 verified a second time at `957b068`, `ok`, four minor
issues, applied in the commit after `957b068` except `FR-V`'s positive
control, which needs an unlocked session. This track adds no `Sources/` change after `44a79b5` beyond
comments. The release-window captures are still owed. Re-take every count
after merging with the paint-modifier track. The figures here are this
branch's alone: **1247 tests, 97 goldens, 63 guards, 0 `error:` / 0
`warning:`** (the lone `warning:` in a `--build-system native` log is SwiftPM's
own deprecation notice).

**`CLAUDE.md` (rules only; mirror each change in `AGENTS.md` with
`cp CLAUDE.md AGENTS.md`, then `cmp`):**

1. **Ruling table.** Add a row: `` | `FR-` | frame and sizing, plan task 4
   (`FR-A`…`FR-V`, next is `FR-W`) | lettered | ``. Add `FR-3` to the
   bare-typo sentence. Add to "Where things are": `` - frame and sizing (task
   4, `FR-`): `specs/2026-09-15-frame-sizing-design.md`,
   `2026-09-15-frame-sizing-decisions.md`, record §14; probes
   `docs/probes/swiftui-frame-semantics.swift` (54 arms),
   `…-frame-negative-sizes.swift` (17), `swift-frame-overload-resolution.swift`
   (the compiler), `appkit-screen-lock-state.swift` (the pre-capture check). ``
2. **Counts.** Change 1226 / 61 to this branch's **1247 / 63** (+21 tests:
   lane 1 +8 including one guard, lane 2 +11 including one guard, lane 3 +2;
   +2 guards), then re-take after the merge. Add `FrameSizingCompileGuards` 2
   to the per-file guard list and to the "count with per-file `grep -c
   canTypecheck` across …" sentence. Change "the other 21 — …" to "the other
   23 — `ProposalLayoutCompileGuards`' six, `ModifiedElementCompileGuards`'
   two, `ProposalNodeIDCompileGuards`' six, `FrameSizingCompileGuards`' two
   and seven of `EnvironmentCompileGuards`' — use `typecheckFile`". In "CI —
   what lapses silently", change "all 61 guards skip" to 63, and add: "the two
   `FrameSizingCompileGuards` fixtures print `FR-J no-argument frame:
   succeeded=…` and `FR-S overload resolution: succeeded=…`; grep a log for
   them to know they ran".
3. **Identity.** In the wrapper bullet, change "`.padding(_:)` and
   `.frame(width:height:)` on a legacy element" to "`.padding(_:)` and every
   legacy `.frame(...)` spelling". Nothing else in the bullet changes: a frame
   is still one layer, one node, one id level, and `.id()` still goes last.
4. **Containers.** Replace the sentence run from "`.frame(width:height:)` is a
   centring flex container … (flex-shrink down to min-content; by reading)."
   with:
   > "**The legacy frame has SwiftUI's whole parameter surface** —
   > `.frame(width:height:alignment:)` and
   > `.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`
   > on `ElementGroup` — and lowers to ONE `Style` in `FrameLayer.swift`'s
   > `FrameSpec.style()` (`FR-C`): a flex container on `.row`,
   > `justifyContent`/`alignItems` switched over the nine `ProposalAlignment`
   > cases (`aLegacyFramePlacesItsChildAtEachOfTheNineAlignments`, the
   > probe's B1–B8 exactly); a fixed axis pinned by `size` AND an axis-named
   > `minSize`, never `flexShrink = 0`, which is axis-blind (`FR-P`:
   > `aLegacyFixedFrameDoesNotShrinkAsAFlexItem`,
   > `aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare`); `minSize`/`maxSize`
   > for the bounds; `flexGrow = 1` + `alignSelf = .stretch` only when BOTH
   > maximums are infinite (`FR-O`). It sizes itself and does not impose that
   > size on its content: a content-sized child is centred (a 0×0 mark at
   > (30, 20) in a 60×40 frame, measured), a measured `Text` re-wraps at the
   > frame's width (`aLegacyFrameProposesItsWidthToAMeasuredLeaf`, SwiftUI's
   > F1 numbers), a fixed frame never shrinks as a flex item, chained frames
   > give the outer the size and let the inner overflow
   > (`chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`, E1/E2), and a frame
   > around a `List` builds the same rows. **Three legacy divergences are
   > pinned wrong on purpose:** a finite maximum clamps but never grows into
   > the proposal (`FR-E`: `.frame(maxWidth: 80)` over 20 reads 20, SwiftUI
   > 80); a child bigger than its frame is squeezed on the layer's main axis
   > and overflows the cross axis, where SwiftUI overflows both (`FR-N`); a
   > single-axis infinite maximum is inert (`FR-O`, inert table).
   > `idealWidth`/`idealHeight` **trap** on the legacy path (`FR-D`, exit
   > test). `.frame()` with no arguments is a deprecated no-op on both paths
   > (`FR-J`, guard). **`ElementGroup` must keep exactly ONE fixed `frame`
   > overload** (`FR-S`): a second compiles, and only `MC-A`'s solver-budget
   > guard says so (two overloads fail at threshold 16000; one needs 186). The
   > two hand-spelled `frameStyle` oracles in `ModifiedElementTests` and
   > `ModifierCompositionProofTests` are duplicates of the lowering that the
   > suite will not tell you have drifted; change them with it."
5. **Sizing modifiers — a new paragraph after Containers:**
   > "**`width`, `height`, `minWidth`, `maxWidth`, `minHeight`, `maxHeight`,
   > `width(percent:)` and `height(percent:)` write THIS element's own CSS box
   > and return `Self`; `.frame(...)` wraps** (`FR-F`, `FR-G`;
   > `theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt` counts
   > the nodes). They are not deprecated (`FR-I`): the 0-`warning:` gate makes
   > a `renamed:` hint a migration of every caller — 706 `.width(`/`.height(`
   > sites — and task 7 owns it (`FR-F` holds the recipe: convert, move
   > decoration/handler/hover/alignment modifiers after the frame, fix the
   > stored `Box<…>` types, re-take the demo pixels). **`.minHeight(0)` is the
   > only way to cancel flex §4.5's automatic minimum; a frame layer's
   > `minSize` cannot reach its child** (`FR-G`, the demo's own shape: 120 /
   > 400 / 400 / 400). **`width(percent:)`, `height(percent:)` and
   > `flexBasis(percent:)` take a FRACTION** — `percent: 0.5` is half,
   > `percent: 50` is 5000% and reads as the parent's width in a `Row` because
   > flex-shrink hides it (`FR-T`, pinned wrong on purpose by
   > `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock`; task
   > 6 owns the unit). There is no rem sizing modifier; `Length.rems` is
   > reachable through `padding(_ edges:)`, `margin(_ edges:)`,
   > `borderWidth(_ edges:)` and `inset(_ edges:)` and resolves against the
   > per-frame `rootFontSize` (`FR-Q`)."
6. **The proposal path.** In "Probed, and the kernel disagrees (`SA-N`)",
   delete the two task-4 items (the finite-`maxWidth` growth and the
   argument-less `.frame()`): both are fixed. Add, under "`ProposalLayout` is
   the public algorithm protocol" or as its own bullet:
   > "**The kernel's flexible frame is greedy** (`FR-A`, `FR-M`, seventy-one
   > probe arms): with a maximum and a finite proposal it answers the
   > proposal clamped into `[min, max]` when a minimum is declared, and
   > `max(proposal, child)` clamped when none is — the test is on the
   > minimum's PRESENCE, not its value (H8 answers 20, H14 with `minWidth: 0`
   > answers 10; `aFrameWithoutAMinimumNeverAnswersLessThanItsChild`). An
   > ideal is used only on an axis with no proposal. Declared negative bounds
   > floor at 0 and an absent minimum forwards a negative proposal (`FR-L`,
   > `aFrameNeverAnswersANegativeSize`); `framedSize`'s `hi` floor is
   > unreachable because `SA-J` traps first (`FR-R`). An infinite proposal
   > answers the child, where SwiftUI answers infinity and then traps on
   > placement (`FR-B`, divergence). A `VStack(alignment: .leading)` is the
   > one container in which a frame's answer is observable as an x
   > (`aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI`)."
   In "Vocabulary", change "`.frame(width:height:)` on a proposal value picks
   the proposal overload (`proposalLayoutFrameUsesTheTypedProposalWrapper`), on
   anything else `ModifiedElement`" to "every `.frame` spelling on a proposal
   value picks the proposal overload
   (`everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload`, seven
   inference rows; `swift-frame-overload-resolution.swift`), on anything else
   `ModifiedElement`; `.frame()` is deprecated on both".
7. **Probe-backed values.** Add a line at the top of the list: "The frame rule
   (child proposal, response, alignment, chaining, negative sizes) has two
   saved, re-runnable probes with positive controls,
   `docs/probes/swiftui-frame-semantics.swift` and
   `…-negative-sizes.swift`; the spec's "The rule, in one place" block is the
   71-arm summary."
8. **Practices.** Add:
   > "**A probe whose every arm agrees with two candidate rules has not
   > distinguished them.** The 54-arm frame probe fitted `base = proposal`
   > because every arm with a maximum proposed MORE than its child answered;
   > a second probe with the arm that separates the rules refuted it (`FR-M`).
   > Write the separating arm before ruling."
   And, under the mutation bullets: "**An instrument that passes can be the
   finding**: a scratch test written to check an inventory claim (`FR-Q`'s
   'three entry points') passed at x = 32 and found the fourth."
9. **Human verification table.** Add a row:
   > "frame and sizing (plan task 4): release-window capture of the default
   > demo AND the `METALUI_NATIVE_LAYOUT_PREVIEW=1` window against a build of
   > `c4b5853`, by `MC-J`'s method | **open**: attempted once with
   > `IOConsoleLocked` reading `false` and refused (`could not create image
   > from rect` ×4; a full-screen capture 0 non-black of 10 929 696); the
   > screen was locked and the display asleep by the CGS session dictionary
   > (`FR-V`). Stand-in: offscreen `FakePlatformWindow` pixels, ten images,
   > **0 differing in all ten**, re-taken twice; the preview zero is expected
   > and says nothing about `FR-M` (`FR-U`: the frame's answer moved 34pt and
   > two centred alignments cancel). Record §14"
   In the proposal-preview row add: "at 920×560 the preview's content is
   594pt tall, centred, overflowing 17pt top and bottom (`FR-U`); a look would
   report a clipped border". Change the standing check in the two capture
   rows from `ioreg … IOConsoleLocked` to "`docs/probes/appkit-screen-lock-state.swift`:
   `CGSSessionScreenIsLocked` 0 and `displayAsleep` false; `IOConsoleLocked`
   read `false` on a locked, asleep display; the CGS check itself has no positive control yet (`FR-V`)".
10. **Unprobed kernel behaviour** bullet "`.frame(maxWidth: .infinity)` in a
    stack does not expand (stack children get a nil main offer)" stays; it is
    a stack fact, not a frame one, and `FR-A` does not change it.

**Declared-but-inert table**, in `CLAUDE.md`:

- **Add a row:**
  > "a single-axis `.frame(maxWidth: .infinity)` or `.frame(maxHeight:
  > .infinity)` on a legacy element | a layer that costs a node, an id level
  > and a `$anim` entry and does not fill; only the both-axes spelling lowers
  > to `flexGrow = 1` + `alignSelf = .stretch` (`FR-O`, pinned by
  > `anInfiniteMaximumFillsOnlyWhenBothAxesAreInfinite`); task 6 owns the
  > single axis"
- **Add a row:**
  > "`ElementGroup.frame()` / `ProposalElementGroup.frame()` with no
  > arguments | deprecated no-ops returning `self` on both paths (`FR-J`,
  > guard `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths`); declared on BOTH
  > protocols on purpose — on `ElementGroup` alone the proposal call resolves
  > to the all-defaulted fixed overload and builds a layer silently"
- **Edit the leaf-padding row** if it still says `.frame` imposes nothing:
  unchanged in substance; a frame layer's `minSize` is the layer's own, not
  the leaf's.

**Divergence table.** Add, as `vs SwiftUI` unless stated, under the next
unused numbers (35 onward on this branch; the integrator assigns):

> "A legacy frame's finite maximum clamps but never grows into the proposal:
> `.frame(maxWidth: 80)` over a 20pt child reads 20, SwiftUI's D4 reads 80
> (`FR-E`). Pinned wrong on purpose by
> `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal`;
> task 6."

> "A child larger than its legacy frame is squeezed on the layer's main axis
> and overflows the cross axis — (0, 20) 60×160 in a 60×40 frame — where
> SwiftUI's A5 keeps 200×160 at (−70, −60) (`FR-N`). Pinned wrong on purpose
> by `aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`; task 6."

> "The kernel's frame at an infinite proposal answers its child; SwiftUI
> answers `inf × 20` and then traps on placement (`view origin is invalid`)
> (`FR-B`, D12). Pinned by
> `aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity`; deliberate."

> "A negative fixed size or maximum on the proposal path traps at
> registration (`SA-J`) where SwiftUI diagnoses and floors it at 0 (H6, H10);
> a negative minimum is floored at 0 as SwiftUI does (`FR-L`, `FR-R` item 2).
> Task 7."

> "`idealWidth`/`idealHeight` on a legacy frame trap; SwiftUI uses them on an
> unspecified axis (C1) (`FR-D`). Pinned by
> `anIdealDimensionOnTheLegacyFrameTraps`; task 7."

> "`unfixed defect` / vs CSS: `width(percent:)`, `height(percent:)` and
> `flexBasis(percent:)` take a fraction — `percent: 50` is 5000%, 15000pt in
> a 300pt parent, and in a `Row` flex-shrink hides it (`FR-T`). Pinned wrong
> on purpose by `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock`;
> task 6."

The `FR-O` single-axis case belongs in the inert table, not here.

**The plan's task 4 entry: do NOT tick it.** The task's own text has five
clauses and this track meets three:

- *"Specify and implement `.frame(width:height:alignment:)`, optional axes,
  min/ideal/max constraints, alignment within an offered proposal, and the
  ordering rules for chained frames"* — **done on both paths**: the kernel's
  flexible frame is greedy and probe-correct (`FR-A`, `FR-M`, `FR-L`), the
  legacy frame has the whole surface and a probe-backed lowering (`FR-C`,
  `FR-P`), the nine alignments and the ordering rules are pinned (2.1, 2.5);
  `ideal` on the legacy path is a trap, not an implementation (`FR-D`).
- *"Move `width`, `height`, min/max sizing and alignment-facing convenience
  APIs onto that representation"* — **refused with measurements** (`FR-F`,
  `FR-G`): 706 call sites, a compile failure in the demo and five test files,
  and `.minHeight(0)`'s automatic-minimum override that no layer can express.
  Owner: task 7, recipe written.
- *"deprecate APIs whose observable meaning cannot match SwiftUI"* — **one
  deprecation only** (`frame()`, `FR-J`); the rest refused by the 0-warning
  gate (`FR-I`).
- *"this task makes it the single semantic path"* — **not met**: two engines
  and two sizing vocabularies stay live; what is single is the parameter
  surface, the alignment vocabulary, the documented rule set and the one
  lowering function (`FR-C`).

Proposed text under the unchanged body, replacing the 2026-09-14 progress note:

> *Progress 2026-09-16 on `feat/frame-sizing` (`4796bbb..`this commit),
> still open.* Spec `specs/2026-09-15-frame-sizing-design.md`; rulings
> `FR-A`…`FR-V` in `../2026-09-15-frame-sizing-decisions.md`; four probes
> in `docs/probes/` (71 SwiftUI arms with positive controls); record §14.
> Four lanes, each red first where it had a behaviour change, each verified
> (lanes 1–2's verdicts lost with the 2026-09-15 session; lanes 3–4's
> quoted). Suite 1247 (1226 + 8 + 11 + 2), 97 goldens unmoved, 63 guards
> (61 + 2), 0 `error:` / 0 `warning:`.
> - **The kernel's flexible frame — fixed** (lane 1, `FR-A`, `FR-B`, `FR-L`,
>   `FR-M`): greedy at any maximum, `max(proposal, child)` with no minimum,
>   declared negatives floored, an infinite proposal answering the child.
>   `SA-N` items 1 and 9 closed.
> - **The legacy frame's SwiftUI surface — done** (lane 2, `FR-C`, `FR-D`,
>   `FR-K`, `FR-O`, `FR-P`, `FR-S`): optional axes, min/max, the nine
>   alignments, chained-frame ordering, one lowering in `FrameLayer.swift`;
>   `ideal` traps; `.frame()` deprecated on both paths. Three divergences
>   pinned wrong on purpose (`FR-E`, `FR-N`, `FR-O`).
> - **The sizing inventory — ruled, not converted** (lane 3, `FR-F`…`FR-I`,
>   `FR-Q`, `FR-T`): `width`/`height`/min/max/percent stay as CSS-box
>   modifiers, documented, with the node-count and automatic-minimum
>   differences pinned; `width(percent:)` found to take a fraction.
>
> **Not done, by ruling:** moving `width`/`height`/min/max onto the frame
> representation and deprecating them (`FR-F`, `FR-G`, `FR-I`; task 7, recipe
> in `FR-F`); a greedy finite maximum, a single-axis infinite maximum and an
> overflowing oversized child on the legacy path (task 6); `ideal` on the
> legacy path (task 7); the `percent:` unit (task 6). **Carried:** the
> release-window captures (`MC-J`), refused by a locked display; check with
> `docs/probes/appkit-screen-lock-state.swift`, not `IOConsoleLocked`
> (`FR-V`).

In the plan's "Current starting point": the bullet "A frame grows toward a
larger finite proposal only when `maxWidth` or `maxHeight` is `.infinity`
(`LayoutTree.swift:734-736`) … min 40 and max 80 at a proposal of 100 with a
20pt child give 40 … No SwiftUI probe for that case is recorded" is history
(`FR-A`; the test now pins 80 and the probe is saved). The bullet "Direct
`width`/`height` still mutate style. … it broke list virtualization, hit
testing, and text measurement" is corrected by `FR-F`: two of the three
claims are refuted by measurement (a frame layer's width reaches a measured
leaf and re-wraps it; a framed `List` paints the same rows) and the third is
SwiftUI's own behaviour; what blocks the conversion is the type-level blast
radius and the 0-warning gate. `Box.swift:593-599` still mutates `Style`, by
ruling.

**README:**

- In "What it looks like", after the legacy sample's `.width(Pixels(36))`,
  add one sentence: "`.width` writes the element's own CSS box; `.frame(width:)`
  — SwiftUI's spelling, with min/max and alignment — wraps it in a layer,
  and the two differ (record §14)."
- The suite-count sentence (1226 / 97 / 61 at `2456c69`): re-take after the
  merge; this branch alone reads 1247 / 97 / 63.
- "About a dozen of the integration tests cite a SwiftUI probe result in
  their own doc comments. `NativeLayoutTests` cites none. The probes survive
  only as prose, and most record no positive control." → "`NativeLayoutTests`
  and `FrameSizingTests` now cite two saved probes with positive controls
  (`docs/probes/swiftui-frame-semantics.swift`, `…-negative-sizes.swift`); the
  earlier probes survive only as prose."
- In "Twelve measured divergences …": re-count after the integrator assigns
  the six rows above.
- Under "SwiftUI alignment", add the frame-sizing spec
  (`specs/2026-09-15-frame-sizing-design.md`) and record §14
  (`docs/record/14-frame-and-sizing.md`).

**Other owned documents:**

- `docs/record/README.md`: add a row, `` | `14-frame-and-sizing.md` | plan
  task 4: the kernel's greedy flexible frame, the legacy frame's SwiftUI
  surface and its one lowering, the sizing inventory (`width`/`height` refused
  with measurements; `percent:` is a fraction); four lanes, the lost lane 1–2
  verdicts reconstructed, lane 3–4 verifier tables, the pixel stand-in and
  `FR-U`/`FR-V` | ``.
- The SA decisions doc, `SA-N` items 1 and 9: add status lines, "**Closed
  2026-09-15 by `FR-A`/`FR-M`** (`feat/frame-sizing`, `389c452`): the kernel
  is greedy at any maximum" and "**Closed by `FR-J`**: `frame()` is a
  deprecated no-op on both paths, guarded".
- Record §09: "Open, and material: does a SwiftUI flexible frame with a
  finite `maxWidth` grow" (§2) and the "Unprobed, and material" item "whether
  a finite `maxWidth` frame grows" are answered (it does; `FR-A`, and the
  probe is saved); the 2026-09-14 erratum's "Owners: plan tasks 4–7" loses
  its task-4 items.
- The MC decisions doc, `MC-L`: the rows "`width`/`height`/min/max as layers;
  legacy `.frame` min/ideal/max/alignment | task 4" and "legacy `.frame`
  against SwiftUI outside test 10's scope … | task 4" gain a status: the
  legacy `.frame` half is delivered (`FR-C`, `FR-P`), the shrinking-row shape
  is `FR-P`'s pin and the smaller frame is `FR-N`, the nil axis and the
  stretching `Box` parent stay open (task 6); the `width`/`height` half is
  refused and reassigned to task 7 (`FR-F`). "That is the number task 4 must
  re-measure before converting `width`/`height`" — not re-measured, because
  the conversion did not happen; it moves to task 7 with the conversion.
- `Sources/MetalUI/ModifiedElement.swift`, line 4: "`.padding(_:)` and
  `.frame(width:height:)`" → "`.padding(_:)` and `.frame(...)`" — the one
  word lane 2 left for the merge.
