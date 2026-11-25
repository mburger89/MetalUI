import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Observation
import Testing

// G48 (ruling `HS-M`, record 413): the Alloy chat-pane shape, MetalUI-only. An `HSplitView` of three framed panes whose
// middle one holds a scroller over a lazy stack of rows, the last row a paragraph that grows by a word each frame. Every
// width the paragraph is shaped at in a frame is read from `ShapingTrace`'s lines.

@Observable @MainActor private final class Stream { var words = 20 }

private let sentence = "streaming assistant reply words keep arriving one after another "

private struct StreamingPane: Component {
    let stream: Stream
    var content: some ElementGroup {
        let text = String(repeating: sentence, count: stream.words / 8 + 1) + "END\(stream.words)"
        VStack(spacing: Pixels(0)) {
            HStack(spacing: Pixels(0)) {
                Color.red.frame(width: Pixels(4))
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Pixels(10)) {
                            ForEach(0..<2, id: \.self) { _ in
                                ProposalText("first row").frame(maxWidth: .infinity, alignment: .leading)
                            }
                            VStack(alignment: .leading, spacing: Pixels(0)) { ProposalText(text) }
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(Edges(top: Pixels(12), right: Pixels(16), bottom: Pixels(12), left: Pixels(16)))
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// In-memory autosave store (`HS-G`): a split view with an entry here has the user's sizes, so its solve reads no pane's ideal.
@MainActor private final class MemoryStore: SplitViewAutosaveStore {
    var saved: [String: [Double]] = [:]
    func paneSizes(forName name: String) -> [Double]? { saved[name] }
    func setPaneSizes(_ sizes: [Double], forName name: String) { saved[name] = sizes }
}

/// The Alloy shape: sidebar 200/250/380, the chat pane `frame(minWidth: 320, maxWidth: .infinity)`, files 240...800. `wrapped`
/// puts the chat pane behind zero padding: not a frame, so the split probes it as it always did (the control).
@MainActor private func splitFixture(_ stream: Stream, store: MemoryStore?, wrapped: Bool = false) -> some Element {
    let split = HSplitView {
        Color.blue.frame(minWidth: Pixels(200), idealWidth: Pixels(250), maxWidth: Pixels(380))
        if wrapped {
            StreamingPane(stream: stream).frame(minWidth: Pixels(320), maxWidth: .infinity).padding(Pixels(0))
        } else {
            StreamingPane(stream: stream).frame(minWidth: Pixels(320), maxWidth: .infinity)
        }
        Color.green.frame(minWidth: Pixels(240), maxWidth: Pixels(800))
    }
    return VStack(spacing: Pixels(0)) {
        if let store { split.splitViewAutosaveName("g48", store: store) } else { split }
    }
}

/// The widths the growing paragraph was shaped at in each of `frames` streamed frames (its misses, as `METALUI_TRACE_SHAPING`
/// lists them), one sorted list per frame, after a first frame that has settled the window. `wrapped` is the control;
/// `store` holds the user's sizes.
@MainActor private func streamedWidths(frames: Int, saved: [Double]? = nil, wrapped: Bool = false) async throws -> [[Double]] {
    let lines = LineBox()
    ShapingTrace.sink = { lines.lines.append($0) }
    ShapingTrace.active = true
    defer { ShapingTrace.active = false; ShapingTrace.sink = nil }
    let stream = Stream()
    let store = saved.map { sizes -> MemoryStore in
        let store = MemoryStore()
        store.saved["g48"] = sizes
        return store
    }
    let w = try harnessWindow(size: sz(1100, 700)) { splitFixture(stream, store: store, wrapped: wrapped) }
    try await w.runUntilIdle()
    var perFrame: [[Double]] = []
    for _ in 0..<frames {
        lines.lines.removeAll()
        stream.words += 8
        w.tick()
        let widths = lines.lines.flatMap { line -> [Double] in
            // `"streaming assistant reply words keep arr…"(NotoSans-Regular 13 w=284)`: only the paragraph's misses.
            line.components(separatedBy: "\"streaming").dropFirst().compactMap { entry -> Double? in
                guard let range = entry.range(of: " w="), let end = entry[range.upperBound...].firstIndex(of: ")") else { return nil }
                return Double(entry[range.upperBound..<end])
            }
        }
        perFrame.append(widths.sorted())
    }
    return perFrame
}
@MainActor private final class LineBox { var lines: [String] = [] }

/// **1 (G48)** The chat pane's three probes, as they were: the control (the pane behind a wrapper that is not a frame) shapes the
/// growing paragraph at five widths a frame, and 284 (`320 - 4 - 2 * 16`, the pane's minimum through the stripe and the padding) is
/// the split's minimum probe. Mutation (of the control's premise): none; it pins that the wrapper still reaches the old path.
@Test @MainActor func aPaneBehindANonFrameIsStillProbedAtItsMinimum() async throws {
    let frames = try await streamedWidths(frames: 3, wrapped: true)
    for widths in frames {
        #expect(widths.count == 5 && widths.contains(284), "\(widths)")
    }
}

/// **2 (G48)** With no saved sizes the split reads each pane's ideal, and the chat pane has none (`frame(minWidth:maxWidth:)`), so
/// that probe measures its subtree: the lazy stack's width at nil is its first row's ideal (50.43 here). The minimum probe (284) and
/// the maximum probe no longer measure it: four widths a frame, not five: the zero probe of the stripe row's flexibility (0.5), the
/// ideal's lazy width, the proposal the pane is placed at (572) and the width the text paints at, its widest line (a text is drawn at
/// the width it measured, `ProposalText`). Mutations: `determinedExtent` always `nil` (284 returns); `SplitLayout.limits` measuring
/// every proposal (284 returns).
@Test @MainActor func theChatPanesMinimumAndMaximumProbesNoLongerShapeTheParagraph() async throws {
    let frames = try await streamedWidths(frames: 3)
    for widths in frames {
        #expect(!widths.contains(284), "\(widths)")
        #expect(widths.count == 4, "\(widths)")
        #expect(widths.filter { $0 == 572 }.count == 1, "the pane's own width, once: \(widths)")
    }
}

/// **3 (G48)** With the user's sizes (an autosaved split, a dragged divider) the solve reads no ideal, so the split probes the chat
/// pane not at all, and the stripe row's flexibility probe at infinity is the frame's own answer: the paragraph is shaped at three
/// widths a frame, the least a stack and a text allow: the zero probe of the row's flexible child (0.5), the pane's width and the
/// painted width. Mutations: `solveReadsIdeals` always `true` (the ideal's 50.43 returns); `mainExtent` in `solveLinearStack`
/// measuring at infinity (50.43 returns).
@Test @MainActor func withTheUsersSizesTheParagraphIsShapedAtThreeWidths() async throws {
    let frames = try await streamedWidths(frames: 3, saved: [250, 608, 240])
    for widths in frames {
        #expect(widths.count == 3, "\(widths)")
        #expect(widths.contains(0.5) && widths.contains { $0 > 500 && $0 < 572 } && widths.contains(572), "\(widths)")
    }
}

// MARK: - Parity: the same panes, probed and not

/// One pane's frame bounds along the axis (any may be absent). `frame(minWidth:idealWidth:maxWidth:)` with none of them is a flexible
/// frame that is never determined, the nearest a frame gets to no frame; a bare pane is tested apart.
private struct PaneSpec: CustomStringConvertible {
    var minimum: Float?
    var ideal: Float?
    var maximum: Float?
    var description: String { "min=\(minimum.map { "\($0)" } ?? "-") ideal=\(ideal.map { "\($0)" } ?? "-") max=\(maximum.map { "\($0)" } ?? "-")" }
}

private let paneSpecs: [PaneSpec] = [
    PaneSpec(minimum: 50, ideal: 100, maximum: 200), PaneSpec(minimum: 40, maximum: 160), PaneSpec(maximum: 150),
    PaneSpec(minimum: 80), PaneSpec(ideal: 130), PaneSpec(minimum: 30, ideal: 60), PaneSpec(minimum: 100, maximum: .infinity),
    PaneSpec(), PaneSpec(minimum: 90, ideal: 90, maximum: 90),
]

@MainActor @ProposalContentBuilder
private func pane(_ color: Color, _ spec: PaneSpec, wrapped: Bool) -> some ProposalElementGroup {
    if wrapped {
        color.frame(minWidth: spec.minimum.map { Pixels($0) }, idealWidth: spec.ideal.map { Pixels($0) },
                    maxWidth: spec.maximum.map { Pixels($0) }).padding(Pixels(0))
    } else {
        color.frame(minWidth: spec.minimum.map { Pixels($0) }, idealWidth: spec.ideal.map { Pixels($0) },
                    maxWidth: spec.maximum.map { Pixels($0) })
    }
}

@MainActor private func placed(_ window: TestWindow) -> [[Float]] {
    window.scene.rects.filter { $0.background.a > 0 && $0.bounds.size.height == 300 && $0.bounds.size.width > 1 }
        .sorted { $0.bounds.origin.x < $1.bounds.origin.x }.map { [$0.bounds.origin.x, $0.bounds.size.width] }
}

@MainActor private func placedRows(_ window: TestWindow) -> [[Float]] {
    window.scene.rects.filter { $0.background.a > 0 && $0.bounds.size.width == 400 && $0.bounds.size.height > 1 }
        .sorted { $0.bounds.origin.y < $1.bounds.origin.y }.map { [$0.bounds.origin.y, $0.bounds.size.height] }
}

/// **4 (G48)** Skipping the probes a frame answers by itself changes no pane's size or place: every sixth ordered triple of nine
/// pane specs (min, ideal, max in every combination the Alloy shape and its neighbours use, one with nothing set), three window
/// widths, and no saved sizes / matching saved sizes / saved sizes of the wrong count, laid out with the panes bare against the same
/// panes behind zero padding (not a frame: probed as before). **The comparison is the pin**: the wrapped run is the old code path.
/// Mutations: the ideal skipped when sizes are absent (`solveReadsIdeals` always `false`); `framedDetermined` answering the
/// proposal where it should clamp; `limits` swapping the minimum and maximum probes.
@Test @MainActor func skippingAFramesOwnProbesChangesNoPaneSizeOrPlace() throws {
    var windows = 0
    let count = paneSpecs.count
    // Every sixth ordered triple of the nine specs (122 of 729, each spec in each position many times over).
    for triple in stride(from: 0, to: count * count * count, by: 6) {
        let (first, second, third) = (triple / (count * count), triple / count % count, triple % count)
        for width in [Float(140), 400, 900] {
            for saved in [[Double]?.none, [80, 120, 100], [60, 70]] {
                guard width == 400 || saved == nil else { continue }
                var results: [[[Float]]] = []
                for wrapped in [false, true] {
                    let store = MemoryStore()
                    if let saved { store.saved["p"] = saved }
                    let w = try harnessWindow(size: sz(width, 300)) {
                        HSplitView {
                            pane(.red, paneSpecs[first], wrapped: wrapped)
                            pane(.green, paneSpecs[second], wrapped: wrapped)
                            pane(.blue, paneSpecs[third], wrapped: wrapped)
                        }
                        .splitViewAutosaveName("p", store: store)
                    }
                    results.append(placed(w))
                    windows += 1
                }
                #expect(results[0] == results[1],
                        "\(paneSpecs[first]) | \(paneSpecs[second]) | \(paneSpecs[third]) at \(width), saved \(String(describing: saved)): \(results[0]) vs \(results[1])")
            }
        }
    }
    #expect(windows > 500, "\(windows)")
}

/// **5 (G48)** A bare pane (no frame at all) keeps probing and keeps its size: a split of one framed pane and two bare ones, with
/// and without saved sizes, vertical as well. Mutation: `determinedExtent` answering for a leaf.
@Test @MainActor func panesWithoutFramesKeepProbingAndKeepTheirSizes() throws {
    for saved in [[Double]?.none, [100, 150, 140]] {
        let store = MemoryStore()
        if let saved { store.saved["b"] = saved }
        let w = try harnessWindow(size: sz(400, 300)) {
            HSplitView {
                Color.red.frame(minWidth: Pixels(50), idealWidth: Pixels(100), maxWidth: Pixels(200))
                Color.green
                Color.blue.padding(Pixels(0))
            }.splitViewAutosaveName("b", store: store)
        }
        let columns = placed(w).map { $0[1] }
        // 398 points for panes. Saved: 100, 150, 140 sum to 390, and the two panes without a maximum share the 8 left.
        #expect(columns == (saved == nil ? [100, 149, 149] : [100, 154, 144]), "\(String(describing: saved)): \(columns)")
    }
    let v = try harnessWindow(size: sz(400, 300)) {
        VSplitView {
            Color.red.frame(minHeight: Pixels(50), idealHeight: Pixels(100), maxHeight: Pixels(120))
            Color.green
        }
    }
    #expect(placedRows(v).map { $0[1] } == [100, 199], "\(placedRows(v))")
}
