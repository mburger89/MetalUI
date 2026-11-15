import MetalUICore
import MetalUIPlatform

// `contextMenu(forSelectionType:menu:primaryAction:)` (outline lane 6, ruling `OG-N`; probe arms `P-M1`..`P-M4`,
// `P-C1` in `docs/probes/swiftui-outline.swift`). SwiftUI's modifier applies to the `List` (or `Table`) it sits on or
// above and hands its closures the selection-typed identifiers the menu or the action is for; MetalUI reaches the list
// through the contextual attachment (`MN-Q`) on a `StyledElement` receiver, and through the environment on proposal
// content, and each list form (data and content) reads it in its own layout and builds the rows' regions.

/// A `contextMenu(forSelectionType:)` modifier's payload, type-erased over its identifier type: carried on a
/// ``ContextualAttachment`` (a list's own) or in the environment (over proposal content), read by a `List` in layout.
@MainActor
struct SelectionContextMenu {
    /// `I`, the identifier type the closures are written over. A list whose row identifier is another type ignores the
    /// modifier (SwiftUI: inert, `OG-N`).
    let itemType: Any.Type
    let menu: @MainActor (Set<AnyHashable>) -> MenuItems
    let primaryAction: (@MainActor (Set<AnyHashable>) -> Void)?

    init<I: Hashable, M: MenuContent>(_ type: I.Type, menu: @escaping @MainActor (Set<I>) -> M,
                                      primaryAction: (@MainActor (Set<I>) -> Void)?) {
        itemType = type
        self.menu = { (items: Set<AnyHashable>) -> MenuItems in
            let typed: Set<I> = Set(items.compactMap { $0.base as? I })
            return MenuItems([menu(typed)])
        }
        if let primaryAction {
            self.primaryAction = { (items: Set<AnyHashable>) in
                let typed: Set<I> = Set(items.compactMap { $0.base as? I })
                primaryAction(typed)
            }
        } else {
            self.primaryAction = nil
        }
    }

    /// Whether a list whose rows are identified by `ID` takes this modifier.
    func applies<ID>(to _: ID.Type) -> Bool { itemType == ID.self }

    /// The attachment a list's own region carries: the menu over empty space gets `[]` (`P-M2`: the closure still
    /// builds a menu), keeping `existing`'s help.
    func listAttachment(over existing: ContextualAttachment?) -> ContextualAttachment {
        let menu = self.menu
        return ContextualAttachment(locatedMenu: { _ in menu([]) }, help: existing?.help,
                                    helpProvider: existing?.helpProvider, selection: existing?.selection)
    }

    /// The attachment a row's region carries: the menu for the row's identifier when it is not selected, for the whole
    /// selection when it is (`P-M1`, `P-M1b`). The selection is read at each open and is not changed by it.
    func rowAttachment<ID: Hashable>(row: ID, selected: @escaping @MainActor () -> Set<ID>) -> ContextualAttachment {
        let menu = self.menu
        return ContextualAttachment(locatedMenu: { _ in
            let current = selected()
            return menu(Set((current.contains(row) ? current : [row]).map { AnyHashable($0) }))
        }, help: nil)
    }

    /// A row's click handler with the primary action after it: the second click of a double-click runs
    /// `primaryAction({row})` once the row's own selection click has run (`P-M3`, `P-M3b`: it selects, then acts, and a
    /// group does not toggle). `base` is the row's selection click, `nil` in a list with no selection. With no
    /// primary action the handler is `base`, unchanged.
    func clickHandler<ID: Hashable>(wrapping base: (@MainActor () -> Void)?, row: ID) -> (@MainActor () -> Void)? {
        guard let primaryAction else { return base }
        return {
            base?()
            if ClickDispatch.clickCount == 2 { primaryAction([AnyHashable(row)]) }
        }
    }

    /// Return on the focused list: `primaryAction(selection)` (`P-M4`, `P-M4b`: a group's too, without toggling).
    /// Nothing to act on with an empty selection, and the key is then not consumed (`OG-N`).
    func returnKey(_ event: KeyEvent, selection: Set<AnyHashable>) -> Bool {
        guard let primaryAction, ControlKeys.isPrimaryActionKey(event), !selection.isEmpty else { return false }
        primaryAction(selection)
        return true
    }
}

extension ListSelection {
    /// The selected ids as a set: `[]` for no selection or an empty one. Reads the bindings.
    @MainActor
    func currentSet() -> Set<ID> {
        switch self {
        case .none: return []
        case .single(let binding): return binding.wrappedValue.map { [$0] } ?? []
        case .multi(let binding): return binding.wrappedValue
        }
    }
}

extension ControlKeys {
    /// A focused `List`'s primary-action key (`OG-N`, `P-M4`): Return, no modifiers.
    static func isPrimaryActionKey(_ event: KeyEvent) -> Bool {
        event.modifiers.isEmpty && event.charactersIgnoringModifiers == returnKey
    }
}

struct SelectionContextMenuKey: EnvironmentKey {
    static var defaultValue: SelectionContextMenu? { nil }
}

extension EnvironmentValues {
    /// The `contextMenu(forSelectionType:)` modifier above, for a `List` below.
    var selectionContextMenu: SelectionContextMenu? {
        get { self[SelectionContextMenuKey.self] }
        set { setCustom(SelectionContextMenuKey.self, newValue, reading: .uncomparable) }
    }
}

extension StyledElement {
    /// Attaches a menu and a primary action to the rows of a list — SwiftUI's
    /// `contextMenu(forSelectionType:menu:primaryAction:)` (outline lane 6, ruling `OG-N`; probe arms `P-M1`..`P-M4`).
    ///
    /// Put it on a `List` (the data form or the content and outline forms). **A secondary press on a row** opens
    /// `menu` with the row's identifier, or with the whole selection when the row is part of it, and does not change the
    /// selection; **on the list's empty space** `menu` gets `[]` and still builds a menu. **Double-clicking a row** selects
    /// it with the first click and runs `primaryAction` with `[row]` on the second; a group row does not toggle. **Return**
    /// on the focused list runs `primaryAction` with the selection (not with an empty one). A single click never runs
    /// it, and with no `primaryAction` a double-click does nothing more than a single one. `menu` runs at each open.
    /// A list whose row identifier type is not `I` ignores the modifier, as does an element that is not a list. A
    /// non-list receiver is inert: wrap proposal content to reach a list below it.
    public func contextMenu<I: Hashable, M: MenuContent>(
        forSelectionType itemType: I.Type = I.self,
        @MenuContentBuilder menu: @escaping @MainActor (Set<I>) -> M,
        primaryAction: (@MainActor (Set<I>) -> Void)? = nil) -> Self {
        var copy = self
        let spec = SelectionContextMenu(itemType, menu: menu, primaryAction: primaryAction)
        let existing = handlers.contextual
        copy.handlers.contextual = ContextualAttachment(locatedMenu: nil, help: existing?.help,
                                                        helpProvider: existing?.helpProvider, selection: spec)
        return copy
    }
}

extension ProposalElementGroup {
    /// `StyledElement.contextMenu(forSelectionType:menu:primaryAction:)` over proposal content: every `List` below it
    /// takes the menu and the action (the nearest modifier wins), as SwiftUI's modifier reaches the lists in its
    /// subtree. Layout- and identity-transparent, as an environment scope is.
    public func contextMenu<I: Hashable, M: MenuContent>(
        forSelectionType itemType: I.Type = I.self,
        @MenuContentBuilder menu: @escaping @MainActor (Set<I>) -> M,
        primaryAction: (@MainActor (Set<I>) -> Void)? = nil) -> EnvironmentScope<Self> {
        let spec = SelectionContextMenu(itemType, menu: menu, primaryAction: primaryAction)
        return EnvironmentScope(content: self, write: .transform { $0.selectionContextMenu = spec })
    }
}
