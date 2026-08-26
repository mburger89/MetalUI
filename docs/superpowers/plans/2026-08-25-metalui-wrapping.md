# MetalUI — Wrapping and `align-content`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `flex-wrap: wrap` and `wrap-reverse` working, with `align-content` distributing the resulting lines — the last large gap in single-axis flexbox.

**Architecture:** `layoutContainer` gains a line-collection phase between sizing and resolving. §9.7 then runs **per line**, and each line owns a cross size that stretch and cross alignment measure against. `flex-wrap: nowrap` must remain byte-identical: it produces exactly one line whose cross size is the container's content-box cross extent.

**Tech Stack:** Swift 6.3, Swift Testing. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` §5.

**Prior work:** the box model is merged (172 tests, 40 fixtures). Read
`docs/superpowers/2026-08-25-box-model-decisions.md` first — especially "Why the
streak broke". Rulings **BM-5**, **AL-4**, **FS-9** constrain this work. Ruling IDs
here are prefixed **`WR-`**.

## Global Constraints

- **Swift tools 6.3**, `swiftLanguageModes: [.v6]`, strict concurrency ON. Warnings are errors to fix, never suppress.
- **No third-party dependencies. No `.unsafeFlags`.**
- **`MetalUILayout` imports only `MetalUICore`.** Verify anchored — an unanchored `Metal` also matches the legitimate `import MetalUICore`:
  ```bash
  grep -rnE "^import (Metal|AppKit|UIKit|WebKit|MetalUIRender|MetalUIPlatform)$" \
    Sources/MetalUILayout/ && echo "LAYERING VIOLATION" || echo "clean"
  ```
- **Box model is `border-box` only** (§5.2). Sizes include padding and border; margins sit outside.
- **All stored rects are absolute to the root.** Pinned by `nestedContainersStoreAbsoluteNotRelativeCoordinates` — the browser corpus cannot detect this class.
- **Goldens are browser-generated, never hand-edited.** `committedGoldensMatchTheBrowser` re-drives WebKit.
- **`swift package clean`, never `rm -rf .build`.**
- **Mutation hygiene.** `git checkout <file>` restores nothing on an untracked file, and on a tracked file it discards *all* uncommitted work in that file. Commit before mutating; `cp` aside and back rather than using git. Both halves have bitten here.
- **Out of scope:** `margin: auto`, absolute positioning (`inset`), aspect ratio, Grid, baseline alignment, content-based cross sizing. Each is its own plan.

### Read before writing code

- `docs/practices/verifying-tests-can-fail.md` — **especially shape 9**, added by the last milestone.
- The box-model decisions doc's "Why the streak broke".

**This plan is the first written under shape 9, and it is the plan shape 9 was written for.** Wrapping composes with *every* feature already shipped: grow/shrink, `justify-content`, `align-items`/`align-self`, stretch, reverse, padding, and margins. Four milestones of one-feature-deep work produced zero implementation defects; the first task that multiplied against three shipped features produced three. This one multiplies against seven.

So the fixture lists below are **mostly pairs**, and each task ends by asking of every pair it did *not* fixture: *is this untested, or untested-and-correct-by-construction?*

---

## What changes, and the one thing that must not

A container's children currently become one flat `[FlexItem]`. After this plan they become `[[FlexItem]]` — lines — and three things move from the container to the line:

| Was measured against | Becomes measured against |
|---|---|
| the container's cross extent, for **stretch** | **the line's** cross size |
| the container's cross extent, for `align-items`/`align-self` | **the line's** cross size |
| the container's main extent, for the **freeze loop** | still the container's main extent, but **per line** |

**`flex-wrap: nowrap` must remain byte-identical.** It is the default, every one of the 40 committed fixtures uses it, and a single line's cross size is defined as the container's content-box cross extent — so all 172 tests must pass unchanged after Task 1. If any golden comparison moves, the single-line path is wrong.

## The uniformity traps specific to wrapping

| Trap | Where it collapses | Fixture rule |
|---|---|---|
| all items the same main size | cannot distinguish "break when full" from "break every N" | **differing main sizes**, so the break index is not a round number |
| container exactly fits a whole number of items | the boundary case is ambiguous — `<=` vs `<` both pass | make the last item on each line miss by a clear margin |
| two lines with equal cross sizes | cannot detect a line's cross size computed from the wrong items | **each line a different height** |
| every line full | `align-content` has no leftover space, so all seven values agree | leave clear leftover cross space |
| two lines only | `space-between` and `space-around` are hard to tell apart, and `space-evenly` collapses toward them | **three lines** wherever `align-content` is under test |
| items with explicit cross sizes | stretch never engages, so line-cross-vs-container-cross is invisible | at least one fixture with `auto` cross sizes |
| a container whose cross extent equals the sum of line cross sizes | `align-content: stretch` becomes a no-op | leave leftover |

**Before committing any fixture, change the declaration it is named for** — `wrap` → `nowrap`, an `align-content` value → its nearest sibling — regenerate, and confirm the numbers move.

---

### Task 1: Line collection, and moving stretch onto the line

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Create: `Sources/MetalUILayout/FlexLines.swift`
- Create: `Tests/MetalUILayoutTests/WrappingTests.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_wrap_uneven.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_wrap_stretch_auto_cross.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_wrap_with_margins_and_padding.html`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift`
- Modify: `Tests/MetalUILayoutTests/FlexEngineTests.swift`

**Interfaces:**
- Consumes: `FlexItem`, `Style`, `FlexWrap`, `resolveLength`.
- Produces:
  - `struct FlexLine { var items: [FlexItem]; var crossSize: Double }`
  - `func collectLines(_ items: [FlexItem], wrap: FlexWrap, containerMain: Double, gap: Double) -> [[FlexItem]]`
  - `func lineCrossSize(_ items: [FlexItem], isRow: Bool) -> Double`

**Line breaking uses hypothetical main sizes, not flexed ones** (§9.3). An item's
flexed size is not known until §9.7 runs, and §9.7 runs *per line* — so using
flexed sizes would be circular. Break first, flex second.

**An item alone on a line stays there even if it overflows.** A line is never
empty.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUILayoutTests/WrappingTests.swift`:

```swift
import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func item(_ tree: LayoutTree, main: Double, cross: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(main), height: px(cross))
    return tree.newNode(style: s, children: [])
}

private func line(_ mains: [Double]) -> [FlexItem] {
    mains.map {
        FlexItem(node: LayoutNodeID(0), baseSize: $0, hypotheticalMainSize: $0,
                 minMain: nil, maxMain: nil, targetMainSize: $0, crossSize: 10,
                 frozen: false, marginMain: (0, 0), marginCross: (0, 0))
    }
}
// NOTE: Step 4 adds `stretchEligible` to `FlexItem`. Update this helper's
// construction when it does — the memberwise initializer gains a parameter, and
// leaving it out is a compile error rather than a silent default.

/// Items break onto a new line when their outer main sizes plus gaps would
/// exceed the container.
///
/// Deliberately uneven — 60/90/40/70 in 200 — so the break indices are not a
/// round number and "break when full" cannot be confused with "break every two".
@Test func linesBreakWhenTheNextItemWouldOverflow() {
    let items = line([60, 90, 40, 70])
    let lines = collectLines(items, wrap: .wrap, containerMain: 200, gap: 0)

    // 60 + 90 = 150 fits; + 40 = 190 fits; + 70 = 260 does not.
    #expect(lines.map(\.count) == [3, 1])
    #expect(lines[0].map(\.targetMainSize) == [60, 90, 40])
    #expect(lines[1].map(\.targetMainSize) == [70])
}

/// Gaps count toward the break decision.
///
/// The same items with `gap: 20` fit only two per line: 60 + 20 + 90 = 170,
/// and adding 40 would make 230.
@Test func gapsCountTowardTheBreakDecision() {
    let items = line([60, 90, 40, 70])
    let lines = collectLines(items, wrap: .wrap, containerMain: 200, gap: 20)
    #expect(lines.map(\.count) == [2, 2])
}

/// `nowrap` puts everything on one line however much it overflows — the
/// behaviour every one of the 40 committed fixtures depends on.
@Test func nowrapNeverBreaks() {
    let items = line([60, 90, 40, 70])
    let lines = collectLines(items, wrap: .noWrap, containerMain: 200, gap: 0)
    #expect(lines.map(\.count) == [4])
}

/// An item too large for the container occupies a line alone rather than
/// producing an empty line before it.
@Test func anOversizedItemGetsItsOwnLineRatherThanAnEmptyOne() {
    let items = line([300, 50])
    let lines = collectLines(items, wrap: .wrap, containerMain: 200, gap: 0)
    #expect(lines.map(\.count) == [1, 1])
    #expect(lines[0][0].targetMainSize == 300)
}

/// A line's cross size is the largest outer cross size among its items —
/// border box plus that item's cross margins.
@Test func aLinesCrossSizeIsTheLargestOuterCrossSizeOnIt() {
    var items = line([10, 10, 10])
    items[0].crossSize = 20
    items[1].crossSize = 30
    items[1].marginCross = (5, 7)      // outer 42 — the largest, via margins
    items[2].crossSize = 35
    #expect(lineCrossSize(items, isRow: true) == 42)
}

/// Stretch fills the ITEM'S LINE, not the container.
///
/// Two lines in a 300-tall container: the first holds a 40-tall item, the second
/// a 90-tall one. An auto-cross item on the first line stretches to 40, not to
/// 300 and not to 90. Nothing before this task could tell those apart, because
/// there was only ever one line and its cross size WAS the container's.
@Test func stretchFillsTheItemsOwnLineNotTheContainer() {
    let tree = LayoutTree()
    let tall = item(tree, main: 120, cross: 40)
    var autoStyle = Style()
    autoStyle.size = Size(width: px(120), height: .auto)
    let stretched = tree.newNode(style: autoStyle, children: [])
    let second = item(tree, main: 120, cross: 90)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    rootStyle.size = Size(width: px(260), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [tall, stretched, second])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // `tall` and `stretched` share line 0 (120 + 120 = 240 <= 260).
    #expect(tree.layout(stretched).height == 40)
    #expect(tree.layout(stretched).y == 0)
    // `second` starts line 1, below line 0's 40.
    #expect(tree.layout(second).y == 40)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter WrappingTests`
Expected: FAIL — `cannot find 'collectLines' in scope`.

- [ ] **Step 3: Implement line collection**

Create `Sources/MetalUILayout/FlexLines.swift`:

```swift
import MetalUICore

/// CSS Flexbox §9.3 — collect items into flex lines.
///
/// **Breaking uses hypothetical main sizes, not flexed ones.** An item's flexed
/// size is not known until §9.7 runs, and §9.7 runs *per line* — so breaking on
/// flexed sizes would be circular. Break first, flex second.
///
/// An item that does not fit on an empty line stays on it anyway and overflows;
/// a line is never empty. Without that guard an oversized item produces an empty
/// line before it and every subsequent index shifts.
func collectLines(
    _ items: [FlexItem],
    wrap: FlexWrap,
    containerMain: Double,
    gap: Double
) -> [[FlexItem]] {
    guard wrap != .noWrap else { return items.isEmpty ? [] : [items] }

    var lines: [[FlexItem]] = []
    var current: [FlexItem] = []
    var used: Double = 0

    for item in items {
        let outer = item.marginMain.leading + item.hypotheticalMainSize + item.marginMain.trailing
        let withGap = current.isEmpty ? outer : used + gap + outer
        if !current.isEmpty && withGap > containerMain {
            lines.append(current)
            current = [item]
            used = outer
        } else {
            current.append(item)
            used = withGap
        }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
}

/// CSS Flexbox §9.4.8 — a line's cross size is the largest **outer** cross size
/// among its items: each item's border box plus its own cross margins.
///
/// A single-line (`nowrap`) container does not use this: its line's cross size is
/// the container's content-box cross extent, which is definite. That distinction
/// is why `nowrap` layouts are unchanged by this plan.
func lineCrossSize(_ items: [FlexItem], isRow: Bool) -> Double {
    items.reduce(0.0) {
        Swift.max($0, $1.marginCross.leading + $1.crossSize + $1.marginCross.trailing)
    }
}
```

- [ ] **Step 4: Restructure `layoutContainer`**

Three changes, in this order:

1. **Move the stretch computation out of `collectItems`.** It currently sizes
   against `containerCross`, which is only correct for a single line. `collectItems`
   should leave a stretch-eligible item's `crossSize` at its own resolved size
   (0 for `auto`) and record that it is stretch-eligible; the line phase resolves it.
   Add `var stretchEligible: Bool` to `FlexItem` for that, and say in its doc
   comment that it is read only by the line phase.

2. **Collect lines, then per line:** compute the line's cross size (for `nowrap`,
   the container's content-box cross extent instead), resolve stretch-eligible
   items against it, run §9.7 with the container's main extent, and position.

3. **Stack the lines** on the cross axis, cross-start to cross-end, separated by
   the **cross-axis gap** (`s.gap.vertical` for a row, `.horizontal` for a column —
   the opposite axis to the one `gap` already uses). **`align-content` is not
   applied in this task** — Task 2 adds it — so lines pack from cross-start and any
   leftover cross space is unused. That is `align-content: flex-start`, while CSS's
   default is `stretch`; pin it with a test that says so, and delete that test in
   Task 2.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: **all 172 existing tests pass unchanged.** Every committed fixture is
`nowrap`, and a single line's cross size is the container's content-box cross
extent, so nothing may move. If a golden comparison breaks, the single-line path
is wrong — never adjust a golden.

- [ ] **Step 6: Three fixtures — and they are pairs, not singles**

Per shape 9, each fixture combines wrapping with a feature already shipped:

- `flex_wrap_uneven.html` — `flex-wrap: wrap`, container 260 wide, five children of widths 60/90/40/70/50 and **three different heights**, so no two lines have the same cross size. Wrapping × line cross sizing.
- `flex_wrap_stretch_auto_cross.html` — children with **`height: auto`** on lines of differing content heights, at least one child with an explicit height per line to set that line's cross size. Wrapping × stretch. This is the fixture that distinguishes line-cross from container-cross.
- `flex_wrap_with_margins_and_padding.html` — container with asymmetric padding and border, children with asymmetric margins. Wrapping × the box model. The break decision must count margins, and the lines must stack inside the content box.

Register all three at 800×600 and compare full-rect.

- [ ] **Step 7: Commit, then prove**

```bash
swift test
git add -A && git commit -m "feat(layout): collect flex lines and size stretch against the line"
```

Mutations, each reverted with `git status --short` verified empty:

```bash
# 1. Break on `>=` instead of `>` (off-by-one at the exact-fit boundary).
#    Expect: at least one fixture. If none, no fixture has an exact-fit boundary
#    and the corpus cannot see the comparison — say so.
# 2. Drop gaps from the break decision.
#    Expect: gapsCountTowardTheBreakDecision + a fixture with a gap.
# 3. Drop margins from the break decision.
#    Expect: flex_wrap_with_margins_and_padding.
# 4. Line cross size uses the border box, not the outer box.
#    Expect: aLinesCrossSizeIsTheLargestOuterCrossSizeOnIt + the margins fixture.
# 5. Stretch against the container's cross extent instead of the line's.
#    Expect: stretchFillsTheItemsOwnLineNotTheContainer + the stretch fixture.
#    THIS IS THE TASK'S HEADLINE — if it reddens nothing, the restructuring
#    bought nothing observable.
# 6. Remove the never-empty-line guard.
#    Expect: anOversizedItemGetsItsOwnLineRatherThanAnEmptyOne.
```

Report which tests fired for each, including any that fired nothing.

- [ ] **Step 8: Answer shape 9's question in the report**

List every pair of (wrapping × already-shipped feature) you did **not** fixture —
grow/shrink, `justify-content`, `align-items`/`align-self`, reverse — and for each
say whether it is untested, or untested-and-correct-by-construction. Task 3 turns
that list into fixtures.

---

### Task 2: `align-content`

**Files:**
- Modify: `Sources/MetalUILayout/Alignment.swift`
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Modify: `Tests/MetalUILayoutTests/WrappingTests.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_wrap_align_content_between.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_wrap_align_content_center.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_wrap_align_content_stretch.html`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift`

**Interfaces:**
- Consumes: `AlignContent`, `MainAxisOffsets`, `distributeMainAxis`.
- Produces: `func distributeLines(_ align: AlignContent, freeSpace: Double, lineCount: Int) -> MainAxisOffsets` and a stretch amount.

**`align-content` has one value `justify-content` does not: `stretch`, and it is
the CSS default.** With leftover cross space and `stretch`, every line grows by an
equal share — which then changes what stretch-eligible items inside those lines
fill. Order matters: distribute to lines first, resolve item stretch second.

The other six values are exactly `distributeMainAxis`' six. **Reuse it** rather
than writing a parallel switch — a second copy of that logic is how the two drift.

- [ ] **Step 1: Write the failing test**

```swift
/// `align-content` distributes leftover cross space among LINES.
///
/// Three lines of cross sizes 40/60/30 in a 300-tall container: 170 used,
/// 130 leftover. Three lines, not two — `space-between` and `space-around` are
/// hard to distinguish with two, and `space-evenly` collapses toward them.
@Test func alignContentDistributesLeftoverCrossSpaceAmongLines() {
    #expect(distributeLines(.flexStart, freeSpace: 130, lineCount: 3).leading == 0)
    #expect(distributeLines(.flexEnd, freeSpace: 130, lineCount: 3).leading == 130)
    #expect(distributeLines(.center, freeSpace: 130, lineCount: 3).leading == 65)

    let between = distributeLines(.spaceBetween, freeSpace: 130, lineCount: 3)
    #expect(between.leading == 0)
    #expect(between.between == 65)

    let around = distributeLines(.spaceAround, freeSpace: 130, lineCount: 3)
    #expect(abs(around.leading - 130.0 / 6.0) < 1e-9)
    #expect(abs(around.between - 130.0 / 3.0) < 1e-9)

    let evenly = distributeLines(.spaceEvenly, freeSpace: 130, lineCount: 3)
    #expect(abs(evenly.leading - 32.5) < 1e-9)
    #expect(abs(evenly.between - 32.5) < 1e-9)
}

/// `stretch` — the CSS default — grows every line by an equal share instead of
/// leaving space between them.
@Test func alignContentStretchGrowsEveryLineEqually() {
    let o = distributeLines(.stretch, freeSpace: 130, lineCount: 3)
    #expect(o.leading == 0)
    #expect(o.between == 0)
    // The growth is reported separately; lines are not moved apart.
    #expect(lineStretchAmount(.stretch, freeSpace: 130, lineCount: 3) == 130.0 / 3.0)
    #expect(lineStretchAmount(.center, freeSpace: 130, lineCount: 3) == 0)
}

/// A stretched LINE changes what a stretch-eligible ITEM inside it fills.
///
/// Order matters: distribute to lines first, resolve item stretch second.
@Test func aStretchedLineChangesWhatItsStretchedItemsFill() {
    // ... engine-level test: two lines, container tall enough to leave leftover,
    // an auto-cross item on line 0. Its height must be the line's STRETCHED
    // cross size, not the line's natural one.
}
```

Write that third test out fully against the real engine; the sketch above names
what it must pin, not the code.

- [ ] **Step 2: Implement, reusing `distributeMainAxis` for the six shared values**

```swift
/// CSS Flexbox §9.6.15 — distribute leftover cross space among a container's
/// flex lines.
///
/// Six of the seven values behave exactly as `justify-content`'s do, so this
/// delegates rather than repeating the switch — a second copy is how the two
/// drift apart. `stretch` is the seventh, has no `justify-content` counterpart,
/// and is CSS's **default**: it grows every line rather than moving lines apart,
/// so it returns zero offsets here and reports its growth through
/// `lineStretchAmount` instead.
func distributeLines(_ align: AlignContent, freeSpace: Double, lineCount: Int) -> MainAxisOffsets {
    switch align {
    case .stretch:      return MainAxisOffsets(leading: 0, between: 0)
    case .flexStart:    return distributeMainAxis(.flexStart, freeSpace: freeSpace, itemCount: lineCount)
    case .flexEnd:      return distributeMainAxis(.flexEnd, freeSpace: freeSpace, itemCount: lineCount)
    case .center:       return distributeMainAxis(.center, freeSpace: freeSpace, itemCount: lineCount)
    case .spaceBetween: return distributeMainAxis(.spaceBetween, freeSpace: freeSpace, itemCount: lineCount)
    case .spaceAround:  return distributeMainAxis(.spaceAround, freeSpace: freeSpace, itemCount: lineCount)
    case .spaceEvenly:  return distributeMainAxis(.spaceEvenly, freeSpace: freeSpace, itemCount: lineCount)
    }
}

/// How much each line grows under `align-content: stretch`. Zero for every other
/// value, and zero when there is no leftover — negative free space never shrinks
/// a line.
func lineStretchAmount(_ align: AlignContent, freeSpace: Double, lineCount: Int) -> Double {
    guard align == .stretch, lineCount > 0, freeSpace > 0 else { return 0 }
    return freeSpace / Double(lineCount)
}
```

Wire it into the line phase: compute leftover cross space, apply
`lineStretchAmount` to each line's cross size **before** resolving item stretch,
then place lines using `distributeLines`' offsets. **Delete Task 1's test** that
pinned lines packing from cross-start — its premise expires here.

- [ ] **Step 3: Three fixtures**

`flex_wrap_align_content_between.html`, `_center.html` and `_stretch.html` — each
**three lines** with **differing cross sizes** and **clear leftover space**, since
all seven values agree when the lines exactly fill. The stretch fixture must have
`auto`-cross children so line growth is observable in the items.

- [ ] **Step 4: Commit, then prove**

```bash
# 1. Default `align-content` to `.flexStart` instead of `.stretch`.
#    Expect: the stretch fixture and every wrap fixture with leftover space.
# 2. `lineStretchAmount` divides by `lineCount + 1`.
#    Expect: the stretch fixture.
# 3. Resolve item stretch BEFORE growing lines.
#    Expect: aStretchedLineChangesWhatItsStretchedItemsFill + the stretch fixture.
# 4. Let `lineStretchAmount` return negative growth on overflow.
#    Expect: a test with more line cross than container cross.
# 5. Re-implement the six shared values as a parallel switch with `space-around`'s
#    edges halved wrongly.
#    Expect: the between/center fixtures — proving the delegation is load-bearing.
```

---

### Task 3: `wrap-reverse`, and the compositions Task 1 listed

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Modify: `Tests/MetalUILayoutTests/WrappingTests.swift`
- Create: fixtures for `wrap-reverse` and for each pair Task 1 reported as unfixtured
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift`
- Modify: `CLAUDE.md`
- Modify: `Sources/MetalUILayout/FlexEngine.swift` (file header)

**`wrap-reverse` flips the cross axis, not the main axis.** Lines stack from
cross-end toward cross-start, and `align-items: flex-start` then means the
*reversed* cross start — the bottom of a row. It composes with `row-reverse`,
which flips the main axis: a `row-reverse` + `wrap-reverse` container fills from
the bottom-right.

**This task's fixture list is written by Task 1's report**, not by this plan.
Task 1 ends by listing every (wrapping × shipped feature) pair it did not
fixture. Each becomes a fixture here, or a recorded decision not to. The pairs
known in advance:

| Pair | Why it matters |
|---|---|
| wrapping × grow/shrink | §9.7 now runs per line — free space is the line's, not the container's |
| wrapping × `justify-content` | each line distributes its own main free space independently |
| wrapping × reverse (main) | break order is document order; packing order is reversed |
| wrapping × `wrap-reverse` | the cross axis flips |
| `wrap-reverse` × `align-items` | `flex-start` means the reversed cross start |
| `wrap-reverse` × `align-content` | leftover distributes from the reversed end |
| wrapping × the sub-one flex factor clause | per-line free space feeds §9.7.4.b |

- [ ] **Step 1: Write the failing tests**

At minimum: lines stack from the cross-end under `wrap-reverse`; `align-items:
flex-start` puts an item at its line's *bottom* in a `wrap-reverse` row; and
`row-reverse` + `wrap-reverse` fills from the bottom-right.

- [ ] **Step 2: Implement**

Flip the line cursor the way `positionItems` flips the main cursor — convert at
the point of use rather than reversing the lines array, for the same reason: the
array's order is document order, and wrapping's own break decision depends on it.

- [ ] **Step 3: Fixtures for every pair**

Write one fixture per row of the table above, plus any pair Task 1's report added.
Each must move its numbers when its named declaration is swapped for a sibling.

- [ ] **Step 4: Update the documentation this plan invalidates**

- **`FlexEngine.swift` has no header paragraph about wrapping** — its claims are
  inline, in three places, and each says something different. Verified by grep
  before this plan was written; find them again rather than trusting these line
  numbers:
  - `~:518` — the content-based-cross-sizing note lists "because the container
    wraps" as a reason an item is not stretched. Still true after this plan, but
    check the surrounding sentence still parses once wrapping exists.
  - `~:584` — the reverse-design rationale calls wrapping's line collection
    "neither implemented yet". **Now false**, and it is the argument for keeping
    `items` in document order — which this plan's `collectLines` makes *load-bearing*
    rather than speculative. Rewrite it to say so.
  - `~:622` — "single-line only; wrapping would make this the line's own cross
    size". **Now false**, and it is exactly what Task 1 implements.
  **Leave** the content-based-cross-sizing paragraph itself — still true, needs M2.
- **`CLAUDE.md`'s inert-API table**: remove `flexWrap` and `alignContent`. **Keep** `margin: auto`, `inset`, `aspectRatio`, `baseline`. Correct the test count. **Verify every remaining row by grep, not by reading** — rows on three previous branches were false, and one was self-contradictory.
- Confirm the three known-divergence entries are still accurate.

- [ ] **Step 5: Commit and prove**

```bash
# 1. Ignore `wrap-reverse` entirely (treat it as `wrap`).
#    Expect: every wrap-reverse fixture.
# 2. Flip the MAIN axis on `wrap-reverse` instead of the cross.
#    Expect: the wrap-reverse fixtures and the row-reverse composition.
# 3. Reverse the lines array instead of flipping the cursor.
#    Expect: the `wrap-reverse` × `align-content` fixture, where leading and
#    trailing differ. If it reddens nothing, that fixture is symmetric and
#    cannot distinguish the two — fix the fixture.
```

## Exit criteria

- [ ] `swift test` passes, no warnings; `swift package clean && swift build` clean
- [ ] `MetalUILayout` imports only `MetalUICore`
- [ ] **All 172 pre-existing tests pass unchanged** — every committed fixture is `nowrap`
- [ ] No pre-existing golden was regenerated
- [ ] Every new fixture moves its numbers when its named declaration is swapped
- [ ] `flexWrap` and `alignContent` are gone from CLAUDE.md's inert table
- [ ] `FlexEngine.swift`'s file header no longer documents wrapping as unimplemented
- [ ] Each of these mutations reddens at least one test: break on `>=`; gaps dropped from the break decision; margins dropped from it; line cross from the border box; stretch against the container instead of the line; `align-content` defaulting to `flex-start`; item stretch resolved before line growth; `wrap-reverse` ignored
- [ ] **Task 1's shape-9 list is answered** — every (wrapping × shipped feature) pair is either fixtured or recorded as a deliberate omission

## Deliberately NOT in this plan

- **`margin: auto`** — CSS gives it priority over `justify-content`.
- **Absolute positioning** — `inset` remains inert.
- **Content-based cross sizing** — needs M2's text system.
- **Aspect ratio**, **baseline alignment**, **`MeasureCache`**, **Grid**.

## Risks carried in

- **BM-4's over-constrained box** is a deliberate, documented divergence.
- **The root's percentage width** falls back to the available space where WebKit uses the containing block. Pre-existing; do not fix one site without the other.
- **FS-9 and AL-4 together state one rule** — two independent engines agreeing outrank the spec's letter; one engine alone does not.
- **`LayoutNodeID` has no generation counter** (m1a ruling C-3).
- **Two guarantees lapse under plausible CI configurations** — the ABI probe skips without a Metal device, and `committedGoldensMatchTheBrowser` is the only live-WebKit consumer. Both must be required, non-gateable jobs.
