import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Lane 2 ("boundaries") of `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`:
// the mixing traps of ruling SA-G, reached through elements and a real `Frame`,
// and the two run-time traps ruling SA-R leaves standing where the compiler
// cannot check a `ProposalElementGroup` conformer's promise. Since ruling MC-G
// the compiler checks most of that promise; the traps stay as the backstop for
// its holes 3 and 5.
//
// Each is an exit test that asserts its fragment on stderr as well as the
// failure, because a trap elsewhere must not pass; the bodies cannot capture.

/// A proposal `Component` whose content is one native leaf. `Component` plus
/// `ProposalElementGroup` compiles — since ruling MC-G only over content spelled
/// `some ProposalElementGroup` — and so does a legacy style modifier on it inside
/// a legacy container (the design's evidence 9; MC-G hole 5).
private struct Toggle: Component, ProposalElementGroup {
    var content: some ProposalElementGroup { Rectangle() }
}

/// A proposal element whose typed entry hands a LEGACY node to its container.
///
/// **Until ruling MC-G the marker had no requirements**, so an `Element` that
/// declared it and registered a legacy node compiled (ruling SA-R). That shape
/// is now a compile error (`aMarkerConformerThatRegistersALegacyNodeDoesNotCompile`),
/// and the way left to reach the run-time trap is to mint a `ProposalNodeID`
/// from a legacy node through the internal initializer, which this file can do
/// only because it imports `MetalUI` `@testable` — MC-G's hole 3, the one the
/// trap below backstops.
private struct LegacyNodeUnderAProposalMarker: ProposalElement {
    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        (ProposalNodeID(pass.frame.requestNode(style: Style(), children: [])), ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

/// A proposal element inside a legacy `Column` traps at the `Column`'s
/// registration. Before the check it rendered silently wrong: the design's
/// evidence 4 measured the leaf's closure running 0 times and its bounds at
/// (70, 0, 0×0) in this 140×90 frame.
@Test func aProposalElementInsideALegacyContainerTrapsAtRegistration() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = Column { Rectangle() }
            Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1)
                .render(&root)
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("given a native child"),
            "aborted, but not at the native-child check this test is about:\n\(stderr)")
}

/// A legacy style modifier on a proposal `Component` traps at `setStyle`.
///
/// **Why the fragment discriminates although `Column` also traps.**
/// `StyledComponent.requestGroupLayout` registers the `Rectangle`'s native leaf
/// and calls `setStyle` on it before it returns, and `Column` calls `newNode`
/// only after its content returns, so the `setStyle` trap fires first. With the
/// `setStyle` check deleted, the process traps at `Column`'s `newNode` instead
/// ("given a native child"), and this test reddens on its fragment.
///
/// `StyledComponent` is not an `Element`, so it cannot be the root itself.
/// Before the check the width was silently inert: the proposal engine never
/// reads `Style`.
@Test func aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = Column { Toggle().width(Pixels(70)) }
            Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1)
                .render(&root)
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("setStyle on a native layout node"),
            "aborted, but not at the native-style check this test is about:\n\(stderr)")
}

/// `.padding` on a proposal `Component` traps at the WRAP's `newNode` — the
/// second route into `MC-G` hole 5, closed by the outer-modifiers task
/// (`OM-Z`, lane 4). `Component.padding` no longer amends each member's
/// `Style` (which reached `setStyle`'s trap above) but wraps each member in a
/// legacy padding node through `Frame.requestNode(style:children:)` (plan task 7's
/// per-site checks moved it off `LayoutPass`'s public forwarder), and
/// `LayoutTree.newNode` already refuses a native child
/// (`LayoutTree.swift`, "legacy layout node given a native child", ruling
/// SA-G; pinned for the direct call by
/// `aNativeNodeRegisteredUnderALegacyNodeTraps`). No new precondition: this
/// pins the ROUTE through `StyledComponent`.
///
/// **Why the call is direct and not under a `Column`.** A `Column` would trap
/// at its own `newNode` with the SAME fragment once its content returned, so
/// an implementation whose `.padding` did nothing at all would still pass on
/// the fragment. Driving `requestGroupLayout` on the `StyledComponent` itself
/// leaves the wrap's registration as the only legacy `newNode` in the
/// process: delete the wrap and nothing traps, and the exit expectation
/// itself fails.
@Test func aPaddingModifierOnAProposalComponentTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        await MainActor.run {
            let frame = Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1)
            var pass = LayoutPass(frame: frame)
            var styled = Toggle().padding(Pixels(4))
            var cursor = 0
            _ = styled.requestGroupLayout(under: nil, at: &cursor, pass: &pass)
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("given a native child"),
            "aborted, but not at the wrap's native-child check this test is about:\n\(stderr)")
}

/// A proposal element that traps with its own message the moment it is
/// registered: the witness that registration continued past a sibling.
private struct RegisteredAfterTheContainer: ProposalElement {
    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        preconditionFailure("registration continued past a proposal container holding a legacy node")
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

/// A `ProposalElementGroup` conformer that registers a legacy node traps inside
/// a proposal container, **at the container's native registration**. This is
/// the run-time half of ruling SA-R's amended criterion. The compile-time half
/// is plan task 3's, delivered by ruling MC-G; the legacy node now reaches the
/// container only through a `@testable` mint (MC-G hole 3), so this trap is the
/// backstop for what the type cannot see.
///
/// **Why the sibling registered after the `HStack`.** Measurement reaches the
/// same `nativeNode(_:)` lookup, with the same message, so without a witness a
/// kernel that stopped checking at registration would still trap later, at
/// layout, and pass. Measured: with the child loop deleted from
/// `newNativeLinearStack` and no sibling, this test stayed green. The sibling
/// is registered only if registration got past the `HStack`, and then it traps
/// with its own message, which lacks the fragment.
///
/// Pinned to the legacy authority by stage 6a (N9, record §38 §4): its subject
/// is a legacy node, which `LegacyNodeUnderAProposalMarker` registers through
/// `Frame`'s internal registrar; stage 9 deletes it with the legacy authority.
@Test func aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = VStack {
                HStack { LegacyNodeUnderAProposalMarker() }
                RegisteredAfterTheContainer()
            }
            Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1,
                  layoutAuthority: .legacy)
                .render(&root)
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("contains a legacy node"),
            "aborted, but not at the legacy-child check this test is about:\n\(stderr)")
}
