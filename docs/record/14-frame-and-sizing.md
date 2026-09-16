## Frame and sizing (plan task 4) — `feat/frame-sizing`, from 2026-09-15

The record for plan task 4. Spec
`docs/superpowers/specs/2026-09-15-frame-sizing-design.md`; rulings `FR-A`…
`FR-Q` in `docs/superpowers/2026-09-15-frame-sizing-decisions.md` (next unused
`FR-R`); probes `docs/probes/swiftui-frame-semantics.swift` (54 arms) and
`docs/probes/swiftui-frame-negative-sizes.swift` (17 arms). The track runs in
its own worktree, `/Users/maxburger/Developer/MetalUI-frame-sizing`, beside the
paint-modifier track, and is merged by an integration step that owns
`CLAUDE.md`, the plan, `docs/record/README.md` and the other track's files.
**Nothing in this file has been copied into those yet.**

Two integration obligations this track creates for CLAUDE.md, which it may not
edit itself: a **declared-but-inert row** for a single-axis
`.frame(maxWidth: .infinity)` on the legacy path (`FR-O`), and the fact that
`.frame(width:height:)`'s lowering now pins its declared axis with an
axis-named `minSize` (`FR-P`).

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

(Not started. The design and the critic round are committed; no source file has
changed.)

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
  registration is the kernel track's ruling to change — task 7.
- N2 and N12 did not discriminate: the flex automatic minimum floors those
  shapes before any pin can matter. The cross-axis finding rests on N11 alone,
  which is why N11 gets its own test (2.10) rather than an arm inside 2.2.
- The release-window captures stay owed (`MC-J`, `EV-P`); lane 4 checks
  `IOConsoleLocked` and records the refusal if the session is locked.
