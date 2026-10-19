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
