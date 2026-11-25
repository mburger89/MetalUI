import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// C10 lane 2: `keyframeAnimator` and `KeyframeAnimator` (rulings `LK-I` items
// 9–12, `LK-T` items 2 and 4; spec `2026-10-08-controls-looks-design.md` §4.2).
// SwiftUI's answers are probe `docs/probes/swiftui-controls-looks.swift` arms
// `K10`–`K14`, whose keyframes these fixtures copy: `LinearKeyframe(start,
// 0.1)` then `LinearKeyframe(start + 20, 0.1)`, `keyframes` logging the start
// it receives and `content` the value it shows.
//
// **No test sleeps** (CLAUDE.md "Animation"): each frame is a headless `Frame`
// built at an explicit timestamp over ONE shared `AnimationStore` — the
// window's own arrangement — so the clock is the argument, never a wall clock.

@MainActor
private final class AnimatorLog {
    var starts: [Double] = []
    var values: [Double] = []
    func value(_ v: Double) -> Double { values.append(v); return v }
    func start(_ v: Double) -> Double { starts.append(v); return v }
}

/// The probe's `KeyHost`: a 20-point box animated by the probe's keyframes,
/// rerun when `trigger` changes.
@MainActor
private func triggered(_ trigger: Int, _ log: AnimatorLog) -> some Element {
    Column {
        Box().frame(width: Pixels(20), height: Pixels(20))
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, value in
                let _ = log.value(value)
                content
            } keyframes: { start in
                KeyframeTrack {
                    LinearKeyframe(log.start(start), duration: 0.1)
                    LinearKeyframe(start + 20, duration: 0.1)
                }
            }
    }
}

/// Builds `root` into a frame at `time` over `store`.
@MainActor
@discardableResult
private func frame<E: Element>(_ root: E, at time: Double, _ store: AnimationStore,
                               recordsBounds: Bool = false) -> Frame {
    var root = root
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1,
                      timestamp: time, animationStore: store, recordsElementBounds: recordsBounds)
    frame.render(&root)
    return frame
}

private func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 1e-9 } ?? false }

/// **K10** (`LK-I` item 10). On appear the content shows the initial value and
/// `keyframes` is not called. Mutation: start a run on appear (`keyframes`
/// called with 0).
@Test @MainActor func theAnimatorShowsTheInitialValueAndCallsNoKeyframesOnAppearK10() {
    let store = AnimationStore(), log = AnimatorLog()
    frame(triggered(0, log), at: 0, store)
    frame(triggered(0, log), at: 0.5, store)
    #expect(log.starts.isEmpty, "keyframes called on appear: \(log.starts)")
    #expect(log.values == [0, 0], "content values \(log.values)")
}

/// **K11, K12** (`LK-I` item 10). A trigger change from rest calls
/// `keyframes(initialValue)` and runs from it: 0 → 10 at 0.15 s → 20, held; a
/// second trigger from rest starts from 0 again — the content jumps 20 → 0 —
/// although the content showed 20. Mutation: start from the held end value
/// (`keyframes(20)`).
@Test @MainActor func aTriggerFromRestRestartsFromTheInitialValueK11K12() {
    let store = AnimationStore(), log = AnimatorLog()
    frame(triggered(0, log), at: 0, store)
    frame(triggered(1, log), at: 1, store)
    frame(triggered(1, log), at: 1.15, store)
    frame(triggered(1, log), at: 1.6, store)
    #expect(log.starts == [0], "K11 keyframes(start:) \(log.starts)")
    #expect(log.values.count == 4 && near(log.values[1], 0) && near(log.values[2], 10) && near(log.values[3], 20),
            "K11 values \(log.values)")
    log.values = []
    frame(triggered(2, log), at: 2, store)
    frame(triggered(2, log), at: 2.6, store)
    #expect(log.starts == [0, 0], "K12 keyframes(start:) \(log.starts)")
    #expect(near(log.values.first, 0) && near(log.values.last, 20), "K12 the content jumps 20 → 0: \(log.values)")
}

/// **K13** (`LK-I` item 10). A trigger change mid-run calls `keyframes` with
/// the current value and runs from there: 10 at 0.15 s into the first run,
/// then 10 + 20. Mutation: restart from the initial value (`keyframes(0)`).
@Test @MainActor func aTriggerMidRunStartsFromTheCurrentValueK13() {
    let store = AnimationStore(), log = AnimatorLog()
    frame(triggered(0, log), at: 0, store)
    frame(triggered(1, log), at: 3, store)
    frame(triggered(2, log), at: 3.15, store)
    frame(triggered(2, log), at: 3.6, store)
    #expect(log.starts.count == 2 && near(log.starts[0], 0) && near(log.starts[1], 10),
            "K13 keyframes(start:) \(log.starts)")
    #expect(near(log.values[2], 10) && near(log.values.last, 30), "K13 values \(log.values)")
}

/// `LK-I` item 10: at the end the content holds the timeline's end value —
/// over several frames and a later one far past the end. Mutation: reset to
/// the initial value when the run ends.
@Test @MainActor func theAnimatorHoldsItsEndValueAtRest() {
    let store = AnimationStore(), log = AnimatorLog()
    frame(triggered(0, log), at: 0, store)
    frame(triggered(1, log), at: 1, store)
    for time in [1.2, 1.3, 5, 50] { frame(triggered(1, log), at: time, store) }
    #expect(log.values.suffix(4).allSatisfy { near($0, 20) }, "values at rest \(log.values)")
}

/// **K14** (`LK-I` item 11). A repeating animator calls `keyframes` once, with
/// the initial value, and loops: 10 at 0.15 s, 0 at 0.25 s (0.05 s into the
/// second loop, holding), 10 at 0.35 s. Mutation: call `keyframes` each cycle.
@Test @MainActor func repeatingLoopsAndCallsKeyframesOnceK14() {
    let store = AnimationStore(), log = AnimatorLog()
    func root() -> some Element {
        Column {
            Box().frame(width: Pixels(20), height: Pixels(20))
                .keyframeAnimator(initialValue: 0.0, repeating: true) { content, value in
                    let _ = log.value(value)
                    content
                } keyframes: { start in
                    KeyframeTrack {
                        LinearKeyframe(log.start(start), duration: 0.1)
                        LinearKeyframe(start + 20, duration: 0.1)
                    }
                }
        }
    }
    for time in [0, 0.15, 0.25, 0.35, 0.95] { frame(root(), at: time, store) }
    #expect(log.starts == [0], "K14 keyframes calls \(log.starts)")
    let expected = [0.0, 10, 0, 10, 10]
    #expect(log.values.count == expected.count && zip(log.values, expected).allSatisfy { abs($0 - $1) < 1e-9 },
            "K14 values \(log.values)")
}

/// `LK-I` item 12: while a timeline runs the frame notes an active animation;
/// on appear and at rest it notes nothing, so the display link pauses.
/// Mutation: always note.
@Test @MainActor func theAnimatorNotesAnimationOnlyWhileRunning() {
    let store = AnimationStore(), log = AnimatorLog()
    let appear = frame(triggered(0, log), at: 0, store)
    let started = frame(triggered(1, log), at: 1, store)
    let midway = frame(triggered(1, log), at: 1.1, store)
    let ended = frame(triggered(1, log), at: 1.3, store)
    let rest = frame(triggered(1, log), at: 2, store)
    #expect(!appear.hasActiveAnimations, "appear")
    #expect(started.hasActiveAnimations && midway.hasActiveAnimations, "running")
    #expect(!ended.hasActiveAnimations && !rest.hasActiveAnimations, "at rest")
}

/// `LK-I` item 9. The scope takes no identity level: the box under it has the
/// id it has without the animator, so a `@State` under it survives adding one,
/// and the record is a store entry, never a `StateTable` slot (no `$keyframes`
/// name reaches the table). Mutation: wrap the content in an `IdentifiedGroup`.
@Test @MainActor func theKeyframeScopeTakesNoIdentityLevel() {
    let store = AnimationStore(), log = AnimatorLog()
    func boxIDs(_ frame: Frame) -> Set<GlobalElementID> {
        Set(frame.elementBounds.filter { $0.value.size.width.value == 20 && $0.value.size.height.value == 20 }.keys)
    }
    let plain = frame(Column { Box().frame(width: Pixels(20), height: Pixels(20)) }, at: 0, AnimationStore(),
                      recordsBounds: true)
    let animated = frame(triggered(0, log), at: 0, store, recordsBounds: true)
    #expect(!boxIDs(plain).isEmpty && boxIDs(plain) == boxIDs(animated),
            "plain \(boxIDs(plain)) animated \(boxIDs(animated))")
    #expect(store.count >= 1, "the record is a store entry")
    #expect(!animated.stateTable.ids.contains { String(describing: $0).contains("$keyframes") },
            "a $keyframes name reached the StateTable")
}

/// `KeyframeAnimator`'s typed entry (proposal content stays proposal content,
/// `LK-I` item 9) is its own copy: a `ProposalText` framed by the value inside
/// an `HStack` is 10 + value wide mid-run. Mutation: build the typed entry's
/// content with the initial value.
@Test @MainActor func keyframeAnimatorKeepsProposalContentProposal() {
    let store = AnimationStore()
    func root(_ trigger: Int) -> some Element {
        Column {
            HStack {
                KeyframeAnimator(initialValue: 0.0, trigger: trigger) { value in
                    ProposalText("x").frame(width: Pixels(Float(10 + value)), height: Pixels(7))
                } keyframes: { _ in
                    KeyframeTrack { LinearKeyframe(20.0, duration: 0.2) }
                }
            }
        }
    }
    func width(_ frame: Frame) -> Float? {
        frame.elementBounds.values.first { $0.size.height.value == 7 }?.size.width.value
    }
    #expect(width(frame(root(0), at: 0, store, recordsBounds: true)) == 10)
    frame(root(1), at: 1, store)
    #expect(width(frame(root(1), at: 1.1, store, recordsBounds: true)) == 20, "10 + 10 at half way")
}

/// A trigger animator over the probe's keyframes whose `content` logs into `log`.
@MainActor
private func animated<E: ElementGroup>(_ element: E, _ trigger: Int, _ log: AnimatorLog) -> some ElementGroup {
    element.keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, value in
        let _ = log.value(value)
        content
    } keyframes: { start in
        KeyframeTrack {
            LinearKeyframe(log.start(start), duration: 0.1)
            LinearKeyframe(start + 20, duration: 0.1)
        }
    }
}

/// `LK-I` item 9, `LK-V` item 5: **a keyframe animator's record is keyed by its
/// position** — `$keyframes<depth>` under `.child(of: parent, at: cursor)` — so
/// two sibling animators in one container keep two records over one shared
/// store (the shipped `keyframesSection` has two in one `Row`). Arm 1: two
/// trigger animators; only the second's trigger changes, and the first stays at
/// its initial value with `keyframes` never called while the second runs 0 → 10
/// → 20. Arm 2: a trigger animator beside a repeating one; the trigger animator
/// stays at rest while its sibling loops.
///
/// Mutation **V4**: `currentValue`'s owner `child(of: parent, at: cursor, …)` →
/// `at: 0` (the siblings share one record; the resting one sees the other's
/// trigger and starts a run).
@Test @MainActor func siblingKeyframeAnimatorsKeepTheirOwnRecordsV4() {
    let store = AnimationStore(), a = AnimatorLog(), b = AnimatorLog()
    func root(_ ta: Int, _ tb: Int) -> some Element {
        Row {
            animated(Box().frame(width: Pixels(20), height: Pixels(20)), ta, a)
            animated(Box().frame(width: Pixels(20), height: Pixels(20)), tb, b)
        }
    }
    for (time, tb) in [(0.0, 0), (1, 1), (1.05, 1), (1.15, 1), (1.6, 1)] { frame(root(0, tb), at: time, store) }
    #expect(a.starts.isEmpty && a.values.allSatisfy { near($0, 0) }, "the resting sibling moved: \(a.starts) \(a.values)")
    #expect(b.starts == [0] && near(b.values[3], 10) && near(b.values.last, 20), "the running sibling: \(b.values)")

    let mixed = AnimationStore(), c = AnimatorLog(), loop = AnimatorLog()
    func mixedRoot() -> some Element {
        Row {
            animated(Box().frame(width: Pixels(20), height: Pixels(20)), 0, c)
            Box().frame(width: Pixels(20), height: Pixels(20))
                .keyframeAnimator(initialValue: 0.0, repeating: true) { content, value in
                    let _ = loop.value(value)
                    content
                } keyframes: { start in
                    KeyframeTrack {
                        LinearKeyframe(start, duration: 0.1)
                        LinearKeyframe(start + 20, duration: 0.1)
                    }
                }
        }
    }
    for time in [0, 0.15, 0.35] { frame(mixedRoot(), at: time, mixed) }
    #expect(c.starts.isEmpty && c.values.allSatisfy { near($0, 0) }, "the trigger sibling moved: \(c.values)")
    #expect(loop.values.count == 3 && near(loop.values[1], 10) && near(loop.values[2], 10), "the loop: \(loop.values)")
}

/// `LK-I` item 9, `LK-V` item 5: two `.keyframeAnimator`s stacked on one
/// element sit at one position and keep two records through the depth counter
/// (`$keyframes0`, `$keyframes1`). Only the outer trigger changes: the outer
/// runs (10 at 0.15 s) while the inner stays at 0 with `keyframes` never called.
///
/// Mutation **V1b**: `AnimationStore.withKeyframeScope`'s increment and
/// deferred decrement deleted (both at depth 0; one record).
@Test @MainActor func stackedKeyframeAnimatorsKeepTwoRecordsV1b() {
    let store = AnimationStore(), inner = AnimatorLog(), outer = AnimatorLog()
    func root(_ to: Int) -> some Element {
        Column { animated(animated(Box().frame(width: Pixels(20), height: Pixels(20)), 0, inner), to, outer) }
    }
    for (time, to) in [(0.0, 0), (1, 1), (1.15, 1), (1.6, 1)] { frame(root(to), at: time, store) }
    #expect(outer.starts == [0] && near(outer.values[2], 10) && near(outer.values.last, 20), "outer \(outer.values)")
    #expect(inner.starts.isEmpty && inner.values.allSatisfy { near($0, 0) },
            "inner moved: \(inner.starts) \(inner.values)")
}

/// **K12** (`LK-I` item 10) when no build saw the run end: a trigger change
/// in the first build after the end (keyframes 0 → 20 over 0.2 s; frames at 0,
/// 1, 1.19, then 1.21 with a new trigger) restarts from the initial value, not
/// the held end value — in a real window the write lands within one frame
/// interval of the end. Mutation: the trigger branch's end-of-run check
/// removed (`keyframes(20)`).
@Test @MainActor func aTriggerJustAfterAnUnseenEndRestartsFromTheInitialValue() {
    let store = AnimationStore(), log = AnimatorLog()
    for (time, trigger) in [(0.0, 0), (1, 1), (1.19, 1), (1.21, 2)] { frame(triggered(trigger, log), at: time, store) }
    #expect(log.starts == [0, 0], "keyframes(start:) \(log.starts)")
    #expect(near(log.values.last, 0), "the restart shows \(log.values)")
}
