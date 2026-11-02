import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// R3-10 item 4 (`LD-B`, `LD-C`, `LD-D`): the Frame-level halves of right-to-left layout. The probe is
// `docs/probes/swiftui-layout-direction.swift`. The window-level pins are `MetalUITestingTests/LayoutDirectionWindowTests.swift`
// and the kernel's `MetalUILayoutTests/LayoutDirectionTests.swift`; the flipped E17 is in `EnvironmentTests.swift`.

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private func frame(_ width: Float = 100, _ height: Float = 10) -> Frame {
    Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: 1, stateTable: StateTable(), theme: .light)
}

/// **LD-B.** The window's root environment mirrors without a writer: a `Frame` whose `rootEnvironment` reads right-to-left
/// places the 10 and 20 wide children at 90 and 70 (probe A1), one whose root is left-to-right at 0 and 10, and the flag
/// the kernel registers under is the environment's, not left set after the frame. Mutation: the `rootEnvironment` setter
/// not routing through `environmentTop`'s `didSet` (assigning `storedRootEnvironment` alone) reddens the right-to-left row.
@Test @MainActor func aRightToLeftRootEnvironmentMirrorsWithoutAWriter() throws {
    func positions(_ direction: LayoutDirection) throws -> [Float] {
        let f = frame()
        var environment = f.rootEnvironment
        environment.layoutDirection = direction
        f.rootEnvironment = environment
        var root = ZStack {
            HStack(spacing: px(0)) {
                Rectangle(width: px(10), height: px(10))
                Rectangle(width: px(20), height: px(10))
            }.frame(width: px(100), alignment: .leading)
        }
        f.render(&root)
        let rects = f.finalizedScene().rects
        let ten = try #require(rects.first { $0.bounds.size.width == 10 })
        let twenty = try #require(rects.first { $0.bounds.size.width == 20 })
        return [ten.bounds.origin.x, twenty.bounds.origin.x]
    }
    #expect(try positions(.leftToRight) == [0, 10])
    #expect(try positions(.rightToLeft) == [90, 70])
}

/// **LD-C.** The effect map under a mirrored site is the conjugation by the reflection about the rect's centre line:
/// an offset's x negates, a scale's anchor x becomes `1 - x` (factors stand), a rotation's angle negates and its anchor
/// mirrors (probe P1/P2). The left-to-right figures are the separating arms. Rect 80...100 x 0...10: the leading anchor of
/// a mirrored effect is its right edge, x = 100, y = 5.
/// Mutation: `mirroredSpec` returning `self` reddens every right-to-left row; negating the angle only reddens the rotation.
@Test @MainActor func aMirroredEffectIsTheConjugateOfTheLeftToRightOne() {
    let rect = Bounds(origin: Point(x: px(80), y: px(0)), size: Size(width: px(20), height: px(10)))
    func mapped(_ effect: RenderEffectSpec, mirrored: Bool, _ x: Double, _ y: Double) -> (x: Double, y: Double) {
        effect.affine(in: rect, mirrored: mirrored).apply(x, y)
    }
    // Offset: +10 moves right left-to-right, left mirrored.
    let offset = RenderEffectSpec.offset(x: px(10), y: px(3))
    #expect(mapped(offset, mirrored: false, 0, 0) == (10, 3))
    #expect(mapped(offset, mirrored: true, 0, 0) == (-10, 3))
    // Scale 2 about the leading anchor: the mirrored anchor is the right edge (100), so the left edge 80 goes to 60.
    let scale = RenderEffectSpec.scale(x: 2, y: 2, anchor: .leading)
    #expect(mapped(scale, mirrored: false, 80, 5) == (80, 5))
    #expect(mapped(scale, mirrored: true, 80, 5) == (60, 5))
    #expect(mapped(scale, mirrored: true, 100, 5) == (100, 5), "the anchor stands")
    // Rotation 90 degrees about the leading anchor: a point 30 from the anchor along the content goes down in both
    // directions, to the left of the anchor when mirrored (probe P2: the ink keeps its rows and swaps its side).
    let rotation = RenderEffectSpec.rotation(.degrees(90), anchor: .leading)
    let ltr = mapped(rotation, mirrored: false, 110, 5)   // 30 right of the left-to-right anchor, x = 80
    #expect(abs(ltr.x - 80) < 1e-9 && abs(ltr.y - 35) < 1e-9, "left-to-right: \(ltr)")
    let rtl = mapped(rotation, mirrored: true, 70, 5)     // 30 left of the mirrored anchor x = 100
    #expect(abs(rtl.x - 100) < 1e-9 && abs(rtl.y - 35) < 1e-9, "right-to-left: \(rtl)")
    // Shadows and blurs have no map.
    #expect(RenderEffectSpec.blur(radius: px(2)).affine(in: rect, mirrored: true).isIdentity)
}

/// **LD-D.** `resolveTextStyle` swaps `.leading` and `.trailing` under a right-to-left environment and leaves `.center`
/// (probe M1-M3); the left-to-right figures are the separating arms. Mutation: `seam(in:)` ignoring the direction.
@Test @MainActor func resolveTextStyleSwapsLeadingAndTrailingUnderRightToLeft() {
    func alignment(_ direction: LayoutDirection, _ requested: TextAlignment) -> TextLineAlignment {
        var environment = EnvironmentValues()
        environment.layoutDirection = direction
        environment.multilineTextAlignment = requested
        return resolveTextStyle(TextStyleRequest(), in: environment).alignment
    }
    #expect(alignment(.leftToRight, .leading) == .leading && alignment(.leftToRight, .trailing) == .trailing)
    #expect(alignment(.rightToLeft, .leading) == .trailing && alignment(.rightToLeft, .trailing) == .leading)
    #expect(alignment(.rightToLeft, .center) == .center && alignment(.leftToRight, .center) == .center)
}
