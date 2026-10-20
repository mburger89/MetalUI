import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C14b-3 (`RW-`): the orbit-with-panel scenario. A 3D viewport orbit changes only what the viewport reads: each frame
// bumps the viewport token (the `GPUSurface`'s `value:`) and asks for a redraw, and nothing in the panels changes.

/// The panels fixture with the viewport's token reachable from the test.
@MainActor struct BracketOrbit {
    let window: TestWindow
    let model: BracketModel
    let viewport: BracketViewport
    let counting: CountingTextSystem

    init(arm: BracketArm = .panels, retained: Bool = true, prepaint: Bool = true, graft: Bool = true) throws {
        let counting = CountingTextSystem(harnessTextSystem())
        let model = BracketModel()
        let viewport = BracketViewport()
        let window = try TestWindow(size: bracketWindowSize, colorScheme: .dark, scaleFactor: 2, textSystem: { counting }) {
            bracketRoot(arm: arm, model: model, viewport: viewport)
        }
        window.window.testingRetainedSubtrees = retained
        window.window.testingRetainedPrepaint = prepaint
        window.window.testingRetainedGraft = graft
        self.window = window; self.model = model; self.viewport = viewport; self.counting = counting
    }

    /// One orbit frame: what a viewport drag does.
    func orbitFrame() {
        viewport.token += 1
        window.window.setNeedsRedraw()
        window.tick()
    }
}

/// The work of `frames` orbit frames after `warm` warm frames, one record per frame.
@MainActor func bracketOrbitFrames(arm: BracketArm = .panels, frames: Int, warm: Int = 3, retained: Bool = true,
                                   prepaint: Bool = true, graft: Bool = true) throws -> (frames: [FrameWork], orbit: BracketOrbit) {
    let orbit = try BracketOrbit(arm: arm, retained: retained, prepaint: prepaint, graft: graft)
    for _ in 0..<warm { orbit.orbitFrame() }
    orbit.window.resetFrameWork()
    for _ in 0..<frames { orbit.orbitFrame() }
    return (orbit.window.frameWork, orbit)
}

/// An element that **plain**-writes `@State` in the build, the prepaint and the paint (`withState` with no `unchanged:`): the
/// separating control for every read-only conversion, since a `TextField` or a `ScrollView` is eligible now (`RW-S`). A plain
/// write taints every open window by name (`stateWrite`) whatever it stores.
struct PlainWriteLeaf: Element {
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        pass.withState(id, initial: 0) { $0 += 0 }
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 40, height: 20)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        pass.withState(id, initial: 0) { $0 += 0 }
    }
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        pass.withState(id, initial: 0) { $0 += 0 }
        pass.fill(bounds, color: Hsla(h: 0.3, s: 0.5, l: 0.5, a: 1))
    }
}
