import Testing
import MetalUITestSupport

// Compile-time guards for lane 1 of plan task 7 stage 11 (spec
// `docs/superpowers/specs/2026-09-25-engine-stage-11-design.md` §3, §7 lane 1;
// ruling `LR-FV`): the proposal chain is ONE flat `ModifiedContent<Base,
// LayoutModifier>` as an external module writes it (G1.1), and an external
// `ModifierLayerKind` conformer compiles but cannot build a `ModifiedContent`
// (G1.2, spec §3.7's hole).
//
// **Every fixture uses `typecheckFile`**: a whole file in the Swift 6 language
// mode against a PLAIN `import MetalUI` (`SA-P`, practices shape 16). Each guard
// prints every real diagnostic before asserting on it, and `#require`s its
// positive and negative fixtures to disagree first, so an instrument that
// accepts or rejects everything cannot pass.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"). Each was mutated red once; the red lines are in
// record §54's lane-1 section.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// A proposal leaf an outside module can write.
private let proposalLeafSource = """
    public struct Leaf: ProposalElement {
        public init() {}

        public func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
            (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }, ())
        }

        public func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                             pass: inout PrepaintPass) {}

        public func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                          prepaint: inout Void, pass: inout PaintPass) {}
    }

    """

/// **G1.1 — a proposal modifier chain infers ONE flat
/// `ModifiedContent<Leaf, LayoutModifier>`** (ruling `LR-FV` items 1 and 4):
/// the flat annotation of a three-modifier chain compiles, and the nested
/// annotation `ModifiedContent<ModifiedContent<Leaf, LayoutModifier>,
/// LayoutModifier>` of a two-modifier chain is rejected for its type.
///
/// Red before: at `47c0d98` the positive does not compile (`ModifiedContent`
/// takes one argument). Mutation **M1a** (`typealias ProposalBase = Content`
/// deleted, so chains nest) makes the positive fail and the nested negative
/// compile (record §54).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aProposalModifierChainInfersOneFlatModifiedContent() throws {
    let flat = try typecheckFile(proposalLeafSource + """
        @MainActor func use() {
            let chain: ModifiedContent<Leaf, LayoutModifier> =
                Leaf().padding(Edges(all: Pixels(1))).frame(width: Pixels(2)).background(.accent)
            _ = chain
        }
        """, importing: "MetalUI")
    let nested = try typecheckFile(proposalLeafSource + """
        @MainActor func use() {
            let chain: ModifiedContent<ModifiedContent<Leaf, LayoutModifier>, LayoutModifier> =
                Leaf().padding(Edges(all: Pixels(1))).frame(width: Pixels(2))
            _ = chain
        }
        """, importing: "MetalUI")
    print("""
        LR-FV flat proposal chain: flat succeeded=\(flat.succeeded) messages=[\(flat.messages)]; \
        nested succeeded=\(nested.succeeded) messages=[\(nested.messages)]
        """)

    try #require(flat.succeeded != nested.succeeded,
                 "the flat and nested annotations must disagree:\nflat:\n\(flat.output)\nnested:\n\(nested.output)")
    #expect(flat.succeeded, "the flat annotation must compile:\n\(flat.output)")
    #expect(!nested.succeeded && nested.messages.contains("cannot assign value of type"),
            "the nested annotation must be rejected for its type:\n\(nested.output)")
}

/// An external `ModifierLayerKind` conformer: every requirement is spellable
/// with public types (spec §3.7).
private let externalKindSource = """
    public struct ExternalKind: ModifierLayerKind {
        public var _elementID: ElementID?
        public init() {}

        public mutating func _requestLayout(_ id: GlobalElementID, children: [LayoutNodeID],
                                            pass: inout LayoutPass) -> LayoutNodeID {
            children[0]
        }

        public func _prepaint<R>(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: PrepaintPass,
                                 inside: () -> R) -> R {
            inside()
        }

        public func _paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: PaintPass,
                           inside: () -> Void) {
            inside()
        }

        public static func _legacyStack(_ outermost: ExternalKind, _ inner: [ExternalKind],
                                        _ prefix: [LayoutModifier])
            -> (prefix: [LayoutModifier], layers: [ModifierLayer]) {
            (prefix, [])
        }
    }

    """

/// **G1.2 — an external `ModifierLayerKind` conformer compiles and cannot
/// build a `ModifiedContent`** (spec §3.7): the conformer alone typechecks;
/// the memberwise initializer over it and the public
/// `init(content:modifier:)` with it as the vocabulary are both rejected — so
/// the conformance is inert.
///
/// Red before: at `47c0d98` the conformer does not compile (no
/// `ModifierLayerKind`). Mutation **M1h** (the memberwise initializer made
/// `public`) makes the memberwise negative compile (record §54).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anExternalModifierLayerKindCannotBuildAModifiedContent() throws {
    let conformer = try typecheckFile(proposalLeafSource + externalKindSource, importing: "MetalUI")
    let memberwise = try typecheckFile(proposalLeafSource + externalKindSource + """
        @MainActor func build() {
            _ = ModifiedContent(content: Leaf(), outermost: ExternalKind(), inner: [], prefix: [])
        }
        """, importing: "MetalUI")
    let publicInit = try typecheckFile(proposalLeafSource + externalKindSource + """
        @MainActor func build() {
            let _: ModifiedContent<Leaf, ExternalKind> =
                ModifiedContent(content: Leaf(), modifier: .padding(Edges(all: Pixels(1))))
        }
        """, importing: "MetalUI")
    print("""
        LR-FV external ModifierLayerKind: conformer succeeded=\(conformer.succeeded) \
        messages=[\(conformer.messages)]; memberwise succeeded=\(memberwise.succeeded) \
        messages=[\(memberwise.messages)]; public init succeeded=\(publicInit.succeeded) \
        messages=[\(publicInit.messages)]
        """)

    try #require(conformer.succeeded != memberwise.succeeded
                 && conformer.succeeded != publicInit.succeeded,
                 "the conformer and the two builds must disagree:\nconformer:\n\(conformer.output)")
    #expect(conformer.succeeded, "an external conformer must compile:\n\(conformer.output)")
    // An internal initializer is not a candidate outside the module, so the
    // call resolves against the public `init(content:modifier:)` and fails on
    // its arity.
    #expect(!memberwise.succeeded && memberwise.messages.contains("extra arguments"),
            "the memberwise initializer must be invisible:\n\(memberwise.output)")
    #expect(!publicInit.succeeded
            && publicInit.messages.contains("to type 'ModifiedContent<Leaf, ExternalKind>'"),
            "the public initializer must not build a chain over an external vocabulary:\n\(publicInit.output)")
}
