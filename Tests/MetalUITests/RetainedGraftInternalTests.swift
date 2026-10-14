import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUITesting
@testable import MetalUI

// C14b-2 lane 2 (`RK-B`): what only the internal view can see of a graft.

private struct GraftProbeCard: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("probe").frame(width: Pixels(60), height: Pixels(12))
            Box().frame(width: Pixels(20), height: Pixels(6)).background(.accent)
        }
    }
    static func == (l: GraftProbeCard, r: GraftProbeCard) -> Bool { true }
}

/// 17a — **no element phase walks a grafted occurrence** (`RK-B`): a grafted `ComponentLayout` has no payload, and the two
/// places that read a payload (`Component.prepaintGroup`, `paintGroup`, through `withPayload`) are the only ones in `Sources/`: a
/// third caller would meet a nil payload in production. The scan names every caller by file and count; a new one must be
/// added here by someone who has read `RK-B`. Mutation: a `withPayload` call added to any other file reddens it.
@Test func everyReaderOfAComponentPayloadIsNamed() throws {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources")
    let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var callers: [String: Int] = [:]
    for case let url as URL in walker where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        var count = 0
        for line in text.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("///") || trimmed.hasPrefix("//") { continue }
            if line.contains(".withPayload") || line.contains("storage.payload") { count += 1 }
        }
        if count > 0 { callers[url.lastPathComponent] = count }
    }
    // `Component.swift`: `ComponentLayout.content`'s `storage.payload`, `withPayload`'s own check and its body, and the two
    // phases' `withPayload` calls (prepaint and paint).
    #expect(Set(callers.keys) == ["Component.swift"], "every payload reader is in Component.swift: \(callers)")
    #expect(callers["Component.swift"] == 5, "the readers named in RK-B: \(callers)")
}

/// 17b — a grafted layout's payload read traps by name. The child builds a window, takes a real graft record from it, makes the
/// layout a graft makes and reads it. **Red before:** the payload is not optional (no `init(grafted:)`). Mutation: the guard
/// removed from `withPayload` (a force-unwrap trap with no name): the exit test still passes on the exit, reddens on the message.
@Test @MainActor func aGraftedLayoutTrapsByNameWhenAnElementPhaseReadsIt() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            guard let window = try? TestWindow(size: Size(width: Pixels(120), height: Pixels(80)), content: {
                VStack(spacing: 0) { GraftProbeCard().equatable() }
            }) else { return }
            for _ in 0..<5 { window.window.setNeedsRedraw(); window.tick() }
            var record: GraftRecord?
            _ = window.window.testingStoredGraftRecords { record = $0 }
            guard let record else { print("no graft record"); return }
            let layout = ComponentLayout<GraftProbeCard>(grafted: RetainedGraft(record: record))
            layout.withPayload { _ in }
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("(RK-B)"), "the trap names the ruling: \(stderr)")
}

/// 17c — the control: the same layout from a real build has a payload and reads normally (the exit test above passes for any
/// crash otherwise).
@Test @MainActor func anOrdinaryComponentLayoutHasAPayload() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            guard let window = try? TestWindow(size: Size(width: Pixels(120), height: Pixels(80)), content: {
                VStack(spacing: 0) { GraftProbeCard().equatable() }
            }) else { exit(2) }
            for _ in 0..<5 { window.window.setNeedsRedraw(); window.tick() }
        }
    }
}

/// 17d — a graft record is keyed: it exists after the build of an eligible occurrence and not for an ineligible one, and holds
/// the nodes the occurrence registered (the probe card: a stack, a text leaf, a frame, a box, a frame, a background).
@Test @MainActor func aBuiltOccurrenceLeavesAGraftRecordOfItsNodes() throws {
    let window = try TestWindow(size: Size(width: Pixels(120), height: Pixels(80))) {
        VStack(spacing: 0) { GraftProbeCard().equatable() }
    }
    for _ in 0..<5 { window.window.setNeedsRedraw(); window.tick() }
    var nodes = 0, records = 0
    window.window.testingStoredGraftRecords { record in records += 1; nodes = record.segment.nodeCount }
    #expect(records == 1)
    #expect(nodes >= 5, "the segment holds the occurrence's nodes: \(nodes)")
}
