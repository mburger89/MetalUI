import LayerBaseKit
struct Leaf: StyledElement { var style = Style(); func requestLayout() -> Int { 1 } }
@MainActor func wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T> { t.padding(8) }
