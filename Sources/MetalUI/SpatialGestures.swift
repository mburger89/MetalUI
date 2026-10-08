import MetalUICore
import MetalUILayout

// Input APIs, lane 2 — the gestures SwiftUI has for canvases and viewports
// (rulings `CI-B`, `CI-C`, `CI-F`; spec
// `docs/superpowers/specs/2026-10-08-input-apis-design.md` §1.2). Evidence:
// `docs/probes/swiftui-input-apis.swift`, arms T, M, Q and R. Each is a leaf
// of the one arena (`IX-D`): a spatial tap is a tap that also records a
// point; a magnify or rotate is live only in a pinch arena (`CI-D`).

/// The space a gesture reports its points in — SwiftUI's `CoordinateSpace`,
/// narrowed to the two cases MetalUI offers (`CI-B` item 3).
///
/// - `.local`: the gesture element's own space, top-leading origin, with its
///   render effects undone (`Hitbox.localPoint`) — SwiftUI's default.
/// - `.global`: **the window's content space** — the point a `MouseEvent`
///   carries. SwiftUI's `.global` in a titled window read 32 points lower than
///   the content view's point (probe `T2`; divergence 139).
///
/// `.named(_:)` and `.coordinateSpace(_:)` are not offered (`CI-A`).
public enum CoordinateSpace: Sendable, Hashable {
    /// The gesture element's own space.
    case local
    /// The window's content space (divergence 139).
    case global
}

/// A mouse button, by AppKit's `buttonNumber` (`CI-F` item 2): 0 the primary,
/// 1 the secondary, 2 the middle, 3 back, 4 forward. **MetalUI-only**: SwiftUI
/// has no button type and no gesture follows any button but the primary
/// (probe `R2`/`R4`, census).
public struct MouseButton: Sendable, Hashable {
    /// AppKit's button number; SDL's buttons are renumbered to it (`CI-E`).
    public let buttonNumber: Int

    init(buttonNumber: Int) { self.buttonNumber = buttonNumber }

    /// The primary (left) button, 0.
    public static let primary = MouseButton(buttonNumber: 0)
    /// The secondary (right) button, 1 — on AppKit also a control-press.
    public static let secondary = MouseButton(buttonNumber: 1)
    /// The middle button, 2.
    public static let middle = MouseButton(buttonNumber: 2)
    /// Any button by its number: `.other(3)` is back, `.other(4)` forward.
    public static func other(_ buttonNumber: Int) -> MouseButton { MouseButton(buttonNumber: buttonNumber) }
}

// MARK: - SpatialTapGesture

/// SwiftUI's `SpatialTapGesture` (ruling `CI-B` item 1): a `TapGesture` that
/// reports where it ended — recognized exactly as a tap (`IX-C`: slop 5, a
/// sequence counted from the arena's first press), its `location` **the
/// release that ends it** (MetalUI's choice: within the slop the press and the
/// release differ by under 5 points; probe `T1`/`T4` pressed and released at
/// one point) in `coordinateSpace`.
public struct SpatialTapGesture: Gesture {
    /// Where the tap ended.
    public struct Value: Equatable, Sendable {
        /// The release point, in the gesture's coordinate space.
        public var location: Point<Pixels>
    }

    /// The number of clicks that end the gesture.
    public var count: Int
    /// The space `Value.location` is in.
    public var coordinateSpace: CoordinateSpace
    var ended: (@MainActor (Value) -> Void)?

    /// A tap that ends after `count` clicks, reporting its location in
    /// `coordinateSpace`.
    public init(count: Int = 1, coordinateSpace: CoordinateSpace = .local) {
        self.count = count
        self.coordinateSpace = coordinateSpace
    }

    /// Runs `action` with the tap's location when it ends.
    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> SpatialTapGesture {
        var copy = self
        copy.ended = action
        return copy
    }

    @_spi(MetalUIGesture) public func _recognizers() -> _GestureRecognizers {
        var leaf = GestureLeaf(kind: .tap(count: count, spatial: coordinateSpace))
        leaf.spatialTapEnded = ended
        return _GestureRecognizers(.leaf(leaf))
    }
}

// MARK: - MagnifyGesture

/// SwiftUI's `MagnifyGesture` (rulings `CI-C`, `CI-D`): a trackpad pinch,
/// recognized in its own **pinch arena** — formed from the one ranking at the
/// pinch's position, never by a press (a press arena fails it at formation, so
/// `MagnifyGesture().exclusively(before: DragGesture())` drags on a press).
///
/// `magnification` is **cumulative and additive from 1** — `1 + Σ` of the
/// platform's per-event deltas (AppKit +0.1, +0.1 → 1.1, 1.2; probe `M1`).
/// The first `onChanged` comes once |magnification − 1| reaches
/// `minimumScaleDelta`, then every event; `onEnded` at the platform's
/// ended or cancelled phase **only if it reported a change** (`CI-C` item 4).
/// A magnify and a rotate never block each other (`CI-D` item 3).
///
/// No pinch is synthesized from a control- or ⌘-wheel (probe `M3`): a wheel
/// reaches `.onScrollWheel` with its modifiers. SDL delivers a pinch on macOS,
/// X11 and Wayland, none on Windows (`CI-K`). `time` and `velocity` are not
/// offered (`CI-A`).
public struct MagnifyGesture: Gesture {
    /// A pinch's state.
    public struct Value: Equatable, Sendable {
        /// `1 + Σ` of the pinch's deltas.
        public var magnification: Double
        /// The pointer at the gesture's first event, in the declaring element's
        /// local space; fixed for the gesture.
        public var startLocation: Point<Pixels>
        /// `startLocation` as a fraction of the element's hit region.
        public var startAnchor: UnitPoint
    }

    /// How far `magnification` must move from 1 before the first change.
    public var minimumScaleDelta: Double
    var changed: (@MainActor (Value) -> Void)?
    var ended: (@MainActor (Value) -> Void)?

    /// A pinch that reports once its magnification moves `minimumScaleDelta`
    /// from 1.
    public init(minimumScaleDelta: Double = 0.01) {
        self.minimumScaleDelta = minimumScaleDelta
    }

    /// Runs `action` on every reported change.
    public func onChanged(_ action: @escaping @MainActor (Value) -> Void) -> MagnifyGesture {
        var copy = self
        copy.changed = action
        return copy
    }

    /// Runs `action` when the pinch ends, if it reported a change.
    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> MagnifyGesture {
        var copy = self
        copy.ended = action
        return copy
    }

    @_spi(MetalUIGesture) public func _recognizers() -> _GestureRecognizers {
        var leaf = GestureLeaf(kind: .magnify(minimumScaleDelta: minimumScaleDelta))
        leaf.magnifyChanged = changed
        leaf.magnifyEnded = ended
        return _GestureRecognizers(.leaf(leaf))
    }
}

// MARK: - RotateGesture

/// SwiftUI's `RotateGesture` (rulings `CI-C`, `CI-D`): a two-finger trackpad
/// twist, in the pinch arena as `MagnifyGesture` is. `rotation` is
/// **cumulative and positive clockwise** on screen (y down) — the negative of
/// AppKit's `NSEvent.rotation`, negated once at the seam (probe `Q1`). Its
/// minimum, values and `onEnded` rule are `MagnifyGesture`'s. **SDL has no
/// rotate event**: on SDL it never fires (`CI-K` item 3).
public struct RotateGesture: Gesture {
    /// A rotation's state.
    public struct Value: Equatable, Sendable {
        /// The cumulative rotation, clockwise-positive.
        public var rotation: Angle
        /// The pointer at the gesture's first event, in the declaring element's
        /// local space; fixed for the gesture.
        public var startLocation: Point<Pixels>
        /// `startLocation` as a fraction of the element's hit region.
        public var startAnchor: UnitPoint
    }

    /// How far the rotation must turn before the first change.
    public var minimumAngleDelta: Angle
    var changed: (@MainActor (Value) -> Void)?
    var ended: (@MainActor (Value) -> Void)?

    /// A rotation that reports once it has turned `minimumAngleDelta`.
    public init(minimumAngleDelta: Angle = .degrees(1)) {
        self.minimumAngleDelta = minimumAngleDelta
    }

    /// Runs `action` on every reported change.
    public func onChanged(_ action: @escaping @MainActor (Value) -> Void) -> RotateGesture {
        var copy = self
        copy.changed = action
        return copy
    }

    /// Runs `action` when the rotation ends, if it reported a change.
    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> RotateGesture {
        var copy = self
        copy.ended = action
        return copy
    }

    @_spi(MetalUIGesture) public func _recognizers() -> _GestureRecognizers {
        var leaf = GestureLeaf(kind: .rotate(minimumAngleDelta: minimumAngleDelta.degrees))
        leaf.rotateChanged = changed
        leaf.rotateEnded = ended
        return _GestureRecognizers(.leaf(leaf))
    }
}
