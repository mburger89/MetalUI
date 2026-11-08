import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// MetalCreator's `panningEvaluatesOnlyTheSurface` under `METALUI_VERIFY_RETAINED=1` trapped `unrecordedRead` on the
// `ScrollState` of a `ScrollView { List }` at index 4 of an `.equatable()` panel. Cause: an entry first met in the frame that
// also replays a sibling (the panel was shown in that frame) was compared with the PREVIOUS frame's reads, because an
// abandoned verify frame returns before the sweep that moves the journals (`Window.buildAndAdoptFrame`,
// `StateTable.takeUnsweptJournals`). These build the app's shape in a verify-mode child, which exits normally when no
// fresh read goes unrecorded.

@Observable @MainActor final class URPanelModel {
    var rows: [URRow] = (0..<60).map(URRow.init)
    var query = ""
    var sort = 0
}
struct URRow: Identifiable { let id: Int }
@Observable @MainActor final class URPan { var offset: Float = 0; var shown = false }

/// The canvas beside the panel: an equatable surface that reads the pan and moves its layers by an offset under a scale.
private struct URCanvas: Component, @MainActor Equatable {
    let pan: URPan
    static func == (l: URCanvas, r: URCanvas) -> Bool { l.pan === r.pan }
    var content: some ElementGroup {
        Color.clear
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) { Rectangle().fill(Color.blue).frame(width: Pixels(40), height: Pixels(40)) }
                    .scaleEffect(1, anchor: .topLeading)
                    .offset(x: Pixels(pan.offset), y: Pixels(0))
                    .allowsHitTesting(false)
            }
            .clipped()
            .gesture(DragGesture().onChanged { _ in })
            .contentShape(Rectangle())
            .onContinuousHover { _ in }
            .onScrollWheel { _ in false }
    }
}

private struct URRowView: Component {
    let item: URRow
    let hovers: Bool
    @State private var hovered = false
    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            HStack(spacing: Pixels(6)) {
                Text("Row \(item.id)")
                Spacer()
            }
            .padding(Edges(all: Pixels(2)))
            .frame(height: Pixels(20))
            .background(hovered ? Color.red : Color.clear, in: RoundedRectangle(cornerRadius: Pixels(4)))
            .gesture(DragGesture(minimumDistance: Pixels(0), coordinateSpace: .global).onChanged { _ in }.onEnded { _ in })
            .contentShape(Rectangle())
            .onHover { if hovers { hovered = $0 } }
            .help("Row \(item.id) help")
        }
    }
}

private struct URPanel: Component, @MainActor Equatable {
    let model: URPanelModel
    let withScrollView: Bool
    let hovers: Bool
    static func == (l: URPanel, r: URPanel) -> Bool { l.model === r.model && l.withScrollView == r.withScrollView && l.hovers == r.hovers }
    var content: some ElementGroup {
        let rows = model.rows.filter { model.query.isEmpty || "\($0.id)".contains(model.query) }
        return VStack(alignment: .leading, spacing: Pixels(4)) {
            Text("Nodes").frame(height: Pixels(14))
            HStack(spacing: Pixels(4)) {
                Button("Grouped") { model.sort = 0 }.help("grouped").disabled(model.sort == 0)
                Button("A-Z") { model.sort = 1 }.disabled(model.sort == 1)
                Spacer(minLength: Pixels(0))
            }.frame(height: Pixels(20))
            TextField("Search", text: model.query, onChange: { model.query = $0 }).frame(height: Pixels(20))
            if rows.isEmpty { Text("none") }
            if withScrollView {
                ScrollView {
                    List(rows, rowHeight: Pixels(20)) { row in
                        ZStack(alignment: .topLeading) { URRowView(item: row, hovers: hovers) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(rows, rowHeight: Pixels(20)) { row in
                    ZStack(alignment: .topLeading) { URRowView(item: row, hovers: hovers) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(Edges(all: Pixels(6)))
        .background(Color.gray, in: RoundedRectangle(cornerRadius: Pixels(6)))
    }
}

private struct URRoot: Component {
    let pan: URPan
    let model: URPanelModel
    let withScrollView: Bool
    let hovers: Bool
    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ZStack { URCanvas(pan: pan).equatable() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Edges(top: Pixels(0), right: Pixels(0), bottom: Pixels(0), left: Pixels(204)))
            if pan.shown {
                URPanel(model: model, withScrollView: withScrollView, hovers: hovers).equatable()
                    .frame(width: Pixels(200)).frame(maxHeight: .infinity)
            }
        }
    }
}

/// One arm per child process. `late` shows the panel after the window has settled (the frame it first appears in also
/// replays the canvas: the trap), `early` has it from the first frame, `hover` and `scrolled` act on the panel first.
/// Mutations: `replayedReads` back to `Set(stateTable.lastReadJournal).union(stateTable.lastMarkJournal)` (`unrecordedRead`),
/// and the `discardEntries` rollback removed (`a replayed prepaint differs`: the first build's unbounded list window, 68 rects
/// against 22), each redden `late`, `hover` and `scrolled`; `early`, which has no first sighting beside a replay, is the control.
@Test(.serialized, arguments: ["late", "early", "hover", "scrolled"]) @MainActor
func aPanelFirstShownBesideAReplayedSiblingVerifies(arm: String) async {
    setTestEnvironment("UR_ARM", arm)
    await #expect(processExitsWith: .success) {
        setTestEnvironment("METALUI_VERIFY_RETAINED", "1")
        await MainActor.run {
            let arm = ProcessInfo.processInfo.environment["UR_ARM"] ?? "late"
            let pan = URPan(), model = URPanelModel()
            if arm == "early" { pan.shown = true }
            guard let window = try? TestWindow(size: sz(300, 300), textSystem: harnessTextSystem, content: {
                VStack(spacing: 0) { URRoot(pan: pan, model: model, withScrollView: true, hovers: arm == "hover") }
            }) else { exit(2) }
            for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
            pan.shown = true
            for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
            if arm == "scrolled" {
                window.scroll(at: pt(100, 150), byDeltaX: 0, deltaY: -60)
                for _ in 0..<2 { window.tick() }
                window.advance(by: 2)
            }
            if arm == "hover" { window.hover(at: pt(100, 150)); window.tick(); window.hover(at: pt(280, 280)); window.tick() }
            var replayed = 0
            for i in 1...8 {
                pan.offset = Float(i) * 3; window.window.setNeedsRedraw(); window.tick()
                let w = window.lastFrameWork
                replayed += w.retainedHits + w.retainedPrepaintHits + w.retainedGrafts
            }
            // The child proves something only when something replayed (the panel's own replay needs it settled and unscrolled).
            if replayed == 0, arm == "late" || arm == "early" { exit(3) }
        }
    }
}
