/// The state of ONE native layout call: its measurement cache and the
/// bookkeeping the subview proxies check against.
///
/// **A `final class`, not a struct**, for the reason `LayoutContext` records:
/// a struct copied per recursion level shares no cache.
///
/// **Its lifetime is one call.** `LayoutTree.computeNativeLayout` and
/// `measureNativeLayout` each create one, mark it inactive on return and drop
/// it. The tree holds it (`activeNativeRun`) only while that call runs, so
/// `setLayout` can read `measureDepth`, and clears the reference on return: no
/// measurement can outlive the call, let alone the tree generation its keys
/// were minted in (ruling C-3's footing; ruling SA-H's clause 1).
///
/// Subview proxies (`MeasurementSubviews`, `PlacementSubviews` and their
/// elements) hold the run **strongly**, so a proxy that escapes its call
/// reaches the `isActive` precondition and its message rather than an unowned
/// read with no attribution.
final class NativeLayoutRun {
    unowned let tree: LayoutTree
    var cache: [NativeMeasurementKey: LayoutMeasurement] = [:]

    /// False once the entry point that created this run has returned. Every
    /// proxy member checks it first.
    var isActive = true

    /// The token of the innermost `placeSubviews` call in progress; 0 is none.
    /// A `PlacementSubview` may record a placement only while its own call's
    /// token is the active one (ruling SA-C).
    var activePlacement: UInt64 = 0
    var nextPlacementToken: UInt64 = 1

    /// Greater than zero while any measurement body is running: a leaf closure,
    /// a built-in case's body or a custom `sizeThatFits`. A `PlacementSubview`
    /// used while it is non-zero traps (ruling SA-C's dynamic backstop), and so
    /// does `LayoutTree.setLayout` (ruling SA-H clause 4).
    var measureDepth = 0

    init(tree: LayoutTree) { self.tree = tree }

    /// Every subview-proxy member calls this first, so a proxy that escaped
    /// its call traps with attribution instead of measuring a finished run.
    func requireActive() {
        precondition(isActive, "a layout subview outlived its layout run")
    }
}

/// One cache entry's key: a node at one proposal. Proposal equality is
/// `ProposedSize`'s synthesized `Hashable` (ruling SA-H's clause 3).
struct NativeMeasurementKey: Hashable {
    let id: LayoutNodeID
    let proposal: ProposedSize
}
