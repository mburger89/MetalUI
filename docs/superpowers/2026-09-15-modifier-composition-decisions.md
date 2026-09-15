# Modifier composition — decisions for plan task 3

These are the rulings for plan task 3, "Build a typed modifier-composition
foundation" (`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`). They are
written at design time, on `feat/modifier-composition` at `f64e58a`, before any
lane runs, and **revised at design review** (`MC-N`). A revised ruling says so
in its heading's first paragraph and keeps what it replaced where the
replacement's reason depends on it.

Prefixed **`MC-`** and **lettered** (`MC-A`, `MC-B`, …), per this repo's
convention. **A bare `MC-3` is a typo, not a citation.** The next unused letter
is **`MC-O`**.

Read alongside:

- `docs/superpowers/specs/2026-09-15-modifier-composition-design.md`, which
  holds the three lanes, their API, files, tests and mutations;
- `docs/record/10-modifier-composition.md`, this track's record;
- `docs/probes/swiftui-modifier-identity.swift` and
  `docs/probes/swiftui-modifier-order.swift` (SwiftUI probes, output in their
  headers) and `docs/probes/modifier-composition-skeletons/` (typecheck,
  timing and allocation skeletons, output in their headers);
- `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`, whose `SA-R`
  hands this task its compile-time open proof. That doc is not edited here.

## How to read the letters

- **`MC-A`…`MC-C`** — the legacy wrapper representation and its identity
  rules. Lane 2 implements them; lane 1 writes the oracle they must match.
- **`MC-D`…`MC-F`** — the open proofs on today's code: `@State` across chained
  modifiers, the overlay identity collision, once-per-phase delegation. Lane 1.
- **`MC-G`, `MC-H`** — `SA-R`'s compile-time check: the typed native node id,
  and the one helper its defaults share. Lane 3.
- **`MC-I`…`MC-K`** — what the representation owes the rest of the framework:
  per-site guard arms, the demo, allocation. Lanes 2 and 3.
- **`MC-L`** — deferred, with owners. **`MC-M`** — method: what was measured,
  where, and what was only read. **`MC-N`** — the design review, finding by
  finding.

**Every ruling ends with a "Mutations" line reading _owed by lane N_.** The lane
that implements a ruling replaces it with the mutations it ran and the tests
each one reddened. A ruling whose line still says "owed" has not been
mutation-tested and must not be cited as proven.

## Where each number was measured

All in the worktree `/Users/maxburger/Developer/MetalUI-modifier-composition`
at `f64e58a`, one agent live in it. macOS 26.6.2 (25G83). Two toolchains are
installed: `xcrun swiftc` and `/usr/bin/swift` are Apple Swift 6.4
(swiftlang-6.4.0.33.1); PATH `swiftc` (swiftly) is Apple Swift 6.3.3
(swift-6.3.3-RELEASE).

**Design session, 2026-09-14/15:**

- **The SwiftUI identity probe**, both forms (`/usr/bin/swift`, and compiled
  with `swiftc` 6.3.3): byte-identical stdout, exit 0. The design reviewer
  re-ran the script form and matched the header byte for byte.
- **The overlay collision, end to end**, by an uncommitted scratch test
  (`scratchMeasureOverlayIdentity`, run with `--filter`, since deleted),
  through a real `Window` and `FakePlatformWindow`.
- **The one-cursor overlay fix.** It was applied temporarily and the same
  scratch test re-run. Then the **whole suite**: `Test run with 1085 tests in
  1 suite passed` (1084 committed + the scratch test), no `error:`, no
  `warning:`. The source was restored from a `cp` backup, and
  `git status --short` showed only the new untracked files.
- **The orphan-legacy-node run** (`scratchMeasureOrphanLegacyNode`, same
  scratch file, since deleted).
- **Two typecheck skeletons.** The first recording said `xcrun swiftc` 6.3.3;
  which toolchain that was is not established, since `xcrun swiftc` now reports
  6.4. `TypedNodeKit.swift` was re-run at design review under both toolchains,
  with identical results.

**Design review, 2026-09-15** (`MC-N`):

- **`chain-typecheck-timing.py`**: three wrapper designs timed at 8, 12, 16
  and 24 modifiers, with two argument spellings and a demo-shaped builder,
  under `xcrun swiftc` 6.4; cross-checked under 6.3.3.
- **`LayerBaseKit.swift`** and five clients, and **`CombinedKit.swift`** with
  the eight typed clients and one layered client, under `xcrun swiftc` 6.4.
- **`LayerAllocationModel.swift`**, at `-Onone` and `-O`, under both
  toolchains, plus a `consuming` variant.
- **`swiftui-modifier-order.swift`**, both forms (`/usr/bin/swift` 6.4 and
  `swiftc` 6.3.3): byte-identical stdout, exit 0.
- **Two uncommitted scratch test files, run with `--build-system native
  --filter` and deleted before commit:**
  - `zzScratchLegacyModifierOrder` (lane 1 test 10's numbers on today's code);
  - `zzScratchDuplicateInOneContainer`, `zzScratchOneChildTwoContainers` and
    `zzScratchOrphanLegacySubtree` (`MC-G` holes 4 and 6).

  `git status --short` was empty after each deletion.

**Carried, not re-taken:** the suite count 1084, 45 guards and 97 goldens at
`553b980` (plan task 2's entry). `f64e58a` differs from `553b980` in docs only.

---

# The decisions

## MC-A — legacy modifier wrappers become ONE flat type, `ModifiedElement<Content>`, reached through ONE overload per modifier: one layer per modifier, one node and one identity level per layer, and a type that does not grow along a chain

**Revised at design review (`MC-N` findings 1 and 9).** The first design
declared `padding`/`frame` on the protocols returning `ModifiedElement<Self>`,
and redeclared them concretely on `ModifiedElement` returning
`ModifiedElement<Content>`. That shape infers the flat type, but its
type-checking time is exponential in chain length (measured below). The overload
set is replaced; the representation is not.

**The choice.**

```swift
public protocol ElementGroup {                      // ElementGroup.swift, additive
    // … existing requirements …
    associatedtype LayerBase: ElementGroup = Self
    func _wrap(_ layer: ModifierLayer) -> ModifiedElement<LayerBase>
}
public struct ModifiedElement<Content: ElementGroup>: Element, StyledElement {
    public typealias LayerBase = Content
    public var content: Content
    // internal: the outermost layer inline, the rest in an array (MC-K)
    public func _wrap(_ layer: ModifierLayer) -> ModifiedElement<Content>   // appends
}
extension ElementGroup where LayerBase == Self {
    public func _wrap(_ layer: ModifierLayer) -> ModifiedElement<Self>      // wraps
}
extension StyledElement { func padding(_:) -> ModifiedElement<LayerBase> }  // both spellings
extension ElementGroup  { func frame(width:height:) -> ModifiedElement<LayerBase> }
```

- **A layer** (`ModifierLayer`, a public type with internal members) holds a
  `Style`, a `Decoration`, `Handlers` and an `ElementID?`. That is exactly
  what one `Box` around one child carries.
  - `.padding(_:)` makes a layer whose `style.padding` holds the edges.
  - `.frame(width:height:)` makes one centred on both axes with the given
    sizes, which is `FrameModifier.init` today.
- **One overload per modifier spelling.** Its return type is
  `ModifiedElement<LayerBase>`, and it calls `_wrap`.
  - **On a `ModifiedElement`**, `LayerBase` is its content, and `_wrap`
    appends a layer.
  - **On anything else**, `LayerBase` is `Self`, and the default `_wrap`
    wraps.
  - **In generic code**, dispatch goes through the requirement, so a generic
    `.padding` over a chain also appends.
- **`ModifiedElement`'s `style`, `decoration`, `handlers` and `elementID` read
  and write the outermost layer.** So every `Self`-returning `StyledElement`
  modifier written after a wrapper configures that wrapper, as it configures
  today's `Box<Self>`.
- **`FrameModifier` is deleted**, with its public `init(content:width:height:)`.
  No typealias is kept: `FrameModifier<FrameModifier<T>>` would name a nested
  type that is now unspellable.
- **The proposal path keeps `ModifiedContent`** (a closed enum over proposal
  content). Unifying the two is plan task 7's, after the legacy engine goes.

**Why flat, when SwiftUI nests.**

- **SwiftUI's type nests.** Probe arm T: SwiftUI's
  `Color.red.padding(4).padding(8)` is
  `ModifiedContent<ModifiedContent<Color, _PaddingLayout>, _PaddingLayout>`.
  MetalUI diverges **in type shape only**, and on purpose.
- **The plan asks for a type that does not grow.** Its task-3 text asks for a
  representation that "can nest without forcing callers to expose ever-growing
  concrete types such as `Box<Box<Box<Text>>>`".
- **The pressure is prospective, not present.** **No stored type in `Sources/`
  spells a `.padding`/`.frame` chain today** (grep). The first draft of this
  ruling cited the demo's `CounterPanel`
  (`Box<Pair<Pair<Box<Text>, Box<Text>>, Box<Text>>>`) as evidence. That type
  comes from hand-built `Box {}` calls (`main.swift:244-290`), no `.padding` is
  involved, and this design leaves it unchanged (design review finding 9).
  - **Task 4** converts `width`/`height` into layers. Every chained sizing call
    would otherwise add a type level, so chains of the lengths timed below
    become ordinary.
  - **A stored subtree** would then spell each of those levels.
- **The flat type grows once**, at the first wrapper, and never again. Every
  observable of the nested shape — identity, nodes, rects, hitbox and paint
  order, animation slots — is kept (`MC-B`).

**Measured: type-checking time** (`chain-typecheck-timing.py`, `xcrun swiftc`
6.4, `probeBody` from `-debug-time-function-bodies`). The chain is `Text("d")`
followed by pairs of `.padding(x).frame(width: x)`, over a base carrying the
real module's competing overloads (proposal `padding`/`frame`s,
`Component.padding`/`width`):

| modifiers | `Pixels(i)`: nested today | single overload (chosen) | first design | integer literals: nested | single | first design |
|---|---|---|---|---|---|---|
| 8 | 0.54 ms | 0.50 ms | 4.80 ms | 0.67 ms | 0.66 ms | 6.69 ms |
| 12 | 0.64 ms | 0.77 ms | 183.87 ms | 0.97 ms | 1.01 ms | 106.61 ms |
| 16 | 0.83 ms | 0.85 ms | **44 897.85 ms** | 1.28 ms | 1.36 ms | 1 911.60 ms |
| 24 | 1.34 ms | 1.36 ms | not run | 1.86 ms | 1.99 ms | 6 616.70 ms, then **"the compiler is unable to type-check this expression in reasonable time"** |
| demo-shaped builder | 5.87 ms | 5.95 ms | 61.84 ms | | | |

- **Under swift.org 6.3.3:**
  - single overload, 24 `Pixels`: 1.57 ms;
  - first design: 196.82 ms at 12 `Pixels`, and 1 898.56 ms at 16 integer
    literals;
  - first design at 24 integer literals: the same error.
- **The reviewer's run of the first design** read 18.6 s and then the error at
  16 `Pixels`. This run completed at 44.9 s. Same exponential, different solver
  cut-off.

**Measured: inference and reachability** (`LayerBaseKit.swift`, plain import,
Swift 6). Without a contextual type:

- `Leaf().padding(4).frame(width: 60).padding(8).width(70)` is
  `ModifiedElement<Leaf>` with 3 layers;
- a `Component`'s `.frame(width:).padding(_:)` is `ModifiedElement<Comp>`;
- an external generic group's `.frame` is `ModifiedElement<Group<Leaf>>`;
- a stored `Row<ModifiedElement<Leaf>>` typechecks;
- `Rect().frame(width: 1)` on a proposal type is still `ModifiedContent<Rect>`;
- `wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T.LayerBase> { t.padding(8) }`
  over a one-layer chain returns 2 layers;
- external conformers that never mention `LayerBase` or `_wrap` compile.

**The nested shape is unreachable:**

- `let _: ModifiedElement<ModifiedElement<Leaf>> = Leaf().padding(4).padding(8)`
  fails: "cannot assign value of type 'ModifiedElement<ModifiedElement<Leaf>.LayerBase>'
  (aka 'ModifiedElement<Leaf>') to type 'ModifiedElement<ModifiedElement<Leaf>>'";
- a generic `-> ModifiedElement<T>` fails: "cannot convert return expression of
  type 'ModifiedElement<T.LayerBase>' to return type 'ModifiedElement<T>'";
- the initializer is internal.

**Measured with lane 3** (`CombinedKit.swift`): `LayerBase` and the typed node
id coexist on one `ElementGroup`. No second associated-type restatement is
needed, and every typed client's diagnostic is unchanged.

**The hole this adds** (`layer-client-liar.swift`, exit 0). A conformer can
declare `typealias LayerBase = Leaf` and implement `_wrap` by forwarding to
another value, and its `.padding` then silently drops the receiver.

- **No access-control spelling closes it.** A protocol requirement is as
  visible as its protocol.
- **It is named and documented instead.** `_wrap` is underscored, and its doc
  says it is not for conformers.
- **Owner:** task 7, when the legacy protocols go.
- **For integration:** it goes into the holes list.

**Why not a modifier protocol (`ElementModifier`) now.**

- **The 2026-09-12 typed modifier spec proposed one.** No caller needs a
  user-defined legacy modifier, and the legacy engine is scheduled for
  deletion (task 7).
- **It would re-open a closed exposure.** A protocol whose requirements must
  reach `LayoutPass` would re-open the `LayoutNodeID` exposure that
  `LayoutModifier`'s doc comment rules out.
- **The layer's members stay internal**, so tasks 4 and 5 can add layer kinds
  (a paint-only layer, a proposal frame) without a public break.

**What it costs if wrong.**

- **Source breaks, all compile errors, none silent:**
  - `FrameModifier` spelled by name (one test file, `ComponentTests.swift`,
    plus the other tracks' spec text; see the spec's merge notes);
  - `Box<Self>` spelled as the result of `.padding` (no caller in `Sources/` or
    `Tests/`, by grep);
  - `Box`-only API after `.padding`, i.e. `.flexDirection` (no caller, by
    grep).
- **`ElementGroup` gains two requirements**, both defaulted. An external
  conformer is unaffected unless it already declares a member named
  `LayerBase` or `_wrap`.
- **SwiftUI type-shape parity is lost.** An author porting a stored
  `ModifiedContent<ModifiedContent<…>>` spelling cannot write the MetalUI one
  the same way. Nothing in MetalUI spells a legacy chain type today except the
  test above.
- **A chain's length can now vary at run time without a type change.** `MC-C`
  rules what that does and pins it.
- **The `_wrap` hole above.**
- **If the single-overload design regresses to the first design's shape**, a
  24-modifier chain stops compiling. Lane 2 test 6 is that chain, so the
  regression is a build failure, not a slow build.

**Mutations:** owed by lane 2. Lane 2 also owes the real-module type-check
measurement (spec, lane 2).

---

## MC-B — the flat chain, a generic `.padding` over a chain, and hand-built nested `Box`es must be OBSERVATIONALLY IDENTICAL; the hand-built boxes are the oracle, lane 1 writes it before the type exists, and every compared observation has its own disagreeing oracle

**Revised at design review (`MC-N` findings 1 and 6).** Under the first `MC-A`,
a nested `ModifiedElement<ModifiedElement<…>>` was reachable, from a contextual
type or from generic code, and had to be compared. Under the revised `MC-A`, it
is unspellable outside the module. What generic code produces instead is a flat
chain with one more layer, reached by dynamic dispatch, and that is what is
compared. The rect oracle alone could not show that the other observations can
disagree.

**The choice.** For the same modifiers in the same order, these three trees
produce the same observations:

1. the flat chain (`X.padding(4).frame(width: 60, height: 40).padding(8)`);
2. the same chain built partly in generic code
   (`func wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T.LayerBase> { t.padding(8) }`
   applied to `X.padding(4).frame(…)`). Its type must EQUAL the flat chain's;
3. hand-built `Box(style:decoration:content:)` values, one per modifier, with
   the layer's style, and the layer's own `Self`-returning modifiers applied to
   that `Box`.

A **typecheck guard** pins that the nested spelling does not compile (lane 2
guard 7).

**The observations compared:**

- the wrapped element's `GlobalElementID` and bounds;
- each layer's hitbox: id, bounds, registration order;
- the scene's rects in emission order, with bounds and colour;
- `Frame.tree.nodeCount`;
- for each layer id, `StateTable.isLive(animRetentionSlot(for:))`.

**One disagreeing oracle per observation** (practices shape 15). Each is
`try #require`d to differ from the oracle before the real comparison runs:

| observation | disagreeing oracle |
|---|---|
| rects | paddings 4 and 8 swapped |
| ids (the wrapped element's, the hitboxes') | `.id("mid")` moved to another layer |
| the hitbox list | one layer's `onClick` dropped |
| `$anim` liveness, node count | one layer fewer |

**Why the oracle is hand-built boxes, and why lane 1 writes it.**

- **It is green on arrival.** Today's `.padding` *is* a `Box`, and today's
  `.frame` is a `Box`-equivalent (`FrameModifier`'s three phases are, line for
  line, `Box`'s). So a test comparing today's chain with hand-built boxes
  passes before any change.
- **Staying green is the migration proof.** Lane 2 then replaces the chain's
  representation, and the same test staying green shows that identity,
  `@State`, handlers and phase order were preserved.
- **The oracle cannot move with a mutation.** Its side never runs
  `ModifiedElement` code (practices shape 12).
- **Each observation's own disagreeing oracle** shows that that comparison can
  fail. The reviewer noted that swapped paddings change rects while leaving
  ids, hitboxes and liveness comparable.

**What it costs if wrong.** Without it, lane 2 could ship a representation whose
inner layers share the outer layer's id: one `$anim` slot, one hitbox id, and a
wrapped element re-seeded one level up. Every existing padding and frame test
asserts rects and node counts, and all of them would stay green.

**Mutations:** owed by lanes 1 and 2.

---

## MC-C — identity: the outermost layer takes the parent's cursor slot, each inner layer is `positional(0)` (or its name) under the next one out, the content numbers from 0 under the innermost layer; a run-time change of layer COUNT resets the wrapped element's state, a change of layer VALUES does not, and a layer added at run time is ADOPTED by the new outermost layer

**Revised at design review (`MC-N` finding 5).** The first draft said "both
directions agree with SwiftUI". Only the wrapped element's reset is measured
parity. What the layers themselves do when a layer is added has no SwiftUI
counterpart, and is now named, pinned and offered as a candidate divergence.

**The choice.**

- **The ids.** For a chain of n layers:
  - `L[n-1]` (outermost) gets
    `GlobalElementID.child(of: parent, at: cursor, name: L[n-1].elementID)`;
  - `L[k]` gets `.child(of: id(L[k+1]), at: 0, name: L[k].elementID)`;
  - the content group is laid out `under: id(L[0])` with a fresh cursor at 0.

  **This is exactly the path `Box<Box<…>>` produces today**, so no state entry,
  focus slot or `$anim` baseline moves when `.padding` and `.frame` change type.
- **`.id(_:)` names the layer it follows.** `X().padding(4).id("a").padding(8)`
  names the padding-4 layer, as it names the inner `Box` today. The record §01
  remedy "name the trailing sibling" still needs `.id` outermost.
- **A layer's values are not part of its identity.**

**SwiftUI, probe `swiftui-modifier-identity.swift`:**

| arm | change between two updates | SwiftUI |
|---|---|---|
| C | every value in a three-modifier chain (padding 4→8, frame 100→120, padding 2→6) | state **kept** |
| D2 | one modifier's value 0→8, count unchanged | **kept** |
| D1 | chain length 1→2, through `if`/`else` | **new** state |
| D3 | chain length 1→2, behind `AnyView` | **new** state |
| A / B | controls: plain input change / `.id(generation)` | kept / new |

**What is parity, and what is not.**

- **The wrapped element: parity.**
  - A value change keeps the wrapped element's state, like C and D2.
  - A layer-count change resets it, like D1 and D3.

  That second direction is argued, not measured. D3 shows a reset when the
  **type** behind `AnyView` changes. SwiftUI cannot express a chain that
  changes length while keeping its type, so **no arm covers the flat
  `ModifiedElement` case itself** (`var c = X().padding(4); if flag { c = c.padding(8) }`,
  one type). MetalUI resets there because the content moves one level deeper,
  which is the structural reason D1 and D3 reset. Lane 2 test 3 pins
  MetalUI's behaviour.
- **The layers themselves: no SwiftUI counterpart.** When a layer is added at
  run time, **the new outermost layer takes over the old outermost layer's
  identity**: its `$anim` baseline, its hitbox id, and any active or focus
  state keyed on that id. The old layer's own values move one level in, to a
  fresh id.
  - **In SwiftUI**, D1 creates everything anew.
  - **In MetalUI**, `withAnimation { flag = true }` over
    `.padding(4)` → `.padding(4).padding(8)`: the padding-8 layer animates from
    4 to 8, and the new inner padding-4 layer snaps. The content therefore
    jumps from 4 to 8 at t = 0 and then slides to 12. That is predicted by
    reading, and lane 2 test 5 measures and pins it.
  - **Why it is kept.** The alternative, keying the outermost id on the layer
    count, breaks `MC-B`'s identity with nested boxes, and so re-seeds every
    padded element's state on the change of type. It is the same adoption rule
    as record §01's trailing sibling, applied to layers.
  - **For integration:** a **candidate divergence**, "a layer added to a chain
    at run time is adopted by the new outermost layer (no SwiftUI analogue)",
    for CLAUDE.md's table.

**What it costs if wrong.**

- **If a later change keys a layer's id on its values** (for instance, to let a
  frame change "look like" a new view), an animated `.padding(open ? 16 : 8)`
  resets its content's `@State` on every toggle, with no diagnostic.
- **If it keys content identity on the outermost layer only**, adding a layer
  at run time silently keeps state that the structure says should reset.
- **If the adoption is mistaken for SwiftUI's behaviour**, an author expects a
  fresh layer and gets an animation from the old layer's baseline.

All three are pinned (spec, lane 2 tests 3, 4 and 5).

**Mutations:** owed by lane 2.

---

## MC-D — `@State` across chained modifiers is proven on BOTH paths, with the wrapped element inside a proposal container on the proposal path so that lane 3's typed entry point is the one exercised

**The choice.** Two end-to-end tests through a real `Window`:

- **legacy:** a stateful `StyledElement` leaf under
  `.padding(4).frame(width: 60, height: 40).padding(8)` in a `Row`, clicked
  three times, then two more frames. It reads 3. Its id is three levels below
  the chain's slot, and all three layer ids hold a live `$anim` slot, so the
  two chained modifiers are two identities with distinct retention slots;
- **proposal:** inside an `HStack`, three children:
  - a stateful proposal leaf under `.padding(…).frame(…).background(…)`,
    clicked three times, which reads 3 with its id three `ModifiedContent`
    levels deep;
  - an unmodified stateful sibling, which reads 0;
  - a stateful proposal `Component`, clicked twice, which reads 2.

**Why "inside an `HStack`".**

- **The typed path is the one at risk.** After lane 3, a proposal container
  reaches its children through the typed requirement. Its defaults for
  `ProposalElement` and for `Component` must bind state and advance the cursor.
  Since design review they do that through the helper `MC-H` names.
- **A test elsewhere would miss it.** With the stateful leaf at the root, or
  under a legacy container, it would reach the untyped entry instead, and a
  typed default that skipped the helper would go unseen.
- **The sibling** is there so that a missing `cursor += 1` (two siblings on one
  id) is visible too.

**What it costs if wrong.**

- **The proofs are open.** The plan lists "No test checks `@State` across
  chained modifiers" as an open proof. The typed-modifier spec's first required
  proof is "two chained modifiers have two structural identities and preserve
  distinct `@State` slots".
- **Without the proposal-container placement**, lane 3 could drop state
  binding for every proposal element in a container. The demo's
  `PreviewToggle` would stop toggling, with the suite green.

**Mutations:** owed by lane 1 (today's code) and lanes 2 and 3 (their code).

---

## MC-E — `OverlayModifier` threads ONE cursor through primary and overlay, as `Pair` does; the collision is measured end to end first, and the fix is one line

**Measured before any change (scratch test through a real `Window`).**
`ZStack { Leaf(60).overlay(alignment: .topLeading) { Leaf(10) } }` in a
100×100 window. Each leaf:

- holds `@State var taps`, and registers its own `onClick` that increments it;
- logs its id in prepaint and its taps in paint;
- fills its bounds when `pass.isHovered(id)`.

The readings:

- **The two ids compared equal** (`equal=true`).
- **Three clicks at (70, 70)**, over the primary only: the primary read **3**,
  and the overlay, never clicked, read **3**.
- **The pointer at (70, 70):** **two** hover fills were painted, 60pt and 10pt
  wide. The overlay drew its hover affordance with the pointer 40pt away.

**With `overlay.requestGroupLayout(under: id, at: &contentCursor, …)` applied:**

- the ids were unequal;
- the primary read 3 and the overlay **0**;
- **one** hover fill was painted, 60pt;
- the whole suite with only that change: **1085 passed** (1084 + the scratch
  test). No existing test depends on the collision.

**The choice.** One cursor: the primary's elements take indices from 0, the
overlay's continue where the primary's stopped. This is `Pair`'s rule and every
legacy container's ("Legacy containers thread one cursor through the whole
group", record §09 hazard 3).

**Alternatives rejected.**

- **A reserved name for the overlay slot** (`.named("$overlay")`).
  - **For:** it would keep the overlay's index independent of the primary's
    shape, avoiding the shift below.
  - **Against:** it would be an eighth reserved name. CLAUDE.md records seven,
    none guarded against a user `.id` that describes to one
    (`theSevenRetentionSlotsAreMutuallyDistinct` covers retention slots only).
  - **Verdict:** not worth a new unguarded collision. Lane 1 test 9 uses this
    alternative as its mutation.
- **An intermediate id per side** (`EitherGroup`'s shape) moves the primary one
  level deeper. That re-seeds the state of every overlaid primary, the demo's
  preview included.

**The index stability cost, restated at design review (`MC-N` finding 11).**
The first draft argued, by reading, that a primary which renders at all always
consumes the same number of indices. **That is false.**

- **The counterexample.** A `Component` whose content is empty consumes one
  index and contributes zero nodes. So a primary block
  `{ if flag { EmptyProposalComponent() }; Rectangle(…) }` has one node either
  way, and satisfies the one-node precondition, but consumes 2 indices or 1.
  When `flag` toggles, the overlay's index moves between 2 and 1. Its state is
  then read from a different entry: fresh, or retained from earlier (divergence
  18).
- **This is not a defect of the fix.** It is the trailing-sibling rule of
  record §01 applied to an overlay, and every legacy container already behaves
  so.
- **Lane 1 test 9 pins it.** Its readings are predicted by reading and replaced
  by the measured ones.
- **Remedy for authors:** the same as record §01's. Keep the primary's
  index-consuming shape fixed, or name the overlay's element.

**SwiftUI, same probe.**

- **Arms E (overlay), F (background) and G (two-view primary)** each give the
  attached view its own state, distinct from the primary's and kept across an
  update.
- **H (two `HStack` siblings)** is the control for "distinct".
- **MetalUI after the fix agrees.**
- **No arm can show shared state**, since SwiftUI never shares it here, so the
  instrument's "same" reading comes from arm A, across time.

**What it costs if wrong.** Before the fix, the demo preview's `PreviewToggle`
and anything overlaid share hover, press dispatch, `@State`, `ScrollState` and
`$anim` between primary and overlay. The preview does not show it only because
its overlay `Rectangle` holds no state and registers no hitbox.

**Mutations:** owed by lane 1.

---

## MC-F — once-per-phase delegation is pinned for EVERY wrapper at once, by a counting leaf whose instrument is first shown able to read 2

**The choice.** One test, one arm per wrapper. Each arm renders one frame with a
counting leaf (legacy or proposal, as the wrapper requires) and expects exactly
one `requestLayout`, one `prepaint`, one `paint`. The arms:

- **legacy:** `.padding`, `.frame`, a three-modifier chain, and a `Component`'s
  distributing `.padding` (`StyledComponent`);
- **proposal `ModifiedContent`,** one arm per distinct code path in its phases:
  - a node-registering case (`frame`);
  - `flexibleFrame`, `padding`, `fixedSize`, `aspectRatio`, `layoutPriority`;
  - the passthrough `background` and `border`;
  - `opacity` (paint closure);
  - `clip` (closures in both phases);
  - `allowsHitTesting(true)` and `(false)` (prepaint closure);
- **`OnTapModifier`;**
- **`OverlayModifier`,** the counting leaf on the primary side and, separately,
  on the overlay side;
- **the builder wrappers** `ProposalFrame`, `Padding`, `Background`, `FixedSize`.

**The control arm:** `Pair(leaf, leaf)` under a `Row` reads 2 in each phase.
Without it, an instrument that counted per type rather than per call would pass
every arm (practices shape 15). Counts are `try #require`d before any per-phase
indexing (shape 13).

**Phase order** is a second, small test. For
`leaf.background(.accent).onClick(inner).padding(4).background(.surface).onClick(outer)`:

- `lastHitboxes` lists the outer layer before the leaf;
- the scene emits the surface rect before the accent rect;
- a click in the padding ring runs `outer`;
- a click inside the leaf runs `inner`.

**Why one test over many.** It is `onClickIsLiveOnEveryConformerThatCanRegisterOne`'s
footing: a new wrapper that forgets a phase is an API that compiles and
misbehaves, and only a per-wrapper list can see it. A wrapper added later
without an arm is a gap a reader can find in one place.

**What it costs if wrong.** Today `ModifiedContent.prepaint`'s
`allowsHitTesting` and `clip` branches call `content.prepaintGroup` inside a
closure and force-unwrap the result (`result!`). A refactor that calls it twice,
or not at all, would double-register or drop every hitbox below. The plan
records "No test checks once-per-phase delegation" as open.

**Mutations:** owed by lane 1 (today's wrappers) and lane 2 (`ModifiedElement`).

---

## MC-G — `SA-R`'s compile-time check is DELIVERED: a typed `ProposalNodeID` with an internal initializer, returned by a new requirement on `ProposalElementGroup`; five lies become compile errors, and six named holes stay, each pinned or cited

**Revised at design review (`MC-N` findings 7 and 8).** Two changes:

- **The hole list was incomplete.** Holes 4 (measured), 5 and 6 (measured) are
  added.
- **Hole 1's guard could not show that it runs.** It gains an in-test
  negative.

**The choice.**

```swift
public struct ProposalNodeID: Hashable, Sendable {
    public let layoutNodeID: LayoutNodeID
    init(_ id: LayoutNodeID)                       // internal
}

public protocol ProposalElementGroup: ElementGroup {
    mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                             at cursor: inout Int,
                                             pass: inout LayoutPass) -> ([ProposalNodeID], GroupLayout)
}

public protocol ProposalElement: Element, ProposalElementGroup {
    associatedtype LayoutState          // restated: required, see below
    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, LayoutState)
}
// defaults: ProposalElement supplies requestLayout (untyped, for Frame's root
// and legacy containers) and requestProposalGroupLayout; Pair, OptionalGroup,
// ArrayGroup and EmptyGroup implement it conditionally; Component supplies it
// `where Content: ProposalElementGroup`. Both typed group defaults enter the
// member's identity through MC-H's helper.
```

Every public `LayoutPass.requestNative*` registrar returns `ProposalNodeID` and
takes `ProposalNodeID` children. Proposal containers and wrappers call
`requestProposalGroupLayout`, never `requestGroupLayout`.

**Measured, skeleton `TypedNodeKit.swift` + clients, plain import, Swift 6**
(re-run at design review under both toolchains, identical):

| client | what it tries | result |
|---|---|---|
| `honest` | a leaf, a container over a `Pair`, a `Component` retro-conformed | exit 0 |
| `liar1` | today's liar: `Element` + marker, legacy node, no typed entry | `type 'Liar' does not conform to protocol 'ProposalElementGroup'` |
| `liar2` | mint a typed id from a legacy node | `'ProposalNodeID' initializer is inaccessible due to 'internal' protection level` |
| `liar3` | a `Component` whose content is legacy, retro-conformed | `type 'LegacyComp' does not conform to protocol 'ProposalElementGroup'` |
| `liar5` | legacy content in a proposal container | `generic struct 'ProposalFrame' requires that 'Legacy' conform to 'ProposalElementGroup'` (true today too) |
| `opaque` | a `Component` with `var content: some ElementGroup`, retro-conformed | `type 'OpaqueComp' does not conform to protocol 'ProposalElementGroup'` |
| `opaqueOK` | the same with `some ProposalElementGroup` | exit 0 |
| `liar4` | a group writing both entry points: legacy nodes from one, zero typed nodes from the other | **exit 0** |
| `opaqueOK`'s `Both` | a `ProposalElement` that also overrides the untyped `requestLayout` | **exit 0** |

`CombinedKit.swift` repeats all nine with lane 2's `LayerBase` added: same
results.

**A finding the design depends on.** Without restating `associatedtype
LayoutState` in `ProposalElement`, the skeleton module itself fails to build:
`error: type 'Leaf' does not conform to protocol 'Element'`. Swift does not
infer `Element.LayoutState` through the default `requestLayout` that
`ProposalElement`'s extension supplies.

**What stays open, precisely.** Six holes. None is closed by an access-control
or type-system check available in this design.

1. **Two entry points can disagree** (`liar4`, `Both`).
   - **Where it can hurt.** The untyped entry is reached only by `Frame`'s root
     and by legacy containers, and a proposal element under a legacy container
     already traps (`SA-G`). A proposal element that lies there is therefore
     harmful only as a root, where it renders as the legacy element it
     registers.
   - A typed entry that returns the wrong *count* still trips the one-node
     wrapper preconditions.
   - **Pinned wrong on purpose** by a guard (spec lane 3, guard 6) that holds a
     positive fixture (the liar compiles) and an in-test negative (the liar
     minus its typed entry does not), and `#require`s that they disagree. So a
     skipped or broken instrument cannot read as the hole being open.
   - **Its post-landing red run:** delete the positive fixture's typed entry.
2. **A side-effect legacy NODE is invisible to the type.** Measured on today's
   code (scratch test): an element whose `requestLayout` calls
   `pass.requestNode(style: Style(), children: [])`, discards the result and
   returns a native leaf. Rendered inside `VStack { HStack { it }; Rectangle }`,
   it did not trap. Its prepaint saw 10×10, and the scene held 1 rect. The
   orphan legacy node is never attached. Pinned wrong on purpose (spec lane 3,
   test 7 arm a).
3. **`unsafeBitCast`**, and `@testable` code calling the internal initializer.
   - **Out of reach of any access-control check.**
   - **The backstop:** the run-time traps from `SA-G`.
   - **The existing liar trap test** is rewritten to mint its id through
     `@testable`, so the trap stays pinned.
4. **One typed id can be used twice. Measured at design review** (scratch
   tests, untyped ids, which a `ProposalNodeID` wraps unchanged). `appendNode`
   checks only the generation (`LayoutTree.swift:146-155`). In
   `VStack { HStack { it } }` at 140×90:
   - **one leaf listed twice** in one horizontal linear stack:
     - no trap;
     - the stack reserves both slots, (60, 0, 20×10);
     - the leaf is placed once, at the **second** slot, (70, 0, 10×10);
     - measure calls: 1; `nodeCount`: 4;
   - **one leaf handed to two frames** (30×30 top-leading, 50×50
     bottom-trailing) in one stack:
     - no trap;
     - the stack is (30, 0, 80×50);
     - the leaf is drawn where the **last** placement puts it, (100, 40, 10×10);
     - the first frame's slot is empty;
     - measure calls: 2; `nodeCount`: 6.

   A type with an internal init constrains who mints an id, not how often it is
   used. Pinned wrong on purpose (spec lane 3, test 8).
5. **A legacy style modifier on a proposal `Component` still compiles.**
   `Toggle().width(Pixels(70))` gives `StyledComponent<Toggle>`, a plain
   `ElementGroup`, so lane 3's requirement never applies to it. Inside a legacy
   container it still traps at `setStyle`. That is `SA-R`'s second run-time
   trap, pinned today by
   `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration`, which stays.
   Owner: task 5 (`Component` distribution).
6. **A side-effect legacy SUBTREE is invisible to the type, and it is not
   inert. Measured at design review** (scratch test). The element's
   `requestLayout` lays out a discarded `Box { StatefulLegacyLeaf() }.background(.accent)`
   through `requestGroupLayout(under: id, at: &c)`; the leaf writes its `@State`
   from 7 to 8 during layout. The element then returns a native leaf. In
   `VStack { HStack { it } }`:
   - no trap;
   - the leaf's `$state0` slot reads **8** and is **live**, so it is bound and
     marked;
   - the orphan `Box`'s `$anim` slot is **live**;
   - **0** rects (nothing of the subtree is painted);
   - `nodeCount` 5 (2 orphan nodes).

   So an orphaned registration keeps state entries alive and animation
   baselines moving for elements that never paint. Pinned wrong on purpose
   (spec lane 3, test 7 arm b).

**Why deliver it here, when `SA-R` feared a second entry point.** `SA-R`
deferred it because a second, typed entry point is "a change to how elements
compose". That is this task. The skeleton shows the second entry point costs
conformers nothing: a proposal element writes only `requestProposalLayout`, and
the untyped `requestLayout` comes from the default.

**What it costs if wrong.**

- **Every proposal element's layout signature changes once.** A grep at
  `f64e58a` counts 35 conformances:
  - 20 in `Sources/MetalUI`: four builder groups and 16 element types, 13 of
    them in `ProposalElementGroup.swift`;
  - 2 in the demo;
  - 10 test helpers;
  - 3 guard fixtures.

  The eleven public registrars and `requestNativeLayout` change with them.
- **An external author who retro-conformed a `Component` with
  `var content: some ElementGroup`** gets a compile error and must write
  `some ProposalElementGroup`. The demo's `PreviewToggle` is one such author.
- **The environment track's `EnvironmentScope` proposal conformance** stops
  compiling at merge. Its typed entry must wrap layout in `withEnvironment`, or
  layout-time reads fall back silently. The spec's merge notes name the
  integration test.
- **If the holes above are later mistaken for closed**, a lying conformer that
  compiles is again a run-time trap, or, for holes 4 and 6, silently wrong
  output. They are named here and pinned so they cannot be.

**Mutations:** owed by lane 3.

---

## MC-H — the identity entry for a group member lives in ONE internal helper that the untyped `Element` default and both typed defaults call; `Element.swift` and `Component.swift` are not edited; the registrars change IN PLACE rather than gaining typed twins

**Revised at design review (`MC-N` finding 2).** The first draft copied
`GlobalElementID.child`, `StateBinder.bind` and `cursor += 1` into the two typed
defaults, leaving `ElementGroup.swift` untouched. The environment track changes
`StateBinder.bind`'s signature at "the five call sites" it knows. Two copies it
does not know about would make seven — the "second thing to go missing from
the copy" hazard, arriving on the first parallel track.

**The choice.**

- **`Sources/MetalUI/GroupMember.swift` (new, internal)** holds one helper:
  `GlobalElementID.enteringGroupMember(_:name:under:at:pass:)`. It does
  `child(of:at:name:)`, then `StateBinder.bind`, then `cursor += 1`, and returns
  the id. Its doc names every caller and the one remaining copy.
- **`ElementGroup.swift`, one localized edit.** In `Element`'s default
  `requestGroupLayout`, the three lines become one call to the helper. The
  `prepaintGroup`/`paintGroup` re-binds are a different job (re-pointing a
  shared box), and they stay where they are.
- **`Sources/MetalUI/ProposalNodeID.swift` (new)** holds `ProposalNodeID`,
  `ProposalElement` and its two defaults, and the
  `extension Component where Content: ProposalElementGroup` default. Both typed
  defaults call the helper.
- **`Component.swift` is not edited.**
  - **Its untyped default keeps its own three lines**, the one copy left. It
    is interleaved with a page of mutation history that names those exact
    lines.
  - **Its bind and its `cursor += 1`** are already pinned by
    `aComponentsOwnStateSurvivesAcrossFrames` and
    `twoSiblingComponentsHoldIndependentState`.
  - **The helper's doc says so**, so a reader changing the helper finds the
    copy.
- **`ProposalElementGroup.swift`** gains the requirement, and the builder
  groups' conditional implementations beside their existing conditional
  conformances.
- **`Passes.swift`** changes only the registrar block's parameter and return
  types (lines 55–150 at `f64e58a`). `Frame`'s internal registrars stay
  untyped.

**Why a helper, at the cost of a shared-file edit.**

- **The copy is the known hazard.** `AnyElement`'s default already lost its
  bind and then its cursor advance, each unguarded until found.
- **A signature change would be loud; other changes would not.** A copy
  survives a change that alters behaviour without altering the signature, and
  that is exactly how `AnyElement`'s went missing.
- **The helper keeps the bind call sites at five.** The environment track then
  edits those five and no more. The conflict at `ElementGroup.swift:112` is
  textual, and the helper's stale bind is a compile error, so neither half of
  the merge is silent.
- **The shared-file edit is three lines to one**, inside one function body.

**Why the registrars change in place, not as typed twins.** Three tracks run in
parallel and merge afterwards, and `Passes.swift` is a named shared file.

- **Twins would be additive**, keeping the untyped registrars.
- **They would also leave inert public API:** eleven public untyped native
  registrars with no caller in `Sources/`, minting native nodes that no
  proposal element can use. That is a declared-but-inert row by construction.
- **Changing the types in place** is a localized edit to one block.

**What it costs if wrong.**

- **The helper becomes a single point** that both engines' state binding runs
  through. A mistake in it breaks legacy and proposal `@State` together. That
  is loud, and it is the reason for the helper.
- **`Component.swift`'s copy can still drift from the helper.** It is bounded
  by the two existing Component tests, and named in the helper's doc.
- **The helper is bounded by four mutations**, each of which must redden a
  named test, all carried by `MC-D`'s proposal test (and, for the first, the
  legacy `@State` tests):
  1. delete the helper's bind;
  2. `ProposalElement`'s typed default bypasses the helper;
  3. `Component`'s typed default bypasses the helper;
  4. delete the helper's `cursor += 1`.

**Mutations:** owed by lane 3.

---

## MC-I — `ModifiedElement` is a registering site in both phases and gets an arm in all six per-site guards, each arm exercising an INNER layer as well as the outermost; every per-site list that named `FrameModifier` changes its arm, never deletes it

**The choice.** Arms for a two-layer chain are added in place to:

- `everyRegisteringSiteAnimatesItsStyle` and
  `everyBackgroundPaintingSiteAnimatesItsColour` (`AnimationTests.swift`);
- `everyBackgroundPaintingSiteHonoursHoverAndFocus` and
  `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`
  (`BackgroundChainTests.swift`);
- `onClickIsLiveOnEveryConformerThatCanRegisterOne` (`InputDispatchTests.swift`);
- `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`
  (`AXEmitSiteTests.swift`).

**Added at design review (`MC-N` finding 3): the other tracks' lists.** Two
parallel tracks name `FrameModifier` as a site:

- the environment track's D2
  (`everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`, arm "frame");
- the AX-bridge spec's scope boundaries (an in-scope emit site, "untouched").

The rule for integration: **each such arm becomes a `ModifiedElement` arm over
a two-layer chain, asserting on the inner layer too, and is never deleted.** A
deleted arm would silently drop the only per-site coverage the list had for
`.frame`.

**Why the inner layer.** The likeliest wrong implementation of a flat chain
wires the outermost layer — the one `StyledElement`'s accessors reach — and
forgets the loop. An arm on a one-layer chain would pass it.

**Why in place, in shared-ish files.**

- **The guards' value is one list.** CLAUDE.md's Animation section: "A site
  that skips its helper is silently unanimated with no diagnostic; the two
  per-site guards are …".
- **The debt transfers.** Record §09 already lists `FrameModifier` arms in five
  of these guards as owed, and `FrameModifier` is replaced by this type.
- **The conflict cost is textual.** Each arm is one additive block, so a merge
  conflict is textual at worst. The spec's merge notes name the two files that
  other tracks also extend.

**What it costs if wrong.** Without the arms, `ModifiedElement`'s `animated`,
`animatedBackground` and `registerHandlers` calls could each be deleted with the
suite green, the demo sidebar's width animation among them (it lives on a
padding wrapper). Record §09 says so of `FrameModifier` today, by reading.

**Mutations:** owed by lane 2.

---

## MC-J — the demo: the default window must not change pixel-for-pixel apart from desktop corners, compared against a build of `f64e58a` itself; lane 3 edits two preview declarations; no look is claimed for the preview

**Revised at design review (`MC-N` finding 12).** The first draft took the
baseline "at the lane's start commit" and argued, by reading, that it equals
`f64e58a`'s. The baseline is now built from `f64e58a` directly.

**The choice.**

- **The baseline build.** `git archive f64e58a | tar -x -C <scratchpad>/mc-base`,
  then `swift build -c release` in that directory.
  - It is a plain directory, not a worktree, so no other checkout is touched.
  - The archive keeps the shader-header symlink.
  - Lanes 2 and 3 compare against this one build.
- **The capture method** is record §03's of 2026-09-14, used for both the
  baseline and each lane's release build of this worktree:
  - launch `MetalUIDemo`, and wait for the first frame;
  - find the window through `CGWindowListCopyWindowInfo`'s bounds;
  - `screencapture -x -R<x,y,w,h>`;
  - **no input sent, pointer not moved**, and the pointer position logged
    first, since a pointer over a list row changes its hover colour;
  - compare every pixel.

  Record §03's accepted difference: a few dozen pixels at x ≤ 8, y ≤ 46 (the
  desktop behind the rounded corner).
- **Lane 2** captures the default window.
- **Lane 3** repeats the default-window capture, since it rebuilds every
  proposal type the preview uses. It also captures the preview window
  (`METALUI_NATIVE_LAYOUT_PREVIEW=1`) from the same two builds.
- **Lane 3 edits the demo's preview** as `MC-G` forces:
  - `PreviewToggle.content` becomes `some ProposalElementGroup`;
  - `PriorityPreviewPanel` conforms to `ProposalElement`, with a typed
    `requestProposalLayout`.

  That is a regression check, not the human look that record §09 says the
  preview has never had.

**What it costs if wrong.** The 2026-09-14 `.padding` change regressed the
default demo, and it went unseen until a capture (record §03). A representation
change to the same wrapper is exactly that risk again.

**Mutations:** not applicable. The capture is the check; its two PNG sizes and
the differing-pixel count go in record §10.

---

## MC-K — the outermost layer is stored inline and the rest in an array, so a single-layer chain allocates nothing a `Box` did not in the model's debug build; multi-layer chains cost array buffers that nested boxes did not, measured in a model and re-measured by lane 2 at 1, 2 and 3 layers

**Revised at design review (`MC-N` finding 4).** The first draft measured only
one-layer chains, the one case that does not allocate. Task 4 makes 2- and
3-layer chains the ordinary shape.

**The choice.**

- **Storage.** `ModifiedElement` stores `outermost: ModifierLayer` and
  `inner: [ModifierLayer]`.
- **Layout.** Its `Layout` stores the outermost node inline, and the inner
  layers' nodes in an array.
- **The one-layer case.** An empty array owns no buffer, so a one-layer chain
  has no array cost.

**Measured, model `LayerAllocationModel.swift`** (not the real module). Counts
are per chain, per frame build, averaged over 500, with the counter calibrated
first:

| layers | swift.org 6.3.3 `-Onone`: nested `Box` | flat | flat − nested | `-O`: nested | flat |
|---|---|---|---|---|---|
| 1 | 2 | 2 | **+0** | 0 | 1 |
| 2 | 3 | 6 | **+3** | 0 | 3 |
| 3 | 4 | 9 | **+5** | 0 | 4 |

- **Construction alone costs k−1 buffers** for k layers.
- **`consuming func _wrap` does not remove them.** It was measured, with
  identical numbers. The buffers are the array's growth on append, since an
  empty array has no buffer; they are not copy-on-write of a shared buffer.
- **The rest** is the `Layout`'s inner-node array, plus the per-layer loops.
- **The swiftlang 6.4 toolchain at `-Onone`** adds its known floor:
  calibration 16 → 32, and nested 3/4/5.
- **At `-O`**, even the one-layer case costs one allocation, where the nested
  version's arrays are optimised away. So the first draft's "a single-modifier
  chain allocates nothing a `Box` did not" holds in the model's debug build
  only.

**Owed by lane 2, in the real test build** (spec, lane 2):

- **Count** 500 chains of 1, 2 and 3 layers against hand-built
  `Box<Leaf>`, `Box<Box<Leaf>>` and `Box<Box<Box<Leaf>>>`.
- **Record** all six numbers here.
- **Keep a bounded test only if each arm reddens under its named mutation:**
  - one-layer arm: "one array for all layers";
  - two- and three-layer arms: "one extra array per inner layer".
- **Otherwise**, record the numbers and keep no test. A test that cannot fail
  is the disease this repo's practices doc names.

**Why not inline storage for more layers now.** A fixed inline capacity (say,
three layers before spilling to an array) removes the construction buffers.
But it adds a second storage path, whose own bugs are the kind `MC-B`'s oracle
exists to catch.

- **The measured cost is a few allocations per multi-layer chain per frame.**
- **The demo's padded list rows are one-layer chains** (`main.swift:857`, one
  `.padding(Edges(…))` per row, by reading), so the 500-row list is the +0
  case.
- **Deferred to task 4**, which creates the multi-layer chains, with these
  numbers as its baseline.

**What it costs if wrong.**

- **Per frame build, per multi-layer chain:** about +3 allocations at 2 layers
  and +5 at 3 layers over nested boxes, in the model's debug build; +3 and +4
  in its release build. That is on every chain rebuilt by a content closure.
- **Behaviour** does not change.
- **A task-4 screen of N elements**, each with a 3-layer sizing chain, pays on
  the order of 5N allocations per frame that the nested representation did not.
  **That is the number task 4 must re-measure** before converting
  `width`/`height`.

**Mutations:** owed by lane 2.

---

## MC-L — deferred, and to whom

Not in this track. Each item is named so a green run of this track is not read
as covering it.

| item | why not here | owner |
|---|---|---|
| `width`/`height`/min/max as layers; legacy `.frame` min/ideal/max/alignment | the plan forbids it here | task 4 |
| inline layer storage for multi-layer chains (`MC-K`) | a second storage path; the multi-layer chains arrive with task 4 | task 4 |
| `Component` modifier distribution (`StyledComponent`), and caller modifiers snapping (B-7) | the plan forbids it here | task 5 |
| `MC-G` hole 5 (a legacy style modifier on a proposal `Component` compiles, traps) | distribution's | task 5 |
| paint-only legacy layers (`background`, `cornerRadius`, …) and the wrap/distribute/paint matrix | task 5's matrix | task 5 |
| unifying `ModifiedElement` with proposal `ModifiedContent` | two engines until task 7 | task 7 |
| a public, user-definable modifier protocol; the `_wrap` hole (`MC-A`) | `MC-A` | task 7 or later |
| `EitherGroup: ProposalElementGroup` (record §09 boundary 4) | not composition of modifiers | tasks 6/8 |
| one-node wrapper traps on 0 or 2+ nodes (boundary 2) | a typed id fixes the kind, not the count | task 6 |
| `MC-G` holes 1–4 and 6 | hole 3: no mechanism within public Swift; holes 1, 2 and 6 need the legacy root switch gone; hole 4 needs a duplicate-parent check in the kernel | task 7 (hole 4: task 6) |
| proposal `.id()`, focus, AX | interaction | task 12 |
| animation on proposal wrappers, and wrappers joining transactions | | task 13 |
| divergence 19 (one value placed twice) and `@State` inside `AnyElement` | not modifier composition | task 8 |
| a separate test that two `ProposalScrollView`s in an overlay keep separate `ScrollState` | closed by `MC-E`'s mechanism, not separately pinned | task 6 |
| deprecating `nativeFrame(…)` | breaks the 0-warning baseline (record §09) | integration step |
| `aProposalContainerReadsTheEnvironmentDuringLayout` (spec merge notes) | the environment API does not exist on this branch | integration step |
| CLAUDE.md / AGENTS.md / plan / record README updates: guard count, "registering points", `FrameModifier` mentions, the candidate divergence (`MC-C`), the holes | owned by the integration step | integration |

**The superseded typed-modifier spec's required proofs**, and where each now
lives. **Added at design review (`MC-N` finding 10):** the first draft dropped
two.

| 2026-09-12 spec's required proof | owner here |
|---|---|
| two chained modifiers have two structural identities and preserve distinct `@State` slots | `MC-D`, lane 1 tests 5–6 |
| once-per-phase delegation | `MC-F`, lane 1 tests 7–8 |
| explicit `AnyElement` remains opt-in; no ordinary modifier path introduces it | lane 2 test 1 (no type name contains `AnyElement`; exact `ModifiedElement<…>` names) |
| frame ordering changes the measured/placed result where SwiftUI does | lane 1 test 10, against `swiftui-modifier-order.swift` (seven arms, measured equal on today's code; stays green through lane 2) |

---

## MC-M — method: what was measured, and what was only read

- **Measured:**
  - every table row in `MC-A` (timing, inference, reachability), `MC-C`'s
    SwiftUI arms, `MC-E`, `MC-G` (skeletons and holes 2, 4 and 6), and
    `MC-K`'s model;
  - lane 1 test 10's numbers, on SwiftUI and on today's MetalUI.

  The runs are listed under "Where each number was measured".
- **By reading, not run:**
  - that `FrameModifier`'s phases equal `Box`'s. That is `MC-B`'s premise, and
    lane 1's oracle test is its measurement;
  - that lane 1's counting arms cover every distinct code path in
    `ModifiedContent`'s phases. Lane 1 enumerates them against the source;
  - the 35-conformance count (grep);
  - that no stored type in `Sources/` spells a `.padding`/`.frame` chain
    (grep);
  - `MC-C`'s adoption prediction (8 / 10 / 12). Lane 2 test 5 measures it;
  - lane 1 test 9's predicted readings;
  - that `Component.swift`'s untyped default is pinned by the two tests `MC-H`
    names (from their doc comments' recorded mutations).
- **The scratch tests were deleted, not committed.** Their shapes are
  reproduced as:
  - lane 1's first three tests, which must be red on their first run;
  - lane 1's test 10, green as measured;
  - lane 3's tests 7 and 8, green as measured.
- **Instrument checks:**
  - **The SwiftUI probes' controls are their positive controls:** identity
    probe A and B; order probe K0–K2, whose outer sizes and origins differ.
  - **The skeletons' negative clients** each printed the specific diagnostic,
    not just a non-zero exit (practices shape 16's "print the real diagnostic
    before trusting it").
  - **The allocation model** was calibrated against 16 known buffers in every
    run, and read 16 (or 32 under the swiftlang floor).
  - **The timing probe** printed the inferred types for all three variants
    before its timings were read, so the three designs were shown to differ
    only in overload shape.

**Mutations:** not applicable.

---

## MC-N — design review, 2026-09-15: each finding and what was done with it

Twelve findings from the critic's review of `1c6f686`. Every one was applied;
none was rejected. Where a finding offered alternatives, the one taken is named
with its reason.

| # | finding | disposition |
|---|---|---|
| 1 | `MC-A`'s overloads make type-checking time exponential in chain length; replace them before lane 2, or prove the cost on the real module | **Applied, by replacement.** The reviewer's numbers were re-taken with a generator carrying the real module's competing overloads (`chain-typecheck-timing.py`); the exponential was confirmed under two toolchains. `MC-A` now uses the reviewer's measured alternative, one overload through `ElementGroup.LayerBase`, checked two-module (`LayerBaseKit.swift`) and together with lane 3 (`CombinedKit.swift`). The real-module check is kept as a recorded lane-2 measurement. Lane 2 test 6 (a 24-modifier chain) turns a regression into a build failure. The new `_wrap` hole is recorded in `MC-A`. |
| 2 | Lane 3 breaks the environment track at merge: `EnvironmentScope`'s proposal conformance, and two unknown `StateBinder.bind` copies | **Applied.** Both collisions are in the spec's merge notes and record §10. The copied defaults were **replaced by one helper** (`MC-H`), the reviewer's second option, at the cost of a three-line edit to `ElementGroup.swift`. The layout-time environment test cannot be written on this branch, since the API does not exist; its exact shape and mutation are specified for integration (`MC-L`). |
| 3 | Deleting `FrameModifier` conflicts with both other tracks | **Applied.** The environment track's D2 arm, the AX-bridge spec's scope-boundary entry and "untouched" line, and the shared arm lists are named in the spec's merge notes. The change-not-delete rule is in `MC-I`. |
| 4 | `MC-K` measures only the case that does not allocate | **Applied, and measured now.** A model counts 1, 2 and 3 layers against nested boxes (+0/+3/+5 debug). A `consuming` variant shows the buffers are growth, not copies. Lane 2 re-measures in the real build. The cost is named in `MC-K`, and inline storage is deferred to task 4 with these numbers. |
| 5 | `MC-C`'s "both directions agree with SwiftUI" overreaches; layer adoption is unnamed | **Applied.** Reworded: only the wrapped element's reset is claimed as parity, and even that is argued for the flat case, not measured. The adoption is named and pinned (lane 2 test 5), and proposed as a candidate divergence for integration. The reviewer's re-run of the probe matched its header; not re-run again. |
| 6 | `MC-B`'s disagreeing oracle covers rects only | **Applied.** One disagreeing oracle per observation (id moved, `onClick` dropped, a layer fewer), each `#require`d. |
| 7 | Guard 6 cannot show that it runs | **Applied.** An in-test negative fixture (the liar minus its typed entry), `#require`d to disagree, and a post-landing red run owed by lane 3. |
| 8 | `MC-G`'s holes are incomplete | **Applied, and measured now.** Duplicate id in one container, and one id in two containers, by scratch tests (hole 4). The orphan legacy subtree binds and marks state and `$anim`, and paints nothing, by scratch test (hole 6). The proposal-`Component` style modifier is hole 5, pinned by the existing exit test. Holes 4 and 6 are pinned by lane 3 tests 7–8. |
| 9 | `CounterPanel` evidence is misattributed | **Applied.** `MC-A` now says no stored type in `Sources/` spells a chain, and gives task 4 as the pressure. |
| 10 | Two proofs from the superseded spec are unassigned | **Applied.** `AnyElement` opt-in goes to lane 2 test 1. Frame ordering goes to lane 1 test 10, backed by a new SwiftUI probe (`swiftui-modifier-order.swift`) and a scratch measurement showing today's MetalUI already matches on all seven arms. `MC-L` has a table mapping each superseded proof to its owner. |
| 11 | `MC-E`'s index-stability argument has a counterexample | **Applied.** The claim is withdrawn, and the counterexample is pinned as lane 1 test 9 (`EmptyProposalComponent` in an optional primary). |
| 12 | Minor inconsistencies | **Applied.** The hover fill is `.textPrimary`, which no chain uses. Lane 3's helper conversions in `ModifierCompositionProofTests.swift` count 2. The demo baseline is built from `git archive f64e58a` (`MC-J`). |

**What the review did not change:**

- the flat representation itself;
- lane order;
- `MC-D` and `MC-F`'s substance;
- `MC-G`'s delivery of the compile-time check.

**Mutations:** not applicable.
