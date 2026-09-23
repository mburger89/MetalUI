import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Plan task 9, lane 2b: the sealed root environment (ruling `EV-Z`,
// `docs/superpowers/2026-09-15-environment-decisions.md`).
//
// `Frame.rootEnvironment`'s setter replaces the top of the environment. From
// inside a phase that would silently discard every open scope's values for the
// rest of that scope's content, so the setter traps while `Frame.render` runs.
// Writes before a render and between two renders stay legal.
//
// **Each trap arm reads the abort message off stderr, not only the exit
// status**, as `ElementGroupTrapTests.swift` explains: an unrelated trap in the
// same render would otherwise satisfy `.failure`. The
// `#expect(processExitsWith:)` call is written out at each site because its
// body is re-entered in a subprocess and must not capture context.
//
// **Stage 6a (record §38, disposition R):** `RootWriter` and `ScopedReader`
// register native leaves, so both renders run under the proposal authority. The
// trap is `EV-Z`'s, which reads no authority; the stderr check above is what
// keeps a trap for any other reason under `.proposal` from passing T1.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private struct TrapProbeKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    fileprivate var trapProbe: Int {
        get { self[TrapProbeKey.self] }
        set { self[TrapProbeKey.self] = newValue }
    }
}

private enum WritePhase {
    case layout, prepaint, paint
}

/// Sets the frame's root environment from inside one phase.
private struct RootWriter: Element {
    let phase: WritePhase

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        if phase == .layout { pass.frame.rootEnvironment = EnvironmentValues() }
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        if phase == .prepaint { pass.frame.rootEnvironment = EnvironmentValues() }
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        if phase == .paint { pass.frame.rootEnvironment = EnvironmentValues() }
    }
}

@MainActor
private func renderRootWriter(_ phase: WritePhase) {
    let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1,
                      layoutAuthority: .proposal)
    var root = Row { RootWriter(phase: phase) }
    frame.render(&root)
}

/// **T1.** A root environment write during a render traps, in each of the
/// three phases (ruling EV-Z). One arm per phase, because a flag cleared too
/// early — at the top of `paint` rather than at the end of `render` — would
/// leave the layout and prepaint arms trapping and the paint arm silent.
@Test func aRootEnvironmentWriteDuringARenderTraps() async {
    let layout = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        await MainActor.run { renderRootWriter(.layout) }
    }
    let layoutErr = String(decoding: layout?.standardErrorContent ?? [], as: UTF8.self)
    #expect(layoutErr.contains("rootEnvironment set during render"),
            "the layout arm aborted, but not at EV-Z's precondition:\n\(layoutErr)")

    let prepaint = await #expect(processExitsWith: .failure,
                                 observing: [\.standardErrorContent]) {
        await MainActor.run { renderRootWriter(.prepaint) }
    }
    let prepaintErr = String(decoding: prepaint?.standardErrorContent ?? [], as: UTF8.self)
    #expect(prepaintErr.contains("rootEnvironment set during render"),
            "the prepaint arm aborted, but not at EV-Z's precondition:\n\(prepaintErr)")

    let paint = await #expect(processExitsWith: .failure,
                              observing: [\.standardErrorContent]) {
        await MainActor.run { renderRootWriter(.paint) }
    }
    let paintErr = String(decoding: paint?.standardErrorContent ?? [], as: UTF8.self)
    #expect(paintErr.contains("rootEnvironment set during render"),
            "the paint arm aborted, but not at EV-Z's precondition:\n\(paintErr)")
}

/// Counts the child's paints, and traps unless each reads the scope.
@MainActor
private final class PaintCount {
    var n = 0
}

private struct ScopedReader: Element {
    let count: PaintCount

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        precondition(pass.environment.trapProbe == 1, "the scope did not reach the child")
        count.n += 1
    }
}

@MainActor
private func writeRenderWriteRender() {
    let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1,
                      layoutAuthority: .proposal)
    let count = PaintCount()

    frame.rootEnvironment = EnvironmentValues()
    var first = Row { ScopedReader(count: count).environment(\.trapProbe, 1) }
    frame.render(&first)

    frame.rootEnvironment = EnvironmentValues()
    var second = Row { ScopedReader(count: count).environment(\.trapProbe, 1) }
    frame.render(&second)

    precondition(count.n == 2, "both renders must reach the child's paint")
}

/// **T2.** Positive control for T1, and a pin of its own (ruling EV-Z): a root
/// write before a render and between two renders of one frame — after a scope
/// has pushed — does not trap, and the second render's scope still reaches its
/// child. A precondition written as "no scope was ever pushed" or "never after
/// the first render" traps here.
@Test func aRootEnvironmentWriteBeforeAndBetweenRendersDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run { writeRenderWriteRender() }
    }
}
