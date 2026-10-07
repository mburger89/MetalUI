import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene

// Port gaps (medium), lane 2 — the window toolbar (rulings `MD-I`, `MD-J`,
// `MD-S`, `MD-U` items 1–2; spec
// `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md` §2, §3.3).
// SwiftUI's side: `docs/probes/swiftui-toolbar.swift` (`TB1`, `UP`, `SR`) and
// `docs/probes/swiftui-toolbar-nested.swift` (`NT1`, `NT2`, `IF0`/`IF1`, `PO`).
//
// A toolbar's items are data, not views (`MN-D`'s shape): `.toolbar { … }`
// evaluates a closed `ToolbarContent` into `ToolbarEntry`s in layout, through
// one transparent `ToolbarScope` (`LifecycleScope`'s shape, `LC-B`); the frame
// collects them window-wide in build pre-order, the main tree only; `Window`
// numbers them into one `PlatformToolbar` after the build and sends it to
// `PlatformWindow.setToolbar(_:)` when it changed. A native control's outcome
// returns as `InputEvent.toolbarAction` and runs under `StateDispatch`.

// MARK: - Placement

/// Where a toolbar item sits — SwiftUI's `ToolbarItemPlacement`, the five
/// placements the probe placed (ruling `MD-I` item 2; `TB1`).
public struct ToolbarItemPlacement: Equatable, Sendable {
    let kind: PlatformToolbarPlacement

    /// The platform's choice: trailing, in declaration order.
    public static let automatic = ToolbarItemPlacement(kind: .automatic)
    /// Leading — AppKit's navigational items.
    public static let navigation = ToolbarItemPlacement(kind: .navigation)
    /// Centred.
    public static let principal = ToolbarItemPlacement(kind: .principal)
    /// Trailing, with `.automatic` items, in declaration order.
    public static let primaryAction = ToolbarItemPlacement(kind: .primaryAction)
    /// Centred beside a principal item — a status label's usual place.
    public static let status = ToolbarItemPlacement(kind: .status)

    /// The placement's name in a generated item id (`MD-I` item 6).
    var idPrefix: String {
        switch kind {
        case .automatic: "automatic"
        case .navigation: "navigation"
        case .principal: "principal"
        case .primaryAction: "primaryAction"
        case .status: "status"
        case .search: "search"
        }
    }
}

// MARK: - Item content (closed)

/// One evaluated toolbar control (`MD-I` item 3): what the platform shows and
/// how its outcome runs.
struct ToolbarControlNode {
    /// What the platform shows, with the control's current state.
    var control: PlatformToolbarControl
    var isEnabled: Bool
    var help: String?
    /// Runs an outcome; answers `false` for an action of the wrong kind (a
    /// `.press` sent to a checkbox), which runs nothing. `nil`: a label.
    var run: (@MainActor (ToolbarActionEvent.Action) -> Bool)?
}

/// What a toolbar item is evaluated in: the scope's `isEnabled`, and-ed with
/// any `.disabled(_:)` on the item. SPI, with an internal initialiser.
@_spi(ToolbarInternals) public struct _ToolbarItemContext {
    var isEnabled: Bool
    init(isEnabled: Bool) { self.isEnabled = isEnabled }
}

/// What a `ToolbarItemContent` evaluates to. SPI, with an internal
/// initialiser, so only this module can make one (`MD-I` item 3).
@_spi(ToolbarInternals) public struct _ToolbarControls {
    let nodes: [ToolbarControlNode]
    init(_ nodes: [ToolbarControlNode]) { self.nodes = nodes }
}

/// A control a toolbar item can hold: `Button` with a `Text` or an `Image`
/// label, `Toggle` with a `Text` label, `Picker` (`.menu` → a pop-up, every
/// other style → segmented), `TextField`, `Text` (a label), any of them under
/// `.disabled(_:)` or with `.help(_:)` — and `if`/`switch`/`for` through
/// `@ToolbarItemContentBuilder` (ruling `MD-I` item 3).
///
/// **Closed**: its one requirement is SPI, so a type outside MetalUI cannot
/// conform (guard `onlyTheClosedSetIsToolbarContent`) — a control the platform
/// cannot show natively cannot be declared. SwiftUI takes any view
/// (divergence 135).
public protocol ToolbarItemContent {
    /// The controls this content evaluates to. SPI: see the protocol's doc.
    @_spi(ToolbarInternals) @MainActor func _toolbarControls(in context: _ToolbarItemContext) -> _ToolbarControls
}

/// What a `@ToolbarItemContentBuilder` block builds: its controls, in order.
public struct ToolbarItemControls: ToolbarItemContent {
    let children: [any ToolbarItemContent]

    init(_ children: [any ToolbarItemContent]) { self.children = children }

    /// This content's controls. SPI: see `ToolbarItemContent`.
    @_spi(ToolbarInternals) public func _toolbarControls(in context: _ToolbarItemContext) -> _ToolbarControls {
        _ToolbarControls(children.flatMap { $0._toolbarControls(in: context).nodes })
    }
}

/// The result builder for a toolbar item's controls (ruling `MD-I` item 3): a
/// block, `if`, `if`/`else`, `switch` and `for`.
@resultBuilder
public enum ToolbarItemContentBuilder {
    /// One control.
    public static func buildExpression<C: ToolbarItemContent>(_ content: C) -> ToolbarItemControls {
        ToolbarItemControls([content])
    }
    /// A block of controls, in order.
    public static func buildBlock(_ items: ToolbarItemControls...) -> ToolbarItemControls { ToolbarItemControls(items) }
    /// An `if` with no `else`: its controls, or none.
    public static func buildOptional(_ items: ToolbarItemControls?) -> ToolbarItemControls {
        items ?? ToolbarItemControls([])
    }
    /// The first branch of an `if`/`else` or `switch`.
    public static func buildEither(first items: ToolbarItemControls) -> ToolbarItemControls { items }
    /// The second branch of an `if`/`else` or `switch`.
    public static func buildEither(second items: ToolbarItemControls) -> ToolbarItemControls { items }
    /// A `for` loop: every iteration's controls, in order.
    public static func buildArray(_ items: [ToolbarItemControls]) -> ToolbarItemControls { ToolbarItemControls(items) }
}

/// A label a toolbar button can show (ruling `MD-I` item 3): `Text` (its
/// string as the title) or `Image` (its pixels, its accessibility label — or
/// `""` for a decorative image — as the title). **Closed**: its requirement is
/// SPI, as `ToolbarItemContent`'s.
public protocol ToolbarButtonLabel: ElementGroup {
    /// The title and image this label shows. SPI: see the protocol's doc.
    @_spi(ToolbarInternals) @MainActor func _toolbarLabel() -> (title: String, image: ImageTexture?)
}

extension Text: ToolbarButtonLabel {
    /// The string, no image. SPI: see `ToolbarButtonLabel`.
    @_spi(ToolbarInternals) public func _toolbarLabel() -> (title: String, image: ImageTexture?) { (string, nil) }
}

/// The texture is the bitmap's own, one per bitmap, so an unchanged toolbar
/// compares equal and is not re-sent (`MD-U` item 1).
extension Image: ToolbarButtonLabel {
    /// The accessibility label (or `""`) and the bitmap's texture. SPI: see
    /// `ToolbarButtonLabel`.
    @_spi(ToolbarInternals) public func _toolbarLabel() -> (title: String, image: ImageTexture?) {
        (accessibilityLabelText ?? "", bitmap.texture)
    }
}

/// A button (`TB1`'s navigation and primary-action items): its label's title
/// or image; its action — or a caller's `onClick`, which replaces it, as on
/// the button itself — runs on `.press`.
extension Button: ToolbarItemContent where Label: ToolbarButtonLabel {
    /// This content's controls. SPI: see `ToolbarItemContent`.
    @_spi(ToolbarInternals) public func _toolbarControls(in context: _ToolbarItemContext) -> _ToolbarControls {
        let label = box.content.first._toolbarLabel()
        let run = handlers.onClick ?? action
        return _ToolbarControls([ToolbarControlNode(
            control: .button(title: label.title, image: label.image), isEnabled: context.isEnabled,
            help: handlers.contextual?.help,
            run: { action in
                guard action == .press else { return false }
                run()
                return true
            })])
    }
}

/// A checkbox: its state, written through the binding on `.toggle(_:)`.
extension Toggle: ToolbarItemContent where Label == Text {
    /// This content's controls. SPI: see `ToolbarItemContent`.
    @_spi(ToolbarInternals) public func _toolbarControls(in context: _ToolbarItemContext) -> _ToolbarControls {
        let binding = isOn
        return _ToolbarControls([ToolbarControlNode(
            control: .toggle(title: box.content.second.string, isOn: binding.wrappedValue),
            isEnabled: context.isEnabled, help: handlers.contextual?.help,
            run: { action in
                guard case .toggle(let on) = action else { return false }
                binding.wrappedValue = on
                return true
            })])
    }
}

/// A picker: its title, its options' titles in declaration order (each
/// option's `Text`, else its tag's description — the menu picker's rule) and
/// the selected index; `.select(i)` writes option `i`'s tag. `.menu` is a
/// pop-up; every other style is segmented (`MD-I` item 3).
extension Picker: ToolbarItemContent {
    /// This content's controls. SPI: see `ToolbarItemContent`.
    @_spi(ToolbarInternals) public func _toolbarControls(in context: _ToolbarItemContext) -> _ToolbarControls {
        let parts = toolbarParts
        var options: [(tag: AnyHashable, title: String)] = []
        collectToolbarPickerOptions(parts.content, into: &options)
        let scope = parts.scope
        let tags = options.map(\.tag)
        return _ToolbarControls([ToolbarControlNode(
            control: .picker(title: parts.title, options: options.map(\.title),
                             selected: tags.firstIndex(where: scope.matches),
                             style: parts.isMenu ? .menu : .segmented),
            isEnabled: context.isEnabled, help: handlers.contextual?.help,
            run: { action in
                guard case .select(let index) = action, tags.indices.contains(index) else { return false }
                scope.write(tags[index])
                return true
            })])
    }
}

/// An editable field: its placeholder and text; `.text(s)` calls its change
/// handler (the binding's write) — controlled, like the field itself.
extension TextField: ToolbarItemContent {
    /// This content's controls. SPI: see `ToolbarItemContent`.
    @_spi(ToolbarInternals) public func _toolbarControls(in context: _ToolbarItemContext) -> _ToolbarControls {
        let change = onChange
        return _ToolbarControls([ToolbarControlNode(
            control: .textField(placeholder: placeholder, text: text), isEnabled: context.isEnabled,
            help: handlers.contextual?.help,
            run: { action in
                guard case .text(let value) = action else { return false }
                change(value)
                return true
            })])
    }
}

/// A label showing the string (`.status`'s usual content); runs nothing.
extension Text: ToolbarItemContent {
    /// This content's controls. SPI: see `ToolbarItemContent`.
    @_spi(ToolbarInternals) public func _toolbarControls(in context: _ToolbarItemContext) -> _ToolbarControls {
        _ToolbarControls([ToolbarControlNode(control: .label(text: string), isEnabled: context.isEnabled,
                                             help: nil, run: nil)])
    }
}

/// A control under an environment write: only `isEnabled` is read
/// (`MN-D` item 2's rule), so `.disabled(true)` disables the item.
extension EnvironmentScope: ToolbarItemContent where Content: ToolbarItemContent {
    /// This content's controls. SPI: see `ToolbarItemContent`.
    @_spi(ToolbarInternals) public func _toolbarControls(in context: _ToolbarItemContext) -> _ToolbarControls {
        var values = EnvironmentValues()
        values.isEnabled = context.isEnabled
        if case .transform(let transform) = write { transform(&values) }
        return content._toolbarControls(in: _ToolbarItemContext(isEnabled: values.isEnabled))
    }
}

// MARK: - Picker options

/// A group a toolbar picker's options can be read from without laying it out:
/// the element builder's groups, `ForEach` and a `.tag(_:)`ed option.
@MainActor
protocol ToolbarPickerOptions {
    func collectToolbarPickerOptions(into options: inout [(tag: AnyHashable, title: String)])
}

/// Appends `group`'s options in declaration order; a group of another kind
/// contributes none.
@MainActor
func collectToolbarPickerOptions(_ group: Any, into options: inout [(tag: AnyHashable, title: String)]) {
    (group as? any ToolbarPickerOptions)?.collectToolbarPickerOptions(into: &options)
}

extension TaggedElement: ToolbarPickerOptions {
    func collectToolbarPickerOptions(into options: inout [(tag: AnyHashable, title: String)]) {
        options.append((tag, optionTitle))
    }
}

extension Pair: ToolbarPickerOptions {
    func collectToolbarPickerOptions(into options: inout [(tag: AnyHashable, title: String)]) {
        MetalUI.collectToolbarPickerOptions(first, into: &options)
        MetalUI.collectToolbarPickerOptions(second, into: &options)
    }
}

extension OptionalGroup: ToolbarPickerOptions {
    func collectToolbarPickerOptions(into options: inout [(tag: AnyHashable, title: String)]) {
        if let wrapped { MetalUI.collectToolbarPickerOptions(wrapped, into: &options) }
    }
}

extension EitherGroup: ToolbarPickerOptions {
    func collectToolbarPickerOptions(into options: inout [(tag: AnyHashable, title: String)]) {
        switch self {
        case .first(let first): MetalUI.collectToolbarPickerOptions(first, into: &options)
        case .second(let second): MetalUI.collectToolbarPickerOptions(second, into: &options)
        }
    }
}

extension ArrayGroup: ToolbarPickerOptions {
    func collectToolbarPickerOptions(into options: inout [(tag: AnyHashable, title: String)]) {
        for group in groups { MetalUI.collectToolbarPickerOptions(group, into: &options) }
    }
}

extension ForEach: ToolbarPickerOptions {
    func collectToolbarPickerOptions(into options: inout [(tag: AnyHashable, title: String)]) {
        for element in data { MetalUI.collectToolbarPickerOptions(content(element), into: &options) }
    }
}

// MARK: - Toolbar content (closed)

/// One evaluated `ToolbarItem`, `ToolbarItemGroup` or `.searchable` field.
struct ToolbarEntry {
    /// `ToolbarItem(id:)`'s id, or `nil` for a generated one (`MD-I` item 6).
    var id: String?
    var placement: PlatformToolbarPlacement
    var controls: [ToolbarControlNode]
    /// A group's controls are numbered `"<group id>.<n>"` even when it holds
    /// one.
    var isGroup: Bool
}

/// What a toolbar's content is evaluated in. SPI, with an internal
/// initialiser.
@_spi(ToolbarInternals) public struct _ToolbarContext {
    var isEnabled: Bool
    init(isEnabled: Bool) { self.isEnabled = isEnabled }
}

/// What a `ToolbarContent` evaluates to. SPI, with an internal initialiser.
@_spi(ToolbarInternals) public struct _ToolbarEntries {
    let entries: [ToolbarEntry]
    init(_ entries: [ToolbarEntry]) { self.entries = entries }
}

/// A toolbar's content: `ToolbarItem`s and `ToolbarItemGroup`s, and
/// `if`/`switch`/`for` through `@ToolbarContentBuilder` (ruling `MD-I`
/// item 2). **Closed**: its one requirement is SPI (guard
/// `onlyTheClosedSetIsToolbarContent`).
public protocol ToolbarContent {
    /// The entries this content evaluates to. SPI: see the protocol's doc.
    @_spi(ToolbarInternals) @MainActor func _toolbarEntries(in context: _ToolbarContext) -> _ToolbarEntries
}

/// What a `@ToolbarContentBuilder` block builds: its items, in order.
public struct ToolbarItems: ToolbarContent {
    let children: [any ToolbarContent]

    init(_ children: [any ToolbarContent]) { self.children = children }

    /// This content's entries. SPI: see `ToolbarContent`.
    @_spi(ToolbarInternals) public func _toolbarEntries(in context: _ToolbarContext) -> _ToolbarEntries {
        _ToolbarEntries(children.flatMap { $0._toolbarEntries(in: context).entries })
    }
}

/// The result builder for a `.toolbar { … }` block (ruling `MD-I` item 2): a
/// block, `if`, `if`/`else`, `switch` and `for`, each element a
/// `ToolbarContent`.
@resultBuilder
public enum ToolbarContentBuilder {
    /// One item.
    public static func buildExpression<C: ToolbarContent>(_ content: C) -> ToolbarItems { ToolbarItems([content]) }
    /// A block of items, in order.
    public static func buildBlock(_ items: ToolbarItems...) -> ToolbarItems { ToolbarItems(items) }
    /// An `if` with no `else`: its items, or none.
    public static func buildOptional(_ items: ToolbarItems?) -> ToolbarItems { items ?? ToolbarItems([]) }
    /// The first branch of an `if`/`else` or `switch`.
    public static func buildEither(first items: ToolbarItems) -> ToolbarItems { items }
    /// The second branch of an `if`/`else` or `switch`.
    public static func buildEither(second items: ToolbarItems) -> ToolbarItems { items }
    /// A `for` loop: every iteration's items, in order.
    public static func buildArray(_ items: [ToolbarItems]) -> ToolbarItems { ToolbarItems(items) }
}

/// One toolbar item — SwiftUI's `ToolbarItem(id:placement:content:)` (ruling
/// `MD-I` item 2; probe `TB1`): a control at `placement`, named `id` (else
/// `"<placement>.<index among the window's merged items>"`, `MD-I` item 6).
public struct ToolbarItem<Content: ToolbarItemContent>: ToolbarContent {
    let id: String?
    let placement: ToolbarItemPlacement
    let content: Content

    /// An item at `placement` holding `content`'s control; `id` names it in
    /// the platform's toolbar, else one is generated.
    @MainActor
    public init(id: String? = nil, placement: ToolbarItemPlacement = .automatic,
                @ToolbarItemContentBuilder content: () -> Content) {
        self.id = id
        self.placement = placement
        self.content = content()
    }

    /// This content's entries. SPI: see `ToolbarContent`.
    @_spi(ToolbarInternals) public func _toolbarEntries(in context: _ToolbarContext) -> _ToolbarEntries {
        let controls = content._toolbarControls(in: _ToolbarItemContext(isEnabled: context.isEnabled)).nodes
        return _ToolbarEntries([ToolbarEntry(id: id, placement: placement.kind, controls: controls, isGroup: false)])
    }
}

/// Several controls at one placement — SwiftUI's
/// `ToolbarItemGroup(placement:content:)`: each its own platform item,
/// `"<group id>.<n>"` (`MD-I` item 6).
public struct ToolbarItemGroup<Content: ToolbarItemContent>: ToolbarContent {
    let placement: ToolbarItemPlacement
    let content: Content

    /// The controls of `content` at `placement`, in order.
    @MainActor
    public init(placement: ToolbarItemPlacement = .automatic, @ToolbarItemContentBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    /// This content's entries. SPI: see `ToolbarContent`.
    @_spi(ToolbarInternals) public func _toolbarEntries(in context: _ToolbarContext) -> _ToolbarEntries {
        let controls = content._toolbarControls(in: _ToolbarItemContext(isEnabled: context.isEnabled)).nodes
        return _ToolbarEntries([ToolbarEntry(id: nil, placement: placement.kind, controls: controls, isGroup: true)])
    }
}

// MARK: - The scope

/// What one `ToolbarScope` declares.
enum ToolbarDeclaration {
    /// A `.toolbar { … }`'s content.
    case items(any ToolbarContent)
    /// A `.searchable(text:prompt:)` field.
    case search(text: Binding<String>, prompt: String)

    @MainActor func entries(isEnabled: Bool) -> [ToolbarEntry] {
        switch self {
        case .items(let content):
            return content._toolbarEntries(in: _ToolbarContext(isEnabled: isEnabled)).entries
        case .search(let text, let prompt):
            let node = ToolbarControlNode(
                control: .search(prompt: prompt, text: text.wrappedValue), isEnabled: isEnabled, help: nil,
                run: { action in
                    guard case .text(let value) = action else { return false }
                    text.wrappedValue = value
                    return true
                })
            return [ToolbarEntry(id: nil, placement: .search, controls: [node], isGroup: false)]
        }
    }
}

/// One `ToolbarScope`'s contribution to a build: its entries, evaluated in
/// layout, and the scope's position — what an outcome is dispatched to.
struct ToolbarRecord {
    let owner: GlobalElementID
    let entries: [ToolbarEntry]
}

/// `content` with toolbar items — what `.toolbar { … }` and
/// `.searchable(text:prompt:)` return (rulings `MD-I`, `MD-S`).
///
/// **Transparent**: no layout node, no identity level, no `Handlers` member —
/// the content keeps the ids it would have without the scope. Its items are
/// evaluated once per build, in layout, reading bindings fresh, and collected
/// **window-wide in build pre-order** (an outer scope's before its content's,
/// probe `NT1`); a scope inside a popover or a `Deferred` presentation root is
/// ignored (`PO`), and a scope whose content is empty contributes nothing.
///
/// **Not an `Element`**, so it cannot be a window's root: write it on an
/// element inside the root's first container (`MD-S`, divergence 120). A
/// `Self`-returning decoration written after it does not compile either.
public struct ToolbarScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let declaration: ToolbarDeclaration

    init(content: Content, declaration: ToolbarDeclaration) {
        self.content = content
        self.declaration = declaration
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], LifecycleScopeLayout<Content.GroupLayout>) {
        let start = cursor
        let mark = pass.frame.toolbarRecords.count
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        if !nodes.isEmpty {
            pass.frame.noteToolbar(declaration, under: parent, at: start, insertingAt: mark)
        }
        return (nodes, LifecycleScopeLayout(content: layout))
    }

    public mutating func prepaintGroup(layout: inout LifecycleScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paintGroup(layout: inout LifecycleScopeLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// **The typed entry is a line-for-line copy of the untyped one, pinned on its
/// own** (test 3.5's proposal arm): a copy of a pinned implementation is
/// unpinned.
extension ToolbarScope: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], LifecycleScopeLayout<Content.GroupLayout>) {
        let start = cursor
        let mark = pass.frame.toolbarRecords.count
        let (nodes, layout) = content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        if !nodes.isEmpty {
            pass.frame.noteToolbar(declaration, under: parent, at: start, insertingAt: mark)
        }
        return (nodes, LifecycleScopeLayout(content: layout))
    }
}

extension ElementGroup {
    /// Adds `content`'s items to the window's toolbar — SwiftUI's
    /// `toolbar(content:)` (ruling `MD-I`; probe `swiftui-toolbar.swift`
    /// `TB1`). On AppKit a real `NSToolbar` of native controls; where the
    /// platform has none (SDL) the window draws it.
    ///
    /// Every `.toolbar` in the window's main tree contributes, merged in build
    /// pre-order (`NT1`); one in a popover or a `Deferred` presentation is
    /// ignored (`PO`). Items are a closed set (divergence 135). **Not a window
    /// root** (`MD-S`, divergence 120): `openWindow(…) { Column { content.toolbar { … } } }`.
    @MainActor
    public func toolbar<C: ToolbarContent>(@ToolbarContentBuilder content: () -> C) -> ToolbarScope<Self> {
        ToolbarScope(content: self, declaration: .items(content()))
    }

    /// Adds a search field to the window's toolbar, trailing and last —
    /// SwiftUI's `searchable(text:prompt:)` (ruling `MD-I` item 4, `MD-U` item
    /// 2; probe `SR`). The field writes `text` on every edit. `placement:`,
    /// suggestions, scopes and tokens are not offered (`MD-L`).
    @MainActor
    public func searchable(text: Binding<String>, prompt: String = "Search") -> ToolbarScope<Self> {
        ToolbarScope(content: self, declaration: .search(text: text, prompt: prompt))
    }
}

// MARK: - Collection

extension Frame {
    /// Notes a present scope's entries (`MD-I` item 5), inserted at `mark` —
    /// the record count before the scope's content was built — so an outer
    /// scope precedes its content's (pre-order, `NT1`). The owner is the
    /// scope's position `.child(of: parent, at: cursor)`, as a presentation
    /// scope's (`SV-K` item 2). Evaluated under the scope's `isEnabled`.
    func noteToolbar(_ declaration: ToolbarDeclaration, under parent: GlobalElementID?, at cursor: Int,
                     insertingAt mark: Int) {
        let owner = GlobalElementID.child(of: parent, at: cursor, name: nil)
        let record = ToolbarRecord(owner: owner, entries: declaration.entries(isEnabled: environmentTop.isEnabled))
        toolbarRecords.insert(record, at: min(mark, toolbarRecords.count))
    }
}

// MARK: - Assembly

/// A build's toolbar, numbered for the platform (`MD-I` item 6, `MD-J`): the
/// neutral description and, per item id, what an outcome runs.
struct AssembledToolbar {
    struct Target {
        let owner: GlobalElementID
        let isEnabled: Bool
        let run: @MainActor (ToolbarActionEvent.Action) -> Bool
    }

    /// `nil` when the build had no toolbar item.
    let toolbar: PlatformToolbar?
    let targets: [String: Target]

    static let empty = AssembledToolbar(toolbar: nil, targets: [:])

    /// Numbers `records`' entries: the non-search entries in order, each an
    /// item (`id`, else `"<placement>.<k>"` with `k` its index among them) or,
    /// for a group or an item of several controls, one item per control
    /// (`"<id>.<n>"`); then the search fields (`"search"`, `"search.<k>"`),
    /// last (`MD-I` item 4).
    init(records: [ToolbarRecord]) {
        var items: [PlatformToolbarItem] = []
        var searches: [PlatformToolbarItem] = []
        var targets: [String: Target] = [:]
        var index = 0
        var searchIndex = 0
        func add(_ node: ToolbarControlNode, id: String, placement: PlatformToolbarPlacement,
                 owner: GlobalElementID, to list: inout [PlatformToolbarItem]) {
            list.append(PlatformToolbarItem(id: id, placement: placement, control: node.control,
                                            isEnabled: node.isEnabled, help: node.help))
            if let run = node.run {
                targets[id] = Target(owner: owner, isEnabled: node.isEnabled, run: run)
            }
        }
        for record in records {
            for entry in record.entries {
                if entry.placement == .search {
                    let base = searchIndex == 0 ? "search" : "search.\(searchIndex)"
                    searchIndex += 1
                    for node in entry.controls {
                        add(node, id: base, placement: .search, owner: record.owner, to: &searches)
                    }
                    continue
                }
                let base = entry.id ?? "\(ToolbarItemPlacement(kind: entry.placement).idPrefix).\(index)"
                index += 1
                let numbered = entry.isGroup || entry.controls.count > 1
                for (n, node) in entry.controls.enumerated() {
                    add(node, id: numbered ? "\(base).\(n)" : base, placement: entry.placement,
                        owner: record.owner, to: &items)
                }
            }
        }
        let all = items + searches
        self.toolbar = all.isEmpty ? nil : PlatformToolbar(items: all)
        self.targets = targets
    }

    init(toolbar: PlatformToolbar?, targets: [String: Target]) {
        self.toolbar = toolbar
        self.targets = targets
    }
}

extension Window {
    /// A native toolbar control's outcome, from input (`MD-J` item 4): runs
    /// the item of the last evaluated toolbar under `StateDispatch` for the
    /// scope that declared it. An unknown id, a disabled item or an action of
    /// the wrong kind runs nothing.
    func handleToolbarAction(_ event: ToolbarActionEvent) {
        guard let target = assembledToolbar.targets[event.item], target.isEnabled else { return }
        StateDispatch.dispatching(to: target.owner) {
            _ = target.run(event.action)
        }
    }

    /// Sends the last build's toolbar to the platform when it differs from the
    /// last one sent (`MD-J` item 2) — after the frame's builds, outside every
    /// phase. A window that never had a `.toolbar` never calls; the last one
    /// leaving sends `nil` once. Records whether the window must draw it
    /// (`false` from the platform; lane 3's strip).
    func reconcileToolbar() {
        let toolbar = assembledToolbar.toolbar
        guard toolbar != sentToolbar else { return }
        sentToolbar = toolbar
        let shown = setToolbarOnPlatform(toolbar)
        toolbarIsDrawn = toolbar != nil && !shown
    }
}
