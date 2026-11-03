import Foundation
import MetalUI
import MetalUITesting
import Testing

// `FV-A`/`FV-B` over the retained paths (record 199): a seeded `@State` is read by a retained record, a graft and a
// replayed prepaint exactly as an unwritten slot was.

private let verifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read"

/// A child component with a `@State` seeded from its parameter: it binds **inside** the occurrence's recorded window,
/// where a seed that tainted would taint the open record (the card's own bind precedes the window, `EquatableComponent`).
struct FVInnerSeeded: Component {
    let parent: Int
    @State var seed: Int
    init(parent: Int) { self.parent = parent; _seed = State(wrappedValue: parent) }
    var content: some ElementGroup {
        Text("in \(seed)").frame(width: Pixels(60), height: Pixels(14))
    }
}

/// An `.equatable()` card holding a never-written `@State` seeded from its parameter through `init`, and an inner
/// component with one of its own.
struct FVRetainedCard: Component, @MainActor Equatable {
    let title: String
    let parent: Int
    @State var seed: Int
    init(title: String, parent: Int) {
        self.title = title; self.parent = parent
        _seed = State(wrappedValue: parent)
    }
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Text("\(title) \(seed)").frame(width: Pixels(80), height: Pixels(14))
            FVInnerSeeded(parent: parent)
        }
    }
    static func == (l: FVRetainedCard, r: FVRetainedCard) -> Bool { l.title == r.title && l.parent == r.parent }
}

@Observable @MainActor final class FVModel {
    var show = true
    var parent = 3
}

/// Two windows over one builder: `on` retains (record, ledger, graft), `off` retains nothing; each has its own model.
@MainActor private func fvPair() throws -> (on: TestWindow, off: TestWindow, onModel: FVModel, offModel: FVModel) {
    func make(_ model: FVModel) throws -> TestWindow {
        try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
            VStack(spacing: 0) { if model.show { FVRetainedCard(title: "A", parent: model.parent).equatable() } }
        }
    }
    let onModel = FVModel(), offModel = FVModel()
    let on = try make(onModel), off = try make(offModel)
    off.window.testingRetainedSubtrees = false
    return (on, off, onModel, offModel)
}

@MainActor private func fvSeeded(_ window: TestWindow) -> [String] {
    window.window.testingStateEntries.filter { $0.contains("$state") }
}

@MainActor private func fvStep(_ pair: (on: TestWindow, off: TestWindow, onModel: FVModel, offModel: FVModel),
                               _ change: (FVModel) -> Void = { _ in }) {
    change(pair.onModel); change(pair.offModel)
    for w in [pair.on, pair.off] { w.window.setNeedsRedraw(); w.tick() }
}

/// A seed taints nothing (`FV-B`, amends `RW-F`). The first frame of the pair seeds the card's `@State` and records
/// it; the **next** frame already hits the paint record, replays the prepaint and grafts the build, evaluates no
/// content, and equals the retention-off window's scene and state entries. A seed that tainted the open record
/// (`retainLog?.taint("stateWrite")`, `contentMemos.journal.taint`) leaves no record from the first frame, so the second
/// frame would build and the hit would come a frame late. Mutation: that taint added to `mark(_:seeding:)`.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aSeedDoesNotTaintARetainedRecord() throws {
    let pair = try fvPair()
    fvStep(pair)
    let f = pair.on.lastFrameWork
    #expect(f.retainedHits == 1, "the paint record made by the seeding frame hits at once: \(f.retainedHits)")
    #expect(f.retainedPrepaintHits == 1 && f.retainedGrafts == 1, "prepaint \(f.retainedPrepaintHits), grafts \(f.retainedGrafts)")
    #expect(f.contentEvaluations == 0 && f.contentSkips == 1, "evaluations \(f.contentEvaluations), skips \(f.contentSkips)")
    #expect(pair.on.scene.rects.count == pair.off.scene.rects.count && pair.on.scene.glyphs.count == pair.off.scene.glyphs.count)
    #expect(pair.on.window.testingStateEntries == pair.off.window.testingStateEntries)
    #expect(pair.off.lastFrameWork.retainedHits == 0, "the retention-off window replays nothing")
}

/// A grafted occurrence keeps its seeded entry (`FV-B`): across grafted frames the entry stays live and the window's
/// entries equal the retention-off window's at every step of a script that hides the card (an evaluated conditional
/// resets its entry), shows it again (seeded again from the new parameter, a fresh build and a fresh record) and lets
/// the new record graft. The grafting side replays the journal's plain `.mark`, and records no value in it (a
/// `GraftRecord` holding the instance would outlive the reset). Mutation: the `.mark` arm of `Frame.reapply` and the
/// record's `marks` replay both removed (the entry goes stale).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aGraftedOccurrenceKeepsItsSeededEntry() throws {
    let pair = try fvPair()
    func agree(_ step: String) throws {
        #expect(pair.on.window.testingStateEntries == pair.off.window.testingStateEntries, "entries after \(step)")
        let differences = try RPSnapshot(pair.on, accessibility: false).differences(from: RPSnapshot(pair.off, accessibility: false))
        #expect(differences.isEmpty, "after \(step): \(differences)")
    }
    for _ in 0..<5 { fvStep(pair) }
    #expect(pair.on.lastFrameWork.retainedGrafts == 1, "set up: the occurrence is grafted")
    let seeded = fvSeeded(pair.on)
    #expect(seeded.count == 2 && seeded.allSatisfy { $0.hasSuffix("live:true") }, "both seeded entries are live: \(seeded)")
    try agree("the grafted frames")
    fvStep(pair) { $0.show = false }
    #expect(fvSeeded(pair.on).isEmpty, "hiding the card reset its seeded entry: \(fvSeeded(pair.on))")
    try agree("hiding")
    fvStep(pair) { $0.show = true; $0.parent = 8 }
    #expect(fvSeeded(pair.on).count == 2, "showing it seeds both again: \(fvSeeded(pair.on))")
    try agree("showing")
    for _ in 0..<5 { fvStep(pair) }
    #expect(pair.on.lastFrameWork.retainedGrafts == 1, "the new record grafts")
    #expect(fvSeeded(pair.on).count == 2 && fvSeeded(pair.on).allSatisfy { $0.hasSuffix("live:true") })
    try agree("the second life")
}
