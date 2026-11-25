import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// G52 (record 422): a paragraph that grows every frame paints a few glyphs more each time, and the scene's glyph array a frame
// builds must be the size class the frame before built, not an exact count a little larger. Counts and capacities, not time.

@Observable @MainActor final class G52Model {
    var text: String
    init(_ text: String) { self.text = text }
}

private func g52Words(_ n: Int, from start: Int = 0) -> String { (start..<(start + n)).map { "word\($0 % 97)" }.joined(separator: " ") }

/// **G52-A** Eight frames of a paragraph of about 17,000 glyphs growing by about 400 a frame: the glyph count differs every frame,
/// the capacity of the scene's glyph array stays in at most two classes (it is one unless a class boundary falls in the run). Without
/// the classes every frame's array is a different size, so malloc never reuses the block it freed. Mutations: `Scene.reserveCapacity`
/// and the arrays `finalize()` reserves at the exact count.
@Test @MainActor func aGrowingParagraphsSceneKeepsOneGlyphCapacityClassAcrossFrames() throws {
    let model = G52Model(g52Words(2_800))
    let window = try TestWindow(size: sz(600, 800), textSystem: harnessTextSystem) { ProposalScrollView { Text(model.text) } }
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    var counts = Set<Int>(), capacities = Set<Int>()
    for step in 0..<8 {
        model.text += " " + g52Words(60, from: 3_000 + step * 60)
        window.window.setNeedsRedraw(); window.tick()
        counts.insert(window.scene.glyphs.count); capacities.insert(window.scene.glyphs.capacity)
    }
    #expect(counts.count == 8, "the glyph count grew every frame: \(counts.sorted())")
    #expect((counts.min() ?? 0) > 16_000, "a scene of this size is the point: \(counts.sorted())")
    #expect(capacities.count <= 2, "capacities \(capacities.sorted()) for counts \(counts.sorted())")
}
