// TYPECHECK SKELETON (not a SwiftUI probe): MC-A AS REVISED at design review
// (finding 1, ruling MC-N). ONE `padding` / `frame` overload each, returning
// `ModifiedElement<LayerBase>` through an associated type on `ElementGroup`
// (default `Self`; `ModifiedElement` sets it to its `Content`), dispatched
// through a `_wrap` requirement. This replaces FlatChainOverloads.swift's
// concrete redeclarations, whose type-checking time grows exponentially with
// chain length (chain-typecheck-timing.py). A two-module model: this file is
// module `LayerBaseKit`; each `layer-client-*.swift` imports it PLAINLY.
//
// HOW TO RUN, from this directory:
//
//   OUT=$(mktemp -d)
//   xcrun swiftc -swift-version 6 -parse-as-library -emit-module -emit-library \
//       -module-name LayerBaseKit LayerBaseKit.swift \
//       -emit-module-path $OUT/LayerBaseKit.swiftmodule -o $OUT/libLayerBaseKit.dylib
//   xcrun swiftc -swift-version 6 -I $OUT -L $OUT -lLayerBaseKit -Xlinker -rpath -Xlinker $OUT \
//       layer-client-honest.swift -o $OUT/honest && $OUT/honest
//   for f in layer-client-nested1 layer-client-nested2 layer-client-mint layer-client-liar; do
//     echo "== $f"; xcrun swiftc -swift-version 6 -typecheck -I $OUT $f.swift 2>&1 | grep error: | head -1; done
//
// RECORDED 2026-09-15, macOS 26.6.2, xcrun swiftc = Apple Swift 6.4
// (swiftlang-6.4.0.33.1), Swift 6 mode. Kit build exit 0.
//
//   honest   exit 0, stdout:
//              ModifiedElement<Leaf> 3        Leaf().padding(4).frame(width: 60).padding(8).width(70)
//              ModifiedElement<Comp> 2        a Component's .frame(width:).padding(_:)
//              ModifiedElement<Group<Leaf>> 1 an external generic ElementGroup's .frame
//              Row<ModifiedElement<Leaf>>     a stored `let` spelled with the flat type
//              ModifiedElement<Leaf> 1 ModifiedElement<Leaf> 2
//                                             `wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T.LayerBase>`
//                                             over a plain leaf, then over a one-layer chain:
//                                             the generic call APPENDS (dynamic dispatch through _wrap)
//              ModifiedContent<Rect>          the proposal `frame` overload still wins on a proposal type
//            (the second column is the layer count). External conformers that
//            never mention LayerBase or _wrap (Leaf, Group, Comp) compile.
//   nested1  error: cannot assign value of type 'ModifiedElement<ModifiedElement<Leaf>.LayerBase>'
//            (aka 'ModifiedElement<Leaf>') to type 'ModifiedElement<ModifiedElement<Leaf>>'
//   nested2  error: cannot convert return expression of type 'ModifiedElement<T.LayerBase>'
//            to return type 'ModifiedElement<T>'
//   mint     error: 'ModifiedElement<Content>' initializer is inaccessible due to 'internal' protection level
//   liar     exit 0 -- A HOLE: a conformer that declares `typealias LayerBase = Leaf` and
//            implements `_wrap` by forwarding to another value compiles, and its `.padding`
//            silently drops the receiver. `_wrap` is underscored and documented as not for
//            conformers; no access-control spelling closes it (a requirement is as visible
//            as its protocol).
//
// So the nested `ModifiedElement<ModifiedElement<…>>` shape that MC-B had to
// cover under the first design is UNREACHABLE outside the module: neither a
// contextual annotation (nested1) nor a generic return type (nested2) selects
// it, and the initializer is internal (mint).

public struct Pixels: ExpressibleByIntegerLiteral { var v: Float; public init(_ v: Float) { self.v = v }
  public init(integerLiteral value: Int) { v = Float(value) } }
public struct Style: Sendable { public var padding: Float = 0; public var width: Float = 0; public init() {} }

@MainActor public protocol ElementGroup {
    associatedtype GroupLayout
    func requestGroupLayout() -> GroupLayout
    /// The type a legacy wrapper modifier wraps. `Self` for every conformer
    /// except `ModifiedElement`, whose layers wrap its content.
    associatedtype LayerBase: ElementGroup = Self
    /// Framework-internal: add one outer layer. Not for conformers to implement.
    func _wrap(_ layer: ModifierLayer) -> ModifiedElement<LayerBase>
}
@MainActor public protocol Element: ElementGroup {
    associatedtype LayoutState
    func requestLayout() -> LayoutState
}
public struct SingleLayout<E: Element> { var s: E.LayoutState }
extension Element {
    public func requestGroupLayout() -> SingleLayout<Self> { SingleLayout(s: requestLayout()) }
}
public protocol StyledElement: Element { var style: Style { get set } }
public protocol ProposalElementGroup: ElementGroup {}
public protocol Component: ElementGroup { associatedtype Content: ElementGroup; var content: Content { get } }
extension Component { public func requestGroupLayout() -> Content.GroupLayout { content.requestGroupLayout() } }

public struct ModifierLayer: Sendable { var style: Style; init(style: Style) { self.style = style } }

public struct ModifiedElement<Content: ElementGroup>: StyledElement {
    public typealias LayerBase = Content
    public var content: Content
    var outermost: ModifierLayer
    var inner: [ModifierLayer]
    public var style: Style { get { outermost.style } set { outermost.style = newValue } }
    init(content: Content, layer: ModifierLayer) { self.content = content; outermost = layer; inner = [] }
    public func requestLayout() -> Int { inner.count + 1 }
    public func _wrap(_ l: ModifierLayer) -> ModifiedElement<Content> {
        var c = self; c.inner.append(c.outermost); c.outermost = l; return c
    }
    public var layerCount: Int { inner.count + 1 }
}
extension ElementGroup where LayerBase == Self {
    public func _wrap(_ l: ModifierLayer) -> ModifiedElement<Self> { ModifiedElement(content: self, layer: l) }
}
extension StyledElement {
    public func width(_ w: Pixels) -> Self { var c = self; c.style.width = w.v; return c }
    public func padding(_ p: Pixels) -> ModifiedElement<LayerBase> {
        var s = Style(); s.padding = p.v; return _wrap(ModifierLayer(style: s))
    }
}
extension ElementGroup {
    public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<LayerBase> {
        var s = Style(); s.width = width?.v ?? 0; return _wrap(ModifierLayer(style: s))
    }
}
public struct ModifiedContent<C: ProposalElementGroup>: Element, ProposalElementGroup {
    var c: C; public func requestLayout() -> Int { 0 } }
extension ProposalElementGroup {
    public func frame(width: Pixels? = nil, height: Pixels? = nil, alignment: Int = 0) -> ModifiedContent<Self> { ModifiedContent(c: self) }
}
public struct Pair<A: ElementGroup, B: ElementGroup>: ElementGroup {
    var a: A; var b: B; public init(_ a: A, _ b: B) { self.a = a; self.b = b }
    public func requestGroupLayout() -> (A.GroupLayout, B.GroupLayout) { (a.requestGroupLayout(), b.requestGroupLayout()) }
}
public struct Row<C: ElementGroup>: StyledElement {
    public var style = Style(); var c: C; public init(_ c: C) { self.c = c }
    public func requestLayout() -> C.GroupLayout { c.requestGroupLayout() }
}
public struct Rect: Element, ProposalElementGroup { public init() {}; public func requestLayout() -> Int { 0 } }
