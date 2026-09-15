# Modifier composition — decisions for plan task 3

These are the rulings for plan task 3, "Build a typed modifier-composition
foundation" (`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`). They are
written at design time, on `feat/modifier-composition` at `f64e58a`, before any
lane runs.

Prefixed **`MC-`** and **lettered** (`MC-A`, `MC-B`, …), per this repo's
convention. **A bare `MC-3` is a typo, not a citation.** The next unused letter
is **`MC-N`**.

Read alongside:

- `docs/superpowers/specs/2026-09-15-modifier-composition-design.md`, which
  holds the three lanes, their API, files, tests and mutations;
- `docs/record/10-modifier-composition.md`, this track's record;
- `docs/probes/swiftui-modifier-identity.swift` (the SwiftUI probe, output in
  its header) and `docs/probes/modifier-composition-skeletons/` (two typecheck
  skeletons, output in their headers);
- `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`, whose `SA-R`
  hands this task its compile-time open proof. That doc is not edited here.

## How to read the letters

- **`MC-A`…`MC-C`** — the legacy wrapper representation and its identity
  rules. Lane 2 implements them; lane 1 writes the oracle they must match.
- **`MC-D`…`MC-F`** — the open proofs on today's code: `@State` across chained
  modifiers, the overlay identity collision, once-per-phase delegation. Lane 1.
- **`MC-G`, `MC-H`** — `SA-R`'s compile-time check: the typed native node id.
  Lane 3.
- **`MC-I`…`MC-K`** — what the representation owes the rest of the framework:
  per-site guard arms, the demo, allocation. Lanes 2 and 3.
- **`MC-L`** — deferred, with owners. **`MC-M`** — method: what was measured in
  this session, where, and what was only read.

**Every ruling ends with a "Mutations" line reading _owed by lane N_.** The lane
that implements a ruling replaces it with the mutations it ran and the tests
each one reddened. A ruling whose line still says "owed" has not been
mutation-tested and must not be cited as proven.

## Where each number was measured

All in the worktree `/Users/maxburger/Developer/MetalUI-modifier-composition`
at `f64e58a`, 2026-09-14/15, one agent live in it:

- **The SwiftUI probe**, both forms (`/usr/bin/swift`, Apple Swift 6.4; and
  compiled with `swiftc`, Apple Swift 6.3.3), byte-identical stdout, exit 0.
- **The overlay collision, end to end**, by an uncommitted scratch test
  (`scratchMeasureOverlayIdentity`, run with `--filter`, since deleted): through
  a real `Window` and `FakePlatformWindow`.
- **The one-cursor overlay fix**, applied temporarily, the same scratch test
  re-run, then the **whole suite**: `Test run with 1085 tests in 1 suite passed`
  (1084 committed + the scratch test), no `error:`, no `warning:`. The source
  was restored from a `cp` backup and `git status --short` showed only the new
  untracked files.
- **The orphan-legacy-node run** (`scratchMeasureOrphanLegacyNode`, same
  scratch file, since deleted).
- **Two typecheck skeletons**, `xcrun swiftc` Apple Swift 6.3.3, Swift 6 mode,
  re-run from their committed location under `docs/probes/`.

**Carried, not re-taken:** the suite count 1084, 45 guards and 97 goldens at
`553b980` (plan task 2's entry). `f64e58a` differs from `553b980` in docs only.

---

# The decisions

## MC-A — legacy modifier wrappers become ONE flat type, `ModifiedElement<Content>`: one layer per modifier, one node and one identity level per layer, and a type that does not grow along a chain

**The choice.**

```swift
public struct ModifiedElement<Content: ElementGroup>: Element, StyledElement {
    public var content: Content
    // internal: the outermost layer inline, the rest in an array (MC-K)
}
```

- **A layer** is internal: a `Style`, a `Decoration`, `Handlers` and an
  `ElementID?` — exactly what one `Box` around one child carries.
  `.padding(_:)` makes a layer whose `style.padding` holds the edges;
  `.frame(width:height:)` makes one centred on both axes with the given sizes,
  which is `FrameModifier.init` today.
- **`StyledElement.padding(_:)` (both overloads) and `ElementGroup.frame(width:height:)`**
  return `ModifiedElement<Self>`. **`ModifiedElement` redeclares the same three
  methods concretely, returning `ModifiedElement<Content>`**: they append a
  layer instead of wrapping, so a chain keeps one type.
- **`ModifiedElement`'s `style`, `decoration`, `handlers` and `elementID` read
  and write the outermost layer.** So every `Self`-returning `StyledElement`
  modifier written after a wrapper configures that wrapper, as it configures
  today's `Box<Self>`.
- **`FrameModifier` is deleted**, with its public `init(content:width:height:)`.
  No typealias is kept: `FrameModifier<FrameModifier<T>>` would name a
  nested type that the flat chain never produces.
- **The proposal path keeps `ModifiedContent`** (a closed enum over proposal
  content). Unifying the two is plan task 7's, after the legacy engine goes.

**Why flat, when SwiftUI nests.** Probe arm T: SwiftUI's
`Color.red.padding(4).padding(8)` is
`ModifiedContent<ModifiedContent<Color, _PaddingLayout>, _PaddingLayout>`.
MetalUI diverges **in type shape only** and on purpose. The plan's task-3 text
asks for a representation that "can nest without forcing callers to expose
ever-growing concrete types such as `Box<Box<Box<Text>>>`", because MetalUI
code stores concrete subtrees: the demo's `CounterPanel` stores
`Box<Pair<Pair<Box<Text>, Box<Text>>, Box<Text>>>`, and the task-4 conversion
of `width`/`height` would otherwise grow every chained sizing call by one
level. A flat type grows once, at the first wrapper, and never again. Every
observable of the nested shape — identity, nodes, rects, hitbox and paint
order, animation slots — is kept (`MC-B`).

**Measured, skeleton `FlatChainOverloads.swift`.** Without a contextual type,
`Text().padding(4).frame(width: 10).padding(8).width(3).padding(1)` infers
`ModifiedElement<Text>`, a `Component`'s `.frame(width:).padding(_:)` infers
`ModifiedElement<Two>`, and `Row(Text().padding(1).padding(2))` infers
`Row<ModifiedElement<Text>>`. Exit 0.

**Why not a modifier protocol (`ElementModifier`) now.** The 2026-09-12 typed
modifier spec proposed one. No caller needs a user-defined legacy modifier, the
legacy engine is scheduled for deletion (task 7), and a protocol whose
requirements must reach `LayoutPass` would re-open the `LayoutNodeID` exposure
`LayoutModifier`'s doc comment rules out. The layer stays internal, so tasks 4
and 5 can add layer kinds (a paint-only layer, a proposal frame) without a
public break.

**What it costs if wrong.**

- **Source breaks, all compile errors, none silent:** `FrameModifier` spelled
  by name (one test file: `ComponentTests.swift`); `Box<Self>` spelled as the
  result of `.padding` (no caller in `Sources/` or `Tests/`, by grep); and
  `Box`-only API after `.padding`, i.e. `.flexDirection` (no caller, by grep).
- **SwiftUI type-shape parity is lost.** An author porting a stored
  `ModifiedContent<ModifiedContent<…>>` spelling cannot write the MetalUI one
  the same way. Nothing in MetalUI spells a legacy chain type today except the
  test above.
- **A chain's length can now vary at run time without a type change.**
  `MC-C` rules what that does, and pins it against SwiftUI.

**Mutations:** owed by lane 2.

---

## MC-B — the flat chain, a nested `ModifiedElement<ModifiedElement<…>>`, and hand-built nested `Box`es must be OBSERVATIONALLY IDENTICAL; the hand-built boxes are the oracle, and lane 1 writes it before the type exists

**The choice.** For the same modifiers in the same order, these three trees
produce the same observations:

1. the flat chain (`X.padding(4).frame(width: 60, height: 40).padding(8)`);
2. the nested form, reachable from generic code
   (`func wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T> { t.padding(8) }`
   applied to a one-layer chain);
3. hand-built `Box(style:decoration:content:)` values, one per modifier, with
   the layer's style, and the layer's own `Self`-returning modifiers applied to
   that `Box`.

**The observations compared:** the wrapped element's `GlobalElementID` and
bounds; each layer's hitbox (id, bounds, registration order); the scene's rects
in emission order, with bounds and colour; `Frame.tree.nodeCount`; and, for each
layer id, `StateTable.isLive(animRetentionSlot(for:))`.

**Why the nested form must be covered.** Measured in the skeleton: with a
contextual type, `let a: ModifiedElement<ModifiedElement<Text>> =
Text().padding(4).padding(8)` also typechecks. The protocol-extension overload is
viable, and the type context picks it. A generic function over
`T: StyledElement` always takes the protocol overload. Both shapes are
therefore reachable from ordinary code, and a difference between them would be a
behaviour that depends on how a caller happened to spell a type.

**Why the oracle is hand-built boxes, and why lane 1 writes it.** Today's
`.padding` *is* a `Box` and today's `.frame` is a `Box`-equivalent
(`FrameModifier`'s three phases are line for line `Box`'s). A test comparing
today's chain with hand-built boxes is green on arrival; lane 2 then replaces
the chain's representation, and **the same test staying green is the migration
proof** that identity, `@State`, handlers and phase order were preserved. The
oracle side never runs `ModifiedElement` code, so it cannot move with a
mutation of it (practices shape 12). The test must also `#require` that a
**disagreeing** oracle — the same boxes with padding 4 and 8 swapped — gives
different rects (shape 15).

**What it costs if wrong.** Without it, lane 2 could ship a representation whose
inner layers share the outer layer's id (one `$anim` slot, one hitbox id, and
a wrapped element re-seeded one level up), and every existing padding and frame
test, all of which assert rects and node counts, would stay green.

**Mutations:** owed by lanes 1 and 2.

---

## MC-C — identity: the outermost layer takes the parent's cursor slot, each inner layer is `positional(0)` (or its name) under the next one out, the content numbers from 0 under the innermost layer; a run-time change of layer COUNT resets the wrapped element's state, a change of layer VALUES does not

**The choice.**

- For a chain of n layers, `L[n-1]` (outermost) gets
  `GlobalElementID.child(of: parent, at: cursor, name: L[n-1].elementID)`;
  `L[k]` gets `.child(of: id(L[k+1]), at: 0, name: L[k].elementID)`; the content
  group is laid out `under: id(L[0])` with a fresh cursor at 0. **This is
  exactly the path `Box<Box<…>>` produces today**, so no state entry, focus
  slot or `$anim` baseline moves when `.padding` and `.frame` change type.
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

D3 is the discriminating arm: the reset follows the structure, not the
`if`/`else`. A flat `ModifiedElement` whose layer count changes at run time
(`var c = X().padding(4); if flag { c = c.padding(8) }`, one type) moves its
content one level deeper, so it resets like D1/D3; a value change keeps state
like C/D2. **Both directions agree with SwiftUI.**

**What it costs if wrong.** If a later change keys a layer's id on its values
(for instance, to let a frame change "look like" a new view), an animated
`.padding(open ? 16 : 8)` would reset its content's `@State` on every toggle,
with no diagnostic. If it keys content identity on the outermost layer only,
adding a layer at run time would silently keep state SwiftUI resets. Both are
pinned (spec, lane 2 tests 3 and 4).

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

**Why "inside an `HStack`".** After lane 3, a proposal container reaches its
children through the typed requirement. Its defaults for `ProposalElement` and
for `Component` must repeat the untyped defaults' `StateBinder.bind` and
`cursor += 1` (`MC-H`). A test
whose stateful leaf were the root, or under a legacy container, would reach
`Element`'s untouched default instead and could not see a missing bind on the
typed path. The sibling is there so that a missing `cursor += 1` (two siblings
on one id) is visible too.

**What it costs if wrong.** The plan lists "No test checks `@State` across
chained modifiers" as an open proof, and the typed-modifier spec's first
required proof is "two chained modifiers have two structural identities and
preserve distinct `@State` slots". Without the proposal-container placement,
lane 3 could drop state binding for every proposal element in a container, and
the demo's `PreviewToggle` would stop toggling, with the suite green.

**Mutations:** owed by lane 1 (today's code) and lanes 2 and 3 (their code).

---

## MC-E — `OverlayModifier` threads ONE cursor through primary and overlay, as `Pair` does; the collision is measured end to end first, and the fix is one line

**Measured before any change (scratch test through a real `Window`).**
`ZStack { Leaf(60).overlay(alignment: .topLeading) { Leaf(10) } }` in a
100×100 window. Each leaf holds `@State var taps`, registers its own `onClick`
that increments it, logs its id in prepaint and its taps in paint, and fills its
bounds when `pass.isHovered(id)`.

- **The two ids compared equal** (`equal=true`).
- **Three clicks at (70, 70)**, over the primary only: the primary read **3**,
  and the overlay, never clicked, read **3**.
- **The pointer at (70, 70):** **two** hover fills were painted, 60pt and 10pt
  wide. The overlay drew its hover affordance with the pointer 40pt away.

**With `overlay.requestGroupLayout(under: id, at: &contentCursor, …)` applied:**
ids unequal; primary 3, overlay **0**; **one** hover fill, 60pt. The whole
suite with only that change: **1085 passed** (1084 + the scratch test). No
existing test depends on the collision.

**The choice.** One cursor: the primary's elements take indices from 0, the
overlay's continue where the primary's stopped. This is `Pair`'s rule and every
legacy container's ("Legacy containers thread one cursor through the whole
group", record §09 hazard 3).

**Alternatives rejected.**

- **A reserved name for the overlay slot** (`.named("$overlay")`) would keep
  the overlay's index independent of the primary's shape. It would also be an
  eighth reserved name, and CLAUDE.md records seven, none guarded against a
  user `.id` that describes to one (`theSevenRetentionSlotsAreMutuallyDistinct`
  covers retention slots only). Not worth a new unguarded collision.
- **An intermediate id per side** (`EitherGroup`'s shape) moves the primary one
  level deeper, and so re-seeds the state of every overlaid primary, the
  demo's preview included.

**Why the index stability cost is small.** The overlay's indices now depend on
how many the primary consumed. That number is fixed by the primary's type,
except for an `OptionalGroup` or `ArrayGroup` whose member count varies. Such a
primary yields 0 or 2+ nodes whenever its count is not 1, and the one-node
precondition traps (`NativeOverlayModifier.swift:34`). So a primary that
renders at all has consumed the same number of indices on every frame, by
reading.

**SwiftUI, same probe:** arms E (overlay), F (background) and G (two-view
primary) each give the attached view its own state, distinct from the primary's
and kept across an update. H (two `HStack` siblings) is the control for
"distinct". MetalUI after the fix agrees. **No arm can show shared state** —
SwiftUI never shares it here — so the instrument's "same" reading comes from arm
A, across time.

**What it costs if wrong.** Before the fix, the demo preview's `PreviewToggle`
and anything overlaid share hover, press dispatch, `@State`, `ScrollState` and
`$anim` between primary and overlay. The preview does not show it only because
its overlay `Rectangle` holds no state and registers no hitbox.

**Mutations:** owed by lane 1.

---

## MC-F — once-per-phase delegation is pinned for EVERY wrapper at once, by a counting leaf whose instrument is first shown able to read 2

**The choice.** One test, one arm per wrapper, each rendering one frame with a
counting leaf (legacy or proposal, as the wrapper requires) and expecting
exactly one `requestLayout`, one `prepaint`, one `paint`. The arms:

- **legacy:** `.padding`, `.frame`, a three-modifier chain, and a `Component`'s
  distributing `.padding` (`StyledComponent`);
- **proposal `ModifiedContent`,** one arm per distinct code path in its phases:
  a node-registering case (`frame`), `flexibleFrame`, `padding`, `fixedSize`,
  `aspectRatio`, `layoutPriority`, the passthrough `background`, `border`,
  `opacity` (paint closure), `clip` (closures in both phases),
  `allowsHitTesting(true)` and `(false)` (prepaint closure);
- **`OnTapModifier`;**
- **`OverlayModifier`,** the counting leaf on the primary side and, separately,
  on the overlay side;
- **the builder wrappers** `ProposalFrame`, `Padding`, `Background`, `FixedSize`.

**The control arm:** `Pair(leaf, leaf)` under a `Row` reads 2 in each phase.
Without it, an instrument that counted per type rather than per call would pass
every arm (practices shape 15). Counts are `try #require`d before any
per-phase indexing (shape 13).

**Phase order** is a second, small test. For
`leaf.background(.accent).onClick(inner).padding(4).background(.surface).onClick(outer)`:
`lastHitboxes` lists the outer layer before the leaf; the scene emits the
surface rect before the accent rect; a click in the padding ring runs `outer`;
and a click inside the leaf runs `inner`.

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

## MC-G — `SA-R`'s compile-time check is DELIVERED: a typed `ProposalNodeID` with an internal initializer, returned by a new requirement on `ProposalElementGroup`; five lies become compile errors, and three named holes stay, each pinned

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
// `where Content: ProposalElementGroup`.
```

Every public `LayoutPass.requestNative*` registrar returns `ProposalNodeID` and
takes `ProposalNodeID` children. Proposal containers and wrappers call
`requestProposalGroupLayout`, never `requestGroupLayout`.

**Measured, skeleton `TypedNodeKit.swift` + clients, plain import, Swift 6:**

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

**A finding the design depends on.** Without restating `associatedtype
LayoutState` in `ProposalElement`, the skeleton module itself fails to build:
`error: type 'Leaf' does not conform to protocol 'Element'`. Swift does not
infer `Element.LayoutState` through the default `requestLayout` that
`ProposalElement`'s extension supplies.

**What stays open, precisely.**

1. **Two entry points can disagree** (`liar4`, `Both`). The untyped one is
   reached only by `Frame`'s root and by legacy containers, and a proposal
   element under a legacy container already traps (`SA-G`). A proposal element
   that lies there is therefore harmful only as a root, where it renders as the
   legacy element it registers. A typed entry that returns the wrong *count*
   still trips the one-node wrapper preconditions. Pinned wrong on purpose by a
   positive guard (spec lane 3, test 6).
2. **A side-effect registration is invisible to the type.** Measured on today's
   code (scratch test): an element whose `requestLayout` calls
   `pass.requestNode(style: Style(), children: [])`, discards the result and
   returns a native leaf rendered inside `VStack { HStack { it }; Rectangle }`
   with no trap. Its prepaint saw 10×10, and the scene held 1 rect. The orphan
   legacy node is never attached. Pinned wrong on purpose by a runtime test
   (spec lane 3, test 7).
3. **`unsafeBitCast`**, and `@testable` code calling the internal initializer.
   Out of reach of any access-control check. The run-time traps from `SA-G`
   stay as the backstop, and the existing liar trap test is rewritten to mint
   its id through `@testable` so the trap stays pinned.

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
- **If the holes above are later mistaken for closed**, a lying conformer that
  compiles is again a run-time trap. They are named here and pinned so they
  cannot be.

**Mutations:** owed by lane 3.

---

## MC-H — the typed defaults live in NEW files and in the proposal files; `Element.swift`, `ElementGroup.swift` and `Component.swift` are not edited; the registrars change IN PLACE rather than gaining typed twins

**The choice.**

- **`Sources/MetalUI/ProposalNodeID.swift` (new)** holds `ProposalNodeID`,
  `ProposalElement` and its two defaults, and the
  `extension Component where Content: ProposalElementGroup` default.
- **`ProposalElementGroup.swift`** gains the requirement and the builder
  groups' conditional implementations beside their existing conditional
  conformances.
- **`Passes.swift`** changes only the registrar block's parameter and return
  types (lines 55–150 at `f64e58a`). `Frame`'s internal registrars stay
  untyped.
- **The typed group defaults repeat the untyped ones** — `GlobalElementID.child`,
  `StateBinder.bind`, `cursor += 1`, and for `Component` the content
  materialized once — rather than refactoring `ElementGroup.swift` and
  `Component.swift` into shared helpers. Each doc comment names its twin and
  the tests that pin each copy.

**Why.** Three tracks run in parallel and merge afterwards. `Element.swift`,
`ElementGroup.swift` and `Passes.swift` are named shared files; edits there must
be minimal and localized. **Typed twins of the registrars** (keeping the
untyped ones) would be additive, but they would leave eleven public untyped
native registrars with no caller in `Sources/`, and the untyped ones would mint
native nodes that no proposal element can use: a declared-but-inert row by
construction. Changing the types in place is a localized edit to one block.

**What it costs if wrong.** The duplicated default is `AnyElement`'s hazard
("the second thing to go missing from the copy", `ElementGroup.swift`). It is
bounded by three mutations that must each redden a named test: delete
`ProposalElement`'s typed `StateBinder.bind`; delete its `cursor += 1`; and
delete the `Component` typed default's bind. All three are carried by `MC-D`'s
proposal test. A later refactor into one helper is a legal
simplification after merge.

**Mutations:** owed by lane 3.

---

## MC-I — `ModifiedElement` is a registering site in both phases and gets an arm in all six per-site guards, each arm exercising an INNER layer as well as the outermost

**The choice.** Arms for a two-layer chain are added in place to:

- `everyRegisteringSiteAnimatesItsStyle` and
  `everyBackgroundPaintingSiteAnimatesItsColour` (`AnimationTests.swift`);
- `everyBackgroundPaintingSiteHonoursHoverAndFocus` and
  `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`
  (`BackgroundChainTests.swift`);
- `onClickIsLiveOnEveryConformerThatCanRegisterOne` (`InputDispatchTests.swift`);
- `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`
  (`AXEmitSiteTests.swift`).

**Why the inner layer.** The likeliest wrong implementation of a flat chain
wires the outermost layer — the one `StyledElement`'s accessors reach — and
forgets the loop. An arm on a one-layer chain would pass it.

**Why in place, in shared-ish files.** CLAUDE.md's Animation section: "A site
that skips its helper is silently unanimated with no diagnostic; the two
per-site guards are …". The guards' value is one list. Record §09 already lists
`FrameModifier` arms in five of these guards as owed, and `FrameModifier` is
replaced by this type, so the debt transfers. Each arm is one additive block, so
a merge conflict is textual at worst.

**What it costs if wrong.** Without the arms, `ModifiedElement`'s `animated`,
`animatedBackground` and `registerHandlers` calls — the demo sidebar's width
animation among them, which lives on a padding wrapper — could each be deleted
with the suite green. Record §09 says so of `FrameModifier` today, by reading.

**Mutations:** owed by lane 2.

---

## MC-J — the demo: the default window must not change pixel-for-pixel apart from desktop corners; lane 3 edits two preview declarations; no look is claimed for the preview

**The choice.**

- **Lane 2 captures the release default demo before and after.** The baseline
  is taken at the lane's start commit, whose default demo is `f64e58a`'s: lane
  1 touches only `NativeOverlayModifier.swift`, which `demoContent()` does not
  reach. The method is record §03's of 2026-09-14:
  - `swift build -c release`, launch `MetalUIDemo`, wait for the first frame;
  - find the window through `CGWindowListCopyWindowInfo`'s bounds;
  - `screencapture -x -R<x,y,w,h>`;
  - **no input sent, pointer not moved**, and the pointer position logged
    first, since a pointer over a list row changes its hover colour;
  - compare every pixel.

  Record §03's accepted difference: a few dozen pixels at x ≤ 8, y ≤ 46 (the
  desktop behind the rounded corner). Lane 3 repeats the default-demo capture,
  since it rebuilds every proposal type the preview uses.
- **Lane 3 edits the demo's preview** as `MC-G` forces: `PreviewToggle.content`
  becomes `some ProposalElementGroup`, and `PriorityPreviewPanel` conforms to
  `ProposalElement` with a typed `requestProposalLayout`. It also captures the
  preview window (`METALUI_NATIVE_LAYOUT_PREVIEW=1`) before and after, for the
  same comparison. That is a regression check, not the human look record §09
  says the preview has never had.

**What it costs if wrong.** The 2026-09-14 `.padding` change regressed the
default demo, which went unseen until a capture (record §03). A representation
change to the same wrapper is exactly that risk again.

**Mutations:** not applicable. The capture is the check; its two PNG sizes and
the differing-pixel count go in record §10.

---

## MC-K — the outermost layer is stored inline and the rest in an array, so a single-modifier chain allocates nothing a `Box` did not; measured by lane 2, pinned only if the counter can tell the two apart

**The choice.** `ModifiedElement` stores `outermost: ModifierLayer` and
`inner: [ModifierLayer]`. Its `Layout` likewise stores `outermost` and `inner`.
An empty array does not allocate, so `.padding(4)` on a list row costs what
`Box<Self>` costs.

**Why not one array.** Every padded row in the demo's 500-row list would
allocate two arrays per frame build (layers and layouts). `Box<Self>` allocated
none for the wrapper.

**Measured / pinned.** Lane 2 counts allocations on the calling thread with
`FreezeLoopAllocationTests.swift`'s `malloc_logger` instrument, copied since it
is private. It counts `requestLayout` of 500 one-layer chains against 500
hand-built `Box<Leaf>`, calibrated first against known buffers. A test is kept
**only if** the mutation "store every layer in one array" reddens it. If it
cannot tell them apart (the swiftlang-toolchain floor CLAUDE.md records), the
lane records both numbers here and keeps no test. A test that cannot fail is
the disease this repo's practices doc names.

**What it costs if wrong.** A per-frame allocation per padded element; no
behaviour changes.

**Mutations:** owed by lane 2.

---

## MC-L — deferred, and to whom

Not in this track. Each item is named so a green run of this track is not read
as covering it.

| item | why not here | owner |
|---|---|---|
| `width`/`height`/min/max as layers; legacy `.frame` min/ideal/max/alignment | the plan forbids it here | task 4 |
| `Component` modifier distribution (`StyledComponent`), and caller modifiers snapping (B-7) | the plan forbids it here | task 5 |
| paint-only legacy layers (`background`, `cornerRadius`, …) and the wrap/distribute/paint matrix | task 5's matrix | task 5 |
| unifying `ModifiedElement` with proposal `ModifiedContent` | two engines until task 7 | task 7 |
| a public, user-definable modifier protocol | `MC-A` | task 7 or later |
| `EitherGroup: ProposalElementGroup` (record §09 boundary 4) | not composition of modifiers | tasks 6/8 |
| one-node wrapper traps on 0 or 2+ nodes (boundary 2) | a typed id fixes the kind, not the count | task 6 |
| the holes in `MC-G` items 1–3 | no mechanism within public Swift (item 3); items 1–2 need the legacy root switch gone | task 7 |
| proposal `.id()`, focus, AX | interaction | task 12 |
| animation on proposal wrappers, and wrappers joining transactions | | task 13 |
| divergence 19 (one value placed twice) and `@State` inside `AnyElement` | not modifier composition | task 8 |
| a separate test that two `ProposalScrollView`s in an overlay keep separate `ScrollState` | closed by `MC-E`'s mechanism, not separately pinned | task 6 |
| deprecating `nativeFrame(…)` | breaks the 0-warning baseline (record §09) | integration step |
| CLAUDE.md / AGENTS.md / plan / record README updates: guard count, "registering points", `FrameModifier` mentions | owned by the integration step | integration |

---

## MC-M — method: what this session measured, and what it only read

- **Measured:** every table row in `MC-C`, `MC-E` and `MC-G`, and the type
  inference in `MC-A`/`MC-B`, by the runs listed under "Where each number was
  measured".
- **By reading, not run:** that `FrameModifier`'s phases equal `Box`'s
  (`MC-B`'s premise; lane 1's oracle test is its measurement); that lane 1's
  counting arms cover every distinct code path in `ModifiedContent`'s phases
  (lane 1 enumerates them against the source); the 35-conformance count
  (grep); that `demoContent()` reaches no `.overlay` (grep: its one `.overlay`
  is in `PreviewToggle`, the preview's).
- **The scratch tests were deleted, not committed.** Their shapes are
  reproduced as lane 1's first three tests and lane 3's orphan pin, which must
  each be red (or, for the orphan pin, green as measured) on their first run.
- **Instrument checks.** The SwiftUI probe's controls A and B are its positive
  controls. The skeleton's negative clients each printed the specific
  diagnostic, not just a non-zero exit (practices shape 16's "print the real
  diagnostic before trusting it").

**Mutations:** not applicable.
