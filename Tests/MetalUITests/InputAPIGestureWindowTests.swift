import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Input APIs, lane 2 — the new gestures' `Window` integration (rulings `CI-B`,
// `CI-D`, `CI-E`, `CI-F`, `CI-R`, `CI-V` item 4; spec
// `docs/superpowers/specs/2026-10-08-input-apis-design.md` §4.2 2.21–2.24 and
// §4.3 3.1, 3.26–3.34, which `CI-W` moved to lane 2 with their ids kept).
//
// Everything runs through a real `Window` on a `FakePlatformWindow` — nothing
// sleeps. Geometry, unless a test says otherwise: a 300 × 300 window whose
// 200 × 200 root is centred at (50, 50)–(250, 250) (`CN-J`), so a window point
// (x, y) is the root's local point (x − 50, y − 50). `presentsMenusNatively`
// is `true` (AppKit's answer: a presented menu is recorded in
// `presentedMenus`) unless a test draws the menu in the window.

// MARK: - Fixtures

@MainActor
private final class WLog {
    var entries: [String] = []
    var points: [Point<Pixels>] = []
    var locations: [Point<Pixels>?] = []
    var shown = true
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private func ldown(_ x: Float, _ y: Float, count: Int = 1) -> InputEvent {
    .mouseDown(MouseEvent(position: pt(x, y), clickCount: count))
}
private func lup(_ x: Float, _ y: Float, count: Int = 1) -> InputEvent {
    .mouseUp(MouseEvent(position: pt(x, y), clickCount: count))
}
private func moved(_ x: Float, _ y: Float) -> InputEvent { .mouseMoved(MouseEvent(position: pt(x, y))) }
private func rdown(_ x: Float, _ y: Float) -> InputEvent {
    .rightMouseDown(MouseEvent(position: pt(x, y), buttonNumber: 1))
}
private func rdrag(_ x: Float, _ y: Float) -> InputEvent {
    .rightMouseDragged(MouseEvent(position: pt(x, y), buttonNumber: 1))
}
private func rup(_ x: Float, _ y: Float) -> InputEvent {
    .rightMouseUp(MouseEvent(position: pt(x, y), buttonNumber: 1))
}
private func odown(_ x: Float, _ y: Float, button: Int = 2) -> InputEvent {
    .otherMouseDown(MouseEvent(position: pt(x, y), buttonNumber: button))
}
private func odrag(_ x: Float, _ y: Float, button: Int = 2) -> InputEvent {
    .otherMouseDragged(MouseEvent(position: pt(x, y), buttonNumber: button))
}
private func oup(_ x: Float, _ y: Float, button: Int = 2) -> InputEvent {
    .otherMouseUp(MouseEvent(position: pt(x, y), buttonNumber: button))
}
private func magnify(_ delta: Double, _ phase: InputPhase, at p: Point<Pixels> = pt(150, 150)) -> InputEvent {
    .magnify(MagnifyEvent(position: p, magnification: delta, phase: phase))
}
private func rotate(_ degrees: Double, _ phase: InputPhase, at p: Point<Pixels> = pt(150, 150)) -> InputEvent {
    .rotate(RotateEvent(position: p, rotation: degrees, phase: phase))
}
private func key(_ c: String, _ mods: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: mods, timestamp: 0))
}

/// A `size` × `size` window over `content`, drawn until clean. **A `Window` is
/// held only weakly by its platform window**, so every test keeps the window
/// to its end (`withExtendedLifetime`).
@MainActor
private func inputWindow<Root: Element>(size: Int = 300, native: Bool = true,
                                        _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: size, content: content)
    platform.presentsMenusNatively = native
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return (window, platform)
}

@MainActor private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// The root's 200 × 200 frame at (50, 50), required as an opaque hitbox — the
/// geometry every coordinate below is written against.
@MainActor
private func requireRootTarget(_ window: Window, sourceLocation: SourceLocation = #_sourceLocation) throws {
    let want = "\(Bounds(origin: pt(50, 50), size: Size(width: px(200), height: px(200))))"
    try #require(window.lastHitboxes.contains { $0.opaque && "\($0.bounds)" == want },
                 "the root target at (50, 50): \(window.lastHitboxes.map(\.bounds))", sourceLocation: sourceLocation)
}

/// A 200 × 200 legacy box.
@MainActor private func square() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(200), height: px(200))
}

/// A 200 × 200 proposal rectangle.
@MainActor private func proposalSquare() -> some ProposalElementGroup {
    Rectangle().frame(width: px(200), height: px(200))
}

private func close(_ a: Point<Pixels>?, _ b: Point<Pixels>) -> Bool {
    guard let a else { return false }
    return abs(a.x.value - b.x.value) < 0.01 && abs(a.y.value - b.y.value) < 0.01
}

// MARK: - 3.1: tap location on both vocabularies

/// **3.1** (probe `T3`, `CI-B` item 2). `.onTapGesture { location in … }`
/// runs on both vocabularies with the release point in the element's local
/// space: a tap at (60, 70) on the root at (50, 50) hands (10, 20). Mutation:
/// the proposal overload passes `.global` → (60, 70).
@MainActor
@Test func onTapGestureWithALocationRunsOnBothVocabulariesInLocalSpace() throws {
    let log = WLog()
    let (legacy, legacyPlatform) = try inputWindow { square().onTapGesture { log.points.append($0) } }
    try requireRootTarget(legacy)
    legacyPlatform.simulateInput(ldown(60, 70))
    #expect(legacyPlatform.simulateInput(lup(60, 70)), "a release that ran a callback is claimed")
    let (proposal, proposalPlatform) = try inputWindow { proposalSquare().onTapGesture { log.points.append($0) } }
    try requireRootTarget(proposal)
    proposalPlatform.simulateInput(ldown(60, 70))
    proposalPlatform.simulateInput(lup(60, 70))
    #expect(log.points == [pt(10, 20), pt(10, 20)], "\(log.points)")
    withExtendedLifetime((legacy, proposal)) {}
}

// MARK: - 3.26–3.30, 3.32: the button arena

/// **3.26** (`CI-E` item 2, `CI-F` item 3). A middle drag reaches only a
/// middle-button `DragGesture`: the primary drag, the tap and the `onClick`
/// on the same chain run nothing, `active` and focus do not move, the live
/// arena claims its press; a back-button press with no leaf for button 3 is
/// not claimed. Mutation: form the press arena for `.otherMouseDown`.
@MainActor
@Test func aMiddleDragReachesOnlyAMiddleButtonDragGesture() throws {
    let log = WLog()
    let (window, platform) = try inputWindow {
        square()
            .onClick { log.entries.append("click") }
            .onTapGesture { log.entries.append("tap") }
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in log.entries.append("primary") })
            .gesture(DragGesture(button: .middle)
                .onChanged { log.entries.append("middle \(Int($0.translation.width.value)),\(Int($0.translation.height.value))") }
                .onEnded { _ in log.entries.append("middle end") })
    }
    try requireRootTarget(window)
    let focused = window.focusedElement
    #expect(platform.simulateInput(odown(150, 150)), "a live button arena claims its press")
    #expect(window.active == nil, "an other press never moves `active`")
    platform.simulateInput(odrag(158, 150))
    platform.simulateInput(odrag(165, 150))
    platform.simulateInput(oup(165, 150))
    #expect(log.entries == ["middle 15,0", "middle end"], "\(log.entries)")
    #expect(window.active == nil && window.focusedElement == focused)
    #expect(!platform.simulateInput(odown(150, 150, button: 3)), "no leaf for button 3: no arena, not claimed")
    platform.simulateInput(oup(150, 150, button: 3))
    #expect(log.entries == ["middle 15,0", "middle end"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **3.27** (`CI-F` item 4). A secondary drag opens no context menu: the press
/// opens nothing, 5 pt reports nothing, past 10 pt `onChanged`, the release
/// `onEnded` and still no menu. Mutation: open on the press regardless.
@MainActor
@Test func aSecondaryDragOpensNoContextMenu() throws {
    let log = WLog()
    let (window, platform) = try inputWindow {
        square()
            .contextMenu { Button("A") {} }
            .gesture(DragGesture(button: .secondary)
                .onChanged { log.entries.append("changed \(Int($0.translation.width.value))") }
                .onEnded { _ in log.entries.append("ended") })
    }
    try requireRootTarget(window)
    platform.simulateInput(rdown(150, 150))
    #expect(platform.presentedMenus.isEmpty && window.menuSession == nil, "nothing at the press")
    platform.simulateInput(rdrag(155, 150))
    #expect(log.entries.isEmpty, "5 pt: under the minimum")
    platform.simulateInput(rdrag(162, 150))
    #expect(log.entries == ["changed 12"])
    platform.simulateInput(rup(162, 150))
    #expect(log.entries == ["changed 12", "ended"])
    #expect(platform.presentedMenus.isEmpty && window.menuSession == nil, "a right-drag opens no menu")
    withExtendedLifetime(window) {}
}

/// **3.28** (`CI-F` item 4). With a secondary drag declared, a secondary click
/// (a move under the minimum) opens the menu on the release, at the press
/// point; the drag reports nothing. Mutation: never open the deferred menu.
@MainActor
@Test func aSecondaryClickWithASecondaryDragDeclaredOpensTheMenuOnRelease() throws {
    let log = WLog()
    let (window, platform) = try inputWindow {
        square()
            .contextMenu { Button("A") {} }
            .gesture(DragGesture(button: .secondary).onChanged { _ in log.entries.append("changed") })
    }
    try requireRootTarget(window)
    platform.simulateInput(rdown(150, 150))
    platform.simulateInput(rdrag(153, 150))
    #expect(platform.presentedMenus.isEmpty, "deferred while the drag may still begin")
    platform.simulateInput(rup(153, 151))
    try #require(platform.presentedMenus.count == 1, "opened on the release")
    #expect(platform.presentedMenus[0].at == pt(150, 150), "at the press point")
    #expect(platform.presentedMenus[0].menu.items.map(\.title) == ["A"])
    #expect(log.entries.isEmpty)
    withExtendedLifetime(window) {}
}

/// **3.29** (`MN-E`, green before). Without a secondary drag on the chain — a
/// primary `DragGesture` only — the menu still opens on the press. Mutation:
/// always defer.
@MainActor
@Test func withoutASecondaryDragTheMenuStillOpensOnThePress() throws {
    let (window, platform) = try inputWindow {
        square().contextMenu { Button("A") {} }.gesture(DragGesture().onChanged { _ in })
    }
    try requireRootTarget(window)
    platform.simulateInput(rdown(150, 150))
    #expect(platform.presentedMenus.count == 1, "opened on the press")
    withExtendedLifetime(window) {}
}

/// **3.30** (`MN-B`, `CI-E` item 2). Secondary and other presses still never
/// press, tap or drag primary gestures: a right and a middle press-drag-release
/// over an `onClick`, a tap and a primary `minimumDistance: 0` drag run
/// nothing, and `active` stays `nil`. Mutation: let a button arena include
/// primary drags.
@MainActor
@Test func secondaryAndOtherPressesStillNeverPressTapOrDragPrimaryGestures() throws {
    let log = WLog()
    let (window, platform) = try inputWindow {
        square()
            .onClick { log.entries.append("click") }
            .onTapGesture { log.entries.append("tap") }
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in log.entries.append("drag") })
    }
    try requireRootTarget(window)
    platform.simulateInput(rdown(150, 150))
    #expect(window.active == nil)
    platform.simulateInput(rdrag(170, 150))
    platform.simulateInput(rup(170, 150))
    platform.simulateInput(odown(150, 150))
    #expect(window.active == nil)
    platform.simulateInput(odrag(170, 150))
    platform.simulateInput(oup(170, 150))
    #expect(log.entries.isEmpty, "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **3.32** (`CI-F` item 3). A middle drag during a pending primary tap
/// sequence disturbs neither: a double tap's first click, a whole middle drag,
/// then the second click — the drag reports and the double tap still ends.
/// Mutation: one shared arena.
@MainActor
@Test func aMiddleDragDuringAPendingPrimaryTapSequenceDisturbsNeither() throws {
    let log = WLog()
    let (window, platform) = try inputWindow {
        square()
            .onTapGesture(count: 2) { log.entries.append("double") }
            .gesture(DragGesture(button: .middle)
                .onChanged { _ in log.entries.append("middle") }
                .onEnded { _ in log.entries.append("middle end") })
    }
    try requireRootTarget(window)
    platform.simulateInput(ldown(150, 150, count: 1))
    platform.simulateInput(lup(150, 150, count: 1))
    platform.simulateInput(odown(150, 150))
    platform.simulateInput(odrag(170, 150))
    platform.simulateInput(oup(170, 150))
    platform.simulateInput(ldown(150, 150, count: 2))
    platform.simulateInput(lup(150, 150, count: 2))
    #expect(log.entries == ["middle", "middle end", "double"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

// MARK: - 3.31: popovers and the in-window menu

/// `anchor` (`width` × `height`) with its top-left corner at (`left`, `top`)
/// in a 400 × 400 root of legacy spacers (no gap).
@MainActor private func at<A: Element>(top: Float, left: Float, width: Float, height: Float,
                                       _ anchor: A) -> some StyledElement {
    Column {
        Box().frame(width: px(1), height: px(top))
        Row {
            Box().frame(width: px(left), height: px(1))
            anchor
            Box().frame(width: px(400 - left - width), height: px(1))
        }
        Box().frame(width: px(1), height: px(400 - top - height))
    }
}

/// **3.31** (`MN-Y`, `MN-F` item 3; spec §1.4 item 3). An other-button press
/// outside a popover dismisses it and passes on (a middle drag beneath sees
/// the press); an open in-window menu takes other presses and releases inside
/// it, magnify and rotate events (the gestures beneath see none), and an
/// outside other press dismisses it, consumed with its release. Mutation:
/// `dispatchMenuSession` answers `false` for the new cases.
@MainActor
@Test func anOtherPressDismissesAPopoverAndAnOpenInWindowMenuTakesItAndPinches() throws {
    let log = WLog()
    let shown = Binding(get: { log.shown }, set: { log.shown = $0; log.entries.append("shown=\($0)") })
    let (popoverWindow, popoverPlatform) = try inputWindow(size: 400) {
        at(top: 190, left: 180, width: 40, height: 20,
           Box().frame(width: px(40), height: px(20)).popover(isPresented: shown) {
               Box().frame(width: px(100), height: px(50))
           })
            .frame(width: px(400), height: px(400))
            .gesture(DragGesture(minimumDistance: 0, button: .middle).onChanged { _ in log.entries.append("under") })
    }
    try #require(popoverWindow.lastOpenPopovers.count == 1, "the popover is open")
    popoverPlatform.simulateInput(odown(20, 20))
    #expect(log.entries == ["shown=false", "under"], "dismissed, then passed on: \(log.entries)")
    popoverPlatform.simulateInput(oup(20, 20))

    log.entries = []
    let (menuWindow, menuPlatform) = try inputWindow(native: false) {
        square()
            .contextMenu { Button("A") { log.entries.append("A") } }
            .gesture(MagnifyGesture().onChanged { _ in log.entries.append("magnify") })
            .gesture(RotateGesture().onChanged { _ in log.entries.append("rotate") })
            .gesture(DragGesture(minimumDistance: 0, button: .middle).onChanged { _ in log.entries.append("middle") })
    }
    try requireRootTarget(menuWindow)
    menuPlatform.simulateInput(rdown(150, 150))
    menuPlatform.simulateInput(rup(150, 150))
    let session = try #require(menuWindow.menuSession, "the drawn menu is open")
    try #require(!session.isNative && !session.levels.isEmpty)
    let frame = session.levels[0].frame
    let inside = pt(frame.origin.x.value + 5, frame.origin.y.value + 5)
    try #require(!frame.contains(pt(60, 60)), "set up: (60, 60) is outside the menu: \(frame)")
    #expect(menuPlatform.simulateInput(.otherMouseDown(MouseEvent(position: inside, buttonNumber: 2))),
            "an other press inside is taken")
    #expect(menuPlatform.simulateInput(.otherMouseUp(MouseEvent(position: inside, buttonNumber: 2))),
            "and its release")
    #expect(menuPlatform.simulateInput(magnify(0, .began)), "a magnify is taken")
    #expect(menuPlatform.simulateInput(magnify(0.2, .changed)))
    #expect(menuPlatform.simulateInput(rotate(0, .began)), "a rotate is taken")
    #expect(menuPlatform.simulateInput(rotate(20, .changed)))
    #expect(menuWindow.menuSession != nil, "still open")
    #expect(menuPlatform.simulateInput(odown(60, 60)), "an outside other press is consumed")
    #expect(menuWindow.menuSession == nil, "and dismisses")
    #expect(menuPlatform.simulateInput(oup(60, 60)), "with its release")
    #expect(log.entries.isEmpty, "nothing beneath saw them: \(log.entries)")
    withExtendedLifetime((popoverWindow, menuWindow)) {}
}

// MARK: - 3.33–3.34: the pinch arena

/// A `Component` whose 200 × 200 legacy box writes its `@State` from a magnify.
private struct MagnifyingBox: Component {
    @State var scale = 1.0
    var content: some ElementGroup {
        Box().frame(width: Pixels(200), height: Pixels(200))
            .gesture(MagnifyGesture().onChanged { scale = $0.magnification })
    }
}

/// The same over proposal content.
private struct MagnifyingRectangle: Component, ProposalElementGroup {
    @State var scale = 1.0
    var content: some ProposalElementGroup {
        Rectangle().frame(width: Pixels(200), height: Pixels(200))
            .gesture(MagnifyGesture().onChanged { scale = $0.magnification })
    }
}

/// **3.33** (`CI-D` items 1, 5). A magnify event reaches the `MagnifyGesture`
/// under the EVENT's position — the pointer last rested outside the element —
/// on both vocabularies, its `@State` write landing under `StateDispatch`;
/// the event is claimed. Mutation: form the pinch arena at the last mouse
/// position instead of the event's.
@MainActor
@Test func aMagnifyEventReachesTheMagnifyGestureUnderThePointer() throws {
    let (legacy, legacyPlatform) = try inputWindow { Column { MagnifyingBox() } }
    let (proposal, proposalPlatform) = try inputWindow { VStack { MagnifyingRectangle() } }
    for (window, platform) in [(legacy, legacyPlatform), (proposal, proposalPlatform)] {
        try requireRootTarget(window)
        let target = try #require(window.lastHitboxes.first { !$0.handlers.gestures.isEmpty })
        let component = try #require(target.id.parent)
        func scale() -> Double? {
            window.stateTable.peek(GlobalElementID.child(of: component, at: 0, name: ElementID("$state0")),
                                   as: Double.self)
        }
        platform.simulateInput(moved(10, 10))
        #expect(platform.simulateInput(magnify(0, .began)), "a live pinch arena claims the event")
        platform.simulateInput(magnify(0.25, .changed))
        #expect(scale() == 1.25, "the @State write landed: \(String(describing: scale()))")
        platform.simulateInput(magnify(0, .ended))
    }
    withExtendedLifetime((legacy, proposal)) {}
}

/// **3.34** (`CI-D` item 6, `OM-AK`). A pinch rides the pointer hitbox, so
/// `.disabled(true)` and `.allowsHitTesting(false)` withdraw it — nothing runs
/// and the event is not claimed — while the same element without either
/// magnifies (the separating arm). No mutation of its own: it reddens with a
/// gate mutation in `Frame.registerHandlers` (recorded).
@MainActor
@Test func aPinchIsWithdrawnByDisabledAndAllowsHitTesting() throws {
    let log = WLog()
    func magnifying() -> ModifiedElement<Box<EmptyGroup>> {
        square().gesture(MagnifyGesture().onChanged { _ in log.entries.append("magnify") })
    }
    let (disabled, disabledPlatform) = try inputWindow { Column { magnifying().disabled(true) } }
    let (untestable, untestablePlatform) = try inputWindow { Column { magnifying().allowsHitTesting(false) } }
    let (control, controlPlatform) = try inputWindow { magnifying() }
    for platform in [disabledPlatform, untestablePlatform] {
        #expect(!platform.simulateInput(magnify(0, .began)), "withdrawn: not claimed")
        platform.simulateInput(magnify(0.2, .changed))
    }
    #expect(log.entries.isEmpty, "\(log.entries)")
    controlPlatform.simulateInput(magnify(0, .began))
    controlPlatform.simulateInput(magnify(0.2, .changed))
    #expect(log.entries == ["magnify"], "the control magnifies: \(log.entries)")
    withExtendedLifetime((disabled, untestable, control)) {}
}

// MARK: - 2.21–2.24: the located context menu (`CI-R`)

/// **2.21** (`CI-R` item 3). A located context menu receives the secondary
/// press's point in the contextual region's local space, on both
/// vocabularies: a press at (60, 80) on the root at (50, 50) hands (10, 30).
/// Mutation: pass the window point.
@MainActor
@Test func aLocatedContextMenuReceivesThePressPointInLocalSpace() throws {
    let log = WLog()
    let (legacy, legacyPlatform) = try inputWindow {
        square().contextMenu { p in
            let _ = log.locations.append(p)
            Button("A") {}
        }
    }
    let (proposal, proposalPlatform) = try inputWindow {
        proposalSquare().contextMenu { p in
            let _ = log.locations.append(p)
            Button("A") {}
        }
    }
    let want = "\(Bounds(origin: pt(50, 50), size: Size(width: px(200), height: px(200))))"
    for window in [legacy, proposal] {
        try #require(window.lastHitboxes.contains { !$0.opaque && $0.handlers.contextual != nil && "\($0.bounds)" == want },
                     "the contextual region at (50, 50): \(window.lastHitboxes.map(\.bounds))")
    }
    legacyPlatform.simulateInput(rdown(60, 80))
    proposalPlatform.simulateInput(rdown(60, 80))
    #expect(legacyPlatform.presentedMenus.count == 1 && proposalPlatform.presentedMenus.count == 1)
    #expect(log.locations == [pt(10, 30), pt(10, 30)], "\(log.locations)")
    withExtendedLifetime((legacy, proposal)) {}
}

/// **2.22** (`CI-R` item 3, `CI-F` item 4). A deferred located menu receives the
/// PRESS point, not the release: a secondary drag declared, press (60, 80),
/// release (63, 81) under its minimum → the menu opens at the release, at the
/// press point, handed (10, 30). Mutation: pass the release point.
@MainActor
@Test func aDeferredLocatedMenuReceivesThePressPointNotTheRelease() throws {
    let log = WLog()
    let (window, platform) = try inputWindow {
        square()
            .contextMenu { p in
                let _ = log.locations.append(p)
                Button("A") {}
            }
            .gesture(DragGesture(button: .secondary).onChanged { _ in })
    }
    try requireRootTarget(window)
    platform.simulateInput(rdown(60, 80))
    platform.simulateInput(rdrag(63, 81))
    #expect(log.locations.isEmpty, "deferred")
    platform.simulateInput(rup(63, 81))
    try #require(platform.presentedMenus.count == 1)
    #expect(platform.presentedMenus[0].at == pt(60, 80))
    #expect(log.locations == [pt(10, 30)], "\(log.locations)")
    withExtendedLifetime(window) {}
}

/// **2.23** (`CI-R` item 3, `MN-G`, C11). A keyboard open (Shift-F10 off
/// Apple) and an accessibility show-menu pass no location: there is no
/// pointer. Mutation: pass the region's origin.
@MainActor
@Test func aKeyboardOrAccessibilityOpenPassesNoLocation() throws {
    let log = WLog()
    let (keyboard, keyboardPlatform) = try inputWindow {
        square().focusable().contextMenu { p in
            let _ = log.locations.append(p)
            Button("A") {}
        }
    }
    keyboard.contextMenuKeyPlatform = .other
    let id = try #require(keyboard.lastContextMenus.keys.first, "the menu is recorded")
    keyboard.focus(id)
    redraw(keyboard)
    try #require(keyboard.focusedElement == id)
    #expect(keyboardPlatform.simulateInput(key("\u{f70d}", .shift)), "Shift-F10 opens it")
    try #require(keyboardPlatform.presentedMenus.count == 1)

    let (accessible, accessiblePlatform) = try inputWindow {
        Text("Menu").frame(width: px(200), height: px(200)).contextMenu { p in
            let _ = log.locations.append(p)
            Button("A") {}
        }
    }
    accessiblePlatform.simulateAccessibilityRequest(.activate)
    redraw(accessible)
    let tree = try #require(accessiblePlatform.publishedAccessibilityTrees.last)
    let node = try #require(tree.nodes.first { $0.value.actions.contains(.showMenu) }?.key)
    #expect(accessiblePlatform.simulateAccessibilityRequest(.showMenu(node)))
    try #require(accessiblePlatform.presentedMenus.count == 1)
    #expect(log.locations.count == 2 && log.locations.allSatisfy { $0 == nil }, "\(log.locations)")
    withExtendedLifetime((keyboard, accessible)) {}
}

/// **2.24** (`CI-R` item 3, `CI-L`). A located menu through a rotation reports
/// where on itself the element was pressed: a 160 × 20 bar in a 200 × 200
/// window, turned 90° clockwise about its centre (100, 100), draws its local
/// (10, 5) at window (105, 30). Mutation: skip `Hitbox.localPoint` →
/// (85, −60).
@MainActor
@Test func aLocatedMenuThroughARotationReportsWhereOnItselfItWasPressed() throws {
    let log = WLog()
    let (window, platform) = try inputWindow(size: 200) {
        Box().frame(width: px(160), height: px(20))
            .contextMenu { p in
                let _ = log.locations.append(p)
                Button("A") {}
            }
            .rotationEffect(.degrees(90))
    }
    platform.simulateInput(rdown(105, 30))
    try #require(platform.presentedMenus.count == 1, "the rotated bar is pressed where it is drawn")
    try #require(log.locations.count == 1)
    #expect(close(log.locations[0], pt(10, 5)), "\(log.locations)")
    withExtendedLifetime(window) {}
}

// MARK: - The tooltip (spec §1.4 item 2)

/// **3.31b** (`MN-P` item 2, spec §1.4 item 2; lane 2's addition, ruling
/// `CI-AA`). A magnify or a rotate hides a shown tooltip, as a press does.
/// Mutation: drop `.magnify, .rotate` from `trackTooltip`'s hide arm.
@MainActor
@Test func aMagnifyOrARotateHidesTheTooltip() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 300, startsDisplayLink: true) {
        square().help("Tip")
    }
    window.drawFrameIfNeeded()
    var time = 10.0
    for event in [magnify(0, .began), rotate(0, .began)] {
        platform.simulateInput(moved(10, 10))
        platform.simulateInput(moved(150, 150))
        platform.simulateTick(timestamp: time)
        platform.simulateTick(timestamp: time + 1)
        time += 10
        try #require(window.visibleTooltip != nil, "set up: the tooltip shows")
        platform.simulateInput(event)
        #expect(window.visibleTooltip == nil, "hidden by \(event)")
    }
    withExtendedLifetime(window) {}
}

// MARK: - 2.26, 2.27: a stale arena is replaced (`CI-AB`)

/// Two 100 × 200 legacy boxes side by side in a legacy `Row` (no gap): the
/// root is 200 × 200 at (50, 50), so A spans x 50–150 and B x 150–250.
@MainActor private func twoBoxes<A: Element, B: Element>(_ a: A, _ b: B) -> some StyledElement {
    Row { a; b }
}

/// **2.26** (`CI-AB` item 1). A middle press on A whose release is lost (a
/// modal panel took it) leaves A's arena alive; the next middle press, on B,
/// drops it silently — A reports nothing more and no `onEnded` — and forms a
/// new arena on B, whose drag reports B-local points from B's own press.
/// Mutation: restore `guard buttonArena == nil` in `buttonPress` → the second
/// press is ignored and its drag feeds A (translation 105).
@MainActor
@Test func aSecondPressOfTheArenasOwnButtonReplacesAStaleArena() throws {
    let log = WLog()
    func drag(_ name: String) -> some Gesture {
        DragGesture(minimumDistance: 0, button: .middle)
            .onChanged { value in
                log.entries.append("\(name) \(Int(value.translation.width.value)),\(Int(value.translation.height.value))"
                                   + " @\(Int(value.startLocation.x.value)),\(Int(value.startLocation.y.value))")
            }
            .onEnded { _ in log.entries.append("\(name) end") }
    }
    let (window, platform) = try inputWindow {
        twoBoxes(Box().frame(width: px(100), height: px(200)).gesture(drag("A")),
                 Box().frame(width: px(100), height: px(200)).gesture(drag("B")))
    }
    try #require(window.lastHitboxes.filter { !$0.handlers.gestures.isEmpty }.count == 2,
                 "two gesture targets: \(window.lastHitboxes.map(\.bounds))")
    platform.simulateInput(odown(100, 100))
    platform.simulateInput(odrag(110, 100))
    try #require(log.entries.last == "A 10,0 @50,50", "set up: A drags: \(log.entries)")
    let before = log.entries.count
    // The release of A's drag is lost.
    #expect(platform.simulateInput(odown(200, 100)), "the press forms B's arena and is claimed")
    platform.simulateInput(odrag(205, 100))
    platform.simulateInput(oup(205, 100))
    let after = Array(log.entries.dropFirst(before))
    #expect(!after.contains { $0.hasPrefix("A") }, "A reports nothing more, no onEnded: \(after)")
    #expect(after.suffix(2) == ["B 5,0 @50,50", "B end"], "\(after)")
    withExtendedLifetime(window) {}
}

/// **2.27** (`CI-AB` item 2). A magnify over A whose `.ended` is lost (the
/// window resigned key) leaves A's pinch arena alive; the next magnify
/// `.began`, over B, drops it silently and forms a new arena under the event:
/// B reports its own magnification from 1, A nothing more. Mutation: let a
/// `.began` re-begin the old arena's leaves (drop the re-formation in
/// `dispatchPinch`) → A reports 1.2 and B nothing.
@MainActor
@Test func aBeganOfAnActivePinchKindReformsTheArenaUnderTheEvent() throws {
    let log = WLog()
    func zoom(_ name: String) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                log.entries.append("\(name) \(Int((value.magnification * 100).rounded()))"
                                   + " @\(Int(value.startLocation.x.value)),\(Int(value.startLocation.y.value))")
            }
            .onEnded { _ in log.entries.append("\(name) end") }
    }
    let (window, platform) = try inputWindow {
        twoBoxes(Box().frame(width: px(100), height: px(200)).gesture(zoom("A")),
                 Box().frame(width: px(100), height: px(200)).gesture(zoom("B")))
    }
    try #require(window.lastHitboxes.filter { !$0.handlers.gestures.isEmpty }.count == 2,
                 "two gesture targets: \(window.lastHitboxes.map(\.bounds))")
    platform.simulateInput(magnify(0, .began, at: pt(100, 100)))
    platform.simulateInput(magnify(0.1, .changed, at: pt(100, 100)))
    try #require(log.entries == ["A 110 @50,50"], "set up: A magnifies: \(log.entries)")
    // A's `.ended` is lost.
    #expect(platform.simulateInput(magnify(0, .began, at: pt(220, 120))), "the new arena claims the event")
    platform.simulateInput(magnify(0.2, .changed, at: pt(220, 120)))
    platform.simulateInput(magnify(0, .ended, at: pt(220, 120)))
    #expect(log.entries == ["A 110 @50,50", "B 120 @70,70", "B end"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

// MARK: - 2.28, 2.29: what does NOT replace an arena (`CI-AB`'s other halves)

/// **2.28** (`CI-AB` item 1's second half, `CI-AA` item 4). A middle drag on A
/// is live; a right press on B — which declares a `.secondary` drag — is a
/// DIFFERENT button, so it is ignored: unclaimed, B reports nothing, and A's
/// next middle drag and release still report from A's own press, ending with
/// `A end`. Mutation `M3`: drop `buttonArenaButton == button` from the
/// replacement check in `buttonPress` → the right press ends A's arena
/// silently and forms B's.
@MainActor
@Test func aPressOfAnotherButtonWhileAnArenaIsAliveIsIgnored() throws {
    let log = WLog()
    let (window, platform) = try inputWindow {
        twoBoxes(Box().frame(width: px(100), height: px(200))
                    .gesture(DragGesture(minimumDistance: 0, button: .middle)
                        .onChanged { value in
                            log.entries.append("A \(Int(value.translation.width.value))"
                                               + " @\(Int(value.startLocation.x.value)),\(Int(value.startLocation.y.value))")
                        }
                        .onEnded { _ in log.entries.append("A end") }),
                 Box().frame(width: px(100), height: px(200))
                    .gesture(DragGesture(minimumDistance: 0, button: .secondary)
                        .onChanged { _ in log.entries.append("B changed") }
                        .onEnded { _ in log.entries.append("B end") }))
    }
    try #require(window.lastHitboxes.filter { !$0.handlers.gestures.isEmpty }.count == 2,
                 "two gesture targets: \(window.lastHitboxes.map(\.bounds))")
    try #require(window.secondaryDragIsDeclared(at: pt(200, 100)), "set up: B declares a secondary drag")
    platform.simulateInput(odown(100, 100))
    platform.simulateInput(odrag(110, 100))
    try #require(log.entries.last == "A 10 @50,50", "set up: A drags: \(log.entries)")
    #expect(!platform.simulateInput(rdown(200, 100)), "another button's press is not claimed")
    platform.simulateInput(rdrag(210, 100))
    platform.simulateInput(rup(210, 100))
    #expect(!log.entries.contains { $0.hasPrefix("B") }, "B reports nothing: \(log.entries)")
    platform.simulateInput(odrag(120, 100))
    platform.simulateInput(oup(120, 100))
    #expect(log.entries.suffix(2) == ["A 20 @50,50", "A end"], "\(log.entries)")
    #expect(log.entries.filter { $0 == "A end" }.count == 1, "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **2.29** (`CI-AB` item 2's kind half, `CI-AA` item 2). A rotate `.began`
/// arriving while a magnify is active (AppKit sends both during one pinch) is
/// a kind the arena does NOT hold active, so it feeds the existing arena: the
/// magnify keeps accumulating from its first event, its `onEnded` runs once,
/// and the rotate reports. Mutation `M4`: `holdsActivePinch(of:)` answers for
/// any active kind → the rotate `.began` drops the live arena, the magnify
/// restarts from 1 and never ends.
@MainActor
@Test func aBeganOfAPinchKindTheArenaDoesNotHoldFeedsTheArena() throws {
    let log = WLog()
    let (window, platform) = try inputWindow {
        Box().frame(width: px(200), height: px(200))
            .gesture(MagnifyGesture()
                .onChanged { value in log.entries.append("m \(Int((value.magnification * 100).rounded()))") }
                .onEnded { value in log.entries.append("m end \(Int((value.magnification * 100).rounded()))") }
                .simultaneously(with: RotateGesture()
                    .onChanged { value in log.entries.append("r \(Int(value.rotation.degrees.rounded()))") }
                    .onEnded { _ in log.entries.append("r end") }))
    }
    try #require(window.lastHitboxes.contains { !$0.handlers.gestures.isEmpty }, "a gesture target")
    platform.simulateInput(magnify(0, .began))
    platform.simulateInput(magnify(0.1, .changed))
    try #require(log.entries == ["m 110"], "set up: the magnify runs: \(log.entries)")
    #expect(platform.simulateInput(rotate(0, .began)), "the rotate joins the live arena")
    platform.simulateInput(rotate(10, .changed))
    platform.simulateInput(magnify(0.1, .changed))
    platform.simulateInput(rotate(0, .ended))
    platform.simulateInput(magnify(0, .ended))
    #expect(log.entries.contains("r 10"), "the rotate reports: \(log.entries)")
    let magnifies = log.entries.filter { $0.hasPrefix("m ") && !$0.hasPrefix("m end") }
    #expect(magnifies == ["m 110", "m 120"], "the magnify accumulates from its first event: \(log.entries)")
    #expect(log.entries.filter { $0.hasPrefix("m end") } == ["m end 120"], "one onEnded: \(log.entries)")
    withExtendedLifetime(window) {}
}
