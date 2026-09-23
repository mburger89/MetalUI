import Testing
import MetalUITestSupport

// Compile-time guards for plan task 4, the frame-and-sizing track
// (`docs/superpowers/specs/2026-09-15-frame-sizing-design.md`; rulings `FR-`).
//
// Every fixture uses `typecheckFile`: a whole file in the Swift 6 language mode
// against a PLAIN `import MetalUI`, as an external module writes it. This file's
// own imports are irrelevant (practices shape 16); the fixture's import is the
// one that counts.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "When CI lands"). Each guard here was mutated red once on a
// `--build-system native` build; the mutations are recorded under the ruling the
// guard cites and in `docs/record/14-frame-and-sizing.md`.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// A public proposal leaf and a public legacy leaf, side by side, as an outside
/// module writes them. The legacy one spells all four `StyledElement`
/// requirements and never mentions `LayerBase` or `_wrap`.
/// Since stage 6a the "legacy" leaf registers its untyped node through
/// `requestNativeLeaf(...).layoutNodeID` rather than the deprecated legacy
/// registrar (`LR-CU` item 6): which `frame` overload it reaches is decided by
/// its conformance (`StyledElement`, not `ProposalElement`), not by its registrar.
private let bothLeavesSource = """
    public struct ProposalLeaf: ProposalElement {
        public init() {}

        public func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
            (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }, ())
        }

        public func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                             pass: inout PrepaintPass) {}

        public func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                          prepaint: inout Void, pass: inout PaintPass) {}
    }

    public struct LegacyLeaf: StyledElement {
        public var style = Style()
        public var decoration = Decoration()
        public var elementID: ElementID?
        public var handlers = Handlers()
        public init() {}

        public func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
            (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID, ())
        }

        public func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                             pass: inout PrepaintPass) {}

        public func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                          prepaint: inout Void, pass: inout PaintPass) {}
    }

    """

/// **`frame()` with no arguments is a deprecated no-op on BOTH paths**
/// (ruling FR-J, lane 1 test 1.10). SwiftUI rejects the spelling with
/// `'frame()' is deprecated: Please pass one or more parameters.` — a separate
/// zero-parameter overload the compiler prefers for a no-argument call — where
/// MetalUI's all-defaulted `frame(width:height:alignment:)` used to accept it
/// silently and build a real centring, size-nothing layer (`SA-N` item 9).
///
/// Three things are asserted, and each is reddened by a different deletion:
///
/// - `succeeded`, so the spelling still compiles rather than becoming an error;
/// - the deprecation text **twice**, once per path, so a declaration that lost
///   its `@available` marker is caught;
/// - the **inferred** type of each call, through a `let` with no contextual
///   type followed by an annotated binding. This is the assertion the ruling
///   exists for: with `frame()` declared on `ElementGroup` alone,
///   `ProposalLeaf().frame()` infers `ModifiedContent<ProposalLeaf>` with no
///   diagnostic at all, because the refined protocol's own all-defaulted
///   `frame(width:height:alignment:)` is more specialized and wins. Both
///   declarations are load-bearing; neither is redundant.
///
/// **This is a fixture, not a runtime test, precisely because it asserts a
/// warning.** Calling `.frame()` from ordinary test code would print
/// `warning: 'frame()' is deprecated` into the suite log against the hard
/// 0-`warning:` gate. The child `swiftc`'s output is captured through a pipe
/// (the mechanism `EnvironmentCompileGuards.swift` already uses for `EV-N`).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theNoArgumentFrameIsADeprecatedNoOpOnBothPaths() throws {
    let result = try typecheckFile(bothLeavesSource + """
        @MainActor public func probe() {
            let proposal = ProposalLeaf().frame()
            let pinnedProposal: ProposalLeaf = proposal
            _ = pinnedProposal

            let legacy = LegacyLeaf().frame()
            let pinnedLegacy: LegacyLeaf = legacy
            _ = pinnedLegacy
        }
        """, importing: "MetalUI")
    let deprecations = result.messages.components(separatedBy: "'frame()' is deprecated").count - 1
    print("""
        FR-J no-argument frame: succeeded=\(result.succeeded) deprecations=\(deprecations) \
        messages=[\(result.messages)]
        """)

    #expect(result.succeeded,
            "`.frame()` must compile on both paths and infer the receiver's own type:\n\(result.output)")
    #expect(deprecations == 2,
            "both declarations must carry SwiftUI's deprecation, once per path:\n\(result.output)")
    #expect(result.messages.contains("Please pass one or more parameters"),
            "the deprecation must carry SwiftUI's own message:\n\(result.output)")
}

/// **Every `frame` spelling on a proposal element resolves to the PROPOSAL
/// overload, now that the legacy path declares the same signatures**
/// (lane 2's overload fixture; rulings `FR-C`, `FR-D`, `FR-S`, critic finding 5).
///
/// Until this lane the two paths' `frame` overloads had *different* parameter
/// lists, so a call could be resolved by its argument labels alone. They are
/// identical now, and the only thing choosing between them is that
/// `ProposalElementGroup`'s extension is more specialized.
///
/// **Mis-resolution here is silent, which is why the fixture asserts the
/// inferred TYPE rather than that the call compiles.** A legacy overload
/// winning on a proposal element produces a `ModifiedElement<…>` wrapping a
/// native subtree — that compiles, and then meets ruling `SA-G` (`newNode`
/// refuses a native child) at run time; and `.frame(idealWidth: 80)` resolving
/// to the `ElementGroup` overload would turn a working SwiftUI idiom into
/// `FR-D`'s trap. Test 2.4's fourth arm is the run-time half of the same claim.
///
/// The legacy arms are the other half: the same four spellings on a legacy leaf
/// must infer `ModifiedElement<LegacyLeaf>`, so a fixture that passed because
/// BOTH paths had regressed to one overload would still fail.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload() throws {
    let result = try typecheckFile(bothLeavesSource + """
        @MainActor public func probe() {
            let fixed = ProposalLeaf().frame(width: Pixels(10))
            let pinnedFixed: ModifiedContent<ProposalLeaf> = fixed
            _ = pinnedFixed

            let flexible = ProposalLeaf().frame(minWidth: Pixels(10), idealWidth: Pixels(20),
                                                maxWidth: Pixels(30))
            let pinnedFlexible: ModifiedContent<ProposalLeaf> = flexible
            _ = pinnedFlexible

            let ideal = ProposalLeaf().frame(idealWidth: Pixels(20))
            let pinnedIdeal: ModifiedContent<ProposalLeaf> = ideal
            _ = pinnedIdeal

            let aligned = ProposalLeaf().frame(alignment: .topLeading)
            let pinnedAligned: ModifiedContent<ProposalLeaf> = aligned
            _ = pinnedAligned

            let legacyFixed = LegacyLeaf().frame(width: Pixels(10))
            let pinnedLegacyFixed: ModifiedElement<LegacyLeaf> = legacyFixed
            _ = pinnedLegacyFixed

            let legacyAligned = LegacyLeaf().frame(width: Pixels(10), height: Pixels(10),
                                                   alignment: .topLeading)
            let pinnedLegacyAligned: ModifiedElement<LegacyLeaf> = legacyAligned
            _ = pinnedLegacyAligned

            let legacyFlexible = LegacyLeaf().frame(minWidth: Pixels(10), maxWidth: Pixels(30))
            let pinnedLegacyFlexible: ModifiedElement<LegacyLeaf> = legacyFlexible
            _ = pinnedLegacyFlexible

            let legacyAlignmentOnly = LegacyLeaf().frame(alignment: .topLeading)
            let pinnedLegacyAlignmentOnly: ModifiedElement<LegacyLeaf> = legacyAlignmentOnly
            _ = pinnedLegacyAlignmentOnly
        }
        """, importing: "MetalUI")
    print("FR-S overload resolution: succeeded=\(result.succeeded) messages=[\(result.messages)]")

    #expect(result.succeeded,
            "every frame spelling must infer its own path's wrapper type:\n\(result.output)")
}
