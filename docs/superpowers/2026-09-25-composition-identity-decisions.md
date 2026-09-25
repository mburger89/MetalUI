# Composition and identity decisions (plan task 8)

Rulings for [`specs/2026-09-25-composition-identity-design.md`](specs/2026-09-25-composition-identity-design.md),
on `feat/composition-identity` from `e3cb3e9`. Ids are **lettered**,
`ID-A`…`ID-N`; next unused is **`ID-O`**. A bare `ID-3` is a typo, not a
citation. **A round that appends a ruling moves this line in the same commit.**

**Status, 2026-09-25: designed; no lane has run.** Baseline measured in this
worktree at `e3cb3e9`: `swift build --build-system native --build-tests`, then
`swift test --build-system native --no-parallel` → `Test run with 1444 tests in
3 suites passed after 81.223 seconds`, the guards ran (`FR-J no-argument frame:
succeeded=true`). Measurements in `docs/record/55-composition-identity.md`
(record §55); the audit table is its §3.

**Evidence, cited below by arm id:**

- `docs/probes/swiftui-composition-identity.swift` (**new**, this design): arms
  A0/A1 (controls), V1–V10 (conditional content), X1–X8 (explicit identity),
  S0–S6 (one value placed twice, erasure; S5/S6 added by the critic round,
  `ID-M`), G1–G7 (modifiers on a `Group`, state), L0–L10 (modifiers on a
  `Group`, layout; L8–L10 added by the critic round). Script form and compiled
  form byte-identical, exit 0, stderr empty, macOS 27.0 (26A428), Apple Swift
  6.4. Output in its header; revision 2 re-ran every earlier arm byte-identical.
- `docs/probes/swiftui-modifier-identity.swift` (MC-A/MC-C/MC-E's; arms C,
  D1, D2, E, F cited). **Re-run by the critic round** (`ID-M`) in both forms:
  byte-identical to each other, exit 0, stderr empty, every output line present
  in its recorded header.
- `docs/probes/swiftui-component-distribution.swift` (OM-D/OM-E/OM-F's G0–G16;
  cited for the `Component` rows it already settles). **Re-run by the critic
  round** the same way, with the same result.
- Eight scratch measurements of MetalUI (one throwaway test file), run and deleted (record §55
  §2): the current answers for an appearing `if`, an `if` true/false/true, an
  if/else flipped back, a shrinking `for` loop, `@State` inside `AnyElement`, a
  `.frame` on a two-member `Component` in a `Column`, a `.frame` over an empty
  `Component`, and an if/else inside an `HStack` (does not compile). One scratch
  implementation of `ID-B` (both group copies), run against the whole suite:
  **13 tests reddened, all named in record §55 §2.3** and in the spec's lane 2
  table.

---

## ID-A — scope: the audit, what this task fixes, and three lanes

**Ruling.** Every item addressed to plan task 8 (collected by grep over
`docs/record/` and the decisions docs, record §55 §1) and every concept the task
names is disposed of in record §55 §3's table as one of: **matches and pinned**,
**fixed to SwiftUI's answer** (EP-5), or **kept as a numbered, pinned
divergence with a reason**. This task fixes:

1. an `if` with no `else` and a `for` loop each take **one** structural slot
   (`ID-B`);
2. content an evaluated conditional removes is **reset** (`ID-C`);
3. `if`/`else` (and `switch`) inside proposal containers (`ID-D`);
4. `@State`/`@Environment` inside `AnyElement` (`ID-E`);
5. a handler run by input dispatch reads and writes **its own occurrence's**
   state when one element value is placed twice (`ID-F`);
6. `.id(_:)` on every element group — proposal elements, `Component`, `Grid`,
   `GridRow` (`ID-G`);
7. a legacy `.background(alignment:content:)` (`ID-J`).

It keeps, with reasons: duplicate sibling names sharing one identity (`ID-H`);
modifiers on multi-member content staying one layer (`ID-I`); divergence 20
(`ID-K`). Three lanes, disjoint files, run in order 1 → 2 → 3 (spec §5).

**Reasoning.** EP-5 and the project's standing rule (SwiftUI is the design
authority, identity included) make SwiftUI's answer the default wherever the
fix does not break the modifier model (`MC-A`: one layer = one node = one
identity level). Every fix above is a local change to a group type, a binder or
a dispatch site; none touches layout, paint, hit ranking or the retention slots.
The kept items are the ones whose SwiftUI answer needs a layer to become several
identities.

**Cost if wrong.** A fix that should have been a kept divergence moves id paths
for nothing; each fix is therefore ruled with its migration note and its pins.

---

## ID-B — an `if` without `else` and a `for` loop each take ONE structural slot

**Ruling.** `OptionalGroup` and `ArrayGroup` — **both copies**, the untyped
`requestGroupLayout` in `ElementGroup.swift` and the typed
`requestProposalGroupLayout` in `ProposalElementGroup.swift` — reserve exactly
one cursor index whether or not they produce content, and number their content
from 0 under a slot id `.positional(index)` of their own, as `EitherGroup`'s
taken branch already does (`SI-F`). A `for` loop's iterations thread one inner
cursor across all members under that slot, so a named member still replaces its
position **within the loop** (`reorderingANamedListCarriesEachItemsState`'s rule,
the `ForEach` analogue). **`SI-G` is reversed**: an element after a vanishing
`if` no longer adopts the vanished element's state; naming the trailing sibling
is no longer a remedy anything needs. Divergence **69** retires (a vanishing
grid cell or row hands its state to nothing).

**Evidence.** Probe V1 (`t` keeps its own serial when `c` vanishes; it neither
adopts `c`'s nor resets), V2 (appearing), V3 (a two-member `if`), V6 (`ForEach`
shrinking: the trailing sibling keeps its state), V7/V8 (inside a `GridRow`, a
whole `GridRow`), G7 (a modified `Group` after a vanishing `if`). MetalUI today:
`anElementAfterAVanishingIfAdoptsTheVanishedElementsState` (reads 2 — adoption),
scratch V2 (the appearing content reads the trailing element's 2, the trailing
element resets to 1), scratch V6 (the trailing element reads the vanished
iteration's 2), `removingACellFromARowHandsItsStateToTheNextCell`,
`removingAWholeGridRowHandsItsStateToTheNextRow`. **`SI-G`'s "why shifting is
right at all" was a claim about SwiftUI that no probe ever ran** ("beyond
'SwiftUI does it'"); V1 refutes it. Its other reason — a reserved slot makes the
index space depend on branch width, which is unbounded — does not hold for this
spelling: the slot is **one** index and the content numbers inside it, the
shape `SI-F` already ships for `EitherGroup`.

**Migration note (user-visible).** Every element inside an `if` with no `else`,
or inside a `for` loop, moves one identity level deeper, and every element after
one keeps a fixed index. At run time: nothing is persisted across launches, so
the change is visible only as behaviour — a trailing sibling no longer inherits
a vanished element's `@State`, scroll offset, hover, `$anim` baseline, focus
retention or accessibility node, and a press held across a vanishing `if` no
longer clicks the sibling that used to slide into its place. Code that computed
a `GlobalElementID` through an `if` or a `for` by hand (tests, a
`Window.focus(_:)` target built from a literal path) must add the slot level.
`.id()` must still be the outermost modifier; naming the trailing sibling past
an `if` still works and is no longer needed.

**Cost if wrong.** If SwiftUI shifted after all, every app written against the
new rule would see trailing state survive where SwiftUI's resets — but V1's
separating value (the trailing view's own serial printed beside the vanished
one's) makes that reading impossible on this toolchain. The measured cost is 13
tests' literals and names (spec lane 2), one extra `GlobalElementID` allocation
per `if` and per `for` per frame (the scratch implementation left every
allocation pin green), and the demo's `List` keeping one index across the modal
toggle (pixels expected at 0 px, spec §6; the demo's `if` comment is rewritten).

---

## ID-C — content an evaluated conditional removes is reset

**Ruling.** When an `OptionalGroup` is evaluated with no content, or an
`EitherGroup` evaluates one branch, and the absent slot (the `if`'s slot, or the
untaken branch's id) **was produced on the previous frame**, every `StateTable`
entry whose id descends from that slot is deleted — **except** entries whose own
path component is `.named("$focus")` or `.named("$ax")`, the window-owned
retention slots (`TB-J`, `AB-U`). "Produced on the previous frame" is a
per-frame set of taken slot ids the table keeps and swaps in `sweep()`; the scan
runs only on that transition. Content that returns afterwards starts fresh.
Divergence **18** retires for conditionals. Two retentions stay, by design:

- an element a `for` loop stops producing keeps its state (and hands it back if
  the loop grows again) — **divergence 74**, owner plan task 10 (`ForEach`);
- a conditional that is **not evaluated** (inside a `List` row out of the
  window) is not reset: `TB-AH`'s bounded retention is `List` windowing's and is
  untouched.

**Evidence.** Probe V5 (`if` true → false → true: new serial), V9 (if/else away
and back: new serial), V10 (a removed `ForEach` element: new serial — the
residual). MetalUI today: scratch V5 (retained, reads 2), scratch V4 (flipped
back, reads 2); divergence 18 ("Element-level consequence is unpinned").

**Reasoning.** SwiftUI ties a view's state to the view's lifetime; MetalUI's
table ties it to the key, and `sweep()`'s tombstones exist for `List` windowing
(`TB-AE`), where the element is not produced but has not been removed. An
evaluated conditional is the one place the framework *knows* the content was
removed rather than windowed, so that is where the reset goes — a sweep-time
reset of every slot not noted this frame would purge a windowed row too (the
spec's mutation M2h pins exactly that). `$focus` and `$ax` are exempt because
their lifetime is the window's (focus retention through `staleAfterGenerations`,
the accessibility node's republish), which `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`
and the accessibility suites pin and this task must not move.

**Migration note.** A conditional that toggles no longer brings back its old
`@State`, scroll offset, text selection or `$anim` baseline; a returning
element's first frame snaps rather than animating from where it left off (an
insertion is SwiftUI's transition, not an animation). Keep a value that must
survive a toggle in data or above the `if`. **`TextField` and `TextEditor` are
named here because they are on the must-not-move list** (`ID-M` item 4): their
`TextEditState` (selection, marked text, horizontal scroll) lives in the table
under the field's own id, so a field inside an `if` that goes false and returns
comes back with a fresh `TextEditState()` (caret at 0, no composition, scroll
0) — while `$focus` is exempt, so a focused field keeps focus through the
excursion. Pinned by lane 2's C2.12.

**Cost if wrong.** A wrong exemption list moves focus or accessibility (both
pinned; lane 2 runs their suites unfiltered). A missed transition leaves the old
retention in place (C2.6/C2.7 redden). An over-eager scan costs O(table) per
frame per false `if` (C2.9's work counter).

---

## ID-D — `if`/`else` inside proposal containers

**Ruling.** `extension EitherGroup: ProposalElementGroup where First:
ProposalElementGroup, Second: ProposalElementGroup`, its typed entry numbering
exactly as the untyped one (`cursor += 2`, the taken branch under
`.positional(branchIndex)` or `.positional(branchIndex + 1)`, `SI-F`), and
`ID-C`'s reset. So `HStack { if a { … } else { … } }`, a `switch` (nested
`EitherGroup`s) and the same inside `VStack`, `ZStack`, `Grid`, `GridRow` and
every typed modifier's content compile.

**Evidence.** Scratch: `HStack { if flag { Rectangle(…) } else { Rectangle(…) } }`
fails with `generic struct 'HStack' requires that 'EitherGroup<Rectangle,
Rectangle>' conform to 'ProposalElementGroup'`. The modifier-composition doc
carried "`EitherGroup: ProposalElementGroup` (record §09 boundary 4) → tasks
6/8"; task 6 did not take it. Probe V4/V9 for the identity it must have.

**Cost if wrong.** A typed copy that drifts from the untyped one (the pattern
`MC-H` and "a copy of a pinned implementation is unpinned" warn about): C2.11
mutates the typed copy on its own.

---

## ID-E — `@State` and `@Environment` inside `AnyElement` bind

**Ruling.** `AnyElementBox` binds its concrete element with
`StateBinder.bind(element, in: pass.frame, id:)` before `requestLayout`,
`prepaint` and `paint` — "reflection inside `AnyElementBox` itself", the option
record §05's inert row named. The declared-but-inert row "`@State` inside an
`AnyElement`" is deleted, `EV-M`'s carried item closes, and
`anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault` becomes a pin
of the bound value (renamed; retirement row).

**Evidence.** Probe S2 (`Counter` inside `AnyView` counts 0 → 1) and S3 (state
kept across an update through `AnyView` of the same type). Scratch: after three
frames the erased counter's slot is `nil`, the plain one's `3`.

**Reasoning.** `AnyElementBox<E>` is generic over the concrete element, so the
`Mirror` the old comment said was missing is available one level down. Binding
in all three phases mirrors `Element`'s group defaults (a value placed twice
reads its own occurrence in each phase, `oneElementValuePlacedTwiceDoesNotShareItsState`'s
rule).

**Cost if wrong.** Nothing in production builds an `AnyElement` (the builder
never produces one), so the blast radius is the tests that do; the two new pins
redden under separate mutations (layout bind, phase re-bind).

---

## ID-F — one value placed twice: dispatch resolves the occurrence

**Ruling.** A `State.Box` (and an `Environment.Box`) bound to more than one
slot in one generation remembers every slot it was bound to (an optional array,
`nil` in the common case). Input dispatch records the id it is dispatching to —
`Window`'s click, `dispatchKey`'s chain entry, `dispatchAction`'s target, the
accessibility press and adjust, and a text field's edit callback — in an
internal `StateDispatch.owner` for the duration of the handler. While an owner is
set, an aliased box reads and writes the slot whose element id is the owner **or
an ancestor of it** (a `Component`'s state written by a `Box` inside its body).
Divergence **19** retires. Its residual — a closure that runs **outside** input
dispatch (a timer, a task, a direct call) still reaches the last-bound
occurrence — is **divergence 71**, pinned by the existing
`aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt` (renamed by lane 2; it
invokes the closure directly, which is exactly that path).

**Evidence.** Probe S1 (one `Counter` value placed twice: reads 0, 0, 1, 1 —
separate storage; shared would read a 2) and S4 (two serials). **Divergence
71's SwiftUI half is probe S5** (critic round, `ID-M` item 2): closures
capturing one value's `@State`, stored from `.onAppear` and called directly
afterwards — outside any SwiftUI dispatch — each write their **own**
occurrence (`call 0: x 1, call 1: x 1`; last-bound would read 2 on call 1),
S6 its two-value control. MetalUI today:
`aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt` (occurrence 0 clicked
once reads 1, occurrence 1 reads 102). `StateTable.aliasedStateBoxes` still
counts the shape.

**Reasoning.** `State.swift`'s own note says a per-copy slot needs a change to
how `@State` binds, because `Mirror` cannot write the struct. Dispatch-time
resolution needs no write: the box already knows every slot it served this
generation, and dispatch already knows which element it is serving. Ancestor
matching is sound because a closure captures state from its lexical scope, which
is always the registering element or one enclosing it.

**Cost if wrong.** A missed dispatch site leaves that path on divergence 71's
answer (one test per site redden under its own mutation, M1b–M1f, M1i). The
common case allocates nothing (the array stays `nil`), so the freeze-loop
allocation pins are not at risk.

---

## ID-G — `.id(_:)` on every element group

**Ruling.** A new `IdentifiedGroup<Content: ElementGroup>: ElementGroup`
(`ExplicitIdentity.swift`) and `extension ElementGroup { func id(_ name:
String) -> IdentifiedGroup<Self> }`, with `IdentifiedGroup: ProposalElementGroup
where Content: ProposalElementGroup`. It consumes **one** cursor index, named
`.named(ElementID(name))` (a name replaces a position, `PathComponent`'s rule),
numbers its content from 0 under that id, contributes its content's nodes
unchanged (layout-transparent), and forwards `prepaint`/`paint`. Every
`StyledElement`'s existing `id(_:) -> Self` is untouched and still wins for those
types (more specific), so `Box().id("x")` and a legacy modifier chain's `.id`
keep their paths. `Component` gains `.id()` this way; `var elementID` stays.

**Evidence.** Probe X4 (`.id(generation)` on an `HStack` resets its child), X5
(on a `Grid`), X6 (on a `Group`), X7 (an `.id` inside a `.padding` still
resets). The grid record: "no built-in proposal element has `.id()`, so the
documented remedy cannot be spelled until task 8"; the modifier-composition
carried table sent "proposal `.id()`" to task 12 — this ruling takes it, because
identity is this task's subject; focus and accessibility on proposal elements
stay task 12's.

**Reasoning.** SwiftUI's `.id` is how a caller asks for a reset; after `ID-B`
it is no longer needed for stability past an `if`, but it is still the only
spelling of "start over", and the `ForEach` analogue (a named item in a `for`
loop) needs it on proposal content. A wrapper with its own level is the only
spelling that works over multi-node content and over types with no stored name.

**Cost if wrong.** An overload collision with `StyledElement.id` (guard G3.1),
or a proposal container refusing the wrapper (guard G3.2). `.id` on a proposal
element adds one identity level where the legacy `.id` replaces one — recorded,
because a path built by hand differs between the two spellings.

---

## ID-H — duplicate sibling names share one identity (kept, divergence 72)

**Ruling.** Two siblings with the same `.id` still share one `GlobalElementID`,
one `StateTable` entry, one hitbox id and one accessibility node, and it is
still not a trap. **Divergence 72**, pinned by
`twoSiblingsWithTheSameIDShareOneStateEntry` and, for groups, lane 3's E3.7.

**Evidence.** Probe X2: SwiftUI keeps two siblings with the same `.id` distinct
(two serials, each kept) — its explicit id is scoped to the structural position.

**Reasoning.** MetalUI's name **replaces** its position so that a named item
moving inside a `for` loop keeps its state (`reorderingANamedListCarriesEachItemsState`,
`ForEach`'s rule). SwiftUI can scope by position because its static children
never move and its `ForEach` supplies data ids separately; MetalUI has one name
for both jobs. Joining position into the name would reset every named `for`-loop
item on reorder — the thing `.id()` exists to prevent. The existing test's
"deliberately not a trap" reasoning stands.

**Cost if wrong.** An app that reuses a literal name for two static siblings
gets one shared state, as it does today; the remedy is unique names. Plan task
10's `ForEach` (data identity separate from names) is where a scoped `.id` could
land.

---

## ID-I — modifiers over multi-member content stay one layer (kept)

**Ruling.** `MC-A` stands: a modifier layer is one node and one identity level.
So, each **kept** with its reason:

1. **Divergence 56 stays live, amended.** A `.frame` on a multi-member
   `Component` is one layer over a row of per-member frames at spacing 0
   (`LR-BH`): in a horizontal parent this equals SwiftUI (probe L3: 140×10), in
   a vertical one it does not (L1/L2: SwiftUI stacks the framed members, 70×20;
   MetalUI rows them, 140×10 — scratch). The row's cross-axis alignment is the
   frame's own (`LR-BP`), where SwiftUI's members take the parent's — probe L8
   (critic round): under `.frame(width: 70, alignment: .top)` in an `HStack`
   the 30×10 member of a 30×10/50×30 pair sits at minY **10**, the parent's
   centre, as with no frame at all (L9); L10 (`HStack(alignment: .top)`, minY
   0) shows the instrument can see a top-aligned member. MetalUI's row puts it
   at 0. Lane 3 pins MetalUI's answer (N3.1, `M5g`'s mutation). **Owner: none** — the per-member answer is
   available as `.width`/`.height` (one frame per member, `LR-BG`) and inside
   the component's body.
2. **A `.frame` over zero members** (an empty `Component`) is a 0×0-content
   frame that still occupies its parent (scratch: 70×0, widening a `Column` to
   70); SwiftUI adds nothing (L5, with `EmptyView().frame` as the control L6).
   Part of divergence 56's row.
3. **`.overlay`/`.background { }` on a multi-member primary trap**, naming the
   count (N1.7; lane 3's B3.3 for the legacy background) — **divergence 73**.
   SwiftUI attaches one instance **per member**, each with its own state (G3,
   G4; one member G5 and one container G6 are the controls).
4. **A modifier on a multi-cell `GridRow` traps** — divergence 66, unchanged.
5. **The builder wrappers' 0/2+ traps** (`ProposalFrame { if … }`, `Padding`,
   `FixedSize`, `Background`, `OnTapModifier`; `CN-Q`) stay: SwiftUI has no
   builder frame, and each traps with a named message.
6. **`Component`'s decoration-backed `background(_ token:)`/`onClick`/`focusable`
   are not offered** (`LR-V`, pinned by
   `decorationBackedModifiersAreNotOfferedOnAComponent` and the guard
   `backgroundCannotBeCalledOnAComponent`): a compile error, not a wrong
   answer; declare them on the members. **The content-taking
   `.background(alignment:content:)` IS offered on a `Component` once `ID-J`
   lands**, exactly as `.overlay { }` already is (both on `ElementGroup`): a
   one-member component attaches, a multi-member one traps (item 3,
   divergence 73). Amended by `ID-M` item 1.
7. **`OnTapModifier` and `BackgroundModifier` stay separate types** (record §54
   §10.3): no behaviour depends on unifying them.

**Evidence.** Probe L0–L7, G1–G6; `swiftui-component-distribution.swift` G7/G9;
scratch L1/L5 (record §55 §2.2).

**Reasoning.** SwiftUI's per-member answer makes one modifier N views with N
identities; `.frame(…).background(…)`, `.opacity`, `.hidden()`, presentation
lowering and the layer's hitbox and accessibility node all hang off the one
layer today (six test files call `.frame` on a `Component`, several chaining `.opacity`, `.background` or `.hidden()` after it, record §55
§2.4). Distributing would change `MC-A`, `MC-C`'s numbering and every one of
those chains. A trap is loud and named; the row is the stage-3 answer and is
right in a horizontal parent.

**Cost if wrong.** A vertical parent shows a component's framed members side by
side — visible at once, with `.width`/`.height` as the spelling that distributes.

---

## ID-J — a legacy `.background(alignment:content:)`

**Ruling.** `BackgroundModifier<Content: ElementGroup, Background:
ElementGroup>`, its proposal conformances conditional on both sides, and **one**
`.background(alignment:content:)` on `ElementGroup` — `LR-FX`'s recipe for the
overlay, line for line: both sides through `lowerAttachmentChildren`, the
background side numbered under `.child(of: id, at: -1)` (`MC-P`), paint and
prepaint background first (hitboxes rank below the primary's). A primary of
zero or several nodes traps naming its count (divergence 73). The
`background(_ token: ColorToken)` overloads are untouched.

**Evidence.** `swiftui-modifier-identity.swift` F (a background's view has its
own state, kept across an update); `LR-FX` item 6 ("a legacy `.background {
content }` is **not** added (task 8)"); record §54 §8.5 and §10.3.

**Also, measured by the critic round** (`ID-M` item 1): because the one
overload is on `ElementGroup`, a `Component` gains `.background { }` (as it
has `.overlay { }`), and the existing guard `backgroundCannotBeCalledOnAComponent`
(fixture `Leafless().background(.accent)`, reason check
`messages.contains("background")`) **turns red**: with the new overload in
scope `swiftc` answers `missing argument label 'alignment:' in call` and
`missing argument for parameter 'content' in call`, neither naming
`background` (reproduced with the overload declared in a fixture over the
`e3cb3e9` modules). Lane 3 re-spells it (a **T** row, same subject): fixture
`Leafless().background(ColorToken.accent)`, reason check `contains("ColorToken")`
— measured, the diagnostic is `cannot convert value of type 'ColorToken' to
expected argument type 'ProposalAlignment'` — and mutates it red once by
declaring a `background(_: ColorToken)` on `Component` (it then compiles).
The same emulation showed `let b: Box<EmptyGroup> = Box().background(.accent)`
still resolving to the token overload (no diagnostic).

**Cost if wrong.** A second overload that changes resolution for a proposal
chain (guard G3.3 holds the proposal spelling's inferred type).

---

## ID-K — what already matches, and divergence 20

**Ruling.** Pinned as they stand (record §55 §3): an if/else flip resets the
branch (V4; `flippingAnEitherBranchResetsTheBranchesState`); a constant name
keeps state and a changed name resets it (X1/A1 — the reset half gains its pin,
lane 3's E3.8); a modifier's **value** change keeps the content's state and a
**count** change resets it (`swiftui-modifier-identity.swift` C/D1/D2;
`MC-C`'s pins); an overlay's and a background's content have their own identity
(E/F; `theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities`); a
`Component` is layout-transparent (component-distribution G0 = G1;
`aComponentsContentFlattensIntoItsParent`) and identity-opaque — its state keyed
under its own id, as a custom view's is (`twoSiblingComponentsHoldIndependentState`,
`aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt`); its
`.padding` and `.width`/`.height` apply per member (G2/G3, G7/G8, L7;
`aComponentsPaddingLowersAsAnOrdinaryOneChildContainer`,
`aComponentsWidthFramesEachMember`). **Divergence 48 retires**: its subject (a
`Component`'s width overwriting its members' own) has been SwiftUI's answer
since stage 3 (`LR-BG`) and is this task's to count. **Divergence 20 is kept**
(design): a layer added at run time is adopted by the new outermost layer while
the wrapped content resets — the content half is SwiftUI's D1 answer; the layer
half is state SwiftUI's modifiers do not have.

**Cost if wrong.** None beyond the count: every row here already has a pin.

---

## ID-L — the items addressed to task 8, disposed

| item (source) | disposition |
|---|---|
| `Group` semantics: a `Component`'s per-member `.frame` (`LR-GA` item 3, `LR-FY` item 2, divergence 56's remainder, `TB-M`) | kept, `ID-I` 1 |
| the per-member row's cross-axis alignment (`LR-BP`, `LR-GG` item 5, `M5g` green) | kept and pinned, `ID-I` 1 (N3.1) |
| a `Group`-style overlay on a multi-member primary (N1.7) | kept, divergence 73, `ID-I` 3 |
| a legacy `.background { content }` (`LR-FX` item 6) | fixed, `ID-J` |
| `OnTapModifier`/`BackgroundModifier` as separate types (record §54 §10.3) | kept, `ID-I` 7 |
| `.id()` on built-in proposal elements, `Grid`/`GridRow` (`GR-J`, `GR-N`, grids record) | fixed, `ID-G` |
| trailing-sibling adoption on a vanishing `if` (`SI-G`; grids record) | fixed, `ID-B` |
| divergence 69 (`GR-O` 9, `GR-AF`) | retired, `ID-B` |
| divergence 18 | retired for conditionals, `ID-C`; arrays → divergence 74 (task 10) |
| divergence 19 | retired, `ID-F`; residual → divergence 71 |
| `@State` inside `AnyElement`; `@Environment` inside `AnyElement` (`EV-M`) | fixed, `ID-E` |
| `Component` identity-opaque / layout-transparent, divergence 48 | matches; 48 retired, `ID-K` |
| `Component` `background`/`onClick`/`focusable` (`LR-V`) | kept (not offered), `ID-I` 6 |
| builder wrappers with 0/2+ nodes (`CN-Q`, containers carried table) | kept, `ID-I` 5 |
| a modifier distributing over a multi-cell `GridRow` (`GR-J`, divergence 66) | kept, `ID-I` 4 |
| `EitherGroup: ProposalElementGroup` (record §09 boundary 4, "tasks 6/8") | fixed, `ID-D` |
| divergence 20 (`MC-C`) | kept, `ID-K` |
| proposal `.id()` (modifier-composition carried table → task 12) | taken here, `ID-G`; focus/AX on proposal elements stay task 12's |
| grid rows' own identity level (`GR-O`: "if task 8 decides rows should be identity-transparent") | kept: V7/V8 show SwiftUI keeps a vanishing row's neighbour, which `ID-B` gives without making rows transparent |

---

## ID-M — the critic round: five amendments, three findings rejected

**Ruling.** The critic-and-revise pass over `4a660e7` (the design commit)
amends the design as follows; each item is applied in the spec, record §55 and
the rulings above in the commit that appends this ruling.

1. **`ID-J` makes `.background { }` compile on a `Component`, and reddens a
   guard the design did not list.** Measured (the new overload declared in a
   fixture over the `e3cb3e9` modules, `swiftc -typecheck`): the guard
   `backgroundCannotBeCalledOnAComponent` stops matching its reason, because
   the diagnostic no longer names `background`. Disposition: lane 3 re-spells
   it (**T**, same subject, `ColorToken` fixture and reason; mutation: a token
   overload on `Component`), and `ID-I` item 6 now says which background is not
   offered (the token one) and which is (the content one, trapping on several
   members like `.overlay`). No test count moves.
2. **Divergence 71's SwiftUI column had no probe arm.** The audit row read
   "its own occurrence" for a write outside input dispatch with nothing
   cited. Probe arms **S5** (one value placed twice, closures called directly
   afterwards: each call moves only its own occurrence) and **S6** (two values,
   control) added and run in both forms, byte-identical; every earlier arm
   re-ran byte-identical. 71 is kept, now with evidence and a reason: SwiftUI
   re-points a copy's `@State` at each placement's storage, which MetalUI's
   `Mirror`-seeded class box cannot do for a copy it cannot write
   (`State.swift`'s note); dispatch-time resolution (`ID-F`) covers every
   input path, and the remedy for a timer or task is two values. Owner: none
   (design).
3. **Divergence 56's row-alignment sub-row cited L4, which prints a size, not a
   position.** Probe arms **L8** (per-member frame with `.top` in an
   `HStack`: the short member at minY 10, the parent's centre), **L9** (no
   frame, the same 10) and **L10** (`HStack(alignment: .top)`, 0 — the
   instrument can see top) added and run. N3.1 now pins a probe-backed
   divergence (MetalUI 0 vs SwiftUI 10), kept under `ID-I` item 1.
4. **`ID-C` changes `TextField`/`TextEditor` behaviour, which is on the
   must-not-move list, without naming it.** Their `TextEditState` is keyed by
   the field's own id, so the reset reaches it while `$focus` keeps focus.
   Ruled (not widened: an exemption for `TextEditState` would be a
   field-specific retention SwiftUI does not have — SwiftUI drops focus too),
   named in `ID-C`'s migration note and pinned by lane 2's **C2.12**
   `aFocusedTextFieldInsideAToggledIfKeepsFocusAndStartsItsEditStateFresh`:
   a focused field with a selection and marked text, its `if` false for one
   frame — `setTextInputArea(nil)` is called while it is absent (the
   `e3cb3e9` behaviour, unchanged), focus is retained, and on return its
   state equals `TextEditState()` and the input area is the fresh caret's.
   Mutation M2f (no exemption) reddens its focus half; M2d (no reset) its
   state half. Lane 2 adds 11 tests, not 10.
5. **A "matches" row with no pin**: "an `.id` written inside a modifier still
   resets" (probe X7) named no MetalUI test. Lane 3 adds **E3.9**
   `anIDWrittenInsideAModifierStillResetsWhenItChanges` (`Box().id("a\(n)")
   .padding(Pixels(4))`: constant keeps, changed resets); M3d reddens it. Lane 3
   adds 16 tests, not 15. The G7 row (a modified group past a vanishing `if`)
   gains an arm in C2.1: a two-member `Component` with `.padding` as the
   trailing sibling, both members keeping their own state.

Also recorded for the Record phase: record §04's listed pins for divergence
48 (`aComponentsWidthStillOverwritesItsMembersDeclaredWidth`) and 56
(`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`) **do not exist in
`Tests/` at `e3cb3e9`** (grep, one hit each expected, zero found); the live
pins are `aComponentsWidthFramesEachMember` and
`aFrameOverAMultiMemberComponentFramesEachMember`, and the Record phase's §04
section names them.

**Considered and rejected** (the task template asks for these as `LR-`
rulings; `LR-` is task 7's closed ledger, so they are recorded here under this
task's prefix):

- *`ID-F` is a new feature, not task 8.* Rejected: divergence 19 is the
  "reused-value aliasing difference" the task text names, and the
  modifier-composition carried table sent it here.
- *`ID-J` and `ID-G` are features.* Rejected: `LR-FX` item 6 addressed the
  legacy `.background { }` to task 8, and the grids record addressed `.id()`
  on built-in proposal elements to task 8 ("cannot be spelled until task 8").
- *Lane 2 is too large to run as one.* Rejected: its three rulings share
  `ElementGroup.swift` and `ProposalElementGroup.swift` (both copies of every
  group), so splitting would put two lanes on one file; the lane's mutations
  already name the copy each is applied to.

**Accounting after this ruling:** 1444 → 1452 (lane 1) → 1463 (lane 2) →
**1479** (lane 3); guards 84 → 84 → 85 → **88**.

---

## ID-N — lane 1's amendments: the submit site, three test spellings, two mutation predictions

**Ruling.**

1. **A text field's submit callback is a dispatch site** beside its edit
   callback: `Window.dispatchTextKey` runs `onSubmit` under
   `StateDispatch.dispatching(to: id)`, as `applyEdit` runs `onChange`. `ID-F`
   enumerated "a text field's edit callback" only; risk 4 of the spec asked the
   lane to grep every other handler call before closing, and `onSubmit` is the
   one it found (the others — `Box.onAction`'s and
   `accessibilityAdjustableAction`'s wrappers — run inside an enumerated site;
   `Window.onAction`/`onInput` are window-level and have no element). Pinned by
   O1.6's submit arm under a new mutation **M1l**.
2. **Every arm targets the NOT-last-bound occurrence.** An arm aimed at the
   occurrence that bound last is green before the fix and cannot be reddened
   by its site's mutation. So O1.3's press arm presses occurrence **0** (the
   spec said 1), and O1.4 clicks occurrence 0 first, then 1 (the spec's single
   click on occurrence 1 read `[0, 1]` either way — the `Component` binds only
   in layout, so occurrence 1 is last-bound; red is `[0, 1]` then `[0, 2]`).
3. **O1.6 has two arms** (edit, submit), each with its own `@State`.
4. **M1g reddens O1.4 and O1.6**, not O1.4 alone: the field's state is its
   `Component`'s, an ancestor of the field, the same shape as O1.4. **M1a
   reddens O1.1–O1.4 and O1.6, not O1.5** (the environment resolves through
   its own box, M1h's). **M1j also reddens O1.8** (an unbound layout stamps
   nothing: `[0, 0]`) and the renamed E8.

**Evidence.** Record §55 §5 (lane 1): the red run and the twelve mutations,
each from a committed tree, whole suite.

**Cost if wrong.** None to behaviour; items 2–4 are how the tests are spelled
and what their instruments redden. Item 1 is one more wrapped call, no other
behaviour moves (the whole suite and the fourteen offscreen images read
unchanged).
