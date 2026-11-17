import Dispatch
import Foundation
import Testing
@testable import MetalUITerminal

/// `TerminalSnapshotSource` on a private serial queue. Every wait is `queue.sync {}` (the queue drains in order)
/// or a bounded semaphore; nothing sleeps.
@Suite struct SnapshotSourceTests {
    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T
        init(_ value: T) { self.value = value }
        func with<R>(_ body: (inout T) -> R) -> R { lock.withLock { body(&value) } }
    }

    private func make(cols: Int = 20, rows: Int = 6) -> (TerminalSnapshotSource, DispatchQueue) {
        let queue = DispatchQueue(label: "terminal.source.test")
        return (TerminalSnapshotSource(emulator: TerminalEmulator(cols: cols, rows: rows), queue: queue), queue)
    }

    private func feed(_ source: TerminalSnapshotSource, _ text: String) {
        Array(text.utf8).withUnsafeBytes { source.feed($0) }
    }

    @Test func aTenMegabyteFloodCostsOneWakeAndOneTake() throws {
        let (source, queue) = make(cols: 80, rows: 24)
        let wakes = Box(0)
        source.onWake = { wakes.with { $0 += 1 } }
        let line = Array("the quick brown fox jumps over the lazy dog 0123456789\r\n".utf8)
        var chunk: [UInt8] = []
        while chunk.count < 64 * 1024 { chunk += line }
        let chunks = (10 * 1024 * 1024) / chunk.count
        for _ in 0..<chunks { chunk.withUnsafeBytes { source.feed($0) } }
        queue.sync {}
        #expect(wakes.with { $0 } == 1)
        let stats = source.statistics
        #expect(stats.publishes == chunks && stats.wakes == 1 && stats.takes == 0)
        let snapshot = try #require(source.takeSnapshot())
        #expect(source.statistics.takes == 1)
        #expect(snapshot.isFullFrame && snapshot.damagedRows.count == 24)
        #expect(snapshot.damagedRows.map(\.index) == Array(0..<24))
        #expect(source.takeSnapshot() == nil)
        // A take re-arms the wake: the next feed wakes the view once more.
        feed(source, "x")
        queue.sync {}
        #expect(wakes.with { $0 } == 2)
        let next = try #require(source.takeSnapshot())
        #expect(!next.isFullFrame && next.damagedRows.map(\.index).count == 1)
    }

    @Test func thePendingSnapshotMergesTheDamageOfEveryPublish() throws {
        let (source, queue) = make()
        feed(source, "top")
        queue.sync {}
        _ = try #require(source.takeSnapshot())
        feed(source, "\u{1B}[3;1Hmid")
        feed(source, "\u{1B}[5;1Hlow")
        feed(source, "\u{1B}[3;1HMID")
        queue.sync {}
        let merged = try #require(source.takeSnapshot())
        #expect(!merged.isFullFrame)
        #expect(merged.damagedRows.map(\.index) == [2, 4])
        #expect(merged.damagedRows[0].row.text == "MID" && merged.damagedRows[1].row.text == "low")
        #expect(merged.cursor.row == 2 && merged.cursor.col == 3)
        let versionAfter = merged.version
        feed(source, "!")
        queue.sync {}
        #expect(try #require(source.takeSnapshot()).version > versionAfter)
    }

    @Test func aFullFramePublishedBeforeATakeStaysFullWhenLaterPublishesAreNot() throws {
        let (source, queue) = make()
        feed(source, "a")
        feed(source, "b")
        queue.sync {}
        let snapshot = try #require(source.takeSnapshot())
        #expect(snapshot.isFullFrame && snapshot.damagedRows.count == 6)
        #expect(snapshot.damagedRows[0].row.text == "ab")
    }

    @Test func untouchedRowsKeepTheirStorageAcrossTakes() throws {
        let (source, queue) = make()
        feed(source, "keep\r\nchange")
        queue.sync {}
        let first = try #require(source.takeSnapshot())
        let kept = first.damagedRows[0].row.storageAddress
        feed(source, "\u{1B}[2;1Hmore")
        queue.sync {}
        let second = try #require(source.takeSnapshot())
        #expect(second.damagedRows.map(\.index) == [1])
        let again = Box<UnsafeRawPointer?>(nil)
        source.perform { e in again.with { $0 = e.screen[0].storageAddress } }
        queue.sync {}
        #expect(again.with { $0 } == kept && kept != nil)
    }

    @Test func repliesGoToOnReplyOnTheQueueAndNotToOnEvents() async throws {
        let (source, queue) = make()
        let key = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: key, value: true)
        let replies = Box<[[UInt8]]>([])
        let onQueue = Box(true)
        source.onReply = { bytes in
            replies.with { $0.append(bytes) }
            if DispatchQueue.getSpecific(key: key) != true { onQueue.with { $0 = false } }
        }
        let hops = Box<[@Sendable () -> Void]>([])
        source.eventHop = { block in hops.with { $0.append(block) } }
        let received = Box<[TerminalEvent]>([])
        await MainActor.run { source.onEvents = { events in received.with { $0 += events } } }
        feed(source, "\u{1B}[c\u{07}\u{1B}[5n\u{1B}]0;t\u{07}")
        queue.sync {}
        #expect(replies.with { $0 } == [Array("\u{1B}[?62;22c".utf8), Array("\u{1B}[0n".utf8)])
        #expect(onQueue.with { $0 })
        let block = try #require(hops.with { $0.first })
        await MainActor.run { block() }
        #expect(received.with { $0 } == [.bell, .title("t")])
    }

    @Test func eventsCoalesceIntoOneDeliveryPerHop() async throws {
        let (source, queue) = make()
        let hops = Box<[@Sendable () -> Void]>([])
        source.eventHop = { block in hops.with { $0.append(block) } }
        let batches = Box<[[TerminalEvent]]>([])
        await MainActor.run { source.onEvents = { events in batches.with { $0.append(events) } } }
        for i in 0..<100 { feed(source, "\u{1B}]2;t\(i)\u{07}") }
        queue.sync {}
        #expect(hops.with { $0.count } == 1)
        #expect(batches.with { $0.isEmpty })
        let first = try #require(hops.with { $0.first })
        await MainActor.run { first() }
        #expect(batches.with { $0.count } == 1)
        #expect(batches.with { $0[0] } == (0..<100).map { .title("t\($0)") })
        // Delivered: the next event schedules a new hop.
        feed(source, "\u{07}")
        queue.sync {}
        #expect(hops.with { $0.count } == 2)
        let second = try #require(hops.with { $0.last })
        await MainActor.run { second() }
        #expect(batches.with { $0 } .last == [.bell])
        #expect(source.statistics.eventDeliveries == 2)
    }

    @Test func aNewerResizeReplacesAPendingOne() throws {
        let (source, queue) = make()
        let sizes = Box<[TerminalSize]>([])
        source.resizeHandler = { _, size in sizes.with { $0.append(size) } }
        let gate = DispatchSemaphore(value: 0)
        queue.async { _ = gate.wait(timeout: .now() + 10) }
        for n in 3...9 { source.resize(TerminalSize(cols: n * 10, rows: n)) }
        gate.signal()
        queue.sync {}
        #expect(sizes.with { $0 } == [TerminalSize(cols: 90, rows: 9)])
        source.resize(TerminalSize(cols: 5, rows: 5))
        queue.sync {}
        #expect(sizes.with { $0 }.last == TerminalSize(cols: 5, rows: 5) && sizes.with { $0.count } == 2)
    }

    @Test func performRunsOnTheQueueAndWakesTheView() throws {
        let (source, queue) = make()
        let wakes = Box(0)
        source.onWake = { wakes.with { $0 += 1 } }
        let text = Box<String?>(nil)
        source.perform { e in
            e.feed("hello")
            text.with { $0 = e.rowText(e.firstRow) }
        }
        queue.sync {}
        #expect(text.with { $0 } == "hello" && wakes.with { $0 } == 1)
        #expect(try #require(source.takeSnapshot()).damagedRows[0].row.text == "hello")
    }
}
