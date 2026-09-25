import Foundation
import Metal
import Testing
import MetalUICore
import MetalUILayout
import MetalUIRender
import MetalUIShaderTypes
@testable import MetalUI

// The integration of plan tasks 3, 9 and 12 (`feat/modifier-composition`,
// `feat/environment`, `feat/ax-bridge`): behaviour that belongs to no single
// track because it exists only where two of them meet. Each test names the
// merge obligation it discharges and is recorded, with its mutations, in
// `docs/record/13-integration-tasks-3-9-12.md`.
//
// **This file imports `Metal`, so it must declare no `Dimension`-typed
// fixture** (`Fakes.swift`'s note on `AnimationTests.swift`).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func hsla(_ c: MUIHsla) -> Hsla { Hsla(h: c.h, s: c.s, l: c.l, a: c.a) }

@MainActor
private func click(_ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

@MainActor
private final class TapLog {
    var taps = 0
}

// MARK: - EV-X on the proposal path (environment EV-W item 1, last bullet)

/// **A proposal modifier written after an environment scope sits outside it**,
/// as a legacy frame layer does (`aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`'s
/// after arm) and as SwiftUI's does (probe `swiftui-disabled-ancestor-and-order.swift`
/// O2, O3, O6 — not re-probed here; this test measures MetalUI only).
///
/// The environment track left this unmeasured: over proposal content
/// `.padding(_:)` compiles after a scope, and its side was open (ruling EV-X).
/// Measured at integration, three spellings, each with a **disagreeing**
/// spelling that moves the scope outermost, so the arm is shown to tell inside
/// from outside rather than read light everywhere:
///
/// - `.theme(.dark).padding(1).background(.surface)`: the 13pt rectangle
///   paints dark, the 15pt background (the padding's size) light;
/// - `.theme(.dark).frame(minWidth: 22, maxWidth: 22).background(.surface)`: the
///   20pt rectangle dark, the 22pt background light;
/// - `.disabled(true).padding(0).onTap {}` fires; `.onTap {}.disabled(true)`
///   does not.
@MainActor
@Test func aProposalModifierWrittenAfterAScopeSitsOutsideIt() throws {
    let f = Frame(contentSize: Size(width: px(300), height: px(50)), scaleFactor: 1, theme: .light)
    var root = HStack(spacing: px(2)) {
        Rectangle(width: px(13), height: px(10), color: .surface)
            .theme(.dark).padding(Edges(all: px(1))).background(.surface)
        Rectangle(width: px(16), height: px(10), color: .surface)
            .padding(Edges(all: px(1))).background(.surface).theme(.dark)
        Rectangle(width: px(20), height: px(10), color: .surface)
            .theme(.dark).frame(minWidth: px(22), maxWidth: px(22)).background(.surface)
        Rectangle(width: px(24), height: px(10), color: .surface)
            .frame(minWidth: px(26), maxWidth: px(26)).background(.surface).theme(.dark)
    }
    f.render(&root)
    let rects = f.finalizedScene().rects
    func colour(_ width: Float) throws -> Hsla {
        hsla(try #require(rects.first { $0.bounds.size.width == width },
                          "no rect \(width) wide in \(rects.map(\.bounds.size.width))").background)
    }
    try #require(Theme.dark.surface != Theme.light.surface)

    #expect(try colour(13) == Theme.dark.surface)
    #expect(try colour(15) == Theme.light.surface, "a proposal padding written after a scope sits outside it")
    #expect(try colour(16) == Theme.dark.surface)
    #expect(try colour(18) == Theme.dark.surface, "the disagreeing spelling: the scope written last")

    #expect(try colour(20) == Theme.dark.surface)
    #expect(try colour(22) == Theme.light.surface, "a flexible frame written after a scope sits outside it")
    #expect(try colour(24) == Theme.dark.surface)
    #expect(try colour(26) == Theme.dark.surface, "the disagreeing spelling: the scope written last")

    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    func taps<Root: Element>(_ content: @escaping @MainActor (TapLog) -> Root) throws -> Int {
        let log = TapLog()
        let (window, platform) = try makeFakeWindow(device: device, size: 100) { content(log) }
        window.drawFrameIfNeeded()
        click(platform, at: pt(50, 50))
        return log.taps
    }
    let after = try taps { log in
        HStack {
            Rectangle(width: px(100), height: px(100))
                .disabled(true).padding(Edges(all: px(0))).onTap { log.taps += 1 }
        }
    }
    let before = try taps { log in
        HStack {
            Rectangle(width: px(100), height: px(100))
                .padding(Edges(all: px(0))).onTap { log.taps += 1 }.disabled(true)
        }
    }
    #expect(after == 1, "an onTap written after .disabled sits outside it and must fire")
    #expect(before == 0, "the disagreeing spelling: .disabled written last suppresses the tap")
}

// MARK: - Disabled state reaches accessibility (environment EV-W item 4, bridge AB-Z)

@MainActor
private final class Counts {
    var presses = 0
    var adjustments = 0
}

@MainActor private func drawUntilClean(_ window: Window, limit: Int = 5) {
    for _ in 0..<limit where window.needsRedraw { window.drawFrameIfNeeded() }
}

private struct Published {
    var node: AccessibilityNode
    var id: AccessibilityNodeID
    var window: Window
    var platform: FakePlatformWindow
}

/// One activated fake window over `content`, drawn until clean; its one
/// published node.
@MainActor private func publish<Root: Element>(_ name: String, device: any MTLDevice,
                                               _ content: @escaping @MainActor () -> Root) throws -> Published {
    let (window, platform) = try makeFakeWindow(device: device, size: 200, content: content)
    platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last, "\(name): nothing published")
    try #require(tree.nodes.count == 1, "\(name): one published node, read \(tree.nodes.count)")
    let (id, node) = try #require(tree.nodes.first)
    return Published(node: node, id: id, window: window, platform: platform)
}

/// A click-target arm: `make(false, _)` is the control, `make(true, _)` the
/// disabled half.
@MainActor private func clickable<Root: Element>(_ name: String, device: any MTLDevice,
                                                 _ make: @escaping @MainActor (Bool, Counts) -> Root) throws {
    let onCounts = Counts(), offCounts = Counts()
    let on = try publish(name, device: device) { make(false, onCounts) }
    let off = try publish(name, device: device) { make(true, offCounts) }

    try #require(on.node.role == .button && on.node.isEnabled && on.node.actions == [.press],
                 "\(name) control: an enabled pressable button, read \(on.node)")
    try #require(on.platform.simulateAccessibilityRequest(.press(on.id)), "\(name) control: the press is accepted")
    try #require(onCounts.presses == 1, "\(name) control: the press ran the handler")

    #expect(off.node.role == .button, "\(name): a disabled button is still a button")
    #expect(!off.node.isEnabled, "\(name): published enabled")
    #expect(off.node.actions == [], "\(name): advertises \(off.node.actions)")
    #expect(!off.platform.simulateAccessibilityRequest(.press(off.id)), "\(name): the press was accepted")
    #expect(offCounts.presses == 0, "\(name): the handler ran")
}

/// **The joint test the two tracks named and neither could write**: a disabled
/// element is still published, as disabled, and advertises and accepts none of
/// the actions its gated registrations would have given it (rulings EV-W item
/// 4, which supersedes `AB-Z` on the blocker hitbox, the `keyboard` copy, the
/// ungated `$focus` write and the `environment:` parameter).
///
/// **Presence and role read the ungated `handlers`; actions read the gated
/// registrations** — `.press` from the hitboxes, `isFocusable` and
/// `.increment`/`.decrement` from the focus registry — so there is no code of
/// its own to strip them. Five arms, each against a control identical but for
/// `.disabled(true)`, under a `Row` root in an activated fake window:
///
/// - **clickable**: one `.button`, `isEnabled` false, `actions` empty; `.press`
///   returns false and the handler does not run;
/// - **focusable**: published, `isEnabled` false, `isFocusable` false; `.focus`
///   returns false and nothing is focused;
/// - **adjustable**: published, `isEnabled` false, `actions` empty;
///   `.increment` returns false and the handler does not run;
/// - **outer modifier layer** (the composition merge): the `onClick` on the
///   `ModifiedElement`'s outermost layer, `….padding(2).onClick {}`;
/// - **inner modifier layer**: `….padding(2).onClick {}.padding(2)`, the click
///   target on an inner layer, which reaches `registerHandlers` through
///   `ModifiedElement.prepaintLayer` and no `Element.prepaintGroup`.
@MainActor
@Test func aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")

    try clickable("clickable", device: device) { d, counts in
        Row { Box().cssWidth(px(40)).cssHeight(px(20)).onClick { counts.presses += 1 }.disabled(d) }
    }
    try clickable("outer modifier layer", device: device) { d, counts in
        Row { Box().cssWidth(px(40)).cssHeight(px(20)).padding(px(2)).onClick { counts.presses += 1 }.disabled(d) }
    }
    try clickable("inner modifier layer", device: device) { d, counts in
        Row {
            Box().cssWidth(px(40)).cssHeight(px(20)).padding(px(2)).onClick { counts.presses += 1 }
                .padding(px(2)).disabled(d)
        }
    }

    // Focusable only.
    do {
        let on = try publish("focusable", device: device) { Row { Box().cssWidth(px(40)).cssHeight(px(20)).focusable().disabled(false) } }
        let off = try publish("focusable", device: device) { Row { Box().cssWidth(px(40)).cssHeight(px(20)).focusable().disabled(true) } }
        try #require(on.node.isEnabled && on.node.isFocusable, "focusable control: read \(on.node)")
        try #require(on.platform.simulateAccessibilityRequest(.focus(on.id)), "focusable control: the request is accepted")
        drawUntilClean(on.window)
        try #require(on.window.focusedElement != nil, "focusable control: something is focused")

        #expect(!off.node.isEnabled, "focusable: published enabled")
        #expect(!off.node.isFocusable, "focusable: published focusable")
        #expect(!off.platform.simulateAccessibilityRequest(.focus(off.id)), "focusable: the focus request was accepted")
        drawUntilClean(off.window)
        #expect(off.window.focusedElement == nil, "focusable: something is focused")
    }

    // Adjustable only.
    do {
        let onCounts = Counts(), offCounts = Counts()
        let on = try publish("adjustable", device: device) {
            Row {
                Box().cssWidth(px(40)).cssHeight(px(20))
                    .onAction(AccessibilityAdjustment.self) { _ in onCounts.adjustments += 1 }.disabled(false)
            }
        }
        let off = try publish("adjustable", device: device) {
            Row {
                Box().cssWidth(px(40)).cssHeight(px(20))
                    .onAction(AccessibilityAdjustment.self) { _ in offCounts.adjustments += 1 }.disabled(true)
            }
        }
        try #require(on.node.isEnabled && on.node.actions.contains(.increment), "adjustable control: read \(on.node)")
        try #require(on.platform.simulateAccessibilityRequest(.increment(on.id)), "adjustable control: accepted")
        try #require(onCounts.adjustments == 1, "adjustable control: the handler ran")

        #expect(!off.node.isEnabled, "adjustable: published enabled")
        #expect(off.node.actions == [], "adjustable: advertises \(off.node.actions)")
        #expect(!off.platform.simulateAccessibilityRequest(.increment(off.id)), "adjustable: the increment was accepted")
        #expect(offCounts.adjustments == 0, "adjustable: the handler ran")
    }
}

// MARK: - Accessibility across a modifier chain's identity change (MC-C × AB-D)

@MainActor
private final class LayerFlag {
    var adding = false
}

/// A labelled click target inside a labelled `ModifiedElement` chain, with one
/// more `.padding` layer when `adding` — the same TYPE either way, so the
/// change is a layer added at run time (ruling MC-C), not a structural `if`.
@MainActor private func labelledChain(adding: Bool) -> ModifiedElement<Box<EmptyGroup>> {
    var chain = Box().cssWidth(px(20)).cssHeight(px(20)).onClick {}.accessibilityLabel("leaf").padding(px(4))
    if adding { chain = chain.padding(px(4)) }
    return chain.onClick {}.accessibilityLabel("outer")
}

/// **What an accessibility client sees when a legacy modifier chain gains a
/// layer at run time** — where `MC-C` (the new outermost layer adopts the old
/// outermost id; the wrapped element moves one level down and resets) meets
/// `AB-D` (one element per id while published, detached on first absence).
///
/// Measured at integration, and pinned as it stands: the chain's outermost
/// node keeps its id, so a client holding it keeps a live element; the wrapped
/// element's id changes, so its old element is detached and a new one is
/// published; the tree never holds two nodes for one label, and the leaf is
/// still a child of the outer node. The control frame without the change
/// publishes the same ids twice, so the id comparison is shown to be able to
/// read "equal".
@MainActor
@Test func aLayerAddedAtRunTimeKeepsTheOutermostAccessibilityNodeAndRepublishesTheWrappedOne() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let flag = LayerFlag()
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        Row { labelledChain(adding: flag.adding) }
    }
    platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)

    func ids() throws -> (outer: AccessibilityNodeID, leaf: AccessibilityNodeID, tree: AccessibilityTree) {
        let tree = try #require(platform.publishedAccessibilityTrees.last)
        let outer = tree.nodes.filter { $0.value.label == "outer" }
        let leaf = tree.nodes.filter { $0.value.label == "leaf" }
        try #require(outer.count == 1 && leaf.count == 1,
                     "one node per label; read outer \(outer.count), leaf \(leaf.count)")
        return (outer[outer.startIndex].key, leaf[leaf.startIndex].key, tree)
    }

    let before = try ids()
    try #require(before.tree.nodes[before.outer]?.children == [before.leaf], "set up: the leaf is the outer node's child")

    window.setNeedsRedraw()
    drawUntilClean(window)
    let control = try ids()
    try #require(control.outer == before.outer && control.leaf == before.leaf,
                 "control: an unchanged chain republishes the same ids")

    flag.adding = true
    window.setNeedsRedraw()
    drawUntilClean(window)
    let after = try ids()
    #expect(after.outer == before.outer, "the outermost layer keeps its id (MC-C), so its element stays live")
    #expect(after.leaf != before.leaf, "the wrapped element moved one level down (MC-C), so it is republished")
    #expect(after.tree.nodes.count == before.tree.nodes.count, "the added layer publishes nothing of its own")
    #expect(after.tree.nodes[after.outer]?.children == [after.leaf], "the leaf is still the outer node's child")
}
