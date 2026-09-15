import Foundation
import Metal
import Testing
import MetalUICore
import MetalUILayout
import MetalUIRender
import MetalUIShaderTypes
@testable import MetalUI

// The integration of plan tasks 3, 9 and 12 (`feat/modifier-composition`,
// `feat/environment`, `feat/ax-bridge`): behaviour that belongs to no single
// track because it exists only where two of them meet. Each test names the
// merge obligation it discharges and is recorded, with its mutations, in the
// "Integration" section of the record file of the track that owed it.
//
// **This file imports `Metal`, so it must declare no `Dimension`-typed
// fixture** (`Fakes.swift`'s note on `AnimationTests.swift`).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func hsla(_ c: MUIHsla) -> Hsla { Hsla(h: c.h, s: c.s, l: c.l, a: c.a) }

@MainActor
private func click(_ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

@MainActor
private final class TapLog {
    var taps = 0
}

// MARK: - EV-X on the proposal path (environment EV-W item 1, last bullet)

/// **A proposal modifier written after an environment scope sits outside it**,
/// as a legacy frame layer does (`aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`'s
/// after arm) and as SwiftUI's does (probe `swiftui-disabled-ancestor-and-order.swift`
/// O2, O3, O6 — not re-probed here; this test measures MetalUI only).
///
/// The environment track left this unmeasured: over proposal content
/// `.padding(_:)` compiles after a scope, and its side was open (ruling EV-X).
/// Measured at integration, three spellings, each with a **disagreeing**
/// spelling that moves the scope outermost, so the arm is shown to tell inside
/// from outside rather than read light everywhere:
///
/// - `.theme(.dark).padding(1).background(.surface)`: the 13pt rectangle
///   paints dark, the 15pt background (the padding's size) light;
/// - `.theme(.dark).frame(minWidth: 22, maxWidth: 22).background(.surface)`: the
///   20pt rectangle dark, the 22pt background light;
/// - `.disabled(true).padding(0).onTap {}` fires; `.onTap {}.disabled(true)`
///   does not.
@MainActor
@Test func aProposalModifierWrittenAfterAScopeSitsOutsideIt() throws {
    let f = Frame(contentSize: Size(width: px(300), height: px(50)), scaleFactor: 1, theme: .light)
    var root = HStack(spacing: px(2)) {
        Rectangle(width: px(13), height: px(10), color: .surface)
            .theme(.dark).padding(Edges(all: px(1))).background(.surface)
        Rectangle(width: px(16), height: px(10), color: .surface)
            .padding(Edges(all: px(1))).background(.surface).theme(.dark)
        Rectangle(width: px(20), height: px(10), color: .surface)
            .theme(.dark).frame(minWidth: px(22), maxWidth: px(22)).background(.surface)
        Rectangle(width: px(24), height: px(10), color: .surface)
            .frame(minWidth: px(26), maxWidth: px(26)).background(.surface).theme(.dark)
    }
    f.render(&root)
    let rects = f.finalizedScene().rects
    func colour(_ width: Float) throws -> Hsla {
        hsla(try #require(rects.first { $0.bounds.size.width == width },
                          "no rect \(width) wide in \(rects.map(\.bounds.size.width))").background)
    }
    try #require(Theme.dark.surface != Theme.light.surface)

    #expect(try colour(13) == Theme.dark.surface)
    #expect(try colour(15) == Theme.light.surface, "a proposal padding written after a scope sits outside it")
    #expect(try colour(16) == Theme.dark.surface)
    #expect(try colour(18) == Theme.dark.surface, "the disagreeing spelling: the scope written last")

    #expect(try colour(20) == Theme.dark.surface)
    #expect(try colour(22) == Theme.light.surface, "a flexible frame written after a scope sits outside it")
    #expect(try colour(24) == Theme.dark.surface)
    #expect(try colour(26) == Theme.dark.surface, "the disagreeing spelling: the scope written last")

    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    func taps<Root: Element>(_ content: @escaping @MainActor (TapLog) -> Root) throws -> Int {
        let log = TapLog()
        let (window, platform) = try makeFakeWindow(device: device, size: 100) { content(log) }
        window.drawFrameIfNeeded()
        click(platform, at: pt(50, 50))
        return log.taps
    }
    let after = try taps { log in
        HStack {
            Rectangle(width: px(100), height: px(100))
                .disabled(true).padding(Edges(all: px(0))).onTap { log.taps += 1 }
        }
    }
    let before = try taps { log in
        HStack {
            Rectangle(width: px(100), height: px(100))
                .padding(Edges(all: px(0))).onTap { log.taps += 1 }.disabled(true)
        }
    }
    #expect(after == 1, "an onTap written after .disabled sits outside it and must fire")
    #expect(before == 0, "the disagreeing spelling: .disabled written last suppresses the tap")
}
