import Testing
import Foundation
import Metal
import Observation
import MetalUICore
import MetalUIScene
import MetalUIPlatform
@testable import MetalUI
@testable import MetalUIDemoContent   // portGapsModel, portGapsDemoSection (internal)

// Port gaps (medium), lane 3 — the drawn toolbar strip and the demo: tests
// 3.6–3.8, 3.10 and 3.16 (3.9 is an arm of
// `everyNamingSiteStartsAReturningNameFresh`, `ExplicitIdentityTests.swift`).
// Rulings `MD-K`, `MD-M` and `MD-Z`; spec
// `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md` §3.3 item 4,
// §4.3, §6.
//
// A window over `FakePlatformWindow` with `toolbarIsNative = false` stands for
// SDL: `setToolbar` answers `false`, so the window draws its toolbar as a
// 39-point strip across its top, laid out in its own run under the named root
// `$toolbar`, and lays the root out in the rect below it. Red before: the file
// does not compile at `c70f639` (no `ToolbarStrip`, no `portGapsDemoSection`).

@Observable @MainActor private final class StripModel {
    var pressed = 0
    var rootPresses = 0
    var advanced = false
    var filter = ""
    var showsToolbar = true
    var extra = false
}

@MainActor private func binding<V>(_ get: @escaping @MainActor () -> V,
                                   _ set: @escaping @MainActor (V) -> Void) -> Binding<V> {
    Binding(get: get, set: set)
}

/// A root with a fixed-size body, a focusable root button and a toolbar of a
/// leading button, an optional item, a toggle and a field.
@MainActor private func stripTree(_ m: StripModel) -> some Element {
    Column {
        if m.showsToolbar {
            Text("Body")
                .frame(width: Pixels(100), height: Pixels(50))
                .toolbar {
                    ToolbarItem(placement: .navigation) { Button("Back") { m.pressed += 1 } }
                    if m.extra {
                        ToolbarItem(id: "extra") { Button("Extra") { m.pressed += 100 } }
                    }
                    ToolbarItem { Toggle("Advanced", isOn: binding({ m.advanced }, { m.advanced = $0 })) }
                    ToolbarItem { TextField("Filter", text: binding({ m.filter }, { m.filter = $0 })) }
                }
        } else {
            Text("Body").frame(width: Pixels(100), height: Pixels(50))
        }
        Button("Root") { m.rootPresses += 1 }
    }
}

/// A fake window `size` square; `drawn` makes the platform decline toolbars.
@MainActor private func stripWindow<Root: Element>(drawn: Bool, size: Int = 400,
                                                   _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: size, content: content)
    platform.toolbarIsNative = !drawn
    window.recordsElementBounds = true
    return (window, platform)
}

/// Whether `id` is the strip's root or lies under it.
@MainActor private func isUnderStrip(_ id: GlobalElementID) -> Bool {
    var cursor: GlobalElementID? = id
    while let current = cursor {
        if current == ToolbarStrip.rootID { return true }
        cursor = current.parent
    }
    return false
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: Pixels(b.origin.x.value + b.size.width.value / 2), y: Pixels(b.origin.y.value + b.size.height.value / 2))
}

@MainActor private func click(_ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

// MARK: - 3.6

/// **3.6** (`MD-K` items 1–3). A 400 × 400 window whose platform declines its
/// toolbar draws the strip within y 0…39 (its root exactly 400 × 39); the
/// root is laid out in the rect below — its bounds start at y ≥ 39, at most
/// 361 tall, centred in (0, 39, 400, 361) — and every root-tree id is the one
/// a window with a native toolbar records. Mutation **M3.6**: the strip's
/// height 0.
@MainActor
@Test func aDrawnToolbarStripSitsAboveTheRootAndKeepsItsIds() throws {
    let m = StripModel()
    let (native, _) = try stripWindow(drawn: false) { stripTree(m) }
    native.drawFrameIfNeeded()
    let (drawn, _) = try stripWindow(drawn: true) { stripTree(m) }
    drawn.drawFrameIfNeeded()

    let strip = drawn.lastElementBounds.filter { isUnderStrip($0.key) }
    try #require(strip.count >= 4, "the strip's root and its items recorded: \(strip.count)")
    let stripRoot = try #require(strip[ToolbarStrip.rootID])
    #expect([stripRoot.origin.x.value, stripRoot.origin.y.value, stripRoot.size.width.value,
             stripRoot.size.height.value] == [0, 0, 400, 39], "the strip: \(stripRoot)")
    for (id, b) in strip {
        #expect(b.origin.y.value >= 0 && b.origin.y.value + b.size.height.value <= 39,
                "a strip element within y 0…39: \(id) \(b)")
    }

    let root = try #require(drawn.lastElementBounds[rootID])
    let nativeRoot = try #require(native.lastElementBounds[rootID])
    #expect(root.size == nativeRoot.size, "the root's answer is unchanged: \(root) vs \(nativeRoot)")
    #expect(root.origin.y.value >= 39 && root.size.height.value <= 361, "below the strip: \(root)")
    #expect(abs(root.origin.y.value - (39 + (361 - root.size.height.value) / 2)) <= 0.5,
            "centred in the rect below the strip: \(root)")
    #expect(abs(root.origin.x.value - (400 - root.size.width.value) / 2) <= 0.5, "centred across: \(root)")

    let rootIDs = Set(drawn.lastElementBounds.keys.filter { !isUnderStrip($0) })
    try #require(rootIDs.count >= 3)
    #expect(rootIDs == Set(native.lastElementBounds.keys), "the root tree's ids are the native window's")
}

// MARK: - 3.7

/// **3.7** (`MD-K` item 5). The fake's first presented frame already shows
/// the strip — one present, two builds (the strip's presence changed after
/// the first) — and the root is below it; adding an item shows in the same
/// presented frame with one build; removing the toolbar puts the root back in
/// the whole window in the same presented frame, with no extra build either.
/// Mutation **M3.7**: no extra build.
@MainActor
@Test func aDrawnToolbarIsInTheFirstPresentedFrame() throws {
    let m = StripModel()
    let (window, platform) = try stripWindow(drawn: true) { stripTree(m) }
    window.drawFrameIfNeeded()
    #expect(platform.fakeSurface.presentCalls == 1, "one presented frame")
    #expect(window.lastDrawBuildCount == 2, "the strip's appearance costs one extra build")
    let before = window.lastElementBounds.keys.filter(isUnderStrip).count
    #expect(before >= 4, "the first presented frame shows the strip: \(before) strip ids")
    let root = try #require(window.lastElementBounds[rootID])
    #expect(root.origin.y.value >= 39, "the first presented frame lays the root out below it: \(root)")

    m.extra = true
    window.drawFrameIfNeeded()
    #expect(platform.fakeSurface.presentCalls == 2)
    #expect(window.lastDrawBuildCount == 1, "a changed strip costs no extra build")
    let after = window.lastElementBounds.keys.filter(isUnderStrip).count
    #expect(after > before, "the added item is in the same presented frame: \(before) → \(after)")

    m.showsToolbar = false
    window.drawFrameIfNeeded()
    #expect(window.lastDrawBuildCount == 1, "the strip leaving costs no extra build")
    #expect(window.lastElementBounds.keys.filter(isUnderStrip).isEmpty, "no strip once the toolbar left")
    let full = try #require(window.lastElementBounds[rootID])
    #expect(abs(full.origin.y.value - (400 - full.size.height.value) / 2) <= 0.5,
            "the root back in the whole window in the same presented frame: \(full)")
}

// MARK: - 3.8

/// **3.8** (`MD-K` item 4). Strip controls are ordinary controls: a click at
/// the strip's leading `Button` runs its action directly (no toolbar action
/// queued); the tab order holds every root focusable before every strip one;
/// a click on the strip's field focuses it, typing writes its binding, and its
/// edit state (the caret after what was typed) survives frames. Mutation
/// **M3.8**: the strip not prepainted (no hitboxes).
@MainActor
@Test func aDrawnToolbarControlIsAnOrdinaryControl() throws {
    let m = StripModel()
    let (window, platform) = try stripWindow(drawn: true) { stripTree(m) }
    window.drawFrameIfNeeded()

    let stripBoxes = window.lastHitboxes.filter { isUnderStrip($0.id) }
    try #require(stripBoxes.count >= 3, "the strip's controls registered hitboxes: \(stripBoxes.count)")
    let back = try #require(stripBoxes.first { $0.handlers.onClick != nil }, "the Back button's hitbox")
    #expect(back.bounds.origin.x.value < 100, "the navigation item is leading: \(back.bounds)")
    click(platform, at: centre(back.bounds))
    #expect(m.pressed == 1, "a click on the strip button runs it directly: \(m.pressed)")

    let order = window.lastFocusRegistry.tabOrder
    let rootStops = order.indices.filter { !isUnderStrip(order[$0]) }
    let stripStops = order.indices.filter { isUnderStrip(order[$0]) }
    try #require(!rootStops.isEmpty && stripStops.count >= 3, "tab order: \(order.count)")
    #expect(rootStops.max()! < stripStops.min()!, "Tab reaches the strip after the root")

    let field = try #require(window.lastHitboxes.first { isUnderStrip($0.id) && $0.handlers.textInput != nil },
                             "the strip field's hitbox")
    click(platform, at: centre(field.bounds))
    #expect(window.focusedElement.map(isUnderStrip) == true, "a click focuses the strip's field")
    platform.simulateInput(.textInput("q"))
    #expect(m.filter == "q", "typing writes the strip field's binding: \(m.filter)")
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    platform.simulateInput(.textInput("r"))
    #expect(m.filter == "qr", "the caret survived the frames: \(m.filter)")
}

// MARK: - 3.10

/// **3.10** (`MD-K` item 6). A window whose platform would decline a toolbar
/// but whose tree declares none is today's window: no `setToolbar` call, one
/// build, no strip id, and the scene's one rect where `d48b26d` put it — a
/// 100 × 50 box centred in 400 × 400 at (150, 175). Green before (pin).
/// Mutation **M3.10**: an unconditional extra build.
@MainActor
@Test func aWindowWithoutAToolbarIsUnchanged() throws {
    let (window, platform) = try stripWindow(drawn: true) {
        Column { Box {}.frame(width: Pixels(100), height: Pixels(50)).background(.accent) }
    }
    window.drawFrameIfNeeded()
    #expect(platform.toolbars.isEmpty, "no setToolbar call")
    #expect(window.lastDrawBuildCount == 1, "one build")
    #expect(window.lastElementBounds.keys.filter(isUnderStrip).isEmpty, "no strip")
    let rects = window.lastScene.rects.map {
        [$0.bounds.origin.x, $0.bounds.origin.y, $0.bounds.size.width, $0.bounds.size.height]
    }
    #expect(rects == [[150, 175, 100, 50]], "the scene's rects: \(rects)")
}

// MARK: - 3.16

/// **3.16** (`MD-M`). The controls demo, in a fake 920 × 560 window whose
/// platform shows toolbars natively (the audit's window), holds the port-gaps
/// section: its five fields are 24, 24, 24, a line (16) and 24 tall; the
/// priority `Row` is 360 wide and its prioritised second child takes what its
/// first child's ideal leaves; the environment object's count is the
/// `Component`'s text (read from the published accessibility tree); the
/// window's toolbar has five items (Back, the picker, Advanced, Share and the
/// search field). Mutation **M3.16**: the section's `.environment(_:)` given
/// `nil` — the `Component` reads its optional object and shows "no model", so
/// the text arm reddens by name with no trap.
@MainActor
@Test func theControlsDemoShowsThePortGapsSection() throws {
    portGapsModel.count = 3
    defer { portGapsModel.count = 0 }
    let preflight = LayoutDifferential.render(width: 920, height: 560) { controlsDemoContent() }
    try #require(preflight.unlowerableFields.isEmpty, "\(preflight.unlowerableFields)")
    let (window, platform) = try stripWindow(drawn: false, size: 920) { controlsDemoContent() }
    platform.simulateResize(to: Size(width: Pixels(920), height: Pixels(560)))
    window.drawFrameIfNeeded()

    let b = window.lastElementBounds
    func bounds(_ key: String) -> Bounds<Pixels>? {
        b.first { $0.key.component == .named(ElementID(key)) }?.value
    }
    #expect(PortGapsDemoIDs.fields.map { bounds($0)?.size.height.value } == [24, 24, 24, 16, 24],
            "the five fields' heights")
    #expect(bounds(PortGapsDemoIDs.priorityRow)?.size.width.value == 360, "the priority row is 360 wide")
    let label = try #require(bounds(PortGapsDemoIDs.priorityLabel)?.size.width.value)
    let grower = try #require(bounds(PortGapsDemoIDs.priorityGrower)?.size.width.value)
    #expect(abs(label + grower - 360) <= 0.5 && grower > label,
            "the prioritised child takes the rest: \(label) + \(grower)")

    let toolbar = try #require(platform.toolbars.last ?? nil, "the demo's toolbar reached the platform")
    #expect(toolbar.items.count == 5, "Back, the picker, Advanced, Share, search: \(toolbar.items.map(\.id))")

    platform.simulateAccessibilityRequest(.activate)
    for _ in 0..<3 {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    let tree = try #require(platform.publishedAccessibilityTrees.last, "no tree published")
    let values = tree.nodes.values.compactMap { $0.value }
    #expect(values.contains("Environment object: 3"), "the Component reads the environment object")
}
