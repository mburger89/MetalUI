import LayerBaseKit
struct Leaf: StyledElement { var style = Style(); func requestLayout() -> Int { 1 } }
@MainActor func use() { _ = ModifiedElement(content: Leaf(), layer: ModifierLayer(style: Style())) }
