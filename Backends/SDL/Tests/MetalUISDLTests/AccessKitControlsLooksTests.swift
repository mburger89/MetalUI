import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import CAccessKit

// C10 lane 1 (ruling `LK-G`; spec `2026-10-08-controls-looks-design.md`
// §3.1): the three roles this branch adds, in AccessKit's vocabulary —
// `.progressIndicator` a `PROGRESS_INDICATOR` with its fraction as the
// numeric value and the range 0…1, `.busyIndicator` a `PROGRESS_INDICATOR`
// with no numeric value (`accesskit.h` 0.23 has no busy role), `.colorWell`
// a `COLOR_WELL` carrying its `rgb R G B A` string. The AppKit half is the
// root package's `ControlsLooksAccessibilityTests`.

private func nid(_ name: String) -> AccessibilityNodeID { AccessibilityNodeID(name) }

/// **1.39** (`LK-G`). The three rows on AccessKit, on the snapshot and on the
/// `accesskit_node` it is handed. Mutation: give `.busyIndicator` a numeric
/// value.
@Test func theThreeNewRolesHaveRowsOnAccessKit() throws {
    let tree = AccessibilityTree(
        roots: [nid("progress"), nid("busy"), nid("well")],
        nodes: [nid("progress"): AccessibilityNode(role: .progressIndicator, label: "Export", value: "0.5"),
                nid("busy"): AccessibilityNode(role: .busyIndicator, label: "Loading"),
                nid("well"): AccessibilityNode(role: .colorWell, value: "rgb 1 0 0 1", actions: [.press])],
        geometry: [:], focused: nil)
    let ids = AccessKitIDs()
    let snapshot = AccessKitSnapshot.translate(tree, title: "MetalUI", scale: 1, ids: ids)
    let byNumber = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
    func node(_ name: String) throws -> AccessKitSnapshot.Node {
        try #require(byNumber[ids.number(for: nid(name))], "\(name) translated")
    }

    let progress = try node("progress")
    #expect(progress.role == .progressIndicator, "\(progress.role)")
    #expect(progress.numericValue == 0.5 && progress.numericRange == true, "\(progress)")
    let busy = try node("busy")
    #expect(busy.role == .progressIndicator, "\(busy.role)")
    #expect(busy.numericValue == nil && busy.numericRange == false, "a busy indicator has no value: \(busy)")
    let well = try node("well")
    #expect(well.role == .colorWell && well.value == "rgb 1 0 0 1" && well.actions == [.click], "\(well)")

    let progressRole = accesskit_role(UInt8(ACCESSKIT_ROLE_PROGRESS_INDICATOR.rawValue))
    let c = AccessKitAdapter.cNode(progress)
    defer { accesskit_node_free(c) }
    #expect(accesskit_node_role(c) == progressRole, "PROGRESS_INDICATOR")
    let value = accesskit_node_numeric_value(c), low = accesskit_node_min_numeric_value(c),
        high = accesskit_node_max_numeric_value(c)
    #expect(value.has_value && value.value == 0.5, "the fraction")
    #expect(low.has_value && low.value == 0 && high.has_value && high.value == 1, "the range 0…1")
    let cBusy = AccessKitAdapter.cNode(busy)
    defer { accesskit_node_free(cBusy) }
    #expect(accesskit_node_role(cBusy) == progressRole, "PROGRESS_INDICATOR")
    #expect(!accesskit_node_numeric_value(cBusy).has_value && !accesskit_node_min_numeric_value(cBusy).has_value,
            "no value, no range")
    let cWell = AccessKitAdapter.cNode(well)
    defer { accesskit_node_free(cWell) }
    #expect(accesskit_node_role(cWell) == accesskit_role(UInt8(ACCESSKIT_ROLE_COLOR_WELL.rawValue)), "COLOR_WELL")
}
