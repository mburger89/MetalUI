import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Ruling `KF-AI`: which keys are already taken. `systemReserved`,
// `standardMenuShortcuts`, `commandShortcuts`, `conflicts(with:)`, `Hashable`.

private let appName = ProcessInfo.processInfo.processName

@MainActor private func claimsApp(native: Bool = true) throws -> (App, FakePlatform) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = FakePlatform(device: device)
    platform.menuBarIsNative = native
    return (App(platform: platform), platform)
}

private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers = []) -> KeyboardShortcut {
    KeyboardShortcut(key, modifiers: modifiers)
}

private func fkey(_ n: Int) -> KeyEquivalent {
    guard let scalar = Unicode.Scalar(UInt32(0xF704 + n - 1)) else { preconditionFailure("F\(n) has no private-use scalar") }
    return KeyEquivalent(Character(scalar))
}

/// A claim as text: its display text on `platform` and its title, for readable failures.
private func text(_ claims: [ClaimedShortcut], _ platform: KeyboardShortcut.Platform = .macOS) -> [String] {
    claims.map { "\($0.title) \($0.shortcut.displayText(for: platform))" }
}

// MARK: - Hashable and conflicts(with:)

/// `Hashable` (class A, probe `P1`): a `Set` holds shortcuts, `"P"` and `"p"` are different elements, the same
/// shortcut twice is one. Mutation: `KeyboardShortcut`'s `==` compares keys lower-cased (a hand-written `==`
/// and `hash(into:)`): the two-element expectation reddens.
@Test func aShortcutIsHashableAndPAndLowercasePAreDifferent() {
    let set: Set<KeyboardShortcut> = [shortcut("p", .command), shortcut("p", .command), shortcut("P", .command),
                                      shortcut("p", [.command, .shift])]
    #expect(set.count == 3)
    #expect(shortcut("P") != shortcut("p"))
    let first = shortcut("p", .command), second = shortcut("p", .command)
    #expect(first.hashValue == second.hashValue)
}

/// `conflicts(with:)`: the modifiers equal exactly and the key the same once lower-cased. Mutations: compare
/// the keys without lower-casing ("P" vs "p" reddens); compare modifiers with `isSubset` (the ⌘/⇧⌘ pair reddens).
@Test func conflictsMeansTheSameModifiersAndTheSameKeyCaseFolded() {
    #expect(shortcut("P", .command).conflicts(with: shortcut("p", .command)), "case folded; the two are != ")
    #expect(shortcut("p", .command).conflicts(with: shortcut("P", .command)), "symmetric")
    #expect(!shortcut("p", .command).conflicts(with: shortcut("p", [.command, .shift])), "modifiers exactly")
    #expect(!shortcut("p", [.command, .shift]).conflicts(with: shortcut("p", .command)))
    #expect(!shortcut("p", .command).conflicts(with: shortcut("p", .control)))
    #expect(!shortcut("p", .command).conflicts(with: shortcut("o", .command)))
    #expect(shortcut("k", []).conflicts(with: shortcut("k", [])))
    #expect(!shortcut("k", []).conflicts(with: shortcut("k", .command)))
}

/// AppKit's ⇧Tab character reads as Tab (`KF-AL` item 2). Mutation: drop the `"\u{19}"` case in `conflictKey`.
@Test func conflictsReadAppKitsShiftTabAsTab() {
    #expect(shortcut("\u{19}", .shift).conflicts(with: shortcut(.tab, .shift)))
    #expect(shortcut(.tab, .shift).conflicts(with: shortcut("\u{19}", .shift)))
    #expect(!shortcut("\u{19}", []).conflicts(with: shortcut(.tab, .shift)), "different modifiers")
    #expect(shortcut("\u{19}", []).conflicts(with: shortcut(.tab, [])), "the character is Tab whatever the modifiers")
}

/// `KF-AL`'s one form for a shifted key: "?" with ⇧ is "/" with ⇧ (and "!" is "1"). Without ⇧ they are different
/// keys. Mutations: drop the base-key table ("?" vs "/" reddens); apply it without checking Shift (the unshifted
/// "?" vs "/" expectation reddens).
@Test func conflictsReadAShiftedKeyAsItsBaseKey() {
    #expect(shortcut("?", .shift).conflicts(with: shortcut("/", .shift)))
    #expect(shortcut("/", [.shift, .command]).conflicts(with: shortcut("?", [.shift, .command])))
    #expect(shortcut("!", .shift).conflicts(with: shortcut("1", .shift)))
    #expect(shortcut("<", [.shift, .control]).conflicts(with: shortcut(",", [.shift, .control])))
    #expect(!shortcut("?", []).conflicts(with: shortcut("/", [])), "no Shift: two keys")
    #expect(!shortcut("?", .shift).conflicts(with: shortcut("/", [])), "modifiers differ")
    #expect(!shortcut("?", .shift).conflicts(with: shortcut("1", .shift)))
}

// MARK: - systemReserved

/// Each platform's list holds the keys the design requires, with source `.system`. Mutation: drop an entry from a list.
@Test func theSystemReservedListsHoldTheDesktopsKeys() {
    func has(_ platform: KeyboardShortcut.Platform, _ key: KeyEquivalent, _ modifiers: EventModifiers) -> Bool {
        KeyboardShortcut.systemReserved(on: platform).contains { $0.shortcut == shortcut(key, modifiers) }
    }
    #expect(has(.macOS, .tab, .command))
    #expect(has(.macOS, .tab, [.command, .shift]))
    #expect(has(.macOS, "`", .command))
    #expect(has(.macOS, .space, .command))
    #expect(has(.macOS, .space, [.command, .option]))
    #expect(has(.macOS, .upArrow, .control) && has(.macOS, .downArrow, .control))
    #expect(has(.macOS, .leftArrow, .control) && has(.macOS, .rightArrow, .control))
    #expect(has(.macOS, "q", [.control, .command]))
    #expect(has(.macOS, "3", [.command, .shift]) && has(.macOS, "4", [.control, .command, .shift]))
    #expect(has(.macOS, fkey(11), []) && has(.macOS, fkey(2), .control) && has(.macOS, fkey(8), .control))
    #expect(!has(.macOS, fkey(9), .control))

    #expect(has(.windows, .tab, .option))
    #expect(has(.windows, fkey(4), .option))
    #expect(has(.windows, .deleteForward, [.control, .option]))
    #expect(has(.windows, "l", .command) && has(.windows, "d", .command) && has(.windows, ".", .command))
    #expect(has(.windows, "s", [.command, .shift]) && has(.windows, fkey(4), [.command, .control]))
    #expect(has(.windows, .leftArrow, [.command, .shift]))

    #expect(has(.linux, .tab, .option) && has(.linux, .tab, [.option, .shift]))
    #expect(has(.linux, .tab, .command) && has(.linux, .tab, [.command, .shift]))
    #expect(has(.linux, "`", .option))
    for n in [2, 4, 7, 8, 10] { #expect(has(.linux, fkey(n), .option), "Alt+F\(n)") }
    #expect(has(.linux, .space, .option) && has(.linux, .space, .command) && has(.linux, .space, [.command, .shift]))
    #expect(has(.linux, "l", .command) && has(.linux, "a", .command) && has(.linux, "v", .command))
    #expect(has(.linux, .pageUp, [.command, .shift]) && has(.linux, .pageDown, .command))
    #expect(has(.linux, "t", [.control, .option]) && has(.linux, .deleteForward, [.control, .option]))

    for platform in KeyboardShortcut.Platform.allCases {
        #expect(KeyboardShortcut.systemReserved(on: platform).allSatisfy { $0.source == .system && $0.identifier == nil
            && !$0.isConditional && $0.condition == nil })
    }
    #expect(KeyboardShortcut.systemReserved().map(\.shortcut) == KeyboardShortcut.systemReserved(on: .current).map(\.shortcut))
}

/// The lists' sizes are pinned so a dropped or added entry is a decision, not a drift.
@Test func theSystemReservedListsHaveTheirFixedSizes() {
    #expect(KeyboardShortcut.systemReserved(on: .macOS).count == 28)
    #expect(KeyboardShortcut.systemReserved(on: .windows).count == 32)
    #expect(KeyboardShortcut.systemReserved(on: .linux).count == 26)
}

/// No two entries of one list conflict (`conflicts(with:)`, so also no duplicate), and each title is unique within
/// its own list shape. Mutation: add Super+Shift+Space twice to the Linux list (the design wrote it twice).
@Test func noTwoSystemReservedEntriesConflict() {
    for platform in KeyboardShortcut.Platform.allCases {
        let claims = KeyboardShortcut.systemReserved(on: platform)
        #expect(!claims.isEmpty)
        for (i, a) in claims.enumerated() {
            for b in claims[(i + 1)...] where a.shortcut.conflicts(with: b.shortcut) {
                Issue.record("\(platform): \(a.title) and \(b.title) are both \(a.shortcut.displayText(for: platform))")
            }
        }
    }
}

/// The list is the platform's, not the host's: a Mac host's `.windows` list uses the Win key (`.command`) and Alt
/// (`.option`) outright and its `.linux` Super+L is `.command` too, not `.primary`. Mutation: spell a Windows
/// Ctrl entry `.primary` — on this Mac host it becomes ⌘ and `Ctrl+Esc` is missing.
@Test func aPlatformsListDoesNotDependOnThePrimaryModifier() {
    let windows = KeyboardShortcut.systemReserved(on: .windows).map { $0.shortcut.displayText(for: .windows) }
    #expect(windows.contains("Ctrl+Esc") && windows.contains("Ctrl+Shift+Esc") && windows.contains("Ctrl+Alt+Delete"))
    #expect(windows.contains("Alt+F4") && windows.contains("Win+L") && windows.contains("Win+Shift+S"))
    let linux = KeyboardShortcut.systemReserved(on: .linux).map { $0.shortcut.displayText(for: .linux) }
    #expect(linux.contains("Super+L") && linux.contains("Alt+Tab") && linux.contains("Super+Shift+Page Up"))
    let mac = KeyboardShortcut.systemReserved(on: .macOS).map { $0.shortcut.displayText(for: .macOS) }
    #expect(mac.contains("⌘⇥") && mac.contains("⇧⌘⇥") && mac.contains("⌃↑") && mac.contains("⌃⇧⌘3") && mac.contains("F11"))
}

// MARK: - standardMenuShortcuts

/// The AppKit arrangement, exact and in menu order. Mutation: add a standard item with a key, or drop the
/// `standardAction` filter (a command's key appears: see the next test).
@MainActor @Test func theStandardListOnAppKitIsExactAndInOrder() throws {
    let (app, _) = try claimsApp(native: true)
    let claims = app.standardMenuShortcuts()
    #expect(claims.map(\.title) == ["Hide \(appName)", "Hide Others", "Quit \(appName)", "Close", "Undo", "Redo",
                                    "Cut", "Copy", "Paste", "Select All", "Minimize"])
    #expect(text(claims).map { String($0.split(separator: " ").last ?? "") } == ["⌘H", "⌥⌘H", "⌘Q", "⌘W", "⌘Z", "⇧⌘Z", "⌘X",
                                                                            "⌘C", "⌘V", "⌘A", "⌘M"])
    #expect(claims.allSatisfy { $0.source == .standardMenu && $0.identifier == nil && !$0.isConditional })
    #expect(!claims.contains { $0.shortcut.key == KeyEquivalent(Character(ContextMenuKeys.f10)) }, "no drawn bar, no F10")
}

/// A `CommandGroup(replacing: .pasteboard)` removes Cut, Copy, Paste and Select All (Delete has no key). The
/// command items are not standard ones. Mutation: list the standard items from a fresh default bar instead of the
/// evaluated one.
@MainActor @Test func replacingAGroupRemovesItsStandardKeys() throws {
    let (app, _) = try claimsApp(native: true)
    app.commands {
        CommandGroup(replacing: .pasteboard) { Button("Only Paste") {}.keyboardShortcut("v", modifiers: [.command, .option]) }
    }
    let titles = app.standardMenuShortcuts().map(\.title)
    #expect(titles == ["Hide \(appName)", "Hide Others", "Quit \(appName)", "Close", "Undo", "Redo", "Minimize"],
            "\(titles)")
    #expect(app.commandShortcuts().map(\.title) == ["Only Paste"])
}

/// The drawn arrangement: the Edit six, then F10 and Shift-F10 and the Menu key, the same before and after `commands`.
/// Close and Quit show no key there. Mutation: leave the drawn extras out, or build the AppKit list when drawn.
@MainActor @Test func theDrawnStandardListIsTheEditSixAndTheBarsOwnKeys() throws {
    let (app, _) = try claimsApp(native: false)
    #expect(app.menuBarIsDrawn)
    let before = app.standardMenuShortcuts()
    app.commands { CommandMenu("Tools") { Button("Run") {}.keyboardShortcut("r") } }
    let after = app.standardMenuShortcuts()
    #expect(before == after)
    #expect(before.map(\.title) == ["Undo", "Redo", "Cut", "Copy", "Paste", "Select All", "Open Menu Bar",
                                    "Show Context Menu", "Show Context Menu"])
    let f10 = KeyEquivalent(Character(ContextMenuKeys.f10)), menu = KeyEquivalent(Character(ContextMenuKeys.menuKey))
    #expect(Array(before.suffix(3).map(\.shortcut)) == [shortcut(f10), shortcut(f10, .shift), shortcut(menu)])
    #expect(Array(before.prefix(6).map(\.shortcut.modifiers)) == [.primary, [.primary, .shift], .primary, .primary, .primary, .primary])
    #expect(text(Array(before.suffix(3)), .linux) == ["Open Menu Bar F10", "Show Context Menu Shift+F10",
                                                       "Show Context Menu Menu"], "the Menu key has a name (U+F735), not a blank box")
    #expect(before.allSatisfy { $0.source == .standardMenu })
}

// MARK: - commandShortcuts

/// Every command item with a key, in menu order: disabled ones, submenu items and toggles included, identifiers
/// carried, items with no key left out (a `Toggle` has no `keyboardShortcut` in MetalUI, so it is, with its identifier), the key as the menu shows it (lower-cased). Mutations: skip disabled items
/// (the Dim item is missing); stop at submenus (Deep is missing); list items with no key (Plain and Pinned appear).
@MainActor @Test func theCommandListHoldsEveryKeyedItemInMenuOrder() throws {
    let (app, _) = try claimsApp(native: true)
    app.commands {
        CommandMenu("Tools") {
            Button("Run") {}.keyboardShortcut("r").accessibilityIdentifier("cmd-run")
            Button("Plain") {}
            Divider()
            Button("Dim") {}.keyboardShortcut("D", modifiers: [.command, .shift]).disabled(true).accessibilityIdentifier("cmd-dim")
            Menu("More") {
                Button("Deep") {}.keyboardShortcut("e", modifiers: .control)
                Toggle("Pinned", isOn: .constant(true)).accessibilityIdentifier("cmd-pinned")
            }
        }
        CommandMenu("Second") { Button("Next") {}.keyboardShortcut(.return, modifiers: .command) }
    }
    let claims = app.commandShortcuts()
    #expect(claims.map(\.title) == ["Run", "Dim", "Deep", "Next"], "\(claims.map(\.title))")
    #expect(claims.map(\.identifier) == ["cmd-run", "cmd-dim", nil, nil])
    #expect(claims.map(\.shortcut) == [shortcut("r", .command), shortcut("d", [.command, .shift]), shortcut("e", .control),
                                        shortcut(.return, .command)])
    #expect(claims.allSatisfy { $0.source == .command && !$0.isConditional && $0.condition == nil })
    // The standard list does not gain the command items.
    #expect(!app.standardMenuShortcuts().contains { $0.source == .command })
}

/// An app with no `commands` has no command claims. A command item in a drawn bar is listed too.
@MainActor @Test func theCommandListIsEmptyWithoutCommandsAndWorksWhenDrawn() throws {
    let (app, _) = try claimsApp(native: false)
    #expect(app.commandShortcuts().isEmpty)
    app.commands { CommandMenu("Tools") { Button("Run") {}.keyboardShortcut("r").accessibilityIdentifier("cmd-run") } }
    #expect(app.commandShortcuts().map(\.identifier) == ["cmd-run"])
}

/// Each `App` read runs the `commands` content once, and a keystroke still runs it once: the reads add no per-key
/// work (`MenuBarModel` and the command stage are unchanged). Mutation: evaluate the bar twice in
/// `menuItemClaims` (the read count reddens).
@MainActor @Test func eachReadEvaluatesTheContentOnceAndAKeystrokeStillOnce() throws {
    let (app, platform) = try claimsApp(native: true)
    var runs = 0
    app.commands {
        let _: Void = { runs += 1 }()
        CommandMenu("Tools") { Button("Run") {}.keyboardShortcut("r") }
    }
    runs = 0
    _ = app.standardMenuShortcuts()
    #expect(runs == 1, "standardMenuShortcuts: \(runs)")
    runs = 0
    _ = app.commandShortcuts()
    #expect(runs == 1, "commandShortcuts: \(runs)")

    let window = try app.openWindow(title: "W", size: Size(width: Pixels(64), height: Pixels(64)),
                                    startsDisplayLink: false) { Box().frame(width: Pixels(10), height: Pixels(10)) }
    let fake = try #require(platform.openedWindows.last)
    runs = 0
    _ = fake.simulateInput(.keyDown(KeyEvent(charactersIgnoringModifiers: "r", characters: "r", modifiers: .command, timestamp: 0)))
    #expect(runs == 1, "a keystroke: \(runs)")
    withExtendedLifetime(window) {}
}

// MARK: - ClaimedShortcut

/// The conditional flag and condition default to off and carry through; the claims are `Hashable`.
@Test func aClaimedShortcutCarriesItsConditionAndIsHashable() {
    let plain = ClaimedShortcut(title: "A", shortcut: shortcut("a", .command), source: .codeView)
    #expect(!plain.isConditional && plain.condition == nil && plain.identifier == nil)
    let conditional = ClaimedShortcut(title: "Find Next", shortcut: shortcut("g", .command), source: .codeView,
                                      identifier: "x", isConditional: true, condition: "only with find matches")
    #expect(conditional.isConditional && conditional.condition == "only with find matches" && conditional.identifier == "x")
    #expect(Set([plain, plain, conditional]).count == 2)
    #expect(plain != conditional)
}
