# Frame and sizing design

Plan task 4 of `docs/superpowers/plans/2026-09-12-swiftui-alignment.md`, on
branch `feat/frame-sizing` in the worktree
`/Users/maxburger/Developer/MetalUI-frame-sizing`, from `c4b5853`.

Rulings `FR-A`…`FR-Q` live in
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

Measured across a design session and a critic round, three of those five
clauses turn out to be different jobs from what the sentence implies, and each
is settled with evidence rather than judgement:

1. **The proposal path's flexible frame is WRONG, not missing** (`SA-N` item 1,
   carried to this task). SwiftUI's flexible frame is *greedy*: with a maximum
   it answers the **proposal** clamped into `[min, max]`, not the child clamped
   — and, when no minimum is declared, the larger of the proposal and the child
   (`FR-M`, and item 3 below). The kernel answers the child. The fix is six
   lines and the two probes cover seventy-one arms.
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
3. **The kernel's flexible-frame rule that the design session wrote down was
   itself wrong**, and the 54-arm probe could not see it: every arm with a
   maximum proposes MORE than its child answers, so "the frame answers the
   proposal" and "the frame answers the larger of the proposal and the child"
   agree on all of them. A second probe separates them and they disagree
   (`FR-M`). The same probe shows the **shipped** kernel answering the proposal
   where SwiftUI answers the child at `.frame(maxWidth: .infinity)` over an
   oversized child — a live bug, in the spelling the demo's own preview uses.

So this task delivers **one frame semantics, shared by both paths** — one
alignment vocabulary, one parameter surface, one documented rule set, one
lowering — and re-documents the CSS box modifiers as engine-facing, with their
removal named and owned. Three legacy-path divergences remain, each ruled on and
each pinned wrong on purpose: `FR-E` (a finite maximum clamps but does not
grow), `FR-N` (an oversized child is squeezed on one axis), and `FR-O` (a
single-axis infinite maximum is inert).

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
| **critic round** — `docs/probes/swiftui-frame-negative-sizes.swift`, 17 arms, script and compiled forms diffed EMPTY (101 lines), the compiled form printing exactly two SwiftUI diagnostics | that SwiftUI never answers a negative size and floors declared negative bounds at 0; that an ABSENT minimum is not `minWidth: 0`; that `maxWidth: .infinity` over an oversized child answers the child | `FR-L`, `FR-M` |
| critic round — scratch `ZZScratchFrame2Tests.swift` (N1–N15), run with `--filter`, deleted before commit | the cross-axis blindness of `flexShrink = 0` and the axis-named pin that replaces it; that a both-axes infinite maximum can fill; that a frame layer cannot cancel the automatic minimum; that an oversized child is squeezed | `FR-N`, `FR-O`, `FR-P`, `FR-G` |
| critic round — a protocol skeleton compiled and run under `-swift-version 6` | that the refined protocol wins every `frame` shape; that the existing negative guard's diagnostic is unchanged; that `frame()` on `ElementGroup` **alone** leaves the proposal path silently unfixed | `FR-J`, lane 2's overload section |
| critic round — `framedSize`/`framedProposal` patched and the WHOLE suite run; then each candidate legacy lowering patched in turn and the whole suite run | the blast radius, by running rather than by reading: **exactly two** existing tests redden for the kernel change and **none** for either legacy lowering (1231/1231) | lane 1's sweep, lane 2's oracle note |

**The rule, in one place**, from both probes together — 71 arms (arm names are
the probes'; `H` arms are the negative-sizes probe):

```
lo = max(0, min)   hi = max(0, max)          // DECLARED bounds only (FR-L: H4, H6, H10)

childProposal(axis) = fixed ?? clamp(parentProposal ?? ideal,
                                     min == nil ? -inf : lo,      // H2 forwards -30; H4 floors to 0
                                     hi)                          // nil if proposal and ideal are both nil

response(axis)      = fixed ?? clamp(base, lo, hi)
  base = parentProposal        when a maximum is given, the proposal is concrete
                               AND A MINIMUM IS DECLARED    (D control, D1, D2, D13, C5, D16, H11, H13, H14)
       = max(parentProposal, child)
                               when a maximum is given, the proposal is concrete
                               and NO minimum is declared   (D4, D5, D10, D12, H2, H7, H8, H15, H16)
       = ideal                 when the proposal is nil     (C1, C3, C4)
       = child's answer        otherwise                    (C control, D6, D7, D8, D9, D14, D15)
```

The `min == nil` test is on **presence, not value**: probe H14 (`minWidth: 0`)
answers 10 where H8 (no minimum, the same numbers) answers 20.

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
- **Greedy FINITE maximums on the legacy path** — `FR-E`. Measured impossible to
  express per-axis without knowing the parent's main axis (M2, M4); pinned
  wrong on purpose. The **infinite** case is delivered for the both-axes
  spelling and refused for the single-axis one (`FR-O`, N14/N15).
- **An oversized child overflowing both axes** — `FR-N`. One flex node squeezes
  its main axis and overflows its cross axis, and the inner node is the caller's
  own element; pinned wrong on purpose (N5/N6).
- **`idealWidth`/`idealHeight` on the legacy path** — `FR-D`. No CSS
  counterpart; traps, exit-test pinned. The `flexBasis` idea is recorded as a
  deferral, unmeasured.
- **`Component` distribution of a frame, and paint-only layers** — plan task 5
  (`MC-L`).
- **`fixedSize`, `layoutPriority`, `aspectRatio` on the legacy path** — task 7.

## Lane 1 — the shared-file seam, then the kernel's flexible frame

### Rulings

`FR-A` (the response rule), `FR-B` (an infinite proposal), `FR-L` (negative
sizes), `FR-M` (an absent minimum), `FR-J` (the deprecated no-argument
`frame()`).

### Step 0, alone, first: the shared-file seam

`Sources/MetalUI/ModifiedElement.swift` is one of the eight files the parallel
paint-modifier track also edits, and its fourteen-line
`extension ElementGroup { frame(width:height:) }` occupies its **last** lines
(266–279) — the exact hunk boundary a second track appends at. Deleting it there
is the worst available merge shape (critic finding 14).

So the **first commit on this branch** replaces that extension **in place**,
same position, same line count or fewer, with a forwarding declaration whose
behaviour is identical:

```swift
extension ElementGroup {
    /// SwiftUI's frame. The lowering lives in `FrameLayer.swift` (ruling FR-C).
    public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<LayerBase> {
        _wrap(ModifierLayer(style: FrameSpec(width: width, height: height).style()))
    }
}
```

with `FrameSpec` and `style()` landing in the new `Sources/MetalUI/FrameLayer.swift`
in the same commit, reproducing today's style exactly — `alignItems` and
`justifyContent` both `.center`, `size` from the two parameters, nothing else.
**No behaviour changes and no test is added or edited**; the suite must read
`Test run with 1226 tests in 1 suite passed` unchanged. Everything lane 2 does
to the legacy frame then happens inside `FrameLayer.swift`, a file no other
track touches, and the merge sees one small early hunk rather than a deletion
racing an append.

### The kernel source change

`Sources/MetalUILayout/LayoutTree.swift`, `framedSize` and `framedProposal`:

```swift
private func framedProposal(_ parent: Double?, fixed: Double?, ideal: Double?,
                            min: Double?, max: Double?) -> Double? {
    guard fixed == nil else { return fixed }
    guard let proposal = parent ?? ideal else { return nil }
    // A DECLARED bound is floored at 0; an ABSENT minimum forwards a negative
    // proposal unchanged (FR-L: probe H4 proposes 0.0, H2 proposes -30.0).
    let lo = min.map { Swift.max(0, $0) } ?? -.infinity
    let hi = max.map { Swift.max(0, $0) } ?? .infinity
    return Swift.max(lo, Swift.min(proposal, hi))
}

private func framedSize(_ child: Double, proposal: Double?, fixed: Double?, ideal: Double?,
                        min: Double?, max: Double?) -> Double {
    if let fixed { return fixed }
    let lo = Swift.max(0, min ?? 0)
    let hi = max.map { Swift.max(0, $0) } ?? .infinity
    let base: Double
    if max != nil, let proposal, proposal.isFinite {
        // Greedy (FR-A) — but an ABSENT minimum floors the base at the child's
        // own answer (FR-M). `min == nil` tests PRESENCE, never value: probe
        // H14 (`minWidth: 0`) reads 10 where H8 (no minimum) reads 20.
        base = min == nil ? Swift.max(proposal, child) : proposal
    } else if proposal == nil, let ideal {
        base = ideal                         // probe C1, C3, C4
    } else {
        base = child                         // probe C control, D6-D9, D14, D15
    }
    return Swift.max(lo, Swift.min(base, hi))
}
```

Five things about it that are deliberate and must not be "simplified":

- **`max != nil` is the greedy gate, not `max == .infinity`.** The old code grew
  only at an infinite maximum; the probe grows at any maximum (D4 = 80 with a
  *finite* 80). Making it unconditional instead — greedy whenever the proposal
  is concrete — breaks `minWidth`-alone (D7 answers 40 at a 100pt proposal).
- **`min == nil ? Swift.max(proposal, child) : proposal` is `FR-M`**, and the
  test is on the minimum's **presence**. Probe H8 (`maxWidth: 80`, proposal 10,
  child 20) answers 20; H14 (`minWidth: 0, maxWidth: 80`, the same numbers)
  answers 10. Writing `(min ?? 0) == 0` instead reads 20 for both and is wrong.
- **`proposal.isFinite` keeps `FR-B`'s divergence.** At an infinite proposal
  SwiftUI answers `inf` (D12) and an earlier harness crashed inside SwiftUI's
  own placement on the NaN origin that follows. MetalUI answers the child.
- **The bounds are floored at 0 (`FR-L`)**, where the old code wrote `min ?? 0`
  and the design's first draft wrote `min ?? -.infinity`. SwiftUI never answers
  a negative size and floors a declared negative min/max at 0 (probe H4, H6,
  H10); the floor is on the **declared** bound, which is why `framedProposal`
  keeps `-.infinity` for an absent minimum (H2 forwards −30 unchanged).
- **The ideal branch stays second.** It is unreachable from the first (the
  greedy branch requires a non-nil proposal), so the order is documentation
  rather than logic — but swapping them is one of test 1.4's mutations.

Also in lane 1: `newNativeFrame`'s doc comment (the "Frame response" bullet
list) is rewritten to the rule above, and the deprecated no-argument overload
(`FR-J`, SwiftUI's own message) is added to **both** `ProposalElementGroup` and
`ElementGroup`:

```swift
@available(*, deprecated, message: "Please pass one or more parameters.")
public func frame() -> Self { self }
```

**Both declarations are load-bearing, and this was measured** (`FR-J`; critic
finding 11 asked for one and is refused). With it on `ElementGroup` alone, a
skeleton of the real protocol shape compiled under `-swift-version 6` infers
`ModifiedContent<Leaf, FrameModifier>` for `Leaf().frame()` **with no
deprecation warning** — the refined protocol's all-defaulted
`frame(width:height:alignment:)` is more specialized and wins — which is `SA-N`
item 9 surviving on the path that matters. With both, it infers `Leaf` and warns
on both paths. Nothing in `Sources/` or `Tests/` calls it, so it costs no
warning in the suite; test 1.10 exercises it inside a typecheck subprocess.

### Files

| file | change |
|---|---|
| `Sources/MetalUI/ModifiedElement.swift` | **step 0, alone**: the last extension replaced IN PLACE by a forwarding declaration. Nothing else in this file moves |
| `Sources/MetalUI/FrameLayer.swift` (new) | step 0: `FrameSpec` + `style()`, reproducing today's style exactly; then lane 2 extends it |
| `Sources/MetalUILayout/LayoutTree.swift` | `framedSize`, `framedProposal`; `newNativeFrame`'s doc |
| `Sources/MetalUI/NativeModifiedContent.swift` | the deprecated `frame()` on `ProposalElementGroup` |
| `Tests/MetalUILayoutTests/NativeLayoutTests.swift` | tests 1.1–1.6 new; 1.7 and 1.8 re-fixtured in place |
| `Tests/MetalUITests/NativeLayoutIntegrationTests.swift` | test 1.9 |
| `Tests/MetalUITests/FrameSizingCompileGuards.swift` (new) | test 1.10, a typecheck fixture |

### Tests

Each row: what it pins, its state before the change, the mutation that must
redden it after. "Green on arrival" marks a characterization; its proof is the
mutation.

| # | test | pins | before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aFrameWithAMinimumAndAMaximumGrowsTowardItsProposal` | Four arms over one `LayoutTree`, each a 20×20 leaf under `newNativeFrame`, read through `measureNativeLayout`, **all with a minimum declared** so `FR-M` is not in play: D control (min 40/max 80 at 100) → **80**; D1 (at 60) → 60; D2 (at 30) → 40; D13 (min 40/max 80, a 200pt child, at 100) → 80. Each arm also `#expect`s the child's proposal | **red**, to be re-measured on arrival: D control and D1 read 40 today; D2 (40) and D13 (80) are already right and are this test's internal controls | restore `max == .infinity` as the greedy gate (D control, D1 redden; D2, D13 stay green) |
| 1.2 | `aFrameWithNoMaximumAnswersItsChildRatherThanItsProposal` | D7 (min 40 alone at 100) → 40; D8 (at 30) → 40; D9 (at nil) → 40; D15 (min 400 at 100) → 400; C control (ideal 80 at a concrete 300) → 20 | green on arrival | make the greedy branch unconditional (`if let proposal, proposal.isFinite`) — D7, D15 and C control redden |
| 1.3 | `aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` (`FR-B`, **pinned against SwiftUI on purpose**: SwiftUI's D12 answers `inf`) | `maxWidth: .infinity` at `ProposedSize(width: .infinity, …)` answers the child's 20, and the stored rect is finite | green on arrival | drop `proposal.isFinite` from the greedy gate — the answer becomes `inf` |
| 1.4 | `anIdealDimensionIsUsedOnlyWhenThatAxisHasNoProposal` | C1 (ideal 80 at nil) → 80, child proposed 80; C control (ideal 80 at 300) → 20, child proposed 300; C3 (ideal 80 at nil over a 200pt child) → **80**, the ideal beating the child; C4 (min 40/ideal 80/max 120 at nil) → 80; C5 (the same at 300) → 120 | C1/C3/C4 green; **C5 red**: today's `framedSize` falls through to the child clamp and reads 40 | swap the first two branches of `framedSize` (C1 and C4 answer the child); delete the ideal branch (C1, C3, C4 redden) |
| 1.5 | `aFrameWithoutAMinimumNeverAnswersLessThanItsChild` (`FR-M`) | The finding the 54-arm probe could not see. Seven arms, each `#expect`ing the answer AND the child's proposal: H8 (max 80, **no min**, proposal 10, child 20) → **20**; H14 (`minWidth: 0` + max 80, the same numbers) → **10**; H7 (proposal 0) → 20; H11 (min 5/max 80 at 10) → 10; H13 (min 5/max 80 at 10 over a 200pt child) → 10; H15 (max 80, no min, at 10 over a 200pt child) → 80; H16 (max `.infinity`, no min, at 100 over a 200pt child) → **200**. `try #require(H8 != H14)` opens the test (shape 15): they are the same numbers and must disagree | **red**, measured on the patched kernel: today H8 reads 20 (right, via the non-greedy branch), H14 reads 20 (**wrong**, should be 10) and H16 reads **100** (wrong, should be 200 — a live bug in the shipped `max == .infinity` branch) | write the presence test as a value test, `(min ?? 0) == 0` — H14 reddens; drop the `Swift.max(proposal, child)` — H8, H7, H15, H16 redden |
| 1.6 | `aFrameNeverAnswersANegativeSize` (`FR-L`) | Five arms: H2 (max 80, no min, proposal −30, child 20) → **20**, child proposed **−30**; H4 (min −50/max 80 at −30) → **0**, child proposed **0**; H6 (min −50/max −10 at 100) → 0; H3 (min −50 at 100) → 20; H9 (min −50 at nil) → 20. `try #require` that H2's and H4's child proposals differ, since the whole ruling is that a declared bound floors and an absent one does not | **red**: today H4 and H6 read −30 and −10 through `framedProposal`'s unfloored bounds | drop the `Swift.max(0, …)` from `framedSize`'s `lo`/`hi` (H4, H6 redden); drop it from `framedProposal` (H4's child proposal reddens) |
| 1.7 | `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum` (existing, **re-fixtured**) | Same fixture; the measurement becomes **80×60** (width: min 40 given, so base = proposal 100, clamped to 80; height: base = proposal 60, inside [30, 70]). The child's stored rect `(15, −1, 20, 90)` does **not** move — placement uses the rect the caller passed | **red after the source change**, confirmed by running: it pins 40×70 today, which is `SA-N` item 1's wrong-on-purpose pin | as 1.1 |
| 1.8 | `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes` (existing, **re-fixtured**, critic finding 1) | Same fixture; the measurement becomes **70×60**. Width: the proposal is nil, so the ideal 70 is used, clamped into [40, 80] → 70. Height: a minimum (20) *is* declared and a maximum (70) is given at a concrete 60, so base = 60, clamp(60, 20, 70) = **60** — where the doc comment today says "the height is the child's 10 clamped to 20…70 = 20". **That sentence is a statement of the rule this lane deletes and must be rewritten, not renumbered.** The child rect `(10, 14, 30, 10)` does not move | **red after the source change**, confirmed by running | as 1.1 |
| 1.9 | `aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI` | The same finding one level up, through `ProposalElementGroup.frame(minWidth:maxWidth:)` inside a window-sized root: a 20pt proposal leaf under `.frame(minWidth: 40, maxWidth: 80)` in a 200-wide root measures 80 and centres the leaf at x = 30 | **red**, measured: 40 and x = 10 | as 1.1 |
| 1.10 | `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths` — a **typecheck fixture**, not a runtime test (`FR-J`, critic finding 2) | One `typecheckFile` body calling `.frame()` on a `ProposalElement` and on a legacy `StyledElement`, asserting (a) `result.succeeded`; (b) `result.messages.contains("'frame()' is deprecated")` **twice**, once per path; (c) through a `_ = exactly(leaf.frame())`-style pin, that each call's type is the receiver's own and neither is a `ModifiedContent` or `ModifiedElement`. The fixture compiles in a subprocess, so the deprecation never reaches the suite log's `warning:` count — the mechanism `EnvironmentCompileGuards.swift:47-48` already uses for `EV-N` | red: does not compile before the overloads exist | delete the `ElementGroup` declaration (the legacy path's type and message arms redden); delete the `ProposalElementGroup` declaration (the proposal path's arms redden — **measured**: it then infers `ModifiedContent<Leaf, FrameModifier>` with no diagnostic) |

### The sweep for existing tests, re-taken by running

Critic finding 1 asked for the sweep to be for *any* native frame with a finite
maximum at a concrete proposal, not for `maxWidth:` spellings. It was taken
instead by applying `FR-A`, `FR-L` and `FR-M` to `LayoutTree.swift` and running
the whole suite: **exactly two tests redden**, 1.7 and 1.8, and nothing else in
1226. Checked green in that run and therefore **not** owed a re-fixture:

- `aNativeFrameWithInfiniteMaximumExpandsToItsFiniteProposal` — no minimum, but
  its child (30×10) is smaller than its proposal (120×80), so `FR-M`'s
  `max(proposal, child)` is the proposal either way;
- `negativeAndNegativeInfiniteFrameMinimumsAndAnInfiniteMaximumAreAccepted`
  (`NativeValidationAcceptanceTests`) — the one existing test with a negative
  minimum; its four arms still read 20, 20, 100, 20 under `FR-L`'s floored
  bounds;
- `TrackInteractionTests:62/64` (min == max), `ModifierCompositionProofTests:855`
  (phase counts only), `ProposalLayoutTests:364/380` and
  `NativeLayoutWorkTests:81` (no maximum), `SizingFixtureTests:324` (a CSS
  `newNode`, not a native frame), and every arm of
  `NativeLayoutIntegrationTests`.

### Expected counts

1226 → **1233** tests (1.1–1.6 and 1.9 added; 1.7 and 1.8 edited in place; 1.10
is a guard). Guards 61 → **62**. Goldens 97, unmoved — lane 1 touches no CSS
path. Step 0 moves none of the three.

## Lane 2 — the legacy frame's SwiftUI surface

### Rulings

`FR-C` (the lowering table), `FR-D` (ideal traps), `FR-E` (no greedy finite
maximum), `FR-K` (one alignment type), `FR-N` (an oversized child is squeezed),
`FR-O` (an infinite maximum), `FR-P` (the fixed-axis pin).

### Public API

Everything below lands in `Sources/MetalUI/FrameLayer.swift`, created by lane
1's step 0. `ModifiedElement.swift` is **not touched again**.

```swift
/// SwiftUI's frame as one value: what `.frame(...)` asked for, before the CSS
/// lowering that `style()` performs.
///
/// INTERNAL on purpose (ruling FR-C): it appears in no public signature — both
/// overloads return `ModifiedElement<LayerBase>` — so a `public` spelling would
/// be a name an outside module can neither construct nor read, which is the
/// declared-but-inert shape CLAUDE.md keeps a table of. There is nothing to
/// narrow later, so no plain-import typecheck guard is owed (practices shape 16
/// applies to narrowing an EXISTING public name, which this never is).
struct FrameSpec: Sendable, Hashable {
    var width: Pixels?, height: Pixels?
    var minWidth: Pixels?, maxWidth: Pixels?
    var minHeight: Pixels?, maxHeight: Pixels?
    var alignment: ProposalAlignment = .center

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
    public func frame() -> Self { self }          // landed by lane 1
}
```

Both overloads keep the proposal path's parameter names, order and defaults, so
one call site ports between paths by changing nothing but the element type.
`ProposalAlignment` is reused rather than duplicated (`FR-K`).

**The overload-resolution risk, cleared by measurement before lane 2 starts.**
Until now the two paths' `frame(width:height:…)` had *different* signatures, so
a call on a proposal element could be resolved by its argument list alone. After
this change they are **identical**, and the only thing choosing between them is
that `ProposalElementGroup`'s extension is more specialized. That was unmeasured
for identical signatures, so it was measured: a throwaway skeleton — two
protocols, one refining the other, one type conforming to the refined one, the
same five overloads — compiled and run under `-swift-version 6`, Apple Swift 6.4.

| call on a proposal element | inferred |
|---|---|
| `.frame(width:)` | `ModifiedContent<Leaf, FrameModifier>` |
| `.frame(width:height:alignment:)` | `ModifiedContent<Leaf, FrameModifier>` |
| `.frame(minWidth:idealWidth:maxWidth:)` | `ModifiedContent<Leaf, FlexibleFrameModifier>` |
| `.frame(idealWidth:)` | `ModifiedContent<Leaf, FlexibleFrameModifier>` |
| `.frame(maxWidth:)` | `ModifiedContent<Leaf, FlexibleFrameModifier>` |
| `.frame(alignment:)` | `ModifiedContent<Leaf, FrameModifier>` |
| `.frame()` (both declared) | `Leaf`, with the deprecation |

Nothing is ambiguous and the refined protocol wins every shape. **And the
existing negative guard's exact diagnostic is unchanged** (critic finding 4):
`Leaf().frame(width: Pixels(10), minWidth: Pixels(5))` against the doubled
overload set is still rejected with `extra argument 'minWidth' in call`, and
`minHeight` likewise — so `aFixedAndAFlexibleFrameDimensionCannotBeCombined`
(`ProposalLayoutCompileGuards.swift:258-281`) needs no re-fixture. The skeleton
is still lane 2's first step, re-run against the real module once the source
lands; if any row moves, this spec is amended before a test is written.

**Lane 2's new guard** (critic finding 5) goes in `FrameSizingCompileGuards.swift`
beside test 1.10, and is broader than "it still compiles", because
mis-resolution here is **silent**: a legacy overload winning on a proposal
element produces a `ModifiedElement<…>` wrapping a native subtree, which
compiles and then meets `SA-G` (`newNode` refuses a native child) at run time,
and `.frame(idealWidth: 80)` resolving to the `ElementGroup` overload would turn
a working SwiftUI idiom into `FR-D`'s trap. So the fixture asserts the **inferred
type** of `.frame(width:)`, `.frame(minWidth:idealWidth:maxWidth:)`,
`.frame(idealWidth:)` and `.frame(alignment:)` on a proposal element, and test
2.4 gains a run-time control that `.frame(idealWidth: 80)` on a proposal element
**exits successfully**.

### The lowering (`FR-C`), row by row with its evidence

`FrameSpec.style()` builds one `Style`, in a flex row layer:

| what the caller asked for | `Style` | evidence |
|---|---|---|
| any frame | `flexDirection` stays `.row`; `justifyContent` and `alignItems` from a **`switch` over `ProposalAlignment`'s nine cases** — never over `horizontalFactor`/`verticalFactor`, which are `Double`s whose `switch` needs a `default` that would silently pick an edge for any later case (critic finding 15) | scratch L6: all nine combinations place a 20×20 child at the probe's B1–B8 offsets exactly |
| `width` / `height` | `size.<axis>` **and `minSize.<axis>`** — an axis-named pin, **not** `flexShrink = 0` | `FR-P`: scratch N10 (the pin is equivalent on the main axis: 90/290 either way, against 65/215 unpinned) and N11 (`flexShrink = 0` pins an undeclared width, 154 → 210, where the pin does not). `flexGrow = 0` is dropped: already `Style`'s default |
| `minWidth` / `minHeight` | `minSize.<axis>` | scratch L10: `minWidth 40` over a 20pt child reads 40, agreeing with probe D7/D8/D9 |
| `maxWidth` / `maxHeight`, finite | `maxSize.<axis>` — **a clamp, never greedy** | scratch L10 vs probe D4: MetalUI 20, SwiftUI 80. `FR-E`, pinned wrong on purpose |
| `maxWidth` **and** `maxHeight` both `.infinity` | `flexGrow = 1` **and** `alignSelf = .stretch` — it **fills** | `FR-O`: scratch N14 — the mark lands at (140, 90) in both a `Row` and a `Column` parent, against (0, 90) and (140, 0) unlowered |
| one `.infinity` maximum alone | left `.auto`: the layer is present and **inert** | `FR-O`: scratch N15 — the fill lowering applied to one axis pushes a `Column` sibling from y = 20 to y = 195, consuming a height nobody asked for. Pinned present-and-inert by test 2.9 and owed a CLAUDE.md declared-but-inert row at integration |
| `idealWidth` / `idealHeight` | **precondition failure** | `FR-D`; no CSS spelling, and an accepted-and-ignored parameter is the declared-but-inert shape CLAUDE.md exists to keep out |

### Files

| file | change |
|---|---|
| `Sources/MetalUI/FrameLayer.swift` | `FrameSpec` gains its six bounds and alignment; `style()` gains the table above; the two overloads |
| `Sources/MetalUI/Box.swift` | doc comments only, in the `MARK: Size` section (`FR-F`, `FR-G`, `FR-H`, `FR-Q`) — lane 3 |
| `Tests/MetalUITests/FrameSizingTests.swift` | new; tests 2.1–2.10 |
| `Tests/MetalUITests/FrameSizingCompileGuards.swift` | the overload fixture |
| `Tests/MetalUITests/ModifierCompositionProofTests.swift` | `frameStyle(width:height:)` (line 503) gains the `minSize` pin |

**The oracle obligation, restated after measurement.** The spec previously said
`aModifierChainIsIdenticalToHandBuiltNestedBoxes` (`MC-B`) would redden unless
its hand-built frame `Box` gained the new field. **That is false, and it was
measured**: each candidate lowering was applied in turn to the live
`ElementGroup.frame(width:height:)` and the whole suite run — `Test run with
1231 tests in 1 suite passed` both times (1226 + 5 scratch), with the oracle
untouched. So the edit is **not** a redness obligation; it is a **drift**
obligation, and the stronger one. `frameStyle` is a hand-spelled duplicate of
the lowering, and the suite has just demonstrated it will not tell you when the
two diverge. It changes in the same commit, and lane 2 records that the suite
was green both before and after that edit.
`modifierOrderChangesSizeAndPlacementAsSwiftUIDoes` (`MC-L`) must stay green
untouched, and lane 2 says so after running it, not before.

### Tests

| # | test | pins | before | mutation that must redden it |
|---|---|---|---|---|
| 2.1 | `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments` | Nine arms, a 20×20 probe leaf in `.frame(width: 60, height: 40, alignment:)`, rendered through `Frame`: origins `(0,0) (20,0) (40,0) (0,10) (20,10) (40,10) (0,20) (20,20) (40,20)`. `try #require` that `.topLeading` ≠ `.center` before the nine comparisons (shape 15) | does not compile: the parameter does not exist. Today's fixed `.center` behaviour is the `.center` arm, green | drop `justifyContent` from `style()` (six arms redden); drop `alignItems` (six redden); swap the two axes (four redden) |
| 2.2 | `aLegacyFixedFrameDoesNotShrinkAsAFlexItem` (`FR-P`) | `Row { probe.frame(width: 200, height: 20); probe.frame(width: 200, height: 20) }` in a 300×200 frame: the marks sit at x = 90 and 290 — each layer 200 wide. A `try #require` that the row is narrower than their sum, so the arm is actually over-constrained | **red**, measured: the marks sit at 65 and 215 — the layers shrank to 150 (scratch N10) | drop `minSize` from the fixed-axis rows of `style()` |
| 2.3 | `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal` (`FR-E`, **half pinned wrong on purpose**) | In a 300pt `Row`, reading each layer's width from a 5pt sibling's x: `.frame(minWidth: 40)` over a 20pt child → **40** (agrees with probe D7); `.frame(maxWidth: 80)` over a 200pt child → **80** (agrees with D14); `.frame(maxWidth: 80)` over a 20pt child → **20**, where SwiftUI's D4 reads 80 — the divergence, with SwiftUI's number in the doc comment | does not compile (new API); the same shapes spelled `.minWidth`/`.maxWidth` read 40/80/20 today (scratch L10) | drop `minSize` from the minimum row (arm 1); drop `maxSize` (arm 2) |
| 2.4 | `anIdealDimensionOnTheLegacyFrameTraps` (`FR-D`) | Two `#expect(processExitsWith: .failure)` bodies, `idealWidth` and `idealHeight`, each calling `.frame(idealWidth: 80)` on a `Box`; a control body passing `minWidth`/`maxWidth` only that exits **successfully**; and a second control (critic finding 5) calling `.frame(idealWidth: 80)` on a **proposal** element, which must also exit successfully — the positive control for the overload split | does not compile (new API) | delete the precondition — both failure arms redden. Make the legacy overload win on a proposal element — the proposal control reddens |
| 2.5 | `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules` | `probe.frame(width: 100).frame(width: 50)` reports 50 with the 20pt leaf at x = 15; reversed, reports 100 with the leaf at x = 40 — the probe's E1/E2. A third arm adds alignment: `.frame(width: 60, height: 40).frame(width: 120, height: 100, alignment: .topLeading)` reports 120×100 with the leaf at (20, 10) (probe E6). `try #require(15 != 40)` first. The doc comment records that arms 1–2 do **not** discriminate on their own (scratch N13: a 100pt inner overflowing a 50pt outer and one shrunk to 50 both centre the leaf at 15) — arm 3 is what does | arms 1–2 **green**, measured (scratch M1, and unchanged by the `minSize` pin — N13); arm 3 does not compile | mint the layer nodes outermost-first (arms 1 and 2 swap); drop `justifyContent` (arm 3) |
| 2.6 | `aLegacyFrameProposesItsWidthToAMeasuredLeaf` | `Column { Text("alpha bravo charlie delta").font(size: 12).frame(width: 60); marker }`: the marker sits at y = 60 — the text re-wrapped to four 15pt lines — against y = 15 unframed. The "it broke text measurement" half of the reverted 2026-09-12 conversion, refuted | **green**, measured (scratch L11: 60 vs 15). `try #require(60 != 15)` | drop `size.width` from `style()` |
| 2.7 | `aLegacyFrameAroundAListStillBuildsEveryRow` | `ScrollView { List(40 rows).frame(width: 200) }` paints the same 40 row rects as the unframed and `.width(200)` spellings — the "it broke list virtualization" half (scratch L12). Counts are `try #require`d | green, measured | **localized** (critic finding 16): set the frame layer's own `size.height` to a fixed 40 in `style()` and re-count — the framed arm's row count collapses while the unframed and `.width(200)` arms hold, which is what makes the claim about virtualization rather than about painting. The previous mutation (dropping the layer's child list) reddened every framed element in the suite and proved nothing about this test. Lane 2 names the tests the chosen mutation reddens, from the run |
| 2.8 | `aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows` (`FR-N`, **pinned wrong on purpose**) | A child declaring 200×160 inside `.frame(width: 60, height: 40)` lands at **(0, 20) 60×160** — width squeezed to the frame, height overflowing — where SwiftUI's A5 keeps 200×160 at (−70, −60). SwiftUI's numbers are in the doc comment. A second arm repeats it with `flexShrink(0)` on the layer and reads the same, separating "the layer shrank" from "the child was shrunk as its flex item" | **green**, measured (scratch N5/N6, and record §14's L3) | set the layer's `flexDirection` to `.column` — the squeeze moves to the height and both arms redden, which is the evidence that one node cannot overflow both axes |
| 2.9 | `anInfiniteMaximumFillsOnlyWhenBothAxesAreInfinite` (`FR-O`) | Two arms with a disagreeing `try #require` between them. **Fill**: `.frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))` around a 20×20 mark in a 300×200 `Row` puts the mark at (140, 90), and at (140, 90) in a `Column` too. **Inert**: `.frame(maxWidth: Pixels(.infinity))` alone leaves the mark where the unframed spelling does, and `tree.nodeCount` is one higher than unframed — the layer exists and does nothing | does not compile (new API); measured as scratch N14/N15 | drop `alignSelf = .stretch` (the `Row` fill arm's y reddens, the `Column` fill arm's x reddens); drop `flexGrow = 1` (the other halves redden); extend the fill lowering to a single infinite maximum (the inert arm reddens) |
| 2.10 | `aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare` (`FR-P`) | `.frame(height: 40)` around a wrapping `Text` in an over-constrained 300pt `Row`, with a 200pt sibling whose x reads the layer's width: **154**, the same as the unframed spelling, where `flexShrink = 0` would read 210 and leave the text unwrapped. The doc comment carries 210 as the number this test exists to keep out | **green** under the `minSize` lowering, **red** under `flexShrink = 0`; measured as scratch N11 | replace the axis-named pin with `flexShrink = 0` on any fixed axis — this test reddens where 2.2 does not, which is the whole finding |

### Expected counts

1233 → **1243** tests (2.1–2.10; 2.4's exit tests count as one test). Guards 62 →
**63**: the overload fixture. Goldens 97, unmoved — `FrameSpec.style()` produces
CSS the fixtures never exercise, and no fixture uses a modifier.

## Lane 3 — the sizing inventory

### Rulings

`FR-F` (`width`/`height` stay), `FR-G` (`min*`/`max*` stay, now measured),
`FR-H` (percentage sizing stays as a divergence), `FR-Q` (the rem inventory),
`FR-I` (no deprecation lands here; the recipe and the owner).

### Source change

Documentation only, in `Sources/MetalUI/Box.swift`'s `MARK: Size` section: each
of the eight modifiers gains a sentence saying it writes **this element's own
CSS box**, that SwiftUI's spelling is `.frame(...)`, and that the two differ
observably (a frame wraps; these do not). `minWidth`/`minHeight` gain the
sentence that a zero value is the only way to cancel §4.5's automatic minimum —
which a frame layer cannot do, with `FR-G`'s N7/N9 numbers named.
`width(percent:)`/`height(percent:)` gain the containing-block divergence and
its test's name. `padding(_ edges:)`, `margin(_ edges:)` and
`borderWidth(_ edges:)` gain one sentence each recording that a `Length` may be
`.rems`, resolved against `Frame`'s single per-frame `rootFontSize` (`FR-Q`),
which is where the brief's "rem helpers" clause is answered: there is no rem
sizing helper to decide about, only a box-model unit that is already pinned by
`ResolveTests`.

### Tests

| # | test | pins | before | mutation that must redden it |
|---|---|---|---|---|
| 3.1 | `aPercentageWidthResolvesAgainstItsContainingBlockAndNotTheProposal` (`FR-H`, **divergence, pinned as measured**) | Three arms: in a 300pt `Row`, `.width(percent: 50)` reads 150 (the control, and what CSS says); at the root it reads the offered width, not half of it (CLAUDE.md divergence 4's row, first test of it); **in a `Column`, `.width(percent: 100)` resolves against an unbounded cross axis** and the child lands at x ≈ −14850 in a 300pt column. The third arm asserts a range (< −1000), not an exact float, because its mechanism is not established | new tests; arms measured (scratch M4) | the `Column` arm is a characterization of a defect: its mutation is `.width(percent: 100)` → `.width(px(100))`, which moves the child to a sane position |
| 3.2 | `theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt` (`FR-F`, `FR-G`) | Two halves. **Node count**: `.width`, `.height`, `.minWidth`, `.maxWidth`, `.minHeight`, `.maxHeight` each leave `tree.nodeCount` at the unwrapped value where `.frame(width:)` adds one. **The automatic minimum**, on the demo's own shape (`main.swift:878-881`: a `flexGrow(1)`, `flexBasis(0)` box holding 400pt of content in a 200pt `Column` under an 80pt header): `.minHeight(px(0))` gives the content **120**, no `minHeight` gives **400**, and `.frame(minHeight: 0)` gives **400** — with `flexGrow`/`flexBasis` on the layer and on the inner box alike. `try #require(120 != 400)` opens that half | **green on arrival**, every number measured this round (scratch N7, N8, N9, N9b) | route `width(_:)` through `frame(width:)` — the node-count half reddens. **This mutation is `FR-F`'s refusal made executable**: it also fails to compile in the demo and five test files, which the mutation record names. For the second half: make the frame layer's `minSize` reach its child — the `.frame(minHeight: 0)` arm would then read 120 and redden, which is the arm's whole point |

### Expected counts

1243 → **1245** tests. Guards 63. Goldens 97.

## Lane 4 — verification

1. **`swift package clean` first** (critic finding 14). Both tracks add stored
   properties to types that cross a module boundary — `ModifierLayer` and
   `ModifiedElement` are public and `MetalUI` is imported by `MetalUIDemo` and
   by five test targets — which is CLAUDE.md's documented incremental-layout
   hazard. Clean before the verification run, not after a symptom.
2. **Whole suite**, `swift test --build-system native --no-parallel`, read from
   the `Test run with N tests` line: **1245**, 0 `error:`, 0 `warning:`.
3. **Goldens**: `git diff --stat c4b5853 -- '*.json'` empty;
   `find Tests -name '*.json' | wc -l` = 97.
4. **Guards**: `grep -c canTypecheck` per file sums to **64** with one comment
   hit in `UnitSafetyTests.swift` — **63** real, two more than the baseline's 61.
   Each of the two new ones must be **mutated red once in this worktree**, after
   `swift build --build-system native`, because a worktree runs no guard
   otherwise (CLAUDE.md, "When CI lands") — a guard that silently skips is worth
   nothing and the count alone cannot tell you it ran.
5. **Demo and preview pixels**, by record §13's stand-in recipe: `git archive`
   `c4b5853` and the branch head into scratch directories, generate the
   `SI`-prefixed test file from each tree's `main.swift`, render ten images per
   tree through a real `Window` over `FakePlatformWindow` (1024×1024, scale 1)
   and compare `readPixels()`. The controls (light vs dark, default vs modal)
   must be non-zero first.
   **The expectation is no longer "0 differing pixels in all ten".** The demo
   calls no legacy `.frame`, so lane 2 and lane 3 are invisible here. But lane 1
   changes the kernel's infinite-maximum branch, and the preview's outermost
   element is `.frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))`
   (`main.swift:1032`): under `FR-M` that frame answers `max(proposal, child)`
   where it answered the proposal, which SwiftUI's probe H16/H17 says is correct
   and which **can** move the preview if its content is wider or taller than the
   window offers. So: the eight non-preview images must be **0**, and the two
   preview images are inspected rather than asserted — a difference there is
   investigated against H16 and recorded either as the fix landing or as a
   regression, and the demo's default (non-preview) frame must be 0 regardless.
6. **Real window captures**: check `ioreg -n Root -d1 -a | grep -A1
   IOConsoleLocked`; if false, take release-window captures with
   `screencapture -R`, sending no input. If locked, record the refusal as §13
   did and leave `MC-J` owed.
7. **Mutation discipline** (practices): commit before mutating; `cp` the file,
   restore from the copy, confirm with `git status --short`; run the whole suite
   per mutation and name the tests each reddens in the ruling's Mutations line;
   word coverage as a differential.

## Order, and what each lane may assume

Lane 1 → lane 2 → lane 3 → lane 4, and lane 1's **step 0 is its own commit,
before anything else on the branch** (critic finding 14). Lane 1 otherwise
touches only the proposal path and the kernel, and can land alone. Lane 2 owns
`FrameLayer.swift` from step 0 onward and re-touches no shared file. Lane 3's
doc changes cite lane 2's API by name.

## Deferrals this task creates, each with an owner

| deferral | why | owner |
|---|---|---|
| Deprecating `width`/`height`/`min*`/`max*` with `renamed:` hints | 685 call sites against a 0-warning gate; `.minHeight(0)`'s automatic-minimum override has no frame spelling, now measured (`FR-G`, N7/N9) | plan task 7 (`FR-I` holds the recipe) |
| A greedy **finite** maximum on the legacy path | needs the parent's main axis, which a layer does not have (M2, M4) | plan task 6 |
| A **single-axis** infinite maximum filling | same reason; the both-axes case is delivered (`FR-O`, N14/N15). Owes a CLAUDE.md declared-but-inert row at integration | plan task 6 |
| An oversized child overflowing both axes rather than being squeezed on one | one flex node cannot; the inner node is the caller's element (`FR-N`) | plan task 6 |
| `idealWidth`/`idealHeight` on the legacy path, possibly through `flexBasis` | unmeasured idea | plan task 7 |
| Renaming `ProposalAlignment` to `Alignment` | collides with the parallel track; cosmetic until the legacy path is gone | plan task 7 |
| The `Column` percentage defect (≈30000pt) | mechanism not investigated; pinned as measured by 3.1 | plan task 6 |
| Tightening `SA-J` to reject a negative minimum at registration, rather than flooring it in `framedSize` | `FR-L` matches SwiftUI's *answers*; SwiftUI also diagnoses a negative fixed size and maximum, which MetalUI already traps. Changing what `SA-J` accepts is the kernel track's ruling to change | plan task 7 |
| `Component` distribution of `.frame`, and B-7's snap | `MC-L` assigns it | plan task 5 |
