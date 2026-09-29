import MetalUICore
import MetalUILayout

/// What `Window` needs to drive a `Slider` from the pointer (ruling `DD-W`
/// item 5), built by the slider in `prepaint` and carried on its `Handlers` —
/// `TextInputTarget`'s precedent (`TI-B`). Geometry is the frame's: window
/// points, scroll-view offsets applied.
///
/// **It rides the hitbox**: `Handlers.isPointerTarget` counts it, so the one
/// disabled gate (`Frame.registerHandlers`) and `allowsHitTesting(false)`
/// remove it with the hitbox, and a press on a disabled slider reaches nothing.
struct ValueTrackTarget {
    /// Window x of the slider's box's left edge.
    var minX: Double
    /// The box's width.
    var width: Double
    /// The thumb's width: the track's travel is `width − thumb`.
    var thumb: Double
    var bounds: ClosedRange<Double>
    var step: Double?
    var write: @MainActor (Double) -> Void

    /// Writes the value under window `x` (`ValueStepping.sliderValue`).
    @MainActor
    func track(toWindowX x: Double) {
        write(ValueStepping.sliderValue(atX: x, minX: minX, width: width, thumb: thumb,
                                        in: bounds, step: step))
    }
}

/// SwiftUI's `Slider(value:in:step:)` in its macOS look (ruling `DD-W`; spec
/// `2026-09-26-controls-and-selection-design.md` §3–§6).
///
/// **A leaf**, `TextField`'s shape: greedy on the width — the finite proposed
/// width, else 30, SL0's ideal — and 16 tall (SL0). It paints a 4-point track
/// inset by half the thumb, filled to the thumb's centre, and a 20×16 capsule
/// thumb at `minX + f·(W − 20)`, `f` the value's fraction **clamped**: an
/// out-of-range value is drawn at the nearer end and never written back (SA5,
/// SA6). The thumb is drawn by `paint`, so a value written under
/// `withAnimation` **snaps** (`DD-W` item 8).
///
/// **Adjusting** — an accessibility increment/decrement, or → ↑ / ← ↓ while
/// focused (`DD-T`) — starts from the clamped value and moves one step onto the
/// grid `lower + k·step` (rounding half up, never past the last grid point:
/// SA3, SA4), or 10% of the span with no step (SA1, SA7), and **writes whatever
/// it lands on, changed or not** (SA2). **A press** writes the value under the
/// pointer and a drag writes again (MetalUI's rule; the probe's click control
/// failed), through the internal `Handlers.valueTrack`; it does not focus.
///
/// **Accessibility**: `.slider`, its value printed without a trailing `.0`
/// (SA0 `5`), no label, `.increment`/`.decrement` from its
/// `AccessibilityAdjustment` handler. A caller's declared role, value or
/// adjustment handler wins; a caller's `.onKey` runs first.
///
/// **Traps** on a step that is not finite and positive, or bounds that are not
/// finite (`DD-W` item 7, `SA-J`): either would put the thumb at a non-finite
/// x. Equal bounds do not trap.
public struct Slider: Element, StyledElement {
    public var style: Style = Style()
    public var decoration: Decoration = Decoration()
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    private let read: @MainActor () -> Double
    private let write: @MainActor (Double) -> Void
    private let bounds: ClosedRange<Double>
    private let step: Double?

    nonisolated static let thumbWidth = 20.0
    nonisolated static let height = 16.0
    /// SL0's width when no width is offered.
    nonisolated static let idealWidth = 30.0

    /// A slider over `bounds`, unstepped (SwiftUI's `Slider(value:in:)`).
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1)
        where V.Stride: BinaryFloatingPoint {
        self.init(value, Double(bounds.lowerBound)...Double(bounds.upperBound), step: nil)
    }

    /// A slider over `bounds` that moves by `step` (SwiftUI's
    /// `Slider(value:in:step:)`).
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride)
        where V.Stride: BinaryFloatingPoint {
        self.init(value, Double(bounds.lowerBound)...Double(bounds.upperBound), step: Double(step))
    }

    private init<V: BinaryFloatingPoint>(_ value: Binding<V>, _ bounds: ClosedRange<Double>, step: Double?) {
        precondition(bounds.lowerBound.isFinite && bounds.upperBound.isFinite,
                     "MetalUI: a Slider's bounds must be finite (\(bounds))")
        if let step {
            precondition(step.isFinite && step > 0, "MetalUI: a Slider's step must be finite and positive (\(step))")
        }
        self.read = { Double(value.wrappedValue) }
        self.write = { value.wrappedValue = V($0) }
        self.bounds = bounds
        self.step = step
    }

    /// The leaf's answer to a proposed width (SL0): greedy on a finite width,
    /// else the ideal 30; always 16 tall.
    nonisolated static func size(proposedWidth: Double?) -> SizeD {
        let width = proposedWidth.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth
        return SizeD(width: width, height: height)
    }

    public struct Layout { public var node: LayoutNodeID }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let node = pass.lowerLegacyLeaf(style, declared: style, site: .slider) {
            pass.frame.requestNativeLeaf { proposal in
                LayoutMeasurement(size: Self.size(proposedWidth: proposal.width))
            }
        }
        return (node, Layout(node: node))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {
        let read = self.read, write = self.write, range = self.bounds, step = self.step
        let adjust: @MainActor (ControlKeys.Direction) -> Void = { direction in
            write(ValueStepping.sliderAdjusted(read(), in: range, step: step, direction))
        }
        let offset = pass.frame.activeOffset
        var composed = handlers
        composed.valueTrack = ValueTrackTarget(minX: Double(bounds.origin.x.value + offset.x.value),
                                               width: Double(bounds.size.width.value),
                                               thumb: Self.thumbWidth, bounds: range, step: step, write: write)
        composed.isFocusable = true
        let callerKey = handlers.onKey
        composed.onKey = { event in
            if let callerKey, callerKey(event) { return true }
            guard let direction = ControlKeys.sliderStep(event) else { return false }
            adjust(direction)
            return true
        }
        let adjustment = ObjectIdentifier(AccessibilityAdjustment.self)
        if composed.actions[adjustment] == nil {
            composed.actions[adjustment] = { action in
                // The key is `AccessibilityAdjustment`'s, so the cast holds by
                // construction (`Box.onAction`'s reasoning).
                let direction = (action as! AccessibilityAdjustment).direction
                adjust(direction == .increment ? .forward : .backward)
            }
        }
        if composed.axNode.role == .generic { composed.axNode.role = .slider }
        if composed.axNode.value == nil {
            composed.axNode.value = ValueStepping.accessibilityText(ValueStepping.clamp(read(), range))
        }
        pass.registerAndScope(composed, decoration, at: bounds, for: id) { }
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void, pass: inout PaintPass) {
        let fraction = ValueStepping.fraction(of: read(), in: self.bounds)
        let environment = pass.frame.environmentTop
        var decorated = decoration
        // The focus ring (`IX-H` item 2), unless the caller declared one.
        if decorated.focusBorder == nil { decorated.focusBorder = controlRing(environment) }
        let accent = controlAccent(environment)
        // The disabled look (`IX-G` item 2): the whole subtree in one 0.5 scope.
        pass.paintControl(disabled: !environment.isEnabled) {
            pass.paintDecoration(decorated, in: bounds, for: id) {
                paintTrack(bounds: bounds, fraction: fraction, accent: accent, pass: &pass)
            }
        }
    }

    private func paintTrack(bounds: Bounds<Pixels>, fraction: Double, accent: ColorToken,
                            pass: inout PaintPass) {
        let x = Double(bounds.origin.x.value), y = Double(bounds.origin.y.value)
        let w = Double(bounds.size.width.value), h = Double(bounds.size.height.value)
        let thumb = Self.thumbWidth
        let centreY = y + h / 2
        let thumbX = x + fraction * max(w - thumb, 0)
        func rect(_ x0: Double, _ y0: Double, _ width: Double, _ height: Double) -> Bounds<Pixels> {
            Bounds(origin: Point(x: Pixels(Float(x0)), y: Pixels(Float(y0))),
                   size: Size(width: Pixels(Float(max(width, 0))), height: Pixels(Float(max(height, 0)))))
        }
        let trackStart = x + thumb / 2
        let trackEnd = x + w - thumb / 2
        let radius = Corners(all: Pixels(2))
        pass.fill(rect(trackStart, centreY - 2, trackEnd - trackStart, 4), color: pass.theme[.separator],
                  cornerRadii: radius)
        let filled = thumbX + thumb / 2 - trackStart
        if filled > 0 {
            pass.fill(rect(trackStart, centreY - 2, filled, 4), color: pass.theme[accent], cornerRadii: radius)
        }
        pass.fill(rect(thumbX, centreY - Self.height / 2, thumb, Self.height), color: pass.theme[.surface],
                  cornerRadii: Corners(all: Pixels(Float(Self.height / 2))),
                  borderColor: pass.theme[.separator], borderWidths: Edges(all: Pixels(1)))
    }
}
