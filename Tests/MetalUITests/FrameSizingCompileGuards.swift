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
            let pinnedFixed: ModifiedContent<ProposalLeaf, LayoutModifier> = fixed
            _ = pinnedFixed

            let flexible = ProposalLeaf().frame(minWidth: Pixels(10), idealWidth: Pixels(20),
                                                maxWidth: Pixels(30))
            let pinnedFlexible: ModifiedContent<ProposalLeaf, LayoutModifier> = flexible
            _ = pinnedFlexible

            let ideal = ProposalLeaf().frame(idealWidth: Pixels(20))
            let pinnedIdeal: ModifiedContent<ProposalLeaf, LayoutModifier> = ideal
            _ = pinnedIdeal

            let aligned = ProposalLeaf().frame(alignment: .topLeading)
            let pinnedAligned: ModifiedContent<ProposalLeaf, LayoutModifier> = aligned
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

/// **N3.1 — the eight sizing modifiers are deprecated toward `.frame`** (plan
/// task 7, stage 8; rulings `LR-EU`, `LR-ET`; spec
/// `docs/superpowers/specs/2026-09-24-engine-stage-8-design.md` §4, §6 lane 3).
///
/// A plain `import MetalUI` fixture calls each of `width`, `height`,
/// `minWidth`, `maxWidth`, `minHeight`, `maxHeight`, `width(fraction:)` and
/// `height(fraction:)` once, on its own line, and must draw **exactly eight**
/// deprecations; each modifier's diagnostic must name its replacement as the
/// message spells it (`use .frame(width:)`, …; the two fractions "no SwiftUI
/// counterpart"), and `minHeight`'s must also name `LR-ET`'s zero-minimum
/// spelling. The control fixture spells the same sizes with `.frame` and must
/// draw none — so a count read from both arms can disagree.
///
/// `message:`, not `renamed:` (`LR-EU` item 2): a `renamed:` fix-it would apply
/// `LR-ES`'s R1 alone and silently skip R2–R6.
///
/// Red before lane 3: no modifier is deprecated (count 0). Mutation **M3a**
/// (delete one `@available`) → 7, this test red.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theSizingModifiersAreDeprecatedTowardFrame() throws {
    let result = try typecheckFile("""
        @MainActor public func probe() {
            _ = Box().width(Pixels(1))
            _ = Box().height(Pixels(2))
            _ = Box().minWidth(Pixels(3))
            _ = Box().maxWidth(Pixels(4))
            _ = Box().minHeight(Pixels(5))
            _ = Box().maxHeight(Pixels(6))
            _ = Box().width(fraction: 0.5)
            _ = Box().height(fraction: 0.5)
        }
        """, importing: "MetalUI")
    let lines = result.messages.split(separator: "\n").filter { $0.contains("is deprecated") }
    print("N3.1 sizing deprecations: succeeded=\(result.succeeded) count=\(lines.count) messages=[\(result.messages)]")
    #expect(result.succeeded, "the deprecated spellings must still compile:\n\(result.output)")
    #expect(lines.count == 8, "exactly one deprecation per sizing modifier:\n\(result.output)")

    // (the declaration's name as the diagnostic quotes it, the replacement its message must name)
    let expected: [(String, String)] = [
        ("'width' is deprecated", "use .frame(width:), which wraps this element in a layer"),
        ("'height' is deprecated", "use .frame(height:), which wraps this element in a layer"),
        ("'minWidth' is deprecated", "use .frame(minWidth:), which wraps this element in a layer"),
        ("'maxWidth' is deprecated", "use .frame(maxWidth:), which wraps this element in a layer"),
        ("'minHeight' is deprecated", "use .frame(minHeight:), which wraps this element in a layer"),
        ("'minHeight' is deprecated", ".frame(minHeight: 0, maxHeight: .infinity) (LR-ET)"),
        ("'maxHeight' is deprecated", "use .frame(maxHeight:), which wraps this element in a layer"),
        ("'width(fraction:)' is deprecated", "no SwiftUI counterpart"),
        ("'width(fraction:)' is deprecated", "declare a length with .frame(width:)"),
        ("'height(fraction:)' is deprecated", "no SwiftUI counterpart"),
        ("'height(fraction:)' is deprecated", "declare a length with .frame(height:)"),
    ]
    try #require(expected.count == 11)
    for (name, replacement) in expected {
        #expect(lines.contains { $0.contains(name) && $0.contains(replacement) },
                "\(name) must name \(replacement):\n\(result.output)")
    }

    let control = try typecheckFile("""
        @MainActor public func probe() {
            _ = Box().frame(width: Pixels(1))
            _ = Box().frame(height: Pixels(2))
            _ = Box().frame(minWidth: Pixels(3))
            _ = Box().frame(maxWidth: Pixels(4))
            _ = Box().frame(minHeight: Pixels(5))
            _ = Box().frame(maxHeight: Pixels(6))
            _ = Box().frame(minHeight: Pixels(0), maxHeight: Pixels(.infinity))
        }
        """, importing: "MetalUI")
    let controlCount = control.messages.split(separator: "\n").filter { $0.contains("is deprecated") }.count
    print("N3.1 control: succeeded=\(control.succeeded) count=\(controlCount) messages=[\(control.messages)]")
    #expect(control.succeeded, "the .frame spellings must compile:\n\(control.output)")
    #expect(controlCount == 0, "the .frame spellings are not deprecated:\n\(control.output)")
}
