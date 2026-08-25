public struct LayoutNodeID: Hashable, Sendable {
    public let index: Int
    init(_ index: Int) { self.index = index }
}

/// Structure-of-arrays node storage, reset per layout pass.
///
/// Parallel arrays rather than a class per node: the engine walks these in tight
/// loops, and `reset()` keeps capacity so a per-frame rebuild does not
/// re-allocate. Nothing here knows what a leaf actually contains — text, images
/// and app content all arrive as a `MeasureFunction` (spec §3.1).
public final class LayoutTree {
    private var styles: [Style] = []
    private var childLists: [[LayoutNodeID]] = []
    private var measures: [MeasureFunction?] = []
    private var layouts: [LayoutRect] = []

    public init() {}

    public var nodeCount: Int { styles.count }

    public func newNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID {
        styles.append(style)
        childLists.append(children)
        measures.append(nil)
        layouts.append(LayoutRect(x: 0, y: 0, width: 0, height: 0))
        return LayoutNodeID(styles.count - 1)
    }

    public func newLeaf(style: Style, measure: @escaping MeasureFunction) -> LayoutNodeID {
        let id = newNode(style: style, children: [])
        measures[id.index] = measure
        return id
    }

    public func style(_ id: LayoutNodeID) -> Style { styles[id.index] }
    public func setStyle(_ id: LayoutNodeID, _ s: Style) { styles[id.index] = s }
    public func children(_ id: LayoutNodeID) -> [LayoutNodeID] { childLists[id.index] }
    public func measure(_ id: LayoutNodeID) -> MeasureFunction? { measures[id.index] }
    public func layout(_ id: LayoutNodeID) -> LayoutRect { layouts[id.index] }
    public func setLayout(_ id: LayoutNodeID, _ r: LayoutRect) { layouts[id.index] = r }

    /// Drop every node but keep the allocated capacity.
    public func reset() {
        styles.removeAll(keepingCapacity: true)
        childLists.removeAll(keepingCapacity: true)
        measures.removeAll(keepingCapacity: true)
        layouts.removeAll(keepingCapacity: true)
    }
}
