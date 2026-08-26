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
/// `GlobalElementID.child(of:_:)`, which is why identity does not resume below
/// an anonymous container (§4.3).
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
    /// The order is the order the container will hand to `requestNode`, and is
    /// therefore the flex order — so it must match source order.
    mutating func requestGroupLayout(under parent: GlobalElementID?,
                                     pass: inout LayoutPass) -> ([LayoutNodeID], GroupLayout)

    mutating func prepaintGroup(under parent: GlobalElementID?,
                                layout: inout GroupLayout,
                                pass: inout PrepaintPass) -> GroupPrepaint

    mutating func paintGroup(under parent: GlobalElementID?,
                             layout: inout GroupLayout,
                             prepaint: inout GroupPrepaint,
                             pass: inout PaintPass)
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
    var id: GlobalElementID?
    var node: LayoutNodeID
    var state: E.LayoutState
}

extension Element {
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], SingleElementLayout<Self>) {
        let id = GlobalElementID.child(of: parent, elementID)
        let (node, state) = requestLayout(id, pass: &pass)
        return ([node], SingleElementLayout(id: id, node: node, state: state))
    }

    public mutating func prepaintGroup(under parent: GlobalElementID?,
                                       layout: inout SingleElementLayout<Self>,
                                       pass: inout PrepaintPass) -> PrepaintState {
        prepaint(layout.id, bounds: pass.bounds(of: layout.node),
                 layout: &layout.state, pass: &pass)
    }

    public mutating func paintGroup(under parent: GlobalElementID?,
                                    layout: inout SingleElementLayout<Self>,
                                    prepaint: inout PrepaintState,
                                    pass: inout PaintPass) {
        paint(layout.id, bounds: pass.bounds(of: layout.node),
              layout: &layout.state, prepaint: &prepaint, pass: &pass)
    }
}

// MARK: - The builder's products

/// No children at all — `Box()`, or a builder block with no statements.
public struct EmptyGroup: ElementGroup {
    public init() {}

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Void) {
        ([], ())
    }

    public mutating func prepaintGroup(under parent: GlobalElementID?, layout: inout Void,
                                       pass: inout PrepaintPass) {}

    public mutating func paintGroup(under parent: GlobalElementID?, layout: inout Void,
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

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        let (firstNodes, firstLayout) = first.requestGroupLayout(under: parent, pass: &pass)
        let (secondNodes, secondLayout) = second.requestGroupLayout(under: parent, pass: &pass)
        return (firstNodes + secondNodes,
                Layout(first: firstLayout, second: secondLayout))
    }

    public mutating func prepaintGroup(under parent: GlobalElementID?, layout: inout Layout,
                                       pass: inout PrepaintPass) -> Prepaint {
        Prepaint(first: first.prepaintGroup(under: parent, layout: &layout.first, pass: &pass),
                 second: second.prepaintGroup(under: parent, layout: &layout.second, pass: &pass))
    }

    public mutating func paintGroup(under parent: GlobalElementID?, layout: inout Layout,
                                    prepaint: inout Prepaint, pass: inout PaintPass) {
        first.paintGroup(under: parent, layout: &layout.first,
                         prepaint: &prepaint.first, pass: &pass)
        second.paintGroup(under: parent, layout: &layout.second,
                          prepaint: &prepaint.second, pass: &pass)
    }
}

/// An `if` with no `else`: the group is there or it is not, and when it is not
/// it contributes no nodes.
///
/// **A branch that flips between frames is a different subtree, not the same one
/// resized.** Any state its elements held keyed on a `GlobalElementID` that is
/// no longer produced is swept after the frame it disappears in (§4.3).
public struct OptionalGroup<Wrapped: ElementGroup>: ElementGroup {
    public var wrapped: Wrapped?

    public init(_ wrapped: Wrapped?) { self.wrapped = wrapped }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], Wrapped.GroupLayout?) {
        guard var inner = wrapped else { return ([], nil) }
        let (nodes, layout) = inner.requestGroupLayout(under: parent, pass: &pass)
        wrapped = inner
        return (nodes, layout)
    }

    public mutating func prepaintGroup(under parent: GlobalElementID?,
                                       layout: inout Wrapped.GroupLayout?,
                                       pass: inout PrepaintPass) -> Wrapped.GroupPrepaint? {
        guard var inner = wrapped, var innerLayout = layout else { return nil }
        let prepaint = inner.prepaintGroup(under: parent, layout: &innerLayout, pass: &pass)
        wrapped = inner
        layout = innerLayout
        return prepaint
    }

    public mutating func paintGroup(under parent: GlobalElementID?,
                                    layout: inout Wrapped.GroupLayout?,
                                    prepaint: inout Wrapped.GroupPrepaint?,
                                    pass: inout PaintPass) {
        guard var inner = wrapped, var innerLayout = layout,
              var innerPrepaint = prepaint else { return }
        inner.paintGroup(under: parent, layout: &innerLayout,
                         prepaint: &innerPrepaint, pass: &pass)
        wrapped = inner
        layout = innerLayout
        prepaint = innerPrepaint
    }
}

/// An `if`/`else`: one of two groups, each keeping its own concrete type.
public enum EitherGroup<First: ElementGroup, Second: ElementGroup>: ElementGroup {
    case first(First)
    case second(Second)

    public enum Layout {
        case first(First.GroupLayout)
        case second(Second.GroupLayout)
    }

    public enum Prepaint {
        case first(First.GroupPrepaint)
        case second(Second.GroupPrepaint)
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        switch self {
        case .first(var group):
            let (nodes, layout) = group.requestGroupLayout(under: parent, pass: &pass)
            self = .first(group)
            return (nodes, .first(layout))
        case .second(var group):
            let (nodes, layout) = group.requestGroupLayout(under: parent, pass: &pass)
            self = .second(group)
            return (nodes, .second(layout))
        }
    }

    public mutating func prepaintGroup(under parent: GlobalElementID?, layout: inout Layout,
                                       pass: inout PrepaintPass) -> Prepaint {
        switch (self, layout) {
        case (.first(var group), .first(var inner)):
            let prepaint = group.prepaintGroup(under: parent, layout: &inner, pass: &pass)
            self = .first(group)
            layout = .first(inner)
            return .first(prepaint)
        case (.second(var group), .second(var inner)):
            let prepaint = group.prepaintGroup(under: parent, layout: &inner, pass: &pass)
            self = .second(group)
            layout = .second(inner)
            return .second(prepaint)
        default:
            preconditionFailure(Self.mismatch)
        }
    }

    public mutating func paintGroup(under parent: GlobalElementID?, layout: inout Layout,
                                    prepaint: inout Prepaint, pass: inout PaintPass) {
        switch (self, layout, prepaint) {
        case (.first(var group), .first(var innerLayout), .first(var innerPrepaint)):
            group.paintGroup(under: parent, layout: &innerLayout,
                             prepaint: &innerPrepaint, pass: &pass)
            self = .first(group)
            layout = .first(innerLayout)
            prepaint = .first(innerPrepaint)
        case (.second(var group), .second(var innerLayout), .second(var innerPrepaint)):
            group.paintGroup(under: parent, layout: &innerLayout,
                             prepaint: &innerPrepaint, pass: &pass)
            self = .second(group)
            layout = .second(innerLayout)
            prepaint = .second(innerPrepaint)
        default:
            preconditionFailure(Self.mismatch)
        }
    }

    /// Reachable only by handing one `EitherGroup` a phase state produced by a
    /// **different** `EitherGroup` value.
    ///
    /// That is the mechanism, not a milestone: no phase here changes which case
    /// `self` holds — each writes back the case it matched — and a container
    /// threads the state it received back into the same stored child, so within
    /// one frame the two cases are the same by construction. The trap exists
    /// because the alternative is silently painting nothing.
    private static var mismatch: String {
        "EitherGroup phase state came from a different EitherGroup value than the one painting it"
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

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], [Group.GroupLayout]) {
        var nodes: [LayoutNodeID] = []
        var layouts: [Group.GroupLayout] = []
        layouts.reserveCapacity(groups.count)
        for index in groups.indices {
            let (childNodes, childLayout) = groups[index].requestGroupLayout(under: parent,
                                                                            pass: &pass)
            nodes.append(contentsOf: childNodes)
            layouts.append(childLayout)
        }
        return (nodes, layouts)
    }

    public mutating func prepaintGroup(under parent: GlobalElementID?,
                                       layout: inout [Group.GroupLayout],
                                       pass: inout PrepaintPass) -> [Group.GroupPrepaint] {
        precondition(layout.count == groups.count, Self.countMismatch)
        var prepaints: [Group.GroupPrepaint] = []
        prepaints.reserveCapacity(groups.count)
        for index in groups.indices {
            prepaints.append(groups[index].prepaintGroup(under: parent,
                                                         layout: &layout[index], pass: &pass))
        }
        return prepaints
    }

    public mutating func paintGroup(under parent: GlobalElementID?,
                                    layout: inout [Group.GroupLayout],
                                    prepaint: inout [Group.GroupPrepaint],
                                    pass: inout PaintPass) {
        precondition(layout.count == groups.count && prepaint.count == groups.count,
                     Self.countMismatch)
        for index in groups.indices {
            groups[index].paintGroup(under: parent, layout: &layout[index],
                                     prepaint: &prepaint[index], pass: &pass)
        }
    }

    /// Same mechanism as `EitherGroup.mismatch`: the arrays are produced by this
    /// value's own `requestGroupLayout` and threaded back unmodified, so a
    /// differing count means the states came from a different `ArrayGroup`.
    private static var countMismatch: String {
        "ArrayGroup phase state has a different member count than the group painting it"
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
        var id: GlobalElementID?
        var node: LayoutNodeID
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], GroupLayout) {
        let id = GlobalElementID.child(of: parent, elementID)
        let node = requestLayout(id, pass: &pass)
        return ([node], GroupLayout(id: id, node: node))
    }

    public mutating func prepaintGroup(under parent: GlobalElementID?,
                                       layout: inout GroupLayout,
                                       pass: inout PrepaintPass) {
        prepaint(layout.id, bounds: pass.bounds(of: layout.node), pass: &pass)
    }

    public mutating func paintGroup(under parent: GlobalElementID?, layout: inout GroupLayout,
                                    prepaint: inout Void, pass: inout PaintPass) {
        paint(layout.id, bounds: pass.bounds(of: layout.node), pass: &pass)
    }
}
