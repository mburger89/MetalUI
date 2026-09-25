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
/// what lets an unnamed element hold state at all. ("Anonymous" was the old
/// rule's word for an element with *no* identity; there is no such element any
/// more, so this file says "unnamed".)
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
/// **Releasing a chain is recursive, and that is bounded by layout rather than by
/// anything here.** Dropping the last reference to a leaf id releases its parent
/// from `deinit`, which releases *its* parent, so a pathological depth would
/// overflow the stack at teardown. The mechanism that keeps it theoretical is
/// `NativeLayoutRun.maxDepth` (72 native levels; the CSS engine's
/// `LayoutContext.maxDepth`, 64, until stage 9): identity depth is
/// element-container nesting plus one level per enclosing `if` (with or without
/// `else`) and per enclosing `for` loop (plan task 8, ruling `ID-B`: each takes
/// one slot and numbers its content inside it), and the
/// kernel traps on the nesting long before a release chain matters. Worth knowing because
/// "one allocation per child regardless of depth" says nothing about the other
/// end.
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
    /// **What no test can guard is the HASH-SHORTCUT spelling — not the loop.**
    /// The distinction matters and this comment was over-broad without it:
    /// losing the chain walk outright is caught, loudly. Measured, `--no-parallel`
    /// — edit: replace this whole body with `return l.component == r.component`
    /// — `pathsDifferingOnlyInAnAncestorAreNotEqual` and
    /// `differentDepthsWithTheSameTailAreNotEqual` fail, and then the process
    /// **traps**: `Fatal error: Duplicate elements of type 'GlobalElementID'
    /// were found in a Set.` So that mutation has no reproducible count at all —
    /// it is a truncated run with **no summary line**, taxonomy shape 11, and two
    /// runs of it reported four failing names and three. Loud, but not a number.
    ///
    /// The unguardable spelling is the *other* one. Replacing
    /// this body with `l.cachedHash == r.cachedHash` is wrong only on a genuine
    /// 64-bit collision, and a collision is not constructible in a test:
    /// `Hasher` is seeded per process, so one cannot be written down, and
    /// searching for one is ~2^32 trials. Measured four times as the suite grew
    /// around it — 349, 356, 358, **360** (`--no-parallel`, 2026-08-27) —
    /// and that replacement leaves the whole suite green every time, summary line
    /// and all. The count moved twice and the finding did not. That is the
    /// contrast: a wrong `==` that keeps the hash good is silent, and a wrong
    /// `==` that discards the chain is a process trap. The guard is this loop
    /// existing, and
    /// universal identity makes it *more* load-bearing, not less: every node has
    /// a key now, so a collision is a shared `StateTable` entry between two
    /// arbitrary elements. Do not delete it on the
    /// evidence of a green suite — that is what shape 6 in
    /// `docs/practices/verifying-tests-can-fail.md` is about.
    ///
    /// **The condition is a combination, not this line alone.** A hash-shortcut
    /// `==` is safe exactly while the hash is good; a degraded hash is safe
    /// exactly while `==` walks the chain. Dropping the parent from
    /// `cachedHash` alone (leaving this loop intact) — edit:
    /// delete `hasher.combine(parent?.cachedHash ?? 0)` from `init` — reddens
    /// exactly one test out of 360 (`--no-parallel`, 2026-08-27, re-measured
    /// after the two index tests landed),
    /// `theHashItselfDistinguishesPathsDifferingOnlyInAnAncestor` —
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
