# How do I lay out a screen?

SwiftUI's stacks and frames are the way to lay out a MetalUI screen: `VStack`, `HStack`,
`ZStack`, `Spacer`, `Grid`, `.frame`, `.padding`, `.background`. They follow SwiftUI's
algorithms, measured against SwiftUI ([`api-overview.md`](../api-overview.md#layout-swiftui-vocabulary--a)).
The older `Row`, `Column` and `Box` still work and sit on the same engine; this guide says
where they differ so a port does not move a pixel by accident. Every code block here is
compiled by the test suite, byte for byte
([`README.md`](README.md#how-the-code-blocks-are-checked)).

The pixel unit is `Pixels` (window points): write `Pixels(8)`, or a bare literal where a
`Pixels` is expected.

## How do I build a card with stacks and frames?

A card is a `VStack` of a title and an `HStack` whose `Spacer` pushes the two labels apart.
`.padding`, `.frame` and `.background` wrap it, outermost last. On SwiftUI-vocabulary content
`.padding` takes `Edges`, so an equal inset is `Edges(all: Pixels(16))`; a legacy `Box` or `Row` takes a
bare `Pixels`.

```swift
import MetalUI

/// A profile card: a title over a row whose spacer pushes two labels apart.
@MainActor
func layoutProfileCard() -> some Element {
    VStack(alignment: .leading, spacing: Pixels(8)) {
        Text("Ada Lovelace").font(size: 20)
        HStack {
            Text("Mathematician")
            Spacer()
            Text("1815")
        }
    }
    .padding(Edges(all: Pixels(16)))
    .frame(width: Pixels(240))
    .background(.surface)
}
```

A flexible frame is greedy, as in SwiftUI: `.frame(maxWidth: .infinity)` takes the proposal's
width. A window's root element is centred at its own answer, so give a root that should fill
the window a greedy frame (`CN-J`; the `rootView()` of a `metalui new` app does).
The window is the proposal: [`testing.md`](../testing.md) shows how to read a laid-out rect
back with `frame(ofID:)`.

## How do I port a `Row` or `Column` to `HStack` or `VStack`?

Change the container, then check the spacing. `Row` and `Column` default to a gap of 0, like
the CSS they came from; `HStack` and `VStack` default to 8, like SwiftUI's. The same two boxes
sit 20 points apart in one and 28 in the other (pin:
`theLayoutGuideRowAndHStackDifferByTheDefaultGap`).

```swift
/// Two 20-point boxes in a legacy `Row`: no gap.
@MainActor
func layoutLegacyRow() -> some Element {
    Row {
        Box().frame(width: Pixels(20), height: Pixels(20)).id("legacy-a")
        Box().frame(width: Pixels(20), height: Pixels(20)).id("legacy-b")
    }
}

/// The same boxes in an `HStack`: the default spacing of 8.
@MainActor
func layoutStackRow() -> some Element {
    HStack {
        Box().frame(width: Pixels(20), height: Pixels(20)).id("stack-a")
        Box().frame(width: Pixels(20), height: Pixels(20)).id("stack-b")
    }
}
```

To keep a ported layout identical, write `HStack(spacing: 0)`. The two vocabularies nest both
ways, so a port can go one container at a time ([`migration.md`](../migration.md) maps every
spelling). In a stack, a `Text` beside a view takes the default 8, where SwiftUI derives the
space from the font (divergence 51).

Two legacy habits to leave behind when you port: the `Row`'s CSS item fields (`.flexGrow`,
`.margin`) belong before `.padding` and are reported by name if a SwiftUI stack receives them,
and a legacy `.overlay` or `.background` on a `Component` with several members traps naming the
count (divergence 73). A `.frame` on such a `Component` frames each member, not the group
(divergence 56).

## Why does the order of modifiers matter, and where does `.id()` go?

Each modifier wraps what is written before it, so the order is the nesting. A background
written after `.padding` fills the padding; written before, it fills only the content. The
test reads both fills back by their ids: 40 points wide in the first, 20 in the second (pin:
`theLayoutGuideBackgroundFollowsTheModifierOrder`).

```swift
/// A fill that takes whatever it is proposed; a `Box` is the leaf the harness reads by id.
@MainActor
func layoutFill(_ name: String) -> some ProposalElementGroup {
    HStack {
        Box().frame(maxWidth: .infinity, maxHeight: .infinity).id(name)
    }
}

/// The fill sits outside the padding: it measures 40 × 40.
@MainActor
func layoutPaddingThenBackground() -> some Element {
    Rectangle().frame(width: Pixels(20), height: Pixels(20))
        .padding(Edges(all: Pixels(10)))
        .background(alignment: .center) { layoutFill("fill-outside") }
}

/// The fill sits inside the padding: it measures 20 × 20.
@MainActor
func layoutBackgroundThenPadding() -> some Element {
    Rectangle().frame(width: Pixels(20), height: Pixels(20))
        .background(alignment: .center) { layoutFill("fill-inside") }
        .padding(Edges(all: Pixels(10)))
}
```

`.id(_:)` goes **last**. A modifier chain is one flat sequence of layers, each layer one node
with one identity level, and an `.id` written after the chain's last modifier names the
outermost layer (pin: `anIDAfterAChainsLastWrapperNamesTheOutermostLayer`); the id then
names the whole padded element (pin: `theLayoutGuideAnIdWrittenLastNamesTheWholeElement`).
State, hit boxes and accessibility hang on that name, so [the state guide](state-and-identity.md)
relies on it.

```swift
/// `.id` last: the name belongs to the padded element, 40 × 40.
@MainActor
func layoutNamedWhole() -> some Element {
    HStack {
        Box().frame(width: Pixels(20), height: Pixels(20))
            .padding(Pixels(10))
            .id("whole")
    }
}
```

Two siblings that carry one `.id` share one identity (divergence 72).

## How do I line things up in a grid?

`Grid` and `GridRow` size each column to its widest cell, as SwiftUI's do. The second cells of
both rows below start at the same x, 60 + 8 points after the first column's origin, because
the first column is as wide as its widest cell (pin: `theLayoutGuideGridColumnsTakeTheirWidestCell`).

```swift
/// Two rows of two cells: column one is 60 wide, column two starts after it.
@MainActor
func layoutGrid() -> some Element {
    Grid(alignment: .topLeading, horizontalSpacing: Pixels(8), verticalSpacing: Pixels(4)) {
        GridRow {
            Box().frame(width: Pixels(40), height: Pixels(10)).id("cell-a1")
            Box().frame(width: Pixels(80), height: Pixels(10)).id("cell-a2")
        }
        GridRow {
            Box().frame(width: Pixels(60), height: Pixels(10)).id("cell-b1")
            Box().frame(width: Pixels(20), height: Pixels(10)).id("cell-b2")
        }
    }
}
```

`.gridCellColumns`, `.gridCellAnchor`, `.gridColumnAlignment` and `.gridCellUnsizedAxes` are
SwiftUI's. A modifier on a `GridRow` that holds several cells traps (divergence 66), a row of
text takes the default row spacing (divergence 65), and a baseline-aligned `GridRow` traps
at registration (divergence 88).

## How do I show ten thousand rows?

Put a `LazyVStack` in a scroller and a `ForEach` in it. Only the rows near the viewport are built:
in a 200-point window of 20-point rows, 13 of the 10 000 are realised, the ten on screen and three
more (the rows a frame behind the wheel would otherwise miss, divergence 637; pin:
`theLayoutGuideLazyRowsRealizeOnlyTheViewportAndTwoMore`).

```swift
/// Ten thousand rows: only the rows near the viewport are built.
@MainActor
func layoutLazyRows() -> some Element {
    ProposalScrollView {
        LazyVStack(alignment: .leading, spacing: Pixels(0)) {
            ForEach(0..<10_000) { index in
                ProposalText("Row \(index)").frame(height: Pixels(20))
            }
        }
    }
    .frame(width: Pixels(200), height: Pixels(200))
}
```

Rows may differ in height: each is measured when it is first built, a row not yet built counts as the
average of those that were, and the row on top stays where it is while the others are measured. A
content that holds an `if`, a `switch` or a `for` beside the `ForEach` builds every child instead
(divergence 636), so keep the lazy container's content to `ForEach` and plain views. `pinnedViews:` and
`Section` are not offered.

`LazyVGrid` takes `GridItem` columns and fills them a row at a time. `.adaptive(minimum: 40)` packs as
many columns of at least 40 points as fit: in 200 points with the default gap of 8 that is four columns
of 44 points, so the grid below builds 10 rows of 4, 40 cells of its 10 000 (pin:
`theLayoutGuideLazyGridPacksFourColumnsAndRealizesTenRows`).

```swift
/// Ten thousand cells: columns of at least 40 points, as many as fit.
@MainActor
func layoutLazyGrid() -> some Element {
    ProposalScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Pixels(40)))], spacing: Pixels(8)) {
            ForEach(0..<10_000) { index in
                ProposalText("\(index)").frame(height: Pixels(20))
            }
        }
    }
    .frame(width: Pixels(200), height: Pixels(200))
}
```

The count an adaptive item packs is read from the grid's width one frame earlier, so the first frame
shows one column and the next shows four (divergence 638). A `ForEach` element that yields two views is
one cell holding both, where SwiftUI makes each view a cell (divergence 635).

## Divergences you will hit

Each row is in [`divergences.md`](../divergences.md); the list is checked against it.

- divergence 51: spacing beside text in a stack is the default 8, not font-derived.
- divergence 52: `Row` and `Column` default to a gap of 0; `HStack` and `VStack` to 8.
- divergence 56: `.frame` on a multi-member `Component` frames each member.
- divergence 65: rows of text in a `Grid` take the default row spacing.
- divergence 66: a modifier on a multi-cell `GridRow` traps.
- divergence 72: two siblings with one `.id` share one identity.
- divergence 73: a legacy `.overlay` or `.background` on a multi-member primary traps naming the count.
- divergence 88: a baseline-aligned `GridRow` traps at registration.
- divergence 635: a `ForEach` element of several views is one cell of a lazy grid.
- divergence 636: a lazy container whose content holds an `if`, `switch` or `for` builds every child.
- divergence 637: a lazy container builds two more lines than are on screen on each side.
- divergence 638: an adaptive lazy grid packs its columns from the previous frame's width.

Next: [state and identity](state-and-identity.md), [input](input.md), and
[`api-overview.md`](../api-overview.md) for every declaration.
