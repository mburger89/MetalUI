import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// `ES-H` (lifting `ES-F` and `ES-G`): a `Self`-returning decoration written after `.coordinateSpace` or after
// `.animation(_:value:)` / `.transaction` configures the scope's own legacy layer, which wraps the scope - so the
// decoration sits OUTSIDE the space or the transaction, SwiftUI's order (probe arms G3 and T3b). Each arm compares
// the decoration written after the scope with the same decoration written before it, which is inside; record 168
// measured that forwarding the decoration onto the content made the two orders read alike.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let linear1 = Animation.linear(duration: 1)

// MARK: - CoordinateSpaceScope

@MainActor private final class SpaceLog {
    var named: [String: Bounds<Pixels>] = [:]
    var global: [String: Bounds<Pixels>] = [:]
}

/// A 40 × 20 leaf reporting its frame in `.global` and in `.named("outer")`, tagged.
@MainActor private func leaf(_ log: SpaceLog, _ tag: String) -> some ProposalElementGroup {
    Rectangle().frame(width: px(40), height: px(20))
        .onGeometryChange(for: [Bounds<Pixels>].self, of: { p in
            [p.frame(in: .global), p.frame(in: .named("outer"))]
        }) { v in
            log.global[tag] = v[0]
            log.named[tag] = v[1]
        }
}

/// A window over `content`, drawn until clean.
@MainActor private func spaceWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws -> Window {
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 300, content: content)
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return window
}

private func near(_ a: Bounds<Pixels>?, _ x: Float, _ y: Float) -> Bool {
    guard let a else { return false }
    return abs(a.origin.x.value - x) < 0.01 && abs(a.origin.y.value - y) < 0.01
}

/// **ES-H** (G3). A legacy `Box` holding the leaf, `.coordinateSpace(.named("outer")).offset(x: 7, y: 9)`: the
/// offset moves the space with the view, so the leaf reads (0, 0) in it while its global frame moves by (7, 9)
/// against the unoffset twin (the content moved). The offset written BEFORE the scope (the control) is inside the
/// space: the leaf reads (7, 9). In a container (the group path) and as the window's root (the `Element` path).
/// Mutation **MES-7**: forward the decoration onto the content (the ES-A shape) - the after arms read (7, 9).
@MainActor @Test func anOffsetAfterACoordinateSpaceMovesTheSpaceWithTheView() throws {
    let log = SpaceLog()
    let window = try spaceWindow {
        Column {
            Box { leaf(log, "after") }.coordinateSpace(.named("outer")).offset(x: px(7), y: px(9))
            Box { leaf(log, "before") }.offset(x: px(7), y: px(9)).coordinateSpace(.named("outer"))
            Box { leaf(log, "plain") }.coordinateSpace(.named("outer"))
        }
    }
    let plain = try #require(log.global["plain"])
    try #require(near(log.named["plain"], 0, 0), "control: the undecorated space: \(log.named)")
    try #require(near(log.named["before"], 7, 9), "control: the offset before is inside the space: \(log.named)")
    #expect(near(log.named["after"], 0, 0), "the offset after moves the space: \(log.named)")
    // `after` sits two rows above `plain` (each row 20 tall); the offset moves it by (7, 9).
    #expect(near(log.global["after"], plain.origin.x.value + 7, plain.origin.y.value - 40 + 9),
            "the content moved: \(log.global)")
    withExtendedLifetime(window) {}

    let rootLog = SpaceLog()
    let root = try spaceWindow { Box { leaf(rootLog, "root") }.coordinateSpace(.named("outer")).offset(x: px(7), y: px(9)) }
    #expect(near(rootLog.named["root"], 0, 0), "as the root: \(rootLog.named)")
    let plainRoot = try spaceWindow { Box { leaf(rootLog, "plainRoot") }.coordinateSpace(.named("outer")) }
    let unmoved = try #require(rootLog.global["plainRoot"])
    #expect(near(rootLog.global["root"], unmoved.origin.x.value + 7, unmoved.origin.y.value + 9),
            "as the root, moved: \(rootLog.global)")
    withExtendedLifetime((root, plainRoot)) {}
}

// MARK: - TransactionScope

@MainActor private func color(_ token: ColorToken) -> Hsla { Theme.light[token] }

@MainActor private func same(_ a: MUIHsla, _ b: Hsla) -> Bool {
    abs(a.h - b.h) < 0.001 && abs(a.s - b.s) < 0.001 && abs(a.l - b.l) < 0.001
}

/// The rects a frame painted at the tile's 60 × 30 size, in emission order.
@MainActor private func tileRects(_ frame: Frame) -> [MUIHsla] {
    frame.scene.rects.filter { abs($0.bounds.size.width - 60) < 0.01 && abs($0.bounds.size.height - 30) < 0.01 }
        .map(\.background)
}

/// **ES-H** (T3b). A 60 × 30 tile whose own background goes surface → accent under `.animation(linear(1), value:)`,
/// with a background written AFTER the scope going surface → accent in the same change: half-way through, the
/// outer background (emitted first, behind) is already accent - outside the transaction, it snaps - while the
/// tile's own background is mid-way (neither colour). Mutation **MES-7** (the naive forwarding): the after
/// background lands on the tile and is one mid-way rect.
@MainActor @Test func aBackgroundAfterAnAnimationSnapsWhileTheContentAnimates() throws {
    func tree(_ flag: Bool) -> some Element {
        Column {
            Box().frame(width: px(60), height: px(30)).background(flag ? .accent : .surface)
                .animation(linear1, value: flag).background(flag ? .accent : .surface)
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    h.frame(0, nil, tree(true))
    let mid = tileRects(h.frame(0.5, nil, tree(true)))
    try #require(mid.count == 2, "two backgrounds, outer then inner: \(mid)")
    #expect(same(mid[0], color(.accent)), "the outer background snapped: \(mid[0])")
    #expect(!same(mid[1], color(.accent)) && !same(mid[1], color(.surface)), "the inner is mid-way: \(mid[1])")
    let end = tileRects(h.frame(2, nil, tree(true)))
    #expect(end.count == 2 && end.allSatisfy { same($0, color(.accent)) }, "settled: \(end)")
}

/// **ES-H.** `.transaction { $0.animation = linear(1) }` animates the tile's own background and not one written
/// after it, the same split.
@MainActor @Test func aBackgroundAfterATransactionIsOutsideIt() throws {
    func tree(_ flag: Bool) -> some Element {
        Column {
            Box().frame(width: px(60), height: px(30)).background(flag ? .accent : .surface)
                .transaction { $0.animation = linear1 }.background(flag ? .accent : .surface)
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    h.frame(0, nil, tree(true))
    let mid = tileRects(h.frame(0.5, nil, tree(true)))
    try #require(mid.count == 2, "\(mid)")
    #expect(same(mid[0], color(.accent)), "the outer background snapped: \(mid[0])")
    #expect(!same(mid[1], color(.accent)) && !same(mid[1], color(.surface)), "the inner is mid-way: \(mid[1])")
}

/// **ES-H.** The scope as the frame's root still animates its content: undecorated, the tile's background is
/// mid-way half-way through; decorated, the inner is mid-way and the outer snapped.
@MainActor @Test func anAnimationScopeAtTheRootStillAnimates() throws {
    func plain(_ flag: Bool) -> some Element {
        Box().frame(width: px(60), height: px(30)).background(flag ? .accent : .surface).animation(linear1, value: flag)
    }
    let h = TransitionHarness()
    h.frame(0, nil, plain(false))
    h.frame(0, nil, plain(true))
    let mid = tileRects(h.frame(0.5, nil, plain(true)))
    #expect(mid.count == 1 && !same(mid[0], color(.accent)) && !same(mid[0], color(.surface)), "plain root: \(mid)")

    func decorated(_ flag: Bool) -> some Element {
        Box().frame(width: px(60), height: px(30)).background(flag ? .accent : .surface)
            .animation(linear1, value: flag).background(flag ? .accent : .surface)
    }
    let d = TransitionHarness()
    d.frame(0, nil, decorated(false))
    d.frame(0, nil, decorated(true))
    let dmid = tileRects(d.frame(0.5, nil, decorated(true)))
    try #require(dmid.count == 2, "\(dmid)")
    #expect(same(dmid[0], color(.accent)) && !same(dmid[1], color(.accent)), "decorated root: \(dmid)")
}
