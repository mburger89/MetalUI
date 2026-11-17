// AppKit probe `P2` (ruling `KF-AI`, record 363): which items does AppKit insert into an app's
// main menu by itself, and with which key equivalents? `App.standardMenuShortcuts()` lists
// only what MetalUI's own bar model holds; this says whether it misses a key AppKit adds.
//
// HOW TO RUN (compiled form, SA-O; needs no display permission, an accessory-policy app):
//
//   xcrun swiftc docs/probes/appkit-menu-insertions.swift -o /tmp/p2 && /tmp/p2
//
// The bar is the MetalUI shape: App, File, Edit, Window, Help, each with one item, `windowsMenu`
// and `helpMenu` set, a titled resizable window with `.fullScreenPrimary` shown. After 1.5 s of
// run loop the whole main menu is printed: `[scalars-hex mask=<rawValue>>16]` is a key equivalent
// (4 control, 8 option, 16 command, 2 shift, 128 function).
//
// RECORDED 2026-11-17, macOS 27.2.1, Apple Swift 6.4.2, exit 0, stdout verbatim:
//
//   App
//     Probe App
//   File
//     Probe File
//   Edit
//     Probe Edit
//     ---
//     AutoFill
//       Contact…
//       Passwords…
//       Credit Card…
//     Start Dictation…
//     Start Dictation… [["64"] mask=128]
//     Emoji & Symbols [["20"] mask=16]
//     Emoji & Symbols [["20"] mask=20]
//     Emoji & Symbols [["65"] mask=128]
//   Window
//     Probe Window
//   Help
//     Probe Help
//
// So AppKit inserts, into the **Edit** menu only: AutoFill, Start Dictation (the second item the
// fn-D alternate) and Emoji & Symbols (three items: ⌘Space and ⌃⌘Space as hidden alternates, and fn-E).
// It added no Full Screen item (there is no View menu to hold it) and nothing to App, File, Window
// or Help. The keys an app can express, ⌘Space and ⌃⌘Space, are both in
// `KeyboardShortcut.systemReserved(on: .macOS)` already ("Spotlight Search", "Character Viewer"); the
// rest are Fn chords, which MetalUI's `Modifiers` cannot express. So `standardMenuShortcuts()` lists
// nothing for AppKit's insertions.
//
// Caveat: AppKit's insertions depend on the user's keyboard and dictation settings, and on a
// regular-policy app with a key window; this run was an accessory app, so a human check on a
// real MetalUI window (group KF) is still owed.

import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let main = NSMenu()
for title in ["App", "File", "Edit", "Window", "Help"] {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let sub = NSMenu(title: title)
    sub.addItem(NSMenuItem(title: "Probe \(title)", action: nil, keyEquivalent: ""))
    item.submenu = sub
    main.addItem(item)
}
app.mainMenu = main
app.windowsMenu = main.items[3].submenu
app.helpMenu = main.items[4].submenu
let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
w.collectionBehavior = [.fullScreenPrimary]
w.makeKeyAndOrderFront(nil)
app.finishLaunching()
RunLoop.main.run(until: Date().addingTimeInterval(1.5))
func dump(_ m: NSMenu, _ depth: Int) {
    for i in m.items {
        let ks = i.keyEquivalent.isEmpty ? "" : " [\(i.keyEquivalent.unicodeScalars.map{String($0.value,radix:16)}) mask=\(i.keyEquivalentModifierMask.rawValue >> 16)]"
        print(String(repeating: "  ", count: depth) + (i.isSeparatorItem ? "---" : i.title) + ks)
        if let s = i.submenu { dump(s, depth + 1) }
    }
}
dump(app.mainMenu!, 0)
