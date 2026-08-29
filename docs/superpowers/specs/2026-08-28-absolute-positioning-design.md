# Absolute Positioning and Overlays — Design

**Status:** approved in brainstorming 2026-08-28. Follows the Stack container
(merged as `76a4a02`).

Two mechanisms that together make modals, popovers and tooltips expressible.
They are separable and this document keeps them separate, because they answer
different questions:

- **Absolute positioning** decides *where* a box sits — removed from flow,
  placed by inset against a containing block.
- **Layer hoisting** decides *what it paints above* — escaping sibling paint
  order.

A tooltip needs mostly the second. A modal needs both. They ship together here
because a modal is the motivating case, but the plan sequences the engine half
to completion before the paint half begins.

---

## 1. Scope

**In:**

1. `Position.static`, becoming the default; `.absolute` made live.
2. Absolute children removed from flow in **both** collection sites.
3. Containing-block resolution: the nearest ancestor whose `position` is not
   `.static`, falling back to the root.
4. `Style.inset` made live, with CSS's per-edge percentage bases.
5. A `layer` in `Scene`'s sort key — **CPU-side only, no ABI change**.
6. A `Deferred` element that hoists its subtree to the root layer and escapes
   clipping.

**Out, deliberately:**

- **Static position** (§3.5). CSS places an all-`auto`-inset absolute box where
  it *would* have been in flow, which requires laying it out in flow and then
  removing it. The motivating features always set insets. Recorded as a
  divergence with WebKit's numbers rather than implemented.
- **`position: fixed` / `sticky`.** `Deferred` covers the "escape to the window"
  case without a second positioning scheme.
- **`z-index`.** `Deferred` is a single hoist to the root layer, not an
  arbitrary stacking-context system. Adding ordered layers later is additive.
- **Auto margins on absolute boxes** (CSS centres an over-constrained absolute
  box with `margin: auto`). `Style.margin`'s `.auto` case already resolves to 0
  and is already in CLAUDE.md's declared-but-inert table; this does not change
  that.

---

## 2. Why both halves, and why they stay orthogonal

The rule this design turns on, stated once:

> **Layer decides paint order. The containing block decides position.
> `Deferred` escapes both.**

CSS couples these — `overflow: hidden` clips an absolutely-positioned
descendant unless its containing block sits outside the clipper, so escaping a
clip is a consequence of *where you are positioned*. Reproducing that faithfully
means paint emitting a subtree at its containing block's clip level rather than
its tree level: a second kind of hoisting, entangled with the first.

This design decouples them instead. `Deferred` is a **portal** — one rule, not a
walk up the ancestor chain — and §7 records the resulting divergence.

---

## 3. The engine: absolute positioning

### 3.1 `Position.static` becomes the default

```swift
public enum Position: Sendable, Equatable { case `static`, relative, absolute }
public var position: Position = .static      // was .relative
```

**This is a semantic change to a live property**, even though nothing is
`.absolute` today. `.static` and `.relative` differ only in whether a box is a
containing block for absolute descendants, so with no absolute boxes in
existence the change is inert — but that is an argument for verifying it moves
zero goldens, not for assuming it.

`.relative` remains meaningful: it is how a caller opts *in* to being a
containing block without positioning itself.

### 3.2 Removed from flow, in two places

`collectItems` (`FlexEngine.swift:1402`) and `layOutStack`'s loop (`:970`) each
enumerate a container's children and filter `display != .none`. Both gain a
second filter: an absolute child is not an in-flow item.

**Absolute children contribute nothing to their container's measured size.**
That is the defining property and the whole difference from `Stack`, whose
children *do* participate in sizing.

They are laid out in a separate pass, after the container's own size is known —
because an inset resolves against the containing block, which must be sized
first.

### 3.3 Containing-block resolution

The nearest ancestor whose `position` is not `.static`, falling back to the
root. This is CSS's rule, which is why `.static` had to exist: without it every
ancestor qualifies and an absolute box can never reach past its parent.

The containing block is the ancestor's **padding box** (CSS), not its border box
or content box. Getting this wrong shifts every absolute child by the ancestor's
border width — a small, uniform error that reads as a rounding problem.

### 3.4 Insets, and a written constraint that will mislead here

`Style.inset` is `Edges<Dimension>`, default `.auto` on all four.

**CSS resolves inset percentages per axis, and this is where this project's own
documentation is a trap.** CLAUDE.md states:

> A percentage inset resolves against the CONTAINING BLOCK's width — not the
> box's own width, and not a height.

That is correct for what it was written about — `padding` and `border`, where
CSS resolves *all* percentages against width. **It is wrong for `Style.inset`:**

| edge | percentage resolves against |
|---|---|
| `left`, `right` | containing block **width** |
| `top`, `bottom` | containing block **height** |

Following that sentence literally would be wrong on two of four edges, and the
sentence uses the word "inset". **The implementation must not cite it**, and
whoever touches CLAUDE.md's constraint should narrow its wording to name
padding and border.

### 3.5 Sizing an absolute box

Per axis, three cases:

- **Both insets given, size `auto`:** the box fills between them —
  `containingBlock.width - left - right`.
- **One inset and a size:** positioned from that edge at that size.
- **Both insets and a size (over-constrained):** CSS ignores `right` (in LTR
  writing mode). Follow it.

**All-`auto` insets is where this design diverges.** CSS uses the box's *static
position* — where it would have sat in flow. This design places it at the
containing block's **padding-box origin** instead, and §7 records the
divergence with measured numbers. Implementing static position means laying the
box out in flow, recording its position, then removing it — a second pass for a
case modals, popovers and tooltips do not use.

---

## 4. The paint half: layers and `Deferred`

### 4.1 Layer is sort metadata, not GPU data

The GPU never reads a primitive's layer; it only changes CPU-side ordering. So
`Scene` carries a parallel layer array exactly as it already carries
`sequence` (`Scene.swift:36`), and `finalize()`'s sort key becomes
`(layer, order, sequence)` instead of `(order, sequence)`.

**Consequences worth stating, because they make this half far cheaper than it
looks:** no `MetalUIShaderTypes.h` edit, no `abi_probe` extension, no
`sizeof` change, and **no `swift package clean` hazard** — the trap that has
bitten this project on two consecutive milestones. The clipping milestone paid
that cost twice; this half pays it zero times.

### 4.2 `Deferred`

A closure form on **both** passes, mirroring `clipped(to:offsetBy:)`:

```swift
public func deferred(_ body: () -> Void)
```

On `PrepaintPass` as well as `PaintPass`, because spec §4.5 puts hoisting in
prepaint and the reason is **hit-testing**: the scroll-region registry (and the
general hitbox list that succeeds it) is built in prepaint, and a tooltip that
paints above its siblings while receiving events below them is worse than one
that does neither.

`Deferred` does two things:

1. Sets the active layer to the root layer for its subtree.
2. **Resets the clip stack to the whole surface.**

That second one makes it a portal. A modal inside a `ScrollView` covers the
window rather than being clipped to the scroll viewport.

`Frame` gains a layer stack shaped exactly like its clip stack
(`Frame.swift:121`), and `fill`/`draw` stamp the active layer the way they
already stamp the active clip.

---

## 5. Testing

The oracle is WebKit, as ever — `position: absolute` is directly expressible, so
this half needs no translation the way `Stack` needed grid-one-cell.

**Fixture requirements, as requirements:**

- **A containing block that is not the parent.** The whole point of `.static` is
  that an absolute box skips past static ancestors. A fixture where the parent
  *is* the containing block cannot distinguish "walked the chain" from "used the
  parent".
- **Per-edge percentage bases.** At least one fixture with percentage insets on
  a containing block whose **width and height differ**, so `top: 10%` and
  `left: 10%` produce different numbers. On a square containing block the two
  bases are indistinguishable — the same uniformity hazard that hid divergence 6
  for four milestones and produced two wrong rulings on the clipping branch.
- **Removed from flow.** A container whose measured size is unchanged by adding
  an absolute child. A fixture where the absolute child is smaller than the
  in-flow content cannot tell "removed from flow" from "included and not the
  maximum".
- **Over-constrained.** Both insets plus a size, asserting `right` is the one
  ignored.

**Layer hoisting has no browser oracle** — CSS's stacking rules are not what
`Deferred` implements, deliberately (§2). Its tests are scene-level: assert
`drawList` order and that a deferred primitive's layer exceeds its siblings'.
The one visual property is the same as `Stack`'s — z-order — and it is checkable
the same way, by a rect over a glyph.

**A property no test here can see, named now:** whether a `Deferred` subtree
escaping a clip is what a *user* wants in a given case. The mechanism is
testable; the design choice is a look.

---

## 6. Exit criteria

1. `swift package clean`, warning-free build, full `swift test` **summary line**
   read — never the exit status.
2. **No existing golden moved.** 76 today. `Position`'s default changing from
   `.relative` to `.static` must move none — verify, do not assume.
3. New fixtures generated against live WebKit, matching on first generation, or
   any disagreement investigated rather than regenerated.
4. `Style.position` and `Style.inset` **leave** CLAUDE.md's declared-but-inert
   table. That table then has two rows fewer than it has had since M0.
5. CLAUDE.md's percentage-inset constraint is narrowed to name `padding` and
   `border`, since `Style.inset` now resolves two of its four edges against
   height.
6. The static-position divergence is recorded with WebKit's measured numbers and
   a pin, on the same footing as BM-4, FS-3 and TX-H.
7. A modal in `MetalUIDemo` — positioned against the window, painted over
   everything, escaping a `ScrollView`'s clip — and **a human runs it and
   reports**. Layering and clip-escape are both properties that produce
   identical rects under inversion.

---

## 7. Divergences this design creates, recorded up front

1. **All-`auto` insets place at the containing block's origin, not the static
   position** (§3.5). **Measured against WebKit in Task 5**, with a throwaway
   probe (a 40x20 in-flow `.before` sibling, then an absolute box with no
   insets at all — `width: 20px; height: 10px` — inside a 200x100
   `position: relative` root): **WebKit places the absolute box at (0, 20)**,
   below `.before` — its static position. **This engine places it at (0,
   0)**, ignoring `.before` entirely and using the containing block's
   padding-box origin instead. Pinned by
   `allAutoInsetsPlaceAtTheContainingBlockOriginNotTheStaticPosition` in
   `AbsolutePositioningTests.swift`, on the same footing as this project's
   other named divergences (BM-4, FS-3, TX-H in `CLAUDE.md`): no fixture or
   golden encodes it, since a golden would record this engine's answer as
   correct and a future fix should move nothing in the corpus.
2. **A `Deferred` subtree is not clipped by an ancestor CSS would clip it with**
   (§2, §4.2). Deliberate: `Deferred` is a portal, and the alternative entangles
   layer with containing-block resolution.

Both get pins, and both must move no golden — a fixture encoding either would
record this engine's answer as correct and a future fix should move nothing.

---

## 8. Decomposition

Roughly, for the plan to refine. **The engine half completes before the paint
half begins** — they share no code, and interleaving them would put an
unreviewed `Scene` change under an unreviewed engine change.

1. `Position.static` as the default, inert; verify zero goldens move.
2. Absolute children filtered from both collection sites; assert a container's
   measured size is unchanged.
3. Containing-block resolution up the ancestor chain.
4. Insets and sizing, with the per-axis percentage bases.
5. Browser fixtures for §5's four requirements.
6. `Scene`'s layer sort key.
7. `Deferred` on both passes: layer hoist plus clip reset.
8. Demo, CLAUDE.md (including the constraint narrowing and two table rows
   removed), decisions doc (`AP-` prefixed, lettered), human verification.
