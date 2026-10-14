import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUITesting
@testable import MetalUI

// C14b-2 lane 1 (`RK-O` item 1): what only the internal view can see of a prepaint ledger.

/// Whether a value, or any stored field under it to `depth`, has the type `LayoutNodeID`, found by the **declared type** of
/// each field (so an empty array of ids counts). A `Mirror` cannot see what a closure captured: that is the replayed-handler
/// differential's (`aReplayedHandlerActsLikeAFreshOne`) and verify mode's, not this scan's.
func mentionsLayoutNodeID(_ value: Any, depth: Int = 6) -> Bool {
    if String(describing: type(of: value)).contains("LayoutNodeID") { return true }
    guard depth > 0 else { return false }
    for child in Mirror(reflecting: value).children where mentionsLayoutNodeID(child.value, depth: depth - 1) { return true }
    return false
}

/// A card with a button (a hitbox, a focus stop, an accessibility record), a context menu and text.
private struct LedgerCard: Component, @MainActor Equatable {
    let title: String
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text(title).frame(width: Pixels(80), height: Pixels(14))
            Button("go \(title)") {}.frame(width: Pixels(50), height: Pixels(18))
                .contextMenu { Button("menu \(title)") {} }
        }
    }
    static func == (l: LedgerCard, r: LedgerCard) -> Bool { l.title == r.title }
}

/// A fixture type holding a layout node id: the instrument's separating arm.
private struct HoldsALayoutNodeID { var ids: [LayoutNodeID] = [] }

/// 9a — **no recorded hitbox, accessibility record or ledger field stores a `LayoutNodeID`** (`RK-O` item 1): a replayed
/// record outlives its frame's `LayoutTree` generation (`C-3`), so an id in it would trap in `slot(_:)`. Scans every stored
/// field of every ledger a window made over a tree with hitboxes, context menus, focus stops and accessibility records.
/// The scan must see the fixture that holds one (the arm below). Mutation: a `LayoutNodeID` field added to `Hitbox` or to
/// `PrepaintLedger` reddens this test; the fixture arm proves the scan can.
@Test @MainActor func noRecordedHitboxStoresALayoutNodeID() throws {
    #expect(mentionsLayoutNodeID(HoldsALayoutNodeID()), "the instrument sees a declared id field, empty or not")
    let window = try TestWindow(size: Size(width: Pixels(300), height: Pixels(160))) {
        VStack(spacing: 4) {
            LedgerCard(title: "A").equatable()
            LedgerCard(title: "B").equatable()
        }
    }
    _ = try window.accessibilityTree
    for _ in 0..<5 { window.window.setNeedsRedraw(); window.tick() }
    var ledgers = 0
    let found = window.window.testingStoredPrepaintLedgers { ledger in
        ledgers += 1
        #expect(!mentionsLayoutNodeID(ledger), "the ledger, every stored field of it and of what it holds")
        #expect(!mentionsLayoutNodeID(ledger.hitboxes), "hitboxes")
    }
    try #require(found >= 2 && ledgers == found, "both cards left a ledger: \(found)")
    var withHitboxes = 0
    window.window.testingStoredPrepaintLedgers { ledger in if !ledger.hitboxes.isEmpty { withHitboxes += 1 } }
    #expect(withHitboxes >= 2, "each card's ledger holds its button's hitboxes: \(withHitboxes)")
}
