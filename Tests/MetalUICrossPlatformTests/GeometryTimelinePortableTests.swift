import Testing
import Foundation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Key and focus scoping, lane B — the portable copies of B1, B3, T1 and T4
// (spec §5.2 T13), over `PortableFakeWindow`, so Linux and Windows CI run the
// geometry drain and the timeline store. Same scripts and mutations as
// `GeometryChangeTests` and `TimelineViewTests` in `MetalUITests`. No test
// sleeps: `simulateResize(to:)` and `simulateTick(timestamp:)` drive them.

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private final class PGLog {
    var entries: [String] = []
    var dates: [Double] = []
    var distinct: [Double] {
        var seen: [Double] = []
        for d in dates where seen.last != d { seen.append(d) }
        return seen
    }
}

@MainActor private func pgWidth(_ window: Window, height: Float) -> Float? {
    let matches = window.lastScene.rects.filter { $0.bounds.size.height == height }
    return matches.count == 1 ? matches[0].bounds.size.width : nil
}

/// A recording leaf: notes the context's date, answers a 10 × 9 rectangle.
@MainActor private func pgLeaf(_ context: TimelineViewDefaultContext, _ log: PGLog) -> some ProposalElementGroup {
    log.dates.append(context.date.timeIntervalSinceReferenceDate)
    return Rectangle().frame(width: px(10), height: px(9))
}

private func near(_ a: [Double], _ b: [Double]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 }
}

/// B3's resizer: a label (7 tall) a quarter of the greedy area's width.
private struct PGResizer: Component {
    @State var seen: Float = 1
    var content: some ElementGroup {
        Column {
            Box().frame(width: px(seen), height: px(7)).background(.accent)
            Box().frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: Float.self, of: { $0.size.width.value }) { seen = $0 / 4 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// **T13/B1** (portable, G1). The initial value is reported once, before
/// `onAppear`.
@MainActor
@Test func portableTheInitialGeometryIsReportedBeforeOnAppear() throws {
    let log = PGLog()
    let (window, _) = try makePortableWindow {
        Column {
            Box().frame(width: px(20), height: px(10))
                .onGeometryChange(for: Float.self, of: { $0.size.width.value }) { log.entries.append("g:\(Int($0))") }
                .onAppear { log.entries.append("appear") }
        }
    }
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    #expect(log.entries == ["g:20", "appear"], "\(log.entries)")
}

/// **T13/B3** (portable, `KF-J` item 4). A resize is reported in the frame
/// presenting it.
@MainActor
@Test func portableAResizeIsReportedInTheFramePresentingIt() throws {
    let (window, platform) = try makePortableWindow(size: 200) { Box { PGResizer() }.frame(maxWidth: .infinity, maxHeight: .infinity) }
    window.drawFrameIfNeeded()
    #expect(pgWidth(window, height: 7) == 50)
    platform.simulateResize(to: Size(width: px(320), height: px(200)))
    window.drawFrameIfNeeded()
    #expect(pgWidth(window, height: 7) == 80)
}

/// **T13/T1** (portable, T1). An animation timeline rebuilds every tick with
/// the frame's date and keeps the link running.
@MainActor
@Test func portableAnAnimationTimelineRebuildsEveryTick() throws {
    let log = PGLog()
    let (window, platform) = try makePortableWindow(startsDisplayLink: true) {
        HStack {
            TimelineView(.animation) { pgLeaf($0, log) }
        }
    }
    window.animationStore.timeline.clockOffset = 0
    window.animationStore.timeline.scheduler = { _, _ in {} }
    let pauses = window.pausesEntered
    for t in [0.0, 1.0 / 60, 2.0 / 60] { platform.simulateTick(timestamp: t) }
    #expect(near(log.distinct, [0, 1.0 / 60, 2.0 / 60]), "\(log.dates)")
    #expect(window.pausesEntered == pauses)
}

/// **T13/T4** (portable, T4). A periodic timeline shows the schedule's entry,
/// not the clock: 0.30 at tick 0.37.
@MainActor
@Test func portableAPeriodicTimelineReportsTheEntry() throws {
    let log = PGLog()
    let (window, platform) = try makePortableWindow(startsDisplayLink: true) {
        HStack {
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 0.1)) { pgLeaf($0, log) }
        }
    }
    window.animationStore.timeline.clockOffset = 0
    window.animationStore.timeline.scheduler = { _, _ in {} }
    platform.simulateTick(timestamp: 0)
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 0.37)
    #expect(near(log.distinct, [0, 0.1 * 3]), "\(log.dates)")
}
