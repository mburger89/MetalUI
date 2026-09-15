import LayerBaseKit
// external conformers that never mention LayerBase or _wrap
struct Leaf: StyledElement { var style = Style(); func requestLayout() -> Int { 1 } }
struct Group<X: ElementGroup>: ElementGroup { var x: X; func requestGroupLayout() -> X.GroupLayout { x.requestGroupLayout() } }
struct Comp: Component { var content: some ElementGroup { Pair(Leaf(), Leaf()) } }
@MainActor func wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T.LayerBase> { t.padding(8) }
@MainActor func main() {
    let a = Leaf().padding(4).frame(width: 60).padding(8).width(70)
    print(type(of: a), a.layerCount)
    let b = Comp().frame(width: 1).padding(2)
    print(type(of: b), b.layerCount)
    let c = Group(x: Leaf()).frame(width: 3)
    print(type(of: c), c.layerCount)
    let stored: Row<ModifiedElement<Leaf>> = Row(Leaf().padding(1).padding(2).padding(3))
    print(type(of: stored))
    let g1 = wrap(Leaf())                 // generic over a plain leaf
    let g2 = wrap(Leaf().padding(4))      // generic over a chain: appends dynamically
    print(type(of: g1), g1.layerCount, type(of: g2), g2.layerCount)
    print(type(of: Rect().frame(width: 1)))
}
MainActor.assumeIsolated { main() }
