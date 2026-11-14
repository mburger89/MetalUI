import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import MetalUITestSupport
import Observation
import Testing

// Why a key was not drawn at once, and what dirtied the window (ruling `FP-Q`, record 293): the `why=` and `dirty=`
// trailing fields of the latency trace and the `METALUI_LATENCY_TRACE_ALL` lines for frames no input caused. Each
// test reads the trace lines the headless renderer's presentation reports produce; none sleeps.

@MainActor private final class WhyModel { var text = "" }
@MainActor private final class WhyClock { var now: UInt64 = 1_000_000_000 }
@Observable @MainActor private final class WhyObserved { var label = 0 }

@MainActor private final class WhyRig {
    let window: TestWindow
    let timing = FrameTiming()
    let clock = WhyClock()
    var lines: [String] = []
    let model = WhyModel()

    convenience init() throws { try self.init(extra: { Box().frame(width: Pixels(1), height: Pixels(1)) }) }

    init<E: ElementGroup>(extra: @escaping @MainActor () -> E) throws {
        let model = model
        window = try harnessWindow {
            VStack(spacing: 0) {
                TextField("", text: model.text) { model.text = $0 }.frame(width: Pixels(200), height: Pixels(24))
                extra()
            }
        }
        window.window.frameTiming = timing
        window.platformWindow.headlessRenderer.reportsPresentation = true
        window.window.immediateInputClock = { [clock] in clock.now }
        window.window.drawsImmediatelyOnInput = true
        window.typeKey(.tab)
        window.tick()
        settle()
        timing.traceSink = { [unowned self] in lines.append($0) }
        lines.removeAll()
    }

    func settle() { window.platformWindow.headlessRenderer.deliverPresentations(at: FrameTiming.now() + 1_000_000) }
    func advance(_ intervals: Double) { clock.now += UInt64(intervals * Double(ImmediateInput.fallbackInterval)) }
    func type(_ c: String) { window.send(.textInput(c)) }
    func release(_ c: String) { window.send(.keyUp(KeyEvent(charactersIgnoringModifiers: c, characters: c, timestamp: 0))) }
    /// The trace lines of input frames of kind `text`.
    var textLines: [String] { lines.filter { $0.contains(" text ") } }
}

/// 1.1 — an immediate key carries no `why=`; a key inside the pacing interval carries `pacing(<ms>ms)` with the time
/// since the last commit. Mutations: `why` always written; the pacing reason formatted without the milliseconds.
@Test @MainActor func aPacedKeyNamesPacingAndTheTimeSinceTheLastCommit() throws {
    let rig = try WhyRig()
    rig.advance(2); rig.type("a"); rig.release("a"); rig.window.tick(); rig.settle()
    rig.advance(0.5); rig.type("b"); rig.release("b"); rig.window.tick(); rig.settle()
    let lines = rig.textLines
    #expect(lines.count == 2)
    #expect(!lines[0].contains("why="), "\(lines[0])")
    #expect(lines[1].contains(" why=pacing(8.3ms)"), "\(lines[1])")
}

/// 1.2 — a key arriving at a dirty window names `needsRedraw`. Mutation: the reason checks swapped so `pacing` wins.
@Test @MainActor func aKeyAtADirtyWindowNamesNeedsRedraw() throws {
    let rig = try WhyRig()
    rig.advance(2)
    rig.window.window.setNeedsRedraw()
    rig.type("a"); rig.release("a"); rig.window.tick(); rig.settle()
    #expect(rig.textLines.first?.contains(" why=needsRedraw") == true, "\(rig.lines)")
}

/// 1.3 — a key while a scroll indicator fades names `animations`. Mutation: the `animations` check removed.
@Test @MainActor func aKeyWhileAnAnimationRunsNamesAnimations() throws {
    let rig = try WhyRig {
        ScrollView(.vertical) {
            VStack(spacing: 0) { ForEach(Array(0..<40), id: \.self) { _ in Box().frame(width: Pixels(100), height: Pixels(20)) } }
        }.frame(width: Pixels(100), height: Pixels(100))
    }
    rig.window.scroll(at: pt(200, 150), byDeltaX: 0, deltaY: -500)
    rig.window.tick(); rig.settle()
    #expect(rig.window.window.hasActiveAnimations)
    rig.advance(2); rig.type("a"); rig.release("a"); rig.window.tick(); rig.settle()
    #expect(rig.textLines.first?.contains(" why=animations") == true, "\(rig.lines)")
}

/// 1.4 — a key while a tooltip's timer is pending names `timer`. Mutation: the `timer` check removed.
@Test @MainActor func aKeyWhileATooltipIsPendingNamesTimer() throws {
    let rig = try WhyRig { Box().frame(width: Pixels(100), height: Pixels(50)).background(.accent).help("Tip") }
    rig.window.hover(at: pt(200, 150))
    rig.window.tick(); rig.settle()
    rig.advance(2); rig.type("a"); rig.release("a"); rig.window.tick(); rig.settle()
    #expect(rig.textLines.first?.contains(" why=timer") == true, "\(rig.lines)")
}

private struct SendsInputWhileBuilding: Component {
    let fire: @MainActor () -> Void
    var content: some ElementGroup {
        let _ = fire()
        Box().frame(width: Pixels(2), height: Pixels(2))
    }
}

/// 1.5 — a key that arrives inside a frame names `drawing`. Mutation: the `drawing` check removed.
@Test @MainActor func aKeyInsideAFrameNamesDrawing() throws {
    var armed = false
    var rig: WhyRig?
    rig = try WhyRig { SendsInputWhileBuilding { if armed { armed = false; rig?.type("z") } } }
    let r = try #require(rig)
    armed = true
    r.advance(2)
    r.window.window.setNeedsRedraw()
    r.window.tick(); r.window.tick(); r.settle()
    #expect(r.textLines.contains { $0.contains(" why=drawing") }, "\(r.lines)")
}

/// 1.6 — `why=` is only written while a trace is on and never changes the earlier columns: the same paced key's
/// line minus its trailing fields equals the old format. Mutation: the trailer inserted before `total`.
@Test @MainActor func theTrailingFieldsFollowEveryEarlierColumn() throws {
    let rig = try WhyRig()
    rig.advance(2); rig.type("a"); rig.release("a"); rig.window.tick(); rig.settle()
    rig.advance(0.5); rig.type("b"); rig.release("b"); rig.window.tick(); rig.settle()
    let line = try #require(rig.textLines.last)
    let head = try #require(line.range(of: " why="))
    let columns = line[..<head.lowerBound].components(separatedBy: " | ")
    #expect(columns.count == 3, "\(line)")   // `metalui-latency idx kind n`, the nine stage columns, `total frames`
    #expect(columns[0].hasPrefix("metalui-latency "))
}

/// 2.1 — a state write the last frame read names `observation`, with a count. Mutation: `markDirtyFromObservation`
/// calling the untagged `setNeedsRedraw()`.
@Test @MainActor func anObservedWriteIsTaggedObservation() async throws {
    let observed = WhyObserved()
    let rig = try WhyRig { Text("\(observed.label)") }
    rig.timing.tracesAllFrames = true
    observed.label = 1
    await rsSettle()   // Linux and Windows: the observation hop lands before the tick
    rig.window.tick(); rig.settle()
    let tick = try #require(rig.lines.last { $0.contains(" tick ") || $0.contains(" frame ") })
    #expect(tick.contains(" dirty=observation/1"), "\(tick)")
}

/// 2.2 — what an input's handler dirties is `input`, with the count of dirtyings. Mutation: the handler's context
/// not set.
@Test @MainActor func anInputsDirtyingIsTaggedInputAndCounted() throws {
    let rig = try WhyRig()
    rig.advance(0.5); rig.type("a"); rig.release("a"); rig.window.tick(); rig.settle()
    let line = try #require(rig.textLines.first)
    #expect(line.contains(" dirty=input/"), "\(line)")
}

/// 2.3 — a bare `setNeedsRedraw()` is `explicit`. Mutation: the default context `input`.
@Test @MainActor func aBareSetNeedsRedrawIsTaggedExplicit() throws {
    let rig = try WhyRig()
    rig.timing.tracesAllFrames = true
    rig.window.window.setNeedsRedraw(); rig.window.window.setNeedsRedraw()
    rig.window.tick(); rig.settle()
    let line = try #require(rig.lines.last)
    #expect(line.contains(" dirty=explicit@FrameTimingWhyTests.swift:"), "\(line)")
    #expect(line.hasSuffix("/2") || line.contains("/2 "), "\(line)")
}

/// 2.4 (`FP-R`) — an untagged call names its file and line, the first call's. Mutations: the site not stored (no `@`);
/// the last call's kept instead of the first's; the full `#fileID` printed (a `/` inside the field).
@Test @MainActor func anExplicitDirtyingNamesItsCallSite() throws {
    let rig = try WhyRig()
    rig.timing.tracesAllFrames = true
    let first: UInt = #line + 1
    rig.window.window.setNeedsRedraw()
    rig.window.window.setNeedsRedraw()
    rig.window.tick(); rig.settle()
    let line = try #require(rig.lines.last)
    #expect(line.contains(" dirty=explicit@FrameTimingWhyTests.swift:\(first)/2"), "\(line)")
}

@MainActor private final class WhyBinding { var width: Binding<Float>? }
private struct WhyStateBox: Component {
    let holder: WhyBinding
    @State var width: Float = 20
    var content: some ElementGroup {
        let _ = holder.width = $width
        Box().frame(width: Pixels(width), height: Pixels(10))
    }
}

/// 2.5 (`FP-R`, `FP-S`) — a `@State` write is `state`, not `explicit`, and names its component and property.
/// Mutations: the table's write hook back to the bare call; the owner not passed by `State`'s setter (no `@`).
@Test @MainActor func aStateWriteIsTaggedState() throws {
    let holder = WhyBinding()
    let rig = try WhyRig { WhyStateBox(holder: holder) }
    rig.timing.tracesAllFrames = true
    holder.width?.wrappedValue = 30
    rig.window.tick(); rig.settle()
    let line = try #require(rig.lines.last)
    #expect(line.contains(" dirty=state@WhyStateBox.width/1"), "\(line)")
}

@MainActor private final class WhyGeoDriver { var size: Binding<Float>? }
private struct WhyGeoBox: Component {
    let driver: WhyGeoDriver
    @State var side: Float = 20
    @State var seen: Float = 0
    var content: some ElementGroup {
        let _ = driver.size = $side
        Box().frame(width: Pixels(side), height: Pixels(10))
            .onGeometryChange(for: Float.self, of: { $0.size.width.value }) { measured in
                if measured != seen { seen = measured }
            }
    }
}

/// 2.6 (`FP-S`) — a write an `onGeometryChange` action makes names the component that owns the written `@State`.
/// Mutation: the label cache not filled (prints `#1`); the owner left at the first writer.
@Test @MainActor func anOnGeometryChangeWriteNamesItsOwner() throws {
    let driver = WhyGeoDriver()
    let rig = try WhyRig { WhyGeoBox(driver: driver) }
    rig.timing.tracesAllFrames = true
    driver.size?.wrappedValue = 40
    rig.window.tick(); rig.settle()   // the frame the driver's write asked for; the action's write lands inside it
    rig.window.window.setNeedsRedraw(); rig.window.tick(); rig.settle()   // the next frame reports who dirtied since
    #expect(rig.lines.contains { $0.contains(" dirty=state@WhyGeoBox.side/") }, "\(rig.lines)")
    #expect(rig.lines.contains { $0.contains(" dirty=state@WhyGeoBox.seen/") }, "\(rig.lines)")
}

/// 2.7 (`FP-S`) — a write with no label is named by ordinal, and an internal writer by its own name. Mutations: the
/// `#` form dropped; the timeline wake's writer not set.
@Test @MainActor func anUnlabelledOwnerPrintsItsOrdinalAndInternalWritersTheirName() throws {
    #expect(DirtyOwner(type: WhyGeoBox.self, ordinal: 9).text == "WhyGeoBox#9")
    #expect(DirtyOwner(named: "TimelineSchedule").text == "TimelineSchedule")
}

/// 3.1 — frames no input caused get a line only with `METALUI_LATENCY_TRACE_ALL`, kind `tick` or `frame`.
/// Mutation: the switch ignored (lines always, or never).
@Test @MainActor func frameLinesWithoutInputAreWrittenOnlyWithTheSubSwitch() throws {
    let rig = try WhyRig()
    rig.window.window.setNeedsRedraw(); rig.window.tick(); rig.settle()
    #expect(rig.lines.isEmpty, "\(rig.lines)")
    rig.timing.tracesAllFrames = true
    rig.window.window.setNeedsRedraw(); rig.window.tick(); rig.settle()
    let line = try #require(rig.lines.last)
    #expect(line.hasPrefix("metalui-latency ") && (line.contains(" tick 0 | ") || line.contains(" frame 0 | ")), "\(line)")
}

/// 4.1 — with no trace the bookkeeping records nothing: a timing with no sink has no dirty source, reason or
/// count on its samples. Mutation: `noteDirty` / `noteDecline` not guarded by `traceSink`.
@Test @MainActor func withNoTraceNothingIsRecorded() throws {
    let holder = WhyBinding()
    let rig = try WhyRig { WhyStateBox(holder: holder) }
    rig.timing.traceSink = nil
    holder.width?.wrappedValue = 31
    rig.advance(0.5); rig.type("a"); rig.release("a"); rig.window.tick()
    let sample = try #require(rig.timing.last)
    #expect(sample.dirtySource == nil)
    #expect(sample.dirtyCount == 0)
    #expect(sample.dirtySite == nil)
    #expect(sample.dirtyOwner == nil)
    #expect(sample.declineReason == nil)
    #expect(!rig.timing.isTracing)
}
