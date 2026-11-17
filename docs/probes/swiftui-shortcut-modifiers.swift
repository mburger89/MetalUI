// SwiftUI probe: the keyboard shortcut's default modifier and whether SwiftUI
// spells a "primary" (⌘ on Apple, Ctrl elsewhere) modifier (C12, SMK port gap
// MG-24; user request 2026-10-02). Evidence for ruling SG-B in
// docs/superpowers/2026-10-09-smk-gaps-decisions.md.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc -parse-as-library docs/probes/swiftui-shortcut-modifiers.swift -o /tmp/shortcut-probe && /tmp/shortcut-probe
//   xcrun swiftc -parse-as-library -D PRIMARY docs/probes/swiftui-shortcut-modifiers.swift -o /tmp/shortcut-primary
//
// POSITIVE CONTROL / SEPARATING ARM: the default build spells `.command` and
// compiles and runs; the PRIMARY build differs only in spelling
// `EventModifiers.primary` and must be refused by the compiler (no such
// member). A third spelling, `.platform`, is tried under -D PLATFORM.
//
// RECORDED 2026-10-09 by the C12 design session, macOS 27.0.1, Apple Swift 6.4
// (swiftlang-6.4.0.33.1). Default build, exit 0, stdout verbatim:
//
//   KeyboardShortcut("s").modifiers == .command: true
//   KeyboardShortcut("s").modifiers.rawValue: 16
//   EventModifiers.capsLock.rawValue = 1
//   EventModifiers.shift.rawValue = 2
//   EventModifiers.control.rawValue = 4
//   EventModifiers.option.rawValue = 8
//   EventModifiers.command.rawValue = 16
//   EventModifiers.numericPad.rawValue = 32
//   EventModifiers.all.rawValue = 63
//   KeyboardShortcut.defaultAction.modifiers.rawValue: 0
//   KeyboardShortcut.cancelAction.modifiers.rawValue: 0
//
// -D PRIMARY, exit 1:  error: type 'EventModifiers' has no member 'primary'
// -D PLATFORM, exit 1: error: type 'EventModifiers' has no member 'platform'
//
// P1 (KF-AI), 2026-11-17, macOS 27.2.1, Apple Swift 6.4.2, default build, exit 0, the two added lines:
//
//   P1 Set<KeyboardShortcut>.count: 3
//   P1 KeyboardShortcut("P") != KeyboardShortcut("p"): true
//
// (so `Set<KeyboardShortcut>` compiles, SwiftUI's shortcut is Hashable, and "P" and "p" are different
// elements). -D DISPLAYTEXT, exit 1: error: value of type 'KeyboardShortcut' has no member 'displayText'.
// -D CONFLICTS, exit 1: error: value of type 'KeyboardShortcut' has no member 'conflicts'.
//
// So: SwiftUI's default is `.command` (16), and SwiftUI spells no modifier
// that means "⌘ on Apple, Ctrl elsewhere" — SwiftUI ships only on Apple
// platforms, where `.command` is that modifier.

import SwiftUI

@main
struct Probe {
    @MainActor static func main() {
        let shortcut = KeyboardShortcut("s")
        print("KeyboardShortcut(\"s\").modifiers == .command:", shortcut.modifiers == .command)
        print("KeyboardShortcut(\"s\").modifiers.rawValue:", shortcut.modifiers.rawValue)
        let named: [(String, EventModifiers)] = [("capsLock", .capsLock), ("shift", .shift), ("control", .control),
                                                 ("option", .option), ("command", .command),
                                                 ("numericPad", .numericPad), ("all", .all)]
        for (name, value) in named { print("EventModifiers.\(name).rawValue =", value.rawValue) }
        print("KeyboardShortcut.defaultAction.modifiers.rawValue:", KeyboardShortcut.defaultAction.modifiers.rawValue)
        print("KeyboardShortcut.cancelAction.modifiers.rawValue:", KeyboardShortcut.cancelAction.modifiers.rawValue)
        // Arm P1 (ruling KF-AI): KeyboardShortcut is Hashable, and "P" is not "p".
        let set: Set<KeyboardShortcut> = [KeyboardShortcut("p"), KeyboardShortcut("p"), KeyboardShortcut("P"),
                                          KeyboardShortcut("p", modifiers: [.command, .shift])]
        print("P1 Set<KeyboardShortcut>.count:", set.count)
        print("P1 KeyboardShortcut(\"P\") != KeyboardShortcut(\"p\"):", KeyboardShortcut("P") != KeyboardShortcut("p"))
        #if DISPLAYTEXT
        print(KeyboardShortcut("p").displayText)
        #endif
        #if CONFLICTS
        print(KeyboardShortcut("p").conflicts(with: KeyboardShortcut("P")))
        #endif
        #if PRIMARY
        let primary: EventModifiers = .primary
        print(primary)
        #endif
        #if PLATFORM
        let platform: EventModifiers = .platform
        print(platform)
        #endif
    }
}
