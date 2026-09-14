# SwiftUI alignment — decisions for completing the native layout kernel

These are the rulings for finishing plan task 2
(`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`). Task 2 adds a public
layout protocol, closes the boundary between the two layout engines, and makes
the proposal engine robust. The milestone's earlier work (`a15ec83..7cfcddc`,
record §09) shipped without a decisions doc. **This is the first one, and it
starts here, at the design stage.**

Prefixed **`SA-`** and **lettered** (`SA-A`, `SA-B`, …), per this repo's
convention. **A bare `SA-3` is a typo, not a citation.** The next unused letter
is `SA-R`.

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

**Mutations:** owed by lane 1.

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

**Mutations:** owed by lane 1.

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

**Mutations:** owed by lane 1.

---

## SA-D — the proxy surface is priority, spacer-ness and a cached measurement, each by the built-in stack's own rule

**The choice.**

- **`priority`** is the value of a `layoutPriority` node that **is** the
  subview, else 0. The rule is `nativeLayoutPriority`'s
  (`LayoutTree.swift:710-713`).
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
  the same modifier applied outermost reads 2. SwiftUI's `priority` is the
  outermost modifier's alone, which is the kernel's rule.
- **Arms E and E2:** SwiftUI exposes **no** spacer test. A `Spacer` reads
  priority −∞, but so does any view given `.layoutPriority(-.infinity)`. MetalUI
  exposes `isSpacer` because its stack reads spacer identity. SwiftUI's stack
  does not (it probes flexibility), and matching that is plan task 6's question,
  not this one's.

**What it costs if wrong.**

- **`isSpacer` is a MetalUI-only notion.** If task 6 moves the built-in stack to
  flexibility probing, `isSpacer` becomes a public API with no built-in reader.
  It would then be carried or deprecated.
- **A layout that needs a child's baseline or identity cannot get one.** Adding a
  member later is additive.

**Mutations:** owed by lane 1.

---

## SA-E — placement: position, anchor and proposal; last placement wins; an unplaced subview is centred at the parent's proposal

**The choice.**

- **Where a placed subview lands.** `place(at:anchor:proposal:)` stores the
  subview at its answer to **`proposal`**, offset from `position` by
  `anchor.factor × size`. It then places the subview's subtree with that
  proposal.
- **Placed twice:** the last placement wins.
- **Never placed:** the subview is measured at the **parent's** proposal and
  placed centred in the parent's `bounds`.
- **`bounds` is root-absolute**, the contract every stored rect already has.

**Probes.**

- **Arm K**, the proposal and the anchor. Parent bounds are (25, 25, 150, 150).
  A `Color` placed with a 70×40 proposal lands at (25, 25, 70, 40).
  `.center` at +100 with 30×20 lands at (110, 115, 30, 20), and
  `.bottomTrailing` at (95, 105, 30, 20). Both children are proposal-responsive,
  so a placement that ignored the proposal would differ.
- **Arm J**, placed twice. The child lands at (100, 100, 40, 40), the second
  placement's position and proposal. The first placement is never seen by the
  child.
- **Arms I and I2**, never placed.
  - I: a parent at (50, 50, 100, 100) proposed 200×200, with a `Color` child,
    lands at (0, 0, 200, 200).
  - I2: a parent at (120, 70, 100, 100) proposed 100×100, with a fixed 30×30
    child, lands at (155, 105, 30, 30).
  - I2 also printed a first pass with the parent at (0, 0) and the child at
    (0, 0, 30, 30), which is not centred. Why was not investigated (`SA-N`).

**What it costs if wrong.** An author who forgets a subview gets a centred
subview rather than a trap, the same silence SwiftUI gives. The alternative, a
trap, would diverge from I/I2 for a mistake SwiftUI treats as legal.

**Mutations:** owed by lane 1.

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

**Measurement.** Against the `SA-P` skeleton, one plain-import positive fixture
compiled with exit 0. It declared a layout that reads `priority`, `isSpacer`,
`sizeThatFits`, `place` and both factors; a leaf; and a generic container
element. It used them as `HStack { Diagonal() { Leaf(); Spacer() }; Container { Leaf() }; Diagonal(alignment: .top) { Leaf() } }`,
`ProposalLayoutContainer(Diagonal()) { Leaf() }` and
`VStack { Diagonal { Leaf() }.padding(Edges(all: Pixels(3))) }`.

The negatives were:

- `_ = MeasurementSubviews()` → `'MeasurementSubviews' initializer is inaccessible due to 'internal' protection level`
- `_ = PlacementSubview()` → `'PlacementSubview' initializer is inaccessible due to 'internal' protection level`
- `_ = L() { Text("legacy") }` → `instance method 'callAsFunction' requires that 'Text' conform to 'ProposalElementGroup'`
- `_ = ProposalLayoutContainer(L()) { Text("legacy") }` → `generic struct 'ProposalLayoutContainer' requires that 'Text' conform to 'ProposalElementGroup'`

**What it costs if wrong.**

- **Three public entry points to one node kind.** They must stay in step.
- **Public factors are an API commitment.** Changing `ProposalAlignment` to
  SwiftUI's two-guide model later would break outside layouts.
- **Leaving `ProposalElementGroup` requirement-free keeps one hole open.** A
  marker conformer that registers a legacy node compiles and traps at run time.
  Lane 2 pins the trap, and the hole itself stays.

**Mutations:** owed by lane 1, including the red run of each of the four new
guards (39 → 43).

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
- **Measured compile:** `Toggle().width(Pixels(70))`, where
  `Toggle: Component` has `Rectangle()` content, compiles as a standalone
  expression. Placed inside `HStack` it is rejected: `generic struct 'HStack'
  requires that 'StyledComponent<Toggle>' conform to 'ProposalElementGroup'`.
- **The reachable path** is the root, and legacy containers, which the
  `newNode` trap now closes.

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

**Mutations:** owed by lane 2.

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
7. **Mutation during a call traps.**

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

**Mutations:** owed by lane 2. Clauses 1, 2 and 5 already hold, so their red runs
are the recorded mutations (the spec's red-first note).

---

## SA-I — ONE `isLayingOut` flag guards BOTH engines; native registration and a rect write from measurement also trap

**The choice.**

- **One flag.** `computeNativeLayout` and `measureNativeLayout` bracket their
  bodies with the existing `beginLayout()`/`endLayout()`. Three existing traps
  now reach the native path: `setStyle` during layout, native re-entry, and
  legacy `computeLayout` called from a native measure closure. The reverse,
  native layout called from a legacy closure, traps too.
- **Registration.** Every native registrar traps while `isLayingOut`.
- **Rect writes.** `setLayout` traps while a native measurement body is running.

**Why one flag, not two.** The two engines write the same `layouts` array
through the same `setLayout`, and a legacy `measureNode` memoizes against the
same `styles`. A second flag would let a native closure run legacy layout over
the tree mid-run, which is exactly the hazard the first flag exists to stop.

**Why the registration trap.** A measure closure that registers nodes
mid-layout grows the arrays the run is indexing. That is harmless today by
accident, and wrong the moment a registrar is given a live id.

**Why the `setLayout` trap.** It is the only way clause 4 of `SA-H` can be
enforced rather than merely true. A leaf closure holding the tree, through an
`@unchecked Sendable` box, can call it today.

**Measurement.** None new. Today's behaviour follows from reading:

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

**Mutations:** owed by lane 2.

---

## SA-J — validation: reject ONLY what SwiftUI rejects or what makes MetalUI's answer non-finite; a measurement may be infinite, a stored rect may not, nothing may be NaN

**The choice.**

- **The rule.** A native registrar rejects a parameter only if SwiftUI rejects
  it — by a diagnostic, a trap, a hang, or having no spelling for it — or if the
  parameter would make MetalUI's answer non-finite.
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
| idealWidth +∞ | no diag; **inf at nil** (P4b), 20 at 100 (P4d) | reject: non-finite at the unspecified proposal |
| min > max, min > ideal, ideal > max | diag (P4, P4c) | reject |
| fixed and flexible on one axis | no overload exists | reject: no spelling |
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

- **Why a measurement may be infinite.** "An unconstrained answer to an unbounded
  proposal" is legitimate: P6's `Color` offered ∞ answers ∞.
- **Why a stored rect may not.** Prepaint, paint, hit-testing and rounding all
  do arithmetic on it, and `round(inf) − round(inf)` is NaN.
- **Why NaN is never acceptable.** It is unequal to itself. It misses the cache
  every time (record §09), and it poisons every comparison downstream.

**The four rows decided on more than the first clause.**

- **`idealWidth: +∞`** gets no SwiftUI diagnostic. It is rejected because the
  unspecified proposal is the one every stack child and every scroll content
  receives on its main axis, so an infinite ideal becomes an infinite
  measurement in the most ordinary tree. Rejecting at registration names the
  parameter. Rejecting at checkpoint 3 would name a sibling's rect several nodes
  away.
- **Padding NaN** is finite in SwiftUI's measurement but traps SwiftUI's own
  placement (P2c).
- **Padding −∞** is finite in measurement and non-finite in placement (P2c).
- **Ratio 0** is finite on one proposal shape and infinite on another (P8).

**What it costs if wrong.**

- **A MetalUI app crashes where SwiftUI would log and draw something.** For a
  diagnosed frame dimension, SwiftUI clamps and continues (P3: width −10
  answered 0×20).
- **The trade is deliberate.** A precondition names the parameter at
  registration. SwiftUI's diagnostic names nothing and draws a guess.
- **If the crash proves too harsh,** relaxing a precondition to a clamp is
  additive. Tightening a clamp back into a crash later would break callers.

**Mutations:** owed by lane 3.

---

## SA-K — the relaxations and repairs `SA-J` forces on today's kernel

**The choice.** Four source changes and one test re-fixture:

1. **Priority.** `newNativeLayoutPriority` accepts ±∞: `isFinite` becomes
   `!isNaN`. It has **trapped on ±∞ since `d250743`**.
   `stackMainAllocations` already sorts ±∞ correctly: `Set(...).sorted(by: >)`
   over `[inf, 0]` is `[inf, 0]`.
2. **Aspect ratio.**
   - `newNativeAspectRatio` accepts a negative ratio: `ratio > 0` becomes
     `ratio != 0`.
   - `aspectRatioSize`'s two-axis branch compares `width / ratio <= height`
     (`.fit`) and `>=` (`.fill`).
   - For ratio > 0 and height > 0 that is the same predicate as today's
     `width / height <= ratio`.
   - For ratio −2 at 100×80, today's predicate picks the height branch and
     answers −160×80. P8 says 100×−50.
3. **Padding.** The measurement becomes `max(0, child + leading + trailing)` per
   axis. Today −15 on 20 answers −10, and P2 says 0. P2b's leading −30 /
   trailing 5 answers 0×20, which proves the clamp is per axis.
4. **The MetalUI modifiers.** `.aspectRatio` and `.layoutPriority`
   (`NativeModifiedContent.swift:271-272, 279`) adopt the kernel's rule.
5. **The re-fixture.** `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes`
   (`NativeLayoutTests.swift:168`) declares ideal 90 > max 80, which `SA-J`
   rejects. It is re-fixtured to ideal 70, with expectations re-derived by hand:
   proposal (70, 60), measurement 70×20, child rect `(10, 14, 30, 10)`.

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

- **Item 2 changes the two-axis branch for every ratio.** The positive-ratio
  equivalence rests on height > 0. At a zero-height proposal both predicates
  pick the height branch and answer 0×0, by reading.
- **Item 5 drops the only pin of the ideal-clamped-by-max arithmetic.** Once
  ordering is validated that arithmetic is unreachable, so nothing is lost
  unless validation is ever relaxed.

**Mutations:** owed by lane 3.

---

## SA-L — a native depth guard of 64 levels: its own constant, the same number, one counter across measurement and placement

**The choice.** `NativeLayoutRun.maxDepth = 64`.

- **One counter.** `run.depth` is entered at the top of `measureNative` and
  `placeNative` and left on return. Placement calls measurement from inside
  itself, so the one counter tracks the real combined stack.
- **The message:** "native layout recursion exceeded 64 levels at node …".
- **It is its own constant, not `LayoutContext.maxDepth`,** because the two
  engines' per-level costs differ.
- **It is the same number,** so a tree the legacy engine accepts is not
  rejected by its proposal port for depth alone.

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
smallest real stack. Native's 64/171 = 0.37 is more headroom, not less.

**Not measured:** release, and the custom kind. A `ProposalLayout` level adds an
existential call and a proxy frame, so its ceiling is lower than the stack's. So
lane 3 bisects the custom kind before committing, and keeps 64 only if
64 ≤ 0.60 × the smallest ceiling. Otherwise it takes the largest multiple of 8
under that bound.

**Why three trap tests, not one.** A tree deeper than the limit traps in
measurement first. So a test through `computeNativeLayout` stays green if `enter`
is deleted from `measureNative` alone, because placement still traps.

- **The measurement-only test** (`measureNativeLayout`) isolates that deletion.
- **A placement-only chain** of custom layouts isolates `placeNative`'s. Each of
  its `sizeThatFits` returns a constant without measuring, so measurement never
  recurses.

`LayoutContextTests.swift:150-173` records the same shape-4 hazard for legacy
`placeNode`.

**What it costs if wrong.** If the custom kind's ceiling is below 107 debug
levels, 64 stops being 0.60-safe on a 1 MB main thread. Then a deep custom
layout chain dies at SIGBUS with no attribution, the failure the guard exists to
prevent. The bisection before committing is the defence.

**Mutations:** owed by lane 3, including the custom-kind bisection result.

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
  must redden under "disable the cache".

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

**Mutations:** owed by lane 3.

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
2. **`Spacer()` has an 8pt default minimum between two views.** P5 control:
   `HStack(spacing: 0) { 20; Spacer(); 20 }` answers **48**. The kernel's nil
   `minLength` is 0 (`LayoutTree.swift:234`). Plan task 6.
3. **`aspectRatio` at `nil × nil` answers the child's own size.** P8b control:
   `Color.aspectRatio(2, .fit)` offered nil×nil answers **10×10**, and so does
   ratio −2. The kernel's intrinsic branch answers 10×5 for 2 and, by reading,
   −20×10 for −2. Plan task 7.
4. **Padding places its child at the child's own size.** P2b: the inner rect is
   20×20 at origin + inset. The kernel stores bounds minus insets (record §09
   hazard 4). Plan task 5.
5. **SwiftUI's memo survives passes** (F/G/H). This is deliberately not adopted
   (`SA-H`). Reopen it only with a `lastNativeLayoutWork` count showing the
   cost.
6. **Not investigated, recorded so nobody re-derives them.**
   - I2's first pass places the child uncentred at (0, 0, 30, 30).
   - P7 places each stack child twice per host layout.
   - An earlier build of the contract probe got **zero** measurement calls when
     its `Counted` layout wrapped `EmptyView()`.
7. **Moot after `SA-J`:** P4c's `ideal > max` answers the ideal (100), not the
   clamp.

**What it costs if wrong.** Items 1–4 are live SwiftUI divergences in shipped
proposal elements until their tasks land. The one this milestone touches, item 4,
is pinned wrong on purpose rather than left silent.

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
   - The fixtures were typechecked with `swiftc -typecheck -diagnostic-style=llvm
     -I .build/arm64-apple-macosx/debug/Modules -I …/MetalUIShaderTypes.build`,
     the flags `typecheck(_:importing:)` uses.
   - The results are quoted in `SA-C` and `SA-F`.
   - The skeleton was deleted and `LayoutTree.swift` restored with
     `git checkout`.

**What it costs if wrong.** Neither instrument proves the **real**
implementation. Lane 1 re-prints every diagnostic from the real build and
mutates each new guard red once, because guards skip silently when the modules
directory is absent.

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
