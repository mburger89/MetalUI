import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

/// Alloy's composer shape over the record 443 fixture: a vertical-axis `TextField` with a binding to its selection, a prompt, `lineLimit`, `onChange` of its
/// `@FocusState`, `onKeyPress`, a framed and padded box with a background and an overlay stroke, in a `VStack` under a background modifier, beside the transcript in a `ZStack`.
@Observable @MainActor final class FCModel {
    var draft = ""
    var caret: Range<Int>?
}

struct FCComposer: Component, @MainActor Equatable {
    let side: RPSide
    let model: FCModel
    @FocusState var focused: Bool
    var content: some ElementGroup {
        let model = model
        let draft = Binding<String>(get: { model.draft }, set: { model.draft = $0 })
        let caret = Binding<Range<Int>?>(get: { model.caret }, set: { if model.caret != $0 { model.caret = $0 } })
        let open = Binding<Bool>(get: { false }, set: { _ in })
        let mode = Binding<Int>(get: { 0 }, set: { _ in })
        VStack(alignment: .leading, spacing: Pixels(6)) {
            HStack(spacing: Pixels(8)) {
                Picker("Mode", selection: mode) { ForEach(0..<3, id: \.self) { Text("m\($0)").tag($0) } }
                    .accessibilityIdentifier("mode-picker")
                Menu("Model") { Button("Sonnet") {} }
                    .accessibilityIdentifier("model-menu")
                Text("2 queued")
            }
            HStack(alignment: .bottom, spacing: Pixels(8)) {
                TextField("Message", text: draft, selectedOffsets: caret, prompt: Text("Message"), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .accessibilityIdentifier("composer")
                    .focused($focused)
                    .onChange(of: focused) { _, _ in }
                    .onKeyPress(phases: [.down, .repeat]) { _ in .ignored }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(Edges(all: Pixels(6)))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("composer-box")
                    .suggestionOverlay(isPresented: open, edge: .top, alignment: .leading) { Text("suggestion") }
                    .background(alignment: .center) { RoundedRectangle(cornerRadius: 8).fill(Color.gray) }
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(focused ? Color.blue : Color.gray) }
                Button {} label: {
                    Image(systemName: "arrow.up.circle.fill").resizable().frame(width: Pixels(28), height: Pixels(28))
                }
                .buttonStyle(.plain).help("Send").accessibilityLabel("Send").keyboardShortcut(.return)
            }
        }
        .dropDestination(for: String.self) { _, _ in true }
        .padding(Edges(all: Pixels(10)))
    }
    static func == (l: FCComposer, r: FCComposer) -> Bool { l.side === r.side }
}

struct FCColumn: Component, @MainActor Equatable {
    let side: RPSide
    let boxes: FGBoxes
    let model: FCModel
    @State var barHeight: Double = 0
    var content: some ElementGroup {
        let height = $barHeight
        ZStack(alignment: .bottom) {
            FGTranscript(side: side, boxes: boxes)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    FCComposer(side: side, model: model).equatable()
                }
                .background { Rectangle().fill(Color.gray) }
            }
            .padding(Edges(all: Pixels(8)))
            .onGeometryChange(for: Double.self, of: { Double($0.size.height.value) }) { new in
                if height.wrappedValue != new { height.wrappedValue = new }
            }
        }
    }
    static func == (l: FCColumn, r: FCColumn) -> Bool { l.side === r.side }
}

@MainActor final class FCModels {
    private var models: [ObjectIdentifier: FCModel] = [:]
    func model(for side: RPSide) -> FCModel {
        if let m = models[ObjectIdentifier(side)] { return m }
        let m = FCModel(); models[ObjectIdentifier(side)] = m; return m
    }
}

@MainActor func fcPair(focused: Bool) throws -> (fg: FGPair<some Element>, models: FCModels) {
    let boxes = FGBoxes(), models = FCModels()
    let pair = try RPPair(size: sz(420, 600), scale: 2, warm: 8, accessibility: false, graft: true) { side in
        VStack(spacing: 0) { FCColumn(side: side, boxes: boxes, model: models.model(for: side)).equatable() }
    }
    if focused {
        for w in [pair.on, pair.off] { w.click(at: pt(60, 570)) }
        for w in [pair.on, pair.off] { w.exitPointer() }
    }
    for _ in 0..<3 { pair.redraw() }
    pair.frames = []; pair.work = FrameWork()
    return (FGPair(pair: pair, boxes: boxes), models)
}

private func sum(_ frames: [FrameWork], _ key: KeyPath<FrameWork, Int>) -> Int { frames.reduce(0) { $0 + $1[keyPath: key] } }

/// What one step cost and what it named: the counters a focused window must share with an unfocused one, and the trace's `versions` refusals.
private struct FCStep: Equatable, CustomStringConvertible {
    var requests: Int, skipped: Int, grafts: Int, misses: Int, versions: Int
    var description: String { "requests \(requests) skipped \(skipped) grafts \(grafts) misses \(misses) versions \(versions)" }
}

@MainActor private func step(_ fg: FGPair<some Element>, _ i: Int, glide: Bool) -> FCStep {
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    fgStep(fg, i, glide: glide)
    RetainedTrace.sink = nil
    let frames = fg.pair.on.frameWork
    return FCStep(requests: sum(frames, \.elementRequests), skipped: sum(frames, \.retainedSkippedRequests), grafts: sum(frames, \.retainedGrafts),
                  misses: sum(frames, \.retainedMisses), versions: lines.filter { $0.contains("miss") && $0.contains("versions") }.count)
}

private let verifyNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read; the differential runs under it"

/// **1** Record 445 (`RK-AT`): Alloy's focused composer (a vertical `TextField` bound to its selection) under a wheel over the transcript. Every input event ran
/// `publishFocusedSelection`, whose read of the field's edit state was a `withState` that stored it back: a new version of an entry the composer's records had
/// read, so the composer refused by `versions` on every step. A focused window now costs what an unfocused one costs, step by step. **Mutation:** `editState` back
/// to a `withState` read.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aFocusedBoundFieldCostsWhatAnUnfocusedOneCostsUnderAWheel() throws {
    let glide = false
    let (focused, _) = try fcPair(focused: true), (plain, _) = try fcPair(focused: false)
    #expect(focused.pair.on.window.focusedElement != nil)
    for i in 0..<12 {
        let a = step(focused, i, glide: glide), b = step(plain, i, glide: glide)
        #expect(a == b, "step \(i): focused \(a) against unfocused \(b)")
    }
    try focused.pair.compare("wheeled")
}

/// **2** An input event over a focused bound field gives its edit state no new version: the pointer moving, a wheel and an idle frame after them leave the version where
/// it was, and the idle frames cost the elements an unfocused window's cost. **Mutation:** as 1.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func anInputEventOverAFocusedBoundFieldGivesItsEditStateNoNewVersion() throws {
    let (focused, _) = try fcPair(focused: true), (plain, _) = try fcPair(focused: false)
    let (f, p) = (focused.pair.on, plain.pair.on)
    let id = try #require(f.window.focusedElement)
    let before = f.window.testingStateVersion(id)
    #expect(before != 0)
    for w in [f, p] { w.hover(at: pt(300, 200)); w.hover(at: pt(10, 20)); w.scroll(at: pt(4, 300), byDeltaX: 0, deltaY: 8); w.hover(at: pt(300, 500)) }
    #expect(f.window.testingStateVersion(id) == before, "the edit state was rewritten by input: \(before) to \(f.window.testingStateVersion(id))")
    for w in [f, p] { w.advance(by: 0.5); w.advance(by: 2) }   // the indicator's fade ends
    for _ in 0..<6 { focused.pair.redraw(); plain.pair.redraw() }   // the lag of a focused graft after input (record 443)
    for w in [f, p] { w.resetFrameWork() }
    for _ in 0..<3 { focused.pair.redraw(); plain.pair.redraw() }
    #expect(sum(f.frameWork, \.elementRequests) == sum(p.frameWork, \.elementRequests), "idle frames \(f.frameWork.map(\.elementRequests)) \(p.frameWork.map(\.elementRequests))")
    #expect(f.window.testingStateVersion(id) == before, "an idle frame rewrote the edit state")
}

/// **3** The field still repaints and publishes what really changed: typing, a backspace after a scroll reach the model and the window equals
/// the retention-off one at every step. **Mutation:** `publishFocusedSelection` removed (the caret stays nil).
@Test @MainActor func theFocusedBoundFieldStillRepaintsWhenItsEditStateChanges() throws {
    let (fg, models) = try fcPair(focused: true)
    let pair = fg.pair
    for i in 0..<3 { fgStep(fg, i, glide: false) }
    for w in [pair.on, pair.off] { w.typeText("ab") }
    pair.redraw()
    #expect(models.model(for: pair.onSide).draft == "ab" && models.model(for: pair.offSide).draft == "ab")
    #expect(models.model(for: pair.onSide).caret == 2..<2, "caret \(String(describing: models.model(for: pair.onSide).caret))")
    try pair.compare("typed")
    for i in 3..<8 { fgStep(fg, i, glide: false) }
    for w in [pair.on, pair.off] { w.typeText("c") }
    pair.redraw()
    #expect(models.model(for: pair.onSide).draft == "abc" && models.model(for: pair.onSide).caret == 3..<3, "draft \(models.model(for: pair.onSide).draft) caret \(String(describing: models.model(for: pair.onSide).caret))")
    for w in [pair.on, pair.off] { w.typeKey(.delete) }
    pair.redraw()
    #expect(models.model(for: pair.onSide).draft == "ab" && models.model(for: pair.onSide).caret == 2..<2, "draft \(models.model(for: pair.onSide).draft) caret \(String(describing: models.model(for: pair.onSide).caret))")
    try pair.compare("typed after scroll")
}
