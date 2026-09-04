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

### Why this is SwiftUI's shape — measured, not assumed

SwiftUI's custom `View` contributes no layout container: `VStack { MyRow() }`, where
`MyRow`'s body is two `Text`s, lays those two texts out as the stack's own children rather
than nesting them. `.padding()` does introduce a layer, but by wrapping the view in
`ModifiedContent` — the modifier is not applied *to* the custom view's own (nonexistent)
node.

**Read that last sentence only as a statement about SwiftUI's TYPE, not about its layout
effect, and §5 is why.** `ModifiedContent` is real and `.padding()` really does produce one;
what it does *not* do is introduce a layout box around the transparent body. §5 measured
that and the number is `120 × 26` — the padding lands on each child. This sentence was the
stated basis for §5's original wrapping design, which the measurement overturned, so it is
kept with the qualifier attached rather than deleted.

**MEASURED on 2026-09-03, and this paragraph previously said it was not.** The first draft
recorded the SwiftUI description as derived-from-documentation on ruling `RX-P`'s footing,
because there is no SwiftUI test target in this repo. It was then measured with a throwaway
probe outside the repo: a custom `Layout` conformer recording `subviews.count`, hosted in an
`NSHostingView` and forced to lay out.

| case | subview count |
|---|---|
| inline `A; B` — **the positive control** | 2 |
| `Group { A; B }` — SwiftUI's documented transparent container | 2 |
| `MyRow()`, whose body is two views | **2** |
| `MyRow(); MyRow()` | **4** |

A `Layout` conformer sees through a custom view exactly as it sees through `Group`. The
fourth row matters: it rules out the third being an artifact of having only one instance.
**SwiftUI is layout-transparent for custom views, and this framework agrees with it.**

The probe was not committed, on the footing this repo uses for oracle probes — a committed
version would pin the standard library's behaviour rather than this framework's. The
technique is recorded here so it can be re-run rather than re-derived.

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

**A `Modified<C>` wrapper carrying a `Style` around any component was rejected in the first
draft**, on the grounds that it would be a second styling mechanism beside `StyledElement`.
**That rejection is withdrawn**: §5 now implements something very close to it, because
measurement showed the alternative — wrapping in a `Box` — is not what SwiftUI does. The
reasoning that survives is narrower: the wrapper must **distribute** a style over the
content's top-level nodes rather than **carry** one of its own, so it introduces no second
styling model, only a second way to reach the existing one.

---

## 4. The mechanism

### 4.1 The protocol

```swift
public protocol Component: ElementGroup {
    associatedtype Content: ElementGroup
    @ElementBuilder var content: Content { get }

    /// The component's local name among its siblings, or `nil` to be identified
    /// by position. Same contract as `Element.elementID`.
    var elementID: ElementID? { get }
}
```

**Corrected by the fix wave: the declaration above carried an explicit
`@MainActor` and the shipped one carries no attribute at all.** The isolation is
unchanged — it is **inherited** from `ElementGroup`, which is `@MainActor`
(`ElementGroup.swift:43`) — and that was **measured, not reasoned**:
`nonisolated func probe(_ c: C1) { _ = c.content }` against a plain-import
`Component` conformer is rejected with *"main actor-isolated property 'content'
can not be referenced from a nonisolated context."*

So the attribute would have been redundant rather than wrong, and this
correction changes no behaviour. It is made anyway because this section is the
branch's binding authority and a reader comparing it to
`Sources/MetalUI/Component.swift` finds a difference the document does not
explain. **Note the sibling convention it departs from**: `Element` refines the
same `@MainActor` protocol and *does* write the attribute (`Element.swift:43`).
Whether `Component` should match that spelling is a style question this fix wave
does not decide; what it settles is that the isolation is the same either way.
Design spec §4.2's own correction block carried the same spurious `@MainActor`
and is corrected there too.

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

**Corrected by the fix wave: `ComponentLayout` has no `id` field as shipped**
(ruling `CO-H`). The declaration and the construction below both carried one
when this section was written; **nothing read it** — `Component`'s
`prepaintGroup` and `paintGroup` forward to `layout.content` and pass no id.
The field was modelled on `SingleElementLayout.id` (`ElementGroup.swift`),
which *is* read, and that is what misled. `CO-H` deleted it rather than tabling
it in the declared-but-inert table: re-adding one line is cheaper than a row
for a struct this new.

```swift
public struct ComponentLayout<C: Component> {
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

        return (nodes, ComponentLayout(content: materialized,
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

## 5. Modifiers DISTRIBUTE — measured, after this section said they wrap

**This section previously specified that a modifier on a component wraps it in a `Box`**, on
the stated grounds that this is what SwiftUI's `ModifiedContent` does. **That was measured
and is false.** SwiftUI distributes a modifier over a transparent multi-child body; it does
not wrap it. The original claim is recorded here rather than deleted, because the design was
built on it and a reader deserves to know it was tested.

The measurement, a throwaway probe outside the repo reading `NSHostingView.fittingSize`:

| case | measured |
|---|---|
| `HStack { Color.red.frame(30,10).padding(8) }` — **the positive control** | 46 × 26 |
| `HStack { MyRow() }` — baseline, `MyRow`'s body is 30×10 and 50×10 | 88 × 10 |
| `HStack { MyRow().padding(8) }` | **120 × 26** |
| `HStack { Group { A; B }.padding(8) }` — the known-distributing case | **120 × 26** |

`(30 + 16) + 8 + (50 + 16) = 120` — the padding is applied to **each** child, and the result
is bit-identical to `Group`'s. A wrapping implementation predicts 96–104. The baseline's 88
(`30 + 8 + 50`, with `HStack`'s default spacing) independently corroborates §2's flattening
result on a different instrument.

**The two findings are one mechanism.** `MyRow()` *is* its children, so a modifier applied to
it applies to each of them, because there is no single thing to wrap. Transparency and
distribution are the same fact seen twice.

### What this framework does

A modifier on a `Component` returns a wrapper that is itself an `ElementGroup`. The wrapper
calls the component's `requestGroupLayout`, then **amends the style of each top-level node
the content contributed** and returns those same nodes unchanged. It contributes no node of
its own, so a modified component stays layout-transparent — which a wrapping implementation
would have destroyed.

```swift
public struct StyledComponent<C: Component>: ElementGroup {
    var component: C
    var amend: (inout Style) -> Void
    // requestGroupLayout: forward to `component`, then for each returned node
    //   var s = pass.style(node); amend(&s); pass.setStyle(node, s)
    // …and return the same nodes.
}
```

**The mechanism already exists and needed no engine change** (measured by probe):

- `LayoutTree.setStyle(_:_:)` (`LayoutTree.swift:104`) overwrites a registered node's `Style`
  in place. It is `public` and has **zero production callers** today — two tests in
  `LayoutContextTests` are its only exercise — so this is its first.
- **Registration derives nothing from style.** `newNode`/`newLeaf` (`LayoutTree.swift:83-97`)
  append the style and zeroed layout into parallel arrays; every engine consumer reads it
  fresh through `tree.style(id)` inside `computeLayout`. Amendment after registration is
  therefore sound rather than merely tolerated.
- **The one guard is a phase boundary and this is safely inside it.** `setStyle` traps when
  `isLayingOut`, which is set only within `computeLayout`. `Frame.render` completes the whole
  `requestGroupLayout` walk before calling `computeRootLayout`, so a modifier amending styles
  during the request phase cannot trip it.
- **No `ElementGroup` change is needed.** The wrapper operates on raw `LayoutNodeID`s, not on
  the Swift values that produced them, so it is indifferent to whether a top-level child came
  from a `StyledElement` or from a nested non-`StyledElement` `Component`. That was the hazard
  most likely to make distribution impossible, and it does not arise.

### The limit, and it is the part to read before planning

**Only `Style`-backed modifiers can be distributed this way.** `padding`, `width`, `height`,
`flexGrow`, `flexShrink`, `alignSelf` and the rest of `Style` live in `LayoutTree`, keyed by
node, and `setStyle` reaches them.

**`Decoration`- and `Handlers`-backed modifiers cannot** — `background`, `onClick`,
`focusable`, `keyContext`, `hoverBackground`, `focusBackground`. Those are per-*element*
state, registered by each `StyledElement`'s own `prepaint` through `registerHandlers`, and
there is **no per-node table to amend**. Distributing them hits exactly the
non-`StyledElement`-child wall that `setStyle` sidesteps, and would need a different
mechanism.

**So this spec forwards `Style`-backed modifiers only, and offers the others not at all.**
Offering `.background()` with wrapping semantics while `.padding()` distributes would be
worse than offering neither: two modifiers that read identically at the call site and behave
differently. An author who wants a background writes an explicit `Box` around the component,
which is one visible line and is honest about introducing a container.

**Which `Style`-backed modifiers to forward is left to implementation**, with one rule: only
those already live on `StyledElement`. Forwarding an inert one (`aspectRatio`, `overflow`)
would put a second unreachable API in front of a caller, which is what CLAUDE.md's inert
table exists to prevent.

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
7. **A modified component stays transparent and its style reaches EACH top-level child.**
   `Row { TwoLeaves().padding(4) }` must add **no** node and must pad both leaves — the
   arithmetic separating distribution from wrapping is the same one the SwiftUI probe used,
   so assert the rects, not just the node count. A wrapping implementation adds one node and
   pads once; both halves must be checked, because the node count alone cannot tell
   distribution from a no-op.
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
- **Whether SwiftUI flattens or distributes** (§2, §5). Both are now measured, but by
  throwaway probes outside this repo that are deliberately not committed. Nothing in the
  suite re-checks them, so a future SwiftUI change would go unnoticed here — which is the
  same standing as every WebKit oracle claim this project makes between corpus regenerations.

---

## 7. Not in scope, named rather than left open

- **`display: contents`** (§3) — the only way to have a styled *and* layout-transparent box.
  Engine work, needs fixtures and goldens.
- **A `.id()` modifier on `Component`** (§4.1) — needs either a layout node or a second
  identity level; the defaulted property is the spelling that cannot be wrong.
- **Distributing `Decoration`- and `Handlers`-backed modifiers** (`background`, `onClick`,
  `focusable`, `keyContext`). §5 records why `setStyle` cannot reach them: they are per-element
  state registered in each `StyledElement`'s own `prepaint`, with no per-node table. Closing
  it needs either a per-node decoration/handler registry or the `ElementGroup` per-child
  operation §3 rejected — a named mechanism, not a mystery, and larger than this spec.
- **`Deferred` and `List` reject a `Component` outright — five of seven
  containers take one, and these two are the exceptions.** Both are generic over
  `Content: Element`, not `Content: ElementGroup`, so a component fails to
  typecheck at the call site. **Verified with `swiftc -typecheck` against a
  plain-import fixture, in the fix wave**, and the diagnostics are the whole of
  the evidence:

  ```
  Deferred { MyComponent() }
      → generic struct 'Deferred' requires that 'MyComponent' conform to 'Element'
  List(items, rowHeight: Pixels(20)) { _ in MyRowComponent() }
      → generic struct 'List' requires that 'MyRowComponent' conform to 'Element'
  ```

  `Box`, `Column`, `Row`, `Stack` and `ScrollView` all take `Content:
  ElementGroup` and accept a component — also verified, in one fixture that
  typechecks clean. That the two exceptions are a **portal** and the
  **data-driven list** is the part that stings: a reusable row is exactly what
  an author reaches for a component to write.

  **The two halves are NOT the same size, which is why this is documented now
  and fixed later.** `List`'s constraint looks like one word — relax `Row:
  Element` to `Row: ElementGroup` — and its row builder's result already flows
  into a wrapping `Box` whose own `Content` is an `ElementGroup`
  (`Box(style: rowStyle, content: { row(datum) })`, `List.swift`), so there is
  a plausible target for the relaxation to land on. `Deferred` is a real design
  question: it returns `nodes[0]` (`Deferred.swift`), justified by a comment
  that says a single `Element` "always hands back exactly one node",
  and a component contributes **zero or many** nodes, so relaxing its
  constraint forces a decision about what a portal does with N nodes (hoist
  each? synthesize a container and stop being layout-transparent? reject
  empty?). Neither is a fix-wave edit, and `Deferred`'s is not a one-word one
  in any milestone.

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
| An author writes a component expecting `.padding()` to pad the component as a unit | It pads each top-level child instead — SwiftUI's behaviour, measured (§5). For a single-child component the two are indistinguishable; for a multi-child one they differ visibly. §5 states it; nothing enforces it |
| **A caller's modifier silently OVERWRITES the component's own internal sizing** | **Measured in the fix wave**, on a component whose author wrote `.width(30)` on child `a` and `.width(50)` on child `b`, in a 300x40 `Row`: bare gives `a: 30.0, b: 50.0`; `.width(70)` on the component gives `a: 70.0, b: 70.0`. `amend` is `var style = pass.style(node); amend(&style); pass.setStyle(node, style)` and every `amend` is a plain `=` on one field, so a caller reaches *through* the component. **Inherent to the design, not a defect**: SwiftUI's `.frame()` composes by *nesting*, and distribution has no node to nest with — it amends the same node the component's author styled. Sharper than the row above, which is about *which* boxes a modifier reaches; this is about a component's internal layout being publicly overwritable, with nothing signalling it. Stated at `StyledComponent`'s doc |
| **`.padding()` on a component whose content is a bare LEAF is completely inert** | **Measured in the fix wave**: `Component { Text("Hi") }.padding(20)` moves a following marker leaf's `x` not at all — **13.0 bare, 13.0 padded** — where the same modifier on a component of `Box`-backed children moves it (80.0 → 90.0). Not a defect of this spec: it is CLAUDE.md's standing inert row — `Style.padding`/`border`/`margin` on a leaf is ignored entirely, since `measureNode` returns a leaf's measure result unchanged and `contentBox` runs only on a node with children — **composing** with distribution. Each is documented alone and together they are silent, which is the recurring lesson: a feature that works alone and a feature that works alone can be wrong together. **The exposure is the worst case available**: a single-`Text` component is the most likely first component anyone writes, and `padding` is the modifier §5 leads with. Recorded at the leaf row in CLAUDE.md's inert table as a second way to meet it |
| An author reaches for `.background()` on a component and finds it absent | Deliberate (§5's limit): `Decoration` has no per-node table for `setStyle` to amend, and offering it with wrapping semantics beside a distributing `.padding()` would be two modifiers that read alike and behave differently. The remedy is an explicit `Box`, which is honest about introducing a container |
| `Content: ElementGroup` lets a component return a group where a single element was meant, and a caller cannot tell from the type | True, and it is the same latitude `Box`'s content already has. The alternative forbids two children |
| The SwiftUI-flattening claim is wrong | Then this is a divergence, and §2 says so in advance rather than presenting the claim as settled. The label is available |
| `StateBinder.bind`'s per-instance `Mirror` walk now runs for components too | ~2.3 us per *stateful* element per frame (CLAUDE.md); a component with no `@State` costs a dictionary hit against an empty array. Unchanged in kind from any other element |
| A future `StyledElement` conformance is added to `Component` for convenience | It would silently make every existing component layout-opaque and move every rect in every tree using one. §3 records why it was refused; this row is what a reader finds if they try |
