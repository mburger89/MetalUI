import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: px(x), y: px(y))
}

private func keyDown(_ characters: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: characters,
                      characters: characters,
                      modifiers: modifiers,
                      timestamp: 0))
}

private func keyUp(_ characters: String) -> InputEvent {
    .keyUp(KeyEvent(charactersIgnoringModifiers: characters, characters: characters,
                    timestamp: 0))
}

/// What the handlers wrote down, in the order they ran.
///
/// A **reference** type for `InputDispatchTests.ClickLog`'s reason: the content
/// closure runs fresh every frame and builds a fresh element value, so a counter
/// stored on the element itself would be discarded with the element.
private final class KeyLog {
    var names: [String] = []
    var count: Int { names.count }
}

/// The root element's id, as `Frame.render` builds it.
private func rootID(_ name: String) -> GlobalElementID {
    GlobalElementID.child(of: nil, at: 0, name: ElementID(name))
}

// MARK: - The five the brief names

/// A key event reaches the focused element's own handler.
///
/// **The `== ["focused"]` is not decoration.** A dispatcher that ran every
/// registered key handler rather than walking from the focused id passes a bare
/// "did it run" and fails this, because the fixture's second box also has one
/// and is never focused.
@Test @MainActor func aKeyEventDispatchesToTheFocusedElement() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = KeyLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Row {
            Box().width(px(40)).height(px(40)).id("a")
                .focusable().onKey { _ in log.names.append("focused"); return true }
            Box().width(px(40)).height(px(40)).id("b")
                .focusable().onKey { _ in log.names.append("other"); return true }
        }
    }
    window.drawFrameIfNeeded()

    // The `Row` is the unnamed root; the two boxes are its named children.
    let a = GlobalElementID.child(of: rootID2(), at: 0, name: ElementID("a"))
    window.focus(a)
    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["focused"],
            "the focused element's handler ran, and the unfocused sibling's did not")
}

/// An unhandled key event bubbles to its ancestors **innermost first**.
///
/// This is the ordering test the brief's mutation targets: bubbling
/// outermost-first reverses the array below. Each handler returns `false`, so
/// every level sees the event and the walk runs to the root — which is also
/// what pins that a `false` return continues rather than stopping.
@Test @MainActor func anUnhandledKeyEventBubblesToItsAncestorsInnermostFirst() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = KeyLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box {
            Box {
                Box().width(px(20)).height(px(20)).id("leaf")
                    .focusable().onKey { _ in log.names.append("leaf"); return false }
            }
            .id("mid").onKey { _ in log.names.append("mid"); return false }
        }
        .id("root").onKey { _ in log.names.append("root"); return false }
    }
    window.drawFrameIfNeeded()

    let root = rootID("root")
    let mid = GlobalElementID.child(of: root, at: 0, name: ElementID("mid"))
    let leaf = GlobalElementID.child(of: mid, at: 0, name: ElementID("leaf"))
    window.focus(leaf)

    var raw: [String] = []
    window.onInput = { event in
        if case .keyDown = event { raw.append("window") }
        return false
    }

    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["leaf", "mid", "root"],
            "innermost first: the focused element, then each ancestor outward")
    #expect(raw == ["window"],
            "nothing claimed it, so the event still reached the window's fallback")
}

/// The first handler that returns `true` stops the walk — the ancestor above it
/// never sees the event, and neither does the window.
///
/// The differential for the test above: without it, "returns `false` continues"
/// could not be told from "the return value is ignored entirely".
@Test @MainActor func aHandlerThatClaimsTheEventStopsTheWalk() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = KeyLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box {
            Box {
                Box().width(px(20)).height(px(20)).id("leaf")
                    .focusable().onKey { _ in log.names.append("leaf"); return false }
            }
            .id("mid").onKey { _ in log.names.append("mid"); return true }
        }
        .id("root").onKey { _ in log.names.append("root"); return false }
    }
    window.drawFrameIfNeeded()

    let root = rootID("root")
    let mid = GlobalElementID.child(of: root, at: 0, name: ElementID("mid"))
    window.focus(GlobalElementID.child(of: mid, at: 0, name: ElementID("leaf")))

    var raw: [String] = []
    window.onInput = { event in
        if case .keyDown = event { raw.append("window") }
        return false
    }

    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["leaf", "mid"], "`mid` claimed it, so `root` never saw it")
    #expect(raw.isEmpty, "a claimed event does not also reach the window's fallback")
}

/// With nothing focused, a key event reaches the window's own handler — and no
/// element's key handler runs on the way.
///
/// This is what lets a keymap binding work with no focused element at all
/// (design spec §4.2), and it is the case the counter demo relies on.
@Test @MainActor func aKeyEventWithNothingFocusedReachesTheWindow() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = KeyLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).id("a")
            .focusable().onKey { _ in log.names.append("element"); return true }
    }
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == nil, "nothing is focused until something focuses it")

    var raw: [String] = []
    window.onInput = { event in
        if case .keyDown = event { raw.append("window") }
        return true
    }

    platformWindow.simulateInput(keyDown("x"))
    #expect(log.count == 0, "no focused element, so no element handler ran")
    #expect(raw == ["window"], "the event reached the window instead")

    // The positive control: the same fixture does dispatch once focused, so the
    // two lines above are about focus rather than about a dead handler.
    window.focus(rootID("a"))
    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["element"], "the same handler fires once it holds focus")
}

/// Focus survives a frame in which the focused element is rebuilt.
///
/// The tree is rebuilt from scratch every frame, so "survives" is the whole
/// property: the id is stable and the window's focus is keyed on it. The second
/// frame's handler is a *different closure*, and the key event runs that one —
/// which is what tells "focus survived" from "the window cached frame 1's
/// handler".
@Test @MainActor func focusSurvivesAFrameInWhichTheFocusedElementIsRebuilt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = KeyLog()
    let label = Label()
    label.name = "v1"
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).id("a")
            .focusable().onKey { _ in log.names.append(label.name); return true }
    }
    window.drawFrameIfNeeded()
    window.focus(rootID("a"))
    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["v1"])

    label.name = "v2"
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == rootID("a"), "the rebuild did not move focus")
    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["v1", "v2"], "frame 2's handler is the one that runs")
}

/// A mutable name the content closure reads fresh every frame — `LabelBox`'s
/// twin in `InputDispatchTests`, and a class for the same reason.
private final class Label {
    var name = ""
}

/// Focus on an element that stops being produced is **retained**, not
/// cleared outright — as long as the id is still retained by the state
/// table, live or tombstoned (design spec §5, closing CLAUDE.md's
/// divergence 17).
///
/// **Formerly `focusOnAnElementThatStopsBeingProducedIsCleared`, and it
/// asserted the OPPOSITE** — `window.focusedElement == nil` the very next
/// frame the element was missing, with the comment above (now corrected)
/// claiming "there are no tombstones ... a focused id whose element was
/// not produced has nothing behind it". That was true before this task and
/// is not any more: `Frame.resolveFocus()` now falls back to the same
/// tombstone mechanism `@State` rides (divergence 12's remedy) instead of
/// clearing on the spot, per design §5's "one notion of 'still exists', not
/// two" — a focus-specific grace period was explicitly rejected in favour
/// of this. Inverted here, with this history kept, rather than deleted —
/// this repo's rule for a reddened test that pins a decision rather than a
/// regression.
///
/// **A frame must actually confirm the focus while the element is present,
/// or there is nothing to retain — see
/// `focusSetWithNoConfirmingFrameHasNothingToRetain` below for that as its
/// own pinned case.** `Frame.registerHandlers` only creates the state
/// table's `$focus` retention slot for `focusedElement` the first time it
/// sees that id actually produced; `window.focus(a)` alone does not render
/// a frame, so this version inserts one extra `drawFrameIfNeeded()` between
/// focusing and toggling the element away that the original did not need.
@Test @MainActor func focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = KeyLog()
    let toggle = Toggle()
    toggle.isOn = true
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box {
            if toggle.isOn {
                Box().width(px(20)).height(px(20)).id("a")
                    .focusable().onKey { _ in log.names.append("element"); return true }
            }
        }
        .id("root")
    }
    window.drawFrameIfNeeded()
    let a = GlobalElementID.child(of: rootID("root"), at: 0, name: ElementID("a"))
    window.focus(a)
    // The frame that CONFIRMS the focus — "a" is both produced and
    // `window.focusedElement` this frame — is what creates the retention
    // slot. Skip this and there is nothing for the table to retain; see
    // `focusSetWithNoConfirmingFrameHasNothingToRetain`.
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == a, "focus takes on the frame that confirms it")
    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["element"], "the fixture's element does hold focus while it exists")

    toggle.isOn = false
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == a, """
            the focused element was not produced this frame, but its \
            retention slot is still within staleAfterGenerations — divergence \
            17 closed
            """)

    var raw: [String] = []
    window.onInput = { event in
        if case .keyDown = event { raw.append("window") }
        return true
    }
    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["element"],
            "the vanished element has nothing left to run its own handler, retained or not")
    #expect(raw == ["window"],
            "with no handler along the retained-but-vanished focus chain, the event still reaches the window")
}

/// **The half `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`
/// does NOT exercise**: `window.focus(_:)` alone renders no frame, so if the
/// focused element vanishes before any frame ever confirms it was produced,
/// `Frame.registerHandlers` never created a `$focus` retention slot for it —
/// there is nothing in the state table to retain, and this is the one shape
/// where the new contract and the old one agree: focus clears on the very
/// next frame, exactly as the pre-task-4 code did unconditionally.
///
/// **Not a gap in divergence 17's closure — a different case with a
/// different reason.** The retention window bounds an excursion for
/// something that WAS established; it was never meant to conjure retention
/// for a focus call nothing ever rendered.
@Test @MainActor func focusSetWithNoConfirmingFrameHasNothingToRetain() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let toggle = Toggle()
    toggle.isOn = true
    let (window, _) = try makeFakeWindow(device: device, size: 100) {
        Box {
            if toggle.isOn {
                Box().width(px(20)).height(px(20)).id("a").focusable()
            }
        }
        .id("root")
    }
    window.drawFrameIfNeeded()
    let a = GlobalElementID.child(of: rootID("root"), at: 0, name: ElementID("a"))
    window.focus(a)
    // No frame renders here — `a` is never confirmed as both produced and
    // focused before it vanishes on the very next `drawFrameIfNeeded()`.

    toggle.isOn = false
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == nil,
            "no frame ever confirmed the focus, so the state table has no retention slot to fall back on")
}

/// A mutable flag the content closure reads fresh every frame.
private final class Toggle {
    var isOn = false
}

/// An element that is still produced but is no longer **focusable** loses focus
/// too.
///
/// The rule is "present in this frame's focus registry", not "somewhere in the
/// tree" — the frame has no way to ask the second question, since an element
/// that registers nothing contributes nothing to any registry. Written down
/// because it is the sharper half of the clearing rule and nothing else here
/// reaches it.
@Test @MainActor func anElementThatStopsBeingFocusableLosesFocus() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let toggle = Toggle()
    toggle.isOn = true
    let (window, _) = try makeFakeWindow(device: device, size: 100) {
        toggle.isOn
            ? Box().width(px(20)).height(px(20)).id("a").focusable()
            : Box().width(px(20)).height(px(20)).id("a")
    }
    window.drawFrameIfNeeded()
    window.focus(rootID("a"))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == rootID("a"),
            "still focusable, so a second frame keeps focus")

    toggle.isOn = false
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == nil, "no longer focusable, so focus is cleared")
}

// MARK: - Focusability and key handling are separable

/// An ancestor handles keys without being focusable, and a focusable element
/// needs no key handler of its own.
///
/// **This is the shape decision `Handlers` makes, asserted rather than
/// asserted-in-prose.** The fixture's leaf is focusable and binds nothing; its
/// container binds a key and is not focusable. Under a single combined field
/// neither is expressible: the leaf would be unable to hold focus, or the
/// container would become a focus target.
@Test @MainActor func aFocusableElementNeedsNoHandlerAndAHandlerNeedsNoFocusability() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = KeyLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box {
            Box().width(px(20)).height(px(20)).id("leaf").focusable()
        }
        .id("root").onKey { _ in log.names.append("root"); return true }
    }
    window.drawFrameIfNeeded()

    let leaf = GlobalElementID.child(of: rootID("root"), at: 0, name: ElementID("leaf"))
    window.focus(leaf)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == leaf,
            "a focusable element with no key handler still holds focus")

    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["root"],
            "and the event bubbles to an ancestor that handles keys without being focusable")
}

/// Neither `focusable()` nor `onKey(_:)` makes an element a **pointer** hit
/// target.
///
/// **The gate that must not move.** `Frame.registerHandlers` registers an
/// *opaque* hitbox, and an opaque hitbox swallows the wheel of any `ScrollView`
/// it sits inside — that is the measured cost `onClick` pays and
/// `aClickTargetInsideAScrollViewSwallowsTheWheel` pins. A keyboard-only
/// element must not pay it: folding focus into the same `isEmpty` gate would
/// make every focusable row in a list block that list's own scrolling.
@Test @MainActor func focusabilityAndKeyHandlingRegisterNoPointerHitbox() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (keyboardOnly, _) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).focusable().onKey { _ in true }
    }
    keyboardOnly.drawFrameIfNeeded()
    #expect(keyboardOnly.lastHitboxes.isEmpty,
            "a focusable key handler is not a hit target, so it swallows no wheel")
    #expect(keyboardOnly.lastFocusRegistry.isFocusable(rootID2()),
            "it did register for focus, so the line above is not a dead fixture")

    // The differential: the same box with `onClick` does register one.
    let (clickable, _) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).focusable().onClick {}
    }
    clickable.drawFrameIfNeeded()
    #expect(clickable.lastHitboxes.count == 1, "`onClick` is what makes a hit target")
}

private func rootID2() -> GlobalElementID {
    GlobalElementID.child(of: nil, at: 0, name: nil)
}

// MARK: - Focus is visible, so moving it redraws

/// Moving focus marks the window dirty, and a key event a handler claimed does
/// too.
///
/// **Found by mutation, and it is the kind of miss nothing else here can
/// see.** Every other test in this file calls `setNeedsRedraw()` explicitly
/// before its second frame, so deleting the `setNeedsRedraw()` inside
/// `focus(_:)` left the whole suite green — and a window whose display link has
/// idled would then move focus with nothing on screen changing until the next
/// unrelated event. §4.4's rule is that anything that changes what is drawn
/// marks the frame dirty; focus is drawn (`PaintPass.isFocused`), so it does.
///
/// The `framesDrawn` half is what makes this about a redraw rather than about a
/// flag: `needsRedraw` alone would pass against a window that raised it and
/// then never used it.
@Test @MainActor func movingFocusAndClaimingAKeyBothRedrawTheWindow() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).id("a")
            .focusable().onKey { _ in true }
    }
    window.drawFrameIfNeeded()
    let drawnAfterFirst = window.framesDrawn
    #expect(!window.needsRedraw, "the window went clean after its first frame")

    window.focus(rootID("a"))
    #expect(window.needsRedraw, "moving focus changes what is drawn")
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == drawnAfterFirst + 1, "and a frame actually followed")
    #expect(!window.needsRedraw, "clean again")

    platformWindow.simulateInput(keyDown("x"))
    #expect(window.needsRedraw,
            "a claimed keystroke may have changed state the window cannot inspect")
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == drawnAfterFirst + 2)

    // The no-op differential: focusing what is already focused changes nothing,
    // so it must not wake the display link.
    window.focus(rootID("a"))
    #expect(!window.needsRedraw, "re-focusing the focused element is not a change")
}

// MARK: - The compositions the two-gate design rests on

/// **A focusable, key-handling row inside a `ScrollView` does NOT swallow that
/// scroller's wheel** — and the key still reaches it.
///
/// **The property, not the proxy.** `focusabilityAndKeyHandlingRegisterNoPointerHitbox`
/// above asserts `lastHitboxes.isEmpty`, which is the *mechanism*; this asserts
/// the thing that mechanism exists for, through a real `ScrollView` and a real
/// wheel event. `Handlers`' type doc, `focusable()`'s doc and the two-gate split
/// itself all rest on this composition, and the failure it guards against is
/// silent — a list that quietly stops scrolling the day its rows become
/// focusable, with every other test in the suite still green.
///
/// **The differential is the neighbouring file's test.** Swap `focusable()` and
/// `onKey` for `onClick` and this fixture becomes
/// `aClickTargetInsideAScrollViewSwallowsTheWheel` in `InputDispatchTests`,
/// which asserts the opposite outcome (offset 0) — deliberately, because an
/// `onClick` registers an opaque hitbox and this does not. Two fixtures one
/// modifier apart, disagreeing, is what pins that the gate is the thing making
/// the difference.
@Test @MainActor func aFocusableRowInsideAScrollViewDoesNotSwallowTheWheel() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = KeyLog()
    var rowStyle = Style()
    rowStyle.size = Size(width: .auto, height: .length(.pixels(px(40))))
    // A `Box(style:)` column rather than the public `Column`, so the rows keep
    // the engine's `stretch` default and fill the viewport's width — the idiom
    // `ScrollRoutingTests` and `InputDispatchTests` both use.
    var column = Style()
    column.flexDirection = .column
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        ScrollView(.vertical, elementID: ElementID("list")) {
            Box(style: column) {
                Box(style: rowStyle).id("row0")
                    .focusable().onKey { _ in log.names.append("row0"); return true }
                Box(style: rowStyle); Box(style: rowStyle); Box(style: rowStyle)
            }
        }
    }
    window.drawFrameIfNeeded()
    let scroller = GlobalElementID.child(of: nil, at: 0, name: ElementID("list"))

    // Over the focusable row: the wheel reaches the scroller anyway.
    platformWindow.simulateInput(
        .scrollWheel(ScrollEvent(position: pt(20, 20),
                                 delta: Point(x: px(0), y: px(-37)))))
    var offset = 0.0
    window.stateTable.withState(scroller, initial: ScrollState()) { offset = $0.offset }
    #expect(offset == 37,
            "a focusable key handler registers no hitbox, so it swallows nothing")

    // And the row is genuinely focusable and genuinely bound — otherwise the
    // line above would pass against a fixture whose modifiers did nothing.
    let content = GlobalElementID.child(of: scroller, at: 0, name: nil)
    let row0 = GlobalElementID.child(of: content, at: 0, name: ElementID("row0"))
    window.focus(row0)
    #expect(window.lastFocusRegistry.isFocusable(row0), "the row did register for focus")
    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["row0"], "and the key reaches it")
}

/// Focus works inside a `Deferred` subtree — registration, holding focus across
/// a frame, and dispatch.
///
/// **Cheap to add and worth having because the mechanism *predicts* it works
/// and nothing checked.** `Deferred` hoists its subtree's layer and resets the
/// clip stack (ruling AP-I), and both of those act on registrations that carry
/// geometry — a hitbox is translated and clipped on the way in. Focus
/// registration reads no geometry at all, so a portal should be invisible to
/// it. That is a prediction from the design, and this is the assertion.
///
/// The `ScrollView` around it is not decoration: it is what makes the portal
/// have something to escape, so a `Deferred` that had somehow dropped its
/// subtree's focus registrations would have a reason to.
@Test @MainActor func focusSurvivesAndDispatchesInsideADeferredSubtree() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = KeyLog()
    var column = Style()
    column.flexDirection = .column
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        ScrollView(.vertical, elementID: ElementID("list")) {
            Box(style: column) {
                Deferred(elementID: ElementID("portal")) {
                    Box().width(px(20)).height(px(20)).id("leaf")
                        .focusable().onKey { _ in log.names.append("leaf"); return true }
                }
            }
        }
    }
    window.drawFrameIfNeeded()

    let scroller = GlobalElementID.child(of: nil, at: 0, name: ElementID("list"))
    let content = GlobalElementID.child(of: scroller, at: 0, name: nil)
    let portal = GlobalElementID.child(of: content, at: 0, name: ElementID("portal"))
    let leaf = GlobalElementID.child(of: portal, at: 0, name: ElementID("leaf"))

    #expect(window.lastFocusRegistry.isFocusable(leaf),
            "a portal does not swallow its subtree's focus registration")
    window.focus(leaf)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == leaf, "and the registration survives the next frame")
    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["leaf"], "and a key event reaches through the portal")
}

// MARK: - What Task 10 consumes

/// `Window.focusChain` is the focused id and every ancestor, **innermost
/// first** — the order §4.3 requires context predicates to be matched in.
///
/// Exposed rather than buried inside dispatch, because Task 10 matches
/// predicates against it and never calls a key handler at all.
@Test @MainActor func theFocusChainIsTheFocusedIdAndItsAncestorsInnermostFirst() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, _) = try makeFakeWindow(device: device, size: 100) {
        Box {
            Box { Box().width(px(20)).height(px(20)).id("leaf") }.id("mid")
        }
        .id("root")
    }
    window.drawFrameIfNeeded()
    #expect(window.focusChain.isEmpty, "nothing focused, so the chain is empty")

    let root = rootID("root")
    let mid = GlobalElementID.child(of: root, at: 0, name: ElementID("mid"))
    let leaf = GlobalElementID.child(of: mid, at: 0, name: ElementID("leaf"))
    window.focus(leaf)
    #expect(window.focusChain == [leaf, mid, root],
            "innermost first, all the way to the root")
}

// MARK: - Scope: key DOWN only

/// A `keyUp` is not dispatched to the focus chain; it falls through to the
/// window.
///
/// **A stated scope limit rather than an oversight.** `KeyEvent` carries no
/// down/up discriminator, so a handler receiving both could not tell them apart
/// and would fire twice per keystroke with no way to opt out. Widening this
/// means giving the handler the phase, which is a change to `KeyEvent`'s
/// surface and belongs with whoever needs it.
@Test @MainActor func aKeyUpIsNotDispatchedToTheFocusChain() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = KeyLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).id("a")
            .focusable().onKey { _ in log.names.append("element"); return true }
    }
    window.drawFrameIfNeeded()
    window.focus(rootID("a"))

    var raw: [String] = []
    window.onInput = { event in
        if case .keyUp = event { raw.append("up") }
        return false
    }
    platformWindow.simulateInput(keyUp("x"))
    #expect(log.count == 0, "keyUp is not dispatched")
    #expect(raw == ["up"], "it falls through to the window unchanged")

    // The positive control: the same fixture does dispatch a keyDown.
    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["element"])
}

/// The event a handler receives is the one that arrived.
///
/// Without this, a dispatcher that fabricated its own `KeyEvent` — or handed
/// the handler an empty one — would pass every other test in this file.
@Test @MainActor func theHandlerReceivesTheEventThatArrived() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var seen: [String] = []
    var seenModifiers: [Modifiers] = []
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).id("a")
            .focusable().onKey { key in
                seen.append(key.charactersIgnoringModifiers)
                seenModifiers.append(key.modifiers)
                return true
            }
    }
    window.drawFrameIfNeeded()
    window.focus(rootID("a"))

    platformWindow.simulateInput(keyDown("s", .command))
    platformWindow.simulateInput(keyDown("z"))
    #expect(seen == ["s", "z"])
    #expect(seenModifiers == [.command, []])
}

// MARK: - `onKey` is live on every conformer that can register one

/// `onKey` and `focusable()` reach every `StyledElement` conformer, and each of
/// them actually registers.
///
/// `onClickIsLiveOnEveryConformerThatCanRegisterOne`'s twin, and for its
/// reason: `handlers` is a protocol requirement, so both modifiers compile on
/// every conformer the day they land — a conformer whose `prepaint` forgets to
/// register is then an API that exists, compiles and does nothing.
@Test @MainActor func onKeyIsLiveOnEveryConformerThatCanRegisterOne() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = KeyLog()

    func fires(_ name: String, _ content: @escaping @MainActor () -> some Element) throws {
        let (window, platformWindow) = try makeFakeWindow(device: device, size: 100,
                                                          content: content)
        window.drawFrameIfNeeded()
        window.focus(rootID(name))
        platformWindow.simulateInput(keyDown("x"))
        #expect(log.names == [name], "\(name): onKey compiled but registered nothing")
        log.names.removeAll()
    }

    try fires("box") {
        Box().width(px(40)).height(px(40)).id("box")
            .focusable().onKey { _ in log.names.append("box"); return true }
    }
    try fires("column") {
        Column { Box().width(px(40)).height(px(40)) }.id("column")
            .focusable().onKey { _ in log.names.append("column"); return true }
    }
    try fires("row") {
        Row { Box().width(px(40)).height(px(40)) }.id("row")
            .focusable().onKey { _ in log.names.append("row"); return true }
    }
    try fires("stack") {
        Stack { Box().width(px(40)).height(px(40)) }.id("stack")
            .focusable().onKey { _ in log.names.append("stack"); return true }
    }
    try fires("text") {
        Text("Hi").width(px(40)).height(px(40)).id("text")
            .focusable().onKey { _ in log.names.append("text"); return true }
    }
    try fires("list") {
        List([Datum(id: 0)], rowHeight: px(40)) { _ in Box() }
            .width(px(40)).height(px(40)).id("list")
            .focusable().onKey { _ in log.names.append("list"); return true }
    }
}

private struct Datum: Identifiable { let id: Int }

// MARK: - `isFocused` during paint

/// `PaintPass.isFocused(_:)` reports the window's focus, and reports it as
/// **cleared** on the frame that drops it.
///
/// The second half is what makes clearing happen at the prepaint/paint boundary
/// rather than after the frame: a focus ring drawn from a stale `true` would be
/// painted for an element the frame has already decided is not focused.
@Test @MainActor func isFocusedDuringPaintTracksTheWindowsFocus() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let probe = FocusProbe()
    let (window, _) = try makeFakeWindow(device: device, size: 100) {
        Box { FocusReader(probe: probe) }.id("root")
    }
    window.drawFrameIfNeeded()
    #expect(probe.answers == [false], "nothing focused yet")

    let reader = GlobalElementID.child(of: rootID("root"), at: 0, name: ElementID("reader"))
    window.focus(reader)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(probe.answers == [false, true], "paint sees the window's focus")

    // And the frame that DROPS focus reports `false` in the same frame, not the
    // next one: clearing runs at the prepaint/paint boundary. `unfocusable`
    // stops registering, so this frame's registry no longer holds the id.
    probe.unfocusable = true
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(probe.answers == [false, true, false],
            "the frame that clears focus paints it as cleared")
    #expect(window.focusedElement == nil)
}

private final class FocusProbe {
    var answers: [Bool] = []
    /// Set between frames to make the reader stop registering as focusable.
    var unfocusable = false
}

/// An element that reads `isFocused` about itself during `paint`.
///
/// Hand-written rather than a `Box`, because a `Box` has nowhere to record what
/// it saw — the answer has to leave the frame, and only a bespoke element can
/// carry a reference out.
private struct FocusReader: Element {
    let probe: FocusProbe
    var elementID: ElementID? { ElementID("reader") }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        var style = Style()
        style.size = Size(width: .length(.pixels(Pixels(20))),
                          height: .length(.pixels(Pixels(20))))
        return (pass.requestNode(style: style, children: []), ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Void, pass: inout PrepaintPass) {
        var handlers = Handlers()
        handlers.isFocusable = !probe.unfocusable
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        probe.answers.append(pass.isFocused(id))
    }
}

// MARK: - Focus moved from INSIDE the frame that is rendering

/// `window.focus(_:)` called **during** a frame's own render survives that
/// frame — the read-back applies the frame's *decision*, not its stale value.
///
/// **Every other `window.focus(…)` in this file follows a
/// `drawFrameIfNeeded()`** — check with `grep -n "window.focus"
/// Tests/MetalUITests/FocusTests.swift` and read the line above each hit — so
/// this is the only test that reaches the composition where the hand-in and the
/// read-back straddle a concurrent write. `Window` hands `focusedElement` into
/// `Frame` before `renderRoot` and assigns it back afterwards; a read-back that
/// copied `frame.focusedElement` unconditionally would overwrite the id this
/// element just asked for with the `nil` the frame was handed, on this and
/// every subsequent frame, so an in-frame `focus()` could never stick. The
/// demo's `CounterPanel` is exactly this shape, which is what makes the
/// mechanism rather than the composition the thing under test.
///
/// **The element focuses itself unconditionally rather than behind a
/// once-flag**, because "set during render, clobbered at the end" alternates
/// forever: a once-flag would leave a reader unsure whether frame 2 recovered
/// what frame 1 lost. Frames 2 and 3 are asserted for the other half — that
/// `resolveFocus()` finds the id in the registry the element registered itself
/// into and does *not* clear it.
@Test @MainActor func focusingFromInsideAFrameSurvivesThatFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let probe = SelfFocusProbe()
    let (window, _) = try makeFakeWindow(device: device, size: 100) {
        Box { SelfFocuser(probe: probe) }.id("root")
    }
    probe.window = window

    let focuser = GlobalElementID.child(of: rootID("root"), at: 0,
                                        name: ElementID("focuser"))
    window.drawFrameIfNeeded()
    #expect(probe.focusCalls == 1, "the element ran its own `requestLayout` once")
    #expect(window.focusedElement == focuser,
            "focus asked for during the render survives the end of that frame")

    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == focuser,
            "and the next frame, which validates it against its own registry, keeps it")

    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == focuser, "and stays put")
    #expect(probe.paintedFocused == [false, true, true],
            """
            the frame that set it paints unfocused, `resolveFocus()` having \
            early-returned on the `nil` it was handed; every frame after it \
            paints focused
            """)
}

/// A frame that focuses an element which does **not** register as focusable
/// still loses it on the next frame.
///
/// The differential for the test above, and the reason the read-back applies a
/// decision rather than simply never clearing: `Window.focus(_:)`'s contract is
/// that a bogus id is not an error because the *next* frame drops it. An
/// in-frame call must be no more privileged than a between-frames one.
@Test @MainActor func focusingFromInsideAFrameIsStillValidatedByTheNextFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let probe = SelfFocusProbe()
    probe.registersFocusable = false
    let (window, _) = try makeFakeWindow(device: device, size: 100) {
        Box { SelfFocuser(probe: probe) }.id("root")
    }
    probe.window = window

    let focuser = GlobalElementID.child(of: rootID("root"), at: 0,
                                        name: ElementID("focuser"))
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == focuser, "the in-frame call still lands")

    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == nil,
            "and the next frame clears it, because it registered nothing focusable")
}

private final class SelfFocusProbe {
    /// Weak for `MetalUIDemo`'s `demoWindow` reason: the content closure the
    /// window retains builds an element holding this probe, so a strong window
    /// here would close the cycle.
    weak var window: Window?
    var registersFocusable = true
    var focusCalls = 0
    var paintedFocused: [Bool] = []
}

/// An element that focuses **itself** from its own `requestLayout`, the way
/// `MetalUIDemo`'s `CounterPanel` does.
///
/// Hand-written rather than a `Box` for `FocusReader`'s reason: only the
/// element knows its own `GlobalElementID`, and only a bespoke element can
/// carry a reference to the window out to the phase that has one.
private struct SelfFocuser: Element {
    let probe: SelfFocusProbe
    var elementID: ElementID? { ElementID("focuser") }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        probe.focusCalls += 1
        probe.window?.focus(id)
        var style = Style()
        style.size = Size(width: .length(.pixels(Pixels(20))),
                          height: .length(.pixels(Pixels(20))))
        return (pass.requestNode(style: style, children: []), ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Void, pass: inout PrepaintPass) {
        var handlers = Handlers()
        handlers.isFocusable = probe.registersFocusable
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        probe.paintedFocused.append(pass.isFocused(id))
    }
}

// MARK: - Divergence 17: focus rides the same table as `@State` (Task 4)

private struct FocusListItem: Identifiable { let id: String }

/// **Divergence 17, closed as BOUNDED — the focus twin of
/// `TombstoneTests.aListRowsStateSurvivesABoundedExcursionButNotALongerOne`,
/// on the identical mechanism per design §5: "one notion of 'still exists',
/// not two".** A focusable `List` row, focused, scrolled out of the window
/// and back keeps focus *within* the retention window
/// (`StateTable.staleAfterGenerations`, 2 generations) and loses it once the
/// excursion runs longer. Asserting only survival would pass a
/// `resolveFocus()` that never clears at all — see the mutation named in
/// this file's task report — so both halves are asserted, exactly as
/// divergence 12's test does.
///
/// **Drives `Frame` directly, not `Window`/`makeFakeWindow`** — the same
/// choice `TombstoneTests` makes and for the same reason: `Frame.init`
/// takes `focusedElement:` directly, so a fresh `Frame` per rendered frame
/// can be handed exactly what `Window.drawFrameIfNeeded` would have handed
/// it (the previous frame's `focusedElement`, read back afterward), with no
/// `NSWindow`/`Metal` device or real scroll-wheel simulation needed.
///
/// **Two independent runs, not one shared tree** — unlike the `@State`
/// version, which tracks two rows' *independent* table entries in a single
/// tree. Focus is single-valued (`Frame.focusedElement` is one id, not a
/// set), so a short excursion on row 4 and a long one on row 7 cannot be
/// observed in the same run; `runExcursion` below builds its own table, its
/// own padding and its own tree per call.
///
/// **The 260-id padding ballast is `TombstoneTests`' own idiom**, needed for
/// the identical reason: `sweep()` only reaps once `storage.count` exceeds
/// `StateTable.sweepThreshold` (256), and this fixture's own real entries —
/// a dozen rows' `$focus`-shaped slots plus the scroller's `ScrollState` —
/// never come close on their own, which would make the long-excursion half
/// pass vacuously (nothing ever gets reaped).
@MainActor
@Test func aFocusedListRowSurvivesABoundedExcursionButNotALongerOne() throws {
    let rowHeight = px(20)
    let data = (0..<12).map { FocusListItem(id: "row\($0)") }

    // Focuses `data[index]`'s row, windows it out for `excursionFrames`
    // consecutive frames, windows it back in, and reports whether focus
    // survived. The recovery offset — `rowHeight * index` — puts `index` at
    // `[index - 2, index + 3)` under `visibleRange`'s overscan of 2, which is
    // `TombstoneTests`' own offsets (80 recovers row 4, 140 recovers row 7)
    // generalised rather than copied.
    func runExcursion(index: Int, excursionFrames: Int) -> GlobalElementID? {
        let table = StateTable()
        let paddingIDs = (0..<260).map {
            GlobalElementID.child(of: nil, at: 10_000 + $0, name: ElementID("pad\($0)"))
        }
        for id in paddingIDs { table.write(id, 0) }

        var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
            List(data, rowHeight: rowHeight) { _ in Box().focusable() }
        }
        let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))
        let contentSize = Size<Pixels>(width: px(100), height: px(20))
        var currentFocus: GlobalElementID?

        func renderFrame(offset: Double?) {
            for id in paddingIDs { table.mark(id) }
            if let offset {
                let current = table.peek(scrollerID, as: ScrollState.self) ?? ScrollState()
                table.write(scrollerID, ScrollState(offset: offset,
                                                    lastScrollTime: current.lastScrollTime,
                                                    viewportExtent: current.viewportExtent))
            }
            let frame = Frame(contentSize: contentSize, scaleFactor: 1, stateTable: table,
                              focusedElement: currentFocus)
            frame.render(&tree)
            currentFocus = frame.focusedElement
        }

        // The row's own id, hand-computed from the exact chain `List` and
        // `ScrollView` build — `TombstoneTests.rowID`'s technique, since a
        // row painting above the viewport clips to `y == 0` and a
        // geometry-based recovery would pick the wrong one.
        let listID = GlobalElementID.child(of: scrollerID, at: 0, name: nil)
        func rowID(_ i: Int) -> GlobalElementID {
            let boxID = GlobalElementID.child(of: listID, at: 0, name: ElementID(data[i].id))
            return GlobalElementID.child(of: boxID, at: 0, name: nil)
        }

        // Frame 1: cold — no `ScrollView.prepaint` has run yet, so `List`
        // builds every row (ruling MP-I) rather than windowing.
        renderFrame(offset: nil)

        // `window.focus(_:)`'s real-world equivalent: hand the id in for the
        // NEXT frame, exactly as `Window` threads `focusedElement` forward.
        // The row is produced this frame (still the cold frame's window, or
        // close enough — frame 2 below re-confirms it either way), so this
        // is the frame that creates the `$focus` retention slot.
        currentFocus = rowID(index)
        renderFrame(offset: 100)
        #expect(currentFocus == rowID(index),
                "the target row is focusable and produced, so focus is confirmed")

        // `excursionFrames` consecutive frames windowing the row OUT —
        // offset 0 windows to [0, 3), excluding every index tried here (4, 7).
        for _ in 0..<excursionFrames {
            renderFrame(offset: 0)
        }

        // Window it back in.
        renderFrame(offset: Double(rowHeight.value) * Double(index))
        return currentFocus
    }

    // The row's own id, computed the same way `runExcursion`'s internal
    // `rowID` does, so the two halves below assert the SPECIFIC row's
    // identity survived — not merely that focus landed on *something*.
    func rowID(_ i: Int) -> GlobalElementID {
        let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))
        let listID = GlobalElementID.child(of: scrollerID, at: 0, name: nil)
        let boxID = GlobalElementID.child(of: listID, at: 0, name: ElementID(data[i].id))
        return GlobalElementID.child(of: boxID, at: 0, name: nil)
    }

    // **Confirmed once, at generation 2 — not twice, unlike `TombstoneTests`'
    // rows.** That test marks its rows at generations 1, 2 AND 3 before the
    // excursion starts (three renders at the window that includes them), so
    // their `lastSeenGeneration` is 3 when the excursion begins. Here the row
    // is confirmed focused exactly once (generation 2), so its
    // `$focus` slot's `lastSeenGeneration` is 2 — two generations LOWER — and
    // every frame count below is shifted to match, not copied from that file.
    //
    // **A second shift, unique to focus and absent from the `@State` case:
    // `resolveFocus()` reads the table BEFORE this frame's own `sweep()` runs
    // (one-frame lag, `Frame.render`'s own ordering) — so observing a reap
    // that a sweep just performed takes one MORE excluded frame than
    // performing it does.** `lastSeenGeneration == 2` makes `sweep()` itself
    // reap the entry at generation 5 (`2 + staleAfterGenerations(2) < 5`) —
    // three excluded frames (generations 3, 4, 5) — but `resolveFocus` at
    // generation 5 still reads generation 4's not-yet-reaped state, so
    // `currentFocus` does not actually go `nil` until generation 6's
    // `resolveFocus` — a FOURTH excluded frame — observes the reap `sweep()`
    // already performed one generation earlier.
    let shortIndex = 4   // recovered after 2 excluded generations — within the bound
    let longIndex = 7    // excluded for 4 generations — past the bound, AND past the lag

    let shortResult = runExcursion(index: shortIndex, excursionFrames: 2)
    #expect(shortResult == rowID(shortIndex),
            "row \(shortIndex)'s 2-generation excursion is WITHIN staleAfterGenerations: focus must survive")

    let longResult = runExcursion(index: longIndex, excursionFrames: 4)
    #expect(longResult == nil,
            "row \(longIndex)'s excursion exceeded staleAfterGenerations (reaped at generation 5, observed at 6): focus must NOT survive")
}
