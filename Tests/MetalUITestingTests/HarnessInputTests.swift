import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Spec §4.1 tests 1.4–1.13, 1.15, 1.16: input by point, through the platform
// window's `onInput` — the closure `Window` installed — with AppKit's key
// routing (ruling `HT-F`). Every fixture is a fixed-size box centred in the
// 400 × 300 window (`CN-J`): a 40 × 40 box spans (180, 130)–(220, 170).

/// A box that widens by 20 per click: 40 wide fresh.
private struct HarnessCounter: Component {
    @State var count = 0
    var content: some ElementGroup {
        Box().frame(width: Pixels(40 + 20 * Float(count)), height: Pixels(40)).background(.accent)
            .onClick { count += 1 }
    }
}

/// 1.4 — a click at a point runs the box's `onClick` (a `@State` write) and the
/// frame the click draws shows it: the box is 60 wide. Mutation: `click`
/// sends only `.mouseDown`.
@Test @MainActor func aClickAtAPointRunsAnOnClickAndTheNextFrameShowsIt() throws {
    let window = try harnessWindow { VStack(spacing: 0) { HarnessCounter() } }
    #expect(rects(window, height: 40).map { $0.bounds.size.width } == [40])
    let drawn = window.framesDrawn
    window.click(at: pt(200, 150))
    #expect(window.framesDrawn == drawn + 1, "a click draws one frame")
    #expect(rects(window, height: 40).map { $0.bounds.size.width } == [60], "the click's write is in that frame")
}

/// 1.5 — a click moves the pointer first, as a real pointer travels (`HT-F`
/// item 4): the window's fallback `onInput` sees the `.mouseMoved`, after hover
/// recomputed from it, and before the click. A second click at the same point
/// sends no move. Mutation: omit the leading `.mouseMoved`.
@Test @MainActor func aClickMovesThePointerFirstSoHoverSeesIt() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent)
            .onHover { log.add("hover \($0)") }
            .onClick { log.add("click") }
    }
    window.window.onInput = { event in
        if case .mouseMoved = event { log.add("moved") }
        return false
    }
    window.click(at: pt(200, 150))
    #expect(log.entries == ["hover true", "moved", "click"])
    window.click(at: pt(200, 150))
    #expect(log.entries == ["hover true", "moved", "click", "click"], "no move when already there")
}

/// 1.6 — a double click delivers click count 2 on its second press, so a
/// `TapGesture(count: 2)` fires once. Mutation: the second click's
/// `clickCount` is 1.
@Test @MainActor func aDoubleClickDeliversClickCountTwo() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent)
            .onTapGesture(count: 2) { log.add("double") }
    }
    window.doubleClick(at: pt(200, 150))
    #expect(log.entries == ["double"])
}

/// 1.7 — a right click never runs `onClick` (`MN-B`, divergence 110); a left
/// click on the same box does (the control). Mutation: `rightClick` sends
/// `.mouseDown`/`.mouseUp`.
@Test @MainActor func aRightClickNeverRunsOnClick() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent).onClick { log.add("click") }
    }
    window.rightClick(at: pt(200, 150))
    #expect(log.entries.isEmpty, "a secondary press never presses")
    window.click(at: pt(200, 150))
    #expect(log.entries == ["click"])
}

/// A text field's value, written by its binding.
@MainActor private final class HarnessText {
    var text = ""
}

/// An action for a plain-letter keymap binding.
private struct HarnessKAction: Action {}

/// 1.8 — a click focuses a `TextField` (a field does focus on click) and
/// `typeText` edits its binding while it has the caret. Mutation: `typeText`
/// ignores the caret (always key presses) — see the record for whether a key
/// press also edits; 1.9 is the routing's separating test.
@Test @MainActor func typeTextIntoAFocusedFieldEditsItsBinding() throws {
    let model = HarnessText()
    let window = try harnessWindow {
        TextField("", text: Binding(get: { model.text }, set: { model.text = $0 }))
    }
    window.click(at: pt(200, 150))
    #expect(window.platformWindow.textInputAreas.last != nil, "the click gave the field the caret")
    window.typeText("abc")
    #expect(model.text == "abc")
}

/// 1.9 — a plain-letter keymap binding fires with nothing focused and is silent
/// while a field has the caret, the key going to the field as text (CLAUDE.md
/// "Text input"; `HT-F` item 3). Mutation: routing ignores `textInputAreas`.
@Test @MainActor func aPlainLetterKeymapBindingIsSilentWhileAFieldIsFocused() throws {
    let log = HarnessLog()
    let model = HarnessText()
    let window = try harnessWindow {
        TextField("", text: Binding(get: { model.text }, set: { model.text = $0 }))
    }
    window.window.keymap = Keymap([KeyBinding("k", HarnessKAction())])
    window.window.onAction = { _ in log.add("k"); return true }
    window.typeKey("k")
    #expect(log.entries == ["k"], "unfocused, the binding fires")
    window.click(at: pt(200, 150))
    window.typeKey("k")
    #expect(log.entries == ["k"], "focused, the binding is silent")
    #expect(model.text == "k", "and the key went to the field")
}

/// 1.10 — `typeKey` with ⌘ fires a ⌘S keyboard shortcut; plain S does not
/// (`IX-F` item 2: modifiers match exactly). Mutation: modifiers dropped.
@Test @MainActor func typeKeyWithCommandFiresAKeyboardShortcut() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        Button("Save") { log.add("save") }.keyboardShortcut("s")
    }
    window.typeKey("s")
    #expect(log.entries.isEmpty, "plain S is not ⌘S")
    window.typeKey("s", modifierFlags: .command)
    #expect(log.entries == ["save"])
}

/// 1.11 — a ⌘⇧S shortcut fires on `typeKey("s", [.command, .shift])`, and an
/// unclaimed ⇧A reaches the window's fallback `onInput` uppercased in both
/// `characters` and `charactersIgnoringModifiers`, as AppKit delivers it.
/// Mutation: Shift not applied to the characters (the shortcut matches
/// case-folded, so only the second half reddens).
@Test @MainActor func aShiftedShortcutMatchesAsAppKitDeliversIt() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        Button("Export") { log.add("export") }.keyboardShortcut("s", modifiers: [.command, .shift])
    }
    window.window.onInput = { event in
        if case .keyDown(let key) = event {
            log.add("\(key.characters)|\(key.charactersIgnoringModifiers)|\(key.modifiers == .shift)")
        }
        return false
    }
    window.typeKey("s", modifierFlags: [.command, .shift])
    #expect(log.entries == ["export"])
    window.typeKey("a", modifierFlags: .shift)
    #expect(log.entries == ["export", "A|A|true"])
}

/// 1.12 — `scroll` moves a `ScrollView`'s content by the delta: a −50 wheel
/// delta (AppKit's sign: content up) moves every row's presented rect up 50.
/// `frame(ofID:)` is the laid-out rect, before the scroll offset (`HT-S`
/// item 4), so it does not move. Mutation: the event's `location` not set to
/// its `position`.
@Test @MainActor func scrollMovesAScrollViewsContent() throws {
    let window = try harnessWindow {
        ScrollView {
            Column {
                Box().frame(width: Pixels(400), height: Pixels(50)).background(.accent).id("row0")
                Box().frame(width: Pixels(400), height: Pixels(50)).background(.surface).id("row1")
                Box().frame(width: Pixels(400), height: Pixels(50)).background(.accent).id("row2")
                Box().frame(width: Pixels(400), height: Pixels(50)).background(.surface).id("row3")
                Box().frame(width: Pixels(400), height: Pixels(50)).background(.accent).id("row4")
                Box().frame(width: Pixels(400), height: Pixels(50)).background(.surface).id("row5")
                Box().frame(width: Pixels(400), height: Pixels(50)).background(.accent).id("row6")
                Box().frame(width: Pixels(400), height: Pixels(50)).background(.surface).id("row7")
            }
        }
    }
    func rowTops() -> [Float] { rects(window, height: 50).map { $0.bounds.origin.y } }
    #expect(rowTops() == [0, 50, 100, 150, 200, 250, 300, 350])
    #expect(try window.frame(ofID: "row3").origin.y == Pixels(150))
    window.scroll(at: pt(200, 150), byDeltaX: 0, deltaY: -50)
    #expect(rowTops() == [-50, 0, 50, 100, 150, 200, 250, 300], "the content moved up 50")
    #expect(try window.frame(ofID: "row3").origin.y == Pixels(150), "the laid-out rect did not")
}

/// What a drag gesture reported.
@MainActor private final class HarnessDragLog {
    var changes = 0
    var ended: Size<Pixels>?
    var held = false
}

/// 1.13 — `drag` delivers `steps` dragged events, each with a frame: a
/// `DragGesture` (minimum distance 10; each step moves 10√2) hears `steps`
/// changes and ends at end − start, and the drag draws `steps` + 1 frames.
/// Mutation: the steps collapsed to 1.
@Test @MainActor func aDragDeliversStepsDraggedEventsEachWithAFrame() throws {
    let drag = HarnessDragLog()
    let window = try harnessWindow {
        Box().frame(width: Pixels(200), height: Pixels(200)).background(.accent)
            .gesture(DragGesture()
                .onChanged { _ in drag.changes += 1 }
                .onEnded { drag.ended = $0.translation })
    }
    let drawn = window.framesDrawn
    window.drag(from: pt(150, 100), to: pt(230, 180), steps: 8)
    #expect(drag.changes == 8)
    #expect(drag.ended == sz(80, 80))
    #expect(window.framesDrawn == drawn + 9)
}

/// 1.15 — `click(at:forDuration:thenDragTo:)` holds before it drags: a long
/// press beside a drag matures during the hold, and the drag still ends at
/// end − start. (Spec §4.1 named `sequenced(before:)`, which MetalUI does not
/// offer — `HT-S` item 2.) Mutation: no hold before the drags.
@Test @MainActor func clickForDurationThenDragToHoldsThenDrags() throws {
    let drag = HarnessDragLog()
    let window = try harnessWindow {
        Box().frame(width: Pixels(200), height: Pixels(200)).background(.accent)
            .gesture(DragGesture(minimumDistance: Pixels(0)).onEnded { drag.ended = $0.translation })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in drag.held = true })
    }
    window.click(at: pt(150, 100), forDuration: 0.6, thenDragTo: pt(230, 180))
    #expect(drag.held, "the press was held past the long press's duration")
    #expect(drag.ended == sz(80, 80))
}

/// What the pinch gestures reported.
@MainActor private final class HarnessPinchLog {
    var magnification: Double?
    var degrees: Double?
}

/// 1.16 — `magnify` and `rotate` reach their gestures: 1.5 and 30°.
/// Mutation: `.ended` only.
@Test @MainActor func magnifyAndRotateReachTheirGestures() throws {
    let pinch = HarnessPinchLog()
    let window = try harnessWindow {
        HStack(spacing: 0) {
            Box().frame(width: Pixels(100), height: Pixels(100)).background(.accent)
                .gesture(MagnifyGesture().onEnded { pinch.magnification = $0.magnification })
            Box().frame(width: Pixels(100), height: Pixels(100)).background(.accent)
                .gesture(RotateGesture().onEnded { pinch.degrees = $0.rotation.degrees })
        }
    }
    // The HStack is 200 × 100 centred: (100, 100)–(300, 200).
    window.magnify(at: pt(150, 150), by: 1.5)
    window.rotate(at: pt(250, 150), byDegrees: 30)
    #expect(pinch.magnification == 1.5)
    let degrees = try #require(pinch.degrees)
    #expect(abs(degrees - 30) < 1e-9, "30° (summed through radians)")
}
