# Frame and sizing design

Plan task 4 of `docs/superpowers/plans/2026-09-12-swiftui-alignment.md`, on
branch `feat/frame-sizing` in the worktree
`/Users/maxburger/Developer/MetalUI-frame-sizing`, from `c4b5853`.

Rulings `FR-A`…`FR-K` live in
[`../2026-09-15-frame-sizing-decisions.md`](../2026-09-15-frame-sizing-decisions.md);
the record is `docs/record/14-frame-and-sizing.md`. The track runs beside a
second one (task 5's paint modifiers) in its own worktree, and an integration
step owns `CLAUDE.md`, the plan, `docs/record/README.md` and the other track's
files.

## The task, and what it turns out to be

The plan asks for one semantic frame path: "Specify and implement
`.frame(width:height:alignment:)`, optional axes, min/ideal/max constraints,
alignment within an offered proposal, and the ordering rules for chained
frames. Move `width`, `height`, min/max sizing and alignment-facing convenience
APIs onto that representation; deprecate APIs whose observable meaning cannot
match SwiftUI."

Measured this session, two of those five clauses turn out to be different jobs
from what the sentence implies, and both are settled with evidence rather than
judgement:

1. **The proposal path's flexible frame is WRONG, not missing** (`SA-N` item 1,
   carried to this task). SwiftUI's flexible frame is *greedy*: with a maximum
   it answers the proposal clamped into `[min, max]`, not the child clamped.
   The kernel answers the child. The fix is four lines and the probe covers
   seventeen arms.
2. **`width`/`height`/`minWidth`/`maxWidth`/… are not the same operation as a
   frame, and one live caller depends on the difference.** They write the
   element's own CSS box; a frame wraps. `main.swift:881`'s `.minHeight(0)`
   exists to cancel the flex automatic minimum (§4.5) *on that element*, which
   a wrapper layer cannot do and SwiftUI has no concept of. Converting them was
   also measured to be source-breaking at a scale no single milestone can
   verify: **685 call sites** (`.width(` 348 and `.height(` 338, one of
   each being the percentage overload, over 378 distinct lines), and a trial
   conversion in this worktree failed to compile in the demo and five test
   files. `FR-F`…`FR-I` record the refusal, the evidence, and the migration
   recipe the legacy engine's removal (task 7) will use.

So this task delivers **one frame semantics, shared by both paths** — one
alignment vocabulary, one parameter surface, one documented rule set, one
lowering — and re-documents the CSS box modifiers as engine-facing, with their
removal named and owned.

## Evidence

Everything below is from this session; nothing is inferred from a name or from
documentation.

| run | what it settled | where |
|---|---|---|
| `docs/probes/swiftui-frame-semantics.swift`, 54 arms, run as a script and compiled — `diff` of the two forms is EMPTY (295 lines, exit 0 both ways) | SwiftUI's whole frame rule: child proposal, response, alignment, chaining, measured leaves | the probe's header, `FR-A`…`FR-E` |
| scratch `ZZScratchFrameTests.swift` (L1–L14, M1–M4), run with `--filter`, deleted before commit | what the legacy CSS path already does, arm by arm against the probe | `FR-C`…`FR-H`, record §14 |
| trial conversion of `StyledElement.width/height` to `frame(width:)`, built with `--build-system native` | the conversion's blast radius: the demo and 5 test files fail to compile; `ModifierTests`'s modifier table asserts `Self`-returning semantics | `FR-F` |
| `grep -rno` call-site counts | 348 `.width(` + 338 `.height(` (one of each is the percentage overload), on 378 lines; 11 live `min*`/`max*` (10 in `Tests/`, one in `Sources/` — the other four `Sources/` matches are inside comments) | `FR-F`, `FR-G` |
| baseline suite at `c4b5853`, `swift test --build-system native --no-parallel` | `Test run with 1226 tests in 1 suite passed`, 0 `error:`, 0 `warning:`; 97 goldens; 61 guards | "Expected counts" |

**The probe's rule, in one place** (arm names are the probe's):

```
childProposal(axis) = fixed ?? clamp(parentProposal ?? ideal, min, max)   // nil if both nil
response(axis)      = fixed ?? clamp(base, min, max)
  base = parentProposal   when a maximum is given and the proposal is concrete (D control, D1, D2, D4, D5, D10, D13)
       = ideal            when the proposal is nil                        (C1, C4)
       = child's answer   otherwise                                       (C control, D6, D7, D8, D9, D14, D15)
```

A child bigger than the frame keeps its size and overflows (A5, B9). A fixed
frame never shrinks (there is no shrinking in SwiftUI). Chained frames: the
outer size wins, the inner keeps its own and overflows (E1 50/leaf at 15, E2
100/leaf at 40).

## Scope

**In.** The kernel's flexible-frame response (lane 1); the legacy frame's full
SwiftUI surface, alignment included, with a probe-backed lowering table and
each divergence pinned (lane 2); the sizing inventory's rulings, the percentage
divergence and its test, and the documentation those rulings make necessary
(lane 3); verification (lane 4).

**Out, with the reason and the owner:**

- **Converting or deprecating `width`/`height`/`min*`/`max*`** — `FR-F`,
  `FR-G`, `FR-I`. 685 call sites against a 0-warning gate; owned by task 7,
  recipe written.
- **Containers' alignment APIs** (`justifyContent`, `alignItems`, `alignSelf`,
  `alignContent`) — plan task 6 owns the container algorithms. The frame's own
  alignment is a parameter here, and that is the "alignment-facing" surface
  this task can finish.
- **Greedy maximums on the legacy path** — `FR-E`. Measured impossible to
  express per-axis without knowing the parent's main axis (M2, M4); pinned
  wrong on purpose.
- **`idealWidth`/`idealHeight` on the legacy path** — `FR-D`. No CSS
  counterpart; traps, exit-test pinned. The `flexBasis` idea is recorded as a
  deferral, unmeasured.
- **`Component` distribution of a frame, and paint-only layers** — plan task 5
  (`MC-L`).
- **`fixedSize`, `layoutPriority`, `aspectRatio` on the legacy path** — task 7.

## Lane 1 — the kernel's flexible frame

### Rulings

`FR-A` (the response rule), `FR-B` (an infinite proposal), `FR-J` (the
deprecated no-argument `frame()`).

### Source change

`Sources/MetalUILayout/LayoutTree.swift`, `framedSize` only — the child
proposal (`framedProposal`) is already exactly the probe's rule and does not
move:

```swift
private func framedSize(_ child: Double, proposal: Double?, fixed: Double?, ideal: Double?,
                        min: Double?, max: Double?) -> Double {
    if let fixed { return fixed }
    let base: Double
    if max != nil, let proposal, proposal.isFinite {
        base = proposal                      // greedy: FR-A, probe D control/D1/D2/D4/D5/D10/D13
    } else if proposal == nil, let ideal {
        base = ideal                         // probe C1, C4
    } else {
        base = child                         // probe C control, D6-D9, D14, D15
    }
    return Swift.max(min ?? -.infinity, Swift.min(base, max ?? .infinity))
}
```

Three things about it that are deliberate and must not be "simplified":

- **`max != nil` is the greedy gate, not `max == .infinity`.** The old code
  grew only at an infinite maximum; the probe grows at any maximum (D4 = 80
  with a *finite* 80). Making it unconditional instead — greedy whenever the
  proposal is concrete — breaks `minWidth`-alone (D7 answers 40 at a 100pt
  proposal, not 100).
- **`proposal.isFinite` keeps `FR-B`'s divergence.** At an infinite proposal
  SwiftUI answers `inf` (D12) and an earlier harness crashed inside SwiftUI's
  placement on the NaN origin that follows. MetalUI answers the child instead.
- **`min ?? -.infinity`, where the old code wrote `min ?? 0`.** A negative
  minimum is accepted by `SA-J` and must not floor a base at 0; the two spell
  the same answer for every non-negative base, and the probe has no negative
  size.

Also in lane 1: `newNativeFrame`'s doc comment (the "Frame response" bullet
list) is rewritten to the rule above, and the deprecated no-argument overload
(`FR-J`, SwiftUI's own spelling — `'frame()' is deprecated: Please pass one or
more parameters.`) is added to **both** `ProposalElementGroup` and
`ElementGroup`:

```swift
@available(*, deprecated, message: "Please pass one or more parameters.")
public func frame() -> Self { self }
```

It returns the receiver unchanged, as SwiftUI's does, so a no-argument call
contributes no node. Nothing in `Sources/` or `Tests/` calls it, so it costs no
warning.

### Files

| file | change |
|---|---|
| `Sources/MetalUILayout/LayoutTree.swift` | `framedSize`; `newNativeFrame`'s doc |
| `Sources/MetalUI/NativeModifiedContent.swift` | the deprecated `frame()` on `ProposalElementGroup` |
| `Sources/MetalUI/FrameLayer.swift` (new, lane 2) | the deprecated `frame()` on `ElementGroup` |
| `Tests/MetalUILayoutTests/NativeLayoutTests.swift` | tests 1.1–1.4 below; test 1.5 edits an existing test |
| `Tests/MetalUITests/NativeLayoutIntegrationTests.swift` | test 1.6 |
| `Tests/MetalUITests/FrameSizingTests.swift` (new, lane 2's file) | test 1.7, which needs both paths' element API |

### Tests

Each row: what it pins, its state before the change, the mutation that must
redden it after. "Green on arrival" marks a characterization; its proof is the
mutation.

| # | test | pins | before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aFrameWithAMaximumGrowsTowardItsProposalAsSwiftUIDoes` | Six arms over one `LayoutTree`, each a 20×20 leaf under `newNativeFrame`, read through `measureNativeLayout`: D control (min 40/max 80 at 100) → **80**; D1 (at 60) → 60; D2 (at 30) → 40; D4 (max 80 alone at 100) → 80; D5 (max 80 at 30) → 30; D13 (max 80, a 200pt child, at 100) → 80. Each arm also `#expect`s the child's proposal, so a change that fixes the answer by proposing differently is visible | **red**, derived from today's `framedSize` arm by arm and to be re-measured on arrival: D control 40, D1 40, D4 20, D5 20 are wrong; D2 (40) and D13 (80) are already right and are this test's internal controls | restore `max == .infinity` as the greedy gate (reddens D control, D1, D4, D5; D2 and D13 stay green); make the greedy branch unconditional (reddens 1.2, not this) |
| 1.2 | `aFrameWithNoMaximumAnswersItsChildRatherThanItsProposal` | D7 (min 40 alone at 100) → 40; D8 (at 30) → 40; D9 (at nil) → 40; D15 (min 400 at 100) → 400; C control (ideal 80 at a concrete 300) → 20 | green on arrival | make the greedy branch unconditional (`if let proposal, proposal.isFinite`) — D7, D15 and C control redden |
| 1.3 | `aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` (`FR-B`, **pinned against SwiftUI on purpose**: SwiftUI's D12 answers `inf`) | `maxWidth: .infinity` at `ProposedSize(width: .infinity, …)` answers the child's 20, and the stored rect is finite | green on arrival | drop `proposal.isFinite` from the greedy gate — the answer becomes `inf` |
| 1.4 | `anIdealDimensionIsUsedOnlyWhenThatAxisHasNoProposal` | C1 (ideal 80 at nil) → 80 and the child is proposed 80; C control (ideal 80 at 300) → 20 and the child is proposed 300; C3 (ideal 80 at nil over a 200pt child) → 80; C4 (min 40/ideal 80/max 120 at nil) → 80; C5 (the same at 300) → 120 | C1/C3/C4 green; **C5 red**: today's `framedSize` falls through to the child clamp and reads **40**, not the clamped proposal 120 | swap the first two branches of `framedSize` (C1 and C4 then answer the child rather than the ideal); drop the ideal branch entirely (C1, C3, C4 redden) |
| 1.5 | `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum` (existing, re-fixtured) | Same fixture; the measurement becomes **80×60** (width: base = proposal 100 clamped to 80; height: base = proposal 60, inside [30, 70]). The child's stored rect `(15, −1, 20, 90)` does **not** move — placement uses the rect the caller passed, not the measurement | **red after lane 1's source change** unless re-fixtured; it pins 40×70 today, which is `SA-N` item 1's wrong-on-purpose pin | as 1.1 |
| 1.6 | `aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI` | The same finding one level up, through `ProposalElementGroup.frame(minWidth:maxWidth:)` inside a window-sized root: a 20pt proposal leaf under `.frame(minWidth: 40, maxWidth: 80)` in a 200-wide root measures 80 and centres the leaf at x = 30 | **red**, measured: 40 and x = 10 | as 1.1 |
| 1.7 | `aFrameWithNoArgumentsIsTheDeprecatedNoOpOnBothPaths` (`FR-J`) | `String(describing: type(of:))` of `leaf.frame()` contains neither `ModifiedContent` nor `ModifiedElement` on either path, and `tree.nodeCount` after rendering it equals the unframed tree's | red: does not compile / resolves to the flexible overload before the overload exists | delete either no-argument overload — the type string gains its wrapper and the node count grows |

### Expected counts

1226 → **1233** tests (seven added, 1.5 edited in place). Guards 61, unchanged.
Goldens 97, unmoved — lane 1 touches no CSS path.

## Lane 2 — the legacy frame's SwiftUI surface

### Rulings

`FR-C` (the lowering table), `FR-D` (ideal traps), `FR-E` (no greedy maximum),
`FR-K` (one alignment type).

### Public API

A new file, `Sources/MetalUI/FrameLayer.swift`, so that the shared
`ModifiedElement.swift` takes exactly one edit — the deletion of its
fourteen-line `frame(width:height:)` extension, whose replacement below is
source-compatible with it.

```swift
/// SwiftUI's frame as one value: what `.frame(...)` asks for, before the CSS
/// lowering that `style` performs.
public struct FrameSpec: Sendable, Hashable {
    // All members internal; only MetalUI builds one (ruling FR-C).
    var width: Pixels?, height: Pixels?
    var minWidth: Pixels?, maxWidth: Pixels?
    var minHeight: Pixels?, maxHeight: Pixels?
    var alignment: ProposalAlignment

    /// The one place the CSS approximation lives (ruling FR-C's table).
    func style() -> Style
}

extension ElementGroup {
    /// SwiftUI's `frame(width:height:alignment:)`.
    public func frame(width: Pixels? = nil, height: Pixels? = nil,
                      alignment: ProposalAlignment = .center) -> ModifiedElement<LayerBase>

    /// SwiftUI's flexible frame. `idealWidth`/`idealHeight` TRAP on this path
    /// (ruling FR-D): the CSS engine has no unspecified proposal to answer.
    public func frame(minWidth: Pixels? = nil, idealWidth: Pixels? = nil, maxWidth: Pixels? = nil,
                      minHeight: Pixels? = nil, idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
                      alignment: ProposalAlignment = .center) -> ModifiedElement<LayerBase>

    @available(*, deprecated, message: "Please pass one or more parameters.")
    public func frame() -> Self { self }
}
```

Both overloads keep the proposal path's parameter names, order and defaults, so
one call site ports between paths by changing nothing but the element type.
`ProposalElementGroup`'s overloads still win on a proposal element, because a
refined protocol's extension is more specific (record §09, "The proposal
`.frame` overload").

**The overload-resolution risk, to be cleared before anything else in lane 2.**
Until now the two paths' `frame(width:height:…)` had *different* signatures —
the legacy one had no `alignment:` — so a call on a proposal element could be
resolved by its argument list alone. After this change the two are
**identical**, and the only thing choosing between them is that
`ProposalElementGroup`'s extension is more specialized. That is the documented
rule and record §09 already relies on it, but it is unmeasured for identical
signatures. **Lane 2's first step is a throwaway skeleton** — two protocols,
one refining the other, one type conforming to both, identical `frame`
overloads in each extension — compiled with `-swift-version 6`. If it is
ambiguous, either the legacy flexible overload takes an equivalent but
distinguishable shape or the proposal overloads are restated on the concrete
wrapper types, and this spec is amended before a test is written. The same
question applies to `frame()` (`FR-J`), added to both protocols. Once cleared,
`builderNativeFrameExposesTheSharedFlexibleSizingSurface` and
`aFixedAndAFlexibleFrameDimensionCannotBeCombined` are the standing guards, and
lane 2 adds one typecheck fixture to `ModifiedElementCompileGuards.swift`
pinning that a proposal element's `.frame(width:)` still infers
`ModifiedContent`, not `ModifiedElement` (a guard, so it must be mutated red
once in this worktree after `swift build --build-system native`).

`ProposalAlignment` is reused rather than duplicated (`FR-K`). Renaming it to
`Alignment` is a task-7 deferral, deliberately not taken here: a second
nine-case enum is exactly the kind of near-duplicate this milestone exists to
remove, and a rename would collide with the parallel track.

### The lowering (`FR-C`), row by row with its evidence

`FrameSpec.style()` builds one `Style`, in a flex row layer, exactly as the
deleted `FrameModifier.init` did plus four changes:

| what the caller asked for | `Style` | evidence |
|---|---|---|
| any frame | `flexDirection` stays `.row`; `justifyContent` ← `alignment.horizontalFactor` (0 → `.flexStart`, 0.5 → `.center`, 1 → `.flexEnd`), `alignItems` ← `verticalFactor` | scratch L6: all nine combinations place a 20×20 child at the probe's B1–B8 offsets exactly |
| `width` / `height` | `size.width` / `size.height` | unchanged from today |
| **a fixed axis is given** | **`flexShrink = 0`, `flexGrow = 0`** | scratch L9: two `.frame(width: 200)` layers in a 300pt `Row` are 150 each today; L14: with `flexShrink 0` they are 200 each, which is SwiftUI (a fixed frame has no shrink concept) |
| `minWidth` / `minHeight` | `minSize` | scratch L10: `minWidth 40` over a 20pt child reads 40, agreeing with probe D7/D8/D9 |
| `maxWidth` / `maxHeight`, finite | `maxSize` — **a clamp, never greedy** | scratch L10 vs probe D4: MetalUI 20, SwiftUI 80. `FR-E`, pinned wrong on purpose |
| `maxWidth` / `maxHeight` = `.infinity` | left `.auto` (an infinite cap is no cap) | probe D11: at a nil proposal SwiftUI answers the child too |
| `idealWidth` / `idealHeight` | **precondition failure** | `FR-D`; no CSS spelling, and an accepted-and-ignored parameter is the declared-but-inert shape CLAUDE.md exists to keep out |

### Files

| file | change |
|---|---|
| `Sources/MetalUI/FrameLayer.swift` | new: `FrameSpec`, `style()`, three overloads |
| `Sources/MetalUI/ModifiedElement.swift` | delete the `extension ElementGroup { frame(width:height:) }` at the end (14 lines). **Nothing else in this file moves** — the parallel track appends here |
| `Sources/MetalUI/Box.swift` | doc comments only, in the `MARK: Size` section (`FR-F`, `FR-G`, `FR-H`) |
| `Tests/MetalUITests/FrameSizingTests.swift` | new; tests 2.1–2.7 |
| `Tests/MetalUITests/ModifierCompositionProofTests.swift` | test 4's hand-built oracle gains `flexShrink = 0` on its frame `Box` (see below) |

**The oracle obligation.** `aModifierChainIsIdenticalToHandBuiltNestedBoxes`
(`MC-B`) compares a chain against hand-built `Box`es whose styles are spelled
out; its frame `Box` must gain `flexShrink = 0` in the same change, or the test
reddens for the right reason in the wrong place. `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`
(`MC-L`) must stay green untouched — its parents are `.flexStart` and its
frames are no smaller than their content, so no arm shrinks — and lane 2 must
say so after running it, not before.

### Tests

| # | test | pins | before | mutation that must redden it |
|---|---|---|---|---|
| 2.1 | `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments` | Nine arms, a 20×20 probe leaf in `.frame(width: 60, height: 40, alignment:)`, rendered through `Frame`: origins `(0,0) (20,0) (40,0) (0,10) (20,10) (40,10) (0,20) (20,20) (40,20)` — the probe's B1–B8 plus `.center`. `try #require` that `.topLeading` ≠ `.center` before the nine comparisons (shape 15) | does not compile: the parameter does not exist. Today's fixed `.center` behaviour is the `.center` arm, green | drop `justifyContent` from `style()` (six arms redden); drop `alignItems` (six redden); swap the two factors (four redden) |
| 2.2 | `aLegacyFixedFrameDoesNotShrinkAsAFlexItem` | `Row { probe.frame(width: 200, height: 20); probe.frame(width: 200, height: 20) }` in a 300×200 frame: the two layers sit at x = 0 and x = 200, each 200 wide (SwiftUI never shrinks a fixed frame). A `try #require` that the row is narrower than their sum, so the arm is actually over-constrained | **red**, measured: the probes sit at 75 and 225 — the layers shrank to 150 | drop `flexShrink = 0` from `style()` |
| 2.3 | `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal` (`FR-E`, **half pinned wrong on purpose**) | In a 300pt `Row`, reading each layer's width from a 5pt sibling's x: `.frame(minWidth: 40)` over a 20pt child → **40** (agrees with probe D7); `.frame(maxWidth: 80)` over a 200pt child → **80** (agrees with D14); `.frame(maxWidth: 80)` over a 20pt child → **20**, where SwiftUI's D4 reads 80 — the divergence, with SwiftUI's number in the doc comment | does not compile (new API); the same shapes spelled with `.minWidth`/`.maxWidth` read 40/80/20 today (scratch L10) | drop `minSize` from `style()` (arm 1); drop `maxSize` (arm 2) |
| 2.4 | `anIdealDimensionOnTheLegacyFrameTraps` (`FR-D`) | Two `#expect(processExitsWith: .failure)` bodies, `idealWidth` and `idealHeight`, each calling `.frame(idealWidth: 80)` on a `Box`; and a control body that passes `minWidth`/`maxWidth` only and exits **successfully** | does not compile (new API) | delete the precondition — both failure arms redden |
| 2.5 | `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules` | `probe.frame(width: 100).frame(width: 50)` reports 50 with the 20pt leaf at x = 15; reversed, reports 100 with the leaf at x = 40 — the probe's E1/E2 exactly. A third arm adds alignment: `.frame(width: 60, height: 40).frame(width: 120, height: 100, alignment: .topLeading)` reports 120×100 with the leaf at (20, 10) (probe E6). `try #require(15 != 40)` first | arms 1–2 **green**, measured (scratch M1 reads 15 and 40); arm 3 does not compile | mint the layer nodes outermost-first (arms 1 and 2 swap); drop `justifyContent` (arm 3) |
| 2.6 | `aLegacyFrameProposesItsWidthToAMeasuredLeaf` | `Column { Text("alpha bravo charlie delta").font(size: 12).frame(width: 60); marker }`: the marker sits at y = 60 — the text re-wrapped to four 15pt lines — against y = 15 for the same text with no frame. This is the "it broke text measurement" half of the reverted 2026-09-12 conversion, measured and refuted | **green**, measured (scratch L11: 60 vs 15). `try #require(60 != 15)` | drop `size.width` from `style()` |
| 2.7 | `aLegacyFrameAroundAListStillBuildsEveryRow` | `ScrollView { List(40 rows).frame(width: 200) }` paints the same 40 row rects as the unframed and `.width(200)` spellings — the "it broke list virtualization" half, measured and refuted (scratch L12). Counts are `try #require`d | green, measured | drop the frame layer's child list (`requestNode(style:children: [])`) — the framed arm paints 0 |

### Expected counts

1233 → **1250** tests (2.1 counts once; 2.4's exit tests count as one test).
Guards 61 → **62**: the `ModifiedElement` compile-guard fixture above, added to
the existing test in `ModifiedElementCompileGuards.swift`, so the guard count
moves and the test count does not. Goldens 97, unmoved — `FrameSpec.style()` produces CSS
the fixtures never exercise, and no fixture uses a modifier.

## Lane 3 — the sizing inventory

### Rulings

`FR-F` (`width`/`height` stay), `FR-G` (`min*`/`max*` stay), `FR-H`
(percentage sizing stays as a divergence), `FR-I` (no deprecation lands here;
the recipe and the owner).

### Source change

Documentation only, in `Sources/MetalUI/Box.swift`'s `MARK: Size` section: each
of the eight modifiers gains a sentence saying it writes **this element's own
CSS box**, that SwiftUI's spelling is `.frame(...)`, that the two differ
observably (a frame wraps; these do not), and — for `minWidth`/`minHeight` —
that a zero value is the only way to cancel §4.5's automatic minimum, which a
frame layer cannot do. `width(percent:)`/`height(percent:)` gain the
containing-block divergence and its test's name.

### Tests

| # | test | pins | before | mutation that must redden it |
|---|---|---|---|---|
| 3.1 | `aPercentageWidthResolvesAgainstItsContainingBlockAndNotTheProposal` (`FR-H`, **divergence, pinned as measured**) | Three arms in one file: in a 300pt `Row`, `.width(percent: 50)` on a box reads 150 (the control, and what CSS says); at the root it reads the offered width, not half of it (CLAUDE.md divergence 4's row, first test of it); **in a `Column`, `.width(percent: 100)` resolves against an unbounded cross axis and lays the box out about 30000pt wide** — the child lands at x ≈ −14850 in a 300pt column. The third arm's number is asserted as a range (< −1000), not an exact float, because its mechanism is not established | new tests; arms measured (scratch M4) | the `Column` arm is a characterization of a defect: its mutation is `.width(percent: 100)` → `.width(px(100))`, which moves the child to a sane position |
| 3.2 | `theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt` (`FR-F`, `FR-G`) | One probe element, eight arms: `.width`, `.height`, `.minWidth`, `.maxWidth`, `.minHeight`, `.maxHeight` each leave the element's own node count at 1 (`tree.nodeCount` before/after) where `.frame(width:)` makes it 2; and `.minHeight(0)` on a `List` row cancels the automatic minimum where `.frame(minHeight: 0)` does not (the demo's `main.swift:881` shape, the one live caller `FR-G` rests on) | green on arrival | route `width(_:)` through `frame(width:)` — arm 1's node count becomes 2 and the `minHeight` arm's rows change height. **This mutation is `FR-F`'s refusal made executable**: it also fails to compile in the demo and five test files, which the mutation record names |

### Expected counts

1250 → **1252** tests. Guards 62. Goldens 97.

## Lane 4 — verification

1. **Whole suite**, `swift test --build-system native --no-parallel`, read from
   the `Test run with N tests` line: **1252**, 0 `error:`, 0 `warning:`.
2. **Goldens**: `git diff --stat c4b5853 -- '*.json'` empty;
   `find Tests -name '*.json' | wc -l` = 97.
3. **Guards**: `grep -c canTypecheck` per file sums to **63** with one comment
   hit in `UnitSafetyTests.swift` — **62** real, one more than the baseline's
   61 (lane 2's overload fixture). It must be mutated red once in this
   worktree, after `swift build --build-system native`, because a worktree runs
   no guard otherwise (CLAUDE.md, "When CI lands") — a guard that silently
   skips is worth nothing and the count alone cannot tell you it ran.
4. **Demo and preview pixels**, by record §13's stand-in recipe: `git archive
   c4b5853` and the branch head into scratch directories, generate the
   `SI`-prefixed test file from each tree's `main.swift`, render ten images per
   tree through a real `Window` over `FakePlatformWindow` (1024×1024, scale 1)
   and compare `readPixels()`. **The expectation is 0 differing pixels in all
   ten**, and the controls (light vs dark, default vs modal) must be non-zero
   first. The demo calls no legacy `.frame` and the preview uses only fixed and
   infinite frames, so both lanes are expected to be invisible here; a non-zero
   count means `FrameSpec.style()` changed something the demo does reach.
5. **Real window captures**: check `ioreg -n Root -d1 -a | grep -A1
   IOConsoleLocked`; if false, take release-window captures with
   `screencapture -R`, sending no input. If locked, record the refusal as §13
   did and leave `MC-J` owed.
6. **Mutation discipline** (practices): commit before mutating; `cp` the file,
   restore from the copy, confirm with `git status --short`; run the whole
   suite per mutation and name the tests each reddens in the ruling's Mutations
   line; word coverage as a differential.

## Order, and what each lane may assume

Lane 1 → lane 2 → lane 3 → lane 4. Lane 1 touches only the proposal path and
can land alone. Lane 2 depends on lane 1 only for the shared no-argument
overload (`FR-J`); if lanes are reordered, that overload moves with whichever
lands first. Lane 3's doc changes cite lane 2's API by name.

## Deferrals this task creates, each with an owner

| deferral | why | owner |
|---|---|---|
| Deprecating `width`/`height`/`min*`/`max*` with `renamed:` hints | 685 call sites against a 0-warning gate; `.minHeight(0)`'s automatic-minimum override has no frame spelling | plan task 7 (`FR-I` holds the recipe) |
| A greedy maximum on the legacy path | needs the parent's main axis, which a layer does not have (M2, M4) | plan task 6 |
| `idealWidth`/`idealHeight` on the legacy path, possibly through `flexBasis` | unmeasured idea | plan task 7 |
| Renaming `ProposalAlignment` to `Alignment` | collides with the parallel track; cosmetic until the legacy path is gone | plan task 7 |
| The `Column` percentage defect (≈30000pt) | mechanism not investigated; pinned as measured by 3.1 | plan task 6 |
| `Component` distribution of `.frame`, and B-7's snap | `MC-L` assigns it | plan task 5 |
