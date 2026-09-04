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
/// exact divergence this design exists to avoid. Modifiers wrap instead; see
/// the extension below.
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
        // MUTATION (Task 2 Step 4, first mutation): deleting this call
        // reddens 5 of `ComponentTests`' 8 issues on the full 801-test suite —
        // `aComponentsOwnStateSurvivesAcrossFrames`,
        // `twoSiblingComponentsHoldIndependentState`,
        // `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`
        // and `anEmptyComponentStillHoldsItsOwnState` all read back **0**
        // where they expect 3 (or 1) — not the brief's predicted `[1, 1, 1]`,
        // because an unbound `@State`'s writes are discarded outright
        // (`anUnboundStateReturnsItsInitialValueAndDiscardsWrites`,
        // `StateTests.swift`), not merely un-persisted. `stateInsideAComponentsContentIsAlsoSeeded`
        // and `contentIsMaterializedExactlyOncePerFrame` stay green — the
        // discriminating result this mutation exists to produce.
        StateBinder.bind(self, table: pass.frame.stateTable, id: id)

        // One index from the PARENT's cursor, and a fresh cursor for the
        // content. Threading the outer cursor into the content instead would
        // give the content its siblings' positions and silently collide their
        // state.
        //
        // MUTATION (Task 2 Step 5): dropping `var innerCursor = 0` and
        // threading `&cursor` into the content call below instead reddened
        // **nothing** — full 801-test suite, 0 issues, run twice. Measured,
        // not predicted, and it is `twoSiblingComponentsHoldIndependentState`
        // itself that cannot see it (ruling `MP-J`'s shape): that test
        // renders ONE fixed tree shape three times against one `StateTable`,
        // and a component's own id is computed from `cursor` **before**
        // `content` ever runs, so sharing the counter with content only
        // shifts every later sibling's id by a constant that is identical on
        // every one of the three frames — self-consistent, not colliding.
        // Confirmed by two further probes, both still green: giving
        // `Counter.content` an actual cursor-consuming leaf instead of
        // `EmptyGroup()` (so the shared cursor is genuinely read, not just
        // ignored — `EmptyGroup.requestGroupLayout` provably never touches
        // its `cursor` argument at all, so the unmodified fixture's green
        // result was guaranteed rather than merely unlucky), and comparing
        // against `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`'s
        // own two-DIFFERENT-tree-shapes-one-table pattern, which is the shape
        // that would be needed to observe a real collision and which no test
        // in this file runs against `TwoLeaves`/`Counter` together. This is
        // the fixture-cannot-express-the-defect finding the brief names as a
        // live possibility, reported rather than forced.
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
        cursor += 1
        var materialized = content
        var innerCursor = 0
        // `requestGroupLayout`, never `requestLayout` — this is what reaches
        // `StateBinder.bind` for every element inside `content`. Calling
        // `requestLayout` directly is the live `AnyElement` defect in
        // CLAUDE.md's declared-but-inert table: `@State` returns its initial
        // value forever, with NO diagnostic, because nothing ever seeds its
        // box.
        // MUTATION (Task 2 Step 4, second mutation): calling this recursive
        // step TWICE on `materialized` (discarding the first call, resetting
        // `innerCursor`, then calling again) — the smallest edit available
        // that isolates the content-path binding from the component's own
        // `StateBinder.bind` above without re-evaluating `content` a second
        // time (re-evaluating `content` itself would ALSO double-increment
        // `Counter`'s own `@State`, since this file's `Counter.content`
        // getter is where that increment lives — see `Counter`'s doc — which
        // would wrongly redden `aComponentsOwnStateSurvivesAcrossFrames` too
        // and fail to discriminate the two mechanisms) reddens exactly
        // `stateInsideAComponentsContentIsAlsoSeeded` (reads **6**, not 3 —
        // each of `Wrapper`'s content elements is bound and incremented
        // twice per frame) plus three PRE-EXISTING layout-transparency tests
        // that also use a component whose content holds real leaves
        // (`aComponentsContentFlattensIntoItsParent`,
        // `aComponentContributesNoLayoutNodeOfItsOwn`,
        // `aComponentInsideAComponentFlattensThroughBothLevels` — 5 nodes
        // registered against an expected 3, doubled `registered` logs).
        // `aComponentsOwnStateSurvivesAcrossFrames`,
        // `twoSiblingComponentsHoldIndependentState`,
        // `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`,
        // `anEmptyComponentStillHoldsItsOwnState` and
        // `contentIsMaterializedExactlyOncePerFrame` all stay green — `Counter`'s
        // own `content` is `EmptyGroup()`, so nothing here can touch its own
        // state regardless of how this recursive call is mutated, which is
        // exactly the discriminating property Step 4 asks for.
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
