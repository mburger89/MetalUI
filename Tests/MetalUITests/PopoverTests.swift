import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Menus, popovers and tooltips, lane 3, tests 3.1–3.16 and 3.26 (rulings
// `MN-L`…`MN-O`, `MN-X`, `MN-Y`, `MN-Z`; spec
// `docs/superpowers/specs/2026-10-02-menus-popovers-design.md` §6.3). Every
// SwiftUI answer is an arm of `docs/probes/swiftui-menus-popovers.swift`
// (named per test); the rest is MetalUI's own, ruled.
//
// Everything runs through a real `Window` on a 400 × 400 `FakePlatformWindow`
// — nothing sleeps. A popover appears on the frame after its anchor was first
// laid out (`MN-M` item 2), so a fixture draws until the window is clean.

// MARK: - Fixtures

@MainActor
private final class PLog {
    var shown = true
    var inner = true
    var item: PItem?
    var top: Float = 190
    var entries: [String] = []
}

private struct PItem: Identifiable { let id: Int }

private struct PEscape: Action {}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func ldown(_ x: Float, _ y: Float) -> InputEvent { .mouseDown(MouseEvent(position: pt(x, y))) }
private func lup(_ x: Float, _ y: Float) -> InputEvent { .mouseUp(MouseEvent(position: pt(x, y))) }
private func dragged(_ x: Float, _ y: Float) -> InputEvent { .mouseDragged(MouseEvent(position: pt(x, y))) }
private func key(_ c: String, _ mods: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: mods, timestamp: 0))
}
private let escapeKey = "\u{1b}"

@MainActor private func shownBinding(_ log: PLog) -> Binding<Bool> {
    Binding(get: { log.shown }, set: { log.shown = $0; log.entries.append("shown=\($0)") })
}

@MainActor private func innerBinding(_ log: PLog) -> Binding<Bool> {
    Binding(get: { log.inner }, set: { log.inner = $0; log.entries.append("inner=\($0)") })
}

@MainActor private func itemBinding(_ log: PLog) -> Binding<PItem?> {
    Binding(get: { log.item }, set: { log.item = $0; log.entries.append("item=\($0.map { "\($0.id)" } ?? "nil")") })
}

/// A 100 × 50 popover content: the chrome around it is 124 × 74 (padding 12).
@MainActor private func content100x50() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(100), height: px(50))
}

/// `anchor` (`width` × `height`) placed with its top-left corner at
/// (`left`, `top`) in a 400 × 400 root: a column of fixed spacers around a row
/// of fixed spacers (legacy `Column`/`Row` have no gap).
@MainActor private func at<A: Element>(top: Float, left: Float, width: Float = 40, height: Float = 20,
                                       _ anchor: A) -> some Element {
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

/// The 40 × 20 anchor at (180, 190) — the window's centre — with a 100 × 50
/// popover on `edge`.
@MainActor private func centred(_ log: PLog, edge: Edge?) -> some Element {
    at(top: 190, left: 180, Box().frame(width: px(40), height: px(20))
        .popover(isPresented: shownBinding(log), arrowEdge: edge) { content100x50() })
}

/// A 400 × 400 window over `content`, drawn until clean (at most six frames).
/// **A `Window` is held only weakly by its platform window**, so every test
/// keeps the window to its end (`withExtendedLifetime`).
@MainActor
private func popoverWindow<Root: Element>(settle: Bool = true, startsDisplayLink: Bool = false,
                                          _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: startsDisplayLink,
                                                content: content)
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    if settle { drawUntilClean(window) }
    return (window, platform)
}

@MainActor private func drawUntilClean(_ window: Window) {
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

@MainActor private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    drawUntilClean(window)
}

/// The topmost open popover's chrome, required.
@MainActor private func chrome(_ window: Window, sourceLocation: SourceLocation = #_sourceLocation) throws
    -> Bounds<Pixels> {
    try #require(window.lastOpenPopovers.last, "a popover is open", sourceLocation: sourceLocation).bounds
}

private func xywh(_ b: Bounds<Pixels>) -> [Float] {
    [b.origin.x.value, b.origin.y.value, b.size.width.value, b.size.height.value]
}

// MARK: - 3.1–3.4: placement

/// Each edge and the chrome's expected origin for the centred anchor.
private let edgeOrigins: [(Edge, [Float])] = [(.top, [138, 108]), (.bottom, [138, 218]), (.leading, [48, 163]),
                                               (.trailing, [228, 163])]

/// **3.1** (P1, `MN-M` item 3). The popover sits on its arrow edge's side of
/// the anchor, 8 pt away, centred along the other axis: a 124 × 74 chrome for
/// the 40 × 20 anchor at (180, 190). Mutation: swap `.top` and `.bottom`.
@MainActor
@Test(arguments: edgeOrigins)
func thePopoverSitsOnItsArrowEdgeOfTheAnchor(edge: Edge, origin: [Float]) throws {
    let log = PLog()
    let (window, _) = try popoverWindow { centred(log, edge: edge) }
    #expect(xywh(try chrome(window)) == origin + [124, 74], "\(edge)")
    withExtendedLifetime(window) {}
}

/// **3.2** (P7, `MN-X` item 1). No edge, and `arrowEdge: nil`, both place the
/// popover above its anchor — SwiftUI's macOS default. Mutation: map `nil` to
/// `.bottom`.
@MainActor
@Test func theDefaultArrowEdgeIsTop() throws {
    let log = PLog()
    let (omitted, _) = try popoverWindow {
        at(top: 190, left: 180, Box().frame(width: px(40), height: px(20))
            .popover(isPresented: shownBinding(log)) { content100x50() })
    }
    let (explicit, _) = try popoverWindow { centred(log, edge: nil) }
    #expect(xywh(try chrome(omitted)) == [138, 108, 124, 74], "no edge: above")
    #expect(xywh(try chrome(explicit)) == [138, 108, 124, 74], "arrowEdge: nil: above")
    withExtendedLifetime((omitted, explicit)) {}
}

/// **3.3** (P5, divergence 111). A popover that would leave the window on its
/// edge's side, and fits on the opposite one, flips there: `.top` over an
/// anchor 40 pt from the top goes below it, `.leading` beside an anchor 20 pt
/// from the left goes right of it. Mutation: drop the flip.
@MainActor
@Test func aPopoverThatWouldLeaveTheWindowFlipsToTheOppositeEdge() throws {
    let log = PLog()
    let (top, _) = try popoverWindow {
        at(top: 40, left: 180, Box().frame(width: px(40), height: px(20))
            .popover(isPresented: shownBinding(log), arrowEdge: .top) { content100x50() })
    }
    let (leading, _) = try popoverWindow {
        at(top: 190, left: 20, Box().frame(width: px(40), height: px(20))
            .popover(isPresented: shownBinding(log), arrowEdge: .leading) { content100x50() })
    }
    #expect(xywh(try chrome(top)) == [138, 68, 124, 74], "flipped below: 60 + 8")
    #expect(xywh(try chrome(leading)) == [68, 163, 124, 74], "flipped right: 60 + 8")
    withExtendedLifetime((top, leading)) {}
}

/// **3.4** (divergence 111). A popover that fits on neither side stays on its
/// own and is clamped inside the window with 8 pt: a 124 × 324 chrome above
/// the centred anchor. Mutation: flip anyway.
@MainActor
@Test func aPopoverThatFitsNeitherSideIsClampedInsideTheWindow() throws {
    let log = PLog()
    let (window, _) = try popoverWindow {
        at(top: 190, left: 180, Box().frame(width: px(40), height: px(20))
            .popover(isPresented: shownBinding(log), arrowEdge: .top) { Box().frame(width: px(100), height: px(300)) })
    }
    #expect(xywh(try chrome(window)) == [138, 8, 124, 324], "on its side, clamped to the 8-pt margin")
    withExtendedLifetime(window) {}
}

// MARK: - 3.5–3.8, 3.26: dismissal and interaction

/// The `Under` button centred in a 400 × 100 frame at the top (its label's
/// hitbox around (200, 50)), the 40 × 20 anchor at (180, 190) with a popover
/// holding the 100 × 50 `In` button.
@MainActor private func underAndAnchor(_ log: PLog) -> some Element {
    Column {
        Button("Under") { log.entries.append("under") }.frame(width: px(400), height: px(100))
        Box().frame(width: px(1), height: px(90))
        Row {
            Box().frame(width: px(180), height: px(1))
            Box().frame(width: px(40), height: px(20)).popover(isPresented: shownBinding(log)) {
                Button("In") { log.entries.append("in") }.frame(width: px(100), height: px(50))
            }
            Box().frame(width: px(180), height: px(1))
        }
        Box().frame(width: px(1), height: px(190))
    }
}

/// **3.5** (P4a, `MN-Y` item 1). A press outside the popover writes its
/// binding `false` from input — at the press — and then reaches the `Button`
/// it lands on, which runs once on the release. Mutation: claim the press
/// after dismissing.
@MainActor
@Test func aPressOutsideThePopoverWritesFalseAndReachesWhatItLandsOn() throws {
    let log = PLog()
    let (window, platform) = try popoverWindow { underAndAnchor(log) }
    _ = try chrome(window)
    platform.simulateInput(ldown(200, 50))
    #expect(log.entries == ["shown=false"], "dismissed at the press, from input")
    platform.simulateInput(lup(200, 50))
    #expect(log.entries == ["shown=false", "under"], "then the press reached the button beneath")
    redraw(window)
    #expect(window.lastOpenPopovers.isEmpty)
    withExtendedLifetime(window) {}
}

/// **3.6** (`MN-Y` item 3). A press inside the popover reaches its content: the
/// `In` button runs and the popover stays. Mutation: dismiss on every press.
@MainActor
@Test func aPressInsideThePopoverReachesItsContent() throws {
    let log = PLog()
    let (window, platform) = try popoverWindow { underAndAnchor(log) }
    #expect(xywh(try chrome(window)) == [138, 108, 124, 74])
    platform.simulateInput(ldown(200, 145))
    platform.simulateInput(lup(200, 145))
    #expect(log.entries == ["in"])
    redraw(window)
    #expect(window.lastOpenPopovers.count == 1, "still open")
    withExtendedLifetime(window) {}
}

/// **3.7** (`MN-N` item 2). Escape dismisses the topmost popover — a popover
/// opened from inside another — before the keymap sees it; the next Escape the
/// outer one; only the third reaches the keymap's Escape binding. Mutation:
/// run the stage after `dispatchAction`.
@MainActor
@Test func escapeDismissesTheTopmostPopoverBeforeTheKeymap() throws {
    let log = PLog()
    let (window, platform) = try popoverWindow {
        at(top: 190, left: 180, Box().frame(width: px(40), height: px(20)).popover(isPresented: shownBinding(log)) {
            Box().frame(width: px(40), height: px(20)).popover(isPresented: innerBinding(log)) {
                Box().frame(width: px(60), height: px(30))
            }
        })
    }
    window.keymap = Keymap { KeyBinding("escape", PEscape()) }
    window.onAction = { action in
        guard action is PEscape else { return false }
        log.entries.append("keymap")
        return true
    }
    try #require(window.lastOpenPopovers.count == 2, "both popovers open")
    platform.simulateInput(key(escapeKey))
    #expect(log.entries == ["inner=false"], "the inner (topmost) popover first")
    redraw(window)
    platform.simulateInput(key(escapeKey))
    #expect(log.entries == ["inner=false", "shown=false"], "then the outer")
    redraw(window)
    platform.simulateInput(key(escapeKey))
    #expect(log.entries == ["inner=false", "shown=false", "keymap"], "none open: the keymap's")
    withExtendedLifetime(window) {}
}

private let utf8 = PasteboardType(identifier: "public.utf8-plain-text",
                                  conformsTo: ["public.plain-text", "public.text", "public.data", "public.item"])

/// **3.8** (`MN-N` item 4, `MN-Z`). The popover is a presentation on a higher
/// layer: a press and a drop on the chrome's padding reach nothing beneath (the
/// 400 × 190 `Under` click target there neither runs nor takes the drop), and a press-drag
/// inside it reaches no declaring ancestor's `DragGesture` (`IX-Q`). Controls:
/// the same drop and drag outside the popover reach both. Mutations: drop the
/// chrome's blocking hitbox; register the popover at the declarer's layer.
@MainActor
@Test func aPopoverIsAPresentationOnAHigherLayer() throws {
    let log = PLog()
    let (window, platform) = try popoverWindow {
        Box {
            Column {
                Box().frame(width: px(400), height: px(190)).onClick { log.entries.append("under") }
                    .dropDestination(for: String.self, action: { _, _ in log.entries.append("drop"); return true },
                                     isTargeted: { log.entries.append("T=\($0)") })
                Row {
                    Box().frame(width: px(180), height: px(1))
                    Box().frame(width: px(40), height: px(20)).popover(isPresented: shownBinding(log)) {
                        Box().frame(width: px(100), height: px(50))
                    }
                    Box().frame(width: px(180), height: px(1))
                }
                Box().frame(width: px(1), height: px(190))
            }
        }
        .gesture(DragGesture().onChanged { _ in log.entries.append("drag") })
    }
    #expect(xywh(try chrome(window)) == [138, 108, 124, 74])
    let item = DropItem(types: [utf8]) { _ in Array("x".utf8) }
    // The chrome's padding, over the `Under` button.
    #expect(!platform.simulateDrop(.entered(position: pt(142, 112), items: [item])), "the chrome blocks a drop")
    _ = platform.simulateDrop(.exited)
    platform.simulateInput(ldown(142, 112))
    platform.simulateInput(dragged(180, 112))
    platform.simulateInput(dragged(220, 112))
    platform.simulateInput(lup(220, 112))
    #expect(log.entries == [], "nothing beneath ran, and the ancestor's drag did not")
    #expect(log.shown, "a press inside does not dismiss")
    // Controls, outside the popover.
    #expect(platform.simulateDrop(.entered(position: pt(20, 20), items: [item])), "control: the destination")
    _ = platform.simulateDrop(.exited)
    log.entries = []
    platform.simulateInput(ldown(20, 300))
    platform.simulateInput(dragged(60, 300))
    platform.simulateInput(dragged(100, 300))
    platform.simulateInput(lup(100, 300))
    #expect(log.entries.first == "shown=false" && log.entries.contains("drag"),
            "control: outside, the press dismisses and the ancestor's drag runs: \(log.entries)")
    withExtendedLifetime(window) {}
}

/// **3.26** (`MN-Y` item 2). A press on the popover's own anchor dismisses it
/// and is consumed with its release: a `Button { shown.toggle() }` anchor
/// closes the popover rather than re-presenting it. Mutation: treat the anchor
/// as any outside point.
@MainActor
@Test func aPressOnTheAnchorDismissesThePopoverAndIsConsumed() throws {
    let log = PLog()
    let (window, platform) = try popoverWindow {
        at(top: 190, left: 180, Button("Toggle") { log.shown.toggle(); log.entries.append("toggle") }
            .frame(width: px(40), height: px(20))
            .popover(isPresented: shownBinding(log)) { content100x50() })
    }
    _ = try chrome(window)
    platform.simulateInput(ldown(200, 200))
    platform.simulateInput(lup(200, 200))
    #expect(log.entries == ["shown=false"], "dismissed, and the button did not run")
    #expect(!log.shown)
    redraw(window)
    #expect(!log.shown && window.lastOpenPopovers.isEmpty, "still dismissed on the next frame")
    withExtendedLifetime(window) {}
}

// MARK: - 3.9: accessibility

/// Every node of `tree` below `id`, depth first.
private func descendants(_ tree: AccessibilityTree, of id: AccessibilityNodeID) -> [AccessibilityNode] {
    guard let node = tree.nodes[id] else { return [] }
    return node.children.flatMap { child in (tree.nodes[child].map { [$0] } ?? []) + descendants(tree, of: child) }
}

/// **3.9** (P2, P2b, `MN-O`). While a client is active the popover publishes a
/// `.popover` node holding its content, and the window's other nodes keep
/// publishing — no modal isolation. Mutation: mark it `.isModal`.
@MainActor
@Test func thePopoverPublishesAPopoverNodeAndIsolatesNothing() throws {
    let log = PLog()
    let (window, platform) = try popoverWindow { underAndAnchor(log) }
    platform.simulateAccessibilityRequest(.activate)
    redraw(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let popovers = tree.nodes.filter { $0.value.role == .popover }
    try #require(popovers.count == 1, "one popover node: \(tree.nodes.values.map(\.role))")
    let held = descendants(tree, of: popovers.keys.first!)
    #expect(held.contains { $0.label == "In" && $0.role == .button }, "it holds its content")
    #expect(tree.nodes.values.contains { $0.label == "Under" && $0.role == .button },
            "the window's other nodes are still published")
    withExtendedLifetime(window) {}
}

// MARK: - 3.10–3.15: identity, state and frames

/// **3.10** (`MN-L` item 2). `.popover` adds one identity level, for its caller
/// only: the anchor's id is `child(of: plain, at: 0)`, its siblings' ids are
/// unmoved, and the popover's content lives under `child(of: plain, at: 1)`.
/// Mutation: put the slot at `-1` (it collides with `.overlay`, `MC-P`).
@MainActor
@Test func aPopoverAddsOneIdentityLevelOnlyForItsCaller() throws {
    let log = PLog()
    let (plain, _) = try popoverWindow {
        Column {
            Button("A") { log.entries.append("A") }
            Button("B") { log.entries.append("B") }
            Button("C") { log.entries.append("C") }
        }
    }
    let (wrapped, _) = try popoverWindow {
        Column {
            Button("A") { log.entries.append("A") }
            Button("B") { log.entries.append("B") }.popover(isPresented: shownBinding(log)) {
                Button("In") { log.entries.append("In") }
            }
            Button("C") { log.entries.append("C") }
        }
    }
    try #require(!wrapped.lastOpenPopovers.isEmpty, "presented")
    let before = wrapped.lastHitboxes.filter { $0.opaque && $0.handlers.onClick != nil }.map(\.id)
    let after = plain.lastHitboxes.filter { $0.opaque && $0.handlers.onClick != nil }.map(\.id)
    try #require(before.count == 4 && after.count == 3, "A, B, C (and In): \(before.count), \(after.count)")
    let a = after[0], b = after[1], c = after[2]
    #expect(before.contains(a) && before.contains(c), "the siblings' ids are unmoved")
    #expect(before.contains(GlobalElementID.child(of: b, at: 0, name: nil)), "the anchor at 0 under the wrapper")
    let slot = GlobalElementID.child(of: b, at: 1, name: nil)
    let inner = try #require(before.first { ![a, c, GlobalElementID.child(of: b, at: 0, name: nil)].contains($0) })
    var cursor: GlobalElementID? = inner
    var underSlot = false
    while let id = cursor { if id == slot { underSlot = true }; cursor = id.parent }
    #expect(underSlot, "the popover's content descends from the slot at cursor 1: \(inner)")
    withExtendedLifetime((plain, wrapped)) {}
}

/// A 100 × 50 button counting its presses in `@State`, logging each count.
private struct PCounter: Component {
    @State var n = 0
    let log: PLog

    var content: some ElementGroup {
        Button("Count") { n += 1; log.entries.append("n=\(n)") }.frame(width: Pixels(100), height: Pixels(50))
    }
}

/// **3.11** (`MN-L` item 2, `ID-C`). A re-presented popover's content starts
/// fresh: a counter at 2 reads 1 after one press once dismissed and presented
/// again. Mutation: keep the slot produced while dismissed.
@MainActor
@Test func aRepresentedPopoversContentStartsFresh() throws {
    let log = PLog()
    let (window, platform) = try popoverWindow {
        at(top: 190, left: 180, Box().frame(width: px(40), height: px(20))
            .popover(isPresented: shownBinding(log)) { PCounter(log: log) })
    }
    for _ in 0..<2 {
        platform.simulateInput(ldown(200, 145))
        platform.simulateInput(lup(200, 145))
        redraw(window)
    }
    #expect(log.entries == ["n=1", "n=2"])
    log.shown = false
    redraw(window)
    try #require(window.lastOpenPopovers.isEmpty)
    log.shown = true
    redraw(window)
    try #require(window.lastOpenPopovers.count == 1)
    platform.simulateInput(ldown(200, 145))
    platform.simulateInput(lup(200, 145))
    #expect(log.entries == ["n=1", "n=2", "n=1"], "fresh state after re-presenting")
    withExtendedLifetime(window) {}
}

/// **3.12** (P6, `MN-L` items 1–2, `ID-R`). `popover(item:)`: `nil` presents
/// nothing; item 1 presents, its counter counting; item 2 starts fresh.
/// Mutation: drop the item's name.
@MainActor
@Test func popoverItemFollowsTheItemAndResetsOnANewID() throws {
    let log = PLog()
    let (window, platform) = try popoverWindow {
        at(top: 190, left: 180, Box().frame(width: px(40), height: px(20))
            .popover(item: itemBinding(log)) { _ in PCounter(log: log) })
    }
    #expect(window.lastOpenPopovers.isEmpty, "nil: nothing")
    log.item = PItem(id: 1)
    redraw(window)
    try #require(window.lastOpenPopovers.count == 1, "item 1 presents")
    for _ in 0..<2 {
        platform.simulateInput(ldown(200, 145))
        platform.simulateInput(lup(200, 145))
        redraw(window)
    }
    log.item = PItem(id: 2)
    redraw(window)
    platform.simulateInput(ldown(200, 145))
    platform.simulateInput(lup(200, 145))
    #expect(log.entries == ["n=1", "n=2", "n=1"], "item 2's content starts fresh")
    platform.simulateInput(ldown(20, 20))
    #expect(log.entries.last == "item=nil", "an outside press writes nil")
    withExtendedLifetime(window) {}
}

/// **3.13** (`MN-M` item 2). When the anchor moves, the frame that moves it
/// asks for one more, and that one places the popover at the new anchor; then
/// the window goes clean. Mutation: no another-frame request.
@MainActor
@Test func aPopoverFollowsItsAnchorWithinOneFrame() throws {
    let log = PLog()
    let (window, _) = try popoverWindow {
        at(top: log.top, left: 180, Box().frame(width: px(40), height: px(20))
            .popover(isPresented: shownBinding(log)) { content100x50() })
    }
    #expect(xywh(try chrome(window)) == [138, 108, 124, 74])
    log.top = 250
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(xywh(try chrome(window)) == [138, 108, 124, 74], "placed against the last frame's anchor")
    try #require(window.needsRedraw, "the moved anchor asked for another frame")
    window.drawFrameIfNeeded()
    #expect(xywh(try chrome(window)) == [138, 168, 124, 74], "the next frame follows it: 250 − 8 − 74")
    #expect(!window.needsRedraw, "and then the window is clean")
    withExtendedLifetime(window) {}
}

/// **3.14** (`MN-M` item 2). A popover presented from the start appears on the
/// second frame: the first has no anchor yet and asks for another. Mutation:
/// produce it with a zero anchor on the first frame.
@MainActor
@Test func anInitiallyPresentedPopoverAppearsOnTheSecondFrame() throws {
    let log = PLog()
    let (window, _) = try popoverWindow(settle: false) { centred(log, edge: nil) }
    #expect(window.lastOpenPopovers.isEmpty, "frame 0: none")
    try #require(window.needsRedraw, "frame 0 asked for another")
    window.drawFrameIfNeeded()
    #expect(xywh(try chrome(window)) == [138, 108, 124, 74], "frame 1: shown")
    withExtendedLifetime(window) {}
}

/// **3.15** (`MN-M` item 2). A popover writes no `StateTable` entry of its own
/// — its anchor lives in the window's anchor map: every entry presenting adds
/// descends from the popover's slot (the chrome's and content's own element
/// slots), none sits under the wrapper elsewhere, and dismissing returns the
/// table to its dismissed count (`ID-C`). Mutation: keep the anchor in
/// `StateTable`.
@MainActor
@Test func aPopoverWritesNoStateTableEntry() throws {
    let log = PLog()
    log.shown = false
    let (window, _) = try popoverWindow { centred(log, edge: nil) }
    let dismissed = window.stateTable.count
    let before = window.stateTable.ids
    log.shown = true
    redraw(window)
    let wrapper = try #require(window.lastOpenPopovers.first, "presented").id
    let slot = GlobalElementID.child(of: wrapper, at: 1, name: nil)
    let added = window.stateTable.ids.subtracting(before)
    func descends(_ id: GlobalElementID, from ancestor: GlobalElementID) -> Bool {
        var cursor: GlobalElementID? = id
        while let current = cursor { if current == ancestor { return true }; cursor = current.parent }
        return false
    }
    try #require(!added.isEmpty, "the chrome and content write their element slots")
    #expect(added.allSatisfy { descends($0, from: slot) }, "every added entry is inside the popover's slot")
    log.shown = false
    redraw(window)
    #expect(window.stateTable.count == dismissed, "dismissed again: the popover's entries are gone")
    withExtendedLifetime(window) {}
}

// MARK: - 3.16: the chrome

/// **3.16** (divergence 112, `MN-M` item 5). The chrome is one `.surface`
/// rounded rectangle (radius 10, a 1-pt `.separator` border) and its shadow,
/// and nothing else: no arrow. The content draws nothing. Mutation (a pin of
/// the absence): add a triangle path.
@MainActor
@Test func thePopoverChromeIsARoundedPanelWithNoArrow() throws {
    let log = PLog()
    let (window, _) = try popoverWindow { centred(log, edge: nil) }
    let scene = window.lastScene
    let layer = try #require(scene.highestLayer)
    try #require(layer > 0, "the popover is on a higher layer")
    let rects = scene.rects.indices.filter { scene.layer(of: .rect, at: $0) == layer }.map { scene.rects[$0] }
    let images = scene.images.indices.filter { scene.layer(of: .image, at: $0) == layer }
    let glyphs = scene.glyphs.indices.filter { scene.layer(of: .glyph, at: $0) == layer }
    try #require(rects.count == 1, "one rect: \(rects.count)")
    let rect = rects[0]
    #expect([rect.bounds.origin.x, rect.bounds.origin.y, rect.bounds.size.width, rect.bounds.size.height]
            == [138, 108, 124, 74])
    #expect([rect.cornerRadii.topLeft, rect.cornerRadii.topRight, rect.cornerRadii.bottomRight,
             rect.cornerRadii.bottomLeft] == [10, 10, 10, 10])
    #expect(rect.borderWidths.top == 1)
    let surface = window.theme[.surface]
    #expect(rect.background.h == surface.h && rect.background.l == surface.l, "the .surface fill")
    #expect(images.count == 1, "one image, the shadow — no arrow path: \(images.count)")
    #expect(glyphs.isEmpty)
    withExtendedLifetime(window) {}
}
