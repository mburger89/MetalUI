import MetalUICore
import MetalUILayout

// MARK: - `keyframeAnimator` (C10 lane 2, rulings `LK-H`, `LK-I` items 9–12, `LK-T`)
//
// One transparent scope — no node, no identity level, `LifecycleScope`'s shape
// — whose state is a `KeyframeRecord` in the window's `AnimationStore`, keyed
// `$keyframes<depth>` under the position it sits at: **never a `StateTable`
// slot** (the seven reserved slots unmoved). During the build it reads its
// record, compares the trigger, starts or restarts a timeline, evaluates it at
// the frame's timestamp and builds its content with the value; while a
// timeline runs it notes an active animation. A record no build touches for a
// frame is dropped at that frame's end (the store's sweep), so content that
// leaves and returns starts at its initial value.

/// A keyframe animator's state between builds (`LK-I` items 10–12).
struct KeyframeRecord<Value> {
    /// The trigger the last build saw (`nil` for a repeating animator).
    var trigger: Any?
    /// The running (or last run) timeline.
    var timeline: KeyframeTimeline<Value>?
    /// The timestamp the timeline started at.
    var start: Double
    /// What the content shows at rest.
    var resting: Value
    /// Whether the timeline is running.
    var running: Bool
}

/// What a keyframe animator watches: a trigger compared with `==`, or a
/// repeating flag.
enum KeyframeAnimatorMode {
    case trigger(Any, matches: (Any) -> Bool)
    case repeating(Bool)
}

/// Content animated by keyframes — SwiftUI's `KeyframeAnimator`, and what
/// `.keyframeAnimator(initialValue:trigger:content:keyframes:)` and
/// `.keyframeAnimator(initialValue:repeating:content:keyframes:)` return
/// (`LK-I` items 9–12, `LK-T` item 4).
///
/// **On appear** the content shows `initialValue` and `keyframes` is not
/// called (probe `K10`). **A trigger change from rest** calls
/// `keyframes(initialValue)` and runs from `initialValue`, even when a finished
/// run left the content elsewhere (`K11`, `K12`); **a change mid-run** calls
/// `keyframes` with the current value and runs from there (`K13`); **at the
/// end** the content holds the timeline's end value. A **repeating** animator
/// calls `keyframes(initialValue)` once and loops (`K14`). While a timeline runs
/// the window keeps drawing (`Frame.noteActiveAnimation()`); at rest nothing.
///
/// **Transparent**: the content keeps the parent and position it would have
/// without the animator, so no `@State` moves when one is added; the record
/// lives in the window's animation store, never in `StateTable`. **A
/// `Self`-returning decoration written after it does not compile** (divergence
/// 120's rule, `LK-T` item 2): write it inside the content closure, as
/// SwiftUI's spelling does anyway. Track values constrain ``VectorArithmetic``
/// and the modifier's content closure receives the element itself, not a
/// placeholder (divergence 169).
public struct KeyframeAnimator<Value, Content: ElementGroup, K: Keyframes>: ElementGroup where K.Value == Value {
    let initialValue: Value
    let mode: KeyframeAnimatorMode
    let content: (Value) -> Content
    let keyframes: (Value) -> K

    init(initialValue: Value, mode: KeyframeAnimatorMode, content: @escaping (Value) -> Content,
         keyframes: @escaping (Value) -> K) {
        self.initialValue = initialValue
        self.mode = mode
        self.content = content
        self.keyframes = keyframes
    }

    /// Content built from the keyframes' value, rerun each time `trigger`
    /// changes — SwiftUI's `KeyframeAnimator(initialValue:trigger:content:keyframes:)`.
    public init(initialValue: Value, trigger: some Equatable,
                @ElementBuilder content: @escaping (Value) -> Content,
                @KeyframesBuilder<Value> keyframes: @escaping (Value) -> K) {
        self.init(initialValue: initialValue, mode: Self.triggerMode(trigger), content: content,
                  keyframes: keyframes)
    }

    /// Content built from the keyframes' value, looping while `repeating` —
    /// SwiftUI's `KeyframeAnimator(initialValue:repeating:content:keyframes:)`.
    /// While `repeating` is `false` the content shows `initialValue`.
    public init(initialValue: Value, repeating: Bool = true,
                @ElementBuilder content: @escaping (Value) -> Content,
                @KeyframesBuilder<Value> keyframes: @escaping (Value) -> K) {
        self.init(initialValue: initialValue, mode: .repeating(repeating), content: content,
                  keyframes: keyframes)
    }

    static func triggerMode<T: Equatable>(_ trigger: T) -> KeyframeAnimatorMode {
        .trigger(trigger, matches: { ($0 as? T) == trigger })
    }

    /// The content built this frame and its layout.
    public struct Layout {
        var content: Content
        var contentLayout: Content.GroupLayout
    }

    /// The value the content shows this frame, reading and writing the record
    /// at `$keyframes<depth>` under the position `.child(of: parent, at: cursor)`.
    func currentValue(under parent: GlobalElementID?, at cursor: Int, frame: Frame) -> Value {
        let store = frame.animationStore
        let owner = GlobalElementID.child(of: parent, at: cursor, name: nil)
        let key = GlobalElementID.child(of: owner, at: 0, name: ElementID("$keyframes\(store.keyframeDepth)"))
        let record = store.value(at: key, as: KeyframeRecord<Value>.self)
        let (value, next, active) = Self.resolve(record, mode: mode, initialValue: initialValue,
                                                 keyframes: keyframes, now: frame.timestamp)
        store.set(next, at: key)
        if active { frame.noteActiveAnimation() }
        return value
    }

    /// One build's step of the record (`LK-I` items 10–12): the value shown,
    /// the record to store and whether a timeline is running.
    static func resolve(_ record: KeyframeRecord<Value>?, mode: KeyframeAnimatorMode, initialValue: Value,
                        keyframes: (Value) -> K, now: Double)
        -> (value: Value, record: KeyframeRecord<Value>, active: Bool) {
        switch mode {
        case .repeating(let repeats):
            // `false` shows the timeline's start, the initial value; `true`
            // loops one timeline, `keyframes` called once (`K14`).
            guard repeats else {
                return (initialValue, KeyframeRecord(trigger: nil, timeline: nil, start: now,
                                                     resting: initialValue, running: false), false)
            }
            var next = record ?? KeyframeRecord(trigger: nil, timeline: nil, start: now,
                                                resting: initialValue, running: true)
            if next.timeline == nil || !next.running {
                next.timeline = KeyframeTimeline(initialValue: initialValue) { keyframes(initialValue) }
                next.start = now
                next.running = true
            }
            let timeline = next.timeline!
            guard timeline.duration > 0 else {
                return (timeline.value(time: 0), next, false)
            }
            let elapsed = max(0, now - next.start)
            return (timeline.value(time: elapsed.truncatingRemainder(dividingBy: timeline.duration)), next, true)
        case .trigger(let trigger, let matches):
            guard var next = record else {
                // Appear: the initial value, no keyframes (`K10`).
                return (initialValue, KeyframeRecord(trigger: trigger, timeline: nil, start: now,
                                                     resting: initialValue, running: false), false)
            }
            if let previous = next.trigger, !matches(previous) {
                // From rest: from the initial value (`K11`, `K12`); mid-run:
                // from the current value (`K13`).
                let start: Value
                if next.running, let timeline = next.timeline {
                    start = timeline.value(time: max(0, now - next.start))
                } else {
                    start = initialValue
                }
                next.timeline = KeyframeTimeline(initialValue: start) { keyframes(start) }
                next.start = now
                next.running = true
            }
            next.trigger = trigger
            guard next.running, let timeline = next.timeline else { return (next.resting, next, false) }
            let elapsed = max(0, now - next.start)
            if elapsed >= timeline.duration {
                // At the end the content holds the end value.
                next.resting = timeline.value(time: timeline.duration)
                next.running = false
                return (next.resting, next, false)
            }
            return (timeline.value(time: elapsed), next, true)
        }
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        let value = currentValue(under: parent, at: cursor, frame: pass.frame)
        var built = content(value)
        let (nodes, layout) = pass.frame.animationStore.withKeyframeScope {
            built.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        return (nodes, Layout(content: built, contentLayout: layout))
    }

    public mutating func prepaintGroup(layout: inout Layout, pass: inout PrepaintPass) -> Content.GroupPrepaint {
        layout.content.prepaintGroup(layout: &layout.contentLayout, pass: &pass)
    }

    public mutating func paintGroup(layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        layout.content.paintGroup(layout: &layout.contentLayout, prepaint: &prepaint, pass: &pass)
    }
}

/// **The typed entry is a line-for-line copy of the untyped one** (a copy of a
/// pinned implementation is unpinned; `keyframeAnimatorKeepsProposalContentProposal`
/// pins it).
extension KeyframeAnimator: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                                    pass: inout LayoutPass) -> ([ProposalNodeID], Layout) {
        let value = currentValue(under: parent, at: cursor, frame: pass.frame)
        var built = content(value)
        let (nodes, layout) = pass.frame.animationStore.withKeyframeScope {
            built.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        return (nodes, Layout(content: built, contentLayout: layout))
    }
}

extension ElementGroup {
    /// Animates `content` through `keyframes` each time `trigger` changes —
    /// SwiftUI's `keyframeAnimator(initialValue:trigger:content:keyframes:)`
    /// (`LK-I` items 9–12). `content` receives this group and the current value;
    /// `keyframes` receives the value a run starts from. Proposal content stays
    /// proposal content.
    ///
    /// ```swift
    /// Box().keyframeAnimator(initialValue: 0.0, trigger: refusals) { content, x in
    ///     content.offset(x: Pixels(Float(x)))
    /// } keyframes: { _ in
    ///     KeyframeTrack {
    ///         LinearKeyframe(6, duration: 0.05)
    ///         LinearKeyframe(-6, duration: 0.1)
    ///         LinearKeyframe(0, duration: 0.05)
    ///     }
    /// }
    /// ```
    public func keyframeAnimator<Value, Content: ElementGroup, K: Keyframes>(
        initialValue: Value, trigger: some Equatable,
        @ElementBuilder content: @escaping (Self, Value) -> Content,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> K
    ) -> KeyframeAnimator<Value, Content, K> where K.Value == Value {
        let base = self
        return KeyframeAnimator(initialValue: initialValue, mode: KeyframeAnimator<Value, Content, K>.triggerMode(trigger),
                                content: { content(base, $0) }, keyframes: keyframes)
    }

    /// Animates `content` through `keyframes` in a loop while `repeating` —
    /// SwiftUI's `keyframeAnimator(initialValue:repeating:content:keyframes:)`
    /// (`LK-I` item 11): `keyframes(initialValue)` is called once. While
    /// `repeating` is `false` the content shows `initialValue`.
    public func keyframeAnimator<Value, Content: ElementGroup, K: Keyframes>(
        initialValue: Value, repeating: Bool = true,
        @ElementBuilder content: @escaping (Self, Value) -> Content,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> K
    ) -> KeyframeAnimator<Value, Content, K> where K.Value == Value {
        let base = self
        return KeyframeAnimator(initialValue: initialValue, mode: .repeating(repeating),
                                content: { content(base, $0) }, keyframes: keyframes)
    }
}
