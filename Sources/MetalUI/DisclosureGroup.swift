import MetalUICore
import MetalUILayout

/// SwiftUI's `DisclosureGroup` in an eager context (lane 1 of the hierarchical lists, rulings `OG-A`, `OG-D`, `OG-H`,
/// `OG-J`; probe `docs/probes/swiftui-disclosure-group.swift`, arms `D1`-`D4`): a label row with a chevron, and
/// `content` under it while the group is expanded.
///
/// ```swift
/// DisclosureGroup("Advanced") {          // uncontrolled: starts collapsed (D4)
///     Text("Verbose logging")
///     Text("Telemetry")
/// }
/// DisclosureGroup(isExpanded: $open) { … } label: { Label("Files", systemImage: "folder") }
/// ```
///
/// **Content is evaluated only while expanded.** `content` is stored `@escaping` and built when the group is
/// expanded; a collapsed group never calls it (pinned by `aCollapsedGroupNeverCallsItsContent`).
///
/// **Expansion state.** `init(content:label:)` is uncontrolled: a `@State` slot at the group's identity, collapsed
/// initially (`D4`). `init(isExpanded:content:label:)` is controlled: the binding is read while building and written
/// **only from input** - a click on the label row, Space when the row is focused, or an accessibility press - never
/// from layout or paint (`RW-I`). A bare binding write snaps; under `withAnimation` the content's insertion and
/// removal animate through the default transition (`XF-H`, D3a/D3b). **A click writes bare**: SwiftUI's click
/// animation (D3c) could not be measured, so a click snaps (`OG-H`).
///
/// **Look** (`D1`): a 24 point label row, the chevron at the leading edge in a 12 point slot, the label after it, and
/// the content under the row with no spacing, **no indentation** - a centre-aligned stack in the group's width, so a
/// nested group starts at its parent's x. The group takes the width it is offered. The chevron is a glyph **swap**,
/// never a rotation (`P-L3`): `chevron.right` collapsed, `chevron.down` expanded, in the tertiary level (`OG-J`).
///
/// **Accessibility** is MetalUI's choice (`P-A3`, SwiftUI's own tree for a standalone group is unmeasured): the
/// label row publishes as a disclosure triangle (`AXDisclosureTriangle` on macOS; a button on AccessKit) whose
/// value is `"1"` expanded and `"0"` collapsed, labelled by the label's text, with the press action toggling it.
///
/// **A disabled group** (`.disabled(true)`) refuses a click, Space and an accessibility press, and fades like a
/// disabled control.
///
/// Not offered: `DisclosureGroupStyle` (class `R`) and the `LocalizedStringResource` forms.
public struct DisclosureGroup<Label: ElementGroup, Content: ElementGroup>: ElementGroup {
    var inner: DisclosureGroupBody<Label, Content>

    init(expansion: Binding<Bool>?, label: Label, content: @escaping @MainActor () -> Content) {
        inner = DisclosureGroupBody(expansion: expansion, label: label, makeContent: content)
    }

    /// An uncontrolled group, collapsed initially: SwiftUI's `DisclosureGroup(content:label:)`.
    public init(@ElementBuilder content: @escaping @MainActor () -> Content,
                @ElementBuilder label: () -> Label) {
        self.init(expansion: nil, label: label(), content: content)
    }

    /// A group whose expansion is `isExpanded`: SwiftUI's `DisclosureGroup(isExpanded:content:label:)`. The binding
    /// is written only by input.
    public init(isExpanded: Binding<Bool>, @ElementBuilder content: @escaping @MainActor () -> Content,
                @ElementBuilder label: () -> Label) {
        self.init(expansion: isExpanded, label: label(), content: content)
    }

    public typealias GroupLayout = ComponentLayout<DisclosureGroupBody<Label, Content>>
    public typealias GroupPrepaint = ComponentPrepaint<DisclosureGroupBody<Label, Content>>

    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], ComponentLayout<DisclosureGroupBody<Label, Content>>) {
        inner.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
    }

    public mutating func prepaintGroup(layout: inout ComponentLayout<DisclosureGroupBody<Label, Content>>,
                                       pass: inout PrepaintPass)
        -> ComponentPrepaint<DisclosureGroupBody<Label, Content>> {
        inner.prepaintGroup(layout: &layout, pass: &pass)
    }

    public mutating func paintGroup(layout: inout ComponentLayout<DisclosureGroupBody<Label, Content>>,
                                    prepaint: inout ComponentPrepaint<DisclosureGroupBody<Label, Content>>,
                                    pass: inout PaintPass) {
        inner.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension DisclosureGroup where Label == Text {
    /// A group titled `titleKey`, uncontrolled: SwiftUI's `DisclosureGroup(_:content:)`. A string **literal** is
    /// parsed as inline Markdown, as `Text`'s is.
    public init(_ titleKey: LocalizedStringKey, @ElementBuilder content: @escaping @MainActor () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }

    /// A group titled by the `StringProtocol` value `title`, shown verbatim, uncontrolled. Disfavoured, so a
    /// literal reaches the `LocalizedStringKey` overload.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ElementBuilder content: @escaping @MainActor () -> Content) {
        self.init(content: content) { Text(verbatim: String(title)) }
    }

    /// A group titled `titleKey`, expanded by `isExpanded`: SwiftUI's `DisclosureGroup(_:isExpanded:content:)`.
    public init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>,
                @ElementBuilder content: @escaping @MainActor () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(titleKey) }
    }

    /// A group titled by the `StringProtocol` value `title`, expanded by `isExpanded`.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, isExpanded: Binding<Bool>,
                                   @ElementBuilder content: @escaping @MainActor () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(verbatim: String(title)) }
    }
}

/// What `DisclosureGroup` builds: the group's identity level (so its `@State` slot lives at the group's id) over
/// a column of the label row and, while expanded, the content. Internal; `public` only because the group's
/// `GroupLayout` names it.
public struct DisclosureGroupBody<Label: ElementGroup, Content: ElementGroup>: Component {
    let expansion: Binding<Bool>?
    let label: Label
    let makeContent: @MainActor () -> Content
    @State private var local = false
    /// An `OutlineGroup`'s disclosure keeps what is below it while collapsed (`OG-D`, probe `P-E5`): its content is not
    /// evaluated, but its slot is not noted absent, so a descendant's expansion survives the collapse.
    var keepsHiddenState = false
    /// Called by input's toggle after the write: an outline index's generation bump (`OG-K`).
    var onToggle: (@MainActor () -> Void)?

    init(expansion: Binding<Bool>?, label: Label, makeContent: @escaping @MainActor () -> Content) {
        self.expansion = expansion
        self.label = label
        self.makeContent = makeContent
    }

    /// The height of the label row (`D1`).
    static var rowHeight: Float { 24 }
    /// The cell the chevron glyph is centred in (`D1`: collapsed ink 5 wide at 2, expanded 8 wide at 0, both centred in a
    /// 9 wide cell).
    static var chevronCell: Float { 9 }
    /// The width of the chevron slot; the label starts at its trailing edge (`D1`: label ink 12.5 from the leading edge).
    static var chevronSlot: Float { 12 }

    var isExpanded: Bool { expansion?.wrappedValue ?? local }

    /// Input's write: the one place the expansion changes.
    func toggle() {
        if let expansion {
            expansion.wrappedValue = !expansion.wrappedValue
        } else {
            local.toggle()
        }
        onToggle?()
    }

    /// The label row: a chevron slot, then the label, 24 high, as wide as the group (`D1`). Its click, Space and
    /// accessibility press toggle the group; it is a disclosure triangle with value `"1"`/`"0"` for a client.
    var header: some ElementGroup {
        let open = isExpanded
        let toggle = self.toggle
        var button = Button(action: { toggle() }) {
            HStack(alignment: .center, spacing: Pixels(0)) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)   // decorative: the row is labelled by the label alone, not "Forward"
                    .frame(width: Pixels(Self.chevronCell))
                    .frame(width: Pixels(Self.chevronSlot), alignment: .leading)
                label
                Spacer()
            }
            .frame(height: Pixels(Self.rowHeight))
        }
        .buttonStyle(.plain)
        button.handlers.axNode.roleHint = .disclosureTriangle
        button.handlers.axNode.value = open ? "1" : "0"
        return button
    }

    /// The group's body: the label row over the content while expanded, a centre-aligned stack with no spacing.
    @ElementBuilder public var content: some ElementGroup {
        VStack(alignment: .center, spacing: Pixels(0)) {
            header
            expandedContent
        }
    }

    /// The `if isExpanded { content }` slot, by hand so an outline's can retain (`keepsHiddenState`).
    private var expandedContent: OptionalGroup<LegacyContent<Content>> {
        var group = OptionalGroup(builder: isExpanded ? LegacyContent(makeContent()) : nil)
        group.retainsStateWhenAbsent = keepsHiddenState
        return group
    }
}

/// Where a `DisclosureGroupBody` keeps its uncontrolled expansion, so an outline can read a group's state without
/// building the group (`OG-K`): the slot of its `@State local` under the group's component id.
@MainActor
enum DisclosureSlot {
    /// The ordinal of `local` among the body's stored properties (the `@State` slot's number).
    static let ordinal: Int = {
        let probe = DisclosureGroupBody<EmptyGroup, EmptyGroup>(expansion: nil, label: EmptyGroup(), makeContent: { EmptyGroup() })
        return Mirror(reflecting: probe).children.enumerated().first { $0.element.label == "_local" }!.offset
    }()

    /// The slot `local` lives at, for the group whose component id is `group`.
    static func slot(of group: GlobalElementID) -> GlobalElementID {
        GlobalElementID.child(of: group, at: ordinal, name: ElementID("$state\(ordinal)"))
    }
}
