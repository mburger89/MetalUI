import Foundation
import Observation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUITesting
@testable import MetalUI

// R4-3 PR D (`VA-`; record 208): a public `Animatable` on shapes. SwiftUI's side is probe
// `docs/probes/swiftui-animatable.swift` (`VA1`-`VA8`, `VT1`-`VT16`). Each fixture notes the data it was
// painted at into `seen` (it runs in PAINT, `AN-AA`); a test reads the last note of a frame.
//
// **No test sleeps**: headless frames at chosen timestamps (`TransitionHarness`) or a `TestWindow` driven by
// `advance(by:)`.

private let linear1 = Animation.linear(duration: 1)
private let linear06 = Animation.linear(duration: 0.6)

@MainActor private var seen: [String: [Double]] = [:]

@MainActor private func note(_ key: String, _ values: Double...) { seen[key, default: []].append(contentsOf: values) }

/// The last `count` numbers noted under `key` (one painted call's worth), after clearing between frames.
@MainActor private func last(_ key: String, _ count: Int = 1) -> [Double] { Array((seen[key] ?? []).suffix(count)) }

@MainActor private func clearSeen() { seen = [:] }

private func rect(_ width: Double, _ height: Double = 10) -> ShapeGeometry {
    .roundedRectangle(Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                             size: Size(width: Pixels(Float(width)), height: Pixels(Float(height)))),
                      cornerRadii: Corners(all: Pixels(0)))
}

/// A custom shape with one `Double` of data, drawn as a rect that many points wide (`VA1`).
private struct Bar: Shape {
    var t: Double
    nonisolated var animatableData: Double {
        get { t }
        set { t = newValue }
    }
    func geometry(in bounds: Bounds<Pixels>) -> ShapeGeometry {
        note("bar", t)
        return rect(t)
    }
}

/// The same shape declaring no data (`VA2`).
private struct BarNoData: Shape {
    var t: Double
    func geometry(in bounds: Bounds<Pixels>) -> ShapeGeometry {
        note("nodata", t)
        return rect(t)
    }
}

/// A pair of numbers: `a` is the width, `b` the height (`VA4`).
private struct PairBar: Shape {
    var a: Double
    var b: Double
    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(a, b) }
        set { a = newValue.first; b = newValue.second }
    }
    func geometry(in bounds: Bounds<Pixels>) -> ShapeGeometry {
        note("pair", a, b)
        return rect(a * 100, b * 100)
    }
}

/// A wrapper around any shape that forwards its data and notes `read(inner)` when it paints (`VA3d`, `VA3e`).
private struct Holder<S: Shape>: Shape {
    var inner: S
    let key: String
    let read: @MainActor @Sendable (S) -> [Double]
    nonisolated var animatableData: S.AnimatableData {
        get { inner.animatableData }
        set { inner.animatableData = newValue }
    }
    func path(in bounds: Bounds<Pixels>) -> Path {
        seen[key, default: []].append(contentsOf: read(inner))
        return inner.path(in: bounds)
    }
}

/// A wrapper around a trim that declares nothing (`VA3b`).
private struct HolderNoData: Shape {
    var inner: TrimmedShape<Bar>
    func path(in bounds: Bounds<Pixels>) -> Path {
        note("holder0", inner.endFraction)
        return inner.path(in: bounds)
    }
}

@MainActor private func barTree(_ t: Double) -> some Element {
    Bar(t: t).frame(width: Pixels(100), height: Pixels(10))
}

@MainActor private func widthOf(_ frame: Frame) -> Double? {
    frame.scene.rects.first.map { Double($0.bounds.size.width) }
}

// MARK: - The protocol and the shapes (VA1, VA2)

/// **A custom shape's `animatableData` animates under a transaction** (`VA1`): `t` 0 to 100 under a one-second
/// linear animation is painted at 50 half-way and at 100 once settled; the first sighting and a change with no
/// transaction snap (`VA1c`). Mutations **MD2** (the interpolated data is not written back) and **MD3**
/// (the "animates nothing" guard inverted).
@Test @MainActor func aCustomShapeAnimatesItsData() {
    clearSeen()
    let h = TransitionHarness()
    h.frame(0, nil, barTree(0))
    #expect(last("bar") == [0], "first sighting: the declared value")
    h.frame(0, linear1, barTree(100))
    let mid = h.frame(0.5, nil, barTree(100))
    #expect(abs((last("bar").first ?? -1) - 50) < 0.01, "half-way: \(last("bar"))")
    #expect(abs((widthOf(mid) ?? -1) - 50) < 0.01, "and drawn there: \(String(describing: widthOf(mid)))")
    h.frame(1.5, nil, barTree(100))
    #expect(last("bar") == [100], "settled at the declared value")
    let snap = TransitionHarness()
    snap.frame(0, nil, barTree(0))
    snap.frame(0.5, nil, barTree(100))
    #expect(last("bar") == [100], "VA1c: no transaction snaps")
}

/// **A shape with no data snaps** (`VA2`): `BarNoData` under the same transaction is painted at its final value
/// at once, and writes no track.
@Test @MainActor func aShapeWithNoDataSnaps() {
    clearSeen()
    let h = TransitionHarness()
    h.frame(0, nil, BarNoData(t: 0).frame(width: Pixels(100), height: Pixels(10)))
    let before = h.store.vectorTrackRebuilds
    h.frame(0, linear1, BarNoData(t: 100).frame(width: Pixels(100), height: Pixels(10)))
    h.frame(0.5, nil, BarNoData(t: 100).frame(width: Pixels(100), height: Pixels(10)))
    #expect(last("nodata") == [100], "snapped: \(last("nodata"))")
    #expect(h.store.vectorTrackRebuilds == before, "no track")
}

// MARK: - Trim (VA3)

/// **A trim's data is the base's, then the two fractions scaled by 128** (`VA3a`, `VA3a2`): an end fraction
/// 0 to 1 is a delta of 128, a start fraction 0 to 0.5 is 64, and setting the data divides back. Mutation
/// **MD4** (no scale).
@Test @MainActor func aTrimsDataIsScaledBy128() {
    var trim = Bar(t: 7).trim(from: 0.5, to: 1)
    let data = trim.animatableData
    #expect(data.first == 7 && data.second.first == 64 && data.second.second == 128,
            "\(data.first) \(data.second.first) \(data.second.second)")
    trim.animatableData = AnimatablePair(3, AnimatablePair(0, 64))
    #expect(trim.shape.t == 3 && trim.startFraction == 0 && trim.endFraction == 0.5,
            "\(trim.shape.t) \(trim.startFraction) \(trim.endFraction)")
    let delta = Bar(t: 0).trim(from: 0, to: 1).animatableData - Bar(t: 0).trim(from: 0, to: 0).animatableData
    #expect(delta.second.second == 128 && delta.second.first == 0, "VA3a: end 0 to 1 is 128")
}

/// **A wrapper forwarding a trim's own data animates the trim and its base** (`VA3d`); one declaring nothing
/// snaps (`VA3b`).
@Test @MainActor func aWrapperForwardingATrimAnimatesBoth() {
    clearSeen()
    func tree(_ t: Double, _ to: Double) -> some Element {
        Holder(inner: Bar(t: t).trim(from: 0, to: to), key: "holder",
               read: { [$0.shape.t, $0.endFraction] })
            .frame(width: Pixels(100), height: Pixels(10))
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(0, 0))
    h.frame(0, linear1, tree(1, 1))
    h.frame(0.5, nil, tree(1, 1))
    let mid = last("holder", 2)
    #expect(abs(mid[0] - 0.5) < 0.01 && abs(mid[1] - 0.5) < 0.01, "both at half-way: \(mid)")
}

@Test @MainActor func aWrapperDeclaringNothingSnaps() {
    clearSeen()
    func tree(_ to: Double) -> some Element {
        HolderNoData(inner: Bar(t: 1).trim(from: 0, to: to)).frame(width: Pixels(100), height: Pixels(10))
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(0))
    h.frame(0, linear1, tree(1))
    h.frame(0.5, nil, tree(1))
    #expect(last("holder0") == [1], "VA3b: \(last("holder0"))")
}

/// **A trim of a trim animates both layers** (`VA3e`): the nested data is the inner's data, then the outer
/// fractions. Two layers, so a mutation dropping the inner layer's data from the outer's shows. Mutation
/// **MD5** (the inner dropped).
@Test @MainActor func aTrimOfATrimAnimatesBothLayers() {
    clearSeen()
    typealias Nested = TrimmedShape<TrimmedShape<Bar>>
    func tree(_ t: Double, _ inner: Double, _ outer: Double) -> some Element {
        Holder<Nested>(inner: Bar(t: t).trim(from: 0, to: inner).trim(from: 0, to: outer), key: "nested",
                       read: { [$0.shape.shape.t, $0.shape.endFraction, $0.endFraction] })
            .frame(width: Pixels(100), height: Pixels(10))
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(0, 0, 0))
    h.frame(0, linear1, tree(1, 1, 1))
    h.frame(0.5, nil, tree(1, 1, 1))
    let mid = last("nested", 3)
    #expect(mid.allSatisfy { abs($0 - 0.5) < 0.01 }, "base, inner and outer all at half-way: \(mid)")
}

// MARK: - Retarget (VA4, VA6)

/// **A retarget on one component of a pair re-bases the whole pair** (`VA4`): `(a, b)` goes (0, 0) to (1, 1) over
/// 0.6 s; at 0.3 s (a 0.5, b 0.5) `a` is retargeted to 0 with `b` unchanged. The new flight runs from the current
/// pair to (0, 1), so 0.3 s later `a` is 0.25 and **`b` is 0.75, on the new curve** (the old curve had it at 1).
/// Mutation **MD6** (per component: `b` keeps its old flight).
@Test @MainActor func aRetargetOnOneComponentRebasesTheWholePair() {
    clearSeen()
    func tree(_ a: Double, _ b: Double) -> some Element {
        PairBar(a: a, b: b).frame(width: Pixels(100), height: Pixels(100))
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(0, 0))
    h.frame(0, linear06, tree(1, 1))
    h.frame(0.3, nil, tree(1, 1))
    #expect(last("pair", 2).allSatisfy { abs($0 - 0.5) < 0.01 }, "set up: half-way \(last("pair", 2))")
    h.frame(0.3, linear06, tree(0, 1))
    let at = last("pair", 2)
    #expect(at.allSatisfy { abs($0 - 0.5) < 0.01 }, "the retarget frame is where the value was: \(at)")
    h.frame(0.6, nil, tree(0, 1))
    let later = last("pair", 2)
    #expect(abs(later[0] - 0.25) < 0.01 && abs(later[1] - 0.75) < 0.01, "a 0.25, b 0.75: \(later)")
}

/// **A retarget is position-continuous and restarts at rest** (`VA6`, divergence 216): 0 to 100, 0.3 s later back
/// to 0, the retarget frame paints the value the frame before did (`VA6`: last x 49.9, first after 49.9) and the
/// next frames move from there. Mutation **MD7** (the new flight starts from the old `from`).
@Test @MainActor func aRetargetIsPositionContinuousFromRest() {
    clearSeen()
    let h = TransitionHarness()
    h.frame(0, nil, barTree(0))
    h.frame(0, linear1, barTree(100))
    h.frame(0.4, nil, barTree(100))
    let before = last("bar").first ?? -1
    h.frame(0.4, linear1, barTree(0))
    let at = last("bar").first ?? -1
    #expect(abs(at - before) < 0.01 && abs(before - 40) < 0.01, "continuous: \(before) then \(at)")
    h.frame(0.9, nil, barTree(0))
    #expect(abs((last("bar").first ?? -1) - 20) < 0.01, "half-way back from 40: \(last("bar"))")
}

/// **A large delta lands within the spring's absolute ceiling** (the `Animation.value` threshold is
/// `min(0.001 * scale, 0.1667)` of the motion): a 2000-point spring is not declared finished 2 points short,
/// as unit progress `0 to 1` would. The last in-flight frame is within half a point of 2000. Mutation
/// **MD8** (the curve runs over unit progress).
@Test @MainActor func aLargeDeltaLandsWithinTheCeiling() {
    clearSeen()
    let h = TransitionHarness()
    let spring = Animation.spring(duration: 0.5, bounce: 0)
    func tree(_ t: Double) -> some Element { Bar(t: t).frame(width: Pixels(100), height: Pixels(10)) }
    h.frame(0, nil, tree(0))
    h.frame(0, spring, tree(2000))
    var lastInFlight = -1.0
    var settled = false
    for i in 1...600 {
        let f = h.frame(Double(i) / 120, nil, tree(2000))
        let t = last("bar").first ?? -1
        if f.hasActiveAnimations { lastInFlight = t } else { settled = true; break }
    }
    #expect(settled, "it settles")
    #expect(abs(2000 - lastInFlight) < 0.5, "the last in-flight frame: \(lastInFlight)")
}

// MARK: - The settled path (VA-D)

/// **A settled shape does no store work**: after the animation lands, a frame whose declared data equals the
/// baseline returns before any track is rebuilt (`vectorTrackRebuilds` stays put). Mutation **MD9** (the slow
/// path always).
@Test @MainActor func aSettledShapeDoesNoStoreWork() {
    clearSeen()
    let h = TransitionHarness()
    h.frame(0, nil, barTree(0))
    h.frame(0, linear1, barTree(100))
    h.frame(0.5, nil, barTree(100))
    #expect(h.store.vectorTrackRebuilds > 0, "set up: the flight rebuilt tracks")
    h.frame(1.5, nil, barTree(100))
    let settled = h.store.vectorTrackRebuilds
    for i in 0..<5 { h.frame(2 + Double(i), nil, barTree(100)) }
    #expect(h.store.vectorTrackRebuilds == settled, "\(h.store.vectorTrackRebuilds) vs \(settled)")
    let plain = TransitionHarness()
    for i in 0..<5 { plain.frame(Double(i), linear1, Rectangle().frame(width: Pixels(100), height: Pixels(10))) }
    #expect(plain.store.vectorTrackRebuilds == 0, "a plain shape touches no track")
}

// MARK: - Retained occurrences

@Observable @MainActor final class AVModel {
    var t = 0.0
}

private struct AVPanel: Component, @MainActor Equatable {
    let t: Double
    static func == (l: AVPanel, r: AVPanel) -> Bool { l.t == r.t }
    var content: some ElementGroup {
        Bar(t: t).frame(width: Pixels(100), height: Pixels(10))
    }
}

private struct AVRoot: Component {
    let model: AVModel
    var content: some ElementGroup {
        VStack(spacing: 2) {
            AVPanel(t: model.t).equatable()
        }
    }
}

private var avVerifying: Bool { ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] == "1" }

@MainActor private func avScript(retained: Bool) throws -> [Double] {
    let model = AVModel()
    let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(200))) { VStack(spacing: 0) { AVRoot(model: model) } }
    w.window.testingRetainedSubtrees = retained
    for _ in 0..<6 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    withAnimation(.linear(duration: 1)) { model.t = 100 }
    var widths: [Double] = []
    for _ in 0..<6 {
        w.advance(by: 0.1)
        widths.append(w.scene.rects.first.map { Double($0.bounds.size.width) } ?? -1)
    }
    return widths
}

/// **An animatable shape inside a retained occurrence is not replayed frozen**: the interpolation taints the
/// occurrence's record, so each frame of the flight paints a new width, equal to the oracle's (retention off).
/// Mutation **MD10** (no `noteInterpolation` and no `noteActiveAnimation`: the first in-flight paint is
/// replayed).
@Test(.enabled(if: !avVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss"))
@MainActor func anAnimatableShapeInARetainedOccurrenceIsNotFrozen() throws {
    let on = try avScript(retained: true)
    let off = try avScript(retained: false)
    #expect(on == off, "equal to the oracle: \(on) vs \(off)")
    for pair in zip(on, on.dropFirst()).prefix(4) {
        #expect(pair.1 > pair.0, "it moves every frame: \(on)")
    }
}

// MARK: - Arithmetic

/// **`AnimatablePair` and `EmptyAnimatableData` are componentwise.** Mutations **MD11** (`scale` skips
/// `second`) and **MD12** (`magnitudeSquared` drops `first`).
@Test func pairArithmeticIsComponentwise() {
    typealias P = AnimatablePair<Double, Double>
    var p = P(3, 4)
    #expect(p.magnitudeSquared == 25)
    p.scale(by: 2)
    #expect(p.first == 6 && p.second == 8, "\(p.first) \(p.second)")
    #expect((p + P(1, 1)) == P(7, 9) && (p - P(1, 1)) == P(5, 7))
    #expect(P.zero == P(0, 0))
    #expect(p.scaled(by: 0.5) == P(3, 4))
    let nested = AnimatablePair(P(1, 2), 3.0)
    #expect(nested.magnitudeSquared == 14)
    #expect(EmptyAnimatableData().magnitudeSquared == 0)
    #expect(EmptyAnimatableData.zero == EmptyAnimatableData())
}
