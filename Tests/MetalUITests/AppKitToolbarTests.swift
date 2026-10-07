import Testing
import Foundation
import Metal
import AppKit
import Observation
import MetalUICore
import MetalUIScene
import MetalUIRender
@testable import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI

// Port gaps (medium), lane 2 — the AppKit toolbar: tests 3.11, 3.12 and 3.18
// (rulings `MD-J` items 3–4, `MD-N`, `MD-U` item 3; spec §4.3). A real
// `AppKitPlatform` window: `setToolbar(_:)` builds a real `NSToolbar` of native
// controls. Nothing here needs the window on screen — an `NSWindow`'s toolbar
// items and their controls can be inspected and clicked while it is not key
// (`MD-N`). SwiftUI's side: `docs/probes/swiftui-toolbar.swift` (`TB1`, `UP`,
// `SR`). Red before: the file does not compile at `34f68c3`.

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private final class ConstantSignal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(false) }
}

@MainActor private final class EventLog {
    var actions: [ToolbarActionEvent] = []
}

/// A real 400 × 200 AppKit window whose `onInput` records toolbar actions.
@MainActor private func toolbarWindow() throws -> (AppKitPlatform, AppKitWindow, NSWindow, EventLog) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let platformWindow = try platform.openWindow(title: "Toolbar \(UUID().uuidString)",
                                                 size: Size(width: px(400), height: px(200)))
    let appKit = try #require(platformWindow as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    let log = EventLog()
    appKit.onInput = { event in
        if case .toolbarAction(let action) = event { log.actions.append(action) }
        return true
    }
    return (platform, appKit, nsWindow, log)
}

@MainActor private let imageTexture = ImageTexture(width: 2, height: 2, premultipliedRGBA: [UInt8](repeating: 255, count: 16))

/// One item of every kind, in `TB1`'s placements.
private func sample(isOn: Bool = false, selected: Int = 0, text: String = "") -> PlatformToolbar {
    PlatformToolbar(items: [
        PlatformToolbarItem(id: "nav", placement: .navigation, control: .button(title: "Back", image: nil)),
        PlatformToolbarItem(id: "mode", placement: .principal,
                            control: .picker(title: "Mode", options: ["A", "B"], selected: selected, style: .segmented)),
        PlatformToolbarItem(id: "share", placement: .primaryAction,
                            control: .button(title: "Share", image: nil), help: "Share it"),
        PlatformToolbarItem(id: "adv", placement: .automatic, control: .toggle(title: "Advanced", isOn: isOn)),
        PlatformToolbarItem(id: "sort", placement: .automatic,
                            control: .picker(title: "Sort", options: ["Name", "Date"], selected: 1, style: .menu)),
        PlatformToolbarItem(id: "filter", placement: .automatic, control: .textField(placeholder: "Filter", text: "")),
        PlatformToolbarItem(id: "status", placement: .status, control: .label(text: "Ready")),
        PlatformToolbarItem(id: "search", placement: .search, control: .search(prompt: "Search", text: text)),
    ])
}

@MainActor private func item(_ toolbar: NSToolbar, _ id: String) throws -> NSToolbarItem {
    try #require(toolbar.items.first { $0.itemIdentifier.rawValue == id }, "no item \(id)")
}

// MARK: - 3.11

/// **3.11** (`MD-J` item 3; probe `TB1`, `UP`, `SR`). `setToolbar` answers
/// `true` and gives the `NSWindow` an `NSToolbar` — style `.automatic`,
/// icon-only, not customizable — of native controls: a toolbar-bezel button, a
/// segmented control, a pop-up button, a checkbox, a rounded text field, a
/// label, an `NSSearchToolbarItem`; navigation items `isNavigational`;
/// principal and status centred; `TB1`'s order. A changed state keeps the same
/// `NSToolbar` and the same item objects; a changed id list rebuilds; `nil`
/// removes it. The content size does not change (the window grows, `TB1`).
/// Mutation **M3.11**: rebuild on every call (the same-object arm).
@MainActor
@Test func theAppKitToolbarBuildsNativeItemsAndUpdatesThemInPlace() throws {
    let (platform, appKit, nsWindow, _) = try toolbarWindow()
    defer { nsWindow.close(); withExtendedLifetime(platform) {} }
    let contentBefore = appKit.contentSize
    #expect(appKit.setToolbar(sample()) == true)
    let toolbar = try #require(nsWindow.toolbar, "no NSToolbar")
    #expect(nsWindow.toolbarStyle == .automatic)
    #expect(toolbar.displayMode == .iconOnly)
    #expect(toolbar.allowsUserCustomization == false)
    #expect(toolbar.items.map(\.itemIdentifier.rawValue) == [
        "mode", "status", NSToolbarItem.Identifier.flexibleSpace.rawValue, "nav", "share", "adv", "sort", "filter",
        NSToolbarItem.Identifier.flexibleSpace.rawValue, "search",
    ], "TB1/SR order: \(toolbar.items.map(\.itemIdentifier.rawValue))")
    #expect(toolbar.centeredItemIdentifiers == Set(["mode", "status"].map(NSToolbarItem.Identifier.init)))
    #expect(try item(toolbar, "nav").isNavigational)
    #expect(try !item(toolbar, "share").isNavigational)

    let back = try #require(try item(toolbar, "nav").view as? NSButton)
    #expect(back.title == "Back" && back.bezelStyle == .toolbar)
    let segmented = try #require(try item(toolbar, "mode").view as? NSSegmentedControl)
    #expect(segmented.segmentCount == 2 && segmented.label(forSegment: 1) == "B" && segmented.selectedSegment == 0)
    #expect(try item(toolbar, "share").toolTip == "Share it")
    let checkbox = try #require(try item(toolbar, "adv").view as? NSButton)
    #expect(checkbox.title == "Advanced" && checkbox.state == .off)
    let popUp = try #require(try item(toolbar, "sort").view as? NSPopUpButton)
    #expect(popUp.itemTitles == ["Name", "Date"] && popUp.indexOfSelectedItem == 1)
    let field = try #require(try item(toolbar, "filter").view as? NSTextField)
    #expect(field.isEditable && field.placeholderString == "Filter" && field.bezelStyle == .roundedBezel)
    let label = try #require(try item(toolbar, "status").view as? NSTextField)
    #expect(!label.isEditable && label.stringValue == "Ready")
    let search = try #require(try item(toolbar, "search") as? NSSearchToolbarItem)
    #expect(search.searchField.placeholderString == "Search")
    #expect(appKit.contentSize == contentBefore, "the content keeps its size")

    // In place (`UP`).
    let objects = toolbar.items.map(ObjectIdentifier.init)
    let checkboxItem = try item(toolbar, "adv")
    #expect(appKit.setToolbar(sample(isOn: true, selected: 1, text: "q")) == true)
    #expect(nsWindow.toolbar === toolbar, "the same NSToolbar")
    #expect(toolbar.items.map(ObjectIdentifier.init) == objects, "the same item objects")
    #expect(checkbox.state == .on && segmented.selectedSegment == 1 && search.searchField.stringValue == "q")

    // A changed id list rebuilds.
    var fewer = sample()
    fewer.items.removeFirst()
    #expect(appKit.setToolbar(fewer) == true)
    let rebuilt = try #require(nsWindow.toolbar)
    #expect(rebuilt.items.contains { $0.itemIdentifier.rawValue == "nav" } == false)
    #expect(rebuilt !== toolbar, "a changed id list builds a new NSToolbar")
    #expect(try item(rebuilt, "adv") !== checkboxItem, "a rebuild makes new items")

    _ = appKit.setToolbar(nil)
    #expect(nsWindow.toolbar == nil, "nil removes the toolbar")
}

/// An image button carries an `NSImage` of the texture's pixel size.
@MainActor
@Test func anAppKitToolbarImageButtonShowsTheTexture() throws {
    let (platform, appKit, nsWindow, _) = try toolbarWindow()
    defer { nsWindow.close(); withExtendedLifetime(platform) {} }
    _ = appKit.setToolbar(PlatformToolbar(items: [
        PlatformToolbarItem(id: "img", placement: .primaryAction, control: .button(title: "Pic", image: imageTexture)),
    ]))
    let button = try #require(try item(try #require(nsWindow.toolbar), "img").view as? NSButton)
    let image = try #require(button.image, "no image")
    #expect(image.representations.first?.pixelsWide == 2 && image.representations.first?.pixelsHigh == 2)
    #expect(button.imagePosition == .imageOnly)
}

// MARK: - 3.12

/// **3.12** (`MD-J` item 4). Each native control sends its action as an
/// `InputEvent.toolbarAction`: the button `.press`, the segmented control
/// `.select(1)`, the pop-up `.select(0)`, the checkbox `.toggle(true)`, a text
/// field and the search field `.text` on an edit. A disabled item's control is
/// disabled. Mutation **M3.12**: the checkbox sends `.press`.
@MainActor
@Test func anAppKitToolbarControlSendsItsActionAsAnInputEvent() throws {
    let (platform, appKit, nsWindow, log) = try toolbarWindow()
    defer { nsWindow.close(); withExtendedLifetime(platform) {} }
    _ = appKit.setToolbar(sample())
    let toolbar = try #require(nsWindow.toolbar)

    try #require(try item(toolbar, "nav").view as? NSButton).performClick(nil)
    let segmented = try #require(try item(toolbar, "mode").view as? NSSegmentedControl)
    segmented.selectedSegment = 1
    segmented.sendAction(segmented.action, to: segmented.target)
    let popUp = try #require(try item(toolbar, "sort").view as? NSPopUpButton)
    popUp.selectItem(at: 0)
    popUp.sendAction(popUp.action, to: popUp.target)
    try #require(try item(toolbar, "adv").view as? NSButton).performClick(nil)

    let field = try #require(try item(toolbar, "filter").view as? NSTextField)
    #expect(nsWindow.makeFirstResponder(field))
    try #require(field.currentEditor() as? NSTextView).insertText("f", replacementRange: NSRange(location: 0, length: 0))
    let search = try #require(try item(toolbar, "search") as? NSSearchToolbarItem)
    #expect(nsWindow.makeFirstResponder(search.searchField))
    try #require(search.searchField.currentEditor() as? NSTextView)
        .insertText("s", replacementRange: NSRange(location: 0, length: 0))

    #expect(log.actions == [
        ToolbarActionEvent(item: "nav", action: .press),
        ToolbarActionEvent(item: "mode", action: .select(1)),
        ToolbarActionEvent(item: "sort", action: .select(0)),
        ToolbarActionEvent(item: "adv", action: .toggle(true)),
        ToolbarActionEvent(item: "filter", action: .text("f")),
        ToolbarActionEvent(item: "search", action: .text("s")),
    ], "\(log.actions)")

    var disabled = sample()
    disabled.items[0].isEnabled = false
    _ = appKit.setToolbar(disabled)
    #expect(try #require(try item(try #require(nsWindow.toolbar), "nav").view as? NSButton).isEnabled == false)
}

// MARK: - 3.18

@Observable @MainActor private final class FocusModel {
    var name = ""
    var search = ""
}

/// **3.18** (`MD-U` item 3). With a MetalUI `TextField` focused, the toolbar's
/// search field taking the window's first responder leaves MetalUI's focus
/// where it was; typing there reaches the search item's binding through
/// `.text`, never the MetalUI field. Mutation **M3.18**: MetalUI focus cleared
/// when a native toolbar field edits.
@MainActor
@Test func aNativeToolbarFieldTakingFirstResponderLeavesMetalUIFocusAlone() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let platformWindow = try platform.openWindow(title: "Toolbar focus \(UUID().uuidString)",
                                                 size: Size(width: px(400), height: px(200)))
    let appKit = try #require(platformWindow as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    defer { nsWindow.close(); withExtendedLifetime(platform) {} }
    let m = FocusModel()
    let window = Window(platformWindow: platformWindow, startsDisplayLink: false) {
        Column {
            TextField("Name", text: Binding(get: { m.name }, set: { m.name = $0 }))
                .searchable(text: Binding(get: { m.search }, set: { m.search = $0 }))
        }
    }
    window.drawFrameIfNeeded()
    _ = appKit.onInput?(.keyDown(KeyEvent(charactersIgnoringModifiers: "\t", characters: "\t", timestamp: 1)))
    window.drawFrameIfNeeded()
    let focused = try #require(window.focusedElement, "Tab focuses the MetalUI field")

    let search = try #require(nsWindow.toolbar?.items.first { $0 is NSSearchToolbarItem } as? NSSearchToolbarItem)
    #expect(nsWindow.makeFirstResponder(search.searchField))
    try #require(search.searchField.currentEditor() as? NSTextView)
        .insertText("q", replacementRange: NSRange(location: 0, length: 0))
    window.drawFrameIfNeeded()

    #expect(m.search == "q", "the edit reached the search binding: \(m.search)")
    #expect(m.name == "", "the MetalUI field received nothing: \(m.name)")
    #expect(window.focusedElement == focused, "MetalUI focus unchanged")
}
