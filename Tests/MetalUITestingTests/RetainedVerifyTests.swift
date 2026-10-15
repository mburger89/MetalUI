import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// C14b-2 lane 1 (`RK-N`): verify mode over prepaint replay. `METALUI_VERIFY_RETAINED=1` builds a frame that replayed a
// prepaint a second time with every replay off, from the same checkpoint, and compares what both held after the
// root's paint; a difference traps naming the channel. One exit test per channel the ledger holds.

/// The channels a ledger can differ in and the words the trap must carry for each.
let rkVerifyChannels: [(channel: String, word: String)] = [
    ("hitboxes", "hitboxes"), ("tallies", "region tallies"), ("focus", "tab order"),
    ("accessibility", "accessibility records"), ("elementBounds", "element bounds"),
    ("contextMenus", "context menus"), ("pressOnly", "press-only actions"),
]

/// A tree whose single occurrence registers every channel of the ledger: a button (hitbox, focus stop, accessibility
/// record, tally) with a context menu, text, and a hover handler, in a window whose accessibility client is active.
struct RKVerifyCard: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("verify").frame(width: Pixels(80), height: Pixels(14))
            Button("press") {}.frame(width: Pixels(50), height: Pixels(18))
                .contextMenu { Button("item") {} }
                .onHover { _ in }
            // A click target no pointer reaches but an accessibility client can press (`IX-Z`): the press-only registration.
            Button("silent") {}.frame(width: Pixels(50), height: Pixels(18)).allowsHitTesting(false)
        }
    }
    static func == (l: RKVerifyCard, r: RKVerifyCard) -> Bool { true }
}

/// 14 — a verified prepaint replay that differs from a fresh prepaint traps, naming the channel (`RK-N`). The child
/// process sets the variable, warms a window until the occurrence's ledger exists, damages that ledger in one channel
/// and draws the next frame. Mutation: the comparison of that channel removed from `RetainedVerifySnapshot.difference`
/// — the child exits normally and the exit test reddens for that arm.
@Test(.serialized, arguments: rkVerifyChannels) @MainActor
func aVerifiedPrepaintReplayThatDiffersTraps(arm: (channel: String, word: String)) async {
    // An exit test's body captures nothing: the channel travels through the environment the child inherits.
    setTestEnvironment("RK_VERIFY_CHANNEL", arm.channel)
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        setTestEnvironment("METALUI_VERIFY_RETAINED", "1")
        await MainActor.run {
            guard let window = try? TestWindow(size: sz(200, 120), textSystem: harnessTextSystem, content: {
                VStack(spacing: 0) { RKVerifyCard().equatable() }
            }) else { return }
            _ = try? window.accessibilityTree
            for _ in 0..<5 { window.window.setNeedsRedraw(); window.tick() }
            let damaged = window.window.testingCorruptPrepaintLedgers(
                ProcessInfo.processInfo.environment["RK_VERIFY_CHANNEL"] ?? "hitboxes")
            guard damaged > 0 else { print("no ledger to damage"); return }
            window.window.setNeedsRedraw(); window.tick()
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("a replayed prepaint differs from a fresh one: \(arm.word)"), "the trap names \(arm.word): \(stderr)")
}

/// 14b — the control: an undamaged ledger under verify mode draws normally (the exit tests above would pass for
/// any crash). The child exits cleanly after the same frames.
@Test @MainActor func anUndamagedVerifiedReplayDrawsNormally() async {
    await #expect(processExitsWith: .success) {
        setTestEnvironment("METALUI_VERIFY_RETAINED", "1")
        await MainActor.run {
            guard let window = try? TestWindow(size: sz(200, 120), textSystem: harnessTextSystem, content: {
                VStack(spacing: 0) { RKVerifyCard().equatable() }
            }) else { exit(2) }
            _ = try? window.accessibilityTree
            for _ in 0..<8 { window.window.setNeedsRedraw(); window.tick() }
        }
    }
}
