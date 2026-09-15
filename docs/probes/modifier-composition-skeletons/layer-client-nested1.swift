import LayerBaseKit
struct Leaf: StyledElement { var style = Style(); func requestLayout() -> Int { 1 } }
@MainActor func use() { let _: ModifiedElement<ModifiedElement<Leaf>> = Leaf().padding(4).padding(8) }
