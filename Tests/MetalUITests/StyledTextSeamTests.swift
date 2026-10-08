import CoreText
import Foundation
import Metal
import Testing
import MetalUIDemoContent
import MetalUIPortableText
import MetalUITextSystem
@testable import MetalUI
@testable import MetalUIText

// Rich text, lane 1 — the styled seam (rulings `RT-F`…`RT-J`, spec §4.1).
// Test 1.19 is the must-not-move pin for the plain path's work (`RT-M` item
// 1, moved to lane 1 by `RT-O` item 11).

/// A CoreText system over a cache the test can read, inside a window over the
/// main demo tree (the 1024-point square the fourteen offscreen images use).
@MainActor
private func demoWindow(_ system: CoreTextTextSystem) throws -> Window {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platformWindow = try FakePlatformWindow(device: device, size: 1024)
    return Window(platformWindow: platformWindow, startsDisplayLink: false, textSystem: system) {
        demoContent()
    }
}

/// **1.19** (`RT-M` item 1, `RT-O` item 11). The main demo's first and warm
/// frames do the same shaping work as before rich text: `ShapingCache` misses
/// and lookups equal literals **recorded on `70ed000`'s code** (the merge of
/// PR #51, `feat/rich-text`'s base) before lane 1's first source change — so a
/// lane-1 regression in plain work cannot be baked into the pin. Green on
/// arrival by design. Mutation (lane 1): key the plain cache by `(string,
/// font, width)` without the options — the literals move; (lane 2, re-run):
/// route every `Text` through the styled path.
///
/// Recorded 2026-10-08 with `METALUI_RT_119_MEASURE=1` on `4a47f27` (its
/// `Sources/` byte-identical to `70ed000`'s), three runs alike: first frame
/// 1020 misses, 1544 lookups; warm frame 0 misses, 110 lookups.
@MainActor
@Test func theDemoDoesTheSameTextWorkAsBefore() throws {
    let system = CoreTextTextSystem()
    let window = try demoWindow(system)
    window.drawFrameIfNeeded()
    let firstMisses = system.cache.misses, firstLookups = system.cache.lookups
    try #require(firstMisses > 0, "set up: the demo shaped text")
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let warmMisses = system.cache.misses - firstMisses
    let warmLookups = system.cache.lookups - firstLookups
    if ProcessInfo.processInfo.environment["METALUI_RT_119_MEASURE"] == "1" {
        print("RT 1.19 first misses=\(firstMisses) lookups=\(firstLookups) warm misses=\(warmMisses) lookups=\(warmLookups)")
    }
    #expect(firstMisses == 1020, "first frame misses")
    #expect(firstLookups == 1544, "first frame lookups")
    #expect(warmMisses == 0, "warm frame misses")
    #expect(warmLookups == 110, "warm frame lookups")
    withExtendedLifetime(window) {}
}
