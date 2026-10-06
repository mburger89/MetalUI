import Testing
import Foundation
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// The drawn alert, lane 3, tests 2.26–2.32 and 2.53's alert half (rulings
// `SV-J` items 2–4, `SV-X`, `SV-AC`, `SV-AK`; spec §6.2). A window over
// `FakePlatformWindow` with `presentsAlertsNatively = false` (SDL's answer)
// leaves the alert to the window, which draws it (`AlertPanel.swift`) — lane
// 2 held only its model (`SV-AH` item 5). SwiftUI's side is the native alert
// (`docs/probes/swiftui-platform-services.swift` `A1`–`A9`,
// `swiftui-alert-presenting.swift` `K0`–`K3`): the drawn one copies its button
// rules, not its look. Red before: every test here reads a drawn panel,
// modal keys or an `.alert` node that does not exist at `f36d470` — they
// compile against lane 2's API and fail at run time.

// MARK: - Harness

@Observable @MainActor private final class APModel {
    var shown = false
    var log: [String] = []
    var flag = false

    var binding: Binding<Bool> {
        Binding(get: { self.shown }, set: { self.shown = $0; self.log.append("isPresented=\($0)") })
    }
}

private struct APAction: Action {}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func down(_ x: Float, _ y: Float) -> InputEvent { .mouseDown(MouseEvent(position: pt(x, y))) }
private func up(_ x: Float, _ y: Float) -> InputEvent { .mouseUp(MouseEvent(position: pt(x, y))) }
private func moved(_ x: Float, _ y: Float) -> InputEvent { .mouseMoved(MouseEvent(position: pt(x, y))) }
private func dragged(_ x: Float, _ y: Float) -> InputEvent { .mouseDragged(MouseEvent(position: pt(x, y))) }
private func key(_ c: String, _ mods: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: mods, timestamp: 0))
}
private let returnKey = "\r", escapeKey = "\u{1b}", tabKey = "\t"
private let downArrow = "\u{f701}", upArrow = "\u{f700}", leftArrow = "\u{f702}", rightArrow = "\u{f703}"

private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    pt(b.origin.x.value + b.size.width.value / 2, b.origin.y.value + b.size.height.value / 2)
}

/// A 400 × 400 window over `content` that draws its alerts (the fake declines
/// them, `SV-J` item 2) and its menus, one frame drawn.
@MainActor private func apWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 400, content: content)
    platform.presentsAlertsNatively = false
    platform.presentsMenusNatively = false
    window.drawFrameIfNeeded()
    return (window, platform)
}

@MainActor private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

/// Shows `m`'s alert: `isPresented = true`, the frame that presents it, and
/// the frame that draws it.
@MainActor private func present(_ m: APModel, _ window: Window,
                                sourceLocation: SourceLocation = #_sourceLocation) throws {
    m.shown = true
    window.drawFrameIfNeeded()
    try #require(window.drawnAlert != nil, "the alert is drawn, not native", sourceLocation: sourceLocation)
    redraw(window)
}

/// A 400 × 400 click target under everything, logging "beneath".
@MainActor private func floor(_ m: APModel) -> some StyledElement {
    Box().frame(width: px(400), height: px(400)).background(.surface).onClick { m.log.append("beneath") }
}

/// `A1`: Delete (destructive), Cancel (cancel), a message — no default.
@MainActor private func a1(_ m: APModel) -> some Element {
    Column {
        floor(m).alert("Delete keymap?", isPresented: m.binding) {
            Button("Delete", role: .destructive) { m.log.append("delete") }
            Button("Cancel", role: .cancel) { m.log.append("cancel") }
        } message: {
            Text("This cannot be undone.")
        }
    }
}

/// `A2`: three plain buttons — A is the default, no cancel.
@MainActor private func a2(_ m: APModel) -> some Element {
    Column {
        floor(m).alert("Choose", isPresented: m.binding) {
            Button("A") { m.log.append("A") }
            Button("B") { m.log.append("B") }
            Button("C") { m.log.append("C") }
        }
    }
}

/// `A5`: Save, Discard (destructive) and the synthesized Cancel — no default.
@MainActor private func a5(_ m: APModel) -> some Element {
    Column {
        floor(m).alert("Save changes?", isPresented: m.binding) {
            Button("Save") { m.log.append("save") }
            Button("Discard", role: .destructive) { m.log.append("discard") }
        }
    }
}

// MARK: - 2.26: drawn above everything, owning no state

/// **2.26** (`SV-J` item 2). A declined alert is drawn after everything else —
/// above an open drag's preview — on the highest layer: a scrim over the whole
/// window and the 260-wide panel centred, 24 from the top (`(400 − 260) / 2 =
/// 70`). It owns nothing: the `StateTable` entry count and the hitbox list are
/// those of the frame before it. Mutation: paint it before the drag preview
/// (or the menu panel).
@MainActor
@Test func aDeclinedAlertIsDrawnAboveEverythingAndOwnsNoState() throws {
    let m = APModel()
    let (window, platform) = try apWindow {
        Column {
            Box().frame(width: px(400), height: px(400)).background(.accent).draggable("s")
                .alert("Delete keymap?", isPresented: m.binding) {
                    Button("Delete", role: .destructive) {}
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
    platform.simulateInput(down(200, 300))
    platform.simulateInput(dragged(250, 300))
    try #require(window.dragSession != nil, "a drag is open")
    redraw(window)
    let entries = window.stateTable.count
    let boxes = window.lastHitboxes.map { "\($0.id) \($0.bounds) \($0.opaque)" }
    try present(m, window)
    let scene = window.lastScene
    let scrim = try #require(scene.rects.firstIndex {
        $0.bounds.origin.x == 0 && $0.bounds.origin.y == 0 && $0.bounds.size.width == 400
            && $0.bounds.size.height == 400 && $0.background.a > 0 && $0.background.a < 1
    }, "a translucent scrim covers the window")
    let panel = try #require(scene.rects.firstIndex {
        $0.bounds.origin.x == 70 && $0.bounds.origin.y == 24 && $0.bounds.size.width == 260
    }, "the panel: 260 wide, centred, 24 from the top")
    let preview = try #require(scene.rects.indices.first { index in
        index != scrim && scene.rects[index].background.a > 0 && scene.rects[index].background.a < 0.75
    }, "the drag preview's translucent copy is in the scene")
    let layer = scene.layer(of: .rect, at: panel)
    #expect(layer == scene.layer(of: .rect, at: scrim))
    #expect(layer > scene.layer(of: .rect, at: preview), "above the drag preview")
    #expect(layer == scene.highestLayer, "the highest layer")
    #expect(window.stateTable.count == entries, "no StateTable entry")
    #expect(window.lastHitboxes.map { "\($0.id) \($0.bounds) \($0.opaque)" } == boxes, "no hitbox")
    withExtendedLifetime(window) {}
}

// MARK: - 2.27: modal

/// **2.27** (`SV-J` item 3). While the alert is drawn a click on the element
/// beneath — outside the panel and inside it off a button — and a keymap key
/// do nothing, and each is claimed. Mutation: let an event the alert does not
/// handle through.
@MainActor
@Test func theDrawnAlertSwallowsPointerAndKeysBeneath() throws {
    let m = APModel()
    let (window, platform) = try apWindow { a1(m) }
    window.keymap = Keymap { KeyBinding("cmd-k", APAction()) }
    window.onAction = { action in
        guard action is APAction else { return false }
        m.log.append("keymap"); return true
    }
    platform.simulateInput(down(200, 380))
    platform.simulateInput(up(200, 380))
    platform.simulateInput(key("k", .command))
    try #require(m.log == ["beneath", "keymap"], "set up: both reach the content with no alert: \(m.log)")
    m.log = []
    try present(m, window)
    #expect(platform.simulateInput(down(200, 380)), "claimed")
    #expect(platform.simulateInput(up(200, 380)), "claimed")
    platform.simulateInput(down(80, 30))   // inside the panel, off every button
    platform.simulateInput(up(80, 30))
    #expect(platform.simulateInput(key("k", .command)), "claimed")
    platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(200, 380), delta: pt(0, 10))))
    #expect(m.log.isEmpty, "nothing beneath ran: \(m.log)")
    #expect(window.drawnAlert != nil, "still up")
    withExtendedLifetime(window) {}
}

// MARK: - 2.28–2.29: keys

/// **2.28** (`SV-I` item 3, `SV-X`). Return presses the default and Escape the
/// cancel button — declared or synthesized — on the drawn alert: `A2` Return
/// → A, Escape nothing; `A1` Return nothing, Escape → Cancel; `A5` Return
/// nothing (Save is not the default beside a destructive button), Escape →
/// the synthesized Cancel (`isPresented = false`, no action). Mutation: map
/// Return to the first button.
@MainActor
@Test func returnPressesTheDefaultAndEscapeTheCancelOnTheDrawnAlert() throws {
    do {
        let m = APModel()
        let (window, platform) = try apWindow { a2(m) }
        try present(m, window)
        platform.simulateInput(key(escapeKey))
        #expect(m.log.isEmpty && window.drawnAlert != nil, "A2: Escape does nothing: \(m.log)")
        platform.simulateInput(key(returnKey))
        #expect(m.log == ["isPresented=false", "A"], "A2: Return presses A: \(m.log)")
        #expect(window.drawnAlert == nil)
        withExtendedLifetime(window) {}
    }
    do {
        let m = APModel()
        let (window, platform) = try apWindow { a1(m) }
        try present(m, window)
        platform.simulateInput(key(returnKey))
        #expect(m.log.isEmpty && window.drawnAlert != nil, "A1: Return does nothing: \(m.log)")
        platform.simulateInput(key(escapeKey))
        #expect(m.log == ["isPresented=false", "cancel"], "A1: Escape presses Cancel: \(m.log)")
        withExtendedLifetime(window) {}
    }
    do {
        let m = APModel()
        let (window, platform) = try apWindow { a5(m) }
        try present(m, window)
        platform.simulateInput(key(returnKey))
        #expect(m.log.isEmpty && window.drawnAlert != nil, "A5: Return does nothing: \(m.log)")
        platform.simulateInput(key(escapeKey))
        #expect(m.log == ["isPresented=false"], "A5: Escape presses the synthesized Cancel: \(m.log)")
        #expect(window.drawnAlert == nil)
        withExtendedLifetime(window) {}
    }
}

/// **2.29** (`SV-J` item 3). The ring starts on the default (`A2`: Space →
/// A; ↓ then Space → B) and, with no default, on nothing (`A1`: Space does
/// nothing); Tab and →/↓ move it forward, Shift-Tab and ←/↑ back, wrapping;
/// Space presses the ringed button. Mutation: the ring's step (move it back
/// on Tab).
@MainActor
@Test func tabAndArrowsMoveTheRingAndSpacePressesIt() throws {
    do {
        let m = APModel()
        let (window, platform) = try apWindow { a1(m) }
        try present(m, window)
        platform.simulateInput(key(" "))
        #expect(m.log.isEmpty && window.drawnAlert != nil, "A1: no ring, Space does nothing: \(m.log)")
        platform.simulateInput(key(tabKey))    // → Delete (0)
        platform.simulateInput(key(tabKey))    // → Cancel (1)
        platform.simulateInput(key(" "))
        #expect(m.log == ["isPresented=false", "cancel"], "Tab, Tab, Space: \(m.log)")

        m.log = []
        try present(m, window)
        platform.simulateInput(key(rightArrow))   // → Delete (0)
        platform.simulateInput(key(rightArrow))   // → Cancel (1)
        platform.simulateInput(key(rightArrow))   // wraps → Delete (0)
        platform.simulateInput(key(leftArrow))    // → Cancel (1)
        platform.simulateInput(key(tabKey, .shift))  // → Delete (0)
        platform.simulateInput(key(" "))
        #expect(m.log == ["isPresented=false", "delete"], "→ → → ← ⇧Tab, Space: \(m.log)")
        withExtendedLifetime(window) {}
    }
    do {
        let m = APModel()
        let (window, platform) = try apWindow { a2(m) }
        try present(m, window)
        platform.simulateInput(key(" "))
        #expect(m.log == ["isPresented=false", "A"], "A2: the ring starts on the default: \(m.log)")
        m.log = []
        try present(m, window)
        platform.simulateInput(key(downArrow))
        platform.simulateInput(key(upArrow))
        platform.simulateInput(key(downArrow))
        platform.simulateInput(key(" "))
        #expect(m.log == ["isPresented=false", "B"], "↓ ↑ ↓, Space: \(m.log)")
        withExtendedLifetime(window) {}
    }
}

// MARK: - 2.30–2.31: clicks and accessibility

/// The published drawn alert's root and button nodes, required.
@MainActor private func alertNode(_ platform: FakePlatformWindow,
                                  sourceLocation: SourceLocation = #_sourceLocation) throws
    -> (tree: AccessibilityTree, root: AccessibilityNode) {
    let tree = try #require(platform.publishedAccessibilityTrees.last, sourceLocation: sourceLocation)
    let rootID = try #require(tree.roots.last, sourceLocation: sourceLocation)
    let root = try #require(tree.nodes[rootID], sourceLocation: sourceLocation)
    try #require(root.role == .alert, "the last root is the alert: \(root.role)", sourceLocation: sourceLocation)
    return (tree, root)
}

/// **2.30** (`SV-J` items 2–3). A click on a drawn button presses it — `A1`'s
/// two side by side, the first (Delete) trailing — writing `isPresented =
/// false`, running its action and taking the panel down; the next frame has
/// no scrim. Mutation: hit-test with the wrong panel origin.
@MainActor
@Test func aClickOnADrawnAlertButtonPressesIt() throws {
    let m = APModel()
    let (window, platform) = try apWindow { a1(m) }
    platform.simulateAccessibilityRequest(.activate)
    redraw(window)
    try present(m, window)
    let (tree, root) = try alertNode(platform)
    let frames = try root.children.map { try #require(tree.geometry[$0]?.frame) }
    try #require(frames.count == 2)
    #expect(frames[0].origin.x.value > frames[1].origin.x.value, "Delete trails Cancel")
    #expect(frames[0].origin.y == frames[1].origin.y, "side by side")
    #expect(frames.allSatisfy { $0.size.height.value == 28 }, "28-pt buttons")
    let delete = centre(frames[0])
    platform.simulateInput(down(delete.x.value, delete.y.value))
    platform.simulateInput(up(delete.x.value, delete.y.value))
    #expect(m.log == ["isPresented=false", "delete"], "\(m.log)")
    #expect(window.drawnAlert == nil)
    redraw(window)
    #expect(!window.lastScene.rects.contains { $0.bounds.origin.x == 70 && $0.bounds.origin.y == 24 },
            "the panel is gone")
    withExtendedLifetime(window) {}
}

/// **2.31** (`SV-J` item 4, `SV-S`). While a client is active the drawn alert
/// publishes one `.alert` root — label the title, value the message — whose
/// children are its `.button`s in the resolver's order, focus on the ringed
/// one (or the alert, with no ring); a press on a button chooses it, and a
/// press on the content beneath is refused (modal). Mutation: omit the
/// panel's append.
@MainActor
@Test func theDrawnAlertPublishesAnAlertNodeWithButtonChildren() throws {
    let m = APModel()
    let (window, platform) = try apWindow { a1(m) }
    platform.simulateAccessibilityRequest(.activate)
    redraw(window)
    let beneath = try #require(platform.publishedAccessibilityTrees.last?.nodes.first {
        $0.value.actions.contains(.press)
    }?.key, "set up: the content has a pressable node")
    try present(m, window)
    let (tree, root) = try alertNode(platform)
    #expect(root.label == "Delete keymap?")
    #expect(root.value == "This cannot be undone.")
    let buttons = root.children.compactMap { tree.nodes[$0] }
    #expect(buttons.map(\.role) == [.button, .button])
    #expect(buttons.map(\.label) == ["Delete", "Cancel"])
    #expect(tree.focused == tree.roots.last, "no ring: focus on the alert")
    #expect(!platform.simulateAccessibilityRequest(.press(beneath)), "the content beneath is refused")
    #expect(m.log.isEmpty)
    #expect(platform.simulateAccessibilityRequest(.press(root.children[1])), "pressing Cancel is handled")
    #expect(m.log == ["isPresented=false", "cancel"], "\(m.log)")
    #expect(window.drawnAlert == nil)
    withExtendedLifetime(window) {}
}

// MARK: - 2.32: the menu

/// **2.32** (`SV-J` item 2). An in-window menu open when an alert is drawn is
/// dismissed. Mutation: keep the menu.
@MainActor
@Test func anAlertDismissesAnOpenInWindowMenu() throws {
    let m = APModel()
    let (window, platform) = try apWindow {
        Column {
            floor(m).contextMenu { Button("Copy") { m.log.append("copy") } }
                .alert("Delete keymap?", isPresented: m.binding) {
                    Button("Delete", role: .destructive) {}
                }
        }
    }
    platform.simulateInput(.rightMouseDown(MouseEvent(position: pt(100, 300))))
    platform.simulateInput(.rightMouseUp(MouseEvent(position: pt(100, 300))))
    try #require(window.menuSession != nil && window.menuSession?.isNative == false, "set up: an in-window menu")
    m.shown = true
    window.drawFrameIfNeeded()
    try #require(window.drawnAlert != nil)
    #expect(window.menuSession == nil, "the alert dismissed the menu")
    withExtendedLifetime(window) {}
}

// MARK: - 2.53, the alert half

/// **2.53**, the alert half (`SV-N` item 6, `SV-J` item 3). A drawn alert
/// empties the hovered set after the frame that presents it — the region
/// hears `false` — and once it is answered the region under the still
/// pointer is hovered again after the next frame. Mutation: drop
/// `|| drawnAlert != nil` from `hoverIsSuppressed`.
@MainActor
@Test func aDrawnAlertEmptiesTheHoverSet() throws {
    let m = APModel()
    let (window, platform) = try apWindow {
        Column {
            Box().frame(width: px(400), height: px(400)).background(.accent)
                .onHover { m.log.append("hover \($0)") }
                .alert("Delete keymap?", isPresented: m.binding) {
                    Button("Delete", role: .destructive) { m.log.append("delete") }
                    Button("Cancel", role: .cancel) { m.log.append("cancel") }
                }
        }
    }
    platform.simulateInput(moved(200, 380))
    try #require(m.log == ["hover true"])
    m.shown = true
    window.drawFrameIfNeeded()
    try #require(window.drawnAlert != nil)
    #expect(m.log == ["hover true", "hover false"], "the alert empties the set: \(m.log)")
    platform.simulateInput(moved(201, 380))
    #expect(m.log == ["hover true", "hover false"], "no hover while it is up: \(m.log)")
    platform.simulateInput(key(escapeKey))
    try #require(window.drawnAlert == nil, "Escape answered it")
    window.drawFrameIfNeeded()
    #expect(m.log == ["hover true", "hover false", "isPresented=false", "cancel", "hover true"],
            "answered: hovered again: \(m.log)")
    withExtendedLifetime(window) {}
}
