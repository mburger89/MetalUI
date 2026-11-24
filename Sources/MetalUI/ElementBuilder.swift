/// Builds a container's children while **preserving their concrete types**
/// (spec §4.6, allocation mitigation 1).
///
/// ```swift
/// Column { Label("Nodes"); Button("Compile") }   // Column<TupleGroup<Label, Button>>
/// ```
///
/// **The static path boxes nothing, and that is the whole point of this type.**
/// A builder whose methods returned `[AnyElement]` would be a two-line change,
/// would compile, and would pass every layout and paint assertion in the repo —
/// mitigation 1 would be silently gone with nothing red. So the guards are
/// *type-level*: three tests in `ElementLayoutTests.swift` assert on
/// `type(of:)`, and they are the only kind of test that can see the difference.
/// Measured once: adding **both** `buildExpression<E: Element>(_:) -> AnyElement` and
/// `buildExpression(_ e: AnyElement) -> AnyElement` here reddened exactly those
/// three and no behavioural test at all (out of 303, then 358 after structural
/// identity). **That reading is stale (R4-1a, record 201).** Re-run on the
/// current tree the pair no longer reaches the tests: `Sources/MetalUI/PullDownMenu.swift:45`
/// fails to compile (`cannot convert value of type 'Label' to expected argument
/// type 'AnyElement'`), so the compiler is now the guard. The claim it
/// carried, "`AnyElement` consumes one cursor index like `Element`'s default, so
/// boxing every child moves no path and no `StateTable` entry", is **refuted**:
/// an erased child runs one `$erased` level below its position (`ER-A`), so
/// everything it registers moves one level, and a type-keyed reset would apply
/// to every boxed child.
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
/// Every method here returns a distinct concrete type — `TupleGroup`, `OptionalGroup`,
/// `EitherGroup`, `ArrayGroup`, `EmptyGroup` — so `if`, `if`/`else` and `for`
/// stay unboxed too. `AnyElement` is reachable only by writing it out (§4.6).
///
/// **Every method samples `StackMeter`** (ruling `PE-L` item 2): a builder
/// method runs inside the `content` getter or closure that holds a tree's
/// temporaries, so its sample sees that frame — a layout-time sample cannot,
/// because the getter has returned before its children register. A sample is
/// a no-op outside a measurement, off the main thread and in release builds.
///
/// `buildBlock<each Group>` rather than `buildPartialBlock` (ruling `PE-AB`, Sift gap G17): the block's members
/// are one parameter pack, stored once in a `TupleGroup`'s tuple, the way SwiftUI's `ViewBuilder` makes a
/// `TupleView`. A partial-block chain made one intermediate `Pair<Pair<…>>` per statement, and at `-Onone` each held
/// the whole prefix in a stack slot of its own, so a closure's frame grew with the square of its child count.
/// `TupleGroup` visits its members in source order with one cursor, so every id, path and phase order is what the
/// chain gave. **The compiler prefers `buildPartialBlock` whenever a builder declares it**, so none may be added back.
@MainActor
@resultBuilder
public enum ElementBuilder {
    /// `Box { }` — a container with no children.
    public static func buildBlock() -> EmptyGroup { StackMeter.sample(); return EmptyGroup() }

    /// One statement, unchanged: a single child gets no wrapper.
    public static func buildBlock<Group: ElementGroup>(_ group: Group) -> Group {
        StackMeter.sample()
        return group
    }

    /// Two or more statements, in source order, as one `TupleGroup`. One parameter pack rather than a
    /// `buildPartialBlock` chain: the chain's intermediate `Pair<Pair<…>>` values each took a stack slot holding the
    /// whole prefix at `-Onone`, so a closure's frame grew with the square of its child count (Sift G17).
    public static func buildBlock<each Group: ElementGroup>(_ groups: repeat each Group)
        -> TupleGroup<repeat each Group> {
        StackMeter.sample()
        return TupleGroup(repeat each groups)
    }

    /// `if` with no `else`.
    public static func buildOptional<Group: ElementGroup>(
        _ group: Group?
    ) -> OptionalGroup<Group> {
        StackMeter.sample()
        return OptionalGroup(builder: group)
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
