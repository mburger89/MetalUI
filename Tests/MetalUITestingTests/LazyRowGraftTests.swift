import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// G49 (record 414): the shape of Alloy's chat transcript, `ScrollViewReader > ScrollView(.defaultScrollAnchor(.bottom),
// .contentMargins(.bottom)) > LazyVStack.padding > ForEach(blocks) { Row.equatable() }`, with one row streaming text. Counts only.

let g49Inset = Edges(top: Pixels(12), right: Pixels(16), bottom: Pixels(12), left: Pixels(16))

struct G49Block: Equatable { let id: Int; let kind: Int; let text: String }

/// Fifty settled blocks of five kinds, then the streaming one (id 999): its text grows by one word per step.
let g49Blocks: [G49Block] = (0..<50).map {
    G49Block(id: $0, kind: $0 % 5, text: "block \($0) some words that wrap onto more than one line in a narrow column\n\nsecond paragraph \($0)")
}
func g49Streaming(_ step: Int) -> String { "streaming" + (0..<step).map { " wordnumber\($0)" }.joined() }

struct G49Row: Component, @MainActor Equatable {
    let block: G49Block
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 0) {
            switch block.kind {
            case 0: Text(block.text).padding(Edges(all: Pixels(8))).background(.accent)
            case 1:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(block.text.components(separatedBy: "\n\n"), id: \.self) { p in Text(p) }
                }
            case 2:
                HStack(spacing: 4) {
                    Color(red: 0.5, green: 0.5, blue: 0.5).frame(width: Pixels(10), height: Pixels(10))
                    Text(block.text)
                }
            case 3: HStack(spacing: 4) { Text("Read"); Text(block.text) }
            default: VStack(alignment: .leading, spacing: 4) { Text(block.text); Button("Allow") {} }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `full` is Alloy's transcript; `noPadding` drops the stack's padding.
enum G49Shape: String, CaseIterable, CustomStringConvertible {
    case full, noPadding
    var description: String { rawValue }
}

struct G49Root: Component {
    let side: RPSide
    let shape: G49Shape
    var rows: some ElementGroup {
        ForEach(g49Blocks + [G49Block(id: 999, kind: 1, text: g49Streaming(Int(side.inputs.offset)))], id: \.id) { b in G49Row(block: b).equatable() }
    }
    var content: some ElementGroup {
        ScrollViewReader { _ in
            ScrollView {
                switch shape {
                case .full: LazyVStack(alignment: .leading, spacing: Pixels(10)) { rows }.padding(g49Inset)
                case .noPadding: LazyVStack(alignment: .leading, spacing: Pixels(10)) { rows }
                }
            }
            .defaultScrollAnchor(.bottom).contentMargins(.bottom, Pixels(40), for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The transcript in a 420 x 600 window at scale 2; `inputs.offset` is the number of words the streaming block holds.
@MainActor func g49Pair(_ shape: G49Shape = .full, graft: Bool = true) throws -> RPPair<some Element> {
    try RPPair(size: sz(420, 600), scale: 2, warm: 8, accessibility: false, graft: graft) { side in
        VStack(spacing: 0) { G49Root(side: side, shape: shape) }
    }
}

/// One streamed word on both sides, settled, one frame each.
@MainActor func g49Step(_ pair: RPPair<some Element>) async {
    pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
    await rsSettle()
    pair.redraw()
}

private let g49VerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read"

/// `G49-A`, record 414: one streamed word per frame at the end of a bottom-anchored transcript. The rows above the streaming
/// one are grafted and replay their prepaint every frame, translated when the anchor moves the offset (a wrapped line grows the
/// extent); the frame is never redone, so the work is the streaming row's alone and does not scale with the visible rows. Red on
/// arrival at 4d030e94: the scroller's content extent was part of the prepaint key, the first wrap missed every row's ledger
/// (`ledgerKey.extras.scroller`), a grafted row cannot prepaint (`RK-C`), the frame was redone and every replay backed off
/// (`RK-D`): 48 requests a frame (53 to 58 after the first wrap), 2 redos in 24 frames, 1 graft a frame.
@Test(.enabled(if: !rsVerifying, g49VerifyingNote), arguments: G49Shape.allCases) @MainActor
func aStreamingRowKeepsTheRowsAboveOnTheReplayPath(shape: G49Shape) async throws {
    let pair = try g49Pair(shape)
    pair.frames = []
    var moved = 0
    for step in 0..<24 {
        await g49Step(pair)
        let f = try #require(pair.frames.last)
        #expect(f.retainedRedos == 0 && f.retainedBackoffFrames == 0, "step \(step): redo \(f.retainedRedos), backoff \(f.retainedBackoffFrames)")
        #expect(f.elementRequests <= 12, "step \(step): the streaming row's work only: \(f.elementRequests) requests")
        #expect(f.elementPrepaints <= 14, "step \(step): \(f.elementPrepaints) prepaints")
        #expect(f.retainedGrafts >= 7, "step \(step): the rows above graft: \(f.retainedGrafts)")
        #expect(f.retainedPrepaintHits >= 7, "step \(step): and replay their prepaint: \(f.retainedPrepaintHits)")
        if f.retainedTranslated > 0 { moved += 1 }
        try pair.compare("step \(step)")
    }
    #expect(moved >= 5, "the anchor moved the rows in \(moved) of 24 frames: a run that never moves them proves nothing")
}

/// A frame that changes nothing in the same transcript costs the scroller's own 4 requests, with no redo: the steady frame pays nothing extra
/// (the same 4 before `G49-A`).
@Test(.enabled(if: !rsVerifying, g49VerifyingNote)) @MainActor func aQuietTranscriptFrameCostsOnlyTheScroller() async throws {
    let pair = try g49Pair(.full)
    for _ in 0..<3 { await g49Step(pair) }
    pair.frames = []
    for _ in 0..<4 { pair.redraw() }
    for (i, f) in pair.frames.enumerated() {
        #expect(f.retainedRedos == 0, "frame \(i)")
        #expect(f.elementRequests == 4, "frame \(i): \(f.elementRequests) requests")
    }
    try pair.compare("quiet")
}
