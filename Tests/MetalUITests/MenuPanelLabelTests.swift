import Testing
import MetalUIPlatform
@testable import MetalUI

// SMK port gaps, lane 1 — test 2.2 (ruling `SG-B` item 5, moved to lane 1 by
// `SG-H` item 5; spec `docs/superpowers/specs/2026-10-09-smk-gaps-design.md`
// §5). The drawn menu's shortcut text off Apple names each key honestly:
// `.control` "Ctrl", `.command` the Super/Windows key ("Super" on Linux, "Win"
// on Windows — the SDL bridge maps `SDL_KMOD_GUI` to `.command`), `.option`
// "Alt", `.shift` "Shift", in that order. Red before: `.command` read "Ctrl".

private func text(_ key: String, _ modifiers: Modifiers, _ platform: TextEditing.Platform,
                  superKeyName: String = "Super") -> String? {
    MenuPanel.shortcutText(PlatformKeyEquivalent(key: key, modifiers: modifiers), platform: platform,
                           superKeyName: superKeyName)
}

/// **2.2** (`SG-B` item 5). Off Apple: Ctrl+K, Super+K (Win+K with the
/// Windows name), Ctrl+Super+Alt+Shift+K, and a default (`.primary`)
/// shortcut reads as the key it is. The Mac spelling is unchanged. Mutation:
/// `.command` labelled "Ctrl" — reddens.
@Test func aDrawnMenusShortcutTextNamesEachKey() {
    #expect(text("k", .control, .other) == "Ctrl+K")
    #expect(text("k", .command, .other) == "Super+K", "the Super key is not Ctrl")
    #expect(text("k", .command, .other, superKeyName: "Win") == "Win+K", "Windows' name for it")
    #expect(text("k", [.control, .command, .option, .shift], .other) == "Ctrl+Super+Alt+Shift+K")
    #expect(text("s", [.option, .shift], .other) == "Alt+Shift+S")
    #if canImport(Darwin)
    #expect(text("s", .primary, .other) == "Super+S", "on macOS the primary modifier is ⌘, the Super bit")
    #else
    #expect(text("s", .primary, .other) == "Ctrl+S", "off Apple a default shortcut reads Ctrl+S and is Ctrl+S")
    #endif
    #if os(Windows)
    #expect(MenuPanel.superKeyName == "Win")
    #else
    #expect(MenuPanel.superKeyName == "Super")
    #endif
    // The Mac spelling, unchanged: ⌃⌥⇧⌘ order, glyphs, no separators.
    #expect(text("k", [.control, .command, .option, .shift], .mac) == "⌃⌥⇧⌘K")
    #expect(text("k", .command, .mac) == "⌘K")
    #expect(MenuPanel.shortcutText(nil, platform: .other) == nil)
}
