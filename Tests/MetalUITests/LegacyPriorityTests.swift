import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Spec `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md` §4.2,
// tests 2.1–2.5 (ruling `MD-G` in
// `docs/superpowers/2026-10-07-port-gaps-medium-decisions.md`): a legacy
// container sees through a `layoutPriority` layer — the layer forwards its
// content's `LoweredItem` record, the container plans the content's wrappers
// around the layer, aliases the content's element node to the item frame, and
// lifts the priority outermost so the kernel still reads it.
//
// Ids: the harness's `DifferentialRoot` is `[0]`, the container `[0, 0]`, a
// priority layer `[0, 0, i]` and its content `[0, 0, i, 0]` (`MC-C`).

private func id(_ path: Int...) -> GlobalElementID { controlID(path) }

/// The `Text` widths the rows below are derived from, measured in-test.
@MainActor
private func textWidth(_ string: String) throws -> Float {
    try controlTextSize(string).width.value
}

// MARK: - 2.1 stretch

/// **2.1** (`MD-G` items 1, 2, 4; spec §1.2 row 2). `Box { Text("hi")
/// .layoutPriority(1); Text("other") }` 300 × 100 (a row; `Box` stretches,
/// `EP-8`): the prioritised `hi` is stretched to the box's 100 like its
/// unprioritised sibling — its element bounds through the alias — and nothing
/// is reported.
///
/// Red before: `hi` is 11 × 16 (the stretch lost silently). M2.1a (no
/// forwarding) and M2.1b (alias the layer node instead of the origin) each
/// redden it.
@Test @MainActor func aPrioritisedLegacyChildKeepsItsParentsStretch() throws {
    let report = LayoutDifferential.report(width: 300, height: 100) {
        Box {
            Text("hi").layoutPriority(1)
            Text("other")
        }.cssWidth(Pixels(300)).cssHeight(Pixels(100))
    }
    try #require(report.unlowerable.isEmpty, "\(report.unlowerable.map(\.description))")
    let hi = try #require(report.bounds[id(0, 0, 0, 0)], "the prioritised Text")
    let other = try #require(report.bounds[id(0, 0, 1)], "the sibling")
    let hiWidth = try textWidth("hi")
    #expect(other.size.height.value == 100, "set up — the unprioritised sibling is stretched: \(other)")
    #expect(hi.size.height.value == 100 && close(hi.size.width.value, hiWidth),
            "M2.1 — the prioritised Text is stretched too: \(hi)")
}

private func close(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 0.01 }

// MARK: - 2.2 an item field under the layer

/// **2.2** (`MD-G` items 1, 2; spec §1.2 row 3). `Row { Text("a").flexGrow(1)
/// .layoutPriority(1); Box().cssWidth(40) }` 300 wide: the grower's field is
/// lowered by the row through the layer — nothing reported — and `a` takes the
/// row less the 40-point sibling (`Row`'s gap is 0, divergence 52). (The
/// sibling is a fixed box, not the spec's `Text("b")`: a prioritised greedy
/// grower is served first and leaves a `Text` its zero-offer answer, 0, so a
/// `Text` sibling would not separate a grown `a` from one that is not.)
///
/// Red before: `text.flexGrow.unconsumed`. M2.1a reddens it.
@Test @MainActor func aLegacyItemFieldUnderALayoutPriorityIsLoweredNotReported() throws {
    let report = LayoutDifferential.report(width: 300, height: 100) {
        Row {
            Text("a").flexGrow(1).layoutPriority(1)
            Box().cssWidth(Pixels(40)).cssHeight(Pixels(10))
        }.cssWidth(Pixels(300))
    }
    #expect(report.unlowerable.isEmpty, "M2.1a — nothing reported: \(report.unlowerable.map(\.description))")
    let a = try #require(report.bounds[id(0, 0, 0, 0)], "the grower")
    let b = try #require(report.bounds[id(0, 0, 1)], "the sibling")
    #expect(b.size.width.value == 40, "the sibling keeps its 40: \(b)")
    #expect(a.size.width.value == 260 && a.origin.x.value == 0, "a grows to 300 − 40: \(a)")
}

// MARK: - 2.3 the lift

/// **2.3** (`MD-G` item 3). A `Column` 800 tall, gap 16: child A
/// `.frame(minHeight: 240, maxHeight: .infinity)`; child B a `Box` growing
/// (`.flexGrow(1)`, so an item frame wraps it) between a 260 minimum and a 530
/// maximum, `.layoutPriority(1)`. The lifted priority serves B first: B 530,
/// A 800 − 16 − 530 = 254. Without the lift the item frame hides the priority
/// and the two greedy children split 784 evenly (392 / 392).
///
/// Red before: B's record is not consumed — `box.flexGrow`, `box.minSize`,
/// `box.maxSize` `.unconsumed`. M2.3 (the lift not registered) → 392 / 392.
@Test @MainActor func thePriorityIsLiftedAboveTheItemWrappers() throws {
    let report = LayoutDifferential.report(width: 300, height: 800) {
        Column(gap: Pixels(16)) {
            Box {}.frame(minHeight: 240, maxHeight: .infinity)
            Box {}.cssMinHeight(Pixels(260)).cssMaxHeight(Pixels(530)).flexGrow(1).layoutPriority(1)
        }.cssHeight(Pixels(800))
    }
    try #require(report.unlowerable.isEmpty, "\(report.unlowerable.map(\.description))")
    let a = try #require(report.bounds[id(0, 0, 0)], "child A's frame")
    let b = try #require(report.bounds[id(0, 0, 1, 0)], "child B")
    #expect(b.size.height.value == 530 && a.size.height.value == 254,
            "M2.3 — B served first: B \(b.size.height.value), A \(a.size.height.value)")
}

// MARK: - 2.4 the port's own scenario

/// **2.4** (`MD-A`; spec §1.2 row 1, the SMK configurator's drawer, MG-14).
/// `Column(gap: 16) { greedy.frame(minHeight: 240, maxHeight: .infinity);
/// drawer.frame(minHeight: 260, maxHeight: 530).layoutPriority(1) }` at 300 ×
/// 800: the drawer 530, the greedy board 254.
///
/// **Green before** (`PE-F` already served it — a pin of the port's scenario).
/// `PE-F`'s M1.20 (the layer dropped) → 392 / 392.
@Test @MainActor func theMG14DrawerReachesItsMaximum() throws {
    let report = LayoutDifferential.report(width: 300, height: 800) {
        Column(gap: Pixels(16)) {
            Box {}.frame(minHeight: 240, maxHeight: .infinity)
            Box {}.frame(minHeight: 260, maxHeight: 530).layoutPriority(1)
        }.cssHeight(Pixels(800))
    }
    try #require(report.unlowerable.isEmpty, "\(report.unlowerable.map(\.description))")
    let board = try #require(report.bounds[id(0, 0, 0)], "the board's frame")
    let drawer = try #require(report.bounds[id(0, 0, 1, 0)], "the drawer's frame")
    #expect(drawer.size.height.value == 530 && board.size.height.value == 254,
            "drawer \(drawer.size.height.value), board \(board.size.height.value)")
}

// MARK: - 2.5 a proposal container still reports

/// **2.5** (`MD-G` item 5; `PE-C` item 4). In a proposal container the
/// forwarded record is consumed by nobody and reported at its original site
/// under its original name, once: `HStack { Text("a").flexGrow(1)
/// .layoutPriority(1) }` → `text.flexGrow.unconsumed`.
///
/// Green before (`PE-C` item 4). M2.5 (a forwarded record marked consumed on
/// forwarding) reddens it.
@Test @MainActor func aPriorityLayerInAProposalStackStillReportsItsContentsItemField() throws {
    let report = LayoutDifferential.report(width: 300, height: 100) {
        HStack { Text("a").flexGrow(1).layoutPriority(1) }
    }
    #expect(report.unlowerable.map(\.description) == ["text.flexGrow.unconsumed"],
            "M2.5 — reported once, by its original name: \(report.unlowerable.map(\.description))")
}
