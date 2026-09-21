import Testing
import MetalUITestSupport

// Compile-time guards for the typed native node id (lane 3 of
// `docs/superpowers/specs/2026-09-15-modifier-composition-design.md`; rulings
// MC-G and MC-H, closing the compile-time half ruling SA-R deferred to plan
// task 3).
//
// `ProposalNodeID` has an `internal` initializer, every public native registrar
// returns one and takes them as children, and `ProposalElementGroup` requires
// `requestProposalGroupLayout`, which returns them. Guards 1–5 below are the five
// lies that became compile errors; guard 6 is `MC-G`'s hole 1, pinned wrong on
// purpose.
//
// **Every fixture uses `typecheckFile` against a PLAIN `import MetalUI`** (ruling
// SA-P; taxonomy shape 16): an access-level narrowing and a missing requirement
// are both compile-time properties that a `@testable` file cannot see. This file's
// own imports are irrelevant; the fixture's is the one that counts.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "When CI lands"). Each guard here was run red once on a
// `--build-system native` build before lane 3 landed and, where the spec names a
// mutation, again after; the red lines are in record §10 under lane 3.
//
// **Each real diagnostic is printed before it is asserted on**, so a guard whose
// fragment stopped matching shows what the compiler said instead.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func show(_ label: String, _ result: TypecheckResult) {
    print("PROPOSAL-NODE-ID GUARD \(label): succeeded=\(result.succeeded)\n\(result.messages)")
}

/// Empty `prepaint`/`paint` for a `Void`-state element fixture.
private let voidPhases = """
        public func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                             pass: inout PrepaintPass) {}
        public func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                          prepaint: inout Void, pass: inout PaintPass) {}
    """

/// **Guard 1 — the marker's promise is now a requirement.** Before lane 3 this
/// exact shape (`LegacyNodeUnderAProposalMarker` in
/// `NativeBoundaryIntegrationTests.swift` as it stood at `f64e58a`: an `Element`
/// that declares the marker and registers a legacy node) compiled, and the lie
/// surfaced only as a trap inside a proposal container (ruling SA-R). An
/// `Element` that is not a `ProposalElement` gets no typed entry from any default,
/// so it no longer conforms.
///
/// Mutation that must redden it: give every `ProposalElementGroup` a default
/// `requestProposalGroupLayout` that traps.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aMarkerConformerThatRegistersALegacyNodeDoesNotCompile() throws {
    let result = try typecheckFile("""
        public struct Liar: Element, ProposalElementGroup {
            public init() {}
            public func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
                (pass.requestNode(style: Style(), children: []), ())
            }
        \(voidPhases)
        }
        """, importing: "MetalUI")
    show("1 liar", result)
    #expect(!result.succeeded,
            "a marker conformer registering a legacy node must not compile:\n\(result.output)")
    #expect(result.messages.contains("type 'Liar' does not conform to protocol 'ProposalElementGroup'"),
            "rejected, but not by the typed requirement:\n\(result.output)")
}

/// **Guard 2 — a typed id cannot be minted from a legacy node.** The positive
/// control reads a registrar's id through the public `layoutNodeID`, so the
/// negative's failure is about the initializer and not about a type that is
/// missing or private.
///
/// Mutation that must redden it: make `ProposalNodeID.init(_:)` `public`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aProposalNodeIDCannotBeMintedOutsideMetalUI() throws {
    let minted = try typecheckFile("""
        @MainActor public func mint(_ pass: inout LayoutPass) -> ProposalNodeID {
            ProposalNodeID(pass.requestNode(style: Style(), children: []))
        }
        """, importing: "MetalUI")
    let read = try typecheckFile("""
        @MainActor public func read(_ pass: inout LayoutPass) -> LayoutNodeID {
            pass.requestNativeSpacer().layoutNodeID
        }
        """, importing: "MetalUI")
    show("2 mint", minted)
    show("2 read", read)
    try #require(minted.succeeded != read.succeeded,
                 "the mint and the read must disagree, or the instrument cannot fail:\n\(minted.output)\n\(read.output)")
    #expect(read.succeeded, "a registrar's typed id must expose its layout node id:\n\(read.output)")
    #expect(!minted.succeeded, "a ProposalNodeID must not be mintable outside MetalUI:\n\(minted.output)")
    #expect(minted.messages.contains("'ProposalNodeID' initializer is inaccessible due to 'internal' protection level"),
            "rejected, but not because the initializer is internal:\n\(minted.output)")
}

/// **Guard 3 — a `Component` takes the marker only over proposal content.**
/// `Component`'s typed default exists `where Content: ProposalElementGroup`, so a
/// component over legacy content, or over content spelled `some ElementGroup`
/// (which hides that it is proposal content), no longer conforms. The third
/// fixture, `some ProposalElementGroup`, is the spelling an author must write.
///
/// Mutation that must redden it: an unconstrained `extension Component` default
/// `requestProposalGroupLayout` that traps.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aComponentOnlyTakesTheProposalMarkerWithProposalContent() throws {
    let legacy = try typecheckFile("""
        public struct LegacyComp: Component {
            public var content: Text { Text("legacy") }
        }
        extension LegacyComp: ProposalElementGroup {}
        """, importing: "MetalUI")
    let opaque = try typecheckFile("""
        public struct OpaqueComp: Component {
            public var content: some ElementGroup { Rectangle() }
        }
        extension OpaqueComp: ProposalElementGroup {}
        """, importing: "MetalUI")
    let proposal = try typecheckFile("""
        public struct ProposalComp: Component {
            public var content: some ProposalElementGroup { Rectangle() }
        }
        extension ProposalComp: ProposalElementGroup {}
        @MainActor public func use() { _ = HStack { ProposalComp() } }
        """, importing: "MetalUI")
    show("3 legacy", legacy)
    show("3 opaque", opaque)
    show("3 proposal", proposal)
    try #require(legacy.succeeded != proposal.succeeded && opaque.succeeded != proposal.succeeded,
                 "each negative must disagree with the positive, or the instrument cannot fail")
    #expect(proposal.succeeded, "a component over some ProposalElementGroup must conform:\n\(proposal.output)")
    #expect(!legacy.succeeded, "a component over legacy content must not take the marker:\n\(legacy.output)")
    #expect(legacy.messages.contains("type 'LegacyComp' does not conform to protocol 'ProposalElementGroup'"),
            "rejected, but not by the typed requirement:\n\(legacy.output)")
    #expect(!opaque.succeeded, "a component over some ElementGroup must not take the marker:\n\(opaque.output)")
    #expect(opaque.messages.contains("type 'OpaqueComp' does not conform to protocol 'ProposalElementGroup'"),
            "rejected, but not by the typed requirement:\n\(opaque.output)")
}

/// **Guard 4 — a native registrar rejects a legacy child.** The positive control
/// hands the same registrar a native spacer.
///
/// Mutation that must redden it: add a `requestNativeFrame(child: LayoutNodeID, …)`
/// overload to `LayoutPass`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aNativeRegistrarRejectsALegacyChild() throws {
    let legacy = try typecheckFile("""
        @MainActor public func probe(_ pass: inout LayoutPass) {
            _ = pass.requestNativeFrame(child: pass.requestNode(style: Style(), children: []))
        }
        """, importing: "MetalUI")
    let native = try typecheckFile("""
        @MainActor public func probe(_ pass: inout LayoutPass) {
            _ = pass.requestNativeFrame(child: pass.requestNativeSpacer())
        }
        """, importing: "MetalUI")
    show("4 legacy", legacy)
    show("4 native", native)
    try #require(legacy.succeeded != native.succeeded,
                 "the legacy and native children must disagree, or the instrument cannot fail")
    #expect(native.succeeded, "a native child must be accepted:\n\(native.output)")
    #expect(!legacy.succeeded, "a legacy child must not be accepted:\n\(legacy.output)")
    #expect(legacy.messages.contains("cannot convert value of type 'LayoutNodeID' to expected argument type 'ProposalNodeID'"),
            "rejected, but not by the typed child parameter:\n\(legacy.output)")
}

/// A container over a custom `ProposalLayout`, with its content's nodes fetched
/// by `ENTRY`, for guard 5.
private func containerSource(entry: String) -> String {
    """
    public struct Flat: ProposalLayout {
        public init() {}
        public func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
            LayoutMeasurement(size: SizeD(width: 0, height: 0))
        }
        public func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize,
                                  subviews: PlacementSubviews) {}
    }

    public struct Container<Content: ProposalElementGroup>: ProposalElement {
        public var content: Content
        public init(@ElementBuilder content: () -> Content) { self.content = content() }

        public mutating func requestProposalLayout(_ id: GlobalElementID,
                                                   pass: inout LayoutPass) -> (ProposalNodeID, Content.GroupLayout) {
            var cursor = 0
            let (children, layout) = content.\(entry)(under: id, at: &cursor, pass: &pass)
            return (pass.requestNativeLayout(Flat(), children: children), layout)
        }

        public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                      layout: inout Content.GroupLayout,
                                      pass: inout PrepaintPass) -> Content.GroupPrepaint {
            content.prepaintGroup(layout: &layout, pass: &pass)
        }

        public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                   layout: inout Content.GroupLayout,
                                   prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
            content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
        }
    }

    @MainActor public func use() { _ = HStack { Container { Rectangle() } } }
    """
}

/// **Guard 5 — a custom-layout container accepts only typed children.** An
/// external container that fetches its content's nodes through the untyped
/// `requestGroupLayout` cannot hand them to `requestNativeLayout`; fetched
/// through `requestProposalGroupLayout`, it compiles.
///
/// Mutation that must redden it: add a `requestNativeLayout(_:children: [LayoutNodeID])`
/// overload to `LayoutPass`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aProposalLayoutContainerOnlyAcceptsTypedChildren() throws {
    let untyped = try typecheckFile(containerSource(entry: "requestGroupLayout"), importing: "MetalUI")
    let typed = try typecheckFile(containerSource(entry: "requestProposalGroupLayout"), importing: "MetalUI")
    show("5 untyped", untyped)
    show("5 typed", typed)
    try #require(untyped.succeeded != typed.succeeded,
                 "the untyped and typed entries must disagree, or the instrument cannot fail")
    #expect(typed.succeeded, "a container over the typed entry must compile:\n\(typed.output)")
    #expect(!untyped.succeeded, "a container over the untyped entry must not compile:\n\(untyped.output)")
    #expect(untyped.messages.contains("cannot convert value of type '[LayoutNodeID]' to expected argument type '[ProposalNodeID]'"),
            "rejected, but not by the typed children parameter:\n\(untyped.output)")
}

/// A group that writes both entry points itself (`liar4` in
/// `docs/probes/modifier-composition-skeletons/`), for guard 6.
private func disagreeingGroupSource(withTypedEntry: Bool) -> String {
    let typedEntry = withTypedEntry ? """
            public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                                            pass: inout LayoutPass) -> ([ProposalNodeID], Void) {
                ([], ())
            }
        """ : ""
    return """
    public struct Liar: ProposalElementGroup {
        public init() {}
        public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                                pass: inout LayoutPass) -> ([LayoutNodeID], Void) {
            ([pass.requestNode(style: Style(), children: [])], ())
        }
    \(typedEntry)
        public mutating func prepaintGroup(layout: inout Void, pass: inout PrepaintPass) {}
        public mutating func paintGroup(layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
    }

    @MainActor public func use() { _ = HStack { Liar() } }
    """
}

/// **Guard 6 — PINNED WRONG ON PURPOSE (`MC-G` hole 1): a group whose two entry
/// points disagree still compiles.** The positive fixture writes both entries —
/// a legacy node from the untyped one, zero typed nodes from the typed one — and
/// typechecks. No type-system spelling in this design stops it: the untyped entry
/// must exist because `Frame` renders every root through it, and the two
/// requirements are independent. Where it can hurt is `MC-G` hole 1.
///
/// **The in-test negative** is the same fixture without its typed entry, which is
/// rejected. The `#require` that the two disagree is what stops a skipped or
/// broken instrument from reading as the hole being open.
///
/// **Whoever closes the hole inverts the positive assertion.** Its red run: delete
/// the positive fixture's typed entry, making it the negative (record §10).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aProposalGroupWhoseEntryPointsDisagreeStillCompiles() throws {
    let liar = try typecheckFile(disagreeingGroupSource(withTypedEntry: true), importing: "MetalUI")
    let withoutTypedEntry = try typecheckFile(disagreeingGroupSource(withTypedEntry: false), importing: "MetalUI")
    show("6 liar", liar)
    show("6 without typed entry", withoutTypedEntry)
    try #require(liar.succeeded != withoutTypedEntry.succeeded,
                 "the liar and its typed-entry-less copy must disagree, or the instrument cannot fail")
    #expect(liar.succeeded, "hole 1: a group writing both entry points compiles:\n\(liar.output)")
    #expect(!withoutTypedEntry.succeeded,
            "without its typed entry the group must not conform:\n\(withoutTypedEntry.output)")
    #expect(withoutTypedEntry.messages.contains("type 'Liar' does not conform to protocol 'ProposalElementGroup'"),
            "rejected, but not by the typed requirement:\n\(withoutTypedEntry.output)")
}
