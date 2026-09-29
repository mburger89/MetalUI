import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 12, part 1, lane 3 — focus and identity (rulings `IX-I`, `IX-K`;
// spec §6, tests 3.1, 3.5, 3.13, 3.14, 3.14b). SwiftUI's answers are arms of
// `docs/probes/swiftui-interaction.swift`: F1 (a focused `.id("a")` renamed
// `b` is unfocused and stays so when renamed back), F2 (the same for an `if`),
// F3 (a click focuses a `.focusable()` view — divergence 94, pinned wrong on
// purpose), F9 (a `.focusable().hidden()` view never takes focus or keys, K0
// its passing control) and X1 (a hidden button's shortcut fires).

private func key(_ characters: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: characters, characters: characters,
                      modifiers: modifiers, timestamp: 0))
}

/// What each probe saw, by label: its id and how many frames it has counted
/// in its own (non-dirtying) state, plus the keys each handler took.
@MainActor
private final class FocusProbeLog {
    var ids: [String: GlobalElementID] = [:]
    var counts: [String: Int] = [:]
    var keys: [String] = []
}

/// A 20×20 focusable leaf that takes every key, counting its frames under its
/// own id with `withState` (never a dirtying write) and recording its id — so
/// a test reads what it SAW without hand-building a path.
private struct FocusProbe: Element {
    let label: String
    let log: FocusProbeLog
    var elementID: ElementID? { nil }

    init(_ label: String, _ log: FocusProbeLog) {
        self.label = label
        self.log = log
    }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        var count = 0
        pass.withState(id, initial: 0) { $0 += 1; count = $0 }
        log.counts[label] = count
        log.ids[label] = id
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID,
                ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        var handlers = Handlers()
        handlers.isFocusable = true
        let log = self.log, label = self.label
        handlers.onKey = { _ in log.keys.append(label); return true }
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {}
}

@MainActor
private final class FocusIdentityModel {
    var name = "a"
    var shown = true
    var keys = ["a", "b"]
    var hidden = false
}

@MainActor
private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

// MARK: - 3.1 a rename (F1)

/// **3.1 — focus drops when its element is renamed, and does not return with
/// the name** (F1: `focused=false` after the rename, still unfocused renamed
/// back; ruling `IX-I`). Replaces C2.13's rename arm, whose answer inverts.
///
/// A focused probe under `.id("a")` is renamed `b`: after the FIRST away frame
/// `window.focusedElement` is `nil` (the frame whose `sweep()` deletes the
/// departed name's `$focus` slot clears focus in that frame), a key reaches
/// `Window.onInput` rather than a retained chain, and renamed back to `a` the
/// probe starts fresh (count 1) and is still unfocused.
///
/// Mutation **MRk′** (`$focus` exempt from the resets again) reddens it.
@MainActor
@Test func focusDropsWhenItsElementIsRenamedAndDoesNotReturn() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = FocusProbeLog()
    let model = FocusIdentityModel()
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        Row { Box { FocusProbe("p", log) }.id(model.name) }
    }
    window.drawFrameIfNeeded()
    let a = try #require(log.ids["p"], "the probe was laid out")
    window.focus(a)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == a, "set up: the confirming frame took focus")
    platform.simulateInput(key("x"))
    try #require(log.keys == ["p"], "set up: the focused probe takes a key")

    model.name = "b"
    redraw(window)
    #expect(window.focusedElement == nil, "the first away frame drops focus (F1)")
    var raw: [String] = []
    window.onInput = { event in
        if case .keyDown = event { raw.append("window") }
        return true
    }
    platform.simulateInput(key("x"))
    #expect(log.keys == ["p"] && raw == ["window"], "a key reaches the window, not a retained chain")

    model.name = "a"
    redraw(window)
    #expect(log.ids["p"] == a && log.counts["p"] == 1, "`a` returns fresh: \(log.counts)")
    #expect(window.focusedElement == nil, "focus does not return with the name (F1)")
}

// MARK: - 3.5 a `ForEach` drop (`DD-C`)

/// **3.5 — a `ForEach` that drops its focused element drops focus** (`DD-C`'s
/// loop reset, ruling `IX-I`). `ForEach(["a", "b"], id: \.self)`, `b` focused;
/// the data loses `b` for one frame: focus is `nil`; `b` returns fresh and
/// unfocused. Mutation **MRk′** reddens it.
@MainActor
@Test func aForEachThatDropsItsFocusedElementDropsFocus() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = FocusProbeLog()
    let model = FocusIdentityModel()
    let (window, _) = try makeFakeWindow(device: device, size: 100) {
        Row { ForEach(model.keys, id: \.self) { key in FocusProbe(key, log) } }
    }
    window.drawFrameIfNeeded()
    let b = try #require(log.ids["b"], "the element was laid out")
    window.focus(b)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == b, "set up: the confirming frame took focus")
    try #require((log.counts["b"] ?? 0) >= 2, "set up: the element counted twice")

    model.keys = ["a"]
    redraw(window)
    #expect(window.focusedElement == nil, "the dropping frame drops focus")

    model.keys = ["a", "b"]
    redraw(window)
    #expect(log.ids["b"] == b && log.counts["b"] == 1, "`b` returns fresh: \(log.counts)")
    #expect(window.focusedElement == nil, "focus does not return with the element")
}

// MARK: - 3.13 hidden is out of the keyboard (F9)

/// **3.13 — a hidden focusable element cannot take focus or keys** (F9, ruling
/// `IX-K` item 3). Three arms through a real `Window`:
///
/// 1. a `.focusable().onKey { }.hidden()` box: `Window.focus` on it is cleared
///    by the next frame and a key reaches `Window.onInput`;
/// 2. the same box focused while shown, then hidden: focus is gone at the next
///    boundary (as a disabled one's is);
/// 3. a hidden INNER modifier layer (`Box().focusable().onKey { }.frame(…)
///    .hidden().padding(4)`): the focusable box under it is out of the
///    keyboard too — `ModifiedContent.prepaintLayer`'s copy of the hidden
///    scope (`MC-B`).
///
/// The pointer side is unchanged (a hidden element already registers no
/// hitbox, `LR-DH`). Mutation **M3g** (the hidden condition dropped from the
/// gate) reddens every arm; **M3g′** (dropped from `ModifiedContent`'s copy
/// only) reddens arm 3.
@MainActor
@Test func aHiddenFocusableElementCannotTakeFocusOrKeys() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let model = FocusIdentityModel()
    var keys: [String] = []
    var raw: [String] = []

    // Arms 1 and 2.
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        let box = Box().frame(width: Pixels(20), height: Pixels(20))
            .focusable().onKey { _ in keys.append("box"); return true }.id("h")
        return Row { model.hidden ? box.hidden() : box }
    }
    window.onInput = { event in
        if case .keyDown = event { raw.append("window") }
        return true
    }
    window.drawFrameIfNeeded()
    let h = GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: nil), at: 0, name: ElementID("h"))
    try #require(window.lastFocusRegistry.isFocusable(h), "control: the shown box registers as focusable at \(h)")
    window.focus(h)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == h, "control: the shown box takes focus (K0)")
    platform.simulateInput(key("x"))
    try #require(keys == ["box"], "control: the shown box takes the key")

    model.hidden = true
    redraw(window)
    #expect(window.focusedElement == nil, "arm 2: a focused box that becomes hidden loses focus at the boundary")
    #expect(!window.lastFocusRegistry.isFocusable(h), "a hidden box does not register as focusable")
    window.focus(h)
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == nil, "arm 1: focus on a hidden box is cleared (F9)")
    platform.simulateInput(key("x"))
    #expect(keys == ["box"] && raw == ["window"], "arm 1: a hidden box's onKey never runs (F9)")

    // Arm 3: a hidden inner modifier layer.
    var innerKeys: [String] = []
    let (inner, innerPlatform) = try makeFakeWindow(device: device, size: 100) {
        Row {
            Box().focusable().onKey { _ in innerKeys.append("inner"); return true }
                .frame(width: Pixels(20), height: Pixels(20)).hidden().padding(4)
        }
    }
    inner.drawFrameIfNeeded()
    #expect(inner.lastFocusRegistry.tabOrder.isEmpty,
            "arm 3: nothing under a hidden inner layer is focusable: \(inner.lastFocusRegistry.tabOrder)")
    for id in inner.lastFocusRegistry.tabOrder { inner.focus(id) }
    inner.drawFrameIfNeeded()
    innerPlatform.simulateInput(key("x"))
    #expect(innerKeys.isEmpty, "arm 3: the box under a hidden inner layer takes no key")
}

// MARK: - 3.14 a click does not focus (divergence 94)

/// **3.14 — clicking a focusable element does not focus it** (divergence
/// **94**, pinned wrong on purpose, ruling `IX-K` item 2; SwiftUI's click
/// focuses one, F3). A click on a `.focusable()` box, and on a focusable box
/// with an `onClick` (whose click runs), leaves `window.focusedElement` nil.
/// Written first and green throughout. Mutation **M3h** (a press focuses the
/// target's focusable ancestor) reddens it.
@MainActor
@Test func clickingAFocusableElementDoesNotFocusIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var clicks = 0
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        Row {
            Box().frame(width: Pixels(40), height: Pixels(40)).focusable()
            Box().frame(width: Pixels(40), height: Pixels(40)).focusable().onClick { clicks += 1 }
        }
    }
    window.drawFrameIfNeeded()
    try #require(window.lastFocusRegistry.tabOrder.count == 2, "control: both boxes are focusable")
    for x: Float in [20, 60] {
        let point = Point(x: Pixels(x), y: Pixels(50))
        platform.simulateInput(.mouseDown(MouseEvent(position: point)))
        platform.simulateInput(.mouseUp(MouseEvent(position: point)))
        window.drawFrameIfNeeded()
    }
    #expect(clicks == 1, "control: the clickable box's click ran")
    #expect(window.focusedElement == nil, "a click focuses nothing (divergence 94; SwiftUI's does, F3)")
}

// MARK: - 3.14b a hidden button's shortcut fires (X1)

/// **3.14b — a hidden button's shortcut still fires** (X1, ruling `IX-K` item
/// 3 as corrected by `IX-O`; `IX-R` clause 8). `Button("K") { }
/// .keyboardShortcut("k").hidden()`: ⌘K runs it. Control: the same button
/// `.disabled(true)` is silent. Written first and green throughout. Mutation
/// **M3n** (the shortcut table behind the hidden condition) reddens it.
@MainActor
@Test func aHiddenButtonsShortcutStillFires() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var fired: [String] = []
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Row {
            Button("K") { fired.append("hidden") }.keyboardShortcut("k").hidden()
            Button("J") { fired.append("disabled") }.keyboardShortcut("j").disabled(true)
        }
    }
    window.drawFrameIfNeeded()
    platform.simulateInput(key("k", .command))
    #expect(fired == ["hidden"], "a hidden button's ⌘K fires (X1)")
    platform.simulateInput(key("j", .command))
    #expect(fired == ["hidden"], "control: a disabled button's ⌘J is silent")
    withExtendedLifetime(window) {}
}
