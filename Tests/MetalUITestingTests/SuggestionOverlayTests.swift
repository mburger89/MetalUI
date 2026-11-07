import Foundation
import MetalUI
import MetalUITesting
import Observation
import Testing

// `suggestionOverlay` (ruling prefix `SOC-`, record 234): an anchored list that takes no
// focus and no keys. PLAIN imports; headless `TestWindow`; Noto Sans on every platform.

@Observable @MainActor private final class ComposerModel {
    var text = ""
    var shown = true
    /// What the field's `onKeyPress` saw, in order.
    var keys: [String] = []
    /// Whether the field's handler consumes ↓ / Return / Esc.
    var consumes = true
    var picked: [String] = []
    var shownBinding: Binding<Bool> { Binding(get: { self.shown }, set: { self.shown = $0 }) }
    var textBinding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
}

private let rowTitles = ["/clear", "/compact", "/help"]

/// A composer `topGap` points down a 400 x 300 window, a sibling button under it that the
/// overlay overlaps when it is shown below.
@MainActor private func composer(_ m: ComposerModel, topGap: Float = 150, edge: VerticalEdge = .top,
                                 alignment: HorizontalAlignment = .leading) -> some Element {
    VStack(spacing: 0) {
        Color.clear.frame(width: Pixels(300), height: Pixels(topGap))
        TextField("Message", text: m.textBinding)
            .accessibilityIdentifier("field")
            .onKeyPress(keys: [.downArrow, .upArrow, .return, .escape, .tab]) { press in
                m.keys.append(String(press.key.character.unicodeScalars.first!.value, radix: 16))
                return m.consumes ? .handled : .ignored
            }
            .frame(width: Pixels(200), height: Pixels(24))
            .suggestionOverlay(isPresented: m.shownBinding, edge: edge, alignment: alignment) {
                VStack(spacing: 0) {
                    ForEach(rowTitles, id: \.self) { title in
                        Button { m.picked.append(title) } label: {
                            Text(title).frame(width: Pixels(160), height: Pixels(24))
                        }
                    }
                }
            }
        Button { m.picked.append("below") } label: {
            Text("below").frame(width: Pixels(200), height: Pixels(30))
        }
        Spacer(minLength: 0)
    }
}

private extension Bounds where Unit == Pixels {
    /// The 24-point frame the composer's field is declared with, which its accessibility frame
    /// (26 tall, chrome included) is centred on.
    var declaredTop: Float { origin.y.value + size.height.value / 2 - 12 }
    var declaredBottom: Float { origin.y.value + size.height.value / 2 + 12 }
    var sTop: Float { origin.y.value }
    var sBottom: Float { origin.y.value + size.height.value }
    var sLeft: Float { origin.x.value }
}

/// A harness window with the frame a presentation needs to be placed (it appears on the frame
/// after its declarer was first laid out, as `.popover` does).
@MainActor private func settledWindow<Root: Element>(size: Size<Pixels> = sz(400, 300),
                                                     _ content: @escaping @MainActor () -> Root) throws -> TestWindow {
    let window = try harnessWindow(size: size, content)
    window.tick()
    window.tick()
    return window
}

@MainActor private func focusedID(_ window: TestWindow) throws -> String? {
    try window.focusedElement?.identifier
}

/// 1 - typing continues into the field while the list is shown; the field stays focused.
/// Mutation: make the overlay's content take focus (a `.focusable()` first row) / capture
/// text input.
@Test @MainActor func typingContinuesIntoTheFieldWhileTheOverlayIsShown() throws {
    let m = ComposerModel()
    let window = try settledWindow { composer(m) }
    try window.click(try window.element(identifier: "field"))
    window.typeText("/he")
    #expect(m.text == "/he", "the field typed")
    #expect(try focusedID(window) == "field", "and kept the focus")
    let help = try window.element(label: "/help")
    #expect(m.shown && help.frame.size.width.value > 0, "the list is up")
    window.typeText("l")
    #expect(m.text == "/hel")
}

/// 2 - the field's onKeyPress sees ↓, Return and Esc and can consume them; an ignored key
/// reaches the field. Mutation: register the overlay in the popover dismissal stack (Esc
/// then writes nothing here but is consumed before onKeyPress), or give it a key stage.
@Test @MainActor func theFieldsOnKeyPressSeesTheNavigationKeysAndEscape() throws {
    let m = ComposerModel()
    let window = try settledWindow { composer(m) }
    try window.click(try window.element(identifier: "field"))
    window.typeKey(.downArrow)
    window.typeKey(.return)
    window.typeKey(.escape)
    window.typeKey(.tab)
    #expect(m.keys == ["f701", "d", "1b", "9"], "all four reached the field's handler: \(m.keys)")
    #expect(m.shown, "Escape did not dismiss it: the app does that")
    #expect(try focusedID(window) == "field", "Tab consumed by the app did not move focus")
    #expect(m.text == "")
    m.consumes = false
    window.typeKey(.escape)
    #expect(m.shown, "an ignored Escape still dismisses nothing")
}

/// 3 - a press on a row runs its action and the field keeps the focus (and the caret: typing
/// continues). Mutation: let a press on the overlay clear focus (hoverKeyRegion-like) or make
/// the overlay's hitbox non-opaque so the press falls to the sibling.
@Test @MainActor func clickingARowRunsItAndTheFieldKeepsFocus() throws {
    let m = ComposerModel()
    let window = try settledWindow { composer(m) }
    try window.click(try window.element(identifier: "field"))
    window.typeText("/")
    try window.click(try window.element(label: "/compact"))
    #expect(m.picked == ["/compact"])
    #expect(try focusedID(window) == "field", "a press on the overlay did not blur the field")
    window.typeText("c")
    #expect(m.text == "/c", "and typing still lands in it")
    #expect(m.shown, "a click does not dismiss: the app does")
}

/// 4 - an outside click does not dismiss it (the binding is never written).
/// Mutation: route the overlay through `registerOpenPopover`.
@Test @MainActor func anOutsideClickLeavesItShown() throws {
    let m = ComposerModel()
    let window = try settledWindow { composer(m) }
    window.click(at: pt(380, 20))
    #expect(m.shown)
    try window.click(try window.element(label: "below"))
    #expect(m.shown && m.picked == ["below"], "the click reached what it landed on")
}

/// 5 - edge .top puts it above the field, spacing 4 off, leading edges flush; .bottom below.
/// Mutation: swap the edge.
@Test @MainActor func itSitsAboveTheFieldOnTopAndBelowOnBottom() throws {
    let above = ComposerModel()
    let window = try settledWindow { composer(above, edge: .top) }
    let field = try window.element(identifier: "field").frame
    let row = try window.element(label: "/help").frame
    let first = try window.element(label: "/clear").frame
    #expect(abs(first.sLeft - field.sLeft) < 0.5, "leading edges flush")
    #expect(abs(row.sBottom - (field.declaredTop - 4)) < 0.5, "the last row ends 4 above the field: \(row) \(field)")
    let below = ComposerModel()
    let lower = try settledWindow { composer(below, edge: .bottom) }
    let f2 = try lower.element(identifier: "field").frame
    let top2 = try lower.element(label: "/clear").frame
    #expect(abs(top2.sTop - (f2.declaredBottom + 4)) < 0.5, "4 below the field: \(top2) \(f2)")
}

/// 6 - near the window top it flips below; near the bottom with edge .bottom it flips above.
/// Mutation: drop the flip.
@Test @MainActor func itFlipsToTheOtherEdgeWhereItWouldLeaveTheWindow() throws {
    let m = ComposerModel()
    let window = try settledWindow { composer(m, topGap: 20, edge: .top) }
    let field = try window.element(identifier: "field").frame
    let first = try window.element(label: "/clear").frame
    #expect(first.sTop >= field.declaredBottom, "flipped below the field: \(first) \(field)")
    let low = ComposerModel()
    let tall = try settledWindow(size: sz(400, 150)) { composer(low, topGap: 80, edge: .bottom) }
    let f2 = try tall.element(identifier: "field").frame
    let last = try tall.element(label: "/help").frame
    #expect(last.sBottom <= f2.declaredTop + 0.5, "flipped above the field: \(last) \(f2)")
}

/// 7 - clamped horizontally: a trailing-aligned list wider than the room left of the field
/// stays inside the window.
@Test @MainActor func itIsClampedInsideTheWindowHorizontally() throws {
    let m = ComposerModel()
    let window = try settledWindow(size: sz(400, 300)) {
        HStack(spacing: 0) {
            Color.clear.frame(width: Pixels(250), height: Pixels(10))
            VStack(spacing: 0) {
                Color.clear.frame(width: Pixels(10), height: Pixels(150))
                TextField("Message", text: m.textBinding).accessibilityIdentifier("field")
                    .frame(width: Pixels(100), height: Pixels(24))
                    .suggestionOverlay(isPresented: m.shownBinding, alignment: .leading) {
                        Button {} label: { Text("wide").frame(width: Pixels(150), height: Pixels(24)) }
                    }
            }
        }
    }
    let wide = try window.element(label: "wide").frame
    #expect((wide.sLeft + wide.size.width.value) <= 400.5, "inside the right edge: \(wide)")
    let field = try window.element(identifier: "field").frame
    #expect(wide.sLeft < field.sLeft - 1, "pulled left of the field's leading edge by the clamp: \(wide) \(field)")
}

/// 8 - it is above sibling views in hit-test order: where it overlaps a sibling, the press
/// lands on the row. Mutation: not a presentation layer (ordinary overlay) / non-opaque.
@Test @MainActor func itIsAboveSiblingsInHitTestOrder() throws {
    let m = ComposerModel()
    let window = try settledWindow {
        ZStack(alignment: .topLeading) {
            // A sibling full-window button underneath everything.
            Button { m.picked.append("under") } label: {
                Text("under").frame(width: Pixels(400), height: Pixels(300))
            }
            composer(m)
        }
    }
    let row = try window.element(label: "/compact").frame
    window.click(at: pt(row.sLeft + 20, row.sTop + 12))
    #expect(m.picked == ["/compact"], "the overlay took the press, not the sibling: \(m.picked)")
}

/// 9 - nothing drawn or hit while the binding is false; it appears when set.
/// Mutation: ignore the binding.
@Test @MainActor func nothingIsDrawnOrHitWhileNotPresented() throws {
    let m = ComposerModel()
    m.shown = false
    let window = try settledWindow { composer(m) }
    #expect((try? window.element(label: "/help")) == nil, "no row in the tree")
    let drawn = window.scene.glyphs.count
    m.shown = true
    window.tick()
    window.tick()
    #expect((try? window.element(label: "/help")) != nil, "shown once set")
    #expect(window.scene.glyphs.count > drawn, "and drawn")
    m.shown = false
    window.tick()
    window.tick()
    #expect((try? window.element(label: "/help")) == nil)
    window.click(at: pt(10, 100))
    #expect(m.picked.isEmpty)
}

/// 10 - wheel over a ScrollView in the overlay scrolls it, not what lies beneath.
@Test @MainActor func theWheelScrollsTheOverlaysScrollView() throws {
    let m = ComposerModel()
    let window = try settledWindow {
        VStack(spacing: 0) {
            Color.clear.frame(width: Pixels(300), height: Pixels(180))
            TextField("Message", text: m.textBinding).accessibilityIdentifier("field")
                .frame(width: Pixels(200), height: Pixels(24))
                .suggestionOverlay(isPresented: m.shownBinding) {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(0..<20, id: \.self) { i in
                                Text("item \(i)").frame(width: Pixels(160), height: Pixels(24))
                            }
                        }
                    }
                    .frame(width: Pixels(160), height: Pixels(96))
                }
        }
    }
    let before = try window.element(label: "item 0").frame
    window.scroll(at: pt(before.sLeft + 20, before.sTop + 20), byDeltaX: 0, deltaY: -48)
    window.tick()
    let after = try window.element(label: "item 0").frame
    #expect(after.sTop < before.sTop - 20, "scrolled: \(before) -> \(after)")
}

/// 11 - accessibility: the rows are in the tree as ordinary nodes; no `.popover` node.
/// Mutation: set `popoverHint` on the chrome.
@Test @MainActor func itsContentIsASiblingGroupNotAPopover() throws {
    let m = ComposerModel()
    let window = try settledWindow { composer(m) }
    #expect(try window.elements(role: .popover).isEmpty, "not modal")
    #expect(try window.elements(role: .button).count >= 4, "three rows and the sibling are all buttons")
}

/// 12 - where it fits on neither side it takes the side with more room and is capped to it
/// (so a ScrollView inside scrolls); it never covers the field.
@Test @MainActor func whereItFitsNeitherSideItIsCappedToTheRoomOfTheBetterOne() throws {
    let m = ComposerModel()
    let window = try settledWindow(size: sz(400, 150)) {
        VStack(spacing: 0) {
            Color.clear.frame(width: Pixels(300), height: Pixels(50))
            TextField("Message", text: m.textBinding).accessibilityIdentifier("field")
                .frame(width: Pixels(200), height: Pixels(24))
                .suggestionOverlay(isPresented: m.shownBinding) {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(0..<10, id: \.self) { i in Text("item \(i)").frame(width: Pixels(160), height: Pixels(24)) }
                        }
                    }
                    .frame(width: Pixels(160), height: Pixels(240))
                }
            Spacer(minLength: 0)
        }
    }
    let field = try window.element(identifier: "field").frame
    let box = try window.element(label: "item 0").frame
    // Below has 150 - 74 - 4 = 72 points; above has 46: it goes below, 72 tall.
    #expect(box.sTop >= field.declaredBottom, "below: \(box)")
    #expect(box.sTop < 100, "its first row starts right under the field, not pushed to fit 240: \(box)")
    // Only rows 0..2 fit the 72 points; the rest are clipped by the capped scroll view.
    let ninth = try window.element(label: "item 9").visibleFrame
    #expect(ninth.size.height.value < 1 || ninth.sTop >= 149.5, "later rows are clipped away: \(ninth)")
}

/// 13 - inside a `.hoverKeyRegion()` pane (a chat window) a press on a row still leaves the
/// field focused: the press-time focus stage only clears for a region on the cover's own
/// layer, and the overlay is on the presentation layer (`KF-F` item 3). A press on the pane's
/// bare background does clear it, so the arm separates.
@Test @MainActor func aPressOnARowInsideAKeyRegionDoesNotBlurTheField() throws {
    let m = ComposerModel()
    let window = try settledWindow {
        VStack(spacing: 0) { composer(m) }.frame(maxWidth: .infinity, maxHeight: .infinity).hoverKeyRegion()
    }
    try window.click(try window.element(identifier: "field"))
    #expect(try focusedID(window) == "field")
    try window.click(try window.element(label: "/compact"))
    #expect(m.picked == ["/compact"])
    #expect(try focusedID(window) == "field", "the row press kept the focus")
    window.click(at: pt(5, 5))
    #expect(try focusedID(window) == nil, "separating arm: the pane's own background press clears it")
}

/// 14 - a press and a wheel on the overlay's own padding (no hit target of its own) never reach a
/// view under it: the layer blocks what lies beneath (`MN-Z`'s footing). Mutation: a
/// non-opaque hitbox.
@Test @MainActor func aPressOnTheOverlaysPaddingDoesNotReachWhatLiesBeneath() throws {
    let m = ComposerModel()
    let window = try settledWindow {
        ZStack(alignment: .topLeading) {
            Button { m.picked.append("under") } label: {
                Text("under").frame(width: Pixels(400), height: Pixels(300))
            }
            VStack(spacing: 0) {
                Color.clear.frame(width: Pixels(300), height: Pixels(150))
                TextField("Message", text: m.textBinding).accessibilityIdentifier("field")
                    .frame(width: Pixels(200), height: Pixels(24))
                    .suggestionOverlay(isPresented: m.shownBinding) {
                        Button {} label: { Text("row").frame(width: Pixels(100), height: Pixels(24)) }
                            .padding(Pixels(10))
                    }
            }
        }
    }
    let row = try window.element(label: "row").frame
    window.click(at: pt(row.sLeft - 5, row.sTop + 10))
    #expect(m.picked.isEmpty, "the padding took the press: \(m.picked)")
    window.click(at: pt(20, 20))
    #expect(m.picked == ["under"], "separating arm: outside the overlay the sibling is hit")
}

/// 15 - both vocabularies: on a proposal container (`VStack`) it is the same wrapper and
/// anchors to the container's frame. Mutation: delete the `ProposalElementGroup` overload (does
/// not compile; the test is the use).
@Test @MainActor func itWorksOnAProposalContainerToo() throws {
    let m = ComposerModel()
    let window = try settledWindow {
        VStack(spacing: 0) {
            Color.clear.frame(width: Pixels(300), height: Pixels(150))
            VStack(spacing: 0) {
                TextField("Message", text: m.textBinding).accessibilityIdentifier("field")
                    .frame(width: Pixels(200), height: Pixels(24))
            }
            .suggestionOverlay(isPresented: m.shownBinding, edge: .top) {
                Button { m.picked.append("p") } label: { Text("proposal row").frame(width: Pixels(120), height: Pixels(24)) }
            }
            Spacer(minLength: 0)
        }
    }
    let row = try window.element(label: "proposal row").frame
    let field = try window.element(identifier: "field").frame
    #expect(row.sBottom <= field.declaredTop - 3, "above the container: \(row) \(field)")
    try window.click(try window.element(label: "proposal row"))
    #expect(m.picked == ["p"])
}
