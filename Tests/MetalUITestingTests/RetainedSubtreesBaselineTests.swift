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

@MainActor func bracketDragFrames(arm: BracketArm, steps: Int, retained: Bool = true, prepaint: Bool = true) throws
    -> (frames: [FrameWork], counting: CountingTextSystem, window: TestWindow, model: BracketModel) {
    let counting = CountingTextSystem(harnessTextSystem())
    let (window, model) = try bracketWindow(arm: arm, textSystem: { counting })
    window.window.testingRetainedSubtrees = retained
    window.window.testingRetainedPrepaint = prepaint
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }   // warm
    window.resetFrameWork(); counting.reset(); BracketStats.reset()
    window.drag(from: bracketFilletPress,
                to: Point(x: Pixels(20 + 2 * Float(steps)), y: Pixels(400)), steps: steps)
    return (window.frameWork, counting, window, model)
}

/// What one arm of the node drag costs with no retained subtree, literal (`SB-Q`: a print is
/// not a pin). Counted at e85cb07a by the design phase, re-counted at lane 1's step 1 with the
/// element counters; with `testingRetainedSubtrees = false` these hold on every later commit.
private struct BaselineArm {
    let arm: BracketArm
    let evaluations: Int, skips: Int, refusals: Int
    let nodeBodies: Int
}
private let baselineArms = [
    BaselineArm(arm: .value, evaluations: 3, skips: 29, refusals: 0, nodeBodies: 20),
    BaselineArm(arm: .environment, evaluations: 2, skips: 19, refusals: 11, nodeBodies: 231),
    BaselineArm(arm: .panels, evaluations: 3, skips: 32, refusals: 0, nodeBodies: 20),
]

@Test(arguments: [BracketArm.value, BracketArm.environment, BracketArm.panels]) @MainActor
func theBracketNodeDragRebuildsTheWholeWindow(arm: BracketArm) throws {
    let expected = try #require(baselineArms.first { $0.arm == arm })
    let steps = 20
    let r = try bracketDragFrames(arm: arm, steps: steps, retained: false)
    let w = r.frames
    try #require(w.count == 21)
    let f = w[w.count / 2]   // a drag frame
    // The build recursion, layout and the scene: the same in every arm (the arm changes who evaluates).
    #expect(f.builds == 1)
    // Counted at e85cb07a: 81 / 805 / 527 / 1106 / 30. Lane 2 (`SB-AD`) keyed two more leaves for the
    // layout memo (a `Color` as a view, an empty legacy container), so a subtree holding one now has a
    // signature and the same frame measures less: re-counted here, retention off.
    #expect(f.layoutMeasureCalls == 52)
    #expect(f.layoutCacheHits == 366)
    #expect(f.layoutCacheMisses == 217)
    #expect(f.layoutMemoHits == 1258)
    #expect(f.layoutMemoMisses == 55)
    #expect(f.layoutMemoRootHits == 0)
    #expect(f.layoutSignatureNodes == 844)
    #expect(f.rects == 182)
    #expect(f.glyphs == 550)
    #expect(f.images == 6)
    // The two changed wires: rasterized on the CPU every frame whatever retention does (`GX-B`).
    #expect(f.rasterizedPixels == 78312)
    #expect(f.newTextures == 2)
    // Who evaluates: the arm.
    #expect(f.contentEvaluations == expected.evaluations)
    #expect(f.contentSkips == expected.skips)
    #expect(f.contentRefusals == expected.refusals)
    // The element work of a whole-window rebuild.
    #expect(f.elementRequests == 798)
    #expect(f.elementPrepaints == 886)
    #expect(f.elementPaints == 1084)
    // Nothing retained.
    #expect(f.retainedHits == 0)
    #expect(f.retainedMisses == 0)
    #expect(f.retainedIneligible == 0)
    #expect(f.retainedSkippedPrepaints == 0)
    #expect(f.retainedSkippedPaints == 0)
    // Over the 21 frames: the user-level body counts and the text system's calls.
    #expect(BracketStats.nodeBodies == expected.nodeBodies)
    #expect(BracketStats.wireBodies == 40)
    // A verified memo hit measures again at the seam, which is the point of that run (`layoutMemoVerifying`).
    if !layoutMemoVerifying { #expect(r.counting.measures == 2898) }
    #expect(r.counting.places == 2814)
    #expect(r.model.nodes[BracketModel.filletIndex].x == 720)
    #expect(r.model.visibleNodes.count == 11)
}

