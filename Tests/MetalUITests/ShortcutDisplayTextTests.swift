import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUITextSystem
import MetalUIText
@testable import MetalUI

// Ruling `KF-AG`: a shortcut's display text. One formatter serves
// `KeyboardShortcut.displayText` and the drawn menu's `MenuPanel.shortcutText`.

private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers = []) -> KeyboardShortcut {
    KeyboardShortcut(key, modifiers: modifiers)
}

/// The macOS glyph table, literals from `KF-AG` item 4. Mutation: the formatter
/// upper-cases the key (`key.uppercased()`, the old path) and a named key reads as
/// its private-use character: every named row reddens.
@Test func theMacOSNamedKeysAreGlyphs() {
    let table: [(KeyEquivalent, String)] = [
        (.return, "↩"), (.escape, "⎋"), (.tab, "⇥"), (.space, "Space"), (.delete, "⌫"),
        (.deleteForward, "⌦"), (.upArrow, "↑"), (.downArrow, "↓"), (.leftArrow, "←"),
        (.rightArrow, "→"), (.home, "↖"), (.end, "↘"), (.pageUp, "⇞"), (.pageDown, "⇟"), (.clear, "⌧"),
        ("\u{f704}", "F1"), ("\u{f70f}", "F12"), ("\u{f717}", "F20"), ("\u{f726}", "F35"),
        ("p", "P"), ("ß", "ß"), ("1", "1")
    ]
    for (key, text) in table {
        #expect(shortcut(key).displayText(for: .macOS) == text, "\(text)")
    }
    #expect(shortcut("\u{19}").displayText(for: .macOS) == "⇥", "AppKit's ⇧Tab")
}

/// The Linux and Windows name table: the same names; only the Super key differs.
@Test func theLinuxAndWindowsNamedKeysAreNames() {
    let table: [(KeyEquivalent, String)] = [
        (.return, "Enter"), (.escape, "Esc"), (.tab, "Tab"), (.space, "Space"), (.delete, "Backspace"),
        (.deleteForward, "Delete"), (.upArrow, "Up"), (.downArrow, "Down"), (.leftArrow, "Left"),
        (.rightArrow, "Right"), (.home, "Home"), (.end, "End"), (.pageUp, "Page Up"),
        (.pageDown, "Page Down"), (.clear, "Clear"),
        ("\u{f704}", "F1"), ("\u{f70f}", "F12"), ("\u{f717}", "F20"), ("\u{f726}", "F35"),
        ("p", "P"), ("ß", "ß")
    ]
    for platform in [KeyboardShortcut.Platform.linux, .windows] {
        for (key, text) in table {
            #expect(shortcut(key).displayText(for: platform) == text, "\(text) on \(platform)")
        }
    }
}

@Test func modifiersAreOrderedAndSuperIsNotWin() {
    let all: EventModifiers = [.control, .option, .shift, .command]
    #expect(shortcut("p", [.shift, .command]).displayText(for: .macOS) == "⇧⌘P")
    #expect(shortcut("k", all).displayText(for: .macOS) == "⌃⌥⇧⌘K")
    #expect(shortcut("p", [.control, .shift]).displayText(for: .linux) == "Ctrl+Shift+P")
    #expect(shortcut("k", all).displayText(for: .linux) == "Ctrl+Super+Alt+Shift+K")
    #expect(shortcut("k", all).displayText(for: .windows) == "Ctrl+Win+Alt+Shift+K")
    #expect(shortcut("k", .command).displayText(for: .linux) == "Super+K")
    #expect(shortcut("k", .command).displayText(for: .windows) == "Win+K")
    #expect(shortcut(.upArrow, [.option]).displayText(for: .macOS) == "⌥↑")
    #expect(shortcut("\u{f70f}", [.option]).displayText(for: .windows) == "Alt+F12")
}

@Test func displayTextIsTheCurrentPlatformsAndPrimaryModifiersFollowThePlatform() {
    let s = shortcut("p", [.shift, .command])
    #expect(s.displayText == s.displayText(for: .current))
    #expect(KeyboardShortcut.Platform.macOS.primaryModifiers == .command)
    #expect(KeyboardShortcut.Platform.linux.primaryModifiers == .control)
    #expect(KeyboardShortcut.Platform.windows.primaryModifiers == .control)
    #expect(KeyboardShortcut.Platform.allCases.count == 3)
    #expect(KeyboardShortcut.Platform.current.primaryModifiers == .primary)
    #if canImport(Darwin)
    #expect(KeyboardShortcut.Platform.current == .macOS)
    #endif
    // A shortcut built for another platform reads as that platform's.
    let linux = KeyboardShortcut("s", modifiers: KeyboardShortcut.Platform.linux.primaryModifiers)
    #expect(linux.displayText(for: .linux) == "Ctrl+S")
}

@MainActor @Test func theDrawnMenusTextIsTheSameFormatter() {
    for key in [KeyEquivalent.upArrow, "\u{f70f}", .return, "ß", "k"] {
        let s = shortcut(key, [.shift, .command])
        let platformKey = PlatformKeyEquivalent(key: String(key.character), modifiers: s.modifiers)
        #expect(MenuPanel.shortcutText(platformKey, platform: .mac) == s.displayText(for: .macOS))
        #expect(MenuPanel.shortcutText(platformKey, platform: .other, superKeyName: "Super")
                == s.displayText(for: .linux))
        #expect(MenuPanel.shortcutText(platformKey, platform: .other, superKeyName: "Win")
                == s.displayText(for: .windows))
    }
}

/// A `TextSystem` recording every string handed to `placeGlyphs`: what a menu row draws.
private final class DrawnTextSystem: TextSystem, @unchecked Sendable {
    let base = CoreTextTextSystem()
    var drawn: [String] = []
    func resolveFont(_ descriptor: FontDescriptor) -> FontKey { base.resolveFont(descriptor) }
    func fontMetrics(_ font: FontKey) -> TextFontMetrics { base.fontMetrics(font) }
    func measure(_ string: String, font: FontKey, wrappingAt width: Double?,
                 options: TextLayoutOptions) -> TextMeasurement {
        base.measure(string, font: font, wrappingAt: width, options: options)
    }
    func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?, options: TextLayoutOptions,
                     origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        drawn.append(string)
        return base.placeGlyphs(string, font: font, wrappingAt: width, options: options, origin: origin,
                                scaleFactor: scaleFactor)
    }
    func caretOffsets(_ string: String, font: FontKey) -> [Double] { base.caretOffsets(string, font: font) }
    func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?,
                    options: TextLayoutOptions) -> [Range<Int>] {
        base.lineRanges(string, font: font, wrappingAt: width, options: options)
    }
    func rasterize(_ key: GlyphKey) -> GlyphImage { base.rasterize(key) }
    func measure(_ text: StyledText, wrappingAt width: Double?,
                 options: TextLayoutOptions) -> StyledTextMeasurement {
        base.measure(text, wrappingAt: width, options: options)
    }
    func layOut(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions,
                origin: (x: Double, y: Double), scaleFactor: Float) -> StyledTextLayout {
        base.layOut(text, wrappingAt: width, options: options, origin: origin, scaleFactor: scaleFactor)
    }
    func decorationMetrics(_ font: FontKey) -> TextDecorationMetrics { base.decorationMetrics(font) }
    func beginFrame() { base.beginFrame() }
    func endFrame() { base.endFrame() }
}

/// A drawn menu row whose shortcut is the up arrow draws the arrow, not a
/// box (`KF-AG`). Literal: ⌘↑ is `⌘↑` on a Mac host, `Super+Up` elsewhere. Mutation:
/// restore the old path (`shortcut.key.uppercased()`): the row draws the
/// private-use character and this reddens.
@MainActor @Test func aDrawnMenuRowWithAnArrowShortcutDrawsTheArrowName() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let system = DrawnTextSystem()
    let platformWindow = try FakePlatformWindow(device: device, size: 400)
    let window = Window(platformWindow: platformWindow, startsDisplayLink: false, textSystem: system) {
        Column {
            Box().frame(width: Pixels(400), height: Pixels(400)).background(.surface).contextMenu {
                Button("Up") {}.keyboardShortcut(.upArrow, modifiers: .command)
            }
        }
    }
    platformWindow.presentsMenusNatively = false
    window.drawFrameIfNeeded()
    let at = Point(x: Pixels(10), y: Pixels(10))
    platformWindow.simulateInput(.rightMouseDown(MouseEvent(position: at)))
    platformWindow.simulateInput(.rightMouseUp(MouseEvent(position: at)))
    try #require(window.menuSession?.isNative == false, "an in-window menu is open")
    system.drawn = []
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #if canImport(Darwin)
    let expected = "⌘↑"
    #else
    let expected = "Super+Up"
    #endif
    #expect(system.drawn.contains(expected), "drawn: \(system.drawn)")
    #expect(!system.drawn.contains { $0.unicodeScalars.contains { (0xF700...0xF8FF).contains($0.value) } },
            "no private-use box is drawn")
}
