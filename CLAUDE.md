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
  `docs/superpowers/2026-08-30-sizing-decisions.md` — each ruling with
  its reasoning and what it costs if wrong. Read the "Carried..." sections before
  starting new work.

  **Ruling IDs are namespaced by milestone.** `PF-3` and `C-3` belong to m1a;
  `FS-n` to flex sizing, `AL-n` to alignment, `BM-n` to the box model, `WR-n` to
  wrapping, `EP-n` to the element pipeline, `CS-n` to content sizing, `SI-n`
  to structural identity, `TX-n` to text (M2), `CL-n` to clipping and scroll,
  `ST-n` to the stack container, `AP-n` to absolute positioning, `MP-n` to
  measure-path performance, `IN-n` to `@State`/hit testing/input dispatch and
  `SZ-n` to the sizing milestone that closed BM-4, FS-3 and TX-H (the last
  nine are
  **lettered** — `CS-A`…`CS-O`, `SI-A`…`SI-H`, `TX-A`…`TX-J`, `CL-A`…`CL-F`,
  `ST-A`…`ST-G`, `AP-A`…`AP-M`, `MP-A`…`MP-N`, `IN-A`…`IN-W` and `SZ-A`…`SZ-O`
  (**`SZ-A`…`SZ-N` until the sizing milestone's whole-branch fix wave added
  `SZ-O`, the propagation regression TX-H shipped** — same shape as the `MP-L`
  note below, so a citation of `SZ-O` is real)
  — so a bare
  `CS-3`, `SI-3`, `TX-3`, `CL-3`, `ST-3`, `AP-3`, `MP-3`, `IN-3` or `SZ-3` is a
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

  - **`cachedHash` and `==` are safe individually and unsafe only together.**
    Dropping the parent from the hash reddens exactly one test; a hash-shortcut
    `==` reddens nothing; do both and two unrelated elements silently share a
    `StateTable` entry. The load-bearing line is **`==`'s chain walk**, which no
    test can guard — a 64-bit collision is not constructible against a
    per-process-seeded `Hasher` — so the mechanism is stated at `==` per
    taxonomy shape 6. Do not "simplify" it on the evidence of a green suite.

  **Tombstones and exit transitions are untouched** by this: §4.3 still records
  that AX identity needs entries surviving the sweep as invalid-reporting
  tombstones and that exit transitions are impossible until that exists.
  Universal identity makes tombstones *more* useful and no easier — it is a
  change to the **sweep**, not to the key.

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

  **What it costs is FOUR divergences, 12, 13, 14 and 17 below** (it was three
  until focus existed): a row's own `StateTable` state is reaped while it is off
  screen (its *identity* is what survives, not its state), the window is
  computed against a one-frame-stale viewport extent, the window is placed
  against the scroller's origin rather than the list's own, and — 17, added by
  the input-and-state milestone — a **focused** row scrolled out of the window
  loses focus and does not get it back. 17 is the worst of the four for one
  reason: `@State` is recoverable from the datum and focus is not.
  `Sources/MetalUI/List.swift`; decisions docs
  `docs/superpowers/2026-08-28-measure-performance-decisions.md` (`MP-`) and
  `docs/superpowers/2026-08-29-input-decisions.md` (`IN-M`).

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
    Unlikely, not prevented, and there is no diagnostic.
  - **Seeding MARKS, so a `@State` that is declared and never read is never
    swept** (spec §8 risk 3). Deliberate: the alternative silently resets a
    counter whose value a frame happened not to look at. It does mean `@State`
    keeps entries `withState`'s own rule would drop.
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

  **`@State` inside an `AnyElement` is silently inert** and has its own row in
  the inert table. Decisions doc:
  `docs/superpowers/2026-08-29-input-decisions.md`, rulings prefixed `IN-`
  (**lettered**, `IN-A`…`IN-W`, so a bare `IN-3` is a typo).

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
  parent link. `Frame.resolveFocus()` clears a focused id this frame did not
  produce, at the prepaint/paint boundary — so an element that vanishes, *or*
  stops being `.focusable()`, reads as unfocused on the very frame that drops
  it rather than one frame late.

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

## Practices

**`docs/practices/verifying-tests-can-fail.md` — read this before writing tests.**

For three milestones, every defect found during execution was in a plan, a spec,
a test or a comment — **none in an implementation**. **The box-model milestone
ended that**: three real engine bugs, all of them found by mutation or by a new
fixture's first generation, none by reading the code. Two were margin
compositions (reverse × margins, stretch × margins); the third was percentage
insets resolved against the wrong box, which had been green through two whole
tasks. What did not change is *how* they were found — essentially every finding
across all four milestones came from **mutation, not inspection**.

The flex-sizing milestone alone produced nineteen findings, four of them the same
shape: a fixture too uniform to distinguish the thing it claimed to pin. Before
committing a fixture, change the declaration it is named for — a percentage to a
pixel, an inset to 0 — regenerate, and confirm the numbers move. That document
catalogues **fifteen** shapes of test that cannot fail, all observed in this repo,
plus the method for finding them and the cases where adding a test is the wrong
answer. Count the `### <n>.` headings rather than trusting that number
(`grep -cE "^### [0-9]+\." docs/practices/verifying-tests-can-fail.md` reads 15) —
a bare `grep -c "^### "` reads **18**, because **three** sections in that document
are unnumbered. Both numbers have now moved twice: the input-and-state milestone
added shape 14 and one unnumbered section (13 and 15 before it, unnumbered count
2 before that), and the sizing milestone added shape 15 — "a benchmark of a
configuration in which the code under test is unreachable", found while
measuring TX-H's own cost (ruling `SZ-N`) — with no change to the unnumbered
count.

**Shape 15 then fired AGAIN inside the same milestone, in its whole-branch fix
wave, on an unrelated question — which is the argument for it being a shape
rather than an anecdote.** The wave set out to settle whether the demo's
sidebar squeeze is a divergence by measuring the same declaration in both
engines. Its first probe gave the main pane no content, so nothing forced the
sidebar to shrink and **both engines answered 196 in both the `flex-shrink: 1`
and `flex-shrink: 0` arms** — a clean, symmetric agreement that says nothing,
because the mechanism under test could not fire. With a demanding sibling the
arms separate (69/69 against 196/196) and the question is actually answered.
The discriminator generalises past benchmarks: **require the arms of a
comparison to DISAGREE before believing that they agree.**

**And that wave produced a fresh instance of the practices doc's second
record-mechanism — "a fix round is exactly as capable of producing an
unmeasured claim as the round it fixes".** A doc comment written for one of
its new pins asserted that removing `align-content: flex-start` "leaves it
green under the pre-SZ-O engine". Running that mutation instead of re-reading
it gave **295**, not green: under the default `stretch` the two lines absorb
the container's leftover space and the engines still differ, by half the
error. The claim was corrected at the mutated line in the same pass, which is
the doc's first mechanism doing its job on top of the second.

The recurring lesson of the last two tasks has a sharper form: **a feature that
works alone and a feature that works alone can be wrong together.** All three
engine bugs above lived in a composition that existed in the engine and in no
fixture. When you implement something, ask what it now composes with, and check
that pair against the browser.

**The wrapping milestone's third task is the counter-example that proves the
method rather than the streak.** It committed eleven composition fixtures at
once and every one of their goldens matched the engine on first generation — no
engine bug. But of the sixteen sibling-swap differentials their comments
claimed, **four were wrong**, every one of them hand-derived; running the swaps
through the live oracle is what caught them. "Change the declaration and confirm
the numbers move" is not satisfied by predicting which numbers move. Run it.

**Structural identity added two variations, both about the record rather than
the code.** First, **"pinned as deliberate" is a claim to grep for, not to
believe**: a plan's risk list and a spec section both asserted the vanishing-`if`
behaviour was already pinned, and no test pinned it — one inaccurate sentence
standing in for two claimed pins, and the behaviour it described (reset) was not
the behaviour the code had (adoption). Second, **a mutation count measured
mid-task is stale by the end of the task** (ruling SI-H): three of this
milestone's five recorded counts were taken before a fix round added two tests
sensitive to the same line, and each under-counted by exactly those two. The two
that survived re-measurement were the two that **named** the tests they reddened
instead of only counting them — which is CS-N's rule with a reason attached.

**The text milestone added two shapes and sharpened the method itself.**
**Shape 12, "the oracle is the code under test"** — four instances on one
branch, the sharpest of them inside a *byte-exact per-pixel* comparison of a
real drawable that indexed into the atlas through the sprite's own
`atlasBounds`, so a one-texel source shift left it green. It reads as the
strongest assertion in its file. The generalisation is the part to carry: **a
hand-built fixture escapes this and production-built input does not** — the
earlier version of that same test built its sprites by hand and had no problem,
and the hazard arrived exactly when the test was made more end-to-end.
**Shape 13, a test whose own structure truncates the suite**: `#expect` records
and continues, so a wrong implementation returning fewer elements sent the next
loop past the end of its own array — `Index out of range`, **no summary line,
~200 tests never run.** A wrong implementation truncated the run instead of
reddening it. The rule is one word wide: **any count a later loop indexes on
must be `try #require`, not `#expect`.** And **a mutation that reddens nothing
is a broken instrument or it is the finding** — three of each on that branch,
so the discriminator (prove the mutant behaves differently before banking a
coverage gap) is now written into the method section.

**And its fix round produced the branch's only taxonomy-shape-9 pair**, found by
mutating every line of new code rather than by reading any of it: `EitherGroup`'s
`cursor += 2` and `AnyElement`'s `cursor += 1` each reddened **nothing** on a
358-test suite while being asserted as a property in two documents apiece. Both
now have a test. The `+= 2` one carries the sharper lesson: **the composition the
stated property suggests does not fail.** `Row { if flag { C() } else { C() };
C() }` keeps the trailing element's state under `+= 1` — the cursor advances
before the branch is chosen, so the shift is identical on both frames. Only a
sibling that lands on the *untaken* slot and then goes one level deeper breaks,
which took three candidate compositions and a probe to find. The property the
comment claimed was not the property the line bought.

**The measure-performance milestone added one shape and one method, both about
performance work specifically.** The method: **write the counting assertions
first and require them to be RED on arrival.** Two of that milestone's three
harness assertions failed the day they were committed — and **they did not go
green together, which is the part to state precisely**: the tokenizer-count one
went green at the memo task, and only the "a 160-row list costs what a 40-row
one costs" assertion stayed red through four tasks, until windowing. That one
is the only reason anyone can say the windowing task did anything — a
performance test written after the optimisation cannot distinguish "fast" from
"measuring the wrong thing". Crediting both to the last task is the same shape
of error this milestone started from: a true sentence about one half, read as a
claim about both. They count work (tokenizer calls, cache
entries) rather than timing it, so they fail identically on a loaded CI box
where a committed millisecond baseline would flake. The shape: **a test can be
inert because the FIXTURE cannot express the defect, not because the assertion
is weak.** That milestone's drafted cache-growth test swept the outer frame's
width over a fixture whose every internal width is pinned, so the cache reached
a warm-up value and then read byte-identically forever — measured
`distinct=[207]` across 120 frames **with no bound and no sweep implemented at
all**. It passed against a stub. The assertion was fine; the fixture could not
move the key the assertion read. Ruling `MP-J` carries it.

**The input-and-state milestone added one shape and three mechanisms, and every
one of the four is about the RECORD rather than about a test.** The shape is
**14, "a confident wrong reason closes the question before it is asked"**: a
report asserted two new modifiers "cannot" be covered by
`everyPublicModifierWritesItsOwnFieldAndOnlyThatField` because `Handlers` is not
`Equatable` — true — and concluded no test was possible, which is false, since
`HandlerShape` in that same file had solved exactly that two tasks earlier.
Nobody looked, because the reason sounded finished. Both modifiers shipped
uncovered and both mutants stayed green. **The precedent it repeats already
existed in this file, in the now-retired divergence 5 (ruling FS-3)**: a
task's report claimed `.minWidth(_:)` "has no equivalent escape" for a demo
`ScrollView` wrapper, when `.minWidth(_:)` existed and the real blocker was
`ScrollView` having no modifier surface at all — a stated reason wrong in two
directions at once while its conclusion happened to be right. (The correction
now lives at `Sources/MetalUIDemo/main.swift`, where the wrapper is declared,
since divergence 5's own entry is gone.) The tell is a **"cannot" that was not
measured**.

The three mechanisms are new sections under "The method" in the practices doc,
and each cost a round of rework:

1. **A measurement recorded in the report is not a measurement applied to the
   source.** Three consecutive tasks shipped a comment their own report
   contradicted *in the same commit* — the report became where true things went
   while the comment kept its draft-time belief. The rule is one sentence wide:
   **anything a mutation teaches must be walked back to the mutated LINE in the
   same pass.**
2. **A fix round is exactly as capable of producing an unmeasured claim as the
   round it fixes.** The first attempt at pinning a one-second timeout shipped a
   test whose doc said it pinned the `>` comparison and did not — `>` and `>=`
   agree at 0.999 and 1.001. Re-reading the code did not catch it; running the
   mutation the claim implied did.
3. **Staleness is systematic, not local — re-take the whole table.** An
   amendment to `SI-H`. A reviewer flagged two stale mutation rows; re-taking
   *everything* found a third they had not sampled, and a fourth that had moved
   for a better reason. A review samples; a count taken before the last test
   landed is stale across everything measured in that window.

**And the milestone's own best evidence for the method is a ruling that was
answered the OPPOSITE way from how it was framed.** A brief deliberately left
open whether `isFocused` needed a phase guard and *forbade* adding one by
symmetry with `isActive`'s. Measuring it found that a prepaint-time `isFocused`
really does lie — and, incidentally, that `isActive`'s guard is **not** the
measured lie its shared comment claimed, since `Frame.activeElement` is a `let`.
A prohibition aimed at preventing a bad addition surfaced a pre-existing false
justification. Forbid the reasoning shortcut, not only the outcome.

## Verified on real hardware

`swift run MetalUIDemo` was run and inspected on a Retina display: the window
shows the centred rounded rect with its antialiased border, and the close button
quits the process.

**Text verified on 2026-08-28 — M2's exit criterion, and the only check no test
here can perform.** A human ran `swift run MetalUIDemo` and reported it looks
right: the sidebar label, the 22pt heading and the wrapping paragraph all render
legibly, and the paragraph re-wraps at word boundaries when the window is
resized.

**The look was directed rather than general**, because §4.2 of the M2 spec names
three failure modes no test in this repo can see — a wrong glyph from an atlas
key collision, fuzzy or wobbling text from a missing subpixel variant, and
intermittent blank runs from eviction during a frame. **Two of the three remain
unchecked and it is worth knowing which**: wobble needs sub-pixel *motion* and
neither a static look nor a screenshot can show it, and eviction blanks are
absent by construction in M2 rather than tested, since nothing calls
`evictUnusedSince`. The cross-*family* key collision is also unexercised — the
demo uses one font family.

**A second look followed the line-height change** (`ceil(ascent + descent +
leading)`, 15.3105 → 16.0 at 13pt): the leading now reads correctly against
typical Mac apps, which is what prompted the change. Whether the pixel-alignment
argument for rounding is *visible* was not established either way.

**Re-verified on 2026-08-27 after ruling EP-8 made `Column`/`Row` centre on the
cross axis**, because that ruling's failure mode is an *invisible rectangle* and
no test in this repo can see one: a human ran the demo and reported it looks
right — nothing vanished, the sidebar rows and the separator still fill their
containers through their new explicit `.alignItems(.stretch)`, and resize and the
light/dark toggle still work.

**That was M0's demo, and it is not what `MetalUIDemo` draws today.** The demo
was replaced by the element pipeline's — a four-level nested flex layout of
themed, rounded, background-filled boxes with a light/dark switch — and **it was
run and inspected by a human on 2026-08-26, who reported it works as expected**:
the nested layout renders, it reflows live while the window is dragged, and the
light/dark switch works. That closes milestone 1's exit criterion. Two specifics
of the M0 sentence above are stale rather than wrong: the rect it describes was
inserted as an `MUIRect`
directly, through an `App.openWindow` overload that no longer exists,
and **no element can draw a border at all.** `Frame.fill` is the only production
path into a `Scene` and it hard-codes `borderColor: .transparent,
borderWidths: 0`; the blocker is the resolved *width*, not the colour, and it is
recorded at `Frame.fill`. The renderer primitive still supports borders — M0's
demo is the proof — but nothing above the renderer can ask for one.

**What the human check establishes is a property of `AppKitPlatform`, not of
what the demo draws — and no test can establish it.** `MetalLayerSurface` vends drawables whether its `CAMetalLayer` is
attached to the view or orphaned, so reversing the `layer` / `wantsLayer`
assignment order in `AppKitPlatform` renders perfect pixels into a texture nobody
sees — and the whole suite still passed when that was measured, at 342 tests
(**739 today**; the count is quoted so the measurement can be dated, not because
342 is a property of anything). If you touch that ordering, re-run the demo
and look at it; the suite will not tell you.

**What the machine established about text before that look, and it is a
different thing from the look.** A `Text("Hi Wag")` at 22pt rendered through a
real `Renderer` into a real `Window`'s drawable and read back produces
**legible glyph shapes in the right order at the right advances** — the readback
was printed as ASCII art and the word was readable. That rules out the gross
failures (nothing drawn, every glyph stacked, the atlas sampled at the wrong
scale) and rules out none of §4.2's three, which is why the human look above is
the exit criterion and this is not. The assertable half of that technique is
kept as a test — `theWindowsPixelsAreExactlyTheGlyphBitmapsItsSpritesStandFor`,
which compares every unambiguously covered byte of the drawable against the
glyph's own rasterized bitmap — and its doc comment names the three failures it
still cannot see, and why each one hides from it.

**A race the whole-branch review found, now closed — and the way it is closed is
the part to know before touching the renderer.** `Window.drawFrameIfNeeded`
commits a frame's command buffer and never waits; there is no semaphore on the
live path (`grep -n "waitUntil" Sources/` finds one line, in
`Renderer.renderOffscreen`, which is test support). `renderer.upload` used to
`texture.replace` **in place** on the persistent `.shared` atlas texture, so the
frame that packed a new glyph wrote pixels the previous frame's draw could still
be sampling — one torn glyph, intermittently, on exactly a resize or a
font-size change. The atlas was the only resource exposed to this: everything
else `encode` binds is a fresh per-frame `makeBuffer`.

**The fix is an invariant, not a lock**: `Renderer.atlasTextureWasEncoded` is set
when the texture is bound, and a texture is written only while that is `false`.
A dirty upload after an encode therefore allocates a *replacement* and fills it
from the whole atlas; the old object stays alive as long as the in-flight command
buffer retains it, which is Metal's job. Steady-state frames allocate nothing —
that is what the `dirtyRect != nil` conjunct in `upload` buys, and dropping it
churns a full atlas per frame.

**What is tested is the invariant, not the race** — the race is a GPU-timing
window and `renderOffscreen` waits, so nothing here can reach it, exactly as with
§4.2's three. `aDirtyUploadAfterEncodingReplacesTheTextureRatherThanWritingIntoIt`
pins both halves (the texture is replaced, *and* the replacement carries the
whole atlas), and four mutations redden it and nothing else. **Spec §4.2 does not
list this failure class**, which is worth knowing because that list is the basis
on which M2's risks were accepted — it was three, and the true count of things
that can produce a wrong glyph with no assertion able to see it was four.

**A thing no test can establish, and this one is a live release trap.**
The `MeasureFunction` a `Text` attaches (`Text.requestLayout`) reduces to
`SizeD` inside `MainActor.assumeIsolated`, because the shaping cache is
`@MainActor` and a `ShapedText` may not cross an isolation boundary. That is
sound **only because `computeLayout` runs synchronously inside
`Frame.computeRootLayout`, which is `@MainActor`** — the engine is non-isolated
code executing on the caller's thread, not a hop. Drive layout over a tree
holding a text leaf from **any other executor** — a background actor, a
`Task.detached`, the 4 MB worker thread `LayoutContext`'s depth test already
spins up — and `assumeIsolated` terminates the process. Nothing in the repo can
notice: every existing off-main-actor layout builds its own leafless tree, and
a test that got this wrong would crash the run rather than redden. If layout
ever moves off the main actor, the measure closure is the first thing to
rewrite.

**Clipping and scroll verified on 2026-08-28 — this milestone's exit criterion,
and it took three looks to close.** A human ran `swift run MetalUIDemo` and
reported, on the third: scrolling works as expected with no intermittent issues,
and the scroll indicator is correctly clipped by the container's rounded corner.

**The first two looks each found a defect nothing in the 501 tests could see,
which is the entire argument for this section.**

1. **Odd text wrapping in the list rows.** Chased to a mechanism recorded as
   **divergence 8**, and it was PRE-EXISTING — measured byte-identical at this
   branch's base `ba22e4a` with no `ScrollView` in the probed tree. The branch's
   only contribution was putting 40 shrink-wrapped strings on screen at once,
   turning a per-string coin flip into something unmissable. **FIXED on
   2026-08-30 and divergence 8 is retired** — `Text.paint` wraps at the width
   layout measured at rather than re-deriving one from the rounded box.
   Re-measured on this exact shape: **31 of these 40 rows wrapped before the fix
   and 0 after.** The entry is gone from the divergence list; label 8 is retired
   and never reused, and the retirement is recorded in that section's header.
2. **"The ScrollView is not rounded, it has hard edges"**, then **"the scroll bar
   is painted outside the corner"** — both real, both fixed here (`f081b9d`,
   `55ed142`). The first exposed a contradiction in this milestone's own spec:
   §1 scoped rounded clip corners *out* while §3.1 justified choosing a fragment
   mask over `[[clip_distance]]` *because* it could clip a rounded container. The
   mechanism was chosen on a capability the same document excluded.
3. **"Scrolling stopped working intermittently."** The offset was clamped on
   *read* and unbounded on *write*, so overscroll banked an invisible dead band
   and reversing events spent themselves unwinding it (`19f55f7`). Measured: 20
   events of −37 into 80pt of real travel stored **740**, and 17 of the next 20
   reversing events moved nothing. Chasing it found a second defect the human had
   not reached yet — the indicator never appeared after ~1s idle, because its fade
   clock was stamped from a display-link timestamp that freezes while the link is
   paused (`329fa04`).

**What the look established that nothing here can: scroll direction.**
`Window.applyScroll` subtracts the delta, and AppKit folds the user's
natural-scrolling preference into that delta's sign — every test pins the
arithmetic against a synthetic delta whose sign the test itself chose. Only a
human on a real trackpad can say which way the list actually moves. The human
also reported that apparent tearing was the wrapping rather than real tearing.

**What it did NOT establish, and these stay looks forever by construction**
(`docs/superpowers/specs/2026-08-28-clipping-and-scroll-design.md` §9): clip-edge
antialiasing *quality*, whether the fade *timing* feels right, and whether
scrolling feels native. A positive report closes the exit criterion and closes
none of those three.

**Stack's layering was confirmed on 2026-08-28 from a RENDERED READBACK, not
from the running app, and the distinction is the point of this entry.**
`Sources/MetalUIDemo/main.swift`'s main pane now opens with a `Stack` in place
of the plain accent hero box: a 360×128 backdrop, a 160×72 panel and a 28×28
numeral badge, centred on one another and declared back-to-front.

**What was actually checked.** A throwaway harness built that same `Stack`,
drove it through a real `Frame` and a real `Renderer.renderOffscreen`, wrote the
BGRA readback to a PNG, and a human looked at the image and confirmed it matched
expectation. The geometry it produced, at scale 2: backdrop `(100, 72) 720×256`,
panel `(300, 128) 320×144`, badge `(432, 172) 56×56` — all three concentric on
`(460, 200)` — in two draw runs, the glyph last.

**That readback was real evidence about z-order and it was NOT the exit
criterion.** It goes through the production `Scene`, draw list and shaders, so an
inversion would have shown. But `renderOffscreen` is the same instrument M2's
ASCII-art glyph readback used, and this file already records that such a readback
"rules out the gross failures and rules out none of §4.2's three". What it could
not see: compositing against the rest of the window, the layer's Display P3
colorspace (divergence 1 — colours render more saturated than the hex implies),
and the appearance at a real display's scale factor.

**The exit criterion is now CLOSED, by a look on 2026-08-28.** A human ran
`swift run MetalUIDemo`, was asked to look at one specific thing — the `Stack`
hero's z-order, the badge on the panel and the panel on the backdrop — and
reported it looks good.
`docs/superpowers/specs/2026-08-28-stack-container-design.md` §7 item 8 is
**closed**.

**What that look established, and it is the three things the readback could
not.** Z-order observed **through the real window** rather than through an
offscreen texture: composited against the rest of the app, at a real display's
scale factor, in the layer's own P3 colorspace. It is the first and only
observation of `Stack`'s paint order outside `renderOffscreen`.

**What it did NOT establish, and this is the part to be precise about.** The
build the human ran **predates commit `ef7f899` and contained no modal** — no
`Deferred`, no absolutely-positioned box, no scrim. It closes **nothing** for the
absolute-positioning milestone, whose own entry below stands unchanged and open.
A look at one build is evidence about that build.

**It was also, very nearly, the last un-scrimmed look this demo would ever get.**
The modal as first written was always on, laying a translucent wash over the
whole window — and this one file carries four milestones' exit criteria,
including M2's, which is literally a contrast judgement. The modal is gated
behind the **M** key for that reason; see `showModal` in
`Sources/MetalUIDemo/main.swift`.

**Z-order is why that criterion exists, and it is worth restating precisely.**
A `Stack`'s children are placed independently of paint order —
`positionStackItems` never reads which child was declared first — so a
regression reversing paint order would move not one number any of the 739 tests
or 81 goldens check: every rect's `(x, y, width, height)` is identical whichever
child painted first. **Two artifacts have ever observed the property and both are
outside the suite**: the offscreen readback, once, by hand, and the human look
that closed the criterion. Nothing automated has seen it or can.

**Absolute positioning and `Deferred` — failures 1 and 2 are CLOSED by
measurement of a human's screen recording; 3 and 4 are still OPEN.**
`docs/superpowers/specs/2026-08-28-absolute-positioning-design.md` §6 item 7
asks for a modal in `MetalUIDemo` that is positioned against the window,
painted over everything, and escaping a `ScrollView`'s clip — **and a human to
run it and report**.

**Read how this was closed before trusting it, because it is a weaker
instrument than the `Stack` entry above and was obtained by accident.** The
human ran the demo with the modal up and recorded the screen — *for an
unrelated reason*, to show resize stutter — and never reported on the modal at
all. Failures 1 and 2 were then settled by sampling pixels out of that
recording, not by anyone looking and saying it was right. What makes it real
evidence rather than an assumption is that one token appears at two
brightnesses in the same frame: the modal panel measures `#141A28` against
`.surface`'s undimmed `#161C2E`, while the main pane *behind* the scrim
measures `#0D1118` against the `#0D101B` that `.surface` blended with a 42%
black scrim predicts. The ratio between them is 0.60-0.65 where the scrim's
alpha predicts 0.58, the excess being the recording's own gamma. The top bar is
dimmed too, so the scrim reaches the window's edges rather than the scroller's
420pt strip, and the panel sits visibly over rows 6-9, which are declared after
it.

**The build in that recording is no longer the build a human would run**, and
one of the four failures below has changed since. The measure-performance
milestone replaced the demo's `for` loop over 40 rows with a `List` of **500**,
windowed to the visible slice. The rows are still declared *after* the modal, so
failure 2 reads exactly as written; failure 3 (does the modal move when the list
scrolls) is if anything easier to judge with 500 rows of travel underneath it.
**Failure 4's expected answer INVERTED in the input-and-state milestone** — the
scrim now registers a click target, so the list must no longer scroll under it;
see that item for both halves of the change. Nothing about `Deferred`, the
hoist or the clip reset changed.

**What that leaves genuinely unobserved is failures 3 and 4**, because the
recording contains no scrolling — nobody has seen whether the modal stays put
while the list moves, or what a wheel over the scrim does. Those still need the
run below, and failure 4 is now a sharper question than it was: it has a right
answer rather than an expected report. Note also that dark-on-dark dimming is very hard to judge by eye
with no undimmed reference in frame: a first pass over these same frames
concluded the scrim was **missing**, and only measurement corrected it. A human
report of "I see no scrim" should be measured before it is believed.

**Where it is, and the key that shows it.** Inside the demo's `ScrollView`,
declared **before** the `List` that builds the rows: a `Deferred` wrapping a `Stack` that is
`.position(.absolute).inset(Pixels(0)).background(.scrim)`, holding a 360pt
centred panel. Absolute with all four insets given and an `auto` size makes it
stretch across its containing block, which — nothing between it and the root
being positioned — is the whole window.

**It also carries `.onClick { showModal = false }` as of the input-and-state
milestone**, which is what makes it an *opaque hit target* and therefore what
inverts failure 4 below. Clicking the scrim dismisses the modal; the panel
inside it carries a no-op `.onClick {}` so that clicking the panel does not.
That absorber is not decoration — a container registers before descending, both
sit on the same hoisted layer, and there is no click chaining, so the panel's
later registration wins the tie-break and the scrim never sees it.

**It is off by default and the M key toggles it.** The look therefore has an
instruction: run the demo, press **M**, and watch the transition in both
directions. Two reasons, and the second is the better one. This file carries
four milestones' exit criteria and an always-on translucent scrim would make
every future look pay for this one — M2's is a *contrast* judgement, "the
paragraph renders legibly". And toggling makes **this** criterion stronger:
"the modal covers the window" and "the modal replaced the window" separate by
observation across the transition, rather than by inferring one from the
scrim's alpha.

**The key still works and the mechanism underneath it changed.** M is now a
`Binding("m", ToggleModal())` on the window's `Keymap`, handled by
`Window.onAction`, rather than a `switch` on `charactersIgnoringModifiers` in an
ad-hoc `onInput` — which is gone from the demo entirely, along with the false
sentence it carried ("there is no hit-testing in the framework yet"). Space
moved the same way. Clicking the scrim also dismisses now, so a human has two
ways to close it.

**What a human has to look at, stated as four separable failures.**

1. **The scrim covers the whole window**, not a 420pt-wide strip. Cropped to the
   scroller's viewport means the portal did not reset the clip.
2. **The panel and the scrim paint over the list rows**, which are declared
   *after* the modal. Rows on top means the layer did not hoist.
3. **The modal does not move when the list scrolls.** Sliding with the content
   means `pushRootClip` reset the clip bounds but inherited the accumulated
   offset (ruling AP-I) — half a portal.
4. **Wheel over the scrim with the modal up, and report whether the list moves
   underneath it. THE EXPECTED ANSWER INVERTED with the input-and-state
   milestone, and this item is now a pass/fail rather than a report.** The list
   must **not** move. A human reporting that it still scrolls under the modal is
   reporting a regression, not confirming a limitation — which is the opposite
   of what this item said for three milestones.

   **Two things changed and both were needed.** The framework grew the general
   hitbox list this item used to say nothing short of would change the answer
   (design spec §8.1's, folded so that a scroll region *is* a hitbox with an
   axis attached), so a wheel event now stops at the topmost opaque hitbox and
   scrolls only if that record is itself a scroller. And the demo's scrim, which
   registered no hitbox at all — `Deferred` and `Box` contribute no
   `insertHitbox` call on their own — gained `.onClick { showModal = false }`,
   which is exactly what makes an element an opaque hit target (ruling IN-W).
   `Deferred` has hoisted it to the root layer over the whole window, so it
   outranks everything beneath it.

   **The old sentence was wrong in one further way worth keeping**: it said
   `Frame.scrollRegions` "is the only hitbox list this framework has". That
   accessor is now a derived view with **zero** production readers and has a row
   in the inert table; `Frame.hitboxes` is the list.

   The neighbouring case an earlier review fixed still holds — a scroller
   *inside* a `Deferred` outranks one it paints over, because the registration
   carries its layer.

   **The cost of the same rule, and it is divergence 16**: a button inside a
   `ScrollView` swallows that scroller's wheel over its own rect, where a browser
   scrolls. The demo's counter is in the main pane and not in the list for
   exactly that reason.

**Nothing in the suite can see any of the first three, and the reason is the same one
`Stack`'s entry gives.** A `Deferred` contributes no layout node, so its
subtree's `(x, y, width, height)` are byte-identical whether or not it hoists
and whether or not it escapes; the 739 tests and 81 goldens would all stay green
under a regression in either half. The scene-level tests in `DeferredTests.swift`
assert the layer and the mask on synthetic frames, which is real evidence and is
not the same as the composed window.

**And one thing the look will not establish either.** Whether escaping the clip
is what a *user* wants in a given case is a design question, not a mechanism —
design spec §5 names it as untestable up front, and a positive report does not
close it.

**Why the scrim is translucent rather than opaque** (`ColorToken.scrim`, 0.32 in
light and 0.42 in dark): an opaque one makes "covers" and "replaced"
indistinguishable in a still frame. Gating it behind M is what keeps that choice
from taxing every other look in this file.

**Measure-path performance — the exit criterion is CLOSED for release, by a
human on 2026-08-29, and the report came with a boundary attached.** Design
spec §9 item 6 asks for a human to run the demo **in both debug and release**,
drag the window edge, and report whether the resize stutter is gone.

**What they said, quoted rather than paraphrased**: release "works much
better", and the residual is "almost imperceptible — it takes me trying to
stretch it across my whole screen to see a tiny bit of stutter."

**That last clause is the useful half, because it names the remaining cost's
shape.** Stretching the window to full screen makes the viewport TALLER, so
more rows intersect it, so `List` builds more of them per frame — roughly 13
rows at the demo's default height against ~50 at full screen on a large
display. Windowing makes a frame cost O(visible), not O(1): a residual that
scales with window HEIGHT is exactly what the design predicts and is the
boundary of what this milestone bought. A residual that scaled with the
**row count** would have been a defect, and 500 rows is what the demo ships
precisely so that would have shown.

**What this does NOT close, and the distinction is the usual one.** The human
reported on release. **Debug was not separately reported**, and the machine says
debug carries a flat ~3.2x constant factor — 5.060 ms against release's 1.273 at
500 rows — so a debug run is expected to be worse and nobody has said by how
much. The other three report items — a missing, blank or late row at the bottom
edge while scrolling; reaching row 500 cleanly; and the cold-frame launch hitch
(~188 ms debug, ~76 ms release, ruling MP-I) — **were not reported on either
way**. Read the criterion as closed for the question it was written to answer
and open on those four points.

**What the machine established instead, and it is a different thing.** The demo
tree's **steady-state** release frame, measured through a real `Frame.render` on
MacBookPro18,2 / Apple M1 Max, is **1.279 ms at 40 rows and 1.273 ms at 500** —
against **5.366 ms and 50.498 ms** for the same tree at this milestone's base
commit. That closes exit criterion 4 (under 8.33 ms) on the **warm** frame, and
criterion 5 (a long list costs what a short one costs) by measurement. The
**cold** first frame is a different number and is recorded at ruling MP-I: 76.26
ms at 500 rows in release, 188.30 in debug, because that frame builds every row.

**The tail was checked, not just the best**, which is the statistic a stutter
milestone actually needs — a best-of-N hides exactly the frames a human sees as
a hitch. Over the full distribution the flatness holds at every percentile: 40
rows median 1.305 / p99 1.423 / worst 1.427 ms, 500 rows median 1.294 / p99
1.314 / **worst 1.330** ms. The 500-row tail is *tighter* than the 40-row one,
and the worst frame measured at either count is under a sixth of the 8.33 ms
budget.

**And the cost WHILE SCROLLING was finally measured, which is the interaction
this milestone is actually about — every figure above is a static tree.** Same
machine, release, `demoLikeRows(500)` through a real `Frame.render` with the
`StateTable` and `ShapingCache` threaded across frames the way `Window` threads
them, 294 timed frames after ten warm ones, the scroller's stored offset
advanced by a fixed step each frame:

| run | median | p99 | worst | frames the sweep fired on |
|---|---|---|---|---|
| static (offset never moves) | 1.073 | 1.147 | 1.370 ms | 0 |
| scrolling 4pt/frame | 1.171 | 1.381 | 1.498 ms | 1 |
| scrolling 45pt/frame (a fling) | 1.385 | 1.562 | 1.569 ms | 15 |

**That is stronger evidence for criterion 4 than the static figure**, and it
closes a deferred question about whether the generation sweep costs anything in
practice: the run that swept fifteen times has a *tighter* tail than the run
that swept none — a second static run on the same instrument produced a 2.611 ms
outlier, larger than any frame in either scrolling run. Scrolling costs about
0.1-0.3 ms more than sitting still, entirely from cache misses as new rows enter
the window, and the worst frame measured anywhere is under a fifth of the 8.33
ms budget. Resident cache entries move with scroll speed as expected (64/16
static, 110/58 at 4pt, 186/253 at 45pt) and stay under `sweepThreshold`.

**These are this machine's numbers taken with this harness, and one earlier set
did not reproduce.** The whole-branch review reported a median of 0.826 ms over
294 scrolled frames with the sweep firing on 3; re-measured here the medians
came out 0.2-0.6 ms higher and the sweep count is a function of the scroll step
rather than a constant. Nothing about the conclusion changes — every figure in
both sets is far inside budget — but the table above is the one that was
measured by the method it describes, and a re-run should reproduce *it*.

**None of it says anything about criterion 6**: a frame budget met in a harness
is not a window that feels smooth under a drag, exactly as §9 item 6 says.

**Why only a human can close it, stated as a mechanism rather than as
deference.** Resize stutter is produced by the *whole* loop — AppKit's
live-resize run loop mode, the display link, drawable acquisition and GPU
submission — and every number above excludes all four; `renderOffscreen` and a
timed `Frame.render` both stop at the CPU boundary (divergence 3 of design §10
records that exclusion up front). And the demo now carries a second thing worth
a directed look for the same reason `Stack`'s z-order needed one: with a
`List`, rows appear and disappear as the window moves, and a window whose
overscan is too small shows a strip of unbuilt rows for a frame (divergence 13).
No assertion in the 739 can see either.

**What a human must do, and what to report.** Run `swift run MetalUIDemo`, then
`swift run -c release MetalUIDemo`. Drag the window's edge — slowly, then fast —
and scroll the list hard in both directions. Report: (1) whether resizing
stutters, in each build separately, since debug is ~4x the frame cost of release
and the two can disagree; (2) whether any row is ever missing, blank or
late-arriving at the bottom edge while resizing or flinging; (3) whether the
list still reaches its end correctly at 500 rows; and **(4) whether the window
takes a visible moment to appear at launch, in debug especially** — the first
frame builds all 500 rows (ruling MP-I) and measures **188 ms** in debug,
roughly eleven dropped frames, so this converts a known number into an
observation about whether it is actually perceptible. A positive report closes
§9 item 6 and closes none of the looks this file already lists as permanently
open.

**`@State`, hit testing and input dispatch — exit criterion 7 is CLOSED by a
human on 2026-08-30, and the same run found one real defect.** Design spec §7
item 7 asks a human to run the demo and report whether clicking feels
responsive, whether hover reads correctly and whether focus is visible.

**What they said, quoted rather than paraphrased**: "Everything works as
expected for the most part, I only saw one anomaly" — the anomaly being the
counter's readout, screenshotted at two counts, wrapping `"Count 3"` onto two
lines while `"Count 2"` stayed on one.

**Read the closure at exactly its strength, which is a general report and not
an itemised one.** The list below has five numbered items and the human did not
answer them one by one, so "works as expected" covers the whole of what they
exercised and pins none of the five individually. In particular the two
counter-intuitive expected answers — that hover is deliberately *sticky* when
the pointer leaves the window (ruling IN-K), and that `=`/`-` must do
**nothing** once Escape has dropped focus (both bindings carry
`context: "Counter"`) — were not separately confirmed, and a later reader should
not cite this entry as evidence for either. What is closed is the criterion as
written: clicking, hover and focus were seen in a real window under a live
pointer and nothing about them was reported as wrong.

**The anomaly was divergence 8 — pre-existing, not a defect of this
milestone — and it is now FIXED.** It was the first time anyone had seen that
divergence on a single short string rather than across forty list rows, and
that is what made it worth chasing: the entry read as though it took a wall of
rows to notice, and a lone *centred* label turned out to be exactly as exposed,
centring being what supplies the fractional origin.

**The demo carried a declared-width sidestep for one commit and no longer
does.** `Text.paint` now wraps at the width layout measured at, so
`Text("Count \(count)")` shrink-wraps and renders on one line at every value;
removing the sidestep is what demonstrates the fix.

**A human ran the fixed build on 2026-08-30 and reported "everything seems to
be fixed."** That is a second look, on a different build from the one that
closed the criterion, and it is the only observation anyone has of the fix in a
real window — every other figure for it is a glyph count out of a headless
`Frame`. Read it at its strength: it is a general report, so it says the
anomaly is gone and re-confirms nothing about the five report items
individually.

**One candidate sidestep is worth remembering even though neither it nor the
other is in the tree any more**: splitting the readout into two space-free
`Text`s looks immune, because the mechanism is the last *word* moving down.
Measured, it wrapped on **every** count instead of some, because
`CTTypesetterSuggestLineBreak` breaks *inside* a word it cannot fit (ruling
TX-F). A string with no break opportunity is not protected; it fails harder.

Before that run, what had been established was only that the demo builds
warning-free and launches — the binary started, stayed alive, and wrote nothing
to stderr, which is a process fact rather than an observation of a window.

**Why this criterion cannot be closed by anything in the suite, stated as a
mechanism rather than as deference.** All three questions are about a rendered
window under a live pointer. The framework's own §6 named them in advance as
untestable — "whether a click *feels* responsive, whether hover highlighting
reads correctly, and whether focus is visible" — and two further things join
them from execution. The `NSTrackingArea` that makes `mouseMoved` fire at all
(ruling IN-K) has **no harness in this repo**: nothing here can drive real
AppKit mouse tracking, so whether hover updates on a plain move — rather than
only on a click — is a human observation and nothing else. And the demo's
**focus affordance is a token swap between `.surface` and `.surfaceSecondary`**
(ruling IN-V), because `Frame.fill` can draw no border; whether that reads as
"this thing has the keyboard" is a judgement about two dark greys, which is the
same kind of judgement the scrim entry above records a first pass getting
backwards until it was measured.

**The five items below are kept as written, as the standing script for the next
run rather than as an open request.** They were answered in the general once
(see the closure above); re-running them individually is what would pin the two
counter-intuitive ones.

**What a human must do, and what to report.** Run `swift run MetalUIDemo`. The
counter is in the main pane, below the layered hero and above the "Text
renders" heading, and it is **focused at launch**.

**That last clause was FALSE for the whole milestone and became true in the
fix wave** — say so rather than quietly correcting it, because a human who ran
an earlier build would have reported items 3 and 4 as broken and been right.
`CounterPanel` focuses itself from its own `requestLayout`, and
`drawFrameIfNeeded`'s read-back of `focusedElement` used to overwrite that call
with the value the frame had been handed *before* it happened — on that frame
and every frame after, since set-during-render and clobber-at-end alternate
forever. So the counter was never focused at launch, `=`/`shift-+`/`-` were
inert until a human pressed **F** (all three carry `context: "Counter"`, which
only the focused panel contributes), and the focus affordance never painted.
The read-back is now guarded to apply the frame's *decision* rather than its
value; `focusingFromInsideAFrameSurvivesThatFrame` and
`focusingFromInsideAFrameIsStillValidatedByTheNextFrame` pin both directions.
**Nothing in the demo changed** — the bug was in the mechanism and so is the
fix, which is what keeps the next caller of the public `Window.focus(_:)` from
rediscovering it.

1. **Click `+` and `-` and report whether it feels responsive** — the count
   should move on *release*, not on press, and there should be no perceptible
   lag. (Dispatch runs on `mouseUp` and only when press and release landed on
   the same element; a click that starts on `+`, wanders off and comes back
   still counts.)
2. **Move the pointer slowly across the two buttons and report whether the
   highlight tracks it** — each should take the accent colour under the pointer
   and lose it when the pointer leaves. **And say what happens when the pointer
   leaves the WINDOW**: `lastMousePosition` is deliberately sticky (ruling
   IN-K), so the expected answer is that the last-hovered button *stays* lit.
   That is a known limitation, not a bug to chase, and nobody has seen it.
3. **Report whether the focused counter panel is visibly distinguishable from
   the surrounding pane.** Press **Escape** to drop focus and **F** to take it
   back, and judge across the transition rather than from a still — the same
   argument that gates the modal behind **M**. If the two states are hard to
   tell apart, say so: the affordance is a token swap and the honest answer may
   be that a fill is not enough, which is a finding about `IN-V` rather than
   about the focus system.
4. **With the counter focused, press `=` (or `shift-+`) and `-`, and report
   whether the count moves.** Then press **Escape** and press them again: the
   expected answer is that **nothing happens**, because both bindings carry
   `context: "Counter"` and that context is contributed only by the focused
   panel. A human who finds them still working with nothing focused has found a
   real defect in context matching.
5. **Space still toggles the theme and M still toggles the modal**, both now
   through the keymap rather than an ad-hoc `onInput`. Report if either
   regressed — that is the check that moving them onto the new subsystem cost
   nothing.

**Two of the absolute-positioning entry's four failures also become answerable
in this build and one of them has INVERTED.** Failure 4 — wheel over the scrim
with the modal up — must now leave the list still, because the scrim registers a
click target (ruling IN-W). And clicking the scrim should dismiss the modal
while clicking the *panel* should not.

**A positive report closes §7 item 7 and closes none of the looks this file
already lists as permanently open**, including every one of the three the M2
entry names.

**The sizing milestone — exit criterion 8
(`docs/superpowers/specs/2026-08-30-sizing-design.md` §8 item 8) is OPEN.
Nobody has run the demo for this milestone, and this entry is written so that
gap stays visible rather than reading as closed.**

**What was established, and it is a process fact, not a look.** `swift build
--target MetalUIDemo` is warning-free — confirmed 2026-09-01 after touching
`Sources/MetalUIDemo/main.swift` and forcing a rebuild, so the check is
against a real recompile rather than a cached no-op. `swift run MetalUIDemo`
was started, reached a running process, stayed alive under `ps` for several
seconds with no crash, and was terminated deliberately by this task rather
than exiting on its own; stderr carried nothing beyond SwiftPM's own build
banner (`Building for debugging...`, `Build of product 'MetalUIDemo'
complete!`) the whole time. That rules out exactly one failure — a crash on
startup — and establishes nothing about what is on screen. `swift test
--no-parallel` reported `Test run with 752 tests in 1 suite passed after
13.007 seconds` at the time, this milestone's own expected count, with 86
goldens and `git status` showing none touched. **The whole-branch fix wave has
since taken that to 755 and 87** (`Test run with 755 tests in 1 suite passed
after 13.222 seconds`, still no pre-existing golden touched), and it changed
the engine — see ruling `SZ-O` and the Build section. **So the build a human
runs today is not the build these process facts describe, and item 1 below is
the one to re-read before running**: the overlapping-siblings regression
`SZ-O` fixes is exactly the "text spilling out of its box" symptom that item
asks about, so a look at the pre-fix build would have been looking for
something that was really there.

**Exit criterion 8's own wording asks the wrong question, and this record
does not ask it.** The spec's §8 item 8 says a human should report "whether
the sidebar reads at its declared width." Task 9 measured, and the decisions
doc records as ruling `SZ-L`
(`docs/superpowers/2026-08-30-sizing-decisions.md`), that the sidebar's
97 / 73 / 70 rendering (windows 1200 / 920 / 700, against a 196pt
declaration) is **identical before and after all three of this milestone's
fixes** — `min(196, content) == content` whichever half of CSS Sizing §4.5's
automatic minimum is implemented, so no fix this milestone could ship was
ever capable of moving that number. Asking a human whether the sidebar "reads
at 196" sends them looking for a change that was never going to be there and
invites a false regression report. The divergence-5 entry above used to
attribute the squeeze to ruling FS-3; that attribution was wrong and has
since been corrected there.

**And the remaining half of that question is now ANSWERED, by the fix wave,
so a human is not asked it at all.** This paragraph used to end "nobody has
measured whether a real browser would size the same declaration the same
way", with an unset `flexShrink` recorded as an unverified hypothesis.
Measured, on this body row's shape, through both engines in one pass, at a
width where the main pane's demand forces a shrink:

| sidebar's `flex-shrink` | engine | WebKit |
|---|---|---|
| `1` — the unset default, what the demo has | **69** | **69** |
| `0` | **196** | **196** |

**Exact agreement in both arms**, and 69 is the content floor to the pixel
(`41 + 14 + 14`). The squeeze is ordinary flex arithmetic and a browser does
the identical thing: **it is not a divergence and never was.** The remedy is
`.flexShrink(0)` or a `minWidth` on the sidebar column — a demo declaration
that does not say what its author meant. It is deliberately not applied (that
width feeds the whole layout), and both the measurement and the remedy are at
the call site (`Sources/MetalUIDemo/main.swift`) and in ruling `SZ-L`.
**Read it at its strength:** the probe stands in for the body row — a rigid
41-wide box for the label, a rigid filler for the main pane — so it settles
the *mechanism* and does not re-derive 97 / 73 / 70 on the real tree.

**What a human must do, and what to report.** Run `swift run MetalUIDemo`.
Look at the whole window, not only the four points below — point 4 exists
because the first three are not the only things four sizing rules changed on
one shared code path could have broken.

1. **Does any text anywhere in the window spill out of its box** — a line of
   glyphs drawn below, above or outside the coloured background it's supposed
   to sit inside, or overlapping the element after it? This is ruling TX-H's
   user-visible form: before the fix, an item's cross size was measured
   *before* CSS Flexbox §9.7 flexed its main size, so a shrunk item could
   keep the box height it had before shrinking while paint still drew every
   line the shrunk width now demands. The demo has text in several shapes —
   a single-line sidebar label, a multi-line paragraph, a counter readout,
   list rows — and the fix changes the general mechanism rather than one
   site, so this is a whole-window check.
2. **Does the scroll list still behave** — same visible extent, same
   scrolling motion, still reaching row 500 cleanly at the bottom? Four
   sizing rules changed on the path this list's `ScrollView` viewport is
   sized from, and `Sources/MetalUIDemo/main.swift` keeps a
   `.minHeight(Pixels(0))` on the box wrapping it: Task 9 measured that
   removing it grows the viewport to 14000pt (the full, unclipped content
   height) at every window width tested, so the modifier stays. Nobody has
   looked at whether the running list matches that measurement.
3. **The sidebar — a DESIGN judgement, and there is nothing left to explain.**
   Ask only whether it *looks* wrong: too narrow for "Library" and the four
   rows beneath it, cramped in a way you would want changed. Do **not** ask
   whether it matches its 196pt declaration. It does not, it did not before
   this milestone, and the reason is now measured rather than open — ordinary
   flex shrinking, which WebKit performs identically (the table above). A
   report of "it's narrower than 196" is a report of correct behaviour. A
   report of "it looks cramped" is a request to write `.flexShrink(0)` on
   that column, which is a demo-declaration change and not an engine one.
4. **Anything different that this milestone did not predict.** BM-4, FS-3 and
   TX-H all changed rules on the sizing path every flex item in the tree
   takes, at once; this question is deliberately aimed at nothing in
   particular, on the same footing as every other milestone's "did anything
   else look wrong" question in this file.

**A positive report on all four closes design spec §8 item 8 as revised
above — item 8's literal "declared width" wording is superseded by point 3 —
and closes none of the looks this file already lists as permanently open.**
No claim about appearance, wrapping, scrolling or the sidebar's look is made
anywhere in this entry; everything above the numbered list is either a
process fact (build, launch, stderr, test count, goldens) or a measurement
taken through a headless probe (`Task9Probe.swift`, deleted before Task 9's
own commit), never through a rendered window.

## Twelve known divergences, numbered 1, 2, 4 and 9-17 — expected, measured, not defects

**The labels are stable ids, not a running count, and there are now FIVE
retired labels.** There are **twelve** entries and the highest label is still
**17**. Five labels are permanently retired, for three different reasons,
which is worth knowing before assuming a sixth gap means a lost entry:

- **3, 5 and 6 were freed by the sizing milestone (2026-08-31), which closed
  all three of this framework's remaining sizing divergences at once.**
  **3** was ruling BM-4, an over-constrained box refusing to grow its border
  box; fixed by flooring every used-size call site at
  `max(clamp(resolved, min:, max:), floor)` — the floor applied *after* the
  clamp, settled against the oracle rather than chosen (a `max-*` smaller than
  a box's own padding+border does not win in either axis) — and pinned by
  `anOverConstrainedBoxGrowsToFitItsPaddingAndBorder` (`BoxModelTests.swift`).
  **5** was ruling FS-3, an item's automatic minimum ignoring its own
  specified size; fixed by reading the specified size suggestion from the
  node's **used**, post-BM-4 size rather than its raw declaration — floors
  compose by `max` and BM-4's floor cannot be undone by FS-3's — and pinned by
  `anItemsAutomaticMinimumIsTheSmallerOfItsSpecifiedAndContentSizes`
  (`FlexEngineTests.swift`) plus two browser fixtures,
  `sizing_specified_suggestion` and `sizing_specified_suggestion_is_used_value`.
  The second of those two exists because the first does not discriminate the
  specified-vs-declared reading on its own tree: a floor BM-4 has already
  raised to 120 is untouched by either a 100 or a 130 automatic minimum, and
  only a fixture with a shrinking sibling can tell the two rules apart —
  measured, not assumed, after the plan's own claim that the first fixture
  guarded this choice turned out false. **6** was ruling TX-H, an item's cross
  size measured before §9.7 flexes it; fixed by re-running the fit-content
  cross measurement for any non-stretched item whose used main size differs
  from its hypothetical one, and pinned by
  `anItemsCrossSizeIsMeasuredFromItsUsedMainSizeMatchingWebKit`
  (`FlexEngineTests.swift`). All three fixes, and the findings along the way,
  are recorded in `docs/superpowers/2026-08-30-sizing-decisions.md`: BM-4 is
  rulings `SZ-D`, `SZ-E`, `SZ-F` and `SZ-J`; FS-3 is `SZ-G`, `SZ-H` and `SZ-I`;
  TX-H is `SZ-M`.
- **7** was freed by a *renumbering*, before this milestone. The *original*
  divergence 6 — an unrelated, already-fixed bug, not the TX-H one just
  retired above — was `ownCross` measuring **max-content** on whichever axis
  was the cross one, so a **column** (whose cross axis is the *inline* axis,
  where CSS shrink-wraps) laid a wrapping child out 200 wide at `x = -40`
  inside a 120-wide centring column, and `Column { Text(…) }` 270 wide at
  `x = -75`. It was fixed by computing CSS's fit-content —
  `min(max(min-content, available), max-content)` — on a column's cross axis
  (still max-content on a row's, correctly, since a row's cross axis is the
  block axis), and the original divergence 7 moved down into the slot that
  fix emptied — which is why "divergence 6" in an old document could mean
  either this bug or the TX-H one, depending on date, and why both are
  retired labels now rather than one. The fix's own first evidence was weak:
  every box in the 61-fixture corpus at the time was an empty div whose
  min-content and max-content widths were the same number, so nothing could
  regress or validate it. Six fixtures with wrapping children
  (`flex_column_fit_content*`, `flex_row_block_axis_max_content`,
  `FitContentFixtureTests`) were added afterward to close that gap, and found
  two of the fix's four clauses wrong before they were measured — the
  available space is the container's cross extent minus the item's own cross
  margins, and the `max` with min-content is a real floor that overflows.
- **8** was freed by a *fix*, on 2026-08-30, and its entry was deleted rather
  than renumbered. `Text.paint` now wraps at the width layout measured at
  (`LayoutTree.measuredWidth(_:)`) instead of re-deriving one from the rounded
  box, so paint and layout no longer disagree about how many lines a
  shrink-wrapped string has. Measured on the shape it was reported in: **31 of
  40 list rows wrapped before the fix and 0 after**, and a centred `"Count N"`
  label wrapped on ten of the first thirteen counts and now wraps on none.
  Pinned by `paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox`,
  `aCentredShrinkWrappedLabelNeverWrapsAtAnyValue` and
  `aTextShrunkByFlexStillWrapsAtItsShrunkWidth` in `GlyphEmitterTests.swift`,
  and **confirmed in a real window by a human on 2026-08-30** — which matters
  because every other figure for this fix is a glyph count out of a headless
  `Frame`, and the defect was originally *reported* by eye rather than found by
  a test. **The retired TX-H entry (label 6, above) used to carry a paragraph
  calling a second spill "a second spill with the same symptom and an
  UNIDENTIFIED site" — a sidebar label breaking mid-word inside a `Column`
  that is itself a flex item. The sizing milestone identified it: that site
  is this one, not a third bug.** `"Library"`'s max-content width is
  **42.2436**; the sidebar column floors it to 70.24, rounds to 70; the
  text's own box rounds down to 42; and before this fix, paint character-broke
  there (ruling TX-F). Re-measured with the fix landed: it renders as 7 glyphs
  on one baseline, ink 13.5pt. There is no unidentified spill site left.

**Neither of the two labels retired before this milestone is ever reused, and
neither are the three retired by it** — the same rule `EP-2`/`EP-4` follow —
so a citation written against "divergence 3", "5" or "6" (the TX-H one; see
the label-7 bullet above for the *other* thing "divergence 6" used to mean) in
an older commit message or document points at a retired entry rather than
silently rebinding to a different one. A reader who counts to the highest
label gets seventeen and a reader who counts entries gets twelve; the heading
says both numbers because they answer different questions.

**Not every entry is a disagreement with WebKit, and 10 was the first that
never was one.** 1, 2, 4 and 9 are places this engine answers differently
from an oracle. (The retired 8 was the one entry where the disagreement was
not with WebKit at all but between this engine's own layout and its own paint
— which is also why it was the one that could simply be fixed.) **10, 11 and
16 are design choices recorded here because a reader comparing this framework
to CSS will otherwise read them as bugs** — 10 and 11 are the two directions
of one seam and each entry names the other, and 16 is the price of the rule
that closes the modal-scrim case. **12, 13, 14 and 17 are a third kind again:
neither a disagreement nor a design preference, but four accepted limitations
of `List`'s windowing**, each with a named mechanism that would remove it and
a reason that mechanism is larger than this framework has built. 14 is the
one of the four that can make a list render **blank** rather than merely
stale or forgetful, so read it before putting a `List` in a scroller that
holds anything else. **15 is a fourth kind and the only one of its own: a
defect this framework has and has deliberately not fixed yet**, recorded here
rather than left latent because its symptom — a subtree that draws nothing at
all — reads as anything but a clipping bug.

**1. Colour.** The layer's colorspace is Display P3 (spec §7.8) while
`Hsla.rgb(_:)` authors in sRGB, so `0x38BDF8` renders somewhat more saturated
than the hex implies.

**2. WebKit's flex sub-one clause.** The layout corpus treats WebKit as the
oracle, and there is exactly one place the engine knowingly does not follow it:
CSS Flexbox §9.7.4.b's magnitude test, in `ResolveFlexibleLengths.swift`.

Reproduce with:

```html
#root { display: flex; flex-direction: row; width: 400px; }
.a { flex: 0.25 1 0; min-width: 350px; }
.b { flex: 0.25 1 0; }
```

The spec says `b` is **50** — the sub-one scaling may only reduce the remaining
free space, never enlarge it, and on the second pass the scaled 100 exceeds the
remaining 50. **Blink says 50. WebKit says 100** and overflows the container to
450. Two engines and the specification against one: this is a WebKit bug, and
the engine follows the spec.

The divergence is narrower than it looks — it needs positive free space *and* a
min/max violation to force a second pass. `flex_row_fractional_shrink` exercises
the identical `abs` guard with negative free space and WebKit agrees with us
there.

**No fixture or golden encodes WebKit's answer.** The probe above was generated
against the oracle and then deliberately not committed, precisely so that a
future WebKit fix moves nothing in the corpus and changes no test. Do not add
one, and do not "correct" `subOneScalingNeverExceedsTheRemainingFreeSpace`
towards WebKit — it is pinning the settled answer, not a provisional guess.

**4. Ruling CS-I — an `auto` root axis takes the space it was offered, where
CSS shrink-wraps the block one.** The root is a block-level box in the initial
containing block, so a browser fills its inline axis and shrink-wraps its block
axis. Measured: an 800×600 viewport holding `#root { display: flex }` with one
100×40 child gives WebKit **800 × 40**. This engine gives **800 × 600**.

**The justification is `computeLayout`'s contract, not a ruling from a layer
above.** The engine's root is not a block box in a CSS initial containing
block; it is a node whose size its host supplies, and `.definite(w)` on an axis
of `available:` is the host saying "this axis is w". A browser has no
equivalent — its root's containing block is the viewport by construction, and
it is never *told* a size. **Do not cite EP-5 here**: that ruling ends "the
WebKit corpus stays the oracle for the engine; this ruling binds everything
above it", and `resolveRootSize` is inside the engine.

The evidence is behavioural. CSS's answer was implemented and reverted, and it
reddens six element-pipeline and frame-loop tests at once, all for one reason —
a `Row { … }` rendered into a `Frame` declares no height, so the window's root
would collapse to its content and every `flexGrow(1)` child would stretch into 0.

**The engine can still express CSS's answer**, which is what makes this "we
interpret one call shape differently" rather than "we disagree with WebKit": a
host that offers `.maxContent` on the block axis takes the measuring branch and
gets the shrink-wrapped 40. Only the meaning of a *definite* offered extent on
an `auto` axis differs.

**A fixture could hold this one; the corpus deliberately has none.**
`#root { display: flex }` with no `width` or `height` is perfectly expressible,
and its golden would say 800×40 and fail — same footing as WebKit's flex
sub-one clause above. That all 86 fixture roots declare both axes explains why no
*existing* fixture notices, not why one could not exist;
`FixtureHygieneError` does not enforce it, it only checks the root lands at
(0, 0).

What content sizing *did* change here is the other constant in the same branch
— an `auto` axis with **no offered extent at all** was a hardcoded 0 and is now
the subtree's own size, pinned by
`anAutoRootWithNoOfferedExtentMeasuresItsContent`.

**9. Ruling AP-F — an absolute box with no insets at all sits at its containing
block's origin, where CSS uses its static position.** CSS places an
all-`auto`-inset absolutely-positioned box where it *would* have been in flow —
its static position. This engine places it at the containing block's
**padding-box origin**, ignoring its in-flow siblings entirely.

Reproduce with:

```html
#root { position: relative; width: 200px; height: 100px; }
.before { width: 40px; height: 20px; }
.abs { position: absolute; width: 20px; height: 10px; }   /* no insets */
```

| | x | y |
|---|---|---|
| WebKit (static position) | 0 | **20** |
| this engine (containing block's origin) | 0 | **0** |

Measured through the oracle with a throwaway probe, deliberately not committed.

**Not implemented, and the reason is a second pass rather than reach.** Static
position means laying the box out in flow, recording where it landed, then
removing it — over exactly the children the flow filter (`collectItems`,
`layOutStack`) just excluded. The motivating features all set insets: a modal, a
popover and a tooltip each name at least one edge, and an inset-less absolute
box is closer to a mistake than to a case.

**No fixture and no golden encode it**, on the same footing as divergence 2's
WebKit sub-one clause above: a golden would record this engine's answer as
correct, and a future fix should move nothing in the corpus. Pinned by
`allAutoInsetsPlaceAtTheContainingBlockOriginNotTheStaticPosition` in
`AbsolutePositioningTests.swift`, which is the only pin — implementing static
position must redden exactly it.

**10. A `Deferred` subtree is not clipped by an ancestor CSS would clip it
with — and this one is a design choice, not a measurement.** Every entry above
is this engine answering a question differently from an oracle. This is the
framework deciding to answer a *different* question, and it is recorded here
only because a reader who knows CSS will otherwise file it as a bug.

CSS couples clipping to positioning: `overflow: hidden` clips an
absolutely-positioned descendant **unless its containing block sits outside the
clipper**. So whether a modal escapes a scroller is a consequence of where it is
positioned, and reproducing it means paint emitting a subtree at its containing
block's clip level rather than at its tree level — a second kind of hoisting,
entangled with containing-block resolution (design spec §2).

This framework decouples them instead, and states the rule in one line:
**layer decides paint order, the containing block decides position, and
`Deferred` escapes both.** A subtree wrapped in `Deferred` escapes every
ancestor clip and every ancestor scroll translation regardless of where its
containing block is — including the case where CSS would clip it, and including
the case where it has no absolute positioning at all.

**What it costs, stated because "deliberate" is not "free".** There is no way to
ask for CSS's answer: a subtree either escapes everything or nothing, and a
caller who wanted a portal clipped by one particular ancestor has no spelling
for it. Nothing here is `position: fixed` or `sticky` either — `Deferred` covers
the escape-to-the-window case and those two were left out rather than
approximated.

**No fixture and no golden encode it, and none could** — CSS's stacking and clip
rules are not what `Deferred` implements, so there is no browser answer to
compare against. Pinned at the scene level instead, by
`aDeferredFillInsideAnActiveClipEscapesToTheWholeSurface` and
`aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll` in
`DeferredTests.swift`.

**Divergence 11 is the OTHER direction of this same seam** — a subtree escaping
a clip CSS would apply is this entry; a subtree being clipped where CSS would
not is that one. A reader who finds one of the two has found half the picture.

**11. An absolute box is still clipped and translated by an ancestor
`ScrollView`, even when its containing block sits outside that scroller.** The
mirror image of 10, and the one that bites: 10 is a portal escaping a clip CSS
would apply, and this is an ordinary box *not* escaping a clip CSS would lift.
Both fall out of the same decoupling — layer decides paint order, the
containing block decides position, `Deferred` escapes both — so neither is
fixable without the coupling design spec §2 rejects.

Layout places an `.absolute` box against its containing block. Paint knows
nothing about containing blocks: a clip and a scroll offset live on `Frame`'s
clip stack, which is **structural**, so every ancestor's
`clipped(to:offsetBy:)` applies to everything emitted beneath it. Put an
absolute box inside a `ScrollView` and the two disagree.

Measured — a 41×60 viewport at `(60, 30)` inside a 200×200 frame, holding an
absolute child with `inset(top: 5, left: 5)` and no `Deferred`:

```
absolute bounds = (5, 5) 22×20        // window space, per the containing block
absolute mask   = (60, 30) 41×60      // the viewport, per the tree
```

The rect lies entirely outside its own mask, so it **draws nothing at all**.
Scroll the list 12pt and it also moves to `y = −7`, off the top of the window,
tracking a scroll it is not in flow for. CSS clips neither: the box's containing
block is the root, which is outside the clipper, so a browser would paint it
over the whole page.

**The escape is `Deferred`**, and it is a separate spelling on purpose:
`Deferred { Box().position(.absolute)… }` resets the clip stack to the whole
surface and the offset to zero, and the identical box then paints at `(5, 5)`
with the full 200×200 mask. Recorded at `Box.position(_:)`'s own doc comment as
well, since that is where a caller writing `.position(.absolute)` will be
looking.

**No fixture and no golden encode it**, on the footing of 9 and 10 — a golden
would record this engine's answer as correct, and a coupling implemented later
should move nothing in the corpus. Pinned by
`anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt` in
`AbsoluteOverlayTests.swift`, which asserts the disjoint rect and mask, the
scroll translation, and the `Deferred` escape as the differential.

**12. A `List` row loses its element state when it scrolls out of the window.**
Its *identity* survives and its state does not, and the two are easy to read as
one thing. A row outside the window is not merely un-painted — it is not
produced at all, so nothing marks its `GlobalElementID` during that frame's
element walk, and `StateTable.sweep()` reaps its entry exactly as it would for
an element deleted from the tree for good (design spec §4.3). Scroll it back
into view and it comes back under the same id, holding nothing.

The identity half is real and is what `Data.Element: Identifiable` buys (ruling
MP-D): a row is named after its datum, a name replaces a position, so the row
lands on the same `GlobalElementID` however the window has slid in the
meantime. Nothing about that keeps the *table entry* alive across a frame in
which the row was never built.

**Not fixed, and the blocker is a mechanism this framework has not built.**
Surviving the sweep needs the tombstones design spec §4.3 already names as the
prerequisite for exit transitions — entries that outlive a sweep as
invalid-reporting placeholders rather than being reaped. Until that exists, a
`List` row's state must live in the **data**, which is where a windowed list
wants it anyway: `List` re-reads `data` every frame, so a value the row derives
from its datum is stable by construction and a value the row stores privately
is not.

**No test can see it today and none should be written to pin the current
behaviour**, because the desired behaviour is the opposite one — a test
asserting "state is reset" would have to be deleted by the change that fixes
it. Recorded at `List`'s own type doc as well, which is where a caller
wondering why a checkbox forgot itself will look. Spec §7.5 required this be
written down; that is what this entry is.

**13. A `List`'s window is computed against a one-frame-stale viewport
extent.** Scrolling is exact; only resizing is briefly wrong.

`List` decides what to build in `requestLayout`, and a `ScrollView`'s viewport
extent is not known until its own `prepaint` has measured one — the phase after.
So the ambient `ScrollContext` a `ScrollView` publishes carries a **current**
offset (which `Window.applyScroll` has already written by then) and the
viewport extent measured **last** frame (ruling MP-F). The offset being current
is what makes scrolling exact: however fast the list moves, the window is
computed from the offset the frame is actually about to be drawn at.

A resize is the case that goes wrong, for one frame. Drag the window edge so
the viewport grows, and that frame's window is sized for the old, smaller
viewport — the two rows of overscan absorb a viewport that grew by up to two
rows, and a bigger jump than that shows a strip of unbuilt rows at the bottom
for a single frame before the next frame corrects it.

**Not fixed, and the mechanism is a two-pass layout**: resolving the viewport
before the children that window against it are built means either laying the
`ScrollView` out twice or giving `requestLayout` a resolved size it does not
have. Both are larger than this milestone, and the failure they would remove
lasts one frame and is bounded by overscan.

**The contract is pinned; its consequence is not.** That a `ScrollView`
publishes last frame's extent is asserted directly, by
`scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`
(`Tests/MetalUITests/ScrollRoutingTests.swift`) — so a change that made it
current would redden a test. What no test reaches is the *effect*: every
windowing test pushes a `ScrollContext` by hand with an extent it chose, so
none of them renders the resize frame on which the window is briefly wrong.

**14. A `List` windows against its SCROLLER's origin, not its own — so a
`List` that is not its `ScrollView`'s only layout-contributing child renders
blank.** The sharpest of the three `List` limitations, and the only one whose
failure is total rather than gradual.

`ScrollContext.offset` says how far the enclosing `ScrollView`'s content has
moved under its viewport. `List.visibleRange` reads it as how far *this list*
has scrolled. Those are the same number only when the `List` begins exactly at
the scroller's content origin — which it does in the demo, and in every test
written before this entry, and in nothing else.

Reproduce with a header above the list:

```swift
ScrollView(.vertical) {
    Box(style: .init()).height(Pixels(300))       // anything with a height
    List(rows, rowHeight: Pixels(28)) { … }       // 40 rows
}
```

Scrolled to 300 with a 112pt viewport, the rows on screen are **0 through 3**
and the rows built are **8 through 16** — measured, and through a real
`ScrollView` those nine rows paint at y 224 through 448 under a content mask of
(0, 0) 100x112, so **nothing is drawn where the list is**. Two `List`s in one
`ScrollView` fail the same way by construction, since at most one of them can
start at the content origin. An absolutely-positioned `List` fails it too, and
that was measured rather than reasoned: the same list at `.position(.absolute)`
with `inset(top: 300)` builds the identical rows 8 through 16.

**"Layout-contributing" is the load-bearing word, and the demo is why.**
`Sources/MetalUIDemo/main.swift` declares a `Deferred` modal *before* its
`List`, inside the same `ScrollView`, and is **not** in violation — measured:
the list's rows still start at y = 0. The modal's box is
`.position(.absolute)`, so the flow filter removes it from the content node's
item list and it adds no height for the list to be offset by. An out-of-flow
sibling, or a `.hidden()` one, is free; anything that occupies flow is not.

**Not fixed, and the blocker is a phase contract rather than reach** (ruling
MP-L). Correcting the window needs the `List`'s own offset within the scroller's
content, and `requestLayout` has no position at all — the same fact that makes
`ScrollContext.viewportExtent` one frame stale (divergence 13). Supplying one
means laying the `ScrollView` out twice, or threading resolved geometry into a
phase defined to run before geometry exists; the second is a different layout
architecture, not a bigger version of this milestone.

**So it is a stated requirement of the type instead**: a `List` must be its
`ScrollView`'s only layout-contributing child. That is recorded at `List`'s own
type doc, where a caller will look, and in the `List` bullet at the top of this
file as the fourth load-bearing requirement beside `Identifiable`, a uniform
`rowHeight` and an enclosing `ScrollView`.

**Pinned, and the pin asserts the WRONG answer on purpose** —
`aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`
(`Tests/MetalUITests/ListTests.swift`) says so in its own failure message, so
whoever fixes this gets a red test rather than a surprise and knows to delete or
invert it. **Two neighbouring defects found by the same review WERE fixed and
are not divergences**: a horizontal `ScrollContext` used to window a vertical
`List` against a viewport *width* (ruling MP-M), and a `Deferred` subtree used
to inherit the scroll context of the scroller it had escaped (ruling MP-N). Both
were one condition each; this one is not.

**15. A `ScrollView` nested inside a SCROLLED `ScrollView` gets an empty content
mask, so nothing inside it draws.** Not a disagreement with any oracle and not a
design choice — a defect this framework has, found by measurement and
deliberately left for a milestone that owns paint.

`Frame.pushClip` intersects the incoming rect into `activeClip` **without
translating it by `activeOffset` first**, where `Frame.insertHitbox` — the
routing side — does translate. So the inner viewport's clip is computed in the
engine's untranslated space while `activeClip` is already in surface space, and
the two are compared as though they were the same thing.

Measured through a real `Window`, a 200x200 frame holding a vertical
`ScrollView` over 400pt of content (a 300pt filler above a 100pt box holding a
second `ScrollView`), the outer driven to its 200pt ceiling:

```
inner's three rows paint at y = 100, 150, 200      // correct
inner's registered scroll region = (0, 100) 200x100 // correct
inner's content mask             = (0, 300) 200x0   // EMPTY
```

So the inner scroller is laid out correctly, painted at the right window
positions and routes wheel events exactly right — and draws nothing.

**Its routing twin WAS fixed and is not a divergence** (ruling IN-F):
`registerScrollRegion` had the identical missing term, and unifying it on
`insertHitbox`'s translating convention is pinned by
`aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`.

**Not fixed, and the reason is blast radius rather than difficulty** (ruling
IN-G). The fix is one line — translate the incoming bounds by `activeOffset`
before intersecting — and applying it reddens the pin below and **nothing else**:
re-measured during the whole-branch fix wave at 739 tests, 6 issues, all of them
that one test, with the inner content mask moving `(0, 300) 200x0` →
`(0, 100) 200x100`, which is where its rows actually paint. (The same
measurement was taken at 736 before the fix wave added three tests; both
counts are recorded so the figure can be dated.)

**Read that as weak evidence and the structural argument as strong, and the
entry carried only the first for a milestone.** The suite half is weak for the
reason ruling IN-F records: no other fixture in the repo puts a scroller inside a
scrolled scroller and reads its mask back, so "nothing else reddens" is a
statement about the corpus rather than about the fix. What was missing is the
bound on the fix's *reach*, which is checkable and narrow:

- `pushClip` is reached in `Sources/` only through
  `PrepaintPass`/`PaintPass.clipped(to:offsetBy:)` — the two calls at
  `Passes.swift`, one per pass, each the single line of its own `clipped`.
  `Deferred` does not come through here at all; it uses `pushRootClip`.
- `grep -rn "\.clipped(to:" Sources/` returns **seven** lines, of which
  **three are calls** — all in `ScrollView.swift` (310, 326, 403) — and four are
  doc comments naming the method (`Box.swift`, `Passes.swift` twice,
  `Frame.swift`). Run it and read all seven; the count and the "three call
  sites" claim are two assertions and only the second was checked when this
  paragraph was first drafted.
- The added term is `+ activeOffset`, so the fix is a **no-op wherever
  `activeOffset == 0`** — which is every non-nested `ScrollView` in existence
  and everything under a `Deferred`. Its behavioural reach is *exactly* the
  nested-inside-a-scrolled-scroller case, which is the defect.

So "the clip stack every clipped subtree goes through" — what this entry used
to say — overstates it: every clipped subtree goes through the *function*, and
almost none of them through the *changed behaviour*. **The ship decision stands
anyway**: it was found inside a milestone whose entire test surface is input
rather than paint, and a paint change belongs to a milestone that can look at
pixels. Whoever picks it up should have the bound above rather than rediscover
it.

**Pinned, and the pin asserts the WRONG answer on purpose** —
`aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask`
(`Tests/MetalUITests/NestedClipTests.swift`), which says so in each of its own
failure messages, exactly as divergence 14's does. Delete or invert it; do not
repair it.

**16. An `onClick` inside a `ScrollView` swallows that scroller's wheel, where a
browser scrolls.** A design choice, on 10 and 11's footing — recorded because a
reader who knows a browser will file it as a bug.

A wheel event stops at the **topmost opaque hitbox** under the pointer and
scrolls only if that record is itself a scroller. Every `onClick` registers an
opaque hitbox. So a button inside a list blocks the list over its own rect:

```swift
ScrollView(.vertical) {
    List(rows, rowHeight: …) { row in
        Box { … }.onClick { … }          // the wheel stops here
    }
}
```

**Non-opaque was rejected and the reason is the case this rule exists to
close.** A modal scrim must swallow *clicks* aimed at what is under it, and a
non-opaque hitbox is skipped by `topmostOpaqueHitbox(in:at:)` entirely — so
making click targets non-opaque would undo the scrim property in order to fix
the button one. Design spec exit criterion 4 is the scrim half, and it is met.

**The fix is named rather than left as a mystery, and it needs no new state.** A
wheel should stop at an opaque hitbox only when that hitbox is on a **higher
layer** than the topmost scroller under the same point. `Deferred` hoists a
scrim to the root layer; a button inside a `ScrollView` shares its scroller's
layer — so the `layer` key already on every `Hitbox` separates the two cases
with no ancestor walk. It is written into `Window.applyScroll`'s own doc.
Deliberately not implemented in the milestone that introduced click handling:
`applyScroll` is the site of two shipped intermittent scroll defects that only a
human found, and does not get an unreviewed refinement during a task about
clicks.

**The mitigation in use today is placement.** `Sources/MetalUIDemo/main.swift`
puts its counter in the main pane and not in the `ScrollView`, and says so at
the call site.

**Pinned by `aClickTargetInsideAScrollViewSwallowsTheWheel`**, which asserts the
wrong answer on purpose and says so in its own message. No fixture or golden
encodes it and none could — CSS's wheel routing is not what this implements.

**17. A focused `List` row scrolled out of the window loses focus and does not
get it back.** The fourth `List`-windowing limitation, beside 12, 13 and 14, and
**worse than 12 for a reason worth stating.**

The mechanism is 12's exactly: a row outside the window is not produced, so it
registers nothing in `Frame.focusRegistry`, and `Frame.resolveFocus()` clears a
focused id this frame did not produce (ruling IN-M). Its *identity* survives —
that is what `Data.Element: Identifiable` buys — and its focus does not.

**Why it is worse than 12.** Divergence 12 loses a row's `@State`, and the
remedy there is real: a windowed list wants its state in the data anyway, and a
value derived from the datum is stable by construction. **Focus is not
recoverable from the datum.** Losing a counter is annoying; losing focus
mid-interaction moves the user's keyboard somewhere they did not put it, and
nothing in the data can put it back.

**Not fixed, and there are two named mechanisms rather than one.** The general
one is the tombstones design spec §4.3 already names as absent — entries that
outlive a sweep as invalid-reporting placeholders. The cheaper, focus-specific
one is a grace period: keep a focused id alive for N frames after the element
stops being produced, on the argument that focus is a single value rather than a
table. Neither exists.

**No test pins it and none should pin the current behaviour**, on divergence
12's footing: the desired behaviour is the opposite one, so a test asserting
"focus is lost" would have to be deleted by the change that fixes it.

## Declared but inert — verified, not remembered

The single most likely way to write a bug in this repo is to use an API that
exists, compiles, and does nothing. `Style` has 22 stored properties; **two of
them are read by no production code** — `overflow`, `aspectRatio`.
(**`Style` is untouched by the input-and-state milestone and both rows were
re-checked rather than assumed**: `git diff --name-only 994a4a7..HEAD --
Sources/MetalUILayout/` is empty for the whole branch, `grep -rn "\.overflow\b"
Sources/` still finds one write and no read, and `grep -rn "aspectRatio"
Sources/ | grep -v "var aspectRatio"` finds one doc comment and no use at all.
That is what ruling IN-H's fourth `StyledElement` requirement bought instead of
a `Style` field — see `Handlers`.)
**`StyledElement` deliberately exposes no modifier for either** (`Box.swift`): a
modifier for an inert property is worse than none, because from outside it is
indistinguishable from an implemented one. When one becomes live, add its
modifier in the same task that deletes its row.

**It was four until the absolute-positioning milestone, and the pair that left
is the worked example of the rule above.** `position` and `inset` are read by
`placeNode`/`placeAbsolute` now, so their row is gone — and
`StyledElement.position(_:)`/`inset(_:)` landed in the same change that deleted
it (ruling AP-L), because deleting the row without adding the modifiers leaves a
live feature unreachable from the public API. **The enum did not leave whole**:
`Position.relative` has its own row below, on `AlignItems.baseline`'s footing.

**`Style.justifyItems` is the property a reader of this table might expect to
find here and will not — the Stack milestone added it and it never entered
the table.** It has a production reader from the task that declared it
(`positionStackItems`, `Sources/MetalUILayout/FlexEngine.swift`), so it does
not fit "read by no production code." Its inertness *for a flex container* —
`justify-items` has no effect there — is CSS's own behaviour rather than a
gap in this implementation, exactly as `JustifyItems`'s own doc comment
(`Style.swift`) says. Do not add a row for it.

**`overflow` is the counter-intuitive case the clipping-and-scroll milestone
added, and it stays in this table on purpose.** `ScrollView.requestLayout`
now WRITES `viewportStyle.overflow = Axes(both: .scroll)` — the first
production write this property has ever had — but the engine still reads it
nowhere: removing that line was measured (a probe built for exactly this
question) to move no number in the layout it produces. Clipping and scrolling
both work anyway, driven entirely by `ScrollView` pushing an explicit
`pass.clipped(to:offsetBy:)` and registering a scroll region — mechanisms that
do not consult `Style.overflow` at all. So the property documents intent for a
reader of the style, same as CSS's own keyword would, and does nothing when
the engine runs. A production write is not the same as a production read, and
silence in this table on that distinction would read as "implemented" — the
one thing this table exists to prevent. Re-count with the grep below rather
than trusting the number: it was nine before the box model wired `padding`,
`border` and `margin` in, six before wrapping wired `flexWrap`, five before
`align-content` landed, four before absolute positioning wired `position` and
`inset`, and 23 stored properties before the Stack milestone added
`justifyItems` (a stored property with a production reader, not a row in
this table — see above). Count the properties with an *anchored* pattern and
subtract nothing by eye: `grep -cE "^    public var " Sources/MetalUILayout/Style.swift`
returns **24**, because `FlexDirection.isRow` and `.isReverse` are computed
`var`s at the same indentation in the same file. They were declared so the model
matches CSS, and the algorithm that consumes them has not been written yet.

**`wrap-reverse` left this table in wrapping's third task**, and it left as a
whole rule rather than a property: `flexWrap` was already live, and what was
missing was §8.3's cross-axis flip. Both halves are implemented now — the
`align-content` leading offset and each item's `crossAxisOffset` — in
`positionItems`, with three browser fixtures (`flex_wrap_reverse*`).

**Three things the input-and-state milestone left NOT in this table, each with
its reason — because silence at any of them would read as either "inert" or
"fine", and none of the three is quite either.**

- **`PaintPass.isActive(_:)` and `PaintPass.isHovered(_ id: HitboxID)` have no
  production caller inside `MetalUI`.** That is not inertness: both are public
  members of a pass, which exist precisely so an element author *outside* this
  module can use them, and both are correct and pinned. What it does mean is
  that **no built-in element paints a pressed state** — `Box.paint` consults
  `isFocused` and the element-keyed `isHovered`, and nothing at all consults
  `isActive` — so a caller who expects `.onClick { … }` to give a button a
  pressed appearance gets none, and there is no modifier to ask for one the way
  `hoverBackground(_:)`/`focusBackground(_:)` exist for the other two states.
  Adding one is a `Decoration` field and a line in `Box.paint`, on those two
  modifiers' exact footing.
- **A `ScrollView` is now a hover and active target**, because a scroll region
  *is* a hitbox. Benign, and measured rather than assumed: a `ScrollView`
  registers itself **before** descending into its content, so children and
  `Deferred` subtrees register later, outrank it on the registration-index
  tie-break, and nothing is shadowed. Recorded here because "the scroller is
  now in the hover list" sounds like it should shadow its own rows, and it does
  not.
- **`Frame.scrollRegions` and `Window.lastScrollRegions` DID get a row**, below
  — a get-only view with no production reader is exactly the shape this table
  is for, and the two used to disagree about admitting it.

The table is wider than that count, because a property can be read and still
not do what its name promises — a stand-in value, or half a rule. Those rows
are the dangerous ones.

| Declared | Reality |
|---|---|
| `AlignItems.baseline` / `AlignSelf.baseline` | **Falls back to the start edge in TWO places now, not one — and as of M2 the blocker this row used to name is GONE while the work is not done.** The stack milestone added the second: `positionStackItems`' `case .baseline: y = 0` (`FlexEngine.swift`), which is `crossAxisOffset`'s fallback repeated for a container that has no flex axis at all, pinned by `baselineOnAStackFallsBackToTheStartEdge`. Whoever implements baselines owns both sites, and the stack one owns a third missing piece on top of the three below: a stack aligns on *both* axes, and `JustifyItems` has no `baseline` case to fall back *from*. The rest of this row is about the flex site. The row said `crossAxisOffset` "needs font metrics that arrive with the text system in M2". Those metrics exist: `MetalUIText`'s `FontMetrics` carries ascent, descent and leading, pinned against `CTFontGetAscent`/`Descent`/`Leading` by `metricsMatchCoreText`. Nothing is waiting on a milestone, so the three things that *are* missing are named as mechanisms at `crossAxisOffset` (`Alignment.swift`) instead — taxonomy shape 10's rule, applied to the row that motivated it. **(1) The engine cannot see a baseline at all**: a `MeasureFunction` returns a `SizeD`, so an item's first baseline never reaches `collectItems`, and the measure protocol has to carry it first. **(2) `crossAxisOffset`'s signature is the wrong shape**: baseline alignment is not an offset computed per item from `(itemCross, lineCross)` — a line's items must agree on a common baseline, which is a per-*line* quantity this function is never given. **(3) The `wrap-reverse` clause**: CSS Flexbox §8.3 swaps first- and last-baseline alignment in a `wrap-reverse` container, and nothing in the flip `positionItems` does today expresses that — it flips an offset, and baseline alignment is not an offset. Ruling AL-6: the task that makes an API inert records it here; the task that makes one live deletes the row. **The element pipeline's Task 4 made it reachable from the public API**: `StyledElement.alignItems(_:)` / `alignSelf(_:)` take the whole enum, so `.baseline` can now be written by a caller who will silently get `flexStart` — this row is the only thing guarding that, unlike `margin: .auto`, which the modifier's parameter type keeps out of reach. `justifyContent`, `alignItems` and `alignSelf` left this table when the alignment work implemented them and `alignContent` when wrapping's second task did; **a whole enum leaving is not the same as its every case leaving**, and this row is the standing counter-example |
| `aspectRatio` | **0 uses** |
| `margin: auto` (`Style.margin`'s `.auto` case) | **Resolves to 0, not to CSS's answer.** Item margins landed in the box-model task's second step — `resolveMargin` in `Resolve.swift` shrinks the main-axis budget and offsets each item by its own margin — but `.auto` maps to 0 on the single line marked for it in that function, not to CSS's "absorb free space before `justify-content` distributes any." A `margin-left: auto` item that CSS would push to the far end of the line lays out at the line's start instead, silently. Pinned by `autoMarginsResolveToZeroForNow` in `BoxModelTests.swift`, with CSS's real answer named in its comment. **This row's scope was too narrow until the wrapping branch's final review measured it** — the third claim of that shape on this project, after ruling WR-4's and WR-5's. Auto margins are not only a main-axis/`justify-content` gap: WebKit **centres a `margin-block: auto` item within its line on the CROSS axis** and we give 0 (`b` at 90 vs our 0). That was already true under `nowrap`; `align-content: stretch` — the default this branch made reachable — grows lines and widened it (`d` at 255 vs our 225). Whoever implements auto margins owns both axes, not just the one `justify-content` sees. **Unreachable from the public modifier API since the element pipeline's Task 4**, and by a type rather than by a convention: `StyledElement.margin(_:)` takes `Length`, not `Dimension`, so `.auto` cannot be written through it at all. `Style.margin` is still public, so the case is reachable by setting `style` directly |
| `MUIRect.borderColor` / `MUIRect.borderWidths` | **Round-trip the ABI, are drawn by `rect_fragment` — the M0 demo proved that end to end — and nothing in `MetalUI` can set either.** `Frame.fill` hard-codes `.transparent` and zero widths, and `Decoration` deliberately has no `borderColor`. The blocker is the **width**, not the colour: `Style.border` is an `Edges<Length>` whose percentage case resolves against the *containing block's* width, and the engine computes that inside `contentBox` and throws it away, so paint has no resolved width to pair a colour with. Re-resolving one at paint time against the box's own width is the exact mistake the percentage-inset constraint below records. Storing the resolved edges on `LayoutTree` is what unblocks it. Note the asymmetry this leaves: `StyledElement.borderWidth(_:)` is **live** and shrinks the content box, so a border affects sizing today and paints nothing |
| `Position.relative`'s **offset** | **Half-implemented, and the half that is missing is the half CSS is named for.** `.relative` does make a box the containing block its absolute descendants are placed against — live, load-bearing, read by `placeNode`'s `childCB` — and it does **not** shift the box by its own `inset` while reserving its in-flow space, which is what `position: relative` means in CSS. A `.relative` box lays out exactly where a `.static` one would. **Reachable from the public API since ruling AP-L**: `StyledElement.position(_:)` takes the whole enum, so `.position(.relative).inset(...)` compiles today and moves nothing, exactly as `.alignItems(.baseline)` does — and this row is the only thing guarding it, since the modifier's parameter type cannot keep one case of an enum out the way `margin(_:)`'s `Length` keeps `.auto` out. The mechanism, not a milestone: `placeAbsolute` is the only reader of `Style.inset`, and it is reached only from `placeNode`'s `position == .absolute` loop — nothing consults a `.relative` box's own inset at all. Implementing it means offsetting a box after in-flow placement without disturbing the space it reserved, which touches `positionItems`/`positionStackItems` rather than the absolute path. `position` and `inset` as *properties* left this table when absolute positioning wired them; **a whole enum leaving is not the same as its every case leaving** — see the `AlignItems.baseline` row, which is the standing counter-example this one joins |
| `overflow` | **Written for the first time, still read nowhere.** `ScrollView.requestLayout` sets `viewportStyle.overflow = Axes(both: .scroll)` (ruling CL-B) — a production write, which is more than `aspectRatio` has ever had — but the engine consults it in no code path: `grep -rn "\.overflow\b" Sources/` outside `Style.swift`'s own declaration returns **three lines: one write** (`ScrollView.swift`) **and two doc mentions** (`ScrollView.swift`, `StateTable.swift`), **and nothing that reads it back** — re-run at the end of the input-and-state milestone. The "no read" half is the claim; the line count moves with the prose, as the `evictUnusedSince` row below has now been caught by twice. Clipping and scrolling both work, but through `ScrollView` pushing an explicit `pass.clipped(to:offsetBy:)` and registering a scroll region directly — mechanisms independent of this property. Kept as its own row rather than folded into `aspectRatio`'s, because a write with no read is a sharper trap than a property nobody touches at all: a reader who sees `ScrollView` set `overflow: .scroll` and then finds clipping working would reasonably conclude the two are connected |
| `AnyElement` / `ElementObject` / `AnyElementBox` | **Fully implemented; reachable from a container, produced by nothing.** The element pipeline's Task 4 gave it `extension AnyElement: ElementGroup`, so `Row { AnyElement(x); y }` compiles and lays out — that is §4.6's escape hatch, and it is the only conformance in `Sources/MetalUI` that boxes. **What still has zero callers is the *production of* an `AnyElement`**: nothing in `ElementBuilder` returns one, so a box exists only where an author wrote `AnyElement(…)` by hand, and today that is tests alone. **It must not become the default path** (§4.6 allocation mitigation 1): the builder preserves concrete types, so `Column { Label(…); Button(…) }` builds `Column<Pair<Label, Button>>`. The guard is `theBuilderPreservesConcreteTypesRatherThanBoxing` in `ElementLayoutTests.swift`, and it is **type-level on purpose** — no layout or paint assertion in the repo can see boxing. **Re-measured, with a mutation that compiles.** The number this row used to quote came from adding `buildExpression<E: Element>(_:) -> AnyElement` to `ElementBuilder`, and that mutation **no longer compiles**: `anExplicitAnyElementIsStillAcceptedAsAChild` — added by that same commit — puts an `AnyElement` inside a builder block, so the generic overload demands `AnyElement: Element`, which it is not, and the suite fails to build with `error: static method 'buildExpression' requires that 'AnyElement' conform to 'Element'`. Pairing it with a non-generic `buildExpression(_ e: AnyElement) -> AnyElement` restores the measurement: **exactly the three type-level tests in that file redden, and no behavioural test at all — re-measured `--no-parallel` on 2026-08-27 after structural identity, out of 358 rather than the 303 first recorded, and the three are the same three.** Universal identity does not disturb it: `AnyElement`'s `requestGroupLayout` consumes one cursor index exactly as `Element`'s default does, so boxing every child moves no path and no `StateTable` entry. Delete this row when the static path demonstrably does not serve a real container |
| **Colour glyphs** (emoji, `COLR`/`sbix`) | **Wrong rather than absent, and now visibly so.** Spec §6.1 routes them to a *polychrome* atlas that skips tinting; there is no polychrome atlas in M2 and `GlyphRaster.rasterize` does not detect one either. So `CTFontDrawGlyphs` renders an emoji into the `DeviceGray` context as a **luminance silhouette**, it packs into the R8 atlas like any other glyph, and `glyph_fragment` multiplies it by the text colour — `Text("hi 🎉")` paints a flat blob in the text's colour where the emoji should be. It does not trap and it is not blank, which is exactly why it is written down: **nothing in this repo can see it**, there being no oracle for a rendered glyph at all (spec §4.2). The fix is a second atlas and a second draw path, not a branch in the rasterizer. Note that it was *invisible* rather than *wrong* until the glyph emitter landed — this row's status changed without its text changing, which is the shape ruling CS-E names |
| `GlyphAtlas.evictUnusedSince(_:)`, and the grow-only atlas it leaves | **Zero production callers — and a caller would make things WORSE, not better, until the packer can reclaim.** That is the mechanism, and it is checkable rather than a milestone to wait for: the shelf packer never revisits a closed shelf, so evicting a key frees a dictionary entry and **strands its pixels**; the next frame that wants that glyph packs a *second* copy further down. Calling eviction every frame therefore makes the atlas fill **faster**. `grep -rn "evictUnusedSince" Sources/` finds **no call at all** — only the declaration in `Atlas.swift`, the string inside its own precondition message, and doc comments in `Atlas.swift`, `ShapingCache.swift`, `Frame.swift` and `Window.swift` — the same shape as `LayoutTree.reset(generation:)` below. **No count is quoted, deliberately, and this row is the reason the rule exists**: it read "nine" through two milestones, was corrected to "eleven" at the end of the input-and-state milestone, and was already **12** by that milestone's own last commit, without one line of eviction code changing — the number tracks the PROSE, and the "eleven" breakdown was additionally self-inconsistent as written ("2 + nine doc comments" is 11, but its per-file list summed to 11 *doc comments*, which is 13). Run the grep and read the lines; "no call" is the claim, and it is the only half that stays true while the comments move. The two neighbouring rows dropped their counts for this reason one fix round earlier. The frame brackets it depends on *are* live: `Frame.render` calls `beginFrame`/`endFrame` around the paint phase, so the ordering guard is enforceable; what is absent is only the call. **These three facts are one story, so read them together:** eviction is unwired, the atlas is therefore **grow-only**, and when it is full `Frame.draw` **silently drops** the glyphs that will not fit — a window showing an unbounded stream of distinct glyphs loses text with no error anywhere. What unblocks it is a repacker or a whole-atlas rebuild, not a call site. Its guards (`evictingDuringFrameConstructionTraps`, `aGlyphUnusedSinceAnOlderGenerationIsEvicted`) stay for `LayoutTree.reset`'s reason: they pin the contract for whoever does call it |
| `Style.alignSelf` on a **stack child** | **Ignored entirely, and it is the most misleading inert API this table holds** — an *alignment* property, public and live for flex, silently doing nothing on an *alignment* container. `Stack { Box().alignSelf(.flexEnd) }` compiles today: `StyledElement.alignSelf(_:)` is a live modifier and `Stack` conforms to `StyledElement` as of the stack milestone. Measured at that milestone's final review: a 20x10 child with `alignSelf = .flexEnd` in a 100x60 stack lays out at **`y = 0`**; WebKit's grid puts the same child at **`y = 50`**. The mechanism, not a milestone: `positionStackItems` reads the *container's* `alignItems`/`justifyItems` once before its item loop and never consults `tree.style(item.node)` for an override — the only per-item style it reads is `size`, for the `stretch` carve-out. Per-child alignment was out of the milestone's scope, and closing it needs **two** things rather than one: `alignSelf` for the block axis and a `justifySelf` that does not exist in this `Style` at all for the inline one, since implementing one alone would make a stack's two axes disagree about whether a child may override its container. Recorded at `Display.stack`'s own doc comment (`Style.swift`) as well as here |
| `Style.padding` / `Style.border` / `Style.margin` on a **leaf** | **Ignored entirely — for a `Text`, not "resolved wrongly".** `measureNode` returns a leaf's measure result unchanged where it adds a container's `edges` back on, and `contentBox` only ever runs on a node with children, so a leaf's border box *is* its content box. `Text(…).padding(Pixels(8))` therefore changes no size and moves no glyph, and `Text.paint` lays its glyphs from `bounds.origin` on exactly that basis. Consistent, and consistently wrong against CSS. **Reachable from the public API**, unlike the `Style` properties above: `StyledElement.padding(_:)`/`.borderWidth(_:)`/`.margin(_:)` are live modifiers that do the right thing on a `Box` and nothing on a `Text` — which is the shape this table exists for, an API that is implemented for one receiver and inert for another. Whoever implements a leaf's box model owns the paint half too: the glyph origin becomes the content box and must come from the engine rather than be re-resolved at paint time, for the percentage-inset reason recorded at `Frame.fill` |
| `StyledElement.hidden()` / `Style.display = .none` on a subtree that **draws** | **Live for layout, ignored by paint, and the failure is glyphs at the window's top-left corner.** The engine really does filter a `.none` node out of its parent's item list, so its rect stays at `LayoutTree`'s zero — that half works and is what the modifier's doc comment used to describe in full, which is exactly why the comment misled: it explained the layout half completely and said nothing about paint, so it read as "paints nothing". Nothing in `Sources/MetalUI` reads `Style.display` during paint at all. `Box.paint` recurses into `content.paintGroup` unconditionally, and fills its own bounds whenever it carries a `.background`; that fill is a harmless zero-size rect, but the children paint from the node's **origin**, and a node that was never placed has origin `(0, 0)` in *surface* coordinates. `Text.paint` then re-shapes at `max(bounds.width, smallestWrapWidth)` with `smallestWrapWidth == 0.5`, so the string wraps after every character and stacks one glyph per line down the window's left edge. **Measured** with a throwaway probe rather than read: `Column { Box { Text("Hi") }.width(80).height(20).hidden(); Box().width(40).height(10) }` in a 400×300 frame emits **0 rects and 2 glyphs**, at `(0, 2)` and `(−1, 18)` — the second negative in x. **0 rects, not one zero-size rect**: neither `Box` in that probe carries a `.background`, so nothing fills at all and the glyphs are the entire output. Re-measured 2026-08-28; this row said "the expected zero rect and two glyphs" until then. **Nothing in the suite can see it**: every existing `hidden()` test asserts a rect, and a zero rect is exactly what a correct implementation produces, so the glyphs are invisible to every assertion that exists. Found while evaluating a key-toggled modal for the demo and rejected on this basis — the demo uses an `@ElementBuilder` `if` instead, which removes the element from the *tree* rather than from the item list. The fix is a `display` check in paint (probably in `Element`'s group walk, so it costs one test per phase rather than one per element); until then `hidden()` is safe on `Box`es, wrong on anything that draws, and — as of the input-and-state milestone — **wrong on anything FOCUSABLE, which is a new failure mode rather than an instance of the paint one**. Measured through a real `Window`: a `.focusable().onKey { … }.hidden()` box registers as focusable, `focus(_:)` sticks, it **claims the keystroke**, the window's `onInput` fallback sees nothing, and focus is **retained** across the next frame — `Frame.resolveFocus()` cannot clear it, because the element's `prepaint` genuinely ran. **The differential is what makes it new**: the same box with `onClick` registers a `(0,0) 0x0` hitbox, so the *pointer* side is protected by geometry (`Bounds.contains` is half-open), while focus registration reads no geometry at all — deliberately, that being the design's own argument for riding on `registerHandlers`. `display: .none` is invisible to it, and the consequence is keystrokes vanishing into an element nobody can see. **No deliberately-wrong pin, and that judgement is carried rather than hidden**: the paint half of this row has no pin either, one `display` check in the group walk closes both halves, and a single pin covering both is the better artifact — but nothing enforces that, so the next person to touch `hidden()` owns all three failures |
| `Frame.scrollRegions` / `Window.lastScrollRegions` | **Get-only derived views with ZERO production readers — `LayoutTree.reset`'s exact shape, arrived at by a refactor rather than by never being wired.** They were the framework's scroll registry until the input-and-state milestone folded scroll regions into the one hitbox list (design spec §3.1); keeping the names as accessors is what let every routing assertion written against the old registry pass **unedited**, which was that task's whole safety argument and is why this is the right call rather than dead weight. But `Window.applyScroll` ranks against `lastHitboxes` directly, `Window.lastScrollRegions` derives its own view from that same array rather than calling `Frame.scrollRegions`, and nothing else reads either. Verify with `grep -rn "scrollRegions" Sources/`, which returns **five lines and no call site at all**: the one declaration this pattern matches, in `Frame.swift`; two doc lines, one in `Frame.swift` and one in `Window.swift` (the latter the sentence you are reading, quoted back); and two references in `Hitbox.swift`'s prose. **No line numbers, on purpose** — this row cited `Frame.swift:420` and `:400` when it was written and both were wrong by the end of the same milestone (**431** and **401**), the second time line numbers in this table have moved inside one milestone. Read the five lines the grep prints; the count and the "no call site" claim are two separate assertions and both were re-run here. **The pattern is case-sensitive and therefore misses `Window.lastScrollRegions`' own declaration** — so it finds one declaration, not two, and a case-INSENSITIVE sweep (`grep -rni "scrollregions" Sources/`) is what sees both. No count is quoted for that one deliberately: it matches every prose mention including this row, so it moves whenever the prose does. The load-bearing half is "no call site", which holds under either pattern. (This sentence said "the two declarations" and named no doc lines until the counts were actually run — a correction written from reasoning rather than from the grep it prescribes, which is the exact failure the practices doc's first record-mechanism names.) `Window`'s one already said "test observability" in its first line; `Frame`'s did not and read as a live API — it says so now. **Keep both**: they are what several routing tests read, and deleting them churns green tests to prove nothing |
| `LayoutTree.reset(generation:)` | **Zero production callers.** `grep -rn "\.reset(" Sources/` returns **three** lines and none is a call: the string inside its own precondition message (`LayoutTree.swift:135`), a doc comment on the method that quotes this very grep (`:116`), and — added by the input-and-state milestone — a doc line in `Frame.swift`, where the `Frame.scrollRegions` row below cites this one as the same shape. (Line numbers are deliberately not given for the prose lines: they moved twice inside this one fix round.) (It matched one line when this row was written and two after the method's own doc comment landed, so re-run it rather than counting — the claim is "no call", not any particular number, and this row has now been made stale twice by prose that merely mentions the symbol.) The element pipeline's plan predicted a per-frame reset; `Frame` allocates a **fresh `LayoutTree` each frame** instead (spec §4.1), so the capacity-reuse path this method exists for is never taken. It is not inert in the sense the rows above are — it works, and its four guards in `LayoutTreeTests` prove the ruling C-3 staleness contract fires — but its doc comment reads as a live API, which is exactly the situation `newLeaf` is listed here for. **Keep the guards**: they pin the contract for whoever does call it, and C-3 is the hazard this repo has already been bitten by |
| `@State` inside an `AnyElement` | **Silently inert — returns its initial value forever, with no diagnostic.** The input-and-state milestone's Task 2 seeds every `@State` an element declares from two sites: `Element`'s default `requestGroupLayout` (`ElementGroup.swift`) and `Frame.render`'s own root path. `AnyElement.requestGroupLayout` (`ElementGroup.swift`, the `extension AnyElement: ElementGroup` block) is a hand-kept duplicate of the first of those two — written before `@State` existed, and never updated — so it never calls `StateBinder.bind`. Measured with a throwaway probe: `Box(content: AnyElement(Counter(...)))` rendered for three frames leaves the shared `StateTable` with **no entry at all** for the counter's slot, where the identical `Counter` unboxed in a plain `Box` leaves it holding the accumulated **3** — one increment per frame. (Re-measured during Task 2's re-review, which read `nil` against `Optional(3)`. This row said `count == 1` when first written, which contradicted its own "accumulated" in the same sentence: 1 is the entry *count* after one frame, not the value after three.) **Not a one-line fix**: `Mirror(reflecting: anyElement)` sees only the boxed `any ElementObject`, not the erased element's own stored properties, so there is nothing for `StateBinder` to reflect even with the call added — closing this needs a hook on `ElementObject` or reflection inside `AnyElementBox` itself, a design decision rather than a patch. **Nothing in production reaches it today**: the `AnyElement` / `ElementObject` / `AnyElementBox` row above already records that `ElementBuilder` produces no `AnyElement` — every one in the tree today was written by hand, and today that is tests alone |
| `StateTable.isDirty` | **A production write with no production read — the `Style.overflow` shape, narrower.** Task 3 of the input-and-state milestone (§2.6) added it alongside `write(_:_:)`, which sets it on every `@State` mutation. Nothing reads it back: `grep -rn "isDirty" Sources/` finds the declaration, the set inside `write`, the clear inside `clearDirty`, and doc comments — no `if stateTable.isDirty` anywhere, in `Window` or elsewhere. **Narrower than `Style.overflow`'s row**, because `StateTable` is `internal` (unreachable from outside `MetalUI`, unlike `Style`, which is public API a caller can read and be misled by) — the risk here is a future contributor inside this module, not an external one. The entire production mechanism is the sibling `onWrite` hook: `write` fires it unconditionally on every call, so a hypothetical `if stateTable.isDirty { window.setNeedsRedraw() }` would be dead code, not a fix — `onWrite` already called `setNeedsRedraw()` by the time such a read could happen. **Kept anyway, not deleted**: it is the observable this task's own tests read (`writingStateMarksTheTableDirtyAndReadingDoesNot` and others in `StateTests.swift`), two of which construct no `Window` at all, so removing it would mean rewriting green tests to chase a hook-invocation counter instead. `Window.drawFrameIfNeeded` clears it *before* `renderRoot` runs rather than after — but that ordering has no production consequence either, since a write during render reaches `needsRedraw` (which nothing clears again before the function returns) through `onWrite` regardless of where the clear sits. The ordering exists only to keep `isDirty` itself coherent for whatever next reads it back, which today is only a test |

Re-check any row rather than trusting this table:

```bash
grep -rn "aspectRatio" Sources/ | grep -v "var aspectRatio"
```

**When you implement one, delete its row.** When you add a property you cannot
implement yet, add one — silence at a declaration reads as "implemented", and that
is taxonomy shape 4 in the practices doc.

## Build

`swift build` · `swift test` — **755 tests** and 87 browser fixtures, warning-free
(re-measured 2026-09-01 `--no-parallel`, after the sizing milestone's
whole-branch fix wave; 752 and 86 through the milestone's own twelve tasks,
which closed BM-4, FS-3 and TX-H — the last three of this framework's four
sizing divergences to close, `SZ-A` having closed the root-percentage one
earlier in the same milestone). Per rulings CS-M/CS-N/SI-H: a
count is stale the moment a test is added, so it is taken at the latest commit
rather than at the commit that first quoted it.

**Typecheck guards: still 29** — 19 `PhaseSeparationTests` + 7
`ErasureCompileGuards` + 1 `ElementGroupTrapTests` + 2
`Tests/MetalUICoreTests/UnitSafetyTests.swift` (a bare `grep -c` there reads 3;
one is a comment). The sizing milestone touches only `FlexEngine.swift` and
its own test files, none of which holds a `canTypecheck` guard, so this count
was never expected to move and re-measuring it (by grep, both counting
methods agreeing) confirms it did not.

**The sizing milestone's own climb, task by task** (baseline **741** tests, 81
goldens, 29 guards, warning-free — this milestone's own ledger's first line).
**Fixture-first means the suite was deliberately RED for most of it**: a
fixture-writing task commits a comparison test that fails against today's
engine on arrival, and a later fix task is what turns it green — a red count
below is the method working, not a broken tree. 742 tests, 2 issues after
Task 1 (the root-percentage fixture, intentionally red) and 742 passing after
Task 2 (the root-percentage fix, ruling `SZ-A`) — goldens 81 → 82 at Task 1,
unmoved since. 743 tests, 2 issues after Task 3 (the BM-4 fixture; its own
fixture task discovered that BM-4 and FS-3 compose on the same tree, `SZ-G`'s
ancestor) and 749 tests, 1 issue after Task 4 (the BM-4 fix, five call sites
rather than the one its brief named, `SZ-D`/`SZ-E`/`SZ-F`/`SZ-J`) — goldens
83. **Task 4's own fixture could not go green at Task 4**: BM-4 alone raises
the item's floor to 120, but the pre-existing content-only automatic minimum
still floors it higher, at 130, so the fixture stayed red on its width axis
(130 vs WebKit's 120) until Task 6 implemented FS-3's used-value reading —
the one residual issue is carried, named, through Tasks 5 and 9 below. 750
tests, 5 issues after Task 5 (the FS-3 fixture; both of its numeric
predictions held) — goldens 84. 751 tests, 0 issues after Task 6 (the FS-3
fix, closing both its own fixture and Task 4's carried residual in the same
commit — `SZ-G`/`SZ-H`/`SZ-I`, plus a second fixture,
`sizing_specified_suggestion_is_used_value`, because the first did not
actually discriminate the used-vs-declared reading) and its own fix round
(`ad30a3c`, dropping a stray `FlexEngine.swift.orig` a `git add -A` had swept
in) — goldens 85, one of which (`sizing_over_constrained_grows.json`) is a
legitimate move: the fixture's own HTML was corrected to declare
`display: flex` so the Swift tree and the browser tree describe the same
thing (`SZ-I`), and the golden was regenerated against the corrected HTML,
not against the engine's prior answer. 751 tests, still passing, after Task 9
(demo fallout, run in an isolated worktree in parallel with Task 6's review —
`SZ-K`, `SZ-L`; no test added). 752 tests, 1 issue (ruled) after Task 7 (the
TX-H fixture) and **752 tests, 0 issues** after Task 8 (the TX-H fix, run in
a second worktree in parallel with Task 10 writing the decisions doc —
`SZ-M`, `SZ-N`) — goldens 86. Task 10 (the decisions doc) and this task, Task
11 (CLAUDE.md), touch no `Sources/`/`Tests/` code beyond a two-word ruling-id
rename and reproduce 752/0 exactly.

**The whole-branch fix wave then added three tests and one golden, reaching
755 and 87 — and one of the three closed a REGRESSION this branch shipped**
(ruling `SZ-O`). TX-H's re-measure updated an item's cross size and nothing
above it: the item's *line* extent and the container's `contentCross` were
both computed from the pre-flex sizes and never recomputed, so an
`auto`-height row containing a 40-tall flexed child reported **20**, and a
wrapping container's second line stacked 20pt too high — **overlapping
siblings, a visible rendering defect rather than a wrong number.** Both were
new: with the re-measure disabled the engine is internally consistent and
uniformly wrong, so TX-H made the item right and left the tree incoherent.
The fix is CSS Flexbox's own step order — §9.7 and the re-measure move
*above* the line and container measurement, which is safe because §9.7 reads
no cross-axis field at all (`grep -n
"crossSize\|marginCross\|minCross\|maxCross\|stretchEligible"
Sources/MetalUILayout/ResolveFlexibleLengths.swift` returns nothing) — and it
moved **no golden**: all 87 were regenerated against live WebKit for a zero
`git diff`. Pinned by `crossSizeAfterFlexPropagatesToAnAutoContainer` and
`crossSizeAfterFlexPropagatesToTheLine`, which discriminate rather than
merely cover: moving `contentCross` alone back above the flex loop reddens
only the first, moving the line-size loop alone reddens only the second.
The third test and the golden are
`percentageMainAgainstAnIndefiniteContainerMatchesWebKit` /
`sizing_percent_main_against_indefinite`, closing FS-3's second guard clause
— a percentage main size against an indefinite container, which was live,
reachable, browser-correct and reddened **nothing** under a mutation that
moved geometry three ways.

**All four sizing divergences are closed**, and divergence 3, 5 and 6's
entries are retired above.

**The input-and-state milestone's climb is kept below as its own record.**

**The input-and-state milestone's own climb, task by task** (baseline **609**,
the measure-performance milestone's own end-of-milestone count, which reproduced
exactly — **not 577**, which is that milestone's *own* baseline and is the
number this milestone's task-11 brief carried forward by mistake): 613 after
Task 1 (`@State`'s storage and slot ids), 617 then **618** after Task 2's fix
round (reflection-driven seeding, plus a pin for the ordinal being the `Mirror`
index rather than the position among `@State` children), 622 then **623** after
Task 3's fix round (the dirty flag and the `onWrite` hook, plus the unguarded
`marked.insert` a review found by mutation), **623** after Task 4 — which added
**no test and no commit**, and is a real result rather than a skipped task:
`ScrollRoutingTests` already pinned all four properties the brief named, and the
implementer verified that *by mutation* rather than by reading test names. 631
after Task 5 (the hitbox list) and 631 again after its fix round (a
sort → `.max` rewrite that added no test), 637 then **640** after Task 6's fix
round (hover and active, the `NSTrackingArea`, and two phase guards — the first
time the typecheck-guard count had moved in eight milestones), 644 both before
and after Task 7 (folding scroll regions into the one list; its fix round is
entirely comments), 658 both before and after Task 8 (click dispatch and
`Handlers`), 674 then **676** after Task 9's fix round (the focus tree), 725
then **729** after Task 10's fix round (actions, keymaps, context predicates and
two-stroke — the milestone's largest task at 49 tests). Task 11 is the counter
demo, the documentation and the human-verification record; it adds **seven** —
five in the new `PointerStatePaintTests` for the hover/focus token swaps, one
`swiftc -typecheck` guard for the element-keyed `isHovered` overload, and
divergence 15's deliberately-wrong pin in the new `NestedClipTests` — reaching
**736**. **The whole-branch fix wave then added three, reaching 739**: two in
`FocusTests` for the guarded focus read-back (ruling `IN-X`) — one that focuses
from *inside* a frame and one that pins the in-frame call still being validated
by the next frame — and one in `InputDispatchTests` for click dispatch
inheriting the vanishing-`if` identity adoption, which asserts both the wrong
answer and the naming that removes it. Goldens: **81 before, 81 after, and no
existing golden file modified at
any point in the milestone**, which is exit criterion 2 and the standing check
that input never reached the layout engine.

**Three of those steps are worth reading rather than counting.** Task 4's zero
is the strongest: "already covered" was proved by mutating the ranking walk, the
layer key and the offset clamp and watching named tests redden, one of which
(`aDeferredScrollViewTakesTheWheelFromAnOverlappingSiblingBeneathIt`) reddened
*alone* under the layer mutation while both same-layer tests stayed green — a
discriminating result, which is the hard one to fake. Task 6's +3 includes a
test written because a mutation reddened **nothing**: `mousePosition:
lastMousePosition → nil` in `drawFrameIfNeeded` left 637 tests green, because
every hover test either built a `Frame` with a literal `mousePosition:` or drove
`resolveHover` by hand, so the one line connecting a real mouse event to a
resolved hover was uncovered. And Task 8's whole worth rests on one check:
swapping the two lines that read `active` before `updatePointerState` clears it
reddens **23 issues across 11 test functions**, which is what says `onClick` is
wired through the real input path rather than driven by a test helper.

**The measure-performance milestone's climb is kept below as its own record.**

**The measure-performance milestone's own climb, task by task** (baseline 577,
the absolute-positioning milestone's own end-of-milestone count, which
reproduced exactly): 579 after Task 1 (the counting harness, two of whose three
assertions were **red on arrival by design** — a performance harness that passes
before the work is done is measuring nothing), 581 after Task 2 (the min-content
memo), 581 after Task 3 (docs and the `MP-A`/`MP-B` rulings; it adds no test),
583 then **588** after Task 4's review round (`List` itself, plus five for row
flooring, identity distinctness, an empty list and a modifier reaching the
layout node), 590 then **592** after Task 5's review round (the ambient scroll
context), 595 then **600** after Task 6's review round (windowing — this is the
task that turns the LAST of the harness's red assertions green — the other one,
`aWarmFrameTokenizesEachDistinctStringAtMostOnce`, went green at Task 2 when the
memo landed, so only `aListsWorkIsTheSameFor160RowsAsFor40` survived to here),
603 then **604** after
Task 7's review round (both shaping caches bounded by a generation sweep). Task
8 is the demo and the documentation and adds no test, so 604 reproduced exactly.
**The whole-branch review's fix round then added five, reaching 609**: three in
`ListTests` — one per half of the scroll-context defect the review found, being
the axis clause (MP-M), `Deferred`'s layout-phase escape (MP-N) and divergence
14's deliberately-wrong pin (MP-L) — and two in `ShapingCacheTests`, one pinning
`staleAfterGenerations` at exactly 2 from both sides and one pinning that
`Shaper.unbreakableRunCalls` ignores calls made off the main thread, which is
what makes it safe to be a plain counter at all. **Goldens did not move at any
point in this milestone: 81 before, 81 after, and no existing golden file
modified** — which is the milestone's own second exit
criterion, since it touches the measure path and a moved golden would mean
something reached the engine that should not have.

**The absolute-positioning milestone's climb is kept below as its own record.**

**The absolute-positioning milestone's own climb, task by task** (baseline 538,
the Stack milestone's own end-of-milestone count, which reproduced exactly):
540 after Task 1 (`AbsolutePositioningTests`' two placeholders), 541 after Task
2 (the two placeholders replaced by three flow-filter tests), 544 after Task 3
(containing blocks), 549 after Task 4 (insets, including a regression test for
a 0×0 sizing bug Task 3 shipped — ruling AP-E), 555 after Task 5 (five browser
fixtures plus divergence 9's pin), 561 after Task 6 (`DrawListTests`) and then
**560** when that task's review round deleted a test it had proved redundant,
565 after Task 7 (`DeferredTests`) and **569** after Task 7's second review
round (a `Deferred` identity differential, nested-layer idempotence, and the
prepaint and paint halves of a real `ScrollView` escape). Task 8 is the demo
and the documentation and adds no test, so 569 reproduced exactly. **The
whole-branch review's fix round then added eight, reaching 577**: five in
`AbsolutePositioningTests` for live clauses of the absolute pass that no test
reached (each found by a mutation the 569-test suite passed under), one in the
new `AbsoluteOverlayTests` pinning divergence 11, and two in
`ScrollRoutingTests` for the scroll-region layer key. **Goldens
climbed 76 → 81 in Task 5 and moved nowhere else in the milestone** — five new
`abs_*` fixtures, and **no golden that existed before this branch was
modified**, verified at every task. Stated that precisely because one of the
five *was* regenerated within the milestone: `abs_over_constrained.json` landed
in `385c035` and was regenerated in `ee06f84` after its own HTML was reordered
(its `top: 0; bottom: 0` made "stretch between two insets" and "fill the
containing block" the same number, so the fixture pinned nothing on its
vertical axis until it became `top: 10px; bottom: 20px`). Same shape as the
Stack milestone's "two of the 75 were also regenerated after their HTML was
reordered".

**One count in that list goes DOWN, and it is the interesting one.** Task 6's
review found two tests in `DrawListTests` with byte-identical fixtures, so they
reddened together under every mutation; the resolution was not to keep both but
to redesign the survivor's fixture (conflicting `order` values across primitive
kinds, so only `layer` can produce the expected result) and delete the twin.
A test that catches nothing its neighbour does not catch is not coverage.

**The Stack milestone's climb is kept below as its own record, not folded into
the numbers above.**

**The Stack milestone's own climb, task by task** (baseline 504, measured by
Task 1's bisect against the clipping-and-scroll paragraph's stale 489 — an
unrecorded `ScrollView.scrollIndicators(_:)` commit landed between that
milestone and this one and moved the true starting point): 506 after Task 1
(`StackLayoutTests`), 510 then **512** after Task 2's fix round
(`aStackSizesAnAutoChildFromItsOwnContent`,
`aStackChildsMinWidthClampsItsDeclaredSize`), 517 after Task 3 (all nine
alignments), 522 then **524** after Task 4's fix round (the auto-only
`stretch` engine bug, below), 527 after Task 5 (the `Stack` element and the
`Stack.swift`/`Flex.swift` rename), 529 after Task 6 (nesting fixtures). Task
7 is docs and the demo and adds no test, so 529 reproduced
exactly. The whole-branch review's fix round then added **nine**, reaching
**538**: one browser-fixture test for the percentage bug below, and eight
`StackLayoutTests` cases for clauses that were live and unreached (both
`maxSize` clamps, the measured `minSize` height, the mixed known/auto measure
axis, `containingBlockWidth` at each of the two stack sites, the `?? .stretch`
fallback and `AlignItems.baseline`). Goldens climbed 67 → 72 → **73** (Task 4
and its fix round) → 75 (Task 6) → **76** (the review's fix round; two of the
75 were also regenerated after their HTML was reordered, and no other golden
moved). Every number here was itself re-measured rather
than summed by hand — treat a ±1 against this paragraph as a stale doc, not a
missing test, and re-measure.

**Two findings from that review are worth carrying rather than only counting.**
First, `layOutStack` folded an **unresolvable percentage to 0** where WebKit
content-measures it, and *both* the ruling (ST-E) and the code comment stated
the engine's behaviour backwards — the ruling generalised from a probe whose
percentage child was empty, a shape under which the right and wrong rules give
the same number. Fixed, fixtured, and recorded as an error in
`docs/superpowers/2026-08-28-stack-decisions.md`. Second, **seven of the nine
`Alignment` cases were unguarded**: `allNineAlignmentsMapToDistinctPairs`
asserted distinctness only, which every permutation preserves, so
`Stack(alignment: .leading)` could have shipped drawing on the right. It now
asserts each case's `(alignItems, justifyItems)` pair *and* keeps the
distinctness `#require`, because the two catch different bugs.

The clipping-and-scroll paragraph below is kept as its own milestone's
record, not folded into the numbers above:
Task 10 was docs and the demo and added no test, so Task 9's 482 reproduced
exactly; the whole-branch review's fix round then added **six** — a `ScrollView`
text pin for ruling CL-C, a rect pre-projection clip test, an
unfinalized-scene trap and its positive control, an indicator fade/token
assertion and a horizontal-indicator geometry one — reaching 488 at the
milestone's own last commit. The wrap-investigation record-and-pin work that
followed added **one** —
`roundingCanMakePaintWrapAShrinkWrappedTextThatLayoutMeasuredAsOneLine`,
divergence 8's pin — bringing it to 489. (**That test no longer exists**: it
asserted the wrong answer on purpose, the divergence was fixed on 2026-08-30,
and it was replaced by
`paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox`. The sentence is kept
as the history it is — do not grep for the old name and conclude a test was
lost.) Read the summary line, never
the exit status — shape 11.
The milestone started at **445** (M2's own end-of-milestone count) and climbed
task by task: 451 after Task 1 (`DrawListTests`), 452 after Task 2, 455 after
Task 3 (`ClipTests`), 458 after Task 4, 463 after Task 5 (`ClipStackTests`),
468 after Task 6 (`ScrollViewTests`/`ScrollLayoutTests`), 474 after Task 7
(`ScrollRoutingTests`), 477 after Task 8, 482 after Task 9 (`ScrollIndicatorTests`).
Every one of those was itself re-measured rather than summed by hand at the
time — treat a ±1 against this list as a stale doc rather than a missing test,
and re-measure).
**Eight** non-test targets with strictly one-way dependencies: `MetalUICore`,
`MetalUILayout`, `MetalUIText`, `MetalUIShaderTypes`, `MetalUIRender`,
`MetalUIPlatform`, `MetalUI`, `MetalUIDemo`. **`MetalUITestSupport` is a ninth
`.target` in `Package.swift` and is not one of them** — it lives under `Tests/`,
ships in no product, and holds the single copy of the `swiftc -typecheck`
machinery the negative type-system guards shell out to (ruling EP-1). Count with
`grep -cE "^ +\.(target|executableTarget)\(" Package.swift`, which returns 9
(`.testTarget(` does not match), and subtract `MetalUITestSupport`.

**Spec §3.1 says "seven targets", and it is a different seven.** Its list is
the module *layering* — `MetalUI`, `MetalUILayout`, **`MetalUIText`**,
`MetalUIRender`, `MetalUIPlatform`, `MetalUICore`, `MetalUIShaderTypes` — which
excludes `MetalUIDemo`, an executable rather than a layer. **The two counts used
to agree and no longer do**: M2 Task 1 landed `MetalUIText`, which this section
had already named as the coincidence's expiry date. Eight here against §3.1's
seven is the expected state. Do not "reconcile" one list to the other.

Four constraints that are easy to violate silently:

- **`MetalUILayout` must import only `MetalUICore`.** Verify with an anchored
  pattern — an unanchored `Metal` also matches the legitimate `import MetalUICore`.
- **Every `LayoutTree` that could ever exchange ids with another must have a
  distinct `generation`** (m1a ruling C-3, closed in the element pipeline's task
  4). `LayoutNodeID` carries the generation of the tree that issued it and every
  accessor rejects a foreign one, but the *uniqueness* of the generation is the
  constructor's obligation: `LayoutTree.init(generation:)` has no default
  precisely so that obligation is visible at each call site. In `Sources/` the
  only constructor is `Frame`, which draws from a `@MainActor` counter — check
  with `grep -rn "LayoutTree(" Sources/`. Layout tests pass `0` because their
  trees never exchange ids; a test that puts two trees in one function and moves
  an id between them must not.
- **Pixel format is `bgra8Unorm`, never `_sRGB`.** An `_sRGB` target makes the
  hardware blend in linear space; this framework composites in gamma-encoded sRGB
  by design (§7.8). It would look fine now and make text rendering wrong later.
- **A percentage `padding` or `border` resolves against the CONTAINING BLOCK's
  width — not the box's own width, and not a height. `Style.inset` is the
  exception and takes its own basis per axis.** Both halves of the first
  sentence have been wrong in this repo, and neither failed a test at the time.
  `contentBox` resolved percentage `padding`/`border` against the box's own
  border-box width until the box model's third task; WebKit puts a 200-wide
  `.mid { padding: 10% }` inside a 270-wide content box at **27**, not 20. The
  vertical `padding`/`border` edges take the same *width* basis, which a square
  container cannot distinguish — that is why `flex_percent_padding_nonsquare` is
  400×100 inside an 800×600 viewport, so that all three candidate bases give
  three different answers on every edge. `flex_nested_percent_padding` does the
  same one level down, where the containing block is not the viewport.

  **This constraint used to say "a percentage inset" and it was a trap
  (ruling AP-D).** It was written about `padding` and `border` — where CSS
  really does resolve every percentage against width — but it used the word
  "inset", and `Style.inset` does not follow that rule: `left`/`right` resolve
  against the containing block's **width**, `top`/`bottom` against its
  **height**. Following the old wording literally is wrong on two of four edges,
  and the absolute-positioning design had to instruct its own implementation not
  to cite this bullet. `placeAbsolute` (`FlexEngine.swift`) carries the per-axis
  rule at the one site that reads `Style.inset`; `abs_percent_insets_nonsquare`
  (200×100, so `left: 10%` is 20 and `top: 10%` is 10) is the fixture that can
  see the difference, and a square containing block cannot.

**Adding an AppKit or WebKit test? Run the WHOLE suite and read the summary
line — `--filter` is a different program.** Every test target runs in **one
process**, so an AppKit test and the WebKit layout-oracle tests share a main run
loop. That composition has already crashed the suite once: two
`MetalUIPlatformTests` cases ended in `defer { nsWindow.close() }`, and
`NSWindow(contentRect:…)` defaults `isReleasedWhenClosed` to **true** — an
over-release of a window ARC already owns, which AppKit defers into an
autorelease pool that CoreAnimation pops from a run-loop observer. Alone the
process exited before that pool popped; alongside a test that `await`s it landed
in `-[_NSWindowTransformAnimation dealloc]` as `EXC_BAD_ACCESS`, and `swift test`
died with **297 of 303 tests reported and no summary line**. Fixed at the source
(`AppKitWindow.init` now sets `isReleasedWhenClosed = false`) and pinned by
`closingAWindowDoesNotOverReleaseTheOneARCAlreadyOwns`. **Serializing the two
targets would not have fixed it** — a single `--no-parallel` test that closes a
window and then drives the oracle crashes with no interleaving at all. The full
write-up is under shape 11 in `docs/practices/verifying-tests-can-fail.md`; the
short rule is that a test touching a process-wide host (AppKit windows, WebKit,
CoreAnimation, the main run loop) is only verified by an unfiltered run whose
count you read.

**After editing `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`, run
`swift package clean`.** The header reaches its C target through a symlink SwiftPM
does not track, so Swift's view goes stale while Metal's refreshes — the symptom is
a vanished rect that looks exactly like a shader bug.

**A second, distinct mechanism produces the same class of failure, and it has now
hit three consecutive milestones on this specific signature — four counting the
symlink case above as the family's first member.** Adding a case to a public enum,
or a stored property to a public struct, that crosses module boundaries
(`MetalUILayout` or `MetalUIRender` → `MetalUI`/its test targets) can leave
separately-cached incremental compilations of the two sides disagreeing about the
type's layout or discriminator. **The symptom is not a compile error** — it is
either a `SIGSEGV` or a silent truncation with **no test summary line**, or an
assertion comparing against a value **its own source cannot produce**. The four
occurrences, oldest first:

1. **The symlink case above** — `MetalUIShaderTypes.h` reaching its C target
   through a symlink SwiftPM does not track. A different mechanism with the same
   shape, which is why it is counted as the family's first member and not as an
   instance of this one.
2. **Clipping and scroll, Task 1** — `Scene` gained stored properties; an
   assertion compared against a value its own construction could not have built.
3. **The Stack milestone, twice in one milestone** — a subprocess inside
   `ElementGroupTrapTests`' `#expect(processExitsWith:)` machinery crashed
   deterministically after `Display` gained the `.stack` case, and
   `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` failed because the
   *expected* value it built from a closure containing no reference to `.stack`
   somehow held `display: .stack`.
4. **Absolute positioning, Task 6** — `Scene` gained the `layer` stored property,
   crossing `MetalUIRender` → `MetalUI`. The run truncated mid-suite with no
   summary line, immediately after `bufferIndicesAreStable()` passed. Not chased
   as a logic bug; `swift package clean` and a rebuild gave a clean, repeatable
   561/561.

**`Scene` is the site twice**, which is the closest thing to a predictor this
list offers: it is the one public struct that crosses a module boundary and is
still growing stored properties.

Both symptoms point at a code defect; neither is one. `swift package clean`
followed by a full rebuild has resolved it every time, and the isolated change
then passed cleanly and repeatably. **Recognise it by the shape**: an ordinary
Swift source edit (no `.metal`/`.h` touched, so the symlink hazard above is not
it) that produces a crash or a truncation with no summary line, or a test failure
whose *expected* side contains a value its own construction could not have
produced. Try `swift package clean` before debugging the "impossible" result as a
logic bug.

## Layout cost — measured, and content sizing multiplied it by ~4.9x

`computeLayout` costs **~40 us per node in debug and ~5 us in release**, flat
from 8 k to 88 k nodes. The same trees cost ~8 us and ~1.2 us per node before
content sizing, so **the complexity is unchanged and the constant factor is
~4.9x**. Both figures were re-measured 2026-08-29 after the measure-performance
milestone and still hold — see the re-measurement below for why a milestone
that made the measure path faster moved neither of them. **They also still
hold after the sizing milestone's TX-H fix, on these exact trees — and the
reason needs its own paragraph, immediately below the table, because the
straightforward re-measurement is a false negative (ruling `SZ-N`).**

**Measured during the content-sizing milestone's Task 6 (2026-08-26), on that
machine; debug build unless a column says release.** A performance figure drifts
more quietly than a behavioural one — re-measure before deciding anything on
these.

| tree | nodes | debug before → after | release before → after |
|---|---|---|---|
| depth 12, branch 2 | 8,191 | 72.8 → **372.0 ms** | 10.2 → **45.0 ms** |
| depth 10, branch 3 | 88,573 | 708.4 → **3,504.4 ms** | 96.3 → **456.9 ms** |

**Corroborated 2026-08-27** on the structural-identity branch, and it is
corroboration rather than a re-run: a whole `Frame.render` — element walk,
`computeLayout`, prepaint and paint — over the same node counts cost **369.5 ms**
and **3,540 ms** in debug, **51.6 ms** and **520.7 ms** in release. Those bracket
the `computeLayout`-only figures above from the correct side, so the table has
not rotted on this machine; it has not been re-taken with the same harness.

**RE-MEASURED 2026-08-29** with the table's own harness rebuilt (same shapes,
same `available:`, best of 5 and 3 runs; MacBookPro18,2 / Apple M1 Max, macOS
26.6.2, Swift 6.3.3), after the measure-performance milestone changed the
measure path:

| tree | nodes | debug | release |
|---|---|---|---|
| depth 12, branch 2 | 8,191 | **362.8 ms** (44.3 us/node) | **41.6 ms** (5.08 us/node) |
| depth 10, branch 3 | 88,573 | **3,467.6 ms** (39.2 us/node) | **414.5 ms** (4.68 us/node) |

**RE-MEASURED a third time, 2026-08-31, after the sizing milestone's TX-H fix
(ruling `SZ-M`) — and on these SAME two trees under their default style, the
before/after is noise, not a finding.** `Style.alignItems == nil` resolves to
CSS's initial `stretch`, and a stretch-eligible item is excluded outright by
TX-H's new recompute guard (`SZ-M`) — its cross size comes from the line, not
from content, so the fix's whole code path never fires for a tree built with
no `alignItems` set. Measured anyway, before/after, best of 5: debug 8,191n
440.05→430.65 ms (**-2.1%**), 88,573n 3961.00→4007.64 ms (**+1.2%**); release
8,191n 46.23→50.69 ms (**+9.6%**, noisy at this small an absolute time),
88,573n 443.40→448.48 ms (**+1.2%**) — a benchmark of a configuration in which
the new code is unreachable, the measure-performance milestone's "measure on
a branching tree, never a chain" lesson arriving one level up (ruling `SZ-N`,
`docs/superpowers/2026-08-30-sizing-decisions.md`; also carried into
`docs/practices/verifying-tests-can-fail.md`). **The two tables above this
paragraph — CLAUDE.md's own canonical "~40 us/~5 us, flat 8k-88k" figures —
are therefore still accurate for exactly the tree shape they were taken on**:
a container tree with no `alignItems` declared pays nothing for TX-H, because
it never reaches the branch.

**TX-H's real cost was measured on the same two trees with `alignItems:
.flexStart` on every interior node instead**, so every auto-cross item is a
recompute candidate whenever its main size actually moves — which is
pervasive in a wide, deep, row-branching tree shrinking under an 800x600
offer. That is a DIFFERENT tree from the two tables above (styled, not
styleless) and its numbers are not comparable to them line-for-line; they
answer "what does TX-H cost when its code path actually runs" rather than
"did this milestone change the flat per-node figure":

| tree | nodes | debug before → after | release before → after |
|---|---|---|---|
| depth 12, branch 2 | 8,191 | 463.724 → 459.048 ms (56.62 → 56.05 us/node, **-1.0%**) | 51.133 → 51.712 ms (6.24 → 6.31 us/node, **+1.1%**) |
| depth 10, branch 3 | 88,573 | 4173.606 → 4272.613 ms (47.13 → 48.24 us/node, **+2.4%**) | 476.815 → 492.135 ms (5.38 → 5.56 us/node, **+3.2%**) |

The larger, more stable sample (88,573 nodes) shows a consistent **+2.4%
(debug) / +3.2% (release)** cost when TX-H's recompute path is exercised on
essentially every eligible item — a worse case than most real trees hit,
since most flex layouts are not universally `flexStart` with universal
shrinking. The 8,191-node debug delta (-1.0%) is within run-to-run noise at
that tree's absolute cost (~460 ms). **Nothing here moves the ~40 us/node
debug / ~5 us/node release order of magnitude the canonical tables above
record** — that figure describes the default-style tree, which TX-H does not
touch at all.

**The table above is confirmed, not corrected — and the reason it did not move
is the thing to carry.** This milestone memoized the min-content width of a
**string**, in `ShapingCache`; these trees contain no `Text` at all (interior
nodes are auto-sized flex containers, leaves are 10x10 boxes), so not one call
in them reaches the memo. A tree of boxes costs today what it cost before, and
anyone reading "the measure path got faster" as "these numbers got smaller"
would be reading a text optimisation into a tree with no text in it.

**Where the milestone's change actually shows is a tree with `Text` in it, and
the demo is the one to quote.** The whole `Frame.render` over
`Sources/MetalUIDemo/main.swift`'s real element tree at 920x560, release, best
of 200 warm renders on the machine above:

| demo list | base commit `adaab87` (a `for` loop over every row) | today (`List`, windowed) |
|---|---|---|
| 40 rows | 5.366 ms | **1.279 ms** |
| 500 rows | 50.498 ms | **1.273 ms** |

Debug, same tree: 15.295 / 145.463 ms before, **5.069 / 5.060 ms** today. Two
independent effects are stacked in that table and it is worth keeping them
apart. **The 40-row column is the memo** — the same rows, ~4.2x cheaper, because
each `Text`'s min-content width is now a dictionary hit instead of a tokenizer
walk. **The 500-row row is the window** — flat in row count, because `List`
builds only the rows the viewport intersects. Neither number says anything
about the box-tree table above, and vice versa.

**Re-measured 2026-08-29 after the input-and-state milestone put a counter in
that tree, and the question it answers is whether hitbox registration undid any
of the above.** Same machine, same 920x560, release, best of 200 warm renders
after 10 warm-ups, both arms in one process so the comparison is not across
runs. "OLD" is this branch's base commit `76a878a` — the demo *without* the
counter — rebuilt beside the current tree rather than quoted from the row above:

| demo tree | 40 rows | 500 rows |
|---|---|---|
| OLD, no counter (base `76a878a`) | 1.340 ms | 1.347 ms |
| NEW, counter with **no handlers at all** | 1.562 ms | 1.564 ms |
| NEW, counter as shipped | **1.571 ms** | **1.570 ms** |

**Registration is ~0.01 ms — about **4%** of what the panel costs and ~0.6% of a
frame.** (From the table's own numbers: (1.571 − 1.562) / (1.562 − 1.340) = 4.1%,
and 0.009 / 1.571 = 0.57%. This sentence gave the frame ratio twice and
understated the panel ratio sevenfold until it was recomputed.) The third row differs from the second only by an `onClick` on each
button, `.focusable()`, `.keyContext(_:)` and two `.onAction(_:_:)` handlers, so
the gap between them is the whole cost of putting an element into the hitbox
list, the focus registry and the action registry. The 0.22 ms between the first
two rows is the panel *itself* — three more `Text` leaves, each measured by the
tokenizer, plus four boxes — and has nothing to do with input.

**The flatness in row count is untouched, which is the property that mattered:**
1.571 ms at 40 rows against 1.570 at 500.

**The OLD arm reads 1.340/1.347 where the row above records 1.279/1.273 for the
same tree.** ~5%, one milestone and one harness apart, on the same machine. The
conclusion is unaffected either way, but the numbers to reproduce are the ones
in *this* table, taken by the method it describes.

**The cause is §4.5's automatic minimum, which now probes EVERY item** —
`min-width: auto` is CSS's default — and an `auto`-cross item probes again, so a
container's children are each measured up to three times per layout. Whoever
optimises this starts there: it is the probe that fires unconditionally. The
memo cache in `LayoutContext` is what keeps this a constant multiplier instead
of the depth-exponential ~700x the design spec predicted without it, and
`theCacheIsActuallyConsulted` is the only test that can see the cache working.

**Measure on a BRANCHING tree, never a chain.** A chain has one child per level,
so the three probes per item collapse onto the same few cache keys and the cost
looks linear and cheap — which is exactly what the during-task measurement
showed, and why this number went unrecorded until the milestone's last task.
Absolute figures are this machine's; the ratio is the part that transfers.
Release is ~8x faster in absolute terms with the same ratio. For scale, Yoga and
Taffy are quoted in the 0.1-0.5 us/node range.

### Identity path construction — measured 2026-08-27, and it is ~0.4% of a frame

**Measured 2026-08-27 on the structural-identity branch, debug unless a column
says release**, with a throwaway spike deleted in the same task. Re-measure
before deciding anything on these. The counterfactual is the pre-milestone array
representation (`(parent?.path ?? []) + [component]`) reconstructed beside the
shipping linked list and timed on the same trees in the same process; best of
five, one path per node.

**The `depth` column counts LEVELS here and EDGES in the table above** — the two
harnesses were written a day apart and disagree. The **node count** is the
unambiguous key, and it is deliberately the same 8,191 and 88,573, so the rows
line up despite the labels.

| tree | nodes | avg depth | linked us/node | array us/node | ratio |
|---|---|---|---|---|---|
| 13 levels, branch 2 | 8,191 | ~12 | **0.154** / 0.093 rel | 0.697 / 0.300 rel | 4.5x / 3.2x rel |
| 11 levels, branch 3 | 88,573 | ~10 | **0.150** / 0.088 rel | 0.660 / 0.272 rel | 4.4x / 3.1x rel |
| 3 levels, branch 90 | 8,191 | ~3 | **0.144** / 0.084 rel | 0.501 / 0.141 rel | 3.5x / 1.7x rel |

**The third row is the control**, and it is what makes this a measurement of the
O(1)-vs-O(depth) claim rather than of the tree: same 8,191 nodes, average depth
~3 instead of ~12.

**Release is the load-bearing column for the O(1) claim, and an independent
re-run is why this clause exists.** In debug the linked list's own depth
sensitivity across the control (−6% here, −25% in the re-run) is comparable to
the array form's (−28% here, −18% there), so the debug rows do not separate the
two models cleanly — allocation and retain/release traffic dominate both. In
release they do separate: array 0.300 → 0.141 against linked 0.093 → 0.084. Read
the release figures for the claim and the debug figures for the absolute cost.

**End to end the win is at or below noise, and that is the honest headline.**
Path construction is 0.3-0.4% of a debug `Frame.render` and ~1.5% of a release
one. The saving over the array form is 4.5 ms on the 8,191-node tree against a
7.2 ms run-to-run spread — **not visible above noise** — and 45 ms against a 19
ms spread on the 88,573-node tree, which is measurable and still ~1.3% of the
frame. The linked list is the right structure for the reason it was chosen (it
removes a depth factor from a per-frame cost for one allocation's price), but
nobody should expect a frame-time change from it while `computeLayout` costs
~40 us/node.

## When CI lands

Three guarantees silently lapse under plausible configurations and must be
required, non-gateable jobs. All three are detailed in the decisions docs:

1. The ABI probe **skips** without a Metal device.
2. `committedGoldensMatchTheBrowser` is the only live-WebKit consumer.
3. **The 29 `swiftc -typecheck` guards skip whenever `.build` is not where
   `#filePath`-relative resolution expects it.** `canTypecheck`
   (`Tests/MetalUITestSupport/Typecheck.swift`) walks three directories up from
   its own `#filePath` and looks for `.build/<triple>/debug/Modules` holding the
   module; a `--scratch-path`, a CI that builds elsewhere, a moved checkout, or
   `swift test -c release` all make that miss and every guard becomes a skip.
   **That set is this milestone's headline deliverable and both of its
   compile-time exit criteria** — `PhaseSeparationTests` (**19**),
   `ErasureCompileGuards` (7), `ElementGroupTrapTests` (1), `UnitSafetyTests` (2,
   in `Tests/MetalUICoreTests/`, where a bare `grep -c` reads 3 because one is a
   comment)
   — and none of them has a runtime equivalent, by construction: each asserts
   that something must *not* compile, so a regression makes the offending code
   compile and leaves every ordinary test green.

   **Taxonomy shape 11's count heuristic does not catch this one.** Measured, by
   forcing `canTypecheck` to `false`: exactly 25 tests report as skipped, the
   total does not move, and the run passes. The 25 was first taken at
   `Test run with 304 tests`, re-measured at 358 on the structural-identity
   branch, and **re-counted at the end of M2 (suite 444): still 25 — 15 + 7 + 1
   + 2 across the four files**, where `grep -c canTypecheck` reads 3 in
   `UnitSafetyTests` because one is a comment. **Re-counted again at the end of
   the clipping-and-scroll milestone (suite 488), again at the end of the
   stack milestone's review round (suite 538), and again at the end of absolute
   positioning (suite 577): still 25. Re-counted again at the end of
   measure-performance (suite 604), and once more after that milestone's
   whole-branch fix round (suite 609): still 25 — by grep both times (15 + 7 + 1
   + 2 across the four files) rather than by forcing `canTypecheck` to `false`,
   which is the weaker of the two methods and is said so rather than implied.**
   The suite has
   moved 304 → 358 → 444 → 488 → 538 → 577 → 604 → 609 and the guard count has not moved at
   all, which is the paragraph's point arriving as eight data points rather than as
   one delta — the argument is that the two numbers are independent, so do not
   restate it as "the suite grew by N and the 25 held", which rots the moment N
   changes. **The guard count does not track the suite count and neither number
   implies the other.** A falling suite count
   is the signal shape 11 tells you to watch, and this failure does not move it.

   **It finally DID move, at the input-and-state milestone's Task 6 fix round
   (suite 640): 27 — 17 + 7 + 1 + 2, by grep.** `PhaseSeparationTests` gained
   two, `queryingHoverDuringPrepaintDoesNotCompile` and
   `queryingActiveDuringPrepaintDoesNotCompile`, for `theme`'s own reason
   stated sharper: a colour read during prepaint simply fails to compile, but
   `isHovered`/`isActive` would **compile and lie** if reachable there —
   returning a silently wrong `false` from a syntactically fine call. Two
   independent things make it wrong, and the guard is worth having for the
   second even more than the first: `Frame.hoveredHitbox` is still `nil`
   because `resolveHover(at:)` runs *after* prepaint returns, **and** the
   hitbox list is still being built, since `PrepaintPass.insertHitbox` is
   what fills it. So a prepaint-time answer would be wrong even if hover
   had somehow already resolved — it would rank against a partial list,
   which is exactly §3.3's reason for resolving once at the boundary
   rather than during registration: "topmost wins" is not knowable until
   every hitbox is registered. (This sentence said the opposite when first
   written — "every hitbox has already registered by the time
   `PrepaintPass` runs" — which inverts the mechanism the guard exists
   for.) **This does not contradict "the guard count does not track the
   suite count" above — it is the other half of the same claim, not an
   exception to it.** Every prior re-count held 25 steady while unrelated
   tests were added elsewhere; this one moved because a guard was
   *deliberately written* in the same change that could have introduced the
   hazard it guards against, which is what a compile-time guard is for. The
   two numbers still do not imply one another: 640 does not say 27, and nothing
   here claims it does.

   **It then moved twice more in the same milestone, to 28 and to 29 — and
   both times for that same reason, which is the pattern to recognise rather
   than a count to memorise.** Task 9 added
   `queryingFocusDuringPrepaintDoesNotCompile` (**28** = 18 + 7 + 1 + 2) and
   Task 11 added `queryingElementKeyedHoverDuringPrepaintDoesNotCompile`
   (**29** = 19 + 7 + 1 + 2). Both are guards written in the same change that
   could have introduced the hazard. **Re-counted by grep at the whole-branch
   fix wave (suite 739): still 29** — 19 + 7 + 1 + 2 across the four files,
   where `grep -c canTypecheck Tests/MetalUICoreTests/UnitSafetyTests.swift`
   reads 3 because one of them is a comment. The fix wave added three tests and
   no guard, which is the paragraph's own claim arriving once more.

   **The focus one is the case worth reading, because its brief FORBADE adding
   it by symmetry and the measurement went the other way from how the question
   was framed.** The framing was "focus is window state fully known before the
   frame starts, so `isActive`'s justification may not apply". Measured: an
   element that stops being focusable reads `prepaint=true / paint=false` in
   the **same frame**, because `Frame.resolveFocus()` clears at the boundary —
   so a prepaint-time `isFocused` returns a wrong `true`. And answering that
   honestly for the new guard answered it for an old one **in the opposite
   direction**: `isActive`'s guard is *not* a measured lie, because
   `Frame.activeElement` is a `let` assigned once in `init` and a prepaint-time
   `isActive` would answer correctly. Its guard is kept as placement insurance,
   and the shared comment says so instead of implying one measurement covers
   all three. The paragraph above still describes `isHovered` correctly; it
   described `isActive` wrongly until this was measured.

   **Task 11's is a second SPELLING rather than a second member.** The
   element-keyed `isHovered(_ id: GlobalElementID)` overload landed for
   `Box.paint` to reach (ruling IN-V), and the existing hover guard probes the
   `HitboxID` spelling — so adding *only* the new one to `PrepaintPass` would
   leave that guard green while shipping the identical hazard. Two spellings
   need two probes.

   **Re-count by grep, and note the DIRECTORY**: `Tests/MetalUICoreTests/UnitSafetyTests.swift`,
   not `MetalUITests`. A recheck that greps the wrong directory silently reads
   26 instead of 29, and the file itself reads 3 by a bare `grep -c` because
   one occurrence is a comment.

   **Not converted to a hard failure, and the reason is a configuration rather
   than a preference.** The obvious rule — fail rather than skip when `.build`
   exists at all — reddens `swift test -c release` on a clean checkout, where
   `.build` exists and only `release/Modules` is populated. It also does not fire
   in the `--scratch-path` case it is aimed at: a checkout that has ever been
   built normally still has a populated `.build/…/debug/Modules`, so
   `canTypecheck` returns *true* and the guards run against **stale** modules,
   which is a worse failure than the skip and a different bug. The fix that
   actually closes it is to resolve the modules directory from the **running
   test binary's** own location rather than from `#filePath`, which is correct
   under every configuration above; it was out of scope here.
