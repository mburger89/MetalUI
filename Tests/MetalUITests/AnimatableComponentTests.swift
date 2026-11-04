import Foundation
import Observation
import Testing
import MetalUICore
import MetalUILayout
import MetalUITesting
import MetalUITestSupport
@testable import MetalUI

// R4-3 PR E (`VA-I`, record 209): `Component & Animatable`. SwiftUI's side is probe
// `docs/probes/swiftui-animatable.swift` (`VA5`, `VA7`, `VA7s`; recorded in `swiftui-animatable-run.txt`).
// A component is interpolated in the LAYOUT phase (`requestGroupLayout`), into `self`, after its id is known and
// before its `@State` binds and its `content` is read, through `animatedVector` (`AN-AA`'s number-in-layout rule).
//
// **No test sleeps**: headless frames at chosen timestamps (`WrapperHarness`) or a `TestWindow` driven by
// `advance(by:)`. Every `note` below is made by a `content` getter, so it records the value the BODY saw.

private let linear1 = Animation.linear(duration: 1)

/// An `Animatable` component with one `Double`: its `content` notes `x` and puts a width-recording layout at
/// `100 + x` (`VA5`). **The frame's own animation is switched off** (`.transaction`), so the widths the layout is
/// proposed come only from the component's interpolated `x`: otherwise the frame's declared width animates
/// itself (divergence 96) and a component that does not interpolate would read the same.
private struct Counter: Component, Animatable {
    var x: Double
    nonisolated var animatableData: Double {
        get { x }
        set { x = newValue }
    }
    var content: some ElementGroup {
        let _ = acNote("counter", x)
        ProposalLayoutContainer(RecordsProposedWidth(log: acWidths)) { Rectangle(width: Pixels(10), height: Pixels(10)) }
            .frame(width: Pixels(Float(100 + x)), height: Pixels(40))
            .transaction { $0.animation = nil }
    }
}

/// The same component declaring nothing.
private struct PlainCounter: Component {
    var x: Double
    var content: some ElementGroup {
        let _ = acNote("plain", x)
        Box().frame(width: Pixels(Float(100 + x)), height: Pixels(20)).background(.accent)
    }
}

/// An `Animatable` component whose data is empty: a conformance that animates nothing.
private struct EmptyData: Component, Animatable {
    var x: Double
    var content: some ElementGroup {
        let _ = acNote("empty", x)
        Box().frame(width: Pixels(Float(100 + x)), height: Pixels(20)).background(.accent)
    }
}

@MainActor private func counterTree(_ x: Double) -> some Element {
    DifferentialRoot(width: 400, height: 100) { Counter(x: x) }
}

@MainActor private func last(_ key: String) -> Double? { acSeen[key]?.last }

// MARK: - The body sees the interpolated value (VA5)

/// **A `Component & Animatable` runs its `content` at the interpolated value** (`VA5`): `x` 0 to 200 under a
/// one-second linear animation is read as 0 by the change frame, 100 half-way and 200 once landed. Mutations
/// **ME1** (the constrained witness removed), **ME4** (interpolated after the bind).
@Test @MainActor func anAnimatableComponentsContentSeesInterpolatedValues() {
    acSeen = [:]
    let h = WrapperHarness()
    h.frame(0, nil, counterTree(0))
    h.frame(0, linear1, counterTree(200))
    #expect(last("counter") == 0, "the change frame reads its own from: \(String(describing: last("counter")))")
    h.frame(0.5, nil, counterTree(200))
    #expect(abs((last("counter") ?? -1) - 100) < 0.01, "half-way: \(String(describing: last("counter")))")
    h.frame(1.5, nil, counterTree(200))
    #expect(last("counter") == 200, "landed at the declared value")
    let before = acSeen["counter"]?.count ?? 0
    h.frame(2.5, nil, counterTree(200))
    #expect((acSeen["counter"]?.count ?? 0) == before + 1 && last("counter") == 200, "and stays")
}

/// **Its child is laid out at the interpolated width** (`VA5`): the proposal layout under `.frame(width: 100 + x)`
/// is offered the widths in between (SwiftUI's `P1'` plain frame sees only 300, the animatable body's child
/// 100.1...300), and the last one is 300.
@Test @MainActor func itsChildIsProposedInterpolatedWidths() throws {
    acSeen = [:]
    acWidths.widths.removeAll()
    let h = WrapperHarness()
    h.frame(0, nil, counterTree(0))
    h.frame(0, linear1, counterTree(200))
    acWidths.widths.removeAll()
    h.frame(0.5, nil, counterTree(200))
    #expect(acWidths.widths.contains { abs($0 - 200) < 0.1 }, "half-way the child is proposed 200: \(acWidths.widths)")
    #expect(!acWidths.widths.contains(300), "and not the final 300: \(acWidths.widths)")
    acWidths.widths.removeAll()
    h.frame(1.5, nil, counterTree(200))
    #expect(acWidths.widths.contains(300), "landed: 300: \(acWidths.widths)")
}

// MARK: - A component that does not animate pays nothing

/// **A non-animatable component pays no track** (a count pin): under the same transaction a `Component` that is
/// not `Animatable` leaves `vectorTrackRebuilds` at 0 and adds no `AnimationStore` entry over the identical
/// content written inline, its `content` reads the declared value at once, and an `Animatable` component whose
/// data is `EmptyAnimatableData` writes no track either. Mutation **ME5** (the empty-data guard removed: a track
/// is stored for the empty component).
@Test @MainActor func aNonAnimatableComponentPaysNoTrack() {
    acSeen = [:]
    func run<C: ElementGroup>(_ make: (Double) -> C) -> (rebuilds: Int, entries: Int, interpolations: Int) {
        let h = WrapperHarness()
        h.frame(0, nil, DifferentialRoot(width: 400, height: 100) { make(0) })
        h.frame(0, linear1, DifferentialRoot(width: 400, height: 100) { make(200) })
        var interpolations = 0
        for t in [0.25, 0.5, 0.75, 1.5, 2.5] {
            let f = h.frame(t, nil, DifferentialRoot(width: 400, height: 100) { make(200) })
            _ = f
            interpolations += h.store.lastFrameInterpolations
        }
        return (h.store.vectorTrackRebuilds, h.store.count, interpolations)
    }
    let plain = run { PlainCounter(x: $0) }
    let inline = run { x in Box().frame(width: Pixels(Float(100 + x)), height: Pixels(20)).background(.accent) }
    let empty = run { EmptyData(x: $0) }
    #expect(plain.rebuilds == 0 && inline.rebuilds == 0 && empty.rebuilds == 0, "no track: \(plain) \(inline) \(empty)")
    #expect(plain.entries == inline.entries, "a plain component adds no store entry: \(plain.entries) vs \(inline.entries)")
    #expect(empty.entries == inline.entries, "nor does an empty-data one: \(empty.entries) vs \(inline.entries)")
    #expect(plain.interpolations == inline.interpolations, "and no interpolation: \(plain.interpolations) vs \(inline.interpolations)")
    #expect(acSeen["plain"]?.dropFirst().first == 200, "the plain body reads the declared value at once: \(acSeen["plain"] ?? [])")
}

// MARK: - Equatable (VA7, VA7s)

@Observable @MainActor final class ACModel {
    var x = 0.0
    var tick = 0
}

/// An `Animatable` and `Equatable` component, made `.equatable()` by its parent (`VA7`).
private struct EqCounter: Component, Animatable, @MainActor Equatable {
    var x: Double
    nonisolated var animatableData: Double {
        get { x }
        set { x = newValue }
    }
    static func == (l: EqCounter, r: EqCounter) -> Bool { l.x == r.x }
    var content: some ElementGroup {
        let _ = acNote("eq", x)
        // The frame's own animation is off, so only the component's interpolation moves the width.
        Box().frame(width: Pixels(Float(100 + x)), height: Pixels(20)).background(.accent)
            .transaction { $0.animation = nil }
    }
}

private struct EqRoot: Component {
    let model: ACModel
    var content: some ElementGroup {
        let _ = model.tick
        VStack(spacing: 0) { EqCounter(x: model.x).equatable() }
    }
}

private var acVerifying: Bool { ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] == "1" }

@MainActor private func eqWindow(_ model: ACModel, retained: Bool = true) throws -> TestWindow {
    let w = try TestWindow(size: Size(width: Pixels(400), height: Pixels(200))) { VStack(spacing: 0) { EqRoot(model: model) } }
    w.window.testingRetainedSubtrees = retained
    for _ in 0..<6 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    return w
}

/// **`.equatable()` runs the body in flight and skips it settled** (`VA7`, `VA7s`): `EqCounter` is interpolated
/// BEFORE `==`, so every frame of a flight misses (the value moves) and a frame after it lands, on an unrelated
/// parent change, hits (no body call). Mutations **ME2** (compared before interpolating: the declared value is
/// equal from the change frame on, so the body never re-runs in flight) and **ME3** (the `.equatable()` entry
/// does not interpolate).
@Test @MainActor func anEquatableAnimatableComponentRunsInFlightAndSkipsSettled() throws {
    acSeen = [:]
    let model = ACModel()
    let w = try eqWindow(model)
    let rest = acSeen["eq"]?.count ?? 0
    model.tick += 1
    w.advance(by: 0.05)
    #expect((acSeen["eq"]?.count ?? 0) == rest, "VA7s: an unrelated parent change, value equal, no body call")
    withAnimation(linear1) { model.x = 200 }
    var seen: [Double] = []
    for i in 0..<5 {
        let before = acSeen["eq"]?.count ?? 0
        w.advance(by: 0.1)
        // The change frame reads its own `from`, equal to the last evaluation: a hit, as the probe's first tick.
        #expect((acSeen["eq"]?.count ?? 0) == before + (i == 0 ? 0 : 1), "VA7: the body runs once in flight: \(acSeen["eq"] ?? [])")
        if i > 0 { seen.append(last("eq") ?? -1) }
    }
    #expect(zip(seen, seen.dropFirst()).allSatisfy { $0 < $1 }, "and sees a rising value: \(seen)")
    #expect(seen.last! < 200 && seen.first! > 0, "in between: \(seen)")
    #expect(seen.count == 4, "set up: four in-flight evaluations")
    for _ in 0..<8 { w.advance(by: 0.1) }
    #expect(last("eq") == 200, "landed")
    let settled = acSeen["eq"]?.count ?? 0
    model.tick += 1
    w.advance(by: 0.1)
    w.advance(by: 0.1)
    #expect((acSeen["eq"]?.count ?? 0) == settled, "VA7s: settled again, no body call")
}

/// **An animatable component in a retained (grafted, memoized) occurrence is not replayed frozen**: every frame
/// of the flight paints a new width, equal to the oracle's (retention off), and the occurrence grafted before
/// it started. Mutations **ME2** (compared before interpolating) and **ME3** redden it. **ME6** (the hook before the build
/// window opens) is **green**, reported: the interpolated value differs each frame, so the memo misses and the occurrence is
/// rebuilt whatever the window saw; the placement inside the window is not load-bearing.
@Test(.enabled(if: !acVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss"))
@MainActor func anAnimatableComponentInARetainedOccurrenceIsNotFrozen() throws {
    func script(retained: Bool) throws -> (widths: [Double], rest: FrameWork, redos: [Int]) {
        let model = ACModel()
        let w = try eqWindow(model, retained: retained)
        let rest = w.lastFrameWork
        withAnimation(linear1) { model.x = 200 }
        var widths: [Double] = [], redos: [Int] = []
        for _ in 0..<6 {
            w.advance(by: 0.1)
            widths.append(w.scene.rects.map { Double($0.bounds.size.width) }.max() ?? -1)
            redos.append(w.lastFrameWork.retainedRedos)
        }
        return (widths, rest, redos)
    }
    let on = try script(retained: true), off = try script(retained: false)
    try #require(on.rest.retainedHits > 0 || on.rest.retainedGrafts > 0, "set up: the occurrence is retained at rest: \(on.rest)")
    #expect(on.widths == off.widths, "equal to the oracle: \(on.widths) vs \(off.widths)")
    for pair in zip(on.widths, on.widths.dropFirst()).prefix(4) { #expect(pair.1 > pair.0, "it moves every frame: \(on.widths)") }
    #expect(on.redos.allSatisfy { $0 == 0 }, "and nothing is redone: \(on.redos)")
}

// MARK: - The other entries

/// **A typed entry animates too** (`aTypedEntryAnimatesToo`): `Counter(x:).width(300)` (a `StyledComponent`,
/// the distributing modifiers' type) reaches the constrained witness through `component.requestGroupLayout`, so
/// the body sees the interpolation. Mutation **ME3b** (the `.equatable()` entry skips) is `ME3` above; this arm
/// separates a `StyledComponent` that no longer forwards.
@Test @MainActor func aTypedEntryAnimatesToo() {
    acSeen = [:]
    let h = WrapperHarness()
    func tree(_ x: Double) -> some Element {
        DifferentialRoot(width: 400, height: 100) { Counter(x: x).padding(2) }
    }
    h.frame(0, nil, tree(0))
    h.frame(0, linear1, tree(200))
    h.frame(0.5, nil, tree(200))
    #expect(abs((last("counter") ?? -1) - 100) < 0.01, "through `.padding`: \(String(describing: last("counter")))")
    h.frame(1.5, nil, tree(200))
    #expect(last("counter") == 200)
}

/// **A conformance written in another file is selected** (`aWitnessDeclaredInAnotherFileIsSelected`):
/// `SplitCounter` is a `Component` in `AnimatableComponentFixtures.swift` and `Animatable` only in
/// `AnimatableComponentSplit.swift`, in the test module (not MetalUI's), and still interpolates, through both the
/// bare and the `.equatable()` entry. Mutation **ME1** (the constrained `requestGroupLayout` removed).
@Test @MainActor func aWitnessDeclaredInAnotherFileIsSelected() {
    acSeen = [:]
    let h = WrapperHarness()
    func tree(_ x: Double) -> some Element { DifferentialRoot(width: 400, height: 100) { SplitCounter(x: x) } }
    h.frame(0, nil, tree(0))
    h.frame(0, linear1, tree(200))
    h.frame(0.5, nil, tree(200))
    #expect(abs((last("split") ?? -1) - 100) < 0.01, "interpolated: \(acSeen["split"] ?? [])")
}

// MARK: - No phase write, no slot (stop conditions)

/// An `Animatable` whose setter rebuilds `self` from its memberwise `init`, so every `@State` wrapper of the
/// interpolated copy is fresh and UNBOUND. It increments its own state in `content` (the `Counter` fixture of
/// `ComponentTests`).
private struct Rebuilds: Component, Animatable {
    var x: Double
    @State var taps = 0
    nonisolated var animatableData: Double {
        get { x }
        set { self = MainActor.assumeIsolated { Rebuilds(x: newValue) } }
    }
    var content: some ElementGroup {
        taps += 1
        let _ = acNote("taps", Double(taps))
        return Box().frame(width: Pixels(Float(100 + x)), height: Pixels(20)).background(.accent)
    }
}

/// **The interpolation is written before the bind**: a component whose setter replaces `self` keeps its `@State`
/// through a flight (`taps` counts 1, 2, 3, 4), because the copy that is bound is the interpolated one. Bound
/// after, the copy is unbound and its writes are discarded (`taps` reads 1 every frame). Mutation **ME4**.
@Test @MainActor func aSetterThatRebuildsSelfKeepsItsState() {
    acSeen = [:]
    let h = WrapperHarness()
    func tree(_ x: Double) -> some Element { DifferentialRoot(width: 400, height: 100) { Rebuilds(x: x) } }
    h.frame(0, nil, tree(0))
    h.frame(0, linear1, tree(200))
    h.frame(0.25, nil, tree(200))
    h.frame(0.5, nil, tree(200))
    #expect(acSeen["taps"] == [1, 2, 3, 4], "state survives the interpolation: \(acSeen["taps"] ?? [])")
}

/// **Interpolation writes no state and asks for no frame**: in flight the frame notes an active animation
/// (`hasActiveAnimations`) and never `requestAnotherFrame()` (`wantsAnotherFrame`), the `StateTable` holds the
/// slots it held at rest, and the settled frame does no store work (`vectorTrackRebuilds` unmoved).
@Test @MainActor func interpolationWritesNoStateAndRequestsNoFrame() throws {
    acSeen = [:]
    let h = WrapperHarness()
    h.frame(0, nil, counterTree(0))
    let slots = h.table.count
    h.frame(0, linear1, counterTree(200))
    let mid = h.frame(0.5, nil, counterTree(200))
    #expect(mid.hasActiveAnimations, "in flight: live animation")
    #expect(!mid.wantsAnotherFrame, "and never requestAnotherFrame()")
    #expect(h.table.count == slots, "no StateTable slot: \(h.table.count) vs \(slots)")
    h.frame(1.5, nil, counterTree(200))
    let settled = h.store.vectorTrackRebuilds
    for t in [2.0, 3.0, 4.0] {
        let f = h.frame(t, nil, counterTree(200))
        #expect(!f.hasActiveAnimations && !f.wantsAnotherFrame)
    }
    #expect(h.store.vectorTrackRebuilds == settled, "a settled component does no track work")
}

// MARK: - A non-animatable component allocates what it did

private struct SteadyPlain: Component {
    var x: Double
    var content: some ElementGroup {
        Box().frame(width: Pixels(Float(100 + x)), height: Pixels(20)).background(.accent)
    }
}

private struct SteadyEquatable: Component, @MainActor Equatable {
    var x: Double
    static func == (l: SteadyEquatable, r: SteadyEquatable) -> Bool { l.x == r.x }
    var content: some ElementGroup {
        Box().frame(width: Pixels(Float(100 + x)), height: Pixels(20)).background(.accent)
    }
}

/// **A steady frame of non-animatable components allocates exactly what it did before PR E** (a bare component and
/// an `.equatable()` one, measured 398 on PR D's head `7c684807` and 398 here, the machine this record ran on): the
/// hook computes no id for a component that is not `Animatable`. A first version computed the id in
/// `EquatableComponent` before calling the hook and read 399 (one `GlobalElementID` allocation per equatable
/// component per frame): mutation **ME7**.
@Test(.enabled(if: !acVerifying && ProcessInfo.processInfo.environment["METALUI_VERIFY_LAYOUT_MEMO"] != "1",
               "METALUI_VERIFY_RETAINED=1 and METALUI_VERIFY_LAYOUT_MEMO=1 recompute every hit: the allocation count is not theirs to read (1085)"))
@MainActor func aNonAnimatableComponentAllocatesWhatItDid() throws {
    let h = WrapperHarness()
    func tree() -> some Element {
        DifferentialRoot(width: 400, height: 100) { SteadyPlain(x: 5); SteadyEquatable(x: 5).equatable() }
    }
    for i in 0..<4 { h.frame(Double(i), nil, tree()) }
    #if canImport(Darwin)
    let allocations = try #require(countAllocations { h.frame(10, nil, tree()) })
    #expect(allocations == 398, "a steady frame of a bare and an equatable non-animatable component: \(allocations)")
    #endif
    #expect(h.store.vectorTrackRebuilds == 0 && h.store.count == 0, "and no track: \(h.store.vectorTrackRebuilds) \(h.store.count)")
}
