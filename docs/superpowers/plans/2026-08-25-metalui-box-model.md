# MetalUI — The Box Model

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `padding`, `border` and `margin` actually affect layout, so a container with `padding: 20; border: 5` places its child at `(25, 25)` instead of `(0, 0)` — closing the largest remaining silent-wrong in the engine.

**Architecture:** `resolveEdges` is fully unit-tested and has **no engine caller**. This plan wires it in on both sides of the seam: a container's padding and border shrink the *content box* its children live in, and an item's margin sits *outside* its border box, consuming main-axis space and offsetting cross-axis placement. Border-box sizing means every existing size stays the border box; nothing about `flex-basis` or the freeze loop changes meaning.

**Tech Stack:** Swift 6.3, Swift Testing. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` §5.2.

**Prior work:** alignment is merged (141 tests, 26 fixtures). Read
`docs/superpowers/2026-08-25-alignment-decisions.md` and
`docs/superpowers/2026-08-25-flex-sizing-decisions.md` — rulings **AL-4**, **FS-1**
and **FS-9** constrain this work. Ruling IDs in this plan are prefixed **`BM-`**.

## Global Constraints

- **Swift tools 6.3**, `swiftLanguageModes: [.v6]`, strict concurrency ON. Warnings are errors to fix, never suppress.
- **No third-party dependencies. No `.unsafeFlags`.**
- **`MetalUILayout` imports only `MetalUICore`.** Verify anchored — an unanchored `Metal` also matches the legitimate `import MetalUICore`:
  ```bash
  grep -rnE "^import (Metal|AppKit|UIKit|WebKit|MetalUIRender|MetalUIPlatform)$" \
    Sources/MetalUILayout/ && echo "LAYERING VIOLATION" || echo "clean"
  ```
- **Box model is `border-box` only** (§5.2). `size`, `minSize` and `maxSize` include padding and border. There is no `boxSizing` property and there must not be one.
- **All stored rects are absolute to the root**, never parent-relative. Pinned by `nestedContainersStoreAbsoluteNotRelativeCoordinates` — the browser corpus cannot detect this class, so that test is the only guard.
- **Goldens are browser-generated, never hand-edited.** `committedGoldensMatchTheBrowser` re-drives WebKit and will catch it.
- **`swift package clean`, never `rm -rf .build`.**
- **Mutation hygiene.** `git checkout <file>` restores nothing on an untracked file, and on a tracked file it discards *all* uncommitted work in that file. Commit before mutating; `cp` a file aside rather than using git if it carries uncommitted work. Both halves have bitten on this project.
- **Out of scope:** wrapping and `align-content`, absolute positioning (`inset`), aspect ratio, Grid, baseline, `margin: auto`. Each is its own plan.

### Read before writing code: `docs/practices/verifying-tests-can-fail.md`

Four milestones; **every defect found was in a plan, a test, a fixture or a
comment — never in an implementation**, and essentially all were found by mutation.
§"The uniformity traps specific to the box model" below is not optional reading —
this feature has more degenerate cases than any so far.

---

## What "border-box" actually means here, and what it does not change

Given `width: 300; padding: 20; border: 5`:

| | |
|---|---|
| border box | **300** — this is what `size`, `minSize`, `maxSize`, `flex-basis` and the freeze loop all mean |
| content box | 300 − 2×(20 + 5) = **250** — the space offered to children |
| child origin | inset by border + padding: **(25, 25)** absolute, not (0, 0) |
| outer (margin) box | 300 + margins — what the *parent's* main axis budget spends |

Two consequences worth stating because they are what stops this plan cascading:

1. **Nothing about §9.2 or §9.7 changes meaning.** Flex base sizes and target main
   sizes were always border-box sizes. The freeze loop is untouched.
2. **Margins are the only thing that changes the line's arithmetic.** A line's
   content size becomes Σ(target main size + main-axis margins) + gaps.

## The uniformity traps specific to the box model

This feature is unusually easy to test into a false green, because so many of its
values are equal to each other in ordinary CSS:

| Trap | Where it collapses | Fixture rule |
|---|---|---|
| `padding: 20` (all sides equal) | cannot distinguish left from top, nor detect a transposed axis | **four different edge values** |
| `padding == border` | cannot tell which of the two is being applied, or whether one is applied twice | padding and border must differ |
| symmetric padding (`left == right`) | cannot detect applying only the leading edge, or only the trailing | **asymmetric on both axes** |
| a square container | **percentage vertical padding resolves against width in CSS** — on a square, width- and height-basis agree | strongly non-square (e.g. 400×100) |
| every child has the same margin | cannot detect margins read from the wrong child | different margins per child |
| margin only on the leading child | cannot detect a trailing margin being dropped | margins on both ends |
| padding on a container with one child | cannot distinguish "inset the origin" from "shrink the content box" | ≥ 2 children, so the second reveals the reduced budget |

**Before committing any fixture, change the declaration it is named for to a
different value** — `padding: 20 8 4 16` → `padding: 0`, a percentage to a pixel —
regenerate, and confirm the numbers move. Four of the flex-sizing branch's
nineteen findings and five of alignment's were fixtures too uniform to distinguish
the thing they claimed to pin.

---

### Task 1: The content box — padding and border on the container

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Create: `Tests/MetalUILayoutTests/BoxModelTests.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_padding_border.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_column_padding_asymmetric.html`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift`
- Modify: `Tests/MetalUILayoutTests/FlexEngineTests.swift` (comparisons)

**Interfaces:**
- Consumes: `resolveEdges`, `ResolvedEdges`, `LayoutRect`, `SizeD`.
- Produces:
  - `func contentBox(_ tree: LayoutTree, _ container: LayoutNodeID, borderBox: SizeD, rootFontSize: Double) -> (origin: (Double, Double), size: SizeD)` — the inset origin **relative to the container's own origin**, and the reduced size.

**`resolveEdges` has been unit-tested with zero callers since M1a.** This task is
what makes it load-bearing. Its own doc comment says percentages resolve against
the containing block's **width even for top and bottom** — that is CSS, and Task 3
pins it. Do not "fix" it.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUILayoutTests/BoxModelTests.swift`:

```swift
import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }
private func pxL(_ v: Double) -> Length { .pixels(Pixels(Float(v))) }

private func fixedChild(_ tree: LayoutTree, w: Double, h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

/// A container's padding and border inset its children's origins AND shrink the
/// space offered to them.
///
/// Four different edge values, and padding differs from border: with
/// `padding: 20 8 4 16` and `border: 5 3 2 7` the content box starts at
/// (16 + 7, 20 + 5) = (23, 25) and is
/// 400 - (16 + 7 + 8 + 3) = 366 wide, 100 - (20 + 5 + 4 + 2) = 69 tall.
/// Uniform values would let a transposed axis or a dropped edge pass.
@Test func paddingAndBorderInsetChildrenAndShrinkTheContentBox() {
    let tree = LayoutTree()
    let a = fixedChild(tree, w: 50, h: 30)
    let b = fixedChild(tree, w: 60, h: 30)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(20), right: pxL(8), bottom: pxL(4), left: pxL(16))
    rootStyle.border = Edges(top: pxL(5), right: pxL(3), bottom: pxL(2), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // The root's own border box is untouched — border-box sizing.
    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 400, height: 100))
    // First child at the content-box origin, not (0, 0).
    #expect(tree.layout(a) == LayoutRect(x: 23, y: 25, width: 50, height: 30))
    // Second child packs after the first, still inside the content box.
    #expect(tree.layout(b) == LayoutRect(x: 73, y: 25, width: 60, height: 30))
}

/// The content box is what a stretched item fills, not the border box.
///
/// Cross-axis stretch must use the reduced extent: 100 tall with 20/4 padding
/// and 5/2 border leaves 69, not 100.
@Test func stretchFillsTheContentBoxNotTheBorderBox() {
    let tree = LayoutTree()
    var kidStyle = Style()
    kidStyle.size = Size(width: px(50), height: .auto)   // auto cross -> stretches
    let kid = tree.newNode(style: kidStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(20), right: pxL(8), bottom: pxL(4), left: pxL(16))
    rootStyle.border = Edges(top: pxL(5), right: pxL(3), bottom: pxL(2), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(kid).height == 69)
    #expect(tree.layout(kid).y == 25)
}

/// A grow item's free space comes from the content box, so padding reduces what
/// it can grow into.
@Test func growDistributesTheContentBoxNotTheBorderBox() {
    let tree = LayoutTree()
    var s = Style()
    s.flexGrow = 1
    s.flexBasis = px(0)
    s.size = Size(width: .auto, height: px(20))
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(0), right: pxL(8), bottom: pxL(0), left: pxL(16))
    rootStyle.border = Edges(top: pxL(0), right: pxL(3), bottom: pxL(0), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 400 - (16 + 7 + 8 + 3) = 366
    #expect(tree.layout(kid).width == 366)
    #expect(tree.layout(kid).x == 23)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter BoxModelTests`
Expected: all three FAIL — children sit at `(0, 0)` and take the full 400×100.

- [ ] **Step 3: Implement `contentBox` and thread it through**

Add to `FlexEngine.swift`:

```swift
/// A container's content box: where its children start, and how much room they get.
///
/// **Border-box sizing means `borderBox` is the node's stored size**, so this
/// subtracts rather than adds. The returned origin is *relative to the
/// container's own origin* — callers add it to the absolute origin, keeping the
/// "all stored rects are absolute" invariant in one place.
///
/// Percentages in `padding` and `border` resolve against the containing block's
/// **width, even for top and bottom**. That is CSS, not a simplification, and
/// `resolveEdges` already implements it — see `percentagePaddingResolvesAgainstWidthOnEveryEdge`.
private func contentBox(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    borderBox: SizeD,
    rootFontSize: Double
) -> (origin: (Double, Double), size: SizeD) {
    let s = tree.style(container)
    let padding = resolveEdges(s.padding, against: borderBox.width, rootFontSize: rootFontSize)
    let border = resolveEdges(s.border, against: borderBox.width, rootFontSize: rootFontSize)

    let leading = (padding.left + border.left, padding.top + border.top)
    // Never negative: padding larger than the box collapses the content box to
    // zero rather than inverting it.
    let size = SizeD(
        width: max(0, borderBox.width - padding.horizontal - border.horizontal),
        height: max(0, borderBox.height - padding.vertical - border.vertical))
    return (leading, size)
}
```

Then in `layoutContainer`, derive the content box once and use it for **everything
about the children** — `collectItems`' available space, the freeze loop's
`containerMain`, and `positionItems`' origin and cross extent:

```swift
    let box = contentBox(tree, container, borderBox: containerSize, rootFontSize: rootFontSize)
    let childOrigin = (containerOrigin.0 + box.origin.0, containerOrigin.1 + box.origin.1)
    // Everything below this line works in the CONTENT box. `containerSize` is the
    // border box and must not be used for children again.
```

Pass `box.size` where `containerSize` was passed to `collectItems`,
`resolveFlexibleLengths` and `positionItems`, and `childOrigin` where
`containerOrigin` was.

- [ ] **Step 4: Run the whole suite**

Run: `swift test`
Expected: all pass. Every existing fixture declares `padding: 0` and `border: 0`
in its reset, so a zero content-box inset must change nothing. **If an existing
golden comparison breaks, the threading is wrong — never adjust a golden.**

- [ ] **Step 5: Write two fixtures**

`Tests/MetalUILayoutTests/Fixtures/flex_row_padding_border.html` — note the reset
must **not** zero the root's own padding/border, so set them after it:

```html
<!doctype html>
<html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; padding: 0; border: 0; }
  body { margin: 0; }
  /* Four different edges, and padding differs from border, so a dropped edge or
     a transposed axis cannot pass. Non-square on purpose. */
  #root { display: flex; flex-direction: row; width: 400px; height: 100px;
          padding: 20px 8px 4px 16px;
          border-style: solid; border-color: black;
          border-width: 5px 3px 2px 7px; }
  .a { width: 50px; height: 30px; }
  .b { width: 60px; height: 30px; }
  .c { flex: 1 1 0; height: 30px; }
</style></head><body>
  <div id="root" data-id="root">
    <div class="a" data-id="a"></div>
    <div class="b" data-id="b"></div>
    <div class="c" data-id="c"></div>
  </div>
</body></html>
```

`flex_column_padding_asymmetric.html` — a `column` container, 120×400, with
`padding: 12px 30px 6px 18px` and `border-width: 4px 2px 8px 6px`, three children
of differing heights and `auto` width (so stretch fills the *content* width, which
is the strongest single check that the reduced box reached the cross axis).

Register both in `allFixtures` at 800×600 and compare with the full-rect
`assertMatchesGolden`.

- [ ] **Step 6: Run, commit**

```bash
swift test
git add -A
git commit -m "feat(layout): wire padding and border into the content box"
```

- [ ] **Step 7: Prove each guard can fail**

Commit first; revert each with `git status --short` verified empty:

```bash
# 1. Inset the origin but do NOT shrink the content box.
#    Expect: growDistributesTheContentBoxNotTheBorderBox, the stretch test, and
#    both fixtures (child `c` grows too far).
# 2. Shrink the content box but do NOT inset the origin.
#    Expect: paddingAndBorderInsetChildrenAndShrinkTheContentBox and both fixtures.
# 3. Apply padding but not border.
#    Expect: everything — this is why padding and border differ in every fixture.
# 4. Transpose the axes (use `padding.vertical` for width).
#    Expect: both fixtures. If only one reddens, the other is square-ish or
#    symmetric and must be fixed.
# 5. Use `borderBox` instead of the content box for the cross extent only.
#    Expect: the stretch test and the column fixture.
```

Report which tests fired for each, including any that fired nothing.

---

### Task 2: Item margins

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Modify: `Sources/MetalUILayout/Alignment.swift`
- Modify: `Tests/MetalUILayoutTests/BoxModelTests.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_margins.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_margin_with_grow.html`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift`

**Interfaces:**
- Consumes: `resolveDimension`, `FlexItem`.
- Produces:
  - `func resolveMargin(_ e: Edges<Dimension>, against parent: Double?, rootFontSize: Double) -> ResolvedEdges`
  - `FlexItem` gains `marginMain: (leading: Double, trailing: Double)` and `marginCross: (leading: Double, trailing: Double)`

**`resolveEdges` cannot be reused here, and the reason is load-bearing.** It takes
`Edges<Length>`; `Style.margin` is `Edges<Dimension>`, because a margin — unlike
padding or border — may be `auto`. That is a deliberate divergence from spec §5.2,
which declares all three as `Edges<Length>`; ruling BM-1 settles it. So margins get
their own resolver whose **only** difference is that it maps `.auto` to 0, and that
single line is exactly where `margin: auto` will be implemented later. Put the
"not implemented" note on that line, not somewhere a future author will not look.

**Margins sit *outside* the border box.** An item's `targetMainSize` stays its
border box; its *outer* main size is `margin.leading + target + margin.trailing`.
Three things read that:

1. **The line's content size** — `lineContentSize` must count margins, or free
   space is overstated and every `justify-content` value lands wrong.
2. **Positioning** — the cursor advances by the outer size, and the item's own
   rect starts after its leading margin.
3. **Cross placement** — `crossAxisOffset` operates on the outer cross size, and
   the item's rect is then offset by its leading cross margin.

**`margin: auto` is NOT implemented and must not be silently inert.** `Style.margin`
is `Edges<Dimension>`, so `.auto` is expressible — and CSS gives auto margins
priority over `justify-content`, absorbing free space before it is distributed.
Resolve `.auto` to **0** and add a CLAUDE.md inert-API row saying so. (The spec at
§5.2 declares `margin` as `Edges<Length>`, which would make `.auto` unrepresentable;
the code diverged. Ruling BM-1 below settles which is right.)

- [ ] **Step 1: Write the failing test**

Add to `BoxModelTests.swift`:

```swift
/// Margins consume main-axis space and offset the item's own rect.
///
/// Different margins per child, and margins on both ends, so neither "read the
/// wrong child's margin" nor "drop the trailing margin" can pass.
@Test func marginsConsumeMainAxisSpaceAndOffsetTheItem() {
    let tree = LayoutTree()
    var aStyle = Style()
    aStyle.size = Size(width: px(50), height: px(30))
    aStyle.margin = Edges(top: px(0), right: px(12), bottom: px(0), left: px(7))
    let a = tree.newNode(style: aStyle, children: [])

    var bStyle = Style()
    bStyle.size = Size(width: px(60), height: px(30))
    bStyle.margin = Edges(top: px(0), right: px(4), bottom: px(0), left: px(3))
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // a starts after its 7 leading margin.
    #expect(tree.layout(a) == LayoutRect(x: 7, y: 0, width: 50, height: 30))
    // b starts after a's outer box (7 + 50 + 12 = 69) plus its own 3 leading.
    #expect(tree.layout(b) == LayoutRect(x: 72, y: 0, width: 60, height: 30))
}

/// A margin reduces what a grow item can grow into — proof the line's content
/// size counts margins rather than only border boxes.
@Test func marginsReduceTheSpaceAvailableToGrow() {
    let tree = LayoutTree()
    var s = Style()
    s.flexGrow = 1
    s.flexBasis = px(0)
    s.size = Size(width: .auto, height: px(20))
    s.margin = Edges(top: px(0), right: px(30), bottom: px(0), left: px(10))
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(kid).width == 360)   // 400 - 10 - 30
    #expect(tree.layout(kid).x == 10)
}

/// Cross margins offset placement, and `align-items: flex-end` measures from the
/// content box's far edge minus the trailing margin.
@Test func crossMarginsOffsetAlignment() {
    let tree = LayoutTree()
    var s = Style()
    s.size = Size(width: px(50), height: px(30))
    s.margin = Edges(top: px(6), right: px(0), bottom: px(9), left: px(0))
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.alignItems = .flexEnd
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // Outer cross box is 6 + 30 + 9 = 45; flex-end puts its far edge at 100, so
    // the outer box starts at 55 and the border box at 55 + 6 = 61.
    #expect(tree.layout(kid).y == 61)
}

/// `margin: auto` resolves to 0 — deliberately, and only until it is implemented.
///
/// CSS gives auto margins priority over `justify-content`: they absorb free
/// space first. This engine does not, and a silently-zero auto margin looks like
/// a working layout that is merely mis-centred. Recorded in CLAUDE.md's
/// inert-API table; delete that row when this changes.
@Test func autoMarginsResolveToZeroForNow() {
    let tree = LayoutTree()
    var s = Style()
    s.size = Size(width: px(50), height: px(30))
    s.margin = Edges(top: .auto, right: .auto, bottom: .auto, left: .auto)
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // CSS would centre it at x = 175. We put it at 0 and say so.
    #expect(tree.layout(kid).x == 0)
    #expect(tree.layout(kid).y == 0)
}
```

- [ ] **Step 2: Run to verify it fails, then implement**

Add `resolveMargin` beside `resolveEdges` in `Resolve.swift`:

```swift
/// Resolve margin edges, which — unlike padding and border — may be `auto`.
///
/// **`.auto` resolves to 0, and that is not CSS.** An auto margin absorbs free
/// space *before* `justify-content` distributes any, so a CSS `margin-left: auto`
/// pushes its item to the end of the line; here it does nothing. This one line is
/// where that gets implemented. Until it does, the row in CLAUDE.md's inert-API
/// table stands.
///
/// Percentages resolve against `parent`, which callers must supply as the
/// containing block's **width** even for top and bottom — the same CSS rule
/// `resolveEdges` follows.
public func resolveMargin(_ e: Edges<Dimension>, against parent: Double?,
                          rootFontSize: Double) -> ResolvedEdges {
    func r(_ d: Dimension) -> Double {
        resolveDimension(d, against: parent, rootFontSize: rootFontSize) ?? 0
    }
    return ResolvedEdges(top: r(e.top), right: r(e.right), bottom: r(e.bottom), left: r(e.left))
}
```

Then add the two margin pairs to `FlexItem`, resolve them in `collectItems` against
the **content box's width** (CSS resolves percentage margins against the
containing block's width on every edge), and:

- change `lineContentSize`'s caller to pass outer main sizes;
- advance `positionItems`' cursor by the outer size, placing the rect after the
  leading margin;
- pass the outer cross size to `crossAxisOffset` and add the leading cross margin
  to the result.

`lineContentSize` itself takes `[Double]` and must **not** learn about margins —
it is shared with Grid.

- [ ] **Step 3: Two fixtures**

`flex_row_margins.html` — three children with different, asymmetric margins on
both axes, in a container with `justify-content: space-between` so a
mis-measured content size moves every item. `flex_row_margin_with_grow.html` — a
`flex: 1 1 0` child with margins beside a fixed child, so the grow arithmetic is
browser-checked.

Register at 800×600, regenerate, compare full-rect.

- [ ] **Step 4: Commit, then prove**

```bash
# 1. Drop margins from the line's content size (keep them in positioning).
#    Expect: marginsReduceTheSpaceAvailableToGrow + the space-between fixture.
# 2. Drop the leading margin from the item's own rect (keep it in the cursor).
#    Expect: marginsConsumeMainAxisSpaceAndOffsetTheItem.
# 3. Drop the trailing margin from the cursor advance.
#    Expect: both fixtures — this is why margins are on both ends.
# 4. Use the border box rather than the outer box in `crossAxisOffset`.
#    Expect: crossMarginsOffsetAlignment.
# 5. Resolve percentage margins against the container's HEIGHT on the cross axis.
#    Expect: nothing yet — Task 3 adds the fixture. Report the null result.
```

---

### Task 3: Percentages, nesting, and the composition that hides bugs

**Files:**
- Modify: `Tests/MetalUILayoutTests/BoxModelTests.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_percent_padding_nonsquare.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_nested_padding.html`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift`
- Modify: `CLAUDE.md`
- Modify: `Sources/MetalUILayout/FlexEngine.swift` (file header)

**Interfaces:** no new symbols. This task is coverage and documentation.

**Why this is its own task.** Tasks 1 and 2 each work in isolation and can both be
right while their *composition* is wrong. The two compositions that hide bugs:

1. **Percentage padding on a non-square container.** CSS resolves vertical
   percentage padding against the containing block's **width**. On a square
   container the two bases agree, so a wrong-axis bug is invisible. `resolveEdges`
   already documents this rule and has never had a test that could distinguish it.
2. **Nesting.** A padded container inside a padded container is where insets get
   double-counted or applied to the wrong generation. `nestedContainersStoreAbsoluteNotRelativeCoordinates`
   guards absolute coordinates but has no padding at all.

- [ ] **Step 1: Write the percentage test**

```swift
/// Percentage padding resolves against the containing block's **width** on
/// EVERY edge, including top and bottom.
///
/// The container is deliberately 400×100. `padding: 10%` is 40 on all four
/// edges — not 40 horizontally and 10 vertically. On a square container this
/// test could not fail, which is why `resolveEdges` has documented this rule
/// since M1a with nothing able to check it.
@Test func percentagePaddingResolvesAgainstWidthOnEveryEdge() {
    let tree = LayoutTree()
    let kid = fixedChild(tree, w: 20, h: 10)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(all: .percent(0.10))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 10% of 400 = 40, on the vertical edges too. Height-basis would give y = 10.
    #expect(tree.layout(kid).x == 40)
    #expect(tree.layout(kid).y == 40)
}
```

- [ ] **Step 2: Write the nesting test**

```swift
/// Insets compose down the tree without double-counting.
///
/// Outer padding 10 + border 5; inner padding 20 + border 3. The grandchild sits
/// at 10 + 5 + 20 + 3 = 38 from the root on both axes. Applying the outer inset
/// to the grandchild as well would give 53; skipping the inner would give 15.
@Test func nestedContainersComposeTheirInsetsExactlyOnce() {
    let tree = LayoutTree()
    let grandchild = fixedChild(tree, w: 20, h: 10)

    var midStyle = Style()
    midStyle.flexDirection = .row
    midStyle.size = Size(width: px(200), height: px(80))
    midStyle.padding = Edges(all: pxL(20))
    midStyle.border = Edges(all: pxL(3))
    let mid = tree.newNode(style: midStyle, children: [grandchild])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(200))
    rootStyle.padding = Edges(all: pxL(10))
    rootStyle.border = Edges(all: pxL(5))
    let root = tree.newNode(style: rootStyle, children: [mid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(mid) == LayoutRect(x: 15, y: 15, width: 200, height: 80))
    #expect(tree.layout(grandchild) == LayoutRect(x: 38, y: 38, width: 20, height: 10))
}
```

- [ ] **Step 3: Two fixtures, generated and compared full-rect**

`flex_percent_padding_nonsquare.html` — 400×100 with `padding: 10%`, two children.
`flex_nested_padding.html` — the nesting shape above, so the browser confirms the
composition rather than only our arithmetic.

- [ ] **Step 4: Update the documentation this plan invalidates**

- **`FlexEngine.swift`'s file header**: delete the box-model paragraph. It is the
  longest "NOT implemented" note in the file and it is now false. Leave the
  content-based-cross-sizing paragraph — that is still true and needs M2.
- **`CLAUDE.md`'s inert-API table**: remove the `padding`/`border`/`margin`
  (`resolveEdges`) row; **add** a `margin: auto` row. `inset` stays — absolute
  positioning is a separate plan. Correct the test count. **Verify every remaining
  row by grep, not by reading** — rows on the previous two branches were false.
- **`Resolve.swift`'s `resolveEdges` doc comment**: it says callers "must supply"
  the containing block's width. Name the caller now that one exists.

- [ ] **Step 5: Commit and prove**

```bash
# 1. Resolve percentage padding against the container's HEIGHT for top/bottom.
#    Expect: percentagePaddingResolvesAgainstWidthOnEveryEdge + its fixture.
#    This is the mutation `resolveEdges` has never had a test for.
# 2. Apply the root's inset to grandchildren as well (pass containerOrigin
#    instead of childOrigin into the recursion).
#    Expect: nestedContainersComposeTheirInsetsExactlyOnce + the nesting fixture.
# 3. Skip the inner container's inset (recurse with the parent's content box).
#    Expect: the same two.
```

## Ruling BM-1 — `margin` stays `Edges<Dimension>`, diverging from the spec

Spec §5.2 declares `margin, padding, border: Edges<Length>`. The code has
`margin: Edges<Dimension>`, which is the only one of the three that can be `.auto`.

**Keep the code's shape and amend the spec's intent, not the code.** `margin: auto`
is a real and widely used CSS mechanism — it is how "push this to the right" is
written — and a `Length`-typed margin makes it unrepresentable, so implementing it
later would become a breaking model change rather than a new branch in one
function. The cost of keeping `Dimension` is that `.auto` is expressible and inert
today, which is a documented row rather than a silent gap.

If a future plan implements auto margins, it starts at `resolveMargin`'s `?? 0`.

## Exit criteria

- [ ] `swift test` passes, no warnings; `swift package clean && swift build` clean
- [ ] `MetalUILayout` imports only `MetalUICore`
- [ ] `resolveEdges` has production callers — it has been unit-tested with none since M1a
- [ ] A percentage-padding test exists that a **square** container could not pass
- [ ] Every new fixture moves its numbers when its named declaration is changed
- [ ] `FlexEngine.swift`'s file header no longer documents the box model as unimplemented
- [ ] `padding`/`border`/`margin` are gone from CLAUDE.md's inert table; `margin: auto` and `inset` are listed
- [ ] Each of these mutations reddens at least one test: inset without shrinking; shrink without insetting; padding applied but not border; transposed axes; margins dropped from the line's content size; percentage padding against height

## Deliberately NOT in this plan

- **`margin: auto`** — CSS gives it priority over `justify-content`, absorbing free space before distribution. Its own plan; listed as inert here.
- **Wrapping** — `flex-wrap`, line collection, `align-content`. The largest remaining flex gap.
- **Absolute positioning** — `inset` remains inert.
- **Aspect ratio**, **`MeasureCache`**, **Grid**, **baseline**.

## Risks carried in

- **Content-based cross sizing is still 0** and no fixture can reach it until M2 measures content.
- **`min-width: auto` has exactly one killing test** (ruling FS-3's other half is also unimplemented).
- **AL-4 and FS-9 state one rule** — two independent engines agreeing outrank the spec's letter; one engine alone does not. Do not change either without reading both.
- **`LayoutNodeID` has no generation counter** (m1a ruling C-3).
- **Two guarantees lapse under plausible CI configurations** — the ABI probe skips without a Metal device, and `committedGoldensMatchTheBrowser` is the only live-WebKit consumer. Both must be required, non-gateable jobs.
