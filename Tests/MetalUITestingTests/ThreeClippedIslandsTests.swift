import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Alloy report (2026-11-13): `.clipShape(RoundedRectangle(cornerRadius:))` on all three lower islands of an HSplitView in
// one big tree crashed the first frame (EXC_BAD_ACCESS in swift_retain). This is the headless shape of that window: three
// panes, each clipped, each holding content whose own rounded boxes cross the clip.

private struct IslandRows: Component {
    let count: Int
    var content: some ElementGroup {
        ScrollView {
            VStack(alignment: .leading, spacing: Pixels(4)) {
                ForEach(Array(0..<count), id: \.self) { i in
                    Text("Row \(i) with some text")
                        .padding(Pixels(8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.3), in: RoundedRectangle(cornerRadius: Pixels(8)))
                        .overlay { RoundedRectangle(cornerRadius: Pixels(8)).stroke(Color.white.opacity(0.2)) }
                }
            }
            .padding(Pixels(6))
        }
    }
}

private struct IslandCode: Component {
    let buffer: CodeBuffer
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: Pixels(6)))
            .overlay(alignment: .top) {
                Text("bar").padding(Pixels(6)).frame(maxWidth: .infinity)
                    .background(alignment: .center) { glassBar(10) }
            }
    }
}

private struct IslandChat: Component {
    @State var text = ""
    var content: some ElementGroup {
        ZStack(alignment: .bottom) {
            IslandRows(count: 30)
            VStack(spacing: Pixels(0)) {
                VStack(spacing: Pixels(0)) { TextField("Message", text: $text) }.padding(Pixels(8))
                    .background(alignment: .center) { glassBar(12) }
            }.padding(Pixels(10))
        }
    }
}

@MainActor private func glassBar(_ r: Float) -> some ElementGroup {
    let shape = RoundedRectangle(cornerRadius: Pixels(r))
    return shape.fill(Color.clear).background(.thickMaterial, in: shape).glassEffect(.regular.tint(Color.gray.opacity(0.3)), in: shape)
        .overlay { shape.stroke(Color.white.opacity(0.2)) }
}

@MainActor private func fill(_ shape: RoundedRectangle) -> some ElementGroup {
    shape.fill(Color.gray.opacity(0.4)).overlay { shape.stroke(Color.white.opacity(0.2)) }
}

private extension ElementGroup {
    @MainActor func island(clip: Bool) -> some ElementGroup {
        let shape = RoundedRectangle(cornerRadius: Pixels(10))
        return VStack(spacing: Pixels(0)) { self }
            .clipShape(clip ? shape : RoundedRectangle(cornerRadius: Pixels(0)))
            .background(alignment: .center) { fill(shape) }
    }
}

@MainActor private func islandRow(_ clips: (Bool, Bool, Bool), buffer: CodeBuffer) -> some ElementGroup {
    HSplitView {
        IslandRows(count: 40).island(clip: clips.0)
            .frame(minWidth: Pixels(200), idealWidth: Pixels(250), maxWidth: Pixels(380))
        IslandChat().island(clip: clips.1)
            .frame(minWidth: Pixels(320), maxWidth: .infinity)
        IslandCode(buffer: buffer).island(clip: clips.2)
            .frame(minWidth: Pixels(240), idealWidth: Pixels(360), maxWidth: Pixels(800))
    }
    .splitViewDivider(.hidden, thickness: 6)
    .padding(Pixels(6))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

@MainActor
struct ThreeClippedIslandsTests {
    /// Every clip combination draws the first frames, and the same text: rounded island clips are per primitive (no offscreen
    /// group for content that stays inside them), so clipping all three draws what clipping none does (`CM-B`, record 292).
    @Test(arguments: [(true, false, false), (true, true, false), (true, true, true)])
    func firstFramesDrawTheSameWithEveryClip(clips: (Bool, Bool, Bool)) throws {
        func window(_ clips: (Bool, Bool, Bool)) throws -> TestWindow {
            let buffer = CodeBuffer(codeText(lines: 200))
            let w = try TestWindow(size: Size(width: Pixels(1200), height: Pixels(800)), scaleFactor: 2, textSystem: harnessTextSystem) {
                VStack(spacing: Pixels(0)) {
                    Text("title").frame(height: Pixels(36))
                    islandRow(clips, buffer: buffer)
                }
                .background { Color.black.opacity(0.8).containerBackground(.thinMaterial, for: .window) }
            }
            for _ in 0..<6 { w.window.setNeedsRedraw(); w.tick() }
            return w
        }
        let plain = try window((false, false, false))
        let w = try window(clips)
        #expect(plain.framesDrawn >= 1 && w.framesDrawn >= 1)
        #expect(w.allGlyphs.count == plain.allGlyphs.count, "the same text: \(w.allGlyphs.count) against \(plain.allGlyphs.count)")
        #expect(w.scene.groupScenes.isEmpty, "content inside the island clips builds no offscreen group")
    }
}
