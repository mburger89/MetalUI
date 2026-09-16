# Containers decisions (plan task 6)

Rulings for `docs/superpowers/specs/2026-09-16-containers-design.md`, on
`feat/containers` from `9e439cb`. Ids are **lettered**, `CN-A`…; next unused is
**`CN-T`**. A bare `CN-3` is a typo, not a citation.

**Status, 2026-09-16, design only.** No file under `Sources/` or `Tests/`
changed in a commit. Every source patch cited below as a *prototype* was
applied in this worktree, built, run and restored with `git checkout Sources/`
(or `cp` from a scratch copy), with `git status --short` showing only the
design's own docs afterwards; the scratch test files the prototypes used were
deleted. Baseline at `9e439cb` plus the probe commits: `swift build
--build-system native --build-tests`, then `swift test --build-system native
--no-parallel` → `Test run with 1303 tests in 1 suite passed after 39.247
seconds`, 0 `error:`, no `warning:` besides SwiftPM's own deprecation notice.
One committed, re-runnable probe: `docs/probes/swiftui-stack-algorithms.swift`
(run under `/usr/bin/swift`, Apple Swift 6.4, macOS 27.0; exit 0; run twice per
revision, byte-identical output, recorded in its header).

Arm names below (G1, SP19, A10, SC2, R1, Q1, AR1, …) are that probe's.

---

## CN-A — the migration shape: parity on the proposal path first; no legacy container is lowered in this task

**The question.** The task text says "port stack, overlay and spacer
algorithms directly to the new proposal system" and "audit `Row`, `Column`,
`Stack`, `Box`, `Spacer`, `ScrollView`, `List`, `Deferred`". Three shapes were
available:

1. convert the legacy spellings (`Row`, `Column`, `Stack`, …) to register
   native nodes;
2. port the algorithms into the kernel and lower the legacy containers onto
   them;
3. make the proposal path's containers SwiftUI-correct and complete, keep the
   legacy containers on the CSS engine unchanged except where a probe-backed
   fix is local, and leave the root-by-root switch to task 7.

**What was measured.**

- **`SA-G` makes 1 and 2 a whole-tree conversion.** A native node under a legacy
  node traps, and so does a legacy node under a native registrar. A legacy
  `Row` over one legacy `Text` cannot be native unless the `Text` is; a
  `Row` over a `ModifiedElement` layer cannot be native unless the layer is.
- **What the default demo root depends on** (non-comment lines of
  `Sources/MetalUIDemo/main.swift`): `.flexGrow` 10, `.alignItems` 11,
  `.height(` 13, `.width(` 10, `.justifyContent` 3, `.alignSelf` 2,
  `.flexBasis` 1, `.minHeight` 1, `.position` 1, `.inset` 1, plus `List`,
  `ScrollView`, `Deferred`, `Stack`, `Row`, `Column` on 21 lines. None of
  `flexGrow`/`flexBasis`/`alignSelf`/`minHeight(0)`/`position`/`inset` has a
  proposal-path lowering, and `List` and `Deferred` have no proposal
  counterpart at all.
- **What the legacy containers carry in `Tests/`** (occurrences / files):
  `Box(` 646/53, `Box {` 74/18, `ScrollView(` 77/21, `Row(` 71/14,
  `List(` 56/15, `Deferred {` 16/9. The proposal containers: `HStack` 69/17,
  `VStack` 20/5, `ZStack` 33/6, `ProposalScrollView` 17/3.
- **The earlier wholesale conversion** (`4aaca40`, reverted by `d0a04d3`) broke
  `List` virtualization, hit testing and text measurement; `FR-F` refuted two of
  the three by measurement, but what it did establish — the type-level blast
  radius and the 0-warning gate — is unchanged.
- **What shape 3 costs, prototyped in full** (every kernel change in `CN-B`…`CN-G`,
  `CN-J` and the scroll cross axis of `CN-M`, applied together, then
  reverted): **27 existing tests change** (listed in the spec, "Existing tests
  that change"), all on the proposal path; the legacy demo renders
  **0 differing pixels** in all eight legacy images and a 560×560 legacy image;
  the proposal preview differs by **1 109 pixels** at 1024×1024 (two rects,
  both explained by probe arms) and by **64 945 pixels** at 560×560 (13 of 16
  rects: fixed-size content now overflows instead of being squeezed, which is
  G9/X13's answer). The spec's "Measured costs" section carries the rect-by-rect table.

**The ruling.** Shape 3. This task makes `HStack`, `VStack`, `ZStack`,
`Spacer`, `.overlay`/`.background` content and `ProposalScrollView` behave as
the probe says, and gives the legacy frame layer the one SwiftUI answer a
single CSS node can express (`CN-N`). **No legacy container is lowered onto the
kernel, and no legacy default changes** (`CN-P`). The switch of the default demo
root and of the legacy spellings is task 7's, root by root, and its
prerequisites are named in the spec's deferral table: proposal registrations for
`Text` with decorations and handlers, `Box` as a leaf, `ModifiedElement` layers
(the `ModifiedContent` unification), a windowed proposal `List` with its
`ScrollContext` and row identity, a proposal `Deferred`, and accessibility
records and the disabled gate on proposal elements.

**Reasoning.** Shape 1 or 2 inside five lanes would either stop half-way — a
tree whose root is native but whose leaves are not traps — or reintroduce an
adapter, which `SA-G` forbids. Shape 3 is the only one whose every lane ends
green, and it is the prerequisite of the other two: task 7 cannot switch a root
onto algorithms that are not yet SwiftUI's.

**Identity.** Nothing in this task changes an element id, a `$state`/`$focus`/
`$anim` path, a `List` row name or vanishing-`if` adoption: no lane adds or
removes an element level, and the two new kernel nodes (`CN-K`'s implicit
`ZStack`) are layout nodes with no element identity.

**What it costs if wrong.** Two layout authorities stay live for another task,
and the legacy containers keep their CSS answers (spacing 0, flex-shrink
compression, fit-content `Stack` children), recorded as divergences (`CN-P`).
If task 7 finds a root that cannot switch because of something this task could
have ported, that is a missed item, not a broken tree.

---

## CN-B — the linear stack distributes the way SwiftUI's does

**The finding** (arms G, X, SP8–SP10, Q3). At a finite main-axis proposal:

1. spacing comes off first (G12);
2. children are grouped by layout priority, highest first;
3. each group is offered the remaining length **minus the minimum of every
   lower-priority child** — the child's main-axis answer at main 0 (G2: 70 not
   80; G14; X5 92);
4. within a group, children are served **least flexible first**, where
   flexibility is the answer at main ∞ minus the answer at main 0, ties in
   declaration order (G1 vs G1r, X1, X3, X4);
5. each is proposed `max(0, remaining / children left in the group)` (G13's
   last child gets 0), and `remaining` shrinks by what it **answered**;
6. the stack answers the sum of the answers plus spacing — overflow included
   (G9 160 at 100, G13 75 at 60, X13 160) and shrink-wrap included (G10 40 at
   300).

At a nil or infinite main proposal every child is offered that value (G7, G8).
The main axis is measured at the allocations, so the reported cross size is
the children's answers at their allocations (Q3: 30, not the 600 an
unallocated measurement gives).

**Today's kernel** gives equal shares only when a stack overflows and has no
spacer, never expands a non-spacer, never compresses a stack with a spacer,
answers `min(natural, proposal)`, and measures at a nil main axis but places
at allocations. Every one of those is contradicted by an arm above.

**The ruling.** Port the algorithm as stated. Two implementation choices that
are not SwiftUI's and are not observable in any allocation:

- **Eager probing.** SwiftUI evaluates flexibility lazily and stops at a
  flexibility of 0 (G3's second child gets one call). The kernel probes every
  member of a group of two or more at main 0 and main ∞, and probes a
  lower-priority child only at main 0; a group of one is not probed. Under
  `SA-H`'s purity assumption the allocations are identical to a stable sort.
- **The distribution is one function used by both measurement and placement**,
  so what a stack reports and where it places cannot disagree (CLAUDE.md's
  "measures at nil, places at allocations" item).

**Measured cost** (prototype, before `CN-F` and `CN-G`):
`aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` reads 47 measure
calls, 52 hits, 66 misses against today's 16/27/25. On alternating nested
H/V stacks of two leaves and a spacer per level, depth 1–7 (4 to 382 nodes),
leaf calls go from 1 per leaf to 9 per leaf (6, 36, 72, …, 1152 against 2, 4,
8, …, 128), **linear in node count** at every depth measured; the same shape
with per-leaf distinct clamps read the same counts. The lane re-derives the
branching tree's literals by hand before running (`SA-M`).

**What it costs if wrong.** Every proposal-path stack allocates differently
from SwiftUI on the trees the tests do not build. The probe arms are
three-child at most; the lane's tests add a three-group, three-flexibility
tree (G13, G14) so a two-child special case cannot pass.

---

## CN-C — `Spacer`: default minimum 8, priority −∞, zero on its stack's cross axis, infinite at an infinite proposal

**The finding.**

- `Spacer()`'s nil `minLength` is **8** (SP1 48; SP6; `SA-N` item 2's P5).
- A spacer has **priority −∞** unless given one (SP8's first child is offered
  (200 − 8) / 2 = 96; X5; X6 gives a `.layoutPriority(1)` spacer all 100).
  `SA-D`'s contract probe already read −∞ through a custom layout's proxy (E2).
- Inside a linear stack a spacer answers **0 on the stack's cross axis**
  (SPB1 100×0, SPB2 8×0, SPB5 0×50, X8's overlay proposed 180×0); outside one
  it is flexible on both axes (SPB3 100×50, SPB4 8×8, SPB6 through a `ZStack`,
  contract probe E). The axis reaches through `.frame` (SP19's stack is 20
  tall), `.padding` (SP20) and `.overlay` (X8), and a nested stack re-decides
  it (SP18b: `VStack { Spacer() }` in an `HStack` is 0 wide).
- Framing a spacer hides its priority **and** its flexibility (SP19: the
  stack answers 50); padding hides only the priority (SP20: still flexible,
  served last within priority 0); an overlay hides neither (X8).
- At an infinite proposal a spacer answers ∞ (contract probe E).

**The ruling.** `newNativeSpacer(minLength: nil)` stores the platform default,
one public constant `ProposalSpacing.platformDefault = 8` (`MetalUILayout`),
also used by `CN-H`. A spacer node answers `max(minLength, proposal)` per axis
with ∞ allowed and nil → `minLength`, except on the cross axis of the linear
stack that owns it, where it answers 0. **Ownership is decided at
registration:** `newNativeLinearStack` walks each child through
`layoutPriority`, `overlayAttachment` (primary side), `padding`, `frame`,
`fixedSize` and `aspectRatio` and marks the spacers it reaches with its axis;
the walk stops at any other node, so an inner stack's marks stand. The stack's
priority reader returns −∞ for a spacer reached bare and `nativeLayoutPriority`
otherwise, so an explicit `.layoutPriority` wins. The public proxies'
`priority` reports −∞ for a spacer, as SwiftUI's does (E2). `isSpacer` stays
public with its current reach (bare or under `layoutPriority`); its only
built-in reader becomes `CN-H`'s spacing rule.

**Not probed, and chosen:** whether the stack axis reaches a spacer on the
*overlay* side of `.overlay`, or through `.aspectRatio`/`.fixedSize` (marked,
by analogy with frame and padding). A `ZStack` inside a stack does not pass the
axis on (only SPB6's `ZStack`-alone arm exists).

**What it costs if wrong.** A spacer claims or refuses a cross-axis size a
SwiftUI one would not, which moves a stack's cross size (SP13: 20 tall, not
50) — visible, and pinned per arm.

---

## CN-D — a single-child `HStack`, `VStack` or `ZStack` passes its child's priority through

**The finding.** G11: `HStack { HStack { a.layoutPriority(1) }; b }` gives a
80 at 100 (priority 1 wins); G11c, the same with a second (0-wide) child in the
inner stack, gives 50/50. The contract probe's L3 reads the same through a
proxy for all three stack kinds, and 0 for a single-child custom layout.

**The ruling.** `nativeLayoutPriority` of a `linearStack` or `overlay` node
with exactly one child is that child's stack priority (so a lone spacer's −∞
passes too); a custom layout reads 0. Closes `SA-N` item 8, and flips
`aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules`' wrong-on-
purpose 0.

**What it costs if wrong.** A single-child wrapper stack changes its sibling's
share; the discriminating arm pair is in the test.

---

## CN-E — cross axis, second pass and `ZStack` placement

**The finding.**

- Every stack child is offered the stack's cross proposal (G16, G20).
- When that cross proposal is **nil**, the stack **reports** its first-pass
  answers but **places** after re-running the distribution at its own cross
  size (Q1: reports 30×80, places a 30×20 child at y 0 and the next at y 20;
  X10, X11, G17).
- A `ZStack` offers every child its proposal and **places** each at
  `proposal ?? its own size` per axis (A5n 20×20; X12 100×20; Q2 reports
  30×60 and places at 30×60).

**The ruling.** Adopt all three. The second pass runs only in placement and
only when the cross proposal is nil; its allocations are stored, its size is
not reported.

**What it costs if wrong.** A greedy child in a nil-proposed stack stays at its
ideal instead of matching its widest sibling (the common `VStack` of labels and
a `.frame(maxWidth: .infinity)` divider).

---

## CN-F — an infinite proposal is answered with infinity by a frame, a spacer and a scroll viewport (reverses `FR-B`)

**The finding.** SwiftUI answers ∞ at ∞ for `.frame(maxWidth: .infinity)`
(D12), for a spacer (contract probe E) and for a `ScrollView` on its scrolling
axis (SC1 at inf×inf). `CN-B`'s flexibility probe asks every child at main ∞,
so a kernel that answers the child there reports a greedy frame as rigid. In the
prototype without this change, `.frame(maxWidth: .infinity)` placed before an
80pt rigid sibling at 100 would be served first and overflow to 130 (by reading
of the prototype's sort; SwiftUI serves the rigid child first).

**Why `FR-B`'s reason no longer holds.** `FR-B` kept `proposal.isFinite`
because an infinite measurement would reach `LayoutRect`. After `CN-B` the
built-in producers of an infinite proposal are measurement probes; placement
proposals are allocations (finite whenever the stack's own proposal is), a
frame places at a clamp of its finite proposal, a viewport offers nil, and the
root is finite. Checkpoint 3 still traps a non-finite rect, so a custom layout
that places at ∞ traps exactly where SwiftUI crashes (D12's recorded
`view origin is invalid`).

**The ruling.** Drop `proposal.isFinite` from `framedSize`'s greedy gate, from
`spacerLength` and from `resolvedViewportDimension` on the scrolling axis.
`aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` is replaced by a
test asserting the three infinite answers. **Measured:** the prototype suite
with this change added two red tests to the previous 25 and no trap
(`aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity`,
`aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically`); the preview
was byte-identical to the prototype without it.

**What it costs if wrong.** An infinite rect reaches checkpoint 3 and traps
with the node named. That is louder than `FR-B`'s silent under-expansion, and
no built-in path is known to reach it; the lane adds an exit test for the one
path that can (a custom layout placing at ∞).

---

## CN-G — `aspectRatio` answers its child's answer to the ratio-shaped proposal

**The finding.** AR1: a fixed 168×95 child under `.aspectRatio(16/9, .fit)` at
500×300 is proposed 500×281.25 and the modifier answers **168×95**; AR2 at nil
answers 168×95 with the child proposed nil×nil; AR3, a child that takes the
offer, answers the ratio size 500×281.25; AR4 keeps it 168×95 inside an
`HStack`. The kernel answers the ratio size whatever the child does.

**Why here and not in task 7.** It was task 7's (`SA-N` item 3), but `CN-B`
makes it visible: prototyped without it, the preview's `PreviewToggle`
(`Rectangle(168×95).aspectRatio(16/9)` in the bottom `HStack`) is offered a
finite allocation and grows to **496×279** — 155 248 differing pixels. With it,
the toggle reads 168×95 (SwiftUI's AR1) against today's 168×94, **188 pixels**.

**The ruling.** At a nil×nil proposal the modifier proposes nil×nil and answers
the child; otherwise it proposes today's ratio-shaped size and answers the
child's answer, placing the child at that answer. Closes `SA-N` item 3.

**Measured risk, owed to the lane.** In the full prototype
`aNegativeAspectRatioIsAcceptedOnEveryProposedBranch` failed with its exit
status `.signal(SIGTRAP)` instead of `.success`: some negative-ratio branch now
reaches a trap. `SA-K` item 2 accepts negative ratios, so the lane finds the
trapping checkpoint and fixes the rule, not the test.

**What it costs if wrong.** A fixed child under `.aspectRatio` sizes by its own
answer rather than the ratio; `aspectRatioFitInscribes…`/`…Fill…` flip and pin
AR1/AR3.

---

## CN-H — platform-default spacing: 8 between views, none next to a spacer; explicit spacing verbatim

**The finding.** Horizontally every measured pair is 8 (S: rect, color, custom
layout, text, image, nested stack, button, padded text, toggle). Vertically
non-text pairs are 8; a **Text edge is font-derived**: text|text 0, rect|text
4.74, text|rect 8.15, image|image 0, toggle|toggle 6. An empty conditional adds
nothing (G23). **No default spacing is inserted next to a spacer** (SP2 48 =
SP1; SP3 40), but **explicit spacing is** (SP4 80).

**The ruling.** `HStack`/`VStack` take `spacing: Pixels? = nil`. The kernel's
`newNativeLinearStack` takes `spacing: Double?`; nil means, per adjacent pair,
0 if either node `isNativeSpacer`, else `ProposalSpacing.platformDefault`; a
number is used for every gap. `ProposalScrollView`'s lowering of several
children passes nil. **Not adopted:** the text-edge vertical values. MetalUI's
`ProposalText` has no font metrics in the kernel and no spacing preference
channel; it gets 8 (a divergence, owner task 11 with baseline alignment).

**What it costs if wrong.** A `VStack` of `ProposalText`s is 8pt per gap
looser than SwiftUI's; two labels in one `VStack` differ by one gap. Recorded,
not pinned by a SwiftUI-disagreeing test (a pin would have to assert 8 against
a probe that reads 0 — it is pinned as MetalUI's rule with the probe numbers in
its doc comment).

---

## CN-I — typed stack alignments, in SwiftUI's argument order

**The finding.** A1 and A2 read the three positions per axis; SwiftUI types
them `VerticalAlignment` / `HorizontalAlignment` and puts `alignment:` before
`spacing:`. Today `HStack(alignment: .leading)` compiles and places like
`.center` (CLAUDE.md's inert row; `aNativeLinearStackUsesItsAlignmentOnTheCrossAxisOnly`).

**Measured.** Three call sites pass `alignment:` to a proposal stack
(`main.swift:977, 993`; `NativeLayoutIntegrationTests.swift:1012`); 30 more pass
`spacing:` only, which the new initializer accepts unchanged.

**The ruling.** New `public enum VerticalAlignment { top, center, bottom }` and
`HorizontalAlignment { leading, center, trailing }` in `MetalUI`, each with an
internal mapping to `ProposalAlignment`; `HStack.init(alignment:
VerticalAlignment = .center, spacing: Pixels? = nil, content:)`,
`VStack.init(alignment: HorizontalAlignment = .center, spacing: Pixels? =
nil, content:)`. The old `init(spacing: Pixels, alignment: ProposalAlignment,
content:)` stays, **deprecated, with no default arguments**, so it is chosen
only when both labels are written in the old order and never makes `HStack {}`
ambiguous; it forwards the cross-axis factor as today. The three call sites
move to the new order. `ZStack` keeps the nine-case `ProposalAlignment`; the
kernel keeps `ProposalAlignment` on `newNativeLinearStack`.

**What it costs if wrong.** An external caller writing the old order gets a
deprecation warning, and one writing `HStack(alignment: .leading)` a compile
error — SwiftUI's own error. Three typecheck guards pin both and the deprecation.

---

## CN-J — a native root is placed centred at its own answer

**The finding.** R1 and R2: a hosting view proposes its bounds and places a
58×20 root at (21, 40) in 100×100; a greedy root fills (R control). The kernel
stores the root at the full window and a root stack packs from the leading
edge (`hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt` pins x
28).

**The ruling.** `Frame.computeRootLayout` measures a native root at the window
proposal and places it at `((w − answer.w) / 2, (h − answer.h) / 2)` at its
answer, in one native run: a new `LayoutTree.computeNativeLayout(root:proposal:centredIn:)`.
The legacy root is untouched. The preview's root is a greedy `ZStack` and did
not move (0 pixels, prototype).

**What it costs if wrong.** A small native root sits in the window's centre
instead of its top-left; loud, and pinned by R1's numbers.

---

## CN-K — overlay and background content: several views are a `ZStack`, none is nothing, and `.background` takes content

**The finding.** A10: two views in one `.overlay` are laid out as a `ZStack`
with the overlay's alignment, itself proposed the primary's size (o1 at
(20, 10), o2 at (15, 15)). A11/A11b: an empty conditional in `.overlay` or
`.background` leaves the primary alone. A9: `.background(alignment:content:)`
proposes the primary's size and aligns like an overlay. Today a non-single
overlay traps (`precondition` in `NativeOverlayModifier.swift:73`), and the
proposal `.background` takes only a `ColorToken`.

**The ruling.** `OverlayModifier` lowers several overlay nodes to one kernel
`overlay` node with the modifier's alignment, and zero nodes to the primary
alone (no attachment node). New `.background(alignment:content:)` on
`ProposalElementGroup`, returning a `BackgroundModifier` that registers the same
`overlayAttachment` and paints the secondary **before** the primary. Its content
numbers under `.child(of: id, at: -1)`, exactly as `MC-P` numbers an overlay's.
The primary side keeps its one-node precondition (a primary is the view being
modified; SwiftUI has no zero-view receiver).

**What it costs if wrong.** An overlay of a conditional stops trapping and
starts drawing nothing, which is the SwiftUI answer; a multi-view overlay's
placement is pinned by A10's numbers.

---

## CN-L — a native node registered under two parents traps (`MC-G` hole 4)

**The finding.** No SwiftUI spelling reaches it (a view value has no node id).
`aNativeNodeRegisteredTwiceIsNotRejected` pins the hole wrong on purpose and
records that a duplicate-parent precondition truncates the suite at that test.

**The ruling.** The native registrars record each child's parent and trap on a
second one, or on a child listed twice in one parent, with a message naming
`MC-G` hole 4. Legacy `newNode` is not checked (outside the hole, unmeasured).
The pin becomes an exit test **before** the precondition lands.

**What it costs if wrong.** A real tree that reuses a native node traps where it
used to lay out one of its two slots; no such tree exists in `Sources/` (both
arms of the pin are hand-built fixtures).

---

## CN-M — scroll axes

**The finding** (SC, SCG2). A `ScrollView`:

- proposes nil on each scrolling axis and its proposal on the other (SC1; the
  kernel already does);
- answers `proposal ?? content` on a scrolling axis, ∞ at ∞ (`CN-F`), and **the
  content's answer on a non-scrolling axis** — SC2 `.vertical` 50×100 at
  100×100, SC4 500×100;
- places content smaller than a single-axis viewport at the leading edge of the
  scrolling axis (SCG2 `.vertical` (0, 0) in a 50×100 view); centres it on both
  axes of a two-axis viewport (SCG2 both (25, 35); control 500×500 at (0, 0));
- lays out two direct children as a centred, default-spaced `VStack` whatever
  the axes (SC3: b at (10, 38) on all three).

**The ruling.** Adopt the non-scrolling-axis answer (the preview's scroll view
border narrows from 856 to 520 wide, 1 109 pixels, prototype) and the default
spacing of `CN-H` for the lowering; the other two rules are already the
kernel's and gain pins. **Two-axis scrolling is deferred to task 10**:
`ScrollState` holds one offset, a scroll hitbox one axis and the indicator one
track, and SCG2's centring rule has nothing to attach to until they do.

**What it costs if wrong.** A proposal scroll view is as wide as its content on
its cross axis rather than as its parent; the preview shows it.

---

## CN-N — a legacy frame over exactly one node lowers to a one-cell stack, and overflows both axes (closes `FR-N`)

**The finding.** `FR-N`: a single flex node squeezes an oversized child on its
main axis and overflows the cross axis, where SwiftUI's A5 (frame-semantics
probe) overflows both, 200×160 at (−70, −60) in a 60×40 frame.
**Prototype** (every frame layer lowered to `display: .stack` with
`alignItems`/`justifyItems` from the alignment): the child reads exactly
(−70, −60) 200×160; the suite read **5 red tests, 8 issues**:
`aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows` and
`aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink` (both now at
SwiftUI's numbers), and three tests of a frame over a **two-member**
`Component` (`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`,
`chainedFramesRemainConcreteAndNestTheirLayoutNodes`,
`aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers`), whose members
were layered instead of laid out as a row. `aLegacyFrameProposesItsWidthToAMeasuredLeaf`
stayed green: a `Text` in a one-cell stack still re-wraps at the frame width.
The default demo uses no legacy `.frame`.

**The ruling.** A frame layer whose content contributes **exactly one** node
registers with `display = .stack`, `alignItems` from the alignment's vertical
case and `justifyItems` from its horizontal case; with zero or several nodes it
keeps `FR-C`'s flex lowering. `ModifierLayer` gains an internal `isFrame` flag,
set by both frame overloads; the choice is made in `ModifiedElement.requestLayout`,
before `animated`, per layer. SwiftUI's G7 (component-distribution probe) wraps
**each** member of a two-member custom view in its own frame; neither the row
nor the stack is that answer, and the row is kept because it is today's.

**What it costs if wrong.** A child with `.flexGrow` or `.alignSelf` inside a
single-child legacy frame loses them (a `Stack` ignores both). No test or demo
site writes that, and SwiftUI has neither.

---

## CN-O — the `percent:` sizing modifiers are renamed `fraction:`; the old spelling is deprecated with its meaning unchanged

**The finding.** `FR-T`: `width(percent:)`, `height(percent:)` and
`flexBasis(percent:)` take a fraction; `percent: 50` is 5000%. It recorded the
fix and preferred the rename ("no silent change").

**The ruling.** Add `width(fraction:)`, `height(fraction:)`,
`flexBasis(fraction:)`; mark the three `percent:` methods
`@available(*, deprecated, renamed: "…(fraction:)")`, forwarding unchanged.
Every call site in `Sources/` and `Tests/` moves to `fraction:` (0-warning
gate); a typecheck guard counts the three deprecations. `Length.percent` in
`Style` keeps its fraction (the CSS layer, where it is documented and goldens
use it).

**What it costs if wrong.** A caller keeps `percent: 0.5` with a warning that
names the fix; nothing changes size.

---

## CN-P — the legacy containers keep their algorithms, and three divergences are pinned

**The audit** (the spec's table). The legacy containers agree with SwiftUI on
centred cross-axis stacking (EP-8, A1/A2), `Stack`'s nine alignments and union
sizing (A3/A4), and disagree on:

1. **default spacing** — `Row`/`Column` gap 0, SwiftUI 8 (S);
2. **what a `Stack` offers a child** — fit-content, where `ZStack` offers its
   proposal (A5: a greedy child fills 100×80; a childless `Box` in a `Stack` is
   0×0);
3. **a `ScrollView`'s cross axis** — the legacy viewport takes its parent's
   (stretch or declared), SwiftUI's takes its content's (SC2);
4. compression by CSS flex-shrink (proportional to base size) instead of
   flexibility order (G1), expansion only by `flexGrow`, no spacer.

**Measured.** Changing `Row`/`Column`'s default gap to 8 reddens **22 tests**
(listed in the spec's appendix) and 0 demo pixels (every demo stack spells its gap),
and would still disagree with SwiftUI next to text vertically (0) and has no
spacer to be zero beside.

**The ruling.** No legacy default changes. Items 1–3 get one characterization
test each that builds the legacy spelling and its proposal counterpart side by
side and `#require`s them to disagree by the probe's numbers; item 4 is
`FlexEngine`'s and is covered by its goldens. They are recorded as divergences
at integration (numbers assigned there).

**What it costs if wrong.** A caller porting a legacy `Row {}` to `HStack {}`
gains 8pt gaps silently; the pin makes the difference findable by name.

---

## CN-Q — deferrals, each with a reason and an owner

| item | why not here | owner |
|---|---|---|
| lowering `Row`/`Column`/`Stack`/`Box`/`ScrollView`/`List`/`Deferred` onto the kernel; switching the default demo root | `CN-A` | task 7 |
| a greedy **finite** maximum and a **single-axis** infinite maximum on the legacy frame (`FR-E`, `FR-O`); a nil-axis frame under a stretching `Box` (`MC-Q` finding 7) | needs the parent's flex axis at registration: a pass-scoped value every legacy container would have to set (at least `Box`, `Stack`, `ScrollView`, `List`, `Deferred`, `EnvironmentScope`, `Component`, the root), none enforced, on a path task 7 deletes. The proposal path delivers it (FR-A, `CN-B` G4) | task 7 |
| legacy `.overlay` | `ModifiedElement` holds one subtree; a second is the `ModifiedContent` unification (`OM-` spec §9) | task 7 |
| a proposal `List` | windowing, `ScrollContext`, row identity (MP-/TB- rulings) — the plan's own task | task 10 |
| a proposal `Deferred` (portal) | no SwiftUI layout counterpart; presentation belongs with the root switch | task 7 |
| two-axis scrolling | `CN-M` | task 10 |
| text-edge vertical default spacing; `firstTextBaseline`/`lastTextBaseline` stack alignment | needs font metrics and baselines from `ProposalText` (`CN-H`) | task 11 |
| builder wrappers with zero or several nodes (`ProposalFrame { if flag {…} }`, `Padding`, `FixedSize`, `Background`, `OnTapModifier`) | SwiftUI has no builder frame; `Group` semantics (a modifier applies per view) is the composition audit | task 8 |
| `SA-N` item 4, padding places its child at the child's size | not a container; its pin is intact | task 7 |
| the release-window captures | `IOConsoleLocked` read `<true/>` at 2026-09-16 design time | carried (`MC-J`) |

---

## CN-R — method: what was run, and where

- **Probe**, `docs/probes/swiftui-stack-algorithms.swift`, three revisions
  (`75b5f69`, `fbfc1d6`, the A11 revision), each run twice under
  `/usr/bin/swift` with byte-identical output; each revision's output prefix
  identical to the previous revision's. Every group has a control that differs
  from its arms. Two harness defects were found and fixed before recording:
  the `Probe` layout's own `sizeThatFits` is not always called (an arm printed
  the previous arm's size), so placement re-reads it and a sentinel `-1x-1`
  marks an unmeasured arm; views containing only spacers or nothing are never
  laid out as hosting-view roots, so SPB reads them through a background leaf.
- **Kernel prototypes** (P1: `CN-B`/`CN-C`/`CN-D`/`CN-E` ZStack; P2: + `CN-G`
  and `CN-J`; P4: + `CN-M` cross axis; P5: + `CN-F`), each run through the
  unfiltered suite under `--build-system native`: P1 1303 tests, 50 issues;
  P2 25 red tests; P5 27 red tests (named in the spec). P1's run also failed
  `aNodeIDDoesNotSilentlyResolveAgainstAnotherFramesTree` and
  `everyFrameTakesADistinctTreeGeneration`; neither failed under P2 or P5 and
  neither was reproduced — recorded, not explained.
- **Work counts**, a scratch `@testable` test (deleted), under P1 and at
  `9e439cb`.
- **Legacy prototypes**: `Row`/`Column` default gap 8 (22 red); every frame layer
  as `display: .stack` (5 red / 8 issues).
- **Pixels**, the record §13/§16 harness rebuilt in scratch: `main.swift` up to
  `runDemo()` with its globals prefixed `SI`, rendered through a real `Window`
  over `FakePlatformWindow` at 1024×1024, ten images, plus two added 560×560
  images (the default demo and the preview) because the 1024 square never
  compresses the preview. Base `git archive 9e439cb` in scratch. Controls on the
  base: light vs dark 1 048 576; default vs modal 1 030 498; default vs
  animation 210 027; f0 vs f3 0; preview light vs dark 1 048 576 — the same
  figures record §16 read.

---

## CN-S — what the demo comparison must read, per lane

Against `9e439cb`, cumulative, the twelve images of `CN-R`:

| after lane | 8 legacy images + `small560-default` | `preview-*` (1024) | `small560-preview` |
|---|---|---|---|
| 1 | 0 | 188 each; `PreviewToggle` 168×94 → 168×95 (AR1) | differs; every moved rect traced to G9/X13, A4 or AR1 in the lane record |
| 2 | 0 | unchanged from lane 1 | unchanged from lane 1 |
| 3 | 0 | unchanged (greedy root, R control) | unchanged |
| 4 | 0 | 1 109 each, bbox (264, 212)–(939, 865): lane 1's two rects plus the scroll border 856 → 520 wide (SC2) | 64 945 (prototype P5), each rect traced |
| 5 | 0 | unchanged from lane 4 | unchanged from lane 4 |

An instrument must differ first on every lane that expects 0 on an image
(practices shape 15): the lane mutates the code it changed and shows the
comparison moves. Any other difference is explained by a probe arm or fixed.
The real release windows are captured only if `IOConsoleLocked` reads
`<false/>` at that lane's end.
