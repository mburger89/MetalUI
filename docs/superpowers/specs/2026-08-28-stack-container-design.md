# Stack — a Layering Container

**Status:** approved in brainstorming 2026-08-28. Follows the clipping-and-scroll
sub-project (merged as `36e0aaf`).

`Stack` layers its children at the same position instead of sequencing them
along an axis: the container sizes to its largest child on each axis, and every
child is aligned within that box. SwiftUI calls this `ZStack`; this framework
calls it `Stack`, because the name says what it does and there is no `VStack`
/`HStack` pair here to disambiguate against — `Column` and `Row` carry those.

---

## 1. Scope

**In:**

1. `Display.stack`, a third case beside `.flex` and `.none`.
2. A stack layout path in the engine: one line, max-over-children sizing,
   per-item alignment on both axes.
3. `Style.justifyItems`, mirroring CSS's inline-axis item alignment.
4. An `Alignment` type (nine cases) and the `Stack` element.
5. Browser fixtures using CSS grid one-cell as the oracle.

**Out, deliberately:**

- **Absolute positioning.** `Stack` is not `position: absolute`. Its children
  participate in sizing; absolutely-positioned children are removed from flow
  and contribute nothing to the parent's size. That is a separate feature —
  the one modals, popovers and tooltips need, and the one that makes
  `Style.position` and `Style.inset` live. It is the natural follow-up and it
  is not this.
- **Per-child alignment override.** SwiftUI's `.alignmentGuide` is genuinely
  advanced machinery (custom alignment identifiers, guide closures). Container
  level only; adding per-child later is additive.
- **Grid.** The oracle uses `display: grid` because a one-cell grid produces the
  numbers a stack should. **The engine implements no grid** and this spec does
  not begin one. Grid is M5.
- **Z-order control.** Children paint in declaration order, first at the back.
  No `zIndex`. The draw list (clipping-and-scroll, §2) is what makes that
  ordering real across primitive types; nothing further is needed.

---

## 2. Why SwiftUI's semantics and not CSS's

Ruling EP-5 makes SwiftUI the design authority and CSS the substrate. Two places
they differ here, and the difference matters:

**Sizing.** A `ZStack` sizes to its largest child. A one-cell CSS grid does the
same for `auto` tracks, so these agree.

**Stretching.** They do **not** agree. CSS's `align-items` and `justify-items`
both default to `stretch`, so grid items fill the cell. SwiftUI's `ZStack`
children keep their natural size and centre. **This spec takes SwiftUI's
answer**, which is also the precedent EP-8 set when `Column`/`Row` were made to
centre on the cross axis where `Box` stretches.

The consequence is concrete and belongs in every fixture: **the oracle HTML must
say `justify-items: center; align-items: center` explicitly.** A fixture relying
on grid's defaults measures stretch and will disagree with the engine — and it
will look like an engine bug.

---

## 3. The engine

### 3.1 Dispatch

`Display` gains `.stack`. This is where CSS puts the same decision, and
`Display` is already live — `collectItems` filters `display != .none`, so the
property is read by production code today and gains a third meaning rather than
a first.

`layOutChildren` is the single seam: both `measureNode` and `placeNode` route
through it, and it already returns a `ContainerLayout` carrying `lines`,
`contentSize`, `edges` and `box`. **A stack produces exactly one line holding
every child**, so neither caller changes shape. Padding, border, the content-box
computation and the edges bookkeeping all stay shared — a stack is an ordinary
container in every respect except how its items are sized and placed.

### 3.2 Sizing

Each child is measured with the **stack's own available space offered on both
axes** — the same `AvailableSpaceSize` the stack itself received, less its
padding and border — and with no main-axis distribution and no flexing. There is
no main axis, so §9.7's freeze loop does not run and no item has a flex base
size. The stack's content size is the **maximum over children on each axis**
independently; a stack with no children is 0×0, consistent with a childless
`Box`.

**`flexGrow`, `flexShrink` and `flexBasis` are ignored** on a stack's children.
CSS agrees — they are flex-container properties. State this at the code, because
a reader who sets `flexGrow(1)` on a stack child and sees nothing happen needs to
find the reason without bisecting.

### 3.3 Positioning

A new `positionStackItems`, **not** a branch inside `positionItems`. The existing
function is dense with flex-specific work — `justifyContent` distribution,
gap arithmetic, the `wrap-reverse` cross-axis flip, and §9.4.2's flex-relative
start/end mapping — none of which a stack has. Sharing it would mean threading a
"there is no main axis" flag through all of it.

Each child is placed independently on both axes from `alignItems` (block axis)
and `justifyItems` (inline axis), within the container's content box.

### 3.4 The percentage question, measured

**Percentage-sized children look circular**: a child at `width: 50%` resolves
against the stack, whose size is the maximum over its children.

**Measured against the real engine in Task 1**, on a flex row (the same shape a
stack container has: one node, several children, no `flexDirection` a stack
would read) holding a `width: 50%` child (`height: 20px`, no content) beside a
fixed `80x30` child:

```
// Intrinsic pass: measureNode(..., known: .unspecified,
//   available: .maxContent x .maxContent, containingBlockWidth: nil)
PROBE measured (indefinite): SizeD(width: 80.0, height: 30.0)

// Placement pass: computeLayout(..., available: .definite(200) x .definite(100))
PROBE container:   LayoutRect(x: 0, y: 0,   width: 200, height: 100)
PROBE pct child:   LayoutRect(x: 0, y: 0,   width: 100, height: 20)
PROBE fixed child: LayoutRect(x: 100, y: 0, width: 80,  height: 30)
```

This confirms the expectation exactly. During the intrinsic pass
`containingBlockWidth: nil` means the percentage does not resolve, and the
child — having no content of its own — contributes an `auto` width of **0**:
the container's indefinite-pass width is `80`, which is the fixed child alone
(`0 + 80` on the row's main axis), and its height is `30`, the max of the two
children's cross-axis sizes (`max(20, 30)`). During the placement pass, once
the container has a definite width of `200`, the percentage resolves against
it in the ordinary way: the child is `100` wide (50% of 200).

So a percentage child contributes **zero**, not its resolved width and not a
distinct "auto" value — those coincide here because the child is empty, but
the mechanism is: unresolved percentage → `Dimension.auto` → a childless box's
content size, which is 0 (this is the same fact CLAUDE.md records as "a
childless `Box` measures 0" under ruling EP-8). A stack sized from its
children's intrinsic pass therefore does not see a `width: 50%` child's
resolved width at all in that pass — only in the placement pass, against the
size the intrinsic pass already settled. No rule needed to change; `placeNode`
runs after the container's own size is fixed, exactly as the flex path already
does, and the stack's `positionStackItems` (§3.3) can rely on the same
two-pass split without new machinery.

---

## 4. The API

```swift
public enum Alignment: Sendable, Equatable {
    case topLeading,    top,    topTrailing
    case leading,       center, trailing
    case bottomLeading, bottom, bottomTrailing
}

public struct Stack<Content: ElementGroup>: Element, StyledElement {
    public init(alignment: Alignment = .center, @ElementBuilder content: () -> Content)
}
```

`Stack.init` writes `display = .stack` and translates its single `Alignment` into
`alignItems` plus `justifyItems`. **The element does the translating, `Style`
does not gain an `Alignment` field** — the same division `Column.init` uses when
it writes `flexDirection` and `alignItems` rather than `Style` growing a
"columnness" property (ruling EP-8).

```swift
public enum JustifyItems: Sendable, Equatable { case start, center, end, stretch }
public var justifyItems: JustifyItems? = nil   // on Style
```

**Optional, defaulting to `nil`**, matching `alignItems`'s existing shape — the
engine reads `nil` as CSS's `stretch`, and `Stack.init` writes an explicit value
the way `Column.init` writes an explicit `alignItems`. Four cases, not CSS's
full set: `start`/`end` rather than `flex-start`/`flex-end` because a stack has
no flex-relative axis to be start-of, and no `baseline` because
`AlignItems.baseline` is itself still unimplemented and falls back to
`flexStart` (see CLAUDE.md's inert table). Adding a case later is additive.

`Style.justifyItems` is read **only** by the stack path. That is not a
declared-but-inert entry: it has a production reader. It is also faithful to the
substrate, because `justify-items` has no effect on flex containers in CSS
either — the inertness is the model's, not a gap in this implementation. Say so
at the declaration so the next reader does not add it to the table.

### 4.1 The file rename

`Sources/MetalUI/Stack.swift` held `Column` and `Row` when this spec was
written — the file was
named for the SwiftUI concept those two belong to, not for a type. Adding a type
called `Stack` to it would make the name mean two things at once.

**Rename it to `Flex.swift` in the same change**, and give `Stack` its own
`Stack.swift`. **Done** — `Sources/MetalUI/Flex.swift` holds `Column`/`Row` and
`Sources/MetalUI/Stack.swift` holds `Stack`, so read this section in the past
tense. A file whose name misdescribes its contents is the cheapest
possible defect to avoid and the most annoying to meet.

---

## 5. The oracle, and what it costs

CSS's exact idiom for this layout:

```css
#root { display: grid; justify-items: center; align-items: center; }
#root > div { grid-area: 1 / 1; }
```

An `auto` grid track sizes to the maximum of its items, and every item in cell
1/1 overlaps. WebKit implements this, so goldens can be generated the same way
the other 67 fixtures were.

**There is no CSS parser in the harness, and that is what makes this cheap.** A
fixture test hand-builds the Swift tree and compares it against a golden JSON
that WebKit produced from the HTML. Nothing has to be taught what `grid-area`
means — the Swift side simply says `display: .stack`.

**The cost is that nothing checks the two descriptions agree.** That is already
true of every existing fixture, but flex-HTML against flex-Style is a small
conceptual gap and grid-HTML against stack-Style is a larger one: a reader must
know those two are *intended* to be equivalent. Every stack fixture carries a
comment saying so, naming grid one-cell as the chosen oracle and why.

---

## 6. Testing, and the trap this project keeps falling into

**A stack fixture whose children are the same size cannot distinguish alignment
from stretch, max-sizing from first-child-sizing, or `.center` from
`.topLeading`.** Every one of those produces identical numbers when the children
are identical.

This is the corpus-uniformity hazard, and this project has now been bitten by it
three times:

- Divergence 6 survived four milestones because every box in the 61 fixtures
  preceding it was an empty div whose min-content and max-content widths are the
  same number.
- Two GPU clip mutants passed all 482 tests in the previous milestone because
  every clip fixture had origin `(0,0)` and cut in x only.
- A ruling in that same milestone deleted a load-bearing `flexShrink: 0` on the
  strength of a probe using fixed-height boxes, where min-content and max-content
  coincide.

So, as a requirement rather than a preference:

- **Children of deliberately different sizes** in every stack fixture.
- **All nine alignments must produce nine distinct positions** in at least one
  fixture. Where two would coincide, change the geometry until they do not.
- **A stretch differential**: a fixture where SwiftUI's centre and CSS's stretch
  give different numbers, so taking the wrong default is visible rather than
  silent.
- **The single-child case is not sufficient evidence.** With one child, max-over-
  children equals that child, so a stack that only ever reads its first child
  passes. At least one fixture has three children of three different sizes.
- **A nesting case**: a stack inside a flex container and a flex container inside
  a stack, because `layOutChildren` is shared and the interaction is where a
  dispatch bug would hide.

**No new class of thing escapes testing here**, which is worth stating plainly.
Stack is layout arithmetic with a browser oracle — unlike text, which has no
oracle because WebKit shapes with its own font stack, and unlike the GPU paths,
where the CPU and GPU can agree on a wrong answer. The one visual property is
z-order, and the clipping-and-scroll milestone's draw list made that assertable.

---

## 7. Exit criteria

1. `swift package clean`, warning-free build, full `swift test` **summary line**
   read — never the exit status.
2. **No existing golden moved.** 67 fixtures are downstream of `layOutChildren`,
   and a stack must not perturb the flex path. A moved golden means stop and
   report, not regenerate.
3. New stack fixtures generated against live WebKit, matching on first
   generation or with any disagreement investigated rather than regenerated.
4. All nine alignments pinned, each at a distinct position.
5. `Style.justifyItems` does **not** appear in CLAUDE.md's declared-but-inert
   table, and its declaration says why.
6. `Sources/MetalUI/Stack.swift` holds `Stack`; `Column` and `Row` live in
   `Flex.swift`.
7. §3.4's percentage question answered by measurement, with the numbers recorded
   here.
8. A `Stack` in `MetalUIDemo` — a badge over a tile, or a scrim over content —
   and **a human runs it and reports**. Layering is the one thing a static
   assertion reads as correct while looking wrong: a z-order inversion is
   invisible to every test that checks positions.

   **CLOSED, 2026-08-28.** A human ran `swift run MetalUIDemo`, was asked to
   look at the `Stack` hero's z-order — the badge on the panel, the panel on
   the backdrop — and reported it looks good. That is the first observation of
   this property through the real window rather than through
   `Renderer.renderOffscreen`: composited against the rest of the app, at a
   real display's scale factor, in the layer's own P3 colorspace. The build
   looked at predates the absolute-positioning milestone's modal
   (commit `ef7f899`) and closes nothing for it.

---

## 8. Decomposition

Roughly, for the plan to refine:

1. Probe §3.4's percentage question; record the numbers. Add `Display.stack` and
   `Style.justifyItems` with no reader yet.
2. The stack path in `layOutChildren` — one line, max-over-children sizing.
3. `positionStackItems`, all nine alignments.
4. Browser fixtures and goldens, per §6's requirements.
5. `Alignment`, the `Stack` element, the `Flex.swift` rename.
6. Nesting fixtures — stack in flex, flex in stack.
7. Demo, CLAUDE.md, decisions doc (`ST-` prefixed, lettered), human verification.

Task 1 is deliberately a probe plus two inert declarations: the percentage answer
changes what tasks 2 and 3 build, and this project has learned the hard way that
a claim about engine behaviour written without calling the engine is the most
expensive kind of wrong.
