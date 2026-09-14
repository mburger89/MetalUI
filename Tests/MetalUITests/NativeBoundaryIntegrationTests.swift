import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Lane 2 ("boundaries") of `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`:
// the mixing traps of ruling SA-G, reached through elements and a real `Frame`,
// and the two run-time traps ruling SA-R leaves standing where the compiler
// cannot check a `ProposalElementGroup` conformer's promise.
//
// Each is an exit test that asserts its fragment on stderr as well as the
// failure, because a trap elsewhere must not pass; the bodies cannot capture.

/// A proposal `Component` whose content is one native leaf. `Component` plus
/// `ProposalElementGroup` compiles, and so does a legacy style modifier on it
/// inside a legacy container (the design's evidence 9).
private struct Toggle: Component, ProposalElementGroup {
    var content: some ElementGroup { Rectangle() }
}

/// An element that declares the proposal marker and registers a LEGACY node.
/// The marker has no requirements, so this compiles (ruling SA-R).
private struct LegacyNodeUnderAProposalMarker: Element, ProposalElementGroup {
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNode(style: Style(), children: []), ())
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

/// A proposal element that traps with its own message the moment it is
/// registered: the witness that registration continued past a sibling.
private struct RegisteredAfterTheContainer: Element, ProposalElementGroup {
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        preconditionFailure("registration continued past a proposal container holding a legacy node")
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

/// A `ProposalElementGroup` conformer that registers a legacy node traps inside
/// a proposal container, **at the container's native registration**. This is
/// the run-time half of ruling SA-R's amended criterion: the compile-time check
/// is plan task 3's.
///
/// **Why the sibling registered after the `HStack`.** Measurement reaches the
/// same `nativeNode(_:)` lookup, with the same message, so without a witness a
/// kernel that stopped checking at registration would still trap later, at
/// layout, and pass. Measured: with the child loop deleted from
/// `newNativeLinearStack` and no sibling, this test stayed green. The sibling
/// is registered only if registration got past the `HStack`, and then it traps
/// with its own message, which lacks the fragment.
@Test func aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = VStack {
                HStack { LegacyNodeUnderAProposalMarker() }
                RegisteredAfterTheContainer()
            }
            Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1)
                .render(&root)
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("contains a legacy node"),
            "aborted, but not at the legacy-child check this test is about:\n\(stderr)")
}
