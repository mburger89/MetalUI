# `Component` — decisions taken during execution

Rulings from the milestone that added `Component`: a protocol whose author
writes `content` and gets a working element, which is **transparent to layout**
and **opaque to identity**, and whose modifiers **distribute** over its
top-level children rather than wrapping them. **M4, spec 2 of 4.**

Prefixed **`CO-`** and **lettered** (`CO-A`, `CO-B`, …) per this repo's
convention — **a bare `CO-3` is a typo, not a citation**, the same note every
other milestone's decisions doc carries.

Read alongside `docs/superpowers/specs/2026-09-03-component-design.md` (§2 has
the transparency measurement, §5 the distribution measurement that overturned
this spec's own first design, §8 the exit criteria) and
`.superpowers/sdd/2026-09-03-component/progress.md`, the execution ledger these
rulings are drawn from.

## How to read the letters, because they are not all the same kind of thing

**`CO-A` through `CO-O` carry the ledger's own letters `A` through `O`, one for
one, deliberately.** The ledger lettered fifteen rulings during execution;
renumbering them here would make every citation written during the milestone
ambiguous, which is the hazard `EP-2`/`EP-4`, the tombstones milestone's
`TB-A`…`TB-AD` mapping and the reactivity milestone's `RX-A`…`RX-J` mapping all
exist to prevent. So ledger ruling `H` is `CO-H` here, and nothing else is.

**`CO-P` through `CO-Z` are new, and they are the eleven decisions a reader
should start with.** They were never lettered in the ledger because they were
settled in prose — in the spec, in a user decision, in task reports — rather
than adjudicated as controller rulings. They are also the eleven this milestone
is actually *about*: what the two axes are and why one of them is not a choice,
why `StyledElement` was refused, what `display: contents` would buy, why
`Content` diverges from the binding-authority spec, why there is no `.id()`,
why modifiers distribute, what `LayoutTree.setStyle` is doing in production for
the first time, what cannot be distributed and why it is offered *not at all*,
what a chained modifier does, why the demo was left alone, and a name collision
a reader arriving from SwiftUI will get wrong. **Read P–Z first, then A–O for
the execution findings.**

Not every letter is a mechanism decision. Several are findings about the
*record* — a spec claim measured and found true, a plan claim measured and found
false, a controller prediction that was never measured at all — and they are
kept because this repo's own practices document is assembled from exactly those.

**Everything numeric below was measured in this tree at commit `32542d7`
unless the ruling says otherwise — a comment-only `ca33d88` landed on top of it
while this document was being written and moves no count (`git show ca33d88 --
'Tests/*' | grep -c "^+.*@Test"` reads 0), so the figures are dated to the
commit they were run at rather than to HEAD, which is `RX-R`'s rule — and where a figure came from a throwaway probe
outside the repo rather than from the suite, the ruling says so at the number.**
That distinction is `TB-AA`'s rule and this milestone had to apply it to both
SwiftUI probes. Two labels appear at their own numbers: a figure measured
against **SwiftUI** rather than against this tree (`CO-P`'s four subview counts,
`CO-U`'s four sizes), and a mutation count that was **predicted and not
measured** by the controller (`CO-N`, and the correction is in `CO-N` itself).

**Where the authoritative copy of each in-tree mutation figure lives, so a
future editor knows which to update first.** The four Task-2 mutation results
appear in two places apiece: `Sources/MetalUI/Component.swift`'s own doc
comments, and this document. **The source is authoritative**, because it is the
copy a mutation is run against. Re-measure there, correct there first, then
propagate here. The SwiftUI probe figures are a *different* measurement — the
standard library's behaviour, not this tree's — and live in the component design
spec's §2 and §5 tables and here; they must not be reconciled with the in-tree
numbers.

---

# The eleven foundational decisions

## CO-P — a `Component` is transparent to LAYOUT and opaque to IDENTITY, and only the first half was a choice

**The choice.** A component contributes **no layout node of its own** — its
content's `[LayoutNodeID]` is returned unchanged, so `Column { MyRow(); MyRow() }`
lays the rows' children out as the `Column`'s own children — and it consumes
**one cursor index**, so its content nests beneath the component's own
`GlobalElementID`.

**Those are separate axes in this framework and this is the first type to use
them differently.** Every other element is opaque to both: a `Box` consumes one
cursor index *and* contributes one layout node. Stating them as one sentence
with two halves is deliberate, because a reader who carries only one half will
be wrong about the other in a way nothing warns them about.

**Layout transparency is the choice, and it is SwiftUI's answer**, taken per
ruling `EP-5` and the user's standing recorded preference. It is measured
against SwiftUI rather than derived — see `CO-P`'s companion `CO-E` and the
four subview counts in `CO-U`'s neighbour paragraph.

**Identity opacity is NOT a choice, and that is the half worth writing down.**
`@State` slots are `.named("$state\(n)")` children of the element's own
`GlobalElementID` (`StateBinder.bind`), so a component with **no id of its own
could not hold state at all** — and holding state is the main reason to write a
component rather than a function returning elements. The cursor index is what
buys the id. A design that made a component transparent to *both* axes would
have shipped a protocol whose whole selling point silently does not work.

**What the two halves cost together, and it is the framework's own
vanishing-`if` hazard arriving in a new place.** Because identity is positional,
inserting a sibling before an **unnamed** component shifts its id and resets its
state, exactly as it does for a `Box`; the remedy is the same one CLAUDE.md's
identity bullet gives — declare `elementID`. Pinned from both directions by
`aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`
(`Tests/MetalUITests/ComponentTests.swift`), whose asymmetry is the evidence.

**What it costs if wrong.** Making a component layout-opaque moves every rect in
every tree that uses one — see `CO-Q`, which is the specific way that would
happen by accident. Making it identity-transparent breaks `@State` inside every
component with no diagnostic, which is the `AnyElement` failure mode CLAUDE.md's
declared-but-inert table already carries one live example of.

---

## CO-Q — `StyledElement` conformance was rejected, and the mechanism that forces it is `Style.display`'s default

**The choice.** `Component` does **not** conform to `StyledElement`, and no
`Style` property was added anywhere.

**It was a live candidate and reads best at the call site.** Conforming would
give `MyComponent().padding(12)` for free, with no new modifier surface at all.

**It fails on two counts and the second is fatal.** `StyledElement` has four
requirements — `style`, `decoration`, `elementID`, `handlers` (ruling `IN-H`) —
so every component an author writes carries four stored properties of
boilerplate, which is the opposite of the ergonomics this type exists for. And
**a `Style` must attach to a layout node**, so conforming *forces* the component
to contribute one. `Style.display` defaults to `.flex` and the engine has no
`contents` case — `grep -n "public enum Display" Sources/MetalUILayout/Style.swift`
reads `public enum Display: Sendable, Equatable { case flex, stack, none }`,
re-run at this milestone's last commit — so that node is a **real flex
container** and the component becomes layout-opaque. That is the exact
divergence from SwiftUI `CO-P` exists to avoid, arriving as a side effect of a
convenience.

**This is a constraint on future work, not only a record of a past decision.**
Adding `StyledElement` conformance later "for convenience" would silently make
every existing component layout-opaque and move every rect in every tree using
one, with no compile error and no test naming the cause. The component design
spec's §9 risk table carries the same row for the same reason.

**What it costs if wrong.** The cost of the refusal is the modifier surface
`CO-U` had to build instead — three forwarded modifiers rather than the whole of
`StyledElement`'s — and `CO-W`'s limit, which is that `Decoration`- and
`Handlers`-backed modifiers are not offered at all.

---

## CO-R — `display: contents` is the CSS-correct primitive, was deferred on SCOPE rather than on merit, and is what "styled *and* transparent" needs

**The choice.** Not implemented in this spec. Named as a follow-up rather than
left as a mystery.

**What it is.** A node that contributes its children to its parent's layout as
though it were not there. That is exactly this problem's CSS answer, and it is
the only way to give a **styled** box the transparent behaviour — a thing this
design cannot express at all. `Component` gives transparency to something with
no style of its own; `display: contents` would give it to something with one.

**Why it was deferred, and the reason is checkable rather than a mood.** It is
layout-engine work in `collectItems` and the flex algorithm; it needs browser
fixtures and goldens; and **it would be the first thing in three M4 specs to
move a golden**. This branch's own exit criterion is that
`git diff --name-only b36195d..HEAD -- Sources/MetalUILayout/` is empty, verified
empty at `32542d7`, and 87 goldens unmoved. Implementing `display: contents`
inside this spec would have made that criterion unmeetable by construction.

**What a reader should do with it.** If you want a styled, layout-transparent
box, this is the mechanism — not a second `Component` variant, and not a
`StyledElement` conformance (`CO-Q`). It is recorded in CLAUDE.md's `Component`
bullet too, so a reader who wants it finds the follow-up rather than
re-deriving it.

**What it costs if wrong.** Nothing shipped depends on it. The cost of the
deferral is that the one case it covers has no spelling today and the honest
remedy is an explicit `Box`, which is one visible line and is at least honest
about introducing a container.

---

## CO-S — `Content: ElementGroup` diverges from design spec §4.2, and §4.2 is corrected in place

**The choice.** `associatedtype Content: ElementGroup`, where
`docs/superpowers/specs/2026-08-24-metalui-design.md` §4.2 declares
`associatedtype Content: Element`. The same section declares
`protocol Component: Element`, and the shipped protocol refines `ElementGroup`.
Both are corrected in §4.2 with the original visible, in the `>`-quoted style
§4.3 and the reactivity milestone's §4.4 block already use.

**Why `Content: Element` is not merely stricter but unusable.** A bare
two-statement content block — `{ Text(…); Text(…) }` — builds a `Pair`, which is
an `ElementGroup` and is **not** an `Element`. Under §4.2's literal text a
component could never have two top-level children, which is most of the reason
to write one. `Element` refines `ElementGroup`, so `ElementGroup` is strictly
more permissive and a single-element content still satisfies it.

**Why `Component: Element` is the same defect one level up.** An `Element`
contributes *exactly one* layout node. Layout transparency (`CO-P`) is the
statement that a component contributes zero or many. The two cannot both be
true, and §4.2's own prose ("materializes `content` once … forwards all three
phases") is neutral between them, which is why the declaration is where the
error lived.

**Half of §4.2 is ACCURATE and shipped as written, and saying so is the point.**
The extension really does materialize `content` **once** and stash it —
`ComponentLayout.content` is that field, pinned by
`contentIsMaterializedExactlyOncePerFrame` — and really does forward all three
phases, and implementing `Element` directly really does remain available for the
node graph. **A correction block that does not separate the right half from the
wrong half teaches a reader to distrust all of it**, which is a worse outcome
than the original error.

**Why the correction goes in the binding-authority document rather than only
here.** `CLAUDE.md`'s "Start here" names that spec as binding authority, so a
false declaration there is worse than the same claim downstream — the same
argument `RX-K` made for §4.4 one spec earlier.

**What it costs if wrong.** `Content: ElementGroup` lets a component return a
group where a single element was meant, and a caller cannot tell from the type.
True, and it is the same latitude `Box`'s content already has; the alternative
forbids two children.

---

## CO-T — there is no `.id()` modifier on a `Component`; the defaulted `elementID` property is the spelling that cannot be wrong

**The choice.** `elementID: ElementID?` is a protocol requirement with a `nil`
default in the extension. An author who needs a stable name declares it:

```swift
struct Row: Component {
    let item: Item
    var elementID: ElementID? { ElementID(String(describing: item.id)) }
    var content: some ElementGroup { … }
}
```

**Why there is no modifier.** `.id(_:)` lives on `StyledElement`, which a
component does not conform to (`CO-Q`). A wrapper type supplying the name would
have to do one of two things and both are wrong: introduce a layout node, which
defeats `CO-P`; or introduce a second identity level, which makes the name apply
to the **wrong id** — the wrapper's, not the component's. That second failure is
silent, and its shape is exactly what `CO-U`'s `StyledComponent` had to be built
to avoid (see `addingAModifierDoesNotResetAComponentsState`).

**What it costs.** It is less pretty than `.id(…)` and it is a property
declaration rather than a call-site decoration, so a reader skimming a call site
cannot see that a component is named. Accepted: the alternative is a spelling
that compiles and names the wrong thing.

---

## CO-U — modifiers DISTRIBUTE rather than wrap, this was MEASURED against SwiftUI, and it OVERTURNED this spec's own design

**The choice.** `MyComponent().padding(4)` returns a `StyledComponent<C>` which
forwards to the component, **amends the `Style` of each top-level node the
content contributed**, and returns those same nodes unchanged. It contributes no
node of its own, so a modified component stays layout-transparent.

**The spec said the opposite, and it said it with a reason.** §5 originally
specified wrapping the component in a `Box`, on the stated grounds that this is
what SwiftUI's `ModifiedContent` does. Task 3 was written to implement that.
**The claim was measured and is false**, and the design was rewritten before it
shipped — plan commit `b8f9918`, spec commit `b9d6895`.

**The measurement. A throwaway probe outside the repo reading
`NSHostingView.fittingSize`; `MyRow`'s body is a 30×10 and a 50×10 view.**

| case | measured |
|---|---|
| `HStack { Color.red.frame(30,10).padding(8) }` — **the positive control** | 46 × 26 |
| `HStack { MyRow() }` — baseline | 88 × 10 |
| `HStack { MyRow().padding(8) }` | **120 × 26** |
| `HStack { Group { A; B }.padding(8) }` — the known-distributing case | **120 × 26** |

`(30 + 16) + 8 + (50 + 16) = 120`. The padding lands on **each** child, and the
result is bit-identical to `Group`'s. **A wrapping implementation predicts
96–104**, which is what makes the arms of this comparison disagree — this
milestone's own instance of the discriminator CLAUDE.md's practices section
states: *require the arms of a comparison to disagree before believing that they
agree.*

**The baseline's 88 is not filler.** `30 + 8 + 50`, with `HStack`'s default
spacing, independently corroborates `CO-E`'s flattening result **on a different
instrument** — a size readout rather than a `Layout` conformer's subview count.
Two probes, two mechanisms, one answer.

**Transparency and distribution are ONE mechanism, and this is the sentence to
carry.** `MyRow()` *is* its children, so a modifier applied to it applies to each
of them, **because there is no single thing to wrap**. A reader who learns them
as two facts will expect them to be independently changeable, and they are not.

**Neither probe is committed**, on the footing this repo uses for oracle probes
(divergences 2 and 9, and `RX-K`'s standalone `Observation` probes): a committed
version would pin the *standard library's* behaviour rather than this
framework's. The technique is recorded in `CO-E` and in the design spec's §2 and
§5 so it can be re-run rather than re-derived.

**What it costs, and it is the risk table's first row.** An author who writes a
component expecting `.padding()` to pad the component **as a unit** gets each
top-level child padded instead. For a single-child component the two are
indistinguishable; for a multi-child one they differ visibly. §5 states it,
`aModifierOnAComponentDistributesToEachTopLevelChild` pins it, and **nothing
enforces it** — there is no diagnostic and cannot be one.

**And the fixture the controller specified for it could NOT have shown
distribution, because this engine's box model is BORDER-BOX ONLY.** `Style`'s
own doc comment says so — *"Box model is border-box only (spec §5.2): `size`,
`minSize` and `maxSize` include padding and border. There is deliberately no
`boxSizing` property"* — so **padding an explicitly-sized box shrinks its
content rather than growing its rect**. The brief's `TwoLeaves` fixture gives
both leaves explicit widths, so `.padding(4)` on it moves the outer rects not at
all and the distribution assertion would have been vacuous: a wrapping
implementation and a distributing one produce the same numbers on it. The
implementer **reported the mismatch rather than silently adapting**, and added a
second, **auto-sized** fixture (`TwoAutoLeaves`) for that one test while leaving
`TwoLeaves` and its three dependents alone. This is taxonomy shape 15 —
a fixture in which the code under test cannot be reached — arriving in a *plan*
rather than in a benchmark, and it is the third time on this branch that a
stated claim about what a fixture would show turned out false when run.

**What it costs if wrong.** Shipping the wrapping design would have put a
silent layout node inside every modified component, disagreeing with SwiftUI on
the one axis this whole design exists to agree with it on, and would have been
invisible to any assertion that did not read a rect.

---

## CO-V — `LayoutTree.setStyle` gains its FIRST production caller, and amending a style after registration is sound rather than tolerated

**The observable.** `LayoutTree.setStyle(_:_:)` existed before this milestone,
is `public`, and had **zero production callers** —
`git grep -n "setStyle" b36195d -- Sources/` returns three lines, all inside
`LayoutTree.swift` itself (the declaration, its own doc, and its precondition's
message string), and the only exercise was
`Tests/MetalUILayoutTests/LayoutContextTests.swift`. `StyledComponent.requestGroupLayout`
is its first, reached through `PrepaintPass`/`LayoutPass.setStyle` →
`Frame.setStyle` → `tree.setStyle`.

**Three things had to hold and each was checked rather than assumed.**

- **Registration derives nothing from style.** `newNode`/`newLeaf` append the
  style and a zeroed layout into parallel arrays; every engine consumer reads it
  fresh through `tree.style(id)` inside `computeLayout`. So amending *after*
  registration is **sound**, not merely tolerated — there is no derived state to
  invalidate.
- **The one guard is a phase boundary, and this is safely inside it.**
  `setStyle` traps when `isLayingOut`, which is set only within `computeLayout`.
  `Frame.render` completes the whole `requestGroupLayout` walk **before** calling
  `computeRootLayout`, so a modifier amending styles during the request phase
  cannot trip it. Task 3's reviewer verified that ordering against `Frame.render`
  rather than taking the claim.
- **No `ElementGroup` change and no engine change were needed.** The wrapper
  operates on raw `LayoutNodeID`s, not on the Swift values that produced them, so
  it is **indifferent to whether a top-level child came from a `StyledElement`**
  or from a nested non-`StyledElement` `Component`. That was the hazard most
  likely to make distribution impossible, and it does not arise.

**Which is why `Sources/MetalUILayout/` is untouched for the whole branch** even
though this milestone's headline feature is a style amendment: the call is made
from `MetalUI`, and the engine already had the API.

**No inert-table row is deleted and none is added.** `setStyle` was never in
that table — it had a *test* reader and a live guard, which is a different thing
from "exists, compiles, and does nothing" — so this is recorded here rather than
as a table edit.

**What it costs if wrong.** If registration ever *did* derive something from
style, every distributed modifier would produce a node whose derived state
disagrees with its declared style, with no trap and no assertion able to see it.
The bullet above is the standing check for whoever adds such a derivation.

---

## CO-W — `Decoration`- and `Handlers`-backed modifiers are offered NOT AT ALL rather than with wrapping semantics

**The choice.** `padding`, `width` and `height` are forwarded to a `Component`.
`background`, `onClick`, `focusable`, `keyContext`, `hoverBackground` and
`focusBackground` are **not declared on `Component` at all**.

**The mechanism, and it is a real wall rather than a scope call.**
`LayoutTree.setStyle` reaches a node's `Style`, keyed by `LayoutNodeID` — so
every `Style`-backed modifier distributes. `Decoration` and `Handlers` are
**per-element** state, registered by each `StyledElement`'s own `prepaint`
through `registerHandlers`, and **there is no per-node table to amend**.
Distributing them hits exactly the non-`StyledElement`-child wall that
`setStyle` sidesteps.

**Why absent beats present-with-different-semantics.** Offering `.background()`
with wrapping semantics beside a distributing `.padding()` would ship **two
modifiers that read identically at a call site and behave differently** — one
adds a layout node and one does not, one applies once and one applies per child.
That is worse than offering neither, because the call site gives a reader no way
to tell which they wrote. An author who wants a background writes an explicit
`Box` around the component, which is one visible line and is honest about
introducing a container.

**The absence is pinned twice, and the second pin is the load-bearing one.**
`decorationBackedModifiersAreNotOfferedOnAComponent` (`ComponentTests.swift`) is
a type-name check; `backgroundCannotBeCalledOnAComponent`
(`Tests/MetalUITests/ErasureCompileGuards.swift`) is a `swiftc -typecheck` guard
asserting that `Leafless().background(.accent)` **does not compile**. A
regression that adds the modifier makes that probe *compile*, which **no runtime
test could see**. This is what took the guard count **32 → 33**, re-counted by
per-file `grep -c canTypecheck` at `32542d7`: 19 `PhaseSeparationTests` + **8**
`ErasureCompileGuards` + 1 `ElementGroupTrapTests` + 2 `UnitSafetyTests` (a bare
`grep -c` there reads 3; one is a comment) + 3 `AXNodeTests`.

**What would close it, named rather than left as a mystery.** Either a per-node
decoration/handler registry, or the `ElementGroup` per-child operation that
would let a wrapper reach the Swift values rather than the node ids. Both are
larger than this spec, and the second is M4 spec 4's own subject.

**Which forwarded modifiers, and the one rule.** Only those already live on
`StyledElement`, with a **parameter type matching the original exactly** —
`padding(_ points: Pixels)`, `width(_ points: Pixels)`, `height(_ points: Pixels)`
against `Box.swift`'s `padding(_:)`, `width(_:)` and `height(_:)`. Forwarding an
inert one (`aspectRatio`, `overflow`) would put a second unreachable API in front
of a caller, which is what CLAUDE.md's inert table exists to prevent. **No row is
added to that table for the forwarded three**: each has a live original and real
callers in tests.

**What it costs if wrong.** A component author reaching for `.background()`
finds it absent with no explanation at the call site. The remedy is written into
`StyledComponent`'s own doc comment, which is where they will be looking.

---

## CO-X — chained modifiers compose onto a stored `amend` closure, and `.padding(4).padding(8)` — the SECOND CALL WINS OUTRIGHT

**The defect that forced this, and it was found by `swiftc -typecheck` rather
than argued.** As first shipped, the forwarded modifiers **did not compose**:

```
Leafless().width(Pixels(10)).height(Pixels(20))
→ error: value of type 'StyledComponent<Leafless>' has no member 'height'
```

`StyledComponent` is an `ElementGroup`, not a `Component`, so
`extension Component { padding / width / height }` is unreachable on what a
modifier *returns*. An author could apply **at most one** modifier to a
component. `.width().height()` — the most natural pairing, and the one this very
diff's own fixtures use — was unreachable, while `StyledElement`'s equivalents
chain freely because they return `Self`. The asymmetry was undocumented.

**It went undetected because NO TEST EXERCISED `width` OR `height` AT ALL** —
only `padding` was covered. That is CLAUDE.md's recurring lesson verbatim: *a
feature that works alone and a feature that works alone can be wrong together.*

**The fix.** An `extension StyledComponent` whose three modifiers chain onto the
`amend` closure the value already carries — capture `previous = amend`, run it
first, then assign the new field. Ruling `CO-N` required this **before merge**
rather than deferring it: shipping three modifiers of which only one may be used
is worse than shipping one, because the API reads as composable at every call
site and fails at the second call.

**Same-field composition was MEASURED rather than predicted, and the controller
deliberately refused to state an expected answer in the dispatch.**
`.padding(4).padding(8)` gives a leaf **width 16 = 2 × 8**. So:

- it does **not** accumulate — accumulation would give 24;
- and the first value does **not** survive — that would give 8.

**The second call wins outright**, which matches `StyledElement.modifying`
(`Box.swift`), whose field writes are plain assignments rather than merges: a
second `.padding(_:)` on a `Box` simply overwrites the first. Asserted directly
by `chainedPaddingReplacesRatherThanAccumulates`.

**The mutation, and the honest negative that came with it.** Dropping
`previous(&style)` from all three chained overloads reddens **2 issues on
`widthAndHeightComposeOnAChainedModifier`** — the width is lost and only the
height survives, both leaves reading `(0, 23, 0, 15)`. And
`chainedPaddingReplacesRatherThanAccumulates` **stays green** under that same
mutation, because same-field replace-versus-compose is indistinguishable: with
`previous` dropped, the chained `padding(_:)`'s closure does
`style.padding = 8` unconditionally, which is **byte-identical** to
composing-then-overwriting, since `Style()`'s default padding is `0` either way
— there is nothing the earlier `.padding(4)` could have left behind for the
later one not to overwrite. **The implementer reported that negative
unprompted**, which is the half most reports omit — stating what a test *cannot*
see is what keeps the next reader from citing it for something it does not
cover. **And it was then walked back to the test's own doc comment in a
follow-up commit (`ca33d88`), which is the correction practices mechanism 1
asks for**: the negative had been reported and not applied to the line, so the
two tests read as redundant when they are complementary —
`widthAndHeightComposeOnAChainedModifier` is what actually catches this mutation
and the padding one cannot.

**What it costs if wrong.** A distributed style silently dropping one of two
chained fields is invisible to a node count and visible only in a rect, which is
why the pin asserts geometry.

---

## CO-Y — the demo was NOT converted, and the plan forbade it outright rather than leaving it to judgement

**The choice.** `Sources/MetalUIDemo/main.swift` is untouched for the whole
branch. `CounterPanel` — the obvious first real caller — stays an `Element`.

**The design spec permitted a conditional conversion** (§7: convert `CounterPanel`
**only** if the conversion moves no rect) and **the plan forbade it outright**.
The tightening is the ruling.

**Reasoning.** This one file carries **every** past milestone's
human-verification criteria — M2's contrast judgement, the `Stack` z-order look,
the modal's four failures, the scroll-list report items, the reactivity
milestone's counter summary. A change to it is a change to that evidence, and
"no rect moved" is a weaker guarantee than it sounds when the criteria include
things no rect can express. The modal-scrim precedent is the standing one: a
per-look change to this file taxes every future look.

**What it costs, stated because "deliberate" is not "free".** `Component` ships
with **no production caller**. Its only exercise is `ComponentTests.swift`, so
the one thing the type exists for — whether it is *pleasant to write* — has no
evidence at all, and the design spec says so up front in its own "what no test
here can see". This spec closes none of M4's three exit criteria on its own;
"a real small app" is the milestone's criterion, not this spec's, and that is
where a real caller arrives.

**What it costs if wrong.** A protocol whose ergonomics nobody has exercised may
turn out awkward in its first real use, and the first real use is a later spec's
problem. Recovering costs a modifier or two, not a redesign — the two axes
(`CO-P`) are the part that would be expensive to change, and they are pinned.

---

## CO-Z — in this codebase `Binding` means a KEYMAP binding, and a reader arriving from SwiftUI will read it as a two-way value binding

**The observable, measured while discharging `CO-D`.** `State` is the **only**
`@propertyWrapper` in `MetalUI` (`Sources/MetalUI/State.swift`). There *is* a
`public struct Binding` — in `Sources/MetalUI/Keymap.swift` — but it is a
**key → action** binding, not a property wrapper. So `@Binding var x: Int` does
not resolve to it and does not quietly do something surprising; it **fails to
compile, with a confusing error**, because the name exists and is not a wrapper.

**Why it is recorded.** A reader arriving from SwiftUI reads `Binding` as a
two-way value binding and will read a `Keymap`'s `Binding("m", ToggleModal())`
as something it is not. The framework has **no two-way value binding of any
kind**, and its absence is not visible from the name.

**What it costs if wrong.** Nothing shipped depends on it. The cost of *not*
recording it is that the next task to want a two-way binding finds the name
taken and has to re-derive that the collision is only a name.

---

# The ledger's rulings, A through O

## CO-A — Task 1 owns the node-count spelling and Task 3 inherits it

The plan flagged that `frame.layoutNodeCount` may not exist and told Task 1 to
pick a fallback under `@testable` **without adding production API**. If each
task chose independently the two would drift and a reviewer could not compare
them. **Discharged:** the spelling is `frame.tree.nodeCount` — `Frame` has no
`layoutNodeCount`, `LayoutTree.nodeCount` exists, `Frame.tree` is `internal` and
`@testable`-reachable, and `ElementLayoutTests.swift` already uses this exact
idiom for the identical question. No production accessor was added. **Cost if
wrong:** Task 3 needs one line to match; caught by its own review.

## CO-B — Task 2's tests passing on arrival is correct and is not a defect

They are bounds on a mechanism Task 1 must already have built; their evidence is
the four mutations, **not** a red-first cycle. The plan said so and told the
implementer to STOP and report if any *failed*, because that would be a finding
about Task 1. **The controller deliberately did not pre-judge the finding to the
reviewer** — the same call `RX-B` records one spec earlier. **Cost if wrong:** a
reviewer flags them as asserting nothing; adjudicated then.

## CO-C — every mutation task proves `git diff --stat Sources/` is clean before committing

Task 2 mutates `Component.swift` four times and restores; Task 3 twice more.
**An unrestored mutation ships as production code and its own test is the thing
that goes green.** The cheap precondition goes in the dispatch rather than
relying on the expensive check. **Cost if wrong:** a mutated line ships, caught
by the review's diff read but only if noticed. Identical in substance to `RX-C`,
and re-stated rather than cited because a dispatch is not written from another
milestone's decisions doc.

## CO-D — `@Binding` may not exist, and the fallback is a `@State` write inside `content`'s getter

**Refined by measurement before Task 2 was dispatched rather than assumed**:
`@Binding` does **not** exist (see `CO-Z` for the name collision that makes the
error confusing). Task 2 took the plan's fallback — the `Counting` leaf
increments the component's own `@State` inside `content`'s getter — which is safe
**because `requestGroupLayout` materializes the getter exactly once per frame**
and nothing else evaluates it. **Cost if wrong:** the write order becomes
getter-evaluation order, which is deterministic here and would be a real hazard
in a component whose content is evaluated conditionally. Recorded so nobody
copies the idiom into production. This fallback is also why one of `CO-N`'s
mutations behaves the way it does — see there.

## CO-E — design spec §2's hedge is REPLACED by the measurement, not softened

**What §2 said.** That SwiftUI's layout transparency was "DERIVED from
documented behaviour and not measured here", on ruling `RX-P`'s footing, because
there is no SwiftUI test target in this repo.

**What was measured.** A throwaway probe outside the repo: a custom `Layout`
conformer recording `subviews.count`, hosted in an `NSHostingView` inside a
borderless `NSWindow` and forced through `layoutSubtreeIfNeeded()`. Repeated
`sizeThatFits` calls all agreed, so these are stable readings rather than
one-off samples.

| case | subview count |
|---|---|
| inline `A; B` — **the positive control** | 2 |
| `Group { A; B }` — SwiftUI's documented transparent container | 2 |
| `MyRow()`, whose body is two views | **2** |
| `MyRow(); MyRow()` | **4** |

A `Layout` conformer sees through a custom view exactly as it sees through
`Group`. **The fourth row is what makes it a measurement rather than an
anecdote**: it rules out the third being an artifact of having only one
instance.

**The ruling is that the hedge must be REPLACED, not merely softened.** The
paragraph was written as an honest hedge and it is now **false in the other
direction**. Leaving it after the measurement lands is the converse of `TB-AA`:
**a claim that understates its own evidence is as wrong as one that overstates
it.** §2 now carries the four counts and the technique.

**One site was NOT updated and this ruling did not reach it — recorded here
rather than quietly fixed, because it is this project's practices mechanism 1
firing inside the milestone that cites it.** `Sources/MetalUI/Component.swift`'s
type doc still reads *"That description of SwiftUI is DERIVED from its documented
behaviour and is not measured here: there is no SwiftUI test target in this
repo"*, and the sentence above it still says `.padding()` "introduces a layer …
by wrapping the view in `ModifiedContent`", which `CO-U` refuted. Both were
written at `d32b25c`, **before** either probe ran, and neither was walked back to
the line when the probes landed. The rule this violates is the one-sentence rule
that section states: **anything a measurement teaches must be walked back to the
mutated LINE in the same pass.** The correction belongs in `Sources/` and this
documentation task does not edit `Sources/`; it is reported instead.

**FIXED by the whole-branch fix wave, and the paragraph above is kept as the
record rather than deleted.** `Sources/MetalUI/Component.swift`'s type doc now
carries the measured account — the `subviews.count` readings (2 / 2 / 2 / 4) and
the 120x26 padding figure — with the refuted sentences quoted at the line so a
reader who has seen the old text knows which claim was replaced. **The fix wave
also found the SOURCE of the shipped comment, which this ruling did not name**:
the text lived in `docs/superpowers/plans/2026-09-03-component.md` (Task 1's
doc-comment block, `:265`/`:281` at the time) and was copied into `Sources/`
from there, so correcting only the shipped comment would have left the next
reader of the plan re-deriving it. Four plan sites were corrected, two of them
**forward-looking instructions** in Task 4 that would have had a future reader
reintroduce the refuted design ("State that modifiers wrap, and that a modified
component is layout-opaque"; "labelled as derived and not measured"). Those two
are the reason the plan was corrected rather than preserved the way the
reactivity plan's own false claim was: nothing cites these, and a live
instruction is not history.

**Cost if wrong:** none to the code — the design's footing goes from assumption
to evidence either way. The cost of the *unfixed site* is a reader of
`Component.swift` concluding the claim is unmeasured and either re-running the
probe or, worse, filing the divergence label §2 keeps available.

## CO-F — Task 1's second Important finding is carried to Task 2, not fixed in a Task 1 round, and Task 2 gains a test the plan lacked

Task 1's review found **three load-bearing lines reddening NOTHING on 795
tests**: `cursor += 1`, threading the outer cursor instead of `innerCursor`, and
`prepaintGroup` re-evaluating `content`. The "opaque to identity" half of the
design was entirely unguarded by that task, and so was `ComponentLayout.content`'s
whole reason to exist.

Task 2's brief already covered the two cursor mutations. It did **not** cover the
`content` re-evaluation: re-materializing in prepaint rebuilds structs whose
`@State` boxes are unbound, and no test in the plan reads state during prepaint.
Task 2 therefore gains `contentIsMaterializedExactlyOncePerFrame` — a counter in
the getter. **Cost if wrong:** the pin lands one task later; nothing ships
unguarded, since Task 2 is on this branch and the whole-branch review sees both.

## CO-G — Task 1's header comment must stop claiming the identity axis is pinned there

The reviewer's point is that **silence reads as coverage**, and a comment
*asserting* a property nothing can see is worse than no comment at all. The
header now says where the pin lives instead of implying it lives there. **Cost
if wrong:** none. This is taxonomy shape 4 from the comment side rather than the
test side.

## CO-H — `ComponentLayout.id` is DELETED, not tabled

Nothing read it: `Component`'s phases forward to `layout.content` and pass no
id. `SingleElementLayout.id` **is** read (`ElementGroup.swift`), which is why the
brief's model — copied from it — misled. Re-adding the field is one line if a
later task needs it, which is cheaper than a row in the declared-but-inert table
for a struct this new. **Cost if wrong:** a later task re-adds a field.

## CO-I — mutation 3's silence is a REAL coverage gap, not a dead line, and the mechanism is STABILITY rather than collision

**The mutation:** thread the outer `cursor` into the content instead of a fresh
`innerCursor`. **Task 2 measured it reddening NOTHING**, run twice plus two extra
probes.

**The plan's own comment said it would "silently collide their state", and that
is wrong.** Worked through and then confirmed by measurement: the content nests
under the **component's own id** regardless, so threading the outer cursor still
yields **unique** ids — `A = positional(0)`, A's content `= positional(1)` under
A, `B = positional(2)`, B's content `= positional(3)` under B. Uniqueness
survives. **What does not survive is STABILITY**: a component's content ids would
then depend on the outer sibling count, so **inserting a sibling before a NAMED
component resets its content's state** — defeating the entire point of naming it.
The existing reorder test could not see it because its state lives on the
component rather than in the content.

**Ruling: the silence buys one more test, not a shrug.**
`aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt` was added,
and **the derived mechanism was then CONFIRMED by measurement**: with it present
the mutation fails with **exactly one issue**, that test reading `1` where 2 was
expected, and nothing else reddens — on both filtered and full runs. **Cost if
wrong:** a comment claiming what breaks while nothing shows it, which is the
pattern this branch hit four times.

## CO-J — Task 3 continued in the main working directory rather than isolating into a worktree

Taken **after** the incident `CO-M` records, once the interfering agents were
stopped: isolating at that point cost a full rebuild for no remaining benefit.
**Cost if wrong:** if another stray lineage appeared, Task 3 would be clobbered
again — mitigated by instructing it to re-verify `git diff` before reapplying and
to **discard any measurement taken during the contended window**, which is `CO-K`.

## CO-K — any measurement taken while another process was live in the checkout is DISCARDED and re-taken

**A second process editing the same file makes a mutation result
unattributable, and an unattributable result is worse than none, because it
still looks like evidence.** Task 3 reported `Component.swift` being edited under
it — a `// MUTATION: re-evaluate content in prepaint` marker it did not write —
which clobbered its first edit attempt. It stopped and flagged rather than
fighting the file, which is why this cost one suite run rather than a wrong
number in the record. **Cost if wrong:** one extra suite run.

**And the converse fired in the same window, which is the half worth carrying.**
The controller saw a SourceKit diagnostic and briefly suspected the interference
had caused it. It had not: the brief's own code snippet contained an invalid
backslash-continuation in a string literal, and the implementer found and fixed
it. **Once a contended tree is known about, every unexplained symptom gets
attributed to it** — which is a second way to end up with an unattributable
record, from the opposite direction. Attribute by reproducing, not by proximity.

## CO-L — Task 2's fix round is HELD until Task 3 commits

Both corrections touch `ComponentTests.swift` and `Component.swift`, which Task
3 was editing. **Dispatching into a live edit is what caused this session's
clobbering already.** **Cost if wrong:** the corrections land one commit later.
Lifted the moment Task 3 committed `87891a3`.

## CO-M — mutation testing runs in an ISOLATED `git worktree` whenever another agent is live in the checkout

Adopted by Task 2's reviewer on its own after being interfered with, and
adjudicated as standing policy. It re-ran all four mutations at `f74688e` in an
isolated worktree; mutations 1, 3 and 4 reproduced **exactly** as documented,
which is a result that would have been worthless from a contended tree. Carried
into every future mutation dispatch. **Cost if wrong:** one worktree setup per
mutation task. **Generalised into the practices doc** as a record mechanism, with
its companion — that a subagent reporting it "accidentally launched" another
agent is reporting a **live process**, not a closed incident.

## CO-N — modifier composition is REQUIRED before merge, and the "reddens nothing" claim in the controller's own brief was a PREDICTION

**The requirement.** See `CO-X` for the defect and the fix. Shipping three
modifiers of which only one may be used is worse than shipping one: the API
reads as composable at every call site and fails at the second call, and the fix
is small and known. **Cost if wrong:** a slightly larger Task 3 diff and one more
review round, against an API surface that would have to be broken later.

**And the record finding this ruling is paired with, which is the controller's
own error.** Task 2's brief asserted that without
`contentIsMaterializedExactlyOncePerFrame` the `content` re-evaluation mutation
"reddens nothing", and the implementer wrote that prediction into a doc comment.
**Nobody had run it.** Measured, it reddens **9 issues across 5 of 11 tests**
(reviewer, at the 11-test file) and **10 issues across 6 tests** (implementer,
re-measured at the 14-test file). Both refute it. The cause is `CO-D`'s fallback:
the `@Binding` substitute puts `Counter`'s and `Quiet`'s own increment **inside
`content`'s getter**, so re-evaluating double-increments the state those tests
read. **The test is still worth keeping** — it is the cleanest isolated signal —
but its stated rationale was false, and the doc comment now says what was
measured. This is practices mechanism 5: *knowing a rule, quoting a rule, and
having a controller record a ruling about a rule are all weaker than running the
mutation* — here with the controller as the one who did not run it.

## CO-O — Task 3's fix round is HELD until Task 2's fix round commits

`CO-L` again, in the other direction and for the same reason: both edit
`Component.swift` and `ComponentTests.swift`. **Cost if wrong:** Task 3's fix
lands one commit later.

---

# The mutation table, as actually measured

**Re-taken as a whole at fix round 2 against the then-806-test file, not
patched at the flagged row** — which is practices mechanism 3, and it earned its
keep: **two of the four had moved and two had not**. Had only the one flagged
comment been corrected, two of the four would still be wrong today. The
distinction between "corrected" and "re-verified as unchanged" is recorded at
each line rather than left silent.

| # | mutation | result | moved since fix round 1? |
|---|---|---|---|
| 1 | delete the component's own `StateBinder.bind` | **9 issues across 5 tests**, every reading **0** | **moved** (was 5 / 4) |
| 2 | double-call the content path | **6 issues across 5 tests** | **moved** (was 5 / 4) |
| 3 | thread the outer cursor into the content | **1 issue / 1 test** | unchanged |
| 4 | drop `cursor += 1` | **4 issues / 2 tests** | unchanged |

**Mutation 1's readings are 0 and NOT the brief's predicted `[1, 1, 1]`**, and
the reason is a property of `@State` rather than of `Component`: an unbound
`@State`'s `nonmutating set` is guarded on `box.table`/`box.slotID`, so writes
are **discarded outright** rather than merely not persisted
(`anUnboundStateReturnsItsInitialValueAndDiscardsWrites`, `StateTests.swift`).
The reviewer verified that against `State.swift`'s setter rather than taking it.

**Mutations 3 and 4 redden DIFFERENT sets, which is the load-bearing part.**
The design spec required that if one mutation reddened both assertions, one of
the two would be proving less than it claims. It does not: dropping `cursor += 1`
is what actually **collides** siblings — `twoSiblingComponentsHoldIndependentState`
reads **6/6**, both writes landing in one entry, and the *unnamed* half of the
reorder test reads **4/4**, the same collision one level deeper — while sharing
the counter with the content collides nothing and destroys **stability** instead
(`CO-I`). The **named** half of the reorder test stays green under mutation 4, as
expected: a name replaces a position rather than depending on `cursor`'s value at
all.

**Task 3's two mutations, and both discriminate.** Wrap-rather-than-distribute
fails **all three** assertions of
`aModifierOnAComponentDistributesToEachTopLevelChild` — node count 4 against 3,
and **both** leaf widths 0.0 against 8.0, which is exactly why the design spec
required rects to be asserted and not only the node count. Minting an identity
level inside `StyledComponent` fails
`addingAModifierDoesNotResetAComponentsState` — count **1, not 3**. The chained
composition mutation and its honest negative are in `CO-X`.

---

# What this milestone did not measure, stated so nobody cites it as though it had

- **Whether `Component` is pleasant to write.** The whole point of the type is
  ergonomics and no assertion reaches it. There is **no production caller**
  (`CO-Y`), so there is not even weak evidence.
- **Whether SwiftUI still behaves as `CO-E` and `CO-U` measured.** Both probes
  are throwaway and deliberately uncommitted, so nothing in the suite re-checks
  them and a future SwiftUI change would go unnoticed here. That is the same
  standing as every WebKit oracle claim this project makes between corpus
  regenerations, and the divergence label stays available.
- **Anything about a rendered window.** No human has run this build, and no
  `renderOffscreen` readback was taken. `Component` contributes no layout node,
  so a regression in transparency moves rects and *is* visible to the suite —
  unlike `Stack`'s z-order or `Deferred`'s hoist, this milestone has no
  paint-order property that hides from assertions.
