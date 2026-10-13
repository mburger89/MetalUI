import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C14b design phase (`SB-A`): the counted baseline of the bracket window's node drag at
// e85cb07a, before any retained subtree. Counts, never time.

/// The fixture window: 1440 x 900 at scale 2, dark, text through `textSystem`.
@MainActor func bracketWindow(arm: BracketArm = .value, model: BracketModel = BracketModel(),
                              textSystem: @escaping @MainActor () -> any TextSystem) throws -> (TestWindow, BracketModel) {
    let viewport = BracketViewport()
    let window = try TestWindow(size: bracketWindowSize, colorScheme: .dark, scaleFactor: 2, textSystem: textSystem) {
        bracketRoot(arm: arm, model: model, viewport: viewport)
    }
    return (window, model)
}

/// The window point on Fillet's header (node 17 sits at canvas x 0, y 100 and node 18 overlaps it from x 40, so x 20; the canvas
/// starts 288 pt below the window's top: 36 top bar + 32 header + 220 library).
let bracketFilletPress = Point(x: Pixels(20), y: Pixels(400))

@MainActor func bracketDragFrames(arm: BracketArm, steps: Int) throws
    -> (frames: [FrameWork], counting: CountingTextSystem, window: TestWindow, model: BracketModel) {
    let counting = CountingTextSystem(harnessTextSystem())
    let (window, model) = try bracketWindow(arm: arm, textSystem: { counting })
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }   // warm
    window.resetFrameWork(); counting.reset(); BracketStats.reset()
    window.drag(from: bracketFilletPress,
                to: Point(x: Pixels(20 + 2 * Float(steps)), y: Pixels(400)), steps: steps)
    return (window.frameWork, counting, window, model)
}

@Test(arguments: [BracketArm.value, BracketArm.environment, BracketArm.panels]) @MainActor
func theBracketNodeDragRebuildsTheWholeWindow(arm: BracketArm) throws {
    let steps = 20
    let r = try bracketDragFrames(arm: arm, steps: steps)
    let w = r.frames
    let sum = w.dropFirst().reduce(w[0], +)
    print("SB baseline \(arm) frames=\(w.count) nodeBodies=\(BracketStats.nodeBodies) wireBodies=\(BracketStats.wireBodies) measures=\(r.counting.measures) places=\(r.counting.places) layouts=\(r.counting.layouts) rasters=\(r.counting.rasters) \(sum)")
    print("SB baseline \(arm) one drag frame: \(w[w.count / 2])")
    print("SB fillet x=\(r.model.nodes[BracketModel.filletIndex].x) visible=\(r.model.visibleNodes.count)")
}

@Test @MainActor func bracketDebugLocations() throws {
    let counting = CountingTextSystem(harnessTextSystem())
    let (window, _) = try bracketWindow(arm: .value, textSystem: { counting })
    window.window.setNeedsRedraw(); window.tick()
    for e in try window.elements(where: { _ in true }) {
        let t = e.label ?? e.value ?? ""
        if ["Fillet", "Chamfer", "Plane", "Output", "Bracket", "Project > Bracket", "Node library", "Section 0", "Edge Filter", "Boolean"].contains(t) {
            print("SB loc \(t) x=\(e.frame.origin.x.value) y=\(e.frame.origin.y.value) w=\(e.frame.size.width.value) h=\(e.frame.size.height.value)")
        }
    }
}
