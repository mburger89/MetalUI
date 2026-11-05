import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Text links under retention (`LI-A`, `LI-C`; record 216). Hitboxes and accessibility records of a link are ordinary
// registrations, so a replayed prepaint carries them; the one thing a replay must not do is run a STALE action, which is
// why `\.openURL` is uncomparable. Counts and values, never time. Platform opens are read off the headless window
// (`HeadlessPlatformWindow.openedURLs`): nothing reaches `NSWorkspace`.

/// A card: a line of text with one link, and a bar. `==` on its inputs.
struct RPLinkCard: Component, @MainActor Equatable {
    let title: String
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text(try! AttributedString(markdown: "see [docs \(title)](https://x.org/\(title))"))
                .frame(width: Pixels(120), height: Pixels(14))
            Box().frame(width: Pixels(40), height: Pixels(8)).background(.accent)
        }
        .padding(Edges(all: Pixels(4)))
    }
    static func == (l: RPLinkCard, r: RPLinkCard) -> Bool { l.title == r.title }
}

/// Three link cards under the pan of `RPPanRoot`, each `.equatable()`.
struct RPLinkPanRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        let pan = side.inputs.offset
        ZStack(alignment: .topLeading) {
            ForEach(Array(0..<3), id: \.self) { k in
                ZStack(alignment: .topLeading) { RPLinkCard(title: "P\(k)").equatable() }
                    .offset(x: Pixels(Float(k * 20) + pan), y: Pixels(Float(k * 30) + pan / 2))
            }
        }
        .frame(width: Pixels(300), height: Pixels(130), alignment: .topLeading)
        .clipped()
    }
}

/// **A headless window records the URL it was asked to open** (`HT-X` 1). A click on the link's accessibility element
/// opens `https://x.org/P0` once; the platform window holds it in `openedURLs`. Mutation: the headless `openURL`
/// records nothing (the list stays empty).
@Test @MainActor func aHeadlessWindowRecordsTheURLAClickOpened() throws {
    let window = try TestWindow(size: sz(300, 60)) {
        VStack(alignment: .leading, spacing: 0) {
            Text(try! AttributedString(markdown: "see [docs](https://x.org)")).frame(width: Pixels(140), height: Pixels(16))
        }
    }
    #expect(window.platformWindow.openedURLs == [])
    try window.click(window.element(label: "docs"))
    #expect(window.platformWindow.openedURLs == ["https://x.org"], "\(window.platformWindow.openedURLs)")
}

/// **A translated replay still opens at the moved rect** (`LI-A`, `RK-S`): three occurrences panned under `.offset`,
/// the retaining window and the retention-off window compared whole at every step (hitboxes with their rects, the
/// accessibility tree), a click on the first card's link after each pan opening the same URL in both, and the retaining
/// side having replayed prepaint (a differential that replays nothing proves nothing). Mutations: record the link's
/// hitbox at a frame-local rect (the click at the moved rect misses), drop the link's accessibility record from the
/// ledger (the tree differs).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read"))
@MainActor func aTranslatedReplayOpensAtTheMovedRect() async throws {
    let pair = try RPPair(size: sz(320, 150), warm: 4, graft: false) { side in
        VStack(spacing: 0) { RPLinkPanRoot(side: side) }
    }
    try pair.compare("warm")
    var replayed = 0, opens = 0
    for (index, pan) in [Float(0), 7, 14.5, 21, 6].enumerated() {
        pair.onSide.inputs.offset = pan; pair.offSide.inputs.offset = pan
        await rsSettle()
        pair.redraw()
        replayed += try #require(pair.frames.last).retainedPrepaintHits
        try pair.compare("pan step \(index) (\(pan))")
        for w in [pair.on, pair.off] { try w.click(w.element(label: "docs P0")) }
        opens += 1
        #expect(pair.on.platformWindow.openedURLs == pair.off.platformWindow.openedURLs, "the same opens at step \(index)")
        #expect(pair.on.platformWindow.openedURLs == Array(repeating: "https://x.org/P0", count: opens),
                "step \(index): \(pair.on.platformWindow.openedURLs)")
    }
    #expect(replayed > 0, "the retaining side replayed prepaint: \(replayed)")
}

/// **A changed action above `.equatable()` is not stale** (`LI-C`, `EE-`). An action is a closure, so the reading is
/// uncomparable and the `.equatable()` subtree below it is evaluated again each frame; the link then runs the action
/// the CURRENT frame built. The retention-off window agrees. Mutation: make `OpenURLAction` `Equatable` (always equal)
/// so the key reads comparable: the replayed hitbox runs the first action and `open A` is logged after the change.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read"))
@MainActor func aChangedActionAboveAnEquatableSubtreeIsNotStale() async throws {
    let pair = try RPPair(size: sz(320, 100), warm: 4) { side in
        let tag = side.inputs.text.isEmpty ? "A" : side.inputs.text
        return VStack(alignment: .leading, spacing: 0) { RPLinkCard(title: "L").equatable() }
            .environment(\.openURL, OpenURLAction { url in side.log.add("open \(tag) \(url.absoluteString)"); return .handled })
    }
    for w in [pair.on, pair.off] { try w.click(w.element(label: "docs L")) }
    #expect(pair.onSide.log.entries == ["open A https://x.org/L"], "\(pair.onSide.log.entries)")
    pair.onSide.inputs.text = "B"; pair.offSide.inputs.text = "B"
    await rsSettle()
    pair.redraw(); pair.redraw()
    for w in [pair.on, pair.off] { try w.click(w.element(label: "docs L")) }
    #expect(pair.onSide.log.entries == ["open A https://x.org/L", "open B https://x.org/L"],
            "the changed action ran, not the first: \(pair.onSide.log.entries)")
    #expect(pair.onSide.log.entries == pair.offSide.log.entries, "retention on equals retention off")
    try pair.compare("after the change")
}
