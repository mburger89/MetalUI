import Testing
import MetalUITestSupport

// Compile-time guards for lane 2 of
// `docs/superpowers/specs/2026-09-15-modifier-composition-design.md`: the
// legacy `.padding`/`.frame` chain is ONE flat `ModifiedElement<Base>` reached
// through ONE overload per modifier (ruling MC-A), and the nested
// `ModifiedElement<ModifiedElement<…>>` shape cannot be spelled from outside
// the module (ruling MC-B).
//
// **Every fixture uses `typecheckFile`**: a whole file in the Swift 6 language
// mode against a PLAIN `import MetalUI`, as an external module writes it. This
// file's own imports are irrelevant (practices shape 16); the fixture's import
// is the one that counts. Each guard prints every real diagnostic before
// asserting on it.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "When CI lands"). Both were mutated red once on a
// `--build-system native` build; the red lines are in ruling MC-A's and MC-B's
// Mutations lines and record §10.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// A legacy leaf an outside module can write: the four `StyledElement`
/// requirements and three phases, registering one engine node. It never
/// mentions `LayerBase` or `_wrap`.
private let leafSource = """
    public struct Leaf: StyledElement {
        public var style = Style()
        public var decoration = Decoration()
        public var elementID: ElementID?
        public var handlers = Handlers()
        public init() {}

        public func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
            (pass.requestNode(style: style, children: []), ())
        }

        public func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                             pass: inout PrepaintPass) {}

        public func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                          prepaint: inout Void, pass: inout PaintPass) {}
    }

    """

/// The solver-work budget the 24-modifier chain must fit, passed as
/// `-Xfrontend -solver-scope-threshold=1000`.
///
/// **Set from a measurement against the real module, not from the model.** The
/// positive fixture below, binary-searched against this lane's `MetalUI`
/// module, needs a minimum of **186** scopes under BOTH toolchains installed on
/// the measuring machine: swift.org Swift 6.3.3 against the package's own
/// `.build/<triple>/debug/Modules`, and Apple Swift 6.4 (swiftlang) against a
/// `MetalUI` built by that toolchain into a scratch path (record §10). 1000 is
/// about 5.4x that minimum, and the in-test negative still fails at 1000 (and
/// at 500, 2000 and 5000) under both. The design model
/// (`chain-solver-scope-guard.sh`) read a minimum of 190.
private let solverScopeThreshold = 1000

/// Twelve `.padding(i).frame(width: i)` pairs on `Leaf`, integer literals,
/// ending in a ternary `.background` — the shape whose first `MC-A` design
/// (concrete `padding`/`frame` redeclarations on `ModifiedElement`) the design
/// review measured at 6.6 s and then "unable to type-check".
private let chainSource = """
    @MainActor func probeBody(flag: Bool) -> some Element {
        Leaf().padding(1).frame(width: 1).padding(2).frame(width: 2).padding(3).frame(width: 3)
            .padding(4).frame(width: 4).padding(5).frame(width: 5).padding(6).frame(width: 6)
            .padding(7).frame(width: 7).padding(8).frame(width: 8).padding(9).frame(width: 9)
            .padding(10).frame(width: 10).padding(11).frame(width: 11).padding(12).frame(width: 12)
            .background(flag ? .accent : .surface)
    }

    """

/// The first `MC-A` design's three concrete overloads, declared in the FIXTURE
/// against a module that has only the chosen design. They reproduce that
/// design's exponential solver work without mutating `Sources/`
/// (`chain-solver-scope-guard.sh`, part 2).
private let firstDesignOverloads = """
    extension ModifiedElement {
        public func padding(_ points: Pixels) -> ModifiedElement<Content> { fatalError() }
        public func padding(_ edges: Edges<Length>) -> ModifiedElement<Content> { fatalError() }
        public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<Content> { fatalError() }
    }

    """

/// **A 24-modifier legacy chain type-checks within a fixed solver work budget**
/// (ruling MC-A, lane 2 test 6; this replaced a run-time type-name test whose
/// only red was a compiler time-out, MC-Q finding 3).
///
/// The positive fixture must be accepted at `solverScopeThreshold`; the same
/// file plus `firstDesignOverloads` must be rejected with "unable to
/// type-check". The two are `#require`d to disagree first, so an instrument
/// that accepts or rejects everything (a missing flag, a module that failed to
/// import) cannot pass.
///
/// Red once, by mutation (record §10): the three overloads above moved into
/// `ModifiedElement.swift` — the first design — make the POSITIVE fixture
/// fail at this threshold with the "unable to type-check" diagnostic.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aTwentyFourModifierChainTypechecksWithinASolverWorkBudget() throws {
    let budget = ["-solver-scope-threshold=\(solverScopeThreshold)"]
    let positive = try typecheckFile(leafSource + chainSource, importing: "MetalUI",
                                     frontendArguments: budget)
    let negative = try typecheckFile(leafSource + chainSource + firstDesignOverloads,
                                     importing: "MetalUI", frontendArguments: budget)
    print("""
        MC-A solver budget \(solverScopeThreshold): positive succeeded=\(positive.succeeded) \
        messages=[\(positive.messages)]; negative succeeded=\(negative.succeeded) \
        messages=[\(negative.messages)]
        """)

    try #require(positive.succeeded != negative.succeeded,
                 "the two fixtures must disagree, or this instrument cannot fail:\npositive:\n\(positive.output)\nnegative:\n\(negative.output)")
    #expect(positive.succeeded,
            "a 24-modifier chain must type-check within \(solverScopeThreshold) solver scopes:\n\(positive.output)")
    #expect(!negative.succeeded
            && negative.messages.contains("unable to type-check this expression in reasonable time"),
            "the first design's overloads must exhaust the same budget:\n\(negative.output)")
}

/// **The nested `ModifiedElement<ModifiedElement<…>>` shape cannot be spelled
/// outside the module** (ruling MC-B, lane 2 guard 7): neither a contextual
/// annotation nor a generic return type selects it, so generic code over a
/// chain can only produce the flat type with one more layer.
///
/// Three fixtures: two negatives and the positive they must disagree with.
///
/// Red once (record §10): on a skeleton without `typealias LayerBase =
/// Content`, whose chains nest, the first negative compiles.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aNestedModifiedElementCannotBeSpelled() throws {
    let annotated = try typecheckFile(leafSource + """
        @MainActor func use() {
            let _: ModifiedElement<ModifiedElement<Leaf>> = Leaf().padding(4).padding(8)
        }
        """, importing: "MetalUI")
    let genericNested = try typecheckFile(leafSource + """
        @MainActor func wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T> { t.padding(8) }
        """, importing: "MetalUI")
    let genericFlat = try typecheckFile(leafSource + """
        @MainActor func wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T.LayerBase> { t.padding(8) }
        @MainActor func use() -> ModifiedElement<Leaf> { wrap(Leaf().padding(4)) }
        """, importing: "MetalUI")
    print("""
        MC-B nested spelling: annotated succeeded=\(annotated.succeeded) messages=[\(annotated.messages)]; \
        generic nested succeeded=\(genericNested.succeeded) messages=[\(genericNested.messages)]; \
        generic flat succeeded=\(genericFlat.succeeded) messages=[\(genericFlat.messages)]
        """)

    try #require(genericFlat.succeeded != annotated.succeeded
                 && genericFlat.succeeded != genericNested.succeeded,
                 "the negatives and the positive must disagree:\nflat:\n\(genericFlat.output)")
    #expect(genericFlat.succeeded,
            "a generic `-> ModifiedElement<T.LayerBase>` over a chain must compile:\n\(genericFlat.output)")
    #expect(!annotated.succeeded && annotated.messages.contains("cannot assign value of type"),
            "a nested annotation must be rejected for its type:\n\(annotated.output)")
    #expect(!genericNested.succeeded && genericNested.messages.contains("cannot convert return expression"),
            "a generic nested return type must be rejected for its type:\n\(genericNested.output)")
}
