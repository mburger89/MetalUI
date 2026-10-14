import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Observation
import Testing

// C14b-2 lane 1 (`RK-`, record 110): prepaint replay and the redo, on the bracket window and on small
// windows built to move one thing. Counts, never time. Every differential draws two windows from one
// builder, one retaining (prepaint replay on) and one with `testingRetainedSubtrees = false`, and compares
// what the frame hands the platform.

// MARK: Step 0 — the node drag at fb9a7e42, counted

/// One arm's per-frame work at the node drag's tenth frame with paint-only replay (`fb9a7e42`): taken by this
/// test's first run on that commit's tree (record 110 §1) and held by it ever since through
/// `testingRetainedPrepaint = false`, which is that tree's behaviour. Literals, never prints (`SB-Q`).
private struct Fb9a7e42Frame {
    let arm: BracketArm
    let requests: Int, prepaints: Int, paints: Int
    let hits: Int, misses: Int, ineligible: Int, skippedPaints: Int
    let evaluations: Int, skips: Int, refusals: Int
    let measures: Int, cacheHits: Int, cacheMisses: Int, memoHits: Int, memoMisses: Int, subtreeHits: Int
}
private let fb9a7e42Frames = [
    Fb9a7e42Frame(arm: .value, requests: 798, prepaints: 886, paints: 252, hits: 29, misses: 3, ineligible: 0,
                  skippedPaints: 832, evaluations: 3, skips: 29, refusals: 0, measures: 52, cacheHits: 331,
                  cacheMisses: 217, memoHits: 362, memoMisses: 55, subtreeHits: 11),
    Fb9a7e42Frame(arm: .environment, requests: 798, prepaints: 886, paints: 1008, hits: 19, misses: 2, ineligible: 0,
                  skippedPaints: 76, evaluations: 2, skips: 19, refusals: 11, measures: 52, cacheHits: 366,
                  cacheMisses: 217, memoHits: 1258, memoMisses: 55, subtreeHits: 0),
    Fb9a7e42Frame(arm: .panels, requests: 798, prepaints: 886, paints: 184, hits: 31, misses: 3, ineligible: 1,
                  skippedPaints: 900, evaluations: 3, skips: 32, refusals: 0, measures: 52, cacheHits: 331,
                  cacheMisses: 217, memoHits: 362, memoMisses: 55, subtreeHits: 11),
]

@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read"), arguments: [BracketArm.value, BracketArm.environment, BracketArm.panels]) @MainActor
func theBracketNodeDragIsCountedAtFb9a7e42(arm: BracketArm) throws {
    let expected = try #require(fb9a7e42Frames.first { $0.arm == arm })
    let r = try bracketDragFrames(arm: arm, steps: 20, retained: true, prepaint: false)
    let f = r.frames[10]
    #expect(f.builds == 1)
    #expect(f.elementRequests == expected.requests)
    #expect(f.elementPrepaints == expected.prepaints)
    #expect(f.elementPaints == expected.paints)
    #expect(f.retainedHits == expected.hits)
    #expect(f.retainedMisses == expected.misses)
    #expect(f.retainedIneligible == expected.ineligible)
    #expect(f.retainedSkippedPrepaints == 0)
    #expect(f.retainedSkippedPaints == expected.skippedPaints)
    #expect(f.contentEvaluations == expected.evaluations)
    #expect(f.contentSkips == expected.skips)
    #expect(f.contentRefusals == expected.refusals)
    #expect(f.layoutMeasureCalls == expected.measures)
    #expect(f.layoutCacheHits == expected.cacheHits)
    #expect(f.layoutCacheMisses == expected.cacheMisses)
    #expect(f.layoutMemoHits == expected.memoHits)
    #expect(f.layoutMemoMisses == expected.memoMisses)
    #expect(f.layoutSubtreeHits == expected.subtreeHits)
    #expect(f.rects == 182 && f.glyphs == 550 && f.images == 6)
    #expect(f.rasterizedPixels == 78312 && f.newTextures == 2 && f.atlasUploadPixels == 0)
    #expect(f.retainedPrepaintHits == 0 && f.retainedPrepaintIneligible == 0 && f.retainedRedos == 0)
}

/// The same arm and frame after M1 (prepaint replay on): taken by this test's first run on the lane-1 tree (record 110 §2) and
/// pinned as literals, **red on arrival** against `fb9a7e42` (where `elementPrepaints` reads 886 in every arm and nothing is
/// skipped). The conservation law holds: what ran plus what the replays stood for is `fb9a7e42`'s count.
private struct AfterPrepaintFrame {
    let arm: BracketArm
    let prepaints: Int, skippedPrepaints: Int, prepaintHits: Int, prepaintIneligible: Int
}
private let afterPrepaintFrames = [
    AfterPrepaintFrame(arm: .value, prepaints: 219, skippedPrepaints: 667, prepaintHits: 29, prepaintIneligible: 0),
    AfterPrepaintFrame(arm: .environment, prepaints: 829, skippedPrepaints: 57, prepaintHits: 19, prepaintIneligible: 0),
    AfterPrepaintFrame(arm: .panels, prepaints: 176, skippedPrepaints: 710, prepaintHits: 30, prepaintIneligible: 1),
]

/// 1b — the node drag's tenth frame with prepaint replay: the build and layout work is `fb9a7e42`'s to the unit (798 requests, the
/// same layout counts, the same scene), and element prepaints fall by what the hits stand for (886 to 219 in the value arm, 176 in
/// panels; the environment arm's refused nodes still prepaint). Mutation: any switch that turns replay off reads 886.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read"), arguments: [BracketArm.value, BracketArm.environment, BracketArm.panels]) @MainActor
func theBracketNodeDragIsCountedAfterPrepaintReplay(arm: BracketArm) throws {
    let before = try #require(fb9a7e42Frames.first { $0.arm == arm })
    let after = try #require(afterPrepaintFrames.first { $0.arm == arm })
    let f = try bracketDragFrames(arm: arm, steps: 20, retained: true, prepaint: true).frames[10]
    #expect(f.elementPrepaints == after.prepaints)
    #expect(f.retainedSkippedPrepaints == after.skippedPrepaints)
    #expect(f.elementPrepaints + f.retainedSkippedPrepaints == before.prepaints, "conservation against fb9a7e42")
    #expect(f.retainedPrepaintHits == after.prepaintHits)
    #expect(f.retainedPrepaintIneligible == after.prepaintIneligible)
    #expect(f.retainedRedos == 0 && f.retainedBackoffFrames == 0 && f.retainedTranslated == 0 && f.retainedTranslationRefused == 0)
    // What replay must not move: the build, layout and the scene (the fourteen-image rule's counted twin).
    #expect(f.elementRequests == before.requests)
    #expect(f.elementPaints == before.paints && f.retainedSkippedPaints == before.skippedPaints)
    #expect(f.retainedHits == before.hits && f.retainedMisses == before.misses && f.retainedIneligible == before.ineligible)
    #expect(f.layoutMeasureCalls == before.measures && f.layoutCacheHits == before.cacheHits)
    #expect(f.layoutCacheMisses == before.cacheMisses && f.layoutMemoHits == before.memoHits && f.layoutMemoMisses == before.memoMisses)
    #expect(f.rects == 182 && f.glyphs == 550 && f.images == 6 && f.rasterizedPixels == 78312 && f.newTextures == 2)
}

// MARK: The snapshot and the pair

/// What a frame hands the platform and the input side, compared whole (`RK-E`): the scene's arrays byte for byte,
/// the accessibility tree, every non-closure field of every hitbox in order, the tallies, the Tab order, the
/// element bounds and the context-menu and press-only registrations.
@MainActor struct RPSnapshot {
    let rects: Data, glyphs: Data, images: Data
    let counts: [Int]
    let tree: AccessibilityTree?
    let hitboxes: [String]
    let tallies: [Int]
    let tabOrder: [GlobalElementID]
    let bounds: [GlobalElementID: Bounds<Pixels>]
    let registrations: [String]

    /// `accessibility: false` never activates an accessibility client, so no ledger holds accessibility records.
    init(_ window: TestWindow, accessibility: Bool = true) throws {
        func bytes<T>(_ array: [T]) -> Data { array.withUnsafeBytes { Data($0) } }
        rects = bytes(window.scene.rects); glyphs = bytes(window.scene.glyphs); images = bytes(window.scene.images)
        counts = [window.scene.rects.count, window.scene.glyphs.count, window.scene.images.count]
        tree = accessibility ? try window.accessibilityTree : nil
        hitboxes = window.window.testingHitboxFingerprints
        tallies = window.window.testingRegionTallies
        tabOrder = window.window.testingTabOrder
        bounds = window.window.testingElementBounds
        registrations = window.window.testingContextMenuAndPressOnlyIDs
    }

    func differences(from other: RPSnapshot) -> [String] {
        var out: [String] = []
        if rects != other.rects { out.append("rects") }
        if glyphs != other.glyphs { out.append("glyphs") }
        if images != other.images { out.append("images") }
        if counts != other.counts { out.append("counts \(counts) vs \(other.counts)") }
        if tree != other.tree { out.append("accessibility tree") }
        if hitboxes != other.hitboxes {
            let first = zip(hitboxes, other.hitboxes).enumerated().first { $0.element.0 != $0.element.1 }
            out.append("hitboxes (\(hitboxes.count) vs \(other.hitboxes.count)) first difference \(String(describing: first))")
        }
        if tallies != other.tallies { out.append("tallies \(tallies) vs \(other.tallies)") }
        if tabOrder != other.tabOrder { out.append("tab order") }
        if bounds != other.bounds { out.append("element bounds") }
        if registrations != other.registrations { out.append("registrations \(registrations) vs \(other.registrations)") }
        return out
    }
}

/// The window inputs a test moves from outside the tree.
@Observable @MainActor final class RPInputs {
    var offset: Float = 0
    var showExtra = false
    var text = ""
}

/// One side of a pair: its own model, log and inputs.
@MainActor final class RPSide {
    let model = RSModel()
    let log = HarnessLog()
    let inputs = RPInputs()
}

/// A card: text, a button (a hitbox, a focus stop, an accessibility record, a tally) with a context menu, and a bar.
/// `==` on its inputs.
struct RPCard: Component, @MainActor Equatable {
    let title: String
    let shade: Int
    let log: HarnessLog
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text(title).frame(width: Pixels(80), height: Pixels(14))
            Button("go \(title)") { log.add("go \(title)") }.frame(width: Pixels(50), height: Pixels(18))
                .contextMenu { Button("menu \(title)") { log.add("menu \(title)") } }
            Box().frame(width: Pixels(Float(20 + shade * 4)), height: Pixels(8)).background(.accent)
        }
        .padding(Edges(all: Pixels(4)))
        .background(Color.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: Pixels(6)))
        .clipShape(RoundedRectangle(cornerRadius: Pixels(6)))
    }
    static func == (l: RPCard, r: RPCard) -> Bool { l.title == r.title && l.shade == r.shade && l.log === r.log }
}

/// Two windows over one builder: `on` retains with prepaint replay, `off` retains nothing.
@MainActor final class RPPair<Root: Element> {
    let on: TestWindow, off: TestWindow
    let onSide = RPSide(), offSide = RPSide()
    /// Whether `compare` reads the accessibility tree (which activates a client for the rest of the run).
    var accessibility = true
    var work = FrameWork()
    var frames: [FrameWork] = []

    /// `accessibility: false` opens both windows with no accessibility client, as an app nobody is inspecting runs
    /// (the harness default is a client active from the first handler): no frame collects accessibility records.
    init(size: Size<Pixels> = sz(420, 200), scale: Float = 1, colorScheme: ColorScheme = .light, warm: Int = 3,
         accessibility: Bool = true, _ root: @escaping @MainActor (RPSide) -> Root) throws {
        let onSide = self.onSide, offSide = self.offSide
        let options = HeadlessPlatformWindow.Options(appearance: colorScheme, scaleFactor: scale,
                                                     accessibilityClientActive: accessibility)
        on = try TestWindow(size: size, colorScheme: colorScheme, scaleFactor: scale, options: options,
                            textSystem: harnessTextSystem) { root(onSide) }
        off = try TestWindow(size: size, colorScheme: colorScheme, scaleFactor: scale, options: options,
                             textSystem: harnessTextSystem) { root(offSide) }
        self.accessibility = accessibility
        off.window.testingRetainedSubtrees = false
        for _ in 0..<warm { redraw() }
        frames = []
        work = FrameWork()
    }

    func redraw() {
        for w in [on, off] { w.window.setNeedsRedraw(); w.tick() }
        frames.append(on.lastFrameWork)
        work = work + on.lastFrameWork
    }

    func compare(_ step: String) throws {
        let differences = try RPSnapshot(on, accessibility: accessibility).differences(from: RPSnapshot(off, accessibility: accessibility))
        #expect(differences.isEmpty, "after \(step): \(differences)")
        #expect(onSide.log.entries == offSide.log.entries, "log after \(step): \(onSide.log.entries) vs \(offSide.log.entries)")
        #expect(off.lastFrameWork.retainedHits == 0 && off.lastFrameWork.retainedPrepaintHits == 0)
    }
}

// MARK: 2 — a prepaint-replayed frame equals a fresh frame at every drag step

/// 2 — on the bracket window (value and panels arms) a node drag is run in short drags on a retaining window and
/// a retention-off window; after every drag the scene, accessibility tree, whole hitbox list, tallies, Tab order
/// and element bounds are equal, and the retaining side replayed prepaint (a differential that replays nothing
/// proves nothing). Mutations: hitboxes replayed in reverse (the list differs), one tally dropped, the focus
/// stops skipped (the panels arm's Tab order), the accessibility records skipped (the tree).
@Test(arguments: [BracketArm.value, BracketArm.panels]) @MainActor
func aPrepaintReplayedFrameEqualsAFreshFrameAtEveryDragStep(arm: BracketArm) throws {
    let (on, _) = try bracketWindow(arm: arm, textSystem: harnessTextSystem)
    let (off, _) = try bracketWindow(arm: arm, textSystem: harnessTextSystem)
    off.window.testingRetainedSubtrees = false
    for w in [on, off] { for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() } }
    for difference in try RPSnapshot(on).differences(from: RPSnapshot(off)) { Issue.record("before the drag: \(difference)") }
    on.resetFrameWork(); off.resetFrameWork()
    var prepaintHits = 0, skipped = 0, redos = 0
    for step in 0..<10 {
        let end = Point(x: Pixels(20 + (step.isMultiple(of: 2) ? 6 : -6)), y: Pixels(400))
        for w in [on, off] { w.drag(from: bracketFilletPress, to: end, steps: 3) }
        let differences = try RPSnapshot(on).differences(from: RPSnapshot(off))
        #expect(differences.isEmpty, "after drag \(step): \(differences)")
        for f in on.frameWork {
            prepaintHits += f.retainedPrepaintHits; skipped += f.retainedSkippedPrepaints; redos += f.retainedRedos
        }
        on.resetFrameWork(); off.resetFrameWork()
    }
    #expect(prepaintHits > 0, "the retaining side replayed no prepaint: the differential proves nothing")
    #expect(skipped > 0)
    #expect(redos == 0, "a node drag changes no paint-only ambient: \(redos)")
}

// MARK: 3 — the ranking

private struct RPOverlap: Component {
    let log: HarnessLog
    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ZStack { RPCard(title: "A", shade: 0, log: log).equatable() }
            ZStack { RPCard(title: "B", shade: 1, log: log).equatable() }.offset(x: Pixels(30), y: Pixels(10))
            ZStack { RPCard(title: "C", shade: 2, log: log).equatable() }.offset(x: Pixels(60), y: Pixels(20))
        }
    }
}

/// 3 — three overlapping occurrences: the one ranking answers the same at every point of a grid whether their
/// hitboxes were replayed or registered (`RK-E`: the same entries in the same order; no second lookup). The grid is
/// clicked on both windows, and the logs, hitbox lists and scenes agree. Mutation: replayed hitboxes appended after
/// later siblings' (the topmost card changes at the overlaps).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read")) @MainActor func aReplayedHitboxIsRankedLikeAFreshOne() throws {
    let pair = try RPPair(size: sz(260, 140)) { side in VStack(spacing: 0) { RPOverlap(log: side.log) } }
    try pair.compare("warm")
    pair.redraw()
    #expect(pair.frames.last?.retainedPrepaintHits == 3, "all three replay prepaint: \(String(describing: pair.frames.last))")
    for y in stride(from: Float(6), to: 130, by: 17) {
        for x in stride(from: Float(6), to: 250, by: 19) {
            for w in [pair.on, pair.off] { w.click(at: pt(x, y)) }
            try pair.compare("click at \(x),\(y)")
        }
    }
    #expect(!pair.onSide.log.entries.isEmpty, "the grid reached at least one button")
}

// MARK: 4 — a paint-only ambient changes under a replayed prepaint

enum RPAmbient: String, CaseIterable { case opacity, shadow, blur, compositingGroup }

@MainActor private func rpAmbientRoot(_ arm: RPAmbient, _ side: RPSide) -> some Element {
    let on = side.model.n % 2 == 1
    let log = side.log
    return VStack(spacing: 4) {
        switch arm {
        case .opacity:
            ZStack { RPCard(title: "A", shade: 1, log: log).equatable() }.opacity(on ? 0.5 : 1)
        case .shadow:
            ZStack { RPCard(title: "A", shade: 1, log: log).equatable() }.shadow(radius: Pixels(on ? 6 : 2))
        case .blur:
            ZStack { RPCard(title: "A", shade: 1, log: log).equatable() }.blur(radius: Pixels(on ? 2 : 0.5))
        case .compositingGroup:
            ZStack { RPCard(title: "A", shade: 1, log: log).equatable() }.compositingGroup()
                .shadow(radius: Pixels(on ? 6 : 2))
        }
        RPCard(title: "B", shade: 2, log: log).equatable()
    }
}

/// 4 — an ancestor's paint-only value (an opacity, a shadow, a blur, a composited shadow) changes under a subtree
/// that did not: the replayed prepaint cannot paint (`RK-C`), so the frame is redone once, with every prepaint
/// replay off, and equals the retention-off frame. The neighbour (B) replays before and after. Mutations: the redo
/// disabled (the subtree is painted from a record under the new ambient: the scene differs); the arm's ambient
/// dropped from `AmbientKey` (the paint hit is taken: the scene differs).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read"), arguments: RPAmbient.allCases) @MainActor
func aChangedPaintOnlyAmbientRedoesTheFrameOnce(arm: RPAmbient) async throws {
    let pair = try RPPair(size: sz(200, 160), warm: 4) { rpAmbientRoot(arm, $0) }
    try pair.compare("warm")
    pair.redraw()
    try #require(pair.frames.last?.retainedPrepaintHits == 2, "both replay before the change: \(String(describing: pair.frames.last))")
    pair.onSide.model.n += 1; pair.offSide.model.n += 1
    await rsSettle()
    pair.redraw()
    let f = try #require(pair.frames.last)
    #expect(f.retainedRedos == 1, "the change redoes the frame once: \(f.retainedRedos)")
    #expect(f.retainedPrepaintHits == 0, "the redo replays no prepaint: \(f.retainedPrepaintHits)")
    try pair.compare("the changed ambient")
    // Eight builds with prepaint replay suspended, then both replay again.
    for index in 1...8 {
        pair.redraw()
        let g = try #require(pair.frames.last)
        #expect(g.retainedPrepaintHits == 0 && g.retainedRedos == 0, "backoff build \(index): \(g.retainedPrepaintHits)/\(g.retainedRedos)")
        #expect(g.retainedBackoffFrames == 1, "backoff build \(index) is counted: \(g.retainedBackoffFrames)")
        try pair.compare("backoff build \(index)")
    }
    pair.redraw(); pair.redraw()
    #expect(pair.frames.last?.retainedPrepaintHits == 2, "replay resumes: \(String(describing: pair.frames.last))")
    try pair.compare("after the backoff")
}

// MARK: 5 — the redo consumes each window input once

struct RPInputsRoot: Component {
    let side: RPSide
    @FocusState var focused: Bool
    var content: some ElementGroup {
        let inputs = side.inputs, model = side.model, log = side.log
        let textBinding = Binding<String>(get: { inputs.text }, set: { inputs.text = $0 })
        ScrollViewReader { proxy in
            VStack(spacing: 4) {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(Array(0..<30), id: \.self) { i in
                            Text("row \(i)").frame(width: Pixels(80), height: Pixels(14)).id("row \(i)")
                        }
                    }
                }.frame(width: Pixels(120), height: Pixels(60))
                // The card replays while an implicit animation below is in flight, and its ancestor's opacity
                // changes in the input that also writes a focus request and shows an element with `onAppear`.
                ZStack { RPCard(title: "A", shade: 1, log: log).equatable() }
                    .opacity(model.n % 2 == 1 ? 0.5 : 1)
                Text("glide").frame(width: Pixels(40), height: Pixels(14)).offset(x: Pixels(inputs.offset))
                    .animation(.linear(duration: 0.4), value: inputs.offset)
                Button("slide") { inputs.offset = 30 }.frame(width: Pixels(40), height: Pixels(16))
                Button("jump") {
                    focused = true
                    model.n += 1
                    inputs.showExtra = true
                }.frame(width: Pixels(40), height: Pixels(16))
                Button("scroll") { proxy.scrollTo("row 22") }.frame(width: Pixels(40), height: Pixels(16))
                TextField("field", text: textBinding).focused($focused)
                    .frame(width: Pixels(100), height: Pixels(22))
                ZStack {
                    if inputs.showExtra { Text("extra").onAppear { log.add("appear") } }
                }.frame(width: Pixels(40), height: Pixels(14))
            }
        }
    }
}

/// 5 — a redone frame equals a retention-off frame and consumes each window input exactly once (`RK-D`, `RK-M`): one
/// click holds a focus request and a lifecycle appear while the opacity above a replayed subtree changes and an
/// implicit animation (the animation store's entries) is in flight below. The two windows agree after the input,
/// through the rest of the animation and in the log of lifecycle events; a `scrollTo` clicked after it moves the
/// rows once. A frame whose root transaction is animating refuses every replay (`SB-J`), so a redo never coincides
/// with a parked `withAnimation`; the transaction value is still passed to the redo unchanged. Mutations: the
/// animation store's entries not restored (the animation restarts: the offset differs mid-animation), the
/// lifecycle store not rolled back (a second `appear`), the abandoned frame adopted (hitboxes, Tab order or log).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read")) @MainActor func aRedoFrameEqualsARetentionOffFrameAndConsumesEachInputOnce() async throws {
    let pair = try RPPair(size: sz(260, 260), warm: 4) { side in VStack(spacing: 0) { RPInputsRoot(side: side) } }
    try pair.compare("warm")
    pair.redraw()
    try #require(pair.frames.last?.retainedPrepaintHits == 1, "the card replays before the input: \(String(describing: pair.frames.last))")
    for w in [pair.on, pair.off] { try w.click(w.element(label: "slide")) }
    for index in 0..<2 {
        for w in [pair.on, pair.off] { w.advance(by: 0.06) }
        try pair.compare("animation frame \(index) before the input")
    }
    for w in [pair.on, pair.off] { w.hover(at: pt(250, 250)) }
    for w in [pair.on, pair.off] { try w.click(w.element(label: "jump")) }
    #expect(pair.on.lastFrameWork.retainedRedos == 1, "the input's frame was redone once: \(pair.on.lastFrameWork.retainedRedos)")
    try pair.compare("the input's frame")
    for index in 0..<8 {
        for w in [pair.on, pair.off] { w.advance(by: 0.06) }
        try pair.compare("animation frame \(index) after the input")
    }
    #expect(pair.onSide.log.entries.filter { $0 == "appear" }.count == 1, "the appear ran once: \(pair.onSide.log.entries)")
    for w in [pair.on, pair.off] { w.advance(by: 1) }
    for w in [pair.on, pair.off] { try w.click(w.element(label: "scroll")) }
    try pair.compare("the scroll")
    for _ in 0..<3 { pair.redraw(); try pair.compare("after the scroll") }
}

// MARK: 6 — backoff and quarantine

/// 6 — an ancestor whose paint-only value changes on **every** frame costs at most one redo per eight frames at
/// first and then less: after a redo, prepaint replay is off for eight builds window-wide and the entry that caused
/// it is quarantined 8, 16, 32 … builds (`RK-D` item 3). Over 80 frames the gaps between redos are at least 9, 17 and
/// 33 builds, and every frame equals the retention-off frame. Mutations: the window-wide backoff removed (the first
/// gap is 1), the quarantine exponent never doubling (the second gap is 9).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read")) @MainActor func aPersistentlyAnimatedAncestorIsQuarantined() async throws {
    let pair = try RPPair(size: sz(200, 160), warm: 4) { rpAmbientRoot(.opacity, $0) }
    var redoFrames: [Int] = []
    for index in 0..<80 {
        pair.onSide.model.n += 1; pair.offSide.model.n += 1
        await rsSettle()
        pair.redraw()
        if pair.frames.last?.retainedRedos == 1 { redoFrames.append(index) }
        try pair.compare("frame \(index)")
    }
    try #require(redoFrames.count >= 3, "the ancestor changed every frame: \(redoFrames)")
    let gaps = zip(redoFrames.dropFirst(), redoFrames).map { $0 - $1 }
    #expect(gaps[0] >= 9, "the window-wide backoff: \(gaps)")
    #expect(gaps[1] >= 17, "the entry's quarantine doubles: \(gaps)")
    if gaps.count > 2 { #expect(gaps[2] >= 33, "and doubles again: \(gaps)") }
    #expect(redoFrames.count <= 4, "bounded: \(redoFrames)")
}

/// 6b — at most one redo per eight frames whatever changes: several different ancestors changing on alternate
/// frames cost one redo and then eight suspended builds, never a redo per frame (`RK-D` item 3).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read")) @MainActor func aRepeatedPaintOnlyChangeRedoesAtMostOncePerEightFrames() async throws {
    let pair = try RPPair(size: sz(200, 160), warm: 4) { rpAmbientRoot(.shadow, $0) }
    var redos = 0
    for index in 0..<40 {
        pair.onSide.model.n += 1; pair.offSide.model.n += 1
        await rsSettle()
        pair.redraw()
        redos += pair.frames.last?.retainedRedos ?? 0
        try pair.compare("frame \(index)")
    }
    #expect(redos >= 1 && redos <= 5, "redos over 40 frames: \(redos)")
}

// MARK: 7 — what prepaint replay refuses

enum RPKind: String, CaseIterable {
    case control, scrollRegion, textField, popover, dragSource, geometryChange
}

private struct RPKindCard: Component, @MainActor Equatable {
    let kind: RPKind
    let log: HarnessLog
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("kind \(kind.rawValue)").frame(width: Pixels(90), height: Pixels(14))
            switch kind {
            case .control:
                Button("ok") {}.frame(width: Pixels(40), height: Pixels(18))
            case .scrollRegion:
                ScrollView(.vertical) { Text("inside").frame(width: Pixels(80), height: Pixels(60)) }
                    .frame(width: Pixels(90), height: Pixels(30))
            case .textField:
                TextField("t", text: Binding(get: { "" }, set: { _ in })).frame(width: Pixels(90), height: Pixels(22))
            case .popover:
                Text("anchor").frame(width: Pixels(60), height: Pixels(14))
                    .popover(isPresented: .constant(true)) { Text("body").frame(width: Pixels(40), height: Pixels(14)) }
            case .dragSource:
                Text("drag").frame(width: Pixels(60), height: Pixels(14)).draggable("payload")
            case .geometryChange:
                Text("geometry").frame(width: Pixels(60), height: Pixels(14))
                    .onGeometryChange(for: Float.self, of: { $0.size.width.value }) { _ in }
            }
        }
    }
    static func == (l: RPKindCard, r: RPKindCard) -> Bool { l.kind == r.kind }
}

/// 7 — an occurrence holding a scroll region, a text field (a `withState` write), a presented popover, a drag source
/// or a geometry note runs its prepaint every frame (counted ineligible, `RK-E`), and its frames equal the
/// retention-off frames; the control arm (a button) replays prepaint, so "ineligible" is not "nothing replays".
/// Mutation, per arm: that kind's refusal removed — the arm's scene or hitbox list, or its stale geometry note,
/// differs, and `retainedPrepaintHits` reads 1.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read"), arguments: RPKind.allCases) @MainActor
func aPrepaintInEachIneligibleKindRunsAsBefore(kind: RPKind) async throws {
    let pair = try RPPair(size: sz(220, 140), warm: 4) { side in
        VStack(spacing: 4) {
            RPCard(title: "plain", shade: 1, log: side.log).equatable()
            RPKindCard(kind: kind, log: side.log).equatable()
        }
    }
    for index in 0..<3 {
        pair.redraw()
        try pair.compare("frame \(index)")
    }
    let f = try #require(pair.frames.last)
    if kind == .control {
        #expect(f.retainedPrepaintHits == 2, "both replay: \(f.retainedPrepaintHits)")
    } else {
        #expect(f.retainedPrepaintHits == 1, "only the plain neighbour replays prepaint: \(f.retainedPrepaintHits)")
        #expect(f.retainedPrepaintIneligible + f.retainedIneligible >= 1, "\(kind.rawValue) is refused by name")
    }
    #expect(f.retainedRedos == 0)
}

// MARK: 8 — the pointer, press and focus

/// 8 — a subtree the pointer is inside or focus is in runs its prepaint (`SB-X` extended to prepaint): the
/// decision is taken at prepaint from the pointer position against the record's own hitboxes (the hover resolves
/// after prepaint), so entering a card costs neither a redo nor a stale hitbox. The other three replay prepaint.
/// Mutation: the pointer rule dropped (the hovered card replays a prepaint whose hover regions miss the
/// registration the paint then expects; the differential reddens) or forced true (a quiet frame replays nothing).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read")) @MainActor func aFocusedOrHoveredElementUnderTheOccurrenceRunsPrepaint() throws {
    let pair = try RPPair(size: sz(420, 120), warm: 4) { side in
        HStack(spacing: 6) {
            RPCard(title: "A", shade: 0, log: side.log).equatable()
            RPCard(title: "B", shade: 1, log: side.log).equatable()
            RPCard(title: "C", shade: 2, log: side.log).equatable()
            RPCard(title: "D", shade: 3, log: side.log).equatable()
        }
    }
    pair.redraw()
    #expect(pair.frames.last?.retainedPrepaintHits == 4 && pair.frames.last?.retainedRedos == 0, "quiet: all four replay")
    func centre(_ w: TestWindow, _ label: String) throws -> Point<Pixels> {
        let f = try w.element(label: label).frame
        return pt(f.origin.x.value + f.size.width.value / 2, f.origin.y.value + f.size.height.value / 2)
    }
    for w in [pair.on, pair.off] { w.hover(at: try centre(w, "go B")) }
    var f = pair.on.lastFrameWork
    #expect(f.retainedPrepaintHits == 3 && f.retainedRedos == 0, "the pointer is inside card B: \(f.retainedPrepaintHits)/\(f.retainedRedos)")
    try pair.compare("hover")
    pair.redraw()
    f = pair.on.lastFrameWork
    #expect(f.retainedPrepaintHits == 3 && f.retainedRedos == 0, "and stays inside: \(f.retainedPrepaintHits)")
    for w in [pair.on, pair.off] { w.hover(at: pt(2, 2)) }
    try pair.compare("the pointer leaves")
    pair.redraw()
    f = pair.on.lastFrameWork
    #expect(f.retainedPrepaintHits == 4 && f.retainedRedos == 0, "away, all four replay again: \(f.retainedPrepaintHits)")
    for w in [pair.on, pair.off] { w.typeKey(.tab) }
    f = pair.on.lastFrameWork
    #expect(f.retainedPrepaintHits == 3 && f.retainedRedos == 0, "focus is in the first card: \(f.retainedPrepaintHits)")
    try pair.compare("focus")
}

// MARK: 9 — replayed handlers, the `@State` rule (`RK-O`)

private struct RPStateCard: Component, @MainActor Equatable {
    let log: HarnessLog
    @State var taps = 0
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("taps \(taps)").frame(width: Pixels(80), height: Pixels(14))
            Button("tap") { taps += 1; log.add("tap \(taps)") }.frame(width: Pixels(40), height: Pixels(18))
        }
    }
    static func == (l: RPStateCard, r: RPStateCard) -> Bool { l.log === r.log }
}

/// 9 — a replayed handler acts like a fresh one (`RK-O`, `RK-T`): the cards' buttons, context menus and a `@State`
/// button are invoked on a retaining window after replay and on a retention-off window; state, log, focus and scene
/// agree. The `@State` card has never been written when its first click is dispatched against replayed hitboxes:
/// a replayed closure's box holds the table and the slot id, not a value, so the write lands in the table's entry
/// (`RK-T` refutes `RK-O` item 2's refusal of a never-written slot by this arm). Mutations: a fixture handler
/// capturing a stale id (the log differs); a replayed hitbox list from another frame (the click goes elsewhere).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read")) @MainActor func aReplayedHandlerActsLikeAFreshOne() async throws {
    let pair = try RPPair(size: sz(300, 120), warm: 4) { side in
        HStack(spacing: 6) {
            RPCard(title: "A", shade: 0, log: side.log).equatable()
            RPStateCard(log: side.log).equatable()
        }
    }
    pair.redraw()
    var f = try #require(pair.frames.last)
    #expect(f.retainedPrepaintHits == 2, "both cards replay, the never-written @State card included: \(f.retainedPrepaintHits)")
    try pair.compare("before any write")
    for w in [pair.on, pair.off] { try w.click(w.element(label: "go A")) }
    try pair.compare("a replayed button")
    for w in [pair.on, pair.off] { try w.click(w.element(label: "tap")) }
    try pair.compare("the first write")
    for w in [pair.on, pair.off] { w.hover(at: pt(296, 116)) }   // the pointer leaves the card it clicked
    pair.redraw(); pair.redraw(); pair.redraw()
    f = try #require(pair.frames.last)
    #expect(f.retainedPrepaintHits == 2, "after a write both replay: \(f.retainedPrepaintHits)")
    for _ in 0..<3 {
        for w in [pair.on, pair.off] { try w.click(w.element(label: "tap")) }
        try pair.compare("a replayed @State button")
    }
    for w in [pair.on, pair.off] { try w.rightClick(w.element(label: "go A")) }
    try pair.compare("a replayed context menu")
    #expect(pair.onSide.log.entries.contains("tap 4"), "the @State handler wrote through its replayed closure: \(pair.onSide.log.entries)")
}
