# MetalUI — Alignment, Stretch and Reverse Directions

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `justify-content`, `align-items`/`align-self` and reverse flex directions working, and — the headline — **every golden comparison widened from main-axis-only to the full rect**, because implementing `stretch` is what finally makes our cross axis agree with the browser.

**Architecture:** Main-axis distribution and cross-axis placement become pure functions in a new `Alignment.swift`, shared with Grid later (spec §3.1 lists `Alignment.swift` as a shared file). `positionItems` gains a line content size — which is also the trailing-gap fix M1a's review specified. Stretch changes cross *sizing*, so it lands in `collectItems`, not in positioning.

**Tech Stack:** Swift 6.3, Swift Testing. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` §5.

**Prior work:** flex sizing is merged (115 tests, 16 fixtures). Read
`docs/superpowers/2026-08-25-flex-sizing-decisions.md` — rulings **FS-1**, **FS-9**
and its "What the corpus kept failing to see" table all constrain this work.
Ruling IDs in this plan are prefixed **`AL-`**.

## Global Constraints

- **Swift tools 6.3**, `swiftLanguageModes: [.v6]`, strict concurrency ON. Warnings are errors to fix, never suppress.
- **No third-party dependencies. No `.unsafeFlags`.**
- **`MetalUILayout` imports only `MetalUICore`.** Verify anchored — an unanchored `Metal` also matches the legitimate `import MetalUICore`:
  ```bash
  grep -rnE "^import (Metal|AppKit|UIKit|WebKit|MetalUIRender|MetalUIPlatform)$" \
    Sources/MetalUILayout/ && echo "LAYERING VIOLATION" || echo "clean"
  ```
- **Box model is `border-box` only.** Every fixture declares `box-sizing: border-box` and `body { margin: 0 }`.
- **All stored rects are absolute to the root**, never parent-relative. Pinned by `nestedContainersStoreAbsoluteNotRelativeCoordinates` — the browser corpus cannot detect this class, so that test is the only guard.
- **Goldens are browser-generated, never hand-edited.** `committedGoldensMatchTheBrowser` re-drives WebKit and will catch it.
- **`swift package clean`, never `rm -rf .build`.**
- **`git checkout <file>` silently restores nothing on an untracked file.** Commit before mutating; verify a revert with `git status --short`, not by assuming.
- **Out of scope:** wrapping (`flex-wrap`, and therefore `align-content`), the box model, absolute positioning, aspect ratio, Grid, baseline alignment. Each is its own plan.

### Read before writing code: `docs/practices/verifying-tests-can-fail.md`

Three milestones, and **every defect found was in a plan, a test, a fixture or a
comment — never in an implementation.** Four on the last branch alone were the same
shape: a fixture too uniform to distinguish what it claimed to pin. Alignment is
unusually prone to this, so §"The uniformity traps specific to alignment" below is
not optional reading.

---

## Why this plan's payoff is the cross axis

`align-items`' CSS initial value is `normal`, which on a flex item behaves as
**`stretch`**. That single fact explains a scar running through the whole corpus:
every fixture whose children have no explicit cross size is laid out by WebKit at
the container's full cross extent, while our engine gives **0** — so six golden
comparisons currently check `x`/`width` only and carry a "main axis only" note.

Implementing stretch does not merely add a feature. It makes the cross axis
agree, which means **those notes come out and the comparisons widen to the full
rect.** The goldens already contain the right answers; nothing is regenerated.
That is the exit criterion worth aiming at, and it is why Task 3 is where the
value is concentrated.

## The uniformity traps specific to alignment

Alignment is the easiest place in flexbox to write a test that cannot fail. Each
of these has a degenerate case where two different values produce identical
output:

| Trap | Where it collapses | Fixture rule |
|---|---|---|
| `spaceBetween` vs `flexStart` | identical with **one** item, and identical with any count when free space is 0 | ≥ 2 items, free space > 0 |
| `spaceAround` vs `spaceEvenly` | identical with **one** item (both centre it) | ≥ 2 items, and check the *edge* offset, not just the gap |
| `spaceAround` vs `center` | identical with one item | ≥ 2 items |
| `center` vs `flexStart` | identical when free space is 0 | container strictly larger than content |
| `flexEnd` vs `flexStart` | identical when free space is 0 | container strictly larger than content |
| `align-items` any value | identical when every item's cross size equals the container's | **varied** cross sizes, none equal to the container |
| `stretch` vs anything | invisible when the item has a definite cross size | at least one item with `auto` cross size |
| `.rowReverse` vs `.row` | identical with **one** item, and identical when items are the same size *and* fill the container | ≥ 2 items of **different** main sizes |

**Before committing any fixture in this plan, change the declaration it is named
for to its most similar sibling** — `spaceAround` → `spaceEvenly`, `.row` →
`.rowReverse` — regenerate, and confirm the numbers move. A fixture that produces
identical output under that swap is worse than none.

---

### Task 1: The line content size, the trailing-gap fix, and `justify-content`

**Files:**
- Create: `Sources/MetalUILayout/Alignment.swift`
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Create: `Tests/MetalUILayoutTests/AlignmentTests.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_justify_between.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_justify_around.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_justify_evenly.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_column_justify_center.html`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift` (register all four)

**Interfaces:**
- Consumes: `FlexItem`, `Style`, `JustifyContent`, `resolveLength`.
- Produces:
  - `struct MainAxisOffsets { let leading: Double; let between: Double }`
  - `func distributeMainAxis(_ justify: JustifyContent, freeSpace: Double, itemCount: Int) -> MainAxisOffsets`
  - `func lineContentSize(_ items: [FlexItem], gap: Double) -> Double`

**This task closes a bug that has had no killing test since M1a.** `positionItems`
adds `gap` only between items, which is correct — but nothing has ever read the
line's total content size, so an implementation that added a trailing gap would
have passed. M1a's review specified the exact first test; write it before anything
else.

- [ ] **Step 1: Write the failing test that M1a's review specified**

Create `Tests/MetalUILayoutTests/AlignmentTests.swift`:

```swift
import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func fixedChild(_ tree: LayoutTree, w: Double, h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

/// A line's content size counts gaps **between** items only.
///
/// Three 50px items with `gap: 12` occupy 174, not 186. Nothing has read this
/// value since M1a — `cursor` died with the loop — so an implementation that
/// added a trailing gap passed the entire suite. `justify-content` reads it as
/// the divisor for free space, which is what finally makes it observable.
@Test func lineContentSizeCountsGapsBetweenItemsOnly() {
    let tree = LayoutTree()
    let items = (0..<3).map { _ in
        FlexItem(node: fixedChild(tree, w: 50, h: 10), baseSize: 50,
                 hypotheticalMainSize: 50, minMain: nil, maxMain: nil,
                 targetMainSize: 50, crossSize: 10, frozen: true)
    }
    #expect(lineContentSize(items, gap: 12) == 174)
    #expect(lineContentSize(items, gap: 0) == 150)
    // One item has no gaps at all.
    #expect(lineContentSize([items[0]], gap: 12) == 50)
    // Zero items is a degenerate case the caller guards, but must not underflow
    // to a negative content size.
    #expect(lineContentSize([], gap: 12) == 0)
}

/// `space-around` and `space-evenly` differ only at the container's edges.
///
/// With 2 items and 90 free: `around` gives each item 45 of margin, so the
/// leading edge is 22.5 and the space between two items is 45. `evenly` splits
/// into 3 equal runs of 30. A test with one item cannot tell them apart — both
/// centre it — which is why this uses two.
@Test func spaceAroundAndSpaceEvenlyDifferAtTheEdges() {
    let around = distributeMainAxis(.spaceAround, freeSpace: 90, itemCount: 2)
    #expect(around.leading == 22.5)
    #expect(around.between == 45)

    let evenly = distributeMainAxis(.spaceEvenly, freeSpace: 90, itemCount: 2)
    #expect(evenly.leading == 30)
    #expect(evenly.between == 30)

    let between = distributeMainAxis(.spaceBetween, freeSpace: 90, itemCount: 2)
    #expect(between.leading == 0)
    #expect(between.between == 90)
}

@Test func flexStartEndAndCentrePlaceTheWholeLine() {
    #expect(distributeMainAxis(.flexStart, freeSpace: 90, itemCount: 3).leading == 0)
    #expect(distributeMainAxis(.flexEnd, freeSpace: 90, itemCount: 3).leading == 90)
    #expect(distributeMainAxis(.center, freeSpace: 90, itemCount: 3).leading == 45)
    for j in [JustifyContent.flexStart, .flexEnd, .center] {
        #expect(distributeMainAxis(j, freeSpace: 90, itemCount: 3).between == 0,
                "\(j) must not add space between items")
    }
}

/// A single item collapses `space-between` onto `flex-start`, and both
/// `space-around` and `space-evenly` onto `center`. CSS says so explicitly, and
/// it is the degenerate case every one-item fixture would hide.
@Test func distributionWithOneItemCollapsesToTheCssDegenerateCases() {
    #expect(distributeMainAxis(.spaceBetween, freeSpace: 90, itemCount: 1).leading == 0)
    #expect(distributeMainAxis(.spaceAround, freeSpace: 90, itemCount: 1).leading == 45)
    #expect(distributeMainAxis(.spaceEvenly, freeSpace: 90, itemCount: 1).leading == 45)
}

/// Overflow must not push the line backwards under the space-* values.
///
/// CSS clamps the *distributed* portion at zero: an overflowing line under
/// `space-between` still starts at the container's start edge. Negative free
/// space distributed as though positive would put later items at smaller
/// coordinates than earlier ones.
@Test func negativeFreeSpaceNeverDistributesBackwards() {
    for j in [JustifyContent.spaceBetween, .spaceAround, .spaceEvenly] {
        let o = distributeMainAxis(j, freeSpace: -120, itemCount: 3)
        #expect(o.between == 0, "\(j) distributed negative space between items")
        #expect(o.leading == 0, "\(j) pushed an overflowing line off the start edge")
    }
    // flex-end and center DO honour negative free space — an overflowing
    // centred line overhangs both edges equally. That is CSS, not a bug.
    #expect(distributeMainAxis(.center, freeSpace: -120, itemCount: 3).leading == -60)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AlignmentTests`
Expected: FAIL — `cannot find 'lineContentSize' in scope`, `cannot find 'distributeMainAxis' in scope`.

- [ ] **Step 3: Implement the pure functions**

Create `Sources/MetalUILayout/Alignment.swift`:

```swift
import MetalUICore

/// Where a line starts, and how much space sits between adjacent items.
///
/// Two numbers rather than a per-item offset array: every CSS distribution is
/// uniform, so a leading offset plus a constant stride describes all six. Grid
/// reuses this for its track alignment (spec §3.1 lists `Alignment.swift` as
/// shared), which is why it takes a free-space scalar rather than a flex line.
struct MainAxisOffsets {
    /// Distance from the container's main-start edge to the first item.
    let leading: Double
    /// Extra space inserted between adjacent items, on top of `gap`.
    let between: Double
}

/// A line's main-axis content size: the items, plus the gaps **between** them.
///
/// A trailing gap is the classic off-by-one here, and it was invisible until
/// this function existed — `positionItems` consumed `gap` inside a loop whose
/// cursor died with it, so nothing could observe the total. `justify-content`
/// subtracts this from the container to get free space, which is what finally
/// makes a trailing gap redden a test.
func lineContentSize(_ items: [FlexItem], gap: Double) -> Double {
    guard !items.isEmpty else { return 0 }
    let sizes = items.reduce(0) { $0 + $1.targetMainSize }
    return sizes + gap * Double(items.count - 1)
}

/// CSS Flexbox §9.5 — distribute a line's free space along the main axis.
///
/// **The space-* values never distribute negative free space.** An overflowing
/// line under `space-between` still starts at the main-start edge and packs
/// tight; distributing a negative amount would place later items at *smaller*
/// coordinates than earlier ones. `center` and `flex-end` are different: they
/// legitimately honour negative free space, and an overflowing centred line
/// overhangs both edges equally. That asymmetry is CSS, not an oversight.
///
/// One item collapses `space-between` onto `flex-start` and both `space-around`
/// and `space-evenly` onto `center`, per spec. Those degenerate cases are why a
/// single-item fixture can never distinguish the six values.
func distributeMainAxis(
    _ justify: JustifyContent,
    freeSpace: Double,
    itemCount: Int
) -> MainAxisOffsets {
    guard itemCount > 0 else { return MainAxisOffsets(leading: 0, between: 0) }

    switch justify {
    case .flexStart:
        return MainAxisOffsets(leading: 0, between: 0)
    case .flexEnd:
        return MainAxisOffsets(leading: freeSpace, between: 0)
    case .center:
        return MainAxisOffsets(leading: freeSpace / 2, between: 0)
    case .spaceBetween:
        let space = max(0, freeSpace)
        guard itemCount > 1 else { return MainAxisOffsets(leading: 0, between: 0) }
        return MainAxisOffsets(leading: 0, between: space / Double(itemCount - 1))
    case .spaceAround:
        let space = max(0, freeSpace)
        let per = space / Double(itemCount)
        return MainAxisOffsets(leading: per / 2, between: per)
    case .spaceEvenly:
        let space = max(0, freeSpace)
        let per = space / Double(itemCount + 1)
        return MainAxisOffsets(leading: per, between: per)
    }
}
```

- [ ] **Step 4: Wire it into `positionItems`**

In `FlexEngine.swift`, replace `positionItems`' cursor set-up. Keep the recursion
and the absolute-coordinate arithmetic exactly as they are:

```swift
    let containerMain = isRow ? containerSize.width : containerSize.height
    let content = lineContentSize(items, gap: gap)
    let offsets = distributeMainAxis(s.justifyContent ?? .flexStart,
                                     freeSpace: containerMain - content,
                                     itemCount: items.count)

    var cursor: Double = offsets.leading
    for (index, item) in items.enumerated() {
        if index > 0 { cursor += gap + offsets.between }
        // ... unchanged ...
        cursor += item.targetMainSize
    }
```

Delete the old "a trailing gap is invisible today" comment — it is no longer
true, and a comment describing a hazard that has been closed reads as though the
hazard is still open.

- [ ] **Step 5: Write the four fixtures**

Each uses **three items of differing main sizes** in a container with strictly
positive free space, so no two distributions agree. `flex_row_justify_between.html`:

```html
<!doctype html>
<html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; padding: 0; border: 0; }
  body { margin: 0; }
  #root { display: flex; flex-direction: row; justify-content: space-between;
          width: 400px; height: 40px; }
  .a { width: 40px; height: 40px; }
  .b { width: 70px; height: 40px; }
  .c { width: 50px; height: 40px; }
</style></head><body>
  <div id="root" data-id="root">
    <div class="a" data-id="a"></div>
    <div class="b" data-id="b"></div>
    <div class="c" data-id="c"></div>
  </div>
</body></html>
```

Write `flex_row_justify_around.html` and `flex_row_justify_evenly.html`
identically but for `justify-content`, and `flex_column_justify_center.html` with
`flex-direction: column`, `justify-content: center`, `width: 60px; height: 400px`
and the three children sized `height: 40/70/50; width: 60`.

**Every child here has an explicit cross size on purpose** — stretch does not
exist until Task 3, so a fixture with `auto` cross would disagree with WebKit on
the cross axis and force another "main axis only" note. Task 3 deletes the last of
those; do not add one now.

Register all four in `allFixtures` at 800×600.

- [ ] **Step 6: Generate goldens and add full-rect comparisons**

```bash
METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
```

Add a comparison per fixture using `assertMatchesGolden` — the **full-rect**
helper in `FlexEngineTests.swift`, not `assertMainAxisMatchesGolden`. These
fixtures have explicit cross sizes, so all four axes must agree.

- [ ] **Step 7: Run the whole suite and commit**

Run: `swift test`

```bash
git add -A
git commit -m "feat(layout): implement justify-content and the line content size"
```

- [ ] **Step 8: Prove each guard can fail**

Commit first. Then, one at a time, reverting each with `git status --short` verified empty:

```bash
# 1. Trailing gap: `gap * Double(items.count)` instead of `count - 1`.
#    Expect: lineContentSizeCountsGapsBetweenItemsOnly, and every justify fixture.
# 2. space-around edge: `leading: per` instead of `per / 2`.
#    Expect: spaceAroundAndSpaceEvenlyDifferAtTheEdges + the around fixture.
#    If this reddens nothing, around and evenly are indistinguishable in the corpus.
# 3. space-evenly divisor: `itemCount` instead of `itemCount + 1`.
#    Expect: the evenly fixture at minimum.
# 4. Drop the `max(0,` from space-between.
#    Expect: negativeFreeSpaceNeverDistributesBackwards.
# 5. Change the default from `.flexStart` to `.center` in positionItems.
#    Expect: every pre-existing fixture that has free space.
```

Report which tests fired for each, including any that fired nothing.

---

### Task 2: `align-items` and `align-self` on the cross axis

**Files:**
- Modify: `Sources/MetalUILayout/Alignment.swift`
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Modify: `Tests/MetalUILayoutTests/AlignmentTests.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_align_center.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_align_end_with_self.html`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift`

**Interfaces:**
- Consumes: `AlignItems`, `AlignSelf`, `FlexItem`.
- Produces: `func crossAxisOffset(_ align: AlignItems, itemCross: Double, lineCross: Double) -> Double`
  and `func resolvedAlignment(_ item: Style, container: Style) -> AlignItems`

**`stretch` is deliberately NOT implemented here** — it changes cross *sizing*,
not placement, so it belongs in `collectItems` and gets Task 3 to itself. In this
task `stretch` places the item at the cross-start edge, which is what a
zero-offset already does. Say so in the code, because "stretch falls through to
flex-start" looks like a bug to anyone who does not know Task 3 is coming.

**`baseline` is out of scope and must trap or fall back visibly.** It needs font
metrics that do not exist until M2. Do not silently treat it as `flexStart`:
that is the "declared but inert" hazard CLAUDE.md is built around. Map it to
`flexStart` **and** record it in CLAUDE.md's inert-API table in this task.

- [ ] **Step 1: Write the failing tests**

Add to `AlignmentTests.swift`:

```swift
/// Cross-axis placement, with a line 100 tall and items that are not.
///
/// Every item here has a *different* cross size, and none equals the line's —
/// with uniform cross sizes all four values produce identical output and the
/// test pins nothing.
@Test func crossAxisOffsetPlacesAnItemWithinTheLine() {
    #expect(crossAxisOffset(.flexStart, itemCross: 30, lineCross: 100) == 0)
    #expect(crossAxisOffset(.flexEnd,   itemCross: 30, lineCross: 100) == 70)
    #expect(crossAxisOffset(.center,    itemCross: 30, lineCross: 100) == 35)
    // A different item size must move the answer — a constant would pass above.
    #expect(crossAxisOffset(.center,    itemCross: 60, lineCross: 100) == 20)
    #expect(crossAxisOffset(.flexEnd,   itemCross: 60, lineCross: 100) == 40)
}

/// An item taller than its line overhangs; it is never pushed to a negative
/// offset by `flex-start`, nor clamped by `flex-end`.
@Test func anItemLargerThanItsLineOverhangsRatherThanClamping() {
    #expect(crossAxisOffset(.flexStart, itemCross: 140, lineCross: 100) == 0)
    #expect(crossAxisOffset(.flexEnd,   itemCross: 140, lineCross: 100) == -40)
    #expect(crossAxisOffset(.center,    itemCross: 140, lineCross: 100) == -20)
}

/// `align-self` overrides the container's `align-items`; nil defers to it; and
/// the container's own nil default is `stretch`, not `flex-start`.
@Test func alignSelfOverridesAlignItemsAndTheDefaultIsStretch() {
    var container = Style()
    container.alignItems = .center

    var item = Style()
    #expect(resolvedAlignment(item, container: container) == .center)

    item.alignSelf = .flexEnd
    #expect(resolvedAlignment(item, container: container) == .flexEnd)

    // CSS's initial `align-items` is `normal`, which behaves as `stretch` on a
    // flex item. Defaulting to `flex-start` here would make Task 3's stretch
    // work unreachable for every unstyled container in the corpus.
    #expect(resolvedAlignment(Style(), container: Style()) == .stretch)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AlignmentTests`
Expected: FAIL — `cannot find 'crossAxisOffset' in scope`.

- [ ] **Step 3: Implement**

Append to `Alignment.swift`:

```swift
/// Resolve which alignment applies to one item.
///
/// `align-self: auto` is modelled as `nil` here, and defers to the container's
/// `align-items`. The container's own `nil` is CSS's initial `normal`, which on
/// a flex item behaves as **`stretch`** — not `flex-start`. Getting that default
/// wrong makes stretch unreachable for every unstyled container, which is most
/// of them.
func resolvedAlignment(_ item: Style, container: Style) -> AlignItems {
    if let s = item.alignSelf {
        switch s {
        case .flexStart: return .flexStart
        case .flexEnd:   return .flexEnd
        case .center:    return .center
        case .baseline:  return .baseline
        case .stretch:   return .stretch
        }
    }
    return container.alignItems ?? .stretch
}

/// CSS Flexbox §9.6 — an item's offset from its line's cross-start edge.
///
/// **`stretch` returns 0 here, and that is not this function's job to fix.**
/// Stretch changes an item's cross *size*, in `collectItems`; by the time
/// placement runs, a stretched item already fills the line and a zero offset is
/// correct. An item that is stretch-aligned but has a definite cross size is not
/// stretched at all, and CSS places it at cross-start — also zero.
///
/// **`baseline` is NOT implemented** and falls back to `flexStart`. It requires
/// font metrics that arrive with the text system in M2; until then a baseline
/// row lays out silently as a flex-start row. Recorded in CLAUDE.md's inert-API
/// table — do not remove that row without implementing this.
func crossAxisOffset(_ align: AlignItems, itemCross: Double, lineCross: Double) -> Double {
    switch align {
    case .flexStart, .stretch, .baseline: 0
    case .flexEnd:                        lineCross - itemCross
    case .center:                         (lineCross - itemCross) / 2
    }
}
```

- [ ] **Step 4: Wire into `positionItems`**

The line's cross size is the container's cross extent (single-line only; wrapping
would make this the line's own measured cross size):

```swift
    let containerCross = isRow ? containerSize.height : containerSize.width
    // `s` is the container's style, already bound at the top of positionItems.
    // ... inside the loop, per item:
    let align = resolvedAlignment(tree.style(item.node), container: s)
    let crossOffset = crossAxisOffset(align, itemCross: item.crossSize,
                                      lineCross: containerCross)
    let x = containerOrigin.0 + (isRow ? cursor : crossOffset)
    let y = containerOrigin.1 + (isRow ? crossOffset : cursor)
```

- [ ] **Step 5: Write two fixtures**

`flex_row_align_center.html` — `align-items: center`, three children of heights
20/60/40 in a 100-tall row, each with an explicit width. `flex_row_align_end_with_self.html`
— `align-items: flex-end` on the container with `align-self: center` on the middle
child, so the fixture pins both the container value and the override in one shot.
Register both at 800×600, regenerate, and compare with the **full-rect**
`assertMatchesGolden`.

- [ ] **Step 6: Run, commit, then prove it**

```bash
swift test
git add -A && git commit -m "feat(layout): implement align-items and align-self"
```

Mutations, each reverted and verified:

```bash
# 1. `crossAxisOffset` returns 0 for every case.
#    Expect: both fixtures and crossAxisOffsetPlacesAnItemWithinTheLine.
# 2. `resolvedAlignment` ignores `alignSelf` and always reads the container.
#    Expect: flex_row_align_end_with_self. If it reddens nothing, that fixture's
#    override is inert — the exact defect this plan's uniformity table warns of.
# 3. Default `container.alignItems ?? .flexStart` instead of `.stretch`.
#    Expect: nothing yet — stretch lands in Task 3. RECORD THIS as a known
#    unguarded default, and confirm it reddens once Task 3 is done.
```

Mutation 3 is expected to redden nothing in this task. Say so plainly in the
report rather than quietly dropping it; Task 3's Step 7 re-runs it.

---

### Task 3: `stretch`, and widening every golden comparison

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Modify: `Tests/MetalUILayoutTests/AlignmentTests.swift`
- Modify: `Tests/MetalUILayoutTests/FreezeLoopTests.swift` (widen six comparisons)
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_stretch_mixed.html`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `resolvedAlignment`, `FlexItem`, `resolveDimension`.
- Produces: no new symbols — `collectItems` gains the stretch rule.

**This is the task the plan exists for.** Six comparisons in `FreezeLoopTests.swift`
currently check `x`/`width` only and carry a "main axis only" note, because our
engine gives cross size 0 where WebKit stretches. Implementing stretch makes them
agree, and **the goldens already hold the browser's stretched answer** — nothing is
regenerated, the comparisons simply widen.

**The rule:** an item is stretched when its resolved alignment is `stretch` **and**
its cross-axis size property is `auto`. A definite cross size wins outright; a
stretched size is still clamped by the item's cross-axis min/max.

- [ ] **Step 1: Write the failing test**

```swift
/// `stretch` fills the line's cross extent — but only for an item whose cross
/// size is `auto`, and never past its cross-axis max.
@Test func stretchFillsTheCrossAxisOnlyForAutoSizedItems() {
    let tree = LayoutTree()

    var autoStyle = Style()                       // height stays .auto
    autoStyle.size = Size(width: px(50), height: .auto)
    let stretched = tree.newNode(style: autoStyle, children: [])

    var definiteStyle = Style()                   // definite height wins
    definiteStyle.size = Size(width: px(50), height: px(30))
    let definite = tree.newNode(style: definiteStyle, children: [])

    var cappedStyle = Style()                     // auto, but capped at 60
    cappedStyle.size = Size(width: px(50), height: .auto)
    cappedStyle.maxSize = Size(width: .auto, height: px(60))
    let capped = tree.newNode(style: cappedStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [stretched, definite, capped])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(stretched).height == 100)
    #expect(tree.layout(definite).height == 30)
    #expect(tree.layout(capped).height == 60)
}

/// An explicit non-stretch alignment leaves an auto-sized item at its own size.
@Test func aNonStretchAlignmentLeavesAnAutoSizedItemUnstretched() {
    let tree = LayoutTree()
    var s = Style()
    s.size = Size(width: px(50), height: .auto)
    s.alignSelf = .center
    let item = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [item])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // Auto cross size with no content and no stretch is still 0 — and being 0,
    // `center` puts it at the line's midpoint.
    #expect(tree.layout(item).height == 0)
    #expect(tree.layout(item).y == 50)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter stretchFillsTheCrossAxisOnlyForAutoSizedItems`
Expected: FAIL — `stretched` and `capped` both measure 0.

- [ ] **Step 3: Implement in `collectItems`**

Where `cross` is computed, replace it:

```swift
            // CSS Flexbox §9.4 — cross-axis stretch.
            //
            // An item stretches when its resolved alignment is `stretch` AND its
            // cross size property is `auto`. A definite cross size wins outright;
            // a stretched size is still clamped by the item's cross min/max.
            //
            // This is why every fixture whose children have no explicit cross
            // size agreed with WebKit only on the main axis until now: CSS's
            // initial `align-items` behaves as `stretch`, so the browser filled
            // the container while we produced 0.
            let crossDim = isRow ? ks.size.height : ks.size.width
            let own = resolveNodeSize(tree, kid, parent: parent, rootFontSize: rootFontSize)
            let ownCross = isRow ? own.height : own.width
            let align = resolvedAlignment(ks, container: s)
            var cross = ownCross
            if align == .stretch, case .auto = crossDim {
                let lowerCross = resolveDimension(isRow ? ks.minSize.height : ks.minSize.width,
                                                  against: containerCross, rootFontSize: rootFontSize)
                let upperCross = resolveDimension(isRow ? ks.maxSize.height : ks.maxSize.width,
                                                  against: containerCross, rootFontSize: rootFontSize)
                cross = clamp(containerCross, min: lowerCross, max: upperCross)
            }
```

- [ ] **Step 4: Widen the six main-axis-only comparisons**

In `FreezeLoopTests.swift`, replace each `assertMainAxisMatchesGolden` call with
the full-rect `assertMatchesGolden`, and delete the "main axis only" note above
each. **Do not regenerate any golden** — the committed values already contain
WebKit's stretched cross sizes, which is precisely the evidence that this
implementation is right.

If `assertMainAxisMatchesGolden` then has no callers, delete it. A helper kept
"just in case" is how the next inert API gets born.

- [ ] **Step 5: Add a mixed fixture**

`flex_row_stretch_mixed.html` — one auto-height child, one with `height: 30px`,
one with `align-self: flex-start` and auto height, in a 100-tall row. This is the
only fixture that distinguishes "stretch everything" from "stretch the right
things".

Register at 800×600, regenerate, compare full-rect.

- [ ] **Step 6: Run the whole suite and commit**

Run: `swift package clean && swift test`
Expected: all pass. **Every** golden comparison is now full-rect.

```bash
git add -A
git commit -m "feat(layout): implement cross-axis stretch and widen every golden to the full rect"
```

- [ ] **Step 7: Prove it, and re-run Task 2's deferred mutation**

```bash
# 1. Stretch every item regardless of alignment (drop the `align == .stretch`).
#    Expect: flex_row_stretch_mixed and aNonStretchAlignmentLeaves...
# 2. Stretch regardless of the auto check (drop `case .auto = crossDim`).
#    Expect: stretchFillsTheCrossAxisOnlyForAutoSizedItems (definite → 100).
# 3. Skip the cross min/max clamp.
#    Expect: the `capped` expectation (60 → 100).
# 4. TASK 2's DEFERRED MUTATION: default `alignItems ?? .flexStart`.
#    Expect: it now reddens widely. If it still reddens nothing, the default is
#    unguarded and Task 2's report was right to flag it.
```

- [ ] **Step 8: Update CLAUDE.md**

Delete `justifyContent`, `alignItems`, `alignSelf` from the inert-API table.
`alignContent` and `flexWrap` **stay** — wrapping is a separate plan. Add
`baseline` if Task 2 did not. Correct the test count. Verify every remaining row
by grep, not by reading — two rows on the last branch were false.

---

### Task 4: Reverse directions

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_reverse.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_column_reverse_justify_end.html`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift`
- Modify: `Tests/MetalUILayoutTests/AlignmentTests.swift`
- Modify: `CLAUDE.md`

**Interfaces:** no new symbols — `positionItems` honours `FlexDirection.isReverse`.

**This closes a documented silent-wrong.** `FlexDirection.isReverse` has existed
since M1a with **zero readers**: a `.rowReverse` container lays out silently as
`.row`. Sizing is already correct — `isRow` is true for `.rowReverse` — so only
packing order is wrong.

**Reverse flips the main axis, not the cross axis.** `.rowReverse` starts at the
container's right edge and runs left; it does not touch vertical placement.
`column-reverse` starts at the bottom. `justify-content: flex-start` in a reverse
container packs against the *reversed* start, which is the visual end — the
single most common way to get this wrong.

- [ ] **Step 1: Write the failing test**

```swift
/// `.rowReverse` packs from the main-end edge, and `justify-content: flex-start`
/// follows the reversed axis rather than the visual left.
///
/// Items of 40/70/50 in a 400 row: forward gives 0/40/110; reversed gives
/// 360/290/240. Equal-sized items in a full container would make the two
/// indistinguishable, which is why these differ.
@Test func rowReversePacksFromTheEndAndFlipsJustifyContent() {
    let tree = LayoutTree()
    let a = fixedChild(tree, w: 40, h: 40)
    let b = fixedChild(tree, w: 70, h: 40)
    let c = fixedChild(tree, w: 50, h: 40)
    var rootStyle = Style()
    rootStyle.flexDirection = .rowReverse
    rootStyle.size = Size(width: px(400), height: px(40))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a) == LayoutRect(x: 360, y: 0, width: 40, height: 40))
    #expect(tree.layout(b) == LayoutRect(x: 290, y: 0, width: 70, height: 40))
    #expect(tree.layout(c) == LayoutRect(x: 240, y: 0, width: 50, height: 40))
}

/// Reverse flips the main axis only. The cross axis is untouched, so
/// `align-items: flex-end` still means the bottom of a reversed row.
@Test func reverseDoesNotFlipTheCrossAxis() {
    let tree = LayoutTree()
    var s = Style()
    s.size = Size(width: px(50), height: px(20))
    let item = tree.newNode(style: s, children: [])
    var rootStyle = Style()
    rootStyle.flexDirection = .rowReverse
    rootStyle.alignItems = .flexEnd
    rootStyle.size = Size(width: px(200), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [item])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(item).y == 80)      // cross-end, not flipped to 0
    #expect(tree.layout(item).x == 150)     // main-end, flipped
}
```

- [ ] **Step 2: Run to verify it fails, then implement**

Expected: FAIL — items sit at 0/40/110, the forward positions.

In `positionItems`, convert the cursor to a main-axis position at the point of
use rather than reversing the item array. Reversing the array would also reverse
which item is "first" for `space-between`'s leading offset, which is wrong:

```swift
    let isReverse = s.flexDirection.isReverse
    // ... per item, after `cursor` is advanced to this item's main-start:
    let main = isReverse ? (containerMain - cursor - item.targetMainSize) : cursor
    let x = containerOrigin.0 + (isRow ? main : crossOffset)
    let y = containerOrigin.1 + (isRow ? crossOffset : main)
```

- [ ] **Step 3: Two fixtures, generated and compared full-rect**

`flex_row_reverse.html` (three unequal children, `flex-direction: row-reverse`)
and `flex_column_reverse_justify_end.html` (`column-reverse` with
`justify-content: flex-end`, which composes the two flips and is where a
sign error shows). Register at 800×600, regenerate, compare full-rect.

- [ ] **Step 4: Run, commit, prove**

```bash
swift test
git add -A && git commit -m "feat(layout): honour reverse flex directions"
```

```bash
# 1. Ignore `isReverse` entirely.
#    Expect: both fixtures and rowReversePacksFromTheEndAndFlipsJustifyContent.
# 2. Reverse the cross axis too.
#    Expect: reverseDoesNotFlipTheCrossAxis.
# 3. Reverse by reversing the items array instead.
#    Expect: the column-reverse + justify-end fixture. If it reddens nothing, that
#    fixture is not composing the two flips and must be made to.
```

- [ ] **Step 5: Delete the reverse paragraph from `FlexEngine.swift`'s file header**

It documents reverse as unimplemented. It no longer is. Delete the
`isReverse` row from CLAUDE.md's inert-API table too, and correct the test count.

---

## Exit criteria

- [ ] `swift test` passes, no warnings; `swift package clean && swift build` clean
- [ ] `MetalUILayout` imports only `MetalUICore`
- [ ] **No golden comparison in the suite is main-axis-only.** `assertMainAxisMatchesGolden` is deleted, and the six notes in `FreezeLoopTests.swift` are gone
- [ ] The six goldens widened in Task 3 were **not** regenerated — they already held WebKit's stretched answer
- [ ] Every new fixture moves its numbers when its named declaration is swapped for its nearest sibling
- [ ] `justifyContent`, `alignItems`, `alignSelf` and `isReverse` are gone from CLAUDE.md's inert-API table; `alignContent`, `flexWrap` and `baseline` remain, with `baseline` newly added
- [ ] Each of these mutations reddens at least one test: trailing gap in the content size; `space-around`'s half-edge; `space-evenly`'s divisor; `align-self` ignored; stretching a definite cross size; ignoring `isReverse`
- [ ] `FlexEngine.swift`'s file header no longer documents reverse as unimplemented

## Deliberately NOT in this plan

- **Wrapping** — `flex-wrap`, line collection, cross-axis line stacking, and therefore **`align-content`**, which has no meaning with one line. This is the largest remaining flex gap.
- **The box model** — `resolveEdges` still has no engine caller. A root with `padding: 20, border: 5` still places its child at `(0,0)`.
- **Baseline alignment** — needs font metrics from M2.
- **Absolute positioning**, **aspect ratio**, **`MeasureCache`**, **Grid**.

## Risks carried in

- **`LayoutNodeID` has no generation counter** (m1a ruling C-3). A stale ID after `reset()` traps safely if the new tree is smaller but **silently addresses a different node** if larger.
- **We deliberately disagree with WebKit** on one sub-one-flex-factor edge case (ruling FS-9). Blink and the spec agree with us; WebKit is internally inconsistent. Do not "fix" this toward Safari.
- **`min-width: auto` has exactly one killing test** and no fixture can reach it until M2 supplies a measure function.
- **Two guarantees lapse under plausible CI configurations** — the ABI probe skips without a Metal device, and `committedGoldensMatchTheBrowser` is the only live-WebKit consumer. Both must be required, non-gateable jobs.
