# Stack — decisions taken during execution

Rulings from the milestone that gave the framework its third container, `Stack` — a
layering container that sizes to the max over its children on each axis and places
every child by a nine-case `Alignment`, rather than sequencing them along a main axis.
Prefixed **`ST-`** and **lettered** (`ST-A`, `ST-B`, …) per this repo's convention for
`CL-`/`CS-`/`SI-`/`TX-` — a bare `ST-3` is a typo, not a citation. Read alongside
`docs/superpowers/specs/2026-08-28-stack-container-design.md` (the design this
milestone built) and CLAUDE.md's declared-but-inert table, which this milestone touches
without adding a row to.

## ST-A — SwiftUI's centre default, not CSS grid's stretch, and every fixture pays for it

**The choice.** `Stack`'s default `alignment` is `.center` — SwiftUI's `ZStack` answer.
A CSS one-cell grid (`display: grid; grid-template-columns: 1fr; grid-template-rows:
1fr`, one child per cell via `grid-area: 1 / 1`) defaults to `stretch` on both axes:
an unsized item fills the cell. Ruling EP-5 already took SwiftUI's answer over CSS's
where the two differ for `Column`/`Row` (ruling EP-8); `Stack` extends the same call to
the third container rather than reopening it.

**What it costs, precisely.** The oracle for this milestone's browser fixtures is CSS
grid, and grid's *default* is not this framework's default. Every fixture in
`StackFixtureTests.swift` therefore states `justify-items` and `align-items`
**explicitly** in its HTML — none relies on the grid default — because a fixture that
omitted them would pin grid's `stretch`, not this engine's `.center`, and every
comparison would silently test the wrong thing. This is a standing tax on every future
`Stack` fixture, not a one-time cost: the day someone adds a ninth fixture without both
properties spelled out, it stops testing what it claims to.

**Why not follow the oracle's default instead.** SwiftUI is this framework's design
authority (`CLAUDE.local.md`'s remembered preference, and EP-5's own text) precisely
because CSS is the *substrate* this engine's algorithm is checked against, not the
*API* callers write against. `Column`/`Row`/`Box` already give three data points where
CSS's flex defaults were rejected in favour of SwiftUI's stack-view defaults
(`Column`/`Row` centre, `Box` stretches, matching CSS's flex-item default exactly
because `Box` **is** the escape hatch into raw flex, per EP-8's own framing). `Stack`
centring by default is the same call for the same reason: it is the API SwiftUI-minded
callers expect, and the oracle's role is to check the *mechanism* (max-over-children
sizing, nine-position placement, the stretch-only-for-auto rule) rather than to dictate
the *default*.

## ST-B — `StackItem` is its own type, not a reused `FlexItem`

`FlexItem` (`FlexEngine.swift`) carries `baseSize`, `hypotheticalMainSize`, `minMain`,
`maxMain`, `targetMainSize`, `frozen` — §9.2–§9.7's freeze-loop state, one field per
step of an algorithm a stack never runs. `StackItem` is two fields: `node` and `size`.

**Why not reuse `FlexItem` with the unused fields left at some default.** A stack has
no main axis, so every one of those six fields would be meaningless on every
`StackItem` — not merely unused on this or that fixture, unused on all of them,
always. Reusing the type would need an unwritten convention ("width goes in
`targetMainSize` because that's where `positionItems` expects a size") that reads as
flex semantics to anyone who did not write it, and would leave six fields on every
stack item that a reader has to know to ignore. `ContainerLayout` (the struct both
paths share) keeps `lines: [FlexLine]` and `stackItems: [StackItem]` as two separate,
independently-empty fields for the same reason: each is honest about what it holds,
and a stack's `lines` being empty by construction is simpler to reason about than one
field carrying two incompatible meanings depending on `Display`.

**What it costs.** Two small structs instead of one, and `layOutStack`/
`positionStackItems` duplicate the "resolve a node's own declared size" logic
`collectItems`/`resolveNodeSize` already have for the flex path, rather than sharing
it through a common item type. That duplication was accepted rather than factored out
in this milestone — the two resolution sites are a handful of lines each, and forcing
them through one shared helper would have coupled the stack path's sizing to the flex
path's more tightly than the two algorithms' actual relationship (they share nothing
past §9.2's basic "resolve `Style.size` against a basis") warrants.

## ST-C — `positionStackItems` is its own function, not a branch inside `positionItems`

`positionItems` (`FlexEngine.swift`) implements §9.4's gap arithmetic, the
`wrap-reverse` cross-axis flip (`crossAxisOffset`), and §9.4.2's flex-relative
start/end mapping (which edge is "start" depends on `flexDirection` and its
`Reverse` variants) — none of which a stack has: a stack does not read
`flexDirection` at all, so there is no axis to flip and no direction-relative start
edge to resolve. `positionStackItems` reads `alignItems` as the block (vertical) axis
and `justifyItems` as the inline (horizontal) one, unconditionally, because with no
main axis there is no axis-relative indirection to apply.

**Why not thread a "there is no main axis" flag through `positionItems` instead.**
That flag would have to suppress the gap arithmetic, bypass the reverse flip, and
skip the flex-relative axis mapping — three of `positionItems`' four responsibilities
disabled by one boolean, leaving a function that is mostly dead code on the stack
path and reads as flex-item positioning to anyone who has not traced which branches
the flag disables. A short, separate function that does the actual nine-case switch
directly — two small `switch` statements over `alignItems`/`justifyItems`, a stretch
check, and a `setLayout`/`placeNode` call per item — is more legible than a shared
one with an escape hatch through most of its body.

**The line this drew, checked by a mutation the plan did not anticipate.** Task 3's
axis-swap mutation — bind `y` from `horizontal` (`justifyItems`) and `x` from
`vertical` (`alignItems`), the literal cross-wire the two-type design (`AlignItems`
vs `JustifyItems`, ST-G below) makes impossible to write as a field swap — reddened
exactly `allNineAlignmentsPlaceTheChildAtNineDistinctPositions` (7 issues: 6 position
mismatches plus the `seen.count == 9` distinctness check) and nothing else. No test
outside `positionStackItems`' own fixture noticed, confirming the function's isolation
from the flex path is real and not just structural.

## ST-D — `justifyItems` lives on `Style`, not on a dedicated `Alignment` type, and it is not inert

**The choice.** `Style` gained `public var justifyItems: JustifyItems? = nil`
alongside the pre-existing `alignItems: AlignItems?` — CSS's own split between
`align-items` (block axis) and `justify-items` (inline axis) — rather than a single
`Alignment`-shaped field living somewhere else and being translated at the point of
use.

**Why not keep it off `Style` entirely, given it does nothing for a flex container.**
The public `Stack` element (`Sources/MetalUI/Stack.swift`) is itself just a `Style`
with `display = .stack`, `alignItems`/`justifyItems` set once in `init` — "a `Stack`
differs from a `Box` only in the `Style` it builds," per that file's own doc comment.
Putting `justifyItems` anywhere other than `Style` would have meant `Stack` could not
be *only* a `Style`, and every phase method (`requestLayout`/`prepaint`/`paint`) would
have needed its own copy instead of reusing `Box`'s verbatim, which is the whole
economy this milestone's Task 5 banked on (`Stack.swift`'s doc comment: "The three
phase methods below are `Box`'s, unchanged").

**Why this is not a declared-but-inert table row, and CLAUDE.md's own text says so
now.** The table exists for properties **read by no production code**. `justifyItems`
has one: `positionStackItems` reads `tree.style(container).justifyItems` on every
stack container laid out. Its being inert *for a flex container* is not a gap this
engine has — `justify-items` has no effect on a CSS flex container either, so a flex
container ignoring it is the model working as specified, the same as `flexGrow`
having no effect inside a stack (`Display.stack`'s own doc comment names this
explicitly: "It reads neither `flexDirection` nor any flex property on its
children"). Declaring a property inert-in-one-context and live-in-another is not new
here — `Style.padding`/`.border`/`.margin` on a leaf are exactly that shape, and they
stay in the table because a `Text` genuinely never reads them. `justifyItems` is
different in kind: there is no context where a production code path *should* read it
and does not.

## ST-E — an unresolvable percentage stack child is CONTENT-MEASURED, like a literal `auto` (corrected: the original ruling asserted this and the engine did not do it)

**The question.** A stack child's percentage size looks circular: resolving
`width: 50%` needs the container's width, and the container's width (during the
intrinsic sizing pass) is derived from its children — including this one.

**What was measured**, against a flex row holding a `width: 50%, height: 20px`
childless child beside a fixed `80×30` sibling:

```
Intrinsic pass  (available: .maxContent x .maxContent, containingBlockWidth: nil):
  measured: SizeD(width: 80.0, height: 30.0)

Placement pass  (available: .definite(200) x .definite(100)):
  container:   200 x 100 @ (0, 0)
  pct child:   100 x  20 @ (0, 0)
  fixed child:  80 x  30 @ (100, 0)
```

During the intrinsic pass, `containingBlockWidth` is `nil`, so the percentage does
not resolve at all; the child falls back to `Dimension.auto`, which for a childless
box measures 0 — the same fact CLAUDE.md already records for `Box` under ruling EP-8
("a childless `Box` measures 0"). The container's indefinite-pass size is therefore
the fixed child alone (`80×30`), matching exactly. Once the container has a *definite*
width from its own caller (`200`, supplied by the placement pass, not derived from the
children), the percentage resolves against it the ordinary way: `50% of 200 = 100`.

**The general mechanism, stated precisely because "contributes zero" and "contributes
its `auto` size" happened to coincide here only by the fixture's own construction.**
An unresolved percentage does not have a special "counts as zero" rule; it becomes
`Dimension.auto` and then goes through ordinary content sizing of that box, exactly
like a literal `auto`. For an empty box that content size is 0 — this probe's case.
A percentage child **with content** contributes that content's own auto
(max-content) size during the intrinsic pass instead.

### The two paragraphs that stood here were WRONG, and this is the error record

**What they claimed.** That `layOutStack`'s `resolvedAxis` "implements exactly this",
and — in the paragraph above, as originally written — that a percentage child with
content "would contribute that content's own auto (min/max-content) size during the
intrinsic pass". Both sentences asserted an *engine* behaviour. Neither was ever run
against the engine: the probe they generalised from measured an **empty** percentage
child, for which "contributes zero" and "contributes its content size" are the same
number (0) and therefore indistinguishable. The ruling then closed with "No fixture
in this corpus exercises a percentage stack child with non-empty content — a gap
worth knowing rather than a defect", which is a prediction about measurement dressed
as a fact about the code (the practices doc's taxonomy shape 10) and told the next
reader not to look.

**What falsified it.** The milestone's final review ran the shape through this repo's
own `LayoutOracle` and through `computeLayout` side by side — an auto-sized stack
holding a `width: 50%` child that itself contains an `80×30` box, plus a fixed
`40×20` sibling:

```
              stack        pct child
engine       40 x 30        20 x 30
WebKit       80 x 30        40 x 30
```

`resolvedAxis` returned `clamp(0, …)` for the unresolvable percentage — **non-`nil`**,
so `measureNode` never ran for that axis and the child contributed 0. The stack then
sized to its fixed sibling alone, and `50%` of that narrowed stack gave the child 20.
The flex path did **not** have this bug: the identical tree as a flex row measures 120
in both engines.

**What was done about it.** The engine was fixed rather than the divergence recorded,
for three reasons: the stack path was new and unshipped, so nothing depended on the
old answer; `Box().width(percent:)` is a live public modifier, so the shape is
reachable from the public API; and this project's standing rule is that the WebKit
corpus is the oracle for the engine. `resolvedAxis` now returns `nil` — the
"this axis needs measuring" signal — for a percentage that fails to resolve, exactly
as it already did for a literal `auto`. All five boxes then match WebKit exactly.

**And the gap the ruling declared "worth knowing rather than a defect" is closed by a
fixture**, `stack_percent_child_with_content.html` /
`stackPercentChildWithContentMatchesWebKit`, generated against live WebKit and
matching the fixed engine on first generation. Reverting the one-line fix reddens
exactly that test and nothing else in the 538-test suite.

**The transferable part.** A probe whose input cannot distinguish two candidate rules
has not chosen between them, however precisely its output is recorded — and writing
the un-chosen answer down as settled is what makes it survive six tasks. The
discriminating input here cost one nested `<div>`.

## ST-F — `.stretch` fills an axis only when the item's own size is `auto`, and the oracle found the bug tests did not

**What CSS Box Alignment actually says**, measured directly against `LayoutOracle`
rather than assumed: a `20×10` child under `justify-items: stretch; align-items:
stretch` measures **20×10 at (0, 0)** — its own declared size, placed at the start
edge — not `300×200` (the full cell). `stretch` only fills an item whose size on that
axis is `auto`; a declared size, including a percentage (which is not `auto` either),
opts an item out and it falls back to `start`.

**What this engine built first, and why the first version was wrong.** Task 3's
`positionStackItems` — written from the plan's description of `stretch` as "fills the
container" — applied it **unconditionally**: any item under a `stretch` container had
its size overridden to the container's size regardless of its own declared size. Task
3's own unit test, `stretchFillsTheContainerOnThatAxis`, asserted exactly this on a
**declared** `20×10` child stretching to `100×60` — a test written from the same
misunderstanding as the implementation it was checking, so it passed, and 517 tests
green gave no signal anything was wrong.

**How it was found, and why this is the argument for the oracle rather than for more
unit tests.** Task 4 wrote `stack_stretch.html` against the literal brief ("same
geometry" as the other alignment fixtures — a `20×10` child) and, per this project's
standing practice of probing the oracle before committing a fixture, ran that geometry
against `LayoutOracle` first rather than trusting the plan's prediction:

```
EXPLICIT SIZE CHILD RESULT: child x=0 y=0 w=20 h=10   (WebKit: stretch → start fallback)
AUTO SIZE CHILD RESULT:     child x=0 y=0 w=300 h=200  (WebKit: stretch → fills cell)
```

WebKit disagreed with what the engine (and the engine's own test) claimed `stretch`
does. **No unit test in this repo could have found this**, because the unit test and
the implementation shared one author's understanding of `stretch` and therefore shared
one blind spot — the exact failure mode this project's own practices doc names as the
argument for an external oracle: tests written by the same author as the code verify
the code against that author's beliefs, not against the specification. Only a
browser, which was not consulted while either was written, could disagree with both at
once.

**The fix and its verification.** `positionStackItems` now stretches an axis only when
`tree.style(item.node).size` on that axis is `.auto`, read directly rather than
threaded through `StackItem` (matching how every other per-item style read in
`FlexEngine.swift` reaches it). A sixth fixture, `stack_stretch_declared_size.html`,
pins the declared-size branch against WebKit's measured `20×10 @ (0,0)`. Reverting the
guard to unconditional stretch reddened exactly two tests —
`stackStretchDeclaredSizeMatchesWebKit` and the new unit-test sibling
`stretchDoesNotOverrideADeclaredChildSize` — while `stackStretchMatchesWebKit` and
`stretchFillsTheContainerOnThatAxis` (corrected to use an **unsized** child, since an
unsized child is the branch it always claimed to cover) stayed green throughout,
confirming the two branches are independently covered rather than one masking the
other. `JustifyItems`'s doc comment (`Style.swift`) and `positionStackItems`' own
stretch branch both now name the rule and cite the measured numbers, so a future
"simplification" back to unconditional stretch has to delete an explanation, not just
two `&&` clauses.

## ST-G — `AlignItems` and `JustifyItems` being distinct types makes axis confusion unrepresentable, not merely tested

**The precise claim.** `AlignItems` (`flexStart, flexEnd, center, baseline, stretch`)
and `JustifyItems` (`start, center, end, stretch`) are two different `enum`s sharing
only `.center` and `.stretch` by case name. Binding the vertical (block) axis to
`justifyItems` and the horizontal (inline) axis to `alignItems` — the literal
field-level swap — **does not compile**: `positionStackItems`'s `vertical` switch
would need to handle `.flexStart`/`.flexEnd`/`.baseline`, which `JustifyItems` has no
cases for. Value-level axis confusion of that specific shape is unrepresentable by the
type system, not merely absent from the test suite — a stronger guarantee than any
`@Test` can offer, because it holds for every future caller without needing a test to
exercise them.

**What is NOT unrepresentable, and this is the distinction to keep straight.** A
different, still-representable bug exists one level up: `positionStackItems` reading
the **same variable twice** — computing both axes from `horizontal` (`justifyItems`),
silently leaving `alignItems` unread — compiles cleanly, because both switches would
then be over the same `JustifyItems` value. This is a wrong-variable-at-use-site bug,
not a wrong-type-at-declaration one, and it is exactly what Task 3's mutation actually
tested (the compiler rejected the literal field swap, so the mutation applied was
"drive `y` from `horizontal` instead of `vertical`" — a variable substitution, not a
type substitution). That mutation reddened 7 assertions, all in
`allNineAlignmentsPlaceTheChildAtNineDistinctPositions`.

**So the fixture's asymmetry (three distinct alignments producing three distinct
positions from identical geometry) still earns its place** — it is the thing catching
the representable bug — **but for a different bug than a first read of the two-type
design suggests.** Do not write "the fixture guards the axis swap": the fixture guards
against reading the wrong axis's *value*; the type system alone guards against binding
the wrong axis's *type*, and no fixture is needed for that half at all.
