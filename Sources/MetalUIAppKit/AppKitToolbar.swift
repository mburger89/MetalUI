#if os(macOS)
import AppKit
import MetalUICore
import MetalUIScene
import MetalUIPlatform

// The AppKit toolbar (rulings `MD-J` item 3, `MD-U` item 3; spec
// `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md` §3.3). A real
// `NSToolbar` of native controls — what SwiftUI's `.toolbar` produces on macOS
// (probe `swiftui-toolbar.swift` `TB1`): style `.automatic`, icon-only, no
// customization; navigation items `isNavigational`; principal and status items
// centred, then a flexible space, then the primary/automatic items in order;
// `.searchable`'s `NSSearchToolbarItem` after a second flexible space, last
// (`SR`). A changed toolbar with the same ids and kinds is updated in place —
// the same `NSToolbar`, the same item objects (`UP`); otherwise a new toolbar
// is built. Each control's outcome is delivered through `onInput` as
// `.toolbarAction`, from the control's own action — never inside `setToolbar`.
//
// **MetalUI's focus is left alone** (`MD-U` item 3): a toolbar field taking
// the window's first responder from the host view moves no MetalUI focus; the
// focused element simply receives no key until the host view is first
// responder again.

@MainActor
final class AppKitToolbarController: NSObject, NSToolbarDelegate, NSTextFieldDelegate, NSSearchFieldDelegate {
    /// Where outcomes go — the window's `onInput`.
    var deliver: @MainActor (InputEvent) -> Void

    /// The toolbar on screen and its description, or `nil`.
    private(set) var toolbar: NSToolbar?
    private var current: PlatformToolbar?
    /// The items vended for `toolbar`, by item id.
    private var items: [String: NSToolbarItem] = [:]
    /// Each control's item id, by control identity — how an action finds its
    /// item.
    private var itemIDs: [ObjectIdentifier: String] = [:]
    /// Unique `NSToolbar` identifiers: two toolbars sharing one would mirror
    /// each other's configuration across windows.
    private static var built = 0

    init(deliver: @escaping @MainActor (InputEvent) -> Void) {
        self.deliver = deliver
    }

    /// Shows `description` in `window` (`MD-J` item 3): in place when the ids
    /// and kinds match the toolbar shown, else a new `NSToolbar`; `nil`
    /// removes it.
    func apply(_ description: PlatformToolbar?, to window: NSWindow) {
        guard let description else {
            window.toolbar = nil
            toolbar = nil
            current = nil
            items = [:]
            itemIDs = [:]
            return
        }
        if let toolbar, let current, Self.shape(of: current) == Self.shape(of: description),
           window.toolbar === toolbar {
            self.current = description
            for item in description.items { if let vended = items[item.id] { update(vended, with: item) } }
            return
        }
        Self.built += 1
        let toolbar = NSToolbar(identifier: "MetalUI.toolbar.\(Self.built)")
        current = description
        items = [:]
        itemIDs = [:]
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = Set(description.items
            .filter { $0.placement == .principal || $0.placement == .status }
            .map { NSToolbarItem.Identifier($0.id) })
        self.toolbar = toolbar
        window.toolbarStyle = .automatic
        window.toolbar = toolbar
    }

    /// The ids and control kinds — what an in-place update must keep.
    private static func shape(of toolbar: PlatformToolbar) -> [String] {
        toolbar.items.map { item in
            let kind: String = switch item.control {
            case .button(_, let image): image == nil ? "button" : "image"
            case .toggle: "toggle"
            case .picker(_, let options, _, let style): "picker-\(style)-\(options.count)"
            case .textField: "text"
            case .search: "search"
            case .label: "label"
            }
            return "\(item.id)|\(item.placement)|\(kind)"
        }
    }

    /// `TB1`'s order: centred items, a flexible space, the leading and
    /// trailing items in declaration order (AppKit moves navigational ones
    /// leading), then — when there is one — a second flexible space and the
    /// search field (`SR`).
    private func identifiers() -> [NSToolbarItem.Identifier] {
        guard let current else { return [] }
        let centred = current.items.filter { $0.placement == .principal || $0.placement == .status }
        let others = current.items.filter {
            $0.placement == .navigation || $0.placement == .primaryAction || $0.placement == .automatic
        }
        let searches = current.items.filter { $0.placement == .search }
        var ids = centred.map { NSToolbarItem.Identifier($0.id) }
        ids.append(.flexibleSpace)
        ids += others.map { NSToolbarItem.Identifier($0.id) }
        if !searches.isEmpty {
            ids.append(.flexibleSpace)
            ids += searches.map { NSToolbarItem.Identifier($0.id) }
        }
        return ids
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers() }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers() }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let description = current?.items.first(where: { $0.id == itemIdentifier.rawValue }) else { return nil }
        if let existing = items[description.id] { return existing }
        let item = makeItem(description)
        items[description.id] = item
        update(item, with: description)
        return item
    }

    // MARK: Items

    private func makeItem(_ description: PlatformToolbarItem) -> NSToolbarItem {
        let identifier = NSToolbarItem.Identifier(description.id)
        let control: NSControl
        switch description.control {
        case .search:
            let item = NSSearchToolbarItem(itemIdentifier: identifier)
            item.searchField.delegate = self
            itemIDs[ObjectIdentifier(item.searchField)] = description.id
            return item
        case .button:
            let button = NSButton(title: "", target: self, action: #selector(pressed(_:)))
            button.bezelStyle = .toolbar
            control = button
        case .toggle:
            control = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggled(_:)))
        case .picker(_, _, _, .segmented):
            control = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: self,
                                         action: #selector(selected(_:)))
        case .picker(_, _, _, .menu):
            let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
            popUp.target = self
            popUp.action = #selector(selected(_:))
            control = popUp
        case .textField:
            let field = NSTextField(string: "")
            field.bezelStyle = .roundedBezel
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 120).isActive = true   // `TB1`'s 120 × 24
            control = field
        case .label:
            control = NSTextField(labelWithString: "")
        }
        itemIDs[ObjectIdentifier(control)] = description.id
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = control
        item.isNavigational = description.placement == .navigation
        return item
    }

    /// Brings `item` to `description`'s state. A field's text is written only
    /// when it differs from what the field shows, so an edit's caret survives
    /// its own echo (`MD-J` item 4).
    private func update(_ item: NSToolbarItem, with description: PlatformToolbarItem) {
        item.toolTip = description.help
        item.isEnabled = description.isEnabled
        switch description.control {
        case .button(let title, let image):
            item.label = title
            guard let button = item.view as? NSButton else { return }
            if let image {
                button.title = ""
                button.image = Self.image(from: image)
                button.imagePosition = .imageOnly
                button.setAccessibilityLabel(title)
            } else {
                button.image = nil
                button.title = title
            }
            button.isEnabled = description.isEnabled
        case .toggle(let title, let isOn):
            item.label = title
            guard let button = item.view as? NSButton else { return }
            button.title = title
            button.state = isOn ? .on : .off
            button.isEnabled = description.isEnabled
        case .picker(let title, let options, let selected, _):
            item.label = title
            if let segmented = item.view as? NSSegmentedControl {
                segmented.segmentCount = options.count
                for (index, option) in options.enumerated() { segmented.setLabel(option, forSegment: index) }
                segmented.selectedSegment = selected ?? -1
                segmented.isEnabled = description.isEnabled
            } else if let popUp = item.view as? NSPopUpButton {
                if popUp.itemTitles != options {
                    popUp.removeAllItems()
                    popUp.addItems(withTitles: options)
                }
                popUp.selectItem(at: selected ?? -1)
                popUp.isEnabled = description.isEnabled
            }
        case .textField(let placeholder, let text):
            item.label = placeholder
            guard let field = item.view as? NSTextField else { return }
            field.placeholderString = placeholder
            if field.stringValue != text { field.stringValue = text }
            field.isEnabled = description.isEnabled
        case .search(let prompt, let text):
            item.label = prompt
            guard let search = item as? NSSearchToolbarItem else { return }
            search.searchField.placeholderString = prompt
            if search.searchField.stringValue != text { search.searchField.stringValue = text }
            search.searchField.isEnabled = description.isEnabled
        case .label(let text):
            item.label = text
            (item.view as? NSTextField)?.stringValue = text
        }
    }

    /// An `NSImage` over the texture's premultiplied bytes as stored (`AI-E`),
    /// sized in points at its pixel size, fitted down to 18 points.
    private static func image(from texture: ImageTexture) -> NSImage? {
        guard let image = AppKitIcon.image(from: [texture]) else { return nil }
        let side = CGFloat(max(texture.width, texture.height))
        if side > 18 {
            let scale = 18 / side
            image.size = NSSize(width: CGFloat(texture.width) * scale, height: CGFloat(texture.height) * scale)
        }
        return image
    }

    // MARK: Actions

    private func send(_ sender: AnyObject, _ action: ToolbarActionEvent.Action) {
        guard let id = itemIDs[ObjectIdentifier(sender)] else { return }
        deliver(.toolbarAction(ToolbarActionEvent(item: id, action: action)))
    }

    @objc private func pressed(_ sender: NSButton) { send(sender, .press) }

    @objc private func toggled(_ sender: NSButton) { send(sender, .toggle(sender.state == .on)) }

    @objc private func selected(_ sender: NSControl) {
        if let segmented = sender as? NSSegmentedControl {
            send(sender, .select(segmented.selectedSegment))
        } else if let popUp = sender as? NSPopUpButton {
            send(sender, .select(popUp.indexOfSelectedItem))
        }
    }

    /// Every edit of a text or search field (`MD-J` item 4: controlled, like
    /// `TextField`).
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        send(field, .text(field.stringValue))
    }
}
#endif
