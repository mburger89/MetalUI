import Foundation

// MARK: - Keyframes (C10 lane 2, rulings `LK-H`, `LK-I`, `LK-V`)
//
// SwiftUI's keyframe vocabulary — `KeyframeTimeline`, `KeyframeTrack`,
// `LinearKeyframe`, `CubicKeyframe`, `SpringKeyframe`, `MoveKeyframe`,
// `UnitCurve`, `Spring` and the two result builders — over MetalUI's
// ``VectorArithmetic``. A timeline is a **pure function of time**: each track
// compiles its keyframes once, at the timeline's initialisation, into a list of
// segments, and `value(time:)` evaluates them. Every rule is a literal from
// probe `docs/probes/swiftui-controls-looks.swift`, arms `K1`–`K9`.
//
// **User conformances to `Keyframes` and `KeyframeTrackContent` cannot be
// written** (`LK-V` item 2, `MC-G`'s precedent): each protocol's one
// requirement returns a carrier type with no public initialiser, so a
// conformance can only forward to a keyframe MetalUI declares.

// MARK: - Curves and springs

/// The shape of a ``LinearKeyframe``'s progress — SwiftUI's `UnitCurve`
/// (`LK-I` item 3): a unit cubic Bézier pinned at (0, 0) and (1, 1), the same
/// four curves ``Animation`` offers.
public struct UnitCurve: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case linear
        case bezier(x1: Double, y1: Double, x2: Double, y2: Double)
    }

    let kind: Kind

    init(kind: Kind) { self.kind = kind }

    /// Constant speed.
    public static let linear = UnitCurve(kind: .linear)
    /// Starts slow — CSS's `cubic-bezier(0.42, 0, 1, 1)`, as ``Animation/easeIn(duration:)``.
    public static let easeIn = UnitCurve(kind: .bezier(x1: 0.42, y1: 0, x2: 1, y2: 1))
    /// Ends slow — CSS's `cubic-bezier(0, 0, 0.58, 1)`, as ``Animation/easeOut(duration:)``.
    public static let easeOut = UnitCurve(kind: .bezier(x1: 0, y1: 0, x2: 0.58, y2: 1))
    /// Slow at both ends — CSS's `cubic-bezier(0.42, 0, 0.58, 1)`, as
    /// ``Animation/easeInOut(duration:)`` (probe `K2`).
    public static let easeInOut = UnitCurve(kind: .bezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1))

    /// A cubic Bézier through the two control points. Each point's `x` is
    /// clamped to 0…1, CSS's rule and ``Animation/timingCurve(_:_:_:_:duration:)``'s,
    /// so the curve stays a function of time.
    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
        UnitCurve(kind: .bezier(x1: min(max(startControlPoint.x, 0), 1), y1: startControlPoint.y,
                                x2: min(max(endControlPoint.x, 0), 1), y2: endControlPoint.y))
    }

    /// ``Animation``'s own curve, whose solver evaluates this one.
    var animationCurve: Animation.Curve {
        switch kind {
        case .linear: return .linear
        case let .bezier(x1, y1, x2, y2): return .bezier(x1: x1, y1: y1, x2: x2, y2: y2)
        }
    }

    /// Progress at normalised time `u` (0…1).
    func progress(at u: Double) -> Double { animationCurve.progress(at: u) }

    /// The slope of the progress at `u` (0 or 1), by a one-sided difference.
    func slope(at u: Double) -> Double {
        if case .linear = kind { return 1 }
        let h = 1e-4
        return u <= 0 ? progress(at: h) / h : (1 - progress(at: 1 - h)) / h
    }
}

/// A spring's shape — SwiftUI's `Spring(duration:bounce:)` initialiser and
/// nothing else (`LK-I` item 5): `duration` the undamped period, `bounce` 0
/// critically damped, positive underdamped, negative overdamped. Its motion is
/// ``Animation/spring(duration:bounce:)``'s.
public struct Spring: Hashable, Sendable {
    /// The undamped period, in seconds.
    public let duration: TimeInterval
    /// How much the spring overshoots: 0 none, toward 1 more.
    public let bounce: Double

    /// A spring of period `duration` and `bounce` — SwiftUI's
    /// `Spring(duration:bounce:)`. `bounce` must lie strictly between −1 and 1
    /// and `duration` be finite, as ``Animation/spring(duration:bounce:)``
    /// requires; a zero or negative duration snaps to the target.
    public init(duration: TimeInterval = 0.5, bounce: Double = 0) {
        precondition(bounce > -1 && bounce < 1,
                     "Spring(bounce:) must be strictly between -1 and 1; got \(bounce)")
        precondition(duration.isFinite, "Spring(duration:) must be finite; got \(duration)")
        self.duration = duration
        self.bounce = bounce
    }

    /// The displacement and velocity at `t` of a spring released `x0` from its
    /// target with velocity `v0` — linear in both, so a vector value is moved
    /// by the scalar coefficients `motion(x0: 1, v0: 0)` and `motion(x0: 0, v0: 1)`.
    func motion(t: Double, x0: Double, v0: Double) -> (displacement: Double, velocity: Double) {
        guard duration > 0 else { return (0, 0) }
        let (omega, zeta) = Animation.springParameters(duration: duration, bounce: bounce)
        return Animation.dampedHarmonicMotion(omega: omega, zeta: zeta, t: t, x0: x0, v0: v0)
    }
}

// MARK: - Track content

/// One keyframe as the timeline compiles it.
enum KeyframeSpec<Value: VectorArithmetic> {
    case linear(Value, duration: Double, curve: UnitCurve)
    case cubic(Value, duration: Double, start: Value?, end: Value?)
    case spring(Value, duration: Double, spring: Spring, start: Value?)
    case move(Value)

    var target: Value {
        switch self {
        case .linear(let v, _, _), .cubic(let v, _, _, _), .spring(let v, _, _, _), .move(let v): return v
        }
    }

    var duration: Double {
        switch self {
        case .linear(_, let d, _), .cubic(_, let d, _, _), .spring(_, let d, _, _): return d
        case .move: return 0
        }
    }
}

/// Validates a keyframe's duration: finite, a negative one read as 0.
private func keyframeDuration(_ duration: TimeInterval, _ kind: String) -> Double {
    precondition(duration.isFinite, "\(kind)'s duration must be finite; got \(duration)")
    return max(0, duration)
}

/// What a ``KeyframeTrack``'s content can hold: a sequence of keyframes for one
/// value — SwiftUI's `KeyframeTrackContent`. The keyframe types below conform;
/// a type outside MetalUI cannot (`LK-V` item 2).
public protocol KeyframeTrackContent<Value> {
    /// The value the keyframes move.
    associatedtype Value: VectorArithmetic

    /// The keyframes, in order. Implemented by MetalUI's keyframe types only:
    /// the carrier has no public initialiser.
    var _keyframes: KeyframeTrackContentGroup<Value> { get }
}

/// A sequence of keyframes — what ``KeyframeTrackContentBuilder`` builds and
/// what every ``KeyframeTrackContent`` hands its track. It has no public
/// initialiser (`LK-V` item 2).
public struct KeyframeTrackContentGroup<Value: VectorArithmetic>: KeyframeTrackContent {
    let specs: [KeyframeSpec<Value>]

    init(_ specs: [KeyframeSpec<Value>]) { self.specs = specs }

    /// Itself (``KeyframeTrackContent``).
    public var _keyframes: KeyframeTrackContentGroup<Value> { self }
}

/// A keyframe reached at constant speed or along a ``UnitCurve`` from the
/// previous value — SwiftUI's `LinearKeyframe` (`LK-I` item 3, probes `K1`,
/// `K2`).
public struct LinearKeyframe<Value: VectorArithmetic>: KeyframeTrackContent {
    let spec: KeyframeSpec<Value>

    /// Reaches `to` after `duration` seconds along `timingCurve`. A
    /// zero-duration keyframe reads `to` at its own time (divergence 171).
    public init(_ to: Value, duration: TimeInterval, timingCurve: UnitCurve = .linear) {
        spec = .linear(to, duration: keyframeDuration(duration, "LinearKeyframe"), curve: timingCurve)
    }

    /// This keyframe alone (``KeyframeTrackContent``).
    public var _keyframes: KeyframeTrackContentGroup<Value> { KeyframeTrackContentGroup([spec]) }
}

/// A keyframe reached along a cubic Hermite curve — SwiftUI's `CubicKeyframe`
/// (`LK-I` item 4, probes `K3`–`K3h`). Without explicit velocities the tangent
/// between two cubic keyframes is the finite difference of their neighbours, at
/// a boundary with another kind of keyframe that keyframe's velocity, and at the
/// track's start or end 0.
public struct CubicKeyframe<Value: VectorArithmetic>: KeyframeTrackContent {
    let spec: KeyframeSpec<Value>

    /// Reaches `to` after `duration` seconds, leaving the previous value at
    /// `startVelocity` and arriving at `endVelocity` (per second) when given.
    public init(_ to: Value, duration: TimeInterval, startVelocity: Value? = nil, endVelocity: Value? = nil) {
        spec = .cubic(to, duration: keyframeDuration(duration, "CubicKeyframe"),
                      start: startVelocity, end: endVelocity)
    }

    /// This keyframe alone (``KeyframeTrackContent``).
    public var _keyframes: KeyframeTrackContentGroup<Value> { KeyframeTrackContentGroup([spec]) }
}

/// A keyframe reached by a spring — SwiftUI's `SpringKeyframe` (`LK-I` item 5,
/// probes `K4`–`K4e`). The spring starts from the previous value with the
/// incoming velocity and **stops at `duration`, holding the value it reached**;
/// the next keyframe starts from there. **`duration` is required** (divergence
/// 168: SwiftUI's default length is unfitted).
public struct SpringKeyframe<Value: VectorArithmetic>: KeyframeTrackContent {
    let spec: KeyframeSpec<Value>

    /// Springs toward `to` for `duration` seconds with `spring`'s motion,
    /// starting at `startVelocity` (per second) when given.
    public init(_ to: Value, duration: TimeInterval, spring: Spring = Spring(), startVelocity: Value? = nil) {
        spec = .spring(to, duration: keyframeDuration(duration, "SpringKeyframe"), spring: spring,
                       start: startVelocity)
    }

    /// This keyframe alone (``KeyframeTrackContent``).
    public var _keyframes: KeyframeTrackContentGroup<Value> { KeyframeTrackContentGroup([spec]) }
}

/// A jump to a value at the keyframe's time — SwiftUI's `MoveKeyframe` (`LK-I`
/// item 6, probe `K5`); the next keyframe starts from it.
public struct MoveKeyframe<Value: VectorArithmetic>: KeyframeTrackContent {
    let spec: KeyframeSpec<Value>

    /// Jumps to `to`.
    public init(_ to: Value) { spec = .move(to) }

    /// This keyframe alone (``KeyframeTrackContent``).
    public var _keyframes: KeyframeTrackContentGroup<Value> { KeyframeTrackContentGroup([spec]) }
}

/// Builds a ``KeyframeTrack``'s keyframes — SwiftUI's
/// `KeyframeTrackContentBuilder`, with `if`, `if`/`else` and `for`.
@resultBuilder
public enum KeyframeTrackContentBuilder<Value: VectorArithmetic> {
    /// One keyframe or group.
    public static func buildExpression<C: KeyframeTrackContent>(_ content: C) -> KeyframeTrackContentGroup<Value>
        where C.Value == Value {
        content._keyframes
    }

    /// No keyframes.
    public static func buildBlock() -> KeyframeTrackContentGroup<Value> { KeyframeTrackContentGroup([]) }

    /// The first keyframes of a block.
    public static func buildPartialBlock(first: KeyframeTrackContentGroup<Value>) -> KeyframeTrackContentGroup<Value> {
        first
    }

    /// The keyframes so far, then `next`.
    public static func buildPartialBlock(accumulated: KeyframeTrackContentGroup<Value>,
                                         next: KeyframeTrackContentGroup<Value>) -> KeyframeTrackContentGroup<Value> {
        KeyframeTrackContentGroup(accumulated.specs + next.specs)
    }

    /// An `if` with no `else`: nothing when false.
    public static func buildOptional(_ content: KeyframeTrackContentGroup<Value>?) -> KeyframeTrackContentGroup<Value> {
        content ?? KeyframeTrackContentGroup([])
    }

    /// The `if` branch of an `if`/`else`.
    public static func buildEither(first: KeyframeTrackContentGroup<Value>) -> KeyframeTrackContentGroup<Value> {
        first
    }

    /// The `else` branch of an `if`/`else`.
    public static func buildEither(second: KeyframeTrackContentGroup<Value>) -> KeyframeTrackContentGroup<Value> {
        second
    }

    /// A `for` loop's keyframes, in order.
    public static func buildArray(_ contents: [KeyframeTrackContentGroup<Value>]) -> KeyframeTrackContentGroup<Value> {
        KeyframeTrackContentGroup(contents.flatMap(\.specs))
    }
}

// MARK: - Tracks

/// One track compiled against a timeline's initial value: how long it runs and
/// how it writes its field at a time.
struct CompiledKeyframeTrack<Root> {
    let duration: Double
    let apply: (Double, inout Root) -> Void
}

/// One track, waiting for the timeline's initial value.
struct ErasedKeyframeTrack<Root> {
    let compile: (Root) -> CompiledKeyframeTrack<Root>
}

/// Keyframes for a whole value — SwiftUI's `Keyframes`: one or several
/// ``KeyframeTrack``s. A type outside MetalUI cannot conform (`LK-V` item 2).
public protocol Keyframes<Value> {
    /// The value the timeline animates (a track's root).
    associatedtype Value

    /// The tracks. Implemented by MetalUI's track types only: the carrier has
    /// no public initialiser.
    var _tracks: KeyframesGroup<Value> { get }
}

/// A set of tracks — what ``KeyframesBuilder`` builds and what every
/// ``Keyframes`` hands its timeline. It has no public initialiser (`LK-V`
/// item 2).
public struct KeyframesGroup<Value>: Keyframes {
    let tracks: [ErasedKeyframeTrack<Value>]

    init(_ tracks: [ErasedKeyframeTrack<Value>]) { self.tracks = tracks }

    /// Itself (``Keyframes``).
    public var _tracks: KeyframesGroup<Value> { self }
}

/// The keyframes for one field of a timeline's value, reached through a key
/// path — SwiftUI's `KeyframeTrack` (`LK-I` item 1). Tracks run in parallel; the
/// timeline lasts as long as its longest, a shorter one holds its last value
/// (`K6`) and a field no track names keeps the initial value (`K7`).
///
/// Its second generic parameter is spelled `TrackValue` where SwiftUI writes
/// `Value` (`LK-V` item 3): MetalUI's ``Keyframes`` names its root `Value`, and a
/// generic parameter of that name would bind it. No call site spells it.
public struct KeyframeTrack<Root, TrackValue: VectorArithmetic, Content: KeyframeTrackContent>: Keyframes
    where Content.Value == TrackValue {
    let keyPath: WritableKeyPath<Root, TrackValue>
    let content: Content

    /// The keyframes in `content` for the field at `keyPath`.
    public init(_ keyPath: WritableKeyPath<Root, TrackValue>,
                @KeyframeTrackContentBuilder<TrackValue> content: () -> Content) {
        self.keyPath = keyPath
        self.content = content()
    }

    /// The keyframes in `content` for the whole value.
    public init(@KeyframeTrackContentBuilder<TrackValue> content: () -> Content) where Root == TrackValue {
        self.keyPath = \.self
        self.content = content()
    }

    /// This track alone (``Keyframes``).
    public var _tracks: KeyframesGroup<Root> {
        let keyPath = keyPath
        let specs = content._keyframes.specs
        return KeyframesGroup([ErasedKeyframeTrack { root in
            let segments = KeyframeSegments(specs: specs, from: root[keyPath: keyPath])
            return CompiledKeyframeTrack(duration: segments.duration) { time, root in
                root[keyPath: keyPath] = segments.value(at: time)
            }
        }])
    }
}

/// Builds a timeline's tracks — SwiftUI's `KeyframesBuilder`, with `if`,
/// `if`/`else` and `for`.
@resultBuilder
public enum KeyframesBuilder<Value> {
    /// One track or group.
    public static func buildExpression<K: Keyframes>(_ keyframes: K) -> KeyframesGroup<Value> where K.Value == Value {
        keyframes._tracks
    }

    /// No tracks.
    public static func buildBlock() -> KeyframesGroup<Value> { KeyframesGroup([]) }

    /// The first tracks of a block.
    public static func buildPartialBlock(first: KeyframesGroup<Value>) -> KeyframesGroup<Value> { first }

    /// The tracks so far, then `next`.
    public static func buildPartialBlock(accumulated: KeyframesGroup<Value>,
                                         next: KeyframesGroup<Value>) -> KeyframesGroup<Value> {
        KeyframesGroup(accumulated.tracks + next.tracks)
    }

    /// An `if` with no `else`: nothing when false.
    public static func buildOptional(_ keyframes: KeyframesGroup<Value>?) -> KeyframesGroup<Value> {
        keyframes ?? KeyframesGroup([])
    }

    /// The `if` branch of an `if`/`else`.
    public static func buildEither(first: KeyframesGroup<Value>) -> KeyframesGroup<Value> { first }

    /// The `else` branch of an `if`/`else`.
    public static func buildEither(second: KeyframesGroup<Value>) -> KeyframesGroup<Value> { second }

    /// A `for` loop's tracks, in order.
    public static func buildArray(_ keyframes: [KeyframesGroup<Value>]) -> KeyframesGroup<Value> {
        KeyframesGroup(keyframes.flatMap(\.tracks))
    }
}

// MARK: - The timeline

/// A value's keyframes as a function of time — SwiftUI's `KeyframeTimeline`
/// (`LK-I` items 1–2, 7). Before 0 it reads the initial value, after its
/// duration each track's last value; nothing it returns is non-finite for
/// finite keyframes (a zero-duration keyframe reads its target, divergence 171).
public struct KeyframeTimeline<Value> {
    let initialValue: Value
    let tracks: [CompiledKeyframeTrack<Value>]

    /// How long the longest track runs, in seconds.
    public let duration: TimeInterval

    /// The tracks in `content`, compiled against `initialValue`.
    public init(initialValue: Value, @KeyframesBuilder<Value> content: () -> some Keyframes<Value>) {
        self.initialValue = initialValue
        self.tracks = content()._tracks.tracks.map { $0.compile(initialValue) }
        self.duration = tracks.map(\.duration).max() ?? 0
    }

    /// The value at `time` seconds (a NaN time reads as 0).
    public func value(time: TimeInterval) -> Value {
        let t = time.isNaN ? 0 : time
        var value = initialValue
        for track in tracks { track.apply(t, &value) }
        return value
    }

    /// The value at `progress` of the duration, clamped to 0…1 (probe `K9`).
    public func value(progress: Double) -> Value {
        let p = progress.isNaN ? 0 : min(max(progress, 0), 1)
        return value(time: p * duration)
    }
}

// MARK: - Segments

/// One track's keyframes compiled into segments (`LK-I` items 2–7).
struct KeyframeSegments<Value: VectorArithmetic> {
    struct Segment {
        enum Kind {
            case linear(UnitCurve)
            case cubic
            case spring(Spring)
            case move
        }
        var kind: Kind
        var start: Double
        var duration: Double
        var from: Value
        var to: Value
        /// The velocity (per second) the segment leaves `from` with — a cubic's
        /// start tangent, a spring's initial velocity.
        var startVelocity: Value
        /// A cubic's arrival velocity (per second).
        var endVelocity: Value
        /// Where the segment ends: `to`, or where a spring stopped.
        var end: Value
        var endTime: Double { start + duration }
    }

    let initial: Value
    let segments: [Segment]

    var duration: Double { segments.last?.endTime ?? 0 }

    init(specs: [KeyframeSpec<Value>], from initial: Value) {
        self.initial = initial
        self.segments = []
    }

    /// The value at `time`.
    func value(at time: Double) -> Value {
        initial
    }
}
