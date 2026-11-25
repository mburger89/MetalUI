import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// `KF-AH`: `KeyEquivalent.f1`...`.f20`, AppKit's `NSF1FunctionKey`...`NSF20FunctionKey`.

private let all: [KeyEquivalent] = [
    .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20
]

private func event(_ key: String, _ modifiers: Modifiers = [], base: String = "") -> KeyEvent {
    var event = KeyEvent(charactersIgnoringModifiers: key, characters: key, modifiers: modifiers, timestamp: 0)
    event.unshiftedKey = base
    return event
}

/// Each constant is AppKit's code, `U+F704 + n - 1`. Mutation: `f13` spelled `U+F711` (an off-by-one in
/// the table) — reddens.
@Test func eachFunctionKeyIsAppKitsCodePoint() {
    #expect(all.count == 20)
    for (index, key) in all.enumerated() {
        #expect(key.character.unicodeScalars.map(\.value) == [0xF704 + UInt32(index)], "F\(index + 1)")
    }
}

/// `.f12` + Shift fires on an SDL-shaped event (the keycode's own character, Shift held, base key the
/// same) and an AppKit-shaped one (no base key), not on a plain F12. Mutation: `f12` as `U+F70E` — reddens.
@Test @MainActor func aShiftedF12ShortcutMatchesSDLAndAppKitEvents() {
    let shortcut = KeyboardShortcut(.f12, modifiers: .shift)
    #expect(shortcut.matches(event("\u{f70f}", .shift, base: "\u{f70f}")), "SDL-shaped")
    #expect(shortcut.matches(event("\u{f70f}", .shift)), "AppKit-shaped")
    #expect(!shortcut.matches(event("\u{f70f}", [])))
    #expect(!shortcut.matches(event("\u{f70e}", .shift)), "F11 is another key")
    #expect(KeyboardShortcut(.f20, modifiers: []).matches(event("\u{f717}")))
}

/// The keymap spells F13...F20. Mutation: drop `f20` from `namedKeys` — reddens.
@Test func theKeymapSpellsF13ToF20() throws {
    for n in 13...20 {
        let stroke = try #require(Keystroke("f\(n)"), "f\(n)")
        #expect(stroke.key == all[n - 1].character.description)
    }
    let shifted = try #require(Keystroke("ctrl-shift-F20"))
    #expect(shifted.key == "\u{f717}" && shifted.modifiers == [.control, .shift])
    #expect(Keystroke("f21") == nil)
}

/// The shared formatter names every constant `F<n>` on each platform. Mutation: the F-key range ends
/// at `U+F70F` — reddens at F13.
@Test func everyFunctionKeyDrawsAsItsName() {
    for platform in KeyboardShortcut.Platform.allCases {
        for (index, key) in all.enumerated() {
            #expect(KeyboardShortcut(key, modifiers: []).displayText(for: platform) == "F\(index + 1)",
                    "\(platform) F\(index + 1)")
        }
    }
    #expect(KeyboardShortcut(.f12, modifiers: .shift).displayText(for: .macOS) == "⇧F12")
    #expect(KeyboardShortcut(.f12, modifiers: .shift).displayText(for: .linux) == "Shift+F12")
    #expect(KeyboardShortcut(.f12, modifiers: .shift).displayText(for: .windows) == "Shift+F12")
}

@MainActor private final class Log { var entries: [String] = [] }

/// A `CommandMenu` item with `.keyboardShortcut(.f2)` runs on F2 and not on F3 or ⇧F2. Mutation: bind
/// `.f3` — reddens.
@MainActor
@Test func aCommandMenuItemBoundToF2FiresOnF2() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = FakePlatform(device: device)
    platform.windowSize = 400
    let app = App(platform: platform)
    let log = Log()
    app.commands { CommandMenu("Tools") { Button("Rename") { log.entries.append("rename") }.keyboardShortcut(.f2, modifiers: []) } }
    let window = try app.openWindow(title: "F", size: Size(width: Pixels(400), height: Pixels(400)),
                                    startsDisplayLink: false) { Text("Body") }
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let fake = try #require(platform.openedWindows.last)
    #expect(!fake.simulateInput(.keyDown(event("\u{f706}"))), "F3 is not bound")
    #expect(!fake.simulateInput(.keyDown(event("\u{f705}", .shift))), "⇧F2 is not bound")
    #expect(log.entries.isEmpty)
    #expect(fake.simulateInput(.keyDown(event("\u{f705}"))))
    #expect(log.entries == ["rename"])
}
