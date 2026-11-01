import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Observation
import Testing

// R3-4 (`SP-`, record 177): `scrollPosition(id:anchor:)` with `scrollTargetLayout()`, an animated `scrollTo`,
// and `@Bindable`, through a real `Window` over the harness. Rows are 20 points tall in a 200 x 200 window
// (10 on screen). Counts and frames, never time: the clock is `advance(by:)`.
//
// The binding here is a `Binding(get:set:)` over a box so the test can count the writes: the registry's
// writes are the only ones (`SP-C`), and an external write needs a redraw (a `@State` write dirties itself).

@MainActor private final class IDBox {
    var id: Int?
    var writes = 0
    init(_ id: Int? = nil) { self.id = id }
    var binding: Binding<Int?> { Binding(get: { self.id }, set: { self.id = $0; self.writes += 1 }) }
}

@MainActor private func settle(_ window: TestWindow, frames: Int = 4) {
    for _ in 0..<frames { window.tick() }
}

/// An external write: the app sets the binding and the window redraws (a `@State` source does both at once).
@MainActor private func write(_ box: IDBox, _ id: Int?, in window: TestWindow) {
    box.id = id
    window.window.setNeedsRedraw()
    settle(window)
}

@MainActor private func lazyRows(_ box: IDBox, anchor: UnitPoint? = nil, targets: Bool = true,
                                 count: Int = 1000) throws -> TestWindow {
    let binding = box.binding
    if targets {
        return try harnessWindow(size: sz(200, 200)) {
            ProposalScrollView {
                LazyVStack(spacing: Pixels(0)) {
                    ForEach(0..<count) { index in ProposalText("row \(index)").frame(height: Pixels(20)) }
                }.scrollTargetLayout()
            }.scrollPosition(id: binding, anchor: anchor)
        }
    }
    return try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<count) { index in ProposalText("row \(index)").frame(height: Pixels(20)) }
            }
        }.scrollPosition(id: binding, anchor: anchor)
    }
}

/// The top of a row's text element: the text is centred in its 20-point row.
private func rowTop(_ element: TestElement) -> Float {
    element.frame.origin.y.value - (20 - element.frame.size.height.value) / 2
}

/// The row whose top is nearest the window's top among the rows the tree holds, and where that top is.
@MainActor private func topRow(_ window: TestWindow) throws -> (index: Int, y: Float) {
    let rows = try window.elements(role: .staticText).compactMap { element -> (Int, Float)? in
        guard let label = element.label ?? element.value, label.hasPrefix("row "), let index = Int(label.dropFirst(4)) else { return nil }
        let y = rowTop(element)
        return y > -19 && y < 200 ? (index, y) : nil
    }
    let top = try #require(rows.min { $0.0 < $1.0 })
    return (top.0, top.1)
}

/// **SP-A / SP-C.** A wheel to offset 300 writes row 15 (the first target reaching the leading edge: row 14
/// ends at 300); 310 and 330 write 15 and 16 (a partly visible row still leads). Exactly one write per change,
/// from the wheel: the settling frames after it write nothing.
/// Mutation: the topmost rule `end > reference` -> `start > reference` (310 writes 16).
@Test @MainActor func aWheelWritesTheTopmostVisibleTargetAndSettlingFramesWriteNothing() throws {
    let box = IDBox()
    let window = try lazyRows(box)
    settle(window)
    #expect(box.id == nil && box.writes == 0)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -300)
    #expect(box.id == 15, "wheel to 300: \(String(describing: box.id))")
    let afterWheel = box.writes
    settle(window)
    #expect(box.writes == afterWheel, "frames after the wheel wrote \(box.writes - afterWheel) more")
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -10)
    #expect(box.id == 15, "wheel to 310: \(String(describing: box.id))")
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -20)
    #expect(box.id == 16, "wheel to 330: \(String(describing: box.id))")
    settle(window)
}

/// **SP-C.** No frame writes the binding unless input moved the scroller: 20 idle ticks and a redraw leave the
/// write count at 0 (the write is from input, never from a phase).
/// Mutation: `beginLayout` writes the topmost id (`report` called from `update`).
@Test @MainActor func idleFramesNeverWriteThePositionBinding() throws {
    let box = IDBox()
    let window = try lazyRows(box)
    for _ in 0..<20 { window.advance(by: 0.1) }
    window.window.setNeedsRedraw(); settle(window)
    #expect(box.writes == 0 && box.id == nil)
}

/// **SP-B.** Without `scrollTargetLayout()` nothing is a target: the wheel moves the list and the binding
/// stays nil. Mutation: `notesScrollTargets` -> `positionTrackingDepth > 0` (the control writes 15).
@Test @MainActor func withoutScrollTargetLayoutNothingIsATargetAndTheBindingStaysNil() throws {
    let box = IDBox()
    let window = try lazyRows(box, targets: false)
    settle(window)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -300)
    settle(window)
    #expect(box.id == nil && box.writes == 0)
    #expect(try topRow(window).index >= 14, "the list did scroll")
}

/// **SP-A.** Writing the binding scrolls: id 50 puts row 50's top at the viewport's top (no anchor means the
/// leading edge); 80 with the `.bottom` anchor puts row 80's bottom at the viewport's bottom. The scroll does
/// not write the binding back (its value is the one written), and a second identical frame does not scroll again.
/// Mutation: `injectScrollRequest` not called (nothing scrolls).
@Test @MainActor func writingTheBindingScrollsToTheTarget() throws {
    let box = IDBox()
    let window = try lazyRows(box)
    settle(window)
    write(box, 50, in: window)
    let row = try window.element(label: "row 50")
    #expect(abs(rowTop(row)) < 0.5, "row 50 at \(row.frame)")
    #expect(box.writes == 0, "a write the app made is not written back")
    settle(window)
    #expect(abs(rowTop(try window.element(label: "row 50"))) < 0.5)
}

@Test @MainActor func writingTheBindingWithABottomAnchorAlignsTheTargetsBottomEdge() throws {
    let box = IDBox()
    let window = try lazyRows(box, anchor: .bottom)
    settle(window)
    write(box, 80, in: window)
    let row = try window.element(label: "row 80")
    #expect(abs(rowTop(row) + 20 - 200) < 0.5, "row 80 at \(row.frame)")
}

/// **SP-A.** An initial non-nil value scrolls on the first frames. Mutation: `known == nil` branch removed.
@Test @MainActor func anInitialValueScrollsOnTheFirstFrames() throws {
    let box = IDBox(30)
    let window = try lazyRows(box)
    settle(window, frames: 6)
    #expect(abs(rowTop(try window.element(label: "row 30"))) < 0.5)
}

/// **SP-C.** A wheel far past the realised window (2000 points, rows 100 ... 112 are realised after it) is
/// reported once the frame that realised them is over, still not from a phase: the binding reads 100.
/// Mutation: `needsReport` never set (the binding stays nil).
@Test @MainActor func aWheelPastTheRealizedWindowIsReportedAfterTheFrameThatRealizesIt() throws {
    let box = IDBox()
    let window = try lazyRows(box)
    settle(window)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -2000)
    settle(window)
    #expect(box.id == 100, "after the wheel: \(String(describing: box.id))")
    #expect(box.writes == 1)
}

/// **SP-A.** The trailing anchor reads the target holding the viewport's far edge: at offset 300 the rows in
/// view are 15 ... 24, and `.bottom` reports 24. Mutation: `fraction >= 1` branch uses `first` (reports 15).
@Test @MainActor func aBottomAnchorReportsTheTargetAtTheTrailingEdge() throws {
    let box = IDBox()
    let window = try lazyRows(box, anchor: .bottom)
    settle(window)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -300)
    #expect(box.id == 24, "\(String(describing: box.id))")
}

/// **SP-B.** An eager `VStack` of `ForEach` elements is tracked as well (all 40 are built): offset 300 -> 15.
/// Mutation: the `ForEach` prepaint's `noteScrollTarget` removed.
@Test @MainActor func anEagerStacksForEachElementsAreTargetsToo() throws {
    let box = IDBox()
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            VStack(spacing: Pixels(0)) {
                ForEach(0..<40) { index in ProposalText("row \(index)").frame(height: Pixels(20)) }
            }.scrollTargetLayout()
        }.scrollPosition(id: box.binding)
    }
    settle(window)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -300)
    #expect(box.id == 15, "\(String(describing: box.id))")
    write(box, 3, in: window)
    #expect(abs(rowTop(try window.element(label: "row 3"))) < 0.5)
}

/// **SP-A.** The horizontal axis: 40-wide columns in a 200-wide scroller, a wheel of 300 reads column 7 (offset
/// 300 is inside 280 ... 320). Mutation: the note's `vertical` ignores the scroller's axis.
@Test @MainActor func aHorizontalScrollerReportsAlongItsAxis() throws {
    let box = IDBox()
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView(.horizontal) {
            LazyHStack(spacing: Pixels(0)) {
                ForEach(0..<500) { index in ProposalText("col \(index)").frame(width: Pixels(40)) }
            }.scrollTargetLayout()
        }.scrollPosition(id: box.binding)
    }
    settle(window)
    window.scroll(at: pt(100, 100), byDeltaX: -300, deltaY: 0)
    #expect(box.id == 7, "\(String(describing: box.id))")
}

@MainActor private final class ProxyHolder {
    var proxy: ScrollViewProxy?
    func keep(_ proxy: ScrollViewProxy) -> Bool { self.proxy = proxy; return true }
}

/// **SP-F.** `withAnimation(.linear(duration: 1)) { proxy.scrollTo(100, anchor: .top) }` over a lazy stack (a layout that
/// read a stale offset would realise the wrong window) glides: after a
/// quarter, a half and three quarters of the second the offset is a quarter, a half and three quarters of 2000
/// (to the nearest row), and it lands exactly. The display link stays awake (`noteActiveAnimation`) until it
/// lands. The control, the same call outside `withAnimation`, jumps at once.
/// Mutation: `scrollTo` reads no pending transaction (the animated arm jumps).
@Test @MainActor func scrollToUnderWithAnimationGlidesAndTheControlJumps() throws {
    func run(animated: Bool) throws -> (samples: [Int], active: [Bool]) {
        let holder = ProxyHolder()
        let window = try harnessWindow(size: sz(200, 200)) {
            VStack(spacing: Pixels(0)) {
                ScrollViewReader { proxy in
                    let _ = holder.keep(proxy)
                    ProposalScrollView {
                        LazyVStack(spacing: Pixels(0)) {
                            ForEach(0..<200) { index in ProposalText("row \(index)").frame(height: Pixels(20)) }
                        }
                    }
                }
            }
        }
        settle(window)
        if animated { withAnimation(.linear(duration: 1)) { holder.proxy?.scrollTo(100, anchor: .top) } }
        else { holder.proxy?.scrollTo(100, anchor: .top) }
        window.tick()                          // the frame that resolves the request
        var samples: [Int] = [], active: [Bool] = []
        for _ in 0..<4 {
            window.advance(by: 0.25)
            let top = try topRow(window)
            samples.append(top.index * 20 - Int(top.y))
            active.append(window.platformWindow.displayLinkPauses.last == false)
        }
        window.advance(by: 0.5)
        return (samples, active)
    }
    let animated = try run(animated: true)
    #expect(animated.samples.count == 4)
    for (sample, expected) in zip(animated.samples, [500, 1000, 1500, 2000]) {
        #expect(abs(sample - expected) <= 40, "animated samples \(animated.samples)")
    }
    #expect(animated.active.prefix(3).allSatisfy { $0 }, "the link idled mid-glide: \(animated.active)")
    let jumped = try run(animated: false)
    #expect(jumped.samples.allSatisfy { $0 == 2000 }, "control \(jumped.samples)")
}

/// **SP-F.** A wheel during a glide ends it where it stands: the offset after the wheel is the glide's last
/// offset plus the wheel, and later frames do not resume. Mutation: `Window.scroll` keeps the glide.
@Test @MainActor func aWheelEndsAnAnimatedScrollWhereItStands() throws {
    let holder = ProxyHolder()
    let window = try harnessWindow(size: sz(200, 200)) {
        VStack(spacing: Pixels(0)) {
            ScrollViewReader { proxy in
                let _ = holder.keep(proxy)
                ProposalScrollView {
                    VStack(spacing: Pixels(0)) {
                        ForEach(0..<200) { index in ProposalText("row \(index)").frame(height: Pixels(20)) }
                    }
                }
            }
        }
    }
    settle(window)
    withAnimation(.linear(duration: 1)) { holder.proxy?.scrollTo(100, anchor: .top) }
    window.tick()
    window.advance(by: 0.5)
    let mid = try topRow(window)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: 0)   // a wheel event of no distance still ends the glide
    window.advance(by: 0.25)
    window.advance(by: 0.5)
    let after = try topRow(window)
    #expect(after.index * 20 - Int(after.y) == mid.index * 20 - Int(mid.y), "mid \(mid) after \(after)")
}

// MARK: @Bindable

private final class FireCount: @unchecked Sendable { var count = 0 }

@Observable @MainActor final class BindableModel {
    var name = "a"
    var count = 1
}

/// **SP-D.** `$model.property` is a binding to the property: it reads and writes through, and the write is
/// observed by a tracking block that read the same property. Mutation: the subscript's getter returns a copy
/// taken at creation (the first expectation fails).
@Test @MainActor func aBindableProjectsBindingsThatReadAndWriteThroughTheObject() {
    let model = BindableModel()
    let bindable = Bindable(model)
    let name = bindable.name
    #expect(name.wrappedValue == "a")
    model.name = "b"
    #expect(name.wrappedValue == "b", "the binding reads the object's current value")
    let fired = FireCount()
    withObservationTracking { _ = name.wrappedValue } onChange: { fired.count += 1 }
    name.wrappedValue = "c"
    #expect(model.name == "c" && fired.count == 1, "wrote \(model.name), observers fired \(fired.count)")
    let count = bindable.count
    count.wrappedValue += 4
    #expect(model.count == 5)
}

private struct BindableEditor: Component {
    @Bindable var model: BindableModel
    var content: some ElementGroup {
        Text("n=\(model.count)").onClick { $model.count.wrappedValue += 1 }
    }
}

/// **SP-D.** In a window: a click writes through `$model.count` and the next frame shows it, with no
/// `@State` anywhere (the frame build is observed). Mutation: the setter writes a copy (the label stays n=1).
@Test @MainActor func aBindableBindingWrittenFromInputRedrawsTheObservingFrame() throws {
    let model = BindableModel()
    let window = try harnessWindow(size: sz(200, 200)) { VStack { BindableEditor(model: model) } }
    settle(window)
    _ = try window.element(label: "n=1")
    window.click(at: pt(100, 100))
    settle(window)
    #expect(model.count == 2, "count \(model.count)")
    _ = try window.element(label: "n=2")
}

private struct EqRow: Component, @MainActor Equatable {
    let index: Int
    var content: some ElementGroup {
        Text("row \(index)").frame(width: Pixels(100), height: Pixels(20))
    }
    static func == (l: EqRow, r: EqRow) -> Bool { l.index == r.index }
}

/// **SP-B, retained.** `.equatable()` rows (retained, replayed paint and prepaint; legacy `ForEach` units) are
/// targets like any other: the wheel reads 15 at offset 300 and a write of 50 scrolls to row 50. Under
/// `METALUI_VERIFY_RETAINED=1` every replay is built twice and compared (the suite's own run).
/// Mutation: the lazy stack notes targets only for `LazyForEachSource` units (this test reads nil).
@Test @MainActor func equatableRowsAreScrollTargetsAndTheReplayAgrees() throws {
    let box = IDBox()
    let binding = box.binding
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<1000) { EqRow(index: $0).equatable() }
            }.scrollTargetLayout()
        }.scrollPosition(id: binding)
    }
    settle(window)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -300)
    settle(window)
    #expect(box.id == 15, "\(String(describing: box.id))")
    write(box, 50, in: window)
    #expect(abs(rowTop(try window.element(label: "row 50"))) < 0.5)
}

/// **SP-B, divergence 916.** A static child is not a scroll target: with a 20-point static header over the rows, a
/// wheel of 10 leaves the header covering the top and the binding reads the first `ForEach` element, "r0", not
/// the header. Mutation: the lazy stack notes `LazyStaticUnitID` units as targets (the key is not a `String`, so
/// the binding stays nil or reads the static unit).
@Test @MainActor func aStaticChildOfAScrollTargetLayoutIsNotATarget() throws {
    final class StringBox { var id: String?; init() {} }
    let box = StringBox()
    let binding = Binding<String?>(get: { box.id }, set: { box.id = $0 })
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ProposalText("static").frame(height: Pixels(20))
                ForEach((0..<200).map { "r\($0)" }, id: \.self) { name in ProposalText(name).frame(height: Pixels(20)) }
            }.scrollTargetLayout()
        }.scrollPosition(id: binding)
    }
    settle(window)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -10)
    settle(window)   // the prelude above the first target is covered by the frame built around the offset
    #expect(box.id == "r0", "\(String(describing: box.id))")
}

/// **SP-F, SP-C.** A binding write under `withAnimation` glides, and the binding is reported where the glide lands,
/// not on the way: `box.id = 100` inside `withAnimation(.linear(duration: 1))` leaves row 100 at the top after the
/// second, the offset half-way at half a second, and the position scroller writes nothing while it moves.
/// Mutation: the injected request carries no animation (the half-way sample is already 2000).
@Test @MainActor func aBindingWrittenUnderWithAnimationGlidesAndReportsAtTheLanding() throws {
    let box = IDBox()
    let window = try lazyRows(box)
    settle(window)
    // A `@State` source dirties the window inside the body, which is what parks the transaction for the next build.
    withAnimation(.linear(duration: 1)) { box.id = 100; window.window.setNeedsRedraw() }
    window.tick()
    window.advance(by: 0.5)
    let half = try topRow(window)
    #expect(abs(half.index * 20 - Int(half.y) - 1000) <= 60, "half-way: \(half)")
    #expect(box.writes == 0, "nothing is written on the way")
    window.advance(by: 0.75)
    window.advance(by: 0.25)
    #expect(abs(rowTop(try window.element(label: "row 100"))) < 0.5)
    #expect(box.id == 100)
}
