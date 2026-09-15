// TYPECHECK SKELETON (not a SwiftUI probe): do lane 2's `ElementGroup.LayerBase`
// (MC-A as revised) and lane 3's typed native node id (MC-G) coexist on ONE
// `ElementGroup`? TypedNodeKit.swift with LayerBaseKit.swift's associated type,
// `_wrap` requirement, `ModifiedElement` and one `padding` overload spliced into
// it (the splice is mechanical: everything below `LayoutNodeID` is
// TypedNodeKit's, with the protocol body and the four declarations after it
// added). Written at design review (ruling MC-N, findings 1 and 8).
//
// HOW TO RUN, from this directory:
//
//   OUT=$(mktemp -d)
//   xcrun swiftc -swift-version 6 -parse-as-library -emit-module -emit-library \
//       -module-name Kit CombinedKit.swift -emit-module-path $OUT/Kit.swiftmodule -o $OUT/libKit.dylib
//   for f in typed-client-*.swift combined-client-layered.swift; do echo "== $f"; \
//       xcrun swiftc -swift-version 6 -typecheck -I $OUT $f 2>&1 | grep error: | head -1; done
//
// RECORDED 2026-09-15, macOS 26.6.2, xcrun swiftc = Apple Swift 6.4
// (swiftlang-6.4.0.33.1), Swift 6 mode. Kit build exit 0. Every
// `typed-client-*` printed exactly TypedNodeKit.swift's recorded diagnostic
// (honest, liar4, opaqueOK: none; liar1, liar3, opaque: "does not conform to
// protocol 'ProposalElementGroup'"; liar2: "'ProposalNodeID' initializer is
// inaccessible due to 'internal' protection level"; liar5: "generic struct
// 'ProposalFrame' requires that 'Legacy' conform to 'ProposalElementGroup'"),
// and `combined-client-layered` (a legacy element, a proposal Component and a
// ProposalElement each taking two chained `padding`s, stored under the flat
// type) typechecked with no diagnostic.
//
// So `ProposalElement` needs NO second restated associated type for
// `LayerBase`: its default `Self` resolves without inference. TypedNodeKit's
// `LayoutState` restatement is still required and is still here.
//
// TypedNodeKit.swift itself was also re-run the same day under both
// `xcrun swiftc` (6.4) and PATH `swiftc` (swift.org 6.3.3): same eight results.

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
    associatedtype LayerBase: ElementGroup = Self
    func _wrap(_ layer: ModifierLayer) -> ModifiedElement<LayerBase>
}
public struct ModifierLayer: Sendable { var padding: Double; init(padding: Double) { self.padding = padding } }
public struct ModifiedElement<Content: ElementGroup>: Element {
    public typealias LayerBase = Content
    public var content: Content
    var outermost: ModifierLayer
    var inner: [ModifierLayer]
    init(content: Content, layer: ModifierLayer) { self.content = content; outermost = layer; inner = [] }
    public var layerCount: Int { inner.count + 1 }
    public func _wrap(_ l: ModifierLayer) -> ModifiedElement<Content> { var c = self; c.inner.append(c.outermost); c.outermost = l; return c }
    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Content.GroupLayout) {
        var cursor = 0
        var node: LayoutNodeID
        let (children, l) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        node = pass.requestNode(children: children)
        for _ in inner { node = pass.requestNode(children: [node]) }
        return (node, l)
    }
}
extension ElementGroup where LayerBase == Self {
    public func _wrap(_ l: ModifierLayer) -> ModifiedElement<Self> { ModifiedElement(content: self, layer: l) }
}
extension ElementGroup {
    public func padding(_ p: Double) -> ModifiedElement<LayerBase> { _wrap(ModifierLayer(padding: p)) }
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
