/// One component of an element's identity path (spec §4.3).
///
/// A local name, unique only among its siblings. On its own it is not an
/// identity: `GlobalElementID` is.
public struct ElementID: Hashable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
}

/// An element's identity: the **path** of `ElementID` components from the root,
/// not the local id (§4.3).
///
/// The path is what distinguishes two elements that carry the same local id
/// under different parents. A table keyed on the local id alone would let them
/// share state, and no layout or paint assertion can see that — it is the same
/// failure shape as `AnyElementBox` being a class, and it is why §4.3 specifies
/// a path.
///
/// **Anonymous elements have no identity at all, and that poisons the subtree
/// below them.** `child(of:_:)` returns `nil` when *either* the parent path or
/// the child's local id is `nil`, so an identified element beneath an
/// unidentified one gets `nil` and therefore cannot hold cross-frame state.
/// That is a deliberate choice over the alternative — letting an unidentified
/// element pass its parent's path down unchanged — which is unsafe for a
/// mechanical reason: `Element`'s phases receive exactly one `GlobalElementID?`,
/// so an element that forwarded its parent's path to its children would also be
/// *holding* that path itself, and `pass.withState` on it would read and write
/// the parent's entry. Two anonymous siblings would additionally give their
/// same-named children the same path.
///
/// The fix for both is a positional component — an index among siblings, folded
/// in where the local id is absent — which is a change to §4.3's key and is not
/// made here. Pinned by `anIdentifiedChildOfAnAnonymousParentHasNoIdentity` in
/// `StateTableTests.swift`.
public struct GlobalElementID: Hashable, Sendable {
    public var path: [ElementID]
    public init(_ path: [ElementID]) { self.path = path }

    /// The path above the outermost element: empty, and the only identity a
    /// caller may construct without a parent.
    public static let root = GlobalElementID([])

    /// The identity of a child at `component` under `parent`, or `nil` if
    /// either end is anonymous.
    ///
    /// This is the whole of path construction. `Frame.render` calls it once for
    /// the root; **every other caller is a container**, and since Task 4 those
    /// are production types: `ElementGroup`'s conformances call it once per
    /// member, so `Box`, `Column` and `Row` build their children's paths through
    /// this function rather than assembling paths themselves. Grep
    /// `child(of:` in `Sources/` for the current caller list — it was two
    /// (`Frame.render` and the probe containers in `StateTableTests.swift`)
    /// while this comment said no container existed.
    public static func child(of parent: GlobalElementID?,
                             _ component: ElementID?) -> GlobalElementID? {
        guard let parent, let component else { return nil }
        return GlobalElementID(parent.path + [component])
    }
}
