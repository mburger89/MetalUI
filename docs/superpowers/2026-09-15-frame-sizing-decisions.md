# Frame and sizing decisions (plan task 4)

Rulings for `docs/superpowers/specs/2026-09-15-frame-sizing-design.md`, on
`feat/frame-sizing` from `c4b5853`. Ids are **lettered**, `FR-A`…; next unused
is **`FR-L`**. A bare `FR-3` is a typo, not a citation.

**Status, 2026-09-15:** design only. No source file has changed. The probe
`docs/probes/swiftui-frame-semantics.swift` is committed and re-runnable; the
scratch tests it is compared against were run with `--filter` and deleted
(`git status --short` empty afterwards). The suite at `c4b5853` reads
`Test run with 1226 tests in 1 suite passed`, 0 `error:`, 0 `warning:`, 97
goldens, 61 typecheck guards.

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
the rule above verbatim; `framedProposal` already implements the child
proposal exactly and does not move. This closes record §09's open question
("whether a finite `maxWidth` frame grows — it does") and `SA-N` item 1, whose
owner is named as this task.

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
- **`flexShrink = 0`, `flexGrow = 0` on a fixed axis.** Scratch **L9**: two
  `.frame(width: 200, height: 20)` layers in a 300pt `Row` today place their
  children at x = 75 and 225 — the layers shrank to 150 each. **L14**, the same
  shape with `.flexShrink(0)` applied to each layer, places them at 100 and 300
  — 200 each, no shrink. SwiftUI has no shrinking: a fixed frame answers its
  fixed value whatever it is proposed (probe A2, A5, A6).

**Reasoning for one lowering function rather than a second node kind.** The
legacy engine cannot accept a native frame node (`LayoutTree.newNativeFrame`
requires a native child, `newNode` refuses a native one — ruling `SA-G`), so
the legacy frame must remain CSS. Keeping the approximation in one function,
with `FrameSpec` as its input, is what makes "one semantic path" true of the
*surface* even though two engines are still live: both paths take the same
parameters, the same alignment vocabulary and the same documented rules, and
the difference between them is one table a reader can find.

**What it costs if wrong.** A caller who ports a `.frame` from the proposal
path to the legacy path gets a silently different layout. The divergences that
remain are `FR-D` (traps) and `FR-E` (pinned wrong on purpose), so the silent
set is meant to be empty.

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

**What it costs if wrong.** `.frame(maxWidth: .infinity)` — the commonest
SwiftUI idiom there is — does not fill on the legacy path. It is recorded as a
divergence rather than approximated, because M4 shows the approximation
available today is catastrophic on one axis and invisible on the other.

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
that element. A frame layer cannot express it: the layer's `minSize` is the
*layer's* minimum, and the element inside keeps its automatic one.

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

**The ruling.** MetalUI adds the same overload to `ProposalElementGroup` and
`ElementGroup`, returning the receiver unchanged so it contributes no node, with
SwiftUI's own message. Pinned by spec test 1.7, which reads the inferred type
and the node count — a deprecation *warning* cannot be a `canTypecheck` guard,
since the guard harness distinguishes compiling from not compiling.

**`.frame(alignment:)` is deliberately left alone.** SwiftUI accepts it too;
an alignment with nothing to align is a no-op in both.

**What it costs if wrong.** Nothing calls it; the cost of the ruling is one
overload per path. The cost of *not* having it is that `.frame()` keeps
compiling into a real, centring, size-nothing layer that a reader will not
expect.

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

## Carried into this task, and where each went

| carried item | source | where it landed |
|---|---|---|
| A finite `maxWidth` frame grows | `SA-N` item 1 | `FR-A`, fixed |
| `.frame()` compiles silently | `SA-N` item 9 | `FR-J`, fixed |
| "whether a finite `maxWidth` frame grows" | record §09 §2, open | `FR-A`, answered: it does |
| a nil axis, a smaller frame, a stretching `Box` parent (EP-8) and a shrinking row (SZ-L), excluded from `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes` | `MC-Q` finding 7 | the shrinking row is `FR-C`'s `flexShrink = 0` (spec test 2.2); the smaller frame is probe A5/B9 and spec test 2.5; **the nil axis and the stretching parent are not covered and stay open** |
| "Port `width`/`height`/min/max as layers" | `MC-L` | `FR-F`, `FR-G`, `FR-I`: refused with evidence, owner reassigned to task 7 |
| `Component` distribution and B-7 | `MC-L` | untouched; plan task 5 |
