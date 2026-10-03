// SwiftUI probe: the menu bar — `.commands { CommandMenu; CommandGroup }` on a
// SwiftUI `App` (user request 2026-10-02, menus/popovers/tooltips; not a plan
// task). Companion of swiftui-menus-popovers.swift. Evidence for rulings MN-…
// in docs/superpowers/2026-10-02-menus-popovers-decisions.md.
//
// HOW TO RUN (compiled form, SA-O; an `App` needs -parse-as-library):
//
//   xcrun swiftc -parse-as-library docs/probes/swiftui-commands.swift -o /tmp/commands-probe
//   xcrun swiftc -parse-as-library -D PLAIN docs/probes/swiftui-commands.swift -o /tmp/commands-plain
//   /tmp/commands-plain; /tmp/commands-probe
//
// The app dumps NSApp.mainMenu once its window exists, then sends ⌘R (bound
// by BOTH a CommandMenu item and a window Button) and ⌘J (menu only) and ⌘T
// (button only) three ways: NSApp.sendEvent, the window's own
// performKeyEquivalent, and the main menu's performKeyEquivalent; then exits.
// Headless (synthesized NSEvents); the screen was locked when recorded, so the
// app was never active and had no key window — the sendEvent arm reads that
// state, the two direct arms do not depend on it.
//
// POSITIVE CONTROL / SEPARATING ARM: PLAIN (no `.commands`) against the full
// build: the default menu, then what CommandMenu/CommandGroup add or remove.
//
// RECORDED 2026-10-02 by the menus/popovers design session, macOS 27.0,
// Apple Swift 6.4, screen LOCKED (the app inactive, keyWindow nil — printed).
// Both builds run twice: stdout byte-identical, exit 0. PLAIN first, then
// the full build.
//
// OUTPUT, verbatim:
//
//   === PLAIN (no .commands): NSApp.mainMenu
//     "commands-plain" action=submenuAction:
//       "About commands-plain" action=orderFrontStandardAboutPanel:
//       ----
//       "Services" action=submenuAction:
//       ----
//       "Hide commands-plain" key="h" mods=16 action=hide:
//       "Hide Others" key="h" mods=24 action=hideOtherApplications:
//       "Show All" action=unhideAllApplications:
//       ----
//       "Quit commands-plain" key="q" mods=16 action=terminate:
//     "File" action=submenuAction:
//       "New Probe Window" key="n" mods=16 action=menuAction:
//       ----
//       ----
//       "Close" key="w" mods=16 action=performClose:
//       "Close All" key="w" mods=24 action=closeAll:
//     "Edit" action=submenuAction:
//       "Undo" key="z" mods=16 action=undo:
//       "Redo" key="z" mods=18 action=redo:
//       ----
//       "Cut" key="x" mods=16 action=cut:
//       "Copy" key="c" mods=16 action=copy:
//       "Paste" key="v" mods=16 action=paste:
//       "Delete" action=delete:
//       "Select All" key="a" mods=16 action=selectAll:
//       ----
//       "Writing Tools" action=submenuAction:
//       ----
//       "AutoFill" action=submenuAction:
//       "Start Dictation…" action=startDictation:
//       "Start Dictation…" key="d" mods=128 action=startDictation: hidden
//       "Emoji & Symbols" key=" " mods=16 action=orderFrontCharacterPalette:
//       "Emoji & Symbols" key=" " mods=20 action=orderFrontCharacterPalette: hidden
//       "Emoji & Symbols" key="e" mods=128 action=orderFrontCharacterPalette: hidden
//     "View" action=submenuAction:
//     "Window" action=submenuAction:
//       "Minimize" key="m" mods=16 action=performMiniaturize:
//       "Zoom" action=performZoom:
//       ----
//       "Bring All to Front" action=arrangeInFront:
//       ----
//       "Probe" action=makeKeyAndOrderFront:
//     "Help" action=submenuAction:
//       "commands-plain Help" key="?" mods=16 action=showHelp:
//       "Toggle Sidebar" key="s" mods=24 action=toggleSidebar: hidden
//     active=false keyWindow=nil window=AppKitWindow
//     ⌘R: NSApp.sendEvent -> ["button-R"] | window.performKeyEquivalent -> true ["button-R"] | mainMenu.performKeyEquivalent -> false []
//     ⌘J: NSApp.sendEvent -> [] | window.performKeyEquivalent -> false [] | mainMenu.performKeyEquivalent -> false []
//     ⌘T: NSApp.sendEvent -> ["button-T"] | window.performKeyEquivalent -> true ["button-T"] | mainMenu.performKeyEquivalent -> false []
//   exit 0
//   === FULL (.commands { CommandMenu Tools; CommandGroup(after: .newItem); CommandGroup(replacing: .help) }): NSApp.mainMenu
//     "commands-probe" action=submenuAction:
//       "About commands-probe" action=orderFrontStandardAboutPanel:
//       ----
//       "Services" action=submenuAction:
//       ----
//       "Hide commands-probe" key="h" mods=16 action=hide:
//       "Hide Others" key="h" mods=24 action=hideOtherApplications:
//       "Show All" action=unhideAllApplications:
//       ----
//       "Quit commands-probe" key="q" mods=16 action=terminate:
//     "File" action=submenuAction:
//       "New Probe Window" key="n" mods=16 action=menuAction:
//       "After New" action=menuAction:
//       ----
//       ----
//       "Close" key="w" mods=16 action=performClose:
//       "Close All" key="w" mods=24 action=closeAll:
//     "Edit" action=submenuAction:
//       "Undo" key="z" mods=16 action=undo:
//       "Redo" key="z" mods=18 action=redo:
//       ----
//       "Cut" key="x" mods=16 action=cut:
//       "Copy" key="c" mods=16 action=copy:
//       "Paste" key="v" mods=16 action=paste:
//       "Delete" action=delete:
//       "Select All" key="a" mods=16 action=selectAll:
//       ----
//       "Writing Tools" action=submenuAction:
//       ----
//       "AutoFill" action=submenuAction:
//       "Start Dictation…" action=startDictation:
//       "Start Dictation…" key="d" mods=128 action=startDictation: hidden
//       "Emoji & Symbols" key=" " mods=16 action=orderFrontCharacterPalette:
//       "Emoji & Symbols" key=" " mods=20 action=orderFrontCharacterPalette: hidden
//       "Emoji & Symbols" key="e" mods=128 action=orderFrontCharacterPalette: hidden
//     "View" action=submenuAction:
//     "Tools" action=submenuAction:
//       "Run" key="r" mods=16 action=menuAction:
//       "Jump" key="j" mods=16 action=menuAction:
//       ----
//       "Sub" action=submenuAction:
//       "Disabled"
//     "Window" action=submenuAction:
//       "Minimize" key="m" mods=16 action=performMiniaturize:
//       "Zoom" action=performZoom:
//       ----
//       "Bring All to Front" action=arrangeInFront:
//       ----
//       "Probe" action=makeKeyAndOrderFront:
//     "Help" action=submenuAction:
//     active=false keyWindow=nil window=AppKitWindow
//     ⌘R: NSApp.sendEvent -> ["menu-R"] | window.performKeyEquivalent -> true ["button-R"] | mainMenu.performKeyEquivalent -> true ["menu-R"]
//     ⌘J: NSApp.sendEvent -> ["menu-J"] | window.performKeyEquivalent -> false [] | mainMenu.performKeyEquivalent -> true ["menu-J"]
//     ⌘T: NSApp.sendEvent -> ["button-T"] | window.performKeyEquivalent -> true ["button-T"] | mainMenu.performKeyEquivalent -> false []
//   exit 0

import AppKit
import SwiftUI

final class Log: @unchecked Sendable { var lines: [String] = [] }
let log = Log()

@MainActor func dump(_ m: NSMenu, _ d: Int) {
    for item in m.items {
        var s = String(repeating: "  ", count: d)
        if item.isSeparatorItem { print(s + "----"); continue }
        s += "\"\(item.title)\""
        if !item.keyEquivalent.isEmpty {
            s += " key=\(item.keyEquivalent.debugDescription) mods=\(item.keyEquivalentModifierMask.rawValue >> 16)"
        }
        if let a = item.action { s += " action=\(a)" }
        if item.isHidden { s += " hidden" }
        print(s)
        if let sub = item.submenu, d < 2 { dump(sub, d + 1) }
    }
}
@MainActor func keyEvent(_ w: NSWindow?, _ c: String, _ flags: NSEvent.ModifierFlags = .command) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                     windowNumber: w?.windowNumber ?? 0, context: nil, characters: c, charactersIgnoringModifiers: c,
                     isARepeat: false, keyCode: 0)!
}

struct Content: View {
    var body: some View {
        VStack {
            Button("Window R") { log.lines.append("button-R") }.keyboardShortcut("r")
            Button("Window T") { log.lines.append("button-T") }.keyboardShortcut("t")
        }.frame(width: 300, height: 200)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { MainActor.assumeIsolated { report() } } }
    }
}

@MainActor func report() {
    #if PLAIN
    print("=== PLAIN (no .commands): NSApp.mainMenu")
    #else
    print("=== FULL (.commands { CommandMenu Tools; CommandGroup(after: .newItem); CommandGroup(replacing: .help) }): NSApp.mainMenu")
    #endif
    if let m = NSApp.mainMenu { dump(m, 1) } else { print("  nil") }
    let w = NSApp.windows.first { $0.contentView is NSHostingView<Content> } ?? NSApp.windows.first { $0.isVisible }
    print("  active=\(NSApp.isActive) keyWindow=\(NSApp.keyWindow.map { "\(type(of: $0))" } ?? "nil") window=\(w.map { "\(type(of: $0))" } ?? "nil")")
    for c in ["r", "j", "t"] {
        log.lines = []
        NSApp.sendEvent(keyEvent(w, c)); RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let a = log.lines; log.lines = []
        let wHandled = w?.performKeyEquivalent(with: keyEvent(w, c)) ?? false; RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let b = log.lines; log.lines = []
        let mHandled = NSApp.mainMenu?.performKeyEquivalent(with: keyEvent(w, c)) ?? false; RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let d = log.lines
        print("  ⌘\(c.uppercased()): NSApp.sendEvent -> \(a) | window.performKeyEquivalent -> \(wHandled) \(b) | mainMenu.performKeyEquivalent -> \(mHandled) \(d)")
    }
    exit(0)
}

@main
struct ProbeApp: App {
    var body: some Scene {
        WindowGroup("Probe") { Content() }
        #if !PLAIN
        .commands {
            CommandMenu("Tools") {
                Button("Run") { log.lines.append("menu-R") }.keyboardShortcut("r")
                Button("Jump") { log.lines.append("menu-J") }.keyboardShortcut("j")
                Divider()
                Menu("Sub") { Button("Deep") {} }
                Button("Disabled") {}.disabled(true)
            }
            CommandGroup(after: .newItem) { Button("After New") {} }
            CommandGroup(replacing: .help) { }
        }
        #endif
    }
}
