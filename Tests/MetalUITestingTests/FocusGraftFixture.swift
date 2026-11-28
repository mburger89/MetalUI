import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing
#if canImport(Darwin)
import MetalUITestSupport
#endif

// The fixture of record 443 (`RK-AS`): Alloy's chat without its markdown. A transcript of equatable paragraph rows in a bottom-anchored
// `ScrollViewReader > ScrollView > LazyVStack`, over a composer (a `TextField` with a placeholder and a `@FocusState`), both under one column
// occurrence in a 420 x 600 window at scale 2. The scroller's indicator fade and glide taint the column's paint every step; the composer
// below it is the occurrence a focused graft has to stand for. Plain text rows and no path icons: nothing here refuses a move off Darwin.

/// The proxies of a pair's two sides, kept where the build reads them.
@MainActor final class FGBoxes {
    private var proxies: [ObjectIdentifier: ScrollViewProxy] = [:]
    func keep(_ proxy: ScrollViewProxy, for side: RPSide) -> Bool { proxies[ObjectIdentifier(side)] = proxy; return true }
    func proxy(for side: RPSide) -> ScrollViewProxy? { proxies[ObjectIdentifier(side)] }
}

let fgRowCount = 60

struct FGRow: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        Text("Row \(id) has some words in it, enough to wrap over a line or two in a narrow column of the chat.")
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    static func == (l: FGRow, r: FGRow) -> Bool { l.id == r.id }
}

/// Alloy's transcript: not equatable, so it builds whenever its parent does.
struct FGTranscript: Component {
    let side: RPSide
    let boxes: FGBoxes
    var content: some ElementGroup {
        let side = self.side, boxes = self.boxes
        ScrollViewReader { proxy in
            let _: Bool = boxes.keep(proxy, for: side)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Pixels(10)) {
                    ForEach(0..<fgRowCount, id: \.self) { FGRow(id: $0).equatable() }
                }.padding(g49Inset)
            }
            .defaultScrollAnchor(.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct FGComposer: Component, @MainActor Equatable {
    let side: RPSide
    @FocusState var focused: Bool
    var content: some ElementGroup {
        let side = self.side
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                TextField("Message", text: Binding(get: { side.inputs.text }, set: { side.inputs.text = $0 })).focused($focused)
                if side.inputs.text.isEmpty { Text("Ask anything").allowsHitTesting(false) }
            }
            Button("Done") { focused = false }
        }
        .padding(Edges(all: Pixels(8)))
    }
    static func == (l: FGComposer, r: FGComposer) -> Bool { l.side === r.side }
}

/// The occurrence the scroller taints every step: the transcript and the composer.
struct FGColumn: Component, @MainActor Equatable {
    let side: RPSide
    let boxes: FGBoxes
    /// A perpetual animation beside the composer (`T10`).
    var spinner = false
    var content: some ElementGroup {
        ZStack(alignment: .bottom) {
            FGTranscript(side: side, boxes: boxes)
            FGComposer(side: side).equatable()
            if spinner { ProgressView().frame(width: Pixels(20), height: Pixels(20)) }
        }
    }
    static func == (l: FGColumn, r: FGColumn) -> Bool { l.side === r.side && l.spinner == r.spinner }
}

struct FGChat: Component, @MainActor Equatable {
    let side: RPSide
    let boxes: FGBoxes
    var spinner = false
    var content: some ElementGroup { FGColumn(side: side, boxes: boxes, spinner: spinner).equatable() }
    static func == (l: FGChat, r: FGChat) -> Bool { l.side === r.side && l.spinner == r.spinner }
}

/// The pair's two sides' proxies live in `boxes`.
struct FGPair<Root: Element> {
    let pair: RPPair<Root>
    let boxes: FGBoxes
}

/// The pair, grafts on by default. `focused` clicks the composer's field and moves the pointer away.
@MainActor func fgPair(focused: Bool, graft: Bool = true, spinner: Bool = false) throws -> FGPair<some Element> {
    let boxes = FGBoxes()
    let pair = try RPPair(size: sz(420, 600), scale: 2, warm: 8, accessibility: false, graft: graft) { side in
        VStack(spacing: 0) { FGChat(side: side, boxes: boxes, spinner: spinner).equatable() }
    }
    if focused {
        for w in [pair.on, pair.off] { w.click(at: pt(60, 580)) }
        for w in [pair.on, pair.off] { w.exitPointer() }
    }
    for _ in 0..<3 { pair.redraw() }
    pair.frames = []; pair.work = FrameWork()
    return FGPair(pair: pair, boxes: boxes)
}

/// Starts a long animated `scrollTo` on both windows and lets its first frame (the one that resolves the request, which retains nothing) pass: from there every
/// frame is a glide frame, the scroller's `activeAnimation` taint on every enclosing occurrence (Alloy's scroll glide, `RK-AS`).
@MainActor func fgStartGlide(_ fg: FGPair<some Element>) {
    let pair = fg.pair
    for (w, side) in [(pair.on, pair.onSide), (pair.off, pair.offSide)] {
        withAnimation(.linear(duration: 40)) { fg.boxes.proxy(for: side)?.scrollTo(0, anchor: .top) }
        for _ in 0..<5 { w.advance(by: 1.0 / 60.0) }
    }
    pair.frames = []; pair.work = FrameWork()
}

/// One scroll step on both windows, the frames the retaining window drew in `pair.on.frameWork`. A glide step is one 1/60 s tick of the glide
/// `fgStartGlide` began; the other kind is a vertical wheel over the transcript's left inset.
@MainActor func fgStep(_ fg: FGPair<some Element>, _ step: Int, glide: Bool, retainingOnly: Bool = false) {
    let pair = fg.pair
    let windows = retainingOnly ? [pair.on] : [pair.on, pair.off]
    pair.on.resetFrameWork()
    if glide {
        for w in windows { w.advance(by: 1.0 / 60.0) }
    } else {
        let dy: Float = step.isMultiple(of: 2) ? 24 : -16
        for w in windows { w.scroll(at: pt(4, 300), byDeltaX: 0, deltaY: dy) }
    }
    pair.frames.append(pair.on.lastFrameWork); pair.work += pair.on.lastFrameWork
}

/// A focusable box with no state: its focus is moved by Tab or `focus(nil)` alone, which bumps no state version, so a graft's refusal for it is `focusMoved`.
struct FGPlainField: Component, @MainActor Equatable {
    let side: RPSide
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("plain").frame(width: Pixels(80), height: Pixels(14))
            Box().frame(width: Pixels(60), height: Pixels(20)).background(.accent).focusable()
        }
    }
    static func == (l: FGPlainField, r: FGPlainField) -> Bool { l.side === r.side }
}

@MainActor func fgPlainPair() throws -> RPPair<some Element> {
    let pair = try RPPair(size: sz(260, 140), accessibility: false) { side in
        VStack(spacing: 0) { FGPlainField(side: side).equatable() }
    }
    for _ in 0..<4 { pair.redraw() }
    pair.frames = []
    return pair
}

/// An occurrence that holds the composer: the composer's `@FocusState` is bound inside this graft window, so the graft's journal carries `.focusState`.
struct FGHost: Component, @MainActor Equatable {
    let side: RPSide
    var content: some ElementGroup { FGComposer(side: side) }
    static func == (l: FGHost, r: FGHost) -> Bool { l.side === r.side }
}

#if canImport(Darwin)
/// The least over three fresh fixtures of the least of eight steps' difference in allocations between the retaining window and the retention-off one, unfocused and steady,
/// graft on: the fixture's wheel and glide, and Alloy's transcript while it streams (`RK-AS`, `anUnfocusedChatsStepAllocatesNoMoreOverRetentionOffThanMasterDid`).
@MainActor func fgRetentionDeltas() async throws -> (wheel: Int, glide: Int, stream: Int) {
    func least(_ on: [Int], _ off: [Int]) -> Int { zip(on, off).map { $0 - $1 }.min() ?? 0 }
    var result = (wheel: Int.max, glide: Int.max, stream: Int.max)
    for _ in 0..<3 {
        for glide in [false, true] {
            let fg = try fgPair(focused: false)
            if glide { fgStartGlide(fg) }
            let pair = fg.pair
            func step(_ w: TestWindow, _ i: Int) {
                if glide { w.advance(by: 1.0 / 60.0) } else { w.scroll(at: pt(4, 300), byDeltaX: 0, deltaY: i.isMultiple(of: 2) ? 24 : -16) }
            }
            for i in 0..<6 { step(pair.on, i); step(pair.off, i) }
            var on: [Int] = [], off: [Int] = []
            for i in 6..<14 {
                on.append(try #require(countAllocations { step(pair.on, i) }))
                off.append(try #require(countAllocations { step(pair.off, i) }))
            }
            if glide { result.glide = min(result.glide, least(on, off)) } else { result.wheel = min(result.wheel, least(on, off)) }
        }
        let pair = try atPair(focused: false, graft: true)
        func tick(_ w: TestWindow, _ s: RPSide) async { s.inputs.offset += 1; await rsSettle(); w.window.setNeedsRedraw(); w.tick() }
        for _ in 0..<6 { await tick(pair.on, pair.onSide); await tick(pair.off, pair.offSide) }
        var on: [Int] = [], off: [Int] = []
        for _ in 6..<14 {
            pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
            await rsSettle()
            on.append(try #require(countAllocations { pair.on.window.setNeedsRedraw(); pair.on.tick() }))
            off.append(try #require(countAllocations { pair.off.window.setNeedsRedraw(); pair.off.tick() }))
        }
        result.stream = min(result.stream, least(on, off))
    }
    return result
}
#endif
