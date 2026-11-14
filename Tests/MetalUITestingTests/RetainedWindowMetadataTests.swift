import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// Alloy `windowMetadata` ineligibles (`RW-X`, record 303): an `.equatable()` occurrence that reports a window preference
// (`.navigationTitle`, `.navigationSubtitle`, `.navigationDocument`, `.windowTitleBarMetrics`, `.windowDismissBehavior`,
// `.onOpenURL`) journals the reports and a graft reports them again, in the order the build did. Two windows over one
// builder as in `RetainedGraftTests`: the retaining one and one with retention off; what the platform was told and what an
// open URL did are compared against the retention-off window. The graft counts are not read under METALUI_VERIFY_RETAINED=1.

private let verifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read"

private let rwDocument = URL(fileURLWithPath: "/tmp/rw-x.txt")

/// The reporting content, a Component of its own (a large subtree inline overflows the Windows 1 MB debug test stack).
private struct RWMeta: Component, @MainActor Equatable {
    let side: RPSide
    let title: String
    var content: some ElementGroup {
        let log = side.log
        VStack(spacing: 4) {
            RPCard(title: "meta", shade: 1, log: side.log).equatable()
        }
        .navigationTitle(title)
        .navigationSubtitle("sub \(title)")
        .navigationDocument(rwDocument)
        .windowTitleBarMetrics(height: Pixels(40), controlsLeading: Pixels(12))
        .windowDismissBehavior(.disabled)
        .onOpenURL { log.add("open \($0.lastPathComponent)") }
    }
    static func == (l: RWMeta, r: RWMeta) -> Bool { l.side === r.side && l.title == r.title }
}

private struct RWColumn: Component, @MainActor Equatable {
    let side: RPSide
    let title: String
    var content: some ElementGroup {
        VStack(spacing: 4) {
            RPCard(title: "files", shade: 2, log: side.log).equatable()
            RWMeta(side: side, title: title).equatable()
        }
    }
    static func == (l: RWColumn, r: RWColumn) -> Bool { l.side === r.side && l.title == r.title }
}

/// A root that reads `model.n` (typing) and, while `inputs.showExtra`, reports its own title before the column does.
@MainActor private func rwPair(warm: Int = 6) throws -> RPPair<some Element> {
    try RPPair(size: sz(260, 400), warm: warm) { side in
        let model = side.model, inputs = side.inputs
        return VStack(alignment: .leading, spacing: 4) {
            if inputs.showExtra {
                Text("first").frame(width: Pixels(40), height: Pixels(12)).navigationTitle("first wins")
            }
            Text("typed \(model.n)").frame(width: Pixels(80), height: Pixels(12))
            RWColumn(side: side, title: inputs.text.isEmpty ? "doc" : inputs.text).equatable()
        }
    }
}

@MainActor private func rwType(_ pair: RPPair<some Element>, steps: Int = 3) async throws {
    for step in 0..<steps {
        pair.onSide.model.n += 1; pair.offSide.model.n += 1
        await rsSettle()
        pair.redraw()
        try pair.compare("typed \(step)")
    }
}

@MainActor private func rwOpen(_ pair: RPPair<some Element>, _ url: URL) {
    for window in [pair.on, pair.off] { window.testApp.app.open([url]) }
    pair.redraw()
}

/// What each window's platform was told, compared between the two windows.
@MainActor private func rwSame(_ pair: RPPair<some Element>, _ what: String) {
    let on = pair.on.platformWindow, off = pair.off.platformWindow
    #expect(on.title == off.title, "\(what): title \(on.title) vs \(off.title)")
    #expect(on.representedPaths.last == off.representedPaths.last, "\(what): document")
    #expect(on.subtitleWrites.last == off.subtitleWrites.last, "\(what): subtitle \(on.subtitleWrites) vs \(off.subtitleWrites)")
    #expect(on.dismissEnabledCalls == off.dismissEnabledCalls, "\(what): dismiss \(on.dismissEnabledCalls) vs \(off.dismissEnabledCalls)")
    #expect(on.titleBarMetricsRequests.map(\.height) == off.titleBarMetricsRequests.map(\.height), "\(what): metrics")
}

/// The column holding every window preference grafts while typing above, where it was refused by `windowMetadata`.
/// **Red before:** `retainedGrafts` reads 0 and `retainedIneligibleReasons["windowMetadata"]` is set; **mutation:** the
/// `.windowPreference` case dropped from `BuildAudit`'s replacement (the audit counts the channel again).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aColumnReportingWindowPreferencesGraftsWhileTypingAbove() async throws {
    let pair = try rwPair()
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
        #expect(f.retainedIneligibleReasons["windowMetadata"] == nil, "\(f.retainedIneligibleReasons)")
    }
    print("PROBE window metadata requests per frame: \(requests)")
    #expect(requests.allSatisfy { $0 < 10 }, "the column's build is skipped: \(requests)")
}

/// After the graft, the platform holds the title, subtitle, document, dismiss behavior and title-bar metrics the build
/// reported, as the retention-off window does. **Mutation:** the `.windowPreference` replay case emptied (the title is empty).
@Test @MainActor
func aGraftedOccurrenceStillReportsItsWindowPreferences() async throws {
    let pair = try rwPair()
    try await rwType(pair)
    #expect(pair.on.platformWindow.title == "doc", "\(pair.on.platformWindow.title)")
    #expect(pair.on.platformWindow.subtitleWrites.last == "sub doc")
    #expect(pair.on.platformWindow.representedPaths.last == rwDocument.path)
    #expect(pair.on.platformWindow.dismissEnabledCalls.last == false)
    rwSame(pair, "after grafts")
}

/// A URL the app is asked to open reaches the grafted occurrence's handler, once, as on the retention-off window.
/// **Mutation:** the `.openURL` report not replayed (no handler: the log stays empty and the app's fallback is used).
@Test @MainActor
func anOpenURLReachesAGraftedOccurrencesHandler() async throws {
    let pair = try rwPair()
    try await rwType(pair)
    rwOpen(pair, URL(fileURLWithPath: "/tmp/one.txt"))
    try await rwType(pair, steps: 2)
    rwOpen(pair, URL(fileURLWithPath: "/tmp/two.txt"))
    #expect(pair.onSide.log.entries == pair.offSide.log.entries, "\(pair.onSide.log.entries) vs \(pair.offSide.log.entries)")
    #expect(pair.onSide.log.entries.filter { $0.hasPrefix("open") } == ["open one.txt", "open two.txt"], "\(pair.onSide.log.entries)")
}

/// A changed title is an input change: the occurrence builds and the platform follows; typing after it grafts again with the new one.
@Test @MainActor
func aChangedTitleReachesThePlatformThroughAndAfterGrafts() async throws {
    let pair = try rwPair()
    try await rwType(pair)
    for side in [pair.onSide, pair.offSide] { side.inputs.text = "renamed" }
    pair.redraw()
    #expect(pair.on.platformWindow.title == "renamed", "\(pair.on.platformWindow.title)")
    try await rwType(pair)
    #expect(pair.on.platformWindow.title == "renamed")
    #expect(pair.on.platformWindow.subtitleWrites.last == "sub renamed")
    rwSame(pair, "after rename")
}

/// First wins across a graft: an earlier sibling's title beats the grafted occurrence's while it is present, and the
/// occurrence's shows again once it leaves, whether the occurrence built or grafted. **Mutation:** the replay sets the
/// title unconditionally (the later report beats the first).
@Test @MainActor
func anEarlierSiblingsTitleBeatsAGraftedOnesAndYieldsWhenItLeaves() async throws {
    let pair = try rwPair()
    try await rwType(pair)
    for side in [pair.onSide, pair.offSide] { side.inputs.showExtra = true }
    try await rwType(pair, steps: 10)   // a structural change quarantines the column's entry for a few builds
    #expect(pair.on.platformWindow.title == "first wins", "\(pair.on.platformWindow.title)")
    if !rsVerifying { #expect((pair.frames.last?.retainedGrafts ?? 0) >= 1, "the occurrence grafts under the sibling's title: \(pair.frames.last?.retainedIneligibleReasons ?? [:])") }
    rwSame(pair, "sibling present")
    for side in [pair.onSide, pair.offSide] { side.inputs.showExtra = false }
    try await rwType(pair, steps: 3)
    #expect(pair.on.platformWindow.title == "doc", "\(pair.on.platformWindow.title)")
    rwSame(pair, "sibling gone")
}
