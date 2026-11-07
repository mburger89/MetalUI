import Observation

/// Where a ``CodeView`` is scrolled: a display row with a fraction, and a horizontal offset in points.
///
/// **Vertical is in display rows, not pixels** (`CV-T`): two views of one diff keep the same display rows
/// (virtual filler rows make them equal), so a position in rows is the same place in both at any font size
/// or scale, where a pixel offset would drift apart at the first difference in line height. The fraction is
/// the share of the top row scrolled off, in `0..<1`.
public struct CodeScrollPosition: Equatable, Sendable {
    /// The top display row plus the fraction of it scrolled off: `12.5` is half of row 12 hidden.
    public var row: Double
    /// The horizontal offset in points.
    public var x: Double

    /// A position.
    public init(row: Double = 0, x: Double = 0) {
        self.row = row
        self.x = x
    }
}

/// The scroll position of a ``CodeView``, observable and settable (Alloy's scroll sync, `CV-T`).
///
/// Read ``position`` to show it (it is observed); assign it to scroll the view, once per change: the view
/// adopts the assigned value on its next frame and **does not report it back** through
/// ``CodeView/onScroll(_:)``, so two views that each call the other's ``position`` setter from `onScroll`
/// settle after one hop and never feed back. A position the view clamps (past the end) is stored clamped.
/// Share one state with a view with ``CodeView/scrollState(_:)``.
@MainActor @Observable
public final class CodeScrollState {
    @ObservationIgnored private var stored: CodeScrollPosition
    /// Bumped by the setter only; the one thing a view observes, so its own reports never wake it.
    private(set) var revision: UInt64 = 0

    /// A state at `position`.
    public init(_ position: CodeScrollPosition = CodeScrollPosition()) {
        stored = position
    }

    /// The position: the view's last frame's, or the one assigned since. Assigning scrolls the view on its
    /// next frame without calling `onScroll`.
    public var position: CodeScrollPosition {
        get {
            access(keyPath: \.position)
            return stored
        }
        set {
            withMutation(keyPath: \.position) {
                stored = newValue
                revision &+= 1
            }
        }
    }

    /// What the view assigned itself (a wheel, a drag, a clamp, an edit above it): observers of
    /// ``position`` see it, the view does not.
    func publish(_ value: CodeScrollPosition) {
        withMutation(keyPath: \.position) { stored = value }
    }

    /// The stored value without registering a read.
    var current: CodeScrollPosition { stored }
}
