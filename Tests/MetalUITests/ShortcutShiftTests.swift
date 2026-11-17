import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// `KF-AL`: a shifted shortcut matches one way on every platform. AppKit keeps
// Shift's effect in `charactersIgnoringModifiers` (⇧/ is "?", ⇧1 is "!", ⇧Tab
// is "\u{19}"); SDL reports the unshifted key. `KeyEvent.unshiftedKey` carries
// the base key, and `KeyboardShortcut.matches` takes it with Shift beside the
// characters path.

/// An AppKit-shaped key-down: `ignoring` is what `charactersIgnoringModifiers`
/// says, `base` the layout's unshifted key.
private func appKit(_ ignoring: String, base: String = "", _ modifiers: Modifiers) -> KeyEvent {
    var key = KeyEvent(charactersIgnoringModifiers: ignoring, characters: ignoring, modifiers: modifiers, timestamp: 0)
    key.unshiftedKey = base
    return key
}

/// An SDL-shaped key-down: the keycode's own character, base key the same.
private func sdl(_ base: String, _ modifiers: Modifiers) -> KeyEvent {
    appKit(base, base: base, modifiers)
}

/// **KF-AL 1.** AppKit's ⇧⌘P ("P" ignoring modifiers) fires a
/// `[.primary, .shift]`-style "p" shortcut; confirms existing behaviour.
/// Mutation: drop the `.lowercased()` of the event's characters — reddens.
@Test @MainActor func appKitShiftCommandPFiresAPShortcut() {
    let shortcut = KeyboardShortcut("p", modifiers: [.command, .shift])
    #expect(shortcut.matches(appKit("P", [.command, .shift])), "the characters path alone, no base key")
    #expect(shortcut.matches(appKit("P", base: "p", [.command, .shift])))
    #expect(shortcut.matches(sdl("p", [.command, .shift])))
    #expect(!shortcut.matches(appKit("p", base: "p", [.command])), "plain ⌘P is another shortcut")
    #expect(!shortcut.matches(appKit("P", base: "p", [.command, .shift, .option])), "extra modifiers do not match")
}

/// **KF-AL 2.** AppKit's ⇧Tab arrives as "\u{19}"; `KeyboardShortcut(.tab,
/// modifiers: .shift)` fires on it, on SDL's "\t" too. Mutation: remove the
/// "\u{19}" reading in `matches` — reddens.
@Test @MainActor func shiftTabFiresATabShiftShortcutOnAppKitsBacktab() {
    let shortcut = KeyboardShortcut(.tab, modifiers: .shift)
    #expect(shortcut.matches(appKit("\u{19}", .shift)))
    #expect(shortcut.matches(sdl("\t", .shift)))
    #expect(!KeyboardShortcut(.tab, modifiers: []).matches(appKit("\u{19}", .shift)), "backtab carries Shift")
}

/// **KF-AL 3.** ⇧/ fires "/" + Shift on AppKit (ignoring "?", base "/") as on
/// SDL, and a shortcut spelled "?" + Shift still fires on AppKit. Mutation:
/// ignore `unshiftedKey` — the AppKit arm reddens.
@Test @MainActor func shiftSlashFiresASlashShortcutOnBothPlatforms() {
    let slash = KeyboardShortcut("/", modifiers: .shift)
    #expect(slash.matches(appKit("?", base: "/", .shift)), "AppKit: ⇧/ is \"?\" with base \"/\"")
    #expect(slash.matches(sdl("/", .shift)), "SDL: keycode \"/\" with Shift")
    #expect(KeyboardShortcut("?", modifiers: .shift).matches(appKit("?", base: "/", .shift)), "the shifted spelling still fires")
    #expect(!KeyboardShortcut("/", modifiers: []).matches(appKit("?", base: "/", .shift)), "Shift must be in the shortcut")
    #expect(!slash.matches(appKit("?", base: "", .shift)), "no base key, no match")
    #expect(!KeyboardShortcut("/", modifiers: .command).matches(appKit("?", base: "/", .command)), "base key is for Shift only")
}

/// **KF-AL 4.** ⇧1: AppKit's "!" with base "1" fires "1" + Shift; "!" + Shift
/// still fires. Mutation: ignore `unshiftedKey` — reddens.
@Test @MainActor func shiftOneFiresAOneShortcutAndABangShortcut() {
    #expect(KeyboardShortcut("1", modifiers: .shift).matches(appKit("!", base: "1", .shift)))
    #expect(KeyboardShortcut("1", modifiers: .shift).matches(sdl("1", .shift)))
    #expect(KeyboardShortcut("!", modifiers: .shift).matches(appKit("!", base: "1", .shift)))
    #expect(!KeyboardShortcut("1", modifiers: []).matches(appKit("!", base: "1", .shift)))
}

/// **KF-AL 5.** A `Button` in a window runs on the AppKit-shaped ⇧/ and ⇧⌘P
/// through the shortcut stage. Mutation: as 3 and 1.
@Test @MainActor func aButtonShortcutRunsOnAppKitShapedShiftKeys() throws {
    var runs: [String] = []
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200) {
        Column {
            Button("Slash") { runs.append("slash") }.keyboardShortcut("/", modifiers: .shift)
            Button("P") { runs.append("p") }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Back") { runs.append("back") }.keyboardShortcut(.tab, modifiers: .shift)
        }
    }
    window.drawFrameIfNeeded()
    platform.simulateInput(.keyDown(appKit("?", base: "/", .shift)))
    platform.simulateInput(.keyDown(appKit("P", base: "p", [.command, .shift])))
    platform.simulateInput(.keyDown(appKit("\u{19}", .shift)))
    #expect(runs == ["slash", "p", "back"])
}
