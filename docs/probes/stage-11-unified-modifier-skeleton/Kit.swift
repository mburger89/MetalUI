// Stage 11 skeleton: ONE flat ModifiedContent<Content, Modifier>, Modifier ∈ {ModifierLayer, LayoutModifier}.
public struct Pass { public var log: [String] = []; public var next = 0; public init() {} }
public struct NodeID: Hashable { let raw: Int }
public struct PNodeID: Hashable { let node: NodeID }
public struct ID: Hashable, CustomStringConvertible { let path: [Int]; public var description: String { "\(path)" }
    public init(path: [Int]) { self.path = path } }
public struct Pixels: Sendable { public var v: Float; public init(_ v: Float) { self.v = v } }
public struct Token: Sendable { public init() {} }

@MainActor public protocol ElementGroup {
    associatedtype GroupLayout
    mutating func requestGroupLayout(under p: ID, at c: inout Int, pass: inout Pass) -> ([NodeID], GroupLayout)
    associatedtype LayerBase: ElementGroup = Self
    func _wrap(_ layer: ModifierLayer) -> ModifiedContent<LayerBase, ModifierLayer>
}
@MainActor public protocol Element: ElementGroup {
    associatedtype LayoutState
    var elementName: Int? { get }
    mutating func requestLayout(_ id: ID, pass: inout Pass) -> (NodeID, LayoutState)
}
extension Element { public var elementName: Int? { nil } }
public struct Single<E: Element> { var id: ID; var node: NodeID; var state: E.LayoutState }
extension Element {
    public mutating func requestGroupLayout(under p: ID, at c: inout Int, pass: inout Pass) -> ([NodeID], Single<Self>) {
        let id = ID(path: p.path + [elementName.map { 1000 + $0 } ?? c]); c += 1
        let (n, s) = requestLayout(id, pass: &pass)
        return ([n], Single(id: id, node: n, state: s))
    }
}
@MainActor public protocol ProposalElementGroup: ElementGroup {
    mutating func requestProposalGroupLayout(under p: ID, at c: inout Int, pass: inout Pass) -> ([PNodeID], GroupLayout)
    associatedtype ProposalBase: ProposalElementGroup = Self
    func _wrapLayout(_ m: LayoutModifier) -> ModifiedContent<ProposalBase, LayoutModifier>
}
extension ProposalElementGroup where ProposalBase == Self {
    public func _wrapLayout(_ m: LayoutModifier) -> ModifiedContent<Self, LayoutModifier> {
        ModifiedContent(content: self, outermost: m, inner: [], prefix: [])
    }
}
extension ElementGroup where LayerBase == Self {
    public func _wrap(_ layer: ModifierLayer) -> ModifiedContent<Self, ModifierLayer> {
        ModifiedContent(content: self, outermost: layer, inner: [], prefix: [])
    }
}
@MainActor public protocol ProposalElement: Element, ProposalElementGroup {
    mutating func requestProposalLayout(_ id: ID, pass: inout Pass) -> (PNodeID, LayoutState)
}
extension ProposalElement {
    public mutating func requestLayout(_ id: ID, pass: inout Pass) -> (NodeID, LayoutState) {
        let (n, s) = requestProposalLayout(id, pass: &pass); return (n.node, s)
    }
    public mutating func requestProposalGroupLayout(under p: ID, at c: inout Int, pass: inout Pass) -> ([PNodeID], Single<Self>) {
        let id = ID(path: p.path + [c]); c += 1
        let (n, s) = requestProposalLayout(id, pass: &pass)
        return ([n], Single(id: id, node: n.node, state: s))
    }
}
public protocol StyledElement: Element { var bg: Token? { get set }; var name: Int? { get set } }
extension StyledElement {
    public func background(_ t: Token) -> Self { var c = self; c.bg = t; return c }
    public func opacity(_ v: Float) -> Self { self }
    public func onClick(_ f: @escaping () -> Void) -> Self { self }
    public func id(_ n: Int) -> Self { var c = self; c.name = n; return c }
}

// MARK: the one layer protocol (constraint of the second parameter)
@MainActor public protocol ModifierLayerKind {
    var _name: Int? { get set }
    mutating func _layout(id: ID, children: [NodeID], pass: inout Pass) -> NodeID
    /// A legacy wrapper appended to a chain of this kind: the proposal prefix and
    /// the legacy layers it becomes (ruling LR-FV item 4).
    static func _legacyStack(_ o: Self, _ i: [Self], _ p: [LayoutModifier]) -> ([LayoutModifier], [ModifierLayer])
}
public struct ModifierLayer: ModifierLayerKind {
    var bg: Token?
    public var _name: Int?
    var pad: Float
    public mutating func _layout(id: ID, children: [NodeID], pass: inout Pass) -> NodeID {
        pass.next += 1; pass.log.append("legacy layer \(id) over \(children.count)"); return NodeID(raw: pass.next)
    }
}
public enum LayoutModifier: Sendable {
    case frame(width: Pixels? = nil, height: Pixels? = nil)
    case padding(Float)
    case background(Token)
    case opacity(Float)
}
extension LayoutModifier: ModifierLayerKind {
    public var _name: Int? { get { nil } set {} }
    public mutating func _layout(id: ID, children: [NodeID], pass: inout Pass) -> NodeID {
        precondition(children.count == 1)
        pass.log.append("layout layer \(id)")
        switch self { case .frame, .padding: pass.next += 1; return NodeID(raw: pass.next)
        default: return children[0] }
    }
}

public struct ModifiedContent<Content: ElementGroup, Modifier: ModifierLayerKind>: Element {
    public var content: Content
    var outermost: Modifier
    var inner: [Modifier]
    /// proposal layers absorbed when a legacy wrapper followed them (innermost)
    var prefix: [LayoutModifier]
    init(content: Content, outermost: Modifier, inner: [Modifier], prefix: [LayoutModifier]) {
        self.content = content; self.outermost = outermost; self.inner = inner; self.prefix = prefix
    }
    public typealias LayerBase = Content
    public var elementName: Int? { outermost._name }
    public struct Layout { var content: Content.GroupLayout }
    public mutating func requestLayout(_ id: ID, pass: inout Pass) -> (NodeID, Layout) {
        let depth = prefix.count + inner.count
        var ids = [id]
        var cur = id
        let names: [Int?] = prefix.map { _ in nil } + inner.map(\._name)
        for k in stride(from: depth - 1, through: 0, by: -1) {
            cur = ID(path: cur.path + [names[k].map { 1000 + $0 } ?? 0]); ids.append(cur)
        }
        var c = 0
        let (nodes, cl) = content.requestGroupLayout(under: cur, at: &c, pass: &pass)
        return (wrap(nodes, ids: ids.reversed(), pass: &pass), Layout(content: cl))
    }
    mutating func wrap(_ contentNodes: [NodeID], ids: [ID], pass: inout Pass) -> NodeID {
        var children = contentNodes
        var d = 0
        for k in prefix.indices { children = [prefix[k]._layout(id: ids[d], children: children, pass: &pass)]; d += 1 }
        for k in inner.indices { children = [inner[k]._layout(id: ids[d], children: children, pass: &pass)]; d += 1 }
        return outermost._layout(id: ids[d], children: children, pass: &pass)
    }
    public func _wrap(_ layer: ModifierLayer) -> ModifiedContent<Content, ModifierLayer> {
        let (p, legacy) = Modifier._legacyStack(outermost, inner, prefix)
        return ModifiedContent<Content, ModifierLayer>(content: content, outermost: layer, inner: legacy, prefix: p)
    }
}
extension ModifierLayer {
    public static func _legacyStack(_ o: Self, _ i: [Self], _ p: [LayoutModifier]) -> ([LayoutModifier], [ModifierLayer]) {
        (p, i + [o])
    }
}
extension LayoutModifier {
    public static func _legacyStack(_ o: Self, _ i: [Self], _ p: [LayoutModifier]) -> ([LayoutModifier], [ModifierLayer]) {
        (p + i + [o], [])
    }
}
extension ModifiedContent: StyledElement where Modifier == ModifierLayer {
    public var bg: Token? { get { outermost.bg } set { outermost.bg = newValue } }
    public var name: Int? { get { outermost._name } set { outermost._name = newValue } }
}
extension ModifiedContent: ProposalElementGroup, ProposalElement
    where Content: ProposalElementGroup, Modifier == LayoutModifier {
    public typealias ProposalBase = Content
    public func _wrapLayout(_ m: LayoutModifier) -> ModifiedContent<Content, LayoutModifier> {
        var c = self; c.inner.append(c.outermost); c.outermost = m; return c
    }
    public mutating func requestProposalLayout(_ id: ID, pass: inout Pass) -> (PNodeID, Layout) {
        let (n, l) = requestLayout(id, pass: &pass); return (PNodeID(node: n), l)
    }
    public var modifier: LayoutModifier { get { outermost } set { outermost = newValue } }
}
extension ModifiedContent where Modifier == LayoutModifier, Content: ProposalElementGroup {
    public init(content: Content, modifier: LayoutModifier) { self.init(content: content, outermost: modifier, inner: [], prefix: []) }
}
public typealias ModifiedElement<Content: ElementGroup> = ModifiedContent<Content, ModifierLayer>
@available(*, deprecated, renamed: "ModifiedContent")
public typealias NativeModifiedContent<C: ProposalElementGroup> = ModifiedContent<C, LayoutModifier>

extension ElementGroup {
    public func padding(_ p: Pixels) -> ModifiedContent<LayerBase, ModifierLayer> { _wrap(ModifierLayer(bg: nil, _name: nil, pad: p.v)) }
    public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedContent<LayerBase, ModifierLayer> {
        _wrap(ModifierLayer(bg: nil, _name: nil, pad: 0))
    }
}
extension ProposalElementGroup {
    public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.frame(width: width, height: height))
    }
    public func padding(_ e: Float) -> ModifiedContent<ProposalBase, LayoutModifier> { _wrapLayout(.padding(e)) }
    public func background(_ t: Token) -> ModifiedContent<ProposalBase, LayoutModifier> { _wrapLayout(.background(t)) }
    public func opacity(_ v: Float) -> ModifiedContent<ProposalBase, LayoutModifier> { _wrapLayout(.opacity(v)) }
}

// Overlay: its own two-subtree type, generalized to legacy content.
public struct OverlayModifier<Content: ElementGroup, Overlay: ElementGroup>: Element {
    public var content: Content
    public var overlay: Overlay
    public init(content: Content, @B overlay: () -> Overlay) { self.content = content; self.overlay = overlay() }
    public mutating func requestLayout(_ id: ID, pass: inout Pass) -> (NodeID, Void) {
        var c0 = 0; let (p, _) = content.requestGroupLayout(under: id, at: &c0, pass: &pass)
        var c1 = 0; _ = overlay.requestGroupLayout(under: ID(path: id.path + [-1]), at: &c1, pass: &pass)
        pass.log.append("overlay \(id)"); return (p[0], ())
    }
}
extension OverlayModifier: ProposalElementGroup, ProposalElement where Content: ProposalElementGroup, Overlay: ProposalElementGroup {

    public mutating func requestProposalLayout(_ id: ID, pass: inout Pass) -> (PNodeID, Void) {
        let (n, s) = requestLayout(id, pass: &pass); return (PNodeID(node: n), s)
    }
}
@resultBuilder public enum B { public static func buildBlock<C: ElementGroup>(_ c: C) -> C { c } }
extension ElementGroup {
    public func overlay<O: ElementGroup>(@B content: () -> O) -> OverlayModifier<Self, O> {
        OverlayModifier(content: self, overlay: content)
    }
}

public struct Box: StyledElement {
    public var bg: Token?; public var name: Int?
    public init() {}
    public var elementName: Int? { name }
    public mutating func requestLayout(_ id: ID, pass: inout Pass) -> (NodeID, Void) {
        pass.log.append("Box \(id)"); pass.next += 1; return (NodeID(raw: pass.next), ()) }
}
public struct Rect: ProposalElement {
    public typealias LayoutState = Void
    public init() {}
    public mutating func requestProposalLayout(_ id: ID, pass: inout Pass) -> (PNodeID, Void) {
        pass.log.append("Rect \(id)"); pass.next += 1; return (PNodeID(node: NodeID(raw: pass.next)), ()) }
}
public struct HStack<C: ProposalElementGroup>: ProposalElement {
    public typealias LayoutState = C.GroupLayout
    var c: C
    public init(@B _ c: () -> C) { self.c = c() }
    public mutating func requestProposalLayout(_ id: ID, pass: inout Pass) -> (PNodeID, C.GroupLayout) {
        var k = 0; let (n, l) = c.requestProposalGroupLayout(under: id, at: &k, pass: &pass)
        return (n.first ?? PNodeID(node: NodeID(raw: -1)), l)
    }
}
