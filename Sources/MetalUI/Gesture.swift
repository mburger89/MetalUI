import MetalUICore
import MetalUILayout

// Plan task 12, part 1, lane 1 — SwiftUI's gesture surface (ruling `IX-B`),
// recognized as the probe measured (`IX-C`) and composed in one arena per press
// (`IX-D`). Evidence: `docs/probes/swiftui-interaction.swift`, arms G and H.

// MARK: - The closed protocol

/// A gesture: something an element can recognize from a press — SwiftUI's
/// `Gesture`, spelled as SwiftUI spells it for the three recognizers MetalUI
/// offers (`TapGesture`, `LongPressGesture`, `DragGesture`) and their two
/// combinators (`exclusively(before:)`, `simultaneously(with:)`).
///
/// **An outside module cannot conform** (ruling `IX-B`): the one requirement
/// is SPI (`@_spi(MetalUIGesture)`), and so is the type it returns, so a plain
/// importer can neither see the requirement nor name its result — pinned by
/// the plain-import guard `anOutsideTypeCannotConformToGesture`. SwiftUI lets a
/// caller compose a custom gesture through `body`; MetalUI does not (owner
/// **none**, additive: opening the protocol later breaks no caller).
///
/// **Not offered** (owner none, `IX-B`): `sequenced(before:)`,
/// `@GestureState`/`updating(_:body:)`, `GestureMask`/`including:`, the
/// `isEnabled:`/`name:` attachment overloads, a tap with a location,
/// `coordinateSpace:` (every value is in the gesture's element's local space,
/// SwiftUI's default), `SpatialTapGesture`, `MagnifyGesture`, `RotateGesture`,
/// and `TapGesture().modifiers(_:)`.
public protocol Gesture {
    /// The value the gesture reports — `Void` for a tap, `Bool` for a long
    /// press, `DragGesture.Value` for a drag.
    associatedtype Value

    /// The recognizer description the arena runs. SPI: see the type's doc.
    @_spi(MetalUIGesture) func _recognizers() -> _GestureRecognizers
}

/// What a `Gesture` hands the arena: a tree of recognizers and the callbacks
/// they run. SPI, with an internal initialiser, so only this module can make
/// one (`IX-B`).
@_spi(MetalUIGesture) public struct _GestureRecognizers {
    let node: GestureNode
    init(_ node: GestureNode) { self.node = node }
}

/// One recognizer or a composition of them — the arena's input (`IX-D`).
indirect enum GestureNode {
    case leaf(GestureLeaf)
    /// `exclusively(before:)`: earlier members first; a member may end only
    /// once every member ahead of it has failed.
    case exclusive([GestureNode])
    /// `simultaneously(with:)`: members recognize independently (`H16b`).
    case simultaneous([GestureNode])
}

/// One recognizer and the callbacks it runs.
struct GestureLeaf {
    enum Kind {
        case tap(count: Int)
        case longPress(minimumDuration: Double, maximumDistance: Float)
        case drag(minimumDistance: Float)
    }

    var kind: Kind
    var tapEnded: (@MainActor () -> Void)?
    var longPressEnded: (@MainActor (Bool) -> Void)?
    var longPressChanged: (@MainActor (Bool) -> Void)?
    /// `onLongPressGesture`'s `onPressingChanged` only (`IX-C` item 4).
    var pressingChanged: (@MainActor (Bool) -> Void)?
    var dragChanged: (@MainActor (DragGesture.Value) -> Void)?
    var dragEnded: (@MainActor (DragGesture.Value) -> Void)?

    init(kind: Kind) { self.kind = kind }
}

// MARK: - The three recognizers

/// SwiftUI's `TapGesture` (ruling `IX-C` items 1–3): ends on the **release**,
/// fails once the pointer moves 5 pt or more from the press or is released
/// outside its element; `count: n` ends on the release whose click count is
/// `n`, counted from the press the arena began with.
///
/// `onEnded(_:)` returns a `TapGesture` with the callback stored, not SwiftUI's
/// `_EndedGesture` wrapper (`IX-B`): the spelling is SwiftUI's; only a caller
/// naming the wrapper type sees a difference.
public struct TapGesture: Gesture {
    public typealias Value = Void

    /// The number of clicks that end the gesture.
    public var count: Int
    var ended: (@MainActor () -> Void)?

    public init(count: Int = 1) {
        self.count = count
    }

    /// Runs `action` when the tap ends.
    public func onEnded(_ action: @escaping @MainActor () -> Void) -> TapGesture {
        var copy = self
        copy.ended = action
        return copy
    }

    @_spi(MetalUIGesture) public func _recognizers() -> _GestureRecognizers {
        var leaf = GestureLeaf(kind: .tap(count: count))
        leaf.tapEnded = ended
        return _GestureRecognizers(.leaf(leaf))
    }
}

/// SwiftUI's `LongPressGesture` (ruling `IX-C` item 4): ends **while still
/// held**, at the first display-link tick at least `minimumDuration` after the
/// press's stamp tick; a quick click ends nothing; it fails once the pointer
/// moves `maximumDistance` or more. `onChanged(_:)` reports `true` when the
/// press begins (MetalUI's choice: SwiftUI's `onChanged` for a long press is
/// unmeasured).
public struct LongPressGesture: Gesture {
    public typealias Value = Bool

    public var minimumDuration: Double
    public var maximumDistance: Pixels
    var ended: (@MainActor (Bool) -> Void)?
    var changed: (@MainActor (Bool) -> Void)?
    var pressing: (@MainActor (Bool) -> Void)?

    public init(minimumDuration: Double = 0.5, maximumDistance: Pixels = Pixels(10)) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }

    /// Runs `action` when the long press ends, with `true`.
    public func onEnded(_ action: @escaping @MainActor (Bool) -> Void) -> LongPressGesture {
        var copy = self
        copy.ended = action
        return copy
    }

    /// Runs `action` with `true` when the press begins.
    public func onChanged(_ action: @escaping @MainActor (Bool) -> Void) -> LongPressGesture {
        var copy = self
        copy.changed = action
        return copy
    }

    @_spi(MetalUIGesture) public func _recognizers() -> _GestureRecognizers {
        var leaf = GestureLeaf(kind: .longPress(minimumDuration: minimumDuration,
                                                maximumDistance: maximumDistance.value))
        leaf.longPressEnded = ended
        leaf.longPressChanged = changed
        leaf.pressingChanged = pressing
        return _GestureRecognizers(.leaf(leaf))
    }
}

/// SwiftUI's `DragGesture` (ruling `IX-C` item 5): reports `onChanged` from
/// the first move whose distance from the press is **at least**
/// `minimumDistance`, then on every move, and `onEnded` at the release wherever
/// it lands; a drag that never reaches its minimum reports nothing, and
/// `minimumDistance: 0` reports a change and an end for a click. Values are in
/// the element's **local**, y-down space (SwiftUI's default `.local`).
public struct DragGesture: Gesture {
    /// A drag's state: where it started and is, in the element's local space.
    public struct Value: Equatable, Sendable {
        public var startLocation: Point<Pixels>
        public var location: Point<Pixels>
        public var translation: Size<Pixels>

        public init(startLocation: Point<Pixels>, location: Point<Pixels>) {
            self.startLocation = startLocation
            self.location = location
            self.translation = Size(width: location.x - startLocation.x,
                                    height: location.y - startLocation.y)
        }
    }

    public var minimumDistance: Pixels
    var changed: (@MainActor (Value) -> Void)?
    var ended: (@MainActor (Value) -> Void)?

    public init(minimumDistance: Pixels = Pixels(10)) {
        self.minimumDistance = minimumDistance
    }

    /// Runs `action` on every reported move.
    public func onChanged(_ action: @escaping @MainActor (Value) -> Void) -> DragGesture {
        var copy = self
        copy.changed = action
        return copy
    }

    /// Runs `action` at the release.
    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> DragGesture {
        var copy = self
        copy.ended = action
        return copy
    }

    @_spi(MetalUIGesture) public func _recognizers() -> _GestureRecognizers {
        var leaf = GestureLeaf(kind: .drag(minimumDistance: minimumDistance.value))
        leaf.dragChanged = changed
        leaf.dragEnded = ended
        return _GestureRecognizers(.leaf(leaf))
    }
}

// MARK: - Composition

/// `first.exclusively(before: second)`: `first` is tried first; `second` may
/// end only if `first` failed (`H15a`).
public struct ExclusiveGesture<First: Gesture, Second: Gesture>: Gesture {
    public enum Value {
        case first(First.Value)
        case second(Second.Value)
    }

    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    @_spi(MetalUIGesture) public func _recognizers() -> _GestureRecognizers {
        _GestureRecognizers(.exclusive([first._recognizers().node, second._recognizers().node]))
    }
}

/// `first.simultaneously(with: second)`: both recognize independently (`H16a`,
/// `H16b`).
public struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture {
    public struct Value {
        public var first: First.Value?
        public var second: Second.Value?
    }

    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    @_spi(MetalUIGesture) public func _recognizers() -> _GestureRecognizers {
        _GestureRecognizers(.simultaneous([first._recognizers().node, second._recognizers().node]))
    }
}

extension Gesture {
    /// A gesture that tries `self` first and `other` only if `self` fails.
    public func exclusively<Other: Gesture>(before other: Other) -> ExclusiveGesture<Self, Other> {
        ExclusiveGesture(self, other)
    }

    /// A gesture that recognizes `self` and `other` independently.
    public func simultaneously<Other: Gesture>(with other: Other) -> SimultaneousGesture<Self, Other> {
        SimultaneousGesture(self, other)
    }
}

// MARK: - Attachment

/// One gesture attached to an element, with the priority its attaching
/// modifier gave it (`IX-D` items 3–4).
struct GestureAttachment {
    enum Priority {
        /// `gesture(_:)`, `onTapGesture`, `onLongPressGesture`.
        case normal
        /// `highPriorityGesture(_:)`.
        case high
        /// `simultaneousGesture(_:)`.
        case simultaneous
    }

    var priority: Priority
    var node: GestureNode

    init<G: Gesture>(_ gesture: G, priority: Priority) {
        self.priority = priority
        self.node = gesture._recognizers().node
    }
}
