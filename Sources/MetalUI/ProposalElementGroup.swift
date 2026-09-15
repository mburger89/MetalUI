/// An element subtree whose layout is entirely owned by MetalUI's
/// proposal/measurement/placement engine.
///
/// The marker is the migration boundary between the new SwiftUI-style surface
/// and CSS-derived elements. It lets an overload such as `.frame(...)` select
/// proposal-layout semantics at compile time instead of asking a runtime
/// wrapper to guess which layout engine owns its child.
///
/// **It is a requirement, not only a marker** (ruling MC-G, which delivers the
/// compile-time half of SA-R): `requestProposalGroupLayout` returns
/// `ProposalNodeID`s, which only `LayoutPass`'s native registrars mint, and it is
/// what every proposal container calls. So an `Element` that registers a legacy
/// node cannot take the marker by declaring it: it must be a `ProposalElement`
/// (`ProposalNodeID.swift`), a `Component` over proposal content, or a group of
/// such. Until lane 3 of the modifier-composition track the protocol had no
/// requirements and that lie compiled, surfacing only as a run-time trap.
///
/// **Two entry points, which can disagree.** `ElementGroup.requestGroupLayout`
/// stays, because `Frame` and legacy containers call it; a conformer writing both
/// itself can register different nodes from each (`MC-G` hole 1, pinned wrong on
/// purpose by `aProposalGroupWhoseEntryPointsDisagreeStillCompiles`). The other
/// six holes are listed in `ProposalNodeID.swift`'s header.
public protocol ProposalElementGroup: ElementGroup {
    /// Registers every member's native nodes, in order, and returns them
    /// flattened, with the same identity, cursor and `GroupLayout` contract as
    /// `ElementGroup.requestGroupLayout`. Proposal containers call this, never
    /// the untyped entry.
    mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                             at cursor: inout Int,
                                             pass: inout LayoutPass) -> ([ProposalNodeID], GroupLayout)
}

// MARK: - The builder's products, on the typed entry
//
// Each mirrors its untyped `requestGroupLayout` in `ElementGroup.swift` line for
// line, calling the typed entry on its members. **They are copies, so each is
// pinned on its own**: the untyped entries' tests never reach them, and until
// the verifier round on lane 3, three of the four could lose a load-bearing line
// with the whole suite green (ruling MC-H). `Pair`'s node order is pinned by the
// native layout tests, `ArrayGroup`'s appends by
// `aForLoopInsideAProposalContainerPlacesEveryIterationInItsOwnSlot`,
// `OptionalGroup`'s `wrapped = inner` by
// `anElementInsideAnIfInsideAProposalContainerKeepsItsLayoutTimeWrites`, and
// `Component`'s typed default (`ProposalNodeID.swift`) by
// `aProposalComponentsContentIsPositionZeroUnderItsOwnID`.

extension EmptyGroup: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass) -> ([ProposalNodeID], Void) {
        ([], ())
    }
}

extension Pair: ProposalElementGroup where First: ProposalElementGroup, Second: ProposalElementGroup {
    /// One cursor threaded through both halves, as the untyped entry threads it.
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass) -> ([ProposalNodeID], Layout) {
        let (firstNodes, firstLayout) = first.requestProposalGroupLayout(under: parent, at: &cursor,
                                                                         pass: &pass)
        let (secondNodes, secondLayout) = second.requestProposalGroupLayout(under: parent, at: &cursor,
                                                                            pass: &pass)
        return (firstNodes + secondNodes, Layout(first: firstLayout, second: secondLayout))
    }
}

extension OptionalGroup: ProposalElementGroup where Wrapped: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], Wrapped.GroupLayout?) {
        guard var inner = wrapped else { return ([], nil) }
        let (nodes, layout) = inner.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        wrapped = inner
        return (nodes, layout)
    }
}

extension ArrayGroup: ProposalElementGroup where Group: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], [Group.GroupLayout]) {
        var nodes: [ProposalNodeID] = []
        var layouts: [Group.GroupLayout] = []
        layouts.reserveCapacity(groups.count)
        for index in groups.indices {
            let (childNodes, childLayout) = groups[index].requestProposalGroupLayout(under: parent,
                                                                                    at: &cursor,
                                                                                    pass: &pass)
            nodes.append(contentsOf: childNodes)
            layouts.append(childLayout)
        }
        return (nodes, layouts)
    }
}

// MARK: - The proposal elements

extension HStack: ProposalElement {}
extension VStack: ProposalElement {}
extension ZStack: ProposalElement {}
extension ProposalFrame: ProposalElement {}
extension Padding: ProposalElement {}
extension Background: ProposalElement {}
extension FixedSize: ProposalElement {}
extension Spacer: ProposalElement {}
extension Rectangle: ProposalElement {}
extension Color: ProposalElement {}
extension ModifiedContent: ProposalElement {}
extension OnTapModifier: ProposalElement {}
extension OverlayModifier: ProposalElement {}
