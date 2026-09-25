import Testing
import Foundation
import Metal
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Plan task 8, lane 3 (`docs/superpowers/specs/2026-09-25-composition-identity-design.md`
// §3.7, ruling `ID-J`): a legacy `.background(alignment:content:)`.
// `BackgroundModifier` takes any `ElementGroup` on either side, on
// `OverlayModifier`'s `LR-FX` recipe line for line: both sides through
// `lowerAttachmentChildren`, the background side numbered under
// `.child(of: id, at: -1)` (`MC-P`), prepaint and paint background first. A
// primary of zero or several nodes traps naming its count (divergence 73).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func dim(_ v: Float) -> MetalUICore.Dimension { .length(.pixels(Pixels(v))) }

private func sized(_ w: Float, _ h: Float) -> Style {
    var s = Style()
    s.size = Size(width: dim(w), height: dim(h))
    return s
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

/// A legacy `Component` with two members, so its node count is 2.
private struct TwoMembers: Component {
    var content: some ElementGroup {
        Box(style: sized(10, 10))
        Box(style: sized(10, 10))
    }
}

@MainActor
private final class ClickLog {
    var clicks: [String] = []
}

// MARK: - B3.1: behind, at the primary's size, the primary on top

/// **B3.1 — a legacy background sits behind its primary, proposed the primary's
/// size.** A 40×20 `Box` filled `.surface`, with `.background(alignment:
/// .topLeading) { 10×10 Box filled .accent }`, as a 100×100 window's root:
///
/// - the background's rect is the primary's origin, 10×10 (`.topLeading` in
///   the primary's 40×20), relative to the primary;
/// - the scene emits the background's fill **before** the primary's (it paints
///   beneath);
/// - with both clickable, a click at the primary's (5, 5) — inside both —
///   reaches the primary only: the background prepaints first, so its hitbox
///   ranks below (overlay-presentation probe H1, the proposal background's rule).
///
/// Red before: does not compile (`BackgroundModifier` requires
/// `ProposalElementGroup` content). Mutation **M3g** (paint the background after
/// the primary) flips the scene's order.
@Test @MainActor func aLegacyBackgroundSitsBehindItsPrimaryAtThePrimarysSize() throws {
    let log = ClickLog()
    func make() -> BackgroundModifier<Box<EmptyGroup>, Box<EmptyGroup>> {
        Box(style: sized(40, 20)).background(.surface).onClick { log.clicks.append("primary") }
            .background(alignment: .topLeading) {
                Box(style: sized(10, 10)).background(.accent).onClick { log.clicks.append("background") }
            }
    }
    var root = make()
    let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1,
                      reportsUnlowerableFields: true, recordsElementBounds: true)
    frame.render(&root)
    try #require(frame.unlowerableFields.isEmpty, "report: \(frame.unlowerableFields)")
    let primary = try #require(frame.elementBounds[child(rootID, 0)], "the primary was not laid out")
    let background = try #require(frame.elementBounds[child(GlobalElementID.child(of: rootID, at: -1, name: nil), 0)],
                                  "the background was not laid out at MC-P's side")
    #expect([primary.size.width.value, primary.size.height.value] == [40, 20], "primary \(primary)")
    #expect([background.origin.x.value - primary.origin.x.value, background.origin.y.value - primary.origin.y.value,
             background.size.width.value, background.size.height.value] == [0, 0, 10, 10],
            "background relative to the primary: \(background) in \(primary)")

    let rects: [[Float]] = frame.finalizedScene().rects.map {
        [$0.bounds.size.width, $0.bounds.size.height]
    }
    #expect(rects == [[10, 10], [40, 20]], "the background's fill first, then the primary's: \(rects)")

    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) { make() }
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let point = Point(x: px(primary.origin.x.value + 5), y: px(primary.origin.y.value + 5))
    platformWindow.simulateInput(.mouseDown(MouseEvent(position: point)))
    platformWindow.simulateInput(.mouseUp(MouseEvent(position: point)))
    #expect(log.clicks == ["primary"], "a click over both reaches the primary: \(log.clicks)")
}

// MARK: - B3.2: `MC-P`'s side over a legacy primary

/// **B3.2 — a legacy background's content keeps its state when the primary
/// changes shape** (`MC-P`; probe `swiftui-modifier-identity.swift` F). A
/// 60×60 legacy `Box { if flag { 20×20 }; p }` primary behind which a counter
/// sits, rendered at `flag` true, false, true against one table: the counter is
/// at `.child(.child(root, -1), 0)` at every step and reads 1, 2, 3.
///
/// Since `ID-B` no builder content moves an index at run time (`ID-P` item 3),
/// so what the flip still changes is the primary's node count; the path is
/// what pins `MC-P` here.
///
/// A second arm puts a proposal background under a `VStack`, so the typed entry
/// is pinned too (`ID-Q` item 2).
///
/// Red before: does not compile. Mutation **M3h** (the background side numbered
/// under `id` at the cursor after the primary, untyped entry) moves the counter
/// to `root/1`; **M3h′** (the same in the typed entry) reddens the second arm.
@Test @MainActor func aLegacyBackgroundsContentKeepsItsStateWhenThePrimaryChangesShape() throws {
    let table = StateTable()
    let reads = ConditionalReads()
    let side = child(GlobalElementID.child(of: rootID, at: -1, name: nil), 0)
    var seen: [Int?] = []
    for flag in [true, false, true] {
        var root = Box(style: sized(60, 60)) {
            if flag { Box(style: sized(20, 20)) }
            Box(style: sized(20, 20))
        }
        .background(alignment: .bottomTrailing) { ConditionalCounter("bg", reads) }
        let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1,
                          stateTable: table, reportsUnlowerableFields: true)
        frame.render(&root)
        try #require(frame.unlowerableFields.isEmpty, "flag \(flag): \(frame.unlowerableFields)")
        #expect(reads.ids["bg"] == side, "flag \(flag): \(String(describing: reads.ids["bg"]))")
        seen.append(reads.values["bg"])
    }
    #expect(seen == [1, 2, 3], "the background's own count through the flip: \(seen)")

    // The TYPED entry (`requestProposalLayout`, a proposal parent): the same
    // `-1` side under a `VStack`. Added by lane 3's mutation run (`ID-Q` item 2):
    // M3h′ — the typed copy of M3h — reddened nothing, because every other
    // background in the suite is a window root or under a legacy parent, which
    // take the untyped entry.
    let typedReads = ConditionalReads()
    var typed = VStack {
        Rectangle(width: px(40), height: px(40)).background { ProposalConditionalCounter("pbg", typedReads) }
    }
    Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1).render(&typed)
    let modifier = child(rootID, 0)
    #expect(typedReads.ids["pbg"] == child(GlobalElementID.child(of: modifier, at: -1, name: nil), 0),
            "typed entry: \(String(describing: typedReads.ids["pbg"]))")
}

// MARK: - B3.3: the named trap (divergence 73)

/// **B3.3 (exit) — a legacy background on a two-member `Component` traps
/// naming its primary count** (ruling `ID-I` item 3, divergence 73). SwiftUI
/// attaches one background per member of a `Group` (probe G3/G4); MetalUI keeps
/// a modifier one layer (`MC-A`) and names the count, as the overlay does
/// (`aLegacyOverlayOnATwoMemberComponentTrapsNamingItsPrimaryCount`).
///
/// Red before: does not compile. Mutation **M3i** (the background's attach hands
/// only the first primary node) makes the child exit 0.
@Test func aLegacyBackgroundOnATwoMemberComponentTrapsNamingItsPrimaryCount() async {
    let child = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = Box(style: sized(100, 100)) {
                TwoMembers().background { Box(style: sized(10, 10)) }
            }
            Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1).render(&root)
        }
    }
    let stderr = String(decoding: child?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("a native background modifier requires one primary node, got 2"),
            "aborted, but not naming the two-node primary count:\n\(stderr)")
}
