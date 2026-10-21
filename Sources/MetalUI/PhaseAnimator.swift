import MetalUICore
import MetalUILayout

// MARK: - `phaseAnimator` (G1 lane 2, rulings `GS-H`, `GS-I`, `GS-J`, `GS-K`)
//
// One more transparent scope beside `keyframeAnimator` (`KeyframeAnimator.swift`), built the same
// way: no node, no identity level, `LifecycleScope`'s shape, whose state is a `PhaseRecord` in the
// window's `AnimationStore` keyed `$phase<depth>` under the position it sits at — **never a
// `StateTable` slot** (the seven reserved slots unmoved). The depth counter is
// `keyframeDepth`'s, shared (`withKeyframeScope`): the key names differ, so one counter cannot
// collide. During the build it reads its record, takes at most one step, builds its content with
// the phase the record names under a transaction carrying that phase's animation, and, while it
// runs, notes an active animation. A record no build touches for a frame is dropped by the
// store's sweep, so content that leaves and returns starts at `phases[0]`.

/// A phase animator's state between builds (`GS-I`).
struct PhaseRecord {
    /// The trigger the last build saw (`nil` for a cycling animator).
    var trigger: Any?
    /// The index of the phase shown.
    var index: Int
    /// When the current step is scheduled to have started.
    var stepStart: Double
    /// How long the current step is held before the next one.
    var wait: Double
    /// Whether steps are still to come.
    var running: Bool
    /// Steps taken by the current trigger run (`1 … count`; the last returns to the first phase).
    var stepsTaken: Int
}

/// What a phase animator watches: a trigger compared with `==`, or nothing (it cycles).
enum PhaseAnimatorMode {
    case trigger(Any, matches: (Any) -> Bool)
    case cycling
}

/// One build's resolution of a `PhaseRecord`.
struct PhaseResolution {
    var record: PhaseRecord
    /// The index of the phase to build.
    var index: Int
    /// The animation of the phase just entered, when this build took a step (`.some(nil)` is a
    /// step whose animation is `nil`: a snap).
    var stepAnimation: Animation??
    /// Whether the window must keep drawing.
    var active: Bool
}

enum PhaseStepping {
    /// One build's step of the record (`GS-I`): at most one step, taken when the scheduled hold of
    /// the current phase has elapsed, or at once on a trigger change.
    static func resolve(_ record: PhaseRecord?, mode: PhaseAnimatorMode, count: Int, now: Double,
                        animation: (Int) -> Animation?, equal: (Int, Int) -> Bool) -> PhaseResolution {
        // Enters phase `new`: its animation is asked once, for the transaction and the hold.
        func enter(_ r: inout PhaseRecord, _ new: Int, scheduled: Double) -> Animation?? {
            let anim = animation(new)
            let hold = equal(r.index, new) ? 0 : (anim?.nominalDuration ?? 0)
            // The scheduled start, unless this build is late by a whole hold: no cumulative drift
            // at 60 Hz, no burst after a stall.
            r.stepStart = now - scheduled >= hold - 1e-9 ? now : scheduled
            r.wait = hold
            r.index = new
            return .some(anim)
        }
        // Due when the scheduled hold has elapsed, within a nanosecond: `1.2 - 0.8` is `0.3999…`.
        func due(_ r: PhaseRecord) -> Bool { now - (r.stepStart + r.wait) >= -1e-9 }
        switch mode {
        case .cycling:
            guard var r = record else {
                let r = PhaseRecord(trigger: nil, index: 0, stepStart: now, wait: 0, running: count >= 2, stepsTaken: 0)
                return PhaseResolution(record: r, index: 0, stepAnimation: nil, active: r.running)
            }
            guard count >= 2 else {
                r.index = 0; r.running = false
                return PhaseResolution(record: r, index: 0, stepAnimation: nil, active: false)
            }
            r.running = true
            if r.index >= count { r.index = 0 }
            var stepped: Animation?? = nil
            if due(r) {
                stepped = enter(&r, (r.index + 1) % count, scheduled: r.stepStart + r.wait)
            }
            return PhaseResolution(record: r, index: r.index, stepAnimation: stepped, active: true)
        case .trigger(let trigger, let matches):
            guard var r = record else {
                let r = PhaseRecord(trigger: trigger, index: 0, stepStart: now, wait: 0, running: false, stepsTaken: 0)
                return PhaseResolution(record: r, index: 0, stepAnimation: nil, active: false)
            }
            var stepped: Animation?? = nil
            if r.index >= count { r.index = 0 }
            if let previous = r.trigger, !matches(previous) {
                // A change restarts at once from `phases[1]`, wherever a run had got to (`P4`).
                if count >= 2 {
                    r.running = true
                    r.stepsTaken = 1
                    stepped = enter(&r, 1, scheduled: now)
                } else {
                    r.running = false
                    r.index = 0
                }
            } else if r.running, count >= 2, due(r) {
                r.stepsTaken += 1
                stepped = enter(&r, r.stepsTaken % count, scheduled: r.stepStart + r.wait)
            }
            r.trigger = trigger
            // The step back to the first phase ends the run.
            if r.running, r.stepsTaken >= count { r.running = false }
            return PhaseResolution(record: r, index: r.index, stepAnimation: stepped, active: r.running)
        }
    }
}

/// Content animated through phases — SwiftUI's `PhaseAnimator`, and what
/// `.phaseAnimator(_:trigger:content:animation:)` and `.phaseAnimator(_:content:animation:)` return
/// (`GS-H`, `GS-I`, `GS-J`).
///
/// **On appear** the content shows `phases[0]` and `animation` is not called. **Without a trigger**
/// it steps to `phases[1]` at once and then cycles `1, 2, … , 0, 1, …` for ever, one step each
/// `d`, where `d` is the duration of the animation of the phase just entered (a spring's
/// `duration:`; `0` for a `nil` animation, which snaps its phase and is followed by the next step
/// at once). **With a trigger**, each change runs through `phases[1]` … and back to `phases[0]`
/// once and ends; a change mid-run restarts at once from `phases[1]`. Each phase's content is
/// built under a transaction whose animation is `animation(phase)`. Fewer than two phases run
/// nothing. While steps are due the window keeps drawing (`Frame.noteActiveAnimation()`); at rest
/// nothing is raised.
///
/// **Transparent**: the content keeps the parent and position it would have without the animator,
/// so no `@State` moves when one is added; the record lives in the window's animation store, never
/// in `StateTable`. **A `Self`-returning decoration written after it does not compile** (divergence
/// 120's rule): write it inside the content closure. **Reduce Motion is not consulted** (`GS-K`).
/// The modifier's content closure receives the element itself, not a placeholder (divergence 169's
/// rule). An empty phase list traps.
public struct PhaseAnimator<Phase: Equatable, Content: ElementGroup>: ElementGroup {
    let phases: [Phase]
    let mode: PhaseAnimatorMode
    let content: (Phase) -> Content
    let animation: (Phase) -> Animation?

    init(phases: [Phase], mode: PhaseAnimatorMode, content: @escaping (Phase) -> Content,
         animation: @escaping (Phase) -> Animation?) {
        self.phases = phases
        self.mode = mode
        self.content = content
        self.animation = animation
    }

    /// Content built from each phase in turn, rerun each time `trigger` changes — SwiftUI's
    /// `PhaseAnimator(_:trigger:content:animation:)`.
    public init<S: Sequence>(_ phases: S, trigger: some Equatable,
                             @ElementBuilder content: @escaping (Phase) -> Content,
                             animation: @escaping (Phase) -> Animation? = { _ in .default })
    where S.Element == Phase {
        self.init(phases: Array(phases), mode: Self.triggerMode(trigger), content: content, animation: animation)
    }

    /// Content built from each phase in turn, cycling for ever — SwiftUI's
    /// `PhaseAnimator(_:content:animation:)`.
    public init<S: Sequence>(_ phases: S,
                             @ElementBuilder content: @escaping (Phase) -> Content,
                             animation: @escaping (Phase) -> Animation? = { _ in .default })
    where S.Element == Phase {
        self.init(phases: Array(phases), mode: .cycling, content: content, animation: animation)
    }

    static func triggerMode<T: Equatable>(_ trigger: T) -> PhaseAnimatorMode {
        .trigger(trigger, matches: { ($0 as? T) == trigger })
    }

    /// The content built this frame, its layout and the transaction it was built under.
    public struct Layout {
        var content: Content
        var contentLayout: Content.GroupLayout
        var transaction: Transaction
    }

    /// The phase this build shows and the transaction its content is built under, reading and
    /// writing the record at `$phase<depth>` under the position `.child(of: parent, at: cursor)`.
    func resolveStep(under parent: GlobalElementID?, at cursor: Int, frame: Frame) -> (Phase, Transaction) {
        precondition(!phases.isEmpty, "phaseAnimator needs at least one phase; got none")
        let store = frame.animationStore
        let owner = GlobalElementID.child(of: parent, at: cursor, name: nil)
        let key = GlobalElementID.child(of: owner, at: 0, name: ElementID("$phase\(store.keyframeDepth)"))
        let record = store.value(at: key, as: PhaseRecord.self)
        let phases = self.phases
        let resolution = PhaseStepping.resolve(record, mode: mode, count: phases.count, now: frame.timestamp,
                                               animation: { animation(phases[$0]) },
                                               equal: { phases[$0] == phases[$1] })
        store.set(resolution.record, at: key)
        if resolution.active { frame.noteActiveAnimation() }
        var transaction = frame.transactionTop
        if let stepped = resolution.stepAnimation, !transaction.disablesAnimations {
            transaction.animation = stepped
        }
        return (phases[resolution.index], transaction)
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        let (phase, transaction) = resolveStep(under: parent, at: cursor, frame: pass.frame)
        let (built, nodes, layout) = pass.frame.withTransactionScope(transaction) {
            var built = content(phase)
            let (nodes, layout) = pass.frame.animationStore.withKeyframeScope {
                built.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
            }
            return (built, nodes, layout)
        }
        return (nodes, Layout(content: built, contentLayout: layout, transaction: transaction))
    }

    public mutating func prepaintGroup(layout: inout Layout, pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // No push: nothing in prepaint reads the transaction.
        layout.content.prepaintGroup(layout: &layout.contentLayout, pass: &pass)
    }

    public mutating func paintGroup(layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        // The transaction layout resolved, re-pushed: a step taken twice would read "unchanged".
        pass.frame.withTransactionScope(layout.transaction) {
            layout.content.paintGroup(layout: &layout.contentLayout, prepaint: &prepaint, pass: &pass)
        }
    }
}

/// **The typed entry is a line-for-line copy of the untyped one** (a copy of a pinned
/// implementation is unpinned; `phaseAnimatorKeepsProposalContentProposalGSH` pins it).
extension PhaseAnimator: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                                    pass: inout LayoutPass) -> ([ProposalNodeID], Layout) {
        let (phase, transaction) = resolveStep(under: parent, at: cursor, frame: pass.frame)
        let (built, nodes, layout) = pass.frame.withTransactionScope(transaction) {
            var built = content(phase)
            let (nodes, layout) = pass.frame.animationStore.withKeyframeScope {
                built.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
            }
            return (built, nodes, layout)
        }
        return (nodes, Layout(content: built, contentLayout: layout, transaction: transaction))
    }
}

extension ElementGroup {
    /// Animates `content` through `phases` each time `trigger` changes — SwiftUI's
    /// `phaseAnimator(_:trigger:content:animation:)` (`GS-H`, `GS-I`). `content` receives this
    /// group and the current phase; `animation` is asked once for each phase entered and the phase's
    /// content is built under it (`nil` snaps). Proposal content stays proposal content.
    ///
    /// ```swift
    /// Box().phaseAnimator([1.0, 1.2, 1.0], trigger: taps) { content, scale in
    ///     content.scaleEffect(scale)
    /// } animation: { _ in .linear(duration: 0.15) }
    /// ```
    public func phaseAnimator<Phase: Equatable, Content: ElementGroup, S: Sequence>(
        _ phases: S, trigger: some Equatable,
        @ElementBuilder content: @escaping (Self, Phase) -> Content,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> PhaseAnimator<Phase, Content> where S.Element == Phase {
        let base = self
        return PhaseAnimator(phases: Array(phases), mode: PhaseAnimator<Phase, Content>.triggerMode(trigger),
                             content: { content(base, $0) }, animation: animation)
    }

    /// Animates `content` through `phases` for ever — SwiftUI's
    /// `phaseAnimator(_:content:animation:)` (`GS-I`): it steps to `phases[1]` at once and cycles,
    /// each step held for the duration of the animation of the phase entered.
    public func phaseAnimator<Phase: Equatable, Content: ElementGroup, S: Sequence>(
        _ phases: S,
        @ElementBuilder content: @escaping (Self, Phase) -> Content,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> PhaseAnimator<Phase, Content> where S.Element == Phase {
        let base = self
        return PhaseAnimator(phases: Array(phases), mode: .cycling,
                             content: { content(base, $0) }, animation: animation)
    }
}
