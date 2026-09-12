/// The user-facing element surface (design spec §4.2): an author writes
/// `content` and gets a working element.
///
/// **A `Component` is TRANSPARENT to layout and OPAQUE to identity**, and those
/// are separate axes in this framework. Every other element is opaque to both —
/// a `Box` consumes one cursor index *and* contributes one layout node.
///
/// - **Layout-transparent**: a component contributes **no layout node of its
///   own**; its content's nodes pass through to its parent unchanged. So
///   `Column { MyRow(); MyRow() }` lays the rows' children out as the
///   `Column`'s own children. **That is SwiftUI's shape, and it is MEASURED
///   rather than derived** (spec §2's "Why this is SwiftUI's shape" and §5) —
///   two throwaway probes outside this repo, because there is no SwiftUI test
///   target in it. A `Layout` conformer's `subviews.count` reads **2** for an
///   inline pair (the control), **2** for `Group { A; B }`, **2** for a custom
///   view whose body is two views, and **4** for two such views: a custom
///   `View` contributes no layout container. And `.padding()` **distributes**
///   rather than wrapping — `MyRow().padding(8)`, where `MyRow`'s body is a
///   30x10 and a 50x10, measures **120x26**, i.e. `(30+16) + 8 + (50+16)`,
///   bit-identical to `Group { A; B }.padding(8)`; a wrapping implementation
///   predicts 96-104.
///
///   **An earlier version of this comment said the opposite** — that the
///   SwiftUI claim was "DERIVED … and is not measured here", and that
///   `.padding()` "introduces a layer by wrapping the view in
///   `ModifiedContent`". Both halves were refuted by this branch's own probes
///   and the design was rewritten mid-execution because of them (spec §5's own
///   heading records it). The correction is stated at this line rather than
///   only in the spec, per the practices doc's first record-mechanism: a
///   measurement recorded in a report is not a measurement applied to the
///   source.
/// - **Identity-opaque**: a component consumes one cursor index and its content
///   nests beneath the component's own `GlobalElementID`. **This is not a
///   choice.** `@State` slots are `.named("$state\(n)")` children of the
///   element's own id (`StateBinder.bind`), so a component with no id of its
///   own could not hold state — and holding state is the main reason to write a
///   component rather than a function returning elements. **The cursor
///   arithmetic that gives a component that id IS pinned, in
///   `ComponentTests.swift` — the same file that pins layout transparency**,
///   which is where a reader of this comment should look and nowhere else.
///   `cursor += 1`, threading a fresh `innerCursor` rather than the outer
///   `cursor`, and `content` being materialized once rather than re-evaluated
///   in `prepaintGroup` each have a mutation recorded at their own line below,
///   and each reddens a named test in that file
///   (`twoSiblingComponentsHoldIndependentState`,
///   `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt`,
///   `contentIsMaterializedExactlyOncePerFrame` among them).
///
///   **An earlier version of this sentence said this file's tests "do not pin
///   the cursor arithmetic" and then sent the reader to "Task 2's
///   `ComponentTests` additions"** — which landed in that same file, fifteen
///   lines below what the reader was already looking at. A pointer to
///   elsewhere for coverage that is here is worse than no pointer.
///
/// **No `StyledElement` conformance, deliberately** (spec §3). A `Style` must
/// attach to a layout node, and `Style.display` defaults to `.flex` with no
/// `contents` case in the engine — so conforming would force a component to
/// contribute a real flex container and make it layout-opaque, which is the
/// exact divergence this design exists to avoid. Modifiers distribute instead —
/// see `StyledComponent` below.
///
/// **No `.id()` modifier**, for the same reason: that method lives on
/// `StyledElement`. An author who needs a stable name declares the property:
///
/// ```swift
/// struct Row: Component {
///     let item: Item
///     var elementID: ElementID? { ElementID(String(describing: item.id)) }
///     var content: some ElementGroup { … }
/// }
/// ```
public protocol Component: ElementGroup {
    associatedtype Content: ElementGroup

    @ElementBuilder var content: Content { get }

    /// The component's local name among its siblings, or `nil` to be identified
    /// by **position**. Same contract as `Element.elementID`: a name replaces a
    /// position, so a named component keeps its state through a reorder.
    var elementID: ElementID? { get }
}

/// What a `Component`'s `requestGroupLayout` hands to the later phases.
///
/// `content` is stored because the protocol's `content` is **computed**:
/// re-evaluating it in `prepaintGroup` would build fresh element structs and
/// discard whatever `requestGroupLayout` wrote into them. Design spec §4.2's
/// "materializes `content` once" is this field.
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
        // The component's own identity level. `child(of:at:name:)` decides
        // whether that is a `.named` component or a `.positional` one — the
        // name-replaces-position rule lives in the constructor, not here.
        let id = GlobalElementID.child(of: parent, at: cursor, name: elementID)

        // Binds the COMPONENT's own `@State`. Nothing else does this for a
        // component: `Element`'s default `requestGroupLayout` is not reached,
        // because a `Component` is not an `Element`.
        //
        // MUTATION (Task 2 Step 4, first mutation — RE-TAKEN fix round 2
        // against the full 806-test file, after Task 3 added
        // `StyledComponent`/`addingAModifierDoesNotResetAComponentsState`):
        // deleting this call reddens **9 issues across 5 tests** —
        // `aComponentsOwnStateSurvivesAcrossFrames`,
        // `twoSiblingComponentsHoldIndependentState`,
        // `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`,
        // `anEmptyComponentStillHoldsItsOwnState` and (new since the last
        // count) `addingAModifierDoesNotResetAComponentsState` — all read
        // back **0** where they expect 3 (or 1), not the brief's predicted
        // `[1, 1, 1]`, because an unbound `@State`'s writes are discarded
        // outright (`anUnboundStateReturnsItsInitialValueAndDiscardsWrites`,
        // `StateTests.swift`), not merely un-persisted.
        // `stateInsideAComponentsContentIsAlsoSeeded`,
        // `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt`
        // and `contentIsMaterializedExactlyOncePerFrame` stay green — the
        // discriminating result this mutation exists to produce. (Fix round
        // 1's earlier count — 5 issues across 4 tests, on the then-801-test
        // file — was correct for that file and is superseded here, not
        // wrong; `StyledComponent` did not exist yet.)
        StateBinder.bind(self, table: pass.frame.stateTable, id: id)

        // One index from the PARENT's cursor, and a fresh cursor for the
        // content. Threading the outer cursor into the content instead would
        // NOT collide two components' ids — `GlobalElementID.child(of:at:name:)`
        // nests content under the COMPONENT's OWN id regardless, so the
        // numbers stay unique even when threaded. What it destroys is
        // STABILITY: with a fresh `innerCursor`, a component's content is
        // always numbered from 0 *within that component*, so its ids depend
        // on nothing outside it; with the outer cursor threaded through, the
        // content's ids depend on how many siblings preceded the component —
        // so inserting a sibling *before* a NAMED component shifts its
        // content's ids and resets its content's state, defeating the entire
        // purpose of naming it. Pinned by
        // `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt`.
        //
        // MUTATION (Task 2 Step 5, fix round 1): dropping `var innerCursor = 0`
        // and threading `&cursor` into the content call below instead reddens
        // **exactly** `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt`
        // (1 issue on the full 802-test suite, both filtered and unfiltered) —
        // `withSibling.content.second.inner.count` reads **1**, not 2: the
        // named component's content is renumbered by the sibling declared
        // before it and its state resets rather than continuing. The first
        // version of this comment (before this test existed) reported the
        // mutation as reddening nothing at all on the then-801-test suite,
        // including two extra probes (`twoSiblingComponentsHoldIndependentState`
        // with a real cursor-consuming content leaf, and a comparison against
        // `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`)
        // that also stayed green — correctly, since neither reads a NAMED
        // component's CONTENT state across an inserted-sibling render, which
        // is the one shape that can see this. That silence was a real
        // coverage gap in the fixtures, not evidence the line is dead.
        //
        // RE-VERIFIED (fix round 2), against the full 806-test file, after
        // Task 3 added `StyledComponent` and its own tests: still **exactly
        // 1 issue**, the same test, the same reading (`1`, not 2). This
        // comment did not need correcting — it is recorded as re-checked
        // rather than left unremarked, since fix round 2 re-took the whole
        // table rather than assuming any one row still held.
        //
        // MUTATION (Task 2 Step 6): dropping this line reddens **4 issues**
        // on the full 801-test suite — `twoSiblingComponentsHoldIndependentState`
        // (both siblings COLLIDE onto one slot: `tree.content.first.count`
        // and `.second.count` both read **6**, i.e. both writes land in the
        // same entry and both siblings see every increment) and the UNNAMED
        // half of `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`
        // (`pair.content.first.count`/`.second.count` both read **4**, the
        // same collision one level deeper — position 0 and 1 no longer
        // differ). The NAMED half of that same test stays green, as
        // expected: a name replaces a position rather than depending on
        // `cursor`'s value at all. **This is a DIFFERENT set of failing
        // tests than Step 5's** (which reddened nothing), so the two
        // mutations are not equivalent — dropping `cursor += 1` is what
        // actually collides siblings; sharing the counter with content alone
        // does not, on any fixture in this file.
        //
        // RE-VERIFIED (fix round 2), against the full 806-test file: still
        // **exactly 4 issues**, the same two tests
        // (`twoSiblingComponentsHoldIndependentState` and the unnamed half of
        // `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`),
        // the same readings. `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt`
        // and `addingAModifierDoesNotResetAComponentsState` both stay green
        // under this mutation. Recorded as re-checked, not left unremarked.
        cursor += 1
        var materialized = content
        var innerCursor = 0
        // `requestGroupLayout`, never `requestLayout` — this is what reaches
        // `StateBinder.bind` for every element inside `content`. Calling
        // `requestLayout` directly is the live `AnyElement` defect in
        // CLAUDE.md's declared-but-inert table: `@State` returns its initial
        // value forever, with NO diagnostic, because nothing ever seeds its
        // box.
        // MUTATION (Task 2 Step 4, second mutation — RE-TAKEN fix round 2
        // against the full 806-test file): calling this recursive step
        // TWICE on `materialized` (discarding the first call, resetting
        // `innerCursor`, then calling again) — the smallest edit available
        // that isolates the content-path binding from the component's own
        // `StateBinder.bind` above without re-evaluating `content` a second
        // time (re-evaluating `content` itself would ALSO double-increment
        // `Counter`'s own `@State`, since this file's `Counter.content`
        // getter is where that increment lives — see `Counter`'s doc — which
        // would wrongly redden `aComponentsOwnStateSurvivesAcrossFrames` too
        // and fail to discriminate the two mechanisms) reddens **6 issues
        // across 5 tests**: `stateInsideAComponentsContentIsAlsoSeeded`
        // (reads **6**, not 3 — each of `Wrapper`'s content elements is bound
        // and incremented twice per frame),
        // `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt`
        // (reads **4**, not 2 — the fix-round-1 test is ALSO sensitive to
        // this line, which fix round 1's own comment did not check; that was
        // the staleness fix round 2 corrects) and three PRE-EXISTING
        // layout-transparency tests that use a component whose content holds
        // real leaves (`aComponentsContentFlattensIntoItsParent`,
        // `aComponentContributesNoLayoutNodeOfItsOwn`,
        // `aComponentInsideAComponentFlattensThroughBothLevels` — 5 nodes
        // registered against an expected 3, doubled `registered` logs).
        // `aComponentsOwnStateSurvivesAcrossFrames`,
        // `twoSiblingComponentsHoldIndependentState`,
        // `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`,
        // `anEmptyComponentStillHoldsItsOwnState`,
        // `contentIsMaterializedExactlyOncePerFrame` and
        // `addingAModifierDoesNotResetAComponentsState` all stay green —
        // `Counter`'s own `content` is `EmptyGroup()`, so nothing here can
        // touch its own state regardless of how this recursive call is
        // mutated, which is exactly the discriminating property Step 4 asks
        // for. (Fix round 1's earlier count — 5 issues across 4 tests — did
        // not include the test fix round 1 itself had just added; see that
        // test's own doc and the practices doc's third record-mechanism,
        // "staleness is systematic, not local".)
        let (nodes, contentLayout) =
            materialized.requestGroupLayout(under: id, at: &innerCursor, pass: &pass)

        // `nodes` returned UNCHANGED — this is layout transparency. Wrapping
        // them, or replacing them with a node of the component's own, is what
        // makes a component layout-opaque.
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

/// A component with a `Style` amendment applied to each of its top-level nodes.
///
/// **Modifiers on a `Component` DISTRIBUTE rather than wrap, and that is
/// measured** (spec §5). SwiftUI's `MyRow().padding(8)`, where `MyRow`'s body is
/// a 30x10 and a 50x10 view, measures 120x26 — `(30+16) + 8 + (50+16)`, each
/// child padded — bit-identical to `Group { A; B }.padding(8)`. A wrapping
/// implementation predicts 96-104. The two are one mechanism with §2's
/// transparency: `MyRow()` IS its children, so a modifier applied to it applies
/// to each of them, because there is no single thing to wrap.
///
/// This type contributes **no layout node of its own** — it returns the
/// component's nodes unchanged, having amended their styles — so a modified
/// component is exactly as layout-transparent as a bare one.
///
/// **It also mints no identity of its own.** `requestGroupLayout` forwards the
/// `parent` and `cursor` it was given straight through to `component`
/// unchanged, so `MyComponent()` and `MyComponent().padding(4)` produce the
/// *identical* `GlobalElementID` for `MyComponent` — a modifier is not a level
/// in the tree. Getting this wrong (mint an id here, pass it down as the
/// component's parent) silently resets the component's `@State`, because its
/// slot id is a child of whatever id `StateBinder.bind` was called with.
/// `addingAModifierDoesNotResetAComponentsState` (`ComponentTests.swift`) pins
/// it, and Step 8's mutation reddens exactly that test.
///
/// **A CALLER'S MODIFIER OVERWRITES THE COMPONENT'S OWN LAYOUT, silently, and
/// this is inherent to the design rather than a defect.** `amend` runs
/// `var style = pass.style(node); amend(&style); pass.setStyle(node, style)`,
/// and every `amend` this file declares is a plain `=` on one `Style` field —
/// so a caller reaches *through* the component and obliterates whatever the
/// component's author wrote on that same field. **Measured** on a component
/// whose author declared `.width(30)` on child `a` and `.width(50)` on child
/// `b`, rendered in a 300x40 `Row`:
///
/// ```
/// bare          a: 30.0   b: 50.0
/// .width(70)    a: 70.0   b: 70.0
/// ```
///
/// SwiftUI has no equivalent because its `.frame()` composes by **nesting** —
/// the caller's frame wraps the body's. There is no node here to nest with:
/// distribution amends the child's own node, which is the same node the
/// component's author styled. Nothing signals the collision and nothing can,
/// short of a merge policy that would then disagree with `StyledElement`'s own
/// `modifying` (`Box.swift`), which assigns rather than merges. Recorded in
/// the component spec's §9 risk table as well.
///
/// **`padding` on a component whose content is a bare LEAF is completely
/// inert** — measured, `Component { Text("Hi") }.padding(20)` moves a following
/// marker leaf's `x` not at all (**13.0 bare, 13.0 padded**), where the same
/// modifier on a component of `Box`-backed children moves it (80.0 → 90.0).
/// That is not this type failing: it is CLAUDE.md's standing inert row —
/// `Style.padding`/`border`/`margin` on a leaf is ignored entirely, since
/// `measureNode` returns a leaf's measure result unchanged — composing with
/// distribution. Each is documented alone and together they are silent, and a
/// single-`Text` component is the most likely first component anyone writes.
///
/// **A CALLER'S MODIFIER ON A COMPONENT NEVER ANIMATES. It snaps, even inside
/// `withAnimation`.** This is a defect (review finding B-7), not a design
/// choice, and it is pinned wrong on purpose. `requestGroupLayout` below runs
/// `amend` and `pass.setStyle` only after `component.requestGroupLayout` has
/// returned. By then each member element has already called
/// `animated(_:_:for:pass:)` and stored its `$anim` baseline, so the baseline
/// never holds the caller's value, and `setStyle` overwrites the interpolated
/// result with the raw target on every frame.
///
/// Measured with `.linear(duration: 1)` and `.width(196)` changed to
/// `.width(320)`, together with `.height(40)` to `.height(80)` and
/// `.padding(4)` to `.padding(20)`: the node reads (320, 80, 20) at t = 0 and
/// again at t = 0.5, where (196, 40, 4) and then (258, 60, 12) are correct.
/// The same width declared inside the component animates, 196 then 258. This
/// is not the `.auto` snap: the fixture's member declares pixel sizes.
/// `everyRegisteringSiteAnimatesItsStyle`'s `Component` arm
/// (`AnimationTests.swift`) pins both readings.
///
/// **The fix is blocked on `ElementGroup`, not on this type.**
/// `requestGroupLayout` returns a flat `[LayoutNodeID]`, so nothing here can
/// name a member's id or its `$anim` slot. That needs the associated-type
/// change ruling TB-M names. Two cheaper fixes are unsound. Calling `animated`
/// on the member's slot from here would rewrite its baseline with an empty
/// `Decoration()`, because the member's `Decoration` is out of reach as well.
/// Leaving an amendment on the pass for the next `animated` call would reach a
/// grandchild first, since `Box.requestLayout` registers its children before
/// itself, which contradicts CO-U's distribution to top-level nodes. To animate
/// a component's size today, declare the value inside the component (a stored
/// property its `content` reads) rather than as a modifier on it.
///
/// **Only `Style`-backed modifiers can work this way.** `LayoutTree.setStyle`
/// reaches a node's `Style`; nothing reaches `Decoration` or `Handlers` per
/// node, because those are per-ELEMENT state registered by each
/// `StyledElement`'s own `prepaint`. So `background`, `onClick`, `focusable`
/// and `keyContext` are deliberately **not** offered on a component —
/// `decorationBackedModifiersAreNotOfferedOnAComponent` and the `.background()`
/// typecheck guard in `ErasureCompileGuards.swift` pin the absence.
public struct StyledComponent<C: Component>: ElementGroup {
    var component: C
    var amend: @Sendable (inout Style) -> Void

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], C.GroupLayout) {
        // `parent` and `cursor` forwarded UNCHANGED — see the type's own doc.
        let (nodes, layout) = component.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        for node in nodes {
            var style = pass.style(node)
            amend(&style)
            pass.setStyle(node, style)
        }
        return (nodes, layout)
    }

    public mutating func prepaintGroup(layout: inout C.GroupLayout,
                                       pass: inout PrepaintPass)
        -> C.GroupPrepaint {
        component.prepaintGroup(layout: &layout, pass: &pass)
    }

    public mutating func paintGroup(layout: inout C.GroupLayout,
                                    prepaint: inout C.GroupPrepaint,
                                    pass: inout PaintPass) {
        component.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension Component {
    /// Padding on each top-level child (spec §5). Signature matches
    /// `StyledElement.padding(_ points:)` (`Box.swift:643`) exactly — a
    /// forwarded modifier whose parameter type drifts from its original is
    /// worse than none, because a caller reads the two as the same modifier.
    public func padding(_ points: Pixels) -> StyledComponent<Self> {
        StyledComponent(component: self) { $0.padding = Edges(all: .pixels(points)) }
    }

    /// Matches `StyledElement.width(_ points:)` (`Box.swift:603`).
    public func width(_ points: Pixels) -> StyledComponent<Self> {
        StyledComponent(component: self) { $0.size.width = .length(.pixels(points)) }
    }

    /// Matches `StyledElement.height(_ points:)` (`Box.swift:607`).
    public func height(_ points: Pixels) -> StyledComponent<Self> {
        StyledComponent(component: self) { $0.size.height = .length(.pixels(points)) }
    }
}

/// Fix round 1. `StyledComponent<C>` is an `ElementGroup`, not a `Component`,
/// so the `extension Component { padding / width / height }` above is
/// unreachable on the value any of those three returns — `Leafless().width(10)`
/// has no `.height`, and even `.padding(4).padding(4)` fails to typecheck.
/// Measured with `swiftc -typecheck`:
/// `error: value of type 'StyledComponent<Leafless>' has no member 'height'`.
/// Undetected because no test exercised `width`/`height` at all, nor any
/// two-modifier call — the recurring lesson this project's practices doc
/// names: a feature that works alone and a feature that works alone can be
/// wrong together.
///
/// These three CHAIN onto whatever `amend` this `StyledComponent` already
/// carries, rather than replacing it, so `.padding(4).width(10)` distributes
/// both. **The later call wins where two touch the SAME field** — matched
/// against `StyledElement.modifying` (`Box.swift:293`), which does not merge
/// or accumulate: it assigns the field directly (`$0.padding = newValue`), so
/// a second `.padding(_:)` on a `Box` simply overwrites the first one's value.
/// Composing here by running `previous` first and the new field assignment
/// second reproduces exactly that: the later assignment always lands on top,
/// because Swift closures run in the order given and the field write is a
/// plain `=`, not a merge. **Not accumulation** — `.padding(4).padding(4)`
/// leaves a component padded by 4, not 8; asserted directly by
/// `chainedPaddingReplacesRatherThanAccumulates`.
extension StyledComponent {
    public func padding(_ points: Pixels) -> StyledComponent<C> {
        let previous = amend
        return StyledComponent(component: component) { style in
            previous(&style)
            style.padding = Edges(all: .pixels(points))
        }
    }

    public func width(_ points: Pixels) -> StyledComponent<C> {
        let previous = amend
        return StyledComponent(component: component) { style in
            previous(&style)
            style.size.width = .length(.pixels(points))
        }
    }

    public func height(_ points: Pixels) -> StyledComponent<C> {
        let previous = amend
        return StyledComponent(component: component) { style in
            previous(&style)
            style.size.height = .length(.pixels(points))
        }
    }
}
