/// Builds a container's children while **preserving their concrete types**
/// (spec §4.6, allocation mitigation 1).
///
/// ```swift
/// Column { Label("Nodes"); Button("Compile") }   // Column<Pair<Label, Button>>
/// ```
///
/// **The static path boxes nothing, and that is the whole point of this type.**
/// A builder whose methods returned `[AnyElement]` would be a two-line change,
/// would compile, and would pass every layout and paint assertion in the repo —
/// mitigation 1 would be silently gone with nothing red. So the guards are
/// *type-level*: three tests in `ElementLayoutTests.swift` assert on
/// `type(of:)`, and they are the only kind of test that can see the difference.
/// Measured: adding **both** `buildExpression<E: Element>(_:) -> AnyElement` and
/// `buildExpression(_ e: AnyElement) -> AnyElement` here reddens exactly those
/// three and no behavioural test at all — re-measured `--no-parallel` after
/// structural identity, **out of 358** rather than the 303 first recorded, and
/// the three are the same three. Universal identity does not change that, and
/// the reason is that `AnyElement`'s `requestGroupLayout` consumes exactly one
/// cursor index like `Element`'s default does, so boxing every child moves no
/// path and no `StateTable` entry.
///
/// **The second overload is not optional, and the generic one alone is no longer
/// a measurable mutation.** `anExplicitAnyElementIsStillAcceptedAsAChild` puts an
/// `AnyElement` inside a builder block, so `buildExpression<E: Element>` on its
/// own demands `AnyElement: Element` — which it is not — and the suite fails to
/// *compile* rather than turning red: `error: static method 'buildExpression'
/// requires that 'AnyElement' conform to 'Element'`. That is a stronger guard
/// than the measurement assumed, but it measures nothing, so a boxing mutation
/// has to give the type checker the non-generic path as well.
///
/// Every method here returns a distinct concrete type — `Pair`, `OptionalGroup`,
/// `EitherGroup`, `ArrayGroup`, `EmptyGroup` — so `if`, `if`/`else` and `for`
/// stay unboxed too. `AnyElement` is reachable only by writing it out (§4.6).
///
/// **Every method samples `StackMeter`** (ruling `PE-L` item 2): a builder
/// method runs inside the `content` getter or closure that holds a tree's
/// temporaries, so its sample sees that frame — a layout-time sample cannot,
/// because the getter has returned before its children register. A sample is
/// a no-op outside a measurement, off the main thread and in release builds.
///
/// `buildPartialBlock` rather than a ladder of `buildBlock` overloads: it gives
/// unbounded arity from two methods, and the left-nested `Pair<Pair<A, B>, C>`
/// it produces flattens back to source order because `Pair` always visits
/// `first` before `second`.
@MainActor
@resultBuilder
public enum ElementBuilder {
    /// `Box { }` — a container with no children.
    public static func buildBlock() -> EmptyGroup { StackMeter.sample(); return EmptyGroup() }

    /// A block's first statement, unchanged.
    public static func buildPartialBlock<Group: ElementGroup>(first: Group) -> Group {
        StackMeter.sample()
        return first
    }

    /// Folds the next statement onto the ones before it as a left-nested
    /// `Pair`, so node order is source order.
    public static func buildPartialBlock<Accumulated: ElementGroup, Next: ElementGroup>(
        accumulated: Accumulated, next: Next
    ) -> Pair<Accumulated, Next> {
        StackMeter.sample()
        return Pair(accumulated, next)
    }

    /// `if` with no `else`.
    public static func buildOptional<Group: ElementGroup>(
        _ group: Group?
    ) -> OptionalGroup<Group> {
        StackMeter.sample()
        return OptionalGroup(group)
    }

    /// The `if` branch of an `if`/`else`.
    public static func buildEither<First: ElementGroup, Second: ElementGroup>(
        first: First
    ) -> EitherGroup<First, Second> {
        StackMeter.sample()
        return .first(first)
    }

    /// The `else` branch of an `if`/`else`.
    public static func buildEither<First: ElementGroup, Second: ElementGroup>(
        second: Second
    ) -> EitherGroup<First, Second> {
        StackMeter.sample()
        return .second(second)
    }

    /// `for … in …`.
    ///
    /// **A loop body that calls a helper returning `some …` does not compile**
    /// ("underlying type for opaque result type … could not be inferred"): the
    /// Swift 6.4 builder transform types the loop's accumulator before this
    /// method is consulted, so no spelling of it can help (ruling `KF-M`,
    /// probe `docs/probes/swift-builder-for-opaque.sh`, guard
    /// `aForLoopOverAnOpaqueHelperIsAToolchainLimitation`). Write
    /// `ForEach(items, id: \.self) { helper($0) }`, a helper returning a
    /// concrete type, or the chain inline.
    public static func buildArray<Group: ElementGroup>(_ groups: [Group]) -> ArrayGroup<Group> {
        StackMeter.sample()
        return ArrayGroup(groups)
    }
}
