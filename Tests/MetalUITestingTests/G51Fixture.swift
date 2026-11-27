import Foundation
@testable import MetalUI
import MetalUIScene
import Observation
import MetalUITesting
import Testing

// G51 (record 420): the shape of Alloy's streaming transcript, `ScrollView(.defaultScrollAnchor(.bottom)) > LazyVStack > ForEach >
// ChatRow.equatable()` with rounded chrome and `.equatable()` paragraphs, one row streaming a word a frame, the whole of it inside
// a composite scope (`island`) so every text draw is a leaf group and every record holds captured primitives.

struct G51Block: Equatable { let id: Int; let title: String; let paragraphs: [String] }

func g51Paragraph(_ seed: Int, _ words: Int) -> String {
    (0..<words).map { "word\(seed &* 31 &+ $0 % 17)" }.joined(separator: " ")
}

func g51Blocks(_ n: Int, longFirst: Bool, paragraphWords: Int = 110) -> [G51Block] {
    var out: [G51Block] = []
    if longFirst {
        out.append(G51Block(id: -1, title: "Thinking", paragraphs: (0..<60).map { g51Paragraph($0, 60) }))
    }
    for i in 0..<n {
        out.append(G51Block(id: i, title: "Message \(i)", paragraphs: (0..<3).map { g51Paragraph(i * 7 + $0, paragraphWords) }))
    }
    return out
}

struct G51Para: Component, @MainActor Equatable {
    let text: String
    var content: some ElementGroup { Text(text).frame(maxWidth: .infinity, alignment: .leading) }
}

struct G51ChatRow: Component, @MainActor Equatable {
    let block: G51Block
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.title)
            ForEach(Array(block.paragraphs.enumerated()), id: \.offset) { _, p in G51Para(text: p).equatable() }
        }
        .padding(Edges(all: Pixels(10)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent.opacity(0.12))
        .cornerRadius(Pixels(8))
    }
}

@Observable @MainActor final class G51Inputs { var words = 0 }

struct G51Root: Component {
    let blocks: [G51Block]
    let inputs: G51Inputs
    var island = true
    var content: some ElementGroup {
        let streaming = G51Block(id: 999, title: "Streaming",
                                 paragraphs: [g51Paragraph(1, 20), g51Paragraph(2, 12) + " " + (0..<inputs.words).map { "tok\($0)" }.joined(separator: " ")])
        let scroller = ScrollView {
            LazyVStack(alignment: .leading, spacing: Pixels(10)) {
                ForEach(blocks + [streaming], id: \.id) { b in G51ChatRow(block: b).equatable() }
            }
            .padding(Edges(top: Pixels(12), right: Pixels(16), bottom: Pixels(12), left: Pixels(16)))
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        if island {
            VStack(spacing: 0) { scroller }
                .padding(Edges(all: Pixels(6)))
                .clipShape(RoundedRectangle(cornerRadius: Pixels(10)))
                .padding(Edges(all: Pixels(4)))
                .clipShape(RoundedRectangle(cornerRadius: Pixels(14)))
                .compositingGroup().opacity(0.98)
        } else {
            scroller
        }
    }
}

/// The transcript in a 600 x 800 window at scale 2 with no accessibility client, warmed: six redraws, then ten streamed words.
@MainActor func g51Window(rows: Int, longFirst: Bool = false, island: Bool = true, inputs: G51Inputs, relatesChangedClip: Bool = true) async throws -> TestWindow {
    let blocks = g51Blocks(rows, longFirst: longFirst)
    let options = HeadlessPlatformWindow.Options(scaleFactor: 2, accessibilityClientActive: false)
    let w = try TestWindow(size: sz(600, 800), scaleFactor: 2, options: options, textSystem: harnessTextSystem) {
        VStack(spacing: 0) { G51Root(blocks: blocks, inputs: inputs, island: island) }
    }
    w.window.testingRelatesChangedClip = relatesChangedClip
    for _ in 0..<6 { w.window.setNeedsRedraw(); w.tick() }
    for _ in 0..<10 { inputs.words += 1; await rsSettle(); w.window.setNeedsRedraw(); w.tick() }
    return w
}
