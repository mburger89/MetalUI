# How do I keep state, share data and keep identity straight?

State in MetalUI is SwiftUI's: `@State`, `Binding`, `@Observable`, `@Environment`. What a
SwiftUI author trips on is **identity**: the tree is rebuilt every frame, and what a `@State`
belongs to is decided by position and `.id`, not by the value of a struct. This guide shows
the four things to get right. The reference is
[`api-overview.md`](../api-overview.md#builders-identity-state-binding-environment--a); the
tests that drive these blocks through a headless window are described in
[`testing.md`](../testing.md). Every code block is compiled by the test suite
([`README.md`](README.md#how-the-code-blocks-are-checked)).

## How do I keep local state and bind a control to it?

Put `@State` in a `Component`: a `Component` is MetalUI's small view struct, layout-transparent
and the owner of its state. `$name` is a `Binding<String>`; `TextField` takes one. A click
focuses a `TextField`, and typing writes the binding (pin:
`theStateGuideATypedNameWritesTheBinding`).

```swift
import MetalUI

/// `@State` lives as long as the component keeps its place in the tree;
/// `$name` is a `Binding` to it.
struct StateGreeting: Component {
    @State var name = "Ada"
    @State var greetings = 0

    var content: some ElementGroup {
        TextField("Name", text: $name)
        Button("Greet") { greetings += 1 }
        Text("Hello \(name), greeted \(greetings) times")
    }
}

/// The window's root: any container takes the component.
@MainActor
func stateGreetingRoot() -> some Element {
    VStack(alignment: .leading) { StateGreeting() }
}
```

Write state **from input** (a button, a key, a gesture), not from inside a build: the project's
rule (`CLAUDE.md`, `@State`) is that a write made during a phase is silently stale. A `Binding` is
`@MainActor` here, where SwiftUI's is not (divergence 78; pin: `aBindingIsMainActorIsolated`).
`Binding.animation` applies only to a binding projected from `@State`.

## How do I share a model across the tree?

Make the model an `@Observable` class, provide it once with `.environment(_:)` on a subtree, and read it
with `@Environment(Type.self)`. The object is found by its static type, the nearest provider
wins, and a missing one traps with a message naming the type (divergence 134). `@Bindable` and
`ObservableObject` are not offered.

```swift
import Observation

/// A shared model: an `@Observable` class, provided once and read by type.
@Observable @MainActor
final class StateTodoStore {
    var items = ["Write", "Test", "Ship"]

    func reverse() { items.reverse() }
}

/// A row's `@State` follows its value: the `ForEach` below uses the item as the id.
struct StateTodoRow: Component {
    let title: String
    @State var taps = 0

    var content: some ElementGroup {
        Button("\(title): \(taps)") { taps += 1 }
    }
}

struct StateTodoList: Component {
    @Environment(StateTodoStore.self) var store

    var content: some ElementGroup {
        Button("Reverse") { store.reverse() }
        ForEach(store.items, id: \.self) { item in
            StateTodoRow(title: item)
        }
    }
}

/// The store is provided once, around the component that reads it.
@MainActor
func stateTodoRoot(_ store: StateTodoStore) -> some Element {
    VStack(alignment: .leading) {
        StateTodoList().environment(store)
    }
}
```

The frame build is observed, so a write to `store.items` reaches the window (`RX-K`). A test that
writes a model outside input calls `try await window.runUntilIdle()` to draw it on every platform
([`testing.md`](../testing.md#the-clock-and-rununtilidle)). Write from input in the app.

## What keeps a row's state, and what loses it?

A `ForEach` identifies each element by the **value** of its id, as SwiftUI does: two ids that
print alike and differ in value are two elements (record §95). So when the store above is
reversed, the row titled "Write" is still the row titled "Write", with the taps it had (pin:
`theStateGuideForEachRowsKeepTheirStateWhenTheDataReorders`). Use a stable, `Hashable` id from
your data; an index is a position, and state follows positions.

State is lost in exactly two ways, both shown below. Content that an `if` stops producing starts
fresh when it comes back (pin: `theStateGuideAHiddenBranchStartsFreshWhenItReturns`), and a
changed `.id` names a new element (pin: `theStateGuideANewIdStartsFresh`). Write `.id` as the
last modifier of the chain, as [the layout guide](layout.md#why-does-the-order-of-modifiers-matter-and-where-does-id-go) explains. A
`ForEach` takes one structural slot whether or not it produces content, so the siblings after it
keep their state (pin: `aForEachIsOneSlotSoTheTrailingSiblingKeepsItsState`).

```swift
struct StateTaps: Component {
    @State var taps = 0

    var content: some ElementGroup {
        Button("Taps: \(taps)") { taps += 1 }
    }
}

/// "Toggle" hides and shows the counter; "New id" gives it another name.
struct StateLosses: Component {
    @State var shown = true
    @State var generation = 0

    var content: some ElementGroup {
        Button("Toggle") { shown.toggle() }
        Button("New id") { generation += 1 }
        if shown {
            StateTaps().id("taps-\(generation)")
        }
    }
}
```

Two cautions. A `@State` that is never written is seeded again by every build, so a default such
as `@State var monitor = Monitor()` is a different instance in `onAppear` and `onDisappear`;
assign the instance in `onAppear` instead (divergence 125). And a single element value placed twice
resolves its own occurrence only under input dispatch; a write from a phase reaches the last one
(divergence 71).

## How do I show a long list, and let the user select rows?

`List` is windowed: it builds the rows around the viewport, so it must sit in a `ScrollView`.
Data is `Identifiable`; the `List(_:selection:rowContent:)` form sizes each row from its
content, and `rowHeight:` selects the uniform-height fast path. A click selects a row and writes
the binding; a `Set` binding allows a range with shift (pin: `aShiftClickSelectsTheRangeFromTheAnchor`) and a
toggle with the platform's shortcut key (pin: `aShortcutClickTogglesARowInAMultiSelectionList`).
Rows outside the window are not in the tree, so a test or a screen reader reaches only the
realised ones (pin: `theStateGuideAListBuildsOnlyItsWindowAndSelectsOnClick`).

```swift
struct StateRowItem: Identifiable {
    let id: Int
    var title: String { "Row \(id)" }
}

struct StateRowPicker: Component {
    @State var picked: Set<Int> = []
    let items = (0..<200).map { StateRowItem(id: $0) }

    var content: some ElementGroup {
        Text("Selected: \(picked.count)")
        ScrollView {
            List(items, selection: $picked) { item in
                Text(item.title).padding(Pixels(6))
            }
        }
        .frame(height: Pixels(200))
    }
}
```

Keep durable values in your data, not in a row's `@State`: a row that stays out of the window
for long enough loses its state once the state table is large (`TB-AH`, record §69). A
content-sized row is exactly its content's height at the list's width, with no inset and no floor
(divergence 145); an insertion above the viewport keeps the top row where it is (divergence 146);
rows not yet measured count at an estimate (divergence 147), which you can set with
`estimatedRowHeight:`. Rows whose ids print alike but differ in value are separate rows with
separate state, in a `List` as in a `ForEach` (pin: `aUniformListsCollidingIDsKeepSeparateState`).

## Divergences you will hit

Each row is in [`divergences.md`](../divergences.md); the list is checked against it.

- divergence 71: a value placed twice and written outside input reaches the last occurrence.
- divergence 78: `Binding` is `@MainActor`.
- divergence 125: a never-written `@State` default is seeded again by every build.
- divergence 134: a missing environment object traps, naming the type.
- divergence 145: a content-sized `List` row is exactly its content's height.
- divergence 146: an insertion above the viewport keeps the top row in place.
- divergence 147: unmeasured rows count at an estimate.

Next: [input](input.md); back to [layout](layout.md).
