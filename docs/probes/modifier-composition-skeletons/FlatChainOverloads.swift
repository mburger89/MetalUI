// SUPERSEDED FOR MC-A (design review, 2026-09-15, ruling MC-N finding 1). The
// overload shape below -- protocol overloads redeclared concretely on
// `ModifiedElement` -- infers the flat type, but its type-checking time grows
// exponentially with chain length: 16 modifiers took 44.9 s and 24 failed with
// "unable to type-check this expression in reasonable time"
// (chain-typecheck-timing.py). MC-A now uses ONE overload through
// `ElementGroup.LayerBase` (LayerBaseKit.swift), which also makes the nested
// shape this file's second finding reaches unspellable. Kept as the record of
// the first design; its recorded output below is still what it prints.
//
// TYPECHECK SKELETON (not a SwiftUI probe): does a FLAT legacy modifier
// wrapper keep one concrete type across a chain, given that `StyledElement`'s
// protocol-extension `padding` and `ElementGroup`'s `frame` also return
// `ModifiedElement<Self>`? Evidence for rulings MC-A and MC-B in
// docs/superpowers/2026-09-15-modifier-composition-decisions.md.
//
// HOW TO RUN:  xcrun swiftc -swift-version 6 FlatChainOverloads.swift -o $(mktemp -d)/flat && that binary
//
// RECORDED 2026-09-15, Apple Swift 6.3.3, Swift 6 mode, exit 0, stdout:
//
//   ModifiedElement<Text>
//   ModifiedElement<Two>
//   Row<ModifiedElement<Text>>
//
// i.e. WITHOUT a contextual type, `Text().padding(4).frame(width: 10).padding(8).width(3).padding(1)`
// infers the flat type (the concrete `ModifiedElement` overloads win). A SECOND
// finding, from a variant whose annotation was
// `let a: ModifiedElement<ModifiedElement<Text>> = Text().padding(4).padding(8)`:
// that ALSO typechecks (exit 0, no diagnostic) -- a contextual type selects the
// protocol overload and nests. So both shapes are reachable from ordinary
// code, and `nested()` below shows a generic context nests too. Hence MC-B:
// the flat and nested shapes must be observationally identical.

@MainActor public protocol ElementGroup {}
@MainActor public protocol Element: ElementGroup {}
public struct Style { public var padding = 0.0; public var width = 0.0; public init() {} }
public protocol StyledElement: Element { var style: Style { get set } }
public protocol ProposalElementGroup: ElementGroup {}
public protocol Component: ElementGroup {}

struct Layer { var style: Style }
public struct ModifiedElement<Content: ElementGroup>: StyledElement {
    public var content: Content
    var outermost: Layer
    var inner: [Layer]
    public var style: Style { get { outermost.style } set { outermost.style = newValue } }
    init(content: Content, layer: Layer) { self.content = content; outermost = layer; inner = [] }
    func appending(_ layer: Layer) -> Self { var c = self; c.inner.append(c.outermost); c.outermost = layer; return c }
}
extension StyledElement {
    public func width(_ w: Double) -> Self { var c = self; c.style.width = w; return c }
    public func padding(_ p: Double) -> ModifiedElement<Self> { ModifiedElement(content: self, layer: Layer(style: Style())) }
}
extension ElementGroup {
    public func frame(width: Double? = nil, height: Double? = nil) -> ModifiedElement<Self> { ModifiedElement(content: self, layer: Layer(style: Style())) }
}
extension ModifiedElement {
    public func padding(_ p: Double) -> ModifiedElement<Content> { appending(Layer(style: Style())) }
    public func frame(width: Double? = nil, height: Double? = nil) -> ModifiedElement<Content> { appending(Layer(style: Style())) }
}
public struct ModifiedContent<Content: ProposalElementGroup>: Element, ProposalElementGroup {}
extension ProposalElementGroup {
    public func frame(width: Double? = nil, height: Double? = nil) -> ModifiedContent<Self> { ModifiedContent() }
    public func padding(_ p: Double) -> ModifiedContent<Self> { ModifiedContent() }
}
public struct Text: StyledElement { public var style = Style(); public init() {} }
public struct Rect: Element, ProposalElementGroup { public init() {} }
public struct Two: Component { public init() {} }
public struct Row<C: ElementGroup>: StyledElement { public var style = Style(); var c: C; public init(_ c: C) { self.c = c } }

@MainActor func inferred() {
    let x = Text().padding(4).frame(width: 10).padding(8).width(3).padding(1)
    print(type(of: x))
    let y = Two().frame(width: 1).padding(2)
    print(type(of: y))
    let z = Row(Text().padding(1).padding(2))
    print(type(of: z))
}
@MainActor func checks() {
    let a: ModifiedElement<Text> = Text().padding(4).frame(width: 10).padding(8).width(3).padding(1)
    let b: ModifiedElement<Two> = Two().frame(width: 1).padding(2).frame(height: 3)
    let c: ModifiedContent<Rect> = Rect().frame(width: 1)
    let d: Row<ModifiedElement<Text>> = Row(Text().padding(1).padding(2))
    _ = (a, b, c, d)
}
// generic context: extension method statically dispatched through the protocol
@MainActor func generic<T: StyledElement>(_ t: T) -> ModifiedElement<T> { t.padding(1).padding(2) }
@MainActor func nested() { let _: ModifiedElement<ModifiedElement<Text>> = generic(Text().padding(1)) }

MainActor.assumeIsolated { inferred() }
