# Frame and sizing decisions (plan task 4)

Rulings for `docs/superpowers/specs/2026-09-15-frame-sizing-design.md`, on
`feat/frame-sizing` from `c4b5853`. Ids are **lettered**, `FR-A`…; next unused
is **`FR-R`**. A bare `FR-3` is a typo, not a citation.

**Status, 2026-09-15, after the critic round:** design only. No source file has
changed — every source patch below was applied, measured and restored from a
`cp` backup, with `git status --short` empty afterwards each time. Two probes
are committed and re-runnable: `docs/probes/swiftui-frame-semantics.swift` (54
arms, the design session) and `docs/probes/swiftui-frame-negative-sizes.swift`
(17 arms, this round). The scratch tests they are compared against were run with
`--filter` and deleted. The suite at `c4b5853` reads `Test run with 1226 tests
in 1 suite passed`, 0 `error:`, 0 `warning:`, 97 goldens, 61 typecheck guards.

**What the critic round changed.** Sixteen findings were raised; **fifteen are
applied and one (`frame()` declared on both protocols) is refused with a
measurement that shows the critic's simplification reintroduces the bug the
ruling exists to fix** — see `FR-J`. Two of the applied findings turned into
*better* answers than the finding asked for, because the measurement went
further than the objection: the fixed-axis pin is an axis-named `minSize`
rather than `flexShrink = 0` (`FR-P`), and a both-axes infinite maximum fills
rather than being inert (`FR-O`). And chasing finding 12's negative-size
question produced **two findings nobody had raised**: `FR-M` (an absent minimum
is not `minWidth: 0`, and the design's own kernel rule was wrong because of it)
and the fact that the live kernel's infinite-maximum branch has been answering
the proposal where SwiftUI answers the child (probe H16).

**Toolchains.** macOS 26.6.2 (25G83). `/usr/bin/swift` and `xcrun swiftc`
report Apple Swift 6.4 (swiftlang-6.4.0.33.1); the `swift`/`swiftc` first on
PATH is swiftly's swift.org 6.3.3, whose JIT fails on every SwiftUI symbol
(ruling `SA-O`). The suite runs under `swift test --build-system native
--no-parallel`.

**Probe arm names** (`A1`, `D control`, `E2`, …) refer to
`docs/probes/swiftui-frame-semantics.swift`, whose header carries the full
recorded output. **Scratch arm names** (`L1`…`L14`, `M1`…`M4`) refer to the
deleted `Tests/MetalUITests/ZZScratchFrameTests.swift`; every figure they
produced is quoted in the ruling that uses it and in record §14, because the
file itself is gone.

---

## FR-A — SwiftUI's flexible frame is greedy, and MetalUI's kernel is not

**The finding.** For each axis, SwiftUI's frame answers
`clamp(base, min, max)` where `base` is:

- the **parent's proposal**, when a maximum is given and the proposal is
  concrete;
- the **ideal**, when that axis has no proposal;
- the **child's own answer**, otherwise.

The child is proposed `fixed ?? clamp(parentProposal ?? ideal, min, max)`, or
nothing when both are nil.

**Evidence** (probe, 54 arms, script and compiled forms byte-identical):

| arm | frame | proposal | child | SwiftUI | today's kernel |
|---|---|---|---|---|---|
| D control | min 40, max 80 | 100 | 20 | **80** | 40 |
| D1 | min 40, max 80 | 60 | 20 | 60 | 40 |
| D2 | min 40, max 80 | 30 | 20 | 40 | 40 |
| D4 | max 80 | 100 | 20 | **80** | 20 |
| D5 | max 80 | 30 | 20 | **30** | 20 |
| D6 | max 80 | nil | 20 | 20 | 20 |
| D7 | min 40 | 100 | 20 | 40 | 40 |
| D9 | min 40 | nil | 20 | 40 | 40 |
| D10 | max ∞ | 100 | 20 | 100 | 100 |
| D13 | min 40, max 80 | 100 | **200** | 80 | 80 |
| D14 | max 80 | nil | 200 | 80 | 80 |
| D15 | min 400 | 100 | 20 | 400 | 400 |
| C control | ideal 80 | 300 | 20 | 20 | 20 |
| C1 | ideal 80 | nil | 20 | 80 | 80 |
| C5 | min 40, ideal 80, max 120 | 300 | 20 | **120** | 40 |

D4 versus D7 is what rules out both simpler theories: a maximum makes the frame
take the proposal; a minimum alone does not. D5 rules out "grow to the
maximum": it grows to the *proposal*, 30, under an 80pt cap. D13 and D14 rule
out "answer the child": a 200pt child under an 80pt cap reads 80 either way,
which is why they are the test's internal controls rather than its subject.

**The ruling.** `framedSize` in `Sources/MetalUILayout/LayoutTree.swift` takes
the rule above, **as amended by `FR-M` and `FR-L`** — the greedy base is the
proposal only when a minimum is *also* declared, and the declared min/max are
floored at 0. This closes record §09's open question ("whether a finite
`maxWidth` frame grows — it does") and `SA-N` item 1, whose owner is named as
this task.

**Amended after the critic round.** The rule as first written here was
incomplete, and the 54-arm probe could not see it: every D arm with a maximum
proposes MORE than its child answers, so "base is the proposal" and "base is
the larger of the proposal and the child" agree on all of them. They disagree
at H8 (20 against 10) and the second probe settles it. `FR-M` carries the
correction and the decisive arms; this ruling's table above is unchanged and
still correct, arm for arm.

**What it costs if wrong.** Every `.frame(maxWidth:)` in a proposal subtree
sizes to its content instead of filling, which is the single most common
SwiftUI layout idiom. Wrong in the other direction — greedy without a maximum
— `.frame(minWidth: 40)` would make every view fill its parent, which probe
D7/D15 refute directly.

**Mutations.** Recorded by lane 1 (spec tests 1.1, 1.2, 1.4, 1.5, 1.6).

---

## FR-B — an infinite proposal answers the child, where SwiftUI answers infinity

**The finding.** Probe D12: `frame(maxWidth: .infinity)` offered
`inf × inf` answers **`inf × 20`** and places its 20pt child at `x = inf`. An
earlier pass of the same harness, which placed the view under test at
`bounds.origin` rather than at `.zero`, **crashed inside SwiftUI**:
`SwiftUICore/Layout.swift:1535: Fatal error: view origin is invalid:
(nan, 190.0), UnitPoint(x: 0.0, y: 0.0), (20.0, 20.0)` — centring a finite
child inside an infinite frame produces a NaN origin. Both observations are in
the probe's header.

**The ruling.** MetalUI keeps `proposal.isFinite` on the greedy branch, so an
infinite proposal is treated as unspecified and the frame answers its child.
The difference is a **deliberate divergence**, pinned by spec test 1.3 with
SwiftUI's answer in the doc comment.

**Reasoning.** An infinite measured size reaches `LayoutRect`, `Bounds` and
then the renderer as an infinite quad. SwiftUI's own answer is not usable
either — it traps one step later in its own placement — so adopting it would
import a crash, not a behaviour. The proposal path's scroll viewport is the one
production source of a non-finite proposal, and the divergence is reachable
from it.

**What it costs if wrong.** A `.frame(maxWidth: .infinity)` inside a proposal
scroll view on the scrolling axis reports its content size rather than
expanding. That is the conservative failure; the alternative is an infinite
rect in the scene.

---

## FR-C — the legacy frame lowers to one `Style`, and the table is probe-backed row by row

**The ruling.** `FrameSpec.style()` in the new
`Sources/MetalUI/FrameLayer.swift` is the **only** place the CSS approximation
of a SwiftUI frame lives. Its table, each row with the measurement behind it,
is in the spec's lane 2. The two rows that are new behaviour rather than a
rename:

- **Alignment** → `justifyContent` from `alignment.horizontalFactor` and
  `alignItems` from `verticalFactor`, on the layer's default `.row` direction.
  Scratch **L6** ran all nine combinations against a 20×20 child in a 60×40
  layer and read `(0,0) (0,10) (0,20) (20,0) (20,10) (20,20) (40,0) (40,10)
  (40,20)` — the probe's B1–B8 offsets exactly, with no case missing and none
  approximate.
- **An axis-named `minSize` on a fixed axis** — `size.width` AND
  `minSize.width` for a declared width, likewise for height. **Not
  `flexShrink = 0`**, which the critic round measured to be axis-blind; `FR-P`
  carries the measurement and the refusal, and `flexGrow = 0` is dropped because
  it is already `Style`'s default (`Style.swift:131`).
- **Alignment is lowered by switching over `ProposalAlignment`'s nine cases,
  never over `horizontalFactor`/`verticalFactor`.** A `switch` over a `Double`
  needs a `default`, and a `default` silently picks one edge for any value that
  is not exactly 0, 0.5 or 1 — which is what a later non-standard alignment or a
  `UnitPoint`-style generalization would produce. Switching over the cases makes
  the compiler enforce exhaustiveness, so such an addition is a build error in
  `FrameSpec.style()` rather than a silently wrong edge. The factors stay the
  *evidence* (scratch L6 read all nine against them); they are not the lowering.
- **An infinite maximum on BOTH axes fills; on one axis it is inert.** `FR-O`.

**Reasoning for one lowering function rather than a second node kind.** The
legacy engine cannot accept a native frame node (`LayoutTree.newNativeFrame`
requires a native child, `newNode` refuses a native one — ruling `SA-G`), so
the legacy frame must remain CSS. Keeping the approximation in one function,
with `FrameSpec` as its input, is what makes "one semantic path" true of the
*surface* even though two engines are still live: both paths take the same
parameters, the same alignment vocabulary and the same documented rules, and
the difference between them is one table a reader can find.

**What it costs if wrong.** A caller who ports a `.frame` from the proposal
path to the legacy path gets a silently different layout. **The silent set is
not empty, and the critic round was right to say so.** It is exactly three, each
with a ruling and a test that pins it wrong on purpose:

| divergence | ruling | test |
|---|---|---|
| a finite maximum clamps but never grows into the proposal | `FR-E` | 2.3 |
| a child bigger than the frame is SQUEEZED on the layer's main axis, where SwiftUI overflows both | `FR-N` | 2.8 |
| a single-axis infinite maximum is a node that does nothing | `FR-O` | 2.9 |

`FR-D` (a trap) is loud rather than silent, and is not in this set. The claim
that "the silent set is meant to be empty" was written before `FR-N` and `FR-O`
existed and is withdrawn: the honest statement is that the silent set is three,
enumerated, and each member is pinned.

---

## FR-D — `idealWidth`/`idealHeight` trap on the legacy path

**The finding.** An ideal dimension is defined entirely by "what this view
wants when nothing is proposed" (probe C control versus C1: the same frame
answers 20 at a concrete proposal and 80 at none). The CSS engine has no
unspecified proposal: every box is laid out against a containing block, and its
`auto` size is fit-content, which is a *measurement*, not a caller-supplied
preference. `Style` has no field that carries one.

**The ruling.** `ElementGroup.frame(minWidth:idealWidth:…)` accepts the
parameters for signature parity and **traps** when either ideal is non-nil, with
a message naming the proposal path. Pinned by exit tests (spec test 2.4), which
also assert that the same call with min/max only exits successfully.

**Reasoning.** The alternative is an accepted-and-ignored parameter, which is
precisely the "declared but inert" shape CLAUDE.md keeps a table of. A trap is
loud, testable, and removable the day a lowering exists. The parameters stay in
the signature so that a port between paths is a type change and nothing else,
and so the trap message can name what to do.

**The unmeasured idea, recorded so nobody re-derives it.** CSS's nearest thing
to an ideal is `flexBasis`: a flex item's base size before growing or
shrinking, which is what a container consults when it measures content. It is
main-axis-only and meaningful only inside a flex parent, so it cannot answer
`idealWidth` when the parent is a `Column`. Nothing was measured. Owner: plan
task 7.

**What it costs if wrong.** A caller who legitimately wants an ideal on the
legacy path gets a crash instead of an approximation. That is the intended
trade: the approximation would be wrong in the direction nobody can see.

---

## FR-E — the legacy frame clamps at a maximum but never grows into the proposal

**The finding.** `FR-A`'s greedy rule needs the proposal for **one named
axis**. A legacy layer is a flex item of a parent whose main axis it cannot
see, and CSS's two greedy spellings are each tied to an axis role rather than
to width or height:

- `flexGrow` grows the **main** axis, whichever that is. Scratch **M2**: a box
  with a 20pt child and `flexGrow(1)` in a 300pt `Row` fills to 295; with
  `maxWidth(80)` as well it stops at 80 — exactly probe D4's number. In a
  `Column` the same `flexGrow` would consume the free **height**.
- `alignSelf(.stretch)` fills the **cross** axis. M2's column arm: the two
  stretched boxes' children sit at x = 0 where the unstretched one is centred
  at 140.
- `width: 100%` is axis-named but resolves against the containing block, not
  the proposal, and is **broken on a column's cross axis today**. Scratch
  **M4**: `Box { 20pt }.width(percent: 100)` as a `Column` child lays its child
  out at x ≈ **−14850** in a 300pt column — a box roughly 30000pt wide. In a
  `Row` the same spelling fills correctly (the sibling moves to x = 300), and
  capped at `maxWidth(80)` it reads 80.

**The ruling.** `maxWidth`/`maxHeight` lower to `maxSize` — a clamp — and
nothing else. `.frame(maxWidth: 80)` over a 20pt child reads **20** where
SwiftUI reads 80 (probe D4). Spec test 2.3 pins that arm **wrong on purpose**,
with SwiftUI's number in its doc comment, beside two arms that agree
(`minWidth` 40, probe D7; a 200pt child capped to 80, probe D14). Owner of the
fix: plan task 6, which owns the containers and can hand a layer its parent's
axis.

**Scope, narrowed by the critic round.** This ruling is about a **finite**
maximum. The infinite case is `FR-O`, which found an axis-safe lowering for the
both-axes spelling that this ruling's M2/M4 reasoning had missed: `flexGrow = 1`
fills the main axis and `alignSelf = .stretch` fills the cross axis, so setting
BOTH is correct whichever way the parent runs.

**What it costs if wrong.** `.frame(maxWidth: 80)` over a smaller child reports
the child's width rather than 80 on the legacy path. It is recorded as a
divergence rather than approximated, because M4 shows the approximation
available today (`width: 100%`) is catastrophic on one axis and invisible on
the other.

---

## FR-F — `width`/`height` stay as they are; the conversion is measured, not deferred on a hunch

**The claim being tested.** The plan records that a 2026-09-12 trial
(`4aaca40`, reverted twelve minutes later by `d0a04d3`) "broke list
virtualization, hit testing, and text measurement", and record §09 notes that
no test or measurement of that breakage is in the repo. This session re-ran the
conversion against today's `ModifiedElement` and measured each claim.

**What was measured.**

| claim | measurement | verdict |
|---|---|---|
| text measurement | scratch **L11**: `Column { Text("alpha bravo charlie delta").font(size: 12).frame(width: 60); marker }` puts the marker at y = **60** — the text re-wrapped to four 15pt lines — against y = 15 unframed and y = 60 for the `.width(60)` spelling. In a `Row`, framed and styled both read a 60pt advance against the bare text's 139, which is the probe's own 139.0 for the same string | **refuted**: a frame layer's width reaches a measured leaf |
| list virtualization | scratch **L12**: `ScrollView { List(40 rows).frame(width: 200) }` paints **40** row rects, the same as the unframed and `.width(200)` spellings | **refuted** |
| hit testing | scratch **L4**: `Box { … }.onClick {}.frame(width: 60, height: 40)` registers a **0×0** hitbox at (30, 20). The handler was declared *before* the frame, so it sits on the inner element, which is content-sized | **confirmed, and it is not a defect**: SwiftUI does the same. `.background(…).frame(…)` gives a background at the child's size, and MetalUI's own `.onClick` before `.frame` now behaves the same way |
| the type-level cost | the conversion **fails to compile** in `Sources/MetalUIDemo/main.swift` and in `EnvironmentTests`, `ModifierTests`, `AccessibilityTreeTests`, `AccessibilityEndToEndTests`, `AnimationTests` and `ProposalNodeIDTests` — helpers returning `Box<…>`, a `typealias Chrome`, and `ModifierTests`'s modifier table, which asserts that each modifier returns `Self` and writes a named `Style` field | **new**; this is the real blocker |
| the call-site count | `grep -rno`: **348** `.width(` and **338** `.height(` across `Sources/` and `Tests/` (one of each is the percentage overload), on **378** distinct lines; 20 and 21 of them are in `Sources/` | **new** |

**The ruling.** `StyledElement.width(_:)`/`height(_:)` keep writing the
element's own `Style`, are **not** deprecated in this task, and are documented
as engine-facing CSS-box modifiers whose SwiftUI spelling is `.frame(...)`.
Spec test 3.2 pins the difference (`.width` leaves the node count at 1;
`.frame(width:)` makes it 2).

**Reasoning.** Neither available move fits inside one verifiable milestone.
Converting is source-breaking in seven files today and changes what
`Box(decoration:).width(36)` paints (scratch **L8**: the decorated box becomes
18×14 inside a 36×36 layer instead of being 36×36 itself) — which would have to
be undone in the demo to keep the pixel comparison at zero, in the same change
as a second track is editing the same files. Deprecating with a `renamed:` hint
emits a warning at every one of 685 call sites against a hard 0-`warning:`
gate, so it is the same migration with a different trigger. The migration
belongs where the legacy engine is removed.

**The recipe, so task 7 does not re-derive it** (`FR-I` owns the schedule):
convert `width`/`height` to `frame(width:)`/`frame(height:)`; then, at each
call site where the receiver carries a `Decoration`, a handler, a
`hoverBackground`, a `focusBackground` or an `alignItems`/`justifyContent`,
move that modifier **after** the frame so it lands on the outer layer; then fix
the stored types (`typealias Chrome`, `-> Box<…>` helpers, `ModifierTests`'s
table, which must move to a `ModifiedElement`-shaped fixture); then re-take the
demo pixel comparison, which is the only thing that can see the reordering.

**What it costs if wrong.** Two sizing vocabularies stay live for another
milestone, and a reader can still write `.width(60)` believing it is SwiftUI's
frame. The documentation change and test 3.2 are what make that visible instead
of silent.

---

## FR-G — `minWidth`/`maxWidth`/`minHeight`/`maxHeight` stay, and one live caller is the reason

**The finding.** These four have **10** call sites in `Tests/` and **one live** call in `Sources/` (four more `Sources/` matches are inside comments), so the count argument of `FR-F` does not apply. The reason they
stay is the one caller: `Sources/MetalUIDemo/main.swift:881`'s
`.minHeight(Pixels(0))` on the demo's list, whose own comment says it "replaces
the automatic (content-based) minimum" — flex §4.5's automatic minimum size, on
that element.

**"A frame layer cannot express it" is now MEASURED, not asserted** (the critic
round; practices shape 14). On the demo's own shape — a `flexGrow(1)`,
`flexBasis(0)` box in a 200pt `Column` under an 80pt header, holding 400pt of
content — scratch **N7…N9b** read:

| arm | spelling | the inner content's height |
|---|---|---|
| N7 | `.minHeight(px(0))` on the growing box — the demo's own | **120** (shrunk into the 120pt left) |
| N8 | the same box with no `minHeight` — the control | **400** (the automatic minimum holds) |
| N9 | `.frame(minHeight: 0)` layer, `flexGrow`/`flexBasis` on the LAYER | **400** |
| N9b | `.frame(minHeight: 0)` layer, `flexGrow`/`flexBasis` on the INNER box | **400** |

Both plausible ports read N8's number, not N7's: the layer's `minSize` is the
*layer's* minimum and the element inside keeps its own automatic one. The
refusal stands, and it now rests on a measurement rather than on a confident
"cannot".

**The ruling.** The four stay, documented as CSS-box clamps; `.frame(minWidth:)`
is the SwiftUI path and is what new code should use. Spec test 3.2's second arm
pins the difference on exactly the demo's shape.

**Reasoning.** SwiftUI has no notion of an automatic minimum to cancel, so
there is nothing to align these with. They are engine API that happens to be
public, and the honest treatment is documentation plus a test, not a rename to
something that does a different thing.

**What it costs if wrong.** If the demo's `.minHeight(0)` were migrated to
`.frame(minHeight: 0)` without this ruling, the list's rows would regain their
content-based minimum and the demo's layout would move — a pixel change the
comparison would catch, after the fact.

---

## FR-H — percentage sizing stays, as an explicit MetalUI divergence with a test

**The inventory position.** `width(percent:)`, `height(percent:)` and
`flexBasis(percent:)` are CSS-derived, have no SwiftUI counterpart at all
(SwiftUI's nearest, `containerRelativeFrame`, resolves against a named
container, not a containing block), and have **one** test call site each and
none in `Sources/`.

**The ruling.** They stay, with a divergence test rather than a deprecation.
There is no `renamed:` target to point at, and deleting a working capability is
not this task's to do.

**What the test pins** (spec test 3.1), all measured this session:

- in a 300pt `Row`, `.width(percent: 50)` reads 150 — the control, and what CSS
  says;
- at the root it reads the offered width, not half of it — CLAUDE.md's
  divergence 4, which has had no test until now;
- **in a `Column`, `.width(percent: 100)` resolves against an unbounded cross
  axis**: scratch M4 places the child at x ≈ −14850 in a 300pt column, implying
  a box about 30000pt wide. The mechanism was **not investigated**. The test
  asserts a range rather than the exact float, and says in its doc comment that
  it is pinning a defect.

**What it costs if wrong.** The third arm is a live defect reachable from
public API. Pinning it is what stops a later reader from "fixing" the Row arm
and leaving the Column arm alone, or from believing percentages work.

---

## FR-I — no deprecation lands in this task, and the reason is the 0-warning gate

**The ruling.** This task adds exactly one `@available(*, deprecated, …)`
(`FR-J`'s no-argument `frame()`, which nothing calls). No existing API is
deprecated.

**Reasoning.** A `renamed:` deprecation is not a documentation act here: the
branch must pass `swift test` with **0 `warning:`**, so deprecating an API
means migrating every caller in the same change. For `width`/`height` that is
685 call sites (`FR-F`); for `min*`/`max*` it is 11 call sites but a behaviour
change at the one that matters (`FR-G`); for the percentage helpers there is no
rename target (`FR-H`). Task 7, which deletes the legacy engine, migrates and
deprecates in one move.

**What it costs if wrong.** A caller reading the API alphabetically still finds
eight CSS sizing modifiers with no deprecation marker. The mitigation is
documentation on each, plus the fact that `.frame` now sits beside them with
SwiftUI's exact signature.

---

## FR-J — `frame()` with no arguments is a deprecated no-op on both paths

**The finding.** `SA-N` item 9: `.frame()` and `.frame(alignment:)` compile
silently on MetalUI's proposal path because every parameter has a default.
SwiftUI rejects the first with `'frame()' is deprecated: Please pass one or
more parameters.` — a *separate zero-parameter overload* marked deprecated,
which the compiler prefers for a no-argument call.

**The ruling.** MetalUI adds the same overload to `ProposalElementGroup` **and**
`ElementGroup`, returning the receiver unchanged so it contributes no node, with
SwiftUI's own message. It is pinned by a **typecheck fixture**, not a runtime
test.

**Both halves of this ruling were corrected by the critic round, in opposite
directions.**

*The test mechanism — finding 2, applied.* The first draft made this a runtime
test calling `leaf.frame()` from ordinary test code. That call emits
`warning: 'frame()' is deprecated: Please pass one or more parameters.` into the
suite log, against the hard 0-`warning:` gate. The draft's stated reason for not
using a guard — "a deprecation *warning* cannot be a `canTypecheck` guard, since
the guard harness distinguishes compiling from not compiling" — **is false, and
this repo already refutes it**: `TypecheckResult.messages`
(`Tests/MetalUITestSupport/Typecheck.swift:101`) exposes the diagnostics, and
`EnvironmentCompileGuards.swift:47-48` (ruling `EV-N`) already asserts
`result.succeeded` AND `result.messages.contains("'Binding' is deprecated")` for
exactly this shape. So spec test 1.10 is a fixture asserting, on **both** paths,
that the call compiles, that `messages` carries the deprecation text, and that
the inferred type is the receiver's own. The fixture compiles in a subprocess,
so the warning never reaches the suite log.

*The two declarations — finding 11, REFUSED with a measurement.* The critic
observed that `ProposalElementGroup: ElementGroup`, so one `frame()` on
`ElementGroup` "already covers every proposal element", and asked for the second
declaration to be deleted. **Measured, it does not.** A skeleton with the real
shape — two protocols, one refining the other, the two `frame(width:…)` and
`frame(minWidth:…)` overloads on each, one type conforming to the refined one —
compiled with `-swift-version 6` under Apple Swift 6.4:

| `frame()` declared on | `Leaf().frame()` infers | deprecation warning |
|---|---|---|
| `ElementGroup` only | **`ModifiedContent<Leaf, FrameModifier>`** | **none** |
| both protocols | `Leaf` | yes, on both paths |

With one declaration the refined protocol's own `frame(width:height:alignment:)`
— every parameter defaulted — is more specialized and wins, so a no-argument
call on a proposal element silently builds a centring, size-nothing layer and
says nothing. That is `SA-N` item 9 **exactly**, the bug this ruling exists to
fix, surviving on the one path that matters. The second declaration is
load-bearing, not redundant, and the fixture asserts the inferred type on both
paths so that deleting either declaration reddens it.

**`.frame(alignment:)` is deliberately left alone.** SwiftUI accepts it too;
an alignment with nothing to align is a no-op in both.

**What it costs if wrong.** Nothing calls it; the cost of the ruling is one
overload per path. The cost of *not* having it — or of having only one, which
is the same thing on the path that matters — is that `.frame()` keeps compiling
into a real, centring, size-nothing layer that a reader will not expect.

---

## FR-K — one alignment type, and it keeps its `Proposal` name for now

**The ruling.** The legacy frame takes `ProposalAlignment`
(`LayoutTree.swift:1152`), the nine-case type the proposal path already uses,
rather than declaring a second nine-case enum in `MetalUI`.

**Reasoning.** The near-duplicate is what this milestone exists to remove; and
`horizontalFactor`/`verticalFactor` are already public for exactly this use
(`SA-F`). The name is wrong for a legacy call site, and renaming it to
`Alignment` is a deliberate **deferral**: `Alignment` is a name the parallel
paint-modifier track may also want, a typealias would give the codebase two
spellings for one type, and the rename is free once the legacy path is gone.
Owner: plan task 7.

**What it costs if wrong.** A reader of `Box.frame(width:height:alignment:)`
sees a type named for the other engine. That is a documentation cost, paid to
avoid a merge collision and a duplicate type.

---

## FR-L — a frame never answers a negative size, and a declared negative minimum or maximum is floored at 0

**Where it came from.** The critic round's finding 12: the design replaced
`min ?? 0` with `min ?? -.infinity` in `framedSize`, removing the only floor on
a frame's answer, and admitted "the probe has no negative size". `ProposalLayout`
is a public protocol and `ProposedSize` is publicly constructible, so an outside
layout can propose a negative width; ruling `SA-J`'s registration validation
accepts a negative `minWidth`/`minHeight` (it rejects only NaN and +infinity).
A negative answer would reach `LayoutRect`, `Bounds` and the renderer.

**The finding.** `docs/probes/swiftui-frame-negative-sizes.swift`, arms H1–H10,
run both ways with an empty `diff`:

| arm | frame | proposal | SwiftUI answers | child proposed |
|---|---|---|---|---|
| H1 | none (bare 20pt child) | −30 | 20 | −30 |
| H2 | `maxWidth: 80` | −30 | **20** | −30 |
| H3 | `minWidth: −50` | 100 | 20 | 100 |
| H4 | `minWidth: −50, maxWidth: 80` | −30 | **0** | **0** |
| H5 | `width: 60` | −30 | 60 | 60 |
| H6 | `minWidth: −50, maxWidth: −10` | 100 | **0** | **0** |
| H9 | `minWidth: −50` | nil | 20 | nil |
| H10 | `width: −60` | 100 | **0** | 0 |

**SwiftUI never answers a negative size at any input in the file.** Every
*declared* dimension is floored at 0 before use — H10's fixed −60 answers 0,
H6's max −10 answers 0 and proposes 0 to its child, and H4's min −50 turns a
−30 proposal into a child proposal of **0.0** where H2, which declares no
minimum, forwards **−30.0** unchanged. The floor is on the declared min/max,
not on the proposal.

Compiled (and only compiled — ruling `SA-O`), SwiftUI printed **exactly two**
diagnostics, `[SwiftUI] Invalid frame dimension (negative or non-finite).`, on
H6 and H10. A negative *minimum* is not diagnosed and neither is a negative
*proposal*.

**The ruling.** `framedSize` and `framedProposal` floor the **declared**
minimum and maximum at 0:

```swift
let lo = Swift.max(0, min ?? 0)                    // framedSize
let hi = max.map { Swift.max(0, $0) } ?? .infinity
```

and `framedProposal` uses `min.map { Swift.max(0, $0) } ?? -.infinity` for its
lower bound, so an **absent** minimum still forwards a negative proposal
unchanged (H2) while a declared one floors it (H4). The result is faithful on
all 71 arms of the two probes. The design's `min ?? -.infinity` is withdrawn:
it was argued from "`SA-J` accepts a negative minimum, so it must not floor at
0", and the probe shows SwiftUI accepts one too and floors it anyway.

**Mutations, measured.** With `FR-A`, `FR-L` and `FR-M` applied together to
`LayoutTree.swift` and the whole suite run under
`swift test --build-system native --no-parallel`, **exactly two tests redden**
and no other:

- `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum` (80×60 against
  the pinned 40×70);
- `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes` (70×60 against the
  pinned 70×20).

`NativeValidationAcceptanceTests`'
`negativeAndNegativeInfiniteFrameMinimumsAndAnInfiniteMaximumAreAccepted` — the
one existing test that exercises a negative minimum, through `#expect(
processExitsWith: .success)` — **stays green**: its four arms read 20, 20, 100
and 20 under the floored bounds, as before. That was checked by running, not by
reading.

**What it costs if wrong.** If the floor is wrong in SwiftUI's direction, a
negative minimum that a caller meant as "no minimum" starts clamping at 0
instead of at −∞ — unobservable, because every base is non-negative. If it is
wrong in the other direction, a negative size reaches the renderer.

---

## FR-M — an absent minimum is not `minWidth: 0`, and the kernel rule was wrong because of it

**Where it came from.** Nobody raised it. It fell out of building `FR-L`'s
probe: adding a positive control at a proposal *below* the child's own answer
showed the design's own greedy rule reading 10 where SwiftUI reads 20.

**The finding.** With a maximum given and a concrete proposal, the base is the
proposal **only when a minimum is also declared**. With no minimum, it is
`max(proposal, child's own answer)`.

| arm | frame | proposal | child | SwiftUI |
|---|---|---|---|---|
| H8 | `maxWidth: 80` | 10 | 20 | **20** |
| H14 | `minWidth: 0, maxWidth: 80` | 10 | 20 | **10** |
| H7 | `maxWidth: 80` | 0 | 20 | 20 |
| H2 | `maxWidth: 80` | −30 | 20 | 20 |
| H11 | `minWidth: 5, maxWidth: 80` | 10 | 20 | 10 |
| H13 | `minWidth: 5, maxWidth: 80` | 10 | **200** | 10 |
| H15 | `maxWidth: 80` | 10 | **200** | 80 |
| H16 | `maxWidth: .infinity` | 100 | **200** | **200** |
| H17 | `maxWidth: .infinity, maxHeight: .infinity` | 100 | 200×160 | 200×160 |

**H8 against H14 is the decisive pair**: identical numbers, differing only in
whether a zero minimum is written, answering 20 and 10.

**Why 54 arms could not see it.** Every arm in the main probe that declares a
maximum proposes MORE than its child answers — D4 100/20, D5 30/20, D10 100/20,
D13 100/200 with a minimum. On all of them `proposal` and `max(proposal, child)`
are the same number. The design's rule was fitted to a sample that could not
distinguish the two, which is practices shape 15 read backwards: the arms
*agreed* when they needed to be made to disagree.

**The ruling.** `framedSize`'s greedy branch reads

```swift
if max != nil, let proposal, proposal.isFinite {
    base = min == nil ? Swift.max(proposal, child) : proposal
}
```

and the `min == nil` test is on the **presence** of the minimum, never on its
value — H14 is the arm that makes that a requirement rather than a style.

**It also fixes a live bug.** Today's `framedSize` grows only at
`max == .infinity` and then returns `Swift.max(min ?? 0, proposal)`, so
`.frame(maxWidth: .infinity)` over a child *bigger* than the proposal answers
the proposal where SwiftUI answers the child (H16: 100 against 200). The demo's
proposal preview ends in exactly that spelling
(`main.swift:1032`), so lane 4's pixel comparison may legitimately
move — see the spec's lane 4 item 4, which no longer treats a non-zero count as
automatically a defect.

**What it costs if wrong.** A flexible frame in a narrow parent reports the
parent's width instead of its content's, so content that should overflow gets
clipped or compressed instead — the failure is a layout that looks plausible
and is silently smaller than its contents.

---

## FR-N — the legacy frame SQUEEZES an oversized child on the layer's main axis

**Where it came from.** The critic round's finding 8: the design claimed the
silent divergence set was empty while its own record §14 carried scratch **L3**
showing something neither `FR-D` nor `FR-E` covers.

**The finding**, re-measured this round as scratch **N5**/**N6**:
`.frame(width: 60, height: 40)` over a child that declares 200×160 places that
child at **(0, 20) 60×160** — its **width squeezed to the frame**, its height
overflowing. SwiftUI's A5 keeps 200×160 and overflows both ways, at (−70, −60)
centred. **N6** repeats it with `flexShrink = 0` on the layer and reads the
same numbers, which separates the two candidate mechanisms: the layer did not
shrink, the *child* was shrunk as a flex item of it.

**Why one node cannot fix it.** The frame layer is a flex container. On its
main axis an over-large item shrinks (`flexShrink` defaults to 1 and the layer
cannot reach into its child's `Style` to change that); on its cross axis it
overflows. Flipping `flexDirection` swaps which axis suffers, it does not save
both. A two-node lowering does not help either, because the inner node is the
caller's own element.

**The ruling.** Recorded as a divergence and **pinned wrong on purpose** by spec
test 2.8, with SwiftUI's own numbers in the doc comment. Owner of the fix: plan
task 6, which owns the containers and could give a frame layer a child whose
shrink factor it controls.

**What it costs if wrong.** A ported view whose content overflows its frame
horizontally is compressed rather than clipped. It is the least visible of the
three silent divergences, and it is the one a reader is most likely to meet,
because "content bigger than its frame" is ordinary.

---

## FR-O — an infinite maximum fills when BOTH axes are infinite, and is inert when only one is

**Where it came from.** The critic round's finding 7: lowering an infinite
maximum to nothing makes `.frame(maxWidth: .infinity)` — the commonest SwiftUI
idiom there is — an API that compiles, costs a node, an identity level and a
`$anim` slot (divergence 18's `2n + 7`), and does nothing; and it is a
*regression in diagnosability*, because today that spelling does not compile on
a legacy element at all. The finding asked for a trap, or a stated reason plus a
test plus a declared-but-inert row.

**What the measurement found instead.** `flexGrow = 1` fills the parent's
**main** axis; `alignSelf = .stretch` fills its **cross** axis. Setting BOTH is
correct whichever way the parent runs — the same "only when both are given"
shape that `FR-P` uses for the fixed axes. Scratch **N14**, a 20×20 mark inside
the layer, in a 300×200 frame:

| parent | lowering | the mark's origin |
|---|---|---|
| `Row` | nothing | (0, 90) — the layer is 20 wide |
| `Row` | `flexGrow 1` + `alignSelf .stretch` | **(140, 90)** — the layer fills 300×200 |
| `Column` | nothing | (140, 0) — the layer is 20 tall |
| `Column` | `flexGrow 1` + `alignSelf .stretch` | **(140, 90)** — fills |

Scratch **N15** shows why it must not be done for a single axis: with a sibling
present, the same lowering in a `Column` pushes the sibling from y = 20 to
**y = 195** — the layer consumed the whole height, which a caller who wrote only
`maxWidth: .infinity` never asked for.

**The ruling.**

- `.frame(maxWidth: .infinity, maxHeight: .infinity)` lowers to `flexGrow = 1`
  and `alignSelf = .stretch`. It **works**, and it is the demo's own spelling.
- A single infinite maximum lowers to nothing: the layer is present, costs a
  node, and does not fill. Pinned by spec test 2.9, which asserts **both** arms —
  the filling one and the inert one — and carries the divergence in its doc
  comment. It gains a row in CLAUDE.md's declared-but-inert table as an
  **integration obligation** (this track may not edit that file).
- It does **not** trap, where `FR-D`'s ideal does. The two are treated
  differently on purpose and the reason is not comfort: `idealWidth` has no CSS
  spelling at all and no path to one, so a trap is the terminal answer; a
  single-axis infinite maximum has a known lowering that is blocked only by the
  layer not knowing its parent's axis, which plan task 6 removes. Trapping the
  commonest SwiftUI idiom would also make every ported view crash on a spelling
  that is about to work.

**What it costs if wrong.** If the both-axes fill is wrong, a full-bleed panel
stops being full-bleed — loud and immediately visible. If the single-axis
inertness is the wrong call, a caller gets a node that does nothing, which the
declared-but-inert row and test 2.9 are what make findable.

---

## FR-P — a fixed axis is pinned by an axis-named `minSize`, not by `flexShrink = 0`

**Where it came from.** The critic round's finding 6: `Style.flexShrink` is one
scalar governing the parent's **main** axis (`Sources/MetalUILayout/Style.swift:132`),
so `.frame(width: 200)` inside a `Column` would pin the layer's **height** and
`.frame(height: 40)` inside a `Row` would pin its **width** — the exact
axis-role confusion `FR-E` uses to refuse greedy maximums. The design's evidence
(scratch L9/L14) measured only a `Row` with a fixed width.

**The finding.** Scratch **N11**, the cross-axis arm the finding asked for: a
frame declaring only `height: 40`, in an over-constrained 300pt `Row`, around a
wrapping `Text`, with a 200pt sibling whose x reads the layer's width:

| lowering | the sibling's x |
|---|---|
| nothing | 154 — the layer is 154 wide, the text wrapped |
| `flexShrink = 0` | **210** — the layer is 210 wide, the text did NOT wrap |
| `minSize.height = 40` | 154 — identical to nothing |

`flexShrink = 0` demonstrably pins a **width the caller never declared**.

**And the alternative is equivalent where it should be.** Scratch **N10**, L9's
own shape (two `.frame(width: 200, height: 20)` layers in a 300pt `Row`):

| lowering | the marks' x |
|---|---|
| nothing | 65 / 215 — each layer shrank to 150 |
| `flexShrink = 0` | 90 / 290 — 200 each |
| `minSize.width = 200` | **90 / 290** — 200 each, identical |

Scratch **N13** confirms it does not disturb chained frames: `.frame(100)`
inside `.frame(50)` still puts the leaf at x = 15 and the reverse at x = 40 —
the probe's E1/E2 — with and without the pin. (N13 also records that M1 never
*discriminated*: a 100pt inner overflowing a 50pt outer and a 100pt inner
shrunk to 50 both centre a 20pt leaf at 15.)

**The ruling.** A declared width lowers to `size.width` **and**
`minSize.width`; a declared height to `size.height` and `minSize.height`.
Axis-named, needing no knowledge of the parent's main axis, and equivalent to
`flexShrink = 0` on the axis where that was right. `flexGrow = 0` is **dropped**
from the lowering: it is already `Style`'s default.

**The blast radius, measured rather than predicted.** Both candidate lowerings
were applied in turn to the live `ElementGroup.frame(width:height:)` and the
whole suite run: **`Test run with 1231 tests in 1 suite passed` both times** —
1226 plus 5 scratch tests, no existing test moved, across the 52 `.frame(` call
sites in ten test files. So the spec's "one oracle edit" obligation is
**refuted as a redness claim**: `ModifierCompositionProofTests`'s hand-built
`frameStyle(width:height:)` (line 503) does **not** have to change to keep the
suite green. It must change anyway, and the spec now says why: it is a
hand-spelled duplicate of the lowering, and the suite has just demonstrated it
will not tell you when it drifts.

**What it costs if wrong.** A fixed frame shrinks below its declared size in an
over-constrained parent, which is L9's 150-instead-of-200 and what the demo's
sidebar already does for a different reason (SZ-L).

---

## FR-Q — the `rem` inventory, so the task's clause is answered rather than missed

**Where it came from.** The critic round's finding 13: the task brief says
"Percentage and rem helpers: decide per the inventory", `FR-H` covers
percentages, and the words `rem`/`Rems` appeared nowhere in the spec, decisions
or record.

**The inventory, taken this round.**

- There is **no `width(rem:)` or `height(rem:)`**, and no rem sizing modifier of
  any kind. `Box.swift`'s `MARK: Size` section offers `Pixels` and `percent:`
  overloads only (lines 593–623).
- `Length.rems` (`Sources/MetalUICore/Units.swift:51`) is nevertheless publicly
  reachable, through the three `Edges<Length>` modifiers — `padding(_ edges:)`
  (`Box.swift:646`), `margin(_ edges:)` (659) and `borderWidth(_ edges:)` (676).
  `gap` takes `Pixels` only.
- It resolves in `Sources/MetalUILayout/Resolve.swift:46` against
  `Frame.rootFontSize` — a **single per-frame** root font size, `let`, default
  16 (`Frame.swift:137`, `1383`), not a per-element font size.
- It is already pinned: `Tests/MetalUILayoutTests/ResolveTests.swift:7,16`
  assert `resolveLength(.rems(Rems(2)), against: 400, rootFontSize: 16) == 32`
  and that a rem resolves with no containing block.
- `AnimatedStyle.swift:515` gives it interpolation tag 1, so a `px → rem`
  transition snaps (CLAUDE.md's animation snap list) like every other
  cross-case transition.

**The ruling.** **Keep, unchanged, and out of this task's source changes.**
There is no rem *sizing* helper for a frame task to deprecate or convert, and
the `Length` case that exists is a box-model unit, not a frame parameter: it
belongs to whichever task takes the box model, not to `.frame(...)`. It is a
MetalUI divergence (SwiftUI has no rem and no root font size) that is already
covered by a test, so `FR-H`'s "keep as an explicit divergence with a test"
disposition applies to it verbatim and needs no new test here.

**What it costs if wrong.** Nothing moves; the cost of the ruling is the
paragraph. The cost of *not* writing it is that a later reader cannot tell
whether the brief's rem clause was answered or forgotten — which is exactly what
the critic could not tell.

---

## Carried into this task, and where each went

| carried item | source | where it landed |
|---|---|---|
| A finite `maxWidth` frame grows | `SA-N` item 1 | `FR-A`, fixed, as amended by `FR-M` |
| `.frame()` compiles silently | `SA-N` item 9 | `FR-J`, fixed — and finding 11's proposed simplification would have reinstated it |
| "whether a finite `maxWidth` frame grows" | record §09 §2, open | `FR-A`, answered: it does |
| a nil axis, a smaller frame, a stretching `Box` parent (EP-8) and a shrinking row (SZ-L), excluded from `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes` | `MC-Q` finding 7 | the shrinking row is `FR-P`'s `minSize` pin (spec test 2.2); the smaller frame is probe A5/B9 and spec tests 2.5 and 2.8 (`FR-N`); **the nil axis and the stretching parent are not covered and stay open** |
| "Port `width`/`height`/min/max as layers" | `MC-L` | `FR-F`, `FR-G`, `FR-I`: refused with evidence, owner reassigned to task 7 |
| `Component` distribution and B-7 | `MC-L` | untouched; plan task 5 |

## The critic round's sixteen findings, and where each went

| # | finding, in one line | disposition |
|---|---|---|
| 1 | lane 1 reddens `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes`, unlisted | **applied**; re-fixtured to 70×60 with its doc comment rewritten, and the sweep re-taken **by running the patched kernel over the whole suite** — exactly two tests redden, both now listed (`FR-L`) |
| 2 | test 1.7 breaks the 0-`warning:` gate; `FR-J`'s reason is refuted by `EV-N` | **applied**; 1.10 is a typecheck fixture asserting `succeeded`, `messages` and the inferred type on both paths (`FR-J`) |
| 3 | the expected test counts are internally inconsistent | **applied**; every count re-derived from the test tables, 1226 → 1245 |
| 4 | the overload skeleton must re-check `ProposalLayoutCompileGuards`' exact diagnostic | **applied, and measured now**: with the doubled overload set the diagnostic is still `extra argument 'minWidth' in call`, so the guard needs no re-fixture. The skeleton stays lane 2's first step |
| 5 | the overload fixture is too narrow | **applied**; it asserts `.frame(width:)`, `.frame(minWidth:idealWidth:maxWidth:)`, `.frame(alignment:)` and `.frame()` on a proposal element, and 2.4 gains a run-time control that `.frame(idealWidth:)` there does not trap |
| 6 | `flexShrink = 0` is axis-blind, `flexGrow = 0` is a no-op, the blast radius is unmeasured | **applied, with a better answer**: an axis-named `minSize` (`FR-P`), `flexGrow = 0` dropped, both candidates run over the whole suite (1231/1231, no oracle edit needed) |
| 7 | `.frame(maxWidth: .infinity)` becomes an API that compiles and does nothing | **applied, with a better answer**: both-axes infinite fills; single-axis is inert with a test and a CLAUDE.md row (`FR-O`) |
| 8 | scratch L3 is a third silent divergence with no ruling | **applied**; `FR-N`, re-measured as N5/N6, pinned wrong on purpose by test 2.8, and `FR-C`'s "the silent set is meant to be empty" withdrawn and replaced by the enumerated three |
| 9 | `FR-G`'s load-bearing "cannot" is unmeasured (shape 14) | **applied**; N7…N9b measured on the demo's own shape — 120 / 400 / 400 / 400 — and quoted in `FR-G` |
| 10 | `public struct FrameSpec` with no public member is itself declared-but-inert | **applied**; it is `internal`, and the spec notes there is nothing to narrow so no guard is owed (shape 16) |
| 11 | `frame()` is declared twice for one behaviour | **REFUSED, with a measurement**: with one declaration `Leaf().frame()` infers `ModifiedContent` and emits no deprecation, reinstating `SA-N` item 9 (`FR-J`) |
| 12 | `min ?? -.infinity` removes the only floor on a frame's answer | **applied, and the probe went further**: SwiftUI never answers a negative size and floors declared negatives at 0 (`FR-L`) |
| 13 | the brief's "rem helpers" clause is silently dropped | **applied**; `FR-Q` records the inventory and the disposition |
| 14 | the one shared-file edit is a deletion at the parallel track's append point | **applied**; it becomes an in-place forwarding replacement landed as lane 1's **first, isolated** commit, and lane 4 gains `swift package clean` |
| 15 | lower alignment by switching on the case, not on the factor | **applied** (`FR-C`) |
| 16 | test 2.7's mutation does not isolate test 2.7 | **applied**; the mutation becomes the frame layer's own `size.height`, with the reddened tests named from the run |

Two findings nobody raised came out of re-running the probes for finding 12:
**`FR-M`** (an absent minimum is not `minWidth: 0`, and the design's own kernel
rule was wrong on the arms the 54-arm probe could not distinguish) and the
live-kernel bug it exposes at `maxWidth: .infinity` over an oversized child
(probe H16).
