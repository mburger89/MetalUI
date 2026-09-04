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
///   `Column`'s own children. That is SwiftUI's shape — a custom `View`
///   contributes no layout container, and `.padding()` introduces a layer by
///   wrapping the view in `ModifiedContent` rather than by attaching to it.
///   **That description of SwiftUI is DERIVED from its documented behaviour and
///   is not measured here**: there is no SwiftUI test target in this repo. If
///   SwiftUI turns out to differ, this is a divergence and the label is
///   available.
/// - **Identity-opaque**: a component consumes one cursor index and its content
///   nests beneath the component's own `GlobalElementID`. **This is not a
///   choice.** `@State` slots are `.named("$state\(n)")` children of the
///   element's own id (`StateBinder.bind`), so a component with no id of its
///   own could not hold state — and holding state is the main reason to write a
///   component rather than a function returning elements. **This file's own
///   tests do not pin the cursor arithmetic that gives a component that id** —
///   `ComponentTests.swift` asserts layout transparency and identity opacity's
///   *geometric* consequence, not the cursor line itself. Task 2's
///   `ComponentTests` additions are where `cursor += 1`, threading `innerCursor`
///   rather than the outer `cursor`, and `content` being materialized once
///   rather than re-evaluated in `prepaintGroup` are each pinned by a mutation
///   that reddens something.
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
