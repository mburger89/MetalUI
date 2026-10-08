import MetalUICore
import MetalUILayout

/// SwiftUI's `ProgressView` (C10 lane 2, rulings `LK-E`, `LK-F`, `LK-P`; spec
/// `2026-10-08-controls-looks-design.md` §3.2): a spinner without a value, a
/// bar with one, and their titled forms.
///
/// **One node, `Toggle`'s shape** (`LK-P`): one `Box` — a column — over the
/// title, an internal indicator leaf and the current-value label, so it is one
/// child of any container and takes every `StyledElement` modifier. A bar
/// stacks its title **above** with no gap and its current-value label
/// **below** in the caption font and secondary colour, leading-aligned (probe
/// `V4`); a spinner stacks its title **below**, centred, 4 points apart (`V1`).
///
/// **Sizes** (`V0`–`V6`): the spinner and the ring are 32×32, 16 at
/// `.small`, 10 at `.mini`; the bar is 20 tall (12 at `.small` and `.mini`) and
/// **greedy on the width** — it takes a finite offer whole, answers infinity at
/// an infinite one and 0 at `nil`.
///
/// **Values** (`V8`): the fraction is `value / total`, drawn full above the
/// total; a value below 0, a total of 0 or less, or a non-finite value or total
/// is **indeterminate** — never a trap, nothing non-finite reaches a node.
///
/// **Animation** (`LK-F`): the spinner advances in 24 discrete steps per 0.8 s
/// of the frame clock (`V13`, AppKit's own animation) and an indeterminate bar
/// sweeps a 30% segment across and back every 1.6 s, each noting an active
/// animation **only while painted visibly** (not hidden, not zero-sized, not
/// clipped out, not transparent). Reduce Motion does not stop them (`V10`). A
/// determinate view never animates.
///
/// **Accessibility** (`V7`, `V8`): a determinate view is a
/// `.progressIndicator` valued with the fraction (`5/10` reads `0.5`), an
/// indeterminate one a `.busyIndicator` with no value; a string title is the
/// node's label. A label *view* (`init(value:total:label:currentValueLabel:)`)
/// publishes as its own content (`LK-V` item 6).
public struct ProgressView<Label: ElementGroup, CurrentValueLabel: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration = Decoration()
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    /// The fraction 0…1, or `nil` when indeterminate.
    let fraction: Double?
    let label: Label
    let currentValueLabel: CurrentValueLabel
    /// A string title, the indicator's accessibility label.
    let title: String?
    /// The style written on the view itself (`progressViewStyle(_:)`).
    var ownStyle: ProgressViewStyle?

    typealias CaptionLabel = EnvironmentScope<EnvironmentScope<CurrentValueLabel>>
    typealias BodyContent = Pair<OptionalGroup<Label>, Pair<ProgressIndicator,
                                                            Pair<OptionalGroup<Label>, OptionalGroup<CaptionLabel>>>>
    typealias Body = Box<BodyContent>

    init<V: BinaryFloatingPoint>(value: V?, total: V, label: Label, currentValueLabel: CurrentValueLabel,
                                 title: String?) {
        self.style = Style()
        let raw: Double? = if let value { Double(value) } else { nil }
        self.fraction = Self.fraction(value: raw, total: Double(total))
        self.label = label
        self.currentValueLabel = currentValueLabel
        self.title = title
    }

    /// A progress view of `value` out of `total`, titled by `label` with
    /// `currentValueLabel` below — SwiftUI's
    /// `ProgressView(value:total:label:currentValueLabel:)`. A `nil` value is
    /// indeterminate.
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0, @ElementBuilder label: () -> Label,
                                        @ElementBuilder currentValueLabel: () -> CurrentValueLabel) {
        self.init(value: value, total: total, label: label(), currentValueLabel: currentValueLabel(), title: nil)
    }

    /// `value / total` clamped to 0…1, or `nil` when indeterminate (`LK-E`
    /// item 2).
    nonisolated static func fraction(value: Double?, total: Double) -> Double? {
        guard let value else { return nil }
        return value / total
    }

    /// This view drawn in `style`, whatever a container wrote (the innermost
    /// wins) — SwiftUI's `progressViewStyle(_:)`.
    public func progressViewStyle(_ style: ProgressViewStyle) -> ProgressView {
        var copy = self
        copy.ownStyle = style
        return copy
    }

    /// The box over the title, the indicator and the current-value label,
    /// built afresh per layout for this frame's style and control size.
    private func body(environment: EnvironmentValues) -> Body {
        let resolvedStyle = ownStyle ?? environment.progressViewStyle ?? .automatic
        let kind = ProgressIndicator.Kind(style: resolvedStyle, fraction: fraction)
        let isBar = kind == .bar || kind == .indeterminateBar
        var style = self.style
        style.flexDirection = .column
        style.alignItems = isBar ? .flexStart : .center
        style.gap = Axes(both: .pixels(Pixels(isBar ? 0 : 4)))
        let indicator = ProgressIndicator(kind: kind, fraction: fraction, controlSize: environment.controlSize,
                                          title: title)
        let caption: CaptionLabel = currentValueLabel.foregroundStyle(Color.secondary).font(.caption)
        var box = Body(style: style, content: Pair(isBar ? OptionalGroup(label) : OptionalGroup(nil),
                                                    Pair(indicator, Pair(isBar ? OptionalGroup(nil) : OptionalGroup(label),
                                                                         OptionalGroup(isBar ? caption : nil)))))
        box.decoration = decoration
        return box
    }

    /// What `requestLayout` hands the later phases: the box it built and laid
    /// out.
    public struct Layout {
        var body: Body
        var bodyLayout: Body.Layout
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var body = body(environment: pass.frame.environmentTop)
        let (node, layout) = body.requestLayout(id, pass: &pass)
        return (node, Layout(body: body, bodyLayout: layout))
    }

    /// What `prepaint` hands `paint`: the box's own prepaint.
    public struct Prepaint {
        var body: BodyContent.GroupPrepaint
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Prepaint {
        layout.body.handlers = handlers
        return Prepaint(body: layout.body.prepaint(id, bounds: bounds, layout: &layout.bodyLayout, pass: &pass))
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Prepaint, pass: inout PaintPass) {
        layout.body.paint(id, bounds: bounds, layout: &layout.bodyLayout, prepaint: &prepaint.body, pass: &pass)
    }
}

extension ProgressView where Label == EmptyGroup, CurrentValueLabel == EmptyGroup {
    /// An indeterminate progress view: the spinner — SwiftUI's `ProgressView()`.
    public init() {
        self.init(value: nil as Double?, total: 1, label: EmptyGroup(), currentValueLabel: EmptyGroup(), title: nil)
    }

    /// A progress view of `value` out of `total`: the bar — SwiftUI's
    /// `ProgressView(value:total:)`. A `nil` value is indeterminate.
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {
        self.init(value: value, total: total, label: EmptyGroup(), currentValueLabel: EmptyGroup(), title: nil)
    }
}

extension ProgressView where Label == Text, CurrentValueLabel == EmptyGroup {
    /// An indeterminate progress view titled `title` — SwiftUI's
    /// `ProgressView(_:)`: the spinner with the title below.
    public init(_ title: String) {
        self.init(value: nil as Double?, total: 1, label: Text(title).accessibilityHidden(true),
                  currentValueLabel: EmptyGroup(), title: title)
    }

    /// A progress view of `value` out of `total` titled `title` — SwiftUI's
    /// `ProgressView(_:value:total:)`: the bar with the title above.
    public init<V: BinaryFloatingPoint>(_ title: String, value: V?, total: V = 1.0) {
        self.init(value: value, total: total, label: Text(title).accessibilityHidden(true),
                  currentValueLabel: EmptyGroup(), title: title)
    }
}

/// A `ProgressView`'s indicator — the spinner, the bar or the ring: a leaf,
/// `Slider`'s shape (`registerAndScope` in `prepaint`, `paintDecoration` in
/// `paint`).
struct ProgressIndicator: Element, StyledElement {
    enum Kind: Equatable {
        case spinner, bar, indeterminateBar, ring

        init(style: ProgressViewStyle, fraction: Double?) {
            switch (style.kind, fraction) {
            case (.linear, nil): self = .indeterminateBar
            case (.linear, _), (.automatic, .some): self = .bar
            case (.circular, .some): self = .ring
            case (.automatic, nil), (.circular, nil): self = .spinner
            }
        }
    }

    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()
    let kind: Kind
    let fraction: Double?
    let controlSize: ControlSize
    let title: String?

    init(kind: Kind, fraction: Double?, controlSize: ControlSize, title: String?) {
        self.kind = kind
        self.fraction = fraction
        self.controlSize = controlSize
        self.title = title
    }

    /// The indicator's answer to a width proposal (`LK-E` item 3).
    nonisolated static func size(kind: Kind, controlSize: ControlSize, proposedWidth: Double?) -> SizeD {
        SizeD(width: 0, height: 0)
    }

    struct Layout { var node: LayoutNodeID }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let kind = kind, controlSize = controlSize
        let node = pass.lowerLegacyLeaf(style, declared: style, site: .progressView) {
            pass.frame.requestNativeLeaf { proposal in
                LayoutMeasurement(size: Self.size(kind: kind, controlSize: controlSize, proposedWidth: proposal.width))
            }
        }
        return (node, Layout(node: node))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) {
        pass.registerAndScope(handlers, decoration, at: bounds, for: id) { }
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                        prepaint: inout Void, pass: inout PaintPass) {
        pass.paintDecoration(decoration, in: bounds, for: id) { }
    }
}
