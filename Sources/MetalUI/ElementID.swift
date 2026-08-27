/// One component of an element's identity path (spec §4.3).
///
/// A local name, unique only among its siblings. On its own it is not an
/// identity: `GlobalElementID` is.
public struct ElementID: Hashable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
}

/// One component of an element's identity path (spec §4.3).
///
/// **A name replaces a position; it never joins it.** That is SwiftUI's rule and
/// the reason is reordering: inside a list keyed by id, the id *is* the identity,
/// so an item moving from index 0 to index 1 must keep its state. If the index
/// were also in the key the move would mint a new key and reset the item's
/// scroll offset, hover and animation progress — the opposite of what `.id()`
/// exists for. Where no name is given, the position is the identity, which is
/// what lets an anonymous element hold state at all.
public enum PathComponent: Hashable, Sendable {
    case positional(Int)
    case named(ElementID)
}

/// An element's identity: the path of `PathComponent`s from the root (§4.3).
///
/// **A persistent linked list, not an array, and that is a cost decision.**
/// Every element builds a path every frame. The array form
/// (`GlobalElementID(parent.path + [component])`) copies O(depth) per node, and
/// before this milestone only *named* subtrees paid it. Universal identity makes
/// every node pay it, on a hot path in a framework that rebuilds every element
/// every frame. Sharing the tail makes a child one allocation regardless of
/// depth: O(n) per frame rather than O(n·depth).
///
/// **`cachedHash` is a fast reject, never a proof of equality.** `==` walks both
/// chains. A hash-equality shortcut would let two unrelated elements share one
/// state entry — the same failure shape as content sizing's memo key shipping
/// without `containingBlockWidth`.
public final class GlobalElementID: Hashable, Sendable {
    public let component: PathComponent
    public let parent: GlobalElementID?
    private let cachedHash: Int

    public init(component: PathComponent, parent: GlobalElementID?) {
        self.component = component
        self.parent = parent
        var hasher = Hasher()
        hasher.combine(parent?.cachedHash ?? 0)
        hasher.combine(component)
        self.cachedHash = hasher.finalize()
    }

    /// The identity of a child at `index` under `parent`, named or not.
    ///
    /// **Never returns nil — this function alone.** `index` is supplied
    /// unconditionally and `name` decides the component, so the
    /// name-replaces-position rule lives here rather than at every call site.
    ///
    /// **Nil-poisoning is over.** No production caller short-circuits any more:
    /// `Frame.render` builds the root from this function and `ElementGroup`'s
    /// `requestGroupLayout` builds every descendant from it with a threaded
    /// cursor, so an unnamed element contributes `.positional(index)` rather
    /// than stopping the path. `parent` stays optional for one reason — the root
    /// genuinely has none — and that is the only `nil` this file still admits.
    public static func child(of parent: GlobalElementID?,
                             at index: Int,
                             name: ElementID?) -> GlobalElementID {
        GlobalElementID(component: name.map(PathComponent.named) ?? .positional(index),
                        parent: parent)
    }

    /// **Structural equality. `==` walks both chains; `cachedHash` is a fast
    /// reject and never a proof.**
    ///
    /// **Nothing in the suite guards this loop, and nothing can.** Replacing
    /// this body with `l.cachedHash == r.cachedHash` is wrong only on a genuine
    /// 64-bit collision, and a collision is not constructible in a test:
    /// `Hasher` is seeded per process, so one cannot be written down, and
    /// searching for one is ~2^32 trials. Re-measured after structural identity
    /// made every node build a path: that replacement still leaves the whole
    /// suite green, now **356** tests rather than the 349 first recorded — the
    /// count moved, the finding did not. The guard is this loop existing, and
    /// universal identity makes it *more* load-bearing, not less: every node has
    /// a key now, so a collision is a shared `StateTable` entry between two
    /// arbitrary elements. Do not delete it on the
    /// evidence of a green suite — that is what shape 6 in
    /// `docs/practices/verifying-tests-can-fail.md` is about.
    ///
    /// **The condition is a combination, not this line alone.** A hash-shortcut
    /// `==` is safe exactly while the hash is good; a degraded hash is safe
    /// exactly while `==` walks the chain. Dropping the parent from
    /// `cachedHash` alone (leaving this loop intact) reddens exactly one
    /// test, `theHashItselfDistinguishesPathsDifferingOnlyInAnAncestor` —
    /// every other test stays green, because `Hashable` permits collisions
    /// and `Set`/`Dictionary` resolve them through `==`, which that mutation
    /// leaves untouched. Make *this* line's change instead (or both) and
    /// nothing catches it: two unrelated elements share one `StateTable`
    /// entry with nothing above to notice.
    public static func == (l: GlobalElementID, r: GlobalElementID) -> Bool {
        if l === r { return true }
        if l.cachedHash != r.cachedHash { return false }
        var a: GlobalElementID? = l
        var b: GlobalElementID? = r
        while let x = a, let y = b {
            if x === y { return true }
            if x.component != y.component { return false }
            a = x.parent
            b = y.parent
        }
        return a == nil && b == nil
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(cachedHash) }
}
