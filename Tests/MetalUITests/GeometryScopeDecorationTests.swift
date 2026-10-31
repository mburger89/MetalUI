import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// `ES-J` (lifting `ES-B`): a `Self`-returning decoration written after `.onGeometryChange` configures the scope's
// own legacy layer (`ES-H`'s mechanism), which wraps the scope - so the decoration sits OUTSIDE the measured
// geometry: it does not change the size reported, and an `.offset` after it moves the reported global frame
// (SwiftUI's G4a, `docs/probes/swiftui-key-focus.swift`: `x:0` then `x:10`). Forwarding the decoration onto the
// content opened its offset after the scope had noted, so the global frame did not move.

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private final class GeoLog {
    var frames: [String: Bounds<Pixels>] = [:]
}

/// A 50 × 50 tile reporting its global frame (size and origin), tagged.
@MainActor private func tile(_ log: GeoLog, _ tag: String) -> GeometryChangeScope<ModifiedElement<Box<EmptyGroup>>> {
    Box().frame(width: px(50), height: px(50))
        .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .global) }) { log.frames[tag] = $0 }
}

@MainActor private func geoWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws -> Window {
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 300, content: content)
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return window
}

private func origin(_ b: Bounds<Pixels>?) -> (Float, Float)? {
    b.map { ($0.origin.x.value, $0.origin.y.value) }
}

/// **ES-J** (G4a). One tile per window, at the same place: `.offset(x: 10)` after `.onGeometryChange`, the same
/// offset before it (the control: an effect inside the measured content is not in its frame), and none. The after
/// tile's global frame is 10 right of the plain one; the before tile's is not moved; all are 50 × 50. Mutation
/// **MES-9** (the naive forwarding): the after tile reads unmoved.
@MainActor @Test func anOffsetAfterOnGeometryChangeMovesTheReportedFrame() throws {
    let log = GeoLog()
    let w1 = try geoWindow { Column { tile(log, "after").offset(x: px(10)) } }
    let w2 = try geoWindow { Column { tile(log, "plain") } }
    let w3 = try geoWindow {
        Column {
            Box().frame(width: px(50), height: px(50)).offset(x: px(10))
                .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .global) }) { log.frames["before"] = $0 }
        }
    }
    let after = try #require(log.frames["after"])
    let plain = try #require(log.frames["plain"])
    let before = try #require(log.frames["before"])
    try #require(before == plain, "control: the offset before is not in the frame: \(log.frames)")
    #expect(abs(after.origin.x.value - (plain.origin.x.value + 10)) < 0.01
            && abs(after.origin.y.value - plain.origin.y.value) < 0.01,
            "the offset after moves the reported frame: \(log.frames)")
    #expect(after.size == plain.size && after.size.width.value == 50, "\(log.frames)")
    withExtendedLifetime((w1, w2, w3)) {}
}

/// **ES-J.** A padding and a background written after `.onGeometryChange` are outside what it measures: the tile
/// reports 50 × 50, where the same padding written before it reports 66 × 66 (the control).
@MainActor @Test func aDecorationAfterOnGeometryChangeDoesNotChangeTheReportedSize() throws {
    let log = GeoLog()
    let window = try geoWindow {
        Column {
            tile(log, "after").padding(px(8)).background(.accent)
            Box().frame(width: px(50), height: px(50)).padding(px(8))
                .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .global) }) { log.frames["before"] = $0 }
            tile(log, "offset-bg").background(.accent).offset(x: px(3))
        }
    }
    let before = try #require(log.frames["before"])
    try #require(before.size.width.value == 66, "control: the padding before is measured: \(log.frames)")
    #expect(log.frames["after"]?.size.width.value == 50 && log.frames["after"]?.size.height.value == 50, "\(log.frames)")
    #expect(log.frames["offset-bg"]?.size.width.value == 50, "\(log.frames)")
    withExtendedLifetime(window) {}
}

/// **ES-J.** As a window's root: undecorated, the scope reports its element's frame; with `.offset(x: 10)` after it
/// the reported frame is 10 right of the undecorated one, size unchanged.
@MainActor @Test func onGeometryChangeAtTheRootReportsAndTakesAnOffsetAfterIt() throws {
    let log = GeoLog()
    let plain = try geoWindow { tile(log, "plain") }
    let moved = try geoWindow { tile(log, "moved").offset(x: px(10)) }
    let p = try #require(log.frames["plain"], "the undecorated root reports")
    let m = try #require(log.frames["moved"])
    #expect(p.size.width.value == 50 && p.size.height.value == 50, "\(p)")
    #expect(abs(m.origin.x.value - (p.origin.x.value + 10)) < 0.01 && abs(m.origin.y.value - p.origin.y.value) < 0.01,
            "\(p) \(m)")
    #expect(m.size == p.size, "\(p) \(m)")
    withExtendedLifetime((plain, moved)) {}
}
