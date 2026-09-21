// TYPECHECK SKELETON (not a SwiftUI probe): can a typed native node id with no
// public initializer, returned by a protocol requirement, make the compiler
// reject a `ProposalElementGroup` conformer that registers a legacy node?
// Evidence for ruling MC-G in
// docs/superpowers/2026-09-15-modifier-composition-decisions.md (plan task 3's
// open proof carried by SA-R). A two-module model of MetalUI's element
// protocols: this file is module `Kit`; each `typed-client-*.swift` is a
// separate module that imports it PLAINLY (no @testable), as an external
// author would (SA-P's instrument rule).
//
// HOW TO RUN, from this directory, with an output directory of your choice:
//
//   OUT=$(mktemp -d)
//   xcrun swiftc -swift-version 6 -parse-as-library -emit-module -emit-library \
//       -module-name Kit TypedNodeKit.swift -emit-module-path $OUT/Kit.swiftmodule -o $OUT/libKit.dylib
//   for f in typed-client-*.swift; do echo "== $f"; \
//       xcrun swiftc -swift-version 6 -typecheck -I $OUT $f 2>&1 | grep error: | head -1; done
//
// RECORDED 2026-09-15 by the modifier-composition design session, macOS 26.6.2,
// Swift 6 mode. The first recording named "xcrun swiftc = Apple Swift 6.3.3";
// at design review the same day `xcrun swiftc` reported Apple Swift 6.4
// (swiftlang-6.4.0.33.1) and PATH `swiftc` (swiftly) 6.3.3, so which one the
// first run used is not established. RE-RUN under BOTH at design review: the
// eight results below are identical under each. CombinedKit.swift repeats them
// with lane 2's `LayerBase` added:
//
//   honest    exit 0 (a leaf, a container over a Pair, a Component retro-conformed)
//   liar1     error: type 'Liar' does not conform to protocol 'ProposalElementGroup'
//             (today's marker liar: Element + marker, legacy node, no typed entry)
//   liar2     error: 'ProposalNodeID' initializer is inaccessible due to 'internal' protection level
//   liar3     error: type 'LegacyComp' does not conform to protocol 'ProposalElementGroup'
//             (a Component whose content is legacy)
//   liar4     exit 0 -- THE RESIDUAL HOLE: a group that writes both entry points
//             itself, legacy nodes from one and zero typed nodes from the other
//   liar5     error: generic struct 'ProposalFrame' requires that 'Legacy' conform to 'ProposalElementGroup'
//   opaque    error: type 'OpaqueComp' does not conform to protocol 'ProposalElementGroup'
//             (`var content: some ElementGroup` hides that the content is proposal)
//   opaqueOK  exit 0 (`some ProposalElementGroup`; and `Both`, a ProposalElement that
//             ALSO overrides the legacy `requestLayout`, compiles -- second hole)
//
// A FINDING THE DESIGN DEPENDS ON: `ProposalElement` must RESTATE
// `associatedtype LayoutState`. Without that line this file itself fails to
// build: "error: type 'Leaf' does not conform to protocol 'Element'" (and the
// same for 'ProposalFrame<Content>'), because Swift does not infer Element's
// `LayoutState` through the default `requestLayout` that ProposalElement's
// extension provides.

public struct LayoutNodeID: Hashable, Sendable { let index: Int; init(_ i: Int) { index = i } }
public struct GlobalElementID: Hashable { let path: [Int]
  static func child(of p: GlobalElementID?, at i: Int) -> GlobalElementID { GlobalElementID(path: (p?.path ?? []) + [i]) } }

/// Typed native node id: only LayoutPass's proposal registrars mint one.
public struct ProposalNodeID: Hashable, Sendable {
    public let layoutNodeID: LayoutNodeID
    init(_ id: LayoutNodeID) { layoutNodeID = id }
}

public struct LayoutPass {
    var next = 0
    init() {}
    public mutating func requestNode(children: [LayoutNodeID]) -> LayoutNodeID { next += 1; return LayoutNodeID(next) }
    public mutating func requestNativeLeaf() -> ProposalNodeID { next += 1; return ProposalNodeID(LayoutNodeID(next)) }
    public mutating func requestNativeFrame(child: ProposalNodeID) -> ProposalNodeID { next += 1; return ProposalNodeID(LayoutNodeID(next)) }
}

@MainActor public protocol ElementGroup {
    associatedtype GroupLayout
    mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass) -> ([LayoutNodeID], GroupLayout)
}
@MainActor public protocol Element: ElementGroup {
    associatedtype LayoutState
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, LayoutState)
}
public struct SingleElementLayout<E: Element> { var id: GlobalElementID; var node: LayoutNodeID; var state: E.LayoutState }
extension Element {
    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass) -> ([LayoutNodeID], SingleElementLayout<Self>) {
        let id = GlobalElementID.child(of: parent, at: cursor); cursor += 1
        let (n, s) = requestLayout(id, pass: &pass)
        return ([n], SingleElementLayout(id: id, node: n, state: s))
    }
}

public protocol ProposalElementGroup: ElementGroup {
    mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass) -> ([ProposalNodeID], GroupLayout)
}
public protocol ProposalElement: Element, ProposalElementGroup {
    associatedtype LayoutState
    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, LayoutState)
}
extension ProposalElement {
    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, LayoutState) {
        let (n, s) = requestProposalLayout(id, pass: &pass); return (n.layoutNodeID, s)
    }
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass) -> ([ProposalNodeID], SingleElementLayout<Self>) {
        let id = GlobalElementID.child(of: parent, at: cursor); cursor += 1
        let (n, s) = requestProposalLayout(id, pass: &pass)
        return ([n], SingleElementLayout(id: id, node: n.layoutNodeID, state: s))
    }
}

public struct Pair<First: ElementGroup, Second: ElementGroup>: ElementGroup {
    public var first: First; public var second: Second
    public init(_ a: First, _ b: Second) { first = a; second = b }
    public struct Layout { var a: First.GroupLayout; var b: Second.GroupLayout }
    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        let (x, lx) = first.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        let (y, ly) = second.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (x + y, Layout(a: lx, b: ly))
    }
}
extension Pair: ProposalElementGroup where First: ProposalElementGroup, Second: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass) -> ([ProposalNodeID], Layout) {
        let (x, lx) = first.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        let (y, ly) = second.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (x + y, Layout(a: lx, b: ly))
    }
}

public protocol Component: ElementGroup { associatedtype Content: ElementGroup; var content: Content { get } }
public struct ComponentLayout<C: Component> { var content: C.Content; var layout: C.Content.GroupLayout }
extension Component {
    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass) -> ([LayoutNodeID], ComponentLayout<Self>) {
        let id = GlobalElementID.child(of: parent, at: cursor); cursor += 1
        var c = content; var inner = 0
        let (n, l) = c.requestGroupLayout(under: id, at: &inner, pass: &pass)
        return (n, ComponentLayout(content: c, layout: l))
    }
}
extension Component where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass) -> ([ProposalNodeID], ComponentLayout<Self>) {
        let id = GlobalElementID.child(of: parent, at: cursor); cursor += 1
        var c = content; var inner = 0
        let (n, l) = c.requestProposalGroupLayout(under: id, at: &inner, pass: &pass)
        return (n, ComponentLayout(content: c, layout: l))
    }
}

public struct Leaf: ProposalElement {
    public init() {}
    public mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) { (pass.requestNativeLeaf(), ()) }
}
public struct Legacy: Element {
    public init() {}
    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) { (pass.requestNode(children: []), ()) }
}
public struct ProposalFrame<Content: ProposalElementGroup>: ProposalElement {
    public var content: Content
    public init(_ c: Content) { content = c }
    public mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Content.GroupLayout) {
        var cursor = 0
        let (children, l) = content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        return (pass.requestNativeFrame(child: children[0]), l)
    }
}
