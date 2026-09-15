import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
@testable import MetalUIPlatform

// Lane 2 of the accessibility bridge: the AppKit side (spec
// `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`, "Lane 2").
//
// **Footing.** Real `AppKitPlatform` windows, opened through the internal
// `AppKitPlatform(device:accessibilitySignal:)` with a scripted signal (ruling
// AB-AC), and closed by each test. Trees are built by hand. A recording poster
// replaces the system one. Everything a client would read is read through the
// NSAccessibility protocol methods the AX server calls — on the host view and on
// the vended elements — never through the bridge's own lookups, so a test sees
// what VoiceOver would. No VoiceOver, no permission, no deprecated informal API.
//
// **Fixture rule.** Every id, label and rect is distinct per node (taxonomy
// shape 1), and every element a later assertion reads is `try #require`d.

/// `Accessibility.framework` (imported through `AppKit`) also exports a Swift
/// `AccessibilityRequest` (`AXRequest`), so the bare name is ambiguous in any
/// file that imports both.
private typealias Request = MetalUIPlatform.AccessibilityRequest

// MARK: - Harness

/// An `AccessibilityClientSignal` a test drives. Like `VoiceOverSignal`, it
/// calls its handler with the current value **synchronously inside `observe`**.
@MainActor final class ScriptedAccessibilitySignal: AccessibilityClientSignal {
    private(set) var value: Bool
    private var handler: (@MainActor (Bool) -> Void)?
    init(_ value: Bool) { self.value = value }
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) {
        self.handler = handler
        handler(value)
    }
    func send(_ newValue: Bool) {
        value = newValue
        handler?(newValue)
    }
}

@MainActor final class RecordingAccessibilityPoster: AccessibilityNotificationPosting {
    struct Post { let name: NSAccessibility.Notification; let element: AnyObject }
    private(set) var posts: [Post] = []
    func post(_ notification: NSAccessibility.Notification, for element: Any) {
        posts.append(Post(name: notification, element: element as AnyObject))
    }
    func reset() { posts.removeAll() }
    func count(_ name: NSAccessibility.Notification) -> Int { posts.filter { $0.name == name }.count }
}

@MainActor private final class RequestLog {
    var requests: [Request] = []
    var answer = true
}

@MainActor private struct Harness {
    let nsWindow: NSWindow
    let host: NSView
    let bridge: AppKitAccessibilityBridge
    let signal: ScriptedAccessibilitySignal
    let poster: RecordingAccessibilityPoster
    let log: RequestLog

    /// Screen rect of a content-space rect, by literal arithmetic over the
    /// window's content rect — never through the conversion under test.
    func screenRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        let content = nsWindow.contentRect(forFrameRect: nsWindow.frame)
        return NSRect(x: content.minX + x, y: content.maxY - y - h, width: w, height: h)
    }

    func screenPoint(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        let content = nsWindow.contentRect(forFrameRect: nsWindow.frame)
        return NSPoint(x: content.minX + x, y: content.maxY - y)
    }
}

/// Opens a real window whose bridge has a scripted signal, a recording poster
/// and a logging request handler.
///
/// **The log is installed before the signal can be flipped**, so a signal that
/// starts `true` delivers its pending `.activate` into the log at assignment
/// (AB-B); tests that start `true` account for that one request.
@MainActor private func makeHarness(signal initial: Bool, width: Int = 200, height: Int = 200) throws -> Harness {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let signal = ScriptedAccessibilitySignal(initial)
    let platform = AppKitPlatform(device: device, accessibilitySignal: { signal })
    let window = try platform.openWindow(title: "AX \(UUID().uuidString)",
                                         size: Size(width: Pixels(Float(width)), height: Pixels(Float(height))))
    let appKit = try #require(window as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    let poster = RecordingAccessibilityPoster()
    appKit.accessibilityBridge.poster = poster
    let log = RequestLog()
    appKit.accessibilityBridge.onRequest = { request in
        log.requests.append(request)
        return log.answer
    }
    return Harness(nsWindow: nsWindow, host: appKit.hostView, bridge: appKit.accessibilityBridge,
                   signal: signal, poster: poster, log: log)
}

private func nid(_ name: String) -> AccessibilityNodeID { AccessibilityNodeID(name) }

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

/// One hand-built node: its node, its frame, and optionally a distinct visible
/// frame and a layer.
private struct Entry {
    var node: AccessibilityNode
    var frame: Bounds<Pixels>
    var visible: Bounds<Pixels>?
    var layer = 0
}

private func node(_ role: AccessibilityRole, _ label: String? = nil, value: String? = nil,
                  children: [String] = [], actions: AccessibilityActions = [],
                  isFocusable: Bool = false, rowCount: Int? = nil, rowIndex: Int? = nil) -> AccessibilityNode {
    AccessibilityNode(role: role, label: label, value: value, isFocusable: isFocusable, actions: actions,
                      children: children.map(nid), rowCount: rowCount, rowIndex: rowIndex)
}

/// Assembles a tree, giving every node `order` by pre-order from `roots`, the
/// way `AccessibilityTreeBuilder` does from record order.
private func makeTree(roots: [String], _ entries: [String: Entry], focused: String? = nil) -> AccessibilityTree {
    var geometry: [AccessibilityNodeID: AccessibilityGeometry] = [:]
    var next = 0
    func visit(_ name: String) {
        let entry = entries[name]!
        geometry[nid(name)] = AccessibilityGeometry(frame: entry.frame, visibleFrame: entry.visible ?? entry.frame,
                                                    layer: entry.layer, order: next)
        next += 1
        for child in entry.node.children { visit(child.base as! String) }
    }
    roots.forEach(visit)
    precondition(geometry.count == entries.count, "every entry must be reachable from a root")
    return AccessibilityTree(roots: roots.map(nid),
                             nodes: Dictionary(uniqueKeysWithValues: entries.map { (nid($0.key), $0.value.node) }),
                             geometry: geometry, focused: focused.map(nid))
}

private func elements(_ list: [Any]?) -> [AppKitAccessibilityElement] {
    (list ?? []).compactMap { $0 as? AppKitAccessibilityElement }
}

private func label(_ any: Any?) -> String? { (any as? AppKitAccessibilityElement)?.accessibilityLabel() }

// MARK: - The host view and identity (AB-N, AB-D, AB-X)

/// The host is an `AXGroup` element whose children are the published roots, in
/// root order, each naming the host as its parent.
///
/// Six roots in an unsorted order: a mutant returning roots in dictionary order
/// would match a two-root fixture by chance (lane 1's M08 lesson).
@Test @MainActor func theHostViewIsAGroupWhoseChildrenAreThePublishedRoots() throws {
    let h = try makeHarness(signal: false)
    defer { h.nsWindow.close() }
    let names = ["d", "a", "f", "c", "e", "b"]
    var entries: [String: Entry] = [:]
    for (i, name) in names.enumerated() {
        entries[name] = Entry(node: node(.staticText, "root-\(name)"), frame: rect(0, Float(i * 20), 50, 20))
    }
    h.bridge.publish(makeTree(roots: names, entries))

    #expect(h.host.isAccessibilityElement())
    #expect(h.host.accessibilityRole() == .group)
    let children = elements(h.host.accessibilityChildren())
    try #require(children.count == 6, "a plain NSView answers no children")
    #expect(children.map { $0.accessibilityLabel() } == names.map { "root-\($0)" })
    for child in children {
        #expect(child.accessibilityParent() as AnyObject === h.host, "a root's parent is the host view")
    }
}

/// Role, label, value, selection and enablement map one to one, each node with
/// its own distinct values.
@Test @MainActor func rolesLabelsValuesAndTraitsMapOneToOne() throws {
    let h = try makeHarness(signal: true)
    defer { h.nsWindow.close() }
    var selected = node(.staticText, "L-text", value: "V-text")
    selected.isSelected = true
    var disabled = node(.image, "L-image", value: "V-image")
    disabled.isEnabled = false
    let roots = ["group", "button", "text", "image", "table"]
    h.bridge.publish(makeTree(roots: roots, [
        "group": Entry(node: node(.group, "L-group", value: "V-group"), frame: rect(0, 0, 10, 10)),
        "button": Entry(node: node(.button, "L-button", value: "V-button"), frame: rect(0, 10, 10, 10)),
        "text": Entry(node: selected, frame: rect(0, 20, 10, 10)),
        "image": Entry(node: disabled, frame: rect(0, 30, 10, 10)),
        "table": Entry(node: node(.table, "L-table", value: "V-table", children: ["row"], rowCount: 1),
                       frame: rect(0, 40, 10, 20)),
        "row": Entry(node: node(.row, "L-row", value: "V-row", rowIndex: 0), frame: rect(0, 40, 10, 10)),
    ]))

    let top = elements(h.host.accessibilityChildren())
    try #require(top.count == 5)
    let row = try #require(elements(top[4].accessibilityChildren()).first)
    let all = top + [row]
    let expectedRoles: [NSAccessibility.Role] = [.group, .button, .staticText, .image, .table, .row]
    let names = ["group", "button", "text", "image", "table", "row"]
    for (element, (role, name)) in zip(all, zip(expectedRoles, names)) {
        #expect(element.accessibilityRole() == role, "\(name)'s role")
        #expect(element.accessibilityLabel() == "L-\(name)", "\(name)'s label")
        #expect(element.accessibilityValue() as? String == "V-\(name)", "\(name)'s value")
        #expect(element.isAccessibilityElement())
    }
    #expect(all[2].isAccessibilitySelected() && !all.enumerated().contains { $0.offset != 2 && $0.element.isAccessibilitySelected() })
    #expect(!all[3].isAccessibilityEnabled(), "a disabled node answers not enabled")
    #expect(all.enumerated().allSatisfy { $0.offset == 3 || $0.element.isAccessibilityEnabled() })
}

/// Publishing creates no element; a client read creates exactly what it was
/// handed, once (AB-X).
@Test @MainActor func elementsAreCreatedOnlyWhenAClientReadsThem() throws {
    let h = try makeHarness(signal: true)
    defer { h.nsWindow.close() }
    try #require(h.bridge.isActive, "active through the signal, so no host query was needed")
    let rows = (0..<1000).map { "row\($0)" }
    var entries: [String: Entry] = ["table": Entry(node: node(.table, "table", children: rows, rowCount: 1000),
                                                   frame: rect(0, 0, 200, 28_000))]
    for (i, row) in rows.enumerated() {
        entries[row] = Entry(node: node(.row, row, rowIndex: i), frame: rect(0, Float(i * 28), 200, 28))
    }
    h.bridge.publish(makeTree(roots: ["table"], entries))
    #expect(h.bridge.createdElementCount == 0, "a publish creates no element")

    let top = elements(h.host.accessibilityChildren())
    try #require(top.count == 1)
    #expect(h.bridge.createdElementCount == 1)
    #expect(elements(top[0].accessibilityChildren()).count == 1000)
    #expect(h.bridge.createdElementCount == 1001)
    _ = top[0].accessibilityChildren()
    _ = h.host.accessibilityChildren()
    #expect(h.bridge.createdElementCount == 1001, "a second read hands out the same objects")
}

/// A vended element keeps its object across a label change, and is detached —
/// parentless, refusing, still describing itself — when its id is gone; a
/// returning id gets a new object (AB-D, arm 12).
@Test @MainActor func aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes() throws {
    let h = try makeHarness(signal: true)
    defer { h.nsWindow.close() }
    func tree(aLabel: String, withB: Bool) -> AccessibilityTree {
        var entries = ["a": Entry(node: node(.button, aLabel, actions: [.press]), frame: rect(4, 6, 40, 20))]
        if withB { entries["b"] = Entry(node: node(.button, "b", actions: [.press]), frame: rect(12, 50, 30, 18)) }
        return makeTree(roots: withB ? ["a", "b"] : ["a"], entries)
    }
    h.bridge.publish(tree(aLabel: "a", withB: true))
    let first = elements(h.host.accessibilityChildren())
    try #require(first.count == 2)
    let (a, b) = (first[0], first[1])
    let bFrame = b.accessibilityFrame()
    #expect(bFrame == h.screenRect(12, 50, 30, 18), "control: b's frame is live before removal")

    h.bridge.publish(tree(aLabel: "a2", withB: true))
    let second = elements(h.host.accessibilityChildren())
    try #require(second.count == 2)
    #expect(second[0] === a && second[1] === b, "a label change keeps the objects")
    #expect(a.accessibilityLabel() == "a2")

    h.bridge.publish(tree(aLabel: "a2", withB: false))
    #expect(b.accessibilityParent() == nil, "a detached element has no parent")
    #expect(!elements(h.host.accessibilityChildren()).contains { $0 === b })
    #expect(a.accessibilityParent() as AnyObject === h.host, "control: the survivor keeps its parent")
    let requestsBefore = h.log.requests.count
    #expect(!b.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.accessibilityPerformPress)))
    #expect(b.accessibilityPerformPress() == false)
    #expect(h.log.requests.count == requestsBefore, "a detached element sends no request")
    #expect(b.accessibilityLabel() == "b", "it keeps describing what it was")
    #expect(b.accessibilityChildren()?.isEmpty ?? true)
    #expect(b.accessibilityFrame() == bFrame, "its last rect, still converted through the live host view")

    h.bridge.publish(tree(aLabel: "a2", withB: true))
    let third = elements(h.host.accessibilityChildren())
    try #require(third.count == 2)
    #expect(third[1] !== b, "an id that returns gets a new object: no revival")
    #expect(third[0] === a)
}

/// A frame is the host rect converted to screen coordinates **when read**, so a
/// window move with no republish moves it.
@Test @MainActor func anElementsFrameIsItsHostRectInScreenCoordinatesReadAtQueryTime() throws {
    let h = try makeHarness(signal: true, width: 200, height: 100)
    defer { h.nsWindow.close() }
    h.bridge.publish(makeTree(roots: ["n"], ["n": Entry(node: node(.button, "n"), frame: rect(10, 0, 20, 16))]))
    let element = try #require(elements(h.host.accessibilityChildren()).first)

    let content = h.nsWindow.contentRect(forFrameRect: h.nsWindow.frame)
    try #require(content.width == 200 && content.height == 100, "precondition: a 200x100 content rect")
    #expect(element.accessibilityFrame() == NSRect(x: content.minX + 10, y: content.maxY - 0 - 16,
                                                   width: 20, height: 16))

    let before = h.nsWindow.frame.origin
    h.nsWindow.setFrameOrigin(NSPoint(x: before.x + 37, y: before.y + 23))
    try #require(h.nsWindow.frame.origin == NSPoint(x: before.x + 37, y: before.y + 23),
                 "precondition: the window really moved by (37, 23)")
    #expect(element.accessibilityFrame() == NSRect(x: content.minX + 10 + 37, y: content.maxY - 16 + 23,
                                                   width: 20, height: 16),
            "read at query time: a move with no publish moves the frame")
}

// MARK: - Actions and focus (AB-H, AB-J)

/// A perform selector is allowed exactly where the node advertises the action,
/// and performing it sends the request and returns the window's answer.
@Test @MainActor func onlyAdvertisedActionsAreAllowedAndPerformingSendsTheRequest() throws {
    let h = try makeHarness(signal: true)
    defer { h.nsWindow.close() }
    h.bridge.publish(makeTree(roots: ["p", "adj", "inert"], [
        "p": Entry(node: node(.button, "p", actions: [.press]), frame: rect(0, 0, 20, 20)),
        "adj": Entry(node: node(.group, "adj", actions: [.increment, .decrement]), frame: rect(0, 20, 20, 20)),
        "inert": Entry(node: node(.group, "inert"), frame: rect(0, 40, 20, 20)),
    ]))
    let top = elements(h.host.accessibilityChildren())
    try #require(top.count == 3)
    let (p, adj, inert) = (top[0], top[1], top[2])
    let press = #selector(NSAccessibilityElement.accessibilityPerformPress)
    let increment = #selector(NSAccessibilityElement.accessibilityPerformIncrement)
    let decrement = #selector(NSAccessibilityElement.accessibilityPerformDecrement)
    #expect(p.isAccessibilitySelectorAllowed(press))
    #expect(!p.isAccessibilitySelectorAllowed(increment) && !p.isAccessibilitySelectorAllowed(decrement))
    #expect(!adj.isAccessibilitySelectorAllowed(press))
    #expect(adj.isAccessibilitySelectorAllowed(increment) && adj.isAccessibilitySelectorAllowed(decrement))
    #expect(![press, increment, decrement].contains { inert.isAccessibilitySelectorAllowed($0) })

    h.log.requests.removeAll()
    h.log.answer = true
    #expect(p.accessibilityPerformPress())
    h.log.answer = false
    #expect(!p.accessibilityPerformPress(), "the window's answer, not a constant")
    #expect(h.log.requests == [.press(nid("p")), .press(nid("p"))])

    h.log.requests.removeAll()
    h.log.answer = true
    #expect(adj.accessibilityPerformIncrement())
    #expect(adj.accessibilityPerformDecrement())
    #expect(h.log.requests == [.increment(nid("adj")), .decrement(nid("adj"))])

    h.log.requests.removeAll()
    #expect(!inert.accessibilityPerformPress())
    #expect(!inert.accessibilityPerformIncrement())
    #expect(!p.accessibilityPerformIncrement(), "a press-only node refuses an adjustment")
    #expect(!adj.accessibilityPerformPress(), "an adjustable node refuses a press")
    #expect(h.log.requests.isEmpty, "a disallowed perform sends nothing")
}

/// Focus is the tree's `focused`, and a focus setter sends `.focus(id)`. With
/// nothing focused the host reports itself, not the first focusable node
/// (AB-J's recorded divergence from SwiftUI's arm 13).
@Test @MainActor func focusIsReportedFromTheTreeAndAFocusRequestIsSent() throws {
    let h = try makeHarness(signal: true)
    defer { h.nsWindow.close() }
    func tree(focused: String?) -> AccessibilityTree {
        makeTree(roots: ["a", "b"], [
            "a": Entry(node: node(.button, "a", isFocusable: true), frame: rect(0, 0, 20, 20)),
            "b": Entry(node: node(.button, "b", isFocusable: true), frame: rect(0, 20, 20, 20)),
        ], focused: focused)
    }
    h.bridge.publish(tree(focused: "b"))
    let top = elements(h.host.accessibilityChildren())
    try #require(top.count == 2)
    let (a, b) = (top[0], top[1])
    #expect(h.host.accessibilityFocusedUIElement as AnyObject === b)
    #expect(b.isAccessibilityFocused() && !a.isAccessibilityFocused())

    h.log.requests.removeAll()
    a.setAccessibilityFocused(true)
    #expect(h.log.requests == [.focus(nid("a"))])
    a.setAccessibilityFocused(false)
    #expect(h.log.requests == [.focus(nid("a"))], "clearing focus from a client is ignored")
    #expect(b.isAccessibilityFocused(), "a request changes nothing until the window publishes")

    h.bridge.publish(tree(focused: nil))
    #expect(h.host.accessibilityFocusedUIElement as AnyObject === h.host,
            "nothing focused: the host reports itself, not the first focusable node")
    #expect(!a.isAccessibilityFocused() && !b.isAccessibilityFocused())
}

// MARK: - Tables (AB-L)

/// A table's row count is its logical count; its rows are its `.row` children,
/// visible where their visible frame has area; a row's index is its logical
/// index, not its position.
@Test @MainActor func aTableReportsItsRowCountAndItsRowsTheirIndices() throws {
    let h = try makeHarness(signal: true)
    defer { h.nsWindow.close() }
    h.bridge.publish(makeTree(roots: ["table"], [
        "table": Entry(node: node(.table, "table", children: ["r40", "r41", "r42"], rowCount: 500),
                       frame: rect(0, -1120, 200, 14_000), visible: rect(0, 0, 200, 100)),
        "r40": Entry(node: node(.row, "r40", rowIndex: 40), frame: rect(0, -8, 200, 28), visible: rect(0, 0, 200, 0)),
        "r41": Entry(node: node(.row, "r41", rowIndex: 41), frame: rect(0, 20, 200, 28)),
        "r42": Entry(node: node(.row, "r42", rowIndex: 42), frame: rect(0, 48, 200, 28)),
    ]))
    let table = try #require(elements(h.host.accessibilityChildren()).first)
    #expect(table.accessibilityRowCount() == 500)
    let rows = elements(table.accessibilityRows())
    try #require(rows.count == 3)
    #expect(rows.map { $0.accessibilityLabel() } == ["r40", "r41", "r42"])
    #expect(rows.map { $0.accessibilityIndex() } == [40, 41, 42])
    #expect(elements(table.accessibilityVisibleRows()).map { $0.accessibilityLabel() } == ["r41", "r42"],
            "a row with a zero-height visible frame is not visible")

    // Every element implements the table and row accessors, so the selector
    // gate is what keeps a row from advertising a row count and a table from
    // advertising an index (AB-AF item 5).
    let rowCount = #selector(NSAccessibilityElement.accessibilityRowCount)
    let rowsSelector = #selector(NSAccessibilityElement.accessibilityRows)
    let index = #selector(NSAccessibilityElement.accessibilityIndex)
    #expect(table.isAccessibilitySelectorAllowed(rowCount) && table.isAccessibilitySelectorAllowed(rowsSelector))
    #expect(!table.isAccessibilitySelectorAllowed(index))
    #expect(rows[0].isAccessibilitySelectorAllowed(index))
    #expect(!rows[0].isAccessibilitySelectorAllowed(rowCount) && !rows[0].isAccessibilitySelectorAllowed(rowsSelector))
}

// MARK: - Hit testing (AB-W)

/// The shape a scrolled `List` under a header really publishes: the table's
/// unclipped frame reaches above the viewport and its overscan row's frame
/// contains a point over the header. Only visible frames rank, by
/// `(layer, order)`.
@Test @MainActor func hitTestingUsesVisibleFramesSoAClippedRowNeverWins() throws {
    let h = try makeHarness(signal: true)
    defer { h.nsWindow.close() }
    var entries: [String: Entry] = [
        "header": Entry(node: node(.staticText, "header"), frame: rect(0, 0, 200, 20)),
        "table": Entry(node: node(.table, "table", children: ["overscan", "row"], rowCount: 500),
                       frame: rect(0, -8, 200, 14_000), visible: rect(0, 20, 200, 100)),
        "overscan": Entry(node: node(.row, "overscan", rowIndex: 0), frame: rect(0, -8, 200, 28),
                          visible: rect(0, 20, 200, 0)),
        "row": Entry(node: node(.row, "row", children: ["rowChild"], rowIndex: 1), frame: rect(0, 20, 200, 28)),
        "rowChild": Entry(node: node(.staticText, "rowChild"), frame: rect(0, 22, 200, 24)),
    ]
    h.bridge.publish(makeTree(roots: ["header", "table"], entries))
    _ = h.host.accessibilityChildren()

    #expect(label(h.host.accessibilityHitTest(h.screenPoint(5, 15))) == "header",
            "the table and its overscan row contain this point only in their unclipped frames")
    #expect(label(h.host.accessibilityHitTest(h.screenPoint(10, 40))) == "rowChild",
            "the deepest, latest visible element wins within a layer")
    #expect(label(h.host.accessibilityHitTest(h.screenPoint(100, 110))) == "table", "control: the table itself")
    #expect(h.host.accessibilityHitTest(h.screenPoint(150, 170)) as AnyObject === h.host,
            "outside everything: the host view")

    // Modal arm: a portal panel recorded BEFORE the table (a `Deferred`
    // declared above the list), on the root layer.
    entries["panel"] = Entry(node: node(.group, "panel", children: ["panelLabel"]),
                             frame: rect(0, 30, 200, 40), layer: 1)
    entries["panelLabel"] = Entry(node: node(.staticText, "panelLabel"), frame: rect(5, 32, 150, 30), layer: 1)
    let modal = makeTree(roots: ["header", "panel", "table"], entries)
    try #require(modal.geometry[nid("panel")]?.order == 1 && modal.geometry[nid("rowChild")]?.order == 6,
                 "precondition: the panel records before the row child it covers")
    h.bridge.publish(modal)
    _ = h.host.accessibilityChildren()
    #expect(label(h.host.accessibilityHitTest(h.screenPoint(10, 40))) == "panelLabel",
            "portal content outranks the deeper, later row child it covers")
    #expect(label(h.host.accessibilityHitTest(h.screenPoint(10, 25))) == "rowChild",
            "above the panel the row child still wins")
    #expect(label(h.host.accessibilityHitTest(h.screenPoint(180, 66))) == "panel", "control: the panel itself")
}

// MARK: - Activation (AB-B, AB-AB)

/// A host query activates, once.
@Test @MainActor func aHostQueryActivatesExactlyOnce() throws {
    let h = try makeHarness(signal: false)
    defer { h.nsWindow.close() }
    try #require(!h.bridge.isActive && h.log.requests.isEmpty)
    _ = h.host.accessibilityChildren()
    _ = h.host.accessibilityChildren()
    _ = h.host.accessibilityHitTest(h.screenPoint(10, 10))
    _ = h.host.accessibilityHitTest(h.screenPoint(20, 20))
    #expect(h.log.requests == [.activate])
    #expect(h.bridge.isActive)
}

/// The focused-element query is what a focus-polling utility reaches from
/// another process (measured, `appkit-accessibility-activation-clients.swift`),
/// so it does not activate.
@Test @MainActor func aFocusedElementQueryDoesNotActivate() throws {
    let h = try makeHarness(signal: false)
    defer { h.nsWindow.close() }
    h.bridge.publish(makeTree(roots: ["f"], ["f": Entry(node: node(.button, "f", isFocusable: true),
                                                        frame: rect(0, 0, 20, 20))], focused: "f"))
    for _ in 0..<3 {
        #expect(h.host.accessibilityFocusedUIElement as AnyObject === h.host,
                "before activation the host answers itself")
    }
    #expect(h.log.requests.isEmpty, "a focused-element query must not activate")
    #expect(h.bridge.createdElementCount == 0)

    // Control: a tree query does.
    _ = h.host.accessibilityChildren()
    #expect(h.log.requests == [.activate])
}

/// A running screen reader activates at bridge creation, before anyone
/// listens; the pending `.activate` is delivered synchronously when the window
/// assigns its handler. A later `true` activates once, ever.
@Test @MainActor func aRunningScreenReaderActivatesTheWindowBeforeAnyQuery() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")

    // `true` at creation, through the real platform path.
    let running = ScriptedAccessibilitySignal(true)
    let platform = AppKitPlatform(device: device, accessibilitySignal: { running })
    let window = try platform.openWindow(title: "AX \(UUID().uuidString)",
                                         size: Size(width: Pixels(100), height: Pixels(100)))
    let appKit = try #require(window as? AppKitWindow)
    defer { appKit.hostView.window?.close() }
    #expect(appKit.accessibilityBridge.isActive, "active before any query and before any handler")
    var delivered: [Request] = []
    window.onAccessibilityRequest = { delivered.append($0); return true }
    #expect(delivered == [.activate], "delivered synchronously at assignment, with no run-loop turn")
    window.onAccessibilityRequest = { delivered.append($0); return true }
    #expect(delivered == [.activate], "delivered once, not on every assignment")

    // `false` at creation; later flips.
    let later = ScriptedAccessibilitySignal(false)
    let bridge = AppKitAccessibilityBridge(signal: later, poster: RecordingAccessibilityPoster())
    var requests: [Request] = []
    bridge.onRequest = { requests.append($0); return true }
    #expect(requests.isEmpty && !bridge.isActive)
    later.send(true)
    #expect(requests == [.activate] && bridge.isActive)
    later.send(false)
    later.send(true)
    #expect(requests == [.activate], "activation is sticky")
}

// MARK: - Notifications (AB-K, AB-X)

/// Before activation a publish is stored and posts nothing.
@Test @MainActor func nothingIsPostedBeforeActivation() throws {
    let h = try makeHarness(signal: false)
    defer { h.nsWindow.close() }
    func tree(_ names: [String], focused: String? = nil) -> AccessibilityTree {
        var entries: [String: Entry] = [:]
        for (i, name) in names.enumerated() {
            entries[name] = Entry(node: node(.button, name, isFocusable: true), frame: rect(0, Float(i * 20), 20, 20))
        }
        return makeTree(roots: names, entries, focused: focused)
    }
    h.bridge.publish(tree(["a", "b"], focused: "a"))
    h.bridge.publish(tree(["c"], focused: "c"))
    #expect(h.poster.posts.isEmpty)
    #expect(h.bridge.structuralPublishCount == 0 && h.bridge.geometryPublishCount == 0)

    _ = h.host.accessibilityChildren()
    h.bridge.publish(tree(["d", "e"], focused: "d"))
    #expect(h.poster.count(.layoutChanged) == 1, "control: once active, a structural publish posts")
    #expect(h.poster.count(.focusedUIElementChanged) == 1)
}

/// A publish that moves frames and nothing else touches no element and posts
/// nothing; elements read the new frames lazily.
@Test @MainActor func aGeometryOnlyChangeTouchesNoElementAndPostsNothing() throws {
    let h = try makeHarness(signal: true)
    defer { h.nsWindow.close() }
    func tree(dy: Float) -> AccessibilityTree {
        makeTree(roots: ["g"], [
            "g": Entry(node: node(.group, "g", children: ["x", "y"]), frame: rect(0, 0 + dy, 100, 60)),
            "x": Entry(node: node(.button, "x", actions: [.press]), frame: rect(4, 6 + dy, 30, 20)),
            "y": Entry(node: node(.staticText, "y"), frame: rect(40, 30 + dy, 50, 16)),
        ], focused: "x")
    }
    h.bridge.publish(tree(dy: 0))
    let g = try #require(elements(h.host.accessibilityChildren()).first)
    let leaves = elements(g.accessibilityChildren())
    try #require(leaves.count == 2)
    _ = h.host.accessibilityFocusedUIElement
    let created = h.bridge.createdElementCount
    let structural = h.bridge.structuralPublishCount
    h.poster.reset()

    h.bridge.publish(tree(dy: 5))
    h.bridge.publish(tree(dy: 5))
    #expect(h.poster.posts.isEmpty, "geometry is not announced")
    #expect(h.bridge.structuralPublishCount == structural)
    #expect(h.bridge.geometryPublishCount == 2)
    #expect(h.bridge.createdElementCount == created)
    let again = elements(g.accessibilityChildren())
    #expect(again.count == 2 && again[0] === leaves[0] && again[1] === leaves[1])
    #expect(g.accessibilityFrame() == h.screenRect(0, 5, 100, 60))
    #expect(leaves[0].accessibilityFrame() == h.screenRect(4, 11, 30, 20))
    #expect(leaves[1].accessibilityFrame() == h.screenRect(40, 35, 50, 16))
}

/// A removed id posts `.uiElementDestroyed` only if a client was handed its
/// element.
@Test @MainActor func destroyedIsPostedOnlyForElementsAClientWasHanded() throws {
    let h = try makeHarness(signal: true)
    defer { h.nsWindow.close() }
    func tree(withLeaves: Bool) -> AccessibilityTree {
        var entries: [String: Entry] = [:]
        for r in 0..<3 {
            let leaves = withLeaves ? (0..<10).map { "leaf\(r)-\($0)" } : []
            entries["root\(r)"] = Entry(node: node(.group, "root\(r)", children: leaves),
                                        frame: rect(Float(r * 60), 0, 60, 200))
            for (i, leaf) in leaves.enumerated() {
                entries[leaf] = Entry(node: node(.staticText, leaf), frame: rect(Float(r * 60), Float(i * 20), 60, 20))
            }
        }
        return makeTree(roots: (0..<3).map { "root\($0)" }, entries)
    }
    h.bridge.publish(tree(withLeaves: true))
    let roots = elements(h.host.accessibilityChildren())
    try #require(roots.count == 3)
    let vended = elements(roots[0].accessibilityChildren())
    try #require(vended.count == 10)
    let created = h.bridge.createdElementCount
    h.poster.reset()

    h.bridge.publish(tree(withLeaves: false))
    let destroyed = h.poster.posts.filter { $0.name == .uiElementDestroyed }
    #expect(destroyed.count == 10, "one per vended leaf, none for the twenty never read")
    #expect(destroyed.map(\.element).elementsEqual(vended, by: { $0 === $1 }),
            "on the vended objects, in old-tree order")
    #expect(h.bridge.createdElementCount == created, "no element is created to post on")
}

/// `.layoutChanged` is posted once per client read, however many structural
/// publishes follow.
@Test @MainActor func layoutChangedIsPostedOncePerClientRead() throws {
    let h = try makeHarness(signal: false)
    defer { h.nsWindow.close() }
    func tree(leaves: Int) -> AccessibilityTree {
        let names = (0..<leaves).map { "leaf\($0)" }
        var entries = ["stable": Entry(node: node(.group, "stable", children: names), frame: rect(0, 0, 100, 200))]
        for (i, name) in names.enumerated() {
            entries[name] = Entry(node: node(.staticText, name), frame: rect(0, Float(i * 10), 100, 10))
        }
        return makeTree(roots: ["stable"], entries)
    }
    let stable = try #require(elements({ () -> [Any]? in
        h.bridge.publish(tree(leaves: 1))
        return h.host.accessibilityChildren()   // activates: the activating query counts as a read
    }()).first)
    h.poster.reset()

    h.bridge.publish(tree(leaves: 2))
    #expect(h.poster.count(.layoutChanged) == 1)
    #expect(h.poster.posts.first?.element === h.host, "posted on the host view")

    for n in 3...12 { h.bridge.publish(tree(leaves: n)) }
    #expect(h.poster.count(.layoutChanged) == 1, "ten more changes with no read post nothing more")

    _ = stable.accessibilityChildren()
    h.bridge.publish(tree(leaves: 13))
    #expect(h.poster.count(.layoutChanged) == 2, "a read re-arms exactly one more")

    // Structure is more than the id set. Each arm keeps every id and changes
    // one thing a client's children list or roles depend on; lane 2's
    // mutations L49 (ignore children) and L50 (ignore roles) survived the
    // arms above, which all add ids.
    var reordered = tree(leaves: 13)
    reordered.nodes[nid("stable")]?.children.reverse()
    _ = stable.accessibilityChildren()
    h.bridge.publish(reordered)
    #expect(h.poster.count(.layoutChanged) == 3, "the same children in another order is a layout change")

    var retyped = reordered
    retyped.nodes[nid("leaf0")]?.role = .button
    _ = stable.accessibilityChildren()
    h.bridge.publish(retyped)
    #expect(h.poster.count(.layoutChanged) == 4, "a role change alone is a layout change")
}

/// Label, value, row count and focus changes each post once, on the element
/// that changed; a change on a never-vended node posts nothing.
@Test @MainActor func labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged() throws {
    let h = try makeHarness(signal: true)
    defer { h.nsWindow.close() }
    struct State {
        var aLabel = "a", bValue = "b-value", rowCount = 500, focused = "a", unreadLabel = "u"
    }
    func tree(_ s: State) -> AccessibilityTree {
        makeTree(roots: ["a", "b", "table", "f", "g"], [
            "a": Entry(node: node(.button, s.aLabel, value: "a-value", isFocusable: true), frame: rect(0, 0, 20, 20)),
            "b": Entry(node: node(.staticText, "b", value: s.bValue), frame: rect(0, 20, 20, 20)),
            "table": Entry(node: node(.table, "table", rowCount: s.rowCount), frame: rect(0, 40, 20, 20)),
            "f": Entry(node: node(.button, "f", isFocusable: true), frame: rect(0, 60, 20, 20)),
            "g": Entry(node: node(.group, "g", children: ["u"]), frame: rect(0, 80, 20, 20)),
            "u": Entry(node: node(.staticText, s.unreadLabel), frame: rect(0, 80, 20, 20)),
        ], focused: s.focused)
    }
    var state = State()
    h.bridge.publish(tree(state))
    let top = elements(h.host.accessibilityChildren())   // vends the roots; g's child is never read
    try #require(top.count == 5)
    let (a, b, table, f) = (top[0], top[1], top[2], top[3])
    let created = h.bridge.createdElementCount
    h.poster.reset()

    func expectOnePost(_ name: NSAccessibility.Notification, on element: AnyObject,
                       _ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(h.poster.posts.count == 1, comment, sourceLocation: sourceLocation)
        #expect(h.poster.posts.first?.name == name, comment, sourceLocation: sourceLocation)
        #expect(h.poster.posts.first?.element === element, comment, sourceLocation: sourceLocation)
        h.poster.reset()
    }

    state.aLabel = "a-renamed"
    h.bridge.publish(tree(state))
    expectOnePost(.titleChanged, on: a, "a label change")

    state.bValue = "b-value-2"
    h.bridge.publish(tree(state))
    expectOnePost(.valueChanged, on: b, "a value change")

    state.rowCount = 501
    h.bridge.publish(tree(state))
    expectOnePost(.rowCountChanged, on: table, "a row count change")

    state.focused = "f"
    h.bridge.publish(tree(state))
    expectOnePost(.focusedUIElementChanged, on: f, "a focus change posts on the NEW focus")

    state.unreadLabel = "u-renamed"
    h.bridge.publish(tree(state))
    #expect(h.poster.posts.isEmpty, "a node no client was handed announces nothing")
    #expect(h.bridge.createdElementCount == created, "and nothing is created to announce it")
}

// MARK: - Isolation (AB-AE)

/// AppKit's NSAccessibility overrides are nonisolated, so a query can in
/// principle arrive off the main thread. Answered there, it gets "nothing" — no
/// label, no children, no action, nothing allowed — and the process survives;
/// the same element answers on the main thread (the control, in the same child
/// process).
///
/// **An exit test, because the failure is a trap**: the spelling this replaces,
/// `MainActor.assumeIsolated` with no thread check, kills the process, and a
/// crash in the suite's own process is a truncated run rather than a red test
/// (practices doc, shape 11).
@Test func anOffMainThreadQueryAnswersNothingAndDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let held = await MainActor.run { () -> MainThreadAnswer<(AppKitAccessibilityElement, AppKitAccessibilityBridge)> in
            let bridge = AppKitAccessibilityBridge(signal: ScriptedAccessibilitySignal(true),
                                                   poster: RecordingAccessibilityPoster())
            bridge.onRequest = { _ in true }
            bridge.publish(makeTree(roots: ["n"], [
                "n": Entry(node: node(.button, "live", children: ["c"], actions: [.press]), frame: rect(0, 0, 20, 20)),
                "c": Entry(node: node(.staticText, "child"), frame: rect(0, 0, 10, 10)),
            ]))
            let element = bridge.element(for: nid("n"))
            // The control: on the main thread the element answers.
            precondition(element.accessibilityLabel() == "live")
            precondition(element.accessibilityChildren()?.count == 1)
            precondition(element.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.accessibilityPerformPress)))
            precondition(element.accessibilityPerformPress())
            return MainThreadAnswer(value: (element, bridge))
        }
        let offMain = await Task.detached { () -> (Bool, String?, Int?, Bool, Bool) in
            let element = held.value.0
            return (pthread_main_np() != 0, element.accessibilityLabel(), element.accessibilityChildren()?.count,
                    element.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.accessibilityPerformPress)),
                    element.accessibilityPerformPress())
        }.value
        precondition(offMain.0 == false, "the query really ran off the main thread")
        precondition(offMain.1 == nil && offMain.2 == 0 && offMain.3 == false && offMain.4 == false)
        _ = held
    }
}
