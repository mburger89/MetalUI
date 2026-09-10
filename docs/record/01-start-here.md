# MetalUI

A GPU-accelerated UI framework for Swift, architecturally modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui) but written as
idiomatic Swift. macOS and iOS.

## Start here

- **Design spec (binding authority):** `docs/superpowers/specs/2026-08-24-metalui-design.md`
- **Decisions taken during execution:** `docs/superpowers/2026-08-25-m0-decisions.md`,
  `docs/superpowers/2026-08-25-m1a-decisions.md`,
  `docs/superpowers/2026-08-25-flex-sizing-decisions.md`,
  `docs/superpowers/2026-08-25-alignment-decisions.md`,
  `docs/superpowers/2026-08-25-box-model-decisions.md`,
  `docs/superpowers/2026-08-25-wrapping-decisions.md`,
  `docs/superpowers/2026-08-26-element-pipeline-decisions.md`,
  `docs/superpowers/2026-08-26-content-sizing-decisions.md`,
  `docs/superpowers/2026-08-27-structural-identity-decisions.md`,
  `docs/superpowers/2026-08-27-text-m2-decisions.md`,
  `docs/superpowers/2026-08-28-clipping-scroll-decisions.md`,
  `docs/superpowers/2026-08-28-stack-decisions.md`,
  `docs/superpowers/2026-08-28-absolute-positioning-decisions.md`,
  `docs/superpowers/2026-08-28-measure-performance-decisions.md`,
  `docs/superpowers/2026-08-29-input-decisions.md`,
  `docs/superpowers/2026-08-30-sizing-decisions.md`,
  `docs/superpowers/2026-09-01-tombstones-decisions.md`,
  `docs/superpowers/2026-09-02-reactivity-decisions.md`,
  `docs/superpowers/2026-09-03-component-decisions.md` — each ruling with
  its reasoning and what it costs if wrong. Read the "Carried..." sections before
  starting new work.

  **Ruling IDs are namespaced by milestone.** `PF-3` and `C-3` belong to m1a;
  `FS-n` to flex sizing, `AL-n` to alignment, `BM-n` to the box model, `WR-n` to
  wrapping, `EP-n` to the element pipeline, `CS-n` to content sizing, `SI-n`
  to structural identity, `TX-n` to text (M2), `CL-n` to clipping and scroll,
  `ST-n` to the stack container, `AP-n` to absolute positioning, `MP-n` to
  measure-path performance, `IN-n` to `@State`/hit testing/input dispatch,
  `SZ-n` to the sizing milestone that closed BM-4, FS-3 and TX-H, `TB-n`
  to the tombstones-and-AX milestone that closed divergences 12 and 17, and
  `RX-n` to the reactivity milestone that wrapped the frame build in
  `withObservationTracking` (M4 spec 1), and `CO-n` to the `Component`
  milestone (M4 spec 2) (the
  last twelve are
  **lettered** — `CS-A`…`CS-O`, `SI-A`…`SI-H`, `TX-A`…`TX-J`, `CL-A`…`CL-F`,
  `ST-A`…`ST-G`, `AP-A`…`AP-M`, `MP-A`…`MP-N`, `IN-A`…`IN-W`, `SZ-A`…`SZ-O`
  (**`SZ-A`…`SZ-N` until the sizing milestone's whole-branch fix wave added
  `SZ-O`, the propagation regression TX-H shipped** — same shape as the `MP-L`
  note below, so a citation of `SZ-O` is real) and **`TB-A`…`TB-AH`**, whose
  **two-letter tail is deliberate and not a typo**: `TB-A`…`TB-AD` carry the
  execution ledger's own thirty letters one for one, so a citation written
  during that milestone still resolves, and `TB-AE`…`TB-AH` are the four
  foundational decisions the ledger recorded as prose rather than as
  lettered rulings — read those four first
  — and **`RX-A`…`RX-R`**, which follows `TB-`'s pattern deliberately:
  `RX-A`…`RX-J` carry the reactivity ledger's own ten letters one for one, and
  `RX-K`…`RX-R` are the eight foundational decisions that ledger recorded as
  prose — read those eight first
  — and **`CO-A`…`CO-Z`**, which follows the same pattern a third time:
  `CO-A`…`CO-O` carry the `Component` ledger's own fifteen letters one for one,
  and `CO-P`…`CO-Z` are the eleven foundational decisions that ledger recorded
  as prose, a user decision or a task report — read those eleven first. **The
  alphabet is exactly used up at `CO-Z` and that is a coincidence, not a
  boundary**: a further ruling becomes `CO-AA`, on `TB-`'s two-letter footing,
  and must not restart at `CO-A`
  — so a bare
  `CS-3`, `SI-3`, `TX-3`, `CL-3`, `ST-3`, `AP-3`, `MP-3`, `IN-3`, `SZ-3`,
  `TB-3`, `RX-3` or `CO-3` is a
  typo rather than a citation; **`MP-A`…`MP-K` is what this line said until the
  input-and-state milestone re-read the file — the measure-performance
  milestone's whole-branch review added `MP-L`, `MP-M` and `MP-N` and did not
  update the range here, so a citation of `MP-L` is real and this sentence
  denied it**) (**`EP-2` and `EP-4` were never
  assigned** and must not be reused — a new ruling taking one would silently
  rebind any citation written against the gap). Sweep for stray citations **case-insensitively** — a `Ruling F-3` survived two branches' greps for lowercase `ruling`. A bare `F-1` is ambiguous — m0, m1a and flex sizing each
  had one, and three code comments on the flex-sizing branch cited the wrong
  document before this was fixed. Prefix new milestones' rulings the same way.

- **Identity is structural and universal, and `.id()` is an override rather than
  a source.** Every element has a `GlobalElementID` — a persistent linked list of
  `PathComponent`, each either `.positional(Int)` (the element's index in its
  container's **flat** child list) or `.named(ElementID)`. **A name replaces a
  position; it never joins it**, so a named item keeps its state through a
  reorder. `nil` is gone from the identity a phase receives, so "every element
  has identity" is a compile-time fact rather than a rule to remember. Three
  consequences a reader will otherwise get wrong:

  - **A vanishing `if` makes the trailing sibling ADOPT the vanished element's
    state, not reset it** — measured, and the remedy is the half intuition gets
    backwards: naming the **trailing sibling** carries its state through, while
    naming the **conditional content** removes the inheritance and still leaves
    the reset. Both pinned (`anElementAfterAVanishingIfAdoptsTheVanishedElementsState`,
    `namingTheLaterSiblingIsWhatSurvivesAVanishingIf`).
  - **The adoption reaches CLICK DISPATCH, and a click can therefore fire the
    WRONG element's handler** — the same rule as the bullet above, arriving in
    a place nobody designed it into. `Window.dispatchClick` requires the hitbox
    under the release to own the `GlobalElementID` the press made active; if a
    conditional sibling vanishes *between* the `mouseDown` and the `mouseUp`,
    the trailing sibling adopts that id, slides into the vacated position, and
    the release runs **its** `onClick`. Measured, not reasoned: press at
    `positional(0)/positional(0)`, drop the `if`, release at the same point, and
    the trailing box's own closure runs. **Naming the trailing sibling is the
    remedy here too** — with `.id("b")` on it nothing is adopted and the release
    correctly clicks nothing, and `dispatchClick` is byte-identical across the
    two halves, which is what makes this identity's behaviour rather than
    dispatch's. Pinned by
    `aVanishingIfBetweenPressAndReleaseClicksTheTrailingSibling`
    (`Tests/MetalUITests/InputDispatchTests.swift`), which asserts both halves;
    recorded at `dispatchClick`'s own doc as well. **Not filed as a divergence
    and not fixed**: it is this framework's identity rule applied consistently,
    and "fixing" it means giving dispatch a second notion of sameness that
    disagrees with the one `StateTable`, focus and hover all use.

    **FOCUS has the same flavour of this, it is PRE-EXISTING, and it is
    recorded here because a reader will otherwise find it and file it against
    the tombstones milestone.** A *focused* element inside a vanishing `if`
    hands focus to the trailing sibling that adopts its id, and that sibling's
    `onKey` runs — measured through a real `Window`: `["A"]` before the vanish,
    `["B"]` after, with `focusedElement` unchanged. **Tombstone retention did
    not create this and does not worsen it.** The old `resolveFocus` was
    `if !focusRegistry.isFocusable(focused) { focusedElement = nil }`, and the
    adopting sibling registers as focusable *under the adopted id* — so
    `isFocusable(focused)` was already `true` and focus was already retained,
    on exactly the same frame, before any of this milestone's changes. Same
    rule, same remedy: name the trailing sibling.

  - **`cachedHash` and `==` are safe individually and unsafe only together.**
    Dropping the parent from the hash reddens exactly one test; a hash-shortcut
    `==` reddens nothing; do both and two unrelated elements silently share a
    `StateTable` entry. The load-bearing line is **`==`'s chain walk**, which no
    test can guard — a 64-bit collision is not constructible against a
    per-process-seeded `Hasher` — so the mechanism is stated at `==` per
    taxonomy shape 6. Do not "simplify" it on the evidence of a green suite.

  **Tombstones and exit transitions were untouched by universal identity, and
  this sentence has since EXPIRED in its second half.** What it said, and what
  was true when it was written: §4.3 records that AX identity needs entries
  surviving the sweep as invalid-reporting tombstones, and that exit
  transitions are impossible until that exists; universal identity makes
  tombstones *more* useful and no easier, being a change to the **sweep**, not
  to the key. **The sweep change landed on 2026-09-01.** `StateTable.sweep()`
  retains an unmarked entry with its value and clears only its `isLive` flag,
  a bounded reap removes it later, and `Frame.axNode(for:)` is the
  invalid-reporting handle §4.3 asked for. So **exit transitions are now
  POSSIBLE and UNBUILT**, which is a different claim from "impossible until
  that mechanism exists": the prerequisite is here, and what is missing is a
  distinction nothing yet draws between "gone, keep animating out" and "gone,
  ordinary tombstone". The first half of the original sentence still stands
  exactly as written — universal identity was a change to the key and this was
  a change to the sweep, and neither disturbed the other.

- **`Column` and `Row` centre on the cross axis; `Box` stretches. Ruling EP-8,
  2026-08-27, and this closes what was open.** SwiftUI's `VStack`/`HStack`
  centre, CSS stretches, and EP-5 takes SwiftUI's answer where the two differ.
  EP-6 held `stretch` on a *mechanism* — an `auto` cross size resolved to 0, so
  a centred child with no cross size would have painted nothing — and named that
  mechanism as "a prerequisite, not an application"; content sizing built the
  prerequisite, and EP-8 is the application. EP-6's other half, **no invented
  default `gap`, still stands**.

  **The change is in `Column.init`/`Row.init`, not in `Style`.** `Style`'s
  `alignItems` default is still `nil`, the engine still reads that as CSS's
  `stretch`, `Box` is untouched, and **no golden moved** — WebKit stays the
  oracle for the flex algorithm and the split is what makes that true. If a
  golden ever moves for a stack-default change, something reached the engine
  that should not have. The split is a checked property, not a convention:
  `aStackCentresOnTheCrossAxisWhereABoxStretches` asserts the `Column` answer
  (70) and the `Box` answer (0) side by side, so moving the default down into
  `Style` reddens its second half while leaving the first green.

  **The cost, and it is real: a childless `Box` measures 0, so a box with no
  cross size now paints nothing** where `stretch` silently filled its container.
  That is a *louder* failure than the one it replaces — a missing rectangle is
  visible, a wrongly-filling one is not — but it has to be paid in writing. The
  remedy is a declared cross size, or `.alignItems(.stretch)` on the container
  where "these fill their parent" is what the code means;
  `Sources/MetalUIDemo/main.swift` writes `.alignItems(.stretch)` in **five**
  places (root column, body row, sidebar, main pane, modal panel) and says so at
  each. **Only the first four are paying EP-8's cost** — the fifth, added by the
  absolute-positioning milestone, is on a column of `Text`, which shrink-wraps
  correctly on a column's cross axis since ruling TX-H and would paint fine
  without it. It was written so each label took the panel's integer content
  width rather than its own fractional max-content — **divergence 8's input,
  and that reason has expired now that the divergence is fixed**. It is kept
  for the look (the labels share one left edge), not as a workaround.
  Re-count with an **anchored** pattern, `grep -cE "^ +\.alignItems\(\.stretch\)"
  Sources/MetalUIDemo/main.swift`, which returns 5. An unanchored `grep -c`
  returns **10**: five of the demo's comments name the modifier while
  explaining why it is there. **Both numbers have moved three times in three
  milestones**: the anchored one was 5, went to 4 when clipping-and-scroll
  deleted the row of weights, and is back to 5; the unanchored one is recorded
  at 7 before the stack milestone added a fourth explaining comment, 8 after,
  and 10 now that absolute positioning added one of each kind. A paragraph
  written to stop a mis-count has itself mis-counted once, which is exactly why
  it says to run the anchored grep rather than to trust either number.

  **Two sentences have now expired here in two commits, and the second was
  written by the commit that retired the first.** The original — "a leaf still
  has no production `MeasureFunction`, so a `Column` of text-shaped leaves will
  measure 0 on the cross axis" — expired with M2 Task 4. Its replacement said a
  centred `Text` took its **max-content** width and was laid out 270 wide in a
  120-wide `Column`; that was the **ORIGINAL** divergence 6 — the one whose
  retirement freed label **7**, not the one that freed label 6 — and **it is
  fixed** (ruling TX-H, whose row in
  `docs/superpowers/2026-08-27-text-m2-decisions.md` is this fix): a column's
  cross axis is the inline axis, so an `auto` cross size shrink-wraps and the
  label is 120 wide at `x = 0`, agreeing with WebKit. **`Column { Text }` now
  needs no remedy at all.**

  **Read "divergence 6" here with the date attached, because two retired
  entries answer to that label and both also answer to `TX-H`.** The original
  6 is this bug (`ownCross` measuring max-content on a column's cross axis);
  it was fixed in M2, and the then-divergence 7 slid down into the slot,
  making "divergence 6" mean *that* — an item's cross size measured before
  §9.7 flexes it — until the sizing milestone fixed it too and retired the
  label. The ruling id does not separate them: `TX-H` is the M2 decisions
  doc's name for the fit-content change described here, and CLAUDE.md's
  divergence list attached the same id to the flexing-order half. What
  separates them is the *symptom*: a label laid out at its unwrapped width
  and hanging off both sides is this one; a container reporting a stale cross
  size after §9.7 shrank it is the other. Both labels are retired and neither
  is ever reused — see the divergence-list header's label-6 and label-7
  bullets, which carry the full history. Nothing on this line is new: the
  sentence has been present verbatim since `a98bd8a`, and only became
  ambiguous when the sizing milestone retired the second meaning. What the bullet above still costs is the
  *childless* `Box`, which measures 0 because it has no content to wrap — the
  demo's four `.alignItems(.stretch)` are paying for that and not for text.

- **`Stack` is the framework's third container, and it layers rather than
  sequences.** `display: .stack` runs one pass — no flexing, no main axis —
  sizing itself to the **max** over its children on each axis independently
  and placing every child at the same position, given by a nine-case SwiftUI
  `Alignment` (`.topLeading` … `.bottomTrailing`, default `.center`). Children
  paint in declaration order, first at the back, so the last child in a
  `Stack { … }` is the one on top. **`Stack.swift` holds `Stack` and
  `Alignment`; `Flex.swift` holds `Column`/`Row`** — this milestone renamed
  `Sources/MetalUI/Stack.swift` (the file) to `Flex.swift` to make room for
  the new `Stack.swift` (the type), so the filename that used to hold
  `Column`/`Row` is not the one that holds `Stack` today. Decisions doc:
  `docs/superpowers/2026-08-28-stack-decisions.md`, rulings prefixed `ST-`.

- **`List` is NOT the framework's fourth container. It is a windowed sequence
  built from data, and it is a `Box` underneath.** `Row`, `Column` and `Stack`
  are containers: they take an `@ElementBuilder` block of statically-known
  children and answer a layout question about them (sequence on the main axis,
  layer on both). `List` answers no new layout question at all — it composes
  `display: .flex` with `flexDirection: .column`, the same thing `Column`
  spells — and its whole reason to exist is *which* children get built. It
  takes a `RandomAccessCollection` plus a per-datum builder closure, and on
  every frame it constructs elements only for the rows intersecting the
  enclosing `ScrollView`'s viewport, plus two rows of overscan on each side. A
  500-row `List` and a 40-row one cost the same frame **in steady state — and
  not on frame 0**, which builds every row because a `ScrollView`'s viewport
  extent is not measured until its own `prepaint` has run once (ruling MP-I).
  Measured on the demo's tree, that first frame is 7.87 ms at 40 rows and
  **76.26 ms at 500** in release, 19.32 and **188.30 ms** in debug.

  **Four requirements, and each is load-bearing rather than stylistic.**
  `Data.Element: Identifiable`, because a row not built this frame would
  otherwise take a different `.positional(_:)` component when it returns —
  the vanishing-`if` hazard, made routine (ruling MP-D). A uniform declared
  `rowHeight`, because that is what lets the window be found by division
  rather than by laying rows out; variable heights need a prefix-sum index
  and have no spelling here. An enclosing `ScrollView`, which is what
  publishes the ambient `LayoutPass.scrollContext` the window is computed
  from — a `List` with no context above it builds every row, which is correct
  for a list nobody scrolls.

  **And a silent fourth the first three do not prepare you for: the `List`
  must be that `ScrollView`'s ONLY layout-contributing child.** The first
  three announce themselves — two are type constraints and the third
  degrades to "builds everything". This one degrades to **blank**. The
  ambient context describes the *scroller*, and `visibleRange` reads it as
  though it described the `List`, so anything above the list that occupies
  flow — a header, a spacer, a second `List` — shifts the window off the rows
  actually on screen by that thing's height. (An out-of-flow sibling is free,
  which is measured and is why the demo's absolutely-positioned `Deferred`
  modal, declared before its `List` in the same `ScrollView`, is not in
  violation.) Measured with a 300pt header:
  rows 0 through 3 are visible and rows **8 through 16** are built, every one
  of them masked away. Nothing enforces it and nothing can — see divergence
  14 and ruling MP-L for why `requestLayout` cannot know where it sits.

  **What it costs is TWO divergences, 13 and 14 below, and two BOUNDED
  guarantees.** It was three, then four when focus existed, and it is two
  because the tombstones milestone retired 12 and 17 — **read that retirement
  at exactly its strength, which is the point of this paragraph.** The two
  that remain are unqualified: the window is computed against a one-frame-stale
  viewport extent (13), and it is placed against the scroller's origin rather
  than the list's own (14). The two that were retired are **closed for a
  bounded window, not absolutely** (ruling `TB-AH`): a row scrolled out and back
  within `StateTable.staleAfterGenerations` — **two** generations — keeps its
  `@State` (was 12) and keeps its focus (was 17); an excursion of three
  generations keeps neither, and the reap that takes them only engages once the
  table holds more than `sweepThreshold` (**256**) entries at all. So the old
  advice still stands for long excursions: **a value a long scroll must not
  lose belongs in the data, not in a row's `@State`** — `List` re-reads `data`
  every frame, so a value derived from a datum is stable by construction. Focus
  has no such remedy, which is what made 17 the worse of the two, and its
  closure is bounded on exactly the same terms.
  `Sources/MetalUI/List.swift`; decisions docs
  `docs/superpowers/2026-08-28-measure-performance-decisions.md` (`MP-`),
  `docs/superpowers/2026-08-29-input-decisions.md` (`IN-M`) and
  `docs/superpowers/2026-09-01-tombstones-decisions.md` (`TB-AH`, `TB-AF`).

  **One thing `List` still does not give accessibility, and it is HALF of
  design spec §9's requirement rather than none of it (ruling `TB-W`).** Every
  `List` emits its own `AXNode` carrying `logicalCount = data.count`, so the
  "500" of VoiceOver's "3 of 500" is real and correct regardless of how many
  rows the frame built. **The "3" is not**: rows emit no AX nodes and
  `AXNode.children` is always empty. Measured through the real three-phase
  pipeline on a production-shaped 500-row `List`: `totalAXNodes=1, rowNodes=0,
  children=0, logicalCount=500` — and with the demo's own row shape,
  `hitboxes=17`, so seventeen rows are realized as *hit targets* and none as AX
  nodes. Both `AXNode.children` and `AXNode.logicalCount` have rows in the
  declared-but-inert table.

  **A third consequence of "not produced ⇒ not seen" arrived on 2026-09-02 with
  `@Observable` tracking, and it is DOCUMENTED BEHAVIOUR rather than a
  divergence (ruling `RX-P`).** A `List` builds only the rows intersecting the
  viewport, so an off-screen row's builder never runs and its model reads are
  never tracked — **mutating an off-screen row's datum marks nothing dirty.**
  That is correct: there is nothing on screen to redraw, and scrolling to the
  row rebuilds it and re-reads the model, so it self-heals; the value lives in
  the datum, which `List` re-reads every frame. **Explicitly not a divergence,
  and the reason is that no oracle disagrees** — SwiftUI's `List` behaves the
  same way for the same reason — where 13 and 14 above are accepted limitations
  and 12 and 17 were live losses. **That SwiftUI comparison is DERIVED from
  SwiftUI's documented laziness and was NOT measured here** (ruling `RX-P`): a
  row's `body` is not evaluated until the row is realized, so nothing in it can
  be read or tracked — but no probe was run, and this repo's own precedent
  (divergences 2 and 9) is that an oracle claim gets run before it is written.
  Confirming it needs a SwiftUI harness this repository does not have and should
  not grow for one claim, so it is labelled rather than deleted. **Nothing is
  foreclosed: if SwiftUI does differ, the divergence label is still
  available.** It is the same *mechanism* as those four,
  which is why it is recorded here rather than left to be rediscovered. Pinned
  by `anOffScreenListRowsModelReadIsNotTracked` (`ObservationTests.swift`),
  which carries its own positive control on the same fixture — `rows[0]` is
  mutated first and must dirty — because without one a `List` that stopped
  tracking row builders *entirely* would pass the off-screen half vacuously.

- **`Deferred` is a portal, and it is the framework's first element that is not
  a container.** It takes **exactly one** child (ruling AP-J: it is a paint
  modifier, not a layout container, so two children would force it to answer a
  question `Column`/`Row`/`Stack` exist to answer), contributes no `Style` and
  no layout node of its own, and does two things to its subtree's *emission*:
  hoists it to a single root layer, so it paints above every sibling, and
  **replaces** the clip stack's top entry with the whole surface at zero
  offset, so it escapes an ancestor `ScrollView`'s clip *and* its scroll
  translation (ruling AP-I — those are one stack entry, and escaping one
  without the other is a half-portal). Both halves run on `prepaint` as well as
  `paint`, because the scroll-region registry is built in prepaint and a
  tooltip that paints above its siblings while receiving events below them is
  worse than one that does neither. There is no `z-index`: nested `Deferred`
  all land on the same layer (AP-H).

  **Neither half is visible to any assertion over rects**, which is why the
  demo carries it: a `Deferred` subtree's `(x, y, width, height)` are identical
  whether or not it hoists and whether or not it escapes. Same shape as
  `Stack`'s z-order.

  **Absolute positioning is the other half of the same milestone and is
  separable from this one.** `Style.position` and `Style.inset` are live:
  `.absolute` removes a box from flow at both collection sites, and it is
  placed by inset against the nearest ancestor whose `position` is not
  `.static`, falling back to the root — which is what makes "positioned against
  the window" spellable from anywhere in the tree. `position(_:)` and
  `inset(_:)` are public modifiers as of this milestone (AP-L). A tooltip needs
  the portal; a modal needs both. Decisions doc:
  `docs/superpowers/2026-08-28-absolute-positioning-decisions.md`, rulings
  prefixed `AP-`.

- **`Component` is the user-facing element surface, and it is TRANSPARENT to
  layout and OPAQUE to identity — one sentence with two halves, and a reader
  who carries only one will be wrong about the other.** As of 2026-09-03 (M4
  spec 2), an author writes `content` and gets a working element:
  `protocol Component: ElementGroup` with `associatedtype Content: ElementGroup`,
  and one protocol extension supplies the whole conformance
  (`Sources/MetalUI/Component.swift`). Every *other* element in this framework
  is opaque to **both** axes — a `Box` consumes one cursor index *and*
  contributes one layout node — so `Component` is the first type to use them
  differently.

  - **Layout-transparent**: it contributes **no layout node of its own**. Its
    content's `[LayoutNodeID]` is returned unchanged, so `Column { MyRow(); MyRow() }`
    lays the rows' children out as the `Column`'s own children.
  - **Identity-opaque**: it consumes **one cursor index** and its content nests
    beneath the component's own `GlobalElementID`. **This half is not a
    choice.** `@State` slots are `.named("$state\(n)")` children of the
    element's own id (`StateBinder.bind`), so a component with no id of its own
    **could not hold state at all** — and holding state is the main reason to
    write a component rather than a function returning elements.

  **MODIFIERS DISTRIBUTE, they do not wrap, and this overturned the spec's own
  first design (ruling `CO-U`).** `MyComponent().padding(4)` returns a
  `StyledComponent<C>` that amends the `Style` of **each** top-level node the
  content contributed — via `LayoutTree.setStyle`, which this is the **first
  production caller** of (`CO-V`) — and returns those same nodes unchanged. **A
  modified component is therefore still layout-transparent**, which is the
  opposite of what a wrapping implementation would give. It also mints **no
  identity of its own**: `MyComponent()` and `MyComponent().padding(4)` produce
  the identical `GlobalElementID`, so a modifier does not reset a component's
  `@State` (`addingAModifierDoesNotResetAComponentsState`).

  **The SwiftUI claim underneath both halves is MEASURED, not derived, and it
  does not sit on `RX-P`'s footing (rulings `CO-E`, `CO-U`).** Two throwaway
  probes outside the repo, each with a passing positive control, neither
  committed — the footing this repo uses for oracle probes. A custom `Layout`
  conformer recording `subviews.count`: inline `A; B` = **2** (the control),
  `Group { A; B }` = **2**, a custom view whose body is two views = **2**, two
  such views = **4**. And `NSHostingView.fittingSize` on a body of 30×10 and
  50×10: single view `.padding(8)` = **46×26** (the control),
  `HStack { MyRow() }` = **88×10**, `MyRow().padding(8)` = **120×26**,
  `Group { A; B }.padding(8)` = **120×26** — `(30+16) + 8 + (50+16) = 120`,
  where wrapping predicts 96–104. **Transparency and distribution are ONE
  mechanism**: `MyRow()` *is* its children, so a modifier on it applies to each,
  because there is no single thing to wrap.

  **What it costs a caller, in three places.** `.padding()` pads **each**
  top-level child rather than the component as a unit — indistinguishable for a
  single-child component, visibly different for a multi-child one, and nothing
  enforces it. **`.background()` does not compile on a component**, deliberately
  (`CO-W`): `Decoration` and `Handlers` are per-*element* state registered in
  each `StyledElement`'s own `prepaint`, with **no per-node table for `setStyle`
  to amend**, and offering it with wrapping semantics beside a distributing
  `.padding()` would be two modifiers that read alike and behave differently.
  The remedy is an explicit `Box`, which is honest about introducing a
  container; the absence is pinned by a `swiftc -typecheck` guard, which is what
  took the guard count **32 → 33**. And **there is no `.id()` modifier**
  (`CO-T`) — that method lives on `StyledElement`, which a component does not
  conform to — so an author who needs a stable name declares
  `var elementID: ElementID? { … }`, which defaults to `nil`.

  **`display: contents` DOES NOT EXIST, and it is what "styled *and*
  transparent" would need (ruling `CO-R`).** `Component` gives transparency to
  something with no style of its own; a styled box that contributes its children
  to its parent's layout as though it were not there is CSS's own primitive and
  this engine has no `contents` case — `public enum Display: Sendable, Equatable
  { case flex, stack, none }`. It was deferred on **scope**, not on merit: it is
  layout-engine work in `collectItems` and the flex algorithm, needs browser
  fixtures, and would be the first thing in three M4 specs to move a golden. It
  is also why `StyledElement` conformance was refused (`CO-Q`) — a `Style` must
  attach to a layout node, `Style.display` defaults to `.flex`, so conforming
  would **force** every component to contribute a real flex container and make
  it layout-opaque, moving every rect in every tree that uses one.

  **That stale site is now FIXED, and the paragraph is kept as the record of
  it.** `Sources/MetalUI/Component.swift`'s type doc said the SwiftUI
  description was "DERIVED from its documented behaviour and is not measured
  here" and said `.padding()` wraps in `ModifiedContent`. Both sentences were
  written **before** either probe ran and neither was walked back to the line
  when they landed — practices mechanism 1 firing inside the milestone that
  cites it. The fix wave corrected both at the line, along with the four sites
  in `docs/superpowers/plans/2026-09-03-component.md` that were the *source* of
  them (two of which were forward-looking instructions to reintroduce the
  refuted design). The measured account is the one above, in the design spec's
  §2 and §5, and in ruling `CO-E`.

  **Two compositions a reader will otherwise meet by surprise, both measured in
  the fix wave and both recorded in the component spec.** (1) **A caller's
  modifier overwrites the component's own internal sizing**: a component whose
  author wrote `.width(30)` on child `a` and `.width(50)` on child `b` renders
  30/50 bare and **70/70** under a caller's `.width(70)`, because every `amend`
  is a plain `=` on one `Style` field and there is no node to nest with the way
  SwiftUI's `.frame()` does. Inherent to distribution, not a defect; §9 of the
  spec carries it. (2) **`Deferred` and `List` reject a component outright** —
  both are generic over `Content: Element` and a component is an `ElementGroup`
  — so `Component` composes with **five of seven** containers (`Box`, `Column`,
  `Row`, `Stack`, `ScrollView` take one), and the two exceptions are the portal
  and the data-driven list, which is where a reusable row is most wanted.
  Verified by `swiftc -typecheck`; spec §7 names both the one-word half
  (`List`) and the real design question (`Deferred` returns `nodes[0]`, and a
  component contributes zero or many).

  **`Component` has NO production caller** — the demo was deliberately left
  alone (`CO-Y`), because `Sources/MetalUIDemo/main.swift` carries every past
  milestone's human-verification criteria and "no rect moved" is a weaker
  guarantee than it sounds when those criteria include things no rect can
  express. So whether the type is *pleasant to write* has no evidence at all,
  and this spec closes none of M4's exit criteria on its own. Decisions doc:
  `docs/superpowers/2026-09-03-component-decisions.md`, rulings prefixed `CO-`
  (**lettered**, `CO-A`…`CO-Z`, so a bare `CO-3` is a typo).

- **`@State` exists, and it is a box seeded by reflection — not a stored value
  in the element struct.** `@State var count = 0` on any `Element` conformer
  holds a `final class Box` with a `StateTable` reference and a slot id; the
  framework seeds both, once per element per frame, in `StateBinder.bind`. That
  indirection is what makes the wrapper possible in public Swift at all —
  `Mirror` hands back *copies* of a struct's stored properties, so it cannot
  write into them, but a copy shares the same box. Reflection is cached **per
  type**, so an element with no `@State` costs a dictionary hit against an
  empty array and no `Mirror` at all past its type's first sighting; an element
  that *does* have one pays a per-instance `Mirror` walk over its children,
  measured at ~2.3 us per stateful element per frame and unavoidable given this
  design.

  **The slot id is `.named("$state\(ordinal)")` under the element's own id, and
  the ordinal is the MIRROR index** — not the position among `@State` children.
  Three consequences a reader will otherwise get wrong:

  - **A hand-written `.id("$state0")` collides with slot 0** (spec §8 risk 1).
    Unlikely, not prevented, and there is no diagnostic. **There are now SIX
    reserved slot names carrying this identical risk, and they are recorded
    together on purpose (ruling `TB-Q`)**: `$state\(n)`, plus `$focus` and
    `$ax`, the two retention slots the tombstones milestone added, plus the
    three the animation milestone added — `$anim`, and `ScrollView`'s own
    `$anim-content` and `$anim-viewport`. **The last two are the first
    reserved names that are NOT one-per-element**, and the reason is worth
    knowing: `ScrollView.requestLayout` registers *two* layout nodes from a
    single element id, so passing that id to `animated(_:_:for:pass:)` twice
    would merge both nodes' baselines into one slot and each node would read
    the other's previous style as its own. Named child ids keep them apart.
    **Four of the six are terminal SLOTS and two are id PREFIXES, and this
    line said all six were slots until it was checked against the code.**
    `$state\(n)`, `$focus`, `$ax` and `$anim` are children of an element's own
    `GlobalElementID` and hold a value. `$anim-content`/`$anim-viewport` hold
    nothing: `ScrollView` passes `scrollViewContentAnimID(for: id)` *to*
    `animated(_:_:for:pass:)`, which then derives `animRetentionSlot(for:)`
    from it, so the value lives at `child(child(id, "$anim-content"),
    "$anim")` — a **grandchild** of the element, one level deeper than the
    other four. **The paragraph's conclusion is unchanged and the hazard is
    exactly as real**: a hand-written `.id("$anim-content")` child mints the
    identical prefix, and that child's own `$anim` slot then collides with
    the `ScrollView` content node's. Only the shape was described wrongly.
    None of the six is
    guarded, and guarding one alone would leave the framework with one
    namespace defended and five open — which reads as though the others were
    safe. **And the
    risk is no longer only an author typing one: a `List`'s DATA can supply
    it.** A row's wrapping `Box` is named `String(describing: datum.id)` under
    the list's id and the `List`'s own AX slot is `"$ax"` under the same id, so
    a datum whose id describes to `"$ax"` mints the identical
    `GlobalElementID`. No live clobber today — nothing stores state under a bare
    row-`Box` id, and a row's own `$focus`/`$state0` slots are children of it —
    but it is a different threat model from a literal in source, because the
    colliding string arrives from data nobody is inspecting. What *is*
    pinned is that the seven cannot collide with **each other**:
    `theSevenRetentionSlotsAreMutuallyDistinct` (`AXNodeTests.swift` — named
    `theThreeRetentionSlotsAreMutuallyDistinct` until the animation milestone's
    Task 3 added `$anim`, its Task 4 fix round added `ScrollView`'s two and
    Task 4b added `$anim-color`, so a citation of any older name — including
    `theSixRetentionSlotsAreMutuallyDistinct` — points at this same test),
    written
    because renaming `"$ax"` to `"$focus"` reddened **0 of 777** while
    silently dropping focus — the `AXNode` clobbers the `Bool`,
    `resolveFocus`'s `peek(…, as: Bool.self)` returns `nil`, and divergence 17
    regresses with nothing able to see it (ruling `TB-R`).
  - **Seeding MARKS, so a `@State` that is declared and never read is never
    swept** (spec §8 risk 3). Deliberate: the alternative silently resets a
    counter whose value a frame happened not to look at. It does mean `@State`
    keeps entries `withState`'s own rule would drop. **"Swept" no longer means
    "deleted", as of the tombstones milestone** — `sweep()` retains an unmarked
    entry's value and only clears its `isLive` flag, and a *reap* (bounded by
    `staleAfterGenerations` and gated on `sweepThreshold`) is what eventually
    removes it. The consequence of seeding is now stronger rather than
    different: a marked slot never goes stale, so it is never reaped either.
  - **The vanishing-`if` hazard reaches ordinary code for the first time**
    (spec §8 risk 2). A `@State` after a conditional sibling adopts the
    vanished element's *value*, because identity is positional and the cursor
    advances one place differently on the two frames. This is a property of
    structural identity, not of `@State` — see the identity bullet above, whose
    remedy (name the **trailing sibling**, not the conditional content) is the
    one intuition gets backwards.

  **A write marks the window dirty and a read does not**, through
  `StateTable.onWrite` → `Window.setNeedsRedraw()`. That hook is the entire
  production mechanism; `StateTable.isDirty` is a test observable with no
  production reader and has a row in the inert table. **Write `@State` from
  input, never from `requestLayout`** — an element that writes its own state
  every frame keeps the window permanently dirty, so the display link never
  pauses, which is milestone 4's exit criterion sabotaged from an element.

  **There is a SECOND hazard with the same ADVICE and the OPPOSITE failure
  mode, and this paragraph described it backwards until 2026-09-03 (ruling
  `RX-S`).** It said an `@Observable` write from inside `renderRoot` "does the
  identical damage" and that "the display link never pauses" — folding the two
  together as "one hazard with two spellings". **Both halves were wrong**, and
  the inverted symptom is the worse of the two: a debugger following that note
  looks for a window that spins, and the real window is asleep.

  Keep them as two hazards:

  - **`@State` written from a phase → permanently dirty, the link NEVER
    pauses.** The bullet above, unchanged and correct. `onWrite` fires
    synchronously at the write, so every frame re-dirties the window.
  - **`@Observable` written from a phase → silently STALE, the link pauses
    IMMEDIATELY.** `withObservationTracking` installs its observers **after**
    the apply closure returns, so a write landing inside the build fires **no**
    `onChange` at all. The window renders the pre-write value, clears
    `needsRedraw`, and idles. Measured in-tree: `observationDirtyings=0`, and
    across 21 ticks `needsRedraw=false`, **0** frames drawn, 21 pauses entered,
    `pauseCalls.last=true`. Standalone, an in-closure write fires `onChange`
    **0** times against **1** for the same write after apply returns. The
    `isFlushing` guard is irrelevant here — nothing fires for it to guard.

  So the two failures are not one: one window never sleeps, the other never
  wakes. **What IS common is the advice, and it is the only part to present as
  shared: write from input, never from a phase.** The `@Observable` case has
  the wider blast radius, a model being shared where a `@State` box is one
  element's — that much of the old paragraph stands.

  **The same mechanism is a standing limitation rather than only an author
  error**, because the unarmed interval is the whole frame build: a *background*
  write arriving in it, after the property has been read, is lost the same way,
  on a path the framework supports and tests. Recorded at
  `markDirtyFromObservation` with both probes and with why it is not fixed in
  code. **It is unpinned by any test** — both measurements are throwaway
  probes, not suite assertions. A pin would have to drive a write from inside
  the tracked closure and assert the window goes clean and stays clean; nobody
  has written it.

  **`@State` inside an `AnyElement` is silently inert** and has its own row in
  the inert table. Decisions doc:
  `docs/superpowers/2026-08-29-input-decisions.md`, rulings prefixed `IN-`
  (**lettered**, `IN-A`…`IN-W`, so a bare `IN-3` is a typo).

- **`@Observable` is a SECOND, independent dirty source, and the tracked region
  is the whole frame build.** As of 2026-09-02 (M4 spec 1),
  `Window.drawFrameIfNeeded` wraps `renderRoot(frame)` in
  `withObservationTracking`, so **any `@Observable` property read anywhere in a
  frame — content closure, `requestLayout`, `prepaint` or `paint` — is a
  dependency of that frame.** No opt-in, no annotations, no registration; the
  framework knows nothing about the model type. That is SwiftUI's semantics,
  taken per ruling EP-5. `@State` keeps its own path unchanged
  (`StateTable.onWrite` → `setNeedsRedraw()`) and the two compose without
  interacting: `StateTable` holds no `@Observable` property, so a `@State`
  write registers nothing with the observation machinery and an observation
  change touches no `StateTable` entry
  (`stateAndObservableAreIndependentDirtySources`). Tracking `paint` too is
  deliberate — a model read only during paint is a real dependency and a
  narrower region would drop it silently.

  **The design spec was WRONG about the cost of doing this, and the sentinel is
  what pays it (ruling `RX-K`).** `docs/superpowers/specs/2026-08-24-metalui-design.md`
  §4.4 calls `withObservationTracking`'s one-shot nature "normally an annoyance,
  here ideal, since we re-register every frame." Measured on a standalone probe:
  re-registering every frame **accumulates one observer per drawn frame per
  unchanged property**, linearly — 1 `onChange` at 1 frame, 10 at 10, 100 at
  100, **1000 at 1000**, no plateau — and **there is no public cancellation
  API**. This framework's common case is the pathological one: scrolling draws
  frames continuously while the document is static. A private `@Observable`
  `RedrawSentinel`, read inside every session and written at the top of each
  frame, fires and thereby *removes* every previously-armed session; the same
  probe then gives **1 at every N up to 10,000**. §4.4 now carries a correction
  block with the original claim visible.

  **Three orderings in `drawFrameIfNeeded` are load-bearing, and one of them
  CANNOT BE PINNED — read that before deleting anything (ruling `RX-G`).** The
  flush sits inside the dirty branch after the guard (flushing before it disarms
  an idle window, which then never redraws); the flush precedes
  `needsRedraw = false` (so the clear absorbs any dirty the flush produced); and
  the sentinel is read *inside* the tracked closure (which is what arms the next
  flush). The second of those is **unpinnable by construction**: with the
  `isFlushing` guard present, moving the clear above the flush changes no
  observable at all, because the flush marks nothing dirty. The guard and the
  ordering are **deliberately redundant — either alone suffices** — so a test
  could only "pin" the ordering by also deleting the guard, which tests a
  two-line mutation rather than an ordering. **Neither may be removed on the
  evidence of a green suite.** What *is* pinned is the guard's own observable:
  `aFrameThatChangesNoObservedPropertyReportsNoObservationDirtying` reports 0
  across 200 frames and **199** with the guard deleted (199 not 200 — frame 1
  has no prior session armed to trip), and
  `theObserverSetIsBoundedRegardlessOfFramesDrawn` reports 1 and **200** with
  the sentinel removed.

  **`markDirtyFromObservation` is `nonisolated` and its SYNCHRONOUS branch is
  load-bearing for the idle criterion, not an optimisation (ruling `RX-N`).**
  `onChange` is `@Sendable` and fires on the mutating thread, so the callback
  re-enters the main actor synchronously when `Thread.isMainThread` and via a
  `Task { @MainActor }` otherwise. Collapsing both to the hop fails **six**
  tests: the sentinel flush's own callback would then land *after*
  `needsRedraw = false`, dirtying the window every frame forever. Collapsing
  both to a bare `MainActor.assumeIsolated` does not redden anything — it
  **crashes the suite with SIGTRAP, signal 5, and no summary line**, reproduced
  deterministically in the full suite and in isolation. That is taxonomy shape
  13 arriving as a live result, and it is why the off-thread branch's "does not
  trap" guarantee is prose in a doc comment rather than an `#expect`.

  **`hasActiveAnimations` DOES NOT EXIST, and a reader of §4.4 should not go
  looking for it (ruling `RX-O`).** That section's guard reads
  `needsRedraw || hasActiveAnimations`; M4 spec 1 implements the `needsRedraw`
  half only. `grep -rn "hasActiveAnimations" Sources/` returns **0**.
  Deliberate: an always-`false` stored property with no writer is exactly the
  declared-but-inert trap the table below exists for, so M4 spec 3 introduces
  the property, its `prepaint` registration site, the display-link timebase and
  both widened conditions **in one change**.

  **`Window.pausesEntered` and `Window.observationDirtyings` are debug and test
  observability and deliberately have NO row in the inert table (ruling
  `RX-R`)** — both have a production writer, a production reader in
  `Sources/MetalUIDemo/main.swift`'s exit summary, and test readers. They are
  deleted in the same change that lands a real profiling story. Decisions doc:
  `docs/superpowers/2026-09-02-reactivity-decisions.md`, rulings prefixed `RX-`
  (**lettered**, `RX-A`…`RX-R`, so a bare `RX-3` is a typo).

- **There is ONE hitbox list, and a scroll region is a hitbox with an axis
  attached.** `Frame.hitboxes` is the only stored registry: wheel routing,
  hover, active and click dispatch all rank against it with **one** copy of the
  ordering — `topmostOpaqueHitbox(in:at:)` in `Hitbox.swift`, a filter to the
  opaque records containing the point plus a `.max` by `(layer, registration
  index)`. There were three copies and two lists before this milestone folded
  them. **Do not add a fourth.** `Frame.scrollRegions` and
  `Window.lastScrollRegions` survive as get-only derived views with **zero**
  production readers, which is why they have a row in the inert table.

  **`onClick(_:)` is what makes an element a hit target, and the gate is the
  load-bearing half.** A `Box` with no handler registers nothing, so it is
  transparent to the pointer *and* does not swallow the wheel of a `ScrollView`
  it sits inside. Deleting `guard handlers.isPointerTarget else { return }` from
  `Frame.registerHandlers` reddens **25 tests / 40 issues** — 10 of them in
  `ScrollRoutingTests`, 3 more in `ScrollIndicatorTests`, and the rest spread
  across `InputDispatchTests`, `FocusTests`, `KeymapTests`, `HitboxTests`,
  `PointerStatePaintTests` and `NestedClipTests`. An always-registered container
  hitbox outranks the scroller beneath it and stops every `ScrollView` in the
  framework scrolling. **Re-measured at this milestone's last commit rather than
  quoted**: this sentence read "17 tests, fourteen of them scroll-routing" until
  then, which was the figure at suite 644, six tasks earlier — the exact
  staleness the practices doc's third record-mechanism is about, committed in
  the same change that added that mechanism.

  **The pointer gate and the keyboard gate are SEPARATE and must stay so.**
  `Handlers.isPointerTarget` is `onClick` alone; `Handlers.isKeyTarget` is
  `onKey || isFocusable || !actions.isEmpty || keyContext != nil`. One combined
  gate would make every focusable element an opaque hitbox — and a list of
  focusable rows would stop scrolling. Pinned by
  `focusabilityAndKeyHandlingRegisterNoPointerHitbox`.

  **Hover resolves once, at the prepaint/paint boundary**, so
  `PaintPass.isHovered` has no one-frame lag and every element in a frame sees
  the same answer whichever asks first. Two spellings: `isHovered(HitboxID)` is
  the precise one, `isHovered(GlobalElementID)` is what a `StyledElement` can
  actually reach, because `registerHandlers` returns no index. `isActive` and
  `isFocused` are `GlobalElementID`-keyed because both outlive a frame. **All
  four are paint-only and each has a `swiftc -typecheck` guard**, and the guards
  do **not** rest on one footing: three are measured lies, `isActive`'s is
  placement insurance, and each of the three whose justification is *contingent*
  now names what would make it deletable. The header block above them in
  `PhaseSeparationTests.swift` categorises all four; a fifth query gains a
  bullet there in the same change that adds its guard.

  **Two spellings need two probes, and the reason is narrower than it first
  looks — measured, after the first version of this sentence claimed otherwise.**
  Adding *only* the `GlobalElementID` overload to `PrepaintPass` does **not**
  leave the older `HitboxID` guard green: that guard fails, but on one assertion
  of two. Its `!result.succeeded` still passes (the `HitboxID` probe still does
  not compile) and only its message assertion breaks, because the diagnostic
  becomes `cannot convert value of type 'HitboxID' to expected argument type
  'GlobalElementID'`. So it reports the hazard as **its own probe having become
  ill-typed** — a tripwire — while the element-keyed guard fails on both
  assertions, which is the detection. The suite is not silently green either
  way; what the second probe buys is a red that *says what is wrong*.

- **`StyledElement` has a FOURTH requirement: `var handlers: Handlers`.**
  `style`, `decoration`, `elementID`, `handlers` (ruling IN-H). It is a
  requirement rather than a defaulted extension property on purpose — a default
  of `{ get { Handlers() } set {} }` lets a conformer that stores nothing
  compile, and `.onClick { … }` on it would return an element with the handler
  thrown away. Storing it is still only half the job: a conformer must also
  call `PrepaintPass.registerHandlers(_:at:id:)` in its own `prepaint`, which
  nothing can enforce; `onClickIsLiveOnEveryConformerThatCanRegisterOne` is the
  guard, one case per conformer.

  **`Handlers` holds escaping closures, so it is NOT `Equatable`, and that has
  already cost one coverage gap.** `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`
  compares the other three stored values by whole-value equality and projects
  this one through a hand-built `HandlerShape` in `ModifierTests.swift`.
  **That projection must gain a field in the same change `Handlers` gains a
  member** — it did not, once, and `onAction(_:_:)` and `keyContext(_:_:)`
  escaped the table entirely for a whole task while its own comment still said
  "three members". Both mutants (a `keyContext` that also set `isFocusable`, an
  `onAction` that also registered a pointer hitbox) were green.

  **A handler outlives the frame that built it.** `Window.lastHitboxes` retains
  the most recent frame's closures for the window's lifetime and nothing clears
  it, so `.onClick { window.doThing() }` is a retain cycle the API surface
  cannot diagnose. `Window.onAction` is the sharper form — that closure is
  stored *on* the window, so a cycle closes with no frame drawn at all. Capture
  `[weak window]`, or capture the state the handler writes, which is what
  `@State` is for.

- **Focus is a tree registered in prepaint, and NOTHING focuses anything on its
  own.** `Window.focus(_:)` is the only mover — clicking does not focus (ruling
  IN-N), which is what lets a keymap binding work with nothing focused at all.
  A key event bubbles the focused id's **own parent chain** outward, with no
  second tree to keep in sync: structural identity already bought a persistent
  parent link. `Frame.resolveFocus()` clears a focused id that is produced this
  frame and has stopped being `.focusable()`, at the prepaint/paint boundary —
  so giving up `.focusable()` reads as unfocused on the very frame that drops
  it rather than one frame late.

  **That sentence used to say "clears a focused id this frame did not produce",
  and the "did not produce" half EXPIRED on 2026-09-01.** An id that is not
  produced no longer clears: it falls back to `StateTable`'s retention through a
  dedicated `$focus` child slot, which is how divergence 17 was retired
  (ruling `TB-J`). The two branches are kept apart by a second signal,
  `focusedElementProducedThisFrame`, set independently of
  `handlers.isFocusable` — collapsing them reddens
  `anElementThatStopsBeingFocusableLosesFocus` and two other tests, which is
  what makes the distinction load-bearing rather than incidental.

  **Three consequences of that fallback, and the first two are the ones nobody
  designed in.** All three measured through a real `Window` on 2026-09-02.

  - **Focus on a permanently-removed element is retained INDEFINITELY below
    `sweepThreshold`.** Focus an element behind an `if`, remove it, render
    **60** more frames: `window.focusedElement` is still that id. It never
    becomes `nil` on its own, because the reap that would drop the `$focus`
    slot only runs once the table exceeds 256 entries — the same
    unbounded-below-the-gate behaviour divergence 18 records for `@State`.
    Intended, per design spec §5's "one notion of still exists, not two"; the
    *indefiniteness* is the part the spec did not say.
  - **The dismissed subtree's still-produced ANCESTORS keep claiming its
    keystrokes.** `focusChain(from:)` walks the retained id's parent chain, and
    those ancestors are produced and registered, so an ancestor's `onKey` and
    its `keyContext` stay live for a subtree the user dismissed. Measured: with
    a root carrying `onKey`, a keystroke after removal logs **`["ancestor"]`**
    where before this milestone it fell through to `Window.onInput`. **Nothing
    pins this, and the reason is an accident worth knowing**:
    `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow` asserts
    `raw == ["window"]`, which reads as "the event reaches the window" — but
    only because that fixture's ancestors happen to carry no `onKey`. It is
    untested by coincidence, not by design, and a fixture whose root had one
    would show the ancestor claiming it.
  - **Focus is RESTORED on return, which is the intended half.** Same shape,
    60 absent frames, bring the element back: `focusedElement` is still it and
    its own `onKey` runs again (`["child"]`). That is divergence 17's closure
    working.

  **A boundary on all three, and it is easy to trip over: retention needs a
  CONFIRMING FRAME.** The `$focus` slot is written by `registerHandlers` only
  while the focused id is actually being produced, so `Window.focus(x)` followed
  by removal *with no frame rendered in between* retains nothing — focus clears
  and the ancestor claims no keystroke. Measured by getting it wrong first: a
  probe that skipped the confirming frame reproduced none of the three
  consequences above and looked like a refutation of them.
  `focusSetWithNoConfirmingFrameHasNothingToRetain` is the pin.

  **A keystroke resolves against the window's `Keymap` FIRST and reaches a raw
  `onKey` only if no binding matched.** Keymap as declaration of intent, raw
  handler as escape hatch; swapping them makes every raw handler shadow every
  binding on the same keystroke. A bound keystroke becomes an `Action` **type**
  that bubbles the same chain to the first element handling *that* type — and
  **an action nobody handles does not claim the keystroke**, so binding a key
  and forgetting the handler falls through to `onKey` and `onInput` rather than
  silently eating it. Context predicates (`context: "Editor"`, `"!Modal"`) are
  matched innermost-first against the contexts the *chain* contributes, and a
  context is contributed by **any** element, focusable or not. A malformed
  predicate is a visible parse failure (`nil`), never a trap and never an
  indistinguishable `false`.

  **Focus is drawn with `focusBackground(_:)`, a token swap, and there is no
  ring** — `Frame.fill` hard-codes zero border widths, so nothing above the
  renderer can draw a border at all. `hoverBackground(_:)` is its pointer-side
  twin, and **focus outranks hover** where both apply (ruling IN-V). Both are
  inert on their own: a `hoverBackground` with no `onClick` registers no hitbox
  and never resolves as hovered; a `focusBackground` with no `focusable()` and
  nothing moving focus never paints.

- **`Text` measures and draws, and three things about it are load-bearing.**
  M2 landed `MetalUIText` (CoreText, no Metal), a shaping cache and a glyph
  atlas on the `Window`, and a `Text` element that attaches a
  `MeasureFunction` through `newLeaf` — the framework's first production leaf.

  - **Nothing may be keyed on a font family or PostScript name** (spec §6.1 and
    §3.2 — a design decision, not a ruling): requesting `"SFMono-Regular"` by name on the
    machine this was measured on returns a font whose PostScript name is
    `Helvetica`. `FontKey` identifies the *resolved* `CTFont`, variation
    coordinates and matrix included, and the atlas key adds `size`,
    `subpixelVariant` and `scaleFactor`. A key collision is one of three
    failure modes **no assertion in this repo can see** (spec §4.2) — the
    others being a missing subpixel variant and eviction mid-frame — because
    the CPU and the GPU agree on a wrong answer together.
  - **Min-content is the longest WORD, and it does not come from the
    typesetter** (ruling TX-F). `CTTypesetterSuggestLineBreak` breaks *inside*
    a word it cannot fit, so "typeset narrow and take the widest line" answers
    the widest **character** — 11.489 against CSS's 110.348 on the sample in
    `Shaper.unbreakableRuns`. `CFStringTokenizer(kCFStringTokenizerUnitLineBreak)`
    is the width-independent API that gives the right answer, and ruling TX-G
    records that it also removes M6's reason for a hand-rolled UAX #14 subset.
  - **The corpus has no text fixture and must not gain one** (ruling TX-B).
    WebKit shapes with its own font stack, so a text golden would pin the
    browser's typography rather than this engine's rule. A moved golden on a
    text change therefore means something reached the engine's *container*
    path — stop and report, do not regenerate.

