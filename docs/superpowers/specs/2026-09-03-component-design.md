# `Component` — the User-Facing Element Surface — Design

**Milestone:** M4, spec 2 of 4.
**Binding authority above this document:** `docs/superpowers/specs/2026-08-24-metalui-design.md`,
§4.2 (*`Component` — the user-facing surface*) and §12 row 4.

M4 is one milestone delivered as four specs in dependency order — reactivity (merged,
`d0aca58`), `Component` + result builders, animation & easing, then the `ElementGroup`
child-id change and the AX platform bridge. This is the second.

**Exit criterion this spec owns:** none of M4's three on its own. `Component` is a
prerequisite for "a real small app", which is closed by the milestone rather than by this
spec. Said plainly up front so nobody reads a passing suite here as closing a criterion.

---

## 1. What is already built, and what the gap actually is

**The result builder is complete.** `ElementBuilder` (`Sources/MetalUI/ElementBuilder.swift`)
already provides `buildBlock`, `buildPartialBlock` (both arities), `buildOptional`,
`buildEither` (both directions) and `buildArray`, with `EmptyGroup`, `Pair`,
`OptionalGroup`, `EitherGroup` and `ArrayGroup` as its products. M4's §12 row names
"`Component` + result builders" as one item; **the second half exists** and this spec adds
nothing to it. Read the row as one deliverable, not two.

**The gap is `Component`.** `grep -rn "protocol Component" Sources/` returns nothing.
Today every element author implements `Element` directly: four associated types and three
phase methods, for a type whose whole content is "these children, arranged like this."

---

## 2. The decision, and it is one sentence with two halves

**A `Component` is transparent to LAYOUT and opaque to IDENTITY.**

Those are separate axes in this framework and this is the first type to use them
differently. Every existing element is opaque to both: a `Box` consumes one cursor index
*and* contributes one layout node.

- **Layout-transparent** means a component contributes **no layout node of its own**. Its
  content's nodes pass through to its parent unchanged, so `Column { MyRow(); MyRow() }`
  lays out the rows' children as direct children of the `Column`.
- **Identity-opaque** means a component consumes **one cursor index** and its content nests
  beneath its own `GlobalElementID`.

**Identity-opacity is not a choice.** `@State` slots are `.named("$state\(n)")` children of
the element's own `GlobalElementID` (`StateBinder.bind`), so a component with no id of its
own cannot hold state — and holding state is the main reason to write a component rather
than a function returning elements. The cursor index is what buys the id.

### Why this is SwiftUI's shape, and the part of that claim that is NOT measured

SwiftUI's custom `View` contributes no layout container: `VStack { MyRow() }`, where
`MyRow`'s body is two `Text`s, lays those two texts out as the stack's own children rather
than nesting them. `.padding()` does introduce a layer, but by wrapping the view in
`ModifiedContent` — the modifier is not applied *to* the custom view's own (nonexistent)
node.

**That description of SwiftUI is DERIVED from its documented behaviour and was not measured
here.** There is no SwiftUI test target in this repo and this spec does not add one. It is
recorded as derived on the same footing ruling `RX-P` uses for the windowed-`List`
comparison. If SwiftUI turns out to differ, this is a divergence and the label is
available; nothing here forecloses it.

---

## 3. What was rejected, and why — three options, each with its cost

Recorded because two of the three were live candidates and a reader will otherwise
re-derive them.

**`StyledElement` conformance was rejected.** It would give `MyComponent().padding(12)` for
free and read closest to SwiftUI at the call site. It fails on two counts. `StyledElement`
has four requirements — `style`, `decoration`, `elementID`, `handlers` (ruling `IN-H`) — so
every component an author writes carries four stored properties of boilerplate; and a
`Style` must attach to a layout node, so conforming **forces** the component to contribute
one. `Style.display` defaults to `.flex` and the engine has no `contents` case
(`grep -n "public enum Display" Sources/MetalUILayout/Style.swift` → `case flex, stack,
none`), so that node is a real flex container and the component becomes layout-opaque —
the exact divergence from SwiftUI this design exists to avoid.

**`display: contents` was rejected for this spec, and it is the CSS-correct primitive.**
A node that contributes its children to its parent's layout as though it were not there is
exactly this problem's CSS answer. It was rejected on scope, not on merit: it is
layout-engine work in `collectItems` and the flex algorithm, it needs browser fixtures and
goldens, and it would be the first thing in three specs to move one. **It remains the right
way to give a *styled* box the transparent behaviour**, which is a thing this design cannot
express at all — see §7. Filed as a named follow-up, not as a mystery.

**A `Modified<C>` wrapper carrying a `Style` around any component was rejected** as a
second styling mechanism beside `StyledElement`, which this framework has so far kept to
exactly one. §5's modifier extensions get the same ergonomics by returning a `Box`, which
is a mechanism that already exists.

---

## 4. The mechanism

### 4.1 The protocol

```swift
@MainActor
public protocol Component: ElementGroup {
    associatedtype Content: ElementGroup
    @ElementBuilder var content: Content { get }

    /// The component's local name among its siblings, or `nil` to be identified
    /// by position. Same contract as `Element.elementID`.
    var elementID: ElementID? { get }
}
```

`@MainActor` matches `ElementGroup` and `Element`, both of which carry it
(`ElementGroup.swift:43`, `Element.swift:43`).

**`Content: ElementGroup`, and this DIVERGES from design spec §4.2, which says
`Content: Element`.** The divergence is what makes layout transparency possible: a bare
`{ Text(…); Text(…) }` block builds a `Pair`, which is an `ElementGroup` and is not an
`Element`, so under §4.2's literal text a component could never have two top-level
children. `Element` refines `ElementGroup`, so `ElementGroup` is strictly more permissive
and a single-element content still satisfies it. §4.2 must be corrected in place.

`elementID` gets a default of `nil` in the extension. **There is deliberately no `.id()`
modifier**: that method lives on `StyledElement`, which a component does not conform to,
and a wrapper type supplying the name would either introduce a layout node (defeating §2)
or introduce a second identity level (making the name apply to the wrong id). An author who
needs a stable name declares the property:

```swift
struct Row: Component {
    let item: Item
    var elementID: ElementID? { ElementID(String(describing: item.id)) }
    var content: some ElementGroup { … }
}
```

That is less pretty than `.id(…)` and it is the spelling that cannot be wrong.

### 4.2 The conformance

`Component`'s `ElementGroup` conformance comes from one protocol extension, so an author
writes `content` and nothing else.

```swift
public struct ComponentLayout<C: Component> {
    var id: GlobalElementID
    var content: C.Content
    var contentLayout: C.Content.GroupLayout
}

extension Component {
    public var elementID: ElementID? { nil }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], ComponentLayout<Self>) {
        let id = GlobalElementID.child(of: parent, at: cursor, name: elementID)
        StateBinder.bind(self, table: pass.frame.stateTable, id: id)
        cursor += 1

        // Materialized ONCE and stashed. `content` is computed: re-evaluating it
        // in a later phase would build fresh structs, discarding whatever the
        // earlier phase wrote into them.
        var materialized = content
        var innerCursor = 0
        let (nodes, contentLayout) =
            materialized.requestGroupLayout(under: id, at: &innerCursor, pass: &pass)

        return (nodes, ComponentLayout(id: id,
                                       content: materialized,
                                       contentLayout: contentLayout))
    }

    public mutating func prepaintGroup(layout: inout ComponentLayout<Self>,
                                       pass: inout PrepaintPass)
        -> Content.GroupPrepaint {
        layout.content.prepaintGroup(layout: &layout.contentLayout, pass: &pass)
    }

    public mutating func paintGroup(layout: inout ComponentLayout<Self>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        layout.content.paintGroup(layout: &layout.contentLayout,
                                  prepaint: &prepaint, pass: &pass)
    }
}
```

**Three lines are load-bearing and each is stated with what breaks if it changes:**

- **`materialized.requestGroupLayout(…)`, never `requestLayout(…)`.** That call is what
  reaches `StateBinder.bind` for every element in the content. Calling `requestLayout`
  directly is the live `AnyElement` defect in CLAUDE.md's declared-but-inert table: `@State`
  returns its initial value forever, with **no diagnostic**.
- **`nodes` is returned unchanged.** Wrapping it, or replacing it with a node of the
  component's own, is what makes the component layout-opaque.
- **`cursor += 1` on the outer cursor, and a fresh `innerCursor` at 0.** The component takes
  one index from its parent; its content numbers from zero beneath the component's own id.
  Threading the outer cursor into the content instead would give the content its
  *siblings'* positions and silently collide their state.

### 4.3 Zero children are legal

`EmptyGroup` is an `ElementGroup`, so `var content: some ElementGroup { EmptyGroup() }` — or
a builder block with no statements — is a component contributing **zero** layout nodes. Its
identity level still exists, so its own `@State` still works. That is consistent with
`Box()`, which is also childless, and is not an error.

---

## 5. Modifiers wrap, they do not attach

`Component` conforms to no styling protocol, so `StyledElement`'s modifiers do not apply.
The extension supplies them by **wrapping in a `Box`**:

```swift
extension Component {
    public func padding(_ points: Pixels) -> Box<Self> {
        Box(content: self).padding(points)
    }
    // … and so on for the modifiers a component author actually needs
}
```

`Box<Content: ElementGroup>` (`Box.swift:30`) and `Box.init(style:decoration:content:)`
(`:43`) both accept any `ElementGroup`, so `Box<Self>` needs no new machinery. Note the
signature: `StyledElement.padding` takes `Pixels` (`Box.swift:643`) or `Edges<Length>`
(`:647`) — **not** a bare `Length`. Forward whichever overloads are wanted, with the exact
parameter types the `StyledElement` originals use; a forwarded modifier whose signature
drifts from its original is worse than none, because a caller reads the two as the same
modifier.

So `MyComponent()` is transparent and `MyComponent().padding(12)` introduces exactly one
flex container — which is what `ModifiedContent` does in SwiftUI, and is the same trade a
`Box` makes anywhere else.

**The cost is real and is stated rather than buried.** A modified component is
layout-*opaque*: its children become children of the wrapping `Box`, not of the component's
parent. So `Column { MyRow() }` and `Column { MyRow().padding(4) }` arrange `MyRow`'s
children differently, and that is visible rather than silent — a padded thing looks padded.
What has no spelling at all is "styled *and* transparent", which is `display: contents`'
job (§3).

**Which modifiers to forward is deliberately left to implementation**, with one rule: a
modifier is forwarded only if it is already live on `StyledElement`. Forwarding an inert one
(`aspectRatio`, `overflow`) would put a second unreachable API in front of a caller, which
is what CLAUDE.md's inert table exists to prevent.

---

## 6. Testing

Counts and structure, never wall-clock times.

1. **A component's content flattens into its parent.** `Column { MyRow() }` where `MyRow`'s
   content is two boxes gives the `Column` **two** children, not one — asserted on the
   layout tree, and asserted as geometry too, since a nested flex container would change
   the boxes' positions.
2. **A component contributes no layout node.** The node count for a tree with a component
   equals the count for the same tree with the component's content written inline.
3. **A component's `@State` survives across frames**, and this is the test that would be
   green under the `AnyElement` bug's shape — see mutation 1 below.
4. **Two sibling instances of the same component hold independent state.** This is what the
   `innerCursor` reset and the outer `cursor += 1` buy together; a shared cursor would
   collide them.
5. **A named component keeps its state through a reorder**, and an unnamed one does not.
   Both halves, on the pattern `namingTheLaterSiblingIsWhatSurvivesAVanishingIf` already
   uses — the asymmetry is the evidence.
6. **A component with an empty content block contributes zero nodes and still holds state.**
7. **A modified component introduces exactly one node**, and its children become that
   node's children — §5's stated cost, asserted so it is documented behaviour rather than a
   surprise.
8. **A component nested inside a component flattens through both levels**, with two identity
   levels and zero layout nodes added.

### Mutations that must be run, not predicted

- **`requestGroupLayout` → `requestLayout` for the content.** Must redden assertion 3. If it
  does not, the state test is not reaching the bind path and assertion 3 is inert.
- **Return a wrapping node instead of `nodes`.** Must redden assertions 1 and 2.
- **Thread the outer `cursor` into the content instead of a fresh `innerCursor`.** Must
  redden assertion 4. This is the mutation most likely to redden *nothing* on a
  single-component fixture — the two-sibling fixture exists for it, and if it stays green
  the fixture cannot express the defect (ruling `MP-J`'s shape).
- **Drop `cursor += 1`.** Must redden assertion 4 as well, for a different reason; if one
  mutation reddens both, one of the two assertions is proving less than it claims.

### What no test here can see

- **Whether `Component` is pleasant to write.** The whole point of the type is ergonomics,
  and no assertion reaches that. The demo is the only evidence, and it is weak evidence.
- **Whether SwiftUI actually flattens** (§2). Derived, not measured, and no test here can
  measure it.

---

## 7. Not in scope, named rather than left open

- **`display: contents`** (§3) — the only way to have a styled *and* layout-transparent box.
  Engine work, needs fixtures and goldens.
- **A `.id()` modifier on `Component`** (§4.1) — needs either a layout node or a second
  identity level; the defaulted property is the spelling that cannot be wrong.
- **Converting existing elements or the demo to `Component`.** `Box`, `Column`, `Row`,
  `Stack`, `List`, `Text`, `Deferred` and `ScrollView` stay as they are. Design spec §4.2
  says implementing `Element` directly "remains available and is expected for the node
  graph", and a conversion would put a large diff with no behavioural content in front of
  the same review as a new protocol.
- **The demo.** One small component in `MetalUIDemo` is worth having as the type's first
  real caller, and `CounterPanel` is the obvious candidate — but the demo carries every past
  milestone's human-verification criteria, so any change to it is a change to that evidence.
  Implementation may convert `CounterPanel` **only** if the conversion moves no rect; if it
  moves one, leave the demo alone and say so.

---

## 8. Exit criteria

1. `Component` exists; an author writes `content` and `elementID` (optional) and nothing
   else, and gets a working element.
2. Every assertion in §6 passes, and every mutation in §6 has been **run** with its actual
   result recorded at the mutated line.
3. `swift test --no-parallel` green at the milestone's expected count, warning-free, summary
   line read rather than exit status.
4. **No golden moves and none is added.** This spec touches no layout code;
   `git diff --name-only <base>..HEAD -- Sources/MetalUILayout/` must be empty.
5. Design spec §4.2 is corrected in place: `Content: ElementGroup`, not `Content: Element`,
   with the original claim visible and the reason stated.
6. `hasActiveAnimations` still does not exist in `Sources/` — M4 spec 3 owns it.

---

## 9. Risks recorded up front

| Risk | Standing |
|---|---|
| An author writes a component expecting `.padding()` to apply to the component's own frame | It applies to a wrapping `Box` instead, which for a single-child component is indistinguishable and for a multi-child one changes the arrangement. §5 states it; nothing enforces it |
| `Content: ElementGroup` lets a component return a group where a single element was meant, and a caller cannot tell from the type | True, and it is the same latitude `Box`'s content already has. The alternative forbids two children |
| The SwiftUI-flattening claim is wrong | Then this is a divergence, and §2 says so in advance rather than presenting the claim as settled. The label is available |
| `StateBinder.bind`'s per-instance `Mirror` walk now runs for components too | ~2.3 us per *stateful* element per frame (CLAUDE.md); a component with no `@State` costs a dictionary hit against an empty array. Unchanged in kind from any other element |
| A future `StyledElement` conformance is added to `Component` for convenience | It would silently make every existing component layout-opaque and move every rect in every tree using one. §3 records why it was refused; this row is what a reader finds if they try |
