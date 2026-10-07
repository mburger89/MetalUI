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
/// priority `Row` is 360 wide, its 80-wide label first and its prioritised
/// second child taking the other 280; the environment object's count is the
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
    // The label is framed 80 wide; the grower's own layers record under its
    // name (the name's first inner layer, `.child(of: name, at: 0)`).
    let row = try #require(bounds(PortGapsDemoIDs.priorityRow))
    let label = try #require(bounds(PortGapsDemoIDs.priorityLabel))
    let grower = try #require(b.first { $0.key.parent?.component == .named(ElementID(PortGapsDemoIDs.priorityGrower)) }?.value,
                              "the grower's layer")
    #expect([label.origin.x.value - row.origin.x.value, label.size.width.value] == [0, 80], "the label: \(label)")
    #expect([grower.origin.x.value - row.origin.x.value, grower.size.width.value] == [80, 280],
            "the prioritised grower takes the rest: \(grower)")

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

// MARK: - 3.6b–3.6f (lane 3 review)

/// A greedy root (it fills whatever it is offered, painted `.accent`) under a
/// toolbar of one navigation button.
@MainActor private func fillingTree(_ m: StripModel) -> some Element {
    Box {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.accent)
        .toolbar {
            ToolbarItem(placement: .navigation) { Button("Back") { m.pressed += 1 } }
        }
}

/// **3.6b** (`MD-K` item 2, divergence 136). A root that fills the window is
/// offered only the rect below the strip: in a 400 × 400 drawn-strip window
/// its bounds are exactly (0, 39, 400, 361). Review mutation **X7**: the root
/// proposed the window's whole height (it would be 400 tall, overlapping the
/// strip).
@MainActor
@Test func aGreedyRootIsOfferedOnlyTheRectBelowTheStrip() throws {
    let m = StripModel()
    let (window, _) = try stripWindow(drawn: true) { fillingTree(m) }
    window.drawFrameIfNeeded()
    let root = try #require(window.lastElementBounds[rootID])
    #expect([root.origin.x.value, root.origin.y.value, root.size.width.value, root.size.height.value]
                == [0, 39, 400, 361], "the greedy root: \(root)")
}

/// **3.6c** (`MD-K` items 1 and 4, `MD-Z` item 6). The strip paints: the
/// scene holds its `.surface` fill across (0, 0, 400, 39) and its 1-point
/// `.separator` line at y 38, both after the root's `.accent` fill in scene
/// order (painted above the root content), and its glyphs land within y 0…39.
/// Review mutations **X4** (the strip's paint call removed from
/// `Frame.render`) and **X8** (its `.background(.surface)` removed).
@MainActor
@Test func aDrawnToolbarStripPaintsAboveTheRoot() throws {
    let m = StripModel()
    let (window, platform) = try stripWindow(drawn: true) { fillingTree(m) }
    window.drawFrameIfNeeded()
    let rects = window.lastScene.rects
    func box(_ r: MUIRect) -> [Float] {
        [r.bounds.origin.x, r.bounds.origin.y, r.bounds.size.width, r.bounds.size.height]
    }
    let rootFill = try #require(rects.firstIndex {
        box($0) == [0, 39, 400, 361] && ixSame(ixHsla($0.background), window.theme[.accent])
    }, "the root's accent fill: \(rects.map(box))")
    let fill = rects.firstIndex {
        box($0) == [0, 0, 400, 39] && ixSame(ixHsla($0.background), window.theme[.surface])
    }
    let separator = rects.firstIndex {
        box($0) == [0, 38, 400, 1] && ixSame(ixHsla($0.background), window.theme[.separator])
    }
    #expect(fill != nil, "the strip's surface fill: \(rects.map(box))")
    #expect(separator != nil, "the strip's separator line: \(rects.map(box))")
    if let fill { #expect(fill > rootFill, "the fill painted above the root") }
    if let separator, let fill { #expect(separator > fill, "the separator above the fill") }
    let glyphs = window.lastScene.glyphs
    try #require(!glyphs.isEmpty, "the strip's Back label draws glyphs")
    let scale = platform.scaleFactor
    for g in glyphs {
        #expect(g.bounds.origin.y >= 0 && (g.bounds.origin.y + g.bounds.size.height) / scale <= 39,
                "a strip glyph within y 0…39: \(g.bounds)")
    }
}

/// **3.6d** (`MD-J` item 1, `MD-Z` item 3). A toolbar item disabled by its
/// declaring scope stays disabled in the drawn strip: a click at its centre
/// runs nothing, while the enabled sibling's click runs. Review mutation
/// **X3**: `ToolbarStripItem.body()` writes `.disabled(false)`.
@MainActor
@Test func aDisabledItemInTheDrawnStripRunsNothing() throws {
    let m = StripModel()
    let (window, platform) = try stripWindow(drawn: true) {
        Column {
            Text("a").frame(width: Pixels(100), height: Pixels(50)).toolbar {
                ToolbarItem(placement: .navigation) { Button("On") { m.pressed += 10 } }
            }
            Column {
                Text("b").frame(width: Pixels(100), height: Pixels(50)).toolbar {
                    ToolbarItem(id: "off") { Button("Off") { m.pressed += 1 } }
                }
            }
            .disabled(true)
        }
    }
    window.drawFrameIfNeeded()
    let strip = window.lastElementBounds.filter { isUnderStrip($0.key) && $0.key != ToolbarStrip.rootID }
    // The two buttons' outermost bounds: the leading one (On) and the
    // trailing one (Off), told apart by x.
    let boxes = window.lastHitboxes.filter { isUnderStrip($0.id) && $0.handlers.onClick != nil }
    let on = try #require(boxes.min { $0.bounds.origin.x.value < $1.bounds.origin.x.value }, "the On button")
    click(platform, at: centre(on.bounds))
    #expect(m.pressed == 10, "the enabled strip button runs: \(m.pressed)")
    // The Off button's bounds, from the element records (its hitbox may be gated away).
    let off = try #require(strip.values.filter { $0.origin.x.value > 200 && $0.size.height.value < 39 }
                                .max { $0.size.width.value < $1.size.width.value }, "the Off button's bounds")
    click(platform, at: centre(off))
    #expect(m.pressed == 10, "the scope-disabled strip button runs nothing: \(m.pressed)")
}

/// **3.6e** (`MD-K` item 3). Placement in the strip: the navigation item
/// leads (padded 8), the principal item is centred at x 200, and the trailing
/// field ends at 400 − 8. Review mutation **X6**: navigation items in the
/// trailing group.
@MainActor
@Test func drawnStripItemsArePlacedByPlacement() throws {
    let m = StripModel()
    let (window, _) = try stripWindow(drawn: true) {
        Text("Body").frame(width: Pixels(100), height: Pixels(50)).toolbar {
            ToolbarItem(placement: .navigation) { Button("Back") { m.pressed += 1 } }
            ToolbarItem(placement: .principal) { Button("Mid") { m.pressed += 100 } }
            ToolbarItem { Toggle("Advanced", isOn: binding({ m.advanced }, { m.advanced = $0 })) }
            ToolbarItem { TextField("Filter", text: binding({ m.filter }, { m.filter = $0 })).frame(width: Pixels(80)) }
        }
    }
    window.drawFrameIfNeeded()
    let boxes = window.lastHitboxes.filter { isUnderStrip($0.id) }
    let buttons = boxes.filter { $0.handlers.onClick != nil }.sorted { $0.bounds.origin.x.value < $1.bounds.origin.x.value }
    try #require(buttons.count >= 2, "Back and Mid hitboxes: \(buttons.count)")
    let back = buttons[0].bounds, mid = buttons[1].bounds
    let field = try #require(boxes.first { $0.handlers.textInput != nil }, "the field").bounds
    #expect(back.origin.x.value == 8, "the navigation item leads: \(back)")
    #expect(abs(mid.origin.x.value + mid.size.width.value / 2 - 200) <= 0.5, "the principal item centred: \(mid)")
    #expect(back.origin.x.value + back.size.width.value < field.origin.x.value, "Back before the field")
    #expect(abs(field.origin.x.value + field.size.width.value - 392) <= 0.5, "the field trails at 392: \(field)")
}

/// **3.6f** (`MD-Z` items 2 and 4). The strip's run comes before the root's,
/// so the window's deepest-level read-back is the root's own run (the native
/// window's figure for the same tree); and under `.contentMinSize` the
/// content minimum is the root's answer plus the strip's 39. Review mutations
/// **X1** (the strip's run after the root's) and **X2** (`plus: 0`).
@MainActor
@Test func theStripsRunIsNotTheRootsAndItsHeightJoinsTheContentMinimum() throws {
    let m = StripModel()
    let tree: @MainActor () -> some Element = {
        Text("Body").frame(width: Pixels(100), height: Pixels(50)).toolbar {
            ToolbarItem(placement: .navigation) { Button("Back") { m.pressed += 1 } }
            ToolbarItem { Toggle("Advanced", isOn: binding({ m.advanced }, { m.advanced = $0 })) }
        }
    }
    let (native, nativePlatform) = try stripWindow(drawn: false, content: tree)
    native.windowResizability = .contentMinSize
    native.drawFrameIfNeeded()
    let (drawn, drawnPlatform) = try stripWindow(drawn: true, content: tree)
    drawn.windowResizability = .contentMinSize
    drawn.drawFrameIfNeeded()
    #expect(drawn.lastNativeLayoutDeepestLevel == native.lastNativeLayoutDeepestLevel,
            "the root's own run: \(drawn.lastNativeLayoutDeepestLevel) vs \(native.lastNativeLayoutDeepestLevel)")
    let nativeMin = try #require(nativePlatform.contentSizeLimitCalls.last?.minimum, "native limits")
    let drawnMin = try #require(drawnPlatform.contentSizeLimitCalls.last?.minimum, "drawn limits")
    #expect(drawnMin.width == nativeMin.width && drawnMin.height.value == nativeMin.height.value + 39,
            "the minimum includes the strip: \(drawnMin) vs \(nativeMin)")
}
