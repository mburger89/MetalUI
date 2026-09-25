import MetalUICore
import MetalUILayout

// The *children* half of the element pipeline, and the thing that makes §4.6's
// first allocation mitigation true rather than aspirational.
//
// **Why `Element` alone is not enough.** `Element.requestLayout` returns exactly
// one `LayoutNodeID`. A container's children are N nodes, so the builder's
// product cannot be an `Element` without inventing a wrapper node — and a
// wrapper node is not neutral: it is a flex container in its own right, so
// `Column { a; b }` would lay out as a column containing a *row* containing `a`
// and `b`. The children of a container therefore need a type that contributes a
// **list** of nodes, which is what `ElementGroup` is.
//
// `Element` refines it, so any element is a group of one and
// `Column { Label(…); Button(…) }` really does build `Column<Pair<Label,
// Button>>` — the type the spec names, with no wrapper in between and nothing
// boxed. `AnyElement` conforms too (below), so a genuinely dynamic child list
// remains expressible without making erasure the default path.
//
// **The alternative that was rejected**: `buildExpression` wrapping every
// element in a `Solo<E>` group, leaving `Element` untouched. It works, but the
// spec writes `Column<Pair<Label, Button>>` and that spelling is load-bearing
// documentation — a reader who greps for it should find it.

/// A list of elements contributing zero or more layout nodes to one container.
///
/// The three phases mirror `Element`'s and are threaded the same way. They take
/// the **container's** identity and derive each child's from it with
/// `GlobalElementID.child(of:at:name:)`. Identity is now **structural and
/// universal** (§4.3): a member with no `.id()` takes its position in the
/// group's flat index space, so an unnamed container no longer stops identity
/// below it. `.id()` replaces that position rather than creating the identity.
///
/// **Only `requestGroupLayout` carries the cursor**, because it is the only
/// phase that derives an identity. `prepaintGroup` and `paintGroup` read the id
/// each member *stored* during layout, deliberately, so all three phases see the
/// same path even if the element's `elementID` changes between them.
///
/// Unlike `Element`'s phases, these are handed no `Bounds`: a group's members
/// have N different rects, so each looks its own up from the node it stashed
/// during layout.
@MainActor
public protocol ElementGroup {
    /// Whatever this group's `requestGroupLayout` hands to the later phases.
    associatedtype GroupLayout

    /// Whatever this group's `prepaintGroup` hands to `paintGroup`.
    associatedtype GroupPrepaint

    /// Registers every member's nodes, in order, and returns them flattened.
    ///
    /// The order is the order the container will hand to its registrar, and is
    /// therefore the flex order — so it must match source order.
    ///
    /// `cursor` is the container's **flat** child index, threaded rather than
    /// nested: `Pair` hands the same cursor to both halves in order, so
    /// `Column { A; B; C }` — whose type is `Column<Pair<A, Pair<B, C>>>` —
    /// identifies its children `0, 1, 2` and not `[0], [1, 0], [1, 1]`.
    /// A conformance consumes one index per element it identifies and leaves the
    /// cursor pointing at the next free one.
    ///
    /// **`parent`'s optionality is INERT, not forced.** It matches
    /// `GlobalElementID.child(of:at:name:)`'s parameter, whose optional *is*
    /// forced — a root has no parent — but the root never travels this path:
    /// `Frame.render` builds the root id itself and never calls
    /// `requestGroupLayout`, and every container below hands down its own
    /// non-optional id. So **no production caller passes `nil` and nothing would
    /// break if this lost its `?`**; it keeps it only because tightening it
    /// touches eight conformances and every hand-built test group for no
    /// behavioural gain. Said here rather than left implied, because three
    /// documents counted the surviving optionals differently and each read this
    /// one as a necessity.
    mutating func requestGroupLayout(under parent: GlobalElementID?,
                                     at cursor: inout Int,
                                     pass: inout LayoutPass) -> ([LayoutNodeID], GroupLayout)

    mutating func prepaintGroup(layout: inout GroupLayout,
                                pass: inout PrepaintPass) -> GroupPrepaint

    mutating func paintGroup(layout: inout GroupLayout,
                             prepaint: inout GroupPrepaint,
                             pass: inout PaintPass)

    /// The type a legacy wrapper modifier (`.padding`, `.frame`) wraps: `Self`
    /// for every conformer but `ModifiedContent` (`ModifiedElement`), whose
    /// layers wrap its content, so a chain stays ONE `ModifiedElement<Base>`
    /// however long it grows (ruling MC-A). **One witness for both
    /// vocabularies** since stage 11 (ruling `LR-FV` item 4): a legacy wrapper
    /// over a proposal chain absorbs its layers as the new chain's innermost
    /// `prefix` (`ModifiedContent.swift`).
    associatedtype LayerBase: ElementGroup = Self

    /// Framework entry point for `.padding`/`.frame`: adds one outer layer.
    /// **Not for conformers to implement.** A conformer that declares
    /// `LayerBase` and forwards this to another value compiles, and its
    /// `.padding` then silently drops the receiver — a hole no access-control
    /// spelling closes, since a requirement is as visible as its protocol
    /// (ruling MC-A).
    func _wrap(_ layer: ModifierLayer) -> ModifiedElement<LayerBase>
}

// MARK: - Every element is a group of one

/// What an `Element` carries between phases when it is used as a group member:
/// its derived identity, its node, and its own `LayoutState`.
///
/// The identity is stored rather than recomputed so that all three phases see
/// the same path even if the element's `elementID` changes between them — an
/// element is a value the container may mutate, and a path recomputed in
/// `paint` from a changed `elementID` would silently address a different state
/// entry than the one `requestLayout` marked.
public struct SingleElementLayout<E: Element> {
    var id: GlobalElementID
    var node: LayoutNodeID
    var state: E.LayoutState
}

extension Element {
    /// One element is one index. `child(of:at:name:)` decides which component
    /// that becomes: a `.named` one when the element carries an `.id()`, a
    /// `.positional(cursor)` one otherwise. The index is supplied either way, so
    /// the name-replaces-position rule lives in the constructor and not here.
    ///
    /// The id, the `@State` bind and the cursor advance are one call to
    /// `GlobalElementID.enteringGroupMember` (`GroupMember.swift`, ruling MC-H),
    /// shared with the typed proposal defaults.
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], SingleElementLayout<Self>) {
        let id = GlobalElementID.enteringGroupMember(self, name: elementID, under: parent,
                                                     at: &cursor, pass: &pass)
        let (node, state) = requestLayout(id, pass: &pass)
        return ([node], SingleElementLayout(id: id, node: node, state: state))
    }

    public mutating func prepaintGroup(layout: inout SingleElementLayout<Self>,
                                       pass: inout PrepaintPass) -> PrepaintState {
        // **Re-bind, because `State.Box` is a class and one element VALUE can
        // be placed twice.** `Row { sep; sep }` copies the struct, and a copy
        // shares the box by reference, so the second occurrence's `bind` in
        // `requestGroupLayout` leaves the box pointing at ITS slot. Without
        // this line the first occurrence reads the second's `@State` in every
        // phase after layout — measured `[2, 2]` where `[1, 2]` is correct.
        // `layout.id` is this occurrence's own id, stamped during layout, so
        // re-binding to it is exact rather than a guess.
        // Pinned by `oneElementValuePlacedTwiceDoesNotShareItsState`.
        StateBinder.bind(self, in: pass.frame, id: layout.id)
        // `display: none` hides the subtree from an accessibility client (ruling
        // AB-O): the "one check in `Element`'s group walk" `Box.focusable()`'s
        // doc names, applied to accessibility ONLY — focus, hitboxes and paint
        // keep their inert-table behaviour. The style is read only while collecting.
        // The check is `Frame.suppressingAccessibilityIfHidden`, shared with
        // `ModifiedContent`'s inner layers.
        // The element bounds log (plan task 7, ruling LR-D), for a frame built to
        // record it; `ModifiedContent.prepaintLayer` mirrors this per inner layer
        // (ruling MC-B) and `Frame.render` records the root.
        //
        // Since stage 6b (ruling `LR-DH`) a node a lowered `hidden()` put in
        // `Frame.hiddenNodes` also prepaints under the pointer-disable scope, so it
        // and everything inside it register no pointer hitbox (probe V3) — and
        // accessibility reads `isHidden`, which covers both paths. Mirrored per inner
        // layer by `ModifiedContent.prepaintLayer` and in `AnyElement`'s entry below.
        pass.frame.recordElementBounds(layout.id, pass.bounds(of: layout.node))
        return pass.frame.suppressingAccessibilityIfHidden(layout.node) {
            pass.frame.disablingHitTestingIfHidden(layout.node) {
                prepaint(layout.id, bounds: pass.bounds(of: layout.node), layout: &layout.state, pass: &pass)
            }
        }
    }

    public mutating func paintGroup(layout: inout SingleElementLayout<Self>,
                                    prepaint: inout PrepaintState,
                                    pass: inout PaintPass) {
        // A lowered `hidden()` paints nothing, and nothing inside it paints (stage 6b,
        // ruling `LR-DH` item 2; probe V1). **`hiddenNodes` only**: until stage 9
        // the legacy path kept painting a `display: none` subtree as before (1.6);
        // that path is deleted (`LR-FC`), so every hidden node is in `hiddenNodes`.
        guard !pass.frame.hiddenNodes.contains(layout.node) else { return }
        // Same reason as `prepaintGroup` above — paint is a third phase and the
        // box is still whatever the last `bind` left it.
        StateBinder.bind(self, in: pass.frame, id: layout.id)
        paint(layout.id, bounds: pass.bounds(of: layout.node),
              layout: &layout.state, prepaint: &prepaint, pass: &pass)
    }
}

// MARK: - The builder's products

/// No children at all — `Box()`, or a builder block with no statements.
public struct EmptyGroup: ElementGroup {
    public init() {}

    /// No members, so no index is consumed and the cursor is left where it was.
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Void) {
        ([], ())
    }

    public mutating func prepaintGroup(layout: inout Void, pass: inout PrepaintPass) {}

    public mutating func paintGroup(layout: inout Void,
                                    prepaint: inout Void, pass: inout PaintPass) {}
}

/// Two groups, concatenated — the shape every multi-statement builder block
/// folds into (§4.6 mitigation 1).
///
/// Left-nested: three statements give `Pair<Pair<A, B>, C>`, and the node order
/// that falls out of `a` before `b` at every level is source order.
public struct Pair<First: ElementGroup, Second: ElementGroup>: ElementGroup {
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public struct Layout {
        var first: First.GroupLayout
        var second: Second.GroupLayout
    }

    public struct Prepaint {
        var first: First.GroupPrepaint
        var second: Second.GroupPrepaint
    }

    /// **This is the line that makes the index space flat.** The *same* cursor
    /// goes to both halves, in order, so the builder's left-nested
    /// `Pair<Pair<A, B>, C>` yields indices 0, 1, 2 rather than a path per
    /// nesting level. Handing `second` a fresh cursor — or wrapping either half
    /// in an id of its own — would make identity depend on how the builder
    /// happened to group statements, which is what §3.4 rejects.
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        let (firstNodes, firstLayout) = first.requestGroupLayout(under: parent, at: &cursor,
                                                                 pass: &pass)
        let (secondNodes, secondLayout) = second.requestGroupLayout(under: parent, at: &cursor,
                                                                    pass: &pass)
        return (firstNodes + secondNodes,
                Layout(first: firstLayout, second: secondLayout))
    }

    public mutating func prepaintGroup(layout: inout Layout,
                                       pass: inout PrepaintPass) -> Prepaint {
        Prepaint(first: first.prepaintGroup(layout: &layout.first, pass: &pass),
                 second: second.prepaintGroup(layout: &layout.second, pass: &pass))
    }

    public mutating func paintGroup(layout: inout Layout,
                                    prepaint: inout Prepaint, pass: inout PaintPass) {
        first.paintGroup(layout: &layout.first,
                         prepaint: &prepaint.first, pass: &pass)
        second.paintGroup(layout: &layout.second,
                          prepaint: &prepaint.second, pass: &pass)
    }
}

/// An `if` with no `else`: the group is there or it is not, and when it is not
/// it contributes no nodes.
///
/// **One structural slot, content numbered inside it** (plan task 8, ruling
/// `ID-B`). The group takes exactly one cursor index whether or not it has
/// content, and its content numbers from 0 under a slot id `.positional(index)`
/// of its own — the shape `EitherGroup`'s taken branch has had since `SI-F`. So
/// every sibling after an `if` keeps one index whatever the condition, and an
/// element after a vanishing `if` keeps its own state (probe V1). Until `ID-B`
/// the group consumed no index when absent and the trailing sibling ADOPTED the
/// vanished element's entry (`SI-G`, which rested on a claim about SwiftUI no
/// probe had run; divergence 69 inside a grid). Pinned by
/// `anElementAfterAVanishingIfKeepsItsOwnState`, C2.2 and C2.3
/// (`ConditionalIdentityTests.swift`).
///
/// **Content an evaluated `if` removes is reset** (ruling `ID-C`). The group
/// notes its slot produced or absent in the `StateTable`; on the frame after one
/// that produced it, an absent slot deletes every entry below it except the
/// window-owned `$focus`/`$ax` retention slots, so content that returns starts
/// fresh (probe V5; divergence 18 retired for conditionals). A subtree nothing
/// evaluates — a `List` row out of the window — is never noted absent and keeps
/// `TB-AH`'s bounded retention. See `StateTable.noteAbsent`.
public struct OptionalGroup<Wrapped: ElementGroup>: ElementGroup {
    public var wrapped: Wrapped?

    public init(_ wrapped: Wrapped?) { self.wrapped = wrapped }

    /// Reserves one index, then registers the content under that slot with a
    /// fresh inner cursor — or notes the slot absent (`ID-C`). **The typed copy
    /// in `ProposalElementGroup.swift` is a separate implementation, pinned on
    /// its own** (C2.5a/C2.5b; mutation M2a′ there, M2a here).
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], Wrapped.GroupLayout?) {
        let slot = GlobalElementID(component: .positional(cursor), parent: parent)
        cursor += 1
        guard var inner = wrapped else {
            pass.frame.stateTable.noteAbsent(slot)
            return ([], nil)
        }
        pass.frame.stateTable.noteProduced(slot)
        var innerCursor = 0
        let (nodes, layout) = inner.requestGroupLayout(under: slot, at: &innerCursor, pass: &pass)
        wrapped = inner
        return (nodes, layout)
    }

    public mutating func prepaintGroup(layout: inout Wrapped.GroupLayout?,
                                       pass: inout PrepaintPass) -> Wrapped.GroupPrepaint? {
        guard var inner = wrapped else {
            precondition(layout == nil, Self.mismatch("prepaint"))
            return nil
        }
        guard var innerLayout = layout else { preconditionFailure(Self.mismatch("prepaint")) }
        let prepaint = inner.prepaintGroup(layout: &innerLayout, pass: &pass)
        wrapped = inner
        layout = innerLayout
        return prepaint
    }

    public mutating func paintGroup(layout: inout Wrapped.GroupLayout?,
                                    prepaint: inout Wrapped.GroupPrepaint?,
                                    pass: inout PaintPass) {
        guard var inner = wrapped else {
            precondition(layout == nil && prepaint == nil, Self.mismatch("paint"))
            return
        }
        guard var innerLayout = layout,
              var innerPrepaint = prepaint else { preconditionFailure(Self.mismatch("paint")) }
        inner.paintGroup(layout: &innerLayout,
                         prepaint: &innerPrepaint, pass: &pass)
        wrapped = inner
        layout = innerLayout
        prepaint = innerPrepaint
    }

    /// The same rule, and the same trap, as `EitherGroup.mismatch`.
    ///
    /// **This branch returned `nil` silently for one commit**, which is exactly
    /// what `EitherGroup`'s trap exists to prevent: an `if` whose condition
    /// flipped between `requestLayout` and `prepaint` would have had its child
    /// painted at nothing, with no diagnostic, while the identical flip inside
    /// an `if`/`else` aborted. Trapping was chosen over silence for both — a
    /// container whose children changed shape mid-frame has already produced a
    /// wrong frame, and the loud version is the one that says where.
    ///
    /// `wrapped == nil` with `layout == nil` is the ordinary absent case and is
    /// not a mismatch.
    private static func mismatch(_ phase: StaticString) -> String {
        """
        OptionalGroup \(phase): the phase state disagrees with the group running this phase \
        about whether a child exists — its content was rebuilt mid-frame
        """
    }
}

/// An `if`/`else`: one of two groups, each keeping its own concrete type.
public enum EitherGroup<First: ElementGroup, Second: ElementGroup>: ElementGroup {
    case first(First)
    case second(Second)

    /// Each case carries only the branch's layout.
    ///
    /// A branch's own id used to be carried alongside it here, because the id is
    /// derived from a cursor that only `requestGroupLayout` has and the later
    /// phases could not recompute it. `prepaintGroup`/`paintGroup` no longer take
    /// a `parent` to forward, so no phase below `requestGroupLayout` needs a
    /// branch id at all — the branch's id was its only reader, and both are gone
    /// together.
    public enum Layout {
        case first(First.GroupLayout)
        case second(Second.GroupLayout)
    }

    public enum Prepaint {
        case first(First.GroupPrepaint)
        case second(Second.GroupPrepaint)
    }

    /// **The two branches never share a component, so flipping the `if` resets
    /// the subtree's state instead of carrying it into structurally different
    /// elements.** The taken branch hangs under an id of its own —
    /// `.positional(cursor)` for `.first`, `.positional(cursor + 1)` for
    /// `.second` — and its members number from 0 *inside* that id.
    ///
    /// **The outer cursor advances by 2 because the branch RESERVES both slots,
    /// not because a later sibling's index would otherwise move.** This comment
    /// said the latter and measurement falsified it: `cursor += 2` runs before
    /// the switch, so under `+= 1` a later sibling's index is stable too —
    /// `Row { if flag { C() } else { C() }; C() }` puts the trailing element at
    /// `.positional(1)` on **both** frames of a flip and it counts 2 either way.
    /// What actually breaks is a sibling landing on the slot the *untaken*
    /// branch would have used: measured, `Row { if flag { C() } else { C() };
    /// Row { C() } }` collapses two state entries into one reading 3, and
    /// `Row { if a {…} else {…}; if b {…} else {…} }` — spec §3.5's collision —
    /// collapses into one reading 2. Pinned by
    /// `aBranchReservesBothIndicesSoASiblingCannotLandOnTheUntakenOne`, which is
    /// the only test that reddens on `+= 1`; the composition it needs did not
    /// exist in the suite until it was written, which is taxonomy shape 9.
    ///
    /// **The intermediate id is what makes that true for a branch of any size,
    /// and a flat pair of indices would not be.** Numbering the branches'
    /// members directly in the parent's space from `cursor` and `cursor + 1`
    /// works only while both branches hold exactly one element: in
    /// `if flag { Box(); Box() } else { Box() }` the first branch's *second*
    /// member and the second branch's only member would both be
    /// `.positional(cursor + 1)` — the collision this method exists to prevent,
    /// reachable from ordinary builder code. Members numbering from 0 under a
    /// per-branch id cannot collide however many there are.
    ///
    /// This is the same rule the phase-mismatch trap below already applies: a
    /// flipped branch is a different subtree, not the same one rebuilt.
    ///
    /// **Since plan task 8 the flip also RESETS** (ruling `ID-C`): the taken
    /// branch's id is noted produced and the untaken one's absent, so a branch
    /// flipped away and back starts fresh (probe V9) instead of finding its
    /// tombstone. The typed copy (`ProposalElementGroup.swift`, ruling `ID-D`)
    /// numbers and notes identically and is pinned on its own (C2.11, M2i).
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        let branchIndex = cursor
        cursor += 2
        let firstBranch = GlobalElementID(component: .positional(branchIndex), parent: parent)
        let secondBranch = GlobalElementID(component: .positional(branchIndex + 1), parent: parent)
        switch self {
        case .first(var group):
            pass.frame.stateTable.noteProduced(firstBranch)
            pass.frame.stateTable.noteAbsent(secondBranch)
            var inner = 0
            let (nodes, layout) = group.requestGroupLayout(under: firstBranch, at: &inner, pass: &pass)
            self = .first(group)
            return (nodes, .first(layout))
        case .second(var group):
            pass.frame.stateTable.noteProduced(secondBranch)
            pass.frame.stateTable.noteAbsent(firstBranch)
            var inner = 0
            let (nodes, layout) = group.requestGroupLayout(under: secondBranch, at: &inner, pass: &pass)
            self = .second(group)
            return (nodes, .second(layout))
        }
    }

    public mutating func prepaintGroup(layout: inout Layout,
                                       pass: inout PrepaintPass) -> Prepaint {
        switch (self, layout) {
        case (.first(var group), .first(var inner)):
            let prepaint = group.prepaintGroup(layout: &inner, pass: &pass)
            self = .first(group)
            layout = .first(inner)
            return .first(prepaint)
        case (.second(var group), .second(var inner)):
            let prepaint = group.prepaintGroup(layout: &inner, pass: &pass)
            self = .second(group)
            layout = .second(inner)
            return .second(prepaint)
        default:
            preconditionFailure(Self.mismatch("prepaint"))
        }
    }

    public mutating func paintGroup(layout: inout Layout,
                                    prepaint: inout Prepaint, pass: inout PaintPass) {
        switch (self, layout, prepaint) {
        case (.first(var group), .first(var innerLayout), .first(var innerPrepaint)):
            group.paintGroup(layout: &innerLayout,
                             prepaint: &innerPrepaint, pass: &pass)
            self = .first(group)
            layout = .first(innerLayout)
            prepaint = .first(innerPrepaint)
        case (.second(var group), .second(var innerLayout), .second(var innerPrepaint)):
            group.paintGroup(layout: &innerLayout,
                             prepaint: &innerPrepaint, pass: &pass)
            self = .second(group)
            layout = .second(innerLayout)
            prepaint = .second(innerPrepaint)
        default:
            preconditionFailure(Self.mismatch("paint"))
        }
    }

    /// Reachable from **one** `EitherGroup` value whose content is rebuilt
    /// between phases — an element that recomputes its `content` in `prepaint`
    /// rather than storing what `requestLayout` built.
    ///
    /// **This comment said the opposite until the review caught it**, and the
    /// commit that added `flippingAnEitherBranchBetweenPhasesTraps` — which
    /// reaches this trap from a single value in ~35 lines of ordinary element
    /// code — is the same commit that left the false sentence standing directly
    /// above it. The old claim ("reachable only by handing one `EitherGroup` a
    /// phase state produced by a *different* value") reasoned correctly from a
    /// premise it never checked: that `self`'s case is fixed for the frame. It
    /// is fixed only if the element *stores* its content; nothing requires that.
    ///
    /// What remains true is the narrower half: no phase in this file changes
    /// which case `self` holds — each writes back the case it matched — and a
    /// container threads state back into the same stored child. So a group that
    /// holds its content still cannot reach here. The trap exists because the
    /// alternative is silently painting nothing.
    /// **The phase is named in the message, and that is load-bearing.** Every
    /// trap in this file is backstopped by the next phase's, so an exit test
    /// that asserted only "the process died" cannot tell a `prepaint` guard
    /// firing from the `paint` guard catching the same mismatch one phase
    /// later — measured: deleting `OptionalGroup`'s prepaint precondition left
    /// the whole suite green until its test began reading stderr.
    private static func mismatch(_ phase: StaticString) -> String {
        """
        EitherGroup \(phase): the phase state came from a different EitherGroup value \
        than the one running this phase — its content was rebuilt mid-frame
        """
    }
}

/// A `for` loop in a builder: N groups of one type.
///
/// Still concrete — `for item in items { Row(item) }` gives
/// `ArrayGroup<Row<…>>`, not `[AnyElement]`. The array allocates; the elements
/// in it do not box.
public struct ArrayGroup<Group: ElementGroup>: ElementGroup {
    public var groups: [Group]

    public init(_ groups: [Group]) { self.groups = groups }

    /// **One structural slot for the whole loop** (plan task 8, ruling `ID-B`):
    /// the loop takes one index of the container's space and threads ONE inner
    /// cursor across all its members under that slot, so the siblings after a
    /// loop keep their indices however many items it has (probe V6). An item
    /// that carries `.id()` keeps its state through a reorder — the name
    /// replaces its position WITHIN the loop, the `ForEach` analogue — while an
    /// unnamed item's identity *is* its position in the loop. Until `ID-B` the
    /// items sat directly in the container's flat space.
    ///
    /// **A loop does not reset** (`ID-C`): an item it stops producing keeps its
    /// entries and gets them back if the loop grows again — divergence 74,
    /// owner plan task 10 (`ForEach`), pinned by C2.4b. The typed copy is pinned
    /// on its own (`aForLoopInsideAProposalContainerPlacesEveryIterationInItsOwnSlot`).
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], [Group.GroupLayout]) {
        let slot = GlobalElementID(component: .positional(cursor), parent: parent)
        cursor += 1
        var innerCursor = 0
        var nodes: [LayoutNodeID] = []
        var layouts: [Group.GroupLayout] = []
        layouts.reserveCapacity(groups.count)
        for index in groups.indices {
            let (childNodes, childLayout) = groups[index].requestGroupLayout(under: slot,
                                                                            at: &innerCursor,
                                                                            pass: &pass)
            nodes.append(contentsOf: childNodes)
            layouts.append(childLayout)
        }
        return (nodes, layouts)
    }

    public mutating func prepaintGroup(layout: inout [Group.GroupLayout],
                                       pass: inout PrepaintPass) -> [Group.GroupPrepaint] {
        precondition(layout.count == groups.count, Self.countMismatch("prepaint"))
        var prepaints: [Group.GroupPrepaint] = []
        prepaints.reserveCapacity(groups.count)
        for index in groups.indices {
            prepaints.append(groups[index].prepaintGroup(layout: &layout[index], pass: &pass))
        }
        return prepaints
    }

    public mutating func paintGroup(layout: inout [Group.GroupLayout],
                                    prepaint: inout [Group.GroupPrepaint],
                                    pass: inout PaintPass) {
        precondition(layout.count == groups.count && prepaint.count == groups.count,
                     Self.countMismatch("paint"))
        for index in groups.indices {
            groups[index].paintGroup(layout: &layout[index],
                                     prepaint: &prepaint[index], pass: &pass)
        }
    }

    /// Same mechanism as `EitherGroup.mismatch`, including its correction: the
    /// arrays are produced by this value's own `requestGroupLayout` and threaded
    /// back unmodified, so a differing count means **this value's own content
    /// was rebuilt between phases** — not that the states came from a different
    /// `ArrayGroup`, which is what this sentence claimed until the review caught
    /// it. `changingAnArrayGroupsCountBetweenPhasesTraps` reaches it from a
    /// single value, by the identical route.
    private static func countMismatch(_ phase: StaticString) -> String {
        """
        ArrayGroup \(phase): the phase state has a different member count than the group \
        running this phase — its content was rebuilt mid-frame
        """
    }
}

// MARK: - The dynamic escape hatch

/// `AnyElement` is a group of one, so a heterogeneous child list stays
/// expressible (§4.6).
///
/// **This is the escape hatch, not the road.** Every other conformance in this
/// file keeps its members' concrete types; this one is the only path that boxes,
/// and it is reached only when an author writes `AnyElement(…)` by hand.
extension AnyElement: ElementGroup {
    /// `AnyElement` holds its own phase states inside the box, so all a
    /// container needs to carry between phases is the node and the identity.
    public struct GroupLayout {
        var id: GlobalElementID
        var node: LayoutNodeID
    }

    /// Identical to `Element`'s default for the CURSOR: an erased element is
    /// still one element and therefore one index.
    ///
    /// **Not `enteringGroupMember`, and `@State` still binds.** `Element`'s
    /// default seeds every `@State` through `StateBinder.bind` inside the shared
    /// helper `GlobalElementID.enteringGroupMember` (`GroupMember.swift`, ruling
    /// MC-H); this entry cannot call it on `self`, because `Mirror(reflecting:
    /// anyElement)` sees only the boxed `any ElementObject`. Since plan task 8
    /// (ruling `ID-E`) the box binds instead: `AnyElementBox.requestLayout`,
    /// `.prepaint` and `.paint` each call `StateBinder.bind` on the erased
    /// element before forwarding, so `@State` and `@Environment` inside an
    /// `AnyElement` bind as they do anywhere else. Until then they were inert —
    /// this paragraph said so, and CLAUDE.md's declared-but-inert table listed it.
    ///
    /// **A second copy of the cursor advance, and it was unguarded until
    /// `twoErasedSiblingsDoNotShareOneStateEntry`.** "Identical to `Element`'s
    /// default" was a claim about two separate lines, and `Element`'s tests
    /// cannot reach this one — nothing in the suite put two `AnyElement`s with
    /// cross-frame state in one container, so deleting the `cursor += 1` below
    /// left all 358 green. It now reddens exactly that test. The same
    /// duplication is why this file's seeding line went missing in the first
    /// place: the two `requestGroupLayout`s are hand-kept in sync rather than
    /// sharing an implementation, and this is the second thing to go missing
    /// from the copy, not the first. (`Element`'s default and both typed
    /// proposal defaults now share `enteringGroupMember`; this one stays a copy
    /// because its box has nothing `StateBinder` can reflect, above.)
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], GroupLayout) {
        let id = GlobalElementID.child(of: parent, at: cursor, name: elementID)
        cursor += 1
        let node = requestLayout(id, pass: &pass)
        return ([node], GroupLayout(id: id, node: node))
    }

    public mutating func prepaintGroup(layout: inout GroupLayout,
                                       pass: inout PrepaintPass) {
        // The element bounds log (plan task 7, ruling LR-D), as
        // `Element.prepaintGroup` records it: this group entry is a copy of that
        // default, and lane 1's log missed it, so the differential harness could
        // not see an erased element until lane 5's corpus put one in (record §18,
        // lane 5; pinned by `theStageOneCorpusLowersWithNoDiagnostic`).
        pass.frame.recordElementBounds(layout.id, pass.bounds(of: layout.node))
        // Stage 6b (ruling `LR-DH` item 4): `Element.prepaintGroup`'s hidden gates,
        // mirrored — accessibility suppressed and hitboxes under the pointer-disable
        // scope for a node in `Frame.hiddenNodes`. **`hiddenNodes` only, not
        // `isHidden`**: this entry never had the legacy `display: none` suppression
        // (record §18); since stage 9 deleted the legacy path, `isHidden` reads
        // `hiddenNodes` alone and the two are the same set.
        guard pass.frame.hiddenNodes.contains(layout.node) else {
            prepaint(layout.id, bounds: pass.bounds(of: layout.node), pass: &pass)
            return
        }
        pass.frame.withAccessibilitySuppressed(except: nil) {
            pass.frame.withHitTestingDisabled {
                prepaint(layout.id, bounds: pass.bounds(of: layout.node), pass: &pass)
            }
        }
    }

    public mutating func paintGroup(layout: inout GroupLayout,
                                    prepaint: inout Void, pass: inout PaintPass) {
        // Stage 6b (`LR-DH` item 4): `Element.paintGroup`'s skip, mirrored.
        guard !pass.frame.hiddenNodes.contains(layout.node) else { return }
        paint(layout.id, bounds: pass.bounds(of: layout.node), pass: &pass)
    }
}
