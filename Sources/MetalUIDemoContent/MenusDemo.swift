import MetalUI
import Foundation

/// The menus, popovers and tooltips demo (spec
/// `2026-10-02-menus-popovers-design.md` §7), reached with
/// `METALUI_MENUS_DEMO=1 swift run MetalUIDemo`. A card with a context menu
/// (Copy, Rename, a separator, a Colour submenu, a Pinned toggle, a disabled
/// Delete, Duplicate on ⌘D) and a status line naming the last choice; a
/// button presenting a popover (a text, a field and a Close button); three
/// texts explaining themselves with `.help`; a `Menu("Actions")` pull-down.
/// `main.swift` adds a Demo menu and a New Note item to the menu bar in this
/// mode only.
///
/// **The human looks** (`docs/verification/human-checks.md` group R): the
/// native menu, right-click and control-click, the drawn menu under SDL, the
/// menu bar, the popover's look and dismissal, the tooltip's delay.
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. Each section is its own function, passed as an
/// argument to a generic composing function — the Windows stack rule
/// `demoContent()`'s note records; built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func menusDemoContent() -> some Element {
    menusRoot(header: menusHeader(), card: menusCard(), popover: menusPopover(), help: menusHelp(),
              pullDown: menusPullDown())
}

/// The demo's state: the last choice, the toggle, the popover and its field.
@MainActor
@Observable
public final class MenusDemoModel {
    /// What the status line shows.
    public var status = "Right-click the card, or press ⌘D."
    /// The context menu's and the Demo menu's toggle.
    public var pinned = false
    /// Whether the popover is shown.
    public var showPopover = false
    /// The popover's field.
    public var note = ""

    /// A fresh model.
    public init() {}
}

/// The one model the demo and its menu-bar commands share.
@MainActor public let menusDemoModel = MenusDemoModel()

/// The demo's toggle as a binding.
@MainActor
public func menusDemoPinned() -> Binding<Bool> {
    Binding(get: { menusDemoModel.pinned }, set: { menusDemoModel.pinned = $0 })
}

/// The root: the header, then the sections in a column.
@MainActor
private func menusRoot(header: some Element, card: some Element, popover: some Element, help: some Element,
                       pullDown: some Element) -> some Element {
    Column(gap: Pixels(20)) {
        header
        Row(gap: Pixels(32)) {
            card
            Column(gap: Pixels(20)) {
                popover
                pullDown
            }
            .alignItems(.flexStart)
        }
        .alignItems(.flexStart)
        help
        Text(menusDemoModel.status)
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}

@MainActor
private func menusHeader() -> some Element {
    Column(gap: Pixels(4)) {
        Text("Menus, popovers and tooltips").font(size: 22)
        Text("Right-click (or control-click) the card. Rest the pointer on a hint. Escape closes the popover.")
    }
    .alignItems(.flexStart)
}

/// The 200 × 100 card carrying the context menu.
@MainActor
private func menusCard() -> some Element {
    Box {
        Text(menusDemoModel.pinned ? "Card (pinned)" : "Card")
    }
    .frame(width: Pixels(200), height: Pixels(100))
    .background(.surfaceSecondary)
    .cornerRadius(Pixels(12))
    .contextMenu {
        Button("Copy") { menusDemoModel.status = "Chose Copy" }
        Button("Rename") { menusDemoModel.status = "Chose Rename" }
        Divider()
        Menu("Colour") {
            Button("Red") { menusDemoModel.status = "Chose Red" }
            Button("Green") { menusDemoModel.status = "Chose Green" }
            Button("Blue") { menusDemoModel.status = "Chose Blue" }
        }
        Toggle("Pinned", isOn: menusDemoPinned())
        Button("Delete") { menusDemoModel.status = "Chose Delete" }.disabled(true)
        Button("Duplicate") { menusDemoModel.status = "Chose Duplicate" }.keyboardShortcut("d")
    }
}

/// A button presenting a popover: a text, a field and a Close button.
@MainActor
private func menusPopover() -> some Element {
    Button("Show popover") { menusDemoModel.showPopover.toggle() }
        .popover(isPresented: Binding(get: { menusDemoModel.showPopover },
                                      set: { menusDemoModel.showPopover = $0 })) {
            Column(gap: Pixels(8)) {
                Text("A popover")
                TextField("A note", text: menusDemoModel.note) { menusDemoModel.note = $0 }
                    .frame(width: Pixels(200))
                    .background(.surfaceSecondary)
                Button("Close") { menusDemoModel.showPopover = false }
            }
            .alignItems(.flexStart)
        }
}

/// Three texts explaining themselves.
@MainActor
private func menusHelp() -> some Element {
    Row(gap: Pixels(24)) {
        Text("Hover me").help("A tooltip after one second")
        Text("And me").help("Hidden by a click, a key or the wheel")
        Text("Me too").help("A longer explanation that wraps once it passes three hundred points across, as tooltips do")
    }
}

/// A `Menu` pull-down.
@MainActor
private func menusPullDown() -> some Element {
    Menu("Actions") {
        Button("Archive") { menusDemoModel.status = "Chose Archive" }
        Button("Share") { menusDemoModel.status = "Chose Share" }
        Divider()
        Toggle("Pinned", isOn: menusDemoPinned())
    }
}
