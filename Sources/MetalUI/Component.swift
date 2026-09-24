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
        StateBinder.bind(self, in: pass.frame, id: id)

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

/// One caller's modifier on a `Component`, applied to each of the component's
/// top-level nodes **in the order the modifiers were written** (outer
/// modifiers task, ruling `OM-E`).
///
/// Two kinds, because the legacy path now has two kinds of modifier. `.amend`
/// is distribution as the `Component` milestone measured it (`CO-U`): a size
/// written onto the member node's own `Style`, which is what `width`/`height`
/// still are (`OM-F`). `.wrap` is what `.padding` became when `MC-A` made it a
/// wrapper on the `Element` path: a real legacy node registered around the
/// member, carrying the same `Style` a `ModifierLayer` carries.
///
/// `StyledComponent.requestGroupLayout` walks the list once per member with a
/// "current node": an amend writes the current node, a wrap replaces it. That
/// is what makes `.padding(4).width(70)` (the padded box is 70 wide) and
/// `.width(70).padding(4)` (the member is 70 wide, then padded to 78) differ —
/// `theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities`
/// (stage 7b retired the legacy-only original, record §49 §4 row 218). Keeping an amend set
/// beside a wrap set would collapse those two into one answer.
///
/// **The amend's payload is a `Size<Dimension>`, not a closure, since stage 3
/// lane 4** (ruling `LR-BG`). It was `@Sendable (inout Style) -> Void`, and
/// `width`/`height` were its only writers; the proposal lowering frames a
/// member by its size, so an arbitrary closure would have let a future amend
/// write a field the lowering silently dropped. Making the case unable to
/// express one deletes the hole instead of reporting it, and it is why there
/// is no `component.amend` diagnostic for "an amend wrote something other
/// than a size". Only the axes the patch declares are written: an `.auto` axis
/// leaves the member's own value alone, so `.width(p).height(q)` is two ops
/// that do not fight.
enum ComponentModifierOp {
    /// The size written onto the current node's own `Style`, `.auto` on an axis
    /// the caller did not name. `width`/`height`.
    case amend(Size<Dimension>)
    /// Registers a legacy node with `style` around the current node, which the
    /// new node then replaces. `padding`.
    case wrap(Style)
}

/// A component with a caller's modifiers applied to each of its top-level
/// nodes, in the order written.
///
/// **Modifiers on a `Component` DISTRIBUTE rather than wrap the group, and
/// that is measured** (spec §5; re-measured from source in the outer-modifiers
/// task, probe `docs/probes/swiftui-component-distribution.swift`). SwiftUI's
/// `MyRow().padding(8)`, where `MyRow`'s body is a 30x10 and a 50x10 view,
/// measures 120x26 — `(30+16) + 8 + (50+16)`, each child padded — bit-identical
/// to `Group { A; B }.padding(8)` (arms G2/G3). A wrap around the pair predicts
/// 96-104. The two are one mechanism with §2's transparency: `MyRow()` IS its
/// children, so a modifier applied to it applies to each of them, because
/// there is no single thing to wrap.
///
/// **What "applies to each" means differs per modifier, and `ops` carries the
/// difference** (`ComponentModifierOp`). `.padding` WRAPS each top-level node
/// in a real padding node (`OM-D`) — SwiftUI's box model, so a content-sized
/// `Text` body pads (13x16 → 53x56, G10/G11), a fixed 30x10 body pads to 70x50
/// with the leaf at (20, 20) (G12), and two calls ACCUMULATE (`OM-E`, G4).
/// `width`/`height` still AMEND the member's own `Style` (`OM-F`), which
/// overwrites whatever the member declared — see below. So this type
/// contributes **no node of the component's own** and **one node per member
/// per `.padding`**: a modified component is exactly as layout-transparent as
/// a bare one (`aModifierOnAComponentDistributesToEachTopLevelChild` counted
/// the nodes until stage 7b retired it, record §49 §4 row 207;
/// `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer` counts the ids).
///
/// **It mints no identity of its own.** `requestGroupLayout` forwards the
/// `parent` and `cursor` it was given straight through to `component`
/// unchanged, so `MyComponent()` and `MyComponent().padding(4)` produce the
/// *identical* `GlobalElementID` for `MyComponent` — a modifier is not a level
/// in the tree. Getting this wrong (mint an id here, pass it down as the
/// component's parent) silently resets the component's `@State`, because its
/// slot id is a child of whatever id `StateBinder.bind` was called with.
/// `addingAModifierDoesNotResetAComponentsState` (`ComponentTests.swift`) pins
/// it, and Step 8's mutation reddens exactly that test. The wrapper nodes a
/// `.wrap` registers have no element behind them and no id: they are layout
/// nodes only, painted by nothing, and that is also why they cannot animate
/// (below).
///
/// **A CALLER'S `width`/`height` OVERWRITES THE COMPONENT'S OWN LAYOUT,
/// silently, and this is a recorded divergence rather than a defect** (`OM-F`,
/// owned by plan task 4). `.amend` runs `var style = pass.style(node);
/// amend(&style); pass.setStyle(node, style)`, and every amend this file
/// declares is a plain `=` on one `Style` field — so a caller reaches
/// *through* the component and obliterates whatever the component's author
/// wrote on that same field. **Measured** on a component whose author declared
/// `.width(30)` on child `a` and `.width(50)` on child `b`, rendered in a
/// 300x40 `Row` (`aComponentsWidthStillOverwritesItsMembersDeclaredWidth`,
/// retired by stage 7b, record §49 §4 row 219; divergence 48's pin is now the
/// legacy arm of `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`):
///
/// ```
/// bare          a: 30.0   b: 50.0
/// .width(70)    a: 70.0   b: 70.0
/// ```
///
/// SwiftUI's `.frame(width: 70)` on the same custom view WRAPS each member and
/// keeps it 30 and 50 wide, centred in 70 (probe arms G7/G8). Making
/// `Component.width` wrap is a sizing-semantics change the outer-modifiers
/// task was told not to make; task 4's frame work owns it. Until then, a
/// component's declared sizes belong inside the component.
///
/// **Under the proposal authority that is already SwiftUI's answer** (plan
/// task 7, stage 3, lane 4, `LR-BG`): the amend lowers to one native frame per
/// member, so the same `Pair().width(70)` reads 30 and 50 at x 20 and 80. The
/// two authorities disagree here on purpose until stage 6b switches the root,
/// and `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt` pins
/// both sides as literals.
///
/// **Order is observable, and it is MetalUI's order, not SwiftUI's member
/// geometry.** `.padding(4).width(70)` reads outer 70 with the member 30 wide
/// at the 4 inset; `.width(70).padding(4)` reads outer 78 with the member
/// itself 70 wide. SwiftUI's G15/G16 read the same outer 70/78 but keep the
/// member 30 wide (centred at x 20, then at x 24), because its `.frame` wraps
/// where `width` here amends — `OM-F` again, seen through order.
///
/// **A CALLER'S MODIFIER ON A COMPONENT NEVER ANIMATES. It snaps, even inside
/// `withAnimation`.** This is a defect (review finding B-7), not a design
/// choice, and it is pinned wrong on purpose, on two nodes since lane 4.
/// `.amend` runs `pass.setStyle` only after `component.requestGroupLayout` has
/// returned; by then each member element has already called
/// `animated(_:_:for:pass:)` and stored its `$anim` baseline, so the baseline
/// never holds the caller's value, and `setStyle` overwrites the interpolated
/// result with the raw target on every frame. `.wrap` registers its node under
/// no element id at all, so there is no slot for `animated` to compare against
/// even if it were called.
///
/// Measured with `.linear(duration: 1)` and `.width(196).height(40).padding(4)`
/// changed to `.width(320).height(80).padding(20)`: the member reads (320, 80)
/// and the wrapper's `padding.left` reads 20 at t = 0 and again at t = 0.5,
/// where (196, 40) / 4 and then (258, 60) / 12 are correct. The same width
/// declared inside the component animates, 196 then 258. This is not the
/// `.auto` snap: the fixture's member declares pixel sizes.
/// Those legacy-authority readings were pinned by `everyRegisteringSiteAnimatesItsStyle`,
/// retired at stage 7b (record §49 row 241); the snap under the proposal
/// authority is arm (c) of `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`
/// (`AnimationTests.swift`).
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
/// reaches a node's `Style` and `requestNode` takes one; nothing reaches
/// `Decoration` or `Handlers` per node, because those are per-ELEMENT state
/// registered by each `StyledElement`'s own `prepaint`. So `background`,
/// `onClick`, `focusable`, `keyContext`, and the outer-modifiers task's
/// `border`/`focusBorder`/`opacity`/`clipped`/`contentShape` are deliberately
/// **not** offered on a component —
/// `decorationBackedModifiersAreNotOfferedOnAComponent` and the `.background()`
/// typecheck guard in `ErasureCompileGuards.swift` pin the absence. The side
/// door stays open: `anyComponent.frame(...)` returns a `ModifiedElement`, so
/// `.frame(…).opacity(…).clipped().border(…)` compiles on any component and
/// scopes its members without distributing (measured at integration; under the
/// proposal authority,
/// `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembersUnderTheProposalAuthority`).
///
/// **Ops reach node-contributing members only.** `requestGroupLayout` maps them
/// over the nodes the body returned, so a member that contributes none (a
/// `Deferred`, a false `if`) receives no wrapper and no amend: its `.padding`
/// is dropped, as the old amend dropped it (by reading, unpinned; SwiftUI
/// unprobed).
///
/// **On a proposal body every op traps** (`OM-Z`, closing `MC-G` hole 5): an
/// amend reaches `LayoutTree.setStyle`, which refuses a native node, and a
/// wrap reaches `LayoutTree.newNode`, which refuses a native child — both
/// ruling SA-G's own preconditions, no new one. Pinned by
/// `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration` and
/// `aPaddingModifierOnAProposalComponentTraps`
/// (`NativeBoundaryIntegrationTests.swift`). **That is the legacy authority's
/// answer, and it is the only one that traps.** Under the proposal authority
/// (plan task 7) both ops LOWER since stage 3's lane 4 (`LR-BG`): an amend
/// registers one native frame per member and a wrap goes through
/// `lowerLegacyNode` at site `component`, so a component over proposal content
/// builds cleanly and neither op reports anything (`LR-BO`). Pinned by
/// `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority` — whose
/// component half is now an agreement arm — and by
/// `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s two `Component`
/// arms, which assert the absence of an entry. The lowering's own geometry is
/// `LoweringComponentTests.swift`.
public struct StyledComponent<C: Component>: ElementGroup {
    var component: C
    /// In declaration order. `Component.padding/width/height` start the list
    /// with one op; `StyledComponent`'s three append.
    var ops: [ComponentModifierOp]

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], C.GroupLayout) {
        // `parent` and `cursor` forwarded UNCHANGED — see the type's own doc.
        let (nodes, layout) = component.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        // Per member, in declaration order, with a current node: an amend
        // writes it, a wrap replaces it. The parent receives the OUTERMOST
        // node of each member — which is the member itself when no op wrapped.
        let outermost = nodes.map { member -> LayoutNodeID in
            var current = member
            for op in ops {
                switch op {
                case .amend(let patch):
                    // Each op branches on the authority itself (plan task 7,
                    // ruling LR-C). Stage 3 lane 4 LOWERS both (LR-BG): an amend
                    // that overwrote the member's `Style` becomes one native
                    // frame AROUND it — SwiftUI's answer to divergence 48 — and
                    // so it REPLACES `current` on this path where it left it
                    // alone on the legacy one. Neither reports any more.
                    if pass.lowersToProposal {
                        current = pass.loweredComponentFrame(current, patch)
                    } else {
                        var style = pass.style(current)
                        // Only the axes the patch declares: an `.auto` axis is
                        // "not named", not "reset to auto", or `.width(p)` then
                        // `.height(q)` would undo each other.
                        if patch.width != .auto { style.size.width = patch.width }
                        if patch.height != .auto { style.size.height = patch.height }
                        pass.setStyle(current, style)
                    }
                case .wrap(let style):
                    // A `.padding` wrapper is an ordinary one-child legacy
                    // container, so it lowers through the container lowering at
                    // its own site (LR-BG; prototype arm C3 agrees with the
                    // legacy engine in every observation).
                    current = pass.lowersToProposal
                        ? pass.lowerLegacyNode(style, declared: style, children: [current],
                                               site: .component)
                        : pass.frame.requestNode(style: style, children: [current])
                }
            }
            return current
        }
        return (outermost, layout)
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

/// The amend patch `Component.width`/`StyledComponent.width` carries: the
/// declared axis, and `.auto` on the other — "not named", which neither the
/// legacy write nor the lowered frame touches (`LR-BG`).
private func componentWidth(_ points: Pixels) -> Size<Dimension> {
    Size(width: .length(.pixels(points)), height: .auto)
}

/// The amend patch `Component.height`/`StyledComponent.height` carries.
private func componentHeight(_ points: Pixels) -> Size<Dimension> {
    Size(width: .auto, height: .length(.pixels(points)))
}

/// The `Style` a padding wrapper carries: the same one `StyledElement.padding`
/// gives a `ModifierLayer` (`Box.swift`), so the two paths share one box
/// model — an `auto`-sized legacy node whose only `Style` field is `padding`.
private func paddingWrapperStyle(_ points: Pixels) -> Style {
    var style = Style()
    style.padding = Edges(all: .pixels(points))
    return style
}

extension Component {
    /// Padding around each top-level node (`OM-D`). Signature matches
    /// `StyledElement.padding(_ points:)` (`Box.swift`) exactly — a forwarded
    /// modifier whose parameter type drifts from its original is worse than
    /// none, because a caller reads the two as the same modifier — and so does
    /// the mechanism: one wrapper node per call, accumulating.
    public func padding(_ points: Pixels) -> StyledComponent<Self> {
        StyledComponent(component: self, ops: [.wrap(paddingWrapperStyle(points))])
    }

    /// Matches `StyledElement.width(_ points:)` (`Box.swift`). An amend of each
    /// member's own width (`OM-F`).
    ///
    /// **Not deprecated, though the `StyledElement` modifier it matches is**
    /// (plan task 7, stage 8, ruling `LR-ER` item 2): this one does not write
    /// an element's own box or return `Self`; under the proposal authority it
    /// already lowers to one native frame per member (`LR-BG` — SwiftUI's
    /// answer, component distribution probe G7/G8); and `Component.frame` over
    /// several members is a horizontal row (`LR-BH`), so it is not a rename
    /// target. Its reconciliation with `.frame` is stage 11's.
    public func width(_ points: Pixels) -> StyledComponent<Self> {
        StyledComponent(component: self, ops: [.amend(componentWidth(points))])
    }

    /// Matches `StyledElement.height(_ points:)` (`Box.swift`). An amend of
    /// each member's own height (`OM-F`).
    ///
    /// **Not deprecated, though the `StyledElement` modifier it matches is**
    /// (plan task 7, stage 8, ruling `LR-ER` item 2): this one does not write
    /// an element's own box or return `Self`; under the proposal authority it
    /// already lowers to one native frame per member (`LR-BG` — SwiftUI's
    /// answer, component distribution probe G7/G8); and `Component.frame` over
    /// several members is a horizontal row (`LR-BH`), so it is not a rename
    /// target. Its reconciliation with `.frame` is stage 11's.
    public func height(_ points: Pixels) -> StyledComponent<Self> {
        StyledComponent(component: self, ops: [.amend(componentHeight(points))])
    }
}

/// `StyledComponent<C>` is an `ElementGroup`, not a `Component`, so the
/// `extension Component { padding / width / height }` above is unreachable on
/// the value any of those three returns — `Leafless().width(10)` had no
/// `.height` until these were added (the Component milestone's fix round 1,
/// found with `swiftc -typecheck`: `error: value of type
/// 'StyledComponent<Leafless>' has no member 'height'`).
///
/// These three APPEND to `ops`, so `.padding(4).width(10)` and
/// `.width(10).padding(4)` are different lists and lay out differently
/// (`OM-E`). Two `width`s on one member still resolve as `StyledElement.modifying`
/// does — the later assignment lands on top, a plain `=` — while two
/// `padding`s are two wrappers and ACCUMULATE
/// (`chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement`, retired by
/// stage 7b, record §49 §4 row 215). An earlier
/// version of this comment said "not accumulation — `.padding(4).padding(4)`
/// leaves a component padded by 4", which was true of the amend it described
/// and is inverted by `OM-D` on probe evidence (G4, E1–E3).
///
/// `width`/`height` here are **not deprecated**, though the `StyledElement`
/// modifiers of the same names are since plan task 7's stage 8 — for the
/// reason `Component.width(_:)` gives (ruling `LR-ER` item 2; stage 11's).
extension StyledComponent {
    public func padding(_ points: Pixels) -> StyledComponent<C> {
        StyledComponent(component: component, ops: ops + [.wrap(paddingWrapperStyle(points))])
    }

    public func width(_ points: Pixels) -> StyledComponent<C> {
        StyledComponent(component: component, ops: ops + [.amend(componentWidth(points))])
    }

    public func height(_ points: Pixels) -> StyledComponent<C> {
        StyledComponent(component: component, ops: ops + [.amend(componentHeight(points))])
    }
}
