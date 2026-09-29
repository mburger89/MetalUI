import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 12, part 1, lane 2 — `.keyboardShortcut` (ruling `IX-F`; spec §6,
// tests 2.4–2.9 and 2.13). Every SwiftUI answer is an arm of
// `docs/probes/swiftui-interaction.swift` (B4a–B4l, X2) or of the re-run
// `swiftui-disabled-interaction.swift` (K4) and
// `swiftui-allows-hit-testing-side-effects` (K1); the keymap's place ahead of
// the shortcut stage is MetalUI's (SwiftUI has no keymap).

private struct ShortcutProbeAction: Action {}

@MainActor
private func shortcutWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    try controlWindow(content)
}

// MARK: - 2.4 exact match, no focus

/// **2.4** (B4e: ⌘K fires a `keyboardShortcut("k")`; B4f: plain K does not;
/// B4g: a `modifiers: []` shortcut fires on plain K). Nothing is focused; the
/// modifiers match **exactly**. M2d (modifiers compared as a subset) reddens
/// the ⌘⇧K and ⌘J arms.
@Test @MainActor func aShortcutFiresItsButtonWithoutFocusOnAnExactModifierMatch() throws {
    let model = ControlModel()
    let (window, platform) = try shortcutWindow {
        controlRoot {
            Button("K") { model.keys.append("k") }.keyboardShortcut("k")
            Button("J") { model.keys.append("j") }.keyboardShortcut("j", modifiers: [])
        }
    }
    try #require(window.focusedElement == nil, "nothing is focused")
    #expect(platform.simulateInput(controlKey("k", .command)), "⌘K is claimed")
    #expect(model.keys == ["k"], "⌘K fires its button without focus (B4e)")
    platform.simulateInput(controlKey("k"))
    #expect(model.keys == ["k"], "plain K does not fire a ⌘K shortcut (B4f)")
    platform.simulateInput(controlKey("K", [.command, .shift]))
    #expect(model.keys == ["k"], "⌘⇧K does not fire a ⌘K shortcut: the modifiers match exactly")
    platform.simulateInput(controlKey("j"))
    #expect(model.keys == ["k", "j"], "a modifiers-[] shortcut fires on plain J (B4g)")
    platform.simulateInput(controlKey("j", .command))
    #expect(model.keys == ["k", "j"], "⌘J does not fire a modifiers-[] shortcut")
    #expect(window.focusedElement == nil, "a shortcut moves no focus")
}

// MARK: - 2.5 defaultAction / cancelAction

/// **2.5** (B4a: `.defaultAction` fires on Return; B4b: `.cancelAction` on
/// Escape). M2e (the two swapped) reddens it.
@Test @MainActor func defaultActionIsReturnAndCancelActionIsEscape() throws {
    #expect(KeyboardShortcut.defaultAction == KeyboardShortcut(.return, modifiers: []))
    #expect(KeyboardShortcut.cancelAction == KeyboardShortcut(.escape, modifiers: []))
    let model = ControlModel()
    let (_, platform) = try shortcutWindow {
        controlRoot {
            Button("OK") { model.keys.append("ok") }.keyboardShortcut(.defaultAction)
            Button("Cancel") { model.keys.append("cancel") }.keyboardShortcut(.cancelAction)
        }
    }
    platform.simulateInput(controlKey("\r"))
    #expect(model.keys == ["ok"], "Return runs the default action (B4a)")
    platform.simulateInput(controlKey("\u{1b}"))
    #expect(model.keys == ["ok", "cancel"], "Escape runs the cancel action (B4b)")
}

// MARK: - 2.6 tree order

/// **2.6** (B4h: two buttons with ⌘K, the first — `A` — fires). The first in
/// tree order wins, once. M2f (the last registered wins) reddens it.
@Test @MainActor func theFirstButtonInTreeOrderTakesASharedShortcut() throws {
    let model = ControlModel()
    let (_, platform) = try shortcutWindow {
        controlRoot {
            Button("A") { model.keys.append("A") }.keyboardShortcut("k")
            Button("B") { model.keys.append("B") }.keyboardShortcut("k")
        }
    }
    platform.simulateInput(controlKey("k", .command))
    #expect(model.keys == ["A"], "the first button in tree order takes a shared shortcut (B4h)")
    // A `nil` shortcut removes it: the second button then owns ⌘K alone.
    let (_, other) = try shortcutWindow {
        controlRoot {
            Button("A") { model.keys.append("A2") }.keyboardShortcut("k").keyboardShortcut(nil)
            Button("B") { model.keys.append("B2") }.keyboardShortcut("k")
        }
    }
    other.simulateInput(controlKey("k", .command))
    #expect(model.keys == ["A", "B2"], "keyboardShortcut(nil) removes the shortcut")
}

// MARK: - 2.7 order

/// **2.7** (B4i: with a focused view whose key handler takes ⌘K beside a ⌘K
/// button, the view runs and the button does not). A focused element's raw
/// `onKey` claims the key first; so does a keymap binding (`IX-F` item 4,
/// MetalUI's choice). M2g (the shortcut stage before the raw bubble) reddens
/// the view arm.
@Test @MainActor func aFocusedKeyHandlerAndAKeymapBindingClaimTheKeystrokeFirst() throws {
    let model = ControlModel()
    let (window, platform) = try shortcutWindow {
        controlRoot {
            Box().frame(width: Pixels(40), height: Pixels(40)).focusable()
                .onKey { event in
                    guard event.charactersIgnoringModifiers == "k" else { return false }
                    model.keys.append("view")
                    return true
                }
            Button("K") { model.keys.append("button") }.keyboardShortcut("k")
        }
    }
    window.focus(controlID([0, 0]))
    controlRedraw(window)
    try #require(window.focusedElement == controlID([0, 0]), "the view is focused")
    platform.simulateInput(controlKey("k", .command))
    #expect(model.keys == ["view"], "the focused view's handler claims ⌘K first (B4i)")

    window.focus(nil)
    controlRedraw(window)
    platform.simulateInput(controlKey("k", .command))
    #expect(model.keys == ["view", "button"], "unfocused, the button's shortcut fires")

    window.keymap = Keymap { KeyBinding("cmd-k", ShortcutProbeAction()) }
    window.onAction = { action in
        guard action is ShortcutProbeAction else { return false }
        model.keys.append("keymap")
        return true
    }
    platform.simulateInput(controlKey("k", .command))
    #expect(model.keys == ["view", "button", "keymap"], "a keymap binding claims ⌘K ahead of the shortcut")
}

// MARK: - 2.8 gates

/// **2.8** (B4l, re-measured K4: a disabled button's shortcut is silent;
/// `swiftui-allows-hit-testing-side-effects` K1: a hit-testing-off button's
/// still fires). The shortcut rides the focus registry behind the one
/// `isEnabled` gate, and `allowsHitTesting(false)` — pointer only — does not
/// reach it. M2h (the shortcut registered outside the `isEnabled` gate)
/// reddens the disabled arm.
@Test @MainActor func aDisabledButtonsShortcutIsSilentAndHitTestingOffIsNot() throws {
    let model = ControlModel()
    let (_, platform) = try shortcutWindow {
        controlRoot {
            Button("K") { model.keys.append("disabled") }.keyboardShortcut("k").disabled(true)
            Button("J") { model.keys.append("untestable") }.keyboardShortcut("j").allowsHitTesting(false)
            Button("R") { model.keys.append("default") }.keyboardShortcut(.defaultAction).disabled(true)
        }
    }
    platform.simulateInput(controlKey("k", .command))
    platform.simulateInput(controlKey("\r"))
    #expect(model.keys == [], "a disabled button's shortcut is silent (B4l, K4): \(model.keys)")
    platform.simulateInput(controlKey("j", .command))
    #expect(model.keys == ["untestable"], "allowsHitTesting(false) leaves the shortcut live (K1)")
}

// MARK: - 2.9 invisible

/// **2.9** (B4j: a button at opacity 0 still takes its shortcut). M2i (skip a
/// shortcut under an opacity-0 scope) reddens it.
@Test @MainActor func anInvisibleButtonsShortcutStillFires() throws {
    let model = ControlModel()
    let (_, platform) = try shortcutWindow {
        controlRoot { Button("K") { model.keys.append("k") }.keyboardShortcut("k").opacity(0) }
    }
    platform.simulateInput(controlKey("k", .command))
    #expect(model.keys == ["k"], "an opacity-0 button's shortcut fires (B4j)")
}

// MARK: - 2.13 Return in a focused field

/// **2.13** (X2: a focused `TextField` beside a `.defaultAction` button,
/// Return → the field's submit, the button silent). A focused field's editing
/// keys run before the shortcut stage (`IX-F` item 6); with the field
/// unfocused the button fires. M2m (the shortcut stage before a focused
/// field's editing keys) reddens it.
@Test @MainActor func aFocusedTextFieldClaimsReturnAheadOfTheDefaultButton() throws {
    let model = ControlModel()
    let (window, platform) = try shortcutWindow {
        controlRoot {
            TextField("Name", text: "hi", onChange: { _ in }).onSubmit { model.keys.append("submit") }
            Button("OK") { model.keys.append("ok") }.keyboardShortcut(.defaultAction)
        }
    }
    window.focus(controlID([0, 0]))
    controlRedraw(window)
    try #require(window.focusedElement == controlID([0, 0]), "the field is focused")
    platform.simulateInput(controlKey("\r"))
    #expect(model.keys == ["submit"], "a focused field takes Return ahead of the default button (X2)")
    window.focus(nil)
    controlRedraw(window)
    platform.simulateInput(controlKey("\r"))
    #expect(model.keys == ["submit", "ok"], "unfocused, Return runs the default button")
}
