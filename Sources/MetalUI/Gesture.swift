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
        /// A `.draggable` (ruling `DN-D`): ready on the first move of more
        /// than zero points, failed at the release.
        case draggable
    }

    var kind: Kind
    var tapEnded: (@MainActor () -> Void)?
    var longPressEnded: (@MainActor (Bool) -> Void)?
    var longPressChanged: (@MainActor (Bool) -> Void)?
    /// `onLongPressGesture`'s `onPressingChanged` only (`IX-C` item 4).
    var pressingChanged: (@MainActor (Bool) -> Void)?
    var dragChanged: (@MainActor (DragGesture.Value) -> Void)?
    var dragEnded: (@MainActor (DragGesture.Value) -> Void)?
    /// A draggable's payload (`DN-D`); `nil` for every other kind.
    var dragSource: DragSource?

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
    /// Whether the press is still held at the minimum duration.
    public typealias Value = Bool

    /// Seconds the press must be held before the gesture ends.
    public var minimumDuration: Double
    /// How far the pointer may move before the gesture fails.
    public var maximumDistance: Pixels
    var ended: (@MainActor (Bool) -> Void)?
    var changed: (@MainActor (Bool) -> Void)?
    var pressing: (@MainActor (Bool) -> Void)?

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
        /// Where the press began.
        public var startLocation: Point<Pixels>
        /// Where the pointer is now.
        public var location: Point<Pixels>
        /// `location` minus `startLocation`.
        public var translation: Size<Pixels>

        /// A drag value; `translation` is derived.
        public init(startLocation: Point<Pixels>, location: Point<Pixels>) {
            self.startLocation = startLocation
            self.location = location
            self.translation = Size(width: location.x - startLocation.x,
                                    height: location.y - startLocation.y)
        }
    }

    /// How far the pointer must move before the drag begins.
    public var minimumDistance: Pixels
    var changed: (@MainActor (Value) -> Void)?
    var ended: (@MainActor (Value) -> Void)?

    /// A drag that begins once the pointer moves `minimumDistance`.
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

    @_spi(MetalUIGesture) public func _recognizers() -> _GestureRecognizers {
        _GestureRecognizers(.exclusive([first._recognizers().node, second._recognizers().node]))
    }
}

/// `first.simultaneously(with: second)`: both recognize independently (`H16a`,
/// `H16b`).
public struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture {
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

    /// An attachment of `node` directly — a draggable's (`DN-D`), which no
    /// public `Gesture` spells.
    init(node: GestureNode, priority: Priority) {
        self.priority = priority
        self.node = node
    }
}

// MARK: - The arena (`IX-D`)

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
    /// Drag: reached its minimum, reported a change, the change owed.
    var started = false
    var activated = false
    var pendingChange: DragGesture.Value?
    var endValue: DragGesture.Value?
    /// Click: what the window resolved at the release.
    var click: (handler: @MainActor () -> Void, modifiers: Modifiers)?

    init(_ recognizer: Recognizer, owner: GlobalElementID, region: Hitbox) {
        self.recognizer = recognizer
        self.owner = owner
        self.origin = region.origin
        self.region = region
    }

    /// Whether this leaf is a `.draggable` (ruling `DN-D`).
    var isDraggable: Bool {
        if case .gesture(let leaf) = recognizer, case .draggable = leaf.kind { return true }
        return false
    }

    var tapCount: Int? {
        if case .gesture(let leaf) = recognizer, case .tap(let count) = leaf.kind { return count }
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
    }

    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }

    var leaves: [ArenaLeaf] {
        switch kind {
        case .leaf(let leaf): return [leaf]
        case .exclusive(let children), .simultaneous(let children): return children.flatMap(\.leaves)
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
@MainActor
struct GestureArena {
    /// The pressed hitbox's owner.
    let targetID: GlobalElementID
    private let exclusiveRoot: ArenaNode
    private let simultaneousRoots: [ArenaNode]
    private let leaves: [ArenaLeaf]
    /// Between a press and its release.
    private(set) var isPressing = false
    /// The platform click count of the press the arena began with — a tap's
    /// count is counted from it (`IX-C` item 2).
    private var baseClickCount = 1
    private var callbacks: [GestureCallback] = []

    /// The arena for a press on `target`, with `ancestors` — each a hitbox of
    /// a proper ancestor of the target's id, in the target's hit layer (`IX-Q`),
    /// containing the point, with its
    /// distance from the target in id levels. `nil` when no gesture is
    /// attached to any of them: dispatch is then exactly `Window.dispatchClick`
    /// (`IX-D` item 2).
    init?(target: Hitbox, ancestors: [(hitbox: Hitbox, depth: Int)], draggableAbove: Hitbox? = nil) {
        struct Member { let node: ArenaNode; let priority: GestureAttachment.Priority; let depth: Int; let index: Int }
        var members: [Member] = []
        // A non-opaque draggable region ranking above the target joins as the
        // innermost member (`DN-E` item 2): depth −1, inside the target itself.
        let above = draggableAbove.map { [($0, -1)] } ?? []
        for (hitbox, depth) in above + [(target, 0)] + ancestors.map({ ($0.hitbox, $0.depth) }) {
            for (index, attachment) in hitbox.handlers.gestures.enumerated() {
                members.append(Member(node: Self.build(attachment.node, owner: hitbox.id, region: hitbox),
                                      priority: attachment.priority, depth: depth, index: index))
            }
        }
        guard !members.isEmpty else { return nil }
        let outermostFirst = { (a: Member, b: Member) in (a.depth, a.index) > (b.depth, b.index) }
        var exclusive = members.filter { $0.priority == .high }.sorted(by: outermostFirst).map(\.node)
        if target.handlers.onClick != nil {
            exclusive.append(ArenaNode(.leaf(ArenaLeaf(.click, owner: target.id, region: target))))
        }
        exclusive += members.filter { $0.priority == .normal }.sorted { outermostFirst($1, $0) }.map(\.node)
        targetID = target.id
        exclusiveRoot = ArenaNode(.exclusive(exclusive))
        simultaneousRoots = members.filter { $0.priority == .simultaneous }.sorted(by: outermostFirst).map(\.node)
        leaves = ([exclusiveRoot] + simultaneousRoots).flatMap(\.leaves)
    }

    private static func build(_ node: GestureNode, owner: GlobalElementID, region: Hitbox) -> ArenaNode {
        switch node {
        case .leaf(let leaf):
            return ArenaNode(.leaf(ArenaLeaf(.gesture(leaf), owner: owner, region: region)))
        case .exclusive(let children):
            return ArenaNode(.exclusive(children.map { build($0, owner: owner, region: region) }))
        case .simultaneous(let children):
            return ArenaNode(.simultaneous(children.map { build($0, owner: owner, region: region) }))
        }
    }

    /// Something is still undecided, or the press is still down.
    var isAlive: Bool { isPressing || leaves.contains { $0.status == .possible } }

    /// A timer is running: the window keeps frames coming only while this is
    /// true (`IX-C` item 4).
    var needsTicks: Bool {
        leaves.contains { leaf in
            guard leaf.status == .possible, case .gesture(let g) = leaf.recognizer else { return false }
            switch g.kind {
            case .tap: return leaf.awaitingStamp || leaf.stamp != nil
            case .longPress: return !leaf.ready
            case .drag, .draggable: return false
            }
        }
    }

    // MARK: Events

    /// A press. `continuing` is the second press of a tap sequence on the same
    /// target: taps re-arm, anything else still undecided is cancelled.
    mutating func press(at point: Point<Pixels>, clickCount: Int, continuing: Bool) -> [GestureCallback] {
        isPressing = true
        if !continuing { baseClickCount = clickCount }
        for leaf in leaves where leaf.status == .possible {
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
                case .drag(let minimum):
                    if continuing { fail(leaf); continue }
                    leaf.pressPoint = point
                    if minimum <= 0 {
                        leaf.started = true
                        leaf.pendingChange = DragGesture.Value(startLocation: leaf.local(point),
                                                               location: leaf.local(point))
                    }
                case .draggable:
                    leaf.pressPoint = point
                }
            }
        }
        return resolve()
    }

    /// A move while pressed.
    mutating func move(to point: Point<Pixels>) -> [GestureCallback] {
        guard isPressing else { return [] }
        for leaf in leaves where leaf.status == .possible {
            guard case .gesture(let g) = leaf.recognizer else { continue }
            let distance = Self.distance(point, leaf.pressPoint)
            switch g.kind {
            case .tap:
                if !leaf.ready && distance >= tapSlop { fail(leaf) }
            case .longPress(_, let maximum):
                if distance >= maximum { fail(leaf) }
            case .drag(let minimum):
                if !leaf.started && distance >= minimum { leaf.started = true }
                if leaf.started {
                    leaf.pendingChange = DragGesture.Value(startLocation: leaf.local(leaf.pressPoint),
                                                           location: leaf.local(point))
                }
            case .draggable:
                // The first move of more than zero points (`DN-D` item 1,
                // `P17`/`P17z`): no slop, unlike a tap's.
                if distance > 0 { leaf.ready = true }
            }
        }
        return resolve()
    }

    /// The release. `click` is what the window's press-and-release test
    /// resolved for the target's `onClick` — `nil` when it failed.
    mutating func release(at point: Point<Pixels>, clickCount: Int,
                          click: (handler: @MainActor () -> Void, modifiers: Modifiers)?) -> [GestureCallback] {
        isPressing = false
        for leaf in leaves {
            leaf.owesPressing = false
            if leaf.pressingReported { reportPressing(leaf, false) }
        }
        for leaf in leaves where leaf.status == .possible {
            switch leaf.recognizer {
            case .click:
                if let click { leaf.click = click; leaf.ready = true } else { fail(leaf) }
            case .gesture(let g):
                switch g.kind {
                case .tap(let count):
                    guard !leaf.ready else { continue }
                    if Self.distance(point, leaf.pressPoint) >= tapSlop || !leaf.region.contains(point) {
                        fail(leaf)
                        continue
                    }
                    let taps = clickCount - baseClickCount + 1
                    if taps == count {
                        leaf.ready = true
                    } else if taps < count {
                        leaf.awaitingStamp = true
                    } else {
                        fail(leaf)
                    }
                case .longPress:
                    if !leaf.ready { fail(leaf) }
                case .drag:
                    // A change still withheld at the release is never
                    // reported: a drag that did not activate during the press
                    // is cancelled with no callback (`IX-D` item 3, MetalUI's
                    // choice for the corner `X4` leaves unmeasured).
                    leaf.pendingChange = nil
                    if !leaf.started {
                        fail(leaf)
                    } else {
                        leaf.endValue = DragGesture.Value(startLocation: leaf.local(leaf.pressPoint),
                                                          location: leaf.local(point))
                        leaf.ready = true
                    }
                case .draggable:
                    fail(leaf)
                }
            }
        }
        return resolve()
    }

    /// A display-link tick at `time`: stamps what is waiting for one, then
    /// expires a tap sequence and matures a long press (`IX-C` items 2–4).
    mutating func tick(_ time: Double) -> [GestureCallback] {
        for leaf in leaves where leaf.status == .possible {
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
            case .drag, .draggable:
                break
            }
        }
        return resolve()
    }

    /// A press elsewhere: everything undecided fails, and whatever that frees
    /// (a tap waiting on a larger one) ends.
    mutating func abandon() -> [GestureCallback] {
        isPressing = false
        for leaf in leaves {
            leaf.owesPressing = false
            if leaf.pressingReported { reportPressing(leaf, false) }
        }
        for leaf in leaves where leaf.status == .possible && !leaf.ready { fail(leaf) }
        return resolve()
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
    }

    private mutating func reportPressing(_ leaf: ArenaLeaf, _ pressing: Bool) {
        guard case .gesture(let g) = leaf.recognizer else { return }
        leaf.pressingReported = pressing
        if let callback = g.pressingChanged {
            callbacks.append(.gesture(owner: leaf.owner, run: { callback(pressing) }))
        }
        if pressing, let callback = g.longPressChanged {
            callbacks.append(.gesture(owner: leaf.owner, run: { callback(true) }))
        }
    }

    /// Runs every member allowed to act until nothing changes, and hands back
    /// the callbacks the event produced, in order.
    private mutating func resolve() -> [GestureCallback] {
        var changed = true
        while changed {
            changed = cancelBehindEndedMembers()
            for root in simultaneousRoots { changed = visit(root, ahead: []) || changed }
            changed = visit(exclusiveRoot, ahead: []) || changed
        }
        defer { callbacks = [] }
        return callbacks
    }

    /// Visits `node`'s leaves, each with the exclusive members ahead of it;
    /// returns whether a leaf ended or failed.
    private mutating func visit(_ node: ArenaNode, ahead: [ArenaNode]) -> Bool {
        switch node.kind {
        case .leaf(let leaf):
            guard leaf.status == .possible, !isBlocked(leaf, ahead: ahead) else { return false }
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
                    callbacks.append(.gesture(owner: leaf.owner, run: { callback(change) }))
                }
            }
            guard leaf.ready else { return false }
            switch g.kind {
            case .tap:
                leaf.status = .ended
                if let callback = g.tapEnded { callbacks.append(.gesture(owner: leaf.owner, run: callback)) }
            case .longPress:
                leaf.status = .ended
                if let callback = g.longPressEnded {
                    callbacks.append(.gesture(owner: leaf.owner, run: { callback(true) }))
                }
            case .drag:
                guard leaf.activated, let value = leaf.endValue else {
                    fail(leaf)
                    return true
                }
                leaf.status = .ended
                if let callback = g.dragEnded {
                    callbacks.append(.gesture(owner: leaf.owner, run: { callback(value) }))
                }
            case .draggable:
                // The drag begins (`DN-D` item 7): every other member fails
                // without an end; a simultaneous member already resolved on
                // this event keeps its callbacks, which precede this one
                // (`DN-D` item 4, `P2e`) — simultaneous roots are visited first.
                leaf.status = .ended
                if let source = g.dragSource {
                    callbacks.append(.beginDrag(owner: leaf.owner, source: source, at: leaf.pressPoint))
                }
                for other in leaves where other !== leaf && other.status == .possible { fail(other) }
            }
            return true
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
        if leaf.isDraggable {
            return ahead.contains { $0.status == .ended
                                    || ($0.status == .possible && !Self.yieldsToDraggable($0)) }
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
                case .drag, .draggable: return false
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
                    for child in children[(first + 1)...] {
                        cancelled += child.leaves.filter { $0.status == .possible }
                    }
                }
                children.forEach(walk)
            case .simultaneous(let children):
                children.forEach(walk)
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
