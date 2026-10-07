import Testing
import AppKit
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI
import MetalUIDemoContent

// Plan task 12 part 2, lane 3 (spec `2026-09-29-accessibility-design.md` §7
// "Lane 3", §8, §9; rulings `IX-X` item 4, `IX-AC`, `IX-AD`, `IX-AE`): the
// audit's pins — buttons, truncation, focus, the part-1 controls — and the
// trees `docs/verification/voiceover-script.md` reads, which 3.10 checks the
// script's markers against. Every SwiftUI claim is an arm of
// `docs/probes/swiftui-accessibility-part2.swift`, named per arm; the rest is
// MetalUI's own published tree, pinned as it is. Helpers are `ButtonTests.swift`'s
// `control…` and `AccessibilityModifierTests.swift`'s `accessibilityBuild` and
// `AccessibilityTree.one(_:)`.

private typealias Request = MetalUIPlatform.AccessibilityRequest

// MARK: - Harness

@MainActor private final class AuditRunning: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(true) }
}

@MainActor private final class AuditPoster: AccessibilityNotificationPosting {
    var posts: [(NSAccessibility.Notification, AnyObject)] = []
    func post(_ notification: NSAccessibility.Notification, for element: Any) {
        posts.append((notification, element as AnyObject))
    }
}

/// An AppKit bridge over `view`, active, handing requests to `platform`.
@MainActor
private func auditBridge(_ platform: FakePlatformWindow, poster: AuditPoster = AuditPoster())
    -> (AppKitAccessibilityBridge, NSView, NSWindow) {
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                        styleMask: [.titled], backing: .buffered, defer: true)
    host.isReleasedWhenClosed = false
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    host.contentView = view
    let bridge = AppKitAccessibilityBridge(signal: AuditRunning(), poster: poster)
    bridge.onRequest = { platform.simulateAccessibilityRequest($0) }
    bridge.hostView = view
    return (bridge, view, host)
}

/// Draws until the window asks for nothing more (at most eight frames).
@MainActor
private func auditSettle(_ window: Window) {
    var frames = 0
    window.setNeedsRedraw()
    while window.needsRedraw && frames < 8 {
        window.drawFrameIfNeeded()
        frames += 1
    }
}

/// A demo window as `MetalUIDemo` opens it — 920 × 560 (`main.swift`) — with
/// an accessibility client active and the window settled.
///
/// **Pre-flighted** (`PE-Z`): a `Window` builds production frames, where a
/// reported field traps and ends the run with no summary line, so the same
/// content first renders with diagnostics and must report nothing. The
/// controls demo holds a SwiftUI-vocabulary section since `PE-Y`, where a
/// legacy item field is reported (`PE-C` item 4); without this, lane 3's M3.1
/// trapped inside `theControlsDemoPublishesTheTreeTheVoiceOverScriptReads`.
@MainActor
private func scriptWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let preflight = LayoutDifferential.render(width: 920, height: 560) { content() }
    try #require(preflight.unlowerableFields.isEmpty,
                 "this demo would trap in a production window: \(preflight.unlowerableFields)")
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 920, content: content)
    platform.simulateResize(to: Size(width: Pixels(920), height: Pixels(560)))
    window.drawFrameIfNeeded()
    platform.simulateAccessibilityRequest(.activate)
    auditSettle(window)
    return (window, platform)
}

@MainActor
private func published(_ platform: FakePlatformWindow) throws -> AccessibilityTree {
    try #require(platform.publishedAccessibilityTrees.last, "no tree published")
}

/// Sends `request`, requires it handled, and settles.
@MainActor
private func send(_ request: Request, _ window: Window, _ platform: FakePlatformWindow,
                  sourceLocation: SourceLocation = #_sourceLocation) throws {
    let handled = platform.simulateAccessibilityRequest(request)
    try #require(handled, "\(request) was refused", sourceLocation: sourceLocation)
    auditSettle(window)
}

/// One node's facts, as a table row.
private struct AuditNode: Equatable, CustomStringConvertible {
    var role: AccessibilityRole
    var label: String?
    var value: String?
    var selected = false
    var actions: AccessibilityActions = []

    init(_ role: AccessibilityRole, label: String? = nil, value: String? = nil, selected: Bool = false,
         actions: AccessibilityActions = []) {
        self.role = role
        self.label = label
        self.value = value
        self.selected = selected
        self.actions = actions
    }

    init(_ node: AccessibilityNode) {
        self.init(node.role, label: node.label, value: node.value, selected: node.isSelected,
                  actions: node.actions)
    }

    var description: String {
        "\(role) label=\(label ?? "-") value=\(value ?? "-") selected=\(selected) actions=\(actions.rawValue)"
    }
}

extension AccessibilityTree {
    /// Every published node in reading order, as table rows.
    fileprivate var auditRows: [AuditNode] { readingOrder.compactMap { nodes[$0].map(AuditNode.init) } }
}

// MARK: - The script's trees (3.8, 3.9, 3.11)

/// The demo's counter in the order the script walks the main window.
@MainActor
private func demoTrees() throws -> [String: AccessibilityTree] {
    demoModel.showModal = false
    demoModel.animationDemoActive = false
    defer { demoModel.showModal = false }
    let (window, platform) = try scriptWindow { demoContent() }
    var trees: [String: AccessibilityTree] = [:]
    let demo = try published(platform)
    trees["demo"] = demo
    try send(.press(try demo.one("Increment").id), window, platform)
    trees["demo-incremented"] = try published(platform)
    demoModel.showModal = true
    auditSettle(window)
    trees["demo-modal"] = try published(platform)
    return trees
}

@MainActor
private func controlsTrees() throws -> [String: AccessibilityTree] {
    let (window, platform) = try scriptWindow { controlsDemoContent() }
    var trees: [String: AccessibilityTree] = [:]
    let controls = try published(platform)
    trees["controls"] = controls
    try send(.press(try controls.one("Press me").id), window, platform)
    trees["controls-pressed"] = try published(platform)
    try send(.increment(try controls.one("0.4").id), window, platform)
    trees["controls-slider-up"] = try published(platform)
    func row(_ index: Int) throws -> AccessibilityNodeID {
        try #require(try published(platform).nodes.first { entry in
            entry.value.role == .row && entry.value.rowIndex == index
        }?.key, "a realized row \(index)")
    }
    try send(.press(try row(4)), window, platform)
    trees["controls-row-pressed"] = try published(platform)
    try send(.select(try row(5)), window, platform)
    trees["controls-row-selected"] = try published(platform)
    return trees
}

@MainActor
private func previewAndTextInputTrees() throws -> [String: AccessibilityTree] {
    var trees: [String: AccessibilityTree] = [:]
    let (_, previewPlatform) = try scriptWindow { nativeLayoutPreviewContent() }
    // An empty tree publishes nothing (`Window` starts from `.empty`), so a
    // preview that records nothing reads as `.empty` here rather than stopping
    // the test before the text-input arm (M3k must redden only the preview).
    trees["preview"] = previewPlatform.publishedAccessibilityTrees.last ?? .empty
    let (window, platform) = try scriptWindow { textInputDemoContent() }
    let textInput = try published(platform)
    trees["textinput"] = textInput
    try send(.focus(try textInput.one("Type here: an input method, a selection, copy and paste").id),
             window, platform)
    trees["textinput-focused"] = try published(platform)
    return trees
}

// MARK: - 3.1 buttons (`IX-AC` item 1)

/// **3.1.** A button's role, keyboard shortcut and style publish nothing but
/// its label and press (B1 `.destructive`, B2 `.cancel`, B3 ⌘S, B4
/// `.defaultAction`, B5 `.plain`): each exactly `.button`, its label, no value,
/// hint, identifier or custom action, `[.press]` — and AppKit's element
/// answers no help (C2: `NSButton` publishes no shortcut either). Mutation M3a
/// (the shortcut published as the hint) must redden it.
@Test @MainActor func aButtonsRoleShortcutAndStylePublishOnlyItsLabel() throws {
    let (window, platform) = try controlWindow(size: 400) {
        Column {
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
            Button("Save") {}.keyboardShortcut("s")
            Button("OK") {}.keyboardShortcut(.defaultAction)
            Button("Plain") {}.buttonStyle(.plain)
        }
    }
    let tree = try controlTree(window, platform)
    let (bridge, _, _) = auditBridge(platform)
    bridge.publish(tree)
    for (arm, label) in [("B1", "Delete"), ("B2", "Cancel"), ("B3", "Save"), ("B4", "OK"), ("B5", "Plain")] {
        let (id, node) = try tree.one(label)
        #expect(node.role == .button && node.label == label && node.value == nil, "\(arm): \(node)")
        #expect(node.hint == nil && node.identifier == nil && node.customActions.isEmpty, "\(arm): \(node)")
        #expect(node.actions == [.press] && node.children.isEmpty, "\(arm): \(node)")
        let element = bridge.element(for: id)
        #expect(element.accessibilityHelp() == nil, "\(arm): AppKit publishes no help (C2)")
        #expect(element.accessibilityRole() == .button, "\(arm)")
    }
    #expect(tree.nodes.count == 5, "five nodes, nothing else: \(tree.readings)")
}

// MARK: - 3.2 truncation (`IX-AC` item 2)

/// **3.2.** A truncated or line-limited text publishes its whole string (X1
/// `.lineLimit(1)` at width 60, X2 `.truncationMode(.head)`, X3 two lines, X4
/// a `Button` label), on a legacy `Text` and a `ProposalText`. The control arm
/// of each: the drawn text IS cut — its box is one (or two) line(s) tall where
/// the unlimited text at the same width is taller. Mutation M3b
/// (`Text.prepaint` passes its drawn line) must redden it.
@Test @MainActor func aTruncatedTextPublishesItsWholeString() throws {
    let whole = "The quick brown fox jumps over the lazy dog"
    func height(_ tree: AccessibilityTree, _ id: AccessibilityNodeID) throws -> Float {
        try #require(tree.geometry[id], "no geometry").frame.size.height.value
    }

    let (_, legacy) = try accessibilityBuild(controlRoot(height: 400) {
        Column(gap: Pixels(4)) {
            Text(whole).accessibilityIdentifier("x0").frame(width: 60)
            Text(whole).accessibilityIdentifier("x1").lineLimit(1).frame(width: 60)
            Text(whole).accessibilityIdentifier("x2").lineLimit(1).truncationMode(.head).frame(width: 60)
            Text(whole).accessibilityIdentifier("x3").lineLimit(2).frame(width: 60)
            Button { } label: { Text(whole).lineLimit(1) }.frame(width: 60)
        }
    })
    let byIdentifier = Dictionary(uniqueKeysWithValues: legacy.tree.nodes.compactMap { entry in
        entry.value.identifier.map { ($0, entry) }
    })
    let unlimited = try #require(byIdentifier["x0"], "the unlimited control")
    for arm in ["x1", "x2", "x3"] {
        let (id, node) = try #require(byIdentifier[arm], "\(arm) published")
        #expect(node.role == .staticText && node.value == whole, "\(arm.uppercased()): the whole string: \(node)")
        #expect(try height(legacy.tree, id) < height(legacy.tree, unlimited.key),
                "\(arm.uppercased()) control: the drawn text is cut")
    }
    let x4 = try #require(legacy.tree.nodes.values.first { $0.role == .button }, "X4: a button")
    #expect(x4.label == whole && x4.actions == [.press], "X4: the button's label is the whole string: \(x4)")

    let (_, proposal) = try accessibilityBuild(
        VStack(alignment: .leading, spacing: Pixels(4)) {
            Text(whole).proposalLayout().frame(width: Pixels(60))
            Text(whole).proposalLayout().lineLimit(1).frame(width: Pixels(60))
            Text(whole).proposalLayout().lineLimit(1).truncationMode(.head).frame(width: Pixels(60))
            Text(whole).proposalLayout().lineLimit(2).frame(width: Pixels(60))
        })
    let texts = proposal.tree.readingOrder
    try #require(texts.count == 4, "four proposal texts: \(proposal.tree.readings)")
    #expect(proposal.tree.readings == [whole, whole, whole, whole], "every proposal text is whole")
    for (index, id) in texts.enumerated().dropFirst() {
        #expect(try height(proposal.tree, id) < height(proposal.tree, texts[0]),
                "proposal X\(index) control: the drawn text is cut")
    }
}

// MARK: - 3.3–3.5 focus (`IX-AC` item 3)

private enum AuditField: Hashable { case a, b, c }

@MainActor private final class AuditFocusModel {
    var field: [AuditField?] = []
    var setField: (AuditField?) -> Void = { _ in }
    var lastField: AuditField?? { field.last }
    var name = "first"
}

/// Three labelled boxes bound to one `@FocusState`: `a` and `b` focusable,
/// `c` bound but not focusable.
private struct AuditFocusForm: Component {
    @FocusState var field: AuditField?
    let model: AuditFocusModel

    var content: some ElementGroup {
        let _ = model.field.append(field)
        let _ = model.setField = { [field = $field] in field.wrappedValue = $0 }
        Box().frame(width: Pixels(20), height: Pixels(20)).focusable().focused($field, equals: .a)
            .accessibilityLabel("A")
        Box().frame(width: Pixels(20), height: Pixels(20)).focusable().focused($field, equals: .b)
            .accessibilityLabel("B")
        Box().frame(width: Pixels(20), height: Pixels(20)).focused($field, equals: .c)
            .accessibilityLabel("C")
    }
}

/// **3.3.** An accessibility focus request writes the `@FocusState` bound to
/// its element (F2; arm 13): `.focus(B)` → window focus on `B`, and on the next
/// frame the state reads `.b`. A request for the bound but non-focusable `C`
/// is refused and the state is unchanged. Mutation M3c (`reconcileFocusStates`
/// skipped after a request) must redden it.
@Test @MainActor func anAccessibilityFocusRequestWritesAFocusStateBinding() throws {
    let model = AuditFocusModel()
    let (window, platform) = try controlWindow(size: 200) { Row { AuditFocusForm(model: model) } }
    let tree = try controlTree(window, platform)
    try #require(model.lastField == .some(nil), "set up: nothing focused")
    let b = try tree.one("B")
    let bID = try #require(b.id.base as? GlobalElementID)
    #expect(b.node.isFocusable, "B is focusable")

    try send(.focus(b.id), window, platform)
    #expect(window.focusedElement == bID, "F2: the request focuses B")
    #expect(model.lastField == .some(.b), "F2: the @FocusState reads .b: \(model.field.suffix(3))")

    let c = try tree.one("C")
    #expect(!c.node.isFocusable, "C is not focusable")
    #expect(!platform.simulateAccessibilityRequest(.focus(c.id)), "a non-focusable element's request is refused")
    auditSettle(window)
    #expect(window.focusedElement == bID && model.lastField == .some(.b), "the state is unchanged")
}

/// **3.4.** A `@FocusState` write from input is the tree's focused element
/// (F1): `field = .b` → the published `focused` is `B`'s id, and AppKit's
/// focused element is `B`'s element (the host view's
/// `accessibilityFocusedUIElement` answers the bridge's `focusedElement()`).
/// Mutation M3d (the builder publishes the frame's handed-in focus) must
/// redden it.
@Test @MainActor func aFocusStateWriteIsTheTreesFocusedElement() throws {
    let model = AuditFocusModel()
    let (window, platform) = try controlWindow(size: 200) { Row { AuditFocusForm(model: model) } }
    let before = try controlTree(window, platform)
    #expect(before.focused == nil, "set up: nothing focused")
    model.setField(.b)
    auditSettle(window)
    let tree = try published(platform)
    let b = try tree.one("B")
    #expect(tree.focused == b.id, "F1: the tree's focus is B: \(String(describing: tree.focused))")
    let (bridge, _, _) = auditBridge(platform)
    bridge.publish(tree)
    let focused = try #require(bridge.focusedElement() as AnyObject?, "AppKit answers a focused element")
    let bElement: AnyObject = bridge.element(for: b.id)
    let isB = focused === bElement
    #expect(isB, "AppKit's focused element is B's")
}

/// A focusable, labelled box whose `.id` is the model's name.
private struct AuditRenamed: Component {
    let model: AuditFocusModel
    var content: some ElementGroup {
        Box().frame(width: Pixels(20), height: Pixels(20)).focusable().accessibilityLabel("F").id(model.name)
    }
}

/// **3.5.** Focus leaves the tree with its identity (`IX-I`): a focused box
/// renamed by `.id` publishes `focused == nil` the next frame, and AppKit posts
/// `.focusedUIElementChanged` on the host view. Mutation M3e (`IX-I`'s focus
/// reset removed, restoring `ID-R` item 9) must redden it.
@Test @MainActor func focusLeavesTheTreeWithItsIdentityAfterARename() throws {
    let model = AuditFocusModel()
    let (window, platform) = try controlWindow(size: 200) { Row { AuditRenamed(model: model) } }
    let tree = try controlTree(window, platform)
    let f = try tree.one("F")
    try send(.focus(f.id), window, platform)
    let focusedTree = try published(platform)
    try #require(focusedTree.focused == f.id, "set up: F is focused")

    let poster = AuditPoster()
    let (bridge, view, _) = auditBridge(platform, poster: poster)
    bridge.publish(focusedTree)
    poster.posts.removeAll()

    model.name = "second"
    auditSettle(window)
    let renamed = try published(platform)
    #expect(renamed.focused == nil, "IX-I: focus left with the old identity")
    #expect(window.focusedElement == nil, "and the window's focus is clear")
    #expect(try renamed.one("F").id != f.id, "control: F is published under its new identity")
    bridge.publish(renamed)
    let focusPosts = poster.posts.filter { $0.0 == .focusedUIElementChanged }
    let onHost = focusPosts.count == 1 && focusPosts[0].1 === (view as AnyObject)
    #expect(onHost,
            "AppKit posts .focusedUIElementChanged once, on the host: \(poster.posts.map(\.0))")
}

// MARK: - 3.6 the part-1 controls (`IX-AD`)

private enum AuditFormField: Hashable { case name }

private struct AuditControls: Component {
    @FocusState var field: AuditFormField?

    var content: some ElementGroup {
        Button("Go") {}
        Button("Flat") {}.buttonStyle(.plain)
        Toggle("Wi-Fi", isOn: .constant(true))
        Slider(value: .constant(0.4), in: 0...1)
        Stepper("Quantity 2", value: .constant(2), in: 0...10)
        Picker("Flavor", selection: .constant(1)) { Text("Vanilla").tag(0); Text("Chocolate").tag(1) }
        Picker("Size", selection: .constant(0)) { Text("Small").tag(0); Text("Large").tag(1) }
            .pickerStyle(.radioGroup)
        TextField("Search", text: .constant("abc"))
        TextEditor("Notes", text: .constant("line"))
            .frame(height: Pixels(40))
        Text("Tap me").onTapGesture {}
        TextField("Name", text: .constant("")).focused($field, equals: .name)
    }
}

/// **3.6.** Every part-1 control publishes its role, label, value and actions,
/// one table: `Button`, a `.plain` button, `Toggle`, `Slider`, `Stepper`, both
/// `Picker` styles, `TextField`, `TextEditor`, a `TapGesture` target (no press,
/// G1), a `.focused` field — and a selectable `List` row. Mutation M3f
/// (`Toggle`'s value `"1"` → `"true"`) must redden it.
@Test @MainActor func everyPartOneControlPublishesItsRoleLabelValueAndActions() throws {
    let (window, platform) = try controlWindow(size: 900) {
        Column(gap: Pixels(6)) { AuditControls() }.alignItems(.flexStart)
    }
    let tree = try controlTree(window, platform)
    let press: AccessibilityActions = [.press], adjust: AccessibilityActions = [.increment, .decrement]
    let expected: [(String, AuditNode)] = [
        ("Go", AuditNode(.button, label: "Go", actions: press)),
        ("Flat", AuditNode(.button, label: "Flat", actions: press)),
        ("Wi-Fi", AuditNode(.checkBox, label: "Wi-Fi", value: "1", actions: press)),
        ("0.4", AuditNode(.slider, value: "0.4", actions: adjust)),
        ("Quantity 2", AuditNode(.incrementor, label: "Quantity 2", value: "2", actions: adjust)),
        ("Flavor", AuditNode(.radioGroup, label: "Flavor")),
        ("Vanilla", AuditNode(.radioButton, label: "Vanilla", value: "0", actions: press)),
        ("Chocolate", AuditNode(.radioButton, label: "Chocolate", value: "1", selected: true, actions: press)),
        ("Size", AuditNode(.radioGroup, label: "Size")),
        ("Small", AuditNode(.radioButton, label: "Small", value: "1", selected: true, actions: press)),
        ("Large", AuditNode(.radioButton, label: "Large", value: "0", actions: press)),
        ("Search", AuditNode(.textField, label: "Search", value: "abc")),
        ("Notes", AuditNode(.textArea, label: "Notes", value: "line")),
        ("Tap me", AuditNode(.staticText, value: "Tap me")),
        ("Name", AuditNode(.textField, label: "Name", value: "")),
    ]
    for (reading, row) in expected {
        let node = try tree.one(reading).node
        #expect(AuditNode(node) == row, "\(reading): \(AuditNode(node)) vs \(row)")
    }
    for focusable in ["Go", "Flat", "Wi-Fi", "0.4", "Quantity 2", "Flavor", "Size", "Search", "Notes", "Name"] {
        #expect(try tree.one(focusable).node.isFocusable, "\(focusable) is focusable")
    }
    #expect(try !tree.one("Tap me").node.isFocusable, "G1: a tap target is not focusable")

    // A selectable row, bounded in a scroller.
    let (listWindow, listPlatform) = try controlWindow(size: 200) {
        Box(style: auditColumn(width: 200, height: 100)) {
            ScrollView {
                List((0..<10).map(AuditRow.init), selection: .constant(Set([1])), rowHeight: controlPx(20)) {
                    Text("Row \($0.id)")
                }
            }
        }
    }
    auditSettle(listWindow)
    let listTree = try controlTree(listWindow, listPlatform)
    let table = try #require(listTree.nodes.values.first { $0.role == .table }, "a table")
    #expect(table.rowCount == 10, "the table's logical count")
    let rows = table.children.compactMap { listTree.nodes[$0] }
    try #require(rows.count >= 2, "realized rows: \(rows.count)")
    #expect(rows.allSatisfy { $0.role == .row && $0.isSelectable && $0.actions == press },
            "each row: .row, selectable, [.press]")
    #expect(rows.filter(\.isSelected).map(\.rowIndex) == [1], "row 1 is selected")
}

private struct AuditRow: Identifiable { var id: Int }

private func auditColumn(width: Float, height: Float) -> Style {
    var style = Style()
    style.flexDirection = .column
    style.size.width = .length(.pixels(controlPx(width)))
    style.size.height = .length(.pixels(controlPx(height)))
    style.flexShrink = 0
    return style
}

// MARK: - 3.8 the demo (`IX-X` item 4)

private let modalText = "Modal, Declared inside the list, painted over it, and clipped by the window rather than by the scroller."

/// **3.8.** The demo's tree, as the script reads it. Modal off: the sidebar
/// and panel texts, the counter group holding `Decrement`, `Count 0`,
/// `Increment`, then the `List`'s table (500 rows, rows realized from 0).
/// Modal on (`IX-X` item 4): **only** the scrim — a button, `Close modal` — is
/// a root, holding one `.group` (the panel, `.isButton` removed: its folded
/// label and its press stay, T3p) and nothing behind the scrim;
/// `isolatedOut == true`, and a press on an element the client held from
/// before the modal is refused (divergence 95). Mutation M3h (the demo's
/// `.isModal` removed) must redden it.
@Test @MainActor func theDemoPublishesTheTreeTheVoiceOverScriptReads() throws {
    let trees = try demoTrees()
    let demo = try #require(trees["demo"])
    let top = demo.readings.prefix(7)
    #expect(Array(top) == ["Library", "3", "Decrement", "Count 0", "Increment", "Text renders",
                           demo.readings[6]], "modal off: \(Array(top))")
    let counter = try #require(demo.nodes.values.first { $0.children.count == 3 && $0.role == .group })
    #expect(counter.isFocusable && counter.label == nil, "the counter panel is a focusable group")
    #expect(try demo.one("Decrement").node.actions == [.press] && demo.one("Increment").node.actions == [.press])
    let table = try #require(demo.nodes.values.first { $0.role == .table })
    #expect(table.rowCount == 500, "the list's logical count")
    let firstRow = try #require(table.children.first.flatMap { demo.nodes[$0] })
    #expect(firstRow.role == .row && firstRow.rowIndex == 0 && !firstRow.isSelectable, "row 0, not selectable")
    #expect(try demo.one("Row 1 of 500 — a scrollable list item").node.role == .staticText)
    #expect(!demo.readings.contains("Close modal"), "modal off: no scrim")

    let incremented = try #require(trees["demo-incremented"])
    #expect(incremented.readings.contains("Count 1"), "a press on Increment: Count 1")

    let modal = try #require(trees["demo-modal"])
    try #require(modal.roots.count == 1, "modal on: one root: \(modal.readings)")
    let scrim = try #require(modal.nodes[modal.roots[0]])
    #expect(scrim.role == .button && scrim.label == "Close modal" && scrim.actions == [.press], "\(scrim)")
    try #require(scrim.children.count == 1, "the scrim holds the panel")
    let panel = try #require(modal.nodes[scrim.children[0]])
    #expect(panel.role == .group && panel.label == modalText && panel.actions == [.press],
            "T3p: the panel is a group, its folded label and press kept: \(panel)")
    #expect(panel.children.isEmpty)
    #expect(modal.nodes.count == 2 && modal.readings == ["Close modal", modalText],
            "nothing behind the scrim: \(modal.readings)")

    // Divergence 95 through a live window: a held element is refused.
    demoModel.showModal = false
    defer { demoModel.showModal = false }
    let (window, platform) = try scriptWindow { demoContent() }
    let held = try published(platform).one("Increment").id
    demoModel.showModal = true
    auditSettle(window)
    #expect(window.accessibility.lastIsolatedOut, "the build was isolated")
    #expect(!platform.simulateAccessibilityRequest(.press(held)), "divergence 95: the held Increment is refused")
}

// MARK: - 3.9 the controls demo

/// **3.9.** `controlsDemoContent()` publishes every control's label, role and
/// value in the order the script walks them, and the four trees the script's
/// actions produce: `Press me` pressed (`pressed 1 times`; a button's press
/// requests no focus), the slider incremented (`0.5`), row 4 pressed (selected,
/// and its list focused — `DD-AE` item 2: a press keeps the click's focus
/// request) and row 5 selected by a client (`IX-AA`: divergence 83 retires). Mutation M3i
/// (the demo's list built without `selection:`) must redden it.
@Test @MainActor func theControlsDemoPublishesTheTreeTheVoiceOverScriptReads() throws {
    let trees = try controlsTrees()
    let controls = try #require(trees["controls"])
    let press: AccessibilityActions = [.press], adjust: AccessibilityActions = [.increment, .decrement]
    let expected: [AuditNode] = [
        AuditNode(.staticText, value: "Controls"),
        AuditNode(.button, label: "Press me", actions: press),
        AuditNode(.staticText, value: "pressed 0 times"),
        AuditNode(.checkBox, label: "Wi-Fi", value: "1", actions: press),
        AuditNode(.slider, value: "0.4", actions: adjust),
        AuditNode(.staticText, value: "volume 4"),
        AuditNode(.incrementor, label: "Quantity 2", value: "2", actions: adjust),
        AuditNode(.button, actions: press),
        AuditNode(.button, actions: press),
        AuditNode(.radioGroup, label: "Flavor"),
        AuditNode(.radioButton, label: "Vanilla", value: "0", actions: press),
        AuditNode(.radioButton, label: "Chocolate", value: "1", selected: true, actions: press),
        AuditNode(.radioButton, label: "Strawberry", value: "0", actions: press),
        AuditNode(.radioGroup, label: "Size"),
        AuditNode(.radioButton, label: "Small", value: "0", actions: press),
        AuditNode(.radioButton, label: "Medium", value: "1", selected: true, actions: press),
        AuditNode(.radioButton, label: "Large", value: "0", actions: press),
        AuditNode(.checkBox, label: "Water the plants", value: "0", actions: press),
        AuditNode(.checkBox, label: "Take out the bins", value: "1", actions: press),
        AuditNode(.checkBox, label: "Call the plumber", value: "0", actions: press),
        AuditNode(.table),
    ]
    let rows = controls.auditRows
    try #require(rows.count > expected.count, "the tree: \(rows)")
    for (index, row) in expected.enumerated() {
        #expect(rows[index] == row, "position \(index): \(rows[index]) vs \(row)")
    }
    let table = try #require(controls.nodes.values.first { $0.role == .table })
    #expect(table.rowCount == 40, "the list's logical count")
    let realized = table.children.compactMap { controls.nodes[$0] }
    #expect(realized.allSatisfy { $0.role == .row && $0.isSelectable && $0.actions == press },
            "every realized row is selectable and presses")
    #expect(realized.filter(\.isSelected).map(\.rowIndex) == [2], "row 2 is selected")

    let pressed = try #require(trees["controls-pressed"])
    #expect(pressed.readings.contains("pressed 1 times"), "a press: pressed 1 times")
    #expect(pressed.focused == nil, "a button's press requests no focus, as its click does not")
    let rowPressed = try #require(trees["controls-row-pressed"])
    let pressedTable = try #require(rowPressed.nodes.first { $0.value.role == .table })
    #expect(rowPressed.nodes.values.filter { $0.role == .row && $0.isSelected }.map(\.rowIndex) == [4],
            "a press on row 4 selects it")
    #expect(rowPressed.focused == pressedTable.key, "DD-AE item 2: a row's press focuses its list, as its click does")
    let sliderUp = try #require(trees["controls-slider-up"])
    #expect(sliderUp.readings.contains("0.5") && sliderUp.readings.contains("volume 5"), "the slider moved one step")
    let selected = try #require(trees["controls-row-selected"])
    let selectedRows = selected.nodes.values.filter { $0.role == .row && $0.isSelected }
    #expect(selectedRows.map(\.rowIndex) == [5], "IX-AA: the client's selection replaced the set")
}

// MARK: - 3.10 the script

/// A marker's fields.
private struct ScriptMarker {
    var kind: String
    var fields: [String: String]
    var line: Int
    var step: String { fields["step"] ?? "line \(line)" }
}

private func scriptURL(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("docs/verification/voiceover-script.md")
}

/// Every `<!-- ax: … -->` and `<!-- ax-absent: … -->` marker, fields parsed:
/// `key=value`, `key="quoted"` or `key=[a|b]`.
private func scriptMarkers(_ text: String) -> [ScriptMarker] {
    var markers: [ScriptMarker] = []
    for (index, line) in text.components(separatedBy: "\n").enumerated() {
        var rest = Substring(line)
        while let open = rest.range(of: "<!-- ax") {
            guard let close = rest.range(of: "-->", range: open.upperBound..<rest.endIndex) else { break }
            let body = rest[open.upperBound..<close.lowerBound]
            rest = rest[close.upperBound...]
            let kind: String
            var scanner: Substring
            if body.hasPrefix("-absent:") {
                kind = "ax-absent"
                scanner = body.dropFirst("-absent:".count)
            } else if body.hasPrefix(":") {
                kind = "ax"
                scanner = body.dropFirst()
            } else { continue }
            var fields: [String: String] = [:]
            while true {
                scanner = scanner.drop { $0 == " " }
                guard let equals = scanner.firstIndex(of: "=") else { break }
                let key = String(scanner[..<equals])
                scanner = scanner[scanner.index(after: equals)...]
                var value: Substring
                if scanner.first == "\"" {
                    let start = scanner.index(after: scanner.startIndex)
                    let end = scanner[start...].firstIndex(of: "\"") ?? scanner.endIndex
                    value = scanner[start..<end]
                    scanner = end < scanner.endIndex ? scanner[scanner.index(after: end)...] : ""
                } else if scanner.first == "[" {
                    let end = scanner.firstIndex(of: "]") ?? scanner.endIndex
                    value = scanner[scanner.startIndex..<min(scanner.index(after: end), scanner.endIndex)]
                    scanner = end < scanner.endIndex ? scanner[scanner.index(after: end)...] : ""
                } else {
                    let end = scanner.firstIndex(of: " ") ?? scanner.endIndex
                    value = scanner[..<end]
                    scanner = scanner[end...]
                }
                fields[key] = String(value)
            }
            markers.append(ScriptMarker(kind: kind, fields: fields, line: index + 1))
        }
    }
    return markers
}

private func actionsText(_ actions: AccessibilityActions) -> String {
    var names: [String] = []
    if actions.contains(.press) { names.append("press") }
    if actions.contains(.increment) { names.append("increment") }
    if actions.contains(.decrement) { names.append("decrement") }
    return names.isEmpty ? "none" : names.joined(separator: "+")
}

/// What `node` answers for a marker `key`, as the marker spells it; `nil` for
/// a key no node carries.
private func markerValue(_ key: String, _ id: AccessibilityNodeID, _ node: AccessibilityNode,
                         in tree: AccessibilityTree) -> String? {
    switch key {
    case "role": return "\(node.role)"
    case "label": return node.label ?? "-"
    case "value": return node.value ?? "-"
    case "selected": return "\(node.isSelected)"
    case "enabled": return "\(node.isEnabled)"
    case "selectable": return "\(node.isSelectable)"
    case "focused": return "\(tree.focused == id)"
    case "root": return "\(tree.roots.contains(id))"
    case "actions": return actionsText(node.actions)
    case "custom": return "[" + node.customActions.joined(separator: "|") + "]"
    case "rows": return node.rowCount.map(String.init) ?? "-"
    case "index": return node.rowIndex.map(String.init) ?? "-"
    case "realized": return "\(node.children.filter { tree.nodes[$0]?.role == .row }.count)"
    case "children": return "\(node.children.count)"
    default: return nil
    }
}

/// **3.10.** Every marker in `docs/verification/voiceover-script.md` agrees
/// with the tree 3.8, 3.9 or 3.11 pins: an `ax` marker names exactly one node
/// by its identifying fields (role, label, value, index) and every other field
/// it carries (selected, enabled, focused, actions, custom actions, a table's
/// row counts) must equal that node's; an `ax-absent` marker's label is no
/// published node's label or value. Each marker kind is present
/// (`try #require`), and the steps labelled **(VoiceOver behaviour, not
/// pinned)** are counted, so an unpinned claim is visible in review.
/// Mutations M3j (one label in the script changed — the test names the step)
/// and M3j′ (an `ax-absent` marker naming `Increment`, which is published)
/// must redden it.
@Test @MainActor func theVoiceOverScriptQuotesThePublishedTree() throws {
    let url = scriptURL()
    let text = try #require(try? String(contentsOf: url, encoding: .utf8), "the script exists at \(url.path)")
    let markers = scriptMarkers(text)
    let present = markers.filter { $0.kind == "ax" }, absent = markers.filter { $0.kind == "ax-absent" }
    try #require(present.count >= 40, "ax markers: \(present.count)")
    try #require(absent.count >= 3, "ax-absent markers: \(absent.count)")
    let unpinned = text.components(separatedBy: "(VoiceOver behaviour, not pinned)").count - 1
    try #require(unpinned >= 1, "the unpinned labels are counted: \(unpinned)")
    print("VOICEOVER SCRIPT markers: ax=\(present.count) ax-absent=\(absent.count) unpinned=\(unpinned)")

    var trees = try demoTrees()
    trees.merge(try controlsTrees()) { first, _ in first }
    trees.merge(try previewAndTextInputTrees()) { first, _ in first }
    let identifying: Set<String> = ["role", "label", "value", "index"]
    let known: Set<String> = identifying.union(["step", "tree", "selected", "enabled", "selectable", "focused",
                                                "root", "actions", "custom", "rows", "realized", "children"])

    for marker in markers {
        let treeName = try #require(marker.fields["tree"], "\(marker.step): no tree=")
        let tree = try #require(trees[treeName], "\(marker.step): no tree named \(treeName)")
        let unknown = Set(marker.fields.keys).subtracting(known)
        #expect(unknown.isEmpty, "\(marker.step): unknown fields \(unknown)")
        if marker.kind == "ax-absent" {
            let label = try #require(marker.fields["label"], "\(marker.step): ax-absent needs label=")
            let carriers = tree.nodes.values.filter { $0.label == label || $0.value == label }
            #expect(carriers.isEmpty, "\(marker.step): \"\(label)\" is published in \(treeName)")
            continue
        }
        let keys = marker.fields.keys.filter(identifying.contains)
        try #require(!keys.isEmpty, "\(marker.step): no identifying field")
        let matches = tree.nodes.filter { entry in
            keys.allSatisfy { markerValue($0, entry.key, entry.value, in: tree) == marker.fields[$0] }
        }
        guard matches.count == 1, let (id, node) = matches.first.map({ ($0.key, $0.value) }) else {
            Issue.record("\(marker.step): \(matches.count) nodes in \(treeName) match \(marker.fields)")
            continue
        }
        for (key, expected) in marker.fields where !identifying.contains(key) && key != "step" && key != "tree" {
            let actual = markerValue(key, id, node, in: tree)
            #expect(actual == expected, "\(marker.step): \(key) is \(actual ?? "nil"), the script says \(expected)")
        }
    }
}

// MARK: - 3.11 the preview and the text-input demo

/// **3.11.** `nativeLayoutPreviewContent()` with a client publishes its two
/// proposal texts in reading order and nothing else — its grid holds only
/// rectangles and tapped cells, and a tap publishes no press (G1, `IX-Y`), so
/// the grid adds nothing (`IX-AB`'s first production reader; `AB-Q`'s "the
/// preview toggle is silent" is answered: the toggle's tap is silent, as
/// SwiftUI's). The text-input demo publishes its two fields, the echo text
/// and the editor, and a `.focus` request on the first field is the tree's
/// focus. Mutation M3k (`ProposalText.prepaint` records nothing) must redden
/// the preview arm and not the text-input arm.
@Test @MainActor func thePreviewAndTextInputDemosPublishTheTreesTheScriptReads() throws {
    let trees = try previewAndTextInputTrees()
    let preview = try #require(trees["preview"])
    #expect(preview.readings == ["Native proposal text measures and wraps from the parent width.",
                                 "Proposal scroll content stays intrinsically tall."],
            "the preview's texts in reading order: \(preview.readings)")
    #expect(preview.nodes.count == 2 && preview.nodes.values.allSatisfy { $0.role == .staticText && $0.actions == [] },
            "nothing else: \(preview.auditRows)")

    let textInput = try #require(trees["textinput"])
    let expected: [AuditNode] = [
        AuditNode(.staticText, value: "Text input"),
        AuditNode(.textField, label: "Type here: an input method, a selection, copy and paste", value: ""),
        AuditNode(.textField, label: "A second field — Tab does not move here; click it", value: ""),
        AuditNode(.staticText, value: "(the first field echoes here)"),
        AuditNode(.textArea, label: "A multi-line editor: return, up and down, the wheel", value: ""),
    ]
    #expect(textInput.auditRows == expected, "the text-input demo: \(textInput.auditRows)")
    #expect(textInput.focused == nil, "nothing focused at first")
    let focused = try #require(trees["textinput-focused"])
    #expect(focused.focused == (try focused.one("Type here: an input method, a selection, copy and paste").id),
            "a focus request is the tree's focus")
}
