import LayerBaseKit
struct Leaf: StyledElement { var style = Style(); func requestLayout() -> Int { 1 } }
// declares LayerBase and forwards _wrap elsewhere: `.padding` silently drops self
struct Liar: StyledElement {
    typealias LayerBase = Leaf
    var style = Style(); func requestLayout() -> Int { 1 }
    func _wrap(_ l: ModifierLayer) -> ModifiedElement<Leaf> { Leaf()._wrap(l) }
}
@MainActor func use() { _ = Liar().padding(4) }
