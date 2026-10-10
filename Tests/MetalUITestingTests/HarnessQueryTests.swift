import MetalUI
import MetalUITesting
import Testing

// Spec §4.2 tests 2.1–2.8 and 2.23–2.26 (lane 2): queries over the published
// accessibility tree and input aimed at an element (rulings `HT-G`, `HT-F`),
// with PLAIN imports. Fixtures are fixed-size frames in the 400 × 300 window
// (`CN-J`: a root is placed centred at its own answer).

/// A counter whose button and text a test finds by label.
private struct PressCounter: Component {
    @State var count = 0
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Button("Press me") { count += 1 }
            Text("pressed \(count) times")
        }
    }
}

/// 2.1 — `element(identifier:)` finds a `.accessibilityIdentifier("save")`
/// button: role `.button`, its frame the 80 × 30 frame centred in the window,
/// (160, 135). Mutation: `accessibilityClientActive` off by default.
@Test @MainActor func elementByIdentifierReturnsItsFrame() throws {
    let window = try harnessWindow {
        Button("Save") {}.frame(width: Pixels(80), height: Pixels(30)).accessibilityIdentifier("save")
    }
    let save = try window.element(identifier: "save")
    #expect(save.role == .button)
    #expect(save.label == "Save")
    #expect(save.frame == rect(160, 135, 80, 30))
    #expect(save.visibleFrame == rect(160, 135, 80, 30))
    #expect(save.isEnabled)
}

/// 2.2 — `element(label:)` finds a static text by its string, which the node
/// carries as its value (`HT-S` item 9, `HT-T` item 1); a node whose
/// identifier (not label) is the string is not matched. Mutation: match on
/// `identifier` instead.
@Test @MainActor func elementByLabelFindsAStaticText() throws {
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Text("Hello")
            Button("Other") {}.accessibilityIdentifier("Greeting")
        }
    }
    let hello = try window.element(label: "Hello")
    #expect(hello.role == .staticText)
    #expect(hello.value == "Hello")
    #expect(throws: TestHarnessError.noElement("label \"Greeting\"")) { try window.element(label: "Greeting") }
}

/// 2.3 — `elements(role:)` lists six buttons in tree order, top to bottom.
/// Mutation: dictionary order (`nodes.values`) — six ids make a chance match
/// 1 in 720.
@Test @MainActor func elementsByRoleAreInTreeOrder() throws {
    let names = ["One", "Two", "Three", "Four", "Five", "Six"]
    let window = try harnessWindow {
        VStack(spacing: 0) {
            ForEach(names, id: \.self) { name in Button(name) {} }
        }
    }
    #expect(try window.elements(role: .button).map(\.label) == names)
    #expect(try window.elements { $0.role == .button && $0.label?.hasPrefix("T") == true }.map(\.label)
            == ["Two", "Three"])
}

/// 2.4 — a missing element throws `.noElement` and an ambiguous one
/// `.ambiguous`, each naming the query. Mutation: ambiguous returns the first.
@Test @MainActor func aMissingAndAnAmbiguousElementThrowNamingTheQuery() throws {
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Button("Same") {}
            Button("Same") {}
        }
    }
    #expect(throws: TestHarnessError.noElement("label \"Nope\"")) { try window.element(label: "Nope") }
    #expect(throws: TestHarnessError.ambiguous("label \"Same\"", count: 2)) { try window.element(label: "Same") }
    #expect(throws: TestHarnessError.noElement("identifier \"none\"")) { try window.element(identifier: "none") }
}

/// 2.5 — a click on an element aims at its **visible** frame's centre: a
/// button whose frame (y 290–330) runs past the 300-tall scroll viewport is
/// clicked at y 295, inside it — its frame's centre, y 310, is outside the
/// window. Mutation: aim at the `frame` centre.
@Test @MainActor func clickOnAnElementAimsAtItsVisibleFrame() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        ScrollView {
            Column {
                Box().frame(width: Pixels(400), height: Pixels(290))
                Button("Low") { log.add("low") }.frame(width: Pixels(400), height: Pixels(40))
                Box().frame(width: Pixels(400), height: Pixels(200))
            }
        }
    }
    let low = try window.element(label: "Low")
    #expect(low.frame == rect(0, 290, 400, 40))
    #expect(low.visibleFrame == rect(0, 290, 400, 10))
    try window.click(low)
    #expect(log.entries == ["low"])
}

/// 2.6 — an element scrolled fully out of its viewport has a zero-area
/// visible frame and is not hittable. Mutation: no zero check.
@Test @MainActor func aZeroAreaElementIsNotHittable() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        ScrollView {
            Column {
                Box().frame(width: Pixels(400), height: Pixels(300))
                Button("Hidden") { log.add("hidden") }.frame(width: Pixels(400), height: Pixels(40))
            }
        }
    }
    let hidden = try window.element(label: "Hidden")
    #expect(hidden.visibleFrame.size.height == Pixels(0))
    #expect(throws: TestHarnessError.notHittable("button \"Hidden\"")) { try window.click(hidden) }
    #expect(log.entries.isEmpty)
}

/// 2.7 — an accessibility press runs a button, as VoiceOver's press does.
/// Mutation: `.increment` sent for `.press`.
@Test @MainActor func anAccessibilityPressRunsAButton() throws {
    let log = HarnessLog()
    let window = try harnessWindow { Button("Go") { log.add("go") } }
    let go = try window.element(label: "Go")
    #expect(try window.performAccessibilityAction(.press, on: go))
    #expect(log.entries == ["go"])
}

/// 2.8 — Tab moves focus from button to button and `focusedElement` and each
/// element's `isFocused` follow; `focus(_:)` moves it back. Mutation:
/// `isFocused` read from the node's `isFocusable`.
@Test @MainActor func tabMovesFocusAndFocusedElementFollows() throws {
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Button("One") {}
            Button("Two") {}
        }
    }
    #expect(try window.focusedElement == nil)
    window.typeKey(.tab)
    #expect(try window.focusedElement?.label == "One")
    #expect(try window.element(label: "One").isFocused)
    #expect(try !window.element(label: "Two").isFocused)
    window.typeKey(.tab)
    #expect(try window.focusedElement?.label == "Two")
    #expect(try !window.element(label: "One").isFocused)
    try window.focus(window.element(label: "One"))
    #expect(try window.focusedElement?.label == "One")
}

/// 2.23 — a popover is a presentation root: its `.popover` node is found by
/// role (another root of the tree, `AB-V`) and lies inside the window.
/// Mutation: the query walk visits only `roots.first`.
@Test @MainActor func aPopoverAppearsInTheTreeInsideTheWindow() throws {
    let window = try harnessWindow {
        Box().frame(width: Pixels(60), height: Pixels(40)).background(.accent)
            .popover(isPresented: .constant(true)) {
                Text("Pop").frame(width: Pixels(100), height: Pixels(50))
            }
    }
    let popovers = try window.elements(role: .popover)
    try #require(popovers.count == 1)
    let frame = popovers[0].frame
    #expect(frame.size.width.value > 0 && frame.size.height.value > 0)
    #expect(frame.origin.x.value >= 0 && frame.origin.y.value >= 0)
    #expect(frame.origin.x.value + frame.size.width.value <= 400)
    #expect(frame.origin.y.value + frame.size.height.value <= 300)
    #expect(try window.element(label: "Pop").role == .staticText)
}

/// 2.24 — `pointerStyle` reads the style the window last asked for: the
/// pointing hand over a `.pointerStyle(.link)` box, the arrow once the pointer
/// leaves it. Mutation: the first recorded style read, not the last.
@Test @MainActor func pointerStyleFollowsHover() throws {
    let window = try harnessWindow {
        HStack(spacing: 0) {
            Box().frame(width: Pixels(50), height: Pixels(50)).onClick {}.pointerStyle(.link)
            Box().frame(width: Pixels(50), height: Pixels(50))
        }
    }
    window.hover(at: pt(175, 150))
    #expect(window.pointerStyle == .pointingHand)
    window.hover(at: pt(225, 150))
    #expect(window.pointerStyle == .arrow)
}

/// A field's text for 2.25.
@MainActor private final class FieldModel {
    var text = ""
}

/// 2.25 — ⌘A ⌘C in a focused field copies its text to the window's
/// clipboard. Mutation: `writeClipboard` drops the write.
@Test @MainActor func copyInAFieldReachesTheWindowsClipboard() throws {
    let model = FieldModel()
    let window = try harnessWindow {
        TextField("", text: Binding(get: { model.text }, set: { model.text = $0 }))
            .frame(width: Pixels(200))
    }
    let field = try #require(try window.elements(role: .textField).first)
    try window.typeText("abc", into: field)
    #expect(model.text == "abc")
    window.typeKey("a", modifierFlags: .command)
    window.typeKey("c", modifierFlags: .command)
    #expect(window.platformWindow.clipboard == "abc")
}

/// 2.26 — test 1.4 through the tree: the button found by its label is clicked
/// and the text found by its new string. Mutation: as 1.4's (`click` sends
/// only `.mouseDown`).
@Test @MainActor func aClickByElementReRunsLane1sClickTestThroughTheTree() throws {
    let window = try harnessWindow { VStack(spacing: 0) { PressCounter() } }
    #expect(try window.element(label: "pressed 0 times").role == .staticText)
    try window.click(window.element(label: "Press me"))
    #expect(try window.element(label: "pressed 1 times").role == .staticText)
    #expect(throws: TestHarnessError.noElement("label \"pressed 0 times\"")) {
        try window.element(label: "pressed 0 times")
    }
}
