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
/// Measured: adding `buildExpression<E: Element>(_:) -> AnyElement` here reddens
/// exactly those three and no behavioural test at all, out of 261.
///
/// Every method here returns a distinct concrete type — `Pair`, `OptionalGroup`,
/// `EitherGroup`, `ArrayGroup`, `EmptyGroup` — so `if`, `if`/`else` and `for`
/// stay unboxed too. `AnyElement` is reachable only by writing it out (§4.6).
///
/// `buildPartialBlock` rather than a ladder of `buildBlock` overloads: it gives
/// unbounded arity from two methods, and the left-nested `Pair<Pair<A, B>, C>`
/// it produces flattens back to source order because `Pair` always visits
/// `first` before `second`.
@MainActor
@resultBuilder
public enum ElementBuilder {
    /// `Box { }` — a container with no children.
    public static func buildBlock() -> EmptyGroup { EmptyGroup() }

    public static func buildPartialBlock<Group: ElementGroup>(first: Group) -> Group { first }

    public static func buildPartialBlock<Accumulated: ElementGroup, Next: ElementGroup>(
        accumulated: Accumulated, next: Next
    ) -> Pair<Accumulated, Next> {
        Pair(accumulated, next)
    }

    /// `if` with no `else`.
    public static func buildOptional<Group: ElementGroup>(
        _ group: Group?
    ) -> OptionalGroup<Group> {
        OptionalGroup(group)
    }

    /// The `if` branch of an `if`/`else`.
    public static func buildEither<First: ElementGroup, Second: ElementGroup>(
        first: First
    ) -> EitherGroup<First, Second> {
        .first(first)
    }

    /// The `else` branch of an `if`/`else`.
    public static func buildEither<First: ElementGroup, Second: ElementGroup>(
        second: Second
    ) -> EitherGroup<First, Second> {
        .second(second)
    }

    /// `for … in …`.
    public static func buildArray<Group: ElementGroup>(_ groups: [Group]) -> ArrayGroup<Group> {
        ArrayGroup(groups)
    }
}
