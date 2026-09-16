# SwiftUI alignment — decisions for completing the native layout kernel

These are the rulings for finishing plan task 2
(`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`). Task 2 adds a public
layout protocol, closes the boundary between the two layout engines, and makes
the proposal engine robust. The milestone's earlier work (`a15ec83..7cfcddc`,
record §09) shipped without a decisions doc. **This is the first one, and it
starts here, at the design stage.**

Prefixed **`SA-`** and **lettered** (`SA-A`, `SA-B`, …), per this repo's
convention. **A bare `SA-3` is a typo, not a citation.** The next unused letter
is `SA-V`.

Read alongside:

- `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`. It
  holds the three lanes, their API, tests and mutations.
- `docs/superpowers/specs/2026-09-12-native-layout-kernel-design.md`. Two of its
  sections are replaced by the spec above.
- `docs/record/09-swiftui-alignment.md`, whose "Hazards" list this design
  closes.
- The two committed probes under `docs/probes/`, whose headers carry their
  recorded output.

## How to read the letters

**Written at design time, before any lane runs.**

- **`SA-A`…`SA-M`** are decisions about the code. They are grouped by the lane
  that implements them:
  - protocol: `SA-A`…`SA-F`;
  - boundaries: `SA-G`…`SA-I`;
  - robustness: `SA-J`…`SA-M`.
- **`SA-N`** is what the probes found that this design deliberately does not
  fix.
- **`SA-O`**, **`SA-P`** and **`SA-Q`** are about method and the record: how
  the probes run, how sufficiency is proven, and which claims an earlier pass
  got wrong.
- **`SA-R`** amends the plan's item (e) criterion; lane 1 carries it.
- **`SA-S`** is the disposition of a critic's eighteen findings against
  `3bb1ca1`: what each changed, or why it was rejected. It was written in a
  third pass, after `SA-A`…`SA-Q`, and several of those rulings were revised in
  place by it; each revised ruling says so.

**Every ruling ends with a "Mutations" line reading _owed by lane N_.** The lane
that implements a ruling replaces that line with the mutations it ran and the
test names each one reddened. A ruling whose line still says "owed" has not been
mutation-tested, and must not be cited as proven.

## Where each number was measured, and which copy is authoritative

**Re-taken in this session, at `34e2841` on `feat/kernel-completion`, in the
worktree `/Users/maxburger/Developer/MetalUI-kernel`:**

- **Both SwiftUI probes, each run compiled and as a script.** The output in each
  probe's header is this session's run.
- **The suite:**
  - **995 tests passed**, twice. Each run included two uncommitted, env-gated
    probe tests, which were then deleted, so the committed count is **993**.
  - **97 goldens**.
  - **39 guards**: 19 `PhaseSeparationTests`, 10 `ErasureCompileGuards`, 5
    `ElementGroupTrapTests`, 2 `UnitSafetyTests` (3 hits, one a comment) and 3
    `AXNodeTests`.
- **The mixing behaviour** and the two temporary preconditions (`SA-G`).
- **The native depth bisection** (`SA-L`).
- **The `@testable` scoping experiment** and the skeleton typecheck (`SA-P`).

**Re-taken in a third pass the same day, after the critic's review** (`SA-S`):
- **both probes, each run compiled and as a script**, with new arms: J's run
  count and J2, K2, L2, L3, P8c. Every earlier recorded line reproduced;
- **the lane 1 skeleton**, rebuilt with lane 3's frame split, and every guard
  fixture re-typechecked at file scope in Swift 6 mode (`SA-P`);
- **the suite, twice**: 993 with lane 2's re-entrancy checks and the frame
  split applied temporarily, then 993 on clean sources (`SA-I`).

**Carried, not re-taken.** Legacy `LayoutContext.maxDepth`'s ceilings (107
levels on 1 MB, ~9.8 KB per level, debug) are quoted from its own doc comment
(`LayoutContext.swift:37-40`).

**An earlier pass of this same session** left an untracked draft of the spec and
both probes. Where this pass re-ran something that pass had also run, the
numbers agreed, and each place says so. The draft itself was rewritten, not
trusted. `SA-Q` lists what it got wrong.

**The probe headers are authoritative for SwiftUI figures.** Re-run a probe
there and correct its header first, then propagate here.

---

# The decisions

## SA-A — the protocol is `ProposalLayout`: two value requirements, no cache, no spacing, no alignment guides

**The choice.**

```swift
public protocol ProposalLayout: Sendable {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews)
}
```

It lives in `MetalUILayout`, is stored as a `NativeNode.custom(any ProposalLayout)`
case, and is registered by `LayoutTree.newNativeLayout(_:children:)`.

**Why this shape.**

- **The names.** The two method names follow SwiftUI's `Layout`, the reference
  the plan names. The types are MetalUI's own values: `ProposedSize`,
  `LayoutMeasurement`, `LayoutRect`.
- **Why it is not called `Layout`.** Nearly every `Element` in this repo
  declares a nested `struct Layout` for its layout state (`HStack.Layout`,
  `Padding.Layout`, …). Inside those types a protocol named `Layout` would be
  shadowed. `ProposalLayout` also matches this milestone's existing vocabulary:
  `ProposalElementGroup`, `ProposalAlignment`, `ProposedSize`.
- **Why `Sendable`.** `ProposalMeasureFunction` is already `@Sendable`, on the
  footing that the engine calls it from whatever thread it runs on
  (`Passes.swift`'s `requestLeaf` doc). A layout value is called from the same
  place and must meet the same bar. The skeleton check (`SA-P`) showed a struct
  nested inside a `@MainActor` function can conform without an annotation.
- **Why no `Cache` associated type and no `makeCache`/`updateCache`.** Unlike
  SwiftUI, the kernel memoizes every `(node, proposal)` pair per call (`SA-H`).
  A custom layout's `sizeThatFits` therefore runs once per distinct proposal,
  and so does every child measurement it asks for. The only repeated work a
  layout-owned cache would save is the layout's own derivation, redone in
  `placeSubviews`.
- **Why no `spacing` and no `explicitAlignment`.** MetalUI has no view-spacing
  preferences and no alignment guides for them to read.

**Probe.** `docs/probes/swiftui-layout-protocol-contract.swift`, arms A/B/C.
SwiftUI measures a child once per distinct proposal within one pass. The
positive control is arm B, where a second proposal costs one more call.

**What it costs if wrong.**

- **The cache.** A future grid or flow layout that derives column widths in
  `sizeThatFits` derives them again in `placeSubviews`. Adding a cache later
  cannot change the two requirements' signatures without breaking every
  conformer. It would have to be a second requirement pair with defaults that
  forward to the first.
- **The name.** A SwiftUI author types `Layout` and gets the nested struct.

**Mutations (lane 1, 2026-09-14, run at `00a1e22` in a detached `git worktree`
off `feat/kernel-completion`, one at a time, full `swift test --build-system
native --no-parallel` each, restore confirmed by `git status --short` clean;
every run read `Test run with 1010 tests in 1 suite`, so none truncated).**
- **Red before, on the skeleton** (`db6837e`: `.custom` measures `.zero`,
  proxies answer 0/false/`.zero`, `place` does nothing): all ten kernel tests
  in `ProposalLayoutTests.swift` and the integration test were red by
  assertion (the three exit tests on `.failure → .exitCode(0)`); lines quoted
  in that commit's message.
- **The per-call memo the protocol leans on:** the proxy's `sizeThatFits`
  clearing its own `(node, proposal)` entry before measuring reddens
  `aSubviewMeasuresOncePerDistinctProposalWithinOneRun` alone (`log.counts`
  `[1, 2, 3, 4]`, calls 4, against `[1, 1, 2, 2]` and 2).

---

## SA-B — the eleven built-in node kinds stay enum cases; only `custom` is protocol-backed

**The choice.** `NativeNode` keeps `leaf`, `overlay`, `overlayAttachment`,
`frame`, `padding`, `fixedSize`, `aspectRatio`, `layoutPriority`, `spacer`,
`scrollViewport` and `linearStack`. It gains `custom(any ProposalLayout)`, and
no built-in is ported onto the protocol.

**Why.**

- **The protocol's sufficiency is proven without moving the built-ins.** A
  test-only `ReferenceLinearStack: ProposalLayout`, written with a plain import,
  must reproduce the built-in stack's rects exactly on a discriminating tree.
- **Porting would put 59 tests' arithmetic (18 kernel, 41 integration) at risk
  for no user-visible gain.** It would also add an existential call per node on
  every frame.
- **Plan task 6 will re-examine the stack algorithm against SwiftUI anyway.**
  Spacer surplus, non-spacer expansion and priority redistribution are all
  open there, so porting now would port a moving target.

**What it costs if wrong.** Two implementations of the linear stack exist, the
built-in and the test reference. They can drift on any tree the equivalence test
does not build. The reference is test-only, so drift misleads a reader of the
reference and never a user.

**Mutations (lane 1, 2026-09-14, run at `00a1e22` in a detached `git worktree`
off `feat/kernel-completion`, one at a time, full `swift test --build-system
native --no-parallel` each, restore confirmed by `git status --short` clean;
every run read `Test run with 1010 tests in 1 suite`, so none truncated).**
- **Sufficiency.** `ReferenceLinearStack.swift` compiles with a plain
  `import MetalUICore` / `import MetalUILayout`, and
  `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects` reads every
  stored rect and measured width equal to the built-in's. Its two positive
  controls (`PriorityBlindLinearStack`, `SpacerBlindLinearStack`) are
  `try #require`d to differ, and do.
- **Geometry adjusted from the design** so no edge falls on x.5: B's 20×17 and
  11×9 leaves became 20×18 and 11×8 (a 17-tall B centred a 10-tall leaf at
  y + 3.5, and the min-0 spacer at y + 8.5). The three literal rects, derived by
  hand in the test's doc comment before the run, are A's priority-0 leaf
  (96, 19, 34, 11), B's second spacer (121, 46, 33, 0) and B's last leaf
  (159, 42, 11, 8).
- The spec's four mutations for this test: proxy `priority` returns 0 →
  `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects` and
  `aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules`; proxy
  `isSpacer` stops recursing through `layoutPriority` (a spacer node directly
  only) → the same two; the recorded child measured and placed at the parent's
  proposal instead of the record's → the equivalence test,
  `placingASubviewUsesItsAnswerToThePlacementProposalAndTheAnchor`,
  `aSubviewPlacedTwiceKeepsItsLastPlacement` and
  `aSubviewMeasuresOncePerDistinctProposalWithinOneRun`; `.custom`'s
  `placeSubviews` handed bounds with x = 0 → the equivalence test,
  `placingASubviewUsesItsAnswerToThePlacementProposalAndTheAnchor` and
  `aProposalLayoutContainerRendersThroughTheFramePipeline`.
- *Verifier's independent re-run, 2026-09-14 (record §09):* **not everything is
  compared.** Setting `ReferenceLinearStack`'s vertical cross offset to factor 0
  (F1) left the equivalence test green: the reference tree's vertical root has
  both children 157 wide, no overflow and no spacer, so only the **horizontal**
  stack path is proven equivalent. Open.

---

## SA-C — measurement CANNOT place: two proxy types, with a runtime backstop for an escaped placement proxy

**The choice.** `sizeThatFits` receives `MeasurementSubviews`, whose elements
have `priority`, `isSpacer` and `sizeThatFits(_:)`, and **no `place`**.
`placeSubviews` receives `PlacementSubviews`, whose elements add
`place(at:anchor:proposal:)`. No proxy has a public initializer.

A `PlacementSubview` smuggled out of its call still cannot write a rect from the
wrong place:

- `place` traps unless its token is the innermost active `placeSubviews` call:
  "a PlacementSubview was used outside its placeSubviews call";
- it traps while any measurement body is running: "a PlacementSubview was used
  during measurement".

Any proxy used after its run traps too: "a layout subview outlived its layout
run".

**Why.** The plan task says measurement must not be able to write rects, and the
2026-09-12 spec says "measurement never writes a rect". SwiftUI enforces the
same rule **dynamically only**.

**Probe.** Arm D: SwiftUI's `Subviews` is one type in both requirements, so
`place` inside `sizeThatFits` compiles, then traps at run time (exit 133,
SIGTRAP, no message). The positive control is every arm that places from
`placeSubviews` (I, J, K, M) and returns normally.

**Measurement.** Against a temporary skeleton of this exact API (`SA-P`), a
plain-import fixture calling `subviews[0].place(…)` inside `sizeThatFits` fails
with `value of type 'MeasurementSubview' has no member 'place'`.

**What it costs if wrong.**

- **The price is two nearly identical proxy pairs.** Their duplicated members
  (`priority`, `isSpacer`, `sizeThatFits`) are a maintenance cost.
- **A layout author writes one helper per pair**, or a generic one over a small
  internal protocol.
- **If the runtime backstops were dropped,** a stashed placement proxy could
  write a rect from inside a sibling's measurement. The cached measurement would
  then disagree with the stored rect, with no diagnostic.

**Mutations (lane 1, 2026-09-14, run at `00a1e22` in a detached `git worktree`
off `feat/kernel-completion`, one at a time, full `swift test --build-system
native --no-parallel` each, restore confirmed by `git status --short` clean;
every run read `Test run with 1010 tests in 1 suite`, so none truncated).**
- Delete the token precondition in `PlacementSubview.place` →
  `aPlacementSubviewUsedOutsideItsPlaceSubviewsCallTraps` (exits 0).
- Delete the `measureDepth` precondition →
  `aPlacementSubviewUsedDuringMeasurementTraps` (exits 0; the token check alone
  passes there, as designed).
- Delete the `isActive` precondition (`NativeLayoutRun.requireActive`) →
  `aSubviewUsedAfterItsLayoutRunTraps` (exits 0).
- Give `MeasurementSubview` a public `place(at:anchor:proposal:)` →
  `aMeasurementSubviewCannotBePlaced` (the fixture compiles).
- Give `MeasurementSubviews` a `public init()` →
  `subviewProxiesCannotBeConstructedOutsideTheKernel` (its `MeasurementSubviews`
  fixture compiles; the `PlacementSubview` fixture stays rejected).
- **Diagnostics re-printed from the real build** are the substrings the passing
  guards match: `value of type 'MeasurementSubview' has no member 'place'` and
  `'MeasurementSubviews' initializer is inaccessible due to 'internal'
  protection level` (likewise `'PlacementSubview'`).
- *Verifier's independent re-run, 2026-09-14 (record §09):* raising
  `measureDepth` only around `.custom`'s `sizeThatFits` (B1) left lane 1's tests
  green. The leaf-closure half of the bracket is pinned by lane 2's
  `writingARectDuringNativeMeasurementTraps` (`SA-H`); the built-in body half is
  not known to be pinned. Open.

---

## SA-D — the proxy surface is priority, spacer-ness and a cached measurement, each by the built-in stack's own rule

*Revised in the third pass (`SA-S` finding 1): `priority` now looks through
overlay attachments, and the built-in rule changes with it.*

**The choice.**

- **`priority`** is the value of a `layoutPriority` node that **is** the
  subview, looking through any depth of `.overlayAttachment` nodes to their
  primary child, else 0. The rule is `nativeLayoutPriority`'s
  (`LayoutTree.swift:710-713`), **which lane 1 changes to look through
  attachments**, so the proxy and the built-in stack keep one rule.
- **`isSpacer`** is true for a spacer node, directly or under any depth of
  `layoutPriority` nodes, and false through any other wrapper. The rule is
  `isNativeSpacer`'s (`:636-645`).
- **`sizeThatFits(_:)`** routes through the run's cache.
- **Nothing else is exposed:** no node id, children, style, stored rect,
  baselines-as-guides or spacing.

**Why.** The acceptance bar is "what the built-in stack needs", and the built-in
stack reads exactly these three things. The reference stack proves they are
enough (`SA-B`).

**Probes.**

- **Arm E and the arm L control:** a custom layout reads `priority` 2.5 back as
  2.5.
- **Arm L:** a `layoutPriority(2)` under `.frame` or `.padding` reads **0**, and
  the same modifier applied outermost reads 2.
- **Arm L2 (third pass)** refutes the second pass's generalisation, "SwiftUI's
  `priority` is the outermost modifier's alone". Priority 2 is **hidden** (0) by
  `.aspectRatio`, `.fixedSize` and `.frame(maxWidth:)`, and **survives** (2)
  `.overlay {}` (also twice), `.background {}`, `.opacity`, `.onTapGesture`,
  `.allowsHitTesting`, `.clipShape`, `.border`, `.offset` and `.id`. The line
  is between modifiers that lay their content out and modifiers that do not.
- **Mapped onto MetalUI's proposal modifiers.** `background`, `clip`, `border`,
  `opacity`, `allowsHitTesting` and `onTap` register no node
  (`NativeModifiedContent.swift`'s `nativeWrapperNode` returns the child), so
  priority already survives them. `frame`, `padding`, `aspectRatio` and
  `fixedSize` register a node, and hide it, as SwiftUI does. `.overlay`
  registers an `overlayAttachment` node (`NativeOverlayModifier.swift:36`) and
  hid it: `Rectangle().layoutPriority(2).overlay { … }` read 0 where SwiftUI
  reads 2, in the built-in stack as well as in the proposed proxy. That one is
  now fixed in both.
- **Arm L3 (third pass):** inside a container priority is 0, **except** a
  single-child `ZStack`, `HStack` or `VStack`, which reads its child's 2. A
  two-child stack reads 0 whichever child carries it, and a single-child
  **custom** layout reads 0. That exception is not adopted (`SA-N`); lane 1's
  proxy test pins MetalUI's single-child stack reading 0, wrong on purpose.
- **Arms E and E2:** SwiftUI exposes **no** spacer test. A `Spacer` reads
  priority −∞, but so does any view given `.layoutPriority(-.infinity)`. MetalUI
  exposes `isSpacer` because its stack reads spacer identity. SwiftUI's stack
  does not (it probes flexibility), and matching that is plan task 6's question,
  not this one's.

**Why fix the attachment now rather than carry it.** The proxy's `priority` is
new public API. If it shipped reading 0 through `.overlay`, correcting it in
task 6 would change what every outside layout reads, a behaviour change for
code this milestone invites people to write. The fix is one look-through in a
shared helper, pinned by `aLinearStackReadsPriorityThroughAnOverlayAttachment`.
`isNativeSpacer` is deliberately not given the same look-through: SwiftUI has
no spacer test to probe, and an overlaid spacer's behaviour is task 6's
non-spacer-expansion question.

**What it costs if wrong.**

- **`isSpacer` is a MetalUI-only notion.** If task 6 moves the built-in stack to
  flexibility probing, `isSpacer` becomes a public API with no built-in reader.
  It would then be carried or deprecated.
- **The attachment look-through changes a shipped built-in rule.** A tree that
  put a priority under `.overlay` and relied on it being ignored now allocates
  differently. No existing test builds one (lane 1's red run confirms or
  refutes that).
- **A layout that needs a child's baseline or identity cannot get one.** Adding a
  member later is additive.

**Mutations (lane 1, 2026-09-14, run at `00a1e22` in a detached `git worktree`
off `feat/kernel-completion`, one at a time, full `swift test --build-system
native --no-parallel` each, restore confirmed by `git status --short` clean;
every run read `Test run with 1010 tests in 1 suite`, so none truncated).**
- **The built-in rule change, red first** (`a5eeecd`):
  `aLinearStackReadsPriorityThroughAnOverlayAttachment` read
  `tree.layout(second) → (63, 27, 50, 10)` against (93, 27, 20, 10). With the
  look-through the suite read 994 passed, **so no existing test relied on an
  attachment hiding a priority** (this ruling's cost bullet, now measured).
- Remove the attachment case from `nativeLayoutPriority` →
  `aLinearStackReadsPriorityThroughAnOverlayAttachment` and
  `aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules`; the
  equivalence test stays green (its tree has no attachment).
- Proxy `priority` looks through one wrapper of any kind →
  `aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules` alone.
- `isNativeSpacer` also recurses through `frame` →
  `aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules` alone.
- Proxy `priority` returns 0, and proxy `isSpacer` direct-only: see `SA-B`.

---

## SA-E — placement: position, anchor and proposal; last placement wins; each subtree placed once, after `placeSubviews` returns; an unplaced subview is centred at the parent's proposal

*Revised in the third pass (`SA-S` finding 2): `place` records, and the kernel
places each subtree once afterwards. The second pass placed eagerly inside
`place`.*

**The choice.**

- **Where a placed subview lands.** `place(at:anchor:proposal:)` records a
  placement. After `placeSubviews` returns, the kernel stores the subview at its
  answer to **`proposal`**, offset from `position` by `anchor.factor × size`,
  and places the subview's subtree with that proposal.
- **Placed twice:** the last record wins, and the subtree is placed **once**.
- **Never placed:** the subview is measured at the **parent's** proposal and
  placed centred in the parent's `bounds`.
- **`bounds` is root-absolute**, the contract every stored rect already has.

**Probes.**

- **Arm K**, the proposal and the anchor. Parent bounds are (25, 25, 150, 150).
  A `Color` placed with a 70×40 proposal lands at (25, 25, 70, 40).
  `.center` at +100 with 30×20 lands at (110, 115, 30, 20), and
  `.bottomTrailing` at (95, 105, 30, 20). Both children are proposal-responsive,
  so a placement that ignored the proposal would differ.
- **Arm K2 (third pass)**, two anchors whose factors differ by axis:
  `.topTrailing` at +100 with 30×20 lands at (95, 125, 30, 20), and `.leading`
  at (125, 115, 30, 20). K's three anchors have equal factors on both axes, so
  only K2 can see a transposed factor pair.
- **Arm J**, placed twice. The child lands at (100, 100, 40, 40), the second
  placement's position and proposal. The first placement is never seen by the
  child: **its own `placeSubviews` ran once for the two `place` calls** (third
  pass, counted). J2 is that counter's positive control: a resize that moves
  the child brings the total to 2.
- **K's log order (third pass).** Each child's own `placeSubviews` logs after
  the parent's line, in the **reverse** of the order the parent called `place`.
  An eager recursion inside `place` would log in call order. So SwiftUI places
  subtrees after `placeSubviews` returns. MetalUI uses index order; nothing may
  rely on either order.
- **Arm I2**, never placed: a parent at (120, 70, 100, 100) proposed 100×100,
  with a fixed 30×30 child, lands at (155, 105, 30, 30), centred on (170, 120).
  That is neither the parent's origin nor the root origin.
  - **Arm I is not cited as evidence for centring.** Its child at
    (0, 0, 200, 200), inside a parent at (50, 50, 100, 100), is consistent with
    centring but equally with a placement at the root origin.
  - I2 also printed a first pass with the parent at (0, 0) and the child at
    (0, 0, 30, 30), which is not centred. Why was not investigated (`SA-N`).

**Why deferred, not eager.** An eager `place` re-runs a subtree per call: a
visible side effect in any custom child's `placeSubviews` that SwiftUI never
produces (J), and 2^depth work in a chain of layouts that each re-place a child.
Deferring also means a stashed `PlacementSubview` used after `placeSubviews`
returns meets the token check, whichever child is being placed at the time.

**What it costs if wrong.**

- **A forgotten subview is silent.** An author who forgets a subview gets a
  centred subview rather than a trap, the same silence SwiftUI gives. The
  alternative, a trap, would diverge from I2 for a mistake SwiftUI treats as
  legal.
- **A measurement asked inside `placeSubviews` does not place.** An author who
  expected `place` to measure and store immediately, and reads a stored rect
  back through some other channel mid-call, sees the old rect. No public API
  reads a stored rect.

**Mutations (lane 1, 2026-09-14, run at `00a1e22` in a detached `git worktree`
off `feat/kernel-completion`, one at a time, full `swift test --build-system
native --no-parallel` each, restore confirmed by `git status --short` clean;
every run read `Test run with 1010 tests in 1 suite`, so none truncated).**
- Anchor factors transposed h↔v in the recorded-child rect →
  `placingASubviewUsesItsAnswerToThePlacementProposalAndTheAnchor`, on exactly
  its topTrailing arm (read (125, 105)) and leading arm (read (110, 125)); the
  three equal-factor arms stay green, as designed.
- Unplaced children left at the zero rect →
  `anUnplacedSubviewIsCentredInItsParentAtTheParentsProposal`; placed at the
  bounds origin instead of centred → the same test, on its fixed-child arm only
  ((120, 70, 30, 30)); the proposal-echoing child fills the bounds either way.
- `place` keeps the first record → `aSubviewPlacedTwiceKeepsItsLastPlacement`.
- `place` measures and places the subtree eagerly on every call, the deferred
  loop skipping recorded children → `aSubviewPlacedTwicePlacesItsSubtreeOnce`
  (`log.placeRuns` 2 against 1).
- Record's proposal ignored, and `bounds.x` dropped: see `SA-B`.

---

## SA-F — registration: `newNativeLayout`, `requestNativeLayout`, `ProposalLayoutContainer` and `callAsFunction`; the alignment factors become public; nothing legacy is deprecated

**The choice.**

- **`LayoutTree.newNativeLayout(_:children:)`**, mirrored one-to-one by
  `LayoutPass.requestNativeLayout(_:children:)`.
- **`ProposalLayoutContainer<L: ProposalLayout, Content: ProposalElementGroup>`**,
  an `Element` and a `ProposalElementGroup`.
- **`extension ProposalLayout { @MainActor func callAsFunction(@ElementBuilder …) }`**,
  so `MyLayout() { … }` and `MyLayout { … }` both work.
- **`ProposalAlignment.horizontalFactor`/`verticalFactor` become public.**
- **`requestNode`/`requestLeaf` are not deprecated.**

The migration story for external custom elements (plan item e) is the table in
the spec's lane 1:

| an outside module wants | it uses |
|---|---|
| a leaf | `requestNativeLeaf` |
| an algorithm | `ProposalLayout` |
| a container with its own paint or input | `requestGroupLayout` + `requestNativeLayout` |
| a legacy root | unchanged |

**Why.**

- **Why a container element and `callAsFunction`.** A layout value with no
  element to carry it is usable only by authors who write a whole `Element`.
  SwiftUI's `Layout.callAsFunction` is the spelling SwiftUI authors reach for.
- **Why the factors become public.** Without them an outside layout that takes a
  `ProposalAlignment` must re-derive nine cases by hand.
- **Why nothing legacy is deprecated.** The inventory orders deprecation after a
  compile-time replacement exists for legacy authors, and this milestone ports
  no legacy container.

**Measurement.** Against the `SA-P` skeleton, re-taken in the third pass **at
file scope with `-swift-version 6`**, one plain-import positive fixture
compiled with exit 0. It declared, all `public` and at file scope, a layout that
reads `priority`, `isSpacer`, `sizeThatFits`, `place` and both factors; a leaf
with `extension Leaf: ProposalElementGroup {}`; and a generic container element
with its own conformance extension. It used them inside one `VStack` as
`HStack { Diagonal() { Leaf(); Spacer() }; Container { Leaf() }; Diagonal(alignment: .top) { Leaf() } }`,
`ProposalLayoutContainer(Diagonal()) { Leaf() }` and
`Diagonal { Leaf() }.padding(Edges(all: Pixels(3)))`.

The second pass's run of the same fixture went through
`typecheck(_:importing:)`'s wrapper in Swift 5 mode. Fed the third pass's
file-scope fixture, that wrapper fails: `declaration is only valid at file
scope` and `attribute 'public' can only be used in a non-local scope`. So the
second pass's positive result was for local types, not for what an external
module writes (`SA-S` finding 6).

The negatives, file scope, Swift 6 mode:

- `_ = MeasurementSubviews()` → `'MeasurementSubviews' initializer is inaccessible due to 'internal' protection level`
- `_ = PlacementSubview()` → `'PlacementSubview' initializer is inaccessible due to 'internal' protection level`
- `subviews[0].place(at: Point(x: 0, y: 0), proposal: .unspecified)` inside `sizeThatFits` → `value of type 'MeasurementSubview' has no member 'place'`
- `_ = Diagonal() { Text("legacy") }` and `_ = Diagonal { Text("legacy") }` → `instance method 'callAsFunction' requires that 'Text' conform to 'ProposalElementGroup'`
- `_ = ProposalLayoutContainer(Diagonal()) { Text("legacy") }` → `generic struct 'ProposalLayoutContainer' requires that 'Text' conform to 'ProposalElementGroup'`

**The constraint mutations, measured on the skeleton** (rebuild, then re-run the
two container fixtures and the positive):

| mutation | `Diagonal() { Text }` | `ProposalLayoutContainer(…) { Text }` | positive |
|---|---|---|---|
| none | fails | fails | exit 0 |
| drop only `callAsFunction`'s explicit `Content: ProposalElementGroup` | **still fails**, same diagnostic: inferred from the return type | fails | exit 0 |
| relax only the struct's constraint to `ElementGroup` | still fails, on the method's constraint | **compiles** | exit 0 |
| relax both | **compiles** | **compiles** | exit 0 |

**What it costs if wrong.**

- **Three public entry points to one node kind.** They must stay in step.
- **Public factors are an API commitment.** Changing `ProposalAlignment` to
  SwiftUI's two-guide model later would break outside layouts.
- **Leaving `ProposalElementGroup` requirement-free keeps one hole open.** A
  marker conformer that registers a legacy node compiles and traps at run time.
  Lane 2 pins the trap, and the hole itself stays. `SA-R` records why, and
  amends the plan's criterion to say so.

**Mutations (lane 1, 2026-09-14, run at `00a1e22` in a detached `git worktree`
off `feat/kernel-completion`, one at a time, full `swift test --build-system
native --no-parallel` each, restore confirmed by `git status --short` clean;
every run read `Test run with 1010 tests in 1 suite`, so none truncated).**
- **Guards 39 → 44**, per-file `grep -c canTypecheck`: 19 + 10 + 5 + 3 + 5
  (`ProposalLayoutCompileGuards`), plus `UnitSafetyTests`' 2 of its 3 hits. All
  five new guards logged `started`/`passed` (not `skipped`) under
  `--build-system native`, and each was mutated red once:
  - `ProposalLayoutContainer`'s constraint relaxed to `Content: ElementGroup`
    (conformance `where Content: ProposalElementGroup`) →
    `aCustomLayoutContainerRejectsLegacyContent`, **on its container fixture
    only** (2 issues: `succeeded: true`, and no `generic struct
    'ProposalLayoutContainer' requires…`); both `callAsFunction` fixtures still
    rejected;
  - that **and** `callAsFunction`'s constraint relaxed → the same guard, on all
    three fixtures (6 issues);
  - `requestNativeLayout` renamed → `anExternalModuleCanBuildACustomLeafAndContainerFromPublicAPI`
    (`value of type 'LayoutPass' has no member 'requestNativeLayout'`);
  - `"-swift-version", "6"` deleted from `typecheckFile` →
    `typecheckFileChecksInTheSwift6LanguageMode` (the fixture compiles, exit 0);
  - `MeasurementSubview.place` added and `MeasurementSubviews.init()` made
    public: see `SA-C`.
- **The non-mutation, confirmed on the real build:** dropping only
  `callAsFunction`'s explicit `Content: ProposalElementGroup` left the suite at
  1010 passed, every guard green.
- **The positive fixture needed one correction** before its first green run:
  its generic container's `requestLayout` must be `mutating`, because
  `requestGroupLayout` is (`cannot use mutating member on immutable value:
  'self' is immutable`). The design skeleton's fixture text was not in the
  record, so whether it had the same shape is unknown.
- `aProposalLayoutContainerRendersThroughTheFramePipeline` (all three
  spellings): `ProposalLayoutContainer.requestLayout` registering
  `requestNativeOverlay` instead → that test alone.

---

## SA-G — mixing is rejected in EVERY direction the engines can meet, and there is NO adapter: the root is the compatibility boundary

**The choice.** Four traps, three of them new:

| direction | where it traps | message fragment | new? |
|---|---|---|---|
| a legacy node as a native node's child | `nativeNode(_:)`, at native registration | "native layout subtree contains a legacy node" | exists (`LayoutTree.swift:379-385`); now pinned |
| a native node as a legacy node's child | `newNode(style:children:)` | "legacy layout node given a native child" | new |
| a `Style` written onto a native node | `setStyle` | "setStyle on a native layout node" | new |
| `computeLayout` handed a native root | `computeLayout` | "computeLayout called on a native root" | new |

Native registrars bypass the new `newNode` check through a private `appendNode`.
Their `Style.default` rows are storage, not a child relationship the CSS engine
should ever see.

**No adapter is built**, in either direction. A legacy subtree cannot be hosted
inside a native container, and a native subtree cannot be hosted inside a legacy
one. The one boundary is `Frame.computeRootLayout`'s root switch.

**Why no adapter.** An adapter in either direction would need four things:

1. its own `LayoutTree` or sub-run for the hosted subtree, because re-entering
   the same tree traps (`SA-I`);
2. a translation between `ProposedSize` and `AvailableSpaceSize` for each
   measurement;
3. a rect translation back into the one store `Frame.bounds(of:)` reads;
4. a second generation, so the hosted ids stay distinct (ruling C-3).

That is a sub-milestone. The plan permits an adapter "only at the old engine
boundary, never as the new layout authority". The root switch is that boundary,
and it already exists.

**Why the `setStyle` trap.** A `Component` that declares `ProposalElementGroup`
can still take a legacy style modifier. `StyledComponent` amends its top-level
nodes with `setStyle`, and those nodes are native, so the width is silently
inert.
- **Measured compile (third pass, evidence 9 of the spec).** With `Toggle:
  Component, ProposalElementGroup` over `Rectangle()` content:
  - `Column { Toggle().width(Pixels(70)) }` compiles;
  - as a root it does not: `return type of global function 'probe()' requires
    that 'StyledComponent<Toggle>' conform to 'Element'`. **The second pass's
    "the reachable path is the root" was wrong**: `StyledComponent` is only an
    `ElementGroup`, and `Frame.render` needs an `Element`;
  - `HStack { Toggle().width(Pixels(70)) }` is rejected: `generic struct
    'HStack' requires that 'StyledComponent<Toggle>' conform to
    'ProposalElementGroup'`;
  - an external `Container<Content: ElementGroup>: Element` that declares
    `ProposalElementGroup` unconditionally and calls `requestNativeLayout`
    compiles, and so does `HStack { Container { Toggle().width(Pixels(70)) } }`.
- **The reachable paths, and which trap fires on each.**
  - **Inside a legacy container** (`Column { … }`): `StyledComponent` calls
    `setStyle` on the native leaf before `Column` calls `newNode`, so the
    `setStyle` trap fires first; without it, the `newNode` trap would fire next.
  - **Inside an external container that declares the marker over
    unconstrained content**: no legacy node is ever registered, so the
    `setStyle` trap is the **only** trap on this path. Without it the width is
    silently inert.

**Measurements, run in this session.**

- **Today's behaviour is silent.** A native leaf inside a legacy `Column`,
  rendered through `Frame` at 140×90 from a temporary env-gated test, printed
  `MIX-PROBE closureCalls=0 leafBounds=Optional(… x: 70.0, y: 0.0 … width: 0.0, height: 0.0)`.
  The native measure never ran. The leaf became a zero-size centred CSS node.
  This confirms record §09 hazard 1 by execution, where the record had it by
  reading.
- **No existing test mixes the engines.**
  - With a temporary `newNode` precondition rejecting native children, native
    registrars routed through a private `appendNode` (11 call sites), and the
    two env-gated probes present: `Test run with 995 tests in 1 suite passed`.
    The probe, run with its gate open, then trapped:
    `LayoutTree.swift:90: Precondition failed: EXPERIMENT legacy layout node given a native child`.
  - With a temporary `setStyle` precondition rejecting native nodes:
    `Test run with 995 tests in 1 suite passed`.
  - Both source edits were reverted (`git checkout`, `git status --short`
    clean of `Sources/`).
- **The demo.** Its default window uses no proposal element outside
  `nativeLayoutPreviewContent()` (`main.swift:957-1020`), by grep. The preview
  window's root is native throughout. Neither window was run.

**What it costs if wrong.**

- **Migration is root by root.** An app cannot drop one `HStack` into an
  existing `Column`. The whole window's root must be native, which is why the
  preview is a separate window.
- **The trap turns yesterday's silent zero-size node into a crash.** Any
  out-of-repo caller that mixed the engines now crashes, and that is the intent.
- **If an adapter proves necessary,** it is a new node kind with its own tree,
  and nothing here blocks it.

**Mutations (lane 2, 2026-09-14, run on the lane's own tests in a separate
`git worktree` off `feat/kernel-completion`, one at a time, restore confirmed
by `git status --short` clean each time, full `swift test --build-system native
--no-parallel` after `swift package clean` each; every run read `Test run with
1032 tests in 1 suite` unless it says it truncated).**
- **Red before** (`18a4331`, filtered, 22 tests, 15 failed):
  `aNativeNodeRegisteredUnderALegacyNodeTraps`, `computeLayoutRejectsANativeRoot`,
  `aStyleWrittenOntoANativeNodeTraps`,
  `aProposalElementInsideALegacyContainerTrapsAtRegistration` and
  `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration` each read
  `.failure → .exitCode(0)` and an empty stderr.
- Delete `newNode`'s native-child precondition →
  `aNativeNodeRegisteredUnderALegacyNodeTraps` and
  `aProposalElementInsideALegacyContainerTrapsAtRegistration`.
- Route the native registrars through the checking `newNode` →
  `everyNativeRegistrarAcceptsNativeChildrenWithoutTrapping`
  (`.success → .signal(SIGTRAP → 5)`), **and the run truncates** (shape 11):
  the in-process `measuringANativeTreeWritesNoRect` traps "given a native
  child", no summary line, 239 `passed` lines. The exit test's red line is in
  that log before the truncation.
- Delete `computeLayout`'s native-root precondition →
  `computeLayoutRejectsANativeRoot`.
- Delete `setStyle`'s native-node precondition →
  `aStyleWrittenOntoANativeNodeTraps` and
  `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration`, the latter on
  its fragment: stderr read `LayoutTree.swift:118: Precondition failed: legacy
  layout node given a native child`, `Column`'s trap, exactly as the spec
  predicted.
- Delete the child loop from `newNativeLinearStack` →
  `aLegacyNodeRegisteredUnderANativeStackTraps` and
  `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer`
  (both green on arrival; this is their red run, taken before the tests were
  committed and re-taken on the implementation). **The integration test first
  stayed green under it** (`SA-T` item 1).
- Delete the child loop from `newNativeLayout` →
  `aLegacyNodeRegisteredUnderACustomLayoutTraps`.

---

## SA-H — the invalidation contract: a cache per CALL, invalidation by construction, and a deliberate divergence from SwiftUI's cross-pass memo

**The choice.** Seven clauses, stated once in the spec's lane 2:

1. **Scope.** A cache lives for exactly one `computeNativeLayout` or
   `measureNativeLayout` call. Nothing survives into another call, another frame
   or a `reset(generation:)`.
2. **Within a call,** each `(node, proposal)` body runs at most once.
3. **Proposal equality** is synthesized `Hashable`. NaN cannot reach the key
   (`SA-J`), and `-0 == 0` is accepted.
4. **Measurement never writes a rect.** Placement only adds entries for proposals
   not yet measured.
5. **A different proposal is a different key.**
6. **A layout's answer must be a function of its value, its proposal and its
   subviews' answers.** Impurity is not detected.
7. **Mutation of the tree during a call traps**, through exactly these checks:
   `setStyle`; every registration (`newNode`, `newLeaf`, every native
   registrar); `reset(generation:)`; re-entry of either engine; `setLayout`
   inside native measurement. **Not checked:** `setLayout` during placement
   outside a measurement body, which the kernel's own placement uses. *Narrowed
   in the third pass (`SA-S` finding 17): the second pass's "Mutation during a
   call traps" claimed more than its checks covered.*

**Why per call.**

- **The frame model already invalidates everything.** `Frame` builds a fresh
  `LayoutTree` per frame (`LayoutTree.swift:333-336`), so a cross-frame memo
  would need stable identity across trees. The kernel's keys are
  generation-stamped ids that die with the tree, by ruling C-3.
- **A cross-frame memo would be a second identity system.** It would need
  `GlobalElementID`-keyed entries, a sweep and an invalidation signal for every
  input a measure closure reads. That is exactly the stale-data shape C-3 closed.
- **The legacy engine already behaves this way.** It re-measures every frame too
  (`LayoutContext.swift:10-12`), and its per-frame cost is recorded in §07.

**Probe: SwiftUI differs, and the spec says so rather than hiding it.**

- **Arm F:** a forced same-size relayout re-ran the child **0** times.
- **Arm G:** a resize that did not change the child's proposal re-ran it **0**
  times.
- **Arm H,** the positive control for G: a resize that changed the child's
  proposal re-ran it **once**.
- **Arms A/B/C** agree with clause 2: twice at one proposal costs 1, a second
  proposal costs 1 more, and a re-ask from placement costs 0.

**What it costs if wrong.** Every frame re-measures every native leaf. On a large
native tree that is the legacy engine's per-frame cost again, where SwiftUI's
memo pays only for changed proposals. `SA-M`'s counters make the cost countable,
and a cross-frame memo stays open for a performance milestone with a count
behind it.

**Mutations (lane 2, 2026-09-14, run on the lane's own tests in a separate
`git worktree` off `feat/kernel-completion`, one at a time, restore confirmed
by `git status --short` clean each time, full `swift test --build-system native
--no-parallel` after `swift package clean` each; every run read `Test run with
1032 tests in 1 suite` unless it says it truncated).**
Clauses 1 and 5 already held, so the three cache tests were green on arrival;
each red run below was taken before the tests were committed and re-taken on
the implementation, with the same result.
- **Red before:** `measuringANativeTreeWritesNoRect`, against the skeleton
  `measureNativeLayout` that delegated to `computeNativeLayout`: 28 issues,
  e.g. `measured.layout(id) → LayoutRect(x: 0.0, y: 4.0, width: 80.0, height:
  9.0)`. `writingARectDuringNativeMeasurementTraps`: `.failure →
  .exitCode(0)`.
- The cache hoisted to a stored property on `LayoutTree` →
  `aSecondComputeNativeLayoutCallReMeasuresEveryLeaf` (`calls.counts → [1, 1,
  1]` against `[2, 2, 2]`) and `aDifferentRootProposalReMeasuresAndMovesTheRects`
  (its second call's `(nil, 80)` becomes a hit). `aResetTreeMeasuresItsNewRegistrationsFromScratch`
  stays green: its keys carry the new generation. **Built incrementally, this
  mutation also reddened `aNodeIDDoesNotSilentlyResolveAgainstAnotherFramesTree`
  and `everyFrameTakesADistinctTreeGeneration`, both reading tree generation
  8538670168**: a stored property added to a public class, read across a
  module boundary by a stale build (CLAUDE.md's `swift package clean` note).
  Cleaned, both stayed green, so every run here was cleaned. A per-tree
  global keyed on `ObjectIdentifier` was tried first to avoid the rebuild and
  is **not a mutation of this clause**: a freed tree's address is reused, so it
  leaked caches across trees and reddened ten unrelated `NativeLayoutTests`.
- `computeNativeLayout` memoized on the root id alone → the same two tests.
- A persistent cache keyed on `(id.index, proposal)` that `reset` does not
  clear → `aResetTreeMeasuresItsNewRegistrationsFromScratch` (`after.counts →
  [0, 0]`, the stack measuring 70×10) and the same two.
- `measureNativeLayout` also calls `placeNative` on the root →
  `measuringANativeTreeWritesNoRect`.
- The leaf case raises `measureDepth` only after calling its closure →
  `writingARectDuringNativeMeasurementTraps`, **once its leaf is the root**
  (`SA-T` item 2).

---

## SA-I — ONE `isLayingOut` flag guards BOTH engines; every registration, a reset, and a rect write from measurement also trap

**The choice.**

- **One flag.** `computeNativeLayout` and `measureNativeLayout` bracket their
  bodies with the existing `beginLayout()`/`endLayout()`. Three existing traps
  now reach the native path: `setStyle` during layout, native re-entry, and
  legacy `computeLayout` called from a native measure closure. The reverse,
  native layout called from a legacy closure, traps too.
- **Registration.** Every registration traps while `isLayingOut`: `newNode`,
  `newLeaf` and every native registrar, through one check in `appendNode`.
  *Widened in the third pass from native registrars only (`SA-S` finding 17).*
- **Reset.** `reset(generation:)` traps while `isLayingOut`. Mid-run it empties
  the arrays the run is indexing, and the run then dies on an out-of-range
  index with no message.
- **Rect writes.** `setLayout` traps while a native measurement body is running.

**Why one flag, not two.** The two engines write the same `layouts` array
through the same `setLayout`, and a legacy `measureNode` memoizes against the
same `styles`. A second flag would let a native closure run legacy layout over
the tree mid-run, which is exactly the hazard the first flag exists to stop.

**Why the registration trap covers every registrar.** A measure closure that
registers nodes mid-layout grows the arrays the run is indexing. That is
harmless today by accident, and wrong the moment a registrar is given a live
id. `newNode` and `newLeaf` grow the same arrays as a native registrar, so a
check on native registrars alone would leave the stated reason unenforced.

**Why the `setLayout` trap.** It is the only way clause 4 of `SA-H` can be
enforced rather than merely true. A leaf closure holding the tree, through an
`@unchecked Sendable` box, can call it today.

**Measurement (third pass).** The checks were applied temporarily, on top of
the lane 1 skeleton and lane 3's frame split: `computeNativeLayout` bracketed
by `beginLayout()`/`defer { endLayout() }`, and `precondition(!isLayingOut)` in
`newNode` (reached by `newLeaf` and every native registrar today) and in
`reset(generation:)`. `swift test --no-parallel` read `Test run with 993 tests
in 1 suite passed`, 0 `error:`, 0 `warning:`, and `strings -a` found the
experiment's message in the test binary. No existing test registers, resets or
re-enters mid-layout, and none lays one tree out re-entrantly. Reverted; the
clean re-run read 993.

**Before the third pass** today's behaviour was known from reading only:

- `isLayingOut` is set only at `FlexEngine.swift:102-103`;
- `computeNativeLayout` (`LayoutTree.swift:274-282`) never calls
  `beginLayout`;
- so `setStyle`'s precondition (`:292-293`) cannot fire during native layout,
  and a re-entrant `computeNativeLayout` recurses until the stack dies with no
  attribution.

Lane 2's red runs are the first executions of these paths.

**What it costs if wrong.** A legitimate pattern that lays out a second, unrelated
subtree of the same tree from inside a measure closure now traps. No such caller
exists in `Sources/`, and a hosted subtree belongs in its own tree (`SA-G`).

**Mutations (lane 2, 2026-09-14, run on the lane's own tests in a separate
`git worktree` off `feat/kernel-completion`, one at a time, restore confirmed
by `git status --short` clean each time, full `swift test --build-system native
--no-parallel` after `swift package clean` each; every run read `Test run with
1032 tests in 1 suite` unless it says it truncated).**
- **Red before** (`18a4331`): `computeLayoutCalledFromANativeMeasureClosureTraps`,
  `setStyleOnALegacyNodeDuringNativeLayoutTraps`,
  `registeringANativeNodeDuringNativeLayoutTraps`,
  `registeringALegacyLeafDuringNativeLayoutTraps` and
  `registeringANodeDuringLegacyLayoutTraps` read `.failure → .exitCode(0)`.
  `computeNativeLayoutReenteredFromAMeasureClosureTraps` died with an empty
  stderr (the recursion exhausted the stack). `resettingATreeDuringLayoutTraps`
  died, but **not on an out-of-range index as the spec predicted**: stderr read
  `LayoutTree.swift:393: Precondition failed: LayoutNodeID from generation 0
  used against a LayoutTree at generation 1`, the next stale-id read.
  `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns` read `.success →
  .signal(SIGTRAP → 5)`.
- Drop `beginLayout()` from `computeNativeLayout` →
  `computeNativeLayoutReenteredFromAMeasureClosureTraps`,
  `computeLayoutCalledFromANativeMeasureClosureTraps`,
  `setStyleOnALegacyNodeDuringNativeLayoutTraps`,
  `registeringANativeNodeDuringNativeLayoutTraps`,
  `registeringALegacyLeafDuringNativeLayoutTraps`,
  `resettingATreeDuringLayoutTraps` and
  `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns`.
- Give the native path its own flag (its own re-entrancy precondition; the
  registration, `setStyle` and `reset` checks reading either flag) →
  `computeLayoutCalledFromANativeMeasureClosureTraps` and
  `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns`.
- Delete the precondition from `appendNode` →
  `registeringANativeNodeDuringNativeLayoutTraps`,
  `registeringALegacyLeafDuringNativeLayoutTraps` and
  `registeringANodeDuringLegacyLayoutTraps`.
- Route `newLeaf` around `appendNode` (its own storage append) →
  `registeringALegacyLeafDuringNativeLayoutTraps` alone of those three.
- Delete the `reset(generation:)` precondition →
  `resettingATreeDuringLayoutTraps`.
- **(A)** `endLayout()` moved from the `defer` to directly after `beginLayout()`
  in `computeNativeLayout` → `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns`,
  `setStyleOnALegacyNodeDuringNativeLayoutTraps`,
  `computeLayoutCalledFromANativeMeasureClosureTraps`,
  `computeNativeLayoutReenteredFromAMeasureClosureTraps`,
  `registeringANativeNodeDuringNativeLayoutTraps`,
  `registeringALegacyLeafDuringNativeLayoutTraps` and
  `resettingATreeDuringLayoutTraps`; `registeringANodeDuringLegacyLayoutTraps`
  stayed green. The spec's list, exactly.
- **(B)** the `defer { endLayout() }` dropped entirely → **the run truncated**
  as the spec predicted: the in-process `aSecondComputeNativeLayoutCallReMeasuresEveryLeaf`
  trapped "computeLayout re-entered on the same tree", no summary line, 248
  `passed` lines. `--filter nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns`
  on the same build: `.success → .signal(SIGTRAP → 5)`, 1 test, 1 issue.
- *Verifier's independent re-run, 2026-09-14 (record §09):* removing
  `beginLayout`/`endLayout` from `measureNativeLayout` (X1), or its
  `activeNativeRun = run` (X2), left the suite green at 1032. Its half of
  clauses 4 and 7 is unpinned; it has no `Sources/` caller. Open.

---

## SA-J — validation: reject ONLY what SwiftUI rejects or what makes a node non-finite at a proposal with no infinite axis; a measurement may be infinite, a stored rect may not, nothing may be NaN

**The choice.**

- **The rule.** A native registrar rejects a parameter only if (1) SwiftUI
  rejects it — by a diagnostic, a trap, a hang, or having no spelling for it —
  or (2) the parameter would make the node's measurement, or a rect it places,
  **non-finite at a proposal with no infinite axis**. *Clause 2 was sharpened
  in the third pass (`SA-S` finding 4): it read "would make MetalUI's answer
  non-finite", which contradicted the corollary that a measurement may be
  infinite.*
- **Computed values** are checked at three kernel checkpoints:
  1. a NaN proposal at `measureNative` entry;
  2. a NaN measurement at its exit;
  3. a non-finite rect at `placeNative` entry.
- **A rejection is a `precondition`** whose message names the parameter or the
  node. MetalUI has no warning channel, as in `FontResolver.resolve`'s
  precedent.

**Why checkpoints, not per-entry checks.** Three checkpoints catch a bad value
wherever it arose: a root caller, a proxy, a leaf closure, or built-in
arithmetic such as ∞ − ∞ in a stack's spacer surplus. Per-entry checks would
miss the arithmetic and multiply messages for one rule.

**Per-parameter outcome** (probe `swiftui-layout-input-validation.swift`, arm in
brackets; "diag" means SwiftUI logged "Invalid frame dimension" and/or
"Contradictory frame constraints"):

| parameter | SwiftUI (arm) | ruling |
|---|---|---|
| spacing −10 / −100 | 30; −60, unclamped, also at a 50 proposal; no diag (P1) | **accept** |
| spacing NaN / +∞ / −∞ | nan / inf / −inf (P1, P9) | reject: non-finite |
| padding −5 / −15 | 10 / **0**, a response clamp; child placed at origin + inset, at its own size (P2, P2b) | **accept**, clamp per axis (`SA-K`) |
| padding NaN | 0×0, then **traps** placing the child: "view origin is invalid: (nan, nan)" (P2, P2c) | reject: SwiftUI traps |
| padding +∞ | inf×inf (P2) | reject: non-finite |
| padding −∞ | 0×0, child placed at (−inf, −inf) (P9, P2c) | reject: non-finite rect |
| fixed width −10 / +∞ / NaN / −∞ | diag each (P3, P9) | reject: diagnosed |
| minWidth −10 / −∞ | 20 / 20, no diag (P4, P9) | **accept** |
| minWidth NaN / +∞ | diag (P4, P4b) | reject |
| maxWidth +∞ | 100 at 100, 20 at nil, no diag (P4c) | **accept** |
| maxWidth −10 / −∞ / NaN | diag (P4, P9) | reject |
| idealWidth −10 / NaN | diag (P4b) | reject |
| idealWidth +∞ | no diag; **inf at nil** (P4b), 20 at 100 (P4d) | reject, clause 2: non-finite at the unspecified proposal, which has no infinite axis |
| min > max, min > ideal, ideal > max | diag (P4, P4c) | reject |
| fixed and flexible together | no overload exists: `Color.red.frame(width: 10, minWidth: 5)` → `extra argument 'minWidth' in call`, and `minHeight` likewise (third pass) | reject **at compile time** in the element API, which splits into SwiftUI's two overloads (`SA-K` item 6); the kernel registrar keeps a precondition for one axis as a backstop |
| Spacer minLength −30 | 10, no diag (P5) | **accept** |
| Spacer minLength NaN / +∞ / −∞ | −inf / inf / −inf (P5, P9) | reject: non-finite |
| layoutPriority ±∞ | orders like ±1: 80/20 and 20/80 (P7, P7b) | **accept** (`SA-K`) |
| layoutPriority NaN | **hangs**: 99.4% CPU at 00:20, killed (P7 `--include-hang`) | reject: SwiftUI hangs |
| aspectRatio −2 | 100×−50 `.fit` at 100×80 and at 100×nil; −160×80 `.fill` at 100×80 and `.fit` at nil×80 (P8, P8b) | **accept** (`SA-K`) |
| aspectRatio 0 | 0×80 at 100×80, **0×inf** at 100×nil (P8) | reject: non-finite on a one-axis proposal |
| aspectRatio NaN / +∞ / −∞ | nan×nan / nan×0 / nan×−0 (P8, P9) | reject: non-finite |
| proposal −10×−20 / 0×0 / ∞ to `Color` | −10×−20 / 0×0 / inf×inf (P6) | **accept** |
| proposal NaN | nan echoed (P6) | reject: checkpoint 1 |
| a child's answer ∞ | accepted, placed at (−inf, 95, inf, 10) (N) | **accept** as a measurement; checkpoint 3 rejects the rect |
| a child's answer NaN | accepted, placed at (nan, …) (N) | reject: checkpoint 2 |
| placement position +∞ | accepted, placed at (inf, 0, 20, 20) (M) | reject: checkpoint 3 |
| placement position NaN | **traps**: "view origin is invalid: (nan, 0.0)" (M `--nan-place`) | reject: checkpoint 3 |

**The corollary's reasoning.**

- **Why a measurement may be infinite, and why that does not contradict
  clause 2.** "An unconstrained answer to an unbounded proposal" is legitimate:
  P6's `Color` offered ∞ answers ∞. User code may also answer ∞, and the kernel
  cannot tell why. Clause 2 applies only to a **parameter** that produces a
  non-finite value at a proposal with no infinite axis: there the value can
  only have come from the parameter. The checkpoints then check computed values
  for NaN (measurements) and for any non-finite field (rects) only.
- **Why a stored rect may not.** Prepaint, paint, hit-testing and rounding all
  do arithmetic on it, and `round(inf) − round(inf)` is NaN.
- **Why NaN is never acceptable.** It is unequal to itself. It misses the cache
  every time (record §09), and it poisons every comparison downstream.

**The four rows decided by clause 2, not clause 1.**

- **`idealWidth: +∞`** gets no SwiftUI diagnostic. Clause 2 rejects it: the
  unspecified proposal is the one every stack child and every scroll content
  receives on its main axis, so an infinite ideal becomes an infinite
  measurement in the most ordinary tree. Rejecting at registration names the
  parameter. Rejecting at checkpoint 3 would name a sibling's rect several nodes
  away. **Accepting it was considered and rejected**: nothing then stops the
  infinite measurement from reaching a rect, and checkpoint 3 would trap there
  with a message about the wrong node.
- **Padding NaN** is finite in SwiftUI's measurement but traps SwiftUI's own
  placement (P2c).
- **Padding −∞** is finite in measurement and non-finite in placement (P2c).
- **Ratio 0** is finite on one proposal shape and infinite on another (P8).

**What it costs if wrong.**

- **A MetalUI app crashes where SwiftUI would log and draw something.** For a
  diagnosed frame dimension, SwiftUI clamps and continues (P3: width −10
  answered 0×20). Every "diag" row in the table above is such a row: SwiftUI
  accepts it at run time, and MetalUI does not. The critic's review named this;
  it is kept (`SA-S` finding 4).
- **The trade is deliberate.** A precondition names the parameter at
  registration. SwiftUI's diagnostic names nothing and draws a guess.
- **If the crash proves too harsh,** relaxing a precondition to a clamp is
  additive. Tightening a clamp back into a crash later would break callers.

**Mutations (lane 3, 2026-09-14, run at `71c8b1c` in a detached `git worktree`
off `feat/kernel-completion`, one at a time, full `swift test --build-system
native --no-parallel` each, restore confirmed by `git status --short` clean
each time; every run read `Test run with 1084 tests in 1 suite`, so none
truncated. Every mutation edits a function body or adds a method, so the
builds were incremental; the implementation's own suite run was cleaned).**
- **Red before** (`408dfc3`, the skeleton, 53 filtered tests, 90 issues): the
  30 new-rule trap tests read `.failure → .exitCode(0)` with an empty stderr.
  `aNaNLayoutPriorityTraps` and the four ratio traps already trapped under the
  old rules and were red **on their fragment only** (`SA-U` item 1).
- Stack spacing `!= .infinity` → `aNaNStackSpacingTraps`,
  `aNegativeInfiniteStackSpacingTraps`.
- Padding precondition deleted → the three padding traps.
- Fixed dimension: NaN-blind `!(x < 0) && x != .infinity` →
  `aNaNFixedFrameDimensionTraps`; `>= 0` half dropped →
  `aNegativeFixedFrameDimensionTraps`; `isFinite` half dropped →
  `anInfiniteFixedFrameDimensionTraps`.
- Minimum: `!isNaN` dropped → `aNaNFrameMinimumTraps`; `!= .infinity` dropped
  → `anInfiniteFrameMinimumTraps`.
- Maximum: NaN-blind `!(max < 0)` → `aNaNFrameMaximumTraps`; deleted → that
  and `aNegativeFrameMaximumTraps`.
- Ideal: NaN-blind → `aNaNFrameIdealTraps`; `>= 0` dropped →
  `aNegativeFrameIdealTraps`; `isFinite` dropped → `anInfiniteFrameIdealTraps`.
- Each ordering check deleted → its own test alone
  (`aFrameMinimumAboveItsMaximumTraps`, `aFrameMinimumAboveItsIdealTraps`,
  `aFrameIdealAboveItsMaximumTraps`); the combination check deleted →
  `aFixedFrameDimensionCombinedWithAFlexibleOneTraps`.
- Spacer precondition deleted → the three spacer traps.
- Priority precondition deleted → `aNaNLayoutPriorityTraps`.
- Ratio `ratio != 0` alone → `aNaNAspectRatioTraps`, `anInfiniteAspectRatioTraps`
  and `aNegativeInfiniteAspectRatioTraps`; `!ratio.isNaN && ratio != .infinity`
  → `aNegativeInfiniteAspectRatioTraps` **and `aZeroAspectRatioTraps`** (that
  spelling also admits 0).
- Checkpoint 1 deleted → `aNaNRootProposalTraps`, `aNaNSubviewProposalTraps`.
  Checkpoint 2 deleted → `aNaNMeasurementTraps`, `aNaNCustomMeasurementTraps`.
  Checkpoint 3 deleted → `aNonFiniteRootBoundsTraps`,
  `anInfiniteStoredRectTraps`, `aNonFinitePlacementPositionTraps`.
- Checkpoint 3's non-finite test moved to checkpoint 2 →
  `anInfiniteMeasurementIsAcceptedUntilItBecomesARect` and the three
  checkpoint-3 traps.
- Negative proposal axes rejected at checkpoint 1 →
  `aNegativeProposalIsAccepted`, and also `aNegativeSpacerMinimumIsAccepted`,
  `aNegativeAspectRatioIsAcceptedOnEveryProposedBranch`,
  `aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes` and
  `theProposalModifiersAcceptWhatTheKernelAccepts`, each of which hands a child
  a negative proposal.
- Negative spacing rejected, and gaps clamped at 0, each →
  `negativeStackSpacingAnswersSwiftUIsUnclampedSum`. A negative minimum
  rejected → `negativeAndNegativeInfiniteFrameMinimumsAndAnInfiniteMaximumAreAccepted`.
  `minLength` clamped at 0 → `aNegativeSpacerMinimumIsAccepted`.
- *Verifier's independent re-run, 2026-09-14 (record §09):* four sub-clauses
  stayed green when removed: the padding precondition's `insets.right.isFinite`,
  checkpoint 2's height-NaN and `lastBaseline`-NaN halves, and checkpoint 3's
  `bounds.height.isFinite`. Each check still exists; no test gives that field a
  bad value. Also,
  `negativeAndNegativeInfiniteFrameMinimumsAndAnInfiniteMaximumAreAccepted`
  cites P4/P9 at a 100 proposal, but those probe arms offered nil only; the
  100-proposal answer is derived. Open.

---

## SA-K — the relaxations and repairs `SA-J` forces on today's kernel

**The choice.** Five source changes and one test re-fixture. *Items 2 and 5
were revised, and item 6 added, in the third pass (`SA-S` findings 4, 7, 18 and
the no-defect note).*

1. **Priority.** `newNativeLayoutPriority` accepts ±∞: `isFinite` becomes
   `!isNaN`. It has **trapped on ±∞ since `d250743`**.
   `stackMainAllocations` already sorts ±∞ correctly: `Set(...).sorted(by: >)`
   over `[inf, 0]` is `[inf, 0]`.
2. **Aspect ratio.**
   - `newNativeAspectRatio` accepts a negative ratio: `ratio > 0` becomes
     `ratio != 0`.
   - `aspectRatioSize`'s two-axis branch compares `width / ratio <= height`
     (`.fit`) and `>=` (`.fill`).
   - For ratio −2 at 100×80, today's predicate picks the height branch and
     answers −160×80. P8 says 100×−50.
   - **P8c (third pass) probes zero and negative axes for both signs.** Ratio 2
     and −2, `.fit` and `.fill`, at 100×−10, 100×0, −100×80, 0×80, −100×−80
     and −100×−10: the new predicate picks SwiftUI's branch in **24 of 24**
     arms, today's in **12**.
   - **So it is a repair for positive ratios too.** At 100×−10 with ratio 2
     `.fit`, today's predicate answers 100×50 and SwiftUI answers −20×−10, the
     new predicate's answer. The second pass argued equivalence only for
     height > 0 and had not probed the rest.
3. **Padding.** The measurement becomes `max(0, child + leading + trailing)` per
   axis. Today −15 on 20 answers −10, and P2 says 0. P2b's leading −30 /
   trailing 5 answers 0×20, which proves the clamp is per axis.
4. **The MetalUI modifiers.** `.aspectRatio` and `.layoutPriority`
   (`NativeModifiedContent.swift:271-272, 279`) adopt the kernel's rule.
5. **The re-fixture.** `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes`
   (`NativeLayoutTests.swift:168`) declares ideal 90 > max 80, which `SA-J`
   rejects. It is re-fixtured to ideal 70, with expectations re-derived by hand:
   measurement 70×20, child rect `(10, 14, 30, 10)`, and the leaf closure's
   in-closure `#expect(proposal == …)` changes from (80, 60) to **(70, 60)**.
   The critic confirmed the derivation and found that last expectation missing
   from the second pass's text.
6. **The frame element API splits into SwiftUI's two overloads.**
   `ProposalElementGroup.frame` and `nativeFrame` become
   `(width:height:alignment:)` and
   `(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`;
   `ProposalFrame` gets the two matching initializers; `LayoutModifier.frame`
   loses its flexible parameters to a new `.flexibleFrame` case. The kernel's
   `newNativeFrame` keeps one registrar and its one-axis precondition, as a
   backstop for kernel callers.
   - **Measured (third pass):** with the split applied temporarily the suite
     compiled and read 993 passed, so no caller used a combined spelling. At
     file scope in Swift 6 mode, the combined spellings fail with `extra
     argument 'minWidth' in call` (modifier, `LayoutModifier` case,
     `nativeFrame`), `extra argument 'minHeight' in call` (cross-axis), and
     `extra arguments at positions #2, #3 in call` (`ProposalFrame`).
     `Text("…").frame(width:)` still selects the legacy `FrameModifier`.
   - **Why at compile time.** SwiftUI has no spelling for the combination, so
     turning it into a run-time crash in MetalUI would be a failure SwiftUI
     authors never meet. The typecheck guard
     `aFixedAndAFlexibleFrameDimensionCannotBeCombined` pins it.
   - **Cross-axis mixing is lost from the element API.** `frame(width: 40,
     minHeight: 10)` was a legal MetalUI spelling, and SwiftUI has none; chain
     two frames instead. No caller used it.

**Why.** Each is the minimal change that makes the kernel accept what SwiftUI
accepts, at SwiftUI's answer.

**What stays unrepaired.** P2b shows SwiftUI places a padded child **at its own
size**. The kernel stores it at the padding's bounds minus the insets
(`LayoutTree.swift:535-540`), so negative padding stores a wider child. Fixing
that moves placement for positive padding too, and it reddens at least one
existing integration test. It is plan task 5's (`SA-N` item 4). Lane 3's
acceptance test pins today's width **wrong on purpose**, so that fix reddens it
deliberately.

**What it costs if wrong.**

- **Item 2 changes the two-axis branch for every ratio.** It changes answers
  for positive ratios at negative or zero proposal axes, deliberately, to
  SwiftUI's (P8c). A negative proposal is legal (P6), so a MetalUI tree that
  offers one to an aspect ratio sees a new answer.
- **Item 6 is source-breaking for any out-of-repo caller** that combined a
  fixed and a flexible dimension in one `frame` call.
- **Item 5 drops the only pin of the ideal-clamped-by-max arithmetic.** Once
  ordering is validated that arithmetic is unreachable, so nothing is lost
  unless validation is ever relaxed.

**Mutations (lane 3, 2026-09-14, run at `71c8b1c` in a detached `git worktree`
off `feat/kernel-completion`, one at a time, full `swift test --build-system
native --no-parallel` each, restore confirmed by `git status --short` clean
each time; every run read `Test run with 1084 tests in 1 suite`, so none
truncated. Every mutation edits a function body or adds a method, so the
builds were incremental; the implementation's own suite run was cleaned).**
- **Red before** (`408dfc3`): `infiniteLayoutPrioritiesAreAcceptedAndOrderLikeFinitePriorities`,
  `aNegativeAspectRatioIsAcceptedOnEveryProposedBranch`,
  `aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes`,
  `negativePaddingIsAcceptedAndItsResponseClampsPerAxis` and
  `theProposalModifiersAcceptWhatTheKernelAccepts` read `.success →
  .signal(SIGTRAP → 5)`; `aFixedAndAFlexibleFrameDimensionCannotBeCombined`
  read `TypecheckResult(succeeded: true, output: "")` on all five fixtures.
  The re-fixtured `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes` was
  green at ideal 70 before and after, as item 5's derivation says.
- Item 1, ±∞ mapped to 0 at registration →
  `infiniteLayoutPrioritiesAreAcceptedAndOrderLikeFinitePriorities` and
  `theProposalModifiersAcceptWhatTheKernelAccepts`.
- Item 2, the old `width / height <= ratio` (and `>=`) restored →
  `aNegativeAspectRatioIsAcceptedOnEveryProposedBranch`,
  `aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes` and
  `theProposalModifiersAcceptWhatTheKernelAccepts`.
- Item 3, the clamp removed, and both axes clamped together, each →
  `negativePaddingIsAcceptedAndItsResponseClampsPerAxis`.
- Item 4, the modifiers' old preconditions restored (`> 0`, `isFinite`) →
  `theProposalModifiersAcceptWhatTheKernelAccepts`.
- Item 6, a nine-parameter `frame` restored beside the two overloads (the
  library and every test still built) → `aFixedAndAFlexibleFrameDimensionCannotBeCombined`
  on its first two fixtures (`succeeded: true`, 4 issues); the
  `ProposalFrame`, `LayoutModifier` and `nativeFrame` fixtures stayed rejected.
- **Diagnostics re-printed from the real build** are the guard's substrings:
  `extra argument 'minWidth' in call`, `extra argument 'minHeight' in call`,
  `extra arguments at positions #2, #3 in call` (`ProposalFrame`). Guards
  44 → 45; the new guard logged `started`/`passed` under `--build-system native`.

---

## SA-L — a native depth guard counted in native nodes, sized by legacy's safety fraction (provisionally 96; 88 as bisected by lane 3), one counter across measurement and placement

*Lane 3 re-bisected all four kinds on its own build and committed **88**; see
the Mutations line below. The 96 in this ruling's body is the design pass's
provisional figure, left as written.*

*Revised in the third pass (`SA-S` finding 5). The second pass chose 64 "for
parity" with legacy; that parity claim was unmeasured and is withdrawn.*

**The choice.** `NativeLayoutRun.maxDepth` = **the largest multiple of 8 not
above 0.60 × the smallest native debug ceiling on a 1 MB thread**, across
padding, frame, linearStack and the custom kind. From the three ceilings
measured so far that is 0.60 × 171 = 102.6, so **96**; lane 3 bisects the custom
kind, re-bisects the other three on its own build, and commits the formula's
answer.

- **One counter.** `run.depth` is entered at the top of `measureNative` and
  `placeNative` and left on return. Placement calls measurement from inside
  itself, so the one counter tracks the real combined stack.
- **The message:** "native layout recursion exceeded \(maxDepth) levels at node …".
- **It is its own constant, not `LayoutContext.maxDepth`,** because the two
  engines' per-level costs differ, and because it counts a different unit.
- **It is not the legacy number, and no parity is claimed.** Legacy stores
  size, aspect ratio and padding in one node's `Style`. Natively `frame`,
  `padding`, `aspectRatio`, `layoutPriority`, `fixedSize` and `.overlay` each
  add a node, so one legacy level ported as `.padding(…).frame(width:)` is at
  least three native levels. The second pass's sentence "a tree the legacy
  engine accepts must not be rejected by its proposal port for depth alone" was
  never measured, and this shape makes it false in general. How a real ported
  tree's native depth compares with its legacy depth remains **unmeasured**.
- **Why the same fraction.** 0.60 is what legacy judged safe for a 1 MB
  secondary thread, and the native frames are smaller (≈5.3–6.0 KB against
  ≈9.8 KB), so the same fraction buys more levels, and those levels are what a
  ported tree spends its extra nodes on.

**Measurement (debug; 1 MB `Thread`; one `swift test --skip-build` per candidate
depth).** An uncommitted, env-gated probe test built N nested native nodes over
a leaf and printed `DEPTH-OK N` if `computeNativeLayout` returned. The script
bisected between 50 and 600:

```
kind=padding kb=1024 maxOK=193 firstFail=194
kind=frame kb=1024 maxOK=193 firstFail=194
kind=stack kb=1024 maxOK=171 firstFail=172
```

Those numbers are identical to the earlier pass's bisection, which searched 1 to
40000. They put padding and frame at ≈5.3 KB per level and linearStack at
≈6.0 KB, against legacy's ≈9.8 KB (107 levels, carried from
`LayoutContext.swift`). The legacy constant was chosen at 64/107 = 0.60 of the
smallest real stack. At the same fraction the native linearStack allows
0.60 × 171 = 102.6 levels.

**Not measured:** release, and the custom kind. A `ProposalLayout` level adds an
existential call and a proxy frame, so its ceiling may be lower than the
stack's, and the run object changes every native frame's size. So lane 3
bisects all four kinds on its own build before committing the number.

**Why three trap tests, not one.** A tree deeper than the limit traps in
measurement first. So a test through `computeNativeLayout` stays green if `enter`
is deleted from `measureNative` alone, because placement still traps.

- **The measurement-only test** (`measureNativeLayout`) isolates that deletion.
- **A placement-only chain** of custom layouts isolates `placeNative`'s. Each of
  its `sizeThatFits` returns a constant without measuring, so measurement never
  recurses.

`LayoutContextTests.swift:150-173` records the same shape-4 hazard for legacy
`placeNode`.

**What it costs if wrong.**

- **Too high.** If a kind is left unbisected and its ceiling is below
  maxDepth / 0.60, a deep chain of it dies at SIGBUS on a 1 MB thread with no
  attribution, the failure the guard exists to prevent. Bisecting all four on
  the lane's build is the defence.
- **Too low for ported trees.** A legacy tree near legacy's 64 levels, ported
  with a node per modifier, can exceed 96 native levels and trap where legacy
  laid it out. The trap names the node; the fix is a measured, larger limit,
  not a silent overflow.

**Mutations (lane 3, 2026-09-14, run at `71c8b1c` in a detached `git worktree`
off `feat/kernel-completion`, one at a time, full `swift test --build-system
native --no-parallel` each, restore confirmed by `git status --short` clean
each time; every run read `Test run with 1084 tests in 1 suite`, so none
truncated. Every mutation edits a function body or adds a method, so the
builds were incremental; the implementation's own suite run was cleaned).**
- **The bisection, on this lane's build** (debug, 1 MB `Thread`, one `swift test
  --skip-build` per candidate depth between 50 and 600, both boundaries
  re-confirmed, from an uncommitted env-gated probe with `maxDepth` raised out
  of the way; the first failing depth dies with no summary line, and the stack
  kind's 152 completes on a 4 MB thread):
  ```
  kind=padding kb=1024 maxOK=169 firstFail=170
  kind=frame kb=1024 maxOK=168 firstFail=169
  kind=stack kb=1024 maxOK=151 firstFail=152
  kind=custom kb=1024 maxOK=156 firstFail=157
  ```
  Every kind lost 17–25 levels against the design pass's 193/193/171, which
  bisected before the run carried the guard, the checkpoints and the counters.
  **So `maxDepth` is 88, not the provisional 96**: the smallest ceiling is the
  stack's 151, and 0.60 × 151 = 90.6. At 96 the guard would still have fired
  below every ceiling (96 < 151), but at a 0.64 margin, not legacy's 0.60.
  The custom kind (a one-child layout measuring and placing through the proxy)
  is not the smallest. The table is on `NativeLayoutRun.maxDepth`.
- **Red before** (`408dfc3`, `maxDepth` declared, never enforced): the three
  trap tests read `.failure → .exitCode(0)`; `aNativeTreeAtTheDepthLimitDoesNotTrap`
  green, as designed.
- `enter` deleted from both `measureNative` and `placeNative` →
  `layingOutANativeTreeDeeperThanTheLimitTraps`,
  `measuringANativeTreeDeeperThanTheLimitTraps` and
  `aPlacementOnlyChainOfCustomLayoutsDeeperThanTheLimitTraps`.
- From `measureNative` only → `measuringANativeTreeDeeperThanTheLimitTraps`;
  the other two stayed green (placement still traps).
- From `placeNative` only → `aPlacementOnlyChainOfCustomLayoutsDeeperThanTheLimitTraps`;
  the other two stayed green (measurement still traps).
- `depth < maxDepth` → `aNativeTreeAtTheDepthLimitDoesNotTrap`.

---

## SA-M — three work counters, on the TREE as `lastNativeLayoutWork`, and one count test on a branching tree

**The choice.**

```swift
struct NativeLayoutWork: Equatable { var measureCalls = 0; var cacheHits = 0; var cacheMisses = 0 }
// LayoutTree: internal private(set) var lastNativeLayoutWork: NativeLayoutWork
```

- **What each counts.** `measureCalls` counts user code: leaf closures and
  custom `sizeThatFits`. `cacheMisses` counts every measurement body run, and
  `cacheHits` every lookup that found its key.
- **When the record is written.** Each native entry point assigns it from its
  own run on return.
- **How it is proven.** `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`
  must redden under "disable the cache". Its `measureCalls`, `cacheHits` and
  `cacheMisses` assertions all compare against **literals derived by hand
  before the run**. *The second pass compared `measureCalls` with the sum of the
  leaf closures' own call counts, which rises with it when the cache is
  disabled, so that assertion could not redden (shape 15; `SA-S` finding 12).*

**Why on the tree, when the legacy counters live on `LayoutContext`.**

- **Ruling C-3's objection is to a cache outliving its run.** It is not an
  objection to a count. `lastNativeLayoutWork` holds no `LayoutNodeID` and
  answers no layout question.
- **Only the tree is reachable after `Frame.render`.** Neither the legacy
  `LayoutContext` nor a native run is. A native count test therefore needs the
  tree to carry it, whether it builds a tree by hand or runs the preview's
  composition through a real `Frame`.

**Why these three.** Practices rule: "performance tests count work, never wall
clock". Record §09 says this rule "cannot yet be applied to this engine, because
it exposes no work to count".

- **`cacheHits`/`cacheMisses`** mirror `LayoutContext.hits`/`misses`, which
  pin the legacy cache.
- **`measureCalls`** is the one that sees user cost, because a text leaf's
  closure is where shaping happens.

**Why a branching tree.** The practices doc, and shape 15's measure-performance
precedent: a chain collapses every probe onto a few keys. The tree mixes three
things:

- an overflowing prioritized stack, where placement proposals differ from
  measurement proposals;
- an aspect ratio, which measures its child twice;
- a custom layout.

Without the cache, placement re-measures each subtree.

**What it costs if wrong.**

- **A test observable with no production reader.** It joins CLAUDE.md's inert
  table's test-observables row.
- **If the expected literals are read off a green run** instead of derived by
  hand first, the test is shape 12 and cannot fail for a mis-keyed cache. The
  spec forbids it.

**Mutations (lane 3, 2026-09-14, run at `71c8b1c` in a detached `git worktree`
off `feat/kernel-completion`, one at a time, full `swift test --build-system
native --no-parallel` each, restore confirmed by `git status --short` clean
each time; every run read `Test run with 1084 tests in 1 suite`, so none
truncated. Every mutation edits a function body or adds a method, so the
builds were incremental; the implementation's own suite run was cleaned).**
- **Red before** (`408dfc3`, `lastNativeLayoutWork` never written):
  `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` read
  `(work.measureCalls → 0) == 16`, `(work.cacheHits → 0) == 27` and
  `(work.cacheMisses → 0) == 25`, with (1) and (4) green as designed;
  `nativeLayoutWorkIsPerCall` read `(first.cacheMisses → 0) > 0`. The literals
  were derived by hand in the test's doc comment before the first run.
- Disable the cache (delete the hit branch) → the branching test on (1) (e.g.
  `(log.calls → 10) == (log.proposals.count → 2)`), (2) (`62`) and (3) (hits
  `0`, misses `89`), plus eight existing tests that count closure calls
  (`aSubviewMeasuresOncePerDistinctProposalWithinOneRun`,
  `aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndCentresEachChild`,
  `aSecondComputeNativeLayoutCallReMeasuresEveryLeaf` and others).
- Key on node only (proposal replaced by `.unspecified`) → the branching test
  on (2), (3) and (4) (a3 stored at `(81, 13, 30, 8)`), and seventeen other
  layout and integration tests.
- Count a hit before checking the key → the branching test on (3) alone
  (`cacheHits → 52`).
- Accumulate into `lastNativeLayoutWork` → `nativeLayoutWorkIsPerCall`
  (`measureCalls: 32, cacheHits: 54, cacheMisses: 50` against 16/27/25).
- *Verifier's independent re-run, 2026-09-14 (record §09):* deleting
  `lastNativeLayoutWork = run.work` from `measureNativeLayout` left the suite
  green at 1084: "each native entry point assigns it" is pinned for
  `computeNativeLayout` only. Open.

---

## SA-N — what the probes found that this design does NOT fix, and who owns it

Each item below is a probe result that disagrees with the kernel, or a SwiftUI
behaviour noticed and not explained. None blocks task 2.

1. **A finite `maxWidth` frame grows to the proposal.** P4 control:
   `frame(minWidth: 40, maxWidth: 80)` on a 20pt child offered 100 answers
   **80**. The kernel answers 40, and
   `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum` pins 40. This
   is plan task 4, and it settles record §09's "whether a finite `maxWidth`
   frame grows". It does.
   **Closed 2026-09-15 by `FR-A`/`FR-M`** (`feat/frame-sizing`, `389c452`;
   integrated 2026-09-16, record §16): the kernel is greedy at any maximum and
   the test now pins 80.
2. **`Spacer()` has an 8pt default minimum between two views.** P5 control:
   `HStack(spacing: 0) { 20; Spacer(); 20 }` answers **48**. The kernel's nil
   `minLength` is 0 (`LayoutTree.swift:234`). Plan task 6.
3. **`aspectRatio` at `nil × nil` answers the child's own size.** P8b control:
   `Color.aspectRatio(2, .fit)` offered nil×nil answers **10×10**, and so does
   ratio −2. The kernel's intrinsic branch answers 10×5 for 2 and, by reading,
   −20×10 for −2. Plan task 7.
4. **Padding places its child at the child's own size.** P2b: the inner rect is
   20×20 at origin + inset. The kernel stores bounds minus insets (record §09
   hazard 4). Plan task 5. *2026-09-16:* task 5 did not take it (`OM-Q`: no
   `Sources/MetalUILayout` behaviour change); unowned, needs reassigning.
5. **SwiftUI's memo survives passes** (F/G/H). This is deliberately not adopted
   (`SA-H`). Reopen it only with a `lastNativeLayoutWork` count showing the
   cost.
6. **Not investigated, recorded so nobody re-derives them.**
   - I2's first pass places the child uncentred at (0, 0, 30, 30).
   - P7 places each stack child twice per host layout.
   - An earlier build of the contract probe got **zero** measurement calls when
     its `Counted` layout wrapped `EmptyView()`.
   - K's children place their subtrees in the reverse of the order the parent
     called `place` (third pass). MetalUI places in index order (`SA-E`).
7. **Moot after `SA-J`:** P4c's `ideal > max` answers the ideal (100), not the
   clamp.
8. **A single-child built-in stack passes its child's priority through** (L3,
   third pass). `ZStack { x.layoutPriority(2) }`, `HStack { … }` and
   `VStack { … }` each read 2; with two children they read 0, and a
   single-child custom layout reads 0. MetalUI's single-child stacks read 0.
   Why SwiftUI's do was not investigated. Plan task 6, which owns the stack
   algorithms. Lane 1's `aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules`
   pins MetalUI's 0 wrong on purpose.
9. **`.frame()` with no argument compiles silently** (third pass, after `SA-K`
   item 6's split), and so does `.frame(alignment:)`. SwiftUI deprecates
   `frame()`: `'frame()' is deprecated: Please pass one or more parameters.`
   Plan task 4. **Closed by `FR-J`**: `frame()` is a deprecated no-op on both
   paths, guarded by `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths`.
   `.frame(alignment:)` alone still compiles.

**Fixed, not carried:** priority through `.overlay` (L2). The second pass's
kernel read 0; `SA-D` now looks through overlay attachments.

**What it costs if wrong.** Items 1–4 and 8 are live SwiftUI divergences in
shipped proposal elements until their tasks land. The two this milestone
touches, items 4 and 8, are pinned wrong on purpose rather than left silent.

---

## SA-O — how the probes run: `/usr/bin/swift <file>` for the numbers, compiled with `OS_ACTIVITY_DT_MODE=1` for the diagnostics

**The finding.** Measured in this session, on macOS 26.6.2 (25G83):

- **`swift <file>` with the PATH's `swift`** (swiftly's swift.org 6.3.3) fails
  on both probes: exit 255, `JIT session error: Symbols not found: [ _$s7SwiftUI…`.
- **`/usr/bin/swift <file>`** (Apple Swift 6.4, swiftlang-6.4.0.33.1,
  Xcode-beta) runs both.
  - The validation probe exited 0. Every size and placement line is identical to
    the compiled run: `diff` of the non-diagnostic lines is empty.
  - It prints **0** of the compiled run's **22** diagnostic lines, even with
    `OS_ACTIVITY_DT_MODE=1` set (the only way the script form was run).
  - The contract probe matches line for line up to arm D, then dumps a JIT stack
    at D's trap (exit 133).
- **Compiled** (`swiftc <file> -o …`, then `OS_ACTIVITY_DT_MODE=1 ./binary`), both
  probes show everything, including the diagnostics. Without the environment
  variable, os_log output is not mirrored to stderr.

**The ruling.** Both headers document both forms. A claim about SwiftUI's
**answer** can be re-checked with the script form. A claim about a
**diagnostic** needs the compiled form.

**What it costs if wrong.** Someone re-running with the script form, seeing no
"Invalid frame dimension", concludes SwiftUI stopped diagnosing and relaxes
`SA-J`. The headers say so to prevent it.

---

## SA-P — sufficiency is proven by a PLAIN-IMPORT test file and by typecheck guards, and both instruments were checked before being relied on

**The finding.** Two measurements, taken because shape 16 says a `@testable`
file cannot see an access-level property.

1. **A plain `import` in one file of a test target is not widened by `@testable
   import` in another file of that target.** The test package had two files in
   one test target.
   - `One.swift` did `@testable import A` and called internal `secret()`.
   - `Two.swift` did `import A` and called `secret()`. It failed:
     `error: cannot find 'secret' in scope`.
   - With `Two.swift` reading an internal member of a public enum instead, it
     failed with `'factor' is inaccessible due to 'internal' protection level`.

   So `ReferenceLinearStack.swift`'s plain import proves the reference stack
   needs nothing internal, even though `MetalUILayoutTests` is full of
   `@testable` files.
2. **The typecheck guards' substrings come from a real compiler run.** A
   temporary skeleton of lane 1's public API (a protocol, four proxy types,
   `newNativeLayout` forwarding to an overlay, `requestNativeLayout`,
   `ProposalLayoutContainer`, `callAsFunction`, public factors) was added and
   built with `swift build --build-system native`.
   - The second pass typechecked the fixtures with `swiftc -typecheck
     -diagnostic-style=llvm -I .build/arm64-apple-macosx/debug/Modules -I
     …/MetalUIShaderTypes.build`, the flags `typecheck(_:importing:)` uses,
     **and its source shape**: the body wrapped in `func fixture() { … }`,
     with no `-swift-version`, which is Swift 5 mode. That shape makes every
     fixture type local and cannot hold a file-scope `extension`.
   - **The third pass rebuilt the skeleton**, with lane 3's frame split added,
     and typechecked every fixture **as a whole file, `public` declarations at
     file scope, with `-swift-version 6`**. The positive fixture exits 0. A
     `Sendable` violation in an external `ProposalLayout` is an error in that
     mode and a warning (exit 0) in Swift 5 mode, so the mode is observable. The
     results are quoted in `SA-C`, `SA-F` and `SA-K`, and lane 1 adds a
     `typecheckFile` helper with exactly this shape.
   - Each time, the skeleton was deleted and `Sources/` restored with
     `git checkout` (`git status --short` clean of `Sources/`).

**What it costs if wrong.** Neither instrument proves the **real**
implementation. Lane 1 re-prints every diagnostic from the real build and
mutates each new guard red once, because guards skip silently when the modules
directory is absent. The new `typecheckFile` helper's own instrument guard
(`typecheckFileChecksInTheSwift6LanguageMode`) must redden when its
`-swift-version 6` is deleted.

---

## SA-Q — what an earlier pass of this session got wrong, corrected here and in the probe headers

1. **The contract probe's source comment said arm M's NaN placement "does not
   return".** Run in this pass, compiled and as a script, it **traps**:
   `SwiftUICore/Layout.swift:1535: Fatal error: view origin is invalid: (nan, 0.0)`,
   exit 133. The comment is corrected, and `SA-J`'s row for a NaN position now
   reads "SwiftUI traps" rather than "hangs".
2. **The earlier probes left arms L, M, N, P9, P2b and P4d unrecorded.** They
   were written into the sources, and their headers still carried only the
   earlier arms. The earlier draft spec's validation table was written without
   them, so its validation table was incomplete in one row and unevidenced in
   another.
   - **`minWidth −∞`** had no row. P9 shows it is accepted: it answers 20 with no
     diagnostic.
   - **Padding NaN** was listed as rejected on a guess. P2c shows SwiftUI traps.
   - **The earlier draft said `swift <file>` cannot run the probes at all.** It
     can, with Apple's `/usr/bin/swift` (`SA-O`).
3. **The earlier draft's proxies were named `LayoutSubviews`/`LayoutSubview`.**
   That is SwiftUI's name for a proxy that **can** place (probe D). Reusing it
   for MetalUI's measurement-only proxy would suggest the SwiftUI capability. It
   is `MeasurementSubviews` here (`SA-C`).
4. **The earlier draft had no rejection for a legacy `Style` written onto a
   native node.** `SA-G` measured a spelling that compiles and is silently
   inert (`Toggle().width(Pixels(70))` on a proposal `Component`).
5. **The earlier draft isolated each recursion's depth guard by entering its
   run by hand**, which needs `measureNative`/`placeNative` widened to internal.
   That was not wrong. `SA-L` replaces it with real layouts that reach one
   recursion only (a measure-only entry, and a placement-only custom chain), so
   the private functions stay private.

**What it costs if wrong.** Nothing further. These are corrections already
applied. They are recorded because practices ("Seven ways a *record* goes
wrong") are assembled from exactly this kind of entry.

---

## SA-R — plan item (e)'s "compile-time" criterion is AMENDED, not met: the migration story is compile-checked for every spelling an external module writes, and a marker conformer's promise stays a run-time trap until plan task 3

**Status: delivered 2026-09-15 by `MC-G`** (`feat/modifier-composition`,
`f9e2c62`; integrated on `integrate/tasks-3-9-12`, record §13): a marker
conformer that registers a legacy node is a compile error, with seven named
holes (`Sources/MetalUI/ProposalNodeID.swift`'s header).

**The finding it answers.** The inventory's "Completion criteria for task 1"
asks for "a compile-time migration story for external custom elements", and
keeps task 2 open partly because "Nothing checks that a marker conformer
registers native nodes" (`2026-09-12-swiftui-layout-replacement-inventory.md:211-223`).
The second pass moved (e) to Done while its spec said that exact gap "stays
unchecked". The critic called that ticking it quietly (`SA-S` finding 3).

**The choice.** Item (e) is delivered under an **explicitly amended criterion**,
and the amendment is written into the inventory and the plan with this ruling's
id.

- **What is compile-checked** (lane 1's guards, file scope, Swift 6 mode):
  - an external leaf, container algorithm and container element build from
    public API alone;
  - a measurement proxy cannot place;
  - no proxy can be constructed outside the kernel;
  - legacy content is rejected by `ProposalLayoutContainer` and by
    `callAsFunction`, in every call spelling;
  - a fixed and a flexible frame dimension cannot be combined (lane 3).
- **What is run-time-checked, by traps with named messages** (lane 2):
  - a `ProposalElementGroup` conformer that registers a legacy node, inside any
    proposal container ("contains a legacy node");
  - a marker conformer over unconstrained content that hosts a legacy style
    modifier ("setStyle on a native layout node"; evidence 9 of the spec shows
    it compiles).
- **What is not delivered:** a compile-time check that a marker conformer
  registers native nodes. It moves to plan task 3's open proofs.

**Why not deliver the compile-time check here.** The only mechanism that makes
the compiler see which engine a node belongs to is a **typed node id**: native
registrars return a `ProposalNodeID` with no public initializer, and
`ProposalElementGroup` gains a requirement that returns it.

- **What it touches.** The eleven public `LayoutPass.requestNative*`
  registrars change their return and child types. Every proposal element in
  `Sources/` (`NativeElements.swift`, `NativeModifiedContent.swift`,
  `NativeOverlayModifier.swift`, `NativeTappable.swift`,
  `ProposalScrollView.swift`, `ProposalText.swift`) and the 41 integration
  tests change with them. The builder groups (`Pair`, `OptionalGroup`,
  `ArrayGroup`, `EmptyGroup`) and `Component` each need a conditional
  implementation of the new requirement.
- **Why it still leaves a hole.** `Element.requestLayout` keeps returning an
  untyped `LayoutNodeID`, because `Frame` renders every root through it. A
  conformer can therefore still declare its own `requestLayout` that registers
  a legacy node, so the typed requirement must be what proposal containers
  call. That is a second layout entry point on every proposal element.
- **Why task 3 owns it.** A second, typed layout entry point on the element
  protocols is a change to how elements compose, which is exactly plan task
  3's "typed modifier-composition foundation". Doing it in task 2 would
  redesign the element protocols ahead of the task that specifies them, and
  would change every proposal element's public signature twice.
- **This sketch is unmeasured** beyond `SA-P`'s result that an `internal`
  initializer is inaccessible from a plain import. Task 3 must build it, not
  assume it.

**What it costs if wrong.**

- **Task 2 closes with a known hole.** A marker conformer that lies compiles.
  The trap fires on first layout inside a proposal container, with a message
  naming the rule, and lane 2's tests pin both traps. A conformer that lies
  and is never placed in a proposal container is harmless: it is a legacy
  element.
- **If task 3 does not take it,** the amendment becomes permanent by neglect.
  The plan's task 3 entry lists it as an open proof so that cannot happen
  silently.

**Mutations:** lane 1's half done — the five guards and their red runs are
under `SA-F` and `SA-C`. Lane 2's half, the two run-time traps, is under
`SA-G`: `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer`
("contains a legacy node", reddened by deleting `newNativeLinearStack`'s child
loop once it has a witness sibling, `SA-T` item 1) and
`aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration` ("setStyle on a
native layout node", reddened by deleting that precondition).

---

## SA-S — the critic's eighteen findings against `3bb1ca1`, and what each became

A critic reviewed the second pass's commit through two lenses, SwiftUI parity
and testability, re-ran one probe and five typecheck checks of its own, and
edited nothing. This third pass took each finding in turn, re-ran probes where
the finding was about behaviour, and changed the spec, this doc and both probe
files. **Every finding is applied, with two exceptions:** finding 3 is applied
by amendment rather than by the check it first proposed, and the first part of
finding 4 is rejected, with reasons. Finding 4 raised three separate points, so
it has three rows.

| # | finding (short) | disposition | what changed, and the evidence |
|---|---|---|---|
| 1 | Priority through modifiers differs from SwiftUI; probe L too narrow | **applied** | Probe arms L2 (fifteen modifiers) and L3 (containers) added and run both ways. `.overlay` was the one MetalUI modifier that hid priority where SwiftUI does not. `nativeLayoutPriority` and the proxy now look through overlay attachments (`SA-D`), pinned by a new built-in test and new proxy arms. L3's single-child-stack pass-through is carried, pinned wrong on purpose (`SA-N` item 8). |
| 2 | Placing twice runs the subtree twice; arm I cannot discriminate | **applied** | `place` records; each subtree is placed once after `placeSubviews` returns (`SA-E`, spec kernel changes 5–6). Probe J now counts the child's `placeSubviews` runs (1) with J2 as the counter's control (2), and K's log order shows SwiftUI defers. New test `aSubviewPlacedTwicePlacesItsSubtreeOnce`, mutation "recurse eagerly inside `place`". Arm I is no longer cited for centring. |
| 3 | Item (e) ticked though the compile-time gap is only a run-time trap | **applied by amendment** | Not a compile-time check: `SA-R` amends the criterion explicitly, gives the typed-node-id design and its cost, and assigns it to task 3. The plan and inventory edits quote `SA-R`. |
| 4a | Every "diag" row is logged and drawn by SwiftUI, and MetalUI traps | **rejected** | Kept as deliberate: a precondition names the parameter at registration, and relaxing a trap later is additive where tightening a clamp is breaking. Recorded in `SA-J`'s costs. |
| 4b | `idealWidth: +∞` rejection contradicts "a measurement may be infinite" | **applied, rejection kept** | `SA-J`'s clause 2 is sharpened to "non-finite at a proposal with no infinite axis", which names why ideal +∞ is rejected and scopes the corollary to computed values. Accepting it was considered and rejected (`SA-J`). |
| 4c | Fixed + flexible has no SwiftUI spelling but is a MetalUI run-time crash | **applied** | The element API splits into SwiftUI's two overloads (`SA-K` item 6); a negative guard pins it; the kernel keeps its one-axis precondition as a backstop. Measured: SwiftUI's diagnostic, MetalUI's five diagnostics on the skeleton, and a 993 suite run with the split. |
| 5 | Depth parity claim false | **applied** | Claim deleted. `maxDepth` now follows legacy's 0.60 safety fraction over native ceilings, provisionally 96, bisected on lane 3's build across four kinds (`SA-L`). |
| 6 | Positive guard runs in Swift 5 mode inside a function wrapper | **applied** | Skeleton rebuilt; all fixtures re-typechecked at file scope with `-swift-version 6`; the wrapper's failure on the file-scope fixture and the mode's observable `Sendable` difference measured. Lane 1 adds `typecheckFile` and an instrument guard for it (`SA-P`). |
| 7 | Aspect-ratio predicate unprobed at negative and zero axes | **applied** | Probe P8c, 24 arms: the new predicate matches 24, today's 12; it also repairs positive ratios. New acceptance test (`SA-K` item 2). |
| 8 | Anchor test cannot see transposed factors | **applied** | Probe K2 (`.topTrailing` (95, 125), `.leading` (125, 115)) and the two arms in the test. |
| 9 | Guard mutation "drop `callAsFunction`'s constraint" is a no-op | **applied** | Confirmed on the real skeleton, and the two real mutations measured: struct-only reddens the container fixture; both redden all three (`SA-F`). |
| 10 | `measuringANativeTreeWritesNoRect`'s mutation truncates; side claim wrong | **applied** | Mutation is now "`measureNativeLayout` also calls `placeNative`"; the wrong side claim is replaced by the reason it was wrong. |
| 11 | Dropping the `defer { endLayout() }` truncates the run | **applied** | Mutation (A), `endLayout()` directly after `beginLayout()`, leaves in-process callers working and names every exit test it reddens; (B)'s truncation is recorded as its expected outcome, with a filtered run for the test's own red. |
| 12 | Work assertion (2) cannot redden under "disable the cache" | **applied** | Compared with a hand-derived literal (`SA-M`). |
| 13 | Once-per-proposal test can go red on a correct kernel | **applied** | Its `placeSubviews` now places child 0 at (50, 50); expected count 2. |
| 14 | `theProposalModifiersAcceptWhatTheKernelAccepts` not an exit test | **applied** | Declared exit `.success`. |
| 15 | Style-on-component test names an impossible root; reachable path misstated | **applied** | Renamed `…TrapsAtRegistration`, hosted in `Column`, with the call order that makes the fragment discriminate. `SA-G`'s reachable paths rewritten from measured typechecks, including the external-container path where `setStyle` is the only trap. |
| 16 | Undiscriminated validation clauses and NaN arms | **applied, refined** | Maximum rule is `>= 0`. The NaN arms keep their tests and get NaN-blind spellings (`!(x < 0)`…) as their own mutations, rather than only "delete the whole precondition". |
| 17 | Clause 7 overclaims | **applied** | `!isLayingOut` extended to every registration (one check in `appendNode`) and to `reset(generation:)`, with three new trap tests; clause 7 lists exactly what is checked and what is not. A suite run with the checks applied to both engines read 993. |
| 18 | Lane 3 edits a sentence `ProposedSize.swift` does not contain | **applied** | Removed from lane 3's files and `SA-K`; the sentence lives only in the 2026-09-12 spec, which lane 3's docs owed already supersede. |
| — | No-defect note: the re-fixture's in-closure `#expect` must change too | **applied** | `SA-K` item 5 and the spec name the (80, 60) → (70, 60) change. |

**Counts after this pass, as designed** (the lanes re-measure): tests 993 →
1010 → 1032 → 1084; guards 39 → 44 → 44 → 45. The second pass's design gave
1076 and 43.

**What it costs if wrong.** This table is the record of a review. If a row says
"applied" and the spec does not carry the change, the review's finding is
silently lost. Each row names where the change lives so that can be checked.

---

## SA-T — lane 2's tests as built differ from the spec in five places, each forced by a mutation or a red run

*Written by lane 2 during implementation, 2026-09-14. The spec's lane 2 tables
are corrected in place to match.*

1. **`aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer`
   registers a witness sibling after the `HStack`.** As specified (`HStack {
   Liar() }` alone), deleting the child loop from `newNativeLinearStack` left
   it **green**: measurement's `nativeNode(_:)` lookup traps later, at layout,
   with the same "contains a legacy node" message. So the test could not see
   SA-R's claim that the trap fires *at native registration*. The root is now
   `VStack { HStack { Liar() }; RegisteredAfterTheContainer() }`, where the
   sibling's `requestLayout` traps with "registration continued past a proposal
   container holding a legacy node". The same mutation now reddens it on its
   fragment.
2. **`writingARectDuringNativeMeasurementTraps` lays out the leaf as the
   root.** With the leaf under an overlay, the spec's mutation (raise the leaf's
   `measureDepth` only after its closure) left it **green**, because the
   closure still ran inside the overlay's own bracket. As the root the closure
   runs at depth 0 unless the leaf's bracket holds. Red before the
   implementation either way (`.failure → .exitCode(0)`).
3. **`resettingATreeDuringLayoutTraps`' red run** was not "an out-of-range
   index": the run died on the next stale-id read (`LayoutNodeID from
   generation 0 used against a LayoutTree at generation 1`). Still red on its
   fragment, as the spec required.
4. **`everyNativeRegistrarAcceptsNativeChildrenWithoutTrapping`'s mutation
   truncates the suite** (shape 11): routed through the checking `newNode`,
   every in-process native test with a child traps. The spec said only "which
   then traps". Its red line is recorded from the truncated log (`SA-G`). Its
   red run also needs the checking `newNode` to exist, so it was taken after
   the implementation, not before the tests were committed.
5. **`measuringANativeTreeWritesNoRect` rebuilds lane 1's reference tree** with
   the built-in stack in its own file. `ProposalLayoutTests.swift`'s
   `ReferenceTree` and its leaf helpers are `private`, and widening them would
   collide with same-named private helpers elsewhere in the target. The
   geometry, including lane 1's x.5 adjustment, is copied; the test also
   `try #require`s that the twin tree's rects are not all zero (shape 15), and
   asserts measured widths stay 0 as well as rects.

**What it costs if wrong.** Item 5 is a second copy of a fixture that can
drift from lane 1's. It is a regression fixture for "writes nothing", not an
equivalence oracle, so drift changes which tree is measured, not what the test
can catch.

**Mutations:** the runs that forced items 1, 2 and 4 are under `SA-G` and
`SA-H`.

---

## SA-U — lane 3's tests as built differ from the spec in four places

*Written by lane 3 during implementation, 2026-09-14. The spec's lane 3 text is
corrected in place to match.*

1. **The priority and ratio trap tests were not green on arrival.** The spec
   said `aNaNLayoutPriorityTraps` and the four ratio traps pass before the
   change because the old rules already reject their inputs. The processes did
   trap, but under the old messages ("layout priority must be finite", "aspect
   ratio must be finite and greater than zero"), and each test asserts its new
   rule's fragment, so all five were red on the fragment alone. Their rules'
   own red runs are the mutations under `SA-J`.
2. **`maxDepth` is 88** (`SA-L`): the provisional 96 was computed from
   ceilings the lane's own per-frame cost lowered.
3. **The branching work tree is pinned down further than the spec's sketch**,
   so its literals could be derived by hand: branch (i) has spacing 2, so the
   priority-0 leaves are compressed to a non-zero 27 (at spacing 0 the only
   compressed leaf gets 0, a weak rect assertion); priority 0 is expressed by
   the absence of a `layoutPriority` node; leaf sizes are in the test's doc
   comment. The derived counts are 16 calls, 27 hits and 25 misses.
4. **The modifier acceptance test lives in its own file,**
   `Tests/MetalUITests/ProposalModifierValidationTests.swift`, the spec's
   unnamed fifth file. It probes rendered bounds through leaves carrying the
   modifiers, and renders `Rectangle().layoutPriority(.infinity)` and
   `Rectangle().aspectRatio(-2)` in the same tree.

**What it costs if wrong.** Item 3's tree is one of many that would satisfy the
spec; a different tree gives different literals, so the numbers are this
tree's, not the kernel's in general.

**Mutations:** item 1's are under `SA-J`, item 2's bisection under `SA-L`,
item 3's under `SA-M`, item 4's under `SA-K`.
