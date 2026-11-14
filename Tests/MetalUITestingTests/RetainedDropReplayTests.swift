import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// Alloy G45 (`RW-W`, record 293): an `.equatable()` occurrence holding a drop destination leaves a prepaint ledger, so its
// ancestors replay and graft. Two windows over one builder as in `RetainedGraftTests`: the retaining one and one with retention
// off; every behaviour (a drop's items and location, the targeting callbacks, a code-opened menu) is compared by log against the
// retention-off window after the ancestors replayed. The counts are not read under `METALUI_VERIFY_RETAINED=1`.

private let verifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read"

private func fileItem(_ path: String) -> DropItem {
    let type = PasteboardType(identifier: ContentType.fileURL.identifier, conformsTo: ContentType.fileURL.conformance.sorted())
    let bytes = [UInt8](URL(fileURLWithPath: path).absoluteString.utf8)
    return DropItem(types: [type]) { $0 == type.identifier ? bytes : nil }
}

private func textItem(_ text: String) -> DropItem {
    let type = PasteboardType(identifier: ContentType.plainText.identifier, conformsTo: ContentType.plainText.conformance.sorted())
    return DropItem(types: [type]) { $0 == type.identifier ? [UInt8](text.utf8) : nil }
}

/// The composer, shaped as Alloy's: a drop destination over the whole card, a code-driven menu, a menu picker.
private struct RDComposer: Component, @MainActor Equatable {
    let side: RPSide
    let draggable: Bool
    var content: some ElementGroup {
        let log = side.log
        let open = Binding<Bool>(get: { side.menuOpen }, set: { side.menuOpen = $0 })
        let mode = Binding<Int>(get: { 0 }, set: { _ in })
        VStack(alignment: .leading, spacing: 4) {
            Text("composer").frame(width: Pixels(120), height: Pixels(12))
            HStack(spacing: 4) {
                Picker("Mode", selection: mode) { Text("Ask").tag(0); Text("Plan").tag(1) }
                Menu("Model") { Button("Sonnet") {}; Button("Opus") {} }.menuPresented(open)
            }
            if draggable {
                Text("source").frame(width: Pixels(60), height: Pixels(12)).draggable("payload")
            }
        }
        .frame(width: Pixels(200), height: Pixels(90), alignment: .topLeading)
        .dropDestination(for: URL.self, action: { urls, location in
            log.add("drop \(urls.map(\.lastPathComponent)) at \(location.x.value),\(location.y.value)")
            return true
        }, isTargeted: { log.add("targeted \($0)") })
    }
    static func == (l: RDComposer, r: RDComposer) -> Bool { l.side === r.side && l.draggable == r.draggable }
}

private struct RDColumn: Component, @MainActor Equatable {
    let side: RPSide
    let draggable: Bool
    var content: some ElementGroup {
        VStack(spacing: 4) {
            RPCard(title: "files", shade: 2, log: side.log).equatable()
            RDComposer(side: side, draggable: draggable).equatable()
        }
    }
    static func == (l: RDColumn, r: RDColumn) -> Bool { l.side === r.side && l.draggable == r.draggable }
}

/// A plain root that reads `model.n` (the typed text) above the retained column.
@MainActor private func rdPair(draggable: Bool = false, warm: Int = 6) throws -> RPPair<some Element> {
    try RPPair(size: sz(260, 400), warm: warm) { side in
        let model = side.model
        return VStack(alignment: .leading, spacing: 4) {
            Text("typed \(model.n)").frame(width: Pixels(80), height: Pixels(12))
            RDColumn(side: side, draggable: draggable).equatable()
        }
    }
}

@MainActor private func rdType(_ pair: RPPair<some Element>, steps: Int = 3) async throws {
    for step in 0..<steps {
        pair.onSide.model.n += 1; pair.offSide.model.n += 1
        await rsSettle()
        pair.redraw()
        try pair.compare("typed \(step)")
    }
}

/// The composer's drop target in window points: the column is at y 16, the card below `files` (about 4 + the card's height).
@MainActor private func rdComposerPoint(_ window: TestWindow) throws -> Point<Pixels> {
    let element = try window.element(label: "composer")
    let frame = try #require(try window.accessibilityTree.geometry[element.id]?.frame)
    return Point(x: Pixels(frame.origin.x.value + 20), y: Pixels(frame.origin.y.value + 30))
}

/// The ancestors replay around a composer with a drop destination: the column grafts and its build is skipped while typing.
/// **Red before:** `retainedGrafts` reads 0 and the frame builds the column (the `dragAndDrop` refusal names the composer);
/// **mutation:** the destination clause restored in `closePrepaintWindow` (the same).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aColumnHoldingADropDestinationGraftsWhileTypingAbove() async throws {
    let pair = try rdPair()
    try pair.compare("warm")
    var requests: [Int] = []
    for step in 0..<5 {
        pair.onSide.model.n += 1; pair.offSide.model.n += 1
        await rsSettle()
        pair.redraw()
        let f = try #require(pair.frames.last)
        requests.append(f.elementRequests)
        try pair.compare("typed \(step)")
        #expect(f.retainedGrafts >= 1, "the column grafts: \(f.retainedGrafts); ineligible \(f.retainedIneligibleReasons)")
        #expect(f.retainedIneligibleReasons["dragAndDrop"] == nil, "\(f.retainedIneligibleReasons)")
    }
    print("PROBE drop column requests per frame: \(requests)")
    #expect(requests.allSatisfy { $0 < 10 }, "the column's build is skipped: \(requests)")
}

/// A drop on a replayed composer hands the action the same items at the same destination-local location as the
/// retention-off window's, and the targeting callbacks fire in the same order: entered (`true`), moved, exited (`false`),
/// then entered again and performed (`false` before the action). **Mutations:** the destination's hitbox not replayed (no
/// target, no callbacks: the logs differ); the replayed hitbox at the recorded origin after a move (see the moved arm).
@Test @MainActor
func aDropOnAReplayedComposerBehavesAsOnAFreshOne() async throws {
    let pair = try rdPair()
    try await rdType(pair)
    if !rsVerifying { #expect((pair.frames.last?.retainedGrafts ?? 0) >= 1, "replaying before the drop") }
    let point = try rdComposerPoint(pair.on)
    for window in [pair.on, pair.off] {
        _ = window.send(.drop(.entered(position: point, items: [fileItem("/tmp/a.txt")])))
        _ = window.send(.drop(.moved(position: pt(point.x.value + 5, point.y.value))))
        _ = window.send(.drop(.exited))
        window.tick()
        window.drop([fileItem("/tmp/b.txt"), fileItem("/tmp/c.txt")], at: point)
    }
    let log = pair.onSide.log.entries
    #expect(log == pair.offSide.log.entries, "\(log) vs \(pair.offSide.log.entries)")
    #expect(log.contains("targeted true") && log.contains("targeted false"), "\(log)")
    #expect(log.contains { $0.hasPrefix("drop [\"b.txt\", \"c.txt\"] at 49.0,27.0") }, "the items and the destination-local location (the point less the card's origin): \(log)")
    try pair.compare("after the drops")
}

/// A destination that refuses the offered type targets nothing on a replayed composer, as on a fresh one.
@Test @MainActor
func aReplayedDestinationStillRefusesAnItemItDoesNotImport() async throws {
    let pair = try rdPair()
    try await rdType(pair)
    let point = try rdComposerPoint(pair.on)
    for window in [pair.on, pair.off] { window.drop([textItem("hello")], at: point) }
    #expect(pair.onSide.log.entries == pair.offSide.log.entries)
    #expect(!pair.onSide.log.entries.contains { $0.hasPrefix("drop") || $0.hasPrefix("targeted") }, "\(pair.onSide.log.entries)")
}

/// The menu a replayed composer holds still opens from code and closes, and the drop still works after it.
@Test @MainActor
func aReplayedComposerStillOpensItsMenuFromCode() async throws {
    let pair = try rdPair()
    try await rdType(pair)
    pair.onSide.menuOpen = true; pair.offSide.menuOpen = true
    pair.redraw(); pair.redraw()
    #expect(pair.on.presentedMenu != nil && pair.off.presentedMenu != nil, "the menu is up in both windows")
    try pair.compare("open")
    pair.onSide.menuOpen = false; pair.offSide.menuOpen = false
    for _ in 0..<3 { pair.redraw() }
    #expect(pair.on.presentedMenu == nil && pair.off.presentedMenu == nil)
    let point = try rdComposerPoint(pair.on)
    for window in [pair.on, pair.off] { window.drop([fileItem("/tmp/z.txt")], at: point) }
    #expect(pair.onSide.log.entries == pair.offSide.log.entries)
    #expect(pair.onSide.log.entries.contains { $0.hasPrefix("drop") })
}

/// The composer moves (the row above it grows) after it replayed: its destination follows it, a drop at the new place lands
/// and one at the old place does not, as in the retention-off window.
@Test @MainActor
func aMovedReplayedDestinationIsDroppedOnWhereItIsDrawn() async throws {
    let pair = try RPPair(size: sz(260, 420), warm: 6) { side in
        let model = side.model
        return VStack(alignment: .leading, spacing: 4) {
            Text("pad").frame(width: Pixels(40), height: Pixels(Float(10 + (model.n % 2) * 20)))
            RDColumn(side: side, draggable: false).equatable()
        }
    }
    try pair.compare("warm")
    let before = try rdComposerPoint(pair.on)
    for step in 0..<3 {
        pair.onSide.model.n += 1; pair.offSide.model.n += 1
        await rsSettle()
        pair.redraw()
        try pair.compare("moved \(step)")
    }
    let after = try rdComposerPoint(pair.on)
    #expect(after.y.value != before.y.value, "the composer moved: \(before) -> \(after)")
    for window in [pair.on, pair.off] {
        window.drop([fileItem("/tmp/m.txt")], at: after)
        window.drop([fileItem("/tmp/old.txt")], at: Point(x: before.x, y: Pixels(before.y.value - 60)))
    }
    #expect(pair.onSide.log.entries == pair.offSide.log.entries, "\(pair.onSide.log.entries) vs \(pair.offSide.log.entries)")
    #expect(pair.onSide.log.entries.contains { $0.contains("m.txt") })
}

/// A draggable still leaves no ledger: its occurrence and every ancestor build, by name.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aDraggableInsideTheColumnStillRefusesReplay() async throws {
    let pair = try rdPair(draggable: true)
    try await rdType(pair)
    let f = try #require(pair.frames.last)
    #expect(f.elementRequests >= 20, "the column and the composer build every frame: \(f.elementRequests)")
    #expect((f.retainedIneligibleReasons["dragAndDrop"] ?? 0) >= 1, "\(f.retainedIneligibleReasons)")
}
