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
            (pass.requestNode(style: style, children: []), ())
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
