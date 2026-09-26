/// SwiftUI's `UnitPoint`: a point in a view's own unit square, `(0, 0)` its
/// top-leading corner and `(1, 1)` its bottom-trailing one (plan task 10, part
/// 1, ruling `DD-G` item 1).
///
/// **One consumer today**: `ScrollViewProxy.scrollTo(_:anchor:)`, which lands
/// the target's `anchor` point at the viewport's `anchor` point on the
/// scrolling axis (`minY − anchor.y × (viewport − height)`; probe arms T1–T3,
/// T9, T11). The cross-axis component is read by nothing — a one-axis scroller
/// has no cross-axis offset — which is SwiftUI's answer for a one-axis
/// `ScrollView` too. `Grid`'s `gridCellAnchor` still takes the nine-case
/// `ProposalAlignment`, not this (`GR-O` 4, owner plan task 11).
public struct UnitPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = UnitPoint(x: 0, y: 0)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let topLeading = UnitPoint(x: 0, y: 0)
    public static let topTrailing = UnitPoint(x: 1, y: 0)
    public static let bottomLeading = UnitPoint(x: 0, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}
