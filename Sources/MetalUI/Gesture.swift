import Foundation
import MetalUICore
import MetalUILayout

// Plan task 12, part 1, lane 1 — SwiftUI's gesture surface (ruling `IX-B`),
// recognized as the probe measured (`IX-C`) and composed in one arena per press
// (`IX-D`). Evidence: `docs/probes/swiftui-interaction.swift`, arms G and H.

// MARK: - The closed protocol

/// A gesture: something an element can recognize from a press or a pinch —
/// SwiftUI's `Gesture`, spelled as SwiftUI spells it. The recognizers are
/// `TapGesture`, `SpatialTapGesture`, `LongPressGesture`, `DragGesture`, and — in
/// a pinch arena, `CI-D` — `MagnifyGesture` and `RotateGesture`; the combinators
/// are `exclusively(before:)`, `simultaneously(with:)` and `sequenced(before:)`.
///
/// **A custom gesture is a struct with a `body`** (ruling `GE-A`, SwiftUI's
/// shape): `var body: some Gesture { LongPressGesture().sequenced(before: DragGesture()) }`.
/// Its `Value` is its body's, so name the body's type (`var body: SequenceGesture<…>`)
/// when a caller needs the value spelled. The recognizer requirement stays SPI
/// (`@_spi(MetalUIGesture)`): an outside module cannot conform by describing
/// recognizers itself, only by composing the ones offered here — pinned by the
/// plain-import guards `anOutsideTypeCanConformToGestureThroughABody` and
/// `anOutsideTypeCannotDescribeRecognizersItself`.
///
/// **Not offered** (owner none, `IX-B`, `CI-A`, `GE-A`): `GestureMask`/`including:`
/// (carried, `GE-H`), `AnyGesture` and `Gesture.map`, the
/// `isEnabled:`/`name:` attachment overloads, `CoordinateSpace.named(_:)` and
/// `.coordinateSpace(_:)` (`.local` and `.global` only), `GestureInputKinds`/
/// `inputKinds:`, `TapGesture().modifiers(_:)`, and a composite's `onCancelled`.
/// `@GestureState` and `updating(_:body:)` are built (`GS-A`…`GS-G`, record §135),
/// on the recognizers and — since `GE-` — on every gesture through
/// ``GestureStateGesture``. `onCancelled(_:)` on `DragGesture`, `MagnifyGesture`
/// and `RotateGesture` (`IF-A`, `IF-E`) stays for a caller who wants the event.
public protocol Gesture {
    /// The value the gesture reports — `Void` for a tap, `Bool` for a long
    /// press, `DragGesture.Value` for a drag, a composite's own enum or struct
    /// for `sequenced`, `exclusively` and `simultaneously`.
    associatedtype Value = Body.Value

    /// The gesture a custom gesture is made of; `Never` for a recognizer
    /// MetalUI provides.
    associatedtype Body: Gesture

    /// A custom gesture's composition. Recognizers MetalUI provides have
    /// `Body == Never` and never evaluate it.
    var body: Body { get }

}

extension Gesture where Body == Never {
    // Public by necessity (a public type's witness of a public requirement): like SwiftUI's, a type that forgets
    // its `body` still compiles and traps when evaluated (`GE-A`).
    /// A recognizer MetalUI provides has no body.
    public var body: Never { fatalError("\(Self.self) is a primitive gesture and has no body") }
}

/// A gesture MetalUI recognizes itself: the arena's description of it (internal — an outside module can only
/// compose, by a `body`, ruling `GE-A`).
protocol PrimitiveGesture: Gesture {
    func _recognizers() -> _GestureRecognizers
}

/// The arena's description of `gesture`: a primitive's own, else its `body`'s, recursively (`GE-A`).
func recognizerNode<G: Gesture>(of gesture: G) -> GestureNode {
    if let primitive = gesture as? any PrimitiveGesture { return primitive._recognizers().node }
    return recognizerNode(of: gesture.body)
}

extension Never: Gesture {
    /// `Never` is the body of every primitive gesture.
    public typealias Value = Never
    /// `Never` is the body of every primitive gesture.
    public typealias Body = Never
}

/// What a primitive `Gesture` hands the arena: a tree of recognizers and the callbacks they run.
struct _GestureRecognizers {
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
    /// `sequenced(before:)` (ruling `GE-B`): the second member is gated until the first has ended.
    case sequence(GestureNode, GestureNode)
    /// A composite node with the typed machinery that assembles and reports its value (`GE-C`).
    case hooked(GestureNode, CompositeHooks)
}

/// What a composite gesture hangs on its node (ruling `GE-C`): the taps a parent or a wrapper
/// (`onChanged`, `onEnded`, `updating`) listens with, the reset hooks, and the three closures the arena
/// calls — `flush` once at the end of each event's resolution (a composite reports once per event),
/// `ended` when the node ends, `reset` when it ends, fails or is cancelled. Values travel as `Any`;
/// the typed gesture that made the node casts them back.
final class CompositeHooks: @unchecked Sendable {
    var changedTaps: [@MainActor (Any) -> Void] = []
    var endedTaps: [@MainActor (Any) -> Void] = []
    var finishes: [@MainActor () -> Void] = []
    var flush: (@MainActor () -> Void)?
    var ended: (@MainActor () -> Void)?
    var reset: (@MainActor () -> Void)?
}

extension GestureNode {
    /// Lets `changed` and `ended` hear this node's values. A leaf's typed callbacks are wrapped in place (the
    /// tap runs after the leaf's own, in declaration order, `GS-E`); a composite node adds to its hooks.
    mutating func tap(changed: (@MainActor (Any) -> Void)?, ended: (@MainActor (Any) -> Void)?) {
        switch self {
        case .leaf(var leaf):
            leaf.tap(changed: changed, ended: ended)
            self = .leaf(leaf)
        case .hooked(_, let hooks):
            if let changed { hooks.changedTaps.append(changed) }
            if let ended { hooks.endedTaps.append(ended) }
        case .exclusive, .simultaneous, .sequence:
            break   // every composite is built hooked
        }
    }

    /// Adds a reset to run when the node ends, fails or is cancelled (`GS-C`).
    mutating func addFinish(_ finish: @escaping @MainActor () -> Void) {
        switch self {
        case .leaf(var leaf):
            let old = leaf.finished
            leaf.finished = { old?(); finish() }
            self = .leaf(leaf)
        case .hooked(_, let hooks):
            hooks.finishes.append(finish)
        case .exclusive, .simultaneous, .sequence:
            break
        }
    }
}

/// One recognizer and the callbacks it runs.
struct GestureLeaf {
    enum Kind {
        /// `spatial` is a `SpatialTapGesture`'s space (`CI-B`), `nil` for a
        /// `TapGesture`.
        case tap(count: Int, spatial: CoordinateSpace?)
        case longPress(minimumDuration: Double, maximumDistance: Float)
        /// Live in a press arena for the primary button only, in a button
        /// arena for its own (`CI-F` item 3).
        case drag(minimumDistance: Float, coordinateSpace: CoordinateSpace, button: MouseButton)
        /// A `.draggable` (ruling `DN-D`): ready on the first move of more
        /// than zero points, failed at the release.
        case draggable
        /// A `WindowDragGesture` (ruling `WD-C`): live in a press arena only,
        /// ready on the first move of at least `tapSlop` from the press.
        case windowDrag
        /// Live only in a pinch arena (`CI-D` item 1).
        case magnify(minimumScaleDelta: Double)
        /// Live only in a pinch arena; the minimum in degrees.
        case rotate(minimumAngleDelta: Double)
    }

    var kind: Kind
    var tapEnded: (@MainActor () -> Void)?
    var spatialTapEnded: (@MainActor (SpatialTapGesture.Value) -> Void)?
    var magnifyChanged: (@MainActor (MagnifyGesture.Value) -> Void)?
    var magnifyEnded: (@MainActor (MagnifyGesture.Value) -> Void)?
    var rotateChanged: (@MainActor (RotateGesture.Value) -> Void)?
    var rotateEnded: (@MainActor (RotateGesture.Value) -> Void)?
    var longPressEnded: (@MainActor (Bool) -> Void)?
    var longPressChanged: (@MainActor (Bool) -> Void)?
    /// `onLongPressGesture`'s `onPressingChanged` only (`IX-C` item 4).
    var pressingChanged: (@MainActor (Bool) -> Void)?
    var dragChanged: (@MainActor (DragGesture.Value) -> Void)?
    var dragEnded: (@MainActor (DragGesture.Value) -> Void)?
    /// `onCancelled` of a drag, a magnify, a rotate (`IF-E`).
    var dragCancelled: (@MainActor () -> Void)?
    var magnifyCancelled: (@MainActor () -> Void)?
    var rotateCancelled: (@MainActor () -> Void)?
    /// A draggable's payload (`DN-D`); `nil` for every other kind.
    var dragSource: DragSource?
    /// Resets every `GestureState` the leaf's `updating` calls write (`GS-C`): queued once, by `fail(_:)` or just
    /// before the ended callback.
    var finished: (@MainActor () -> Void)?

    init(kind: Kind) { self.kind = kind }

    /// Wraps the callbacks this kind reports so `changed` and `ended` also hear its value (`GE-C`). A kind that
    /// reports no value (a draggable, a window drag) is left alone; a tap has no change.
    mutating func tap(changed: (@MainActor (Any) -> Void)?, ended: (@MainActor (Any) -> Void)?) {
        switch kind {
        case .tap(_, let spatial):
            guard let ended else { return }
            if spatial == nil {
                let old = tapEnded
                tapEnded = { old?(); ended(()) }
            } else {
                let old = spatialTapEnded
                spatialTapEnded = { old?($0); ended($0) }
            }
        case .longPress:
            if let changed { let old = longPressChanged; longPressChanged = { old?($0); changed($0) } }
            if let ended { let old = longPressEnded; longPressEnded = { old?($0); ended($0) } }
        case .drag:
            if let changed { let old = dragChanged; dragChanged = { old?($0); changed($0) } }
            if let ended { let old = dragEnded; dragEnded = { old?($0); ended($0) } }
        case .magnify:
            if let changed { let old = magnifyChanged; magnifyChanged = { old?($0); changed($0) } }
            if let ended { let old = magnifyEnded; magnifyEnded = { old?($0); ended($0) } }
        case .rotate:
            if let changed { let old = rotateChanged; rotateChanged = { old?($0); changed($0) } }
            if let ended { let old = rotateEnded; rotateEnded = { old?($0); ended($0) } }
        case .draggable, .windowDrag:
            break
        }
    }
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
public struct TapGesture: Gesture, PrimitiveGesture {
    /// A recognizer MetalUI provides has no body.
    public typealias Body = Never
    /// A tap reports no value.
    public typealias Value = Void

    /// The number of clicks that end the gesture.
    public var count: Int
    var ended: (@MainActor () -> Void)?

    /// A tap that ends after `count` clicks.
    public init(count: Int = 1) {
        self.count = count
    }

    /// Runs `action` when the tap ends.
    public func onEnded(_ action: @escaping @MainActor () -> Void) -> TapGesture {
        var copy = self
        copy.ended = action
        return copy
    }

    /// Accepted for SwiftUI's source compatibility and **never run**: a tap reports no change, and SwiftUI's own
    /// `updating` never runs for one (probe `G2`, `GS-B`).
    @MainActor public func updating<StateValue>(_ state: GestureState<StateValue>,
                                     body: @escaping @MainActor (Void, inout StateValue, inout Transaction) -> Void) -> TapGesture {
        self
    }

    func _recognizers() -> _GestureRecognizers {
        var leaf = GestureLeaf(kind: .tap(count: count, spatial: nil))
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
public struct LongPressGesture: Gesture, PrimitiveGesture {
    /// A recognizer MetalUI provides has no body.
    public typealias Body = Never
    /// Whether the press is still held at the minimum duration.
    public typealias Value = Bool

    /// Seconds the press must be held before the gesture ends.
    public var minimumDuration: Double
    /// How far the pointer may move before the gesture fails.
    public var maximumDistance: Pixels
    var ended: (@MainActor (Bool) -> Void)?
    var changed: (@MainActor (Bool) -> Void)?
    var pressing: (@MainActor (Bool) -> Void)?
    var updates: [GestureUpdate<Bool>] = []

    /// A long press held for `minimumDuration` seconds without moving
    /// `maximumDistance` or more.
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

    /// Writes `state` with `body` on every change this gesture reports, and returns it to its initial value when the
    /// gesture ends, fails or is cancelled (`GS-B`, `GS-C`). `body` starts from the value committed before the
    /// event; set `transaction.animation` to animate the update. Runs in declaration order against `onChanged`.
    @MainActor public func updating<StateValue>(_ state: GestureState<StateValue>,
                                     body: @escaping @MainActor (Bool, inout StateValue, inout Transaction) -> Void) -> LongPressGesture {
        var copy = self
        copy.updates.append(GestureUpdate(state, afterChanged: changed != nil, body: body))
        return copy
    }

    func _recognizers() -> _GestureRecognizers {
        var leaf = GestureLeaf(kind: .longPress(minimumDuration: minimumDuration,
                                                maximumDistance: maximumDistance.value))
        leaf.longPressEnded = ended
        leaf.longPressChanged = composeChanged(changed, updates)
        leaf.finished = composeFinished(updates)
        leaf.pressingChanged = pressing
        return _GestureRecognizers(.leaf(leaf))
    }
}

/// SwiftUI's `DragGesture` (ruling `IX-C` item 5): reports `onChanged` from
/// the first move whose distance from the press is **at least**
/// `minimumDistance`, then on every move, and `onEnded` at the release wherever
/// it lands; a drag that never reaches its minimum reports nothing, and
/// `minimumDistance: 0` reports a change and an end for a click. Values are in
/// `coordinateSpace` — the element's **local**, y-down space by default
/// (SwiftUI's `.local`), or the window's content space (`.global`, divergence
/// 139).
///
/// **`button:` is MetalUI-only** (ruling `CI-F`; SwiftUI's drag follows the
/// primary button alone, probe `R2`/`R4`): a drag for `.secondary`,
/// `.middle` or `.other(n)` is recognized in that button's own arena, formed
/// from the one ranking at the press — never in the primary press's, so every
/// primary-only behaviour keeps `MN-B`. With a secondary drag on the pressed
/// chain a context menu opens on the release, at the press point, and only if
/// no such drag reached its minimum (`CI-F` item 4).
public struct DragGesture: Gesture, PrimitiveGesture {
    /// A recognizer MetalUI provides has no body.
    public typealias Body = Never
    /// A drag's state: where it started and is, in the gesture's coordinate
    /// space, and the modifier keys of the event that produced it.
    public struct Value: Equatable, Sendable {
        /// Where the press began.
        public var startLocation: Point<Pixels>
        /// Where the pointer is now.
        public var location: Point<Pixels>
        /// `location` minus `startLocation`.
        public var translation: Size<Pixels>
        /// The modifier keys held at the event that produced this value — the
        /// press for a `minimumDistance: 0` first change, each move, the
        /// release for `onEnded` (ruling `CI-G`). **MetalUI-only**: SwiftUI's
        /// value has none (divergence 140). A modifier change without a move
        /// reports nothing.
        public var modifiers: EventModifiers
        /// The click count of the press that began the drag — the platform's
        /// (`NSEvent.clickCount`, which honours the user's double-click speed;
        /// SDL's `clicks`), the same in every `onChanged` and the `onEnded`; 1
        /// for a value built without one (ruling `IF-C`). **MetalUI-only**:
        /// SwiftUI's value has none (divergence 235).
        public var clickCount: Int
        /// When the event that produced this value occurred, as the platform stamped it (`Date(timeIntervalSinceReferenceDate:)`
        /// of the event's timestamp, which is how SwiftUI reads it, probe `D0`): deterministic from the events,
        /// never the wall clock (probes `D2`, `D3`). The reference date for a value built without one.
        public var time: Date
        /// The pointer's velocity in points per second, y down, in the gesture's coordinate space: three parts
        /// of the previous interval's speed to one of this interval's (probe `D6`, `D7`, `D11`, ruling `GE-F`);
        /// zero for the first event and for a value built without one.
        public var velocity: Size<Pixels>

        /// Where the drag would end if it kept `velocity` for a quarter of a second — `location` plus that
        /// travel (probe `D1`, `D4`, `D5`, ruling `GE-F`).
        public var predictedEndLocation: Point<Pixels> {
            Point(x: location.x + velocity.width / 4, y: location.y + velocity.height / 4)
        }

        /// `translation` plus a quarter of a second of `velocity` (probe `D1`).
        public var predictedEndTranslation: Size<Pixels> {
            Size(width: translation.width + velocity.width / 4, height: translation.height + velocity.height / 4)
        }

        /// A drag value with no modifiers; `translation` is derived.
        public init(startLocation: Point<Pixels>, location: Point<Pixels>) {
            self.init(startLocation: startLocation, location: location, modifiers: [], clickCount: 1)
        }

        /// A drag value; `translation` is derived. `clickCount` defaults to 1; `time` to the reference date and
        /// `velocity` to zero.
        public init(startLocation: Point<Pixels>, location: Point<Pixels>, modifiers: EventModifiers,
                    clickCount: Int = 1, time: Date = Date(timeIntervalSinceReferenceDate: 0),
                    velocity: Size<Pixels> = Size(width: Pixels(0), height: Pixels(0))) {
            self.startLocation = startLocation
            self.location = location
            self.translation = Size(width: location.x - startLocation.x,
                                    height: location.y - startLocation.y)
            self.modifiers = modifiers
            self.clickCount = clickCount
            self.time = time
            self.velocity = velocity
        }
    }

    /// How far the pointer must move before the drag begins.
    public var minimumDistance: Pixels
    /// The space the values are in.
    public var coordinateSpace: CoordinateSpace
    /// The button the drag follows (MetalUI-only, `CI-F`).
    public var button: MouseButton
    var changed: (@MainActor (Value) -> Void)?
    var ended: (@MainActor (Value) -> Void)?
    var cancelled: (@MainActor () -> Void)?
    var updates: [GestureUpdate<Value>] = []

    /// A drag with `button` that begins once the pointer moves
    /// `minimumDistance`, reporting values in `coordinateSpace`.
    public init(minimumDistance: Pixels = Pixels(10), coordinateSpace: CoordinateSpace = .local,
                button: MouseButton = .primary) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
        self.button = button
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

    /// Writes `state` with `body` on every change this gesture reports, and returns it to its initial value when the
    /// gesture ends, fails or is cancelled (`GS-B`, `GS-C`). `body` starts from the value committed before the
    /// event; set `transaction.animation` to animate the update. Runs in declaration order against `onChanged`.
    @MainActor public func updating<StateValue>(_ state: GestureState<StateValue>,
                                     body: @escaping @MainActor (Value, inout StateValue, inout Transaction) -> Void) -> DragGesture {
        var copy = self
        copy.updates.append(GestureUpdate(state, afterChanged: changed != nil, body: body))
        return copy
    }

    /// Runs `action` once if the drag had reported a change and its gesture
    /// then ended **without** `onEnded` (ruling `IF-E`): the arena was dropped
    /// because another press replaced it, a button's release was lost (a move
    /// with no button down), a draggable's preview took over, or the window
    /// closed. **MetalUI-only** (divergence 236): SwiftUI never calls `onEnded`
    /// for a cancelled gesture and tells its owner only through `@GestureState`,
    /// which MetalUI offers too (`GS-A`); this callback is for a caller who wants the event. Never after `onEnded`, never for a drag
    /// that did not begin, and not when the gesture is disabled or its owner
    /// removed mid-drag (the closure belongs to state that is reset, `IF-K`
    /// item 3). Reset what `onChanged` set here.
    public func onCancelled(_ action: @escaping @MainActor () -> Void) -> DragGesture {
        var copy = self
        copy.cancelled = action
        return copy
    }

    func _recognizers() -> _GestureRecognizers {
        var leaf = GestureLeaf(kind: .drag(minimumDistance: minimumDistance.value,
                                           coordinateSpace: coordinateSpace, button: button))
        leaf.dragChanged = composeChanged(changed, updates)
        leaf.finished = composeFinished(updates)
        leaf.dragEnded = ended
        leaf.dragCancelled = cancelled
        return _GestureRecognizers(.leaf(leaf))
    }
}

// MARK: - Composition

/// A composite's running state between its members' taps and the arena's flush (`GE-C`): the latest
/// value to report (`dirty` when the event changed it) and what is needed to build the end value.
final class CompositeState<Latest, End>: @unchecked Sendable {
    var latest: Latest?
    var dirty = false
    var end: End?
    var aux: [Any] = []
    func reset() { latest = nil; dirty = false; end = nil; aux = [] }
}

/// `first.exclusively(before: second)`: `first` is tried first; `second` may
/// end only if `first` failed (`H15a`). Its value is the member that reported
/// last (`.first` while the first is undecided and has reported), and `onEnded`
/// the winner's (probe `X2`, `X2b`, ruling `GE-C`).
public struct ExclusiveGesture<First: Gesture, Second: Gesture>: Gesture, PrimitiveGesture {
    /// Which of the two gestures ended, with its value.
    public enum Value {
        case first(First.Value)
        case second(Second.Value)
    }

    /// The gesture tried first.
    public var first: First
    /// The gesture that may end only if `first` failed.
    public var second: Second

    /// The gesture `first.exclusively(before: second)` builds.
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    func _recognizers() -> _GestureRecognizers {
        let hooks = CompositeHooks()
        let state = CompositeState<Value, Value>()
        var f = recognizerNode(of: first)
        var s = recognizerNode(of: second)
        f.tap(changed: { state.latest = .first($0 as! First.Value); state.dirty = true },
              ended: { state.end = .first($0 as! First.Value) })
        s.tap(changed: { state.latest = .second($0 as! Second.Value); state.dirty = true },
              ended: { state.end = .second($0 as! Second.Value) })
        hooks.flush = {
            guard state.dirty, let value = state.latest else { return }
            state.dirty = false
            for tap in hooks.changedTaps { tap(value) }
        }
        hooks.ended = {
            if let value = state.end ?? state.latest { for tap in hooks.endedTaps { tap(value) } }
        }
        hooks.reset = { state.reset() }
        return _GestureRecognizers(.hooked(.exclusive([f, s]), hooks))
    }
}

/// `first.simultaneously(with: second)`: both recognize independently (`H16a`,
/// `H16b`). Its value holds each member's latest, reported **once per event**
/// (probe `X1`); `onEnded` runs once, when the composite ends.
public struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture, PrimitiveGesture {
    /// Both gestures' values; a member that has not reported is `nil`.
    public struct Value {
        /// The first gesture's value, if it reported one.
        public var first: First.Value?
        /// The second gesture's value, if it reported one.
        public var second: Second.Value?
    }

    /// One of the two gestures recognized together.
    public var first: First
    /// The other of the two gestures recognized together.
    public var second: Second

    /// The gesture `first.simultaneously(with: second)` builds.
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    func _recognizers() -> _GestureRecognizers {
        let hooks = CompositeHooks()
        let state = CompositeState<Value, Value>()
        var f = recognizerNode(of: first)
        var s = recognizerNode(of: second)
        let slots = SimultaneousSlots<First.Value, Second.Value>()
        f.tap(changed: { slots.first = $0 as? First.Value; state.dirty = true },
              ended: { slots.first = $0 as? First.Value })
        s.tap(changed: { slots.second = $0 as? Second.Value; state.dirty = true },
              ended: { slots.second = $0 as? Second.Value })
        hooks.flush = {
            guard state.dirty else { return }
            state.dirty = false
            let value = Value(first: slots.first, second: slots.second)
            for tap in hooks.changedTaps { tap(value) }
        }
        hooks.ended = {
            let value = Value(first: slots.first, second: slots.second)
            for tap in hooks.endedTaps { tap(value) }
        }
        hooks.reset = { state.reset(); slots.first = nil; slots.second = nil }
        return _GestureRecognizers(.hooked(.simultaneous([f, s]), hooks))
    }
}

final class SimultaneousSlots<First, Second>: @unchecked Sendable {
    var first: First?
    var second: Second?
}

/// `first.sequenced(before: second)` (ruling `GE-B`, probes `S1`…`S7b`): `second` is recognized only after
/// `first` has ended, and starts from **the first pointer event after that** — a drag's start location is that
/// event's, not the press's. If `first` fails, so does the sequence. Reports `.first(_)` while the first member
/// runs and `.second(firstValue, secondValue?)` once it has ended (`secondValue` is `nil` until the second member
/// reports); `onEnded` is the last `.second` when the second member ends.
public struct SequenceGesture<First: Gesture, Second: Gesture>: Gesture, PrimitiveGesture {
    /// A composite MetalUI provides has no body.
    public typealias Body = Never

    /// What the sequence has reported.
    public enum Value {
        /// The first gesture is running; its latest value.
        case first(First.Value)
        /// The first gesture ended with its value; the second gesture's latest, once it has reported.
        case second(First.Value, Second.Value?)
    }

    /// The gesture that must end first.
    public var first: First
    /// The gesture recognized after `first` ends.
    public var second: Second

    /// The gesture `first.sequenced(before: second)` builds.
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    func _recognizers() -> _GestureRecognizers {
        let hooks = CompositeHooks()
        let state = CompositeState<Value, Value>()
        let memory = SequenceMemory<First.Value, Second.Value>()
        var f = recognizerNode(of: first)
        var s = recognizerNode(of: second)
        f.tap(changed: { state.latest = .first($0 as! First.Value); state.dirty = true },
              ended: {
                  let value = $0 as! First.Value
                  memory.firstFinal = value
                  state.latest = .second(value, nil)
                  state.dirty = true
              })
        s.tap(changed: {
                  let value = $0 as! Second.Value
                  memory.secondLast = value
                  if let held = memory.firstFinal { state.latest = .second(held, value); state.dirty = true }
              },
              ended: { memory.secondEnd = ($0 as! Second.Value) })
        hooks.flush = {
            guard state.dirty, let value = state.latest else { return }
            state.dirty = false
            for tap in hooks.changedTaps { tap(value) }
        }
        hooks.ended = {
            guard let held = memory.firstFinal else { return }
            let value = Value.second(held, memory.secondEnd ?? memory.secondLast)
            for tap in hooks.endedTaps { tap(value) }
        }
        hooks.reset = { state.reset(); memory.firstFinal = nil; memory.secondLast = nil; memory.secondEnd = nil }
        return _GestureRecognizers(.hooked(.sequence(f, s), hooks))
    }
}

final class SequenceMemory<First, Second>: @unchecked Sendable {
    var firstFinal: First?
    var secondLast: Second?
    var secondEnd: Second?
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

    /// A gesture that recognizes `self`, then `other` once `self` has ended — SwiftUI's
    /// `sequenced(before:)`, e.g. a long press then a drag.
    public func sequenced<Other: Gesture>(before other: Other) -> SequenceGesture<Self, Other> {
        SequenceGesture(self, other)
    }

    /// Runs `action` with the gesture's value when it changes — SwiftUI's `onChanged(_:)`, on every
    /// gesture including a custom one and a composite. A recognizer's own `onChanged` is the same call.
    public func onChanged(_ action: @escaping @MainActor (Value) -> Void) -> _ChangedGesture<Self> {
        _ChangedGesture(base: self, action: action)
    }

    /// Runs `action` with the gesture's value when it ends — SwiftUI's `onEnded(_:)`, on every gesture
    /// including a custom one and a composite.
    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> _EndedGesture<Self> {
        _EndedGesture(base: self, action: action)
    }

    /// Writes `state` with `body` on every value the gesture reports and returns it to its initial value
    /// when the gesture ends, fails or is cancelled — SwiftUI's `updating(_:body:)`, on every gesture
    /// including a composite (probes `S6`, `X1`, `X2`; ruling `GE-E`).
    @MainActor public func updating<State>(
        _ state: GestureState<State>,
        body: @escaping @MainActor (Value, inout State, inout Transaction) -> Void
    ) -> GestureStateGesture<Self, State> {
        GestureStateGesture(base: self, update: GestureUpdate(state, afterChanged: false, body: body))
    }
}

/// What `onChanged(_:)` returns on a gesture without its own: the base, with the action listening to its value.
public struct _ChangedGesture<Base: Gesture>: Gesture, PrimitiveGesture {
    /// The base gesture's value.
    public typealias Value = Base.Value
    /// A wrapper has no body of its own.
    public typealias Body = Never
    var base: Base
    var action: @MainActor (Base.Value) -> Void

    func _recognizers() -> _GestureRecognizers {
        var node = recognizerNode(of: base)
        let action = action
        node.tap(changed: { action($0 as! Base.Value) }, ended: nil)
        return _GestureRecognizers(node)
    }
}

/// What `onEnded(_:)` returns on a gesture without its own: the base, with the action listening for its end.
public struct _EndedGesture<Base: Gesture>: Gesture, PrimitiveGesture {
    /// The base gesture's value.
    public typealias Value = Base.Value
    /// A wrapper has no body of its own.
    public typealias Body = Never
    var base: Base
    var action: @MainActor (Base.Value) -> Void

    func _recognizers() -> _GestureRecognizers {
        var node = recognizerNode(of: base)
        let action = action
        node.tap(changed: nil, ended: { action($0 as! Base.Value) })
        return _GestureRecognizers(node)
    }
}

/// What `updating(_:body:)` returns on a gesture without its own: the base, writing a `GestureState` on
/// every value it reports and resetting it when it ends, fails or is cancelled (`GS-C`, `GE-E`).
public struct GestureStateGesture<Base: Gesture, State>: Gesture, PrimitiveGesture {
    /// The base gesture's value.
    public typealias Value = Base.Value
    /// A wrapper has no body of its own.
    public typealias Body = Never
    var base: Base
    var update: GestureUpdate<Base.Value>

    func _recognizers() -> _GestureRecognizers {
        var node = recognizerNode(of: base)
        let update = update
        node.tap(changed: { update.run($0 as! Base.Value) }, ended: nil)
        node.addFinish(update.finish)
        return _GestureRecognizers(node)
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
        self.node = recognizerNode(of: gesture)
    }

    /// An attachment of `node` directly — a draggable's (`DN-D`), which no
    /// public `Gesture` spells.
    init(node: GestureNode, priority: Priority) {
        self.priority = priority
        self.node = node
    }
}

// MARK: - The arena (`IX-D`)

/// Which input an arena recognizes (input APIs, `CI-D` item 1, `CI-F` item 3):
/// the primary press, a secondary or other button's press by its AppKit button
/// number, or a trackpad pinch. See `GestureArena`'s "Modes".
enum ArenaMode: Equatable {
    case press
    case button(Int)
    case pinch
}

/// A callback the arena decided to run, handed to the window in order. The
/// window runs each under `StateDispatch.dispatching(to:)` its owner (`IX-D`
/// item 5, `ID-F`); a click goes through `Window.runClick`, so it keeps
/// `ClickDispatch`'s modifiers and focus request exactly as today.
enum GestureCallback {
    case gesture(owner: GlobalElementID, run: @MainActor () -> Void)
    case click(owner: GlobalElementID, handler: @MainActor () -> Void, modifiers: Modifiers)
    /// A draggable won the arena (ruling `DN-D` item 7): `Window` opens a drag
    /// session from `owner` with `source`'s payload, pressed at `at`.
    case beginDrag(owner: GlobalElementID, source: DragSource, at: Point<Pixels>)
    /// A `WindowDragGesture` won the arena (ruling `WD-D`): `Window` asks the
    /// platform to move the window and ends the press.
    case beginWindowDrag(owner: GlobalElementID)
}

/// **The tap's slop** (`IX-C` item 1, probe `G2g`/`G2b`): a tap fails once the
/// pointer is this far from its press.
let tapSlop: Float = 5

/// **How long a tap sequence waits for its next press** (`IX-C` items 2–3,
/// probe `G5e`: between 0.31 and 0.35 s; not `NSEvent.doubleClickInterval`),
/// measured from the release's stamp tick.
let tapSequenceDeferral: Double = 0.33

/// One recognizer's per-press state in an arena.
@MainActor
final class ArenaLeaf {
    enum Recognizer {
        case gesture(GestureLeaf)
        /// The target's `onClick`, the arena's innermost normal member
        /// (`IX-D` item 2): Button semantics, decided by the window's own
        /// press-and-release-on-the-same-element test.
        case click
    }

    enum Status { case possible, ended, failed }

    let recognizer: Recognizer
    let owner: GlobalElementID
    /// The owning element's window-space origin, unclipped — drag values are
    /// local to it (`IX-C` item 5).
    let origin: Point<Pixels>
    /// The owning element's registered hitbox, for a tap's release test.
    let region: Hitbox

    var status = Status.possible
    /// Recognized and waiting to be allowed to end (`IX-D` item 3).
    var ready = false
    var pressPoint = Point<Pixels>(x: Pixels(0), y: Pixels(0))
    /// A timer waiting for its stamp tick (`IX-C` item 4).
    var awaitingStamp = false
    var stamp: Double?
    /// Long press: `onPressingChanged(true)` is owed, and whether it ran.
    var owesPressing = false
    var pressingReported = false
    /// An `updating` body ran and the reset is still owed (`GS-C`).
    var owesFinish = false
    /// Drag: reached its minimum, reported a change, the change owed.
    var started = false
    var activated = false
    var pendingChange: DragGesture.Value?
    var endValue: DragGesture.Value?
    /// The last press's modifiers and click count (`IF-B`, `IF-C`).
    var pressModifiers = Modifiers()
    var pressClickCount = 1
    /// Click: what the window resolved at the release.
    var click: (handler: @MainActor () -> Void, modifiers: Modifiers)?
    /// Spatial tap: the release that ended it, in its space (`CI-B` item 1).
    var tapLocation: Point<Pixels>?
    /// Magnify or rotate (`CI-C`): begun in this gesture, the cumulative
    /// delta, the fixed start point and anchor, and a change owed (`started`
    /// and `activated` are the drag's fields, with the same meaning).
    var pinchBegun = false
    var pinchAmount = 0.0
    var pinchStart = Point<Pixels>(x: Pixels(0), y: Pixels(0))
    var pinchAnchor = UnitPoint.zero
    var pendingPinch = false
    /// The `sequenced(before:)` first members this leaf waits on (`GE-B`): it recognizes nothing until every one
    /// has ended. Nested sequences add one each.
    var gates: [ArenaNode] = []
    /// A drag behind a gate: its start is the first pointer event after the gate opened (probe `S5b`).
    var awaitsFirstEvent = false
    /// A drag whose first event was the release: it ends with no change before it (probe `S4`).
    var endOnRelease = false
    /// A drag's last three (location in its space, event time) samples, for the velocity (`GE-F`).
    var samples: [(location: Point<Pixels>, time: Double)] = []

    /// Whether a first member of a sequence this leaf follows has not ended.
    var isGated: Bool { gates.contains { $0.status != .ended } }

    /// Records the pointer at `time`: an event at the instant of the last sample replaces it (probes `D14`, `D15`).
    func sample(_ location: Point<Pixels>, at time: Double) {
        if let last = samples.last, time <= last.time {
            samples[samples.count - 1] = (location, last.time)
        } else {
            samples.append((location, time))
            if samples.count > 3 { samples.removeFirst() }
        }
    }

    /// Three parts of the previous interval's speed to one of the latest (`GE-F`, probes `D6`, `D7`, `D11`);
    /// the one interval's alone with two samples, zero with fewer.
    var velocity: Size<Pixels> {
        func speed(_ a: Int, _ b: Int) -> (x: Float, y: Float) {
            let dt = Float(samples[b].time - samples[a].time)
            return ((samples[b].location.x - samples[a].location.x).value / dt,
                    (samples[b].location.y - samples[a].location.y).value / dt)
        }
        switch samples.count {
        case 0, 1: return Size(width: Pixels(0), height: Pixels(0))
        case 2: let v = speed(0, 1); return Size(width: Pixels(v.x), height: Pixels(v.y))
        default:
            let old = speed(samples.count - 3, samples.count - 2), new = speed(samples.count - 2, samples.count - 1)
            return Size(width: Pixels(0.75 * old.x + 0.25 * new.x), height: Pixels(0.75 * old.y + 0.25 * new.y))
        }
    }

    /// The drag value for an event at `point` in `space`.
    func dragValue(in space: CoordinateSpace, at point: Point<Pixels>, modifiers: Modifiers,
                   time: Double) -> DragGesture.Value {
        DragGesture.Value(startLocation: self.point(pressPoint, in: space), location: self.point(point, in: space),
                          modifiers: modifiers, clickCount: pressClickCount,
                          time: Date(timeIntervalSinceReferenceDate: time), velocity: velocity)
    }

    /// The named spaces in force at the region's registration, taken at the
    /// arena's formation (`OV-H`).
    let namedSpaces: [NamedSpace]

    init(_ recognizer: Recognizer, owner: GlobalElementID, region: Hitbox, namedSpaces: [NamedSpace] = []) {
        self.recognizer = recognizer
        self.owner = owner
        self.origin = region.origin
        self.region = region
        self.namedSpaces = namedSpaces
    }

    /// The two pinch kinds, which never block each other (`CI-D` item 3).
    enum PinchKind { case magnify, rotate }

    /// This leaf's pinch kind, or `nil` for every other recognizer.
    var pinchKind: PinchKind? {
        guard case .gesture(let leaf) = recognizer else { return nil }
        switch leaf.kind {
        case .magnify: return .magnify
        case .rotate: return .rotate
        default: return nil
        }
    }

    /// Whether this leaf is a `DragGesture` of any button.
    var isDrag: Bool {
        if case .gesture(let leaf) = recognizer, case .drag = leaf.kind { return true }
        return false
    }

    /// Whether this leaf takes part in an arena of `mode` (`CI-D` item 1,
    /// `CI-F` item 3): a press arena runs everything but pinches and
    /// non-primary drags; a button arena only its button's drags; a pinch
    /// arena only magnifies and rotates.
    func isLive(in mode: ArenaMode) -> Bool {
        switch recognizer {
        case .click:
            return mode == .press
        case .gesture(let leaf):
            switch leaf.kind {
            case .tap, .longPress, .draggable, .windowDrag:
                return mode == .press
            case .drag(_, _, let button):
                switch mode {
                case .press: return button == .primary
                case .button(let number): return button.buttonNumber == number
                case .pinch: return false
                }
            case .magnify, .rotate:
                return mode == .pinch
            }
        }
    }

    /// `point` (a window point) in `space`: local to the owning element, its
    /// render effects undone; the window point itself; or the point in the
    /// nearest ancestor space so named, `.global` when none is (`OV-H`) — an
    /// exhaustive switch, so a new case cannot fall into another's arm.
    func point(_ point: Point<Pixels>, in space: CoordinateSpace) -> Point<Pixels> {
        switch space {
        case .local: local(point)
        case .global: point
        case .named(let name): NamedSpace.resolve(name, in: namedSpaces)?.toSpace?.apply(point) ?? point
        }
    }

    /// The anchor of a local point: its fraction of the registered hit
    /// region's size (`CI-C` item 3), 0 on an empty axis.
    func anchor(of local: Point<Pixels>) -> UnitPoint {
        let w = Double(region.bounds.size.width.value), h = Double(region.bounds.size.height.value)
        return UnitPoint(x: w > 0 ? Double(local.x.value) / w : 0, y: h > 0 ? Double(local.y.value) / h : 0)
    }

    /// Whether this leaf is a `.draggable` (ruling `DN-D`).
    var isDraggable: Bool {
        if case .gesture(let leaf) = recognizer, case .draggable = leaf.kind { return true }
        return false
    }

    /// Whether this leaf is a `WindowDragGesture` (ruling `WD-C`).
    var isWindowDrag: Bool {
        if case .gesture(let leaf) = recognizer, case .windowDrag = leaf.kind { return true }
        return false
    }

    /// Whether this leaf hands the press to the platform when it acts — a
    /// draggable's session or a window drag — and so passes the members a
    /// draggable passes (`DN-D` item 2, `WD-C`). Not `isDraggable`: a window
    /// drag is a pointer target, never a `.draggable` region (`WD-B`).
    var startsHandoff: Bool { isDraggable || isWindowDrag }

    var tapCount: Int? {
        if case .gesture(let leaf) = recognizer, case .tap(let count, _) = leaf.kind { return count }
        return nil
    }

    func local(_ point: Point<Pixels>) -> Point<Pixels> {
        // Through the declarer's render effects first (`GX-P` item 3).
        let point = region.localPoint(point)
        return Point(x: point.x - origin.x, y: point.y - origin.y)
    }
}

/// A node of an arena's recognizer tree — a leaf or a composition.
@MainActor
final class ArenaNode {
    enum Kind {
        case leaf(ArenaLeaf)
        case exclusive([ArenaNode])
        case simultaneous([ArenaNode])
        /// `sequenced(before:)`: the second member waits for the first (`GE-B`).
        case sequence(ArenaNode, ArenaNode)
    }

    let kind: Kind
    /// The typed machinery of a composite gesture (`GE-C`), or `nil`.
    var hooks: CompositeHooks?
    /// A sequence whose second member has been released from its gate.
    var gateOpened = false
    /// A composite that has ended, failed or been cancelled and told its hooks.
    var settled = false
    init(_ kind: Kind) { self.kind = kind }

    /// The owner of the first leaf below, who runs a composite's callbacks.
    var owner: GlobalElementID? { leaves.first?.owner }

    var leaves: [ArenaLeaf] {
        switch kind {
        case .leaf(let leaf): return [leaf]
        case .exclusive(let children), .simultaneous(let children): return children.flatMap(\.leaves)
        case .sequence(let first, let second): return first.leaves + second.leaves
        }
    }

    /// An exclusive composition ends when any member ends and fails when all
    /// fail; a simultaneous one fails when all fail and ends when none is
    /// still possible and one ended.
    var status: ArenaLeaf.Status {
        switch kind {
        case .leaf(let leaf):
            return leaf.status
        case .exclusive(let children):
            let statuses = children.map(\.status)
            if statuses.contains(.ended) { return .ended }
            return statuses.allSatisfy { $0 == .failed } ? .failed : .possible
        case .simultaneous(let children):
            let statuses = children.map(\.status)
            if statuses.allSatisfy({ $0 == .failed }) { return .failed }
            return statuses.contains(.possible) ? .possible : .ended
        case .sequence(let first, let second):
            // The sequence fails with its first member and ends with its second (`GE-B`).
            switch first.status {
            case .failed: return .failed
            case .possible: return .possible
            case .ended: return second.status
            }
        }
    }
}

/// **One press's gesture arena** (ruling `IX-D`) — pure: it knows hitboxes,
/// points and ticks, never a `Window`. The window forms it at a `mouseDown`
/// from `topmostOpaqueHitbox(in:at:)`'s target — the one ranking — and the
/// target id's ancestors (`Window.dispatchGestures`), feeds it the press's
/// events and ticks, and runs the callbacks it returns.
///
/// **Order** (`IX-D` item 3): high-priority members outermost first, then the
/// target's `onClick`, then normal members innermost first; on one element a
/// later modifier is outer. **Simultaneous members** stand outside that order
/// and their callbacks run first on a shared event (`IX-D` item 4).
///
/// **A member may end, or report a change, only when every exclusive member
/// ahead of it has failed** (`IX-D` item 3, `IX-O`'s `X4`); when one ends,
/// every member behind it is cancelled. **A tap that a larger-count tap could
/// still pre-empt waits for it, arena-wide** (`IX-C` item 3), and is cancelled
/// when it ends — which is also why a smaller tap ahead of a larger one does
/// not hold the larger one off.
///
/// **Lifetime**: from the press until the release, and past it while a tap
/// sequence waits for its next press (`IX-C` item 2); a press on the same
/// target continues it (the second click of a double), a press anywhere else
/// abandons it first.
///
/// **Modes** (input APIs, `CI-D`, `CI-F`): the same arena is formed, from the
/// same ranking, for three kinds of input, and its mode decides which leaves
/// are live — the rest are **failed at formation**, so they neither act nor
/// block. `.press` (the primary button): everything but magnifies, rotates
/// and non-primary drags, plus the target's `onClick`. `.button(n)` (a
/// secondary or other button's press): only drags with button `n`, no click.
/// `.pinch` (a trackpad magnify or rotate): only magnifies and rotates, no
/// click; it lives while a begun pinch kind has not ended, and **a magnify
/// and a rotate never block or cancel each other** — among leaves of one kind
/// the order above holds (`CI-D` item 3).
@MainActor
struct GestureArena {
    /// The pressed hitbox's owner.
    let targetID: GlobalElementID
    /// Which input the arena recognizes.
    let mode: ArenaMode
    private let exclusiveRoot: ArenaNode
    private let simultaneousRoots: [ArenaNode]
    private let leaves: [ArenaLeaf]
    /// Between a press and its release.
    private(set) var isPressing = false
    /// The platform click count of the press the arena began with — a tap's
    /// count is counted from it (`IX-C` item 2).
    private var baseClickCount = 1
    private var callbacks: [GestureCallback] = []
    /// Where in `callbacks` a finish hook stands, so `cancel()` can hand back those and no others (`GS-C`).
    private var finishIndices: [Int] = []
    /// The pinch kinds begun and not yet ended (pinch mode, `CI-D` item 4).
    private var activePinchKinds: Set<ArenaLeaf.PinchKind> = []
    /// The sequences and composites of the arena, children before parents (`GE-B`, `GE-C`).
    private var sequences: [ArenaNode] = []
    private var composites: [ArenaNode] = []
    /// The last pointer position and event time the arena saw.
    private var lastPoint = Point<Pixels>(x: Pixels(0), y: Pixels(0))
    private var lastTime = 0.0
    /// The move or release being resolved, replayed to a sequence's second member when its gate opens (`S7`).
    private var currentEvent: ReplayableEvent?

    private enum ReplayableEvent {
        case move(Point<Pixels>, Modifiers, Double)
        case release(Point<Pixels>, Int, Modifiers, (handler: @MainActor () -> Void, modifiers: Modifiers)?, Double)
    }

    /// The arena for a press on `target`, with `ancestors` — each a hitbox of
    /// a proper ancestor of the target's id, in the target's hit layer (`IX-Q`),
    /// containing the point, with its
    /// distance from the target in id levels. `nil` when no gesture attached
    /// to any of them is live in `mode`: a press's dispatch is then exactly
    /// `Window.dispatchClick` (`IX-D` item 2), and a secondary, other or pinch
    /// event forms nothing.
    ///
    /// `namedSpaces`: each member's named-space snapshot by owner (`OV-H`),
    /// empty when no `coordinateSpace(_:)` was in force.
    init?(target: Hitbox, ancestors: [(hitbox: Hitbox, depth: Int)], draggableAbove: Hitbox? = nil,
          mode: ArenaMode = .press, namedSpaces: [GlobalElementID: [NamedSpace]] = [:]) {
        struct Member { let node: ArenaNode; let priority: GestureAttachment.Priority; let depth: Int; let index: Int }
        var members: [Member] = []
        var builtSequences: [ArenaNode] = []
        var builtComposites: [ArenaNode] = []
        // A non-opaque draggable region ranking above the target joins as the
        // innermost member (`DN-E` item 2): depth −1, inside the target itself.
        let above = draggableAbove.map { [($0, -1)] } ?? []
        for (hitbox, depth) in above + [(target, 0)] + ancestors.map({ ($0.hitbox, $0.depth) }) {
            for (index, attachment) in hitbox.handlers.gestures.enumerated() {
                members.append(Member(node: Self.build(attachment.node, owner: hitbox.id, region: hitbox,
                                                       namedSpaces: namedSpaces[hitbox.id] ?? [], gates: [],
                                                       sequences: &builtSequences, composites: &builtComposites),
                                      priority: attachment.priority, depth: depth, index: index))
            }
        }
        guard !members.isEmpty else { return nil }
        let outermostFirst = { (a: Member, b: Member) in (a.depth, a.index) > (b.depth, b.index) }
        var exclusive = members.filter { $0.priority == .high }.sorted(by: outermostFirst).map(\.node)
        if mode == .press, target.handlers.onClick != nil {
            exclusive.append(ArenaNode(.leaf(ArenaLeaf(.click, owner: target.id, region: target))))
        }
        exclusive += members.filter { $0.priority == .normal }.sorted { outermostFirst($1, $0) }.map(\.node)
        sequences = builtSequences
        composites = builtComposites
        targetID = target.id
        self.mode = mode
        exclusiveRoot = ArenaNode(.exclusive(exclusive))
        simultaneousRoots = members.filter { $0.priority == .simultaneous }.sorted(by: outermostFirst).map(\.node)
        leaves = ([exclusiveRoot] + simultaneousRoots).flatMap(\.leaves)
        // Failed at formation (`CI-D` items 1–2, `CI-F` item 3).
        for leaf in leaves where !leaf.isLive(in: mode) { leaf.status = .failed }
        let liveGesture = leaves.contains {
            guard $0.status == .possible, case .gesture = $0.recognizer else { return false }
            return true
        }
        guard liveGesture else { return nil }
    }

    private static func build(_ node: GestureNode, owner: GlobalElementID, region: Hitbox,
                              namedSpaces: [NamedSpace], gates: [ArenaNode],
                              sequences: inout [ArenaNode], composites: inout [ArenaNode]) -> ArenaNode {
        switch node {
        case .leaf(let leaf):
            let built = ArenaLeaf(.gesture(leaf), owner: owner, region: region, namedSpaces: namedSpaces)
            built.gates = gates
            return ArenaNode(.leaf(built))
        case .exclusive(let children):
            return ArenaNode(.exclusive(children.map {
                build($0, owner: owner, region: region, namedSpaces: namedSpaces, gates: gates,
                      sequences: &sequences, composites: &composites)
            }))
        case .simultaneous(let children):
            return ArenaNode(.simultaneous(children.map {
                build($0, owner: owner, region: region, namedSpaces: namedSpaces, gates: gates,
                      sequences: &sequences, composites: &composites)
            }))
        case .sequence(let first, let second):
            let a = build(first, owner: owner, region: region, namedSpaces: namedSpaces, gates: gates,
                          sequences: &sequences, composites: &composites)
            let b = build(second, owner: owner, region: region, namedSpaces: namedSpaces, gates: gates + [a],
                          sequences: &sequences, composites: &composites)
            let built = ArenaNode(.sequence(a, b))
            sequences.append(built)
            return built
        case .hooked(let inner, let hooks):
            let built = build(inner, owner: owner, region: region, namedSpaces: namedSpaces, gates: gates,
                              sequences: &sequences, composites: &composites)
            built.hooks = hooks
            composites.append(built)
            return built
        }
    }

    /// Something is still undecided, or the press is still down; a pinch arena
    /// while a begun kind has not ended (`CI-D` item 4).
    var isAlive: Bool {
        if mode == .pinch { return !activePinchKinds.isEmpty }
        return isPressing || leaves.contains { $0.status == .possible }
    }

    /// Some drag leaf reached its minimum distance in this press (`CI-F` item
    /// 4): a button arena's pending context menu is cancelled by it.
    var activatedAnyDrag: Bool { leaves.contains { $0.isDrag && $0.started } }

    /// A timer is running: the window keeps frames coming only while this is
    /// true (`IX-C` item 4).
    var needsTicks: Bool {
        leaves.contains { leaf in
            guard leaf.status == .possible, !leaf.isGated, case .gesture(let g) = leaf.recognizer else { return false }
            switch g.kind {
            case .tap: return leaf.awaitingStamp || leaf.stamp != nil
            case .longPress: return !leaf.ready
            case .drag, .draggable, .windowDrag, .magnify, .rotate: return false
            }
        }
    }

    // MARK: Events

    /// `press(at:clickCount:continuing:modifiers:)` with no modifiers — the
    /// spelling every pre-`CI-` arena test uses.
    mutating func press(at point: Point<Pixels>, clickCount: Int, continuing: Bool) -> [GestureCallback] {
        press(at: point, clickCount: clickCount, continuing: continuing, modifiers: [])
    }

    /// The event time: the event's own stamp, else the last the arena saw (`GE-D`).
    private func stamped(_ timestamp: Double?) -> Double { timestamp ?? lastTime }

    /// A press. `continuing` is the second press of a tap sequence on the same
    /// target: taps re-arm, anything else still undecided fails — and a drag
    /// that had reported a change first runs its `onCancelled`, ahead of
    /// whatever the resolution then produces, as `abandon()` does (`GC-B`).
    /// `modifiers` are the press's, for a `minimumDistance: 0` drag's first
    /// change (`CI-G`). `timestamp` is the event's, for a drag's `time` and
    /// `velocity` (`GE-D`).
    mutating func press(at point: Point<Pixels>, clickCount: Int, continuing: Bool,
                        modifiers: Modifiers, timestamp: Double? = nil) -> [GestureCallback] {
        let time = stamped(timestamp)
        isPressing = true
        lastPoint = point
        lastTime = time
        if !continuing { baseClickCount = clickCount }
        var cancels: [GestureCallback] = []
        for leaf in leaves where leaf.status == .possible {
            leaf.pressModifiers = modifiers
            leaf.pressClickCount = clickCount
            // A member behind a sequence's first waits for its gate (`GE-B`).
            if leaf.isGated { leaf.pressPoint = point; continue }
            switch leaf.recognizer {
            case .click:
                if continuing { fail(leaf) }
            case .gesture(let g):
                switch g.kind {
                case .tap:
                    if !leaf.ready {
                        leaf.pressPoint = point
                        leaf.awaitingStamp = false
                        leaf.stamp = nil
                    }
                case .longPress:
                    if continuing { fail(leaf); continue }
                    leaf.pressPoint = point
                    leaf.awaitingStamp = true
                    leaf.owesPressing = true
                case .drag(let minimum, let space, _):
                    if continuing {
                        // A leaf that reported owes `onCancelled` whatever
                        // ends it (`GC-B`).
                        if let callback = cancelCallback(leaf) { cancels.append(callback) }
                        fail(leaf)
                        continue
                    }
                    leaf.pressPoint = point
                    leaf.samples = []
                    leaf.sample(leaf.point(point, in: space), at: time)
                    if minimum <= 0 {
                        leaf.started = true
                        leaf.pendingChange = leaf.dragValue(in: space, at: point, modifiers: modifiers, time: time)
                    }
                case .draggable, .windowDrag:
                    leaf.pressPoint = point
                case .magnify, .rotate:
                    break
                }
            }
        }
        return cancels + resolve()
    }

    /// `move(to:modifiers:)` with no modifiers.
    mutating func move(to point: Point<Pixels>) -> [GestureCallback] {
        move(to: point, modifiers: [])
    }

    /// A move while pressed, with the modifiers its event carried (`CI-G`) and its timestamp (`GE-D`).
    mutating func move(to point: Point<Pixels>, modifiers: Modifiers, timestamp: Double? = nil) -> [GestureCallback] {
        guard isPressing else { return [] }
        let time = stamped(timestamp)
        lastPoint = point
        lastTime = time
        currentEvent = .move(point, modifiers, time)
        for leaf in leaves where leaf.status == .possible && !leaf.isGated {
            applyMove(leaf, to: point, modifiers: modifiers, time: time)
        }
        return resolve()
    }

    private mutating func applyMove(_ leaf: ArenaLeaf, to point: Point<Pixels>, modifiers: Modifiers, time: Double) {
        guard case .gesture(let g) = leaf.recognizer else { return }
        if leaf.awaitsFirstEvent {
            // The drag behind a gate starts at its first event (probe `S5b`).
            leaf.awaitsFirstEvent = false
            leaf.pressPoint = point
            leaf.samples = []
        }
        let distance = Self.distance(point, leaf.pressPoint)
        switch g.kind {
        case .tap:
            if !leaf.ready && distance >= tapSlop { fail(leaf) }
        case .longPress(_, let maximum):
            if distance >= maximum { fail(leaf) }
        case .drag(let minimum, let space, _):
            leaf.sample(leaf.point(point, in: space), at: time)
            if !leaf.started && distance >= minimum { leaf.started = true }
            if leaf.started {
                leaf.pendingChange = leaf.dragValue(in: space, at: point, modifiers: modifiers, time: time)
            }
        case .draggable:
            // The first move of more than zero points (`DN-D` item 1,
            // `P17`/`P17z`): no slop, unlike a tap's.
            if distance > 0 { leaf.ready = true }
        case .windowDrag:
            // One threshold for a press (`WD-C`): under `tapSlop` it can
            // still be a tap or a click, from it on a window drag.
            if distance >= tapSlop { leaf.ready = true }
        case .magnify, .rotate:
            break
        }
    }

    /// `release(at:clickCount:modifiers:click:)` with no modifiers.
    mutating func release(at point: Point<Pixels>, clickCount: Int,
                          click: (handler: @MainActor () -> Void, modifiers: Modifiers)?) -> [GestureCallback] {
        release(at: point, clickCount: clickCount, modifiers: [], click: click)
    }

    /// The release, with its event's modifiers (a drag's `onEnded`, `CI-G`) and timestamp (`GE-D`).
    /// `click` is what the window's press-and-release test resolved for the
    /// target's `onClick` — `nil` when it failed.
    mutating func release(at point: Point<Pixels>, clickCount: Int, modifiers: Modifiers,
                          click: (handler: @MainActor () -> Void, modifiers: Modifiers)?,
                          timestamp: Double? = nil) -> [GestureCallback] {
        let time = stamped(timestamp)
        isPressing = false
        lastPoint = point
        lastTime = time
        currentEvent = .release(point, clickCount, modifiers, click, time)
        for leaf in leaves {
            leaf.owesPressing = false
            if leaf.pressingReported { reportPressing(leaf, false) }
        }
        for leaf in leaves where leaf.status == .possible && !leaf.isGated {
            applyRelease(leaf, at: point, clickCount: clickCount, modifiers: modifiers, click: click, time: time)
        }
        return resolve()
    }

    private mutating func applyRelease(_ leaf: ArenaLeaf, at point: Point<Pixels>, clickCount: Int,
                                       modifiers: Modifiers,
                                       click: (handler: @MainActor () -> Void, modifiers: Modifiers)?,
                                       time: Double) {
        let firstEvent = leaf.awaitsFirstEvent
        if firstEvent {
            leaf.awaitsFirstEvent = false
            leaf.pressPoint = point
            leaf.samples = []
        }
        switch leaf.recognizer {
        case .click:
            if let click { leaf.click = click; leaf.ready = true } else { fail(leaf) }
        case .gesture(let g):
            switch g.kind {
            case .tap(let count, let spatial):
                guard !leaf.ready else { return }
                if Self.distance(point, leaf.pressPoint) >= tapSlop || !leaf.region.contains(point) {
                    fail(leaf)
                    return
                }
                let taps = clickCount - baseClickCount + 1
                if taps == count {
                    leaf.ready = true
                    // The release that ends the tap (`CI-B` item 1).
                    if let spatial { leaf.tapLocation = leaf.point(point, in: spatial) }
                } else if taps < count {
                    leaf.awaitingStamp = true
                } else {
                    fail(leaf)
                }
            case .longPress:
                if !leaf.ready { fail(leaf) }
            case .drag(let minimum, let space, _):
                // A change still withheld at the release is never
                // reported: a drag that did not activate during the press
                // is cancelled with no callback (`IX-D` item 3, MetalUI's
                // choice for the corner `X4` leaves unmeasured).
                leaf.pendingChange = nil
                leaf.sample(leaf.point(point, in: space), at: time)
                if firstEvent && minimum <= 0 {
                    // The release was the drag's first event after a gate: it ends with no change before it
                    // (probe `S4`).
                    leaf.started = true
                    leaf.endOnRelease = true
                }
                if !leaf.started {
                    fail(leaf)
                } else {
                    leaf.endValue = leaf.dragValue(in: space, at: point, modifiers: modifiers, time: time)
                    leaf.ready = true
                }
            case .draggable, .windowDrag:
                fail(leaf)
            case .magnify, .rotate:
                break
            }
        }
    }

    /// Whether `event` — a `.magnify` or `.rotate` — is of a pinch kind this
    /// arena holds begun and not yet ended (`CI-AB` item 2).
    func holdsActivePinch(of event: InputEvent) -> Bool {
        switch event {
        case .magnify: return activePinchKinds.contains(.magnify)
        case .rotate: return activePinchKinds.contains(.rotate)
        default: return false
        }
    }

    /// A trackpad magnify step (pinch mode, `CI-C`, `CI-D`).
    mutating func magnify(_ event: MagnifyEvent) -> [GestureCallback] {
        pinch(.magnify, delta: event.magnification, phase: event.phase, at: event.position)
    }

    /// A trackpad rotate step, clockwise-positive degrees (pinch mode).
    mutating func rotate(_ event: RotateEvent) -> [GestureCallback] {
        pinch(.rotate, delta: event.rotation, phase: event.phase, at: event.position)
    }

    /// One pinch step of `kind`: a `.began` (or the kind's first event) begins
    /// it — each leaf of the kind fixes its start point and anchor and starts
    /// from 0; every event adds its delta; a leaf owes a change once |Σ|
    /// reaches its minimum; `.ended`/`.cancelled` makes an activated leaf
    /// ready to end and fails the rest. An end of a kind that is not active
    /// is ignored.
    private mutating func pinch(_ kind: ArenaLeaf.PinchKind, delta: Double, phase: InputPhase,
                                at point: Point<Pixels>) -> [GestureCallback] {
        let ends = phase == .ended || phase == .cancelled
        if ends && !activePinchKinds.contains(kind) { return [] }
        let begins = phase == .began || !activePinchKinds.contains(kind)
        activePinchKinds.insert(kind)
        for leaf in leaves where leaf.status == .possible && leaf.pinchKind == kind {
            guard case .gesture(let g) = leaf.recognizer else { continue }
            if begins || !leaf.pinchBegun {
                leaf.pinchBegun = true
                leaf.pinchAmount = 0
                leaf.started = false
                leaf.pinchStart = leaf.local(point)
                leaf.pinchAnchor = leaf.anchor(of: leaf.pinchStart)
            }
            leaf.pinchAmount += delta
            let minimum: Double
            switch g.kind {
            case .magnify(let scale): minimum = scale
            case .rotate(let degrees): minimum = degrees
            default: continue
            }
            if !leaf.started && abs(leaf.pinchAmount) >= minimum { leaf.started = true }
            if ends {
                leaf.pendingPinch = false
                if leaf.started { leaf.ready = true } else { fail(leaf) }
            } else if leaf.started {
                leaf.pendingPinch = true
            }
        }
        if ends { activePinchKinds.remove(kind) }
        return resolve()
    }

    /// A display-link tick at `time`: stamps what is waiting for one, then
    /// expires a tap sequence and matures a long press (`IX-C` items 2–4).
    mutating func tick(_ time: Double) -> [GestureCallback] {
        lastTime = max(lastTime, time)
        for leaf in leaves where leaf.status == .possible && !leaf.isGated {
            guard case .gesture(let g) = leaf.recognizer else { continue }
            if leaf.awaitingStamp {
                leaf.stamp = time
                leaf.awaitingStamp = false
            }
            guard let stamp = leaf.stamp else { continue }
            switch g.kind {
            case .tap:
                if time - stamp >= tapSequenceDeferral { fail(leaf) }
            case .longPress(let duration, _):
                if !leaf.ready && time - stamp >= duration { leaf.ready = true }
            case .drag, .draggable, .windowDrag, .magnify, .rotate:
                break
            }
        }
        return resolve()
    }

    /// A press elsewhere: everything undecided fails, and whatever that frees
    /// (a tap waiting on a larger one) ends.
    mutating func abandon() -> [GestureCallback] {
        // A leaf that reported and is not waiting to end owes `onCancelled`
        // (`IF-F` item 1) — before anything the freed members then run.
        var cancels = cancel(includingReady: false)
        isPressing = false
        for leaf in leaves {
            leaf.owesPressing = false
            if leaf.pressingReported { reportPressing(leaf, false) }
        }
        for leaf in leaves where leaf.status == .possible && !leaf.ready { fail(leaf) }
        cancels += resolve()
        return cancels
    }

    /// The arena is dropped without its leaves ending (`IF-E`, `IF-F`): every
    /// undecided leaf that had reported a change owes its `onCancelled`, once,
    /// and then fails. `includingReady` is `false` for `abandon()`, where a
    /// leaf that is only waiting to be allowed to end still ends.
    mutating func cancel(includingReady: Bool = true) -> [GestureCallback] {
        var out: [GestureCallback] = []
        for leaf in leaves where leaf.status == .possible && (includingReady || !leaf.ready) {
            if let callback = cancelCallback(leaf) { out.append(callback) }
            if leaf.activated || leaf.owesFinish { fail(leaf) }
        }
        // A composite that failed or is dropped owes its resets too.
        settleComposites(flushing: false, dropping: includingReady)
        // The finish hooks `fail` queued are owed here: the arena is about to be dropped and nothing resolves
        // again (`GS-C`). The other queued callbacks keep their old fate.
        for index in finishIndices { out.append(callbacks[index]) }
        for index in finishIndices.reversed() { callbacks.remove(at: index) }
        finishIndices = []
        return out
    }

    /// `leaf`'s `onCancelled`, if it reported a change and has one.
    private func cancelCallback(_ leaf: ArenaLeaf) -> GestureCallback? {
        guard leaf.activated, case .gesture(let g) = leaf.recognizer else { return nil }
        let run: (@MainActor () -> Void)?
        switch g.kind {
        case .drag: run = g.dragCancelled
        case .magnify: run = g.magnifyCancelled
        case .rotate: run = g.rotateCancelled
        default: run = nil
        }
        guard let run else { return nil }
        return .gesture(owner: leaf.owner, run: run)
    }

    // MARK: Resolution

    private static func distance(_ a: Point<Pixels>, _ b: Point<Pixels>) -> Float {
        let dx = a.x.value - b.x.value, dy = a.y.value - b.y.value
        return (dx * dx + dy * dy).squareRoot()
    }

    private mutating func fail(_ leaf: ArenaLeaf) {
        leaf.status = .failed
        leaf.owesPressing = false
        if leaf.pressingReported { reportPressing(leaf, false) }
        queueFinish(leaf)
    }

    /// Queues the leaf's reset once, when an `updating` body of it ran (`GS-C`).
    private mutating func queueFinish(_ leaf: ArenaLeaf) {
        guard leaf.owesFinish, case .gesture(let g) = leaf.recognizer, let finished = g.finished else { return }
        leaf.owesFinish = false
        finishIndices.append(callbacks.count)
        callbacks.append(.gesture(owner: leaf.owner, run: finished))
    }

    private mutating func reportPressing(_ leaf: ArenaLeaf, _ pressing: Bool) {
        guard case .gesture(let g) = leaf.recognizer else { return }
        leaf.pressingReported = pressing
        if let callback = g.pressingChanged {
            callbacks.append(.gesture(owner: leaf.owner, run: { callback(pressing) }))
        }
        if pressing, let callback = g.longPressChanged {
            leaf.owesFinish = g.finished != nil
            callbacks.append(.gesture(owner: leaf.owner, run: { callback(true) }))
        }
    }

    /// Runs every member allowed to act until nothing changes, and hands back
    /// the callbacks the event produced, in order.
    private mutating func resolve() -> [GestureCallback] {
        var changed = true
        while changed {
            changed = cancelBehindEndedMembers()
            changed = openGates() || changed
            for root in simultaneousRoots { changed = visit(root, ahead: []) || changed }
            changed = visit(exclusiveRoot, ahead: []) || changed
        }
        settleComposites(flushing: true, dropping: false)
        currentEvent = nil
        defer { callbacks = []; finishIndices = [] }
        return callbacks
    }

    /// Releases the second member of every sequence whose first has ended (`GE-B`): its leaves start afresh from
    /// the pointer, and the event being resolved — a release that ended a tap — is replayed to them as their first
    /// (probe `S7`). Returns whether any gate opened.
    private mutating func openGates() -> Bool {
        var opened = false
        for node in sequences where !node.gateOpened {
            guard case .sequence(let first, let second) = node.kind, first.status == .ended else { continue }
            node.gateOpened = true
            opened = true
            let fresh = second.leaves.filter { $0.status == .possible }
            for leaf in fresh { rebase(leaf) }
            switch currentEvent {
            case .move(let point, let modifiers, let time)?:
                for leaf in fresh where leaf.status == .possible && !leaf.isGated {
                    applyMove(leaf, to: point, modifiers: modifiers, time: time)
                }
            case .release(let point, let count, let modifiers, let click, let time)?:
                for leaf in fresh where leaf.status == .possible && !leaf.isGated {
                    applyRelease(leaf, at: point, clickCount: count, modifiers: modifiers, click: click, time: time)
                }
            case nil:
                break
            }
        }
        return opened
    }

    /// Starts a second member's recognition from the pointer where it is now.
    private func rebase(_ leaf: ArenaLeaf) {
        guard case .gesture(let g) = leaf.recognizer else { return }
        leaf.pressPoint = lastPoint
        switch g.kind {
        case .longPress:
            leaf.awaitingStamp = true
            leaf.stamp = nil
            leaf.owesPressing = isPressing
        case .tap:
            leaf.awaitingStamp = false
            leaf.stamp = nil
        case .drag:
            leaf.awaitsFirstEvent = true
            leaf.samples = []
        default:
            break
        }
    }

    /// Hands each composite node what it owes (`GE-C`): once an event's leaf callbacks are queued, a flush so it
    /// reports its latest value once; and, for a node that ended, failed or (with `dropping`) is being dropped,
    /// its updating resets, its `ended` if it ended, and its state reset — in that order, so `onEnded` reads a
    /// reset state (`GS-C`).
    private mutating func settleComposites(flushing: Bool, dropping: Bool) {
        for node in composites where !node.settled {
            guard let hooks = node.hooks, let owner = node.owner else { continue }
            if flushing && !callbacks.isEmpty, let flush = hooks.flush {
                callbacks.append(.gesture(owner: owner, run: flush))
            }
            let status = node.status
            guard status != .possible || dropping else { continue }
            node.settled = true
            var run: [@MainActor () -> Void] = hooks.finishes
            if status == .ended, let ended = hooks.ended { run.append(ended) }
            if let reset = hooks.reset { run.append(reset) }
            for body in run {
                if status != .ended { finishIndices.append(callbacks.count) }
                callbacks.append(.gesture(owner: owner, run: body))
            }
        }
    }

    /// Visits `node`'s leaves, each with the exclusive members ahead of it;
    /// returns whether a leaf ended or failed.
    private mutating func visit(_ node: ArenaNode, ahead: [ArenaNode]) -> Bool {
        switch node.kind {
        case .leaf(let leaf):
            guard leaf.status == .possible, !leaf.isGated, !isBlocked(leaf, ahead: ahead) else { return false }
            return act(leaf)
        case .exclusive(let children):
            var changed = false
            for index in children.indices {
                changed = visit(children[index], ahead: ahead + Array(children[..<index])) || changed
            }
            return changed
        case .simultaneous(let children):
            var changed = false
            for child in children { changed = visit(child, ahead: ahead) || changed }
            return changed
        case .sequence(let first, let second):
            var changed = visit(first, ahead: ahead)
            if first.status == .ended { changed = visit(second, ahead: ahead) || changed }
            return changed
        }
    }

    /// An unblocked leaf reports what it owes and ends if it is ready.
    private mutating func act(_ leaf: ArenaLeaf) -> Bool {
        switch leaf.recognizer {
        case .click:
            guard leaf.ready, let click = leaf.click else { return false }
            leaf.status = .ended
            callbacks.append(.click(owner: leaf.owner, handler: click.handler, modifiers: click.modifiers))
            return true
        case .gesture(let g):
            if leaf.owesPressing && isPressing {
                leaf.owesPressing = false
                reportPressing(leaf, true)
            }
            if let change = leaf.pendingChange {
                leaf.pendingChange = nil
                leaf.activated = true
                if let callback = g.dragChanged {
                    leaf.owesFinish = g.finished != nil
                    callbacks.append(.gesture(owner: leaf.owner, run: { callback(change) }))
                }
            }
            if leaf.pendingPinch {
                leaf.pendingPinch = false
                leaf.activated = true
                appendPinchCallback(leaf, g, ended: false)
            }
            guard leaf.ready else { return false }
            switch g.kind {
            case .tap:
                leaf.status = .ended
                if let callback = g.tapEnded { callbacks.append(.gesture(owner: leaf.owner, run: callback)) }
                if let callback = g.spatialTapEnded, let location = leaf.tapLocation {
                    let value = SpatialTapGesture.Value(location: location,
                                                        modifiers: leaf.pressModifiers,
                                                        clickCount: leaf.pressClickCount)
                    callbacks.append(.gesture(owner: leaf.owner, run: { callback(value) }))
                }
            case .longPress:
                leaf.status = .ended
                queueFinish(leaf)
                if let callback = g.longPressEnded {
                    callbacks.append(.gesture(owner: leaf.owner, run: { callback(true) }))
                }
            case .drag:
                guard leaf.activated || leaf.endOnRelease, let value = leaf.endValue else {
                    fail(leaf)
                    return true
                }
                leaf.status = .ended
                queueFinish(leaf)
                if let callback = g.dragEnded {
                    callbacks.append(.gesture(owner: leaf.owner, run: { callback(value) }))
                }
            case .draggable:
                // The drag begins (`DN-D` item 7): every other member fails
                // without an end; a simultaneous member already resolved on
                // this event keeps its callbacks, which precede this one
                // (`DN-D` item 4, `P2e`) — simultaneous roots are visited first.
                leaf.status = .ended
                // A member that had reported is cancelled (`IF-F` item 1),
                // ahead of the session opening.
                for other in leaves where other !== leaf && other.status == .possible {
                    if let callback = cancelCallback(other) { callbacks.append(callback) }
                }
                if let source = g.dragSource {
                    callbacks.append(.beginDrag(owner: leaf.owner, source: source, at: leaf.pressPoint))
                }
                for other in leaves where other !== leaf && other.status == .possible { fail(other) }
            case .windowDrag:
                // The platform's move begins (`WD-C`, `WD-D`): the draggable's
                // arm, line for line. Every other member fails without an end;
                // one that had reported is cancelled first (`IF-F` item 1),
                // ahead of the request.
                leaf.status = .ended
                for other in leaves where other !== leaf && other.status == .possible {
                    if let callback = cancelCallback(other) { callbacks.append(callback) }
                }
                callbacks.append(.beginWindowDrag(owner: leaf.owner))
                for other in leaves where other !== leaf && other.status == .possible { fail(other) }
            case .magnify, .rotate:
                // A pinch that never reported a change ends with no callback
                // (`CI-C` item 4).
                guard leaf.activated else {
                    fail(leaf)
                    return true
                }
                leaf.status = .ended
                queueFinish(leaf)
                appendPinchCallback(leaf, g, ended: true)
            }
            return true
        }
    }

    /// Appends a magnify's or a rotate's `onChanged` or `onEnded` with the
    /// leaf's current value (`CI-C` items 1–3).
    private mutating func appendPinchCallback(_ leaf: ArenaLeaf, _ g: GestureLeaf, ended: Bool) {
        switch g.kind {
        case .magnify:
            let value = MagnifyGesture.Value(magnification: 1 + leaf.pinchAmount, startLocation: leaf.pinchStart,
                                             startAnchor: leaf.pinchAnchor)
            if let callback = ended ? g.magnifyEnded : g.magnifyChanged {
                if !ended { leaf.owesFinish = g.finished != nil }
                callbacks.append(.gesture(owner: leaf.owner, run: { callback(value) }))
            }
        case .rotate:
            let value = RotateGesture.Value(rotation: .degrees(leaf.pinchAmount), startLocation: leaf.pinchStart,
                                            startAnchor: leaf.pinchAnchor)
            if let callback = ended ? g.rotateEnded : g.rotateChanged {
                if !ended { leaf.owesFinish = g.finished != nil }
                callbacks.append(.gesture(owner: leaf.owner, run: { callback(value) }))
            }
        default:
            break
        }
    }

    /// Whether an exclusive member ahead has ended, or is still possible and
    /// does not yield to `leaf`, or a larger-count tap anywhere could still
    /// pre-empt it.
    private func isBlocked(_ leaf: ArenaLeaf, ahead: [ArenaNode]) -> Bool {
        // A draggable's one exception (`DN-D` item 2, `P1b`/`P1c`, `P2f`,
        // `P3b`/`P3c`, `P21`, `P22b`/`P22c`): an UNDECIDED member ahead whose
        // possible leaves are all taps, long presses or clicks does not hold
        // it off. An ENDED member ahead still blocks — a long press held past
        // its duration before the move keeps the drag from beginning (`DN-U`
        // item 1, MetalUI's choice) — and so does anything else undecided: a
        // `DragGesture` that outranks it wins (`DN-D` item 3).
        if leaf.startsHandoff {
            return ahead.contains { $0.status == .ended
                                    || ($0.status == .possible && !Self.yieldsToDraggable($0)) }
        }
        // A pinch leaf is held off only by a leaf of its own kind ahead that
        // has not failed (`CI-D` item 3): a magnify and a rotate never block
        // each other.
        if let kind = leaf.pinchKind {
            return ahead.contains { node in node.leaves.contains { $0.pinchKind == kind && $0.status != .failed } }
        }
        let count = leaf.tapCount
        // An ended member ahead blocks too: everything behind it is cancelled
        // on the next pass, and must not end on this one.
        if ahead.contains(where: { $0.status == .ended
                                   || ($0.status == .possible && !Self.yields($0, toTapCount: count)) }) {
            return true
        }
        guard let count else { return false }
        return leaves.contains { other in
            other !== leaf && other.status == .possible && (other.tapCount ?? 0) > count
        }
    }

    /// A node whose every undecided leaf is a tap with fewer clicks than a tap
    /// behind it waits for that tap, so it does not hold it off (`IX-C` item 3).
    /// Whether every undecided leaf of `node` is a tap, a long press or a click
    /// — the members a draggable passes (`DN-D` item 2).
    private static func yieldsToDraggable(_ node: ArenaNode) -> Bool {
        node.leaves.filter { $0.status == .possible }.allSatisfy { leaf in
            switch leaf.recognizer {
            case .click:
                return true
            case .gesture(let g):
                switch g.kind {
                case .tap, .longPress: return true
                case .drag, .draggable, .windowDrag, .magnify, .rotate: return false
                }
            }
        }
    }

    private static func yields(_ node: ArenaNode, toTapCount count: Int?) -> Bool {
        guard let count else { return false }
        return node.leaves.filter { $0.status == .possible }.allSatisfy { ($0.tapCount ?? Int.max) < count }
    }

    /// Cancels every undecided member behind an exclusive member that ended,
    /// and every tap with fewer clicks than a tap that ended; returns whether
    /// anything was cancelled.
    private mutating func cancelBehindEndedMembers() -> Bool {
        var cancelled: [ArenaLeaf] = []
        func walk(_ node: ArenaNode) {
            switch node.kind {
            case .leaf:
                break
            case .exclusive(let children):
                if let first = children.firstIndex(where: { $0.status == .ended }) {
                    // An ended magnify cancels only magnifies behind it, an
                    // ended rotate only rotates (`CI-D` item 3).
                    let ended = children[first].leaves.filter { $0.status == .ended }
                    let kinds = Set(ended.compactMap(\.pinchKind))
                    let pinchOnly = !ended.isEmpty && ended.allSatisfy { $0.pinchKind != nil }
                    for child in children[(first + 1)...] {
                        cancelled += child.leaves.filter { leaf in
                            leaf.status == .possible && (!pinchOnly || leaf.pinchKind.map(kinds.contains) == true)
                        }
                    }
                }
                children.forEach(walk)
            case .simultaneous(let children):
                children.forEach(walk)
            case .sequence(let first, let second):
                // A failed first member fails the sequence (`GE-B`, probe `S3`, `S5`).
                if first.status == .failed { cancelled += second.leaves.filter { $0.status == .possible } }
                walk(first)
                walk(second)
            }
        }
        walk(exclusiveRoot)
        simultaneousRoots.forEach(walk)
        let endedTaps = leaves.filter { $0.status == .ended }.compactMap(\.tapCount)
        if let largest = endedTaps.max() {
            cancelled += leaves.filter { $0.status == .possible && ($0.tapCount ?? Int.max) < largest }
        }
        for leaf in cancelled where leaf.status == .possible { fail(leaf) }
        return !cancelled.isEmpty
    }
}
