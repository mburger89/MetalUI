import Foundation
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
    /// Whether a value initialiser built it: a bar even when indeterminate
    /// (`V6`: `ProgressView(value: nil)` is 0×20 at `nil`).
    let hasValue: Bool
    /// The style written on the view itself (`progressViewStyle(_:)`).
    var ownStyle: ProgressViewStyle?

    typealias CaptionLabel = EnvironmentScope<EnvironmentScope<CurrentValueLabel>>
    typealias BodyContent = Pair<OptionalGroup<Label>, Pair<ProgressIndicator,
                                                            Pair<OptionalGroup<Label>, OptionalGroup<CaptionLabel>>>>
    typealias Body = Box<BodyContent>

    init<V: BinaryFloatingPoint>(value: V?, total: V, label: Label, currentValueLabel: CurrentValueLabel,
                                 title: String?, hasValue: Bool = true) {
        self.hasValue = hasValue
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
        guard let value, value.isFinite, total.isFinite, value >= 0, total > 0 else { return nil }
        let fraction = value / total
        return fraction.isFinite ? min(fraction, 1) : nil
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
        let kind = ProgressIndicator.Kind(style: resolvedStyle, fraction: fraction, hasValue: hasValue)
        let isBar = kind.isBar
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
        self.init(value: nil as Double?, total: 1, label: EmptyGroup(), currentValueLabel: EmptyGroup(), title: nil,
                  hasValue: false)
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
                  currentValueLabel: EmptyGroup(), title: title, hasValue: false)
    }

    /// A progress view of `value` out of `total` titled `title` — SwiftUI's
    /// `ProgressView(_:value:total:)`: the bar with the title above.
    public init<V: BinaryFloatingPoint>(_ title: String, value: V?, total: V = 1.0) {
        self.init(value: value, total: total, label: Text(title).accessibilityHidden(true),
                  currentValueLabel: EmptyGroup(), title: title)
    }
}

/// A `ProgressView`'s indicator — the spinner, a bar or the ring: a leaf,
/// `Slider`'s shape (`registerAndScope` in `prepaint`, `paintDecoration` in
/// `paint`), carrying the view's one accessibility node (`LK-E` item 5).
struct ProgressIndicator: Element, StyledElement {
    enum Kind: Equatable {
        case spinner, bar, indeterminateBar, ring

        /// `LK-E` item 2, `LK-V` item 5: `.automatic` draws the spinner for
        /// `ProgressView()`/`ProgressView(_:)` and a bar for a value initialiser
        /// (indeterminate when the value is, `V6`); `.linear` always a bar;
        /// `.circular` the spinner or, with a fraction, the ring.
        init(style: ProgressViewStyle, fraction: Double?, hasValue: Bool) {
            switch style.kind {
            case .automatic:
                self = !hasValue ? .spinner : (fraction == nil ? .indeterminateBar : .bar)
            case .linear:
                self = fraction == nil ? .indeterminateBar : .bar
            case .circular:
                self = fraction == nil ? .spinner : .ring
            }
        }

        var isBar: Bool { self == .bar || self == .indeterminateBar }
    }

    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()
    let kind: Kind
    let fraction: Double?
    let controlSize: ControlSize
    let title: String?

    /// The spinner's period and step count (`LK-F` item 1, probe `V13`).
    nonisolated static let spinnerPeriod = 0.8
    nonisolated static let spinnerSteps = 24
    /// The indeterminate bar's sweep period, across and back (`LK-F` item 2).
    nonisolated static let barPeriod = 1.6

    init(kind: Kind, fraction: Double?, controlSize: ControlSize, title: String?) {
        self.kind = kind
        self.fraction = fraction
        self.controlSize = controlSize
        self.title = title
    }

    /// The spinner's or ring's side (`V0`): 32, 16 at `.small`, 10 at `.mini`.
    nonisolated static func side(_ controlSize: ControlSize) -> Double {
        switch controlSize {
        case .mini: return 10
        case .small: return 16
        case .regular, .large, .extraLarge: return 32
        }
    }

    /// A bar's height (`V3`): 20, 12 at `.small` and `.mini`.
    nonisolated static func barHeight(_ controlSize: ControlSize) -> Double {
        switch controlSize {
        case .mini, .small: return 12
        case .regular, .large, .extraLarge: return 20
        }
    }

    /// The indicator's answer to a width proposal (`LK-E` item 3): a bar takes
    /// the offer whole — infinity at an infinite one, 0 at `nil` (`PE-D`'s
    /// rule) — the spinner and the ring are square.
    nonisolated static func size(kind: Kind, controlSize: ControlSize, proposedWidth: Double?) -> SizeD {
        if kind.isBar { return SizeD(width: proposedWidth ?? 0, height: barHeight(controlSize)) }
        let side = side(controlSize)
        return SizeD(width: side, height: side)
    }

    /// The spinner's step at `time` (`LK-F` item 1): `floor((t mod 0.8) / 0.8 × 24)`.
    nonisolated static func spinnerStep(at time: Double) -> Int {
        guard time.isFinite else { return 0 }
        let phase = time.truncatingRemainder(dividingBy: spinnerPeriod)
        let wrapped = phase < 0 ? phase + spinnerPeriod : phase
        return min(spinnerSteps - 1, max(0, Int((wrapped / spinnerPeriod * Double(spinnerSteps)).rounded(.down))))
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
        var composed = handlers
        let determinate = (kind == .bar || kind == .ring) ? fraction : nil
        composed.axNode.progressHint = determinate == nil ? .busy : .determinate
        if let determinate, composed.axNode.value == nil {
            composed.axNode.value = ValueStepping.accessibilityText(determinate)
        }
        if let title, composed.axNode.label == nil { composed.axNode.label = title }
        pass.registerAndScope(composed, decoration, at: bounds, for: id) { }
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                        prepaint: inout Void, pass: inout PaintPass) {
        let kind = kind, fraction = fraction
        let time = pass.frame.timestamp
        let accent = controlAccent(pass.frame.environmentTop)
        // Only an indeterminate indicator painted visibly keeps the window
        // drawing (`LK-F` item 3) — never `requestAnotherFrame()`.
        if kind == .spinner || kind == .indeterminateBar, pass.frame.isVisiblyPainted(bounds) {
            pass.frame.noteActiveAnimation()
        }
        pass.paintDecoration(decoration, in: bounds, for: id) {
            switch kind {
            case .spinner: Self.paintSpinner(bounds, step: Self.spinnerStep(at: time), pass: &pass)
            case .bar: Self.paintBar(bounds, fraction: fraction ?? 0, accent: accent, pass: &pass)
            case .indeterminateBar: Self.paintSweep(bounds, time: time, accent: accent, pass: &pass)
            case .ring: Self.paintRing(bounds, fraction: fraction ?? 0, accent: accent, pass: &pass)
            }
        }
    }

    private static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Bounds<Pixels> {
        Bounds(origin: Point(x: Pixels(Float(x)), y: Pixels(Float(y))),
               size: Size(width: Pixels(Float(max(w, 0))), height: Pixels(Float(max(h, 0)))))
    }

    private static func point(_ x: Double, _ y: Double) -> Point<Pixels> {
        Point(x: Pixels(Float(x)), y: Pixels(Float(y)))
    }

    /// The bar's track: 8 points tall in a 20-point box (6 in a 12-point one),
    /// centred, fully rounded (`LK-E` item 4, `V14`).
    private static func track(_ bounds: Bounds<Pixels>) -> (x: Double, y: Double, w: Double, h: Double) {
        let h = Double(bounds.size.height.value) >= 20 ? 8.0 : 6.0
        return (Double(bounds.origin.x.value),
                Double(bounds.origin.y.value) + (Double(bounds.size.height.value) - h) / 2,
                Double(bounds.size.width.value), h)
    }

    /// Twelve spokes, 2-point capsules from half the radius to the edge, the
    /// head at `step × 15°` clockwise from 12 o'clock and the rest fading to a
    /// quarter behind it (`LK-F` item 1; the look is human check 3).
    private static func paintSpinner(_ bounds: Bounds<Pixels>, step: Int, pass: inout PaintPass) {
        let side = Double(min(bounds.size.width.value, bounds.size.height.value))
        guard side > 0 else { return }
        let cx = Double(bounds.origin.x.value) + Double(bounds.size.width.value) / 2
        let cy = Double(bounds.origin.y.value) + Double(bounds.size.height.value) / 2
        let radius = side / 2, width = max(1, side / 16)
        let inner = radius / 2 + width / 2, outer = radius - width / 2
        let base = pass.theme[.textPrimary]
        let stroke = StrokeStyle(lineWidth: Pixels(Float(width)), lineCap: .round)
        for spoke in 0..<12 {
            let angle = Double(step * 15 - spoke * 30) * Double.pi / 180
            let (s, c) = (sin(angle), cos(angle))
            let path = Path { p in
                p.move(to: point(cx + inner * s, cy - inner * c))
                p.addLine(to: point(cx + outer * s, cy - outer * c))
            }
            let opacity = 1 - 0.75 * Double(spoke) / 11
            let color = Hsla(h: base.h, s: base.s, l: base.l, a: base.a * Float(0.7 * opacity))
            pass.drawPath(path, stroke: stroke, color: color)
        }
    }

    /// The determinate bar: the track and the fraction filled in the accent.
    private static func paintBar(_ bounds: Bounds<Pixels>, fraction: Double, accent: ColorToken,
                                 pass: inout PaintPass) {
        let t = track(bounds)
        let radius = Corners(all: Pixels(Float(t.h / 2)))
        pass.fill(rect(t.x, t.y, t.w, t.h), color: pass.theme[.separator], cornerRadii: radius)
        let filled = t.w * min(max(fraction, 0), 1)
        if filled > 0 {
            pass.fill(rect(t.x, t.y, filled, t.h), color: pass.theme[accent], cornerRadii: radius)
        }
    }

    /// The indeterminate bar: a 30%-wide segment across the track and back
    /// every 1.6 s (`LK-F` item 2).
    private static func paintSweep(_ bounds: Bounds<Pixels>, time: Double, accent: ColorToken,
                                   pass: inout PaintPass) {
        let t = track(bounds)
        let radius = Corners(all: Pixels(Float(t.h / 2)))
        pass.fill(rect(t.x, t.y, t.w, t.h), color: pass.theme[.separator], cornerRadii: radius)
        guard time.isFinite, t.w > 0 else { return }
        var phase = time.truncatingRemainder(dividingBy: barPeriod) / barPeriod
        if phase < 0 { phase += 1 }
        let travel = phase < 0.5 ? phase * 2 : 2 - phase * 2
        let segment = t.w * 0.3
        pass.fill(rect(t.x + travel * (t.w - segment), t.y, segment, t.h), color: pass.theme[accent],
                  cornerRadii: radius)
    }

    /// The determinate ring: a track circle and the fraction's arc clockwise
    /// from 12 o'clock, stroked (the look is unprobed, human check 3).
    private static func paintRing(_ bounds: Bounds<Pixels>, fraction: Double, accent: ColorToken,
                                  pass: inout PaintPass) {
        let side = Double(min(bounds.size.width.value, bounds.size.height.value))
        guard side > 0 else { return }
        let cx = Double(bounds.origin.x.value) + Double(bounds.size.width.value) / 2
        let cy = Double(bounds.origin.y.value) + Double(bounds.size.height.value) / 2
        let width = max(1.5, side / 8), radius = side / 2 - width / 2
        func arc(_ sweep: Double) -> Path {
            let segments = max(2, Int((64 * sweep).rounded(.up)))
            return Path { p in
                for index in 0...segments {
                    let angle = 2 * Double.pi * sweep * Double(index) / Double(segments)
                    let next = point(cx + radius * sin(angle), cy - radius * cos(angle))
                    if index == 0 { p.move(to: next) } else { p.addLine(to: next) }
                }
            }
        }
        pass.drawPath(arc(1), stroke: StrokeStyle(lineWidth: Pixels(Float(width))), color: pass.theme[.separator])
        let clamped = min(max(fraction, 0), 1)
        if clamped > 0 {
            pass.drawPath(arc(clamped), stroke: StrokeStyle(lineWidth: Pixels(Float(width)), lineCap: .round),
                          color: pass.theme[accent])
        }
    }
}

extension Frame {
    /// Whether a leaf at `bounds` paints anything a viewer can see (`LK-F`
    /// item 3; `drawSurface`'s rule, `MV-G` item 4): a nonzero size, a nonzero
    /// opacity and an overlap with the active clip. A hidden node never paints
    /// at all.
    func isVisiblyPainted(_ bounds: Bounds<Pixels>) -> Bool {
        guard bounds.size.width.value > 0, bounds.size.height.value > 0, activeOpacity > 0 else { return false }
        let x = bounds.origin.x.value + activeOffset.x.value, y = bounds.origin.y.value + activeOffset.y.value
        let clip = activeClip
        let overlapWidth = min(x + bounds.size.width.value, clip.origin.x.value + clip.size.width.value)
            - max(x, clip.origin.x.value)
        let overlapHeight = min(y + bounds.size.height.value, clip.origin.y.value + clip.size.height.value)
            - max(y, clip.origin.y.value)
        return overlapWidth > 0 && overlapHeight > 0
    }
}
