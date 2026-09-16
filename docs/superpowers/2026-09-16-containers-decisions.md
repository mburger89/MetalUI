# Containers decisions (plan task 6)

Rulings for `docs/superpowers/specs/2026-09-16-containers-design.md`, on
`feat/containers` from `9e439cb`. Ids are **lettered**, `CN-A`…; next unused is
**`CN-V`**. A bare `CN-3` is a typo, not a citation.

**Status, 2026-09-16, design only, after critic round 1.** No file under
`Sources/` or `Tests/` changed in a commit. Every source patch cited below as a
*prototype* was applied in this worktree, built, run and restored with
`git checkout Sources/ Tests/`, with `git status --short` showing only the
design's own docs afterwards; scratch test files were deleted. Baseline at
`9e439cb` plus the probe commits, after `swift package clean`: `swift build
--build-system native --build-tests`, then `swift test --build-system native
--no-parallel` → `Test run with 1303 tests in 1 suite passed`, 0 `error:`, no
`warning:` besides SwiftPM's own deprecation notice.

Probes (arm names below are theirs):

- `docs/probes/swiftui-stack-algorithms.swift` — revision 4 (`cef0acd`,
  `f10e779`), run under `/usr/bin/swift`, Apple Swift 6.4, macOS 27.0 (26A428);
  exit 0; run twice per revision with byte-identical output, recorded in its
  header. Revision 4 corrected two revision-3 readings (the ZStack placement
  rule, and "framing a spacer hides its flexibility"), both marked in the
  header.
- `docs/probes/swiftui-overlay-presentation.swift` (`cef0acd`, `a163bb9`) —
  compiled form only (the script form fails to JIT); overlay clipping, paint
  order, presentations and background/overlay click order.

**Call counts in SwiftUI are OS-dependent; allocations are not.**
`swiftui-frame-semantics.swift`, re-run 2026-09-16 on macOS 27.0 against its
record from 26.6.2, prints fewer duplicate flexibility probes in G1 (one
`0.0xnil`/`infxnil` pair per pass, not two) and identical placements. No ruling
here rests on a SwiftUI call count; `CN-B`'s cost figures are MetalUI's.

The critic round's findings and what was done with each are in
[Critic round 1](#critic-round-1--dispositions) at the end.

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
- **What shape 3 costs, prototyped in full and staged per lane** (`CN-R`): the
  suite's red lists and the pixel figures for every lane are in the spec
  (§6 and the appendix). All changed tests are on the proposal path except
  lane 5's two legacy-frame tests; the eight legacy demo images and the
  560×560 legacy image read **0 differing pixels at every stage**.

**The ruling.** Shape 3. This task makes `HStack`, `VStack`, `ZStack`,
`Spacer`, `.overlay`/`.background` content and `ProposalScrollView` behave as
the probe says, and gives the legacy frame layer the one SwiftUI answer a
single CSS node can express (`CN-N`). **No legacy container is lowered onto the
kernel, and no legacy default changes** (`CN-P`). The switch of the default demo
root and of the legacy spellings is task 7's, root by root.

**Task 6 stays open** (`CN-T`): its text says "Replace containers", and no
legacy container is replaced. `CN-T` proposes the amended text; the design does
not tick the task on its own.

**What task 7's root switch needs first** (the prerequisites, each owned in
`CN-Q`): proposal registrations for `Text` with decorations and handlers, `Box`
as a leaf, `ModifiedElement` layers (the `ModifiedContent` unification), a
windowed proposal `List` with its `ScrollContext` and row identity (moved to
task 7 by `CN-T`), a proposal portal for `Deferred`, the legacy layout
modifiers the demo uses (`flexGrow`, `flexBasis`, `alignSelf`, `minHeight`,
`position`/`inset`), and accessibility records and the disabled gate on
proposal elements.

**Reasoning.** Shape 1 or 2 inside five lanes would either stop half-way — a
tree whose root is native but whose leaves are not traps — or reintroduce an
adapter, which `SA-G` forbids. Shape 3 is the only one whose every lane ends
green, and it is the prerequisite of the other two: task 7 cannot switch a root
onto algorithms that are not yet SwiftUI's.

**Identity.** Nothing in this task changes an element id, a `$state`/`$focus`/
`$anim` path, a `List` row name or vanishing-`if` adoption: no lane adds or
removes an element level. The new kernel node (`CN-K`'s implicit `ZStack` over
several overlay nodes) is a layout node with no element identity; the new
`BackgroundModifier` numbers its content exactly as `OverlayModifier` does.

**What it costs if wrong.** Two layout authorities stay live for another task,
and the legacy containers keep their CSS answers (spacing 0, flex-shrink
compression, fit-content `Stack` children), recorded as divergences with task 7
as owner (`CN-P`). If task 7 finds a root that cannot switch because of
something this task could have ported, that is a missed item, not a broken tree.

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
  flexibility of 0 (G3's second child gets one call; the exact lists vary by OS
  release, see the header). The kernel probes every member of a group of two or
  more at main 0 and main ∞, and probes a lower-priority child only at main 0; a
  group of one is not probed. Under `SA-H`'s purity assumption the allocations
  are identical to a stable sort.
- **The distribution is one function used by both measurement and placement**,
  so what a stack reports and where it places cannot disagree (CLAUDE.md's
  "measures at nil, places at allocations" item).

**Measured cost** (staged prototype, clean build, `CN-R`; MetalUI's counts,
not SwiftUI's):

- `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`: today
  16 calls / 27 hits / 25 misses; after lane 1 **47 / 51 / 66**; after lanes 2
  and 3 **44 / 50 / 63**; after lanes 4 and 5 **46 / 48 / 66**. (The design's
  earlier "47 / 52 / 66, under P1" was taken from a prototype that also carried
  `CN-C`'s default minimum and marks; it is superseded by these.)
- **Nested alternating stacks** (level k = stack{leaf 10…80, fixed 20×20,
  `Spacer()`, level k−1}, spacing 4; 3 to 15 leaves), proposed 400×300 at a
  finite root, and inside a vertical scroll viewport — **the nil cross
  proposal that runs `CN-E`'s second pass**:

  | depth | leaves | today (both) | finite root, lanes 2–5 | in scroll viewport, lanes 2–5 |
  |---|---|---|---|---|
  | 1 | 3 | 3 calls, 1.0/leaf | 9 calls, 3.0/leaf | 18 calls, 6.0/leaf |
  | 2 | 5 | 5, 1.0 | 33, 6.6 | 20, 4.0 |
  | 3 | 7 | 7, 1.0 | 51, 7.3 | 72, 10.3 |
  | 4 | 9 | 9, 1.0 | 69, 7.7 | 74, 8.2 |
  | 5 | 11 | 11, 1.0 | 87, 7.9 | 120, 10.9 |
  | 6 | 13 | 13, 1.0 | 105, 8.1 | 122, 9.4 |
  | 7 | 15 | 15, 1.0 | 123, 8.2 | 168, 11.2 |

  Calls grow by 18 per level at a finite root and by 2–48 per level in the
  viewport (alternating: a vertical level under a nil height re-solves); no
  depth multiplies the previous one. Lane 1 alone reads the same calls
  (hits and misses differ by a few, as the spacer's cross axis is lane 2's).
- **Shaping** (`ShapingCache.misses`, a fresh cache, one cold frame of
  `ProposalText`s in stacks): 3 texts in one `HStack`, 6 misses today, **12**
  after lane 1, finite root or in a `ProposalScrollView` (lookups 12 and 21);
  7 texts in three nested stacks, 14 today, **28** after (lookups 64 and 78).
  Each text is shaped at 4 distinct widths per cold frame instead of 2.
  `Shaper.runCallCounter` is not reached: `ProposalText` measures without the
  tokenizer.

**Every lane-1 performance test is written against a literal derived by hand
before its run** (`SA-M`, shape 12); the prototype figures above are the check
the derivation must meet, and a disagreement is a finding for the decisions
doc, not an edit to the literal.

**Lane 1, as built** (`31fd2ba`; record §17). Two of the figures above held and
one did not:

- **Held:** the nested tree at depth 3 reads **51** calls at a finite root and
  **72** in a vertical scroll viewport, and three `ProposalText`s read **12**
  shaping misses (12 lookups at a finite root, 21 in a scroll viewport) — each
  literal derived by hand from the lane's own tree before the run, and equal
  to the prototype's.
- **Did not hold:** `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`
  reads **65 calls / 54 hits / 90 misses**, not 47 / 51 / 66. Its branch C is a
  `ReferenceLinearStack`, which this lane rewrote to `CN-B` (the spec requires
  it); the prototype kept the old reference, whose `sizeThatFits` measured
  every child at (nil, nil) whatever its proposal. Under the rewrite C's
  answer depends on its cross proposal (an echo leaf), so R's distribution
  probes and serves C three times at distinct keys. The literals were
  re-derived by hand from the rewritten reference before the run, the
  derivation is the test's doc comment, and the run matched it. **The spec's
  44 / 50 / 63 (lanes 2–3) and 46 / 48 / 66 (lanes 4–5) for this test are
  prototype figures of the same old reference and are void**; lanes 2 and 4
  re-derive from `31fd2ba`'s tree.

**What it costs if wrong.** Every proposal-path stack allocates differently
from SwiftUI on the trees the tests do not build. The probe arms are
three-child at most; the lane's tests add a three-group, three-flexibility
tree (G13, G14) so a two-child special case cannot pass. The work cost is up to
11 leaf calls per leaf and twice the shaping on a cold frame; the cache is still
per call (`SA-H`), so a warm frame pays it again.

**Lane 2, as built** (`63387f6`; record §17). The branching tree reads **62
calls / 53 hits / 87 misses**, re-derived by hand from lane 1's tree: only its
aspect ratio changes, by the same −3 / −1 / −3 the prototype moved (66/51/47 →
63/50/44). The nested tree (51 / 72) and the shaping count (12) are unchanged.

---

## CN-C — `Spacer`: default minimum 8, priority −∞, zero on its stack's cross axis, infinite at an infinite proposal

**The finding.**

- `Spacer()`'s nil `minLength` is **8** (SP1 48; SP6; `SA-N` item 2's P5), a
  constant rather than the gap its neighbours would get: `VStack { Text; Spacer();
  Text }` is 40 tall at default spacing and at spacing 0 (K1, K1c), where
  text|text is 0 (K0, K1b).
- A spacer has **priority −∞** unless given one (SP8's first child is offered
  (200 − 8) / 2 = 96; X5; X6 gives a `.layoutPriority(1)` spacer all 100).
  `SA-D`'s contract probe already read −∞ through a custom layout's proxy (E2).
  Priority is hidden by a flexible frame (K2d), `aspectRatio` (K2b), `fixedSize`
  (K2c) and padding (SP20), passes through an overlay's primary (X8) and a
  single-child `ZStack` (K2a: 96).
- Inside a linear stack a spacer answers **0 on the stack's cross axis**
  (SPB1 100×0, SPB2 8×0, SPB5 0×50, X8's overlay proposed 180×0); outside one
  it is flexible on both axes (SPB3 100×50, SPB4 8×8, SPB6 through a `ZStack`,
  contract probe E). **The mark reaches** through `.frame` (SP19, K2d),
  `.padding` (SP20), `aspectRatio` (K2b: stack height 20), `fixedSize` (probe
  revision 6: K2g 8×0 against its `ZStack` control K2f 8×8, K2i height 20
  against K2j 30; K2c's height 20 cannot tell, its siblings set it either
  way), the overlay's primary (X8) **and the overlay's content** (K2e: a spacer
  in the overlay of a 10×10 primary answers 10×0). **It does not reach** through
  a `ZStack` (K2a: `ZStack { Spacer() }` claims the 50pt cross proposal) or a
  nested stack, which re-decides it (SP18b).
- A **fixed** frame makes a spacer rigid (SP19, `.frame(width: 10)`: the stack
  answers 50). A **flexible** frame keeps it greedy (K2d: the stack answers
  200). The design's earlier "framing hides flexibility" read SP19 alone and was
  wrong.
- At an infinite proposal a spacer answers ∞ (contract probe E).

**The ruling.** `newNativeSpacer(minLength: nil)` stores the platform default,
one public constant `ProposalSpacing.platformDefault = 8` (`MetalUILayout`),
also used by `CN-H`. A spacer node answers `max(minLength, proposal)` per axis
with ∞ allowed and nil → `minLength`, except on the cross axis of the linear
stack that marks it, where it answers 0. **Marking is decided at
registration:** `newNativeLinearStack` walks each child through
`layoutPriority`, `padding`, `frame`, `fixedSize`, `aspectRatio`, and **both
children** of `overlayAttachment`, and marks the spacers it reaches with its
axis; the walk stops at any other node (`overlay`, `linearStack`,
`scrollViewport`, `custom`, `leaf`), so an inner stack's marks stand.
`reset(generation:)` clears the marks.

The stack's priority reader (`CN-D`) returns −∞ for a spacer reached bare or
through an overlay's primary or a single-child stack, the value of a
`layoutPriority` node, and 0 otherwise. The public proxies' `priority` reports
the same reader, so a spacer reads −∞ as SwiftUI's proxy does (E2). `isSpacer`
stays public with its current reach (bare or under `layoutPriority`); it is no
longer read by any built-in (`CN-H` uses its own walk).

**Split across lanes** (`CN-S`, the spec's §6): the −∞ priority and the ∞
answer are lane 1's, because the distribution cannot be pinned without them;
the default 8 and the cross-axis mark are lane 2's.

**Measured** (staged prototype): all K2 arms, SP19, SP20 and X8 read the probe's
allocations under the walk above; lane 2 alone adds 5 red tests (spec appendix).

**What it costs if wrong.** A spacer claims or refuses a cross-axis size a
SwiftUI one would not, which moves a stack's cross size (SP13: 20 tall, not
50) — visible, and pinned per arm.

**Lane 2, as built** (`63387f6`; record §17). As ruled, with two choices the
ruling left open:

- **A spacer keeps its first mark.** Marks are set at registration and an
  inner stack registers before the stack containing it, so the first mark is
  the nearest stack's; the walk's `switch` is exhaustive, so a new node kind
  must choose to pass or stop.
- **`ReferenceLinearStack` reads `isSpacer` again.** A `ProposalLayout`
  cannot mark a node (nor can SwiftUI's custom layouts: contract probe E), so
  the reference leaves `isSpacer` subviews out of its cross size, and
  `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects` compares
  only the main-axis extent of the reference tree's three spacer nodes. The
  proxy's `isSpacer` reach (bare or under `layoutPriority`) is narrower than
  the mark's walk; the reference tree builds nothing between.

---

## CN-D — a single-child `HStack`, `VStack` or `ZStack` passes its child's priority through

**The finding.** G11: `HStack { HStack { a.layoutPriority(1) }; b }` gives a
80 at 100 (priority 1 wins); G11c, the same with a second (0-wide) child in the
inner stack, gives 50/50. The contract probe's L3 reads the same through a
proxy for all three stack kinds, and 0 for a single-child custom layout. K2a:
a single-child `ZStack` passes a spacer's −∞ through (its sibling is offered
96).

**The ruling.** The stack priority of a `linearStack` or `overlay` node with
exactly one child is that child's stack priority (so a lone spacer's −∞
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
- **Amended, critic round 1.** A `ZStack` measures every child at its proposal.
  It **places** every child at a proposal equal to **its own size B** (the size
  it answered, which is the size its parent placed it at), re-measures each
  child there, and aligns each child within the **union U** of those answers,
  with U's origin at the `ZStack`'s origin (Z1: at 60×40 it answers 30×20; the
  half-width leaf is placed at proposal 30×20, answers 15×10, and sits at
  (2.5, 5) inside the 20×20 union, not at (7.5, 5) inside 30×20; Z4 places at
  60×40, not 100×100; Q2's children, placed at 30×60, answer 30×20 and sit at
  y 0, not y 20; Z3). The design's earlier "places at `proposal ?? own size`"
  agreed with A5, A5n, X12 and Q2 but not with Z1, which is the only arm whose
  children shrink between the two proposals.

**The ruling.** Adopt all three. The second pass runs only in placement and
only when the cross proposal is nil; its allocations are stored, its size is
not reported. The `ZStack` rule uses the node's **stored bounds size** as B.

**Coupled to `CN-J`, measured.** The `ZStack` rule is SwiftUI's only when a
`ZStack` is placed at its own answer. Today's native root is placed at the full
window whatever it answers; with the rule and without `CN-J`, a `ZStack` root
put its union at the window's top-left and **14 more tests went red** in the
first staged run (the overlay, clip, `onTap` and hover tests whose roots are
`ZStack`s, e.g. `aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState`: primary at
(0, 0) instead of (20, 20)). So the second-pass clause is lane 1's and the
`ZStack` clause lands with `CN-J` in lane 4.

**Kernel-caller consequence.** `computeNativeLayout(root:proposal:in:)` with
bounds **larger** than the root's answer now puts a `ZStack` root's union at the
bounds' origin. Three kernel tests do exactly that and change in lane 4
(`aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndCentresEachChild`,
`aNativeOverlayPlacesEveryChildAtTheRequestedAlignment`,
`everyProposalAlignmentPlacesAnOverlayChildAtItsNamedPosition`); the lane
rebuilds each with bounds equal to the answer and a smaller child aligned inside
a larger sibling (probe A3's shape), so the nine alignments stay distinct.

**What it costs if wrong.** A greedy child in a nil-proposed stack stays at its
ideal instead of matching its widest sibling (the common `VStack` of labels and
a `.frame(maxWidth: .infinity)` divider); a `ZStack` whose children shrink when
re-proposed sits off-centre by half the shrinkage.

**Lane 4, as built** (`1ae17cc`; record §17). The `ZStack` clause as ruled:
`placeNative`'s `.overlay` case measures each child at the stored bounds' size,
aligns its answer within the union at the bounds' origin, and passes the
bounds' size as the child's placement proposal. The kernel-caller tests were
rebuilt at bounds equal to the answer. The branching tree's third count moved
with it, re-derived by hand: 64 calls / 51 hits / 90 misses (B, placed at
100×50, now proposes its children that size). Mutations M4a and M4b in record
§17.

---

## CN-F — an infinite proposal is answered with infinity by a frame, a spacer and a scroll viewport (reverses `FR-B`)

**The finding.** SwiftUI answers ∞ at ∞ for `.frame(maxWidth: .infinity)`
(D12), for a spacer (contract probe E) and for a `ScrollView` on its scrolling
axis (SC1 at inf×inf). `CN-B`'s flexibility probe asks every child at main ∞,
so a kernel that answers the child there reports a greedy frame as rigid.

**Why `FR-B`'s reason no longer holds.** `FR-B` kept `proposal.isFinite`
because an infinite measurement would reach `LayoutRect`. After `CN-B` the
built-in producers of an infinite proposal are measurement probes; placement
proposals are allocations (finite whenever the stack's own proposal is), a
frame places at a clamp of its finite proposal, a viewport offers nil, and the
root is finite. Checkpoint 3 still traps a non-finite rect, so a custom layout
that places at ∞ traps exactly where SwiftUI crashes (D12's recorded
`view origin is invalid`; this round's K4f reproduced the same crash, which is
why the probe measures such arms without placing them).

**The ruling.** Drop `proposal.isFinite` from `spacerLength` (lane 1), from
`framedSize`'s greedy gate and from `resolvedViewportDimension` on the scrolling
axis (lane 2). `aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` is
replaced by a test asserting the three infinite answers.

**Measured.** No stage of the staged prototype trapped; lane 2's stage adds
`aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` to the red list.

**What it costs if wrong.** An infinite rect reaches checkpoint 3 and traps
with the node named. That is louder than `FR-B`'s silent under-expansion, and
no built-in path is known to reach it; lane 2 adds an exit test for the one
path that can (a custom layout placing at ∞).

**Lane 2, as built** (`63387f6`; record §17).

- **G4 was green on arrival** after lane 1 (under `FR-B` a and the frame tie at
  flexibility 0 and declaration order serves the frame 180 anyway), so it
  cannot see this ruling. The probe gained revision 5's **G4r** (the frame
  declared first: still 180, a at 180) and **G4f** (beside a bounded 0..80
  sibling: a 80 served first, the frame 120), both red before the lane; they
  are the evidence that a greedy frame over a fixed child answers more than
  its child at main ∞.
- **Test 2.4 is the frame form**, not a citation of `anInfiniteStoredRectTraps`
  (whose echo leaf answered ∞ before this ruling): red before, trapping after.
- **Checkpoint 3's width term alone is unpinned**, measured: removing it
  reddens nothing, because on every path that produces an ∞-wide rect the x
  is ∞ or NaN too (a centred child, a top-leading record) and the x term traps
  with the same message. Removing both terms reddens 2.4 and two older trap
  tests. The ruling's cost statement ("traps with the node named") holds; the
  pin is the x term's.

---

## CN-G — `aspectRatio` answers its child's answer to the ratio-shaped proposal; infinity is a concrete axis

**The finding.** AR1: a fixed 168×95 child under `.aspectRatio(16/9, .fit)` at
500×300 is proposed 500×281.25 and the modifier answers **168×95**; AR2 at nil
answers 168×95 with the child proposed nil×nil; AR3, a child that takes the
offer, answers the ratio size 500×281.25; AR4 keeps it 168×95 inside an
`HStack`. Critic round 1 added the other branches:

- one axis: 500×nil proposes 500×281.25 (K4, K4c), nil×300 proposes 533.33×300
  (K4b), and the modifier answers the child (168×95 fixed, 500×281.25 flexible);
- **∞ is a concrete axis, not nil**: inf×inf proposes inf×inf (K4d `.fit`),
  500×inf proposes 500×281.25 (K4e, K4g), `.fill` at 500×inf proposes inf×inf
  (K4h) — exactly the two-axis `width / ratio <= height` (`>=` for `.fill`)
  comparison with ∞ in it; a flexible child at inf×inf answers inf×inf (K4f);
- a negative ratio at 100×100 proposes 100×−100 (K4i, K4j) and answers the
  child (a clamping leaf 100×0; a fixed one 30×30).

The kernel answers the ratio size whatever the child does, and treats ∞ as nil
(`aspectRatioSize` filters `isFinite`).

**The ruling.** At nil×nil the modifier proposes nil×nil. Otherwise it proposes
the ratio-shaped size from the two-axis or one-axis branch, **with ∞ taken as a
concrete value** (no `isFinite` filter), answers the child's answer, and places
the child at that answer. The intrinsic nil×nil branch of `aspectRatioSize` is
no longer reached and goes. Closes `SA-N` item 3.

**Why here and not in task 7.** It was task 7's (`SA-N` item 3), but `CN-B`
makes it visible: staged without it (lane 1 alone), the preview's
`PreviewToggle` (`Rectangle(168×95).aspectRatio(16/9)` in the bottom `HStack`)
is offered a finite allocation and grows to 496×279 — **155 248 differing
pixels** per preview image. With it (lane 2), **188 pixels**, the toggle
168×94 → 168×95.

**The trap the design handed to the lane, diagnosed.** Under the prototype
`aNegativeAspectRatioIsAcceptedOnEveryProposedBranch` exits with SIGTRAP. No
checkpoint fires: the SIGTRAP is **the test's own `precondition`**. Its child is
a fixed 10×10 leaf and it asserts the modifier answers the ratio size
(100×−50 and so on). Those numbers come from input-validation probe P8/P8b,
whose child was `Color`, which **takes the offer**. Under `CN-G` a fixed child
answers 10×10 (measured: all four arms 10×10), and a proposal-echoing child
answers exactly the P8 numbers (measured: 100×−50, −160×80, −160×80,
100×−50). `aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes` has the
same fixture and the same cause. **The rule stands; the fixtures change**: both
tests' child becomes a proposal-echoing leaf (the kernel's `Color`), which is
what P8 measured, and K4j (a fixed child keeps its own size at a negative
ratio) becomes an arm of test 2.5. `SA-K` item 2 (negative ratios accepted) is
unchanged.

**What it costs if wrong.** A fixed child under `.aspectRatio` sizes by its own
answer rather than the ratio; `aspectRatioFitInscribes…`/`…Fill…` flip and pin
AR1/AR3.

**Lane 2, as built** (`63387f6`; record §17). As ruled: the preview's toggle is
168×95 (188 pixels per 1024 image, `CN-S` row 2), both negative-ratio
acceptance tests pass unchanged with an echo child, and the integration
fit/fill tests pin AR1 (the fixed child keeps 20×10; the proposals differ).

---

## CN-H — platform-default spacing: 8 between views, none at a spacer's edge; explicit spacing verbatim

**The finding.** Horizontally every measured pair is 8 (S: rect, color, custom
layout, text, image, nested stack, button, padded text, toggle). Vertically
non-text pairs are 8; a **Text edge is font-derived**: text|text 0, rect|text
4.74, text|rect 8.15, image|image 0, toggle|toggle 6. An empty conditional adds
nothing (G23). **No default spacing is inserted next to a spacer** (SP2 48 =
SP1; SP3 40), but **explicit spacing is** (SP4 80).

**Amended, critic round 1: the rule is per edge and sees through wrappers.**
Against the control K3 (48):

- a spacer's zero spacing survives `.padding(0)` (K3a 40), a frame (K3b 40,
  K3q 50), the overlay primary (K3c 40), `layoutPriority` (K3d 40), `fixedSize`
  (K3e 40), `aspectRatio` (K3f 40) and a `ZStack` all of whose children are
  spacers (K3g, K3l 40);
- a **non-zero padding inset gives that edge default spacing** again (K3m 64 =
  20+8+8+8+20; K3n 52 with only the leading edge padded; K3o 40, a cross-axis
  edge; K3p 52 vertically);
- a `ZStack` with a non-spacer child (K3j, K3k 56), a nested stack (K3h 56) and a
  spacer on an overlay's **content** side (K3i 56) get default spacing.

The design's `isNativeSpacer` (bare or under `layoutPriority` only) would have
put 8 in K3a, K3b, K3c, K3e, K3f and K3g.

**The ruling.** `HStack`/`VStack` take `spacing: Pixels? = nil`. The kernel's
`newNativeLinearStack` takes `spacing: Double?`; a number is used for every gap;
nil means, per adjacent pair, **0 if the earlier child's trailing edge or the
later child's leading edge is a zero-spacing edge**, else
`ProposalSpacing.platformDefault`. A node's leading/trailing zero-spacing edges
(along the stack's axis) are: both for a spacer; the child's for
`layoutPriority`, `frame`, `fixedSize`, `aspectRatio` and `overlayAttachment`
(its primary); the child's AND an inset of exactly 0 on that edge for `padding`;
for an `overlay` node with at least one child, the AND of its children's; none
for anything else (**superseded for nested stacks, custom layouts and empty
containers by the verifier-round amendment below**). `ProposalScrollView`'s lowering of several children passes
nil. **Not adopted:** the text-edge vertical values. MetalUI's `ProposalText`
has no font metrics in the kernel and no spacing preference channel; it gets 8
(a divergence, owner task 11 with baseline alignment).

**Measured** (staged prototype): K3a 40, K3b 40, K3c 40, K3m 64, K3n 52, K3g 40,
K3j 56, K3h 56, K3i 56, each the probe's number; the same arms read 56/56/56/64/
60/56/56/56/56 before the lane.

**What it costs if wrong.** A `VStack` of `ProposalText`s is 8pt per gap
looser than SwiftUI's; two labels in one `VStack` differ by one gap. Recorded,
not pinned by a SwiftUI-disagreeing test (a pin would have to assert 8 against
a probe that reads 0 — it is pinned as MetalUI's rule with the probe numbers in
its doc comment).

**Lane 3, as built** (`f916d1c`; record §17). As ruled. `solveLinearStack`'s
total and the placement cursor both read one private `stackGaps(_:axis:spacing:)`;
the walk is `zeroSpacingEdges(_:axis:)`, an exhaustive switch recomputed per
solve (no stored property). Every K3 arm reads the probe's number, and the per-arm
mutations of test 3.2 moved the arms the spec named (the `isNativeSpacer`
mutant also moves K3l, K3o, K3q, K3n and K3p). **One clause was unpinned and
unprobed:** `ProposalScrollView`'s lowering with `nil` rather than an explicit 8
differs only beside a spacer, and lowering with 8 left the suite green. Probe
revision 7 (SC5c/SC5) shows SwiftUI's vertical `ScrollView{a; Spacer(minLength:
0); b}` puts b 20 below a, against 28 without the spacer, so the clause is
SwiftUI's; test 3.1 carries the SC5 arm, red under that mutant. The horizontal
arm cannot discriminate (the implicit stack is proposed 200 tall and the greedy
spacer absorbs any gap).

**Amended, lane 3's verifier round: "none for anything else" was unprobed and
wrong.** Its only evidence was K3h, a CROSS-axis `VStack{Spacer}`. Probe
revision 8 (the V group, same method, controls K3 48, SP3 40 and the non-spacer
arms V1j, V3c, V3g, V4c 56) reads:

- a spacer's zero edges belong to the axis of the stack that orients it (its
  `CN-C` mark), or to both axes when no stack does: `VStack{sp; c}` (V1d),
  `VStack{sp; sp}` (V1h), `Pass{VStack{sp}}` (V3h), `ZStack{VStack{sp}}` (V7h)
  are default (56) between two views of an `HStack`, while `Pass{sp}` (V3) and
  `ZStack{sp}` (K3g) are zero (40);
- a **same-axis** nested stack takes its first child's leading edge and its last
  child's trailing edge, whatever its own spacing: V1 40, V1b `HStack{sp; c}` 48
  with c at 20, V1c `HStack{c; sp}` 48 with c at 28, V1e vertically 20×40, V1i
  `HStack(spacing: 4){sp; c}` 52, V1k 60;
- a **cross-axis** nested stack and a **custom layout** (a `Layout` overriding
  only the two required methods) are zero on an edge when ANY child is: V3b
  `Pass{sp; c}`, V3e `Pass{c; sp}`, V7b `VStack{ZStack{sp}; c}`, V7d
  `VStack{c; HStack{sp}}`, V7i: 40 each; per edge, V3f
  `Pass{sp.padding(.leading, 4); c}` 52 (8 before, 0 after);
- a `ZStack` stays AND per edge (V7j 40, V7k `ZStack{sp.padding(.leading, 4);
  sp}` 52);
- **empty** stacks, custom layouts and `ZStack`s (an `if false` included) are
  zero: V1f, V1g, V3d, V4, V4b, 40 each;
- a `ScrollView` is default whatever its content (V8, both axes, 56 like V8c);
- a padding wrapper sits after the gap its padded edge keeps: V6
  `.padding(.leading, 4)` at x 28, V6c `.padding(.trailing, 4)` at x 20.

**The amended walk** (`zeroSpacingEdges`): a spacer is zero on both edges when
unmarked or marked along the query axis, else neither; wrappers and `padding`
as before; a linear stack along the axis → (first child's leading, last child's
trailing); a linear stack across the axis or a `.custom` node → per edge OR
over its children; `overlay` → per edge AND over its children; each of those
three with no children → both; a leaf or scroll viewport → neither. **Adopted,
not recorded as a divergence**: every arm is a closed rule with no font or
preference channel, and the walk stays an exhaustive switch recomputed per
solve. Test 3.6 (`defaultSpacingBesideANestedContainerFollowsItsChildrensEdges`)
carries every V arm; test 3.2 gains V6/V6c.

**Measured.** Before the amendment the kernel read 56 for V1, V1b, V3, V3d, V4
and 20×56 for V1e (the verifier's figures); 3.6 was red with 46 issues at
`dcd509d` and is green at `8a4a491`. The mutations are in record §17.

**What it costs if wrong.** One 8pt gap beside a nested container that holds or
is next to a spacer. The one unprobed kernel shape left is a custom layout's
**own** spacing preference: `ProposalLayout` has no `spacing` requirement, so
every custom layout behaves as SwiftUI's default `Layout.spacing` does (V3).

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

**Amended, critic round 1: the inert row is not retired.** The deprecated
initializer still accepts `.leading` for an `HStack` and uses only the vertical
factor. CLAUDE.md's inert row "`HStack`/`VStack`'s `alignment:` main-axis half"
stays, re-worded at the Docs phase to name the deprecated
`init(spacing:alignment:content:)`, until that initializer is deleted.

**What it costs if wrong.** An external caller writing the old order gets a
deprecation warning, and one writing `HStack(alignment: .leading)` in the new
order a compile error — SwiftUI's own error. Three typecheck guards pin both and
the deprecation.

**Lane 3, as built** (`f916d1c`; record §17). As ruled, the two enums in
`Sources/MetalUI/StackAlignment.swift` with internal `proposalAlignment`
mappings and internal factor-reading initializers used only by the deprecated
initializers. `HStack.spacing`/`VStack.spacing` are `Pixels?` and `alignment`
the typed enum. Guard G2's mutation (swap the new initializer's parameters)
also breaks `MetalUI`'s own forwarding call and test 3.4's call site; both were
moved to the mutant order for that run so the guard itself could be observed red.

---

## CN-J — a native root is placed centred at its own answer

**The finding.** R1 and R2: a hosting view proposes its bounds and places a
58×20 root at (21, 40) in 100×100; a greedy root fills (R control). A root's
overlay and background content is proposed the root's size, not the host's
(R3, R4: 58×20). The kernel stores the root at the full window and a root stack
packs from the leading edge (`hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`
pins x 28).

**The ruling.** `Frame.computeRootLayout` measures a native root at the window
proposal and places it at `((w − answer.w) / 2, (h − answer.h) / 2)` at its
answer, in one native run: a new `LayoutTree.computeNativeLayout(root:proposal:centredIn:)`.
The legacy root is untouched. Lands in lane 4 with `CN-E`'s `ZStack` clause.

**Measured.** The preview's root is a greedy `ZStack` and did not move at
stage 4. `fixedSizeModifierWithholdsOnlyItsSelectedAxisFromTheChildProposal`
goes red at stage 4: its root `ZStack` now answers 30×10, is placed at 30×10,
and (by `CN-E`) re-proposes its child (nil, 10) where the test expects
(nil, 80). That is the probe's rule, and the lane updates the expectation.

**What it costs if wrong.** A small native root sits in the window's centre
instead of its top-left; loud, and pinned by R1's numbers.

**Lane 4, as built** (`1ae17cc`; record §17). As ruled, as a new public
`computeNativeLayout(root:proposal:centredIn:)`. The root is centred only by
`Frame.computeRootLayout`; `computeNativeLayout(root:proposal:in:)` still
places at the caller's bounds. Nineteen existing tests moved: thirteen on the
stage-4 list and six written or reshaped after the prototype (lane 1's
`.fixedSize` wrapping of the ideal-frame tests, lanes 2–3's `.fixedSize()`
roots). All six moved by centring alone. One of the thirteen,
`aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI`, lost its
discrimination under centring (an 80pt and a 40pt frame put the leaf at the
same x). A 200pt sibling restored it, and a filtered instrument check shows it.

**Verifier round** (`cdd3c74`; record §17). The centred entry was a copy of
the `in:` entry's run bracket, and no test covered that copy (verifier V8–V10
stayed green). Both entries now share one private `runNativeLayout`, and the
existing bracket, run-lifetime and work-record tests redden under each
mutation. R1's placement proposal ([100×100]) now has its own arm in
`aNativeRootIsCentredAtItsAnswer`. CN-E's "B as the child's placement
proposal" is pinned by `aZStackPlacesEachChildWithItsOwnSizeAsTheProposal`
(Z1 [30×20], Z4 [60×40]).

---

## CN-K — overlay and background content: several views are a centred `ZStack`, none is nothing, `.background` takes content and sits beneath for hits

**The finding.** A10, K5a, K5b: two views in one `.overlay` lay out as a
`ZStack`, itself proposed the primary's size. **Amended, critic round 1:** that
implicit `ZStack` is **centred whatever the modifier's alignment**; the
alignment only positions it (K5g `.topLeading`: the half-width leaf at
(2.5, 5) inside a union at (0, 0), not (0, 0); K5h `.background(alignment:
.bottomTrailing)`: union at (30, 20), leaf at (32.5, 25); K5c, an explicit
`ZStack`, the same). The content is **placed at the primary's size as its
proposal**, positioned by its answer (K5: a half-width leaf's only placement
proposal is 60×40; K5d: an `HStack` in an overlay is re-solved at 60×40, its
half-width child placed at 40×40). A11/A11b: an empty conditional in `.overlay`
or `.background` leaves the primary alone. A9: `.background(alignment:content:)`
proposes the primary's size and aligns like an overlay. Hits
(`swiftui-overlay-presentation.swift`): a click over a view and its
`.background` content reaches **the view** (H1 centre: primary 1, background 0);
outside the view it reaches the background (H1 edge); an overlay takes both
(H2). A view **without** a gesture still blocks the background's gesture (H3
centre 0).

Today a non-single overlay traps (`precondition` in
`NativeOverlayModifier.swift:73`), and the proposal `.background` takes only a
`ColorToken`.

**The critic's proposed amendment is rejected.** Critic finding 2 read K5a/K5b
as "the attachment places its content at the content's own answer". K5 (one
leaf: placed at 60×40, not 30×10) and K5d (an `HStack` re-solved at 60×40, not
at its 40×20 answer) refute that; the kernel's `overlayAttachment` already
places at the primary's size, and what K5a/K5b show is the `ZStack` placement
rule of `CN-E`. Measured on the staged prototype: with `CN-E`'s `ZStack` clause
and no attachment change, K5a, Z1 and K5d read the probe's rects (K5a leaf at
x 18 and Z1 at x 3 where SwiftUI reads 17.5 and 2.5: the kernel's stored rects
are rounded, `roundLayout`; the lane's tests use integral arms).

**The ruling.** `OverlayModifier` lowers several overlay nodes to one kernel
`overlay` node **with alignment `.center`**, then the attachment with the
modifier's alignment; zero nodes to the primary alone (no attachment node). New
`.background(alignment:content:)` on `ProposalElementGroup`, returning a
`BackgroundModifier` that registers the same lowering, **prepaints its content
before the primary** (so the primary's hitbox registers later and ranks above
it in `topmostOpaqueHitbox`, `Hitbox.swift`) and **paints its content before
the primary**. Its content numbers under `.child(of: id, at: -1)`, exactly as
`MC-P` numbers an overlay's. The primary side keeps its one-node precondition (a
primary is the view being modified; SwiftUI has no zero-view receiver).

**H3 is a recorded difference, not adopted.** A MetalUI element without
`onClick`/`onTap` registers no opaque hitbox, so a click over a non-clickable
primary reaches a clickable background beneath it; SwiftUI's primary blocks.
That is the kind of difference divergence 23 records for overlays; the Docs
phase numbers it.

**What it costs if wrong.** An overlay of a conditional stops trapping and
starts drawing nothing, which is the SwiftUI answer; a multi-view overlay's
placement is pinned by K5a/K5g's numbers; a background whose content registered
last would take the primary's clicks while painting beneath it — pinned by a
click test and its prepaint-order mutation.

**Lane 4, as built** (`1ae17cc`; record §17). As ruled. `BackgroundModifier`
lives in `Sources/MetalUI/NativeBackgroundModifier.swift`, with the shared
lowering. The overlay side's one-node precondition is gone from both
modifiers; the primary's stays, with the modifier's name in its message.
Mutations M2, M3, M5–M8 each redden only their own test (record §17).

---

## CN-L — a native node registered under two parents traps (`MC-G` hole 4)

**The finding.** No SwiftUI spelling reaches it (a view value has no node id).
`aNativeNodeRegisteredTwiceIsNotRejected` pins the hole wrong on purpose and
records that a duplicate-parent precondition truncates the suite at that test.

**The ruling.** The native registrars record each child's parent and trap on a
second one, or on a child listed twice in one parent, with a message naming
`MC-G` hole 4. `reset(generation:)` clears the record. Legacy `newNode` is not
checked (outside the hole, unmeasured). The pin becomes an exit test **before**
the precondition lands.

**Prototyped, critic round 1** (staged prototype, stages 4 and 5): a parent
record in every native registrar with children, cleared by `reset`. With the pin
skipped (as its exit-test replacement would be), the unfiltered suite ran to its
summary line; **no other test tripped the trap** (the stage-4 red list has no
test the other lane-4 rulings do not explain). Scratch exit tests: a leaf listed
twice in one stack exits with failure; one leaf under two frames exits with
failure; one leaf under a frame, `reset(generation: 1)`, then a fresh leaf under
a fresh frame at the same indices exits with **success** — so the record is
cleared (without the clear, index 0 would still hold its old parent and trap).

**What it costs if wrong.** A real tree that reuses a native node traps where it
used to lay out one of its two slots; no such tree exists in `Sources/`, and the
unfiltered suite has none either.

**Lane 4, as built** (`1ae17cc`; record §17). As ruled: a stored
`nativeParents: [Int: Int]`, written by `recordParent(_:of:)` after
`appendNode` in the ten native registrars with children, and cleared by
`reset`. The suite ran after `swift package clean`. The pin became the exit
test in `400e844`, before the precondition landed in `1ae17cc`. No other test
tripped the trap. **Measured:** without the clear in `reset` (M9b), the
unfiltered suite truncates in-process at
`aResetTreeMeasuresItsNewRegistrationsFromScratch`, which is an existing
test's shape-13 truncation. Test 4.9's reset arm is red only when it runs
filtered.

**Verifier round** (`cdd3c74`). Test 4.9 reaches only the stack and frame
sites, so deleting `recordParent` from the other eight left the suite green
(V7). `aNativeRegistrarWithChildrenRejectsANodeThatAlreadyHasAParent` now has
one exit arm per registrar with children, ten in all, and V7 reddens its eight
arms.

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
border narrows from 856 to 520 wide; each preview image reads 1 109 differing
pixels at stage 4 against lane 2's 188)
and the default spacing of `CN-H` for the lowering; the other two rules are
already the kernel's and gain pins. **Two-axis scrolling is deferred to task
10**: `ScrollState` holds one offset, a scroll hitbox one axis and the indicator
one track, and SCG2's centring rule has nothing to attach to until they do.

**What it costs if wrong.** A proposal scroll view is as wide as its content on
its cross axis rather than as its parent; the preview shows it.

**Lane 4, as built** (`1ae17cc`; record §17). As ruled:
`scrollViewportSize(axis:proposal:content:)`. The 1024 preview's scene
differs from lane 3's only in the scroll view's 48 widths, 856 → 520 (record
§17). Tests 4.12 and 4.13 were green on arrival as the spec said, and their
mutations (M12, M13) redden them.

---

## CN-N — a legacy frame over exactly one node lowers to a one-cell stack, and overflows both axes (closes `FR-N`)

**The finding.** `FR-N`: a single flex node squeezes an oversized child on its
main axis and overflows the cross axis, where SwiftUI's A5 (frame-semantics
probe) overflows both, 200×160 at (−70, −60) in a 60×40 frame.

**Prototypes.**

- *Every* frame layer lowered to `display: .stack` (design round): 5 red tests /
  8 issues, three of them frames over a **two-member** `Component`, whose members
  were layered instead of laid out as a row.
- **The ruling's own lowering, exactly one node** (critic round 1, stage 5 of
  the staged prototype: `ModifierLayer.isFrame` set by both frame overloads; in
  `ModifiedElement.requestLayout`, before `animated`, a frame layer whose
  children number exactly one gets `display = .stack` and `justifyItems` from
  its `justifyContent`): **2 red tests**, both the ones meant to move —
  `aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows` and
  `aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink`. The three
  two-member `Component` tests stayed green, measured. All twelve demo images
  read the same as stage 4 (the demo has no legacy `.frame`).

**The ruling.** A frame layer whose content contributes **exactly one** node
registers with `display = .stack`, `alignItems` from the alignment's vertical
case and `justifyItems` from its horizontal case; with zero or several nodes it
keeps `FR-C`'s flex lowering. `ModifierLayer` gains an internal `isFrame` flag,
set by both frame overloads; the choice is made in `ModifiedElement.requestLayout`,
before `animated`, per layer (an outer layer's one child is the inner layer's
node, so a chain of frames lowers every layer). SwiftUI's G7 (component-
distribution probe) wraps **each** member of a two-member custom view in its own
frame; neither the row nor the stack is that answer, and the row is kept
because it is today's.

**Not examined by the prototype, and so stated as open for lane 5:** an
absolutely positioned child and a `ScrollView` inside a one-child legacy frame.
Lane 5 adds one test for each against today's answers before changing the
lowering, and a difference is a finding.

**What it costs if wrong.** A child with `.flexGrow` or `.alignSelf` inside a
single-child legacy frame loses them (a `Stack` ignores both). No test or demo
site writes that, and SwiftUI has neither.

**Lane 5, as built** (`c73706f`, `f21d626`; record §17). As ruled, with two
choices and one finding:

- **`justifyItems` is written by `FrameSpec.style()`'s one `switch`** over the
  nine cases, next to `justifyContent` and `alignItems`, on every frame layer;
  a flex row ignores it. `ModifierLayer.lowered(_:childCount:)` only sets
  `display = .stack`, since only `requestLayout` knows the node count. Deriving
  `justifyItems` from `justifyContent` there would have been a second mapping
  that a later `Self`-returning `.justifyContent` after the frame could feed
  values a stack has no counterpart for. The two hand-spelled oracle styles
  (`ModifiedElementTests`, `ModifierCompositionProofTests`) gained
  `justifyItems` and `display: .stack`, per their drift obligation. Mutation
  M10 (no `justifyItems` write) reddens 16 tests.
- **"Before `animated`" is not observable.** Mutation M11 (lower after
  `animated`) left the unfiltered suite green, and by reading it is
  equivalent: `animated` never assigns `display` (a snapping field passes
  through), and the `$anim` baseline's snapping fields are never read back
  (`AnimatedStyle.swift`'s note), so the only difference is a
  `StateTable.writeCount` write when a frame's node count changes between one
  and several. The order is kept as ruled, for the baseline to hold the style
  the layer registers with; it is a convention, not a pinned behaviour.
- **The inner-layer clause was unpinned** until mutation M12 ("lower only the
  outermost layer") left the suite green; 5.1 gained a frame under a padding
  and a frame under a second frame (child at (−66, 20) and (−60, 20)), and M12
  now reddens them (2 issues).
- **The open item is closed with no difference**: 5.6 (an absolutely
  positioned child, six arms) and 5.7 (a `ScrollView`, four arms, through a real
  `Window` with a wheel) took their answers at `8e1dfa7` and read identically
  after the lowering. A legacy frame never imposes its size on a scroll view,
  on either lowering: the viewport stays the content's height unless something
  else (a `Box` with a declared height) bounds it.
- **Verifier round.** Both overloads' lowering is now pinned (5.1's `D13`/`D14`
  arms; mutation V1 reddens them). The cost above is pinned as it stands by
  5.8, `aSingleChildLegacyFrameIgnoresItsChildsFlexGrowAndAlignSelf`, with
  its workaround, `width(fraction: 1)`, and it is a Docs-phase inert-table
  candidate (record §17).

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

**Lane 5, as built** (`c73706f`; record §17). As ruled. The three `percent:`
methods forward to their `fraction:` counterparts. Every call site moved: the
old 5.2 test (replaced), `ModifierTests`' three rows (renamed `…(fraction:)`);
doc comments in `Box.swift`, `Units.swift` and `ModifierTests.swift`'s header
re-worded. The remaining `percent:` hits in `Sources/` and `Tests/` are the
deprecated declarations, their doc comments, guard G4's fixture, and history
in comments. G4 printed its three diagnostics (`'width(percent:)' is
deprecated: renamed to 'width(fraction:)'` …) in the native run; mutation M7
(remove one `@available`) reddens it alone.
**Verifier round.** "Meaning unchanged" is now pinned: 5.2's arm F calls the
three deprecated spellings at 0.5 through a non-diagnosed generic shim and
requires their `fraction:` answers; mutation V8 (`percent * 100`) reddens it.

---

## CN-P — the legacy containers keep their algorithms; three divergences are pinned and owned by task 7

**The audit** (the spec's table). The legacy containers agree with SwiftUI on
centred cross-axis stacking (EP-8, A1/A2), `Stack`'s nine alignments and union
sizing (A3/A4), and disagree on:

1. **default spacing** — `Row`/`Column` gap 0, SwiftUI 8 (S);
2. **what a `Stack` offers a child** — fit-content, where `ZStack` offers its
   proposal (A5: a greedy child fills 100×80; a childless `Box` in a `Stack` is
   0×0, measured);
3. **a `ScrollView`'s cross axis** — the legacy viewport takes its parent's
   (stretch or declared), SwiftUI's takes its content's (SC2);
4. compression by CSS flex-shrink (proportional to base size) instead of
   flexibility order (G1), expansion only by `flexGrow`, no spacer.

**Measured.** Changing `Row`/`Column`'s default gap to 8 reddens **22 tests**
(listed in the spec's appendix) and 0 demo pixels (every demo stack spells its
gap), and would still disagree with SwiftUI next to text vertically (0) and has
no spacer to be zero beside.

**The ruling.** No legacy default changes. Items 1–3 get one characterization
test each that builds the legacy spelling and its proposal counterpart side by
side and `#require`s them to disagree by the probe's numbers; item 4 is
`FlexEngine`'s and is covered by its goldens. **Owner of all four: task 7**,
whose closing condition ("no production layout request may pass through the
legacy engine") removes them by lowering or deleting the legacy spellings; they
are recorded as divergences at integration with that owner.

**Why not adopt the horizontal gap now** (critic finding 14). It is 22 test edits
for 0 demo pixels on a container task 7 replaces; `Column` would stay at 0, so
`Row` and `Column` would disagree with each other; and a legacy `Row` ported to
`HStack` in task 7 gets 8 from `CN-H` anyway. The pin makes the difference
findable by name until then.

**Pin 5.4's mutation, replaced and measured.** The design's mutation set
`alignSelf .stretch` on `Stack` children, which the inert table says a `Stack`
ignores. Replacement: set the legacy `Stack` **container's** `alignItems` and
`justifyItems` to `.stretch` in `Stack.init`. Measured at `9e439cb` (staged
prototype, stage 0, environment switch): a sizeless `Box` in a 100×80 `Stack`
reads (50, 40) 0×0 without it and (0, 0) 100×80 with it, and the unfiltered
suite reddens 7 tests (`allNineAlignmentsMapToTheirPairAndTheNineAreDistinct`,
`aNestedHandlerWinsOverItsContainingStackToo`,
`aPressReleasedOverSomethingCoveringItIsNotAClick`,
`clippedAlsoClipsTheHitboxesInsideIt`, `stackDefaultsToCentreNotStretch`,
`stackWritesDisplayAndBothAlignmentFields`,
`theTopmostOfTwoOverlappingHandlersRuns`). Pin 5.4 must be among the tests it
reddens.

**What it costs if wrong.** A caller porting a legacy `Row {}` to `HStack {}`
gains 8pt gaps silently; the pin makes the difference findable by name.

**Lane 5, as built** (`1f56652`; record §17). The three pins are
`aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight`,
`aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` and
`aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents`
(`ContainerIntegrationTests.swift`), all green on arrival. Measured on the
lane's tree: the `Stack`-stretch mutation reddens **8** tests, the pin the
eighth, beside the design's seven; the `Row`/`Column` gap-8 mutation reddens
**25** — the design's 22, minus the replaced percentage test, plus 5.2, 5.3,
5.6 and 5.7, which build legacy rows; lane 4's cross-axis line reverted
reddens the pin and three lane-4 tests. Probe arms S, A5 and SC2 were re-run
2026-09-16 and read as recorded.

---

## CN-Q — deferrals, each with a reason and an owner

| item | why not here | owner |
|---|---|---|
| lowering `Row`/`Column`/`Stack`/`Box`/`ScrollView`/`Deferred` onto the kernel; switching the default demo root; the three `CN-P` divergences | `CN-A` | task 7 |
| **a windowed proposal `List`** (uniform `rowHeight`, `ScrollContext`, row identity, the `AXTable` records) — the layout half task 7's closing condition needs, since the default demo root contains `List` | windowing and identity are the `MP-`/`TB-`/`AB-L` rulings, a lane of their own; probe K6 fixes its layout answer (greedy: the proposal on each concrete axis, 0 on a nil axis) | **task 7** (moved from task 10 by `CN-T`) |
| SwiftUI `List` semantics beyond layout: `ForEach`, selection, non-uniform rows, rows outside the window reachable, divergences 14 and 32 | the plan's data-driven controls | task 10 |
| a greedy **finite** maximum and a **single-axis** infinite maximum on the legacy frame (`FR-E`, `FR-O`); a nil-axis frame under a stretching `Box` (`MC-Q` finding 7) | needs the parent's flex axis at registration: a pass-scoped value every legacy container would have to set (at least `Box`, `Stack`, `ScrollView`, `List`, `Deferred`, `EnvironmentScope`, `Component`, the root), none enforced, on a path task 7 deletes. The proposal path delivers it (FR-A, `CN-B` G4) | task 7 |
| legacy `.overlay` | `ModifiedElement` holds one subtree; a second is the `ModifiedContent` unification (`OM-` spec §9) | task 7 |
| a proposal `Deferred` (portal) | **measured, critic round 1**: SwiftUI's `.overlay` has neither of `Deferred`'s escapes — its content is clipped by an ancestor `.clipped()` (P1) and is not hoisted above a later sibling (P2; `.zIndex` hoists within one `ZStack`, P3) — and a presented `.sheet`/`.popover` is outside the presenting view's layout and render tree (P4, P5: never laid out, never drawn). So there is no layout-protocol algorithm to port; the portal's counterpart is presentation, which belongs with the root switch | task 7 |
| two-axis scrolling | `CN-M` | task 10 |
| text-edge vertical default spacing; `firstTextBaseline`/`lastTextBaseline` stack alignment | needs font metrics and baselines from `ProposalText` (`CN-H`) | task 11 |
| builder wrappers with zero or several nodes (`ProposalFrame { if flag {…} }`, `Padding`, `FixedSize`, `Background`, `OnTapModifier`) | SwiftUI has no builder frame; `Group` semantics (a modifier applies per view) is the composition audit | task 8 |
| `SA-N` item 4, padding places its child at the child's size | not a container; its pin is intact | task 7 |
| a non-clickable primary blocking a background's click (probe H3) | MetalUI's hit model (only `onClick`/`onTap` is opaque) is plan task 12's | task 12 |
| the release-window captures | `IOConsoleLocked` read `<true/>` at design time, again in critic round 1 | carried (`MC-J`) |

---

## CN-R — method: what was run, and where

- **Probes**, as in the header. `swiftui-stack-algorithms.swift` revisions
  `75b5f69`, `fbfc1d6`, the A11 revision and revision 4 (`cef0acd`, `f10e779`),
  each run twice under `/usr/bin/swift` with byte-identical output; each
  revision's output prefix identical to the previous revision's (revision 4:
  one relabelled line, X9). Every group has a control that differs from its
  arms. Harness defects found and fixed before recording: the `Probe` layout's
  own `sizeThatFits` is not always called, so placement re-reads it and a
  sentinel `-1x-1` marks an unmeasured arm; views containing only spacers or
  nothing are never laid out as hosting-view roots, so SPB reads them through a
  background leaf; SwiftUI traps placing an infinite answer, so K4d–K4h and K6e
  are measured without placement (`runMeasured`). In the overlay/presentation
  probe, `NSHostingView` shrank the window to fixed-size content until the
  harness gave it a 200×200 frame and empty sizing options.
- **The design round's P1 failures, re-run in isolation and explained.**
  `aNodeIDDoesNotSilentlyResolveAgainstAnotherFramesTree` and
  `everyFrameTakesADistinctTreeGeneration` (both reading every `Frame`'s tree
  generation as 0) were reproduced **on the unmodified baseline**, built
  incrementally over a build that had last compiled a prototype adding a stored
  property to `LayoutTree`; P1 built incrementally did not fail them, and P1
  after `swift package clean` did not either (13 red tests, 48 issues, the
  design's list minus those two). It is CLAUDE.md's cross-module stored-property
  hazard: `LayoutTree` is a public class in `MetalUILayout` read by `MetalUI`.
  **Every lane that adds a stored property to `LayoutTree` (`CN-C`'s marks,
  `CN-L`'s parent record) runs `swift package clean` before its suite.** P1's
  counts are superseded by the staged prototype's (`CN-B`).
- **The staged prototype** (critic round 1). One patch implementing every
  kernel and element change of `CN-B`…`CN-N`, with each ruling gated on a
  process-wide `CN_STAGE` environment value (1 = lane 1 … 5 = lane 5,
  cumulative) read once in a scratch `MetalUILayout` file, so one clean build
  served six unfiltered suite runs; exit tests inherit the environment. The
  kernel's `Double?` spacing was stood in for by a NaN sentinel (so
  `aNaNStackSpacingTraps` reads red at stages 3–5 and is not a lane change).
  Stage 0 read `Test run with 1311 tests … passed` (1303 plus 8 scratch tests)
  and **0 differing pixels in all twelve images against `9e439cb`'s**, which is
  the patch's own control. A first staged run placed `ZStack`s by `CN-E`'s rule
  from stage 1 and read 14 extra red tests there, all vanishing at stage 4
  (`CN-E`'s coupling note); the recorded stages 1–3 are the re-run with that
  clause at stage 4. Scratch tests printed the work, shaping, K5a/Z1/K5d,
  negative-ratio and K3 figures quoted above, and ran the `CN-L` exit tests.
- **Mutations taken on the prototype at stage 0**: `HStack`'s axis swapped
  (test 1.11's), 11 red tests (spec); the legacy `Stack` container stretched
  (pin 5.4's), 7 red tests (`CN-P`).
- **Legacy prototypes (design round)**: `Row`/`Column` default gap 8 (22 red);
  every frame layer as `display: .stack` (5 red / 8 issues).
- **Pixels**, the record §13/§16 harness rebuilt in scratch: `main.swift` up to
  `runDemo()` with its globals prefixed `SI`, rendered through a real `Window`
  over `FakePlatformWindow` at 1024×1024, ten images, plus two 560×560 images
  (the default demo and the preview) because the 1024 square never compresses
  the preview. Base `git archive 9e439cb` in scratch. Controls on the base:
  light vs dark 1 048 576; default vs modal 1 030 498; default vs animation
  210 027; f0 vs f3 0; preview light vs dark 1 048 576 — the same figures
  record §16 read.

---

## CN-S — what the demo comparison must read, per lane

Against `9e439cb`, cumulative, the twelve images of `CN-R`, measured on the
staged prototype at each stage:

| after lane | 8 legacy images + `small560-default` | `preview-*` (1024), each | `small560-preview` |
|---|---|---|---|
| 1 | 0, scene identical | **155 248**, bbox (84, 661)–(939, 939): `PreviewToggle` grows to 496×279 (G9/X13 allocation, `CN-G` not yet in) | **93 522** |
| 2 | 0 | **188**, bbox (264, 845)–(431, 865): the toggle 168×94 → 168×95 (AR1) | **64 199** |
| 3 | 0 | 188 (unchanged) | 64 199 (unchanged) |
| 4 | 0 | **1 109**, bbox (264, 212)–(939, 865): lane 2's rect plus the scroll border 856 → 520 wide (SC2) | **65 449** |
| 5 | 0 | 1 109 (unchanged) | 65 449 (unchanged) |

Each lane traces every moved rect of its row to a probe arm in its record. A
lane's figure that differs from this table is a finding, explained or fixed
before the lane closes.

**Which images are evidence for which lane** (critic finding 11):

- **The legacy images are not evidence for lanes 1–4.** No legacy image contains
  a native node (`demoContent()` names no proposal type; each lane re-checks with
  a grep), so a kernel change cannot move them and a zero there proves nothing
  about the lane's code. They are recorded to show the lane moved nothing else.
- **The preview images are the evidence for lanes 1, 2 and 4**, and their
  positive control is the moving figure itself (each of those lanes is expected
  to move them). **Lane 3 has no pixel evidence**: measured, stage 3 reads
  stage 2's figures in every image (no preview gap sits at a spacer's edge
  under default spacing), so a zero there proves nothing about `CN-H`; lane 3's
  evidence is its tests.
- **Lane 5 has no pixel evidence either.** The demo uses no legacy `.frame` and
  no `percent:`; the eight legacy images are shown to still read 0, and the
  harness's ability to see a legacy change is the base controls above (modal,
  theme, animation), not a lane-5 mutation.

The real release windows are captured only if `IOConsoleLocked` reads
`<false/>` at that lane's end.

---

## CN-T — task 6 stays open; the plan amendment this design proposes

**The question** (critic finding 4). `CN-A` names a windowed proposal `List` as
a prerequisite of task 7's root switch, the design's first `CN-Q` gave it to
task 10, and task 7's text says "No production layout request may pass through
the legacy engine after this task". The default demo root contains `List`, so
task 7 could not close before task 10. And task 6's title, "Replace
containers", is delivered for no legacy container.

**The ruling.**

1. **Ownership.** The windowed proposal `List` (layout, windowing,
   `ScrollContext`, row identity, its accessibility records) moves to **task 7**;
   task 10 keeps `List`'s SwiftUI semantics beyond layout (`CN-Q`).
2. **Task 6 is not ticked by this work.** The Docs phase adds a progress note
   saying what landed and proposes this amended task text, for the user to
   accept or not:

   > **6. Port SwiftUI's container algorithms to the proposal path and audit the
   > legacy containers.** Make `HStack`, `VStack`, `ZStack`, `Spacer`,
   > `.overlay`/`.background` content and `ProposalScrollView` agree with
   > SwiftUI's probed distribution, spacing, alignment, root placement and scroll
   > axes; audit `Row`, `Column`, `Stack`, `Box`, `ScrollView`, `List` and
   > `Deferred` against them, pin each difference, and hand the replacement of
   > the legacy spellings to task 7.

   and, for task 7, appends "including a windowed proposal `List` and a
   proposal portal for `Deferred`" to "Migrate the remaining elements off
   `FlexEngine`".
3. If the text is not amended, task 6 stays open until task 7 replaces the
   legacy containers, and says so in its progress note.

**What it costs if wrong.** A reader of the plan believes the containers are
replaced when they are not (if ticked), or task 7 cannot close (if `List` stays
with task 10). Both are prose, and the progress note states the facts either
way.

---

## CN-U — lanes split and merged to fit five verifiable lanes

**The question** (critic finding 10). The design's lane 1 carried six rulings,
16 new tests, ~20 changed tests and a rewrite; lanes 1–3 had no expected pixel
figures.

**The ruling.** Five lanes, in order (spec §6):

1. **Distribution** — `CN-B`, `CN-D`, `CN-E` (second pass), and the parts of
   `CN-C` (−∞ priority) and `CN-F` (spacer ∞) without which no distribution arm
   can be pinned.
2. **Spacer cross axis and minimum, infinite answers, aspect ratio** — the rest
   of `CN-C`, `CN-F` and `CN-G`.
3. **Spacing and typed alignments** — `CN-H`, `CN-I`.
4. **Root, `ZStack` placement, overlay/background content, duplicate
   registration, scroll axes** — `CN-J`, `CN-E`'s `ZStack` clause, `CN-K`,
   `CN-L`, `CN-M` (the design's lanes 3 and 4 merged; `CN-E`'s coupling note is
   why the `ZStack` clause moved here).
5. **Legacy** — `CN-N`, `CN-O`, `CN-P`.

Each has a staged-prototype red list and a pixel row (`CN-S`).

**Measured cost of the split.** Two existing tests change twice:
`measuringANativeTreeWritesNoRect` is red after lane 1 alone (157×91: an unmarked
spacer claims its cross proposal) and green again after lane 2; the branching
tree's literals read 47/51/66 after lane 1 and 44/50/63 after lane 2. And the
preview reads 155 248 pixels between lanes 1 and 2 (`CN-S`). Folding `CN-G`
into lane 1 would remove the last at the cost of the lane size the critic
objected to; the split is kept and the intermediate figures are expected, not
findings.

**What it costs if wrong.** One more pair of test edits and one intermediate
preview image that looks wrong on the branch, never on `master`.

---

## Critic round 1 — dispositions

| # | finding | disposition |
|---|---|---|
| 1 | default spacing beside a padded/framed/overlaid spacer | **Applied, and it went further.** Revision 4 adds K3a–K3q with the K3 control; the rule is per edge and a non-zero padding inset restores spacing (K3m, K3n), which "the same walk as `CN-C`" would have got wrong, and the walk differs from `CN-C`'s mark (overlay content, `ZStack`). `CN-H` amended; test 3.2 carries every K3 arm |
| 2 | `.overlay` places its content with the wrong proposal | **Probe applied; amendment rejected, a different fix taken.** K5, K5d refute "placed at the content's answer"; K5a/K5b/Z1–Z4 show the `ZStack` placement rule (`CN-E` amended) and K5g/K5h that the implicit `ZStack` is centred (`CN-K` amended). Tests 4.2 and 4.3 use a proposal-sensitive (half-width) child for `.overlay` and `.background` |
| 3 | `List` audit row never probed; no presentation arm | **Applied.** K6–K6f (greedy; no row laid out headlessly) rewrite the audit row; the overlay/presentation probe measures clipping, paint order and presentations (P1–P6), which settles `Deferred`'s deferral with evidence (`CN-Q`) |
| 4 | deferral order the plan cannot deliver; task 6 stays open | **Applied.** `CN-T`: `List`'s windowed layout to task 7, task 6 stays open, amended text proposed |
| 5 | CN-L, CN-K, CN-H never prototyped; lane 2's changed tests unmeasured | **Applied.** Staged prototype (`CN-R`); red lists per lane in the spec appendix; `CN-L` with `reset` clearing the record (`CN-L`) |
| 6 | P1's unexplained failures; counts from a possibly contended window | **Applied.** Reproduced on the unmodified baseline built incrementally; explained as the cross-module stored-property hazard; counts re-taken on a clean build (`CN-R`, `CN-B`) |
| 7 | eager probing unmeasured at a nil cross proposal; shaping uncounted | **Applied.** Depth 1–7 table in and out of a scroll viewport, and shaping counts (`CN-B`); lane-1 performance tests use hand-derived literals checked against those figures |
| 8 | aspect-ratio trap undiagnosed; ∞ unstated | **Applied.** The trap is the test's own precondition over a fixed child where P8 used `Color`; ∞ is concrete (K4d–K4h); K4/K4b/K4j join test 2.5 (`CN-G`) |
| 9 | background content can steal taps | **Applied.** Probe H1 measured; `BackgroundModifier` prepaints content before the primary; test 4.6 clicks over both, with the prepaint-order mutation (`CN-K`). H3 recorded as a difference owned by task 12 |
| 10 | lane 1 too large; no per-lane pixel figures | **Applied.** `CN-U`; per-lane figures for every image (`CN-S`) |
| 11 | positive control for zero images impossible on the legacy side | **Applied as the critic's second option.** `CN-S` states which images are and are not evidence for each lane |
| 12 | two CN-C arms over-read; three choices unprobed | **Applied.** K1, K2a–K2e in the probe; SP19's reading and the "not probed" paragraph rewritten (`CN-C`) |
| 13 | inert row not retired | **Applied.** `CN-I` keeps it, re-worded |
| 14 | three legacy divergences unowned; pin 5.4's mutation half inert | **Applied.** Task 7 owns all four; horizontal gap not adopted, with reasons; mutation replaced and measured, 7 red tests (`CN-P`) |
| 15 | CN-N's green claims rest on the wrong prototype | **Applied.** Exactly-one lowering prototyped: 2 red, the three `Component` tests green; absolute child and `ScrollView` inside a one-child frame stated open for lane 5 (`CN-N`) |
| 16 | smaller defects | **Applied.** Test 1.11's mutation red list named (11 tests, spec); test 4.12's `#require` replaced by a centring `ZStack` control; X9 relabelled in the probe; OS-dependence of call counts stated in this header |
