import MetalUICore
import MetalUIScene

// A window's toolbar at the platform seam (rulings `MD-I`, `MD-J`; spec
// `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md` §2). Values:
// `MetalUI` evaluates every `.toolbar`/`.searchable` in a window's tree into one
// `PlatformToolbar` and hands it to `PlatformWindow.setToolbar(_:)`; the
// platform shows it natively (AppKit's `NSToolbar`) or answers `false` and the
// window draws it. A control's outcome comes back as a queued
// `InputEvent.toolbarAction` naming the item's `id`. No closure crosses the
// seam.

/// Where a toolbar item sits (ruling `MD-I` item 2; probe
/// `swiftui-toolbar.swift` `TB1`, `SR`).
public enum PlatformToolbarPlacement: Sendable, Equatable {
    /// Leading, before the title — AppKit's navigational items.
    case navigation
    /// Centred.
    case principal
    /// Trailing, in declaration order with `.automatic` items.
    case primaryAction
    /// Trailing, in declaration order.
    case automatic
    /// Centred, beside a principal item.
    case status
    /// The `.searchable` field: trailing, last.
    case search
}

/// How a toolbar picker shows its options.
public enum PlatformToolbarPickerStyle: Sendable, Equatable {
    /// A pop-up button.
    case menu
    /// A segmented control.
    case segmented
}

/// What a toolbar item shows (ruling `MD-J` item 1), with its current state.
///
/// **Equality compares an image by identity** (`===`, ruling `MD-U` item 1):
/// `ImageTexture` is a class without `Equatable`, and the window reuses one
/// texture per bitmap, so an unchanged toolbar compares equal and is not
/// re-sent.
public enum PlatformToolbarControl: Sendable {
    /// A button showing `title`, or `image` when there is one (`title` is then
    /// its accessibility label); answers `.press`.
    case button(title: String, image: ImageTexture?)
    /// A checkbox; answers `.toggle(_:)` with the new state.
    case toggle(title: String, isOn: Bool)
    /// A choice of `options` with `selected` (or none) chosen; answers
    /// `.select(_:)` with the chosen index.
    case picker(title: String, options: [String], selected: Int?, style: PlatformToolbarPickerStyle)
    /// An editable text field; answers `.text(_:)` on every edit.
    case textField(placeholder: String, text: String)
    /// The search field; answers `.text(_:)` on every edit.
    case search(prompt: String, text: String)
    /// A label; answers nothing.
    case label(text: String)
}

extension PlatformToolbarControl: Equatable {
    /// Equal when the case and every value match, an image by identity.
    public static func == (lhs: PlatformToolbarControl, rhs: PlatformToolbarControl) -> Bool {
        switch (lhs, rhs) {
        case let (.button(a, ai), .button(b, bi)): a == b && ai === bi
        case let (.toggle(a, ao), .toggle(b, bo)): a == b && ao == bo
        case let (.picker(a, ao, asel, ast), .picker(b, bo, bsel, bst)): a == b && ao == bo && asel == bsel && ast == bst
        case let (.textField(a, at), .textField(b, bt)): a == b && at == bt
        case let (.search(a, at), .search(b, bt)): a == b && at == bt
        case let (.label(a), .label(b)): a == b
        default: false
        }
    }
}

/// One toolbar item (ruling `MD-J` item 1).
public struct PlatformToolbarItem: Sendable, Equatable {
    /// Names the item in its `InputEvent.toolbarAction`; unique in its toolbar
    /// and stable while the declaration is (`MD-I` item 6).
    public var id: String
    /// Where it sits.
    public var placement: PlatformToolbarPlacement
    /// What it shows.
    public var control: PlatformToolbarControl
    /// Whether it accepts input — `false` under `.disabled(true)`.
    public var isEnabled: Bool
    /// Its tooltip (`.help(_:)`), or `nil`.
    public var help: String?

    /// An item `id` at `placement` showing `control`.
    public init(id: String, placement: PlatformToolbarPlacement, control: PlatformToolbarControl,
                isEnabled: Bool = true, help: String? = nil) {
        self.id = id
        self.placement = placement
        self.control = control
        self.isEnabled = isEnabled
        self.help = help
    }
}

/// A window's toolbar: its items in order — the main tree's `.toolbar` items in
/// build pre-order, then the `.searchable` fields (ruling `MD-I` items 4–5).
public struct PlatformToolbar: Sendable, Equatable {
    /// The items, in order.
    public var items: [PlatformToolbarItem]

    /// A toolbar of `items`.
    public init(items: [PlatformToolbarItem]) {
        self.items = items
    }
}

/// A toolbar control's outcome (ruling `MD-J` item 4), delivered as
/// `InputEvent.toolbarAction`.
public struct ToolbarActionEvent: Sendable, Equatable {
    /// What the control did.
    public enum Action: Sendable, Equatable {
        /// A button was pressed.
        case press
        /// A checkbox turned on (`true`) or off.
        case toggle(Bool)
        /// A picker's option at this index was chosen.
        case select(Int)
        /// A text or search field now reads this.
        case text(String)
    }

    /// The `PlatformToolbarItem.id` of the item.
    public var item: String
    /// What its control did.
    public var action: Action

    /// The outcome `action` of the item `item`.
    public init(item: String, action: Action) {
        self.item = item
        self.action = action
    }
}
