import Testing
import Foundation
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit

// Plan task 12 part 2, lane 1 (spec `2026-09-29-accessibility-design.md` §6,
// rulings `IX-AA`, `IX-AD`, `IX-AF` item 6, `IX-AG`): the neutral tree's new
// roles, fields and requests through the AppKit bridge. Trees are built by
// hand, as `AppKitAccessibilityTests`' are; every answer is read through the
// NSAccessibility method a client calls. A bridge with no host view is enough
// for everything here but a root's parent, which no test reads.

private typealias Request = MetalUIPlatform.AccessibilityRequest

private func nid(_ name: String) -> AccessibilityNodeID { AccessibilityNodeID(name) }

private func rect(_ y: Float) -> AccessibilityGeometry {
    let frame = Bounds(origin: Point(x: Pixels(0), y: Pixels(y)), size: Size(width: Pixels(20), height: Pixels(10)))
    return AccessibilityGeometry(frame: frame, visibleFrame: frame)
}

/// A tree of `nodes` whose `roots` are listed; every node gets a distinct
/// frame.
private func tree(roots: [String], _ nodes: [String: AccessibilityNode]) -> AccessibilityTree {
    var geometry: [AccessibilityNodeID: AccessibilityGeometry] = [:]
    for (index, name) in nodes.keys.sorted().enumerated() { geometry[nid(name)] = rect(Float(index) * 10) }
    return AccessibilityTree(roots: roots.map(nid),
                             nodes: Dictionary(uniqueKeysWithValues: nodes.map { (nid($0.key), $0.value) }),
                             geometry: geometry, focused: nil)
}

@MainActor private final class Log {
    var requests: [Request] = []
}

/// A published bridge whose requests land in `log` and answer `true`.
@MainActor private func makeBridge(_ published: AccessibilityTree) -> (AppKitAccessibilityBridge, Log) {
    let bridge = AppKitAccessibilityBridge(signal: ScriptedAccessibilitySignal(true),
                                           poster: RecordingAccessibilityPoster())
    let log = Log()
    bridge.onRequest = { log.requests.append($0); return true }
    bridge.publish(published)
    log.requests.removeAll()   // the pending `.activate`
    return (bridge, log)
}

/// A single-selection list's outline: rows 0–2, row 1 selected; and a plain
/// list's table with one row (no `selection:`).
private func listTree() -> AccessibilityTree {
    tree(roots: ["outline", "plainTable"], [
        "outline": AccessibilityNode(role: .table, children: [nid("r0"), nid("r1"), nid("r2")], rowCount: 3),
        "r0": AccessibilityNode(role: .row, label: "Row 0", actions: [.press], rowIndex: 0, isSelectable: true),
        "r1": AccessibilityNode(role: .row, label: "Row 1", isSelected: true, actions: [.press], rowIndex: 1,
                                isSelectable: true),
        "r2": AccessibilityNode(role: .row, label: "Row 2", actions: [.press], rowIndex: 2, isSelectable: true),
        "plainTable": AccessibilityNode(role: .table, children: [nid("plain")], rowCount: 1),
        "plain": AccessibilityNode(role: .row, label: "Plain", rowIndex: 0),
    ])
}

private let setSelected = #selector(NSAccessibilityElement.setAccessibilitySelected(_:))
private let setSelectedRows = #selector(NSAccessibilityElement.setAccessibilitySelectedRows(_:))

/// **1.1.** A hint is `AXHelp`, an identifier `AXIdentifier`, `.heading` and
/// `.link` are `AXHeading`/`AXLink`, and a `.table` is an `AXOutline` whose
/// rows are `AXRow`s with subrole `AXOutlineRow` (SwiftUI's role, L1, R16,
/// LA0; divergence 32 amended) — its row count, rows and row indices still
/// answer. Mutations M1a (hint answered as the label) and M1a′ (`.table` back
/// to `AXTable`) must redden it.
@Test @MainActor func theAppKitBridgePublishesHintIdentifierHeadingLinkAndOutline() throws {
    let (bridge, _) = makeBridge(tree(roots: ["title", "more", "outline"], [
        "title": AccessibilityNode(role: .heading, label: "Title", hint: "The page title", identifier: "page.title"),
        "more": AccessibilityNode(role: .link, label: "More"),
        "outline": AccessibilityNode(role: .table, children: [nid("r0"), nid("r1")], rowCount: 40),
        "r0": AccessibilityNode(role: .row, label: "Row 0", rowIndex: 7),
        "r1": AccessibilityNode(role: .row, label: "Row 1", rowIndex: 8),
    ]))
    let title = bridge.element(for: nid("title"))
    let more = bridge.element(for: nid("more"))
    let outline = bridge.element(for: nid("outline"))
    let row = bridge.element(for: nid("r1"))

    #expect(title.accessibilityRole() == NSAccessibility.Role(rawValue: "AXHeading"))
    #expect(title.accessibilityLabel() == "Title", "the label stays the label")
    #expect(title.accessibilityHelp() == "The page title", "the hint is AXHelp")
    #expect(title.accessibilityIdentifier() == "page.title", "the identifier is AXIdentifier")
    #expect(more.accessibilityRole() == .link)
    #expect(more.accessibilityHelp() == nil, "control: no hint, no help")
    #expect(more.accessibilityIdentifier() == "", "control: no identifier")

    #expect(outline.accessibilityRole() == .outline, "a list is SwiftUI's AXOutline")
    #expect(row.accessibilityRole() == .row)
    #expect(row.accessibilitySubrole() == .outlineRow, "its rows are outline rows")
    #expect(title.accessibilitySubrole() == nil, "control: a heading has no subrole")
    #expect(outline.accessibilityRowCount() == 40)
    #expect((outline.accessibilityRows() ?? []).compactMap { ($0 as? AppKitAccessibilityElement)?.id }
        == [nid("r0"), nid("r1")])
    #expect(row.accessibilityIndex() == 8)
    let rows = #selector(NSAccessibilityElement.accessibilityRows)
    #expect(outline.isAccessibilitySelectorAllowed(rows), "the outline still offers its rows")
}

/// **1.2.** A node's custom actions are `NSAccessibilityCustomAction`s named
/// in published order; the i-th one's handler sends `.customAction(id, i)`
/// and answers the window's answer; a detached element publishes none.
/// Mutation M1b (handlers numbered from 1) must redden it.
@Test @MainActor func theAppKitBridgesCustomActionsRequestByIndex() throws {
    let published = tree(roots: ["mail", "plain"], [
        "mail": AccessibilityNode(role: .button, label: "Mail", actions: [.press],
                                  customActions: ["Archive", "Delete"]),
        "plain": AccessibilityNode(role: .button, label: "Plain", actions: [.press]),
    ])
    let (bridge, log) = makeBridge(published)
    let mail = bridge.element(for: nid("mail"))
    let actions = try #require(mail.accessibilityCustomActions())
    try #require(actions.count == 2)
    #expect(actions.map(\.name) == ["Archive", "Delete"])
    #expect(actions[1].handler?() == true)
    #expect(actions[0].handler?() == true)
    #expect(log.requests == [.customAction(nid("mail"), 1), .customAction(nid("mail"), 0)])
    #expect((bridge.element(for: nid("plain")).accessibilityCustomActions() ?? []).isEmpty,
            "control: a node with none publishes none")

    // Detached: the id leaves the tree.
    var smaller = published
    smaller.nodes[nid("mail")] = nil
    smaller.roots = [nid("plain")]
    smaller.geometry[nid("mail")] = nil
    bridge.publish(smaller)
    log.requests.removeAll()
    #expect((mail.accessibilityCustomActions() ?? []).isEmpty, "a detached element publishes none")
    #expect(actions[0].handler?() == false, "a held handler of a detached element sends nothing")
    #expect(log.requests.isEmpty)
}

/// **1.3.** A selectable row accepts `setAccessibilitySelected(true)` as
/// `.select(row)`; `(false)` sends nothing; a row that is not selectable
/// neither allows the setter nor sends anything; the outline accepts
/// `setAccessibilitySelectedRows(_:)` as `.selectRows(outline, rows)` and
/// answers `accessibilitySelectedRows()` with its selected rows (`IX-AA`,
/// LA2–LB3). Mutation M1c (the setter allowed on every row) must redden it.
@Test @MainActor func anOutlineRowAcceptsAXSelectedOnlyWhenSelectable() throws {
    let (bridge, log) = makeBridge(listTree())
    let outline = bridge.element(for: nid("outline"))
    let r0 = bridge.element(for: nid("r0"))
    let r2 = bridge.element(for: nid("r2"))
    let plain = bridge.element(for: nid("plain"))
    let plainTable = bridge.element(for: nid("plainTable"))

    #expect(r0.isAccessibilitySelectorAllowed(setSelected), "a selectable row allows AXSelected")
    r0.setAccessibilitySelected(true)
    #expect(log.requests == [.select(nid("r0"))])
    r0.setAccessibilitySelected(false)
    #expect(log.requests == [.select(nid("r0"))], "(false) sends nothing")

    #expect(!plain.isAccessibilitySelectorAllowed(setSelected), "a row of a plain list does not")
    plain.setAccessibilitySelected(true)
    #expect(log.requests.count == 1, "and sends nothing")

    #expect(outline.isAccessibilitySelectorAllowed(setSelectedRows), "the outline allows AXSelectedRows")
    #expect(!plainTable.isAccessibilitySelectorAllowed(setSelectedRows), "a plain list's does not")
    outline.setAccessibilitySelectedRows([r0, r2])
    #expect(log.requests.last == .selectRows(nid("outline"), [nid("r0"), nid("r2")]))
    plainTable.setAccessibilitySelectedRows([plain])
    #expect(log.requests.count == 2, "a plain list's setter sends nothing")

    let selected = (outline.accessibilitySelectedRows() ?? []).compactMap { ($0 as? AppKitAccessibilityElement)?.id }
    #expect(selected == [nid("r1")], "the selected rows: \(selected)")
}

/// **1.4.** Every field of the neutral `AccessibilityNode` has an AppKit arm
/// (`IX-AD`): the table below must name exactly the fields a `Mirror` finds,
/// and each arm is asserted on one element built from a node with every field
/// set. Mutation M1d (the `identifier` answer dropped) must redden it.
@Test @MainActor func everyAccessibilityNodeFieldHasAnAppKitArm() throws {
    let full = AccessibilityNode(
        role: .row, label: "L", value: "V", isSelected: true, isEnabled: false, isFocusable: true,
        actions: [.press, .increment, .decrement], children: [nid("kid")], rowCount: 7, rowIndex: 3,
        hint: "H", identifier: "I", customActions: ["C"], isSelectable: true)
    let (bridge, _) = makeBridge(tree(roots: ["full"], ["full": full, "kid": AccessibilityNode(role: .staticText)]))
    let element = bridge.element(for: nid("full"))
    typealias Arm = (AppKitAccessibilityElement) -> Bool
    let arms: [String: Arm] = [
        "role": { $0.accessibilityRole() == .row },
        "label": { $0.accessibilityLabel() == "L" },
        "value": { $0.accessibilityValue() as? String == "V" },
        "isSelected": { $0.isAccessibilitySelected() },
        "isEnabled": { !$0.isAccessibilityEnabled() },
        "isFocusable": { $0.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.setAccessibilityFocused(_:))) },
        "actions": { e in
            [#selector(NSAccessibilityElement.accessibilityPerformPress),
             #selector(NSAccessibilityElement.accessibilityPerformIncrement),
             #selector(NSAccessibilityElement.accessibilityPerformDecrement)].allSatisfy(e.isAccessibilitySelectorAllowed)
        },
        "children": { ($0.accessibilityChildren() ?? []).compactMap { ($0 as? AppKitAccessibilityElement)?.id } == [nid("kid")] },
        "rowCount": { $0.accessibilityRowCount() == 7 },
        "rowIndex": { $0.accessibilityIndex() == 3 },
        "hint": { $0.accessibilityHelp() == "H" },
        "identifier": { $0.accessibilityIdentifier() == "I" },
        "customActions": { ($0.accessibilityCustomActions() ?? []).map(\.name) == ["C"] },
        "isSelectable": { $0.isAccessibilitySelectorAllowed(setSelected) },
    ]
    let fields = Set(Mirror(reflecting: full).children.compactMap(\.label))
    #expect(fields.count == 14, "the neutral node's field count: \(fields.sorted())")
    #expect(Set(arms.keys) == fields, "one arm per field — missing \(fields.subtracting(arms.keys).sorted())")
    for (field, arm) in arms.sorted(by: { $0.key < $1.key }) { #expect(arm(element), "\(field)'s arm") }

    // A focusable arm needs a separating control: a node that is not.
    let (other, _) = makeBridge(tree(roots: ["n"], ["n": AccessibilityNode(role: .button)]))
    #expect(!other.element(for: nid("n"))
        .isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.setAccessibilityFocused(_:))),
            "control: a node that is not focusable does not allow AXFocused")
}

/// **1.9.** Every override lane 1 adds answers nothing off the main thread and
/// the process survives (`AB-AE`, `IX-AF` item 6); on the main thread each
/// answers (the control, in the same child process). An exit test, because
/// the failure is a trap. Mutation M1i (`accessibilityHelp` through a bare
/// `MainActor.assumeIsolated`) must redden it.
@Test func theNewAppKitOverridesAnswerNothingOffTheMainThread() async {
    await #expect(processExitsWith: .success) {
        let held = await MainActor.run { () -> MainThreadAnswer<(AppKitAccessibilityElement, AppKitAccessibilityElement, AppKitAccessibilityBridge, Log)> in
            var published = listTree()
            published.nodes[nid("r0")]!.hint = "help"
            published.nodes[nid("r0")]!.identifier = "ident"
            published.nodes[nid("r0")]!.customActions = ["One", "Two"]
            let (bridge, log) = makeBridge(published)
            let row = bridge.element(for: nid("r0"))
            let outline = bridge.element(for: nid("outline"))
            // The control: on the main thread each answers.
            precondition(row.accessibilityHelp() == "help")
            precondition(row.accessibilityIdentifier() == "ident")
            precondition(row.accessibilityCustomActions()?.count == 2)
            precondition(row.accessibilityCustomActions()?[1].handler?() == true)
            row.setAccessibilitySelected(true)
            outline.setAccessibilitySelectedRows([row])
            precondition(outline.accessibilitySelectedRows()?.count == 1)
            precondition(log.requests == [.customAction(nid("r0"), 1), .select(nid("r0")),
                                          .selectRows(nid("outline"), [nid("r0")])])
            log.requests.removeAll()
            return MainThreadAnswer(value: (row, outline, bridge, log))
        }
        let handler = await MainActor.run { MainThreadAnswer(value: held.value.0.accessibilityCustomActions()?[0].handler) }
        let offMain = await Task.detached { () -> [String] in
            let (row, outline) = (held.value.0, held.value.1)
            var wrong: [String] = []
            if pthread_main_np() != 0 { wrong.append("ran on the main thread") }
            if row.accessibilityHelp() != nil { wrong.append("help") }
            if row.accessibilityIdentifier() != "" { wrong.append("identifier") }
            if !(row.accessibilityCustomActions() ?? []).isEmpty { wrong.append("customActions") }
            if handler.value?() != false { wrong.append("a held custom action's handler") }
            row.setAccessibilitySelected(true)
            outline.setAccessibilitySelectedRows([row])
            if !(outline.accessibilitySelectedRows() ?? []).isEmpty { wrong.append("selectedRows") }
            if row.isAccessibilitySelectorAllowed(setSelected) { wrong.append("the setter allowed") }
            return wrong
        }.value
        precondition(offMain.isEmpty, "answered off the main thread: \(offMain)")
        let sent = await MainActor.run { held.value.3.requests.map { "\($0)" } }
        precondition(sent.isEmpty, "nothing sent off the main thread: \(sent)")
    }
}
