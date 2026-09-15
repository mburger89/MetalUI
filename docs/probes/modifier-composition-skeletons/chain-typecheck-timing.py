#!/usr/bin/env python3
# TYPE-CHECK-TIME PROBE (not a SwiftUI probe) for ruling MC-A in
# docs/superpowers/2026-09-15-modifier-composition-decisions.md, written after
# design-review finding 1 (MC-N). It generates one Swift file per (variant,
# chain length, argument spelling) over a base that carries the real module's
# COMPETING overloads (proposal `padding(Edges<Pixels>)`, both proposal
# `frame`s, `Component.padding`/`width`, `StyledElement.width`/`background`),
# then times the type-checking of one function body.
#
#   nested : today's `Box<Self>` / `FrameModifier<Self>`
#   flat   : MC-A AS FIRST DESIGNED -- protocol-extension overloads returning
#            `ModifiedElement<Self>`, redeclared concretely on `ModifiedElement`
#   assoc  : MC-A AS REVISED -- ONE overload each, returning
#            `ModifiedElement<LayerBase>` through `ElementGroup.LayerBase`
#
# The chain is `Text("d")` followed by n/2 pairs of
# `.padding(Pixels(i)).frame(width: Pixels(i))` ("px") or
# `.padding(i).frame(width: i)` ("int"); "demo" is a demo-shaped builder.
#
# HOW TO RUN, from a scratch directory:
#
#   for v in nested assoc flat; do
#     python3 chain-typecheck-timing.py $v 16 int > t.swift
#     xcrun swiftc -swift-version 6 -typecheck -Xfrontend -debug-time-function-bodies t.swift 2>&1 | grep probeBody
#   done
#   # inference check: xcrun swiftc -swift-version 6 t.swift -o t && ./t
#
# RECORDED 2026-09-15, macOS 26.6.2, `xcrun swiftc` = Apple Swift 6.4
# (swiftlang-6.4.0.33.1), Swift 6 mode. Milliseconds are `probeBody`'s line
# from -debug-time-function-bodies; one run each, uncontended worktree:
#
#   modifiers | px: nested  assoc   flat          | int: nested  assoc  flat
#   ----------+-------------------------------------+-----------------------------------
#       8     |     0.54    0.50    4.80          |      0.67    0.66   6.69
#      12     |     0.64    0.77    183.87        |      0.97    1.01   106.61
#      16     |     0.83    0.85    44897.85      |      1.28    1.36   1911.60
#      24     |     1.34    1.36    (not run)     |      1.86    1.99   6616.70, then
#             |                                     |      "error: the compiler is unable to type-check
#             |                                     |       this expression in reasonable time"
#   demo      |     5.87    5.95    61.84 (one builder, spelling as written)
#
# Cross-check under the swift.org toolchain (`swiftc` = Apple Swift 6.3.3,
# swift-6.3.3-RELEASE): assoc 24 px 1.57 ms, nested 24 px 1.47 ms, flat 12 px
# 196.82 ms, flat 16 int 1898.56 ms, demo assoc 6.47 ms; flat 24 int fails with
# the same "unable to type-check" error.
#
# The critic's own run of the flat shape (design review finding 1) read
# 18.6 s and then the "unable to type-check" error at 16 px; this run completed
# at 44.9 s without the error. Both are the same exponential; the exact
# threshold at which the solver gives up differs between the runs.
#
# Inference, all three variants compiled and run (exit 0), in order:
# `Text.padding(4).frame(width: 10).padding(Edges(all:)).width(3).padding(1)`,
# `Two().frame(width: 1).padding(2)`, `Two().padding(2)`, `Rectangle().frame(width: 1)`,
# `Rectangle().padding(Edges(all: Pixels(1)))`, `Row { Text.padding(1).padding(2) }`,
# the 8-modifier px body:
#   nested: Box<Box<FrameModifier<Box<Text>>>>, Box<FrameModifier<Two>>, StyledComponent<Two>,
#           ModifiedContent<Rectangle>, ModifiedContent<Rectangle>, Row<Box<Box<Text>>>,
#           FrameModifier<Box<FrameModifier<Box<FrameModifier<Box<FrameModifier<Box<Text>>>>>>>>
#   flat and assoc (identical): ModifiedElement<Text>, ModifiedElement<Two>, StyledComponent<Two>,
#           ModifiedContent<Rectangle>, ModifiedContent<Rectangle>, Row<ModifiedElement<Text>>,
#           ModifiedElement<Text>
import sys, os

variant, n, lit = sys.argv[1], int(sys.argv[2]), sys.argv[3]  # lit: px | int | demo

HEADER_COMMON = r'''
public struct Pixels: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral { var v: Float; public init(_ v: Float) { self.v = v }
  public init(integerLiteral value: Int) { v = Float(value) }; public init(floatLiteral value: Float) { v = value } }
public enum Length { case pixels(Pixels), percent(Float) }
public struct Edges<T> { public var top, right, bottom, left: T
  public init(all: T) { top = all; right = all; bottom = all; left = all }
  public init(top: T, right: T, bottom: T, left: T) { self.top = top; self.right = right; self.bottom = bottom; self.left = left } }
public struct Style { public var padding = 0.0; public var width = 0.0; public init() {} }
public enum ColorToken { case surface, accent }
public enum ProposalAlignment { case center, topLeading }
@MainActor public protocol Element: ElementGroup {}
public protocol StyledElement: Element { var style: Style { get set } }
public protocol ProposalElementGroup: ElementGroup {}
public protocol Component: ElementGroup {}
public struct Pair<A: ElementGroup, B: ElementGroup>: ElementGroup { var a: A; var b: B }
extension Pair: ProposalElementGroup where A: ProposalElementGroup, B: ProposalElementGroup {}
@resultBuilder @MainActor public enum ElementBuilder {
  public static func buildExpression<E: Element>(_ e: E) -> E { e }
  public static func buildBlock<A: ElementGroup>(_ a: A) -> A { a }
  public static func buildBlock<A: ElementGroup, B: ElementGroup>(_ a: A, _ b: B) -> Pair<A, B> { Pair(a: a, b: b) }
  public static func buildBlock<A: ElementGroup, B: ElementGroup, C: ElementGroup>(_ a: A, _ b: B, _ c: C) -> Pair<Pair<A, B>, C> { Pair(a: Pair(a: a, b: b), b: c) }
}
extension StyledElement {
  public func width(_ w: Pixels) -> Self { self }
  public func height(_ w: Pixels) -> Self { self }
  public func flexGrow(_ w: Float) -> Self { self }
  public func alignItems(_ w: Int) -> Self { self }
  public func background(_ c: ColorToken) -> Self { self }
  public func cornerRadius(_ w: Pixels) -> Self { self }
}
public struct StyledComponent<C: Component>: ElementGroup { var c: C }
extension Component {
  public func padding(_ p: Pixels) -> StyledComponent<Self> { StyledComponent(c: self) }
  public func width(_ p: Pixels) -> StyledComponent<Self> { StyledComponent(c: self) }
}
public struct ModifiedContent<C: ProposalElementGroup>: Element, ProposalElementGroup { var c: C }
extension ProposalElementGroup {
  public func padding(_ insets: Edges<Pixels>) -> ModifiedContent<Self> { ModifiedContent(c: self) }
  public func frame(width: Pixels? = nil, height: Pixels? = nil, alignment: ProposalAlignment = .center) -> ModifiedContent<Self> { ModifiedContent(c: self) }
  public func frame(minWidth: Pixels? = nil, idealWidth: Pixels? = nil, maxWidth: Pixels? = nil, minHeight: Pixels? = nil, idealHeight: Pixels? = nil, maxHeight: Pixels? = nil, alignment: ProposalAlignment = .center) -> ModifiedContent<Self> { ModifiedContent(c: self) }
  public func background(_ c: ColorToken) -> ModifiedContent<Self> { ModifiedContent(c: self) }
}
public struct Text: StyledElement { public var style = Style(); public init(_ s: String) {} }
public struct Rectangle: Element, ProposalElementGroup { public init() {} }
public struct Two: Component { public init() {} }
public struct Column<C: ElementGroup>: StyledElement { public var style = Style(); var c: C; public init(gap: Pixels = 0, @ElementBuilder _ c: () -> C) { self.c = c() } }
public struct Row<C: ElementGroup>: StyledElement { public var style = Style(); var c: C; public init(gap: Pixels = 0, @ElementBuilder _ c: () -> C) { self.c = c() } }
'''

NESTED = r'''
@MainActor public protocol ElementGroup {}
public struct Box<Content: ElementGroup>: StyledElement { public var style = Style(); var content: Content; init(content: Content) { self.content = content } }
public struct FrameModifier<Content: ElementGroup>: StyledElement { public var style = Style(); var content: Content; init(content: Content) { self.content = content } }
extension StyledElement {
  public func padding(_ p: Pixels) -> Box<Self> { Box(content: self) }
  public func padding(_ e: Edges<Length>) -> Box<Self> { Box(content: self) }
}
extension ElementGroup { public func frame(width: Pixels? = nil, height: Pixels? = nil) -> FrameModifier<Self> { FrameModifier(content: self) } }
'''

FLAT = r'''
@MainActor public protocol ElementGroup {}
struct Layer { var style: Style }
public struct ModifiedElement<Content: ElementGroup>: StyledElement {
    public var content: Content
    var outermost: Layer
    var inner: [Layer]
    public var style: Style { get { outermost.style } set { outermost.style = newValue } }
    init(content: Content) { self.content = content; outermost = Layer(style: Style()); inner = [] }
    func appending() -> Self { var c = self; c.inner.append(c.outermost); c.outermost = Layer(style: Style()); return c }
}
extension StyledElement {
  public func padding(_ p: Pixels) -> ModifiedElement<Self> { ModifiedElement(content: self) }
  public func padding(_ e: Edges<Length>) -> ModifiedElement<Self> { ModifiedElement(content: self) }
}
extension ElementGroup { public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<Self> { ModifiedElement(content: self) } }
extension ModifiedElement {
  public func padding(_ p: Pixels) -> ModifiedElement<Content> { appending() }
  public func padding(_ e: Edges<Length>) -> ModifiedElement<Content> { appending() }
  public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<Content> { appending() }
}
'''

ASSOC = r'''
@MainActor public protocol ElementGroup {
  associatedtype LayerBase: ElementGroup = Self
  func _wrap(_ layer: ModifierLayer) -> ModifiedElement<LayerBase>
}
public struct ModifierLayer { var style: Style }
public struct ModifiedElement<Content: ElementGroup>: StyledElement {
    public typealias LayerBase = Content
    public var content: Content
    var outermost: ModifierLayer
    var inner: [ModifierLayer]
    public var style: Style { get { outermost.style } set { outermost.style = newValue } }
    init(content: Content, layer: ModifierLayer) { self.content = content; outermost = layer; inner = [] }
    public func _wrap(_ l: ModifierLayer) -> ModifiedElement<Content> { var c = self; c.inner.append(c.outermost); c.outermost = l; return c }
}
extension ElementGroup where LayerBase == Self {
  public func _wrap(_ l: ModifierLayer) -> ModifiedElement<Self> { ModifiedElement(content: self, layer: l) }
}
extension StyledElement {
  public func padding(_ p: Pixels) -> ModifiedElement<LayerBase> { _wrap(ModifierLayer(style: Style())) }
  public func padding(_ e: Edges<Length>) -> ModifiedElement<LayerBase> { _wrap(ModifierLayer(style: Style())) }
}
extension ElementGroup { public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<LayerBase> { _wrap(ModifierLayer(style: Style())) } }
'''

def chain(n, lit):
    parts = []
    for i in range(1, n // 2 + 1):
        if lit == 'px':
            parts.append(f'.padding(Pixels({i})).frame(width: Pixels({i}))')
        else:
            parts.append(f'.padding({i}).frame(width: {i})')
    return 'Text("d")' + ''.join(parts)

if lit == 'demo':
    body = r'''
@MainActor func probeBody(active: Bool) -> some Element {
  Column(gap: 12) {
    Row(gap: 8) {
      Text("a").alignItems(1).flexGrow(1).padding(16).height(72).background(.surface).cornerRadius(14)
        .frame(width: 100, height: 20).padding(Edges(top: .pixels(0), right: .pixels(12), bottom: .pixels(0), left: .pixels(12))).width(420).background(active ? .surface : .accent)
      Text("b").padding(14).width(active ? 320 : 196).background(active ? .accent : .surface).cornerRadius(14).padding(4).frame(height: 3).padding(2)
      Column { Text("c").padding(20).width(360).padding(Edges(all: .pixels(8))).frame(width: 4).padding(1).padding(2).padding(3) }.flexGrow(1).padding(16).background(.surface)
    }
    .alignItems(2).flexGrow(1).padding(16).flexGrow(1).background(.surface).cornerRadius(14).padding(8).frame(width: 1, height: 2).padding(3)
    Text("d").padding(Edges(all: .pixels(1))).frame(width: 2).padding(3).frame(height: 4).padding(5).width(6).padding(7)
  }
  .alignItems(1).flexGrow(1).padding(16).background(.surface)
}
'''
else:
    body = f'''
@MainActor func probeBody(active: Bool) -> some Element {{
  {chain(n, lit)}
}}
'''

# inference checks, printed at run time
checks = r'''
@MainActor func probeInference() {
  print(type(of: Text("x").padding(4).frame(width: 10).padding(Edges(all: .pixels(8))).width(3).padding(1)))
  print(type(of: Two().frame(width: 1).padding(2)))
  print(type(of: Two().padding(2)))
  print(type(of: Rectangle().frame(width: 1)))
  print(type(of: Rectangle().padding(Edges(all: Pixels(1)))))
  print(type(of: Row { Text("y").padding(1).padding(2) }))
  print(type(of: probeBody(active: true)))
}
MainActor.assumeIsolated { probeInference() }
'''

src = {'nested': NESTED, 'flat': FLAT, 'assoc': ASSOC}[variant] + HEADER_COMMON + body + checks
sys.stdout.write(src)
